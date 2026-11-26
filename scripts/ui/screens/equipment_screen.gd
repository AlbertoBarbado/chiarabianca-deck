extends ScreenBase
## Party equipment ("Inventory"). One character at a time stands on a lit stage between her nine
## slots (helmet, amulet, chest, gauntlets on the left; weapon, two rings, belt, boots on the
## right), with her bonuses as chips underneath. On the right: the party stash as a grid of sockets
## (filter by kind, best rarity first) and an item card that compares the item with what she wears.
##
## Two ways to do everything, so it works with a mouse and on a touch screen:
## - drag and drop: a stash item onto a slot or onto her (equip), a worn item onto the stash
##   (unequip) or onto the other ring slot (swap). While an item is carried, the places that would
##   take it glow and the others dim.
## - tap / click: select an item, then Equip / Unequip on its card.
## Logic lives in Equipment; every change is saved at once.

const LEFT_SLOTS: Array[String] = ["helmet", "amulet", "chest", "gauntlets"]
const RIGHT_SLOTS: Array[String] = ["weapon", "ring_1", "ring_2", "belt", "boots"]
const SLOT_TILE := Vector2(74, 74)
const STASH_MIN_CELLS := 15
const EFFECT_COLOR := Color("9fe8c8")  # an item's in-battle effect lines (jade), apart from plain stats
const FILTERS := {
	"all": {"label": "All", "slots": []},
	"weapons": {"label": "Weapons", "slots": ["weapon"]},
	"armour": {"label": "Armour", "slots": ["helmet", "chest", "gauntlets", "boots", "belt"]},
	"trinkets": {"label": "Trinkets", "slots": ["amulet", "ring"]},
}
const POP_SCALE := 1.3

var _character_id: String = ""
var _selected_item: String = ""    # stash item id
var _selected_slot: String = ""    # worn slot of the current character
var _filter: String = "all"
var _flash_slot: String = ""       # a slot that just received an item (pop animation)
var _tabs: HBoxContainer
var _doll: HBoxContainer
var _stage: DollStage
var _stats: HFlowContainer
var _stash: GridContainer
var _stash_panel: PanelContainer
var _stash_title: Label
var _filters: HBoxContainer
var _details: VBoxContainer
var _message: Label
var _figure: TextureRect
var _slot_tiles: Dictionary = {}   # slot -> ItemTile
var _stash_tiles: Array[ItemTile] = []
var _dragging: Dictionary = {}


