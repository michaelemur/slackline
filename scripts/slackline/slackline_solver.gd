class_name SlacklineSolver
extends RefCounted
## Lightweight custom slackline solver (pure simulation, no rendering).
##
## Model: "taut string" with stretch-dependent tension.
##  * The line is a chain of N+1 nodes between two fixed anchors.
##  * Each node moves transversely: vertical offset `y` (world up) and lateral
##    offset `z` (horizontal, perpendicular to the anchor chord).
##  * Axial waves in webbing travel at ~1 km/s, so tension is treated as
##    uniform along the line and recomputed every substep from total stretch:
##        T = EA * (L_current - L_rest) / L_rest   (clamped >= 0, i.e. slack)
##    This gives the real non-linear stiffening of a slackline under load.
##  * Transverse dynamics per node: m * a = T/h * (y[i-1] - 2y[i] + y[i+1]) + F - m*g
##    integrated with the theta-method (tridiagonal, Thomas algorithm, O(N)).
##    theta = 0.5 (trapezoidal rule) conserves the energy of the linear system,
##    so the line stores and returns elastic energy without numerical loss;
##    theta = 1 is implicit Euler (very stable, but ~10 %/cycle artificial
##    damping on a trickline bounce). Unconditionally stable for theta >= 0.5.
##  * Damping: Rayleigh (mass-proportional + stiffness-proportional).
##
## Athlete coupling: the athlete's mass and leg/balance forces are distributed
## onto the two nodes around the contact point every step (see set_point_load).

var gravity: float = 9.81
var theta: float = 0.52     # 0.5 = energy-conserving; slightly above damps solver noise

var params: SlacklineParams
var anchor_a: Vector3
var anchor_b: Vector3
var axis: Vector3 = Vector3.RIGHT      # unit vector A -> B
var lateral: Vector3 = Vector3.BACK    # unit, horizontal, perpendicular to axis
var chord_length: float = 0.0
var segment_count: int = 0
var h: float = 0.0                      # chord length per segment
var node_mass: float = 0.0
var rest_length: float = 0.0
var tension: float = 0.0
var current_length: float = 0.0
var ground_height: float = 0.0
var ground_clearance: float = 0.02

var y := PackedFloat64Array()
var z := PackedFloat64Array()
var vy := PackedFloat64Array()
var vz := PackedFloat64Array()
var extra_mass := PackedFloat64Array()      # lumped mass, vertical axis
var extra_mass_z := PackedFloat64Array()    # lumped mass, lateral axis
var fy := PackedFloat64Array()
var fz := PackedFloat64Array()

var _cp := PackedFloat64Array()
var _dp := PackedFloat64Array()


func setup(p: SlacklineParams, a: Vector3, b: Vector3) -> void:
	params = p
	anchor_a = a
	anchor_b = b
	chord_length = a.distance_to(b)
	axis = (b - a).normalized()
	var lat := axis.cross(Vector3.UP)
	lateral = lat.normalized() if lat.length() > 1e-4 else Vector3.BACK
	segment_count = maxi(4, p.segments)
	h = chord_length / segment_count
	var n := segment_count + 1
	for arr_name in ["y", "z", "vy", "vz", "extra_mass", "extra_mass_z", "fy", "fz", "_cp", "_dp"]:
		var arr := PackedFloat64Array()
		arr.resize(n)
		arr.fill(0.0)
		set(arr_name, arr)
	refresh_material()
	tension = p.pretension
	current_length = chord_length


func refresh_material() -> void:
	## Call after changing pretension / EA / mass at runtime (like re-ratcheting).
	node_mass = params.mass_per_meter * h
	rest_length = chord_length / (1.0 + params.pretension / params.stiffness_ea)


func node_count() -> int:
	return segment_count + 1


# ---------------------------------------------------------------- loads

