class_name CombatEnemyView
extends CombatUnitView
## Enemy on the left side of the battlefield (Slay-the-Spire style): pose art, a small intent badge
## above its head (icon + damage / block number) and only its life bar below. Hovering (desktop) or
## tapping (touch / click when no card is selected) pops up the details (CombatUnitView's detail
## panel): name, HP, Block, the full intent text and statuses.

const ELITE_TINT := Color(1.25, 1.1, 0.78)
const BADGE_HEIGHT := 28.0

var _badge: HBoxContainer


func setup_enemy(enemy: Combatant, enemy_def_id: String) -> void:
	info_height = 30.0
	setup_unit(enemy.id, true, enemy.accent_color, func(state: String) -> Texture2D: return CombatPresentation.enemy_state(enemy_def_id, state))
	size_scale = CombatPresentation.enemy_scale(enemy_def_id)
	set_motion_profile(CombatPresentation.enemy_motion(enemy_def_id))
	ground_sink = CombatPresentation.enemy_sink(enemy_def_id)
	if enemy.enemy_def != null and enemy.enemy_def.elite:
		# Reusable elite treatment (no new artwork): warm gold tint on the existing sprite and a gold name.
		_base_tint = ELITE_TINT
		_art.self_modulate = ELITE_TINT
	_badge = UIFactory.hbox(3)
	_badge.name = "IntentBadge"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_badge)
	_init_detail_panel("EnemyDetail", false)


## intent_text is formatted by the combat screen (it knows the resolved target).
func update_enemy(enemy: Combatant, intent_text: String) -> void:
	set_alive(enemy.is_alive())
	set_health(enemy.hp, enemy.max_hp)
	var elite := enemy.enemy_def != null and enemy.enemy_def.elite
	# Default view: only the life bar (plus the Block number when the enemy has Block).
	var bar_row := UIFactory.hbox(6)
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := UIFactory.hp_bar(enemy.hp, enemy.max_hp)
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(bar)
	var hp_label := UIFactory.label("%d" % enemy.hp, &"DimLabel")
	hp_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(hp_label)
	if enemy.block > 0:
		bar_row.add_child(UIFactory.icon("block", 16))
		var block_label := UIFactory.label("%d" % enemy.block, &"DimLabel")
		block_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		bar_row.add_child(block_label)
	set_info_rows([bar_row] as Array[Control])
	_update_badge(enemy)
	_update_detail(enemy, intent_text, elite)


## Enemy status chips sit above the intent badge.
func status_row_gap() -> float:
	return BADGE_HEIGHT


func on_vanished() -> void:
	UIFactory.clear_children(_badge)
	_detail.visible = false
	_pinned = false


func _update_badge(enemy: Combatant) -> void:
	UIFactory.clear_children(_badge)
	if not enemy.is_alive() or enemy.intent == null:
		return
	if enemy.will_freeze():  # Chill brought its initiative to 0: it will lose this action
		var ice := CombatUnitView.status_icon("chill")
		if ice != null:
			var ice_rect := TextureRect.new()
			ice_rect.texture = ice
			ice_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ice_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ice_rect.custom_minimum_size = Vector2(26, 26)
			ice_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_badge.add_child(ice_rect)
		var frozen := UIFactory.label("Frozen", &"HeaderLabel")
		frozen.name = "FrozenTag"
		frozen.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT)
		frozen.add_theme_color_override("font_color", Color("bfe8ff"))
		frozen.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		frozen.add_theme_constant_override("outline_size", 5)
		frozen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.add_child(frozen)
		return
	var defend := enemy.intent.type == EnemyIntent.TYPE_DEFEND
	var emblem := UIAssets.texture("icons/icon_shield" if defend else "icons/icon_combat")
	if emblem != null:  # the ornate UI icons (cut-outs), not the old square tiles
		var icon_rect := TextureRect.new()
		icon_rect.texture = emblem
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(28, 28)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.add_child(icon_rect)
	else:
		_badge.add_child(UIFactory.icon("block" if defend else "combat", 24))
	var badge_text := "%d" % enemy.intent.value
	if enemy.intent.hits_all:
		badge_text += " all"
	var rider := enemy.intent.status_id if enemy.intent.status_value > 0 else ""
	var value := UIFactory.label(badge_text, &"HeaderLabel")
	value.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT)
	var element := enemy.intent.element
	value.add_theme_color_override("font_color", UITheme.SILVER if defend else (UITheme.CRIMSON.lightened(0.35) if element == DamageTypes.PHYSICAL else DamageTypes.color(element).lightened(0.15)))
	value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	value.add_theme_constant_override("outline_size", 5)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(value)
	if rider != "":  # the status the attack adds: its own icon and amount, in its colour
		var style: Dictionary = STATUS_STYLE.get(rider, {})
		var rider_texture := CombatUnitView.status_icon(rider)
		if rider_texture != null:
			var rider_icon := TextureRect.new()
			rider_icon.texture = rider_texture
			rider_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rider_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rider_icon.custom_minimum_size = Vector2(24, 24)
			rider_icon.modulate = CombatUnitView.status_icon_tint(rider)
			rider_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_badge.add_child(rider_icon)
		var amount := UIFactory.label("+%d" % enemy.intent.status_value, &"HeaderLabel")
		amount.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL + 2)
		amount.add_theme_color_override("font_color", (style.get("color", UITheme.SILVER) as Color).lightened(0.2))
		amount.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		amount.add_theme_constant_override("outline_size", 5)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.add_child(amount)


func _update_detail(enemy: Combatant, intent_text: String, elite: bool) -> void:
	var column := _begin_detail()
	column.add_child(_detail_title(("★ " if elite else "") + enemy.display_name, UITheme.GOLD if elite else enemy.accent_color.lightened(0.3)))
	column.add_child(_detail_line("HP %d / %d" % [enemy.hp, enemy.max_hp] + ("   Block %d" % enemy.block if enemy.block > 0 else ""), UITheme.SILVER))
	if enemy.is_alive():
		column.add_child(_detail_line("Intent: " + ("Frozen — loses this turn" if enemy.will_freeze() else intent_text), Color("bfe8ff") if enemy.will_freeze() else UITheme.GOLD))
		var initiative_text := "Initiative %d" % enemy.base_initiative
		if enemy.initiative() != enemy.base_initiative:
			initiative_text += " → %d (Chill)" % enemy.initiative()
		column.add_child(_detail_line(initiative_text, UITheme.SILVER))
		for entry in DamageTypes.describe_affinity(enemy.affinity):
			var weak := int(entry["pct"]) > 0
			var line := _detail_line(("Weak: " if weak else "Resists: ") + DamageTypes.display_name(str(entry["element"])) + (" +%d%%" % int(entry["pct"]) if weak else " %d%%" % -int(entry["pct"])), DamageTypes.color(str(entry["element"])))
			line.name = "Affinity_" + str(entry["element"])
			column.add_child(line)
		for row in CombatUnitView.status_rows(enemy.statuses, DETAIL_FONT, true, DETAIL_WRAP_WIDTH):
			column.add_child(row)
	else:
		column.add_child(_detail_line("Defeated", UITheme.SILVER))
	_end_detail()


func _after_layout() -> void:
	if _badge == null or _detail == null:
		return
	_badge.size = Vector2(size.x, BADGE_HEIGHT)
	_badge.position = Vector2(0, _art_holder.position.y - BADGE_HEIGHT + 2.0)
	_badge.z_index = 9  # never hidden behind a neighbour's sprite
	_place_detail()
