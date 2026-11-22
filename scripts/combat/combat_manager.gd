class_name CombatManager
extends RefCounted
## Turn-based party combat rules. Pure logic: the UI listens to signals and reads state.
## Flow: start() -> player turn (play cards) -> end_player_turn() -> enemy turn -> repeat.

signal changed
signal message(text: String)
signal ended(result: String)
## Presentation hook: emitted right after a gameplay effect, status tick, potion or enemy action
## has resolved. Keys: kind, card_id, specialization_id, source_id, target_ids, target_group,
## status_id (optional). Listeners only read it; it cannot change the outcome.
signal visual_event(event: Dictionary)

enum State { PLAYER_TURN, ENEMY_TURN, VICTORY, DEFEAT }

const RESULT_VICTORY := "victory"
const RESULT_DEFEAT := "defeat"
const BASE_ENERGY := 3
const HAND_SIZE := 5

var state: State = State.PLAYER_TURN
var turn: int = 0
var energy: int = 0
var max_energy: int = BASE_ENERGY
var encounter_name: String = ""
var gold_reward: int = 0
var deck: PartyDeck
var party: Party
var inventory: Inventory
var passives: PassiveRunner = PassiveRunner.new()
## Owner id of the previous card played this player turn ("" = none yet); read by passives.
var last_card_owner_id: String = ""
## Elite encounters (data flag) have a distinct introduction and a better reward.
var is_elite: bool = false
var is_boss: bool = false
var intro_text: String = ""
## Encounter "cinematic": a kicker line ("Final Battle") that gives a regular fight the elite-style
## introduction (a map's last fight without a boss). Empty = only elites and bosses get one.
var cinematic: String = ""
var reward_rules: Dictionary = {}
var party_combatants: Array[Combatant] = []
var enemies: Array[Combatant] = []
## Aether: the party's surplus magic this turn. Every Energy gained and every card drawn by a card
## or passive during the player's turn adds 1 (the turn's normal draw does not). Cards read it with
## "per_aether" and spend it with the "spend_aether" effect; it fades at the start of each turn.
const MAX_AETHER := 6
var aether: int = 0
## Momentum: cards the party has played this turn (tokens included). Cards read it with
## "per_card_played" (counting the cards played before them); Wind's Tailwind passive watches it.
var cards_played_this_turn: int = 0
## Twin reactions set off this combat (Reactions.try_react), for tests and the log.
var reactions_fired: int = 0
var _reacting: bool = false

var _rng: RandomNumberGenerator


## encounter: a data/encounters definition. seed_value < 0 means random.
func setup(p_party: Party, encounter: Dictionary, p_inventory: Inventory, seed_value: int = -1) -> void:
	party = p_party
	inventory = p_inventory
	_rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	deck = PartyDeck.new(_rng)
	encounter_name = str(encounter.get("name", "Battle"))
	is_elite = bool(encounter.get("elite", false))
	is_boss = bool(encounter.get("boss", false))
	intro_text = str(encounter.get("intro", ""))
	cinematic = str(encounter.get("cinematic", ""))
	reward_rules = encounter.get("reward", {}) if encounter.get("reward", {}) is Dictionary else {}
	gold_reward = int(encounter.get("gold_reward", 0))
	for member in party.members:
		var c := Combatant.new()
		c.id = member.id
		c.display_name = member.definition.display_name
		c.side = Combatant.SIDE_PARTY
		c.max_hp = member.max_hp
		c.hp = member.current_hp
		c.accent_color = member.definition.accent_color
		c.specialization_id = member.specialization.id if member.specialization != null else ""
		var gear := Equipment.totals(member)  # armour resistances and weapon damage bonuses
		for element: String in gear["resist"]:
			c.affinity[element] = int(c.affinity.get(element, 0)) - int(gear["resist"][element])
		c.damage_bonus = (gear["damage"] as Dictionary).duplicate()
		c.immunities.assign(gear["immune"])
		party_combatants.append(c)
	_spawn_enemies(encounter.get("enemies", []))
	_apply_difficulty(RunRules.get_block("difficulty"))
	# Relic stats (boss relics): Energy per turn, cards per turn and a harder enemy hit.
	max_energy += RelicEffects.stat(inventory, "energy")
	var relic_damage := RelicEffects.stat(inventory, "enemy_damage_pct")
	if relic_damage != 0:
		for enemy in enemies:
			enemy.damage_scale *= 1.0 + relic_damage / 100.0
	passives.setup(self, party)


