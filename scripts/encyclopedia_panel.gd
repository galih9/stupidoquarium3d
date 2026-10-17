extends PanelContainer

## Encyclopedia panel: lists every creature and plant with a rotating 3D preview,
## a short description, and its stats. Stats are read from the gameplay scripts and
## scripts/game_balance.gd so they always match the real game numbers.
## Used by the Main Menu and the Pause Menu.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const UI = preload("res://scripts/ui_style.gd")
const Balance = preload("res://scripts/game_balance.gd")
const SwimmingFishScript = preload("res://scripts/swimming_fish.gd")
const ArcherFishScript = preload("res://scripts/archer_fish.gd")
const PetCrabScript = preload("res://scripts/pet_crab.gd")
const DuckweedTileScript = preload("res://scripts/duckweed_tile.gd")
const CoinDropScript = preload("res://scripts/coin_drop.gd")
const TankDecorationScript = preload("res://scripts/tank_decoration.gd")

signal closed

var _entries: Array[Dictionary] = []
var _list_buttons: Array[Button] = []
var _selected: int = -1

var _name_label: Label = null
var _role_label: Label = null
var _desc_label: Label = null
var _stats_grid: GridContainer = null

var _viewport: SubViewport = null
var _turntable: Node3D = null
var _model_holder: Node3D = null
var _preview_cam: Camera3D = null
var _spin_speed: float = 0.6


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_style(UI.PANEL_SOLID, 14, 22.0, 20.0))
	custom_minimum_size = Vector2(780.0, 470.0)
	_build_entries()
	_build_ui()
	select_entry(0)


func _process(delta: float) -> void:
	if is_visible_in_tree() and _turntable:
		_turntable.rotation.y += delta * _spin_speed


