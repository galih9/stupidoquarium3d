extends RefCounted

## Shared minimal UI style helpers (colors, panels, buttons, labels).
## Used by the HUD, main menu, pause menu, loading screen, tutorial and encyclopedia
## so every screen shares the same calm, minimal look.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

const BG := Color(0.030, 0.060, 0.095, 1.0)
const PANEL := Color(0.040, 0.085, 0.130, 0.86)
const PANEL_SOLID := Color(0.050, 0.095, 0.140, 0.97)
const PANEL_BORDER := Color(1.0, 1.0, 1.0, 0.07)
const TEXT := Color(0.93, 0.96, 0.98, 1.0)
const TEXT_MUTED := Color(0.60, 0.70, 0.78, 1.0)
const TEXT_FAINT := Color(0.45, 0.54, 0.62, 1.0)
const ACCENT := Color(0.36, 0.80, 0.93, 1.0)
const GOLD := Color(1.00, 0.84, 0.40, 1.0)
const GOOD := Color(0.46, 0.88, 0.62, 1.0)
const WARN := Color(1.00, 0.76, 0.34, 1.0)
const BAD := Color(1.00, 0.45, 0.42, 1.0)

const RADIUS: int = 10


static func panel_style(bg: Color = PANEL, radius: int = RADIUS, pad_h: float = 14.0, pad_v: float = 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = PANEL_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.anti_aliasing = true
	return s


static func make_panel(bg: Color = PANEL, radius: int = RADIUS, pad_h: float = 14.0, pad_v: float = 10.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, radius, pad_h, pad_v))
	return p


static func make_label(text_str: String, size: int = 13, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text_str
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func make_caption(text_str: String) -> Label:
	# Small uppercase muted caption used above values and as section headers
	var l := make_label(text_str.to_upper(), 10, TEXT_FAINT)
	return l


static func _button_box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	s.anti_aliasing = true
	return s


## kind: "primary" (filled accent), "secondary" (subtle fill), "ghost" (transparent)
static func style_button(btn: Button, kind: String = "secondary", accent: Color = ACCENT, radius: int = 8) -> void:
	var normal: StyleBoxFlat
	match kind:
		"primary":
			normal = _button_box(Color(accent.r * 0.55, accent.g * 0.55, accent.b * 0.60, 0.95), Color(accent.r, accent.g, accent.b, 0.0), radius)
		"ghost":
			normal = _button_box(Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.0), radius)
		"hud":
			# Dark translucent fill so the button stays readable over the bright 3D tank
			normal = _button_box(PANEL, PANEL_BORDER, radius)
		_:
			normal = _button_box(Color(1.0, 1.0, 1.0, 0.045), Color(1.0, 1.0, 1.0, 0.06), radius)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.10) if kind in ["primary", "hud"] else Color(1.0, 1.0, 1.0, 0.10)
	hover.border_color = Color(accent.r, accent.g, accent.b, 0.55)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = normal.bg_color.darkened(0.15) if kind in ["primary", "hud"] else Color(1.0, 1.0, 1.0, 0.03)
	pressed.border_color = Color(accent.r, accent.g, accent.b, 0.75)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, 0.55) if kind == "hud" else Color(1.0, 1.0, 1.0, 0.02)
	disabled.border_color = Color(1.0, 1.0, 1.0, 0.03)

	var focus := StyleBoxEmpty.new()

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(TEXT_FAINT.r, TEXT_FAINT.g, TEXT_FAINT.b, 0.6))


static func make_button(text_str: String, kind: String = "secondary", accent: Color = ACCENT, font_size: int = 14, min_h: float = 38.0) -> Button:
	var btn := Button.new()
	btn.text = text_str
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0.0, min_h)
	btn.add_theme_font_size_override("font_size", font_size)
	style_button(btn, kind, accent)
	return btn


static func make_progress_bar(fill: Color = ACCENT, height: float = 4.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	bg.set_corner_radius_all(int(height))
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(int(height))
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


static func set_progress_color(bar: ProgressBar, fill: Color) -> void:
	if bar == null:
		return
	var fg := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fg and fg.bg_color != fill:
		fg.bg_color = fill


static func make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(1.0, 1.0, 1.0, 0.07)
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	sep.add_theme_constant_override("separation", 10)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


static func make_background_gradient() -> TextureRect:
	# Soft vertical underwater gradient used behind menus and loading screens
	var grad := Gradient.new()
	grad.set_color(0, Color(0.055, 0.130, 0.190, 1.0))
	grad.set_color(1, Color(0.015, 0.035, 0.060, 1.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 16
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
