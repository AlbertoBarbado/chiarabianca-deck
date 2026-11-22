# Voidfarer Chronicles — Agent Instructions

## 1. Project Overview

**Game Name:** Voidfarer Chronicles

**Genre:** Fantasy JRPG / Roguelike Deckbuilder

**Engine:** Godot 4.7

**Language:** GDScript

**Target Platforms:** PC and Mobile (Android/iOS)

**Primary Inspirations:** Slay the Spire, combined with JRPG party systems, character specialization trees and fantasy RPG progression.

Voidfarer Chronicles is a party-based roguelike deckbuilding game.

Players navigate branching maps, choosing their path through different locations such as combat encounters, resting areas, merchants, events and bosses.

The main difference from traditional deckbuilders is that players control a party of characters. Each character has their own identity, specialization, skill tree and card pool.

Characters develop in different directions depending on their chosen specialization and progression.

The game must be designed for both PC and mobile from the beginning.

---

## 2. Development Philosophy

Follow these principles throughout development:

1. Build modular, reusable and maintainable systems.
2. Prefer data-driven design over hardcoded game content.
3. Separate gameplay logic from visual presentation.
4. Keep systems independent whenever possible.
5. Prioritize working gameplay over visual polish.
6. Avoid unnecessary abstractions and overengineering.
7. Do not implement systems before they are needed.
8. Keep code readable and understandable.
9. Build reusable components for cards, characters, enemies and map nodes.
10. Always consider mobile compatibility when implementing UI or gameplay interactions.

Before implementing a new system:

- Inspect the existing architecture.
- Identify reusable components.
- Avoid duplicating existing functionality.
- Explain significant architectural decisions.
- Update relevant documentation.

Do not rewrite working systems unnecessarily.

---

## 3. Technical Architecture

Use Godot 4 and GDScript.

### Architecture requirements

- Use scenes for visual entities and interfaces.
- Use scripts for gameplay logic.
- Use Resources or structured data files for game definitions.
- Use Autoloads only for genuinely global systems.
- Avoid excessive global state.
- Separate runtime game state from static game definitions.
- Prefer signals for communication between independent systems.

### Data-driven content

Characters, specializations, cards, enemies, encounters, items and maps must be defined independently from their runtime logic.

For example:

- A character definition describes base stats and available specializations.
- A specialization definition describes its identity, skill tree and card pool.
- A card definition describes its cost, effects, target rules and other properties.
- An enemy definition describes its stats, behavior and available actions.

Adding a new character or card should not require rewriting the combat engine.

---

## 4. Project Folder Structure

Follow this folder structure when creating project files.

Do not create alternative root directories or reorganize the project without a clear architectural reason.

```text
VoidfarerChronicles/
│
├── AGENTS.md
├── project.godot
├── README.md
│
├── assets/
│   ├── characters/
│   │   ├── chiara/
│   │   └── bianca/
│   ├── enemies/
│   ├── environments/
│   ├── cards/
│   ├── ui/
│   ├── icons/
│   ├── effects/
│   ├── music/
│   └── sfx/
│
├── scenes/
│   ├── main/
│   ├── menus/
│   ├── map/
│   ├── combat/
│   ├── characters/
│   ├── events/
│   ├── shops/
│   ├── exploration/
│   └── castle/          (castle hub, world map, preparation, results, service shell)
│
├── scripts/
│   ├── autoload/
│   ├── core/
│   ├── map/
│   ├── combat/
│   ├── cards/
│   ├── characters/
│   ├── progression/
│   ├── inventory/
│   ├── events/
│   └── ui/              (ui/castle: castle screens and service panels)
│
├── data/
│   ├── characters/
│   ├── specializations/
│   ├── cards/
│   ├── enemies/
│   ├── encounters/
│   ├── maps/
│   ├── items/
│   ├── events/
│   ├── regions/         (world map regions)
│   ├── missions/        (expedition missions and objectives)
│   ├── castle/          (castle services)
│   ├── fusion/          (card fusion recipes)
│   ├── apothecary/      (potion brew recipes)
│   └── progression/     (run rules, campaign rules, Sister Bond)
│
├── resources/
│   ├── themes/
│   ├── fonts/
│   └── shaders/
│
├── tests/
│   ├── combat/
│   ├── cards/
│   ├── map/
│   ├── progression/
│   └── campaign/        (persistent campaign: logic suite and castle walkthrough)
│
└── docs/
    ├── GAME_DESIGN.md
    ├── COMBAT_SYSTEM.md
    ├── CHARACTER_SYSTEM.md
    ├── MAP_SYSTEM.md
    ├── PERSISTENT_RPG_DESIGN.md
    └── TODO.md
```

