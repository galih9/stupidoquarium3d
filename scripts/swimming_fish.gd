extends "res://assets/fih/goldfish.gd"
class_name SwimmingFish

## Autonomous goldfish controller supporting swimming, idling, duckweed feeding,
## hunger, mood (bored / happy / stressed), hiding at decorations when stressed,
## growth stages, coin dropping on a timer, hit feedback, and death.
##
## Mood rules:
## - Fish start Bored. Decorations (tank comfort) and swimming next to them make fish Happy.
## - Bored for too long: babies stop making coins, medium fish drop copper, adults drop silver.
## - Seeing tank mates get eaten builds stress (less with lots of decoration). Stressed fish
##   hide next to decorations, which calms them faster, and drop slower, cheaper coins.
## - Each plant tier only feeds certain sizes (see duckweed_tile.gd), so fish need upgraded plants to keep growing.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const CombatVFXScript = preload("res://scripts/combat_vfx.gd")
const Balance = preload("res://scripts/game_balance.gd")
const TankDecorationScript = preload("res://scripts/tank_decoration.gd")

const MEALS_TO_MEDIUM: int = 3
const MEALS_TO_ADULT: int = 7

enum State { IDLE, SWIM, SEEK_FOOD, EATING, DYING, HIDE }
enum SizeCategory { BABY, MEDIUM, ADULT }
enum HungerStatus { FED, HUNGRY }
enum Mood { STRESSED, BORED, HAPPY }

const SIZE_SCALES := {
	SizeCategory.BABY: 0.34,
	SizeCategory.MEDIUM: 0.30,
	SizeCategory.ADULT: 0.26,
}

const SIZE_SPEEDS := {
	SizeCategory.BABY: 1.95,
	SizeCategory.MEDIUM: 1.65,
	SizeCategory.ADULT: 1.40,
}

const SIZE_RADII := {
	SizeCategory.BABY: 0.45,
	SizeCategory.MEDIUM: 0.65,
	SizeCategory.ADULT: 0.90,
}

const FISH_MODELS := {
	SizeCategory.BABY: preload("res://assets/fih/baby.glb"),
	SizeCategory.MEDIUM: preload("res://assets/fih/medium.glb"),
	SizeCategory.ADULT: preload("res://assets/fih/adult.glb"),
}

const SIZE_NAMES := ["Baby", "Medium", "Adult"]
const VARIANT_TITLES := ["Classic", "Golden", "Calico", "Kohaku"]
const HUNGER_NAMES := ["Fed", "Hungry"]
const MOOD_NAMES := ["Stressed", "Bored", "Happy"]
const COIN_NAMES := ["copper", "silver", "gold"]
const PLANT_FOR_SIZE := ["Duckweed", "Duckweed Lv.2", "Water Hyacinth"]

## Shared tank comfort (0 = no decorations, 1 = enough for every fish). Set by the main controller.
static var tank_comfort_ratio: float = 0.0

## coin_tier follows CoinDrop.CoinTier (0 copper, 1 silver, 2 gold)
signal coin_dropped(world_pos: Vector3, coin_tier: int)
signal fish_died(fish: SwimmingFish, reason: String)
signal mood_changed(fish: SwimmingFish, new_mood: int, penalized: bool)
signal needs_better_food(fish: SwimmingFish)

@export var size_category: SizeCategory = SizeCategory.BABY
@export var tank_bounds: AABB = AABB(Vector3(-6.7, 1.05, -3.9), Vector3(13.4, 4.75, 7.8))
@export var fed_duration_min: float = Balance.FISH_FED_MIN
@export var fed_duration_max: float = Balance.FISH_FED_MAX
@export var max_starve_time: float = Balance.FISH_STARVE_TIME
@export var base_coin_interval: float = Balance.FISH_COIN_INTERVAL

var state: State = State.SWIM
var hunger_status: HungerStatus = HungerStatus.FED
var mood: Mood = Mood.BORED
var joy: float = Balance.JOY_START
var stress: float = 0.0
var bored_time: float = 0.0
var no_food_for_size: bool = false

var _mood_tick: float = 0.0
var _was_penalized: bool = false
var _hide_target: Node3D = null
var _hide_point: Vector3 = Vector3.ZERO
var _hide_repick: float = 0.0
var _food_warned: bool = false
var _grow_anim_timer: float = 0.0
const GROW_ANIM_TIME: float = 0.8

var hunger_timer: float = 12.0
var starve_timer: float = 22.0
var coin_timer: float = 8.0
var meals_eaten: int = 0
var is_dead: bool = false

var velocity: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var state_timer: float = 0.0
var bob_phase: float = 0.0
var turn_speed: float = 2.5
var current_speed: float = 0.0

var _visual_root: Node3D = null
var _base_visual_pos: Vector3 = Vector3.ZERO
var _base_visual_rot: Vector3 = Vector3(0.0, PI * 0.5, 0.0)
var _base_visual_scale: float = 0.34
var _hit_area: Area3D = null
var _collision_shape: CollisionShape3D = null
var _status_label: Label3D = null
var _current_duckweed: Node3D = null
var _death_timer: float = 0.0
var _wait_offset: Vector3 = Vector3.ZERO

