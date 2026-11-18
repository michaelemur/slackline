class_name LabPanel
extends CanvasLayer
## HUD (always on) + Physics Laboratory panel (toggle with F1 / Tab).
## The lab edits a live SlacklineParams copy and the athlete/balance tunables.

signal preset_requested(path: String)
signal reset_requested
signal restart_requested

const PRESETS := {
	"Trickline 15m": "res://resources/presets/trickline.tres",
	"Trickline 30m": "res://resources/presets/trickline_30m.tres",
	"Trickline 40m": "res://resources/presets/trickline_40m.tres",
	"Standard": "res://resources/presets/standard.tres",
}

var line: Slackline
var athlete: Athlete

var _hud: Label
var _hud_box: VBoxContainer
var _trick_label: Label
var _rhythm: Label
var _diagnostics: Label
var demo_enabled_fn: Callable
var demo_mode_fn: Callable
var _balance_bar: ProgressBar
var _energy_bar: ProgressBar
var _panel: PanelContainer
var _sliders: VBoxContainer
var _line_length_options: OptionButton
var _pause_button: Button
var _help_button: Button
var _help_panel: PanelContainer
var _pause_overlay: ColorRect
var _pause_resume: Button
var _scroll: ScrollContainer
var _rebuild_pending: bool = false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_build_panel()
	_build_pause_overlay()
	_panel.visible = false
	get_viewport().size_changed.connect(_refresh_safe_layout)
	_refresh_safe_layout()


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


func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	_pause_overlay.visible = get_tree().paused
	if get_tree().paused:
		_pause_resume.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if line == null or athlete == null:
		return
	var sv := line.solver
	var contact_sag := -sv.offset_at(athlete.s).x
	var demo_tag := "   DEMO: %s" % (demo_mode_fn.call() if demo_mode_fn.is_valid() else "") if demo_enabled_fn.is_valid() and demo_enabled_fn.call() else ""
	_hud.text = "SLACKLINE  [%s]%s\nSCORE  %d\nBEST COMBO  x%d" % [line.params.preset_name, demo_tag,
		athlete.tricks.score, athlete.tricks.best_combo]
	if _panel.visible:
		_diagnostics.text = ("State: %s   Jumps: %d   Landings: %d\n" % [athlete.state_name(), athlete.jumps, athlete.landings]
			+ "Tension: %.2f kN   Sag @ feet: %.2f m   Max sag: %.2f m\n" % [sv.tension / 1000.0, contact_sag, sv.max_sag()]
			+ "Line vel: %+.2f m/s   Lean: %+.1f deg   COM height: %.2f m   Knees: %d%%   Last jump: %.2f m\n" % [athlete.foot_velocity.y, rad_to_deg(athlete.balance.theta), athlete.visual.com_global().y - athlete.global_position.y, int(athlete.balance.crouch * 100.0), athlete.last_jump_height]
			+ "Balance: side %+.1f deg (felt %+.1f)  spin %+.2f rad/s | fwd/back %+.1f deg | legs out L %.0f%% R %.0f%% | pose %s\n" % [rad_to_deg(athlete.balance.theta), rad_to_deg(athlete.balance.theta_seen), athlete.balance.omega, rad_to_deg(athlete.balance.phi), athlete.balance.leg_lift_l * 100.0, athlete.balance.leg_lift_r * 100.0, athlete.pose if athlete.pose != "" else "feet"]
			+ "Air: flip %+.0f deg  spin %+.1f rad/s  tuck %d%%  grab %s | velocity %.1f m/s\n" % [rad_to_deg(athlete.tricks.pitch), athlete.tricks.omega_pitch, int(athlete.tricks.tuck * 100.0), athlete.tricks.grab if athlete.tricks.grab != "" else "-", athlete.linear_velocity.length() if athlete.state == 1 else athlete.foot_velocity.length()]
			+ "Solver: %.2f ms   FPS: %d%s" % [line.last_step_ms, Engine.get_frames_per_second(), "   SLOW-MO" if Engine.time_scale < 0.9 else ""])
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
	_hud_box = VBoxContainer.new()
	add_child(_hud_box)
	_hud = Label.new()
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	_hud.add_theme_font_size_override("font_size", 22)
	_hud_box.add_child(_hud)
	var lbl := Label.new()
	lbl.text = "Balance  L ◀            ▶ R"
	_hud_box.add_child(lbl)
	_balance_bar = ProgressBar.new()
	_balance_bar.min_value = -1.0
	_balance_bar.max_value = 1.0
	_balance_bar.value = 0.0
	_balance_bar.show_percentage = false
	_balance_bar.custom_minimum_size = Vector2(220, 12)
	_hud_box.add_child(_balance_bar)
	var energy_label := Label.new()
	energy_label.text = "SUPER REBOUND ENERGY"
	energy_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	_hud_box.add_child(energy_label)
	_energy_bar = ProgressBar.new()
	_energy_bar.min_value = 0.0
	_energy_bar.max_value = 1.0
	_energy_bar.value = 0.0
	_energy_bar.show_percentage = false
	_energy_bar.custom_minimum_size = Vector2(220, 10)
	_hud_box.add_child(_energy_bar)
	_rhythm = Label.new()
	_rhythm.add_theme_color_override("font_color", Color(0.6, 1.0, 1.0))
	_hud_box.add_child(_rhythm)
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
	_pause_button = Button.new()
	_pause_button.text = "||"
	_pause_button.tooltip_text = "Pause"
	_pause_button.custom_minimum_size = Vector2(44, 44)
	_pause_button.pressed.connect(toggle_pause)
	add_child(_pause_button)
	_help_button = Button.new()
	_help_button.text = "?"
	_help_button.tooltip_text = "Controls"
	_help_button.custom_minimum_size = Vector2(44, 44)
	_help_button.visible = not DisplayServer.is_touchscreen_available()
	_help_button.pressed.connect(func(): _help_panel.visible = not _help_panel.visible)
	add_child(_help_button)
	_help_panel = PanelContainer.new()
	_help_panel.custom_minimum_size = Vector2(300, 172)
	_help_panel.visible = false
	add_child(_help_panel)
	var help_text := Label.new()
	help_text.text = ("CONTROLS\n"
		+ "RIGHT HAND  hold SPACE = load the line, release = jump\n"
		+ "   in the air: hold = tuck (spin faster), release = open/straight\n"
		+ "   aim the takeoff while loading: UP/J backflip, DOWN/K frontflip,\n"
		+ "   LEFT/RIGHT (H/L) twist.  F = grab (tucked or straight)\n"
		+ "LEFT HAND  A/D balance, W/S walk (in the air: small attitude fix)\n"
		+ "Z/X/C butt / chest / back   1/3/4 line   N music on/off   R reset   ESC pause")
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_panel.add_child(help_text)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -360
	_panel.offset_right = -12
	_panel.offset_top = 12
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(340, 660)
	_panel.add_child(_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(root)
	var title := Label.new()
	title.text = "PHYSICS LAB"
	root.add_child(title)
	_diagnostics = Label.new()
	_diagnostics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_diagnostics)
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


