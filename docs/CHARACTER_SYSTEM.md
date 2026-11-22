# Character System

Data strategy: JSON files in `data/<category>/`, loaded by `DataRegistry` into typed RefCounted definitions (`CharacterDef`, `SpecializationDef`, `CardDef`, `EnemyDef`). Dropping a new JSON file in a folder registers it; no code change needed. (Exported builds must include `*.json` in the export filter.)

Static vs runtime: definitions (`*Def`) are read-only. Runtime state is `Party` > `PartyMember` (HP, chosen specialization) > `OwnedCard` (uid, card_id, owner_character_id, upgrade_level). Combat copies owned cards into `CardInstance`s.

Extensions to the supplied pack data (project copy only; `assets_pack/` is untouched): `ui.accent_color` on characters; `starting_deck_card_ids` + `"status": "playable"` for Arcana and Tanking. Specialization `display_name`/`description` default to the capitalised id / `identity`.
Passives and skill trees are still design templates.

## Milestone 2: progression
- **Card rewards** (`scripts/progression/card_reward.gd`): after a won combat `GameState.prepare_card_reward()` rolls 3 distinct cards, weighted by rarity, from the `card_pool` of every party member's selected specialization. The player takes one (added to the owner's `PartyMember.deck` as a new `OwnedCard`) or skips. A reward resolves only once, and an option whose card is not in its owner's pool is rejected. Pools live in `data/specializations/*.json`; the new Arcana/Tanking pool cards are in `data/cards/arcana_pool_cards.json` and `tanking_pool_cards.json`.
- **Unique ids**: each copy has its own `OwnedCard.uid` (minted per member, collision-proof) and each combat `CardInstance` its own `instance_id`, so duplicate card ids never clash.
- **Upgrades** (`scripts/progression/card_upgrader.gd`): data-driven by the card's `upgrade` block (`name`, `cost`, `description`, `effects`, optional `max_level`, default 1). Applying one raises `OwnedCard.upgrade_level` of a single copy; `CardInstance` reads it, so it persists across combats and saves. Rest rooms allow the heal AND one upgrade (design choice; change in `rest_room_screen.gd` if it should be either/or). The supplied placeholder upgrades of the 8 starter cards were filled in with real values in the project copy.
- **Save/load** (`scripts/core/save_manager.gd`, `GameState.save_game/load_game`): JSON at `user://savegame.json`, version field (`SAVE_VERSION`, `_migrate()` hook), atomic write via temp file. Only ids and player progress are stored (no static stats), so balance changes apply to old saves. Restore validates: unknown cards/items dropped with warnings, HP/gold/upgrade levels clamped, duplicate or missing uids repaired, empty decks refilled with the starting deck, and unusable saves (wrong-character specialization, unknown map or node, newer version, corrupt JSON) rejected with a message while the file is kept.
- **Autosave** happens whenever the map screen opens (between rooms), so Continue always resumes at a room boundary; progress inside a room is not saved. A finished run (exit or defeat) deletes the save.

## Milestone 3: Fire and Holy

Both specializations are `"status": "playable"` and fully data-driven (`data/specializations/chiara_fire.json`, `bianca_holy.json`, cards in `data/cards/fire_cards.json`, `holy_cards.json`). New optional specialization fields: `display_name`, `description`, `keywords` (status ids explained on the selection screen), and a structured `starting_passive` (see COMBAT_SYSTEM.md). Specializations without a real passive keep their TODO placeholder (`has_passive()` is false).

Interpretation: each specialization has 3 basic starter card types (10-card deck) plus the 6 reward-pool cards required by the brief (the "six initial cards"); starters are never offered as rewards.

