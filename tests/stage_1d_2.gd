extends SceneTree

const Session := preload("res://game/campaign_session.gd")
var app
var checks := 0
var failures := 0
var wins := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	await process_frame
	await process_frame

func center(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas()*(c.size/2)

func mouse(at: Vector2, down: bool, device := 0, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.device = device
	event.position = at
	event.button_index = button
	event.pressed = down
	root.push_input(event,true)

func click(c: Control) -> void:
	for down in [true,false]:
		mouse(center(c),down)

func touch(at: Vector2,index: int,down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = at
	e.index = index
	e.pressed = down
	root.push_input(e,true)

func escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.push_input(key,true)

func status(id: int) -> String:
	return app.cards[id].get_node("Content/Status").text

func finish() -> void:
	var sequence: Array = app.catalog.get_level(app.game.level_id).solution
	var before: int = app.session.completed_count()
	for id in sequence:
		app.game.move(id)
		check(not app.game.complete.visible and app.session.completed_count()==before,"unlock waits for tail")
		app.game.animation.custom_step(5)
	check(app.game.complete.visible,"win committed")

func native_touch_click(c: Control) -> void:
	# Go through Input itself, allowing Godot to synthesize the GUI mouse events.
	var window_position := root.get_final_transform() * center(c)
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.position = window_position
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func menu_routes() -> void:
	check(app.screen==app.Screen.MENU and app.game==null and app.menu.visible,"startup menu")
	check(app.menu.get_node("Play").text=="Play · Level 1" and app.session.completed_count()==0,"fresh campaign")
	check(not app.open_level(2) and not app.open_level(0) and not app.open_level(101),"guarded route")
	await native_touch_click(app.menu.get_node("Levels"))
	await settle()
	check(app.screen==app.Screen.LEVELS,"native touch opens Levels")
	var entries: Array = app.catalog.entries()
	check(entries.size()==100 and app.cards.size()==100,"all levels in selector")
	for row in entries:
		var card: Button = app.cards[row.id]
		var grid := card.get_parent()
		var header: Label = grid.get_parent().get_child(grid.get_index()-1)
		check(header.text==row.tier and card.get_node("Content/Number").text==str(row.id) and card.disabled==(row.id!=1),"catalog card %d"%row.id)
	check(status(1)=="Open" and status(2)=="Locked","text status")
	click(app.cards[2])
	check(app.game==null,"disabled card")
	var at := center(app.cards[1])
	touch(at,0,true)
	touch(at,1,true)
	touch(at,1,false)
	touch(at,0,false)
	mouse(at,true,InputEvent.DEVICE_ID_EMULATION)
	mouse(at,false,InputEvent.DEVICE_ID_EMULATION)
	check(app.game==null,"multitouch and emulated click ignored")
	mouse(at,true,0,MOUSE_BUTTON_WHEEL_DOWN)
	await settle()
	check(app.scroll.scroll_vertical>0 and app.game==null,"viewport wheel scroll")
	app.scroll.scroll_vertical = 0
	await settle()
	click(app.cards[1])
	await settle()
	check(app.game!=null and app.game.level_id==1,"selector opens exact id")
	var old = app.game
	var ticket: int = old.generation
	old.move("A")
	check(app.session.completed_count()==0 and old.board.flashed=="A","blocked not complete")
	old.move("B")
	click(old.get_node("%Restart"))
	check(app.session.completed_count()==0 and old.model.ids().size()==8,"restart during exit")
	old.move("B")
	old.animation.custom_step(5)
	check(app.session.completed_count()==0,"partial not complete")
	old.move("A")
	click(old.get_node("%Back"))
	old.finish_move("A",ticket)
	check(app.game==null and not old.is_inside_tree() and not old.board.is_processing_input(),"detached in-flight game")
	await settle()
	check(not is_instance_valid(old) and app.screen==app.Screen.LEVELS,"freed game returns to selector")
	click(app.cards[1])
	escape()
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app.screen==app.Screen.LEVELS,"duplicate platform back leaves one screen")
	await settle()
	escape()
	check(app.screen==app.Screen.MENU,"escape levels to menu")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app.screen==app.Screen.MENU,"root back stays at menu")
	click(app.menu.get_node("Play"))
	app.game.completed.connect(func(_id): wins+=1)
	check(app.game.model.ids().size()==8 and not app.open_level(1),"fresh board and repeated route rejected")
	finish()
	app.game.finish_move("G",app.game.generation)
	check(wins==1 and app.session.completed_count()==1 and app.session.can_play(2),"one completion unlocks two")
	click(app.game.get_node("%Restart"))
	finish()
	check(app.session.completed_count()==1,"replay unique")
	click(app.game.get_node("%Next"))
	check(app.game.level_id==2 and app.session.completed_count()==1,"next board")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app.screen==app.Screen.MENU and app.menu.get_node("Progress").text=="1 / 100 completed" and app.menu.get_node("Play").text=="Continue · Level 2","origin retained through next")

