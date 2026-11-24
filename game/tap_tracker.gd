extends RefCounted

const IDLE := -2
const MOUSE := -1
var owner := IDLE
var start := Vector2.ZERO
var cancelled := false
var tolerance := 0.0

var fingers := {}

func clear() -> void:
	owner = IDLE
	fingers.clear()
	cancelled = false

func feed(event: InputEvent, slop: float, eligible: bool) -> bool:
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
	if event is InputEventScreenTouch:
		if pressed:
			fingers[pointer] = true
			if fingers.size() > 1:
				cancelled = true
		else:
			fingers.erase(pointer)
	if pressed:
		if owner == IDLE and eligible and fingers.size() <= 1 and not cancelled:
			owner = pointer
			start = pos
			tolerance = slop
			cancelled = false
		return false
	if pointer != owner:
		if fingers.is_empty() and owner == IDLE:
			cancelled = false
		return false
	cancelled = cancelled or start.distance_to(pos) > tolerance
	if motion:
		return false
	var accepted: bool = not cancelled and not event.canceled
	owner = IDLE
	cancelled = not fingers.is_empty()
	return accepted
