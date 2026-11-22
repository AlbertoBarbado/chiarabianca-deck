extends Node
## Global run state: the party, inventory and map progress of the current adventure.
## Gameplay rules live in their own classes; this node only holds and wires them together.

signal run_started
signal run_finished(result: String)

const RESULT_COMPLETED := "completed"
const RESULT_DEFEATED := "defeated"

var party: Party
var inventory: Inventory
var map_progress: MapProgress
var run_result: String = ""
## Card reward waiting to be resolved after a won combat (null when none).
var pending_reward: CardReward = null
## State of the room the party is currently inside ({} while on the map). Saved with the run so a
## quit inside a room resumes that room: {node_id, kind, ...room specific fields}. See docs/MAP_SYSTEM.md.
var room_state: Dictionary = {}
## Map used by the next new adventure (the Royal Castle unless the demo route was chosen).
var next_map_id: String = GameConfig.DEFAULT_MAP_ID
## Set by load_game: warnings about the loaded file (dropped content, backup used).
var load_warnings: Array[String] = []
## Run-wide facts that are saved with the run: {"seen_events": [ids], "completed_maps": [ids]}.
var run_flags: Dictionary = {}
## Location of the save file; tests point this elsewhere to protect real saves.
var save_path: String = GameConfig.SAVE_PATH
## character_id -> specialization_id while the player is choosing.
var selected_specializations: Dictionary = {}


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Saves the current run. Returns false if there is no run or writing failed.
func save_game() -> bool:
	if party == null or inventory == null or map_progress == null:
		return false
	return SaveManager.write_file(save_path, SaveManager.serialize(party, inventory, map_progress, room_state, pending_reward, run_flags))


## Loads the saved run into the global state. Returns "" on success or an error message.
func load_game() -> String:
	var read := SaveManager.read_file(save_path)
	if not read["ok"]:
		return str(read["error"])
	var restored := SaveManager.restore(read["data"])
	if not restored["ok"]:
		return str(restored["error"])
	load_warnings.clear()
	for warning: String in restored["warnings"]:
		push_warning("Save: " + warning)
		load_warnings.append(warning)
	if bool(read.get("from_backup", false)):
		load_warnings.append("The main save was damaged; the previous backup was loaded.")
	party = restored["party"]
	inventory = restored["inventory"]
	map_progress = restored["progress"]
	room_state = restored["room"]
	run_flags = restored["flags"]
	pending_reward = restored["reward"]
	run_result = ""
	run_started.emit()
	return ""


