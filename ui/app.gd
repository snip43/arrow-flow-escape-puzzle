extends Control

const Game := preload("res://scenes/game.tscn")
const Session := preload("res://game/player_profile.gd")
const Economy := Session.Economy
const Catalog := preload("res://levels/level_catalog.gd")
enum Screen { MENU, LEVELS, GAME }

@onready var menu: Control = $Layout/Menu
@onready var selector: Control = $Layout/Selector
@onready var scroll: ScrollContainer = $Layout/Selector/Scroll
var session := Session.new()
var store := preload("res://game/save_store.gd").new()
var dirty := false
var suspended := false
var unfocused := false
var base_snapshot := {}
var catalog := Catalog.new()
var cards := {}
var screen := Screen.MENU
var origin := Screen.MENU
var game
var fingers := {}
var cancel_activation := false
var last_system_back_frame := -1

func _ready() -> void:
	get_tree().quit_on_go_back = false
	menu.get_node("Play").pressed.connect(play)
	menu.get_node("Levels").pressed.connect(open_selector)
	selector.get_node("Back").pressed.connect(button_back)
	resized.connect(update_margins)
	update_margins()
	store.restore()
	base_snapshot = store.last_snapshot.duplicate()
	session.restore_profile(base_snapshot)
	show_menu()

func update_margins() -> void:
	preload("res://ui/safe_layout.gd").apply(self,$Layout,1200)

func show_menu() -> void:
	retry_save()
	screen = Screen.MENU
	$Layout.show()
	selector.hide()
	menu.show()
	var count := session.completed_count()
	menu.get_node("Progress").text = "%d / 100 completed" % count
	menu.get_node("Track").value = count
	menu.get_node("Play").visible = count < Session.LAST
	var action := "Play" if count == 0 else "Continue"
	menu.get_node("Play").text = "%s · Level %d" % [action, session.next_incomplete()]
	menu.get_node("Levels").theme_type_variation = &"Primary" if count == Session.LAST else &"Button"
	menu.get_node("Levels").text = "Replay levels" if count == Session.LAST else "Levels"

func play() -> void:
	if screen == Screen.MENU:
		open_level(session.next_incomplete())

func open_selector() -> void:
	if screen == Screen.MENU and not cancel_activation:
		show_selector()

func show_selector() -> void:
	screen = Screen.LEVELS
	$Layout.show()
	menu.hide()
	selector.show()
	retry_save()
	if cards.is_empty():
		build_cards()
	selector.get_node("Progress").text = "%d / 100 completed" % session.completed_count()
	for id in cards:
		var card: Button = cards[id]
		card.disabled = not session.can_play(id)
		card.focus_mode = Control.FOCUS_NONE if card.disabled else Control.FOCUS_ALL
		var status := "Locked"
		if session.is_completed(id): status = "Cleared"
		elif not card.disabled: status = "Open"
		card.get_node("Content/Status").text = status
		card.theme_type_variation = &"Primary" if status == "Open" else &"Button"
		var ink := card.get_theme_color("muted","Flow")
		var caption := ink
		if status == "Cleared":
			ink = card.get_theme_color("paper","Flow")
			caption = card.get_theme_color("mint","Flow")
		elif status == "Open":
			ink = card.get_theme_color("bg","Flow")
			caption = ink
		card.get_node("Content/Number").add_theme_color_override("font_color",ink)
		card.get_node("Content/Status").add_theme_color_override("font_color",caption)
	var target := session.next_incomplete()
	if target <= 1:
		scroll.scroll_vertical = 0
	else:
		reveal.call_deferred(target)

func reveal(id: int) -> void:
	if screen == Screen.LEVELS:
		scroll.ensure_control_visible(cards[id])

