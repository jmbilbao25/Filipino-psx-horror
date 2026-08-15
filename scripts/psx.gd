class_name Psx
## Procedural PSX surfaces. Everything that needs a surface calls Psx.mat() and
## nothing else, so the whole look can be changed in one file.
##
## Materials are cached and SHARED per (kind, tint). Call duplicate() before
## touching shader params (e.g. uv_scale) on one instance only.

const SHADER := "res://shaders/psx_surface.gdshader"
const SIZE := 32

# kind -> [base colour, noise, stripe axis (0 none / 1 vertical / 2 horizontal),
#          stripe strength, stripe period px, emission]
const KINDS := {
	&"dirt": [Color(0.34, 0.26, 0.17), 0.40, 0, 0.0, 4, 0.0],
	&"wood": [Color(0.42, 0.28, 0.16), 0.22, 1, 0.30, 8, 0.0],
	&"thatch": [Color(0.55, 0.44, 0.22), 0.32, 2, 0.35, 3, 0.0],
	&"concrete": [Color(0.52, 0.50, 0.45), 0.18, 0, 0.0, 4, 0.0],
	&"rust": [Color(0.46, 0.24, 0.12), 0.45, 2, 0.20, 6, 0.0],
	&"bamboo": [Color(0.52, 0.50, 0.26), 0.20, 1, 0.28, 6, 0.0],
	&"leaf": [Color(0.16, 0.34, 0.14), 0.30, 2, 0.30, 5, 0.0],
	&"cloth": [Color(0.62, 0.58, 0.52), 0.16, 1, 0.14, 2, 0.0],
	&"cloth_dark": [Color(0.16, 0.15, 0.18), 0.22, 1, 0.16, 2, 0.0],
	&"skin": [Color(0.72, 0.56, 0.44), 0.10, 0, 0.0, 4, 0.0],
	&"metal": [Color(0.44, 0.46, 0.50), 0.14, 1, 0.22, 8, 0.0],
	&"glass": [Color(0.60, 0.66, 0.70), 0.12, 0, 0.0, 4, 3.0],
}

static var _mats: Dictionary = {}
static var _texs: Dictionary = {}


## Procedural PSX surface. `kind` picks the generated texture:
## "dirt" "wood" "thatch" "concrete" "rust" "bamboo" "leaf" "cloth" "skin"
## "metal" "glass" "cloth_dark"
static func mat(kind: StringName, tint: Color = Color.WHITE) -> Material:
	var key := "%s|%s" % [kind, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("tex", _tex(kind))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("emit", float(_params(kind)[5]))
	_mats[key] = m
	return m


static func _params(kind: StringName) -> Array:
	return KINDS.get(kind, KINDS[&"concrete"])


## 32x32, nearest, no mipmaps (filter comes from the shader's sampler hint).
static func _tex(kind: StringName) -> ImageTexture:
	if _texs.has(kind):
		return _texs[kind]
	var p := _params(kind)
	var base: Color = p[0]
	var nz: float = p[1]
	var axis: int = p[2]
	var st: float = p[3]
	var period: int = p[4]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			# fine speckle + chunky 4px blotches
			var v := 1.0 + rng.randf_range(-nz, nz)
			v *= 1.0 + (float(hash(Vector2i(x >> 2, y >> 2)) % 997) / 997.0 - 0.5) * nz
			if axis == 1:
				v *= 1.0 - st * float((x / period) % 2)
				if x % (period * 2) == 0:
					v *= 1.0 - st
			elif axis == 2:
				v *= 1.0 - st * float((y / period) % 2)
				if y % (period * 2) == 0:
					v *= 1.0 - st
			img.set_pixel(x, y, Color(base.r * v, base.g * v, base.b * v).clamp())
	var t := ImageTexture.create_from_image(img)
	_texs[kind] = t
	return t
