class_name Athlete
extends RigidBody3D
## Placeholder athlete. Hybrid physics:
##  * ON_LINE  - body is frozen (kinematic) at the feet. Vertical dynamics are a
##               two-body system (LegModel): the centre of mass rides on a
##               muscle-actuated leg whose feet sit on the line. Load, recoil,
##               takeoff and landing absorption all emerge from leg + line
##               forces. Lateral balance is a BalanceController pendulum.
##  * AIRBORNE - Godot rigid body physics (rotation locked) carries the jump.
##  * FALLEN   - Godot rigid body physics, rotation unlocked, tumbles to ground.
## Origin of this body is at the FEET.

signal state_changed(new_state: int)
signal launched(launch_velocity: Vector3)
signal contact_started(contact_name: String)

enum State { ON_LINE, AIRBORNE, FALLEN }

const ReboundMeterScript := preload("res://scripts/athlete/rebound_meter.gd")

## --- Arcade tuning (menu: Line Explosiveness) + combo power ------------
## push scales the leg drive, air_g the gravity in flight. Clean trick
## landings raise the POWER level (+12 % leg drive each, up to 5); a bail,
## a fall or a saved landing drops it back to zero.
signal power_changed(level: int)
var arcade_push: float = 1.0
var arcade_air_g: float = 1.0
var power_level: int = 0
const POWER_MAX := 5
const POWER_STEP := 0.12
var _base_f_max: float = -1.0
var _base_v_max: float = -1.0


func apply_arcade(push: float, air_g: float) -> void:
	arcade_push = push
	arcade_air_g = air_g
	gravity_scale = air_g
	tricks.air_gravity = 9.81 * air_g


func power_multiplier() -> float:
	return arcade_push * (1.0 + POWER_STEP * power_level)


func set_power(level: int) -> void:
	level = clampi(level, 0, POWER_MAX)
	if level != power_level:
		power_level = level
		power_changed.emit(level)


func _update_arcade_drive() -> void:
	if _base_f_max < 0.0:
		_base_f_max = leg.f_max
		_base_v_max = leg.v_max
	var m := power_multiplier()
	leg.f_max = _base_f_max * m
	leg.v_max = _base_v_max * sqrt(m)
	line.solver.arcade_contact = state == State.ON_LINE and leg.force > 150.0


## --- Sticky bounce (butt bounce with both hands gripping the line) -----
## Hold GRAB while sitting in a butt bounce: both hands close on the line and
## the body stays attached (no takeoff). SPACE hold = pull in / compress,
## release = push away / extend: pumping in time with the line builds its
## amplitude through actuator work only. Let go of GRAB to release: the line's
## stored energy throws you up through the normal (unilateral) contact.
signal sticky_changed(active: bool)
@export var sticky_stroke: float = 0.30        # m of hip/arm stroke above the sitting height
@export var sticky_pull_in: float = 0.03       # m below sitting height the arms pull toward
var sticky: bool = false
var sticky_time: float = 0.0
var sticky_cycles: int = 0
var sticky_work: float = 0.0                   # J of actuator work put into the line while gripping
var _sticky_prev_vf: float = 0.0

## --- Takeoff rotation from the body lean (two-zone controls) -----------
## The right-hand AIM leans the body fore/aft while loading and pushing. The
## line pushes through the feet, the centre of mass is offset by the lean, so
## the push is off-axis: L = m * v_up * lever (lever = COM height * sin lean).
## Nothing adds rotation in the air: tuck/open only change the speed.
@export var aim_lean_max: float = 0.26          # rad of fore/aft lean at full aim
@export var pose_takeoff_lever: float = 0.16    # m, hip drive lever from butt/chest/back
@export var twist_set_gain: float = 6.0         # kg m^2/s of twist L at full aim and push
## Air: arms/hips can re-orient the body a little without any new angular
## momentum (shape change); bounded per flight.
@export var air_attitude_rate: float = 0.9      # rad/s
@export var air_attitude_max: float = 0.35      # rad per flight
var takeoff_aim: Vector2 = Vector2.ZERO
var _aim_seen_t: float = 0.0

@export var athlete_mass: float = 75.0
@export var walk_speed: float = 0.9               # m/s along the line
## Leaning into the takeoff (W/S held) sends you along the line.
@export var forward_jump_speed: float = 1.6       # m/s at full lean
## SPACE held: squat (leg target drops at this rate). Release: leg drives to
## full extension for `push_time`. How deep, how fast and WHEN you do this
## decides how much energy goes into the line - nothing else adds energy.
@export var dip_speed: float = 2.5                # m/s target change while squatting
@export var push_time: float = 0.35               # s of full-extension drive after release
@export var stance_bend: float = 0.03             # m below lockout when standing
@export var land_lateral_tolerance: float = 0.35  # m, foot must be this close
@export var walk_disturbance: float = 1.6         # rad/s^2 noise at full speed
@export var idle_disturbance: float = 0.35
@export var fallen_reset_time: float = 2.5
@export var end_margin: float = 0.8               # keep away from anchors, m

