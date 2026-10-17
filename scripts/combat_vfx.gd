extends Node3D
class_name CombatVFX

## Reusable 3D combat, hit-flash, impact burst, water splash, selection outline, and screen-shake VFX helper.
## Never uses circle/ring torus indicators; uses 3D droplet/spark bursts and outline shaders.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const SelectionOutlineShader = preload("res://shaders/selection_outline.gdshader")

var _elapsed: float = 0.0
var _duration: float = 0.50
var _particles: Array[Dictionary] = []
var _popup_label: Label3D = null
var _popup_base_y: float = 0.45
var _popup_style: String = "punch"


static func create_flash_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.albedo_color = Color(2.2, 2.2, 2.35, 0.0)
	return mat


static func create_selection_outline_material(
	outline_col: Color = Color(0.38, 0.96, 1.0, 0.96),
	width: float = 3.2
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SelectionOutlineShader
	mat.set_shader_parameter("outline_color", outline_col)
	mat.set_shader_parameter("outline_width", width)
	return mat


static func collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root == null:
		return result
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			# Skip trail ribbon meshes so only actual 3D models get outlines/flashes
			if mi.name in ["WaterStreamRibbons", "RibbonTrailMesh"]:
				continue
			result.append(mi)
	return result


static func set_selection_outline(
	root: Node,
	enabled: bool,
	outline_mat: ShaderMaterial = null
) -> void:
	if root == null or not is_instance_valid(root):
		return
	var meshes := collect_mesh_instances(root)
	var mat_to_apply: ShaderMaterial = outline_mat
	if enabled and mat_to_apply == null:
		mat_to_apply = create_selection_outline_material()

	for mi in meshes:
		if not is_instance_valid(mi):
			continue
		if enabled:
			mi.set_meta("selection_outline_mat", mat_to_apply)
			if mi.material_overlay == null or mi.material_overlay is ShaderMaterial:
				mi.material_overlay = mat_to_apply
		else:
			if mi.has_meta("selection_outline_mat"):
				mi.remove_meta("selection_outline_mat")
			if mi.material_overlay is ShaderMaterial:
				mi.material_overlay = null


static func update_flash_overlay(
	meshes: Array[MeshInstance3D],
	flash_mat: StandardMaterial3D,
	alpha: float,
	tint: Color = Color(2.2, 2.2, 2.35, 1.0)
) -> void:
	if flash_mat == null:
		return
	var clamped_a := clampf(alpha, 0.0, 1.0)
	if clamped_a <= 0.005:
		for mi in meshes:
			if not is_instance_valid(mi):
				continue
			if mi.has_meta("selection_outline_mat"):
				var sel_mat: Material = mi.get_meta("selection_outline_mat")
				if mi.material_overlay != sel_mat:
					mi.material_overlay = sel_mat
			elif mi.material_overlay == flash_mat:
				mi.material_overlay = null
		return

	flash_mat.albedo_color = Color(tint.r, tint.g, tint.b, clamped_a)
	for mi in meshes:
		if is_instance_valid(mi) and mi.material_overlay != flash_mat:
			mi.material_overlay = flash_mat


static func trigger_camera_shake(tree: SceneTree, intensity: float, duration: float = 0.22) -> void:
	if tree == null:
		return
	if Engine.has_meta("screen_shake_enabled") and not bool(Engine.get_meta("screen_shake_enabled")):
		return
	var root := tree.current_scene
	if root == null:
		return
	var cam_rig := root.get_node_or_null("AquariumCamera")
	if cam_rig and cam_rig.has_method("trigger_shake"):
		cam_rig.call("trigger_shake", intensity, duration)


static func spawn_hit_effect(
	tree: SceneTree,
	world_pos: Vector3,
	is_heavy: bool = false,
	popup_text: String = "",
	accent_color: Color = Color(0.45, 0.95, 1.0, 1.0)
) -> void:
	if tree == null or tree.current_scene == null:
		return
	var fx := CombatVFX.new()
	fx.name = "CombatHitVFX"
	fx.top_level = true
	tree.current_scene.add_child(fx)
	fx.global_position = world_pos
	fx._build_hit_burst(is_heavy, popup_text, accent_color)


static func spawn_water_splash(
	tree: SceneTree,
	world_pos: Vector3,
	intensity: float = 1.0
) -> void:
	if tree == null or tree.current_scene == null:
		return
	var fx := CombatVFX.new()
	fx.name = "WaterSplashVFX"
	fx.top_level = true
	tree.current_scene.add_child(fx)
	fx.global_position = world_pos
	fx._build_water_splash(intensity)


## Small floating text only (no sparks), e.g. mood changes or "No room to rotate".
static func spawn_text_popup(
	tree: SceneTree,
	world_pos: Vector3,
	popup_text: String,
	color: Color = Color(0.9, 0.96, 1.0, 1.0)
) -> void:
	if tree == null or tree.current_scene == null:
		return
	var fx := CombatVFX.new()
	fx.name = "TextPopupVFX"
	fx.top_level = true
	tree.current_scene.add_child(fx)
	fx.global_position = world_pos
	fx._build_text_popup(popup_text, color)


## Golden sparkle burst used when a coin is collected.
static func spawn_coin_sparkle(tree: SceneTree, world_pos: Vector3, color: Color = Color(1.0, 0.85, 0.35, 1.0)) -> void:
	if tree == null or tree.current_scene == null:
		return
	var fx := CombatVFX.new()
	fx.name = "CoinSparkleVFX"
	fx.top_level = true
	tree.current_scene.add_child(fx)
	fx.global_position = world_pos
	fx._build_coin_sparkle(color)


## Calm, celebratory growth effect for goldfish evolution: rising spiral of
## glowing motes and bubbles plus a soft label. No flash, no shake, no sparks,
## so it never reads as the fish being hurt.
static func spawn_growth_effect(tree: SceneTree, world_pos: Vector3, popup_text: String, color: Color = Color(0.55, 1.0, 0.75, 1.0)) -> void:
	if tree == null or tree.current_scene == null:
		return
	var fx := CombatVFX.new()
	fx.name = "GrowthVFX"
	fx.top_level = true
	tree.current_scene.add_child(fx)
	fx.global_position = world_pos
	fx._build_growth(popup_text, color)


func _make_popup(popup_text: String, color: Color, pixel: float, size: int) -> void:
	_popup_label = Label3D.new()
	_popup_label.position = Vector3(0.0, _popup_base_y, 0.0)
	_popup_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_popup_label.no_depth_test = true
	_popup_label.pixel_size = pixel
	_popup_label.font_size = size
	_popup_label.outline_size = 9
	_popup_label.modulate = color
	_popup_label.outline_modulate = Color(0.04, 0.06, 0.08, 0.92)
	_popup_label.text = popup_text
	add_child(_popup_label)


func _build_text_popup(popup_text: String, color: Color) -> void:
	_duration = 1.1
	_popup_base_y = 0.2
	_popup_style = "soft"
	_make_popup(popup_text, color, 0.0036, 30)


func _build_coin_sparkle(color: Color) -> void:
	_duration = 0.5
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.07, 0.07)
	for i in range(10):
		var p_inst := MeshInstance3D.new()
		var p_mat := StandardMaterial3D.new()
		p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p_mat.albedo_color = Color(color.r * 1.6, color.g * 1.5, color.b * 1.2, 0.95)
		p_inst.mesh = mesh
		p_inst.material_override = p_mat
		p_inst.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(p_inst)
		var angle := TAU * float(i) / 10.0 + randf_range(-0.2, 0.2)
		var vel := Vector3(cos(angle) * randf_range(1.0, 2.0), randf_range(1.8, 3.2), sin(angle) * randf_range(1.0, 2.0))
		_particles.append({
			"node": p_inst,
			"mat": p_mat,
			"vel": vel,
			"gravity": 5.0,
			"base_scale": randf_range(0.7, 1.2),
			"spin": randf_range(6.0, 12.0),
		})