func delete_save() -> void:
	for path in [save_path, save_path + ".bak", save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- Room state (what the party is doing right now) --------------------------

## Called when the party enters a room: records it and saves, so quitting inside the room resumes it.
func begin_room(node: MapNodeData) -> void:
	room_state = {"node_id": node.id, "kind": node.type}
	save_game()


## Merges fields into the current room state and saves. Call after every important change.
func update_room(patch: Dictionary) -> void:
	room_state.merge(patch, true)
	save_game()


## The encounter of the current room: an event may turn into a fight (room state), otherwise the node's own.
func current_encounter_id() -> String:
	var node := get_current_node()
	var override := str(room_state.get("encounter_id", ""))
	return override if override != "" else (node.encounter_id if node != null else "")


## Town definition of the current node ({} when it is not a town).
func current_town() -> Dictionary:
	var node := get_current_node()
	return DataRegistry.get_town(node.town_id) if node != null and node.type == MapNodeData.TYPE_TOWN else {}


func current_shop_id() -> String:
	var node := get_current_node()
	var town := current_town()
	return str(town.get("shop_id", "")) if not town.is_empty() else (node.shop_id if node != null else "")


## Share of max HP a rest restores here: the town's or the rest node's "heal_percent", else the default.
func current_heal_fraction() -> float:
	var node := get_current_node()
	var town := current_town()
	var source: Dictionary = town if not town.is_empty() else (node.raw if node != null else {})
	return float(source.get("heal_percent", GameConfig.DEFAULT_REST_HEAL_FRACTION * 100.0)) / 100.0


## True while the party is inside the room of this node (any kind: a town hosts a merchant and a rest).
func in_room(node_id: String) -> bool:
	return str(room_state.get("node_id", "")) == node_id


func mark_event_seen(event_id: String) -> void:
	if event_id == "":
		return
	var seen: Array = run_flags.get("seen_events", [])
	if not seen.has(event_id):
		seen.append(event_id)
	run_flags["seen_events"] = seen


## Rolls a card reward for a non-combat source (events) and saves it with the room's reward phase.
func start_card_reward(patch: Dictionary = {}) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	pending_reward = CardReward.generate(party, rng)
	room_state.merge(patch, true)
	room_state["phase"] = "reward"
	save_game()


# --- Acts ---------------------------------------------------------------------------------------

## Map that follows the current one in the run ("" when this is the last act or a standalone map).
func next_map_after_current() -> String:
	if map_progress == null:
		return ""
	var order: Array = RunRules.get_block("acts").get("order", [])
	var index := order.find(map_progress.graph.id)
	return str(order[index + 1]) if index >= 0 and index + 1 < order.size() else ""


## Moves the run to the next act's map. Party, HP, decks, upgrades, gold, items and relics are
## untouched; only the map progress is replaced. Saves at the new entrance.
func advance_to_next_map() -> bool:
	var next_id := next_map_after_current()
	if next_id == "" or party == null:
		return false
	var graph := MapGraph.from_dict(DataRegistry.get_map(next_id))
	if not graph.validate().is_empty():
		push_error("GameState: next map '%s' is invalid" % next_id)
		return false
	var completed: Array = run_flags.get("completed_maps", [])
	if not completed.has(map_progress.graph.id):
		completed.append(map_progress.graph.id)
	run_flags["completed_maps"] = completed
	heal_between_acts(party)
	map_progress = MapProgress.new(graph)
	room_state = {}
	pending_reward = null
	save_game()
	return true


## Reaching the next act restores run_rules acts.heal_between_acts of every member's max HP (fallen
## members rise with it): beating an act's boss is rewarded, and the next act starts fair.
static func heal_between_acts(p_party: Party) -> void:
	var share := float(RunRules.get_block("acts").get("heal_between_acts", 0.0))
	if p_party == null or share <= 0.0:
		return
	for member in p_party.members:
		var amount := maxi(1, roundi(member.max_hp * share))
		if member.is_alive():
			member.heal(amount)
		else:
			member.revive(amount)


## The room state belongs to this node and kind (and not to a stale earlier room).
func room_matches(node_id: String, kind: String) -> bool:
	return str(room_state.get("node_id", "")) == node_id and str(room_state.get("kind", "")) == kind


## Leaves the room (back to the map) and saves the finished state.
func end_room() -> void:
	room_state = {}
	pending_reward = null
	save_game()


## Applies the outcome of a won combat exactly once: gold, relic healing and the reward roll are
## saved together with the "reward" phase, so reloading shows the SAME reward and grants nothing twice.
func record_combat_victory(gold: int, encounter: Dictionary) -> void:
	var node := get_current_node()
	if node == null or str(room_state.get("phase", "")) == "reward":
		return  # Already recorded (e.g. after a reload).
	inventory.add_gold(gold)
	var heal := RelicEffects.total(inventory, "heal_after_victory")
	if heal > 0:
		for member in party.get_living_members():
			member.heal(heal)
	var rules: Dictionary = {}
	if bool(encounter.get("elite", false)):
		rules = RunRules.get_block("elite_defaults")
	if encounter.get("reward", {}) is Dictionary and not (encounter.get("reward", {}) as Dictionary).is_empty():
		rules = encounter["reward"]  # e.g. the boss: its own reward rules
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	pending_reward = CardReward.generate(party, rng, CardReward.OPTION_COUNT, rules)
	# Equipment drop: rolled once, put straight into the stash and remembered for the reward screen.
	var source := "boss" if bool(encounter.get("boss", false)) else ("elite" if bool(encounter.get("elite", false)) else "combat")
	var loot := Loot.roll(source, party, rng)
	for item_id in loot:
		inventory.add_equipment(item_id)
	# Relics (run_rules "relics"): an elite always leaves one; a boss offers a choice of boss relics.
	var relic_rules: Dictionary = RunRules.get_block("relics")
	var relics_found: Array[String] = []
	if source == "elite":
		var relic_id := RelicEffects.roll(rng, relic_rules.get("elite_weights", {"common": 5, "uncommon": 3, "rare": 1}), inventory)
		if relic_id != "" and RelicEffects.gain(relic_id, party, inventory):
			relics_found.append(relic_id)
	var boss_choices: Array[String] = []
	if source == "boss":
		boss_choices = RelicEffects.boss_choices(rng, inventory, int(relic_rules.get("boss_choices", 3)))
	room_state = {"node_id": node.id, "kind": node.type, "phase": "reward", "gold": gold, "elite": bool(encounter.get("elite", false)), "boss": bool(encounter.get("boss", false)), "loot": loot,
		"relics": relics_found, "relic_choices": boss_choices, "relic_taken": ""}
	save_game()


## Takes one of the boss relics offered by the reward just won (once). Returns false otherwise.
func take_boss_relic(relic_id: String) -> bool:
	var choices: Array = room_state.get("relic_choices", [])
	if not choices.has(relic_id) or str(room_state.get("relic_taken", "")) != "":
		return false
	if not RelicEffects.gain(relic_id, party, inventory):
		return false
	room_state["relic_taken"] = relic_id
	save_game()
	return true


## Rolls the card reward for the combat that was just won.
func prepare_card_reward() -> void:
	if pending_reward != null:
		return  # Keep the reward that was rolled (and saved) already.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	pending_reward = CardReward.generate(party, rng)


func reset_selection() -> void:
	selected_specializations.clear()
	party = null


func select_specialization(character_id: String, spec_id: String) -> void:
	selected_specializations[character_id] = spec_id


func can_confirm_selection() -> bool:
	for character_id in GameConfig.INITIAL_PARTY_IDS:
		var spec := DataRegistry.get_specialization(str(selected_specializations.get(character_id, "")))
		if spec == null or not spec.is_playable():
			return false
	return true


## Builds the party (with individual decks) from the current selection.
func create_party_from_selection() -> bool:
	if not can_confirm_selection():
		return false
	party = Party.from_selection(selected_specializations)
	return true


## Starts the adventure on the default map using the already created party.
func begin_adventure(map_id: String = "") -> bool:
	if map_id == "":
		map_id = next_map_id
	var graph := MapGraph.from_dict(DataRegistry.get_map(map_id))
	var problems := graph.validate()
	if party == null or not problems.is_empty():
		push_error("GameState: cannot begin adventure: %s" % ", ".join(problems))
		return false
	inventory = Inventory.new()
	inventory.gold = GameConfig.STARTING_GOLD
	map_progress = MapProgress.new(graph)
	room_state = {}
	run_flags = {}
	pending_reward = null
	run_result = ""
	run_started.emit()
	return true


func get_current_node() -> MapNodeData:
	if map_progress == null:
		return null
	return map_progress.graph.get_node_data(map_progress.current_node_id)


func finish_run(result: String) -> void:
	run_result = result
	pending_reward = null
	room_state = {}
	delete_save()  # A finished run cannot be continued.
	run_finished.emit(result)
