extends Control
## Diegetic HUD. Add this INSIDE the psx rig's World SubViewport (320x180) so it
## is dithered, posterised, scanlined and CRT-bordered along with the world --
## that is the whole reason it looks right instead of looking like an overlay.
##
## All _draw() primitives: no theme, no font import, no NinePatch, no rounded
## corners, no gradients. Hard 1px rectangles only.
##
## Kept out of the bottom corners on purpose: that is where the thumbs and the
## full-res touch layer live. Kept 18px off the edges because the post shader's
## CRT border and corner radius eat roughly that much.

const BONE := Color(0.88, 0.80, 0.62)
const AMBER := Color(0.96, 0.72, 0.26)
const ALARM := Color(1.0, 0.42, 0.30)
## The post shader's CRT border (0.055 screen heights) plus its 0.070 corner
## radius eat the top corners of a 320x180 frame; measured off a capture, 26px
## is where text stops being clipped by the rounded corner.
const PAD := 26.0
const FS := 8

var _tension := 0.0
var _player: Node = null
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.tension_changed.connect(func(t: float) -> void: _tension = t)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()  # 320x180, every frame is free


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var tint := BONE.lerp(ALARM, _tension)
	var right := size.x - PAD

	# -- charms, top left
	_text(font, Vector2(PAD, PAD + 6.0), "ANTING-ANTING", tint)
	for i in Game.TOTAL_CHARMS:
		var r := Rect2(PAD + i * 11.0, PAD + 12.0, 8.0, 8.0)
		draw_rect(r, tint, false, 1.0)
		if i < Game.charms:
			draw_rect(r.grow(-2.0), AMBER, true)

	# -- flashlight + battery, top right
	var p := _who()
	var lit := p != null and bool(p.flashlight_on)
	var bat := float(p.battery) if p != null else 1.0
	var low := bat < 0.2 and fmod(_t, 0.7) < 0.38
	_text(font, Vector2(right - 22.0, PAD + 6.0), "ILAW", tint if lit else tint.darkened(0.55))
	var bar := Rect2(right - 60.0, PAD + 12.0, 60.0, 7.0)
	draw_rect(bar, tint.darkened(0.3), false, 1.0)
	if bat > 0.0 and not low:
		draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2(maxf(1.0, (bar.size.x - 4.0) * bat), 3.0)),
			AMBER if bat > 0.2 else ALARM, true)

	# -- objective, bottom centre: between the thumbs, out of both their ways
	var goal := "TUMAKBO SA KAPILYA" if Game.has_all_charms() else "HANAPIN ANG TATLONG ANTING-ANTING"
	var w := font.get_string_size(goal, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
	_text(font, Vector2((size.x - w) * 0.5, size.y - PAD + 4.0), goal, tint.darkened(0.15))


## Hard 1px black backdrop then the glyph: survives a blown-out light pool
## without a drop shadow.
func _text(font: Font, at: Vector2, s: String, col: Color) -> void:
	draw_string(font, at + Vector2.ONE, s, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0, 0, 0))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, col)


func _who() -> Node:
	if _player == null or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group(&"player")
	return _player
