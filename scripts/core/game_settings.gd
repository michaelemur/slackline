extends Node
## Session settings chosen in the main menu (autoload "GameSettings").
## Saved to user://settings.cfg. Headless test runs always use the physical
## defaults so the regression suite measures the real model.

const SAVE_PATH := "user://settings.cfg"

## Line Explosiveness presets. kick/soften shape the line (slow deep
## compression, fast powerful release); push scales the athlete's leg drive;
## air_g scales gravity in flight (more hang time). Soft = the physical model.
const EXPLOSIVENESS := {
	"soft":      {"label": "Soft",      "kick": 0.0,  "soften": 0.0,  "push": 1.0,  "air_g": 1.0,  "cap": 20000.0},
	"balanced":  {"label": "Balanced",  "kick": 0.45, "soften": 0.25, "push": 1.35, "air_g": 0.82, "cap": 16000.0},
	"explosive": {"label": "Explosive", "kick": 0.95, "soften": 0.45, "push": 1.65, "air_g": 0.68, "cap": 8500.0},
	"extreme":   {"label": "Extreme",   "kick": 1.6,  "soften": 0.6,  "push": 2.05, "air_g": 0.55, "cap": 7500.0},
}
const ORDER := ["soft", "balanced", "explosive", "extreme"]
const HEIGHT_MIN := 1.0
const HEIGHT_MAX := 10.0
const LENGTHS := ["Trickline 15m", "Trickline 30m", "Trickline 40m"]

var character: String = "male"          # "male" | "female"
var line_height: float = 2.2            # m, anchor height
var explosiveness: String = "balanced"
var line_length: String = "Trickline 15m"
var music_on: bool = true
var from_menu: bool = false             # true when the session was started from the menu


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		explosiveness = "soft"
		return
	load_settings()


func preset() -> Dictionary:
	return EXPLOSIVENESS.get(explosiveness, EXPLOSIVENESS["balanced"])


## Applies height and explosiveness to a line preset (a copy is used).
func apply_to_params(p: SlacklineParams) -> SlacklineParams:
	var q: SlacklineParams = p.duplicate()
	q.anchor_height = clampf(line_height, HEIGHT_MIN, HEIGHT_MAX)
	q.arcade_kick = preset()["kick"]
	q.arcade_soften = preset()["soften"]
	q.arcade_tension_cap = preset()["cap"]
	return q


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "character", character)
	cfg.set_value("game", "line_height", line_height)
	cfg.set_value("game", "explosiveness", explosiveness)
	cfg.set_value("game", "line_length", line_length)
	cfg.set_value("game", "music_on", music_on)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	character = cfg.get_value("game", "character", character)
	line_height = clampf(float(cfg.get_value("game", "line_height", line_height)), HEIGHT_MIN, HEIGHT_MAX)
	explosiveness = cfg.get_value("game", "explosiveness", explosiveness)
	if not EXPLOSIVENESS.has(explosiveness):
		explosiveness = "balanced"
	line_length = cfg.get_value("game", "line_length", line_length)
	music_on = cfg.get_value("game", "music_on", music_on)
