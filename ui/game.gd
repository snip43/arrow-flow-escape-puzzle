extends Control

const Model := preload("res://game/board_model.gd")
const Level := preload("res://levels/level_1.gd")
@onready var board = %Board
@onready var complete: Label = %Complete
var model := Model.new()
const SPEED := 25.0 # cells per second
var generation := 0
var animation: Tween

func _ready() -> void:
	board.tapped.connect(move)
	%Restart.pressed.connect(restart)
	restart()

func restart() -> void:
	generation += 1
	if animation:
		animation.kill()
	board.reset_visuals()
	board.model = model
	if not model.load_level(Level.SIZE, Level.arrows()):
		push_error("Invalid Level 1")
		board.locked = true
	complete.visible = false

func move(id: String) -> void:
	if board.locked or model.path_for(id).is_empty():
		return
	if not model.can_exit(id):
		board.reject(id)
		return
	board.reset_visuals(false)
	board.locked = true
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
	if not removed:
		push_error("Could not commit exit: " + id)