var line: Slackline
var input: AthleteInput
var balance := BalanceController.new()
var leg := LegModel.new()
var tricks := TrickController.new()
var rebound_meter = ReboundMeterScript.new()
var _super_rebound_active := false
var _energy_awarded_this_landing := false
# --- arm swing (sagittal) ---
## Both arms swing as one ~7.4 kg pair (2 x 4.9 % body mass) about the
## shoulders, COM 0.33 m out. Down while sinking into the line, up while
## driving out of it and rising, down again to prepare a landing.
var arm_swing: float = 0.0       # rad from hanging, + forward/up
var arm_swing_v: float = 0.0
var _arm_y_prev: float = -0.33
var _arm_vy_prev: float = 0.0
const ARM_PAIR_FRAC := 0.098
const ARM_COM_R := 0.33
var gait_phase: float = 0.0
@export var stride_length: float = 0.55  # m per step pair on a line
var _prev_walk_v: float = 0.0
var _walk_v: float = 0.0
## Walking speeds up/slows down gently: a stop must flip the body's lean
## (into the deceleration) within what the feet on the webbing can hold.
@export var walk_accel: float = 0.4
var _rising_from: String = ""   # position the leg drive is lifting out of
var _rise_t: float = 0.0
## Motion library (tools/mocap). Key: start>trick>landing.
const MOCAP_REFS := {
	"feet>backflip>feet": "res://assets/mocap/backflip_motion.json",
	"chest>frontflip>chest": "res://assets/mocap/real_chest_frontflip_chest.json",
	"chest>backflip>butt": "res://assets/mocap/real_chest_backflip_butt.json",
	"butt>backflip>feet": "res://assets/mocap/real_butt_backflip_feet.json",
	"butt>frontflip>chest": "res://assets/mocap/real_butt_frontflip_chest.json",
	"chest>backflip>feet": "res://assets/mocap/real_chest_backflip_feet.json",
}
var visual: AthleteVisual
var rng := RandomNumberGenerator.new()

var state: int = State.ON_LINE
var s: float = 0.0                 # position along line chord, m
var pump: float = 0.0              # 0..1 current pump amount
var foot_velocity := Vector3.ZERO
var foot_accel := Vector3.ZERO
var air_time: float = 0.0
var fallen_time: float = 0.0
var last_jump_height: float = 0.0
var jumps: int = 0
var landings: int = 0

var _lateral_force: float = 0.0
var _pending_velocity = null       # Vector3 or null, applied in _integrate_forces
var _pending_angular = null
var _launch_y: float = 0.0
var _apex_y: float = 0.0
var _push_left: float = 0.0
var _dip_target: float = 0.95
var _prev_air_dy: float = 1.0
## Slow running mean of the contact height = the bounce's centre line.
## dev > 0: line above centre (squat now), dev < 0: below (push now).
var line_mean_y: float = 0.0

## Line-trick body position ("" = standing).
const POSE_REACH := 0.22          # arms/hips can push the body this far off the line
const POSE_RISE_TIMEOUT := 1.0    # return to supported stance if a pose push stalls
const CONTACT_HISTORY_LIMIT := 32
var pose_strength: float = 0.6       # arms + hips pushing off the line vs the legs
@export var pose_push_reach: float = 0.35    # extra extension available during chest/back push-off
## Landing on the butt/chest/back: the soft body (glutes, chest, back) on the
## webbing absorbs much more than the stiff stop of a straight leg.
@export var pose_tissue_damping: float = 2500.0   # N*s/m
## Sitting on the line the legs hang: the push off the butt is a short,
## partial sit-to-stand (hips + thighs), not a full leg drive.
@export var landing_miss_gain: float = 3.0     # extra absorption per (miss / tolerance)^2
@export var impact_brace_speed: float = 4.0   # m/s, harder than this is braced
@export var impact_brace_gain: float = 3.0
@export var butt_push_reach: float = 0.35
@export var butt_push_strength: float = 0.7
const POSE_TIMEOUT := 4.0         # s without a takeoff -> stand up (no points)
## Technique assist for line tricks: push off with arms/hips automatically at
## the right moment of the recoil (a real force through the leg model). With
## SPACE you can time it yourself instead.
@export var pose_auto_push: bool = true
var _pose_pushed: bool = false
var _pose_contacted: bool = false  # butt/chest/back actually hit the line
var pose: String = ""
var pose_time: float = 0.0
var pose_blend: float = 0.0
var _pose_visual: String = ""
var _line_combo: int = 0          # consecutive line-trick bounces
var _launch_pose: String = ""     # position we took off from
var _landing_pose_explicit: bool = false
var _air_leg: float = 0.98        # COM-to-landing-contact distance in the air
var _air_leg_launch: float = 0.98
@export var contact_debug_enabled: bool = false
var contact_history: Array[Dictionary] = []
var contact_state_duration: float = 0.0
var last_landing_failure_reason: String = ""


func _ready() -> void:
	tricks.landed.connect(_on_tricks_landed)
	for id in MOCAP_REFS:
		var r := MotionReference.load_json(MOCAP_REFS[id])
		if r != null:
			tricks.references[id] = r
	mass = athlete_mass
	leg.body_mass = athlete_mass
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	can_sleep = false
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 1.75
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	visual = AthleteVisual.new()
	visual.name = "Visual"
	add_child(visual)
	if input == null:
		input = AthleteInput.new()
		input.name = "Input"
		add_child(input)
	rng.seed = 7


func attach(to_line: Slackline) -> void:
	line = to_line


## Centre-of-mass velocity while on the line: feet velocity plus the
## pendulum's lateral swing. This, not the foot velocity, is what flies.
func com_velocity() -> Vector3:
	var lat := line.lateral_axis()
	var foot_lat := foot_velocity.dot(lat)
	var com_lat := foot_lat + balance.com_height * balance.omega * cos(balance.theta)
	if pose != "" or _rising_from != "":
		# lying/sitting on the line: the body moves with the line, no
		# standing-pendulum swing
		com_lat = foot_lat
	var v_up := leg.body_velocity(line.solver) if state == State.ON_LINE else foot_velocity.y
	return Vector3.UP * v_up + lat * com_lat


func com_world() -> Vector3:
	return global_position + Vector3.UP * balance.com_height


# ------------------------------------------------------------ simulation hooks
# Called by the SimulationDirector each physics tick:
#   athlete.pre_line_step(dt) -> line.simulate(dt) -> athlete.post_line_step(dt)

