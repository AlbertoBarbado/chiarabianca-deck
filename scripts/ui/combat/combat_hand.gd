class_name CombatHand
extends Control
## The player's hand along the bottom of the battlefield. Reuses CardView for every card.
##
## Layout: the cards fan out in a gentle arc (a slight rotation per card), overlapping when the hand
## is large; every card stays visible. Hovering pops a card up, straight and enlarged, in front of
## the others; the selected card stays raised with a gold glow; playable cards glow softly.
## Motion (skipped when effects are Off):
##   draw     - new cards fly in from the draw pile (bottom left), staggered
##   play     - a played card rises toward its target with a flash, then sweeps into the discard
##              pile, or burns away when it exhausts
##   discard  - at the end of the turn the hand sweeps off to the discard pile (bottom right)
## Pure layout and input forwarding: card rules stay in CombatManager.

signal card_pressed(card: CardInstance)
signal card_hovered(card: CardInstance)  # null when the pointer leaves the hand

const CARD_GAP := 10.0
const HOVER_RAISE := 56.0
const SELECT_RAISE := 40.0
const HOVER_SCALE := 1.22
const MOVE_TIME := 0.12
const HOVER_TIME := 0.16
const ARC := 0.35  # extra drop (px) per card away from the middle, for a gentle fan
const FAN_DEGREES := 2.6  # rotation per card away from the middle
const MAX_FAN_DEGREES := 9.0
const DRAW_TIME := 0.32
const DRAW_STAGGER := 0.06
const PLAY_RISE_TIME := 0.15
const PLAY_HOLD := 0.1
const PLAY_OUT_TIME := 0.24
const EXHAUST_TIME := 0.5
const DISCARD_TIME := 0.3
const DISCARD_STAGGER := 0.04

var _views: Dictionary = {}  # CardInstance -> CardView
var _order: Array[CardInstance] = []
var _hovered: CardInstance = null
var _selected: CardInstance = null
var _armed: CardInstance = null  # touch: first tap enlarges, second tap plays
var _played: Dictionary = {}  # CardInstance -> target point (local) of a card just played
var _discarding := false
var _first_fill := true
## Optional: returns true while new cards must wait at the deck (the enemy phase is still playing out).
var draw_hold: Callable


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	resized.connect(func() -> void: layout(false))


func get_view(card: CardInstance) -> CardView:
	return _views.get(card)


func card_count() -> int:
	return _order.size()


## Scale applied to every card so the hand fits this control's height.
func base_scale() -> float:
	return clampf((size.y - HOVER_RAISE - 6.0) / CardView.CARD_SIZE.y, 0.6, 1.0)


func _effects_on() -> bool:
	return is_inside_tree() and SettingsStore.load_values().get("effects_quality", "full") != "off"


## The screen calls this right before a card is played, with the point (global) it flies toward.
func mark_played(card: CardInstance, target_global: Vector2) -> void:
	_played[card] = target_global - global_position


## The screen calls this right before the turn ends: the cards that leave now are discarded.
func begin_discard() -> void:
	_discarding = true


## cards: the current hand in order; playable(card) -> bool; selected may be null.
## `preview` (optional): card -> CardEffects.damage_preview entries, shown on the card's text.
func set_cards(cards: Array[CardInstance], playable: Callable, selected: CardInstance, armed: CardInstance = null, preview: Callable = Callable()) -> void:
	_selected = selected
	_armed = armed
	var discard_index := 0
	for card: CardInstance in _views.keys():
		if not cards.has(card):
			var leaving: CardView = _views[card]
			_views.erase(card)
			if _hovered == card:
				_hovered = null
			if _played.has(card):
				_animate_play(leaving, card, _played[card])
				_played.erase(card)
			elif _discarding:
				_animate_discard(leaving, discard_index)
				discard_index += 1
			else:
				_animate_vanish(leaving)
	_discarding = false
	_order = cards.duplicate()
	var new_index := 0
	for card in cards:
		if not _views.has(card):
			var view := CardView.new()
			view.show_instance(card)
			view.show_playable_glow = true
			view.mouse_entered.connect(_on_hover.bind(card))
			view.mouse_exited.connect(_on_unhover.bind(card))
			view.pressed.connect(func(_v: CardView) -> void: card_pressed.emit(card))
			add_child(view)
			_views[card] = view
			_start_draw(view, new_index)
			new_index += 1
		var card_view: CardView = _views[card]
		card_view.damage_preview = preview.call(card) if preview.is_valid() else []
		card_view.show_instance(card)  # Refresh cost / text (upgrades, cost changes).
		card_view.show_playable_glow = true
		card_view.set_playable(playable.call(card))
		card_view.set_selected(card == selected or card == armed)
		card_view.set_hovered(card == _hovered)
	layout(false if new_index == 0 else true)
	_settle_sizes.call_deferred()
	_first_fill = false


