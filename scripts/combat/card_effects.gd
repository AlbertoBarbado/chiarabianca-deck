class_name CardEffects
extends RefCounted
## Reusable card effect implementations. Cards reference these by name in data
## ("effect": "damage"); the combat controller never contains card-specific logic.


static func resolve_all(effects: Array, ctx: EffectContext) -> void:
	for effect: Dictionary in effects:
		# X-cost cards: "repeat_x": true resolves the effect X times (+ "repeat_bonus" more).
		var times := ctx.x_value + int(effect.get("repeat_bonus", 0)) if bool(effect.get("repeat_x", false)) else 1
		for i in times:
			resolve(effect, ctx)


static func resolve(effect: Dictionary, ctx: EffectContext) -> void:
	var value := int(effect.get("value", 0)) + int(effect.get("per_aether", 0)) * ctx.combat.aether \
		+ int(effect.get("per_card_played", 0)) * ctx.combat.cards_played_this_turn + int(effect.get("per_x", 0)) * ctx.x_value
	var targets := ctx.resolve_targets(str(effect.get("target", CardDef.TARGET_NONE)))
	var card_name := ctx.card.get_card_name()
	match str(effect.get("effect", "")):
		"damage":
			var element := DamageTypes.for_card_effect(effect, ctx.card.definition)
			for target in targets:
				if not target.is_alive():
					continue
				var amount := _damage_amount(effect, value, ctx.source, target)
				var lost := ctx.combat.hit(target, amount, element, ctx.source)
				var final_amount := int(ctx.combat.last_hit.get("final", amount))
				var note := ""
				if final_amount != amount:
					note = " (%s %s)" % [DamageTypes.display_name(element), "weakness" if final_amount > amount else "resisted"]
				ctx.combat.say("%s hits %s for %d%s (%d lost)." % [card_name, target.display_name, final_amount, note, lost])
				var consumed := str(effect.get("consume_status", ""))
				if consumed != "" and target.is_alive():
					target.statuses.erase(consumed)
			_announce(ctx, effect, "damage", targets, {"element": element})
		"block":
			value += ctx.source.power_block
			for target in targets:
				target.add_block(value)
				ctx.combat.say("%s gains %d Block." % [target.display_name, value])
				ctx.combat.passives.on_event({"type": "block_gained", "source": ctx.source, "target": target, "amount": value, "origin": "card"})
			_announce(ctx, effect, "block", targets)
		"heal":
			if value <= 0:  # an Aether heal with no Aether to draw on
				return
			for target in targets:
				target.heal(value)
				ctx.combat.say("%s heals %d." % [target.display_name, value])
			_announce(ctx, effect, "heal", targets)
		"apply_status":
			var status_id := str(effect.get("status_id", ""))
			for target in targets:
				if not target.is_alive():
					continue
				var amount := value + _from_target_status(effect, target)
				if amount <= 0:
					continue
				var before := int(target.statuses.get(status_id, {}).get("stacks", 0))
				target.add_status(status_id, amount, ctx.source.id)
				var status_def := DataRegistry.get_status(status_id)
				var status_name := status_def.display_name if status_def != null else status_id.capitalize()
				ctx.combat.say("%s is afflicted with %d %s." % [target.display_name, amount, status_name])
				ctx.combat.passives.on_event({"type": "status_applied", "source": ctx.source, "target": target, "status_id": status_id, "stacks_before": before})
			_announce(ctx, effect, "apply_status", targets, {"status_id": status_id})
		"draw":
			var drawn := ctx.combat.deck.draw(value).size()
			ctx.combat.say("Drew %d card(s)." % drawn)
			_announce(ctx, effect, "draw", targets)
			ctx.combat.add_aether(drawn, ctx.source)
		"gain_energy":
			ctx.combat.energy += value
			ctx.combat.say("Gained %d Energy." % value)
			_announce(ctx, effect, "gain_energy", targets)
			ctx.combat.add_aether(value, ctx.source)
		"create_card":
			# Tokens (Gusts): temporary cards added to the hand; they vanish when played or at turn end.
			var token_def := DataRegistry.get_card(str(effect.get("card_id", "")))
			if token_def != null:
				var added := ctx.combat.deck.add_tokens(token_def, value)
				if added > 0:
					ctx.combat.say("%s conjures %d %s." % [ctx.source.display_name, added, token_def.display_name])
					var caster: Array[Combatant] = [ctx.source]
					_announce(ctx, effect, "create_card", caster, {"created_card_id": token_def.id, "amount": added})
		"spread_status":
			# Wind's Scatter: half (rounded up, at least 1) of each listed debuff on the target goes to
			# every other living enemy. "status_id": "all" spreads every debuff it carries.
			var wanted := str(effect.get("status_id", "all"))
			var ratio := float(effect.get("ratio", 0.5))
			for target in targets:
				if not target.is_alive():
					continue
				for status_id: String in target.statuses.keys():
					var status_def := DataRegistry.get_status(status_id)
					if (wanted != "all" and status_id != wanted) or status_def == null or status_def.kind != "debuff" or status_id == "taunt":
						continue
					var share := maxi(1, ceili(int(target.statuses[status_id]["stacks"]) * ratio))
					for other in ctx.combat.get_living_enemies():
						if other != target:
							other.add_status(status_id, share, ctx.source.id)
					ctx.combat.say("%s spreads %d %s to every other enemy." % [ctx.card.get_card_name(), share, status_def.display_name])
			_announce(ctx, effect, "spread_status", ctx.combat.get_living_enemies())
		"multiply_status":
			# Catalyst: the target's stacks of a status are multiplied (x2 by default).
			var multiply_id := str(effect.get("status_id", ""))
			var factor := int(effect.get("factor", 2))
			for target in targets:
				if target.is_alive() and target.has_status(multiply_id):
					var stacks := int(target.statuses[multiply_id]["stacks"])
					target.add_status(multiply_id, stacks * (factor - 1), ctx.source.id)
					ctx.combat.say("%s: %s's %s grows to %d." % [ctx.card.get_card_name(), target.display_name, multiply_id.capitalize(), int(target.statuses[multiply_id]["stacks"])])
			_announce(ctx, effect, "apply_status", targets, {"status_id": multiply_id})
		"power":
			# A Power card: its "power" block is a passive (PassiveRunner format) and/or "stats"
			# ({"damage": N, "block": N}) that last for the rest of the combat.
			ctx.combat.add_power(ctx.source, effect.get("power", {}), ctx.card.get_card_name())
			var self_target: Array[Combatant] = [ctx.source]
			_announce(ctx, effect, "power", self_target)
		"multiply_block":
			# Entrench: the target's Block is multiplied ("factor", default 2).
			for target in targets:
				var extra := target.block * (int(effect.get("factor", 2)) - 1)
				target.add_block(extra)
				ctx.combat.say("%s's Block grows to %d." % [target.display_name, target.block])
			_announce(ctx, effect, "block", targets)
		"spend_aether":
			# Always the card's last effect: the bonuses above read Aether before it is used up.
			var spent := ctx.combat.spend_aether()
			if spent > 0:
				ctx.combat.say("%s releases %d Aether." % [ctx.source.display_name, spent])
				ctx.combat.visual_event.emit({"kind": "aether_spent", "card_id": ctx.card.definition.id, "specialization_id": ctx.card.definition.specialization_id, "source_id": ctx.source.id, "target_ids": [ctx.source.id], "target_group": CardDef.TARGET_SELF, "amount": spent})
		_:
			push_warning("CardEffects: unknown effect '%s' on card %s" % [effect.get("effect", ""), ctx.card.definition.id])


