extends Node3D

## Main 3D Insaniquarium-inspired game controller.
## Manages economy (coins), tile-based Duckweed & Water Hyacinth food producers,
## default Pet Crab coin collector, Peaceful-phase Decorating Mode, Archer Fish defenders,
## Kingfisher wave phases, the minimal HUD, and the Tutorial game mode hooks.
## All difficulty numbers come from scripts/game_balance.gd.
##
## NOTE FOR FUTURE DEVELOPERS:
## Never use or put any emojis anywhere in the game (UI, scripts, comments, logs, or assets).

const SwimmingFishScript = preload("res://scripts/swimming_fish.gd")
const DuckweedTileScript = preload("res://scripts/duckweed_tile.gd")
const CoinDropScript = preload("res://scripts/coin_drop.gd")
const ArcherFishScript = preload("res://scripts/archer_fish.gd")
const PetCrabScript = preload("res://scripts/pet_crab.gd")
const TankDecorationScript = preload("res://scripts/tank_decoration.gd")
const KingfisherThreatScript = preload("res://scripts/kingfisher_threat.gd")
const AquariumCameraScript = preload("res://scripts/aquarium_camera.gd")
const TutorialDirectorScript = preload("res://scripts/tutorial_director.gd")
const LoadingScreenScript = preload("res://scripts/loading_screen.gd")
const Balance = preload("res://scripts/game_balance.gd")
const UI = preload("res://scripts/ui_style.gd")
const PauseMenuScene = preload("res://pause_menu.tscn")

const FISH_MODELS := {
	0: preload("res://assets/fih/baby.glb"),
	1: preload("res://assets/fih/medium.glb"),
	2: preload("res://assets/fih/adult.glb"),
}

const TANK_BOUNDS := AABB(Vector3(-6.7, 1.05, -3.9), Vector3(13.4, 4.75, 7.8))
const WATER_SURFACE_Y: float = 6.37
const MAX_SURFACE_PLANTS: int = 12

# Ordered grid cells (6x4 grid) from center outward for default tile placement
const PREFERRED_GRID_CELLS: Array[Vector2i] = [
	Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(3, 2),
	Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 2), Vector2i(4, 2),
	Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 3), Vector2i(3, 3),
	Vector2i(1, 0), Vector2i(4, 0), Vector2i(1, 3), Vector2i(4, 3),
	Vector2i(0, 1), Vector2i(5, 1), Vector2i(0, 2), Vector2i(5, 2),
	Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 3), Vector2i(5, 3),
]

const COST_BABY_FISH: int = Balance.COST_BABY_FISH
const COST_DUCKWEED: int = Balance.COST_DUCKWEED

const SHOP_IDS: Array[String] = ["fish", "plant", "upgrade", "archer", "crab", "decorate"]
const SHOP_KEYS := {
	KEY_1: "fish", KEY_2: "plant", KEY_3: "upgrade",
	KEY_4: "archer", KEY_5: "crab", KEY_6: "decorate",
}

enum WavePhase { PEACEFUL, CAREFUL, ATTACK }

## Emitted for tutorial objectives: coin_click, select, fish_fed, buy_fish, buy_plant,
## upgrade_plant, buy_archer, upgrade_crab, bird_killed, decor_on, decor_off.
signal tutorial_event(event_name: String, data: Variant)

var game_mode: String = "endless"
var is_tutorial: bool = false
var is_game_over: bool = false

var coins: int = Balance.STARTING_COINS
var current_wave: int = 1
var current_phase: WavePhase = WavePhase.PEACEFUL
var phase_timer: float = 60.0
var phase_duration: float = 60.0
var wave_timer_enabled: bool = true
var total_fish_spawned: int = 0
var recent_event_text: String = ""
var recent_event_timer: float = 0.0

var _duckweed_tiles: Array[Node3D] = []
var _decorations: Array[Node3D] = []
var _pet_crab: Node3D = null
var _active_kingfishers: Array[Node3D] = []
var is_decorating_mode: bool = false
var decor_layer: int = AquariumCameraScript.DECOR_LAYER_SURFACE

var _shop_locked: Dictionary = {}
var _shop_highlight: String = ""
var _tutorial_training_wave: bool = false
var _tutorial_director: Node = null
var _game_over_check_timer: float = 0.0
var _pulse_time: float = 0.0

@onready var fish_container: Node3D = $FishContainer
@onready var props_container: Node3D = $Tank/Decorations
@onready var camera_rig: Node3D = $AquariumCamera
@onready var hud_layer: CanvasLayer = $HUD
@onready var status_label: Label = $HUD/StatusLabel

var _duckweed_container: Node3D = null
var _coin_container: Node3D = null
var _pet_container: Node3D = null
var _threat_container: Node3D = null
var _pause_menu: CanvasLayer = null

# --- HUD references --------------------------------------------------------
var _stats_row: HBoxContainer = null
var _coins_value: Label = null
var _fish_value: Label = null
var _fish_hungry: Label = null
var _defense_value: Label = null
var _controls_hint: PanelContainer = null
var _hints_visible: bool = true
var _hints_timer: float = 45.0

var _wave_title: Label = null
var _wave_phase: Label = null
var _wave_bar: ProgressBar = null
var _wave_sub: Label = null

var _call_wave_btn: Button = null
var _pause_btn: Button = null

var _toast_panel: PanelContainer = null
var _event_label: Label = null

var _shop_panel: PanelContainer = null
var _shop_cards: Dictionary = {}

var _decor_panel: PanelContainer = null
var _surface_tab_btn: Button = null
var _floor_tab_btn: Button = null
var _surface_decor_box: HBoxContainer = null
var _floor_decor_grid: GridContainer = null
var _decor_buy_plant_btn: Button = null
var _decor_upg_plant_btn: Button = null
var _decor_hint: Label = null
var _decor_buttons: Array[Dictionary] = []
var _styled_layer: int = -1

var _inspector_panel: PanelContainer = null
var _insp_title: Label = null
var _insp_role: Label = null
var _insp_info: Label = null
var _ctx_upgrade_btn: Button = null
var _ctx_move_btn: Button = null
var _ctx_rotate_btn: Button = null
var _ctx_remove_btn: Button = null

var _game_over_root: Control = null
var _game_over_sub: Label = null


func _ready() -> void:
	randomize()
	get_tree().paused = false
	if Engine.has_meta("game_mode"):
		game_mode = str(Engine.get_meta("game_mode"))
	is_tutorial = (game_mode == "tutorial")
	coins = Balance.STARTING_COINS

	_duckweed_container = Node3D.new()
	_duckweed_container.name = "DuckweedContainer"
	add_child(_duckweed_container)

	_coin_container = Node3D.new()
	_coin_container.name = "CoinContainer"
	add_child(_coin_container)

	_pet_container = Node3D.new()
	_pet_container.name = "PetContainer"
	add_child(_pet_container)

	_threat_container = Node3D.new()
	_threat_container.name = "ThreatContainer"
	add_child(_threat_container)

	_pause_menu = get_node_or_null("PauseMenu") as CanvasLayer
	if _pause_menu == null and PauseMenuScene != null:
		_pause_menu = PauseMenuScene.instantiate() as CanvasLayer
		add_child(_pause_menu)

	_build_gameplay_hud()

	# 1. Default 1 sparse duckweed tile snapped on the water surface grid
	_spawn_duckweed_tile()

	# 2. Default Pet Crab on the tank bottom (collects falling coins, upgradable speed)
	_spawn_pet_crab()

	# 3. Starter fish school
	for _i in range(Balance.STARTING_FISH):
		_spawn_goldfish(SwimmingFishScript.SizeCategory.BABY, false)

	if camera_rig:
		if camera_rig.has_signal("focus_changed"):
			camera_rig.connect("focus_changed", _on_focus_changed)
		if camera_rig.has_signal("entity_moved"):
			camera_rig.connect("entity_moved", _on_entity_moved)

	_enter_phase(WavePhase.PEACEFUL)

	if is_tutorial:
		wave_timer_enabled = false
		for id in SHOP_IDS:
			_shop_locked[id] = true
		_tutorial_director = TutorialDirectorScript.new()
		_tutorial_director.name = "TutorialDirector"
		add_child(_tutorial_director)
		_tutorial_director.call("setup", self, hud_layer)
		if _controls_hint:
			_controls_hint.visible = false
	else:
		_set_event("Build up your tank. The first birds arrive in %ds." % int(phase_timer), 6.0)

	_update_hud()


