extends Node3D
## REBOUND LABORATORY
## Five trickline lengths (15/18/20/25/30 m) run the SAME experiment side by
## side under identical initial conditions, using the game's own solver and
## LegModel. Live 3D view + a comparison table of measured outputs.
## F3 / Esc: back to the game.

const LENGTHS := [15.0, 18.0, 20.0, 25.0, 30.0]
const SPACING := 3.2

var protocol: String = "rhythm"
var time_scale: float = 1.0
var cfg := {
	"pretension": 3000.0, "stiffness_ea": 90000.0, "damping_stiffness": 0.003,
	"mass": 75.0, "f_max_bw": 3.5, "k_leg": 30000.0, "drop_height": 0.10,
	"dip_depth": 0.60, "launch_offset": 0.0, "pump_cycles": 10, "duration": 16.0,
}

var experiments: Array[ReboundExperiment] = []
var _renderers: Array[SlacklineRenderer] = []
var _bodies: Array[Node3D] = []
var _legs: Array[MeshInstance3D] = []
var _tags: Array[Label3D] = []
var _results: Array = []
var _table: RichTextLabel
var _status: Label
var _proto_buttons := {}
var _anchor_root: Node3D


func _ready() -> void:
	InputSetup.ensure_actions()
	_build_world()
	_build_ui()
	restart()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3 or event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		elif event.keycode == KEY_R:
			restart()


# ------------------------------------------------------------- experiments

func _make(L: float, z: float) -> ReboundExperiment:
	var e := ReboundExperiment.new()
	var p := (load("res://resources/presets/trickline.tres") as SlacklineParams).duplicate()
	p.pretension = cfg["pretension"]
	p.stiffness_ea = cfg["stiffness_ea"]
	p.damping_stiffness = cfg["damping_stiffness"]
	e.params = p
	e.length = L
	e.origin = Vector3(-L * 0.5, 0.0, z)
	e.protocol = protocol
	e.duration = cfg["duration"]
	e.drop_height = cfg["drop_height"]
	e.dip_depth = cfg["dip_depth"]
	e.launch_offset = cfg["launch_offset"]
	e.pump_cycles = int(cfg["pump_cycles"])
	e.leg.body_mass = cfg["mass"]
	e.leg.k_leg = cfg["k_leg"]
	e.leg.f_max = cfg["f_max_bw"] * cfg["mass"] * 9.81
	return e


## Restart all five lines from identical initial conditions.
func restart() -> void:
	experiments.clear()
	_results.clear()
	for i in range(LENGTHS.size()):
		var e := _make(LENGTHS[i], -i * SPACING)
		e.setup()
		experiments.append(e)
		_results.append(null)
		_renderers[i].solver = e.solver
		_renderers[i].params = e.params
		_renderers[i].rebuild_material()
	_rebuild_anchors()
	_update_table()


## Runs every length to completion instantly (no rendering) and fills the table.
func run_instant() -> void:
	var t0 := Time.get_ticks_msec()
	for i in range(LENGTHS.size()):
		var e := _make(LENGTHS[i], -i * SPACING)
		_results[i] = e.run()
	restart_keep_results()
	_status.text = "Instant run: %d experiments in %d ms (identical initial conditions)" % [
		LENGTHS.size(), Time.get_ticks_msec() - t0]


func restart_keep_results() -> void:
	var saved := _results.duplicate()
	restart()
	_results = saved
	_update_table()


func _physics_process(delta: float) -> void:
	var steps := int(round(delta * time_scale / ReboundExperiment.DT))
	for i in range(experiments.size()):
		var e := experiments[i]
		for k in range(steps):
			e.step()
		if e.done() and _results[i] == null:
			_results[i] = e.finish()
			_update_table()


func _process(_delta: float) -> void:
	for i in range(experiments.size()):
		var e := experiments[i]
		var foot := e.foot_point()
		var com_y := e.com_y()
		var feet_y := com_y - e.leg.l_max if e.airborne else foot.y
		var com := Vector3(foot.x, com_y, foot.z)
		_bodies[i].global_position = com
		var leg_len := maxf(0.05, com_y - feet_y)
		_legs[i].global_position = Vector3(foot.x, feet_y + leg_len * 0.5, foot.z)
		_legs[i].scale = Vector3(1, leg_len, 1)
		_tags[i].global_position = Vector3(foot.x, e.origin.y + e.params.anchor_height + 1.4, foot.z)
		_tags[i].text = "%d m   t %.1fs   T %.2f kN   %s   jumps %d" % [
			LENGTHS[i], e.t, e.solver.tension / 1000.0,
			"AIR" if e.airborne else "contact", e.m.get("takeoffs", 0)]
	if experiments.size() > 0:
		_status.text = "Protocol: %s   t = %.1f / %.0f s   (R restart, F3 back to game)" % [
			protocol, experiments[0].t, cfg["duration"]]


