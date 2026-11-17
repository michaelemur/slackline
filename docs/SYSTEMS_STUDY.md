# Systems study: skeleton/IK, balance controller, elastic line

Measured on v0.8 (headless runs of the real game code). Each system is
studied separately: what it does now, what was measured, what is wrong or
missing, and the recommended fix.

## 1. Skeleton and IK

**Now.** Two layers:
- *Pose rig* (`athlete_visual.gd`): hips, torso, thighs, shins, arms. This is
  what the physics drives.
- *Skinned athlete* (`athlete_character.gd`, 53 bones): copies the pose rig;
  two-bone IK for each leg (feet pinned on the line, pole from the rig's
  knee), hands-to-shins arm IK in the tuck, procedural elbows, head, fingers,
  pointed toes in the air.

**Degrees of freedom the physics can actually command**

| Joint | Now | Needed |
|---|---|---|
| Hips | 1 value for BOTH legs (`crouch`), sagittal only | per leg: flexion, abduction, rotation |
| Knees | 1 value for both (always 2 x hip) | per leg |
| Ankles | none in the rig; IK just keeps the foot flat | per foot pitch/roll, contact with the line |
| Shoulders | abduction only (arms out/up), same rule for every situation | flexion + abduction per arm |
| Elbows | one procedural rule (bend more when arms are up) | independent, driven |
| Spine | upper body leans with crouch and hip input | bend + twist |

**Main findings**
- The legs are **always symmetric**: `set_body` writes the same angle to both
  thighs and both shins. That is why walking, single-leg balance and the
  asymmetric chest bounce are impossible today.
- Joints are **set instantly** (kinematic). Nothing has its own spring-damper
  dynamics, so arms snap between positions and look stiff.
- **No joint limits** are enforced in the rig (the IK clamps reach, nothing else).

**Recommendation**
1. Replace the shared `crouch` with a per-limb pose: each joint gets a target
   angle from the controllers, and moves toward it with its own
   spring-damper (stiffness/damping per joint, torque limit). This gives
   natural lag, follow-through and the "loose" arms the brief asks for.
2. Per-leg command + foot contact: stance leg (pinned to the line, IK) vs
   swing leg (free), switched by the walking/balance controller.
3. Joint limits from human range-of-motion tables (knee 0-150, hip -20..130,
   elbow 0-150, ...).

## 2. Balance controller

**Now** (`balance_controller.gd`): inverted pendulum about the line (side to
side only). Gravity torque, foot acceleration from the line, arm reaction
torque + arm mass shift, knee compliance, hip input from the player.

**Measured: standing still for 60 s with NO input, after a small push**

| Setting | Max lean | Falls? |
|---|---|---|
| As shipped | 3.1 deg, then back to 0.1 deg | never |
| Automatic assist off | 62 deg | after 1.1 s |
| Assist and arm reflexes off | 62 deg | after 1.1 s |

**Main findings**
- The automatic **assist is stronger than gravity**: its stiffness is
  1.54 x g/l, while gravity only tips the body at 1.0 x g/l. So the athlete
  balances himself forever. That breaks the brief's rule "never perfectly
  balanced automatically".
- With assist off he falls in 1.1 s. That is physically right for a 1 m
  inverted pendulum, but nobody can play that.
- The arm reaction uses `arm_gain = 3.0`, an **arbitrary multiplier**.
- No **reaction delay** (humans need ~120-200 ms), no line **micro-disturbances**, so the
  body sits perfectly still.
- Side-to-side only: no forward/back balance, and the COM height is a
  formula rather than computed from where the body segments are.

**Recommendation**
1. Set the assist **below** the critical value (about 0.6-0.8 x g/l). The body
   still tips over, just more slowly, so the player has to help.
2. Add a ~150 ms sensorimotor delay to the reflexes and small random line
   disturbances. That gives constant visible micro-corrections.
3. Remove `arm_gain`: compute the arm's real inertia (arm + hand about the
   shoulder) and the reaction torque from it.
4. Compute the COM from segment masses (standard anthropometric tables).
   Then arm and leg positions move the COM for real, and single-leg balance
   becomes "keep the COM over the stance foot".
5. Add forward/back balance (needed for walking and landings).

## 3. Elastic line

**Now** (`slackline_solver.gd`): 48 segments, tension from stretch
T = EA (L - L0) / L0, implicit theta-method integration with a tridiagonal
solve, separate masses for vertical and sideways motion, mass and stiffness
damping. Defaults: 15 m, 3.0 kN pretension, EA 90 kN, 90 g/m.

**Measured (rebound lab, 15-30 m lines)**
- Sag under 75 kg: 0.80 m (15 m line) to 1.58 m (30 m line), consistent with
  the statics a tension calculator uses.
- Bounce frequency: 0.63 Hz (15 m) down to 0.45 Hz (30 m). Longer lines are
  softer and slower, as expected.
- Energy loss: 12-14 % per cycle.
- In-phase pumping beats out-of-phase pumping (takeoffs vs none), so the
  rhythm mechanic is physical.

**Main findings**
- **Jumps are too small for trickline.** Best launch 3.4 m/s, about 0.6 m above the
  line. Real trickliners go well above 1.5 m.
  - **Peak line tension** is at most 6.3 kN in that test.
  - **Line vs athlete speed:** the line moves at up to 8.4 m/s at release, but the athlete leaves at 3.4 m/s.
  - So energy is being lost in the leg-to-line handover (leg force cap 5.3 x body weight, contact lockout). This is the first thing to investigate.
- **Stretch is linear.** Real trickline webbing stretches nonlinearly: one
  tested webbing is 6.85 % at 3.91 kN and 11.2 % at 8.33 kN. That means a
  secant stiffness of about 57 kN at low load, rising to about 74 kN, against
  the game's constant 90 kN.
- **Anchors are rigid.** Real anchors (trees, frames, slings) give a little,
  which lowers peaks and changes the timing.
- No twisting (torsion) of the webbing under the feet. Minor for gameplay.

**Recommendation**
1. Trace the energy in the leg-line handover with the lab, and fix the loss
   so a well-timed pump launches 1.5-2.5 m.
2. Use a measured force-stretch curve instead of a constant EA.
3. Add anchor compliance (a spring in series at each end).
4. Re-run the lab and compare with the targets above.

## Suggested order

1. **Balance** (small change, big effect on feel): assist below critical,
   delay, disturbances, remove `arm_gain`.
2. **Skeleton**: per-limb joint targets with spring-damper joints and per-leg
   control. This unlocks walking, single-leg balance and the two bounce
   positions (brief phases 3-5).
3. **Line energy**: find the launch loss, add nonlinear webbing and anchor
   compliance, re-calibrate in the lab.
