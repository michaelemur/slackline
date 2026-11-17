class_name AthleteCharacter
extends Node3D
## The real athlete (skinned MakeHuman-based model, 53-bone game rig) driven
## procedurally by the existing physics.
##
## Nothing here simulates anything. AthleteVisual still poses its simple joint
## chain (hips, torso, thighs, shins, arms) from the balance, leg and trick
## systems; that chain is now an invisible "pose rig". Every frame this node
## copies it onto the skeleton:
##   - pelvis / spine / arms: rotation deltas of the matching pose-rig joints
##   - legs: two-bone IK; on the line the feet are pinned to the webbing, in
##     the air they follow the pose rig's shins (tuck, layout, landing prep)
##   - elbows, head, toes, fingers: small procedural rules on top
## So body rotation, lean, knee bend and arm counterbalance all come straight
## from the gameplay systems.

const SCENE_PATH := "res://assets/athlete/athlete.glb"

var visual: Node3D            # AthleteVisual (pose rig owner)
var skel: Skeleton3D
var contact: float = 1.0      # 0 = feet free (air/poses), 1 = feet on the line
var contact_target: float = 1.0
var tuck: float = 0.0         # 0..1 from the trick controller
var floor_y: float = -INF     # global ground height (feet never go below)
var stance_gap: float = 0.17  # m between front and back foot along the line
var ref_arm_w: float = 0.0    # motion-capture arm override (0 = off)
# --- per-limb commands from the body dynamics (AthleteVisual.apply_body) ---
var foot_contact := {"l": 1.0, "r": 1.0}            # 1 = foot pinned on the line
var foot_offset := {"l": Vector3.ZERO, "r": Vector3.ZERO}   # visual space, on the line
var elbow_cmd := {"l": -1.0, "r": -1.0}             # rad, <0 = procedural
var elbow_w: float = 0.0
## Hand reaches: side -> [kind, data, weight]. kind "bone": [bone, t along
## it to the next bone, side offset]; kind "point": visual-space point.
var hand_goal := {"l": [], "r": []}
var ref_shoulder: float = 0.0 # rad, arm forward/up from hanging
var ref_elbow: float = 0.0    # rad

var _idx := {}                # bone name -> index
var _order: Array[int] = []   # parents before children
var _rest_v: Array[Transform3D] = []   # bone global rest in visual space
var _rest_local: Array[Transform3D] = []
var _S: Transform3D           # skeleton space -> visual space
var _Sinv: Transform3D
var _map := {}                # bone -> [proxy node, P_ref^-1 * rest]
var _len := {}                # leg segment lengths
var _ok := false
var last_pose: Array = []     # bone global transforms (visual space) of the last solve
## Body segments for the centre of mass (de Leva 1996, adult male mass
## fractions): [bone, end bone ("" = along the bone's own axis), fraction].
const SEGMENTS := [
	["pelvis", "spine_01", 0.1117], ["spine_01", "spine_03", 0.1633], ["spine_03", "neck_01", 0.1596],
	["neck_01", "", 0.0694],
	["upperarm_l", "lowerarm_l", 0.0271], ["lowerarm_l", "hand_l", 0.0162], ["hand_l", "", 0.0061],
	["upperarm_r", "lowerarm_r", 0.0271], ["lowerarm_r", "hand_r", 0.0162], ["hand_r", "", 0.0061],
	["thigh_l", "calf_l", 0.1416], ["calf_l", "foot_l", 0.0433], ["foot_l", "ball_l", 0.0137],
	["thigh_r", "calf_r", 0.1416], ["calf_r", "foot_r", 0.0433], ["foot_r", "ball_r", 0.0137],
]
var com: Vector3 = Vector3.ZERO     # visual space, from the solved skeleton
var air_shift: float = 0.0           # 0 on the line .. 1 in the air
var _seg_ext := {}                   # bone -> local end offset for "" segments


