class_name Charm
extends Area3D
## The three folk repellents: asin (salt), bawang (garlic), buntot pagi
## (stingray tail). Procedural meshes, faintly self-lit so they can be found in
## the dark. Lifting one is loud -- it calls the aswang to you. Collecting is
## the dangerous part of the night.
##
## The chapel door lives in here too (Charm.Door): it is the other half of the
## same rule and does not deserve a file of its own.
##   Charm.make(Charm.Kind.ASIN, pos)
##   Charm.Door.make(pos)

enum Kind { ASIN, BAWANG, BUNTOT_PAGI }

const LABEL := ["asin", "bawang", "buntot pagi"]

@export var kind := Kind.ASIN
## How far the noise of lifting it carries, as a 0..1 strength for the aswang.
@export var noise := 1.0

var _taken := false


static func make(kind_: Kind, pos: Vector3) -> Charm:
	var c := Charm.new()
	c.kind = kind_
	c.position = pos
	return c


func _ready() -> void:
	collision_mask = 0xFFFFFFFF
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.9  # generous: the player is fumbling in the dark with a thumbstick
	col.shape = sph
	col.position = Vector3(0, 0.4, 0)
	add_child(col)
	_build()
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group(&"player"):
		return
	_taken = true
	Sfx.play(&"pickup")
	Game.collect_charm()
	# The noise draws it. This is the whole risk of the collect loop.
	for a in get_tree().get_nodes_in_group(&"aswang"):
		a.hear_noise(global_position, noise)
	print("[charm] took %s (%d/%d) -- noise called the aswang" % [LABEL[kind], Game.charms, Game.TOTAL_CHARMS])
	queue_free()


func _build() -> void:
	match kind:
		Kind.ASIN:  # a cone of spilled salt
			var pile := CylinderMesh.new()
			pile.top_radius = 0.015
			pile.bottom_radius = 0.17
			pile.height = 0.16
			pile.radial_segments = 6
			pile.rings = 1
			_part(pile, Vector3(0, 0.08, 0), Vector3.ZERO, _lit(&"cloth", Color(0.86, 0.85, 0.8)))
		Kind.BAWANG:  # a garlic bulb with a stalk
			var bulb := SphereMesh.new()
			bulb.radius = 0.11
			bulb.height = 0.22
			bulb.radial_segments = 6
			bulb.rings = 3
			var skin := _lit(&"skin", Color(0.9, 0.87, 0.74))
			_part(bulb, Vector3(0, 0.11, 0), Vector3.ZERO, skin)
			var stalk := CylinderMesh.new()
			stalk.top_radius = 0.005
			stalk.bottom_radius = 0.03
			stalk.height = 0.18
			stalk.radial_segments = 4
			_part(stalk, Vector3(0, 0.3, 0), Vector3(0.2, 0, 0), skin)
		Kind.BUNTOT_PAGI:  # stingray tail, planted barb-up
			var tail := CylinderMesh.new()
			tail.top_radius = 0.012
			tail.bottom_radius = 0.05
			tail.height = 0.95
			tail.radial_segments = 5
			var horn := _lit(&"leaf", Color(0.32, 0.26, 0.2))
			_part(tail, Vector3(0, 0.48, 0), Vector3(0.22, 0, 0.1), horn)
			var barb := BoxMesh.new()
			barb.size = Vector3(0.03, 0.16, 0.06)
			_part(barb, Vector3(0.02, 0.9, -0.16), Vector3(0.5, 0, 0.1), horn)


## Psx.mat, made faintly self-lit: findable in the dark without lighting the room.
## Psx caches and shares materials, so duplicate before touching emission.
func _lit(mat_kind: StringName, tint: Color) -> Material:
	var m := Psx.mat(mat_kind, tint).duplicate() as Material
	if m is ShaderMaterial:
		m.set_shader_parameter(&"emit", 0.8)
	elif m is StandardMaterial3D:
		m.emission_enabled = true
		m.emission = tint
		m.emission_energy_multiplier = 0.8
	return m


func _part(mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The kapilya door. All three charms -> you get in. Otherwise it refuses.
class Door extends Area3D:
	var _last := -9.0

	static func make(pos: Vector3) -> Door:
		var d := Door.new()
		d.position = pos
		return d

	func _ready() -> void:
		collision_mask = 0xFFFFFFFF
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 2.2, 1.0)
		col.shape = box
		col.position = Vector3(0, 1.1, 0)
		add_child(col)
		var wood := Psx.mat(&"wood", Color(0.22, 0.16, 0.11))
		for side in [-1.0, 1.0]:
			var panel := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.72, 2.1, 0.1)
			panel.mesh = b
			panel.position = Vector3(0.37 * side, 1.05, 0)
			panel.material_override = wood
			add_child(panel)
		body_entered.connect(_on_body_entered)

	func _on_body_entered(body: Node3D) -> void:
		if not body.is_in_group(&"player"):
			return
		if Game.has_all_charms():
			print("[door] all charms -> win")
			Game.win()
		elif Time.get_ticks_msec() * 0.001 - _last > 1.5:
			_last = Time.get_ticks_msec() * 0.001
			Sfx.play(&"gate")
			print("[door] refused, %d/%d charms" % [Game.charms, Game.TOTAL_CHARMS])
