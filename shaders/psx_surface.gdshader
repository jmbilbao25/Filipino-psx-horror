shader_type spatial;

// PSX surface. Per-vertex light (no per-pixel shading existed on the console),
// no specular, no ambient floor so unlit geometry reaches #000000.
// cull_disabled is global on purpose: leaf/thatch cards need to be two-sided and
// closed meshes hide their backfaces with depth anyway, so one shader covers both.
// Per-pixel light, NOT vertex_lighting. Checked against the reference footage:
// Nun Massacre's lantern and candle pools have smooth elliptical falloff, so the
// era feel there comes from low resolution + dither + affine UVs + vertex snap,
// not from Gouraud. Vertex lighting also made a 14-degree flashlight invisible on
// a 2.2 m ground grid, because the pool landed between vertices.
render_mode specular_disabled, diffuse_lambert, ambient_light_disabled, cull_disabled;

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float emit = 0.0;
// Clip-space quantisation grid. NDC is -1..1, so 160x90 == the 320x180 pixel
// grid of the render target: vertices land on whole pixels and visibly wobble.
uniform vec2 snap = vec2(160.0, 90.0);
uniform float uv_scale = 1.0;

// Affine (perspective-incorrect) texture mapping: premultiplying by w cancels
// the hardware's perspective divide, so the varying interpolates linearly in
// screen space exactly like the PSX GTE did.
varying vec3 v_uvw;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (clip.w > 0.0) {
		clip.xy = round(clip.xy / clip.w * snap) / snap * clip.w;
	}
	POSITION = clip;
	v_uvw = vec3(UV * uv_scale * clip.w, clip.w);
}

void fragment() {
	vec3 c = texture(tex, v_uvw.xy / v_uvw.z).rgb * tint.rgb;
	ALBEDO = c;
	EMISSION = c * emit;
}
