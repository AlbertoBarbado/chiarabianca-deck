class_name CampaignRules
extends RefCounted
## Tunable campaign rules (data/progression/campaign_rules.json) and the Sister Bond table
## (data/progression/bond.json). Read-only; see docs/PERSISTENT_RPG_DESIGN.md.

const RULES_PATH := "res://data/progression/campaign_rules.json"
const BOND_PATH := "res://data/progression/bond.json"

static var _rules: Dictionary = {}
static var _bond: Dictionary = {}


static func block(block_id: String) -> Dictionary:
	if _rules.is_empty():
		var parsed: Variant = DataRegistry.read_json(RULES_PATH)
		_rules = parsed if parsed is Dictionary else {}
	return (_rules.get(block_id, {}) as Dictionary).duplicate(true) if _rules.get(block_id, {}) is Dictionary else {}


static func bond() -> Dictionary:
	if _bond.is_empty():
		var parsed: Variant = DataRegistry.read_json(BOND_PATH)
		_bond = parsed if parsed is Dictionary else {}
	return _bond


static func outcome(result: String) -> Dictionary:
	return block("outcomes").get(result, {}) if block("outcomes").get(result, {}) is Dictionary else {}


static func reload() -> void:
	_rules.clear()
	_bond.clear()
