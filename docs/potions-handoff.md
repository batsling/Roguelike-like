# Potions — session handoff

**Steps 1–4 of [`potions-design.md`](potions-design.md) §11 are built. Step 5 —
the THROW — is what is left, and it is where the new gameplay actually is.**

That doc is the spec; this one is only how to pick the work back up. Everything
about *what* potions are and *why* lives there — nothing in here restates it, so
if the two ever disagree, the plan is right and this file is stale.

---

## 1. Where things are

- **Steps 1–4 are on `claude/potions-handoff-docs-9mjklk`**, branched off
  `16ea81d` (which is where PR #204 merged step 1 into `main`). Pushed. No PR —
  none was asked for. If the branch has landed on `main` by the time you read
  this, a fresh clone has all of it and there is nothing to check out.
- **Suite:** green. `Scripts 33, Tests 1618, Passing 1618, Orphans 3` in ~385s.
  The 3 orphans and the leaked-RID warnings at the end of a run are pre-existing
  UI-test noise; a **Risky / "Did not assert" is not** (see CLAUDE.md). The ASSERT
  count moves between runs because several tests walk a random graph — the test
  count is the stable number.
- **Read before touching anything:** `docs/potions-design.md` §1 (the 30 locked
  decisions), §9.1 (the reuse map — what already exists and must not be rebuilt),
  and §11 (the build order).

## 2. What is built

| Step | What landed | Where |
|---|---|---|
| 1 | The **timed status layer** — stacks that expire on their own | `GameState.timed_statuses`, `GameLoop2._expire_timed_statuses`, `StatusData.clock_note` |
| 2 | The **scroll deltas** — rarity, `description`, `find_weight`, kind-blind `forget`, `identify_loot`, `remove_curse` | `ScrollSystem`, `LootSystem`, `Data._pick_by_find_weight` |
| 3 | The **data** — `PotionData`, the generator, §7.3's 30 sheet cells, `roll_potion` | `data/potions2.0/` (15 rows, 9/3/3) |
| 4 | **`PotionSystem`** (autoload #23) and the **quaff** verb | `scripts/autoload/PotionSystem.gd` |

Each has a CHANGELOG entry with the reasoning; the four openers are *"Statuses can
be borrowed"*, *"Every scroll in the game was Common"*, *"Fifteen potions exist as
content"* and *"You can drink a potion"*.

**What a caller touches today:**

```gdscript
GameState.apply_status(&"dexterity", 5, 1)      # 5 stacks, for one game
GameState.add_potion_loot(&"fire_potion")       # DevTools-style grant
LootSystem.use_loot(index, {"rng": rng})        # quaffs a carried potion
PotionSystem.quaff_potion(entry, {"rng": rng})  # {logs, requests}, like its siblings
```

**Tests:** `test_potion_system.gd` (33), `test_timed_statuses.gd` (26), the
*Potions2.0* section of `test_redesign2.gd` (15), the step-2 additions in
`test_scroll_system2.gd` (17).

## 3. What is next — §11 step 5, the throw

This is the big one. §4.2–§4.7 of the plan specify all of it; the order that works:

1. **`GameLoop2.area_cells(cell, area)`** — the shapes an `area=` token names
   (`cell` / `row` / `col` / `3x3` / `board`), resolved relative to the aimed cell,
   **clipped and never wrapped**. It belongs beside `target_cells` and
   `column_cells`, because the board owns what a shape means. Note §4.3's rule that
   the area resolves **twice** and the two lists differ: cells for the tile clauses,
   **deduped instances** for anything aimed at a body.
2. **`max_health` on a board entry** (§4.6), seeded from `effective_health` when a
   body spawns and serialized beside `health` and `shield`. `grant_health` caps at
   it; `grant_max_health` raises it and the current pool together. It is worth
   having anyway — it is the number the enemy health bar has been drawing without
   ever being told.
3. **The four new ops** — `deal_damage`, `grant_shield`, `grant_health`,
   `grant_max_health` — plus `apply_tile` and `apply_status` on the throw side.
   `deal_damage` goes through `GameLoop2._damage_enemy`, **not `_explode`** (§4.4):
   a throw is not a bomb, fires no `bomb_used`, is not widened by Brimstone, and a
   body it kills is destroyed rather than defeated. A boss takes no damage from one.
4. **The picker.** Generalise `BattlefieldView.aim_cells` past `ItemData` (§4.2) —
   widen it, do not fork it. `ctx.target` carrying a `Vector2i` is the existing
   convention (`EffectSystem._effect_cells` reads exactly that key), and a throw is
   deliberately **not** a `request`: a request is fulfilled after the piece
   resolved, and a throw has nothing to resolve until it knows where it landed.
5. **The second button** in `LootUseModal`: Quaff and Throw side by side on a
   potion, one Use on everything else. The throw arms the picker, hides the modal,
   and resumes on the click. **No confirmation** (decision #27).
6. **The Landmine's `damaged:` trigger** (§4.7) — the one piece of step 5 that is
   not potion code, and a §17.1 spec edit.

Then steps 6–8 as §11 lists them: `loot_capacity()`, the three-way income split,
and the README/CHANGELOG pass.

## 4. Five things step 5 inherits

- **`LootSystem._resolve` has a `"potion"` arm that ignores `ctx.verb` and always
  quaffs.** That is the seam: read `ctx.verb` there and route to `throw_potion`.
  The comment on it says so.
- **`PotionData.ops(verb)` / `line(verb)` already take the verb**, and
  `has_throw()` already answers §4.5's button rule.
- **`PotionSystem.LOOT_SCALED_FIELDS` covers the quaff ops only.** The throw side
  adds the four new ops' `value` **and** §8.2's `area` LADDER, which is the unusual
  half: a grid cannot be twice as big, so the Bark widens by one step — `cell` stays
  `cell` (a radius of zero doubles to zero), `3x3` → `5x5`, a row or column → the
  **cross**. The generator already accepts `5x5` as an area token.
- **Raise Level has no throw PROSE either**, not just no throw effect — its `On
  Tile` cell is the sheet's `N/A`. `PotionSystem.description` already says *"this
  one cannot be thrown"* rather than drawing a blank row; the Throw BUTTON has to
  make the same distinction, and §4.5 is careful about which way: hidden for a
  KNOWN potion with no throw, offered for an unknown one, which fizzles on impact.
  Hiding it for unknowns would leak which bottles have no throw.
- **The timed layer takes `games` straight through.** Do not add a second path for
  timed stacks on the throw side; `GameLoop2.apply_status_to(instance, id, stacks,
  games)` already exists and already reports the clock in `goal_text_for`.

## 5. Decisions the build made that the plan did not

Each of these is now load-bearing, and none of them is in the plan:

- **The vial deal is by colour NAME, not by file.** Golden and Magenta each ship
  in both art sets, and decision #18 has an unknown bottle introduce itself by its
  colour — two potions answering *"Golden Potion"* would make the run log ambiguous
  about the mystery the player is tracking. `PotionSystem.ensure_colors` draws one
  vial per distinct name; both files stay in the pool, at most one of each pair is
  dealt. A test hammers 25 deals to keep it true.
- **The kind-blind half of every loot verb lives on `LootSystem`** —
  `identified_types`, `unidentify`, `identify`, `forget_identified`,
  `carried_unidentified`, `pick_label`. Adding potions to Amnesia and Identify was
  one line in each of two functions. Anything else kind-blind should go there too.
- **One level is `GameState.grant_level_up`.** Stats plus the character's own
  reward, no condition; `Overworld2` keeps the condition and the bonus-level chain,
  which are the parts about EARNING a level. A run with no character cannot level,
  so `gain_level` reads the counter rather than trusting the call and fizzles in
  words when nothing moved.
- **`find_weight` is parsed out of the Notes column's PROSE** on `scrolls2.0`
  (`"+25% find rate"` → 1.25). `PotionData` deliberately has **no** `find_weight`:
  `potions2.0` has no Notes column, and a field nothing can write is the mistake
  `rarity` was making until step 2 caught it. Add it the day the sheet grows a
  place to say it.
- **Identify's candidates are carried ENTRIES, deduped per type**, and the picker
  names a scroll while leaving a pill or a potion as its art. A scroll's mask is
  one shared picture, so an unnamed list is not a choice; a potion's mask is its
  colour, and `LootSystem.pick_label` falls through to `display_name`, which names
  the colour and never the potion.

## 6. The workbook

- **Every machine column is authored now.** Three one-shots have edited it, all
  through `_xlsx_surgery`: `_potions2_uselessness_uncommon.py` (the Common →
  Uncommon move), `_scrolls2_step2_effects.py` (three `scrolls2.0` Effect cells)
  and `_potions2_effect_cells.py` (§7.3's 30 cells). A future edit is a re-TUNE,
  and the step-3 script will refuse to run over a cell that is not blank —
  deliberately. Write a new guarded one-shot instead.
- **Never openpyxl-save it** — it drops the charts on `Map Analysis`. Use
  `tools/_xlsx_surgery.py`; `_scrolls2_step2_effects.py` is the template worth
  copying, because it guards every cell against the value it EXPECTS and refuses
  the whole edit if the sheet moved underneath it. Regenerate in the same commit,
  or the sheet and `data/` disagree until somebody notices.
- **Verify afterwards by PART, never by file size.** `_xlsx_surgery` rewrites the
  whole zip, so git reports a large binary delta for a one-cell edit (#204 made the
  file 83 KB *smaller*; nothing was lost):

  ```bash
  python3 - <<'PY'
  import hashlib, subprocess, zipfile
  open("/tmp/old.xlsx", "wb").write(
      subprocess.run(["git", "show", "HEAD~1:tools/Roguelikes.xlsx"],
                     capture_output=True).stdout)
  h = lambda p: {n: hashlib.sha1(zipfile.ZipFile(p).read(n)).hexdigest()
                 for n in zipfile.ZipFile(p).namelist()}
  a, b = h("/tmp/old.xlsx"), h("tools/Roguelikes.xlsx")
  print("changed:", [k for k in a if a[k] != b.get(k)])
  PY
  ```

  A clean one-sheet edit prints **one or two** parts: that sheet's
  `xl/worksheets/sheetN.xml`, and its `xl/tables/tableN.xml` only when the grid's
  SHAPE changed — filling cells inside an unchanged rectangle regenerates the table
  part byte-for-byte and git never sees it. Any `xl/charts/*` in that list means the
  charts were touched, which is the failure this check exists to catch.
- **A sheet's NAME does not tell you its file name.** `potions2.0` is `sheet11.xml`
  and `scrolls2.0` is `sheet9.xml`, but only by coincidence of ordering — resolve
  `<sheet name=… r:id=…>` in `xl/workbook.xml` through `xl/_rels/workbook.xml.rels`,
  which is what `_xlsx_surgery.sheet_parts` does.
- **Do not hand-edit it between sessions.** It is a binary blob in git and
  concurrent edits do not merge — one version wins. If it does get edited, say so
  at the start of the session so the sheet is re-read rather than written over.

## 7. Working notes that cost time

- **The GUT filter flag.** `-gtest=res://test/foo.gd` does **not** filter; it runs
  all 33 scripts. What works:
  ```bash
  godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gprefix=test_potion -gexit
  ```
  Iterate with that (sub-second), then run the whole suite before committing.
- **A full run is 6–9 minutes** and buffers its output until it exits, so a
  backgrounded run shows an empty log the whole time it is working. Redirect to a
  file and wait for it rather than assuming it has died.
- **Do not edit source while a suite run is in flight.** Autoloads are loaded once
  at process start, so a mid-run edit is not picked up and the green you get back
  describes a tree that no longer exists. Finish the run, then edit, then re-run.
- **A fresh clone has no `.godot/`**, so the first headless run pays for a full
  import. `godot --headless --editor --quit` once at the start of a session.
- **That same command is needed after a new `class_name` AND after rebuilding the
  glyph fonts** — Godot re-imports the changed `.ttf`s only when the editor scans,
  and until it does, a new glyph is on disk and `test_display_settings.gd` still
  fails, which reads exactly like the font script not having worked. 🧪 cost a cycle
  to that. `tools/build_glyph_font.py` also needs `pip install fonttools brotli`.
- **`--check-only --script` on an autoload is not a syntax check.** It reports
  `Identifier not found: GameState` for any file that references another autoload,
  on clean files too. It is only useful for CLAUDE.md's shadows-a-native-class
  check — which `PotionData` was run through, and passed.

## 8. Corrections worth carrying forward

Four so far, one per step, and every one was found by building the thing rather
than by reasoning about it:

- **Step 1.** The design said to cap a status's stacks on read. Wrong: the authored
  ceiling (Burn's `Max: 3`) is a rule about the way **up**, and stacks already over
  it must tick down one at a time rather than being frozen. The cap applies only to
  what the timed layer *adds*.
- **Step 2.** A `loot` forget ran its count against EACH alphabet in turn, so
  `forget 1` forgot one scroll **and** one pill. Merging the two implementations
  exposed it; neither was wrong on its own terms.
- **Step 3.** Raise Level has no throw PROSE either, not just no throw effect. §3's
  roster writes that cell as "— (N/A)" and it reads like a formatting choice; it is
  data, and the card has to draw it.
- **Step 4.** Two vials share a colour word, twice over, which decision #18 did not
  account for. See §5 above.

Expect more. The plan is careful but it is still a plan; where it and a green test
disagree, the test is describing the build.