| | Fire (Chiara) | Holy (Bianca) |
|---|---|---|
| Starter (4/3/3) | Ember Bolt 6 dmg, Cinder Ward 5 Block, Kindle 3 Burn | Radiant Strike 6, Blessed Shield 5 Block, Soothing Touch heal 5 |
| Pool | Fireball (2, 10 dmg), Immolate (3 dmg + 3 Burn), Fuel the Flames (5, +6 vs Burning), Flame Wave (4 to all), Smoke Screen (7 Block + draw), Inferno (3 energy, 20 dmg + 3 Burn) | Mending Light (heal 10), Sanctified Ward (9 Block), Smite (9), Radiant Bulwark (3 + Block as damage), Benediction (party 5 Block + heal 3), Divine Judgment (3 energy, 18 dmg + party heal 5) |
| Passive | Kindled Spark | Blessed Aegis |

All 18 cards have `upgrade` data (max_level 1). Saves need no migration: they store only specialization ids and card ids, validated against the registry (Milestone 1/2 saves still load).

Placeholder balance (untuned): all numbers above, Burn tick 2, passive bonuses 2, card rarities.


## Presentation (Milestone 4)
Characters and specializations are never duplicated for art. `data/art/art_catalog.json` maps a character to its portrait/figure; a specialization may carry presentation-only data:

```json
"visual": {"accent": "#ee7a3c", "icon": "icon_fire"}
```

`SpecializationDef.accent_color` / `icon_id` (with `get_accent(fallback)`) feed `PortraitView` (accent frame, tint, bottom glow on figures, badge), `CharacterPanel`, `CardView` (spec icon in the owner banner) and the selection screens. Arcana = violet swirl, Fire = orange flame, Tanking = steel shield, Holy = gold star. Specializations without a `visual` block use the character colour and show no badge. The art itself is shared per character (one portrait per princess); only frame, tint and badge change with the specialization.


## Passives added in Milestone 7
Both passives use the existing `PassiveRunner` (data in `starting_passive`, once per turn, no recursion, fallen owners never trigger, bonus effects emit no passive events).

**Chiara, Arcana: Arcane Flow.** Event `card_played`. When Chiara plays a card right after a card owned by Bianca, the party draws 1 extra card (effect `draw_cards`). Once per player turn. Chiara after Chiara, or the first card of the turn, never triggers it; the extra draw is not a card played. Rewards sequencing and cross-character play. Visual: a `draw` visual event with Chiara as source.

**Bianca, Tanking: Bulwark Stance.** Event `attack_absorbed` (an enemy attack on Bianca that deals no HP damage because her Block absorbed it all; emitted by `CombatManager` after the attack resolves). The attacker gets Taunt 2 (it must attack Bianca on its next action; effect `taunt_attacker`). Once per round (the counter resets at the start of each player turn). Attacks that get through, or hit Chiara, do not trigger it. Rewards using Block and controlling enemy targeting. Visual: an `apply_status` (taunt) event on the enemy.

New passive trigger keys: `played_by`, `after_other_owner`; new events `card_played` (with `previous_owner_id`) and `attack_absorbed`; new effects `draw_cards`, `taunt_attacker`. Passive state is not saved (it is rebuilt from the specialization every combat). Both appear in the combat unit panel as "<name>: ready / used this turn".


## Frost (Chiara)
`data/specializations/chiara_frost.json`, cards in `data/cards/frost_cards.json` (+2 epics in `epic_cards.json`). Damage type frost.
- **Passive, Rime Touch:** the first time Chiara applies Chill each turn, the target gains 1 extra Chill. This is the new passive effect `extra_status`.
- **Starter (10 cards):** Frost Bolt x4 (5 damage + 1 Chill), Ice Ward x3 (5 Block), Chilling Touch x3 (2 Chill).
- **Reward pool:** Glacial Spike, Frost Nova, Cold Snap, Shatter (damage per Chill, then removes it), Blizzard, Rime Shell, Frostbrand (Chill + party Block), Absolute Zero, Glacier.
- **Epics:** Avalanche and Frozen Heart.
- **New effect keys:** `per_target_status` (extra damage per stack) and `consume_status`.
- **Presentation:** card art, three cast cut-ins (tiers 2-4) and spell effects (ice spear, frost nova, ice prison for Frozen) were generated locally with ComfyUI (`assets/generated/frost/`). Chill has its own snowflake chip.

