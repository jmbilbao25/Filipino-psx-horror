extends Control
## The beacon's pixels. Deliberately the dumbest possible drawing: flat bars and
## draw_string, at full resolution, no shader, no viewport. If this is invisible
## then nothing about the PSX pipeline is worth investigating yet.

const BARS := [
	Color(1, 0, 1), Color(0, 1, 0), Color(0, 1, 1),
	Color(1, 1, 0), Color(1, 1, 1), Color(1, 0, 0),
]


func _ready() -> void:
	set_process(true)


func _process(_d: float) -> void:
	queue_redraw()  # window size and Game.plain can both change under us


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var fs := int(clampf(size.y * 0.030, 9.0, 22.0))
	var h := maxf(6.0, size.y * 0.018)

	# Colour bars: if the canvas draws at all, these are impossible to miss.
	var w := size.x / float(BARS.size())
	for i in BARS.size():
		draw_rect(Rect2(i * w, 0.0, w + 1.0, h), BARS[i], true)

	var y := h + fs + 2.0
	for line in [
		"BARANGAY ASWANG  build 4",
		"TAP = START      TAP TOP-RIGHT = PLAIN MODE",
		"post=%s  %s" % ["OFF" if Game.plain else "ON", Beacon.info()],
	]:
		_text(font, Vector2(6.0, y), line, fs)
		y += fs + 3.0

	# The plain-mode hit target, drawn so it can be found without instructions.
	var r := Rect2(size.x - size.x * 0.22, h, size.x * 0.22 - 4.0, size.y * 0.10)
	draw_rect(r, Color(1, 0.8, 0.3, 0.85), false, 2.0)
	_text(font, r.position + Vector2(6.0, r.size.y * 0.5 + fs * 0.4),
		"PLAIN: %s" % ["ON" if Game.plain else "OFF"], fs)


## Black backdrop then the glyph, so it survives any background colour.
func _text(font: Font, at: Vector2, s: String, fs: int) -> void:
	draw_string(font, at + Vector2.ONE, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
