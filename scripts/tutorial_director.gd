extends Node

## Tutorial game mode director.
## Runs a fixed, step-by-step lesson on top of the normal aquarium scene:
## each step shows a short explanation and one clear goal, unlocks the shop item
## it teaches, highlights it, and advances automatically once the goal is met.
## Birds only appear in the dedicated training step, and the training bird can never
## catch a fish. The last step sends the player into the normal Endless game.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const UI = preload("res://scripts/ui_style.gd")
const Balance = preload("res://scripts/game_balance.gd")
const LoadingScreenScript = preload("res://scripts/loading_screen.gd")

const ADVANCE_DELAY: float = 1.3

var main: Node = null

var _steps: Array[Dictionary] = []
var _index: int = -1
var _progress: int = 0
var _completed: bool = false
var _advance_timer: float = -1.0
var _coin_refill_timer: float = 0.0

var _panel: PanelContainer = null
var _step_label: Label = null
var _step_bar: ProgressBar = null
var _title_label: Label = null
var _body_label: Label = null
var _goal_panel: PanelContainer = null
var _goal_mark: Label = null
var _goal_label: Label = null
var _next_btn: Button = null
var _skip_btn: Button = null
var _finish_row: VBoxContainer = null


func setup(main_node: Node, hud_layer: CanvasLayer) -> void:
	main = main_node
	_build_steps()
	_build_ui(hud_layer)
	if main.has_signal("tutorial_event"):
		main.connect("tutorial_event", _on_event)
	_go_to(0)


func _build_steps() -> void:
	_steps = [
		{
			"title": "Welcome to your tank",
			"body": "Goldfish swim around and drop coins. Coins slowly sink to the sand.\n\nClick falling coins to collect them before they reach the floor.",
			"goal": "Click coins",
			"event": "coin_click",
			"count": 3,
			"enter": "_enter_welcome",
		},
		{
			"title": "Meet your Pet Crab",
			"body": "The crab walks along the sand and picks up any coins that land there, so nothing is wasted.\n\nClick the crab to see its details.",
			"goal": "Select the crab",
			"event": "select",
			"filter": "crab",
			"count": 1,
		},
		{
			"title": "Feeding time",
			"body": "Fish get hungry over time. A hungry fish swims up to the Duckweed on the water surface and eats.\n\nA fish that stays hungry too long will starve, so keep enough plants for everyone.",
			"goal": "Watch a fish eat",
			"event": "fish_fed",
			"count": 1,
			"enter": "_enter_feed",
		},
		{
			"title": "Grow your school",
			"body": "More fish means more coins. Fish grow after a few meals and then drop better coins: copper, then silver, then gold.\n\nBuy a goldfish from the shop at the bottom, or press 1.",
			"goal": "Buy a goldfish",
			"event": "buy_fish",
			"count": 1,
			"enter": "_enter_buy_fish",
			"highlight": "fish",
		},
		{
			"title": "More food",
			"body": "Each Duckweed feeds one fish at a time. With a bigger school, fish have to wait their turn.\n\nAdd a second Duckweed, or press 2.",
			"goal": "Buy a Duckweed",
			"event": "buy_plant",
			"count": 1,
			"enter": "_enter_buy_plant",
			"highlight": "plant",
		},
		{
			"title": "Upgrade your plants",
			"body": "Upgraded plants feed more fish at the same time. At the Water Hyacinth level they even hatch new baby fish once you have 2 adult goldfish.\n\nUpgrade a plant, or press 3.",
			"goal": "Upgrade a plant",
			"event": "upgrade_plant",
			"count": 1,
			"enter": "_enter_upgrade",
			"highlight": "upgrade",
		},
		{
			"title": "Hire a defender",
			"body": "Kingfisher birds hunt your fish from above. Archer Fish shoot them with water jets and slow them down. They never need food.\n\nBuy an Archer Fish, or press 4.",
			"goal": "Buy an Archer Fish",
			"event": "buy_archer",
			"count": 1,
			"enter": "_enter_archer",
			"highlight": "archer",
		},
		{
			"title": "Here comes a Kingfisher",
			"body": "A training bird will circle, then dive for your fish. Click the bird to hit it and knock it back while your Archer Fish shoots.\n\nFish close to the surface are the easiest to catch.",
			"goal": "Defeat the Kingfisher",
			"event": "bird_killed",
			"count": 1,
			"enter": "_enter_attack",
		},
		{
			"title": "How waves work",
			"body": "In Endless mode every wave has three phases:\n\nPeaceful - safe time to buy and upgrade.\nCareful - birds circle above the tank.\nAttack - birds dive for your fish.\n\nEach wave is a little harder than the last. The bar at the top shows the time left in each phase.",
			"goal": "",
			"event": "",
			"count": 0,
			"enter": "_enter_waves",
		},
		{
			"title": "Make it yours",
			"body": "While it is peaceful you can decorate. The timer pauses while you move plants and place rocks, corals and seaweed on the floor.\n\nPress B (or Decorate in the shop) to open it, then press Done to close it.",
			"goal": "Open and close Decorate",
			"event": "decor_off",
			"count": 1,
			"enter": "_enter_decorate",
			"highlight": "decorate",
		},
		{
			"title": "You are ready",
			"body": "Keep your fish fed, collect coins, grow your defense and survive as many waves as you can.\n\nYou can look up any creature in the Encyclopedia from the main menu or the pause menu.",
			"goal": "",
			"event": "",
			"count": 0,
			"enter": "_enter_done",
			"final": true,
		},
	]


