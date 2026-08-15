extends Control
## Shared by title / win / lose. One script, three scenes — the only thing that
## differs is the next scene and the text, so there is no reason for three.

@export var next_scene: String = "res://scenes/game.tscn"

func _ready() -> void:
	if next_scene == "res://scenes/game.tscn":
		Game.reset()


func _unhandled_input(event: InputEvent) -> void:
	var go: bool = event.is_action_pressed("ui_confirm_tap")
	if event is InputEventScreenTouch:
		go = go or (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		go = go or (event as InputEventMouseButton).pressed
	if go:
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(next_scene)