func _build_growth(popup_text: String, color: Color) -> void:
	_duration = 1.35
	_popup_style = "soft"
	var mote_mesh := BoxMesh.new()
	mote_mesh.size = Vector3(0.06, 0.06, 0.06)
	var bubble_mesh := SphereMesh.new()
	bubble_mesh.radius = 0.05
	bubble_mesh.height = 0.1
	bubble_mesh.radial_segments = 8
	bubble_mesh.rings = 4
	for i in range(18):
		var is_bubble := i % 3 == 0
		var p_inst := MeshInstance3D.new()
		var p_mat := StandardMaterial3D.new()
		p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if is_bubble:
			p_mat.albedo_color = Color(0.85, 0.97, 1.0, 0.6)
			p_inst.mesh = bubble_mesh
		else:
			p_mat.albedo_color = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 0.95)
			p_inst.mesh = mote_mesh
			p_inst.rotation = Vector3(PI * 0.25, PI * 0.25, 0.0)
		p_inst.material_override = p_mat
		add_child(p_inst)
		var angle := TAU * float(i) / 18.0
		var radius := randf_range(0.35, 0.6)
		p_inst.position = Vector3(cos(angle) * radius, randf_range(-0.25, 0.1), sin(angle) * radius)
		_particles.append({
			"node": p_inst,
			"mat": p_mat,
			"vel": Vector3(0.0, randf_range(0.7, 1.3), 0.0),
			"gravity": -0.4,
			"base_scale": randf_range(0.8, 1.3),
			"orbit": angle,
			"orbit_r": radius,
			"orbit_speed": randf_range(2.5, 3.5),
		})
	if popup_text != "":
		_popup_base_y = 0.55
		_make_popup(popup_text, Color(color.r, color.g, color.b, 1.0), 0.0040, 34)


