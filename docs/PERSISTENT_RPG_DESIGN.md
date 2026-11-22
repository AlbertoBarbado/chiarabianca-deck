# Persistent RPG & Expedition Roguelite — Design and Architecture

Status: first implementation complete (2026-11-22), see §11. This document is the source of truth
for the castle / campaign / expedition loop. Combat rules stay in COMBAT_SYSTEM.md, maps in
MAP_SYSTEM.md, characters in CHARACTER_SYSTEM.md.

---

## 1. Audit of the game before this milestone

### 1.1 Architecture (unchanged foundations)

| Layer | Where | Notes |
|---|---|---|
| Static content | `data/**.json`, loaded by `DataRegistry` | characters, 12 specializations (8 playable), ~250 cards, enemies, encounters, maps + layouts, events, shops, towns, treasure, items (61 equipment, 23 relics, 2 potions), statuses, reactions, twin combo guide, run rules |
| Runtime party | `Party`, `PartyMember`, `OwnedCard` | each sister owns her deck (uid, card_id, upgrade_level); worn equipment per slot |
| Run inventory | `Inventory` | gold, consumables, relics, equipment stash |
| Map | `MapGraph` (static), `MapProgress` (position, visited), `MapLayout` (presentation) | all maps are handcrafted graphs; maps without a layout file use node `position` |
| Combat | `CombatManager`, `PartyDeck`, `CardEffects`, `PassiveRunner`, `Reactions`, `EnemyAI` | independent of UI; UI listens to `visual_event` |
| Global run state | `GameState` autoload | party, inventory, map progress, room state, pending reward, run flags |
| Saving | `SaveManager` (v2) | one JSON file, temp-file + backup writes, validation of every id, room-state resume, reward-phase idempotency |
| Screens | `SceneRouter` autoload + `ScreenBase` subclasses | one host, fade transitions, `UIFactory` / `UITheme` / components |

### 1.2 Loop before this milestone

Main menu → choose a specialization per sister → party overview → map → rooms (combat, elite, event,
rest, merchant, treasure, town, boss) → exit. The normal run chains three acts in
`run_rules.acts.order` (Royal Castle → Enchanted Forest → Sunlit Coast); Frostpeak and two demo
routes are standalone maps started from the main menu. A finished run deletes the save; nothing
carries over.

### 1.3 System status

| System | Status |
|---|---|
| Combat engine, statuses, damage types, reactions, passives, powers, X cost, retain | complete |
| Specializations | 8 playable (Fire, Frost, Arcana, Wind / Holy, Tanking, Venom, Ashveil); Earth, Lightning, Retribution, Commander are design templates |
| Sister synergies | 8 twin reactions (`reactions.json`), combo guide for every playable pair (`twin_combos.json`), reaction pop-ups in combat |
| Card rewards, upgrades (rest, merchant), removal | complete, run-only |
| Equipment (9 slots, passives, drag and drop screen) | complete, run-only |
| Relics (23, elite/boss/chest rewards) | complete, run-only |
| Potions | 2 heal potions, usable in combat; no capacity |
| Events, merchants, towns, treasure | complete, run-only |
| Maps | 4 adventure maps + 2 demos, all fixed graphs |
| Saves | v2, single run |
| Tests | 18 headless suites + 25 windowed walkthroughs (see §9) |

---

## 2. New loop

```
Castle hub ─► World map ─► Region ─► Mission ─► Preparation ─► Expedition ─► Results ─► Castle hub
   ▲  services: Deck Workshop, Armory, Upgrade Workshop, Enchanter,                    │
   │  Apothecary, Training Hall, Sisters, Collection                                    │
   └────────────────────────────────────────────────────────────────────────────────────┘
```

* **New Campaign**: pick a primary specialization for each sister (existing selection screen) →
  the castle. The campaign holds everything permanent.
* **Expedition**: the existing run (map, rooms, combat, rewards) wrapped in a mission. It ends by
  completing the objective, retreating, or defeat; every ending goes to the Results screen and back
  to the castle. Nothing restarts automatically.
* **Quick Play** (kept): the main menu's direct starts (Forest, Coast, Frostpeak, the two demo
  routes) still start a classic standalone run without a campaign, saved in a separate file. This
  keeps every existing map and test path working and is useful for balance testing.

---

## 3. State split

### 3.1 Campaign state (`CampaignState`, persistent)