func pre_line_step(dt: float) -> void:
	if line == null:
		return
	if contact_debug_enabled:
		contact_state_duration += dt
	input.poll()
	# Body controls go straight to the balance model (knees + each arm).
	balance.knee_input = input.knees
	balance.arm_left_input = input.arm_left
	balance.arm_right_input = input.arm_right
	# Flip set-up: arms swing down and back while loading for a queued flip,
	# then throw up at takeoff (real arm torque in the balance model too).
	if state == State.ON_LINE and tricks.queued != "" and input.arm_left == 0.0 and input.arm_right == 0.0:
		var arms := -0.9 if bounce_dev() < 0.05 else 0.6
		balance.arm_left_input = arms
		balance.arm_right_input = arms
	if input.trick != "" and state != State.FALLEN:
		if TrickController.LINE_TRICKS.has(input.trick):
			if state == State.ON_LINE and pose == "" and (input.pump_held or absf(foot_velocity.y) > 0.6):
				# Explosive: a full leg drive (with arm swing) off the feet,
				# flying up and landing in the position.
				tricks.queued_pose = input.trick
				_landing_pose_explicit = true
				_push_left = push_time
			elif state == State.ON_LINE and pose == "":
				_enter_pose(input.trick, true)
			else:
				# In the air, or already bouncing in a position: this is where
				# you want to land next. Press nothing to land on your feet.
				if state == State.AIRBORNE:
					if tricks.set_landing(input.trick):
						tricks.queued_pose = input.trick
						_landing_pose_explicit = true
					else:
						tricks.say("Too late to change landing position")
				else:
					tricks.queued_pose = input.trick
					_landing_pose_explicit = true
		else:
			# Holding the direct rotation controls is the primary aerial input;
			# legacy discrete requests remain available to replay/test callers.
			var direct_rotation := absf(input.flip_axis) > 0.01 or absf(input.twist_axis) > 0.01
			if not direct_rotation:
				tricks.request(input.trick, state == State.AIRBORNE)
	_update_sticky(dt)
	tricks.tick_message(dt)
	if state == State.ON_LINE:
		if input.aim.length() > 0.15:
			takeoff_aim = input.aim
			_aim_seen_t = 0.0
		else:
			_aim_seen_t += dt
			if _aim_seen_t > 0.35:
				takeoff_aim = Vector2.ZERO   # aim let go well before the push
	_update_arm_swing(dt)
	pump = 1.0 if input.pump_held else 0.0
	leg.body_mass = athlete_mass
	leg.gravity = line.solver.gravity
	_update_arcade_drive()
	if state == State.ON_LINE:
		if pose == "":
			var line_len := line.chord_length()
			# walking speed builds up over steps (~2 m/s^2), it doesn't jump
			_walk_v = move_toward(_walk_v, input.move_axis * walk_speed, walk_accel * dt)
			s = clampf(s + _walk_v * dt, end_margin, line_len - end_margin)
		leg.s = s
		leg.lateral_force = _lateral_force if pose == "" else 0.0
		leg.target = _leg_command(dt)
		_update_rebound_boost()
		# the extra give of a braced/sloppy landing lasts that one contact
		if leg.leg_speed(line.solver) > 0.0:
			leg.c_leg = move_toward(leg.c_leg, 1000.0, 6000.0 * dt)


## Leg target length from the controls (the only way the athlete adds energy).
func _leg_command(dt: float) -> float:
	var stance := leg.l_max - stance_bend - balance.knee_input * 0.22
	if input.jump_released:
		_push_left = push_time
	if sticky:
		# hold = pull the body in toward the line, release = push away from it
		return leg.l_pose - sticky_pull_in if input.pump_held else leg.l_pose + sticky_stroke
	if pose != "":
		# Same controls as on the feet: SPACE hold = load low, release = push
		# off the line with arms and hips.
		# SPACE hold = stay low and ride the line; release (or the auto
		# timing, on the recoil) = drive the legs back under you and up.
		if input.pump_held:
			_pose_pushed = true      # player is timing it manually
			return leg.l_pose
		var vf := line.sample_velocity(s).y
		var auto := pose_auto_push and not _pose_pushed and _pose_contacted and vf > 0.3
		if (input.jump_released and _pose_contacted) or auto:
			_rise_from_pose()
			return leg.l_max + 0.05
		return leg.l_pose + 0.04
	if input.pump_held:
		_dip_target = move_toward(_dip_target, leg.l_min + 0.04, dip_speed * dt)
		_push_left = 0.0
		return _dip_target
	_dip_target = maxf(_dip_target, leg.leg_length(line.solver))
	if _push_left > 0.0:
		_push_left -= dt
		return leg.l_max + 0.05      # drive to full extension
	_dip_target = stance
	return stance


func _update_rebound_boost() -> void:
	if _super_rebound_active and _push_left <= 0.0 and _rising_from == "":
		_super_rebound_active = false
	if not _super_rebound_active and rebound_meter.is_ready() and (_push_left > 0.0 or _rising_from != ""):
		_super_rebound_active = rebound_meter.consume() > 0.0
		if _super_rebound_active:
			tricks.say("SUPER REBOUND CHARGED!")
	leg.rebound_boost = 1.0 if _super_rebound_active else 0.0


func _on_tricks_landed(names: Array, points: int) -> void:
	if state != State.AIRBORNE or tricks.last_outcome != "clean" or names.is_empty():
		return
	var gain := 0.18 + minf(float(points) / 10000.0, 0.35) + 0.04 * maxf(0.0, names.size() - 1.0)
	rebound_meter.earn(gain)
	_energy_awarded_this_landing = true
	set_power(power_level + 1)


## Steps the line; while standing on it, the leg exchanges forces with the
## line at every solver substep.
func simulate_line(dt: float) -> void:
	if state == State.ON_LINE:
		line.simulate(dt, Callable(leg, "pre_substep"), Callable(leg, "post_substep"))
	else:
		line.clear_contact()
		line.simulate(dt)


