extends Label

const Economy := preload("res://game/economy.gd")
var lives := 0

func set_lives(value: int) -> void:
	lives = value
	text = "Lives %d/%d" % [value, Economy.ATTEMPT_LIVES]
	queue_redraw()

func _draw() -> void:
	# A filled heart becomes an empty outline when that life is lost.
	var shape := PackedVector2Array([
		Vector2(0,13),Vector2(-12,1),Vector2(-14,-4),Vector2(-13,-9),
		Vector2(-8,-12),Vector2(-4,-12),Vector2(0,-8),Vector2(4,-12),
		Vector2(8,-12),Vector2(13,-9),Vector2(14,-4),Vector2(12,1),Vector2(0,13)
	])
	for i in Economy.ATTEMPT_LIVES:
		draw_set_transform(Vector2(size.x-15-(Economy.ATTEMPT_LIVES-1-i)*36,size.y/2))
		if i < lives:
			draw_colored_polygon(shape.slice(0,-1),get_theme_color("coral","Flow"))
		draw_polyline(shape,get_theme_color("coral" if i<lives else "muted","Flow"),2.5,true)
