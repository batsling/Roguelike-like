# Potions — session handoff

Written at the end of the session that produced
[`potions-design.md`](potions-design.md) and built step 1 of its §11, and
**rewritten at the end of the session that built step 2**. **That doc is the
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
- **Suite:** green. `Scripts 32, Tests 1570, Passing 1570, Orphans 3` in ~510s —
  1549 before step 2, and 21 tests added by it. (The ASSERT count moves between
  runs — 32539 and 32650 on two green runs of the same tree — because several
  tests walk a random graph. The test count is the number that should be stable.)
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

## 4. What is next

**§11 step 3 — the data.** `PotionData`, `tools/generate_potion2_tres.py`,
`Data` wiring, the editor rescan, and **writing §7.3's 30 effect cells into the
workbook** (decision #30; §5 and §7 below are how). Then step 4 is `PotionSystem` with
quaff only, at which point a potion is playable as a pill with better art, and
step 5 is where the new gameplay actually is.

Two things now true that the plan was written before:

- `data/scrolls2.0/` holds **8** rows, not 7, and they are **3 Common / 4 Uncommon
  / 1 Rare**. A test asserts the count; regenerating after a sheet edit that adds a
  row means updating it.
- `ScrollData` is the template `PotionData` copies — it now carries `rarity`,
  `description` and `find_weight` as well as `rarity_index()` and `art_file()`,
  and §7.1's list of fields is one draft behind it.

## 5. The workbook, as verified

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
- **`potions2.0`'s two effect columns are still empty for all 15 rows** — column `E`
  (`On Player Effect`) and column `G` (`On Tile Effect`). §7.3 of the plan is still
  what goes into them, and writing them is still the build session's job
  (decision #30). The prose columns `D` / `F`, `Rarity`, `Preference`, `Reference`
  and `File` are all authored.
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

  A clean one-sheet edit prints **exactly two** parts: that sheet's
  `xl/worksheets/sheetN.xml` and its `xl/tables/tableN.xml`. #204 prints
  `sheet11.xml` + `table11.xml` and nothing else. Any `xl/charts/*` in that list
  means the charts were touched, which is the failure this check exists to catch.
- **A sheet's NAME does not tell you its file name.** `potions2.0` is `sheet11.xml`
  and `scrolls2.0` is `sheet9.xml`, but that is a coincidence of this workbook's
  ordering — the real map is `<sheet name=… r:id=…>` in `xl/workbook.xml` resolved
  through `xl/_rels/workbook.xml.rels`. Resolve it rather than counting.
- **The corollary still stands: do not hand-edit the workbook between sessions.** It
  is a binary blob in git, and a session writing 30 cells into a copy that has since
  changed elsewhere does not merge — one version wins. It happened to be safe this
  time because the two edits touched different sheets. If it does get edited in the
  meantime, say so at the start of the session and it will re-read the sheet first
  rather than writing over it. It was safe this time because the surgery was run
  against the uploaded copy rather than against a stale one — not because the two
  edits could not have collided. They were on the same sheet.

## 6. Working notes that cost time

- **The GUT filter flag.** `-gtest=res://test/foo.gd` does **not** filter; it runs
  all 32 scripts. What works:
  ```bash
  godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gprefix=test_timed -gexit
  ```
  Iterate with that (sub-second), then run the whole suite before committing.
- **A full run is ~9 minutes**, not the ~5 the older notes said — measured at 522s
  on 1549 tests and 516s on 1570. It buffers its output until it exits, so a
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
  part-hash check in §5.

## 7. Two things to know before step 3

- **The 30 sheet cells are the next build session's to write** (decision #30),
  through `_xlsx_surgery`, from §7.3 of the plan. Follow
  `_scrolls2_step2_effects.py`, which is the closer template — it writes several
  cells in one pass, guards each against the value it EXPECTS to find, and refuses
  the whole edit if the sheet has moved underneath it. One one-shot, kept in
  `tools/`, and the part-hash check afterwards. Regenerate in the same pass, or the
  sheet and `data/` disagree until somebody notices.
- **The four open questions in §12** are all recommendations already written down,
  not blockers: throwing mid-report, Fysh Oil under Sacred Bark, whether Bark's
  area-doubling leaves a `cell` alone, and Lucky Foot's reach. They are better
  answered by playing the thing than by asking again — the `verify` skill
  (`.claude/skills/verify/`) is how to get it on screen.

## 8. One correction worth carrying forward

The design said to cap a status's stacks on read. That is wrong and the suite
caught it: the authored ceiling (Burn's `Max: 3`) is a rule about the way **up**,
and stacks already over it — from a save written before the cap, or a cap the sheet
lowered — must tick down one at a time rather than being frozen. The cap now
applies only to what the timed layer *adds*, floored at the permanent count.

Expect more of these. The plan is careful but it is still a plan; where it and a
green test disagree, the test is describing the build.
