extends SceneTree
## Frames of the mocap viewer (needs a display / xvfb-run).
var v; var n := 0; var out := "/tmp"
func _initialize():
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	v = load("res://scenes/mocap_viewer.tscn").instantiate()
	root.add_child(v)
func _process(d) -> bool:
	n += 1
	if v.player != null and n > 3:
		var t: float = [0.4, 0.75, 0.85, 0.95, 1.05, 1.15, 1.3, 1.6][mini((n - 4) / 1, 7)]
		v.player.seek(t, true)
		v._process(0.0)
	if n > 5 and n <= 13:
		root.get_viewport().get_texture().get_image().save_png(out.path_join("viewer_%d.png" % (n - 5)))
	return n > 14
