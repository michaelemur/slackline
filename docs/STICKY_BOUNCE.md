# Task 005 — Sticky Bounce

**Status:** implemented and covered by automated tests. Not yet played by hand (see Known limitations).
**Recovery point:** git tag `before-sticky-bounce` (commit before any Task 005 change) and `~/Downloads/Slackline Game/Backups/`.

## Sequence
1. Sit into a **Butt Bounce** (Z, or the BUTT button).
2. Hold **GRAB** (F) once the butt is on the line. Both hands close on the line in front of the hips.
3. **Pump**: hold SPACE while the line drops (pull in / compress), release SPACE as it comes back up (push away / extend). This is the same rhythm as pumping on the feet.
4. The line's swing builds up. You stay attached: the game never launches you while you grip.
5. **Let go of GRAB** whenever you choose. If the line is coming up, the hips and legs drive with it and the line throws you into the air. If it is going down, you ride it and the recoil push throws you.
6. Fly with the normal aerial controls (hold = tuck, grab, aim was set before), and land as usual (feet, butt, chest or back).

## Physical model (reuses the existing solver and leg actuator)
* The athlete–line coupling is the existing `LegModel`: a muscle actuator between the body's centre of mass and the contact point on the line, solved together with the `SlacklineSolver` every substep, so the line reacts to the athlete and the athlete reacts to the line.
* **Grip** makes this coupling two-way (`LegModel.grip`):
  * the actuator may **pull** (negative force) up to `grip_pull_max` = 1500 N (about 2× body weight, an assumption);
  * beyond straight-arm reach (`l_pose + grip_reach` = 0.57 m above the line) the arms act as a stiff stop (40 kN/m), still capped by the grip;
  * the takeoff test is disabled, and the contact stays at the same point `s`, so the hands cannot slide.
* **Pumping** moves the actuator target between `l_pose − 0.03 m` (hold: pull in) and `l_pose + 0.30 m` (release: push away). Energy enters only through actuator work ∫F·(dl/dt)dt, recorded as `sticky_work`. No velocity is ever injected.
* **Timing** comes from the physics, not from a rule. Work is positive only when the force and the relative motion agree, so pumping in phase with the line adds energy and pumping out of phase removes it.
* **Limits** come from the existing actuator force limit and its force–velocity (Hill) curve, the grip strength, the arm stop, and line damping. Losses grow with amplitude until they balance the input, so the amplitude saturates.
* **Release** sets `grip = false`. The contact becomes one-way again, so the body leaves the line only if the line and the body move apart. The jump is the line's recoil plus the existing butt push (`_rise_from_pose`), the same path a normal butt bounce uses.

## Measurements (`tests/measure_sticky.gd`, 60 fps physics, 15 m trickline)
| Pumping | Time gripping | Peak line amplitude | Takeoff speed | Body apex above the line |
| --- | --- | --- | --- | --- |
| none | 6 s | 0.47 m (settling) | no takeoff | — |
| out of phase | 12 s | 0.47 m | 0.4 m/s (no real jump) | −0.25 m |
| in phase | 3 s | 0.79 m | 4.3 m/s | 1.03 m |
| in phase | 6 s | 0.87 m | 3.0 m/s (release late in the rise) | 1.16 m |
| in phase | 12 s | 1.04 m | 4.4 m/s | 1.14 m |
| in phase | 25 s | 1.13 m (saturated) | 4.5 m/s | 1.20 m |

For comparison, a normal feet takeoff in the same session reaches about 3.5–3.6 m/s.

## Controls
| Action | Keyboard | Gamepad | Phone (two-zone) |
| --- | --- | --- | --- |
| Enter Butt Bounce | Z | D-pad down | BUTT button |
| Grip / keep gripping | hold F | hold X | keep the **left thumb** down (or hold GRAB) |
| Pump: compress / extend | hold / release SPACE | hold / release A | hold / release the right zone |
| Release | let go of F | let go of X | lift the left thumb |

While gripping, the HUD shows "Sticky Bounce xN — let go of GRAB to fly". N counts the pump cycles.

## State safety
* The grip ends automatically only when it becomes physically invalid: leaving the line, leaving the butt position, a fall, or a reset. In those cases the hands are cleared (`end_sticky`).
* The stand-up timeout is suspended while gripping.
* GRAB on the feet does nothing to the line.

## Files
* `scripts/athlete/leg_model.gd`: grip coupling (pull force, arm stop, no takeoff).
* `scripts/athlete/athlete.gd`: sticky state, entry and release, pumping targets, work and cycle counters, recovery.
* `scripts/athlete/athlete_input.gd`: `grip_held` (F / GRAB / left thumb).
* `scripts/athlete/athlete_visual.gd`: both hands IK-placed on the line while gripping.
* `scripts/ui/touch_controls.gd`: left thumb down sets the grip.
* `scripts/ui/lab_panel.gd`: HUD line and help text.
* Tests: `tests/test_sticky_bounce.gd` (new scene scenario, 24 checks), `tests/test_touch_controls.gd` (+2), `tests/run_tests.gd` (runs scenario scenes), `tests/measure_sticky.gd`, `tests/playtest_monkey.gd` (adds a sticky plan).

## Validation
* **Automated:** full suite **1287 passed, 0 failed**, including the sticky scenario. That scenario covers:
  * entering the grip;
  * both hands drawn on the line;
  * no launch while gripping (6 s, then 26 s more);
  * at least 8 pump cycles;
  * timing dependence (out of phase builds less than 75 % of in phase);
  * a 15 s energy limit with saturation;
  * voluntary release into a takeoff above 3 m/s;
  * hands detached after release;
  * a valid landing state;
  * no stand-up timeout while holding;
  * reset clears the grip;
  * GRAB on the feet does not grip.
* **Randomized play:** 3 × 10-minute sessions that include sticky plans with random timing and random release moments. They produced 0 stuck states, 0 contact loops and 0 runaway speeds.
* **Visual:** offline renders show the seated grip, the pumping and the release with the hands opening.
* **Manual:** not yet played by hand.

## Known limitations
* `grip_pull_max`, `grip_reach` and `sticky_stroke` are estimates. Tune them after playing.
* The hands are placed by IK on two points in front of the hips. The arm bend during pumping is drawn by the joint springs, not by a separate arm simulation.
* A release while the line is falling still leads to a takeoff on the recoil, via the existing automatic butt push. Releasing on the rise is not much stronger yet. Making timing matter more is a tuning question for hands-on play.
