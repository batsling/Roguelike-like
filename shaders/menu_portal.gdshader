// THE MAIN MENU'S PORTAL: a blue swirl behind the title and subtitle, bright in
// the middle so the darker cut letters (Isaac's black, the brown K and E) still
// read over the red rift behind it. One oval round both lines, fading out at
// its edge, where MenuPortal's bats take over the blend into the red.
// Set on a ColorRect by MenuPortal.gd, which keeps `px` at the rect's size.
//
// The noise is rift_swirl.gdshader's, so the two read as the same stuff.
shader_type canvas_item;

uniform vec4 rim : source_color = vec4(0.40, 0.92, 0.88, 1.0);
uniform vec4 core : source_color = vec4(0.82, 1.0, 0.98, 1.0);
uniform vec4 deep : source_color = vec4(0.08, 0.38, 0.42, 1.0);
uniform vec2 px = vec2(1000.0, 200.0);
uniform float speed = 0.06;   // MainMenu sets it to SWIRL_SPEED, the rift's own
// Alpha starts falling here, 1 being the oval's edge.
uniform float edge_in = 0.8;
// The least the middle is lit, so no letter ever sits on the dark of the swirl.
uniform float floor_bright = 0.55;

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
	vec2 c = UV - 0.5;
	float d = length(c * 2.0);          // 1 on the oval's edge
	vec2 p = c * px / 90.0;             // the swirl at one scale whatever the size
	float t = TIME * speed;
	float ang = 1.8 * (1.0 - d) + t * 2.0;
	p = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang))) * p;
	vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3 - t)));
	float n = fbm(p + 3.0 * q);
	vec3 col = mix(deep.rgb, rim.rgb, smoothstep(0.25, 0.7, n));
	float hot = max(floor_bright, smoothstep(0.35, 0.8, n)) * smoothstep(1.0, 0.15, d);
	col = mix(col, core.rgb, hot);
	COLOR = vec4(col, smoothstep(1.0, edge_in, d));
}
