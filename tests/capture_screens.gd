extends SceneTree
## Renders gameplay screenshots (needs a display, e.g. xvfb-run).
## godot --path . --rendering-method gl_compatibility -s res://tests/capture_screens.gd -- <outdir>
var main; var a; var t := 0.0; var out := "user://"; var shots := {}
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)
func _process(d):
	t += d
	if a == null:
		a = main.get_node("Athlete")
		a.input.override_enabled = true
	a.input.override_pump = t > 2.5 and t < 5.6
	if t > 1.5 and not shots.has("1"): shots["1"] = true; _shot("01_standing")
	if t > 4.85 and not shots.has("2"): shots["2"] = true; _shot("02_bounce")
	if a.state == Athlete.State.AIRBORNE and not shots.has("3"): shots["3"] = true; _shot("03_airborne")
	if t > 8.0 and not shots.has("4"):
		shots["4"] = true
		main.get_node("LabPanel").toggle()
	if t > 8.3 and not shots.has("5"): shots["5"] = true; _shot("04_lab_panel")
	if t > 8.5 and not shots.has("6"):
		shots["6"] = true; main.get_node("LabPanel").toggle(); main.load_preset("res://resources/presets/standard.tres")
	if t > 10.0 and not shots.has("7"): shots["7"] = true; _shot("05_standard")
	return t > 10.2
