class_name EnemyPanel
extends PanelContainer
## Enemy widget: portrait token, name, HP, block, statuses and the announced intent.
## Tap to target. No enemy illustrations exist yet, so the portrait is a themed token
## (accent gradient + initial); an enemy definition may later point at real art.

signal pressed(enemy_id: String)

const TOKEN_SIZE := 56

var enemy_id: String = ""


## intent_text is pre-formatted by the combat screen (it knows the resolved target).
func setup(enemy: Combatant, intent_text: String, targetable: bool) -> void:
	enemy_id = enemy.id
	UIFactory.clear_children(self)
	custom_minimum_size = Vector2(210, 150)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var border := UITheme.IVORY if targetable else enemy.accent_color
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.NAVY_DEEP, 0.95), border, 14, 4 if targetable else 2, 10))
	modulate = Color(1, 1, 1, 0.35) if not enemy.is_alive() else Color.WHITE

	var column := UIFactory.vbox(3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var header := UIFactory.hbox(8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_make_token(enemy))
	var title := UIFactory.vbox(2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UIFactory.label(enemy.display_name, &"")
	name_label.add_theme_color_override("font_color", enemy.accent_color.lightened(0.3))
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL + 1)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_child(name_label)
	var bar := UIFactory.hp_bar(enemy.hp, enemy.max_hp)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(bar)
	header.add_child(title)
	column.add_child(header)

	var hp_row := UIFactory.hbox(6)
	hp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(UIFactory.icon("health", 18))
	hp_row.add_child(UIFactory.label("HP %d / %d" % [enemy.hp, enemy.max_hp], &"DimLabel"))
	if enemy.block > 0:
		hp_row.add_child(UIFactory.icon("block", 18))
		hp_row.add_child(UIFactory.label("Block %d" % enemy.block, &"DimLabel"))
	column.add_child(hp_row)

	if enemy.is_alive():
		column.add_child(_make_intent_row(enemy, intent_text))
	else:
		column.add_child(UIFactory.label("Defeated", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	for status_id: String in enemy.statuses:
		column.add_child(_make_status_row(status_id, enemy.statuses[status_id]["stacks"]))


## Themed token standing in for an enemy portrait.
func _make_token(enemy: Combatant) -> Control:
	var gradient := Gradient.new()
	gradient.set_color(0, enemy.accent_color.lightened(0.15))
	gradient.set_color(1, enemy.accent_color.darkened(0.65))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.4)
	texture.fill_to = Vector2(1.0, 1.0)
	var tile := UIFactory.panel(UITheme.box(Color.TRANSPARENT, enemy.accent_color, 28, 2, 0))
	tile.custom_minimum_size = Vector2(TOKEN_SIZE, TOKEN_SIZE)
	tile.clip_contents = true
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := TextureRect.new()
	fill.texture = texture
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(fill)
	var initial := UIFactory.label(enemy.display_name.left(1), &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_color_override("font_color", Color.WHITE)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_child(initial)
	UIFactory.full_rect(initial)
	return tile


## Intent: icon by action type (attack = crossed swords, defend = shield) plus its text.
func _make_intent_row(enemy: Combatant, intent_text: String) -> Control:
	var row := UIFactory.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_name := "combat"
	if enemy.intent != null and enemy.intent.type == EnemyIntent.TYPE_DEFEND:
		icon_name = "block"
	row.add_child(UIFactory.icon(icon_name, 24))
	var intent_label := UIFactory.label("Intent: " + intent_text, &"", true)
	intent_label.add_theme_color_override("font_color", UITheme.GOLD)
	intent_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	intent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intent_label.custom_minimum_size.x = 0
	row.add_child(intent_label)
	return row


func _make_status_row(status_id: String, stacks: int) -> Control:
	var status_def := DataRegistry.get_status(status_id)
	var status_text := status_def.short_text(stacks) if status_def != null else "%s %d" % [status_id.capitalize(), stacks]
	var row := UIFactory.hbox(4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if AssetCatalog.icon(status_id) != null:
		row.add_child(UIFactory.icon(status_id, 18))
	var label := UIFactory.label(status_text, &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_color_override("font_color", UITheme.GOLD.lerp(Color("e0663a"), 0.6) if status_id == "burn" else UITheme.SILVER)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if status_def != null:
		label.tooltip_text = status_def.describe(stacks)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	row.add_child(label)
	return row


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(enemy_id)
		accept_event()