func _build_hit_burst(is_heavy: bool, popup_text: String, accent_color: Color) -> void:
	_duration = 0.56 if is_heavy else 0.42
	var scale_mult := 1.40 if is_heavy else 1.0

	# Radial impact streaks & droplets (no circle/ring meshes)
	var count := 12 if is_heavy else 8
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.06 * scale_mult, 0.06 * scale_mult, 0.26 * scale_mult)

	for i in range(count):
		var p_inst := MeshInstance3D.new()
		var p_mat := StandardMaterial3D.new()
		p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p_mat.albedo_color = Color(accent_color.r * 1.25, accent_color.g * 1.25, accent_color.b * 1.25, 0.92)
		p_inst.mesh = spark_mesh
		p_inst.material_override = p_mat
		add_child(p_inst)

		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.45, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		if dir.length_squared() < 0.01:
			dir = Vector3.UP
		var speed := randf_range(2.4, 5.0) * scale_mult
		p_inst.position = dir * 0.12
		if dir.abs().dot(Vector3.UP) < 0.98:
			p_inst.look_at(global_position + dir * 2.0, Vector3.UP)

		_particles.append({
			"node": p_inst,
			"mat": p_mat,
			"vel": dir * speed,
			"gravity": 6.5,
			"base_scale": randf_range(0.75, 1.2),
		})

	# Floating popup label
	if popup_text != "":
		_popup_label = Label3D.new()
		_popup_label.position = Vector3(0.0, _popup_base_y, 0.0)
		_popup_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_popup_label.no_depth_test = true
		_popup_label.pixel_size = 0.0046 if is_heavy else 0.0040
		_popup_label.font_size = 40 if is_heavy else 34
		_popup_label.outline_size = 9
		_popup_label.modulate = Color(1.0, 0.95, 0.45, 1.0) if not is_heavy else Color(1.0, 0.42, 0.35, 1.0)
		_popup_label.outline_modulate = Color(0.06, 0.04, 0.04, 0.94)
		_popup_label.text = popup_text
		add_child(_popup_label)


func _build_water_splash(intensity: float) -> void:
	_duration = 0.46
	var s := clampf(intensity, 0.5, 2.0)

	# Upward droplet crown (no circle/torus ring)
	var drop_mesh := BoxMesh.new()
	drop_mesh.size = Vector3(0.07 * s, 0.14 * s, 0.07 * s)

	var drop_count := int(roundf(8.0 * s))
	for i in range(drop_count):
		var d_inst := MeshInstance3D.new()
		var d_mat := StandardMaterial3D.new()
		d_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d_mat.albedo_color = Color(0.55, 0.92, 1.0, 0.88)
		d_inst.mesh = drop_mesh
		d_inst.material_override = d_mat
		add_child(d_inst)

		var angle := (TAU * float(i)) / maxf(float(drop_count), 1.0) + randf_range(-0.2, 0.2)
		var horiz := randf_range(0.9, 1.8) * s
		var up_vel := randf_range(2.2, 3.6) * s
		var vel := Vector3(cos(angle) * horiz, up_vel, sin(angle) * horiz)
		d_inst.position = Vector3(cos(angle) * 0.15, 0.05, sin(angle) * 0.15)
		_particles.append({
			"node": d_inst,
			"mat": d_mat,
			"vel": vel,
			"gravity": 9.8,
			"base_scale": randf_range(0.8, 1.2),
		})


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / maxf(_duration, 0.01), 0.0, 1.0)

	for p in _particles:
		var node: MeshInstance3D = p["node"]
		var mat: StandardMaterial3D = p["mat"]
		if is_instance_valid(node):
			var vel: Vector3 = p["vel"]
			vel.y -= float(p["gravity"]) * delta
			if not p.has("orbit"):
				vel *= (1.0 - minf(delta * 3.0, 0.5))
			p["vel"] = vel
			node.position += vel * delta
			if p.has("orbit"):
				# Spiral upward around the fish
				var ang := float(p["orbit"]) + float(p["orbit_speed"]) * delta
				p["orbit"] = ang
				var r := float(p["orbit_r"]) * (1.0 + t * 0.4)
				node.position.x = cos(ang) * r
				node.position.z = sin(ang) * r
			if p.has("spin"):
				node.rotation.y += float(p["spin"]) * delta
			var sc := float(p["base_scale"]) * (1.0 - t * 0.85)
			if p.has("orbit"):
				sc = float(p["base_scale"]) * sin(clampf(t, 0.0, 1.0) * PI)
			node.scale = Vector3.ONE * maxf(0.05, sc)
			if mat:
				mat.albedo_color.a = (1.0 - t) * 0.92

	if _popup_label and is_instance_valid(_popup_label):
		if _popup_style == "soft":
			_popup_label.position.y = _popup_base_y + t * 0.5
			_popup_label.scale = Vector3.ONE * (0.85 + 0.15 * minf(t * 6.0, 1.0))
		else:
			_popup_label.position.y = _popup_base_y + t * 0.85
			var pop_scale := 1.0 + sin(minf(t * 3.5, 1.0) * PI) * 0.25
			_popup_label.scale = Vector3.ONE * pop_scale
		_popup_label.modulate.a = clampf(1.0 - maxf(0.0, (t - 0.45) / 0.55), 0.0, 1.0)
		_popup_label.outline_modulate.a = _popup_label.modulate.a * 0.95

	if _elapsed >= _duration:
		queue_free()
