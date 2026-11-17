"""Step 4: motion reference -> skeletal animation on our athlete rig (Blender,
headless via the bpy module) -> GLB with an animation for Godot.

The capture is side-on (sagittal), so the retarget drives the joints that
matter for a flip: whole-body rotation, hips, knees, shoulders, elbows, ankles.
Height in the air is not taken from the video (handheld cameras pan); it is
rebuilt from the measured flight time as a ballistic arc, h = v0*t - g*t^2/2.

Usage: python3 retarget_blender.py athlete.glb motion.json out.glb
"""
import json, math, sys
import bpy
from mathutils import Matrix, Vector

src, motion_path, out = sys.argv[-3:]
M = json.load(open(motion_path))
fps = M["fps"]
F = M["frames_data"]
n = M["frames"]
take, land = M["phases"]["takeoff"], M["phases"]["landing"]
T = (land - take) / fps
g = 9.81
v0 = g * T / 2

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
scene = bpy.context.scene
scene.render.fps = int(round(fps))
scene.frame_start, scene.frame_end = 0, n - 1

pb = arm.pose.bones
rest = {b.name: b.bone.matrix_local.copy() for b in pb}
# Blender: model faces -Y, X is the athlete's lateral axis, Z up.
X = Vector((1, 0, 0))


def rot_about(point, angle):
    return Matrix.Translation(point) @ Matrix.Rotation(angle, 4, X) @ Matrix.Translation(-point)


pelvis_h = rest["pelvis"].translation.copy()
thigh_len = (rest["calf_l"].translation - rest["thigh_l"].translation).length
shin_len = (rest["foot_l"].translation - rest["calf_l"].translation).length
REST_ELBOW = 45.0   # the model's rest forearm is already flexed ~45 deg

order = [b.name for b in sorted(pb, key=lambda b: len(b.parent_recursive))]
action = bpy.data.actions.new("backflip_mocap")
arm.animation_data_create()
arm.animation_data.action = action

for f in range(n):
    pitch = F["pitch"][f]
    hip = math.radians(F["hip"][f])
    knee = math.radians(F["knee"][f])
    sh = math.radians(F["shoulder"][f])
    el = math.radians(max(0.0, F["elbow"][f] - REST_ELBOW))
    # pelvis height: legs on the ground before takeoff / after landing,
    # ballistic arc in between
    if take <= f <= land:
        tau = (f - take) / fps
        lift = v0 * tau - 0.5 * g * tau * tau
        legs = thigh_len + shin_len
        base = legs * 0.99
    else:
        lift = 0.0
    # standing height from the leg angles (feet planted)
    stand = thigh_len * math.cos(max(0.0, hip - 0.0) * 0.5) + shin_len * math.cos(knee * 0.5)
    drop = (thigh_len + shin_len) - stand if not (take <= f <= land) else 0.0
    delta = {}
    world = Matrix.Translation(Vector((0, 0, lift - drop))) @ rot_about(pelvis_h, pitch)
    for name in order:
        b = pb[name]
        parent = b.parent.name if b.parent else None
        d = delta.get(parent, Matrix.Identity(4)) if parent else Matrix.Identity(4)
        h = rest[name].translation
        local = Matrix.Identity(4)
        if name == "pelvis":
            d = world
        elif name.startswith("thigh"):
            local = rot_about(h, -hip)
        elif name.startswith("calf"):
            local = rot_about(h, knee)
        elif name.startswith("foot"):
            point = 0.35 if take < f < land else 0.0
            local = rot_about(h, point)
        elif name.startswith("upperarm"):
            local = rot_about(h, -sh)
        elif name.startswith("lowerarm"):
            local = rot_about(h, -el)
        d = d @ local
        delta[name] = d
        b.matrix = d @ rest[name]
        bpy.context.view_layer.update()
        b.keyframe_insert("rotation_quaternion", frame=f)
        if name == "pelvis":
            b.keyframe_insert("location", frame=f)

bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True,
                          export_frame_range=True, export_force_sampling=True,
                          export_image_format="WEBP", export_image_quality=85)
print("EXPORTED", out, n, "frames", f"flight {T:.2f}s v0 {v0:.2f}m/s")
