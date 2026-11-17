extends TestCase
## Skinned athlete: loads, maps onto the pose rig, feet pinned on the line,
## skeleton follows flips. Runs headless (no rendering needed).


func _make() -> AthleteVisual:
	# Built outside the tree (the runner works before the tree is ready);
	# everything the character needs is local to the visual.
	var v := AthleteVisual.new()
	v._ready()
	return v


func _bone_pos(v: AthleteVisual, bn: String) -> Vector3:
	var sk := v.character.skel
	var i := sk.find_bone(bn)
	return (v.character.last_pose[i] as Transform3D).origin


func test_character_loads_and_hides_capsules() -> void:
	var v := _make()
	check(v.character != null, "athlete model loaded and mapped")
	check(v.character.skel.get_bone_count() == 53, "53-bone rig")
	v.set_use_character(false)
	check(not v.character.visible, "V toggles back to capsules")
	v.free()


func test_feet_pinned_on_line_when_standing_and_crouched() -> void:
	var v := _make()
	for crouch in [0.0, 0.6]:
		v.set_body(0.05, crouch, 0.8, 0.8, 0.0, 1.0)
		v.set_character_state(true, 0.0)
		v.character.contact = 1.0
		v.character.solve()
		for side in ["l", "r"]:
			var p := _bone_pos(v, "foot_" + side)
			check(absf(p.x) < 0.03 and p.y < 0.13, "%s ankle over the line at crouch %.1f (%s)" % [side, crouch, p])
	v.free()


func test_skeleton_follows_flip_rotation() -> void:
	var v := _make()
	v.set_character_state(false, 1.0)
	v.character.contact = 0.0
	v.set_trick_rotation(PI, 0.0)
	v.set_body(0.0, 0.8, 0.9, 0.9, 0.0, 1.0)
	v.character.solve()
	var head := _bone_pos(v, "head")
	var pel := _bone_pos(v, "pelvis")
	check(head.y < pel.y, "upside down at half a flip (head %.2f below pelvis %.2f)" % [head.y, pel.y])
	v.free()
