extends Control

signal completed(id: int)
signal back_requested
signal attempt_changed
signal hint_requested(ticket: int)
var blocked_moves := 0
var used_hint := false
var hint_ticket := -1
var reward_ticket := -1

const Model := preload("res://game/board_model.gd")
const Level := preload("res://levels/level_1.gd")
@onready var board = %Board
@onready var complete: Label = %Complete
var model := Model.new()
const SPEED := 25.0 # cells per second
var catalog := preload("res://levels/level_catalog.gd").new()
var level_id := 1
var total := 0
var allow_next: Callable
var generation := 0
var animation: Tween

func _ready() -> void:
	board.tapped.connect(move)
	%Restart.pressed.connect(restart)
	%Next.pressed.connect(next_level)
	%Back.pressed.connect(back_requested.emit)
	%Hint.button_down.connect(func(): hint_ticket = generation)
	%Hint.pressed.connect(request_hint)
	resized.connect(update_safe_margins)
	update_safe_margins()
	restart()

func next_level() -> void:
	if complete.visible and level_id < 100 and (not allow_next.is_valid() or allow_next.call(level_id + 1)):
		load_level(level_id + 1)

func restart() -> void:
	load_level(level_id)

func load_level(id: int) -> bool:
	var data := catalog.get_level(id)
	if data.has("error"):
		push_warning(str(data.error))
		return false
	if not model.load_level(data.size,data.paths):
		return false
	hint_ticket = -1
	blocked_moves = 0
	used_hint = false
	board.hinted = ""
	$Layout/Overlay/Reward.hide()
	level_id = id
	generation += 1
	if animation:
		animation.kill()
	board.reset_visuals()
	board.model = model
	total = model.ids().size()
	update_progress()
	$Layout/Level.text = "LEVEL %d" % id
	$Layout/Tier.text = data.tier
	$Layout/Tutorial.visible = id == 1
	$Layout/Overlay.hide()
	board.set_process_input(true)
	complete.text = "ALL LEVELS COMPLETE" if id == 100 else "LEVEL COMPLETE"
	complete.visible = false
	%Next.visible = false
	attempt_changed.emit()
	return true

func move(id: String) -> void:
	if board.locked or model.path_for(id).is_empty():
		return
	if not model.can_exit(id):
		blocked_moves += 1
		board.reject(id)
		return
	hint_ticket = -1
	board.reset_visuals(false)
	board.locked = true
	board.hinted = ""
	attempt_changed.emit()
	board.motion = board.Motion.new(model.path_for(id), model.size)
	board.exiting = id
	animation = create_tween()
	animation.tween_method(board.advance, 0.0, board.motion.travel, board.motion.travel / SPEED)
	animation.tween_callback(finish_move.bind(id, generation))

func finish_move(id: String, ticket: int) -> void:
	if ticket != generation or board.exiting != id:
		return
	var removed := model.remove(id)
	board.reset_visuals(false)
	complete.visible = removed and model.ids().is_empty()
	%Next.visible = complete.visible and level_id < 100
	if removed:
		update_progress()
	if complete.visible:
		board.tap.clear()
		board.set_process_input(false)
		$Layout/Tutorial.hide()
		$Layout/Overlay.show()
		completed.emit(level_id)
	attempt_changed.emit()
	if not removed:
		push_error("Could not commit exit: " + id)

func hint_candidate() -> String:
	if not is_inside_tree() or level_id == 1 or complete.visible or board.locked or not board.hinted.is_empty() or process_mode == Node.PROCESS_MODE_DISABLED:
		return ""
	var ids := model.ids()
	ids.sort()
	for id in ids:
		if model.can_exit(id): return id
	return ""

func request_hint() -> void:
	hint_requested.emit(hint_ticket)
	hint_ticket = -1

func update_progress() -> void:
	var cleared := total - model.ids().size()
	$Layout/Count.text = "%d / %d cleared" % [cleared,total]
	$Layout/Track.max_value = total
	$Layout/Track.value = cleared

func update_safe_margins() -> void:
	preload("res://ui/safe_layout.gd").apply(self,$Layout)

func leave() -> void:
	hint_ticket = -1
	board.hinted = ""
	generation += 1
	if animation:
		animation.kill()
	board.reset_visuals()
	board.set_process_input(false)
	process_mode = Node.PROCESS_MODE_DISABLED
