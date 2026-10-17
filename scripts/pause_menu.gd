extends CanvasLayer
class_name PauseMenu

## In-game minimal Pause Menu.
## Opens with ESC / P or the HUD Pause button, shows a short session summary,
## and offers Resume, Restart, Encyclopedia, Controls, Screen Shake, Main Menu and Quit.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const LoadingScreenScript = preload("res://scripts/loading_screen.gd")
const EncyclopediaScript = preload("res://scripts/encyclopedia_panel.gd")
const UI = preload("res://scripts/ui_style.gd")
const Balance = preload("res://scripts/game_balance.gd")

signal pause_toggled(is_paused: bool)

var _root_control: Control = null
var _card_panel: PanelContainer = null
var _stats_label: Label = null
var _controls_panel: PanelContainer = null
var _encyclopedia: PanelContainer = null
var _shake_btn: Button = null
var _restart_btn: Button = null


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_meta("screen_shake_enabled"):
		Engine.set_meta("screen_shake_enabled", true)

	_build_pause_ui()
	_set_paused_state(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		var scene := get_tree().current_scene
		if scene and bool(scene.get("is_game_over")):
			return
		if ke.keycode == KEY_ESCAPE:
			if scene and bool(scene.get("is_decorating_mode")):
				if scene.has_method("exit_decorating_mode"):
					scene.call("exit_decorating_mode")
				get_viewport().set_input_as_handled()
				return
			# ESC closes an open side panel first
			if get_tree().paused and ((_encyclopedia and _encyclopedia.visible) or (_controls_panel and _controls_panel.visible)):
				_hide_side_panels()
				get_viewport().set_input_as_handled()
				return
		if ke.keycode in [KEY_P, KEY_ESCAPE]:
			toggle_pause()
			get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	_set_paused_state(not get_tree().paused)


func open_pause() -> void:
	_set_paused_state(true)


func close_pause() -> void:
	_set_paused_state(false)


func _hide_side_panels() -> void:
	if _controls_panel:
		_controls_panel.visible = false
	if _encyclopedia:
		_encyclopedia.visible = false


func _set_paused_state(paused: bool) -> void:
	get_tree().paused = paused
	if _root_control:
		_root_control.visible = paused
	_hide_side_panels()

	if paused:
		_refresh_stats()
		_update_shake_button_text()
		if _card_panel:
			_card_panel.modulate.a = 0.0
			var tw := create_tween()
			tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tw.tween_property(_card_panel, "modulate:a", 1.0, 0.12)

	pause_toggled.emit(paused)


func _build_pause_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "PauseOverlay"
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root_control)

	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.01, 0.03, 0.06, 0.70)
	_root_control.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(center)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	center.add_child(hbox)

	_card_panel = UI.make_panel(UI.PANEL_SOLID, 14, 24.0, 22.0)
	_card_panel.custom_minimum_size = Vector2(300.0, 0.0)
	hbox.add_child(_card_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_card_panel.add_child(vbox)

	var title := UI.make_label("Paused", 24, UI.TEXT)
	vbox.add_child(title)

	_stats_label = UI.make_label("", 12, UI.TEXT_MUTED)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_stats_label)

	vbox.add_child(UI.make_separator())

	var resume_btn := UI.make_button("Resume", "primary")
	resume_btn.pressed.connect(close_pause)
	vbox.add_child(resume_btn)

	_restart_btn = UI.make_button("Restart", "secondary")
	_restart_btn.pressed.connect(_on_restart_pressed)
	vbox.add_child(_restart_btn)

	var enc_btn := UI.make_button("Encyclopedia", "secondary")
	enc_btn.pressed.connect(_on_toggle_encyclopedia_pressed)
	vbox.add_child(enc_btn)

	var controls_btn := UI.make_button("Controls", "secondary")
	controls_btn.pressed.connect(_on_toggle_controls_pressed)
	vbox.add_child(controls_btn)

	_shake_btn = UI.make_button("", "secondary")
	_shake_btn.pressed.connect(_on_toggle_shake_pressed)
	vbox.add_child(_shake_btn)

	vbox.add_child(UI.make_separator())

	var menu_btn := UI.make_button("Main menu", "ghost", UI.TEXT_MUTED)
	menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(menu_btn)

	var quit_btn := UI.make_button("Quit game", "ghost", UI.TEXT_MUTED)
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

	# Side panel: controls
	_controls_panel = UI.make_panel(UI.PANEL_SOLID, 14, 24.0, 22.0)
	_controls_panel.custom_minimum_size = Vector2(360.0, 0.0)
	_controls_panel.visible = false
	hbox.add_child(_controls_panel)

	var c_vbox := VBoxContainer.new()
	c_vbox.add_theme_constant_override("separation", 8)
	_controls_panel.add_child(c_vbox)
	c_vbox.add_child(UI.make_label("Controls", 20, UI.TEXT))
	c_vbox.add_child(UI.make_separator())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 7)
	c_vbox.add_child(grid)
	var rows := [
		["Left click", "Select, collect coins, hit birds"],
		["Drag", "Rotate the camera"],
		["Scroll", "Zoom in and out"],
		["W A S D", "Rotate the camera"],
		["1 - 6", "Shop: fish, plant, upgrade, archer, crab, decorate"],
		["U", "Upgrade the selected plant or crab"],
		["B", "Open or close Decorate (peaceful only)"],
		["Tab", "Switch surface / floor while decorating"],
		["R", "Rotate selected plant or decoration"],
		["Space", "Deselect"],
		["H", "Show or hide the on-screen hints"],
		["P / Esc", "Pause"],
	]
	for r in rows:
		var k := UI.make_label(String(r[0]), 12, UI.ACCENT)
		k.custom_minimum_size = Vector2(80.0, 0.0)
		grid.add_child(k)
		var v := UI.make_label(String(r[1]), 12, UI.TEXT_MUTED)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(220.0, 0.0)
		grid.add_child(v)

	# Side panel: encyclopedia
	_encyclopedia = EncyclopediaScript.new()
	_encyclopedia.visible = false
	hbox.add_child(_encyclopedia)


