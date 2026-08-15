extends Node
## Autoload "Sfx". Every sound is synthesised at boot into an AudioStreamWAV:
## no audio file is imported, the APK ships zero audio bytes.
##
## Bus layout is built at runtime because project.godot has no default_bus_layout:
##   Master <- Rev (AudioEffectReverb) <- Tik, one-shots, distant dog/rooster
##          <- Amb   crickets, wind
##          <- Body  breath, heartbeat, sub drone
##
## Mono, 22050 Hz, 16-bit. Follows world/barangay.gd's _hum(): build a
## PackedByteArray, hand it to AudioStreamWAV, done.

const SR := 22050

# --- the tik-tik inversion ---------------------------------------------------
## Folklore, and the game's core tension instrument: the aswang's familiar calls
## LOUDLY when the creature is FAR and shuts up when it is on top of you. The
## silence is the warning. This curve therefore FALLS as the distance falls.
## It is not broken. Do not "fix" it into distance attenuation.
const TIK_MUTE := 5.0   ## metres: closer than this there is no call at all
const TIK_FAR := 40.0   ## metres: full volume from here outwards


## Linear gain of the tik-tik call. Monotonically DECREASING as `d` decreases.
## Static so tests can assert the real curve instead of a copy of it.
static func tik_gain(d: float) -> float:
	if is_inf(d) or is_nan(d):
		return 0.0  # not hunting: no call
	return clampf((d - TIK_MUTE) / (TIK_FAR - TIK_MUTE), 0.0, 1.0)


## Seconds between calls for a given gain. Far = loud AND frequent, near = quiet
## and sparse, then nothing. Same inversion as tik_gain, so it is asserted too.
static func tik_interval(g: float) -> float:
	return lerpf(3.6, 1.6, g)  # >0.62s sample: a sparse call, not a machine gun


## Base gain per one-shot, dB. Jittered per play.
const _DB := {
	&"footstep": -14.0, &"footstep_run": -8.0, &"pickup": -9.0, &"scare": -3.0,
	&"breath": -13.0, &"gate": -7.0, &"win": -6.0, &"lose": -6.0, &"ui": -12.0,
	&"dog": -22.0, &"rooster": -24.0, &"tik": -6.0,
}

var _bank := {}  ## StringName -> Array[AudioStreamWAV]; >1 entry = pick at random
var _pool: Array[AudioStreamPlayer] = []
var _pool3: Array[AudioStreamPlayer3D] = []
var _n := 0
var _n3 := 0
var _crickets: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _far: AudioStreamPlayer  ## distant dog / rooster, fired on a slow timer
var _heart: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _tik: AudioStreamPlayer
var _amb := false
var _t := 0.0    ## tension
var _d := INF    ## aswang distance, metres
var _tik_t := 0.0
var _far_t := 0.0
var _rng := RandomNumberGenerator.new()
var _debug := false  ## AUDIO_DUMP set: log every tik-tik call


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	_debug = not OS.get_environment("AUDIO_DUMP").is_empty()
	_buses()
	_bank = {
		&"footstep": [_footstep(false, 11), _footstep(false, 12), _footstep(false, 13)],
		&"footstep_run": [_footstep(true, 21), _footstep(true, 22), _footstep(true, 23)],
		&"pickup": [_pickup()],
		&"scare": [_scare()],
		&"breath": [_breath_wav(false)],
		&"gate": [_gate()],
		&"win": [_win()],
		&"lose": [_lose()],
		&"ui": [_ui()],
		&"tik": [_tik_wav()],
		&"dog": [_dog()],
		&"rooster": [_rooster()],
	}
	for i in 8:
		_pool.append(_player("Rev"))
	for i in 4:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Rev"
		p.unit_size = 6.0
		p.max_distance = 45.0
		add_child(p)
		_pool3.append(p)
	_crickets = _player("Amb", _bed_crickets())
	_wind = _player("Amb", _bed_wind())
	_far = _player("Rev")
	_heart = _player("Body", _heart_wav())
	_breath = _player("Body", _breath_wav(true))
	_drone = _player("Body", _drone_wav())
	_tik = _player("Tik", _bank[&"tik"][0])
	set_tension(0.0)
	_dump(t0)