func _build() -> void:
	_character_id = GameState.party.members[0].id
	var page := UIFactory.vbox(8)
	root.add_child(page)
	var top := UIFactory.hbox(12)
	page.add_child(top)
	var heading := SectionHeading.new()
	heading.setup("Equipment", false, false)
	top.add_child(heading)
	_tabs = UIFactory.hbox(8)
	top.add_child(_tabs)
	top.add_child(UIFactory.expander())
	var gold := GoldDisplay.new()
	top.add_child(gold)
	gold.setup(GameState.inventory.gold)
	var back := UIFactory.button("Back", true, Vector2(150, 52))
	back.name = "EquipmentBack"
	back.pressed.connect(_on_back)
	top.add_child(back)

	var body := UIFactory.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	# Left: the character on her stage between her slots, her bonuses underneath.
	var character_panel := UIFactory.panel(UITheme.compact_panel_style(0.32, Vector4(18, 12, 18, 12)))
	character_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_panel.size_flags_stretch_ratio = 1.15
	body.add_child(character_panel)
	var character_column := UIFactory.vbox(6)
	character_panel.add_child(character_column)
	_doll = UIFactory.hbox(10)
	_doll.alignment = BoxContainer.ALIGNMENT_CENTER
	_doll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_column.add_child(_doll)
	_stats = HFlowContainer.new()
	_stats.name = "EquipmentStats"
	_stats.add_theme_constant_override("h_separation", 6)
	_stats.add_theme_constant_override("v_separation", 4)
	character_column.add_child(_stats)
	# Right: the stash on top, the item card below.
	var side := UIFactory.vbox(10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(side)
	_stash_panel = UIFactory.panel(UITheme.compact_panel_style(0.32, Vector4(16, 10, 16, 10)))
	_stash_panel.name = "StashPanel"
	_stash_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Dropping a worn item anywhere on the stash panel takes it off.
	_stash_panel.set_drag_forwarding(Callable(), _can_drop_on_stash, _drop_on_stash)
	side.add_child(_stash_panel)
	var stash_column := UIFactory.vbox(6)
	_stash_panel.add_child(stash_column)
	var stash_head := UIFactory.hbox(8)
	stash_column.add_child(stash_head)
	_stash_title = UIFactory.label("Party stash", &"HeaderLabel")
	_stash_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT)
	stash_head.add_child(_stash_title)
	stash_head.add_child(UIFactory.expander())
	_filters = UIFactory.hbox(4)
	_filters.name = "StashFilters"
	stash_head.add_child(_filters)
	var scroll := UIFactory.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 96
	stash_column.add_child(scroll)
	_stash = GridContainer.new()
	_stash.name = "Stash"
	_stash.columns = 5
	_stash.add_theme_constant_override("h_separation", 8)
	_stash.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_stash)
	var details_panel := UIFactory.panel(UITheme.compact_panel_style(0.32, Vector4(16, 12, 16, 12)))
	side.add_child(details_panel)
	_details = UIFactory.vbox(4)
	_details.name = "ItemDetails"
	_details.custom_minimum_size = Vector2(0, 168)
	details_panel.add_child(_details)
	var bottom := UIFactory.hbox(12)
	page.add_child(bottom)
	_message = UIFactory.label("", &"DimLabel", true)
	_message.name = "EquipmentMessage"
	_message.add_theme_color_override("font_color", UITheme.GOLD)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_message)
	var hint := UIFactory.label("Drag items onto a slot or onto her to equip · drag a worn item to the stash to remove it · or tap and use the buttons", &"DimLabel")
	hint.name = "DragHint"
	hint.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL - 1)
	hint.add_theme_color_override("font_color", Color(UITheme.IVORY_DIM, 0.7))
	bottom.add_child(hint)
	resized.connect(_fit_columns)
	_refresh()


func _fit_columns() -> void:
	if _stash != null:
		var width := _stash.get_parent_control().size.x if _stash.get_parent_control() != null else 400.0
		_stash.columns = clampi(int((width + 8.0) / (ItemTile.SIZE.x + 8.0)), 3, 8)


func _member() -> PartyMember:
	return GameState.party.get_member(_character_id)


## Shows another character (tabs).
func select_character(character_id: String) -> void:
	_character_id = character_id
	_selected_slot = ""
	_refresh()


func _refresh() -> void:
	_build_tabs()
	_build_doll()
	_build_stats()
	_build_filters()
	_build_stash()
	_build_details()
	_fit_columns.call_deferred()


func _build_tabs() -> void:
	UIFactory.clear_children(_tabs)
	for member in GameState.party.members:
		var tab := UIFactory.button(member.definition.display_name, false, Vector2(150, 48))
		tab.name = "Tab_" + member.id
		tab.toggle_mode = true  # same toggle look as the specialization buttons: the shown character stays lit
		tab.theme_type_variation = &"ToggleButton"
		tab.button_pressed = member.id == _character_id
		tab.add_theme_color_override("font_color", member.definition.accent_color.lightened(0.3))
		var portrait := member.definition.get_portrait_texture()
		if portrait != null:
			tab.icon = portrait
			tab.expand_icon = true
			tab.add_theme_constant_override("icon_max_width", 30)
		tab.pressed.connect(select_character.bind(member.id))
		# Dropping a stash item on the other princess's tab equips it on her.
		var id := member.id
		tab.set_drag_forwarding(Callable(),
			func(_at: Vector2, data: Variant) -> bool: return _can_drop_on_member(data, id),
			func(_at: Vector2, data: Variant) -> void: _drop_on_member(data, id))
		_tabs.add_child(tab)


func _accent(member: PartyMember) -> Color:
	return member.specialization.get_accent(member.definition.accent_color) if member.specialization != null else member.definition.accent_color


