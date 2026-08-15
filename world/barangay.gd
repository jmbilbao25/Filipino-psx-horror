class_name Barangay
extends Node3D
## One enclosed barangay at night. 100% procedural: every mesh is a Godot
## primitive (optionally merged with SurfaceTool) and every surface is Psx.mat().
##
## Shape of the level: a dirt road is the spine (north -> south). The player
## spawns at the north end and the kapilya is at the south end. Huts, fences and
## trees flank the road so sightlines break constantly. Exactly one sodium lamp
## works; everything else is fog-silhouette black.
##
## psx_surface.gdshader lights PER VERTEX, like the console did. So every surface
## a light pool has to land on is a subdivided plane, never one big quad: a 4-vert
## 60 m slab samples the light only at its corners and stays black. Walls stay as
## boxes on purpose - big Gouraud gradients are the look.

const R := 30.0 ## half-extent of the walkable map

# Warm amber/olive palette. REFERENCE: never neutral grey.
const C_DIRT := Color(0.62, 0.52, 0.34)
const C_ROAD := Color(0.80, 0.66, 0.42)
const C_RUT := Color(0.45, 0.35, 0.22)
const C_WOOD := Color(0.72, 0.56, 0.34)
const C_BAMBOO := Color(0.86, 0.78, 0.48)
const C_THATCH := Color(0.84, 0.66, 0.34)
const C_CONC := Color(0.68, 0.66, 0.58)
const C_COURT := Color(0.90, 0.87, 0.76)
const C_CHAPEL := Color(1.00, 0.95, 0.80)
const C_RUST := Color(0.74, 0.44, 0.26)
const C_METAL := Color(0.40, 0.40, 0.44)
const C_LEAF := Color(0.52, 0.78, 0.42)
const C_LEAF2 := Color(0.66, 0.86, 0.44)
const C_CLOTH := Color(0.90, 0.86, 0.74)
const C_CLOTH2 := Color(0.34, 0.32, 0.40)
const C_BULB := Color(1.00, 0.72, 0.30)
const C_PANE := Color(1.00, 0.70, 0.32)
const C_DEAD := Color(0.10, 0.10, 0.11)
const LAMP_E := 13.0

# --- contract ---------------------------------------------------------------
var player_start := Transform3D(Basis(), Vector3(0.0, 0.0, 26.0))
var charm_spots: Array[Vector3] = []
var chapel_door := Vector3(0.0, 0.0, -20.6)
var patrol_points: Array[Vector3] = []
var nav_region: NavigationRegion3D

var _rng := RandomNumberGenerator.new()
var _cache := {}
var _lamp: SpotLight3D
var _glow: OmniLight3D
var _t := 0.0
var _mm: Dictionary = {}
var _occupied: Array[Vector3] = []  ## building footprints, so trees dodge them


func build(rng_seed: int = 0) -> void:
	_rng.seed = rng_seed
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)

	_ground()
	_huts()
	_store(Vector3(-8.5, 0.0, 17.0), -PI * 0.5)
	_occupied.append(Vector3(-8.5, 0.0, 17.0))
	_chapel(Vector3(0.0, 0.0, -26.0))
	_court(Vector3(14.5, 0.0, 21.5))
	_fences()
	_trees()
	_power_and_laundry()
	_lamps()
	_walls()
	_flush_mm()

	player_start = Transform3D(Basis(), Vector3(0.0, 0.0, 26.0))
	chapel_door = Vector3(0.0, 0.0, -20.6)
	charm_spots = [
		Vector3(-22.5, 0.5, 6.5),   # west, beside the far huts
		Vector3(20.0, 0.6, 24.5),   # north-east, on the basketball court
		Vector3(14.0, 0.5, -26.5),  # south-east, behind the last huts
	]
	patrol_points = [
		Vector3(0, 0, 24), Vector3(0, 0, 10), Vector3(0, 0, -4), Vector3(0, 0, -18),
		Vector3(-14, 0, 21), Vector3(-15, 0, -9), Vector3(-24, 0, -20),
		Vector3(14, 0, -21), Vector3(14.5, 0, 21.5), Vector3(25, 0, 10),
		Vector3(7, 0, -26), Vector3(-6, 0, -23),
	]
	_bake_nav()


# --- primitive helpers ------------------------------------------------------
## Cached so hundreds of identical boxes share one resource.
func _res(key: String, maker: Callable) -> Variant:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


## `uvs` tiles the 32x32 procedural texture. Godot primitives put UV 0..1 across
## a whole face, so without this a 5 m wall shows one giant smeared texel.
func _m(kind: StringName, tint: Color, uvs := 1.0) -> Material:
	return _res("m%s%s%.2f" % [kind, tint, uvs], func():
		var m := Psx.mat(kind, tint)
		if is_equal_approx(uvs, 1.0) or not m is ShaderMaterial:
			return m
		var d: ShaderMaterial = m.duplicate()
		d.set_shader_parameter("uv_scale", uvs)
		return d)


