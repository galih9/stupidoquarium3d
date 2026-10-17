extends Node3D
class_name PetCrab

## Pet Crab controller.
## Always present on the bottom of the tank by default.
## Moves around the sandy floor, chases and collects falling/fallen coins,
## and supports 12 upgrade levels: levels 1-6 raise its movement speed, levels 7-12 unlock
## and grow an area pickup that pulls in every coin around the crab at once.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const CRAB_MODEL := preload("res://assets/fih/crab.glb")
const CombatVFXScript = preload("res://scripts/combat_vfx.gd")
const Balance = preload("res://scripts/game_balance.gd")

const VISUAL_SCALE: float = 0.42
const BASE_VISUAL_POS := Vector3(0.0, 0.0, 0.0)
const BASE_VISUAL_ROT := Vector3(0.0, PI, 0.0)
const FLOOR_Y: float = 0.50
const MAX_SPEED_LEVEL: int = 12
const AREA_START_LEVEL: int = 7

# Speed levels 1-6 (levels 7-12 keep the top speed)
const WALK_SPEEDS: Array[float] = [0.55, 1.00, 1.55, 2.20, 3.00, 3.90]
const CHASE_SPEEDS: Array[float] = [0.80, 1.45, 2.25, 3.20, 4.30, 5.60]
# Pickup radius per level (0 = collects coins one by one)
const PICKUP_RADII: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.3, 1.7, 2.1, 2.6, 3.1, 3.7]
# Cost to go from level N to N+1 (index N-1); last entry unused
const UPGRADE_COSTS: Array[int] = [150, 260, 400, 580, 800, 1000, 1300, 1650, 2050, 2500, 3000, 0]

enum State { IDLE, PATROL, CHASE_COIN, COLLECTING }

signal speed_upgraded(crab: PetCrab, new_level: int)
signal coin_collected_by_crab(crab: PetCrab, coin: Node3D)

@export var tank_bounds: AABB = AABB(Vector3(-6.7, 0.50, -3.9), Vector3(13.4, 4.75, 7.8))

var state: State = State.PATROL
var speed_level: int = 1
var coins_collected_count: int = 0
var is_selected: bool = false

var target_position: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var state_timer: float = 0.0
var collect_anim_timer: float = 0.0

var _visual_root: Node3D = null
var _anim_player: AnimationPlayer = null
var _hit_area: Area3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D = null
var _outline_mat: ShaderMaterial = null
var _flash_timer: float = 0.0
var _area_scan_timer: float = 0.0


func _ready() -> void:
	add_to_group("crab")
	add_to_group("selectable_fish")
	add_to_group("selectable_entities")
	position.y = FLOOR_Y

	_flash_mat = CombatVFXScript.create_flash_material()
	_outline_mat = CombatVFXScript.create_selection_outline_material(Color(1.0, 0.65, 0.32, 0.96), 3.4)

	_setup_visual_and_collision()
	_enter_patrol_state()


func set_selected(selected: bool) -> void:
	is_selected = selected
	if _visual_root:
		CombatVFXScript.set_selection_outline(_visual_root, is_selected, _outline_mat)


func _setup_visual_and_collision() -> void:
	_visual_root = CRAB_MODEL.instantiate()
	# Rotate 180 deg around Y so claws/eyes (+Z in GLB) align with -Z (Godot forward)
	_visual_root.rotation = BASE_VISUAL_ROT
	_visual_root.scale = Vector3.ONE * VISUAL_SCALE
	_visual_root.position = BASE_VISUAL_POS
	add_child(_visual_root)

	_mesh_instances = CombatVFXScript.collect_mesh_instances(_visual_root)
	if is_selected:
		CombatVFXScript.set_selection_outline(_visual_root, true, _outline_mat)

	var found := _visual_root.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		_anim_player = found[0] as AnimationPlayer
		for anim_name in ["Idle", "Walk"]:
			if _anim_player.has_animation(anim_name):
				_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		if _anim_player.has_animation("Collect"):
			_anim_player.get_animation("Collect").loop_mode = Animation.LOOP_NONE

	_hit_area = Area3D.new()
	_hit_area.name = "CrabClickArea"
	_hit_area.collision_layer = 2
	_hit_area.collision_mask = 0
	_hit_area.input_ray_pickable = true
	add_child(_hit_area)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.72
	col.shape = shape
	col.position = Vector3(0.0, 0.32, 0.0)
	_hit_area.add_child(col)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	global_position.y = FLOOR_Y
	_update_flash(delta)
	_update_area_pickup(delta)

	if state == State.COLLECTING:
		collect_anim_timer -= delta
		if collect_anim_timer <= 0.0:
			var next_coin := _find_best_target_coin()
			if next_coin != null:
				state = State.CHASE_COIN
				play_anim("Walk", 0.15)
			else:
				_enter_patrol_state()
		return

	var target_coin := _find_best_target_coin()
	if target_coin != null:
		if state != State.CHASE_COIN:
			state = State.CHASE_COIN
			play_anim("Walk", 0.15)
		_process_chase_coin(target_coin, delta)
	else:
		if state == State.CHASE_COIN:
			_enter_patrol_state()
		state_timer -= delta
		match state:
			State.PATROL:
				_process_patrol(delta)
			State.IDLE:
				_process_idle(delta)

	_keep_on_floor_bounds()


