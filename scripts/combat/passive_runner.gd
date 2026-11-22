class_name PassiveRunner
extends RefCounted
## Resolves data-defined specialization passives during one combat.
##
## A passive (data/specializations "starting_passive") looks like:
##   "trigger": {"event": "status_applied", "status_id": "burn", "applied_by": "owner"}
##   "limit_per_turn": 1
##   "effect": {"effect": "bonus_damage", "value": 2}
## Supported events (emitted by CardEffects through CombatManager):
##   status_applied {source, target, status_id}   trigger keys: status_id, applied_by ("owner")
##   block_gained   {source, target, amount, origin} trigger keys: recipient ("owner"), origin ("card")
##   card_played    {source, card, previous_owner_id, cards_played}  trigger keys: played_by ("owner"),
##                  after_other_owner (true), cards_played (N: the Nth card of the turn, either sister's)
##   status_applied also carries stacks_before; trigger key target_already_had (true)
##   attack_absorbed {source (enemy), target}          trigger keys: recipient ("owner")  (an enemy attack fully absorbed by Block)
##   turn_start      {turn}  (after the turn's draw)    trigger keys: turn (exactly turn N), every (every Nth turn)
##   enemy_killed    {source, target}                   (an enemy fell to a party hit)
##   card_played also takes card_type ("attack", "spell", ...).
##   card_exhausted  {source, card}                      a played card went to the exhaust pile
##   turn_end        {turn}  (before the hand is discarded)
##   attacked        {source (enemy), target}            an enemy attack hit a party member; trigger key recipient ("owner")
## Power cards (CardEffects "power") add entries for the rest of the combat (source "power").
## Supported passive effects: bonus_damage (to the event target, owner's damage type), bonus_block (to the owner),
##   extra_status (more stacks of the triggering status on the event target),
##   draw_cards (party deck draws N), taunt_attacker (the event source enemy must attack the owner),
##   create_card (N token cards, "card_id", into the hand), gain_energy (N), gain_aether (N),
##   party_block (N Block to every living sister), heal_party (N HP to every living sister),
##   apply_status_all ("status_id", N stacks on every living enemy), damage_all (N to every living enemy),
##   status_to_target ("status_id", N stacks on the event target),
##   damage_source (N to the enemy behind the event: thorns on "attacked").
##   bonus_damage and damage_all take an optional "element" (default: the owner's damage type).
##
## Worn equipment adds passives too: each item's "effects" (data/items/equipment.json) use this same
## format and belong to the wearer. "limit_per_combat": N caps a passive per battle (e.g. combat-start
## effects); "limit_per_turn" defaults to 1.
##
## Rules that keep passives predictable:
##  - Timing: a passive reacts right after the triggering effect resolves, during the player turn.
##  - Limit: at most `limit_per_turn` triggers per owner per player turn; counters reset when a
##    new player turn begins.
##  - No recursion: bonus effects use combatant methods directly (they emit no events), and events
##    arriving while a passive is resolving are ignored.
##  - Fallen owners never trigger their passive.

signal triggered(owner_id: String, passive_id: String, text: String)
## A relic's effect fired (the combat screen flashes its icon in the relic bar).
signal relic_triggered(relic_id: String, text: String)

var _combat: CombatManager
## [{owner_id, passive: Dictionary}]
var _entries: Array[Dictionary] = []
## "owner_id|passive_id" -> triggers this turn
var _counts: Dictionary = {}
## "owner_id|passive_id" -> triggers this combat
var _combat_counts: Dictionary = {}
var _resolving: bool = false


func setup(combat: CombatManager, party: Party) -> void:
	_combat = combat
	_entries.clear()
	_counts.clear()
	_combat_counts.clear()
	for member in party.members:
		var passive: Dictionary = member.specialization.passive if member.specialization != null else {}
		if passive.has("trigger") and passive.has("effect"):
			_entries.append({"owner_id": member.id, "passive": passive, "source": "specialization"})
		for item_passive in Equipment.passives(member):
			_entries.append({"owner_id": member.id, "passive": item_passive, "source": "item"})
	# Relics belong to the party: each acts through the sister who caused the event (else the first
	# living one). "debuff_only": true limits status_applied triggers to debuffs.
	for relic_passive in RelicEffects.passives(combat.inventory):
		_entries.append({"owner_id": "", "passive": relic_passive, "source": "relic"})