func _refresh_stats() -> void:
	if _stats_label == null:
		return
	var scene := get_tree().current_scene
	var wave := 1
	var coins := 0
	var mode := "endless"
	if scene:
		if scene.get("current_wave") != null:
			wave = int(scene.get("current_wave"))
		if scene.get("coins") != null:
			coins = int(scene.get("coins"))
		if scene.get("game_mode") != null:
			mode = str(scene.get("game_mode"))

	var alive_fish := 0
	for node in get_tree().get_nodes_in_group("goldfish"):
		if is_instance_valid(node) and not bool(node.get("is_dead")):
			alive_fish += 1
	var plants := get_tree().get_nodes_in_group("duckweed").size()
	var archers := get_tree().get_nodes_in_group("archerfish").size()

	var head := "Tutorial" if mode == "tutorial" else "Wave %d (%s)" % [wave, Balance.difficulty_name()]
	_stats_label.text = "%s   %d coins\n%s   %s   %s" % [
		head, coins,
		_plural(alive_fish, "fish", "fish"),
		_plural(plants, "plant", "plants"),
		_plural(archers, "archer", "archers"),
	]
	if _restart_btn:
		_restart_btn.text = "Restart tutorial" if mode == "tutorial" else "Restart"


func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


func _update_shake_button_text() -> void:
	if _shake_btn == null:
		return
	var enabled := true
	if Engine.has_meta("screen_shake_enabled"):
		enabled = bool(Engine.get_meta("screen_shake_enabled"))
	_shake_btn.text = "Screen shake: %s" % ("On" if enabled else "Off")


func _on_toggle_controls_pressed() -> void:
	if _encyclopedia:
		_encyclopedia.visible = false
	if _controls_panel:
		_controls_panel.visible = not _controls_panel.visible


func _on_toggle_encyclopedia_pressed() -> void:
	if _controls_panel:
		_controls_panel.visible = false
	if _encyclopedia:
		_encyclopedia.visible = not _encyclopedia.visible


func _on_toggle_shake_pressed() -> void:
	var enabled := true
	if Engine.has_meta("screen_shake_enabled"):
		enabled = bool(Engine.get_meta("screen_shake_enabled"))
	Engine.set_meta("screen_shake_enabled", not enabled)
	_update_shake_button_text()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	LoadingScreenScript.transition_to(get_tree(), "res://main.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	LoadingScreenScript.transition_to(get_tree(), "res://menu.tscn")


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
