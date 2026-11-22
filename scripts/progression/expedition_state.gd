class_name ExpeditionState
extends RefCounted
## Facts about the current expedition that the classic run state does not already hold
## (docs/PERSISTENT_RPG_DESIGN.md §3.2). The party, inventory, map progress, room state and pending
## reward stay in GameState exactly as in a classic run.

const OUTCOME_NONE := ""
const OUTCOME_COMPLETED := "completed"
const OUTCOME_RETREATED := "retreated"
const OUTCOME_DEFEATED := "defeated"
const OUTCOMES := [OUTCOME_COMPLETED, OUTCOME_RETREATED, OUTCOME_DEFEATED]

var mission_id: String = ""
var region_id: String = ""
var seed: int = 0
## The map actually played (rerolled contents or a generated map) is saved with the map progress
## (MapGraph.custom_def / custom_layout, see SaveManager), so a reload shows the same expedition.
## Objective: {type, required, progress, done_nodes: [node ids]} (see Objectives).
var objective: Dictionary = {}
## Collection uids each sister took along (character_id -> [uids]); cards in the expedition deck
## that are not listed here were drafted during the expedition (discoveries).
var departure_uids: Dictionary = {}
## Capped Sister Bond sources counted this expedition ({twin_reaction: n, event: n}) and the XP earned.
var bond_counts: Dictionary = {}
var bond_xp: int = 0
var bosses_defeated: int = 0
var outcome: String = OUTCOME_NONE
## Set once the outcome's rewards were applied to the campaign (never twice, even after a reload).
var rewards_claimed: bool = false
## What the results screen shows: {gold_in, gold_kept, essence, unlocks: [texts], loot: [ids], ...}.
var results: Dictionary = {}
## Discovery choice: offered cards [{card_id, owner_character_id, upgrade_level}], how many may be
## kept, and whether the choice was made.
var discoveries: Array = []
var discoveries_allowed: int = 0
var discoveries_claimed: bool = false


func is_finished() -> bool:
	return outcome != OUTCOME_NONE


func mission() -> Dictionary:
	return DataRegistry.get_mission(mission_id)


func to_dict() -> Dictionary:
	return {
		"mission_id": mission_id, "region_id": region_id, "seed": seed,
		"objective": objective.duplicate(true), "departure_uids": departure_uids.duplicate(true),
		"bond_counts": bond_counts.duplicate(), "bond_xp": bond_xp, "bosses_defeated": bosses_defeated,
		"outcome": outcome, "rewards_claimed": rewards_claimed, "results": results.duplicate(true),
		"discoveries": discoveries.duplicate(true), "discoveries_allowed": discoveries_allowed,
		"discoveries_claimed": discoveries_claimed,
	}


static func from_dict(data: Variant, warnings: Array[String]) -> ExpeditionState:
	var state := ExpeditionState.new()
	if not data is Dictionary:
		return state
	var raw: Dictionary = data
	state.mission_id = str(raw.get("mission_id", ""))
	if state.mission_id != "" and DataRegistry.get_mission(state.mission_id).is_empty():
		warnings.append("Unknown mission '%s'; the expedition continues without its objective." % state.mission_id)
		state.mission_id = ""
	state.region_id = str(raw.get("region_id", ""))
	state.seed = int(raw.get("seed", 0))
	state.objective = raw.get("objective", {}) if raw.get("objective", {}) is Dictionary else {}
	state.departure_uids = raw.get("departure_uids", {}) if raw.get("departure_uids", {}) is Dictionary else {}
	state.bond_counts = raw.get("bond_counts", {}) if raw.get("bond_counts", {}) is Dictionary else {}
	state.bond_xp = maxi(0, int(raw.get("bond_xp", 0)))
	state.bosses_defeated = maxi(0, int(raw.get("bosses_defeated", 0)))
	state.outcome = str(raw.get("outcome", "")) if OUTCOMES.has(str(raw.get("outcome", ""))) else OUTCOME_NONE
	state.rewards_claimed = bool(raw.get("rewards_claimed", false))
	state.results = raw.get("results", {}) if raw.get("results", {}) is Dictionary else {}
	state.discoveries = raw.get("discoveries", []) if raw.get("discoveries", []) is Array else []
	state.discoveries_allowed = maxi(0, int(raw.get("discoveries_allowed", 0)))
	state.discoveries_claimed = bool(raw.get("discoveries_claimed", false))
	return state
