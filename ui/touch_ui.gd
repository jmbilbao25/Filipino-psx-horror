extends Control
## Full-resolution touch layer. Put this on a CanvasLayer ABOVE the psx rig, so
## fingers stay pixel-accurate while the world stays 320x180.
##
## It feeds the SAME InputMap actions the keyboard uses -- Input.action_press /
## action_release -- so there is exactly one movement code path and nothing here
## is unreachable from a keyboard or from the capture harness.
##
## It also owns LOOK for the whole game, because the player normally lives inside
## a SubViewport and SubViewports never receive input events. Right-half drag and
## mouse motion both land here and both call Player.add_look().
##
## Style: hard-edged 1px amber/bone outlines at low alpha. No gradients, no
## rounded cards, no drop shadows, no emoji, no textures.

const BONE := Color(0.88, 0.82, 0.66)
const AMBER := Color(0.98, 0.74, 0.30)

## [action, label]. Right thumb, L-shaped cluster in the bottom-right corner.
const BUTTONS := [
	[&"interact", "GAMIT"],
	[&"sprint", "TAKBO"],
	[&"flashlight", "ILAW"],
]

var _player: Node = null
var _stick := -1  ## touch index driving the joystick, -1 = none
var _home := Vector2.ZERO
var _tip := Vector2.ZERO
var _look := -1
var _held := [-1, -1, -1]  ## touch index holding each button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never block the drag region


# ---------------------------------------------------------------- geometry
# Everything is derived from height, so it scales with the device instead of
# being pinned to a resolution. ~13% of height is well over 48dp on any phone.

func _unit() -> float:
	return size.y * 0.13


func _radius() -> float:
	return size.y * 0.16


## Where the stick sits before a thumb has landed (and where WASD deflects it).
func _rest() -> Vector2:
	return Vector2(size.x * 0.15, size.y * 0.70)


func _button(i: int) -> Rect2:
	var u := _unit()
	var m := size.y * 0.06
	# GAMIT bottom-right (thumb home), TAKBO above it, ILAW to its left.
	var o: Vector2 = [Vector2(0, 0), Vector2(0, -u - m * 0.4), Vector2(-u - m * 0.4, 0)][i]
	return Rect2(Vector2(size.x - m - u, size.y - m - u) + o, Vector2(u, u))


# ---------------------------------------------------------------- input

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_down(t.index, t.position)
		else:
			_up(t.index)
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _stick:
			_tip = d.position
		elif d.index == _look:
			_aim(d.relative)
	elif e is InputEventMouseMotion and _stick < 0 and _look < 0:
		# Desktop / capture harness look. Same rotation path as the drag.
		_aim((e as InputEventMouseMotion).relative)


func _down(idx: int, p: Vector2) -> void:
	for i in BUTTONS.size():
		# Buttons are hit-tested first, so they never fight the look drag.
		if _button(i).grow(_unit() * 0.15).has_point(p):
			_held[i] = idx
			Input.action_press(BUTTONS[i][0])
			return
	if p.x < size.x * 0.5:
		if _stick < 0:
			_stick = idx
			_home = p  # the stick appears under the thumb, not the other way round
			_tip = p
	elif _look < 0:
		_look = idx


func _up(idx: int) -> void:
	for i in BUTTONS.size():
		if _held[i] == idx:
			_held[i] = -1
			Input.action_release(BUTTONS[i][0])
	if idx == _stick:
		_stick = -1
		_axis(Vector2.ZERO)
	if idx == _look:
		_look = -1


func _process(_delta: float) -> void:
	if _stick >= 0:
		var v := (_tip - _home) / _radius()
		_axis(v if v.length() <= 1.0 else v.normalized())
	queue_redraw()


## Identical to the capture harness's own axis injection, on purpose: one path.
func _axis(v: Vector2) -> void:
	for a in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(a)
	if v.x < 0.0:
		Input.action_press(&"move_left", -v.x)
	elif v.x > 0.0:
		Input.action_press(&"move_right", v.x)
	if v.y < 0.0:
		Input.action_press(&"move_up", -v.y)
	elif v.y > 0.0:
		Input.action_press(&"move_down", v.y)


