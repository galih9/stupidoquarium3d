extends Node3D

## Orbit, selection, and tile-grid Decorating Mode camera controller.
## Uses an outline shader for any selected entity (never uses a white circle indicator).
## Supports 360-degree camera orbit in normal play, and automatic top-down tile-grid placement
## for Food Producers (Duckweed/Hyacinth) and Tank Decorations when in Decorating Mode.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const CombatVFXScript = preload("res://scripts/combat_vfx.gd")

signal focus_changed(entity: Node3D)
signal entity_moved(entity: Node3D)

const WATER_SURFACE_Y: float = 6.37
const FLOOR_Y: float = 0.50

const GRID_COLS: int = 6
const GRID_ROWS: int = 4
const TILE_SIZE: float = 1.85

const TOPDOWN_YAW: float = 0.0
const TOPDOWN_PITCH: float = -1.52
const TOPDOWN_DISTANCE: float = 13.8

const DECOR_LAYER_FLOOR: int = 0
const DECOR_LAYER_SURFACE: int = 1

@export var default_pivot: Vector3 = Vector3(0.0, 3.3, 0.0)
@export var default_distance: float = 15.5
@export var min_distance: float = 1.6
@export var max_distance: float = 26.0
@export var mouse_sensitivity: float = 0.0055
@export var key_orbit_speed: float = 1.6
@export var zoom_step: float = 1.25
@export var orbit_smoothing: float = 12.0
@export var follow_smoothing: float = 10.0

var focused_fish: Node3D = null
var can_decorate_tank: bool = true
var is_decorating_mode: bool = false
var decor_layer: int = DECOR_LAYER_SURFACE
var is_move_mode: bool = false

var target_yaw: float = 0.35
var target_pitch: float = -0.28
var current_yaw: float = 0.35
var current_pitch: float = -0.28
var target_distance: float = 15.5
var current_distance: float = 15.5

var _saved_yaw: float = 0.35
var _saved_pitch: float = -0.28
var _saved_distance: float = 15.5

var _is_dragging_orbit: bool = false
var _drag_button: int = -1
var _drag_distance: float = 0.0
var _dragging_movable: Node3D = null
var _camera: Camera3D = null

var _grid_root: Node3D = null
var _grid_mesh: ImmediateMesh = null
var _grid_instance: MeshInstance3D = null
var _grid_mat: StandardMaterial3D = null
var _hovered_cell: Vector2i = Vector2i(-1, -1)
var _hovered_cell_valid: bool = true

var _shake_timer: float = 0.0
var _shake_duration: float = 0.22
var _shake_intensity: float = 0.0
var _shake_phase: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO
var _shake_roll: float = 0.0


static func grid_to_world(cell: Vector2i, y_level: float) -> Vector3:
	var c := clampi(cell.x, 0, GRID_COLS - 1)
	var r := clampi(cell.y, 0, GRID_ROWS - 1)
	var x := (float(c) - float(GRID_COLS - 1) * 0.5) * TILE_SIZE
	var z := (float(r) - float(GRID_ROWS - 1) * 0.5) * TILE_SIZE
	return Vector3(x, y_level, z)


static func world_to_grid(world_pos: Vector3) -> Vector2i:
	var col := int(roundf(world_pos.x / TILE_SIZE + float(GRID_COLS - 1) * 0.5))
	var row := int(roundf(world_pos.z / TILE_SIZE + float(GRID_ROWS - 1) * 0.5))
	return Vector2i(clampi(col, 0, GRID_COLS - 1), clampi(row, 0, GRID_ROWS - 1))


static func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_COLS and cell.y >= 0 and cell.y < GRID_ROWS


func _ready() -> void:
	global_position = default_pivot
	target_distance = default_distance
	current_distance = default_distance
	current_yaw = target_yaw
	current_pitch = target_pitch

	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.fov = 50.0
		_camera.near = 0.05
		_camera.far = 120.0
		add_child(_camera)

	_setup_grid_visuals()
	_update_camera_transform()


func _exit_tree() -> void:
	if _grid_root and is_instance_valid(_grid_root):
		_grid_root.queue_free()


