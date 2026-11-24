extends "res://tests/stage_1e_2b.gd"

func migration_and_wire() -> void:
	for version in [1,2]:
		store = Fixture.make_store()
		DirAccess.make_dir_recursive_absolute(store.directory)
		var old := store.directory.path_join(Store.SLOTS[0])
		var original := legacy(42,83) if version==1 else wallet_row(42,83,"119")
		raw(old,original)
		mount()
		var coins := 50 if version==1 else 119
		check(app.screen==app.Screen.MENU and durable(42,coins,83),"lazy legacy read")
		app.open_level(21)
		partial_move()
		buy()
		var baseline := Store.stamp(store.inspect())
		check(durable(42,coins-30,84) and baseline.checkpoint.removed.size()==1 and FileAccess.get_file_as_string(old)==original,"one v3 slot alongside intact legacy")
		mount()
		check(app.game.level_id==21 and app.game.board.hinted==baseline.checkpoint.hint and Store.stamp(store.inspect())==baseline,"reopen without migration fee")
		clean()

func bad_checkpoint() -> void:
	setup(1,240)
	app.play()
	partial_move()
	buy()
	var good := Store.stamp(store.inspect())
	var active := store.directory.path_join(Store.SLOTS[store.inspect().active])
	var doc := Store.document(good)
	var cp: Dictionary = doc.checkpoint
	var pretty := {"wallet":doc.wallet,"revision":doc.revision,"schema_version":3,"checkpoint":cp,"campaign":doc.campaign}
	raw(active,JSON.stringify(pretty,"  ",false))
	check(Store.stamp(store.inspect())==good,"formatted v3 with reordered fields")
	var bad_values := {
		"catalog":["old"],"origin":["other"],"level":[1,3,2.5],"kind":["other","continue"],
		"operation":["deadbeef","-0123456789abcdef0123456789abcde"],"used_hint":[false,1],
		"lives":[-1,0,1,4],"errors":[-1,2,2147483648],"state":["won","failed"],
		"hint":["unknown",blocker()],"removed":[[cp.removed[0],cp.removed[0]],["missing"],[blocker()]]
	}
	for key in bad_values:
		for value in bad_values[key]:
			var broken := doc.duplicate(true)
			broken.checkpoint[key] = value
			raw(active,JSON.stringify(broken))
			check(store.read_slot(active).state=="invalid" and store.restore()==1 and store.last_snapshot.coins==240 and store.notice==Store.FALLBACK and store.spending_blocked,"invalid paid record "+key)
	for key in cp:
		var broken := doc.duplicate(true)
		broken.checkpoint.erase(key)
		raw(active,JSON.stringify(broken))
		check(store.read_slot(active).state=="invalid","mandatory checkpoint field "+key)
	var encoded := JSON.stringify(doc)
	for payload in [encoded.replace('"level":2','"level":2,"level":2'),encoded.replace('"level":2','"level":2.00000000000000001'),encoded.replace('"lives":3','"lives":3,'),encoded.replace('"kind":','"extra":1,"kind":')]:
		raw(active,payload)
		check(store.read_slot(active).state=="invalid","strict v3 wire form")
	var damaged := FileAccess.get_file_as_string(active)
	mount()
	app.play()
	buy()
	check(app.session.coins==240 and not app.game.used_hint and FileAccess.get_file_as_string(active)==damaged,"fallback freezes spending and retains evidence")
	finish()
	var archived := active+"."+damaged.sha256_text()+".bak"
	check(FileAccess.get_file_as_string(archived)==damaged and store.inspect().coins==250,"verified archive before replacement")
	clean()

func full_comparison() -> void:
	setup(1,200)
	app.play()
	var sibling_path := store.directory.path_join(Store.SLOTS[1])
	raw(sibling_path,"damaged after restore")
	buy()
	check(store.spending_blocked and app.session.coins==200 and not app.game.used_hint and store.inspect().revision==1 and FileAccess.get_file_as_string(sibling_path)=="damaged after restore","new sibling damage detected during debit")
	clean()
	setup(1,200)
	app.open_selector()
	app.open_level(2)
	buy()
	var baseline := Store.stamp(store.inspect())
	var changed := baseline.duplicate(true)
	changed.checkpoint.operation = "ab".repeat(16)
	var path := store.directory.path_join(Store.SLOTS[store.inspect().active])
	raw(path,JSON.stringify(Store.document(changed)))
	check(not store.save(1,160,baseline,baseline.checkpoint) and store.needs_reload and Store.stamp(store.inspect())==changed,"receipt-only difference fails expected base")
	var sibling := store.directory.path_join(Store.SLOTS[1-store.inspect().active])
	raw(sibling,JSON.stringify(Store.document(baseline)))
	mount()
	check(store.inspect().conflict and store.spending_blocked and store.notice==Store.CONFLICT and app.game.used_hint,"same wallet and revision, conflicting receipt")
	var selected := Store.stamp(store.inspect())
	changed = selected.duplicate(true)
	changed.checkpoint.origin = "menu"
	check(not store.save(1,160,changed,selected.checkpoint) and store.needs_reload,"checkpoint-only stale base")
	clean()

