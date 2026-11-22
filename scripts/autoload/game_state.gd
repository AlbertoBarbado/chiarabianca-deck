extends Node
## Global run state: the party, inventory and map progress of the current adventure.
## Gameplay rules live in their own classes; this node only holds and wires them together.
##
## Two modes (docs/PERSISTENT_RPG_DESIGN.md):
##  * Campaign: `campaign` holds everything permanent. At the castle `party` is the campaign roster
##    and `inventory` its vault (so the equipment screen works there); during an expedition they are
##    the expedition's copies and `expedition` holds the mission, objective and outcome.
##  * Quick Play (classic): `campaign` is null and a run behaves exactly as before this milestone.

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
## Location of the save file; tests point this elsewhere to protect real saves. Reads the path of the
## active slot: the campaign slot is the path that was set, the Quick Play slot sits beside it
## ("<name>_quickplay.json"), so a Quick Play run never overwrites the campaign.
var save_path: String:
	get:
		return slot_path(_slot)
	set(value):
		_campaign_path = value
		_slot = SLOT_CAMPAIGN
const SLOT_CAMPAIGN := "campaign"
const SLOT_QUICKPLAY := "quickplay"
var _campaign_path: String = GameConfig.SAVE_PATH
var _slot: String = SLOT_CAMPAIGN
## What the next New Game flow builds: "campaign" (castle) or "classic" (Quick Play run). The main menu
## sets it; "classic" is the default so screens opened directly keep their classic behaviour.
var new_game_mode: String = "classic"


func slot_path(slot: String) -> String:
	return _campaign_path if slot == SLOT_CAMPAIGN else _campaign_path.get_basename() + "_" + SLOT_QUICKPLAY + ".json"


func use_slot(slot: String) -> void:
	_slot = SLOT_QUICKPLAY if slot == SLOT_QUICKPLAY else SLOT_CAMPAIGN


func active_slot() -> String:
	return _slot


func slot_has_save(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))
## character_id -> specialization_id while the player is choosing.
var selected_specializations: Dictionary = {}
## The persistent campaign (null in Quick Play).
var campaign: CampaignState = null
## The expedition under way (null at the castle and in Quick Play).
var expedition: ExpeditionState = null


func in_campaign() -> bool:
	return campaign != null


func in_castle() -> bool:
	return campaign != null and expedition == null


## A new campaign from the specialization chosen for each sister; the party goes home to the castle.
func start_campaign() -> bool:
	if not can_confirm_selection():
		return false
	campaign = CampaignState.create(selected_specializations)
	expedition = null
	enter_castle()
	return true


## The castle state: roster and vault are the active party and inventory; no map, no room.
func enter_castle() -> void:
	if campaign == null:
		return
	expedition = null
	campaign.refresh_roster()
	Bond.apply_unlocks(campaign)
	party = campaign.roster
	inventory = campaign.vault
	map_progress = null
	room_state = {}
	run_flags = {}
	pending_reward = null
	run_result = ""
	save_game()


## Ends the expedition with an outcome (ExpeditionState.OUTCOME_*) and applies its rewards once.
func finish_expedition(outcome: String) -> Dictionary:
	return ExpeditionService.finish(outcome)


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Saves the campaign (with the expedition under way, if any) or the Quick Play run. Returns false if
## there is nothing to save or writing failed.
func save_game() -> bool:
	if campaign != null:
		var data := {"version": SaveManager.SAVE_VERSION}
		if expedition != null and party != null and inventory != null and map_progress != null:
			data = SaveManager.serialize(party, inventory, map_progress, room_state, pending_reward, run_flags)
			data["expedition"] = expedition.to_dict()
		data["mode"] = "campaign"
		data["campaign"] = campaign.to_dict()
		return SaveManager.write_file(save_path, data)
	if party == null or inventory == null or map_progress == null:
		return false
	var run := SaveManager.serialize(party, inventory, map_progress, room_state, pending_reward, run_flags)
	run["mode"] = "classic"
	return SaveManager.write_file(save_path, run)