## Equipment
- **Slots:** helmet, amulet, chest, gauntlets, weapon, belt, two rings and boots (`Equipment.SLOTS`). Every slot has items (`data/items/equipment.json`, `"category": "equipment"`): 59 in all.
- **Specialization gear:** `"specializations": [ids]` limits an item to wearers with one of those specializations (an empty list means anyone). Weapons ask for the specializations whose damage type they raise: a Fire staff needs Fire Chiara. `Equipment.can_equip` explains the refusal ("Ember Staff needs Fire.").
- **Item effects:** `"effects"` are passives in the `PassiveRunner` format (`trigger`, `effect`, `limit_per_turn`, `limit_per_combat`, plus a player-facing `text`). `PassiveRunner.setup` registers every worn item's effects for its wearer after her specialization passive (`Equipment.passives`). The equipment screen, tooltips, the shop and the reward screen show them as "✦" lines in jade.
  - Triggers added for gear: `turn_start` (`turn`: N, `every`: N) and `enemy_killed` (Poison, Burn and Blight kills count for whoever applied the status). `card_played` also takes `card_type`.
  - Effects added for gear: `gain_energy`, `gain_aether`, `party_block`, `heal_party`, `apply_status_all`, `damage_all`, `status_to_target`; `bonus_damage` takes an `element`.
- **Item stats:** `max_hp`, `resist` {type: %} or `damage` {type: %}. Each item has at most one resistance or one damage type, at most 30%, and at most +6 HP. Weapons have a `wielder`: staffs are Chiara's, swords Bianca's. Armour can be worn by anyone.
- **Runtime:** worn items are in `PartyMember.equipment` (slot -> id) and the stash in `Inventory.equipment`. `Equipment.equip / unequip` swap items, and `refresh_stats` applies Max HP: raising it also raises current HP, lowering it only clamps, and armour never revives a fallen member. Both are saved; invalid entries are dropped with warnings on load.
- **Combat:** `CombatManager.setup` turns the totals into `Combatant.affinity` (resistances) and `damage_bonus`.
- **Loot:** see the `loot` block in `data/progression/run_rules.json`.
  - Normal fights drop an item 15% of the time, elites 75%, bosses always (mostly rare). The rates were halved when every drop became usable.
  - Only items somebody in the party can use **as she is** drop: right princess and right specialization (`Equipment.usable_by_party`, used by `Loot.pick`). A Fire staff never drops for an Arcana Chiara.
  - Shops leave out gear the party cannot use and add 1 gear offer it can use per visit (`loot.shop` in run_rules, or `"gear_offers"` in a shop definition), rolled from the visit's saved seed.
  - The drop is rolled once in `GameState.record_combat_victory`, stored in the room state (`loot`) and shown on the reward screen.
  - Every chest also offers one piece of equipment (treasure choice type `equipment`).
