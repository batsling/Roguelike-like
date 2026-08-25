# Potions — session handoff

**All eight steps of [`potions-design.md`](potions-design.md) §11 are built.**
Potions are a finished kind: they drop, they draw, they drag, they bin, they
echo, they identify, and they are spent by drinking them or by throwing them at
a square of the battlefield.

That doc is the spec; this one is only how to pick the work back up. Everything
about *what* potions are and *why* lives there — nothing in here restates it, so
if the two ever disagree, the plan is right and this file is stale.

---

## 1. Where things are

- **Steps 1–4 are on `main`** (PRs #204 and #205). **Steps 5–8 are on
  `claude/potions-design-44t17j`**, branched off `806bd11`. Pushed; no PR, none
  was asked for.
- **Suite:** green. `Scripts 33, Tests 1665, Passing 1665, Orphans 3` in ~530s.
  The 3 orphans and the leaked-RID warnings at the end of a run are pre-existing
  UI-test noise; a **Risky / "Did not assert" is not** (see CLAUDE.md). The ASSERT
  count moves between runs because several tests walk a random graph — the test
  count is the stable number.
- **Read before touching anything:** `docs/potions-design.md` §1 (the 30 locked
  decisions) and §9.1 (the reuse map — what already existed and was not rebuilt).
  §11 is now a record rather than a plan.

## 2. What is built

| Step | What landed | Where |
|---|---|---|
| 1 | The **timed status layer** — stacks that expire on their own | `GameState.timed_statuses`, `GameLoop2._expire_timed_statuses`, `StatusData.clock_note` |
| 2 | The **scroll deltas** — rarity, `description`, `find_weight`, kind-blind `forget`, `identify_loot`, `remove_curse` | `ScrollSystem`, `LootSystem`, `Data._pick_by_find_weight` |
| 3 | The **data** — `PotionData`, the generator, §7.3's 30 sheet cells, `roll_potion` | `data/potions2.0/` (15 rows, 9/3/3) |
| 4 | **`PotionSystem`** (autoload #23) and the **quaff** verb | `scripts/autoload/PotionSystem.gd` |
| 5 | The **throw** — geometry, `max_health`, the six throw ops, the picker, the second button, the Landmine's `damaged:` | `GameLoop2.area_cells`, `PotionSystem.throw_potion`, `BattlefieldView`, `LootUseModal` |
| 6 | **`GameState.loot_capacity()`** — the seam for a bigger bag, no relic | `GameState`, `LootGrid.grid_columns()` |
| 7 | The **three-way payout** — one roll, one place | `GameState.roll_loot_kind()` |
| 8 | The **catalog's third sub-tab**, README, CHANGELOG | `Collection.gd`, `README.md` |

Each has a CHANGELOG entry with the reasoning; the openers are *"Statuses can be
borrowed"*, *"Every scroll in the game was Common"*, *"Fifteen potions exist as
content"*, *"You can drink a potion"*, *"You can throw one now, at a square you
pick"* and *"a cap that can move"*.

**What a caller touches today:**

```gdscript
GameState.apply_status(&"dexterity", 5, 1)          # 5 stacks, for one game
GameState.add_potion_loot(&"fire_potion")           # DevTools-style grant
LootSystem.use_loot(index, {"rng": rng})            # quaffs a carried potion
LootSystem.use_loot(index, {"rng": rng, "verb": "throw", "target": cell})
PotionSystem.throw_potion(entry, {"target": cell})  # {logs, requests}
GameLoop2.area_cells(cell, "3x3")                   # the shapes an area= names
GameState.loot_capacity()                           # never LOOT_CAPACITY
```

**Tests:** `test_potion_system.gd` (80), `test_timed_statuses.gd` (26), the
*Potions2.0* section of `test_redesign2.gd` (15), the step-2 additions in
`test_scroll_system2.gd` (17).

## 3. What is NOT built, deliberately

None of these is a loose end; each is a decision the plan made and wrote down.

- **No relic pays out a potion.** `EffectSystem.gain_potion` is registered AND
  `generate_item_tres.py` parses it, so an `items2.0` cell saying `gain_potion 1`
  works — nothing authors one yet (§8). Both halves matter: a handler the
  generator cannot parse is a verb the sheet can write and silently get nothing
  from, which is the `rarity` failure §10 caught.
- **No `deal_damage` or `gain_level` on `EffectSystem`**, though §9.2 listed them
  beside `gain_potion`. The potion path dispatches through `PotionSystem`'s own
  table rather than that one, and an item-side `deal_damage` needs a target/area
  vocabulary on `items2.0` that nothing is asking for. Register them — with the
  parser, per the row above — the day a sheet cell wants one.
- **`games=` on `apply_status` is authorable from `items2.0` now** and nothing
  authors it either. The timed layer was built for potions and is not theirs; an
  item or a location that wants to lend a buff for a game says so with the same
  token.
- **No bigger bag.** `loot_capacity()` is base 9 with nothing adding to it
  (§8.1, decision #15). Whoever authors the relic adds the term in that one
  function — and inherits the 720p fit problem knowingly, which is the whole
  point of building the seam early.
- **Lucky Foot is still pills-only** (§8). Its sheet cell says `pills_positive`
  and its whole text is about pills. Widening it is a balance call, not a
  consequence of this work.
- **`PotionData` has no `find_weight`.** `potions2.0` has no Notes column to
  author one in, and a field nothing can write is the mistake `rarity` was making
  until step 2 caught it (§7.1). Add it the day the sheet grows a place to say it.
- **The Landmine is the only unit with a `damaged:` list.** The trigger word is
  in the DSL for the next unit that wants to react to damage differently — a
  barrel that breaks, a totem that fires when shot (§4.7).

## 4. Where to tune it

§12's four open questions are down to two, and both are balance rather than
build:

- **Fysh Oil's two clauses under Sacred Bark** — the Bark doubles named fields
  per op, so a two-clause potion doubles both (2 Strength *and* 2 Dexterity).
  Correct by the rule; worth eyeballing against the one-clause rows in play.
- **Lucky Foot's reach**, above.

Beyond those, the numbers that will want turning first: the **one-in-three** loot
split (`GameState.LOOT_KINDS`), Fire Potion's 3x3 (decision #11 makes a Common
bottle the most board-changing thing in the pool, deliberately), and the
**9/3/3 rarity spread** on `potions2.0`.

## 5. Decisions the build made that the plan did not

Each of these is load-bearing, and none of them was in the plan:

- **The vial deal is by colour NAME, not by file.** Golden and Magenta each ship
  in both art sets, and decision #18 has an unknown bottle introduce itself by its
  colour — two potions answering *"Golden Potion"* would make the run log ambiguous
  about the mystery the player is tracking. `PotionSystem.ensure_colors` draws one
  vial per distinct name; both files stay in the pool, at most one of each pair is
  dealt. A test hammers 25 deals to keep it true.
- **The kind-blind half of every loot verb lives on `LootSystem`** —
  `identified_types`, `unidentify`, `identify`, `forget_identified`,
  `carried_unidentified`, `pick_label`, and now `can_throw` / `is_throw` /
  `use_verb`. Anything else kind-blind should go there too.
- **One level is `GameState.grant_level_up`.** Stats plus the character's own
  reward, no condition; `Overworld2` keeps the condition and the bonus-level chain,
  which are the parts about EARNING a level.
- **Identify's candidates are carried ENTRIES, deduped per type**, and the picker
  names a scroll while leaving a pill or a potion as its art.
- **`LootDiscoveries` is NOT kind-blind and cannot be made so cheaply.** It walks
  each catalog and asks that system whether a row is identified, so a third
  alphabet is a third walk, a third row and a second *unlearned* count. Worth
  knowing before adding a fourth: it looks like the sort of thing `LootSystem`
  should answer, and the reason it isn't is that the two masked kinds count their
  spares in different units — a pill is a COLOUR out of 13, a potion a BOTTLE out
  of 37, and one summed number is useless for either.
- **`BattlefieldView.aim_cells` takes an aim REQUEST**, not just an `ItemData`:
  `{target_kind, col_min, col_max}`, which both an item and a thrown bottle can
  produce. One highlight rule and one accepted-click rule is the whole reason that
  function exists, so the second thing that aims at ground widened it rather than
  forking it.
- **A throw is refused while the drop screen is up**, and arming one closes the
  loot window and the info card. All three float over the board, and a picker
  armed under any of them lights squares nobody can reach. Nothing is spent, so
  the modal says so rather than offering a button that does not work.
- **`UITheme.action_button(text, colour, …)`** — the affirmative plate in a colour
  of its own, which `confirm_button` is now a thin wrapper of. The potion card is
  the one screen that offers TWO affirmatives, and two identical green plates read
  as one button drawn twice.

## 6. The workbook

- **Every machine column is authored.** Four one-shots have edited it, all
  through `_xlsx_surgery`: `_potions2_uselessness_uncommon.py` (the Common →
  Uncommon move), `_scrolls2_step2_effects.py` (three `scrolls2.0` Effect cells),
  `_potions2_effect_cells.py` (§7.3's 30 cells) and `_units2_landmine_damaged.py`
  (the Landmine's second trigger and its Description). A future edit is a re-TUNE,
  and each of those scripts will refuse to run over a cell that does not say what
  it expects — deliberately. Write a new guarded one-shot instead.
- **Never openpyxl-save it** — it drops the charts on `Map Analysis`. Use
  `tools/_xlsx_surgery.py`; `_units2_landmine_damaged.py` is the newest template
  and guards two columns of one row against the values it expects, refusing the
  whole edit if the sheet moved underneath it. Regenerate in the same commit, or
  the sheet and `data/` disagree until somebody notices.
- **Verify afterwards by PART, never by file size.** `_xlsx_surgery` rewrites the
  whole zip, so git reports a large binary delta for a one-cell edit:

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
  `xl/worksheets/sheetN.xml`, and its `xl/tables/tableN.xml`. The table part comes
  back whenever `write_grid` regenerates it — it drops Excel's `xr3:uid`
  attributes on each `tableColumn`, which is harmless and is what the last edit
  did. Any `xl/charts/*` in that list means the charts were touched, which is the
  failure this check exists to catch.
- **A sheet's NAME does not tell you its file name.** `potions2.0` is `sheet11.xml`,
  `scrolls2.0` is `sheet9.xml` and `units2.0` is `sheet15.xml`, all by coincidence
  of ordering — resolve `<sheet name=… r:id=…>` in `xl/workbook.xml` through
  `xl/_rels/workbook.xml.rels`, which is what `_xlsx_surgery.sheet_parts` does.
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
- **`test_overworld2.gd` alone is ~335s of that**, so it is not a cheap smoke
  test — but it is the one that proves `Overworld2.gd` still parses, which is
  worth knowing before a full run.
- **Do not edit source while a suite run is in flight.** Autoloads are loaded once
  at process start, so a mid-run edit is not picked up and the green you get back
  describes a tree that no longer exists.
- **A fresh clone has no `.godot/`**, so the first headless run pays for a full
  import. `godot --headless --editor --quit` once at the start of a session.
- **`test_display_settings.gd` scans SOURCE, comments included.** A `⅓` typed into
  a GDScript comment fails the glyph test exactly as one in a Label would, and the
  message reads like a font problem. Spell fractions out in prose.
- **`--check-only --script` on an autoload is not a syntax check.** It reports
  `Identifier not found: GameState` for any file that references another autoload,
  on clean files too. It is only useful for CLAUDE.md's shadows-a-native-class
  check.
- **A body built by hand in a test does not survive `serialize` / `restore`.**
  `_deserialize_entry` drops an entry whose enemy id the catalog does not know, so
  a save/load test needs a real row out of `Data.all_goal_enemies()` rather than
  the synthetic enemy the rest of a suite uses.

## 8. Corrections worth carrying forward

Five so far, one per step that had one, and every one was found by building the
thing rather than by reasoning about it:

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
- **Step 5.** §4.7 said to take a unit off the board **before** its `damaged:` list
  runs, reasoning from Hot Bombs laying fire back over the same cell. Wrong:
  `detonate` goes back through `detonate_unit`, which is what spends the unit,
  guards the chain and carries the bomb modifiers — and which refuses a cell with
  nothing on it. A mine erased ahead of its own trigger quietly failed to go off,
  and what caught it was Blood Bombs not being paid. The list runs with the unit
  standing there; the cell is cleared afterwards, whatever the list did.

The plan was careful and it still needed five corrections. Where it and a green
test disagree, the test is describing the build.
