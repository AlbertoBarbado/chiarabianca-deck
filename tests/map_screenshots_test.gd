extends Node
## Captures the illustrated map at key moments of the route (windowed run):
##   godot --path . [--resolution 844x390] res://tests/map_screenshots_test.tscn -- <screenshot_dir>
## Travels with MapProgress directly (rooms are covered by the UI walkthrough).

var _shot_dir := ""
var _tag := "map"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot_dir = args[0]
	if args.size() > 1:
		_tag = args[1]
	GameState.save_path = "user://test_map_shots_save.json"
	GameState.delete_save()
	add_child((load("res://scenes/main/main.tscn") as PackedScene).instantiate())
	await _wait(0.4)
	GameState.reset_selection()
	GameState.select_specialization("chiara", "fire")
	GameState.select_specialization("bianca", "holy")
	GameState.create_party_from_selection()
	GameState.begin_adventure()
	await _show("1_initial")
	await _real_click_check()
	GameState.map_progress.travel_to("training_yard")
	await _show("2_after_first_room")
	GameState.map_progress.travel_to("central_courtyard")
	await _show("3_branching_choices")
	GameState.map_progress.travel_to("royal_library")
	GameState.map_progress.travel_to("throne_approach")
	await _show("4_throne_and_exit")
	GameState.delete_save()
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _show(shot_name: String) -> void:
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.7)
	if _shot_dir != "" and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_shot_dir, _tag, shot_name])


## Regression: with the real map screen on top, a real mouse click on an available node must
## reach the node (a full-screen spacer once swallowed every click).
func _real_click_check() -> void:
	if DisplayServer.get_name() == "headless":
		return
	SceneRouter.go(SceneRouter.Screen.MAP)
	await _wait(0.5)
	var view: MapView = _find_map_view(SceneRouter.current_screen)
	var button := view.get_button("training_yard")
	# Input events use window pixels; the UI lives in the stretched design canvas.
	var position: Vector2 = get_viewport().get_final_transform() * button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _wait(0.1)
	var hovered := get_viewport().gui_get_hovered_control()
	print("  hovered at node: ", hovered, " path ", hovered.get_path() if hovered != null else "-", " mouse_filter ", hovered.mouse_filter if hovered != null else -1)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _wait(0.1)
	await _wait(0.5)
	var ok: bool = GameState.map_progress.current_node_id == "training_yard"
	print(("  ok   " if ok else "  FAIL "), "a real mouse click on a node of the map screen travels there")
	if not ok:
		get_tree().quit(1)
	SceneRouter.go(SceneRouter.Screen.MAP)
	GameState.map_progress.current_node_id = "royal_chambers"
	GameState.map_progress.visited_ids = ["royal_chambers"]


func _find_map_view(node: Node) -> MapView:
	if node is MapView:
		return node
	for child in node.get_children():
		var found := _find_map_view(child)
		if found != null:
			return found
	return null
