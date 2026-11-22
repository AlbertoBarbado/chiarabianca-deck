class_name Combatant
extends RefCounted
## Runtime combat participant (party member or enemy): health, block and statuses.
## Pure logic, no UI. Party combatants use the character id as their id.

const SIDE_PARTY := "party"
const SIDE_ENEMY := "enemy"

var id: String = ""
var display_name: String = ""
var side: String = SIDE_ENEMY
var max_hp: int = 1
var hp: int = 1
var block: int = 0
## status_id -> {"stacks": int, "source_id": String}
var statuses: Dictionary = {}
var enemy_def: EnemyDef = null
var intent: EnemyIntent = null
var ai_cursor: int = 0
var enraged: bool = false
var accent_color: Color = Color("c9d1dc")
## Party members only: the chosen specialization (presentation picks its pose set, if any).
var specialization_id: String = ""
## Damage taken modifier per element in percent: + = weakness, - = resistance (enemy data, armour).
var affinity: Dictionary = {}
## Damage dealt bonus per element in percent (weapons).
var damage_bonus: Dictionary = {}
## Enemies: multiplier on the value of their attack intents (run_rules "difficulty"; 1 = as in data).
var damage_scale: float = 1.0
## Enemies act in initiative order (highest first). Chill lowers it; at 0 or less the enemy is Frozen
## and loses its next action. Party members do not use initiative.
var base_initiative: int = 0
## Status ids this combatant never receives (equipment such as the Kelpwoven Coat).
var immunities: Array[String] = []
## Powers played this combat (party members): [{id, name, description, count}] for the UI.
var powers: Array[Dictionary] = []
## From powers: extra damage on every damage effect of this combatant's cards, and extra Block on
## every Block effect of them (like Strength and Dexterity). Combat only.
var power_damage: int = 0
var power_block: int = 0


func is_alive() -> bool:
	return hp > 0


## Applies damage through block first (unless ignore_block). Returns the HP actually lost.
func take_damage(amount: int, ignore_block: bool = false) -> int:
	var remaining := maxi(0, amount)
	if not ignore_block:
		var absorbed := mini(block, remaining)
		block -= absorbed
		remaining -= absorbed
	var lost := mini(hp, remaining)
	hp -= lost
	return lost


## Healing never revives: a fallen combatant stays at 0 HP.
func heal(amount: int) -> int:
	if hp <= 0:
		return 0
	var before := hp
	hp = mini(max_hp, hp + maxi(0, amount))
	return hp - before


func add_block(amount: int) -> void:
	block += maxi(0, amount)


func add_status(status_id: String, stacks: int, source_id: String = "") -> void:
	if immunities.has(status_id):
		return
	var current: Dictionary = statuses.get(status_id, {"stacks": 0, "source_id": source_id})
	current["stacks"] = int(current["stacks"]) + stacks
	var status_def := DataRegistry.get_status(status_id)
	if status_def != null and status_def.max_stacks > 0:
		current["stacks"] = mini(int(current["stacks"]), status_def.max_stacks)
	current["source_id"] = source_id
	statuses[status_id] = current


## Initiative after statuses that lower it (Chill: -1 per stack).
func initiative() -> int:
	var value := base_initiative
	for status_id: String in statuses:
		var status_def := DataRegistry.get_status(status_id)
		if status_def != null and status_def.initiative_per_stack != 0:
			value += status_def.initiative_per_stack * int(statuses[status_id]["stacks"])
	return value


## True when this enemy will be Frozen (skip its action) at the start of the next enemy phase.
func will_freeze() -> bool:
	return side == SIDE_ENEMY and is_alive() and has_initiative_status() and initiative() <= 0


func has_initiative_status() -> bool:
	for status_id: String in statuses:
		var status_def := DataRegistry.get_status(status_id)
		if status_def != null and status_def.initiative_per_stack != 0:
			return true
	return false


## Extra damage taken (percent) of an element from statuses, e.g. Chill: +10% physical per stack.
func status_vulnerability(element: String) -> int:
	var pct := 0
	for status_id: String in statuses:
		var status_def := DataRegistry.get_status(status_id)
		if status_def != null and status_def.vulnerable_elements.has(element):
			pct += status_def.vulnerable_per_stack * int(statuses[status_id]["stacks"])
	return pct


## Change to the damage this combatant's attacks deal, in percent, from statuses (Sandblind: -25).
func damage_dealt_pct() -> int:
	var pct := 0
	for status_id: String in statuses:
		var status_def := DataRegistry.get_status(status_id)
		if status_def != null:
			pct += status_def.damage_dealt_pct
	return pct


func has_status(status_id: String) -> bool:
	return statuses.has(status_id)


func get_status_source(status_id: String) -> String:
	return str((statuses.get(status_id, {}) as Dictionary).get("source_id", ""))


## All statuses currently decay by one stack per round.
func tick_statuses() -> void:
	for status_id in statuses.keys():
		var status_def := DataRegistry.get_status(status_id)
		if status_def != null and status_def.decay == "on_trigger":
			continue  # e.g. Bleed: only its own trigger uses it up
		statuses[status_id]["stacks"] -= 1
		if statuses[status_id]["stacks"] <= 0:
			statuses.erase(status_id)


## Removes statuses, block and intent (used when a combatant falls and when combat ends).
func clear_combat_state() -> void:
	statuses.clear()
	block = 0
	intent = null
