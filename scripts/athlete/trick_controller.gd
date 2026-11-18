class_name TrickController
extends RefCounted
## Aerial rotation from angular momentum, not animation.
##
##   L = I * w   (angular momentum is conserved in flight)
##
## * A flip gets its angular momentum at TAKEOFF ("the set"): more pop from the
##   line = more momentum (L = flip_gain * takeoff speed).
## * In the air the athlete changes I by tucking (hold the flip key or SPACE):
##   tuck -> small I -> fast rotation; open -> large I -> rotation slows.
##   So you time the flip by how long you hold the tuck.
## * Twists rotate about the body's long axis through the centre of mass;
##   arms in (tucked) twist faster.
## * Landing: upright = clean; tipped ~90 deg = save onto chest (forward) or back
##   (backward) with a balance hit; upside down = bail.
## Moment-of-inertia values are estimates for a 75 kg athlete (tuck ~3.5,
## layout ~13 kg m^2 about the somersault axis; ~1.2 / ~0.7 about the long axis).

signal trick_completed(trick_name: String)
signal landed(trick_names: Array, points: int)
signal bailed(reason: String)

const TRICKS := {
	"backflip":  {"name": "Backflip",  "axis": "pitch", "dir": -1.0, "points": 500},
	"frontflip": {"name": "Frontflip", "axis": "pitch", "dir":  1.0, "points": 550},
	"spin360":   {"name": "Full Twist", "axis": "twist", "dir": 1.0, "points": 300},
	"spin180":   {"name": "Half Twist", "axis": "twist", "dir": 1.0, "points": 150},
}
## Combined sets: one takeoff sets both a flip (pitch L) and a twist (long-axis
## L). Each rotation still integrates from its own momentum; nothing is faked.
const COMBOS := {
	"backflip360":  {"name": "Full-Twisting Backflip",  "parts": ["backflip", "spin360"],  "flip": "Backflip",  "points": 1200},
	"frontflip360": {"name": "Full-Twisting Frontflip", "parts": ["frontflip", "spin360"], "flip": "Frontflip", "points": 1300},
	"backflip180":  {"name": "Back Half (Barani out)",  "parts": ["backflip", "spin180"],  "flip": "Backflip",  "points": 800},
}
const LINE_TRICKS := {
	"butt":  {"name": "Butt Bounce",  "points": 100},
	"chest": {"name": "Chest Bounce", "points": 150},
	"back":  {"name": "Back Bounce",  "points": 150},
}
## Body orientation of each contact position (pitch, rad; + = face down,
## the frontflip direction). A trick is start position -> rotation -> landing
## position, e.g. chest -> backflip -> feet is -450 deg.
const POSE_ANGLE := {"": 0.0, "feet": 0.0, "butt": 0.0, "chest": PI * 0.5, "back": -PI * 0.5}
const POSE_NAMES := {"": "", "feet": "", "butt": "Butt", "chest": "Chest", "back": "Back"}
const LAND_TOLERANCE := 0.7     # rad (40 deg), clean landing window
const SAVE_MIN := 0.6           # rad, beyond clean: save onto chest/back...
const SAVE_MAX := 2.2           # ...up to here; more = bail

