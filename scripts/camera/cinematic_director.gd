class_name CinematicDirector
extends Node
## Decides the "shot": how far the camera pulls back, when it moves in for a
## trick, when it shakes, and when time slows down. It only READS the athlete
## (state, height, tricks); it never touches physics. The CameraRig reads
## `shot`, and Engine.time_scale is the only thing this node writes.
##
## Slow motion is a reward, not a constant: only for a Super Rebound, a hard
## trick (double flip, flip + twist) or a big combo landing, with a cooldown.

signal super_rebound(launch_speed: float)
signal slowmo_started(reason: String)
signal slowmo_ended

@export var enabled: bool = true
@export var slowmo_enabled: bool = true
@export var slowmo_scale: float = 0.3
@export var slowmo_ease_in: float = 0.35      # s (real time)
@export var slowmo_ease_out: float = 0.5
@export var slowmo_cooldown: float = 5.0
## Super Rebound: a launch at least this fast AND close to the best launch
## of the session (so it stays special on every line setup).
@export var super_min_speed: float = 3.6
@export var super_of_best: float = 0.92
@export var combo_slowmo_tricks: int = 3      # tricks in one landing
@export var heavy_landing_speed: float = 4.0  # m/s impact: shake

## What the camera should do right now (all smoothed 0..1 weights, real time).
var shot := {
	"pull": 0.0,       # high jump: pull back + frame the whole jump
	"trick": 0.0,      # hard trick in the air: slight orbit, hero angle
	"super": 0.0,      # super rebound: big reveal of the height
	"close": 0.0,      # super rebound trick: closer cinematic angle
	"combo": 0.0,      # big combo: subtle zoom
	"hero": 0.0,       # hard trick: low-angle opposite-side shot
	"trauma": 0.0,     # shake amount (squared when applied)
}

var athlete: Node = null
var line: Node = null
var best_launch: float = 0.0
var is_super: bool = false
var time_scale: float = 1.0

# slow-motion envelope (real time)
var _slow_t: float = -1.0
var _forced_out_t: float = -1.0
var _forced_out_start: float = 1.0
var _slow_hold: float = 0.0
var _cooldown: float = 0.0
var _manual_override: bool = false
# per-jump bookkeeping
var _airborne: bool = false
var _apex_slow_done: bool = false
var _last_vy: float = 0.0
var _hard_done: bool = false
var _targets := {"pull": 0.0, "trick": 0.0, "super": 0.0, "close": 0.0, "combo": 0.0, "hero": 0.0}
var _combo_timer: float = 0.0
var _hero_timer: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		slowmo_enabled = false   # tests measure gameplay in real time


func bind(a: Node, l: Node) -> void:
	athlete = a
	line = l
	var tr = a.get("tricks")
	if tr:
		tr.trick_completed.connect(_on_trick_completed)
		tr.landed.connect(_on_landed)
	a.launched.connect(_on_launched)
	a.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	if not enabled:
		return
	var real := delta / maxf(Engine.time_scale, 0.05)
	if athlete != null:
		_observe()
	update(real)


## Read the athlete each frame (no physics writes).
func _observe() -> void:
	var airborne: bool = athlete.state == 1   # Athlete.State.AIRBORNE
	var vy: float = athlete.linear_velocity.y
	var h := 0.0
	if line != null:
		var s: float = clampf(line.project_s(athlete.global_position), 0.3, line.chord_length() - 0.3)
		h = athlete.global_position.y - line.sample_world(s).y
	var rotating: bool = athlete.tricks.is_rotating()
	on_air(airborne, vy, h, rotating)
	_last_vy = vy


# ---- events (also called directly by the unit tests) ----------------------

func on_launch(v_up: float) -> void:
	_airborne = true
	_apex_slow_done = false
	_hard_done = false
	is_super = v_up >= super_min_speed and v_up >= best_launch * super_of_best
	best_launch = maxf(best_launch, v_up)
	if is_super:
		super_rebound.emit(v_up)


func on_air(airborne: bool, vy: float, h: float, rotating: bool) -> void:
	if not airborne:
		_targets["pull"] = 0.0
		_targets["trick"] = 0.0
		_targets["super"] = 0.0
		_targets["close"] = 0.0
		_targets["hero"] = 0.0
		return
	# high jumps pull the camera back (0 at 0.4 m, full at 1.6 m above line)
	_targets["pull"] = clampf((h - 0.4) / 1.2, 0.0, 1.0)
	_targets["trick"] = 1.0 if rotating else 0.0
	_targets["super"] = 1.0 if is_super else 0.0
	# super rebound: reveal on the way up, move in close for the trick
	_targets["close"] = 1.0 if is_super and rotating and vy < 1.5 else 0.0
	var ttc := (vy + sqrt(vy * vy + 2.0 * 9.81 * maxf(h, 0.0))) / 9.81
	if is_super and not _apex_slow_done and vy < 1.2:
		_apex_slow_done = true
		var hold := ttc - slowmo_ease_in - slowmo_ease_out
		if hold >= 0.1:
			request_slowmo("super rebound", minf(1.1, hold))
	# End the slow-motion ramp early enough that the last part of the descent
	# and physical contact are close to normal speed.
	if vy < 0.0 and h > 0.0 and _slow_t >= 0.0:
		if ttc <= slowmo_ease_out * 1.2:
			_force_slowmo_out()


