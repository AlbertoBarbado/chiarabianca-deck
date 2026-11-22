extends SceneTree
## Milestone 4B tests: combat VFX mapping, fallbacks, positioning, timing and cleanup. Run:
##   godot --headless --path . --script res://tests/combat/run_vfx_tests.gd

var _failures: int = 0
var _checks: int = 0
var _rects: Dictionary = {}


func _initialize() -> void:
	_run()


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _run() -> void:
	DataRegistry.reload()
	VfxCatalog.reload()
	_test_catalog()
	_test_card_coverage()
	_test_event_timing()
	_test_gameplay_unchanged()
	_setup_rects()
	await _test_manager()
	await _test_cleanup_and_animation()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- helpers -----------------------------------------------------------------

func _party(chiara_spec: String, bianca_spec: String) -> Party:
	return Party.from_selection({"chiara": chiara_spec, "bianca": bianca_spec})


func _combat(party: Party, seed_value: int = 7) -> CombatManager:
	var combat := CombatManager.new()
	combat.setup(party, DataRegistry.get_encounter("castle_training_01"), Inventory.new(), seed_value)
	combat.start()
	return combat


func _hand_card(combat: CombatManager, card_id: String) -> CardInstance:
	var instance := CardInstance.new()
	instance.definition = DataRegistry.get_card(card_id)
	instance.owner_character_id = instance.definition.owner_character_id
	combat.deck.hand.append(instance)
	return instance


func _setup_rects() -> void:
	_rects = {
		"chiara": Rect2(40, 400, 560, 100), "bianca": Rect2(660, 400, 560, 100),
		"enemy_0": Rect2(300, 60, 210, 150), "enemy_1": Rect2(540, 60, 210, 150), "enemy_2": Rect2(780, 60, 210, 150),
	}


func _locate(id: String) -> Rect2:
	return _rects.get(id, Rect2())


func _manager(quality: String = "full") -> CombatVfxManager:
	var manager := CombatVfxManager.new()
	manager.size = Vector2(1280, 720)
	root.add_child(manager)
	manager.setup(null, _locate, quality)
	return manager


# --- tests -------------------------------------------------------------------

func _test_catalog() -> void:
	print("Catalog and mapping")
	var rules_ok := true
	for rule: Dictionary in VfxCatalog.rules():
		rules_ok = rules_ok and not VfxCatalog.effect(str(rule.get("vfx", ""))).is_empty()
	check(rules_ok, "every mapping rule points at a defined effect")
	var sprites_ok := true
	for id in VfxCatalog.effect_ids():
		sprites_ok = sprites_ok and ResourceLoader.exists(VfxCatalog.sprite_path(VfxCatalog.effect(id)))
	check(sprites_ok, "every effect's sprite file exists (%d effects)" % VfxCatalog.effect_ids().size())
	check(VfxCatalog.match_event({"kind": "damage", "card_id": "chiara_fire_fireball", "specialization_id": "fire"}) == "fireball", "Fireball damage -> fireball")
	check(VfxCatalog.match_event({"kind": "apply_status", "status_id": "burn", "card_id": "chiara_fire_kindle", "specialization_id": "fire"}) == "burn_apply", "Burn applied -> burn_apply")
	check(VfxCatalog.match_event({"kind": "status_tick", "status_id": "burn"}) == "burn_tick", "Burn tick -> burn_tick")
	check(VfxCatalog.match_event({"kind": "heal", "card_id": "bianca_holy_touch", "specialization_id": "holy", "target_group": "single_ally"}) == "holy_heal", "Holy single heal -> holy_heal (golden light)")
	check(VfxCatalog.match_event({"kind": "heal", "card_id": "bianca_holy_benediction", "specialization_id": "holy", "target_group": "all_allies"}) == "party_heal", "Benediction heal -> party_heal")
	check(VfxCatalog.match_event({"kind": "block", "card_id": "bianca_holy_benediction", "specialization_id": "holy", "target_group": "all_allies"}) == "sanctified_ward", "Benediction Block -> sanctified_ward")
	check(VfxCatalog.match_event({"kind": "damage", "card_id": "chiara_arcana_bolt", "specialization_id": "arcana"}) == "arcane_bolt", "Arcane damage -> arcane_bolt")
	check(VfxCatalog.match_event({"kind": "damage", "card_id": "chiara_arcana_starfall", "specialization_id": "arcana", "target_group": "all_enemies"}) == "arcane_explosion", "Arcane area attack -> arcane_explosion")
	check(VfxCatalog.match_event({"kind": "damage", "card_id": "bianca_tanking_strike", "specialization_id": "tanking"}) == "earth_spike", "Earth/Tanking damage -> earth_spike")
	check(VfxCatalog.match_event({"kind": "apply_status", "status_id": "taunt", "card_id": "bianca_tanking_challenge", "specialization_id": "tanking"}) == "taunt", "Taunt -> taunt")
	check(VfxCatalog.match_event({"kind": "damage", "specialization_id": "frost"}) == "ice_shards" and VfxCatalog.match_event({"kind": "damage", "specialization_id": "wind"}) == "wind_slash", "Ice and Wind damage rules exist for future specializations")
	check(VfxCatalog.match_event({"kind": "apply_status", "status_id": "poison"}) == "poison_burst", "Poison applied -> poison_burst (the dedicated poison sprite)")
	check(VfxCatalog.match_event({"kind": "enemy_attack"}) == "enemy_slash" and VfxCatalog.match_event({"kind": "enemy_defend"}) == "enemy_guard", "enemy attack and defend events have visuals")
	check(VfxCatalog.match_event({"kind": "unknown_kind"}) == "", "unmapped events produce no effect")