# --- body (estimates) ---
## Moments of inertia about the side axis through the COM (75 kg, 1.75 m):
## tight tuck with the hands on the shins ~4.2, straight layout ~13.
var i_tuck: float = 4.2
var i_layout: float = 13.0
var i_twist_open: float = 1.2
var i_twist_in: float = 0.7
var flip_gain: float = 14.0      # (legacy) L per m/s of takeoff speed
var i_eff: float = 7.0           # effective inertia of a typical tuck-then-open flip
## Most angular momentum the legs and arm swing can generate at takeoff
## (kg m^2/s). Caps the spin: a short, weak flight can't complete a flip.
var l_max: float = 60.0
var tuck_speed: float = 4.5       # 1/s: a full tuck takes ~0.22 s
var skip_weak_flips: bool = false # autopilots: don't throw a flip that can't make it
var hop: bool = false
var skipped: int = 0              # flips an autopilot decided not to throw             # brief separation while dropping into a position
## Aerial grabs. Each grab is a body shape with its own moment of inertia
## about the side axis (hands holding the legs in place): it changes the
## spin exactly like tucking does (L conserved, I changes).
const GRABS := {
	"both_knees": {"name": "Double Knee Grab", "I": 5.2, "points": 250},
	"left_knee": {"name": "Left Knee Grab", "I": 7.6, "points": 200},
	"knee": {"name": "Knee Grab", "I": 7.6, "points": 200},
	"leg": {"name": "Leg Grab", "I": 9.4, "points": 250},
	"cross": {"name": "Cross Grab", "I": 7.2, "points": 300},
	"tuck": {"name": "Tuck Grab", "I": 4.2, "points": 150},
}
const GRAB_MIN_HOLD := 0.25      # s held to count
var grab: String = ""
var grab_w: float = 0.0          # 0..1 how far into the grab shape
var grab_t: float = 0.0
var _grabbed := {}
var twist_gain: float = 3.2      # twist L per m/s
## Direct mid-air controls add angular momentum gradually. They let the player
## accelerate, release, and reverse rotation without a canned trick impulse.
var pitch_control_torque: float = 30.0
var twist_control_torque: float = 5.0
var twist_l_max: float = 8.0
var _player_flip_controlled := false
var _player_twist_controlled := false
var _direct_pitch_progress := 0.0
var _direct_pitch_direction := 0.0
var _direct_front_count := 0
var _direct_back_count := 0
var _direct_twist_progress := 0.0
var _direct_twist_direction := 0.0
var _direct_twist_halves := 0

# --- state ---
var pitch: float = 0.0           # + = frontflip direction
var yaw: float = 0.0             # twist about the body's long axis
var l_pitch: float = 0.0
var l_twist: float = 0.0
var tuck: float = 0.0            # 0 open .. 1 full tuck
var omega_pitch: float = 0.0
var twist_target: float = 0.0
var active: String = ""          # flip in progress (for HUD)
var queued: String = ""
var queued_twist: String = ""
var queued_pose: String = ""
var performed: Array[String] = []
var launch_speed: float = 0.0
var last_outcome: String = ""
var score: int = 0
var best_combo: int = 0
var tricks_landed: int = 0
var message: String = ""
var message_time: float = 0.0
var _flips_counted: int = 0
# --- start/landing positions ---
var start_pose: String = ""      # position the athlete took off from
var pitch0: float = 0.0          # orientation at takeoff
var land_target: float = 0.0     # orientation of the planned landing position
var l_set: float = 0.0           # part of the angular momentum that is the "set"
var air_t: float = 0.0
var set_T: float = 0.5           # predicted flight time (ballistic)
var landing_pose: String = ""    # where the last flight landed
var pose_drop: float = 0.35      # m the contact point is lower when landing in a position
var launch_drop: float = 0.0     # m the feet sit below the takeoff point at a feet landing
var v_launch: float = 0.0
# --- motion-capture references (tools/mocap) ---
## Captured performances, keyed "start>trick>landing" (e.g. chest>backflip>butt).
## When one matches the trick being done, the athlete's limbs follow the
## captured movement over the flight; rotation and flight stay physical.
var references := {}
var use_references: bool = true
var ref: MotionReference = null
var ref_t: float = 0.0
var ref_T: float = 0.0
var _twist_halves: int = 0
var _queued_ms: int = 0
var _flip_started := false
## Flip timing: pressed in the last ~0.35 s before takeoff = perfect (more
## spin, easier landing); earlier = ok; set in the air = late.
var timing: String = ""
const PERFECT_WINDOW_MS := 350
const PERFECT_BOOST := 1.2
## Partial assist: once the player opens out (releases), the rotation is
## eased toward the nearest landable orientation. 0 = pure physics.
var assist_rate: float = 5.0