func paid_lifecycle() -> void:
	setup(1,240,true)
	app.open_selector()
	app.open_level(2)
	partial_move()
	buy()
	var g = app.game
	var baseline := Store.stamp(store.inspect())
	check(not g.load_level(101) and Store.stamp(store.inspect())==baseline,"invalid destination preserves paid board")
	var selected: String = g.board.hinted
	store.fault = "before"
	block()
	check(g.lives==3 and g.blocked_moves==0 and g.board.hinted==selected and Store.stamp(store.inspect())==baseline,"rejected error rolled back")
	g.move(selected)
	g.animation.custom_step(5)
	check(g.removed_ids==baseline.checkpoint.removed and g.board.hinted==selected and Store.stamp(store.inspect())==baseline,"rejected move restores exact stable field")
	g.restart()
	app.back()
	check(app.game==g and app.screen==app.Screen.GAME and store.notice.contains("still saved") and Store.stamp(store.inspect())==baseline,"failed abandon retains board")
	store.fault = ""
	fail_board()
	mount()
	g = app.game
	check(g.state==g.Attempt.FAILED and g.used_hint and g.blocked_moves==3 and not g.board.is_processing_input() and g.board.hinted=="","failed checkpoint restores")
	pay()
	var continued := Store.stamp(store.inspect())
	check(continued.checkpoint.operation!=baseline.checkpoint.operation and continued.coins==135 and g.lives==1,"continue replaces hint receipt")
	buy()
	check(g.used_hint and store.inspect().checkpoint.kind=="hint" and store.inspect().coins==105,"new hint after continue")
	var seq: Array = app.catalog.get_level(2).solution
	for id in seq:
		if g.model.path_for(id).is_empty() or id==seq[-1]: continue
		g.move(id)
		g.animation.custom_step(5)
	var last := Store.stamp(store.inspect())
	store.fault = "before"
	g.move(seq[-1])
	g.animation.custom_step(5)
	check(Store.stamp(store.inspect())==last and g.model.ids()==[seq[-1]] and app.session.completed_count()==1 and app.session.coins==105 and not g.complete.visible,"failed paid victory rolled back as a unit")
	store.fault = "lost_ack"
	g.move(seq[-1])
	g.animation.custom_step(5)
	check(durable(2,110,last.revision+1) and not store.inspect().has("checkpoint") and g.complete.visible,"atomic base reward and checkpoint removal")
	mount()
	check(app.screen==app.Screen.MENU and app.session.completed_count()==2,"terminal snapshot opens menu")
	app.open_level(2)
	buy()
	finish()
	check(app.session.coins==80 and not store.inspect().has("checkpoint") and app.game.get_node("Layout/Overlay/Reward").text=="Already cleared","paid replay consumes checkpoint without reward")
	clean()

func unknown_move() -> void:
	setup(1,120,true)
	app.play()
	buy()
	var op: String = store.inspect().checkpoint.operation
	store.fault = "unknown"
	block()
	var on_disk := Store.stamp(store.inspect())
	check(app.game.recovery_locked and app.game.lives==3 and on_disk.checkpoint.lives==2,"unconfirmed gameplay write frozen")
	app.game.move(app.game.board.hinted)
	buy()
	app.back()
	check(Store.stamp(store.inspect())==on_disk and app.screen==app.Screen.GAME,"unresolved board cannot be overwritten")
	store.fault = ""
	mount()
	check(app.game.lives==2 and app.game.blocked_moves==1 and app.game.used_hint and app.session.coins==90 and store.inspect().checkpoint.operation==op,"reopen reconciles without debit")
	app.game.restart()
	check(app.game.lives==3 and not app.game.used_hint and app.session.coins==90 and not store.inspect().has("checkpoint"),"explicit discard without refund")
	mount()
	check(app.screen==app.Screen.MENU,"discard survives launch")
	clean()

func run() -> void:
	migration_and_wire()
	bad_checkpoint()
	full_comparison()
	paid_lifecycle()
	unknown_move()
	print("STAGE 1E.2C: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
