class_name EnemyAI
extends RefCounted
## Enemy behaviour: walks the enemy's data-defined action pattern and picks targets.

const STATUS_TAUNT := "taunt"


static func plan_intent(enemy: Combatant, living_party: Array[Combatant], rng: RandomNumberGenerator) -> EnemyIntent:
	var def := enemy.enemy_def
	if def == null or def.pattern.is_empty():
		return null
	var pattern := def.pattern
	if not def.enraged_pattern.is_empty() and enemy.hp <= int(enemy.max_hp * def.enrage_below):
		if not enemy.enraged:  # the enraged pattern starts from its first action
			enemy.enraged = true
			enemy.ai_cursor = 0
		pattern = def.enraged_pattern
	var action_id := pattern[enemy.ai_cursor % pattern.size()]
	enemy.ai_cursor += 1
	var action: Dictionary = def.actions.get(action_id, {})
	var intent := EnemyIntent.new()
	intent.action_id = action_id
	intent.action_name = str(action.get("name", action_id))
	intent.type = str(action.get("type", EnemyIntent.TYPE_ATTACK))
	intent.value = int(action.get("value", 0))
	var rider: Dictionary = action.get("status", {}) if action.get("status", {}) is Dictionary else {}
	intent.status_id = str(rider.get("id", ""))
	intent.status_value = int(rider.get("value", 0))
	intent.hits_all = str(action.get("target", "")) == "all"
	intent.element = DamageTypes.normalize(str(action.get("element", def.element)))
	if intent.type == EnemyIntent.TYPE_ATTACK and not living_party.is_empty():
		intent.planned_target_id = living_party[rng.randi_range(0, living_party.size() - 1)].id
	return intent


## Resolves who an attack actually hits: a living taunter wins, then the planned target.
static func resolve_target(enemy: Combatant, party_combatants: Array[Combatant]) -> Combatant:
	var taunter_id := enemy.get_status_source(STATUS_TAUNT) if enemy.has_status(STATUS_TAUNT) else ""
	var preferred := [taunter_id, enemy.intent.planned_target_id if enemy.intent != null else ""]
	for wanted_id: String in preferred:
		for candidate in party_combatants:
			if candidate.id == wanted_id and candidate.is_alive():
				return candidate
	for candidate in party_combatants:
		if candidate.is_alive():
			return candidate
	return null
