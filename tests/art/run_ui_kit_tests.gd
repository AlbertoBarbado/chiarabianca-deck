extends SceneTree
## Asset catalog validation for the art direction milestone (docs/ART_DIRECTION.md): every asset of
## the castle UI batch is registered in the art catalog and loads, every composed kit piece exists with
## sane nine-patch margins, and every castle service has a painted icon.
##   godot --headless --path . --script res://tests/art/run_ui_kit_tests.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_catalog()
	_test_kit()
	_test_services()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	_checks += 1
	print(("  ok   " if ok else "  FAIL "), label)
	if not ok:
		_failures += 1


func _test_catalog() -> void:
	var prompts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/tools/castle_ui_prompts.json"))
	var missing: Array[String] = []
	for key: String in prompts:
		if key.begins_with("_"):
			continue
		var entry := AssetCatalog.get_entry(key)
		if entry.is_empty() or AssetCatalog.texture(key) == null or bool(entry.get("release_cleared", true)):
			missing.append(key)
	check(missing.is_empty(), "every castle UI asset is in the art catalog, loads and is not marked release-cleared (%s)" % ", ".join(missing))
	var background := AssetCatalog.texture("bg_castle_hub")
	check(background != null and absf(float(background.get_width()) / background.get_height() - 16.0 / 9.0) < 0.02, "the castle hub background is 16:9")
	var cutouts := ["frame_diamond", "icon_svc_expeditions", "icon_res_gold", "orn_corner"]
	var opaque: Array[String] = []
	for key: String in cutouts:
		var image := AssetCatalog.texture(key).get_image() if AssetCatalog.texture(key) != null else null
		if image == null or not image.detect_alpha():
			opaque.append(key)
	check(opaque.is_empty(), "icons and ornaments are transparent cut-outs (%s)" % ", ".join(opaque))


func _test_kit() -> void:
	var pieces := ["plaque_parchment", "plaque_parchment_hover", "plaque_parchment_pressed", "plaque_locked", "panel_navy", "panel_navy_small"]
	for family in ["button_violet", "button_navy"]:
		for suffix in ["", "_hover", "_pressed", "_disabled"]:
			pieces.append(family + suffix)
	var bad: Array[String] = []
	for piece in pieces:
		var box := UIKit.style(piece)
		if box == null or box.texture == null:
			bad.append(piece + " (missing)")
			continue
		var w := box.texture.get_width()
		var h := box.texture.get_height()
		if box.texture_margin_left + box.texture_margin_right >= w or box.texture_margin_top + box.texture_margin_bottom >= h:
			bad.append(piece + " (margins)")
	check(bad.is_empty(), "every kit piece exists and its nine-patch margins leave a stretchable centre (%s)" % ", ".join(bad))


func _test_services() -> void:
	var hub: GDScript = load("res://scripts/ui/castle/castle_hub_screen.gd")
	var icons: Dictionary = hub.get_script_constant_map()["SERVICE_ICONS"]
	var missing: Array[String] = []
	for service: Dictionary in _services():
		var icon_id := str(icons.get(str(service["id"]), ""))
		if icon_id == "" or AssetCatalog.texture(icon_id) == null:
			missing.append(str(service["id"]))
	check(missing.is_empty(), "every castle service has a painted icon (%s)" % ", ".join(missing))


func _services() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/castle/services.json"))
	return parsed if parsed is Array else []
