# Assets (Blender pipeline)

MVP 0.1 deliberately uses primitives only (capsules, cylinders, boxes) built in
code. No Blender files are included yet.

## Planned pipeline

- Author in Blender 4.x, export **glTF 2.0 binary (.glb)** into `assets/blender/`
  (Godot imports .glb natively; avoid .blend import so the project opens on any
  machine without Blender installed).
- Units: metres, +Y up in Godot (enable "+Y Up" on export), athlete ~1.75 m.
- Athlete origin **at the feet**, facing −Z, matching `Athlete` conventions.
- Mobile budget: athlete ≤ 15k triangles, 1 material + 1 texture atlas (≤ 1024²),
  anchors/props ≤ 2k triangles each.
- Rig: humanoid skeleton compatible with Godot's `SkeletonProfileHumanoid` for
  retargeting. Animations needed first: idle-balance, walk-on-line, crouch/pump,
  jump/tuck, land, fall.
- The animated character must implement
  `set_pose(roll, crouch, balance_input, airborne)` so it drops in for
  `AthleteVisual` without touching physics.