func _test_card_coverage() -> void:
	print("Coverage of the four playable specializations")
	var missing: Array[String] = []
	for spec_id in ["arcana", "fire", "tanking", "holy"]:
		var spec := DataRegistry.get_specialization(spec_id)
		var ids: Array[String] = []
		ids.append_array(spec.starting_deck_card_ids)
		ids.append_array(spec.card_pool)
		for card_id in ids:
			var card := DataRegistry.get_card(card_id)
			for effect: Dictionary in card.effects:
				var kind := str(effect.get("effect", ""))
				if not ["damage", "block", "heal", "apply_status"].has(kind):
					continue
				var event := {"kind": kind, "card_id": card.id, "specialization_id": card.specialization_id, "target_group": str(effect.get("target", "")), "status_id": str(effect.get("status_id", ""))}
				if VfxCatalog.match_event(event) == "":
					missing.append("%s:%s" % [card.id, kind])
	check(missing.is_empty(), "every damage/block/heal/status effect of Arcana, Fire, Tanking and Holy cards has a visual (missing: %s)" % ", ".join(missing))


func _test_event_timing() -> void:
	print("Events follow gameplay resolution")
	var combat := _combat(_party("fire", "holy"))
	var enemy := combat.enemies[0]
	var log: Array[Dictionary] = []
	combat.visual_event.connect(func(e: Dictionary) -> void:
		var snapshot: Dictionary = e.duplicate()
		snapshot["enemy_hp"] = enemy.hp
		snapshot["enemy_burn"] = enemy.has_status("burn")
		snapshot["party_hp"] = combat.get_combatant("bianca").hp
		log.append(snapshot))
	combat.energy = 9
	# A card that is only in hand (or cannot be played) emits nothing.
	var ember := _hand_card(combat, "chiara_fire_ember")
	check(log.is_empty(), "no event while a card is merely drawn or displayed")
	combat.energy = 0
	check(not combat.play_card(ember, enemy.id) and log.is_empty(), "an unaffordable card emits no event")
	combat.energy = 9
	var hp_before := enemy.hp
	combat.play_card(ember, enemy.id)
	check(log.size() == 1 and log[0]["kind"] == "damage" and log[0]["enemy_hp"] == hp_before - 6, "damage event is emitted after the damage was applied")
	log.clear()
	var kindle := _hand_card(combat, "chiara_fire_kindle")
	combat.play_card(kindle, enemy.id)
	check(log.size() == 1 and log[0]["kind"] == "apply_status" and log[0]["status_id"] == "burn" and log[0]["enemy_burn"], "Burn application event arrives after Burn was applied")
	log.clear()
	combat.end_player_turn()
	var tick: Array = log.filter(func(e: Dictionary) -> bool: return e["kind"] == "status_tick")
	check(tick.size() == 1 and tick[0]["status_id"] == "burn" and tick[0]["target_ids"] == [enemy.id] and tick[0]["enemy_hp"] < hp_before - 6 + 1, "Burn tick event arrives after the tick damage")

	var holy := _combat(_party("arcana", "holy"))
	holy.energy = 9
	holy.get_combatant("chiara").hp = 30
	holy.get_combatant("bianca").hp = 40
	var holy_log: Array[Dictionary] = []
	holy.visual_event.connect(func(e: Dictionary) -> void: holy_log.append(e.duplicate()))
	holy.play_card(_hand_card(holy, "bianca_holy_benediction"))
	var kinds: Array = holy_log.map(func(e: Dictionary) -> String: return e["kind"])
	check(kinds == ["block", "heal"] and holy_log[0]["target_ids"].size() == 2 and holy_log[1]["target_group"] == "all_allies", "party Block and party heal each announce both living members")
	holy_log.clear()
	holy.play_card(_hand_card(holy, "chiara_arcana_twinbolt"), holy.enemies[0].id)
	var card_events := holy_log.filter(func(e: Dictionary) -> bool: return str(e["card_id"]) != "")  # passive effects (Arcane Flow) announce separately
	check(card_events.size() == 2, "a two-hit card announces both hits")
	var enemy_combat := _combat(_party("fire", "holy"))
	var enemy_log: Array[Dictionary] = []
	var hp_at_event: Array[int] = []
	enemy_combat.visual_event.connect(func(e: Dictionary) -> void:
		if str(e["kind"]).begins_with("enemy_"):
			enemy_log.append(e.duplicate())
			hp_at_event.append(enemy_combat.get_combatant(str(e["target_ids"][0])).hp))
	var party_hp_before: int = enemy_combat.get_combatant("chiara").hp + enemy_combat.get_combatant("bianca").hp
	enemy_combat.end_player_turn()
	var attack_events := enemy_log.filter(func(e: Dictionary) -> bool: return e["kind"] == "enemy_attack")
	check(attack_events.size() >= 1 and enemy_combat.enemies.any(func(e: Combatant) -> bool: return e.id == attack_events[0]["source_id"]) and ["chiara", "bianca"].has(attack_events[0]["target_ids"][0]), "an enemy attack announces the enemy as source and a party member as target")
	var target_max := enemy_combat.get_combatant(str(attack_events[0]["target_ids"][0])).max_hp
	check(hp_at_event[0] < target_max and enemy_combat.get_combatant("chiara").hp + enemy_combat.get_combatant("bianca").hp < party_hp_before, "the enemy attack event arrives after the damage was applied")
	var potion_combat := _combat(_party("arcana", "tanking"))
	potion_combat.get_combatant("chiara").hp = 20
	potion_combat.inventory.add_item("health_potion", 1)
	var potion_log: Array[Dictionary] = []
	potion_combat.visual_event.connect(func(e: Dictionary) -> void: potion_log.append(e.duplicate()))
	potion_combat.use_potion("health_potion")
	check(potion_log.size() == 1 and potion_log[0]["kind"] == "heal" and potion_log[0]["target_ids"] == ["chiara"], "potion healing announces a heal on the healed character")


