# Game Design (prototype state)

Loop: Main Menu -> New Game -> Character Selection -> Specialization Selection -> Party Overview -> Royal Castle map -> rooms (Combat / Rest / Merchant / Event) -> Exit -> completion screen.

Decisions made where the brief was open:
- Party is fixed to Chiara + Bianca for now (`GameConfig.INITIAL_PARTY_IDS`); `Party` supports any size.
- Only specializations with a real starting deck (`status: "playable"`: Arcana, Tanking) can be confirmed. All 12 can be inspected.
- Starting decks (10 cards each, data in `data/specializations`): Arcana = 4 Arcane Bolt, 3 Arcane Ward, 2 Gathering Focus, 1 Mana Surge; Tanking = 4 Shield Strike, 3 Steadfast Resolve, 2 Hold the Line, 1 Challenge.
- Starting gold 30; combat victories and the fountain event grant gold; potions (merchant) heal the most wounded member and are used from the combat screen.
- Rest heals 30% of max HP (override per node with `"heal_percent"`). Fallen members return at 1 HP after a won combat; resting does not revive.
- Landscape orientation, 1280x720 base, `canvas_items` stretch with `expand` aspect.
- Input is tap/click based; keyboard shortcuts in combat: 1-9 select card, E end turn, Esc cancel.


## Run structure (Milestone 8)
A normal run now has two acts. Act I is the Royal Castle tutorial; leaving it leads into Act II, the Enchanted Forest, with everything the party owns carried over. The Forest is a five-stage branching map with safer routes (events, towns, rests) and riskier ones (hard fights, elites, treasure behind them) that all converge on the Forest Serpent. Defeating it and leaving the forest completes the run ("Forest Act Complete"). There is no third act yet.


## Merchants: what gold buys
- **Wares:** each shop's item stock: potions and some gear.
- **Cards for sale:** 4 cards from the party's specialization pools.
  - Prices by rarity: common 45, uncommon 75, rare 120, with a small random spread.
  - Rolled once per visit from a saved seed, so reopening or reloading shows the same offer. Bought cards are marked Sold.
- **Card removal:** 60 gold, +25 for every shop removal already made in the run. One per visit, and a deck never goes below the minimum.
- **Card upgrade:** 55 gold, +15 per shop upgrade in the run, two per visit. A before/after preview is shown before paying.
- **Data:** all prices and limits are in `run_rules.json` `shop_services`, and a shop can override them with its own `shop_services` entry. Logic: `ShopServices`; screen: `merchant_room_screen.gd`.
- **Saved state:** the run-wide counters (`shop_removals`, `shop_upgrades`) are saved with the run.

## Frostpeak (standalone mountain adventure)

A climb from the snowy foothills to the White Dragon's aerie, chosen from the main menu. The party
starts fresh (starter decks, starting gold), so the climb ramps from forest-level fights at the foot to
coast-level ones near the summit.

- **Monsters by altitude:** Frost Wolf, Polar Bear and Yeti on the pine slopes; Crystal Spider, Rime
  Wraith and Ice Drake on the glacier; Storm Roc, Ice Drake, Yeti and Rime Wraith at the summit. Elites:
  Woolly Mammoth, Crystal Matriarch and Ice Giant (twice). Boss: Vaelith, the White Dragon.
- **Varied weaknesses:** only 3 of 11 monsters fear fire (Frost Wolf, Yeti and Rime Wraith, each 25%), and
  the Ice Drake and the dragon resist it. Crystal shatters under blades (physical), drakes fear
  lightning, the Ice Giant fears arcane and wraiths fear holy light; the dragon's pearl scales give way
  to arcane and venom.
- **Frostbitten** (new party debuff): +15% Frost damage taken per stack, max 3, -1 per round. Yetis,
  drakes, wraiths, crystal spiders, the Ice Giant and the dragon inflict it. The Yeti-Fur Mantle
  (hunters' lodge event, Pinefall furrier) makes the wearer immune; Glacier Plate resists frost.

## Persistent campaign: the castle and expeditions (2026-11-22)

The main loop is now **Castle -> War Table -> Region -> Mission -> Preparation -> Expedition -> Results
-> Castle**. Full design: `docs/PERSISTENT_RPG_DESIGN.md`.

- **The castle** is the sisters' home and never resets: card collection and prepared decks, the armory,
  the potion stores, learned specializations, the Sister Bond, the world state and the treasury.
- **Expeditions** are the old runs wrapped in missions. Fixed maps get rerolled contents every time;
  new missions use generated maps built from a region's content. They end in success, retreat or
  defeat, and always return to the castle with a results screen.
- **What persists:** gold by outcome (100 / 50 / 25%), equipment always, relics as heirloom choices,
  potions unless defeated, and up to 2 (1 on retreat) of the cards drafted on the way.
- **Signature systems:** hybrid specializations (Training Hall), permanent card upgrades and
  equipment refinement (Upgrade Workshop), card fusion between the sisters (Enchanter), and the
  Sister Bond, which grows from shared expeditions and twin reactions and unlocks fusion recipes and
  bond relics rather than stats.
- **Quick Play** keeps the classic run (Royal Castle -> Forest -> Coast) and the direct starts
  (demos, Forest, Coast, Frostpeak) without the castle, in a separate save slot.
