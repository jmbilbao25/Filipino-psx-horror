class_name Aswang
extends CharacterBody3D
## The aswang. States: lurk -> patrol -> investigate -> hunt -> attack.
##
## Godot does the work: NavigationAgent3D paths it, one RayCast3D is the line of
## sight, a dot product is the vision cone. No hand-rolled pathfinder, no state
## machine framework -- an enum and a match block are the state machine.
##
## Lurk is the DEFAULT state, not an edge case. Per the reference, dread is
## nothing happening: the aswang stands at the end of the road, and is gone when
## you look back. Chases are rationed by a cooldown so there is breathing room.

enum State { LURK, PATROL, INVESTIGATE, HUNT, ATTACK }

const _NAME := ["lurk", "patrol", "investigate", "hunt", "attack"]
const _SPEED := [2.2, 1.1, 1.8, 3.5, 7.0]
const _GRAVITY := 18.0

## Sight range with no flashlight on us. Barangay at night: it is nearly blind.
@export var sight_dark := 7.0
## Sight range when the player's beam is pointed our way. The light betrays you.
@export var sight_lit := 30.0
## Vision cone half-angle as a cosine (0.5 = 60 deg).
@export var cone_cos := 0.5
## Hearing radius = hear_base + hear_gain * noise^2. Squared, not linear: a walk
## stays local (~7 m) and only a sprint carries across the barangay (~26 m).
@export var hear_base := 4.0
@export var hear_gain := 22.0
## Patrol wanders this far from where it spawned.
@export var patrol_radius := 18.0
## Seconds it keeps charging the last known spot after losing the player.
@export var hunt_grace := 1.6
## Pacing governor: no chase lasts longer than this.
@export var max_hunt := 20.0
## Pacing governor: after a chase, this many seconds of lurk-only quiet.
@export var hunt_cooldown := 25.0
## The night opens quiet: seconds of lurk before it will hunt at all.
@export var opening_quiet := 20.0
## While lurking it stays at least this far away, visible but out of reach.
@export var lurk_min_dist := 16.0
@export var lurk_dwell := 8.0
@export var attack_range := 1.6
@export var debug_log := false

var state := State.LURK
var last_known := Vector3.ZERO

var _player: Node3D
var _eye: Node3D  ## the player's camera if it has one, else the player body
var _nav: NavigationAgent3D
var _ray: RayCast3D
var _rig: Node3D
var _limb: Array[Node3D] = []  ## arm L, arm R, leg L, leg R
var _home := Vector3.ZERO
var _t := 0.0  ## seconds in the current state
var _clock := 0.0
var _lost := 0.0
var _cool := 0.0
var _dwell := 0.0
var _peer := 0.0  ## investigate: time spent looking around
var _watched := 0.0  ## how long the player has had eyes on us
var _vanish := false
var _repath := 0.0
var _gait := 0.0
var _tension := 0.0
var _reason := ""
var _beat := 0.0
var _struck := false


func _ready() -> void:
	add_to_group(&"aswang")
	_home = global_position
	_build()

	_nav = NavigationAgent3D.new()
	_nav.radius = 0.5
	_nav.height = 2.0
	_nav.path_desired_distance = 0.7
	_nav.target_desired_distance = 0.9
	add_child(_nav)

	_ray = RayCast3D.new()
	_ray.position = Vector3(0, 1.75, 0)
	_ray.collision_mask = 0xFFFFFFFF
	add_child(_ray)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 2.0
	col.shape = cap
	col.position = Vector3(0, 1.0, 0)
	add_child(col)

	_cool = opening_quiet  # the night starts quiet
	_dwell = 0.0
	Sfx.set_aswang_distance(INF)


func _physics_process(delta: float) -> void:
	_clock += delta
	_t += delta
	_repath -= delta
	if not Game.alive:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if _player == null or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group(&"player")
		if _player == null:
			return
		var cams := _player.find_children("", "Camera3D", true, false)
		_eye = cams[0] if not cams.is_empty() else _player

	var d := global_position.distance_to(_player.global_position)
	var reason := _sense(d)
	# Either of these means "I know where you are right now", so both start a hunt.
	var saw := reason.begins_with("sight") or reason == "heard_loud"

	match state:
		State.LURK:
			_lurk(delta, d, reason, saw)
		State.PATROL:
			_patrol(d, reason, saw)
		State.INVESTIGATE:
			_investigate(delta, d, reason, saw)
		State.HUNT:
			_hunt(delta, d, reason, saw)
		State.ATTACK:
			_attack(d)

	_cool = maxf(_cool - delta, 0.0)
	_drive(delta, d)
	_log(d, reason)