func post_line_step(dt: float) -> void:
	if line == null:
		return
	match state:
		State.ON_LINE:
			_update_on_line(dt)
		State.AIRBORNE:
			_update_airborne(dt)
		State.FALLEN:
			_update_fallen(dt)
	var crouch := balance.crouch
	var arm_l := balance.arm_left
	var arm_r := balance.arm_right
	if state == State.AIRBORNE:
		# Tuck = knees to chest, hands to shins; twisting = arms wrapped in.
		crouch = 0.15
		if tricks.tuck > 0.2:
			arm_l = lerpf(arm_l, 0.9, tricks.tuck)
			arm_r = lerpf(arm_r, 0.9, tricks.tuck)
		elif tricks.l_twist != 0.0 and input.arm_left < 0.5 and input.arm_right < 0.5:
			arm_l = 0.35
			arm_r = 0.35
	visual.set_body(balance.theta if state != State.FALLEN else 0.0, crouch,
		arm_l, arm_r, balance.hip_input, balance.com_height)
	visual.set_trick_rotation(tricks.pitch, tricks.yaw)
	# Blend into / out of line-trick positions (visual only).
	var shown := pose
	if state == State.AIRBORNE and tricks.queued_pose != "":
		shown = tricks.queued_pose
	if state == State.ON_LINE and pose == "" and _rising_from != "":
		# driving up out of a position: the body stays in it until takeoff,
		# the flight's rotation (the set) brings it round from there
		_rise_t += dt
		shown = _rising_from
		if _rise_t > POSE_RISE_TIMEOUT:
			_recover_stalled_pose_rise()
	if shown != "":
		_pose_visual = shown
	pose_blend = move_toward(pose_blend, 1.0 if shown != "" else 0.0, dt * 7.0)
	if pose_blend <= 0.0:
		_pose_visual = ""
	var line_low := 0.0
	if state == State.ON_LINE:
		# Hanging shins need ~0.95 m under the butt; below that they swing
		# forward so the feet never go through the floor.
		line_low = clampf((1.0 - (line.sample_world(s).y - line.ground_height)) / 0.45, 0.0, 1.0)
	# In the air the body's orientation is the flight rotation (tricks.pitch);
	# the position only shapes the limbs.
	visual.set_line_pose(_pose_visual, pose_blend, line_low, 0.0 if state == State.AIRBORNE else 1.0)
	visual.set_character_state(state == State.ON_LINE and _pose_visual == "",
		tricks.tuck if state == State.AIRBORNE else 0.0)
	if visual.character != null:
		visual.character.air_shift = move_toward(visual.character.air_shift,
			1.0 if state == State.AIRBORNE else 0.0, dt * 10.0)
	# Captured limb shapes from the motion reference (body rotation and
	# flight path stay physical).
	if state == State.AIRBORNE and tricks.ref != null:
		var u := tricks.ref_phase()  # flight phase: slow-motion source timing does not matter
		var r := tricks.ref
		visual.set_reference_limbs(deg_to_rad(r.sample("hip", u)), deg_to_rad(r.sample("knee", u)),
			deg_to_rad(r.sample("shoulder", u)), deg_to_rad(r.sample("elbow", u)), 1.0, dt)
	else:
		visual.set_reference_limbs(0.0, 0.0, 0.0, 0.0, 0.0, dt)
	# The tuck that sets the inertia (I_tuck) is drawn at the same depth:
	# hips ~120 deg, knees ~130 deg flexed at full tuck.
	visual.set_tuck(tricks.tuck if state == State.AIRBORNE else 0.0)
	# Every joint from the physics state (independent legs, loose arms,
	# bounce positions, grabs), each through its own spring-damper.
	visual.apply_body({
		"state": state, "pose": _pose_visual, "pose_b": pose_blend,
		"gait": gait_phase, "walk": clampf(absf(_walk_v) / maxf(walk_speed, 0.01), 0.0, 1.0),
		"lift_l": balance.leg_lift_l, "lift_r": balance.leg_lift_r,
		"arm_flex": balance.arm_flex, "phi": balance.phi,
		"grab": tricks.grab, "grab_w": tricks.grab_w,
		"arm_swing": arm_swing,
		"land_pt": _land_point, "land_w": _land_w,
		# point on the line under the left shoulder (chest bounce hand)
		"line_pt": Vector3(-0.02, 0.03, -0.62),
		"sticky": sticky,
	}, dt)
	if state != State.FALLEN:
		visual.keep_feet_above(line.ground_height)
	visual.finish_frame(dt)


func _update_on_line(dt: float) -> void:
	var foot := line.sample_world(s)
	var vel := line.sample_velocity(s)
	foot_accel = (vel - foot_velocity) / dt
	foot_velocity = vel
	if pose != "":
		global_transform = Transform3D(_line_basis(), foot + Vector3.UP * 0.01)
		balance.leg_length_override = leg.leg_length(line.solver)
		line_mean_y += (foot.y - line_mean_y) * minf(1.0, dt / 1.2)
		if leg.takeoff:
			launch(com_velocity())
			return
		_update_pose(dt, vel)
		return
	balance.leg_length_override = leg.leg_length(line.solver)
	line_mean_y += (foot.y - line_mean_y) * minf(1.0, dt / 1.2)
	var lat_acc := foot_accel.dot(line.lateral_axis())
	# Walking: no random noise. Each step the swing leg's mass is carried
	# beside the line and the stance foot is a point: that rocks the body
	# (physical gait torque, in rad/s^2 about the line).
	var speed := absf(_walk_v)
	gait_phase = fmod(gait_phase + TAU * speed / stride_length * dt, TAU)
	var disturbance := 0.0
	if speed > 0.01:
		var swing_side := signf(sin(gait_phase))   # +1 left leg swinging
		var swing := absf(sin(gait_phase))
		var tq := athlete_mass * balance.leg_mass_frac * 9.81 * 0.06 * swing * swing_side
		disturbance = tq / balance.inertia() * (1.0 - 0.5 * balance.crouch)
	balance.leg_input = input.leg_lift
	balance.step(dt, input.balance_axis, lat_acc, foot_accel.y, disturbance, pump)
	# forward/back: line surge along its axis + walking start/stop
	var a_walk := (_walk_v - _prev_walk_v) / dt
	_prev_walk_v = _walk_v
	# lean into the acceleration (like anyone starting/stopping a walk)
	balance.phi_ref = clampf(a_walk / 9.81, -0.1, 0.1)
	# AIM: lean back (backflip) / forward (frontflip) while loading + driving
	# (only during the drive: held statically, a lean that big tips you over)
	# and only on a real drive off a rising line - a lean on a weak push that
	# doesn't leave the line just tips you over)
	if not input.hold and foot_velocity.y > 0.8 and (_push_left > 0.0 or leg.leg_speed(line.solver) > 0.05):
		balance.phi_ref += -takeoff_aim.y * aim_lean_max
	balance.step_fb(dt, foot_accel.dot(line.axis()) + a_walk, foot_accel.y)
	_lateral_force = balance.reaction_lateral_force(athlete_mass)
	global_transform = Transform3D(_line_basis(), foot + Vector3.UP * 0.01)
	if balance.fallen:
		fall("balance limit")
		return
	# Takeoff is decided by the leg model: leg fully extended while the body
	# keeps moving away from the line.
	if leg.takeoff:
		launch(com_velocity())