func setup(pose_rig: Node3D, ref_nodes: Dictionary) -> bool:
	visual = pose_rig
	if not ResourceLoader.exists(SCENE_PATH):
		return false
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		return false
	var inst := scene.instantiate()
	add_child(inst)
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return false
	skel = found[0]
	# The model faces +Z (glTF); the athlete faces -Z.
	basis = Basis(Vector3.UP, PI)
	for i in skel.get_bone_count():
		_idx[skel.get_bone_name(i)] = i
	for bn: String in ["pelvis", "spine_03", "upperarm_l", "upperarm_r", "thigh_l", "calf_l", "foot_l"]:
		if not _idx.has(bn):
			return false
	_order = _sorted_bones()
	_S = _xform_to_visual(skel)
	_Sinv = _S.affine_inverse()
	_rest_v.resize(skel.get_bone_count())
	_rest_local.resize(skel.get_bone_count())
	for i in skel.get_bone_count():
		_rest_v[i] = _S * skel.get_bone_global_rest(i)
		_rest_local[i] = skel.get_bone_rest(i)
	for side: String in ["l", "r"]:
		var h := _rest_v[_idx["thigh_" + side]].origin
		var k := _rest_v[_idx["calf_" + side]].origin
		var a := _rest_v[_idx["foot_" + side]].origin
		_len[side] = Vector2(h.distance_to(k), k.distance_to(a))
	# Map pose-rig joints (captured in the reference pose) onto bones.
	for bn: String in ref_nodes:
		var node: Node3D = ref_nodes[bn][0]
		var ref: Transform3D = ref_nodes[bn][1]
		if _idx.has(bn):
			_map[bn] = [node, ref.affine_inverse() * _rest_v[_idx[bn]]]
	_seg_ext = {"neck_01": Vector3(0, 0.22, 0), "hand_l": Vector3(0, 0.09, 0), "hand_r": Vector3(0, 0.09, 0)}
	_ok = true
	return true


## Centre of mass = sum(m_i * p_i) / sum(m_i) over the body segments, each
## at the midpoint of its bone (visual space).
func compute_com(glob: Array) -> Vector3:
	var acc := Vector3.ZERO
	var tot := 0.0
	for sg: Array in SEGMENTS:
		var bi: int = _idx.get(sg[0], -1)
		if bi < 0:
			continue
		var a: Transform3D = glob[bi]
		var e: Vector3
		if sg[1] != "" and _idx.has(sg[1]):
			e = (glob[_idx[sg[1]]] as Transform3D).origin
		else:
			e = a * (_seg_ext.get(sg[0], Vector3(0, 0.1, 0)) as Vector3)
		acc += (a.origin + e) * 0.5 * float(sg[2])
		tot += float(sg[2])
	return acc / maxf(tot, 1e-6)


## Upper-arm angle from hanging (rad) in the model's rest pose, so the pose
## rig can be put in the same reference pose.
static func rest_arm_angle() -> float:
	return 0.85


func _sorted_bones() -> Array[int]:
	var out: Array[int] = []
	var depth := {}
	for i in skel.get_bone_count():
		var d := 0
		var p := skel.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = skel.get_bone_parent(p)
		depth[i] = d
	var ids := range(skel.get_bone_count())
	ids.sort_custom(func(a, b): return depth[a] < depth[b])
	for i in ids:
		out.append(i)
	return out


