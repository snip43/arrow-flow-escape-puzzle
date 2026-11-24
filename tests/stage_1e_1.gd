extends SceneTree

const Store := preload("res://game/save_store.gd")
const Fixture := preload("res://tests/save_fixture.gd")
const Session := preload("res://game/campaign_session.gd")
const App := preload("res://scenes/app.tscn")
# Fault injection at the final boundary, after real staging, flush and readback.
class InterruptedStore extends Store:
	func publish(_tmp: String, _path: String) -> bool:
		return false

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	run.call_deferred()

func put(path: String, content: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)

func row(count: Variant, rev: Variant, version: Variant = 1) -> String:
	return JSON.stringify({"schema_version":version,"revision":rev,"campaign":{"completed_count":count}})

func validation() -> void:
	var s := Fixture.make_store()
	check(s.restore()==0 and s.notice.is_empty() and not DirAccess.dir_exists_absolute(s.directory),"fresh profile read only")
	DirAccess.make_dir_recursive_absolute(s.directory)
	var path := s.directory.path_join(Store.SLOTS[0])
	for bad in [-1,101,2.3,"2",true,null,{},[]]:
		put(path,row(bad,1))
		check(s.read_slot(path).state=="invalid","invalid count "+str(bad))
	for bad in [0,-8,1.2,true,"1",null,Store.MAX_REVISION+1]:
		put(path,row(0,bad))
		check(s.read_slot(path).state=="invalid","invalid revision "+str(bad))
	for bad in [0,1.1,"1",true,null]:
		put(path,row(0,1,bad))
		check(s.read_slot(path).state=="invalid","invalid schema "+str(bad))
	for bad in ["[]","{}","{",row(1,1).left(-2),'{"schema_version":1,"revision":1,"campaign":{}}','{"schema_version":1,"revision":1,"campaign":[]}'," ".repeat(Store.MAX_BYTES)+row(0,1)]:
		put(path,bad)
		check(s.read_slot(path).state=="invalid","reject malformed or oversized record")
	for token in ["1.0000000000000000001","1e-999","2.01","-1e-900"]:
		put(path,'{"campaign":{"completed_count":'+token+'},"schema_version":1,"revision":1}')
		check(s.read_slot(path).state=="invalid","reject rounded fraction "+token)
	put(path,row(0,1).left(-1)+",}")
	check(s.read_slot(path).state=="invalid","reject trailing comma")
	put(path,row(0,1).left(-1)+',"revision":1}')
	check(s.read_slot(path).state=="invalid","reject duplicate keys")
	put(path,'{"schema_version":1e0,"revision":3.00,"campaign":{"completed_count":2.5e1}}')
	check(s.restore()==25,"whole scientific notation")
	for n in [0,100]:
		put(path,row(n,1))
		check(s.restore()==n and s.notice.is_empty(),"valid endpoint")
	put(path,row(3,Store.MAX_REVISION))
	check(not Fixture.seed_profile(s,4) and s.restore()==3,"revision limit preserves active slot")
	var domain := Session.new()
	check(domain.restore(42),"restore continuous prefix")
	for bad in [-1,101,false,"1",0.5]:
		check(not domain.restore(bad) and domain.completed_count()==42,"atomic domain validation")
	check(Session.new().completed_count()==0,"fresh domain independent")
	check(Fixture.clean(s),"clean validation profile")

func recovery() -> void:
	var s := Fixture.make_store()
	var a := s.directory.path_join(Store.SLOTS[0])
	var b := s.directory.path_join(Store.SLOTS[1])
	check(Fixture.seed_profile(s,1) and Fixture.seed_profile(s,2) and Fixture.seed_profile(s,3),"three verified alternating writes")
	check(s.read_slot(a).revision==3 and s.read_slot(b).revision==2,"alternating revisions")
	put(a,"partial revision 3")
	put(a+".tmp",row(99,100))
	check(s.restore()==2 and s.notice==Store.FALLBACK,"fallback ignores newer temp")
	put(b,"corrupt B")
	check(s.restore()==0 and s.notice==Store.CORRUPT,"two corrupt slots")
	check(FileAccess.get_file_as_string(a)=="partial revision 3" and FileAccess.get_file_as_string(b)=="corrupt B","load preserves bytes")
	var archive_a := a+"."+FileAccess.get_sha256(a)+".bak"
	var archive_b := b+"."+FileAccess.get_sha256(b)+".bak"
	put(archive_b,"archive collision")
	check(not Fixture.seed_profile(s,1) and FileAccess.get_file_as_string(b)=="corrupt B" and FileAccess.get_file_as_string(a)=="partial revision 3","archive verification failure preserves both originals")
	DirAccess.remove_absolute(archive_b)
	check(Fixture.seed_profile(s,1) and FileAccess.get_file_as_string(archive_a)=="partial revision 3" and FileAccess.get_file_as_string(archive_b)=="corrupt B","first new progress archives both damaged byte streams")
	put(a,row(8,10))
	put(b,row(6,10))
	check(s.restore()==6 and s.notice==Store.CONFLICT,"equal revisions choose conservative prefix")
	check(Fixture.seed_profile(s,7) and s.restore()==7 and s.inspect().revision==11,"conflict resolved on new progress")
	var newer := '{"schema_version":3,"new_data":"keep"}'
	put(b,newer)
	var old_bytes := FileAccess.get_file_as_bytes(a)
	check(s.restore()==7 and s.notice==Store.FUTURE and not Fixture.seed_profile(s,8),"future schema locks both slots")
	check(FileAccess.get_file_as_bytes(a)==old_bytes and FileAccess.get_file_as_string(b)==newer,"future and previous bytes intact")
	DirAccess.remove_absolute(a)
	check(s.restore()==0 and s.notice==Store.FUTURE and not Fixture.seed_profile(s,1),"future as only slot")
	DirAccess.remove_absolute(b)
	check(s.restore()==0 and s.notice.is_empty(),"temp alone not a commit")
	check(Fixture.clean(s),"clean recovery profile")

