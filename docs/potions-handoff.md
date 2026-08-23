# Potions — session handoff

Written at the end of the session that produced
[`potions-design.md`](potions-design.md) and built step 1 of its §11, and
**refreshed at the top of the session that started step 2**. **That doc is the
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
- **Step 2 is on `claude/potions-handoff-docs-9mjklk`**, branched off `16ea81d`.
- **A fresh session clones `main` and already has everything step 1 built**, so
  there is nothing to check out before reading the plan. Start with
  `docs/potions-design.md` §1 (the 30 locked decisions), §9.1 (the reuse map — the
  list of things that already exist and should not be rebuilt) and §11 (the build
  order).

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

Steps 3–8 then run as §11 lists them. Step 3 is the big one — the `PotionData`
resource, the generator, and **writing §7.3's 30 effect cells into the workbook**
(decision #30; see §4 below for how).

## 4. The workbook, as verified on `main`

- **Both edits survived the merge, and this was checked cell by cell rather than
  assumed.** A new `Roguelikes.xlsx` was uploaded twice while the design session was
  running (`1ffbc37`, `76fdec9`); the second added `scrolls2.0`'s `Notes` column
  header and Identify's *"Has a +25% find rate"* cell, which is the note §10 turns
  into `find_weight`. #204's squash merge landed the Uselessness surgery **on top of**
  that upload rather than reverting it. Nothing was lost.
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
  rather than writing over it.

## 5. Working notes that cost time

- **The GUT filter flag.** `-gtest=res://test/foo.gd` does **not** filter; it runs
  all 32 scripts. What works:
  ```bash
  godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gprefix=test_timed -gexit
  ```
  Iterate with that (sub-second), then run the whole suite before committing.
- **A full run is ~6.5 minutes** and buffers its output until it exits, so a
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
  `_potions2_uselessness_uncommon.py` is the template. Verify afterwards with the
  part-hash check in §4.

## 6. Two things to know before step 3

- **The 30 sheet cells are the next build session's to write** (decision #30),
  through `_xlsx_surgery`, from §7.3 of the plan. Follow
  `_potions2_uselessness_uncommon.py`: one one-shot, kept in `tools/`, and the
  part-hash check afterwards.
- **The four open questions in §12** are all recommendations already written down,
  not blockers: throwing mid-report, Fysh Oil under Sacred Bark, whether Bark's
  area-doubling leaves a `cell` alone, and Lucky Foot's reach. They are better
  answered by playing the thing than by asking again — the `verify` skill
  (`.claude/skills/verify/`) is how to get it on screen.

## 7. One correction worth carrying forward

The design said to cap a status's stacks on read. That is wrong and the suite
caught it: the authored ceiling (Burn's `Max: 3`) is a rule about the way **up**,
and stacks already over it — from a save written before the cap, or a cap the sheet
lowered — must tick down one at a time rather than being frozen. The cap now
applies only to what the timed layer *adds*, floored at the permanent count.

Expect more of these. The plan is careful but it is still a plan; where it and a
green test disagree, the test is describing the build.
