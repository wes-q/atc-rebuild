shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;
// Faint 100-unit grid so motion reads on the plane. Not original art.
void fragment() {
	vec2 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 g = abs(fract(w / 100.0 - 0.5) - 0.5) / fwidth(w / 100.0);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	ALBEDO = vec3(0.15, 0.4, 0.7) * line * 0.35;
}
