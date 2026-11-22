shader_type canvas_item;
// Card body and frame, drawn procedurally so it stays crisp at every size: a soft glow outside the
// card (playable / hovered / selected), a bevelled dark-metal border, a thin rim in the owner's
// colour, and a colour-graded body with a faint engraved lattice and grain. Epic cards get a slow
// shimmer along the border; `dissolve` burns the card away with a glowing edge (exhaust).

uniform vec2 rect_size = vec2(352.0, 480.0);   // size of the ColorRect (card + 2 * margin)
uniform float margin = 26.0;                   // glow room around the card
uniform float radius = 22.0;
uniform float border = 14.0;
uniform vec4 border_dark : source_color = vec4(0.10, 0.10, 0.13, 1.0);
uniform vec4 border_light : source_color = vec4(0.62, 0.56, 0.44, 1.0);
uniform vec4 rim_color : source_color = vec4(0.83, 0.65, 0.29, 1.0);
uniform vec4 body_top : source_color = vec4(0.16, 0.20, 0.34, 1.0);
uniform vec4 body_bottom : source_color = vec4(0.05, 0.06, 0.11, 1.0);
uniform vec4 glow_color : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform float glow = 0.0;
uniform float glow_pulse = 0.0;                // 0..1: how much the glow breathes
uniform float desaturate = 0.0;
uniform float darken = 0.0;
uniform float shimmer = 0.0;
uniform float dissolve = 0.0;
uniform vec4 dissolve_edge : source_color = vec4(1.0, 0.55, 0.15, 1.0);

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 grade(vec3 c) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate);
	return c * (1.0 - darken);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 center = rect_size * 0.5;
	vec2 half_card = center - vec2(margin);
	vec2 local = p - center;
	float d = sd_round_box(local, half_card, radius);
	float aa = max(fwidth(d), 0.75);
	vec4 result = vec4(0.0);

	// Outer glow.
	if (glow > 0.0) {
		float breathe = 1.0 - glow_pulse * 0.35 * (0.5 + 0.5 * sin(TIME * 3.2));
		float g = glow * breathe * exp(-max(d, 0.0) / (margin * 0.38));
		result = vec4(glow_color.rgb, glow_color.a * g * smoothstep(-aa, aa, d));
	}

	vec2 n = local / half_card;
	// Border: brushed dark metal with a bevel lit from the top left.
	float in_card = 1.0 - smoothstep(-aa, aa, d);
	float t_border = clamp(-d / border, 0.0, 1.0);
	float bevel = clamp(0.5 - 0.5 * dot(normalize(local + vec2(0.001)), normalize(vec2(0.55, 0.85))), 0.0, 1.0);
	vec3 metal = mix(border_dark.rgb, border_light.rgb, 0.25 + 0.55 * bevel * (1.0 - t_border) + 0.12 * noise(p * vec2(0.08, 1.2)));
	metal *= 0.82 + 0.25 * (1.0 - abs(t_border * 2.0 - 1.0));
	// Rim in the owner's colour at the inner edge of the border, with a fine dark line inside it.
	float rim = smoothstep(border - 3.6, border - 2.2, -d) * (1.0 - smoothstep(border - 0.2, border + 1.0, -d));
	float inner_line = smoothstep(border + 0.4, border + 1.2, -d) * (1.0 - smoothstep(border + 1.8, border + 2.8, -d));

	// Body: vertical grade, vignette, a faint engraved lattice and grain.
	vec3 body = mix(body_top.rgb, body_bottom.rgb, smoothstep(0.0, 1.0, UV.y));
	float vignette = smoothstep(1.25, 0.35, length(n * vec2(0.9, 0.75)));
	body *= 0.62 + 0.38 * vignette;
	vec2 lattice = abs(fract((local + vec2(local.y, -local.x) * 1.0) / 26.0) - 0.5);
	float lines = smoothstep(0.47, 0.5, max(lattice.x, lattice.y));
	body += lines * 0.025;
	body += (noise(p * 0.9) - 0.5) * 0.035;

	vec3 col = body;
	col = mix(col, metal, smoothstep(border - 2.6, border - 3.6, -d));
	col = mix(col, rim_color.rgb * (0.9 + 0.3 * bevel), rim);
	col = mix(col, vec3(0.85, 0.69, 0.38) * (0.75 + 0.25 * bevel), inner_line * 0.75);

	// Epic shimmer: a bright band sweeping along the border.
	if (shimmer > 0.0) {
		float band = smoothstep(0.92, 1.0, sin((n.x + n.y) * 2.2 - TIME * 1.6) * 0.5 + 0.5);
		col += shimmer * band * (1.0 - t_border * 0.8) * vec3(0.9, 0.7, 1.0) * step(-border, d) * 0.6;
	}

	col = grade(col);
	vec4 card = vec4(col, in_card);

	// Dissolve (exhaust): noise threshold with a glowing edge.
	if (dissolve > 0.0) {
		float burn = noise(p * 0.045) * 0.75 + noise(p * 0.2) * 0.25;
		float edge = smoothstep(dissolve - 0.08, dissolve, burn);
		float keep = step(dissolve, burn);
		card.rgb = mix(dissolve_edge.rgb * 1.6, card.rgb, edge);
		card.a *= keep;
	}

	// Card over glow.
	COLOR = vec4(mix(result.rgb, card.rgb, card.a), card.a + result.a * (1.0 - card.a));
}
