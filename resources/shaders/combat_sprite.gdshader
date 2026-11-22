shader_type canvas_item;
// Battlefield unit sprite (CombatUnitView). Presentation only; every effect defaults to "off".
//   flash      : whole-sprite colour flash (hits = white/red, heals = green, blocks = blue)
//   (the glowing outline is a separate layer: combat_outline.gdshader)
//   rim        : light catching one side of the silhouette, coloured by the battle backdrop
//   ambient    : multiplies the sprite so it sits in the backdrop's light
//   saturation : 0 = grey (fallen party member)
//   dissolve   : 0..1 burns the sprite away from the noise with a glowing edge (death)

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_amount : hint_range(0.0, 2.0) = 0.0;
uniform vec2 rim_direction = vec2(-0.7, -0.7); // where the light comes from (unit vector, UV space)
uniform float rim_width = 5.0;              // texture pixels
uniform vec4 ambient : source_color = vec4(1.0);
uniform float saturation : hint_range(0.0, 1.5) = 1.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_edge : source_color = vec4(1.0, 0.6, 0.25, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.15;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec4 c = COLOR;  // in Godot 4 the fragment COLOR already is texture x modulate (do not multiply again)
	vec2 px = TEXTURE_PIXEL_SIZE;

	// Rim light: the sprite is lit where the alpha drops off toward the light.
	if (rim_amount > 0.0 && tex.a > 0.05) {
		float behind = texture(TEXTURE, UV + rim_direction * px * rim_width).a;
		float rim = clamp(tex.a - behind, 0.0, 1.0);
		c.rgb += rim_color.rgb * rim * rim_amount;
	}
	c.rgb *= ambient.rgb;

	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(grey), c.rgb, saturation);

	c.rgb = mix(c.rgb, flash_color.rgb, flash_amount * tex.a);

	// Dissolve with an ember edge.
	if (dissolve > 0.0) {
		float n = fbm(UV * 9.0) * 0.85 + (1.0 - UV.y) * 0.15;
		float cut = dissolve * 1.12;
		if (n < cut - 0.08) {
			c.a = 0.0;
		} else if (n < cut) {
			float edge = (n - (cut - 0.08)) / 0.08;
			c.rgb = mix(dissolve_edge.rgb * 1.6, c.rgb, edge * edge);
		}
	}
	COLOR = c;
}
