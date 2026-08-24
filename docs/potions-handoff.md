# Potions — session handoff

Written at the end of the session that produced
[`potions-design.md`](potions-design.md) and built step 1 of its §11, and
**rewritten at the end of the session that built steps 2 and 3**. **That doc is the
spec; this one is only how to pick the work back up.** Everything about *what*
potions are and *why* lives there — nothing in here restates it, so if the two ever
disagree, the plan is right and this file is stale.

---

## 1. Where things are

- **Step 1 is on `main`.** PR #204 — *"Add timed status layer for potion buffs
  expiring after one game"* — merged as `16ea81d`, and it carries the design doc,
  the timed-status layer, `test/test_timed_statuses.gd` and the one workbook edit.
  The branch it was built on, `claude/potions-loot-design-hlpttv`, is spent; the
  earlier revision of this file told you to check it out, and that instruction is
  now wrong.
- **Step 2 is on `claude/potions-handoff-docs-9mjklk`**, branched off `16ea81d`,
  pushed. No PR — none was asked for. If it has landed on `main` by the time you
  read this, a fresh clone has it and there is nothing to check out.
- **Suite:** green. `Scripts 32, Tests 1585, Passing 1585, Orphans 3` in ~560s.
  1549 before step 2, +21 for step 2, +15 for step 3. (The ASSERT count moves
  between runs — 32539 and 32650 on two green runs of the same tree — because
  several tests walk a random graph. The test count is the stable number.)
  The 3 orphans and the leaked-RID warnings at the end of a run are pre-existing
  UI-test noise; a **Risky / "Did not assert" is not** (see CLAUDE.md).
- Read `docs/potions-design.md` §1 (the 30 locked decisions), §9.1 (the reuse map —
  the list of things that already exist and should not be rebuilt) and §11 (the
  build order).

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

Where the pieces sit, for the session that has to extend them:

| Piece | Where |
|---|---|
| The player's layer | `GameState.timed_statuses` (`GameState.gd:518`), written by `apply_status` (`:1698`) |
| The per-game tick | `GameState.tick_timed_statuses()` (`:1818`) |
| Save / restore | `GameState.serialize_timed_statuses` / `restore_timed_statuses` (`:2062`, `:2073`), called from `SaveSystem.gd:270` / `:389` |
| The expiry hook | `GameLoop2._expire_timed_statuses()` (`GameLoop2.gd:2307`), run from `beat_game` into `res["statuses_expired"]` (`:1534`) |
| A body's layer | `entry["timed_statuses"]`, serialized in `GameLoop2.serialize()` (`:665`) |
| The wording | `StatusData.clock_note` / `clock_suffix` (`StatusData.gd:342`, `:350`) |

**Nothing applies one yet.** That is deliberate: the layer was built and tested
ahead of the content so a potion bug and a clock bug can never be the same bug.

## 3. What step 2 built, and the three things it decided

**The scroll deltas** (§10, §10.1): `rarity` and `description` off the sheet,
`find_weight`, the kind-blind `forget`, `identify_loot`, and `remove_curse` with
its picker. The narrative is the CHANGELOG entry opening *"Every scroll in the game
was Common"*; the tests are 17 in `test_scroll_system2.gd` and 4 in
`test_redesign2.gd`. What matters to step 3 is where it put things:

| Piece | Where |
|---|---|
| Kind-blind knowledge | `LootSystem.identified_types` / `unidentify` / `forget_identified` / `carried_unidentified` / `identify` / `pick_label` |
| The scroll's words | `ScrollSystem.scroll_text` (authored Description first, `assembled_text` as the fallback, `op_text` per op) |
| Remove Curse | `ScrollSystem._remove_curse` + `GameState.remove_curse_goal(index)` + `LootUseModal._pick_remove_curse` |
| The weighted draw | `Data._pick_by_find_weight`, inside `roll_scroll`'s rarity bucket |
| The sheet edit | `tools/_scrolls2_step2_effects.py` (three Effect cells, one one-shot) |

Three decisions the plan left open, settled by the build:

- **The kind-blind half lives on `LootSystem`, not on either consumable.** It is
  the layer that already knew there was more than one alphabet. `PotionSystem` is
  therefore a **one-line** addition to `identified_types` and `unidentify` in
  step 4 — every kind-blind verb widens at once and no call site changes.
- **`find_weight` is parsed out of the Notes column's PROSE** (`"+25% find rate"`
  → `1.25`) rather than given a column of its own, because it is one annotation on
  one row. `PotionData` should do the same. A test pins the parsed value, so a
  reworded note fails rather than silently reverting the weight to 1.0.
- **Identify's candidates are carried ENTRIES, deduped per type**, not ids — a
  pill's name depends on its entry, and an unknown potion's will too. The picker
  names a scroll outright (they all wear one art, so an unnamed list is not a
  choice) and leaves a pill as its capsule (its mask IS the colour, which the run
  protects everywhere else). **A potion is the pill case**: name the colour, per
  decision #18, and never the potion.

