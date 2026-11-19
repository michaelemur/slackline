extends Node
## Scenario on the real main scene: the simple controls and the fail system.
##  * right hand = power: pumping works in every position, with less power
##    from the butt (90 %), chest (80 %) and back (50 %) than the feet;
##  * left hand = position: in a real jump the landing is locked late (close
##    to touchdown). Too early does not count, no lock = fail;
##  * chest and back locked late land on the chest / back from the feet, the
##    butt and the chest - never swapped;
##  * a fail picks a random fail type, the body goes floppy (ragdoll) and he
##    is back on the line quickly.
## Inputs go through AthleteInput overrides exactly as a player's would.

signal finished(passes: int, failures: Array)

var main: Node3D
var athlete: Athlete
var line: Slackline
var passes := 0
var failures: Array = []
var _steps: Array = []
var _step := 0
var _step_t := 0.0
var _case := {}             # per-step scratch
var _results := {}          # "from>to" -> landed pose / "FAIL"
var _fail_seen := {}
var _rag_energy := 0.0
var _rag_joint_span := 0.0
var _rag_samples := {}
var _reset_after := -1.0
var _too_early_seen := false
var _strength_seen := {}

const LAUNCH_V := 6.5        # m/s, a real jump (~1.3 s in the air)
const LOCK_AT := 0.35        # s before touchdown


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	athlete = main.get_node("Athlete")
	line = main.get_node("Slackline")
	athlete.input.override_enabled = true
	athlete.failed.connect(func(kind: String): _fail_seen[kind] = int(_fail_seen.get(kind, 0)) + 1)
	_steps = [["settle", 0.8, Callable(), Callable()]]
	# chest / back from feet, butt and chest
	for from in ["feet", "butt", "chest"]:
		for to in ["chest", "back"]:
			_steps.append(["%s>%s" % [from, to], 4.2, _jump_and_lock.bind(from, to), _end_jump.bind(from, to)])
	_steps.append(["early press", 3.5, _early_press, _check_early])
	_steps.append(["no lock", 4.5, _no_lock, _check_no_lock])
	_steps.append(["easy no lock", 3.5, _easy_no_lock, _check_easy_no_lock])
	_steps.append(["free air", 3.5, _free_air, _check_free_air])
	for p in ["butt", "chest", "back"]:
		_steps.append(["pump " + p, 3.0, _pump_in.bind(p), Callable()])
	_steps.append(["end", 0.1, Callable(), Callable()])


func _check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures.append("[landing lock] " + msg)


func _physics_process(dt: float) -> void:
	if athlete == null or _step >= _steps.size():
		return
	_step_t += dt
	var i := athlete.input
	i.override_trick = ""
	i.override_balance = 0.0      # auto balance does the work
	var st: Array = _steps[_step]
	if (st[2] as Callable).is_valid():
		(st[2] as Callable).call(dt)
	if _step_t >= float(st[1]):
		if (st[3] as Callable).is_valid():
			(st[3] as Callable).call()
		_step += 1
		_step_t = 0.0
		_case = {}
		i.override_pump = false
		if _step >= _steps.size():
			_finish()
		else:
			athlete.reset_to_line(line.chord_length() * 0.5)


## Gets into the start position, launches a real jump, locks the landing late.
func _jump_and_lock(dt: float, from: String, to: String) -> void:
	var a := athlete
	var phase: String = _case.get("phase", "setup")
	match phase:
		"setup":
			if from != "feet" and _step_t > 0.1 and a.pose == "" and not _case.has("pressed"):
				a.input.override_trick = from
				_case["pressed"] = true
			var ready := (from == "feet" and _step_t > 0.3) or (a.pose == from and a._pose_contacted and a.pose_time > 0.15)
			if ready and a.state == Athlete.State.ON_LINE:
				a.launch(Vector3.UP * LAUNCH_V)
				_case["phase"] = "air"
				_case["needs_lock"] = a.needs_lock
		"air":
			if a.state == Athlete.State.AIRBORNE:
				if not a.tricks.locked and a.land_eta() < LOCK_AT:
					a.input.override_trick = to
			elif not _case.has("landed"):
				_case["landed"] = a.pose if a.state == Athlete.State.ON_LINE else "FAIL:" + a.fail_kind
				_case["outcome"] = a.tricks.last_outcome


func _end_jump(from: String, to: String) -> void:
	var key := "%s>%s" % [from, to]
	var landed: String = _case.get("landed", "none")
	_results[key] = landed
	_check(_case.get("needs_lock", false), "%s: a %.1f m/s launch is a real jump (needs a lock)" % [key, LAUNCH_V])
	_check(landed == to, "%s: locked %s late, lands on the %s (got %s, %s)" % [key, to, to, landed, _case.get("outcome", "")])
	var other := "back" if to == "chest" else "chest"
	_check(landed != other, "%s: never lands on the %s" % [key, other])