func on_hard_trick(name: String) -> void:
	if _hard_done:
		return
	_hard_done = true
	_hero_timer = 1.4
	_targets["hero"] = 1.0
	request_slowmo("hard trick: " + name, 0.8)


func on_land(impact_speed: float, n_tricks: int) -> void:
	_airborne = false
	is_super = false
	_hero_timer = 0.0
	_targets["hero"] = 0.0
	if impact_speed >= heavy_landing_speed:
		add_trauma(clampf((impact_speed - heavy_landing_speed) / 3.0, 0.15, 0.45))
	if n_tricks >= 2:
		_combo_timer = 1.4
		add_trauma(0.25 + 0.1 * minf(n_tricks - 2, 3))
	if n_tricks >= combo_slowmo_tricks:
		request_slowmo("combo x%d" % n_tricks, 0.7)


func add_trauma(a: float) -> void:
	shot["trauma"] = clampf(shot["trauma"] + a, 0.0, 1.0)


## Slow motion: ease into slowmo_scale, hold, ease back out. Ignored while on
## cooldown or while the player's manual slow-mo (M) is on.
func request_slowmo(reason: String, hold: float) -> bool:
	if not slowmo_enabled or _cooldown > 0.0 or _slow_t >= 0.0 or _forced_out_t >= 0.0:
		return false
	if Engine.time_scale < 0.9 and _slow_t < 0.0:
		return false   # manual slow-mo in charge
	_slow_t = 0.0
	_forced_out_t = -1.0
	_slow_hold = hold
	slowmo_started.emit(reason)
	return true


func is_slowmo() -> bool:
	return _slow_t >= 0.0 or _forced_out_t >= 0.0


func _force_slowmo_out() -> void:
	if _slow_t < 0.0 or _forced_out_t >= 0.0:
		return
	_forced_out_t = 0.0
	_forced_out_start = time_scale
	_slow_t = -1.0


## Advance by REAL time (so ramps and camera stay smooth in slow motion).
func update(real_dt: float) -> void:
	# slow-motion envelope
	if _forced_out_t >= 0.0:
		_forced_out_t += real_dt
		var k_out := 1.0 - smoothstep(0.0, maxf(slowmo_ease_out, 0.01), _forced_out_t)
		time_scale = lerpf(1.0, _forced_out_start, k_out)
		if _forced_out_t >= slowmo_ease_out:
			_forced_out_t = -1.0
			time_scale = 1.0
			_cooldown = slowmo_cooldown
			slowmo_ended.emit()
		if slowmo_enabled:
			Engine.time_scale = time_scale
	elif _slow_t >= 0.0:
		_slow_t += real_dt
		var total := slowmo_ease_in + _slow_hold + slowmo_ease_out
		var k: float
		if _slow_t < slowmo_ease_in:
			k = smoothstep(0.0, 1.0, _slow_t / slowmo_ease_in)
		elif _slow_t < slowmo_ease_in + _slow_hold:
			k = 1.0
		else:
			k = 1.0 - smoothstep(0.0, 1.0, (_slow_t - slowmo_ease_in - _slow_hold) / slowmo_ease_out)
		time_scale = lerpf(1.0, slowmo_scale, k)
		if _slow_t >= total:
			_slow_t = -1.0
			time_scale = 1.0
			_cooldown = slowmo_cooldown
			slowmo_ended.emit()
		if slowmo_enabled:
			Engine.time_scale = time_scale
	else:
		_cooldown = maxf(0.0, _cooldown - real_dt)
	# combo zoom
	_combo_timer = maxf(0.0, _combo_timer - real_dt)
	_hero_timer = maxf(0.0, _hero_timer - real_dt)
	if _hero_timer <= 0.0:
		_targets["hero"] = 0.0
	_targets["combo"] = 1.0 if _combo_timer > 0.0 else 0.0
	# smooth every shot weight (no sudden moves)
	var rates := {"pull": 2.2, "trick": 2.0, "super": 1.6, "close": 2.4, "combo": 3.0, "hero": 1.8}
	for k2 in rates:
		shot[k2] = lerpf(shot[k2], _targets[k2], 1.0 - exp(-rates[k2] * real_dt))
	shot["trauma"] = maxf(0.0, shot["trauma"] - 1.4 * real_dt)


# ---- athlete signals --------------------------------------------------------

func _on_state_changed(s: int) -> void:
	if s == 0 and _airborne:   # ON_LINE after a flight
		on_land(absf(_last_vy), 0)
	elif s != 1:
		_airborne = false


func _on_launched(launch_velocity: Vector3) -> void:
	on_launch(launch_velocity.y)


func _on_trick_completed(name: String) -> void:
	var tr = athlete.tricks
	# hard = a double flip, or a flip and a twist in the same jump
	if " x" in name or tr.performed.size() >= 2:
		on_hard_trick(name)


func _on_landed(names: Array, _points: int) -> void:
	if names.size() >= 2:
		on_land(0.0, names.size())