func _update_airborne(dt: float) -> void:
	air_time += dt
	balance.step_air(dt, input.balance_axis)
	# Hold the flip key or SPACE in the air = tuck (faster rotation).
	tricks.update_air(dt, input.tuck, input.grab, input.flip_axis, input.twist_axis)
	tricks.adjust_attitude(dt, input.stick.y * air_attitude_rate, air_attitude_max)
	# Prepare the landing: straight legs for feet, or the chosen line-trick
	# position (Z/X/C pressed in the air).
	var land_leg := leg.l_pose if tricks.queued_pose != "" else leg.l_max
	_air_leg = move_toward(_air_leg, land_leg, dt * 3.0)
	balance.leg_length_override = _air_leg
	visual.position.y = _air_leg_launch - _air_leg
	_apex_y = maxf(_apex_y, global_position.y)
	var feet := global_position + Vector3.UP * (_air_leg_launch - _air_leg)
	var ls := line.project_s(feet)
	var vy := linear_velocity.y
	if ls > 0.3 and ls < line.chord_length() - 0.3 and air_time > 0.08:
		var lp := line.sample_world(ls)
		var dy := feet.y - lp.y
		var lat_off := (feet - lp).dot(line.lateral_axis())
		# Unilateral contact: the feet crossed the line since last frame
		# (falling onto it, or the line snapping up into the feet).
		var closing := vy - line.sample_velocity(ls).y <= 0.0
		# (a weak hop can leave the line rebounding past the feet from below:
		# shallow penetration still counts as contact)
		var crossed := dy < 0.04 and (_prev_air_dy >= -0.02 or dy > -0.3)
		_prev_air_dy = dy
		if crossed and closing:
			var tol := land_lateral_tolerance + (0.15 if tricks.queued_pose != "" else 0.0)
			if absf(lat_off) <= tol and absf(balance.theta) < balance.fall_angle:
				if tricks.on_land():
					land(ls, lat_off)
					if tricks.last_outcome != "clean":
						# Saved on chest/back after over/under-rotating: not under
						# control, so the balance takes a hit you have to correct.
						set_power(power_level - 2)
						balance.grace = 0.0
						balance.omega += rng.randf_range(0.8, 1.5) * (1.0 if rng.randf() < 0.5 else -1.0)
				else:
					last_landing_failure_reason = "rotation outside save window"
					fall("rotation bailout")
				return
			else:
				var reason := "lateral miss" if absf(lat_off) > tol else "excessive lateral lean"
				if reason != last_landing_failure_reason:
					last_landing_failure_reason = reason
					_record_contact_event("landing rejected: " + reason)
	# Missed the line: below it, descending, close to the ground.
	# (no "descending" requirement once the body is down at the ground: the
	# ground collider stops it at vy = 0, which used to leave the athlete
	# stuck in AIRBORNE on the sand forever)
	var low: float = minf(feet.y, global_position.y)
	if air_time > 0.15 and vy < 0.5 and low < line.ground_height + 0.25:
		last_landing_failure_reason = "missed line; ground clearance reached"
		fall(last_landing_failure_reason)
	elif not global_position.is_finite() or not linear_velocity.is_finite():
		# A bad numeric state is the only airborne watchdog: valid high flights
		# remain governed by gravity and physical line/ground contact, with no
		# arbitrary flight-duration or altitude cutoff.
		last_landing_failure_reason = "non-finite airborne state"
		reset_to_line(line.chord_length() * 0.5)


func _update_fallen(dt: float) -> void:
	fallen_time += dt
	if fallen_time > fallen_reset_time:
		reset_to_line(line.chord_length() * 0.5)


# ------------------------------------------------------------ transitions

