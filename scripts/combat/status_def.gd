class_name StatusDef
extends RefCounted
## Static status definition (data/statuses). Describes how a status behaves; the runtime
## stack count lives on the Combatant. Duration rule for every status: stacks == turns
## remaining, and all statuses lose one stack at the end of each round (after the enemy phase).
## A status may also tick: deal damage at a fixed timing (see TICK_ENEMY_PHASE_START).

const TICK_ENEMY_PHASE_START := "enemy_phase_start"

var id: String = ""
var display_name: String = ""
var kind: String = "debuff"
var description: String = ""
## Empty when the status has no periodic effect.
var tick_timing: String = ""
var tick_damage: int = 0
var tick_ignores_block: bool = false
## When true the tick deals damage equal to the current stacks (Poison) instead of a fixed amount.
var tick_per_stack: bool = false
## Highest stack count (0 = unlimited). Burn is capped: short and hot.
var max_stacks: int = 0
## "round": loses 1 stack every round (default). "on_trigger": only its own trigger uses it up (Bleed).
var decay: String = "round"
## "stacks": every attack that deals HP damage costs the victim this many extra HP (Bleed).
var on_hit: String = ""
## Damage type of the tick (Burn = fire, Poison = poison): resistances and weaknesses apply to it.
var tick_element: String = ""
## Chill: each stack makes the bearer take this much more damage (percent) of one element.
var vulnerable_element: String = ""
var vulnerable_per_stack: int = 0
## Every element the vulnerability applies to (Soaked: lightning and frost). vulnerable_element is the first.
var vulnerable_elements: Array[String] = []
## Sandblind: the bearer's attacks deal this much more (negative = less) damage, in percent, while it lasts.
var damage_dealt_pct: int = 0
## Quicksand: the party draws this many fewer cards at the start of its turn (then 1 stack is used up).
var draw_penalty: int = 0
## Chill: each stack changes the bearer's initiative by this amount (negative = slower).
var initiative_per_stack: int = 0
## Blight: at the start of the enemy phase (after damage ticks) a bearer whose HP is at or below its
## stacks perishes. Usually paired with decay "on_trigger" so it builds up over the fight.
var execute: bool = false


static func from_dict(data: Dictionary) -> StatusDef:
	var def := StatusDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("name", def.id.capitalize()))
	def.kind = str(data.get("kind", "debuff"))
	def.description = str(data.get("description", ""))
	var tick: Dictionary = data.get("tick", {})
	def.tick_timing = str(tick.get("timing", ""))
	def.tick_damage = int(tick.get("damage", 0))
	def.tick_ignores_block = bool(tick.get("ignores_block", false))
	def.tick_per_stack = bool(tick.get("per_stack", false))
	def.max_stacks = int(data.get("max_stacks", 0))
	def.decay = str(data.get("decay", "round"))
	def.on_hit = str(data.get("on_hit", ""))
	def.tick_element = str(tick.get("element", ""))
	var vulnerable: Dictionary = data.get("vulnerable", {})
	def.vulnerable_elements.assign(vulnerable.get("elements", [vulnerable["element"]] if vulnerable.has("element") else []))
	def.vulnerable_element = def.vulnerable_elements[0] if not def.vulnerable_elements.is_empty() else ""
	def.damage_dealt_pct = int(data.get("damage_dealt_pct", 0))
	def.draw_penalty = int(data.get("draw_penalty", 0))
	def.vulnerable_per_stack = int(vulnerable.get("per_stack", 0))
	def.initiative_per_stack = int(data.get("initiative_per_stack", 0))
	def.execute = bool(data.get("execute", false))
	return def


func ticks_at(timing: String) -> bool:
	return tick_timing != "" and tick_timing == timing and (tick_damage > 0 or tick_per_stack)


## Damage of one tick for the given stack count.
func tick_amount(stacks: int) -> int:
	return maxi(0, stacks) if tick_per_stack else tick_damage


## Player-facing explanation with the live stack count filled in.
func describe(stacks: int) -> String:
	return description.replace("{damage}", str(tick_amount(stacks))).replace("{stacks}", str(stacks)).replace("{vulnerable}", str(vulnerable_per_stack * stacks)).replace("{initiative}", str(absi(initiative_per_stack) * stacks))


## Compact label for combatant panels, e.g. "Burn 3 (2 dmg/turn)".
func short_text(stacks: int) -> String:
	if initiative_per_stack != 0:
		return "%s %d (-%d initiative, +%d%% %s dmg taken)" % [display_name, stacks, absi(initiative_per_stack) * stacks, vulnerable_per_stack * stacks, vulnerable_element]
	if execute:
		return "%s %d (dies at %d HP or less)" % [display_name, stacks, stacks]
	if on_hit == "stacks":
		return "%s %d (+%d per hit)" % [display_name, stacks, stacks]
	if tick_per_stack:
		return "%s %d (%d dmg, then -1)" % [display_name, stacks, stacks]
	if tick_damage > 0:
		return "%s %d (%d dmg/turn)" % [display_name, stacks, tick_damage]
	return "%s %d" % [display_name, stacks]
