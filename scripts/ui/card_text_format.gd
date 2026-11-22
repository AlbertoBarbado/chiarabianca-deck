class_name CardTextFormat
extends RefCounted
## Turns a card's plain description into BBCode for its rules panel, so the important words read at
## a glance: damage types in their element colour, statuses and card keywords (Block, Exhaust,
## Energy...) in gold, numbers in bold white. On upgraded cards the numbers are green, as in other
## deckbuilders, so the improvement is visible without comparing cards.

const NUMBER_COLOR := Color("ffffff")
const UPGRADED_COLOR := Color("8dff7a")
const KEYWORD_COLOR := Color("ffd27a")
## Card words that are not statuses or damage types but deserve emphasis.
const CARD_KEYWORDS := ["Block", "Exhaust", "Retain", "Energy", "Draw", "ALL", "Heal", "Taunt", "X"]
## The party's surplus magic (CombatManager.aether): violet, like the counter in the top bar.
const AETHER_COLOR := Color("c9a7ff")
## Wind's conjured Gust cards: jade, like the Momentum counter.
const GUST_COLOR := Color("8fe8c8")

## In-combat damage preview (CardEffects.damage_preview): a number raised by the current situation
## (weapon, Aether, Momentum, a weakness) is cyan, a lowered one (resistance, Sandblind) red.
const BOOSTED_COLOR := Color("6fe3ff")
const REDUCED_COLOR := Color("ff7b6b")
const PREVIEW_MARK := 0xE000  # private-use characters stand in for swapped numbers

static var _keyword_regex: RegEx
static var _damage_number_regex: RegEx
static var _keyword_colors: Dictionary = {}


static func to_bbcode(description: String, upgraded: bool, damage_preview: Array = []) -> String:
	_ensure()
	var text := description.replace("[", "(").replace("]", ")")
	var swapped: Array[String] = []
	text = _mark_preview(text, damage_preview, swapped)
	# Numbers first (keywords never contain digits), then keywords, each wrapped once.
	var number := RegEx.create_from_string("(?<![\\w#])(\\+?\\d+%?)")
	var number_color := (UPGRADED_COLOR if upgraded else NUMBER_COLOR).to_html(false)
	text = number.sub(text, "[b][color=#%s]$1[/color][/b]" % number_color, true)
	var out := ""
	var last := 0
	for m in _keyword_regex.search_all(text):
		out += text.substr(last, m.get_start() - last)
		var word := m.get_string()
		var color: Color = _keyword_colors.get(word.to_lower(), KEYWORD_COLOR)
		out += "[b][color=#%s]%s[/color][/b]" % [color.to_html(false), word]
		last = m.get_end()
	out += text.substr(last)
	for i in swapped.size():
		out = out.replace(String.chr(PREVIEW_MARK + i), swapped[i])
	return out


## Puts each previewed damage number in place of the printed one ("Deal 6 damage" -> 9 with a weapon
## bonus). Printed numbers are found in order ("Deal N" or "N <Element> damage") and matched to the
## preview entries by value; a number left unchanged keeps the normal colour. Each swapped number is
## replaced by a private-use marker here, and by its coloured BBCode at the end of to_bbcode (so the
## number and keyword passes never touch it).
static func _mark_preview(text: String, preview: Array, swapped: Array[String]) -> String:
	if preview.is_empty():
		return text
	if _damage_number_regex == null:
		_damage_number_regex = RegEx.create_from_string("(?i)\\bdeal (\\d+)\\b|(?<![\\w+])(\\d+) (?:[A-Z][a-z]+ )?damage")
	var spans: Array[Dictionary] = []
	var next := 0
	var matches := _damage_number_regex.search_all(text)
	for entry: Variant in preview:
		var base := int((entry as Dictionary).get("base", 0))
		var final_amount := int((entry as Dictionary).get("final", base))
		while next < matches.size():
			var m: RegExMatch = matches[next]
			next += 1
			var group := 1 if m.get_string(1) != "" else 2
			if int(m.get_string(group)) != base:
				continue
			if final_amount != base:
				spans.append({"start": m.get_start(group), "end": m.get_end(group), "final": final_amount, "base": base})
			break
	spans.reverse()  # replace from the end so earlier offsets stay valid
	for span in spans:
		var color := BOOSTED_COLOR if int(span["final"]) > int(span["base"]) else REDUCED_COLOR
		var mark := String.chr(PREVIEW_MARK + swapped.size())
		swapped.append("[b][color=#%s]%d[/color][/b]" % [color.to_html(false), int(span["final"])])
		text = text.substr(0, int(span["start"])) + mark + text.substr(int(span["end"]))
	return text


static func _ensure() -> void:
	if _keyword_regex != null:
		return
	var words: Array[String] = []
	for element: String in DamageTypes.ids():
		var label := DamageTypes.display_name(element)
		words.append(label)
		_keyword_colors[label.to_lower()] = DamageTypes.color(element).lightened(0.15)
	for status_id: String in DataRegistry.statuses:
		var status_def := DataRegistry.get_status(status_id)
		if status_def != null and status_def.display_name != "":
			words.append(status_def.display_name)
	words.append_array(CARD_KEYWORDS)
	words.append("Aether")
	_keyword_colors["aether"] = AETHER_COLOR
	for gust_word in ["Gust", "Gusts"]:
		words.append(gust_word)
		_keyword_colors[gust_word.to_lower()] = GUST_COLOR
	# Longest first so "Sandblind" wins over shorter overlaps.
	words.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var escaped: Array[String] = []
	for word in words:
		escaped.append(word.replace("'", "\\'"))
	_keyword_regex = RegEx.create_from_string("\\b(" + "|".join(escaped) + ")\\b")


static func reset() -> void:
	_keyword_regex = null
	_keyword_colors.clear()
