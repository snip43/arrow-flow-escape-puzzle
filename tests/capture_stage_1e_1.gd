extends SceneTree

# The PowerShell runner owns a unique profile shared by the two processes.
const Fixture := preload("res://tests/save_fixture.gd")
const Store := preload("res://game/save_store.gd")
const DIR := "res://docs/screenshots/stage_1e_1/"
var store: Store
var app
var capture := false
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func settle() -> void:
	await process_frame
	await process_frame

func mount() -> void:
	if is_instance_valid(app): app.free()
	app = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	app.store = store
	root.add_child(app)

func snap(label: String) -> void:
	if not capture: return
	await settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size()==Vector2i(405,720) and image.save_png(DIR+label+".png")==OK,label)

func win_tutorial() -> void:
	app.play()
	for id in app.catalog.get_level(1).solution:
		app.game.move(id)
		await app.game.animation.finished

func layout(panel: Control, notice_expected: bool) -> void:
	for dims in [Vector2i(360,640),Vector2i(412,915)]:
		root.size = dims
		await settle()
		var warning: Label = panel.get_node("SaveNotice")
		check(warning.is_visible_in_tree()==notice_expected,"notice visibility at "+str(dims))
		if notice_expected:
			var rect := warning.get_global_rect()
			check(root.get_visible_rect().encloses(rect) and rect.size.x>=warning.get_minimum_size().x,"notice fits")
			for button in panel.find_children("*","Button",true,false):
				if button.is_visible_in_tree():
					check(not rect.intersects(button.get_global_rect()),"notice clear of "+button.name)
		else:
			check(root.get_visible_rect().encloses(panel.get_node("Progress").get_global_rect()),"progress fits")
	root.size = Vector2i(405,720)
	await settle()

func write_phase() -> void:
	check(not DirAccess.dir_exists_absolute(store.directory),"unique unused profile")
	mount()
	check(app.session.completed_count()==0 and app.menu.get_node("Play").text=="Play · Level 1","clean launch")
	await layout(app.menu,false)
	await snap("01-fresh")
	await win_tutorial()
	check(app.game.complete.visible and store.inspect().count==1 and store.inspect().revision==1,"commit before leaving game")
	await snap("02-victory-level-1")

func read_phase() -> void:
	mount()
	check(app.session.completed_count()==1 and app.menu.get_node("Play").text=="Continue · Level 2","second process restored")
	await snap("03-relaunch-continue")
	app.open_selector()
	check(app.cards[1].get_node("Content/Status").text=="Cleared" and not app.cards[2].disabled and app.cards[3].disabled,"restored unlocks")
	await snap("04-relaunch-selector")
	check(store.save(100),"completed profile fixture")
	mount()
	check(app.menu.get_node("Levels").text=="Replay levels" and not app.menu.get_node("Play").visible,"restored full campaign")
	await snap("05-completed-campaign")
	for slot in Store.SLOTS:
		var file := FileAccess.open(store.directory.path_join(slot),FileAccess.WRITE)
		file.store_string("truncated")
		file.close()
	mount()
	check(app.session.completed_count()==0 and store.notice==Store.CORRUPT,"recovery notice")
	await layout(app.menu,true)
	await snap("06-recovery-warning")
	app.open_selector()
	await layout(app.selector,true)
	app.back()
	var obstruction := store.directory.path_join("save_a.json.tmp")
	check(DirAccess.make_dir_absolute(obstruction)==OK,"block temporary file")
	await win_tutorial()
	check(app.dirty and app.session.completed_count()==1 and store.notice==Store.UNSAVED,"real write failure")
	await layout(app.game.get_node("Layout"),true)
	await snap("07-save-failed")
	DirAccess.remove_absolute(obstruction)
	app.back()
	check(not app.dirty and store.inspect().count==1,"retry publishes")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()<2 or not Fixture.valid(args[1]):
		push_error("Run with tests/run_stage_1e_1_relaunch.ps1")
		quit(1)
		return
	store = Store.new(args[1])
	capture = "--capture" in args
	if capture: DirAccess.make_dir_recursive_absolute(DIR)
	match args[0]:
		"write": await write_phase()
		"read": await read_phase()
		"cleanup": check(Fixture.clean(store),"remove own profile")
		_: check(false,"unknown phase")
	print("STAGE_1E_1_PROCESS ",args[0]," PID=",OS.get_process_id()," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
