class_name GameConfig
extends RefCounted
## Tunable global constants. Content-specific values belong in data/ instead.

const INITIAL_PARTY_IDS: Array[String] = ["chiara", "bianca"]
const DEFAULT_MAP_ID := "royal_castle_tutorial"
const STARTING_GOLD := 30
## Fraction of max HP restored by a rest room unless the node overrides "heal_percent".
const DEFAULT_REST_HEAL_FRACTION := 0.3
## HP given to fallen party members when a combat is won.
const FALLEN_REVIVE_HP := 1
const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"