### Folder responsibilities

- `assets/`: Imported visual and audio assets. Never put gameplay scripts here.
- `scenes/`: Godot scenes (`.tscn`) and visual scene compositions.
- `scripts/`: GDScript implementation and gameplay logic.
- `data/`: Static game definitions, preferably Godot Resources or structured data files.
- `resources/`: Shared Godot resources, themes, fonts and shaders.
- `tests/`: Automated tests and gameplay validation.
- `docs/`: Game design documentation and technical documentation.

### Organization rules

1. Keep scenes and their corresponding scripts logically close in naming and responsibility, but inside their designated directories.
2. Never mix static game definitions with runtime game state.
3. Use `data/` for reusable definitions and `scripts/` for their behavior.
4. Use `autoload/` exclusively for systems that genuinely need global access.
5. Do not create empty folders unless they are needed.
6. Create new subfolders only when the amount of content justifies them.
7. Keep asset filenames descriptive and consistent.
8. Avoid duplicate implementations of existing systems.
9. Update this structure when an architectural change is approved.
10. The actual Godot project root is `VoidfarerChronicles/`; do not create another nested project directory.

---

## 5. Core Gameplay Systems

The game consists of several interconnected systems.

### 5.1 Party System

The player controls a party of characters.

Initial party:

- Chiara
- Bianca

Each character has:

- Name
- Portrait
- Base attributes
- Current health
- Maximum health
- Specialization
- Skill tree
- Personal card pool
- Status effects
- Equipment

The architecture must support adding additional party members in the future.

Characters must remain independent entities even when they participate in the same combat.

### 5.2 Character Specializations

Each character has multiple possible specializations.

At the beginning of an adventure, the player chooses one specialization for each starting character.

A specialization determines:

- Starting deck contribution
- Available cards
- Skill tree
- Combat identity
- Possible future upgrades
- Passive abilities

Characters should be able to develop further within their selected specialization.

Do not hardcode specialization-specific behavior into the combat engine.

### 5.3 Initial Character Definitions

**Chiara — Mage**

Available specializations:

1. Arcana
2. Fire
3. Frost
4. Earth
5. Wind
6. Lightning

Each specialization should have its own:

- Starting deck
- Card pool
- Skill tree
- Passive identity

**Bianca — Paladin**

Available specializations:

1. Retribution
2. Tanking
3. Holy
4. Venom (plague knight: Poison, Catalysts and Blight; replaced Vanguard)
5. Ashveil (rogue-ish knight: oil, powder, smoke and traps; replaced Duelist)
6. Commander

Each specialization should have its own:

- Starting deck
- Card pool
- Skill tree
- Passive identity

The initial game should only implement a limited selection of these specializations. The architecture must support all of them without structural changes.

### 5.4 Party Deck System

This is one of the defining mechanics of Voidfarer Chronicles.

Each character owns their individual cards, but the party uses a single combined deck during combat.

Example:

- Chiara contributes 10 cards.
- Bianca contributes 10 cards.
- The resulting party deck contains 20 cards.
- The 20 cards are shuffled together.
- Players draw from this shared deck during combat.

Every card must retain its original character ownership.

When a card is drawn, the player must be able to identify which character owns it.

Cards can only be played if their owner is alive and any other applicable requirements are satisfied.

### Deck organization

The combat deck must support:

- Draw pile
- Hand
- Discard pile
- Exhaust pile

Cards move between these piles according to their effects and rules.

At the appropriate point, the discard pile is shuffled back into the draw pile.

The system must preserve card ownership, upgrade levels and other card-specific properties during all pile transitions.

### Character deck ownership

Characters own their individual cards outside combat.

The party deck is assembled from all active party members when combat starts.

This means:

- Adding a character adds their cards to the party deck.
- Removing a character removes their cards from future party decks.
- Character-specific card upgrades remain attached to the individual card.
- The combat deck must not overwrite the original character deck definitions.

### Card interactions

The system should eventually support:

- Cards that interact with their owner's abilities.
- Cards that interact with another party member.
- Combo cards between characters.
- Specialization-specific synergies.
- Cards that trigger effects when another character plays a card.

Do not implement all these interactions immediately. The architecture must simply allow them to be introduced later.