# ------------------------------------------------------------- world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.34, 0.5, 0.3)
	ground.material_override = gm
	ground.position = Vector3(0, 0, -6)
	add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.position = Vector3(-3.0, 3.4, 9.5)
	add_child(cam)
	cam.look_at(Vector3(-1.0, 2.0, -6.4))
	cam.make_current()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.95, 0.3, 0.2)
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.15, 0.17, 0.22)
	for i in range(LENGTHS.size()):
		var r := SlacklineRenderer.new()
		add_child(r)
		_renderers.append(r)
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.18
		cap.height = 0.8
		body.mesh = cap
		body.material_override = body_mat
		add_child(body)
		_bodies.append(body)
		var leg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 1.0
		leg.mesh = cyl
		leg.material_override = leg_mat
		add_child(leg)
		_legs.append(leg)
		var tag := Label3D.new()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 40
		tag.pixel_size = 0.004
		tag.outline_size = 8
		add_child(tag)
		_tags.append(tag)


func _rebuild_anchors() -> void:
	if _anchor_root:
		_anchor_root.queue_free()
	_anchor_root = Node3D.new()
	add_child(_anchor_root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.25, 0.16)
	for e in experiments:
		for x in [e.origin.x, e.origin.x + e.length]:
			var post := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.12
			c.bottom_radius = 0.15
			c.height = e.params.anchor_height + 0.3
			post.mesh = c
			post.material_override = mat
			post.position = Vector3(x, c.height * 0.5, e.origin.z)
			_anchor_root.add_child(post)


# ------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.modulate = Color(1, 1, 1, 0.92)
	layer.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	panel.add_child(root)
	panel.theme = Theme.new()
	panel.theme.default_font_size = 13
	var title := Label.new()
	title.text = "REBOUND LAB\n15 / 18 / 20 / 25 / 30 m, identical conditions"
	root.add_child(title)
	_status = Label.new()
	root.add_child(_status)
	var row := GridContainer.new()
	row.columns = 3
	root.add_child(row)
	for p in ReboundExperiment.PROTOCOLS:
		var b := Button.new()
		b.text = p
		b.toggle_mode = true
		b.button_pressed = p == protocol
		b.tooltip_text = ReboundExperiment.PROTOCOLS[p]
		b.pressed.connect(func(): _select_protocol(p))
		row.add_child(b)
		_proto_buttons[p] = b
	var row2 := GridContainer.new()
	row2.columns = 2
	root.add_child(row2)
	var rb := Button.new()
	rb.text = "Restart (R)"
	rb.pressed.connect(restart)
	row2.add_child(rb)
	var ib := Button.new()
	ib.text = "Run all instantly"
	ib.pressed.connect(run_instant)
	row2.add_child(ib)
	var cb := Button.new()
	cb.text = "Copy CSV"
	cb.pressed.connect(func(): DisplayServer.clipboard_set(results_csv()))
	row2.add_child(cb)
	var back := Button.new()
	back.text = "Game (F3)"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	row2.add_child(back)
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	_slider(grid, "Pretension kN", 1.0, 10.0, 0.1, cfg["pretension"] / 1000.0, func(v): cfg["pretension"] = v * 1000.0)
	_slider(grid, "Stiffness EA kN", 30.0, 300.0, 5.0, cfg["stiffness_ea"] / 1000.0, func(v): cfg["stiffness_ea"] = v * 1000.0)
	_slider(grid, "Line damping", 0.0, 0.02, 0.0005, cfg["damping_stiffness"], func(v): cfg["damping_stiffness"] = v)
	_slider(grid, "Athlete kg", 40.0, 110.0, 1.0, cfg["mass"], func(v): cfg["mass"] = v)
	_slider(grid, "Leg force xBW", 1.5, 5.0, 0.1, cfg["f_max_bw"], func(v): cfg["f_max_bw"] = v)
	_slider(grid, "Leg stiff kN/m", 10.0, 60.0, 1.0, cfg["k_leg"] / 1000.0, func(v): cfg["k_leg"] = v * 1000.0)
	_slider(grid, "Drop height m", 0.0, 0.6, 0.01, cfg["drop_height"], func(v): cfg["drop_height"] = v)
	_slider(grid, "Launch offset m", -0.4, 0.8, 0.05, cfg["launch_offset"], func(v): cfg["launch_offset"] = v)
	_slider(grid, "Pump cycles", 2.0, 16.0, 1.0, cfg["pump_cycles"], func(v): cfg["pump_cycles"] = int(v))
	_slider(grid, "Duration s", 4.0, 30.0, 1.0, cfg["duration"], func(v): cfg["duration"] = v)
	_slider(grid, "Speed x", 0.1, 4.0, 0.1, time_scale, func(v): time_scale = v)
	var tpanel := PanelContainer.new()
	tpanel.anchor_top = 1.0
	tpanel.anchor_bottom = 1.0
	tpanel.anchor_right = 1.0
	tpanel.offset_top = -168
	tpanel.offset_left = 8
	tpanel.offset_right = -8
	tpanel.offset_bottom = -8
	tpanel.modulate = Color(1, 1, 1, 0.92)
	layer.add_child(tpanel)
	_table = RichTextLabel.new()
	_table.bbcode_enabled = true
	_table.scroll_active = false
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "DejaVu Sans Mono", "Consolas", "monospace"])
	_table.add_theme_font_override("mono_font", mono)
	_table.add_theme_font_override("normal_font", mono)
	_table.add_theme_font_size_override("mono_font_size", 12)
	_table.add_theme_font_size_override("normal_font_size", 12)
	tpanel.add_child(_table)