func _buses() -> void:
	AudioServer.set_bus_count(5)
	for b in [[1, "Rev"], [2, "Amb"], [3, "Body"], [4, "Tik"]]:
		AudioServer.set_bus_name(b[0], b[1])
		AudioServer.set_bus_send(b[0], "Master")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.9
	rev.damping = 0.65
	rev.spread = 0.7
	rev.predelay_msec = 45.0
	rev.wet = 0.24
	rev.dry = 1.0
	AudioServer.add_bus_effect(1, rev)
	# bed(t=1) + the ATTACK scare stinger measured 1.22 peak through the reverb
	# bus. Per-stream normalisation cannot see the sum, so catch it on Master.
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -0.5
	lim.threshold_db = -3.0
	AudioServer.add_bus_effect(0, lim)
	AudioServer.set_bus_send(4, "Rev")  # the call comes from out in the dark


func _player(bus: String, stream: AudioStream = null) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = stream
	add_child(p)
	return p


# --- contract ---------------------------------------------------------------
func play(name: StringName) -> void:
	var arr: Array = _bank.get(name, [])
	if arr.is_empty():
		push_warning("Sfx: unknown sound %s" % name)
		return
	var p := _pool[_n]
	_n = (_n + 1) % _pool.size()
	p.stream = arr[_rng.randi() % arr.size()]
	# Jitter: three baked variants plus pitch/gain wobble is what stops a walk
	# cycle from machine-gunning the same waveform.
	p.pitch_scale = _rng.randf_range(0.92, 1.09)
	p.volume_db = float(_DB.get(name, 0.0)) + _rng.randf_range(-1.5, 1.5)
	p.play()


func play_at(name: StringName, pos: Vector3) -> void:
	var arr: Array = _bank.get(name, [])
	if arr.is_empty():
		push_warning("Sfx: unknown sound %s" % name)
		return
	var p := _pool3[_n3]
	_n3 = (_n3 + 1) % _pool3.size()
	p.stream = arr[_rng.randi() % arr.size()]
	p.pitch_scale = _rng.randf_range(0.92, 1.09)
	p.volume_db = float(_DB.get(name, 0.0))
	p.global_position = pos
	p.play()


func set_tension(t: float) -> void:
	_t = clampf(t, 0.0, 1.0)
	if _crickets == null:
		return
	var m := mix()
	_crickets.volume_db = m.crickets
	_wind.volume_db = m.wind
	_heart.volume_db = m.heart
	_breath.volume_db = m.breath
	_drone.volume_db = m.drone
	_heart.pitch_scale = m.heart_rate
	_breath.pitch_scale = m.breath_rate


func set_aswang_distance(d: float) -> void:
	_d = d


func ambience(on: bool) -> void:
	if on == _amb:
		return
	_amb = on
	for p in [_crickets, _wind, _heart, _breath, _drone]:
		if on:
			p.play()
		else:
			p.stop()
	if not on:
		_tik.stop()
		_far.stop()
	_far_t = _rng.randf_range(4.0, 12.0)


## Current mix, dB and pitch multipliers. Read by set_tension and by the tests:
## one source of truth so a test cannot assert a stale copy of the curve.
func mix() -> Dictionary:
	return {
		# Insects going quiet is the cue players read without being told. 14 dB of
		# duck still reads unmistakably as "the night stopped"; the old 24 dB
		# removed nearly all the phone-audible energy in the mix, and since
		# everything replacing it was sub-bass, raising tension made the game
		# QUIETER on a phone speaker. Solved numerically: this set is +3.1 dB
		# through a 450 Hz highpass at t=1 vs t=0, with peak 0.76.
		"crickets": lerpf(-6.0, -20.0, _t),
		"wind": lerpf(-16.0, -11.0, _t),
		"heart": lerpf(-40.0, -6.0, _t),
		"breath": lerpf(-44.0, -8.0, _t),
		"drone": lerpf(-60.0, -8.0, _t * _t),
		"heart_rate": lerpf(0.80, 1.75, _t),
		"breath_rate": lerpf(0.85, 1.40, _t),
	}


