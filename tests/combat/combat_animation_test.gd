extends Node
## Combat animation and sprite checks for every enemy family and the party: sprite shader, motion
## profiles (stand / caster / beast / heavy / hover / slither), attack lunge, hit flash, block and
## cast glow, target outline, backdrop lighting, heavy impact shake and the death dissolve.
##   godot --path . res://tests/combat/combat_animation_test.tscn -- <screenshot_dir>
## With a screenshot folder it also captures each fight at rest and mid-motion for visual review.

const FIGHTS := [
	{"key": "castle", "map": "royal_castle_tutorial", "enemies": ["hall_guard", "hall_captain", "guard_recruit"]},
	{"key": "forest_a", "map": "enchanted_forest", "enemies": ["forest_wolf", "forest_bear", "forest_spider"]},
	{"key": "forest_b", "map": "enchanted_forest", "enemies": ["forest_boar", "forest_troll", "forest_drake"]},
	{"key": "serpent", "map": "enchanted_forest", "enemies": ["forest_serpent"], "boss": true},
	{"key": "hollow", "map": "crystal_hollow_demo", "enemies": ["demo_cave_bat", "demo_crystal_golem", "demo_shadow_wraith"]},
	{"key": "wyrm", "map": "crystal_hollow_demo", "enemies": ["demo_fungal_shambler", "demo_crystal_wyrm"], "boss": true},
]
const EXPECTED_PROFILES := {"forest_wolf": "beast", "forest_bear": "heavy", "forest_troll": "heavy", "forest_serpent": "slither",
	"demo_cave_bat": "hover", "demo_shadow_wraith": "hover", "demo_crystal_golem": "heavy", "hall_guard": "stand"}

var _failures := 0
var _checks := 0
var _shot_dir := ""
var _impacts := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_combat_animation.json"
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.5)
	await _run()
	GameState.delete_save()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	_checks += 1
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


func _start(map_id: String) -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "tanking")
	GameState.create_party_from_selection()
	GameState.next_map_id = map_id
	GameState.begin_adventure()
	GameState.next_map_id = GameConfig.DEFAULT_MAP_ID


func _fight(fight: Dictionary) -> Node:
	_start(str(fight["map"]))
	var encounter_id := "anim_" + str(fight["key"])
	DataRegistry.encounters[encounter_id] = {"id": encounter_id, "name": "Animation " + str(fight["key"]), "enemies": fight["enemies"], "gold_reward": 0}
	GameState.room_state = {}
	GameState.get_current_node().encounter_id = encounter_id
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.0)
	var screen := SceneRouter.current_screen
	var cinematic := screen.find_child("EliteBanner", true, false)
	if cinematic != null:  # skip a boss intro
		cinematic.queue_free()
		await _wait(0.2)
	return screen


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	for fight: Dictionary in FIGHTS:
		await _check_fight(fight)


