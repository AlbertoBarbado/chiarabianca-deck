class_name ScreenBase
extends Control
## Base for full-screen UIs: royal navy background, gold accent line and a margin container.
## Subclasses override _build() and add their widgets to `root`.

const OUTER_MARGIN := 28
const MENU_FADE_TIME := 0.25

var root: MarginContainer


func _ready() -> void:
	UIFactory.full_rect(self)
	var menu := _menu_screen()
	if menu:
		var menu_background := MenuBackground.new()
		add_child(menu_background)
		menu_background.setup(_menu_dim())
	else:
		var backdrop := RoomBackdrop.new()
		add_child(backdrop)
		backdrop.setup(_backdrop(), _backdrop_dim())
	if not menu:
		var accent := ColorRect.new()
		accent.color = UITheme.GOLD
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		accent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		accent.offset_bottom = 4
		add_child(accent)
	root = MarginContainer.new()
	UIFactory.full_rect(root)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, OUTER_MARGIN)
	add_child(root)
	_build()
	if menu and SettingsStore.load_values().get("effects_quality", "full") != "off":
		modulate.a = 0.0  # Short fade between menu screens.
		create_tween().tween_property(self, "modulate:a", 1.0, MENU_FADE_TIME)


func _build() -> void:
	pass


## Menu screens (title, selection, overview, settings, completion) use the castle illustration,
## particles and a fade-in; gameplay screens keep their room backdrops.
func _menu_screen() -> bool:
	return false


func _menu_dim() -> float:
	return 0.3


## Override to show room art: {texture, tint} (see AssetCatalog.room_backdrop). {} = plain gradient.
func _backdrop() -> Dictionary:
	return {}


func _backdrop_dim() -> float:
	return 0.62


## Backdrop of the map node the party is currently in (rooms, combat, rewards).
func current_room_backdrop() -> Dictionary:
	var node := GameState.get_current_node()
	if node == null:
		return {}
	var map_id := GameState.map_progress.graph.id if GameState.map_progress != null else ""
	var backdrop := AssetCatalog.room_backdrop(node.id, node.type, map_id)
	# Inside a town (its hub, its merchant, its fire) the town's own scene is the backdrop.
	var town_art := str(GameState.current_town().get("art", ""))
	if town_art != "" and AssetCatalog.texture(town_art) != null:
		return AssetCatalog.backdrop_by_asset(town_art, backdrop.get("tint", Color(0.3, 0.4, 0.8)))
	# Terrain (e.g. a room at sea, aboard the ship) overrides the map-wide room picture.
	var terrain_id := GameState.map_progress.graph.terrain_backdrop(node) if GameState.map_progress != null else ""
	if terrain_id != "" and AssetCatalog.texture(terrain_id) != null:
		return AssetCatalog.backdrop_by_asset(terrain_id, backdrop.get("tint", Color(0.3, 0.4, 0.8)))
	return backdrop


## Standard bottom row: optional back button on the left, spacer, then right-side buttons.
func make_footer(back_screen: int = -1) -> HBoxContainer:
	var footer := UIFactory.hbox()
	if back_screen >= 0:
		var back := UIFactory.button("Back")
		back.pressed.connect(func() -> void: SceneRouter.go(back_screen as SceneRouter.Screen))
		footer.add_child(back)
	footer.add_child(UIFactory.expander())
	return footer
