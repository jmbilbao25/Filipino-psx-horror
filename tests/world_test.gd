extends Node3D
## Standalone viewer for world/barangay.gd. Not part of the game: it supplies the
## camera, the night environment and a stand-in flashlight so the capture harness
## can photograph the level before the player piece exists.

var _cam: Camera3D
var _yaw := 0.0
var _pitch := -0.10


func _ready() -> void:
	var we := WorldEnvironment.new()
	we.environment = load("res://world/night.tres")
	add_child(we)

	var b := Barangay.new()
	add_child(b)
	b.build(1)

	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 90.0
	_cam.position = b.player_start.origin + Vector3(0.0, 1.6, -6.0)
	add_child(_cam)
	_aim()

	# Stand-in flashlight, angled down like a hand-held torch. The real one is
	# the player piece's job; this only has to make geometry judgeable.
	var fl := SpotLight3D.new()
	fl.light_color = Color(1.0, 0.93, 0.78)
	fl.light_energy = 5.5
	fl.spot_range = 20.0
	fl.spot_angle = 34.0
	fl.spot_attenuation = 1.5
	fl.shadow_enabled = true
	fl.transform = Transform3D(Basis(Vector3.RIGHT, -0.16), Vector3(0.25, -0.2, 0.0))
	_cam.add_child(fl)

	print("TRIS ", _tris(b))
	print("NAVPOLYS ", b.nav_region.navigation_mesh.get_polygon_count(),
		"  navverts ", b.nav_region.navigation_mesh.get_vertices().size())
	print("CHARMS ", b.charm_spots, "  PATROL ", b.patrol_points.size(),
		"  DOOR ", b.chapel_door)
	_nav_check(b)


## The aswang paths to every published point, so each one must land on the baked
## navmesh. NavigationServer syncs asynchronously - it needs a few physics frames
## before queries return anything but the origin.
func _nav_check(b: Barangay) -> void:
	for _i in 30:
		await get_tree().physics_frame
	var map := b.nav_region.get_navigation_map()
	var pts: Array[Vector3] = b.patrol_points.duplicate()
	pts.append_array(b.charm_spots)
	pts.append(b.chapel_door)
	pts.append(b.player_start.origin)
	var bad := 0
	for p in pts:
		if NavigationServer3D.map_get_closest_point(map, p).distance_to(p) > 1.5:
			bad += 1
			print("OFF-NAV ", p)
	print("NAVCHECK region_bounds=", NavigationServer3D.region_get_bounds(b.nav_region.get_rid()),
		" off-navmesh ", bad, "/", pts.size())


## Look deltas are a fraction of the viewport, not raw pixels: with stretch mode
## "canvas_items" the injected relative is already scaled by the window/viewport
## ratio, so raw pixels turn a different amount at every capture resolution.
## This way `look 400 0` is 50 degrees at any resolution.
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var vw := get_viewport().get_visible_rect().size.x
		_yaw -= e.relative.x / vw * 2.112
		_pitch = clampf(_pitch - e.relative.y / vw * 2.112, -1.4, 1.4)
		_aim()


func _aim() -> void:
	_cam.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)


static func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and n.mesh != null:
		t += n.mesh.get_faces().size() / 3
	elif n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
		t += n.multimesh.mesh.get_faces().size() / 3 * n.multimesh.instance_count
	for c in n.get_children():
		t += _tris(c)
	return t
