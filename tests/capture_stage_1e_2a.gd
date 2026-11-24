extends "res://tests/capture_stage_1e_1.gd"

func stage_id() -> String:
	return "1e_2a"

func finish_board() -> void:
	for id in app.catalog.get_level(app.game.level_id).solution:
		if app.game.model.path_for(id).is_empty(): continue
		app.game.move(id)
		await app.game.animation.finished

func hint() -> void:
	app.buy_hint(app.game.generation,app.game)

func write_phase() -> void:
	check(not DirAccess.dir_exists_absolute(store.directory),"unused profile")
	mount()
	check(app.session.coins==50,"starting coins")
	await snap("01-menu-fresh")
	await win_tutorial()
	check(app.session.coins==55,"tutorial credit")
	await snap("02-tutorial-reward")
	app.game.next_level()
	await finish_board()
	check(app.session.coins==65,"easy perfect credit")
	await snap("03-easy-perfect")
	app.game.next_level()
	await snap("04-hint-before")
	hint()
	check(app.session.coins==35 and app.game.used_hint,"first paid hint")
	await snap("05-hint-active")
	app.game.move(app.game.board.hinted)
	await app.game.animation.finished
	hint()
	app.game.move(app.game.board.hinted)
	await app.game.animation.finished
	check(app.session.coins==5 and app.game.get_node("%Hint").disabled,"second purchase, funds insufficient")
	await snap("06-insufficient-coins")

func read_phase() -> void:
	mount()
	check(app.session.completed_count()==2 and app.session.coins==5 and store.inspect().revision==6,"restored exact wallet and prefix")
	check(app.game.level_id==3 and app.game.removed_ids.size()==2,"paid board resumed")
	app.back()
	await snap("08-relaunch-wallet")
	app.open_level(1)
	await finish_board()
	check(app.session.coins==5 and store.inspect().revision==7,"no replay credit")
	await snap("07-replay-no-reward")
	app.back()
	app.play()
	var tmp := store.directory.path_join("save_b.json.tmp")
	check(DirAccess.make_dir_absolute(tmp)==OK,"obstruct staging file")
	await finish_board()
	check(app.dirty and store.inspect().coins==5 and app.session.coins==15,"dirty victory")
	await snap("09-save-failed")
	DirAccess.remove_absolute(tmp)
	app.back()
	check(not app.dirty,"retry saved reward")
	check(Fixture.seed_profile(store,99,50),"dense test fixture")
	mount()
	app.play()
	for dims in [Vector2i(360,640),Vector2i(412,915)]:
		root.size = dims
		await settle()
		await snap("10-game-360x640" if dims.x==360 else "11-game-412x915",dims)
