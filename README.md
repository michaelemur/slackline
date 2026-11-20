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

**Simple controls: right hand = power, left hand = position.**

| Key | Action |
|---|---|
| **Space** hold / release | RIGHT HAND, power. Pump the line in every position: hold = sink into it, release = drive off it. Power: feet 100 %, butt 90 %, chest 80 %, back 50 %. In the air: hold = tuck, release = open out. |
| **V / Z / X / C** | LEFT HAND, position: feet / butt / chest / back. On the line: drop into it. In a jump: choose the landing; locked close to touchdown it steers him onto it (a last-moment lock is a PERFECT LOCK, +25 %). With no choice he lands in whatever position he's closest to. Menu setting **Landing lock: HARDCORE** makes an unlocked jump a fail. |
| Arrows or J K H L | On the line: aim the takeoff lean. **In the air: free rotation**: up = backflip, down = frontflip, left/right = twist. Start, stop, reverse at any time; pushing against the spin brakes it fast. |
| F, B, N, P / U, I, O | Air grabs (F grab, B double knee, N knee, P cross) and leg shapes (U pike, I straddle, O split), held any time, combined with any rotation. F in a butt bounce: sticky grip |
| A / D, W / S | Optional: balance is automatic now; walk along the line |
| T / M | Demo autopilot / slow motion |
| G | Show centre of mass (navel) + plumb line |
| [ ] , mouse wheel | Camera orbit / zoom |
| R | Reset |  1 / 2 presets | F1 physics panel |
| F8 | Skinned athlete / capsule body |
| **F3** | **Rebound Laboratory** (5 line lengths side by side) |

On a phone: the left half is a position pad (push up = FEET, down = BUTT,
left = BACK, right = CHEST; slide to change), the right half is
hold-to-pump (in the air: hold = tuck, drag = flip / twist), GRAB / PIKE /
SPLIT are the small buttons top right.

**Fails:** landing far off any position (upside down, sideways off the line)
ends in a fail; in HARDCORE also any real jump without a late lock. The fail type is random (weighted by what went wrong):
over-rotating, under-rotating, feet missing the line, twisted sideways off the
line (mostly from an out-of-balance butt bounce) or ejected. The body goes
floppy (ragdoll), then he is back on the line in under ~2 s.

Tricks fire in the air, or press them while bouncing to queue one for the
next pop-off. Several tricks in one jump multiply the score (x1.5, x2 …).
Touch down mid-rotation and you bail. A queued air trick waits for a launch
big enough to finish it. Line tricks (Z/X/C) drop you onto the line; a strong
rebound throws you back to your feet for points. Press them in the air to land
straight into the position.

**How to bounce:** hold Space for a few cycles until the line is moving fast,
then let go as it starts coming up. Lower **Balance assist** in the lab to make
balancing fully manual.

## Play on a phone (web version)

Every push to `main` on GitHub rebuilds the game for the browser and publishes
it to GitHub Pages (`.github/workflows/deploy-web.yml`). It takes about 2–4
minutes. Then open the Pages link on the phone, hold it sideways and reload.
The touch controls appear automatically on touchscreens. "Add to Home Screen"
makes it open full screen.

Build the web version locally (needs the Godot 4.7.2 web export templates):

```bash
godot --headless --path . --import
godot --headless --path . --export-release "Web" build/web/index.html
python3 -m http.server 8765 --directory build/web
```

The web build is single-threaded, so it works on plain static hosting with no
special server headers. Browsers use Godot's Compatibility (WebGL 2) renderer,
so lighting can look slightly different from the iOS build.

## Tests

```bash
godot --headless --path . --import                                   # first time only
godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd # exit code 0 = pass
```

1668 checks: solver statics vs closed-form, bounce frequency, energy, stability,
balance, tricks, the 10 Rebound-Lab acceptance criteria, and a scripted
end-to-end run of the real scene, the butt-seat clearance after tricks
(`test_butt_clearance.gd`), chest/back landing choice (`test_landing_choice.gd`)
and the landing lock, pumping power and fails (`test_landing_lock.gd`).
Single suites: `-s res://tests/run_unit.gd -- res://tests/test_x.gd` (unit) or
`-s res://tests/run_scenario.gd -- res://tests/test_x.gd` (scene scenario). `tests/lab_report.gd` regenerates
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
