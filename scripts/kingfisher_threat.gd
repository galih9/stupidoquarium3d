extends Node3D
class_name KingfisherThreat

## Kingfisher aerial/diving predator threat.
## Careful Phase: Circles above the aquarium and observes fish without attacking.
## Attack Phase: Flies around with 3D wingtip/slipstream trails and dives to strike the closest goldfish.
## Fish closer to the water surface are snatched much faster.
## Archer Fish slow the Kingfisher and deal damage to kill it, triggering white flash, hitstop, and shake.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const KINGFISHER_MODEL := preload("res://assets/fih/kingfisher.glb")
const CombatVFXScript = preload("res://scripts/combat_vfx.gd")
const Balance = preload("res://scripts/game_balance.gd")

const VISUAL_SCALE: float = 0.46
const BASE_VISUAL_POS := Vector3(0.0, -0.35, 0.0)
const BASE_VISUAL_ROT := Vector3(0.0, PI * 0.5, 0.0)
const WATER_SURFACE_Y: float = 6.35
const TANK_BOTTOM_Y: float = 1.05

enum PhaseMode { OBSERVE, ATTACK, RETREAT, DEFEATED }
enum AttackState { FLY_HUNT, DIVE_STRIKE, CLIMB_OUT }

signal fish_snatched(fish: Node3D)
signal threat_killed(threat: KingfisherThreat)

@export var max_hp: float = 175.0

var hp: float = 175.0
var wave_level: int = 1
var bird_index: int = 0
var total_birds_in_wave: int = 1
## Wave speed multiplier (set by the main controller from GameBalance).
var speed_boost: float = 1.0
## 0.0 = gentle (slow dives, long snatch time), 1.0 = full late-game aggression.
var aggression: float = 0.0
## Tutorial training bird: pecks at fish but can never snatch one.
var training_mode: bool = false
var phase_mode: PhaseMode = PhaseMode.OBSERVE
var attack_state: AttackState = AttackState.FLY_HUNT

var target_fish: Node3D = null
var orbit_angle: float = 0.0
var strike_cooldown: float = 0.8
var snatch_progress: float = 0.0
var climb_target: Vector3 = Vector3(0.0, 7.4, 0.0)

var _visual_root: Node3D = null
var _anim_player: AnimationPlayer = null
var _status_label: Label3D = null
var _defeat_timer: float = 0.0
var _dive_elapsed: float = 0.0

# Hit feedback: white flash, brief hit delay (hitstop), and shake animation
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D = null
var _flash_timer: float = 0.0
var _flash_duration: float = 0.18
var _hitstop_timer: float = 0.0
var _shake_timer: float = 0.0
var _shake_duration: float = 0.28
var _shake_intensity: float = 0.24
var _shake_phase: float = 0.0
var _strike_peck_timer: float = 0.0
var _was_above_water: bool = true

# 3D Flight Trail System (wingtip ribbons + center slipstream)
var _trail_root: Node3D = null
var _trail_mesh: ImmediateMesh = null
var _trail_instance: MeshInstance3D = null
var _trail_mat: StandardMaterial3D = null
var _left_wing_pts: Array[Dictionary] = []
var _right_wing_pts: Array[Dictionary] = []
var _center_pts: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("threat")
	hp = max_hp
	orbit_angle = (TAU * float(bird_index)) / maxf(float(total_birds_in_wave), 1.0)
	_was_above_water = global_position.y >= WATER_SURFACE_Y

	_setup_visuals()
	_setup_flight_trails()
	set_phase_observe()


func _exit_tree() -> void:
	if _trail_root and is_instance_valid(_trail_root):
		_trail_root.queue_free()


