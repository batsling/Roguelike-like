// THE RIFT BACKDROP (docs/rifts-design.md §9): a swirl of domain-warped noise in
// the rift colours, drifting slowly, drawn behind a rift game's cover wherever a
// card for one is shown. Built in UITheme.rift_backdrop(), which sets the colours
// from UITheme.RIFT / RIFT_DEEP so the palette has one home.
//
// Domain warping (noise fed its own output as an offset) is what gives the
// marbled, folded look; the twist around the centre is what makes it read as a
// vortex rather than as smoke. Kept cheap on purpose: three cards share a row and
// each one runs this per pixel every frame.
shader_type canvas_item;

uniform vec4 rift_color : source_color = vec4(0.40, 0.92, 0.88, 1.0);
uniform vec4 deep_color : source_color = vec4(0.20, 0.08, 0.34, 1.0);
uniform vec4 base_color : source_color = vec4(0.05, 0.03, 0.09, 1.0);
uniform float speed = 0.06;
uniform float twist = 2.6;
// A per-card offset, so three rift cards in a row don't swirl in lockstep.
uniform float seed = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv);
	float t = TIME * speed + seed;
	// The vortex: spin each ring by an amount that grows toward the middle.
	float ang = twist * (0.75 - r) + t * 2.0;
	float c = cos(ang);
	float s = sin(ang);
	vec2 p = mat2(vec2(c, -s), vec2(s, c)) * uv * 3.0;
	// Two passes of domain warping.
	vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3 - t)));
	vec2 w = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2)), fbm(p + 3.0 * q + vec2(8.3, 2.8)));
	float n = fbm(p + 3.5 * w);
	vec3 col = mix(base_color.rgb, deep_color.rgb, smoothstep(0.15, 0.65, n));
	// Bright filaments where the warped field folds over itself.
	float fil = smoothstep(0.55, 0.85, n) * (0.55 + 0.45 * length(q));
	col = mix(col, rift_color.rgb, fil);
	COLOR = vec4(col, 1.0);
}