func launch(v: Vector3) -> void:
	if state != State.ON_LINE:
		return
	_energy_awarded_this_landing = false
	# Leaving the line from a butt/chest/back position completes that bounce.
	var contact_source := pose if pose != "" else _rising_from
	_launch_pose = contact_source
	var hop := false
	if pose != "" and not _pose_contacted:
		# Separated while still falling into the position (the line dropped
		# away): no bounce yet - keep falling into the same position.
		tricks.queued_pose = pose
		pose = ""
		hop = true
	elif pose != "":
		_award_line_pose(pose)
		pose = ""
	elif _rising_from != "" and _pose_contacted:
		_award_line_pose(_rising_from)
	if not _landing_pose_explicit:
		tricks.queued_pose = contact_source
	# Lean into the takeoff to travel along the line; flips lean you too.
	var lean := input.move_axis
	if tricks.queued == "frontflip":
		lean += 0.3
	elif tricks.queued == "backflip":
		lean -= 0.2
	v += line.axis() * clampf(lean, -1.0, 1.0) * forward_jump_speed
	_air_leg_launch = leg.leg_length(line.solver)
	_air_leg = _air_leg_launch
	line.clear_contact()
	air_time = 0.0
	jumps += 1
	_launch_y = global_position.y
	_apex_y = _launch_y
	lock_rotation = true
	freeze = false
	_pending_velocity = v
	_pending_angular = Vector3.ZERO
	linear_velocity = v
	_super_rebound_active = false
	leg.rebound_boost = 0.0
	launched.emit(v)
	_set_state(State.AIRBORNE)
	var from := _launch_pose if _launch_pose != "" else _rising_from
	var from_angle: float = TrickController.POSE_ANGLE.get(from, 0.0) * pose_blend
	_rising_from = ""
	# for the flight-time prediction: contact point drops when landing low
	tricks.pose_drop = leg.l_max - leg.l_pose
	tricks.launch_drop = leg.l_max - _air_leg_launch
	if _launch_pose != "" and tricks.queued_pose == _launch_pose and not _pose_contacted:
		# not a real takeoff: still falling into the position (the line
		# dropped away). Keep any flip that is set for the real one.
		var keep := tricks.queued
		var keep_t := tricks.queued_twist
		tricks.queued = ""
		tricks.queued_twist = ""
		# keep the orientation exactly; no flip, no set
		tricks.on_launch(v.y, from, TrickController.POSE_ANGLE.get(from, 0.0))
		tricks.hop = true
		tricks.queued = keep
		tricks.queued_twist = keep_t
	else:
		tricks.on_launch(v.y, from, from_angle)
		tricks.hop = false
	if not tricks.hop and tricks.active == "" and tricks.queued == "":
		_set_takeoff_rotation(v.y, contact_source)
		# A plain push out of a butt/chest/back bounce (no flip) recovers to the
		# feet by default; with a flip, the takeoff position stays the default
		# landing. A position button pressed by the player always wins.
		if contact_source != "" and not _landing_pose_explicit and absf(tricks.l_pitch - tricks.l_set) < 8.0:
			tricks.queued_pose = ""
			tricks.set_landing("")
	_prev_air_dy = 1.0
	last_landing_failure_reason = ""
	_record_contact_event("takeoff from " + (contact_source if contact_source != "" else "feet"))


## Angular momentum at takeoff from how the body was leaning on the push.
func _set_takeoff_rotation(v_up: float, from_pose: String) -> void:
	var push := maxf(v_up, 0.0)
	var lever: float
	if from_pose == "":
		lever = balance.com_height * sin(balance.phi)   # the real lean (physics state)
	else:
		lever = -takeoff_aim.y * pose_takeoff_lever
	var l_pitch := clampf(athlete_mass * push * lever, -tricks.l_max, tricks.l_max)
	var l_twist := takeoff_aim.x * twist_set_gain * clampf(push / 4.0, 0.3, 1.0)
	tricks.launch_spin(l_pitch, l_twist)
	takeoff_aim = Vector2.ZERO


func _award_line_pose(contact_type: String) -> void:
	_line_combo += 1
	var info: Dictionary = TrickController.LINE_TRICKS[contact_type]
	var label: String = info["name"] + ("  x%d" % _line_combo if _line_combo > 1 else "")
	tricks.award(label, int(info["points"]) * _line_combo)


func land(at_s: float, lateral_offset: float) -> void:
	if state != State.AIRBORNE:
		return
	last_jump_height = _apex_y - _launch_y
	if tricks.last_outcome == "clean" and not _energy_awarded_this_landing:
		rebound_meter.earn(0.08)
	_energy_awarded_this_landing = false
	landings += 1
	s = clampf(at_s, end_margin, line.chord_length() - end_margin)
	var v := linear_velocity
	freeze = true
	visual.position.y = 0.0
	# The contact (feet, or butt/chest/back) joins the line with its momentum;
	# the COM lands on the leg / body.
	var v_impact := absf(v.y - line.sample_velocity(s).y)   # before body and line merge
	leg.land(line.solver, s, _air_leg - 0.01, v.y, v.dot(line.lateral_axis()))
	_set_contact_geometry("")
	_push_left = 0.0
	_dip_target = leg.l_max - stance_bend
	foot_velocity = line.sample_velocity(s)
	foot_accel = Vector3.ZERO
	# Knees absorb; off-centre landings still give a small wobble.
	balance.absorb_landing()
	balance.omega += lateral_offset * 1.5
	# Landing quality: off-angle or off the line, the body can't take the
	# line's energy cleanly - joints give and tissue absorbs it. A clean
	# landing keeps the bounce; a sloppy one loses part of it.
	var miss := pow(tricks.land_error / TrickController.LAND_TOLERANCE, 2.0) + pow(lateral_offset / 0.45, 2.0)
	var c_quality := 1000.0 * (1.0 + landing_miss_gain * miss)
	leg.c_leg = minf(c_quality, 9000.0)
	if tricks.queued_pose != "":
		_enter_pose(tricks.queued_pose, false)
		# Hard landings in a position are braced: the body absorbs more the
		# faster it hits (eccentric muscle work + soft tissue), light ones
		# keep their bounce. This is what limits how high bounces build up.
		var vi := v_impact
		var over := maxf(0.0, vi - impact_brace_speed) / 2.0
		leg.c_leg = minf(maxf(leg.c_leg, 1000.0 * (1.0 + impact_brace_gain * over * over)), 9000.0)
		# the flight rotated the body into the position: hand it over
		_pose_visual = tricks.queued_pose
		pose_blend = 1.0
		_pose_contacted = leg.leg_length(line.solver) <= leg.l_pose + 0.05
		_pose_pushed = not _pose_contacted
		tricks.queued_pose = ""
	else:
		_line_combo = 0   # back on the feet: line-trick combo ends
	pump = 0.0
	_landing_pose_explicit = false
	last_landing_failure_reason = ""
	_record_contact_event("landed in " + (pose if pose != "" else "feet"))
	_set_state(State.ON_LINE)
	global_transform = Transform3D(_line_basis(), line.sample_world(s))


