class_name CampaignState
extends RefCounted
## Everything permanent about the player's campaign (docs/PERSISTENT_RPG_DESIGN.md §3.1).
## Runtime expedition state (map, HP, drafted cards) lives in GameState / ExpeditionState instead.
##
## The roster is a normal Party: each sister's `deck` array is her permanent card COLLECTION
## (every copy she owns, with its permanent upgrade level) and her `equipment` is what she wears.
## The vault is a normal Inventory: gold = the castle treasury, equipment = the armory stash,
## items = the potion stores. Reusing these classes lets the existing equipment screen and card views
## work at the castle unchanged.

const DATA_VERSION := 1

var roster: Party
var vault: Inventory
## character_id -> Array[String] of collection uids forming the prepared deck.
var prepared: Dictionary = {}
## preset name -> {character_id: [uids]} (saved deck configurations).
var presets: Dictionary = {}
var essence: int = 0
## Blacksmith refinement: equipment item id -> level (applies to every copy of that item).
var refinement: Dictionary = {}
## Relics found at least once: each can be chosen as the heirloom carried into an expedition.
var relic_collection: Array[String] = []
var heirloom: String = ""
var potion_capacity: int = 3
## Unlocked apothecary brew recipes.
var recipes: Array[String] = []
## character_id -> Array[String] of playable specialization ids she may use.
var unlocked_specs: Dictionary = {}
## Open castle services (data/castle).
var services: Array[String] = []
## Sister Bond: {xp: int}. The level derives from the xp (Bond.level_for).
var bond: Dictionary = {"xp": 0}
## Fusion recipes already crafted (non-repeatable recipes can only be crafted once).
var fusions_done: Array[String] = []
## {flags: {flag: value}, regions: {region_id: {threat: int, flags: {}}}}
var world: Dictionary = {"flags": {}, "regions": {}}
## {completed: [mission ids], attempts: {mission_id: n}}
var missions: Dictionary = {"completed": [], "attempts": {}}
## Lifetime numbers: expeditions_started, completed, retreated, defeated, cards_upgraded, fusions.
var stats: Dictionary = {}
## Apothecary belt upgrades already bought (indices into campaign_rules apothecary.capacity_upgrades).
var capacity_upgrades_bought: int = 0
## Sister levels: character_id -> XP (Levels derives the level, Max HP bonus and milestones).
var levels: Dictionary = {}
## Pending Mastery card choices from level-ups: [{character_id, level, upgraded, options: [card ids]}].
var level_rewards: Array = []
## Region contracts (Contracts): region_id -> {tier, kind, seed}. Offered once every authored
## mission of the region is completed; each completion raises the tier and rolls a new contract.
var contracts: Dictionary = {}


## A new campaign from the specialization chosen for each sister (her primary specialization).
static func create(selection: Dictionary) -> CampaignState:
	var campaign := CampaignState.new()
	var start := CampaignRules.block("start")
	campaign.roster = Party.from_selection(selection)
	campaign.vault = Inventory.new()
	campaign.vault.gold = int(start.get("treasury", 0))
	campaign.essence = int(start.get("essence", 0))
	var potions: Dictionary = start.get("potions", {})
	for item_id: String in potions:
		campaign.vault.add_item(item_id, int(potions[item_id]))
	campaign.potion_capacity = int(start.get("potion_capacity", 3))
	campaign.services.assign(start.get("services", []))
	campaign.recipes.assign(start.get("recipes", []))
	for member in campaign.roster.members:
		campaign.unlocked_specs[member.id] = [member.specialization.id]
		campaign.reset_prepared_to_starter(member.id)
	campaign.refresh_roster()
	return campaign


# --- Roster and collection ------------------------------------------------------------------------

func member(character_id: String) -> PartyMember:
	return roster.get_member(character_id) if roster != null else null


## Collection copies of one sister (her whole permanent card pool).
func collection(character_id: String) -> Array[OwnedCard]:
	var m := member(character_id)
	return m.deck if m != null else ([] as Array[OwnedCard])


