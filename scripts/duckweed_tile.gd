extends Node3D
class_name DuckweedTile

## Floating surface food producer tile (Duckweed -> Water Hyacinth).
## Movable across the water surface and upgradable through 4 stages:
## - Tier 0: Duckweed Lv.1 (Sparse) -> Feeds 1 fish at a time
## - Tier 1: Duckweed Lv.2 (Normal) -> Feeds 2 fish at the same time
## - Tier 2: Hyacinth Lv.1 (Sparse) -> Feeds 4 fish at a time + spawns 1 Baby Goldfish every 180s (3 min) if >= 2 Adult Goldfish
## - Tier 3: Hyacinth Lv.2 (Normal) -> Feeds 8 fish at the same time + spawns 1 Baby Goldfish every 60s (1 min) if >= 2 Adult Goldfish
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const CombatVFXScript = preload("res://scripts/combat_vfx.gd")
const Balance = preload("res://scripts/game_balance.gd")

enum ProducerTier {
	DUCKWEED_LV1_SPARSE = 0,
	DUCKWEED_LV2_NORMAL = 1,
	HYACINTH_LV1_SPARSE = 2,
	HYACINTH_LV2_NORMAL = 3,
}

const TIER_MODELS := {
	ProducerTier.DUCKWEED_LV1_SPARSE: preload("res://assets/fih/duckweed_tile_sparse.glb"),
	ProducerTier.DUCKWEED_LV2_NORMAL: preload("res://assets/fih/duckweed_tile.glb"),
	ProducerTier.HYACINTH_LV1_SPARSE: preload("res://assets/fih/water_hyacinth_tile_sparse.glb"),
	ProducerTier.HYACINTH_LV2_NORMAL: preload("res://assets/fih/water_hyacinth_tile.glb"),
}

const TIER_NAMES := [
	"Duckweed Lv.1 (Sparse)",
	"Duckweed Lv.2 (Normal)",
	"Hyacinth Lv.1 (Sparse)",
	"Hyacinth Lv.2 (Normal)",
]

const TIER_SHORT_NAMES := [
	"Duckweed Lv.1",
	"Duckweed Lv.2",
	"Hyacinth Lv.1",
	"Hyacinth Lv.2",
]

const TIER_MAX_FEEDERS := [1, 2, 4, 8]
# Biggest goldfish size each tier can feed (0 = Baby, 1 = Medium, 2 = Adult).
# Duckweed Lv.1 only feeds babies, Lv.2 adds medium fish, Water Hyacinth feeds adults too.
const TIER_MAX_FISH_SIZE := [0, 1, 2, 2]
const SIZE_LABELS := ["Baby fish only", "Baby and Medium fish", "All fish sizes", "All fish sizes"]
const TIER_BREED_INTERVALS := [0.0, 0.0, 180.0, 60.0]
const TIER_UPGRADE_COSTS := [180, 360, 650, 0]

const FEED_DURATION: float = 3.0
const TILE_SCALE: float = 0.38
const MIN_ADULTS_FOR_BREEDING: int = 2

signal feeding_started(tile: DuckweedTile, fish: Node3D)
signal feeding_completed(tile: DuckweedTile, fish: Node3D)
signal baby_goldfish_spawned(tile: DuckweedTile, spawn_pos: Vector3)
signal upgraded(tile: DuckweedTile, new_tier: int)

var tile_index: int = 0
var grid_cell: Vector2i = Vector2i.ZERO
var tier: ProducerTier = ProducerTier.DUCKWEED_LV1_SPARSE
var base_position: Vector3 = Vector3.ZERO
var is_selected: bool = false

# Array of {"fish": Node3D, "timer": float, "slot": int}
var _active_feeders: Array[Dictionary] = []
var _breed_elapsed: float = 0.0
var _bob_phase: float = 0.0
var _visual_root: Node3D = null
var _hit_area: Area3D = null
var _status_label: Label3D = null
var _outline_mat: ShaderMaterial = null


func _ready() -> void:
	add_to_group("duckweed")
	add_to_group("selectable_entities")
	add_to_group("movable_surface")
	base_position = position
	_bob_phase = randf() * TAU
	_outline_mat = CombatVFXScript.create_selection_outline_material(Color(0.42, 1.0, 0.62, 0.96), 3.4)

	_rebuild_model()
	_setup_click_area()
	_create_feedback_visuals()


func _rebuild_model() -> void:
	if _visual_root and is_instance_valid(_visual_root):
		remove_child(_visual_root)
		_visual_root.queue_free()
		_visual_root = null

	var scene: PackedScene = TIER_MODELS.get(int(tier), TIER_MODELS[ProducerTier.DUCKWEED_LV1_SPARSE])
	if scene:
		_visual_root = scene.instantiate()
		_visual_root.scale = Vector3.ONE * TILE_SCALE
		_visual_root.rotation.y = (tile_index % 4) * (PI * 0.5)
		add_child(_visual_root)

	if is_selected and _visual_root:
		CombatVFXScript.set_selection_outline(_visual_root, true, _outline_mat)


