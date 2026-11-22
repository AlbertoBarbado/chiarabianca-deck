extends ScreenBase
## Combat battlefield: enemies on the left, Chiara and Bianca on the right, turn / phase / log and
## potions above, the overlapping hand along the bottom, energy and End Turn beside it, and a clear
## centre for VFX, cut-ins and floating numbers. Renders CombatManager state and forwards input;
## it contains no combat rules. Input is click / tap based; keys 1-9, E and Esc are shortcuts.
## On touch the first tap on a card enlarges it and the second plays or targets it; Cancel (or Esc
## or a tap on empty ground) clears a selection.

const HAND_HEIGHT := 262.0
const SIDE_DOCK_WIDTH := 180.0
const MARGIN := 12

var combat: CombatManager

var _selected_card: CardInstance = null
var _armed_card: CardInstance = null  # touch: enlarged but not yet played
var _preview_target_id := ""  # enemy under the pointer while a card is selected (damage preview)
var _touch_mode: bool = false
var _log_lines: Array[String] = []

var _title_label: Label
var _phase_label: Label
var _potion_row: HBoxContainer
## Potion waiting for its drinker ("" = none).
var _armed_potion := ""
var _log_label: Label
var _battlefield: CombatBattlefield
var _hand: CombatHand
var _chips: Dictionary = {}  # character id -> VBoxContainer holding that character's vitals
var _pile_buttons: Dictionary = {}  # "draw" | "discard" | "exhaust" -> Button
var _energy_label: Label
var _end_turn: Button
var _cancel: Button
var _overlay: Control
## Layers above the battlefield; all ignore input.
var _fx_layer: Control
var _cutin_layer: Control
var _vfx: CombatVfxManager
var _animations: CombatAnimationController
var _panels: Dictionary = {}    # combatant id -> unit view (kept for VFX and floating numbers)
var _last_hp: Dictionary = {}   # combatant id -> hp at the previous refresh
var _last_block: Dictionary = {}
var _last_energy: int = -1
var _aether_box: HBoxContainer
var _aether_label: Label
var _last_aether: int = -1
var _aether_uses: int = -1
var _momentum_box: HBoxContainer
var _momentum_label: Label
var _last_momentum: int = -1
var _momentum_uses: int = -1  # -1 unknown, 0 no Aether cards, 1 the party has some
var _shown_phase_enemy: bool = false
var _encounter: Dictionary = {}


func _menu_screen() -> bool:
	return false


func _build() -> void:
	var node := GameState.get_current_node()
	combat = CombatManager.new()
	_encounter = DataRegistry.get_encounter(GameState.current_encounter_id())
	combat.setup(GameState.party, _encounter, GameState.inventory)
	combat.message.connect(_on_message)
	combat.changed.connect(_refresh)
	combat.ended.connect(_on_ended)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, MARGIN)

	var column := UIFactory.vbox(6)
	root.add_child(column)
	column.add_child(_build_header())

	_battlefield = CombatBattlefield.new()
	_battlefield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battlefield.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battlefield.mouse_filter = Control.MOUSE_FILTER_STOP
	_battlefield.gui_input.connect(_on_battlefield_input)
	column.add_child(_battlefield)
	_battlefield.setup(combat)
	_build_relic_bar()
	_battlefield.unit_pressed.connect(_on_unit_pressed)
	_battlefield.target_hovered.connect(_on_target_hovered)
	_battlefield.impact.connect(_shake)
	combat.visual_event.connect(_on_affinity_event)
	combat.visual_event.connect(_on_reaction_event)
	_battlefield.set_lighting(CombatPresentation.lighting(str(_backdrop().get("asset_id", ""))))
	for member_id: String in _battlefield.party_views:
		var party_view: CombatCharacterView = _battlefield.party_views[member_id]
		party_view.hide_info()
		party_view.rows_sink = _fill_chip.bind(member_id)
	for view in _battlefield.all_views():
		_panels[view.unit_id] = view
	column.add_child(_build_bottom())
	if combat.is_elite or combat.is_boss or combat.cinematic != "":
		_show_elite_intro()

	# Spell / impact sprites, cut-ins and floating numbers sit above the battlefield and the hand.
	_vfx = CombatVfxManager.new()
	UIFactory.full_rect(_vfx)
	# Unit sprites use z_index 1 and their status chips 9: without this, an effect drawn inside a
	# front-row silhouette (energy, draw, heals) would be hidden behind the sprite.
	_vfx.z_index = VFX_Z
	add_child(_vfx)
	_vfx.setup(combat, _locate_panel)
	_cutin_layer = Control.new()
	_cutin_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(_cutin_layer)
	_cutin_layer.z_index = VFX_Z
	add_child(_cutin_layer)
	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(_fx_layer)
	_fx_layer.z_index = VFX_Z
	add_child(_fx_layer)
	_animations = CombatAnimationController.new()
	add_child(_animations)
	_animations.setup(combat, _battlefield, _cutin_layer)

	combat.start()


## Elite encounters announce themselves with a banner (non-blocking, fades out) and an ELITE tag in the header.
func _show_elite_intro() -> void:
	var tag := UIFactory.label("BOSS" if combat.is_boss else ("ELITE ENCOUNTER" if combat.is_elite else combat.cinematic.to_upper()), &"DimLabel")
	tag.name = "EliteTag"
	tag.add_theme_color_override("font_color", UITheme.GOLD)
	_phase_label.get_parent().add_child(tag)
	_show_encounter_cinematic()


