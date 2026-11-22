# Combat System

Logic: `scripts/combat/combat_manager.gd` (no UI). UI: `scripts/ui/screens/combat_screen.gd` listens to `changed` / `message` / `ended` signals.

- Shared party deck: `PartyDeck` builds `CardInstance`s from every member's `OwnedCard`s (ownership, upgrade level kept), shuffles with an injectable RNG. Piles: draw, hand, discard, exhaust. Empty draw pile reshuffles the discard pile. Hand cap 10.
- Static `CardDef`s are never mutated; instances only reference them (verified by tests).
- Turn: 3 shared Energy, draw 5, discard hand at end of turn. Party block resets at the start of the player's turn, enemy block at the start of that enemy's action.
- Playable only if: player turn, owner alive, enough Energy. Power cards are exhausted on play.
- Effects are data (`"effect": "damage|block|heal|apply_status|draw|gain_energy"`) resolved by `CardEffects` with an `EffectContext` (combat, owner, card, chosen target) - the hook for future cross-character/combo effects.
- Enemies: `EnemyDef` pattern of named actions (`data/enemies`); `EnemyAI` plans an intent (shown to the player) and resolves its target at execution time so Taunt can redirect it. Statuses decay one stack per round.
- End: victory when all enemies are down (HP committed to the party, fallen revive at 1 HP), defeat when the party is wiped.

## Milestone 3: statuses, Burn and passives

**Status definitions** live in `data/statuses/` (`StatusDef`, `DataRegistry.get_status`). Rules for every status: stacks = turns remaining; all statuses lose one stack at the end of each round (after the enemy phase); applying a status again adds stacks. A status may define a `tick` (timing, damage, ignores_block).

**Burn**: 2 damage, ignoring Block, at the start of the enemy phase (before enemies act); applying Burn N gives exactly N ticks. It ticks on whoever carries it, even if the applier has since fallen. Enemies killed by a tick never act; the last enemy dying to Burn ends combat in victory. The enemy panel shows `Burn 3 (2 dmg/turn)`, with a tooltip.

**Cleanup**: a fallen combatant loses statuses, Block and intent immediately; on victory or defeat every combatant's statuses and Block are cleared.