func _box(x: float, y: float, z: float) -> BoxMesh:
	return _res("b%.3f_%.3f_%.3f" % [x, y, z], func():
		var b := BoxMesh.new()
		b.size = Vector3(x, y, z)
		return b)


## Horizontal surface tessellated to `cell` metres, because light is per-vertex.
func _plane(w: float, d: float, cell: float) -> PlaneMesh:
	return _res("p%.2f_%.2f_%.2f" % [w, d, cell], func():
		var p := PlaneMesh.new()
		p.size = Vector2(w, d)
		p.subdivide_width = maxi(0, int(w / cell) - 1)
		p.subdivide_depth = maxi(0, int(d / cell) - 1)
		return p)


func _cyl(rb: float, rt: float, h: float, seg := 6) -> CylinderMesh:
	return _res("c%.3f_%.3f_%.3f_%d" % [rb, rt, h, seg], func():
		var c := CylinderMesh.new()
		c.bottom_radius = rb
		c.top_radius = rt
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		return c)


func _quad(w: float, h: float) -> PlaneMesh:
	return _res("q%.3f_%.3f" % [w, h], func():
		var p := PlaneMesh.new()
		p.size = Vector2(w, h)
		p.orientation = PlaneMesh.FACE_Z
		return p)


## The one way geometry enters the world. `solid` adds Godot's own convex
## collider, which is also what the navmesh baker parses.
func _add(mesh: Mesh, mat: Material, xf: Transform3D, parent: Node, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)
	if solid:
		mi.create_convex_collision()
	return mi


## Collision without geometry: for tessellated planes (never hull a 2k-tri mesh)
## and for the boundary the player must not cross.
func _body(shape: Shape3D, xf: Transform3D) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	b.transform = xf
	nav_region.add_child(b)


func _box_shape(x: float, y: float, z: float) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(x, y, z)
	return s


