class_name SlacklineRenderer
extends MeshInstance3D
## Visual-only: draws the solver's node chain as a flat webbing ribbon.
## Reads solver state in _process and never writes to it.

var solver: SlacklineSolver
var params: SlacklineParams
var thickness: float = 0.01
var _imesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true  # mesh is built in world space
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rebuild_material()


func rebuild_material() -> void:
	if params:
		_mat.albedo_color = params.color
		# Thin webbing is only a few pixels wide on a phone; a little emission
		# keeps its colour readable from any light angle.
		_mat.emission_enabled = true
		_mat.emission = params.color * 0.45
	_mat.roughness = 0.7
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _process(_delta: float) -> void:
	redraw()


func redraw() -> void:
	_imesh.clear_surfaces()
	if solver == null or solver.node_count() < 2:
		return
	var n := solver.node_count()
	var half_w := params.width * 0.5 if params else 0.025
	var lat := solver.lateral
	var up := Vector3.UP
	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	top.resize(n * 2)
	bot.resize(n * 2)
	for i in range(n):
		var p := solver.node_world(i)
		top[i * 2] = p - lat * half_w + up * thickness
		top[i * 2 + 1] = p + lat * half_w + up * thickness
		bot[i * 2] = p - lat * half_w
		bot[i * 2 + 1] = p + lat * half_w
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	for i in range(n - 1):
		var a := i * 2
		var b := (i + 1) * 2
		_quad(top[a], top[a + 1], top[b + 1], top[b], up)
		_quad(bot[a + 1], bot[a], bot[b], bot[b + 1], -up)
		_quad(bot[a], top[a], top[b], bot[b], -lat)
		_quad(top[a + 1], bot[a + 1], bot[b + 1], top[b + 1], lat)
	_imesh.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		_imesh.surface_set_normal(n)
		_imesh.surface_add_vertex(v)


## 0..1: the webbing glows hotter as the athlete's POWER builds.
func set_glow(amount: float) -> void:
	if params == null:
		return
	var hot := Color(1.0, 0.75, 0.2)
	_mat.emission_enabled = true
	_mat.emission = (params.color * 0.45).lerp(hot * 2.2, clampf(amount, 0.0, 1.0))