func _setup_click_area() -> void:
	if _hit_area != null:
		return
	_hit_area = Area3D.new()
	_hit_area.name = "TileClickArea"
	_hit_area.collision_layer = 8
	_hit_area.collision_mask = 0
	_hit_area.input_ray_pickable = true
	add_child(_hit_area)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.85, 0.65, 1.85)
	col.shape = box
	col.position = Vector3(0.0, -0.1, 0.0)
	_hit_area.add_child(col)


func _create_feedback_visuals() -> void:
	_status_label = Label3D.new()
	_status_label.name = "FeedLabel"
	_status_label.position = Vector3(0.0, 0.42, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = false
	_status_label.pixel_size = 0.0036
	_status_label.font_size = 28
	_status_label.outline_size = 6
	_status_label.modulate = Color(0.75, 1.0, 0.78, 0.90)
	_status_label.outline_modulate = Color(0.05, 0.12, 0.06, 0.88)
	_status_label.visible = false
	add_child(_status_label)


func set_selected(selected: bool) -> void:
	is_selected = selected
	if _visual_root:
		CombatVFXScript.set_selection_outline(_visual_root, is_selected, _outline_mat)


func set_grid_cell(cell: Vector2i, world_pos: Vector3) -> void:
	grid_cell = cell
	set_surface_position(world_pos)


func set_surface_position(new_pos: Vector3) -> void:
	base_position.x = new_pos.x
	base_position.z = new_pos.z
	position.x = new_pos.x
	position.z = new_pos.z


func rotate_step(angle_rad: float = PI * 0.5) -> void:
	rotation.y = wrapf(rotation.y + angle_rad, 0.0, TAU)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_bob_phase += delta * 1.8
	_process_active_feeders(delta)
	_process_hyacinth_breeding(delta)

	if not _active_feeders.is_empty():
		var nibble_offset := sin(_bob_phase * 5.5) * 0.032
		position.y = base_position.y + nibble_offset
	else:
		position.y = base_position.y + sin(_bob_phase) * 0.02

	if _status_label:
		if is_selected and not _active_feeders.is_empty():
			_status_label.visible = true
			_status_label.text = "%d/%d" % [_active_feeders.size(), get_max_feeders()]
		else:
			_status_label.visible = false


func _process_active_feeders(delta: float) -> void:
	var i := _active_feeders.size() - 1
	while i >= 0:
		var entry: Dictionary = _active_feeders[i]
		var fish: Node3D = entry["fish"]
		if fish == null or not is_instance_valid(fish) or bool(fish.get("is_dead")):
			_active_feeders.remove_at(i)
			i -= 1
			continue

		var next_t := float(entry["timer"]) + delta
		entry["timer"] = next_t
		if next_t >= FEED_DURATION:
			_active_feeders.remove_at(i)
			if fish.has_method("complete_feeding"):
				fish.call("complete_feeding")
			feeding_completed.emit(self, fish)
		i -= 1


func _process_hyacinth_breeding(delta: float) -> void:
	var interval := get_breed_interval()
	if interval <= 0.0:
		_breed_elapsed = 0.0
		return

	var adult_count := _count_alive_adult_goldfish()
	if adult_count >= MIN_ADULTS_FOR_BREEDING:
		_breed_elapsed += delta
		if _breed_elapsed >= interval:
			_breed_elapsed = 0.0
			var spawn_pos := global_position + Vector3(
				randf_range(-0.35, 0.35),
				-0.55,
				randf_range(-0.35, 0.35)
			)
			CombatVFXScript.spawn_water_splash(get_tree(), Vector3(global_position.x, global_position.y - 0.1, global_position.z), 0.75)
			CombatVFXScript.spawn_hit_effect(
				get_tree(),
				spawn_pos,
				false,
				"NEW BABY FISH!",
				Color(0.55, 1.0, 0.68, 1.0)
			)
			baby_goldfish_spawned.emit(self, spawn_pos)


func _count_alive_adult_goldfish() -> int:
	if get_tree() == null:
		return 0
	var count := 0
	for node in get_tree().get_nodes_in_group("goldfish"):
		if is_instance_valid(node) and not bool(node.get("is_dead")):
			if int(node.get("size_category")) == 2:
				count += 1
	return count


func get_max_feeders() -> int:
	return TIER_MAX_FEEDERS[clampi(int(tier), 0, TIER_MAX_FEEDERS.size() - 1)]


func get_active_feeder_count() -> int:
	var i := _active_feeders.size() - 1
	while i >= 0:
		var fish: Node3D = _active_feeders[i]["fish"]
		if fish == null or not is_instance_valid(fish) or bool(fish.get("is_dead")):
			_active_feeders.remove_at(i)
		i -= 1
	return _active_feeders.size()


func get_breed_interval() -> float:
	return TIER_BREED_INTERVALS[clampi(int(tier), 0, TIER_BREED_INTERVALS.size() - 1)]


func get_breed_time_remaining() -> float:
	var interval := get_breed_interval()
	if interval <= 0.0:
		return 0.0
	return maxf(0.0, interval - _breed_elapsed)


func can_upgrade() -> bool:
	return int(tier) < ProducerTier.HYACINTH_LV2_NORMAL


func get_upgrade_cost() -> int:
	if not can_upgrade():
		return 0
	return Balance.price(TIER_UPGRADE_COSTS[clampi(int(tier), 0, TIER_UPGRADE_COSTS.size() - 1)])


func get_next_tier_name() -> String:
	if not can_upgrade():
		return "Max"
	return TIER_SHORT_NAMES[clampi(int(tier) + 1, 0, TIER_SHORT_NAMES.size() - 1)]


func upgrade_tier() -> bool:
	if not can_upgrade():
		return false
	tier = (int(tier) + 1) as ProducerTier
	_rebuild_model()
	CombatVFXScript.spawn_growth_effect(
		get_tree(),
		global_position + Vector3(0.0, 0.15, 0.0),
		"Upgraded: %s" % TIER_SHORT_NAMES[int(tier)],
		Color(0.45, 1.0, 0.65, 1.0)
	)
	upgraded.emit(self, int(tier))
	return true


func get_max_fish_size() -> int:
	return TIER_MAX_FISH_SIZE[clampi(int(tier), 0, TIER_MAX_FISH_SIZE.size() - 1)]


func can_feed_size(size_cat: int) -> bool:
	return size_cat <= get_max_fish_size()


func can_feed_fish(fish: Node3D) -> bool:
	if fish == null or not is_instance_valid(fish):
		return false
	return can_feed_size(int(fish.get("size_category")))


func is_available() -> bool:
	return get_active_feeder_count() < get_max_feeders()


func is_feeding_fish(fish: Node3D) -> bool:
	for entry in _active_feeders:
		if entry["fish"] == fish:
			return true
	return false


func begin_feeding(fish: Node3D) -> bool:
	if fish == null or not is_instance_valid(fish):
		return false
	if is_feeding_fish(fish):
		return true
	if not is_available() or not can_feed_fish(fish):
		return false

	var used_slots: Array[int] = []
	for entry in _active_feeders:
		used_slots.append(int(entry["slot"]))
	var chosen_slot := 0
	var max_f := get_max_feeders()
	for s in range(max_f):
		if not used_slots.has(s):
			chosen_slot = s
			break

	_active_feeders.append({
		"fish": fish,
		"timer": 0.0,
		"slot": chosen_slot,
	})
	feeding_started.emit(self, fish)
	return true


func cancel_feeding(fish: Node3D) -> void:
	if fish == null:
		_active_feeders.clear()
		return
	var i := _active_feeders.size() - 1
	while i >= 0:
		if _active_feeders[i]["fish"] == fish:
			_active_feeders.remove_at(i)
		i -= 1


func get_feed_point_for(fish: Node3D) -> Vector3:
	var max_f := get_max_feeders()
	if max_f <= 1 or fish == null:
		return global_position + Vector3(0.0, -0.48, 0.0)

	var slot_idx := -1
	for entry in _active_feeders:
		if entry["fish"] == fish:
			slot_idx = int(entry["slot"])
			break
	if slot_idx < 0:
		slot_idx = abs(fish.get_instance_id()) % max_f

	var angle := (TAU * float(slot_idx)) / float(max_f)
	var radius := 0.36 if max_f <= 2 else (0.48 if max_f <= 4 else 0.58)
	return global_position + Vector3(cos(angle) * radius, -0.48, sin(angle) * radius)


func get_feed_point() -> Vector3:
	return global_position + Vector3(0.0, -0.48, 0.0)


func get_wait_point() -> Vector3:
	return global_position + Vector3(0.0, -1.25, 0.0)


func get_display_label() -> String:
	var t_name: String = TIER_NAMES[clampi(int(tier), 0, TIER_NAMES.size() - 1)]
	var feed_str := "Feeds: %s" % SIZE_LABELS[clampi(int(tier), 0, SIZE_LABELS.size() - 1)]
	feed_str += " | Feeding %d of %d fish" % [get_active_feeder_count(), get_max_feeders()]
	var interval := get_breed_interval()
	if interval > 0.0:
		var adults := _count_alive_adult_goldfish()
		if adults >= MIN_ADULTS_FOR_BREEDING:
			feed_str += " | New baby fish in %ds" % int(ceilf(get_breed_time_remaining()))
		else:
			feed_str += " | Breeding needs %d adults (%d now)" % [MIN_ADULTS_FOR_BREEDING, adults]
	else:
		feed_str += " | Upgrade to feed more and bigger fish"
	return "%s | %s" % [t_name, feed_str]


func get_focus_distance() -> float:
	return 4.2