### 5.5 Card System

Cards are the primary combat mechanic.

Every card should support relevant properties such as:

- Unique ID
- Name
- Description
- Image reference
- Cost
- Card type
- Character ownership
- Specialization requirements
- Target type
- Effects
- Upgrade level

Possible card types:

- Attack
- Skill
- Spell
- Defense
- Support
- Power

The system must support:

- Drawing cards
- Playing cards
- Discarding cards
- Exhausting cards
- Energy or resource costs
- Multiple targets
- Card effects
- Card upgrades

Do not implement individual card effects directly in the combat controller.

Create reusable effect implementations that cards can reference.

### 5.6 Combat System

Combat is turn-based.

The player controls their entire party against one or more enemies.

Combat must support:

- Multiple player characters
- Multiple enemies
- Individual character health
- Cards from different characters
- Shared party draw pile
- Individual card ownership
- Enemy intent previews
- Status effects
- Buffs and debuffs
- Damage and healing
- Victory and defeat conditions

Keep combat calculations independent from the combat UI.

### 5.7 Map System

The adventure map is a branching node-based structure inspired by Slay the Spire.

Players choose between available connected nodes.

Initial node types:

- Starting location
- Combat
- Rest
- Merchant
- Event
- Exit

Future node types:

- Elite combat
- Treasure
- Boss
- Special encounters

Map requirements:

- Multiple possible paths
- Connections between nodes
- Visually distinguishable node types
- Player progression tracking
- Visited and unavailable node states
- Support for different map sizes and layouts

The map generator must be independent from the map visualization.

### 5.8 Rest System

Resting locations allow the player to recover party members.

Initially, resting restores a configurable amount of health.

Future possibilities include:

- Card upgrades
- Character-specific interactions
- Special resting events

### 5.9 Merchant System

Merchants provide access to purchasable items.

Initial merchant inventory:

- Health potions
- Other basic consumables

Future possibilities:

- Cards
- Card removal
- Equipment
- Special items
- Character upgrades

The merchant system must be reusable across different maps.

### 5.10 Progression and Inventory

The player should have an inventory for:

- Potions
- Consumables
- Equipment
- Other collectible items

The architecture should support future card rewards, character progression and persistent unlocks.

---

## 6. First Playable Content: The Royal Castle

The first playable map is the sisters' castle.

Chiara and Bianca are twin princesses.

The castle acts as a tutorial adventure where the player learns the fundamental gameplay systems.

### Objectives

- Introduce the characters.
- Introduce the map navigation system.
- Teach the player how to choose paths.
- Introduce combat.
- Introduce resting.
- Introduce merchants.
- Introduce the party deck system.
- Reach the castle exit.

### Map requirements

The castle should contain:

- Starting room
- Several branching paths
- Resting locations
- Merchant locations
- Normal combat encounters
- One final combat encounter
- Exit location

There is no boss in the initial tutorial map.

The final encounter is a stronger regular combat encounter.

Tutorial instructions should be integrated naturally into gameplay.

Do not overwhelm the player with multiple systems at once.

---

## 7. User Interface and Platform Support

The game must support both PC and mobile.

### UI principles

- Responsive layouts.
- Touch-friendly controls.
- Readable typography.
- Scalable card interfaces.
- Consistent visual hierarchy.
- Reusable UI components.

### PC

Support:

- Mouse interaction
- Keyboard navigation where appropriate
- Tooltips on hover
- Drag-and-drop where appropriate

### Mobile

Support:

- Touch interaction
- Tap-based card selection
- Swipe gestures where appropriate
- Large interaction targets
- Interfaces that adapt to smaller screens

Never design an interface that only works with a mouse.

Avoid fixed pixel positioning where responsive containers and anchors are more appropriate.

Gameplay must remain understandable on both platforms.

---

## 8. Art and Asset Management

Art assets will be generated externally using AI image-generation tools.

Do not generate placeholder artwork through code unless explicitly requested.

Use temporary placeholders when assets are unavailable.

Keep asset references centralized and organized.

Suggested asset categories:

- Characters
- Enemies
- Environments
- Cards
- Icons
- UI
- Visual effects
- Music
- Sound effects

Do not assume that an asset exists.

Always verify file paths before referencing assets.

Keep gameplay functional even when final artwork is missing.

---

## 9. Saving and Game State

The game must eventually support saving and loading.

Persist relevant information such as:

