extends Node
## Local preference only; never part of room data or the simulation snapshot.
const SETTINGS_PATH := "user://settings.cfg"
const SUPPORTED_LOCALES := ["zh_CN", "en"]
signal language_changed

func _ready() -> void:
	set_language(read_language(), false)

func read_language(path: String = SETTINGS_PATH) -> String:
	var settings := ConfigFile.new()
	if settings.load(path) == OK:
		var saved := str(settings.get_value("interface", "language", ""))
		if saved in SUPPORTED_LOCALES:
			return saved
	return language_for_system(OS.get_locale())

func language_for_system(system_locale: String) -> String:
	var language := system_locale.replace("-", "_").get_slice("_", 0).to_lower()
	return "zh_CN" if language == "zh" else "en"

func set_language(locale: String, persist: bool = true) -> void:
	if locale not in SUPPORTED_LOCALES:
		return
	TranslationServer.set_locale(locale)
	if persist:
		var error := save_language(locale)
		if error != OK:
			push_warning("Could not save language preference: " + error_string(error))
	language_changed.emit()

func save_language(locale: String, path: String = SETTINGS_PATH) -> Error:
	if locale not in SUPPORTED_LOCALES:
		return ERR_INVALID_PARAMETER
	var settings := ConfigFile.new()
	settings.load(path)
	settings.set_value("interface", "language", locale)
	return settings.save(path)