## Difficulty (data/progression/run_rules.json "difficulty"): enemy HP and attack damage multipliers,
## with extra factors for elite and boss fights. 1.0 everywhere = the numbers in the enemy data.
##   {"enemy_hp": 1.0, "enemy_damage": 1.0, "elite_hp": 1.1, "elite_damage": 1.0, "boss_hp": 1.2, "boss_damage": 1.1}
func _apply_difficulty(rules: Dictionary) -> void:
	var hp_scale := float(rules.get("enemy_hp", 1.0))
	var damage := float(rules.get("enemy_damage", 1.0))
	if is_elite:
		hp_scale *= float(rules.get("elite_hp", 1.0))
		damage *= float(rules.get("elite_damage", 1.0))
	if is_boss:
		hp_scale *= float(rules.get("boss_hp", 1.0))
		damage *= float(rules.get("boss_damage", 1.0))
	for enemy in enemies:
		var base_hp := enemy.enemy_def.max_hp if enemy.enemy_def != null else enemy.max_hp  # from the data: calling it again never compounds
		enemy.max_hp = maxi(1, roundi(base_hp * hp_scale))
		enemy.hp = enemy.max_hp
		enemy.damage_scale = damage


func start() -> void:
	deck.build_from_party(party)
	say("%s begins!" % encounter_name)
	_plan_intents()
	_begin_player_turn()


# --- Queries -----------------------------------------------------------------

func get_combatant(id: String) -> Combatant:
	for c in party_combatants:
		if c.id == id:
			return c
	for c in enemies:
		if c.id == id:
			return c
	return null


func get_living_enemies() -> Array[Combatant]:
	return _living(enemies)


func get_living_party() -> Array[Combatant]:
	return _living(party_combatants)


## Returns "" if the card can be played now, otherwise the reason it cannot.
func can_play(card: CardInstance) -> String:
	if state != State.PLAYER_TURN:
		return "It is not your turn."
	var owner_c := get_combatant(card.owner_character_id)
	if owner_c == null or not owner_c.is_alive():
		return "%s has fallen and cannot play cards." % (owner_c.display_name if owner_c != null else "The owner")
	if card.get_cost() > energy:
		return "Not enough Energy."
	return ""


## True when the player must pick a specific target for this card.
func needs_target_choice(card: CardInstance) -> bool:
	match card.definition.target:
		CardDef.TARGET_SINGLE_ENEMY:
			return get_living_enemies().size() > 1
		CardDef.TARGET_SINGLE_ALLY:
			return get_living_party().size() > 1
	return false


func get_intent_target(enemy: Combatant) -> Combatant:
	if enemy.intent == null or enemy.intent.type != EnemyIntent.TYPE_ATTACK:
		return null
	return EnemyAI.resolve_target(enemy, party_combatants)


# --- Player actions ----------------------------------------------------------

func play_card(card: CardInstance, target_id: String = "") -> bool:
	var reason := can_play(card)
	if reason != "":
		say(reason)
		return false
	if needs_target_choice(card):
		var chosen := get_combatant(target_id)
		var wants_enemy := card.definition.target == CardDef.TARGET_SINGLE_ENEMY
		var side_ok := chosen != null and chosen.is_alive() and (chosen.side == Combatant.SIDE_ENEMY) == wants_enemy
		if not side_ok:
			say("Choose a valid target.")
			return false
	elif target_id == "":
		target_id = _default_target_id(card)
	var ctx_x := 0
	if card.definition.x_cost:  # X: all the Energy left
		ctx_x = energy
		energy = 0
	else:
		energy -= card.get_cost()
	var owner_c := get_combatant(card.owner_character_id)
	say("%s plays %s%s." % [owner_c.display_name, card.get_card_name(), " (X = %d)" % ctx_x if card.definition.x_cost else ""])
	deck.remove_from_hand(card)
	var ctx := EffectContext.new(self, owner_c, card, target_id)
	ctx.x_value = ctx_x
	CardEffects.resolve_all(card.get_effects(), ctx)
	var exhausted := card.exhausts()
	if exhausted:
		deck.send_to_exhaust(card)
	else:
		deck.send_to_discard(card)
	if exhausted and not card.definition.token:
		passives.on_event({"type": "card_exhausted", "source": owner_c, "card": card})
	var previous_owner := last_card_owner_id
	last_card_owner_id = card.owner_character_id
	cards_played_this_turn += 1
	passives.on_event({"type": "card_played", "source": owner_c, "card": card, "previous_owner_id": previous_owner, "cards_played": cards_played_this_turn})
	if not _check_end():
		changed.emit()
	return true