## Full-screen introduction for elites and bosses: the battlefield darkens behind a vignette, the
## foe's silhouette rises in, then a kicker line, the title in display type between ornate dividers
## and the story line. It fades out by itself after a few seconds; a click or tap skips it.
## Skipped entirely when effects are Off. Purely presentation: combat has already started.
func _show_encounter_cinematic() -> void:
	if SettingsStore.load_values().get("effects_quality", "full") == "off":
		return
	var boss := combat.is_boss
	var accent := Color("e04a4a") if boss else UITheme.GOLD
	var overlay := Control.new()
	overlay.name = "EliteBanner"
	overlay.z_index = 100  # above the hand cards (they use z_index for hover) and every effect
	UIFactory.full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, 0.86)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(shade)
	overlay.add_child(shade)
	var glow := TextureRect.new()  # soft coloured light behind the foe
	var gradient := Gradient.new()
	gradient.set_color(0, Color(accent, 0.38))
	gradient.set_color(1, Color(accent, 0.0))
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow.texture = glow_texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(glow)
	overlay.add_child(glow)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(centre)
	overlay.add_child(centre)
	var column := UIFactory.vbox(6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(column)
	# The elite or boss leads the introduction; without one, the toughest foe (the Hall Captain).
	var leader: Combatant = combat.enemies[0]
	for enemy in combat.enemies:
		if enemy.max_hp > leader.max_hp:
			leader = enemy
	for enemy in combat.enemies:
		if enemy.enemy_def != null and (enemy.enemy_def.boss or enemy.enemy_def.elite):
			leader = enemy
			break
	var portrait := TextureRect.new()
	portrait.name = "FoePortrait"
	portrait.texture = CombatPresentation.enemy_state(leader.enemy_def.id if leader.enemy_def != null else "", "prep")
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(420, minf(260.0, size.y * 0.36))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(portrait)
	var kicker_text := "— A GREAT EVIL STIRS —" if boss else ("— ELITE ENCOUNTER —" if combat.is_elite or combat.cinematic == "" else "— %s —" % combat.cinematic.to_upper())
	var kicker := UIFactory.label(kicker_text, &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	kicker.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL + 2)
	kicker.add_theme_color_override("font_color", accent.lightened(0.2))
	column.add_child(kicker)
	var heading := SectionHeading.new()
	heading.setup(combat.encounter_name, true)
	column.add_child(heading)
	var story := UIFactory.label(combat.intro_text if combat.intro_text != "" else "A dangerous foe bars the way.", &"", true, HORIZONTAL_ALIGNMENT_CENTER)
	story.custom_minimum_size.x = minf(640.0, size.x * 0.7)
	story.add_theme_color_override("font_color", UITheme.IVORY)
	column.add_child(story)
	var hint := UIFactory.label("Click or tap to begin", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	hint.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	column.add_child(hint)
	# Entrance: fade in, the foe rises, the words follow; then it holds and fades away.
	overlay.modulate.a = 0.0
	portrait.modulate.a = 0.0
	for line in [kicker, heading, story, hint]:
		line.modulate.a = 0.0
	var tween := overlay.create_tween()
	tween.tween_property(overlay, "modulate:a", 1.0, 0.35)
	tween.tween_property(portrait, "modulate:a", 1.0, 0.45)
	for line in [kicker, heading, story, hint]:
		tween.tween_property(line, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.2)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.5)
	tween.tween_callback(overlay.queue_free)
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			tween.kill()
			var out := overlay.create_tween()
			out.tween_property(overlay, "modulate:a", 0.0, 0.2)
			out.tween_callback(overlay.queue_free))


