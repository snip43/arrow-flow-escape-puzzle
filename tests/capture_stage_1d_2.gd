extends SceneTree

const DIR := "res://docs/screenshots/stage_1d_2/"
var app
var failed := false

func _initialize() -> void:
	run.call_deferred()

func snap(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame.get_size()!=Vector2i(405,720) or frame.save_png(DIR+label+".png")!=OK:
		failed = true

func win() -> void:
	for id in app.catalog.get_level(app.game.level_id).solution:
		app.game.move(id)
		await app.game.animation.finished

func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	app = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(app)
	root.size = Vector2i(405,720)
	await snap("01-main-fresh")
	app.open_selector()
	await snap("03-levels-fresh")
	app.back()
	app.play()
	await snap("07-game-tutorial")
	await win()
	await snap("09-victory-next")
	app.back()
	await snap("02-main-continue")
	app.open_selector()
	await snap("04-levels-progress")
	# Use scroll coordinates of the actual first Hard card; include the last Normal row.
	app.scroll.scroll_vertical += roundi(app.cards[61].global_position.y-app.scroll.global_position.y-app.scroll.size.y*0.45)
	await snap("05-normal-hard")
	app.scroll.scroll_vertical = int(app.scroll.get_v_scroll_bar().max_value)
	await snap("06-levels-bottom")
	# Test-only setup: exercise the same sequential unlock API up to the final board.
	for id in range(2,100):
		app.session.record_completion(id)
	app.open_level(100)
	await snap("08-game-hard")
	await win()
	await snap("10-final-victory")
	quit(1 if failed or app.session.completed_count()!=100 else 0)
