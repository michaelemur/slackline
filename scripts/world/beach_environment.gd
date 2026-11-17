class_name BeachEnvironment
extends Node3D
## Tropical beach built from code (no imported assets, mobile friendly):
## sky + sun, sand, animated ocean, palm trees with swaying fronds, bushes,
## grass tufts and drifting clouds. Layers: foreground plants near the
## camera side, the line on the sand in the middle, the sea and far islands
## behind. Nothing here has physics except the flat sand collider.
##
## Layout: the line runs along +X from the origin; the camera looks from -Z
## toward +Z, so the ocean is placed at +Z behind the line.

@export var line_length: float = 15.0
@export var shore_z: float = 24.0          # where sand meets water
@export var seed_value: int = 7

var _clouds: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _layout_built: bool = false

const MIN_LINE_CLEARANCE := 10.0
const PALM_FOOTPRINT_RADIUS := 5.5
const BUSH_FOOTPRINT_RADIUS := 2.5
const GRASS_FOOTPRINT_RADIUS := 0.5

const OCEAN_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.02, 0.22, 0.42);
uniform vec3 shallow : source_color = vec3(0.05, 0.45, 0.58);
uniform float shore_z = 16.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float h = sin(wpos.x * 0.25 + t * 1.1) * 0.12
		+ sin(wpos.z * 0.35 - t * 1.4 + wpos.x * 0.1) * 0.10
		+ sin((wpos.x + wpos.z) * 0.9 + t * 2.3) * 0.03;
	VERTEX.y += h;
	wpos.y += h;
}
void fragment() {
	float d = clamp((wpos.z - shore_z) / 30.0, 0.0, 1.0);
	ALBEDO = mix(shallow, deep, d);
	float foam = (1.0 - smoothstep(0.0, 1.6, wpos.z - shore_z)) * (0.6 + 0.4 * sin(wpos.x * 1.7 + TIME * 2.0));
	ALBEDO = mix(ALBEDO, vec3(0.95), clamp(foam, 0.0, 1.0) * 0.8);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_col : source_color = vec3(0.16, 0.42, 0.12);
uniform vec3 tip_col : source_color = vec3(0.42, 0.62, 0.20);
uniform float sway = 0.12;
void vertex() {
	// UV.x = 0 at the stem, 1 at the tip: tips move most (wind)
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = w.x * 0.37 + w.z * 0.21;
	float k = UV.x * UV.x;
	VERTEX.y += sin(TIME * 1.7 + ph) * sway * k;
	VERTEX.x += sin(TIME * 1.3 + ph * 1.7) * sway * 0.6 * k;
}
void fragment() {
	ALBEDO = mix(base_col, tip_col, UV.x) * (0.85 + 0.15 * UV.y);
	ROUGHNESS = 0.8;
}
"""

const SAND_SHADER := """
shader_type spatial;
uniform vec3 dry : source_color = vec3(0.78, 0.67, 0.49);
uniform vec3 wet : source_color = vec3(0.55, 0.46, 0.33);
uniform float shore_z = 16.0;
uniform sampler2D noise_tex;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.08).r;
	float n2 = texture(noise_tex, wpos.xz * 0.9).r;
	float wetk = smoothstep(shore_z - 3.0, shore_z - 0.2, wpos.z + n * 1.5);
	ALBEDO = mix(dry, wet, wetk) * (0.9 + 0.12 * n + 0.06 * n2);
	ROUGHNESS = mix(0.95, 0.35, wetk);
}
"""


func _ready() -> void:
	_rebuild_layout()


func configure_for_line_length(length: float) -> void:
	var next_length := maxf(length, 4.0)
	var changed := not is_equal_approx(line_length, next_length)
	line_length = next_length
	shore_z = shore_for_line_length(next_length)
	if _layout_built and changed:
		_rebuild_layout()


func _rebuild_layout() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_clouds.clear()
	_rng.seed = seed_value
	_build_sky()
	_build_sand()
	_build_ocean()
	_build_islands()
	_build_palms()
	_build_plants()
	_build_clouds()
	_layout_built = true


static func shore_for_line_length(length: float) -> float:
	# Keep the beach comfortably behind the clearance band. It grows slightly
	# with the selected span so the background remains visually spacious.
	return 24.0 + maxf(0.0, length - 15.0) * 0.05


static func golden_hour_palette() -> Dictionary:
	return {
		"sun_elevation_degrees": 14.0,
		"sun_color": Color(1.0, 0.72, 0.48),
		"sky_top": Color(0.12, 0.26, 0.48),
		"sky_horizon": Color(0.92, 0.53, 0.33),
		"ground_horizon": Color(0.56, 0.31, 0.25),
		"ground_bottom": Color(0.14, 0.20, 0.30),
		"fog": Color(0.82, 0.68, 0.61),
	}


static func clearance_to_line(point: Vector3, length: float) -> float:
	var closest_x := clampf(point.x, 0.0, maxf(length, 0.0))
	return Vector2(point.x - closest_x, point.z).length()


static func is_clear_of_line(point: Vector3, length: float, obstacle_radius: float = 0.0) -> bool:
	return clearance_to_line(point, length) >= MIN_LINE_CLEARANCE + maxf(obstacle_radius, 0.0)


static func palm_spots_for_length(length: float, seed: int = 7) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var spots: Array[Vector3] = []
	for i in range(7):
		var x := lerpf(0.0, length, float(i) / 6.0) + rng.randf_range(-1.2, 1.2)
		spots.append(Vector3(x, 0.0, rng.randf_range(16.0, 21.0)))
	spots.append(Vector3(-16.0, 0.0, 0.0))
	spots.append(Vector3(length + 16.0, 0.0, 0.0))
	spots.append(Vector3(-16.0, 0.0, -16.0))
	spots.append(Vector3(length + 16.0, 0.0, -16.0))
	return spots


static func plant_spots_for_length(length: float) -> Array[Vector3]:
	return [
		Vector3(-14.0, 0.0, -14.0), Vector3(-13.0, 0.0, 14.0),
		Vector3(length + 14.0, 0.0, -14.0), Vector3(length + 13.0, 0.0, 14.0),
		Vector3(length * 0.25, 0.0, -14.0), Vector3(length * 0.5, 0.0, 14.0),
		Vector3(length * 0.75, 0.0, -14.0), Vector3(length * 0.9, 0.0, 14.0),
	]


static func grass_spots_for_length(length: float, seed: int = 7, count: int = 260) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var spots: Array[Vector3] = []
	for i in range(maxi(count, 0)):
		var p := Vector3.ZERO
		for attempt in range(16):
			p = Vector3(rng.randf_range(-25.0, length + 25.0), 0.0, rng.randf_range(-22.0, 9.0))
			if is_clear_of_line(p, length, GRASS_FOOTPRINT_RADIUS):
				break
		if not is_clear_of_line(p, length, GRASS_FOOTPRINT_RADIUS):
			p.z = 10.75 if rng.randf() < 0.5 else -10.75
		spots.append(p)
	return spots


func _process(delta: float) -> void:
	for c in _clouds:
		c.position.x += delta * c.get_meta("speed")
		if c.position.x > line_length + 140.0:
			c.position.x = -160.0


# ---------------------------------------------------------------------------

func _build_sky() -> void:
	var palette := golden_hour_palette()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = palette["sky_top"]
	sm.sky_horizon_color = palette["sky_horizon"]
	sm.ground_horizon_color = palette["ground_horizon"]
	sm.ground_bottom_color = palette["ground_bottom"]
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.9
	# cheap aerial perspective: depth fog tinted like the horizon
	e.fog_enabled = true
	e.fog_light_color = palette["fog"]
	e.fog_density = 0.0035
	e.fog_aerial_perspective = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-float(palette["sun_elevation_degrees"]), -150.0, 0.0)
	sun.light_color = palette["sun_color"]
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0      # shadows only where they matter
	add_child(sun)


func _build_sand() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(260, 120)
	mi.mesh = pm
	mi.position = Vector3(line_length * 0.5, 0.0, shore_z - 60.0 + 2.0)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SAND_SHADER
	mat.shader = sh
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	nt.noise = fn
	mat.set_shader_parameter("noise_tex", nt)
	mat.set_shader_parameter("shore_z", shore_z)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# gentle dunes at the back of the beach (foreground side)
	for i in range(5):
		var d := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 1.0
		sp.height = 2.0
		sp.radial_segments = 16
		sp.rings = 8
		d.mesh = sp
		d.scale = Vector3(_rng.randf_range(8, 14), _rng.randf_range(0.8, 1.6), _rng.randf_range(4, 6))
		d.position = Vector3(-30.0 + i * 20.0 + _rng.randf_range(-4, 4), -0.3, -26.0 + _rng.randf_range(-3, 3))
		d.material_override = mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)


func _build_ocean() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 260)
	pm.subdivide_width = 80     # enough vertices for the waves, still cheap
	pm.subdivide_depth = 50
	mi.mesh = pm
	mi.position = Vector3(line_length * 0.5, -0.15, shore_z + 128.0)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = OCEAN_SHADER
	mat.shader = sh
	mat.set_shader_parameter("shore_z", shore_z)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_islands() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.40, 0.30)
	mat.roughness = 1.0
	for i in range(3):
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 1.0
		sp.height = 2.0
		sp.radial_segments = 12
		sp.rings = 6
		mi.mesh = sp
		mi.scale = Vector3(_rng.randf_range(25, 45), _rng.randf_range(6, 12), 12.0)
		mi.position = Vector3(-70.0 + i * 75.0, -1.5, 190.0 + _rng.randf_range(-20, 20))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# --- palms -----------------------------------------------------------------

func _build_palms() -> void:
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.45, 0.33, 0.22)
	trunk_mat.roughness = 1.0
	var leaf_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LEAF_SHADER
	leaf_mat.shader = sh
	var frond := _frond_mesh()
	var nut_mat := StandardMaterial3D.new()
	nut_mat.albedo_color = Color(0.30, 0.22, 0.10)
	# Where: behind the line (middle ground), at both ends, and a few in the
	# foreground off to the sides so they never cover the athlete.
	for p in palm_spots_for_length(line_length, seed_value):
		if not is_clear_of_line(p, line_length, PALM_FOOTPRINT_RADIUS):
			continue
		_palm(p, _rng.randf_range(5.5, 8.5), trunk_mat, leaf_mat, frond, nut_mat)


func _palm(base: Vector3, h: float, trunk_mat: Material, leaf_mat: Material, frond: Mesh, nut_mat: Material) -> void:
	var palm := Node3D.new()
	palm.position = base
	palm.rotation.y = _rng.randf() * TAU
	add_child(palm)
	# curved trunk from tapered segments
	var lean := _rng.randf_range(0.6, 1.8)
	var segs := 7
	var prev := Vector3.ZERO
	var trunk_builder := SurfaceTool.new()
	trunk_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segs):
		var t := float(i + 1) / segs
		var p := Vector3(lean * t * t, h * t, 0.0)
		var cm := CylinderMesh.new()
		var r := lerpf(0.22, 0.13, t)
		cm.top_radius = r * 0.95
		cm.bottom_radius = r * 1.08
		cm.height = prev.distance_to(p) + 0.05
		cm.radial_segments = 8
		cm.rings = 1
		var dir := (p - prev).normalized()
		var segment_basis := Basis(Quaternion(Vector3.UP, dir))
		trunk_builder.append_from(cm, 0, Transform3D(segment_basis, (prev + p) * 0.5))
		prev = p
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_builder.commit()
	trunk.material_override = trunk_mat
	palm.add_child(trunk)
	# crown: fronds radiating out, drooping
	var crown := Node3D.new()
	crown.position = prev
	palm.add_child(crown)
	var n := 9
	var frond_builder := SurfaceTool.new()
	frond_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var rotation := Vector3(0.0, TAU * i / n + _rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.25, 0.15))
		var scale := Vector3.ONE * _rng.randf_range(0.85, 1.15)
		frond_builder.append_from(frond, 0, Transform3D(Basis.from_euler(rotation).scaled(scale), Vector3.ZERO))
	var fronds := MeshInstance3D.new()
	fronds.mesh = frond_builder.commit()
	fronds.material_override = leaf_mat
	crown.add_child(fronds)
	var coconut_mesh := SphereMesh.new()
	coconut_mesh.radius = 0.12
	coconut_mesh.height = 0.24
	coconut_mesh.radial_segments = 8
	coconut_mesh.rings = 4
	var coconuts := MultiMesh.new()
	coconuts.transform_format = MultiMesh.TRANSFORM_3D
	coconuts.mesh = coconut_mesh
	coconuts.instance_count = 3
	for i in range(3):
		var c := Vector3(cos(i * 2.1) * 0.18, -0.2, sin(i * 2.1) * 0.18)
		coconuts.set_instance_transform(i, Transform3D(Basis.IDENTITY, c))
	var coconut_instances := MultiMeshInstance3D.new()
	coconut_instances.multimesh = coconuts
	coconut_instances.material_override = nut_mat
	coconut_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown.add_child(coconut_instances)


## One frond: a drooping strip with leaflets, UV.x 0 (stem) -> 1 (tip).
func _frond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var length := 3.2
	for i in range(n):
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a := _frond_pt(t0, length)
		var b := _frond_pt(t1, length)
		var w0 := sin(t0 * PI) * 0.75 + 0.05
		var w1 := sin(t1 * PI) * 0.75 + 0.05
		# leaflets angled down on both sides (V shape)
		for side in [-1.0, 1.0]:
			var a2 := a + Vector3(0, -0.18 * w0, side * w0)
			var b2 := b + Vector3(0, -0.18 * w1, side * w1)
			st.set_uv(Vector2(t0, 0)); st.add_vertex(a)
			st.set_uv(Vector2(t1, 0)); st.add_vertex(b)
			st.set_uv(Vector2(t1, 1)); st.add_vertex(b2)
			st.set_uv(Vector2(t0, 0)); st.add_vertex(a)
			st.set_uv(Vector2(t1, 1)); st.add_vertex(b2)
			st.set_uv(Vector2(t0, 1)); st.add_vertex(a2)
	st.generate_normals()
	return st.commit()


func _frond_pt(t: float, length: float) -> Vector3:
	return Vector3(t * length, 0.5 * t - 1.6 * t * t, 0.0)


# --- vegetation ------------------------------------------------------------

func _build_plants() -> void:
	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_color = Color(0.18, 0.40, 0.14)
	bush_mat.roughness = 1.0
	var bush := SphereMesh.new()
	bush.radius = 1.0
	bush.height = 2.0
	bush.radial_segments = 10
	bush.rings = 5
	var bush_transforms: Array[Transform3D] = []
	for p in plant_spots_for_length(line_length):
		if not is_clear_of_line(p, line_length, BUSH_FOOTPRINT_RADIUS):
			continue
		for k in range(3):
			var s := _rng.randf_range(0.5, 1.0)
			var bush_scale := Vector3(s * 1.3, s * 0.8, s * 1.2)
			var bush_position := p + Vector3(_rng.randf_range(-1, 1), s * 0.3, _rng.randf_range(-1, 1))
			bush_transforms.append(Transform3D(Basis.IDENTITY.scaled(bush_scale), bush_position))
	if not bush_transforms.is_empty():
		var bush_multimesh := MultiMesh.new()
		bush_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		bush_multimesh.mesh = bush
		bush_multimesh.instance_count = bush_transforms.size()
		for i in range(bush_transforms.size()):
			bush_multimesh.set_instance_transform(i, bush_transforms[i])
		var bushes := MultiMeshInstance3D.new()
		bushes.multimesh = bush_multimesh
		bushes.material_override = bush_mat
		bushes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bushes)
	# grass tufts: one MultiMesh, swaying with the leaf shader
	var leaf_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LEAF_SHADER
	leaf_mat.shader = sh
	leaf_mat.set_shader_parameter("sway", 0.05)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tuft_mesh()
	var grass_spots := grass_spots_for_length(line_length, seed_value, 260)
	mm.instance_count = grass_spots.size()
	for i in range(mm.instance_count):
		var p: Vector3 = grass_spots[i]
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.6, 1.3))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = leaf_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var a := TAU * i / 5.0
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x) * 0.04
		var tip := d * 0.25 + Vector3.UP * 0.5
		st.set_uv(Vector2(0, 0)); st.add_vertex(-side)
		st.set_uv(Vector2(0, 1)); st.add_vertex(side)
		st.set_uv(Vector2(1, 0.5)); st.add_vertex(tip)
	st.generate_normals()
	return st.commit()


func _build_clouds() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 10
	sp.rings = 5
	for i in range(7):
		var c := Node3D.new()
		c.position = Vector3(_rng.randf_range(-150, line_length + 130.0), _rng.randf_range(45, 70), _rng.randf_range(160, 260))
		c.set_meta("speed", _rng.randf_range(0.6, 1.4))
		var cloud_multimesh := MultiMesh.new()
		cloud_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		cloud_multimesh.mesh = sp
		cloud_multimesh.instance_count = 4
		for k in range(4):
			var r := _rng.randf_range(5, 9)
			var puff_scale := Vector3(r * 1.6, r * 0.6, r)
			var puff_position := Vector3(k * 7.0 - 10.0, _rng.randf_range(-1.5, 2.0), _rng.randf_range(-2, 2))
			cloud_multimesh.set_instance_transform(k,
				Transform3D(Basis.IDENTITY.scaled(puff_scale), puff_position))
		var cloud_puffs := MultiMeshInstance3D.new()
		cloud_puffs.multimesh = cloud_multimesh
		cloud_puffs.material_override = mat
		cloud_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(cloud_puffs)
		add_child(c)
		_clouds.append(c)
