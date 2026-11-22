# Balance pass 1 (Milestone 7)

Goal: a coherent first pass for the four playable specializations (Arcana, Fire, Tanking, Holy), not final balance. Values that did not need to change were left alone. The simulation `tests/combat/balance_simulation.gd` (greedy policy, 60 fixed seeds per fight, all four pairings) guards against obviously dominant or useless setups.

## Card changes

| Card | Old | New | Reason | Expected impact |
|---|---|---|---|---|
| Immolate (Fire, 1 energy) | 3 dmg + 3 Burn (3 + 6 burn = 9 total); upgrade 4 + 5 Burn | 3 dmg + 2 Burn (7 total); upgrade 4 + 3 Burn (10 total) | At Burn tick 2, Immolate out-valued Ember Bolt by 50% for the same cost and made Kindle pointless. | Immolate still beats Ember Bolt (7 vs 6) but only by a little; Kindle stays the burn-focused option. |
| Kindle+ | 5 Burn (10 dmg over time for 1 energy) | 4 Burn (8) | Upgraded Kindle out-damaged every 1-cost attack. | Upgrade is still worth it but is no longer the best 1-cost damage. |
| Inferno (Fire, 3 energy) | 20 dmg + 3 Burn; upgrade 26 + 4 | 18 dmg + 3 Burn; upgrade 23 + 4 | 26 damage for 3 energy was ~8.7 per energy, above every other rare. | Still the strongest Fire finisher, about 7 per energy. |
| Fuel the Flames | 5 dmg, +6 if Burning (11); upgrade 7, +9 (16) | 5, +4 (9); upgrade 7, +6 (13) | With Immolate/Kindle available, 11 damage for 1 energy was reliably triggered. | Rewards setting up Burn without being the best 1-cost card. |
| Radiant Bulwark (Holy) | 3 dmg + 100% of current Block | 3 dmg + 75% of Block; upgrade stays 5 + 100% | With Blessed Aegis and Block cards, it reached 15-20 damage for 1 energy. | Upgrade now matters (100%). |
| Smite (Holy) | 9 dmg; upgrade 12 | 8 dmg; upgrade 11 | 9 damage for 1 energy beat Fireball per energy and left Radiant Strike pointless. | Holy still has the best common 1-cost hit, by a smaller margin. |
| Mending Light (Holy) | Heal 10; upgrade 14 | Heal 8; upgrade 12 | Enemy hits are 5-13; a 10 HP heal every turn for 1 energy made damage meaningless. | Healing remains strong but costs tempo. |
| Pulse (Arcana) | Heal 8; upgrade 12 | Heal 6; upgrade 9 | Arcana is not a healer; it matched Holy's identity too closely. | Keeps Arcana distinct. |
| Mana Surge (Arcana power) | Cost 1, gain 1 Energy (net 0, exhausted); upgrade gain 2 | Gain 2 Energy (net +1, exhausts); upgrade costs 0 | Net zero before upgrading. | A real, one-shot payoff that fits Arcane Flow. |

Unchanged on purpose: Burn tick (2; Burn duration is now 2 to 3 stacks per card, so a single Immolate deals 4 extra damage instead of 6), Divine Judgment (18 + party heal 5 for 3 energy is about 6 per energy plus healing, fair for a rare), Kindled Spark and Blessed Aegis values, all Tanking cards (Taunt and Block are their identity; the new passive adds the missing piece).

## Passives
Arcana: Arcane Flow, Tanking: Bulwark Stance (see CHARACTER_SYSTEM.md).

## Simulation results (60 seeds per cell, greedy policy)
Regular fights are won 100% by every pairing. Party HP left on the final regular fight: Arcana+Tanking 60%, Arcana+Holy 67%, Fire+Tanking 56%, Fire+Holy 63%. Elites cost far more: roughly 27-48% HP left, 93-100% win rate. Spread between pairings on the same fight stays under 20 points. The greedy policy does not use Taunt or combo ordering, so Tanking and Arcana are likely stronger with real play.

