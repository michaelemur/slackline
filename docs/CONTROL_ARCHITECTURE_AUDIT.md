# Slackline — Project Audit and Two-Zone Control Adaptation

**Date:** 2026-11-18 · **Engine:** Godot 4.7.2 · **Branch:** `claude/two-zone-controls` (from Codex `907b9db`)
**Inputs reviewed:** the source tree, `docs/RELEASE_READINESS_REPORT.md`, `docs/AUTONOMOUS_DEVELOPMENT_LOG.md`, all 14 automated suites, 16 recovery folders.
No separate "Codex technical audit" or "Stage 1 completion report" file exists on the Mac (searched Downloads, Desktop, Documents, all recovery folders); the release report and the development log are the latest Codex records and were used as the reference.

Legend: **[C]** confirmed by a test, measurement or graphical run · **[A]** assumption still to be confirmed by hands-on play.

---

## 1. Existing systems and their condition

| System | Files | Condition |
| --- | --- | --- |
| Slackline solver (θ-method taut string, Rayleigh damping, 15/30/40 m presets) | `slackline/*` | **Reliable [C]** — 24 solver tests; 0.25–0.5 ms/step; no NaN or blow-ups in 2 h of randomized play. |
| Leg actuator (PD + Hill limit, contact lockout) | `leg_model.gd` | **Reliable [C]** — energy only enters through the legs; pumping builds a 0.5–0.8 m flight with a bot, 1 m with timed play. |
| Balance (inverted pendulum, 150 ms reflex delay, fore/aft + lateral) | `balance_controller.gd` | **Works [C]**, but its fore/aft authority is small (point foot, `foot_half` 0.11 m) — a held lean tips you over. |
| Athlete state machine (ON_LINE / AIRBORNE / FALLEN + butt/chest/back poses) | `athlete.gd` (≈900 lines) | **Works with one confirmed stuck state (fixed, see §4)**; over-large single file, many flags (`_rising_from`, `_pose_contacted`, `_pose_pushed`, `_landing_pose_explicit`, `hop`). |
| Tricks / aerial rotation (L = I·ω, tuck/layout inertia, landing outcomes) | `trick_controller.gd` | **Physics core sound [C]**; Codex's held flip/twist "torque" added angular momentum in mid-air (not physical); legacy flips use a sizing assist. |
| Contacts and landings (feet, butt, chest, back; save/bail windows; takeoff memory) | `athlete.gd`, `trick_controller.gd` | **Works [C]** — every landing in 2 h of play resolved to clean/saved/bail/fall/reset; 0 contact loops, 0 trapped-in-line events. |
| 53-bone rig, two-bone IK, per-joint springs, COM from segment masses | `athlete_character.gd`, `athlete_visual.gd` | **Reliable [C]** — 0.19 ms; seen running correctly in the live game on the Mac. |
| Camera + cinematic director, slow motion | `camera_rig.gd`, `cinematic_director.gd` | **Works [C]** headless; readable framing seen on the Mac **[C]**; shot quality on hard tricks **[A]**. |
| Beach environment (batched) | `world/beach_environment.gd` | **Works [C]** — runs in the Mobile renderer on the Mac (M4). |
| Input | `athlete_input.gd`, `input_setup.gd`, `touch_controls.gd` | **Was the main problem** — see §5. Replaced by the two-zone scheme. |
| UI / HUD / pause / help | `lab_panel.gd`, `main.gd` | Works [C]; help text updated. |
| Tests | `tests/` | 14 suites, now 1239 assertions passing; plus a new long-session playtest harness. |

## 2. Preserve
Solver, presets, leg model, balance model, rig/IK/visual, trick physics core (inertia, landing outcomes, takeoff-contact memory), scoring/combos, rebound meter, camera + director, beach, HUD/pause flow, all regression suites.

## 3. Repair (done in this pass)
* **Stuck AIRBORNE on the sand [C, fixed].** Root cause: Stage 6 removed the 6-second airborne cutoff, and the "missed the line" check required `vy < 0`. The ground collider stops the body at `vy = 0`, so the athlete stayed AIRBORNE forever (seen twice in 20 min of randomized play; flip counters then ran away: 1424 "flips" in one session). The check now uses the lowest body point with `vy < 0.5`. After the fix: 0 occurrences in 60+ min.
* **Flips landed inside the clean window were not credited [C, fixed].** Rotation is now counted from the net rotation since takeoff (minus planned set and attitude correction), within `LAND_TOLERANCE` of a full turn.
* **Small leans saved onto the back [C, eased].** Clean window widened 0.6 → 0.7 rad (40°).

## 4. Replace
* **The control layer.** Keys and roles collided: SPACE = pump *and* tuck *and* jump; J/K/H/L were both one-shot trick keys and held torque keys; arrows duplicated WASD; nine grab keys. Mid-air torque created angular momentum from nothing, which is why rotations felt "floaty" and why a sizing assist was needed. Replaced by the two-zone scheme (§7–9).

