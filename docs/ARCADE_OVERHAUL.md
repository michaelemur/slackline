# Arcade Overhaul — milestone report (2026-11-18)

## Why earlier updates felt the same
* They tuned realism (balance, takeoff rotation, contact safety). With physical webbing the jumps stay around 1 m, so nothing looked different.
* There was no menu or settings, so the player never chose anything new.
* The HUD and the athlete's look did not change.
* The chest and back positions looked wrong for one confirmed reason: the feet stayed IK-pinned to the contact point, which folded both legs back onto the line.

## Implemented
| Area | What changed |
| --- | --- |
| Main menu | New start scene `scenes/menu.tscn`. Title, PLAY, SETTINGS, and both athletes standing on the beach (tap KAI or MAYA). |
| Settings | Line height 1–10 m (slider, shown in metres), Line Explosiveness (Soft / Balanced / Explosive / Extreme), line length 15/30/40 m, music on/off. Saved to `user://settings.cfg`. The pause menu has a Main menu button. |
| Line height | The line, posts, beach, athlete and camera use the chosen anchor height. Tested at 10 m. |
| Line Explosiveness | While the athlete loads the line, its extra tension is softened as it stretches (slow, deep compression) and boosted as it springs back (fast kick). The boost fades as the tension nears a per-preset cap, so the bounce grows to a maximum instead of without limit. Each preset also scales leg drive and hang time (air gravity). Parameters are in `GameSettings.EXPLOSIVENESS` and `SlacklineParams.arcade_*`. |
| Energy / combos | POWER level: +12 % leg drive per clean trick landing (5 levels). A saved landing costs 2 levels, a fall resets to 0. HUD pips, the line glows hotter, and the live air height shows during big jumps. |
| Female athlete | MAYA (`assets/athlete_female/`), built by `tools/female/make_female.py` from the same 53-bone rig. Sculpted body shape (narrower shoulders and waist, wider hips, chest), skeleton rebuilt to match, 4 % shorter, hair cap and ponytail skinned to the head, her own outfit texture. |
| Chest bounce | Chest rests on top of the line, left hand grips the line beside the head, right hand free, left leg extended, right knee bent, body slightly diagonal. |
| Back bounce | Lying on the back on top of the line, legs raised ~45° in a V, arms spread to the sides. |
| Transitions | A plain push out of butt/chest/back now recovers to the feet. With a flip, the takeoff position stays the default landing, and a position button always wins. |
| Sticky Bounce | Kept from Task 005 and works with every Explosiveness setting. |
| iOS | `export_presets.cfg` iOS preset (bundle id `com.michael.slackline`, iPhone only, arm64, iOS 16+). Landscape orientation is set in the project. |

## Measured (scripted pumping, no tricks, 60 fps)
| Preset | Feet above the line (25 s on a 2.2 m line) | Airtime | Ceiling (60 s, 10 m line) |
| --- | --- | --- | --- |
| Soft | 0.9 m | 0.4 s | — |
| Balanced | 2.3 m | 1.3 s | 2.3 m |
| Explosive | 5.3 m | 2.4 s | 6.7 m |
| Extreme | 6.8–7.7 m | 3.0–3.2 s | 12.3 m |

POWER from clean tricks adds on top of these.

## Tests
* Full suite **1307 passed, 0 failed**. New scenario `tests/test_arcade_menu.gd` covers:
  * menu buttons and the height slider up to 10 m;
  * male/female selection and both 53-bone models loading;
  * the female model has her own proportions;
  * the line is built at the chosen height;
  * Explosive more than 2.5× Soft;
  * Extreme above 6 m on a 10 m line, and below 30 m (bounded).
* `tests/test_body.gd` was updated for the new chest pose. A new check makes sure lying positions do not pin the feet.
* Offline renders checked:
  * the menu with both athletes;
  * the settings panel;
  * the chest, back and sticky positions from three angles;
  * MAYA on a 10 m Extreme line with the camera following.

## Blocked / not done
* **iPhone build:** this Mac has only Apple's Command Line Tools, not full Xcode (needed to sign and install). Godot's iOS export templates are not installed either. Steps:
  1. Install Xcode from the App Store and open it once.
  2. Sign in with an Apple ID (Xcode → Settings → Accounts).
  3. In Godot: Editor → Manage Export Templates → Download.
  4. Project → Export → "iOS (iPhone 15 Pro)": set the Team ID, then Export Project.
  5. Open the generated Xcode project, plug in the iPhone and press Run.
* **Not played by hand yet:** the Mac screen was locked when I tried to launch the editor.