func _setup_visuals() -> void:
	_visual_root = KINGFISHER_MODEL.instantiate()
	# Raw GLB beak faces +X; rotate +90 deg around Y to align with -Z (Godot forward)
	_visual_root.rotation = BASE_VISUAL_ROT
	_visual_root.scale = Vector3.ONE * VISUAL_SCALE
	_visual_root.position = BASE_VISUAL_POS
	add_child(_visual_root)

	_mesh_instances = CombatVFXScript.collect_mesh_instances(_visual_root)
	_flash_mat = CombatVFXScript.create_flash_material()

	var found := _visual_root.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		_anim_player = found[0] as AnimationPlayer
		for anim_name in ["Idle", "Fly", "Swim"]:
			if _anim_player.has_animation(anim_name):
				_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		for once_name in ["Dive", "Strike"]:
			if _anim_player.has_animation(once_name):
				_anim_player.get_animation(once_name).loop_mode = Animation.LOOP_NONE

	_status_label = Label3D.new()
	_status_label.name = "ThreatLabel"
	_status_label.position = Vector3(0.0, 0.88, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.pixel_size = 0.0040
	_status_label.font_size = 32
	_status_label.outline_size = 8
	_status_label.modulate = Color(1.0, 0.78, 0.28, 0.92)
	_status_label.outline_modulate = Color(0.08, 0.04, 0.02, 0.9)
	add_child(_status_label)

	var click_area := Area3D.new()
	click_area.name = "ThreatClickArea"
	click_area.collision_layer = 32
	click_area.collision_mask = 0
	click_area.input_ray_pickable = true
	add_child(click_area)

	var click_col := CollisionShape3D.new()
	var click_sphere := SphereShape3D.new()
	click_sphere.radius = 0.95
	click_col.shape = click_sphere
	click_area.add_child(click_col)


func _setup_flight_trails() -> void:
	_trail_root = Node3D.new()
	_trail_root.name = "KingfisherFlightTrails"
	_trail_root.top_level = true
	add_child(_trail_root)

	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true

	_trail_mesh = ImmediateMesh.new()
	_trail_instance = MeshInstance3D.new()
	_trail_instance.name = "RibbonTrailMesh"
	_trail_instance.mesh = _trail_mesh
	_trail_instance.material_override = _trail_mat
	_trail_root.add_child(_trail_instance)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_update_hit_effects(delta)
	_update_flight_trails(delta)

	# Brief hit delay (hitstop): freeze flight translation and animation on impact frame
	if _hitstop_timer > 0.0:
		_hitstop_timer = maxf(0.0, _hitstop_timer - delta)
		if _anim_player:
			_anim_player.speed_scale = 0.0
		_update_label()
		return

	var prev_above := _was_above_water
	match phase_mode:
		PhaseMode.OBSERVE:
			_process_observe(delta)
		PhaseMode.ATTACK:
			_process_attack(delta)
		PhaseMode.RETREAT:
			_process_retreat(delta)
		PhaseMode.DEFEATED:
			_process_defeated(delta)

	var now_above := global_position.y >= WATER_SURFACE_Y
	if prev_above != now_above:
		_was_above_water = now_above
		CombatVFXScript.spawn_water_splash(
			get_tree(),
			Vector3(global_position.x, WATER_SURFACE_Y, global_position.z),
			1.15
		)

	_update_label()


func _update_hit_effects(delta: float) -> void:
	# 1. White flash overlay
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		var norm := clampf(_flash_timer / maxf(_flash_duration, 0.05), 0.0, 1.0)
		# Hold full pure white during hitstop, then smooth fade
		var alpha := 0.96 if _hitstop_timer > 0.0 else pow(norm, 0.7) * 0.92
		CombatVFXScript.update_flash_overlay(_mesh_instances, _flash_mat, alpha, Color(2.3, 2.3, 2.45, 1.0))
	else:
		CombatVFXScript.update_flash_overlay(_mesh_instances, _flash_mat, 0.0)

	# 2. Shake animation + squash/stretch punch on _visual_root
	if _visual_root == null:
		return

	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		_shake_phase += delta * 68.0
		var decay := clampf(_shake_timer / maxf(_shake_duration, 0.05), 0.0, 1.0)
		var amp := _shake_intensity * decay

		var offset := Vector3(
			sin(_shake_phase * 1.17) * amp,
			cos(_shake_phase * 1.53) * amp * 0.85,
			sin(_shake_phase * 1.91) * amp * 0.75
		)
		var rot_jitter := Vector3(
			cos(_shake_phase * 1.35) * amp * 0.85,
			sin(_shake_phase * 0.95) * amp * 0.55,
			sin(_shake_phase * 1.75) * amp * 1.25
		)
		var punch := sin(decay * PI) * 0.26
		var squash_scale := Vector3(
			VISUAL_SCALE * (1.0 + punch),
			VISUAL_SCALE * (1.0 - punch * 0.65),
			VISUAL_SCALE * (1.0 + punch)
		)

		_visual_root.position = BASE_VISUAL_POS + offset
		_visual_root.rotation = BASE_VISUAL_ROT + rot_jitter
		_visual_root.scale = squash_scale
	else:
		_visual_root.position = BASE_VISUAL_POS
		_visual_root.rotation = BASE_VISUAL_ROT
		_visual_root.scale = Vector3.ONE * VISUAL_SCALE


func _update_flight_trails(delta: float) -> void:
	var max_age := 0.48 if (phase_mode == PhaseMode.ATTACK and attack_state == AttackState.DIVE_STRIKE) else 0.38

	# Age and prune existing trail samples
	_age_trail_array(_left_wing_pts, delta, max_age)
	_age_trail_array(_right_wing_pts, delta, max_age)
	_age_trail_array(_center_pts, delta, max_age)

	# Sample current wingtip & tail positions when not frozen in hitstop
	if _hitstop_timer <= 0.0:
		var basis_now := global_transform.basis.orthonormalized()
		var left_pos := global_position + basis_now * Vector3(-0.62, 0.05, 0.08)
		var right_pos := global_position + basis_now * Vector3(0.62, 0.05, 0.08)
		var center_pos := global_position + basis_now * Vector3(0.0, -0.06, 0.34)

		_push_trail_sample(_left_wing_pts, left_pos, 26)
		_push_trail_sample(_right_wing_pts, right_pos, 26)
		_push_trail_sample(_center_pts, center_pos, 28)

	_rebuild_trail_meshes(max_age)


func _age_trail_array(arr: Array[Dictionary], delta: float, max_age: float) -> void:
	var i := arr.size() - 1
	while i >= 0:
		var next_age := float(arr[i]["age"]) + delta
		if next_age >= max_age:
			arr.remove_at(i)
		else:
			arr[i]["age"] = next_age
		i -= 1


func _push_trail_sample(arr: Array[Dictionary], world_pos: Vector3, max_points: int) -> void:
	if not arr.is_empty():
		var head_pos: Vector3 = arr[0]["pos"]
		if head_pos.distance_to(world_pos) < 0.035:
			arr[0]["pos"] = world_pos
			return
	arr.push_front({
		"pos": world_pos,
		"age": 0.0,
	})
	if arr.size() > max_points:
		arr.resize(max_points)


func _rebuild_trail_meshes(max_age: float) -> void:
	if _trail_mesh == null:
		return
	_trail_mesh.clear_surfaces()

	var is_diving := (phase_mode == PhaseMode.ATTACK and attack_state == AttackState.DIVE_STRIKE)
	var is_attacking := (phase_mode == PhaseMode.ATTACK)

	var wing_head_col := Color(0.65, 0.96, 1.0, 0.68)
	var wing_tail_col := Color(0.25, 0.75, 1.0, 0.0)
	var center_head_col := Color(1.0, 0.88, 0.45, 0.52)
	var center_tail_col := Color(0.55, 0.92, 1.0, 0.0)
	var wing_width := 0.11
	var center_width := 0.14

	if is_diving:
		wing_head_col = Color(1.8, 0.45, 0.32, 0.92)
		wing_tail_col = Color(1.0, 0.75, 0.25, 0.0)
		center_head_col = Color(2.0, 1.85, 1.6, 0.90)
		center_tail_col = Color(1.4, 0.35, 0.25, 0.0)
		wing_width = 0.16
		center_width = 0.24
	elif is_attacking:
		wing_head_col = Color(1.35, 0.72, 0.26, 0.82)
		wing_tail_col = Color(1.0, 0.35, 0.22, 0.0)
		center_head_col = Color(1.5, 0.92, 0.55, 0.68)
		center_tail_col = Color(1.0, 0.55, 0.2, 0.0)
		wing_width = 0.13
		center_width = 0.18

	_draw_ribbon_strip(_left_wing_pts, wing_width, wing_head_col, wing_tail_col, max_age)
	_draw_ribbon_strip(_right_wing_pts, wing_width, wing_head_col, wing_tail_col, max_age)
	_draw_ribbon_strip(_center_pts, center_width, center_head_col, center_tail_col, max_age)


func _draw_ribbon_strip(
	pts: Array[Dictionary],
	base_width: float,
	head_col: Color,
	tail_col: Color,
	max_age: float
) -> void:
	var count := pts.size()
	if count < 2:
		return

	# Draw two perpendicular crossed ribbon strips so the trail is visible from any 360 camera angle
	for pass_idx in range(2):
		_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for idx in range(count):
			var p: Vector3 = pts[idx]["pos"]
			var age: float = float(pts[idx]["age"])
			var t := clampf(maxf(float(idx) / float(count - 1), age / maxf(max_age, 0.05)), 0.0, 1.0)

			var tangent := Vector3.FORWARD
			if idx < count - 1:
				tangent = (Vector3(pts[idx]["pos"]) - Vector3(pts[idx + 1]["pos"])).normalized()
			elif idx > 0:
				tangent = (Vector3(pts[idx - 1]["pos"]) - Vector3(pts[idx]["pos"])).normalized()
			if tangent.length_squared() < 0.001:
				tangent = Vector3.UP

			var ref_up := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
			var side_a := tangent.cross(ref_up).normalized()
			var side_b := tangent.cross(side_a).normalized()
			var axis := side_a if pass_idx == 0 else side_b

			var w := base_width * pow(1.0 - t, 0.75)
			var col := head_col.lerp(tail_col, t)
			col.a = head_col.a * pow(1.0 - t, 1.35)

			_trail_mesh.surface_set_color(col)
			_trail_mesh.surface_add_vertex(p + axis * w)
			_trail_mesh.surface_set_color(col)
			_trail_mesh.surface_add_vertex(p - axis * w)
		_trail_mesh.surface_end()


func set_phase_observe() -> void:
	phase_mode = PhaseMode.OBSERVE
	play_anim("Fly", 0.25)


func set_phase_attack() -> void:
	if phase_mode == PhaseMode.DEFEATED:
		return
	phase_mode = PhaseMode.ATTACK
	attack_state = AttackState.FLY_HUNT
	strike_cooldown = lerpf(2.4, 1.0, aggression) + float(bird_index) * 0.8
	snatch_progress = 0.0
	play_anim("Fly", 0.2)


func retreat_and_despawn() -> void:
	if phase_mode == PhaseMode.DEFEATED:
		return
	phase_mode = PhaseMode.RETREAT
	play_anim("Fly", 0.2)


func is_attackable() -> bool:
	return phase_mode == PhaseMode.ATTACK


func get_archer_count() -> int:
	return get_tree().get_nodes_in_group("archerfish").size()


func get_speed_multiplier() -> float:
	# Wave scaling boosts bird speed; Archer Fish slow is shared across active birds
	var archers := get_archer_count()
	var wave_boost := speed_boost
	var slow_per_archer := 0.22 / maxf(1.0, float(total_birds_in_wave) * 0.60)
	var slow_factor := clampf(1.0 - float(archers) * slow_per_archer, 0.30, 1.0)
	return slow_factor * wave_boost


func get_slow_percent() -> int:
	return int(roundf(maxf(0.0, (1.0 - get_speed_multiplier()) * 100.0)))


func apply_archer_hit(damage: float) -> void:
	if phase_mode != PhaseMode.ATTACK:
		return
	hp = maxf(0.0, hp - damage)

	# Trigger bright white flash, brief hit delay (hitstop), and shake animation
	_flash_duration = 0.19
	_flash_timer = _flash_duration
	_hitstop_timer = maxf(_hitstop_timer, 0.085)
	_shake_duration = 0.28
	_shake_timer = _shake_duration
	_shake_intensity = 0.25

	CombatVFXScript.spawn_hit_effect(
		get_tree(),
		global_position + Vector3(0.0, 0.1, 0.0),
		false,
		"-%d" % int(roundf(damage)),
		Color(0.28, 0.92, 1.0, 1.0)
	)
	# No camera shake on archer hits: they happen constantly and made the screen jitter.

	if hp <= 0.0:
		_on_killed()


func apply_player_click(damage: float = Balance.PLAYER_CLICK_DAMAGE) -> void:
	if phase_mode != PhaseMode.ATTACK:
		return
	hp = maxf(0.0, hp - damage)
	snatch_progress = maxf(0.0, snatch_progress - 0.6)

	_flash_duration = 0.20
	_flash_timer = _flash_duration
	_hitstop_timer = maxf(_hitstop_timer, 0.06)
	_shake_duration = 0.22
	_shake_timer = _shake_duration
	_shake_intensity = 0.12

	# If diving, push the bird slightly upward to interrupt/delay the strike
	if attack_state == AttackState.DIVE_STRIKE:
		global_position.y += 0.55

	CombatVFXScript.spawn_hit_effect(
		get_tree(),
		global_position + Vector3(0.0, 0.15, 0.0),
		false,
		"-%d!" % int(roundf(damage)),
		Color(1.0, 0.65, 0.25, 1.0)
	)
	# Intentionally no camera shake here: manual clicks are frequent and the
	# screen shake was uncomfortable for players. Feedback comes from the
	# white flash, damage popup and the small wobble on the bird itself.

	if hp <= 0.0:
		_on_killed()


func _on_killed() -> void:
	if phase_mode == PhaseMode.DEFEATED:
		return
	phase_mode = PhaseMode.DEFEATED
	_defeat_timer = 0.0
	_flash_duration = 0.42
	_flash_timer = _flash_duration
	_hitstop_timer = 0.16
	_shake_duration = 0.52
	_shake_timer = _shake_duration
	_shake_intensity = 0.36

	CombatVFXScript.spawn_hit_effect(
		get_tree(),
		global_position,
		true,
		"DEFEATED!",
		Color(1.0, 0.86, 0.28, 1.0)
	)
	CombatVFXScript.trigger_camera_shake(get_tree(), 0.12, 0.22)
	play_anim("Fly", 0.15)
	threat_killed.emit(self)


func _process_observe(delta: float) -> void:
	# Careful phase: circle above the open aquarium in formation and observe fish without attacking
	orbit_angle += delta * (0.72 + float(bird_index % 3) * 0.06)
	var radius_x := 4.6 + float(bird_index % 2) * 0.65
	var radius_z := 2.6 + float(bird_index % 3) * 0.35
	var desired_pos := Vector3(
		cos(orbit_angle) * radius_x,
		7.55 + float(bird_index % 3) * 0.28 + sin(orbit_angle * 2.0) * 0.22,
		sin(orbit_angle) * radius_z
	)
	var move_dir := (desired_pos - global_position)
	if move_dir.length_squared() > 0.0001:
		_steer_toward(move_dir.normalized(), delta, 4.0, -0.18)
	global_position = global_position.lerp(desired_pos, clampf(delta * 3.5, 0.0, 1.0))

	if _anim_player:
		_anim_player.speed_scale = 1.0


func _process_attack(delta: float) -> void:
	var spd_mult := get_speed_multiplier()
	if _anim_player:
		_anim_player.speed_scale = clampf(spd_mult * 1.2, 0.45, 1.55)

	match attack_state:
		AttackState.FLY_HUNT:
			_process_fly_hunt(delta, spd_mult)
		AttackState.DIVE_STRIKE:
			_process_dive_strike(delta, spd_mult)
		AttackState.CLIMB_OUT:
			_process_climb_out(delta, spd_mult)


func _process_fly_hunt(delta: float, spd_mult: float) -> void:
	strike_cooldown -= delta * spd_mult
	target_fish = _find_closest_goldfish()

	if target_fish == null:
		# No fish in tank: circle above water surface
		orbit_angle += delta * 0.9 * spd_mult
		var idle_pos := Vector3(cos(orbit_angle) * 4.2, 7.3 + float(bird_index % 3) * 0.25, sin(orbit_angle) * 2.4)
		var dir := (idle_pos - global_position).normalized()
		_steer_toward(dir, delta, 4.0, 0.0)
		global_position = global_position.move_toward(idle_pos, 4.5 * spd_mult * delta)
		return

	var fish_pos := target_fish.global_position
	var hover_target := Vector3(fish_pos.x, 7.15 + float(bird_index % 2) * 0.18, fish_pos.z)
	var to_hover := hover_target - global_position
	var flat_dist := Vector2(to_hover.x, to_hover.z).length()

	var fly_speed := 5.4 * spd_mult
	if to_hover.length_squared() > 0.001:
		_steer_toward(to_hover.normalized(), delta, 5.5, -0.15)
	global_position = global_position.move_toward(hover_target, fly_speed * delta)

	if flat_dist < 1.25 and strike_cooldown <= 0.0:
		attack_state = AttackState.DIVE_STRIKE
		snatch_progress = 0.0
		_dive_elapsed = 0.0
		_strike_peck_timer = 0.0
		play_anim("Dive", 0.15)


func _process_dive_strike(delta: float, spd_mult: float) -> void:
	_dive_elapsed += delta
	if target_fish == null or not is_instance_valid(target_fish) or bool(target_fish.get("is_dead")):
		target_fish = _find_closest_goldfish()
		if target_fish == null or _dive_elapsed > 3.5:
			_begin_climb_out()
			return

	var fish_pos := target_fish.global_position
	# Surface proximity factor: 1.0 right at the water surface, 0.0 at the tank floor.
	# The closer the fish is to the surface, the faster the Kingfisher dives and snatches it.
	var depth := clampf(WATER_SURFACE_Y - fish_pos.y, 0.0, WATER_SURFACE_Y - TANK_BOTTOM_Y)
	var surface_proximity := 1.0 - (depth / maxf(WATER_SURFACE_Y - TANK_BOTTOM_Y, 0.01))

	var dive_speed := lerpf(3.0, 8.4, surface_proximity) * spd_mult
	var to_fish := fish_pos - global_position
	var dist := to_fish.length()

	if dist > 0.001:
		_steer_toward(to_fish / dist, delta, 7.0, -0.75)

	global_position = global_position.move_toward(fish_pos, dive_speed * delta)

	if dist <= 0.78:
		play_anim("Strike", 0.1)
		_strike_peck_timer -= delta
		if _strike_peck_timer <= 0.0:
			_strike_peck_timer = 0.24
			if is_instance_valid(target_fish) and target_fish.has_method("on_predator_strike"):
				target_fish.call("on_predator_strike", global_position)
			_shake_duration = 0.16
			_shake_timer = maxf(_shake_timer, 0.16)
			_shake_intensity = maxf(_shake_intensity, 0.14)

		# Snatch duration is shorter near the surface and shrinks as waves get more aggressive.
		# Wave 1: about 0.95s at the surface and 2.0s at the bottom.
		var snatch_surface := lerpf(0.95, 0.35, aggression)
		var snatch_bottom := lerpf(2.0, 1.0, aggression)
		var required_snatch_time := lerpf(snatch_bottom, snatch_surface, surface_proximity)
		snatch_progress += (delta * spd_mult) / maxf(required_snatch_time, 0.05)
		if training_mode and snatch_progress >= 0.9:
			# Training bird always misses and flies back up
			_begin_climb_out()
			return
		if snatch_progress >= 1.0:
			var caught := target_fish
			target_fish = null
			# Brief hitstop & shake on the Kingfisher at the moment of snatching
			_hitstop_timer = maxf(_hitstop_timer, 0.14)
			_shake_duration = 0.26
			_shake_timer = _shake_duration
			_shake_intensity = 0.24
			if is_instance_valid(caught) and caught.has_method("snatch_by_kingfisher"):
				caught.call("snatch_by_kingfisher")
			fish_snatched.emit(caught)
			_begin_climb_out()
			return

	# Abort dive if it takes too long (e.g. heavily slowed by Archer Fish)
	if _dive_elapsed >= 4.2:
		_begin_climb_out()


func _begin_climb_out() -> void:
	attack_state = AttackState.CLIMB_OUT
	strike_cooldown = lerpf(2.8, 1.3, aggression)
	snatch_progress = 0.0
	climb_target = Vector3(
		clampf(global_position.x + randf_range(-2.2, 2.2), -5.5, 5.5),
		7.4 + float(bird_index % 3) * 0.2,
		clampf(global_position.z + randf_range(-1.5, 1.5), -3.2, 3.2)
	)
	play_anim("Fly", 0.2)


func _process_climb_out(delta: float, spd_mult: float) -> void:
	var to_climb := climb_target - global_position
	var d := to_climb.length()
	if d > 0.001:
		_steer_toward(to_climb / d, delta, 5.0, 0.55)
	global_position = global_position.move_toward(climb_target, 6.0 * spd_mult * delta)
	if d < 0.45:
		attack_state = AttackState.FLY_HUNT
		play_anim("Fly", 0.2)


func _process_retreat(delta: float) -> void:
	var exit_pos := Vector3(0.0, 14.5, -9.0)
	var dir := (exit_pos - global_position).normalized()
	_steer_toward(dir, delta, 4.0, 0.45)
	global_position = global_position.move_toward(exit_pos, 8.5 * delta)
	if global_position.distance_to(exit_pos) < 0.8:
		queue_free()


func _process_defeated(delta: float) -> void:
	_defeat_timer += delta
	global_position += Vector3(0.0, 5.5, -4.5) * delta
	rotation.y += delta * 10.0
	rotation.z = lerp_angle(rotation.z, 0.8, clampf(delta * 4.0, 0.0, 1.0))
	if _defeat_timer >= 1.1:
		queue_free()


func _find_closest_goldfish() -> Node3D:
	var other_targets: Array[Node3D] = []
	for t_node in get_tree().get_nodes_in_group("threat"):
		if t_node == self or not is_instance_valid(t_node):
			continue
		var tf: Node3D = t_node.get("target_fish")
		if tf != null and is_instance_valid(tf):
			other_targets.append(tf)

	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("goldfish"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if bool(node.get("is_dead")):
			continue
		var fish := node as Node3D
		var score := global_position.distance_to(fish.global_position)
		if other_targets.has(fish):
			score += 6.0
		if score < best_score:
			best_score = score
			best = fish
	return best


func _steer_toward(desired_dir: Vector3, delta: float, rate: float, pitch_bias: float) -> void:
	var flat_len := Vector2(desired_dir.x, desired_dir.z).length()
	if flat_len > 0.001:
		var target_yaw := atan2(-desired_dir.x, -desired_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * rate, 0.0, 1.0))

	var target_pitch := clampf(asin(clampf(desired_dir.y, -0.85, 0.85)) + pitch_bias * 0.25, -0.85, 0.65)
	rotation.x = lerp_angle(rotation.x, target_pitch, clampf(delta * 5.0, 0.0, 1.0))


func _update_label() -> void:
	if _status_label == null:
		return
	match phase_mode:
		PhaseMode.OBSERVE:
			_status_label.visible = false
		PhaseMode.ATTACK:
			_status_label.visible = true
			_status_label.modulate = Color(1.0, 0.42, 0.36, 0.94)
			_status_label.text = "%d / %d HP" % [int(ceilf(hp)), int(max_hp)]
		PhaseMode.DEFEATED, PhaseMode.RETREAT:
			_status_label.visible = false


func play_anim(anim_name: String, blend: float = 0.2) -> void:
	if _anim_player and _anim_player.has_animation(anim_name):
		if _anim_player.current_animation != anim_name:
			_anim_player.play(anim_name, blend)
