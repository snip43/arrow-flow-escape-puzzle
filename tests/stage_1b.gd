extends SceneTree

const Motion := preload("res://game/arrow_motion.gd")
const Level := preload("res://levels/level_1.gd")
var game
var board
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	run.call_deferred()

func touch(i: int, at: Vector2, down: bool, canceled := false, device := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = board.get_global_transform_with_canvas() * at
	e.pressed = down
	e.canceled = canceled
	e.device = device
	root.push_input(e,true)

func run() -> void:
	var paths := Level.arrows()
	paths["zigzag"] = [Vector2i(2,2),Vector2i(3,2),Vector2i(3,3),Vector2i(4,3),Vector2i(4,4)]
	for id in paths:
		var m := Motion.new(paths[id],Level.SIZE)
		check(m.section(0) == m.points,"start "+id)
		var good := true
		var previous := m.section(0)
		for n in range(1,201):
			var d := m.travel*n/200
			var p := m.section(d)
			var length := 0.0
			for j in range(1,p.size()):
				length += p[j].distance_to(p[j-1])
			good = good and is_equal_approx(length,m.length) and p[-1].is_equal_approx(m.points[-1]+m.direction*d)
			good = good and p[0].distance_to(previous[0]) <= m.travel/200+0.0001
			previous = p
		check(good,"continuous translation "+id)
		for j in m.length:
			check(m.section(j)[0] == m.points[j],"tail follows corner "+id)
		check(not Rect2(Vector2(-0.5,-0.5),Vector2(Level.SIZE)).grow(0.2).has_point(previous[0]),"fully outside "+id)
	game = preload("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	board = game.board
	await process_frame
	var bend: Vector2 = board.center(Vector2i(2,8))
	var outside := Vector2(-20,-20)
	for first in [0,1]:
		touch(0,bend,true)
		touch(1,outside,true)
		touch(first,bend if first == 0 else outside,false)
		touch(2,bend,true)
		touch(2,bend,false)
		touch(1-first,outside if first == 0 else bend,false)
		check(not board.locked,"multitouch release order")
	for mode in ["outside","cancel","focus","emulated","miss"]:
		var at := outside if mode == "miss" else bend
		var device := InputEvent.DEVICE_ID_EMULATION if mode == "emulated" else 0
		touch(0,at,true,false,device)
		if mode == "focus":
			board.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		touch(0,outside if mode == "outside" else at,false,mode == "cancel",device)
		check(not board.locked,mode)
	game.move("A")
	board.feedback.pause()
	board.feedback.custom_step(0.18)
	board.feedback.play()
	game.move("E")
	await create_timer(0.09).timeout
	check(board.flashed == "E" and game.model.ids().size() == 8,"replace blocked feedback")
	for ratio in [0.01,0.5,0.96]:
		touch(0,bend,true)
		touch(0,bend,false)
		check(board.exiting == "D","single bend tap recovered")
		game.animation.pause()
		game.animation.custom_step(board.motion.travel/game.SPEED*ratio)
		var old: int = game.generation
		game.restart()
		game.finish_move("D",old)
		check(not board.locked and board.motion == null and game.model.ids().size()==8,"restart at "+str(ratio))
	game.move("A")
	game.move("C")
	check(board.flashed=="C" and game.model.ids().size()==8,"replace feedback")
	game.move("B")
	game.animation.pause()
	game.animation.custom_step(0.06)
	var saved: PackedVector2Array = board.motion.section(board.distance)
	touch(0,bend,true)
	for dims in [Vector2i(405,720),Vector2i(900,600)]:
		root.size = dims
		await process_frame
		await process_frame
		check(board.motion.section(board.distance)==saved and game.model.path_for("D")==paths["D"] and not game.model.can_exit("A"),"resize while occupied")
	check(board.flashed=="","successful move clears feedback")
	game.animation.custom_step(1.0)
	touch(0,board.center(Vector2i(2,8)),false)
	check(not board.locked and game.model.ids().size()==7,"ignore press during motion")
	for id in Level.SOLUTION.slice(1):
		game.move(id)
		check(not game.complete.visible and board.locked,"victory deferred "+id)
		game.animation.custom_step(2.0)
	check(game.complete.visible,"all tails gone")
	print("STAGE 1B: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
