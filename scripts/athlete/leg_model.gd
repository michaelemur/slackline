class_name LegModel
extends RefCounted
## Two-body athlete <-> line coupling in the vertical direction.
##
##   COM (body minus feet) ── actuated leg ── feet (lumped into the line)
##
## The leg is a muscle-driven actuator, not an animation:
##  * PD servo toward a target leg length (the player's knee/hip command),
##    behaving like the "leg spring" of hopping biomechanics
##    (Ferris & Farley 1997: k_leg ~17.8 kN/m on hard ground, up to ~53 kN/m on
##    soft surfaces; default here 30 kN/m, tunable in the lab).
##  * Push-only (a foot cannot pull the line).
##  * Force-velocity limit: concentric force falls as extension speed rises
##    (Hill-type), eccentric (yielding) force may exceed it.
##  * Lockout: the leg cannot be longer than l_max. When the body keeps moving
##    away from the line with the leg fully extended, the feet leave the line:
##    takeoff emerges from the physics, it is not triggered by a button.
##  * Bottoming out: below l_min a stiff passive stop takes over.
## Energy enters the system only through actuator work F * dl/dt.

var body_mass: float = 75.0
var foot_mass: float = 6.0          # feet + part of shanks, rides with the line
var l_max: float = 0.98             # standing COM height (56 % of 1.75 m)
var l_min: float = 0.55             # deepest squat COM height
var l_pose: float = 0.15            # COM height sitting/lying on the line
var k_leg: float = 30000.0          # N/m
var assist_force: float = 0.0       # N, arm-swing reaction (set by the athlete)
var rebound_boost: float = 0.0      # 0..1; improves the next physical push limit
var rebound_boost_gain: float = 0.20
var c_leg: float = 1000.0           # N*s/m (below ~600 the foot-line mode rings)
var f_max: float = 2600.0           # N, max concentric push (~3.5 BW, assumption)
var eccentric_ratio: float = 1.5
var v_max: float = 3.5              # m/s, max leg extension speed
var k_stop: float = 60000.0         # N/m, bottom-out stop
var c_stop: float = 2500.0
var lockout_band: float = 0.03      # m, force fades to 0 at full extension
## Muscle activation delay: commands reach the leg through a first-order lag
## (muscles cannot switch force instantly).
var activation_tau: float = 0.06    # s
var gravity: float = 9.81

# --- command ---
## Contact geometry: longest COM-to-contact distance while touching the line.
## Feet: l_max (straight legs). Butt/chest/back: l_pose + arm/hip reach.
var contact_max: float = 0.98
var strength: float = 1.0           # 1 = legs, ~0.6 = arms/hips pushing off the line
var target: float = 0.96            # commanded leg length (m)
var active_target: float = 0.96     # after activation dynamics
var min_len: float = 0.55           # active bottom-out length (l_pose in tricks)

## --- Sticky bounce grip (hands closed around the line) -----------------
## While gripping, the coupling is two-way: the arms can PULL the body toward
## the line (negative force) up to the grip strength, the body cannot leave
## the line (no takeoff) and the hands stay at the contact point. Beyond full
## arm reach the straight arms act as a stiff stop. Energy still only enters
## through actuator work F * dl/dt.
var grip: bool = false
var grip_reach: float = 0.42        # m, COM above the line with straight arms (sitting)
var grip_pull_max: float = 1500.0   # N, two-hand grip + arm pull (~2 BW, assumption)
var k_grip_stop: float = 40000.0    # N/m, straight arms
var c_grip_stop: float = 1500.0

# --- state ---
var s: float = 0.0                  # contact position along the chord
var y_c: float = 0.0                # COM height (world)
var v_c: float = 0.0                # COM vertical velocity
var force: float = 0.0              # current leg force (N, push)
var lateral_force: float = 0.0      # passed through to the line (balance)
var takeoff: bool = false
var peak_force: float = 0.0
var work: float = 0.0               # actuator work this contact (J)


func com_mass() -> float:
	return body_mass - foot_mass


