extends Control

signal tapped(id: String)

const Tap := preload("res://game/tap_tracker.gd")
const Model := preload("res://game/board_model.gd")
var model: Model
var tap := Tap.new()
var locked := false
var exiting := ""
const Motion := preload("res://game/arrow_motion.gd")
const HIT_RADIUS := 0.38
const SLOP := 0.24
var motion: Motion
var distance := 0.0
var clip := Control.new()
var ink := Node2D.new()

func _ready() -> void:
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	add_child(clip)
	clip.add_child(ink)
	ink.draw.connect(draw_arrows)

var flashed := ""
var feedback: Tween

func spacing() -> float:
	return minf(size.x / (model.size.x + 0.6), size.y / (model.size.y + 0.6))

func center(cell: Vector2) -> Vector2:
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
		if distance > spacing() * HIT_RADIUS:
			continue
		if is_equal_approx(distance, best):
			winner = ""
		elif distance < best:
			best = distance
			winner = id
	return winner

func _input(event: InputEvent) -> void:
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		handle_pointer(make_input_local(event))

func handle_pointer(event: InputEvent) -> void:
	if model == null:
		return
	if tap.feed(event, spacing() * SLOP, not locked and Rect2(Vector2.ZERO, size).has_point(event.position)) and not locked:
		var id := hit(event.position)
		if id != "" and hit(tap.start) == id:
			tapped.emit(id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and tap:
		tap.clear()

func reset_visuals(reset_input := true) -> void:
	if feedback:
		feedback.kill()
	if reset_input:
		tap.clear()
	locked = false
	exiting = ""
	motion = null
	distance = 0.0
	flashed = ""
	queue_redraw()

func reject(id: String) -> void:
	if feedback:
		feedback.kill()
	flashed = id
	queue_redraw()
	feedback = create_tween()
	feedback.tween_interval(0.22)
	feedback.tween_callback(func(): flashed = ""; queue_redraw())

func advance(value: float) -> void:
	distance = value
	queue_redraw()

func _draw() -> void:
	if model == null:
		return
	var s := spacing()
	var field := Rect2(center(Vector2i.ZERO) - Vector2.ONE * s * 0.5, Vector2(model.size) * s)
	var dot := get_theme_color("dot","Flow")
	for x in model.size.x:
		for y in model.size.y:
			draw_circle(center(Vector2i(x,y)), s * 0.028, dot, true, -1, true)
	clip.position = field.position
	clip.size = field.size
	ink.position = -field.position
	ink.queue_redraw()

func draw_arrows() -> void:
	var s := spacing()
	for id in model.ids():
		var path := PackedVector2Array(model.path_for(id))
		if exiting == id:
			path = motion.section(distance)
		var color := get_theme_color("coral" if flashed == id else "mint","Flow")
		var stroke := s * (0.165 if flashed == id else 0.138)
		var head := center(path[-1])
		var axis := (head - center(path[-2])).normalized()
		var side := axis.orthogonal()
		for i in range(path.size()-1):
			var point := center(path[i])
			var end := center(path[i+1])
			if i == path.size()-2:
				end -= axis * minf(s * 0.13, point.distance_to(end))
			ink.draw_line(point, end, color, stroke, true)
			ink.draw_circle(point, stroke * 0.5, color, true, -1, true)
		var base := head - axis * s * 0.21
		ink.draw_colored_polygon(PackedVector2Array([head + axis*s*0.22, base+side*s*0.215, base-side*s*0.215]), color)