## A Power card played this combat: its passive belongs to the card's owner until the battle ends.
## Every copy is its own entry (two copies trigger twice).
func add_power(owner_id: String, passive: Dictionary) -> void:
	var entry_passive := passive.duplicate(true)
	entry_passive["id"] = "%s#%d" % [str(passive.get("id", "power")), _entries.size()]
	_entries.append({"owner_id": owner_id, "passive": entry_passive, "source": "power"})


func reset_turn() -> void:
	_counts.clear()


## True if the owner's passive exists, the owner is alive and it has not used up its limit.
func is_ready(owner_id: String) -> bool:
	for entry in _entries:
		if entry["owner_id"] == owner_id and entry["source"] == "specialization":
			var owner_c := _combat.get_combatant(owner_id)
			return owner_c != null and owner_c.is_alive() and _count(entry) < _limit(entry)
	return false


func has_passive(owner_id: String) -> bool:
	return _entries.any(func(e: Dictionary) -> bool: return e["owner_id"] == owner_id and e["source"] == "specialization")


func on_event(event: Dictionary) -> void:
	if _resolving:
		return
	for entry in _entries:
		var owner_c := _owner(entry, event)
		if owner_c == null or not owner_c.is_alive():
			continue
		if _count(entry) >= _limit(entry) or not _matches(entry, owner_c, event):
			continue
		var combat_limit := int(entry["passive"].get("limit_per_combat", 0))
		if combat_limit > 0 and int(_combat_counts.get(_key(entry), 0)) >= combat_limit:
			continue
		_counts[_key(entry)] = _count(entry) + 1
		_combat_counts[_key(entry)] = int(_combat_counts.get(_key(entry), 0)) + 1
		_resolving = true
		_apply(entry, owner_c, event)
		_resolving = false


func _matches(entry: Dictionary, owner_c: Combatant, event: Dictionary) -> bool:
	var trigger: Dictionary = entry["passive"]["trigger"]
	if str(trigger.get("event", "")) != str(event.get("type", "")):
		return false
	if trigger.has("status_id") and str(trigger["status_id"]) != str(event.get("status_id", "")):
		return false
	if str(trigger.get("applied_by", "")) == "owner" and event.get("source") != owner_c:
		return false
	if str(trigger.get("recipient", "")) == "owner" and event.get("target") != owner_c:
		return false
	if str(trigger.get("played_by", "")) == "owner" and event.get("source") != owner_c:
		return false
	if bool(trigger.get("after_other_owner", false)):
		var previous := str(event.get("previous_owner_id", ""))
		if previous == "" or previous == owner_c.id:
			return false
	if trigger.has("origin") and str(trigger["origin"]) != str(event.get("origin", "")):
		return false
	# Tailwind: fires on the Nth card the party plays this turn.
	if trigger.has("cards_played") and int(event.get("cards_played", -1)) != int(trigger["cards_played"]):
		return false
	# Lingering Venom: only when the target already carried the status before this application.
	if bool(trigger.get("target_already_had", false)) and int(event.get("stacks_before", 0)) <= 0:
		return false
	if bool(trigger.get("debuff_only", false)):
		var applied := DataRegistry.get_status(str(event.get("status_id", "")))
		if applied == null or applied.kind != "debuff":
			return false
	if trigger.has("turn") and int(event.get("turn", -1)) != int(trigger["turn"]):
		return false
	if trigger.has("every") and (int(trigger["every"]) <= 0 or int(event.get("turn", 0)) % int(trigger["every"]) != 0):
		return false
	if trigger.has("card_type"):
		var card: CardInstance = event.get("card")
		if card == null or card.definition.card_type != str(trigger["card_type"]):
			return false
	return true


