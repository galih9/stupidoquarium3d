extends "res://assets/fih/goldfish.gd"
class_name SwimmingFish

## Autonomous goldfish controller supporting swimming, idling, duckweed feeding,
## hunger/stress stats, growth stages, coin dropping on a timer, hit-flash/hitstop/shake effects, and death.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const CombatVFXScript = preload("res://scripts/combat_vfx.gd")
const Balance = preload("res://scripts/game_balance.gd")

const MEALS_TO_MEDIUM: int = 3
const MEALS_TO_ADULT: int = 7

enum State { IDLE, SWIM, SEEK_FOOD, EATING, DYING }
enum SizeCategory { BABY, MEDIUM, ADULT }
enum HungerStatus { FED, HUNGRY }
enum StressStatus { STRESS, BORED, NORMAL, HAPPY }

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
const STRESS_NAMES := ["Stress", "Bored", "Normal", "Happy"]

signal coin_dropped(world_pos: Vector3, size_cat: int, stress: int)
signal fish_died(fish: SwimmingFish, reason: String)

@export var size_category: SizeCategory = SizeCategory.BABY
@export var tank_bounds: AABB = AABB(Vector3(-6.7, 1.05, -3.9), Vector3(13.4, 4.75, 7.8))
@export var fed_duration_min: float = Balance.FISH_FED_MIN
@export var fed_duration_max: float = Balance.FISH_FED_MAX
@export var max_starve_time: float = Balance.FISH_STARVE_TIME
@export var base_coin_interval: float = Balance.FISH_COIN_INTERVAL

var state: State = State.SWIM
var hunger_status: HungerStatus = HungerStatus.FED
var stress_status: StressStatus = StressStatus.NORMAL

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
	stress_status = StressStatus.NORMAL
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

	if is_dead or state == State.DYING:
		return

	match state:
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
	elif not _is_snatched_anim:
		_visual_root.position = _base_visual_pos
		_visual_root.rotation = _base_visual_rot
		_visual_root.scale = Vector3.ONE * _base_visual_scale


func on_predator_strike(_attacker_pos: Vector3) -> void:
	if is_dead or _is_snatched_anim:
		return
	stress_status = StressStatus.STRESS
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
		var mult := _get_stress_coin_interval_multiplier()
		coin_timer = randf_range(base_coin_interval * 0.85, base_coin_interval * 1.15) * mult
		coin_dropped.emit(global_position + Vector3(0.0, -0.15, 0.0), int(size_category), int(stress_status))


func _get_stress_coin_interval_multiplier() -> float:
	match stress_status:
		StressStatus.HAPPY:
			return 0.72
		StressStatus.NORMAL:
			return 1.0
		StressStatus.BORED:
			return 1.45
		StressStatus.STRESS:
			return 2.1
		_:
			return 1.0


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
		# All duckweed tiles are currently occupied; wait near the closest duckweed below the surface
		var any_tile: Node3D = _find_closest_duckweed(false)
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


func _find_closest_duckweed(only_available: bool) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("duckweed"):
		if not (node is Node3D):
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

	# Brief celebratory flash & pop when growing to next size stage
	_flash_duration = 0.16
	_flash_timer = _flash_duration
	_shake_duration = 0.20
	_shake_timer = _shake_duration
	_shake_intensity = 0.12
	CombatVFXScript.spawn_hit_effect(
		get_tree(),
		global_position,
		false,
		"GREW TO %s!" % SIZE_NAMES[int(new_size)].to_upper(),
		Color(0.45, 1.0, 0.55, 1.0)
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


func set_stress_status(new_status: StressStatus) -> void:
	stress_status = new_status


func cycle_stress_status() -> void:
	stress_status = ((int(stress_status) + 1) % STRESS_NAMES.size()) as StressStatus


func get_hunger_status_name() -> String:
	return HUNGER_NAMES[clampi(int(hunger_status), 0, HUNGER_NAMES.size() - 1)]


func get_stress_status_name() -> String:
	return STRESS_NAMES[clampi(int(stress_status), 0, STRESS_NAMES.size() - 1)]


func get_display_label() -> String:
	var v_idx := clampi(int(variant), 0, VARIANT_TITLES.size() - 1)
	var s_idx := clampi(int(size_category), 0, SIZE_NAMES.size() - 1)
	var hunger_str := "Fed"
	if hunger_status == HungerStatus.HUNGRY:
		hunger_str = "Hungry, starves in %.0fs" % ceilf(starve_timer)
	var growth_str := "Fully grown"
	if size_category == SizeCategory.BABY:
		growth_str = "Meals %d / %d to grow" % [meals_eaten, MEALS_TO_MEDIUM]
	elif size_category == SizeCategory.MEDIUM:
		growth_str = "Meals %d / %d to grow" % [meals_eaten, MEALS_TO_ADULT]
	return "%s Goldfish (%s) | %s | Mood: %s | %s | Next coin in %.0fs" % [
		VARIANT_TITLES[v_idx],
		SIZE_NAMES[s_idx],
		hunger_str,
		get_stress_status_name(),
		growth_str,
		ceilf(maxf(0.0, coin_timer))
	]


func get_focus_distance() -> float:
	match size_category:
		SizeCategory.BABY:
			return 2.6
		SizeCategory.MEDIUM:
			return 3.4
		_:
			return 4.2