## 5. Architectural conflicts found
1. In-air flip/twist torque vs. conservation of angular momentum (fixed by moving rotation creation to the takeoff).
2. Assist that steers the rotation toward a landable angle vs. "never guarantee landings" (no longer used by the player controls; only the demo pilot's legacy requests use it).
3. The aim lean vs. the balance controller: a lean held while loading tipped the athlete over (82 falls / 10 min vs 30 baseline [C]). Resolved by leaning only during the drive off a rising line → back to 28–34 falls / 10 min (same as baseline).
4. `athlete.gd` owns too much (states, poses, rotation hand-off, arm swing, walking, events). Not split in this pass (risk); listed under the plan.

## 6. Recommended athlete controller architecture — ownership
| Quantity | Owner | Others may |
| --- | --- | --- |
| Line shape, line velocity | `SlacklineSolver` | read; apply contact force via `set_contact` |
| Athlete position / velocity on the line | line contact point (`Athlete._update_on_line`) | — |
| Position / velocity in the air | `RigidBody3D` (gravity only) | — |
| Leg length / push force | `LegModel` (target from `Athlete._leg_command`) | read |
| COM lean (lateral θ, fore/aft φ) | `BalanceController` | set references (`phi_ref`, input axis) |
| Angular momentum about the pitch/twist axes | created **once at takeoff** (`Athlete._set_takeoff_rotation` → `TrickController.launch_spin`) | tuck/grab change inertia only; `adjust_attitude` re-orients ≤ 0.35 rad without new L |
| Contact state / pose | `Athlete` state machine | — |
| Animation | `AthleteVisual` + rig, **read-only** consumer of the physical state | never writes physics |
| Player intent | `AthleteInput` (`hold`, `aim`, `stick`, `grab_held`, position taps) | read only |

## 7. Aerial input (right hand) — implemented
Inspired by the touch-and-hold rhythm of Flip Master (MotionVolt): simple presses whose *timing* is the skill, and tucking to rotate faster. We do not know its internals and do not copy its controls.
* **On the line:** hold = load (sink), release = drive. While holding, **drag** sets the AIM: up = backflip lean, down = frontflip lean, sideways = twist.
* **Takeoff:** the aim leans the body during the drive; the push is then off-axis, so `L = m · v_up · (COM height · sin φ)`. A bigger, better-timed push ⇒ more height **and** more rotation. Measured: full aim with a timed 3.6 m/s push gives L ≈ 43 kg·m²/s; tucked that lands a full backflip or frontflip (rot −5.6 / +5.6 rad, clean) [C].
* **In the air:** hold = tuck (I 13 → 4.2, spins ~3× faster); release = open/straight (straight flips need a big push — physically honest). Direction cannot be reversed in the air (it can on the next contact). Grab is its own button and works tucked (knees) or straight (legs).
* **Positions:** BUTT / CHEST / BACK taps choose the landing contact (defaults to the takeoff contact).

## 8. Balance input (left hand) — implemented
Floating stick: x = weight shift (on the line and in the air), y = walk along the line on the feet, and in the air a small arm/hip attitude correction (≤ 0.35 rad per flight, no new angular momentum).

## 9. How both reach the physics
`AthleteInput` holds intents only. On the line, `stick.x` → balance input, `stick.y` → walk speed, `hold` → leg target, `aim` → `phi_ref` during the drive. At takeoff the athlete converts the *measured* lean into angular momentum. In the air, `hold` → tuck inertia, `grab` → grab inertia, `stick` → lateral air control + attitude. The two hands never write the same quantity, so they cannot fight.

## 10. Keeping existing functionality
Legacy discrete trick requests (`request()`, demo pilot, replays, 60 trick tests) and the held-torque API (tests) still exist; only the default bindings changed. Full suite: **1239 passed, 0 failed** [C]. Smoke: 71/71 [C].

## 11. Future multiple connected lines (not implemented)
Already compatible: the athlete talks to *one* `Slackline` through `project_s / sample_world / sample_velocity / set_contact`, and the solver is per-line. Next steps when wanted: (a) `LineSet` node owning several `Slackline`s; (b) airborne contact search over all lines (the crossing test in `_update_airborne` becomes a loop); (c) `attach(line)` on landing so the contact switches lines; (d) camera framing uses the current line's axis (already rebuilt on preset change).

## 12. Phased plan and test criteria
| Phase | Work | Pass criteria |
| --- | --- | --- |
| 1 ✅ | Audit, stuck-state fix, two-zone controls, takeoff rotation, playtest harness | Full suite green; 60 min randomized play with 0 anomalies; full flips landed by physics [C] |
| 2 | Hands-on tuning on the Mac: aim lean size, tuck speed, landing window | A new player lands a backflip in < 5 min **[A]** |
| 3 | Split `athlete.gd` into contact/pose state machine + takeoff/flight modules (no behaviour change) | Suite + 60 min harness unchanged |
| 4 | Visual polish of tuck / straight / grab shapes and the aim lean | Graphical review |
| 5 | Mobile export (needs export templates, Xcode / Android SDK, a device) | Runs on a phone at stable FPS |

## Playtest harness results (randomized 10-minute sessions, 60 fps physics)
| Build | Session | Jumps | Landings | Falls | Anomalies |
| --- | --- | --- | --- | --- | --- |
| Codex 907b9db | seed 2 | 7 | 4 | 4 | **stuck AIRBORNE at t=141 s for the rest of the session** |
| Codex 907b9db | seed 3 | 22 | 20 | 2 | stuck AIRBORNE at t=88 s |
| + stuck fix | seeds 2–5 | 48–80 | 38–67 | 24–39 | none |
| two-zone controls | seeds 1–2 | 71–82 | 63–69 | 28–34 | none |

Run it with: `godot --headless --fixed-fps 60 --path . -s res://tests/playtest_monkey.gd -- 600 <seed>`