| Field | Meaning |
|---|---|
| `roster: Party` | the sisters at home: primary + secondary specialization, worn equipment, **collection** (their `deck` array = every permanent card copy they own) |
| `prepared` | per sister: list of collection uids forming the prepared deck |
| `presets` | named saved deck configurations (same shape as `prepared`) |
| `treasury` | gold at the castle (the only gold currency) |
| `essence` | Starlight Essence: rare material for fusion and rare brews (the only extra resource) |
| `stash` | unworn equipment (item ids) |
| `refinement` | item id → refinement level (Blacksmith equipment upgrades) |
| `relic_collection` | relics discovered at least once (unlocks for the heirloom slot) |
| `heirloom` | the one relic carried into the next expedition ("" = none) |
| `potions` | potion id → count in the castle stores |
| `potion_capacity` | how many potions an expedition may carry |
| `recipes` | unlocked apothecary recipe ids |
| `unlocked_specs` | sister → playable specialization ids she may use |
| `services` | unlocked castle services |
| `bond` | `{xp, level}` + per-expedition counters |
| `fusions_done` | fusion recipe ids already crafted (non-repeatable recipes) |
| `world` | `{flags: {}, regions: {region_id: {threat, flags}}}` |
| `missions` | `{completed: [], attempts: {id: n}}`; unlocks derive from data + flags |
| `stats` | expeditions started / completed / retreated / defeated |

### 3.2 Expedition state (temporary)

The pre-milestone run state, unchanged in shape: `GameState.party` (copies of the roster made at
departure), `inventory` (purse gold, carried potions, expedition relics, found equipment),
`map_progress`, `room_state`, `pending_reward`, `run_flags`, plus `GameState.expedition`
(`ExpeditionState`): mission id, region id, seed, the generated map graph, objective progress,
discoveries (cards drafted), bond events, outcome, and `rewards_claimed`.

### 3.3 What returns home (data: `data/progression/campaign_rules.json` → `outcomes`)

| | Completed | Retreated | Defeated |
|---|---|---|---|
| Purse gold → treasury | 100% | 50% | 25% |
| Mission rewards (gold, essence, unlocks) | yes | no | no |
| Equipment found | kept | kept | kept (items are never lost) |
| Potions left + found | kept | kept | lost |
| Card discoveries made permanent | choose up to 2 | choose 1 | none |
| Relics found → relic collection (heirloom unlock) | yes | yes | yes |
| Bond XP | full | small | small |
| HP, deck changes (rest upgrades, removals, drafted cards), expedition relics | reset | reset | reset |

Everything that resets is rebuilt from the campaign at the next departure, so a bad expedition can
never damage the permanent collection.

---

## 4. Content model (data-driven)

* `data/regions/*.json` — id, name, description, art, world-map position, unlock requirements,
  mission ids, threat levels, region mechanics text, default region state.
* `data/missions/*.json` — id, name, region, description, objective `{type, ...}`, map rules
  (`fixed` template map with randomized contents, or `generated` from region pools), difficulty,
  rewards, unlock requirements, consequences (`on_complete`, `on_retreat`, `on_defeat`: set flags,
  change threat, unlock missions / regions / services / recipes / specializations), `repeatable`.
* `data/castle/services.json` — castle services: id, name, icon, description, unlock rule, panel.
* `data/progression/campaign_rules.json` — deck rules, outcomes, upgrade and refinement prices,
  discovery rules, starting treasury, potion capacity.
* `data/progression/bond.json` — bond levels, XP sources and per-expedition caps, unlocks.
* `data/fusion/recipes.json` — fusion recipes; result cards in `data/cards/fusion_cards.json`.
* `data/items/consumables.json` — potions (new ones reuse combat effect types).
* `data/apothecary/recipes.json` — brew recipes.

Requirements use one shared format evaluated by `Requirements.met(campaign, req)`:
`{missions: [ids], flags: {flag: value}, bond_level: n, services: [ids], regions: [ids]}`.

---

## 5. Systems

### 5.1 Reused unchanged
Combat engine, cards, statuses, reactions, passives, equipment rules, relic effects, events,
merchants, towns, treasure, room screens, map view, card view, deck viewer, equipment screen.

### 5.2 Modified
* `GameState` — gains `campaign` and `expedition`; ending an expedition hands control to
  `ExpeditionService` instead of deleting the save. Classic runs keep the old behaviour.