**Damage modifiers** (data on the `damage` effect): `bonus_if_status {status_id, value}` (Fuel the Flames) and `per_source_block` (Radiant Bulwark: attacker's current Block x factor; Block is not consumed). Block absorbs all damage except Burn ticks; healing never exceeds max HP and never revives.

**Passives** (`PassiveRunner`, data in the specialization's `starting_passive`: `trigger`, `limit_per_turn`, `effect`):
- Timing: reacts immediately after the triggering card effect, during the player turn. Counters reset when a new player turn starts.
- Recursion: bonus effects call combatant methods directly and emit no events; events raised while a passive resolves are ignored.
- Fallen owners never trigger. Passive damage is normal damage (absorbed by Block).
- **Kindled Spark** (Fire): first time Chiara applies Burn each turn -> that target takes 2 extra damage. Several targets in one effect trigger once (first target).
- **Blessed Aegis** (Holy): first time Bianca receives Block from a *card effect* each turn (her own, or an ally's card targeting her) -> +2 Block. Not triggered by Block from the passive itself or non-card sources.
- UI: party panels show `Passive: ready / used this turn`; triggers appear in the combat log with a star.


## Combat presentation (Milestone 4)
Purely visual, no rule changes. `CombatScreen` compares each combatant's HP and Block with the previous refresh and shows a floating number (red damage, green heal, pale-blue Block) plus a brief panel flash; Burn ticks and passive bonuses appear the same way because they change HP/Block. Enemy panels show an intent icon (crossed swords = attack, shield = defend), HP/Block icons and a Burn row with the Burn icon and tooltip. Party panels show the specialization badge, Block and passive state ("Kindled Spark: ready / used this turn / fallen"). Victory is gold with both portraits and the gold reward; defeat is crimson with greyed portraits. The room backdrop comes from the map node (`AssetCatalog.room_backdrop`) under a 72% veil so text stays readable.


## Combat visual effects (Milestone 4B)
Presentation only; no rule, value or timing changed. `CombatManager.visual_event(event)` fires right after a gameplay effect has been applied (`CardEffects._announce`), after each status tick (Burn), after a potion heal and when an enemy intent resolves (`enemy_attack` on the party member hit, `enemy_defend` on the enemy itself), with `kind` (damage, heal, block, apply_status, status_tick, draw, gain_energy), `card_id`, `specialization_id`, `source_id`, `target_ids`, `target_group` and `status_id`. Nothing is announced for a card that is merely drawn, displayed, selected or unaffordable.

`data/effects/combat_vfx.json` maps events to effects with ordered rules (first match wins: card id, then status, then specialization + kind, then kind). `CombatVfxManager` (a full-screen input-transparent layer in the combat screen) waits one frame for the UI to rebuild, finds each target panel through a locator callable, and spawns `CombatVfx` nodes (`scenes/combat/combat_vfx.tscn`) with a short stagger. Motions: projectile (travels from the caster's panel to the target, then spawns an impact effect), burst, pulse (shields), rise (healing, Burn), sweep (area). Single targets get one sprite, area effects with `group_fit` get one sprite over the enemy group (capped by `group_max`), party Block/heals put one sprite on each recipient. Sizes scale with the viewport height (720 = 1.0) and the target panel width. Missing sprites draw a generated radial glow instead; unknown events or off-screen targets are skipped.

Performance: one TextureRect per effect, textures cached, one shared additive material, one tween per effect, at most 24 simultaneous effects (8 on Reduced). Settings > Combat effects: Full, Reduced (shorter, one sprite per multi-target event, no impact sprites) or Off. Every node ignores mouse and touch input.

## Battlefield presentation (Milestone 6)
`CombatScreen` hosts a `CombatBattlefield` (enemies left, party right), a `CombatHand` of reused `CardView`s and a `CombatAnimationController` that listens to `CombatManager.visual_event`. Poses, cut-ins and tiers come from `data/combat/combat_presentation.json` through `CombatPresentation`. Effects quality: Full = poses + cut-ins, Reduced = poses only, Off = none. Touch: first tap arms a card, second tap on a valid target plays it; Cancel clears. Presentation is purely visual and never changes or delays resolution.


## Milestone 7 additions
- Elite encounters: `"elite": true` on an encounter (data/encounters/elite_encounters.json) and on enemies (data/enemies/elite_enemies.json). Same rules as normal combat; presentation adds an ELITE tag, an introduction banner (non-blocking, fades), a gold sprite tint and a star in the name. Elite victory: more gold and a card reward of 4 options with at least one uncommon or better (`elite_defaults` in `data/progression/run_rules.json`).
- Relics (data/items/relics.json): `combat_start_block`, `first_turn_draw` (applied by `CombatManager` on turn 1), `heal_after_victory` (applied once by `GameState.record_combat_victory`).
- Combat battlefield now uses `assets/environments/0_castle/castle_generic.jpg` as a side-view backdrop (enemies left, party right).
- Combat save strategy: a checkpoint. Entering a combat or elite room saves the run (`room_state` kind combat/elite). Quitting mid-fight and continuing restarts that fight from its entry state (HP, deck and gold as they were). Victory saves the "reward" phase (gold, healing, and the rolled reward are applied once and stored), so reloading shows the same reward and never grants it twice. Full mid-turn serialization (piles, statuses, intents, RNG) was not implemented on purpose.

## Slay-the-Spire style layout (Milestone 7 follow-up)
Top bar: both characters' vitals chips (name, HP bar, HP, Block, passive/status line), encounter title, phase and log, energy icon with `n/max`, and Draw / Discard / Exhaust buttons that open a card list (draw pile shown sorted, never in draw order). Enemy health bars stay on the enemies. The hand sits at the bottom with raise/enlarge/glow on the selected card. The battle backdrop has no colour wash or veil. When a character falls, `PartyDeck.set_owner_inactive` sets their cards aside (draw pile, hand and discard pile) so only the remaining characters' cards are drawn or reshuffled for the rest of the combat.

Battlefield sizing (follow-up): all units share one ground line and one sprite height (62% of the battlefield, max 270 px, Slay-the-Spire scale). Enemies show only a life bar below them and an intent badge (icon + number) above; hovering or tapping an enemy opens its details (name, HP, Block, full intent text, statuses). Character vitals are compact chips in the top bar; passive readiness and statuses are in the chip tooltip.

Follow-up (QA pass): units are grouped close together around the centre of their side on one ground line; defeated enemies fade out and vanish completely (sprite, life bar, intent badge, popup). The top bar, character chips, enemy hover menu and every tooltip use the ornate panel art of the other game menus (`UITheme.compact_panel_style`, `compact_button_style`, tooltip theme items).


## Milestone 8: forest enemies, Poison, the Forest Serpent
- **Enemy actions** (data only) may now carry `"status": {"id", "value"}` (applied to everyone the attack hits, even through Block) and `"target": "all"` (hits every living party member). Intents show both ("Venom Strike: 11 dmg +3 Poison -> Chiara", "... -> whole party"); the badge above the enemy shows the number, "all" and the poison amount.
- **Poison** (`data/statuses`): at the start of the enemy phase the victim takes damage equal to its stacks, ignoring Block, then loses 1 stack (`tick.per_stack`). Burn is unchanged (fixed 2).
- **Enrage:** an enemy may define `enrage_below` (share of max HP) and `enraged_pattern`; below that health it switches pattern.
- **Forest enemies** (`data/enemies/forest_enemies.json`): Wolf 22 HP (7 / block 4 / 10), Boar 30 (9 / block 6 / 13), Venom Spider 18 (4 +2 Poison / 6 / block 5), Bear 48 (8 / 13 / block 8), Drake 40 (9 / 5 +3 Poison / block 8), Moss Troll 64 (14 / block 10 / 8 to all). Elites: Alpha Wolf 58 (11 / block 10 / 15) with two wolves, Grove Warden 105 (17 / 10 to all / block 14), Broodmother 66 (7 +4 Poison / 13 / block 12) with two spiders.
- **Forest Serpent** (boss, 150 HP): Venom Strike 11 +3 Poison, Serpent Coil 12 Block, Toxic Breath 5 to all +2 Poison, Forest Quake 15. At or below 50% HP: Ancient Venom 6 to all +3 Poison, Forest Quake, Venom Strike, Coil. Reward: 120 gold and a 4-card choice with a guaranteed rare. Values were lowered from a first draft (190 HP) after the simulation showed 0-17% wins.
- **Simulation** (`tests/combat/balance_simulation.gd`, greedy policy, decks with reward pools, full HP per fight): normal forest fights 100% wins with 55-96% HP left; elites 100% with 23-65% left; the Serpent 65-100% with 11-45% left. A real run arrives wounded, so the boss is harder in practice.
- **Presentation:** forest sprites come from `assets/enemies/1_forest` (see COMBAT_ASSET_INVENTORY.md); slots adapt to wide animals; `enemies.scale` in `combat_presentation.json` draws elites and the boss larger; the boss has a BOSS tag and banner; forest fights use the forest backdrop (`battle_backdrop` of the map). Poison attacks, poison application and poison ticks use the poison sprite through the existing CombatVfx rules.
- **Polish:** units have a contact shadow, a subtle idle breathing (full quality only), a lunge on attacks, a recoil and shake on hits, a brace on blocks and a hop on casts; defeated enemies sink and fade. All of it is skipped when effects are Off and none of it delays combat.

## Damage over time: Burn, Poison, Bleed (distinct rules)
| Status | Damage | Duration / stacking | Ignores Block | Icon |
|---|---|---|---|---|
| **Burn** (fire) | fixed **3** at the start of the enemy phase | stacks = turns left, new Burn adds turns but **never more than 4** (short and hot) | yes | flame (`fire/burn_apply`) |
| **Poison** (venom) | **equal to its stacks** at the start of the enemy phase, then -1 | stacks without limit (slow, builds up) | yes | skull (`nature/poison_skull`) |
| **Bleed** (wounds) | **no tick**: every *attack* that costs HP makes the victim lose Bleed more HP, then Bleed -1 | never fades over time; only hits use it up | yes (the extra loss) | red slash (`wind/wind_slash`, tinted) |
All attack damage (cards, enemy moves, passives) goes through `CombatManager.hit()`, which applies Bleed; status ticks do not, so they never trigger Bleed. `StatusDef` gained `max_stacks`, `decay` ("round" / "on_trigger") and `on_hit` ("stacks"). Enemy intents show the status their attack adds with its own icon (e.g. sword 7 + slash +2). Sources: Venom Spider, Forest Drake, Broodmother, Forest Serpent (Poison); Forest Wolf's Rending Bite, Alpha Wolf, Bear's Maul, Boar's Charge (Bleed); Chiara's Fire cards (Burn). Kindle now applies 2 Burn (upgrade 3) because each tick is hotter.


## Damage types, weaknesses and resistances
Every hit has a damage type (`data/combat/damage_types.json`): physical, fire, frost, arcane, holy, shadow, lightning, wind, poison. One rule (`DamageTypes.apply`, used by `CombatManager.hit`):

    final = base x (100 + attacker bonus + target modifier + status vulnerability) / 100   (rounded, at least 1)

- **Attacker bonus:** weapons (`Combatant.damage_bonus`, e.g. Ember Staff +15% fire).
- **Target modifier:** enemy `weaknesses` (+) and `resistances` (-) in `data/enemies`, armour resistances for the party (`Combatant.affinity`). Resistance is capped at 75%.
- **Status vulnerability:** Chill adds +10% physical damage taken per stack.
- **Card damage type:** the effect's `element`, else the specialization's `damage_element` (Fire = fire, Arcana = arcane, Frost = frost, Holy = holy, Tanking = physical).
- **Enemy attacks:** the action's `element`, else the enemy's `element` (default physical). The intent text names non-physical types ("6 fire dmg"), and the badge number takes the type's colour.
- **DoTs:** Burn ticks are fire and Poison ticks are poison, so weaknesses and resistances apply to them. Bleed's extra loss ignores types.
- **Presentation:** when a type changes the damage, a `visual_event` of kind `affinity` makes the screen pop "Weak! Fire" or "Resist Physical" over the unit. The enemy hover popup lists its weaknesses, resistances and initiative.

## Initiative, Chill and Frozen
- **Initiative:** each enemy has `initiative` (default 3). In the enemy phase they act highest first; ties keep the battlefield order.
- **Chill (Frost):** -1 initiative and +10% physical damage taken per stack, max 5 stacks, -1 per round.
- **Frozen:** at the start of the enemy phase, an enemy whose initiative is 0 or less (and that has Chill) is Frozen. It loses its action and its Chill shatters (removed), so it cannot be kept frozen without new Chill. The intent badge already shows "Frozen" during the player turn, so the outcome is predictable.
- **Bosses and elites:** bosses have initiative 6-7, above the Chill cap, so they are never frozen. Elites have 4-6, so freezing one needs most of a turn's Chill.
- **Combo:** Chill's physical vulnerability is what makes Frost pair with Bianca's Tanking (physical) cards.


## Water and earth (Act III)
- **New damage types:** water and earth, in `damage_types.json`.
- **Soaked** (water): +15% lightning and frost damage taken per stack, max 3, -1 per round. Statuses may now list several elements in `vulnerable.elements`.
- **Sandblind** (earth): the bearer's attacks deal 25% less damage (`damage_dealt_pct`), max 3 turns. It changes the attacker's numbers, so the target shows no "Resist" pop-up.
- **Quicksand** (earth): the party draws 1 fewer card at the start of its turn for each sinking member, at most 2 fewer. One stack is used per turn (`decay: on_trigger`, `draw_penalty`).
- **Immunity:** equipment can grant it (`stats.immune`). `Combatant.immunities` blocks the status, and the log says the gear warded it off.
- **Coast enemies:**

  | Enemy | Type | Weak to | Resists | Notes |
  |---|---|---|---|---|
  | Giant Crab | — | lightning, frost | physical, fire, water | slow; pinch makes you bleed |
  | Dire Albatross | wind | physical, arcane | wind | fast; Storm Dive is lightning |
  | Triton Soldier | water | lightning, frost | fire, water | Tide Surge soaks |
  | Rock Spider | earth | frost, holy | physical, poison, earth | Sand Web: Quicksand; Stone Fang poisons |
  | Sand Giant (elite) | earth | frost | — | its gust Sandblinds the party |
  | Rock Giant (elite) | earth | arcane | physical 40% | hurls boulders, Quake hits everyone |
  | Sand Scorpion | earth | arcane 50%, frost | earth, fire, poison | Sand Spray Sandblinds, Venom Sting poisons. Shore rooms only |
  | Shark Knight | water | lightning, holy | water, frost, physical 15% | Riptide Cleave soaks the whole party; Frenzied Bite bleeds. Sea rooms only |
  | Sea Snake (elite) | water | lightning, holy | frost, water | Brine Spray soaks everyone, then poison and bleed |
  | Sandstorm Elemental (boss) | earth | frost 50%, arcane | physical, holy, wind, earth | initiative 8, never frozen; Sandblind and Quicksand, enrages at half HP |

  Fire finds no coast weakness on purpose: the coast is wet.
- **Attack effects:** enemy attack events now carry `element` and `action_id`, and VFX rules can match both (`VfxCatalog.MATCH_KEYS`):
  - water attacks splash;
  - earth attacks throw a sand blast;
  - the Rock Giant's Boulder Hurl flies as a boulder;
  - Brine Spray and Tide Surge are waves.


## Standing on the floor (all battle backdrops)
- **The feet line:** the battlefield puts every unit's feet on one ground line, about 0.615 of the screen height. On a 16:9 picture that is 62% down. Wider screens crop the picture, so the line lands lower on it.
- **Floor data:** each battle backdrop has an entry in `combat_presentation.json` `"floors"` (`CombatPresentation.floor_info`):
  - `top`: where its walkable floor begins, measured on the picture.
  - `anchor_y`: how much of a wide screen's crop comes from the top. The default 0.8 drops sky and keeps floor (`RoomBackdrop.anchor_y`).
  - `zoom`: an optional zoom anchored at the bottom, for pictures whose floor starts too low. Units must stand at least 7% of the picture height inside the floor; the ship deck, forest, chasm and ruins use it.
- **Checks:**
  - `tests/map/run_terrain_tests.gd` places the feet line on every backdrop on 16:9, phone (1558x720) and ultrawide (1706x720) screens. It must land at least 0.015 below the floor top.
  - `tests/progression/terrain_flow_test.tscn` opens a fight on every terrain of every map at three window sizes. It measures each sprite's lowest opaque pixel: grounded units must touch their slot's floor (6 px tolerance) and stand on the picture's floor. Hovering units are checked by their shadow.
- **Facing:** enemies stand on the left and must face right, toward the party. The Shark Knight and Sand Scorpion sprites were mirrored after generation for this.
- **New forest monsters:**

  | Monster | HP | Initiative | Attacks | Weak to | Resists |
  |---|---|---|---|---|---|
  | Cliff Harpy (mountain) | 24 | 6, hovers | Talon Rake (7, Bleed 2), Shrieking Gale (4 wind to all), Take Wing (Block 6) | lightning 50%, arcane 25% | wind |
  | Will-o'-Wisp (deep wood) | 20 | 5, hovers | Ghostfire (5 fire, Burn 2), Drain Light (3 shadow to all), Flicker (Block 6) | holy 50%, frost 25% | fire 75%, physical 25% |


## Oiled (Ashveil)
- **Effect:** "Slick with oil." The bearer deals 15% less attack damage (`damage_dealt_pct`) and takes +15% Fire damage per stack. Max 3 stacks (+45% at most), -1 per round.
- **Combo with Chiara:** Chiara's Fire cards and Burn ticks (Fire) all count. Frost and the other damage types are not affected.
- **Ignition visual:** when a status makes a hit land harder, `CombatManager.hit` emits a `status_exploit` visual event `{status_id, element}`. The VFX rule `status_exploit` + `oiled` plays the oil bursting into flame (`oil_ignite`). Soaked and Chill could get their own rules.
- **Element in card hits:** card damage events now carry `element`.
- **On the enemy:** an Oiled enemy turns dark and glossy (status tint) and shows the black oil-drop chip.
- **Card effects:** applying Oiled splashes black oil. Ashveil Block is a smoke veil (a smoke cloud when it covers the party). Blasting Powder and Ashfall explode, Caltrops scatter, and the slashes are ember-coloured (Shadow Thrust in violet).


## Aether (the Arcana + Holy combo)
The three combos each have their own engine: Frost makes enemies physically vulnerable for Tanking (Chill), Ashveil soaks them for Fire (Oiled), and Arcana feeds Holy with **Aether**.
- **What it is:** the party's surplus magic this turn, a counter on `CombatManager` (`aether`, max `MAX_AETHER` = 6), not a status. It is not tied to a character, so the rules engine has no Arcana or Holy logic.
- **Gaining it:** every Energy gained (`gain_energy`) and every card actually drawn (`draw`, and the `draw_cards` passive effect, which includes Arcane Flow) during the player's turn adds 1. The turn's normal draw does not count. A draw that finds no card adds nothing.
- **Fading:** unused Aether is lost when the next player turn begins.
- **Using it:**
  - Any effect may carry `"per_aether": N`, which adds N to its value per point of Aether. It works for damage, Block and heal.
  - The `spend_aether` effect, always placed last on a card, releases all of it after the card's other effects have read it.
  - A heal whose value is 0 (an Aether heal with no Aether) is skipped.
- **Cards:**
  - Arcana builds it: Ley Siphon, Arcane Echo, Leyline Weave, plus the existing Focus, Mana Surge, Insight and Time Fold.
  - Holy spends it: Hymn of Dawn, Radiant Cascade, Lightfall, Wellspring Prayer.
  - Aether Lance is Arcana's own small payoff, so Arcana is not empty-handed with Tanking or Ashveil.
  - Other specializations' draw and Energy cards also make Aether, so Holy's hymns work in every pairing, just best with Arcana.
- **UI:**
  - A violet counter (icon `icon_aether`, `AetherBox`) next to Energy. It is shown when the party has Aether cards or some Aether, dims at 0, pops when it changes, and has a tooltip.
  - The word "Aether" is violet on cards (`CardTextFormat.AETHER_COLOR`).
- **Visuals:**
  - Releasing Aether emits `aether_spent {amount}`, which plays a gold-and-violet light burst on Bianca (`aether_release`).
  - Lightfall's hit is its own pillar of light (`lightfall`).
  - Gaining Aether emits `aether_gained {amount, total}`. No effect is drawn for it: the draw and Energy effects already play.
- **Tests:** `tests/specializations/run_aether_tests.gd`.


## Combat UI fixes
- **Enemy panel:** the hover panel can no longer stick. While open, it checks every frame that the pointer is still over the enemy; leaving also closes a click-pinned panel. On touch screens a tap pins it until the next tap elsewhere.
  - It uses compact text (13 px lines, 16 px name) and explains every status in full, which also serves touch screens.
- **Status chips:** they receive hover now (they were set to ignore the mouse), so their tooltip explains the status.
- **Cards:** each card fits its own text after layout. The name shrinks to one line (down to 10 px), then the effect text (down to 10 px). If it still cannot fit, the card shows its full text on hover (`CardView.text_clipped`). A test renders all 74 cards and their upgrades and requires every one to fit.
- **Potions:** tapping a potion arms it (green frame). The living allies glow green, the one under the pointer gets a thick white outline and a slight lift, and tapping an ally makes them drink it. Tapping the potion again or empty ground cancels. `CombatManager.use_potion(item, target_id)`.
  - Any valid target under the pointer is highlighted the same way, for cards too.
- **Pile viewer:** draw, discard and exhaust open above everything (z 200, nearly opaque), and the battle is hidden while it is open.
- **Reward screen:** cards shrink step by step (down to 0.85) until the footer buttons are fully on screen, for example with the epic note and a loot strip.
- **Exhaust:** cards can be one-use per combat with `"exhaust": true` (`CardDef.exhausts`; powers always exhaust).


## Cards: look and motion
- **Card face (`scripts/ui/card_view.gd`):**
  - **Resolution:** a fixed 300 x 428 face in design coordinates, scaled to the card's size. It is twice the usual on-screen size, so text and edges stay crisp in the hand, on hover zoom and on large reward cards.
  - **Frame (`resources/shaders/card_frame.gdshader`):** bevelled dark metal, a rim in the owner's colour (Chiara blue, Bianca gold), a gold hairline, and a colour-graded body with a faint lattice and grain. Gold rivets sit in the corners. Epic cards shimmer.
  - **Glows:** playable (soft blue, breathing; hand only), hovered (bright) and selected (gold).
  - **Unplayable cards:** desaturated, with the cost in red.
  - **Art window (`card_art.gdshader`):** its silhouette shows the type: attack has a blade-point bottom, spell an arched top, power is an oval, and everything else a rectangle. The picture is cover-fitted (atlas pictures included) inside a gold border.
  - **Name ribbon:** coloured by rarity: basic slate, common silver, uncommon teal, rare gold, epic violet. The name is in Cinzel and shrinks to one line; upgraded names are green.
  - **Cost orb:** a glossy energy gem.
  - **Type plaque:** in the type's colour.
  - **Owner medallion:** her round portrait.
  - **Rules text (`CardTextFormat`):** numbers in bold white (green when upgraded), damage types in their element colour, statuses and card keywords in gold.
  - **Fitting:** the text shrinks to fit; if it still cannot, hovering shows it whole (`text_clipped`).
- **Hand (`scripts/ui/combat/combat_hand.gd`):** cards fan in an arc with a slight rotation. Hovering pops a card up, straight and 1.22x. The card waiting for a target stays raised with a gold glow.
  - **Draw:** cards fly in from the deck (bottom left), staggered. During the enemy phase they wait at the deck (`draw_hold`), so the next hand appears only when the enemies are done.
  - **Play:** the card rises to the gap between the party and the enemies (never over the caster or the target), flashes, then sweeps into the discard pile, or burns away (frame dissolve) when it exhausts. The screen calls `mark_played` before `play_card`.
  - **End of turn:** the hand sweeps off to the discard pile (`begin_discard`).
  - **Layout:** a newer layout always cancels the card's running slide, so hover and select never fight.
  - **Effects Off:** all motion is skipped.
- **Tests:**
  - `tests/ui/card_gallery_test.tscn` (look-book, type silhouettes, states, all 148 cards and upgrades fit).
  - `tests/ui/card_motion_test.tscn` (fan, hover, select, play, exhaust, discard, draw timing).


## Every card shows an effect
- **Rule:** every effect of every playable card (starting decks, reward pools, epic pools, upgrades) matches a VFX rule in `data/effects/combat_vfx.json` that is specific to the card, its specialization or its status. The generic per-kind fallbacks remain only for enemies and passives.
- **Ashveil:**
  - Oil splashes black oil (Oil Flask throws a flask first).
  - A single Block wraps the ally in a ring of smoke (hollow, so her block pose stays visible); a party-wide Block (Smoke Bomb, Veil of Ash) is a smoke cloud over the party.
  - Ember slash, shadow thrust, caltrops, powder blast and oil ignition each have their own sprite.
- **Per specialization:** card draw (glowing cards), energy (a crystal burst) and heals (Holy gold, Arcana violet, Tanking "second wind" green) are tinted for their specialization; Arcana's draw is the mana surge.
- **Dark effects:** oil, smoke, the flask and the caltrops are cut-out sprites drawn with normal (`mix`) blending, because additive blending makes dark pixels invisible. Light effects (slashes, glows) stay additive.
- **Layering:** the effect, cut-in and floating-number layers use `z_index` 10 (`CombatScreen.VFX_Z`), above unit sprites (1) and their status chips (9), so an effect inside a character's silhouette is never hidden. Hovered and played hand cards (z 100 / 200) and overlays stay above them.
- **Tests:**
  - `tests/combat/run_card_vfx_audit.gd` (headless; `-- report` lists every card effect and its visual).
  - `tests/ui/card_vfx_showcase_test.tscn` (windowed; plays every Ashveil card plus the draw, energy and heal cards of the other specializations in a real fight, checks the expected effects spawn and that the effect layer draws above the unit artwork, and takes screenshots).


## Hover panels for every unit
- Enemies and party members share one detail panel (`CombatUnitView`: `_init_detail_panel`, `_set_hover`, `_on_detail_pressed`). Hover on desktop; tap to pin on touch; it closes when the pointer leaves, even if `mouse_exited` is missed.
- **Enemy:** name, HP and Block, intent, initiative, weaknesses and resistances, statuses explained.
- **Party member** (`CombatCharacterView`): name and specialization, HP and Block, the passive's state and rule, and every status explained ("No statuses." otherwise). It opens toward the middle of the battlefield and stays open for a fallen ally.
- Test: `tests/ui/combat_ui_fixes_test.tscn` ("Party hover panel").



## Twin combos: reactions, Gusts, Momentum and Blight
Every playable Chiara specialization works with every playable Bianca specialization (16 pairings). Five are signature combos; the rest are lighter but real. The guide is `data/combat/twin_combos.json`, and the selection screen shows it.

The inspiration is Slay the Spire 2's engines:
- Stored resources: Aether, like Regent's Stars.
- An execute threshold: Blight, like Necrobinder's Doom.
- Cheap generated cards: Gusts, like Silent's Shivs.

The rules are this game's own. Each needs one sister to set it up and the other to cash it in.

### Twin reactions (`data/combat/reactions.json`, `scripts/combat/reactions.gd`)
After a party member's hit (card or passive), a reaction resolves if the hit's element matches a reaction and the enemy carries that reaction's status.
- **Never triggered by:** status ticks, enemy hits, or a reaction's own damage (`CombatManager._reacting`).
- **Effect types:** `detonate`, `spread`, `add_status`, `shatter`, `block_source`.

| Reaction | Hit | On | Effect | Pair |
|---|---|---|---|---|
| Combustion | Fire | Poison | Poison removed; 3 Fire per stack to EVERY enemy | Fire + Venom |
| Miasma | Wind | Poison | Half the Poison (min 1) to every other enemy | Wind + Venom |
| Fanned Oil | Wind | Oiled | Half the Oiled (min 1) to every other enemy | Wind + Ashveil |
| Black Ice | Frost | Oiled | +1 Chill | Frost + Ashveil |
| Frostbite | Frost | Poison | +2 Poison | Frost + Venom |
| Shatterlight | Holy | Chill | Chill removed; 2 Holy per stack | Frost + Holy |
| Purifying Flame | Holy | Burn | The attacker gains 1 Block per Burn | Fire + Holy |
| Searing Bash | Physical | Burn | +1 Burn | Fire + Tanking |

**Presentation:**
- Each reaction emits `reaction {reaction_id, reaction_name, color}`.
- Its name pops over every unit it touched: "Combustion!" on the target, "+Combustion!" on the others.
- Each has its own VFX rule; `reaction_id` is a VFX match key.

### Gusts (token cards)
- **Tokens:** a card with `"token": true` never joins a deck and is never offered as a reward. It vanishes when played or at the end of the turn.
- **Creating them:** the `create_card` effect (on a card or a passive) adds tokens to the hand through `PartyDeck.add_tokens`, up to `MAX_HAND_SIZE`.
- **The Gust card** (`chiara_wind_gust`): costs 0 and deals 4 damage. With Chiara's Wind element, every Gust hit sets off Miasma and Fanned Oil.

### Momentum
- **Counter:** `CombatManager.cards_played_this_turn` counts the cards played this turn, tokens included. It resets when the player turn begins.
- **Card effects:** the key `"per_card_played": N` adds N per card already played this turn.
- **Tailwind:** Wind's passive watches for the third card of the turn (trigger key `cards_played`).
- **UI:** a jade counter (`MomentumBox`, icon `icon_momentum`) beside Aether, shown when the party has Wind or a Momentum card.

### Blight (Venom)
- **Status:** `blight`, with `execute: true` and `decay: on_trigger`. Blight never fades.
- **Execution:** at the start of the enemy phase, after Burn and Poison tick, a bearer whose HP is at or below its Blight perishes (`CombatManager._check_executions`, visual `execute`).
- **Sources:** Plague Reaping sets it from Poison (effect key `from_target_status`), and Scatter can spread it.

### Other new effect keys
- **`spread_status`** (`status_id` or `"all"`, `ratio`): copies half of the target's debuffs to every other enemy.
- **`multiply_status`** (`factor`): used by Catalyst and Death's Ledger.
- **`bonus_if_any_status`** (`status_ids`, `value`): used by Sunfire Smite.
- **`stacks_before`:** status application events now carry it, and the passive trigger key `target_already_had` reads it (Lingering Venom).

### Tests
- **`tests/specializations/run_twin_combo_tests.gd`** (headless): every reaction, Gusts, Momentum, Venom, Blight, the cross cards and the guide.
- **`tests/combat/sim_policy.gd`:** the greedy bot shared by both balance simulations. It values reactions, Momentum, Gusts and Blight.

## Difficulty
- `data/progression/run_rules.json` `"difficulty"`: `enemy_hp` and `enemy_damage` for every fight, and `elite_hp`, `elite_damage`, `boss_hp`, `boss_damage` multiplied on top for elite and boss fights. 1.0 everywhere = the enemy data.
- HP is scaled from the enemy data when the fight is set up (`CombatManager._apply_difficulty`; calling it again never compounds). Attack intents are scaled when planned (`Combatant.damage_scale`), so the number on the intent is the number that lands.
- Current values: normal fights 1.0; elites x1.1 HP and x1.15 damage; bosses x1.1 HP and x1.2 damage (BALANCE.md, "Relics").

## Encounter introductions
- Elites and bosses open with the full-screen introduction. A regular fight gets it too with `"cinematic": "<kicker>"` in its encounter (the Royal Castle's last fight, the Throne Hall Guards: "Final Battle"). The header tag shows the kicker, and the toughest foe leads the picture when no elite is present.

## Relics
- Data: `data/items/relics.json` (`"category": "relic"`). Fields: `rarity` (common, uncommon, rare, boss), `description`, `flavor`, `icon`, and:
  - `effects`: in-battle passives in the `PassiveRunner` format (as worn gear). A relic belongs to the party: it acts through the sister who caused the event, else the first living one. `"debuff_only": true` limits a `status_applied` trigger to debuffs.
  - `stats`: `energy` (per turn), `hand_size` (cards drawn each turn), `max_hp` (both sisters, `PartyMember.extra_max_hp`, kept by saves), `enemy_damage_pct`.
  - `effect`: the three original relics' fixed effects (`combat_start_block`, `first_turn_draw`, `heal_after_victory`).
- Sources: every won elite fight leaves a relic (`run_rules.json` `relics.elite_weights`); a boss offers 3 boss relics to choose from on the reward screen (`GameState.take_boss_relic`); chests roll a non-boss relic by rarity. Always through `RelicEffects.gain`, which also applies Max HP.
- In battle: the relic bar (top left of the battlefield) shows every relic with its name and effect on hover; a relic pops when it fires (`PassiveRunner.relic_triggered`).
- Tests: `tests/progression/run_relic_tests.gd`.

## Card keywords: Powers, Retain, X cost, Exhaust

Added with the card-pool expansion (9 new reward cards per playable specialization, 18-21 each now).

- **Powers last the whole combat.** A Power card's `"effect": "power"` carries a `power` block:
  - a passive in the PassiveRunner format (`trigger`, `effect`, `limit_per_turn`) that belongs to the
    card's owner until the battle ends (`PassiveRunner.add_power`, source `"power"`), and/or
  - `"stats": {"damage": N, "block": N}`: +N on every damage or Block effect of the owner's cards
    (`Combatant.power_damage` / `power_block`, like Strength and Dexterity; the damage preview includes it).
  - Every copy played adds up (two Pyromancy trigger twice). The owner shows a violet star chip per
    power with its count and text on hover (`CombatUnitView.set_statuses(..., powers)`).
  - Powers always exhaust. The older one-shot "power" cards (Leyline Weave, the epic hearts) still work.
- **Retain** (`"retain": true`, or in the upgrade block): the card stays in the hand at the end of the
  turn (`PartyDeck.discard_hand`). Tokens never stay.
- **X cost** (`"x_cost": true`): playable with any Energy; playing it spends all of it as X
  (`EffectContext.x_value`). Effects read X with `"per_x": N` (+N per point) or `"repeat_x": true`
  (resolve X times, + `"repeat_bonus"`). The cost orb shows "X".
- **Exhaust** may be changed by an upgrade (`"exhaust": false`); `CardInstance.exhausts()` decides.
- **New passive events:** `card_exhausted` {source, card}, `turn_end` {turn} (before the hand is
  discarded; an end-of-turn kill ends the fight) and `attacked` {source enemy, target} (any enemy
  attack that hits a sister; trigger key `recipient`). New passive effect: `damage_source` (thorns).
- **New card effects:** `power`, `multiply_block` (Entrench).
- Each specialization's pool has at least 2 real Powers, and Retain, X-cost and Exhaust cards
  (checked by `tests/cards/run_card_keyword_tests.gd`). The simulation bot values Powers by the enemy
  HP left in the fight and plays X cards with the Energy it has.