func _check_fight(fight: Dictionary) -> void:
	var key := str(fight["key"])
	var screen := await _fight(fight)
	var field: CombatBattlefield = screen._battlefield
	if not field.impact.is_connected(_count_impact):
		field.impact.connect(_count_impact)
	var views := field.all_views()
	check(views.all(func(v: CombatUnitView) -> bool: return v._art.material is ShaderMaterial), "%s: every sprite uses the combat sprite shader" % key)
	for enemy: Combatant in screen.combat.enemies:
		var def_id := field._definition_id(enemy.id)
		if EXPECTED_PROFILES.has(def_id):
			check(field.enemy_views[enemy.id].motion_profile_id() == EXPECTED_PROFILES[def_id], "%s: %s moves like a %s" % [key, def_id, EXPECTED_PROFILES[def_id]])
	check(field.party_views["chiara"].motion_profile_id() == "caster", "%s: Chiara moves like a caster" % key)
	var light := CombatPresentation.lighting(str(screen._backdrop().get("asset_id", "")))
	var rim: Color = field.party_views["bianca"]._material.get_shader_parameter("rim_color")
	check(rim.is_equal_approx(light["rim"]), "%s: sprites take the backdrop's rim light" % key)
	await _shot("anim_%s_01_rest" % key)

	# Hover creatures bob while idle.
	for enemy: Combatant in screen.combat.enemies:
		var view: CombatUnitView = field.enemy_views[enemy.id]
		if view.motion_profile_id() == "hover":
			var y0 := view._float.position.y
			await _wait(0.45)
			check(absf(view._float.position.y - y0) > 0.5, "%s: %s hovers (bobs) while idle" % [key, enemy.display_name])

	# An enemy attacks the party: wind-up, lunge, then the target is hit (white flash, knockback).
	var attacker: Combatant = screen.combat.enemies[screen.combat.enemies.size() - 1]
	var attacker_view: CombatUnitView = field.enemy_views[attacker.id]
	var impacts_before := _impacts
	screen.combat.visual_event.emit({"kind": "enemy_attack", "source_id": attacker.id, "target_ids": ["bianca"], "card_id": "", "specialization_id": "", "target_group": ""})
	var bianca_view: CombatUnitView = field.party_views["bianca"]
	await _wait(0.3)
	check(attacker_view._art.position.x > 4.0, "%s: %s lunges toward the party" % [key, attacker.display_name])
	await _shot("anim_%s_02_enemy_lunge" % key)
	await _wait(0.06)
	check(bianca_view.flash_amount() > 0.05 or absf(bianca_view._art.position.x) > 1.0, "%s: Bianca flashes and recoils when hit" % key)
	await _shot("anim_%s_03_party_hit" % key)
	await _wait(0.5)
	if attacker_view.motion_profile_id() == "heavy":
		check(_impacts > impacts_before, "%s: a heavy creature's blow shakes the screen" % key)

	# Chiara casts (glow at her feet) and Bianca braces (blue outline).
	screen.combat.visual_event.emit({"kind": "apply_status", "source_id": "chiara", "target_ids": [], "card_id": "", "specialization_id": "fire", "target_group": ""})
	screen.combat.visual_event.emit({"kind": "block", "source_id": "bianca", "target_ids": ["bianca"], "card_id": "", "specialization_id": "", "target_group": ""})
	await _wait(0.12)
	check(field.party_views["chiara"]._glow.modulate.a > 0.1, "%s: a spell lights a glow under Chiara" % key)
	check(float(bianca_view._outline_mat.get_shader_parameter("outline_width")) > 0.0, "%s: Bianca's block shows a shield outline" % key)
	await _shot("anim_%s_04_cast_block" % key)
	await _wait(0.6)

	# Chiara attacks an enemy: the enemy is knocked back.
	var victim: Combatant = screen.combat.enemies[0]
	var victim_view: CombatUnitView = field.enemy_views[victim.id]
	screen.combat.visual_event.emit({"kind": "damage", "source_id": "chiara", "target_ids": [victim.id], "card_id": "", "specialization_id": "fire", "target_group": ""})
	await _wait(0.34)
	check(victim_view._art.position.x < -1.0, "%s: %s is knocked back by the hit" % [key, victim.display_name])
	await _shot("anim_%s_05_enemy_hit" % key)
	await _wait(0.6)

	# Targeting: a single-enemy card outlines the valid targets.
	var single: Array = screen.combat.deck.hand.filter(func(c: CardInstance) -> bool: return c.definition.target == CardDef.TARGET_SINGLE_ENEMY and screen.combat.can_play(c) == "")
	if not single.is_empty() and screen.combat.needs_target_choice(single[0]):  # one enemy = auto-target
		screen._touch_mode = false
		screen._on_card_pressed(single[0])
		await _wait(0.15)
		check(victim_view.has_target_outline(), "%s: valid targets get a glowing outline" % key)
		await _shot("anim_%s_06_targeting" % key)
		screen._cancel_selection()
		await _wait(0.1)
		check(not victim_view.has_target_outline(), "%s: the outline goes away when the card is cancelled" % key)

	# Death: the sprite burns away, then vanishes.
	victim.take_damage(9999)
	screen.combat._cleanup_fallen()
	screen.combat.changed.emit()
	await _wait(0.55)
	check(float(victim_view._material.get_shader_parameter("dissolve")) > 0.05, "%s: a defeated enemy dissolves" % key)
	await _shot("anim_%s_07_dissolve" % key)
	await _wait(0.8)
	check(victim_view.is_vanished(), "%s: and then it is gone" % key)


func _count_impact(_strength: float) -> void:
	_impacts += 1