func _xform_to_visual(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != visual:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func _vis(n: Node3D) -> Transform3D:
	return _xform_to_visual(n)


## Called by the visual at the end of each physics tick (same tick as the
## body, so the skeleton and the COM never lag the physics).
func update(dt: float) -> void:
	if not _ok or not is_visible_in_tree():
		return
	contact = move_toward(contact, contact_target, dt * 6.0)
	solve()
	# In the air the body turns about its real centre of mass: shift the
	# skeleton so the computed COM sits on the flight's rotation centre.
	var pivot := Vector3(0, visual.COM_HEIGHT, 0)
	var want_shift := (pivot - com) * air_shift
	position = want_shift


## Builds the pose for this frame.
func solve() -> void:
	var n := skel.get_bone_count()
	var want: Array = []            # desired global (visual space) or null
	want.resize(n)
	# 1) mapped bones from the pose rig
	for bn: String in _map:
		var m: Array = _map[bn]
		want[_idx[bn]] = _vis(m[0]) * (m[1] as Transform3D)
	var pelvis: Transform3D = want[_idx["pelvis"]]
	var up_rel := Quaternion(pelvis.basis.get_rotation_quaternion())
	# spine: share the upper-body rotation over three vertebrae
	if want[_idx["spine_03"]] != null:
		var q0 := (pelvis.basis * _rest_v[_idx["pelvis"]].basis.inverse()).get_rotation_quaternion()
		var q3 := ((want[_idx["spine_03"]] as Transform3D).basis * _rest_v[_idx["spine_03"]].basis.inverse()).get_rotation_quaternion()
		for k: int in [1, 2]:
			var bn := "spine_0%d" % k
			if _idx.has(bn):
				var q := q0.slerp(q3, k / 3.0)
				want[_idx[bn]] = Transform3D(Basis(q) * _rest_v[_idx[bn]].basis, Vector3.ZERO)
		# neck and head: follow the chest, chin tucks in when tucking, and the
		# head partly rights itself against body roll (vestibular reflex)
		var qn := q3
		var fwd_axis := (Basis(q3) * Vector3.FORWARD).normalized()
		var roll := _roll_about(Basis(q3), fwd_axis)
		var right := (Basis(q3) * Vector3.RIGHT).normalized()
		var head_q := Quaternion(fwd_axis, -roll * 0.5 * contact) * Quaternion(right, -0.45 * tuck) * qn
		for bn: String in ["neck_01", "head"]:
			if _idx.has(bn):
				want[_idx[bn]] = Transform3D(Basis(head_q) * _rest_v[_idx[bn]].basis, Vector3.ZERO)
		for side: String in ["l", "r"]:
			var cb := "clavicle_" + side
			if _idx.has(cb):
				var arm_t = want[_idx["upperarm_" + side]]
				var lift := 0.0
				if arm_t != null:
					var d: Vector3 = (arm_t as Transform3D).basis.y.normalized()
					lift = clampf((d.y + 0.2) * 0.35, 0.0, 0.4)
				var axis := (Basis(q3) * Vector3.FORWARD).normalized() * (1.0 if side == "r" else -1.0)
				want[_idx[cb]] = Transform3D(Basis(Quaternion(axis, -lift) * q3) * _rest_v[_idx[cb]].basis, Vector3.ZERO)
	# 2) legs: two-bone IK
	_solve_legs(want)
	# 3) arms: elbows bend more when the arms are up; in a tuck the hands
	# reach for the shins (two-bone arm IK onto the solved legs)
	for side: String in ["l", "r"]:
		_solve_arm(side, want)
	_hand_goals(want)
	# 4) write local poses (rotation for all, position only for pelvis/root)
	_apply(want)


## Forward kinematics of the current wish list (same rules as _apply), to
## know where joints are before writing the pose.
func _fk(want: Array) -> Array:
	var glob: Array = []
	glob.resize(skel.get_bone_count())
	for i in _order:
		var p := skel.get_bone_parent(i)
		var parent_g: Transform3D = _S if p < 0 else glob[p]
		var rl: Transform3D = _rest_local[i]
		if want[i] == null:
			glob[i] = parent_g * rl
		else:
			var w: Transform3D = want[i]
			var origin := (parent_g * rl).origin
			if skel.get_bone_name(i) == "pelvis":
				origin = w.origin
			glob[i] = Transform3D(w.basis.orthonormalized(), origin)
	return glob


## Hands reaching for a body part (grabs) or a point (the line).
func _hand_goals(want: Array) -> void:
	var g: Array = []
	for side: String in ["l", "r"]:
		var goal: Array = hand_goal[side]
		if goal.is_empty() or float(goal[2]) <= 0.01:
			continue
		if g.is_empty():
			g = _fk(want)
		var T: Vector3
		if goal[0] == "bone":
			var d: Array = goal[1]
			var b0: int = _idx[d[0]]
			var p0: Vector3 = (g[b0] as Transform3D).origin
			var nxt := {"thigh_l": "calf_l", "thigh_r": "calf_r", "calf_l": "foot_l", "calf_r": "foot_r",
				"foot_l": "ball_l", "foot_r": "ball_r"}
			var p1: Vector3 = (g[_idx[nxt[d[0]]]] as Transform3D).origin
			T = p0.lerp(p1, float(d[1]))
			# grip on the outside/front of the limb, not inside it
			var fwd := ((g[_idx["pelvis"]] as Transform3D).basis * _rest_v[_idx["pelvis"]].basis.inverse() * Vector3.FORWARD).normalized()
			T += fwd * 0.05
		else:
			T = goal[1]
		_reach(side, T, float(goal[2]), want, g)


func _reach(side: String, T: Vector3, w: float, want: Array, g: Array) -> void:
	var ua: int = _idx["upperarm_" + side]
	var la: int = _idx["lowerarm_" + side]
	var hb: int = _idx["hand_" + side]
	var S: Vector3 = (g[ua] as Transform3D).origin
	var a := _rest_v[ua].origin.distance_to(_rest_v[la].origin)
	var b := _rest_v[la].origin.distance_to(_rest_v[hb].origin)
	var dv := T - S
	var d := clampf(dv.length(), absf(a - b) + 0.01, a + b - 0.002)
	var u := dv.normalized()
	var chest_q := (g[_idx["spine_03"]] as Transform3D).basis * _rest_v[_idx["spine_03"]].basis.inverse()
	var side_out := (chest_q * Vector3.RIGHT).normalized() * (-1.0 if side == "l" else 1.0)
	var pole := side_out - u * side_out.dot(u)
	pole = pole.normalized() if pole.length() > 1e-4 else Vector3.UP
	var ca_ := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var E := S + u * (a * ca_) + pole * (a * sqrt(1.0 - ca_ * ca_))
	var H := S + u * d
	var rest_pole := Vector3.RIGHT * (-1.0 if side == "l" else 1.0)
	var up_b := _aim(_rest_v[ua].basis, (_rest_v[la].origin - _rest_v[ua].origin).normalized(), rest_pole, (E - S).normalized(), pole)
	var lo_b := _aim(_rest_v[la].basis, (_rest_v[hb].origin - _rest_v[la].origin).normalized(), rest_pole, (H - E).normalized(), pole)
	var cur_u: Transform3D = want[ua]
	var cur_l: Transform3D = want[la] if want[la] != null else Transform3D(_rest_v[la].basis, Vector3.ZERO)
	var qu := cur_u.basis.get_rotation_quaternion().slerp(up_b.get_rotation_quaternion(), w)
	var ql := cur_l.basis.get_rotation_quaternion().slerp(lo_b.get_rotation_quaternion(), w)
	want[ua] = Transform3D(Basis(qu), cur_u.origin)
	want[la] = Transform3D(Basis(ql), Vector3.ZERO)
	var fq := (Basis(ql) * _rest_v[la].basis.inverse()).get_rotation_quaternion()
	want[hb] = Transform3D(Basis(fq) * _rest_v[hb].basis, Vector3.ZERO)
	for f: String in ["index", "middle", "ring", "pinky"]:
		var prev := fq
		for j: int in [1, 2, 3]:
			var bi: int = _idx.get("%s_0%d_%s" % [f, j, side], -1)
			if bi < 0:
				continue
			var c_axis := (Basis(fq) * _rest_v[hb].basis.x).normalized()
			var q := Quaternion(c_axis, 1.0 * w * (1.0 if side == "l" else -1.0)) * prev
			want[bi] = Transform3D(Basis(q) * _rest_v[bi].basis, Vector3.ZERO)
			prev = q


func _hands_to_shins(want: Array) -> void:
	var g := _fk(want)
	var w := clampf((tuck - 0.05) / 0.5, 0.0, 1.0)
	for side: String in ["l", "r"]:
		var ua: int = _idx["upperarm_" + side]
		var la: int = _idx["lowerarm_" + side]
		var ca: int = _idx["calf_" + side]
		var fo: int = _idx["foot_" + side]
		var S: Vector3 = (g[ua] as Transform3D).origin
		var knee: Vector3 = (g[ca] as Transform3D).origin
		var ankle: Vector3 = (g[fo] as Transform3D).origin
		# grip on the front of the shin, a third of the way down
		var shin_dir := (ankle - knee).normalized()
		var thigh_dir := (knee - (g[_idx["thigh_" + side]] as Transform3D).origin).normalized()
		var front := (thigh_dir - shin_dir * thigh_dir.dot(shin_dir)).normalized()
		var T := knee + (ankle - knee) * 0.35 + front * 0.05
		var a := _rest_v[ua].origin.distance_to(_rest_v[la].origin)
		var b := _rest_v[la].origin.distance_to(_rest_v[_idx["hand_" + side]].origin)
		var dv := T - S
		var d := clampf(dv.length(), absf(a - b) + 0.01, a + b - 0.002)
		var u := dv.normalized()
		# elbow points out to the side and back
		var side_out := ((g[_idx["spine_03"]] as Transform3D).basis * _rest_v[_idx["spine_03"]].basis.inverse() * Vector3.RIGHT).normalized()
		side_out *= (-1.0 if side == "l" else 1.0)
		var pole := side_out - u * side_out.dot(u)
		pole = pole.normalized() if pole.length() > 1e-4 else Vector3.UP
		var ca_ := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
		var E := S + u * (a * ca_) + pole * (a * sqrt(1.0 - ca_ * ca_))
		var H := S + u * d
		var rest_pole := (_rest_v[_idx["spine_03"]].basis * _rest_v[_idx["spine_03"]].basis.inverse() * Vector3.RIGHT) * (-1.0 if side == "l" else 1.0)
		var up_b := _aim(_rest_v[ua].basis, (_rest_v[la].origin - _rest_v[ua].origin).normalized(), rest_pole, (E - S).normalized(), pole)
		var lo_b := _aim(_rest_v[la].basis, (_rest_v[_idx["hand_" + side]].origin - _rest_v[la].origin).normalized(), rest_pole, (H - E).normalized(), pole)
		var cur_u: Transform3D = want[ua]
		var cur_l: Transform3D = want[la] if want[la] != null else Transform3D(_rest_v[la].basis, Vector3.ZERO)
		var qu := cur_u.basis.get_rotation_quaternion().slerp(up_b.get_rotation_quaternion(), w)
		var ql := cur_l.basis.get_rotation_quaternion().slerp(lo_b.get_rotation_quaternion(), w)
		want[ua] = Transform3D(Basis(qu), cur_u.origin)
		want[la] = Transform3D(Basis(ql), Vector3.ZERO)
		var h: int = _idx["hand_" + side]
		var fq := (Basis(ql) * _rest_v[la].basis.inverse()).get_rotation_quaternion()
		want[h] = Transform3D(Basis(fq) * _rest_v[h].basis, Vector3.ZERO)
		# fingers wrap around the shin
		for f: String in ["index", "middle", "ring", "pinky"]:
			var prev := fq
			for j: int in [1, 2, 3]:
				var bi: int = _idx.get("%s_0%d_%s" % [f, j, side], -1)
				if bi < 0:
					continue
				var c_axis := (Basis(fq) * _rest_v[h].basis.x).normalized()
				var q := Quaternion(c_axis, 1.1 * w * (1.0 if side == "l" else -1.0)) * prev
				want[bi] = Transform3D(Basis(q) * _rest_v[bi].basis, Vector3.ZERO)
				prev = q


func _roll_about(b: Basis, axis: Vector3) -> float:
	# How far the body's up axis is rolled about 'axis' from world up.
	var upv := b.y
	var flat := (upv - axis * upv.dot(axis))
	var ref := (Vector3.UP - axis * Vector3.UP.dot(axis))
	if flat.length() < 1e-4 or ref.length() < 1e-4:
		return 0.0
	return ref.normalized().signed_angle_to(flat.normalized(), axis)


func _solve_arm(side: String, want: Array) -> void:
	var ua: int = _idx.get("upperarm_" + side, -1)
	var la: int = _idx.get("lowerarm_" + side, -1)
	if ua < 0 or la < 0 or want[ua] == null:
		return
	var U: Transform3D = want[ua]
	if ref_arm_w > 0.0 and want[_idx["spine_03"]] != null:
		# captured arm swing: forward flexion about the chest's side axis
		var chest: Transform3D = want[_idx["spine_03"]]
		var cq := (chest.basis * _rest_v[_idx["spine_03"]].basis.inverse()).get_rotation_quaternion()
		var side_axis := (Basis(cq) * Vector3.RIGHT).normalized()
		var hang := Basis(cq) * _rest_v[ua].basis
		var swung := Basis(Quaternion(side_axis, ref_shoulder)) * hang
		var mixed := U.basis.get_rotation_quaternion().slerp(swung.get_rotation_quaternion(), ref_arm_w)
		U = Transform3D(Basis(mixed), U.origin)
		want[ua] = U
	var dq := (U.basis * _rest_v[ua].basis.inverse()).get_rotation_quaternion()
	# rest forearm, carried by the upper arm
	var rest_fore := Basis(dq) * _rest_v[la].basis
	var arm_dir := U.basis.y.normalized()
	var raise := clampf(arm_dir.y + 0.6, 0.0, 1.4)          # 0 hanging .. up
	# The model's rest forearm is already ~45 deg flexed; aim for a relaxed
	# 25 deg when hanging, ~70 deg with the arms up, ~110 deg in a tuck.
	var target := lerpf(0.45, 1.2, clampf(raise / 1.2, 0.0, 1.0))
	target = lerpf(target, 1.9, tuck)
	target = lerpf(target, ref_elbow, ref_arm_w)
	if float(elbow_cmd[side]) >= 0.0:
		target = lerpf(target, float(elbow_cmd[side]), elbow_w)
	var rest_bend := _rest_v[ua].basis.y.normalized().angle_to(_rest_v[la].basis.y.normalized())
	var fwd := (Basis(dq) * _rest_v[la].basis.y).normalized()
	var axis := arm_dir.cross(fwd)
	if axis.length() < 1e-4:
		axis = U.basis.x
	axis = axis.normalized()
	var extra := target - rest_bend
	var fore := Basis(Quaternion(axis, extra)) * rest_fore
	want[la] = Transform3D(fore, Vector3.ZERO)
	var h: int = _idx.get("hand_" + side, -1)
	if h >= 0:
		var fq := (fore * _rest_v[la].basis.inverse()).get_rotation_quaternion()
		want[h] = Transform3D(Basis(fq) * _rest_v[h].basis, Vector3.ZERO)
		# relaxed fingers: curl each finger joint toward the palm
		var curl := lerpf(0.25, 0.9, tuck)
		for f: String in ["index", "middle", "ring", "pinky"]:
			var prev := fq
			for j: int in [1, 2, 3]:
				var bn := "%s_0%d_%s" % [f, j, side]
				var bi: int = _idx.get(bn, -1)
				if bi < 0:
					continue
				var rb := Basis(prev) * _rest_v[bi].basis
				var c_axis := (Basis(fq) * _rest_v[h].basis.x).normalized()
				var q := Quaternion(c_axis, curl * (1.0 if side == "l" else -1.0)) * prev
				want[bi] = Transform3D(Basis(q) * _rest_v[bi].basis, Vector3.ZERO)
				prev = q


func _solve_legs(want: Array) -> void:
	var pel: Transform3D = want[_idx["pelvis"]]
	var pel_delta := pel * _rest_v[_idx["pelvis"]].affine_inverse()
	var fwd := (pel.basis * _rest_v[_idx["pelvis"]].basis.inverse() * Vector3.FORWARD)
	fwd.y = 0.0
	if fwd.length() < 1e-3:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var targets := {}
	var hips := {}
	var deficit := 0.0
	for side: String in ["l", "r"]:
		var thigh: int = _idx["thigh_" + side]
		var hip := pel_delta * _rest_v[thigh].origin
		hips[side] = hip
		# free target: the pose rig's foot (shin tip), plus the ankle height
		var shin: Node3D = visual.get_shin(side)
		var ank_h := _rest_v[_idx["foot_" + side]].origin.y
		var free := _vis(shin) * Vector3(0, -visual.SHIN + ank_h, 0)
		# line target: both feet on the webbing, one ahead of the other
		var ahead := -1.0 if side == "l" else 1.0
		var line := Vector3(0.012 * (-1.0 if side == "l" else 1.0), ank_h, ahead * stance_gap * 0.5 + 0.045)
		var c_side: float = contact * float(foot_contact[side])
		line += foot_offset[side] as Vector3
		var t := free.lerp(line, c_side)
		if floor_y > -INF:
			t.y = maxf(t.y, _floor_local() + ank_h * 0.9)
		targets[side] = t
		var reach: float = _len[side].x + _len[side].y - 0.005
		if c_side > 0.5:
			deficit = maxf(deficit, hip.distance_to(t) - reach)
	# On the line, sink the hips if the legs can't reach (pins the feet).
	var sink := maxf(deficit, 0.0) * contact
	if sink > 0.0:
		pel.origin.y -= sink
		want[_idx["pelvis"]] = pel
		for side: String in ["l", "r"]:
			hips[side] = hips[side] - Vector3(0, sink, 0)
	for side: String in ["l", "r"]:
		var shin_node: Node3D = visual.get_shin(side)
		var knee_hint := _vis(shin_node).origin
		_two_bone(side, hips[side], targets[side], knee_hint, fwd, want)


func _floor_local() -> float:
	# floor height expressed in visual space (visual may be rotated in a flip;
	# only the vertical matters for the feet)
	var gp := visual.global_position
	return visual.to_local(Vector3(gp.x, floor_y, gp.z)).y


func _two_bone(side: String, H: Vector3, T: Vector3, knee_hint: Vector3, fwd: Vector3, want: Array) -> void:
	var th: int = _idx["thigh_" + side]
	var ca: int = _idx["calf_" + side]
	var fo: int = _idx["foot_" + side]
	var a: float = _len[side].x
	var b: float = _len[side].y
	var dv := T - H
	var d := clampf(dv.length(), absf(a - b) + 0.01, a + b - 0.001)
	var u := dv.normalized() if dv.length() > 1e-5 else Vector3.DOWN
	# pole: where the pose rig's knee is (bends forward); fall back to facing
	var mid := H + u * (a * 0.5)
	var pole := knee_hint - mid
	pole = pole - u * pole.dot(u)
	var pf := fwd - u * fwd.dot(u)
	if pole.length() < 0.02:
		pole = pf
	else:
		pole = pole.normalized().lerp(pf.normalized(), 0.35 * contact)
	if pole.length() < 1e-4:
		pole = Vector3.FORWARD
	pole = pole.normalized()
	# toes out a little on the back foot
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var K := H + u * (a * cos_a) + pole * (a * sqrt(1.0 - cos_a * cos_a))
	var Tc := H + u * d
	var rest_fwd := Vector3.FORWARD
	want[th] = Transform3D(_aim(_rest_v[th].basis, (_rest_v[ca].origin - _rest_v[th].origin).normalized(), rest_fwd,
		(K - H).normalized(), pole), H)
	want[ca] = Transform3D(_aim(_rest_v[ca].basis, (_rest_v[fo].origin - _rest_v[ca].origin).normalized(), rest_fwd,
		(Tc - K).normalized(), pole), K)
	# foot: flat on the line (front foot straight, back foot turned out),
	# pointed toes in the air (follows the shin)
	var yaw := 0.0 if side == "l" else 0.35
	var flat := Basis(Vector3.UP, yaw) * _rest_v[fo].basis
	var calf_q := ((want[ca] as Transform3D).basis * _rest_v[ca].basis.inverse()).get_rotation_quaternion()
	var shin_axis := ((want[ca] as Transform3D).basis * _rest_v[ca].basis.inverse() * Vector3.RIGHT).normalized()
	var pointed := Basis(Quaternion(shin_axis, 0.55) * calf_q) * _rest_v[fo].basis
	var fq := pointed.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(), contact * float(foot_contact[side]))
	want[fo] = Transform3D(Basis(fq), Tc)
	var ball: int = _idx.get("ball_" + side, -1)
	if ball >= 0:
		var dq := (Basis(fq) * _rest_v[fo].basis.inverse()).get_rotation_quaternion()
		want[ball] = Transform3D(Basis(dq) * _rest_v[ball].basis, Vector3.ZERO)