func request(id: String, airborne: bool) -> void:
	if COMBOS.has(id):
		for part in COMBOS[id]["parts"]:
			request(part, airborne)
		return
	if not TRICKS.has(id):
		return
	var t: Dictionary = TRICKS[id]
	if not airborne:
		if t["axis"] == "pitch":
			queued = id
			_queued_ms = Time.get_ticks_msec()
		else:
			queued_twist = id
		return
	timing = "late"
	_start(id, launch_speed * 0.6)   # late set in the air: less momentum


## v_up: takeoff speed. from_pose: the position the athlete leaves (feet,
## butt, chest, back); from_angle: the body's orientation at that moment.
func on_launch(v_up: float, from_pose: String = "", from_angle: float = 0.0) -> void:
	launch_speed = maxf(v_up, 0.0)
	performed.clear()
	start_pose = from_pose
	pitch0 = from_angle
	pitch = from_angle
	air_t = 0.0
	v_launch = v_up
	set_T = flight_time_for(queued_pose)
	land_target = from_angle
	l_set = 0.0
	l_pitch = 0.0
	l_twist = 0.0
	tuck = 0.0
	_flips_counted = 0
	_twist_halves = 0
	active = ""
	timing = ""
	_flip_started = false
	_attitude_used = 0.0
	_player_flip_controlled = false
	_player_twist_controlled = false
	_direct_pitch_progress = 0.0
	_direct_pitch_direction = 0.0
	_direct_front_count = 0
	_direct_back_count = 0
	_direct_twist_progress = 0.0
	_direct_twist_direction = 0.0
	_direct_twist_halves = 0
	if queued != "":
		var dt_ms := Time.get_ticks_msec() - _queued_ms
		timing = "perfect" if dt_ms <= PERFECT_WINDOW_MS else "ok"
		_start(queued, launch_speed)
		if timing == "perfect":
			l_pitch = clampf(l_pitch * PERFECT_BOOST, -l_max, l_max)
		queued = ""
	if queued_twist != "":
		_start(queued_twist, launch_speed)
		queued_twist = ""
	set_landing(queued_pose)


## The "set": hips and arms at takeoff give the extra rotation needed to land
## in the chosen position (e.g. butt -> chest is a quarter turn forward). It is
## angular momentum like any other: the body then turns by L/I. Changing the
## landing position in the air is only possible on the way up (before apex).
## Ballistic flight time to the landing contact: up with v, down to a point
## 'drop' metres below the takeoff (lower when landing in a position).
## Rotation set by the body at takeoff (two-zone controls): the player's
## lean decides the angular momentum; no assist steers it afterwards.
var _attitude_used: float = 0.0


func launch_spin(lp: float, lt: float) -> void:
	_attitude_used = 0.0
	if absf(lp) > 2.0:
		l_pitch += lp
		_flip_started = true
		_player_flip_controlled = true
	if absf(lt) > 0.3:
		l_twist = clampf(l_twist + lt, -twist_l_max, twist_l_max)
		_player_twist_controlled = true


## Arms/hips re-orient the body a little (no change of angular momentum).
func adjust_attitude(dt: float, rate: float, limit: float) -> void:
	if absf(rate) < 1e-3:
		return
	var step := clampf(rate * dt, -limit - _attitude_used, limit - _attitude_used)
	_attitude_used += step
	pitch += step


func flight_time_for(pose_id: String) -> float:
	var drop := launch_drop + (pose_drop if pose_id != "" and pose_id != "feet" else 0.0)
	var v := maxf(v_launch, 0.5)
	return maxf(0.3, (v + sqrt(maxf(0.0, v * v + 2.0 * 9.81 * drop))) / 9.81)


func set_landing(pose_id: String) -> bool:
	var target: float = POSE_ANGLE.get(pose_id, 0.0)
	if absf(target - land_target) < 1e-4:
		return true
	if air_t > set_T * 0.5:
		return false
	if air_t <= set_T * 0.5:
		set_T = flight_time_for(pose_id)
	var left := maxf(0.15, set_T - air_t)
	var add := i_layout * (target - land_target) / left
	l_set += add
	l_pitch += add
	land_target = target
	return true

