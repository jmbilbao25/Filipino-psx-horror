extends Node3D
## Integration point: assembles the level, the player, the enemy and the UI.
## Placeholder until the pieces land — enough to boot and render a frame.

func _ready() -> void:
	Game.reset()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	add_child(ground)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 4, 0)
	lamp.light_color = Color(1.0, 0.72, 0.35)
	lamp.light_energy = 4.0
	lamp.omni_range = 18.0
	add_child(lamp)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 6)
	cam.fov = 70.0
	add_child(cam)
