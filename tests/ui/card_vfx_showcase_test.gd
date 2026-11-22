extends Node
## Windowed showcase: plays every Ashveil card and the draw / energy / heal cards of the other
## specializations in a real fight, records which effects spawn, and captures each mid-effect.
## Every card must spawn at least one effect, and the effects must be the expected ones.
##   godot --path . res://tests/ui/card_vfx_showcase_test.tscn -- <screenshot_dir>

## [chiara spec, bianca spec, card id, effects that must appear]
const CASES := [
	["fire", "ashveil", "bianca_ash_slash", ["ash_slash"]],
	["fire", "ashveil", "bianca_ash_flask", ["oil_flask", "oil_splash"]],
	["fire", "ashveil", "bianca_ash_veil", ["smoke_veil"]],
	["fire", "ashveil", "bianca_ash_dagger", ["shadow_thrust", "oil_splash"]],
	["fire", "ashveil", "bianca_ash_caltrops", ["caltrops"]],
	["fire", "ashveil", "bianca_ash_shadow", ["shadow_thrust"]],
	["fire", "ashveil", "bianca_ash_smokebomb", ["smoke_burst", "card_draw_ashveil"]],
	["fire", "ashveil", "bianca_ash_snare", ["oil_splash", "smoke_veil"]],
	["fire", "ashveil", "bianca_ash_powder", ["powder_blast"]],
	["fire", "ashveil", "bianca_ash_shadowstep", ["smoke_veil", "card_draw_ashveil"]],
	["fire", "ashveil", "bianca_ash_ignite", ["oil_ignite"]],
	["fire", "ashveil", "bianca_ash_greasefire", ["oil_splash", "burn_apply"]],
	["fire", "ashveil", "bianca_ash_epic_ashfall", ["oil_splash", "powder_blast"]],
	["fire", "ashveil", "bianca_ash_epic_veil", ["smoke_burst", "oil_splash", "card_draw_ashveil"]],
	["fire", "ashveil", "chiara_fire_epic_heart", ["energy_fire", "card_draw_fire"]],
	["fire", "ashveil", "chiara_fire_smokescreen", ["smoke_screen", "card_draw_fire"]],
	["frost", "tanking", "chiara_frost_snap", ["chill_apply", "card_draw_frost"]],
	["frost", "tanking", "bianca_tanking_wind", ["second_wind", "card_draw_tanking"]],
	["arcana", "holy", "chiara_arcana_epic_timefold", ["energy_arcana", "mana_surge"]],
	["arcana", "holy", "bianca_holy_touch", ["holy_heal"]],
	["arcana", "holy", "chiara_arcana_pulse", ["arcane_heal"]],
]

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_card_vfx.json"
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


func _start(chiara: String, bianca: String) -> Node:
	GameState.reset_selection()
	GameState.select_specialization("chiara", chiara)
	GameState.select_specialization("bianca", bianca)
	GameState.create_party_from_selection()
	GameState.next_map_id = "enchanted_forest"
	GameState.begin_adventure()
	GameState.room_state = {}
	GameState.map_progress.current_node_id = "bone_clearing"
	GameState.get_current_node().encounter_id = "forest_bone_clearing"
	SceneRouter.go(SceneRouter.Screen.COMBAT)
	await _wait(1.6)
	return SceneRouter.current_screen


func _run() -> void:
	SettingsStore.save_values(SettingsStore.load_values().merged({"effects_quality": "full"}, true))
	var pair := ""
	var screen: Node = null
	for entry: Array in CASES:
		var key := "%s+%s" % [entry[0], entry[1]]
		if key != pair:
			screen = await _start(entry[0], entry[1])
			pair = key
			_check_layering(screen)
		await _play(screen, entry[2], entry[3])


## Effects must draw above every unit sprite and its chips: an effect smaller than the sprite it
## lands on (Smoke Veil on Bianca, Ashen Slash on a foe) would otherwise be hidden behind it.
func _check_layering(screen: Node) -> void:
	var highest := 0
	for view: Control in screen._battlefield.all_views():
		# The unit artwork only: intent badges, status chips and the hover panel are interface
		# and are meant to stay readable above effects.
		var art: CanvasItem = view.get("_art")
		if art != null:
			highest = maxi(highest, _absolute_z(art, screen))
	check(screen._vfx.z_index > highest, "effects draw above unit sprites (effects z %d, highest unit z %d)" % [screen._vfx.z_index, highest])


func _absolute_z(item: CanvasItem, root: Node) -> int:
	var z := 0
	var node: Node = item
	while node != null and node != root:
		if node is CanvasItem:
			z += (node as CanvasItem).z_index
			if not (node as CanvasItem).z_as_relative:
				break
		node = node.get_parent()
	return z


func _play(screen: Node, card_id: String, expected: Array) -> void:
	var cm: CombatManager = screen.combat
	if cm.state != CombatManager.State.PLAYER_TURN:
		return
	var def := DataRegistry.get_card(card_id)
	var card := CardInstance.new()
	card.definition = def
	card.owner_character_id = def.owner_character_id
	card.owned_uid = "showcase_" + card_id
	cm.deck.hand.append(card)
	cm.energy = 9
	for c in cm.party_combatants:
		c.hp = maxi(1, c.max_hp - 25)  # room for heals to show
	screen._refresh()
	await _wait(0.45)
	var spawned: Array[String] = []
	var vfx: CombatVfxManager = screen._vfx
	var record := func(effect_id: String, _node: CombatVfx) -> void: spawned.append(effect_id)
	vfx.effect_spawned.connect(record)
	var target := ""
	if def.target == CardDef.TARGET_SINGLE_ENEMY:
		target = cm.get_living_enemies()[0].id
	elif def.target == CardDef.TARGET_SINGLE_ALLY:
		target = "chiara"
	if target != "":
		screen._selected_card = card
		screen._play_selected(target)
	else:
		screen._on_card_pressed(card)
	await _wait(0.32)
	await _shot("vfx_%s" % card_id)
	await _wait(0.3)
	await _shot("vfx_%s_late" % card_id)
	await _wait(0.6)
	vfx.effect_spawned.disconnect(record)
	var missing := expected.filter(func(e: String) -> bool: return not spawned.has(e))
	check(not spawned.is_empty() and missing.is_empty(), "%s shows %s (spawned: %s)" % [card_id, ", ".join(expected), ", ".join(spawned)])
