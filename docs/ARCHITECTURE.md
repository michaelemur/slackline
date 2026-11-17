# Architecture

## Principles

- **Physics is separate from rendering and animation.** `SlacklineSolver` is a
  plain `RefCounted` with no nodes. `SlacklineRenderer` and `AthleteVisual` only
  read state in `_process`; nothing visual writes back into physics.
- **Deterministic order.** `main.gd` is the SimulationDirector; the line and
  athlete have no `_physics_process` of their own:
  `athlete.pre_line_step(dt) → line.simulate(dt) → athlete.post_line_step(dt)`.
- **Input is abstracted.** Gameplay reads only `AthleteInput`
  (move / balance / pump / jump-release). The keyboard writes it today; touch
  controls, replays and tests use the same fields (tests use `override_*`).
- **Data-driven tuning.** All line numbers live in `SlacklineParams` resources;
  presets are duplicated at load so the lab never edits files on disk.

## Runtime graph

```
Main (Node3D, main.gd)               SimulationDirector + environment
├─ Slackline (slackline.gd)          solver + anchors (StaticBody3D posts)
│   ├─ Renderer (MeshInstance3D)     ribbon mesh, top_level, world space
│   └─ Anchors
├─ Athlete (RigidBody3D, athlete.gd) state machine, LegModel, BalanceController
│   ├─ CollisionShape3D (capsule)
│   ├─ Visual (AthleteVisual)        placeholder body, pose only
│   └─ Input (AthleteInput)
├─ CameraRig (camera_rig.gd)         Camera3D child
└─ LabPanel (CanvasLayer)            HUD + Physics Lab
```

## Athlete states

```
ON_LINE ──pop-off──▶ AIRBORNE ──lands on line──▶ ON_LINE
   │                    │
   └──over-lean──▶ FALLEN ◀──misses line───┘
                     └──2.5 s / R──▶ ON_LINE (line pre-settled)
```

## Extension points for later versions

- **Mobile controls (v0.2):** a `TouchControls` CanvasLayer with a virtual
  joystick (move) and a separate balance pad + trick buttons writing to
  `AthleteInput`. No gameplay changes required.
- **Tricks (v0.3+):** a `TrickController` reading AthleteInput trick buttons
  while AIRBORNE, driving rotations on the rigid body and scoring on landing.
- **Blender character:** replace `AthleteVisual` with an animated glTF scene
  exposing the same `set_pose(roll, crouch, balance_input, airborne)`.
- **Multiple lines / levels:** `Slackline` is self-contained and placed by its
  transform; the director can hold an array of lines.

## Physics phase additions

- `scripts/athlete/leg_model.gd` — two-body athlete/line coupling (actuated leg,
  push-only, force–velocity limits, emergent takeoff, landing absorption).
  Pure `RefCounted`, used by both the game athlete and the lab.
- `Slackline.simulate(dt, pre, post)` — per-substep hooks so bodies exchange
  forces with the line at the solver rate.
- `scripts/lab/rebound_experiment.gd` — one deterministic experiment (solver +
  LegModel + scripted technique) with measurements; headless-runnable.
- `scenes/rebound_lab.tscn` / `scripts/lab/rebound_lab.gd` — 5 lengths live,
  sliders, protocols, comparison table, CSV. F3 from the game.