func _at(pos: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


func _node(pos: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.transform = _at(pos, yaw)
	nav_region.add_child(n)
	return n


## Merge primitives into one mesh so a whole prop can go through MultiMesh.
static func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		st.append_from(p[0], 0, p[1])
	st.generate_normals()
	return st.commit()


## Queue an instance of a repeated prop. Flushed into one draw call later.
func _inst(id: String, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	if not _mm.has(id):
		_mm[id] = [mesh, mat, [] as Array[Transform3D]]
	_mm[id][2].append(xf)


func _flush_mm() -> void:
	for id in _mm:
		var e: Array = _mm[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e[0]
		mm.instance_count = e[2].size()
		for i in e[2].size():
			mm.set_instance_transform(i, e[2][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = id
		mmi.multimesh = mm
		mmi.material_override = e[1]
		nav_region.add_child(mmi)


## Sagging cable / rope: n+1 points on a quadratic bezier dipped by `sag`.
static func _sag_pts(a: Vector3, b: Vector3, sag: float, n: int) -> Array[Vector3]:
	var ctrl := (a + b) * 0.5 - Vector3(0.0, sag * 2.0, 0.0)
	var out: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return out


## Transform that stretches a unit BoxMesh so it spans a -> b.
static func _span(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var d := b - a
	var l := maxf(d.length(), 0.001)
	return Transform3D(
		Basis.looking_at(d / l) * Basis.from_scale(Vector3(thick, thick, l)),
		(a + b) * 0.5)


# --- ground -----------------------------------------------------------------
func _ground() -> void:
	# Visual ground and its collider are separate: one is a 2 m lighting grid,
	# the other is a single box the navmesh baker can read cleanly.
	_add(_plane(R * 2.1, R * 2.1, 2.2), _m(&"dirt", C_DIRT, 30.0),
		_at(Vector3.ZERO), nav_region, false)
	_body(_box_shape(R * 2.1, 1.0, R * 2.1), _at(Vector3(0, -0.5, 0)))
	# Packed-earth road: the spine of the level.
	_add(_plane(7.0, R * 2.0, 1.5), _m(&"dirt", C_ROAD, 14.0),
		_at(Vector3(0, 0.03, 0)), nav_region, false)
	for x in [-1.35, 1.35]:
		_add(_plane(0.6, R * 2.0, 1.5), _m(&"dirt", C_RUT, 12.0),
			_at(Vector3(x, 0.05, 0)), nav_region, false)
	# Rubble: small meshes catch per-vertex light, so this is what actually makes
	# the ground read as ground when the flashlight sweeps it.
	var rub := _box(1.0, 1.0, 1.0)
	for i in 46:
		var p := Vector3(_rng.randf_range(-R, R), 0.0, _rng.randf_range(-R, R))
		var s := Vector3(_rng.randf_range(0.25, 0.8), _rng.randf_range(0.06, 0.2),
			_rng.randf_range(0.25, 0.8))
		p.y = s.y * 0.4
		var tint := C_RUT if i % 3 else C_ROAD
		_inst("rubble%d" % (i % 3), rub, _m(&"dirt", tint, 2.0),
			Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(s), p))


# --- bahay kubo -------------------------------------------------------------
func _hut(pos: Vector3, w: float, d: float, yaw: float) -> void:
	_occupied.append(pos)
	var g := _node(pos, yaw)
	var fh := 1.15  # stilt / floor height
	var wh := 1.9   # wall height
	var rh := 2.35  # roof height (steep)
	var bam := _m(&"bamboo", C_BAMBOO, 4.0)
	var wood := _m(&"wood", C_WOOD, 3.0)

	for sx in [-0.44, 0.0, 0.44]:
		for sz in [-0.44, 0.44]:
			_add(_cyl(0.085, 0.075, fh, 5), bam,
				_at(Vector3(float(sx) * w, fh * 0.5, float(sz) * d)), g)
	_add(_box(w, 0.14, d), wood, _at(Vector3(0, fh, 0)), g)

	var wy := fh + wh * 0.5
	_add(_box(w, wh, 0.09), bam, _at(Vector3(0, wy, -d * 0.5)), g)          # back
	_add(_box(0.09, wh, d), bam, _at(Vector3(-w * 0.5, wy, 0)), g)          # left
	_add(_box(0.09, wh, d), bam, _at(Vector3(w * 0.5, wy, 0)), g)           # right
	# Front wall, split around a doorway so the hut reads as enterable.
	var pw := w * 0.5 - 0.45
	for s in [-1.0, 1.0]:
		_add(_box(pw, wh, 0.09), bam,
			_at(Vector3(float(s) * (0.45 + pw * 0.5), wy, d * 0.5)), g)
	_add(_box(0.9, 0.34, 0.09), bam, _at(Vector3(0, fh + wh - 0.17, d * 0.5)), g)
	# Window shutter propped open on the left wall - very bahay kubo.
	_add(_box(0.05, 0.8, 1.1), wood,
		Transform3D(Basis(Vector3.FORWARD, 0.9), Vector3(-w * 0.5 - 0.35, fh + 1.6, 0)), g, false)

	# Steep four-sided thatch roof: a 4-segment cone is a pyramid, scaled to fit.
	var ov := 1.5
	_add(_cyl(0.70711, 0.0, rh, 4), _m(&"thatch", C_THATCH, 5.0),
		Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(w + ov, 1.0, d + ov)),
			Vector3(0, fh + wh + rh * 0.5, 0)), g, false)
	# Ladder plank up to the doorway.
	_add(_box(0.55, 0.07, sqrt(fh * fh + 1.44)), wood,
		Transform3D(Basis(Vector3.RIGHT, -atan2(fh, 1.2)),
			Vector3(0, fh * 0.5, d * 0.5 + 0.62)), g)


func _huts() -> void:
	# x, z, width, depth, yaw
	for h in [
		[-9.5, 23.0, 4.2, 3.6, 0.12], [-10.0, 11.0, 4.6, 3.8, -0.09],
		[-9.0, -2.0, 4.0, 3.4, 0.20], [-11.0, -15.0, 4.4, 3.6, -0.15],
		[-20.0, 18.0, 4.4, 3.6, 1.30], [-22.0, -6.0, 4.2, 3.6, 1.42],
		[10.0, 12.0, 4.4, 3.8, -0.22], [20.0, 4.0, 4.2, 3.6, 0.32],
		[8.0, -9.0, 4.6, 3.8, 0.10], [19.0, -16.0, 4.2, 3.6, -0.55],
		[-19.0, -26.0, 4.2, 3.4, 0.60], [9.0, -25.0, 4.4, 3.6, -0.35],
	]:
		_hut(Vector3(h[0], 0.0, h[1]), h[2], h[3], h[4])


# --- sari-sari store --------------------------------------------------------
func _store(pos: Vector3, yaw: float) -> void:
	# Local +Z faces the road: that is the counter side.
	var g := _node(pos, yaw)
	var w := 4.6
	var d := 3.6
	var wh := 2.6
	var conc := _m(&"concrete", C_CONC, 4.0)
	var wood := _m(&"wood", C_WOOD, 3.0)
	_add(_plane(w, d, 1.2), conc, _at(Vector3(0, 0.13, 0)), g, false)
	_add(_box(w, 0.12, d), conc, _at(Vector3(0, 0.06, 0)), g)
	_add(_box(w, wh, 0.15), conc, _at(Vector3(0, wh * 0.5, -d * 0.5)), g)
	_add(_box(0.15, wh, d), conc, _at(Vector3(-w * 0.5, wh * 0.5, 0)), g)
	_add(_box(0.15, wh, d), conc, _at(Vector3(w * 0.5, wh * 0.5, 0)), g)
	# Counter opening: waist-high counter, header above, barred in between.
	_add(_box(w, 1.05, 0.2), wood, _at(Vector3(0, 0.55, d * 0.5)), g)
	_add(_box(w, 0.75, 0.15), conc, _at(Vector3(0, wh - 0.38, d * 0.5)), g)
	for i in 7:
		_add(_box(0.05, 0.85, 0.05), _m(&"metal", C_METAL),
			_at(Vector3(-w * 0.5 + 0.35 + i * (w - 0.7) / 6.0, 1.5, d * 0.5)), g, false)
	# Corrugated roof + awning over the counter.
	var rust := _m(&"rust", C_RUST, 6.0)
	_add(_box(w + 0.7, 0.1, d + 0.7), rust, _at(Vector3(0, wh + 0.05, 0)), g, false)
	_add(_box(w + 0.5, 0.08, 1.7), rust,
		Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, wh - 0.15, d * 0.5 + 0.8)), g, false)
	for s in [-1.0, 1.0]:
		_add(_box(0.07, 1.05, 0.07), _m(&"metal", C_METAL),
			_at(Vector3(float(s) * w * 0.45, 1.6, d * 0.5 + 1.5)), g, false)
	# Hand-painted signboard, and a dead fluorescent tube under the awning.
	_add(_box(2.6, 0.55, 0.06), _m(&"cloth", C_CLOTH, 3.0),
		_at(Vector3(0, wh + 0.35, d * 0.5 + 0.1)), g, false)
	_add(_cyl(0.05, 0.05, 1.4, 5), _m(&"metal", C_DEAD),
		Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, wh - 0.4, d * 0.5 + 0.75)), g, false)


