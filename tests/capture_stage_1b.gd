extends SceneTree

const DIR := "res://docs/screenshots/stage_1b/"
var game
var failed := false

func _initialize() -> void:
	run.call_deferred()

func snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(DIR + name + ".png") != OK:
		failed = true

func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR + "motion")
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await snap("01-initial")
	game.move("A")
	await snap("02-blocked")
	game.move("B")
	await game.animation.finished
	game.move("A")
	game.animation.pause()
	var prev := 0.0
	for d in [0.0,0.35,1.0,3.0,5.5,7.5,9.0]:
		game.animation.custom_step((d-prev)/game.SPEED)
		prev = d
		await snap("motion/A-%03d" % roundi(d*10))
		if d == 0.35:
			await snap("03-bent-arrow-moving")
		if d == 9.0:
			await snap("04-bent-arrow-tail-exit")
	game.animation.play()
	await game.animation.finished
	await snap("05-partial")
	for id in game.Level.SOLUTION.slice(2):
		game.move(id)
		await game.animation.finished
	await snap("06-complete")
	quit(1 if failed or not game.complete.visible else 0)
