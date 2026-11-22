# Map System

- `MapGraph` / `MapNodeData`: static graph from `data/maps/*.json` with validation (`validate()`).
- `MapProgress`: runtime position + visited list; `travel_to()` only accepts connected, unvisited nodes and emits `move_rejected` otherwise. Held by `GameState.map_progress`, so the position survives screen changes.
- `MapView` / `MapNodeButton`: visualization only; lays out left (start) to right (exit) from the node coordinates and re-flows on resize.
- `SceneRouter.go_to_room(node)` maps node type to a room screen. Rooms: combat (`data/encounters`), rest, merchant (`data/shops`), event (`data/events`), exit.

## Illustrated map (Milestone 4C)
`MapView` shows a map illustration from the art catalog (`maps.<map_id>` in `data/art/art_catalog.json`): `asset`, `nodes` (normalised x,y per node id, 0..1 on the picture), `rooms` (normalised rectangles each node must lie in), `paths` (optional corridor waypoints per "from>to" edge, drawn as Catmull-Rom curves) and `label_sides` (above/below). The picture is fitted with its aspect ratio, centred and never cropped; positions are computed from it, so nodes and paths stay aligned at any resolution. The picture ignores input. A map without art entries falls back to the plain left-to-right layout. None of this changes the graph (`data/maps/*.json`) or `MapProgress`: taps still call `MapProgress.travel_to`.

Final Royal Castle node positions (x, y): royal_chambers (0.105, 0.22) bedroom, west_gallery (0.205, 0.24) gallery walkway, royal_library (0.285, 0.23) library, throne_approach (0.50, 0.27) red carpet below the throne, training_yard (0.879, 0.30) arena, west_training (0.19, 0.52) west training room, central_courtyard (0.50, 0.585) fountain, east_armory (0.79, 0.51) merchant room, castle_exit (0.503, 0.85) main gate.

## Layout-driven map (Milestone 4C, current)
Supersedes the catalog-based map art above. `data/maps/royal_castle_layout.json` ("layout_for": map id) holds normalised node positions, label sides, curve bends, node size and the background asset id; `MapLayout` (scripts/map/map_layout.gd) loads and validates it (every node positioned, 0..1 bounds, no unknown nodes or edges). `DataRegistry.layouts` keeps layouts apart from maps. `MapView` renders any graph + progress + layout: background shown whole and centred, curved paths behind nodes (gold = choices from the current room, blue = travelled, dashed ink = unexplored), node states (current pulse, available ring, completed badge, locked dim), hover/pressed scale. Invalid layouts fall back to the plain layout. The graph JSON and MapProgress are unchanged. Note: the project stretches the 1280x720 design canvas, so phones see a wider virtual viewport.


## Milestone 7: elite and treasure rooms, room state
- New node types `elite` (uses `encounter_id`) and `treasure` (uses `treasure_id`, data/treasure). Icons: star and chest (`data/art/art_catalog.json`); the map legend lists them only when the map has such rooms.
- The Royal Castle tutorial graph is unchanged. A separate demo route `data/maps/castle_elite_demo.json` (start, fight, elite, rest, treasure, elite, exit) is started from the main menu button "Elite Route" (it uses `GameState.next_map_id`; no map layout art, so the plain layout is used).
- Room state: `GameState.room_state` ({} on the map, otherwise `{node_id, kind, ...}`) is saved with the run (save version 2). `SceneRouter.go_to_room` records the room and saves; screens call `update_room(...)` after each important change (rest used, upgrade done, removal done, purchases, treasure taken, combat reward phase); `end_room()` runs when the map opens. `SceneRouter.resume_run()` reopens the saved room after Continue. Rooms that do not match the saved map position are dropped (the run resumes on the map).
- Save robustness: version 2 adds `room`, `reward` and `inventory.relics`; version 1 saves still load. The previous good save is kept as `.bak`; a damaged main file loads from the backup, otherwise an error is shown and the file is NOT deleted. The main menu has Delete Save with a confirmation dialog.
- Rest rooms: Rest, Upgrade a Card and Remove a Card (rules in `data/progression/run_rules.json`: enabled, uses per rest visit = 1, gold cost = 0, minimum 6 cards per character; a rest node may override them with its own `card_removal` block).


