extends SceneTree

const DIR := "res://docs/screenshots/stage_1d_1/"
var game
var failed := false

func _initialize() -> void:
	run.call_deferred()

func snap(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame.get_size() != root.size or frame.save_png(DIR + label + ".png") != OK:
		failed = true

func finish_level() -> void:
	for id in game.catalog.get_level(game.level_id).solution:
		if game.model.path_for(id).is_empty(): continue
		game.move(id)
		await game.animation.finished

func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	game = preload("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	root.size = Vector2i(405,720)
	await snap("01-tutorial-405x720")
	for entry in [[10,"02-easy-405x720"],[40,"03-normal-405x720"],[100,"04-hard-405x720"]]:
		game.load_level(entry[0])
		await snap(entry[1])
	game.load_level(1)
	game.move("A")
	await snap("05-blocked-405x720")
	game.move("B")
	await game.animation.finished
	game.move("A")
	game.animation.pause()
	game.animation.custom_step(0.4/game.SPEED)
	await snap("06-motion-405x720")
	game.animation.play()
	await game.animation.finished
	await snap("07-partial-405x720")
	await finish_level()
	await snap("08-victory-next-405x720")
	game.load_level(100)
	await finish_level()
	await snap("09-final-victory-405x720")
	game.restart()
	root.size = Vector2i(360,640)
	await snap("10-hard-360x640")
	root.size = Vector2i(412,915)
	await snap("11-hard-412x915")
	quit(1 if failed else 0)
