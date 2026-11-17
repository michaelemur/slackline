class_name DemoPilot
extends Node
## Autopilot that plays the game through AthleteInput (the same path a player
## or the touch controls use): pumps the line, releases on the up-stroke,
## and throws a rotating list of tricks. Toggle with T.

## Line tricks that follow each other are chained: the next one is pressed in
## the air, so the athlete lands straight into it (butt -> butt, back -> back).
## Air tricks are SET while bouncing in a butt/chest bounce: the leg drive out
## of the position launches them (that's where the big launches come from).
const SEQUENCE := ["butt", "butt", "backflip", "chest", "back", "spin360", "backflip360",
	"butt", "frontflip", "butt", "spin180"]

var athlete: Athlete
var enabled: bool = false
var _phase: String = "pump"
var _timer: float = 0.0
var _index: int = 0
var _was_airborne: bool = false
var _landed_count: int = 0
var _skipped_seen: int = 0
var open_early: float = 0.8   # rad before upright to open the tuck

## "video" mode: the combo from the reference clip (Rio beach, 6 tricks with
## no pause): every flip starts from and lands in a body position.
## Each step: [flip ("" = none), landing position ("feet" = on the feet)].
## A step whose flip is "drop" sits down from standing.
const VIDEO_COMBO := [["drop", "butt"], ["", "chest"], ["frontflip", "chest"], ["backflip", "butt"],
	["backflip", "feet"], ["drop", "butt"], ["frontflip", "chest"], ["backflip", "feet"]]
## "rikuto" mode: Angel flip and Manson flip in one combo (butt -> butt).
const BUTT_COMBO := [["backflip", "butt"], ["frontflip", "butt"]]
var mode: String = "classic"
var _step: int = 0
var _set_done: bool = false


func toggle() -> void:
	# T: classic demo -> video combo -> off
	if not enabled:
		mode = "classic"
		set_enabled(true)
	elif mode == "classic":
		mode = "video"
		set_enabled(true)
	elif mode == "video":
		mode = "rikuto"
		set_enabled(true)
	else:
		set_enabled(false)


func set_enabled(on: bool) -> void:
	enabled = on
	if athlete == null:
		return
	athlete.input.override_enabled = on
	athlete.tricks.skip_weak_flips = on
	athlete.input.override_move = 0.0
	athlete.input.override_balance = 0.0
	athlete.input.override_pump = false
	athlete.input.override_trick = ""
	_phase = "pump"
	_timer = 0.0
	_step = 0
	_set_done = false