## Milestone 8: the Enchanted Forest and acts
- **Acts.** `data/progression/run_rules.json` -> `acts.order` lists the maps of a normal run: `royal_castle_tutorial`, then `enchanted_forest`. Reaching the exit of a map with a successor opens the act transition screen (`ACT_TRANSITION`); `GameState.advance_to_next_map()` swaps only the map progress. Party, HP, decks, upgrades, gold, items and relics are untouched. The exit of the last map finishes the run. The castle graph itself was not changed.
- **Forest map** (`data/maps/1_forest.json`, id `enchanted_forest`, 21 nodes): entrance, five stages (3 / 4 / 4 / 4 / 3 rooms), the boss and the exit. 4 normal fights, 2 elites, 3 events (two from the `forest` pool, one from `forest_danger`), 2 treasures, 3 towns, 1 merchant, 2 rests, 1 boss. Every route reaches the Serpent's Domain; 32 different routes; skipped siblings close behind the party.
- **Layout** (`data/maps/1_forest_layout.json`): normalised positions on `assets/environments/maps/1_forest.jpg`, climbing from the bottom to the top. The picture is shown whole (aspect kept, never cropped) and is a separate background; nodes, paths and name plates are UI. The whole map fits every supported landscape size, so no scrolling is used.
- **New node types:** `town` (uses `town_id`, data/towns) and `boss` (uses `encounter_id`). Events may use `event_pool` instead of a fixed `event_id`.
- **Map markers (both maps):** nodes are ornate medallions (the gold ring frame of the UI art, an emblem per room type, a ring in the type colour); elite nodes are 14% larger and the boss 50% larger. Available rooms breathe with a gold glow, the current room pulses, visited rooms get a check seal, locked rooms are desaturated. Routes are trails of ink dots (faint, blue when walked, gold beads for the open choices). Room names sit on small framed plates.
- **Towns** (`data/towns`): `services` is any of `merchant`, `rest`. The town screen is a hub; the services are the existing merchant and rest rooms (`GameState.current_shop_id()`, `current_heal_fraction()`), which return to the town. Used services live in the saved room state (`rested`, `upgraded`, `removed`, `bought`). A town node cannot be re-entered.
- **Events** (`data/events`): pools via `"pools": [...]`; each choice has `text`, `result` (the consequence shown to the player), `effects` and optional `requires` (gold / item). Effects: gain_gold, lose_gold, heal_party, damage_party (never kills; stops at 1 HP; skips the fallen), gain_item, lose_item, gain_relic (falls back to gold), card_reward, start_combat. The rolled event, the choice and the outcome are saved in the room state; seen events are kept in `run_flags.seen_events` and are not rolled again while fresh ones remain.
- **Saves:** still version 2; new optional keys `flags` (`seen_events`, `completed_maps`) and room kinds `town` and `boss`. The map id was already saved, so forest saves load into the forest and castle saves into the castle. A save made on the transition screen resumes on the transition screen.

### Scrolling charts (Milestone 8 follow-up)
A layout may set `canvas_height` (multiples of the picture height). Above 1 the nodes, routes and name plates scroll vertically inside the picture's frame while the picture itself stays fixed; node `y` positions are normalised on the whole chart. Mouse wheel, mouse drag and touch drag scroll; a press that does not move is still a tap. The view opens centred on the party's room and shows a gold scroll thumb on the right. The Forest uses `canvas_height` 3.4 with 47 rooms over 11 stages; the Castle does not scroll.


## Act III: the Sunlit Coast
- **Data:** `data/maps/2_beach.json` (id `sunlit_coast`, act 3, 39 rooms, 15 floors). The layout is in `2_beach_layout.json`: a route chart 3 pictures tall that scrolls over `assets/generated/beach/map_sunlit_coast.png`.
- **Act order:** in run_rules: castle, then forest, then coast. The forest's exit now leads to the act screen and on to the coast. The coast's exit completes the run.
- **Rooms:** 14 fights, 4 elites (Sea Caves, Dune Crest, Serpent Deep, Colossus Steps), 4 towns, 1 merchant, 3 rests, 7 events and 3 chests. The boss, Eye of the Storm, is reached from all three last rooms.
  - **Towns:** Fishers' Flotilla and Raft Camp (at sea), Dune Village and Last Camp (shore), with shops in `data/shops/beach_shops.json`. The shops also sell coast armour and weapons.
  - **Events:** six events in `data/events/beach_events.json`, in the pools `beach_sea` (wreck, fisherman, bottle) and `beach_shore` (tide pool, sun shrine, smugglers, bottle); all are also in `beach`. The event effect `gain_equipment` puts an item in the stash.
  - **Chests:** `data/treasure/beach_treasure.json`, five choices each, equipment included.
