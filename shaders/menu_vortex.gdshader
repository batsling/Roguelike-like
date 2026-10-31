// THE MAIN MENU'S VORTEX: the red rift across the whole screen and the blue
// portal the title stands in, drawn as ONE swirl. They used to be two shaders,
// a full-screen rift and an oval laid over it, which turned at their own rates
// and met at a seam; here both colours are read off the same field, so a fold
// of the red runs on into the blue, and the whole of it turns and is drawn
// inward toward the portal's middle.
//
// Set on the menu's %Background by MainMenu._paint_vortex; MenuPortal writes the
// portal's oval (`portal_center`, `portal_radii`, px) whenever the title moves,
// and MainMenu keeps `size` at the background's.
//
// THE INWARD FLOW is the noise sampled at a scale that grows with time, which
// carries every feature toward the middle. A scale cannot grow forever, so it is
// two copies half a cycle apart, each growing from 1x to 2x and faded out at the
// moment it jumps back: the classic endless zoom.
//
// The noise and the colour rules are rift_swirl.gdshader's (the rift cards'),
// so the menu reads as the same stuff as a rift on the map.
shader_type canvas_item;

uniform vec2 size = vec2(1280.0, 720.0);
uniform vec2 portal_center = vec2(640.0, 360.0);
uniform vec2 portal_radii = vec2(0.0, 0.0);   // zero: no portal, all red

// The red rift.
uniform vec4 rift_color : source_color = vec4(1.0, 0.36, 0.30, 1.0);
uniform vec4 deep_color : source_color = vec4(0.36, 0.03, 0.06, 1.0);
uniform vec4 base_color : source_color = vec4(0.06, 0.02, 0.02, 1.0);
// The blue portal.
uniform vec4 rim : source_color = vec4(0.40, 0.92, 0.88, 1.0);
uniform vec4 core : source_color = vec4(0.82, 1.0, 0.98, 1.0);
uniform vec4 deep : source_color = vec4(0.08, 0.38, 0.42, 1.0);

uniform float speed = 0.045;      // the turn
uniform float inflow = 0.035;     // zoom cycles a second: the pull inward
uniform float twist = 2.6;
// Of the portal's radii: blue from here in, red past 1.
uniform float edge_in = 0.8;
// The portal's shape: 2 is an ellipse; higher is squarer, a rounded rectangle
// that reaches into the corners of the text an ellipse leaves out. MenuPortal
// sets it (ROUNDNESS) so its bats leave the same edge.
uniform float roundness = 3.0;
// The least the portal's middle is lit, so no letter sits on its dark.
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

// The warped field at `p`, and how strongly it folds (for the red's filaments).
vec2 field(vec2 p, float t) {
	vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3 - t)));
	vec2 w = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2)), fbm(p + 3.0 * q + vec2(8.3, 2.8)));
	return vec2(fbm(p + 3.5 * w), length(q));
}

void fragment() {
	vec2 rel = UV * size - portal_center;
	// One frame for the whole screen, centred on the portal and the same scale
	// both ways, so the vortex is round and its eye is the portal's middle.
	vec2 uv = rel / size.y;
	float r = length(uv);
	float t = TIME * speed;
	float ang = twist * (0.75 - r) + t * 2.0;
	vec2 p = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang))) * uv * 3.0;

	// The endless zoom inward: two layers half a cycle apart.
	vec2 f = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		float ph = fract(TIME * inflow + 0.5 * float(k));
		float wgt = 1.0 - abs(2.0 * ph - 1.0);
		f += wgt * field(p * exp2(ph) + vec2(float(k) * 17.3), t);
	}
	float n = f.x;
	float fold = f.y;

	vec3 red = mix(base_color.rgb, deep_color.rgb, smoothstep(0.15, 0.65, n));
	red = mix(red, rift_color.rgb, smoothstep(0.55, 0.85, n) * (0.55 + 0.45 * fold));

	if (portal_radii.x <= 0.0 || portal_radii.y <= 0.0) {
		COLOR = vec4(red, 1.0);
	} else {
		vec2 e = abs(rel / portal_radii);
		float d = pow(pow(e.x, roundness) + pow(e.y, roundness), 1.0 / roundness);   // 1 on the rim
		vec3 blue = mix(deep.rgb, rim.rgb, smoothstep(0.25, 0.7, n));
		float hot = max(floor_bright, smoothstep(0.35, 0.8, n)) * smoothstep(1.0, 0.15, d);
		blue = mix(blue, core.rgb, hot);
		// The rim follows the field, so the blue reaches out along the same folds
		// the red comes in on rather than ending on a clean line.
		float inside = smoothstep(1.0, edge_in, d + (n - 0.5) * 0.35);
		COLOR = vec4(mix(red, blue, inside), 1.0);
	}
}