func _setup_grid_visuals() -> void:
	_grid_root = Node3D.new()
	_grid_root.name = "DecoratingGridOverlay"
	_grid_root.top_level = true
	_grid_root.visible = false
	add_child(_grid_root)

	_grid_mat = StandardMaterial3D.new()
	_grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_grid_mat.vertex_color_use_as_albedo = true
	_grid_mat.no_depth_test = true

	_grid_mesh = ImmediateMesh.new()
	_grid_instance = MeshInstance3D.new()
	_grid_instance.name = "GridLinesMesh"
	_grid_instance.mesh = _grid_mesh
	_grid_instance.material_override = _grid_mat
	_grid_root.add_child(_grid_instance)


func set_can_decorate(allowed: bool) -> void:
	can_decorate_tank = allowed
	if not can_decorate_tank:
		if is_decorating_mode:
			set_decorating_mode(false)
		if is_instance_valid(_dragging_movable):
			_dragging_movable = null
		if is_instance_valid(focused_fish) and focused_fish.is_in_group("decorations"):
			is_move_mode = false
			clear_focus()


func _ensure_layer_selection() -> void:
	if not is_decorating_mode or get_tree() == null:
		return
	if is_instance_valid(focused_fish):
		if decor_layer == DECOR_LAYER_SURFACE and focused_fish.is_in_group("movable_surface"):
			return
		if decor_layer == DECOR_LAYER_FLOOR and focused_fish.is_in_group("movable_floor"):
			return
		clear_focus()
	var group_name := "duckweed" if decor_layer == DECOR_LAYER_SURFACE else "decorations"
	var nodes := get_tree().get_nodes_in_group(group_name)
	for n in nodes:
		if n is Node3D and is_instance_valid(n):
			focus_on_fish(n as Node3D)
			return


func set_decor_layer(new_layer: int) -> void:
	var clamped_layer := DECOR_LAYER_SURFACE if new_layer == DECOR_LAYER_SURFACE else DECOR_LAYER_FLOOR
	decor_layer = clamped_layer
	_dragging_movable = null
	is_move_mode = false
	_hovered_cell = Vector2i(-1, -1)
	_hovered_cell_valid = true

	_ensure_layer_selection()
	_rebuild_grid_visuals()
	focus_changed.emit(focused_fish)


func set_decorating_mode(active: bool) -> void:
	var next_mode := active and can_decorate_tank
	if is_decorating_mode == next_mode:
		return

	is_decorating_mode = next_mode
	_is_dragging_orbit = false
	_dragging_movable = null
	_hovered_cell = Vector2i(-1, -1)

	if is_decorating_mode:
		_saved_yaw = target_yaw
		_saved_pitch = target_pitch
		_saved_distance = target_distance
		target_yaw = TOPDOWN_YAW
		target_pitch = TOPDOWN_PITCH
		target_distance = TOPDOWN_DISTANCE
		_ensure_layer_selection()
		if _grid_root:
			_grid_root.visible = true
		_rebuild_grid_visuals()
	else:
		is_move_mode = false
		target_yaw = _saved_yaw
		target_pitch = _saved_pitch
		target_distance = _saved_distance
		if _grid_root:
			_grid_root.visible = false
	focus_changed.emit(focused_fish)


func start_move_mode_for_selected() -> void:
	if not is_instance_valid(focused_fish):
		return
	if not can_decorate_tank:
		return
	if focused_fish.is_in_group("movable_surface") or focused_fish.is_in_group("movable_floor"):
		if focused_fish.is_in_group("movable_surface"):
			decor_layer = DECOR_LAYER_SURFACE
		else:
			decor_layer = DECOR_LAYER_FLOOR
		if not is_decorating_mode:
			set_decorating_mode(true)
		is_move_mode = not is_move_mode
		if is_move_mode:
			_hovered_cell = focused_fish.get("grid_cell") if focused_fish.get("grid_cell") != null else world_to_grid(focused_fish.global_position)
			_hovered_cell_valid = true
		_rebuild_grid_visuals()
		focus_changed.emit(focused_fish)


