# Potions — session handoff

Written at the end of the session that produced
[`potions-design.md`](potions-design.md) and built step 1 of its §11. **That doc
is the spec; this one is only how to pick the work back up.** Everything about
*what* potions are and *why* lives there — nothing in here restates it, so if the
two ever disagree, the plan is right and this file is stale.

---

## 1. Where things are

- **Branch:** `claude/potions-loot-design-hlpttv`, 8 commits, pushed, tree clean.
  No PR — none was asked for.
- **Suite:** green. `1549 tests, 0 failing, 0 risky, 3 orphans` (the orphans and
  the leaked-RID warnings at the end of a run are pre-existing UI-test noise).
- **The workbook has one real edit in it** — Potion of Uselessness moved Common →
  Uncommon (`tools/_potions2_uselessness_uncommon.py`). Everything else about
  potions is still design.

A fresh remote session clones the repo at the default branch, so start with:

```bash
git fetch origin claude/potions-loot-design-hlpttv
git checkout claude/potions-loot-design-hlpttv
```

Then read `docs/potions-design.md` §1 (the 29 locked decisions) and §11 (the build
order). §9.1 is the reuse map — the list of things that already exist and should
not be rebuilt.

## 2. What is already built (§11 step 1)

The **timed status layer**: stacks that expire on their own, which is the one
genuinely new system the feature needed. Design in §5 of the plan, narrative in the
CHANGELOG entry opening *"Statuses can be borrowed"*, tests in
`test/test_timed_statuses.gd` (26).

What a caller touches:

```gdscript
GameState.apply_status(&"dexterity", 5, 1)              # 5 stacks, for one game
GameLoop2.apply_enemy_status(&"strength", 3, "current", 1)
GameLoop2.apply_status_to(instance, &"burn", 2, 1)
```

`games` defaults to 0 (permanent), so every pre-existing call means what it always
meant. Reads (`status_stacks`, `status_list`, `combat_totals`, `enemy_statuses`,
`enemy_combat`, `goal_text_for`) already return the merged view and already say
"this game only" where it applies — **do not add a second path for timed stacks
when the potion ops land; just pass `games`.**

**Nothing applies one yet.** That is deliberate: the layer was built and tested
ahead of the content so a potion bug and a clock bug can never be the same bug.

## 3. What is next

**§11 step 2 — the scroll deltas.** All of it is specified in §10 and §10.1 of the
plan; the order that works is:

1. `tools/generate_scroll2_tres.py` writes `rarity` from the sheet's column, and
   carries `Description` onto a new `ScrollData.description`. Regenerate
   `data/scrolls2.0/`. **This is the fix with the most reach in the whole step:**
   `Data.roll_scroll` has been rarity-weighting off a field the generator never
   wrote, so every scroll in the game is currently Common.
2. `forget` goes kind-blind (Amnesia forgets any identified loot).
3. `identify_scrolls` → `identify_loot`, offering scrolls, pills and potions; keep
   the old verb parsing as an alias.
4. `find_weight` (Identify's "+25% find rate") as a weight *inside* the rolled
   rarity bucket.
5. `remove_curse choose|random|all N` + `GameState.remove_curse_goal(index)` + a
   picker in `LootUseModal`. Read §10.1 first — curse GOALS are live content and
   are not the shelved curse CARDS, and `remove_active_curse` is the wrong
   function.

Steps 3–8 then run as §11 lists them. Step 3 (the `PotionData` resource, the
generator, the sheet cells) is the one with a **decision in it** — see §5 below.

## 4. Working notes that cost time this session

- **The GUT filter flag.** `-gtest=res://test/foo.gd` does **not** filter; it runs
  all 32 scripts (~400s). What works:
  ```bash
  godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gprefix=test_timed -gexit
  ```
  Iterate with that (sub-second), then run the whole suite before committing.
- **A full run is ~6.5 minutes** and buffers its output until it exits, so a
  backgrounded run shows an empty log the whole time it is working. Redirect to a
  file and wait for it rather than assuming it has died.
- **`--check-only --script` on an autoload is not a syntax check.** It reports
  `Identifier not found: GameState` / `TriggerBus` / `Data` for any file that
  references another autoload, on clean files too. It is only useful for the
  `class_name`-shadows-a-native-class check CLAUDE.md describes.
- **Never openpyxl-save the workbook** — it silently drops the seven charts on
  `Map Analysis`. Use `tools/_xlsx_surgery.py` and keep the edit as a one-shot
  beside the others; `_potions2_uselessness_uncommon.py` is the template. Verify
  afterwards that only that sheet's two XML parts changed.
- **A new `class_name` needs `godot --headless --editor --quit` once** before the
  suite can see it. `PotionData` will hit this.

## 5. Two things to settle at the top of the next session

- **Who authors the 30 sheet cells?** `potions2.0`'s `On Player Effect` and
  `On Tile Effect` are both empty for all 15 rows. §7.3 of the plan proposes every
  cell. Either the owner pastes them in, or the next session writes them through
  `_xlsx_surgery` the way the Uselessness edit went. Ask — the sheet is upstream of
  `data/`, and two people editing it in one day is how a regeneration silently
  reverts someone.
- **The four open questions in §12** are all recommendations already written down,
  not blockers: throwing mid-report, Fysh Oil under Sacred Bark, whether Bark's
  area-doubling leaves a `cell` alone, and Lucky Foot's reach. They are better
  answered by playing the thing than by asking again — the `verify` skill
  (`.claude/skills/verify/`) is how to get it on screen.

## 6. One correction worth carrying forward

The design said to cap a status's stacks on read. That is wrong and the suite
caught it: the authored ceiling (Burn's `Max: 3`) is a rule about the way **up**,
and stacks already over it — from a save written before the cap, or a cap the sheet
lowered — must tick down one at a time rather than being frozen. The cap now
applies only to what the timed layer *adds*, floored at the permanent count.

Expect more of these. The plan is careful but it is still a plan; where it and a
green test disagree, the test is describing the build.
