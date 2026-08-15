extends Node
## Integration: barangay + player + aswang + charms + door + audio, all inside
## the psx rig's SubViewport so the level is actually rendered through the PSX
## pipeline. The pieces already own their own behaviour; this only places them.

## The aswang starts at whichever patrol point is furthest from the player, so
## the night opens with it somewhere else in the barangay.
@export var world_seed := 1


func _ready() -> void:
	Game.reset()
	add_child(Beacon.new())
	($Rig as Node).call(&"set_post", not Game.plain)
	var world: Node = $Rig/World

	var barangay := Barangay.new()
	world.add_child(barangay)
	barangay.build(world_seed)

	var player: Player = $Rig/World/Player
	player.global_transform = barangay.player_start
	# player_start sits on the ground; lift out of the floor so the first
	# move_and_slide does not start inside the collider.
	player.global_position.y += 0.2

	# One charm kind per spot: asin, bawang, buntot pagi. Kind is an int enum.
	for i in barangay.charm_spots.size():
		world.add_child(Charm.make(i, barangay.charm_spots[i]))
	world.add_child(Charm.Door.make(barangay.chapel_door))

	# A trace of moonlight. Without it the barangay measures 91% pure #000000 at
	# spawn with the torch off, which is indistinguishable from a broken build --
	# and the blind critic independently flagged the same thing ("80% of the frame
	# is empty black; no subject, no silhouette"). Low enough that the reference's
	# crushed blacks survive, high enough that rooflines and palms read.
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(38.0), 0.0)
	moon.light_color = Color(0.42, 0.50, 0.78)
	moon.light_energy = 0.16
	moon.shadow_enabled = false
	world.add_child(moon)

	var aswang := Aswang.new()
	aswang.position = _far_from(barangay.patrol_points, barangay.player_start.origin)
	world.add_child(aswang)

	# The aswang writes Game.tension every physics frame; the post shader reads it
	# from here, so the picture reddens and grains up as it closes on you.
	Game.tension_changed.connect(Callable($Rig, "set_tension"))
	Sfx.ambience(true)
	print("[game] ", ($Rig as Node).call(&"report"))


static func _far_from(points: Array[Vector3], from: Vector3) -> Vector3:
	var best := from
	var best_d := -1.0
	for p in points:
		var d := p.distance_to(from)
		if d > best_d:
			best_d = d
			best = p
	return best + Vector3(0.0, 0.3, 0.0)
