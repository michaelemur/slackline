extends TestCase

const LabScript := preload("res://scripts/ui/lab_panel.gd")
const AudioScript := preload("res://scripts/audio/audio_director.gd")


func test_safe_area_is_mapped_from_physical_screen_to_viewport() -> void:
	var safe := LabScript.safe_rect_for_viewport(
		Vector2(422.0, 195.0), Vector2i(844, 390), Rect2i(44, 0, 756, 390))
	check(safe.position.is_equal_approx(Vector2(22.0, 0.0)),
		"left notch inset scales into viewport coordinates")
	check(safe.size.is_equal_approx(Vector2(378.0, 195.0)),
		"safe viewport size respects display scaling")
	var fallback := LabScript.safe_rect_for_viewport(Vector2(100, 50), Vector2i.ZERO, Rect2i())
	check(fallback == Rect2(Vector2.ZERO, Vector2(100, 50)),
		"unknown desktop safe area falls back to the full viewport")


func test_pause_action_is_registered() -> void:
	InputSetup.ensure_actions()
	check(InputMap.has_action("pause"), "pause action is available to keyboard and UI")


func test_audio_director_is_safe_with_missing_optional_assets() -> void:
	var audio: AudioDirector = AudioScript.new()
	audio._ready()
	check(audio._voices.size() == 4, "audio director creates a small overlapping SFX voice pool")
	check(audio.ocean_ambience == null and audio.wind_ambience == null,
		"project audio assets remain explicitly unassigned")
	check(not audio._play(null), "missing sound streams safely produce no playback")
	audio.free()
