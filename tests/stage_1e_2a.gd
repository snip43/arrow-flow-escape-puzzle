extends SceneTree

const Store := preload("res://game/save_store.gd")
const Fixture := preload("res://tests/save_fixture.gd")
const App := preload("res://scenes/app.tscn")
const E := Store.Economy

# Only the publication acknowledgement or the first readback is faulted.
# Slots and staging files are real. Tests own a different directory every time.
class FaultStore extends Store:
	var fault := ""
	var hide_readback := false
	func publish(tmp: String, path: String) -> bool:
		if fault=="before": return false
		var result := super.publish(tmp,path)
		if fault=="unknown": hide_readback = true
		return false if fault=="lost_ack" else result
	func inspect() -> Dictionary:
		var state := super.inspect()
		if hide_readback:
			hide_readback = false
			state.blocked = IO_ERROR
		return state

var checks := 0
var failures := 0
var app
var store: Store

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	run.call_deferred()

func setup(count: int, coins: int, faultable := false) -> void:
	store = FaultStore.new(Fixture.unique_name()) if faultable else Fixture.make_store()
	check(Fixture.seed_profile(store,count,coins),"seed isolated profile")
	mount()

func mount() -> void:
	if is_instance_valid(app): app.free()
	app = App.instantiate()
	app.store = store
	root.add_child(app)

func clean() -> void:
	if is_instance_valid(app): app.free()
	check(Fixture.clean(store),"clean isolated directory")

func finish() -> void:
	var game = app.game
	for id in app.catalog.get_level(game.level_id).solution:
		if game.model.path_for(id).is_empty(): continue
		var before: int = app.session.coins
		game.move(id)
		check(game.board.locked and before==app.session.coins,"no credit before tail")
		game.animation.custom_step(4)

func block() -> void:
	for id in app.game.model.ids():
		if not app.game.model.can_exit(id):
			app.game.move(id)
			return
	check(false,"expected initial dependency")

func buy() -> void:
	app.buy_hint(app.game.generation,app.game)

func raw(path: String, content: String) -> void:
	var f := FileAccess.open(path,FileAccess.WRITE)
	f.store_string(content)

func legacy(n: int, rev: int) -> String:
	return JSON.stringify({"schema_version":1,"revision":rev,"campaign":{"completed_count":n}})

func wallet_row(n: int, rev: int, balance: String) -> String:
	return '{"schema_version":2,"revision":%d,"campaign":{"completed_count":%d},"wallet":{"coins":%s}}'%[rev,n,balance]

func migration() -> void:
	for n in [0,1,42,100]:
		store = Fixture.make_store()
		DirAccess.make_dir_recursive_absolute(store.directory)
		var a := store.directory.path_join(Store.SLOTS[0])
		var original := legacy(n,37)
		raw(a,original)
		mount()
		check(app.session.completed_count()==n and app.session.coins==50 and store.inspect().revision==37,"v1 mapped without retroactive reward")
		if n>0:
			app.open_level(1)
			finish()
			check(app.session.coins==50 and store.inspect().revision==37,"legacy replay earns nothing")
			app.back()
		if n<100:
			app.play()
			finish()
		else:
			app.open_level(100)
			buy()
		var committed: int = app.session.coins
		check(FileAccess.get_file_as_string(a)==original and store.inspect().revision==38,"v1 bytes retained on promotion")
		mount()
		check(app.session.coins==committed and app.session.completed_count()==mini(n+1,100),"relaunch does not add starter")
		clean()
	store = Fixture.make_store()
	DirAccess.make_dir_recursive_absolute(store.directory)
	var a := store.directory.path_join(Store.SLOTS[0])
	var b := store.directory.path_join(Store.SLOTS[1])
	raw(a,legacy(3,12))
	raw(b,wallet_row(5,10,"75"))
	check(store.restore()==3 and store.last_snapshot.coins==50,"newest v1 beats v2")
	raw(b,wallet_row(4,12,"2"))
	check(store.restore()==3 and store.last_snapshot.coins==50 and store.notice==Store.CONFLICT,"choose one whole conflicting snapshot")
	raw(b,wallet_row(3,12,"2"))
	check(store.restore()==3 and store.last_snapshot.coins==2 and store.notice==Store.CONFLICT,"tie on prefix chooses lower coins")
	raw(b,wallet_row(4,13,"0"))
	check(store.restore()==4 and store.last_snapshot.coins==0,"newest v2")
	for token in ['"1"',"true","null","-1","1.5","1.0000000000000000001","1e-999","1000000001","{}","[]"]:
		raw(b,wallet_row(4,13,token))
		check(store.read_slot(b).state=="invalid" and store.restore()==3 and store.last_snapshot.coins==50,"reject invalid balance "+token)
	for bad in [wallet_row(4,13,"3").replace('"coins":3','"coins":2,"coins":3'),wallet_row(4,13,"3").replace('"coins":3',''),wallet_row(4,13,"3").replace(',"wallet":{"coins":3}',''),wallet_row(4,13,"3").left(-1)+",}"]:
		raw(b,bad)
		check(store.read_slot(b).state=="invalid","malformed wallet")
	raw(b,wallet_row(4,Store.MAX_REVISION-1,"60"))
	mount()
	app.open_level(2)
	buy()
	check(store.inspect().coins==30 and store.spending_blocked and store.notice==Store.REVISION_LIMIT,"final available revision can commit once")
	mount()
	check(app.session.coins==30 and store.spending_blocked and app.menu.get_node("SaveNotice").visible,"exhausted revisions visible on relaunch")
	raw(b,'{"schema_version":3}')
	raw(a,legacy(3,12))
	mount()
	app.open_level(2)
	buy()
	check(store.spending_blocked and app.game.get_node("%Hint").disabled and app.session.coins==50 and FileAccess.get_file_as_string(b)=='{"schema_version":3}',"future is read-only")
	clean()

