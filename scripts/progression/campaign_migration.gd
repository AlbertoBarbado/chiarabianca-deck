class_name CampaignMigration
extends RefCounted
## Turns a run saved before the persistent campaign existed (save version 2 or older, no "mode") into
## a campaign (docs/PERSISTENT_RPG_DESIGN.md §7). Nothing is reset:
##  * the sisters keep their specializations; every card of the run deck enters the collection with
##    its upgrade level, and the prepared deck is the starting deck (upgraded copies first);
##  * worn equipment stays worn; relics enter the relic collection; the purse stays with the run;
##  * maps listed in run_flags.completed_maps complete the missions that use them ("legacy_map"), so
##    the regions after them are open;
##  * the run itself continues as an expedition of the mission for its current map, and returns to
##    the castle when it ends.


## restored: the result of SaveManager.restore. Returns {campaign, expedition}.
static func from_legacy_run(restored: Dictionary) -> Dictionary:
	var run_party: Party = restored["party"]
	var run_inventory: Inventory = restored["inventory"]
	var progress: MapProgress = restored["progress"]
	var flags: Dictionary = restored.get("flags", {})
	var selection := {}
	for m in run_party.members:
		selection[m.id] = m.specialization.id
	var campaign := CampaignState.create(selection)
	# The collection: every card of the run (uids kept so the expedition copies line up).
	for m in run_party.members:
		var home := campaign.member(m.id)
		if home == null:
			continue
		home.deck.clear()
		for owned in m.deck:
			var copy := OwnedCard.create(owned.uid, owned.card_id, m.id)
			copy.upgrade_level = owned.upgrade_level
			home.deck.append(copy)
		home.next_card_serial = maxi(home.next_card_serial, m.next_card_serial)
		home.equipment = m.equipment.duplicate()
		campaign.reset_prepared_to_starter(m.id)
	for relic_id in run_inventory.relics:
		campaign.discover_relic(relic_id)
	for map_id: Variant in flags.get("completed_maps", []):
		var mission_id := mission_for_map(str(map_id))
		if mission_id != "":
			campaign.mark_mission_completed(mission_id)
	campaign.refresh_roster()
	var expedition := ExpeditionState.new()
	expedition.mission_id = mission_for_map(progress.graph.id)
	var mission := DataRegistry.get_mission(expedition.mission_id)
	expedition.region_id = str(mission.get("region_id", ""))
	expedition.objective = Objectives.create(mission, DataRegistry.get_map(progress.graph.id))
	for m in run_party.members:
		expedition.departure_uids[m.id] = m.deck.map(func(o: OwnedCard) -> String: return o.uid)
	campaign.add_attempt(expedition.mission_id)
	return {"campaign": campaign, "expedition": expedition}


## The mission that plays this map ("legacy_map" or its fixed map), or "".
static func mission_for_map(map_id: String) -> String:
	DataRegistry.ensure_loaded()
	for mission: Dictionary in DataRegistry.missions.values():
		if str(mission.get("legacy_map", "")) == map_id:
			return str(mission["id"])
	for mission: Dictionary in DataRegistry.missions.values():
		if str((mission.get("map", {}) as Dictionary).get("map_id", "")) == map_id:
			return str(mission["id"])
	return ""
