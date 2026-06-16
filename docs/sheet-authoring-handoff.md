# Handoff: sheet-author items, events, and addons

**Goal:** make **items**, **events**, and **addons** generated from
`tools/Roguelikes.xlsx` the same way the entire **card** catalog already is —
the spreadsheet becomes the single source of truth, the `.tres` / generated
code are produced by a tool and never hand-edited.

Do this work in a **new spreadsheet section per target** (new sheets
`itemsnew` / `eventsnew`, mirroring how `cardsnew` and `cursesnew` are the
structured counterparts to the older prose `cards`/`curses` sheets). Leave the
existing prose sheets (`items`, `events`) untouched as reference.

---

## What's already done — use it as the template

The card catalog is fully sheet-authored. Study these before starting:

- `tools/generate_card_tres.py` — the reference generator. Note its Effects DSL
  parser (`_effect_from_tokens` / `parse_effects`), the `parse_attack` archetype
  parser, the upgrade-column handling, `parse_keywords`, and the `--all` /
  `--attacks` / default(curses) mode switch.
- `tools/generate_curse_tres.py` — the minimal generator pattern.
- `docs/action-attack-translation.md` — the attack-archetype design.
- Commits on branch `claude/nice-goldberg-0zbo4f`: the card flip
  (`Make all cards sheet-authored`, `Generate attack cards from the spreadsheet`,
  `Extend card Effects parser…`).

## The proven methodology (follow it for each target)

1. **Survey the gap.** Read the resource schema (`scripts/resources/*.gd`), the
   existing hand-authored `.tres`, and the sheet columns. Enumerate every field
   and every "effect verb" the hand-authored files actually use.
2. **Write/extend a generator** that turns a sheet row into a `.tres`.
3. **Build a parity harness** (a throwaway Python script): generate each row
   *in memory*, parse the corresponding hand-authored `.tres`, and diff
   field-by-field (parse the `key = [...]`/`{...}` blocks as JSON; compare tags
   as sets; ignore field order). This is how the card work was de-risked — do
   not skip it.
4. **Iterate** until only *acceptable* differences remain. Split diffs into:
   - **gameplay-critical** (must be 0 before flipping),
   - **cosmetic** (description wording, field order, dropped-but-unused fields),
   - **sheet-data gaps** (fix the cell), **parser gaps** (fix the code).
5. **Fix the sheet** for genuine data bugs/gaps (malformed cells, missing tags),
   editing `tools/Roguelikes.xlsx` with `openpyxl` and **documenting every cell
   change** so the user can keep it when they re-upload.
6. **Flip**: add a dedicated `--items` / `--events` mode, regenerate, re-verify
   art and structure, commit, push.

---

## Target 1 — Addons (easiest; start here)

- **State:** the addon *catalog* (display text) is **already** generated:
  `tools/import-reference-godot.py` builds `scripts/data/ReferenceCatalog.gd`
  from the `addonsnew` sheet (columns: Name, Deckbuilder, Action, Strategy,
  Has Value, Can Be Attatched To, Forms). Cards already reference addons by slug
  (e.g. `indiscriminate`, `fishing_weight`).
- **The gap:** the *runtime behavior* of each addon is hardcoded in
  `scripts/autoload/Stats.gd` (`apply_addons_to_effect`, `addon_damage_bonus`,
  …). The sheet describes addons in prose, not executable form.
- **Task / decision:** decide whether addon behavior should be data-driven. Most
  likely keep behavior in code but (a) verify every `addonsnew` row has a
  matching code arm and vice-versa (add a check/test), and (b) confirm the
  catalog regenerates cleanly. If the user wants behavior in the sheet, design a
  small per-mode effect DSL column. Confirm scope with the user first.

## Target 2 — Items (hardest; budget the most time)

- **State:** `data/items/*.tres` (~89 files) are **hand-authored**. There is
  **no item generator**. The schema (`scripts/resources/ItemData.gd`) is large
  and varied: `triggers`, `card_grants`, `stat_bonuses`, `scaling`,
  `status_amplify`, `stat_mirror`, `attack_damage_bonus`, `weapon_card_id`,
  `verification_*`, `perfect_*`, **`custom_handler`** (one-off code), and more.