## Cards wrap text, so their minimum height settles one frame after creation; pin the size again then.
func _settle_sizes() -> void:
	for view: CardView in _views.values():
		view.reset_size()
		view.size = CardView.CARD_SIZE
	layout(false)


## Where a card sits in the current hover / selection state: the point under its bottom centre
## (local coordinates), its scale, rotation (radians) and draw order. Cards scale and turn about
## their bottom centre.
func target_transform(index: int) -> Dictionary:
	var count := _order.size()
	var s := base_scale()
	var card_w := CardView.CARD_SIZE.x * s
	var spacing := card_w + CARD_GAP
	if count > 1:
		spacing = minf(spacing, (size.x - card_w - 8.0) / (count - 1))
	var total := card_w + spacing * (count - 1)
	var center_x := (size.x - total) / 2.0 + spacing * index + card_w / 2.0
	var middle := (count - 1) / 2.0
	var drop := (index - middle) * (index - middle) * ARC * 0.5
	var bottom_y := size.y - 4.0 + drop
	var card := _order[index]
	var scale_factor := s
	var rotation := deg_to_rad(clampf((index - middle) * FAN_DEGREES, -MAX_FAN_DEGREES, MAX_FAN_DEGREES))
	var z := index
	if card == _hovered or card == _armed:
		scale_factor = s * HOVER_SCALE
		bottom_y -= HOVER_RAISE
		var half := card_w * HOVER_SCALE / 2.0
		center_x = clampf(center_x, half, maxf(half, size.x - half))  # an enlarged end card stays on screen
		rotation = 0.0
		z = 100
	elif card == _selected:
		bottom_y -= SELECT_RAISE
		rotation = 0.0
		z = 50
	return {"bottom_center": Vector2(center_x, bottom_y), "scale": scale_factor, "rotation": rotation, "z": z}


func layout(animate: bool = true) -> void:
	var smooth: bool = animate and _effects_on()
	for i in _order.size():
		var view: CardView = _views[_order[i]]
		if view.has_meta("drawing"):
			continue  # still flying in from the draw pile; it lands on its slot by itself
		var target := target_transform(i)
		var target_scale := Vector2.ONE * float(target["scale"])
		view.z_index = int(target["z"])
		view.reset_size()  # drop any stale height, then pin the card to its design size
		view.size = CardView.CARD_SIZE
		view.pivot_offset = Vector2(CardView.CARD_SIZE.x / 2.0, CardView.CARD_SIZE.y)
		var top_left: Vector2 = (target["bottom_center"] as Vector2) - view.pivot_offset
		# A newer layout always wins: stop the card's previous slide, or it would finish later and
		# put the card back where an older state wanted it (e.g. un-hover then select at once).
		# has_meta first: get_meta with a null default still logs an error when the key is missing.
		var running: Variant = view.get_meta("layout_tween") if view.has_meta("layout_tween") else null
		if running is Tween and (running as Tween).is_valid():
			(running as Tween).kill()
		if smooth:
			var popping := _order[i] == _hovered or _order[i] == _armed
			var tween := view.create_tween().set_parallel(true)
			view.set_meta("layout_tween", tween)
			var trans := Tween.TRANS_BACK if popping else Tween.TRANS_SINE
			var time := HOVER_TIME if popping else MOVE_TIME
			tween.tween_property(view, "position", top_left, time).set_trans(trans).set_ease(Tween.EASE_OUT)
			tween.tween_property(view, "scale", target_scale, time).set_trans(trans).set_ease(Tween.EASE_OUT)
			tween.tween_property(view, "rotation", float(target["rotation"]), time).set_trans(Tween.TRANS_SINE)
		else:
			view.position = top_left
			view.scale = target_scale
			view.rotation = float(target["rotation"])


func set_hovered(card: CardInstance) -> void:
	if card == _hovered:
		return
	var previous := _hovered
	_hovered = card
	for c: CardInstance in [previous, card]:
		if c != null and _views.has(c):
			(_views[c] as CardView).set_hovered(c == _hovered)
	card_hovered.emit(card)
	layout(true)


func _on_hover(card: CardInstance) -> void:
	set_hovered(card)


func _on_unhover(card: CardInstance) -> void:
	if _hovered == card:
		set_hovered(null)


# --- Motion ------------------------------------------------------------------------------------

