class_name RelicIcon
extends TextureRect
## A relic's picture with its name and effect as the tooltip (mouse) and a pop when it fires. Falls
## back to the treasure icon when the relic has no art yet. Used by the combat relic bar, the relic
## list, chests and the reward screen.
##   RelicIcon.create("ley_crystal", 40)

var relic_id: String = ""
var _pop: Tween


static func create(p_relic_id: String, icon_size: int = 40) -> RelicIcon:
	var icon := RelicIcon.new()
	icon.relic_id = p_relic_id
	icon.name = "RelicIcon_" + p_relic_id
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.texture = texture_for(p_relic_id)
	icon.tooltip_text = tooltip_for(p_relic_id)
	return icon


## The one relic hover text used everywhere: name, rarity and what it does.
static func tooltip_for(p_relic_id: String) -> String:
	var def := DataRegistry.get_item(p_relic_id)
	var rarity := str(def.get("rarity", ""))
	var kind := "Boss relic" if rarity == "boss" else ("Bond relic" if rarity == "bond" else ("%s relic" % rarity.capitalize() if rarity != "" else "Relic"))
	return "%s  ·  %s\n%s" % [str(def.get("name", p_relic_id)), kind, str(def.get("description", ""))]


## Several relics in one hover text (relic buttons and lists).
static func tooltip_for_all(relic_ids: Array) -> String:
	var parts: Array[String] = []
	for relic_id: Variant in relic_ids:
		parts.append(tooltip_for(str(relic_id)))
	return "\n\n".join(parts)


## A relic as icon + name (+ effect) row with the hover text on the whole row.
static func row(p_relic_id: String, icon_size: int = 36, with_effect: bool = true) -> HBoxContainer:
	var box := UIFactory.hbox(8)
	box.name = "RelicRow_" + p_relic_id
	box.tooltip_text = tooltip_for(p_relic_id)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon := create(p_relic_id, icon_size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var def := DataRegistry.get_item(p_relic_id)
	var text := UIFactory.label(str(def.get("name", p_relic_id)) + ((": " + str(def.get("description", ""))) if with_effect else ""), &"", true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("font_color", rarity_color(str(def.get("rarity", "common"))).lightened(0.2))
	text.tooltip_text = box.tooltip_text
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(text)
	return box


static func texture_for(p_relic_id: String) -> Texture2D:
	var path := str(DataRegistry.get_item(p_relic_id).get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return AssetCatalog.icon("treasure")


## Rarity colour for names (boss relics in red-gold).
static func rarity_color(rarity: String) -> Color:
	return Color("ff9a6a") if rarity == "boss" else Equipment.rarity_color(rarity)


## A quick bounce and glow: the relic just did something.
func flash() -> void:
	if SettingsStore.load_values().get("effects_quality", "full") == "off":
		return
	if _pop != null and _pop.is_valid():
		_pop.kill()
	pivot_offset = size / 2.0
	_pop = create_tween()
	_pop.tween_property(self, "scale", Vector2.ONE * 1.45, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.parallel().tween_property(self, "modulate", Color(1.6, 1.45, 1.0), 0.12)
	_pop.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)
	_pop.parallel().tween_property(self, "modulate", Color.WHITE, 0.3)