func labels_fit(panel: Control) -> bool:
	var area := Rect2(Vector2.ZERO,Vector2(root.size)).grow(1)
	for child in panel.find_children("*","Label",true,false):
		var label := child as Label
		if not label.is_visible_in_tree(): continue
		if not area.encloses(root.get_final_transform()*label.get_global_rect()):
			return false
		if label.size.x + 0.1 < label.get_minimum_size().x:
			return false
	return true

func sizes() -> void:
	for dims in [Vector2i(360,640),Vector2i(405,720),Vector2i(412,915),Vector2i(768,1024),Vector2i(900,600)]:
		root.size = dims
		await settle()
		var play: Button = app.menu.get_node("Play")
		var levels: Button = app.menu.get_node("Levels")
		var scale_factor := root.get_final_transform().x.length()
		check(play.size.y*scale_factor>=48 and not play.get_global_rect().intersects(levels.get_global_rect()),"menu target and space")
		check(labels_fit(app.menu),"main labels fit viewport")
		click(levels)
		await settle()
		check(status(1)=="Cleared" and status(2)=="Open" and status(3)=="Locked","progressed selector")
		app.scroll.scroll_vertical = int(app.scroll.get_v_scroll_bar().max_value)
		await settle()
		check(app.scroll.get_global_rect().grow(1).encloses(app.cards[100].get_global_rect()),"bottom reachable")
		var card: Button = app.cards[100]
		check(card.size.y*scale_factor>=48 and card.size.x*scale_factor>=48,"card target")
		check(card.focus_mode==Control.FOCUS_NONE and app.cards[2].focus_mode==Control.FOCUS_ALL,"locked cards skipped in focus order")
		app.cards[2].grab_focus()
		await settle()
		check(app.scroll.get_global_rect().grow(1).encloses(app.cards[2].get_global_rect()),"keyboard focus scrolls to available card")
		var number: Label = card.get_node("Content/Number")
		check(card.get_global_rect().encloses(number.get_global_rect()) and number.size.x>=number.get_minimum_size().x,"100 fits")
		app.scroll.scroll_vertical = 0
		await settle()
		click(app.cards[1])
		await settle()
		var back_button: Button = app.game.get_node("%Back")
		var pose: Rect2 = app.game.board.get_global_rect()
		check(back_button.size.y*scale_factor>=48 and not pose.intersects(back_button.get_global_rect()) and not back_button.get_global_rect().intersects(app.game.get_node("%Restart").get_global_rect()),"game back safe target")
		app.game.move("B")
		app.game.animation.custom_step(5)
		await settle()
		check(app.game.board.get_global_rect().is_equal_approx(pose),"partial geometry")
		for id in app.catalog.get_level(1).solution.slice(1):
			app.game.move(id)
			app.game.animation.custom_step(5)
		await settle()
		check(app.game.complete.visible and pose.is_equal_approx(app.game.board.get_global_rect()),"victory geometry")
		click(app.game.get_node("%Restart"))
		await settle()
		check(pose.is_equal_approx(app.game.board.get_global_rect()) and app.game.model.ids().size()==8,"restart geometry")
		print("LAYOUT ",dims," play=",play.size*scale_factor," card=",card.size*scale_factor," back=",back_button.size*scale_factor)
		click(back_button)
		await settle()
		click(app.selector.get_node("Back"))
		await settle()

func boundaries() -> void:
	for id in [20,60,99,100]:
		for earlier in range(app.session.completed_count()+1,id):
			app.session.record_completion(earlier)
		click(app.menu.get_node("Levels"))
		await settle()
		check(app.scroll.get_global_rect().grow(1).encloses(app.cards[id].get_global_rect()),"auto-scroll frontier")
		click(app.cards[id])
		check(app.game.level_id==id and not app.session.can_play(id+1),"locked next boundary")
		check(labels_fit(app.game),"game labels fit at tier boundary")
		finish()
		check(app.session.completed_count()==id and app.session.is_completed(id),"boundary recorded")
		if id < 100:
			click(app.game.get_node("%Next"))
			check(app.game.level_id==id+1 and app.session.can_play(id+1),"unlocked next")
		else:
			check(not app.game.get_node("%Next").visible and app.session.next_incomplete()==0,"campaign end")
		click(app.game.get_node("%Back"))
		await settle()
		click(app.selector.get_node("Back"))
		await settle()
	check(app.menu.get_node("Progress").text=="100 / 100 completed" and not app.menu.get_node("Play").visible,"finished menu")
	click(app.menu.get_node("Levels"))
	await settle()
	check(status(100)=="Cleared" and not app.cards[100].disabled and not app.open_level(101),"all replayable, no 101")

func run() -> void:
	app = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	app.store = preload("res://tests/save_fixture.gd").make_store()
	root.add_child(app)
	await settle()
	await menu_routes()
	await sizes()
	await boundaries()
	check(Session.new().completed_count()==0,"independent session")
	print("STAGE 1D.2: %d checks, %d failures"%[checks,failures])
	if not preload("res://tests/save_fixture.gd").clean(app.store):
		quit(1)
		return
	quit(1 if failures else 0)