func _build_entries() -> void:
	var coin_c: int = CoinDropScript.COIN_VALUES[CoinDropScript.CoinTier.COPPER]
	var coin_s: int = CoinDropScript.COIN_VALUES[CoinDropScript.CoinTier.SILVER]
	var coin_g: int = CoinDropScript.COIN_VALUES[CoinDropScript.CoinTier.GOLD]
	var fish_speeds: Dictionary = SwimmingFishScript.SIZE_SPEEDS
	var crab_costs: Array[int] = PetCrabScript.UPGRADE_COSTS
	var crab_speeds: Array[float] = PetCrabScript.CHASE_SPEEDS
	var dw_feeders: Array = DuckweedTileScript.TIER_MAX_FEEDERS
	var dw_costs: Array = DuckweedTileScript.TIER_UPGRADE_COSTS
	var dw_breed: Array = DuckweedTileScript.TIER_BREED_INTERVALS

	var crab_cost_list := PackedStringArray()
	for c in crab_costs:
		if c > 0:
			crab_cost_list.append(str(c))

	_entries = [
		{
			"category": "Fish",
			"name": "Goldfish",
			"role": "Coin producer",
			"color": UI.GOLD,
			"model": "res://assets/fih/adult.glb",
			"anim": "Swim",
			"desc": "The heart of your tank. Goldfish drop coins and grow after enough meals, but each size needs a better plant to eat. They start bored: decorations make them happy, and seeing tank mates eaten stresses them until they hide among decorations.",
			"stats": [
				["Cost", "%d coins" % Balance.price(Balance.COST_BABY_FISH)],
				["Coins (happy)", "Baby copper %d  /  Medium silver %d  /  Adult gold %d" % [coin_c, coin_s, coin_g]],
				["Too bored", "Baby none  /  Medium copper  /  Adult silver"],
				["Bored limit", "%ds without enough decoration" % int(Balance.bored_limit())],
				["Stressed", "Hides by decorations, slower and cheaper coins"],
				["Growth", "Medium after %d meals, Adult after %d" % [SwimmingFishScript.MEALS_TO_MEDIUM, SwimmingFishScript.MEALS_TO_ADULT]],
				["Food needed", "Baby: Duckweed  /  Medium: Lv.2  /  Adult: Hyacinth"],
				["Stays fed", "%d - %ds after a meal" % [int(Balance.FISH_FED_MIN), int(Balance.FISH_FED_MAX)]],
				["Starves after", "%ds of being hungry" % int(Balance.FISH_STARVE_TIME)],
			],
		},
		{
			"category": "Fish",
			"name": "Archer Fish",
			"role": "Defender",
			"color": UI.ACCENT,
			"model": "res://assets/fih/archerfish.glb",
			"anim": "Swim",
			"desc": "A sharpshooter that patrols near the surface. When a Kingfisher attacks, it fires water jets that damage the bird and slow it down. Archer Fish never need food.",
			"stats": [
				["Cost", "%d coins, more for each extra" % Balance.archer_cost(0)],
				["Damage", "%d per shot" % int(ArcherFishScript.SHOT_DAMAGE)],
				["Fire rate", "1 shot every %.2fs" % ArcherFishScript.SHOOT_COOLDOWN],
				["Slow", "Each archer slows birds, up to 70% total"],
				["Food", "None needed"],
				["Active", "Only during the Attack phase"],
			],
		},
		{
			"category": "Pets",
			"name": "Pet Crab",
			"role": "Coin collector",
			"color": UI.WARN,
			"model": "res://assets/fih/crab.glb",
			"anim": "Walk",
			"desc": "Your loyal helper on the sand. The crab walks the tank floor and picks up coins that land there. Early upgrades make it faster; from level 7 it pulls in every coin around it at once, in an area that grows with each level.",
			"stats": [
				["Cost", "Free - every tank starts with one"],
				["Levels 1 - 6", "Speed %.1f up to %.1f" % [crab_speeds[0], crab_speeds[crab_speeds.size() - 1]]],
				["Levels 7 - 12", "Area pickup, radius %.1fm up to %.1fm" % [PetCrabScript.PICKUP_RADII[6], PetCrabScript.PICKUP_RADII[11]]],
				["Upgrade costs", ", ".join(crab_cost_list)],
				["Floor coins", "Vanish after 28s if nobody collects them"],
			],
		},
		{
			"category": "Plants",
			"name": "Duckweed",
			"role": "Food plant",
			"color": UI.GOOD,
			"model": "res://assets/fih/duckweed_tile.glb",
			"anim": "",
			"desc": "A floating carpet of tiny leaves. Hungry goldfish swim up to it to eat. Each plant can only feed a few fish at once, so a growing school needs more plants or upgrades.",
			"stats": [
				["Cost", "%d coins" % Balance.price(Balance.COST_DUCKWEED)],
				["Lv.1", "Feeds %d baby fish at a time" % int(dw_feeders[0])],
				["Lv.2", "Feeds %d baby or medium fish (upgrade %d)" % [int(dw_feeders[1]), int(dw_costs[0])]],
				["Meal time", "%.0fs per fish" % DuckweedTileScript.FEED_DURATION],
				["Surface limit", "12 plants"],
			],
		},
		{
			"category": "Plants",
			"name": "Water Hyacinth",
			"role": "Food plant and nursery",
			"color": UI.GOOD,
			"model": "res://assets/fih/water_hyacinth_tile.glb",
			"anim": "",
			"desc": "The fully upgraded Duckweed. It feeds many fish at once and, when you have at least two adult goldfish, its long roots shelter newborn baby fish.",
			"stats": [
				["Lv.1", "Feeds %d fish of any size (upgrade %d)" % [int(dw_feeders[2]), int(dw_costs[1])]],
				["Lv.1 breeding", "1 baby fish every %d min" % int(float(dw_breed[2]) / 60.0)],
				["Lv.2", "Feeds %d fish (upgrade %d)" % [int(dw_feeders[3]), int(dw_costs[2])]],
				["Lv.2 breeding", "1 baby fish every %d min" % int(float(dw_breed[3]) / 60.0)],
				["Breeding needs", "%d adult goldfish in the tank" % DuckweedTileScript.MIN_ADULTS_FOR_BREEDING],
			],
		},
		{
			"category": "Tank",
			"name": "Decorations",
			"role": "Comfort",
			"color": Color(0.80, 0.70, 1.0),
			"model": "res://assets/fih/decorations/coral_tube.glb",
			"anim": "",
			"desc": "Rocks, corals and seaweed for the tank floor. Each piece adds Comfort: more expensive pieces add more. Enough comfort keeps fish happy, and stressed fish hide next to decorations to calm down. Pieces cover from 1x1 up to 4x1 or 3x2 floor tiles.",
			"stats": [
				["Comfort", "About 1 point per 10 coins of price"],
				["Comfort needed", "%.1f points per fish for 100%% (Hard: %d)" % [Balance.comfort_per_fish(), int(Balance.COMFORT_PER_FISH)]],
				["Cheapest", "Small Rock 1x1, 40 coins, +4"],
				["Long pieces", "Rock Arch 3x1, Grass Row 4x1"],
				["Big sets", "Kelp Forest 2x3 (+17), Coral Garden 3x2 (+21)"],
				["Floor grid", "%d x %d tiles, rotate with R" % [TankDecorationScript.FLOOR_COLS, TankDecorationScript.FLOOR_ROWS]],
			],
		},
		{
			"category": "Threats",
			"name": "Kingfisher",
			"role": "Threat",
			"color": UI.BAD,
			"model": "res://assets/fih/kingfisher.glb",
			"anim": "Fly",
			"desc": "A fast, bright hunter. During the Careful phase it circles above the tank. During the Attack phase it dives for the closest goldfish. Fish near the surface are caught much faster.",
			"stats": [
				["Health", "%d on wave 1, +%d each wave" % [int(Balance.BIRD_HP_BASE), int(Balance.BIRD_HP_PER_WAVE)]],
				["Birds per wave", "1, plus 1 more every %d waves (max %d)" % [Balance.BIRD_WAVES_PER_EXTRA, Balance.BIRD_MAX_COUNT]],
				["Your click", "%d damage and knocks it back" % int(Balance.PLAYER_CLICK_DAMAGE)],
				["Reward", "1 gold coin (%d) when defeated" % coin_g],
				["Weakness", "Archer Fish slow it down"],
			],
		},
	]


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := UI.make_label("Encyclopedia", 20, UI.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := UI.make_button("Close", "secondary", UI.ACCENT, 12, 30.0)
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# Left: entry list grouped by category
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.custom_minimum_size = Vector2(170.0, 0.0)
	body.add_child(list)

	var last_cat := ""
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var cat := String(e["category"])
		if cat != last_cat:
			if last_cat != "":
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0.0, 6.0)
				list.add_child(gap)
			list.add_child(UI.make_caption(cat))
			last_cat = cat
		var btn := UI.make_button(String(e["name"]), "ghost", e["color"], 13, 32.0)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(select_entry.bind(i))
		list.add_child(btn)
		_list_buttons.append(btn)

	var vsep := VSeparator.new()
	var vline := StyleBoxLine.new()
	vline.color = Color(1.0, 1.0, 1.0, 0.07)
	vline.vertical = true
	vsep.add_theme_stylebox_override("separator", vline)
	body.add_child(vsep)

	# Right: preview + details
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	detail.add_child(top)

	var preview_frame := UI.make_panel(Color(0.02, 0.05, 0.08, 1.0), 10, 0.0, 0.0)
	preview_frame.custom_minimum_size = Vector2(210.0, 190.0)
	top.add_child(preview_frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(210.0, 190.0)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_frame.add_child(svc)
	_build_preview_world(svc)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 6)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(text_box)
	_role_label = UI.make_caption("")
	text_box.add_child(_role_label)
	_name_label = UI.make_label("", 24, UI.TEXT)
	text_box.add_child(_name_label)
	_desc_label = UI.make_label("", 13, UI.TEXT_MUTED)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(300.0, 0.0)
	text_box.add_child(_desc_label)

	detail.add_child(UI.make_separator())

	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 18)
	_stats_grid.add_theme_constant_override("v_separation", 7)
	detail.add_child(_stats_grid)


