extends Node3D
class_name TankDecoration

## Movable bottom-of-tank decoration item (Corals, Rocks, Seaweed and multi-piece sets).
## Decorations live on a fine floor grid and can cover several tiles (for example 2x3 or 4x1),
## so the tank floor can be packed efficiently. They rotate in 90 degree steps (which swaps
## the footprint), can be moved during the Peaceful phase, and give the fish Comfort:
## more expensive pieces calm fish down more (see `comfort`).
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const CombatVFXScript = preload("res://scripts/combat_vfx.gd")
const DecorSwayScript = preload("res://assets/fih/decorations/decor_sway.gd")

const FLOOR_Y: float = 0.50

# Fine floor grid used only by decorations (the surface plant grid is separate)
const FLOOR_COLS: int = 14
const FLOOR_ROWS: int = 8
const FLOOR_TILE: float = 0.95
const FIT_MARGIN: float = 0.92
const DEFAULT_MAX_HEIGHT: float = 2.4

const M_BRAIN := preload("res://assets/fih/decorations/coral_brain.glb")
const M_BRANCH := preload("res://assets/fih/decorations/coral_branch.glb")
const M_FAN := preload("res://assets/fih/decorations/coral_fan.glb")
const M_TUBE := preload("res://assets/fih/decorations/coral_tube.glb")
const M_GRASS := preload("res://assets/fih/decorations/seaweed_grass.glb")
const M_BUBBLE := preload("res://assets/fih/decorations/seaweed_bubble.glb")
const M_KELP := preload("res://assets/fih/decorations/seaweed_kelp.glb")
const M_ROCK_SMALL := preload("res://assets/fih/decorations/rock_small.glb")
const M_ROCK_FLAT := preload("res://assets/fih/decorations/rock_flat.glb")
const M_ROCK_STACK := preload("res://assets/fih/decorations/rock_stack.glb")
const M_ROCK_BIG := preload("res://assets/fih/decorations/rock_big.glb")
const M_ROCK_ARCH := preload("res://assets/fih/decorations/rock_arch.glb")

## Catalog. "foot" is the size in floor tiles (width along X, depth along Z).
## "parts" places one or more models inside the footprint: "at" is the part center and
## "fit" the area it is scaled to fill, both in tile units from the footprint corner.
## Parts without "at"/"fit" fill the whole footprint. Comfort is derived from cost.
const CATALOG: Array[Dictionary] = [
	{"id": "rock_small", "name": "Small Rock", "category": "Rock", "cost": 40, "foot": Vector2i(1, 1),
		"parts": [{"scene": M_ROCK_SMALL}]},
	{"id": "seaweed_grass", "name": "Sea Grass", "category": "Plant", "cost": 50, "foot": Vector2i(1, 1), "sway": true,
		"parts": [{"scene": M_GRASS}]},
	{"id": "rock_flat", "name": "Flat Stone", "category": "Rock", "cost": 50, "foot": Vector2i(2, 1),
		"parts": [{"scene": M_ROCK_FLAT}]},
	{"id": "rock_stack", "name": "Rock Stack", "category": "Rock", "cost": 65, "foot": Vector2i(1, 1),
		"parts": [{"scene": M_ROCK_STACK}]},
	{"id": "seaweed_bubble", "name": "Bubble Weed", "category": "Plant", "cost": 65, "foot": Vector2i(1, 1), "sway": true,
		"parts": [{"scene": M_BUBBLE}]},
	{"id": "coral_brain", "name": "Brain Coral", "category": "Coral", "cost": 65, "foot": Vector2i(2, 2),
		"parts": [{"scene": M_BRAIN}]},
	{"id": "coral_branch", "name": "Branch Coral", "category": "Coral", "cost": 75, "foot": Vector2i(1, 1),
		"parts": [{"scene": M_BRANCH}]},
	{"id": "coral_fan", "name": "Fan Coral", "category": "Coral", "cost": 75, "foot": Vector2i(2, 1),
		"parts": [{"scene": M_FAN}]},
	{"id": "seaweed_kelp", "name": "Tall Kelp", "category": "Plant", "cost": 75, "foot": Vector2i(1, 1), "sway": true,
		"parts": [{"scene": M_KELP, "max_h": 2.7}]},
	{"id": "rock_big", "name": "Boulder", "category": "Rock", "cost": 80, "foot": Vector2i(2, 2),
		"parts": [{"scene": M_ROCK_BIG}]},
	{"id": "coral_tube", "name": "Tube Coral", "category": "Coral", "cost": 85, "foot": Vector2i(2, 2),
		"parts": [{"scene": M_TUBE}]},
	{"id": "rock_arch", "name": "Rock Arch", "category": "Rock", "cost": 110, "foot": Vector2i(3, 1),
		"parts": [{"scene": M_ROCK_ARCH}]},
	{"id": "grass_row", "name": "Grass Row", "category": "Set", "cost": 140, "foot": Vector2i(4, 1), "sway": true,
		"parts": [
			{"scene": M_GRASS, "at": Vector2(0.5, 0.5), "fit": Vector2(1, 1), "yaw": 0.0},
			{"scene": M_GRASS, "at": Vector2(1.5, 0.5), "fit": Vector2(1, 1), "yaw": 70.0},
			{"scene": M_BUBBLE, "at": Vector2(2.5, 0.5), "fit": Vector2(1, 1), "yaw": 150.0},
			{"scene": M_GRASS, "at": Vector2(3.5, 0.5), "fit": Vector2(1, 1), "yaw": 220.0},
		]},
	{"id": "kelp_forest", "name": "Kelp Forest", "category": "Set", "cost": 170, "foot": Vector2i(2, 3), "sway": true,
		"parts": [
			{"scene": M_KELP, "at": Vector2(0.5, 0.5), "fit": Vector2(1, 1), "max_h": 2.9, "yaw": 0.0},
			{"scene": M_KELP, "at": Vector2(1.5, 0.9), "fit": Vector2(1, 1), "max_h": 2.4, "yaw": 90.0},
			{"scene": M_KELP, "at": Vector2(0.6, 1.6), "fit": Vector2(1, 1), "max_h": 2.2, "yaw": 200.0},
			{"scene": M_KELP, "at": Vector2(1.4, 2.4), "fit": Vector2(1, 1), "max_h": 2.8, "yaw": 300.0},
			{"scene": M_GRASS, "at": Vector2(0.5, 2.5), "fit": Vector2(1, 1), "yaw": 45.0},
		]},
	{"id": "coral_garden", "name": "Coral Garden", "category": "Set", "cost": 210, "foot": Vector2i(3, 2),
		"parts": [
			{"scene": M_BRAIN, "at": Vector2(0.75, 0.75), "fit": Vector2(1.5, 1.5), "yaw": 0.0},
			{"scene": M_TUBE, "at": Vector2(2.3, 0.6), "fit": Vector2(1.2, 1.2), "yaw": 40.0},
			{"scene": M_BRANCH, "at": Vector2(2.4, 1.5), "fit": Vector2(1, 1), "yaw": 120.0},
			{"scene": M_FAN, "at": Vector2(1.1, 1.65), "fit": Vector2(1.6, 0.6), "yaw": 0.0},
		]},
]

