extends SceneTree

const DIR := "res://docs/screenshots/stage_1c/"
var game
var failed := false

func _initialize() -> void:
	run.call_deferred()

func capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(DIR+label+".png")!=OK:
		failed = true

func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	game = preload("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for id in [1,2,10,20,21,40,60,61,80,100]:
		if not game.load_level(id): quit(1); return
		await capture("level-%03d"%id)
		if id not in [2,100]: continue
		var order: Array = game.catalog.get_level(id).solution
		for i in order.size():
			game.move(order[i])
			await game.animation.finished
			if id==100 and i==9: await capture("hard-partial")
		if not game.complete.visible: quit(1); return
		await capture("all-complete" if id==100 else "next-level")
	quit(1 if failed else 0)