func _build_preview_world(svc: SubViewportContainer) -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(210, 190)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.085, 0.125, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.85, 0.95)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	key.light_energy = 1.25
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.6, 0.85, 1.0)
	_viewport.add_child(rim)

	_preview_cam = Camera3D.new()
	_preview_cam.fov = 35.0
	_preview_cam.position = Vector3(0.0, 0.9, 4.2)
	_preview_cam.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	_viewport.add_child(_preview_cam)

	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	_model_holder = Node3D.new()
	_turntable.add_child(_model_holder)


func select_entry(idx: int) -> void:
	if idx < 0 or idx >= _entries.size():
		return
	_selected = idx
	var e: Dictionary = _entries[idx]
	var col: Color = e["color"]

	for i in range(_list_buttons.size()):
		UI.style_button(_list_buttons[i], "secondary" if i == idx else "ghost", _entries[i]["color"])

	_role_label.text = String(e["role"]).to_upper()
	_role_label.add_theme_color_override("font_color", col)
	_name_label.text = String(e["name"])
	_desc_label.text = String(e["desc"])

	for c in _stats_grid.get_children():
		c.queue_free()
	for pair in e["stats"]:
		var k := UI.make_label(String(pair[0]), 12, UI.TEXT_FAINT)
		k.custom_minimum_size = Vector2(110.0, 0.0)
		_stats_grid.add_child(k)
		var v := UI.make_label(String(pair[1]), 13, UI.TEXT)
		_stats_grid.add_child(v)

	_show_model(String(e["model"]), String(e["anim"]))


func _show_model(path: String, anim_name: String) -> void:
	if _model_holder == null:
		return
	for c in _model_holder.get_children():
		_model_holder.remove_child(c)
		c.queue_free()
	_model_holder.position = Vector3.ZERO
	_model_holder.scale = Vector3.ONE
	_turntable.rotation = Vector3.ZERO
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var inst := scene.instantiate()
	_model_holder.add_child(inst)

	# Auto-fit: scale the model into a ~1.8 unit box and center it on the turntable
	var bounds := _compute_bounds(inst)
	if bounds.size.length() > 0.001:
		var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var s := 1.8 / maxf(longest, 0.001)
		_model_holder.scale = Vector3.ONE * s
		_model_holder.position = -bounds.get_center() * s + Vector3(0.0, 0.55, 0.0)

	if anim_name != "":
		var found := inst.find_children("*", "AnimationPlayer", true, false)
		if not found.is_empty():
			var ap := found[0] as AnimationPlayer
			if ap.has_animation(anim_name):
				ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
				ap.play(anim_name)


func _compute_bounds(root: Node) -> AABB:
	var result := AABB()
	var first := true
	var root_xf_inv := Transform3D.IDENTITY
	if root is Node3D:
		root_xf_inv = (root as Node3D).global_transform.affine_inverse()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var local_xf := root_xf_inv * mi.global_transform
		var box := local_xf * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _on_close_pressed() -> void:
	visible = false
	closed.emit()
