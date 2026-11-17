class_name LabPanel
extends CanvasLayer
## HUD (always on) + Physics Laboratory panel (toggle with F1 / Tab).
## The lab edits a live SlacklineParams copy and the athlete/balance tunables.

signal preset_requested(path: String)
signal reset_requested

const PRESETS := {
	"Trickline 15m": "res://resources/presets/trickline.tres",
	"Trickline 30m": "res://resources/presets/trickline_30m.tres",
	"Trickline 40m": "res://resources/presets/trickline_40m.tres",
	"Standard": "res://resources/presets/standard.tres",
}

var line: Slackline
var athlete: Athlete

var _hud: Label
var _trick_label: Label
var _rhythm: Label
var demo_enabled_fn: Callable
var demo_mode_fn: Callable
var _balance_bar: ProgressBar
var _energy_bar: ProgressBar
var _panel: PanelContainer
var _sliders: VBoxContainer
var _line_length_options: OptionButton
var _rebuild_pending: bool = false


func _ready() -> void:
	layer = 10
	_build_hud()
	_build_panel()
	_panel.visible = false


func bind(l: Slackline, a: Athlete) -> void:
	line = l
	athlete = a
	if _line_length_options != null:
		var preset_lengths := [15.0, 30.0, 40.0]
		for i in preset_lengths.size():
			if is_equal_approx(line.params.length, preset_lengths[i]):
				_line_length_options.select(i)
				break
	_populate_sliders()


func toggle() -> void:
	_panel.visible = not _panel.visible


func _process(_delta: float) -> void:
	if line == null or athlete == null:
		return
	var sv := line.solver
	var contact_sag := -sv.offset_at(athlete.s).x
	_hud.text = ("SLACKLINE  MVP 0.1   [%s]\n" % line.params.preset_name
		+ "State: %s   Jumps: %d  Landings: %d\n" % [athlete.state_name(), athlete.jumps, athlete.landings]
		+ "Tension: %.2f kN   Sag @ feet: %.2f m   Max sag: %.2f m\n" % [sv.tension / 1000.0, contact_sag, sv.max_sag()]
		+ "Line vel: %+.2f m/s   Lean: %+.1f deg   COM height: %.2f m   Knees: %d%%   Last jump: %.2f m\n" % [athlete.foot_velocity.y, rad_to_deg(athlete.balance.theta), athlete.visual.com_global().y - athlete.global_position.y, int(athlete.balance.crouch * 100.0), athlete.last_jump_height]
		+ "Balance: side %+.1f deg (felt %+.1f)  spin %+.2f rad/s | fwd/back %+.1f deg | legs out L %.0f%% R %.0f%% | pose %s\n" % [rad_to_deg(athlete.balance.theta), rad_to_deg(athlete.balance.theta_seen), athlete.balance.omega, rad_to_deg(athlete.balance.phi), athlete.balance.leg_lift_l * 100.0, athlete.balance.leg_lift_r * 100.0, athlete.pose if athlete.pose != "" else "feet"]
		+ "Air: flip %+.0f deg  spin %+.1f rad/s  tuck %d%%  grab %s | velocity %.1f m/s\n" % [rad_to_deg(athlete.tricks.pitch), athlete.tricks.omega_pitch, int(athlete.tricks.tuck * 100.0), athlete.tricks.grab if athlete.tricks.grab != "" else "-", athlete.linear_velocity.length() if athlete.state == 1 else athlete.foot_velocity.length()]
		+ "Solver: %.2f ms   FPS: %d\n" % [line.last_step_ms, Engine.get_frames_per_second()]
		+ "SCORE: %d   Tricks landed: %d   Best combo: %d%s\n" % [athlete.tricks.score, athlete.tricks.tricks_landed, athlete.tricks.best_combo, (("   [DEMO: %s]" % (demo_mode_fn.call() if demo_mode_fn.is_valid() else "")) if demo_enabled_fn.is_valid() and demo_enabled_fn.call() else "")]
		+ "W/S walk  A/D hips  Q/E left/right arm  SHIFT bend knees  SPACE pump/jump  R reset  1/2/3/4 line presets  [ ] camera  G COM  V body  F1 lab  F one leg\n"
		+ "SET on the line: J back K front L 360 H 180 U back360 I front360 Y back180 | AIR: SPACE tuck, W lean fwd, grabs B knees N knee O leg P cross F tuck   LINE: Z butt  X chest  C back bounce   T demo  M slow-mo  F3 REBOUND LAB  F4 MOCAP%s" % ("  [SLOW-MO]" if Engine.time_scale < 0.9 else ""))
	var tr := athlete.tricks
	if tr.message_time > 0.0:
		_trick_label.text = tr.message
		_trick_label.modulate.a = clampf(tr.message_time / 0.5, 0.0, 1.0)
	elif athlete.state == Athlete.State.AIRBORNE and tr.queued_pose != "":
		_trick_label.text = "Landing: " + TrickController.LINE_TRICKS[tr.queued_pose]["name"]
		_trick_label.modulate.a = 0.85
	elif athlete.pose != "":
		_trick_label.text = TrickController.LINE_TRICKS[athlete.pose]["name"] + "..."
		_trick_label.modulate.a = 1.0
	elif athlete.state == Athlete.State.AIRBORNE and tr.is_rotating():
		# Live rotation readout: you decide when to open out of the tuck.
		_trick_label.text = "%.2f flips  %.1f twists  %s" % [absf(tr.pitch) / TAU,
			absf(tr.yaw) / TAU, "TUCK" if tr.tuck > 0.5 else "open"]
		_trick_label.modulate.a = 1.0
	elif (tr.queued != "" or tr.queued_twist != "") and athlete.state == Athlete.State.ON_LINE:
		var parts := []
		for q in [tr.queued, tr.queued_twist]:
			if q != "":
				parts.append(tr.TRICKS[q]["name"])
		_trick_label.text = "Set: " + " + ".join(parts)
		_trick_label.modulate.a = 0.7
	else:
		_trick_label.text = ""
	_balance_bar.value = clampf(athlete.balance.theta / athlete.balance.fall_angle, -1.0, 1.0)
	_energy_bar.value = athlete.rebound_meter.charge
	# Rhythm cue: squat while the line is high, push while it is low.
	var dev := athlete.bounce_dev()
	if athlete.state != Athlete.State.ON_LINE or absf(dev) < 0.03:
		_rhythm.text = "Rhythm:  -"
	elif dev > 0.0:
		_rhythm.text = "Rhythm:  LINE HIGH -> hold SPACE (squat / load)"
	else:
		_rhythm.text = "Rhythm:  LINE LOW  -> release SPACE (push / drive)"
	if _rebuild_pending:
		_rebuild_pending = false
		line.build()
		athlete.reset_to_line(line.chord_length() * 0.5)


