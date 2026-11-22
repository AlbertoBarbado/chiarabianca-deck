extends Node
## Milestone 6 tests: battlefield layout, hand, targeting, states, cut-ins, quality settings and
## responsive layout of the redesigned combat screen. Runs as a scene (the screen uses autoloads):
##   godot --path . res://tests/combat/combat_presentation_test.tscn [-- <screenshot_dir>]
## Screenshots (optional) are written for the eight required situations.

const WINDOWS: Array[Vector2] = [Vector2(1280, 720), Vector2(844, 390), Vector2(1024, 768), Vector2(2560, 1080), Vector2(2000, 678)]
const ENCOUNTERS := {"single": "castle_training_01", "pair": "castle_training_02", "captain": "castle_final_regular_01", "six": "qa_six_guards", "four": "qa_four_guards"}

var _failures: int = 0
var _checks: int = 0
var _shot_dir := ""
var _original_settings: Dictionary = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	_run()


func check(condition: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), label)
	if not condition:
		_failures += 1


func _virtual_size(window: Vector2) -> Vector2:
	return window / minf(window.x / 1280.0, window.y / 720.0)


func _run() -> void:
	DataRegistry.reload()
	AssetCatalog.reload()
	CombatPresentation.reload()
	_original_settings = SettingsStore.load_values()
	GameState.save_path = "user://test_combat_presentation_save.json"
	GameState.delete_save()
	_test_data()
	await _test_layouts()
	await _test_hand()
	await _test_interaction()
	await _test_top_bar()
	await _test_end_turn_always()
	await _test_qa()
	await _test_battlefield_polish()
	await _test_crowded()
	await _test_states_and_cutins()
	await _test_screenshots()
	SettingsStore.save_values(_original_settings)
	GameState.delete_save()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _party(chiara: String, bianca: String) -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", chiara)
	GameState.select_specialization("bianca", bianca)
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	for member in GameState.party.members:  # reward-pool cards in the deck so every card can appear
		for card_id in member.specialization.card_pool:
			member.add_card(card_id)


## Hosts a combat screen in a SubViewport with the stretched virtual size of a window.
func _host_combat(encounter_key: String, virtual_size: Vector2) -> Dictionary:
	DataRegistry.ensure_loaded()
	DataRegistry.encounters["qa_six_guards"] = {"id": "qa_six_guards", "name": "QA Six", "enemies": ["hall_guard", "hall_captain", "hall_guard", "guard_recruit", "guard_recruit", "hall_guard"], "gold_reward": 0}
	DataRegistry.encounters["qa_four_guards"] = {"id": "qa_four_guards", "name": "QA Four", "enemies": ["hall_guard", "hall_captain", "hall_guard", "guard_recruit"], "gold_reward": 0}
	GameState.get_current_node().encounter_id = ENCOUNTERS[encounter_key]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(virtual_size)
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var screen := (load("res://scenes/combat/combat_screen.tscn") as PackedScene).instantiate() as Control
	screen.theme = UITheme.get_theme()
	viewport.add_child(screen)
	add_child(viewport)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return {"viewport": viewport, "screen": screen}


func _free(host: Dictionary) -> void:
	(host["viewport"] as Node).queue_free()


