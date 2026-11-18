extends TestCase
## Generated music, ambience and effects load and are routed.

func test_all_generated_sounds_load() -> void:
	var d := AudioDirector.new()
	d._load_defaults()
	for key in AudioDirector.DEFAULTS:
		var s: AudioStream = d.get(key)
		check(s != null, "%s loads" % key)
		if s != null:
			check(s.get_length() > 0.2, "%s has sound (%.1f s)" % [key, s.get_length()])
	check(d.music is AudioStreamOggVorbis and d.music.loop, "music loops")
	check(d.ocean_ambience.loop and d.wind_ambience.loop, "ambience loops")
	check(d.music.get_length() > 60.0, "music track is over a minute (%.0f s)" % d.music.get_length())
	d.free()
