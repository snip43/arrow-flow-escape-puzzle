extends RefCounted

const M := preload("res://game/level_metrics.gd")
const Solver := preload("res://game/level_solver.gd")

static func generate(t: int, seed_value: int, budget := 2800) -> Dictionary:
	if t < 1 or t > 3 or budget < 1 or budget > 2800:
		return {"error":"invalid tier or attempt budget"}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size: Vector2i = M.SIZES[t]
	var bounds := Rect2i(Vector2i.ZERO,size)
	var paths := {}
	var taken := {}
	var goal := rng.randi_range(M.COUNTS[t][0],M.COUNTS[t][1])
	var fill := rng.randf_range(M.COVER[t][0], M.COVER[t][1])
	for attempt in budget:
		var head := Vector2i(rng.randi_range(0,size.x-1),rng.randi_range(0,size.y-1))
		var dir: Vector2i = M.DIR[rng.randi_range(0,3)]
		var neck := head-dir
		if taken.has(head) or taken.has(neck) or not bounds.has_point(neck): continue
		var ray := {}
		var probe := head+dir
		while bounds.has_point(probe) and not taken.has(probe):
			ray[probe] = true
			probe += dir
		if bounds.has_point(probe): continue
		var path := [head,neck]
		var target := rng.randi_range(4,10)
		for j in range(2,target):
			var choices := []
			for delta in M.DIR:
				var cell: Vector2i = path[-1]+delta
				if bounds.has_point(cell) and not taken.has(cell) and not path.has(cell) and not ray.has(cell):
					choices.append(cell)
			if choices.is_empty(): break
			path.append(choices[rng.randi_range(0,choices.size()-1)])
		if taken.size()+path.size() > M.COVER[t][1]*size.x*size.y: continue
		path.reverse()
		paths["a%02d" % paths.size()] = path
		for cell in path: taken[cell] = true
		var reached_target := paths.size() >= goal and taken.size() >= fill * size.x * size.y
		if reached_target or paths.size() == M.COUNTS[t][1]:
			break
	var graph := Solver.solve(size,paths)
	if not graph.solvable: return {"error":graph.error}
	var metrics := M.measure(size,paths,graph)
	if not M.accepts(t,metrics): return {"error":"tier metrics"}
	var witness := paths.keys()
	witness.reverse()
	if not Solver.replay(size,paths,witness) or not Solver.replay(size,paths,graph.solution):
		return {"error":"replay failed"}
	return {"paths":paths,"solution":graph.solution,"witness":witness,"metrics":metrics,"seed":seed_value}
