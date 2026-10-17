@tool
extends Node3D
## Goldfish helper for baby.glb / medium.glb / adult.glb.
## Usage: make a Node3D, add one of the .glb files as its child, attach this script to the Node3D.
## Pick a color with `variant`, and call play("Idle"), play("Swim") or play("Died").

enum Variant { CLASSIC, GOLDEN, CALICO, KOHAKU }
const _NAMES := ["classic", "golden", "calico", "kohaku"]
const _LOOPING := ["Idle", "Swim"]

static var _mat_cache := {}

@export var variant: Variant = Variant.CLASSIC:
	set(v):
		variant = v
		if is_inside_tree():
			_apply_variant()

## Folder holding goldfish_*.png. Leave empty to use the "textures" folder next to this script.
@export_dir var textures_dir := ""

@export var autoplay := "Idle"


func _ready() -> void:
	_apply_variant()
	var ap := get_animation_player()
	if ap:
		for n in _LOOPING:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		if autoplay != "" and not Engine.is_editor_hint():
			play(autoplay)


func play(anim: String, blend := 0.2) -> void:
	var ap := get_animation_player()
	if ap and ap.has_animation(anim):
		ap.play(anim, blend)


func get_animation_player() -> AnimationPlayer:
	var found := find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


func _apply_variant() -> void:
	var dir := textures_dir
	if dir == "":
		dir = get_script().resource_path.get_base_dir() + "/textures"
	var tex_path := "%s/goldfish_%s.png" % [dir, _NAMES[variant]]
	if not ResourceLoader.exists(tex_path):
		push_warning("Goldfish texture not found: " + tex_path)
		return
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var base := mi.mesh.surface_get_material(0) as BaseMaterial3D
		if base == null:
			continue
		var key := "%s|%d" % [tex_path, base.get_instance_id()]
		if not _mat_cache.has(key):
			var m := base.duplicate() as BaseMaterial3D
			m.albedo_texture = load(tex_path)
			_mat_cache[key] = m
		mi.set_surface_override_material(0, _mat_cache[key])
