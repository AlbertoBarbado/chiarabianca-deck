class_name DeckViewer
extends ColorRect
## Full-screen overlay listing the party's cards (each princess's own deck, which together form the
## shared battle deck). Tabs: the whole party or one princess. Copies are grouped (× N); tapping a
## card shows it large with its details. Closes with the Close button, a tap on the dim background
## or Escape. Works on touch and mouse alike; it only reads the party, never changes it.
##   DeckViewer.open(screen, GameState.party)

const CARD_SCALE := 0.82
const Z := 120  # above map markers and screen chrome

var _party: Party
var _filter: String = ""  # "" = whole party, otherwise a member id
var _flow: HFlowContainer
var _count_label: Label
var _tabs: Dictionary = {}
var _inspect: Control


static func open(parent: Node, party: Party) -> DeckViewer:
	var existing := parent.get_node_or_null("DeckViewer") as DeckViewer
	if existing != null:
		return existing
	var viewer := DeckViewer.new()
	viewer.name = "DeckViewer"
	viewer._party = party
	parent.add_child(viewer)
	return viewer


## Groups identical cards (same id and upgrade level): [{owned: OwnedCard, count: int}].
static func group_deck(member: PartyMember) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var index: Dictionary = {}
	for owned in member.deck:
		var key := "%s|%d" % [owned.card_id, owned.upgrade_level]
		if index.has(key):
			groups[index[key]]["count"] += 1
		else:
			index[key] = groups.size()
			groups.append({"owned": owned, "count": 1})
	return groups


func _ready() -> void:
	color = Color(UITheme.NAVY_DEEP, 0.94)
	z_index = Z
	mouse_filter = Control.MOUSE_FILTER_STOP
	UIFactory.full_rect(self)
	gui_input.connect(_on_background_input)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(center)
	add_child(center)
	var panel := UIFactory.panel()
	var viewport := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(1100.0, viewport.x - 40.0), minf(640.0, viewport.y - 40.0))
	center.add_child(panel)
	var column := UIFactory.vbox(8)
	panel.add_child(column)

	var header := UIFactory.hbox(12)
	header.add_child(UIFactory.label("Party Deck", &"HeaderLabel"))
	_count_label = UIFactory.label("", &"DimLabel")
	_count_label.name = "DeckCount"
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_count_label)
	header.add_child(UIFactory.expander())
	var close := UIFactory.button("Close", true, Vector2(140, 48))
	close.name = "CloseDeck"
	close.pressed.connect(queue_free)
	header.add_child(close)
	column.add_child(header)

	var tabs := UIFactory.hbox(8)
	tabs.add_child(_make_tab("", "Whole party", UITheme.GOLD))
	for member in _party.members:
		var spec_name := member.specialization.display_name if member.specialization != null else ""
		tabs.add_child(_make_tab(member.id, "%s · %s" % [member.definition.display_name, spec_name], member.definition.accent_color))
	column.add_child(tabs)
	column.add_child(UIFactory.label("Each princess owns her cards; in battle they are shuffled into one shared deck. Tap a card to look closer.", &"DimLabel", true))

	var scroll := UIFactory.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_flow = HFlowContainer.new()
	_flow.name = "DeckCards"
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 10)
	_flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_flow)
	_show_filter("")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _inspect != null:
			_close_inspect()
		else:
			queue_free()


func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		queue_free()


func _make_tab(member_id: String, text: String, accent: Color) -> Button:
	var tab := UIFactory.button(text, false, Vector2(0, 44))
	tab.name = "DeckTab_" + (member_id if member_id != "" else "all")
	tab.toggle_mode = true
	tab.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	tab.add_theme_color_override("font_pressed_color", accent)
	tab.pressed.connect(_show_filter.bind(member_id))
	_tabs[member_id] = tab
	return tab


func _show_filter(member_id: String) -> void:
	_filter = member_id
	for key: String in _tabs:
		(_tabs[key] as Button).set_pressed_no_signal(key == member_id)
	UIFactory.clear_children(_flow)
	var total := 0
	for member in _party.members:
		if member_id != "" and member.id != member_id:
			continue
		total += member.deck.size()
		for entry in group_deck(member):
			_flow.add_child(_make_stack(member, entry))
	_count_label.text = "%d cards" % total
	if total == 0:
		_flow.add_child(UIFactory.label("No cards.", &"DimLabel"))


func _make_stack(member: PartyMember, entry: Dictionary) -> Control:
	var owned: OwnedCard = entry["owned"]
	var box := UIFactory.vbox(2)
	box.name = "DeckCard_%s_%d" % [owned.card_id, owned.upgrade_level]
	var view := CardView.new()
	view.show_owned(DataRegistry.get_card(owned.card_id), member.id, owned.upgrade_level)
	view.set_scale_factor(CARD_SCALE)
	view.pressed.connect(func(_v: CardView) -> void: _open_inspect(member, owned, int(entry["count"])))
	box.add_child(view)
	var count := UIFactory.label("× %d" % entry["count"], &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	count.name = "Copies"
	box.add_child(count)
	return box


func _open_inspect(member: PartyMember, owned: OwnedCard, count: int) -> void:
	_close_inspect()
	var def := DataRegistry.get_card(owned.card_id)
	var layer := ColorRect.new()
	layer.name = "DeckInspect"
	layer.color = Color(0, 0, 0, 0.72)
	UIFactory.full_rect(layer)
	layer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_close_inspect())
	add_child(layer)
	_inspect = layer
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIFactory.full_rect(center)
	layer.add_child(center)
	var row := UIFactory.hbox(24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	var view := CardView.new()
	view.show_owned(def, member.id, owned.upgrade_level)
	view.set_scale_factor(1.6)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(view)
	var info := UIFactory.panel()
	info.custom_minimum_size.x = 320
	var details := UIFactory.vbox(6)
	info.add_child(details)
	var name_text := def.display_name + ("+" if owned.upgrade_level > 0 else "")
	details.add_child(UIFactory.label(name_text, &"HeaderLabel", true))
	details.add_child(UIFactory.label("Owner: %s (%s)" % [member.definition.display_name, member.specialization.display_name if member.specialization != null else ""]))
	details.add_child(UIFactory.label("Type: %s · Cost: %d · Rarity: %s" % [def.card_type.capitalize(), def.cost, def.rarity.capitalize()], &"DimLabel", true))
	details.add_child(UIFactory.label("Copies in deck: %d" % count, &"DimLabel", true))
	if owned.upgrade_level == 0 and not def.upgrade.is_empty():
		details.add_child(UIFactory.label("Upgrade: " + str(def.upgrade.get("description", "")), &"DimLabel", true))
	details.add_child(UIFactory.label("Tap anywhere to close.", &"DimLabel"))
	row.add_child(info)


func _close_inspect() -> void:
	if _inspect != null:
		_inspect.queue_free()
		_inspect = null
