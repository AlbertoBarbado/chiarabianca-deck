class_name Objectives
extends RefCounted
## Mission objectives (data/missions "objective"). Pure rules; the map screen only shows them.
## Types:
##   reach_exit     complete when the party reaches the map's exit (the castle tutorial)
##   boss_hunt      complete when the party reaches the exit after the boss room (the classic act)
##   clear_targets  rooms marked "objective": true (generated maps). Winning the fight there counts;
##                  `required` of `targets` complete it. The party may then return home at once,
##                  or carry on. Reaching the exit without it counts as a retreat.
##                  Flavour keys: verb ("Rescue"), noun ("captives"), target_name.

const TYPE_REACH_EXIT := "reach_exit"
const TYPE_BOSS_HUNT := "boss_hunt"
const TYPE_CLEAR_TARGETS := "clear_targets"
const TYPES := [TYPE_REACH_EXIT, TYPE_BOSS_HUNT, TYPE_CLEAR_TARGETS]


## Fresh objective progress for a mission and the map actually generated for it.
static func create(mission: Dictionary, map_def: Dictionary) -> Dictionary:
	var spec: Dictionary = mission.get("objective", {})
	var type := str(spec.get("type", TYPE_REACH_EXIT))
	if not TYPES.has(type):
		type = TYPE_REACH_EXIT
	var objective := {"type": type, "progress": 0, "done_nodes": [], "verb": str(spec.get("verb", "")), "noun": str(spec.get("noun", "")),
		"text": str(spec.get("text", ""))}
	if type == TYPE_CLEAR_TARGETS:
		var targets := 0
		for node: Dictionary in map_def.get("nodes", []):
			if bool(node.get("objective", false)):
				targets += 1
		objective["targets"] = targets
		objective["required"] = clampi(int(spec.get("required", targets)), 1, maxi(1, targets))
	return objective


## A fight was won on this node: counts it when it is an objective room. Returns true on progress.
static func on_room_cleared(objective: Dictionary, node: MapNodeData) -> bool:
	if node == null or str(objective.get("type", "")) != TYPE_CLEAR_TARGETS or not bool(node.raw.get("objective", false)):
		return false
	var done: Array = objective.get("done_nodes", [])
	if done.has(node.id):
		return false
	done.append(node.id)
	objective["done_nodes"] = done
	objective["progress"] = done.size()
	return true


## Objective met before reaching the exit (only clear_targets can be met early).
static func is_met(objective: Dictionary) -> bool:
	return str(objective.get("type", "")) == TYPE_CLEAR_TARGETS and int(objective.get("progress", 0)) >= int(objective.get("required", 1))


## Outcome of reaching the exit: completed, or retreated for an unmet clear_targets mission.
static func outcome_at_exit(objective: Dictionary) -> String:
	if str(objective.get("type", "")) == TYPE_CLEAR_TARGETS and not is_met(objective):
		return ExpeditionState.OUTCOME_RETREATED
	return ExpeditionState.OUTCOME_COMPLETED


## One line for the map's objective tracker.
static func describe(objective: Dictionary) -> String:
	match str(objective.get("type", "")):
		TYPE_CLEAR_TARGETS:
			var verb := str(objective.get("verb", "Clear"))
			var noun := str(objective.get("noun", "targets"))
			var line := "%s %s: %d / %d" % [verb, noun, int(objective.get("progress", 0)), int(objective.get("required", 1))]
			if is_met(objective):
				line += "  — done! Return home when ready."
			return line
		TYPE_BOSS_HUNT:
			return str(objective.get("text", "Defeat the master of this land and reach the way out."))
		_:
			return str(objective.get("text", "Reach the exit."))
