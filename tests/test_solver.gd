extends TestCase
## Physics validation for SlacklineSolver against closed-form statics.

const TRICK := "res://resources/presets/trickline.tres"
const STANDARD := "res://resources/presets/standard.tres"


func _make(path: String, heavy_damping: bool = false) -> SlacklineSolver:
	var p := (load(path) as SlacklineParams).duplicate()
	if heavy_damping:
		p.damping_mass = 4.0
	var s := SlacklineSolver.new()
	s.setup(p, Vector3(0, p.anchor_height, 0), Vector3(p.length, p.anchor_height, 0))
	return s


func _run(s: SlacklineSolver, seconds: float, load_s: float = -1.0, mass: float = 0.0,
		dt: float = 1.0 / 240.0) -> void:
	for i in range(int(seconds / dt)):
		s.clear_loads()
		if load_s >= 0.0:
			s.set_point_load(load_s, mass, 0.0, 0.0)
		s.step(dt)


## Analytic centre sag for a point load W on a stretchy line (line mass ignored).
## Matches the solver's transverse force (tan-slope) form: W = 2 T d / a.
func _analytic_center_sag(p: SlacklineParams, w: float) -> float:
	var a := p.length * 0.5
	var l0 := p.rest_length()
	var lo := 1e-5
	var hi := a
	for i in range(200):
		var d := (lo + hi) * 0.5
		var t := p.stiffness_ea * (2.0 * sqrt(a * a + d * d) - l0) / l0
		if 2.0 * t * d / a > w:
			hi = d
		else:
			lo = d
	return (lo + hi) * 0.5


func test_unloaded_tension_matches_pretension() -> void:
	var s := _make(TRICK, true)
	_run(s, 6.0)
	near(s.tension, s.params.pretension, 0.03, "unloaded tension")
	# Self-weight sag of a taut string: mu g L^2 / (8 T)
	var expected := s.params.mass_per_meter * 9.81 * pow(s.params.length, 2) / (8.0 * s.tension)
	near(s.max_sag(), expected, 0.08, "self-weight sag")


func test_center_point_load_matches_statics_trickline() -> void:
	var s := _make(TRICK, true)
	var w := 75.0 * 9.81 + s.params.mass_per_meter * s.params.length * 9.81 * 0.5
	_run(s, 10.0, s.chord_length * 0.5, 75.0)
	var expected := _analytic_center_sag(s.params, w)
	near(-s.offset_at(s.chord_length * 0.5).x, expected, 0.03, "trickline centre sag")


func test_center_point_load_matches_statics_standard() -> void:
	var s := _make(STANDARD, true)
	var w := 75.0 * 9.81 + s.params.mass_per_meter * s.params.length * 9.81 * 0.5
	_run(s, 12.0, s.chord_length * 0.5, 75.0)
	var expected := _analytic_center_sag(s.params, w)
	near(-s.offset_at(s.chord_length * 0.5).x, expected, 0.03, "standard centre sag")


func test_symmetry_under_center_load() -> void:
	var s := _make(TRICK, true)
	_run(s, 6.0, s.chord_length * 0.5, 75.0)
	var n := s.segment_count
	var worst := 0.0
	for i in range(n / 2):
		worst = maxf(worst, absf(s.y[i] - s.y[n - i]))
	check(worst < 0.002, "symmetric deflection, worst diff %.5f" % worst)


func test_bounce_frequency_matches_linearised_model() -> void:
	# Small vertical oscillation of the athlete about equilibrium.
	var s := _make(TRICK, true)
	var mid := s.chord_length * 0.5
	_run(s, 10.0, mid, 75.0)
	s.params.damping_mass = 0.0
	s.params.damping_stiffness = 0.0
	var y0 := s.offset_at(mid).x
	# Numerical stiffness from statics: k = dW/dd
	var p := s.params
	var d0 := _analytic_center_sag(p, 700.0)
	var d1 := _analytic_center_sag(p, 760.0)
	var k := 60.0 / (d1 - d0)
	var expected_period := TAU * sqrt(75.0 / k)
	# Kick and measure zero crossings.
	s.impart_velocity(mid, 75.0, 0.3, 0.0)
	var dt := 1.0 / 240.0
	var t := 0.0
	var crossings: Array[float] = []
	var prev := 0.0
	while t < 6.0 and crossings.size() < 5:
		s.clear_loads()
		s.set_point_load(mid, 75.0, 0.0, 0.0)
		s.step(dt)
		t += dt
		var cur := s.offset_at(mid).x - y0
		if prev < 0.0 and cur >= 0.0:
			crossings.append(t)
		prev = cur
	check(crossings.size() >= 3, "found oscillation crossings")
	if crossings.size() >= 3:
		var period := (crossings[crossings.size() - 1] - crossings[0]) / (crossings.size() - 1)
		near(period, expected_period, 0.12, "bounce period")