## Slay-the-Spire style bar: both characters' vitals, the encounter title/phase/log, energy and the
## clickable draw / discard / exhaust piles. Enemy health stays on the enemies themselves.
func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.add_theme_stylebox_override("panel", UITheme.compact_panel_style(0.26, Vector4(14, 5, 14, 5)))
	var top := UIFactory.hbox(12)
	bar.add_child(top)
	for member in GameState.party.members:
		var chip := PanelContainer.new()
		chip.name = "Chip_" + member.id
		chip.custom_minimum_size.x = 120
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.size_flags_stretch_ratio = 1.2
		chip.add_theme_stylebox_override("panel", UITheme.compact_panel_style(0.2, Vector4(12, 5, 12, 5), Color.WHITE.lerp(member.definition.accent_color.lightened(0.5), 0.35)))
		var chip_box := UIFactory.vbox(0)
		chip.add_child(chip_box)
		_chips[member.id] = chip_box
		top.add_child(chip)
	var left := UIFactory.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.x = 60
	_title_label = UIFactory.label("", &"HeaderLabel")
	_title_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	# Long encounter names shrink with "…" instead of widening the bar (the Aether and Momentum
	# counters can both be shown); the full name stays in the tooltip.
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.clip_text = true
	_title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(_title_label)
	_phase_label = UIFactory.label("Player Turn", &"DimLabel")
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_phase_label.add_theme_color_override("font_color", UITheme.MAGIC_BLUE)
	left.add_child(_phase_label)
	top.add_child(left)
	_log_label = UIFactory.label("", &"DimLabel", true, HORIZONTAL_ALIGNMENT_CENTER)
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.size_flags_stretch_ratio = 1.4
	_log_label.custom_minimum_size = Vector2(60, 0)
	_log_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_log_label.max_lines_visible = 2
	_log_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_log_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	top.add_child(_log_label)
	var energy_box := UIFactory.hbox(4)
	energy_box.name = "EnergyBox"
	energy_box.mouse_filter = Control.MOUSE_FILTER_STOP
	energy_box.tooltip_text = ENERGY_TIP
	energy_box.add_child(UIFactory.icon("energy", 28))
	_energy_label = UIFactory.label("", &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	_energy_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 2)
	energy_box.add_child(_energy_label)
	top.add_child(energy_box)
	# Aether: the party's surplus magic this turn (extra Energy and extra cards). Shown when the party
	# can use it or has some, so the counter never clutters decks without Aether cards.
	_aether_box = UIFactory.hbox(2)
	_aether_box.name = "AetherBox"
	_aether_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_aether_box.tooltip_text = AETHER_TIP
	_aether_box.add_child(UIFactory.icon("aether", 26, "✦"))
	_aether_label = UIFactory.label("0", &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	_aether_label.name = "AetherLabel"
	_aether_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 2)
	_aether_label.add_theme_color_override("font_color", AETHER_COLOR)
	_aether_box.add_child(_aether_label)
	top.add_child(_aether_box)
	# Momentum: cards played this turn (Wind's engine). Shown when the party has cards that use it.
	_momentum_box = UIFactory.hbox(2)
	_momentum_box.name = "MomentumBox"
	_momentum_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_momentum_box.tooltip_text = MOMENTUM_TIP
	_momentum_box.add_child(UIFactory.icon("momentum", 26, "»"))
	_momentum_label = UIFactory.label("0", &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	_momentum_label.name = "MomentumLabel"
	_momentum_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 2)
	_momentum_label.add_theme_color_override("font_color", MOMENTUM_COLOR)
	_momentum_box.add_child(_momentum_label)
	top.add_child(_momentum_box)
	for pile: String in ["draw", "discard", "exhaust"]:
		var button := Button.new()  # Flat style: the ornate theme buttons are too tall for a slim bar.
		button.text = pile.capitalize()
		button.custom_minimum_size = Vector2(64, 32)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_stylebox_override("normal", UITheme.compact_button_style())
		button.add_theme_stylebox_override("hover", UITheme.compact_button_style(Color(1.3, 1.22, 1.08)))
		button.add_theme_stylebox_override("pressed", UITheme.compact_button_style(Color(0.72, 0.74, 0.92)))
		button.add_theme_stylebox_override("focus", UITheme.compact_button_style(Color(1.2, 1.2, 1.4)))
		button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		button.name = pile.capitalize() + "PileButton"
		button.pressed.connect(_open_pile.bind(pile))
		_pile_buttons[pile] = button
		top.add_child(button)
	_potion_row = UIFactory.hbox(6)
	top.add_child(_potion_row)
	return bar


## Fills a character's chip in the top bar (rows come from CombatCharacterView).
func _fill_chip(rows: Array[Control], live_text: String, member_id: String) -> void:
	var box: VBoxContainer = _chips.get(member_id)
	if box == null:
		return
	box.get_parent().tooltip_text = _chip_tip(member_id, live_text)  # passive readiness and statuses on hover
	UIFactory.clear_children(box)
	for row in rows:
		box.add_child(row)


## Hover text of a character chip: passive state line first, then the passive's rule.
func _chip_tip(member_id: String, live_text: String) -> String:
	var spec: SpecializationDef = GameState.party.get_member(member_id).specialization
	var description := str(spec.passive.get("description", ""))
	return live_text if description == "" else live_text + "\n\n" + description


## Pile viewer: click Draw / Discard / Exhaust to see its cards (draw pile is sorted, never in draw order).
const PILE_VIEWER_Z := 200
const VFX_Z := 10  # effects, cut-ins and floating numbers: above sprites and resting hand cards


func _set_battle_visible(on: bool) -> void:
	for layer: Control in [_battlefield, _vfx, _cutin_layer]:
		if layer != null and is_instance_valid(layer):
			layer.visible = on


func _open_pile(pile: String) -> void:
	if get_node_or_null("PileViewer") != null:
		return
	var source: Array[CardInstance] = combat.deck.draw_pile if pile == "draw" else (combat.deck.discard_pile if pile == "discard" else combat.deck.exhaust_pile)
	var cards: Array[CardInstance] = source.duplicate()
	cards.sort_custom(func(a: CardInstance, b: CardInstance) -> bool: return a.owner_character_id + a.get_card_name() < b.owner_character_id + b.get_card_name())
	var dim := ColorRect.new()
	dim.name = "PileViewer"
	dim.color = Color(UITheme.NAVY_DEEP, 0.96)
	# Above everything: unit sprites, status chips and the enemy panels use z_index up to 40, which
	# drew them over the old viewer. The battle itself is hidden while the pile is open.
	dim.z_index = PILE_VIEWER_Z
	UIFactory.full_rect(dim)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			dim.queue_free())
	dim.tree_exiting.connect(_set_battle_visible.bind(true))
	_set_battle_visible(false)
	add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(center)
	dim.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size = Vector2(minf(980.0, size.x - 60.0), minf(560.0, size.y - 60.0))
	center.add_child(panel)
	var column := UIFactory.vbox(8)
	panel.add_child(column)
	column.add_child(UIFactory.label("%s pile (%d cards)" % [pile.capitalize(), cards.size()], &"HeaderLabel"))
	var scroll := UIFactory.scroll()
	column.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)
	for card in cards:
		var view := CardView.new()
		view.show_instance(card)
		flow.add_child(view)
	if cards.is_empty():
		flow.add_child(UIFactory.label("No cards here.", &"DimLabel"))
	var close := UIFactory.button("Close", true, Vector2(180, 52))
	close.name = "ClosePile"
	close.pressed.connect(dim.queue_free)
	column.add_child(close)


