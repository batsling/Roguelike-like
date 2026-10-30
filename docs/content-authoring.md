# Content authoring & tooling

How content gets into the game: the art folders, the spreadsheet and the
generators that turn it into `data/`, the research and map tools, and the
how-to for the two sheet-authored systems with the most moving parts (events and
objects). The full specs for each sheet are their own docs —
[`event-sheet-authoring.md`](event-sheet-authoring.md),
[`object-sheet-authoring.md`](object-sheet-authoring.md),
and [`item-sheet-authoring.md`](item-sheet-authoring.md) (the plan they were built
from is [`archive/sheet-authoring-handoff.md`](archive/sheet-authoring-handoff.md)); research is
[`research.md`](research.md). This page was the README's authoring half until
the README was split on 20 Oct 2026.

**The two rules everything here serves** (CLAUDE.md has the long form): the
spreadsheet `tools/Roguelikes.xlsx` is upstream of `data/`, so edit the sheet
and regenerate rather than hand-editing a generated `.tres`; and the `goals`
sheet is upstream of six of its own sheets (`python3 tools/apply_goals_sheet.py`).
**Never round-trip the workbook through openpyxl** — it drops the charts;
`tools/_xlsx_surgery.py` is how a sheet is edited.

## Adding art / images

**`images2.0/` is the drop folder for all art the games-first build uses**,
organized by category. `images/` holds what's left of the pre-2.0 art (the item /
event / encounter / character sets whose `data/` resources still load it). Because
the repository root is the Godot project, Godot reads both directly as
`res://images2.0/…` / `res://images/…` — there is no second copy to keep in sync.

To add or replace art:

1. Drop a **PNG** (covers may be **JPG**) into the matching subfolder, named to
   match the content id in **PascalCase** — or, for covers, the sheet's `File`
   column. The category folders are:

   | Folder | Used for |
   |---|---|
   | `images2.0/games/` | Real-game cover art — the overworld cards + Games compendium |
   | `images2.0/items/` | 2.0 item art (`data/items2.0`) |
   | `images2.0/enemies/`, `images2.0/bosses/` | Goal-enemy and boss art |
   | `images2.0/characters/Full/`, `images2.0/characters/Icon/` | 2.0 character portrait + in-world token |
   | `images2.0/scrolls/` | Scroll art (identified art + `Unidentified.png`) |
   | `images2.0/pills/` | Pill capsules — 13 colours, each with a `<Colour>Horse.png` twin. Bound to pills by the RUN, not by a `.tres` (`PillSystem.COLORS`), so adding art means adding its name to that list too |
   | `images2.0/statuses/` | Status art (`data/statuses2.0`) |
   | `images2.0/tiles/` | Tile-effect art (`data/tiles2.0`) |
   | `images2.0/units/` | Unit art (`data/units2.0`) |

2. **Reopen / refocus the Godot editor** so it imports the new file (Godot
   auto-imports anything placed under the project root).
3. Reference it from a `.tres` or script as `res://images2.0/<category>/<Name>.png`.
   Most content already resolves art by convention from its id or its sheet `File`
   column (e.g. a goal-enemy with `file = "Goblin"` looks for
   `res://images2.0/enemies/Goblin.png`).

> Art with nothing referencing it is deleted rather than kept "just in case" — the
> pruned folders (cards, statuses, covers, potions, spells, …) belonged to combat
> content whose `data/` resources are already gone. The last of the pre-2.0 art
> (`images/items/`, `images/characters/`) went with its data on 25 Oct 2026, and
> the old HTML build with it.

### Title letters (cut from real logos)

The main menu's title is to be spelled out of letters cut from real roguelikes'
logos, with each place's game drawn again every time the game opens (not yet
wired into the menu). The letters live one folder per letter, one file per game:
`images2.0/custom/title/<letter>/<game id>.png` (`r/balatro.png`). A piece that
is not a letter gets a name of its own; `dash` is the hyphen. So far: Balatro
(B A L T R O), Hades II (H A D E S), Hades (H A D E S) and Enter the Gungeon
(G U N G E O N, plus the pink E N T R H of "Enter the"). Two copies of one letter from the same logo
are `g/<game id>.png` and `g/<game id>_2.png` (a piece named `g.2` in the
config); a logo's exact repeats (Gungeon's pink E, T) are left out.
A small source shows blurry when the title draws it large, so Gungeon's config
sets `"scale": 3`: its letters are written at three times the logo's size, the
letter shapes and their black band redrawn crisp and the insides scaled pixel
for pixel. Prefer the biggest source there is; `scale` is for when there is none.

They are made by `tools/logo_letters.py`, never by hand, because a logo's letters
are not separate drawings: they share one outline, overlap, and sit on one drop
shadow. The script finds each letter by its light fill, rebuilds an even outline
round it in the logo's own shades, paints back anything a neighbour hid, and
re-casts the logo's shadow per letter (measured off the logo itself). Its
docstring has the detail. To add a logo:

1. Put the logo in `tools/logo_letters/<game id>.<ext>` (transparent background,
   as large as can be found — a Steam library logo or a press kit). `tools/` is
   `.gdignore`d, so Godot never imports it.