- **Sea and shore (terrain):** the picture stays fixed while the rooms scroll, so only a room's column is stable on it. The middle column is always open sea and the side columns are beach (left) and rocky shore (right).
  - Every room has `"terrain": "sea"` or `"shore"`; start, boss and exit have none.
  - The map's `terrains` block (see "Terrains" below) gives sea rooms the ship-deck picture, for fights and for room screens (towns, rest, shop, events). Other rooms use `battle_backdrop` / `rooms.by_map` as before (`MapGraph.terrain_backdrop`).
  - Sea fights have only marine and sky foes (tritons, albatrosses, the Shark Knight, the Sea Snake). Shore fights have only beach and rock foes (crabs, rock spiders, Sand Scorpions, the Sand and Rock Giants). Encounters carry a matching `terrain` tag, and `run_beach_tests.gd` checks all of this.
  - Node tooltips say "At sea" or "On the shore".
- **Battles:** shore fights use `battle_beach`, sea fights `battle_ship_deck`.

- **Direct act starts:** the main menu also has "Start: Forest" and "Start: Coast". They begin a fresh run on that act (`GameState.next_map_id`) with the starting decks, and the run continues through the later acts. The list is `ACT_STARTS` in `main_menu.gd`.


## Terrains (every map)
- **Data:** a map lists its terrains in `"terrains"`: `{id: {name, hint, backdrop, foes}}`. Rooms carry `"terrain": id`.
  - `backdrop`: the battle picture for that terrain's fights. It is also the room-screen picture for that terrain's rooms (towns, rests, shops, events). The castle only tags its fight rooms, so its other rooms keep their own pictures.
  - `hint`: an extra line in the room's map tooltip.
  - `foes`: the monsters that belong there. Encounters carry the same `terrain` tag.
  - **Checks:** `tests/map/run_terrain_tests.gd` checks that every fight room has a terrain and that its encounter only uses that terrain's foes.
  - **Code:** `MapGraph.terrains`, `terrain_backdrop()` and `terrain_hint()`. Rooms without a tag (start, boss, exit) use the map's `battle_backdrop`.
- **Castle** (tutorial and Elite Route):
  - `yard`: the training courtyard (`battle_castle_yard`), with the Practice Automaton, Guard Recruits and Vanguard Knights.
  - `hall`: the stone hall (`battle_castle_generic`), with the Hall Guards, Hall Captain and Knight Commander.
- **Forest:** the picture is fixed while rooms scroll, so terrain follows the column.
  - **Left, `mountain`:** the mountains of the picture. Wolves, bears, the new Cliff Harpy and the Alpha Wolf.
  - **Middle, `deepwood`:** the giant trees. Venom spiders, the new Will-o'-Wisp and the Broodmother.
  - **Right, `falls`:** the waterfalls (`battle_forest`). Boars, Moss Trolls, drakes, the Grove Warden and the Elder Drake.
  - **Renamed mountain rooms:** Webbed Hollow is now Harpy Roost, Fern Gully is Pine Gully, Spider Gorge is Windy Gorge, Troll Bridge is Stone Bridge and Venom Marsh is Eagle Crag.
  - The Forest Serpent keeps the waterfall arena.
- **Crystal Hollow:**
  - `chasm`: Bat Roost, on a ledge over the underground lake. Bats.
  - `grotto`: the blue crystal caves on the left and the rooms on the right. Shamblers, bats and the Shadow Wraith.
  - `ruins`: Golem Gate and Glittering Deep, in the temple ruins. Golems and wraiths; Glittering Deep is now a wraith and a golem.
  - The Crystal Wyrm keeps the crystal cavern.
  - Its non-fight rooms now show the cave instead of castle rooms (`rooms.by_map`).
- **Coast:** `sea` (`battle_ship_deck`) and `shore` (`battle_beach`), as described above.


