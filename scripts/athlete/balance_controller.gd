class_name BalanceController
extends RefCounted
## Lateral (side-to-side) balance on a slackline, built from biomechanics
## research (see docs/PHYSICS.md "Balance — research basis"):
##
##  * Centre of mass (COM) at ~56 % of body height: just below the navel.
##    The line's restoring force points at the anchor chord, which is BELOW
##    the COM, so standing on a slackline is inherently unstable (inverted
##    pendulum on a moving foot).
##  * Strategies available on a line (foot placement / ankle are mostly gone):
##      - HIP strategy: move upper body against lower body  -> balance input
##      - ARMS: each arm is a separate segment. Swinging an arm throws angular
##        momentum into the body (reaction torque), and where the arm mass sits
##        shifts the COM sideways.
##      - KNEES: experts bend their knees. That lowers the COM and makes the
##        stance leg compliant, so it soaks up the line's sideways jerks
##        instead of passing them to the body.
##
##   I * theta'' = M g_eff l sin(theta) - M l a_foot_eff cos(theta)
##               + arm reaction + arm mass shift
##               + hip input + assist - damping
##
## theta > 0 = leaning toward +lateral (athlete's right).

# --- body (1.75 m, 75 kg athlete) ---
const BODY_HEIGHT := 1.75
const COM_RATIO := 0.56
var body_mass: float = 75.0
var arm_mass: float = 3.75            # each arm ~5 % body mass
var arm_length: float = 0.7
var arm_gain: float = 1.0             # 1 = physical (no extra multiplier)
var standing_com: float = BODY_HEIGHT * COM_RATIO   # 0.98 m
var knee_com_drop: float = 0.25       # COM height lost at full knee bend
var knee_compliance: float = 0.6      # share of line side-jerk soaked by bent knees

# --- arms (angle from hanging down: 0 = down, PI/2 = horizontal) ---
var arm_rest: float = 0.85            # relaxed: arms low and loose, reflexes lift them
var arm_raised: float = 2.75          # held up overhead
var arm_speed: float = 9.0            # max swing speed, rad/s
var arm_low: float = 0.25             # dropped arm
## Arms react to the lean on their own (one goes up, the other drops),
## the way people instinctively throw an arm out to save balance.
var arm_reflex: float = 2.2

# --- control ---
var max_input_accel: float = 6.0      # hip strategy authority, rad/s^2
## Automatic postural help as a fraction of what it would take to cancel
## gravity's tipping (critical = 1/assist_kp_ratio = 0.45). Kept BELOW
## critical, so the athlete always drifts and the player has to correct.
var assist: float = 0.3
var assist_kp_ratio: float = 2.2
var body_damping: float = 0.8
var fall_angle: float = 1.05
var air_control: float = 0.35
## In the air nothing pushes the body upright (no external torque): roll is
## only changed by the arms (internal torque). 0 = physical.
var air_righting: float = 0.0
var grace: float = 0.0
var gravity: float = 9.81

# --- inputs (set by the athlete each tick) ---
var knee_input: float = 0.0           # 0..1 hold to bend knees
var arm_left_input: float = 0.0       # 0..1 raise left arm
var arm_right_input: float = 0.0      # 0..1 raise right arm
var hip_input: float = 0.0            # last hip input (for visuals)
## Actual leg length from the LegModel (COM height). < 0 = use knee_input.
var leg_length_override: float = -1.0

# --- state ---
# --- sensorimotor delay: reflexes see the body ~150 ms late ---
var reflex_delay: float = 0.15
var _hist: Array[Vector2] = []
var theta_seen: float = 0.0
var omega_seen: float = 0.0
# --- legs: a lifted leg is a counterweight (thigh+shank+foot ~20 % BW) ---
var leg_mass_frac: float = 0.2
var leg_out: float = 0.28             # m sideways shift of the leg COM, fully out
var leg_input: float = 0.0            # 0..1 player: lift the free leg
var leg_lift_l: float = 0.0
var leg_lift_r: float = 0.0
var leg_reflex_start: float = 0.13    # rad of (seen) lean before a leg goes out
# --- forward/back (along the line): COM over the feet, ankles push ---
var phi: float = 0.0                  # + = falling forward
var phi_dot: float = 0.0
var phi_ref: float = 0.0              # lean the player asks for (walking)
var foot_half: float = 0.11           # m, front/back reach of the base of support
var fall_angle_fb: float = 0.65
var arm_flex: float = 0.0             # arms forward(+)/back(-) from the fwd/back reflex
var theta: float = 0.0
var omega: float = 0.0
var alpha: float = 0.0
var fallen: bool = false
var crouch: float = 0.0               # actual knee bend 0..1
var com_height: float = standing_com
var arm_left: float = arm_rest
var arm_right: float = arm_rest
var _arm_left_vel: float = 0.0
var _arm_right_vel: float = 0.0
var arm_left_acc: float = 0.0
var arm_right_acc: float = 0.0


