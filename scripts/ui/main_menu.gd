extends Node3D
## Main menu: title, PLAY, SETTINGS, and the athlete choice with both
## athletes standing on the beach. Settings: line height (1-10 m), Line
## Explosiveness, line length, music. Big touch targets for the phone.

const BeachScript := preload("res://scripts/world/beach_environment.gd")
const GAME_SCENE := "res://scenes/main.tscn"
const CHAR := {
	"male": {"name": "KAI", "scene": "res://assets/athlete/athlete.glb", "x": 0.75},
	"female": {"name": "MAYA", "scene": "res://assets/athlete_female/athlete_female.glb", "x": -0.75},
}
const EXPLO_TEXT := {
	"soft": "Soft - gentle, realistic rebound",
	"balanced": "Balanced - lively arcade bounce",
	"explosive": "Explosive - deep load, powerful kick",
	"extreme": "Extreme - huge, exaggerated launches",
}

var _visuals := {}
var _rings := {}
var _cam: Camera3D
var _t := 0.0
var _ui: CanvasLayer
var _name_label: Label
var _settings: PanelContainer
var _height_label: Label
var _height_slider: HSlider
var _explo_buttons := {}
var _explo_label: Label
var _length_buttons := {}
var _music_button: Button


func _ready() -> void:
	InputSetup.ensure_actions()
	var beach := BeachScript.new()
	beach.set("line_length", 15.0)
	add_child(beach)
	for id in CHAR:
		_add_athlete(id)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.make_current()
	_build_ui()
	_select(GameSettings.character)
	var audio := AudioDirector.new()
	audio.name = "MenuAudio"
	audio.music_enabled = GameSettings.music_on
	add_child(audio)


func _add_athlete(id: String) -> void:
	AthleteCharacter.selected_scene = CHAR[id]["scene"]
	var v := AthleteVisual.new()
	v.name = "Preview_" + id
	v.position = Vector3(CHAR[id]["x"], 0.0, 0.0)
	v.rotation.y = (0.3 if id == "male" else -0.3)   # face the camera, turned a little to each other
	add_child(v)
	_visuals[id] = v
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.40
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.75, 0.25)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.15)
	m.emission_energy_multiplier = 1.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.position = Vector3(CHAR[id]["x"], 0.02, 0.0)
	add_child(ring)
	_rings[id] = ring
	AthleteCharacter.selected_scene = AthleteCharacter.SCENE_PATH


func _process(delta: float) -> void:
	_t += delta
	# gentle camera drift, looking at the pair
	var a := 0.12 * sin(_t * 0.25)
	_cam.position = Vector3(0.6 + 3.6 * sin(a), 1.35, -3.9 * cos(a))
	_cam.look_at(Vector3(0.35, 1.0, 0.0), Vector3.UP)
	for id in _visuals:
		var v: AthleteVisual = _visuals[id]
		var sel: bool = id == GameSettings.character
		var sway := 0.04 * sin(_t * 1.3 + (0.0 if id == "male" else 1.7))
		v.set_body(sway, 0.05 if sel else 0.0, 0.85 + (0.3 * sin(_t * 1.1) if sel else 0.0), 0.85, 0.0, 1.0)
		v.set_trick_rotation(0.0, 0.0)
		v.set_line_pose("", 0.0, 0.0, 1.0)
		v.apply_body({"state": 0, "pose": "", "pose_b": 0.0, "gait": 0.0, "walk": 0.0,
			"lift_l": 0.0, "lift_r": 0.0, "arm_flex": 0.3 * sway, "phi": 0.0}, delta)
		v.finish_frame(delta)
		_rings[id].visible = sel
		_rings[id].rotation.y += delta * 0.8


# ------------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var title := Label.new()
	title.text = "SLACKLINE"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	title.add_theme_color_override("font_outline_color", Color(0.85, 0.3, 0.1))
	title.add_theme_constant_override("outline_size", 14)
	title.position = Vector2(48, 28)
	root.add_child(title)
	var sub := Label.new()
	sub.text = "TRICKLINE  ·  BEACH SESSION"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	sub.position = Vector2(54, 122)
	root.add_child(sub)
	# right column: PLAY + SETTINGS
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	col.position = Vector2(-330, -120)
	col.custom_minimum_size = Vector2(280, 0)
	col.add_theme_constant_override("separation", 16)
	root.add_child(col)
	var play := _big_button("PLAY", Color(0.95, 0.42, 0.12))
	play.name = "PlayButton"
	play.pressed.connect(start_game)
	col.add_child(play)
	var settings := _big_button("SETTINGS", Color(0.1, 0.45, 0.55))
	settings.pressed.connect(func(): _settings.visible = not _settings.visible)
	col.add_child(settings)
	_settings_summary(col)
	# bottom: athlete choice
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position = Vector2(-260, -110)
	bar.custom_minimum_size = Vector2(520, 80)
	bar.add_theme_constant_override("separation", 20)
	root.add_child(bar)
	for id in ["male", "female"]:
		var b := _big_button(CHAR[id]["name"], Color(0.15, 0.15, 0.2))
		b.name = "Pick_" + id
		b.custom_minimum_size = Vector2(240, 76)
		b.pressed.connect(_select.bind(id))
		bar.add_child(b)
	_name_label = Label.new()
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_name_label.position = Vector2(-200, -150)
	_name_label.custom_minimum_size = Vector2(400, 30)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_name_label)
	_build_settings(root)