## Known open balance points
Healing (Holy) still makes regular fights easy; consider enemy damage scaling after the first playtests. Frost, Wind, Lightning, Earth and the other Bianca specializations are not balanced (not playable yet).


## Damage types and Frost (balance simulation, 60 seeds)
- **Castle, party HP left:** Frost + Tanking 60% on the final regular fight and 45% / 45% on the elites. Frost + Holy 69% and 51% / 53%. Fire and Arcana stay where they were.
- **Vanguard Knights:** their weakness moved from fire to frost, so fire + holy keeps the elite clearly harder than the final regular fight.
- **Forest:** Frost is strongest against slow beasts it can freeze (bear 89-94%, troll 84-92% HP left) and weakest against the fast Alpha pack (22-36%). The Serpent cannot be frozen: 95-100% wins, 22-37% HP left.
- **Elite initiative:** the Grove Warden and Broodmother were raised to initiative 5 so they cannot be frozen with one card.
- **Equipment:** the largest bonus is 30% resistance to one type or +20% damage of one type, about one card's worth in a long fight.


## Sunlit Coast (simulation, decks with reward pools, full HP per fight)
- **Regular coast fights:** all 100% won.
- **Elites:**
  - The Sea Snake is hardest for Frost + Tanking (95% wins, 23% HP left).
  - The Sand Giant is hardest for the Fire and Arcana Tanking pairs (62–65% wins, about 10% HP left). It is the act's wall for low-damage pairs.
- **Sandstorm Elemental:**
  - **First tuning:** 190 HP and 50% physical resistance made it nearly unbeatable for Tanking pairs (2–25% wins) and trivial for Holy.
  - **Final values:** 165 HP; resists physical and holy 25%; Scouring Lash 13; Desert Maelstrom 9. Every pair now wins 95–100% of simulated fights with 16–51% HP left. The fight costs the most HP for Tanking pairs.

- **Sea and shore encounters (after the terrain split):**
  - Shore fights are crab and rock spider mixes. Sea fights are tritons, albatrosses and the Shark Knight.
  - All regular coast fights are won 98-100% of the time by every pair.
  - Shark Waters was first two tritons and the Shark Knight: Fire + Tanking ended it with 15% HP, harder than the later Storm Front. It is now one triton and the Shark Knight (58-73% HP left for Tanking pairs). Storm Front (triton, Shark Knight, albatross) leaves 35-51%.
  - The Shark Knight's Riptide Cleave applies 2 Soaked: a single stack wears off before the party's turn and did nothing.
- **Sand Scorpion (shore):** 30 HP, initiative 5. In the new shore fights every pair wins 100% of the time. Salt Flats (2 scorpions + spider) leaves 49-80% HP and Shell Beach (scorpion + crab) 72-95%.

- **Forest after the terrain split:**
  - Mountain fights mix wolves, bears and harpies. Deep-wood fights mix spiders and wisps. Falls fights mix boars, trolls and drakes.
  - Every pair wins every regular forest fight 100% of the time.
  - The hardest regular fights are Eagle Crag (harpy, bear, harpy: 49-71% HP left) and Troll's Crossing (troll and boar: 40-92%).
  - The elites and the Forest Serpent are unchanged.

- **Ashveil (simulation, greedy policy now counting conditional damage bonuses):**
  - Every Ashveil pair wins every castle, forest and coast fight, including the elites and bosses.
  - It is close to Holy: final castle fight 65-68% HP left (Holy 63-69%, Tanking 55-60%); Forest Serpent 44-58% (Holy 37-56%); Sandstorm Elemental 42-52%.
  - Fire + Ashveil is the intended combo, and it is strong without leading the field.
  - Oiled is capped at +45% Fire, and Ignition Strike burns the oil away, so the bonus cannot be farmed.