func _build_bottom() -> Control:
	var bottom := UIFactory.hbox(8)
	bottom.custom_minimum_size.y = HAND_HEIGHT

	var left_balance := Control.new()  # same width as the right dock, so the hand sits in the middle of the screen
	left_balance.custom_minimum_size.x = SIDE_DOCK_WIDTH
	left_balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(left_balance)
	_hand = CombatHand.new()
	_hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hand.card_pressed.connect(_on_card_pressed)
	_hand.draw_hold = func() -> bool: return _animations != null and _animations.is_enemy_phase()
	bottom.add_child(_hand)

	var right_dock := UIFactory.vbox(8)
	right_dock.custom_minimum_size.x = SIDE_DOCK_WIDTH
	right_dock.alignment = BoxContainer.ALIGNMENT_END
	_cancel = UIFactory.button("Cancel", false, Vector2(0, 48))
	_cancel.visible = false
	_cancel.pressed.connect(_cancel_selection)
	right_dock.add_child(_cancel)
	_end_turn = UIFactory.button("End Turn", true, Vector2(0, 72))
	_end_turn.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BUTTON + 4)
	_end_turn.pressed.connect(_on_end_turn)
	_end_turn.z_index = 30  # never covered by the hand or the battlefield
	right_dock.add_child(_end_turn)
	bottom.add_child(right_dock)
	return bottom


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		_cancel_selection()
	elif event.keycode == KEY_E:
		_on_end_turn()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var index: int = event.keycode - KEY_1
		if index < combat.deck.hand.size():
			_on_card_pressed(combat.deck.hand[index])


## Touch input switches the hand to "tap once to enlarge, tap again to play".
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION):
		_touch_mode = true


func set_touch_mode(on: bool) -> void:
	_touch_mode = on
	_armed_card = null


func _process(_delta: float) -> void:
	if _animations == null or _phase_label == null:
		return
	var enemy_phase := _animations.is_enemy_phase() or combat.state == CombatManager.State.ENEMY_TURN
	if enemy_phase != _shown_phase_enemy:
		_shown_phase_enemy = enemy_phase
		_update_phase_label()
		_show_turn_banner("Enemy Turn" if enemy_phase else "Your Turn", UITheme.CRIMSON.lightened(0.3) if enemy_phase else UITheme.GOLD)