func _play_script(combat: CombatManager) -> Array:
	combat.energy = 9
	var burn_card := _hand_card(combat, "chiara_fire_immolate")
	var ember := _hand_card(combat, "chiara_fire_ember")
	var ward := _hand_card(combat, "bianca_holy_shield")
	combat.play_card(burn_card, combat.enemies[0].id)
	combat.play_card(ember, combat.enemies[0].id)
	combat.play_card(ward)
	combat.end_player_turn()
	var state: Array = [combat.turn, combat.energy, combat.deck.draw_pile.size(), combat.deck.discard_pile.size()]
	for c in combat.party_combatants + combat.enemies:
		state.append([c.id, c.hp, c.block, c.statuses.keys()])
	return state


func _test_gameplay_unchanged() -> void:
	print("Visuals do not change gameplay")
	var plain := _play_script(_combat(_party("fire", "holy"), 11))
	var watched_combat := _combat(_party("fire", "holy"), 11)
	var counter: Array[int] = [0]
	watched_combat.visual_event.connect(func(_e: Dictionary) -> void: counter[0] += 1)
	var watched := _play_script(watched_combat)
	check(counter[0] >= 4, "the watched run emitted visual events (%d)" % counter[0])
	check(JSON.stringify(plain) == JSON.stringify(watched), "identical seed and plays give identical damage, Block, statuses, deck and turn state with and without listeners")


