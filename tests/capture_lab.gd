extends SceneTree
## Renders the Rebound Lab (needs a display / xvfb-run).
var lab; var t := 0.0; var out := "user://"; var n := 0
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	lab = load("res://scenes/rebound_lab.tscn").instantiate()
	root.add_child(lab)
func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png")); print("saved ", name)
func _process(d):
	t += d
	if n == 0 and t > 0.3: lab.time_scale = 1.0; n = 1
	# Grab a frame while lines are deep in the bounce.
	if n == 1 and t > 6.5: _shot("lab_live"); n = 2
	if n == 2: lab.run_instant(); n = 3
	if n == 3 and t > 7.5: _shot("lab_table"); n = 4
	return n >= 4