func _build_doll() -> void:
	UIFactory.clear_children(_doll)
	_slot_tiles.clear()
	var member := _member()
	_doll.add_child(_slot_column(LEFT_SLOTS, member))
	var centre := UIFactory.vbox(2)
	centre.alignment = BoxContainer.ALIGNMENT_END
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage = DollStage.new()
	_stage.name = "DollStage"
	_stage.custom_minimum_size = Vector2(190, 300)
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.setup(_stage_texture(member), _accent(member))
	_stage.drop_check = _can_drop_on_member.bind(member.id)
	_stage.drop_handler = _drop_on_member.bind(member.id)
	_figure = _stage.figure()
	centre.add_child(_stage)
	var name_label := UIFactory.label("%s — %s" % [member.definition.display_name, member.specialization.display_name], &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT)
	name_label.add_theme_color_override("font_color", _accent(member).lightened(0.25))
	centre.add_child(name_label)
	var hp_row := UIFactory.hbox(6)
	hp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var bar := UIFactory.hp_bar(member.current_hp, member.max_hp)
	bar.custom_minimum_size = Vector2(150, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(bar)
	var hp := UIFactory.label("HP %d / %d" % [member.current_hp, member.max_hp], &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	hp.name = "EquipmentHp"
	hp.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	hp_row.add_child(hp)
	centre.add_child(hp_row)
	_doll.add_child(centre)
	_doll.add_child(_slot_column(RIGHT_SLOTS, member))


func _slot_column(slots: Array[String], member: PartyMember) -> VBoxContainer:
	var column := UIFactory.vbox(7)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	for slot in slots:
		var tile := ItemTile.create(str(member.equipment.get(slot, "")), slot, SLOT_TILE)
		tile.name = "Slot_" + slot
		tile.source = "slot"
		tile.character_id = member.id
		tile.pressed.connect(_on_slot.bind(slot))
		tile.drag_started.connect(_on_drag_started)
		tile.drop_check = _can_drop_on_slot.bind(slot)
		tile.drop_handler = _drop_on_slot.bind(slot)
		column.add_child(tile)
		_slot_tiles[slot] = tile
		if slot == _selected_slot:
			tile.set_selected.call_deferred(true)
		if slot == _flash_slot:
			_pop.call_deferred(tile)
	return column


## A slot that just received an item pops and flashes.
func _pop(tile: Control) -> void:
	if not is_instance_valid(tile) or SettingsStore.load_values().get("effects_quality", "full") == "off":
		return
	tile.pivot_offset = tile.size / 2.0
	tile.scale = Vector2.ONE * POP_SCALE
	tile.modulate = Color(1.6, 1.5, 1.2)
	var tween := tile.create_tween().set_parallel(true)
	tween.tween_property(tile, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(tile, "modulate", Color.WHITE, 0.4)
	_flash_slot = ""


func _build_stats() -> void:
	UIFactory.clear_children(_stats)
	var totals := Equipment.totals(_member())
	var any := false
	if int(totals["max_hp"]) != 0:
		_stats.add_child(_chip("%+d Max HP" % int(totals["max_hp"]), UITheme.CRIMSON.lightened(0.35), "health"))
		any = true
	for element: String in totals["damage"]:
		_stats.add_child(_chip("+%d%% %s damage" % [int(totals["damage"][element]), DamageTypes.display_name(element)], DamageTypes.color(element), "combat"))
		any = true
	for element: String in totals["resist"]:
		_stats.add_child(_chip("%s resistance %d%%" % [DamageTypes.display_name(element), int(totals["resist"][element])], DamageTypes.color(element), "block"))
		any = true
	for status_id: Variant in totals["immune"]:
		var status_def := DataRegistry.get_status(str(status_id))
		_stats.add_child(_chip("Immune to %s" % (status_def.display_name if status_def != null else str(status_id).capitalize()), UITheme.SILVER, "block"))
		any = true
	if not any:
		_stats.add_child(_stat_line("No bonuses yet: equip something to see it here.", UITheme.IVORY_DIM))


## A small pill: icon and text in the bonus's colour.
func _chip(text: String, color: Color, icon_name: String) -> Control:
	var chip := PanelContainer.new()
	var style := UITheme.box(Color(color.darkened(0.75), 0.85), Color(color, 0.75), 12, 1, 0)
	style.content_margin_left = 8
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)
	var row := UIFactory.hbox(4)
	chip.add_child(row)
	row.add_child(UIFactory.icon(icon_name, 14))
	var label := _stat_line(text, color.lightened(0.3))
	row.add_child(label)
	return chip


## The large figure on the stage. The full-size character art (two to three times the combat pose's
## resolution, so it stays sharp on big screens), unless her specialization has a look of its own
## (Ashveil and Venom Bianca), which only exists as combat poses.
func _stage_texture(member: PartyMember) -> Texture2D:
	var spec_id := member.specialization.id if member.specialization != null else ""
	var figure := AssetCatalog.figure(member.id)
	if figure != null and not CombatPresentation.has_variant(member.id, spec_id):
		return figure
	# A specialization look of her own: its HD "figure" picture (falls back to the idle pose).
	return CombatPresentation.character_state(member.id, "figure", spec_id)


func _stat_line(text: String, color: Color) -> Label:
	var label := UIFactory.label(text, &"DimLabel")
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", color)
	return label


func _build_filters() -> void:
	UIFactory.clear_children(_filters)
	for key: String in FILTERS:
		var button := UIFactory.button(str(FILTERS[key]["label"]), false, Vector2(0, 32))
		button.name = "Filter_" + key
		button.toggle_mode = true
		button.theme_type_variation = &"ToggleButton"
		button.button_pressed = key == _filter
		CastleUI.chip_style(button)  # filter chips: compact enamel, lit when selected
		button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL - 1)
		button.pressed.connect(func() -> void:
			_filter = key
			_refresh())
		_filters.add_child(button)


func _passes_filter(item_id: String) -> bool:
	var wanted: Array = FILTERS[_filter]["slots"]
	return wanted.is_empty() or wanted.has(str(Equipment.item(item_id).get("slot", "")))


## Stash order: best rarity first, then name; tile names keep the stash index (Stash_<index>).
func _sorted_stash_indices() -> Array[int]:
	var stash := GameState.inventory.equipment
	var indices: Array[int] = []
	for i in stash.size():
		if _passes_filter(stash[i]):
			indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		var ra := Equipment.RARITY_ORDER.find(str(Equipment.item(stash[a]).get("rarity", "common")))
		var rb := Equipment.RARITY_ORDER.find(str(Equipment.item(stash[b]).get("rarity", "common")))
		if ra != rb:
			return ra > rb
		return str(Equipment.item(stash[a]).get("name", "")) < str(Equipment.item(stash[b]).get("name", "")))
	return indices