func _start(id: String, v: float) -> void:
	var t: Dictionary = TRICKS[id]
	if t["axis"] == "pitch":
		if l_pitch != 0.0:
			return
		# Athletes size the flip to the flight: enough angular momentum for one
		# turn with a typical tuck (I_eff) in the time they will be in the air.
		# The tuck then fine-tunes it (tight = faster, open = slower).
		var t_left := maxf(0.25, set_T - air_t)
		var need: float = i_eff * TAU / t_left * (v / maxf(launch_speed, 0.01) if air_t > 0.0 else 1.0)
		if skip_weak_flips and need > l_max * 1.02:
			skipped += 1
			return   # not enough bounce for this flip: ride it out
		l_pitch = t["dir"] * minf(need, l_max)
		active = id
		_flip_started = true
		# a captured reference only applies to the same start/landing (a
		# backflip from the feet is a different movement from a chest one)
		var key := "%s>%s>%s" % [start_pose if start_pose != "" else "feet", id, queued_pose if queued_pose != "" else "feet"]
		ref = null
		if use_references:
			ref = references.get(key)
		ref_t = 0.0
		# expected flight time of a ballistic jump with this takeoff speed
		ref_T = maxf(0.3, set_T - air_t)
	else:
		var turn := PI * (2.0 if id == "spin360" else 1.0)
		twist_target = yaw + turn
		# also sized to the flight: done by ~70% of the time in the air
		var tl := maxf(0.25, set_T - air_t)
		l_twist = signf(t["dir"]) * maxf(twist_gain * 1.2, lerpf(i_twist_open, i_twist_in, 0.5) * turn / (0.7 * tl))


## Flight phase of the active reference: 0 takeoff .. 1 expected landing.
func ref_phase() -> float:
	return clampf(ref_t / ref_T, 0.0, 1.0) if ref != null and ref_T > 0.0 else 0.0


func is_rotating() -> bool:
	return absf(omega_pitch) > 1.5


