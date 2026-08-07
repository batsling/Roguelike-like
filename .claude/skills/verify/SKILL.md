---
name: verify
description: Run this Godot project's real scenes headless-with-display and capture screenshots to verify gameplay changes at runtime.
---

# Verifying gameplay changes in this repo

Godot binary: `/root/.local/godot/godot` (4.6), also on `PATH`. GUT unit tests
are CI's job — verification means running the real scenes and observing.

## Recipe

1. Write a temporary driver scene (**never commit it**):
   - `test/_verify_driver.gd` — `extends Node`; in `_ready()` instantiate the real
     scene, drive it through the same public methods the UI calls, print
     `VERIFY PASS/FAIL` lines, `get_tree().quit(fails)`.
   - `test/_verify_driver.tscn` — a one-node scene with that script attached
     (autoloads only run when launching a scene, NOT with `--script`).
2. Run it under Xvfb so real frames render and screenshots work:

   ```bash
   xvfb-run -a godot --path . --rendering-driver opengl3 \
       --resolution 1280x720 res://test/_verify_driver.tscn
   ```

3. Screenshot: `await RenderingServer.frame_post_draw` then
   `get_viewport().get_texture().get_image().save_png(abs_path)`.
4. Delete `test/_verify_driver.gd`, `.tscn` and any `.uid` before committing.

## Scene boot cheatsheet

There are only two scenes, and the simulated combat modes are gone (the real
video game you go and play is the combat). Mirror what the GUT suites do.

- **The overworld — the game.** Instantiate
  `res://scenes/redesign2/Overworld2.tscn` and `add_child` it; `_ready` builds the
  UI and rolls the choose-your-start panel. `choose_start(0)` takes a start and
  gives the run a position — nothing else works until you do. Then drive it with
  the same methods its cards call: `pick(i)` travels, `report(goal_met)` resolves,
  and `bash_choice(i)` / `transmute_choice(i)` / `dash()` / `scramble()` are the
  board verbs. To boot on a specific character: `start_run(&"ironclad")` then
  `choose_start(0)`. See `test/test_overworld2.gd`.
- **Screens built in code** (no scene file) — construct and `add_child` directly:
  `Collection.new()`, `RewardScreen`, `TierListScreen`, `RunOverScreen`,
  `AtlasView`, `EventModal`. Set `set_anchors_preset(Control.PRESET_FULL_RECT)` if
  you want it to fill the viewport for a screenshot.
- **`PlaySession2.tscn`** is the text-only precursor of the overworld, kept as a
  headless harness for the loop.
- Reset between runs with `GameState.reset_run()` + `GameLoop2.reset()`. Apply a
  character with `GameState.apply_character2(Data.get_character2(&"ironclad"))` —
  note the `2`; the roster is the 2.0 set.

## Gotchas

- Give the UI ~30 `await get_tree().process_frame` before screenshotting or
  measuring layout; several screens size themselves over multiple frames.
- Game covers load lazily (`GameData.cover_path` → `cover_image` on first read),
  so a cover is only decoded once something asks for it. Reading `cover_image` in
  a driver is what makes it appear.
- Audio errors (ALSA/pulse) are noise; the dummy driver kicks in.
- Leaked-RID and orphan warnings at exit are pre-existing noise from Control-heavy
  screens, not something your change caused.