func prepared_uids(character_id: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(prepared.get(character_id, []))
	return result


func prepared_cards(character_id: String) -> Array[OwnedCard]:
	var m := member(character_id)
	var result: Array[OwnedCard] = []
	if m == null:
		return result
	for uid in prepared_uids(character_id):
		var owned := m.find_card(uid)
		if owned != null:
			result.append(owned)
	return result


func set_prepared(character_id: String, uids: Array) -> void:
	var clean: Array[String] = []
	var m := member(character_id)
	for uid: Variant in uids:
		if m != null and m.find_card(str(uid)) != null and not clean.has(str(uid)):
			clean.append(str(uid))
	prepared[character_id] = clean


## Prepared deck = the primary specialization's starting deck, taken from the collection copies
## (upgraded copies first). Missing starter copies are added to the collection (starter cards are
## always available).
func reset_prepared_to_starter(character_id: String) -> void:
	var m := member(character_id)
	if m == null:
		return
	var chosen: Array[String] = []
	for card_id in m.specialization.starting_deck_card_ids:
		var best: OwnedCard = null
		for owned in m.deck:
			if owned.card_id == card_id and not chosen.has(owned.uid) and (best == null or owned.upgrade_level > best.upgrade_level):
				best = owned
		if best == null:
			best = m.add_card(card_id)
		chosen.append(best.uid)
	prepared[character_id] = chosen


func add_collection_card(character_id: String, card_id: String, upgrade_level: int = 0) -> OwnedCard:
	var m := member(character_id)
	if m == null or DataRegistry.get_card(card_id) == null:
		return null
	var owned := m.add_card(card_id)
	owned.upgrade_level = clampi(upgrade_level, 0, maxi(CardUpgrader.get_max_level(DataRegistry.get_card(card_id)), 0))
	return owned


## Removes a copy from the collection and from every prepared deck and preset that used it.
func remove_collection_card(character_id: String, uid: String) -> bool:
	var m := member(character_id)
	if m == null or not m.remove_card(uid):
		return false
	(prepared.get(character_id, []) as Array).erase(uid)
	for preset_name: String in presets:
		((presets[preset_name] as Dictionary).get(character_id, []) as Array).erase(uid)
	return true


func count_owned(character_id: String, card_id: String) -> int:
	return collection(character_id).filter(func(o: OwnedCard) -> bool: return o.card_id == card_id).size()


# --- Specializations ------------------------------------------------------------------------------

func unlocked_specializations(character_id: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(unlocked_specs.get(character_id, []))
	return result


## Unlocks a playable specialization and adds its starting cards to the sister's collection.
func unlock_specialization(character_id: String, spec_id: String) -> bool:
	var spec := DataRegistry.get_specialization(spec_id)
	if spec == null or spec.character_id != character_id or not spec.is_playable() or unlocked_specializations(character_id).has(spec_id):
		return false
	var list: Array = unlocked_specs.get(character_id, [])
	list.append(spec_id)
	unlocked_specs[character_id] = list
	for card_id in spec.starting_deck_card_ids:
		add_collection_card(character_id, card_id)
	return true


# --- World, missions, bond ------------------------------------------------------------------------

func is_mission_completed(mission_id: String) -> bool:
	return (missions.get("completed", []) as Array).has(mission_id)


func mark_mission_completed(mission_id: String) -> void:
	var completed: Array = missions.get("completed", [])
	if not completed.has(mission_id):
		completed.append(mission_id)
	missions["completed"] = completed


func add_attempt(mission_id: String) -> void:
	var attempts: Dictionary = missions.get("attempts", {})
	attempts[mission_id] = int(attempts.get(mission_id, 0)) + 1
	missions["attempts"] = attempts


func get_flag(flag: String) -> Variant:
	return (world.get("flags", {}) as Dictionary).get(flag, null)


func set_flag(flag: String, value: Variant) -> void:
	var flags: Dictionary = world.get("flags", {})
	flags[flag] = value
	world["flags"] = flags


## Persistent state of a region: {threat, flags}. Created from the region's defaults on first use.
func region_state(region_id: String) -> Dictionary:
	var regions: Dictionary = world.get("regions", {})
	if not regions.has(region_id):
		var def := DataRegistry.get_region(region_id)
		regions[region_id] = {"threat": int(def.get("threat", 0)), "flags": {}}
	world["regions"] = regions
	return regions[region_id]


func bond_level() -> int:
	return Bond.level_for(int(bond.get("xp", 0)))


func add_stat(key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


func discover_relic(relic_id: String) -> bool:
	if relic_id == "" or relic_collection.has(relic_id) or str(DataRegistry.get_item(relic_id).get("category", "")) != "relic":
		return false
	relic_collection.append(relic_id)
	return true


## Re-applies refinement and worn-equipment Max HP to the roster, and sets every sister to full HP
## (the castle heals everyone between expeditions).
func refresh_roster() -> void:
	Equipment.refinement = refinement
	Requirements.active_campaign = self
	for m in roster.members:
		m.level_max_hp = Levels.hp_bonus(self, m.id)
		m.extra_max_hp = m.level_max_hp
		Equipment.refresh_stats(m)
		m.current_hp = m.max_hp
	Contracts.sync(self)


# --- Saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var members: Array = []
	for m in roster.members:
		members.append(SaveManager.serialize_member(m))
	return {
		"data_version": DATA_VERSION,
		"roster": members,
		"vault": SaveManager.serialize_inventory(vault),
		"prepared": prepared.duplicate(true),
		"presets": presets.duplicate(true),
		"essence": essence,
		"refinement": refinement.duplicate(),
		"relic_collection": relic_collection.duplicate(),
		"heirloom": heirloom,
		"potion_capacity": potion_capacity,
		"capacity_upgrades_bought": capacity_upgrades_bought,
		"recipes": recipes.duplicate(),
		"unlocked_specs": unlocked_specs.duplicate(true),
		"services": services.duplicate(),
		"bond": bond.duplicate(true),
		"fusions_done": fusions_done.duplicate(),
		"world": world.duplicate(true),
		"missions": missions.duplicate(true),
		"stats": stats.duplicate(true),
		"levels": levels.duplicate(),
		"level_rewards": level_rewards.duplicate(true),
		"contracts": contracts.duplicate(true),
	}


## Rebuilds a campaign from save data, dropping anything unknown. Returns null when unusable
## (warnings and the error are appended to `warnings` / result["error"]).
static func from_dict(data: Variant, warnings: Array[String], result: Dictionary) -> CampaignState:
	if not data is Dictionary:
		result["error"] = "The campaign data is damaged."
		return null
	var raw: Dictionary = data
	var campaign := CampaignState.new()
	campaign.refinement = _int_dict(raw.get("refinement", {}))
	Equipment.refinement = campaign.refinement
	campaign.roster = SaveManager.restore_party(raw.get("roster", []), warnings, result, 0)
	if campaign.roster == null:
		return null
	campaign.vault = SaveManager.restore_inventory(raw.get("vault", {}), warnings)
	campaign.vault.relics.clear()  # Relics never sit in the vault: see relic_collection.
	campaign.essence = maxi(0, int(raw.get("essence", 0)))
	for relic_id: Variant in raw.get("relic_collection", []) if raw.get("relic_collection", []) is Array else []:
		campaign.discover_relic(str(relic_id))
	campaign.heirloom = str(raw.get("heirloom", "")) if campaign.relic_collection.has(str(raw.get("heirloom", ""))) else ""
	campaign.potion_capacity = clampi(int(raw.get("potion_capacity", 3)), 1, 10)
	campaign.capacity_upgrades_bought = maxi(0, int(raw.get("capacity_upgrades_bought", 0)))
	campaign.recipes.assign(_strings(raw.get("recipes", [])))
	campaign.services.assign(_strings(raw.get("services", [])))
	campaign.fusions_done.assign(_strings(raw.get("fusions_done", [])))
	campaign.bond = {"xp": maxi(0, int((raw.get("bond", {}) as Dictionary).get("xp", 0)) if raw.get("bond", {}) is Dictionary else 0)}
	campaign.world = raw.get("world", {}) if raw.get("world", {}) is Dictionary else {}
	if not campaign.world.get("flags", null) is Dictionary:
		campaign.world["flags"] = {}
	if not campaign.world.get("regions", null) is Dictionary:
		campaign.world["regions"] = {}
	campaign.missions = raw.get("missions", {}) if raw.get("missions", {}) is Dictionary else {}
	campaign.missions["completed"] = _strings(campaign.missions.get("completed", []))
	if not campaign.missions.get("attempts", null) is Dictionary:
		campaign.missions["attempts"] = {}
	campaign.stats = raw.get("stats", {}) if raw.get("stats", {}) is Dictionary else {}
	# Specializations: always include the sister's current primary (and secondary) so a save stays usable.
	var specs: Dictionary = raw.get("unlocked_specs", {}) if raw.get("unlocked_specs", {}) is Dictionary else {}
	for m in campaign.roster.members:
		var list: Array = []
		for spec_id in _strings(specs.get(m.id, [])):
			var spec := DataRegistry.get_specialization(spec_id)
			if spec != null and spec.character_id == m.id and spec.is_playable() and not list.has(spec_id):
				list.append(spec_id)
		for current in [m.specialization, m.secondary_specialization]:
			if current != null and not list.has(current.id):
				list.append(current.id)
		campaign.unlocked_specs[m.id] = list
	var raw_prepared: Dictionary = raw.get("prepared", {}) if raw.get("prepared", {}) is Dictionary else {}
	for m in campaign.roster.members:
		campaign.set_prepared(m.id, raw_prepared.get(m.id, []) if raw_prepared.get(m.id, []) is Array else [])
		if campaign.prepared_uids(m.id).is_empty():
			warnings.append("%s's prepared deck was empty; her starting deck was restored." % m.definition.display_name)
			campaign.reset_prepared_to_starter(m.id)
	var raw_presets: Dictionary = raw.get("presets", {}) if raw.get("presets", {}) is Dictionary else {}
	for preset_name: String in raw_presets:
		if raw_presets[preset_name] is Dictionary:
			var preset: Dictionary = {}
			for m in campaign.roster.members:
				preset[m.id] = _strings((raw_presets[preset_name] as Dictionary).get(m.id, [])).filter(func(uid: String) -> bool: return m.find_card(uid) != null)
			campaign.presets[preset_name] = preset
	_restore_levels(campaign, raw)
	campaign.refresh_roster()
	return campaign


## Levels, pending Mastery choices and contracts. A save from before levels existed starts each
## sister at the XP her completed missions would have earned.
static func _restore_levels(campaign: CampaignState, raw: Dictionary) -> void:
	if raw.get("levels", null) is Dictionary:
		for m in campaign.roster.members:
			campaign.levels[m.id] = maxi(0, int((raw["levels"] as Dictionary).get(m.id, 0)))
	else:
		var estimate := Levels.estimate_xp(campaign.missions.get("completed", []))
		for m in campaign.roster.members:
			campaign.levels[m.id] = estimate
	for choice: Variant in raw.get("level_rewards", []) if raw.get("level_rewards", []) is Array else []:
		if choice is Dictionary and campaign.member(str((choice as Dictionary).get("character_id", ""))) != null:
			var options: Array = ((choice as Dictionary).get("options", []) as Array).filter(func(id: Variant) -> bool: return DataRegistry.get_card(str(id)) != null)
			if not options.is_empty():
				campaign.level_rewards.append({"character_id": str(choice["character_id"]), "level": int(choice.get("level", 0)), "upgraded": bool(choice.get("upgraded", false)), "options": options})
	var raw_contracts: Dictionary = raw.get("contracts", {}) if raw.get("contracts", {}) is Dictionary else {}
	for region_id: String in raw_contracts:
		if raw_contracts[region_id] is Dictionary and not DataRegistry.get_region(region_id).is_empty():
			var c: Dictionary = raw_contracts[region_id]
			campaign.contracts[region_id] = {"tier": maxi(1, int(c.get("tier", 1))), "kind": str(c.get("kind", "")), "seed": int(c.get("seed", 0))}


static func _strings(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for entry: Variant in raw:
			if not result.has(str(entry)):
				result.append(str(entry))
	return result


static func _int_dict(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in raw:
			if int((raw as Dictionary)[key]) > 0:
				result[str(key)] = int((raw as Dictionary)[key])
	return result
