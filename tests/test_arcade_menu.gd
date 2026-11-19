extends Node
## Scenario tests for the Nov 18 brief: menu + settings, both athletes, line
## height up to 10 m, Line Explosiveness, bounded arcade energy.

signal finished(passes: int, failures: Array)

var passes := 0
var failures: Array = []
var _phase := 0
var _t := 0.0
var _main: Node3D
var _a: Athlete
var _rest := 0.0
var _best := 0.0
var _results := {}
var _runs := [["soft", 2.2, 10.0], ["explosive", 2.2, 12.0], ["extreme", 10.0, 22.0]]
var _run_i := -1
var _gs: Node


func _check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures.append("[arcade/menu] " + msg)


func _ready() -> void:
	_gs = get_node("/root/GameSettings")
	_test_menu()
	_test_characters()
	_next_run()


func _test_menu() -> void:
	var menu: Node3D = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	_check(menu.find_child("PlayButton", true, false) != null, "menu has a PLAY button")
	var slider: HSlider = menu.find_child("HeightSlider", true, false)
	_check(slider != null and is_equal_approx(slider.max_value, 10.0), "height slider goes up to 10 m")
	if slider:
		slider.value = 10.0
		_check(is_equal_approx(_gs.line_height, 10.0), "slider sets the line height (%.1f m)" % _gs.line_height)
		slider.value = 2.2
	menu._select("female")
	_check(_gs.character == "female", "athlete selection: female")
	menu._select("male")
	_check(_gs.character == "male", "athlete selection: male")
	for id in ["male", "female"]:
		var v: AthleteVisual = menu._visuals[id]
		_check(v.character != null and v.character.skel != null, "%s preview has a rigged model" % id)
	menu.free()


func _test_characters() -> void:
	var heights := {}
	for id in ["male", "female"]:
		AthleteCharacter.selected_scene = AthleteCharacter.SCENE_PATH if id == "male" else AthleteCharacter.FEMALE_SCENE_PATH
		var v := AthleteVisual.new()
		v._ready()
		var c := v.character
		_check(c != null and c.skel != null and c.skel.get_bone_count() == 53, "%s: 53-bone rig loads" % id)
		if c and c.skel:
			var head := c.skel.get_bone_global_rest(c.skel.find_bone("head")).origin
			heights[id] = head.y
		v.free()
	AthleteCharacter.selected_scene = AthleteCharacter.SCENE_PATH
	if heights.size() == 2:
		_check(heights["female"] < heights["male"] * 0.99, "female athlete has her own (shorter) proportions")


func _next_run() -> void:
	if _main:
		_main.queue_free()
		_main = null
	_run_i += 1
	if _run_i >= _runs.size():
		_finish()
		return
	var r: Array = _runs[_run_i]
	_gs.explosiveness = r[0]
	_gs.line_height = r[1]
	_gs.from_menu = true
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_a = _main.get_node("Athlete")
	_a.input.override_enabled = true
	_t = 0.0
	_best = 0.0
	var line: Slackline = _main.get_node("Slackline")
	_check(is_equal_approx(line.params.anchor_height, float(r[1])), "%s: line built at %.1f m" % [r[0], r[1]])


func _physics_process(dt: float) -> void:
	if _a == null or _run_i >= _runs.size():
		return
	_t += dt
	var i := _a.input
	i.override_balance = clampf(-_a.balance.theta_seen * 3.0 - _a.balance.omega_seen * 0.6, -1, 1)
	var line: Slackline = _main.get_node("Slackline")
	if _t < 1.0:
		_rest = line.sample_world(_a.s).y
	if _a.state == Athlete.State.ON_LINE:
		var dev := _a.bounce_dev()
		if _t > 1.0 and _t < 1.5:
			i.override_pump = true
		elif _t < 4.0 and absf(dev) > 0.03:
			i.override_pump = dev > 0.0
		elif _t >= 4.0:
			if _a.foot_velocity.y < 0.0:
				i.override_pump = true
			elif dev > 0.0:
				i.override_pump = false
	else:
		i.override_pump = false
		_best = maxf(_best, _a.global_position.y - _rest)
	var r: Array = _runs[_run_i]
	if _t >= float(r[2]):
		_results[r[0]] = _best
		_check(is_finite(line.tension()), "%s: line stays numerically stable" % r[0])
		_next_run()


func _finish() -> void:
	_gs.explosiveness = "soft"
	_gs.line_height = 2.2
	_gs.from_menu = false
	var soft: float = _results.get("soft", 0.0)
	var explo: float = _results.get("explosive", 0.0)
	var ext: float = _results.get("extreme", 0.0)
	print("    arcade: soft %.2f m, explosive %.2f m, extreme@10m %.2f m" % [soft, explo, ext])
	_check(explo > soft * 2.5, "Explosive jumps far higher than Soft (%.1f vs %.1f m)" % [explo, soft])
	_check(ext > 6.0, "Extreme on a 10 m line gives spectacular height (%.1f m)" % ext)
	_check(ext < 30.0, "energy stays bounded (%.1f m)" % ext)
	finished.emit(passes, failures)
