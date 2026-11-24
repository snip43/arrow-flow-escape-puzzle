extends Control

const Model := preload("res://game/board_model.gd")
const Level := preload("res://levels/level_1.gd")
@onready var board = %Board
@onready var complete: Label = %Complete
var model := Model.new()
const SPEED := 25.0 # cells per second
var catalog := preload("res://levels/level_catalog.gd").new()
var level_id := 1
var generation := 0
var animation: Tween

func _ready() -> void:
	board.tapped.connect(move)
	%Restart.pressed.connect(restart)
	%Next.pressed.connect(next_level)
	restart()

func next_level() -> void:
	if complete.visible and level_id < 100:
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
	level_id = id
	generation += 1
	if animation:
		animation.kill()
	board.reset_visuals()
	board.model = model
	$Layout/Level.text = "LEVEL %d · %s" % [id,data.tier.to_upper()]
	complete.text = "ALL LEVELS COMPLETE" if id == 100 else "LEVEL COMPLETE"
	complete.visible = false
	%Next.visible = false
	return true

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
	%Next.visible = complete.visible and level_id < 100
	if not removed:
		push_error("Could not commit exit: " + id)