func _process(delta: float) -> void:
	if not _amb:
		return
	_far_t -= delta
	if _far_t <= 0.0:
		_far_t = _rng.randf_range(11.0, 26.0)
		var which: StringName = &"dog" if _rng.randf() < 0.65 else &"rooster"
		_far.stream = _bank[which][0]
		_far.volume_db = float(_DB[which]) + _rng.randf_range(-3.0, 3.0)
		_far.pitch_scale = _rng.randf_range(0.90, 1.10)
		_far.play()

	var g := tik_gain(_d)
	if g <= 0.02:
		_tik_t = 0.6  # silent, but ready to speak the moment it backs off
		return
	_tik_t -= delta
	if _tik_t <= 0.0:
		_tik_t = tik_interval(g) * _rng.randf_range(0.85, 1.15)
		_tik.volume_db = linear_to_db(g) + float(_DB[&"tik"])
		_tik.pitch_scale = _rng.randf_range(0.96, 1.05)
		_tik.play()
		if _debug:
			print("TIKFIRE d=%6.1fm gain=%.4f vol=%+.1fdB next_call_in=%.2fs"
				% [_d, g, _tik.volume_db, _tik_t])


# --- synthesis --------------------------------------------------------------
## All generators fill a float buffer, then _pack normalises to 0.85 full scale
## (so nothing can clip) and encodes 16-bit mono.
static func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * SR))
	return b