func build_cards() -> void:
	var groups := scroll.get_node("Groups")
	var tier := ""
	var grid: GridContainer
	for entry in catalog.entries():
		if tier != entry.tier:
			tier = entry.tier
			var header := Label.new()
			header.text = tier
			header.theme_type_variation = &"Wordmark"
			header.add_theme_font_size_override("font_size",43)
			header.custom_minimum_size.y = 90
			groups.add_child(header)
			grid = GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation",14)
			grid.add_theme_constant_override("v_separation",14)
			groups.add_child(grid)
		var card := Button.new()
		card.name = "Level%d" % entry.id
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(150,168)
		grid.add_child(card)
		var content := VBoxContainer.new()
		content.name = "Content"
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation",0)
		for part in ["Number","Status"]:
			var label := Label.new()
			label.name = part
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size",52 if part=="Number" else 32)
			content.add_child(label)
		content.get_node("Number").text = str(entry.id)
		card.pressed.connect(card_pressed.bind(entry.id))
		cards[entry.id] = card

func card_pressed(id: int) -> void:
	if screen == Screen.LEVELS:
		open_level(id)

func open_level(id: int) -> bool:
	if screen == Screen.GAME or cancel_activation or not session.can_play(id):
		return false
	origin = screen
	screen = Screen.GAME
	$Layout.hide()
	game = Game.instantiate()
	game.catalog = catalog
	game.level_id = id
	game.attempt_changed.connect(update_notice)
	game.hint_requested.connect(buy_hint.bind(game))
	game.continue_requested.connect(buy_continue.bind(game))
	game.completed.connect(level_completed.bind(game))
	game.back_requested.connect(button_back)
	game.allow_next = allow_next
	add_child(game)
	var back_button: Button = game.get_node("%Back")
	back_button.tooltip_text = "Return to %s. An unfinished board starts over on re-entry." % ("Levels" if origin == Screen.LEVELS else "the menu")
	back_button.show()
	update_notice()
	return true

func allow_next(id: int) -> bool:
	return screen == Screen.GAME and not cancel_activation and session.can_play(id)

func level_completed(id: int, source: Control) -> void:
	if not is_instance_valid(game) or source != game or source.level_id != id or not source.complete.visible:
		return
	if source.reward_ticket == source.generation: return
	source.reward_ticket = source.generation
	var perfect: bool = source.blocked_moves == 0 and not source.used_hint
	var reward := session.first_clear(id,perfect)
	var receipt: Label = source.get_node("Layout/Overlay/Reward")
	receipt.show()
	if reward.is_empty():
		receipt.text = "Already cleared"
		return
	receipt.text = "+%d Coins" % reward.base
	if reward.bonus > 0: receipt.text += "   ·   Perfect +%d" % reward.bonus
	dirty = true
	retry_save()

func retry_save() -> void:
	if dirty:
		dirty = not store.save(session.completed_count(),session.coins,base_snapshot)
		if not dirty: base_snapshot = store.last_snapshot.duplicate()
	update_notice()

func purchase_allowed(ticket: int, source: Variant, price: int) -> bool:
	return (screen == Screen.GAME and is_instance_valid(source) and source == game
		and source.is_inside_tree() and source.is_visible_in_tree() and ticket == game.generation
		and not game.purchase_pending and not suspended and not unfocused and not cancel_activation
		and not dirty and not store.spending_blocked and session.coins >= price)

func debit(price: int, item: String) -> bool:
	var remaining := session.coins - price
	if not store.save(session.completed_count(),remaining,base_snapshot):
		if store.notice == store.UNSAVED:
			store.notice = "%s not purchased. Please retry." % item
		return false
	base_snapshot = store.last_snapshot.duplicate()
	session.coins = remaining
	return true

func buy_hint(ticket: int, source: Variant) -> void:
	if not purchase_allowed(ticket,source,Economy.HINT): return
	var id: String = game.hint_candidate()
	if id.is_empty(): return
	game.purchase_pending = true
	if debit(Economy.HINT,"Hint"):
		game.used_hint = true
		game.board.hinted = id
		game.board.queue_redraw()
	game.purchase_pending = false
	update_notice()