var _summary: Label


func _settings_summary(col: VBoxContainer) -> void:
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 18)
	_summary.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_summary.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_summary.add_theme_constant_override("outline_size", 6)
	col.add_child(_summary)


func _refresh_summary() -> void:
	_summary.text = "Line %.1f m high · %s\n%s · music %s" % [GameSettings.line_height,
		GameSettings.EXPLOSIVENESS[GameSettings.explosiveness]["label"],
		GameSettings.line_length.replace("Trickline ", ""), "on" if GameSettings.music_on else "off"]


func _big_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 84)
	b.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.12 if state == "hover" else (-0.1 if state == "pressed" else 0.0)) if state != "pressed" else color.darkened(0.15)
		sb.set_corner_radius_all(18)
		sb.border_color = Color(1, 1, 1, 0.5 if state == "focus" else 0.25)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	return b


func _build_settings(root: Control) -> void:
	_settings = PanelContainer.new()
	_settings.name = "SettingsPanel"
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.position = Vector2(-330, -250)
	_settings.custom_minimum_size = Vector2(660, 500)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(26)
	_settings.add_theme_stylebox_override("panel", sb)
	_settings.visible = false
	root.add_child(_settings)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_settings.add_child(v)
	v.add_child(_heading("LINE HEIGHT"))
	_height_label = Label.new()
	_height_label.add_theme_font_size_override("font_size", 30)
	v.add_child(_height_label)
	_height_slider = HSlider.new()
	_height_slider.name = "HeightSlider"
	_height_slider.min_value = GameSettings.HEIGHT_MIN
	_height_slider.max_value = GameSettings.HEIGHT_MAX
	_height_slider.step = 0.1
	_height_slider.custom_minimum_size = Vector2(600, 48)
	_height_slider.value = GameSettings.line_height
	_height_slider.value_changed.connect(func(x):
		GameSettings.line_height = x
		_refresh())
	v.add_child(_height_slider)
	v.add_child(_heading("LINE EXPLOSIVENESS"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for id in GameSettings.ORDER:
		var b := Button.new()
		b.text = GameSettings.EXPLOSIVENESS[id]["label"]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(145, 60)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func():
			GameSettings.explosiveness = id
			_refresh())
		row.add_child(b)
		_explo_buttons[id] = b
	_explo_label = Label.new()
	_explo_label.add_theme_font_size_override("font_size", 18)
	v.add_child(_explo_label)
	v.add_child(_heading("LINE LENGTH"))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	v.add_child(row2)
	for id in GameSettings.LENGTHS:
		var b := Button.new()
		b.text = id.replace("Trickline ", "")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 56)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func():
			GameSettings.line_length = id
			_refresh())
		row2.add_child(b)
		_length_buttons[id] = b
	_music_button = Button.new()
	_music_button.custom_minimum_size = Vector2(200, 56)
	_music_button.add_theme_font_size_override("font_size", 22)
	_music_button.pressed.connect(func():
		GameSettings.music_on = not GameSettings.music_on
		var a := get_node_or_null("MenuAudio")
		if a: a.music_enabled = GameSettings.music_on
		_refresh())
	v.add_child(_music_button)
	var done := _big_button("DONE", Color(0.95, 0.42, 0.12))
	done.custom_minimum_size = Vector2(200, 64)
	done.pressed.connect(func():
		_settings.visible = false
		GameSettings.save_settings())
	v.add_child(done)
	_refresh()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	return l


func _refresh() -> void:
	_height_label.text = "%.1f m" % GameSettings.line_height
	for id in _explo_buttons:
		_explo_buttons[id].button_pressed = id == GameSettings.explosiveness
	_explo_label.text = EXPLO_TEXT[GameSettings.explosiveness]
	for id in _length_buttons:
		_length_buttons[id].button_pressed = id == GameSettings.line_length
	_music_button.text = "Music: " + ("ON" if GameSettings.music_on else "OFF")
	_refresh_summary()


func _select(id: String) -> void:
	if not CHAR.has(id):
		id = "male"
	GameSettings.character = id
	_name_label.text = "Athlete: %s" % CHAR[id]["name"]
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))


func start_game() -> void:
	GameSettings.from_menu = true
	GameSettings.save_settings()
	AthleteCharacter.selected_scene = CHAR[GameSettings.character]["scene"]
	get_tree().change_scene_to_file(GAME_SCENE)
