extends Node
## Windowed: the equipment screen's drag and drop with real mouse input (press, move, release go
## through Godot's GUI, exactly like a player's drag), the drop highlights, ring swaps, unequip by
## dropping on the stash, equipping by dropping on the character, the comparison card and filters.
##   godot --path . res://tests/ui/inventory_drag_test.tscn -- <screenshot_dir>

var _failures := 0
var _checks := 0
var _shot_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	GameState.save_path = "user://test_inventory_drag.json"
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
	return SceneRouter.current_screen.find_child(node_name, true, false) if SceneRouter.current_screen != null else null


func _stash_tile(item_id: String) -> ItemTile:
	return _find("Stash_%d" % GameState.inventory.equipment.find(item_id)) as ItemTile


## A real drag: press on `from`, move in steps (past the drag threshold), release on `to`.
## `capture` (optional) is awaited mid-drag, while the item is carried over the target.
func _drag(from: Control, to: Control, capture: Callable = Callable()) -> void:
	var start := from.get_global_rect().get_center()
	var end := to.get_global_rect().get_center()
	Input.warp_mouse(start)
	_mouse_button(start, true)
	await get_tree().process_frame
	var previous := start
	for i in range(1, 13):
		var point := start.lerp(end, i / 12.0)
		_motion(point, point - previous)
		previous = point
		await get_tree().process_frame
	await _wait(0.1)
	if capture.is_valid():
		await capture.call()
	_mouse_button(end, false)
	await _wait(0.35)


func _mouse_button(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(event)


## `relative` matters: Godot starts a drag once the accumulated movement passes its threshold.
func _motion(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	Input.warp_mouse(at)


func _run() -> void:
	GameState.reset_selection()
	GameState.select_specialization("chiara", "frost")
	GameState.select_specialization("bianca", "ashveil")
	GameState.create_party_from_selection()
	GameState.next_map_id = "enchanted_forest"
	GameState.begin_adventure()
	for id in ["rimeglass_staff", "stormweave_coat", "dawnsteel_blade", "chainmail_hauberk", "tidecaller_staff", "padded_gambeson"]:
		GameState.inventory.add_equipment(id)
	var rings := Equipment.all_items().filter(func(d: Dictionary) -> bool: return str(d.get("slot", "")) == "ring" and str(d.get("wielder", "")) in ["", "chiara"])
	var ring_id := str(rings[0]["id"]) if not rings.is_empty() else ""
	if ring_id != "":
		GameState.inventory.add_equipment(ring_id)
	SceneRouter.open_equipment(SceneRouter.Screen.MAP)
	await _wait(0.8)
	var chiara := GameState.party.get_member("chiara")
	await _shot("inv_01_screen")

	# 1. Drag the staff from the stash onto the weapon slot; mid-drag the slots light up.
	var weapon_slot := _find("Slot_weapon") as ItemTile
	var helmet_slot := _find("Slot_helmet") as ItemTile
	var staff := _stash_tile("rimeglass_staff")
	var mid := {}
	await _drag(staff, weapon_slot, func() -> void:
		mid["weapon"] = weapon_slot.drop_state()
		mid["helmet"] = helmet_slot.drop_state()
		await _shot("inv_02_dragging"))
	check(mid.get("weapon", -1) in [ItemTile.DropState.VALID, ItemTile.DropState.TARGET], "while carrying the staff, the weapon slot glows")
	check(mid.get("helmet", -1) == ItemTile.DropState.INVALID, "and the helmet slot dims")
	check(chiara.equipment.get("weapon") == "rimeglass_staff", "dropping it on the weapon slot equips it")
	check((_find("Slot_weapon") as ItemTile).drop_state() == ItemTile.DropState.NONE, "the highlights clear after the drop")
	await _shot("inv_03_equipped")

	# 2. Dropping a stash item onto the character equips it in the slot it fits.
	await _drag(_stash_tile("stormweave_coat"), _find("DollStage") as Control)
	check(chiara.equipment.get("chest") == "stormweave_coat", "dropping the coat on Chiara puts it on")
	check(chiara.max_hp == chiara.definition.max_hp + 4, "and her Max HP rises at once")

	# 3. An item she cannot use is refused: Bianca's blade on Chiara's weapon slot.
	await _drag(_stash_tile("dawnsteel_blade"), _find("Slot_weapon") as Control)
	check(chiara.equipment.get("weapon") == "rimeglass_staff" and GameState.inventory.equipment.has("dawnsteel_blade"), "a sword only Bianca can use is not taken")

	# 4. Rings move between the two ring slots.
	if ring_id != "":
		await _drag(_stash_tile(ring_id), _find("Slot_ring_1") as Control)
		check(chiara.equipment.get("ring_1") == ring_id, "a ring dropped on the first ring slot")
		await _drag(_find("Slot_ring_1") as Control, _find("Slot_ring_2") as Control)
		check(chiara.equipment.get("ring_2") == ring_id and not chiara.equipment.has("ring_1"), "dragging it to the other ring slot moves it")

	# 5. A worn item dropped on the stash goes back to it.
	await _drag(_find("Slot_chest") as Control, _find("StashPanel") as Control)
	check(not chiara.equipment.has("chest") and GameState.inventory.equipment.has("stormweave_coat"), "dropping the worn coat on the stash takes it off")

	# 6. The card compares with what she wears; filters narrow the stash.
	(_stash_tile("tidecaller_staff") as Button).pressed.emit()
	await _wait(0.2)
	var comparison := _find("Comparison")
	var texts: Array[String] = []
	if comparison != null:
		for label in comparison.find_children("*", "Label", true, false):
			texts.append((label as Label).text)
	check(comparison != null and " ".join(texts).contains("Rimeglass"), "the item card compares it with her staff (%s)" % " ".join(texts))
	await _shot("inv_04_compare")
	(_find("Filter_weapons") as Button).pressed.emit()
	await _wait(0.2)
	var shown := SceneRouter.current_screen.find_children("Stash_*", "ItemTile", true, false)
	check(not shown.is_empty() and shown.all(func(t: Node) -> bool: return str(Equipment.item((t as ItemTile).item_id).get("slot", "")) == "weapon"), "the Weapons filter shows only weapons (%d)" % shown.size())
	(_find("Filter_all") as Button).pressed.emit()
	await _wait(0.2)

	# 7. Saved at once.
	GameState.load_game()
	check(GameState.party.get_member("chiara").equipment.get("weapon") == "rimeglass_staff", "drag-and-drop changes are saved")
