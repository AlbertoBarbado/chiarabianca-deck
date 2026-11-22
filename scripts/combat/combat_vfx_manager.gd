class_name CombatVfxManager
extends Control
## Layer that turns CombatManager.visual_event signals into CombatVfx nodes.
## The events are emitted AFTER a gameplay effect has resolved, so a visual never runs ahead
## of the rules and never changes them. The manager is a full-screen, input-transparent
## Control: nothing it spawns can block taps or clicks.
##
## `locator` is a Callable(combatant_id: String) -> Rect2 giving the on-screen rectangle (global
## coordinates) of that combatant's panel; an empty Rect2 means "not visible" and is skipped.

signal effect_spawned(effect_id: String, node: CombatVfx)

const REFERENCE_HEIGHT := 720.0
const VFX_SCENE_PATH := "res://scenes/combat/combat_vfx.tscn"

var quality_name: String = VfxCatalog.DEFAULT_QUALITY
var spawned_count: int = 0

var _locator: Callable
var _pending: Array[Dictionary] = []
var _flush_scheduled: bool = false
var _scene: PackedScene = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## quality_override "" = the player's setting (SettingsStore "effects_quality").
func setup(combat: CombatManager, locator: Callable, quality_override: String = "") -> void:
	_locator = locator
	quality_name = quality_override if quality_override != "" else str(SettingsStore.load_values().get("effects_quality", VfxCatalog.DEFAULT_QUALITY))
	if combat != null and not combat.visual_event.is_connected(handle_event):
		combat.visual_event.connect(handle_event)


func is_enabled() -> bool:
	return bool(VfxCatalog.quality(quality_name).get("enabled", false))


func active_count() -> int:
	var count := 0
	for child in get_children():
		if child is CombatVfx and not child.is_queued_for_deletion():
			count += 1
	return count


## Queues an event. Effects are spawned one frame later, once the UI has rebuilt its panels.
func handle_event(event: Dictionary) -> void:
	if not is_enabled():
		return
	var effect_id := VfxCatalog.match_event(event)
	if effect_id == "":
		return
	_pending.append({"event": event, "effect_id": effect_id})
	if not _flush_scheduled:
		_flush_scheduled = true
		_flush.call_deferred()


func _flush() -> void:
	if is_inside_tree():
		await get_tree().process_frame
	_flush_scheduled = false
	var batch := _pending.duplicate()
	_pending.clear()
	var stagger := float(VfxCatalog.quality(quality_name).get("stagger", 0.1))
	for i in batch.size():
		spawn_effect(batch[i]["effect_id"], batch[i]["event"], i * stagger)


## Spawns an effect for an event right now. Returns the created nodes (empty if skipped).
func spawn_effect(effect_id: String, event: Dictionary, delay: float = 0.0) -> Array[CombatVfx]:
	var created: Array[CombatVfx] = []
	var def := VfxCatalog.effect(effect_id)
	var quality := VfxCatalog.quality(quality_name)
	if def.is_empty() or not bool(quality.get("enabled", false)) or not _locator.is_valid():
		return created
	var target_ids: Array[String] = []
	target_ids.assign(event.get("target_ids", []))
	var rects: Dictionary = {}  # id -> local Rect2
	for id in target_ids:
		var rect := _local_rect(id)
		if rect.has_area():
			rects[id] = rect
	if rects.is_empty():
		return created
	var source_rect := _local_rect(str(event.get("source_id", "")))
	var groups: Array = []  # each entry is a list of target ids drawn as one effect
	if def.has("group_fit") and rects.size() > 1:
		groups.append(rects.keys())
	elif int(quality.get("max_active", 0)) < 12 and rects.size() > 1:
		groups.append([rects.keys()[0]])  # reduced quality: one effect for the whole event
	else:
		for id in rects.keys():
			groups.append([id])
	for ids: Array in groups:
		if active_count() >= int(quality.get("max_active", 0)):
			break
		var node := _create_node()
		var target_rects: Array[Rect2] = []
		for id in ids:
			target_rects.append(rects[id])
		var texture_size: Vector2 = CombatVfx.resolve_texture(def)["texture"].get_size()
		var geometry := CombatVfx.compute_geometry(def, texture_size, target_rects, source_rect, maxf(size.y, 1.0) / REFERENCE_HEIGHT, VfxCatalog.reference_target_width())
		add_child(node)
		node.play(effect_id, def, geometry, quality, delay)
		if def.has("impact") and bool(quality.get("impacts", false)):
			var impact_event := event.duplicate()
			impact_event["target_ids"] = ids
			node.impact.connect(func(_at: Vector2) -> void: spawn_effect(str(def["impact"]), impact_event))
		created.append(node)
		spawned_count += 1
		effect_spawned.emit(effect_id, node)
	return created


func _create_node() -> CombatVfx:
	if _scene == null and ResourceLoader.exists(VFX_SCENE_PATH):
		_scene = load(VFX_SCENE_PATH) as PackedScene
	var instance: CombatVfx = _scene.instantiate() as CombatVfx if _scene != null else null
	return instance if instance != null else CombatVfx.new()


func _local_rect(id: String) -> Rect2:
	if id == "" or not _locator.is_valid():
		return Rect2()
	var global_rect: Rect2 = _locator.call(id)
	return Rect2(global_rect.position - global_position, global_rect.size)