func _process(delta: float) -> void:
	_pulse_time += delta
	if _hints_timer > 0.0:
		_hints_timer -= delta
		if _hints_timer <= 0.0:
			_hints_visible = false
	if recent_event_timer > 0.0:
		recent_event_timer = maxf(0.0, recent_event_timer - delta)

	if not is_game_over:
		_update_wave_timer(delta)
		_game_over_check_timer -= delta
		if _game_over_check_timer <= 0.0:
			_game_over_check_timer = 0.5
			_check_game_over()
	_update_hud()


func _input(event: InputEvent) -> void:
	if get_tree().paused or is_game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_B:
			_on_toggle_decorate_pressed()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_TAB and is_decorating_mode:
			_on_toggle_decor_layer_pressed()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_ESCAPE and is_decorating_mode:
			exit_decorating_mode()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_U:
			_on_ctx_upgrade_pressed()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_H:
			_hints_visible = not _hints_visible
			_hints_timer = 0.0
			get_viewport().set_input_as_handled()
		elif SHOP_KEYS.has(ke.keycode) and not is_decorating_mode:
			_use_shop_item(String(SHOP_KEYS[ke.keycode]))
			get_viewport().set_input_as_handled()


# =============================================================================
# Waves
# =============================================================================

func _update_wave_timer(delta: float) -> void:
	if not wave_timer_enabled:
		return
	# Pause the Peaceful phase timer while the player is in Decorating Mode
	if current_phase == WavePhase.PEACEFUL and is_decorating_mode:
		return
	phase_timer -= delta
	if phase_timer <= 0.0:
		_advance_to_next_phase()


func _enter_phase(new_phase: WavePhase) -> void:
	current_phase = new_phase
	var is_peaceful := (current_phase == WavePhase.PEACEFUL)
	if not is_peaceful and is_decorating_mode:
		_set_decorating_mode(false)
	if camera_rig and camera_rig.has_method("set_can_decorate"):
		camera_rig.call("set_can_decorate", is_peaceful)

	match current_phase:
		WavePhase.PEACEFUL:
			phase_duration = Balance.peaceful_duration(current_wave)
			phase_timer = phase_duration
			for kf in _active_kingfishers:
				if is_instance_valid(kf):
					if kf.has_method("retreat_and_despawn"):
						kf.call("retreat_and_despawn")
					else:
						kf.queue_free()
			_active_kingfishers.clear()
			if current_wave > 1 and not is_tutorial:
				_set_event("Wave %d. Safe for now - grow your tank." % current_wave)

		WavePhase.CAREFUL:
			phase_duration = 5.0 if _tutorial_training_wave else Balance.careful_duration(current_wave)
			phase_timer = phase_duration
			_spawn_kingfishers_if_needed()
			var count := _get_alive_kingfishers().size()
			for kf in _active_kingfishers:
				if is_instance_valid(kf) and kf.has_method("set_phase_observe"):
					kf.call("set_phase_observe")
			_set_event("%s circling above. Get ready." % _bird_word(count))

		WavePhase.ATTACK:
			phase_duration = 600.0 if _tutorial_training_wave else Balance.attack_duration(current_wave)
			phase_timer = phase_duration
			_spawn_kingfishers_if_needed()
			var count := _get_alive_kingfishers().size()
			for kf in _active_kingfishers:
				if is_instance_valid(kf) and kf.has_method("set_phase_attack"):
					kf.call("set_phase_attack")
			_set_event("%s attacking. Click them to fight back." % _bird_word(count))


func _bird_word(count: int) -> String:
	return "%d %s" % [count, "bird" if count == 1 else "birds"]


func _advance_to_next_phase() -> void:
	if is_decorating_mode:
		_set_decorating_mode(false)
	match current_phase:
		WavePhase.PEACEFUL:
			_enter_phase(WavePhase.CAREFUL)
		WavePhase.CAREFUL:
			_enter_phase(WavePhase.ATTACK)
		WavePhase.ATTACK:
			_finish_wave()


func _finish_wave() -> void:
	current_wave += 1
	if _tutorial_training_wave:
		_tutorial_training_wave = false
		wave_timer_enabled = false
	_enter_phase(WavePhase.PEACEFUL)


func _get_alive_kingfishers() -> Array[Node3D]:
	var alive: Array[Node3D] = []
	for kf in _active_kingfishers:
		if is_instance_valid(kf) and kf.get("phase_mode") != KingfisherThreatScript.PhaseMode.DEFEATED:
			alive.append(kf)
	return alive


func _spawn_kingfishers_if_needed() -> void:
	_active_kingfishers = _get_alive_kingfishers()
	if not _active_kingfishers.is_empty():
		return

	var bird_count := 1 if _tutorial_training_wave else Balance.bird_count(current_wave)
	for i in range(bird_count):
		var kf: Node3D = KingfisherThreatScript.new()
		kf.name = "Kingfisher_W%d_%02d" % [current_wave, i + 1]
		kf.set("wave_level", current_wave)
		kf.set("bird_index", i)
		kf.set("total_birds_in_wave", bird_count)
		if _tutorial_training_wave:
			kf.max_hp = 90.0
			kf.set("speed_boost", 0.85)
			kf.set("aggression", 0.0)
			kf.set("training_mode", true)
		else:
			kf.max_hp = Balance.bird_hp(current_wave)
			kf.set("speed_boost", Balance.bird_speed(current_wave))
			kf.set("aggression", Balance.bird_aggression(current_wave))
		kf.hp = kf.max_hp
		var angle := (TAU * float(i)) / maxf(float(bird_count), 1.0)
		kf.position = Vector3(cos(angle) * 5.2, 9.5 + float(i % 3) * 0.35, sin(angle) * 3.2)
		kf.connect("fish_snatched", _on_kingfisher_snatched_fish)
		kf.connect("threat_killed", _on_kingfisher_killed)
		_threat_container.add_child(kf)
		_active_kingfishers.append(kf)


func _on_kingfisher_snatched_fish(_fish: Node3D) -> void:
	_set_event("A Kingfisher caught one of your fish.")


func _on_kingfisher_killed(threat: Node3D) -> void:
	var drop_pos := Vector3(0.0, 6.0, 0.0)
	if is_instance_valid(threat):
		drop_pos = Vector3(
			clampf(threat.global_position.x, -5.5, 5.5),
			5.8,
			clampf(threat.global_position.z, -3.2, 3.2)
		)
	_spawn_coin_at(drop_pos, CoinDropScript.CoinTier.GOLD)
	_active_kingfishers.erase(threat)
	tutorial_event.emit("bird_killed", threat)

	var remaining := _get_alive_kingfishers().size()
	if remaining <= 0:
		_active_kingfishers.clear()
		_set_event("Wave cleared. Bonus gold coin dropped.")
		_finish_wave()
	else:
		_set_event("Kingfisher defeated. %d left." % remaining)


# =============================================================================
# Spawning
# =============================================================================

func _find_free_grid_cell(group_name: String) -> Vector2i:
	for cell in PREFERRED_GRID_CELLS:
		var occupied := false
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node3D and is_instance_valid(node):
				if node.get("grid_cell") == cell:
					occupied = true
					break
		if not occupied:
			return cell
	return PREFERRED_GRID_CELLS[0]


func _spawn_duckweed_tile() -> Node3D:
	if _duckweed_tiles.size() >= MAX_SURFACE_PLANTS:
		return null
	var idx := _duckweed_tiles.size()
	var cell := _find_free_grid_cell("duckweed")
	var world_pos := AquariumCameraScript.grid_to_world(cell, WATER_SURFACE_Y)

	var tile: Node3D = DuckweedTileScript.new()
	tile.name = "FoodProducer_%02d" % (idx + 1)
	tile.set("tile_index", idx)
	tile.set("grid_cell", cell)
	tile.position = world_pos
	tile.connect("baby_goldfish_spawned", _on_hyacinth_spawned_baby)
	tile.connect("feeding_completed", _on_tile_feeding_completed)
	_duckweed_container.add_child(tile)
	_duckweed_tiles.append(tile)
	return tile


