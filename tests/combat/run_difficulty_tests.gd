extends SceneTree
## Difficulty scaling (run_rules "difficulty"): enemy HP at spawn and attack intents when planned,
## with extra factors for elite and boss fights. Run:
##   godot --headless --path . --script res://tests/combat/run_difficulty_tests.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	DamageTypes.reload()
	_test_scaling()
	_test_rules()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _combat(flags: Dictionary) -> CombatManager:
	var encounter := {"id": "qa", "name": "QA", "enemies": ["forest_troll"], "gold_reward": 0}
	encounter.merge(flags)
	var cm := CombatManager.new()
	cm.setup(Party.from_selection({"chiara": "fire", "bianca": "tanking"}), encounter, Inventory.new(), 7)
	return cm


func _first_attack(cm: CombatManager) -> int:
	cm.start()
	var enemy: Combatant = cm.enemies[0]
	for i in 6:  # walk the pattern until an attack is planned
		if enemy.intent != null and enemy.intent.type == EnemyIntent.TYPE_ATTACK:
			return enemy.intent.value
		cm._plan_intents()
	return -1


func _test_scaling() -> void:
	var def := DataRegistry.get_enemy("forest_troll")
	var plain := _combat({})
	plain._apply_difficulty({})
	check(plain.enemies[0].max_hp == def.max_hp and plain.enemies[0].hp == def.max_hp, "1.0 everywhere keeps the data's HP (%d)" % def.max_hp)
	var base_attack := _first_attack(plain)

	var elite := _combat({"elite": true})
	elite._apply_difficulty({"elite_hp": 1.5, "elite_damage": 2.0})
	check(elite.enemies[0].max_hp == roundi(def.max_hp * 1.5) and elite.enemies[0].hp == elite.enemies[0].max_hp, "an elite fight scales HP (x1.5 = %d)" % elite.enemies[0].max_hp)
	check(_first_attack(elite) == roundi(base_attack * 2.0), "and the attack shown on the intent (%d -> %d)" % [base_attack, roundi(base_attack * 2.0)])

	var boss := _combat({"boss": true})
	boss._apply_difficulty({"enemy_hp": 2.0, "boss_hp": 1.5, "elite_hp": 9.0})
	check(boss.enemies[0].max_hp == roundi(def.max_hp * 3.0), "boss factors multiply the global one, elite factors stay out (x3)")

	var normal := _combat({})
	normal._apply_difficulty({"elite_hp": 9.0, "boss_hp": 9.0})
	check(normal.enemies[0].max_hp == def.max_hp, "a normal fight ignores the elite and boss factors")


func _test_rules() -> void:
	var rules := RunRules.get_block("difficulty")
	check(float(rules.get("enemy_hp", 0)) > 0.0 and float(rules.get("enemy_damage", 0)) > 0.0, "run_rules defines the global difficulty")
	check(float(rules.get("boss_hp", 1.0)) >= float(rules.get("elite_hp", 1.0)) and float(rules.get("elite_hp", 1.0)) >= 1.0, "bosses are scaled at least as hard as elites")
