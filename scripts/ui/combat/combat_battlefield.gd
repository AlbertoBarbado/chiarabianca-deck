class_name CombatBattlefield
extends Control
## The battlefield: enemies on the LEFT, Chiara and Bianca on the RIGHT and a free CENTRE for
## projectiles, cut-ins and floating numbers. Views are created once per combatant and updated in
## place; positions are computed from this control's size, so any landscape window works.
## It never reads combat rules beyond the values it is given.

signal unit_pressed(unit_id: String)
## A valid card target is under the pointer (its id), or none any more ("").
signal target_hovered(unit_id: String)
## A heavy creature's attack landed (screen shake strength in pixels).
signal impact(strength: float)

const ENEMY_ZONE := Vector2(0.03, 0.48)   # share of the width (the group is centred in its zone)
const PARTY_ZONE := Vector2(0.58, 0.94)
const GAP := 22.0
const UNIT_WIDTH_PER_HEIGHT := 0.82     # slot width / sprite height (sprites are about 0.7 wide)
const ENEMY_MAX_WIDTH := 230.0
const PARTY_MAX_WIDTH := 230.0
const ART_HEIGHT_SHARE := 0.78             # sprite height as a share of the battlefield height
const MAX_ART_HEIGHT := 220.0              # about Slay-the-Spire scale at 720p
const GROUND_MARGIN := -12.0               # feet stand slightly below the battlefield rect: the empty strip above the hand
const TOP_ROOM := 62.0                     # space above the heads for the intent badge and the status counters
const MAX_PER_ROW := 3
const BACK_ROW_SCALE := 0.88               # back-row units are a little smaller (further away)
const BACK_ROW_RISE := 0.24                # back row feet are this share of a sprite height higher

var enemy_views: Dictionary = {}   # id -> CombatEnemyView
var party_views: Dictionary = {}   # id -> CombatCharacterView
var _enemy_order: Array[String] = []
var _party_order: Array[String] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = false


func setup(combat: CombatManager) -> void:
	UIFactory.clear_children(self)
	enemy_views.clear()
	party_views.clear()
	_enemy_order.clear()
	_party_order.clear()
	for enemy in combat.enemies:
		var view := CombatEnemyView.new()
		add_child(view)
		view.setup_enemy(enemy, _definition_id(enemy.id))
		view.pressed.connect(func(id: String) -> void: unit_pressed.emit(id))
		view.target_hover_changed.connect(func(id: String, on: bool) -> void: target_hovered.emit(id if on else ""))
		enemy_views[enemy.id] = view
		_enemy_order.append(enemy.id)
	for member in combat.party_combatants:
		var view := CombatCharacterView.new()
		add_child(view)
		view.setup_character(member)
		view.pressed.connect(func(id: String) -> void: unit_pressed.emit(id))
		party_views[member.id] = view
		_party_order.append(member.id)
	if not resized.is_connected(layout):
		resized.connect(layout)
	var index := 0
	for view in all_views():
		view.impact.connect(func(strength: float) -> void: impact.emit(strength))
		view.play_entrance(0.05 + index * 0.07)
		index += 1


## Backdrop light on every sprite (CombatPresentation.lighting).
func set_lighting(light: Dictionary) -> void:
	for view in all_views():
		view.set_lighting(light)


## Enemy ids look like "<definition>_<index>".
func _definition_id(enemy_id: String) -> String:
	var cut := enemy_id.rfind("_")
	return enemy_id.left(cut) if cut > 0 else enemy_id


func get_view(unit_id: String) -> CombatUnitView:
	if enemy_views.has(unit_id):
		return enemy_views[unit_id]
	return party_views.get(unit_id)


func all_views() -> Array[CombatUnitView]:
	var views: Array[CombatUnitView] = []
	for id in _enemy_order:
		views.append(enemy_views[id])
	for id in _party_order:
		views.append(party_views[id])
	return views


## Places every view. Call after the views' info cards changed height (the screen does so on refresh).
func layout() -> void:
	_layout_zone(_enemy_order, enemy_views, ENEMY_ZONE, ENEMY_MAX_WIDTH, true)
	_layout_zone(_party_order, party_views, PARTY_ZONE, PARTY_MAX_WIDTH, false)


## Up to 3 characters stand in one row; up to 6 enemies stand in one row (1-3) or two rows (4-6,
## the back row a little higher and drawn behind, its life bars in front). Every row uses the same
## sprite height; the feet of the front row stand on the ground line near the hand.
func _layout_zone(order: Array[String], views: Dictionary, zone: Vector2, max_width: float, rows_allowed: bool) -> void:
	var count := order.size()
	if count == 0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var rows := 2 if rows_allowed and count > MAX_PER_ROW else 1
	var front_count := ceili(count / float(rows))
	var back_count := count - front_count
	var zone_w := size.x * (zone.y - zone.x)
	var ground_y := size.y - GROUND_MARGIN
	# Every unit has its own height (size factor x the common base height) and its own width (that
	# height x the idle sprite's aspect). The slot is as wide as the widest unit; if the row does not
	# fit its zone, everything shrinks by the same factor.
	var vertical_room := (ground_y - TOP_ROOM) / (1.0 + (BACK_ROW_RISE if rows == 2 else 0.0))
	var base_h := minf(size.y * ART_HEIGHT_SHARE, MAX_ART_HEIGHT)
	var tallest := 0.0
	var widest := 0.0
	for id in order:
		var unit: CombatUnitView = views[id]
		tallest = maxf(tallest, base_h * unit.size_scale)
		widest = maxf(widest, base_h * unit.size_scale * clampf(unit.pose_aspect(), 0.5, 1.8))
	var slots := float(maxi(front_count, back_count))
	if rows == 2 and back_count == front_count:
		slots += 0.5  # the back row is shifted by half a slot
	var fit := minf(1.0, minf(vertical_room / maxf(1.0, tallest), ((zone_w - GAP * (slots - 1.0)) / slots) / maxf(1.0, widest)))
	var unit_w := maxf(widest * fit, 40.0)
	var centre_x := size.x * (zone.x + zone.y) / 2.0
	for i in count:
		var in_back := rows == 2 and i < back_count
		var row_count := back_count if in_back else front_count
		var index_in_row := i if in_back else i - back_count
		var total_w := unit_w * row_count + GAP * (row_count - 1)
		if rows == 2 and back_count == front_count:
			total_w += (unit_w + GAP) * 0.5  # keep the staggered group centred in its zone
		var shift := (unit_w + GAP) * 0.5 if in_back and back_count == front_count else 0.0
		var view: CombatUnitView = views[order[i]]
		var own_h := maxf(base_h * view.size_scale * fit * (BACK_ROW_SCALE if in_back else 1.0), 40.0)
		var unit_h := own_h + view.get_info_height() + (4.0 if view.get_info_height() > 0.0 else 0.0)
		var feet_y := ground_y - (tallest * fit * BACK_ROW_RISE if in_back else 0.0)
		view.set_back_row(in_back)
		view.layout_in(Rect2(centre_x - total_w / 2.0 + shift + index_in_row * (unit_w + GAP), feet_y - own_h, unit_w, unit_h))
