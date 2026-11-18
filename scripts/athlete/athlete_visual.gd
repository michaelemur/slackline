class_name AthleteVisual
extends Node3D
## Placeholder stylised athlete built from primitives. Visual only: it is
## posed from gameplay/physics state and never feeds back into physics.
## Segments: thighs + shins (real knee bend), torso, head, two independent
## arms. Shows the centre of mass (navel) and a plumb line to the slackline.
## Will be replaced by a rigged Blender glTF (see docs/ASSETS.md).

const THIGH := 0.45
const SHIN := 0.45
const LEG_LEN := THIGH + SHIN
const COM_HEIGHT := 1.0      # pivot for flips (approx. navel)

## Developer-only COM/plumb overlay. Toggle with G; hidden during normal play.
var show_com: bool = false

var _trick: Node3D       # flips/spins about the centre of mass
var _pose: Node3D        # line-trick body positions (butt/chest/back)
var _pivot: Node3D       # whole-body lean about the feet
var _hips: Node3D        # moves down when knees bend
var _upper: Node3D       # torso/head/arms (hip strategy counter-tilt)
var _thigh_l: Node3D
var _thigh_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _com_marker: MeshInstance3D
var _plumb: MeshInstance3D
var _plumb_mat := StandardMaterial3D.new()
var character: AthleteCharacter      # real skinned athlete (null = capsules)
var _capsules: Array[Node3D] = []
var use_character: bool = true


func _ready() -> void:
	process_priority = 10   # after the character has solved this frame
	var skin := _mat(Color(0.78, 0.78, 0.78))
	var top := _mat(Color(0.96, 0.96, 0.96))
	var pants := _mat(Color(0.48, 0.48, 0.5))
	_trick = Node3D.new()
	_trick.position = Vector3(0, COM_HEIGHT, 0)
	add_child(_trick)
	_pose = Node3D.new()
	_trick.add_child(_pose)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, -COM_HEIGHT, 0)
	_pose.add_child(_pivot)
	_hips = Node3D.new()
	_hips.position = Vector3(0, LEG_LEN, 0)
	_pivot.add_child(_hips)
	# Legs: hip joint -> thigh -> knee joint -> shin
	_thigh_l = _limb(_hips, Vector3(-0.1, 0, 0), 0.08, THIGH, pants)
	_thigh_r = _limb(_hips, Vector3(0.1, 0, 0), 0.08, THIGH, pants)
	_shin_l = _limb(_thigh_l, Vector3(0, -THIGH, 0), 0.065, SHIN, pants)
	_shin_r = _limb(_thigh_r, Vector3(0, -THIGH, 0), 0.065, SHIN, pants)
	_upper = Node3D.new()
	_hips.add_child(_upper)
	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.17
	cap.height = 0.62
	torso.mesh = cap
	torso.material_override = top
	torso.position = Vector3(0, 0.32, 0)
	_upper.add_child(torso)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.12
	sph.height = 0.24
	head.mesh = sph
	head.material_override = skin
	head.position = Vector3(0, 0.78, 0)
	_upper.add_child(head)
	_arm_l = _limb(_upper, Vector3(-0.2, 0.58, 0), 0.05, 0.66, skin)
	_arm_r = _limb(_upper, Vector3(0.2, 0.58, 0), 0.05, 0.66, skin)
	# Centre of mass marker (navel) + plumb line.
	_com_marker = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.045
	dot.height = 0.09
	_com_marker.mesh = dot
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1.0, 0.9, 0.1)
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.no_depth_test = true
	cm.render_priority = 1
	_com_marker.material_override = cm
	# World-space COM from the body segments (set every frame, top level so
	# no parent rotation can carry it off the body).
	_com_marker.top_level = true
	add_child(_com_marker)
	_plumb = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = 1.0
	_plumb.mesh = cyl
	_plumb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plumb_mat.no_depth_test = true
	_plumb.material_override = _plumb_mat
	_plumb.top_level = true
	add_child(_plumb)
	_setup_character()


