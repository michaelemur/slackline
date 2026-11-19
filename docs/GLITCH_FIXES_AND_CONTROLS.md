# Glitch fixes and fun controls — milestone report (2026-11-19)

Brief: *Slackline - Glitch Fixes and Fun Controls* (fix two glitches, then
right hand = power, left hand = position, random fails, ragdoll falls).

## 1. Glitch: butt passes through the line — fixed

Measured on the real scene (lowest hip joint above the line while drawn in the
butt position; ~0.13 m is a correct seat):

| Situation | Before | After |
| --- | --- | --- |
| First plain butt bounce | +0.13 m | +0.14 m |
| Seated after any rise / after tricks | **−0.21 m** (every frame) | +0.12 m |
| Driving up out of the seat | **−0.21 m** | +0.12 m |
| Line ringing up right after a seat takeoff | **−0.9 m** (line through the body, then he fell from under it) | +0.12 m |
| Fast landing into the seat (−12 to −20 m/s) | **−0.12 m** for one drawn frame | +0.12 m |

Causes and fixes (`scripts/athlete/athlete.gd`):
* **Double drop.** Rising out of a position, the balance model read the short
  leg as a deep knee squat (`crouch = 1`), and the sitting pose dropped the hips
  again on top. The crouch was never cleared while seated, so every later butt
  bounce sat 0.2 m low ("the first one is fine, it starts after tricks"). The
  knee crouch now fades out while a line position is drawn.
* **Seat guard, every frame.** Hips and both hip joints are measured against
  the line under each of them. If they would be closer than 12 cm, the whole
  body is raised (it eases back off at 0.6 m/s). In the air it looks one
  physics step ahead, so a fast landing never shows a frame through the line.
* **The line catching the body after takeoff.** The line can ring back up
  faster than the body rises; contact was ignored for 0.08 s, so it passed
  straight through. Now the light line and the heavy body meet inelastically
  (momentum kept): the line is stopped by the body, the flight and any trick
  continue. A re-catch that early is not a landing, so it never counts as a
  landing without a lock.

Test: `tests/test_butt_clearance.gd`: a plain bounce, then 15+ flips set from the
seat and landed back in it (Angel / Manson), then the demo's video combo.
Lowest seat clearance is checked every frame (≥ 5 cm).

## 2. Glitch: chest and back swap — fixed

Three ways a chosen chest landing could come out on the back (and back on the
chest), all in `scripts/athlete/trick_controller.gd`:
* **Wrap-around.** The save position came from the absolute pitch wrapped to
  ±180°. Over-rotating past face-down by more than 90° wrapped negative and read
  as the back. Saves are now decided along the miss, never across the wrap. Far
  past face-down is a fail (head-down), not the back.
* **The chosen position wins.** Within 65° of the chosen butt/chest/back it
  lands there (a "sketchy" landing beyond 40°), instead of whichever position is
  nearest.
* **Half twist.** With half a twist the face points the other way, so pitch
  +90° is face-up. Landings use the facing angle (`facing_pitch()`) and the lock
  steers to the right side.
* **Lean against the set.** A backward pumping lean could cancel the forward
  quarter turn into the chest. The late lock now steers onto the chosen
  position.

Tests: `tests/test_landing_choice.gd` (300 checks). Every start (feet, butt,
chest) × target (chest, back) × twist × spin × miss from −2.6 to +2.6 rad: never
swapped. Full flights from all three starts with and without flips, leaning
against the set, half-twisted jumps. `tests/test_landing_lock.gd` repeats
chest/back from feet, butt and chest on the real scene.

## 3. New controls

| Hand | Keyboard | Phone | What it does |
| --- | --- | --- | --- |
| Right: power | SPACE | right half, hold | Pump in every position: hold = sink, release = drive. In the air: tuck / open. |
| Left: position | V feet, Z butt, X chest, C back | left half pad: up/down/left/right | On the line: drop into it. In a jump: lock the landing late. |

* **Pumping power** (`Athlete.POSITION_POWER`): feet 100 %, butt 90 %, chest
  80 %, back 50 %. It sets the push strength from that position. A push that
  does not leave the line settles back into the same position, ready for the
  next pump. Measured from rest: butt and chest take off after ~1.5 s, back
  after ~3 s. Good pumping from the butt launches at 2.9 m/s vs 1.3 m/s
  without.
