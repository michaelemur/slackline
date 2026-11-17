extends Node3D
## Motion-capture viewer (F4 in the game): plays the captured backflip on our
## athlete with an AnimationPlayer, next to the source video, at the same time
## base. Esc / F4 returns to the game.

const MODEL := "res://assets/mocap/athlete_backflip_mocap.glb"
const MOTION := "res://assets/mocap/backflip_motion.json"
const VIDEO := "res://assets/mocap/backflip_reference.ogv"

var player: AnimationPlayer
var video: VideoStreamPlayer
var label: Label
var motion: MotionReference
var speed := 1.0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.32, 0.34)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var model: Node3D = load(MODEL).instantiate()
	add_child(model)
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	var anim_name: String = player.get_animation_list()[0]
	player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	player.play(anim_name)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(4.2, 1.4, 0.0), Vector3(0, 1.3, 0))
	cam.fov = 45
	motion = MotionReference.load_json(MOTION)
	var ui := CanvasLayer.new()
	add_child(ui)
	video = VideoStreamPlayer.new()
	video.stream = load(VIDEO)
	video.position = Vector2(20, 20)
	video.size = Vector2(384, 216)
	video.expand = true
	video.loop = true
	ui.add_child(video)
	video.play()
	label = Label.new()
	label.position = Vector2(20, 250)
	label.add_theme_font_size_override("font_size", 15)
	ui.add_child(label)


func _process(_dt: float) -> void:
	var f := int(player.current_animation_position * motion.fps)
	var phase := "ground"
	if f >= motion.takeoff and f <= motion.landing:
		phase = "FLIGHT"
	label.text = ("MOTION CAPTURE VIEWER  (source: reference video, top left)\n"
		+ "Trick: %s  turns: %d  rotation: %.0f deg  flight: %.2f s\n" % [motion.name, motion.turns, rad_to_deg(motion.total_rotation), motion.flight_time]
		+ "Tuck peaks at %d%% of the flight, opens at %d%%  peak spin %.1f rad/s\n" % [int(motion.tuck_at_u * 100), int(motion.open_at_u * 100), motion.peak_omega]
		+ "frame %d / %d   phase: %s\n" % [f, motion.frames, phase]
		+ "SPACE pause   S slow-mo   Esc/F4 back to the game")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_ESCAPE, KEY_F4:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		KEY_SPACE:
			var paused := player.speed_scale == 0.0
			player.speed_scale = speed if paused else 0.0
			video.paused = not paused
		KEY_S:
			speed = 0.3 if speed > 0.5 else 1.0
			player.speed_scale = speed
			video.speed_scale = speed
