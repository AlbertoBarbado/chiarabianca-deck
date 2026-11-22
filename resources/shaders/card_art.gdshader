shader_type canvas_item;
// The card's illustration window. Its silhouette tells the card type at a glance:
//   0 skill / defense / support: rounded rectangle
//   1 attack: rectangle with chamfered bottom corners (a blade's point)
//   2 spell: arched top
//   3 power: oval
// A gold border, an inner shadow and a soft top light frame the picture. The texture is drawn
// cover-fitted: uv_min / uv_max give the visible region of the texture.

uniform vec2 rect_size = vec2(252.0, 156.0);
uniform int shape = 0;
uniform vec2 uv_min = vec2(0.0);
uniform vec2 uv_max = vec2(1.0);
uniform float edge = 5.5;
uniform vec4 border_color : source_color = vec4(0.95, 0.80, 0.45, 1.0);
uniform vec4 border_shadow : source_color = vec4(0.25, 0.17, 0.06, 1.0);
uniform float desaturate = 0.0;
uniform float darken = 0.0;

float sd_round_box(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float shape_sdf(vec2 p, vec2 h) {
	float box = sd_round_box(p, h, 9.0);
	if (shape == 1) {
		float c = h.y * 0.42;
		float chamfer = ((abs(p.x) + p.y) - (h.x + h.y - c)) * 0.70710678;
		return max(sd_round_box(p, h, 6.0), chamfer);
	}
	if (shape == 2) {
		float arch_h = h.y * 0.55;
		float cy = -h.y + arch_h;
		if (p.y < cy) {
			float e = (length(vec2(p.x / h.x, (p.y - cy) / arch_h)) - 1.0) * min(h.x, arch_h);
			return max(sd_round_box(p, h, 6.0), e);
		}
		return sd_round_box(p, h, 6.0);
	}
	if (shape == 3) {
		return (length(p / h) - 1.0) * min(h.x, h.y);
	}
	return box;
}

void fragment() {
	vec2 local_uv = (UV - uv_min) / max(uv_max - uv_min, vec2(0.0001));
	vec2 p = (local_uv - 0.5) * rect_size;
	vec2 h = rect_size * 0.5;
	float d = shape_sdf(p, h);
	float aa = max(fwidth(d), 0.75);
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = tex.rgb;
	// Top light and inner shadow.
	col *= 0.9 + 0.18 * (1.0 - local_uv.y);
	col *= mix(0.55, 1.0, smoothstep(0.0, 14.0, -d));
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(l), desaturate) * (1.0 - darken);
	// Gold border with a darker outer line.
	float b = 1.0 - smoothstep(edge - aa, edge + aa, -d);
	vec3 gold = mix(border_shadow.rgb, border_color.rgb, smoothstep(0.0, edge, -d) * 0.7 + 0.3 * (1.0 - local_uv.y));
	col = mix(col, gold * (1.0 - darken), b);
	float alpha = 1.0 - smoothstep(-aa, aa, d);
	COLOR = vec4(col, alpha);
}
