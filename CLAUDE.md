# CLAUDE.md

Godot 4.6 project at the repository root (`project.godot` is here, so `res://x`
is `./x`). A roguelike played on a graph of real video games: each node is a real
game, and the "combat" is you going off and actually playing it, reported back on
the honour system.

## Orientation — read in this order

| you need | read |
|---|---|
| the rules as a player sees them | `docs/rules.md` — **generated** from the in-game manual (`HowToPlayText.gd`) by `tools/dump_rules_doc.gd`; never edit it by hand, `test_rules_doc.gd` fails when it is stale. Change the manual, then regenerate |
| how the current build works | `docs/games-first-redesign.md` — **the canonical spec**, referenced from 25 places |
| what the project is, repo layout, which doc to read | `README.md` — a short front door with the docs map (split on 20 Oct 2026) |
| autoloads, every screen, the window, data loading, Luck, code conventions | `docs/architecture.md` (was most of the README) |
| the OBS overlay, scene layouts, the speedrun clock | `docs/streaming.md` |
| art folders, the generators, authoring events and objects | `docs/content-authoring.md` |
| **what fires first** in a game — the ground or the swing, a kill's gold or `enemy_killed`, `game_beaten` or the game's own loot | `docs/turn-order.md`: picking a game, a lost run's turn, the report's steps, the screens after, and the kill and hit chains. **It is checked**: each section ends in an ` ```order ` block of source snippets that `tools/check_turn_order.py` (CI) holds to the code's order. Moving, adding or removing a step in any function it names means updating that section's prose and block in the same commit. A new signal or report step goes in too — the check can't see a step the doc has never named |
| the end-of-session Camp — Rest or one card dealt by a game beaten since the last camp | `docs/rest-site-design.md`; rules in `scripts/runtime/Camp.gd`, screen `CampScreen.gd`, tests `test_camp.gd` |
| locations — dealt at the start and at every difficulty up, no goal, no choice; what they do, the tag lean (`Locations.pick` sits in every roll a tag means anything to) and the blocking poops | `docs/locations-design.md`; rules `scripts/runtime/Locations.gd`, state `GameLoop2.location_*`, sheet `locations` → `tools/generate_location_tres.py`, tests `test_locations.gd`. The suite runs with the roster EMPTY (`test/pre_run_hook.gd`) |
| what changed and why | `CHANGELOG.md` — narrative history, not needed to make a change |
| what is known-slow and not yet fixed | `docs/performance-backlog.md` — measured findings with the fix for each. The Events tab and the page's cold compile are fixed; `GameLoop2.gd` has been measured and is cheap. What stays useful is the method: `Overworld2.gd` carries a seam table re-measured rather than guessed, and `test_page_load.gd` keeps the screens a run only opens on demand out of the page's compile |
| what the layout pass left open | `docs/layout-review-backlog.md` — all eight items closed. Fonts and gaps are both on `UITheme`'s scales project-wide, with `test_design_tokens.gd` asserting both lists complete and no value off the scale. All of it stays in the doc with its reasoning so none of it gets re-litigated. Two standing notes in it are worth reading before touching any UI: judge colour by sampling the rendered pixel rather than by eye off a screenshot (that produced one confidently wrong finding), and use the `verify` skill to look at a screen rather than reasoning about it |
| trinkets, passive cards, bags, weapons, and why WHERE a piece sits in the pack matters | `docs/loot-passives.md` — the sixth loot kind, Blueprint's neighbour rule (it copies ANY loot, usable pieces included), the five hooks it added, the coin-chain rule and the trigger toast; §6 is BAGS, the seventh kind, which give the pack its shape (slots are numbered by which bag owns the cell, so a bag's contents ride along when it moves); §10 is pieces BIGGER than one cell (one index on several slots, anchored at the lowest); §11 is food, which counts CHARGES (a defeated enemy is one; anything that charges loot is another); §12 is WEAPONS, the eighth kind — aimed like a thrown potion, charged once per game by their own goal; §13 is evolutions; §14 the hover glow; §15 Link Cable, which makes every piece touch every other — a new neighbour rule has to ask `LootPassives.linked()` too; §16 Smelter, which takes a passive piece out of the pack and keeps it working from the shelf |
| **research of any kind** — influences, tags, and what each game's enemies, items, events, characters, statuses and places could give this one | `docs/research.md`: eight kinds, one entry point (`tools/research.py`), candidates in `research/<kind>.csv`, reviewed by the owner in `tools/Research.xlsx` (a sheet per kind, `Owner` yes/no), one ledger (`research/ledger.json`) and each game's wiki (`research/wikis.json`). **If the owner has uploaded `Research.xlsx`, run `python3 tools/research.py sync` before anything else** or their ticks are overwritten by the next build. Nothing reaches `Roguelikes.xlsx` until the owner has said yes |
| finding influences missing from the chart | `docs/influence-research.md`: the method, what counts as a source (first-hand only), which sources paid off, and the traps. `tools/influence_research.py` does the scanning. Candidates found so far are rows of `research/connections.csv`, and **nothing from it goes into `connections` until the owner has ticked it**. Interviews and podcasts for the owner to listen to (nobody else can) are in `docs/influence-media.md` |
| which games should carry which tags | `tools/tag_research.py` writes **suggestions** into `tools/Research.xlsx` (its own workbook, not `Roguelikes.xlsx`) from each game's Steam tags, store text and title, with the evidence beside each one. **Never type a tag into the `games` sheet yourself**: the owner reads the sheet and does that. Its `Owner` column (yes/no) survives a rerun. The owner can also tag games **in game** (the Collection's game page and the run map's game card, `GameTags` + `TagEditor`); those edits count at once and reach the sheet only through Settings → Game tags → *Export tags for all games* → `tools/tag_edits.json` → `python3 tools/apply_tag_edits.py` (see the porting steps below) |
| rifts (all four build steps done; key sources in items and loot are the owner's) | `docs/rifts-design.md` — per-run rift games that pull off-map games into the map without ever shortening a path; path rifts on the start routes, world rifts on weak spots, Rift Keys that fill empty offering slots with rift cards, and the measured effect on the Amulet pool |
| Fractures — the ten difficulty levels above a normal run, unlocked per character (designed, not yet built) | `docs/fracture-design.md` — the ladder, what each level touches, the XP and trophy rules, and Fracture 10's Collapse: carry the Amulet back to the start over a map whose played games have all been transmuted |
| Roguelike Radio — the player's own music, unlocked per game, played into OBS | `docs/roguelike-radio.md`: the `radio` sheet, the unlock rules, why the game keeps the clock, the one-speaker rule, `radio.html` |
| combat-era designs | `docs/archive/` — **describes systems that no longer exist**; see its README before trusting a path or class name |

## The shape of it

- **The main menu has a moving background.** `MenuFallingArt` drops enemies,
  items, loot and game covers across the whole screen, dimmed to `BAND_DIM` behind
  the button column (`_band_dim`) so the buttons still read. Four things to
  know before touching it: a texture filter belongs to the CanvasItem, so the
  pieces are split across two draw layers (NEAREST for pixel art, LINEAR for the
  rest); art is only used if `_is_cutout` says so — `wands_unidentified/` is RGBA
  with every pixel opaque, and falls as teal tiles otherwise; **enemies come from
  `GoalEnemyData`, not from `images2.0/enemies/`**, because the resource carries
  the battlefield footprint that sizes them and the folder does not; and a pool
  entry is handed out off a free list so one picture cannot be on screen twice.
  Toggle and amount (pieces on screen, default 150) live in Settings under Display.
- **Two scenes only.** `scenes/menu/MainMenu.tscn` boots, `scenes/redesign2/Overworld2.tscn`
  *is* the game — and **`Overworld2.tscn` is one node and a script**, so don't go
  looking for the game's UI in it; every screen past the menu is built in code.
  `MainMenu.tscn` is the exception and always was: it lays out its 20 nodes (the
  title, the eight buttons, the save list) in the editor like an ordinary scene.
- **29 autoloads** in `scripts/autoload/`, registered in `project.godot`. The ones
  that matter most: `GameState` (run-persistent state), `Data` (loads every
  `.tres` and serves it by id), `GameLoop2` (the run loop — `Overworld2` is a view
  over it), `EffectSystem` + `TriggerBus` (effect dispatch and the signal hub).
  `docs/architecture.md`'s "Autoload singletons" table covers all 29. Count them with
  `sed -n '/^\[autoload\]/,/^\[/p' project.godot | grep -c '=\"\*res://'` rather
  than trusting this line — it has been wrong before.
- **Content is data, never code.** Everything lives as typed `.tres` under `data/`,
  with schemas in `scripts/resources/`. Gameplay code asks `Data` for content
  rather than hardcoding it.
- **The spreadsheet is upstream of `data/`.** `tools/Roguelikes.xlsx` drives the
  `tools/generate_*.py` and `tools/import-*.py` generators. Edit the sheet and
  regenerate; don't hand-edit generated `.tres` in bulk. If you change the shape
  a `.tres` is written in, **update the generator in the same commit** or the next
  regeneration silently reverts you.
  **…and the `goals` sheet is upstream of six of its own sheets.** Every goal in
  the game is authored there, in one sorted list, and
  `python3 tools/apply_goals_sheet.py` writes it out into `enemies`, `bosses`,
  `characters` (`Level Up`), `curses` (`Condition`), `statuses` (spliced back
  into the `On Player` prose) and `weapons` (`Goal` — always `any time`, since a
  weapon's goal charges it even in a lost game). So a goal is edited in `goals` and NOWHERE ELSE —
  anything typed into an owner sheet's goal column is lost on the next push, the
  same rule `data/` lives under. `--check` runs in CI. It went that way round
  because the reverse (a generated view) made a one-pass rewrite of 34 goals
  possible and then stood in the way of keeping it; the script's docstring has
  the argument. Two columns live only in `goals` + `enemies`/`bosses`: `Ticked`
  (`any time` / `game beaten`) and `Count` (blank, or 2+) — see §7.7 of the spec.
  **Never edit the workbook with openpyxl** — a round-trip drops its eight charts.
  `tools/_xlsx_surgery.py` rewrites one sheet's XML and copies every other zip
  entry through byte-for-byte; the `_*_setup.py` one-shots beside it are the
  worked examples. Note the sheet names lost their `2.0` suffixes (`enemies2.0` →
  `enemies`, and so on); the output folders did not move.

## Working here

**The workbook comes first in every upload.** When the owner uploads, assume
`tools/Roguelikes.xlsx` has already been updated before anything else (images,
proof clips, music lists): fetch `main`, diff the sheet against the last commit
sheet by sheet, run `python3 tools/apply_goals_sheet.py --check`,
`python3 tools/check_data_sync.py` and `python3 tools/map_calc.py --check`, and
regenerate, then wire up the art. `map_calc.py` (no flag) rewrites `Map Calc`
and `Map Analysis`'s formulas; they read rows as `INDEX(games!$A:$A,ROW())`, which
no delete, insert or sort in `games` or `connections` can turn into `#REF!` (a
row-by-row `games!$A933` broke the dashboard three times). Its "on the map"
figures match `RunGraph`'s main group, and `--check` says when they can't. An
owner edit typed into an owner sheet's goal column (as Stumpy Stump's was, 14 Oct)
is carried up into `goals` rather than reverted; see
`tools/_goals_stumpy_stump_wording.py`.