## Pulling uses the arms: a share of the push strength.
func strength_pull() -> float:
	return 1.0


## Starts a contact phase with the COM at `leg_length` above the line.
func begin_contact(solver: SlacklineSolver, at_s: float, leg_length: float, com_v: float) -> void:
	s = at_s
	y_c = solver.world_at(s).y + leg_length
	v_c = com_v
	takeoff = false
	peak_force = 0.0
	work = 0.0
	min_len = minf(l_min, leg_length)
	active_target = leg_length


func leg_length(solver: SlacklineSolver) -> float:
	return y_c - solver.world_at(s).y


func leg_speed(solver: SlacklineSolver) -> float:
	return v_c - solver.world_velocity_at(s).y


## Before each solver substep: compute the leg force and load the line.
func pre_substep(solver: SlacklineSolver, dt: float) -> void:
	var l := leg_length(solver)
	var ldot := leg_speed(solver)
	# Bottom-out length ratchets back up after a trick position.
	if min_len < l_min and min_len > l_pose + 1e-3:
		min_len = minf(l_min, maxf(min_len, l))
	active_target += (target - active_target) * minf(1.0, dt / activation_tau)
	# Muscles always damp; below ~600 N*s/m the explicit foot coupling rings.
	var f := k_leg * (active_target - l) - maxf(c_leg, 600.0) * ldot
	var fm := f_max * strength * (1.0 + clampf(rebound_boost, 0.0, 1.0) * rebound_boost_gain)
	var cap := fm * eccentric_ratio
	if ldot > 0.0:
		cap = fm * maxf(0.0, 1.0 - ldot / v_max)
	if grip:
		# arms pull toward the line as hard as the grip allows
		f = clampf(f, -grip_pull_max * strength_pull(), cap)
	else:
		f = clampf(f, 0.0, cap)
	# Arm swing: accelerating the arms upward pushes the body (and so the
	# feet) down harder - the reaction m_arms * a_arms adds to the push.
	if assist_force != 0.0 and l < contact_max:
		f = maxf(0.0, f + assist_force)
	# Lockout: a straight leg (or straight arms) cannot push further.
	if not grip or f > 0.0:
		f *= clampf((contact_max - l) / lockout_band, 0.0, 1.0)
	if l < min_len:
		f += k_stop * (min_len - l) + c_stop * maxf(0.0, -ldot)
	if grip:
		var reach := l_pose + grip_reach
		if l > reach:
			f -= k_grip_stop * (l - reach) + c_grip_stop * maxf(0.0, ldot)
		f = maxf(f, -grip_pull_max)
	elif l > contact_max + 1e-3:
		f = 0.0
	force = f
	peak_force = maxf(peak_force, f)
	solver.set_point_load(s, foot_mass, -f, lateral_force, body_mass)


## After each solver substep: integrate the COM and detect takeoff.
func post_substep(solver: SlacklineSolver, dt: float) -> void:
	var ldot := leg_speed(solver)
	work += force * ldot * dt
	v_c += (force / com_mass() - gravity) * dt
	y_c += v_c * dt
	var l := leg_length(solver)
	# Takeoff: out of reach of the line and still moving away from it.
	# (Falling INTO a lower contact, e.g. dropping to a butt bounce, is not a takeoff.)
	if l > contact_max + 0.005 and leg_speed(solver) > 0.05 and not grip:
		takeoff = true


## Whole-body vertical velocity (momentum-weighted) at takeoff.
func body_velocity(solver: SlacklineSolver) -> float:
	var vf := solver.world_velocity_at(s).y
	return (com_mass() * v_c + foot_mass * vf) / body_mass


## Landing: the feet (and their momentum) join the line, the COM keeps its speed.
func land(solver: SlacklineSolver, at_s: float, leg_len: float, body_v: float, lat_v: float) -> void:
	solver.impart_velocity(at_s, foot_mass, body_v, lat_v)
	begin_contact(solver, at_s, leg_len, body_v)
