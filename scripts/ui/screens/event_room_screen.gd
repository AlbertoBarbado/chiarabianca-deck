extends ScreenBase
## Event room: shows a data-driven event, lists each choice with its consequences and applies the
## chosen outcome exactly once. Rooms with an "event_pool" roll their event when first entered; the
## rolled event, the choice and the outcome are kept in the saved room state, so reloading neither
## rerolls the event nor grants anything twice. Logic lives in EventResolver.

var _event: Dictionary = {}
var _column: VBoxContainer


func _build() -> void:
	var node := GameState.get_current_node()
	var event_id := node.event_id
	if GameState.room_matches(node.id, "event") and str(GameState.room_state.get("event_id", "")) != "":
		event_id = str(GameState.room_state["event_id"])  # Resumed: same event as before.
	elif node.event_pool != "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		event_id = EventResolver.pick_from_pool(node.event_pool, GameState.run_flags.get("seen_events", []), rng)
	if GameState.room_matches(node.id, "event") and str(GameState.room_state.get("event_id", "")) == "":
		GameState.update_room({"event_id": event_id})
	_event = DataRegistry.get_event(event_id)
	var center := CenterContainer.new()
	root.add_child(center)
	var panel := UIFactory.panel()
	panel.custom_minimum_size.x = 780
	center.add_child(panel)
	_column = UIFactory.vbox(12)
	panel.add_child(_column)
	var heading := SectionHeading.new()
	heading.setup(str(_event.get("title", node.display_name)), true)
	_column.add_child(heading)
	for paragraph in _event.get("paragraphs", []):
		_column.add_child(UIFactory.label(str(paragraph), &"", true))
	if bool(GameState.room_state.get("resolved", false)) and GameState.room_matches(node.id, "event"):
		_show_outcome(str(GameState.room_state.get("outcome", "")))
		return
	var choices: Array = _event.get("choices", [{"text": "Continue", "effects": []}])
	for i in choices.size():
		_column.add_child(_make_choice(choices[i], i))


## A choice button with its consequences spelled out underneath; unavailable choices say why.
func _make_choice(choice: Dictionary, index: int) -> Control:
	var blocked := EventResolver.blocked_reason(choice, GameState.inventory)
	var consequence := str(choice.get("result", ""))
	if blocked != "":
		consequence += ("  " if consequence != "" else "") + "(" + blocked + ")"
	var button := ChoiceCard.create(str(choice.get("text", "Continue")), consequence, _choice_icon(choice))
	button.name = "EventChoice%d" % index
	button.disabled = blocked != ""
	button.pressed.connect(_on_choice.bind(choice, index))
	return button


## Emblem that hints at what a choice does (fight, reward, heal, gold, risk).
func _choice_icon(choice: Dictionary) -> String:
	var types: Array = []
	for effect: Dictionary in choice.get("effects", []):
		types.append(str(effect.get("type", "")))
	if types.has("start_combat"):
		return "icons/icon_combat"
	if types.has("card_reward"):
		return "icons/icon_rune"
	if types.has("gain_relic"):
		return "icons/icon_star"
	if types.has("heal_party") or types.has("heal_party_fraction"):
		return "icons/icon_heart"
	if types.has("gain_item"):
		return "icons/icon_potion"
	if types.has("gain_gold"):
		return "icons/icon_gold"
	if types.has("damage_party"):
		return "icons/icon_flame"
	return "icons/icon_back"


func _on_choice(choice: Dictionary, index: int) -> void:
	var node := GameState.get_current_node()
	if bool(GameState.room_state.get("resolved", false)) or EventResolver.blocked_reason(choice, GameState.inventory) != "":
		return
	var result := EventResolver.apply(choice.get("effects", []), GameState.party, GameState.inventory)
	var outcome := "\n".join(result["log"] as Array[String])
	GameState.mark_event_seen(str(_event.get("id", "")))
	var patch := {"resolved": true, "choice": index, "outcome": outcome}
	if str(result["encounter_id"]) != "":
		# The event turns into a fight: the combat screen reads the encounter from the room state.
		patch["encounter_id"] = str(result["encounter_id"])
		patch["phase"] = "fight"
		GameState.update_room(patch)
		SceneRouter.go(SceneRouter.Screen.COMBAT)
		return
	if bool(result["card_reward"]):
		GameState.start_card_reward(patch)  # Saves the outcome together with the rolled reward.
		SceneRouter.go(SceneRouter.Screen.REWARD)
		return
	if GameState.room_matches(node.id, "event"):
		GameState.update_room(patch)  # Saved now: the outcome can never be applied twice.
	_show_outcome(outcome)


func _show_outcome(outcome: String) -> void:
	for child in _column.get_children():
		if child is Button:
			child.queue_free()
	if outcome != "":
		var result_label := UIFactory.label(outcome, &"", true)
		result_label.name = "EventOutcome"
		result_label.add_theme_color_override("font_color", UITheme.GOLD)
		_column.add_child(result_label)
	var leave := UIFactory.button("Continue", true, Vector2(0, 56))
	leave.name = "EventContinue"
	leave.pressed.connect(func() -> void: SceneRouter.go(SceneRouter.Screen.MAP))  # The map saves the finished room.
	_column.add_child(leave)


func _backdrop() -> Dictionary:
	return current_room_backdrop()