**Porting games from the owner's upload is several jobs, not one.** After
`import-games-godot.py` (which prints the games still waiting), every kind of
research runs over the new games (`docs/research.md` §7 has the detail):

1. `python3 tools/research.py new` runs every scripted pass over just the games
   with no entry in `research/ledger.json`: the influence scans
   (`influence_research.py new`, into `.influence_work/new_games.md`), the tag
   suggestions (`tag_research.py`), each game's wiki, and a brief per game in
   `.research_work/briefs/`. It prints the hand work left.
2. **Connections:** read every line of `.influence_work/new_games.md`, then do
   the hand half the script can't: a web search per game for an interview, a
   devlog or a press release in the developer's own words, and an X search
   with **both** "inspiration" and "inspired" (the brief links them; search
   engines don't stem tweets, and "inspiration" is the one that found Enter the
   Chronosphere's). What holds up goes
   in `research/connections.csv` (`to review` for a pair of chart games, `lead`
   for a roguelike the chart lacks, `nothing found` for a game searched with
   nothing found), **never** into `connections`. **Also the developer's other
   roguelikes:** `new_games.md`'s *The developer's other games* lists every
   Steam game by the same developer; one on the chart and not connected is a
   `to review` row with Dev/Series `yes`, a roguelike off the chart a `lead`
   (by hand for a game off Steam). Then
   `python3 tools/influence_research.py new --mark`.
3. **Goals, loot (always including weapons and evolutions), events,
   characters, statuses, locations:** read each new game's brief and the wiki
   pages it lists, write candidate rows into
   `research/<kind>.csv` by the rules in `docs/research.md` §6, then
   `python3 tools/research.py mark <kind> <game> --note "..."` for EVERY kind,
   rows or not, so "nothing usable" is on record.
4. `python3 tools/research.py check && python3 tools/check_goal_candidates.py &&
   python3 tools/research.py build` (the middle one also holds every weapon to a
   goal no other game's goal repeats), and
   commit the CSVs, the ledger, `research/wikis.json` and `tools/Research.xlsx`
   together.
5. If the upload includes `tools/tag_edits.json` (tags the owner edited in game
   and exported), run `python3 tools/apply_tag_edits.py`, which writes them into
   the `games` sheet's Tags column and re-imports, then delete the JSON in the
   same commit. Unlike tag *suggestions*, these are the owner's own decisions.

Do all of them without being asked. The owner asked for the research to happen
every time games are added, for every kind.

**When the owner says they uploaded a proof clip (an `.mp4` in
`images2.0/proof/`)**, turn it into what the game plays and get rid of the MP4,
without being asked twice:

1. If its name isn't in the proof format, `python3 tools/proof_owner_match.py`
   (then `--write`, or `--pair`) renames it. The format is the influencers' ids
   joined by ONE hyphen, then `---`, then the influenced game's id —
   `balatro-inscryption---black_jacket.mp4` is one clip proving two connections.
   The `Proof` column of the `connections` sheet has the name for every row.
2. `python3 tools/convert_proof_videos.py` writes `<name>.ogv` and
   `<name>.poster.jpg`, checks the `.ogv` runs as long as the MP4, and **deletes
   the MP4**. It refuses (and keeps the upload) when an id isn't a game, a pair
   isn't a connection, or the name is over 150 characters.
3. `python3 tools/proof_column.py`, then commit the `.ogv`, the poster, the
   MP4's deletion and `tools/Roguelikes.xlsx` together.

The MP4 stays in git history from the upload commit itself: deleting it shrinks
the checkout, not what a full clone downloads.

```bash
tools/gut.sh test_gameloop2            # ONE file, ~5 s (test_overworld2 is the slow one: 10+ min)
tools/gut.sh test_overworld2 crash     # only the tests in it whose name contains "crash"
tools/gut.sh                           # the whole suite: 63 scripts, ~3130 tests, ~25 min
python3 tools/outline.py scripts/redesign2/Overworld2.gd --grep stun   # a file's sections + funcs, with lines
```

- **Run one file, not the suite, while working.** `-gtest=` on its own does NOT
  narrow a run here: `.gutconfig.json` names `res://test/` and GUT adds the file on
  top of it, so `godot ... -gtest=res://test/test_x.gd` quietly runs all ~3,100
  tests. `tools/gut.sh` passes `-gconfig=` to drop the directory and hands the
  pre-run hook back by hand. Run the full suite once, before pushing.
- **Shared test helpers live in `test/helpers/`, so use them rather than writing
  another copy.** `run_page.gd` (`const Page := preload(...)`) builds the game page
  and stands it where a test wants it: `Page.build(self)`, `Page.play_opening(_ui)`,
  `Page.open_at_first_offering(_ui)` (the opening played out, its event closed and
  its escort taken off), `report_beat`, `pick_enemies`, `leave_post_game`,
  `text_of`. `fixtures.gd` holds the small ones: `choose_solo`, `body`, `park`,
  `trinket(self, …)`, `give(self, …)`, `rng(seed)`. Each was copied into two to six
  files before it was shared; a fix to how a test stands on the page now lands in
  every file at once. Not named `test_*`, so GUT does not run them.
- **Find your way into a big script with `tools/outline.py` before reading it.**
  `GameLoop2.gd` (8.4k lines) and `Overworld2.gd` (7.7k) are about 45% comments
  and are cut into `# --- section ---` blocks; the outline lists each block's line
  range and members, so a Read can start at the right line instead of a grep
  landing on a name with no context.

- Godot is at `/root/.local/godot/godot` and on `PATH` (installed by
  `.claude/hooks/session-start.sh` in remote sessions).
- **A new `class_name` needs an editor rescan before the suite can see it.**
  `.godot/global_script_class_cache.cfg` is gitignored and only regenerates when
  the editor scans, so a headless test run against a fresh `class_name` fails
  with "Could not find type X" — in hundreds of unrelated tests, because the
  script that referenced it failed to parse and its scene fell back to a bare
  Control. Run `godot --headless --editor --quit` once after adding one.
- **A skipped case is `pending("why")`, never a bare `return`.** ~250 tests guard
  themselves against a run that did not reach their case (`if pin == &"":`,
  `if _ui._fulfil_checks.is_empty():`, `if not view.has_layout():`). They used to
  bail in silence — and GUT only reports Risky when a test asserts **nothing at
  all**, so a test that asserted once and then bailed reported green while testing
  nothing it was written for. There was no way to tell "2092 passing" from "1997
  passing and 95 shrugging". Every one of those guards now calls `pending()` with
  the reason first, which GUT counts separately and prints as **Risky/Pending** in
  the totals: the skips are a number you can watch. Read it as a budget, not as
  noise — a guard that fires often is a case the suite has stopped covering, and
  the fix is to ARRANGE the state (`_stand_at_hops`, `_reboot`, `_disarm_board`)
  rather than to hope for it.
- **A GUT run should be all green, with no Risky / "Did not assert"** — with no
  known exceptions any more. It used to
  report one or two, varying between runs, because a couple of tests early-
  `return`ed when the run's random graph didn't reach the case they were about.
  Both are fixed: `test_atlas.gd::test_path_taken_follows_the_order_the_games_were_visited`
  now walks the graph's own edges (revisits included) so a history always exists,
  and `test_run_map.gd::test_the_route_fits_the_window_it_opens_in` asserts the
  *other* branch — the fit bottoming out at the legibility floor — rather than
  asserting nothing. If a Risky turns up, it is a new one; find out which case
  stopped being reachable rather than assuming it is noise.
- **A test that stands a body on the front line and expects a swing is a flake
  waiting to happen.** The offering rolls a RANDOM enemy, and since §7.6 an
  ability can spend a body's whole turn on something other than you (Ritual,
  Defensive Stance, either spawner, a thief's getaway) or add a body to the board
  mid-turn. `test_overworld2` has `_disarm_board()` / `_front_line()` for exactly
  this, and `test_statuses` does it inline. Tests about the SCREEN should disarm;
  `test_enemy_abilities.gd` is where abilities are the subject.
- **A failure that comes and goes is an assertion that is only USUALLY true.**
  Every intermittent this suite has had was one, and `docs/test-flakes.md` has
  each with how it was found — read it before blaming a seed. The usual suspects:
  the random offering stands a BOSS about one run in seven, the road stands
  bodies up at the end of ANY game (`pressure()`), two bodies can swap enemies in
  one re-roll, and
  a WIDTH that varies upstream of a text wrap. Find which case stopped being
  reachable with a stress loop that prints the state on failure.
- **TWO ENEMY OBJECTS CAN SHARE ONE ID, so compare bodies by `id` and never by
  object.** A body's `enemy` is normally Data's own shared resource, and that made
  `==` look safe for years. It is not: `test_overworld2`'s `_plain_goals` (inside
  `_disarm_board`) hands a body a `duplicate()` of its enemy to strip a goal's
  `ticked` and `count`, which it must do for the 21 of 111 bodies authored as
  `game beaten` or counted. An identity check against such a body is false for an
  enemy that IS that enemy. This cost two intermittents and three wrong
  hypotheses; `_pick_by_type_tier`'s `exclude` and both `fresh == old` guards now
  compare ids, which is what "the same enemy" meant in the first place.
- **The suite runs with STARTING GEAR OFF.** `test/pre_run_hook.gd` (wired in
  `.gutconfig.json`) sets `GameState.start_gear_enabled = false`, because the kit
  rides the genre of whichever start a test picks and `choose_start(0)` is a
  random genre: on, it put an item chest over the board or a weapon's goal on the
  checklist in 8 unrelated `test_overworld2` tests. A test ABOUT the kit turns it
  on and back off, as `test_start_panel.gd` does.
- The leaked-RID / orphan warnings at the end of a GUT run are also pre-existing
  noise from UI tests that build Controls.
- To see a change on screen rather than in assertions, use the `verify` skill
  (`.claude/skills/verify/`) — Xvfb + a temporary driver scene.
- **The docs are the navigation layer, so a dead pointer in one is a real bug.**
  `python3 tools/check_doc_paths.py` checks that every repo path named in a live
  doc exists. Seventeen had rotted before it was written, all from the same two
  renames the project has already done (the `2.0` migration and the combat →
  games-first cut) with the prose left behind — including two whole documents that
  described retired systems while sitting in the live `docs/` folder. The paths
  that are missing ON PURPOSE are listed in the script with the reason;
  add to that list rather than deleting a sentence that means what it says.
- **`data/` drifts from the sheet, and now something says so.**
  `python3 tools/check_data_sync.py` runs every generator over the checked-in
  workbook, asks git whether anything moved, and restores the tree. Its first run
  found three rows that had been shipping wrong for weeks — and, tellingly, they
  had drifted in BOTH directions (the sheet was ahead on two, the `.tres` on one),
  so "which side is right" needed archaeology in the changelog rather than a rule.
  Run it before pushing a content change; CI runs it on every push. A sheet row
  part-way through being authored goes in the script's `KNOWN_UNFINISHED` list
  with its reason, the way `check_doc_paths.py` lists its deliberate exceptions.
- **CI runs all of this** (`.github/workflows/ci.yml`): GUT, `check_doc_paths`,
  `check_turn_order`, `check_data_sync`, `map_calc --check`, `check_map_sync` (informational — it drifts in both
  directions by design) and `check_overlay.js`. Three jobs, so a red build says
  which KIND of thing broke — the game, the content pipeline, or the browser page
  GUT cannot see. The engine version is pinned there and in
  `.claude/hooks/session-start.sh`; keep the two the same as `project.godot`.
- **GUT cannot see the OBS overlay, because the overlay is a browser page.**
  `test_obs_companion.gd` pins the payload and stops at the file; everything past
  it — whether `hidden` hides, whether the road actually scrolls, whether a burst
  of toasts stays inside the browser source, how tall the page really is — needs
  `node tools/check_overlay.js`, which renders `obs/overlay.html` in headless
  Chromium and asserts all of it. Run it whenever anything under `obs/` changes;
  every check in it is a regression that shipped once. It needs
  `npm install playwright-core` and a Chromium (`--browser=` or `$CHROMIUM_PATH`
  if it cannot find one).

## Things that will bite you

- **`project.godot` comments are `;`, not `#`.** A `#` line is parsed as part of
  the NEXT key. This already silently renamed the `backpack` input action once;
  `test/test_collection.gd` now guards against it.
- **A new key on an enemy body goes in `GameLoop2.BODY_KEYS` too.** A body on the
  board is a bare `Dictionary`, and reads are `entry.get(k, default)` by design —
  a body from an older save legitimately lacks the newer keys. The cost is that a
  mistyped WRITE (`entry["revive"]` for `revives`) is silent forever: the key
  nothing reads is written, the real one keeps answering its default, and the
  symptom is a content bug three files away. `BODY_KEYS` is the list, `_check_body`
  compares against it on every spawn and load, and `_check_stack` sweeps the whole
  board at the end of each turn and each game — so a stray key from ANY of the ~49
  write sites is caught without those sites being touched. Debug builds only. The
  report names the key, the site, and the legal key it is one edit from.
  **This was written because the contract had already drifted**: the comment above
  `stack` listed 16 keys where the code used 19, and two of the three it had lost
  are written by `_add_to_grid`, the one constructor, in the same file.
- **A `class_name` that shadows a NATIVE Godot class is a parse error**, and it
  takes down every `.tres` that names the script — `Data` then loads that whole
  folder as zero rows and the failure surfaces hundreds of tests away as missing
  content. `tiles2.0`'s resource is `TileEffectData` for exactly this reason:
  Godot already ships a `TileData` for TileMaps. Check a new name with
  `godot --headless --check-only --script scripts/resources/<New>.gd` before
  wiring it up — it says "hides a native class" in one line.
- **Game covers load lazily.** `GameData.cover_path` holds the path and
  `GameData.cover_image` loads it on first read. Do **not** turn `cover_image`
  back into an `@export var ... : Texture2D` — `Data` loads all 927 games at
  startup and an ExtResource resolves eagerly, which meant decoding ~206 MB of
  PNG on every boot and every headless test run (~5.2s of a ~5.7s startup).
- **`data/games/` has 927 files.** Never glob or read it wholesale to answer a
  question; query it with `grep` for the field you care about.
- **The repo tracks source only.** `.godot/`, `*.import`, `*.uid` and
  `export_presets.cfg` are gitignored and regenerate. They show up in local file
  listings and are not part of the project.
- Art filenames are **PascalCase**, matched to content ids by convention. **Pill
  capsules are the exception**: `images2.0/pills/` is matched to pills by the RUN
  (`PillSystem.COLORS` deals 10 of the 13 per run and leaves 3 meaning nothing),
  so a new colour has to be added to that const list as well as to the folder, in
  both `<Colour>.png` and `<Colour>Horse.png`. `test_pill_system.gd` checks the
  list against the folder in one direction only — art that ships without being
  listed is art no run can ever show.
- **A new UI glyph needs `tools/build_glyph_font.py` re-run.** The UI is drawn out
  of ~70 symbols (⚔ ☠ ⚡ 🏆 …) and Godot's built-in font has two of them; the rest
  are shipped as subsetted Noto fonts in `fonts/`, chained onto the theme font by
  `UITheme.glyph_font`. A glyph that isn't in them still renders — the chain ends
  in a system-searching font — but it costs ~2 ms of host font search every time
  a Label carrying it is created, which is what shipping them was for.
  `test_display_settings.gd` fails if the source uses one the fonts don't have.
  **Rebuilding is two steps**: run the script, then `godot --headless --editor --quit`
  so Godot re-imports the changed `.ttf`s — until it does, the new glyph is on disk
  and the test still fails, which reads exactly like the script not having worked.
  It also needs `pip install fonttools brotli` and network access to fontsource.
  If you ever swap a font in there, its **vertical metrics must stay on the base
  font's em grid** (4096 upem, ascender 4378, descender 1200): Godot takes a
  font's height as the max over the whole fallback chain, so a taller subset makes
  every line in the game taller and the 720p fit tests fail 63px over.
