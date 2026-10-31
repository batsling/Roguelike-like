// THE GREY BAT PATTERN: one bat (images2.0/custom/menu_bat.png, the owner's own
// bat averaged from their pattern) repeated on the pattern's diagonal lattice and
// drifting from the top right to the bottom left, in two dark greys. Drawn by
// hand rather than tiled because the pattern it was taken from did not tile; the
// lattice vectors are measured off it. Served by UITheme.bat_backdrop(), which
// keeps `size` current; the Collection and the run page stand on it.
shader_type canvas_item;

uniform sampler2D bat : filter_linear;
uniform vec2 b1 = vec2(-105.6, 36.5);   // lattice, px: down-left
uniform vec2 b2 = vec2(84.5, 71.0);     // and down-right
uniform vec2 speed = vec2(-18.0, 12.0); // top right to bottom left, px/s
uniform vec4 base : source_color = vec4(0.231, 0.227, 0.224, 1.0);
uniform vec4 ink : source_color = vec4(0.184, 0.180, 0.176, 1.0);
uniform vec2 size = vec2(1280.0, 720.0);
uniform float bat_px = 109.0;

void fragment() {
	vec2 p = UV * size - speed * TIME;
	mat2 m = mat2(b1, b2);
	vec2 local = m * (fract(inverse(m) * p) - 0.5);   // offset from the nearest bat
	float a = 0.0;
	// A bat is wider than a lattice cell, so its neighbours reach in too.
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 uv = (local - m * vec2(float(i), float(j))) / bat_px + 0.5;
			if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0)
				a = max(a, texture(bat, uv).a);
		}
	}
	float glow = 1.0 - 0.25 * length(UV - vec2(0.55, 0.45));
	COLOR = vec4(mix(base.rgb, ink.rgb, a) * glow, 1.0);
}
