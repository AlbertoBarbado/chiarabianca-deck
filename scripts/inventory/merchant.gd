class_name Merchant
extends RefCounted
## Reusable shop logic. Stock comes from a data/shops definition; purchases move gold and
## items on an Inventory. Contains no UI code.

signal stock_changed

const UNLIMITED := -1

var shop_id: String = ""
var display_name: String = ""
var greeting: String = ""
## [{item_id, price, quantity}] where quantity -1 means unlimited.
var stock: Array[Dictionary] = []


## With a party, gear nobody in it can use is left out of the stock, and `rng` (seeded per visit)
## adds the shop's gear offers: "gear_offers" in the shop definition, else run_rules loot.shop.offers,
## random items the party can use, weighted by loot.shop.rarity_weights, one of each, at their price.
static func from_definition(shop_def: Dictionary, party: Party = null, rng: RandomNumberGenerator = null) -> Merchant:
	var merchant := Merchant.new()
	merchant.shop_id = str(shop_def.get("id", ""))
	merchant.display_name = str(shop_def.get("name", "Merchant"))
	merchant.greeting = str(shop_def.get("greeting", ""))
	for entry: Dictionary in shop_def.get("stock", []):
		var item_id := str(entry.get("item_id", ""))
		if party != null and Equipment.is_equipment(item_id) and not Equipment.usable_by_party(party, item_id):
			continue
		merchant.stock.append({
			"item_id": item_id,
			"price": int(entry.get("price", 0)),
			"quantity": int(entry.get("quantity", UNLIMITED)),
		})
	if party != null and rng != null:
		var rules: Dictionary = RunRules.get_block("loot").get("shop", {})
		var offers := int(shop_def.get("gear_offers", rules.get("offers", 0)))
		var taken: Array[String] = []
		for entry in merchant.stock:
			taken.append(str(entry["item_id"]))
		for i in offers:
			var item_id := Loot.pick(party, rng, rules.get("rarity_weights", {}), taken)
			if item_id == "":
				break
			taken.append(item_id)
			merchant.stock.append({"item_id": item_id, "price": int(Equipment.item(item_id).get("price", 60)), "quantity": 1})
	return merchant


## Returns "" on success, otherwise a player-facing reason the purchase failed.
func buy(item_id: String, inventory: Inventory) -> String:
	var entry := _find(item_id)
	if entry.is_empty():
		return "That item is not for sale."
	if entry["quantity"] == 0:
		return "Sold out."
	if not inventory.spend_gold(entry["price"]):
		return "Not enough gold."
	if Equipment.is_equipment(item_id):
		inventory.add_equipment(item_id)  # gear goes to the party stash
	else:
		inventory.add_item(item_id)
	if entry["quantity"] != UNLIMITED:
		entry["quantity"] -= 1
	stock_changed.emit()
	return ""


## Re-applies purchases saved in the room state ({item_id: count}) so limited stock stays sold out after a reload.
func apply_purchases(bought: Dictionary) -> void:
	for item_id: String in bought:
		var entry := _find(item_id)
		if not entry.is_empty() and entry["quantity"] != UNLIMITED:
			entry["quantity"] = maxi(0, int(entry["quantity"]) - int(bought[item_id]))


func get_price(item_id: String) -> int:
	return int(_find(item_id).get("price", 0))


func get_quantity(item_id: String) -> int:
	return int(_find(item_id).get("quantity", 0))


func _find(item_id: String) -> Dictionary:
	for entry in stock:
		if entry["item_id"] == item_id:
			return entry
	return {}
