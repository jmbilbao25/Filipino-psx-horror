shader_type canvas_item;
render_mode unshaded;

// Post chain: dither -> posterise -> scanlines -> chromatic aberration -> grain
// -> vignette -> CRT border. Aberration is done at sample time because it *is*
// a sampling operation; everything after the sample keeps the listed order, so
// dithering still happens before quantisation (the trait that matters).

uniform float tension : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cast_rest : source_color = vec3(1.10, 1.00, 0.60);  // warm amber/olive
uniform vec3 cast_tense : source_color = vec3(1.30, 0.55, 0.42); // toward red
uniform float levels = 18.0;      // < 5 bits/channel
uniform float dither = 1.6;       // in quantisation steps
uniform float scanline = 0.34;
uniform float aberration = 0.0020;
uniform float grain = 0.055;
uniform float vignette = 0.62;
uniform float border = 0.055;     // black inset, in screen heights
uniform float corner = 0.070;     // border corner radius

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = 1.0 / SCREEN_PIXEL_SIZE;          // output resolution
	float asp = px.x / px.y;
	vec2 d = UV - 0.5;
	float r2 = dot(d, d) * 4.0;                 // 0 centre .. ~1+ edges

	// -- chromatic aberration, stronger toward the frame edges
	float ca = aberration * (0.35 + r2) * (1.0 + 2.5 * tension);
	vec3 col = vec3(
		texture(TEXTURE, UV + d * ca).r,
		texture(TEXTURE, UV).g,
		texture(TEXTURE, UV - d * ca).b
	);

	// -- colour cast. The 3D pass is LDR, so a flat multiply would cap the blue
	// channel and no highlight could ever reach white; fade the cast out at the
	// top end instead, which is what the reference light pools do.
	float l = max(col.r, max(col.g, col.b));
	col *= mix(mix(cast_rest, cast_tense, tension), vec3(1.0), smoothstep(0.84, 1.0, l));

	// -- ordered 4x4 Bayer dither, then posterise
	vec2 dp = mod(floor(UV * px), 4.0);
	float b = BAYER[int(dp.y) * 4 + int(dp.x)] / 16.0 - 0.46875;
	col = floor(col * levels + b * dither) / levels;

	// -- scanlines + a slow horizontal tape band
	// 240 lines, fixed: independent of output resolution, so no moire on upscale
	col *= 1.0 - scanline * step(1.0, mod(floor(UV.y * 240.0), 2.0));
	float band = smoothstep(0.965, 1.0, fract(UV.y * 1.7 - TIME * 0.09));
	col += band * 0.05;

	// -- animated grain, chunky (locked to the 320x180 grid)
	// gated on signal so dead-black regions stay exactly #000000
	vec2 gp = floor(UV * vec2(320.0, 180.0));
	float lit = smoothstep(0.0, 0.03, max(col.r, max(col.g, col.b)));
	col += (hash(gp + fract(TIME) * 91.7) - 0.5) * grain * lit * (1.0 + 2.0 * tension);

	// -- vignette
	col *= clamp(1.0 - vignette * pow(r2, 2.2), 0.0, 1.0);

	// -- CRT border: rounded rect, hard edge, corners fully black
	vec2 p = vec2(d.x * asp, d.y);
	vec2 h = vec2(0.5 * asp, 0.5) - border - corner;
	vec2 q = abs(p) - h;
	float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner;
	col *= step(sd, 0.0);

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