func end_player_turn() -> void:
	if state != State.PLAYER_TURN:
		return
	passives.on_event({"type": "turn_end", "turn": turn})
	if _check_end():  # an end-of-turn power may fell the last enemy
		changed.emit()
		return
	state = State.ENEMY_TURN
	deck.discard_hand()
	_run_enemy_turn()
	if state == State.ENEMY_TURN:
		_begin_player_turn()


## Potions that act on the whole party instead of one drinker (apothecary brews):
##   block N (every living sister gains N Block), energy N (gain N Energy now), draw N (draw N cards).
const POTION_PARTY_EFFECTS := ["block", "energy", "draw"]


func _use_party_potion(item_id: String, item: Dictionary, effect: Dictionary) -> String:
	var value := int(effect.get("value", 0))
	var living := get_living_party()
	if living.is_empty():
		return "Nobody can drink it."
	inventory.remove_item(item_id)
	match str(effect["type"]):
		"block":
			for c in living:
				c.add_block(value)
			visual_event.emit({"kind": "block", "card_id": "", "specialization_id": "", "source_id": living[0].id, "target_ids": living.map(func(c: Combatant) -> String: return c.id), "target_group": CardDef.TARGET_ALL_ALLIES, "item_id": item_id})
		"energy":
			energy += value
		"draw":
			deck.draw(value)
	say("The party uses %s." % str(item.get("name", item_id)))
	changed.emit()
	return ""


## Uses a consumable on the most wounded living party member. Returns "" or an error text.
## target_id: the ally who drinks it (chosen on screen); "" picks the most wounded living ally.
func use_potion(item_id: String, target_id: String = "") -> String:
	if state != State.PLAYER_TURN:
		return "It is not your turn."
	var item := DataRegistry.get_item(item_id)
	if item.is_empty() or inventory == null or inventory.count_of(item_id) <= 0:
		return "You do not have that item."
	var effect: Dictionary = item.get("effect", {})
	if POTION_PARTY_EFFECTS.has(str(effect.get("type", ""))):
		return _use_party_potion(item_id, item, effect)
	if effect.get("type", "") != "heal":
		return "That item cannot be used now."
	var best: Combatant = null
	if target_id != "":
		best = get_combatant(target_id)
		if best == null or best.side != Combatant.SIDE_PARTY or not best.is_alive():
			return "Choose a living ally."
		if best.hp >= best.max_hp:
			return "%s is already at full health." % best.display_name
	else:
		for c in get_living_party():
			if c.hp < c.max_hp and (best == null or float(c.hp) / c.max_hp < float(best.hp) / best.max_hp):
				best = c
	if best == null:
		return "Nobody needs healing."
	inventory.remove_item(item_id)
	best.heal(int(effect.get("value", 0)))
	say("%s uses %s on %s." % ["The party", str(item.get("name", item_id)), best.display_name])
	visual_event.emit({"kind": "heal", "card_id": "", "specialization_id": "", "source_id": best.id, "target_ids": [best.id], "target_group": CardDef.TARGET_SINGLE_ALLY, "item_id": item_id})
	changed.emit()
	return ""


## Writes combat results (HP) back to the persistent party. Fallen members rise on victory.
func commit_to_party() -> void:
	for c in party_combatants:
		var member := party.get_member(c.id)
		if member != null:
			member.current_hp = c.hp
	if state == State.VICTORY:
		party.revive_fallen(GameConfig.FALLEN_REVIVE_HP)