* `SaveManager` — v3 file `{version, campaign, expedition}`; the v2 run payload is reused as the
  expedition section; v2 files migrate (§7).
* `SceneRouter` — new screens: castle hub, world map, expedition preparation, expedition results,
  castle service shell.
* `PartyMember` — optional secondary specialization.
* `CardReward` — secondary specialization pool at reduced weight; records discoveries.
* `Equipment.totals` — adds refinement bonuses.
* Map screen — objective tracker, Retreat and Return Home buttons.
* Main menu — New Campaign / Continue Campaign; Quick Play grid.

### 5.3 New
`CampaignState`, `ExpeditionState`, `ExpeditionService` (start, end, rewards, return),
`MissionDef` / `RegionDef` access in `DataRegistry`, `Requirements`, `ExpeditionGenerator`
(map variation + generated maps), `Objectives`, `DeckRules` (deck validation), `CardWorkshop`
(permanent upgrades), `Fusion`, `Apothecary`, `Bond`, `WorldState`; UI: castle hub, world map,
preparation, results, service shell + panels (deck workshop/collection, upgrades, enchanter,
apothecary, training hall, sisters), reusable `CardGrid` with filters and `ConfirmDialog`.

---

## 6. Key design decisions

1. **One gold currency, two wallets.** The expedition purse starts at `STARTING_GOLD` exactly as
   before (merchant balance is untouched); the purse converts into the castle treasury at the end
   by outcome share. Castle services spend the treasury. One rare material (Essence) gates fusion.
2. **Collection = copies.** Every permanent card is an `OwnedCard` in the roster. Prepared decks
   reference uids. At departure the prepared copies are cloned into the expedition party; rest-site
   upgrades and drafted cards affect only the clones.
3. **Discoveries.** Cards drafted during an expedition are temporary. On completion the player keeps
   up to 2 of them permanently (1 on retreat), so the collection grows by choice, not by inflation.
4. **Hybrid specializations.** A sister has one primary specialization (its passive is the only
   specialization passive that runs) and, once the Training Hall is open, an optional secondary
   one she has unlocked. Secondary cards are capped per deck (`secondary_card_limit`) and appear in
   rewards at half weight. Twin combos and the combo guide stay keyed by primary specializations.
5. **Equipment is permanent**, worn by the roster; expeditions carry clones and found items join the
   stash at the end. Blacksmith refinement upgrades an item id (all copies) up to level 2.
6. **Relics are temporary** except the one heirloom chosen from the relic collection. Every relic
   found unlocks it for the heirloom slot. Bond rewards are bond relics (rarity `bond`) that never
   drop randomly.
7. **Potions**: castle stores + loadout limited by capacity (3, Apothecary upgrade to 4).
8. **Fusion is rare**: few recipes, each crafted once, consumes the two inputs, needs Essence and a
   bond level; the result is a fusion card (rarity `fusion`, max 1 copy per deck).
9. **Bond** grows from shared expeditions and twin reactions (capped per expedition) and unlocks
   fusion recipes, bond relics and the Enchanter. No stat-only bonuses.
10. **Procedural variation without losing art.** Fixed maps keep their layout and art but get rerolled
    room contents within each terrain band (encounters from the terrain's pool, events, chests,
    elite placement) and randomly pruned side links (connectivity re-validated). New missions use a
    generated layered map built from the region's pools.

---

## 7. Save format and migration

* v3: `{"version": 3, "campaign": {...} | null, "expedition": {<v2 run payload> + "meta"} | null}`.
* v2 / older run saves migrate automatically:
  * a campaign is created from the run: sisters with their specializations, the run decks become the
    collection (upgrades kept), worn equipment and stash become the armory, relics enter the relic
    collection, gold is kept in the purse;
  * acts listed in `run_flags.completed_maps` mark their missions completed and unlock the following
    regions (`legacy_map` on every mission links old maps to missions);
  * the run itself continues as an expedition of the matching mission, so the player resumes
    exactly where they were and returns to the castle afterwards.
* Unknown ids are dropped with warnings (as before). A save that cannot be migrated shows the error
  on the main menu with the existing Delete Save recovery path; the damaged file is kept as `.bak`.
* Idempotency: rewards are applied once per expedition (`rewards_claimed`), castle transactions
  (upgrade, fusion, purchase) mutate state and save in one step, the existing reward-phase room
  state still guards combat rewards.

