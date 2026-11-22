extends SceneTree
## Every card effect shows a fitting visual when played. For each card (and its upgrade) every
## effect is turned into the event CardEffects announces; the VFX rule that matches it must exist,
## have a sprite, and be specific to the card, its specialization or its status - not only the
## generic fallback for the effect kind. Run:
##   godot --headless --path . --script res://tests/combat/run_card_vfx_audit.gd [-- report]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	DataRegistry.reload()
	VfxCatalog.reload()
	var report := OS.get_cmdline_user_args().has("report")
	var missing: Array[String] = []
	var generic: Array[String] = []
	var no_sprite: Array[String] = []
	var total := 0
	for card_id: String in _playable_card_ids():
		var def: CardDef = DataRegistry.get_card(card_id)
		var effect_lists: Array = [def.effects]
		if not (def.upgrade.get("effects", []) as Array).is_empty():
			effect_lists.append(def.upgrade["effects"])
		var seen: Dictionary = {}
		for effects: Array in effect_lists:
			for effect: Dictionary in effects:
				var event := _event(def, effect)
				var key := "%s|%s|%s" % [event["kind"], event.get("status_id", ""), event.get("target_group", "")]
				if seen.has(key):
					continue
				seen[key] = true
				total += 1
				var rule := _matching_rule(event)
				var label := "%s %s%s" % [card_id, event["kind"], (" " + str(event.get("status_id", ""))) if event.has("status_id") else ""]
				if rule.is_empty():
					missing.append(label)
				else:
					var vfx_id := str(rule.get("vfx", ""))
					if VfxCatalog.sprite_texture(VfxCatalog.effect(vfx_id)) == null:
						no_sprite.append("%s -> %s" % [label, vfx_id])
					if not (rule.has("card_id") or rule.has("specialization_id") or rule.has("status_id")):
						generic.append("%s -> %s" % [label, vfx_id])
				if report:
					print("  %-34s %-26s -> %s" % [card_id, label.trim_prefix(card_id + " "), str(rule.get("vfx", "NONE"))])
	check(total >= 100, "the audit covers every playable card (%d card effects)" % total)
	check(missing.is_empty(), "every card effect has a visual (missing: %s)" % ", ".join(missing))
	check(no_sprite.is_empty(), "every matched visual has its sprite (%s)" % ", ".join(no_sprite))
	check(generic.is_empty(), "no card falls back to a generic visual (%d generic: %s)" % [generic.size(), ", ".join(generic)])
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## Every card a player can meet: the starting decks, reward pools and epic pools of every specialization.
func _playable_card_ids() -> Array[String]:
	var ids: Array[String] = []
	for character_id in ["chiara", "bianca"]:
		for spec: SpecializationDef in DataRegistry.get_specializations_for(character_id):
			for card_id: String in spec.starting_deck_card_ids + spec.card_pool + spec.epic_pool:
				if not ids.has(card_id) and DataRegistry.get_card(card_id) != null:
					ids.append(card_id)
	return ids


func check(ok: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


## The same event CardEffects._announce emits for this effect.
func _event(def: CardDef, effect: Dictionary) -> Dictionary:
	var kind := str(effect.get("effect", ""))
	if kind == "spend_aether":
		kind = "aether_spent"  # CardEffects emits this event when the Aether is released
	if kind == "multiply_status":
		kind = "apply_status"  # Catalyst shows as more of the status landing
	if kind == "multiply_block":
		kind = "block"  # Entrench shows as Block landing
	var event := {"kind": kind, "card_id": def.id, "specialization_id": def.specialization_id, "target_group": str(effect.get("target", ""))}
	if kind == "apply_status":
		event["status_id"] = str(effect.get("status_id", ""))
	if kind == "damage":
		event["element"] = DamageTypes.for_card_effect(effect, def)
	return event


func _matching_rule(event: Dictionary) -> Dictionary:
	for rule: Dictionary in VfxCatalog.rules():
		var ok := true
		for key in VfxCatalog.MATCH_KEYS:
			if rule.has(key) and str(rule[key]) != str(event.get(key, "")):
				ok = false
				break
		if ok:
			return rule
	return {}