## A short banner sweeps across the battlefield when the turn changes. It never blocks input and is
## skipped when effects are Off or the fight is over.
func _show_turn_banner(text: String, color: Color) -> void:
	if SettingsStore.load_values().get("effects_quality", "full") == "off" or combat.state == CombatManager.State.VICTORY or combat.state == CombatManager.State.DEFEAT:
		return
	var old := _fx_layer.get_node_or_null("TurnBanner")
	if old != null:
		old.queue_free()
	var banner := PanelContainer.new()
	banner.name = "TurnBanner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_stylebox_override("panel", UITheme.compact_panel_style(0.34, Vector4(46, 10, 46, 10)))
	var label := UIFactory.label(text, &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(label)
	_fx_layer.add_child(banner)
	banner.reset_size()
	var centre := Vector2((_fx_layer.size.x - banner.size.x) / 2.0, _fx_layer.size.y * 0.3)
	banner.position = centre - Vector2(120, 0)
	banner.modulate.a = 0.0
	var tween := banner.create_tween()
	tween.set_parallel(true)
	tween.tween_property(banner, "position:x", centre.x, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(banner, "modulate:a", 1.0, 0.18)
	tween.chain().tween_interval(0.55)
	tween.chain().tween_property(banner, "position:x", centre.x + 120.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(banner, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(banner.queue_free)


## Brief shake of the battlefield for heavy hits on the party (full effects only).
func _shake(strength: float) -> void:
	if SettingsStore.load_values().get("effects_quality", "full") != "full" or _battlefield == null:
		return
	var tween := _battlefield.create_tween()
	for i in 5:
		var amount := strength * (1.0 - i / 5.0)
		tween.tween_property(_battlefield, "position:x", _battlefield.position.x + (amount if i % 2 == 0 else -amount), 0.035)
	tween.tween_property(_battlefield, "position:x", _battlefield.position.x, 0.05)


func _update_phase_label() -> void:
	match combat.state:
		CombatManager.State.VICTORY:
			_phase_label.text = "Victory"
		CombatManager.State.DEFEAT:
			_phase_label.text = "Defeat"
		_:
			_phase_label.text = "Enemy Turn" if _shown_phase_enemy else "Player Turn"
	_phase_label.add_theme_color_override("font_color", UITheme.CRIMSON.lightened(0.3) if _shown_phase_enemy else UITheme.MAGIC_BLUE)


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	_title_label.text = "%s — Turn %d" % [combat.encounter_name, combat.turn]
	_title_label.tooltip_text = _title_label.text
	_update_phase_label()
	_refresh_potions()
	_refresh_units()
	_refresh_hand()
	var deck := combat.deck
	_pile_buttons["draw"].text = "Draw %d" % deck.draw_pile.size()
	_pile_buttons["discard"].text = "Discard %d" % deck.discard_pile.size()
	_pile_buttons["exhaust"].text = "Exhaust %d" % deck.exhaust_pile.size()
	_energy_label.text = "%d/%d" % [combat.energy, combat.max_energy]
	_pulse_energy()
	_refresh_aether()
	_refresh_momentum()
	_end_turn.disabled = combat.state != CombatManager.State.PLAYER_TURN
	# End Turn is always available during the player turn (no energy needed); it glows when nothing else can be played.
	# An X card with no Energy left would be played at X = 0, so it does not count as a move worth making.
	var can_play_any := combat.deck.hand.any(func(c: CardInstance) -> bool: return combat.can_play(c) == "" and not (c.definition.x_cost and combat.energy <= 0))
	_end_turn.modulate = Color(1.3, 1.18, 0.78) if combat.state == CombatManager.State.PLAYER_TURN and not can_play_any else Color.WHITE
	_cancel.visible = _selected_card != null or _armed_card != null
	_log_label.text = "\n".join(_log_lines.slice(-2))
	_battlefield.layout()
	_show_feedback()


func _pulse_energy() -> void:
	if _last_energy >= 0 and combat.energy != _last_energy and is_inside_tree():
		_energy_label.pivot_offset = _energy_label.size / 2.0
		_energy_label.scale = Vector2(1.25, 1.25)
		create_tween().tween_property(_energy_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_energy_label.add_theme_color_override("font_color", UITheme.MAGIC_BLUE if combat.energy > _last_energy else UITheme.GOLD)
	_last_energy = combat.energy


const AETHER_COLOR := CardTextFormat.AETHER_COLOR
const ENERGY_TIP := "Energy: what the party has left to spend this turn / what each turn starts with.
Every card costs the Energy shown on its blue gem; both sisters share the same Energy.
It refills at the start of your next turn."
const AETHER_TIP := "Aether: surplus magic this turn.\nEvery extra Energy gained and every extra card drawn adds 1 (max %d).\nHoly light feeds on it; unused Aether fades when your turn ends." % CombatManager.MAX_AETHER


func _refresh_aether() -> void:
	if _aether_uses == -1:
		_aether_uses = 1 if _deck_uses_aether() else 0
	_aether_box.visible = combat.aether > 0 or _aether_uses == 1
	_aether_label.text = str(combat.aether)
	_aether_box.modulate = Color.WHITE if combat.aether > 0 else Color(1, 1, 1, 0.5)
	if _last_aether >= 0 and combat.aether != _last_aether and is_inside_tree():
		_aether_label.pivot_offset = _aether_label.size / 2.0
		_aether_label.scale = Vector2(1.35, 1.35) if combat.aether > _last_aether else Vector2(0.8, 0.8)
		create_tween().tween_property(_aether_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_last_aether = combat.aether


const MOMENTUM_COLOR := Color("8fe8c8")
const MOMENTUM_TIP := "Momentum: cards the party has played this turn.
Cards that say \"per card already played this turn\" grow with it; Tailwind adds a Gust on the third card.
It resets when your turn ends."


func _refresh_momentum() -> void:
	if _momentum_uses == -1:
		var uses := GameState.party != null and GameState.party.members.any(func(m: PartyMember) -> bool: return m.specialization != null and m.specialization.id == "wind")
		var deck := combat.deck
		for pile: Array[CardInstance] in [deck.draw_pile, deck.hand, deck.discard_pile, deck.exhaust_pile]:
			for card in pile:
				uses = uses or CardEffects.uses_momentum(card.definition)
		_momentum_uses = 1 if uses else 0
	_momentum_box.visible = _momentum_uses == 1
	_momentum_label.text = str(combat.cards_played_this_turn)
	_momentum_box.modulate = Color.WHITE if combat.cards_played_this_turn > 0 else Color(1, 1, 1, 0.5)
	if _last_momentum >= 0 and combat.cards_played_this_turn > _last_momentum and is_inside_tree():
		_momentum_label.pivot_offset = _momentum_label.size / 2.0
		_momentum_label.scale = Vector2(1.35, 1.35)
		create_tween().tween_property(_momentum_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_last_momentum = combat.cards_played_this_turn


## True if any card the party brought reads or spends Aether.
func _deck_uses_aether() -> bool:
	var deck := combat.deck
	for pile: Array[CardInstance] in [deck.draw_pile, deck.hand, deck.discard_pile, deck.exhaust_pile]:
		for card in pile:
			if CardEffects.uses_aether(card.definition):
				return true
	return false


func _refresh_potions() -> void:
	UIFactory.clear_children(_potion_row)
	for item_id: String in GameState.inventory.items:
		var item := DataRegistry.get_item(item_id)
		# Compact potion button (icon + count) so the bar never grows wider than the screen; the name is the tooltip.
		var button := Button.new()
		button.name = "Potion_" + item_id
		button.text = "×%d" % GameState.inventory.count_of(item_id)
		button.tooltip_text = "%s
%s" % [item.get("name", item_id), item.get("description", "")]
		button.custom_minimum_size = Vector2(58, 32)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_stylebox_override("normal", UITheme.compact_button_style())
		button.add_theme_stylebox_override("hover", UITheme.compact_button_style(Color(1.3, 1.22, 1.08)))
		button.add_theme_stylebox_override("pressed", UITheme.compact_button_style(Color(0.72, 0.74, 0.92)))
		button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		var potion_icon := UIAssets.texture("icons/icon_potion")
		if potion_icon != null:
			button.icon = potion_icon
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 22)
		button.pressed.connect(_on_potion.bind(item_id))
		if _armed_potion == item_id:
			# Armed: bright green frame until someone drinks it or the choice is cancelled.
			button.add_theme_stylebox_override("normal", UITheme.box(Color(UITheme.NAVY_DEEP, 0.95), Color("7dffb0"), 8, 3, 4))
			button.add_theme_stylebox_override("hover", UITheme.box(Color(UITheme.NAVY_DEEP, 0.95), Color("b8ffd6"), 8, 3, 4))
		_potion_row.add_child(button)


## Updates the persistent unit views and the target highlighting for the selected card.
func _refresh_units() -> void:
	var selecting := _selected_card != null and combat.needs_target_choice(_selected_card)
	var wants_enemy := selecting and _selected_card.definition.target == CardDef.TARGET_SINGLE_ENEMY
	var wants_ally := selecting and _selected_card.definition.target == CardDef.TARGET_SINGLE_ALLY
	if _armed_potion != "":
		selecting = true
		wants_enemy = false
		wants_ally = true
	for enemy in combat.enemies:
		var view: CombatEnemyView = _battlefield.enemy_views[enemy.id]
		view.update_enemy(enemy, _intent_text(enemy))
		view.set_statuses(enemy.statuses if enemy.is_alive() else {})
		view.set_targeting(selecting, wants_enemy and enemy.is_alive())
	for c in combat.party_combatants:
		var view: CombatCharacterView = _battlefield.party_views[c.id]
		view.update_character(c, GameState.party.get_member(c.id).specialization, _live_text(c), _passive_text(c))
		var no_powers: Array[Dictionary] = []
		view.set_statuses(c.statuses if c.is_alive() else {}, c.block if c.is_alive() else 0, c.powers if c.is_alive() else no_powers)
		view.set_targeting(selecting, wants_ally and c.is_alive())


func _intent_text(enemy: Combatant) -> String:
	if enemy.intent == null:
		return "—"
	var target := combat.get_intent_target(enemy)
	return enemy.intent.describe(target.display_name if target != null else "")


## Passive readiness alone, e.g. "Kindled Spark: ready" ("" without a passive).
func _passive_text(c: Combatant) -> String:
	if not combat.passives.has_passive(c.id):
		return ""
	var passive: Dictionary = GameState.party.get_member(c.id).specialization.passive
	var state := "ready" if combat.passives.is_ready(c.id) else ("used this turn" if c.is_alive() else "fallen")
	return "%s: %s" % [passive.get("name", "Passive"), state]


## Passive readiness and active statuses for a party chip, e.g. "Kindled Spark: ready   Burn 2".
func _live_text(c: Combatant) -> String:
	var parts: Array[String] = []
	var passive := _passive_text(c)
	if passive != "":
		parts.append(passive)
	for status_id: String in c.statuses:
		var status_def := DataRegistry.get_status(status_id)
		parts.append(status_def.short_text(c.statuses[status_id]["stacks"]) if status_def != null else status_id.capitalize())
	return "   ".join(parts)


func _refresh_hand() -> void:
	_hand.set_cards(combat.deck.hand, func(card: CardInstance) -> bool: return combat.can_play(card) == "", _selected_card, _armed_card, _damage_preview)


## Damage numbers on the hand's cards (CardEffects.damage_preview). The selected card is previewed
## against the enemy under the pointer; with a single enemy left, every card is previewed against it
## (touch screens have no hover).
func _damage_preview(card: CardInstance) -> Array[Dictionary]:
	var target: Combatant = null
	var living := combat.get_living_enemies()
	if living.size() == 1:
		target = living[0]
	elif _preview_target_id != "" and (card == _selected_card or card == _armed_card):
		target = combat.get_combatant(_preview_target_id)
		if target != null and not target.is_alive():
			target = null
	return CardEffects.damage_preview(card, combat, target)


## The party's relics along the top-left of the battlefield (name and effect on hover); a relic pops
## when it does something (PassiveRunner.relic_triggered).
func _build_relic_bar() -> void:
	if combat.inventory == null or combat.inventory.relics.is_empty():
		return
	var bar := HBoxContainer.new()
	bar.name = "RelicBar"
	bar.add_theme_constant_override("separation", 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(8, 4)
	bar.z_index = 20
	for relic_id: String in combat.inventory.relics:
		bar.add_child(RelicIcon.create(relic_id, 34))
	_battlefield.add_child(bar)
	combat.passives.relic_triggered.connect(func(relic_id: String, _text: String) -> void:
		var icon := bar.get_node_or_null("RelicIcon_" + relic_id) as RelicIcon
		if icon != null:
			icon.flash())


func _on_target_hovered(unit_id: String) -> void:
	if unit_id == _preview_target_id:
		return
	_preview_target_id = unit_id
	if _selected_card != null or _armed_card != null:
		_refresh_hand()


## Screen rectangle (global) where effects should point for a combatant: its pose art.
func _locate_panel(combatant_id: String) -> Rect2:
	var view := _panels.get(combatant_id) as CombatUnitView
	if view == null or not is_instance_valid(view):
		return Rect2()
	return view.get_art_rect()


# --- Damage / heal / block feedback -----------------------------------------
# Pure presentation: compares each combatant with the previous refresh and shows a floating
# number plus a brief flash on its art. It never reads or changes combat rules.

const FLOAT_RISE := 46.0
const HEAVY_HIT := 8   # HP lost in one hit that shakes the screen
const FLOAT_TIME := 0.9
const COLOR_DAMAGE := Color("ff6b6b")
const COLOR_HEAL := Color("7be0a0")
const COLOR_BLOCK := Color("b9d4ff")


func _show_feedback() -> void:
	var events: Array[Dictionary] = []
	var everyone: Array[Combatant] = []
	everyone.append_array(combat.party_combatants)
	everyone.append_array(combat.enemies)
	for c in everyone:
		if _last_hp.has(c.id):
			var delta: int = c.hp - int(_last_hp[c.id])
			if delta < 0:
				events.append({"id": c.id, "text": "%d" % delta, "color": COLOR_DAMAGE})
				if c.side == Combatant.SIDE_PARTY and delta <= -HEAVY_HIT:
					_shake(minf(14.0, 4.0 - delta * 0.5))
			elif delta > 0:
				events.append({"id": c.id, "text": "+%d" % delta, "color": COLOR_HEAL})
			var block_delta: int = c.block - int(_last_block.get(c.id, 0))
			if block_delta > 0:
				events.append({"id": c.id, "text": "+%d Block" % block_delta, "color": COLOR_BLOCK})
		_last_hp[c.id] = c.hp
		_last_block[c.id] = c.block
	if events.is_empty():
		return
	await get_tree().process_frame  # Layout may have just changed; wait for it.
	var offset := 0
	for event in events:
		var view := _panels.get(event["id"]) as CombatUnitView
		if view == null or not is_instance_valid(view):
			continue
		_spawn_float(view, str(event["text"]), event["color"], offset)
		offset += 1


## "Weak!" / "Resist" pops over a unit when a hit's damage type changed its damage.
func _on_affinity_event(event: Dictionary) -> void:
	if str(event.get("kind", "")) != "affinity" or not is_inside_tree():
		return
	var pct := int(event.get("pct", 0))
	var element := str(event.get("element", DamageTypes.PHYSICAL))
	for target_id: String in event.get("target_ids", []):
		var view := _panels.get(target_id) as CombatUnitView
		if view != null and is_instance_valid(view):
			var text := ("Weak! %s" if pct > 0 else "Resist %s") % DamageTypes.display_name(element)
			# Pop-ups that arrive together over one unit stack upwards instead of overlapping.
			var now := Time.get_ticks_msec()
			var recent: Array = (_popup_times.get(target_id, []) as Array).filter(func(t: int) -> bool: return now - t < 700)
			recent.append(now)
			_popup_times[target_id] = recent
			_spawn_float(view, text, DamageTypes.color(element).lightened(0.2) if pct > 0 else UITheme.SILVER, -2 - (recent.size() - 1) * 2)
			affinity_popups += 1


## Twin reactions ("Combustion!", "Miasma!") and Blight executions pop over the units they touch.
func _on_reaction_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	if (kind != "reaction" and kind != "execute") or not is_inside_tree():
		return
	var text := str(event.get("reaction_name", "")) + "!" if kind == "reaction" else "Blighted!"
	# Campaign: a ♥ while twin reactions still strengthen the Sister Bond this expedition (capped).
	if kind == "reaction" and GameState.expedition != null and int(GameState.expedition.bond_counts.get("twin_reaction", 0)) + combat.reactions_fired <= Bond.cap("twin_reaction"):
		text += " ♥"
	var color := Color.from_string(str(event.get("color", "#c89cff")), Color("c89cff")) if kind == "reaction" else Color("c89cff")
	var ids: Array = event.get("target_ids", [])
	for i in ids.size():
		var view := _panels.get(str(ids[i])) as CombatUnitView
		if view != null and is_instance_valid(view):
			_spawn_float(view, text if i == 0 else "+" + text, color, -4)
			reaction_popups += 1


var reaction_popups: int = 0
var affinity_popups: int = 0
var _popup_times: Dictionary = {}  # unit id -> msec of its recent affinity pop-ups


func _spawn_float(view: CombatUnitView, text: String, color: Color, stagger: int) -> void:
	var label := UIFactory.label(text, &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(label)
	var area := view.get_art_rect()
	var start := area.position - _fx_layer.global_position + Vector2(area.size.x * 0.5 - 40.0, area.size.y * 0.25 + stagger * 22.0)
	label.size = Vector2(maxf(80.0, label.get_minimum_size().x + 8.0), 36)
	start.x -= (label.size.x - 80.0) / 2.0
	label.position = start
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(1.7, 1.7)  # numbers pop in, then rise and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", start.y - FLOAT_RISE, FLOAT_TIME)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_TIME).set_delay(FLOAT_TIME * 0.4)
	tween.chain().tween_callback(label.queue_free)
	if color == COLOR_DAMAGE or color == COLOR_HEAL:
		view.flash(color.lightened(0.3))


# --- Input handlers ----------------------------------------------------------

func _on_card_pressed(card: CardInstance) -> void:
	if combat.state != CombatManager.State.PLAYER_TURN:
		return
	if card == _selected_card:
		_cancel_selection()
		return
	var reason := combat.can_play(card)
	if reason != "":
		_on_message(reason)
		_refresh()
		return
	if _touch_mode and card != _armed_card:
		_armed_card = card  # first tap: enlarge only
		_on_message("%s: tap again to play." % card.get_card_name())
		_refresh()
		return
	_armed_card = null
	if combat.needs_target_choice(card):
		_select(card)
		_on_message("Choose a target for %s." % card.get_card_name())
		_refresh()
		return
	_select(null)
	_hand.mark_played(card, _play_point(""))
	combat.play_card(card)


func _on_unit_pressed(unit_id: String) -> void:
	if _armed_potion != "":
		if _battlefield.party_views.has(unit_id):
			_drink_armed_potion(unit_id)
		else:
			_on_message("Choose an ally to drink it.")
		return
	if _selected_card == null:
		return
	var is_enemy := _battlefield.enemy_views.has(unit_id)
	var wants_enemy := _selected_card.definition.target == CardDef.TARGET_SINGLE_ENEMY
	if is_enemy == wants_enemy and _battlefield.get_view(unit_id).is_targetable():
		_play_selected(unit_id)
	else:
		_on_message("Choose a valid target for %s." % _selected_card.get_card_name())  # Selection stays.


func _on_enemy_pressed(enemy_id: String) -> void:
	if _selected_card != null:
		_play_selected(enemy_id)


func _on_battlefield_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cancel_selection()  # A tap on empty ground cancels targeting.


func _play_selected(target_id: String) -> void:
	var card := _selected_card
	_select(null)
	_hand.mark_played(card, _play_point(target_id))
	combat.play_card(card, target_id)


## Where a played card flies: toward its target, or the middle of the battlefield.
## Played cards show themselves in the gap between the enemies (left) and the party (right), never
## on top of a unit, so the effect on the target stays visible.
func _play_point(_target_id: String) -> Vector2:
	var area := _battlefield.get_global_rect()
	var gap_x := (CombatBattlefield.ENEMY_ZONE.y + CombatBattlefield.PARTY_ZONE.x) / 2.0
	return area.position + Vector2(area.size.x * gap_x, area.size.y * 0.5)


func _select(card: CardInstance) -> void:
	_selected_card = card
	if card != null:
		_armed_potion = ""  # picking a card cancels a potion waiting for its drinker
	if combat.state == CombatManager.State.PLAYER_TURN:
		_refresh()


func _cancel_selection() -> void:
	if _armed_potion != "":
		_armed_potion = ""
		_refresh()
		return
	if _selected_card == null and _armed_card == null:
		return
	_armed_card = null
	_select(null)


## Tapping a potion arms it: the living allies glow green, the one under the pointer is outlined in
## white, and tapping an ally makes them drink it. Tapping the potion again (or empty ground) cancels.
func _on_potion(item_id: String) -> void:
	if combat.state != CombatManager.State.PLAYER_TURN:
		return
	_selected_card = null
	_armed_card = null
	# Party-wide brews (Block, Energy, draw) need no drinker: they act at once.
	if CombatManager.POTION_PARTY_EFFECTS.has(str((DataRegistry.get_item(item_id).get("effect", {}) as Dictionary).get("type", ""))):
		_armed_potion = ""
		var error := combat.use_potion(item_id)
		if error != "":
			_on_message(error)
		_refresh()
		return
	_armed_potion = "" if _armed_potion == item_id else item_id
	if _armed_potion != "":
		var item := DataRegistry.get_item(item_id)
		_on_message("Choose who drinks the %s." % str(item.get("name", "potion")))
	_refresh()


func _drink_armed_potion(target_id: String) -> void:
	var item_id := _armed_potion
	_armed_potion = ""
	var error := combat.use_potion(item_id, target_id)
	if error != "":
		_on_message(error)
	_refresh()


func _on_end_turn() -> void:
	if combat.state != CombatManager.State.PLAYER_TURN:
		return
	_selected_card = null
	_armed_card = null
	_hand.begin_discard()
	combat.end_player_turn()


func _on_message(text: String) -> void:
	_log_lines.append(text)
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines.slice(-2))


# --- End of combat -----------------------------------------------------------

func _on_ended(result: String) -> void:
	var won := result == CombatManager.RESULT_VICTORY
	if won:
		GameState.record_combat_victory(combat.gold_reward, _encounter, combat.reactions_fired)  # Gold, relic healing and reward roll: once, and saved.
	_update_phase_label()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.7)
	UIFactory.full_rect(_overlay)
	add_child(_overlay)
	var center := CenterContainer.new()
	UIFactory.full_rect(center)
	_overlay.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = 460
	center.add_child(panel)
	var column := UIFactory.vbox(14)
	panel.add_child(column)
	var result_label := UIFactory.label("Victory!" if won else "Defeat", &"TitleLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	result_label.add_theme_color_override("font_color", UITheme.GOLD if won else UITheme.CRIMSON.lightened(0.25))
	column.add_child(result_label)
	var faces := UIFactory.hbox(12)
	faces.alignment = BoxContainer.ALIGNMENT_CENTER
	for member in GameState.party.members:
		var face := AvatarFrame.new()
		face.setup(member.id, 84.0, member.specialization.get_accent(member.definition.accent_color))
		face.modulate = Color.WHITE if member.current_hp > 0 or won else Color(0.5, 0.5, 0.5)
		faces.add_child(face)
	column.add_child(faces)
	if won:
		var gold_row := UIFactory.icon_text("gold", "Gold gained: %d" % combat.gold_reward, 28)
		gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(gold_row)
	else:
		column.add_child(UIFactory.label("Both princesses have fallen.", &"", false, HORIZONTAL_ALIGNMENT_CENTER))
	var next := UIFactory.button("Continue", true, Vector2(0, 60))
	next.pressed.connect(_on_continue.bind(won))
	column.add_child(next)
	# Short fade-in; the result itself was decided by CombatManager before this runs.
	if SettingsStore.load_values().get("effects_quality", "full") != "off":
		_overlay.modulate.a = 0.0
		create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.35)


func _on_continue(won: bool) -> void:
	if won:
		SceneRouter.go(SceneRouter.Screen.REWARD)
	else:
		GameState.finish_run(GameState.RESULT_DEFEATED)
		SceneRouter.go_to_run_end()


## Battle backdrop: the room's terrain picture, else the map's, else the generic castle hall.
## Wide screens crop it mostly from the sky (floor anchor) so the units keep standing on floor.
func _backdrop() -> Dictionary:
	var custom := battle_backdrop_id()
	var backdrop := AssetCatalog.backdrop_by_asset(custom, Color.BLACK, 0.0)
	var floor := CombatPresentation.floor_info(custom)
	backdrop["anchor_y"] = float(floor["anchor_y"])
	backdrop["zoom"] = float(floor["zoom"])
	return backdrop


func battle_backdrop_id() -> String:
	if GameState.map_progress != null:
		var graph := GameState.map_progress.graph
		var custom := graph.terrain_backdrop(GameState.get_current_node())
		if custom == "" or AssetCatalog.texture(custom) == null:
			custom = graph.battle_backdrop
		if custom != "" and AssetCatalog.texture(custom) != null:
			return custom
	return "battle_castle_generic"


func _backdrop_dim() -> float:
	return 0.0