- **The catch:** the `items` sheet columns are **prose** (Name, Rating, Type,
  Description, **Effect**, Reference, tags, File, Requirement, Sorting) — the
  `Effect` column is human text, **not** a structured DSL. So unlike cards,
  there is no machine-readable effect spec to parse yet.
- **Plan:**
  1. Create an **`itemsnew`** sheet with structured columns mirroring the
     ItemData schema (id/name/kind/rarity/tags/img + a structured **Effects
     DSL** column, plus columns for the common structured fields: triggers,
     card_grants, stat_bonuses, charge/weapon fields).
  2. Extend the card Effects-DSL approach to items, or write a dedicated item
     DSL. Reuse `tools/generate_card_tres.py`'s parser pieces where possible.
  3. **`custom_handler` items cannot be fully sheet-authored** — they point to
     bespoke GDScript. Give `itemsnew` a `custom_handler` column that just emits
     that field; the logic stays in code. Catalog the items that need it.
  4. Write `tools/generate_item_tres.py` + a `--items` flow, parity-check
     against the 89 hand-authored files, fix gaps, flip.
- **Expect** to do this incrementally (e.g. passive/stat items first, then
  triggered, then charged/weapon, then the custom-handler tail).

## Target 3 — Events (medium; nested data)

- **State:** `tools/generate_event_tres.py` already pulls event **metadata**
  from the `events` sheet, but the **narrative** (prompt + choices + per-outcome
  effects) is hand-authored in a Python dict named `AUTHORED` inside that file,
  keyed by the row's `Img`. Only 4 events exist.
- **The gap:** the branching narrative isn't in the sheet. Each event has
  several choices; each choice is a stat-check with `crit_good/good/bad/crit_bad`
  outcomes, each carrying a description + structured effects (see `EventData.gd`
  and the existing `AUTHORED` entries).
- **Plan:** design how to represent the choice/outcome tree in the sheet — e.g.
  an **`eventsnew`** sheet with one row per `(event, choice, outcome)` plus an
  effects-DSL cell, or a structured/JSON-in-cell encoding. Then move the
  `AUTHORED` content into the sheet and have the generator read it from there.
  Confirm the chosen layout with the user before porting all events.

---

## Conventions & guardrails (carried over from the card work)

- **Branch:** develop on `claude/nice-goldberg-0zbo4f`; commit with clear
  messages; push with `git push -u origin <branch>`. Do **not** open a PR unless
  asked.
- **Sheet edits:** the user manages `Roguelikes.xlsx` and re-uploads it via
  "Add files via upload". If you edit the xlsx with `openpyxl`, **list every
  cell you changed** so the user can replicate it; after `openpyxl` saves,
  verify sheet count + per-sheet row counts didn't change (it once looked like a
  sheet dropped — it hadn't, but check).
- **Don't clobber what the sheet can't yet express** — e.g. `custom_handler`
  items. Only flip a category to generated once a parity check shows 0
  gameplay-critical differences; report cosmetic ones.
- **Art:** every entity has art, so don't add a color column; resolve images
  from `images/<category>/` (cards also fall back to `images/items/`).
- **Ids & names:** id = slug of the full Name (keep disambiguating suffixes like
  `(Ironclad)` → `strike_ironclad`); display_name drops the trailing `(...)`.
- **`__pycache__`:** running the importer regenerates a tracked `.pyc`; restore
  it (`git checkout -- tools/__pycache__/…`) so it doesn't pollute commits.
- **No Godot runtime here** — validate by parity-diffing generated vs existing
  `.tres` and by confirming referenced art exists; you can't launch the game.

## Definition of done (per target)

- A generator + sheet section that reproduces every existing entity with **0
  gameplay-critical diffs** (verified by a parity harness).
- The hand-authored `.tres` regenerated from the sheet and committed.
- The generator's docstring + this section of the docs updated.
- Any items/events that genuinely require code (`custom_handler`, bespoke
  narrative logic) explicitly catalogued as the documented exceptions.