# --- kapilya ----------------------------------------------------------------
func _chapel(pos: Vector3) -> void:
	# Faces +Z (up the road towards the player spawn). The only lit interior, and
	# the only emissive glass, so it is a beacon from the far end of the road.
	var g := _node(pos, 0.0)
	var w := 8.0
	var d := 10.0
	var wh := 4.2
	var conc := _m(&"concrete", C_CHAPEL, 5.0)
	var pane := _m(&"glass", C_PANE)
	_add(_plane(w, d, 1.2), conc, _at(Vector3(0, 0.21, 0)), g, false)
	_add(_box(w, 0.2, d), conc, _at(Vector3(0, 0.1, 0)), g)
	_add(_box(w, wh, 0.3), conc, _at(Vector3(0, wh * 0.5, -d * 0.5)), g)
	# Side walls in three bands so window holes are left between the mullions.
	var mull := [-d * 0.5 + 0.6, -1.2, 1.2, d * 0.5 - 0.6]
	for s in [-1.0, 1.0]:
		var x: float = s * w * 0.5
		_add(_box(0.3, 1.5, d), conc, _at(Vector3(x, 0.75, 0)), g)
		_add(_box(0.3, 1.2, d), conc, _at(Vector3(x, wh - 0.6, 0)), g)
		for zz in mull:
			_add(_box(0.3, 1.5, 1.2), conc, _at(Vector3(x, 2.25, zz)), g)
		for zz in [-2.8, 0.0, 2.8]:
			_add(_box(0.1, 1.4, 1.7), pane, _at(Vector3(x, 2.25, zz)), g, false)
	# Front wall with the door the player has to reach.
	var pw := w * 0.5 - 0.9
	for s in [-1.0, 1.0]:
		_add(_box(pw, wh, 0.3), conc,
			_at(Vector3(float(s) * (0.9 + pw * 0.5), wh * 0.5, d * 0.5)), g)
	_add(_box(1.8, 1.5, 0.3), conc, _at(Vector3(0, wh - 0.75, d * 0.5)), g)
	# Galvanised gable roof, bell tower, cross: reads as a chapel in silhouette.
	var prism := PrismMesh.new()
	prism.size = Vector3(w + 1.0, 2.4, d + 0.8)
	_add(prism, _m(&"rust", C_RUST, 7.0), _at(Vector3(0, wh + 1.2, 0)), g, false)
	_add(_box(1.9, 2.6, 1.9), conc, _at(Vector3(0, wh + 1.3, d * 0.5 - 1.2)), g, false)
	_add(_box(1.35, 1.0, 0.12), pane, _at(Vector3(0, wh + 1.6, d * 0.5 - 0.27)), g, false)
	_add(_cyl(1.35, 0.0, 1.4, 4), _m(&"rust", C_RUST, 3.0),
		Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, wh + 3.3, d * 0.5 - 1.2)), g, false)
	var cross := _merge([
		[_box(0.13, 1.3, 0.13), Transform3D()],
		[_box(0.75, 0.13, 0.13), Transform3D(Basis(), Vector3(0, 0.25, 0))],
	])
	_add(cross, _m(&"metal", C_METAL), _at(Vector3(0, wh + 4.7, d * 0.5 - 1.2)), g, false)
	for zz in [-2.0, 0.6]:
		_add(_box(4.0, 0.45, 0.5), _m(&"wood", C_WOOD, 4.0), _at(Vector3(0, 0.42, zz)), g)

	# Short range so it lights the inside without leaking onto the street, plus a
	# narrow spot for the spill through the doorway.
	var inner := OmniLight3D.new()
	inner.light_color = Color(1.0, 0.74, 0.38)
	inner.light_energy = 7.0
	inner.omni_range = 6.5
	inner.omni_attenuation = 1.4
	inner.position = Vector3(0, 2.4, 0.5)
	g.add_child(inner)
	var spill := SpotLight3D.new()
	spill.light_color = Color(1.0, 0.70, 0.34)
	spill.light_energy = 5.0
	spill.spot_range = 13.0
	spill.spot_angle = 32.0
	spill.spot_attenuation = 1.2
	spill.transform = Transform3D(Basis(Vector3.RIGHT, -0.40), Vector3(0, 2.6, d * 0.5 + 0.4))
	spill.rotate_object_local(Vector3.UP, PI)
	g.add_child(spill)