func reset(initial_theta: float = 0.0) -> void:
	phi = 0.0
	phi_dot = 0.0
	leg_lift_l = 0.0
	leg_lift_r = 0.0
	_hist.clear()
	theta = initial_theta
	omega = 0.0
	alpha = 0.0
	fallen = false
	arm_left = arm_rest
	arm_right = arm_rest
	_arm_left_vel = 0.0
	_arm_right_vel = 0.0


## Knees and arms move every tick (on the line and in the air).
func update_limbs(dt: float, extra_crouch: float = 0.0) -> void:
	if leg_length_override > 0.0:
		# Physical leg length drives COM height and visual knee bend.
		com_height = clampf(leg_length_override, 0.15, standing_com)
		crouch = clampf((standing_com - com_height) / (standing_com - 0.55), 0.0, 1.0)
	else:
		var target_crouch := clampf(maxf(knee_input, extra_crouch), 0.0, 1.0)
		crouch = move_toward(crouch, target_crouch, dt * 5.0)
		com_height = standing_com * (1.0 - knee_com_drop * crouch)
	# Reflexes act on what the body sensed ~150 ms ago.
	_hist.append(Vector2(theta, omega))
	var n := maxi(1, int(round(reflex_delay / maxf(dt, 1e-4))))
	while _hist.size() > n:
		_hist.pop_front()
	theta_seen = _hist[0].x
	omega_seen = _hist[0].y
	# Leaning right (+theta): left arm up, right arm drops (and vice versa).
	var reflex := clampf(theta_seen * arm_reflex + omega_seen * 0.4, -1.0, 1.0)
	# Bigger lean: the leg on the high side swings out as a counterweight
	# (leaning right -> left leg out to the left).
	var lean_need := clampf((absf(theta_seen) - leg_reflex_start) / 0.2, 0.0, 1.0)
	var want_l := maxf(lean_need if theta_seen > 0.0 else 0.0, leg_input if theta_seen >= -0.02 else 0.0)
	var want_r := maxf(lean_need if theta_seen < 0.0 else 0.0, leg_input if theta_seen < -0.02 else 0.0)
	leg_lift_l = move_toward(leg_lift_l, want_l, dt * 4.0)
	leg_lift_r = move_toward(leg_lift_r, want_r, dt * 4.0)
	# Forward/back: arms swing against the fall (falling forward -> arms back).
	arm_flex = move_toward(arm_flex, clampf(-2.5 * phi - 0.5 * phi_dot, -1.2, 1.4), dt * 6.0)
	var r := _drive_arm(arm_left, _arm_left_vel, arm_left_input + reflex, dt)
	arm_left = r.x
	_arm_left_vel = r.y
	arm_left_acc = r.z
	r = _drive_arm(arm_right, _arm_right_vel, arm_right_input - reflex, dt)
	arm_right = r.x
	_arm_right_vel = r.y
	arm_right_acc = r.z


func _drive_arm(a: float, v: float, inp: float, dt: float) -> Vector3:
	var target := lerpf(arm_rest, arm_raised, clampf(inp, 0.0, 1.0)) if inp >= 0.0 \
		else lerpf(arm_rest, arm_low, clampf(-inp, 0.0, 1.0))
	var want_v := clampf((target - a) * 14.0, -arm_speed, arm_speed)
	var acc := clampf((want_v - v) / maxf(dt, 1e-4), -80.0, 80.0)
	v += acc * dt
	a = clampf(a + v * dt, 0.0, 3.0)
	return Vector3(a, v, acc)


func arm_torque() -> float:
	## Reaction to arm swing + sideways shift of arm mass (N*m, + = to the right).
	var i_arm := arm_mass * arm_length * arm_length / 3.0
	# Raising the LEFT arm rotates it in the +theta sense, so the body reacts
	# toward -theta; the right arm is the mirror image.
	var reaction := -i_arm * (arm_left_acc - arm_right_acc) * arm_gain
	var half := arm_length * 0.5
	var mass_shift := arm_mass * gravity * half * (sin(arm_right) - sin(arm_left))
	# lifted leg: its mass moves out to one side
	var legs := body_mass * leg_mass_frac * gravity * leg_out * (leg_lift_r - leg_lift_l)
	return reaction + mass_shift + legs


