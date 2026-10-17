shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

// Selection outline shader for focused/selected 3D objects (fish, pets, plants, decorations).
// NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

uniform vec4 outline_color : source_color = vec4(0.38, 0.96, 1.0, 0.96);
uniform float outline_width : hint_range(0.5, 12.0) = 3.2;
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;

void vertex() {
	float model_scale = max(length(MODEL_MATRIX[0].xyz), 0.01);
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float cam_dist = clamp(length(view_pos), 2.0, 24.0);
	float world_thickness = outline_width * 0.0013 * cam_dist;
	float local_thickness = world_thickness / model_scale;

	vec3 radial = length(VERTEX) > 0.0001 ? normalize(VERTEX) : NORMAL;
	vec3 smooth_normal = normalize(NORMAL + radial * 0.35);
	VERTEX += smooth_normal * local_thickness;
}

void fragment() {
	float pulse = 0.90 + 0.10 * sin(TIME * pulse_speed);
	ALBEDO = outline_color.rgb * pulse;
	ALPHA = outline_color.a;
}