func _snap(host: Dictionary, name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	((host["viewport"] as SubViewport).get_texture().get_image()).save_png("%s/%s.png" % [_shot_dir, name])


func _hand_card(screen: Node, card_id: String) -> CardInstance:
	var combat: CombatManager = screen.combat
	for pile: Array[CardInstance] in [combat.deck.hand, combat.deck.draw_pile, combat.deck.discard_pile]:
		for card in pile:
			if card.definition.id == card_id:
				for other: Array[CardInstance] in [combat.deck.draw_pile, combat.deck.discard_pile]:
					other.erase(card)
				if not combat.deck.hand.has(card):
					combat.deck.hand.append(card)
				return card
	return null


func _labels(node: Node, found: Array[String] = []) -> Array[String]:
	if node is Label and (node as Label).is_visible_in_tree():
		found.append((node as Label).text)
	for child in node.get_children():
		_labels(child, found)
	return found


# --- tests -------------------------------------------------------------------

func _test_data() -> void:
	print("Presentation data")
	var chars_ok := true
	for character_id in ["chiara", "bianca"]:
		for state in ["idle", "attack", "cast", "block", "hit", "down"]:
			chars_ok = chars_ok and CombatPresentation.character_state(character_id, state) != null
	check(chars_ok, "Chiara and Bianca have all six pose states (with idle fallback)")
	check(CombatPresentation.enemy_set("hall_captain") == "knight_captain" and CombatPresentation.enemy_set("hall_guard") == "knight_generic" and CombatPresentation.enemy_set("guard_recruit") == "knight_generic", "captains use captain art, other enemies the normal knight set")
	check(CombatPresentation.enemy_state("hall_captain", "idle") != CombatPresentation.enemy_state("hall_guard", "idle"), "captain and knight art are different images")
	check(CombatPresentation.enemy_state("hall_guard", "hit") != null and CombatPresentation.enemy_state("hall_guard", "attack") != null and CombatPresentation.enemy_state("hall_guard", "block") != null, "knights have hit, attack and block poses")
	check(CombatPresentation.enemy_state("unknown_enemy", "unknown_state") != null, "unknown enemies fall back to the default knight set")
	var cards_ok := true
	for card_id in DataRegistry.cards:
		pass
	var tiers: Dictionary = JSON.parse_string(FileAccess.open(CombatPresentation.PATH, FileAccess.READ).get_as_text())["card_tiers"]
	for card_id: String in tiers:
		cards_ok = cards_ok and DataRegistry.get_card(card_id) != null
	check(cards_ok, "every card with a presentation tier exists (%d)" % tiers.size())
	var cutins_ok := true
	for card_id: String in tiers:
		var card := DataRegistry.get_card(card_id)
		var cutin := CombatPresentation.cutin_for_card(card_id, card.specialization_id)
		cutins_ok = cutins_ok and ((int(tiers[card_id]) < 2 and cutin.is_empty()) or (int(tiers[card_id]) >= 2 and not cutin.is_empty()))
	check(cutins_ok, "tier 1 cards have no cut-in; tier 2-4 cards in the four specializations have one")
	check(CombatPresentation.card_tier("chiara_fire_inferno") == 4 and CombatPresentation.card_tier("chiara_fire_kindle") == 0 and DataRegistry.get_card("chiara_fire_inferno").cost == 3, "tiers come from explicit data, not from card cost or rarity")
	check(CombatPresentation.character_state("nobody", "idle") == null, "an unknown character yields no art (the view draws a token)")


func _test_layouts() -> void:
	print("Battlefield layout at supported sizes")
	_party("fire", "holy")
	for window in WINDOWS:
		var size_value := _virtual_size(window)
		for key in ["single", "pair", "captain"]:
			var host := await _host_combat(key, size_value)
			var screen: Control = host["screen"]
			var battlefield: CombatBattlefield = screen._battlefield
			var tag := "%s at %dx%d" % [key, window.x, window.y]
			var field := battlefield.get_global_rect()
			var middle := field.position.x + field.size.x / 2.0
			var enemies_left := true
			var party_right := true
			var inside := true
			var overlap := false
			var views := battlefield.all_views()
			for view in views:
				var rect := view.get_global_rect()
				inside = inside and Rect2(field.position - Vector2(2, 2), field.size + Vector2(4, 62)).encloses(rect)  # feet may stand in the empty strip above the hand
				if view.is_enemy:
					enemies_left = enemies_left and rect.get_center().x < middle
				else:
					party_right = party_right and rect.get_center().x > middle
				for other in views:
					if other != view and rect.intersection(other.get_global_rect()).get_area() > 1.0:
						overlap = true
			check(enemies_left and party_right, "%s: enemies stand on the left, Chiara and Bianca on the right" % tag)
			check(inside and not overlap, "%s: every unit is inside the battlefield and units do not overlap" % tag)
			var party_ok := true
			for view in views:
				if not view.is_enemy:
					party_ok = party_ok and view.get_art_rect().end.y <= view.get_global_rect().position.y + view.get_art_rect().size.y + 1.0
			check(party_ok, "%s: pose art sits above the info card (art never covers HP)" % tag)
			var centre_free := true
			for view in views:
				centre_free = centre_free and (view.get_global_rect().end.x <= middle + field.size.x * 0.05 if view.is_enemy else view.get_global_rect().position.x >= middle - field.size.x * 0.05)
			check(centre_free, "%s: the central strip stays free for effects" % tag)
			var view_rect := Rect2(Vector2.ZERO, size_value)
			var end_turn := _find_button(screen, "End Turn")
			check(end_turn != null and view_rect.encloses(end_turn.get_global_rect()) and end_turn.get_global_rect().size.y >= 56.0, "%s: End Turn is on screen and large" % tag)
			var living: int = (screen.combat as CombatManager).get_living_enemies().size()
			var badges := screen.find_children("IntentBadge", "HBoxContainer", true, false).filter(func(n: Node) -> bool: return n.get_child_count() == 2)
			check(badges.size() == living, "%s: every living enemy shows an intent badge above its head (%d)" % [tag, living])
			var first_enemy: CombatEnemyView = screen._battlefield.enemy_views.values()[0]
			check(not first_enemy.is_detail_visible(), "%s: enemy details are hidden by default (only the life bar shows)" % tag)
			first_enemy._set_hover(true)
			var texts := _labels(screen)
			check(first_enemy.is_detail_visible() and texts.any(func(t: String) -> bool: return t.begins_with("Intent:") and (t.contains("dmg") or t.contains("block"))), "%s: hovering an enemy shows its intent text with the value" % tag)
			first_enemy._set_hover(false)
			var hand_ok := true
			var bad_card := ""
			for card_view in screen._hand.get_children():
				if not view_rect.grow(2.0).encloses(card_view.get_global_rect()):
					hand_ok = false
					bad_card = str(card_view.get_global_rect())
			check(hand_ok, "%s: all hand cards are on screen %s" % [tag, bad_card])
			_free(host)
	_party("arcana", "tanking")
	var host := await _host_combat("captain", Vector2(1280, 720))
	check(host["screen"]._battlefield.party_views.size() == 2 and host["screen"]._battlefield.enemy_views.size() == 3, "Arcana + Tanking parties get the same layout (three enemies incl. the captain)")
	_free(host)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _test_hand() -> void:
	print("Hand layout and hover")
	_party("fire", "holy")
	var host := await _host_combat("single", Vector2(1280, 720))
	var screen: Control = host["screen"]
	var hand: CombatHand = screen._hand
	var combat: CombatManager = screen.combat
	var pool: Array[CardInstance] = []
	for pile: Array[CardInstance] in [combat.deck.hand, combat.deck.draw_pile, combat.deck.discard_pile]:
		pool.append_array(pile)
	for count in [1, 3, 5, 8, 10]:
		var cards: Array[CardInstance] = []
		cards.assign(pool.slice(0, count))
		hand.set_cards(cards, func(_c: CardInstance) -> bool: return true, null)
		await get_tree().create_timer(1.2).timeout  # newly drawn cards fly in from the deck first
		var rects: Array[Rect2] = []
		for card in cards:
			rects.append(Rect2(hand.get_view(card).position, CardView.CARD_SIZE * hand.base_scale()))
		var inside := true
		var overlapping := false
		for i in rects.size():
			inside = inside and rects[i].position.x >= -1.0 and rects[i].end.x <= hand.size.x + 1.0
			if i > 0 and rects[i - 1].end.x > rects[i].position.x + 0.5:
				overlapping = true
		check(inside and hand.card_count() == count, "%d cards: every card is placed inside the hand (none dropped)" % count)
		check(overlapping == (count > 5 and rects.size() * rects[0].size.x + 10.0 * (count - 1) > hand.size.x), "%d cards: cards overlap only when the hand is wide (%s)" % [count, "overlap" if overlapping else "spaced"])
	var cards: Array[CardInstance] = []
	cards.assign(pool.slice(0, 7))
	hand.set_cards(cards, func(_c: CardInstance) -> bool: return true, null)
	await get_tree().process_frame
	var before := hand.target_transform(3)
	hand.set_hovered(cards[3])
	var after := hand.target_transform(3)
	check((after["bottom_center"] as Vector2).y < (before["bottom_center"] as Vector2).y and float(after["scale"]) > float(before["scale"]) and int(after["z"]) > int(before["z"]), "hovering raises, enlarges and brings a card to the front")
	hand.set_hovered(null)
	check((hand.target_transform(3)["bottom_center"] as Vector2).y == (before["bottom_center"] as Vector2).y, "leaving the card restores it")
	hand.set_hovered(cards[0])
	check(hand.target_transform(0)["bottom_center"].x - CardView.CARD_SIZE.x * hand.base_scale() * 1.22 / 2.0 >= -1.0, "an enlarged card at the end of the hand stays on screen")
	_free(host)


func _test_crowded() -> void:
	print("Crowded battlefields: up to 6 enemies and 3 characters, End Turn always reachable")
	for window in WINDOWS:
		var virtual_size := _virtual_size(window)
		for key in ["four", "six"]:
			_party("fire", "holy")
			var host := await _host_combat(key, virtual_size)
			var screen: Control = host["screen"]
			var combat: CombatManager = screen.combat
			var field: CombatBattlefield = screen._battlefield
			var tag := "%s enemies at %dx%d" % [combat.enemies.size(), window.x, window.y]
			check(combat.enemies.size() == (6 if key == "six" else 4), "%s: the crowded encounter has the expected enemies" % tag)
			var view_rect := Rect2(Vector2.ZERO, virtual_size)
			var inside := true
			var rects: Array[Rect2] = []
			for view in field.all_views():
				var art := view.get_art_rect()
				inside = inside and view_rect.grow(1.0).encloses(art)
				rects.append(art)
			check(inside, "%s: every sprite is fully on screen" % tag)
			var overlap := false
			for i in field.enemy_views.size():
				for j in range(i + 1, field.enemy_views.size()):
					var a: Rect2 = field.enemy_views.values()[i].get_art_rect()
					var b: Rect2 = field.enemy_views.values()[j].get_art_rect()
					var inter := a.intersection(b)
					# Back-row sprites may be partly hidden by the front row, never more than 55% of one sprite.
					if inter.get_area() > minf(a.get_area(), b.get_area()) * 0.55:
						overlap = true
			check(not overlap, "%s: enemy sprites do not pile on top of each other" % tag)
			var end_turn := _find_button(screen, "End Turn")
			check(end_turn != null and not end_turn.disabled and view_rect.encloses(end_turn.get_global_rect()), "%s: End Turn is on screen and enabled" % tag)
			var blocked := false
			var end_rect := end_turn.get_global_rect()
			for card_view in screen._hand.get_children():
				if (card_view as Control).get_global_rect().intersects(end_rect.grow(-2.0)):
					blocked = true
			for view in field.all_views():
				if view.get_global_rect().intersects(end_rect.grow(-2.0)):
					blocked = true
			check(not blocked, "%s: nothing covers the End Turn button" % tag)
			var min_size := screen.get_combined_minimum_size()
			check(min_size.x <= virtual_size.x + 1.0 and min_size.y <= virtual_size.y + 1.0, "%s: the screen's minimum size (%dx%d) fits the window" % [tag, min_size.x, min_size.y])
			if key == "six" and window == WINDOWS[0]:
				await _snap(host, "combat_qa_six_enemies")
			_free(host)
	# Three characters: a third combatant stands in the same row.
	_party("fire", "holy")
	var host3 := await _host_combat("pair", Vector2(1280, 720))
	var combat3: CombatManager = host3["screen"].combat
	var extra := Combatant.new()
	extra.id = "third_member"
	extra.display_name = "Third"
	extra.side = Combatant.SIDE_PARTY
	extra.max_hp = 40
	extra.hp = 40
	combat3.party_combatants.append(extra)
	var field3: CombatBattlefield = host3["screen"]._battlefield
	field3.setup(combat3)
	field3.layout()
	var party_rects: Array[Rect2] = []
	for id in field3.party_views:
		party_rects.append((field3.party_views[id] as CombatUnitView).get_art_rect())
	check(party_rects.size() == 3 and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(party_rects[0]) and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(party_rects[2]), "three characters fit in one row")
	var disjoint := true
	for i in 3:
		for j in range(i + 1, 3):
			disjoint = disjoint and not party_rects[i].intersects(party_rects[j].grow(-3.0))
	check(disjoint, "three characters do not overlap")
	_free(host3)


func _test_battlefield_polish() -> void:
	print("Battlefield polish: grounded sprites, gaps, badges, party Block")
	for key in ["pair", "six"]:
		_party("fire", "holy")
		var host := await _host_combat(key, Vector2(1280, 720))
		var screen: Control = host["screen"]
		var field: CombatBattlefield = screen._battlefield
		var grounded := true
		for view in field.all_views():
			var slot_bottom := view.get_global_rect().position.y + view.get_global_rect().size.y - view.get_info_height() - (4.0 if view.get_info_height() > 0.0 else 0.0)
			grounded = grounded and absf(view.get_art_rect().end.y - slot_bottom) < 1.5
		check(grounded, "%s: every sprite stands on the floor of its slot (none floating)" % key)
		var enemy_right := 0.0
		for view in field.enemy_views.values():
			enemy_right = maxf(enemy_right, (view as CombatUnitView).get_art_rect().end.x)
		var party_left := 99999.0
		for view in field.party_views.values():
			party_left = minf(party_left, (view as CombatUnitView).get_art_rect().position.x)
		check(party_left - enemy_right > 60.0, "%s: enemies keep a clear distance from the party (%d px)" % [key, int(party_left - enemy_right)])
		var badges_on_top := true
		for view in field.enemy_views.values():
			var badge: Control = (view as Node).find_child("IntentBadge", true, false)
			badges_on_top = badges_on_top and badge.z_index >= 9 and badge.get_global_rect().end.y <= (view as CombatUnitView).get_art_rect().position.y + 4.0
		check(badges_on_top, "%s: intent badges sit above the heads and are drawn over every sprite" % key)
		var same_row_gap := true
		var rects: Array[Rect2] = []
		for view in field.enemy_views.values():
			rects.append((view as CombatUnitView).get_global_rect())
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				if absf(rects[i].position.y - rects[j].position.y) < 2.0 and rects[i].intersects(rects[j]):
					same_row_gap = false
		check(same_row_gap, "%s: units in the same row never touch" % key)
		_free(host)
	_party("fire", "holy")
	var host2 := await _host_combat("pair", Vector2(1280, 720))
	var screen2: Control = host2["screen"]
	var bianca: Combatant = screen2.combat.get_combatant("bianca")
	bianca.add_block(9)
	screen2._refresh()
	var bianca_view: CombatUnitView = screen2._battlefield.party_views["bianca"]
	check(bianca_view.status_count("block") == 9, "the party shows its remaining Block over the sprite")
	bianca.block = 0
	screen2._refresh()
	check(bianca_view.status_count("block") == 0, "the Block chip disappears when Block is gone")
	_free(host2)


func _test_qa() -> void:
	print("QA: sprites, spacing, defeated enemies, hover menus")
	# Chiara's legs: the lowest rows of her idle pose are opaque (boots / leggings), in every pose.
	for pose_name in ["idle", "attack", "cast", "block", "hit"]:
		var texture := CombatPresentation.character_state("chiara", pose_name)
		var image := texture.get_image() if texture != null else null
		var bottom_pixels := 0
		if image != null:
			for y in range(int(image.get_height() * 0.9), image.get_height()):
				for x in image.get_width():
					if image.get_pixel(x, y).a > 0.5:
						bottom_pixels += 1
		check(bottom_pixels > 40, "Chiara's %s pose keeps her legs (%d opaque pixels in the lowest 10%%)" % [pose_name, bottom_pixels])
	_party("fire", "holy")
	var host := await _host_combat("pair", Vector2(1280, 720))
	var screen: Control = host["screen"]
	var combat: CombatManager = screen.combat
	var field: CombatBattlefield = screen._battlefield
	var views := field.all_views()
	var baselines: Array[float] = []
	for view in views:
		baselines.append(snappedf(view.get_art_rect().end.y, 1.0))
	check(baselines.all(func(v: float) -> bool: return v == baselines[0]), "all units stand on the same ground line")
	var chiara_rect: Rect2 = field.party_views["chiara"].get_art_rect()
	var bianca_rect: Rect2 = field.party_views["bianca"].get_art_rect()
	check(bianca_rect.position.x - chiara_rect.end.x < 40.0, "the party stands close together")
	var enemy_rect: Rect2 = field.enemy_views.values()[-1].get_art_rect()
	check(chiara_rect.position.x - enemy_rect.end.x < 420.0, "the two sides face each other without a huge gap")
	check(chiara_rect.size.y <= 275.0, "sprites stay at Slay-the-Spire scale")
	# Defeated enemies disappear completely.
	var victim: Combatant = combat.enemies[0]
	var survivor: Combatant = combat.enemies[1]
	var victim_view: CombatEnemyView = field.enemy_views[victim.id]
	victim.take_damage(999)
	combat._cleanup_fallen()
	combat.changed.emit()
	await get_tree().create_timer(1.2).timeout
	check(victim_view.is_vanished() and not victim_view.is_detail_visible(), "a defeated enemy vanishes completely (no sprite, no life bar, no popup)")
	check(victim_view.find_child("IntentBadge", true, false).get_child_count() == 0, "a defeated enemy shows no intent")
	check(not field.enemy_views[survivor.id].is_vanished(), "the other enemy is untouched")
	var ember := _hand_card(screen, "chiara_fire_ember")
	screen._refresh()
	screen._on_card_pressed(ember)
	check(not victim_view.is_targetable() and screen._selected_card == null or screen._selected_card == ember, "a card can be played after an enemy died")
	screen._cancel_selection()
	# Hover menu uses the ornate frame and shows the details.
	var live_view: CombatEnemyView = field.enemy_views[survivor.id]
	live_view._set_hover(true)
	await get_tree().process_frame
	var detail: PanelContainer = live_view.find_child("EnemyDetail", true, false)
	check(detail != null and detail.visible and detail.get_theme_stylebox("panel") is StyleBoxTexture, "the enemy hover menu uses the ornate panel art")
	check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(detail.get_global_rect()), "the hover menu stays on screen")
	await _snap(host, "combat_qa_hover_enemy")
	live_view._set_hover(false)
	check(not live_view.is_detail_visible(), "moving the pointer away hides the menu")
	# A tap pins the menu, a second tap hides it; while a card waits for a target the menu stays closed.
	live_view._on_detail_pressed(live_view.unit_id)
	check(live_view.is_detail_visible(), "tapping an enemy pins its details")
	live_view._on_detail_pressed(live_view.unit_id)
	check(not live_view.is_detail_visible(), "tapping again hides them")
	var tip: String = (screen.find_child("Chip_chiara", true, false) as Control).tooltip_text
	check(tip.contains("Kindled Spark") and tip.length() > 40, "the character hover text explains the passive")
	check(ThemeDB.get_default_theme() != null and UITheme.get_theme().get_stylebox("panel", "TooltipPanel") is StyleBoxTexture, "tooltips use the ornate frame")
	_free(host)


