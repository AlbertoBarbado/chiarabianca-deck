extends Node
## Windowed: the Deck button on the map opens the party deck viewer (whole party and per-princess
## tabs, grouped copies, tap to inspect, close by button / background / Escape). Also captures the
## specialization selection screen to check the portrait crops.
##   godot --path . res://tests/ui/deck_viewer_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_deck_viewer.json"
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


func _find(node_name: String) -> Node:
	return SceneRouter.current_screen.find_child(node_name, true, false)


func _viewer() -> DeckViewer:
	return SceneRouter.current_screen.get_node_or_null("DeckViewer") as DeckViewer


func _run() -> void:
	GameState.reset_selection()
	SceneRouter.go(SceneRouter.Screen.SPECIALIZATION_SELECTION)
	await _wait(0.6)
	await _shot("deck_00_selection")

	GameState.select_specialization("chiara", "arcana")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	var chiara := GameState.party.get_member("chiara")
	chiara.add_card("chiara_arcana_echo")
	chiara.deck[0].upgrade_level = 1  # one upgraded Arcane Bolt
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.8)
	var button := _find("DeckButton") as Button
	var total := GameState.party.get_total_deck_size()
	check(button != null and button.is_visible_in_tree() and button.text == "Deck (%d)" % total, "the map has a Deck button with the card count (%d)" % total)
	check(button != null and button.size.y >= 44, "the button is touch-sized")
	button.pressed.emit()
	await _wait(0.4)
	var viewer := _viewer()
	check(viewer != null and viewer.is_visible_in_tree(), "it opens the deck viewer over the map")
	var count := viewer.find_child("DeckCount", true, false) as Label
	check(count != null and count.text == "%d cards" % total, "the whole party's %d cards are listed" % total)
	check(viewer.find_child("DeckCard_chiara_arcana_bolt_1", true, false) != null and viewer.find_child("DeckCard_chiara_arcana_bolt_0", true, false) != null, "the upgraded copy is shown apart from the plain ones")
	var bolts := viewer.find_child("DeckCard_chiara_arcana_bolt_0", true, false)
	var copies := bolts.find_child("Copies", true, false) as Label if bolts != null else null
	check(copies != null and copies.text == "× 2", "copies are grouped (× 2 plain Arcane Bolts)")
	await _shot("deck_01_party")

	(viewer.find_child("DeckTab_bianca", true, false) as Button).pressed.emit()
	await _wait(0.2)
	var bianca_size := GameState.party.get_member("bianca").deck.size()
	check(count.text == "%d cards" % bianca_size and viewer.find_child("DeckCard_chiara_arcana_bolt_0", true, false) == null, "Bianca's tab shows only her %d cards" % bianca_size)
	await _shot("deck_02_bianca")

	var hymn := viewer.find_child("DeckCard_bianca_holy_hymn_0", true, false)
	var hymn_view := hymn.find_children("*", "CardView", true, false)[0] as CardView if hymn != null else null
	if hymn_view != null:
		hymn_view.pressed.emit(hymn_view)
	await _wait(0.3)
	var inspect := viewer.find_child("DeckInspect", true, false)
	check(inspect != null, "tapping a card shows it large with its details")
	await _shot("deck_03_inspect")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _wait(0.3)
	check(_viewer() != null and viewer.find_child("DeckInspect", true, false) == null, "Escape closes the close-up first")
	Input.parse_input_event(esc)
	await _wait(0.3)
	check(_viewer() == null, "and then the viewer")

	(_find("DeckButton") as Button).pressed.emit()
	await _wait(0.3)
	(_viewer().find_child("CloseDeck", true, false) as Button).pressed.emit()
	await _wait(0.3)
	check(_viewer() == null and GameState.party.get_total_deck_size() == total, "Close shuts it and the decks are untouched")

	# Relics: no button without relics; with relics, the button opens a list with each one's text.
	check(_find("RelicButton") == null, "no Relics button before the party finds one")
	GameState.inventory.relics.append("guardian_locket")
	GameState.inventory.relics.append("healers_pendant")
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.8)
	var relic_button := _find("RelicButton") as Button
	check(relic_button != null and relic_button.is_visible_in_tree() and relic_button.text == "Relics (2)" and relic_button.size.y >= 44, "the map shows a touch-sized Relics (2) button")
	relic_button.pressed.emit()
	await _wait(0.3)
	var relic_viewer := SceneRouter.current_screen.get_node_or_null("RelicViewer")
	check(relic_viewer != null and relic_viewer.find_child("Relic_guardian_locket", true, false) != null and relic_viewer.find_child("Relic_healers_pendant", true, false) != null, "the relic list names both relics")
	await _shot("deck_04_relics")
	(relic_viewer.find_child("CloseRelics", true, false) as Button).pressed.emit()
	await _wait(0.3)
	check(SceneRouter.current_screen.get_node_or_null("RelicViewer") == null and GameState.inventory.relics.size() == 2, "Close shuts the relic list and keeps the relics")
