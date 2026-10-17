extends Node3D
class_name ArcherFish

## Pet Archer Fish controller.
## Does not need to feed; swims around the tank and shoots high-visibility water jets at any active threat.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const ARCHER_MODEL := preload("res://assets/fih/archerfish.glb")
const CombatVFXScript = preload("res://scripts/combat_vfx.gd")

const VISUAL_SCALE: float = 0.30
const BASE_VISUAL_POS := Vector3(0.0, 0.0, -0.22)
const BASE_VISUAL_ROT := Vector3(0.0, PI * 0.5, 0.0)
const SWIM_SPEED: float = 2.05
const ATTACK_SWIM_SPEED: float = 2.65
const SHOOT_COOLDOWN: float = 1.15
const SHOT_DAMAGE: float = 18.0
const SHOT_SPEED: float = 14.5

enum State { IDLE, SWIM, ATTACK_THREAT }

@export var tank_bounds: AABB = AABB(Vector3(-6.7, 1.3, -3.9), Vector3(13.4, 4.6, 7.8))

var state: State = State.SWIM
var velocity: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var state_timer: float = 0.0
var shoot_timer: float = 0.4
var bob_phase: float = 0.0
var current_speed: float = 0.0

var _visual_root: Node3D = null
var _anim_player: AnimationPlayer = null
var _hit_area: Area3D = null
var _status_label: Label3D = null
var _projectiles_node: Node3D = null

var _core_mesh: CapsuleMesh = null
var _shell_mesh: CapsuleMesh = null
var _tail_mesh: CylinderMesh = null
var _wake_drop_mesh: SphereMesh = null

var _core_mat: StandardMaterial3D = null
var _shell_mat: StandardMaterial3D = null
var _tail_mat: StandardMaterial3D = null
var _trail_ribbon_mat: StandardMaterial3D = null
var _trail_ribbon_mesh: ImmediateMesh = null
var _trail_ribbon_instance: MeshInstance3D = null

var _active_shots: Array[Dictionary] = []
var _wake_drops: Array[Dictionary] = []

var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D = null
var _flash_timer: float = 0.0
var _recoil_timer: float = 0.0
var is_selected: bool = false
var _outline_mat: ShaderMaterial = null


func _ready() -> void:
	add_to_group("archerfish")
	add_to_group("selectable_fish")
	add_to_group("selectable_entities")
	bob_phase = randf() * TAU
	shoot_timer = randf_range(0.2, 0.7)
	_outline_mat = CombatVFXScript.create_selection_outline_material(Color(0.38, 0.96, 1.0, 0.96), 3.2)

	_setup_visual_and_collision()
	_setup_projectile_resources()
	_enter_swim_state()


func set_selected(selected: bool) -> void:
	is_selected = selected
	if _visual_root:
		CombatVFXScript.set_selection_outline(_visual_root, is_selected, _outline_mat)


func _exit_tree() -> void:
	if _projectiles_node and is_instance_valid(_projectiles_node):
		_projectiles_node.queue_free()