func step(dt: float) -> void:
	if not enabled or athlete == null:
		return
	if mode == "video" or mode == "rikuto":
		_step_video(dt)
		return
	var inp := athlete.input
	var b := athlete.balance
	# Skilled balance: PD on lean, like a good player on the A/D keys.
	inp.override_balance = clampf(-(2.2 * b.theta + 0.6 * b.omega), -1.0, 1.0)
	_timer += dt
	# Advance the sequence only when a trick actually lands (or the flip was
	# skipped because the bounce was too small for it).
	if athlete.tricks.skipped != _skipped_seen:
		_skipped_seen = athlete.tricks.skipped
		_index += 1
	if athlete.tricks.tricks_landed != _landed_count:
		_landed_count = athlete.tricks.tricks_landed
		_index += 1
	match athlete.state:
		Athlete.State.ON_LINE:
			if _was_airborne:
				_was_airborne = false
				_phase = "recover"
				_timer = 0.0
			match _phase:
				"recover":
					inp.override_pump = false
					if _timer > 0.6:
						_phase = "pump"
						_timer = 0.0
				"pose":
					var nxt_air: String = SEQUENCE[_index % SEQUENCE.size()]
					if athlete.pose != "" and (TrickController.TRICKS.has(nxt_air) or TrickController.COMBOS.has(nxt_air)) \
							and athlete.tricks.queued == "" and athlete.tricks.queued_twist == "":
						inp.override_trick = nxt_air   # set the flip during the bounce
					if athlete.pose == "" and _timer > 0.3:
						_phase = "recover"
						_timer = 0.0
				"pump":
					var next: String = SEQUENCE[_index % SEQUENCE.size()]
					# Physical pumping technique (same as the lab's in-phase rhythm):
					# squat while the line is high, drive the legs while it is low.
					var dev := athlete.bounce_dev()
					if TrickController.LINE_TRICKS.has(next):
						inp.override_pump = false
						inp.override_trick = next
						_phase = "pose"
						_timer = 0.0
						return
					if _timer < 0.4:
						inp.override_pump = true
					elif absf(dev) > 0.03:
						inp.override_pump = dev > 0.0
					# Queue the next trick early; it fires at a big enough takeoff.
					if athlete.tricks.queued == "":
						inp.override_trick = next
				"ride":
					inp.override_pump = false
					if _timer > 2.0:
						_phase = "pump"
						_timer = 0.0
		Athlete.State.AIRBORNE:
			if not _was_airborne:
				_was_airborne = true
			# Tuck timing: tuck to spin fast, open ~1 rad before upright to slow
			# the rotation for landing.
			var tr := athlete.tricks
			inp.override_pump = tr.tuck_hint(open_early) > 0.5
			var nxt: String = SEQUENCE[_index % SEQUENCE.size()]
			# Land into a bounce position when the next trick is a line trick, or
			# when an air trick is next (it will be set from that position).
			var want := nxt if TrickController.LINE_TRICKS.has(nxt) else "butt"
			if athlete.tricks.queued_pose == "" and not athlete.tricks.is_rotating() \
					and absf(athlete.tricks.l_pitch) < 1.0:
				inp.override_trick = want
		Athlete.State.FALLEN:
			inp.override_pump = false
			_phase = "recover"
			_timer = 0.0


func _step_video(dt: float) -> void:
	var inp := athlete.input
	var b := athlete.balance
	var tr := athlete.tricks
	inp.override_balance = clampf(-(2.2 * b.theta + 0.6 * b.omega), -1.0, 1.0)
	_timer += dt
	var combo: Array = BUTT_COMBO if mode == "rikuto" else VIDEO_COMBO
	var cur: Array = combo[_step % combo.size()]
	match athlete.state:
		Athlete.State.ON_LINE:
			if _was_airborne:
				_was_airborne = false
				_step += 1
				_set_done = false
				_timer = 0.0
				cur = combo[_step % combo.size()]
			inp.override_pump = false
			if athlete.pose == "" and athlete._rising_from == "":
				# on the feet: the next step must start by sitting down
				# sit down straight after landing on the feet, while the line is
				# still loaded (as in the video): its recoil throws the butt bounce.
				# A "drop" step is that sit-down; otherwise (feet where a position
				# was expected) sit down and keep the step.
				if _timer > 0.06:
					inp.override_trick = cur[1] if cur[0] == "drop" else "butt"
					if cur[0] == "drop":
						_step += 1
					_timer = 0.0
				return
			# bouncing in a position: choose the landing position, then set the
			# flip (one key per frame, both before the leg drive)
			if athlete.pose != "" and athlete._pose_contacted and athlete.pose_time > 0.1 and not _set_done:
				if tr.queued_pose != _want_pose(cur[1]) and cur[1] != "feet":
					inp.override_trick = cur[1]
				elif cur[0] != "" and cur[0] != "drop" and tr.queued == "":
					inp.override_trick = cur[0]
				else:
					_set_done = true
		Athlete.State.AIRBORNE:
			_was_airborne = true
			inp.override_pump = tr.tuck_hint(open_early) > 0.5
		Athlete.State.FALLEN:
			_step = 0
			_set_done = false
			_was_airborne = false


func _want_pose(p: String) -> String:
	return "" if p == "feet" else p