# Combat hit feedback: white flash, brief hitstop delay, and shake animation
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D = null
var _flash_timer: float = 0.0
var _flash_duration: float = 0.18
var _hitstop_timer: float = 0.0
var _shake_timer: float = 0.0
var _shake_duration: float = 0.28
var _shake_intensity: float = 0.24
var _shake_phase: float = 0.0
var _attacked_alert_timer: float = 0.0
var _is_snatched_anim: bool = false
var _snatch_anim_timer: float = 0.0
var is_selected: bool = false
var _outline_mat: ShaderMaterial = null


func _ready() -> void:
	if textures_dir == "":
		textures_dir = "res://assets/fih/textures"
	add_to_group("goldfish")
	add_to_group("selectable_entities")
	bob_phase = randf() * TAU
	turn_speed = randf_range(2.2, 3.1)

	# Initialize timers with slight random variation so fish do not sync up
	hunger_status = HungerStatus.FED
	mood = Mood.BORED
	joy = Balance.JOY_START + randf_range(-6.0, 6.0)
	_mood_tick = randf() * 0.25
	hunger_timer = randf_range(fed_duration_min * 0.65, fed_duration_max)
	starve_timer = max_starve_time
	coin_timer = randf_range(base_coin_interval * 0.55, base_coin_interval * 1.15)
	_wait_offset = Vector3(randf_range(-1.1, 1.1), randf_range(-0.35, 0.15), randf_range(-1.1, 1.1))

	_flash_mat = CombatVFXScript.create_flash_material()
	_outline_mat = CombatVFXScript.create_selection_outline_material(Color(0.38, 0.96, 1.0, 0.96), 3.2)
	_setup_visual_and_collision()
	_create_status_label()
	super._ready()

	var ap := get_animation_player()
	if ap and ap.current_animation != "":
		ap.seek(randf() * ap.current_animation_length, true)

	if randf() < 0.75:
		_enter_swim_state()
	else:
		_enter_idle_state()


func set_selected(selected: bool) -> void:
	is_selected = selected
	if _visual_root:
		CombatVFXScript.set_selection_outline(_visual_root, is_selected, _outline_mat)


func _setup_visual_and_collision() -> void:
	var scale_factor: float = SIZE_SCALES.get(size_category, 0.30)
	_base_visual_scale = scale_factor
	_visual_root = null
	for child in get_children():
		if child is Node3D and not (child is Area3D) and not (child is CollisionObject3D) and not (child is Label3D):
			_visual_root = child
			break

	if _visual_root == null:
		var glb_scene: PackedScene = FISH_MODELS.get(size_category, FISH_MODELS[SizeCategory.BABY])
		_visual_root = glb_scene.instantiate()
		add_child(_visual_root)

	# Raw GLB faces +X; rotating +90 deg around Y aligns Mouth with -Z (Godot forward)
	_base_visual_rot = Vector3(0.0, PI * 0.5, 0.0)
	var x_center_offset := 0.85 * scale_factor
	_base_visual_pos = Vector3(0.0, 0.0, -x_center_offset)

	_visual_root.rotation = _base_visual_rot
	_visual_root.scale = Vector3.ONE * scale_factor
	_visual_root.position = _base_visual_pos

	_mesh_instances = CombatVFXScript.collect_mesh_instances(_visual_root)
	if is_selected:
		CombatVFXScript.set_selection_outline(_visual_root, true, _outline_mat)

	if _hit_area == null:
		_hit_area = Area3D.new()
		_hit_area.name = "ClickArea"
		_hit_area.collision_layer = 2
		_hit_area.collision_mask = 0
		_hit_area.input_ray_pickable = true
		add_child(_hit_area)

		_collision_shape = CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = SIZE_RADII.get(size_category, 0.65)
		_collision_shape.shape = shape
		_hit_area.add_child(_collision_shape)
	elif _collision_shape and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = SIZE_RADII.get(size_category, 0.65)


