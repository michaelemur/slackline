"""Builds the female athlete from the male athlete GLB (same 53-bone rig, so
every gameplay system, IK target and contact works unchanged).

Changes (not a colour swap):
  * body shape sculpted on the skinned mesh: narrower shoulders and waist,
    wider hips and thighs, a chest, slimmer arms and neck, 4 % shorter overall;
  * the skeleton is rebuilt at the new proportions (bones follow the mesh);
  * hair: a hair cap and a ponytail, skinned to the head bone;
  * her own outfit texture: coral sports top, teal leggings, darker hair.

Run headless:  python3 -I tools/female/make_female.py <male.glb> <out.glb>
(-I avoids a glog double-init crash of the bpy module in this environment)
"""
import math
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector

src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
body = bpy.data.objects["AthleteBody"]
FRONT = Vector((0, -1, 0))   # the athlete faces -Y in Blender here


def bone_head(name):
    return arm.matrix_world @ arm.data.bones[name].head_local


def group_weights(obj, names):
    idx = {obj.vertex_groups[n].index for n in names if n in obj.vertex_groups}
    w = np.zeros(len(obj.data.vertices))
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in idx:
                w[v.index] += g.weight
    return np.clip(w, 0, 1)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


me = body.data
co = np.array([v.co[:] for v in me.vertices])
nrm = np.array([v.normal[:] for v in me.vertices])
x, y, z = co[:, 0].copy(), co[:, 1].copy(), co[:, 2].copy()

pelvis = bone_head("pelvis")
chest = bone_head("spine_03")
neck = bone_head("neck_01")
w_hip = group_weights(body, ["pelvis", "thigh_l", "thigh_r"])
w_waist = group_weights(body, ["spine_01", "spine_02"])
w_chest = group_weights(body, ["spine_03"])
w_shoulder = group_weights(body, ["clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r"])
w_arm = group_weights(body, ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"])
w_neck = group_weights(body, ["neck_01"])
w_thigh = group_weights(body, ["thigh_l", "thigh_r"])

# hips and upper thighs wider (around the hip line)
hip_band = smooth(z, pelvis.z - 0.35, pelvis.z - 0.12) * (1 - smooth(z, pelvis.z + 0.08, pelvis.z + 0.2))
x *= 1 + 0.11 * w_hip * hip_band
y = pelvis.y + (y - pelvis.y) * (1 + 0.06 * w_hip * hip_band)
# waist narrower
x *= 1 - 0.10 * w_waist
y = pelvis.y + (y - pelvis.y) * (1 - 0.06 * w_waist)
# shoulders in, arms and neck slimmer (about their own centre lines)
side = np.sign(x)
x -= side * 0.028 * w_shoulder
x -= side * 0.012 * w_arm
x *= 1 - 0.10 * w_neck
y = neck.y + (y - neck.y) * (1 - 0.10 * w_neck)
# thighs a little fuller
x *= 1 + 0.03 * w_thigh * (1 - hip_band)
# chest: two smooth bumps on the front of the upper torso
for sx in (-1.0, 1.0):
    c = np.array([sx * 0.085, chest.y - 0.09, chest.z + 0.08])
    d2 = ((co[:, 0] - c[0]) ** 2) / 0.07 ** 2 + ((co[:, 2] - c[2]) ** 2) / 0.065 ** 2
    facing = np.clip((nrm @ np.array(FRONT[:])) * 1.4, 0, 1)
    bump = 0.045 * np.exp(-d2) * facing * np.clip(w_chest * 2.0, 0, 1)
    y -= bump          # forward = -Y
    z -= bump * 0.25   # natural slight droop

co2 = np.stack([x, y, z], axis=1)
for v, p in zip(me.vertices, co2):
    v.co = Vector(p)
me.update()

# ---- rebuild the skeleton at the new proportions --------------------------
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
for b in eb:
    for attr in ("head", "tail"):
        p = getattr(b, attr)
        sx = 1.0
        if b.name.startswith(("clavicle", "upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky")):
            sx = None
        if b.name.startswith(("thigh",)) and attr == "head":
            p.x *= 1.09
        if sx is None and abs(p.x) > 0.02:
            p.x -= math.copysign(0.028 if b.name.startswith("clavicle") and attr == "head" else 0.034, p.x)
bpy.ops.object.mode_set(mode="OBJECT")

# ---- hair: cap + ponytail, skinned to the head ----------------------------
head = bone_head("head")
head_top = arm.matrix_world @ arm.data.bones["head"].tail_local
hair_mat = bpy.data.materials.new("HairMat")
hair_mat.use_nodes = True
bsdf = hair_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.11, 0.055, 0.03, 1)
bsdf.inputs["Roughness"].default_value = 0.55

hv = [body.matrix_world @ v.co for v, wv in zip(me.vertices, group_weights(body, ["head"])) if wv > 0.6]
hv = np.array([p[:] for p in hv])
hc = hv.mean(axis=0)
r_head = np.percentile(np.linalg.norm(hv[:, [0, 1]] - hc[[0, 1]], axis=1), 92)
top = hv[:, 2].max()