static var _bounds_cache: Dictionary = {}

var decor_id: String = "rock_small"
var decor_name: String = "Small Rock"
var decor_cost: int = 40
var comfort: int = 4
var grid_cell: Vector2i = Vector2i.ZERO   # anchor = lowest column/row the footprint covers
var quarter_turns: int = 0
var is_selected: bool = false

var _visual_root: Node3D = null
var _hit_area: Area3D = null
var _hit_shape: BoxShape3D = null
var _outline_mat: ShaderMaterial = null
var _base_foot: Vector2i = Vector2i.ONE
var _height: float = 1.0


# =============================================================================
# Catalog and grid helpers (static, shared with the camera and main controller)
# =============================================================================

static func get_catalog_entry(id_str: String) -> Dictionary:
	for entry in CATALOG:
		if String(entry["id"]) == id_str:
			return entry
	return CATALOG[0]


static func comfort_for_cost(cost: int) -> int:
	# The more expensive the decoration, the more it calms the fish
	return maxi(1, int(roundf(float(cost) / 10.0)))


static func footprint_label(foot: Vector2i) -> String:
	return "%dx%d" % [foot.x, foot.y]


static func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < FLOOR_COLS and cell.y >= 0 and cell.y < FLOOR_ROWS


static func cell_center(cell: Vector2i) -> Vector3:
	var x := (float(cell.x) - float(FLOOR_COLS - 1) * 0.5) * FLOOR_TILE
	var z := (float(cell.y) - float(FLOOR_ROWS - 1) * 0.5) * FLOOR_TILE
	return Vector3(x, FLOOR_Y, z)


static func world_to_cell(world_pos: Vector3) -> Vector2i:
	var col := int(floorf(world_pos.x / FLOOR_TILE + float(FLOOR_COLS) * 0.5))
	var row := int(floorf(world_pos.z / FLOOR_TILE + float(FLOOR_ROWS) * 0.5))
	return Vector2i(col, row)


static func clamp_anchor(anchor: Vector2i, size: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(anchor.x, 0, maxi(0, FLOOR_COLS - size.x)),
		clampi(anchor.y, 0, maxi(0, FLOOR_ROWS - size.y))
	)