## Pressing the landing long before touchdown does not lock it.
func _early_press(_dt: float) -> void:
	var a := athlete
	a.require_lock = true       # hardcore mode
	if not _case.has("launched") and _step_t > 0.2:
		a.launch(Vector3.UP * LAUNCH_V)
		_case["launched"] = true
		return
	if a.state == Athlete.State.AIRBORNE:
		var eta := a.land_eta()
		if eta > TrickController.LOCK_WINDOW + 0.2 and not _case.has("early"):
			a.input.override_trick = "chest"
			_case["early"] = true
			_case["early_eta"] = eta
		elif _case.has("early") and not _case.has("checked"):
			_case["checked"] = true
			_too_early_seen = not a.tricks.locked and a.tricks.message.begins_with("Too early")
		elif eta < LOCK_AT and not a.tricks.locked:
			a.input.override_trick = "feet"      # lock properly afterwards
	elif _case.has("launched") and not _case.has("landed") and _step_t > 0.4:
		_case["landed"] = a.pose if a.state == Athlete.State.ON_LINE else "FAIL"


func _check_early() -> void:
	_check(_case.has("early"), "pressed CHEST early in the jump (%.2f s before touchdown)" % float(_case.get("early_eta", 0.0)))
	_check(_too_early_seen, "an early press is not a lock (\"Too early\")")
	_check(_case.get("landed", "") == "", "a proper late FEET lock after it lands on the feet (%s)" % _case.get("landed", "?"))


## A real jump with no landing chosen: fail -> ragdoll -> quick reset.
func _no_lock(dt: float) -> void:
	var a := athlete
	a.require_lock = true       # hardcore mode
	if not _case.has("launched") and _step_t > 0.2:
		a.launch(Vector3.UP * LAUNCH_V)
		_case["launched"] = true
		_case["t_launch"] = _step_t
		return
	if a.state == Athlete.State.FALLEN:
		if not _case.has("t_fall"):
			_case["t_fall"] = _step_t
			_case["kind"] = a.fail_kind
			_case["ragdoll"] = a.visual.ragdoll_on
		_rag_energy = maxf(_rag_energy, a.visual.ragdoll_energy)
		# how far the limbs flop about while ragdolling
		for j in ["thx_l", "ax_r", "shx_l"]:
			var v: Vector2 = a.visual._rag.get(j, Vector2.ZERO)
			var mm: Vector2 = _rag_samples.get(j, Vector2(INF, -INF))
			_rag_samples[j] = Vector2(minf(mm.x, v.x), maxf(mm.y, v.x))
	elif _case.has("t_fall") and not _case.has("t_back") and a.state == Athlete.State.ON_LINE:
		_case["t_back"] = _step_t


func _check_no_lock() -> void:
	_check(_case.has("t_fall"), "no landing chosen in a real jump = fail")
	_check(String(_case.get("kind", "")) in Athlete.FAIL_KINDS, "fail has a type (%s)" % _case.get("kind", ""))
	_check(_case.get("ragdoll", false), "the body goes floppy (ragdoll) on the fail")
	for j in _rag_samples:
		_rag_joint_span = maxf(_rag_joint_span, (_rag_samples[j] as Vector2).y - (_rag_samples[j] as Vector2).x)
	_check(_rag_energy > 2.0, "ragdoll limbs flop about (peak joint speed %.1f rad/s)" % _rag_energy)
	_check(_rag_joint_span > 0.8, "ragdoll joints swing through a wide range (%.2f rad)" % _rag_joint_span)
	var back_t: float = float(_case.get("t_back", INF)) - float(_case.get("t_fall", 0.0))
	_reset_after = back_t
	_check(back_t <= athlete.fail_max_time + 0.05, "back on the line quickly after the fall (%.2f s)" % back_t)
	athlete.require_lock = false
	_check(athlete.state == Athlete.State.ON_LINE and not athlete.visual.ragdoll_on, "reset leaves the ragdoll and stands on the line")


## Easy mode (default): never choosing a landing just lands him.
func _easy_no_lock(_dt: float) -> void:
	var a := athlete
	a.require_lock = false
	if not _case.has("launched") and _step_t > 0.2:
		a.launch(Vector3.UP * LAUNCH_V)
		_case["launched"] = true
		_case["fails0"] = _fail_count()
		return
	if _case.has("launched") and a.state == Athlete.State.ON_LINE and not _case.has("landed") and _step_t > 0.5:
		_case["landed"] = a.pose


func _check_easy_no_lock() -> void:
	_check(_case.has("landed"), "easy mode: a real jump with no position chosen lands on the line")
	_check(_fail_count() == int(_case.get("fails0", -1)), "easy mode: no fail for not choosing")


func _fail_count() -> int:
	var n := 0
	for k in _fail_seen:
		n += int(_fail_seen[k])
	return n


