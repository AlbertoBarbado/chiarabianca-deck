extends SceneTree
## Release gate: fails (exit code 1) while any shipped art is not cleared for commercial use.
## Run before exporting a release build:
##   godot --headless --path . --script res://tests/art/check_release_art.gd
##
## Sources checked (an entry counts as cleared only with "release_cleared": true):
## - the art catalog (data/art/art_catalog.json, via AssetCatalog);
## - the effect and UI sprite manifests (arrays of entries);
## - the combat, recut and forest sprite manifests (arrays, or {"assets": {id: entry}});
## - every ComfyUI generation log in assets/generated/*/generation_log.json ({"assets": {id: entry}}).

const LIST_MANIFESTS := {
	"res://assets/effects/sprites/manifest.json": "effects",
	"res://assets/ui/manifest.json": "ui",
	"res://assets/combat_manifest.json": "combat",
	"res://assets/recut_manifest.json": "recut",
	"res://assets/forest_manifest.json": "forest",
}
const GENERATED_ROOT := "res://assets/generated"


func _initialize() -> void:
	AssetCatalog.reload()
	var blockers: Array[String] = []
	for id: String in AssetCatalog.release_blockers():
		blockers.append("catalog/%s (%s)" % [id, AssetCatalog.get_entry(id).get("status", "unknown")])
	for path: String in LIST_MANIFESTS:
		blockers.append_array(manifest_blockers(path, str(LIST_MANIFESTS[path])))
	for folder in DirAccess.get_directories_at(GENERATED_ROOT):
		blockers.append_array(manifest_blockers("%s/%s/generation_log.json" % [GENERATED_ROOT, folder], "generated/" + folder))
	if blockers.is_empty():
		print("Release art check passed: every shipped asset is marked cleared.")
		quit(0)
		return
	print("Release art check FAILED: %d asset(s) are not cleared for commercial release:" % blockers.size())
	for line in blockers:
		print("  - " + line)
	print("Replace them with cleared art or verify the license, then set release_cleared to true (see docs/ASSET_LICENSES.md).")
	quit(1)


## Uncleared entries of one manifest file, labelled "<prefix>/<id>". A missing file yields none.
static func manifest_blockers(path: String, prefix: String) -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var entries: Array = []
	if data is Array:
		entries = data
	elif data is Dictionary and (data as Dictionary).get("assets") is Array:
		entries = data["assets"]
	elif data is Dictionary and (data as Dictionary).get("assets") is Dictionary:
		var assets: Dictionary = data["assets"]
		for id: String in assets:
			var entry: Dictionary = (assets[id] as Dictionary).duplicate() if assets[id] is Dictionary else {}
			entry["id"] = entry.get("id", id)
			entries.append(entry)
	else:
		out.append("%s (unreadable manifest %s)" % [prefix, path])
		return out
	for entry: Variant in entries:
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		if bool(e.get("release_cleared", false)):
			continue
		var label := str(e.get("id", e.get("path", e.get("file", "?"))))
		var group := str(e.get("folder", e.get("group", "")))
		out.append("%s/%s%s" % [prefix, (group + "/") if group != "" else "", label])
	return out