func _test_manager() -> void:
	print("Manager: positioning, multi-target, fallback, quality")
	var manager := _manager()
	var chiara_event := {"kind": "damage", "card_id": "chiara_fire_fireball", "specialization_id": "fire", "source_id": "chiara", "target_ids": ["enemy_0"], "target_group": "single_enemy"}
	var nodes := manager.spawn_effect("fireball", chiara_event)
	check(nodes.size() == 1 and nodes[0].effect_id == "fireball", "single-target effect spawns one node")
	var target_center: Rect2 = _rects["enemy_0"]
	var node: CombatVfx = nodes[0]
	check(node.size.x > 100 and node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "effect has a scaled size and ignores input")
	node._apply(0.6)  # impact moment: travel 0.42 s of 0.7 s
	check(node.position.distance_to(target_center.get_center() - node.size / 2.0) < 1.0, "projectile reaches the target centre at impact")
	node._apply(0.0)
	check(node.position.distance_to(_rects["chiara"].get_center() - node.size / 2.0) < 1.0, "projectile starts at the source panel")
	check(manager.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the VFX layer lets all input through")

	var wave := manager.spawn_effect("flame_wave", {"kind": "damage", "source_id": "chiara", "target_ids": ["enemy_0", "enemy_1", "enemy_2"], "target_group": "all_enemies"})
	var union: Rect2 = _rects["enemy_0"].merge(_rects["enemy_1"]).merge(_rects["enemy_2"])
	check(wave.size() == 1 and wave[0].size.x <= 520.5 and wave[0].size.x >= 400.0 and absf(wave[0].position.x + wave[0].size.x / 2.0 - union.get_center().x) < 1.0, "all-enemies effect is one sprite centred on the enemy group, capped so it does not bury the panels")
	var many := manager.spawn_effect("fire_bolt", {"kind": "damage", "source_id": "chiara", "target_ids": ["enemy_0", "enemy_1"], "target_group": "all_enemies"})
	check(many.size() == 2, "a per-target effect on several targets spawns one sprite each")
	var ward := manager.spawn_effect("sanctified_ward", {"kind": "block", "source_id": "bianca", "target_ids": ["chiara", "bianca"], "target_group": "all_allies"})
	var ward_centres_ok := ward.size() == 2
	for i in ward.size():
		var id: String = ["chiara", "bianca"][i]
		ward_centres_ok = ward_centres_ok and absf(ward[i].position.x + ward[i].size.x / 2.0 - _rects[id].get_center().x) < 1.0
	check(ward_centres_ok, "party Block puts a ward on each living party member")
	var self_shield := manager.spawn_effect("blessed_shield", {"kind": "block", "source_id": "bianca", "target_ids": ["bianca"], "target_group": "self"})
	check(self_shield.size() == 1 and absf(self_shield[0].position.x + self_shield[0].size.x / 2.0 - _rects["bianca"].get_center().x) < 1.0, "self-targeted effect is centred on the caster")
	var heal := manager.spawn_effect("healing", {"kind": "heal", "source_id": "bianca", "target_ids": ["chiara"], "target_group": "single_ally"})
	check(heal.size() == 1, "ally healing appears on the recipient")
	var burn_apply := manager.spawn_effect("burn_apply", {"kind": "apply_status", "status_id": "burn", "source_id": "chiara", "target_ids": ["enemy_1"]})
	var burn_tick := manager.spawn_effect("burn_tick", {"kind": "status_tick", "status_id": "burn", "source_id": "", "target_ids": ["enemy_1"]})
	check(burn_apply.size() == 1 and burn_tick.size() == 1 and burn_tick[0].size.x < burn_apply[0].size.x, "Burn tick is a smaller effect than Burn application")
	check(manager.spawn_effect("fireball", {"kind": "damage", "target_ids": ["ghost"]}).is_empty(), "a target without an on-screen panel is skipped without error")
	check(manager.spawn_effect("no_such_effect", chiara_event).is_empty(), "an unknown effect id is ignored")
	manager.queue_free()

	var fallback_manager := _manager()
	check(VfxCatalog.effect("fireball").has("sprite"), "effect defs name a sprite")
	var missing_def := {"sprite": "fire/does_not_exist", "blend": "add", "motion": "burst", "duration": 0.3, "width": 100, "color": "#ff8800"}
	var resolved := CombatVfx.resolve_texture(missing_def)
	check(resolved["fallback"] and resolved["texture"] != null, "a missing sprite resolves to a generated fallback texture")
	var fx := CombatVfx.new()
	fallback_manager.add_child(fx)
	fx.play("missing", missing_def, CombatVfx.compute_geometry(missing_def, Vector2(64, 64), [Rect2(100, 100, 200, 100)], Rect2(), 1.0, 210.0), VfxCatalog.quality("full"))
	check(fx.used_fallback and fx.get_node("Sprite") != null, "the effect still plays using the fallback")
	fallback_manager.queue_free()

	var off := _manager("off")
	off.handle_event(chiara_event)
	await process_frame
	await process_frame
	check(off.spawned_count == 0 and off.active_count() == 0, "quality 'off' spawns nothing")
	off.queue_free()
	var reduced := _manager("reduced")
	var reduced_nodes := reduced.spawn_effect("fireball", chiara_event)
	check(reduced_nodes.size() == 1 and reduced_nodes[0].total_time < VfxCatalog.effect("fireball")["duration"], "'reduced' quality shortens effects")
	reduced_nodes[0]._apply(1.0)
	check(reduced.spawn_effect("fire_bolt", {"kind": "damage", "source_id": "chiara", "target_ids": ["enemy_0", "enemy_1", "enemy_2"]}).size() == 1, "'reduced' quality draws one effect per multi-target event")
	reduced.queue_free()
	var capped := _manager()
	var total := 0
	for i in 40:
		total += capped.spawn_effect("burn_tick", {"kind": "status_tick", "status_id": "burn", "target_ids": ["enemy_0"]}).size()
	check(total == int(VfxCatalog.quality("full")["max_active"]) and capped.active_count() == total, "the number of simultaneous effects is capped (%d)" % total)
	capped.queue_free()


func _test_cleanup_and_animation() -> void:
	print("Animation and cleanup")
	var manager := _manager()
	var fire_event := {"kind": "damage", "card_id": "chiara_fire_fireball", "specialization_id": "fire", "source_id": "chiara", "target_ids": ["enemy_0"], "target_group": "single_enemy"}
	var fx: Array[CombatVfx] = manager.spawn_effect("ember_impact", fire_event)
	var burst := fx[0]
	burst._apply(0.0)
	var start_alpha := burst.modulate.a
	burst._apply(0.4)
	var mid_alpha := burst.modulate.a
	var mid_scale := burst.scale.x
	burst._apply(1.0)
	check(start_alpha == 0.0 and mid_alpha > 0.5 and burst.modulate.a < 0.01, "burst fades in and fully fades out")
	burst._apply(0.0)
	check(burst.scale.x < mid_scale, "burst expands over time")

	var projectile := manager.spawn_effect("fireball", fire_event)[0]
	var impacts: Array[int] = [0]
	projectile.impact.connect(func(_at: Vector2) -> void: impacts[0] += 1)
	projectile._apply(0.3)
	projectile._apply(0.8)
	projectile._apply(1.0)
	check(impacts[0] == 1, "a projectile reports its impact exactly once")
	await create_timer(0.1).timeout
	var before := manager.active_count()
	await create_timer(1.6).timeout
	check(before > 0 and manager.active_count() == 0 and manager.get_child_count() == 0, "finished effects free themselves (%d -> 0 nodes)" % before)
	var connected := _combat(_party("fire", "holy"))
	var live := CombatVfxManager.new()
	live.size = Vector2(1280, 720)
	root.add_child(live)
	_rects["enemy_0"] = Rect2(300, 60, 210, 150)
	live.setup(connected, func(id: String) -> Rect2: return _rects.get(id.replace(connected.enemies[0].id, "enemy_0"), Rect2()), "full")
	connected.energy = 9
	var ember := _hand_card(connected, "chiara_fire_ember")
	connected.play_card(ember, connected.enemies[0].id)
	check(live.spawned_count == 0, "nothing is drawn in the same frame the card resolves (waits for the UI to lay out)")
	await process_frame
	await process_frame
	check(live.spawned_count >= 1, "the effect appears after the UI has had a frame to rebuild")
	await create_timer(1.8).timeout
	check(live.active_count() == 0, "effects triggered by real gameplay clean up too")
	live.queue_free()
	manager.queue_free()
