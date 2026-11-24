extends "res://tests/stage_1e_2a.gd"

# Reuse the accepted isolated fixture, real viewport input and rename/readback faults.
const WINDOWS := [Vector2i(360,640),Vector2i(405,720),Vector2i(412,915),Vector2i(768,1024),Vector2i(900,600)]

class ReentrantStore extends Store:
	var during_publish: Callable
	func publish(tmp: String, path: String) -> bool:
		if during_publish.is_valid(): during_publish.call()
		return super.publish(tmp,path)

func contents() -> Dictionary:
	var paths := {}
	for id in app.game.model.ids():
		paths[id] = app.game.model.path_for(id)
	return paths

func pose() -> Array:
	var board = app.game.board
	return [board.get_global_rect(),board.spacing(),board.center(Vector2i.ZERO),board.center(board.model.size-Vector2i.ONE)]

func position_of(id: String) -> Vector2:
	var g = app.game
	return g.board.get_global_transform_with_canvas()*g.board.center(g.model.path_for(id)[0])

func blocker() -> String:
	for id in app.game.model.ids():
		if not app.game.model.can_exit(id): return id
	check(false,"expected real dependency")
	return ""

func fail_board() -> void:
	var errors: int = app.game.lives
	var at := position_of(blocker())
	for i in errors: click(at)
	check(app.game.state==app.game.Attempt.FAILED and app.game.lives==0,"entered failed via viewport")

func pay() -> void:
	app.buy_continue(app.game.generation,app.game)

func durable(count: int, coins: int, revision: int) -> bool:
	var state := Store.stamp(store.inspect())
	return state.count==count and state.coins==coins and state.revision==revision

func partial_move() -> void:
	var g = app.game
	var id: String = g.hint_candidate()
	click(position_of(id))
	check(g.state==g.Attempt.EXITING and g.board.locked,"real exit started")
	g.animation.custom_step(4)
	check(g.state==g.Attempt.ACTIVE and not g.board.locked,"exit committed")

func standalone() -> void:
	var g = preload("res://scenes/game.tscn").instantiate()
	g.level_id = 2
	root.add_child(g)
	var id: String = g.model.ids().filter(func(key): return not g.model.can_exit(key))[0]
	var at: Vector2 = g.board.get_global_transform_with_canvas()*g.board.center(g.model.path_for(id)[0])
	for i in 3: click(at)
	check(g.state==g.Attempt.FAILED and g.lives==0 and g.get_node("%Continue").disabled and g.continue_requested.get_connections().is_empty(),"standalone failure has no economy provider")
	click(g.get_node("%Restart").get_global_rect().get_center())
	check(g.lives==3 and g.blocked_moves==0 and g.board.is_processing_input(),"standalone free restart")
	g.free()

func rules() -> void:
	store = Fixture.make_store()
	mount()
	app.play()
	var g = app.game
	for i in 7: click(position_of(blocker()))
	pay()
	buy()
	check(g.blocked_moves==7 and g.state==g.Attempt.ACTIVE and not g.get_node("Layout/Lives").visible and not g.get_node("%Continue").is_visible_in_tree(),"tutorial unlimited")
	finish()
	check(durable(1,55,1) and g.get_node("Layout/Overlay/Reward").text=="+5 Coins","tutorial pays only five")
	clean()
	for level in [2,21,61,100]:
		setup(level-1,0)
		app.open_selector()
		app.open_level(level)
		g = app.game
		var initial := contents()
		var geometry := pose()
		check(g.lives==3 and g.blocked_moves==0,"three lives on tier boundary")
		partial_move()
		var left := contents()
		var at := position_of(blocker())
		for life in [2,1,0]:
			click(at)
			check(g.lives==life and g.blocked_moves==3-life and g.board.flashed!="" and contents()==left and pose()==geometry,"one coral refusal, same cells")
		var failed_ticket: int = g.generation
		click(at)
		g.move(blocker())
		g.finish_move(blocker(),failed_ticket)
		app.level_completed(level,g)
		g.next_level()
		buy()
		pay()
		check(g.generation==failed_ticket and g.blocked_moves==3 and g.board.exiting=="" and not g.board.is_processing_input(),"no fourth refusal or exit")
		check(not g.complete.visible and not g.get_node("%Next").is_visible_in_tree() and not g.get_node("%Hint").is_visible_in_tree() and durable(level-1,0,1),"failed excludes victory, hint and payment")
		click(g.get_node("%Restart").get_global_rect().get_center())
		check(contents()==initial and pose()==geometry and g.lives==3 and g.blocked_moves==0 and not g.used_hint,"free restart restores board and lives")
		fail_board()
		g.restart()
		finish()
		var base := 5 if level==2 else (10 if level==21 else 15)
		check(durable(level,base+5,2),"free win after repeated zero-coin restarts")
		pay()
		check(g.state==g.Attempt.WON and not g.get_node("Layout/Failed").visible,"won excludes failure")
		app.back()
		check(app.screen==app.Screen.LEVELS and app.session.completed_count()==level,"back returns to selector")
		clean()

