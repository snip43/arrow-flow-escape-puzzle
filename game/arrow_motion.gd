extends RefCounted

# Adjacent cell centres are exactly one unit apart, so vertex index is arc length.
var points: PackedVector2Array
var direction: Vector2
var length: int
var travel: float

func _init(path: Array, bounds: Vector2i) -> void:
	for cell in path:
		points.append(Vector2(cell))
	length = points.size() - 1
	var head := points[length]
	direction = head - points[length - 1]
	var edge_distance := head.dot(-direction)
	if direction.x > 0 or direction.y > 0:
		edge_distance += Vector2(bounds).dot(direction) - 1.0
	travel = length + edge_distance + 1.0

func sample(distance: float) -> Vector2:
	if distance >= length:
		return points[length] + direction * (distance - length)
	var i := floori(distance)
	return points[i].lerp(points[i + 1], distance - i)

func section(distance: float) -> PackedVector2Array:
	var result := PackedVector2Array([sample(distance)])
	for i in range(floori(distance) + 1, length + 1):
		if i < distance + length:
			result.append(points[i])
	result.append(sample(distance + length))
	return result