## `d` is in this layer's pixels; the player wants a fraction of the screen width,
## so the same swipe means the same angle on any device (and on the capture
## harness, whose deltas arrive pre-scaled by the window/viewport stretch).
func _aim(d: Vector2) -> void:
	if _player == null or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group(&"player")
	if _player != null and _player.has_method(&"add_look"):
		_player.add_look(d / maxf(size.x, 1.0))


# ---------------------------------------------------------------- draw

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var fs := int(_unit() * 0.26)
	var r := _radius()
	var live := _stick >= 0
	var c := _home if live else _rest()

	# Joystick. Faint ring at rest so it is discoverable; a real one under the
	# thumb once it lands. Low segment counts keep the edges faceted, not smooth.
	draw_arc(c, r, 0.0, TAU, 28, BONE * Color(1, 1, 1, 0.5 if live else 0.16), 2.0)
	draw_arc(c, r * 0.30, 0.0, TAU, 16, BONE * Color(1, 1, 1, 0.22), 1.0)
	# Knob follows the thumb; with no thumb it shows the keyboard/pad deflection,
	# which is also how a capture proves movement input arrived.
	var v := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if live:
		v = (_tip - _home) / r
		if v.length() > 1.0:
			v = v.normalized()
	var knob := c + v * r
	draw_arc(knob, r * 0.34, 0.0, TAU, 20, AMBER * Color(1, 1, 1, 0.85 if (live or not v.is_zero_approx()) else 0.22), 2.0)
	# Signage only: it says what the faint ring is for, and once a thumb is on the
	# glass it is both redundant and in the way (the ring follows the thumb and can
	# sit anywhere in the left half, including off the bottom of the frame).
	if not live:
		_label(font, Rect2(c.x - r, c.y + r * 0.9, r * 2.0, 12.0), "LAKAD", fs, 0.28)

	# Look region: four corner ticks in the right half, nothing that blocks a drag.
	var lr := Rect2(size.x * 0.5, size.y * 0.06, size.x * 0.5 - _unit() * 2.4, size.y * 0.62)
	_ticks(lr, BONE * Color(1, 1, 1, 0.5 if _look >= 0 else 0.13))
	_label(font, Rect2(lr.position.x, lr.position.y + 6.0, lr.size.x, 12.0), "TANAW", fs, 0.22)

	# Buttons. Pressed state reads Input directly, so the keyboard lights them up
	# too -- one truth for both, and it shows up in a screenshot.
	for i in BUTTONS.size():
		var b := _button(i)
		var on := Input.is_action_pressed(BUTTONS[i][0])
		draw_rect(b, (AMBER if on else BONE) * Color(1, 1, 1, 0.9 if on else 0.34), false, 2.0)
		if on:
			draw_rect(b.grow(-4.0), AMBER * Color(1, 1, 1, 0.14), true)
		_label(font, Rect2(b.position.x, b.get_center().y - fs * 0.6, b.size.x, fs + 2.0),
			BUTTONS[i][1], fs, 0.95 if on else 0.55)


func _label(font: Font, r: Rect2, s: String, fs: int, a: float) -> void:
	draw_string(font, r.position + Vector2(0.0, float(fs)), s, HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x, fs, BONE * Color(1, 1, 1, a))


## Four hard corner ticks. Cheaper and less noisy than an outlined box.
func _ticks(r: Rect2, col: Color) -> void:
	var n := minf(r.size.x, r.size.y) * 0.07
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var p := r.position + Vector2(r.size.x * sx, r.size.y * sy)
			var dx := n * (1.0 if sx == 0.0 else -1.0)
			var dy := n * (1.0 if sy == 0.0 else -1.0)
			draw_line(p, p + Vector2(dx, 0), col, 2.0)
			draw_line(p, p + Vector2(0, dy), col, 2.0)