func _slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float,
		on_change: Callable) -> void:
	var l := Label.new()
	l.text = "%s %s" % [label, _fmt(value, step)]
	parent.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(120, 14)
	sl.value_changed.connect(func(v: float):
		on_change.call(v)
		l.text = "%s %s" % [label, _fmt(v, step)])
	parent.add_child(sl)


func _fmt(v: float, step: float) -> String:
	return ("%.0f" % v) if step >= 1.0 else (("%.2f" % v) if step >= 0.01 else ("%.4f" % v))


func _select_protocol(p: String) -> void:
	protocol = p
	for k in _proto_buttons:
		_proto_buttons[k].button_pressed = k == p
	restart()


const COLUMNS := [
	["Line m", "length", "%.0f"], ["Sag m", "static_sag", "%.2f"],
	["Depth m", "max_depth", "%.2f"], ["PeakT kN", "peak_tension", "kN"],
	["Leg BW", "peak_leg_force_bw", "%.2f"], ["Freq Hz", "freq_hz", "%.2f"],
	["Loss%/cyc", "energy_loss_pct", "%.1f"], ["Rebnd m/s", "rebound_v", "%.2f"],
	["T-off m/s", "takeoff_v", "%.2f"], ["Jump m", "jump_height", "%.2f"],
	["Air s", "airtime", "%.2f"], ["Takeoffs", "takeoffs", "%d"],
	["Land BW", "landing_peak_force_bw", "%.2f"], ["Rotations", "-", "-"],
]


func _cell(r, col: Array) -> String:
	if r == null:
		return "..."
	if col[1] == "-":
		return "n/a"
	var v = r.get(col[1], NAN)
	if v is float and is_nan(v):
		return "-"
	if col[2] == "kN":
		return "%.2f" % (v / 1000.0)
	if col[2] == "%d":
		return "%d" % int(v)
	return col[2] % v


func _update_table() -> void:
	if _table == null:
		return
	var txt := "[b]Results - %s[/b]  (%s)\n" % [protocol, ReboundExperiment.PROTOCOLS[protocol]]
	var header := ""
	for c in COLUMNS:
		header += "%-11s" % c[0]
	txt += "[code]" + header + "\n"
	for i in range(LENGTHS.size()):
		var row := ""
		for c in COLUMNS:
			row += "%-11s" % (_cell(_results[i], c) if c[1] != "length" else "%d" % LENGTHS[i])
		txt += row + "\n"
	txt += "[/code]Rotations / angular velocity: not simulated yet (phase 4: aerial L = I*w)."
	_table.text = txt


func results_csv() -> String:
	var out := ""
	for c in COLUMNS:
		out += c[0] + ","
	out += "\n"
	for i in range(LENGTHS.size()):
		for c in COLUMNS:
			out += (_cell(_results[i], c) if c[1] != "length" else "%d" % LENGTHS[i]) + ","
		out += "\n"
	return out
