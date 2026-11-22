extends Node
## Room/screen transitions. The Main scene registers a host Control; screens are swapped
## inside it so transitions can share a fade and a theme.

signal screen_changed(screen: Screen)

enum Screen {
	MAIN_MENU, SETTINGS, CHARACTER_SELECTION, SPECIALIZATION_SELECTION, PARTY_OVERVIEW,
	MAP, REST, MERCHANT, EVENT, COMBAT, REWARD, RUN_END, TREASURE, TOWN, ACT_TRANSITION, EQUIPMENT,
	CASTLE_HUB, WORLD_MAP, EXPEDITION_PREP, EXPEDITION_RESULTS, CASTLE_SERVICE,
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
	Screen.CASTLE_HUB: "res://scenes/castle/castle_hub.tscn",
	Screen.WORLD_MAP: "res://scenes/castle/world_map.tscn",
	Screen.EXPEDITION_PREP: "res://scenes/castle/expedition_prep.tscn",
	Screen.EXPEDITION_RESULTS: "res://scenes/castle/expedition_results.tscn",
	Screen.CASTLE_SERVICE: "res://scenes/castle/castle_service.tscn",
}
const FADE_TIME := 0.18

var current_screen: Node = null
var current_screen_id: Screen = Screen.MAIN_MENU
var _host: Control = null
## Screen the equipment screen returns to (map, town or reward).
var equipment_return: Screen = Screen.MAP
## Castle service the CASTLE_SERVICE shell shows (data/castle id), and the mission the preparation
## screen prepares (set by open_service / open_preparation).
var service_id: String = ""
var mission_id: String = ""
## Region the world map opens on ("" = the first open one).
var world_region_id: String = ""
## Screen the settings screen returns to (the main menu or the castle).
var settings_return: Screen = Screen.MAIN_MENU


func open_settings(from: Screen) -> void:
	settings_return = from
	go(Screen.SETTINGS)


## Opens one castle service (Deck Workshop, Upgrade Workshop, ...) in the shared service shell.
func open_service(p_service_id: String) -> void:
	service_id = p_service_id
	go(Screen.CASTLE_SERVICE)


func open_preparation(p_mission_id: String) -> void:
	mission_id = p_mission_id
	go(Screen.EXPEDITION_PREP)


## After a run ends: the expedition results (campaign) or the classic completion / defeat screen.
func go_to_run_end() -> void:
	go(Screen.EXPEDITION_RESULTS if GameState.expedition != null else Screen.RUN_END)


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
	if GameState.in_castle():
		go(Screen.CASTLE_HUB)
		return
	if GameState.expedition != null and GameState.expedition.is_finished():
		go(Screen.EXPEDITION_RESULTS)  # Ended but not yet back home: show the results again.
		return
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
			if GameState.expedition != null:
				GameState.finish_expedition(Objectives.outcome_at_exit(GameState.expedition.objective))
				go(Screen.EXPEDITION_RESULTS)
			elif GameState.next_map_after_current() != "":
				GameState.save_game()
				go(Screen.ACT_TRANSITION)  # The next act follows; the run continues.
			else:
				GameState.finish_run(GameState.RESULT_COMPLETED)
				go(Screen.RUN_END)
		_:
			go(Screen.MAP)
