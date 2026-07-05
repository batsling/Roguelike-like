---
name: verify
description: Run this Godot project's real combat scenes headless-with-display and capture screenshots to verify gameplay changes at runtime.
---

# Verifying gameplay changes in this repo

Godot binary: `/root/.local/godot/godot` (4.x). GUT unit tests are CI's job —
verification means running the real scenes and observing.

## Recipe

1. Write a temporary driver scene (never commit it):
   - `test/_verify_driver.gd` — `extends Node`; in `_ready()` instantiate the
     real combat scene, drive it through the same methods the UI calls, print
     `VERIFY PASS/FAIL` lines, `get_tree().quit(fails)`.
   - `test/_verify_driver.tscn` — a one-node scene with that script attached
     (autoloads only run when launching a scene, NOT with `--script`).
2. Run it under Xvfb so real frames render and screenshots work:

   ```bash
   xvfb-run -a /root/.local/godot/godot --path . --rendering-driver opengl3 \
       --resolution 1280x720 res://test/_verify_driver.tscn
   ```

3. Screenshot: `await RenderingServer.frame_post_draw` then
   `get_viewport().get_texture().get_image().save_png(abs_path)`.

## Scene boot cheatsheet

- **Deckbuilder**: instantiate `res://scenes/deckbuilder/DeckbuilderCombat.tscn`,
  set `dev_combat = true` and `enemies_to_spawn = [&"jaw_worm", ...]`
  (ids from `data/enemies/`) BEFORE `add_child` — `_ready` auto-starts combat.
  Play cards via `_resolve_card(inst, target_or_null)`. `hand` is a typed
  array — `hand.clear()` + `append`, never assign a plain `Array`.
- **Action**: instantiate `res://scenes/action/ActionCombat.tscn` with
  `target_game_id = &""` and `enemies_to_spawn` (ids from
  `data/action_enemies/`). Spawns are telegraphed — materialise
  `_pending_spawns` by hand or wait `SPAWN_TELEGRAPH_TIME`. Cast via
  `_resolve_card_effects(card_data)`; move `enemies[i].pos` near
  `player_pos` for melee reach.
- **Strategy**: `load(".../BattleView.gd").new()` + `add_child` builds its UI;
  wire units like `test/test_strategy_deckbuilder.gd` does.
- First run each character with `GameState.reset_run()` +
  `GameState.apply_character(Data.get_character(&"ironclad"))`.

## Gotchas

- Top up enemy HP before counting multi-hit damage — clamped overkill hides hits.
- Audio errors (ALSA/pulse) are noise; the dummy driver kicks in.
