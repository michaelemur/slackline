# Status against the "Advanced physics & biomechanics" brief

## Map of the existing implementation (before this phase)

| System | Where | Verdict |
|---|---|---|
| Line physics | `slackline_solver.gd` (custom taut-string, tension from stretch) | **Reused**; integrator fixed (artificial 10 %/cycle loss) |
| Athlete ↔ line | athlete mass glued to line; jump = velocity boost; pump = force multiplier | **Replaced** by `LegModel` (two-body, actuated leg) |
| Balance | `balance_controller.gd` (pendulum, navel COM, arms, knees) | Reused, now fed by real leg length |
| Air | Godot `RigidBody3D` | Reused (ballistic) |
| Tricks | `trick_controller.gd`, scripted rotation rates | Reused for now — **phase 4 to replace** |
| Animation | primitive body posed from physics (`athlete_visual.gd`) | Reused, visual only |
| Input | `athlete_input.gd` abstraction | Reused |

## Phases

| Phase | Status |
|---|---|
| 1 Dynamic line + athlete interaction | ✅ two-body coupling at 240 Hz, lengths 15–30 m |
| 2 Elastic loading, recoil, rebound | ✅ energy only from leg work; takeoff emerges; measured in lab |
| 3 Balance & body mechanics | 🟡 frontal-plane balance with hips/arms/knees; no ankle, no pitch |
| 4 Takeoff & airborne rotation (L = I·ω) | ❌ next |
| 5 Landing & repeated bounce | 🟡 physical landing + repeated bouncing work; landing alignment/foot placement simplified |
| 6 Combos & advanced movement | ❌ (old scripted tricks still in game) |
| 7 Calibration & optimisation | ❌ jump heights below real athletes |

## Acceptance criteria — Rebound Laboratory (part 10)

All covered by `tests/test_rebound_lab.gd` (26 checks, deterministic):

1. 15 m and 30 m behave differently — ✅ sag 0.80 vs 1.58 m, depth, frequency
2. Real-time line deformation — ✅ lab scene, 5 lines live
3. Different oscillation frequencies — ✅ 0.63 / 0.55 / 0.45 Hz
4. Athlete-controlled loading — ✅ slow-deep vs fast-dip give different rebounds
5. Rebound from elastic energy — ✅ in-phase launches, wrong phase never does
6. Different takeoff velocities — ✅ 3.42 m/s (15 m) vs 0.62 m/s (30 m)
7. Repeated bouncing — ✅ 8 takeoffs + 8 landings in 16 s (15 m)
8. Measurable outputs — ✅ 13 metrics, CSV export, identical-condition repeats
