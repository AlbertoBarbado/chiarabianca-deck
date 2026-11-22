shader_type canvas_item;
// Glowing silhouette outline drawn behind a battlefield sprite (CombatUnitView). The rect is larger
// than the sprite by `margin_uv` on each side, so the outline is never clipped by the picture edge.

uniform vec4 outline_color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float outline_width = 0.0;   // texture pixels
uniform vec2 margin_uv = vec2(0.0);

float alpha_at(sampler2D tex, vec2 p) {
	if (p.x < 0.0 || p.y < 0.0 || p.x > 1.0 || p.y > 1.0) {
		return 0.0;
	}
	return texture(tex, p).a;
}

void fragment() {
	if (outline_width <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = (UV - margin_uv) / (vec2(1.0) - 2.0 * margin_uv);
		float near = 0.0;
		for (int i = 0; i < 16; i++) {
			float angle = float(i) * 0.3927;
			vec2 offset = vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE * outline_width;
			near = max(near, alpha_at(TEXTURE, uv + offset));
			near = max(near, alpha_at(TEXTURE, uv + offset * 0.5) * 0.9);
		}
		float inside = alpha_at(TEXTURE, uv);
		COLOR = vec4(outline_color.rgb, outline_color.a * clamp(near * 1.6, 0.0, 1.0) * (1.0 - inside) * COLOR.a);
	}
}