func _build_stash() -> void:
	UIFactory.clear_children(_stash)
	_stash_tiles.clear()
	var stash := GameState.inventory.equipment
	if _selected_item != "" and not stash.has(_selected_item):
		_selected_item = ""
	_stash_title.text = "Party stash  (%d)" % stash.size()
	var shown := 0
	for i in _sorted_stash_indices():
		var tile := ItemTile.create(stash[i])
		tile.name = "Stash_%d" % i
		tile.source = "stash"
		tile.pressed.connect(_on_stash_item.bind(stash[i]))
		tile.drag_started.connect(_on_drag_started)
		tile.drop_check = _can_drop_on_stash
		tile.drop_handler = _drop_on_stash
		_stash.add_child(tile)
		_stash_tiles.append(tile)
		shown += 1
		if stash[i] == _selected_item and _selected_slot == "":
			tile.set_selected.call_deferred(true)
	# Empty sockets fill the grid so it reads as a bag, and take dropped (worn) items too.
	for i in maxi(0, STASH_MIN_CELLS - shown):
		var socket := ItemTile.create("")
		socket.name = "StashSocket_%d" % i
		socket.focus_mode = Control.FOCUS_NONE
		socket.drop_check = _can_drop_on_stash
		socket.drop_handler = _drop_on_stash
		socket.tooltip_text = ""
		_stash.add_child(socket)
		_stash_tiles.append(socket)
	if stash.is_empty():
		_message.text = _message.text if _message.text != "" else "The stash is empty. Monsters, elites, bosses and chests drop equipment."


