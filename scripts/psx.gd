class_name Psx
## API contract only — the shader piece implements the bodies.
## Everything that needs a surface calls Psx.mat() and nothing else, so the
## whole look can be changed in one file.

## Procedural PSX surface. `kind` picks the generated texture:
## "dirt" "wood" "thatch" "concrete" "rust" "bamboo" "leaf" "cloth" "skin"
## "metal" "glass" "cloth_dark"
static func mat(kind: StringName, tint: Color = Color.WHITE) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if kind == &"leaf" or kind == &"thatch":
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