# --- basketball court -------------------------------------------------------
func _court(pos: Vector3) -> void:
	var g := _node(pos, 0.0)
	var w := 15.0
	var d := 11.0
	_add(_plane(w, d, 1.4), _m(&"concrete", C_COURT, 12.0), _at(Vector3(0, 0.15, 0)), g, false)
	_body(_box_shape(w, 0.14, d), _at(pos + Vector3(0, 0.07, 0)))
	# Markings are tessellated planes, not flat boxes: a 14 m 4-vertex strip is
	# sampled only at its corners and stays black. Lit, they are what makes this
	# read as a court at all when the flashlight sweeps across it.
	var paint := _m(&"concrete", Color(1.0, 0.96, 0.82))
	for l in [
		[0.0, 0.0, 0.16, d - 1.0],                                     # centre
		[-w * 0.5 + 0.5, 0.0, 0.16, d - 1.0], [w * 0.5 - 0.5, 0.0, 0.16, d - 1.0],
		[0.0, -d * 0.5 + 0.5, w - 1.0, 0.16], [0.0, d * 0.5 - 0.5, w - 1.0, 0.16],
		[-w * 0.5 + 2.6, -1.8, 4.2, 0.16], [-w * 0.5 + 2.6, 1.8, 4.2, 0.16],
		[-w * 0.5 + 4.7, 0.0, 0.16, 3.6],                              # west key
		[w * 0.5 - 2.6, -1.8, 4.2, 0.16], [w * 0.5 - 2.6, 1.8, 4.2, 0.16],
		[w * 0.5 - 4.7, 0.0, 0.16, 3.6],                               # east key
	]:
		_add(_plane(l[2], l[3], 1.2), paint, _at(Vector3(l[0], 0.17, l[1])), g, false)
	var metal := _m(&"metal", C_METAL, 3.0)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.3
	rim.outer_radius = 0.38
	rim.rings = 8
	rim.ring_segments = 5
	# Two hoops. The second one is bent - pole leaning, board and rim askew.
	for s in [-1.0, 1.0]:
		var bend := 0.22 if s < 0.0 else 0.0  # the bent one is the near/west hoop
		var hg := Node3D.new()
		hg.transform = Transform3D(Basis(Vector3.FORWARD, bend * 0.6),
			Vector3(float(s) * (w * 0.5 - 0.9), 0.14, 0.0))
		g.add_child(hg)
		_add(_cyl(0.13, 0.10, 3.6, 6), metal, _at(Vector3(0, 1.8, 0)), hg)
		_add(_box(0.12, 0.12, 1.2), metal, _at(Vector3(float(-s) * 0.6, 3.4, 0)), hg, false)
		_add(_box(0.09, 1.15, 1.75), _m(&"concrete", Color(1.0, 0.98, 0.90), 2.0),
			Transform3D(Basis(Vector3.FORWARD, bend), Vector3(float(-s) * 1.2, 3.3, 0)), hg, false)
		_add(rim, metal, Transform3D(Basis(Vector3.FORWARD, bend * 1.8),
			Vector3(float(-s) * 1.75, 2.95, 0)), hg, false)