func inertia() -> float:
	var l := com_height
	var spread := 0.2 + 0.35 * (sin(arm_left) + sin(arm_right)) * 0.5
	return body_mass * l * l + 2.0 * arm_mass * spread * spread


## Advances the on-line balance state.
## `input` in [-1, 1] = hip strategy; accelerations in m/s^2; `disturbance` rad/s^2.
func step(dt: float, input: float, foot_accel_lat: float, foot_accel_vert: float,
		disturbance: float = 0.0, extra_crouch: float = 0.0) -> void:
	update_limbs(dt, extra_crouch)
	hip_input = clampf(input, -1.0, 1.0)
	if fallen:
		return
	var l := com_height
	var m := body_mass
	var g_eff := maxf(0.0, gravity + foot_accel_vert)
	var a_foot := foot_accel_lat * (1.0 - knee_compliance * crouch)
	var torque := m * g_eff * l * sin(theta) - m * l * a_foot * cos(theta) + arm_torque()
	alpha = torque / inertia()
	var eff_assist := assist
	if grace > 0.0:
		grace -= dt
		eff_assist = minf(1.0, assist + 0.35)
	# Control acts through the feet's sideways push on the webbing, which is
	# limited by how hard they are loaded: authority scales with g_eff / g
	# (more when the line pushes up, none when it drops away).
	var load := clampf(g_eff / gravity, 0.0, 3.0)
	var kp := eff_assist * assist_kp_ratio * g_eff / l
	var kd := eff_assist * 2.0 * sqrt(maxf(kp, 0.0)) * 0.6
	alpha += hip_input * max_input_accel * load
	alpha += -(kp * theta + kd * omega)
	alpha += -body_damping * omega
	alpha += disturbance
	omega += alpha * dt
	theta += omega * dt
	if absf(theta) > fall_angle:
		fallen = true


## Forward/back balance along the line. The feet lie ALONG the webbing, so
## here there is a real base of support: the ankles can push the COM back
## over the feet, but only up to the torque the foot length allows
## (m g * half foot). Beyond that the athlete topples forward/back.
## a_fwd: foot acceleration along the line (+ = forward).
func step_fb(dt: float, a_fwd: float, a_vert: float = 0.0) -> void:
	if fallen:
		return
	var l := com_height
	var m := body_mass
	# the line's vertical acceleration changes the support force: it scales
	# both the tipping torque and how much torque the feet can hold
	var g_eff := maxf(0.0, gravity + a_vert)
	var torque := m * g_eff * l * sin(phi) - m * l * a_fwd * cos(phi)
	var limit := m * g_eff * foot_half
	var ankle := -(m * g_eff * l * 1.6 * (phi - phi_ref) + m * l * l * 2.2 * phi_dot)
	ankle = clampf(ankle, -limit, limit)
	# arm swing reaction (arms going back push the body forward and v.v.)
	var phi_dd := (torque + ankle) / (m * l * l) - 0.8 * phi_dot
	phi_dot += phi_dd * dt
	phi += phi_dot * dt
	if absf(phi) > fall_angle_fb:
		fallen = true


## Airborne: no gravity torque about the feet; arms still throw momentum.
func step_air(dt: float, input: float) -> void:
	update_limbs(dt)
	hip_input = clampf(input, -1.0, 1.0)
	alpha = hip_input * max_input_accel * air_control - body_damping * omega
	alpha += -(air_righting * theta + 2.0 * sqrt(air_righting) * 0.8 * omega)
	var i_arm := arm_mass * arm_length * arm_length / 3.0
	alpha += -i_arm * (arm_left_acc - arm_right_acc) * arm_gain / inertia()
	omega += alpha * dt
	theta += omega * dt


## Knees absorb the touchdown: most of the lean and spin is soaked up.
func absorb_landing() -> void:
	phi *= 0.3
	phi_dot *= 0.3
	theta *= 0.5
	omega *= 0.3
	grace = 0.7


## Lateral force the athlete pushes into the line (N), from the COM
## accelerating relative to the feet (feet-following inertia is already
## lumped into the line).
func reaction_lateral_force(mass: float, limit: float = 600.0) -> float:
	var com_rel_accel := com_height * (alpha * cos(theta) - omega * omega * sin(theta))
	return clampf(-mass * com_rel_accel, -limit, limit)