2. Copy `tools/logo_letters/balatro.json` to `<game id>.json` and give each piece
   a point inside its fill. Two letters whose fills run together need a `splits`
   line between them; a part one letter hid needs a `restore` polygon. Balatro
   has one of each (its T crossbar is drawn over the R's top-left corner), and
   `ignore`s its ace.
3. `python3 tools/logo_letters.py tools/logo_letters/<game id>.json --preview <png>`
   (needs `pip install numpy scipy pillow`) and look at the preview on magenta,
   which shows any stray pixel. Commit the config, the source and the PNGs.

The defaults suit a light fill in a dark outline over a soft drop shadow
(Balatro). `hades_ii.json` is the other worked example: white letters in a
hand-inked black outline with a glow, thorns that must not be smoothed away, and
a green II behind that has to go. It is cut, not repainted (`"cut"`): every pixel
kept is the logo's own. Each letter takes what the logo drew near it on its own
side of the line between letters; the II is found as the big regions of its
green and followed out through its glow (never across ink), and the few bits of
the II's rock outlines that touch a letter are cut away by hand (`erase`
polygons). Check a cut like this by putting the letters back where they were and
comparing with the source. A logo with dark letters and no outline at all would
need more than the script does today.

**How every logo is cut — the owner's standing instructions** (each line is a
correction they made along the way, so none of it is up for re-deciding):

- **Cut, never repaint.** Every pixel is the logo's own (`"cut"`). Colour-picking
  round a letter ("magic wand") lost spike detail and left messy retouches.
  Repainting is only for a part another letter hid (`restore`), and then in the
  logo's own face and outline colours.