## A Power card was played: its passive joins the combat and its stats add up on the owner.
func add_power(owner_c: Combatant, power: Dictionary, card_name: String) -> void:
	if owner_c == null or power.is_empty():
		return
	if power.has("trigger") and power.has("effect"):
		var passive := power.duplicate(true)
		passive["name"] = str(power.get("name", card_name))
		passives.add_power(owner_c.id, passive)
	var stats: Dictionary = power.get("stats", {})
	owner_c.power_damage += int(stats.get("damage", 0))
	owner_c.power_block += int(stats.get("block", 0))
	var power_id := str(power.get("id", card_name))
	for existing in owner_c.powers:
		if existing["id"] == power_id:
			existing["count"] = int(existing["count"]) + 1
			say("%s's %s grows stronger (x%d)." % [owner_c.display_name, existing["name"], existing["count"]])
			return
	owner_c.powers.append({"id": power_id, "name": str(power.get("name", card_name)), "description": str(power.get("description", "")), "count": 1})
	say("%s gains the power %s." % [owner_c.display_name, str(power.get("name", card_name))])


func say(text: String) -> void:
	message.emit(text)


## Adds surplus magic (extra Energy or extra cards). Only counts during the player's turn.
func add_aether(amount: int, source: Combatant = null) -> void:
	if amount <= 0 or state != State.PLAYER_TURN:
		return
	var before := aether
	aether = mini(MAX_AETHER, aether + amount)
	if aether > before:
		visual_event.emit({"kind": "aether_gained", "card_id": "", "specialization_id": "", "source_id": source.id if source != null else "", "target_ids": [], "target_group": "", "amount": aether - before, "total": aether})


## Uses up all Aether; returns how much there was.
func spend_aether() -> int:
	var spent := aether
	aether = 0
	return spent


# --- Internals ---------------------------------------------------------------

func _spawn_enemies(enemy_ids: Array) -> void:
	var totals: Dictionary = {}
	for enemy_id: String in enemy_ids:
		totals[enemy_id] = int(totals.get(enemy_id, 0)) + 1
	var seen: Dictionary = {}
	for i in enemy_ids.size():
		var def := DataRegistry.get_enemy(str(enemy_ids[i]))
		if def == null:
			push_warning("CombatManager: unknown enemy '%s'" % enemy_ids[i])
			continue
		var c := Combatant.new()
		c.id = "%s_%d" % [def.id, i]
		c.display_name = def.display_name
		if totals[def.id] > 1:
			var n := int(seen.get(def.id, 0))
			c.display_name += " " + char(65 + n)
			seen[def.id] = n + 1
		c.side = Combatant.SIDE_ENEMY
		c.max_hp = def.max_hp
		c.hp = def.max_hp
		c.enemy_def = def
		c.accent_color = def.color
		c.affinity = def.affinity()
		c.base_initiative = def.initiative
		enemies.append(c)


func _living(list: Array[Combatant]) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c in list:
		if c.is_alive():
			result.append(c)
	return result


func _default_target_id(card: CardInstance) -> String:
	match card.definition.target:
		CardDef.TARGET_SINGLE_ENEMY:
			var alive := get_living_enemies()
			return alive[0].id if not alive.is_empty() else ""
		CardDef.TARGET_SINGLE_ALLY:
			var alive_party := get_living_party()
			return alive_party[0].id if not alive_party.is_empty() else ""
	return ""


func _begin_player_turn() -> void:
	turn += 1
	state = State.PLAYER_TURN
	energy = max_energy
	aether = 0
	cards_played_this_turn = 0
	passives.reset_turn()
	last_card_owner_id = ""
	for c in party_combatants:
		c.block = 0
	if turn == 1:
		_apply_relics_at_start()
	deck.draw(maxi(1, HAND_SIZE + RelicEffects.stat(inventory, "hand_size") + (RelicEffects.total(inventory, "first_turn_draw") if turn == 1 else 0) - _use_draw_penalties()))
	say("— Turn %d —" % turn)
	# Equipment and passives that act at the start of a turn (turn 1 = the start of the battle).
	passives.on_event({"type": "turn_start", "turn": turn})
	if _check_end():  # a relic or item may have felled the last enemy (Mercury Bell, Dragon Heart)
		changed.emit()
		return
	changed.emit()


## Quicksand: every living party member with a draw-penalty status costs the party that many cards
## this turn (at most MAX_DRAW_PENALTY in total) and uses up one stack of it.
const MAX_DRAW_PENALTY := 1  # three Sand Webs used to cut the hand from 5 to 3 cards for good


