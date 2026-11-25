// Neutral ground grid with anti-aliased lines (1 m major cells by default).
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.40, 0.41, 0.42);
uniform vec3 minor_line_color : source_color = vec3(0.34, 0.35, 0.36);
uniform vec3 major_line_color : source_color = vec3(0.26, 0.27, 0.28);
uniform vec3 x_axis_color : source_color = vec3(0.70, 0.28, 0.28);
uniform vec3 z_axis_color : source_color = vec3(0.28, 0.40, 0.75);
uniform float minor_cell = 0.25;
uniform float major_cell = 1.0;

varying vec3 world_pos;

float grid_line(vec2 p, float cell) {
	vec2 coord = p / cell;
	vec2 g = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), vec2(1e-4));
	return 1.0 - min(min(g.x, g.y), 1.0);
}

float axis_line(float v) {
	return 1.0 - min(abs(v) / max(fwidth(v) * 1.5, 1e-4), 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 col = base_color;
	col = mix(col, minor_line_color, grid_line(p, minor_cell));
	col = mix(col, major_line_color, grid_line(p, major_cell));
	col = mix(col, x_axis_color, axis_line(world_pos.z));
	col = mix(col, z_axis_color, axis_line(world_pos.x));
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