func buy_continue(ticket: int, source: Variant) -> void:
	if not purchase_allowed(ticket,source,Economy.CONTINUE_COST) or game.state != game.Attempt.FAILED:
		return
	game.purchase_pending = true
	game.invalidate_purchase_input()
	if debit(Economy.CONTINUE_COST,"Continue"):
		game.resume_board()
	game.purchase_pending = false
	update_notice()

func update_notice() -> void:
	for panel in [menu, selector]:
		panel.get_node("Wallet").set_balance(session.coins)
		panel.get_node("Wallet").show()
		panel.get_node("SaveNotice").text = store.notice
		panel.get_node("SaveNotice").visible = not store.notice.is_empty()
	scroll.offset_top = 336 if store.notice.is_empty() else 408
	if is_instance_valid(game):
		var label: Label = game.get_node("Layout/SaveNotice")
		label.text = store.notice
		var failed: bool = game.state == game.Attempt.FAILED
		var price := Economy.CONTINUE_COST if failed else Economy.HINT
		if store.notice.is_empty() and game.level_id > 1 and not game.complete.visible and session.coins < price:
			label.text = "Not enough coins"
		label.visible = not label.text.is_empty()
		game.get_node("Layout/Tutorial").visible = game.level_id == 1 and not game.complete.visible and store.notice.is_empty()
		var wallet: Label = game.get_node("Layout/Wallet")
		wallet.set_balance(session.coins)
		wallet.show()
		var hint: Button = game.get_node("%Hint")
		hint.text = "Hint · %d" % Economy.HINT
		hint.visible = not failed
		var blocked: bool = game.purchase_pending or suspended or unfocused or dirty or store.spending_blocked
		var resume: Button = game.get_node("%Continue")
		resume.disabled = not failed or blocked or session.coins < Economy.CONTINUE_COST
		if failed:
			var info: Label = game.get_node("Layout/Failed/Panel/Description")
			info.text = "Restart for free to try again." if resume.disabled else "Resume this board with %d life." % Economy.CONTINUE_LIVES
		hint.disabled = blocked or session.coins < Economy.HINT or game.hint_candidate().is_empty()

func button_back() -> void:
	if not cancel_activation:
		back()

func back() -> void:
	if is_instance_valid(game) and game.purchase_pending: return
	if screen == Screen.GAME:
		game.leave()
		game.hide()
		remove_child(game)
		game.queue_free()
		game = null
		if origin == Screen.LEVELS:
			show_selector()
		else:
			show_menu()
	elif screen == Screen.LEVELS:
		show_menu()

func system_back() -> void:
	# Some hosts deliver Escape and a system-back notification for one action.
	var frame := Engine.get_process_frames()
	if frame != last_system_back_frame:
		last_system_back_frame = frame
		back()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		suspended = what == NOTIFICATION_APPLICATION_PAUSED
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN]:
		unfocused = what == NOTIFICATION_APPLICATION_FOCUS_OUT
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and is_instance_valid(game):
		game.invalidate_purchase_input()
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED] and is_node_ready():
		update_notice()
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_CLOSE_REQUEST] and is_node_ready() and dirty:
		retry_save()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		system_back()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		fingers.clear()
		cancel_activation = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			system_back()
		elif fingers.is_empty():
			last_system_back_frame = -1
			cancel_activation = false
	elif event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed:
			last_system_back_frame = -1
			cancel_activation = not fingers.is_empty()
			fingers[event.index] = event.position
		else:
			fingers.erase(event.index)
			cancel_activation = cancel_activation or event.canceled
	elif event is InputEventScreenDrag and fingers.has(event.index):
		if event.position.distance_to(fingers[event.index]) > 24:
			cancel_activation = true
	elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		last_system_back_frame = -1
		cancel_activation = not fingers.is_empty()