func _use_draw_penalties() -> int:
	var penalty := 0
	for c in get_living_party():
		for status_id: String in c.statuses.keys():
			var status_def := DataRegistry.get_status(status_id)
			if status_def == null or status_def.draw_penalty <= 0:
				continue
			penalty += status_def.draw_penalty
			c.statuses[status_id]["stacks"] = int(c.statuses[status_id]["stacks"]) - 1
			if int(c.statuses[status_id]["stacks"]) <= 0:
				c.statuses.erase(status_id)
			say("%s sinks in the %s: one card fewer this turn." % [c.display_name, status_def.display_name])
	return mini(penalty, MAX_DRAW_PENALTY)


## Relics that act at the start of a battle (first player turn only).
func _apply_relics_at_start() -> void:
	var block := RelicEffects.total(inventory, "combat_start_block")
	if block > 0:
		for c in party_combatants:
			c.add_block(block)
		say("Relics grant %d Block to the party." % block)


## Damage from an attack (cards, enemy moves, passives). The element rule comes first
## (DamageTypes.apply: weapon bonus, weakness / resistance, Chill), then Block, then HP. If the target
## bleeds and the hit cost HP, Bleed adds its stacks as extra HP loss (ignoring Block and elements)
## and drops by 1. Returns the total HP lost. Status ticks do not go through here (never trigger Bleed).
## last_hit holds the outcome for the log and presentation: {base, final, element, pct}.
var last_hit: Dictionary = {}


func hit(target: Combatant, amount: int, element: String = DamageTypes.PHYSICAL, source: Combatant = null) -> int:
	element = DamageTypes.normalize(element)
	var pct := DamageTypes.modifier(element, source, target)
	var final_amount := DamageTypes.apply(amount, element, source, target)
	last_hit = {"base": amount, "final": final_amount, "element": element, "pct": pct}
	# "Weak!" / "Resist" pop-ups describe the TARGET only (weakness, resistance, Chill, Soaked), never
	# the attacker's weapon or Sandblind, and only when they really change the number.
	var target_pct := DamageTypes.modifier(element, null, target)
	if target_pct != 0 and amount > 0 and DamageTypes.apply(amount, element, null, target) != amount:
		visual_event.emit({"kind": "affinity", "card_id": "", "specialization_id": "", "source_id": source.id if source != null else "", "target_ids": [target.id], "target_group": "", "element": element, "pct": target_pct})
	# A status that makes this hit land harder (Oiled + fire, Soaked + lightning...) gets its own
	# visual (VFX rule on kind "status_exploit" + status_id), e.g. the oil bursting into flame.
	if amount > 0:
		for status_id: String in target.statuses.keys():
			var vulnerable_def := DataRegistry.get_status(status_id)
			if vulnerable_def != null and vulnerable_def.vulnerable_elements.has(element):
				visual_event.emit({"kind": "status_exploit", "card_id": "", "specialization_id": "", "source_id": source.id if source != null else "", "target_ids": [target.id], "target_group": "", "element": element, "status_id": status_id})
	var was_alive := target.is_alive()
	var lost := target.take_damage(final_amount)
	if was_alive and not target.is_alive() and target.side != Combatant.SIDE_PARTY and source != null and source.side == Combatant.SIDE_PARTY:
		passives.on_event({"type": "enemy_killed", "source": source, "target": target})
	_react(source, target, element, amount)
	if lost <= 0 or not target.is_alive():
		return lost
	for status_id: String in target.statuses.keys():
		var status_def := DataRegistry.get_status(status_id)
		if status_def == null or status_def.on_hit != "stacks":
			continue
		var stacks := int(target.statuses[status_id]["stacks"])
		var extra := target.take_damage(stacks, true)
		lost += extra
		say("%s bleeds for %d." % [target.display_name, extra])
		target.statuses[status_id]["stacks"] = stacks - 1
		if stacks - 1 <= 0:
			target.statuses.erase(status_id)
		visual_event.emit({"kind": "status_tick", "card_id": "", "specialization_id": "", "source_id": "", "target_ids": [target.id], "target_group": "", "status_id": status_id})
	return lost