func rewards() -> void:
	store = Fixture.make_store()
	mount()
	mount()
	check(app.session.coins==50 and app.menu.get_node("Wallet").text=="50 Coins" and store.inspect().revision==0,"fresh twice")
	app.open_selector()
	check(app.selector.get_node("Wallet").text=="50 Coins","selector balance")
	app.open_level(1)
	buy()
	check(app.game.get_node("%Hint").disabled and app.session.coins==50,"tutorial no debit")
	finish()
	check(app.session.coins==55 and store.inspect().count==1 and store.inspect().revision==1,"single tutorial reward")
	app.level_completed(1,app.game)
	check(app.session.coins==55 and store.inspect().revision==1,"duplicate callback")
	app.game.restart()
	finish()
	check(app.game.get_node("Layout/Overlay/Reward").text=="Already cleared" and app.session.coins==55,"replay no credit")
	clean()
	for id in [2,21,61,100]:
		for perfect in [false,true]:
			setup(id-1,50)
			app.play()
			block()
			check(app.game.blocked_moves==1,"real blocker")
			if perfect: app.game.restart()
			finish()
			var base := 5 if id==2 else (10 if id==21 else 15)
			var expected := 50+base+(5 if perfect else 0)
			check(app.session.coins==expected and store.inspect().coins==expected and store.inspect().count==id,"tier payout "+str(id))
			check(app.game.get_node("Layout/Overlay/Reward").text.contains("Perfect")==perfect,"perfect receipt")
			check(app.game.get_node("%Hint").disabled and app.game.get_node("%Next").visible==(id<100),"victory gating")
			clean()
	setup(1,E.LIMIT-2)
	app.play()
	finish()
	check(app.session.coins==E.LIMIT and app.game.get_node("Layout/Overlay/Reward").text=="+2 Coins","cap checked before credit")
	clean()

func touch_button(c: Control) -> void:
	var at := root.get_final_transform()*c.get_global_transform_with_canvas()*(c.size/2)
	for down in [true,false]:
		var e := InputEventScreenTouch.new()
		e.position = at
		e.pressed = down
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		await process_frame

