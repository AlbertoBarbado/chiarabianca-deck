class_name Requirements
extends RefCounted
## One shared unlock-requirement format for regions, missions, castle services, recipes and items:
##   {"missions": [ids]       every mission completed at least once
##    "flags": {flag: value}  world flags equal to these values (true / numbers / strings)
##    "bond_level": n         Sister Bond at least n
##    "level": n              party level at least n (Levels.party_level)
##    "services": [ids]       castle services open}
## An empty requirement is always met.

## The loaded campaign, for pure rules that gate content by world state without reaching for the
## GameState autoload (equipment drops). Set by CampaignState.refresh_roster; null in Quick Play.
static var active_campaign: CampaignState = null


static func met(campaign: CampaignState, requirement: Variant) -> bool:
	return missing(campaign, requirement).is_empty()


## Player-facing descriptions of what is still missing ([] = met).
static func missing(campaign: CampaignState, requirement: Variant) -> Array[String]:
	var result: Array[String] = []
	if not requirement is Dictionary or campaign == null:
		return result
	var req: Dictionary = requirement
	for mission_id: Variant in req.get("missions", []):
		if not campaign.is_mission_completed(str(mission_id)):
			result.append("Complete \"%s\"" % str(DataRegistry.get_mission(str(mission_id)).get("name", mission_id)))
	var flags: Dictionary = req.get("flags", {}) if req.get("flags", {}) is Dictionary else {}
	for flag: String in flags:
		if campaign.get_flag(flag) != flags[flag]:
			result.append(str(req.get("flag_hint", "Something in the world must change first")))
			break
	if int(req.get("level", 0)) > Levels.party_level(campaign):
		result.append("Party level %d" % int(req["level"]))
	if int(req.get("bond_level", 0)) > campaign.bond_level():
		result.append("Sister Bond level %d" % int(req["bond_level"]))
	for service_id: Variant in req.get("services", []):
		if not campaign.services.has(str(service_id)):
			result.append("Open the %s" % str(DataRegistry.get_service(str(service_id)).get("name", service_id)))
	return result