func clear_loads() -> void:
	extra_mass.fill(0.0)
	extra_mass_z.fill(0.0)
	fy.fill(0.0)
	fz.fill(0.0)


## Lumps `mass` (kg) and external forces (N, world-vertical / lateral) at
## distance `s` (m along the chord from anchor A), split linearly between the
## two neighbouring nodes. Gravity on the lumped mass is applied by the solver.
## `lateral_mass` (if >= 0) lumps a different mass for the sideways axis: a
## standing athlete's feet ride the line vertically through an actuated leg,
## but the whole body's inertia resists sideways line motion.
func set_point_load(s: float, mass: float, force_y: float, force_z: float,
		lateral_mass: float = -1.0) -> void:
	var u := clampf(s / h, 0.0, float(segment_count) - 1e-6)
	var k := int(floor(u))
	var f := u - k
	var mz := mass if lateral_mass < 0.0 else lateral_mass
	extra_mass[k] += (1.0 - f) * mass
	extra_mass[k + 1] += f * mass
	extra_mass_z[k] += (1.0 - f) * mz
	extra_mass_z[k + 1] += f * mz
	fy[k] += (1.0 - f) * force_y
	fy[k + 1] += f * force_y
	fz[k] += (1.0 - f) * force_z
	fz[k + 1] += f * force_z


## Sets the line velocity around `s` (used when an athlete lands with momentum).
## Momentum-conserving blend between incoming body and the two contact nodes.
func impart_velocity(s: float, body_mass: float, vel_y: float, vel_z: float) -> void:
	var u := clampf(s / h, 0.0, float(segment_count) - 1e-6)
	var k := int(floor(u))
	var f := u - k
	for contact in [[k, 1.0 - f], [k + 1, f]]:
		var i: int = contact[0]
		if i <= 0 or i >= segment_count:
			continue
		var incoming_mass := body_mass * float(contact[1])
		if incoming_mass <= 0.0:
			continue
		var m := node_mass
		vy[i] = (incoming_mass * vel_y + m * vy[i]) / (incoming_mass + m)
		vz[i] = (incoming_mass * vel_z + m * vz[i]) / (incoming_mass + m)


# ---------------------------------------------------------------- stepping

func compute_tension() -> float:
	var total := 0.0
	var ay := axis.y
	for i in range(segment_count):
		var dy := y[i + 1] - y[i]
		var dz := z[i + 1] - z[i]
		total += sqrt(maxf(1e-12, h * h + dy * dy + dz * dz + 2.0 * h * dy * ay))
	current_length = total
	tension = maxf(0.0, params.stiffness_ea * (total - rest_length) / rest_length)
	return tension


var _ck: float = 0.0


func step(dt: float) -> void:
	compute_tension()
	var kk := tension / h
	var th := theta
	var r := maxf(0.0, (tension - params.pretension) / maxf(params.pretension, 1.0) - params.hysteresis_start)
	_ck = params.damping_stiffness * (1.0 + params.hysteresis_gain * r * r)
	var cdt := th * th * dt * dt + th * dt * _ck
	var old_vy := vy
	var old_vz := vz
	vy = _solve_axis(y, vy, fy, extra_mass, dt, kk, cdt, -gravity)
	vz = _solve_axis(z, vz, fz, extra_mass_z, dt, kk, cdt, 0.0)
	var base_y0 := anchor_a.y
	for i in range(1, segment_count):
		y[i] += dt * ((1.0 - th) * old_vy[i] + th * vy[i])
		z[i] += dt * ((1.0 - th) * old_vz[i] + th * vz[i])
		# Ground contact for the line itself (very low anchors / huge sag).
		var world_y := base_y0 + axis.y * h * i + y[i]
		var floor_y := ground_height + ground_clearance
		if world_y < floor_y:
			y[i] += floor_y - world_y
			if vy[i] < 0.0:
				vy[i] = 0.0