func _build_hud() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	add_child(box)
	_hud = Label.new()
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	box.add_child(_hud)
	var lbl := Label.new()
	lbl.text = "Balance  L ◀            ▶ R"
	box.add_child(lbl)
	_balance_bar = ProgressBar.new()
	_balance_bar.min_value = -1.0
	_balance_bar.max_value = 1.0
	_balance_bar.value = 0.0
	_balance_bar.show_percentage = false
	_balance_bar.custom_minimum_size = Vector2(260, 14)
	box.add_child(_balance_bar)
	var energy_label := Label.new()
	energy_label.text = "SUPER REBOUND ENERGY"
	energy_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	box.add_child(energy_label)
	_energy_bar = ProgressBar.new()
	_energy_bar.min_value = 0.0
	_energy_bar.max_value = 1.0
	_energy_bar.value = 0.0
	_energy_bar.show_percentage = false
	_energy_bar.custom_minimum_size = Vector2(260, 12)
	box.add_child(_energy_bar)
	_rhythm = Label.new()
	_rhythm.add_theme_color_override("font_color", Color(0.6, 1.0, 1.0))
	box.add_child(_rhythm)
	_trick_label = Label.new()
	_trick_label.anchor_left = 0.0
	_trick_label.anchor_right = 1.0
	_trick_label.anchor_top = 0.3
	_trick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trick_label.add_theme_font_size_override("font_size", 40)
	_trick_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_trick_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_trick_label.add_theme_constant_override("outline_size", 8)
	add_child(_trick_label)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -360
	_panel.offset_right = -12
	_panel.offset_top = 12
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 660)
	_panel.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)
	var title := Label.new()
	title.text = "PHYSICS LAB"
	root.add_child(title)
	var row := HBoxContainer.new()
	root.add_child(row)
	_line_length_options = OptionButton.new()
	_line_length_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset_name in ["Trickline 15m", "Trickline 30m", "Trickline 40m"]:
		_line_length_options.add_item(preset_name)
		_line_length_options.set_item_metadata(_line_length_options.item_count - 1, PRESETS[preset_name])
	_line_length_options.item_selected.connect(func(index: int):
		preset_requested.emit(str(_line_length_options.get_item_metadata(index))))
	row.add_child(_line_length_options)
	var standard_button := Button.new()
	standard_button.text = "Standard 18m"
	standard_button.pressed.connect(func(): preset_requested.emit(PRESETS["Standard"]))
	row.add_child(standard_button)
	var rb := Button.new()
	rb.text = "Reset athlete"
	rb.pressed.connect(func(): reset_requested.emit())
	root.add_child(rb)
	_sliders = VBoxContainer.new()
	root.add_child(_sliders)