- Current adventure
- Party composition
- Character specializations
- Character health
- Individual character decks
- Card upgrade levels
- Inventory
- Progression
- Current map position

Separate save data from visual scenes.

Design save data so that it can evolve as the game develops.

---

## 10. Coding Conventions

Follow these conventions:

- Use clear and descriptive names.
- Use snake_case for variables and functions.
- Use PascalCase for classes and custom Resource types.
- Avoid excessively long functions.
- Avoid unnecessary nested conditionals.
- Add comments when explaining complex gameplay logic.
- Use typed GDScript wherever practical.
- Avoid magic numbers; use constants or configurable data.
- Handle invalid references and missing resources safely.

Do not create giant scripts that handle multiple unrelated systems.

Prefer small, focused scripts with clear responsibilities.

---

## 11. Development Workflow

Development must happen incrementally.

For every task:

1. Understand the requested functionality.
2. Inspect relevant existing files.
3. Propose the implementation approach when architectural changes are involved.
4. Implement the smallest complete solution.
5. Test the affected functionality.
6. Fix errors before moving forward.
7. Update documentation when necessary.

Do not implement multiple unrelated systems in a single step.

Do not leave broken references, unused placeholder scripts or unfinished integrations without documenting them.

When a feature is incomplete, clearly explain what remains.

---

## 12. Current Development Priorities

Follow this development order.

### Phase 1 — Foundation

- Create the Godot project.
- Establish folder structure.
- Configure project settings.
- Implement the main game entry point.
- Create basic navigation between screens.
- Establish responsive UI foundations.

### Phase 2 — Characters

- Implement character data definitions.
- Create Chiara.
- Create Bianca.
- Implement specialization selection.
- Implement starting decks.
- Implement individual character deck ownership.

### Phase 3 — Cards and Combat

- Implement card definitions.
- Implement combined party deck creation.
- Implement deck shuffling.
- Implement draw, hand, discard and exhaust piles.
- Implement turn management.
- Implement basic card effects.
- Implement party combat.
- Implement enemy behavior.
- Implement victory and defeat.

### Phase 4 — Map

- Implement node-based maps.
- Implement node connections.
- Implement path selection.
- Implement map progression.
- Implement room transitions.

### Phase 5 — Exploration Systems

- Implement resting rooms.
- Implement merchants.
- Implement potion inventory.
- Implement combat encounters.

### Phase 6 — Tutorial Map

- Create the Royal Castle map.
- Configure its rooms.
- Implement tutorial progression.
- Add the final combat encounter.
- Implement the exit and tutorial completion.

### Phase 7 — Polish

- Integrate final art.
- Add animations.
- Add audio.
- Improve UI.
- Test mobile and PC builds.
- Implement saving and loading.

---

## 13. Important Restrictions

- Do not implement multiplayer.
- Do not introduce unnecessary procedural generation complexity.
- Do not create an open-world system.
- Do not implement features unrelated to the current development phase.
- Do not hardcode character-specific logic into generic systems.
- Do not couple gameplay calculations to UI scenes.
- Do not sacrifice mobile compatibility for PC convenience.
- Do not assume future features are required in the current playable prototype.

When in doubt, prioritize a small, functional and extensible implementation.

---

## 14. Documentation Strategy

Keep AGENTS.md as the primary source of development instructions.

Detailed game and technical specifications should gradually be documented in the `docs/` directory.

Suggested documentation responsibilities:

- `GAME_DESIGN.md`: Overall game concept, gameplay loop, story and design decisions.
- `COMBAT_SYSTEM.md`: Combat rules, card resolution, turn order, energy and status effects.
- `CHARACTER_SYSTEM.md`: Character definitions, specializations, skill trees and progression.
- `MAP_SYSTEM.md`: Map generation, node types, connections and navigation.
- `TODO.md`: Current development tasks, completed milestones and known issues.

Update documentation whenever an important design or architectural decision is made.

Do not duplicate entire technical specifications across multiple documents.

---

## 15. Definition of Done

A feature is complete only when:

- Its functionality is implemented.
- It integrates with the existing architecture.
- It has no known runtime errors.
- Its basic behavior has been tested.
- It works with the intended input methods.
- Documentation is updated when relevant.

The ultimate objective is to build a polished, expandable party-based roguelike deckbuilder.

**Build the foundation correctly. Expand the game incrementally. Prioritize playable systems over speculative complexity.**

## 16. Commercial Asset Licensing and Intellectual Property

