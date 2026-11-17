extends SceneTree
## COM check: the yellow ball must sit at the segment-mass COM, close to the
## body, and in the air on the flight's rotation centre (ballistic point).
var main; var a; var t := 0.0
var mx_body := 0.0; var mx_pivot := 0.0; var tuck_shift := 0.0; var open_pos := Vector3.ZERO
var n_air := 0
var where := ""
func _initialize():
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
func _physics_process(d) -> bool:
	t += d
	if a == null:
		a = main.get_node("Athlete"); main.demo.mode = "rikuto"; main.demo.set_enabled(true)
		return false
	var v: AthleteVisual = a.visual
	var ball: Vector3 = v._com_marker.global_position
	var com: Vector3 = v.com_global()
	var sk: Skeleton3D = v.character.skel
	var pel := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("spine_01")).origin
	if ball.distance_to(pel) > mx_body:
		mx_body = ball.distance_to(pel); where = "state %d pose %s air %.2f tuck %.2f" % [a.state, a.pose, a.air_time, a.tricks.tuck]
	if a.state == 1 and a.air_time > 0.25:
		n_air += 1
		var pivot: Vector3 = v._trick.global_position
		mx_pivot = maxf(mx_pivot, com.distance_to(pivot))
		# where the COM sits relative to the chest, tucked vs open
		var chest := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("spine_03")).origin
		var rel := (com - chest).length()
		if a.tricks.tuck > 0.9: tuck_shift = maxf(tuck_shift, rel)
		elif a.tricks.tuck < 0.1: open_pos.x = maxf(open_pos.x, rel)
	if t > 20.0 and false:
		pass
	if t > 20.0:
		print("COM: ball-to-pelvis max %.2f m | air frames %d, COM-to-rotation-centre max %.3f m | COM-to-chest tucked %.2f m vs open %.2f m" % [mx_body, n_air, mx_pivot, tuck_shift, open_pos.x])
		print("  worst ball-to-pelvis at: ", where)
		return true
	return false