## Full-run simulation (`tests/combat/run_simulation.tscn`)
- **What it plays:** whole runs (castle, forest, coast). HP carries over; it takes route choices, card rewards, rests (heal when hurt, otherwise upgrade), shops (potions, gear), chests, loot and equipment, and drinks potions below 35% HP. Same greedy card policy as `balance_simulation.gd`.
- **Targets:** every pairing wins 40-85% of runs. A person beats a greedy bot, so the real game is easier than these numbers. The act bosses should be where runs are decided.
- **Before tuning:** Holy pairings won 77-97% of runs and Tanking 10-30%. Over a run, sustain and unresisted damage decide everything, which the full-HP per-fight table hid. Three rock spiders cut the hand from 5 to 3 cards for good, and parties entered the coast still hurt from the Forest Serpent.
- **Changes:**
  - **Quicksand:** at most 1 card fewer per turn.
  - **Between acts:** reaching the next act heals 35% of max HP and revives the fallen (`run_rules acts.heal_between_acts`).
  - **Tanking:** Shield Strike 6, Steadfast Resolve 6 Block, Hold the Line 5 party Block. Second Wind is common and replaces one Hold the Line in the starting deck. Bulwark Slam adds half her Block. Sweeping Shield 5.
  - **Holy:** Blessed Aegis +1 Block (was +2). Radiant Strike 5, Smite 7, Sanctified Ward 7. Soothing Touch heals 3 and gives 2 Block, and the starting deck has 2 Touches (5 Strikes). Mending heals 10 then exhausts. Benediction gives 4 Block and heals 2. Divine Judgment deals 16 and heals 3.
  - **Bone Clearing:** drake and boar.
  - **Sand Giant:** 100 HP, Sand Slam 12.
  - **Sandstorm Elemental:** 180 HP, the final boss's climax.
- **After tuning (60 runs per pairing):**

  | Chiara | Tanking | Holy | Ashveil |
  |---|---|---|---|
  | Arcana | 43% | 77% | 68% |
  | Fire | 53% | 85% | 80% |
  | Frost | 67% | 73% | 73% |

  - Average 69%.
  - Runs mostly end at the Forest Serpent (63 of 540) and the Sand Giant (18). The Sandstorm Elemental now ends 14.
- **Still open:** runs finish with 300-600 unspent gold. Shops only sell potions and some gear, so gold is not rewarding enough. Card removal, card sales or upgrades for gold would fix that.

- **Shop services (the full-run simulation now shops the way a sensible player would):**
  - It removes its weakest basic card, buys the rarest affordable card, and upgrades.
  - Unspent gold at the end of a run fell from 300-600 to about 150-330: gold now has uses all run long.
  - Holy's Blessed Shield is 4 Block (upgrade 6), because Holy pairings stayed on top.
  - **Final numbers (60 runs per pairing, shops included):**

    | Chiara | Tanking | Holy | Ashveil |
    |---|---|---|---|
    | Arcana | 45% | 75% | 57% |
    | Fire | 57% | 83% | 72% |
    | Frost | 67% | 75% | 62% |

    Average 66%. Runs mostly end at the Forest Serpent, then the Sand Giant and the Sandstorm Elemental.

## Arcana + Holy: Aether (full-run simulation, 60 runs per pairing)
- **Goal:** give Arcana + Holy a combo of its own, like Frost + Tanking (Chill) and Fire + Ashveil (Oiled). Arcana makes extra cards and Energy into Aether; Holy spends it. Rules are in COMBAT_SYSTEM.md, cards in CHARACTER_SYSTEM.md.
- **Diagnostics:** `run_simulation.gd` now prints how many Aether cards were played and the average Aether they found. It also has experiments `pre_aether`, `old_arcana` and `old_holy`, which put back the old decks.
- **What the simulation showed:**
  - With the old decks, Arcana + Holy won 75% of runs.
  - The new Arcana cards alone gave 77%, and the new Holy cards alone 75%. Only together did they jump, to 88-90%, so the gain really is the combo.
  - The first values were too strong, so the starting Hymn of Dawn was cut to 4 damage +1 per Aether. It is the most-played Aether card, so it was the lever that mattered.
  - Ley Siphon first dealt 4 damage, which dropped Arcana + Tanking from 45% to 35%. It now deals 6 and draws, so Arcana is never worse than before.