## tuck_input 0..1 from the player (hold flip key / SPACE in the air).
func update_air(dt: float, tuck_input: float = 0.0, grab_input: String = "",
		flip_input: float = 0.0, twist_input: float = 0.0) -> void:
	var old_pitch := pitch
	# grab: hands go to the legs over ~0.2 s, release the same way
	if grab_input != "" and GRABS.has(grab_input):
		if grab != grab_input:
			grab = grab_input
			grab_t = 0.0
		grab_w = move_toward(grab_w, 1.0, dt * 5.0)
		grab_t += dt
		if grab_t >= GRAB_MIN_HOLD and not _grabbed.has(grab):
			_grabbed[grab] = true
			performed.append(GRABS[grab]["name"])
	else:
		grab_w = move_toward(grab_w, 0.0, dt * 5.0)
		if grab_w <= 0.0:
			grab = ""
	air_t += dt
	if ref != null:
		# The reference shapes the limbs (see Athlete); the tuck that sets the
		# inertia stays the player's. Real-video captures are too noisy in
		# tight tucks to drive the physics directly (see docs/MOCAP.md).
		ref_t += dt
	tuck = move_toward(tuck, clampf(tuck_input, 0.0, 1.0), dt * tuck_speed)
	var i := lerpf(i_layout, i_tuck, tuck)
	if grab != "":
		i = lerpf(i, float(GRABS[grab]["I"]), grab_w)
	# Partial assist after opening out: ease toward the nearest landable
	# orientation (perfect timing = stronger help).
	if absf(flip_input) > 0.001:
		_player_flip_controlled = true
		_flip_started = true
		l_pitch = clampf(l_pitch + flip_input * pitch_control_torque * dt, -l_max, l_max)
	if _flip_started and not _player_flip_controlled and tuck_input < 0.5 and air_t > 0.15:
		var t_left := maxf(0.12, set_T - air_t)
		var target := land_target + roundf((pitch - land_target) / TAU) * TAU
		var l_need := i * (target - pitch) / t_left
		var rate := assist_rate * (1.5 if timing == "perfect" else (0.6 if timing == "late" else 1.0))
		l_pitch = lerpf(l_pitch, l_need, 1.0 - exp(-rate * dt))
	omega_pitch = l_pitch / i
	pitch += omega_pitch * dt
	# Count completed rotations.
	# (measured from the take-off orientation, minus the set's quarter turns)
	var set_part := (land_target - pitch0) * clampf(air_t / set_T, 0.0, 1.0)
	if _player_flip_controlled:
		_track_direct_pitch(pitch - old_pitch)
	else:
		var full := int(floor((absf(pitch - pitch0 - set_part) + 0.5) / TAU))
		while _flips_counted < full and l_pitch != 0.0:
			_flips_counted += 1
			var base: String = "Frontflip" if l_pitch - l_set > 0.0 else "Backflip"
			var label := base if _flips_counted == 1 else ("%s x%d" % [base, _flips_counted])
			if _flips_counted > 1:
				performed.erase(base if _flips_counted == 2 else "%s x%d" % [base, _flips_counted - 1])
			performed.append(label)
			trick_completed.emit(label)
	# Twist: arms/legs in (tuck) -> smaller long-axis inertia -> faster.
	if absf(twist_input) > 0.001:
		_player_twist_controlled = true
		l_twist = clampf(l_twist + twist_input * twist_control_torque * dt, -twist_l_max, twist_l_max)
	if _player_twist_controlled:
		var old_yaw := yaw
		var it := lerpf(i_twist_open, i_twist_in, maxf(tuck, 0.5))
		yaw += l_twist / it * dt
		_track_direct_twist(yaw - old_yaw)
	elif l_twist != 0.0:
		var it := lerpf(i_twist_open, i_twist_in, maxf(tuck, 0.5))
		var step := l_twist / it * dt
		var left := twist_target - yaw
		if absf(step) >= absf(left):
			step = left
			l_twist = 0.0
		yaw += step
		var halves := int(floor(absf(yaw) / PI + 0.02))
		while _twist_halves < halves:
			_twist_halves += 1
		if l_twist == 0.0:
			var n := _twist_halves
			performed.append("Full Twist" if n % 2 == 0 else "Half Twist")
			_twist_halves = 0
	if absf(omega_pitch) < 0.5:
		active = ""


func _track_direct_pitch(_delta_pitch: float) -> void:
	# Count from the net rotation since takeoff (minus any planned set and the
	# shape-change attitude adjustment). A flip counts once it is within the
	# clean-landing window of a full turn; reversing is impossible in the air.
	var set_part := (land_target - pitch0) * clampf(air_t / maxf(set_T, 0.01), 0.0, 1.0)
	var net := pitch - pitch0 - set_part - _attitude_used
	var n := int(floor((absf(net) + LAND_TOLERANCE) / TAU))
	var direction := signf(net)
	while _flips_counted < n:
		_flips_counted += 1
		var base := "Frontflip" if direction > 0.0 else "Backflip"
		if direction > 0.0:
			_direct_front_count += 1
		else:
			_direct_back_count += 1
		var count := _direct_front_count if direction > 0.0 else _direct_back_count
		var label := base if count == 1 else "%s x%d" % [base, count]
		performed.append(label)
		trick_completed.emit(label)


func _track_direct_twist(delta_yaw: float) -> void:
	if absf(delta_yaw) < 1e-6:
		return
	var direction := signf(delta_yaw)
	if _direct_twist_direction != direction:
		_direct_twist_direction = direction
		_direct_twist_progress = 0.0
		_direct_twist_halves = 0
	_direct_twist_progress += absf(delta_yaw)
	while _direct_twist_progress >= PI:
		_direct_twist_progress -= PI
		_direct_twist_halves += 1
		var label := "Full Twist" if _direct_twist_halves % 2 == 0 else "Half Twist"
		performed.append(label)
		trick_completed.emit(label)


