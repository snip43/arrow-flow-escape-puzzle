extends RefCounted

var size := Vector2i.ZERO
var _paths := {}
var _occupied := {}

# Build both indexes before replacing a live level.
func load_level(bounds: Vector2i, paths: Dictionary) -> bool:
	if bounds.x <= 0 or bounds.y <= 0 or paths.is_empty():
		return false
	var occupied := {}
	for id in paths:
		if not id is String or id.is_empty() or not paths[id] is Array:
			return false
		var path: Array = paths[id]
		if path.size() < 2:
			return false
		for i in path.size():
			var cell = path[i]
			if not cell is Vector2i or not Rect2i(Vector2i.ZERO, bounds).has_point(cell) or occupied.has(cell):
				return false
			if i > 0:
				var step: Vector2i = (cell - path[i-1]).abs()
				if step.x + step.y != 1:
					return false
			occupied[cell] = id
		var direction: Vector2i = path[-1] - path[-2]
		var probe: Vector2i = path[-1] + direction
		while Rect2i(Vector2i.ZERO, bounds).has_point(probe):
			if occupied.get(probe) == id:
				return false
			probe += direction
	size = bounds
	_paths = paths.duplicate(true)
	_occupied = occupied
	return true

func ids() -> Array:
	return _paths.keys()

func path_for(id: String) -> Array:
	return _paths.get(id, []).duplicate()

func can_exit(id: String) -> bool:
	if not _paths.has(id):
		return false
	var path: Array = _paths[id]
	var direction: Vector2i = path[-1] - path[-2]
	var probe: Vector2i = path[-1] + direction
	while Rect2i(Vector2i.ZERO, size).has_point(probe):
		if _occupied.has(probe):
			return false
		probe += direction
	return true

func remove(id: String) -> bool:
	if not can_exit(id):
		return false
	for cell in _paths[id]:
		_occupied.erase(cell)
	_paths.erase(id)
	return true
