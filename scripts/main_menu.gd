extends Control
class_name MainMenu

## Minimal 2D Main Menu: Play Endless, Tutorial, Encyclopedia, Settings, Quit.
## The selected game mode is passed to the game scene through Engine meta "game_mode".
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const LoadingScreenScript = preload("res://scripts/loading_screen.gd")
const EncyclopediaScript = preload("res://scripts/encyclopedia_panel.gd")
const UI = preload("res://scripts/ui_style.gd")

var _menu_column: VBoxContainer = null
var _settings_panel: PanelContainer = null
var _encyclopedia: PanelContainer = null
var _shake_btn: Button = null
var _fullscreen_btn: Button = null


func _ready() -> void:
	get_tree().paused = false
	if not Engine.has_meta("screen_shake_enabled"):
		Engine.set_meta("screen_shake_enabled", true)
	_build_menu_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_close_panels()
			get_viewport().set_input_as_handled()


func _build_menu_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.make_background_gradient())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 40)
	center.add_child(main_hbox)

	# Left column: title + buttons (no card, just clean typography)
	_menu_column = VBoxContainer.new()
	_menu_column.custom_minimum_size = Vector2(280.0, 0.0)
	_menu_column.add_theme_constant_override("separation", 10)
	_menu_column.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.add_child(_menu_column)

	var title := UI.make_label("FIH-2", 44, UI.TEXT)
	_menu_column.add_child(title)
	var subtitle := UI.make_label("Keep your fish fed. Keep the birds away.", 13, UI.TEXT_MUTED)
	_menu_column.add_child(subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 18.0)
	_menu_column.add_child(gap)

	var play_btn := UI.make_button("Play Endless", "primary", UI.ACCENT, 15, 44.0)
	play_btn.pressed.connect(_on_start_pressed)
	_menu_column.add_child(play_btn)

	var tut_btn := UI.make_button("Tutorial", "secondary", UI.GOOD, 14, 40.0)
	tut_btn.pressed.connect(_on_tutorial_pressed)
	_menu_column.add_child(tut_btn)

	var enc_btn := UI.make_button("Encyclopedia", "secondary", UI.ACCENT, 14, 40.0)
	enc_btn.pressed.connect(_on_encyclopedia_pressed)
	_menu_column.add_child(enc_btn)

	var settings_btn := UI.make_button("Settings", "secondary", UI.ACCENT, 14, 40.0)
	settings_btn.pressed.connect(_on_settings_pressed)
	_menu_column.add_child(settings_btn)

	var quit_btn := UI.make_button("Quit", "ghost", UI.TEXT_MUTED, 14, 40.0)
	quit_btn.pressed.connect(_on_quit_pressed)
	_menu_column.add_child(quit_btn)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0.0, 10.0)
	_menu_column.add_child(gap2)
	var hint := UI.make_label("First time here? Start with the Tutorial.", 12, UI.TEXT_FAINT)
	_menu_column.add_child(hint)

	# Right side: settings card and encyclopedia (only one visible at a time)
	_settings_panel = _build_settings_panel()
	main_hbox.add_child(_settings_panel)

	_encyclopedia = EncyclopediaScript.new()
	_encyclopedia.visible = false
	_encyclopedia.connect("closed", _on_encyclopedia_closed)
	main_hbox.add_child(_encyclopedia)


func _build_settings_panel() -> PanelContainer:
	var panel := UI.make_panel(UI.PANEL_SOLID, 14, 22.0, 20.0)
	panel.custom_minimum_size = Vector2(320.0, 0.0)
	panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UI.make_label("Settings", 20, UI.TEXT))
	vbox.add_child(UI.make_separator())

	_shake_btn = UI.make_button("", "secondary")
	_shake_btn.pressed.connect(_on_toggle_shake)
	vbox.add_child(_shake_btn)

	_fullscreen_btn = UI.make_button("", "secondary")
	_fullscreen_btn.pressed.connect(_on_toggle_fullscreen)
	vbox.add_child(_fullscreen_btn)

	var close_btn := UI.make_button("Close", "ghost", UI.TEXT_MUTED)
	close_btn.pressed.connect(func() -> void: panel.visible = false)
	vbox.add_child(close_btn)

	_refresh_settings_labels()
	return panel


func _refresh_settings_labels() -> void:
	if _shake_btn:
		var shake_on := true
		if Engine.has_meta("screen_shake_enabled"):
			shake_on = bool(Engine.get_meta("screen_shake_enabled"))
		_shake_btn.text = "Screen shake: %s" % ("On" if shake_on else "Off")

	if _fullscreen_btn:
		var mode := DisplayServer.window_get_mode()
		var is_fs := (mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_fullscreen_btn.text = "Window mode: %s" % ("Fullscreen" if is_fs else "Windowed")


func _close_panels() -> void:
	if _settings_panel:
		_settings_panel.visible = false
	if _encyclopedia:
		_encyclopedia.visible = false


func _on_start_pressed() -> void:
	Engine.set_meta("game_mode", "endless")
	LoadingScreenScript.transition_to(get_tree(), "res://main.tscn")


func _on_tutorial_pressed() -> void:
	Engine.set_meta("game_mode", "tutorial")
	LoadingScreenScript.transition_to(get_tree(), "res://main.tscn")


func _on_encyclopedia_pressed() -> void:
	if _settings_panel:
		_settings_panel.visible = false
	if _encyclopedia:
		_encyclopedia.visible = not _encyclopedia.visible


func _on_encyclopedia_closed() -> void:
	pass


func _on_settings_pressed() -> void:
	if _encyclopedia:
		_encyclopedia.visible = false
	if _settings_panel:
		_settings_panel.visible = not _settings_panel.visible
		_refresh_settings_labels()


func _on_toggle_shake() -> void:
	var shake_on := true
	if Engine.has_meta("screen_shake_enabled"):
		shake_on = bool(Engine.get_meta("screen_shake_enabled"))
	Engine.set_meta("screen_shake_enabled", not shake_on)
	_refresh_settings_labels()


func _on_toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_refresh_settings_labels()


func _on_quit_pressed() -> void:
	get_tree().quit()
