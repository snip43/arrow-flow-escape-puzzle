extends "res://tests/capture_stage_1e_2b.gd"

# Only this test subclass stops the process at a synchronous storage boundary.
class CrashStore extends Store:
	var gate: Callable
	var operation := ""
	func save(count: Variant, coins: Variant, expected: Dictionary, checkpoint := {}) -> bool:
		operation = checkpoint.get("operation","")
		var ok := super.save(count,coins,expected,checkpoint)
		if ok and gate.is_valid(): gate.call("confirmed")
		return ok
	func publish(tmp: String, path: String) -> bool:
		if gate.is_valid(): gate.call("before")
		var ok := super.publish(tmp,path)
		if ok and gate.is_valid(): gate.call("renamed")
		return ok

var kind: String
var boundary: String
var goal := ""
var marker: String
var previous: Dictionary
var expected: Dictionary
var purchase_cut := false
var phase: String

func stage_id() -> String: return "1e_2c"

func stop_at(point: String) -> void:
	if point!=goal: return
	if purchase_cut:
		expected.checkpoint.operation = store.operation
		check(expected.checkpoint.operation.length()==32,"operation assigned before publication")
		if point!="applied":
			check(app.session.coins==previous.coins and app.game.board.hinted=="" and (kind=="hint" or app.game.lives==0),"payment not delivered ahead of confirmation")
	var envelope := {"pid":OS.get_process_id(),"kind":kind,"boundary":boundary,"errors":failures,
		"before":previous,"expected":previous if point=="before" else expected}
	var f := FileAccess.open(marker+".part",FileAccess.WRITE)
	f.store_string(JSON.stringify(envelope))
	f.close()
	if DirAccess.rename_absolute(marker+".part",marker)!=OK: return
	# The parent waits for this exact marker and kills this process object.
	while true: OS.delay_msec(50)

func pose_snapshot() -> Dictionary:
	var g = app.game
	return {"catalog":preload("res://game/paid_checkpoint.gd").CATALOG_ID,"origin":"levels","level":2,
		"removed":g.removed_ids.duplicate(),"used_hint":g.used_hint,"hint":g.board.hinted,
		"state":"failed" if g.lives==0 else "active","errors":g.blocked_moves,"lives":g.lives}

func purchase() -> void:
	if kind=="hint": hint()
	else: app.buy_continue(app.game.generation,app.game)

func writer() -> void:
	check(Fixture.seed_profile(store,1,240),"seed fresh isolated profile")
	mount()
	app.open_selector()
	app.open_level(2)
	var g = app.game
	var solution: Array = app.catalog.get_level(2).solution
	g.move(solution[0])
	g.animation.custom_step(5)
	if boundary=="prior" and kind=="continue": hint()
	if kind=="continue" or boundary=="prior":
		for i in 3: reject_arrow()
	if boundary=="prior" and kind=="hint": app.buy_continue(g.generation,g)
	previous = Store.stamp(store.inspect())
	expected = previous.duplicate(true)
	expected.coins -= 30 if kind=="hint" else 75
	expected.revision += 1
	var cp := pose_snapshot()
	cp.kind = kind
	cp.operation = ""
	if kind=="hint":
		cp.used_hint = true
		cp.hint = g.hint_candidate()
	else:
		cp.state = "active"
		cp.lives = 1
		cp.hint = ""
	expected.checkpoint = cp
	purchase_cut = boundary in ["before","prior","renamed","confirmed","applied"]
	if purchase_cut:
		goal = "before" if boundary=="prior" else boundary
		store.gate = stop_at
	purchase()
	check(app.session.coins==expected.coins and g.lives==cp.lives and g.board.hinted==cp.hint,"purchase delivered")
	stop_at("applied")
	purchase_cut = false
	cp.operation = store.operation
	check(Store.stamp(store.inspect())==expected,"authoritative complete purchase")
	if boundary in ["motion","stable"]:
		previous = expected.duplicate(true)
		g.move(solution[1])
		if boundary=="motion":
			g.animation.custom_step(0.015)
			check(g.board.locked and g.animation.is_running() and g.board.distance>0 and not g.model.path_for(solution[1]).is_empty(),"in-flight arrow already travelled before kill")
			goal = "motion"
			stop_at("motion")
		g.animation.custom_step(5)
		cp.removed.append(solution[1])
		cp.hint = ""
		expected.revision += 1
		goal = "stable"
		stop_at("stable")
	if boundary.begins_with("win"):
		for id in solution.slice(1,-1):
			g.move(id)
			g.animation.custom_step(5)
	previous = Store.stamp(store.inspect())
	expected = previous.duplicate(true)
	expected.erase("checkpoint")
	expected.revision += 1
	if boundary.begins_with("win"):
		expected.count += 1
		expected.coins += 5
	goal = "before" if boundary.ends_with("before") else "renamed"
	store.gate = stop_at
	if boundary.begins_with("win"):
		g.move(solution[-1])
		g.animation.custom_step(5)
	elif boundary.begins_with("restart"): g.restart()
	else: app.back()
	check(false,"writer missed boundary")