func mouse(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.pressed = down
	root.push_input(e,true)

func click(at: Vector2) -> void:
	mouse(at,true)
	mouse(at,false)

func finger(at: Vector2, index: int, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	root.push_input(event,true)

func gestures() -> void:
	setup(1,60)
	app.play()
	var g = app.game
	var id: String = g.hint_candidate()
	var at: Vector2 = g.board.get_global_transform_with_canvas()*g.board.center(g.model.path_for(id)[0])
	click(g.board.get_global_rect().position+Vector2.ONE)
	finger(at,0,true)
	var drag := InputEventScreenDrag.new()
	drag.position = at+Vector2(100,100)
	root.push_input(drag,true)
	finger(at,0,false)
	finger(at,0,true)
	finger(at,1,true)
	finger(at,1,false)
	finger(at,0,false)
	check(not g.board.locked and g.blocked_moves==0 and not g.used_hint and g.model.ids().size()==g.total,"cancelled gestures and miss leave attempt intact")
	var button: Vector2 = g.get_node("%Hint").get_global_rect().get_center()
	mouse(button,true)
	g.restart()
	mouse(button,false)
	check(app.session.coins==60 and g.board.hinted=="" and store.inspect().revision==1,"old release after restart")
	block()
	var old: int = g.generation
	g.restart()
	g.finish_move(id,old)
	check(g.blocked_moves==0 and g.board.flashed=="" and not g.complete.visible,"stale exit cannot finish a restarted attempt")
	block()
	app.back()
	app.play()
	check(app.game.blocked_moves==0 and app.game.board.flashed=="" and app.session.coins==60,"back during feedback ends attempt")
	g = app.game
	var deadlock := {"A":[Vector2i(0,0),Vector2i(1,0)],"B":[Vector2i(3,0),Vector2i(2,0)]}
	check(g.model.load_level(Vector2i(4,1),deadlock),"test-only blocked board")
	g.attempt_changed.emit()
	buy()
	check(g.get_node("%Hint").disabled and store.inspect().revision==1,"no available arrow cannot spend")
	clean()
	setup(1,25)
	app.play()
	block()
	finish()
	buy()
	check(app.session.coins==30 and app.game.hint_candidate()=="" and store.inspect().revision==2,"empty victory field refuses hint")
	app.game.next_level()
	check(not app.game.get_node("%Hint").disabled and app.game.blocked_moves==0,"reward makes next hint affordable")
	buy()
	check(app.session.coins==0 and app.game.used_hint,"spend exactly earned funds")
	clean()

func free_campaign() -> void:
	store = Fixture.make_store()
	mount()
	app.play()
	for id in range(1,101):
		finish()
		check(app.game.level_id==id and app.session.completed_count()==id and store.inspect().revision==id,"unassisted campaign level %d"%id)
		app.game.next_level()
	check(app.session.coins==1645 and app.game.complete.visible and not app.game.get_node("%Next").visible,"all 100 free completions and exact wallet")
	mount()
	check(app.session.completed_count()==100 and app.session.coins==1645,"full campaign restores")
	clean()

func hints() -> void:
	for balance in [0,29,30,31]:
		setup(1,balance)
		app.play()
		await process_frame
		var g = app.game
		var hint: Button = g.get_node("%Hint")
		var ids: Array = g.model.ids()
		var first: String = g.hint_candidate()
		check(hint.disabled==(balance<30) and g.get_node("Layout/Wallet").text=="%d Coins"%balance,"button reflects wallet")
		if balance==31:
			await touch_button(hint)
		else:
			click(hint.get_global_rect().get_center())
		var paid: bool = balance>=30
		check(app.session.coins==balance-(30 if paid else 0),"viewport input buys once")
		buy()
		check(app.session.coins==balance-(30 if paid else 0) and g.model.ids()==ids and not g.board.locked,"hint purchase is not a move")
		check(g.used_hint==paid and g.board.hinted==(first if paid else "") and store.inspect().revision==(2 if paid else 1),"one confirmed debit")
		if paid:
			check(g.model.can_exit(first),"hint free in current model")
			var other: Array = ids.filter(func(id): return id!=first and g.model.can_exit(id))
			g.move(other[0])
			buy()
			check(g.board.hinted=="" and g.board.locked and g.used_hint,"different exit clears only the highlight")
			g.animation.custom_step(4)
			finish()
			check(app.session.coins==balance-30+5,"hint forfeits perfect")
		clean()
	setup(1,60)
	app.play()
	var g = app.game
	var old: int = g.generation
	buy()
	g.restart()
	app.buy_hint(old,g)
	check(not g.used_hint and g.board.hinted=="" and app.session.coins==30,"restart invalidates old click")
	var id: String = g.hint_candidate()
	click(g.board.get_global_transform_with_canvas()*g.board.center(g.model.path_for(id)[0]))
	check(g.board.locked and app.session.coins==30 and g.blocked_moves==0,"board click only moves arrow")
	g.move("not-an-id")
	buy()
	check(g.get_node("%Hint").disabled and app.session.coins==30,"animation guards")
	g.animation.custom_step(4)
	buy()
	check(g.board.hinted!=id and g.model.can_exit(g.board.hinted) and app.session.coins==0,"live remaining arrow")
	app.back()
	app.buy_hint(old,g)
	check(app.session.coins==0 and not g.is_inside_tree(),"inactive source cannot spend")
	clean()

func faults() -> void:
	setup(1,80,true)
	app.play()
	var base: Dictionary = app.base_snapshot.duplicate()
	store.fault = "before"
	buy()
	check(app.session.coins==80 and store.inspect().coins==80 and not app.game.used_hint and not app.dirty,"pre-publication refusal")
	store.fault = "lost_ack"
	buy()
	buy()
	check(app.session.coins==50 and store.inspect().coins==50 and app.game.used_hint and store.inspect().revision==2,"lost acknowledgement reconciles once")
	var stale := Store.new(store.directory.get_file())
	check(not stale.save(1,80,base) and store.inspect().coins==50,"stale wallet cannot overwrite debit")
	store.fault = "before"
	finish()
	check(app.dirty and app.session.coins==55 and app.session.completed_count()==2 and store.inspect().count==1 and store.inspect().coins==50,"dirty unified victory")
	app.game.next_level()
	buy()
	check(app.game.get_node("%Hint").disabled and app.session.coins==55 and not app.game.used_hint,"dirty blocks spending")
	finish()
	check(app.dirty and app.session.completed_count()==3 and app.session.coins==65,"free play while dirty")
	store.fault = ""
	app.back()
	app.retry_save()
	check(not app.dirty and store.inspect().coins==65 and store.inspect().count==3 and store.inspect().revision==3,"retry latest snapshot once")
	app.play()
	store.fault = "unknown"
	buy()
	check(store.needs_reload and app.session.coins==65 and store.inspect().coins==35 and not app.game.used_hint,"unverifiable readback freezes purchase")
	buy()
	app.retry_save()
	check(store.inspect().revision==4 and not app.game.used_hint,"ambiguous debit never retried")
	store.fault = ""
	mount()
	check(app.session.coins==35 and not store.spending_blocked,"relaunch reconciles published debit")
	clean()

func label_fits(label: Label, icon_width := 0) -> bool:
	var text_size := label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size"))
	return root.get_visible_rect().grow(1).encloses(label.get_global_rect()) and text_size.x+icon_width<=label.size.x+1 and text_size.y<=label.size.y+1

func layouts() -> void:
	for dims in [Vector2i(360,640),Vector2i(405,720),Vector2i(412,915),Vector2i(768,1024),Vector2i(900,600)]:
		setup(98,30,true)
		root.size = dims
		await process_frame
		var wallet: Label = app.menu.get_node("Wallet")
		check(label_fits(wallet,44) and not wallet.get_global_rect().intersects(app.menu.get_node("Title").get_global_rect()),"menu wallet fits")
		app.open_selector()
		wallet = app.selector.get_node("Wallet")
		var title: Label = app.selector.get_node("Title")
		var title_width := title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,title.get_theme_font_size("font_size")).x
		check(label_fits(wallet,44) and title.global_position.x+title_width<wallet.global_position.x,"selector title and wallet fit")
		app.open_level(99)
		await process_frame
		await process_frame
		var g = app.game
		var board: Rect2 = g.board.get_global_rect()
		var hint: Rect2 = g.get_node("%Hint").get_global_rect()
		var restart: Rect2 = g.get_node("%Restart").get_global_rect()
		check(not hint.intersects(board) and not hint.intersects(restart) and root.get_visible_rect().encloses(hint) and (root.get_final_transform()*hint).size.y>=48,"hint physical bounds")
		check(not g.get_node("Layout/Wallet").get_global_rect().intersects(g.get_node("Layout/Brand").get_global_rect()),"wallet avoids wordmark")
		store.fault = "before"
		buy()
		var warning: Label = g.get_node("Layout/SaveNotice")
		check(warning.visible and label_fits(warning) and not warning.get_global_rect().intersects(board) and not warning.get_global_rect().intersects(hint) and g.board.get_global_rect()==board,"purchase failure fits footer")
		store.fault = ""
		buy()
		check(warning.text=="Not enough coins" and label_fits(warning) and label_fits(g.get_node("Layout/Wallet"),44),"lack of funds fits footer")
		block()
		check(board==g.board.get_global_rect() and g.board.hinted!="","stable board with hint and blocked feedback")
		store.fault = "before"
		finish()
		var receipt: Label = g.get_node("Layout/Overlay/Reward")
		check(app.dirty and label_fits(warning) and g.board.get_global_rect()==board and label_fits(receipt),"unsaved victory and wallet fit")
		check(not receipt.get_global_rect().intersects(g.complete.get_global_rect()) and not receipt.get_global_rect().intersects(g.get_node("%Next").get_global_rect()),"receipt clears title and Next")
		clean()

func run() -> void:
	migration()
	rewards()
	await hints()
	gestures()
	free_campaign()
	faults()
	await layouts()
	print("STAGE 1E.2A: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