- **Final values:**
  - Ley Siphon: 5 damage, draw 1. It was 6 in the simulated build; it was lowered after playtesting because it simply beat Arcane Bolt (6 damage, no draw). Arcana + Tanking may end a few points lower than the table.
  - Arcane Echo: +1 Energy, draw 2, exhaust.
  - Leyline Weave: +2 Energy, draw 2.
  - Aether Lance: 6 damage, +2 per Aether.
  - Hymn of Dawn: 4 damage, +1 per Aether.
  - Radiant Cascade: 2 to all, +1 per Aether.
  - Lightfall: 6 damage, +3 per Aether, releases it.
  - Wellspring Prayer: party 3 Block, +2 per Aether, releases it. Its heal per Aether was cut: healing decides runs.
  - Aether is capped at 6.
- **Aether found per Aether card played:** Arcana + Holy 1.9, Arcana + Tanking 1.5, Arcana + Ashveil 1.8, Fire + Holy 0.6, Frost + Holy 0.2. The combo works best with its intended partner.

  | Chiara | Tanking | Holy | Ashveil |
  |---|---|---|---|
  | Arcana | 48% (was 45%) | 82% (was 75%) | 67% (was 57%) |
  | Fire | 57% | 72% (was 83%) | 72% |
  | Frost | 67% | 67% (was 75%) | 62% |

  - Average 66%. Every pairing is within the 40-85% target.
  - Holy is no longer the best partner for everyone. It is now best with Arcana.
  - Fire and Frost with Holy lost a few points, because one Radiant Strike became a Hymn of Dawn that wants Aether.


## Twin combos, Wind and Venom (full-run simulation, 60 runs per pairing, 16 pairings)
- **The bot:** `tests/combat/sim_policy.gd`, shared by both simulations.
  - It values twin reactions by what they set off: Combustion counts as Poison x 3 on every enemy, and Miasma as the Poison it spreads.
  - It also values Gusts, Momentum bonuses, Poison, Blight, Catalyst and spreading.
  - It still never plans a turn, so it does not deliberately build Poison and then detonate it.
- **First pass:**
  - Frost + Holy won 90% of runs: Shatterlight did 3 per Chill, and Sunfire Smite added +4.
  - Fire + Holy won 83-87%.
  - Fire + Venom, a signature combo, won only 47-50%: Fire detonated small Poison stacks too early.
  - Wind + Tanking won 42%.
- **Tuning:**
  - Shatterlight: 2 per Chill.
  - Purifying Flame: 1 Block per Burn.
  - Sunfire Smite: +3.
  - Combustion: 3 Fire per Poison stack, to every enemy.
  - Venom Strike: 5 damage. Toxic Guard: 6 Block. Envenom: 4 Poison.
  - Momentum Bash: 5 damage.
  - Fire gained a ninth reward card, Ember Volley.
- **Final results:**

  | Chiara | Tanking | Holy | Ashveil | Venom |
  |---|---|---|---|---|
  | Arcana | 45% | 75% | 52% | 50% |
  | Fire | 63% | 75% | 70% | 70% |
  | Frost | 67% | 77% | 60% | 73% |
  | Wind | 43% | 65% | 57% | 80% |

  - Average 64%. Every pairing is within the 40-85% target. Arcana and Wind do best with their signature partner (Holy, Venom). Fire's signatures (Ashveil, Venom: 70%) trail Holy (75%) by a little, and Frost does better with Holy (77%) than with its signature Tanking (67%): Holy's sustain carries every pairing in a bot's hands.
  - Reactions per run: Wind + Ashveil 144 and Wind + Venom 111 (each Gust hit spreads), Frost pairings 33-41, Fire pairings 24-33.
  - Tanking pairings stay the weakest (43-67%). That was already true before, and they are the safest for a person who uses Taunt, which the bot does not.
  - Runs still mostly end at the Forest Serpent, then the Sandstorm Elemental and the Sand Giant.