func reader() -> void:
	var envelope = JSON.parse_string(FileAccess.get_file_as_string(marker))
	var wanted: Dictionary = envelope.expected
	# JSON.parse_string gives floats even for integer tokens on Godot 4.3.
	for key in ["count","revision","coins"]: wanted[key] = int(wanted[key])
	if wanted.has("checkpoint"):
		for key in ["level","lives","errors"]: wanted.checkpoint[key] = int(wanted.checkpoint[key])
	mount()
	var disk := Store.stamp(store.inspect())
	check(disk==wanted,"complete disk snapshot including receipt")
	check(app.session.coins==wanted.coins and app.session.completed_count()==wanted.count,"restored wallet and prefix")
	if wanted.has("checkpoint"):
		var cp: Dictionary = wanted.checkpoint
		check(app.screen==app.Screen.GAME and app.game.level_id==cp.level and app.origin==app.Screen.LEVELS,"paid level and Back route")
		var actual := pose_snapshot()
		for key in actual: check(actual[key]==cp[key],"restored "+key)
		var paths: Dictionary = app.catalog.get_level(cp.level).paths
		for id in cp.removed: paths.erase(id)
		check(app.game.model.ids().size()==paths.size(),"exact remaining count")
		for id in paths: check(app.game.model.path_for(id)==paths[id],"exact remaining cells "+id)
		check(app.game.board.is_processing_input()==(cp.state=="active") and not app.game.board.locked,"stable input restored")
	else:
		check(app.screen==app.Screen.MENU and app.game==null,"menu without checkpoint")
	if capture:
		if phase=="again": await snap("03-repeat-launch")
		elif kind=="continue": await snap("02-restored-continue")
		else: await snap("01-restored-hint")
	check(Store.stamp(store.inspect())==wanted,"recovery causes zero writes")
	print("VERIFY ",phase," PID=",OS.get_process_id()," checks=",checks," failures=",failures)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()<5 or not Fixture.valid(args[1]):
		quit(1)
		return
	phase = args[0]
	kind = args[2]
	boundary = args[3]
	marker = args[4]
	capture = "--capture" in args
	if capture: DirAccess.make_dir_recursive_absolute(capture_directory())
	store = CrashStore.new(args[1])
	match phase:
		"writer": writer()
		"reader","again": await reader()
		"warning":
			mount()
			var base: Dictionary = store.inspect()
			var target := 1 if base.active==0 else 0
			var tmp := store.directory.path_join(Store.SLOTS[target]+".tmp")
			check(DirAccess.make_dir_absolute(tmp)==OK,"real staging obstruction")
			app.back()
			check(app.screen==app.Screen.GAME and app.game.get_node("Layout/SaveNotice").visible and store.inspect()==base,"abandon refused")
			await snap("04-write-warning")
			check(DirAccess.remove_absolute(tmp)==OK,"release obstruction")
			app.back()
			check(app.screen==app.Screen.LEVELS and not store.inspect().has("checkpoint"),"manual retry succeeded")
			print("VERIFY warning PID=",OS.get_process_id()," checks=",checks," failures=",failures)
		"cleanup":
			check(Fixture.clean(store),"isolated profile cleanup")
			print("VERIFY cleanup PID=",OS.get_process_id()," checks=",checks," failures=",failures)
		_: check(false,"invalid phase")
	quit(1 if failures else 0)