func _build_details() -> void:
	UIFactory.clear_children(_details)
	var item_id := str(_member().equipment.get(_selected_slot, "")) if _selected_slot != "" else _selected_item
	if item_id == "":
		_details.add_child(_stat_line("Select an item in the stash or a worn slot to see it here.", UITheme.IVORY_DIM))
		return
	var def := Equipment.item(item_id)
	var rarity := str(def.get("rarity", "common"))
	var head := UIFactory.hbox(12)
	_details.add_child(head)
	var picture := ItemTile.create(item_id, "", Vector2(76, 76))
	picture.name = "DetailPicture"
	picture.focus_mode = Control.FOCUS_NONE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(picture)
	var titles := UIFactory.vbox(1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := UIFactory.label(str(def.get("name", item_id)), &"HeaderLabel")
	title.name = "DetailName"
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_DEFAULT + 1)
	title.add_theme_color_override("font_color", Equipment.rarity_color(rarity))
	titles.add_child(title)
	var wielder_def := DataRegistry.get_character(str(def.get("wielder", "")))
	var fitting := Equipment.slots_for(item_id)
	var slot_name := str(Equipment.SLOT_NAMES.get(fitting[0], "")) if not fitting.is_empty() else ""
	var only := (" · %s only" % wielder_def.display_name) if wielder_def != null else ""
	titles.add_child(_stat_line("%s %s%s" % [rarity.capitalize(), slot_name, only], UITheme.IVORY_DIM))
	for line in Equipment.stat_lines(item_id):
		var is_effect := line.begins_with("✦")
		var stat := _stat_line(line, EFFECT_COLOR if is_effect else UITheme.GOLD)
		if is_effect:  # item effects are sentences: wrap them inside the detail panel
			stat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			stat.custom_minimum_size.x = 260
		titles.add_child(stat)
	if _selected_slot == "" and not fitting.is_empty() and Equipment.can_equip(_member(), item_id) == "":
		_details.add_child(_comparison(item_id, fitting))
	if str(def.get("description", "")) != "":
		var flavour := _stat_line(str(def["description"]), Color(UITheme.IVORY_DIM, 0.85))
		flavour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_details.add_child(flavour)
	var actions := UIFactory.hbox(8)
	_details.add_child(actions)
	if _selected_slot != "":
		var unequip := UIFactory.button("Unequip", false, Vector2(160, 46))
		unequip.name = "UnequipButton"
		unequip.pressed.connect(_on_unequip)
		actions.add_child(unequip)
	else:
		for member in GameState.party.members:
			var equip := UIFactory.button("Equip on %s" % member.definition.display_name, member.id == _character_id, Vector2(190, 46))
			equip.name = "Equip_" + member.id
			var reason := Equipment.can_equip(member, item_id)
			equip.disabled = reason != ""
			equip.tooltip_text = reason
			equip.pressed.connect(_on_equip.bind(member.id))
			actions.add_child(equip)


## "Compared with what she wears": green gains, red losses, for the slot it would take.
func _comparison(item_id: String, fitting: Array[String]) -> Control:
	var member := _member()
	var slot := fitting[0]
	for candidate in fitting:
		if str(member.equipment.get(candidate, "")) == "":
			slot = candidate
			break
	var box := HFlowContainer.new()
	box.name = "Comparison"
	box.add_theme_constant_override("h_separation", 10)
	var worn := str(member.equipment.get(slot, ""))
	var lead := _stat_line("vs %s:" % (str(Equipment.item(worn).get("name", "")) if worn != "" else "empty slot"), UITheme.IVORY_DIM)
	box.add_child(lead)
	var deltas := Equipment.compare(member, item_id, slot)
	if deltas.is_empty():
		box.add_child(_stat_line("no change", UITheme.IVORY_DIM))
	for key: String in deltas:
		var delta := int(deltas[key])
		box.add_child(_stat_line(("▲ " if delta > 0 else "▼ ") + Equipment.describe_delta(key, delta), Color("7fe08a") if delta > 0 else Color("ff7a7a")))
	return box


# --- Tap / click ------------------------------------------------------------------------------

func _on_slot(slot: String) -> void:
	_selected_slot = slot if str(_member().equipment.get(slot, "")) != "" else ""
	_selected_item = ""
	if _selected_slot == "":
		_message.text = "%s slot is empty. Pick an item from the stash, or drag one here." % Equipment.SLOT_NAMES.get(slot, slot)
	_refresh()


func _on_stash_item(item_id: String) -> void:
	_selected_item = item_id
	_selected_slot = ""
	_message.text = ""
	_refresh()


func _on_equip(character_id: String) -> void:
	_equip(character_id, _selected_item, "")


func _on_unequip() -> void:
	_unequip(_selected_slot)


# --- Drag and drop ----------------------------------------------------------------------------