## Hint for autopilots: keep tucking until close to the next full rotation.
## open_before: how far (rad) before the landing orientation to open up.
func tuck_hint(open_before: float = 1.6) -> float:
	var lf := l_pitch - l_set
	if absf(lf) < 1.0:
		return 0.0
	var dir := signf(lf)
	# one flip: the landing orientation one full turn away (plus the set)
	var goal := land_target + dir * TAU
	var left := dir * (goal - pitch)
	# Open as soon as the open (layout) body would still get round in the
	# time left; stay tucked while it wouldn't.
	var t_left := maxf(0.0, set_T - air_t)
	var w_open := absf(l_pitch) / i_layout
	if t_left > 0.05:
		# opening takes ~0.15 s, during which the body still spins faster
		var w_now := absf(l_pitch) / lerpf(i_layout, i_tuck, tuck)
		return 1.0 if left > w_open * t_left + (w_now - w_open) * 0.09 else 0.0
	return 1.0 if left > open_before else 0.0


func pitch_error() -> float:
	return wrapf(pitch - land_target, -PI, PI)


func can_land() -> bool:
	return absf(pitch_error()) < LAND_TOLERANCE and _twist_ok()


func _twist_ok() -> bool:
	return absf(wrapf(yaw, -PI * 0.5, PI * 0.5)) < LAND_TOLERANCE


## Decides the landing: "clean", "save_chest", "save_back", "save_feet" or
## "bail". Clean = within tolerance of the planned position's orientation.
## Otherwise the body lands in whichever position it is closest to (if the
## miss is not too big), with a balance hit.
func landing_outcome() -> String:
	var e := pitch_error()
	if absf(e) < LAND_TOLERANCE and _twist_ok():
		return "clean"
	if absf(e) < SAVE_MAX or (absf(e) < LAND_TOLERANCE and not _twist_ok()):
		var a := wrapf(pitch, -PI, PI)
		if absf(a) < PI * 0.25:
			return "save_feet" if land_target != 0.0 else ("save_chest" if e > 0.0 else "save_back")
		return "save_chest" if a > 0.0 else "save_back"
	return "bail"


## Call at touchdown on the feet. Returns false for a bail.
var land_error: float = 0.0       # rad off the landing orientation at contact


func on_land() -> bool:
	land_error = absf(pitch_error())
	if hop:
		# not a flight, just the line dropping away under a position
		hop = false
		last_outcome = "clean"
		landing_pose = queued_pose
		_finish_air(1.0)
		return true
	last_outcome = landing_outcome()
	var lf := l_pitch - l_set
	if performed.is_empty() and absf(lf) < 1.0 and air_t < 0.25 and last_outcome.begins_with("save"):
		# a tiny hop out of a position: you just come back down into it
		where_silent()
		return true
	if last_outcome == "bail":
		_bail("Over/under-rotated")
		return false
	if last_outcome != "clean":
		var where: String = last_outcome.trim_prefix("save_")
		queued_pose = "" if where == "feet" else where
		landing_pose = queued_pose
		_say("Saved on the %s! %s" % [where, "+ ".join(performed)] if not performed.is_empty() else "Saved on the %s!" % where)
		_finish_air(0.5)
		return true
	landing_pose = queued_pose
	_finish_air(1.0)
	return true


func where_silent() -> void:
	var where: String = last_outcome.trim_prefix("save_")
	queued_pose = "" if where == "feet" else where
	landing_pose = queued_pose
	last_outcome = "clean"
	_finish_air(1.0)