func is_cell_occupied(cell: Vector2i, group_name: String, ignore_entity: Node3D = null) -> bool:
	if get_tree() == null:
		return false
	for node in get_tree().get_nodes_in_group(group_name):
		if node == ignore_entity or not (node is Node3D) or not is_instance_valid(node):
			continue
		var n_cell: Vector2i = node.get("grid_cell") if node.get("grid_cell") != null else world_to_grid((node as Node3D).global_position)
		if n_cell == cell:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			var min_d := 9.0 if is_decorating_mode else min_distance
			target_distance = clampf(target_distance - zoom_step, min_d, max_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			var max_d := 19.0 if is_decorating_mode else max_distance
			target_distance = clampf(target_distance + zoom_step, min_distance, max_d)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_distance = 0.0
				# 1. If tile move mode is active in Decorating Mode, clicking LMB places the object on the tile
				if is_decorating_mode and is_move_mode and is_instance_valid(focused_fish):
					_move_entity_to_screen_pos(focused_fish, mb.position)
					is_move_mode = false
					_rebuild_grid_visuals()
					entity_moved.emit(focused_fish)
					focus_changed.emit(focused_fish)
					return

				# 2. Immediate coin collection or Kingfisher click-defense on click/press (only outside Decorating Mode)
				if not is_decorating_mode:
					var coin := _pick_coin_at(mb.position)
					if coin != null and coin.has_method("collect"):
						coin.call("collect", true)
						return
					var threat := _pick_threat_at(mb.position)
					if threat != null and threat.has_method("apply_player_click"):
						threat.call("apply_player_click")
						return

				# 3. Check if pressing on a Food Producer or Decoration (strictly filtered by decor_layer in Decorating Mode)
				var movable := _pick_movable_at(mb.position)
				if movable != null:
					focus_on_fish(movable)
					if is_decorating_mode:
						# In Decorating Mode, dragging moves the object from tile to tile on the active layer grid
						_dragging_movable = movable
						_hovered_cell = movable.get("grid_cell") if movable.get("grid_cell") != null else world_to_grid(movable.global_position)
						_hovered_cell_valid = true
						_rebuild_grid_visuals()
					_is_dragging_orbit = false
					return

				# 4. In Decorating Mode, clicking an empty tile moves the currently selected item on the active layer to that tile!
				if is_decorating_mode:
					if is_instance_valid(focused_fish):
						var matches_layer := (decor_layer == DECOR_LAYER_SURFACE and focused_fish.is_in_group("movable_surface")) or (decor_layer == DECOR_LAYER_FLOOR and focused_fish.is_in_group("movable_floor"))
						if matches_layer:
							_move_entity_to_screen_pos(focused_fish, mb.position)
							_rebuild_grid_visuals()
							entity_moved.emit(focused_fish)
							focus_changed.emit(focused_fish)
					return

				# 5. Otherwise start normal orbit drag or click check
				_is_dragging_orbit = true
				_drag_button = MOUSE_BUTTON_LEFT
			else:
				if _dragging_movable != null:
					var moved_obj := _dragging_movable
					_dragging_movable = null
					_rebuild_grid_visuals()
					if is_instance_valid(moved_obj):
						entity_moved.emit(moved_obj)
						focus_changed.emit(moved_obj)
					return
				if _is_dragging_orbit and _drag_button == MOUSE_BUTTON_LEFT:
					_is_dragging_orbit = false
					if _drag_distance < 7.0:
						_handle_click(mb.position)

		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				if is_decorating_mode:
					if mb.button_index == MOUSE_BUTTON_RIGHT:
						is_move_mode = false
						clear_focus()
						_rebuild_grid_visuals()
					return
				_is_dragging_orbit = true
				_drag_button = mb.button_index
				_drag_distance = 0.0
			else:
				if _is_dragging_orbit and mb.button_index == _drag_button:
					_is_dragging_orbit = false
					if _drag_distance < 7.0 and mb.button_index == MOUSE_BUTTON_RIGHT:
						is_move_mode = false
						clear_focus()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if is_decorating_mode:
			if is_move_mode and is_instance_valid(focused_fish):
				_move_entity_to_screen_pos(focused_fish, mm.position)
				return
			if is_instance_valid(_dragging_movable):
				_drag_distance += mm.relative.length()
				_move_entity_to_screen_pos(_dragging_movable, mm.position)
				return
			_update_hover_cell_from_screen(mm.position)
			return

		if _is_dragging_orbit:
			_drag_distance += mm.relative.length()
			target_yaw -= mm.relative.x * mouse_sensitivity
			target_pitch = clampf(target_pitch - mm.relative.y * mouse_sensitivity, -1.35, 1.35)

	elif event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode in [KEY_SPACE, KEY_BACKSPACE]:
			is_move_mode = false
			clear_focus()
			_rebuild_grid_visuals()
		elif ke.keycode == KEY_R and is_instance_valid(focused_fish):
			if focused_fish.has_method("rotate_step"):
				focused_fish.call("rotate_step")
			else:
				focused_fish.rotation.y = wrapf(focused_fish.rotation.y + PI * 0.5, 0.0, TAU)
		elif ke.keycode == KEY_ESCAPE and focused_fish != null and not is_decorating_mode:
			is_move_mode = false
			clear_focus()
			_rebuild_grid_visuals()
			get_viewport().set_input_as_handled()


func trigger_shake(intensity: float = 0.25, duration: float = 0.22) -> void:
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_duration = maxf(0.05, duration)
	_shake_timer = maxf(_shake_timer, duration)


func _process(delta: float) -> void:
	if not is_decorating_mode:
		_handle_keyboard_orbit(delta)
	else:
		target_yaw = TOPDOWN_YAW
		target_pitch = TOPDOWN_PITCH

	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		_shake_phase += delta * 58.0
		var decay := clampf(_shake_timer / maxf(_shake_duration, 0.05), 0.0, 1.0)
		var amp := _shake_intensity * decay * decay
		_shake_offset = Vector3(
			sin(_shake_phase * 1.13) * amp,
			cos(_shake_phase * 1.47) * amp * 0.85,
			sin(_shake_phase * 0.89) * amp * 0.35
		)
		_shake_roll = sin(_shake_phase * 1.31) * amp * 0.065
		if _shake_timer <= 0.0:
			_shake_intensity = 0.0
			_shake_offset = Vector3.ZERO
			_shake_roll = 0.0
	else:
		_shake_offset = Vector3.ZERO
		_shake_roll = 0.0

	var rot_weight := 1.0 - exp(-orbit_smoothing * delta)
	current_yaw = lerp_angle(current_yaw, target_yaw, rot_weight)
	current_pitch = lerpf(current_pitch, target_pitch, rot_weight)
	current_distance = lerpf(current_distance, target_distance, rot_weight)

	var desired_pivot := default_pivot
	if is_instance_valid(focused_fish):
		if not is_decorating_mode and not focused_fish.is_in_group("movable_surface") and not focused_fish.is_in_group("movable_floor"):
			desired_pivot = focused_fish.global_position
	else:
		if focused_fish != null:
			focused_fish = null
			is_move_mode = false
			focus_changed.emit(null)

	var follow_weight := 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(desired_pivot, follow_weight)

	_update_camera_transform()


func _handle_keyboard_orbit(delta: float) -> void:
	var yaw_input := 0.0
	var pitch_input := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		yaw_input -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		yaw_input += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		pitch_input -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		pitch_input += 1.0

	if yaw_input != 0.0:
		target_yaw += yaw_input * key_orbit_speed * delta
	if pitch_input != 0.0:
		target_pitch = clampf(target_pitch + pitch_input * key_orbit_speed * 0.75 * delta, -1.35, 1.35)


func _update_camera_transform() -> void:
	rotation = Vector3(current_pitch, current_yaw, 0.0)
	if _camera:
		_camera.position = Vector3(0.0, 0.0, current_distance) + _shake_offset
		_camera.rotation = Vector3(0.0, 0.0, _shake_roll)


func _handle_click(screen_pos: Vector2) -> void:
	if not is_decorating_mode:
		var coin: Node3D = _pick_coin_at(screen_pos)
		if coin != null and coin.has_method("collect"):
			coin.call("collect", true)
			return

	var movable: Node3D = _pick_movable_at(screen_pos)
	if movable != null:
		focus_on_fish(movable)
		return

	if not is_decorating_mode:
		var picked: Node3D = _pick_fish_at(screen_pos)
		if picked != null:
			focus_on_fish(picked)
			return
		if focused_fish != null:
			clear_focus()


func _update_hover_cell_from_screen(screen_pos: Vector2) -> void:
	if _camera == null:
		return
	var active_y := WATER_SURFACE_Y if decor_layer == DECOR_LAYER_SURFACE else FLOOR_Y
	var group_name := "duckweed" if decor_layer == DECOR_LAYER_SURFACE else "decorations"
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)
	var hit_pt: Variant = Plane(Vector3.UP, active_y).intersects_ray(ray_origin, ray_dir)
	if hit_pt is Vector3:
		var new_cell := world_to_grid(hit_pt as Vector3)
		var valid := not is_cell_occupied(new_cell, group_name, focused_fish)
		if new_cell != _hovered_cell or valid != _hovered_cell_valid:
			_hovered_cell = new_cell
			_hovered_cell_valid = valid
			_rebuild_grid_visuals()


