class_name Beacon
extends CanvasLayer
## Diagnostic beacon. Draws at full resolution on its own CanvasLayer, so it is
## OUTSIDE the SubViewport and OUTSIDE post.gdshader — the two suspects.
##
## Why this exists: a real phone renders the game black while every offscreen
## desktop capture is correct, so the failure is in mobile GLES and cannot be
## reproduced here. This reports what the engine thinks is true, and gives a
## bypass, so one screenshot identifies the broken layer instead of a guess.
##
## Reading it:
##   nothing on screen at all  -> the engine or the whole canvas is dead
##   bars + text, game black   -> the SubViewport/post chain is the culprit
##   everything visible        -> rendering is fine, the level is just too dark

const BONE := Color(0.9, 0.85, 0.7)

## Anything a scene wants shown on the device. A phone has no console, so this is
## the only channel for telemetry that does not need adb.
static var extra := ""


func _ready() -> void:
	layer = 100
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_script(preload("res://ui/beacon_draw.gd"))
	add_child(c)
	print("[beacon] ", info())


## Plain text so it also lands in `adb logcat -s godot`.
static func info() -> String:
	var vp := Vector2i.ZERO
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		vp = tree.root.size
	return "os=%s gpu=%s api=%s window=%v viewport=%v plain=%s" % [
		OS.get_name(),
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version(),
		DisplayServer.window_get_size(),
		vp,
		Game.plain,
	]
