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
	var def := DataRegistry.get_item(p_relic_id)
	icon.tooltip_text = "%s\n%s" % [def.get("name", p_relic_id), def.get("description", "")]
	return icon


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
