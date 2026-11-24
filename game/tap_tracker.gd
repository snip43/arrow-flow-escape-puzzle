extends RefCounted

const IDLE := -2
const MOUSE := -1
var owner := IDLE
var start := Vector2.ZERO
var cancelled := false
var tolerance := 0.0

func clear() -> void:
	owner = IDLE
	cancelled = false

func feed(event: InputEvent, slop: float) -> bool:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	var pointer := MOUSE
	var motion := false
	var pressed := false
	var pos: Vector2
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		pointer = event.index
		motion = event is InputEventScreenDrag
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return false
	elif event is InputEventMouseMotion:
		motion = true
	else:
		return false
	pos = event.position
	if not motion:
		pressed = event.pressed
	if pressed:
		if owner == IDLE:
			owner = pointer
			start = pos
			tolerance = slop
			cancelled = false
		return false
	if pointer != owner:
		return false
	cancelled = cancelled or start.distance_to(pos) > tolerance
	if motion:
		return false
	var accepted: bool = not cancelled and not event.canceled
	clear()
	return accepted