## Twin reactions (Reactions): only for real hits, never from a reaction's own damage.
func _react(source: Combatant, target: Combatant, element: String, amount: int) -> void:
	if _reacting or amount <= 0 or source == null or not target.is_alive():
		return
	_reacting = true
	Reactions.try_react(self, source, target, element)
	_reacting = false


## Blight: a living bearer whose HP is at or below its stacks perishes (after the damage ticks).
func _check_executions() -> void:
	for c in enemies + party_combatants:
		if not c.is_alive():
			continue
		for status_id: String in c.statuses.keys():
			var status_def := DataRegistry.get_status(status_id)
			if status_def == null or not status_def.execute:
				continue
			if c.hp <= int(c.statuses[status_id]["stacks"]):
				c.hp = 0
				say("%s succumbs to %s!" % [c.display_name, status_def.display_name])
				visual_event.emit({"kind": "execute", "card_id": "", "specialization_id": "", "source_id": "", "target_ids": [c.id], "target_group": "", "status_id": status_id})
				_on_status_kill(c, status_id)
				break


func _plan_intents() -> void:
	var living := get_living_party()
	for enemy in get_living_enemies():
		enemy.intent = EnemyAI.plan_intent(enemy, living, _rng)
		# Difficulty scales attacks when they are planned, so the intent shows the real number.
		if enemy.intent != null and enemy.intent.type == EnemyIntent.TYPE_ATTACK and not is_equal_approx(enemy.damage_scale, 1.0):
			enemy.intent.value = maxi(1, roundi(enemy.intent.value * enemy.damage_scale))


## Statuses that tick at the start of the enemy phase (Burn). Runs for every living combatant,
## whoever applied the status, so Burn keeps ticking even if its applier has fallen.
func _tick_statuses(timing: String) -> void:
	for c in enemies + party_combatants:
		if not c.is_alive():
			continue
		for status_id: String in c.statuses.keys():
			var status_def := DataRegistry.get_status(status_id)
			if status_def == null or not status_def.ticks_at(timing):
				continue
			var tick := status_def.tick_amount(int(c.statuses[status_id]["stacks"]))
			if status_def.tick_element != "":
				tick = DamageTypes.apply(tick, status_def.tick_element, null, c)  # Burn = fire, Poison = poison
			var lost := c.take_damage(tick, status_def.tick_ignores_block)
			say("%s suffers %d damage from %s (%d lost)." % [c.display_name, tick, status_def.display_name, lost])
			visual_event.emit({"kind": "status_tick", "card_id": "", "specialization_id": "", "source_id": "", "target_ids": [c.id], "target_group": "", "status_id": status_id})
			if not c.is_alive():
				say("%s has fallen!" % c.display_name)
				_on_status_kill(c, status_id)
				break


## An enemy killed by a status (Poison, Burn, Blight) counts as killed by the sister who applied it.
func _on_status_kill(victim: Combatant, status_id: String) -> void:
	if victim.side == Combatant.SIDE_PARTY:
		return
	var killer := get_combatant(victim.get_status_source(status_id))
	if killer != null and killer.side == Combatant.SIDE_PARTY and killer.is_alive():
		passives.on_event({"type": "enemy_killed", "source": killer, "target": victim})


## A fallen combatant keeps no statuses, block or intent.
func _cleanup_fallen() -> void:
	for c in enemies + party_combatants:
		if not c.is_alive():
			c.clear_combat_state()
			if c.side == Combatant.SIDE_PARTY and deck != null:
				deck.set_owner_inactive(c.id)  # Only the remaining characters' cards are drawn.


func _run_enemy_turn() -> void:
	_tick_statuses(StatusDef.TICK_ENEMY_PHASE_START)
	_check_executions()
	_cleanup_fallen()
	if _check_end():
		return
	for enemy in enemies_in_initiative_order():
		enemy.block = 0
		if enemy.will_freeze():
			_freeze(enemy)
			continue
		if not enemy.is_alive():  # thorns may fell an enemy before its turn comes
			continue
		_execute_intent(enemy)
		if party.members.is_empty() or get_living_party().is_empty():
			break
	if _check_end():
		return
	for c in party_combatants + enemies:
		c.tick_statuses()
	_plan_intents()