func _populate_sliders() -> void:
	for c in _sliders.get_children():
		c.queue_free()
	var p := line.params
	# --- line material (live) ---
	_slider("Pretension (kN)", 0.3, 10.0, 0.05, p.pretension / 1000.0,
		func(v):
			p.pretension = v * 1000.0
			line.refresh_material())
	_slider("Stiffness EA (kN)", 10.0, 500.0, 1.0, p.stiffness_ea / 1000.0,
		func(v):
			p.stiffness_ea = v * 1000.0
			line.refresh_material())
	_slider("Line mass (g/m)", 10.0, 300.0, 1.0, p.mass_per_meter * 1000.0,
		func(v):
			p.mass_per_meter = v / 1000.0
			line.refresh_material())
	_slider("Damping (mass)", 0.0, 3.0, 0.01, p.damping_mass,
		func(v): p.damping_mass = v)
	_slider("Damping (stiffness)", 0.0, 0.05, 0.0005, p.damping_stiffness,
		func(v): p.damping_stiffness = v)
	_slider("Substeps", 1.0, 16.0, 1.0, p.substeps,
		func(v): p.substeps = int(v))
	# --- geometry (rebuild) ---
	_slider("Length (m) *", 6.0, 40.0, 0.5, p.length,
		func(v):
			p.length = v
			_rebuild_pending = true)
	_slider("Anchor height (m) *", 0.8, 3.0, 0.05, p.anchor_height,
		func(v):
			p.anchor_height = v
			_rebuild_pending = true)
	_slider("Segments *", 12.0, 120.0, 1.0, p.segments,
		func(v):
			p.segments = int(v)
			_rebuild_pending = true)
	# --- athlete ---
	var b := athlete.balance
	_slider("Athlete mass (kg)", 40.0, 120.0, 1.0, athlete.athlete_mass,
		func(v):
			athlete.athlete_mass = v
			athlete.mass = v)
	_slider("Balance assist", 0.0, 1.0, 0.01, b.assist, func(v): b.assist = v)
	_slider("Balance authority", 2.0, 20.0, 0.5, b.max_input_accel, func(v): b.max_input_accel = v)
	_slider("Walk wobble", 0.0, 5.0, 0.05, athlete.walk_disturbance,
		func(v): athlete.walk_disturbance = v)
	var lg := athlete.leg
	_slider("Leg stiffness (kN/m)", 10.0, 80.0, 1.0, lg.k_leg / 1000.0, func(v): lg.k_leg = v * 1000.0)
	_slider("Max leg force (x BW)", 1.0, 4.0, 0.05, lg.f_max / (athlete.athlete_mass * 9.81),
		func(v): lg.f_max = v * athlete.athlete_mass * 9.81)
	_slider("Max extension speed (m/s)", 1.0, 5.0, 0.1, lg.v_max, func(v): lg.v_max = v)
	_slider("Squat speed (m/s)", 0.5, 5.0, 0.1, athlete.dip_speed, func(v): athlete.dip_speed = v)
	_slider("Time scale", 0.1, 1.0, 0.05, Engine.time_scale, func(v): Engine.time_scale = v)
	var note := Label.new()
	note.text = "* rebuilds the line and resets the athlete"
	_sliders.add_child(note)


func _slider(label: String, lo: float, hi: float, step: float, value: float, on_change: Callable) -> void:
	var lbl := Label.new()
	var fmt := "%s: %.0f" if step >= 1.0 else ("%s: %.2f" if step >= 0.01 else "%s: %.4f")
	lbl.text = fmt % [label, value]
	_sliders.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(300, 18)
	sl.value_changed.connect(func(v: float):
		on_change.call(v)
		lbl.text = fmt % [label, v])
	_sliders.add_child(sl)