func _create_status_label() -> void:
	if _status_label != null:
		return
	_status_label = Label3D.new()
	_status_label.name = "StatusTag"
	_status_label.position = Vector3(0.0, 0.44, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.pixel_size = 0.0035
	_status_label.font_size = 28
	_status_label.outline_size = 7
	_status_label.modulate = Color(1.0, 0.9, 0.4, 0.88)
	_status_label.outline_modulate = Color(0.06, 0.06, 0.08, 0.88)
	_status_label.visible = false
	add_child(_status_label)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	bob_phase += delta * 2.2
	if _attacked_alert_timer > 0.0:
		_attacked_alert_timer = maxf(0.0, _attacked_alert_timer - delta)

	_update_hit_effects(delta)

	if _is_snatched_anim:
		_process_snatched_sequence(delta)
		return

	if is_dead or state == State.DYING:
		_process_dying(delta)
		return

	# Brief hit delay (hitstop): freeze fish movement and animation on impact frame
	if _hitstop_timer > 0.0:
		_hitstop_timer = maxf(0.0, _hitstop_timer - delta)
		var ap := get_animation_player()
		if ap:
			ap.speed_scale = 0.0
		_update_overhead_label()
		return

	state_timer -= delta
	_update_hunger_and_coins(delta)
	_update_mood(delta)

	if is_dead or state == State.DYING:
		return

	match state:
		State.HIDE:
			_process_hide(delta)
		State.SWIM:
			_process_swim(delta)
		State.IDLE:
			_process_idle(delta)
		State.SEEK_FOOD:
			_process_seek_food(delta)
		State.EATING:
			_process_eating(delta)

	_keep_within_bounds(delta)
	_update_overhead_label()


func _update_hit_effects(delta: float) -> void:
	# 1. White flash overlay
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		var norm := clampf(_flash_timer / maxf(_flash_duration, 0.05), 0.0, 1.0)
		var alpha := 0.96 if _hitstop_timer > 0.0 else pow(norm, 0.68) * 0.92
		CombatVFXScript.update_flash_overlay(_mesh_instances, _flash_mat, alpha, Color(2.35, 2.35, 2.5, 1.0))
	else:
		CombatVFXScript.update_flash_overlay(_mesh_instances, _flash_mat, 0.0)

	# 2. Shake animation + squash/stretch on _visual_root
	if _visual_root == null:
		return

	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		_shake_phase += delta * 72.0
		var decay := clampf(_shake_timer / maxf(_shake_duration, 0.05), 0.0, 1.0)
		var amp := _shake_intensity * decay

		var offset := Vector3(
			sin(_shake_phase * 1.21) * amp,
			cos(_shake_phase * 1.57) * amp * 0.85,
			sin(_shake_phase * 1.93) * amp * 0.75
		)
		var rot_jitter := Vector3(
			cos(_shake_phase * 1.43) * amp * 0.95,
			sin(_shake_phase * 1.07) * amp * 0.65,
			sin(_shake_phase * 1.85) * amp * 1.45
		)
		var punch := sin(decay * PI) * 0.30
		var squash_scale := Vector3(
			_base_visual_scale * (1.0 + punch),
			_base_visual_scale * (1.0 - punch * 0.65),
			_base_visual_scale * (1.0 + punch)
		)

		_visual_root.position = _base_visual_pos + offset
		_visual_root.rotation = _base_visual_rot + rot_jitter
		_visual_root.scale = squash_scale
	elif _grow_anim_timer > 0.0:
		# Springy grow: starts a bit small, overshoots, then settles at the new size
		_grow_anim_timer = maxf(0.0, _grow_anim_timer - delta)
		var t := 1.0 - _grow_anim_timer / GROW_ANIM_TIME
		var k := 1.0 - 0.35 * exp(-5.0 * t) * cos(t * 14.0)
		_visual_root.position = _base_visual_pos
		_visual_root.rotation = _base_visual_rot + Vector3(0.0, sin(t * PI * 2.0) * 0.25 * (1.0 - t), 0.0)
		_visual_root.scale = Vector3.ONE * _base_visual_scale * k
	elif not _is_snatched_anim:
		_visual_root.position = _base_visual_pos
		_visual_root.rotation = _base_visual_rot
		_visual_root.scale = Vector3.ONE * _base_visual_scale


func on_predator_strike(_attacker_pos: Vector3) -> void:
	if is_dead or _is_snatched_anim:
		return
	if Balance.moods_enabled():
		stress = minf(100.0, stress + Balance.stress_self_attacked())
	_mood_tick = 0.0
	_attacked_alert_timer = 0.90

	# Trigger bright white flash, brief hit delay (hitstop), and shake animation
	_flash_duration = 0.19
	_flash_timer = _flash_duration
	_hitstop_timer = maxf(_hitstop_timer, 0.085)
	_shake_duration = 0.28
	_shake_timer = _shake_duration
	_shake_intensity = 0.24

	CombatVFXScript.spawn_hit_effect(
		get_tree(),
		global_position,
		false,
		"ATTACKED!",
		Color(1.0, 0.42, 0.32, 1.0)
	)
	# No camera shake per peck: it fired several times per second during dives.


func _process_snatched_sequence(delta: float) -> void:
	_snatch_anim_timer += delta
	_update_overhead_label()

	# Phase 1 (0.0s -> 0.20s): Freeze in place with intense white flash and violent shake
	if _snatch_anim_timer < 0.20:
		var ap := get_animation_player()
		if ap:
			ap.speed_scale = 0.0
		return

	# Phase 2 (0.20s -> 0.36s): Yank upward toward water surface while shrinking
	var yank_t := clampf((_snatch_anim_timer - 0.20) / 0.16, 0.0, 1.0)
	global_position.y += delta * 11.5
	if _visual_root:
		_visual_root.scale = Vector3.ONE * lerpf(_base_visual_scale, 0.02, yank_t)
	if yank_t >= 1.0:
		queue_free()


func _update_hunger_and_coins(delta: float) -> void:
	# 1. Hunger lifecycle: Fed -> Hungry -> Starve to death if not fed in time
	if hunger_status == HungerStatus.FED:
		hunger_timer -= delta
		if hunger_timer <= 0.0:
			hunger_status = HungerStatus.HUNGRY
			starve_timer = max_starve_time
			if state != State.EATING:
				_enter_seek_food_state()
	else:
		# While actively eating duckweed, pause starvation countdown
		if state != State.EATING:
			starve_timer -= delta
			if starve_timer <= 0.0:
				_die("Starved")
				return
			if state != State.SEEK_FOOD:
				_enter_seek_food_state()

	# 2. Coin drop timer (interval depends on stress level)
	coin_timer -= delta
	if coin_timer <= 0.0:
		var mult := _get_mood_coin_interval_multiplier()
		coin_timer = randf_range(base_coin_interval * 0.85, base_coin_interval * 1.15) * mult
		var tier := get_coin_tier()
		if tier >= 0:
			coin_dropped.emit(global_position + Vector3(0.0, -0.15, 0.0), tier)


func _get_mood_coin_interval_multiplier() -> float:
	match mood:
		Mood.HAPPY:
			return Balance.COIN_INTERVAL_HAPPY
		Mood.STRESSED:
			return Balance.COIN_INTERVAL_STRESSED
		_:
			return 1.0


## True when the fish's mood lowers its coin value (stressed, or bored for too long).
func is_coin_penalized() -> bool:
	return mood == Mood.STRESSED or (mood == Mood.BORED and bored_time >= Balance.bored_limit())


## Coin tier this fish drops right now: -1 none, 0 copper, 1 silver, 2 gold.
func get_coin_tier() -> int:
	var t := int(size_category)
	if is_coin_penalized():
		t -= 1
	return t


# =============================================================================
# Mood
# =============================================================================

func _update_mood(delta: float) -> void:
	_mood_tick -= delta
	if _mood_tick > 0.0:
		return
	if not Balance.moods_enabled():
		# Easy difficulty: no moods, fish are always happy
		_mood_tick = 0.25
		mood = Mood.HAPPY
		joy = 100.0
		stress = 0.0
		bored_time = 0.0
		return
	var dt := 0.25 - _mood_tick
	_mood_tick = 0.25

	var comfort := clampf(tank_comfort_ratio, 0.0, 1.5)
	var near := _nearby_decor_comfort()

	# Stress fades over time, faster in a well decorated tank and next to decorations
	var decay := Balance.STRESS_DECAY_BASE + comfort * Balance.STRESS_DECAY_COMFORT + near * Balance.STRESS_DECAY_NEAR
	stress = maxf(0.0, stress - decay * dt)

	# Joy rises with decoration and visits to decorations, and slowly decays into boredom
	var joy_rate := -Balance.joy_decay()
	if mood != Mood.STRESSED:
		joy_rate += comfort * Balance.JOY_GAIN_COMFORT + near * Balance.JOY_GAIN_NEAR
	joy = clampf(joy + joy_rate * dt, 0.0, 100.0)

	var prev_mood := mood
	if stress >= Balance.STRESSED_AT or (mood == Mood.STRESSED and stress > Balance.CALM_AT):
		mood = Mood.STRESSED
	elif joy >= Balance.HAPPY_AT or (mood == Mood.HAPPY and joy > Balance.UNHAPPY_AT):
		mood = Mood.HAPPY
	else:
		mood = Mood.BORED

	if mood == Mood.BORED:
		bored_time += dt
	else:
		bored_time = 0.0

	var penalized := is_coin_penalized()
	if mood != prev_mood or penalized != _was_penalized:
		_on_mood_changed(prev_mood, penalized)
	_was_penalized = penalized

	# Stressed fish that are not busy eating go hide next to a decoration
	if mood == Mood.STRESSED and state in [State.SWIM, State.IDLE] and hunger_status == HungerStatus.FED:
		_enter_hide_state()


func _on_mood_changed(prev_mood: Mood, penalized: bool) -> void:
	var head := global_position + Vector3(0.0, 0.55, 0.0)
	if mood == Mood.STRESSED and prev_mood != Mood.STRESSED:
		CombatVFXScript.spawn_text_popup(get_tree(), head, "Stressed", Color(1.0, 0.55, 0.40))
	elif mood == Mood.HAPPY and prev_mood != Mood.HAPPY:
		CombatVFXScript.spawn_text_popup(get_tree(), head, "Happy", Color(0.55, 1.0, 0.65))
	elif mood == Mood.BORED and penalized and not _was_penalized:
		CombatVFXScript.spawn_text_popup(get_tree(), head, "Bored", Color(0.70, 0.78, 0.88))
	mood_changed.emit(self, int(mood), penalized)


func on_tank_mate_eaten(world_pos: Vector3) -> void:
	if is_dead or not Balance.moods_enabled():
		return
	# Decorations shelter the fish: a well decorated tank softens the shock
	var protection := clampf(tank_comfort_ratio * 0.4, 0.0, 0.6)
	var near_factor := 1.0 if global_position.distance_to(world_pos) <= Balance.STRESS_WITNESS_NEAR else 0.6
	stress = minf(100.0, stress + Balance.stress_per_witness() * (1.0 - protection) * near_factor)
	joy = maxf(0.0, joy - 10.0)
	_mood_tick = 0.0


func _nearby_decor_comfort() -> float:
	var total := 0.0
	for node in get_tree().get_nodes_in_group("decorations"):
		if not is_instance_valid(node) or not node.has_method("get_center"):
			continue
		var c: Vector3 = node.call("get_center")
		var foot: Vector2i = node.call("get_footprint")
		var reach := float(maxi(foot.x, foot.y)) * TankDecorationScript.FLOOR_TILE * 0.5 + 1.0
		var flat := Vector2(global_position.x - c.x, global_position.z - c.z).length()
		if flat <= reach and global_position.y <= c.y + float(node.call("get_height")) + 1.5:
			total += float(node.get("comfort"))
	return total


func _find_hide_decoration() -> Node3D:
	var best: Node3D = null
	var best_score := -1.0
	for node in get_tree().get_nodes_in_group("decorations"):
		if not is_instance_valid(node) or not node.has_method("get_center"):
			continue
		var c: Vector3 = node.call("get_center")
		var score := float(node.get("comfort")) / (1.0 + global_position.distance_to(c) * 0.35)
		if score > best_score:
			best_score = score
			best = node as Node3D
	return best


func _enter_hide_state() -> void:
	state = State.HIDE
	_hide_target = _find_hide_decoration()
	_pick_hide_point()
	play("Swim", 0.25)


func _pick_hide_point() -> void:
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size
	_hide_repick = randf_range(2.0, 4.0)
	if is_instance_valid(_hide_target):
		var c: Vector3 = _hide_target.call("get_center")
		var foot: Vector2i = _hide_target.call("get_footprint")
		var hw := float(foot.x) * TankDecorationScript.FLOOR_TILE * 0.5
		var hd := float(foot.y) * TankDecorationScript.FLOOR_TILE * 0.5
		var top := c.y + float(_hide_target.call("get_height"))
		_hide_point = Vector3(
			clampf(c.x + randf_range(-hw, hw), min_p.x, max_p.x),
			clampf(randf_range(min_p.y, maxf(min_p.y + 0.2, minf(top, min_p.y + 1.2))), min_p.y, max_p.y),
			clampf(c.z + randf_range(-hd - 0.3, hd + 0.3), min_p.z, max_p.z)
		)
	else:
		# Nowhere to hide: cower near the bottom
		_hide_point = Vector3(
			randf_range(min_p.x + 0.8, max_p.x - 0.8),
			min_p.y + randf_range(0.0, 0.4),
			randf_range(min_p.z + 0.8, max_p.z - 0.8)
		)


func _process_hide(delta: float) -> void:
	if mood != Mood.STRESSED:
		_enter_swim_state()
		return
	if not is_instance_valid(_hide_target) and not get_tree().get_nodes_in_group("decorations").is_empty():
		_hide_target = _find_hide_decoration()
		_pick_hide_point()

	var to_p := _hide_point - global_position
	var dist := to_p.length()
	_hide_repick -= delta
	if dist < 0.5 and _hide_repick <= 0.0:
		_pick_hide_point()
	var desired_dir := to_p / maxf(dist, 0.001) if dist > 0.15 else -global_transform.basis.z
	desired_dir += _compute_separation() * 0.6
	if desired_dir.length_squared() > 0.001:
		desired_dir = desired_dir.normalized()
	var max_spd: float = SIZE_SPEEDS.get(size_category, 1.5) * (1.1 if dist > 1.0 else 0.35)
	current_speed = lerpf(current_speed, max_spd, delta * 3.0)
	_steer_toward(desired_dir, delta, turn_speed * 1.2)
	global_position += (-global_transform.basis.z) * current_speed * delta
	var ap := get_animation_player()
	if ap:
		ap.speed_scale = 1.1 if dist > 1.0 else 0.8


func _process_swim(delta: float) -> void:
	var to_target := target_position - global_position
	var dist := to_target.length()

	if dist < 0.85 or state_timer <= 0.0:
		if randf() < 0.38:
			_enter_idle_state()
		else:
			_pick_new_target()
			state_timer = randf_range(3.5, 7.5)
		return

	var desired_dir := to_target / maxf(dist, 0.001)
	desired_dir += _compute_separation() * 0.85
	if desired_dir.length_squared() > 0.001:
		desired_dir = desired_dir.normalized()
	else:
		desired_dir = -global_transform.basis.z

	var max_spd: float = SIZE_SPEEDS.get(size_category, 1.5)
	var arrival_factor := clampf(dist / 2.0, 0.45, 1.0)
	var target_spd := max_spd * arrival_factor
	current_speed = lerpf(current_speed, target_spd, delta * 2.5)

	_steer_toward(desired_dir, delta, turn_speed)

	var forward := -global_transform.basis.z
	velocity = forward * current_speed
	global_position += velocity * delta

	var ap := get_animation_player()
	if ap:
		ap.speed_scale = clampf(0.85 + (current_speed / max_spd) * 0.55, 0.8, 1.5)


func _process_idle(delta: float) -> void:
	if state_timer <= 0.0:
		_enter_swim_state()
		return

	current_speed = lerpf(current_speed, 0.12, delta * 2.2)
	var sep := _compute_separation()
	var forward := -global_transform.basis.z
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length_squared() < 0.001:
		flat_forward = Vector3.FORWARD
	else:
		flat_forward = flat_forward.normalized()

	var drift_dir := (flat_forward + sep * 0.5).normalized()
	_steer_toward(drift_dir, delta, 1.1)

	var bob_vel := cos(bob_phase) * 0.12
	velocity = flat_forward * current_speed + Vector3(0.0, bob_vel, 0.0)
	global_position += velocity * delta

	var ap := get_animation_player()
	if ap:
		ap.speed_scale = 0.95


func _process_seek_food(delta: float) -> void:
	var best_free_tile: Node3D = _find_closest_duckweed(true)
	no_food_for_size = best_free_tile == null and _find_closest_duckweed(false) == null
	if no_food_for_size and not _food_warned:
		_food_warned = true
		needs_better_food.emit(self)
	if best_free_tile != null:
		var feed_pt: Vector3 = best_free_tile.call("get_feed_point_for", self) if best_free_tile.has_method("get_feed_point_for") else best_free_tile.call("get_feed_point")
		var to_feed := feed_pt - global_position
		var dist := to_feed.length()

		if dist < 0.85:
			if bool(best_free_tile.call("begin_feeding", self)):
				_current_duckweed = best_free_tile
				state = State.EATING
				play("Idle", 0.2)
				return

		var desired_dir := to_feed / maxf(dist, 0.001)
		desired_dir += _compute_separation() * 0.35
		if desired_dir.length_squared() > 0.001:
			desired_dir = desired_dir.normalized()

		var max_spd: float = SIZE_SPEEDS.get(size_category, 1.6) * 1.25
		current_speed = lerpf(current_speed, max_spd, delta * 3.5)
		_steer_toward(desired_dir, delta, turn_speed * 1.45)

		var forward := -global_transform.basis.z
		velocity = forward * current_speed
		global_position += velocity * delta

		var ap := get_animation_player()
		if ap:
			ap.speed_scale = 1.35
	else:
		# All suitable plants are busy (or none can feed this size); wait near a plant below the surface
		var any_tile: Node3D = _find_closest_duckweed(false)
		if any_tile == null:
			any_tile = _find_closest_duckweed(false, false)
		var wait_target := Vector3(0.0, 5.1, 0.0) + _wait_offset
		if any_tile != null and any_tile.has_method("get_wait_point"):
			wait_target = any_tile.call("get_wait_point") + _wait_offset

		var to_wait := wait_target - global_position
		var dist := to_wait.length()
		var desired_dir := to_wait / maxf(dist, 0.001) if dist > 0.2 else -global_transform.basis.z
		desired_dir += _compute_separation() * 0.7
		if desired_dir.length_squared() > 0.001:
			desired_dir = desired_dir.normalized()

		var wait_spd: float = SIZE_SPEEDS.get(size_category, 1.5) * (0.85 if dist > 0.9 else 0.35)
		current_speed = lerpf(current_speed, wait_spd, delta * 2.5)
		_steer_toward(desired_dir, delta, turn_speed)
		global_position += (-global_transform.basis.z) * current_speed * delta


func _process_eating(delta: float) -> void:
	if _current_duckweed == null or not is_instance_valid(_current_duckweed):
		_current_duckweed = null
		if hunger_status == HungerStatus.HUNGRY:
			_enter_seek_food_state()
		else:
			_enter_swim_state()
		return

	var feed_pt: Vector3 = _current_duckweed.call("get_feed_point_for", self) if _current_duckweed.has_method("get_feed_point_for") else _current_duckweed.call("get_feed_point")
	var nibble := Vector3(0.0, sin(bob_phase * 4.5) * 0.04, 0.0)
	global_position = global_position.lerp(feed_pt + nibble, clampf(delta * 6.0, 0.0, 1.0))
	current_speed = 0.0
	# Pitch nose gently upward toward the floating duckweed
	rotation.x = lerp_angle(rotation.x, 0.32, clampf(delta * 5.0, 0.0, 1.0))
	rotation.z = lerp_angle(rotation.z, 0.0, clampf(delta * 5.0, 0.0, 1.0))

	var ap := get_animation_player()
	if ap:
		ap.speed_scale = 1.25


func _process_dying(delta: float) -> void:
	_death_timer += delta
	current_speed = lerpf(current_speed, 0.0, delta * 3.0)
	# Slowly sink toward the sand floor while playing Died animation
	if global_position.y > 0.85:
		global_position.y -= 0.45 * delta
	rotation.z = lerp_angle(rotation.z, PI * 0.5, clampf(delta * 1.8, 0.0, 1.0))
	_update_overhead_label()
	if _death_timer >= 2.7:
		queue_free()


func _find_closest_duckweed(only_available: bool, only_compatible: bool = true) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("duckweed"):
		if not (node is Node3D):
			continue
		if only_compatible and node.has_method("can_feed_size") and not bool(node.call("can_feed_size", int(size_category))):
			continue
		if only_available and node.has_method("is_available") and not bool(node.call("is_available")):
			continue
		var tile := node as Node3D
		var d := global_position.distance_to(tile.global_position)
		if d < best_dist:
			best_dist = d
			best = tile
	return best


func complete_feeding() -> void:
	if is_dead:
		return
	_current_duckweed = null
	hunger_status = HungerStatus.FED
	hunger_timer = randf_range(fed_duration_min, fed_duration_max)
	starve_timer = max_starve_time
	meals_eaten += 1
	_food_warned = false
	no_food_for_size = false

	# Grow baby -> medium -> adult as the fish eats duckweed meals
	if size_category == SizeCategory.BABY and meals_eaten >= MEALS_TO_MEDIUM:
		_grow_to_size(SizeCategory.MEDIUM)
	elif size_category == SizeCategory.MEDIUM and meals_eaten >= MEALS_TO_ADULT:
		_grow_to_size(SizeCategory.ADULT)

	_enter_swim_state()
	# Pick a target deeper in the tank after eating at the surface
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size
	target_position = Vector3(
		randf_range(min_p.x + 0.8, max_p.x - 0.8),
		randf_range(min_p.y + 0.4, min_p.y + 2.6),
		randf_range(min_p.z + 0.8, max_p.z - 0.8)
	)


func _grow_to_size(new_size: SizeCategory) -> void:
	if size_category == new_size:
		return
	size_category = new_size
	if _visual_root and is_instance_valid(_visual_root):
		remove_child(_visual_root)
		_visual_root.queue_free()
		_visual_root = null

	var glb_scene: PackedScene = FISH_MODELS.get(size_category, FISH_MODELS[SizeCategory.BABY])
	var model_instance := glb_scene.instantiate()
	add_child(model_instance)

	_setup_visual_and_collision()
	_apply_variant()
	var ap := get_animation_player()
	if ap:
		for n in _LOOPING:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	play("Swim", 0.2)

	# Gentle growth celebration: springy "pop" into the new size with a rising
	# spiral of glowing motes and bubbles. No white flash or shake, so it never
	# looks like the fish was hit.
	_flash_timer = 0.0
	_shake_timer = 0.0
	_grow_anim_timer = GROW_ANIM_TIME
	CombatVFXScript.spawn_growth_effect(
		get_tree(),
		global_position,
		"Grown up: %s" % SIZE_NAMES[int(new_size)],
		Color(0.55, 1.0, 0.75, 1.0)
	)


func _die(reason: String) -> void:
	if is_dead:
		return
	is_dead = true
	state = State.DYING
	_death_timer = 0.0
	if _current_duckweed and is_instance_valid(_current_duckweed) and _current_duckweed.has_method("cancel_feeding"):
		_current_duckweed.call("cancel_feeding", self)
	_current_duckweed = null

	_flash_duration = 0.22
	_flash_timer = _flash_duration
	_shake_duration = 0.25
	_shake_timer = _shake_duration
	_shake_intensity = 0.18

	var ap := get_animation_player()
	if ap and ap.has_animation("Died"):
		ap.get_animation("Died").loop_mode = Animation.LOOP_NONE
		ap.speed_scale = 1.0
		play("Died", 0.2)
	fish_died.emit(self, reason)


func snatch_by_kingfisher() -> void:
	if is_dead:
		return
	is_dead = true
	if _current_duckweed and is_instance_valid(_current_duckweed) and _current_duckweed.has_method("cancel_feeding"):
		_current_duckweed.call("cancel_feeding", self)
	_current_duckweed = null

	# Trigger dramatic white flash, hitstop delay, intense shake, and 3D burst before removal
	_is_snatched_anim = true
	_snatch_anim_timer = 0.0
	_flash_duration = 0.32
	_flash_timer = _flash_duration
	_hitstop_timer = 0.20
	_shake_duration = 0.34
	_shake_timer = _shake_duration
	_shake_intensity = 0.32

	CombatVFXScript.spawn_hit_effect(
		get_tree(),
		global_position,
		true,
		"SNATCHED!",
		Color(1.0, 0.32, 0.28, 1.0)
	)
	CombatVFXScript.trigger_camera_shake(get_tree(), 0.14, 0.22)
	fish_died.emit(self, "Snatched by Kingfisher")


func _update_overhead_label() -> void:
	if _status_label == null:
		return
	if is_dead or state == State.DYING or _is_snatched_anim:
		_status_label.visible = false
	elif hunger_status == HungerStatus.HUNGRY and state != State.EATING:
		if starve_timer <= 7.0:
			_status_label.visible = true
			_status_label.modulate = Color(1.0, 0.36, 0.32, 0.94)
			_status_label.text = "%.0fs" % ceilf(starve_timer)
		elif no_food_for_size:
			_status_label.visible = true
			_status_label.modulate = Color(1.0, 0.76, 0.34, 0.92)
			_status_label.text = "Needs %s" % PLANT_FOR_SIZE[clampi(int(size_category), 0, 2)]
		elif is_selected:
			_status_label.visible = true
			_status_label.modulate = Color(1.0, 0.86, 0.36, 0.88)
			_status_label.text = "Hungry"
		else:
			_status_label.visible = false
	else:
		_status_label.visible = false


func _steer_toward(desired_dir: Vector3, delta: float, rate: float) -> void:
	var flat_len := Vector2(desired_dir.x, desired_dir.z).length()
	var target_yaw := rotation.y
	if flat_len > 0.001:
		target_yaw = atan2(-desired_dir.x, -desired_dir.z)

	var prev_yaw := rotation.y
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * rate, 0.0, 1.0))
	var yaw_rate := angle_difference(prev_yaw, rotation.y) / maxf(delta, 0.001)

	var target_pitch := clampf(asin(clampf(desired_dir.y, -0.65, 0.65)), -0.38, 0.38)
	if state == State.IDLE:
		target_pitch = sin(bob_phase) * 0.04
	rotation.x = lerp_angle(rotation.x, target_pitch, clampf(delta * 3.0, 0.0, 1.0))

	var target_roll := clampf(-yaw_rate * 0.14, -0.24, 0.24)
	rotation.z = lerp_angle(rotation.z, target_roll, clampf(delta * 4.0, 0.0, 1.0))


