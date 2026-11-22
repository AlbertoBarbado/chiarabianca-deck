class_name EnemyDef
extends RefCounted
## Static enemy definition (data/enemies). Behaviour is a repeating pattern of named actions.

var id: String = ""
var display_name: String = ""
var max_hp: int = 1
var color: Color = Color("8d9db0")
## action_id -> {name, type ("attack"|"defend"), value}
var actions: Dictionary = {}
var pattern: Array[String] = []
var art_path: String = ""
## Elite enemies get a visual treatment (gold aura, "ELITE" tag); their stats are plain data.
var elite: bool = false
## Bosses get their own presentation (large sprite, BOSS banner); stats and actions are plain data.
var boss: bool = false
## Optional second pattern used once HP is at or below enrage_below (share of max HP, 0 = never).
var enraged_pattern: Array[String] = []
var enrage_below: float = 0.0
## Percent modifiers to damage taken per element: weaknesses (+) and resistances (-).
var weaknesses: Dictionary = {}
var resistances: Dictionary = {}
## Turn order in the enemy phase (highest first). Chill lowers it; at 0 the enemy is Frozen.
var initiative: int = 3
## Damage type of its attacks unless an action names its own ("element").
var element: String = "physical"


static func from_dict(data: Dictionary) -> EnemyDef:
	var def := EnemyDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("name", def.id))
	def.max_hp = int(data.get("max_hp", 1))
	def.color = Color.from_string(str(data.get("color", "")), def.color)
	def.actions = (data.get("actions", {}) as Dictionary).duplicate(true)
	def.pattern.assign(data.get("pattern", []))
	def.art_path = str(data.get("art_path", ""))
	def.elite = bool(data.get("elite", false))
	def.boss = bool(data.get("boss", false))
	def.enraged_pattern.assign(data.get("enraged_pattern", []))
	def.enrage_below = float(data.get("enrage_below", 0.0))
	def.weaknesses = (data.get("weaknesses", {}) as Dictionary).duplicate()
	def.resistances = (data.get("resistances", {}) as Dictionary).duplicate()
	def.initiative = int(data.get("initiative", 3))
	def.element = str(data.get("element", "physical"))
	return def


## Combined damage-taken modifier per element (weakness - resistance), as used by Combatant.affinity.
func affinity() -> Dictionary:
	var result: Dictionary = {}
	for element: String in weaknesses:
		result[element] = int(result.get(element, 0)) + int(weaknesses[element])
	for element: String in resistances:
		result[element] = int(result.get(element, 0)) - int(resistances[element])
	return result
