extends Node3D
class_name TankDecoration

## Movable bottom-of-tank decoration item (Corals, Rocks, Seaweed).
## Can be placed, selected (with outline shader), rotated, and moved across the tank bottom during the Peaceful phase.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const CombatVFXScript = preload("res://scripts/combat_vfx.gd")
const DecorSwayScript = preload("res://assets/fih/decorations/decor_sway.gd")

const FLOOR_Y: float = 0.50

const CATALOG: Array[Dictionary] = [
	{
		"id": "coral_brain",
		"name": "Brain Coral",
		"category": "Coral",
		"cost": 65,
		"scene": preload("res://assets/fih/decorations/coral_brain.glb"),
		"scale": 0.92,
		"y_offset": 0.02,
		"radius": 0.72,
		"height": 0.65,
		"sway": false,
	},
	{
		"id": "coral_branch",
		"name": "Branch Coral",
		"category": "Coral",
		"cost": 75,
		"scene": preload("res://assets/fih/decorations/coral_branch.glb"),
		"scale": 0.90,
		"y_offset": 0.16,
		"radius": 0.68,
		"height": 1.25,
		"sway": false,
	},
	{
		"id": "coral_fan",
		"name": "Fan Coral",
		"category": "Coral",
		"cost": 75,
		"scene": preload("res://assets/fih/decorations/coral_fan.glb"),
		"scale": 0.95,
		"y_offset": 0.04,
		"radius": 0.75,
		"height": 1.15,
		"sway": false,
	},
	{
		"id": "coral_tube",
		"name": "Tube Coral",
		"category": "Coral",
		"cost": 85,
		"scene": preload("res://assets/fih/decorations/coral_tube.glb"),
		"scale": 0.90,
		"y_offset": 0.05,
		"radius": 0.68,
		"height": 1.10,
		"sway": false,
	},
	{
		"id": "seaweed_grass",
		"name": "Sea Grass",
		"category": "Plant",
		"cost": 50,
		"scene": preload("res://assets/fih/decorations/seaweed_grass.glb"),
		"scale": 0.95,
		"y_offset": 0.02,
		"radius": 0.65,
		"height": 1.60,
		"sway": true,
	},
	{
		"id": "seaweed_bubble",
		"name": "Bubble Weed",
		"category": "Plant",
		"cost": 65,
		"scene": preload("res://assets/fih/decorations/seaweed_bubble.glb"),
		"scale": 0.95,
		"y_offset": 0.01,
		"radius": 0.68,
		"height": 1.65,
		"sway": true,
	},
	{
		"id": "seaweed_kelp",
		"name": "Tall Kelp",
		"category": "Plant",
		"cost": 75,
		"scene": preload("res://assets/fih/decorations/seaweed_kelp.glb"),
		"scale": 0.92,
		"y_offset": 0.06,
		"radius": 0.55,
		"height": 2.45,
		"sway": true,
	},
	{
		"id": "rock_small",
		"name": "Small Rock",
		"category": "Rock",
		"cost": 40,
		"scene": preload("res://assets/fih/decorations/rock_small.glb"),
		"scale": 1.05,
		"y_offset": 0.02,
		"radius": 0.52,
		"height": 0.50,
		"sway": false,
	},
	{
		"id": "rock_flat",
		"name": "Flat Stone",
		"category": "Rock",
		"cost": 50,
		"scene": preload("res://assets/fih/decorations/rock_flat.glb"),
		"scale": 1.00,
		"y_offset": 0.03,
		"radius": 0.78,
		"height": 0.40,
		"sway": false,
	},
	{
		"id": "rock_stack",
		"name": "Rock Stack",
		"category": "Rock",
		"cost": 65,
		"scene": preload("res://assets/fih/decorations/rock_stack.glb"),
		"scale": 0.95,
		"y_offset": 0.0,
		"radius": 0.62,
		"height": 0.95,
		"sway": false,
	},
	{
		"id": "rock_big",
		"name": "Boulder",
		"category": "Rock",
		"cost": 80,
		"scene": preload("res://assets/fih/decorations/rock_big.glb"),
		"scale": 0.96,
		"y_offset": 0.03,
		"radius": 0.76,
		"height": 0.88,
		"sway": false,
	},
	{
		"id": "rock_arch",
		"name": "Rock Arch",
		"category": "Rock",
		"cost": 110,
		"scene": preload("res://assets/fih/decorations/rock_arch.glb"),
		"scale": 0.92,
		"y_offset": 0.35,
		"radius": 1.05,
		"height": 1.65,
		"sway": false,
	},
]

var decor_id: String = "coral_brain"
var decor_name: String = "Brain Coral"
var decor_cost: int = 65
var grid_cell: Vector2i = Vector2i.ZERO
var is_selected: bool = false

var _visual_root: Node3D = null
var _hit_area: Area3D = null
var _outline_mat: ShaderMaterial = null
var _y_offset: float = 0.02


static func get_catalog_entry(id_str: String) -> Dictionary:
	for entry in CATALOG:
		if String(entry["id"]) == id_str:
			return entry
	return CATALOG[0]


func _ready() -> void:
	add_to_group("decorations")
	add_to_group("selectable_entities")
	add_to_group("movable_floor")
	_outline_mat = CombatVFXScript.create_selection_outline_material(Color(0.98, 0.86, 0.38, 0.96), 3.4)
	_build_decoration()


func _build_decoration() -> void:
	var entry := get_catalog_entry(decor_id)
	decor_name = String(entry["name"])
	decor_cost = int(entry["cost"])
	_y_offset = float(entry["y_offset"])
	position.y = FLOOR_Y

	if _visual_root and is_instance_valid(_visual_root):
		remove_child(_visual_root)
		_visual_root.queue_free()
		_visual_root = null

	var holder := Node3D.new()
	holder.name = "VisualHolder"
	holder.position = Vector3(0.0, _y_offset, 0.0)
	if bool(entry["sway"]) and DecorSwayScript != null:
		holder.set_script(DecorSwayScript)

	var scene: PackedScene = entry["scene"]
	if scene:
		var inst := scene.instantiate()
		inst.scale = Vector3.ONE * float(entry["scale"])
		holder.add_child(inst)

	add_child(holder)
	_visual_root = holder

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
		var cyl := CylinderShape3D.new()
		cyl.radius = float(entry["radius"])
		cyl.height = float(entry["height"])
		col.shape = cyl
		col.position = Vector3(0.0, float(entry["height"]) * 0.5, 0.0)
		_hit_area.add_child(col)


func set_selected(selected: bool) -> void:
	is_selected = selected
	if _visual_root:
		CombatVFXScript.set_selection_outline(_visual_root, is_selected, _outline_mat)


func set_grid_cell(cell: Vector2i, world_pos: Vector3) -> void:
	grid_cell = cell
	set_floor_position(world_pos)


func set_floor_position(new_pos: Vector3) -> void:
	position.x = clampf(new_pos.x, -6.3, 6.3)
	position.z = clampf(new_pos.z, -3.6, 3.6)
	position.y = FLOOR_Y


func rotate_step(angle_rad: float = PI * 0.5) -> void:
	rotation.y = wrapf(rotation.y + angle_rad, 0.0, TAU)


func get_display_label() -> String:
	return "%s | Floor tile %d, %d | Drag to move, R to rotate" % [decor_name, grid_cell.x + 1, grid_cell.y + 1]


func get_focus_distance() -> float:
	return 4.5
