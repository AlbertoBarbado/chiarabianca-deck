extends ScreenBase
## Shared shell of every castle service (data/castle/services.json "panel"): header with the
## service name and the campaign resources, a back button to the castle, and the service's panel.
## Panels are small focused controllers (scripts/ui/castle/panels/) with setup(shell) and refresh();
## they call shell.changed() after a transaction (saves and redraws the header).

const PANELS := {
	"deck_workshop": "res://scripts/ui/castle/panels/deck_workshop_panel.gd",
	"collection": "res://scripts/ui/castle/panels/collection_panel.gd",
	"upgrades": "res://scripts/ui/castle/panels/upgrades_panel.gd",
	"fusion": "res://scripts/ui/castle/panels/fusion_panel.gd",
	"apothecary": "res://scripts/ui/castle/panels/apothecary_panel.gd",
	"training": "res://scripts/ui/castle/panels/training_panel.gd",
	"bond": "res://scripts/ui/castle/panels/bond_panel.gd",
}

var service: Dictionary = {}
var panel: Control
var _column: VBoxContainer
var _header: Control


func _menu_screen() -> bool:
	return true


func _menu_dim() -> float:
	return 0.6


func _build() -> void:
	service = DataRegistry.get_service(SceneRouter.service_id)
	var campaign := GameState.campaign
	if campaign == null or service.is_empty() or not PANELS.has(str(service.get("panel", ""))):
		SceneRouter.go.call_deferred(SceneRouter.Screen.CASTLE_HUB if campaign != null else SceneRouter.Screen.MAIN_MENU)
		return
	_column = UIFactory.vbox(12)
	root.add_child(_column)
	_header = _make_header()
	_column.add_child(_header)
	if not campaign.services.has(str(service["id"])):
		_column.add_child(UIFactory.label(str(service.get("hint", "This service is not open yet.")), &"", true))
		return
	var script := load(PANELS[str(service["panel"])]) as GDScript
	panel = script.new()
	panel.name = "Panel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_child(panel)
	panel.call("setup", self)


func _make_header() -> Control:
	return CastleUI.header(str(service.get("name", "")), str(service.get("description", "")), _back)


func _back() -> void:
	SceneRouter.go(SceneRouter.Screen.CASTLE_HUB)


## A transaction happened: save the campaign and refresh the resources in the header.
func changed() -> void:
	GameState.save_game()
	var fresh := _make_header()
	_column.add_child(fresh)
	_column.move_child(fresh, 0)
	_header.queue_free()
	_header = fresh


func toast(text: String, good: bool = true) -> void:
	CastleUI.toast(self, text, good)
