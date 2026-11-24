extends RefCounted

const SIZE := Vector2i(10, 14)
const SOLUTION := ["B","A","H","E","D","C","F","G"]

static func arrows() -> Dictionary:
	return {
		"A": [Vector2i(1,2), Vector2i(1,3), Vector2i(2,3), Vector2i(3,3), Vector2i(4,3)],
		"B": [Vector2i(7,4), Vector2i(7,3), Vector2i(7,2), Vector2i(7,1)],
		"C": [Vector2i(8,9), Vector2i(7,9), Vector2i(6,9)],
		"D": [Vector2i(1,8), Vector2i(2,8), Vector2i(2,9), Vector2i(2,10), Vector2i(2,11)],
		"E": [Vector2i(4,6), Vector2i(4,5), Vector2i(4,4)],
		"F": [Vector2i(9,6), Vector2i(8,6), Vector2i(8,7), Vector2i(8,8)],
		"G": [Vector2i(4,12), Vector2i(5,12), Vector2i(6,12), Vector2i(7,12)],
		"H": [Vector2i(5,0), Vector2i(4,0), Vector2i(3,0)]
	}