func _setup_visual_and_collision() -> void:
	_visual_root = ARCHER_MODEL.instantiate()
	# Raw GLB faces +X; rotate +90 deg around Y so Mouth aligns with -Z (Godot forward)
	_visual_root.rotation = BASE_VISUAL_ROT
	_visual_root.scale = Vector3.ONE * VISUAL_SCALE
	_visual_root.position = BASE_VISUAL_POS
	add_child(_visual_root)

	_mesh_instances = CombatVFXScript.collect_mesh_instances(_visual_root)
	_flash_mat = CombatVFXScript.create_flash_material()
	if is_selected:
		CombatVFXScript.set_selection_outline(_visual_root, true, _outline_mat)

	var found := _visual_root.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		_anim_player = found[0] as AnimationPlayer
		for anim_name in ["Idle", "Swim"]:
			if _anim_player.has_animation(anim_name):
				_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

	_hit_area = Area3D.new()
	_hit_area.name = "ClickArea"
	_hit_area.collision_layer = 2
	_hit_area.collision_mask = 0
	_hit_area.input_ray_pickable = true
	add_child(_hit_area)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.65
	col.shape = shape
	_hit_area.add_child(col)

	_status_label = Label3D.new()
	_status_label.name = "PetTag"
	_status_label.position = Vector3(0.0, 0.44, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.pixel_size = 0.0036
	_status_label.font_size = 28
	_status_label.outline_size = 6
	_status_label.modulate = Color(0.55, 0.92, 1.0, 0.85)
	_status_label.outline_modulate = Color(0.05, 0.1, 0.15, 0.85)
	_status_label.text = ""
	_status_label.visible = false
	add_child(_status_label)


func _setup_projectile_resources() -> void:
	_projectiles_node = Node3D.new()
	_projectiles_node.name = "WaterShots"
	_projectiles_node.top_level = true
	add_child(_projectiles_node)

	# 1. Bright glowing inner core (high contrast + glow)
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.albedo_color = Color(2.0, 2.45, 2.8, 0.98)

	_core_mesh = CapsuleMesh.new()
	_core_mesh.radius = 0.16
	_core_mesh.height = 0.68
	_core_mesh.radial_segments = 10
	_core_mesh.rings = 4
	_core_mesh.material = _core_mat

	# 2. Saturated cobalt-aqua outer shell for high contrast against bright skies/water
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shell_mat.albedo_color = Color(0.04, 0.56, 1.0, 0.72)

	_shell_mesh = CapsuleMesh.new()
	_shell_mesh.radius = 0.25
	_shell_mesh.height = 0.90
	_shell_mesh.radial_segments = 10
	_shell_mesh.rings = 4
	_shell_mesh.material = _shell_mat

	# 3. Elongated pressurized water-jet cone tail
	_tail_mat = StandardMaterial3D.new()
	_tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tail_mat.albedo_color = Color(0.28, 0.90, 1.0, 0.78)

	_tail_mesh = CylinderMesh.new()
	_tail_mesh.top_radius = 0.03
	_tail_mesh.bottom_radius = 0.20
	_tail_mesh.height = 1.45
	_tail_mesh.radial_segments = 10
	_tail_mesh.rings = 2
	_tail_mesh.material = _tail_mat

	# 4. Wake droplet spheres left behind along flight path
	_wake_drop_mesh = SphereMesh.new()
	_wake_drop_mesh.radius = 0.10
	_wake_drop_mesh.height = 0.20
	_wake_drop_mesh.radial_segments = 8
	_wake_drop_mesh.rings = 4

	# 5. Continuous ImmediateMesh ribbon trail for water stream
	_trail_ribbon_mat = StandardMaterial3D.new()
	_trail_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_ribbon_mat.vertex_color_use_as_albedo = true

	_trail_ribbon_mesh = ImmediateMesh.new()
	_trail_ribbon_instance = MeshInstance3D.new()
	_trail_ribbon_instance.name = "WaterStreamRibbons"
	_trail_ribbon_instance.mesh = _trail_ribbon_mesh
	_trail_ribbon_instance.material_override = _trail_ribbon_mat
	_projectiles_node.add_child(_trail_ribbon_instance)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	bob_phase += delta * 2.4
	state_timer -= delta
	_update_recoil_and_flash(delta)
	_update_water_shots(delta)

	var active_threat := _find_active_threat()
	if active_threat != null:
		if state != State.ATTACK_THREAT:
			state = State.ATTACK_THREAT
			play_anim("Swim", 0.2)
		_process_attack_threat(active_threat, delta)
	else:
		if state == State.ATTACK_THREAT:
			_enter_swim_state()
		if _status_label:
			_status_label.visible = false
		match state:
			State.SWIM:
				_process_swim(delta)
			State.IDLE:
				_process_idle(delta)

	_keep_within_bounds(delta)


func _update_recoil_and_flash(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		var alpha := clampf(_flash_timer / 0.12, 0.0, 1.0) * 0.75
		CombatVFXScript.update_flash_overlay(_mesh_instances, _flash_mat, alpha, Color(1.4, 2.2, 2.5, 1.0))
	else:
		CombatVFXScript.update_flash_overlay(_mesh_instances, _flash_mat, 0.0)

	if _visual_root:
		if _recoil_timer > 0.0:
			_recoil_timer = maxf(0.0, _recoil_timer - delta)
			var t := _recoil_timer / 0.18
			var kick_back := sin(t * PI) * 0.16
			var squash := sin(t * PI) * 0.22
			_visual_root.position = BASE_VISUAL_POS + Vector3(0.0, 0.0, kick_back)
			_visual_root.scale = Vector3(
				VISUAL_SCALE * (1.0 + squash),
				VISUAL_SCALE * (1.0 - squash * 0.5),
				VISUAL_SCALE * (1.0 + squash)
			)
		else:
			_visual_root.position = BASE_VISUAL_POS
			_visual_root.scale = Vector3.ONE * VISUAL_SCALE


func _find_active_threat() -> Node3D:
	var best_threat: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("threat"):
		if node is Node3D and is_instance_valid(node):
			if node.has_method("is_attackable") and bool(node.call("is_attackable")):
				var t_node := node as Node3D
				var d := global_position.distance_to(t_node.global_position)
				if d < best_dist:
					best_dist = d
					best_threat = t_node
	return best_threat


func _process_attack_threat(threat: Node3D, delta: float) -> void:
	if _status_label:
		_status_label.visible = false

	var threat_pos := threat.global_position
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size

	# Swim to a surface vantage point beneath/near the threat
	var desired_spot := Vector3(
		clampf(threat_pos.x, min_p.x + 0.6, max_p.x - 0.6),
		clampf(max_p.y - 0.25, min_p.y, max_p.y),
		clampf(threat_pos.z, min_p.z + 0.6, max_p.z - 0.6)
	)
	desired_spot += _compute_separation() * 0.9

	var to_spot := desired_spot - global_position
	var dist_spot := to_spot.length()

	if dist_spot > 1.35:
		var dir := to_spot / maxf(dist_spot, 0.001)
		current_speed = lerpf(current_speed, ATTACK_SWIM_SPEED, delta * 3.5)
		_steer_toward(dir, delta, 3.8, 0.35)
		global_position += (-global_transform.basis.z) * current_speed * delta
	else:
		# Aim toward the threat and fire water jets
		current_speed = lerpf(current_speed, 0.2, delta * 4.0)
		var to_threat := (threat_pos - global_position).normalized()
		_steer_toward(to_threat, delta, 5.0, 0.55)
		global_position += Vector3(0.0, cos(bob_phase) * 0.1 * delta, 0.0)

	shoot_timer -= delta
	if shoot_timer <= 0.0:
		shoot_timer = SHOOT_COOLDOWN * randf_range(0.9, 1.1)
		_fire_water_shot(threat)


func _fire_water_shot(threat: Node3D) -> void:
	play_anim("Shoot", 0.1)
	_flash_timer = 0.12
	_recoil_timer = 0.18

	var start_pos := global_position + (-global_transform.basis.z) * 0.42 + Vector3(0.0, 0.14, 0.0)
	CombatVFXScript.spawn_water_splash(get_tree(), start_pos, 0.62)

	var bolt_root := Node3D.new()
	bolt_root.name = "WaterJetBolt"
	_projectiles_node.add_child(bolt_root)
	bolt_root.global_position = start_pos

	# Inner bright glowing core aligned along -Z
	var core_inst := MeshInstance3D.new()
	core_inst.mesh = _core_mesh
	core_inst.rotation.x = PI * 0.5
	bolt_root.add_child(core_inst)

	# Outer high-contrast electric blue shell
	var shell_inst := MeshInstance3D.new()
	shell_inst.mesh = _shell_mesh
	shell_inst.rotation.x = PI * 0.5
	bolt_root.add_child(shell_inst)

	# Pressurized jet cone tail trailing behind (+Z)
	var tail_inst := MeshInstance3D.new()
	tail_inst.mesh = _tail_mesh
	tail_inst.rotation.x = -PI * 0.5
	tail_inst.position = Vector3(0.0, 0.0, 0.68)
	bolt_root.add_child(tail_inst)

	if is_instance_valid(threat):
		var t_pos := threat.global_position
		if t_pos.distance_squared_to(start_pos) > 0.01:
			bolt_root.look_at(t_pos, Vector3.UP)

	var trail_pts: Array[Vector3] = [start_pos]
	_active_shots.append({
		"node": bolt_root,
		"target": threat,
		"pos": start_pos,
		"speed": SHOT_SPEED,
		"age": 0.0,
		"wake_timer": 0.0,
		"trail_points": trail_pts,
	})


func _spawn_wake_droplet(world_pos: Vector3) -> void:
	var drop_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.95, 1.0, 0.85)
	drop_inst.mesh = _wake_drop_mesh
	drop_inst.material_override = mat
	_projectiles_node.add_child(drop_inst)
	drop_inst.global_position = world_pos + Vector3(
		randf_range(-0.06, 0.06),
		randf_range(-0.06, 0.06),
		randf_range(-0.06, 0.06)
	)
	_wake_drops.append({
		"node": drop_inst,
		"mat": mat,
		"age": 0.0,
		"max_age": 0.26,
	})


func _update_water_shots(delta: float) -> void:
	var i := _active_shots.size() - 1
	while i >= 0:
		var shot: Dictionary = _active_shots[i]
		var node: Node3D = shot["node"]
		var target: Node3D = shot["target"]
		shot["age"] = float(shot["age"]) + delta
		shot["wake_timer"] = float(shot["wake_timer"]) + delta

		if not is_instance_valid(node) or float(shot["age"]) > 1.8:
			if is_instance_valid(node):
				node.queue_free()
			_active_shots.remove_at(i)
			i -= 1
			continue

		var target_pos: Vector3 = target.global_position if is_instance_valid(target) else (Vector3(shot["pos"]) + Vector3(0.0, 4.0, 0.0))
		var cur_pos: Vector3 = shot["pos"]
		var to_t := target_pos - cur_pos
		var d := to_t.length()
		var step := float(shot["speed"]) * delta

		if d <= step + 0.42:
			if is_instance_valid(target) and target.has_method("apply_archer_hit"):
				target.call("apply_archer_hit", SHOT_DAMAGE)
			node.queue_free()
			_active_shots.remove_at(i)
		else:
			var next_pos := cur_pos + (to_t / maxf(d, 0.001)) * step
			shot["pos"] = next_pos
			node.global_position = next_pos
			if target_pos.distance_squared_to(next_pos) > 0.001:
				node.look_at(target_pos, Vector3.UP)

			var pts: Array[Vector3] = shot["trail_points"]
			pts.push_front(next_pos)
			if pts.size() > 12:
				pts.resize(12)

			if float(shot["wake_timer"]) >= 0.025:
				shot["wake_timer"] = 0.0
				_spawn_wake_droplet(cur_pos)
		i -= 1

	# Update wake droplets
	var w_idx := _wake_drops.size() - 1
	while w_idx >= 0:
		var drop: Dictionary = _wake_drops[w_idx]
		var d_node: MeshInstance3D = drop["node"]
		var d_mat: StandardMaterial3D = drop["mat"]
		var age := float(drop["age"]) + delta
		var max_age := float(drop["max_age"])
		drop["age"] = age
		if not is_instance_valid(d_node) or age >= max_age:
			if is_instance_valid(d_node):
				d_node.queue_free()
			_wake_drops.remove_at(w_idx)
		else:
			var t := age / max_age
			d_node.scale = Vector3.ONE * lerpf(1.15, 0.2, t)
			d_node.global_position.y -= delta * 0.6
			if d_mat:
				d_mat.albedo_color.a = (1.0 - t) * 0.82
		w_idx -= 1

	_rebuild_projectile_ribbons()


func _rebuild_projectile_ribbons() -> void:
	if _trail_ribbon_mesh == null:
		return
	_trail_ribbon_mesh.clear_surfaces()
	if _active_shots.is_empty():
		return

	for shot in _active_shots:
		var pts: Array[Vector3] = shot["trail_points"]
		if pts.size() < 2:
			continue
		_draw_crossed_ribbon(pts, 0.18, Color(1.4, 2.2, 2.6, 0.90), Color(0.08, 0.65, 1.0, 0.0))


func _draw_crossed_ribbon(pts: Array[Vector3], base_width: float, head_col: Color, tail_col: Color) -> void:
	var count := pts.size()
	if count < 2:
		return

	for pass_idx in range(2):
		_trail_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for idx in range(count):
			var t := float(idx) / float(count - 1)
			var p := pts[idx]
			var forward := Vector3.FORWARD
			if idx < count - 1:
				forward = (pts[idx] - pts[idx + 1]).normalized()
			elif idx > 0:
				forward = (pts[idx - 1] - pts[idx]).normalized()
			if forward.length_squared() < 0.001:
				forward = Vector3.UP

			var ref_up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
			var side_a := forward.cross(ref_up).normalized()
			var side_b := forward.cross(side_a).normalized()
			var axis := side_a if pass_idx == 0 else side_b

			var w := base_width * (1.0 - t * 0.85)
			var col := head_col.lerp(tail_col, t)
			_trail_ribbon_mesh.surface_set_color(col)
			_trail_ribbon_mesh.surface_add_vertex(p + axis * w)
			_trail_ribbon_mesh.surface_set_color(col)
			_trail_ribbon_mesh.surface_add_vertex(p - axis * w)
		_trail_ribbon_mesh.surface_end()


func _process_swim(delta: float) -> void:
	var to_target := target_position - global_position
	var dist := to_target.length()

	if dist < 0.85 or state_timer <= 0.0:
		if randf() < 0.32:
			_enter_idle_state()
		else:
			_pick_new_target()
			state_timer = randf_range(3.5, 7.0)
		return

	var desired_dir := to_target / maxf(dist, 0.001)
	desired_dir += _compute_separation() * 0.75
	if desired_dir.length_squared() > 0.001:
		desired_dir = desired_dir.normalized()

	var arrival_factor := clampf(dist / 2.0, 0.5, 1.0)
	current_speed = lerpf(current_speed, SWIM_SPEED * arrival_factor, delta * 2.8)
	_steer_toward(desired_dir, delta, 2.8, 0.35)

	velocity = (-global_transform.basis.z) * current_speed
	global_position += velocity * delta


func _process_idle(delta: float) -> void:
	if state_timer <= 0.0:
		_enter_swim_state()
		return

	current_speed = lerpf(current_speed, 0.14, delta * 2.2)
	var forward := -global_transform.basis.z
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length_squared() < 0.001:
		flat_forward = Vector3.FORWARD
	else:
		flat_forward = flat_forward.normalized()

	_steer_toward(flat_forward, delta, 1.2, 0.15)
	global_position += (flat_forward * current_speed + Vector3(0.0, cos(bob_phase) * 0.1, 0.0)) * delta


func _steer_toward(desired_dir: Vector3, delta: float, rate: float, max_pitch: float) -> void:
	var flat_len := Vector2(desired_dir.x, desired_dir.z).length()
	var target_yaw := rotation.y
	if flat_len > 0.001:
		target_yaw = atan2(-desired_dir.x, -desired_dir.z)

	var prev_yaw := rotation.y
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * rate, 0.0, 1.0))
	var yaw_rate := angle_difference(prev_yaw, rotation.y) / maxf(delta, 0.001)

	var target_pitch := clampf(asin(clampf(desired_dir.y, -0.75, 0.75)), -max_pitch, max_pitch)
	rotation.x = lerp_angle(rotation.x, target_pitch, clampf(delta * 3.5, 0.0, 1.0))

	var target_roll := clampf(-yaw_rate * 0.12, -0.22, 0.22)
	rotation.z = lerp_angle(rotation.z, target_roll, clampf(delta * 4.0, 0.0, 1.0))