func _test_end_turn_always() -> void:
	print("End Turn is always available")
	_party("fire", "holy")
	var host := await _host_combat("pair", Vector2(1280, 720))
	var screen: Control = host["screen"]
	var combat: CombatManager = screen.combat
	var end_turn := _find_button(screen, "End Turn")
	check(not end_turn.disabled, "End Turn is enabled at the start of the turn, with energy and playable cards")
	combat.energy = 0
	screen._refresh()
	check(not end_turn.disabled and end_turn.modulate != Color.WHITE, "with no energy left End Turn stays enabled and glows")
	var turn_before := combat.turn
	end_turn.pressed.emit()
	await get_tree().process_frame
	check(combat.turn == turn_before + 1 and not end_turn.disabled, "pressing it ends the turn and it is available again")
	combat.energy = 3
	screen._refresh()
	var hand_before := combat.deck.hand.size()
	end_turn.pressed.emit()
	await get_tree().process_frame
	check(combat.turn == turn_before + 2, "it also works with energy and playable cards left (no condition)")
	_free(host)


func _test_top_bar() -> void:
	print("Top bar and pile viewer")
	_party("fire", "holy")
	var host := await _host_combat("pair", Vector2(1280, 720))
	var screen: Control = host["screen"]
	var combat: CombatManager = screen.combat
	var bar: Control = screen.find_child("TopBar", true, false)
	check(bar != null and bar.get_global_rect().size.y < 120.0, "a slim top bar exists")
	check(screen.find_child("Chip_chiara", true, false) != null and screen.find_child("Chip_bianca", true, false) != null, "both characters have their vitals in the top bar")
	var chiara_hp: Label = null
	for label in screen.find_child("Chip_chiara", true, false).find_children("*", "Label", true, false):
		if (label as Label).text.contains("/") and not (label as Label).text.contains("Fallen"):
			chiara_hp = label
	check(chiara_hp != null and chiara_hp.text == "%d/%d" % [combat.get_combatant("chiara").hp, combat.get_combatant("chiara").max_hp], "the chip shows Chiara's current HP")
	check(screen._energy_label.text == "%d/%d" % [combat.energy, combat.max_energy], "energy is shown in the bar")
	var draw_button := screen.find_child("DrawPileButton", true, false) as Button
	check(draw_button != null and draw_button.text == "Draw %d" % combat.deck.draw_pile.size(), "the draw pile button shows its count")
	check(screen.find_child("DiscardPileButton", true, false) != null and screen.find_child("ExhaustPileButton", true, false) != null, "discard and exhaust buttons exist")
	draw_button.pressed.emit()
	await get_tree().process_frame
	var viewer: Node = screen.find_child("PileViewer", true, false)
	check(viewer != null and viewer.find_children("*", "CardView", true, false).size() == combat.deck.draw_pile.size(), "clicking the draw pile lists all its cards")
	(screen.find_child("ClosePile", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	check(screen.find_child("PileViewer", true, false) == null, "the viewer closes")
	var backdrop := screen.find_children("*", "RoomBackdrop", true, false)
	var wash_alpha := 1.0
	for node in backdrop[0].get_children():
		if node is ColorRect:
			wash_alpha = minf(wash_alpha, (node as ColorRect).color.a)
	check(wash_alpha == 0.0, "no blue wash or dark veil is drawn over the battle background")
	# A fallen character's cards disappear from the hand display.
	combat.get_combatant("chiara").take_damage(999)
	combat._cleanup_fallen()  # runs after every action in a real fight
	combat.changed.emit()
	await get_tree().process_frame
	var only_bianca := combat.deck.hand.all(func(c: CardInstance) -> bool: return c.owner_character_id == "bianca")
	check(only_bianca or combat.deck.hand.is_empty(), "after Chiara falls her cards are no longer in the hand")
	_free(host)


func _test_interaction() -> void:
	print("Selection, targeting, touch and End Turn")
	_party("fire", "holy")
	var host := await _host_combat("pair", Vector2(1280, 720))
	var screen: Control = host["screen"]
	var combat: CombatManager = screen.combat
	var field: CombatBattlefield = screen._battlefield
	combat.energy = 9
	var ember := _hand_card(screen, "chiara_fire_ember")
	screen._refresh()
	screen._on_card_pressed(ember)
	check(screen._selected_card == ember, "a targeted card becomes selected")
	var targets_ok := true
	for enemy in combat.enemies:
		targets_ok = targets_ok and field.enemy_views[enemy.id].is_targetable()
	for member in combat.party_combatants:
		targets_ok = targets_ok and not field.party_views[member.id].is_targetable()
	check(targets_ok, "valid enemy targets are highlighted and the party is not")
	check(field.party_views["chiara"].modulate.r < 1.0 and field.party_views["chiara"].modulate.a == 1.0 and field.enemy_views[combat.enemies[0].id].modulate == Color.WHITE, "invalid targets are darkened (never see-through)")
	var hp_before := combat.enemies[0].hp
	screen._on_unit_pressed("chiara")
	check(screen._selected_card == ember and combat.enemies[0].hp == hp_before and combat.energy == 9, "choosing an invalid target is rejected and the selection stays")
	check(screen._cancel.visible, "Cancel is shown while a card is selected")
	screen._cancel.pressed.emit()
	check(screen._selected_card == null and not field.enemy_views[combat.enemies[0].id].is_targetable(), "Cancel clears the selection and the highlights")
	screen._on_card_pressed(ember)
	screen._on_unit_pressed(combat.enemies[0].id)
	check(combat.enemies[0].hp == hp_before - 6 and combat.energy == 8, "choosing a valid target plays the card with the unchanged rules (6 damage, 1 energy)")
	var heal := _hand_card(screen, "bianca_holy_touch")
	combat.get_combatant("chiara").hp = 30
	screen._refresh()
	screen._on_card_pressed(heal)
	var ally_ok: bool = field.party_views["chiara"].is_targetable() and field.party_views["bianca"].is_targetable() and not field.enemy_views[combat.enemies[0].id].is_targetable()
	check(ally_ok, "an ally-target card highlights the party instead of the enemies")
	screen._on_unit_pressed(combat.enemies[0].id)
	check(screen._selected_card == heal, "an enemy is rejected as the target of a heal")
	screen._on_unit_pressed("chiara")
	check(combat.get_combatant("chiara").hp == 30 + int(heal.get_effects()[0]["value"]), "healing the chosen ally works as before")
	# touch: first tap arms, second tap plays
	screen.set_touch_mode(true)
	var bolt := _hand_card(screen, "chiara_fire_kindle")
	screen._refresh()
	var energy_before := combat.energy
	screen._on_card_pressed(bolt)
	check(screen._armed_card == bolt and combat.energy == energy_before and combat.deck.hand.has(bolt), "touch: the first tap enlarges the card without playing it")
	screen._on_card_pressed(bolt)
	check(screen._selected_card == bolt, "touch: the second tap starts targeting")
	screen._on_unit_pressed(combat.enemies[1].id)
	check(combat.enemies[1].has_status("burn"), "touch: tapping a valid target plays the card")
	screen.set_touch_mode(false)
	var turn_before := combat.turn
	screen._on_end_turn()
	await get_tree().process_frame
	check(combat.turn == turn_before + 1 and not screen._end_turn.disabled, "End Turn passes the turn and the button is ready again")
	_free(host)


func _test_states_and_cutins() -> void:
	print("States, cut-ins, quality and cleanup")
	_party("fire", "holy")
	var host := await _host_combat("captain", Vector2(1280, 720))
	var screen: Control = host["screen"]
	var combat: CombatManager = screen.combat
	var field: CombatBattlefield = screen._battlefield
	var target_enemy := combat.enemies[1]  # the captain (32 HP) survives Inferno, so the hit pose can be observed
	var guard_view: CombatUnitView = field.enemy_views[target_enemy.id]
	var chiara_view: CombatUnitView = field.party_views["chiara"]
	check(guard_view.current_state() == "idle" and chiara_view.current_state() == "idle", "units start in their idle pose")
	combat.energy = 9
	var inferno := _hand_card(screen, "chiara_fire_inferno")
	screen._refresh()
	var target_id := target_enemy.id
	screen._on_card_pressed(inferno)
	screen._on_unit_pressed(target_id)
	check(["attack", "cast"].has(chiara_view.current_state()) and guard_view.current_state() == "idle", "the caster switches to an attack / cast pose immediately; the target reacts after a short delay")
	await get_tree().create_timer(0.5).timeout
	check(guard_view.current_state() == "hit", "the target shows its hit pose")
	var cutins: Array[Node] = screen._cutin_layer.get_children()
	check(cutins.size() == 1 and screen._animations.cutins_shown == 1, "a tier-4 card shows one cut-in (a two-effect card does not show two)")
	var cutin_rect := (cutins[0] as Control).get_global_rect()
	var field_rect := field.get_global_rect()
	var covers_units := false
	for view in field.all_views():
		if cutin_rect.intersection(view.get_global_rect()).get_area() > view.get_global_rect().get_area() * 0.35:
			covers_units = true
	check(not covers_units and cutin_rect.size.y <= field_rect.size.y * 0.8, "the cut-in stays in the centre and does not bury the units")
	await get_tree().create_timer(2.0).timeout
	check(screen._cutin_layer.get_child_count() == 0, "the cut-in frees itself after its animation")
	check(guard_view.current_state() == "idle" and chiara_view.current_state() == "idle", "poses return to idle afterwards")
	check(screen._vfx.active_count() == 0, "VFX nodes are cleaned up as well")
	var art: Rect2 = screen._locate_panel(target_id)
	check(art.has_area() and art.get_center().x < field_rect.get_center().x and Rect2(field_rect.position, field_rect.size + Vector2(0, 60)).encloses(art), "VFX target the enemy's pose art, on the left of the battlefield")
	var chiara_art: Rect2 = screen._locate_panel("chiara")
	check(chiara_art.get_center().x > field_rect.get_center().x, "VFX target Chiara's pose art on the right")
	# fallen character
	combat.get_combatant("chiara").hp = 0
	screen._refresh()
	check(chiara_view.current_state() == "down" and chiara_view.get_global_rect().has_area(), "a fallen character switches to her down pose and stays on the battlefield")
	check(_labels(screen).any(func(t: String) -> bool: return t.contains("Fallen")), "fallen status is spelled out")
	combat.get_combatant("chiara").hp = 40
	screen._refresh()
	check(chiara_view.current_state() == "idle", "a revived character returns to idle")
	# enemy attack pose and phase
	var strikes_before: int = screen._animations.poses_played
	combat.visual_event.emit({"kind": "enemy_attack", "card_id": "", "specialization_id": "", "source_id": target_enemy.id, "target_ids": ["bianca"], "target_group": "single_ally"})
	check(guard_view.current_state() == "attack" and screen._animations.poses_played == strikes_before + 2, "an enemy attack event makes the enemy strike and queues the target's reaction")
	check(screen._animations.is_enemy_phase(), "the header can show the Enemy Turn while enemy actions play")
	await get_tree().create_timer(1.6).timeout
	check(guard_view.current_state() == "idle" and field.party_views["bianca"].current_state() == "idle", "enemy and target poses clean up")
	# quality
	var controller: CombatAnimationController = screen._animations
	var holy_event := {"kind": "damage", "card_id": "bianca_holy_judgment", "specialization_id": "holy", "source_id": "bianca", "target_ids": [target_enemy.id], "target_group": "single_enemy"}
	controller.quality_name = "off"
	var poses := controller.poses_played
	controller.handle_event(holy_event)
	check(controller.poses_played == poses and screen._cutin_layer.get_child_count() == 0, "quality Off: no poses and no cut-ins")
	controller.quality_name = "reduced"
	controller.handle_event(holy_event)
	check(controller.poses_played > poses and screen._cutin_layer.get_child_count() == 0, "quality Reduced: poses but no cut-ins")
	controller.quality_name = "full"
	await get_tree().create_timer(1.0).timeout
	controller.handle_event(holy_event)
	check(screen._cutin_layer.get_child_count() == 1, "quality Full: the cut-in appears")
	await get_tree().create_timer(2.4).timeout
	check(screen._cutin_layer.get_child_count() == 0, "cut-in cleaned up")
	# combat result is independent of animations
	controller.quality_name = "off"
	var start_hp := combat.enemies[2].hp
	combat.energy = 9
	var ember := _hand_card(screen, "chiara_fire_ember")
	screen._refresh()
	screen._on_card_pressed(ember)
	screen._on_unit_pressed(combat.enemies[2].id)
	check(combat.enemies[2].hp == start_hp - 6, "with animations off, combat still resolves exactly the same (6 damage)")
	_free(host)


func _test_screenshots() -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	print("Screenshots")
	_party("fire", "holy")
	for entry in [["1_one_knight", "single"], ["2_several_knights", "pair"], ["3_knight_captain", "captain"]]:
		var host := await _host_combat(entry[1], Vector2(1280, 720))
		await _snap(host, "combat_" + entry[0])
		_free(host)
	var host := await _host_combat("captain", Vector2(1280, 720))
	var screen: Control = host["screen"]
	var combat: CombatManager = screen.combat
	await _snap(host, "combat_4_fire_holy_party")
	combat.energy = 9
	var fireball := _hand_card(screen, "chiara_fire_fireball")
	screen._refresh()
	screen._on_card_pressed(fireball)
	await _snap(host, "combat_5_selected_card_targets")
	screen._on_unit_pressed(combat.enemies[1].id)
	await get_tree().create_timer(0.3).timeout
	await _snap(host, "combat_6_attack")
	await get_tree().create_timer(1.2).timeout
	screen._on_end_turn()
	await get_tree().create_timer(0.35).timeout
	await _snap(host, "combat_7_enemy_turn")
	await get_tree().create_timer(1.5).timeout
	var cards: Array[CardInstance] = []
	for pile: Array[CardInstance] in [combat.deck.draw_pile, combat.deck.discard_pile]:
		for card in pile:
			if cards.size() < 5:
				cards.append(card)
	for card in cards:
		combat.deck.draw_pile.erase(card)
		combat.deck.discard_pile.erase(card)
		combat.deck.hand.append(card)
	screen._refresh()
	await get_tree().create_timer(0.3).timeout
	await _snap(host, "combat_8_large_hand")
	_free(host)
	var phone := await _host_combat("captain", _virtual_size(Vector2(844, 390)))
	await _snap(phone, "combat_9_phone_844x390")
	_free(phone)