# --- yero fences ------------------------------------------------------------
## Rusted corrugated iron: three offset ribs read as corrugation in raking light
## without relying on the texture. One long box collider per run, not per panel.
func _fence(a: Vector3, b: Vector3) -> void:
	# The ribs are YAWED, not just offset: identical normals would light
	# identically and read as one flat slab. Alternating normals is the whole
	# point - that is what makes corrugation visible in raking light.
	var panel: ArrayMesh = _res("fencepanel", func(): return _merge([
		[_box(0.05, 1.75, 0.82), Transform3D(Basis(Vector3.UP, 0.26), Vector3(0.05, 0, -0.67))],
		[_box(0.05, 1.75, 0.82), Transform3D(Basis(Vector3.UP, -0.26), Vector3(-0.04, 0, 0.0))],
		[_box(0.05, 1.75, 0.82), Transform3D(Basis(Vector3.UP, 0.26), Vector3(0.05, 0, 0.67))],
	]))
	var d := b - a
	var l := d.length()
	d /= l
	var n := maxi(1, int(round(l / 2.0)))
	var step := l / n
	var yaw := atan2(d.x, d.z)
	var rot := Basis(Vector3.UP, yaw)
	for i in n:
		_inst("fence", panel, _m(&"rust", C_RUST, 3.0), Transform3D(
			rot * Basis.from_scale(Vector3(1, 1, step / 2.0)),
			a + d * (step * (i + 0.5)) + Vector3(0, 0.9, 0)))
	for i in n + 1:
		_inst("fencepost", _box(0.11, 2.0, 0.11), _m(&"wood", C_WOOD, 2.0),
			Transform3D(rot, a + d * (step * i) + Vector3(0, 1.0, 0)))
	_body(_box_shape(0.14, 1.8, l), Transform3D(rot, (a + b) * 0.5 + Vector3(0, 0.9, 0)))


func _fences() -> void:
	for f in [
		[-5.3, 26.0, -5.3, 18.5], [-5.3, 13.5, -5.3, 5.0],
		[-5.4, -6.0, -5.4, -16.0], [-5.3, -20.0, -5.3, -27.0],
		[5.2, 9.0, 5.2, 16.5], [5.2, -1.0, 5.2, -11.0],
		[5.2, -18.0, 5.2, -27.0], [-16.0, 8.0, -16.0, 0.0],
		[22.8, 16.0, 22.8, 28.0], [5.4, 30.2, 22.4, 30.2],
		[-14.0, 28.0, -25.0, 28.0], [14.0, -28.0, 26.0, -28.0],
		[-26.0, 22.0, -26.0, 12.0], [24.0, -6.0, 24.0, -14.0],
	]:
		_fence(Vector3(f[0], 0.0, f[1]), Vector3(f[2], 0.0, f[3]))


