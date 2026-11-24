extends RefCounted

const M := preload("res://game/level_metrics.gd")
const Solver := preload("res://game/level_solver.gd")
const Tutorial := preload("res://levels/level_1.gd")
const FILE := "res://levels/data/catalog.json"
const VERSION := 1
var _rows: Array = []

static func tutorial() -> Dictionary:
	var paths := Tutorial.arrows()
	var graph := Solver.solve(Tutorial.SIZE,paths)
	return {"paths":paths,"solution":Tutorial.SOLUTION.duplicate(),"witness":[],"seed":0,
		"metrics":M.measure(Tutorial.SIZE,paths,graph)}

static func encode(id: int, data: Dictionary) -> Dictionary:
	var t := M.tier(id)
	var size: Vector2i = M.SIZES[t]
	var arrows := []
	for key in data.paths:
		var coords := []
		for cell in data.paths[key]:
			coords.append([cell.x,cell.y])
		arrows.append({"id":key,"path":coords})
	return {"schema_version":1,"generator_version":VERSION,"level_id":id,"width":size.x,"height":size.y,
		"tier":M.TIERS[t],"seed":data.seed,"arrows":arrows,"metrics":data.metrics,
		"solution":data.solution,"witness":data.witness}

static func integer(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v) and floor(v) == v)

static func decode(id: int, row: Variant) -> Dictionary:
	if id < 1 or id > 100 or not row is Dictionary:
		return {"error":"invalid ID or record"}
	var t := M.tier(id)
	var size: Vector2i = M.SIZES[t]
	if row.get("level_id") != id or row.get("schema_version") != 1 or row.get("generator_version") != VERSION or row.get("width") != size.x or row.get("height") != size.y or row.get("tier") != M.TIERS[t] or not integer(row.get("seed")):
		return {"error":"invalid metadata for level %d" % id}
	if not row.get("arrows") is Array or not row.get("solution") is Array or not row.get("witness") is Array or not row.get("metrics") is Dictionary:
		return {"error":"missing arrows, metrics or solutions"}
	var paths := {}
	for arrow in row.arrows:
		if not arrow is Dictionary or not arrow.get("id") is String or arrow.id.is_empty() or paths.has(arrow.id) or not arrow.get("path") is Array:
			return {"error":"invalid arrow ID or path"}
		var path := []
		for xy in arrow.path:
			if not xy is Array or xy.size()!=2 or not integer(xy[0]) or not integer(xy[1]) or xy[0]<0 or xy[0]>=size.x or xy[1]<0 or xy[1]>=size.y:
				return {"error":"invalid coordinate in "+arrow.id}
			path.append(Vector2i(xy[0],xy[1]))
		paths[arrow.id] = path
	var graph := Solver.solve(size,paths)
	if not graph.solvable: return {"error":graph.error}
	if not Solver.replay(size,paths,row.solution) or (id > 1 and not Solver.replay(size,paths,row.witness)):
		return {"error":"invalid recorded solution"}
	var metrics := M.measure(size,paths,graph)
	if JSON.stringify(metrics) != JSON.stringify(row.metrics) or (id > 1 and not M.accepts(t,metrics)):
		return {"error":"invalid metrics"}
	return {"paths":paths,"size":size,"tier":row.tier,"seed":int(row.seed),"metrics":metrics,
		"solution":row.solution.duplicate(),"witness":row.witness.duplicate()}

func get_level(id: int) -> Dictionary:
	if id < 1 or id > 100: return {"error":"level ID outside 1..100"}
	if _rows.is_empty():
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(FILE)) != OK or not parser.data is Array or parser.data.size()!=100:
			return {"error":"invalid level catalog"}
		_rows = parser.data
	return decode(id,_rows[id-1])