func _compute_separation() -> Vector3:
	var steer := Vector3.ZERO
	var my_radius: float = SIZE_RADII.get(size_category, 0.65) * 2.1
	for node in get_tree().get_nodes_in_group("goldfish"):
		if node == self or not (node is Node3D):
			continue
		var other := node as Node3D
		var diff := global_position - other.global_position
		var d := diff.length()
		if d > 0.001 and d < my_radius:
			steer += (diff / d) * ((my_radius - d) / my_radius)
	return steer


func _keep_within_bounds(delta: float) -> void:
	if state == State.EATING:
		return
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size
	var top_y := max_p.y + (0.35 if state == State.SEEK_FOOD else 0.0)
	var pos := global_position

	var clamped := Vector3(
		clampf(pos.x, min_p.x, max_p.x),
		clampf(pos.y, min_p.y, top_y),
		clampf(pos.z, min_p.z, max_p.z)
	)
	if pos != clamped:
		global_position = pos.lerp(clamped, clampf(delta * 8.0, 0.0, 1.0))
		if state == State.SWIM:
			_pick_new_target()


func _enter_swim_state() -> void:
	state = State.SWIM
	state_timer = randf_range(4.0, 8.0)
	_pick_new_target()
	play("Swim", 0.3)


func _enter_idle_state() -> void:
	state = State.IDLE
	state_timer = randf_range(2.0, 4.2)
	play("Idle", 0.35)


