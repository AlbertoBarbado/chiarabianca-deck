class_name EffectContext
extends RefCounted
## Everything a card effect needs while resolving: the combat, the card, its owner and the
## chosen target. Effects reach other party members through `combat`, which keeps
## cross-character and combo effects possible without changing the combat engine.

var combat: CombatManager
var source: Combatant
var card: CardInstance
var chosen_target_id: String = ""
## X-cost cards: the Energy spent on them (0 for every other card).
var x_value: int = 0


func _init(p_combat: CombatManager, p_source: Combatant, p_card: CardInstance, p_target_id: String) -> void:
	combat = p_combat
	source = p_source
	card = p_card
	chosen_target_id = p_target_id


## Converts a target keyword from card data into living combatants.
func resolve_targets(target_key: String) -> Array[Combatant]:
	var result: Array[Combatant] = []
	var chosen := combat.get_combatant(chosen_target_id)
	match target_key:
		CardDef.TARGET_SELF:
			result.append(source)
		CardDef.TARGET_SINGLE_ENEMY:
			if chosen != null and chosen.side == Combatant.SIDE_ENEMY and chosen.is_alive():
				result.append(chosen)
			elif not combat.get_living_enemies().is_empty():
				result.append(combat.get_living_enemies()[0])
		CardDef.TARGET_SINGLE_ALLY:
			if chosen != null and chosen.side == Combatant.SIDE_PARTY and chosen.is_alive():
				result.append(chosen)
			else:
				result.append(source)
		CardDef.TARGET_ALL_ENEMIES:
			result.append_array(combat.get_living_enemies())
		CardDef.TARGET_ALL_ALLIES:
			result.append_array(combat.get_living_party())
	return result
