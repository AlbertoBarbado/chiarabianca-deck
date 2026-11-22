extends SceneTree

const SimPolicy := preload("res://tests/combat/sim_policy.gd")
## Deterministic balance simulation (Milestone 7). A simple greedy policy plays full fights for
## every combination of the four playable specializations against the castle encounters over many
## fixed seeds, and prints win rate, average turns and remaining HP. It is a guard against obviously
## dominant or useless setups, not a substitute for play testing. Run:
##   godot --headless --path . --script res://tests/combat/balance_simulation.gd

const SEEDS := 60
const MAX_TURNS := 30
const ENCOUNTERS := ["castle_training_02", "castle_final_regular_01", "elite_commander_01", "elite_vanguard_01"]
const COAST := ["beach_crabs", "beach_shore_pair", "beach_spiders", "beach_crab_colony", "beach_scorpion_crab", "beach_salt_flats", "beach_dune_patrol", "beach_sea_raiders", "beach_albatross_flock", "beach_shark_patrol", "beach_storm_vanguard", "elite_sea_snake", "elite_rock_giant", "elite_sand_giant", "boss_sandstorm_elemental"]
const FOREST := ["forest_wolves_01", "forest_boar_01", "forest_harpies_01", "forest_wolf_harpy", "forest_bear_01", "forest_wisp_spiders", "forest_spider_ambush", "forest_troll_01", "forest_harpy_gorge", "forest_eagle_crag", "forest_last_hunt", "elite_alpha_pack", "elite_grove_warden", "elite_broodmother", "boss_forest_serpent"]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	DataRegistry.reload()
	var table: Dictionary = {}
	for chiara_spec in ["arcana", "fire", "frost", "wind"]:
		for bianca_spec in ["tanking", "holy", "ashveil", "venom"]:
			var line := "%s + %s" % [chiara_spec, bianca_spec]
			print("\n== %s ==" % line)
			for encounter in ENCOUNTERS:
				var stats := _run(chiara_spec, bianca_spec, encounter)
				table["%s|%s" % [line, encounter]] = stats
				print("  %-26s win %3d%%   turns %4.1f   party HP left %3d%%" % [encounter, roundi(stats["win_rate"] * 100.0), stats["turns"], roundi(stats["hp_left"] * 100.0)])
	# Forest act: the party is stronger by then (reward cards); the simulation adds the reward pools
	# to the decks and reports only (no assertions except that fights are not impossible).
	print("
== Forest (decks with reward pools, full HP per fight) ==")
	for chiara_spec in ["arcana", "fire", "frost", "wind"]:
		for bianca_spec in ["tanking", "holy", "ashveil", "venom"]:
			var parts: Array[String] = []
			for encounter in FOREST:
				var stats := _run(chiara_spec, bianca_spec, encounter, true)
				parts.append("%s %d%%/%d%%" % [encounter.replace("forest_", "").replace("elite_", "E:").replace("boss_", "B:"), roundi(stats["win_rate"] * 100.0), roundi(stats["hp_left"] * 100.0)])
				if encounter == "boss_forest_serpent":
					check(stats["win_rate"] >= 0.15, "%s + %s: the Forest Serpent is beatable" % [chiara_spec, bianca_spec])
					check(stats["win_rate"] <= 0.98 or stats["hp_left"] <= 0.6, "%s + %s: the Forest Serpent is dangerous" % [chiara_spec, bianca_spec])
			print("  %s + %s (win%% / HP left%%): %s" % [chiara_spec, bianca_spec, "  ".join(parts)])
	# Coast act (Act III): decks with reward pools; regular fights must be winnable, elites and the
	# Sandstorm Elemental beatable but costly.
	print("
== Sunlit Coast (decks with reward pools, full HP per fight) ==")
	for chiara_spec in ["arcana", "fire", "frost", "wind"]:
		for bianca_spec in ["tanking", "holy", "ashveil", "venom"]:
			var coast_parts: Array[String] = []
			for encounter in COAST:
				var stats := _run(chiara_spec, bianca_spec, encounter, true)
				coast_parts.append("%s %d%%/%d%%" % [encounter.replace("beach_", "").replace("elite_", "E:").replace("boss_", "B:"), roundi(stats["win_rate"] * 100.0), roundi(stats["hp_left"] * 100.0)])
				if encounter.begins_with("beach_"):
					check(stats["win_rate"] >= 0.85, "%s + %s: %s is winnable" % [chiara_spec, bianca_spec, encounter])
				elif encounter.begins_with("elite_"):
					check(stats["win_rate"] >= 0.5, "%s + %s: %s is beatable" % [chiara_spec, bianca_spec, encounter])
				else:
					check(stats["win_rate"] >= 0.15, "%s + %s: the Sandstorm Elemental is beatable" % [chiara_spec, bianca_spec])
					check(stats["win_rate"] <= 0.98 or stats["hp_left"] <= 0.6, "%s + %s: the Sandstorm Elemental is dangerous" % [chiara_spec, bianca_spec])
			print("  %s + %s (win%% / HP left%%): %s" % [chiara_spec, bianca_spec, "  ".join(coast_parts)])
	for key: String in table:
		var stats: Dictionary = table[key]
		if not key.contains("elite"):
			check(stats["win_rate"] >= 0.9, "%s: regular fights are winnable by the greedy policy" % key)
		else:
			var combo: String = key.split("|")[0]
			var regular: Dictionary = table[combo + "|castle_final_regular_01"]
			check(stats["hp_left"] <= regular["hp_left"] - 0.08, "%s: elites cost clearly more HP than the regular final fight" % key)
			check(stats["win_rate"] >= 0.6, "%s: elites remain beatable" % key)
	var best := 0.0
	var worst := 1.0
	for key: String in table:
		if key.ends_with("castle_final_regular_01"):
			best = maxf(best, table[key]["hp_left"])
			worst = minf(worst, table[key]["hp_left"])
	check(best - worst < 0.2, "all specialization pairings stay within 20 points of party HP left on the same fight")
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL ", label)


func _run(chiara_spec: String, bianca_spec: String, encounter_id: String, with_pools: bool = false) -> Dictionary:
	var wins := 0
	var turns := 0
	var hp_left := 0.0
	for seed_value in SEEDS:
		var party := Party.from_selection({"chiara": chiara_spec, "bianca": bianca_spec})
		if with_pools:
			for member in party.members:
				for card_id in member.specialization.card_pool:
					member.add_card(card_id)
		var cm := CombatManager.new()
		cm.setup(party, DataRegistry.get_encounter(encounter_id), Inventory.new(), seed_value + 1)
		cm.start()
		while cm.state == CombatManager.State.PLAYER_TURN and cm.turn < MAX_TURNS:
			_play_turn(cm)
			if cm.state == CombatManager.State.PLAYER_TURN:
				cm.end_player_turn()
		if cm.state == CombatManager.State.VICTORY:
			wins += 1
			var total := 0.0
			var max_total := 0.0
			for member in party.members:
				total += member.current_hp
				max_total += member.max_hp
			hp_left += total / max_total
		turns += cm.turn
	return {"win_rate": float(wins) / SEEDS, "turns": float(turns) / SEEDS, "hp_left": hp_left / maxf(1.0, wins)}


## Greedy: heal wounded allies, block when an attack is coming, otherwise the card with the most damage per energy.
func _play_turn(cm: CombatManager) -> void:
	SimPolicy.play_turn(cm)