## A newly drawn card starts small and turned at the draw pile and flies to its slot.
func _start_draw(view: CardView, stagger_index: int) -> void:
	if not _effects_on():
		return
	view.size = CardView.CARD_SIZE
	view.pivot_offset = Vector2(CardView.CARD_SIZE.x / 2.0, CardView.CARD_SIZE.y)
	view.position = Vector2(-CardView.CARD_SIZE.x * 0.6, size.y - CardView.CARD_SIZE.y * 0.2)
	view.scale = Vector2.ONE * base_scale() * 0.4
	view.rotation = deg_to_rad(-24.0)
	view.modulate.a = 0.0
	view.set_meta("drawing", true)
	var delay := stagger_index * DRAW_STAGGER
	var tween := view.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(_try_fly.bind(view, delay))


## New cards wait at the deck while the enemies are still acting, then fly in staggered.
func _try_fly(view: CardView, stagger: float) -> void:
	if not is_instance_valid(view):
		return
	if draw_hold.is_valid() and bool(draw_hold.call()):
		view.create_tween().tween_callback(_try_fly.bind(view, stagger)).set_delay(0.1 + stagger * 0.0)
		return
	_fly_to_slot(view)


func _fly_to_slot(view: CardView) -> void:
	if not is_instance_valid(view):
		return
	var index := -1
	for i in _order.size():
		if _views.get(_order[i]) == view:
			index = i
	view.remove_meta("drawing")
	if index < 0:
		return
	var target := target_transform(index)
	view.z_index = int(target["z"])
	var top_left: Vector2 = (target["bottom_center"] as Vector2) - view.pivot_offset
	var tween := view.create_tween().set_parallel(true)
	tween.tween_property(view, "position", top_left, DRAW_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "scale", Vector2.ONE * float(target["scale"]), DRAW_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "rotation", float(target["rotation"]), DRAW_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "modulate:a", 1.0, DRAW_TIME * 0.5)
	# The slot was computed when the flight began; if the hand resized meanwhile (an intro overlay,
	# a window change), settle every card on its current slot once it lands.
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(self):
			layout(true))


## Played: rise toward the target, flash gold, then sweep into the discard pile (or burn away).
func _animate_play(view: CardView, card: CardInstance, target: Vector2) -> void:
	if not _effects_on():
		view.queue_free()
		return
	_detach(view)
	view.set_selected(true)
	# The target is the bottom-centre point of the card in the gap between the two sides.
	var rise_to := target + Vector2(0.0, CardView.CARD_SIZE.y * base_scale() * 0.5)
	var tween := view.create_tween()
	tween.set_parallel(true)
	tween.tween_property(view, "position", rise_to - view.pivot_offset, PLAY_RISE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "scale", Vector2.ONE * base_scale() * 0.95, PLAY_RISE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "rotation", 0.0, PLAY_RISE_TIME)
	tween.chain().tween_interval(PLAY_HOLD)
	if card.definition.exhausts:
		tween.chain().tween_method(view.set_dissolve, 0.0, 1.0, EXHAUST_TIME)
		tween.parallel().tween_property(view, "modulate:a", 0.0, EXHAUST_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(view, "position:y", rise_to.y - view.pivot_offset.y - 30.0, EXHAUST_TIME)
	else:
		var pile := _discard_point()
		tween.chain().tween_property(view, "position", pile - view.pivot_offset, PLAY_OUT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(view, "scale", Vector2.ONE * base_scale() * 0.3, PLAY_OUT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(view, "rotation", deg_to_rad(28.0), PLAY_OUT_TIME)
		tween.parallel().tween_property(view, "modulate:a", 0.0, PLAY_OUT_TIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(view.queue_free)


## End of turn: the card sweeps off to the discard pile.
func _animate_discard(view: CardView, index: int) -> void:
	if not _effects_on():
		view.queue_free()
		return
	_detach(view)
	var pile := _discard_point()
	var tween := view.create_tween()
	tween.tween_interval(index * DISCARD_STAGGER)
	tween.set_parallel(true)
	tween.chain().tween_property(view, "position", pile - view.pivot_offset, DISCARD_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(view, "scale", Vector2.ONE * base_scale() * 0.3, DISCARD_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(view, "rotation", deg_to_rad(32.0), DISCARD_TIME)
	tween.parallel().tween_property(view, "modulate:a", 0.0, DISCARD_TIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(view.queue_free)


func _animate_vanish(view: CardView) -> void:
	if not _effects_on():
		view.queue_free()
		return
	_detach(view)
	var tween := view.create_tween()
	tween.tween_property(view, "modulate:a", 0.0, 0.15)
	tween.tween_callback(view.queue_free)


## A leaving card no longer takes input or hover and draws above the hand.
func _detach(view: CardView) -> void:
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = 200
	for connection in view.mouse_entered.get_connections():
		view.mouse_entered.disconnect(connection["callable"])
	for connection in view.mouse_exited.get_connections():
		view.mouse_exited.disconnect(connection["callable"])
	view.set_hovered(false)


func _discard_point() -> Vector2:
	return Vector2(size.x + CardView.CARD_SIZE.x * 0.3, size.y + 10.0)
