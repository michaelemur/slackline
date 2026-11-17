# Physics model

Everything here is simulated, not animated. Visuals only read physics state.

## 1. Slackline — `SlacklineSolver`

**Taut string with stretch-dependent tension**, N segments between fixed anchors.

- Nodes move transversely: vertical `y` (world up) and lateral `z`.
- Axial waves in webbing travel at ~1 km/s, so tension is uniform along the line
  and recomputed every substep from the stretched length:
  `T = EA · (L_now − L_rest) / L_rest`, clamped ≥ 0 (tension-only: slack is possible).
  `L_rest = L / (1 + T0/EA)`, so the unloaded line sits at the ratchet pretension.
  Sag stiffens the line (geometric + material non-linearity).
- Per node: `m·a = (T/h)·(y[i−1] − 2y[i] + y[i+1]) + F − m·g`.
- **θ-method integration** (θ = 0.52), tridiagonal Thomas solve, O(N), stable.
  θ = 0.5 is the trapezoidal rule, which conserves elastic energy. The earlier
  implicit Euler (θ = 1) silently removed **~10 % of the bounce energy per cycle**
  (measured with all damping set to zero), which is wrong for a sport built on
  stored elastic energy. Fixed in this phase.
- **Damping** (Rayleigh): `damping_mass` (1/s) + `damping_stiffness` (s).
  Measured in the lab, the line's stiffness damping dominates; the trickline
  preset now uses 0.003 s → **12–14 % energy loss per bounce cycle**.
- Loads: each contact lumps a mass and forces onto the two nodes around it.
  The vertical and lateral lumped masses are separate (see §2).
- Length is a real simulation parameter (segment count scales with length).

## 2. Athlete ↔ line: `LegModel` (new in this phase)

Two bodies in the vertical direction, joined by an actuated leg:

```
   COM  (body − feet, 69 kg)          y_c, v_c  — integrated each substep
    │   leg: servo spring-damper + muscle limits, PUSH ONLY
   feet (6 kg, lumped into the line) — move with the line
```

- **Leg actuator.** PD servo towards a commanded leg length (= the player's
  squat/extend command), behaving like the "leg spring" of hopping biomechanics.
  Stiffness default 30 kN/m (Ferris & Farley 1997 measured k_leg of 17.8 kN/m on
  hard ground and up to 53.3 kN/m on the softest surface), damping 1000 N·s/m.
- **Muscle limits.** Concentric force capped at `f_max` (default 2600 N ≈ 3.5 BW —
  an assumption, tunable) and reduced linearly with extension speed up to
  `v_max` = 3.5 m/s (Hill-type force–velocity). Eccentric (yielding) force may
  reach 1.5 × f_max. Muscle activation lag τ = 60 ms.
- **Lockout.** The leg cannot exceed full length (COM 0.98 m above the feet =
  56 % of a 1.75 m athlete). Bottom-out: stiff passive stop at the deepest squat
  (or at butt/chest/back height during line tricks).
- **Takeoff emerges.** When the leg is fully extended and the COM still moves away
  from the line, the feet leave it. Nothing adds velocity on a button press.
- **Energy enters only through actuator work** `∫F·(dl/dt)dt` — pushing while the
  line is deep (force high) and squatting while it is high (force low) pumps
  energy in; doing the reverse does not. The lab measures this (§4).
- **Lateral.** The whole body's inertia resists sideways line motion (lumped
  laterally), the balance pendulum (§3) adds its reaction force.
- **Landing.** Feet join the line with their momentum (momentum-conserving), the
  COM lands on the leg, and the leg absorbs the impact through the same
  actuator: impact forces, line deformation and rebound emerge.
- Coupled at every solver substep (240 Hz) via hooks in `Slackline.simulate`.

## 3. Balance — `BalanceController` (frontal plane)

Inverted pendulum on the moving foot, COM at 56 % of height (just below the
navel). Strategies available on a line: **hips** (A/D), **arms** — each arm a
separate segment whose swing reacts on the body and whose mass shifts the COM
(Q/E), **knees** (Shift / leg length) — lower COM and a compliant stance leg that
soaks up the line's sideways jerks. Line acceleration changes effective gravity.
Optional assist for beginners (lab slider; set 0 for no help).

## 4. Rebound Laboratory — measured (defaults, see `REBOUND_LAB_RESULTS.md`)

Same webbing (3 kN, EA 90 kN, 90 g/m), same 75 kg athlete, same anchors (3.5 m):

| | 15 m | 20 m | 30 m |
|---|---|---|---|
| Static sag | 0.80 m | 1.07 m | 1.58 m |
| Bounce frequency (athlete on line) | 0.63 Hz | 0.55 Hz | 0.45 Hz |
| Energy loss / cycle (passive) | 14.2 % | 12.7 % | 12.0 % |
| Slow-deep squat → rebound speed | 2.40 m/s | 2.12 m/s | 1.77 m/s |
| Fast-dip → rebound speed | 1.31 m/s | 1.12 m/s | 1.08 m/s |
| In-phase pumping → best takeoff | 3.42 m/s | 3.16 m/s | 0.62 m/s |
| Jump (COM rise) / airtime | 0.59 m / 0.69 s | 0.50 m / 0.66 s | 0.02 m / 0.24 s |
| Same effort, wrong timing | no takeoff | no takeoff | no takeoff |

Findings that emerged (not scripted):
- Longer line → slower rhythm and deeper loading, **but not higher jumps** at equal
  pretension: to separate, the line must rise near the anchor chord, and the
  30 m line's 1.58 m sag needs more amplitude than pumping can build. Raising
  pretension to 5 kN gives the 30 m line takeoffs (1.96 m/s measured).
- Slow-deep loading stores more energy than a fast shallow dip.
- Timing, not effort, decides whether energy goes in.

## 5. Known limitations / next phases

- Jumps are still modest (≤ ~0.6 m COM rise). Real tricklining achieves far more;
  calibration (pretension range, leg strength, arm swing, launch technique) is
  phase 7 work — numbers above must not be read as validated against athletes.
- No pitch (fore–aft) balance; feet are a single contact point; no ankle joint.
- Air tricks still use scripted rotation rates — **phase 4** replaces them with
  angular momentum `L = I·ω` and tuck/extend inertia changes.
- "Rebound m/s" in pumping runs includes landing transients.
- 15 Hz foot-on-line mode needs leg damping ≥ 600 N·s/m (enforced).

## Sources (verified)

- Paoletti P., Mahadevan L. (2012) *Balancing on tightropes and slacklines.*
  J. R. Soc. Interface 9(74):2097–2108. doi:10.1098/rsif.2012.0077
  (note: the brief cites Proc. R. Soc. A — the paper is in J. R. Soc. Interface).
- Mildren R.L. et al. (2018) *Learning to balance on a slackline: development of
  coordinated multi-joint synergies.* Scand J Med Sci Sports.
- Qian J. et al. (2020) *A finite element model for estimation of contact dynamics
  during a jumping movement on a trampoline.* J. Hum. Kinet. 73:59–72.
  doi:10.2478/hukin-2019-0127
- Ferris D.P., Farley C.T. (1997) *Interaction of leg stiffness and surface
  stiffness during human hopping.* J. Appl. Physiol. 82(1):15–22.
- Stein K., Mombaur K. (2022) *A quantitative comparison of slackline balancing
  capabilities of experts and beginners.* Front. Sports Act. Living 4:831362.
- Vallery H., Neumann J. (2013) *Balancing on slacklines: modeling and empirical
  evaluation* (Dynamic Walking abstract).
- Body centre of mass ≈ 55–56 % of height: standard anthropometry.
