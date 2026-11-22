class_name SettingsStore
extends RefCounted
## Persists and applies player settings (user://settings.cfg).

const SECTION := "settings"


static func load_values() -> Dictionary:
	var config := ConfigFile.new()
	config.load(GameConfig.SETTINGS_PATH)  # A missing file just yields defaults.
	return {
		"volume": float(config.get_value(SECTION, "volume", 0.8)),
		"fullscreen": bool(config.get_value(SECTION, "fullscreen", false)),
		"effects_quality": str(config.get_value(SECTION, "effects_quality", "full")),
	}


static func save_values(values: Dictionary) -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "volume", values["volume"])
	config.set_value(SECTION, "fullscreen", values["fullscreen"])
	config.set_value(SECTION, "effects_quality", values.get("effects_quality", "full"))
	config.save(GameConfig.SETTINGS_PATH)


static func apply(values: Dictionary) -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, float(values["volume"]))))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
