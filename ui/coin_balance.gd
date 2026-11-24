extends Label

func set_balance(value: int) -> void:
	text = "%d Coins" % value
	queue_redraw()

func _draw() -> void:
	var font := get_theme_font("font")
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,get_theme_font_size("font_size")).x
	var point := Vector2(size.x-width-28,size.y/2)
	var gold := get_theme_color("gold","Flow")
	draw_circle(point,16,gold,true,-1,true)
	draw_arc(point,11,0,TAU,32,get_theme_color("bg","Flow"),2,true)
	draw_line(point+Vector2(0,-6),point+Vector2(0,6),get_theme_color("bg","Flow"),3,true)