func input_edges() -> void:
	setup(99,200)
	app.play()
	var g = app.game
	var at := position_of(blocker())
	click(g.board.get_global_rect().position+Vector2.ONE)
	g.move("missing")
	finger(at,0,true)
	var drag := InputEventScreenDrag.new()
	drag.position = at+Vector2(110,0)
	root.push_input(drag,true)
	drag.position = at
	root.push_input(drag,true)
	finger(at,0,false)
	finger(at,0,true)
	var cancel := InputEventScreenTouch.new()
	cancel.position = at
	cancel.canceled = true
	root.push_input(cancel,true)
	finger(at,0,true)
	finger(at,1,true)
	finger(at,1,false)
	finger(at,0,false)
	mouse(at,true)
	g.board.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	mouse(at,false)
	check(g.lives==3 and g.blocked_moves==0 and not g.board.locked,"miss, unknown, drag, cancel, multitouch and focus loss ignored on dense board")
	finger(at,0,true)
	finger(at,0,false)
	check(g.lives==2 and g.blocked_moves==1,"screen touch charges one life")
	var free_id: String = g.hint_candidate()
	click(position_of(free_id))
	click(at)
	finger(at,0,true)
	finger(at,0,false)
	check(g.state==g.Attempt.EXITING and g.lives==2 and g.blocked_moves==1,"tween input ignored")
	var old: int = g.generation
	g.restart()
	g.finish_move(free_id,old)
	check(g.lives==3 and g.total==g.model.ids().size(),"stale exit after restart")
	buy()
	check(g.lives==3 and g.used_hint and durable(99,170,2),"hint leaves lives intact")
	fail_board()
	check(g.board.hinted=="" and g.used_hint,"failed clears highlight only")
	var button: Button = g.get_node("%Continue")
	var center := button.get_global_rect().get_center()
	mouse(center,true)
	g.restart()
	fail_board()
	mouse(center,false)
	app.buy_continue(old,g)
	check(g.lives==0 and durable(99,170,6),"old release and ticket cannot buy in new failure")
	mouse(center,true)
	app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var out_ticket: int = g.generation
	app.buy_continue(out_ticket,g)
	app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	mouse(center,false)
	check(g.lives==0 and durable(99,170,6),"focus interrupted press")
	app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	pay()
	check(g.lives==0 and durable(99,170,6),"no payment while paused")
	app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await touch_button(button)
	check(g.lives==1 and durable(99,95,7),"fresh native GUI touch after resume buys one life")
	buy()
	check(g.used_hint and g.board.hinted!="" and durable(99,65,8),"hint works after continue")
	fail_board()
	check(g.used_hint and g.board.hinted=="","second failure keeps used_hint")
	old = g.generation
	app.back()
	app.play()
	app.buy_continue(old,g)
	check(g.state==g.Attempt.LEFT and app.game.lives==3 and durable(99,65,10),"old detached scene cannot spend")
	await process_frame
	await process_frame
	check(not is_instance_valid(g),"old scene freed")
	app.buy_continue(old,g)
	app.buy_continue(old,null)
	check(durable(99,65,10),"removed source ignored")
	clean()