func _move_entity_to_screen_pos(entity: Node3D, screen_pos: Vector2) -> void:
	if _camera == null or not is_instance_valid(entity) or not is_decorating_mode:
		return
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	if decor_layer == DECOR_LAYER_SURFACE and entity.is_in_group("movable_surface"):
		var surface_plane := Plane(Vector3.UP, WATER_SURFACE_Y)
		var hit_pt: Variant = surface_plane.intersects_ray(ray_origin, ray_dir)
		if hit_pt is Vector3:
			var cell := world_to_grid(hit_pt as Vector3)
			var occupied := is_cell_occupied(cell, "duckweed", entity)
			_hovered_cell = cell
			_hovered_cell_valid = not occupied
			if not occupied:
				var snapped := grid_to_world(cell, WATER_SURFACE_Y)
				if entity.has_method("set_grid_cell"):
					entity.call("set_grid_cell", cell, snapped)
				elif entity.has_method("set_surface_position"):
					entity.call("set_surface_position", snapped)
				else:
					entity.global_position = snapped
			_rebuild_grid_visuals()

	elif decor_layer == DECOR_LAYER_FLOOR and entity.is_in_group("movable_floor") and can_decorate_tank:
		var floor_plane := Plane(Vector3.UP, FLOOR_Y)
		var hit_pt: Variant = floor_plane.intersects_ray(ray_origin, ray_dir)
		if hit_pt is Vector3:
			var cell := world_to_grid(hit_pt as Vector3)
			var occupied := is_cell_occupied(cell, "decorations", entity)
			_hovered_cell = cell
			_hovered_cell_valid = not occupied
			if not occupied:
				var snapped := grid_to_world(cell, FLOOR_Y)
				if entity.has_method("set_grid_cell"):
					entity.call("set_grid_cell", cell, snapped)
				elif entity.has_method("set_floor_position"):
					entity.call("set_floor_position", snapped)
				else:
					entity.global_position = snapped
			_rebuild_grid_visuals()