- **Keep every spike and detail as drawn**; never smooth a letter's edge.
- **Nothing that is not the letter**: no background shape (Hades II's II), no
  bits of a neighbour, no streak ends running past the letter, no spatter, no
  loose flecks (`min_part`), no hole or loop a cut accidentally closes.
- **Each letter whole.** A part one letter drew over another is rebuilt
  (`restore`); a cut end gets the logo's outline round it.
- **Clean pixels.** Check on magenta zoomed in, and count each image's separate
  parts: a letter is one shape unless the logo itself splits it (red Hades'
  slash). Pixel-font letters are fully on or off (`hard_edge`).
- **Sharp at title size.** A letter only ~200px tall goes blurry when drawn
  large: find a bigger source, or set `scale` so the shapes are redrawn crisp.
- **Leave out a logo's exact repeats**; keep letters that differ (Gungeon's two
  G's have different cracks).
- **Ask** before deciding anything about the letters themselves: keep a slash or
  mend it, keep a spike, keep spatter, which of two overlapping letters is in
  front.

`hades.json` (the red Hades logo) shows the most of these at once: `assign`
moves the A's middle band out of the D, `restore` rebuilds the D's stem and
serif behind the A's leg and caps the A's band where its slash streak is cut
off, `despeckle` fills red flecks on the white faces, `min_part` drops loose
spatter, and `"scale": 2` redraws it in two tones, face and outline.

## The spreadsheet and the generators

`tools/Roguelikes.xlsx` is the **design source of truth** for bulk content. The
Python scripts in `tools/` regenerate Godot resources from it (re-run after
editing the sheet, then review the diff):

**The sheets lost their `2.0` suffixes.** `enemies2.0` is now `enemies`,
`items2.0` is `items`, and so on for characters, bosses, statuses, tiles, units,
scrolls, pills, potions, events, curses and objects; the pre-2.0 sheets they
displaced gained `old` (`itemsold`, `eventsold`, `charactersold`,
`encountersold`, `cursesold2`). Nothing reads the `old` sheets any more: their
output (`data/items/`, `data/characters/`, `data/curses/`) and generators were
deleted on 25 Oct 2026. The **output folders did not move** — the
generators still write `data/enemies2.0/` — so only the `SHEET_NAME` at the top
of each script changed. If a generator ever reports zero rows, this is the first
thing to check: openpyxl raises on a missing sheet, but a *renamed* one that
still exists under an old name silently generates the wrong content.

> **`data/games/` is NOT in this table, and that is the point.** It is written by
> `import-games-godot.py` (below), out of the `games` and `connections` sheets.
> There used to be a `generate_game_tres.py` beside these, named like them and
> writing to the same folder, but reading the retired HTML build's
> `games-data.js` through a hardcoded 15-game subset. Running it did not
> regenerate anything: it overwrote 15 of the 861 real files with a lossy copy,
> dropping `influence_sources`, `influence_relations`, `owned`, `file_location`
> and `steam_page`, and cutting `games_influenced` down to whatever was inside
> the subset (Hades: 48 links to 8). That is the graph the Atlas is baked from.
> It is deleted rather than fixed, because `import-games-godot.py` already does
> the job from the sheet the rest of the pipeline uses.

| Script | Generates |
|---|---|
| `generate_item2_tres.py` | `data/items2.0/*.tres` from the 2.0 items sheet |
| `generate_goal_enemy_tres.py` | `data/enemies2.0/*.tres` from the goal-enemy sheet |
| `generate_boss_tres.py` | `data/bosses2.0/*.tres` from the boss sheet |
| `generate_character2_tres.py` | `data/characters2.0/*.tres` from the characters sheet |
| `generate_scroll2_tres.py` | `data/scrolls2.0/*.tres` from the scrolls sheet — **and `data/scroll_names.tres`**, the bag of meaningless titles an unread scroll wears, off the same sheet's two right-hand columns (`Random Scroll Name` / `Random Scroll Part`) |
| `generate_pill2_tres.py` | `data/pills2.0/*.tres` from the `pills` sheet — one row is one pill and BOTH its doses, so it parses two effect columns onto one resource |
| `generate_potion2_tres.py` | `data/potions2.0/*.tres` from the `potions` sheet — two effect columns again, but they are two VERBS rather than two doses, so they parse in two dialects: the quaff side targets the drinker, the throw side takes an `area=` around the aimed cell |
| `generate_wand2_tres.py` | `data/wands2.0/*.tres` from the `wands` sheet — one effect column, plus the two columns only a wand has: `Charges` (what a fresh one holds) and `Type` (what it wants pointed at it). `nothing` is a verb here, and every *other* empty Effect cell is refused — Wand of Nothing is the roster's authored blank and a hole must not be able to look like one |
| `generate_trinket2_tres.py` | `data/trinkets2.0/*.tres` from the `trinkets` sheet — the Effect column is in the RELIC grammar, compiled by `item_dsl.parse_loot_passive` (shared with the passive cards), which refuses any relic field the pack cannot honour. `Size` is `HxW`, rows first (as the art is painted) — the foods are 2x1 and 1x2, and the pack places any rectangle (docs/loot-passives.md §10) |
| `generate_weapon_tres.py` | `data/weapons2.0/*.tres` from the `weapons` sheet — `Aim` (any/front/back/column N/enemy/none) and `Area` (a word, an `RxC` rectangle, or a `#.O` drawing) are validated here with the same grammar `GameLoop2.area_cells` reads; `Effect` is `stun N`; `Passive Effect` is the loot-passive grammar; `Goal` is written by `apply_goals_sheet.py` (docs/loot-passives.md §12) |
| `generate_evolution_tres.py` | `data/evolutions2.0/*.tres` from the `evolutions` sheet — both weapon names are checked against `weapons`, Requirement 2 must read `Any [N] Item(s) or Trinket(s) with "tag"` (docs/loot-passives.md §13) |
| `generate_bag2_tres.py` | `data/bags2.0/*.tres` from the `bags` sheet — `Size` is any `HxW` rectangle, rows first (the Potion Belt's `4x1` stands), and the Effect column (relic grammar, same parser) may be blank for a bag that only adds room (docs/loot-passives.md §6) |
| `generate_status_tres.py` | `data/statuses2.0/*.tres` from the `statuses` sheet — owns the reward-token DSL, and the `Decrease` column's table: `On Completion` sheds a stack when a SIDE is completed, while `On Trigger` and `Each Turn` are worn away by the BOARD (an attack, a turn) and mean *per game* on the player, who has neither |
| `generate_tile_tres.py` | `data/tiles2.0/*.tres` from the `tiles` sheet — owns the trigger / interaction DSL both board kinds use (§17) |
| `generate_unit_tres.py` | `data/units2.0/*.tres` from the `units` sheet — imports the parsers above rather than restating them |
| `generate_ability_tres.py` | `data/abilities2.0/*.tres` from the `abilities` sheet — and owns the **grammar of the enemy `Ability` column** (`Ranged (2), Fireproof, Infliction (1, Burn)`), which the goal-enemy generator imports rather than restating (§7.6) |
| `generate_event2_tres.py` | `data/events2.0/*.tres` from the `events` sheet — see [Authoring an event](#authoring-an-event) |
| `generate_curse2_tres.py` | `data/curses2.0/*.tres` from the `curses` sheet |
| `build_glyph_font.py` | `fonts/*.ttf` — the UI's symbol glyphs, subsetted from Noto. Not sheet-driven: it scans `scripts/**/*.gd` for the glyphs actually used. Run it after adding a new one; `--check` verifies without writing |
| `item_dsl.py` | **not a generator**: the item Effect-column DSL and ItemData writer that `generate_item2_tres.py` runs and the loot generators borrow (it was `generate_item_tres.py`) |
| `import-games-godot.py` | `data/games/*.tres` (incl. per-connection source + sequel flag), resolving each cover in `images2.0/games/` — then re-bakes the Atlas, and lists the games `research/ledger.json` has no entry for (`research.py new` researches them) |
| `research.py` | **not data**: every kind of research (connections, tags, goals, loot, events, characters, statuses, locations) in one place. Candidates in `research/<kind>.csv`; `build` writes them into `tools/Research.xlsx` for the owner and `sync` reads the owner's yes/no and edits back; `research/ledger.json` records what has been researched and `research/wikis.json` each game's wiki. `new` runs everything for games just added. See `docs/research.md` |
| `influence_research.py new` | **not data**: researches the games added since the last pass for influences (every scan that works from the cloud, over just those games) into `.influence_work/new_games.md`; `--mark` records them in `research/ledger.json`. See `docs/influence-research.md` |
| `apply_tag_edits.py` | the `games` sheet's **Tags** column, from the game's tag export (Settings → Game tags; `tools/tag_edits.json`), writing only each game's added/removed tags, through `_xlsx_surgery` so the charts and formula columns survive — then runs `import-games-godot.py`. Idempotent; `--dry-run` shows the changes |
| `apply_radio_import.py` | the `radio` sheet, from the Radio screen's *Export song list* (`tools/radio_import.json`): a row per new audio file in the player's music folder, from the file's own tags, its game matched from the folder it sits in. Only adds; through `_xlsx_surgery`, then runs `generate_song_tres.py`. `--dry-run`, `--game "Folder=Game"`; see `docs/roguelike-radio.md` §2a |
| `tag_research.py` | **not data**: the tag sheets of `tools/Research.xlsx` (it leaves the other sheets alone), tag suggestions for the owner from each game's Steam tags, store text and title. It never writes `Roguelikes.xlsx`; the owner types the tags they agree with into `games` |
| `bake_atlas.py` | `data/atlas_layout.tres` — the Atlas star chart's positions |
| `_relics_events_sheet_edit.py` | one-shot: the Boss/Event relic effects, the curse penalties, and the two new event rows |
| `_events2_ranwid_setup.py` | one-shot: the Ranwid the Elder event row |
| `_events2_tiny_rogues_setup.py` | one-shot: the `Opens With` column, the Potion Lab and Golden Monkey rows, and Ranwid's credit line |
| `_events2_we_meet_again_setup.py` | one-shot: the We Meet Again! event row |
| `_events2_woman_in_blue_setup.py` | one-shot: the Woman in Blue row, and Ranwid's gold ask settling at a flat 2 |
| `_events_gold_doubled.py` | one-shot (23 Oct): every gold cost and gold requirement an event asks doubled, once chests began paying gold |
| `_punch_off_robot_edit.py` | one-shot: Punch Off's "I Can Take Them" also spawns a robot (`spawn_enemy tag=robot 1`) |
| `_abilities_sheet_setup.py` | one-shot: settled the `abilities` sheet (the two riders' wording, the new **Agile** row), gave The Obscura and the two thieves their arguments, and turned the boss sheet's `Notes` column into `Phases` — with Guillatina as the first three-phase boss (§7.6) |
| `_chart_system_vocabulary.py` | one-shot: settled the `chart` sheet's System column on plural (`Bomb`/`Bombs` and three more collided, and a group-by rendered each as two systems), trimmed stray whitespace, and renamed the `Arcade` node to `Arcade Room`. |
| `_abilities_effect_column_setup.py` | one-shot: filled the `abilities` sheet's `Effect` column for all 31 rows — the `trigger: op args` DSL `GameLoop2` now dispatches on. Before it, the column was empty in every row and each ability was a hardcoded branch keyed by id, which made abilities the one content type whose behaviour was not authored upstream (§7.6) |
| `_chart_abilities_review_fixes.py` | one-shot: the ten fixes off the systems-graph ability review — dropped the duplicate `Loot Amount` Good Direction, pointed Haste at `Speed on Enemy`, renamed the Gold system to `Economy`, settled the new trigger names (`Enemy Attack`, `Enemy Passive`, `On Player Debuff`), and added the three structural rows (Enemy Damage, Shield Absorption, Lost Game). |
| `_chart_summoners_and_tiles.py` | one-shot: gave the five summoners the loot/gold payout §7.6 says a summoned body owes, and added the two tile rules (Fire applies Burn, Web applies Stun, both to enemies) — which took Tiles off the systems graph's sink list. |
| `_chart_enemy_goals.py` | one-shot: added `Goals · Goal Amount` and the `Enemy Goal` structural row, so the systems graph carries the game's central loop — a body arriving puts a real game on your evening, and beating that game is what takes a point of its Health (§7.6, "Health here is goal completions"). |
| `audit_systems_graph.py` | read-only audit of the `chart` sheet — the systems graph (`docs/systems-graph.md`). Reports uncoloured arrows, vocabulary collisions and dangling `Otainable` refs; coverage against every content sheet; and the collapsed system→system graph with its cycles and its sinks. Writes nothing, so it is safe to run any time. |
| `check_data_sync.py` | **is `data/` still what the sheet says?** Runs every generator over the checked-in workbook and asks git whether anything moved, then puts the tree back. This is the rule in CLAUDE.md ("the spreadsheet is upstream of `data/`") with something behind it: the first run found three rows that had drifted, two of them in one direction and one in the other. `check_map_sync.py` covers `data/games/`; this covers the other twenty folders. Run by CI. |
| `_xlsx_surgery.py` | shared helper: edit ONE sheet of `Roguelikes.xlsx` in place. An openpyxl round-trip drops the workbook's eight charts, so the sheet-editing one-shots (`_statuses_sheet_setup.py`, `_statuses2_combat_setup.py`, `_statuses2_burn_setup.py`, `_items2_statuses_setup.py`, `_events2_sheet_setup.py`, `_curses2_sheet_setup.py`, `_abilities_sheet_setup.py`, `_abilities_effect_column_setup.py`) rewrite just that sheet's XML parts and copy every other zip entry through untouched. |

**The one-shots live in `tools/oneshots/`** (moved there on 25 Oct 2026, so
`tools/` holds the generators, checks and research tools). Every `_*.py` named in
the table above is there except `_xlsx_surgery.py`, `_proof_names.py` and
`_candidates_to_sheet.py`, which real tools import or still use. Each moved script
carries a few lines at the top that resolve its paths as if it were still in
`tools/`, so `python3 tools/oneshots/<name>.py` behaves as it always did.

The `_*_setup.py` scripts are **bootstraps, not generators**: they lay a sheet's
header row down and re-author the rows they hold in Python. Once you are editing
a tab by hand you never need them again — and they will refuse to run rather than
overwrite a row they don't know about. `_relics_events_sheet_edit.py` is the same
kind of one-shot pointed at a single change (the Boss/Event relics, the curse
penalties, the Golden Idol and Relic Trader rows, and the two extra `Choice N`
column groups); it is idempotent and kept as the record of that edit.

These require Python 3 with `openpyxl` (`pip install openpyxl`) and are run from
the repository root, e.g.:

```bash
python3 tools/generate_item2_tres.py
```

`bake_atlas.py` runs automatically at the end of `import-games-godot.py`, so
adding a game or a connection to the spreadsheet and re-importing moves the sky
with it. Run it directly to re-tune the layout:

```bash
python3 tools/bake_atlas.py --all-filters  # every sky (what the importer runs)
python3 tools/bake_atlas.py                # 8 capitals, full catalog
python3 tools/bake_atlas.py --filter owned # just the owned-games sky
python3 tools/bake_atlas.py --capitals 12  # re-cut the constellations
python3 tools/bake_atlas.py --stats        # report without writing
```

One sky is baked per `Settings.game_filter` value. The Atlas has to show the
graph the run actually travels — an owned-only run drawn over the full 751-game
sky would offer routes through games the run cannot enter — so each variant is
laid out from scratch over its own subgraph and gets its own capitals rather
than being the full map with stars hidden.

It refuses to write a layout in which any two stars overlap, so a bad run fails
loudly rather than shipping an unreadable map.

**The same layout also runs at runtime.** `scripts/ui/AtlasLayoutBuilder.gd` is
a GDScript port of the baker's layout half (`build_graph` / `span_tree` /
`cluster_layout` / `pack_around` / `pack_discs`), because the sky for a filter
the player assembles in the Collection — "Deckbuilder + never beaten + owned" —
is one of hundreds of combinations and cannot be baked. The two agree about the
*shape* of a sky (same capitals, same regions, same hops, same no-overlap
guarantee) but are not bit-identical: `math.hypot` is not `sqrt(x*x + y*y)` in
the last bits, and the packer picks positions with strict comparisons a one-ulp
difference can flip. That never shows, because the unfiltered catalog is drawn
from the baked file. Keep the two in step when either changes — the tests in
`test/test_atlas_layout_builder.gd` assert the agreement.

**Is the map still healthy after a batch of new games?**
`tools/dump_map_health.gd` measures the run graph with the game's own code —
`RunGraph.degree`, `best_connected`, and `pick_amulet_and_starts` rolled a few hundred
times — under both the ALL and OWNED filters, and prints the shape of what a
player would be offered: how much of the catalog is on the map at all, how many
games qualify as starts, which Amulets and which starts actually come up, and
the spread of genres and route lengths across the cards.

```bash
MAP_HEALTH_ROLLS=200 godot --headless -s addons/gut/gut_cmdln.gd \
    -gdir=res://tools -gprefix=dump_ -gselect=dump_map_health.gd -gexit
```

It reports rather than asserts, because "healthy" is a judgement about the
catalog and not a property code can own: a genre that never wears a card and a
start that wears one run in twelve are both legal outputs of the picker, and the
number is the thing worth looking at. Adding connections moves it; a batch of
games hung off one hub moves it a lot.

---

## Authoring an event

An **event** is what the run does between games. One fires after every game
the run plays — win, loss, or escape — on top of whatever the game itself paid
(spec §12; the Event node that dealt one more on arrival was retired in §19.10).
The games this is a graph of are hour-long roguelikes, and an event is the beat
between two of them: a decision that takes a minute and costs something.
Everything about one lives in the **`events2.0` tab** of
`tools/Roguelikes.xlsx` — one row per event — and nothing about it lives in code.

**Which event you get** is dealt from a **shuffle bag**, per rarity:

- roll the rarity ladder (Luck rerolls it, like every other roll in the build),
  falling down to the nearest stocked rung — today everything is Common;
- draw from the events of that rarity **not yet seen this run**. Opening one
  marks it seen whether or not you engaged with it;
- when a rarity's bag empties it reshuffles, except that the event which just
  emptied it may not open the next bag;
- an event gated out right now (Requirement unmet, wrong tier) is **skipped and
  stays in the bag** rather than being burned.

Each **game** pays one event and then is spent for the run, so walking a
two-node loop is not an event faucet. A **detour** (`play_game`) pays none — its
destination is somewhere the run was sent, and an event there would land on top
of the stay-or-return question. Nor does the **Amulet** game: the run is over.

> Events used to hang off dead ends only, with placement **hashed** from the node
> id so the offered card's `✦ EVENT` badge could not change under the player.
> Both are gone — an event after every game means there is no subset of nodes to
> badge, and no honest answer to "which event is over there" before you arrive.

The full design rationale is [`docs/event-sheet-authoring.md`](event-sheet-authoring.md);
this is the how-to.

### The loop

```bash
# 1. edit the events2.0 tab in Excel
python3 tools/generate_event2_tres.py --list   # 2. dry run: parse it, write nothing
python3 tools/generate_event2_tres.py          # 3. write data/events2.0/*.tres
godot --headless -s addons/gut/gut_cmdln.gd    # 4. (optional) the suite still passes
```

The generator is **strict on purpose** — a typo'd stat or a dangling curse id is
an event that silently never fires, so it raises instead. Read the error, it
names the row and the cell.

### The row: fifteen event columns, then four choice groups

| Column | Fill in |
|---|---|
| `Event` | Display name. Slugified, this is the id (`Scrap Ooze` → `scrap_ooze`) and the `.tres` filename. |
| `Game` | The real game it's lifted from. Shows as "From: *game*" in the modal. |
| `Tier` | `All`, or a comma list of `Low` / `Medium` / `High` / `Insane`. |
| `Where` | **Leave blank.** An event fires after every game, so this answers nothing today. It stays wired (`Dead End` / `Any` / `Game`) for the per-location work. |
| `Requirement` | A gate on the run: `<stat> <op> <value>`, `%` reads against the max. `hp <= 70%`, `games >= 6`. Several clauses joined by **`and`** when an event needs more than one thing at once (`gold>=4 and potions>=1 and relics>=1` — Ranwid, whose every button spends a different kind of thing). Blank = always eligible. A gated event is skipped and stays in the bag. |
| `Trigger` | `After` (fires once the game at the node is played). ⚠ `Before` parses and is stored, but **nothing reads it yet**. Leave it `After` until that is wired up. |
| `Rarity` | `Common` / `Uncommon` / `Rare` — which bag it is dealt from. |
| `Image` | Art base name → `images2.0/events/<Image>.png`. Blank falls back to the de-spaced `Event`. |
| `Prompt` | The prose at the top of the modal. Blank is legal — a wordless event stacks its art *above* the choices instead of beside them (see "Art"). |
| `Opens With` | What the event is already doing when it opens, before anything is pressed. One token: `offer_loot <kind> <n>` — n rolled pieces laid out as the **real drop table inside the event's body**, with the player's live 3×3 and its bin beside them, so taking one is the same drag it is anywhere else (the Potion Lab). Blank on every other event — and note that loot an event PAYS lands on the same table, so a `gain_potion 3` in an `Effect` cell needs nothing here. |
| `Goal Met` / `Goal Missed` | Only if a choice uses `add_goal`: what the event says when that goal lands or lapses, games later. |
| `Chance Won` / `Chance Lost` | Only if a choice uses `chance`: what it says when the roll lands or doesn't. |

Then `Choice N | Repeat N | Result N | Effect N` for N = 1…6, in display order.
**A blank `Choice N` ends the list** — the generator stops reading there, so a
two-option event just leaves the remaining cells empty. (Six because the Golden
Idol is a five-button event — Take and Leave, then the three ways out from under
the boulder.)

`Result N` is the prose printed once that choice resolves; blank is legal (the
modal then prints only the mechanical line). `Effect N` is the payload.

### The `Effect` cell

Semicolon-separated tokens. It is the same reward DSL `statuses2.0` and
`items2.0` speak, so a chest an event pays is the chest an item pays.

| Token | Does |
|---|---|
| `gain_chest small\|medium\|large\|huge N` | N chests. The size is **how many items it offers to pick from** — small = 1, medium = 2, large = 3, huge = 5. |
| `gain_chest reward N` | The sheet's **`[chest reward]`** — N chest *points* spent on the size ladder instead of N chests of one size. Small 1, Medium 2, Large 3, Huge 4, then greedily Huge + a remainder: 3 = one Large, 6 = a Huge and a Medium, 8 = two Huges. Use this wherever the payout has to grow with something (a status's stack count); `gain_chest small {X}` grows into X screens each worth less than the last. |
| `gain_hp N` / `gain_max_hp N` / `gain_empty_max_hp N` / `heal_full` | Health. `gain_max_hp` raises the cap **and heals by the same amount** — the container arrives full. `gain_empty_max_hp` is the half that doesn't heal, for the item that means an empty container (Hollow Heart). |
| `lose_hp N` / `lose_max_hp N` | The same, pointed the other way — except `lose_max_hp` **costs no Health**: it takes the room, and Health only moves when it no longer fits. A `lose_hp` that empties Health ends the run — no separate kill token. |
| `take_damage N` | Damage rather than a bill: it resolves through `GameLoop2.damage_player`, so a Shield (§3) stops the whole instance and the player's own statuses scale it. `lose_hp` goes straight to Health past both. Burn's "or take 3 Damage" is what it was added for. |
| `gain_gold N` / `lose_gold N` / `lose_gold all` | Gold. `all` empties the purse — the one amount settled when the choice is taken rather than when the `.tres` is written. |
| `gain_stat <verb> N` / `lose_stat <verb> N` | `bash`, `dash`, `push`, `transmute`, `scramble`, `bombs`, `keys`, `shields`. |
| `gain_loot N` | A loot drop, rolled across every loot type there is — it widened on its own as pills and then potions arrived, with no row ever touched. `gain_scroll N`, `gain_pill N` and `gain_potion N` name one alphabet instead, for a row that is *about* that kind of thing (the Battleworn Dummy pays a potion because the dummy it is translated from does). |
| `apply_status <status> N` | A `statuses2.0` status on the player. On an **item** an optional `target=` says who instead: `current` / `all` / `random` name bodies by rule, and **`target=enemy` means one the player POINTS AT** — `ItemData.wants_target()` reads it, so the overworld arms the board and the click fires the item (Staff of Flame). A **scroll** takes the same words plus `player` and `front` (everything touching the front column — Scroll of Fire burns you and them at once). |
| `apply_tile <tile> …` | A `tiles2.0` TILE EFFECT on the GROUND (§17). On a **scroll**, `front` / `back` / `all` name a strip of the board (Scroll of Fire lights the front column). On an **item**, `target=tile` means a CELL the player POINTS AT — `ItemData.target_kind()` reads it, so the board arms a cell picker instead of lighting up the stack — and `cols=A-B` fences how far it reaches (Red Candle's columns 2-3). |
| `apply_unit <unit> …` | The same, for a `units2.0` UNIT (§17). `target=random_empty` puts it on a cell with nothing on it at all — no body, no unit, no tile effect (Landmines). |
| `random_item_choice N` | Pick 1 of N random items. |
| `gain_item <item_id>` | A **named** `items2.0` relic, handed straight over — the one token that says *which* item. The generator checks the id against the sheet. |
| `spawn_enemy [N] [tag=<t>]` | Conjures N enemies at the run's current difficulty onto the following stack. What every curse costs. `tag=` narrows the roll to the goal-enemies carrying that synergy tag (`spawn_enemy tag=robot 1` — Punch Off's Constructs); the generator checks the tag against the `enemies` sheet's Tag column, and a tagged roll widens by difficulty rather than dropping the tag. |
| `trade_relic <slot>` | The Relic Trader's swap: one of your relics for one of his. Fills `<give>` / `<get>` in the choice's prose. |
| `gain_random_item N` | N relics off the rollable pool, straight into the pack — not a chest opened a screen later. Prefers what you don't own, and fills `{ITEM}` with what it rolled. |
| `lose_potion` / `lose_relic` / `lose_card [uncommon+]` | A price paid in **things**: one bottle, one tradeable relic, one card. Which one is rolled when the event opens and named on the button through the `<potion>` / `<relic>` / `<card>` holes, so the player knows what they are handing over before they press (Ranwid the Elder, We Meet Again!). |
| `obtain_item` | Pick **any** item in the catalogue. This is Wand of Wishing's picker (the WAND's, since the relic became one — `docs/wands-design.md` §5.2) — much stronger than a chest, use deliberately. |
| `nothing` | An explicit no-op. Write it where a blank cell would read as unfinished. |

And the event-only forms:

```
needs keys 1                           only offered if the player HAS it (a check, not a charge)
needs Immerse > 0                      only offered at this point in the event (names another Choice)
add_goal "<condition>" [for <n> games] -> <reward>
add_curse <curse_id> | random [for <n> games]
play_game tag=<tag> -> <reward>
chance <p>% -> <reward>
```

- **`needs <resource> <n>` only checks.** It does not deduct — a locked chest
  that costs a key is `needs keys 1; lose_stat keys 1; gain_chest medium 1`, with
  the gate and the charge written separately. Gate stats: `hp`, `max_hp`, `gold`,
  `games`, `keys`, `bombs`, `bash`, `dash`, `push`, `transmute`, `scramble`,
  `shields`, `relics` (tradeable ones only) and `potions` (bottles carried).
- **`add_goal`** bolts an objective onto the next *n* games, in the same
  honour-system voice enemy goals use. Pays if met, costs nothing if not.
- **`add_curse random`** draws the curse when the button is pressed instead of
  naming one, and **never draws a permanent one** — a random roll that could hand
  out Curse of the Bell would make an idle button a coin flip on the rest of the
  run. The Golden Monkey is what it is for.
- **`add_curse`** is that inverted — an objective you want to *not* meet, which
  bills you every time you do. It takes an id from the **`curses2.0` tab**, so
  the curse is authored once and any event can hand out the same one. On the
  report checklist it is a row like any other — an **instruction** with its price
  after it (`CurseData2.goal_text()`, then `if failed, <penalty>`: "don't use a
  rest site to replenish health   if failed, Spawn a random enemy") — ticked if
  you followed it, and **left unticked is what fires the penalty**. Conditions
  authored as an absence ("you don't ring a bell") have the negation stripped
  rather than doubled, so the row reads "ring a bell".
- **`play_game`** sends the player to a random game carrying `tag`, off their
  route; the `->` payload lands when they beat it. **Check the tag has games
  behind it first** — the thin end of that vocabulary has single-game buckets.
- **`chance`** rolls. A win pays the `->` payload *and closes the event*; a loss
  pays nothing. The costs in front of it are charged either way.

`add_goal`, `play_game` and `chance` are **arrow verbs**: everything past the
`->` is their payload, so each has to be the last clause in its cell — which is
also what limits a cell to one of them, since a second could only come after the
first.

### Making a choice repeat, and escalate

Two columns do all the push-your-luck work:

| `Repeat N` | After the choice resolves |
|---|---|
| blank / `End` | The event closes. |
| `Again` | Stays open, choice still available. `Again x3` caps it. |
| `Stay` | Stays open, but this choice is now **spent** — which is how a two-stage event fits on one row. |

And inside an `Effect`, **`{X}` is how many times this choice has already been
taken** (0 on the first press) — and a hole may also name the run itself,
`MAX_HP` / `HP` / `GOLD` / `GAMES`, which is how the Golden Idol charges 25% of
Max Health and still prints "-3 Health" on the button. So one authored group is a
whole ladder:

```
Linger        Again   needs Immerse > 0; gain_max_hp 1; lose_hp {4+X}     4, then 5, then 6…
Deeper        Again   lose_hp {2+X}; chance {35+10*X}% -> gain_chest small 1
```

Arithmetic is evaluated at press time, so the button can print what *this* press
costs ("−3 Health · 55%: +1 Small Chest") and the player never sees the formula.

A **staged** event is `Stay` plus a `needs <Choice>` gate: the first press spends
itself and reveals a different button. Abyssal Baths (Immerse → Linger) and
Scrap Ooze (Reach Inside → Deeper) are both built that way.

### Art

Drop a PNG in `images2.0/events/` named after the `Image` column — PascalCase,
like the rest (`ScrapOoze.png`). Portrait suits the modal's left column best. The
generator prints a `!` warning if the art is missing; the event still works.

Where the picture goes depends on the `Prompt`. With prose, it stands in a fixed
column to the LEFT of the words and buttons, costing no vertical room. With a
BLANK prompt — the Arcade Room — there is no page of words for it to sit beside,
so the modal stacks: art on top, centred and height-capped, choices under it. The
shape is chosen when the modal opens and does not change if a `Result` prints
later.

### Seeing it in the game

**Use the dev panel's Events tab.** Turn on dev mode in Settings, press `` ` ``
in a run, and open **Events**. Every authored event is listed, and each row
carries the thing that is otherwise invisible — *why it is or isn't turning up
where you stand*:

```
Scrap Ooze    (3 choices)    ✓ eligible here
Unrest Site   (2 choices)    ✗ not a dead end, needs Health <= 70%
Punch Off     (2 choices)    ✗ used 1/1 this run
```

Clicking a row **starts it right there**, blockers and all — the one you can't
reach is exactly the one you need to look at. It goes through the same path an
earned event takes, so the modal, the `finished` handling and a `play_game`
detour all behave as they will in a real run (which also means starting one puts
it in the bag — there's an **Empty the bag** button for that, and an **Un-spend
this node** one for the game you are standing on).

Why it's needed: an event you cannot get to tells you nothing about which gate
stopped it, and waiting for the bag to deal you the one you are editing is not a
workflow. Every row prints its blockers straight from `EventSystem.blockers_for`
— the same call the dealer makes.

The tab also **spawns objects**. Objects are only spawned by events today, so
without that button the under-board panel — the whole non-event half of how a
machine reaches the screen — would have nothing that could reach it.

The panel is the fast path; driving
`EventModal2.open(host, Data.get_event2(&"your_event"))` from a throwaway scene
with the `verify` skill (`.claude/skills/verify/`) still works and will
screenshot it.

### Rules of thumb

- **Worth well under one game's reward.** One fires after every game now, so a
  6–12 game run sees 6–12 of them; anything that would be a fair payout for a
  two-game detour is, at this cadence, the run's main income.
- **Health is 5–10, not 75.** A source game's damage numbers almost never come
  across unscaled; 3 damage is a third of a character here.
- **Be careful with events that can kill you.** They no longer sit at the end of
  a detour the player chose to walk; they turn up after any game at all.
- **Quote the source game verbatim** where you can, and leave a `Result` blank
  rather than inventing prose and presenting it as the game's.
- **Don't run `tools/oneshots/_events2_sheet_setup.py`** once you've authored by hand. It
  is the bootstrap that laid the tab down and it rewrites it wholesale from a
  Python list; it will refuse rather than drop your rows, but it has nothing you
  want. The same goes for `tools/oneshots/_objects2_sheet_setup.py`.

## Authoring an object

An **object** is a machine you stand in front of — the Blood Donation Machine,
the Donation Machine. Same authored shape as an event (one row on the
**`objects2.0` tab**, choices in numbered column groups, Effect cells in the same
DSL), differing in that it **persists** while the run is on that game, is
**spawned** rather than arriving on its own, and is **stateful**.

```bash
python3 tools/generate_object2_tres.py --list   # dry run
python3 tools/generate_object2_tres.py          # write data/objects2.0/*.tres
```

Full format spec, the eight object-only verbs, and the two authored machines:
[`docs/object-sheet-authoring.md`](object-sheet-authoring.md).

`tools/` carries a `.gdignore`, which keeps Godot from importing the working
files in there. Without it the editor rasterises `RoguelikeMap.svg` — a
133,638 × 51,748 px canvas — into a clamped 16384² texture on every fresh import.

See `docs/architecture.md` (the `Stats` autoload and its Luck section) for how stats resolve; `docs/archive/stat-dispatcher.md` is the combat-era design it began as.
