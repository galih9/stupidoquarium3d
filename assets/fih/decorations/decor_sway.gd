extends Node3D
## For decorations/seaweed_*.glb: loops the "Sway" animation, starting at a random point and
## speed so several seaweeds next to each other don't move in sync.
## Usage: make a Node3D, add a seaweed .glb as its child, attach this script to the Node3D.

@export var speed_min := 0.8
@export var speed_max := 1.2


func _ready() -> void:
	var found := find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	var ap := found[0] as AnimationPlayer
	if not ap.has_animation("Sway"):
		return
	var anim := ap.get_animation("Sway")
	anim.loop_mode = Animation.LOOP_LINEAR
	ap.speed_scale = randf_range(speed_min, speed_max)
	ap.play("Sway")
	ap.seek(randf() * anim.length, true)