func _rebuild_grid_visuals() -> void:
	if _grid_mesh == null:
		return
	_grid_mesh.clear_surfaces()
	if not is_decorating_mode:
		return

	# Strictly use decor_layer (never switches based on selection!)
	var active_surface := (decor_layer == DECOR_LAYER_SURFACE)
	var grid_y := (WATER_SURFACE_Y + 0.02) if active_surface else (FLOOR_Y + 0.03)
	var line_col := Color(0.28, 0.98, 0.62, 0.62) if active_surface else Color(0.98, 0.84, 0.36, 0.62)
	var group_name := "duckweed" if active_surface else "decorations"

	var half_w := float(GRID_COLS) * TILE_SIZE * 0.5
	var half_d := float(GRID_ROWS) * TILE_SIZE * 0.5

	_grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for c in range(GRID_COLS + 1):
		var x := -half_w + float(c) * TILE_SIZE
		_grid_mesh.surface_set_color(line_col)
		_grid_mesh.surface_add_vertex(Vector3(x, grid_y, -half_d))
		_grid_mesh.surface_set_color(line_col)
		_grid_mesh.surface_add_vertex(Vector3(x, grid_y, half_d))

	for r in range(GRID_ROWS + 1):
		var z := -half_d + float(r) * TILE_SIZE
		_grid_mesh.surface_set_color(line_col)
		_grid_mesh.surface_add_vertex(Vector3(-half_w, grid_y, z))
		_grid_mesh.surface_set_color(line_col)
		_grid_mesh.surface_add_vertex(Vector3(half_w, grid_y, z))

	# Draw subtle frames around all occupied tiles on the active layer
	if get_tree() != null:
		var occ_col := Color(0.45, 1.0, 0.72, 0.45) if active_surface else Color(1.0, 0.88, 0.48, 0.45)
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			var n_cell: Variant = node.get("grid_cell")
			if n_cell is Vector2i and is_valid_cell(n_cell):
				_draw_cell_box(n_cell, grid_y + 0.01, TILE_SIZE * 0.42, occ_col)

	# Draw bright frame around selected entity's cell
	if is_instance_valid(focused_fish) and focused_fish.get("grid_cell") is Vector2i:
		var sel_cell: Vector2i = focused_fish.get("grid_cell")
		var sel_col := Color(0.45, 1.0, 0.95, 0.98) if active_surface else Color(1.0, 0.95, 0.55, 0.98)
		_draw_cell_box(sel_cell, grid_y + 0.025, TILE_SIZE * 0.45, sel_col)

	# Draw highlighted tile frame around hovered cell
	if is_valid_cell(_hovered_cell):
		var h_col := Color(0.35, 1.0, 0.55, 0.96) if _hovered_cell_valid else Color(1.0, 0.35, 0.32, 0.96)
		_draw_cell_box(_hovered_cell, grid_y + 0.03, TILE_SIZE * 0.47, h_col)

	_grid_mesh.surface_end()