# --- coconut palms and banana trees ----------------------------------------
func _trees() -> void:
	var palm_trunk := _cyl(0.17, 0.12, 6.4, 5)
	# Crown is baked at trunk height so both MultiMeshes share one transform.
	var frond_parts := []
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		var spin := Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
		frond_parts.append([_quad(0.55, 1.7),
			spin * Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(0, 6.25, -0.85))])
		frond_parts.append([_quad(0.42, 1.7),
			spin * Transform3D(Basis(Vector3.RIGHT, 1.15), Vector3(0, 5.95, -2.2))])
	var palm_crown := _merge(frond_parts)

	var ban_trunk := _cyl(0.24, 0.17, 2.3, 5)
	var leaf_parts := []
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		leaf_parts.append([_quad(0.95, 2.6),
			Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
			* Transform3D(Basis(Vector3.RIGHT, 0.95), Vector3(0, 2.9, -1.0))])
	var ban_crown := _merge(leaf_parts)

	var wood := _m(&"wood", C_WOOD, 6.0)
	var leaf := _m(&"leaf", C_LEAF, 2.0)
	var leaf2 := _m(&"leaf", C_LEAF2, 2.0)

	var spots: Array[Vector3] = []
	# A ring of palms just inside the fence: the level's visual wall.
	var ring := 20
	for i in ring:
		var a := TAU * i / float(ring)
		spots.append(Vector3(sin(a) * 27.5, 0.0, cos(a) * 27.5))
	# Clusters that break sightlines along the road.
	for p in [
		[-6.4, 20.0], [-6.6, 3.0], [6.3, 6.0], [6.6, -14.0], [-6.5, -22.0],
		[13.5, 6.0], [-15.0, 24.0], [15.0, -6.0], [-15.5, -20.0],
		[-14.0, 4.0], [24.5, 14.0],
		# Right on the road shoulder: these pinch the 55 m sightline down the
		# spine so the aswang has somewhere to step out of.
		[-4.1, 6.0], [4.2, -6.0], [-4.1, -8.0], [-4.2, -20.0], [4.1, 22.0],
	]:
		spots.append(Vector3(p[0], 0.0, p[1]))

	for i in spots.size():
		var p := spots[i]
		p.x += _rng.randf_range(-1.2, 1.2)
		p.z += _rng.randf_range(-1.2, 1.2)
		if _blocked(p):
			continue
		var lean := Basis(Vector3(sin(i * 2.3), 0.0, cos(i * 1.7)).normalized(),
			_rng.randf_range(-0.10, 0.10))
		var s := _rng.randf_range(0.8, 1.25)
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * lean
			* Basis.from_scale(Vector3(s, s, s)), p)
		# Bananas grow in yards between the huts, never as a windbreak, so they
		# only appear in the clusters; the boundary ring stays all coconut.
		if i >= ring and i % 2 == 1:
			_inst("banana_t", ban_trunk, wood, xf * Transform3D(Basis(), Vector3(0, 1.15, 0)))
			_inst("banana_c", ban_crown, leaf2, xf)
			_body(_capsule(0.35, 2.4), _at(p + Vector3(0, 1.2, 0)))
		else:
			_inst("palm_t", palm_trunk, wood, xf * Transform3D(Basis(), Vector3(0, 3.2, 0)))
			_inst("palm_c", palm_crown, leaf, xf)
			_body(_capsule(0.28, 6.0), _at(p + Vector3(0, 3.0, 0)))


## The palm ring is generated blind, so it would otherwise plant trees inside the
## chapel, on the court and on top of the spawn. Cheaper than hand-placing 24.
func _blocked(p: Vector3) -> bool:
	if absf(p.x) < 5.5 and absf(p.z) > 18.0:
		return true                                  # spawn end / chapel end of the road
	if p.x > 6.0 and p.x < 23.5 and p.z > 15.0:
		return true                                  # basketball court
	for o in _occupied:
		if p.distance_to(o) < 4.2:
			return true
	return false


func _capsule(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s


# --- electric poles, drooping wires, laundry lines --------------------------
func _power_and_laundry() -> void:
	var pole: ArrayMesh = _res("polemesh", func(): return _merge([
		[_cyl(0.16, 0.11, 8.0, 6), Transform3D(Basis(), Vector3(0, 4.0, 0))],
		[_box(2.1, 0.13, 0.14), Transform3D(Basis(), Vector3(0, 7.35, 0))],
		[_box(1.3, 0.11, 0.12), Transform3D(Basis(), Vector3(0, 6.6, 0))],
	]))
	var unit := _box(1.0, 1.0, 1.0)
	var wood := _m(&"wood", C_WOOD, 8.0)
	var wire := _m(&"metal", Color(0.14, 0.14, 0.16))
	var zs := [28.0, 18.0, 8.0, -2.0, -12.0, -22.0]
	for i in zs.size():
		var p := Vector3(4.6, 0.0, zs[i])
		_inst("pole", pole, wood, _at(p, 0.06 * (1 if i % 2 else -1)))
		_body(_capsule(0.3, 8.0), _at(p + Vector3(0, 4.0, 0)))
		if i + 1 < zs.size():
			var q := Vector3(4.6, 0.0, zs[i + 1])
			for k in 3:
				var y := 7.32 - k * 0.36
				var off := (k - 1) * 0.75
				var pts := _sag_pts(p + Vector3(off, y, 0), q + Vector3(off, y, 0), 0.55, 3)
				for j in 3:
					_inst("wire", unit, wire, _span(pts[j], pts[j + 1], 0.055))
	# One service drop into the sari-sari store.
	var drop := _sag_pts(Vector3(4.6, 7.0, 18.0), Vector3(-6.4, 2.7, 17.4), 0.7, 3)
	for j in 3:
		_inst("wire", unit, wire, _span(drop[j], drop[j + 1], 0.055))

	# Laundry: sagging line between two posts, shirts hung along it.
	for l in [
		[-7.6, 21.0, -7.6, 13.5], [7.4, 13.5, 7.4, 6.0], [-12.4, -12.0, -12.4, -18.5],
		[11.6, -21.5, 11.6, -27.5],
	]:
		var a := Vector3(l[0], 2.55, l[1])
		var b := Vector3(l[2], 2.55, l[3])
		_add(_cyl(0.06, 0.06, 2.6, 5), wood, _at(a - Vector3(0, 1.25, 0)), nav_region)
		_add(_cyl(0.06, 0.06, 2.6, 5), wood, _at(b - Vector3(0, 1.25, 0)), nav_region)
		var pts := _sag_pts(a, b, 0.3, 10)
		for j in 10:
			_inst("line", unit, wire, _span(pts[j], pts[j + 1], 0.03))
		for j in [1, 3, 5, 7, 9]:
			var c: Vector3 = pts[j]
			var tall := _rng.randf_range(0.55, 0.95)
			var tint := C_CLOTH if j % 4 else C_CLOTH2
			var kind := &"cloth" if j % 4 else &"cloth_dark"
			_inst("cloth%d" % (j % 4), unit, _m(kind, tint, 2.0), Transform3D(
				Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4))
				* Basis.from_scale(Vector3(_rng.randf_range(0.45, 0.7), tall, 0.04)),
				c - Vector3(0, tall * 0.5 + 0.05, 0)))