func _finish_air(points_scale: float) -> void:
	ref = null
	grab = ""
	grab_w = 0.0
	_grabbed.clear()
	l_set = 0.0
	land_target = 0.0
	pitch0 = 0.0
	yaw = PI if absf(wrapf(yaw, -PI, PI)) > PI * 0.5 else 0.0
	twist_target = yaw
	pitch = 0.0
	l_pitch = 0.0
	l_twist = 0.0
	tuck = 0.0
	omega_pitch = 0.0
	active = ""
	_merge_combos()
	_name_positions()
	if not performed.is_empty():
		var base := 0
		for n in performed:
			base += _points_for(n)
		var mult := 1.0 + 0.5 * (performed.size() - 1)
		var pts := int(base * mult * points_scale)
		score += pts
		tricks_landed += performed.size()
		best_combo = maxi(best_combo, performed.size())
		if points_scale >= 1.0:
			var tag: String = {"perfect": "  PERFECT TIMING", "late": "  late"}.get(timing, "")
			_say("%s  +%d%s%s" % [" + ".join(performed), pts, ("  x%.1f" % mult) if performed.size() > 1 else "", tag])
		landed.emit(performed.duplicate(), pts)
	performed.clear()


## Flips out of / into a body position are named after them, e.g.
## "Chest Backflip to Butt" (bonus points for each position).
var _pos_bonus := 0


func _name_positions() -> void:
	_pos_bonus = 0
	if performed.is_empty():
		return
	var from: String = POSE_NAMES.get(start_pose, "")
	var to: String = POSE_NAMES.get(landing_pose, "")
	if from == "" and to == "":
		return
	var first: String = performed[0]
	if not (first.contains("flip") or first.contains("Twist")):
		return
	# Named butt-to-butt flips (trickline names)
	if start_pose == "butt" and landing_pose == "butt" and first in ["Frontflip", "Backflip"]:
		var named := "Manson Flip" if first == "Frontflip" else "Angel Flip"
		_pos_bonus = 450
		_pos_names[named] = first
		performed[0] = named
		return
	var n := first
	if from != "":
		n = from + " " + n
		_pos_bonus += 150
	if to != "":
		n += " to " + to
		_pos_bonus += 150
	_pos_names[n] = first
	performed[0] = n


var _pos_names := {}


func award(trick_name: String, points: int) -> void:
	score += points
	tricks_landed += 1
	best_combo = maxi(best_combo, 1)
	_say("%s  +%d" % [trick_name, points])
	landed.emit([trick_name], points)


func say(text: String) -> void:
	_say(text)


func reset() -> void:
	ref = null
	grab = ""
	grab_w = 0.0
	_grabbed.clear()
	l_set = 0.0
	land_target = 0.0
	pitch0 = 0.0
	start_pose = ""
	active = ""
	queued = ""
	queued_twist = ""
	queued_pose = ""
	performed.clear()
	pitch = 0.0
	yaw = 0.0
	twist_target = 0.0
	l_pitch = 0.0
	l_twist = 0.0
	tuck = 0.0
	omega_pitch = 0.0


func tick_message(dt: float) -> void:
	message_time = maxf(0.0, message_time - dt)


func _bail(reason: String) -> void:
	ref = null
	_say("BAIL! " + reason)
	bailed.emit(reason)
	reset()


func _say(text: String) -> void:
	message = text
	message_time = 2.5


## A single flip and a twist landed in the same jump become the named combo.
func _merge_combos() -> void:
	for k in COMBOS:
		var c: Dictionary = COMBOS[k]
		var twist: String = "Full Twist" if "spin360" in c["parts"] else "Half Twist"
		if c["flip"] in performed and twist in performed:
			performed.erase(c["flip"])
			performed.erase(twist)
			performed.insert(0, c["name"])
			return


func _points_for(display_name: String) -> int:
	for k in GRABS:
		if GRABS[k]["name"] == display_name:
			return int(GRABS[k]["points"])
	if _pos_names.has(display_name):
		return _points_for(_pos_names[display_name]) + _pos_bonus
	for k in COMBOS:
		if COMBOS[k]["name"] == display_name:
			return int(COMBOS[k]["points"])
	var mult := 1
	var n := display_name
	if " x" in n:
		mult = int(n.get_slice(" x", 1))
		n = n.get_slice(" x", 0)
	for k in TRICKS:
		if TRICKS[k]["name"] == n:
			return int(TRICKS[k]["points"]) * mult * (2 if mult > 1 else 1)
	return 0
