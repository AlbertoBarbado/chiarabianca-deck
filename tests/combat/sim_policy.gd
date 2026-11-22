extends RefCounted
## Greedy card policy shared by the balance simulations (balance_simulation.gd, run_simulation.gd).
## Scores each playable card by its rough value per Energy and plays the best one, again and again.
## It knows the combo rules well enough to value them: Aether and Momentum bonuses, conditional
## damage, Gust tokens, Poison and Blight, and twin reactions (a Fire hit on a Poisoned foe is worth
## the Combustion it sets off). It does not plan a turn ahead, so real players get more from combos.

const MAX_PLAYS_PER_TURN := 30


static func play_turn(cm: CombatManager) -> void:
	var guard := 0
	while cm.state == CombatManager.State.PLAYER_TURN and guard < MAX_PLAYS_PER_TURN:
		guard += 1
		var best: CardInstance = null
		var best_score := -1.0
		for card in cm.deck.hand:
			if cm.can_play(card) != "":
				continue
			var score := score(cm, card)
			if score > best_score:
				best_score = score
				best = card
		if best == null or best_score <= 0.0:
			return
		cm.play_card(best, target_for(cm, best))


static func score(cm: CombatManager, card: CardInstance) -> float:
	var x := cm.energy if card.definition.x_cost else 0
	if card.definition.x_cost and x <= 0:
		return 0.0  # an X card with no Energy does nothing
	var cost := maxf(0.5, float(x if card.definition.x_cost else card.get_cost()))
	var total := 0.0
	var missing := 0
	for c in cm.get_living_party():
		missing += c.max_hp - c.hp
	var living := cm.get_living_enemies()
	var focus := _focus(cm)
	var owner := cm.get_combatant(card.owner_character_id)
	for effect: Dictionary in card.get_effects():
		var value := float(effect.get("value", 0)) + float(effect.get("per_aether", 0)) * cm.aether \
			+ float(effect.get("per_card_played", 0)) * cm.cards_played_this_turn + float(effect.get("per_x", 0)) * x
		var effect_total := total
		if owner != null and str(effect.get("effect", "")) == "damage":
			value += owner.power_damage
		if owner != null and str(effect.get("effect", "")) == "block":
			value += owner.power_block
		var all_targets := str(effect.get("target", "")) == "all_enemies"
		var targets := living.size() if all_targets else 1
		match str(effect.get("effect", "")):
			"damage":
				var hit_element := DamageTypes.for_card_effect(effect, card.definition)
				var extra := 0.0
				if effect.has("per_source_block") and owner != null:
					extra += float(owner.block) * float(effect["per_source_block"])
				if focus != null:
					extra += _conditional_bonus(effect, focus)
					extra += _reaction_value(cm, hit_element, focus) / float(targets)
				total += (value + extra) * targets
			"block":
				# Block is worth the damage it stops on whoever is really being attacked.
				var receivers: Array[Combatant] = []
				match str(effect.get("target", "")):
					"all_allies":
						receivers = cm.get_living_party()
					"single_ally":
						var ally := cm.get_combatant(target_for(cm, card))
						if ally != null:
							receivers.append(ally)
					_:
						if owner != null:
							receivers.append(owner)
				for r in receivers:
					total += minf(value, maxf(0.0, float(incoming_on(cm, r.id) - r.block))) * 0.9
			"heal":
				total += minf(value, float(missing)) * 0.8
			"apply_status":
				if str(effect.get("status_id", "")) == "taunt":
					total += _taunt_value(cm, owner, all_targets)
					continue
				total += _status_value(cm, str(effect.get("status_id", "")), value + _from_status(effect, focus), focus) * targets
			"multiply_status":
				if focus != null and focus.has_status(str(effect.get("status_id", ""))):
					total += float(focus.statuses[str(effect["status_id"])]["stacks"]) * (2.0 if all_targets else 1.0) * 1.5
			"spread_status":
				if focus != null:
					for status_id: String in focus.statuses:
						if status_id != "taunt":
							total += ceilf(int(focus.statuses[status_id]["stacks"]) * 0.5) * (living.size() - 1) * 1.2
			"create_card":
				total += 3.0 * value
			"draw":
				total += 3.0 * value
			"gain_energy":
				total += 6.0
			"power":
				# A power pays off every turn that is left: worth a lot early, little at the end.
				var living_hp := 0
				for enemy in living:
					living_hp += enemy.hp
				total += float(effect.get("sim_value", 6)) * clampf(float(living_hp) / 25.0, 0.5, 4.0)
			"multiply_block":
				if owner != null:
					total += minf(float(owner.block), maxf(0.0, float(incoming_on(cm, owner.id) - owner.block))) * 0.9
		if bool(effect.get("repeat_x", false)):
			total = effect_total + (total - effect_total) * float(x + int(effect.get("repeat_bonus", 0)))
	return total / cost


## The enemy the policy aims at: the weakest living one.
static func _focus(cm: CombatManager) -> Combatant:
	var focus: Combatant = null
	for enemy in cm.get_living_enemies():
		if focus == null or enemy.hp < focus.hp:
			focus = enemy
	return focus


