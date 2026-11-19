class_name SlacklineParams
extends Resource
## Tunable physical parameters for one slackline setup.
## Presets live in res://resources/presets/*.tres. Always duplicate() a preset
## before editing it at runtime so the shared resource on disk stays untouched.

@export var preset_name: String = "Custom"

@export_group("Geometry")
## Anchor-to-anchor distance in metres.
@export_range(4.0, 60.0, 0.5) var length: float = 15.0
## Height of both anchors above the ground, metres.
@export_range(0.5, 12.0, 0.05) var anchor_height: float = 2.0
## Number of simulated segments (nodes = segments + 1).
@export_range(8, 128, 1) var segments: int = 48

@export_group("Material")
## Line tension at rest with no load, newtons (what the ratchet sets).
@export_range(100.0, 15000.0, 50.0) var pretension: float = 3000.0
## Axial stiffness EA in newtons (force per unit strain). Lower = stretchier/bouncier.
@export_range(5000.0, 600000.0, 1000.0) var stiffness_ea: float = 90000.0
## Linear mass density of the webbing, kg/m.
@export_range(0.01, 0.5, 0.005) var mass_per_meter: float = 0.09
## Visual webbing width, metres (2" trickline = 0.05).
@export_range(0.01, 0.1, 0.005) var width: float = 0.05

@export_group("Damping")
## Mass-proportional damping (1/s). Mostly controls how long the bounce rings.
@export_range(0.0, 3.0, 0.01) var damping_mass: float = 0.25
## Stiffness-proportional (Rayleigh) damping (s). Kills high-frequency jitter.
@export_range(0.0, 0.05, 0.0005) var damping_stiffness: float = 0.01
## Webbing hysteresis grows with load: internal damping is multiplied by
## 1 + gain * (r - start)^2, r = (tension - pretension) / pretension. Small bounces keep
## their spring; very big loads lose more energy (a natural ceiling).
@export_range(0.0, 2000.0, 0.5) var hysteresis_gain: float = 0.0
## r below which there is no extra loss (pumping loads stay springy).
@export_range(0.0, 3.0, 0.05) var hysteresis_start: float = 0.0

@export_group("Arcade explosiveness")
## Gameplay exaggeration (not real webbing): while an athlete is loading the
## line, the extra tension (above pretension) is reduced as the line stretches
## (a slower, deeper compression) and increased as it springs back (a fast,
## powerful release). 0/0 = physical webbing.
@export_range(0.0, 2.0, 0.01) var arcade_kick: float = 0.0
@export_range(0.0, 0.8, 0.01) var arcade_soften: float = 0.0
## The kick fades out as the extra tension approaches this value, so the
## bounce grows to a preset-dependent maximum instead of without limit.
@export_range(1000.0, 200000.0, 500.0) var arcade_tension_cap: float = 20000.0

@export_group("Solver")
## Solver substeps per physics tick.
@export_range(1, 16, 1) var substeps: int = 4

@export_group("Look")
@export var color: Color = Color(1.0, 0.55, 0.1)


func rest_length() -> float:
	## Unstretched length that produces `pretension` when stretched to `length`.
	return length / (1.0 + pretension / stiffness_ea)
