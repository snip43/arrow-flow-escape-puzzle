extends Control

# A bent path and its outward-pointing head repeat the board's visual language.
func _draw() -> void:
	var unit := minf(size.x, size.y)
	var tint := get_theme_color("accent", "Flow")
	var points := PackedVector2Array([Vector2(0.12,0.75), Vector2(0.47,0.75),
		Vector2(0.47,0.29), Vector2(0.85,0.29)])
	for i in points.size():
		points[i] *= unit
	draw_polyline(points, tint, unit*0.11, true)
	for p in points:
		draw_circle(p, unit*0.055, tint, true, -1, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0.72,0.09)*unit,
		Vector2(0.97,0.29)*unit, Vector2(0.72,0.49)*unit]), tint)