## Free air control on the real scene: start a flip after takeoff, reverse
## it, add and take out twist, tuck twice, grab, leg shape - all in one jump,
## then let go and land.
func _free_air(_dt: float) -> void:
	var a := athlete
	var i := a.input
	a.require_lock = false
	i.override_aim = Vector2.ZERO
	i.override_grab = ""
	i.override_tuck = -1.0
	if not _case.has("launched") and _step_t > 0.2:
		a.launch(Vector3.UP * 7.0)
		_case["launched"] = true
		_case["fails0"] = _fail_count()
		_case["t0"] = _step_t
		return
	if not _case.has("launched") or a.state != Athlete.State.AIRBORNE:
		if _case.has("launched") and a.state == Athlete.State.ON_LINE and _case.has("w_back") and not _case.has("landed"):
			_case["landed"] = a.pose if a.pose != "" else "feet"
		return
	var at := a.air_time
	var tr := a.tricks
	if at < 0.1:
		pass                                   # straight takeoff, nothing set
	elif at < 0.35:
		i.override_aim = Vector2(0, -1)        # start a frontflip mid-air
		_case["w_front"] = tr.omega_pitch
	elif at < 0.6:
		i.override_aim = Vector2(0, 1)         # reverse it into a backflip
		_case["w_back"] = tr.omega_pitch
	elif at < 0.75:
		i.override_aim = Vector2(1, 0)         # add twist
		i.override_tuck = 1.0
		_case["twist"] = tr.l_twist
		_case["tuck1"] = tr.tuck
	elif at < 0.85:
		i.override_tuck = 0.0
		i.override_grab = "both_knees"
		_case["grab"] = tr.grab_w
	elif at < 0.95:
		i.override_aim = Vector2(-1, 0)        # take the twist out
		i.override_tuck = 1.0
		i.override_grab = "split"
	elif at < 1.0:
		_case["twist_after"] = tr.l_twist
	# then hands off: settle and land


func _check_free_air() -> void:
	_check(float(_case.get("w_front", 0.0)) > 0.8, "flip started after takeoff (%.1f rad/s)" % float(_case.get("w_front", 0.0)))
	_check(float(_case.get("w_back", 0.0)) < -0.3, "same jump: reversed into a backflip (%.1f rad/s)" % float(_case.get("w_back", 0.0)))
	_check(float(_case.get("twist", 0.0)) > 0.3, "twist added mid-flip (L %.2f)" % float(_case.get("twist", 0.0)))
	_check(float(_case.get("twist_after", 9.0)) < float(_case.get("twist", 0.0)), "twist taken out again")
	_check(float(_case.get("tuck1", 0.0)) > 0.4, "tucked during the flight")
	_check(float(_case.get("grab", 0.0)) > 0.3, "grabbed during the flight")
	_check(_case.has("landed"), "still in control until touchdown, then back on the line (%s)" % _case.get("landed", "?"))


## Pumping in a position: every push uses that position's power.
func _pump_in(_dt: float, p: String) -> void:
	var a := athlete
	if _step_t > 0.1 and a.pose == "" and a._rising_from == "" and not _case.has("pressed"):
		a.input.override_trick = p
		_case["pressed"] = true
	if a.state == Athlete.State.ON_LINE and (a.pose == p or a._rising_from == p) and _step_t > 0.3:
		a.input.override_pump = line.sample_velocity(a.s).y < 0.0
	if a._rising_from == p:
		_strength_seen[p] = a.leg.strength


func _finish() -> void:
	for p in ["butt", "chest", "back"]:
		var want := Athlete.position_power(p)
		_check(_strength_seen.has(p), "pumped from the %s (a push happened)" % p)
		_check(is_equal_approx(float(_strength_seen.get(p, -1.0)), want), "%s push power is %d %% (got %.2f)" % [p, int(want * 100.0), float(_strength_seen.get(p, -1.0))])
	_check(is_equal_approx(Athlete.position_power(""), 1.0) and is_equal_approx(Athlete.position_power("feet"), 1.0), "feet push power is 100 %")
	# fail types are random, weighted by what went wrong
	var counts := {}
	for i in 400:
		var k := athlete._pick_fail_kind("none")
		counts[k] = int(counts.get(k, 0)) + 1
	_check(counts.size() == Athlete.FAIL_KINDS.size(), "every fail type can happen (%s)" % str(counts))
	athlete.reset_to_line(line.chord_length() * 0.5)
	athlete.input.override_trick = ""
	athlete._enter_pose("butt", false)
	var twisted := 0
	for i in 400:
		if athlete._pick_fail_kind("balance") == "twisted_off":
			twisted += 1
	_check(twisted > 240, "out of balance in a butt bounce: mostly twisted off sideways (%d / 400)" % twisted)
	var over := 0
	for i in 400:
		if athlete._pick_fail_kind("over") == "over_rotate":
			over += 1
	_check(over > 200, "an over-rotation bail mostly fails as over-rotating (%d / 400)" % over)
	print("    landing lock: %s, fails %s, reset after %.2f s, ragdoll peak %.1f rad/s" % [str(_results), str(_fail_seen), _reset_after, _rag_energy])
	finished.emit(passes, failures)
