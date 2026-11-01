shader_type canvas_item;

// A logo whose letters are still to be earned (LogoProgress): greyscale, its
// shape and transparency kept, so the whole title can still be read. Its shades
// are squeezed into a narrow band of mid grey rather than dimmed, and it is made
// partly see-through: dimming left a black-ink logo (Darkest Dungeon) black, so
// an earned black letter laid on it looked no different from a locked one.
uniform float floor_grey : hint_range(0.0, 1.0) = 0.26;
uniform float spread : hint_range(0.0, 1.0) = 0.22;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(floor_grey + g * spread), c.a * opacity);
}