func _update_flash(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		var alpha := clampf(_flash_timer / 0.14, 0.0, 1.0) * 0.65
		CombatVFXScript.update_flash_overlay(_mesh_instances, _flash_mat, alpha, Color(1.8, 1.5, 1.1, 1.0))
	else:
		CombatVFXScript.update_flash_overlay(_mesh_instances, _flash_mat, 0.0)


func get_pickup_radius() -> float:
	return PICKUP_RADII[clampi(speed_level - 1, 0, PICKUP_RADII.size() - 1)]


func _update_area_pickup(delta: float) -> void:
	var radius := get_pickup_radius()
	if radius <= 0.0 or get_tree() == null:
		return
	_area_scan_timer -= delta
	if _area_scan_timer > 0.0:
		return
	_area_scan_timer = 0.1
	var pulled := 0
	var max_h := FLOOR_Y + 1.2 + radius * 0.6
	for node in get_tree().get_nodes_in_group("coins"):
		if not is_instance_valid(node) or bool(node.get("is_collected")) or node.get("attract_target") != null:
			continue
		var c := node as Node3D
		if c.global_position.y > max_h:
			continue
		var horiz := Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length()
		if horiz <= radius:
			c.call("attract_to", self)
			coins_collected_count += 1
			pulled += 1
	if pulled > 0:
		_flash_timer = 0.10
		if _anim_player and state != State.CHASE_COIN:
			play_anim("Collect", 0.1)


func _find_best_target_coin() -> Node3D:
	if get_tree() == null:
		return null
	var best_coin: Node3D = null
	var best_score := INF

	for node in get_tree().get_nodes_in_group("coins"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if bool(node.get("is_collected")) or node.get("attract_target") != null:
			continue
		var c := node as Node3D
		var horiz_dist := Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length()
		var height_above_floor := maxf(0.0, c.global_position.y - FLOOR_Y)
		# Prioritize coins that are horizontally close and lower in the water column
		var score := horiz_dist + height_above_floor * 0.75
		if score < best_score:
			best_score = score
			best_coin = c

	return best_coin


func _process_chase_coin(coin: Node3D, delta: float) -> void:
	var coin_pos := coin.global_position
	var floor_target := Vector3(coin_pos.x, FLOOR_Y, coin_pos.z)
	var to_target := floor_target - global_position
	to_target.y = 0.0
	var horiz_dist := to_target.length()

	# Gently pull low falling coins toward the crab's claws when close
	if horiz_dist < 0.85 and coin_pos.y <= FLOOR_Y + 1.45:
		coin.global_position = coin.global_position.lerp(
			global_position + Vector3(0.0, 0.35, 0.0),
			clampf(delta * 4.5, 0.0, 1.0)
		)

	# Collect coin when within horizontal reach and low enough for the crab to grab
	if horiz_dist <= 0.72 and coin.global_position.y <= FLOOR_Y + 1.35:
		if coin.has_method("collect"):
			coin.call("collect")
		coins_collected_count += 1
		state = State.COLLECTING
		collect_anim_timer = 0.26
		current_speed = 0.0
		if _anim_player:
			_anim_player.speed_scale = 1.45
		play_anim("Collect", 0.1)
		coin_collected_by_crab.emit(self, coin)
		return

	var max_spd := get_chase_speed()
	if horiz_dist > 0.12:
		var dir := to_target / maxf(horiz_dist, 0.001)
		current_speed = lerpf(current_speed, max_spd, delta * 6.0)
		_steer_on_floor(dir, delta, 7.5)
		global_position += dir * minf(horiz_dist, current_speed * delta)
		if _anim_player:
			_anim_player.speed_scale = clampf(current_speed / 1.6, 0.45, 2.8)
	else:
		# Waiting directly underneath a falling coin
		current_speed = 0.0
		play_anim("Idle", 0.2)
		if _anim_player:
			_anim_player.speed_scale = 1.1


func _process_patrol(delta: float) -> void:
	var to_target := target_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 0.45 or state_timer <= 0.0:
		if randf() < 0.42:
			_enter_idle_state()
		else:
			_pick_new_floor_target()
			state_timer = randf_range(3.0, 6.0)
		return

	var dir := to_target / maxf(dist, 0.001)
	var max_spd := get_walk_speed()
	current_speed = lerpf(current_speed, max_spd, delta * 4.5)
	_steer_on_floor(dir, delta, 5.2)
	global_position += dir * current_speed * delta

	if _anim_player:
		_anim_player.speed_scale = clampf(current_speed / 1.6, 0.40, 2.4)


func _process_idle(delta: float) -> void:
	current_speed = lerpf(current_speed, 0.0, delta * 6.0)
	if state_timer <= 0.0:
		_enter_patrol_state()


func _steer_on_floor(desired_dir: Vector3, delta: float, turn_rate: float) -> void:
	var flat_len := Vector2(desired_dir.x, desired_dir.z).length()
	if flat_len > 0.001:
		var target_yaw := atan2(-desired_dir.x, -desired_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * turn_rate, 0.0, 1.0))
	rotation.x = 0.0
	rotation.z = 0.0


func _keep_on_floor_bounds() -> void:
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size
	global_position.x = clampf(global_position.x, min_p.x + 0.4, max_p.x - 0.4)
	global_position.z = clampf(global_position.z, min_p.z + 0.4, max_p.z - 0.4)
	global_position.y = FLOOR_Y


func _enter_patrol_state() -> void:
	state = State.PATROL
	state_timer = randf_range(3.0, 6.2)
	_pick_new_floor_target()
	play_anim("Walk", 0.2)


func _enter_idle_state() -> void:
	state = State.IDLE
	state_timer = randf_range(1.2, 2.5)
	if _anim_player:
		_anim_player.speed_scale = 1.0
	play_anim("Idle", 0.25)


func _pick_new_floor_target() -> void:
	var min_p := tank_bounds.position
	var max_p := tank_bounds.position + tank_bounds.size
	for _i in range(5):
		var candidate := Vector3(
			randf_range(min_p.x + 0.6, max_p.x - 0.6),
			FLOOR_Y,
			randf_range(min_p.z + 0.6, max_p.z - 0.6)
		)
		if candidate.distance_to(global_position) > 1.6:
			target_position = candidate
			return
	target_position = Vector3(0.0, FLOOR_Y, 0.0)


func get_walk_speed() -> float:
	var idx := clampi(speed_level - 1, 0, WALK_SPEEDS.size() - 1)
	return WALK_SPEEDS[idx]


func get_chase_speed() -> float:
	var idx := clampi(speed_level - 1, 0, CHASE_SPEEDS.size() - 1)
	return CHASE_SPEEDS[idx]


func can_upgrade_speed() -> bool:
	return speed_level < MAX_SPEED_LEVEL


func get_upgrade_cost() -> int:
	if not can_upgrade_speed():
		return 0
	var idx := clampi(speed_level - 1, 0, UPGRADE_COSTS.size() - 1)
	return Balance.price(UPGRADE_COSTS[idx])


func upgrade_speed() -> bool:
	if not can_upgrade_speed():
		return false
	speed_level += 1
	_flash_timer = 0.16
	var txt := "Crab Lv.%d" % speed_level
	if get_pickup_radius() > 0.0:
		txt = "Crab Lv.%d - wider pickup" % speed_level if speed_level > AREA_START_LEVEL else "Crab Lv.%d - area pickup" % speed_level
	CombatVFXScript.spawn_growth_effect(
		get_tree(),
		global_position + Vector3(0.0, 0.4, 0.0),
		txt,
		Color(1.0, 0.75, 0.40, 1.0)
	)
	speed_upgraded.emit(self, speed_level)
	return true


func play_anim(anim_name: String, blend: float = 0.2) -> void:
	if _anim_player and _anim_player.has_animation(anim_name):
		if _anim_player.current_animation != anim_name or anim_name == "Collect":
			_anim_player.play(anim_name, blend)


func get_display_label() -> String:
	var act := "Chasing a coin" if state == State.CHASE_COIN else "Patrolling the floor"
	var pickup := "Collects coins one by one"
	if get_pickup_radius() > 0.0:
		pickup = "Pulls in coins within %.1fm" % get_pickup_radius()
	return "Pet Crab | Level %d of %d | %s | Coins collected: %d | %s" % [
		speed_level,
		MAX_SPEED_LEVEL,
		pickup,
		coins_collected_count,
		act
	]


func get_next_upgrade_text() -> String:
	if not can_upgrade_speed():
		return "Max level"
	var next := speed_level + 1
	if next < AREA_START_LEVEL:
		return "Faster (Lv.%d)" % next
	if next == AREA_START_LEVEL:
		return "Area pickup (Lv.%d)" % next
	return "Wider pickup (Lv.%d)" % next


func get_focus_distance() -> float:
	return 3.4