- **Screen:** `scenes/menus/equipment.tscn`, opened from the map, the town and the reward screen.
  - **Character:** her idle pose on a lit stage (`DollStage`: an aura in her specialization colour and a gold pedestal) between her nine slots. Her HP bar and her bonuses as coloured chips (Max HP, damage, resistances, immunities) sit underneath.
  - **Tiles (`ItemTile`):** drawn sockets with a rarity glow, frame and corner gem. Empty slots show a faint engraved glyph of what goes there (`assets/generated/ui/slot_*.png`; the slot name when the glyph is missing). Hovered or selected tiles lift slightly.
  - **Stash:** a grid of sockets (at least 15, so it reads as a bag), best rarity first. Filters: All / Weapons / Armour / Trinkets. The count is in the title.
  - **Item card:** picture, rarity and slot, stats, and a comparison with what she wears in that slot (▲ green gains, ▼ red losses; `Equipment.compare`), flavour text, then Equip on Chiara / Equip on Bianca or Unequip.
  - **Drag and drop:**
    - Stash item onto a slot, onto her stage or onto a character tab: equips it.
    - Worn item onto the stash: unequips it.
    - A ring onto the other ring slot: moves or swaps it (`Equipment.move_worn`).
    - While an item is carried, the places that take it pulse gold and the others dim; the slot that receives it pops.
  - **Input:** everything also works by tap or click (select, then use the card's buttons), so touch screens never need a drag.
  - **Tests:** `tests/progression/equipment_frost_test.tscn` (tap flow, phone layout) and `tests/ui/inventory_drag_test.tscn` (real mouse drags, highlights, refusals, ring move, unequip by drop, comparison, filters, save).


## Gear for every slot
Ideas taken from the kinds of relics in Slay the Spire 2 (energy every few turns, extra draw at the start of a battle, payoffs on the Nth card of a turn or when a foe falls, opening debuffs), turned into equipment that feeds each specialization and its twin combos.

| Specialization | Items (slot) | What they do |
|---|---|---|
| Anyone | Hourglass Amulet, Alchemist's Bandolier, Twinbond Ring, Victor's Signet; Spellweaver Gloves (Chiara) | +1 Energy every 3rd turn; +1 Energy on turn 1; draw 1 when a card follows the other sister's; draw 1 on a kill; the 3rd card each turn draws 1 |
| Anyone (plain stats) | Iron Sallet, Amber Amulet, Leather Bracers, Sturdy Belt, Copper Ring, Traveling Boots | Max HP and small resistances |
| Arcana | Seer's Circlet, Ley Pendant, Arcanist's Ring | draw 2 at the start (makes Aether); +1 Aether each turn; draw 1 every 2nd turn. All feed Holy's hymns |
| Fire | Ember Crown, Kindling Sash, Cinderheart Ring | 2 Burn on all at the start; 3 Burn on all every 3rd turn; +1 Burn on the first Burn each turn |
| Frost | Rimefrost Hood, Frostbite Band, Glacier Greaves | 2 Chill on all at the start; 3 Block on the first Chill each turn; 1 Chill on all every 2nd turn |
| Wind | Galeplume Helm, Storm Grips, Windstep Boots, Tempest Ring, Gale Staff | a Gust every 2nd turn; the 5th card each turn refunds 1 Energy; 2 Gusts at the start; 2 Gusts on a kill; +15% wind |
| Tanking | Bastion Greathelm, Shieldbearer Gauntlets, Rampart Sabatons | 10 Block at the start; 3 Block when Block stops a whole attack; 3 Block each turn |
| Holy | Sunlit Reliquary, Pilgrim's Girdle, Dawnwalker Sabatons | the first Attack each turn heals the party 1; the party heals 3 every 3rd turn; +1 Aether every 2nd turn |
| Ashveil | Powder Belt, Cinderfist Gauntlets, Smokeveil Hood | 2 Oiled on all at the start (Fire and Wind partners profit); 4 Fire damage on the first Oiled each turn; 4 Block on the 3rd card each turn |
| Venom | Plague Mask, Catalyst Locket, Venomfang Ring, Plaguewalker Boots, Venom Kris | 3 Poison on all at the start (and immunity to Poison); 2 Blight with the first Poison each turn; 2 Poison on all on a kill; 4 Poison on all every 3rd turn; +15% poison |

- **Art:** `assets/generated/gear/` (ComfyUI group `gear`, seeds 7001-7039), not release-cleared.
- **Tests:** `tests/progression/run_gear_tests.gd` (data, specialization-only drops, shop filtering and offers, every kind of effect in a real battle).


## Coast equipment (Act III)
- **Armour:** Coral Mail (water 30%), Sandstone Cuirass (earth 30%), Kelpwoven Coat (rare: water 15%, immune to Soaked) and Dunewalker Wraps (rare: earth 15%, immune to Sandblind).
- **Weapons:** the Tidecaller Staff (Chiara, rare, +20% frost) and the Coralsteel Sabre (Bianca, uncommon, +15% holy).
- **Balance rule:** at most one resistance, one damage type and one immunity per item.
- **Where they come from:** like all equipment, they drop from fights and chests. The coast shops also sell some of them, and two events give them.


## Bianca: Ashveil (replaces Duelist)
- **Identity:** a knight who fights like a rogue: oil, black powder, smoke and traps. Data: `data/specializations/bianca_ashveil.json`. The Duelist template file is removed.
- **Damage type:** physical by default. Shadow Thrust deals Shadow; Blasting Powder, Ignition Strike and Ashfall deal Fire.
- **Passive, Slick Tricks:** the first time Bianca applies Oiled each turn, she gains 3 Block.
- **Starting deck:** 4 Ashen Slash (6 damage), 3 Smoke Veil (5 Block), 3 Oil Flask (3 damage, 2 Oiled).
- **Reward pool** (`data/cards/ashveil_cards.json`):

  | Card | Cost | Rarity | Effect |
  |---|---|---|---|
  | Pitch Dagger | 0 | common | 3 damage, 1 Oiled |
  | Caltrops | 1 | common | 1 Oiled and 1 Bleed to all |
  | Shadow Thrust | 1 | common | 6 Shadow, +5 if Oiled |
  | Smoke Bomb | 1 | uncommon | party 4 Block, draw 1 |
  | Tar Snare | 1 | uncommon | 2 Oiled, 6 Block |
  | Blasting Powder | 2 | uncommon | 7 Fire to all, +4 to Oiled |
  | Shadowstep | 0 | uncommon | 4 Block, draw 1 |
  | Ignition Strike | 2 | rare | 9 Fire, +4 per Oiled, consumes the oil |
  | Greasefire Trap | 2 | rare | 2 Oiled and 2 Burn to all |

- **Epics** (`epic_cards.json`):
  - **Ashfall (3):** 3 Oiled to all, then 10 Fire to all.
  - **Veil of Ash (2):** party 8 Block, 2 Oiled to all, draw 2.
- **Look in combat:** Bianca has her own Ashveil pose set (`combat_presentation.json` `character_variants.bianca.ashveil`), cut from the owner-provided sheet `assets/characters/bianca/ashveil_bianca.jpg` by `scripts/tools/cut_pose_sheet.py`. That script runs BiRefNet through the local ComfyUI, trims each pose and gives all poses one shared scale, so the idle is 357 px tall like her paladin idle. The cut sprites are in `assets/characters/bianca/ashveil/`. Venom reuses the same set (`character_variants.bianca.venom`), so a plague knight Bianca wears the Ashveil gear.
  - Poses used: idle (flask in hand), attack (lunging slash), block (dagger guard), cast (throw), hit (turning into the cloak), down (kneeling). The map-reading and pouch poses are cut but unused.
  - Combatants carry `specialization_id`, so `CombatPresentation.character_state(id, state, specialization_id)` picks the variant. Other specializations keep the paladin look.

## Arcana + Holy: the Aether combo
Each Chiara and Bianca pair has its own combo. Frost Chill opens enemies to Tanking's physical hits. Ashveil Oil makes them burn for Fire. Arcana feeds Holy with **Aether** (rules in COMBAT_SYSTEM.md).
- **Arcana builds Aether.** Every extra card Chiara conjures and every Energy she gains is 1 Aether this turn. Arcane Flow (Bianca's card, then Chiara's) draws a card, which is Aether too, so alternating the sisters pays twice.
- **Holy spends it.** Bianca's hymns grow with Aether. Lightfall and Wellspring Prayer release all of it for a big finisher.
- **Starting decks:**
  - Arcana: 3 Arcane Bolt, 1 Ley Siphon, 3 Arcane Ward, 2 Gathering Focus, 1 Mana Surge.
  - Holy: 4 Radiant Strike, 1 Hymn of Dawn, 3 Blessed Shield, 2 Soothing Touch.
- **New cards** (the art is in `assets/generated/aether/`):

  | Card | Cost | Rarity | Effect | Upgrade |
  |---|---|---|---|---|
  | Ley Siphon (Arcana) | 1 | common | 5 damage, draw 1 | 8 damage |
  | Arcane Echo (Arcana) | 1 | uncommon | +1 Energy, draw 2, exhaust (3 Aether) | costs 0 |
  | Leyline Weave (Arcana) | 2 | rare | +2 Energy, draw 2 (4 Aether) | draw 3 |
  | Aether Lance (Arcana) | 1 | uncommon | 6 damage, +2 per Aether | 9, +3 |
  | Hymn of Dawn (Holy) | 1 | common | 4 damage, +1 per Aether | 5, +2 |
  | Radiant Cascade (Holy) | 1 | uncommon | 2 to all, +1 per Aether | 3, +2 |
  | Lightfall (Holy) | 2 | uncommon | 6 damage, +3 per Aether, releases it | 9, +4 |
  | Wellspring Prayer (Holy) | 1 | rare | party 3 Block +2 per Aether, releases it | 5 Block, +3 |

- **A typical combo turn:**
  1. Bianca plays Blessed Shield.
  2. Chiara plays Gathering Focus: 1 Aether, and Arcane Flow draws another (2).
  3. Chiara plays Mana Surge: +2 Energy (4).
  4. Bianca plays Lightfall for 6 + 12 = 18 damage.


## Chiara: Wind
- **Identity:** speed and flow. Data: `data/specializations/chiara_wind.json`; cards: `data/cards/wind_cards.json`. Damage type Wind, accent jade.
- **Passive, Tailwind:** the third card the party plays each turn (either princess's) adds a Gust to the hand. Once per turn.
- **Gust (token):** costs 0 and deals 4 damage. It vanishes when played or at the end of the turn.
- **Starting deck:**
  - 4 Gale Bolt: 6 damage.
  - 3 Zephyr Ward: 5 Block.
  - 3 Flurry: add 2 Gusts.
- **Rewards:**
  - Razor Wind (0): 2 damage, draw 1.
  - Tempest Blades (1): 2 damage, three times.
  - Updraft (1): 5 Block and a Gust.
  - Tailwind Barrier (1): party 3 Block, +1 per card already played.
  - Cyclone (1): 2 damage to all, +1 per card already played.
  - Scatter (1): 3 damage, and spreads half of the target's debuffs to every other enemy.
  - Slipstream (0): +1 Energy and a Gust; exhaust.
  - Whispering Draft (1): draw 2 and a Gust.
  - Gale Force (2, rare): 6 damage, +3 per card already played.
  - Eye of the Storm (2, rare): 4 Gusts.
- **Epics:**
  - Hurricane (3): 3 damage to all, four times.
  - Sky Dancer (1): +2 Energy and 3 Gusts.

## Bianca: Venom (replaces Vanguard)
- **Identity:** a plague knight. Data: `data/specializations/bianca_venom.json`; cards: `data/cards/venom_cards.json`. Damage type Poison, accent toxic green. The Vanguard template file is removed.
- **Passive, Lingering Venom:** the first time each turn Bianca adds Poison to an already Poisoned enemy, it gains 2 extra.
- **Starting deck:**
  - 4 Venom Strike: 6 damage, 1 Poison (upgraded 8 and 2).
  - 3 Toxic Guard: 6 Block.
  - 3 Envenom: 3 Poison (upgraded 5).
- **Rewards:**
  - Noxious Cut (0): 2 damage, 2 Poison.
  - Toxic Cloud (1): 2 Poison to all.
  - Corrode (1): 5 damage, +1 per Poison.
  - Septic Strike (1): 6 damage, +4 if Poisoned.
  - Miasmic Veil (1): 6 Block, 1 Poison to all.
  - Catalyst (1): double the target's Poison; exhaust.
  - Mark of Blight (1): 10 Blight.
  - Distilled Venom (1): 3 Poison, +1 per Aether.
  - Plague Reaping (2, rare): Blight equal to 3 times the target's Poison.
  - Virulent Bloom (2, rare): 3 Poison and 6 Blight to all.
- **Epics:**
  - Pestilence (3): 6 Poison and 10 Blight to all.
  - Death's Ledger (2): double every enemy's Poison.

## Cross-combo cards in the other pools
- **Tanking:**
  - Runic Bastion: Block, +2 per Aether (Arcana).
  - Momentum Bash: 5 damage, +3 per card already played (Wind).
  - Branding Bash: +4 against Burning foes (Fire).
- **Holy:**
  - Sunfire Smite: +3 against Burning or Chilled foes (Fire, Frost).
  - Psalm of Wings: party Block, +1 per card already played (Wind).
- **Ashveil:** Hexed Powder: Fire to all, +1 per Aether (Arcana).
- **Fire:**
  - Flashpoint: 4 damage, twice.
  - Wildfire: 5 damage and 1 Burn to all.
  - Ember Volley: 2 damage, three times.

  These multi-hit and all-enemy cards set off Combustion, Searing Bash and Purifying Flame on more targets.

## Twin combo matrix (`data/combat/twin_combos.json`)
| Chiara \ Bianca | Tanking | Holy | Ashveil | Venom |
|---|---|---|---|---|
| Arcana | ★★ Runic Wall (Aether) | ★★★ Aether Hymns | ★★ Hexed Powder (Aether) | ★★ Distilled Venom (Aether) |
| Fire | ★★ Searing Bash | ★★ Purifying Flame | ★★★ Ignition (Oiled) | ★★★ Combustion |
| Frost | ★★★ Brittle (Chill) | ★★ Shatterlight | ★★ Black Ice | ★★ Frostbite |
| Wind | ★★ Momentum | ★★ Psalm of Wings | ★★ Fanned Oil | ★★★ Miasma |

On the selection screen, each specialization lists its combos with the other princess's specializations. The footer names the combo of the chosen pair.

## Campaign: collection, prepared decks and hybrid specializations

- **Collection:** in a campaign each roster sister's `deck` is her permanent collection (every copy she
  owns, with its permanent upgrade level). `CampaignState.prepared` lists the uids she takes on the
  next expedition; presets save whole configurations. Expedition copies share uids and upgrades but
  never write back (rest-site upgrades and drafted cards are temporary).
- **Deck rules** (`DeckRules`, `campaign_rules.json` "deck"): 8-15 cards per sister, copies capped by
  rarity (basic 4, common 3, uncommon / rare 2, epic / fusion 1), cards must be hers and of her primary
  or secondary specialization, at most 4 secondary cards.
- **Specializations:** a new campaign knows the two chosen primaries. The Training Hall (opens after
  the Forest Serpent) teaches other playable specializations for gold (their starting cards join the
  collection) and sets primary and secondary. Only the primary passive runs; the secondary pool
  appears in rewards at half weight (`CardReward.generate`). Worn items that require a specialization
  follow the primary. Twin combos stay keyed by the primaries.
- **Permanent upgrades** (Upgrade Workshop): one collection copy per purchase, priced by rarity;
  the card's existing `upgrade` block is used (branching upgrades are not implemented yet).
- **Fusion** (Enchanter, Sister Bond 2+): `data/fusion/recipes.json`, results in
  `data/cards/fusion_cards.json` (rarity `fusion`). Four recipes: Purifying Flame (Fire + Holy),
  Frozen Bastion (Frost + Tanking), Venom Cinder (Fire + Venom), Aether Aegis (Arcana + Holy).
- **Sister Bond** (`data/progression/bond.json`): 5 levels. XP from completed expeditions (4),
  other returns (1), bosses (2), twin reactions (1 each, max 3 per expedition) and bond event choices
  (1, max 2). Unlocks: the Enchanter and recipes, and bond relics carried on every expedition
  (Sisters' Rhythm, Shared Heartbeat, Twin Stars).