func _enter_seek_food_state() -> void:
	state = State.SEEK_FOOD
	play("Swim", 0.25)


func _pick_new_target() -> void:
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size
	# Fish like to visit decorations; each visit cheers them up (see _nearby_decor_comfort)
	var decor: Array = get_tree().get_nodes_in_group("decorations") if is_inside_tree() else []
	if not decor.is_empty() and randf() < 0.35:
		var d: Node = decor[randi() % decor.size()]
		if is_instance_valid(d) and d.has_method("get_center"):
			var c: Vector3 = d.call("get_center")
			var top := c.y + float(d.call("get_height"))
			target_position = Vector3(
				clampf(c.x + randf_range(-0.8, 0.8), min_p.x, max_p.x),
				clampf(top + randf_range(0.1, 1.0), min_p.y, max_p.y),
				clampf(c.z + randf_range(-0.8, 0.8), min_p.z, max_p.z)
			)
			return
	for _i in range(6):
		var candidate := Vector3(
			randf_range(min_p.x, max_p.x),
			randf_range(min_p.y, max_p.y),
			randf_range(min_p.z, max_p.z)
		)
		if absf(candidate.y - global_position.y) > 2.2:
			candidate.y = clampf(
				global_position.y + randf_range(-1.6, 1.6),
				min_p.y,
				max_p.y
			)
		if candidate.distance_to(global_position) > 1.8:
			target_position = candidate
			return
	target_position = tank_bounds.get_center()