## Illustrated maps for the castle and the forest
- **Castle:** the castle and the forest now use generated top-down maps in the same style as Crystal Hollow and the coast: `assets/generated/maps/map_royal_castle.png` and `map_enchanted_forest.png`. The older parchment pictures stay in the catalog, unused.
  - Every castle room sits on its building: the chambers in the lower-left court, the guest lodge and the guard court on the left, the drilling soldiers, the fountain, the provisioner's house and the library on the right, the palace hall, and the gatehouse at the top.
  - Positions were solved against the map-view rules: no route passes a room, and the first branches split left and right.
- **Forest:** its picture matches the terrain columns: mountains on the left, the forest in the middle and the river with waterfalls on the right. The serpent's lair is at the top.

## Frostpeak: a climbing map (standalone adventure)

`data/maps/3_mountain.json` (id `frostpeak`) is started only from the main menu ("Frostpeak" button,
`main_menu.gd` ACT_STARTS). It is not in run_rules `acts.order`, so its summit ends the run.

- **Shape:** 51 rooms: 16 rows of three lanes from Frostpeak Foothills to the Dragon's Aerie (boss)
  and the summit (exit). Every path climbs (each next room sits higher on the chart), and the lanes
  draw together toward the peak while the trail sways left and right.
- **Altitude bands** (terrains): `slopes` (rows 1-5: pine woods), `glacier` (rows 6-11: ice caves) and
  `summit` (rows 12-16). Each band has its backdrop, foes and event pool (`mountain_<band>`).
- **Rooms:** 23 fights, 4 elites, 4 villages and outposts (Pinefall Village, Ropebridge Outpost,
  Cloud Monastery, the Last Cairn), a trading post, 3 rests, 3 chests and 10 events.
- **Layout keys added for climbing** (`MapLayout`, `MapView`), usable by any scrolling chart:
  - `climb_asset`: a tall picture drawn under the paths that scrolls with the rooms (the fixed
    `background_asset` stays as the frame), so the party visibly climbs the mountain.
  - `altitude` {base, summit, unit}: a gauge at the left edge of the chart shows the party's height
    (`MapLayout.altitude_at`: base at the lowest room, summit at the highest).

## Expeditions: regions, missions and map variation (persistent campaign)

Data: `data/regions/regions.json` (world chart position, art, unlock requirement, missions) and
`data/missions/missions.json` (objective, map rules, rewards, consequences). See
`docs/PERSISTENT_RPG_DESIGN.md` for the lifecycle.

- **Map rules** (`mission.map`): `{"mode": "fixed", "map_id", "variation": "shuffle" | "none"}` or
  `{"mode": "generated", "template", "rows", "lanes" | "bands", "start_name", "exit_name"}`.
- **`ExpeditionGenerator`** (`scripts/map/expedition_generator.gd`) works on map definitions only:
  - `vary_fixed`: fights trade encounters with fights of the same terrain and depth band (thirds of
    the map by distance from the start), elites may trade places with such fights, and up to 30% of
    branching nodes lose one side link when every room stays reachable and the exit stays reachable
    from every room. The layout and art of the map are unchanged.
  - `generate`: a layered map (rows x 3 lanes) from the template map's pools (`pools_from`: fights per
    terrain and band, elites, event pools, chests, towns, shops). Objective rooms (`"objective": true`)
    sit in different lanes at 30 / 55 / 80% of the climb; one elite in the last third, a rest in the
    middle and before the exit. A layout on the template's picture is synthesised and registered in
    `DataRegistry.layouts` under the generated map id.
  - Every result passes `MapGraph.validate()` and `is_fully_connected` (tested over many seeds).
- **Saving:** a rerolled or generated graph is kept in `MapGraph.custom_def` / `custom_layout` and
  saved in the map block (`map_def`, `layout_def`), so a reload shows the same expedition.
- **Objectives** (`scripts/progression/objectives.gd`): `reach_exit`, `boss_hunt`, `clear_targets`
  (win the fights in N of M objective rooms; Return Home appears on the map once met; reaching the exit
  without it is a retreat). The map shows the objective tracker and Retreat / Return Home bottom-left;
  objective rooms carry a blue diamond with a star.
- In a campaign an expedition is one map: `GameState.next_map_after_current()` returns "" and the exit
  leads to the results screen. Classic (Quick Play) runs still chain the acts.
