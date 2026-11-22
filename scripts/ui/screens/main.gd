extends Node
## Game entry point: loads data and settings, then opens the main menu inside a screen host.

@onready var _host: Control = $ScreenHost


func _ready() -> void:
	DataRegistry.ensure_loaded()
	SettingsStore.apply(SettingsStore.load_values())
	SceneRouter.register_host(_host)
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