func fall(reason: String = "unspecified") -> void:
	if state == State.FALLEN:
		return
	set_power(0)
	last_landing_failure_reason = reason
	_record_contact_event("fall: " + reason)
	var b := _line_basis() * Basis(Vector3(0, 0, -1), balance.theta) * Basis(Vector3.RIGHT, -balance.phi)
	var v := foot_velocity if state == State.ON_LINE else linear_velocity
	v += line.lateral_axis() * balance.omega * balance.com_height * 0.5
	line.clear_contact()
	_set_state(State.FALLEN)
	fallen_time = 0.0
	visual.set_body(0.0, 0.0, balance.arm_left, balance.arm_right, 0.0, balance.com_height)
	lock_rotation = false
	global_transform = Transform3D(b, global_position)
	freeze = false
	_pending_velocity = v
	_pending_angular = line.axis() * balance.omega - line.lateral_axis() * balance.phi_dot
	linear_velocity = v


func reset_to_line(at_s: float) -> void:
	end_sticky("reset")
	freeze = true
	lock_rotation = true
	_pending_velocity = null
	_pending_angular = null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	s = clampf(at_s, end_margin, line.chord_length() - end_margin)
	line.settle(s, athlete_mass)
	leg.body_mass = athlete_mass
	var stance := leg.l_max - stance_bend
	leg.target = stance
	# Start at the leg's static equilibrium so nothing jolts on reset.
	_set_contact_geometry("")
	leg.begin_contact(line.solver, s, stance - 0.025, 0.0)
	_line_combo = 0
	visual.position.y = 0.0
	line_mean_y = line.sample_world(s).y
	_dip_target = stance
	_push_left = 0.0
	balance.reset(0.0)
	tricks.reset()
	pose = ""
	pose_blend = 0.0
	_pose_visual = ""
	_launch_pose = ""
	_rising_from = ""
	_rise_t = 0.0
	pose_time = 0.0
	_pose_contacted = false
	_pose_pushed = false
	_landing_pose_explicit = false
	air_time = 0.0
	fallen_time = 0.0
	_prev_air_dy = 1.0
	last_landing_failure_reason = ""
	pump = 0.0
	_lateral_force = 0.0
	foot_velocity = Vector3.ZERO
	foot_accel = Vector3.ZERO
	global_transform = Transform3D(_line_basis(), line.sample_world(s))
	_record_contact_event("reset to line")
	_set_state(State.ON_LINE)


# ------------------------------------------------------------ line tricks

## Line tricks: the legs let go, the body falls onto the line (butt / chest /
## back becomes the contact) and the line's recoil has to throw it back up.
func _enter_pose(id: String, _drop: bool) -> void:
	pose = id
	contact_started.emit(id)
	pose_time = 0.0
	_push_left = 0.0
	_pose_contacted = false
	_pose_pushed = true   # no push before the body has hit the line
	_set_contact_geometry(id)
	_record_contact_event("contact entered: " + id)


## Feet vs butt/chest/back contact: reach and strength of what pushes on the line.
func _set_contact_geometry(pose_id: String) -> void:
	if pose_id == "":
		leg.c_stop = 2500.0
		leg.c_leg = 1000.0
		leg.contact_max = leg.l_max
		leg.strength = 1.0
		leg.min_len = minf(leg.l_min, maxf(leg.l_pose + 0.002, leg.leg_length(line.solver)))
	else:
		leg.contact_max = leg.l_pose + POSE_REACH
		leg.strength = pose_strength
		leg.c_stop = pose_tissue_damping
		leg.min_len = leg.l_pose


func _update_pose(dt: float, vel: Vector3) -> void:
	pose_time += dt
	# Lying/sitting on the line is stable: lean bleeds away.
	balance.theta = move_toward(balance.theta, 0.0, dt * 1.5)
	balance.omega *= 0.85
	_lateral_force = 0.0
	if not _pose_contacted and leg.leg_length(line.solver) < leg.l_pose + 0.05:
		_pose_contacted = true
		_pose_pushed = false
	# The bounce ends physically with a takeoff (see _update_on_line). If the
	# line dies out under you, you climb back to your feet without points.
	if pose_time > POSE_TIMEOUT and not sticky:
		_stand_up_from_pose()


## Leg drive out of a butt/chest/back bounce, timed with the line's recoil:
## the bounce counts, the feet come back under the body and the legs extend.
## The takeoff that follows is physical (same leg model as from the feet).
var _land_point := Vector3.ZERO
var _land_w := 0.0


## Before a feet landing: where on the line the feet will touch, and how
## close in time that is (0 = far, 1 = touching).
func _update_landing_prediction() -> void:
	_land_w = 0.0
	if state != State.AIRBORNE or tricks.queued_pose != "" or linear_velocity.y >= 0.0:
		return
	if absf(tricks.pitch_error()) > 1.2:
		return
	var s_now := clampf(line.project_s(global_position), end_margin, line.chord_length() - end_margin)
	var lp := line.sample_world(s_now)
	var h := global_position.y - lp.y
	var vy := linear_velocity.y
	var g := tricks.air_gravity
	var ttc := (vy + sqrt(maxf(0.0, vy * vy + 2.0 * g * maxf(h, 0.0)))) / g
	_land_point = lp
	_land_w = clampf(1.0 - ttc / 0.45, 0.0, 1.0)


func _update_arm_swing(dt: float) -> void:
	_update_landing_prediction()
	var target := 0.4
	if state == State.ON_LINE and pose == "":
		var sinking := leg.leg_speed(line.solver) < -0.05 or (leg.contact_max > 0.0 and pump > 0.0)
		var driving := leg.leg_speed(line.solver) > 0.05 and not input.pump_held
		if sinking:
			target = -0.5         # down and back while loading the line
		elif driving:
			target = 2.6          # throw up while extending
	elif state == State.AIRBORNE:
		# rising: arms high; falling: bring them down for the landing
		target = 2.2 if linear_velocity.y > 0.0 else 0.9
	var w := 16.0
	var acc := w * w * (target - arm_swing) - 2.0 * 0.7 * w * arm_swing_v
	arm_swing_v += acc * dt
	arm_swing += arm_swing_v * dt
	arm_swing = clampf(arm_swing, -0.8, 3.0)
	# reaction on the body: m_arms * vertical acceleration of the arms' COM
	var y := -ARM_COM_R * cos(arm_swing)
	var vy := (y - _arm_y_prev) / dt
	var ay := (vy - _arm_vy_prev) / dt
	_arm_y_prev = y
	_arm_vy_prev = vy
	var f := athlete_mass * ARM_PAIR_FRAC * clampf(ay, -60.0, 60.0)
	# Only the drive phase loads the line: the arms' braking at the top of the
	# swing happens as the feet leave, so it is not fed back into the push.
	var driving_now := leg.leg_speed(line.solver) > 0.0
	leg.assist_force = maxf(f, 0.0) if state == State.ON_LINE and pose == "" and driving_now else 0.0


