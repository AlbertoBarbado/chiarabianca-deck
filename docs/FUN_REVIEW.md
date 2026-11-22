# Fun review: why a run is not yet as compelling as Slay the Spire 2

Written 2026-11-21 from the project's data, the two simulations and the screens. Slay the Spire 2
(StS2) is used only as a benchmark for what keeps players starting "one more run".

## What makes StS2 compelling

1. **Every run is different.** Relics, card rewards and boss relics change how the run plays. StS2
   has about 290 relics and around 75 cards per character; most runs end with a deck nobody planned.
2. **Snowballing.** Powers and scaling buffs (Strength, Dexterity, Focus, Poison) turn a deck into an
   engine that grows during a fight, so a good draw feels like a payoff.
3. **Readable risk.** Enemy intents, Weak, Vulnerable and Block make every turn a small puzzle: block
   this hit or race the enemy.
4. **Risk and reward on the map.** Elites are dangerous but give relics; shops, rests and events
   each trade something.
5. **Feel.** Sound on every hit and card, snappy animations and clear numbers.
6. **Long-term goals.** Unlocks, Ascension levels and a run history give a reason to start again.

## Where Voidfarer Chronicles stands

| Driver | Voidfarer today | Gap |
|---|---|---|
| Run variety | 9-12 reward cards per specialization (about 25 per party with cross-combo cards) and 2 epics; 2 potions; 59 equipment items; 23 relics (3 before this review) | Card pools are small: the same rewards repeat within one run. |
| Snowballing | 7 Power cards in the whole game; Poison, Burn, Chill and Aether stack, but no Strength, Dexterity or similar | Few cards grow stronger during a fight. |
| Readable risk | Intents, Block, Taunt, element weaknesses and resistances, damage preview on cards | No Weak or Vulnerable, the two most-used tactical debuffs. |
| Keywords | Exhaust as a flag (no card uses it), Gust tokens | No Exhaust, Retain, Innate, Ethereal or X-cost cards: fewer kinds of decisions. |
| Map risk/reward | Elites give gear (75%) and now a relic; bosses a choice of boss relics | Fine now. Events could offer more trades (HP for relics, curses). |
| Twin identity (unique) | Shared deck, 8 twin reactions, Momentum, Aether, 16 combo pairings | The strongest part of the design; needs more cards that reference the other sister. |
| Feel | Animations, effects, cut-ins, screen shake | **No audio at all.** This is the biggest single "feel" gap. |
| Long-term goals | None (a run ends, the next starts from zero) | No unlocks, Ascension or run history. |

## Done in this review

- **Relics became the run-defining reward layer** (`data/items/relics.json`, `RelicEffects`):
  - 23 relics: 8 common, 6 uncommon, 5 rare and 4 boss relics. Effects use the passive system (like
    gear) and lean on the party's identity: Sisters' Locket rewards alternating sisters, Ley Crystal
    feeds Aether, Alchemist's Stone feeds every status build, Chime of Echoes and Storm Crown reward
    Momentum.
  - Boss relics give power with a price: +1 Energy each turn for one card fewer (Runic Crown), harder
    enemies (Eclipse Orb) or less Max HP (Crimson Chalice); or one card more each turn (Twin Halo).
  - Elites always leave a relic; a boss offers 3 boss relics to choose from; chests roll from every
    non-boss relic.
  - A relic bar in battle shows every relic with its text on hover and pops when one fires.

- **Card pools grew from 9-12 to 18-21 reward cards per specialization** (72 new cards), with the
  keywords that were missing: real Powers that last the whole fight (2-3 per specialization: Pyromancy,
  Winter's Grip, Arcane Cascade, Zephyr Stance, Consecration, Spiked Bulwark, Plague Censer,
  Trapmaster...), Retain cards, X-cost cards (Firestorm, Hailstorm, Mana Burst, Phalanx, Powder Keg...)
  and more Exhaust cards. COMBAT_SYSTEM.md, "Card keywords". Every card, old and new, now has its own
  ComfyUI art (no more shared fallback pictures).

## Recommended next steps (in order of impact)

1. **Audio.** Hit, block, card, status and UI sounds plus one music track per act. Needs assets with
   a commercial licence (Kenney.nl and Freesound CC0 packs), which means downloads the owner approves.
2. ~~Bigger card pools with keywords~~ (done: 18-21 reward cards each, Powers, Retain, X cost).
   Still open: Innate and Ethereal, and more cards that reference the other sister.
3. **Weak, Vulnerable and Strength.** On cards and on enemy intents, with the damage preview and the
   intent numbers updated. This makes "block or race" decisions sharper.
4. **More potions** (about 12, some tied to the twin reactions).
5. **Long-term goals.** Card and relic unlocks after runs, Ascension levels (each adds one rule), and
   a run history screen.
6. **Events with trades** (HP or gold for relics, removing a card for a curse) to make ? rooms tense.