Autosaves: castle hub entry, every castle transaction, expedition start, node entry, combat victory,
reward claim, event resolution, merchant purchase (existing room saves), objective completion,
return to castle.

---

## 8. Implementation phases (sub-milestones)

| | Scope |
|---|---|
| 18A | this document, campaign rules data |
| 18B | `CampaignState`, save v3 + migration, castle hub, world map, start / return loop |
| 18C | missions + regions data, `ExpeditionState`, generator, objectives, retreat, results |
| 18D | collection, prepared decks, `DeckRules`, Deck Workshop + Collection panels |
| 18E | permanent card upgrades, equipment refinement + Armory at the castle, Apothecary |
| 18F | secondary specializations (Training Hall), fusion (Enchanter) |
| 18G | Sister Bond (levels, XP, bond relics, Sisters panel) |
| 18H | world state consequences, mission unlock chains, gated loot |
| 18I | balance checks, UI walkthrough tests (incl. phone size), docs, report |

---

## 9. Testing

`tests/run_all_tests.sh` runs every suite. New: `tests/campaign/run_campaign_tests.gd` (logic) and
`tests/campaign/castle_flow_test.tscn` (windowed walkthrough with screenshots, desktop and phone
sizes).

---

## 10. Technical risks

* **Save compatibility** — mitigated by migration tests on real v2 payloads.
* **Two run modes** (campaign and Quick Play) — both use the same expedition code; only the ending
  differs (`GameState.campaign == null`).
* **Balance drift**: maps were balanced for a starter deck plus one act of rewards. Prepared decks
  are capped (deck rules) and permanent upgrades cost treasury gold, so power grows slowly.
* **Random maps** must stay navigable: the generator validates reachability of the exit / objective
  from start and retries with a new seed.
* **Global modifiers** (`Equipment.refinement`) are set from the campaign on load and cleared for
  classic runs; tests reset them.

---

## 11. Implementation status (2026-11-22)

### Done
| Area | Where |
|---|---|
| Campaign state, castle state, Quick Play slot | `scripts/progression/campaign_state.gd`, `GameState` (`campaign`, `expedition`, `enter_castle`, save slots) |
| Save v3, migration of v0-v2 runs, damaged-expedition recovery | `SaveManager`, `GameState._load_campaign`, `scripts/progression/campaign_migration.gd` |
| Regions, missions, castle services, unlock requirements | `data/regions`, `data/missions`, `data/castle`, `scripts/progression/requirements.gd` |
| Expedition lifecycle, rewards once, discoveries, world consequences | `scripts/progression/expedition_service.gd`, `expedition_state.gd` |
| Map variation and generated maps, objectives | `scripts/map/expedition_generator.gd`, `scripts/progression/objectives.gd` |
| Deck rules, prepared decks, presets | `scripts/cards/deck_rules.gd`, `CampaignState` |
| Permanent upgrades, refinement, Training Hall | `scripts/progression/castle_workshop.gd`, `Equipment.refined_bonus` |
| Fusion (4 recipes) | `scripts/progression/fusion.gd`, `data/fusion`, `data/cards/fusion_cards.json` |
| Apothecary (buy, brew, belt, loadout) | `scripts/inventory/apothecary.gd`, `data/apothecary`, party potions in `CombatManager` |
| Sister Bond (5 levels, 3 bond relics, capped sources) | `scripts/progression/bond.gd`, `data/progression/bond.json` |
| Screens | `scripts/ui/castle/` (hub, war table, preparation, results, service shell, `CastleUI`) and `panels/` (deck workshop, collection, upgrades, fusion, apothecary, training, bond) |

The castle's Armory is the existing equipment screen, which works unchanged on the roster and the
vault. The castle hub, war table and preparation screens fit 1280x720 and 844x390 (tested).

### Deferred (not in this milestone)
- Branching card upgrades (data hook: an optional `upgrade_paths` block; combat reads one `upgrade`).
- Region threat as a difficulty modifier (threat is tracked and shown; it does not scale enemies yet).
- Boss variants / modifiers, survival / escape / defend objectives (the objective framework takes new
  types in `Objectives`).
- Equipment sell / dismantle, NPC quest givers, personal sister stories.
- A campaign-aware balance simulation (the bot plays classic runs).
- Portrait phone layouts (landscape only, as the rest of the game).
