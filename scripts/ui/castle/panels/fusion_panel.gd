extends VBoxContainer
## Enchanter: card fusion (Fusion, data/fusion/recipes.json). Each recipe the Sister Bond has revealed
## shows its two input cards (one per sister, upgraded), the fusion card it makes, its requirements
## and cost. Fusing asks for confirmation and says which cards are consumed.

const CARD_SCALE := 0.6

var shell: Node
var _list: VBoxContainer


func setup(p_shell: Node) -> void:
	shell = p_shell
	add_theme_constant_override("separation", 10)
	add_child(UIFactory.label("Fusion joins one card of each sister into a twin card. The two input cards (upgraded copies) are consumed; each recipe can be crafted once.", &"DimLabel", true))
	var scroll := UIFactory.scroll()
	_list = UIFactory.vbox(10)
	_list.name = "Recipes"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	add_child(scroll)
	refresh()


func refresh() -> void:
	UIFactory.clear_children(_list)
	var campaign := GameState.campaign
	var known := Fusion.known_recipes(campaign)
	for recipe in known:
		_list.add_child(_recipe_panel(recipe))
	var hidden := Fusion.all_recipes().size() - known.size()
	if hidden > 0:
		var next := 0
		for recipe in Fusion.all_recipes():
			if not known.has(recipe):
				next = int(recipe.get("bond_level", 0)) if next == 0 else mini(next, int(recipe.get("bond_level", 0)))
		_list.add_child(UIFactory.label("%d more recipe%s will awaken as the sisters' bond grows (next at Bond level %d)." % [hidden, "" if hidden == 1 else "s", next], &"DimLabel", true))


func _recipe_panel(recipe: Dictionary) -> Control:
	var campaign := GameState.campaign
	var recipe_id := str(recipe["id"])
	var done := campaign.fusions_done.has(recipe_id)
	var reason := Fusion.can_fuse(campaign, recipe_id)
	var panel := CastleUI.card_panel(8, UITheme.GOLD if reason == "" else Color(0.45, 0.45, 0.5))
	panel.name = "Recipe_" + recipe_id
	var column := CastleUI.column_of(panel)
	var title := UIFactory.label(str(recipe["name"]) + ("  ✓ crafted" if done else ""), &"HeaderLabel", false)
	column.add_child(title)
	column.add_child(UIFactory.label(str(recipe.get("text", "")), &"", true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	for input: Dictionary in recipe["inputs"]:
		var box := UIFactory.vbox(2)
		var have := Fusion.input_copy(campaign, input) != null
		var view := CastleUI.card(DataRegistry.get_card(str(input["card_id"])), str(input["owner"]), int(input.get("min_upgrade", 0)), CARD_SCALE)
		view.modulate = Color.WHITE if have else Color(0.5, 0.5, 0.58)
		view.pressed.connect(func(_v: CardView) -> void: CastleUI.inspect_card(shell, DataRegistry.get_card(str(input["card_id"])), str(input["owner"]), int(input.get("min_upgrade", 0)), "Needed (upgraded)." if not have else "In the collection.", []))
		box.add_child(view)
		box.add_child(UIFactory.label("✓ owned" if have else "✗ needed", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
		flow.add_child(box)
		flow.add_child(UIFactory.label("+" if input != recipe["inputs"][-1] else "=", &"TitleLabel", false))
	var result: Dictionary = recipe["result"]
	var result_view := CastleUI.card(DataRegistry.get_card(str(result["card_id"])), str(result["owner"]), 0, CARD_SCALE * 1.15)
	result_view.name = "Result"
	result_view.pressed.connect(func(_v: CardView) -> void: CastleUI.inspect_card(shell, DataRegistry.get_card(str(result["card_id"])), str(result["owner"]), 0, "Fusion card for %s. One copy per deck." % DataRegistry.get_character(str(result["owner"])).display_name, []))
	flow.add_child(result_view)
	column.add_child(flow)
	var specs: Dictionary = recipe.get("specializations", {})
	var spec_names: Array[String] = []
	for character_id: String in specs:
		spec_names.append("%s: %s" % [DataRegistry.get_character(character_id).display_name, DataRegistry.get_specialization(str(specs[character_id])).display_name])
	var cost: Dictionary = recipe.get("cost", {})
	column.add_child(UIFactory.label("Needs %s · Bond %d · Cost %d gold, ✦ %d Essence" % [", ".join(spec_names), int(recipe.get("bond_level", 0)), int(cost.get("gold", 0)), int(cost.get("essence", 0))], &"DimLabel", true))
	var button := UIFactory.button("Fuse" if reason == "" else reason, reason == "", Vector2(0, 52))
	button.name = "Fuse"
	button.disabled = reason != ""
	button.pressed.connect(_confirm.bind(recipe))
	column.add_child(button)
	return panel


func _confirm(recipe: Dictionary) -> void:
	var names: Array[String] = []
	for input: Dictionary in recipe["inputs"]:
		names.append(DataRegistry.get_card(str(input["card_id"])).display_name + "+")
	var cost: Dictionary = recipe.get("cost", {})
	CastleUI.confirm(shell, "Fuse %s?" % str(recipe["name"]), "%s will be consumed. Cost: %d gold and ✦ %d Essence. The new card joins the collection." % [" and ".join(names), int(cost.get("gold", 0)), int(cost.get("essence", 0))], "Fuse", func() -> void:
		var outcome := Fusion.fuse(GameState.campaign, str(recipe["id"]))
		if not outcome["ok"]:
			shell.toast(str(outcome["error"]), false)
			return
		shell.changed()
		shell.toast("%s joins the collection!" % str(recipe["name"]))
		refresh())
