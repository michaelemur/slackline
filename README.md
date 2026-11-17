# SLACKLINE — v0.3 (physics phase: rebound laboratory)

A 3D mobile slackline game for Godot **4.7.2** (GDScript). Landscape, third-person,
trickline and standard slackline disciplines, hybrid physics.

MVP 0.1 contains: two anchors, a custom simulated slackline with real sag,
stretch, bounce and sway, a placeholder athlete standing on it, a balance
controller, pumping/jumping/landing, falling, a third-person camera, keyboard
controls, a HUD and a live **Physics Lab** with Trickline and Standard presets.

No tricks, mobile touch controls or final art yet. See `docs/ROADMAP.md`.

## Run it

1. Open Godot 4.7.2 → **Import** → choose this folder's `project.godot`.
2. Press **F5** (main scene: `scenes/main.tscn`).

| Key | Action |
|---|---|
| W / S | Walk along the line |
| A / D | Hips (balance strategy) |
| Q / E | Raise left / right arm (each arm is simulated) |
| Shift | Bend knees (lower centre of mass) |
| Space hold / release | Squat (load) / drive the legs (push). Hold while the line is HIGH, release while it is LOW — the on-screen rhythm cue tells you. Takeoff happens physically. |
| J K L H | SET a backflip / frontflip / 360 / 180 on the line (or while bouncing in a butt/chest bounce); it launches as angular momentum at takeoff (L = I·ω) |
| SPACE in the air | Tuck (3× faster rotation); release to open and slow down. Time it: too long over-rotates, too short under-rotates; small misses are saved on chest/back, big ones bail |
| W at takeoff | Lean forward: jump along the line |
| Z X C | Butt / Chest / Back bounce. On the line: drop into it. In the air (or while bouncing in one): choose your next landing — press nothing to land on your feet, press Z/X/C again to chain (x2, x3 … combo). Out of the position you drive back up with your legs on the line's recoil (automatic, or time it with SPACE). |
| T / M | Demo autopilot / slow motion |
| G | Show centre of mass (navel) + plumb line |
| [ ] , mouse wheel | Camera orbit / zoom |
| R | Reset |  1 / 2 presets | F1 physics panel |
| **F3** | **Rebound Laboratory** (5 line lengths side by side) |

Tricks fire in the air, or press them while bouncing to queue one for the
next pop-off. Several tricks in one jump multiply the score (x1.5, x2 …).
Touch down mid-rotation and you bail. A queued air trick waits for a launch
big enough to finish it. Line tricks (Z/X/C) drop you onto the line; a strong
rebound throws you back to your feet for points. Press them in the air to land
straight into the position.

**How to bounce:** hold Space for a few cycles until the line is moving fast,
then let go as it starts coming up. Lower **Balance assist** in the lab to make
balancing fully manual.

## Tests

```bash
godot --headless --path . --import                                   # first time only
godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd # exit code 0 = pass
```

96 checks: solver statics vs closed-form, bounce frequency, energy, stability,
balance, tricks, the 10 Rebound-Lab acceptance criteria, and a scripted
end-to-end run of the real scene. `tests/lab_report.gd` regenerates
`docs/REBOUND_LAB_RESULTS.md`. See `docs/PHYSICS.md` and `docs/PHASE_STATUS.md`.

Screenshots (needs a display or `xvfb-run`):
```bash
godot --path . --rendering-method gl_compatibility -s res://tests/capture_screens.gd -- /some/dir
```

## Layout

```
project.godot
scenes/main.tscn                 level: Slackline, Athlete, CameraRig, LabPanel
scripts/main.gd                  SimulationDirector (fixed physics order) + environment
scripts/slackline/
  slackline_params.gd            Resource: all line tunables
  slackline_solver.gd            pure-math solver (no nodes, unit-testable)
  slackline.gd                   Node3D: owns solver, anchors, contact API
  slackline_renderer.gd          visual-only ribbon mesh
scripts/athlete/
  athlete.gd                     RigidBody3D + ON_LINE / AIRBORNE / FALLEN states
  balance_controller.gd          inverted-pendulum balance model
  athlete_input.gd               input abstraction (keyboard now, touch later)
  athlete_visual.gd              placeholder primitive body, pose only
scripts/camera/camera_rig.gd     third-person follow camera
scripts/ui/lab_panel.gd          HUD + Physics Lab sliders
scripts/core/input_setup.gd      input map registered in code
resources/presets/               trickline.tres, standard.tres
tests/                           headless runner, suites, screenshot capture
docs/                            ARCHITECTURE, PHYSICS, ASSETS, ROADMAP
```