func _on_tile_feeding_completed(_tile: Node3D, fish: Node3D) -> void:
	tutorial_event.emit("fish_fed", fish)


func _on_hyacinth_spawned_baby(_tile: Node3D, spawn_pos: Vector3) -> void:
	_spawn_goldfish_at(SwimmingFishScript.SizeCategory.BABY, spawn_pos)
	_set_event("Your Water Hyacinth hatched a baby goldfish.")


func _spawn_pet_crab() -> Node3D:
	if is_instance_valid(_pet_crab):
		return _pet_crab
	var crab: Node3D = PetCrabScript.new()
	crab.name = "PetCrab"
	crab.set("tank_bounds", TANK_BOUNDS)
	crab.position = Vector3(0.0, PetCrabScript.FLOOR_Y, 1.2)
	_pet_container.add_child(crab)
	_pet_crab = crab
	return crab


func _spawn_goldfish(size_cat: int = 0, from_top: bool = true) -> Node3D:
	var min_p := TANK_BOUNDS.position
	var max_p := TANK_BOUNDS.position + TANK_BOUNDS.size
	var pos := Vector3.ZERO
	if from_top:
		pos = Vector3(
			randf_range(min_p.x + 1.5, max_p.x - 1.5),
			max_p.y - 0.15,
			randf_range(min_p.z + 1.2, max_p.z - 1.2)
		)
	else:
		pos = Vector3(
			randf_range(min_p.x + 0.8, max_p.x - 0.8),
			randf_range(min_p.y + 0.5, max_p.y - 0.5),
			randf_range(min_p.z + 0.8, max_p.z - 0.8)
		)
	return _spawn_goldfish_at(size_cat, pos)


func _spawn_goldfish_at(size_cat: int, world_pos: Vector3) -> Node3D:
	total_fish_spawned += 1
	var fish: Node3D = SwimmingFishScript.new()
	var variant_idx: int = (total_fish_spawned - 1) % 4

	fish.name = "Goldfish_%02d" % total_fish_spawned
	fish.set("size_category", size_cat)
	fish.set("variant", variant_idx)
	fish.set("tank_bounds", TANK_BOUNDS)
	if is_tutorial:
		# Tutorial fish never starve, so the lesson can go at the player's pace
		fish.set("max_starve_time", 600.0)

	var glb_scene: PackedScene = FISH_MODELS.get(size_cat, FISH_MODELS[0])
	var model_instance := glb_scene.instantiate()
	fish.add_child(model_instance)

	fish.position = world_pos
	fish.rotation.y = randf() * TAU

	fish.connect("coin_dropped", _on_fish_coin_dropped)
	fish.connect("fish_died", _on_fish_died)
	fish_container.add_child(fish)
	return fish


func _spawn_archer_fish() -> Node3D:
	var archer: Node3D = ArcherFishScript.new()
	var count := get_tree().get_nodes_in_group("archerfish").size() + 1
	archer.name = "ArcherFish_%02d" % count
	archer.set("tank_bounds", TANK_BOUNDS)

	var min_p := TANK_BOUNDS.position
	var max_p := TANK_BOUNDS.position + TANK_BOUNDS.size
	archer.position = Vector3(
		randf_range(min_p.x + 1.2, max_p.x - 1.2),
		max_p.y - 0.3,
		randf_range(min_p.z + 1.0, max_p.z - 1.0)
	)
	archer.rotation.y = randf() * TAU
	_pet_container.add_child(archer)
	return archer


func _spawn_decoration(decor_id: String, cell: Vector2i, rot_y: float = 0.0) -> Node3D:
	var decor: Node3D = TankDecorationScript.new()
	decor.set("decor_id", decor_id)
	decor.set("grid_cell", cell)
	decor.name = "Decor_%s_%02d" % [decor_id, _decorations.size() + 1]
	decor.position = AquariumCameraScript.grid_to_world(cell, TankDecorationScript.FLOOR_Y)
	decor.rotation.y = rot_y
	props_container.add_child(decor)
	_decorations.append(decor)
	return decor


func _on_fish_coin_dropped(world_pos: Vector3, size_cat: int, _stress: int) -> void:
	var tier := CoinDropScript.CoinTier.COPPER
	if size_cat == SwimmingFishScript.SizeCategory.MEDIUM:
		tier = CoinDropScript.CoinTier.SILVER
	elif size_cat == SwimmingFishScript.SizeCategory.ADULT:
		tier = CoinDropScript.CoinTier.GOLD
	_spawn_coin_at(world_pos, tier)


func _spawn_coin_at(world_pos: Vector3, tier: int) -> void:
	var coin: Node3D = CoinDropScript.new()
	coin.set("tier", tier)
	coin.position = world_pos
	coin.connect("collected", _on_coin_collected)
	_coin_container.add_child(coin)


func _on_coin_collected(value: int, coin: Node3D) -> void:
	coins += value
	if is_instance_valid(coin) and bool(coin.get("collected_by_player")):
		tutorial_event.emit("coin_click", coin)


func _on_fish_died(_fish: Node3D, reason: String) -> void:
	if reason.begins_with("Snatched"):
		return  # already announced by the kingfisher signal
	_set_event("A goldfish starved. Add plants so fish can eat sooner.")


# =============================================================================
# Shop actions
# =============================================================================

func _is_locked(id: String) -> bool:
	if bool(_shop_locked.get(id, false)):
		_set_event("This unlocks later in the tutorial.")
		return true
	return false


func _use_shop_item(id: String) -> void:
	match id:
		"fish":
			_on_buy_baby_fish_pressed()
		"plant":
			_on_buy_duckweed_pressed()
		"upgrade":
			_on_upgrade_plant_pressed()
		"archer":
			_on_buy_archer_fish_pressed()
		"crab":
			_on_upgrade_crab_speed_pressed()
		"decorate":
			_on_toggle_decorate_pressed()


func _on_buy_baby_fish_pressed() -> void:
	if _is_locked("fish"):
		return
	if coins < COST_BABY_FISH:
		_set_event("Need %d coins for a goldfish." % COST_BABY_FISH)
		return
	coins -= COST_BABY_FISH
	var fish := _spawn_goldfish(SwimmingFishScript.SizeCategory.BABY, true)
	_set_event("A baby goldfish joined your tank.")
	tutorial_event.emit("buy_fish", fish)


func _on_buy_duckweed_pressed() -> void:
	if _is_locked("plant"):
		return
	if _duckweed_tiles.size() >= MAX_SURFACE_PLANTS:
		_set_event("The surface is full (%d plants)." % MAX_SURFACE_PLANTS)
		return
	if coins < COST_DUCKWEED:
		_set_event("Need %d coins for a Duckweed." % COST_DUCKWEED)
		return
	coins -= COST_DUCKWEED
	var tile := _spawn_duckweed_tile()
	if tile:
		if camera_rig and camera_rig.has_method("focus_on_fish"):
			camera_rig.call("focus_on_fish", tile)
			if is_decorating_mode:
				camera_rig.set("is_move_mode", true)
		_set_event("Duckweed placed on the surface.")
		tutorial_event.emit("buy_plant", tile)


func _find_target_plant_for_upgrade() -> Node3D:
	var focused: Node3D = _get_focused()
	if is_instance_valid(focused) and focused.is_in_group("duckweed") and bool(focused.call("can_upgrade")):
		return focused
	# Otherwise pick the lowest-tier upgradable food producer tile in the tank
	var best_tile: Node3D = null
	var best_tier := 999
	for tile in _duckweed_tiles:
		if is_instance_valid(tile) and bool(tile.call("can_upgrade")):
			var t_lv := int(tile.get("tier"))
			if t_lv < best_tier:
				best_tier = t_lv
				best_tile = tile
	return best_tile


