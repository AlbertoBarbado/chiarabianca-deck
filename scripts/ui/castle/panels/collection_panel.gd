extends VBoxContainer
## Card Collection: every card of a sister's playable specializations, fusion cards included, with
## how many copies she owns. Cards not found yet are dimmed and say where they come from.
## Filters: sister, specialization, owned / missing, type and rarity. Tap a card for details.

const CARD_SCALE := 0.74
const SHOW := [["all", "All"], ["owned", "Owned"], ["missing", "Not found"]]

var shell: Node
var sister := "chiara"
var spec_filter := "all"
var show_filter := "all"
var type_filter := "all"
var rarity_filter := "all"

var _summary: Label
var _filters: VBoxContainer
var _grid: HFlowContainer


func setup(p_shell: Node) -> void:
	shell = p_shell
	add_theme_constant_override("separation", 10)
	var top := UIFactory.hbox(12)
	top.add_child(CastleUI.chips([["chiara", "Chiara"], ["bianca", "Bianca"]], sister, func(id: String) -> void:
		sister = id
		spec_filter = "all"
		refresh(), "Sister", false))
	_summary = UIFactory.label("", &"DimLabel", true)
	_summary.name = "Summary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_summary)
	add_child(top)
	_filters = UIFactory.vbox(4)
	add_child(_filters)
	var scroll := CastleUI.flow_scroll(8)
	_grid = CastleUI.grid_of(scroll)
	_grid.name = "CollectionGrid"
	add_child(scroll)
	refresh()


## Every card that can belong to this sister: her playable specializations' starters, pools and
## epic pools, plus fusion cards she can receive.
static func cards_for(character_id: String) -> Array[String]:
	var result: Array[String] = []
	for spec in DataRegistry.get_specializations_for(character_id):
		if not spec.is_playable():
			continue
		for list: Array in [spec.starting_deck_card_ids, spec.card_pool, spec.epic_pool]:
			for card_id: String in list:
				if not result.has(card_id):
					result.append(card_id)
	for recipe in Fusion.all_recipes():
		var result_card: Dictionary = recipe["result"]
		if str(result_card["owner"]) == character_id and not result.has(str(result_card["card_id"])):
			result.append(str(result_card["card_id"]))
	return result


## Where a card comes from (shown for cards not found yet).
static func source_text(card_id: String) -> String:
	var def := DataRegistry.get_card(card_id)
	if def == null:
		return ""
	if def.rarity == "fusion":
		for recipe in Fusion.all_recipes():
			if str(recipe["result"]["card_id"]) == card_id:
				return "Fusion at the Enchanter: %s (Sister Bond %d)." % [str(recipe["name"]), int(recipe.get("bond_level", 0))]
	var spec := DataRegistry.get_specialization(def.specialization_id)
	var spec_name := spec.display_name if spec != null else def.specialization_id
	if spec != null and spec.starting_deck_card_ids.has(card_id):
		return "A %s starting card: learn %s at the Training Hall." % [spec_name, spec_name]
	if spec != null and spec.epic_pool.has(card_id):
		return "Epic: offered after a region's final fight to a %s sister." % spec_name
	return "Found on expeditions as a reward when a sister follows %s." % spec_name


func refresh() -> void:
	var campaign := GameState.campaign
	var all := cards_for(sister)
	var owned_total := all.filter(func(id: String) -> bool: return campaign.count_owned(sister, id) > 0).size()
	_summary.text = "%s owns %d of %d cards (%d copies in all)." % [DataRegistry.get_character(sister).display_name, owned_total, all.size(), campaign.collection(sister).size()]
	UIFactory.clear_children(_filters)
	var specs: Array = [["all", "All styles"]]
	for spec in DataRegistry.get_specializations_for(sister):
		if spec.is_playable():
			specs.append([spec.id, spec.display_name])
	specs.append(["fusion", "Fusion"])
	_filters.add_child(CastleUI.chips(specs, spec_filter, func(id: String) -> void:
		spec_filter = id
		refresh(), "Spec"))
	_filters.add_child(CastleUI.chips(SHOW, show_filter, func(id: String) -> void:
		show_filter = id
		refresh(), "Show"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	_filters.add_child(row)
	row.add_child(CastleUI.dropdown(preload("res://scripts/ui/castle/panels/deck_workshop_panel.gd").TYPES, type_filter, func(id: String) -> void:
		type_filter = id
		refresh.call_deferred(), "TypeFilter"))
	row.add_child(CastleUI.dropdown(preload("res://scripts/ui/castle/panels/deck_workshop_panel.gd").RARITIES, rarity_filter, func(id: String) -> void:
		rarity_filter = id
		refresh.call_deferred(), "RarityFilter"))
	UIFactory.clear_children(_grid)
	for card_id in all:
		var def := DataRegistry.get_card(card_id)
		var count := campaign.count_owned(sister, card_id)
		if spec_filter == "fusion" and def.rarity != "fusion" or spec_filter != "all" and spec_filter != "fusion" and (def.specialization_id != spec_filter or def.rarity == "fusion"):
			continue
		if show_filter == "owned" and count == 0 or show_filter == "missing" and count > 0:
			continue
		if type_filter != "all" and def.card_type != type_filter or rarity_filter != "all" and def.rarity != rarity_filter:
			continue
		var box := UIFactory.vbox(2)
		box.name = "Card_" + card_id
		var best := 0
		for owned in campaign.collection(sister):
			if owned.card_id == card_id:
				best = maxi(best, owned.upgrade_level)
		var view := CastleUI.card(def, sister, best, CARD_SCALE)
		view.pressed.connect(func(_v: CardView) -> void: _inspect(card_id, count, best))
		box.add_child(view)
		if count == 0:
			# Not found yet: the face is dimmed and a lock badge sits on the art (tap for where it comes from).
			# A dark veil over the face (CardView manages its own tint) and a small lock on the art.
			var veil := ColorRect.new()
			veil.name = "Veil"
			veil.color = Color(UITheme.NAVY_DEEP, 0.62)
			veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
			UIFactory.full_rect(veil)
			view.add_child(veil)
			CastleUI.badge_on(view, "🔒", UITheme.IVORY_DIM, true).tooltip_text = "Not found yet"
		else:
			CastleUI.badge_on(view, "×%d" % count, UITheme.GOLD)
		_grid.add_child(box)


func _inspect(card_id: String, count: int, best: int) -> void:
	var campaign := GameState.campaign
	var upgraded := 0
	for owned in campaign.collection(sister):
		if owned.card_id == card_id and owned.upgrade_level > 0:
			upgraded += 1
	var info := ("Owned: %d (%d upgraded)." % [count, upgraded]) if count > 0 else source_text(card_id)
	var tags := CastleUI.card_tags(DataRegistry.get_card(card_id))
	if not tags.is_empty():
		info += "\nWorks with: " + ", ".join(tags.map(func(t: String) -> String: return DataRegistry.get_status(t).display_name if DataRegistry.get_status(t) != null else t.capitalize()))
	CastleUI.inspect_card(shell, DataRegistry.get_card(card_id), sister, best, info, [])