## Rotation that turns a bone so its rest direction d0 (with rest pole p0)
## points along d1 (with pole p1), applied to its rest basis.
func _aim(rest: Basis, d0: Vector3, p0: Vector3, d1: Vector3, p1: Vector3) -> Basis:
	var f0 := _frame(d0, p0)
	var f1 := _frame(d1, p1)
	return (f1 * f0.transposed()) * rest


func _frame(d: Vector3, p: Vector3) -> Basis:
	var y := d.normalized()
	var x := (p - y * p.dot(y))
	if x.length() < 1e-5:
		x = y.cross(Vector3.RIGHT)
		if x.length() < 1e-5:
			x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _apply(want: Array) -> void:
	var glob: Array = []
	glob.resize(skel.get_bone_count())
	for i in _order:
		var p := skel.get_bone_parent(i)
		var parent_g: Transform3D = _S if p < 0 else glob[p]
		var rl: Transform3D = _rest_local[i]
		var g: Transform3D
		if want[i] == null:
			g = parent_g * rl
		else:
			var w: Transform3D = want[i]
			var origin := (parent_g * rl).origin
			var bn := skel.get_bone_name(i)
			if bn == "pelvis" or bn.begins_with("thigh") or bn.begins_with("calf") or bn.begins_with("foot"):
				origin = w.origin if bn == "pelvis" else origin
			g = Transform3D(w.basis.orthonormalized(), origin)
		glob[i] = g
		var local := parent_g.affine_inverse() * g
		skel.set_bone_pose_position(i, local.origin)
		skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	last_pose = glob
	com = compute_com(glob)