func get_plant_upgrade_cost() -> int:
	var tile := _find_target_plant_for_upgrade()
	return int(tile.call("get_upgrade_cost")) if tile != null else 0


func _upgrade_plant(target_tile: Node3D) -> void:
	if target_tile == null:
		_set_event("All plants are at max level.")
		return
	if not bool(target_tile.call("can_upgrade")):
		_set_event("This plant is already at max level.")
		return
	var cost := int(target_tile.call("get_upgrade_cost"))
	var next_name := str(target_tile.call("get_next_tier_name"))
	if coins < cost:
		_set_event("Need %d coins to upgrade to %s." % [cost, next_name])
		return
	coins -= cost
	target_tile.call("upgrade_tier")
	if camera_rig and camera_rig.has_method("focus_on_fish"):
		camera_rig.call("focus_on_fish", target_tile)
	_set_event("Plant upgraded to %s." % next_name)
	tutorial_event.emit("upgrade_plant", target_tile)


func _on_upgrade_plant_pressed() -> void:
	if _is_locked("upgrade"):
		return
	_upgrade_plant(_find_target_plant_for_upgrade())


func get_archer_fish_cost() -> int:
	var count := get_tree().get_nodes_in_group("archerfish").size() if get_tree() else 0
	return Balance.archer_cost(count)


func _on_buy_archer_fish_pressed() -> void:
	if _is_locked("archer"):
		return
	var cost := get_archer_fish_cost()
	if coins < cost:
		_set_event("Need %d coins for an Archer Fish." % cost)
		return
	coins -= cost
	var archer := _spawn_archer_fish()
	_set_event("An Archer Fish now guards your tank.")
	tutorial_event.emit("buy_archer", archer)


func _on_upgrade_crab_speed_pressed() -> void:
	if _is_locked("crab"):
		return
	if not is_instance_valid(_pet_crab):
		_spawn_pet_crab()
	if not bool(_pet_crab.call("can_upgrade_speed")):
		_set_event("Your crab is already at top speed.")
		return
	var cost := int(_pet_crab.call("get_upgrade_cost"))
	if coins < cost:
		_set_event("Need %d coins to upgrade the crab." % cost)
		return
	coins -= cost
	_pet_crab.call("upgrade_speed")
	_set_event("Crab speed is now Lv.%d." % int(_pet_crab.get("speed_level")))
	tutorial_event.emit("upgrade_crab", _pet_crab)


# =============================================================================
# Decorating mode
# =============================================================================

func exit_decorating_mode() -> void:
	if is_decorating_mode:
		_set_decorating_mode(false)


func _set_decor_layer(new_layer: int) -> void:
	decor_layer = new_layer
	if camera_rig and camera_rig.has_method("set_decor_layer"):
		camera_rig.call("set_decor_layer", decor_layer)
	_update_hud()


func _on_toggle_decor_layer_pressed() -> void:
	if decor_layer == AquariumCameraScript.DECOR_LAYER_SURFACE:
		_set_decor_layer(AquariumCameraScript.DECOR_LAYER_FLOOR)
	else:
		_set_decor_layer(AquariumCameraScript.DECOR_LAYER_SURFACE)


func _set_decorating_mode(active: bool) -> void:
	var was_active := is_decorating_mode
	var can_enable := active and (current_phase == WavePhase.PEACEFUL)
	is_decorating_mode = can_enable
	if camera_rig:
		if camera_rig.has_method("set_decor_layer"):
			camera_rig.call("set_decor_layer", decor_layer)
		if camera_rig.has_method("set_decorating_mode"):
			camera_rig.call("set_decorating_mode", is_decorating_mode)
	if is_decorating_mode and not was_active:
		tutorial_event.emit("decor_on", null)
	elif was_active and not is_decorating_mode:
		tutorial_event.emit("decor_off", null)
	_update_hud()


func _on_toggle_decorate_pressed() -> void:
	if _is_locked("decorate"):
		return
	if current_phase != WavePhase.PEACEFUL:
		_set_event("You can only decorate while it is peaceful.")
		return
	if not is_decorating_mode:
		var focused: Node3D = _get_focused()
		if is_instance_valid(focused):
			if focused.is_in_group("duckweed"):
				decor_layer = AquariumCameraScript.DECOR_LAYER_SURFACE
			elif focused.is_in_group("decorations"):
				decor_layer = AquariumCameraScript.DECOR_LAYER_FLOOR
	_set_decorating_mode(not is_decorating_mode)


func _on_buy_decoration_pressed(decor_id: String) -> void:
	if current_phase != WavePhase.PEACEFUL:
		_set_event("You can only decorate while it is peaceful.")
		return
	if _decorations.size() >= PREFERRED_GRID_CELLS.size():
		_set_event("Every floor tile is already used.")
		return
	var entry := TankDecorationScript.get_catalog_entry(decor_id)
	var cost := int(entry["cost"])
	if coins < cost:
		_set_event("Need %d coins for %s." % [cost, String(entry["name"])])
		return
	coins -= cost
	_set_decor_layer(AquariumCameraScript.DECOR_LAYER_FLOOR)
	if not is_decorating_mode:
		_set_decorating_mode(true)
	var cell := _find_free_grid_cell("decorations")
	var decor := _spawn_decoration(decor_id, cell, 0.0)
	if camera_rig and camera_rig.has_method("focus_on_fish"):
		camera_rig.call("focus_on_fish", decor)
		camera_rig.set("is_move_mode", true)
	_set_event("%s placed. Click a tile to move it." % String(entry["name"]))


# =============================================================================
# Inspector actions
# =============================================================================

func _on_ctx_upgrade_pressed() -> void:
	var focused: Node3D = _get_focused()
	if is_instance_valid(focused):
		if focused.is_in_group("duckweed"):
			if _is_locked("upgrade"):
				return
			_upgrade_plant(focused)
			return
		elif focused.is_in_group("crab"):
			_on_upgrade_crab_speed_pressed()
			return
	# Fallback if U pressed without selection: upgrade a food producer
	_on_upgrade_plant_pressed()


func _on_ctx_move_pressed() -> void:
	if current_phase != WavePhase.PEACEFUL:
		_set_event("You can only move things while it is peaceful.")
		return
	if bool(_shop_locked.get("decorate", false)):
		_set_event("Moving unlocks later in the tutorial.")
		return
	var focused: Node3D = _get_focused()
	if is_instance_valid(focused):
		if focused.is_in_group("duckweed"):
			_set_decor_layer(AquariumCameraScript.DECOR_LAYER_SURFACE)
		elif focused.is_in_group("decorations"):
			_set_decor_layer(AquariumCameraScript.DECOR_LAYER_FLOOR)
	if not is_decorating_mode:
		_set_decorating_mode(true)
	if camera_rig and camera_rig.has_method("start_move_mode_for_selected"):
		camera_rig.call("start_move_mode_for_selected")


func _on_ctx_rotate_pressed() -> void:
	var focused: Node3D = _get_focused()
	if is_instance_valid(focused):
		if focused.has_method("rotate_step"):
			focused.call("rotate_step")
		else:
			focused.rotation.y = wrapf(focused.rotation.y + PI * 0.5, 0.0, TAU)


func _on_ctx_remove_decor_pressed() -> void:
	if current_phase != WavePhase.PEACEFUL:
		return
	var focused: Node3D = _get_focused()
	if is_instance_valid(focused) and focused.is_in_group("decorations"):
		var refund := int(focused.get("decor_cost")) / 2
		coins += refund
		var d_name := str(focused.get("decor_name"))
		_decorations.erase(focused)
		if camera_rig and camera_rig.has_method("clear_focus"):
			camera_rig.call("clear_focus")
		focused.queue_free()
		_set_event("Removed %s (+%d coins)." % [d_name, refund])


func _on_call_wave_pressed() -> void:
	if current_phase == WavePhase.PEACEFUL and not is_tutorial:
		_advance_to_next_phase()


func _on_pause_pressed() -> void:
	if _pause_menu and _pause_menu.has_method("open_pause"):
		_pause_menu.call("open_pause")


