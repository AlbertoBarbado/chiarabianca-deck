extends Node
## Room/screen transitions. The Main scene registers a host Control; screens are swapped
## inside it so transitions can share a fade and a theme.

signal screen_changed(screen: Screen)

enum Screen {
	MAIN_MENU, SETTINGS, CHARACTER_SELECTION, SPECIALIZATION_SELECTION, PARTY_OVERVIEW,
	MAP, REST, MERCHANT, EVENT, COMBAT, REWARD, RUN_END, TREASURE, TOWN, ACT_TRANSITION, EQUIPMENT,
}

const SCREEN_PATHS := {
	Screen.MAIN_MENU: "res://scenes/menus/main_menu.tscn",
	Screen.SETTINGS: "res://scenes/menus/settings.tscn",
	Screen.CHARACTER_SELECTION: "res://scenes/menus/character_selection.tscn",
	Screen.SPECIALIZATION_SELECTION: "res://scenes/menus/specialization_selection.tscn",
	Screen.PARTY_OVERVIEW: "res://scenes/menus/party_overview.tscn",
	Screen.MAP: "res://scenes/map/map_screen.tscn",
	Screen.REST: "res://scenes/exploration/rest_room.tscn",
	Screen.MERCHANT: "res://scenes/shops/merchant_room.tscn",
	Screen.EVENT: "res://scenes/events/event_room.tscn",
	Screen.COMBAT: "res://scenes/combat/combat_screen.tscn",
	Screen.REWARD: "res://scenes/progression/card_reward.tscn",
	Screen.RUN_END: "res://scenes/menus/run_end.tscn",
	Screen.TREASURE: "res://scenes/exploration/treasure_room.tscn",
	Screen.TOWN: "res://scenes/exploration/town_room.tscn",
	Screen.ACT_TRANSITION: "res://scenes/exploration/act_transition.tscn",
	Screen.EQUIPMENT: "res://scenes/menus/equipment.tscn",
}
const FADE_TIME := 0.18

var current_screen: Node = null
var current_screen_id: Screen = Screen.MAIN_MENU
var _host: Control = null
## Screen the equipment screen returns to (map, town or reward).
var equipment_return: Screen = Screen.MAP


func register_host(host: Control) -> void:
	_host = host


func go(screen: Screen) -> void:
	if _host == null:
		push_warning("SceneRouter: no host registered; cannot open screen %d" % screen)
		return
	var packed := load(SCREEN_PATHS[screen]) as PackedScene
	if packed == null:
		push_error("SceneRouter: cannot load %s" % SCREEN_PATHS[screen])
		return
	if current_screen != null:
		current_screen.queue_free()
	current_screen = packed.instantiate()
	current_screen_id = screen
	if current_screen is Control:
		(current_screen as Control).theme = UITheme.get_theme()
		(current_screen as Control).modulate.a = 0.0
	_host.add_child(current_screen)
	if current_screen is Control:
		create_tween().tween_property(current_screen, "modulate:a", 1.0, FADE_TIME)
	screen_changed.emit(screen)


## Opens the party equipment screen; its Back button returns to `from`.
func open_equipment(from: Screen) -> void:
	equipment_return = from
	go(Screen.EQUIPMENT)


## Enters a room for the first time: records it in the saved room state, then opens it.
func go_to_room(node: MapNodeData) -> void:
	if node.type != MapNodeData.TYPE_EXIT:
		GameState.begin_room(node)
	open_room_screen(node)


## After loading a save: reopens the room the party was in (or the map when it was between rooms).
## A saved combat in its fight phase restarts that fight (checkpoint); the reward phase reopens
## the saved reward, so nothing is granted twice.
func resume_run() -> void:
	var node := GameState.get_current_node()
	if node != null and node.type == MapNodeData.TYPE_EXIT and GameState.next_map_after_current() != "":
		go(Screen.ACT_TRANSITION)  # The run was saved between two acts.
		return
	if node == null or GameState.room_state.is_empty() or not GameState.room_matches(node.id, node.type):
		GameState.room_state = {}
		go(Screen.MAP)
		return
	if str(GameState.room_state.get("phase", "")) == "fight":
		go(Screen.COMBAT)  # An event that turned into a fight.
		return
	if str(GameState.room_state.get("phase", "")) == "reward" and GameState.pending_reward != null:
		go(Screen.REWARD)
		return
	open_room_screen(node)


## Leaves a service room (merchant, rest): back to the town hub when the node is a town, else the map.
func leave_service() -> void:
	var node := GameState.get_current_node()
	go(Screen.TOWN if node != null and node.type == MapNodeData.TYPE_TOWN else Screen.MAP)


## Opens the screen matching a map node's room type (no state changes).
func open_room_screen(node: MapNodeData) -> void:
	match node.type:
		MapNodeData.TYPE_COMBAT, MapNodeData.TYPE_ELITE, MapNodeData.TYPE_BOSS:
			go(Screen.COMBAT)
		MapNodeData.TYPE_TOWN:
			go(Screen.TOWN)
		MapNodeData.TYPE_TREASURE:
			go(Screen.TREASURE)
		MapNodeData.TYPE_REST:
			go(Screen.REST)
		MapNodeData.TYPE_MERCHANT:
			go(Screen.MERCHANT)
		MapNodeData.TYPE_EVENT:
			go(Screen.EVENT)
		MapNodeData.TYPE_EXIT:
			if GameState.next_map_after_current() != "":
				GameState.save_game()
				go(Screen.ACT_TRANSITION)  # The next act follows; the run continues.
			else:
				GameState.finish_run(GameState.RESULT_COMPLETED)
				go(Screen.RUN_END)
		_:
			go(Screen.MAP)
