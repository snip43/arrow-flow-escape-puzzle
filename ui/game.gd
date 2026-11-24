extends Control

signal completed(id: int)
signal back_requested
signal attempt_changed
signal hint_requested(ticket: int)
signal continue_requested(ticket: int)
enum Attempt { ACTIVE, EXITING, FAILED, WON, LEFT }
const Economy := preload("res://game/economy.gd")
var state := Attempt.ACTIVE
var lives := 0
var continue_ticket := -1
var navigation_presses := {}
var purchase_pending := false
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
	connect_navigation(%Restart,restart)
	connect_navigation(%Next,next_level)
	connect_navigation(%Back,back_requested.emit)
	%Hint.button_down.connect(func(): hint_ticket = generation)
	%Hint.pressed.connect(request_hint)
	%Continue.text = "Continue · %d" % Economy.CONTINUE_COST
	%Continue.button_down.connect(func(): continue_ticket = generation)
	%Continue.pressed.connect(request_continue)
	resized.connect(update_safe_margins)
	update_safe_margins()
	restart()

func connect_navigation(button: Button, action: Callable) -> void:
	button.button_down.connect(func(): navigation_presses[button] = [generation,state])
	button.pressed.connect(func():
		# Programmatic activation has no pointer-down. For a real gesture,
		# the board behind the release must still be the one pressed.
		var valid: bool = navigation_presses.get(button,[generation,state]) == [generation,state]
		navigation_presses.erase(button)
		if valid and not purchase_pending: action.call()
	)

func next_level() -> void:
	if complete.visible and level_id < 100 and (not allow_next.is_valid() or allow_next.call(level_id + 1)):
		load_level(level_id + 1)

func restart() -> void:
	load_level(level_id)

func load_level(id: int) -> bool:
	if purchase_pending or state == Attempt.LEFT: return false
	var data := catalog.get_level(id)
	if data.has("error"):
		push_warning(str(data.error))
		return false
	if not model.load_level(data.size,data.paths):
		return false
	hint_ticket = -1
	continue_ticket = -1
	state = Attempt.ACTIVE
	lives = Economy.ATTEMPT_LIVES if id > 1 else 0
	$Layout/Lives.visible = id > 1
	$Layout/Lives.set_lives(lives)
	$Layout/Track.offset_left = 312 if id > 1 else 0
	$Layout/Failed.hide()
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
	if purchase_pending or state != Attempt.ACTIVE or model.path_for(id).is_empty():
		return
	if not model.can_exit(id):
		blocked_moves += 1
		board.reject(id)
		if level_id > 1:
			lives -= 1
			$Layout/Lives.set_lives(lives)
			if lives == 0:
				state = Attempt.FAILED
				invalidate_purchase_input()
				board.hinted = ""
				board.set_process_input(false)
				$Layout/Failed.show()
			attempt_changed.emit()
		return
	hint_ticket = -1
	board.reset_visuals(false)
	state = Attempt.EXITING
	board.locked = true
	board.hinted = ""
	attempt_changed.emit()
	board.motion = board.Motion.new(model.path_for(id), model.size)
	board.exiting = id
	animation = create_tween()
	animation.tween_method(board.advance, 0.0, board.motion.travel, board.motion.travel / SPEED)
	animation.tween_callback(finish_move.bind(id, generation))

func finish_move(id: String, ticket: int) -> void:
	if state != Attempt.EXITING or ticket != generation or board.exiting != id:
		return
	var removed := model.remove(id)
	board.reset_visuals(false)
	complete.visible = removed and model.ids().is_empty()
	state = Attempt.WON if complete.visible else Attempt.ACTIVE
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
	if not is_inside_tree() or level_id == 1 or state != Attempt.ACTIVE or not board.hinted.is_empty() or process_mode == Node.PROCESS_MODE_DISABLED:
		return ""
	var ids := model.ids()
	ids.sort()
	for id in ids:
		if model.can_exit(id): return id
	return ""

func request_hint() -> void:
	hint_requested.emit(hint_ticket)
	hint_ticket = -1

func request_continue() -> void:
	var ticket := continue_ticket
	continue_ticket = -1
	continue_requested.emit(ticket)

func invalidate_purchase_input() -> void:
	for button in navigation_presses:
		navigation_presses[button] = []
	hint_ticket = -1
	continue_ticket = -1
	board.tap.clear()
	# Failed intervals get distinct command tickets, including after a retry.
	# Never invalidate an exit tween waiting to commit its arrow.
	if state == Attempt.FAILED:
		generation += 1

func resume_board() -> void:
	if not purchase_pending or state != Attempt.FAILED: return
	state = Attempt.ACTIVE
	lives = Economy.CONTINUE_LIVES
	$Layout/Lives.set_lives(lives)
	$Layout/Failed.hide()
	board.reset_visuals()
	board.set_process_input(true)
	attempt_changed.emit()

func update_progress() -> void:
	var cleared := total - model.ids().size()
	$Layout/Count.text = "%d / %d cleared" % [cleared,total]
	$Layout/Track.max_value = total
	$Layout/Track.value = cleared

func update_safe_margins() -> void:
	preload("res://ui/safe_layout.gd").apply(self,$Layout)

func leave() -> void:
	if purchase_pending: return
	state = Attempt.LEFT
	continue_ticket = -1
	hint_ticket = -1
	board.hinted = ""
	generation += 1
	if animation:
		animation.kill()
	board.reset_visuals()
	board.set_process_input(false)
	process_mode = Node.PROCESS_MODE_DISABLED