static func _conditional_bonus(effect: Dictionary, focus: Combatant) -> float:
	var extra := 0.0
	var bonus: Dictionary = effect.get("bonus_if_status", {})
	if not bonus.is_empty() and focus.has_status(str(bonus.get("status_id", ""))):
		extra += float(bonus.get("value", 0))
	var any_of: Dictionary = effect.get("bonus_if_any_status", {})
	if not any_of.is_empty() and (any_of.get("status_ids", []) as Array).any(func(s: Variant) -> bool: return focus.has_status(str(s))):
		extra += float(any_of.get("value", 0))
	var per_stack: Dictionary = effect.get("per_target_status", {})
	if not per_stack.is_empty() and focus.has_status(str(per_stack.get("status_id", ""))):
		extra += float(per_stack.get("value", 0)) * float(focus.statuses[str(per_stack["status_id"])]["stacks"])
	return extra


static func _from_status(effect: Dictionary, focus: Combatant) -> float:
	var spec: Dictionary = effect.get("from_target_status", {})
	if spec.is_empty() or focus == null or not focus.has_status(str(spec.get("status_id", ""))):
		return 0.0
	return float(focus.statuses[str(spec["status_id"])]["stacks"]) * float(spec.get("factor", 1))


## Rough worth of what a reaction would add (Combustion = Poison stacks on every enemy...).
static func _reaction_value(cm: CombatManager, element: String, focus: Combatant) -> float:
	var worth := 0.0
	for reaction: Dictionary in Reactions.all():
		if str(reaction.get("element", "")) != element or not focus.has_status(str(reaction.get("status_id", ""))):
			continue
		var stacks := float(focus.statuses[str(reaction["status_id"])]["stacks"])
		match str(reaction.get("effect", "")):
			"detonate":
				worth += stacks * float(reaction.get("per_stack", 1)) * (cm.get_living_enemies().size() if str(reaction.get("scope", "")) == "all_enemies" else 1)
			"spread":
				worth += ceilf(stacks * 0.5) * (cm.get_living_enemies().size() - 1) * 1.2
			"shatter":
				worth += stacks * float(reaction.get("per_stack", 1))
			"add_status", "block_source":
				worth += 3.0
	return worth


## Value of applying `value` stacks of a status to the focus.
static func _status_value(cm: CombatManager, status_id: String, value: float, focus: Combatant) -> float:
	match status_id:
		"burn":
			return value * 2.0
		"poison":
			return value * 1.6
		"blight":
			if focus == null:
				return 0.0
			var current := float(focus.statuses.get("blight", {}).get("stacks", 0))
			# Blight is worth the HP it lets the party skip once the foe is low enough.
			return minf(value, maxf(0.0, focus.hp - current)) * (0.9 if focus.hp <= current + value + 12 else 0.35)
	return 4.0


## Damage the living enemies' attack intents will deal to `member_id` (Taunt redirects single
## attacks to the taunter; attacks on everyone count for all).
static func incoming_on(cm: CombatManager, member_id: String) -> int:
	var total := 0
	for enemy in cm.get_living_enemies():
		if enemy.intent == null or enemy.intent.type != EnemyIntent.TYPE_ATTACK:
			continue
		if enemy.intent.hits_all or _attack_target(cm, enemy) == member_id:
			total += enemy.intent.value
	return total


static func _attack_target(cm: CombatManager, enemy: Combatant) -> String:
	if enemy.has_status("taunt"):
		var taunter := cm.get_combatant(enemy.get_status_source("taunt"))
		if taunter != null and taunter.is_alive():
			return taunter.id
	return enemy.intent.planned_target_id if enemy.intent != null else ""


## Taunt pulls single attacks aimed at the other princess onto the taunter (worth more with Block).
static func _taunt_value(cm: CombatManager, taunter: Combatant, all_targets: bool) -> float:
	if taunter == null:
		return 0.0
	var worth := 0.0
	for enemy in cm.get_living_enemies():
		if enemy.intent == null or enemy.intent.type != EnemyIntent.TYPE_ATTACK or enemy.intent.hits_all:
			continue
		if _attack_target(cm, enemy) == taunter.id:
			continue
		var moved := float(enemy.intent.value) * (0.9 if taunter.block > 0 else 0.6)
		worth = worth + moved if all_targets else maxf(worth, moved)
	return worth


## The enemy a Taunt should go to: the hardest single attack aimed at someone else.
static func _taunt_target(cm: CombatManager, taunter_id: String) -> String:
	var best := ""
	var best_value := -1
	for enemy in cm.get_living_enemies():
		if enemy.intent == null or enemy.intent.type != EnemyIntent.TYPE_ATTACK or enemy.intent.hits_all:
			continue
		if _attack_target(cm, enemy) != taunter_id and enemy.intent.value > best_value:
			best_value = enemy.intent.value
			best = enemy.id
	return best


static func target_for(cm: CombatManager, card: CardInstance) -> String:
	match card.definition.target:
		CardDef.TARGET_SINGLE_ENEMY:
			for effect: Dictionary in card.get_effects():
				if str(effect.get("status_id", "")) == "taunt":
					var taunted := _taunt_target(cm, card.owner_character_id)
					if taunted != "":
						return taunted
			var living := cm.get_living_enemies()
			if living.is_empty():
				return ""
			living.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.hp < b.hp)
			return living[0].id
		CardDef.TARGET_SINGLE_ALLY:
			var party := cm.get_living_party()
			party.sort_custom(func(a: Combatant, b: Combatant) -> bool: return (a.max_hp - a.hp) > (b.max_hp - b.hp))
			return party[0].id
	return ""