func _compute_separation() -> Vector3:
	var steer := Vector3.ZERO
	var my_radius := 1.35
	for node in get_tree().get_nodes_in_group("archerfish"):
		if node == self or not (node is Node3D):
			continue
		var other := node as Node3D
		var diff := global_position - other.global_position
		var d := diff.length()
		if d > 0.001 and d < my_radius:
			steer += (diff / d) * ((my_radius - d) / my_radius)
	return steer


func _keep_within_bounds(delta: float) -> void:
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size
	var pos := global_position
	var clamped := Vector3(
		clampf(pos.x, min_p.x, max_p.x),
		clampf(pos.y, min_p.y, max_p.y),
		clampf(pos.z, min_p.z, max_p.z)
	)
	if pos != clamped:
		global_position = pos.lerp(clamped, clampf(delta * 8.0, 0.0, 1.0))


func _enter_swim_state() -> void:
	state = State.SWIM
	state_timer = randf_range(4.0, 7.5)
	_pick_new_target()
	play_anim("Swim", 0.25)


func _enter_idle_state() -> void:
	state = State.IDLE
	state_timer = randf_range(1.8, 3.6)
	play_anim("Idle", 0.3)


func _pick_new_target() -> void:
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size
	# Archer fish prefer patrolling upper-middle water column
	target_position = Vector3(
		randf_range(min_p.x + 0.5, max_p.x - 0.5),
		randf_range(min_p.y + 1.8, max_p.y - 0.15),
		randf_range(min_p.z + 0.5, max_p.z - 0.5)
	)


func play_anim(anim_name: String, blend: float = 0.2) -> void:
	if _anim_player and _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name, blend)


func get_display_label() -> String:
	var mode_str := "Shooting at a Kingfisher" if state == State.ATTACK_THREAT else "Patrolling"
	return "Archer Fish | %s | %d damage every %.1fs | Needs no food" % [mode_str, int(SHOT_DAMAGE), SHOOT_COOLDOWN]


func get_focus_distance() -> float:
	return 3.5
