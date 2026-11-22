class_name Inventory
extends RefCounted
## Player currency and consumable items (item definitions live in data/items).

signal changed

var gold: int = 0
var items: Dictionary = {}  # item_id -> count
## Owned relic ids (permanent passive items from data/items, category "relic"); each at most once.
var relics: Array[String] = []
## Party stash of equipment that nobody wears (item ids; duplicates allowed). See Equipment.
var equipment: Array[String] = []


func add_gold(amount: int) -> void:
	gold += amount
	changed.emit()


func can_afford(price: int) -> bool:
	return gold >= price


func spend_gold(amount: int) -> bool:
	if not can_afford(amount):
		return false
	gold -= amount
	changed.emit()
	return true


func add_item(item_id: String, count: int = 1) -> void:
	items[item_id] = count_of(item_id) + count
	changed.emit()


func remove_item(item_id: String, count: int = 1) -> bool:
	if count_of(item_id) < count:
		return false
	items[item_id] = count_of(item_id) - count
	if items[item_id] <= 0:
		items.erase(item_id)
	changed.emit()
	return true


func has_relic(relic_id: String) -> bool:
	return relics.has(relic_id)


## Adds a relic. Returns false for unknown ids or relics already owned (no duplicates).
func add_relic(relic_id: String) -> bool:
	if has_relic(relic_id) or str(DataRegistry.get_item(relic_id).get("category", "")) != "relic":
		return false
	relics.append(relic_id)
	changed.emit()
	return true


## Puts an equipment item into the party stash. Returns false for ids that are not equipment.
func add_equipment(item_id: String) -> bool:
	if str(DataRegistry.get_item(item_id).get("category", "")) != "equipment":
		return false
	equipment.append(item_id)
	changed.emit()
	return true


func count_of(item_id: String) -> int:
	return int(items.get(item_id, 0))