func _on_drag_started(data: Dictionary) -> void:
	_dragging = data
	var member := _member()
	for slot: String in _slot_tiles:
		var tile: ItemTile = _slot_tiles[slot]
		var ok := _can_drop_on_slot(data, slot)
		var is_source := str(data.get("from", "")) == "slot" and str(data.get("slot", "")) == slot
		if not is_source:
			tile.set_drop_state(ItemTile.DropState.VALID if ok else ItemTile.DropState.INVALID)
	if str(data.get("from", "")) == "slot":
		for tile in _stash_tiles:
			tile.set_drop_state(ItemTile.DropState.VALID)
	_stage.set_drop_state(_can_drop_on_member(data, member.id))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not _dragging.is_empty():
		_dragging = {}
		_clear_drop_states()


func _clear_drop_states() -> void:
	for tile: ItemTile in _slot_tiles.values():
		if is_instance_valid(tile):
			tile.set_drop_state(ItemTile.DropState.NONE)
	for tile in _stash_tiles:
		if is_instance_valid(tile):
			tile.set_drop_state(ItemTile.DropState.NONE)
	if is_instance_valid(_stage):
		_stage.set_drop_state(false)


func _is_item(data: Variant) -> bool:
	return data is Dictionary and str((data as Dictionary).get("type", "")) == ItemTile.DRAG_TYPE


func _can_drop_on_slot(data: Variant, slot: String) -> bool:
	if not _is_item(data):
		return false
	var item_id := str(data["item_id"])
	if not Equipment.slots_for(item_id).has(slot):
		return false
	if str(data["from"]) == "stash":
		return Equipment.can_equip(_member(), item_id) == ""
	return str(data["character_id"]) == _character_id and str(data["slot"]) != slot


func _drop_on_slot(data: Variant, slot: String) -> void:
	if str(data["from"]) == "stash":
		_equip(_character_id, str(data["item_id"]), slot)
	else:
		var error := Equipment.move_worn(_member(), str(data["slot"]), slot)
		_message.text = error if error != "" else "Moved %s." % Equipment.item(str(data["item_id"])).get("name", "")
		if error == "":
			_flash_slot = slot
			_selected_slot = ""
			GameState.save_game()
		_refresh()


func _can_drop_on_member(data: Variant, character_id: String) -> bool:
	return _is_item(data) and str(data["from"]) == "stash" and Equipment.can_equip(GameState.party.get_member(character_id), str(data["item_id"])) == ""


func _drop_on_member(data: Variant, character_id: String) -> void:
	_equip(character_id, str(data["item_id"]), "")


func _can_drop_on_stash(_at_position_or_data: Variant, data: Variant = null) -> bool:
	var payload: Variant = data if data != null else _at_position_or_data
	return _is_item(payload) and str(payload["from"]) == "slot"


func _drop_on_stash(_at_position_or_data: Variant, data: Variant = null) -> void:
	var payload: Variant = data if data != null else _at_position_or_data
	_unequip(str(payload["slot"]))


# --- Shared actions ---------------------------------------------------------------------------

func _equip(character_id: String, item_id: String, slot: String) -> void:
	var member := GameState.party.get_member(character_id)
	var fitting := Equipment.slots_for(item_id)
	var target := slot
	if target == "" and not fitting.is_empty():
		target = fitting[0]
		for candidate in fitting:
			if str(member.equipment.get(candidate, "")) == "":
				target = candidate
				break
	var error := Equipment.equip(member, GameState.inventory, item_id, slot)
	if error != "":
		_message.text = error
		return
	_message.text = "%s equipped %s." % [member.definition.display_name, Equipment.item(item_id).get("name", item_id)]
	_selected_item = ""
	_selected_slot = ""
	_character_id = character_id
	_flash_slot = target
	GameState.save_game()
	_refresh()


func _unequip(slot: String) -> void:
	var item_id := str(_member().equipment.get(slot, ""))
	if Equipment.unequip(_member(), GameState.inventory, slot):
		_message.text = "%s went back to the stash." % Equipment.item(item_id).get("name", item_id)
		GameState.save_game()
	_selected_slot = ""
	_refresh()


func _on_back() -> void:
	SceneRouter.go(SceneRouter.equipment_return)


func _backdrop() -> Dictionary:
	return current_room_backdrop()


func _backdrop_dim() -> float:
	return 0.72