func _build_ui(hud_layer: CanvasLayer) -> void:
	_panel = UI.make_panel(UI.PANEL_SOLID, 12, 18.0, 16.0)
	_panel.name = "TutorialPanel"
	_panel.position = Vector2(16.0, 104.0)
	_panel.custom_minimum_size = Vector2(320.0, 0.0)
	hud_layer.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	_step_label = UI.make_caption("Tutorial")
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_step_label)
	_skip_btn = UI.make_button("Skip", "ghost", UI.TEXT_MUTED, 11, 24.0)
	_skip_btn.tooltip_text = "Jump to the end of the tutorial"
	_skip_btn.pressed.connect(_on_skip_pressed)
	head.add_child(_skip_btn)

	_step_bar = UI.make_progress_bar(UI.ACCENT, 3.0)
	vbox.add_child(_step_bar)

	_title_label = UI.make_label("", 18, UI.TEXT)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_title_label)

	_body_label = UI.make_label("", 13, UI.TEXT_MUTED)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(284.0, 0.0)
	vbox.add_child(_body_label)

	_goal_panel = UI.make_panel(Color(1.0, 1.0, 1.0, 0.04), 8, 12.0, 8.0)
	_goal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_goal_panel)
	var goal_row := HBoxContainer.new()
	goal_row.add_theme_constant_override("separation", 10)
	goal_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal_panel.add_child(goal_row)
	_goal_mark = UI.make_label("GOAL", 10, UI.ACCENT)
	_goal_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_goal_mark.custom_minimum_size = Vector2(38.0, 0.0)
	goal_row.add_child(_goal_mark)
	_goal_label = UI.make_label("", 13, UI.TEXT)
	_goal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_row.add_child(_goal_label)

	_next_btn = UI.make_button("Next", "primary", UI.ACCENT, 13, 34.0)
	_next_btn.pressed.connect(_on_next_pressed)
	vbox.add_child(_next_btn)

	_finish_row = VBoxContainer.new()
	_finish_row.add_theme_constant_override("separation", 6)
	_finish_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finish_row.visible = false
	vbox.add_child(_finish_row)
	var endless_btn := UI.make_button("Play Endless", "primary", UI.ACCENT, 14, 38.0)
	endless_btn.pressed.connect(_on_play_endless_pressed)
	_finish_row.add_child(endless_btn)
	var menu_btn := UI.make_button("Main Menu", "secondary", UI.ACCENT, 13, 34.0)
	menu_btn.pressed.connect(_on_main_menu_pressed)
	_finish_row.add_child(menu_btn)


func _process(delta: float) -> void:
	if _advance_timer >= 0.0:
		_advance_timer -= delta
		if _advance_timer < 0.0:
			_go_to(_index + 1)
			return

	# Keep a few coins in the water during the first lesson so it can always be finished
	if _index == 0 and not _completed and main != null:
		_coin_refill_timer -= delta
		if _coin_refill_timer <= 0.0:
			_coin_refill_timer = 1.0
			if int(main.call("count_free_coins")) == 0:
				main.call("spawn_tutorial_coins", 3)

	if _goal_mark and not _completed and _current_has_goal():
		var p := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
		_goal_mark.modulate.a = 0.55 + 0.45 * p