func get_hunger_status_name() -> String:
	return HUNGER_NAMES[clampi(int(hunger_status), 0, HUNGER_NAMES.size() - 1)]


func get_mood_name() -> String:
	return MOOD_NAMES[clampi(int(mood), 0, MOOD_NAMES.size() - 1)]


func get_mood_description() -> String:
	match mood:
		Mood.HAPPY:
			return "Happy - full value coins"
		Mood.STRESSED:
			return "Stressed - hiding, slower and cheaper coins"
		_:
			if is_coin_penalized():
				if size_category == SizeCategory.BABY:
					return "Too bored - makes no coins"
				return "Too bored - only %s coins" % COIN_NAMES[clampi(get_coin_tier(), 0, 2)]
			return "Bored - cheaper coins in %ds (add decorations)" % int(ceilf(Balance.bored_limit() - bored_time))


func get_display_label() -> String:
	var s_idx := clampi(int(size_category), 0, SIZE_NAMES.size() - 1)
	var hunger_str := "Fed"
	if hunger_status == HungerStatus.HUNGRY:
		hunger_str = "Hungry, starves in %.0fs" % ceilf(starve_timer)
		if no_food_for_size:
			hunger_str += " - needs %s or better" % PLANT_FOR_SIZE[clampi(int(size_category), 0, 2)]
	var growth_str := "Fully grown"
	if size_category == SizeCategory.BABY:
		growth_str = "Meals %d / %d to grow" % [meals_eaten, MEALS_TO_MEDIUM]
	elif size_category == SizeCategory.MEDIUM:
		growth_str = "Meals %d / %d to grow" % [meals_eaten, MEALS_TO_ADULT]
	var coin_str := "No coins while this bored"
	var tier := get_coin_tier()
	if tier >= 0:
		coin_str = "Next %s coin in %.0fs" % [COIN_NAMES[tier], ceilf(maxf(0.0, coin_timer))]
	return "%s Goldfish | %s | %s | %s | %s" % [
		SIZE_NAMES[s_idx],
		hunger_str,
		get_mood_description(),
		growth_str,
		coin_str
	]


func get_focus_distance() -> float:
	match size_category:
		SizeCategory.BABY:
			return 2.6
		SizeCategory.MEDIUM:
			return 3.4
		_:
			return 4.2