Voidfarer Chronicles is a commercial project intended for monetization and distribution.

All assets, dependencies and third-party resources used in the project must be legally usable in a commercial game.

### 16.1 General Licensing Requirements

1. Only use assets explicitly permitted for commercial use.
2. Never use assets marked as personal use only, educational use only or non-commercial.
3. Never assume an asset is commercially usable simply because it is publicly accessible or free to download.
4. Verify the license of every third-party asset before integrating it.
5. Respect attribution requirements, redistribution restrictions and other license conditions.
6. Do not use copyrighted assets from existing games, films, anime, books or other commercial franchises without appropriate authorization.
7. Do not use pirated, leaked, ripped or unauthorized assets.
8. When license terms are unclear, do not use the asset until its commercial usage rights have been verified.

### 16.2 Asset Categories

These rules apply to:

- Character illustrations and portraits.
- Enemy illustrations.
- Backgrounds and environments.
- Card artwork.
- UI elements and icons.
- Fonts and typography.
- Music and sound effects.
- Animations and visual effects.
- Shaders and materials.
- Plugins and code libraries.
- External tools and frameworks.

### 16.3 Preferred Asset Sources

When searching for free commercial-use assets, prioritize resources with clear licensing, such as:

- Kenney.nl — Game assets with permissive licensing.
- OpenGameArt.org — Only assets with verified commercial-compatible licenses.
- itch.io — Only assets whose individual licenses explicitly permit commercial use.
- Freesound.org — Only recordings with licenses permitting commercial use.
- Google Fonts — Fonts under licenses permitting commercial use.
- Poly Haven — Assets released under CC0.

These are discovery sources, not blanket guarantees. Verify the license of each individual asset.

### 16.4 AI-Generated Assets

Artwork and audio may be generated using external AI tools.

Before using generated content commercially:

1. Verify the generation platform's current commercial usage terms.
2. Verify that the account or subscription tier permits the intended use.
3. Avoid prompts requesting direct reproductions of copyrighted characters, existing artwork or recognizable commercial intellectual property.
4. Do not intentionally reproduce the distinctive style of living artists.
5. Keep records of generation sources and relevant usage terms where possible.

AI-generated assets must still be reviewed for potential intellectual property conflicts.

### 16.5 License Documentation

Create and maintain:

`docs/ASSET_LICENSES.md`

For every third-party asset, document:

- Asset name.
- Asset category.
- Original source URL.
- Creator or publisher.
- License name.
- License URL.
- Attribution requirements.
- Date obtained.
- Commercial usage permission.
- Any additional restrictions.

Keep relevant license files and attribution notices in the project when required.

### 16.6 Dependencies and Plugins

All external plugins, libraries and code dependencies must have licenses compatible with commercial distribution.

Before introducing a dependency:

- Check its license.
- Check its redistribution requirements.
- Check whether it introduces additional dependencies.
- Avoid dependencies with incompatible licensing restrictions.

Pay particular attention to copyleft licenses and their implications for distributing a proprietary commercial game.

Do not introduce a dependency with unclear licensing.

### 16.7 Prohibited Actions

Never:

- Download and integrate an asset without checking its license.
- Assume free assets are automatically free for commercial use.
- Remove copyright notices or attribution requirements.
- Use non-commercial Creative Commons assets.
- Use assets with licensing restrictions incompatible with the game's monetization model.
- Copy assets directly from other games or commercial products.
- Use unlicensed AI-generated reproductions of existing intellectual property.

### 16.8 Final Commercial Release

Before preparing a release:

1. Review every third-party asset.
2. Review all fonts, plugins and dependencies.
3. Verify that all commercial permissions remain valid.
4. Check required attribution notices.
5. Ensure license documentation is complete.
6. Remove any asset with unresolved licensing status.

**Default rule: If commercial usage permission cannot be verified, the asset must not be included in Voidfarer Chronicles.**

## Game Art Generation Rules

- Maintain a consistent art direction across all assets.
- Create transparent PNGs for individual sprites.
- Generate sprite sheets with consistent frame dimensions.
- Keep characters visually consistent across animations.
- Generate tilesets aligned to the game's tile grid.
- Never overwrite approved assets without confirmation.
- Save assets in organized folders:
  /assets/characters
  /assets/enemies
  /assets/tilesets
  /assets/environment
  /assets/ui
  /assets/vfx
- Always preview generated assets before integration.
- Optimize assets for the target game engine.