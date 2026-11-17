extends TestCase

const BeachScript := preload("res://scripts/world/beach_environment.gd")
const LENGTHS := [15.0, 30.0, 40.0]
const PRESET_PATHS := [
	"res://resources/presets/trickline.tres",
	"res://resources/presets/trickline_30m.tres",
	"res://resources/presets/trickline_40m.tres",
]


func test_trickline_presets_cover_supported_lengths_with_consistent_segments() -> void:
	for i in LENGTHS.size():
		var params := load(PRESET_PATHS[i]) as SlacklineParams
		check(params != null, "supported length preset loads")
		if params == null:
			continue
		check(params.preset_name.begins_with("Trickline"), "all supported spans stay in Trickline category")
		check(is_equal_approx(params.length, LENGTHS[i]), "preset length matches %s m" % str(LENGTHS[i]))
		check(params.length / float(params.segments) <= 0.5,
			"line discretization stays at or below 0.5 m per segment (%s m)" % str(LENGTHS[i]))


func test_authored_palm_and_plant_layouts_clear_all_supported_lines() -> void:
	for length in LENGTHS:
		for p in BeachScript.palm_spots_for_length(length):
			check(BeachScript.is_clear_of_line(p, length, 5.5),
				"palm footprint clears %s m line at %s" % [str(length), str(p)])
		for p in BeachScript.plant_spots_for_length(length):
			check(BeachScript.is_clear_of_line(p, length, 2.5),
				"bush footprint clears %s m line at %s" % [str(length), str(p)])


func test_procedural_grass_stays_outside_clearance_band() -> void:
	for length in LENGTHS:
		for p in BeachScript.grass_spots_for_length(length, 93, 260):
			check(BeachScript.is_clear_of_line(p, length, 0.5),
				"grass footprint clears %s m line at %s" % [str(length), str(p)])


func test_clearance_math_measures_from_the_segment_and_endpoints() -> void:
	near(BeachScript.clearance_to_line(Vector3(15.0, 0.0, 0.0), 30.0), 0.0, 0.001,
		"point on the span has no clearance")
	near(BeachScript.clearance_to_line(Vector3(-6.0, 0.0, 8.0), 30.0), 10.0, 0.001,
		"endpoint clearance uses planar distance")
	near(BeachScript.clearance_to_line(Vector3(36.0, 0.0, 8.0), 30.0), 10.0, 0.001,
		"far endpoint clearance uses planar distance")
	check(not BeachScript.is_clear_of_line(Vector3(15.0, 0.0, 9.9), 30.0),
		"inside the ten metre band is rejected")
	check(BeachScript.is_clear_of_line(Vector3(15.0, 0.0, 10.1), 30.0),
		"outside the ten metre band is accepted")


func test_environment_configuration_tracks_selected_span() -> void:
	var beach: BeachEnvironment = BeachScript.new()
	beach.configure_for_line_length(40.0)
	check(is_equal_approx(beach.line_length, 40.0), "environment records 40 m span")
	check(beach.shore_z > 24.0, "shoreline adapts slightly to the longer span")
	beach.free()
