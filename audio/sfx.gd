extends Node
## Autoload "Sfx". API contract only — the audio piece implements the bodies.
## Every other piece calls through these five methods and nothing else.

## One-shot, non-positional. Known names:
## "footstep" "footstep_run" "pickup" "scare" "breath" "gate" "win" "lose" "ui"
func play(_name: StringName) -> void:
	pass


## One-shot at a world position.
func play_at(_name: StringName, _pos: Vector3) -> void:
	pass


## 0 = calm night, 1 = the aswang is on top of you.
func set_tension(_t: float) -> void:
	pass


## Distance in metres from player to aswang, or INF when it is not hunting.
## Folklore: the tik-tik call gets QUIETER the closer the creature is.
func set_aswang_distance(_d: float) -> void:
	pass


## Start/stop the barangay night bed (crickets, wind, distant dogs).
func ambience(_on: bool) -> void:
	pass