func _on_deselect_pressed() -> void:
	if camera_rig and camera_rig.has_method("clear_focus"):
		camera_rig.call("clear_focus")


func _on_entity_moved(_entity: Node3D) -> void:
	_update_hud()


func _on_focus_changed(entity: Node3D) -> void:
	if is_instance_valid(entity):
		tutorial_event.emit("select", entity)
	_update_hud()


func _get_focused() -> Node3D:
	# Read the camera selection safely: the selected fish may have been freed (eaten)
	if camera_rig == null:
		return null
	var f: Variant = camera_rig.get("focused_fish")
	if f == null or not is_instance_valid(f):
		return null
	return f as Node3D


func _set_event(msg: String, duration: float = 3.5) -> void:
	recent_event_text = msg
	recent_event_timer = duration


# =============================================================================
# Game over (endless mode only)
# =============================================================================

func _count_alive_fish() -> int:
	var alive := 0
	for node in get_tree().get_nodes_in_group("goldfish"):
		if is_instance_valid(node) and not bool(node.get("is_dead")):
			alive += 1
	return alive


func _check_game_over() -> void:
	if is_tutorial or is_game_over:
		return
	if _count_alive_fish() > 0:
		return
	var reachable := coins
	for node in get_tree().get_nodes_in_group("coins"):
		if is_instance_valid(node) and not bool(node.get("is_collected")):
			reachable += int(node.get("coin_value"))
	if reachable >= COST_BABY_FISH:
		return
	is_game_over = true
	if is_decorating_mode:
		_set_decorating_mode(false)
	if _game_over_sub:
		_game_over_sub.text = "Your tank made it to wave %d." % current_wave
	if _game_over_root:
		_game_over_root.visible = true


func _on_game_over_retry() -> void:
	Engine.set_meta("game_mode", game_mode)
	LoadingScreenScript.transition_to(get_tree(), "res://main.tscn")


func _on_game_over_menu() -> void:
	LoadingScreenScript.transition_to(get_tree(), "res://menu.tscn")


# =============================================================================
# Tutorial hooks (called by scripts/tutorial_director.gd)
# =============================================================================

func set_shop_locked(id: String, locked: bool) -> void:
	_shop_locked[id] = locked
	_update_hud()


func unlock_all_shop() -> void:
	for id in SHOP_IDS:
		_shop_locked[id] = false
	_update_hud()


func set_shop_highlight(id: String) -> void:
	_shop_highlight = id


func ensure_coins(amount: int) -> void:
	if coins < amount:
		var gift := amount - coins
		coins = amount
		_set_event("Tutorial gift: +%d coins." % gift)


func spawn_tutorial_coins(count: int) -> void:
	for i in range(count):
		var x := lerpf(-3.6, 3.6, float(i) / maxf(float(count - 1), 1.0))
		_spawn_coin_at(Vector3(x, 5.9, randf_range(-0.8, 0.8)), CoinDropScript.CoinTier.SILVER)


func count_free_coins() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("coins"):
		if is_instance_valid(node) and not bool(node.get("is_collected")):
			n += 1
	return n


func make_one_fish_hungry() -> void:
	for node in get_tree().get_nodes_in_group("goldfish"):
		if is_instance_valid(node) and not bool(node.get("is_dead")):
			if int(node.get("hunger_status")) == SwimmingFishScript.HungerStatus.FED:
				node.set("hunger_timer", 0.4)
				return


func tutorial_start_training_wave() -> void:
	_tutorial_training_wave = true
	wave_timer_enabled = true
	if is_decorating_mode:
		_set_decorating_mode(false)
	_enter_phase(WavePhase.CAREFUL)


func get_shop_card(id: String) -> Control:
	if _shop_cards.has(id):
		return _shop_cards[id]["btn"]
	return null


# =============================================================================
# HUD construction
# =============================================================================

func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _make_stat_block(caption: String, value_color: Color) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_ignore(box)
	box.add_child(UI.make_caption(caption))
	var value := UI.make_label("0", 20, value_color)
	box.add_child(value)
	_stats_row.add_child(box)
	return value



func _build_gameplay_hud() -> void:
	if hud_layer == null:
		return
	if status_label:
		status_label.visible = false

	# 1. Top-left stats: coins, fish, defenders
	var stats_panel := UI.make_panel(UI.PANEL, 10, 16.0, 10.0)
	stats_panel.name = "StatsPanel"
	stats_panel.position = Vector2(16.0, 16.0)
	hud_layer.add_child(stats_panel)

	_stats_row = HBoxContainer.new()
	_stats_row.add_theme_constant_override("separation", 22)
	_ignore(_stats_row)
	stats_panel.add_child(_stats_row)

	_coins_value = _make_stat_block("Coins", UI.GOLD)
	_coins_value.custom_minimum_size = Vector2(64.0, 0.0)
	_fish_value = _make_stat_block("Fish", UI.TEXT)
	_fish_hungry = UI.make_label("", 10, UI.WARN)
	(_fish_value.get_parent() as VBoxContainer).add_child(_fish_hungry)
	_defense_value = _make_stat_block("Archers", UI.ACCENT)

	# Controls hint (left, under the stats). Fades out after a while, H shows it again.
	_controls_hint = UI.make_panel(Color(0.04, 0.085, 0.13, 0.62), 10, 14.0, 10.0)
	_ignore(_controls_hint)
	_controls_hint.position = Vector2(16.0, 104.0)
	hud_layer.add_child(_controls_hint)
	var hint_grid := GridContainer.new()
	hint_grid.columns = 2
	hint_grid.add_theme_constant_override("h_separation", 12)
	hint_grid.add_theme_constant_override("v_separation", 3)
	_ignore(hint_grid)
	_controls_hint.add_child(hint_grid)
	for pair in [
		["Click", "select, collect coins, hit birds"],
		["Drag", "rotate view"],
		["Scroll", "zoom"],
		["1 - 6", "shop"],
		["B", "decorate"],
		["P", "pause"],
		["H", "hide these hints"],
	]:
		hint_grid.add_child(UI.make_label(String(pair[0]), 11, UI.ACCENT))
		hint_grid.add_child(UI.make_label(String(pair[1]), 11, UI.TEXT_MUTED))

	# 2. Top-center wave status
	var wave_anchor := Control.new()
	_ignore(wave_anchor)
	wave_anchor.anchor_left = 0.5
	wave_anchor.anchor_right = 0.5
	wave_anchor.offset_left = -180.0
	wave_anchor.offset_right = 180.0
	wave_anchor.offset_top = 16.0
	wave_anchor.offset_bottom = 90.0
	hud_layer.add_child(wave_anchor)

	var wave_panel := UI.make_panel(UI.PANEL, 10, 16.0, 10.0)
	wave_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	wave_anchor.add_child(wave_panel)

	var wave_vbox := VBoxContainer.new()
	wave_vbox.add_theme_constant_override("separation", 6)
	_ignore(wave_vbox)
	wave_panel.add_child(wave_vbox)

	var wave_head := HBoxContainer.new()
	_ignore(wave_head)
	wave_vbox.add_child(wave_head)
	_wave_title = UI.make_label("WAVE 1", 15, UI.TEXT)
	_wave_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_head.add_child(_wave_title)
	_wave_phase = UI.make_label("PEACEFUL", 12, UI.GOOD)
	wave_head.add_child(_wave_phase)

	_wave_bar = UI.make_progress_bar(UI.GOOD, 4.0)
	wave_vbox.add_child(_wave_bar)

	_wave_sub = UI.make_label("", 12, UI.TEXT_MUTED)
	_wave_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_vbox.add_child(_wave_sub)

	# 3. Top-right buttons
	var top_right := HBoxContainer.new()
	_ignore(top_right)
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -340.0
	top_right.offset_right = -16.0
	top_right.offset_top = 16.0
	top_right.offset_bottom = 54.0
	top_right.alignment = BoxContainer.ALIGNMENT_END
	top_right.add_theme_constant_override("separation", 8)
	hud_layer.add_child(top_right)

	_call_wave_btn = UI.make_button("Start wave now", "hud", UI.WARN, 13, 36.0)
	_call_wave_btn.tooltip_text = "Skip the rest of the peaceful time and call the birds now."
	_call_wave_btn.pressed.connect(_on_call_wave_pressed)
	top_right.add_child(_call_wave_btn)

	_pause_btn = UI.make_button("Pause", "hud", UI.ACCENT, 13, 36.0)
	_pause_btn.pressed.connect(_on_pause_pressed)
	top_right.add_child(_pause_btn)

	# 4. Toast (below the wave panel)
	var toast_center := CenterContainer.new()
	_ignore(toast_center)
	toast_center.anchor_left = 0.0
	toast_center.anchor_right = 1.0
	toast_center.offset_top = 104.0
	toast_center.offset_bottom = 136.0
	hud_layer.add_child(toast_center)

	_toast_panel = UI.make_panel(Color(0.04, 0.085, 0.13, 0.78), 16, 16.0, 6.0)
	_ignore(_toast_panel)
	toast_center.add_child(_toast_panel)
	_event_label = UI.make_label("", 13, UI.TEXT)
	_toast_panel.add_child(_event_label)

	# 5. Bottom bar holder (shop and decorate bars share this spot)
	var bottom_center := CenterContainer.new()
	_ignore(bottom_center)
	bottom_center.anchor_left = 0.0
	bottom_center.anchor_right = 1.0
	bottom_center.anchor_top = 1.0
	bottom_center.anchor_bottom = 1.0
	bottom_center.offset_top = -100.0
	bottom_center.offset_bottom = -16.0
	bottom_center.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_layer.add_child(bottom_center)

	_build_shop_bar(bottom_center)
	_build_decor_bar(bottom_center)
	_build_inspector()
	_build_game_over()


