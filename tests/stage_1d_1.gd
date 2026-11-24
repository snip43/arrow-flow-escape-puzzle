extends SceneTree

const Game := preload("res://scenes/game.tscn")
const WINDOWS := [Vector2i(360,640), Vector2i(405,720), Vector2i(412,915), Vector2i(768,1024), Vector2i(900,600)]
var game
var board
var checks := 0
var failed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(label)

func settle() -> void:
	await process_frame
	await process_frame

func progress(count: int) -> bool:
	return (game.get_node("Layout/Count").text == "%d / %d cleared" % [count,game.total]
		and game.get_node("Layout/Track").value == count and game.get_node("Layout/Track").max_value == game.total)

func pose() -> Array:
	return [board.get_global_rect(), board.spacing(), board.center(Vector2i.ZERO),
		board.center(game.model.size-Vector2i.ONE),board.center(game.model.size/2)]

func same(a: Array) -> bool:
	var b := pose()
	return (a[0].is_equal_approx(b[0]) and is_equal_approx(a[1],b[1]) and a[2].is_equal_approx(b[2])
		and a[3].is_equal_approx(b[3]) and a[4].is_equal_approx(b[4]))

func pointer(at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	root.push_input(ev,true)

func click(at: Vector2) -> void:
	pointer(at,true)
	pointer(at,false)

func cell_position(cell: Vector2i) -> Vector2:
	return board.get_global_transform_with_canvas()*board.center(cell)

func button_click(button: Button) -> void:
	click(button.get_global_transform_with_canvas()*(button.size/2))

func screen_rect(control: Control) -> Rect2:
	return root.get_final_transform()*control.get_global_rect()

func layout(id: int) -> void:
	var b := screen_rect(board)
	var button := screen_rect(game.get_node("%Restart"))
	var screen := Rect2(Vector2.ZERO,Vector2(root.size)).grow(0.1)
	check(screen.encloses(b) and screen.encloses(button) and not b.intersects(button),"board and restart bounds")
	check(button.size.y>=47.99,"physical restart target")
	var panel: Control = game.get_node("Layout/Overlay")
	check(panel.get_global_rect().is_equal_approx(board.get_global_rect()),"overlay covers only board")
	for node in game.find_children("*","Label"):
		if node.is_visible_in_tree():
			check(screen.encloses(screen_rect(node)) and node.size.x+0.1>=node.get_minimum_size().x,"text clipped: "+node.name)
	if game.get_node("%Next").is_visible_in_tree():
		var next := screen_rect(game.get_node("%Next"))
		check(next.size.y>=47.99 and b.encloses(next) and not next.intersects(screen_rect(game.complete)),"next layout")
	if id==100 and game.complete.visible:
		print("LAYOUT ",root.size," board=",b," cell_px=",snappedf(board.spacing()*root.get_final_transform().get_scale().x,0.01)," restart=",button.size)

func gestures() -> void:
	game.load_level(1)
	await settle()
	var initial := pose()
	var pos := cell_position(Vector2i(1,3))
	click(pos)
	await settle()
	check(board.flashed=="A" and progress(0) and same(initial),"blocked tap and stable layout")
	pos = cell_position(Vector2i(7,3))
	pointer(pos,true)
	check(not board.locked and progress(0),"wait for release")
	pointer(pos,false)
	game.animation.pause()
	check(board.exiting=="B" and progress(0) and not game.complete.visible,"counter waits for tail")
	var stale: int = game.generation
	button_click(game.get_node("%Restart"))
	game.finish_move("B",stale)
	check(progress(0) and not board.locked and game.model.ids().size()==8,"restart button interrupts motion")
	click(pos)
	game.animation.custom_step(4)
	game.finish_move("B",game.generation)
	game.move("?")
	game.move("B")
	check(progress(1) and not game.complete.visible,"one commit for B")

func check_states(id: int) -> void:
	game.load_level(id)
	await settle()
	var initial := pose()
	if root.size==Vector2i(405,720):
		var xf := root.get_final_transform()
		print("level=",id," first_px=",xf*cell_position(Vector2i.ZERO)," last_px=",xf*cell_position(game.model.size-Vector2i.ONE)," step_px=",board.spacing()*xf.x.length())
	var solution: Array = game.catalog.get_level(id).solution
	game.next_level()
	check(game.level_id==id and not game.get_node("%Next").is_visible_in_tree(),"next gated")
	layout(id)
	for i in solution.size():
		game.move(solution[i])
		game.animation.pause()
		if i==0 or i==solution.size()-1:
			await settle()
			check(same(initial) and progress(i) and not game.complete.visible,"flight layout and uncommitted progress")
		game.animation.custom_step(5)
		if i==0:
			await settle()
			check(progress(1) and same(initial),"partial layout")
	await settle()
	check(progress(game.total) and same(initial) and game.complete.is_visible_in_tree(),"victory layout")
	check(not board.is_processing_input() and board.tap.owner==board.tap.IDLE and game.get_node("Layout/Overlay").mouse_filter==Control.MOUSE_FILTER_STOP,"board input disabled at victory")
	check(game.complete.text==("ALL LEVELS COMPLETE" if id==100 else "LEVEL COMPLETE"),"victory label")
	layout(id)
	click(board.get_global_rect().position+Vector2(10,10))
	click(game.get_node("Layout/Level").get_global_rect().get_center())
	check(game.level_id==id and progress(game.total) and game.complete.visible,"non-button clicks at victory")
	if id < 100:
		button_click(game.get_node("%Next"))
		check(game.level_id==id+1 and progress(0) and board.is_processing_input(),"viewport next")
		game.load_level(id)
	else:
		check(not game.get_node("%Next").is_visible_in_tree(),"final next hidden")
	button_click(game.get_node("%Restart"))
	await settle()
	check(same(initial) and progress(0) and not game.complete.visible,"restart restores board")

func dense_input() -> void:
	game.load_level(100)
	var all_hits := true
	var edges := [false,false,false,false]
	var paths: Dictionary = game.catalog.get_level(100).paths
	for id in paths:
		var path: Array = paths[id]
		for i in path.size():
			var cell: Vector2i = path[i]
			all_hits = all_hits and board.hit(board.center(cell))==id
			if i>0:
				var mid: Vector2 = (board.center(cell)+board.center(path[i-1]))/2
				all_hits = all_hits and board.hit(mid)==id
			if cell.x==0: edges[0] = true
			if cell.y==0: edges[1] = true
			if cell.x==game.model.size.x-1: edges[2] = true
			if cell.y==game.model.size.y-1: edges[3] = true
	check(all_hits and not edges.has(false),"dense midpoints, turns and four edges")
	var gap := (cell_position(Vector2i.ZERO)+cell_position(Vector2i.ONE))/2
	click(gap)
	check(progress(0) and not board.locked and board.flashed.is_empty(),"gap between four centers")
	var id: String = game.catalog.get_level(100).solution[0]
	var pos := cell_position(paths[id][0])
	for pair in [[0,true],[1,true],[0,false],[1,false]]:
		var e := InputEventScreenTouch.new()
		e.position = pos
		e.index = pair[0]
		e.pressed = pair[1]
		root.push_input(e,true)
	check(not board.locked and progress(0),"multitouch never starts exit")
	click(pos)
	game.animation.pause()
	game.animation.custom_step(0.04)
	var section: PackedVector2Array = board.motion.section(board.distance)
	root.size = Vector2i(412,915)
	await settle()
	check(section==board.motion.section(board.distance) and board.exiting==id and progress(0),"resize preserves flight and count")
	game.restart()

func run() -> void:
	game = Game.instantiate()
	root.add_child(game)
	board = game.board
	await settle()
	for id in [1,2,20,21,60,61,80,100]:
		var data: Dictionary = game.catalog.get_level(id)
		check(game.load_level(id) and game.total==data.paths.size() and progress(0),"catalog total")
		check(game.get_node("Layout/Level").text=="LEVEL %d"%id and game.get_node("Layout/Tier").text==data.tier,"catalog labels")
		check(game.get_node("Layout/Tutorial").visible==(id==1),"tutorial gated")
	await gestures()
	await dense_input()
	game.load_level(1)
	# A press from the old generation cannot become a click on the restored field.
	game.restart()
	var pos := cell_position(Vector2i(7,3))
	pointer(pos,true)
	game.restart()
	pointer(pos,false)
	check(not board.locked and progress(0),"no ghost click after restart")
	for dims in WINDOWS:
		root.size = dims
		await settle()
		for id in [2,40,100]:
			await check_states(id)
	print("STAGE 1D.1: %d checks, %d failures" % [checks,failed])
	quit(1 if failed else 0)
