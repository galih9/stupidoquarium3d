extends Control
class_name LoadingScreen

## Asynchronous threaded loading screen with minimalistic progress bar and gameplay tips.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const UI = preload("res://scripts/ui_style.gd")
const DEFAULT_TARGET_SCENE := "res://main.tscn"
const MIN_DISPLAY_TIME: float = 0.95

const TIPS: Array[String] = [
	"Each Duckweed feeds one fish at a time. Add plants or upgrade them as your school grows.",
	"Water Hyacinth hatches new baby fish once you have 2 adult goldfish.",
	"Your Pet Crab collects coins on the sand. From level 7 it pulls in every coin around it.",
	"Bored fish drop cheaper coins. Decorations keep them happy, and pricier pieces help more.",
	"Medium fish need Duckweed Lv.2 to eat, adults need Water Hyacinth.",
	"Press B while it is peaceful to decorate. The wave timer pauses while you do.",
	"Click a diving Kingfisher to hit it and knock it back. Archer Fish help a lot.",
	"Fish near the water surface are the easiest for birds to catch.",
	"Shop hotkeys: 1 fish, 2 plant, 3 upgrade, 4 archer, 5 crab, 6 decorate.",
]

var _target_path: String = DEFAULT_TARGET_SCENE
var _elapsed: float = 0.0
var _display_progress: float = 0.0
var _load_started: bool = false
var _transitioned: bool = false

var _title_label: Label = null
var _stage_label: Label = null
var _percent_label: Label = null
var _tip_label: Label = null
var _progress_bar: ProgressBar = null


static func transition_to(tree: SceneTree, target_scene_path: String) -> void:
	if tree == null:
		return
	tree.paused = false
	Engine.set_meta("target_scene_path", target_scene_path)
	tree.change_scene_to_file("res://loading.tscn")


func _ready() -> void:
	get_tree().paused = false
	if Engine.has_meta("target_scene_path"):
		_target_path = str(Engine.get_meta("target_scene_path"))
	if _target_path == "":
		_target_path = DEFAULT_TARGET_SCENE

	_build_ui()

	var err := ResourceLoader.load_threaded_request(_target_path)
	_load_started = (err == OK)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	add_child(UI.make_background_gradient())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(440.0, 0.0)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	_title_label = Label.new()
	var mode := str(Engine.get_meta("game_mode")) if Engine.has_meta("game_mode") else "endless"
	if not _target_path.ends_with("main.tscn"):
		_title_label.text = "Returning to menu"
	elif mode == "tutorial":
		_title_label.text = "Starting tutorial"
	else:
		_title_label.text = "Filling the tank  -  %s" % str(Engine.get_meta("difficulty", "medium")).capitalize()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", UI.TEXT)
	vbox.add_child(_title_label)

	_stage_label = Label.new()
	_stage_label.text = "Preparing aquarium..."
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.add_theme_font_size_override("font_size", 13)
	_stage_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
	vbox.add_child(_stage_label)

	_progress_bar = UI.make_progress_bar(UI.ACCENT, 4.0)
	_progress_bar.max_value = 100.0
	vbox.add_child(_progress_bar)

	_percent_label = Label.new()
	_percent_label.text = "0%"
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent_label.add_theme_font_size_override("font_size", 13)
	_percent_label.add_theme_color_override("font_color", UI.TEXT_FAINT)
	vbox.add_child(_percent_label)

	_tip_label = Label.new()
	_tip_label.text = TIPS[randi() % TIPS.size()]
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_size_override("font_size", 12)
	_tip_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
	vbox.add_child(_tip_label)


func _process(delta: float) -> void:
	if _transitioned:
		return

	_elapsed += delta

	var real_progress := 0.0
	var is_loaded := false
	var packed_scene: PackedScene = null

	if _load_started:
		var prog_arr := []
		var status := ResourceLoader.load_threaded_get_status(_target_path, prog_arr)
		if not prog_arr.is_empty():
			real_progress = float(prog_arr[0])
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			real_progress = 1.0
			is_loaded = true
			packed_scene = ResourceLoader.load_threaded_get(_target_path) as PackedScene
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_load_started = false
			is_loaded = true
	else:
		real_progress = 1.0
		is_loaded = true

	var time_progress := clampf(_elapsed / MIN_DISPLAY_TIME, 0.0, 1.0)
	var target_prog := minf(real_progress, time_progress)
	_display_progress = move_toward(_display_progress, target_prog, delta * 1.45)

	var pct := int(roundf(_display_progress * 100.0))
	if _progress_bar:
		_progress_bar.value = _display_progress * 100.0
	if _percent_label:
		_percent_label.text = "%d%%" % pct

	if _stage_label:
		if pct < 35:
			_stage_label.text = "Warming up the water..."
		elif pct < 75:
			_stage_label.text = "Adding fish and plants..."
		else:
			_stage_label.text = "Ready"

	if is_loaded and _display_progress >= 0.995:
		_transitioned = true
		if packed_scene != null:
			get_tree().change_scene_to_packed(packed_scene)
		else:
			get_tree().change_scene_to_file(_target_path)