func _draw_cell_box(cell: Vector2i, y_pos: float, hs: float, col: Color) -> void:
	var center := grid_to_world(cell, y_pos)
	var p0 := Vector3(center.x - hs, center.y, center.z - hs)
	var p1 := Vector3(center.x + hs, center.y, center.z - hs)
	var p2 := Vector3(center.x + hs, center.y, center.z + hs)
	var p3 := Vector3(center.x - hs, center.y, center.z + hs)
	for seg in [[p0, p1], [p1, p2], [p2, p3], [p3, p0]]:
		_grid_mesh.surface_set_color(col)
		_grid_mesh.surface_add_vertex(seg[0])
		_grid_mesh.surface_set_color(col)
		_grid_mesh.surface_add_vertex(seg[1])


func _pick_movable_at(screen_pos: Vector2) -> Node3D:
	if _camera == null:
		return null

	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	# In Decorating Mode, strictly isolate picking to the active layer (Surface OR Floor, never both!)
	var check_surface := true
	var check_floor := can_decorate_tank
	if is_decorating_mode:
		check_surface = (decor_layer == DECOR_LAYER_SURFACE)
		check_floor = (decor_layer == DECOR_LAYER_FLOOR) and can_decorate_tank

	var space_state := get_world_3d().direct_space_state
	var mask := (8 if check_surface else 0) | (16 if check_floor else 0)
	if mask != 0:
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 60.0, mask)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty() and hit.has("collider"):
			var collider := hit["collider"] as Node
			if collider and collider.get_parent() is Node3D:
				var parent := collider.get_parent() as Node3D
				if check_surface and parent.is_in_group("movable_surface"):
					return parent
				if check_floor and parent.is_in_group("movable_floor"):
					return parent

	# Deterministic ray-plane grid tile check for the active layer
	if check_surface:
		var surf_hit: Variant = Plane(Vector3.UP, WATER_SURFACE_Y).intersects_ray(ray_origin, ray_dir)
		if surf_hit is Vector3:
			var pt := surf_hit as Vector3
			for node in get_tree().get_nodes_in_group("duckweed"):
				if not (node is Node3D) or not is_instance_valid(node):
					continue
				var tile := node as Node3D
				if absf(pt.x - tile.global_position.x) <= TILE_SIZE * 0.48 and absf(pt.z - tile.global_position.z) <= TILE_SIZE * 0.48:
					return tile

	if check_floor:
		var floor_hit: Variant = Plane(Vector3.UP, FLOOR_Y).intersects_ray(ray_origin, ray_dir)
		if floor_hit is Vector3:
			var pt := floor_hit as Vector3
			for node in get_tree().get_nodes_in_group("decorations"):
				if not (node is Node3D) or not is_instance_valid(node):
					continue
				var decor := node as Node3D
				if absf(pt.x - decor.global_position.x) <= TILE_SIZE * 0.48 and absf(pt.z - decor.global_position.z) <= TILE_SIZE * 0.48:
					return decor

	return null


