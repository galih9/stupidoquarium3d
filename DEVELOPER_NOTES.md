# Developer Notes - FIH-2 Aquarium

## Strict Content Rule (Important for Future Developers)
**NEVER put any emojis anywhere in the game.**
This applies strictly to all UI labels, in-game text, shaders, GDScript code comments, debug logs, commit messages, and documentation. Keep all text clean, minimal, and strictly ASCII/plain text.
**NEVER use white circle / ring torus indicators anywhere in the game.** Always use `shaders/selection_outline.gdshader` for selection feedback.

## Game Modes
- `Engine` meta `game_mode` selects the mode before `main.tscn` loads: `"endless"` (default) or `"tutorial"`. Set by the Main Menu, kept on Restart.
- Endless: waves of Peaceful -> Careful -> Attack. Game over when no fish are alive and the player cannot afford a new one.
- Tutorial: `scripts/tutorial_director.gd` runs 11 fixed steps, locks shop items until they are taught, freezes the wave timer, and spawns one harmless training Kingfisher (`training_mode`). The last step offers Play Endless.

## Difficulty
- All difficulty and economy numbers live in `scripts/game_balance.gd` (starting coins, hunger timers, phase durations, bird count/HP/speed/aggression per wave, click damage). Tune there; the Encyclopedia reads the same values.
- Camera shake is never triggered by manual bird clicks, archer hits, or predator pecks. Only kills and snatches use a small shake (and the Screen Shake setting can turn it off).

## Architecture Overview
- `menu.tscn` / `scripts/main_menu.gd`: Minimal 2D Main Menu: Play Endless, Tutorial, Encyclopedia, Settings, Quit.
- `scripts/ui_style.gd`: Shared colors, panels, buttons, progress bars and labels used by every screen. Use it for any new UI so the look stays consistent.
- `scripts/encyclopedia_panel.gd`: Encyclopedia panel (menu and pause menu) with a rotating 3D preview per creature/plant and live stats pulled from the gameplay scripts.
- `scripts/tutorial_director.gd`: Tutorial step machine and its side panel. Listens to the `tutorial_event` signal emitted by `aquarium_main.gd`.
- `scripts/game_balance.gd`: Central difficulty and economy tuning.
- `loading.tscn` / `scripts/loading_screen.gd`: Minimalistic asynchronous threaded Loading Screen with slim progress bar and gameplay tips.
- `pause_menu.tscn` / `scripts/pause_menu.gd`: In-game Pause Menu overlay (`PROCESS_MODE_ALWAYS`, opened with `P`, `ESC`, or the HUD Pause button) with a session summary, Resume, Restart, Encyclopedia, Controls, Screen Shake toggle, Main Menu, and Quit.
- `main.tscn` / `scripts/aquarium_main.gd`: Root 3D game controller and HUD (top-left stats, top-center wave bar, bottom shop bar with hotkeys 1-6, bottom-right selection inspector, decorate bar, game over card). Manages player coins, movable & upgradable surface food producers (Duckweed -> Water Hyacinth), default Pet Crab coin collector, Peaceful-phase tank bottom decorating, Archer Fish defenders, and wave-based threat phases (`Peaceful`, `Careful`, `Attack`).
- `shaders/selection_outline.gdshader`: Spatial inverted-hull selection outline shader applied to any selected 3D entity (Goldfish, Archer Fish, Pet Crab, Duckweed/Hyacinth tile, or Tank Decoration).
- `scripts/combat_vfx.gd`: Reusable 3D VFX & selection outline helper providing `set_selection_outline`, unshaded hit-flash material overlays (preserving selection outlines), 3D impact sparks/droplets, water surface splashes, floating 3D popups, and camera shake triggers.
- `scripts/duckweed_tile.gd`: Movable and 4-stage upgradable surface food producer:
  - Tier 0 (`duckweed_tile_sparse.glb`): Duckweed Lv.1 (Sparse), feeds 1 fish at a time.
  - Tier 1 (`duckweed_tile.glb`): Duckweed Lv.2 (Normal), feeds 2 fish simultaneously.
  - Tier 2 (`water_hyacinth_tile_sparse.glb`): Water Hyacinth Lv.1 (Sparse), feeds 4 fish simultaneously and spawns 1 Baby Goldfish every 3 minutes (180s) when the tank has at least 2 alive Adult Goldfish.
  - Tier 3 (`water_hyacinth_tile.glb`): Water Hyacinth Lv.2 (Normal), feeds 8 fish simultaneously and spawns 1 Baby Goldfish every 1 minute (60s) when the tank has at least 2 alive Adult Goldfish.
- `scripts/pet_crab.gd`: Default Pet Crab (`assets/fih/crab.glb`) that patrols the bottom of the tank, chases and collects falling/floor coins, and supports movement speed upgrades (`Lv.1` to `Lv.6`).
- `scripts/tank_decoration.gd`: Movable 3D tank floor decorations (`coral_*`, `rock_*`, `seaweed_*` with `decor_sway.gd` animation) that can be placed, selected, rotated, and moved across the bottom of the tank during the `Peaceful` phase.
- `scripts/swimming_fish.gd`: Extends `assets/fih/goldfish.gd` with autonomous `SWIM`, `IDLE`, `SEEK_FOOD`, `EATING`, and `DYING` states, `HungerStatus`, `StressStatus`, growth across meals (`BABY` -> `MEDIUM` -> `ADULT`), timed coin drops, and selection outline support.
- `scripts/coin_drop.gd`: Collectible 3D coins (`copper.gltf`, `silver.gltf`, `gold.gltf`) dropped by fish on a timer. Collected by the Pet Crab on the tank bottom or clicked by the player.
- `scripts/archer_fish.gd`: Pet Archer Fish (`assets/fih/archerfish.glb`). Swims around the tank and fires multi-layered 3D water jet bolts with ribbon trails at active threats.
- `scripts/kingfisher_threat.gd`: Wave threat predator (`assets/fih/kingfisher.glb`) with 3D wingtip/slipstream ribbon trails. Observes during `Careful` phase and dives at the closest goldfish during `Attack` phase.
- `scripts/aquarium_camera.gd`: 360-degree orbital camera rig with zoom, outline-shader entity selection, surface dragging for Duckweed/Hyacinth tiles, floor dragging for Decorations during the `Peaceful` phase, and smooth target tracking.
- `shaders/toon_water.gdshader` & `shaders/toon_water_material.tres`: Godot 4.4+ toon water shader.
