class_name MotionReference
extends RefCounted
## A captured movement (from tools/mocap): joint angles and body rotation of
## a real performance, normalised over the flight (u = 0 takeoff .. 1 landing).
##
## It is a REFERENCE, not a recording to play back: in the game the athlete
## copies the captured coordination (when to tuck, when to open, what the arms
## and legs do), and the physics turns that into rotation (L = I*w with the
## inertia of the captured body shape) and into the flight path.

var name: String = ""
var fps: float = 30.0
var frames: int = 0
var turns: int = 1
var direction: String = "back"
var total_rotation: float = 0.0
var flight_time: float = 0.0
var takeoff: int = 0
var landing: int = 0
var tuck_at_u: float = 0.0
var open_at_u: float = 1.0
var peak_omega: float = 0.0
var u: PackedFloat32Array
var curves := {}     # tuck (0..1), hip/knee/shoulder/elbow (deg), pitch (rad)


static func load_json(path: String) -> MotionReference:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var m := MotionReference.new()
	m.name = d.get("name", "")
	m.fps = d.get("fps", 30.0)
	m.frames = int(d.get("frames", 0))
	m.turns = int(d.get("turns", 1))
	m.direction = d.get("direction", "back")
	m.total_rotation = d.get("total_rotation_rad", 0.0)
	var ph: Dictionary = d["phases"]
	m.takeoff = int(ph["takeoff"])
	m.landing = int(ph["landing"])
	m.flight_time = ph["flight_s"]
	var tm: Dictionary = d["timing"]
	m.tuck_at_u = tm["tuck_at_u"]
	m.open_at_u = tm["open_at_u"]
	m.peak_omega = tm["peak_omega"]
	var fl: Dictionary = d["flight"]
	m.u = PackedFloat32Array(fl["u"])
	for k in ["pitch", "tuck", "hip", "knee", "shoulder", "elbow"]:
		m.curves[k] = PackedFloat32Array(fl[k])
	return m


## Value of a captured curve at flight phase u (0..1), linear interpolation.
func sample(curve: String, phase: float) -> float:
	var c: PackedFloat32Array = curves[curve]
	var x := clampf(phase, 0.0, 1.0) * (c.size() - 1)
	var i := mini(int(x), c.size() - 2)
	return lerpf(c[i], c[i + 1], x - i)
