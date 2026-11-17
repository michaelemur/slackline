class_name Slackline
extends Node3D
## Scene-facing slackline: owns the solver, the anchors and the renderer.
## Simulation is stepped explicitly by the SimulationDirector (main.gd) via
## simulate(dt) so athlete <-> line coupling order is deterministic.

signal rebuilt

const PRESET_TRICKLINE := "res://resources/presets/trickline.tres"

@export var params: SlacklineParams
@export var ground_height: float = 0.0

var solver := SlacklineSolver.new()
var renderer: SlacklineRenderer
var last_step_ms: float = 0.0

var _anchor_root: Node3D


func _ready() -> void:
	if params == null:
		params = load(PRESET_TRICKLINE) as SlacklineParams
	params = params.duplicate()  # never mutate the preset on disk
	renderer = SlacklineRenderer.new()
	renderer.name = "Renderer"
	add_child(renderer)
	build()


func build() -> void:
	## (Re)creates solver state and anchor geometry from `params`.
	var a := global_transform * Vector3(0.0, params.anchor_height, 0.0)
	var b := global_transform * Vector3(params.length, params.anchor_height, 0.0)
	solver.gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.81))
	solver.ground_height = ground_height
	solver.setup(params, a, b)
	_build_anchors()
	if renderer:
		renderer.solver = solver
		renderer.params = params
		renderer.rebuild_material()
	rebuilt.emit()


func apply_preset(p: SlacklineParams) -> void:
	params = p.duplicate()
	build()


func refresh_material() -> void:
	solver.refresh_material()
	if renderer:
		renderer.params = params
		renderer.rebuild_material()


## Steps the line. Optional per-substep hooks let a body (e.g. LegModel)
## exchange forces with the line at the solver rate:
##   pre(solver, sub_dt)  -> set loads    post(solver, sub_dt) -> integrate body
func simulate(dt: float, pre: Callable = Callable(), post: Callable = Callable()) -> void:
	var t0 := Time.get_ticks_usec()
	var n := maxi(1, params.substeps)
	var sub := dt / n
	for i in range(n):
		if pre.is_valid():
			solver.clear_loads()
			pre.call(solver, sub)
		solver.step(sub)
		if post.is_valid():
			post.call(solver, sub)
	last_step_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Runs the solver with heavy temporary damping so the line starts at its
## loaded equilibrium (avoids a huge drop-in bounce on reset).
func settle(s: float, mass: float, seconds: float = 4.0) -> void:
	var old_cm := params.damping_mass
	params.damping_mass = 6.0
	var dt := 1.0 / 120.0
	for i in range(int(seconds / dt)):
		solver.clear_loads()
		if mass > 0.0:
			solver.set_point_load(s, mass, 0.0, 0.0)
		solver.step(dt)
	params.damping_mass = old_cm
	solver.clear_loads()
	for i in range(solver.node_count()):
		solver.vy[i] = 0.0
		solver.vz[i] = 0.0


# --- athlete contact API -------------------------------------------------

func set_contact(s: float, mass: float, force_y: float, force_z: float) -> void:
	solver.clear_loads()
	solver.set_point_load(s, mass, force_y, force_z)


func clear_contact() -> void:
	solver.clear_loads()


func chord_length() -> float:
	return solver.chord_length


func axis() -> Vector3:
	return solver.axis


func lateral_axis() -> Vector3:
	return solver.lateral


func sample_world(s: float) -> Vector3:
	return solver.world_at(s)


func sample_velocity(s: float) -> Vector3:
	return solver.world_velocity_at(s)


func project_s(world_pos: Vector3) -> float:
	return solver.project_s(world_pos)


func tension() -> float:
	return solver.tension


# --- anchors -----------------------------------------------------------------

func _build_anchors() -> void:
	if _anchor_root:
		_anchor_root.queue_free()
	_anchor_root = Node3D.new()
	_anchor_root.name = "Anchors"
	add_child(_anchor_root)
	_add_post(Vector3(-0.15, 0.0, 0.0))
	_add_post(Vector3(params.length + 0.15, 0.0, 0.0))


func _add_post(local_base: Vector3) -> void:
	var post_h := params.anchor_height + 0.35
	var body := StaticBody3D.new()
	body.position = local_base + Vector3(0.0, post_h * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.15
	cyl.height = post_h
	shape.shape = cyl
	body.add_child(shape)
	var mesh_inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.15
	mesh.bottom_radius = 0.18
	mesh.height = post_h
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.55)
	mat.roughness = 0.9
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	_anchor_root.add_child(body)