func _apply(entry: Dictionary, owner_c: Combatant, event: Dictionary) -> void:
	var passive: Dictionary = entry["passive"]
	var effect: Dictionary = passive["effect"]
	var value := int(effect.get("value", 0))
	var passive_name := str(passive.get("name", passive.get("id", "Passive")))
	var text := ""
	match str(effect.get("effect", "")):
		"bonus_damage":
			var target: Combatant = event.get("target")
			if target != null and target.is_alive():
				var lost := _combat.hit(target, value, _element(effect, owner_c), owner_c)
				text = "%s: %s takes %d extra damage (%d lost)." % [passive_name, target.display_name, value, lost]
		"extra_status":
			var status_target: Combatant = event.get("target")
			var status_id := str(event.get("status_id", ""))
			if status_target != null and status_target.is_alive() and status_id != "":
				status_target.add_status(status_id, value, owner_c.id)
				var status_def := DataRegistry.get_status(status_id)
				text = "%s: %s gains %d extra %s." % [passive_name, status_target.display_name, value, status_def.display_name if status_def != null else status_id]
				_combat.visual_event.emit({"kind": "apply_status", "card_id": "", "specialization_id": "", "source_id": owner_c.id, "target_ids": [status_target.id], "target_group": CardDef.TARGET_SINGLE_ENEMY, "status_id": status_id})
		"bonus_block":
			owner_c.add_block(value)
			text = "%s: %s gains %d extra Block." % [passive_name, owner_c.display_name, value]
		"draw_cards":
			var before := _combat.deck.hand.size()
			_combat.deck.draw(value)
			var drawn := _combat.deck.hand.size() - before
			if drawn > 0:
				text = "%s: the party draws %d extra card(s)." % [passive_name, drawn]
				_combat.visual_event.emit({"kind": "draw", "card_id": "", "specialization_id": "", "source_id": owner_c.id, "target_ids": [owner_c.id], "target_group": CardDef.TARGET_SELF})
				_combat.add_aether(drawn, owner_c)
		"create_card":
			var token_def := DataRegistry.get_card(str(effect.get("card_id", "")))
			if token_def != null and _combat.deck.add_tokens(token_def, maxi(1, value)) > 0:
				text = "%s: %s gains %d %s." % [passive_name, "the hand", maxi(1, value), token_def.display_name]
				_combat.visual_event.emit({"kind": "create_card", "card_id": "", "specialization_id": owner_c.specialization_id, "source_id": owner_c.id, "target_ids": [owner_c.id], "target_group": CardDef.TARGET_SELF, "created_card_id": token_def.id})
		"taunt_attacker":
			var attacker: Combatant = event.get("source")
			if attacker != null and attacker.is_alive():
				attacker.add_status("taunt", value, owner_c.id)
				text = "%s: %s is taunted and must attack %s next." % [passive_name, attacker.display_name, owner_c.display_name]
				_combat.visual_event.emit({"kind": "apply_status", "card_id": "", "specialization_id": "", "source_id": owner_c.id, "target_ids": [attacker.id], "target_group": CardDef.TARGET_SINGLE_ENEMY, "status_id": "taunt"})
		"gain_energy":
			_combat.energy += value
			text = "%s: +%d Energy." % [passive_name, value]
			_combat.visual_event.emit({"kind": "gain_energy", "card_id": "", "specialization_id": owner_c.specialization_id, "source_id": owner_c.id, "target_ids": [owner_c.id], "target_group": CardDef.TARGET_SELF})
		"gain_aether":
			_combat.add_aether(value, owner_c)
			text = "%s: +%d Aether." % [passive_name, value]
		"party_block":
			for ally in _combat.get_living_party():
				ally.add_block(value)
			text = "%s: the party gains %d Block." % [passive_name, value]
			_combat.visual_event.emit({"kind": "block", "card_id": "", "specialization_id": owner_c.specialization_id, "source_id": owner_c.id, "target_ids": _ids(_combat.get_living_party()), "target_group": "all_allies"})
		"heal_party":
			for ally in _combat.get_living_party():
				ally.heal(value)
			text = "%s: the party heals %d HP." % [passive_name, value]
			_combat.visual_event.emit({"kind": "heal", "card_id": "", "specialization_id": owner_c.specialization_id, "source_id": owner_c.id, "target_ids": _ids(_combat.get_living_party()), "target_group": "all_allies"})
		"apply_status_all":
			var all_status := str(effect.get("status_id", ""))
			var foes := _combat.get_living_enemies()
			for foe in foes:
				foe.add_status(all_status, value, owner_c.id)
			if not foes.is_empty() and all_status != "":
				var all_def := DataRegistry.get_status(all_status)
				text = "%s: every enemy gains %d %s." % [passive_name, value, all_def.display_name if all_def != null else all_status]
				_combat.visual_event.emit({"kind": "apply_status", "card_id": "", "specialization_id": owner_c.specialization_id, "source_id": owner_c.id, "target_ids": _ids(foes), "target_group": "all_enemies", "status_id": all_status})
		"status_to_target":
			var marked: Combatant = event.get("target")
			var marked_status := str(effect.get("status_id", ""))
			if marked != null and marked.is_alive() and marked_status != "":
				marked.add_status(marked_status, value, owner_c.id)
				var marked_def := DataRegistry.get_status(marked_status)
				text = "%s: %s gains %d %s." % [passive_name, marked.display_name, value, marked_def.display_name if marked_def != null else marked_status]
				_combat.visual_event.emit({"kind": "apply_status", "card_id": "", "specialization_id": owner_c.specialization_id, "source_id": owner_c.id, "target_ids": [marked.id], "target_group": CardDef.TARGET_SINGLE_ENEMY, "status_id": marked_status})
		"damage_source":
			var attacker_foe: Combatant = event.get("source")
			if attacker_foe != null and attacker_foe.is_alive() and attacker_foe.side == Combatant.SIDE_ENEMY:
				var thorn_lost := _combat.hit(attacker_foe, value, _element(effect, owner_c), owner_c)
				text = "%s: %s takes %d damage (%d lost)." % [passive_name, attacker_foe.display_name, value, thorn_lost]
				_combat.visual_event.emit({"kind": "damage", "card_id": "", "specialization_id": owner_c.specialization_id, "source_id": owner_c.id, "target_ids": [attacker_foe.id], "target_group": CardDef.TARGET_SINGLE_ENEMY, "element": _element(effect, owner_c)})
		"damage_all":
			var hit_foes := _combat.get_living_enemies()
			for foe in hit_foes:
				_combat.hit(foe, value, _element(effect, owner_c), owner_c)
			if not hit_foes.is_empty():
				text = "%s: %d damage to every enemy." % [passive_name, value]
				_combat.visual_event.emit({"kind": "damage", "card_id": "", "specialization_id": owner_c.specialization_id, "source_id": owner_c.id, "target_ids": _ids(hit_foes), "target_group": "all_enemies", "element": _element(effect, owner_c)})
		_:
			push_warning("PassiveRunner: unknown passive effect '%s'" % effect.get("effect", ""))
	if text != "":
		_combat.say("✦ " + text)
		triggered.emit(owner_c.id, str(passive.get("id", "")), text)
		if passive.has("relic_id"):
			relic_triggered.emit(str(passive["relic_id"]), text)