## Living enemies in the order they act: highest initiative first (ties keep the battlefield order).
func enemies_in_initiative_order() -> Array[Combatant]:
	var living := get_living_enemies()
	var indexed: Array = []
	for i in living.size():
		indexed.append([living[i], i])
	indexed.sort_custom(func(a: Array, b: Array) -> bool:
		var ia := (a[0] as Combatant).initiative()
		var ib := (b[0] as Combatant).initiative()
		return ia > ib if ia != ib else int(a[1]) < int(b[1]))
	var ordered: Array[Combatant] = []
	for entry: Array in indexed:
		ordered.append(entry[0])
	return ordered


## Chill brought its initiative to 0: the enemy loses this action, and the Chill shatters (removed),
## so the same enemy cannot be kept frozen without applying Chill again.
func _freeze(enemy: Combatant) -> void:
	for status_id: String in enemy.statuses.keys():
		var status_def := DataRegistry.get_status(status_id)
		if status_def != null and status_def.initiative_per_stack != 0:
			enemy.statuses.erase(status_id)
	say("%s is Frozen solid and loses its turn!" % enemy.display_name)
	visual_event.emit({"kind": "frozen", "card_id": "", "specialization_id": "", "source_id": enemy.id, "target_ids": [enemy.id], "target_group": CardDef.TARGET_SINGLE_ENEMY})


func _execute_intent(enemy: Combatant) -> void:
	var intent := enemy.intent
	if intent == null:
		return
	match intent.type:
		EnemyIntent.TYPE_ATTACK:
			# One target (Taunt aware) or, for "target": "all" actions, every living party member.
			var targets: Array[Combatant] = []
			if intent.hits_all:
				targets = get_living_party()
			else:
				var single := EnemyAI.resolve_target(enemy, party_combatants)
				if single != null:
					targets.append(single)
			var hit_ids: Array[String] = []
			for target in targets:
				var had_block := target.block > 0
				var lost := hit(target, intent.value, intent.element, enemy)
				say("%s uses %s on %s (%d lost)." % [enemy.display_name, intent.action_name, target.display_name, lost])
				hit_ids.append(target.id)
				if not target.is_alive():
					say("%s has fallen!" % target.display_name)
					continue
				if intent.status_id != "" and intent.status_value > 0 and target.immunities.has(intent.status_id):
					say("%s's gear wards off the %s." % [target.display_name, intent.status_id.capitalize()])
				elif intent.status_id != "" and intent.status_value > 0:
					target.add_status(intent.status_id, intent.status_value, enemy.id)
					var status_def := DataRegistry.get_status(intent.status_id)
					say("%s is afflicted with %d %s." % [target.display_name, intent.status_value, status_def.display_name if status_def != null else intent.status_id.capitalize()])
				if had_block and lost == 0 and not intent.hits_all:
					passives.on_event({"type": "attack_absorbed", "source": enemy, "target": target})
				passives.on_event({"type": "attacked", "source": enemy, "target": target})
				if not enemy.is_alive():
					break
			if not hit_ids.is_empty():
				visual_event.emit({"kind": "enemy_attack", "card_id": "", "specialization_id": "", "source_id": enemy.id, "target_ids": hit_ids, "target_group": CardDef.TARGET_ALL_ALLIES if intent.hits_all else CardDef.TARGET_SINGLE_ALLY, "status_id": intent.status_id, "element": intent.element, "action_id": intent.action_id})
		EnemyIntent.TYPE_DEFEND:
			enemy.add_block(intent.value)
			say("%s uses %s." % [enemy.display_name, intent.action_name])
			visual_event.emit({"kind": "enemy_defend", "card_id": "", "specialization_id": "", "source_id": enemy.id, "target_ids": [enemy.id], "target_group": CardDef.TARGET_SELF})


## Ends combat if either side is eliminated. Returns true if combat ended.
func _check_end() -> bool:
	if state == State.VICTORY or state == State.DEFEAT:
		return true
	_cleanup_fallen()
	var result := ""
	if get_living_enemies().is_empty():
		state = State.VICTORY
		result = RESULT_VICTORY
	elif get_living_party().is_empty():
		state = State.DEFEAT
		result = RESULT_DEFEAT
	if result == "":
		return false
	commit_to_party()
	for c in enemies + party_combatants:
		c.clear_combat_state()  # No effect outlives the combat.
	say("Victory!" if result == RESULT_VICTORY else "The party has fallen...")
	changed.emit()
	ended.emit(result)
	return true