func test_damping_dissipates_energy() -> void:
	var s := _make(TRICK)
	var mid := s.chord_length * 0.5
	_run(s, 0.05, mid, 75.0)
	s.impart_velocity(mid, 75.0, -1.5, 0.5)
	_run(s, 0.1, mid, 75.0)
	var e0 := s.kinetic_energy()
	_run(s, 12.0, mid, 75.0)
	var e1 := s.kinetic_energy()
	check(e1 < e0 * 0.5, "energy decays: %.2f -> %.2f J" % [e0, e1])


func _transferred_momentum(s: SlacklineSolver, contact_s: float, body_mass: float,
		lateral_axis: bool = false) -> float:
	var total := 0.0
	var velocities := s.vz if lateral_axis else s.vy
	var u := clampf(contact_s / s.h, 0.0, float(s.segment_count) - 1e-6)
	var k := int(floor(u))
	var f := u - k
	for i in range(1, s.segment_count):
		var contact_mass := 0.0
		if i == k:
			contact_mass = body_mass * (1.0 - f)
		elif i == k + 1:
			contact_mass = body_mass * f
		total += (s.node_mass + contact_mass) * velocities[i]
	return total


func test_landing_momentum_at_node() -> void:
	var s := _make(TRICK)
	var contact_node := 5
	var body_mass := 75.0
	var launch_speed := 2.4
	s.impart_velocity(contact_node * s.h, body_mass, launch_speed, 0.0)
	var expected := body_mass * launch_speed / (body_mass + s.node_mass)
	near(s.vy[contact_node], expected, 1e-9, "full incoming mass at node contact")
	check(is_zero_approx(s.vy[contact_node - 1]) and is_zero_approx(s.vy[contact_node + 1]),
		"node contact does not impart velocity to other nodes")
	check(absf(_transferred_momentum(s, contact_node * s.h, body_mass) - body_mass * launch_speed) < 1e-8,
		"node contact conserves vertical momentum")


func test_landing_momentum_halfway_between_nodes() -> void:
	var s := _make(TRICK)
	var k := 5
	var body_mass := 75.0
	var vy_in := 2.4
	var vz_in := -0.8
	s.impart_velocity((k + 0.5) * s.h, body_mass, vy_in, vz_in)
	var half_mass := body_mass * 0.5
	var expected := half_mass * vy_in / (half_mass + s.node_mass)
	near(s.vy[k], expected, 1e-9, "half body mass on left node")
	near(s.vy[k + 1], expected, 1e-9, "half body mass on right node")
	check(absf(_transferred_momentum(s, (k + 0.5) * s.h, body_mass) - body_mass * vy_in) < 1e-8,
		"halfway contact conserves vertical momentum")
	check(absf(_transferred_momentum(s, (k + 0.5) * s.h, body_mass, true) - body_mass * vz_in) < 1e-8,
		"halfway contact conserves lateral momentum")


func test_landing_momentum_uses_interpolation_weights() -> void:
	for fraction_value in [0.2, 0.7]:
		var fraction: float = fraction_value
		var s := _make(TRICK)
		var k := 5
		var body_mass := 75.0
		var incoming_speed := 1.7
		s.impart_velocity((k + fraction) * s.h, body_mass, incoming_speed, 0.0)
		var left_mass := body_mass * (1.0 - fraction)
		var right_mass := body_mass * fraction
		near(s.vy[k], left_mass * incoming_speed / (left_mass + s.node_mass), 1e-9,
			"left-node contribution at fraction %.1f" % fraction)
		near(s.vy[k + 1], right_mass * incoming_speed / (right_mass + s.node_mass), 1e-9,
			"right-node contribution at fraction %.1f" % fraction)
		check(absf(_transferred_momentum(s, (k + fraction) * s.h, body_mass)
			- body_mass * incoming_speed) < 1e-8,
			"contact at fraction %.1f conserves momentum" % fraction)


func test_stability_random_impulses() -> void:
	var s := _make(TRICK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var dt := 1.0 / 240.0
	var pos := s.chord_length * 0.3
	for i in range(240 * 20):
		pos = clampf(pos + rng.randf_range(-0.02, 0.02), 1.0, s.chord_length - 1.0)
		s.clear_loads()
		s.set_point_load(pos, 80.0, rng.randf_range(-1500, 300), rng.randf_range(-300, 300))
		s.step(dt)
	check(s.is_finite_state(), "state finite after 20 s of random loading")
	check(s.max_sag() < s.params.anchor_height + 0.01, "line stays above ground")


func test_tension_increases_with_load() -> void:
	var s := _make(TRICK, true)
	_run(s, 6.0, s.chord_length * 0.5, 75.0)
	check(s.tension > s.params.pretension * 1.05, "loaded tension %.0f N > pretension" % s.tension)
