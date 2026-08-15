extends Node
## Shared by title / win / lose. The visible menu lives INSIDE the psx rig's
## World SubViewport (320x180), so it is dithered, posterised, scanlined and
## CRT-bordered exactly like the game — that is why it looks right, and it costs
## nothing but parenting.
##
## The text itself is plain Labels in the .tscn: at 320x180 the built-in font is
## already a chunky bitmap, so there is no font to import and no _draw() to write.
## Only the next scene, the colour cast and the sting differ between the three,
## which is why there is one script and not three.

@export_file("*.tscn") var next_scene: String = "res://scenes/game.tscn"
## Post-processing cast: 0 = warm amber, 1 = red. The lose screen is not calm.
@export_range(0.0, 1.0) var tension := 0.0
## An Sfx one-shot to land on arrival, or &"" for none.
@export var sting: StringName = &""

## Starts true so a button still held from the previous scene cannot skip this one.
var _was := true


func _ready() -> void:
	Sfx.ambience(false)  # crickets belong to gameplay, not to a menu
	($Rig as Node).call(&"set_tension", tension)
	if sting != &"":
		Sfx.play(sting)
	if next_scene == "res://scenes/game.tscn":
		Game.reset()


## Keys are POLLED with an explicit edge, not taken from _input: Input.action_press()
## — which is how both the touch layer and the capture harness press things — emits
## no event at all, and its just_pressed bookkeeping is tied to the frame it was
## called on, which is not the frame a node gets to look at it. Two lines of edge
## detection work for a real key, a synthetic press and a harness press alike.
func _process(_delta: float) -> void:
	var now := Input.is_action_pressed(&"ui_confirm_tap") or Input.is_action_pressed(&"interact")
	if now and not _was:
		_go()
	_was = now


## Touch, which does arrive as an event. Mouse clicks land here too:
## project.godot has emulate_touch_from_mouse on.
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
		get_viewport().set_input_as_handled()
		_go()


func _go() -> void:
	if not is_processing():
		return  # one transition, however many fingers and keys land at once
	set_process(false)
	Sfx.play(&"ui")
	get_tree().change_scene_to_file(next_scene)