# ---------------------------------------------------------------- senses

## Returns "", "sight_dark", "sight_flashlight", "heard" or "heard_loud". Sets
## last_known -- for hearing it is deliberately fuzzed, so the aswang never
## magically knows exactly where you are.
func _sense(d: float) -> String:
	var los := _los()
	if los and d <= sight_lit:
		var to: Vector3 = (_player.global_position - global_position).normalized()
		if (-global_basis.z).dot(to) > cone_cos:
			var lit := _flashlit()
			if d <= (sight_lit if lit else sight_dark):
				last_known = _player.global_position
				return "sight_flashlight" if lit else "sight_dark"
	var n := 0.0
	var nv: Variant = _player.get(&"noise")
	if nv is float or nv is int:
		n = float(nv)
	if n > 0.05 and d < hear_base + hear_gain * n * n:
		# heard, not seen: a rough bearing, not a fix
		var fuzz := 3.0 * (1.0 - n)
		last_known = _player.global_position + Vector3(randf_range(-fuzz, fuzz), 0, randf_range(-fuzz, fuzz))
		# Sprinting is unmistakable: that is a chase, not a rustle worth a look.
		return "heard_loud" if n > 0.8 else "heard"
	return ""


## Clear line of sight to the player? One RayCast3D, aimed at chest height.
func _los() -> bool:
	_ray.target_position = _ray.to_local(_player.global_position + Vector3.UP * 1.0)
	_ray.force_raycast_update()
	return not _ray.is_colliding() or _ray.get_collider() == _player


## The flashlight betrays you: beam roughly on us => we can see much further.
func _flashlit() -> bool:
	if _player.get(&"flashlight_on") != true:
		return false
	var to: Vector3 = (global_position - _player.global_position).normalized()
	return (-_eye.global_basis.z).dot(to) > 0.55


## Does the player currently have us in view? Drives the lurk vanish trick.
func _watching(d: float) -> bool:
	if d > sight_lit:
		return false
	var to: Vector3 = (global_position - _player.global_position).normalized()
	return (-_eye.global_basis.z).dot(to) > 0.7 and _los()


# ---------------------------------------------------------------- states

## Somewhere else in the level. Stands still at a distance, faces the player,
## and disappears the moment you are not looking.
func _lurk(delta: float, d: float, reason: String, saw: bool) -> void:
	if _cool <= 0.0:
		if saw:
			_go(State.HUNT, reason, d)
			return
		_go(State.PATROL, "quiet_over", d)
		return
	if d < 4.0 and _los():
		_go(State.HUNT, "walked_into_it", d)  # ignoring you would be sillier
		return

	_watched = _watched + delta if _watching(d) else 0.0
	if _watched > 1.2:
		_vanish = true
	if _vanish and not _watching(d):
		var p := _far_point()
		if p != Vector3.INF and p.distance_to(_player.global_position) > lurk_min_dist * 0.75:
			global_position = p  # gone when you look back
			_nav.target_position = p
			_vanish = false
			_dwell = lurk_dwell
			if debug_log:
				print("[aswang] %5.1fs lurk: vanished, reappears at %v" % [_clock, p])
		return

	_dwell -= delta
	if _dwell <= 0.0 or d < lurk_min_dist * 0.6:
		var p := _far_point()
		if p != Vector3.INF:
			_nav.target_position = p
			if debug_log:
				print("[aswang] %5.1fs lurk: standing off at %.0fm, moving to %v" % [_clock, d, p.snappedf(0.1)])
		_dwell = lurk_dwell


func _patrol(d: float, reason: String, saw: bool) -> void:
	if saw and _can_hunt(d):
		_go(State.HUNT, reason, d)
		return
	if reason != "":
		# A rustle is worth a look, not a lunge. Only a sprint (heard_loud, caught
		# by `saw` above) or something almost on top of it starts a chase.
		_go(State.HUNT if d < 4.0 else State.INVESTIGATE, reason, d)
		return
	if _cool > 0.0 and _t > 6.0:
		_go(State.LURK, "pacing", d)
		return
	if _nav.is_navigation_finished() or _t < 0.1:
		var p := _near_point(_home, patrol_radius)
		if p != Vector3.INF:
			_nav.target_position = p