func stale_ui() -> void:
	setup(1,180)
	app.play()
	var g = app.game
	buy()
	block()
	block()
	var nav: Button = g.get_node("%Restart")
	mouse(nav.get_global_rect().get_center(),true)
	block()
	mouse(nav.get_global_rect().get_center(),false)
	check(g.state==g.Attempt.FAILED and g.lives==0,"restart pressed in a previous state cannot release on failure")
	var resume: Button = g.get_node("%Continue")
	var center := resume.get_global_rect().get_center()
	for mode in ["focus","pause"]:
		mouse(center,true)
		var ticket: int = g.generation
		var stop := Node.NOTIFICATION_APPLICATION_FOCUS_OUT if mode=="focus" else Node.NOTIFICATION_APPLICATION_PAUSED
		var start := Node.NOTIFICATION_APPLICATION_FOCUS_IN if mode=="focus" else Node.NOTIFICATION_APPLICATION_RESUMED
		app.notification(stop)
		pay()
		check(resume.disabled and durable(1,150,5),"no purchase while "+mode)
		app.notification(start)
		mouse(center,false)
		app.buy_continue(ticket,g)
		check(g.lives==0 and durable(1,150,5),"old release invalidated by "+mode)
	click(center)
	check(g.lives==1 and g.blocked_moves==3 and g.used_hint and g.board.hinted=="" and durable(1,75,6),"paid continue preserves earlier hint usage")
	fail_board()
	mouse(center,true)
	g.restart()
	for i in 3: block()
	mouse(center,false)
	check(g.lives==0 and durable(1,75,8),"held continue cannot activate on later failure at the same screen coordinates")
	click(center)
	check(g.lives==1 and durable(1,0,9),"fresh press in new attempt succeeds")
	clean()

func prices() -> void:
	for balance in [0,74,75,76,150]:
		setup(1,balance)
		app.play()
		var g = app.game
		pay()
		check(durable(1,balance,1),"active continue ignored")
		partial_move()
		fail_board()
		var paths := contents()
		var button: Button = g.get_node("%Continue")
		var valid: bool = balance>=75
		check(button.disabled!=valid,"button follows affordability")
		var old: int = g.generation
		click(button.get_global_rect().get_center())
		app.buy_continue(old,g)
		if not valid:
			check(g.state==g.Attempt.FAILED and g.lives==0 and durable(1,balance,1) and contents()==paths,"insufficient remains failed")
		else:
			check(g.lives==1 and g.state==g.Attempt.ACTIVE and g.blocked_moves==3 and durable(1,balance-75,2) and contents()==paths,"one explicit debit with full occupancy preserved")
			if balance==150:
				fail_board()
				app.buy_continue(old,g)
				check(g.lives==0 and durable(1,75,3),"first command cannot pay for a second failure")
				click(button.get_global_rect().get_center())
				check(g.lives==1 and g.blocked_moves==4 and durable(1,0,4),"second explicit purchase")
			var before: Dictionary = Store.stamp(store.inspect())
			var final_revision: int = before.revision+g.model.ids().size()
			finish()
			check(durable(2,before.coins+5,final_revision) and g.get_node("Layout/Overlay/Reward").text=="+5 Coins","only base after continue")
			g.restart()
			finish()
			check(durable(2,before.coins+5,final_revision) and g.get_node("Layout/Overlay/Reward").text=="Already cleared","replay no reward or refund")
		clean()

func transaction_faults() -> void:
	setup(1,150,true)
	app.play()
	partial_move()
	fail_board()
	var paths := contents()
	var old: int = app.game.generation
	store.fault = "before"
	pay()
	check(app.game.lives==0 and durable(1,150,1) and app.session.coins==150 and contents()==paths and store.notice.contains("not purchased"),"refusal before rename")
	store.fault = "lost_ack"
	app.buy_continue(old,app.game)
	check(durable(1,150,1),"declined command cannot retry itself")
	pay()
	pay()
	check(app.game.lives==1 and durable(1,75,2) and app.session.coins==75 and contents()==paths,"lost ack reconciled exactly once in running process")
	fail_board()
	store.fault = "unknown"
	pay()
	check(store.needs_reload and app.game.lives==0 and app.session.coins==75 and durable(1,0,4) and contents()==paths,"unreadable published state freezes spending")
	pay()
	app.retry_save()
	app.game.restart()
	app.back()
	check(durable(1,0,4) and app.screen==app.Screen.GAME and app.game.lives==0 and store.needs_reload,"unconfirmed abandonment stays put without redebit")
	mount()
	check(app.session.coins==0 and not store.needs_reload,"reload resolves frozen wallet")
	clean()
	for cause in ["dirty","future","stale","limit","io"]:
		setup(1,150,true)
		var slot := store.directory.path_join(Store.SLOTS[1])
		match cause:
			"future": raw(slot,'{"schema_version":4}')
			"limit": raw(slot,wallet_row(1,Store.MAX_REVISION,"150"))
			"io": check(DirAccess.make_dir_absolute(slot)==OK,"unreadable slot")
		mount()
		app.play()
		if cause=="dirty":
			store.fault = "before"
			finish()
			app.game.next_level()
		elif cause=="stale":
			check(Fixture.seed_profile(store,1,120),"external newer profile")
		fail_board()
		var disk := Store.stamp(store.inspect())
		var coins: int = app.session.coins
		pay()
		check(app.game.lives==0 and app.game.state==app.game.Attempt.FAILED and app.session.coins==coins and Store.stamp(store.inspect())==disk and app.game.get_node("%Continue").disabled,"guarded payment "+cause)
		check(app.game.get_node("Layout/SaveNotice").is_visible_in_tree(),"visible warning "+cause)
		app.game.restart()
		check(app.game.lives==3 and app.game.state==app.game.Attempt.ACTIVE,"restart while blocked "+cause)
		if cause=="io": DirAccess.remove_absolute(slot)
		clean()
	store = ReentrantStore.new(Fixture.unique_name())
	check(Fixture.seed_profile(store,1,150),"reentrancy fixture")
	mount()
	app.play()
	fail_board()
	var g = app.game
	store.during_publish = func():
		pay()
		buy()
		g.restart()
		g.load_level(1)
		app.back()
		check(g==app.game and g.state==g.Attempt.FAILED and g.lives==0 and app.session.coins==150,"pending debit excludes competing commands and navigation")
	pay()
	store.during_publish = Callable()
	check(g.lives==1 and durable(1,75,2),"one published reentrant transaction")
	clean()