## Damage the card would deal right now, without changing anything: one {"base", "final"} per
## damage effect, where runs of identical effects ("Deal 3 damage 3 times") count once. "base" is the
## printed value; "final" adds Aether, Momentum, Block scaling, the owner's weapon bonus and Sandblind,
## and, when `target` is given, that target's statuses, weaknesses and resistances. A card with
## several targets is previewed without one. The card text shows "final" in place of "base".
static func damage_preview(card: CardInstance, combat: CombatManager, target: Combatant = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if card == null or combat == null:
		return out
	var source := combat.get_combatant(card.owner_character_id)
	if source == null:
		return out
	var previous: Dictionary = {}
	for effect: Dictionary in card.get_effects():
		if str(effect.get("effect", "")) != "damage":
			previous = {}
			continue
		if effect == previous:
			continue
		previous = effect
		var base := int(effect.get("value", 0))
		if base <= 0:  # nothing printed to swap ("damage equal to twice the target's Poison")
			continue
		var value := base + int(effect.get("per_aether", 0)) * combat.aether + int(effect.get("per_card_played", 0)) * combat.cards_played_this_turn \
			+ int(effect.get("per_x", 0)) * (combat.energy if card.definition.x_cost else 0)
		var element := DamageTypes.for_card_effect(effect, card.definition)
		var final_amount: int
		if target != null and str(effect.get("target", "")) == CardDef.TARGET_SINGLE_ENEMY:
			final_amount = DamageTypes.apply(_damage_amount(effect, value, source, target), element, source, target)
		else:
			value += int(floor(float(source.block) * float(effect.get("per_source_block", 0.0)))) + source.power_damage
			final_amount = DamageTypes.apply(value, element, source, null)
		out.append({"base": base, "final": final_amount})
	return out


## True if the card (or its upgrade) reads or spends the party's Aether.
static func uses_aether(def: CardDef) -> bool:
	if def == null:
		return false
	for effect: Dictionary in def.effects + (def.upgrade.get("effects", []) as Array):
		if effect.has("per_aether") or str(effect.get("effect", "")) == "spend_aether":
			return true
	return false


## True if the card (or its upgrade) grows with Momentum (cards already played this turn).
static func uses_momentum(def: CardDef) -> bool:
	if def == null:
		return false
	for effect: Dictionary in def.effects + (def.upgrade.get("effects", []) as Array):
		if effect.has("per_card_played"):
			return true
	return false


## Tells the presentation layer that a gameplay effect has just resolved (never before it).
## Listeners (combat VFX) only read this event; it cannot change the outcome.
static func _announce(ctx: EffectContext, effect: Dictionary, kind: String, targets: Array[Combatant], extra: Dictionary = {}) -> void:
	if targets.is_empty():
		return
	var ids: Array[String] = []
	for target in targets:
		ids.append(target.id)
	var event := {
		"kind": kind, "card_id": ctx.card.definition.id, "specialization_id": ctx.card.definition.specialization_id,
		"source_id": ctx.source.id, "target_ids": ids, "target_group": str(effect.get("target", "")),
	}
	event.merge(extra)
	ctx.combat.visual_event.emit(event)


## Damage after optional data-driven modifiers on the effect (before the element rule):
##   "bonus_if_status": {"status_id": "burn", "value": 5}  extra damage if the target has the status
##   "bonus_if_any_status": {"status_ids": ["burn", "chill"], "value": 4}  extra damage if it has any of them
##   "per_source_block": 1.0                               extra damage = attacker's Block x factor
##   "per_target_status": {"status_id": "chill", "value": 4}  extra damage per stack of the status
##   "consume_status": "chill"                             the status is removed after the hit (Shatter)
##   "element": "frost"                                    damage type (default: the specialization's)
## Any effect's value may also carry "per_card_played": N (+N per card the party already played this
## turn: Momentum, see CombatManager.cards_played_this_turn) and "per_aether": N (+N per point of the party's Aether this turn;
## see CombatManager.aether); it is added in resolve() before these modifiers.
## "from_target_status": {"status_id": "poison", "factor": 3}: extra value = the target's stacks x factor
## (Plague Reaping: Blight equal to three times the target's Poison).
static func _from_target_status(effect: Dictionary, target: Combatant) -> int:
	var spec: Dictionary = effect.get("from_target_status", {})
	if spec.is_empty() or not target.has_status(str(spec.get("status_id", ""))):
		return 0
	return int(target.statuses[str(spec["status_id"])]["stacks"]) * int(spec.get("factor", 1))


static func _damage_amount(effect: Dictionary, base: int, source: Combatant, target: Combatant) -> int:
	var amount := base + source.power_damage
	var conditional: Dictionary = effect.get("bonus_if_status", {})
	if not conditional.is_empty() and target.has_status(str(conditional.get("status_id", ""))):
		amount += int(conditional.get("value", 0))
	var any_of: Dictionary = effect.get("bonus_if_any_status", {})
	if not any_of.is_empty() and (any_of.get("status_ids", []) as Array).any(func(s: Variant) -> bool: return target.has_status(str(s))):
		amount += int(any_of.get("value", 0))
	amount += int(floor(float(source.block) * float(effect.get("per_source_block", 0.0))))
	var per_stack: Dictionary = effect.get("per_target_status", {})
	if not per_stack.is_empty() and target.has_status(str(per_stack.get("status_id", ""))):
		amount += int(per_stack.get("value", 0)) * int(target.statuses[str(per_stack["status_id"])]["stacks"])
	return amount