## Walks to the last known position, then looks around before giving up.
func _investigate(delta: float, d: float, reason: String, saw: bool) -> void:
	if (saw and _can_hunt(d)) or (reason != "" and d < 4.0):
		_go(State.HUNT, reason, d)
		return
	if reason != "" or _t < 0.1:
		_nav.target_position = last_known
	if _nav.is_navigation_finished():
		_peer += delta
		rotation.y += delta * 1.2  # look around
		if _peer > 3.0:
			_go(State.LURK if _cool > 0.0 else State.PATROL, "nothing_here", d)
	elif _t > 10.0:
		# Cap it: creeping after a rumour forever is a chase in slow motion.
		_go(State.LURK if _cool > 0.0 else State.PATROL, "search_timeout", d)


func _hunt(delta: float, d: float, reason: String, saw: bool) -> void:
	# LOS matters here: pressed against the far side of a fence you are 1 m away
	# and completely safe, and it has to walk around like anything else.
	if d < attack_range and _los():
		_go(State.ATTACK, "reached", d)
		return
	if reason != "":
		_lost = 0.0
	else:
		_lost += delta
		if _lost > hunt_grace:
			_cool = hunt_cooldown  # pacing: earn the quiet back
			_go(State.INVESTIGATE, "lost_player", d)
			return
	if _t > max_hunt:
		_cool = hunt_cooldown
		_go(State.INVESTIGATE, "gave_up", d)
		return
	if _repath <= 0.0:
		_nav.target_position = last_known
		_repath = 0.2


## A short lunge, then it has you. Getting inside attack_range with clear line of
## sight is the mistake; there is no dodge window on purpose.
func _attack(_d: float) -> void:
	if _t > 0.55 and not _struck:
		_struck = true
		if _player.has_method(&"die"):
			_player.die()
		Game.lose()


# ---------------------------------------------------------------- movement

func _drive(delta: float, d: float) -> void:
	var speed: float = _SPEED[state]
	var step := Vector3.ZERO
	if state == State.ATTACK:
		step = (_player.global_position - global_position)
		step.y = 0.0
		step = step.normalized() * speed
	elif not _nav.is_navigation_finished():
		step = _nav.get_next_path_position() - global_position
		step.y = 0.0
		step = step.normalized() * speed if step.length() > 0.1 else Vector3.ZERO

	velocity.x = step.x
	velocity.z = step.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _GRAVITY * delta
	move_and_slide()

	# Standing still it stares at you; moving, it faces where it is going.
	var face := step if step.length_squared() > 0.01 else (_player.global_position - global_position)
	_face(face, delta)
	_lurch(delta)
	_audio(delta, d)


func _face(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 5.0, 0.0, 1.0))


## Cheap procedural lurch: no imported animation, four sines.
func _lurch(delta: float) -> void:
	_gait += delta * (1.2 + Vector2(velocity.x, velocity.z).length() * 1.6)
	var s := sin(_gait * 2.0)
	_rig.position.y = s * 0.05
	_rig.rotation.z = sin(_gait) * 0.05
	_limb[0].rotation.x = s * 0.5
	_limb[1].rotation.x = -s * 0.5
	_limb[2].rotation.x = -s * 0.45
	_limb[3].rotation.x = s * 0.45


# ---------------------------------------------------------------- horror

func _audio(delta: float, d: float) -> void:
	var hunting := state == State.HUNT or state == State.ATTACK
	# Folklore: the tik-tik gets QUIETER the closer it is. The audio piece owns
	# the inversion; we owe it an honest distance, and INF when it is not hunting.
	Sfx.set_aswang_distance(d if hunting else INF)

	var want := 0.05
	match state:
		State.ATTACK:
			want = 1.0
		State.HUNT:
			want = 0.55 + 0.45 * (1.0 - clampf(d / 18.0, 0.0, 1.0))
		State.INVESTIGATE:
			want = 0.3 + 0.2 * (1.0 - clampf(d / 20.0, 0.0, 1.0))
		State.PATROL:
			want = 0.12 + 0.15 * (1.0 - clampf(d / 25.0, 0.0, 1.0))
		State.LURK:
			# The spike is seeing it far away, not it being near.
			want = 0.35 if _watched > 0.2 else 0.05
	_tension = move_toward(_tension, want, delta * (1.5 if want > _tension else 0.35))
	Game.tension = _tension
	Sfx.set_tension(_tension)


# ---------------------------------------------------------------- helpers

## Pacing governor, second half: during the quiet after a chase it will not
## commit to a fresh hunt unless you are practically on top of it. It stalks
## instead, which is the point -- an endless chase is not scary, it is a race.
func _can_hunt(d: float) -> bool:
	return _cool <= 0.0 or d < 6.0