func _rise_from_pose() -> void:
	_rising_from = pose
	_rise_t = 0.0
	var from := pose
	pose = ""
	_set_contact_geometry("")
	# What actually pushes off the line out of a position: from the butt the
	# legs can drive a sit-to-stand (shorter stroke); from the chest or back
	# only the arms and hips (short stroke, weaker).
	var reach: float = butt_push_reach if from == "butt" else pose_push_reach
	leg.contact_max = leg.l_pose + reach
	leg.strength = butt_push_strength if from == "butt" else pose_strength
	_push_left = push_time
	_pose_pushed = true
	_record_contact_event("push attempt from " + from)


func _recover_stalled_pose_rise() -> void:
	var source := _rising_from
	_set_contact_geometry("")
	_rising_from = ""
	_rise_t = 0.0
	_pose_contacted = false
	_pose_pushed = false
	_dip_target = leg.l_max - stance_bend
	if not _landing_pose_explicit:
		tricks.queued_pose = ""
	if source != "":
		last_landing_failure_reason = source + " push did not reach takeoff; recovered to feet"
		_record_contact_event(last_landing_failure_reason)


func _record_contact_event(event_name: String) -> void:
	if not contact_debug_enabled:
		return
	var contact_type := pose if pose != "" else (_rising_from if _rising_from != "" else "feet")
	var point := line.sample_world(s) if line != null else global_position
	var velocity := linear_velocity if state != State.ON_LINE else com_velocity()
	var entry := {
		"event": event_name, "state": state_name(), "contact": contact_type,
		"duration": contact_state_duration, "point": point, "force": leg.force,
		"velocity": velocity, "angular_velocity": angular_velocity,
		"trick_angular_velocity": tricks.omega_pitch,
		"failure_reason": last_landing_failure_reason,
	}
	contact_history.append(entry)
	if contact_history.size() > CONTACT_HISTORY_LIMIT:
		contact_history.pop_front()
	print("CONTACT %s state=%s type=%s point=%s force=%.1f v=%s omega=%s trick_omega=%.2f duration=%.3f" % [event_name, state_name(), contact_type, point, leg.force, velocity, angular_velocity, tricks.omega_pitch, contact_state_duration])
	contact_state_duration = 0.0


func _stand_up_from_pose() -> void:
	tricks.say("Weak bounce - push off with SPACE, or bounce harder first")
	pose = ""
	_line_combo = 0
	_set_contact_geometry("")
	_dip_target = leg.l_max - stance_bend
	balance.reset(0.0)
	balance.grace = 0.8


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if _pending_velocity != null:
		st.linear_velocity = _pending_velocity
		_pending_velocity = null
	if _pending_angular != null:
		st.angular_velocity = _pending_angular
		_pending_angular = null


func _update_sticky(dt: float) -> void:
	var can_grip := state == State.ON_LINE and pose == "butt" and _pose_contacted and _rising_from == ""
	if sticky:
		if not can_grip:
			end_sticky("contact lost")
			return
		if not input.grip_held:
			end_sticky("released")
			return
		sticky_time += dt
		sticky_work += leg.force * leg.leg_speed(line.solver) * dt
		var vf := line.sample_velocity(s).y
		if _sticky_prev_vf < 0.0 and vf >= 0.0:
			sticky_cycles += 1          # line turned at the bottom: one pump cycle
		_sticky_prev_vf = vf
		pose_time = 0.0
		_pose_pushed = true             # no automatic push while holding on
	elif can_grip and input.grip_held:
		sticky = true
		sticky_time = 0.0
		sticky_cycles = 0
		sticky_work = 0.0
		_sticky_prev_vf = line.sample_velocity(s).y
		leg.grip = true
		_pose_pushed = true
		_record_contact_event("sticky grip")
		tricks.say("STICKY GRIP!")
		sticky_changed.emit(true)


## Hands open. The contact goes back to one-way: if the line is coming up,
## the body is thrown off it (and the hips/legs drive with it).
func end_sticky(reason: String) -> void:
	if not sticky:
		return
	sticky = false
	leg.grip = false
	_record_contact_event("sticky end: " + reason)
	sticky_changed.emit(false)
	if reason == "released" and state == State.ON_LINE and pose == "butt":
		_pose_pushed = false
		if line.sample_velocity(s).y > 0.3 and not input.pump_held:
			_rise_from_pose()


func _set_state(new_state: int) -> void:
	if new_state != State.ON_LINE and sticky:
		end_sticky("left the line")
	if state != new_state:
		var old_state := state_name()
		state = new_state
		_record_contact_event("state " + old_state + " -> " + state_name())
		state_changed.emit(new_state)


func _line_basis() -> Basis:
	# Faces +axis: local X = lateral (right), Y = up, Z = -axis.
	var ax := line.axis()
	var lat := line.lateral_axis()
	return Basis(lat, Vector3.UP, -ax)


## Bounce phase for the HUD/pilot: + above the bounce centre, - below.
func bounce_dev() -> float:
	return line.sample_world(s).y - line_mean_y if state == State.ON_LINE else 0.0


func state_name() -> String:
	return ["ON LINE", "AIRBORNE", "FALLEN"][state]