# --- lighting ---------------------------------------------------------------
## Exactly one working sodium lamp. The other two are dead, for contrast.
func _lamp_post(pos: Vector3, yaw: float, live: bool) -> void:
	var g := _node(pos, yaw)
	var metal := _m(&"metal", C_METAL, 3.0)
	_add(_cyl(0.15, 0.11, 7.0, 6), _m(&"concrete", C_CONC, 6.0), _at(Vector3(0, 3.5, 0)), g)
	_add(_box(0.11, 0.11, 1.9), metal, _at(Vector3(0, 6.85, 0.95)), g, false)
	_add(_box(0.5, 0.22, 0.95), metal, _at(Vector3(0, 6.62, 1.8)), g, false)
	# "glass" is the one emissive kind, so only the live lamp gets it.
	_add(_box(0.42, 0.06, 0.8), _m(&"glass", C_BULB) if live else _m(&"metal", C_DEAD),
		_at(Vector3(0, 6.49, 1.8)), g, false)
	if not live:
		return

	_lamp = SpotLight3D.new()
	_lamp.light_color = Color(1.0, 0.57, 0.15)
	_lamp.light_energy = LAMP_E
	_lamp.spot_range = 18.0
	_lamp.spot_angle = 50.0
	_lamp.spot_attenuation = 1.0
	_lamp.shadow_enabled = true
	_lamp.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 6.42, 1.8))
	g.add_child(_lamp)

	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.66, 0.24)
	_glow.light_energy = 1.6
	_glow.omni_range = 3.8
	_glow.position = Vector3(0, 6.5, 1.8)
	g.add_child(_glow)

	# ponytail: 12 lines of generated mains hum beats waiting on the audio piece.
	var buzz := AudioStreamPlayer3D.new()
	buzz.stream = _hum()
	buzz.unit_size = 2.2
	buzz.max_distance = 20.0
	buzz.volume_db = -16.0
	buzz.position = Vector3(0, 6.4, 1.8)
	buzz.autoplay = true
	g.add_child(buzz)


static func _hum() -> AudioStreamWAV:
	var sr := 22050
	var n := 2205  # 0.1 s: a whole number of 120 Hz cycles, so the loop is seamless
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sr
		var v := 0.3 * signf(sin(TAU * 120.0 * t)) + 0.14 * sin(TAU * 360.0 * t)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 11000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _lamps() -> void:
	_lamp_post(Vector3(3.2, 0.0, 7.0), -PI * 0.5, true)   # the only working one
	_lamp_post(Vector3(-3.3, 0.0, -14.0), PI * 0.5, false)
	_lamp_post(Vector3(12.0, 0.0, 15.2), 0.0, false)
	_lamp_post(Vector3(17.0, 0.0, 27.8), PI, false)


func _process(delta: float) -> void:
	if _lamp == null:
		return
	_t += delta
	# Sodium ballast: fast mains ripple, slow swell, occasional dropout.
	var f := 0.84 + 0.16 * sin(_t * 43.0) * sin(_t * 7.3)
	if sin(_t * 2.7) > 0.986:
		f *= 0.12
	_lamp.light_energy = LAMP_E * f
	_glow.light_energy = 1.6 * f


# --- enclosure + navmesh ----------------------------------------------------
## Fences and the palm ring sell the boundary; these guarantee it.
func _walls() -> void:
	for i in 4:
		var a := PI * 0.5 * i
		_body(_box_shape(0.5, 8.0, R * 2.2),
			Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * R, 4.0, cos(a) * R)))


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.cell_size = 0.25  # matches the default navigation map, avoids rasterise warnings
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.filter_baking_aabb = AABB(Vector3(-R, -0.6, -R), Vector3(R * 2.0, 6.0, R * 2.0))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)  # synchronous: callers can read polys now