## Smarter Block and Taunt in the bot (2026-11-21)
- **Change (bot only, no game data):** `tests/combat/sim_policy.gd` now values Block by the attacks really aimed at whoever receives it (planned targets, Taunt redirection, attacks on everyone), not by the total incoming damage. It also values Taunt by the single attacks it pulls off the other princess, and taunts the hardest of them.
- **Result** (60 runs per pairing; every pairing improved because the bot now blocks better):

  | Chiara | Tanking | Holy | Ashveil | Venom |
  |---|---|---|---|---|
  | Arcana | 57% | 73% | 62% | 58% |
  | Fire | 70% | 82% | 87%* | 85% |
  | Frost | 72% | 82% | 70% | 77% |
  | Wind | 48% | 68% | 55% | 78% |

  - Average 70% (was 64%).
  - \*Fire + Ashveil re-measured over 200 runs: 79%. The 87% was noise (about ±4 points at 60 runs), so no card was changed.
  - Tanking gained the most (Arcana + Tanking 45% to 57%). It is still Wind's weakest partner (48%), and Fire stays the strongest Chiara specialization with every partner.

## Gear for every slot (2026-11-21)
- **Change:** 39 new items (helmets, amulets, gauntlets, belts, rings, boots, two weapons), 31 with in-battle effects. Only gear somebody in the party can use drops or is sold, and shops add a gear offer per visit.
- **First result** (60 runs per pairing): every pairing rose, to an average of about 82%, and 7 pairings went over the 85% cap.
- **Tuning tried:**
  - Supply: drops from normal fights 30% -> 15%, elites 100% -> 75%, one shop offer instead of two, and new gear priced 60 / 95 / 140.
  - Holy gear: Sunlit Reliquary heals 1 (was 2); Pilgrim's Girdle heals 3 every 3rd turn (was 2 every 2nd); Dawnwalker Sabatons give Aether every 2nd turn (was every turn).
  - Max HP: items with effects add none; the plain commons add at most +4.
  - Each step moved the results by less than the noise (about ±5 points at 60 runs).
- **Diagnosis** (Fire + Holy, 100 runs): 88% without the new items, and 88% with their effects switched off, against 93-95% with them. So the new gear adds about 5 points. The rest of the rise comes from the usable-only rule: drops that used to be wasted (an Arcane staff for a Fire Chiara) now always fit, so weapons and armour count for more. Experiments `no_gear_effects` and `no_new_gear` in `run_simulation.gd`.
- **Final** (60 runs per pairing):

  | Chiara | Tanking | Holy | Ashveil | Venom |
  |---|---|---|---|---|
  | Arcana | 63% | 88% | 65% | 70% |
  | Fire | 75% | 95% | 88% | 88% |
  | Frost | 82% | 87% | 87% | 85% |
  | Wind | 57% | 78% | 78% | 88% |

  - Average about 80%. Seven pairings are over the 85% cap for the bot; Holy pairings are the easiest.
  - Fixed by the difficulty pass below.

## Difficulty pass (2026-11-21)
- **New setting:** `"difficulty"` in `data/progression/run_rules.json`. Enemy HP is scaled when enemies spawn, and attacks when they are planned, so the intent shows the real number (`CombatManager._apply_difficulty`). It has global factors plus extra factors for elite and boss fights. Test: `tests/combat/run_difficulty_tests.gd`.
- **Tried:**
  - Elites x1.15 HP / x1.1 damage and bosses x1.2 / x1.15: average 58%. Too hard for teams that deal little damage (Wind + Tanking 23%, Arcana + Tanking 32%). Extra HP punishes low damage most.
  - Elites x1.05 HP / x1.1 damage and bosses x1.05 / x1.15 (kept): average 66%. Extra damage hits the strong healing and Block teams more evenly. Wind + Tanking was still 28%.