func _build_pause_overlay() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0.0, 0.015, 0.035, 0.78)
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.visible = false
	add_child(_pause_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 240)
	center.add_child(card)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	card.add_child(layout)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	layout.add_child(title)
	_pause_resume = Button.new()
	_pause_resume.text = "Resume"
	_pause_resume.pressed.connect(toggle_pause)
	layout.add_child(_pause_resume)
	var restart := Button.new()
	restart.text = "Restart line"
	restart.pressed.connect(func(): restart_requested.emit())
	layout.add_child(restart)
	var help := Button.new()
	help.text = "Controls"
	help.pressed.connect(func():
		_pause_overlay.visible = false
		get_tree().paused = false
		_help_panel.visible = true)
	layout.add_child(help)


static func safe_rect_for_viewport(viewport_size: Vector2, screen_size: Vector2i,
		screen_safe_area: Rect2i) -> Rect2:
	if screen_size.x <= 0 or screen_size.y <= 0 or screen_safe_area.size.x <= 0 or screen_safe_area.size.y <= 0:
		return Rect2(Vector2.ZERO, viewport_size)
	var scale := Vector2(viewport_size.x / float(screen_size.x), viewport_size.y / float(screen_size.y))
	return Rect2(Vector2(screen_safe_area.position) * scale, Vector2(screen_safe_area.size) * scale)


func _refresh_safe_layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var safe := safe_rect_for_viewport(size, DisplayServer.screen_get_size(), DisplayServer.get_display_safe_area())
	var margin := Vector2(12.0, 12.0)
	_hud_box.position = safe.position + Vector2(16.0, 12.0)
	_pause_button.position = Vector2(safe.end.x - _pause_button.custom_minimum_size.x - margin.x, safe.position.y + margin.y)
	_help_button.position = Vector2(safe.end.x - _help_button.custom_minimum_size.x - margin.x,
		safe.position.y + margin.y + _pause_button.custom_minimum_size.y + 6.0)
	_help_panel.position = Vector2(maxf(safe.position.x + 12.0, safe.end.x - _help_panel.custom_minimum_size.x - 12.0),
		safe.position.y + 64.0)
	var right_inset := size.x - safe.end.x
	var panel_width := minf(360.0, maxf(240.0, safe.size.x - 24.0))
	_panel.offset_right = -(right_inset + 12.0)
	_panel.offset_left = _panel.offset_right - panel_width
	_panel.offset_top = safe.position.y + 12.0
	_scroll.custom_minimum_size = Vector2(panel_width - 20.0, minf(660.0, maxf(240.0, safe.size.y - 24.0)))


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