func _build_shop_bar(parent: Control) -> void:
	_shop_panel = UI.make_panel(UI.PANEL, 12, 8.0, 8.0)
	_shop_panel.name = "ShopBar"
	parent.add_child(_shop_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_ignore(row)
	_shop_panel.add_child(row)

	_add_shop_card(row, "fish", "Goldfish", "1", UI.GOLD,
		"Adds a baby goldfish. Fish drop coins and grow as they eat.")
	_add_shop_card(row, "plant", "Duckweed", "2", UI.GOOD,
		"Adds a food plant on the water surface. Each plant feeds one fish at a time.")
	_add_shop_card(row, "upgrade", "Upgrade Plant", "3", UI.GOOD,
		"Upgrades your selected (or lowest) plant so it feeds more fish at once.")
	_add_shop_card(row, "archer", "Archer Fish", "4", UI.ACCENT,
		"A defender that shoots and slows Kingfishers. Needs no food.")
	_add_shop_card(row, "crab", "Crab Speed", "5", UI.WARN,
		"Makes your Pet Crab move faster so it collects more coins.")
	_add_shop_card(row, "decorate", "Decorate", "6 / B", Color(0.80, 0.70, 1.0),
		"Pause the timer and arrange plants and decorations. Peaceful phase only.")


func _add_shop_card(row: HBoxContainer, id: String, title: String, key: String, accent: Color, tip: String) -> void:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(134.0, 58.0)
	btn.tooltip_text = tip
	UI.style_button(btn, "secondary", accent, 9)
	btn.pressed.connect(_use_shop_item.bind(id))
	row.add_child(btn)

	var margin := MarginContainer.new()
	_ignore(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 11)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	btn.add_child(margin)

	var vbox := VBoxContainer.new()
	_ignore(vbox)
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	var top := HBoxContainer.new()
	_ignore(top)
	vbox.add_child(top)
	var title_lbl := UI.make_label(title, 13, UI.TEXT)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_lbl)
	top.add_child(UI.make_label(key, 10, UI.TEXT_FAINT))

	var bottom := HBoxContainer.new()
	_ignore(bottom)
	vbox.add_child(bottom)
	var cost_lbl := UI.make_label("", 13, UI.GOLD)
	cost_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(cost_lbl)
	var detail_lbl := UI.make_label("", 10, UI.TEXT_MUTED)
	bottom.add_child(detail_lbl)

	_shop_cards[id] = {
		"btn": btn,
		"title": title_lbl,
		"cost": cost_lbl,
		"detail": detail_lbl,
	}


func _build_decor_bar(parent: Control) -> void:
	_decor_panel = UI.make_panel(UI.PANEL_SOLID, 12, 14.0, 12.0)
	_decor_panel.name = "DecorBar"
	_decor_panel.visible = false
	parent.add_child(_decor_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_ignore(vbox)
	_decor_panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_ignore(header)
	vbox.add_child(header)

	var title := UI.make_label("DECORATE", 13, UI.TEXT)
	title.custom_minimum_size = Vector2(90.0, 0.0)
	header.add_child(title)

	_surface_tab_btn = UI.make_button("Water surface", "secondary", UI.GOOD, 12, 30.0)
	_surface_tab_btn.pressed.connect(_set_decor_layer.bind(AquariumCameraScript.DECOR_LAYER_SURFACE))
	header.add_child(_surface_tab_btn)

	_floor_tab_btn = UI.make_button("Tank floor", "secondary", UI.WARN, 12, 30.0)
	_floor_tab_btn.pressed.connect(_set_decor_layer.bind(AquariumCameraScript.DECOR_LAYER_FLOOR))
	header.add_child(_floor_tab_btn)

	var spacer := Control.new()
	_ignore(spacer)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(24.0, 0.0)
	header.add_child(spacer)

	var done_btn := UI.make_button("Done  (B)", "primary", UI.ACCENT, 12, 30.0)
	done_btn.pressed.connect(exit_decorating_mode)
	header.add_child(done_btn)

	# Surface layer tools
	_surface_decor_box = HBoxContainer.new()
	_surface_decor_box.add_theme_constant_override("separation", 8)
	_ignore(_surface_decor_box)
	vbox.add_child(_surface_decor_box)

	_decor_buy_plant_btn = UI.make_button("", "secondary", UI.GOOD, 12, 34.0)
	_decor_buy_plant_btn.custom_minimum_size.x = 190.0
	_decor_buy_plant_btn.pressed.connect(_on_buy_duckweed_pressed)
	_surface_decor_box.add_child(_decor_buy_plant_btn)

	_decor_upg_plant_btn = UI.make_button("", "secondary", UI.GOOD, 12, 34.0)
	_decor_upg_plant_btn.custom_minimum_size.x = 230.0
	_decor_upg_plant_btn.pressed.connect(_on_upgrade_plant_pressed)
	_surface_decor_box.add_child(_decor_upg_plant_btn)

	var rot_btn := UI.make_button("Rotate selected  (R)", "secondary", UI.ACCENT, 12, 34.0)
	rot_btn.pressed.connect(_on_ctx_rotate_pressed)
	_surface_decor_box.add_child(rot_btn)

	# Floor layer catalog
	_floor_decor_grid = GridContainer.new()
	_floor_decor_grid.columns = 6
	_floor_decor_grid.add_theme_constant_override("h_separation", 6)
	_floor_decor_grid.add_theme_constant_override("v_separation", 6)
	_floor_decor_grid.visible = false
	_ignore(_floor_decor_grid)
	vbox.add_child(_floor_decor_grid)

	for item in TankDecorationScript.CATALOG:
		var d_id := String(item["id"])
		var d_name := String(item["name"])
		var d_cost := int(item["cost"])
		var d_btn := UI.make_button("%s   %d" % [d_name, d_cost], "secondary", UI.WARN, 12, 32.0)
		d_btn.custom_minimum_size.x = 124.0
		d_btn.pressed.connect(_on_buy_decoration_pressed.bind(d_id))
		_floor_decor_grid.add_child(d_btn)
		_decor_buttons.append({
			"btn": d_btn,
			"cost": d_cost,
		})

	_decor_hint = UI.make_label("", 11, UI.TEXT_FAINT)
	_decor_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_decor_hint)


