extends Node
## Plays real cards through the combat screen and captures each effect mid-animation.
## Run windowed so screenshots work:
##   godot --path . res://tests/vfx_gallery_test.tscn -- <screenshot_dir>
## Exit code 1 if an expected effect did not appear or a card changed its gameplay outcome.

var _failures := 0
var _shot_dir := ""
var _peak_nodes := 0
var _frame_samples: Array[float] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_vfx_save.json"
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.4)
	await _party("fire", "holy", "castle_final_regular_01")
	await _fire_holy()
	await _party("arcana", "tanking", "castle_final_regular_01")
	await _arcana_tanking()
	var avg := 0.0
	for sample in _frame_samples:
		avg += sample
	avg = avg / maxf(1.0, _frame_samples.size())
	print("Peak simultaneous effect nodes: %d; average frame time while effects ran: %.2f ms" % [_peak_nodes, avg * 1000.0])
	print("VFX gallery: %d failures" % _failures)
	GameState.delete_save()
	get_tree().quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _party(chiara_spec: String, bianca_spec: String, encounter_id: String) -> void:
	SceneRouter.go(SceneRouter.Screen.MAIN_MENU)
	await _wait(0.3)
	GameState.reset_selection()
	GameState.select_specialization("chiara", chiara_spec)
	GameState.select_specialization("bianca", bianca_spec)
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	# Reward-pool cards are not in the starting decks; add them so every card can be shown.
	for member in GameState.party.members:
		for card_id in member.specialization.card_pool:
			member.add_card(card_id)
	GameState.get_current_node().encounter_id = encounter_id
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(0.5)


func _screen() -> Node:
	return SceneRouter.current_screen


## Puts a card into the hand, plays it through the UI handlers and captures the effect.
func _play(card_id: String, shot_name: String, wait_for_shot: float, target: String = "") -> void:
	var screen := _screen()
	var combat: CombatManager = screen.combat
	combat.energy = 9
	var card: CardInstance = null
	for pile: Array[CardInstance] in [combat.deck.hand, combat.deck.draw_pile, combat.deck.discard_pile]:
		for candidate in pile:
			if card == null and candidate.definition.id == card_id:
				card = candidate
	check(card != null, "%s is in the party deck" % card_id)
	if card == null:
		return
	for pile: Array[CardInstance] in [combat.deck.draw_pile, combat.deck.discard_pile]:
		pile.erase(card)
	if not combat.deck.hand.has(card):
		combat.deck.hand.append(card)
	screen._refresh()
	var before: int = screen._vfx.spawned_count
	screen._on_card_pressed(card)
	if screen._selected_card != null:
		var wants_enemy: bool = card.definition.target == CardDef.TARGET_SINGLE_ENEMY
		var chosen := target if target != "" else (combat.get_living_enemies()[0].id if wants_enemy else "chiara")
		screen._play_selected(chosen)
	var sampling := true
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(wait_for_shot * 1000.0):
		await get_tree().process_frame
		_peak_nodes = maxi(_peak_nodes, screen._vfx.active_count())
		if sampling:
			_frame_samples.append(1.0 / maxf(1.0, Engine.get_frames_per_second()))
	await _shot(shot_name)
	check(screen._vfx.spawned_count > before, "%s showed a visual effect" % card_id)
	await _wait(1.0)  # let it finish before the next case
	check(screen._vfx.active_count() == 0, "%s effect cleaned up" % card_id)


func _hurt_party() -> void:
	var combat: CombatManager = _screen().combat
	combat.get_combatant("chiara").hp = 25
	combat.get_combatant("bianca").hp = 40
	_screen()._refresh()


func _fire_holy() -> void:
	print("Fire + Holy")
	await _play("chiara_fire_fireball", "30_fx_fireball_flight", 0.2)
	await _play("chiara_fire_kindle", "31_fx_burn_apply", 0.35)
	await _play("chiara_fire_wave", "32_fx_flame_wave_area", 0.32)
	await _play("chiara_fire_inferno", "33_fx_inferno", 0.3)
	await _play("chiara_fire_cinderward", "34_fx_fire_shield", 0.3)
	await _play("bianca_holy_smite", "35_fx_holy_smite", 0.28)
	await _play("bianca_holy_shield", "36_fx_blessed_shield", 0.3)
	_hurt_party()
	await _play("bianca_holy_touch", "37_fx_healing", 0.35, "chiara")
	await _play("bianca_holy_benediction", "38_fx_party_ward_and_heal", 0.4)
	await _play("bianca_holy_judgment", "39_fx_divine_judgment", 0.35)
	var combat: CombatManager = _screen().combat
	var before: int = _screen()._vfx.spawned_count
	_screen()._on_end_turn()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 300:
		await get_tree().process_frame
	await _shot("40_fx_burn_tick")
	check(_screen()._vfx.spawned_count > before, "Burn tick at the start of the enemy phase showed an effect")
	await _wait(1.2)
	check(combat != null, "combat still running after all effects")


func _arcana_tanking() -> void:
	print("Arcana + Tanking")
	await _play("chiara_arcana_bolt", "41_fx_arcane_bolt", 0.2)
	await _play("chiara_arcana_starfall", "42_fx_arcane_explosion_area", 0.3)
	await _play("chiara_arcana_barrier", "43_fx_magic_barrier", 0.3)
	await _play("chiara_arcana_surge", "44_fx_mana_surge", 0.3)
	await _play("bianca_tanking_challenge", "45_fx_taunt", 0.3)
	await _play("bianca_tanking_strike", "46_fx_earth_spike", 0.3)
	await _play("bianca_tanking_sweep", "47_fx_earth_shatter_area", 0.3)
	await _play("bianca_tanking_wall", "48_fx_stone_wall_party", 0.3)
