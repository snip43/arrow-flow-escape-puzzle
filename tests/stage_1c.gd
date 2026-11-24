extends SceneTree

const C := preload("res://levels/level_catalog.gd")
const G := preload("res://game/level_generator.gd")
const S := G.Solver
const M := G.M
const Model := preload("res://game/board_model.gd")
var catalog := C.new()
var checks := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(label)

func _initialize() -> void:
	run.call_deferred()

func random_clear(data: Dictionary, rng: RandomNumberGenerator) -> bool:
	var model := Model.new()
	if not model.load_level(data.size,data.paths): return false
	while not model.ids().is_empty():
		var free := model.ids().filter(model.can_exit)
		if free.is_empty() or not model.remove(free[rng.randi_range(0,free.size()-1)]): return false
	return true

func fixtures() -> void:
	var cycle := {"a":[Vector2i(0,0),Vector2i(1,0)],"b":[Vector2i(4,0),Vector2i(3,0)]}
	var bounds := Vector2i(8,4)
	check(S.solve(bounds,cycle).error == "deadlock","cycle")
	cycle.c = [Vector2i(0,2),Vector2i(0,3)]
	var graph := S.solve(bounds,cycle)
	check(graph.remaining_ids == ["a","b"] and graph.solution == ["c"],"partial deadlock")
	var line := {}
	for i in 4:
		line[str(i)] = [Vector2i(2*i,0),Vector2i(2*i+1,0)]
	graph = S.solve(bounds,line)
	check(graph.initial == 1 and graph.edges == 6 and graph.waves == 4,"all blockers and longest chain")
	line.erase("0")
	line.erase("1")
	line["2"] = [Vector2i(4,1),Vector2i(5,1)]
	check(S.solve(bounds,line).initial == 2,"independent arrows")
	check(not S.replay(bounds,line,["unknown"]),"unknown id")
	line["2"][1] = Vector2i(6,1)
	check(S.solve(bounds,line).error == "invalid geometry","geometry versus cycle")
	var row := C.encode(1,C.tutorial())
	for bad in [[1.2,1],[1],[1,-1],["1",1],[1,1,2],[false,0],[1,1e20]]:
		var copy := row.duplicate(true)
		copy.arrows[0].path[0] = bad
		check(C.decode(1,copy).has("error"),"invalid coordinate "+str(bad))
	row.arrows[1].id = row.arrows[0].id
	check(C.decode(1,row).has("error"),"duplicate id")
	check(G.generate(4,1).has("error") and G.generate(3,1,1).has("error"),"bounded failure")

func run() -> void:
	fixtures()
	var rng := RandomNumberGenerator.new()
	var times := []
	var seen := {}
	var previous := 0.0
	for id in range(1,101):
		var d := catalog.get_level(id)
		check(not d.has("error"),"decode %d"%id)
		if d.has("error"): quit(1); return
		var before := var_to_bytes(d)
		var start := Time.get_ticks_usec()
		var graph := S.solve(d.size,d.paths)
		times.append(Time.get_ticks_usec()-start)
		check(graph.solvable and S.replay(d.size,d.paths,graph.solution),"solver replay")
		check(S.replay(d.size,d.paths,d.solution),"stored solution")
		var t := M.tier(id)
		if id > 1:
			check(S.replay(d.size,d.paths,d.witness),"reverse witness")
			var key := M.signature(d.size,d.paths)
			check(not seen.has(key),"unique symmetry class")
			seen[key] = true
			seed(id)
			randf()
			var rebuilt := G.generate(t,d.seed)
			check(not rebuilt.has("error") and C.encode(id,rebuilt)==C.encode(id,d),"seed reconstruction")
			check(M.accepts(t,d.metrics) and (M.tier(id-1)!=t or previous<=d.metrics.difficulty),"range and order")
		else:
			check(d.paths == C.Tutorial.arrows() and d.solution == C.Tutorial.SOLUTION,"tutorial")
		previous = d.metrics.difficulty
		for k in 3:
			rng.seed = id*3+k
			check(random_clear(d,rng),"alternate order")
		check(before == var_to_bytes(d),"input immutable")
		d.paths.clear()
		check(not catalog.get_level(id).paths.is_empty(),"independent reads")
	times.sort()
	print("solver usec median=", (times[49]+times[50])/2.0," max=",times[-1])
	for t in range(1,4):
		var outcomes := {}
		for i in (34 if t==1 else 33):
			var d := G.generate(t,900000+t*1000+i)
			var outcome: String = d.get("error","accepted")
			outcomes[outcome] = outcomes.get(outcome,0)+1
			check(outcome=="tier metrics" or (outcome=="accepted" and S.replay(M.SIZES[t],d.paths,d.witness)),"extra seed")
		print(M.TIERS[t]," extra seeds ",outcomes)
	await scene_checks()
	print("STAGE 1C: %d checks, %d failures" % [checks,failed])
	quit(1 if failed else 0)

func scene_checks() -> void:
	var game := preload("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.load_level(61)
	var first := catalog.get_level(61)
	var old_id: String = first.solution[0]
	game.move(old_id)
	var old_ticket: int = game.generation
	check(not game.load_level(0) and game.board.exiting == old_id, "invalid switch preserves active move")
	check(game.load_level(62), "switch during active move")
	var second := catalog.get_level(62)
	var new_id: String = second.solution[0]
	game.move(new_id)
	game.finish_move(new_id,old_ticket)
	check(game.board.exiting == new_id and game.model.ids().size()==second.paths.size(),"old ticket cannot finish new exit")
	for id in [1,20,60,100]:
		check(game.load_level(id),"load boundary")
		var d := catalog.get_level(id)
		game.next_level()
		check(game.level_id==id and not game.get_node("%Next").visible and game.model.size==d.size,"next gated")
		game.move(d.solution[0])
		var old: int = game.generation
		game.restart()
		game.finish_move(d.solution[0],old)
		check(game.model.ids().size()==d.paths.size() and not game.board.locked,"restart transition")
		for move_id in d.solution:
			game.move(move_id)
			check(not game.complete.visible and game.board.locked,"wait for tail")
			game.animation.custom_step(5)
		check(game.complete.visible and game.get_node("%Next").visible==(id<100),"victory controls")
		game.get_node("%Next").pressed.emit()
		check(game.level_id==mini(id+1,100),"next boundary")
		game.restart()
		check(not game.complete.visible and not game.get_node("%Next").visible,"restart complete")
	check(not game.load_level(101) and game.level_id==100,"invalid id atomic")
	var data := catalog.get_level(100)
	for dims in [Vector2i(360,640),Vector2i(405,720),Vector2i(412,915)]:
		root.size = dims
		await process_frame
		await process_frame
		var tested := false
		for key in data.paths:
			var p: Array = data.paths[key]
			for j in range(2,p.size()):
				if p[j]-p[j-1]==p[j-1]-p[j-2]: continue
				var at: Vector2 = game.board.center(p[j-1])
				var off: Vector2 = Vector2(p[j]-p[j-1]).orthogonal()*game.board.spacing()*0.23
				check(game.board.hit(at)==key and game.board.hit(at+off)==key,"dense bend target")
				for down in [true,false]:
					var e := InputEventScreenTouch.new()
					e.position = game.board.get_global_transform_with_canvas()*(at+off)
					e.pressed = down
					root.push_input(e,true)
				check(game.board.exiting==key or game.board.flashed==key,"dense viewport tap")
				game.restart()
				tested = true
				break
			if tested: break
		check(tested,"dense bend present")