## Who acts for an entry: its owner; for a relic, the sister behind the event, else the first living one.
func _owner(entry: Dictionary, event: Dictionary) -> Combatant:
	if entry["source"] != "relic":
		return _combat.get_combatant(entry["owner_id"])
	var source: Variant = event.get("source")
	if source is Combatant and (source as Combatant).side == Combatant.SIDE_PARTY and (source as Combatant).is_alive():
		return source
	var living := _combat.get_living_party()
	return living[0] if not living.is_empty() else null


func _element(effect: Dictionary, owner_c: Combatant) -> String:
	return DamageTypes.normalize(str(effect.get("element", owner_spec_element(owner_c))))


static func _ids(units: Array[Combatant]) -> Array[String]:
	var ids: Array[String] = []
	for unit in units:
		ids.append(unit.id)
	return ids


func owner_spec_element(owner_c: Combatant) -> String:
	var member := _combat.party.get_member(owner_c.id) if _combat.party != null else null
	return member.specialization.damage_element if member != null else DamageTypes.PHYSICAL


func _limit(entry: Dictionary) -> int:
	return int(entry["passive"].get("limit_per_turn", 1))


func _count(entry: Dictionary) -> int:
	return int(_counts.get(_key(entry), 0))


func _key(entry: Dictionary) -> String:
	return "%s|%s" % [entry["owner_id"], entry["passive"].get("id", "")]