## Anchor so that the footprint is centered on the given cell (used while dragging).
static func anchor_centered_on(cell: Vector2i, size: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	var a := Vector2i(cell.x - (size.x - 1) / 2, cell.y - (size.y - 1) / 2)
	return clamp_anchor(a, size)


static func footprint_center(anchor: Vector2i, size: Vector2i) -> Vector3:
	var a := cell_center(anchor)
	return Vector3(
		a.x + float(size.x - 1) * 0.5 * FLOOR_TILE,
		FLOOR_Y,
		a.z + float(size.y - 1) * 0.5 * FLOOR_TILE
	)


static func rect_overlaps(a_anchor: Vector2i, a_size: Vector2i, b_anchor: Vector2i, b_size: Vector2i) -> bool:
	return a_anchor.x < b_anchor.x + b_size.x and b_anchor.x < a_anchor.x + a_size.x \
		and a_anchor.y < b_anchor.y + b_size.y and b_anchor.y < a_anchor.y + a_size.y


static func is_area_free(tree: SceneTree, anchor: Vector2i, size: Vector2i, ignore: Node = null) -> bool:
	if anchor.x < 0 or anchor.y < 0 or anchor.x + size.x > FLOOR_COLS or anchor.y + size.y > FLOOR_ROWS:
		return false
	if tree == null:
		return true
	for node in tree.get_nodes_in_group("decorations"):
		if node == ignore or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if not node.has_method("get_footprint"):
			continue
		if rect_overlaps(anchor, size, node.get("grid_cell"), node.call("get_footprint")):
			return false
	return true


## Finds a free spot for a footprint, preferring the middle of the tank. Returns (-1, -1) if full.
static func find_free_anchor(tree: SceneTree, size: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var mid := Vector2(float(FLOOR_COLS) * 0.5, float(FLOOR_ROWS) * 0.5)
	for y in range(0, FLOOR_ROWS - size.y + 1):
		for x in range(0, FLOOR_COLS - size.x + 1):
			var a := Vector2i(x, y)
			if not is_area_free(tree, a, size):
				continue
			var c := Vector2(float(x) + float(size.x) * 0.5, float(y) + float(size.y) * 0.5)
			var d := c.distance_squared_to(mid)
			if d < best_d:
				best_d = d
				best = a
	return best


static func _scene_bounds(scene: PackedScene) -> AABB:
	if _bounds_cache.has(scene):
		return _bounds_cache[scene]
	var inst := scene.instantiate()
	var boxes: Array[AABB] = []
	_collect_bounds(inst, Transform3D.IDENTITY, boxes)
	inst.free()
	var result := AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	if not boxes.is_empty():
		result = boxes[0]
		for b in boxes:
			result = result.merge(b)
	_bounds_cache[scene] = result
	return result


static func _collect_bounds(n: Node, xf: Transform3D, out: Array[AABB]) -> void:
	var my := xf
	if n is Node3D:
		my = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(my * (n as MeshInstance3D).get_aabb())
	for c in n.get_children():
		_collect_bounds(c, my, out)


# =============================================================================
# Instance
# =============================================================================

func _ready() -> void:
	add_to_group("decorations")
	add_to_group("selectable_entities")
	add_to_group("movable_floor")
	_outline_mat = CombatVFXScript.create_selection_outline_material(Color(0.98, 0.86, 0.38, 0.96), 3.4)
	_build_decoration()
	_apply_grid_position()


func get_footprint() -> Vector2i:
	if quarter_turns % 2 == 1:
		return Vector2i(_base_foot.y, _base_foot.x)
	return _base_foot


func get_center() -> Vector3:
	return footprint_center(grid_cell, get_footprint())


func get_height() -> float:
	return _height


func occupies_cell(cell: Vector2i) -> bool:
	var f := get_footprint()
	return cell.x >= grid_cell.x and cell.x < grid_cell.x + f.x and cell.y >= grid_cell.y and cell.y < grid_cell.y + f.y


func _build_decoration() -> void:
	var entry := get_catalog_entry(decor_id)
	decor_name = String(entry["name"])
	decor_cost = int(entry["cost"])
	comfort = comfort_for_cost(decor_cost)
	_base_foot = entry["foot"]
	position.y = FLOOR_Y

	if _visual_root and is_instance_valid(_visual_root):
		remove_child(_visual_root)
		_visual_root.queue_free()
		_visual_root = null

	_visual_root = Node3D.new()
	_visual_root.name = "VisualHolder"
	add_child(_visual_root)

	var foot_w := float(_base_foot.x) * FLOOR_TILE
	var foot_d := float(_base_foot.y) * FLOOR_TILE
	var sway := bool(entry.get("sway", false))
	_height = 0.3
	var idx := 0
	for part in entry["parts"]:
		var scene: PackedScene = part["scene"]
		var at: Vector2 = part.get("at", Vector2(float(_base_foot.x) * 0.5, float(_base_foot.y) * 0.5))
		var fit: Vector2 = part.get("fit", Vector2(_base_foot))
		var max_h := float(part.get("max_h", DEFAULT_MAX_HEIGHT))
		var yaw := deg_to_rad(float(part.get("yaw", 0.0)))

		var b := _scene_bounds(scene)
		var fit_w := fit.x * FLOOR_TILE * FIT_MARGIN
		var fit_d := fit.y * FLOOR_TILE * FIT_MARGIN
		var s := minf(fit_w / maxf(b.size.x, 0.01), fit_d / maxf(b.size.z, 0.01))
		s = minf(s, max_h / maxf(b.size.y, 0.01))

		var holder := Node3D.new()
		holder.name = "Part%d" % idx
		holder.position = Vector3(at.x * FLOOR_TILE - foot_w * 0.5, 0.0, at.y * FLOOR_TILE - foot_d * 0.5)
		holder.rotation.y = yaw
		if sway and DecorSwayScript != null:
			holder.set_script(DecorSwayScript)
		_visual_root.add_child(holder)

		var inst := scene.instantiate() as Node3D
		inst.scale = Vector3.ONE * s
		# Center the model on its part spot and sit its base on the sand
		var c := b.get_center()
		inst.position = Vector3(-c.x * s, -b.position.y * s + 0.01, -c.z * s)
		holder.add_child(inst)
		_height = maxf(_height, b.size.y * s)
		idx += 1

	if is_selected:
		CombatVFXScript.set_selection_outline(_visual_root, true, _outline_mat)

	if _hit_area == null:
		_hit_area = Area3D.new()
		_hit_area.name = "DecorClickArea"
		_hit_area.collision_layer = 16
		_hit_area.collision_mask = 0
		_hit_area.input_ray_pickable = true
		add_child(_hit_area)
		var col := CollisionShape3D.new()
		_hit_shape = BoxShape3D.new()
		col.shape = _hit_shape
		_hit_area.add_child(col)
	_hit_shape.size = Vector3(foot_w * 0.96, maxf(_height, 0.4), foot_d * 0.96)
	(_hit_area.get_child(0) as Node3D).position = Vector3(0.0, maxf(_height, 0.4) * 0.5, 0.0)


func _apply_grid_position() -> void:
	var c := get_center()
	position = Vector3(c.x, FLOOR_Y, c.z)
	rotation.y = float(quarter_turns) * PI * 0.5


func set_selected(selected: bool) -> void:
	is_selected = selected
	if _visual_root:
		CombatVFXScript.set_selection_outline(_visual_root, is_selected, _outline_mat)


## Places the footprint at an anchor cell. Returns false if the spot is blocked.
func place_at_anchor(anchor: Vector2i) -> bool:
	var size := get_footprint()
	var a := clamp_anchor(anchor, size)
	if not is_area_free(get_tree(), a, size, self):
		return false
	grid_cell = a
	_apply_grid_position()
	return true


## Rotates 90 degrees. Long pieces swap width and depth, so the turn only happens if
## the rotated footprint still fits; returns false otherwise.
func rotate_step(_angle_rad: float = PI * 0.5) -> bool:
	var new_turns := (quarter_turns + 1) % 4
	var new_size := Vector2i(_base_foot.y, _base_foot.x) if new_turns % 2 == 1 else _base_foot
	var old := get_footprint()
	@warning_ignore("integer_division")
	var center_cell := grid_cell + Vector2i((old.x - 1) / 2, (old.y - 1) / 2)
	var candidates: Array[Vector2i] = [anchor_centered_on(center_cell, new_size), clamp_anchor(grid_cell, new_size)]
	for a in candidates:
		if is_area_free(get_tree(), a, new_size, self):
			quarter_turns = new_turns
			grid_cell = a
			_apply_grid_position()
			return true
	CombatVFXScript.spawn_text_popup(get_tree(), global_position + Vector3(0.0, _height + 0.3, 0.0), "No room to rotate", Color(1.0, 0.6, 0.45))
	return false


func get_display_label() -> String:
	return "%s | Size %s tiles | Comfort +%d for your fish | Drag to move, R to rotate" % [
		decor_name, footprint_label(get_footprint()), comfort
	]


func get_focus_distance() -> float:
	return 4.5 + float(maxi(_base_foot.x, _base_foot.y)) * 0.6
