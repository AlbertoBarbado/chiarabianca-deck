# Voidfarer Chronicles — Initial Asset Pack

This pack contains:
- Two generated concept-art boards for visual direction.
- Character JSON templates for Chiara and Bianca.
- All twelve specialization definition templates.
- A reusable card-definition schema and eight prototype starter cards.
- A handcrafted Royal Castle tutorial node graph.

## Important visual note
The PNGs are concept boards/collages, not production-ready individual sprites or transparent UI components. Do not slice them automatically and assume the resulting pieces are clean game assets. Use them as visual references for generating/exporting individual assets.

## Initial character canon
- Chiara: auburn-blonde hair, light grey eyes, mage.
- Bianca: black hair, brown eyes, paladin.
- They are twin princesses.

## Party deck rule
Characters own their individual card collections. At combat start, instantiate runtime card instances from all active party members' owned cards, combine them into one party draw pile, and shuffle it. Runtime instances must preserve owner_character_id, upgrades and temporary modifiers. Never mutate the static card definitions or the out-of-combat character deck when shuffling.

Combat piles:
- draw_pile
- hand
- discard_pile
- exhaust_pile

When the draw pile is empty, shuffle the discard pile into a new draw pile if the rules permit.

## Prototype caveats
- Starting card values are illustrative balance placeholders.
- Chiara Arcana and Bianca Tanking are example starting specializations only; the player-facing game should let the player choose a specialization.
- The map is a fixed tutorial graph, not a procedural map generator.
- Encounter, shop and event IDs are references that still need corresponding definitions.
- No boss is present in the tutorial map.

## Godot integration
The JSON files are engine-agnostic data templates. Claude Code should either load them with JSON.parse_string() or convert them into typed Godot Resource definitions. Choose one consistent approach and document it before scaling content.

Suggested destinations when integrating into the Godot project:
- `data/characters/`
- `data/specializations/`
- `data/cards/`
- `data/maps/`
- `assets/concept/` for the two PNG reference boards

## Licensing
The concept boards were generated with ChatGPT image generation. Before commercial release, verify the applicable OpenAI terms for the account and generation date. Record the result in `docs/ASSET_LICENSES.md`. All future third-party assets, fonts, plugins, music and sound effects must have verified commercial-use permissions.