func _current_has_goal() -> bool:
	if _index < 0 or _index >= _steps.size():
		return false
	return String(_steps[_index]["event"]) != ""


func _go_to(i: int) -> void:
	_index = clampi(i, 0, _steps.size() - 1)
	_progress = 0
	_completed = false
	_advance_timer = -1.0
	var step: Dictionary = _steps[_index]
	if step.has("enter"):
		call(String(step["enter"]))
	if main:
		main.call("set_shop_highlight", String(step.get("highlight", "")))
	_refresh()


func _refresh() -> void:
	var step: Dictionary = _steps[_index]
	var is_final := bool(step.get("final", false))
	_step_label.text = "TUTORIAL  -  STEP %d OF %d" % [_index + 1, _steps.size()]
	_step_bar.value = float(_index + 1) / float(_steps.size())
	_title_label.text = String(step["title"])
	_body_label.text = String(step["body"])

	var has_goal := _current_has_goal()
	_goal_panel.visible = has_goal
	if has_goal:
		var count := int(step["count"])
		var goal_txt := String(step["goal"])
		if count > 1:
			goal_txt += "   %d / %d" % [mini(_progress, count), count]
		_goal_label.text = goal_txt
		if _completed:
			_goal_mark.text = "DONE"
			_goal_mark.modulate.a = 1.0
			_goal_mark.add_theme_color_override("font_color", UI.GOOD)
			_goal_label.add_theme_color_override("font_color", UI.GOOD)
		else:
			_goal_mark.text = "GOAL"
			_goal_mark.add_theme_color_override("font_color", UI.ACCENT)
			_goal_label.add_theme_color_override("font_color", UI.TEXT)

	_next_btn.visible = (not has_goal) and not is_final
	_finish_row.visible = is_final
	_skip_btn.visible = not is_final


func _on_event(event_name: String, data: Variant) -> void:
	if _index < 0 or _completed:
		return
	var step: Dictionary = _steps[_index]
	if String(step["event"]) != event_name:
		return
	if step.has("filter"):
		if not (data is Node) or not is_instance_valid(data) or not (data as Node).is_in_group(String(step["filter"])):
			return
	_progress += 1
	if _progress >= int(step["count"]):
		_completed = true
		_advance_timer = ADVANCE_DELAY
		if main:
			main.call("set_shop_highlight", "")
	_refresh()


func _on_next_pressed() -> void:
	_go_to(_index + 1)


func _on_skip_pressed() -> void:
	_go_to(_steps.size() - 1)


func _on_play_endless_pressed() -> void:
	Engine.set_meta("game_mode", "endless")
	LoadingScreenScript.transition_to(get_tree(), "res://main.tscn")


func _on_main_menu_pressed() -> void:
	LoadingScreenScript.transition_to(get_tree(), "res://menu.tscn")


# --- Step setup -----------------------------------------------------------

func _enter_welcome() -> void:
	main.call("spawn_tutorial_coins", 4)
	_coin_refill_timer = 3.0


func _enter_feed() -> void:
	main.call("make_one_fish_hungry")


func _enter_buy_fish() -> void:
	main.call("set_shop_locked", "fish", false)
	main.call("ensure_coins", Balance.COST_BABY_FISH)


func _enter_buy_plant() -> void:
	main.call("set_shop_locked", "plant", false)
	main.call("ensure_coins", Balance.COST_DUCKWEED)


func _enter_upgrade() -> void:
	main.call("set_shop_locked", "upgrade", false)
	main.call("ensure_coins", int(main.call("get_plant_upgrade_cost")))


func _enter_archer() -> void:
	main.call("set_shop_locked", "archer", false)
	main.call("ensure_coins", int(main.call("get_archer_fish_cost")))


func _enter_attack() -> void:
	main.call("tutorial_start_training_wave")


func _enter_waves() -> void:
	main.call("set_shop_locked", "crab", false)


func _enter_decorate() -> void:
	main.call("set_shop_locked", "decorate", false)


func _enter_done() -> void:
	main.call("unlock_all_shop")
