extends Control

signal tapped(id: String)

const Tap := preload("res://game/tap_tracker.gd")
const Model := preload("res://game/board_model.gd")
const INK := Color("#a7f2dd")
const DENIED := Color("#ffae83")
var model: Model
var tap := Tap.new()
var locked := false
var exiting := ""
var opacity := 1.0
var flashed := ""
var feedback: Tween

func spacing() -> float:
	return minf(size.x / (model.size.x + 0.6), size.y / (model.size.y + 0.6))

func center(cell: Vector2i) -> Vector2:
	return size * 0.5 + (Vector2(cell) + Vector2.ONE * 0.5 - Vector2(model.size) * 0.5) * spacing()

func hit(pos: Vector2) -> String:
	var best := INF
	var winner := ""
	for id in model.ids():
		var path := model.path_for(id)
		var distance := INF
		for i in range(1, path.size()):
			var closest := Geometry2D.get_closest_point_to_segment(pos, center(path[i-1]), center(path[i]))
			distance = minf(distance, pos.distance_to(closest))
		if distance > spacing() * 0.38:
			continue
		if is_equal_approx(distance, best):
			winner = ""
		elif distance < best:
			best = distance
			winner = id
	return winner

func _gui_input(event: InputEvent) -> void:
	if locked or model == null:
		return
	if tap.feed(event, spacing() * 0.24):
		var id := hit(event.position)
		if id != "" and hit(tap.start) == id:
			tapped.emit(id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and tap:
		tap.clear()

func reset_visuals() -> void:
	if feedback:
		feedback.kill()
	tap.clear()
	locked = false
	exiting = ""
	opacity = 1.0
	flashed = ""
	queue_redraw()

func reject(id: String) -> void:
	if feedback:
		feedback.kill()
	flashed = id
	queue_redraw()
	feedback = create_tween()
	feedback.tween_interval(0.18)
	feedback.tween_callback(func(): flashed = ""; queue_redraw())

func fade(value: float) -> void:
	opacity = value
	queue_redraw()

func _draw() -> void:
	if model == null:
		return
	var s := spacing()
	var field := Rect2(center(Vector2i.ZERO) - Vector2.ONE * s * 0.5, Vector2(model.size) * s)
	draw_rect(field.grow(s * 0.12), Color("#172f3a"))
	for x in model.size.x:
		for y in model.size.y:
			draw_circle(center(Vector2i(x,y)), s * 0.034, Color("#49616a"), true, -1, true)
	for id in model.ids():
		var path := model.path_for(id)
		var color := DENIED if flashed == id else INK
		if exiting == id:
			color.a = opacity
		var head := center(path[-1])
		var axis := (head - center(path[-2])).normalized()
		var side := axis.orthogonal()
		for i in range(path.size()-1):
			var point := center(path[i])
			var end := center(path[i+1])
			if i == path.size()-2:
				end -= axis * s * 0.13
			draw_line(point, end, color, s * 0.13, true)
			draw_circle(point, s * 0.065, color, true, -1, true)
		var base := head - axis * s * 0.19
		draw_colored_polygon(PackedVector2Array([head + axis*s*0.18, base+side*s*0.20, base-side*s*0.20]), color)
