class_name RunRules
extends RefCounted
## Tunable run-wide rules read from data/progression/run_rules.json (card removal limits, elite
## reward defaults). Nodes may override a block with their own entry of the same name.

const PATH := "res://data/progression/run_rules.json"

static var _cache: Dictionary = {}


static func get_block(block_id: String, node_override: Dictionary = {}) -> Dictionary:
	if _cache.is_empty():
		var parsed: Variant = DataRegistry.read_json(PATH)
		_cache = parsed if parsed is Dictionary else {}
	var block: Dictionary = (_cache.get(block_id, {}) as Dictionary).duplicate(true)
	var override: Variant = node_override.get(block_id, {})
	if override is Dictionary:
		block.merge(override, true)
	return block


static func reload() -> void:
	_cache.clear()