func layout_matrix() -> void:
	for dims in WINDOWS:
		setup(99,75,true)
		root.size = dims
		app.open_level(1)
		await process_frame
		await process_frame
		check(not app.game.get_node("Layout/Lives").visible and not app.game.get_node("%Continue").is_visible_in_tree(),"tutorial layout")
		app.back()
		app.play()
		var g = app.game
		var geometry := pose()
		var hud: Label = g.get_node("Layout/Lives")
		var board: Rect2 = g.board.get_global_rect()
		var failed: Control = g.get_node("Layout/Failed")
		var resume: Button = g.get_node("%Continue")
		var warning: Label = g.get_node("Layout/SaveNotice")
		for name in ["Wallet","Level","Tier","Count","Track"]:
			check(not hud.get_global_rect().intersects(g.get_node("Layout/"+name).get_global_rect()),"HUD clear of "+name)
		var id: String = g.hint_candidate()
		g.move(id)
		check(pose()==geometry and g.state==g.Attempt.EXITING,"stable geometry during exit")
		g.animation.custom_step(4)
		for life in [3,2,1,0]:
			if life<3: click(position_of(blocker()))
			check(hud.text=="Lives %d/3"%life and label_fits(hud,104) and pose()==geometry,"HUD and geometry "+str(life))
		check(failed.get_global_rect()==board and failed.visible and not resume.disabled,"failed overlay covers board")
		var panel: Control = failed.get_node("Panel")
		var title: Label = panel.get_node("Title")
		var desc: Label = panel.get_node("Description")
		check(label_fits(title) and label_fits(desc) and board.encloses(panel.get_global_rect()) and not title.get_global_rect().intersects(desc.get_global_rect()) and not desc.get_global_rect().intersects(resume.get_global_rect()),"failure text and button fit")
		var controls := [resume,g.get_node("%Restart"),g.get_node("%Back")]
		for c in controls:
			var rect: Rect2 = c.get_global_rect()
			var pixels: Rect2 = root.get_final_transform()*rect
			check(c.is_visible_in_tree() and root.get_visible_rect().encloses(rect) and minf(pixels.size.x,pixels.size.y)>=47.99,"reachable target "+c.name)
		check(not board.intersects(controls[1].get_global_rect()) and not board.intersects(controls[2].get_global_rect()),"board not covering navigation")
		store.fault = "before"
		pay()
		check(warning.visible and label_fits(warning) and not board.intersects(warning.get_global_rect()) and not controls[1].get_global_rect().intersects(warning.get_global_rect()) and pose()==geometry,"failed save warning in reserved footer")
		store.fault = ""
		pay()
		check(not failed.visible and g.lives==1 and pose()==geometry,"continue geometry")
		fail_board()
		check(resume.disabled and warning.text=="Not enough coins" and label_fits(desc) and pose()==geometry,"unaffordable layout")
		g.restart()
		check(g.lives==3 and pose()==geometry,"restart geometry")
		finish()
		check(not failed.visible and g.complete.visible and pose()==geometry,"victory geometry")
		print("WINDOW ",dims," board_px=",(root.get_final_transform()*board).size," continue_px=",(root.get_final_transform()*resume.get_global_rect()).size)
		clean()

func run() -> void:
	standalone()
	rules()
	await input_edges()
	stale_ui()
	prices()
	transaction_faults()
	await layout_matrix()
	print("STAGE 1E.2B: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