## Loads the skinned athlete and maps it onto this pose rig. The capsule body
## stays as a fallback (and is shown if the model is missing).
func _setup_character() -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		if n != _com_marker and n != _plumb:
			_capsules.append(n)
	# Reference pose: the rig posed like the model's rest (A-pose arms).
	var a := 0.72
	set_body(0.0, 0.0, a, a, 0.0, COM_HEIGHT)
	set_trick_rotation(0.0, 0.0)
	var refs := {}
	for pair in [["pelvis", _hips], ["spine_03", _upper], ["upperarm_l", _arm_l], ["upperarm_r", _arm_r]]:
		var node: Node3D = pair[1]
		refs[pair[0]] = [node, _rel(node)]
	set_body(0.0, 0.0, 0.0, 0.0, 0.0, COM_HEIGHT)
	var c := AthleteCharacter.new()
	c.name = "Character"
	add_child(c)
	if c.setup(self, refs):
		character = c
	else:
		c.queue_free()
	set_use_character(use_character)


func set_use_character(on: bool) -> void:
	use_character = on
	var show_char := on and character != null
	if character != null:
		character.visible = show_char
	for m in _capsules:
		m.visible = not show_char


func _rel(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != self:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


var _ref_w := 0.0
const TUCK_HIP := 2.1    # rad hip flexion at full tuck
const TUCK_KNEE := 2.3   # rad knee flexion at full tuck


## Deep tuck on top of the current leg pose (knees to chest).
func set_tuck(t: float) -> void:
	if _thigh_l == null or t <= 0.0:
		return
	var e := t * t * (3.0 - 2.0 * t)
	for th in [_thigh_l, _thigh_r]:
		th.rotation.x = lerpf(th.rotation.x, TUCK_HIP, e)
	for sh in [_shin_l, _shin_r]:
		sh.rotation.x = lerpf(sh.rotation.x, -TUCK_KNEE, e)


## Limb angles from a motion-capture reference (rad): hip and knee flexion,
## shoulder flexion (arm forward/up), elbow flexion. w = blend weight.
func set_reference_limbs(hip: float, knee: float, shoulder: float, elbow: float, w: float,
		dt: float = 1.0 / 60.0) -> void:
	_ref_w = move_toward(_ref_w, clampf(w, 0.0, 1.0), maxf(dt, 0.0) * 6.0)
	if _ref_w <= 0.0 or _thigh_l == null:
		if character != null:
			character.ref_arm_w = 0.0
		return
	for th in [_thigh_l, _thigh_r]:
		th.rotation.x = lerpf(th.rotation.x, hip, _ref_w)
	for sh in [_shin_l, _shin_r]:
		sh.rotation.x = lerpf(sh.rotation.x, -knee, _ref_w)
	if character != null:
		character.ref_arm_w = _ref_w
		character.ref_shoulder = shoulder
		character.ref_elbow = elbow


func get_shin(side: String) -> Node3D:
	return _shin_l if side == "l" else _shin_r


## Contact/tuck hints for the skinned athlete (feet pinned on the line or free).
func set_character_state(feet_on_line: bool, tuck_amount: float) -> void:
	if character == null:
		return
	character.contact_target = 1.0 if feet_on_line else 0.0
	character.tuck = tuck_amount


## Full body pose from the physics state.
##  lean: whole-body roll (rad); crouch: knee bend 0..1; arm_l/arm_r: arm
##  angles from hanging (rad); hip: hip-strategy input -1..1; com_h: COM height.
func set_body(lean: float, crouch: float, arm_l: float, arm_r: float, hip: float,
		com_h: float) -> void:
	if _pivot == null:
		return
	_pivot.basis = Basis(Vector3(0, 0, -1), lean)
	# Knee bend: thigh forward, shin back -> hips drop, feet stay under hips.
	var k := clampf(crouch, 0.0, 1.0) * 0.9
	_thigh_l.rotation.x = k
	_thigh_r.rotation.x = k
	_shin_l.rotation.x = -2.0 * k
	_shin_r.rotation.x = -2.0 * k
	_hips.position.y = THIGH * cos(k) + SHIN * cos(k)
	# Upper body leans forward a bit when crouched, and counter-tilts against
	# the legs when using the hips (hip strategy).
	_upper.rotation = Vector3(-k * 0.45, 0, -hip * 0.3)
	_arm_l.rotation = Vector3(0, 0, -arm_l)
	_arm_r.rotation = Vector3(0, 0, arm_r)
	_com_marker.visible = show_com
	_update_plumb()


## World-space centre of mass of the drawn body (segment masses).
func com_global() -> Vector3:
	if character != null and character.visible and not character.last_pose.is_empty():
		return to_global(character.position + character.com)
	return _proxy_com_global()


func _proxy_com_global() -> Vector3:
	# capsule fallback: trunk 50 %, head 7 %, arms 10 %, thighs 28 %, shins 9 %
	var p := _hips.to_global(Vector3(0, 0.3, 0)) * 0.50 + _upper.to_global(Vector3(0, 0.78, 0)) * 0.07
	p += (_arm_l.to_global(Vector3(0, -0.33, 0)) + _arm_r.to_global(Vector3(0, -0.33, 0))) * 0.05
	p += (_thigh_l.to_global(Vector3(0, -THIGH * 0.5, 0)) + _thigh_r.to_global(Vector3(0, -THIGH * 0.5, 0))) * 0.14
	p += (_shin_l.to_global(Vector3(0, -SHIN * 0.5, 0)) + _shin_r.to_global(Vector3(0, -SHIN * 0.5, 0))) * 0.045
	return p


## End of the physics tick: solve the skeleton, then place the COM ball.
func finish_frame(dt: float) -> void:
	if character != null:
		character.update(dt)
	if _com_marker == null or not is_inside_tree():
		return
	_com_marker.global_position = com_global()
	_update_plumb()


func _update_plumb() -> void:
	if not is_inside_tree():
		return
	_plumb.visible = show_com and is_visible_in_tree()
	if not _plumb.visible:
		return
	var com := _com_marker.global_position
	var feet := global_position
	var h := maxf(0.01, com.y - feet.y)
	_plumb.global_transform = Transform3D(Basis().scaled(Vector3(1, h, 1)),
		Vector3(com.x, feet.y + h * 0.5, com.z))
	# Green when the COM is over the line, red as it drifts off.
	var lateral := (com - feet)
	lateral.y = 0.0
	var off := lateral.length()
	_plumb_mat.albedo_color = Color(0.2, 1.0, 0.3).lerp(Color(1.0, 0.2, 0.15), clampf(off / 0.25, 0.0, 1.0))


## Body positions for line tricks, blended in with b (0 = standing, 1 = full).
## low: 0..1, how close the line is to the ground (legs reach forward so
## they don't drag and stop the movement).
func set_line_pose(pose_name: String, b: float, low: float = 0.0, tilt_scale: float = 1.0) -> void:
	if _pose == null:
		return
	b = clampf(b, 0.0, 1.0)
	var e := b * b * (3.0 - 2.0 * b)  # smoothstep
	var drop := 0.0
	var tilt := 0.0      # + = lean back (about local +X)
	var legs := 0.0      # + = swing legs forward
	var shin_l := 0.0
	var shin_r := 0.0
	var shin := 0.0      # knee bend relative to the thigh
	match pose_name:
		"butt":
			# Sitting in a chair: thighs forward, shins hanging down. When the
			# line goes low, the legs reach forward so the feet clear the floor.
			drop = 0.85
			tilt = 0.2 + 0.15 * low
			legs = 1.45
			shin = lerpf(-1.35, -0.15, clampf(low, 0.0, 1.0))
		"chest":
			drop = 0.85
			tilt = -PI * 0.5   # face down, head toward travel direction
		"back":
			drop = 0.85
			tilt = PI * 0.5    # on the back, looking at the sky
	_pose.position = Vector3(0, -drop * e, 0)
	# Chest bounce: the body lies a bit diagonal across the line (legs swung
	# to the right, extended right leg off the line), not straight along it.
	var yaw := CHEST_DIAGONAL if pose_name == "chest" else 0.0
	_pose.basis = Basis(Vector3.UP, yaw * e * tilt_scale) * Basis(Vector3.RIGHT, tilt * e * tilt_scale)
	if e > 0.0:
		_thigh_l.rotation.x = lerpf(_thigh_l.rotation.x, legs, e)
		_thigh_r.rotation.x = lerpf(_thigh_r.rotation.x, legs, e)
		_shin_l.rotation.x = lerpf(_shin_l.rotation.x, shin, e)
		_shin_r.rotation.x = lerpf(_shin_r.rotation.x, shin * 0.85, e)


# ---------------------------------------------------------------- body dynamics
## Per-joint spring-damper state: name -> Vector2(angle, velocity).
var _jt := {}
## Natural frequency (rad/s) and damping ratio per joint group: legs are
## firm, arms loose (they overshoot and swing like real arms), elbows looser.
const JOINT_SPRING := {"leg": Vector2(22.0, 0.85), "arm": Vector2(13.0, 0.55),
	"elbow": Vector2(11.0, 0.5), "spine": Vector2(16.0, 0.8)}
## Human ranges of motion (rad) for the pose rig's joints.
const JOINT_LIMIT := {"thigh_x": Vector2(-0.5, 2.3), "thigh_z": Vector2(-0.8, 0.8),
	"shin_x": Vector2(-2.45, 0.0), "arm_x": Vector2(-1.0, 2.8), "arm_z": Vector2(-3.05, 3.05),
	"elbow": Vector2(0.05, 2.5), "upper_x": Vector2(-0.6, 0.9), "upper_y": Vector2(-0.6, 0.6),
	"upper_z": Vector2(-0.5, 0.5), "hips_y": Vector2(-0.5, 0.5)}


func _spring(key: String, group: String, target: float, dt: float, lim: String = "") -> float:
	var st: Vector2 = _jt.get(key, Vector2(target, 0.0))
	var p: Vector2 = JOINT_SPRING[group]
	var w := p.x
	var z := p.y
	# semi-implicit spring-damper step, sub-stepped for stability at 60 Hz
	var n := 2
	var h := dt / n
	for i in n:
		var acc := w * w * (target - st.x) - 2.0 * z * w * st.y
		st.y += acc * h
		st.x += st.y * h
	if lim != "":
		var l: Vector2 = JOINT_LIMIT[lim]
		if st.x < l.x:
			st = Vector2(l.x, maxf(st.y, 0.0))
		elif st.x > l.y:
			st = Vector2(l.y, minf(st.y, 0.0))
	_jt[key] = st
	return st.x


## Builds every joint's target from the physics state, then lets each joint
## follow it with its own spring-damper. ctx (from Athlete):
##  state 0 line/1 air/2 fallen, pose, pose_b, gait (phase), walk (0..1),
##  lift_l/lift_r, arm_flex, phi, omega, tuck, grab, grab_w, line_pt (visual
##  space point on the line under the chest).
func apply_body(ctx: Dictionary, dt: float) -> void:
	if _thigh_l == null:
		return
	var st: int = ctx.get("state", 0)
	var pose: String = ctx.get("pose", "")
	var pb: float = ctx.get("pose_b", 0.0)
	var e := pb * pb * (3.0 - 2.0 * pb)
	var gait: float = ctx.get("gait", 0.0)
	var walk: float = ctx.get("walk", 0.0) if st == 0 and pose == "" else 0.0
	var grab: String = ctx.get("grab", "")
	var gw: float = ctx.get("grab_w", 0.0) if st == 1 else 0.0
	var on_feet := 1.0 if st == 0 and pose == "" else 0.0
	# forward/back lean about the feet (ankle strategy)
	_pivot.basis = _pivot.basis * Basis(Vector3.RIGHT, -float(ctx.get("phi", 0.0)) * on_feet)
	# ---- legs ---- (chest bounce: right leg extended, left bent; see CHEST_DIAGONAL)
	var tgt := {}
	for side: String in ["l", "r"]:
		var thigh: Node3D = _thigh_l if side == "l" else _thigh_r
		var shin: Node3D = _shin_l if side == "l" else _shin_r
		var out := -1.0 if side == "l" else 1.0          # rotation.z sign that moves this leg outward
		var tx := thigh.rotation.x
		var tz := 0.0
		var sx := shin.rotation.x
		# single-leg balance / counterweight leg (from the balance model)
		var lift: float = ctx.get("lift_" + side, 0.0) * on_feet
		tx += 0.3 * lift
		tz += out * 0.6 * lift
		sx -= 0.55 * lift
		# walking: alternate swing legs (left swings while sin(gait) > 0)
		var sw := maxf(0.0, sin(gait) * (1.0 if side == "l" else -1.0)) * walk
		tx += 0.35 * sw
		sx -= 0.75 * sw
		# bounce positions (blended with the position blend e)
		if pose == "chest":
			# As in the reference photos: chest on the line, both legs off to
			# the right and hanging down; right leg long, left leg bent.
			if side == "r":
				tx = lerpf(tx, 0.55, e)
				tz = lerpf(tz, out * 0.5, e)
				sx = lerpf(sx, -0.15, e)
			else:
				tx = lerpf(tx, 0.8, e)
				tz = lerpf(tz, -out * 0.35, e)
				sx = lerpf(sx, -1.45, e)
		elif pose == "back":
			# legs ~45 deg above horizontal, slightly open V, knees soft
			tx = lerpf(tx, BACK_HIP, e)
			tz = lerpf(tz, out * 0.2, e)
			sx = lerpf(sx, -0.25, e)
		# Reaching for the line before a feet landing: each leg aims at the
		# predicted contact point (diagonal when it's off to the side or far,
		# vertical right above it); feet stay pointed, so toes touch first.
		var lw: float = ctx.get("land_w", 0.0)
		if lw > 0.0 and ctx.has("land_pt"):
			var hip_g := thigh.global_position
			var d: Vector3 = (_hips.global_transform.basis.inverse() * ((ctx["land_pt"] as Vector3) - hip_g))
			var aim_x := atan2(-d.z, -d.y)
			var aim_z := atan2(d.x, -d.y)
			tx = lerpf(tx, clampf(aim_x, -0.4, 1.2), lw)
			tz = lerpf(tz, clampf(aim_z, -0.6, 0.6), lw)
			sx = lerpf(sx, -0.12, lw)
		# grabs: body shape for each grab
		if gw > 0.0:
			var g := _grab_leg_shape(grab, side)
			tx = lerpf(tx, g.x, gw)
			sx = lerpf(sx, g.y, gw)
			tz = lerpf(tz, out * g.z, gw)
		var grp := "leg"
		thigh.rotation.x = _spring("thx_" + side, grp, tx, dt, "thigh_x")
		thigh.rotation.z = _spring("thz_" + side, grp, tz, dt, "thigh_z")
		shin.rotation.x = _spring("shx_" + side, grp, sx, dt, "shin_x")
		tgt[side] = lift
	# ---- pelvis / spine ----
	var hy := 0.14 * cos(gait) * walk
	_hips.rotation.y = _spring("hips_y", "spine", hy, dt, "hips_y")
	var ux := _upper.rotation.x
	var uy := 0.0
	var uz := _upper.rotation.z
	if pose == "chest":
		uz = lerpf(uz, 0.22, e)   # chest diagonal on the line
		uy = lerpf(uy, 0.2, e)
	elif pose == "back":
		ux = lerpf(ux, -0.15, e)
	_upper.rotation = Vector3(_spring("up_x", "spine", ux, dt, "upper_x"),
		_spring("up_y", "spine", uy - hy * 0.6, dt, "upper_y"), _spring("up_z", "spine", uz, dt, "upper_z"))
	# ---- arms: abduction from the balance model, plus forward/back swing ----
	var flex: float = ctx.get("arm_flex", 0.0) * on_feet
	# sagittal arm swing (down while loading, up while driving / rising)
	var swing: float = ctx.get("arm_swing", 0.0)
	var swing_w := 0.0 if pose != "" else 1.0
	for side: String in ["l", "r"]:
		var arm: Node3D = _arm_l if side == "l" else _arm_r
		var az := arm.rotation.z
		# walking counter-swing: arm opposite to the swinging leg goes forward
		var ax := flex * 0.8 + 0.3 * sin(gait) * walk * (-1.0 if side == "l" else 1.0)
		ax = lerpf(ax, swing, swing_w * clampf(absf(swing - 0.4) / 0.6, 0.0, 1.0))
		if pose == "chest":
			# both hands under the chest on the line
			az = lerpf(az, 0.3 * (-1.0 if side == "l" else 1.0), e)
			ax = lerpf(ax, 1.25, e)
		elif pose == "back":
			az = lerpf(az, 0.95 * (-1.0 if side == "l" else 1.0), e)
			ax = lerpf(ax, 0.55, e)
		arm.rotation.x = _spring("ax_" + side, "arm", ax, dt, "arm_x")
		arm.rotation.z = _spring("az_" + side, "arm", az, dt, "arm_z")
		# elbows: relaxed bend, more when the arm is raised; they lag (loose)
		var elev := absf(arm.rotation.z)
		var el := 0.35 + 0.45 * clampf((elev - 0.8) / 1.6, 0.0, 1.0) + 0.25 * absf(ax)
		if pose == "chest":
			el = lerpf(el, 1.0, e)
		_elbow[side] = _spring("el_" + side, "elbow", el, dt, "elbow")
	if character != null:
		character.elbow_cmd = _elbow
		character.elbow_w = 1.0
		# feet: lifted/swinging feet leave the line; stance feet stay pinned
		for side: String in ["l", "r"]:
			var lift: float = tgt[side]
			var sw := maxf(0.0, sin(gait) * (1.0 if side == "l" else -1.0)) * walk
			character.foot_contact[side] = clampf(1.0 - maxf(lift * 1.4, sw * 1.6), 0.0, 1.0)
			character.foot_offset[side] = Vector3(0, 0, -0.13 * cos(gait) * walk * (1.0 if side == "l" else -1.0))
		# hands: grabs reach for the legs; chest bounce: same-side hand to the line
		character.hand_goal["l"] = []
		character.hand_goal["r"] = []
		if gw > 0.0:
			for side: String in ["l", "r"]:
				var hg := _grab_hand(grab, side)
				if not hg.is_empty():
					character.hand_goal[side] = ["bone", hg, gw]
		elif ctx.get("sticky", false) and pose == "butt":
			# sticky bounce: both hands closed on the line in front of the hips
			character.hand_goal["l"] = ["point", Vector3(-0.03, 0.03, -0.14), 1.0]
			character.hand_goal["r"] = ["point", Vector3(0.03, 0.03, -0.30), 1.0]
		elif pose == "chest" and e > 0.3:
			var lp: Vector3 = ctx.get("line_pt", Vector3.ZERO)
			character.hand_goal["l"] = ["point", lp, e * 0.9]
			character.hand_goal["r"] = ["point", lp + Vector3(0.02, 0.0, 0.13), e * 0.9]


var _elbow := {"l": 0.4, "r": 0.4}
## Back bounce hip flexion: torso ~25 deg above horizontal, legs 45 deg above
## horizontal -> hip flexion = 180 - 25 - 45... measured on the rig (see test).
const BACK_HIP := 1.31
const CHEST_DIAGONAL := 0.15   # rad the body lies across the line in a chest bounce


## Leg shape for a grab: Vector3(hip flexion, knee (negative), abduction).
func _grab_leg_shape(grab: String, side: String) -> Vector3:
	match grab:
		"both_knees":
			return Vector3(1.75, -1.7, 0.12)
		"knee":
			return Vector3(1.8, -1.9, 0.1) if side == "r" else Vector3(0.25, -0.2, 0.05)
		"left_knee":
			return Vector3(1.8, -1.9, 0.1) if side == "l" else Vector3(0.25, -0.2, 0.05)
		"leg":
			return Vector3(1.45, -0.15, 0.05) if side == "r" else Vector3(0.1, -0.3, 0.05)
		"cross":
			return Vector3(1.75, -1.85, 0.0) if side == "l" else Vector3(0.3, -0.35, 0.1)
		"tuck":
			return Vector3(TUCK_HIP, -TUCK_KNEE, 0.08)
	return Vector3(0.0, 0.0, 0.0)


## Which part each hand grabs: [bone, fraction toward the next bone].
func _grab_hand(grab: String, side: String) -> Array:
	match grab:
		"both_knees":
			return ["calf_" + side, 0.05]
		"knee":
			return ["calf_r", 0.08] if side == "r" else []
		"left_knee":
			return ["calf_l", 0.08] if side == "l" else []
		"leg":
			return ["calf_r", 0.75] if side == "r" else []
		"cross":
			return ["calf_l", 0.1] if side == "r" else []
		"tuck":
			return ["calf_" + side, 0.35]
	return []


## Keeps the feet above the floor: if a shin tip would go through it, the
## leg swings forward (knee straightens, thigh lifts) until it clears.
func keep_feet_above(floor_y: float) -> void:
	if _thigh_l == null:
		return
	if character != null:
		character.floor_y = floor_y
	for pair in [[_thigh_l, _shin_l], [_thigh_r, _shin_r]]:
		var thigh: Node3D = pair[0]
		var shin: Node3D = pair[1]
		for i in range(24):
			var tip_y := shin.to_global(Vector3(0, -SHIN - 0.06, 0)).y
			if tip_y >= floor_y + 0.02:
				break
			shin.rotation.x = move_toward(shin.rotation.x, 0.0, 0.25)
			# Swing the thigh whichever way lifts the foot (depends on how the
			# whole body is tilted, e.g. blending out of a chest bounce).
			var base := thigh.rotation.x
			thigh.rotation.x = base + 0.15
			var up_y := shin.to_global(Vector3(0, -SHIN - 0.06, 0)).y
			thigh.rotation.x = base - 0.15
			var down_y := shin.to_global(Vector3(0, -SHIN - 0.06, 0)).y
			thigh.rotation.x = base + 0.15 if up_y >= down_y else base - 0.15


## pitch: + = frontflip direction (about local +X). yaw: spin about up.
func set_trick_rotation(pitch: float, yaw: float) -> void:
	if _trick == null:
		return
	# Somersault about the lateral axis through the COM, twist about the
	# body's own long axis (also through the COM).
	_trick.basis = Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.UP, yaw)


func _limb(parent: Node3D, joint_pos: Vector3, radius: float, length: float,
		mat: Material) -> Node3D:
	# Joint node sits at the joint; the mesh hangs down from it.
	var joint := Node3D.new()
	joint.position = joint_pos
	parent.add_child(joint)
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	m.mesh = cap
	m.material_override = mat
	m.position = Vector3(0, -length * 0.5, 0)
	joint.add_child(m)
	return joint


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m