func _solve_axis(pos: PackedFloat64Array, vel: PackedFloat64Array, force: PackedFloat64Array,
		lumped: PackedFloat64Array, dt: float, kk: float, cdt: float, g: float) -> PackedFloat64Array:
	# Theta-method on velocity (C = cm*M + ck*K, K = kk*tridiag(-1,2,-1)):
	#   (M(1 + th dt cm) + (th^2 dt^2 + th dt ck) K) v_new
	#     = M v (1 - (1-th) dt cm) + dt (F + M g)
	#       - K (dt x + th(1-th) dt^2 v + (1-th) dt ck v)
	# Anchor nodes have v = 0.
	var out := vel.duplicate()
	var n := segment_count
	var off := -kk * cdt
	var cm := params.damping_mass
	var th := theta
	var ck := _ck
	var vx_coef := th * (1.0 - th) * dt * dt + (1.0 - th) * dt * ck
	var prev_c := 0.0
	var prev_d := 0.0
	for i in range(1, n):
		var m := node_mass + lumped[i]
		var diag := m * (1.0 + th * dt * cm) + 2.0 * kk * cdt
		var lap := dt * (pos[i - 1] - 2.0 * pos[i] + pos[i + 1]) \
			+ vx_coef * (vel[i - 1] - 2.0 * vel[i] + vel[i + 1])
		var rhs := m * vel[i] * (1.0 - (1.0 - th) * dt * cm) + kk * lap + dt * (force[i] + m * g)
		if i == 1:
			_cp[i] = off / diag
			_dp[i] = rhs / diag
		else:
			var denom := diag - off * prev_c
			_cp[i] = off / denom
			_dp[i] = (rhs - off * prev_d) / denom
		prev_c = _cp[i]
		prev_d = _dp[i]
	out[n - 1] = _dp[n - 1]
	for i in range(n - 2, 0, -1):
		out[i] = _dp[i] - _cp[i] * out[i + 1]
	out[0] = 0.0
	out[n] = 0.0
	return out


# ---------------------------------------------------------------- queries

func base_point(s: float) -> Vector3:
	return anchor_a + axis * s


func node_world(i: int) -> Vector3:
	return anchor_a + axis * (h * i) + Vector3.UP * y[i] + lateral * z[i]


## Interpolated transverse offset at s: Vector2(vertical, lateral).
func offset_at(s: float) -> Vector2:
	var u := clampf(s / h, 0.0, float(segment_count) - 1e-6)
	var k := int(floor(u))
	var f := u - k
	return Vector2(lerpf(y[k], y[k + 1], f), lerpf(z[k], z[k + 1], f))


func velocity_offset_at(s: float) -> Vector2:
	var u := clampf(s / h, 0.0, float(segment_count) - 1e-6)
	var k := int(floor(u))
	var f := u - k
	return Vector2(lerpf(vy[k], vy[k + 1], f), lerpf(vz[k], vz[k + 1], f))


func world_at(s: float) -> Vector3:
	var o := offset_at(s)
	return base_point(s) + Vector3.UP * o.x + lateral * o.y


func world_velocity_at(s: float) -> Vector3:
	var v := velocity_offset_at(s)
	return Vector3.UP * v.x + lateral * v.y


## Projects a world point onto the chord: returns distance along the chord.
func project_s(world_pos: Vector3) -> float:
	return (world_pos - anchor_a).dot(axis)


func max_sag() -> float:
	var m := 0.0
	for i in range(node_count()):
		m = maxf(m, -y[i])
	return m


func kinetic_energy() -> float:
	var e := 0.0
	for i in range(1, segment_count):
		var m := node_mass + extra_mass[i]
		e += 0.5 * m * (vy[i] * vy[i] + vz[i] * vz[i])
	return e


func is_finite_state() -> bool:
	for i in range(node_count()):
		if is_nan(y[i]) or is_nan(z[i]) or is_inf(y[i]) or is_inf(z[i]):
			return false
	return true
