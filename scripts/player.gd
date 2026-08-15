class_name Player
extends CharacterBody3D
## The player: slow walk, worse flashlight. Per the reference the player is slow
## and the light is bad, so both are deliberately underpowered.
##
## Contract the aswang reads (do not rename):
##   group "player", `noise`, `flashlight_on`, `die()`, a descendant Camera3D.
##
## Movement is ONE code path: Input.get_vector on the existing InputMap actions.
## Keyboard, the touch joystick and the capture harness all press the same
## actions, so there is nothing touch-only and nothing keyboard-only.
##
## Look is fed from outside via add_look(): this node normally lives inside the
## psx rig's World SubViewport, which never receives _input, so ui/touch_ui.gd
## (at root level) owns the mouse/drag events and calls in here.

const WALK := 2.3
const RUN := 4.3
const GRAVITY := 18.0
## Radians of yaw per drag of one full screen width. Resolution-independent on
## purpose: the same thumb-swipe turns the same amount on a 720p phone and on a
## 1440p one, and the capture harness's stretch-scaled deltas mean one angle too.
const SENS := 2.8  ## No inversion, by design.

## Full-battery beam energy. High enough that the pool clips to white.
const TORCH := 16.0
## Downward tilt of the beam, radians. The reference image is a hard pool on the
## ground ahead, not a level beam into the void.
const TILT := -0.192

@export var pitch_limit := 78.0
## Seconds of light. Short on purpose: the battery is the stealth trade-off,
## because light = seen (see Aswang._flashlit).
@export var battery_seconds := 100.0

## 0.0 still, ~0.4 walking, ~1.0 sprinting. The aswang's hearing radius is
## hear_base + hear_gain * noise^2, so this single float is the stealth system.
var noise := 0.0
var flashlight_on := true  # on at spawn: a black first frame reads as a crash
var battery := 1.0
var alive := true

var cam: Camera3D
var torch: SpotLight3D

var _pitch := 0.0
var _sway := 0.0
var _step := 0.0


func _ready() -> void:
	add_to_group(&"player")

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	cam = Camera3D.new()
	cam.position = Vector3(0, 1.55, 0)
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 60.0
	add_child(cam)

	# Weak and narrow: a cheap barangay torch, not a searchlight. On the camera
	# so the aswang can test the beam against its own bearing.
	torch = SpotLight3D.new()
	torch.position = Vector3(0.16, -0.14, 0.0)
	torch.light_color = Color(1.0, 0.92, 0.72)
	torch.light_energy = TORCH
	# Aimed DOWN at the ground ahead, like the hand-held lantern in the reference:
	# the signature image is a hard elliptical pool on the floor in front of you.
	# Held level with a 14deg cone and 11m range, the beam met flat ground only at
	# ~12.6m -- past its own range -- so it lit nothing at all on an open road.
	torch.rotation.x = TILT
	torch.spot_range = 22.0
	torch.spot_angle = 30.0
	torch.spot_angle_attenuation = 0.5
	torch.spot_attenuation = 1.1
	torch.shadow_enabled = true
	torch.shadow_bias = 0.08
	torch.shadow_normal_bias = 1.2
	torch.visible = true
	cam.add_child(torch)


## Relative look delta, as a FRACTION of the screen width (touch_ui.gd does the
## division, because it is the node that owns the pixels — this node lives in a
## 320x180 SubViewport and has no idea how big the screen is). Called for both
## the right-thumb drag and mouse motion, so there is one rotation path.
func add_look(d: Vector2) -> void:
	if not alive:
		return
	rotation.y -= d.x * SENS
	_pitch = clampf(_pitch - d.y * SENS, -deg_to_rad(pitch_limit), deg_to_rad(pitch_limit))
	cam.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var v := Vector2.ZERO
	if alive:
		v = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var run := Input.is_action_pressed(&"sprint") and not v.is_zero_approx()
	var speed := RUN if run else WALK

	var dir := (global_basis * Vector3(v.x, 0.0, v.y))
	dir.y = 0.0
	dir = dir.normalized() * minf(v.length(), 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	noise = 0.0 if not moving else (1.0 if run else 0.4)

	_flashlight(delta)
	_handheld(delta, moving, run)
	_footsteps(delta, moving, run)


# ---------------------------------------------------------------- flashlight

func _flashlight(delta: float) -> void:
	if alive and Input.is_action_just_pressed(&"flashlight") and (battery > 0.0 or flashlight_on):
		flashlight_on = not flashlight_on
		Sfx.play(&"ui")
	if flashlight_on:
		battery = maxf(battery - delta / battery_seconds, 0.0)
		if battery <= 0.0:
			flashlight_on = false  # dead: you are in the dark whether you like it or not
	torch.visible = flashlight_on
	# Dims as it goes, and stutters in the last few seconds.
	var dying := 1.0 if battery > 0.12 else (0.25 + 0.75 * float(fmod(_sway, 0.4) < 0.24))
	torch.light_energy = TORCH * (0.45 + 0.55 * battery) * dying


## Slow hand-held sway on the light only, never on the camera: the aswang uses
## camera forward to decide if the beam is on it, and a swaying camera would
## make that read as noise.
func _handheld(delta: float, moving: bool, run: bool) -> void:
	_sway += delta * (0.9 + (2.4 if run else 1.3) * float(moving))
	# Sway around the base downward tilt, never absolute: overwriting rotation.x
	# here would cancel the aim set in _ready and the beam would miss the ground.
	torch.rotation.x = TILT + sin(_sway * 1.7) * 0.035
	torch.rotation.y = sin(_sway * 1.1 + 0.7) * 0.05
	torch.position.y = -0.14 + sin(_sway * 2.3) * 0.02
	cam.position.y = 1.55 + sin(_sway * 3.0) * 0.018 * float(moving)


func _footsteps(delta: float, moving: bool, run: bool) -> void:
	if not moving:
		_step = 0.55  # next step lands soon after you start walking again
		return
	_step -= delta * (1.9 if run else 1.15)
	if _step <= 0.0:
		_step = 1.0
		Sfx.play(&"footstep_run" if run else &"footstep")


# ---------------------------------------------------------------- death

## Called by the aswang on the killing blow. Game.lose() is the aswang's call,
## not ours: all we do is stop and fall over.
func die() -> void:
	if not alive:
		return
	alive = false
	noise = 0.0
	flashlight_on = false
	torch.visible = false
	velocity = Vector3.ZERO
	var t := create_tween()
	t.tween_property(cam, ^"position:y", 0.35, 0.8).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(cam, ^"rotation:z", 1.25, 0.8)
