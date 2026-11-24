extends "res://tests/capture_stage_1e_2a.gd"

func stage_id() -> String:
	return "1e_2b"

func reject_arrow() -> void:
	for id in app.game.model.ids():
		if not app.game.model.can_exit(id):
			app.game.move(id)
			return
	check(false,"expected a blocked arrow on current board")

func partial() -> void:
	var id: String = app.game.hint_candidate()
	app.game.move(id)
	await app.game.animation.finished

func write_phase() -> void:
	check(not DirAccess.dir_exists_absolute(store.directory),"unique profile")
	check(Fixture.seed_profile(store,1,120),"seed tutorial prefix and 120 local coins")
	mount()
	app.open_level(1)
	await snap("01-tutorial-no-lives")
	app.back()
	app.play()
	await snap("02-three-lives")
	await partial()
	reject_arrow()
	reject_arrow()
	check(app.game.lives==1 and app.game.board.flashed!="","two errors on partial board")
	await snap("03-one-life")
	reject_arrow()
	check(app.game.state==app.game.Attempt.FAILED and app.session.coins==120,"affordable failure")
	await snap("04-failed-affordable")
	var obstruction := store.directory.path_join("save_b.json.tmp")
	check(DirAccess.make_dir_absolute(obstruction)==OK,"obstruct actual staging path")
	app.buy_continue(app.game.generation,app.game)
	check(app.game.lives==0 and app.session.coins==120 and store.inspect().revision==1 and store.notice.contains("not purchased"),"refused purchase")
	await snap("09-continue-save-failed")
	check(DirAccess.remove_absolute(obstruction)==OK,"remove own obstruction")
	app.buy_continue(app.game.generation,app.game)
	check(app.game.lives==1 and app.session.coins==45 and app.game.model.ids().size()==app.game.total-1,"same partial board resumed")
	await snap("05-continued")
	await finish_board()
	check(store.inspect().count==2 and store.inspect().coins==50 and store.inspect().revision==3 and app.game.get_node("Layout/Overlay/Reward").text=="+5 Coins","paid continue then base reward")
	await snap("08-victory-after-continue")
	app.game.next_level()
	await partial()
	reject_arrow()
	check(app.game.level_id==3 and app.game.lives==2,"leave unfinished third level")

func read_phase() -> void:
	mount()
	check(app.session.completed_count()==2 and app.session.coins==50 and store.inspect().revision==3,"relaunch exact durable state")
	app.play()
	check(app.game.level_id==3 and app.game.lives==3 and app.game.total==app.game.model.ids().size(),"unfinished board starts anew")
	await partial()
	for i in 3: reject_arrow()
	check(app.game.lives==0 and app.game.get_node("%Continue").disabled,"insufficient funds")
	await snap("06-failed-insufficient")
	app.game.restart()
	check(app.game.lives==3 and app.game.model.ids().size()==app.game.total and app.session.coins==50,"free restart")
	await snap("07-free-restart")
	app.back()
	app.open_level(2)
	await finish_board()
	check(app.game.get_node("Layout/Overlay/Reward").text=="Already cleared" and store.inspect().coins==50 and store.inspect().revision==3,"replay keeps settled balance")
	app.back()
	check(Fixture.seed_profile(store,99,100),"dense screenshot fixture")
	mount()
	app.play()
	await partial()
	for i in 3: reject_arrow()
	for dims in [Vector2i(360,640),Vector2i(412,915)]:
		root.size = dims
		await settle()
		check(app.game.level_id==100 and app.game.state==app.game.Attempt.FAILED,"dense failed viewport")
		await snap("10-failed-360x640" if dims.x==360 else "11-failed-412x915",dims)