## Loads the saved run into the global state. Returns "" on success or an error message.
func load_game() -> String:
	var read := SaveManager.read_file(save_path)
	if not read["ok"]:
		return str(read["error"])
	load_warnings.clear()
	var data: Variant = read["data"]
	if data is Dictionary and int((data as Dictionary).get("version", 0)) > SaveManager.SAVE_VERSION:
		return "Save was made by a newer version of the game."
	if data is Dictionary and (data as Dictionary).has("campaign"):
		var error := _load_campaign(data)
		if error == "" and bool(read.get("from_backup", false)):
			load_warnings.append("The main save was damaged; the previous backup was loaded.")
		return error
	var restored := SaveManager.restore(data)
	if not restored["ok"]:
		return str(restored["error"])
	for warning: String in restored["warnings"]:
		push_warning("Save: " + warning)
		load_warnings.append(warning)
	if bool(read.get("from_backup", false)):
		load_warnings.append("The main save was damaged; the previous backup was loaded.")
	campaign = null
	expedition = null
	Equipment.refinement = {}
	Requirements.active_campaign = null
	# A run saved before the campaign existed (no "mode") becomes a campaign: the run continues as an
	# expedition and returns to the castle when it ends (CampaignMigration).
	if data is Dictionary and not (data as Dictionary).has("mode"):
		var migrated := CampaignMigration.from_legacy_run(restored)
		campaign = migrated["campaign"]
		expedition = migrated["expedition"]
		load_warnings.append("Your adventure was moved into the new campaign: finish it to return to the castle.")
	party = restored["party"]
	inventory = restored["inventory"]
	map_progress = restored["progress"]
	room_state = restored["room"]
	run_flags = restored["flags"]
	pending_reward = restored["reward"]
	run_result = ""
	run_started.emit()
	if campaign != null:
		save_game()  # Rewrite a migrated save in the campaign format at once.
	return ""


## Restores a campaign save: the campaign, and the expedition when one is under way.
func _load_campaign(data: Dictionary) -> String:
	var warnings: Array[String] = []
	var result := {"error": ""}
	var loaded := CampaignState.from_dict(data.get("campaign", {}), warnings, result)
	if loaded == null:
		return str(result["error"]) if str(result["error"]) != "" else "The campaign could not be loaded."
	campaign = loaded
	expedition = null
	room_state = {}
	run_flags = {}
	pending_reward = null
	run_result = ""
	if data.has("party"):
		var restored := SaveManager.restore(data)
		if restored["ok"]:
			warnings.append_array(restored["warnings"])
			party = restored["party"]
			inventory = restored["inventory"]
			map_progress = restored["progress"]
			room_state = restored["room"]
			run_flags = restored["flags"]
			pending_reward = restored["reward"]
			expedition = ExpeditionState.from_dict(data.get("expedition", {}), warnings)
		else:
			# The expedition is beyond repair: the sisters make it home; the campaign is kept.
			warnings.append("The expedition could not be restored (%s); the sisters returned to the castle." % restored["error"])
	for warning in warnings:
		push_warning("Save: " + warning)
		load_warnings.append(warning)
	if expedition == null:
		enter_castle()
	else:
		Bond.apply_unlocks(campaign)
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
	if map_progress == null or expedition != null:
		return ""  # An expedition is one mission: its exit leads home, never to another act.
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
func record_combat_victory(gold: int, encounter: Dictionary, reactions: int = 0) -> void:
	var node := get_current_node()
	if node == null or str(room_state.get("phase", "")) == "reward":
		return  # Already recorded (e.g. after a reload).
	ExpeditionService.on_combat_won(node, encounter, reactions)
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
	campaign = null  # A classic (Quick Play) run.
	expedition = null
	Equipment.refinement = {}
	Requirements.active_campaign = null
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
	if campaign != null and expedition != null:
		# Campaign: the expedition ends and the results screen leads home; nothing is deleted.
		finish_expedition(ExpeditionState.OUTCOME_COMPLETED if result == RESULT_COMPLETED else ExpeditionState.OUTCOME_DEFEATED)
		run_finished.emit(result)
		return
	delete_save()  # A finished run cannot be continued.
	run_finished.emit(result)