- **Card changes for the weakest pairings:**
  - Shield Strike (Tanking starter): 6 damage plus half Bianca's Block (upgraded 9 plus half). Tanking's Block now also hits.
  - Momentum Bash: +3 per card already played (upgraded +4), was +2 / +3.
  - Gust: 4 damage (was 3). Wind's own damage carries pairings with no status to spread.
- **Final** (60 runs per pairing):

  | Chiara | Tanking | Holy | Ashveil | Venom |
  |---|---|---|---|---|
  | Arcana | 53% | 78% | 55% | 55% |
  | Fire | 63% | 75% | 72% | 80% |
  | Frost | 73% | 82% | 68% | 80% |
  | Wind | 52% | 73% | 73% | 81%* |

  - Average 70%. Every pairing is within 40-85%.
  - \*Wind + Venom showed 90% at 60 runs and 81% over 200 (noise).
  - Normal fights are unchanged (factor 1.0). Runs are still mostly decided at the Forest Serpent, then the Sandstorm Elemental and the Sand Giant.

## Venom tuning (2026-11-21)
- **Problem:** in the per-fight simulation, Venom pairings ended the castle elite fights with 63-77% party HP, as much as the regular final fight. Holy pairings ended them with 29-56%.
- **Cause, measured:**
  - Damage per turn against the Knight Commander: about 24 with Venom (two-thirds from Poison), about 13 with Holy or Ashveil. Venom finished elites in about 5 turns instead of about 10.
  - Lowering the passive (+1 instead of +2) or Envenom alone changed little. Every Strike also adding Poison was the bulk of it.
- **Change:**
  - Venom Strike: 6 damage + 1 Poison (was 5 + 2); upgraded 8 + 2 (was 7 + 3).
  - Envenom: 3 Poison (was 4); upgraded 5 (was 6).
- **Sandstorm Elemental:** its Wind resistance is now 40% (was 75%, the cap, so Wind did only a quarter of its damage). With starting decks, Wind + Holy won 0% and Wind + Tanking 12% of isolated fights against it. At 40%: 18% and 67%. The result is very sensitive: 13% at 50% resistance, 88% at 35%.
- **Per-fight simulation:** 1 failure of 385 (was 9). Frost + Venom keeps 68% HP against the Knight Commander, against 74% in the regular final fight; the check wants at least 8 points between them.
- **Full runs** (60 per pairing):

  | Chiara | Tanking | Holy | Ashveil | Venom |
  |---|---|---|---|---|
  | Arcana | 53% | 78% | 55% | 57% |
  | Fire | 63% | 75% | 72% | 70% |
  | Frost | 73% | 82% | 68% | 82% |
  | Wind | 72% | 82%* | 80% | 85% |

  - Average 72%. \*Wind + Holy showed 87% at 60 runs and 82% over 200.

## Relics (2026-11-21)
- **Change:** 23 relics (19 from elites and chests, 4 boss relics offered as a choice of 3 by bosses). Every elite now leaves a relic.
- **Effect on runs:** the average rose from 72% to 80%; Fire + Holy, Fire + Ashveil, Wind + Holy and Wind + Ashveil went over 85%. Runs at the coast got easy (the Sandstorm Elemental ended 8 runs of 960): a boss relic from the forest carries the party.
- **Difficulty raised to match:** elites x1.1 HP and x1.15 damage (was 1.05 / 1.1), bosses x1.1 HP and x1.2 damage (was 1.05 / 1.15).
- **Bug found and fixed:** a relic that fells the last enemy at the start of a turn (Mercury Bell, Dragon Heart) did not end the fight.
- **Final** (60 runs per pairing):

  | Chiara | Tanking | Holy | Ashveil | Venom |
  |---|---|---|---|---|
  | Arcana | 53% | 72% | 50% | 63% |
  | Fire | 73% | 83%* | 80% | 82% |
  | Frost | 72% | 77% | 72% | 70% |
  | Wind | 77% | 88%* | 80% | 82% |

  - Average 74%. \*Over 200 runs: Fire + Holy 83%, Wind + Holy 88%.
  - **Open:** Wind + Holy stays 3 points over the cap; Holy's healing stacks with the healing relics (Healer's Pendant, Phoenix Feather).