def make_obj(name, bm):
    m = bpy.data.meshes.new(name)
    bm.to_mesh(m)
    bm.free()
    o = bpy.data.objects.new(name, m)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(hair_mat)
    o.parent = arm
    vg = o.vertex_groups.new(name="head")
    vg.add(list(range(len(m.vertices))), 1.0, "REPLACE")
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for poly in m.polygons:
        poly.use_smooth = True
    return o

# cap: upper back part of a slightly larger sphere, cut above the forehead
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
keep = []
for v in bm.verts:
    p = v.co
    front_cut = (-p.y) > 0.35 and p.z < 0.55   # leave the face free
    if p.z < -0.15 or front_cut:
        keep.append(v)
bmesh.ops.delete(bm, geom=keep, context="VERTS")
for v in bm.verts:
    v.co = Vector((hc[0] + v.co.x * r_head * 1.10, hc[1] + v.co.y * r_head * 1.12 + 0.008,
                   (top - r_head * 0.95) + v.co.z * r_head * 1.08))
cap = make_obj("HairCap", bm)

# ponytail: a tapered tube from the back of the head, hanging down
bm = bmesh.new()
start = Vector((hc[0], hc[1] + r_head * 0.95, top - r_head * 0.55))
pts = [start + Vector((0, 0.05 * t + 0.03 * t * t, -0.26 * t)) for t in np.linspace(0, 1, 9)]
rings = []
for k, p in enumerate(pts):
    rad = 0.045 * (1 - 0.7 * k / (len(pts) - 1)) + 0.006
    ring = [bm.verts.new(p + Vector((math.cos(a) * rad, math.sin(a) * rad * 0.8, 0)))
            for a in np.linspace(0, 2 * math.pi, 10, endpoint=False)]
    rings.append(ring)
for r0, r1 in zip(rings, rings[1:]):
    for i in range(10):
        bm.faces.new((r0[i], r0[(i + 1) % 10], r1[(i + 1) % 10], r1[i]))
tip = bm.verts.new(pts[-1] + Vector((0, 0.01, -0.03)))
for i in range(10):
    bm.faces.new((rings[-1][i], rings[-1][(i + 1) % 10], tip))
bm.normal_update()
tail = make_obj("Ponytail", bm)
# hair tie
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.05, radius2=0.05, depth=0.03)
for v in bm.verts:
    v.co = start + Vector((v.co.x, v.co.y * 0.8, v.co.z))
tie = make_obj("HairTie", bm)
tie_mat = bpy.data.materials.new("HairTieMat")
tie_mat.use_nodes = True
tie_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.6, 0.6, 1)
tie.data.materials[0] = tie_mat

# ---- her own outfit texture ------------------------------------------------
mat = body.material_slots[0].material
img_node = next(n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image and "albedo" in n.image.name.lower())
img = img_node.image
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
rgb = px[:, :, :3]
mx, mn = rgb.max(axis=2), rgb.min(axis=2)
sat = (mx - mn) / np.maximum(mx, 1e-4)
yy = (np.arange(H)[:, None] / H) * np.ones((1, W))   # 0 = bottom row in Blender
xx = np.ones((H, 1)) * (np.arange(W)[None, :] / W)
# shirt: bright, unsaturated, in the upper-left torso island
shirt = (mx > 0.62) & (sat < 0.12) & (xx < 0.62) & (yy > 0.45)
shade = (rgb.mean(axis=2) / 0.85)[..., None]
coral = np.array([0.93, 0.36, 0.33], dtype=np.float32)
rgb[shirt] = np.clip(coral * shade[shirt], 0, 1)
# trousers: dark navy -> deep teal leggings
pants = (mx < 0.32) & (mx > 0.03) & (xx < 0.66) & (yy > 0.12) & (yy < 0.52) & (sat < 0.6)
teal = np.array([0.05, 0.30, 0.34], dtype=np.float32)
lum = rgb.mean(axis=2)[..., None]
rgb[pants] = np.clip(teal * (lum[pants] / 0.15), 0, 1)
# hair painted on the scalp: darker, warmer
hair = (xx > 0.6) & (sat > 0.25) & (mx < 0.35) & (mx > 0.02) & (rgb[:, :, 0] > rgb[:, :, 2])
rgb[hair] = rgb[hair] * np.array([0.85, 0.62, 0.55], dtype=np.float32)
px[:, :, :3] = rgb
new_img = bpy.data.images.new("athlete_female_albedo", W, H, alpha=True)
new_img.pixels = px.ravel()
new_img.pack()
img_node.image = new_img

# ---- overall height (4 % shorter) -------------------------------------------
arm.scale = (0.96, 0.96, 0.96)
for o in bpy.context.scene.objects:
    o.select_set(o == arm or o.parent == arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_skins=True,
                          export_animations=False, export_apply=False)
print("WROTE", out)
