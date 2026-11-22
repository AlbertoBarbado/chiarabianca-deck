class_name CombatAnimationController
extends Node
## Turns CombatManager.visual_event signals (emitted after gameplay has resolved) into battlefield
## poses and attack cut-ins: attackers swing or cast, targets flinch or guard, enemies strike the
## party. Presentation only. Events are staggered with timers, never awaited by the rules, so a
## disabled or slow animation cannot change any outcome. Effects quality: Full = poses + cut-ins,
## Reduced = poses only, Off = nothing.

const ENEMY_STRIKE_SECONDS := 0.6
const HIT_DELAY := 0.25
const STAGGER := 0.22
const CUTIN_DEDUPE_MSEC := 600
const CUTIN_MAX_WIDTH_SHARE := 0.16
const CUTIN_MAX_HEIGHT_SHARE := 0.28  # cut-ins never cover the battlefield units

signal phase_changed(enemy_phase: bool)

var _combat: CombatManager
var _battlefield: CombatBattlefield
var _cutin_layer: Control
var _enemy_phase_until_msec: int = 0
var _last_cutin_key: String = ""
var _last_cutin_msec: int = -10000
var _enemy_events: int = 0
var quality_name: String = "full"
var poses_played: int = 0
var cutins_shown: int = 0


func setup(combat: CombatManager, battlefield: CombatBattlefield, cutin_layer: Control, quality_override: String = "") -> void:
	_combat = combat
	_battlefield = battlefield
	_cutin_layer = cutin_layer
	quality_name = quality_override if quality_override != "" else str(SettingsStore.load_values().get("effects_quality", "full"))
	if not combat.visual_event.is_connected(handle_event):
		combat.visual_event.connect(handle_event)


func is_enemy_phase() -> bool:
	return Time.get_ticks_msec() < _enemy_phase_until_msec


func handle_event(event: Dictionary) -> void:
	if quality_name == "off":
		return
	var kind := str(event.get("kind", ""))
	var targets: Array = event.get("target_ids", [])
	var source_id := str(event.get("source_id", ""))
	match kind:
		"enemy_attack":
			if not is_enemy_phase():
				_enemy_events = 0  # a new enemy phase starts its own stagger
			_enemy_events += 1
			var delay := (_enemy_events - 1) * (ENEMY_STRIKE_SECONDS + 0.1)
			_enemy_phase_until_msec = maxi(_enemy_phase_until_msec, Time.get_ticks_msec() + int((delay + ENEMY_STRIKE_SECONDS + 0.5) * 1000.0))
			_pose(source_id, "attack", ENEMY_STRIKE_SECONDS, delay)
			for target_id: String in targets:
				_pose(target_id, "hit", 0.5, delay + HIT_DELAY)
		"enemy_defend":
			_pose(source_id, "block", 0.6, 0.0)
		"damage":
			_pose(source_id, "attack", 0.5, 0.0)
			for target_id: String in targets:
				_pose(target_id, "hit", 0.45, STAGGER)
			_maybe_cutin(event)
		"block":
			for target_id: String in targets:
				_pose(target_id, "block", 0.55, 0.0)
		"apply_status", "heal", "draw", "gain_energy", "power":
			_pose(source_id, "cast", 0.5, 0.0)
			if kind == "apply_status":
				_maybe_cutin(event)
		"status_tick":
			for target_id: String in targets:
				_pose(target_id, "hit", 0.35, 0.0)
		"frozen":
			_pose(source_id, "block", 0.8, 0.0)
	phase_changed.emit(is_enemy_phase())


func _pose(unit_id: String, state: String, seconds: float, delay: float) -> void:
	var view := _battlefield.get_view(unit_id) if _battlefield != null else null
	if view == null:
		return
	poses_played += 1
	if delay <= 0.0 or not is_inside_tree():
		view.play_state(state, seconds)
		return
	# A bound method (not a lambda) so the connection simply drops if the view is freed meanwhile.
	get_tree().create_timer(delay).timeout.connect(view.play_state.bind(state, seconds))


## Tiered attack artwork: only cards with an explicit tier of 2 or more in the presentation data,
## once per card play (multi-hit cards announce several events).
func _maybe_cutin(event: Dictionary) -> void:
	if quality_name != "full" or _cutin_layer == null:
		return
	var card_id := str(event.get("card_id", ""))
	var cutin := CombatPresentation.cutin_for_card(card_id, str(event.get("specialization_id", "")))
	if cutin.is_empty():
		return
	var now := Time.get_ticks_msec()
	if card_id == _last_cutin_key and now - _last_cutin_msec < CUTIN_DEDUPE_MSEC:
		return
	_last_cutin_key = card_id
	_last_cutin_msec = now
	show_cutin(cutin)


## Framed cut-in in the centre of the battlefield; fades out and frees itself.
func show_cutin(cutin: Dictionary) -> Control:
	var texture: Texture2D = cutin["texture"]
	var max_height := _cutin_layer.size.y * CUTIN_MAX_HEIGHT_SHARE
	var fit := minf(minf(float(cutin["width"]), _cutin_layer.size.x * CUTIN_MAX_WIDTH_SHARE) / texture.get_width(), max_height / texture.get_height())
	var width := texture.get_width() * fit
	var height := texture.get_height() * fit
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UITheme.card_frame_style(Color(1.3, 1.2, 0.9), 0.4, Vector4(10, 10, 10, 10)))
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.custom_minimum_size = Vector2(width, height)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	_cutin_layer.add_child(frame)
	frame.size = frame.get_combined_minimum_size()
	frame.position = Vector2((_cutin_layer.size.x - frame.size.x) / 2.0, maxf(8.0, _cutin_layer.size.y * 0.08))
	frame.modulate.a = 0.0
	frame.pivot_offset = frame.size / 2.0
	frame.scale = Vector2(0.92, 0.92)
	var seconds := float(cutin["seconds"])
	var tween := frame.create_tween()
	tween.set_parallel(true)
	tween.tween_property(frame, "modulate:a", 1.0, 0.12)
	tween.tween_property(frame, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(seconds)
	tween.chain().tween_property(frame, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(frame.queue_free)
	cutins_shown += 1
	return frame
