# Voidfarer Chronicles

Party-based fantasy JRPG roguelike deckbuilder (Godot 4.7, GDScript). This is the first playable prototype: the Royal Castle tutorial with Chiara (Mage, Arcana) and Bianca (Paladin, Tanking).

## Run
Open the folder in Godot 4.7 and press F5, or:
```
Godot_v4.7.2-stable_win64.exe --path .
```
First launch needs one import pass (`--headless --import`) so `class_name` scripts are registered.

## Tests
```
godot --headless --path . --script res://tests/run_tests.gd        # logic tests (65 checks)
godot --path . res://tests/ui_smoke_test.tscn -- <screenshot_dir>   # full UI walkthrough + screenshots
```

## Layout
See `AGENTS.md` section 4. Docs live in `docs/` (`TODO.md` lists remaining work).
`assets_pack/` is the original supplied input pack, kept untouched for reference; the integrated copies live in `data/` and `assets/concept/`.