func _build_inspector() -> void:
	_inspector_panel = UI.make_panel(UI.PANEL_SOLID, 12, 16.0, 14.0)
	_inspector_panel.name = "Inspector"
	_inspector_panel.visible = false
	_inspector_panel.anchor_left = 1.0
	_inspector_panel.anchor_right = 1.0
	_inspector_panel.anchor_top = 1.0
	_inspector_panel.anchor_bottom = 1.0
	_inspector_panel.offset_left = -296.0
	_inspector_panel.offset_right = -16.0
	_inspector_panel.offset_top = -116.0
	_inspector_panel.offset_bottom = -116.0
	_inspector_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_inspector_panel.custom_minimum_size = Vector2(280.0, 0.0)
	hud_layer.add_child(_inspector_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_ignore(vbox)
	_inspector_panel.add_child(vbox)

	var head := HBoxContainer.new()
	_ignore(head)
	vbox.add_child(head)
	var head_text := VBoxContainer.new()
	head_text.add_theme_constant_override("separation", 0)
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ignore(head_text)
	head.add_child(head_text)
	_insp_role = UI.make_caption("")
	head_text.add_child(_insp_role)
	_insp_title = UI.make_label("", 15, UI.TEXT)
	_insp_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_title.custom_minimum_size = Vector2(200.0, 0.0)
	head_text.add_child(_insp_title)

	var close_btn := UI.make_button("X", "ghost", UI.TEXT_MUTED, 12, 26.0)
	close_btn.custom_minimum_size = Vector2(26.0, 26.0)
	close_btn.tooltip_text = "Deselect (Space)"
	close_btn.pressed.connect(_on_deselect_pressed)
	head.add_child(close_btn)

	vbox.add_child(UI.make_separator())

	_insp_info = UI.make_label("", 12, UI.TEXT_MUTED)
	_insp_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_info.custom_minimum_size = Vector2(248.0, 0.0)
	vbox.add_child(_insp_info)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_ignore(actions)
	vbox.add_child(actions)

	_ctx_upgrade_btn = UI.make_button("Upgrade", "primary", UI.GOOD, 12, 32.0)
	_ctx_upgrade_btn.pressed.connect(_on_ctx_upgrade_pressed)
	actions.add_child(_ctx_upgrade_btn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_ignore(row)
	actions.add_child(row)

	_ctx_move_btn = UI.make_button("Move", "secondary", UI.ACCENT, 12, 32.0)
	_ctx_move_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ctx_move_btn.pressed.connect(_on_ctx_move_pressed)
	row.add_child(_ctx_move_btn)

	_ctx_rotate_btn = UI.make_button("Rotate  (R)", "secondary", UI.ACCENT, 12, 32.0)
	_ctx_rotate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ctx_rotate_btn.pressed.connect(_on_ctx_rotate_pressed)
	row.add_child(_ctx_rotate_btn)

	_ctx_remove_btn = UI.make_button("Remove", "secondary", UI.BAD, 12, 32.0)
	_ctx_remove_btn.pressed.connect(_on_ctx_remove_decor_pressed)
	actions.add_child(_ctx_remove_btn)


func _build_game_over() -> void:
	_game_over_root = Control.new()
	_game_over_root.name = "GameOver"
	_game_over_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_root.visible = false
	hud_layer.add_child(_game_over_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.06, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_root.add_child(dim)

	var center := CenterContainer.new()
	_ignore(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_root.add_child(center)

	var card := UI.make_panel(UI.PANEL_SOLID, 14, 32.0, 28.0)
	card.custom_minimum_size = Vector2(360.0, 0.0)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_ignore(vbox)
	card.add_child(vbox)

	var title := UI.make_label("Your tank is empty", 22, UI.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_game_over_sub = UI.make_label("", 13, UI.TEXT_MUTED)
	_game_over_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_sub)
	var tip := UI.make_label("Tip: more plants keep fish fed, Archer Fish keep birds away.", 12, UI.TEXT_FAINT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tip)
	vbox.add_child(UI.make_separator())

	var retry := UI.make_button("Try again", "primary")
	retry.pressed.connect(_on_game_over_retry)
	vbox.add_child(retry)
	var menu := UI.make_button("Main menu", "secondary")
	menu.pressed.connect(_on_game_over_menu)
	vbox.add_child(menu)


# =============================================================================
# HUD updates
# =============================================================================

func _set_btn_visible(btn: Control, should_show: bool) -> void:
	if btn != null and btn.visible != should_show:
		btn.visible = should_show


func _set_text(lbl: Label, txt: String) -> void:
	if lbl != null and lbl.text != txt:
		lbl.text = txt


func _set_card(id: String, cost_text: String, detail: String, affordable: bool, available: bool) -> void:
	if not _shop_cards.has(id):
		return
	var card: Dictionary = _shop_cards[id]
	var btn: Button = card["btn"]
	var locked := bool(_shop_locked.get(id, false))
	var cost_lbl: Label = card["cost"]
	var detail_lbl: Label = card["detail"]

	if locked:
		_set_text(cost_lbl, "Locked")
		_set_text(detail_lbl, "")
		cost_lbl.add_theme_color_override("font_color", UI.TEXT_FAINT)
		btn.disabled = true
	else:
		_set_text(cost_lbl, cost_text)
		_set_text(detail_lbl, detail)
		var col := UI.GOLD
		if not available:
			col = UI.TEXT_FAINT
		elif not affordable:
			col = UI.BAD
		cost_lbl.add_theme_color_override("font_color", col)
		btn.disabled = not (available and affordable)

	# Tutorial highlight: gently pulse the card the player should press next
	if _shop_highlight == id and not locked:
		var p := 0.5 + 0.5 * sin(_pulse_time * 5.0)
		btn.modulate = Color(1.0 + 0.30 * p, 1.0 + 0.30 * p, 1.0 + 0.30 * p, 1.0)
	elif btn.modulate != Color.WHITE:
		btn.modulate = Color.WHITE


func _update_hud() -> void:
	if _coins_value == null:
		return

	# --- Stats ---
	_set_text(_coins_value, str(coins))
	var alive_fish := 0
	var hungry_fish := 0
	for node in get_tree().get_nodes_in_group("goldfish"):
		if is_instance_valid(node) and not bool(node.get("is_dead")):
			alive_fish += 1
			if int(node.get("hunger_status")) == SwimmingFishScript.HungerStatus.HUNGRY:
				hungry_fish += 1
	_set_text(_fish_value, str(alive_fish))
	_set_text(_fish_hungry, ("%d hungry" % hungry_fish) if hungry_fish > 0 else "")
	var archer_count := get_tree().get_nodes_in_group("archerfish").size()
	_set_text(_defense_value, str(archer_count))

	# --- Wave panel ---
	var remaining := int(ceilf(maxf(0.0, phase_timer)))
	_set_text(_wave_title, "TUTORIAL" if is_tutorial else "WAVE %d" % current_wave)
	var frac := clampf(phase_timer / maxf(phase_duration, 0.01), 0.0, 1.0)
	match current_phase:
		WavePhase.PEACEFUL:
			_set_text(_wave_phase, "PEACEFUL")
			_wave_phase.add_theme_color_override("font_color", UI.GOOD)
			UI.set_progress_color(_wave_bar, UI.GOOD)
			if is_decorating_mode:
				_set_text(_wave_sub, "Decorating - timer paused")
			elif not wave_timer_enabled:
				_set_text(_wave_sub, "No birds yet - take your time")
				frac = 1.0
			else:
				var next_birds := Balance.bird_count(current_wave)
				_set_text(_wave_sub, "%s %s in %ds" % [_bird_word(next_birds), "arrives" if next_birds == 1 else "arrive", remaining])
		WavePhase.CAREFUL:
			_set_text(_wave_phase, "CAREFUL")
			_wave_phase.add_theme_color_override("font_color", UI.WARN)
			UI.set_progress_color(_wave_bar, UI.WARN)
			var c_birds := _get_alive_kingfishers().size()
			_set_text(_wave_sub, "%s circling - attack in %ds" % [_bird_word(c_birds), remaining])
		WavePhase.ATTACK:
			_set_text(_wave_phase, "ATTACK")
			_wave_phase.add_theme_color_override("font_color", UI.BAD)
			UI.set_progress_color(_wave_bar, UI.BAD)
			var a_birds := _get_alive_kingfishers().size()
			if _tutorial_training_wave:
				_set_text(_wave_sub, "Click the bird to fight back")
				frac = 1.0
			else:
				_set_text(_wave_sub, "%s attacking - %ds left" % [_bird_word(a_birds), remaining])
	_wave_bar.value = frac

	_set_btn_visible(_call_wave_btn, (not is_tutorial) and current_phase == WavePhase.PEACEFUL and not is_decorating_mode and wave_timer_enabled)

	# --- Toast ---
	if recent_event_timer > 0.0 and recent_event_text != "":
		_toast_panel.visible = true
		_set_text(_event_label, recent_event_text)
		_toast_panel.modulate.a = clampf(recent_event_timer / 0.6, 0.0, 1.0)
	else:
		_toast_panel.visible = false

	# --- Shop / Decor bars ---
	_set_btn_visible(_shop_panel, not is_decorating_mode)
	_set_btn_visible(_decor_panel, is_decorating_mode)
	_set_btn_visible(_controls_hint, _hints_visible and (not is_tutorial) and not is_decorating_mode)

	var plants_full := _duckweed_tiles.size() >= MAX_SURFACE_PLANTS
	_set_card("fish", str(COST_BABY_FISH), "", coins >= COST_BABY_FISH, true)
	_set_card("plant", "Full" if plants_full else str(COST_DUCKWEED),
		"%d / %d" % [_duckweed_tiles.size(), MAX_SURFACE_PLANTS], coins >= COST_DUCKWEED, not plants_full)

	var upg_tile := _find_target_plant_for_upgrade()
	if upg_tile != null:
		var u_cost := int(upg_tile.call("get_upgrade_cost"))
		_set_card("upgrade", str(u_cost), str(upg_tile.call("get_next_tier_name")).replace(" Lv.", " "), coins >= u_cost, true)
	else:
		_set_card("upgrade", "Max", "", false, false)

	var a_cost := get_archer_fish_cost()
	_set_card("archer", str(a_cost), "own %d" % archer_count, coins >= a_cost, true)

	if is_instance_valid(_pet_crab):
		var lv := int(_pet_crab.get("speed_level"))
		if bool(_pet_crab.call("can_upgrade_speed")):
			var c_cost := int(_pet_crab.call("get_upgrade_cost"))
			_set_card("crab", str(c_cost), "Lv.%d" % lv, coins >= c_cost, true)
		else:
			_set_card("crab", "Max", "Lv.%d" % lv, false, false)

	var is_peaceful := (current_phase == WavePhase.PEACEFUL)
	_set_card("decorate", "Open" if is_peaceful else "Wait", "", true, is_peaceful)

	if is_decorating_mode:
		_update_decor_bar()

	_update_inspector()


func _update_decor_bar() -> void:
	var is_surf := (decor_layer == AquariumCameraScript.DECOR_LAYER_SURFACE)
	if _styled_layer != decor_layer:
		_styled_layer = decor_layer
		UI.style_button(_surface_tab_btn, "primary" if is_surf else "secondary", UI.GOOD)
		UI.style_button(_floor_tab_btn, "primary" if not is_surf else "secondary", UI.WARN)
	_set_btn_visible(_surface_decor_box, is_surf)
	_set_btn_visible(_floor_decor_grid, not is_surf)

	if _duckweed_tiles.size() >= MAX_SURFACE_PLANTS:
		_decor_buy_plant_btn.text = "Surface is full"
		_decor_buy_plant_btn.disabled = true
	else:
		_decor_buy_plant_btn.text = "Add Duckweed   %d" % COST_DUCKWEED
		_decor_buy_plant_btn.disabled = coins < COST_DUCKWEED or bool(_shop_locked.get("plant", false))

	var upg_tile := _find_target_plant_for_upgrade()
	if upg_tile != null:
		var u_cost := int(upg_tile.call("get_upgrade_cost"))
		_decor_upg_plant_btn.text = "Upgrade to %s   %d" % [str(upg_tile.call("get_next_tier_name")), u_cost]
		_decor_upg_plant_btn.disabled = coins < u_cost or bool(_shop_locked.get("upgrade", false))
	else:
		_decor_upg_plant_btn.text = "All plants at max level"
		_decor_upg_plant_btn.disabled = true

	for d_entry in _decor_buttons:
		var b: Button = d_entry["btn"]
		if is_instance_valid(b):
			b.disabled = coins < int(d_entry["cost"])

	if is_surf:
		_set_text(_decor_hint, "Drag a plant to move it    R rotate    Tab switch to floor    The wave timer is paused")
	else:
		_set_text(_decor_hint, "Buy an item, then drag it to a tile    R rotate    Tab switch to surface    The wave timer is paused")


func _update_inspector() -> void:
	if _inspector_panel == null:
		return
	var focused: Node3D = _get_focused()
	if not is_instance_valid(focused):
		_set_btn_visible(_inspector_panel, false)
		return
	_set_btn_visible(_inspector_panel, true)

	var label_text: String = str(focused.call("get_display_label")) if focused.has_method("get_display_label") else str(focused.name)
	var parts := label_text.split(" | ")
	_set_text(_insp_title, parts[0] if parts.size() > 0 else "")
	var info_lines: PackedStringArray = PackedStringArray()
	for i in range(1, parts.size()):
		info_lines.append(parts[i])
	_set_text(_insp_info, "\n".join(info_lines))

	var role := ""
	if focused.is_in_group("goldfish"):
		role = "Coin producer"
	elif focused.is_in_group("archerfish"):
		role = "Defender"
	elif focused.is_in_group("crab"):
		role = "Coin collector"
	elif focused.is_in_group("duckweed"):
		role = "Food plant"
	elif focused.is_in_group("decorations"):
		role = "Decoration"
	_set_text(_insp_role, role.to_upper())

	var show_upgrade := false
	var show_move := false
	var show_rotate := false
	var show_remove := false
	var move_active: bool = bool(camera_rig.get("is_move_mode")) if camera_rig else false
	var is_peaceful := (current_phase == WavePhase.PEACEFUL)

	if focused.is_in_group("duckweed"):
		show_upgrade = not bool(_shop_locked.get("upgrade", false))
		if bool(focused.call("can_upgrade")):
			var u_cost := int(focused.call("get_upgrade_cost"))
			_ctx_upgrade_btn.text = "Upgrade to %s   %d" % [str(focused.call("get_next_tier_name")), u_cost]
			_ctx_upgrade_btn.disabled = coins < u_cost
		else:
			_ctx_upgrade_btn.text = "Max level"
			_ctx_upgrade_btn.disabled = true
		var can_edit := is_peaceful and not bool(_shop_locked.get("decorate", false))
		show_move = can_edit
		show_rotate = can_edit
		_ctx_move_btn.text = "Pick a tile..." if move_active else "Move"
	elif focused.is_in_group("crab"):
		show_upgrade = not bool(_shop_locked.get("crab", false))
		if bool(focused.call("can_upgrade_speed")):
			var c_cost := int(focused.call("get_upgrade_cost"))
			_ctx_upgrade_btn.text = "Upgrade speed to Lv.%d   %d" % [int(focused.get("speed_level")) + 1, c_cost]
			_ctx_upgrade_btn.disabled = coins < c_cost
		else:
			_ctx_upgrade_btn.text = "Top speed reached"
			_ctx_upgrade_btn.disabled = true
	elif focused.is_in_group("decorations"):
		show_move = is_peaceful
		show_rotate = is_peaceful
		show_remove = is_peaceful
		_ctx_move_btn.text = "Pick a tile..." if move_active else "Move"
		_ctx_remove_btn.text = "Remove   +%d" % (int(focused.get("decor_cost")) / 2)

	_set_btn_visible(_ctx_upgrade_btn, show_upgrade)
	_set_btn_visible(_ctx_move_btn, show_move)
	_set_btn_visible(_ctx_rotate_btn, show_rotate)
	_set_btn_visible(_ctx_move_btn.get_parent() as Control, show_move or show_rotate)
	_set_btn_visible(_ctx_remove_btn, show_remove)
