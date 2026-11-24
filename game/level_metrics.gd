extends RefCounted

const DIR := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const TIERS := ["Tutorial","Easy","Normal","Hard"]
const SIZES := [Vector2i(10,14),Vector2i(8,12),Vector2i(10,14),Vector2i(12,16)]
const COUNTS := [[8,8],[8,14],[14,22],[22,32]]
const COVER := [[0,1],[0.4,0.65],[0.55,0.75],[0.65,0.85]]
const FREE := [[0,1],[0.3,0.7],[0.15,0.5],[0.05,0.35]]

static func tier(id: int) -> int:
	if id == 1: return 0
	if id <= 20: return 1
	if id <= 60: return 2
	return 3

static func measure(size: Vector2i, paths: Dictionary, graph: Dictionary) -> Dictionary:
	var cells := 0
	var bent := 0
	var multi := 0
	var directions := [0,0,0,0]
	var lengths := {}
	for p in paths.values():
		cells += p.size()
		var key := str(p.size())
		lengths[key] = lengths.get(key,0) + 1
		var turns := 0
		for i in range(2,p.size()):
			if p[i]-p[i-1] != p[i-1]-p[i-2]: turns += 1
		bent += int(turns > 0)
		multi += int(turns >= 2)
		directions[DIR.find(p[-1]-p[-2])] += 1
	var n := paths.size()
	var coverage := float(cells)/(size.x*size.y)
	var free := float(graph.initial)/n
	var difficulty: float = (coverage + n/32.0 + 1-free + graph.waves/16.0 + graph.edges/(3.0*n))/5.0
	return {"arrows":n,"cells":cells,"coverage":coverage,"bent":float(bent)/n,"multi":multi,
		"free":free,"edges":graph.edges,"chain":graph.waves,"waves":graph.waves,
		"forced":graph.forced,"choice":n-graph.forced,"deadlocks":0,"directions":directions,
		"lengths":lengths,"difficulty":difficulty}

static func accepts(t: int, m: Dictionary) -> bool:
	return (m.arrows >= COUNTS[t][0] and m.arrows <= COUNTS[t][1]
		and m.coverage >= COVER[t][0] and m.coverage <= COVER[t][1]
		and m.free >= FREE[t][0] and m.free <= FREE[t][1]
		and m.bent >= [0,0.25,0.35,0.45][t] and m.chain >= [1,2,3,5][t]
		and m.directions.count(0) <= 1 and (t != 3 or m.multi >= 2))

# Enumerate the eight rectangular grid isometries. Translation after reflection
# is implicit in the bounds; cell order within an arrow stays directional.
static func signature(size: Vector2i, paths: Dictionary) -> String:
	var forms := PackedStringArray()
	for flip_x in [false,true]:
		for flip_y in [false,true]:
			for swap in [false,true]:
				var arrows := PackedStringArray()
				for path in paths.values():
					var coords := PackedStringArray()
					for cell in path:
						var x: int = size.x-1-cell.x if flip_x else cell.x
						var y: int = size.y-1-cell.y if flip_y else cell.y
						coords.append("%d,%d" % ([y,x] if swap else [x,y]))
					arrows.append(";".join(coords))
				arrows.sort()
				forms.append(str(Vector2i(size.y,size.x) if swap else size)+"|"+"/".join(arrows))
	forms.sort()
	return forms[0].sha256_text()
