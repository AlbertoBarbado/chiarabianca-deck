class_name CardPileModal
extends ColorRect
## Modal card gallery for the draw, discard and exhaust piles (and any read-only list of cards):
## a dim backdrop, a navy enamel frame (UIKit), a header with the pile name and count, a responsive
## gallery whose card size follows the space available (several columns on desktop, fewer on phones,
## never clipped: the gallery scrolls), and a large preview of the hovered or tapped card. Tapping the
## backdrop, pressing Escape or Close dismisses it. It only displays cards; it never changes them.

const PREVIEW_SCALE := 1.45
const GAP := 12.0
const MIN_CARD := 0.62
const MAX_CARD := 0.95

var _flow: HFlowContainer
var _scroll: ScrollContainer
var _preview_holder: Control
var _preview_text: Label
var _cards: Array[CardInstance] = []


## Opens the modal over `parent`. Returns it (already added).
static func open(parent: Node, title: String, cards: Array[CardInstance], node_name: String = "PileViewer") -> CardPileModal:
	var modal := CardPileModal.new()
	modal.name = node_name
	modal._cards = cards
	parent.add_child(modal)
	modal._build(title)
	return modal


func _build(title: String) -> void:
	color = Color(UITheme.NAVY_DEEP, 0.9)
	UIFactory.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			queue_free())
	var margin := MarginContainer.new()
	UIFactory.full_rect(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.name = "PileFrame"
	var style := UIKit.style("panel_navy")
	if style != null:
		panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var column := UIFactory.vbox(10)
	panel.add_child(column)
	var header := UIFactory.hbox(12)
	var heading := UIFactory.label(title, &"HeaderLabel", false)
	heading.name = "PileTitle"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var count := CastleUI.pill("%d card%s" % [_cards.size(), "" if _cards.size() == 1 else "s"], UITheme.VIOLET_LIGHT)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(count)
	column.add_child(header)
	var divider_texture := UIKit.picture("orn_divider")
	if divider_texture != null:
		var divider := TextureRect.new()
		divider.texture = divider_texture
		divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		divider.custom_minimum_size = Vector2(0, 16)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(divider)
	var body := UIFactory.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_scroll = UIFactory.scroll()
	_scroll.name = "PileScroll"
	body.add_child(_scroll)
	_flow = HFlowContainer.new()
	_flow.name = "PileGrid"
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", int(GAP))
	_flow.add_theme_constant_override("v_separation", int(GAP))
	_scroll.add_child(_flow)
	var side := UIFactory.vbox(8)
	side.name = "PilePreview"
	side.custom_minimum_size.x = CardView.CARD_SIZE.x * PREVIEW_SCALE + 8.0
	body.add_child(side)
	_preview_holder = CenterContainer.new()
	side.add_child(_preview_holder)
	_preview_text = UIFactory.label("Hover or tap a card to look at it closely.", &"DimLabel", true, HORIZONTAL_ALIGNMENT_CENTER)
	_preview_text.custom_minimum_size.x = side.custom_minimum_size.x
	side.add_child(_preview_text)
	for card in _cards:
		var view := CardView.new()
		view.show_instance(card)
		view.mouse_entered.connect(_preview.bind(card))
		view.pressed.connect(func(_v: CardView) -> void: _preview(card))
		_flow.add_child(view)
	if _cards.is_empty():
		_flow.add_child(UIFactory.label("No cards here.", &"DimLabel"))
	var footer := UIFactory.hbox(8)
	footer.add_child(UIFactory.expander())
	var close := UIFactory.button("Close", false, Vector2(200, 52))
	close.name = "ClosePile"
	close.pressed.connect(queue_free)
	footer.add_child(close)
	column.add_child(footer)
	if not _cards.is_empty():
		_preview(_cards[0])
	_scroll.resized.connect(_fit_cards)
	_fit_cards.call_deferred()
	close.grab_focus.call_deferred()


## Card size from the gallery width: as many columns as fit at a readable size (4-7 on desktop).
func _fit_cards() -> void:
	if _scroll == null or _flow == null:
		return
	var width := _scroll.size.x - 16.0
	var columns := clampi(int(width / (CardView.CARD_SIZE.x * 0.8 + GAP)), 2, 7)
	var scale := clampf((width - (columns - 1) * GAP) / columns / CardView.CARD_SIZE.x, MIN_CARD, MAX_CARD)
	for child in _flow.get_children():
		if child is CardView:
			(child as CardView).set_scale_factor(scale)
	# Narrow screens give the gallery all the room.
	var preview := find_child("PilePreview", true, false) as Control
	if preview != null:
		preview.visible = size.x >= 900.0


func _preview(card: CardInstance) -> void:
	UIFactory.clear_children(_preview_holder)
	var view := CardView.new()
	view.show_instance(card)
	view.set_scale_factor(PREVIEW_SCALE)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_holder.add_child(view)
	var owner := DataRegistry.get_character(card.owner_character_id)
	var spec := DataRegistry.get_specialization(card.definition.specialization_id)
	var parts: Array[String] = []
	if owner != null:
		parts.append(owner.display_name)
	if spec != null:
		parts.append(spec.display_name)
	parts.append(card.definition.rarity.capitalize())
	if card.is_upgraded():
		parts.append("Upgraded")
	_preview_text.text = " · ".join(parts)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
