extends TestCase

const BeachScript := preload("res://scripts/world/beach_environment.gd")


func test_beach_uses_warm_low_sun_palette() -> void:
	var palette: Dictionary = BeachScript.golden_hour_palette()
	var sun_tint: Color = palette["sun_color"]
	var horizon: Color = palette["sky_horizon"]
	check(float(palette["sun_elevation_degrees"]) >= 10.0
		and float(palette["sun_elevation_degrees"]) <= 18.0,
		"sun is placed low for a golden-hour silhouette")
	check(sun_tint.r > sun_tint.g and sun_tint.g > sun_tint.b, "sun tint is warm")
	check(horizon.r > horizon.g and horizon.g > horizon.b,
		"sky horizon fades to a warm color")
	check(palette.has("ground_horizon") and palette.has("ground_bottom") and palette.has("fog"),
		"sky, ground and atmosphere share the beach palette")
	var beach: BeachEnvironment = BeachScript.new()
	beach._build_sky()
	var sun_light: DirectionalLight3D = beach.get_node("Sun")
	var worlds := beach.find_children("*", "WorldEnvironment", false, false)
	check(not worlds.is_empty(), "beach creates a world environment")
	if not worlds.is_empty():
		var world := worlds[0] as WorldEnvironment
		var sky_material := world.environment.sky.sky_material as ProceduralSkyMaterial
		check(absf(sun_light.rotation_degrees.x + float(palette["sun_elevation_degrees"])) < 0.01
			and absf(sun_light.light_color.g - sun_light.light_color.b) > 0.1
			and sky_material.sky_horizon_color == horizon,
			"created sky and sun use the golden-hour profile")
	beach.free()


func test_ocean_foam_uses_defined_smoothstep_edges() -> void:
	check(BeachScript.OCEAN_SHADER.contains("1.0 - smoothstep(0.0, 1.6, wpos.z - shore_z)"),
		"foam fades with ordered smoothstep edges on mobile shader compilers")
	check(not BeachScript.OCEAN_SHADER.contains("smoothstep(1.6, 0.0"),
		"undefined reversed smoothstep edges are removed")
