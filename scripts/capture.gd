extends Node
## Offscreen capture + scripted demo driver.
## Only active when SHOT_DIR env is set, so it costs nothing in a real build.
## Lets a critic look at real rendered frames instead of a description.

var _dir := ""
var _n := 0


func _ready() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir.is_empty():
		return
	var script_path := OS.get_environment("SHOT_SCRIPT")
	if script_path.is_empty():
		return
	_run(script_path)


## SHOT_SCRIPT is a text file, one step per line:
##   wait <seconds>
##   shot <name>
##   press <action>          hold an input action
##   release <action>
##   tap <action>            press for 0.1s
##   move <x> <y>            set movement axis (-1..1), persists
##   look <dx> <dy>          inject one relative look delta (pixels)
##   scene <res://path>      change scene
##   quit
func _run(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("capture: cannot open %s" % path)
		get_tree().quit(1)
		return
	var lines := f.get_as_text().split("\n")
	f.close()
	await get_tree().process_frame
	for raw in lines:
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var a := line.split(" ", false)
		match a[0]:
			"wait":
				await _wait(float(a[1]))
			"shot":
				await _shot(a[1])
			"press":
				Input.action_press(a[1])
			"release":
				Input.action_release(a[1])
			"tap":
				Input.action_press(a[1])
				await _wait(0.1)
				Input.action_release(a[1])
			"move":
				_axis(float(a[1]), float(a[2]))
			"look":
				_look(float(a[1]), float(a[2]))
			"scene":
				get_tree().change_scene_to_file(a[1])
				await _wait(0.4)
			"quit":
				get_tree().quit()
				return
	get_tree().quit()


func _wait(sec: float) -> void:
	# Real frames, not a timer skip: software rendering is slow, so we count frames
	# at the nominal rate to keep captures deterministic.
	var frames := int(sec * 30.0)
	for _i in frames:
		await get_tree().process_frame


func _axis(x: float, y: float) -> void:
	for act in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(act)
	if x < 0.0:
		Input.action_press("move_left", -x)
	elif x > 0.0:
		Input.action_press("move_right", x)
	if y < 0.0:
		Input.action_press("move_up", -y)
	elif y > 0.0:
		Input.action_press("move_down", y)


func _look(dx: float, dy: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	ev.screen_relative = ev.relative
	Input.parse_input_event(ev)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var out := "%s/%02d_%s.png" % [_dir, _n, name]
	img.save_png(out)
	print("SHOT ", out)
