extends Node3D
## SimulationDirector + level bootstrap for MVP 0.1.
## Owns the deterministic physics order each tick:
##   athlete.pre_line_step -> slackline.simulate -> athlete.post_line_step
## Rendering (SlacklineRenderer, AthleteVisual, CameraRig, LabPanel) only
## reads state in _process.

@onready var line: Slackline = $Slackline
@onready var athlete: Athlete = $Athlete
@onready var camera_rig: CameraRig = $CameraRig
@onready var lab: LabPanel = $LabPanel
@onready var audio_director: AudioDirector = $AudioDirector

var _crash_mat: MeshInstance3D
var demo := DemoPilot.new()


func _ready() -> void:
	InputSetup.ensure_actions()
	_build_environment()
	athlete.attach(line)
	athlete.reset_to_line(line.chord_length() * 0.5)
	director.name = "CinematicDirector"
	add_child(director)
	director.bind(athlete, line)
	director.super_rebound.connect(func(_v): athlete.tricks.say("SUPER REBOUND!"))
	audio_director.bind(athlete, director)
	camera_rig.director = director
	camera_rig.line = line
	camera_rig.target = athlete
	camera_rig.set_forward(line.axis())
	camera_rig.snap()
	lab.bind(line, athlete)
	_add_touch_controls()
	line.rebuilt.connect(_on_line_rebuilt)
	demo.name = "DemoPilot"
	demo.athlete = athlete
	add_child(demo)
	lab.demo_enabled_fn = func(): return demo.enabled
	lab.demo_mode_fn = func(): return {"classic": "classic", "video": "video combo", "rikuto": "Angel/Manson"}.get(demo.mode, demo.mode)
	lab.preset_requested.connect(load_preset)
	lab.reset_requested.connect(func(): athlete.reset_to_line(line.chord_length() * 0.5))
	lab.restart_requested.connect(restart_game)


func _add_touch_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TouchControlsLayer"
	add_child(layer)
	var controls := TouchControlsScript.new()
	controls.name = "TouchControls"
	controls.athlete_input = athlete.input
	controls.visible = DisplayServer.is_touchscreen_available()
	layer.add_child(controls)


func _physics_process(delta: float) -> void:
	demo.step(delta)
	athlete.pre_line_step(delta)
	athlete.simulate_line(delta)
	athlete.post_line_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		get_tree().change_scene_to_file("res://scenes/rebound_lab.tscn")
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F4:
		get_tree().change_scene_to_file("res://scenes/mocap_viewer.tscn")
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		toggle_environment()
		return
	if event.is_action_pressed("reset"):
		athlete.reset_to_line(line.chord_length() * 0.5)
	elif event.is_action_pressed("toggle_character"):
		athlete.visual.set_use_character(not athlete.visual.use_character)
	elif event.is_action_pressed("toggle_com"):
		athlete.visual.show_com = not athlete.visual.show_com
	elif event.is_action_pressed("toggle_music"):
		audio_director.toggle_music()
	elif event.is_action_pressed("slow_motion"):
		Engine.time_scale = 0.35 if Engine.time_scale > 0.9 else 1.0
	elif event.is_action_pressed("demo_toggle"):
		demo.toggle()
	elif event.is_action_pressed("toggle_lab"):
		lab.toggle()
	elif event.is_action_pressed("preset_trickline"):
		load_preset(LabPanel.PRESETS["Trickline 15m"])
	elif event.is_action_pressed("preset_trickline_30m"):
		load_preset(LabPanel.PRESETS["Trickline 30m"])
	elif event.is_action_pressed("preset_trickline_40m"):
		load_preset(LabPanel.PRESETS["Trickline 40m"])
	elif event.is_action_pressed("preset_standard"):
		load_preset(LabPanel.PRESETS["Standard"])


func load_preset(path: String) -> void:
	line.apply_preset(load(path) as SlacklineParams)
	athlete.reset_to_line(line.chord_length() * 0.5)
	camera_rig.snap()
	lab.bind(line, athlete)


func restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_line_rebuilt() -> void:
	if beach != null:
		beach.call("configure_for_line_length", line.chord_length())
	if camera_rig != null:
		camera_rig.set_forward(line.axis())


# preloaded (not class_name) so a freshly copied project runs before the
# editor has rescanned its class list
const DirectorScript := preload("res://scripts/camera/cinematic_director.gd")
const BeachScript := preload("res://scripts/world/beach_environment.gd")
const TouchControlsScript := preload("res://scripts/ui/touch_controls.gd")
var director: Node = DirectorScript.new()
var beach: Node3D = null
var studio: Node3D = null


## Beach by default; F2 switches to the plain grey studio (for analysis).
func _build_environment() -> void:
	beach = BeachScript.new()
	beach.name = "Beach"
	beach.call("configure_for_line_length", line.chord_length())
	add_child(beach)
	# Floor collider for falls (shared by both looks). No mattress.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	ground.position = Vector3(10, 0, 0)
	add_child(ground)


func toggle_environment() -> void:
	if beach.get_parent() != null:
		remove_child(beach)
		if studio == null:
			studio = _build_studio()
			studio.name = "Studio"
		add_child(studio)
	else:
		if studio != null:
			remove_child(studio)
			studio.free()
			studio = null
		add_child(beach)


func _build_studio() -> Node3D:
	# Plain, high-contrast scene so the body reads clearly: black background,
	# grey floor with a grid.
	var root := Node3D.new()
	root.name = "Studio"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.55)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	mi.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _grid_texture()
	gm.uv1_scale = Vector3(80, 80, 1)   # 1 m grid squares
	gm.roughness = 1.0
	mi.material_override = gm
	mi.position = Vector3(10, 0, 0)
	root.add_child(mi)
	return root


func _grid_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color(0.22, 0.22, 0.22))
	for i in range(n):
		for w in range(2):
			img.set_pixel(i, w, Color(0.4, 0.4, 0.4))
			img.set_pixel(w, i, Color(0.4, 0.4, 0.4))
	return ImageTexture.create_from_image(img)
