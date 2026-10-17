extends Node3D
class_name CoinDrop

## Collectible 3D coin dropped by goldfish on a timer.
## Sinks to the sandy bottom and can be clicked or collected automatically.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const CombatVFXScript = preload("res://scripts/combat_vfx.gd")

enum CoinTier { COPPER, SILVER, GOLD }

const SPARKLE_COLORS := {
	CoinTier.COPPER: Color(1.0, 0.62, 0.35, 1.0),
	CoinTier.SILVER: Color(0.85, 0.92, 1.0, 1.0),
	CoinTier.GOLD: Color(1.0, 0.85, 0.30, 1.0),
}

const COIN_MODELS := {
	CoinTier.COPPER: preload("res://assets/copper.gltf"),
	CoinTier.SILVER: preload("res://assets/silver.gltf"),
	CoinTier.GOLD: preload("res://assets/gold.gltf"),
}

const COIN_VALUES := {
	CoinTier.COPPER: 20,
	CoinTier.SILVER: 35,
	CoinTier.GOLD: 65,
}

signal collected(value: int, coin: CoinDrop)

@export var tier: CoinTier = CoinTier.COPPER
@export var floor_y: float = 0.68
@export var sink_speed: float = 0.85

var coin_value: int = 20
var is_collected: bool = false
## True when the player clicked the coin (false when the Pet Crab picked it up).
var collected_by_player: bool = false
## Set by the Pet Crab's area pickup: the coin glides into the crab, then collects.
var attract_target: Node3D = null
var _attract_speed: float = 2.0

var _visual: Node3D = null
var _hit_area: Area3D = null
var _floor_timer: float = 0.0
var _collect_anim_timer: float = 0.0
var _spin_speed: float = 2.6
var _bob_phase: float = 0.0
var _popup_label: Label3D = null


func _ready() -> void:
	add_to_group("coins")
	coin_value = COIN_VALUES.get(tier, 20)
	_bob_phase = randf() * TAU

	var scene: PackedScene = COIN_MODELS.get(tier, COIN_MODELS[CoinTier.COPPER])
	if scene:
		_visual = scene.instantiate()
		_visual.scale = Vector3.ONE * 0.44
		add_child(_visual)

	_hit_area = Area3D.new()
	_hit_area.name = "CoinClickArea"
	_hit_area.collision_layer = 4
	_hit_area.collision_mask = 0
	_hit_area.input_ray_pickable = true
	add_child(_hit_area)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.52
	col.shape = shape
	_hit_area.add_child(col)

	_popup_label = Label3D.new()
	_popup_label.position = Vector3(0.0, 0.35, 0.0)
	_popup_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_popup_label.pixel_size = 0.0045
	_popup_label.font_size = 40
	_popup_label.outline_size = 10
	_popup_label.modulate = Color(1.0, 0.92, 0.35, 0.95)
	_popup_label.outline_modulate = Color(0.12, 0.08, 0.02, 0.95)
	_popup_label.text = "+%d" % coin_value
	_popup_label.visible = false
	add_child(_popup_label)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if is_collected:
		_collect_anim_timer += delta
		global_position.y += delta * 2.2
		if _visual:
			_visual.rotation.y += delta * 12.0
			_visual.scale = _visual.scale.lerp(Vector3.ZERO, clampf(delta * 8.0, 0.0, 1.0))
		if _collect_anim_timer >= 0.45:
			queue_free()
		return

	_bob_phase += delta * 3.0
	if _visual:
		_visual.rotation.y += _spin_speed * delta

	if attract_target != null:
		if not is_instance_valid(attract_target):
			attract_target = null
		else:
			var goal := attract_target.global_position + Vector3(0.0, 0.35, 0.0)
			_attract_speed = minf(_attract_speed + delta * 18.0, 14.0)
			global_position = global_position.move_toward(goal, _attract_speed * delta)
			if _visual:
				_visual.rotation.y += delta * 10.0
			if global_position.distance_to(goal) < 0.25:
				collect(false)
			return

	if global_position.y > floor_y:
		global_position.y = maxf(floor_y, global_position.y - sink_speed * delta)
		global_position.x += sin(_bob_phase) * 0.12 * delta
	else:
		_floor_timer += delta
		# Stay on the sand floor for the Pet Crab (or player click) to collect
		if _floor_timer >= 28.0:
			queue_free()


func attract_to(target: Node3D) -> void:
	if is_collected or attract_target != null:
		return
	attract_target = target
	_attract_speed = 2.0


func collect(by_player: bool = false) -> void:
	if is_collected:
		return
	is_collected = true
	collected_by_player = by_player
	attract_target = null
	CombatVFXScript.spawn_coin_sparkle(get_tree(), global_position, SPARKLE_COLORS.get(tier, Color(1.0, 0.85, 0.35)))
	if _popup_label:
		_popup_label.visible = true
	collected.emit(coin_value, self)