## Card-pool expansion (2026-11-22)

72 new reward cards (9 per specialization) with Powers, Retain and X cost; COMBAT_SYSTEM.md, "Card keywords".
The bot values a Power by the enemy HP left in the fight and plays X cards with all its Energy.

- **First result** (60 runs per pairing): average 76%. Wind pairs rose to 87-93% (Zephyr Stance and
  Sharpened Winds fed Gust every turn), and Arcana + Venom fell to 45%. Experiments `old_pool_<spec>`
  (`run_simulation.gd`, drops the 9 new cards) showed the new Tanking pool alone added 8 points to Wind + Tanking.
- **Changes:**
  - Wind: Gust 4 -> 3 damage; Zephyr Stance costs 2 (1 Gust a turn, 2 upgraded); Sharpened Winds costs 2
    (+1; upgrade costs 1); Featherstep 5 Block +1 per card (7 upgraded); Crosswind 3 + (3 +2 per card).
  - Arcana: Arcane Mastery costs 1 (+3 damage, +4 upgraded); Mana Burst 8 x X (10 upgraded).
  - Tanking: Spiked Bulwark thorns 3 -> 2; Iron Skin 4 -> 3 Block at the end of the turn.
- **Result** (60 runs per pairing, 16 pairings): average **74%**, every pairing 50-87%.
  - Arcana 50-75% (Venom 50%, Ashveil 55%, Tanking 60%, Holy 75%); Fire 75-87%; Frost 68-78%; Wind 78-87%.
  - Fire + Holy and Wind + Holy read 87% at 60 runs; at 150 runs both are 85%, on the cap. Holy pairings
    also end runs with the most gold (350-417 against about 200).
- **Open:** Arcana is the weakest Chiara (Arcana + Venom 50%); Holy is the strongest Bianca. Watch both
  with the next content; a small Holy trim is the first lever if it rises.

## Frostpeak (2026-11-22)

Simulated alone from a fresh party (`run_simulation.tscn -- <runs> "" map:frostpeak`).

- **First result** (30 runs per pairing): average 57%, 23-80%. The White Dragon (220 HP, frost 75%)
  ended 155 runs, and Frost + Holy fell to 23%.
- **Changes:** the dragon got 195 HP, frost resistance 50% and wind 25%, and Frost Breath 7, Crystal
  Talons 13 and Absolute Zero 10. The Yeti's fire weakness dropped from 50% to 25% (plus lightning 25%).
- **Result** (40 runs per pairing): average about 72%, 48-85% (Fire + Tanking 85% at 80 runs). Holy
  pairings are the weakest here (Frost + Holy 48%, Wind + Holy 53%): their damage is slow against a
  195 HP dragon. The Icefall (drake + wraith) and the Crystal Matriarch are the hardest fights on the way.

## Persistent campaign (2026-11-22)

Combat numbers are unchanged; the campaign changes what the party brings:
- The purse still starts at 30 gold, so merchants are balanced as before. Treasury income: a completed
  mission returns the whole purse plus 30-200 gold of rewards.
- Power growth is slow by design: a prepared deck is capped at 15 cards per sister, permanent upgrades
  cost 40-180 gold each, refinement adds +2 HP / +5% per level (max 2), the heirloom slot carries one
  relic, and the potion belt holds 3 (4 after a 120-gold upgrade).
- Map rerolls keep fights within their terrain and depth band, so the difficulty curve of each map is
  kept. Generated missions draw fights from the template's bands by row.
- **Not yet measured:** the simulation bot plays classic runs only; campaign expeditions with upgraded
  collections, hybrid decks and fusion cards have not been simulated. Expect expeditions to get easier
  as the collection grows; difficulty modifiers by region threat are a planned lever.
