extends Node
## Card look-book and checks: every card type silhouette, rarity ribbon, both owners, upgraded and
## unplayable states, the hand glows (playable / hovered / selected), and every card in the game
## rendered at hand size with its text fitting. Screenshots for art review.
##   godot --path . res://tests/ui/card_gallery_test.tscn -- <screenshot_dir>

const SAMPLES := [
	["chiara_fire_ember", "chiara", 0], ["chiara_frost_spike", "chiara", 1], ["chiara_arcana_pulse", "chiara", 0],
	["chiara_fire_epic_heart", "chiara", 0], ["bianca_ash_ignite", "bianca", 0], ["bianca_ash_powder", "bianca", 1],
	["bianca_holy_judgment", "bianca", 0], ["bianca_tanking_wall", "bianca", 0], ["bianca_ash_epic_ashfall", "bianca", 0],
	["bianca_ash_veil", "bianca", 0],
]

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	DataRegistry.reload()
	await _run()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


func _frames(count: int = 4) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, shot_name])


func _background() -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color("1c2533")
	bg.size = get_viewport().get_visible_rect().size
	add_child(bg)
	return bg


func _run() -> void:
	var bg := _background()
	# Sheet 1: samples at hand size (scaled like the hand) with states.
	var views: Array[CardView] = []
	for i in SAMPLES.size():
		var entry: Array = SAMPLES[i]
		var view := CardView.new()
		view.show_owned(DataRegistry.get_card(entry[0]), entry[1], entry[2])
		view.show_playable_glow = true
		bg.add_child(view)
		view.size = CardView.CARD_SIZE
		view.position = Vector2(40 + (i % 5) * 245, 50 + (i / 5) * 330)
		views.append(view)
	views[1].set_playable(false)
	views[2].set_hovered(true)
	views[3].set_selected(true)
	await _frames(6)
	await _shot("cards_01_samples")
	check(views.all(func(v: CardView) -> bool: return not v.text_clipped), "sample cards fit their text")
	var types: Dictionary = {}
	for view in views:
		types[view.definition.card_type] = (view.find_child("Art", true, false) as Control).material.get_shader_parameter("shape")
	check(types.get("attack", -1) == 1 and types.get("spell", -1) == 2 and types.get("power", -1) == 3 and types.get("defense", -1) == 0, "the art window's silhouette follows the card type (%s)" % str(types))
	check((views[1].find_child("Cost", true, false) as Label).get_theme_color("font_color") == CardView.COST_UNAFFORDABLE, "an unplayable card shows its cost in red")
	var upgraded_text := (views[1].find_child("CardText", true, false) as RichTextLabel).text
	check(upgraded_text.contains(CardTextFormat.UPGRADED_COLOR.to_html(false)), "upgraded numbers are green")
	var plain_text := (views[0].find_child("CardText", true, false) as RichTextLabel).text
	check(plain_text.contains("[b]") and plain_text.contains(DamageTypes.color("fire").lightened(0.15).to_html(false)) or plain_text.contains("[b][color="), "rules text highlights numbers and keywords")

	# Sheet 2: big versions (reward size) of a few cards.
	for view in views:
		view.queue_free()
	await _frames(2)
	var big: Array[CardView] = []
	for i in 4:
		var entry: Array = SAMPLES[[0, 4, 6, 8][i]]
		var view := CardView.new()
		view.show_owned(DataRegistry.get_card(entry[0]), entry[1], entry[2])
		bg.add_child(view)
		view.set_scale_factor(1.9)
		view.size = view.custom_minimum_size
		view.position = Vector2(30 + i * 310, 60)
		big.append(view)
	await _frames(6)
	await _shot("cards_02_large")
	for view in big:
		view.queue_free()

	# Every card and upgrade at hand size fits its text.
	var holder := Control.new()
	bg.add_child(holder)
	var all_views: Array[CardView] = []
	var index := 0
	for card_id: String in DataRegistry.cards:
		var def: CardDef = DataRegistry.cards[card_id]
		for level in [0, 1] if not def.upgrade.is_empty() else [0]:
			var view := CardView.new()
			view.show_owned(def, def.owner_character_id, level)
			holder.add_child(view)
			view.size = CardView.CARD_SIZE
			view.position = Vector2((index % 16) * 78, (index / 16) * 70)
			all_views.append(view)
			index += 1
	await _frames(8)
	var clipped: Array[String] = []
	for view in all_views:
		if view.text_clipped:
			clipped.append(view.definition.id)
	check(clipped.is_empty(), "all %d cards and upgrades fit their name and text (clipped: %s)" % [all_views.size(), ", ".join(clipped)])
