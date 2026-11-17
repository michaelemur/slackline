extends SceneTree
var t := 0
func _initialize():
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.05,0.05,0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.45,0.45,0.5)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e; root.add_child(env)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-35, 30, 0); l.light_energy = 1.4; root.add_child(l)
	var ch = load("res://assets/athlete/athlete.glb").instantiate(); root.add_child(ch)
	var c := Camera3D.new(); root.add_child(c)
	var a := OS.get_cmdline_user_args()
	var mode := a[0] if a.size() > 0 else "full"
	if mode == "face":
		c.look_at_from_position(Vector3(0.15, 1.65, 0.55), Vector3(0, 1.63, 0))
	elif mode == "back":
		c.look_at_from_position(Vector3(-1.2, 1.1, -2.6), Vector3(0, 0.9, 0))
	elif mode == "feet":
		c.look_at_from_position(Vector3(0.5, 0.35, 0.8), Vector3(0, 0.08, 0))
	else:
		c.look_at_from_position(Vector3(1.2, 1.1, 2.6), Vector3(0, 0.9, 0))
	c.fov = 40
func _process(d) -> bool:
	t += 1
	if t == 5:
		root.get_viewport().get_texture().get_image().save_png("/tmp/prev_%s.png" % (OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() else "full"))
		quit()
	return false
