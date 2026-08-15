extends Node
## Global run state. Autoload "Game".
## Deliberately tiny: three counters and four signals is the whole game loop.

signal charm_collected(found: int, total: int)
signal tension_changed(t: float)

const TOTAL_CHARMS := 3

var charms := 0
var alive := true
## 0 = calm, 1 = the aswang is on you. Audio and post-processing both read this.
var tension := 0.0:
	set(v):
		var c := clampf(v, 0.0, 1.0)
		if not is_equal_approx(c, tension):
			tension = c
			tension_changed.emit(c)


func reset() -> void:
	charms = 0
	alive = true
	tension = 0.0


func collect_charm() -> void:
	charms += 1
	charm_collected.emit(charms, TOTAL_CHARMS)


func has_all_charms() -> bool:
	return charms >= TOTAL_CHARMS


func win() -> void:
	if not alive:
		return
	alive = false
	_go("res://scenes/win.tscn")


func lose() -> void:
	if not alive:
		return
	alive = false
	_go("res://scenes/lose.tscn")


func _go(path: String) -> void:
	# Deferred: callers are usually inside physics/signal processing.
	get_tree().change_scene_to_file.call_deferred(path)
