class_name EnemyIntent
extends RefCounted
## What an enemy has announced it will do on its next turn.

const TYPE_ATTACK := "attack"
const TYPE_DEFEND := "defend"

var action_id: String = ""
var action_name: String = ""
var type: String = TYPE_ATTACK
var value: int = 0
## Target chosen when the intent was planned; a Taunt may override it at execution time.
var planned_target_id: String = ""
## Optional rider of an attack: a status applied to everyone it hits (e.g. Poison).
var status_id: String = ""
var status_value: int = 0
## True when the attack hits every living party member.
var hits_all: bool = false
## Damage type of the attack.
var element: String = "physical"


func describe(target_name: String = "") -> String:
	match type:
		TYPE_ATTACK:
			var kind := "" if element == DamageTypes.PHYSICAL else DamageTypes.display_name(element).to_lower() + " "
			var rider := ""
			if status_id != "" and status_value > 0:
				var status_def := DataRegistry.get_status(status_id)
				rider = " +%d %s" % [status_value, status_def.display_name if status_def != null else status_id.capitalize()]
			if hits_all:
				return "%s: %d %sdmg%s → whole party" % [action_name, value, kind, rider]
			if target_name != "":
				return "%s: %d %sdmg%s → %s" % [action_name, value, kind, rider, target_name]
			return "%s: %d %sdmg%s" % [action_name, value, kind, rider]
		TYPE_DEFEND:
			return "%s: +%d block" % [action_name, value]
	return action_name