static func _pack(b: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var mx := 0.0
	for v in b:
		mx = maxf(mx, absf(v))
	var k := (0.85 / mx) if mx > 0.0 else 0.0
	var d := PackedByteArray()
	d.resize(b.size() * 2)
	for i in b.size():
		d.encode_s16(i * 2, int(b[i] * k * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.data = d
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = b.size()
	return w


## Wrap-crossfade for noise beds: render n+xf samples, blend the tail over the
## head, keep n. Afterwards x[0] IS the natural successor of x[n-1], so the loop
## point has no step in it. A step there is an audible click on every repeat.
static func _loopify(b: PackedFloat32Array, n: int, xf: int) -> PackedFloat32Array:
	for i in xf:
		var a := float(i) / xf
		b[i] = b[i] * a + b[n + i] * (1.0 - a)
	b.resize(n)
	return b


## Decaying sine sweeping f0 -> f1. The sweep is what turns a sine into a thump.
static func _tone(b: PackedFloat32Array, at_s: float, dur_s: float, f0: float,
		f1: float, amp: float, att_s: float, decay: float) -> void:
	var at := int(at_s * SR)
	var n := int(dur_s * SR)
	var att := maxf(1.0, att_s * SR)
	var ph := 0.0
	for i in n:
		var j := at + i
		if j >= b.size():
			return
		var u := float(i) / n
		ph += TAU * lerpf(f0, f1, u) / SR
		b[j] += amp * minf(1.0, i / att) * exp(-decay * u) * sin(ph)


## Band-passed white noise burst: two-pole lowpass at `hi` minus two-pole lowpass
## at `lo`. Both skirts have to be 12 dB/oct - with a single pole the high side
## leaks so much that a 1 kHz "band" measures a 5 kHz centroid and reads as
## sizzle. Carries no DC by construction. Footsteps, breath, knocks, every "air".
## `amp` is normalised against the band width so it stays comparable to _tone.
static func _band(b: PackedFloat32Array, at_s: float, dur_s: float, lo: float,
		hi: float, amp: float, att_s: float, decay: float,
		rng: RandomNumberGenerator) -> void:
	var at := int(at_s * SR)
	var n := int(dur_s * SR)
	var att := maxf(1.0, att_s * SR)
	# Exact pole, not the TAU*f/SR approximation: at 22050 Hz that approximation
	# hits 1.0 (= no filtering at all, pure white noise) at only ~3.5 kHz, which
	# silently turned every bright band into sizzle.
	var ka := 1.0 - exp(-TAU * hi / SR)
	var kb := 1.0 - exp(-TAU * lo / SR)
	var g := amp * 2.4 / sqrt(maxf(ka, 0.02))
	var a1 := 0.0
	var a2 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for i in n:
		var j := at + i
		if j >= b.size():
			return
		var w := rng.randf_range(-1.0, 1.0)
		a1 += ka * (w - a1)
		a2 += ka * (a1 - a2)
		b1 += kb * (w - b1)
		b2 += kb * (b1 - b2)
		b[j] += (a2 - b2) * g * minf(1.0, i / att) * exp(-decay * float(i) / n)


# --- ambience bed -----------------------------------------------------------
## One cricket: a high tone chopped by a fast trill, swelling in and out. Placed
## wholly inside the buffer so it never straddles the loop point.
static func _chirp(b: PackedFloat32Array, at_s: float, rng: RandomNumberGenerator) -> void:
	var at := int(at_s * SR)
	var n := int(rng.randf_range(0.18, 0.45) * SR)
	var f := rng.randf_range(3400.0, 4700.0)
	var trill := rng.randf_range(22.0, 34.0)
	var amp := rng.randf_range(0.2, 1.0)
	for i in n:
		var j := at + i
		if j >= b.size():
			return
		var t := float(i) / SR
		var g := maxf(0.0, sin(TAU * trill * t))
		b[j] += amp * sin(PI * float(i) / n) * g * g \
			* (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t))


## The dominant layer: a chorus of insects, 6 s so the repeat is not obvious.
static func _bed_crickets() -> AudioStreamWAV:
	var n := int(6.0 * SR)
	var xf := int(0.5 * SR)
	var b := PackedFloat32Array()
	b.resize(n + xf)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in 52:
		_chirp(b, rng.randf_range(0.0, 5.95), rng)
	return _pack(_loopify(b, n, xf), true)


## Low wind: white noise through two cascaded one-poles (~105 Hz), DC-blocked,
## with a slow gust swell. 3 s is plenty for something this featureless.
static func _bed_wind() -> AudioStreamWAV:
	var n := int(3.0 * SR)
	var xf := int(0.4 * SR)
	var b := PackedFloat32Array()
	b.resize(n + xf)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var p1 := 0.0
	var p2 := 0.0
	var dc := 0.0
	for i in b.size():
		var w := rng.randf_range(-1.0, 1.0)
		p1 += 0.030 * (w - p1)
		p2 += 0.030 * (p1 - p2)
		dc += 0.0006 * (p2 - dc)
		b[i] = (p2 - dc) * (0.62 + 0.38 * sin(TAU * (1.0 / 3.0) * i / SR))
	return _pack(_loopify(b, n, xf), true)


## Sub drone that fades in with tension. 41/54.5 Hz carry it on headphones; the
## 700/1103 Hz beating pair is what a phone speaker can actually emit. Measured:
## with the old 110/164 Hz partials, 91% of the tension mix sat below 200 Hz and
## a phone played NOTHING of it, so raising tension made the game quieter.
## 54.5 not 54.7, and 700/1103 -- all whole cycles over 2.0 s, so the loop is seamless.
static func _drone_wav() -> AudioStreamWAV:
	var n := int(2.0 * SR)
	var xf := int(0.3 * SR)
	var b := PackedFloat32Array()
	b.resize(n + xf)
	for i in b.size():
		var t := float(i) / SR
		b[i] = 1.0 * sin(TAU * 41.0 * t) + 0.65 * sin(TAU * 54.5 * t) \
			+ 0.30 * sin(TAU * 700.0 * t) + 0.22 * sin(TAU * 1103.0 * t)
	return _pack(_loopify(b, n, xf), true)


## lub-dub, then silence: the tail is exactly zero so it loops with no seam and
## needs no crossfade. Rate and pitch ride on pitch_scale from set_tension.
static func _heart_wav() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var b := _buf(1.2)
	_tone(b, 0.00, 0.30, 66.0, 40.0, 1.00, 0.002, 5.0)
	_tone(b, 0.00, 0.16, 150.0, 88.0, 0.45, 0.001, 8.0)
	_band(b, 0.00, 0.05, 60.0, 400.0, 0.25, 0.0, 6.0, rng)
	_tone(b, 0.33, 0.26, 58.0, 36.0, 0.65, 0.003, 5.5)
	_tone(b, 0.33, 0.13, 132.0, 80.0, 0.28, 0.001, 8.0)
	return _pack(b, true)


## `loop` version is the tension bed (silent tail = seamless); the one-shot is
## the shorter gasp callers ask for by name.
static func _breath_wav(loop: bool) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9 if loop else 8
	if loop:
		var b := _buf(2.4)
		_band(b, 0.05, 0.50, 300.0, 1600.0, 0.90, 0.18, 2.0, rng)  # in
		_band(b, 0.70, 0.60, 220.0, 1100.0, 0.75, 0.08, 2.6, rng)   # out
		return _pack(b, true)
	var s := _buf(1.0)
	_band(s, 0.00, 0.42, 300.0, 1500.0, 0.90, 0.14, 2.2, rng)
	_band(s, 0.50, 0.45, 220.0, 1000.0, 0.70, 0.06, 3.0, rng)
	return _pack(s)


# --- one-shots --------------------------------------------------------------
## Packed earth: grit is the sound, the pitch-dropping thump is only the weight
## behind it. Deliberately light on bass - a phone speaker has none, and a
## bass-heavy step reads as a boot on a hollow floor, not dirt.
## Each variant gets its own grit seed, timing and decay so three of them in a
## row do not read as one waveform repeating.
static func _footstep(run: bool, sd: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var b := _buf(0.18)
	var t0 := rng.randf_range(0.0, 0.006)
	_tone(b, t0, 0.09, rng.randf_range(120.0, 150.0) * (1.25 if run else 1.0),
		55.0, 0.45 if run else 0.22, 0.001, 7.0)
	_band(b, t0, rng.randf_range(0.09, 0.13), 600.0, 4000.0 if run else 2200.0,
		1.3 if run else 1.0, 0.002, rng.randf_range(10.0, 18.0), rng)
	# The toe dragging out of the dirt. Barely there when running.
	_band(b, t0 + rng.randf_range(0.035, 0.06), 0.09, 1200.0, 5000.0 if run else 3500.0,
		0.30 if run else 0.45, 0.02, rng.randf_range(7.0, 11.0), rng)
	return _pack(b)


## Charm lifted off a shrine. A bare fifth, no major third: reward, not cheer.
static func _pickup() -> AudioStreamWAV:
	var b := _buf(0.85)
	_tone(b, 0.00, 0.85, 1046.5, 1046.5, 0.70, 0.004, 5.0)
	_tone(b, 0.00, 0.85, 1568.0, 1566.0, 0.45, 0.006, 6.0)
	_tone(b, 0.00, 0.40, 2093.0, 2093.0, 0.20, 0.002, 12.0)
	_tone(b, 0.02, 0.83, 523.3, 523.0, 0.30, 0.010, 4.0)
	return _pack(b)


## Hunt stinger: crash, a sub dropping out from under you, and a minor-second
## cluster - the interval that will not resolve.
static func _scare() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var b := _buf(1.5)
	_band(b, 0.0, 0.25, 300.0, 8000.0, 1.00, 0.0, 16.0, rng)
	_tone(b, 0.0, 1.00, 190.0, 42.0, 1.00, 0.001, 4.0)
	_tone(b, 0.0, 1.20, 622.0, 618.0, 0.50, 0.003, 3.0)
	_tone(b, 0.0, 1.20, 659.0, 664.0, 0.50, 0.004, 3.0)
	_tone(b, 0.0, 1.20, 1244.0, 1236.0, 0.25, 0.020, 3.5)
	_band(b, 0.0, 1.30, 1800.0, 6000.0, 0.35, 0.05, 3.0, rng)
	return _pack(b)


## The chapel door refuses you: dead thud, wood knock, padlock ring, chain.
static func _gate() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var b := _buf(0.5)
	_tone(b, 0.00, 0.22, 105.0, 62.0, 1.00, 0.001, 9.0)
	_band(b, 0.00, 0.10, 250.0, 1800.0, 0.60, 0.0, 18.0, rng)
	_tone(b, 0.03, 0.30, 1720.0, 1690.0, 0.12, 0.001, 10.0)
	_band(b, 0.10, 0.22, 2500.0, 6500.0, 0.18, 0.0, 12.0, rng)
	return _pack(b)


static func _win() -> AudioStreamWAV:
	var b := _buf(2.0)
	var fs := [220.0, 330.0, 440.0]
	for i in 3:
		var at := i * 0.22
		var f: float = fs[i]
		_tone(b, at, 2.0 - at, f, f * 0.998, 0.8 - i * 0.12, 0.03, 2.2)
	_tone(b, 0.0, 2.0, 110.0, 109.5, 0.5, 0.08, 1.6)
	return _pack(b)


static func _lose() -> AudioStreamWAV:
	var b := _buf(2.4)
	var fs := [146.8, 110.0, 73.4]
	for i in 3:
		var at := i * 0.30
		var f: float = fs[i]
		_tone(b, at, 2.4 - at, f, f * 0.985, 0.8, 0.02, 2.0)
		_tone(b, at, 2.4 - at, f * 1.012, f * 0.994, 0.5, 0.03, 2.0)
	_tone(b, 0.0, 1.6, 90.0, 30.0, 0.7, 0.01, 3.0)
	return _pack(b)


static func _ui() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var b := _buf(0.07)
	_tone(b, 0.0, 0.05, 1400.0, 1200.0, 0.8, 0.0005, 9.0)
	_band(b, 0.0, 0.02, 2000.0, 8000.0, 0.3, 0.0, 6.0, rng)
	return _pack(b)


## Four dry clicks. Gain and repeat rate are set by set_aswang_distance.
static func _tik_wav() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var b := _buf(0.62)
	for i in 4:
		var at := 0.02 + i * 0.135
		_tone(b, at, 0.030, 2600.0 - i * 60.0, 2100.0, 1.0 - i * 0.12, 0.0004, 14.0)
		_band(b, at, 0.020, 3000.0, 9000.0, 0.50, 0.0, 8.0, rng)
	return _pack(b)


## Distant dog: nothing above 1.8 kHz, which is what "far away" sounds like.
static func _dog() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var b := _buf(1.3)
	for i in 2:
		var at := 0.04 + i * 0.42
		_tone(b, at, 0.20, 260.0, 150.0, 0.80, 0.008, 6.0)
		_tone(b, at, 0.16, 520.0, 300.0, 0.35, 0.006, 8.0)
		_band(b, at, 0.14, 400.0, 1200.0, 0.30, 0.004, 10.0, rng)
	return _pack(b)


## A rooster crowing at 2am, which in a real barangay they do constantly.
static func _rooster() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	var b := _buf(1.5)
	_tone(b, 0.00, 0.18, 620.0, 780.0, 0.70, 0.010, 5.0)
	_tone(b, 0.20, 0.16, 900.0, 820.0, 0.60, 0.010, 5.0)
	_tone(b, 0.40, 0.70, 760.0, 700.0, 0.75, 0.020, 2.4)
	_band(b, 0.40, 0.70, 700.0, 2000.0, 0.20, 0.030, 3.0, rng)
	return _pack(b)


# --- debug dump -------------------------------------------------------------
## Writes every generated stream to AUDIO_DUMP as .wav and prints the numbers a
## measurement script needs. Unset env = one string compare and out.
func _dump(t0: int) -> void:
	var dir := OS.get_environment("AUDIO_DUMP")
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var all := {}
	for k in _bank:
		var arr: Array = _bank[k]
		for i in arr.size():
			all["%s_%d" % [k, i]] = arr[i]
	all["bed_crickets"] = _crickets.stream
	all["bed_wind"] = _wind.stream
	all["loop_heart"] = _heart.stream
	all["loop_breath"] = _breath.stream
	all["loop_drone"] = _drone.stream
	var bytes := 0
	for k in all:
		var w: AudioStreamWAV = all[k]
		bytes += w.data.size()
		print("DUMP %s %.3fs loop=%s -> %s" % [k, w.get_length(),
			w.loop_mode != AudioStreamWAV.LOOP_DISABLED, dir])
		w.save_to_wav("%s/%s.wav" % [dir, k])
	print("DUMP total_bytes=%d (%.0f KiB, all runtime-generated) synth=%.0f ms"
		% [bytes, bytes / 1024.0, (Time.get_ticks_usec() - t0) / 1000.0])
	for d in [INF, 60.0, 40.0, 20.0, 10.0, 4.0, 1.0]:
		print("TIK d=%6.1f gain=%.4f" % [d, tik_gain(d)])
	var keep := _t
	for t in [0.0, 1.0]:
		set_tension(t)
		print("MIX t=%.1f %s" % [t, mix()])
	set_tension(keep)