func interrupted_publish() -> void:
	var s := Fixture.make_store()
	check(Fixture.seed_profile(s,5) and Fixture.seed_profile(s,6),"prepare two committed slots")
	var a := s.directory.path_join(Store.SLOTS[0])
	var b := s.directory.path_join(Store.SLOTS[1])
	var old_a := FileAccess.get_file_as_bytes(a)
	var old_b := FileAccess.get_file_as_bytes(b)
	var interrupted := InterruptedStore.new(s.directory.get_file())
	check(not Fixture.seed_profile(interrupted,7) and interrupted.read_slot(a+".tmp").count==7,"unpublished staged bytes verified")
	check(FileAccess.get_file_as_bytes(a)==old_a and FileAccess.get_file_as_bytes(b)==old_b,"interrupted publication keeps both originals")
	check(s.restore()==6 and s.inspect().revision==2,"restart ignores interrupted publication")
	check(Fixture.seed_profile(s,7) and s.restore()==7 and s.inspect().revision==3,"next retry succeeds")
	check(Fixture.clean(s),"clean interruption fixture")

func mount(s: Store) -> Control:
	var app := App.instantiate()
	app.store = s
	root.add_child(app)
	return app

func finish(app: Control) -> void:
	var order: Array = app.catalog.get_level(app.game.level_id).solution
	for id in order:
		if app.game.model.path_for(id).is_empty(): continue
		app.game.move(id)
		app.game.animation.custom_step(5)

func integration() -> void:
	var s := Fixture.make_store()
	var app := mount(s)
	check(app.menu.get_node("Play").text=="Play · Level 1" and not s.inspect().revision,"first menu")
	app.play()
	app.game.move("A")
	app.game.move("B")
	app.game.move("D")
	app.game.restart()
	app.game.move("B")
	app.game.animation.custom_step(5)
	var stale = app.game
	app.back()
	app.level_completed(1,stale)
	check(s.inspect().revision==0 and app.session.completed_count()==0,"blocked partial restart back ignored and stale")
	app.play()
	for id in app.catalog.get_level(1).solution:
		app.game.move(id)
		check(s.inspect().revision==0,"wait for tail")
		app.game.animation.custom_step(5)
	check(s.inspect().count==1 and s.inspect().revision==1 and not app.dirty,"immediate victory publication")
	app.level_completed(1,app.game)
	app.game.restart()
	finish(app)
	check(s.inspect().revision==1,"duplicate and replay do not write")
	app.free()
	app = mount(Store.new(s.directory.get_file()))
	app.open_selector()
	check(app.cards[1].get_node("Content/Status").text=="Cleared" and not app.cards[2].disabled and app.cards[3].disabled,"restored selector")
	app.open_level(2)
	# A directory occupying the exact staging filename makes the real write fail.
	var blocked_path := s.directory.path_join("save_b.json.tmp")
	check(DirAccess.make_dir_absolute(blocked_path)==OK,"prepare real staging error")
	finish(app)
	check(app.dirty and app.session.completed_count()==2 and s.inspect().count==1 and s.inspect().revision==1,"failed write keeps previous disk commit and new memory progress")
	check(app.game.get_node("Layout/SaveNotice").is_visible_in_tree(),"visible unsaved status")
	app.back()
	check(app.dirty and app.selector.get_node("SaveNotice").visible,"retry still blocked")
	DirAccess.remove_absolute(blocked_path)
	app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(not app.dirty and app.store.notice.is_empty() and s.inspect().count==2 and s.inspect().revision==2,"pause retry verified")
	app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(s.inspect().revision==2,"clean resume does not write")
	app.free()
	for last in [20,60,99,100]:
		check(Fixture.seed_profile(s,last-1),"seed boundary fixture")
		app = mount(Store.new(s.directory.get_file()))
		check(app.session.next_incomplete()==last and not app.session.can_play(last+1),"restored boundary")
		app.play()
		finish(app)
		check(s.inspect().count==last and app.session.can_play(mini(last+1,100)),"real boundary victory")
		app.free()
	app = mount(Store.new(s.directory.get_file()))
	app.open_selector()
	var all_open := true
	for button in app.cards.values():
		all_open = all_open and not button.disabled
	check(all_open and not app.open_level(101) and app.session.completed_count()==100,"completed campaign restored")
	app.back()
	check(not app.menu.get_node("Play").visible and app.menu.get_node("Levels").text=="Replay levels","replay route")
	app.free()
	check(Fixture.clean(s),"clean integration profile")

func run() -> void:
	validation()
	recovery()
	interrupted_publish()
	integration()
	check(FileAccess.get_sha256("res://levels/data/catalog.json")=="5401de5a357fba34ca8e0c2c03c78a1431dcc46ecf0929ab827416f4255d14ff","catalog checksum")
	print("STAGE 1E.1: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