## 4. What step 3 built

**The data layer**, all of it: `scripts/resources/PotionData.gd`,
`tools/generate_potion2_tres.py`, `data/potions2.0/` (15 rows, 9 Common /
3 Uncommon / 3 Rare), `Data.get_potion` / `all_potions` / `roll_potion`, and
**§7.3's 30 effect cells written into the sheet** (decision #30) by
`tools/_potions2_effect_cells.py`. 15 tests in `test_redesign2.gd`'s
*Potions2.0* section.

**Nothing spends a potion yet.** Same discipline as step 1: the content exists
and is asserted before anything can run it, so a content bug and a `PotionSystem`
bug can never be the same bug.

Three things the build settled or turned up:

- **The two effect columns parse in two DIALECTS**, and the generator refuses a
  quaff verb in a throw cell and vice versa. They diverge more than they look: the
  quaff side targets the drinker (`target: "player"`) and the throw side is aimed
  (`area:`), and neither carries the other's word. That check is what turned up the
  next item.
- **Raise Level's `On Tile` PROSE cell is `N/A` too**, not just its effect — so one
  potion in fifteen has no throw line at all. Step 4's card has to read a blank
  there as *"this one cannot be thrown"* rather than as missing text. Uselessness
  is the contrast and is pinned by a test: it has no throw OPS but it does have
  prose (*"Do nothing"*), because doing nothing loudly is not the same as having no
  tile side.
- **`PotionData` carries no `find_weight`**, unlike `ScrollData`. `potions2.0` has
  no Notes column to author one in, and a field nothing can write is exactly the
  mistake `rarity` was making until step 2 caught it. It belongs there the day the
  sheet grows a place to say it.

## 5. What is next

**§11 step 4 — `PotionSystem`, quaff only.** The colour deal, identification, art
and `quaff_potion`; at that point a potion is playable as a pill with better art.
Then step 5 is the throw, which is where the new gameplay actually is.

Four things waiting for it:

- **`PotionSystem` is autoload #23** and goes in `project.godot`, whose comments
  are `;` and never `#` (CLAUDE.md).
- **The kind-blind verbs widen in one place.** Add a `"potion"` arm to
  `LootSystem.identified_types` and `LootSystem.unidentify`, and `forget loot`,
  `identify_loot` and everything after them cover potions with no call site
  touched. `GameState.identified_potion_types` and `potion_color_map` are
  **already declared, reset, saved and restored** — §9.1.
- **`PotionSystem.COLORS` must list all 37 vials**, and its test should check the
  list against the folder **in both directions**. `test_pill_system.gd` only checks
  one way, which is why art that ships without being listed is art no run can ever
  show; do not inherit that.
- **The prose is on the resource already** (`quaff_text` / `throw_text`), so the
  card quotes the sheet rather than assembling from ops — which is the lesson §10
  learned the hard way on `ScrollData`.

Also true, and the plan predates it:

- `data/scrolls2.0/` holds **8** rows, not 7, and they are **3 Common / 4 Uncommon
  / 1 Rare**. A test asserts the count; a sheet edit that adds a row means updating
  it.

## 6. The workbook, as verified

- **The uploads survived the merge, and this was checked part by part rather than
  assumed.** A new `Roguelikes.xlsx` was uploaded twice while the design session was
  running (`1ffbc37`, `76fdec9`); the second added `scrolls2.0`'s `Notes` column
  header and Identify's *"Has a +25% find rate"* cell, which is the note §10 turns
  into `find_weight`. #204's squash merge landed the Uselessness surgery **on top of**
  that upload rather than reverting it: between `76fdec9` and `16ea81d` the only
  parts that changed are `potions2.0`'s two, so the uploaded `scrolls2.0` came
  through untouched.
- **Step 2 made the third edit**, `tools/_scrolls2_step2_effects.py`: three
  `scrolls2.0` Effect cells — Amnesia's `forget loot 1`, Identify's
  `identify_loot choose 1`, and Remove Curse's `remove_curse choose 1`, which had
  been a row with a Description and no Effect since it was added. Three cells in
  ONE one-shot rather than three, because each write is a chance for two versions
  of a binary blob to exist at once. It changed exactly `sheet9.xml` +
  `table9.xml`, by the check below.
- **Step 3 made the fourth**, `tools/_potions2_effect_cells.py`: `potions2.0`'s
  column `E` (`On Player Effect`) and column `G` (`On Tile Effect`), all 15 rows,
  from §7.3 of the plan — the decision #30 cells. Every row is now fully authored;
  the sheet has no empty machine column left.