## Public: anything that makes a noise (a charm being lifted off a shrine)
## can point the aswang at it. Investigating is allowed even during the quiet.
func hear_noise(pos: Vector3, strength := 1.0) -> void:
	var fuzz := 3.0 * (1.0 - clampf(strength, 0.0, 1.0))
	last_known = pos + Vector3(randf_range(-fuzz, fuzz), 0, randf_range(-fuzz, fuzz))
	if state == State.HUNT or state == State.ATTACK:
		return
	_nav.target_position = last_known
	_go(State.INVESTIGATE, "noise_%.1f" % strength, global_position.distance_to(pos))


func _go(s: State, why: String, d: float) -> void:
	if s == state:
		return
	if debug_log:
		print("[aswang] %5.1fs %-11s -> %-11s d=%5.1fm  why=%s" % [_clock, _NAME[state], _NAME[s], d, why])
	state = s
	_t = 0.0
	_lost = 0.0
	_peer = 0.0
	_watched = 0.0
	_vanish = false
	_repath = 0.0
	if s == State.HUNT:
		Sfx.play_at(&"scare", global_position)
	elif s == State.INVESTIGATE:
		_nav.target_position = last_known
	elif s == State.LURK:
		_dwell = 0.0


func _log(d: float, reason: String) -> void:
	if not debug_log:
		return
	if reason != _reason:
		_reason = reason
		print("[aswang] %5.1fs detect=%-16s d=%5.1fm state=%s" % [_clock, ("none" if reason == "" else reason), d, _NAME[state]])
	_beat -= get_physics_process_delta_time()
	if _beat <= 0.0:
		_beat = 1.0
		print("[aswang] %5.1fs state=%-11s d=%5.1fm tension=%.2f tik=%s" % [_clock, _NAME[state], d, _tension, ("%.1f" % d) if (state == State.HUNT or state == State.ATTACK) else "INF"])


## A random navmesh point near `origin`, or Vector3.INF if the map is not ready.
func _near_point(origin: Vector3, radius: float) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF  # navmesh not baked/synced yet
	for _i in 8:
		var p := NavigationServer3D.map_get_random_point(map, 1, false)
		if p.distance_to(origin) < radius:
			return p
	return Vector3.INF


## A random navmesh point far from the player: somewhere else in the level.
func _far_point() -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var best := Vector3.INF
	var best_d := 0.0
	for _i in 12:
		var p := NavigationServer3D.map_get_random_point(map, 1, false)
		var pd := p.distance_to(_player.global_position)
		if pd > lurk_min_dist:
			return p
		if pd > best_d:
			best_d = pd
			best = p
	return best


# ---------------------------------------------------------------- body

## Tall, hunched, long-limbed. Boxes only, built here, no imported model: in
## near-zero ambient it reads as a black cut-out with two faint eyes.
func _build() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	var dark := Psx.mat(&"cloth_dark", Color(0.03, 0.03, 0.04))

	_box(_rig, Vector3(0.5, 0.85, 0.34), Vector3(0, 1.42, 0.06), -0.45, dark)  # torso, hunched
	_box(_rig, Vector3(0.22, 0.3, 0.24), Vector3(0, 1.83, -0.16), -0.9, dark)  # neck
	_box(_rig, Vector3(0.3, 0.28, 0.34), Vector3(0, 1.96, -0.3), -0.35, dark)  # head, thrust forward
	_box(_rig, Vector3(0.34, 0.4, 0.3), Vector3(0, 0.95, 0), 0.0, dark)  # hips

	for side in [-1.0, 1.0]:
		var sh := Node3D.new()  # shoulder pivot: long arms hanging past the knees
		sh.position = Vector3(0.3 * side, 1.68, 0.1)
		_rig.add_child(sh)
		_box(sh, Vector3(0.12, 1.3, 0.12), Vector3(0.04 * side, -0.65, 0), 0.0, dark)
		_box(sh, Vector3(0.1, 0.34, 0.12), Vector3(0.04 * side, -1.4, -0.08), 0.6, dark)
		_limb.append(sh)
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.14 * side, 0.9, 0)
		_rig.add_child(hip)
		_box(hip, Vector3(0.14, 0.9, 0.14), Vector3(0, -0.45, 0), 0.0, dark)
		_limb.append(hip)

	# "glass" is the one self-lit kind Psx already ships, so the eyes are the only
	# part of it that survives total darkness. No new material needed.
	var eye := Psx.mat(&"glass", Color(1.0, 0.86, 0.5))
	for side in [-1.0, 1.0]:
		_box(_rig, Vector3(0.05, 0.035, 0.02), Vector3(0.07 * side, 1.99, -0.47), 0.0, eye)


func _box(parent: Node, size: Vector3, pos: Vector3, tilt: float, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.rotation.x = tilt
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
