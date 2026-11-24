extends SceneTree

const Model := preload("res://game/board_model.gd")
const Level := preload("res://levels/level_1.gd")
const Game := preload("res://scenes/game.tscn")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var m := Model.new()
	check(m.load_level(Level.SIZE, Level.arrows()), "valid level")
	var original := m.ids()
	var available := []
	for id in original:
		if m.can_exit(id):
			available.append(id)
	check(available == ["B","D","G","H"], "initial free exits north south east west")
	check(not m.remove("A") and not m.remove("?") and m.ids() == original, "blocked and unknown moves preserve ids")
	check(m.remove("B") and m.can_exit("A") and not m.remove("B"), "release ray and reject repeat")
	for bad in [
		{"a":[Vector2i.ZERO]}, {"a":[Vector2i.ZERO,Vector2i.ONE]},
		{"a":[Vector2i.ZERO,Vector2i.LEFT]}, {"a":[Vector2i.ZERO,Vector2i.RIGHT,Vector2i.ZERO]},
		{"a":[Vector2i.ZERO,Vector2i.RIGHT],"b":[Vector2i.RIGHT,Vector2i.ONE]},
		{"a":[Vector2i.ZERO,Vector2i.DOWN,Vector2i(1,1),Vector2i(2,1),Vector2i(2,0),Vector2i(1,0)]}
	]:
		check(not m.load_level(Level.SIZE,bad) and m.can_exit("A"), "reject invalid geometry atomically")
	check(m.load_level(Level.SIZE,Level.arrows()) and not m.can_exit("A"), "restore occupancy")
	for id in Level.SOLUTION:
		check(m.remove(id), "solution " + id)
	check(m.ids().is_empty(), "model complete")

	var game := Game.instantiate()
	root.add_child(game)
	await process_frame
	var board = game.board
	var bend: Vector2 = board.center(Vector2i(2,8))
	check(board.hit(bend) == "D" and board.hit(bend + Vector2.RIGHT*board.spacing()*0.5) == "", "bend and gap hit tests")
	var at: Vector2 = board.center(Vector2i(7,3))
	mouse(board, at, true)
	var drag := InputEventMouseMotion.new()
	drag.position = at + Vector2.RIGHT*board.spacing()
	board._gui_input(drag)
	mouse(board, at, false)
	check(not board.locked, "drag out and back cancels")
	mouse(board, at, true, InputEvent.DEVICE_ID_EMULATION)
	mouse(board, at, false, InputEvent.DEVICE_ID_EMULATION)
	check(not board.locked, "emulated mouse ignored")
	game.move("A")
	check(board.flashed == "A" and game.model.ids() == original, "blocked feedback")
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	touch.position = at
	touch.pressed = true
	board._gui_input(touch)
	check(not board.locked, "touch press waits")
	touch.pressed = false
	board._gui_input(touch)
	var ticket: int = game.generation
	mouse(board, bend, true)
	mouse(board, bend, false)
	check(board.locked and board.exiting == "B" and game.model.ids() == original, "touch release starts one deferred removal")
	game.get_node("%Restart").pressed.emit()
	game.finish_move("B",ticket)
	await create_timer(0.35).timeout
	check(game.model.ids() == original and not board.locked and not game.complete.visible, "restart during animation rejects stale callback")
	# Deliver the final mouse gesture through the viewport and GUI hit routing.
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = board.get_global_transform_with_canvas() * at
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		root.push_input(click, true)
	await create_timer(0.35).timeout
	check(game.model.can_exit("A") and game.model.ids().size() == 7, "mouse release commits once")
	for id in Level.SOLUTION.slice(1):
		game.move(id)
		await create_timer(0.35).timeout
	check(game.complete.is_visible_in_tree() and game.model.ids().is_empty(), "victory after final tween")
	game.get_node("%Restart").pressed.emit()
	check(not game.complete.visible and game.model.ids() == original, "restart after victory")
	for dimensions in [Vector2i(360,640), Vector2i(412,915), Vector2i(768,1024), Vector2i(900,600)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var grid := Rect2(board.center(Vector2i.ZERO) - Vector2.ONE * board.spacing() * 0.5, Vector2(Level.SIZE) * board.spacing())
		var viewport_rect := root.get_visible_rect()
		check(Rect2(Vector2.ZERO,board.size).encloses(grid) and viewport_rect.encloses(board.get_global_rect()) and viewport_rect.encloses(game.get_node("%Restart").get_global_rect()), "layout %s" % dimensions)
	print("STAGE 1A: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func mouse(board: Control, at: Vector2, pressed: bool, device := 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = device
	board._gui_input(event)