- **The file got 83 KB SMALLER in #204, and that is not damage.** `_xlsx_surgery`
  rewrites the whole zip, so the deflate level changes and git reports a large binary
  delta for a one-cell edit. The archive still holds its 8 charts and 47 worksheets.
  Do not read the size drop as chart loss — compare the parts instead:

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
  `xl/worksheets/sheetN.xml`, and its `xl/tables/tableN.xml` **only when the grid's
  shape changed** — `_xlsx_surgery` rewrites the table part every time, but filling
  in cells inside an unchanged rectangle regenerates it byte-for-byte and git never
  sees it. #204 and the step-2 edit print two; step 3's 30 cells print one. Any
  `xl/charts/*` in that list means the charts were touched, which is the failure
  this check exists to catch.
- **A sheet's NAME does not tell you its file name.** `potions2.0` is `sheet11.xml`
  and `scrolls2.0` is `sheet9.xml`, but that is a coincidence of this workbook's
  ordering — the real map is `<sheet name=… r:id=…>` in `xl/workbook.xml` resolved
  through `xl/_rels/workbook.xml.rels`. Resolve it rather than counting.
- **The corollary still stands: do not hand-edit the workbook between sessions.** It
  is a binary blob in git, and a session writing 30 cells into a copy that has since
  changed elsewhere does not merge — one version wins. It happened to be safe this
  time because the two edits touched different sheets. If it does get edited in the
  meantime, say so at the start of the session and it will re-read the sheet first
  rather than writing over it. It was safe the one time it was tested because the
  surgery ran against the uploaded copy rather than against a stale one — not
  because the two edits could not have collided. They were on the same sheet.

## 7. Working notes that cost time

- **The GUT filter flag.** `-gtest=res://test/foo.gd` does **not** filter; it runs
  all 32 scripts. What works:
  ```bash
  godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gprefix=test_timed -gexit
  ```
  Iterate with that (sub-second), then run the whole suite before committing.
- **A full run is ~9 minutes**, not the ~5 the older notes said — measured at 522s
  on 1549 tests, 516s on 1570 and 558s on 1585. It buffers its output until it exits, so a
  backgrounded run shows an empty log the whole time it is working. Redirect to a
  file and wait for it rather than assuming it has died.
- **A fresh clone has no `.godot/`**, so the first headless run pays for an import
  of the whole project. Run `godot --headless --editor --quit` once at the start of
  a session and the suite runs at its normal speed afterwards — it is the same
  command a new `class_name` needs, and `PotionData` will need it in step 3.
- **`--check-only --script` on an autoload is not a syntax check.** It reports
  `Identifier not found: GameState` / `TriggerBus` / `Data` for any file that
  references another autoload, on clean files too. It is only useful for the
  `class_name`-shadows-a-native-class check CLAUDE.md describes.
- **Never openpyxl-save the workbook** — it silently drops the charts. Use
  `tools/_xlsx_surgery.py` and keep the edit as a one-shot beside the others;
  `_scrolls2_step2_effects.py` is the template. Verify afterwards with the
  part-hash check in §6.

## 8. Two things to know about the sheet

- **The 30 sheet cells are written** (decision #30, `_potions2_effect_cells.py`),
  so the next edit to `potions2.0` is a re-tune rather than a first pass — and it
  will hit that script's guard, which refuses to run over a cell that is not blank.
  That is on purpose: it authors §7.3's first pass and nothing else. A tuning pass
  is its own one-shot, guarded against the value it expects to find, the way
  `_scrolls2_step2_effects.py` is. Regenerate in the same commit, or the sheet and
  `data/` disagree until somebody notices.
- **The four open questions in §12** are all recommendations already written down,
  not blockers: throwing mid-report, Fysh Oil under Sacred Bark, whether Bark's
  area-doubling leaves a `cell` alone, and Lucky Foot's reach. They are better
  answered by playing the thing than by asking again — the `verify` skill
  (`.claude/skills/verify/`) is how to get it on screen.

## 9. Corrections worth carrying forward

Three so far, one per step, and each was found by writing the thing down rather
than by reasoning about it:

- **Step 1.** The design said to cap a status's stacks on read. That is wrong and
  the suite caught it: the authored ceiling (Burn's `Max: 3`) is a rule about the
  way **up**, and stacks already over it — from a save written before the cap, or a
  cap the sheet lowered — must tick down one at a time rather than being frozen.
  The cap now applies only to what the timed layer *adds*, floored at the permanent
  count.
- **Step 2.** A `loot` forget ran its count against EACH alphabet in turn, so
  `forget 1` forgot one scroll **and** one pill — a scroll promising one thing
  taking two. Merging the two implementations is what exposed it; neither was wrong
  on its own terms.
- **Step 3.** Raise Level has no throw PROSE either, not just no throw effect. The
  plan's §3 roster writes that cell as "— (N/A)" and it is easy to read as a
  formatting choice; it is data, and a card is going to have to draw it.

Expect more of these. The plan is careful but it is still a plan; where it and a
green test disagree, the test is describing the build.