func _pick_coin_at(screen_pos: Vector2) -> Node3D:
	if _camera == null:
		return null

	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 60.0, 4)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty() and hit.has("collider"):
		var collider := hit["collider"] as Node
		if collider and collider.get_parent() is Node3D and collider.get_parent().is_in_group("coins"):
			var c := collider.get_parent() as Node3D
			if not bool(c.get("is_collected")):
				return c

	var best_coin: Node3D = null
	var best_dist := 42.0
	for node in get_tree().get_nodes_in_group("coins"):
		if not (node is Node3D) or bool(node.get("is_collected")):
			continue
		var c := node as Node3D
		if _camera.is_position_behind(c.global_position):
			continue
		var c_screen := _camera.unproject_position(c.global_position)
		var d := c_screen.distance_to(screen_pos)
		if d < best_dist:
			best_dist = d
			best_coin = c
	return best_coin


func _pick_threat_at(screen_pos: Vector2) -> Node3D:
	if _camera == null or get_tree() == null:
		return null

	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 60.0, 32)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty() and hit.has("collider"):
		var collider := hit["collider"] as Node
		if collider and collider.get_parent() is Node3D and collider.get_parent().is_in_group("threat"):
			var t := collider.get_parent() as Node3D
			if t.has_method("is_attackable") and bool(t.call("is_attackable")):
				return t

	var best_threat: Node3D = null
	var best_dist := 54.0
	for node in get_tree().get_nodes_in_group("threat"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var t := node as Node3D
		if not t.has_method("is_attackable") or not bool(t.call("is_attackable")):
			continue
		if _camera.is_position_behind(t.global_position):
			continue
		var t_screen := _camera.unproject_position(t.global_position)
		var d := t_screen.distance_to(screen_pos)
		if d < best_dist:
			best_dist = d
			best_threat = t
	return best_threat


func _pick_fish_at(screen_pos: Vector2) -> Node3D:
	if _camera == null:
		return null

	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	# 1. Direct physics raycast against fish/pet/crab click areas (layer 2)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 60.0, 2)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty() and hit.has("collider"):
		var collider := hit["collider"] as Node
		if collider and collider.get_parent() is Node3D:
			var parent := collider.get_parent() as Node3D
			if parent.is_in_group("goldfish") or parent.is_in_group("selectable_fish"):
				return parent

	# 2. Screen-space proximity fallback for easy clicking on small/fast fish or crab
	var best_fish: Node3D = null
	var best_screen_dist := 38.0
	var candidates := get_tree().get_nodes_in_group("goldfish") + get_tree().get_nodes_in_group("selectable_fish")
	for node in candidates:
		if not (node is Node3D):
			continue
		var fish := node as Node3D
		if _camera.is_position_behind(fish.global_position):
			continue
		var f_screen := _camera.unproject_position(fish.global_position)
		var d := f_screen.distance_to(screen_pos)
		if d < best_screen_dist:
			best_screen_dist = d
			best_fish = fish

	return best_fish


func focus_on_fish(entity: Node3D) -> void:
	if entity == null:
		return
	if is_instance_valid(focused_fish) and focused_fish != entity:
		_apply_entity_selected(focused_fish, false)
		is_move_mode = false

	focused_fish = entity
	_apply_entity_selected(focused_fish, true)

	if not is_decorating_mode and not entity.is_in_group("movable_surface") and not entity.is_in_group("movable_floor"):
		if entity.has_method("get_focus_distance"):
			target_distance = float(entity.call("get_focus_distance"))
	if is_decorating_mode:
		_rebuild_grid_visuals()
	focus_changed.emit(focused_fish)


func clear_focus() -> void:
	if focused_fish == null:
		return
	if is_instance_valid(focused_fish):
		_apply_entity_selected(focused_fish, false)
	focused_fish = null
	is_move_mode = false
	if not is_decorating_mode:
		target_distance = default_distance
	else:
		_rebuild_grid_visuals()
	focus_changed.emit(null)


func _apply_entity_selected(entity: Node3D, selected: bool) -> void:
	if not is_instance_valid(entity):
		return
	if entity.has_method("set_selected"):
		entity.call("set_selected", selected)
	else:
		CombatVFXScript.set_selection_outline(entity, selected)
