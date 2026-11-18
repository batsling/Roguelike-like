// A COVER YOU HAVEN'T SEEN, PIXELATED (Collection's UNSEEN_COVER "pixel"): the
// picture averaged down to `cells` blocks across, like a Gamedle cover before a
// guess. Each block is ONE mip sample at the level whose texel is a block, so
// a block is the average of the art under it rather than one pixel picked out
// of it. Needs the texture imported with mipmaps, which every picture here is
// (project.godot [importer_defaults]).
shader_type canvas_item;

uniform float cells = 8.0;
uniform float dim = 0.85;

void fragment() {
	vec2 tex = vec2(textureSize(TEXTURE, 0));
	vec2 grid = vec2(cells, max(1.0, floor(cells * tex.y / tex.x)));
	vec2 uv = (floor(UV * grid) + 0.5) / grid;
	float lod = log2(max(tex.x / grid.x, 1.0));
	vec4 c = textureLod(TEXTURE, uv, lod);
	COLOR = vec4(c.rgb * dim, c.a);
}