* **Late landing lock.** A real jump (predicted flight ≥ 0.55 s) needs a lock
  in the last 0.75 s before touchdown. Earlier = "Too early!" (not locked).
  Within 0.28 s = PERFECT LOCK (+25 % points). The body is then steered onto the
  chosen position with at most 26 rad/s². That is plenty for a quarter turn, but
  not enough to stop a tuck held too long, so the timing of opening the trick
  still matters. The HUD flashes "LOCK YOUR LANDING!" while the window is open.
* **Balance is automatic** (the left hand is busy). A/D still override it.

## 4. Fails

A fail happens when no landing is locked in a real jump, the rotation is too
far off at touchdown (opening too early or late), the feet miss the line, or
the balance goes. The type is random, weighted by what went wrong:

| Type | Typical cause (higher weight) | How he flies |
| --- | --- | --- |
| Over-rotating | spun past the landing | keeps tumbling head over heels |
| Under-rotating | didn't come round | slams in short |
| Feet missing the line | lateral miss | drops through beside the line |
| Twisted sideways off | out of balance, most from a butt bounce | spins round and rolls off |
| Ejected | no lock / hard hit | thrown up and away, tumbling |

## 5. Ragdoll falls

`AthleteVisual._ragdoll_step`: every joint becomes a loose, under-damped
pendulum. Gravity pulls each limb toward hanging, the body's tumble flings arms
and legs out and makes them lag, and each hit on the sand kicks them about.
Joint limits are bouncy and the body has a little bounce off the sand. The
flight rotation at the moment of the fail is kept, so the tumble starts from
the pose he was in. He is back on the line ~0.35 s after lying still (1.1 s at
the earliest, 2.6 s at the latest), next to where he fell. Frames of every
type: `godot --path . -s res://tests/capture_fails.gd -- /out/dir`.

## Tests

Full suite **1668 passed, 0 failed** (was 1307). New: `test_landing_choice.gd`,
`test_butt_clearance.gd`, `test_landing_lock.gd`. Updated for the new rules:
`test_touch_controls.gd` (position pad), `test_gameplay_smoke.gd` (stalled
pushes now return to the position; the back is pumped; physics checks use the
`auto_lock` assist), `test_arcade_menu.gd` (`auto_lock`, same heights as
before: soft 0.80 m, explosive 2.33 m, extreme 7.38 m).

## Follow-up: playability and free air control (same day)

Playtest feedback: "he fails a lot, doesn't feel playable", plus a brief asking
for an unrestricted aerial trick sandbox.

* **Landing lock is now optional** (menu: *Landing lock: EASY / HARDCORE*,
  default EASY). With no choice he lands in the nearest landable position. A
  choice pressed early is remembered and locks itself when the window opens.
  The lock only steers while the player is not rotating him.
* **Free air control** (`TrickController.update_air`). Flip torque
  (front/back), twist torque (left/right), tuck/open, grabs and leg shapes
  (pike, straddle, split) are independent and available until touchdown.
  Torques: 55 (flip) and 9 (twist), doubled when pushing against the current
  spin, so reversals feel quick. Angular momentum is kept through every shape
  change. The recorded mocap limb motion switches off once the player rotates.
  A gentle settle assist works only when hands are off and the body is open.
* **Arcade help** on the way down: a sideways pull over the line
  (`line_magnet`) and air righting of the sideways lean.
* Measured with a scripted button-masher (random flips, twists, grabs, never
  locking, 3 min). EASY: fails 17 → **0** of ~85 jumps, score 6.6k → 32k.
  HARDCORE: 4 fails out of 81 jumps, all from skipping the lock.
* Tests: `tests/test_air_freedom.gd` (start a flip any time, smooth reversal,
  repeat tuck/open, add/remove/reverse twist, grabs independent of rotation, a
  lock never overrides input). `test_landing_lock.gd` adds an easy-mode jump
  and a full free-style flight on the real scene. Suite: **1716 passed**.

## Not done / not checked

* Not played by hand on a phone or keyboard. Checked in headless scripted
  scenarios and rendered frames only.
* The demo autopilot locks its landings like a player. Its score per run is
  lower than before because more of its jumps now need a well-timed lock.
