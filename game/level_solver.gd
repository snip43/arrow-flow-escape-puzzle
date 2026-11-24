extends RefCounted

const Model := preload("res://game/board_model.gd")

static func solve(size: Vector2i, paths: Dictionary) -> Dictionary:
	var model := Model.new()
	if not model.load_level(size, paths):
		return {"solvable": false, "error": "invalid geometry", "remaining_ids": paths.keys(), "solution": []}
	var cells := {}
	var pending := {}
	var dependents := {}
	var ids := paths.keys()
	ids.sort()
	for id in ids:
		dependents[id] = []
		for cell in paths[id]:
			cells[cell] = id
	var ready := []
	var edges := 0
	for id in ids:
		var p: Array = paths[id]
		var step: Vector2i = p[-1] - p[-2]
		var cell: Vector2i = p[-1] + step
		var blockers := {}
		while Rect2i(Vector2i.ZERO, size).has_point(cell):
			if cells.has(cell):
				blockers[cells[cell]] = true
			cell += step
		pending[id] = blockers.size()
		edges += blockers.size()
		if blockers.is_empty():
			ready.append(id)
		for blocker in blockers:
			dependents[blocker].append(id)
	var initial := ready.size()
	var waves := 0
	var solution := []
	var forced := 0
	while not ready.is_empty():
		waves += 1
		var next := []
		for i in ready.size():
			var id = ready[i]
			if ready.size() - i + next.size() == 1:
				forced += 1
			solution.append(id)
			pending.erase(id)
			for child in dependents[id]:
				pending[child] -= 1
				if pending[child] == 0:
					next.append(child)
		ready = next
	return {"solvable": pending.is_empty(), "error": "" if pending.is_empty() else "deadlock",
		"remaining_ids": pending.keys(), "solution": solution, "edges": edges, "initial": initial,
		"waves": waves, "forced": forced}

static func replay(size: Vector2i, paths: Dictionary, order: Array) -> bool:
	var model := Model.new()
	if not model.load_level(size, paths):
		return false
	for id in order:
		if not id is String or not model.remove(id):
			return false
	return model.ids().is_empty()
