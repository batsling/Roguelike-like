# Changelog

Newest first. This is the running narrative of what changed in the build and
why — it was the README's `## Recent changes` section until it grew to two
thirds of the README, at which point everyone reading the README to learn how
the project *works* was paying for it.

For how the project is laid out and how its systems fit together, see
[`README.md`](README.md); for the canonical spec of the current build, see
[`docs/games-first-redesign.md`](docs/games-first-redesign.md).

---

- **Statuses where you fight, items you can read, and a dev panel worth opening.**
  Four changes, all about seeing what the run is doing to you.

  **Statuses are on the board now.** The player's draw as art pips between the
  hero's portrait and their health — tries / who you are / what is riding you /
  what is left of you, top to bottom. An enemy's draw *below* its box, under the
  ❤/⚔ row. Those two badges were printed over the middle of the art at full size
  and were covering the enemy you were trying to recognise, so they are smaller
  now and sit straddling the box's bottom edge, leaving the picture the whole
  cell. Every pip carries the full hover text, built in one place
  (`StatusData.tooltip_for`) so the board, the enemy card and the HUD chip cannot
  drift apart: name and stack count, what that side DOES, the live line at that
  stack, and whether it decays. The enemy card grew a proper status row too — art,
  name, and the clause spelled out rather than left to a hover, since the card is
  where you have already stopped to read.

  **The pack separates reading from spending.** Clicking an item's tile opens an
  ItemInfoCard — big art, description, rarity / behaviour-class / charge / source
  chips, tags, and a Use button when it can fire. Firing now lives *above* the
  tile instead of on it: a Usable item gets a Use button, and a charged item gets
  a battery — one rectangle per charge, filling left to right, Isaac's active bar
  turned on its side — which becomes that same Use button at full. So the strip
  answers "how long until I can" and "can I now" in the same pixels, and
  inspecting an item can no longer spend a charge by mis-clicking it.

  **The dev panel is rebuilt** from three grant lists into four tabs. GRANT:
  items, scrolls, and statuses with a player / current / all / random target
  picker and a stack count, listing each status's mode on the side it is about to
  land on. RUN: vitals, every board verb, gold, banked chests, level, and games
  played (the difficulty tier is derived from it, so the panel moves the count
  rather than pretending the tier is a field). BOARD: spawn any goal-enemy or
  boss, and per standing body — by instance id — stun / push / bomb / defeat /
  remove, or hang a status on it. FLOW: jump to any game, heal, clear the board,
  force the win or the loss. Everything routes through the same public API the
  game uses, so the panel cannot drift into testing a path nothing else takes;
  three small public methods were added for the ones it needed
  (`GameLoop2.despawn` / `apply_status_to`, `Overworld2.travel_to_game`,
  `GameState.verb_value`). It also had two plain bugs: it built its layer visible
  and then flipped it, so the first `` ` `` press did nothing and only the second
  opened it, and its panel had no opaque background, so the whole overworld read
  straight through the tool you were using.

  `test_run_history.test_newest_run_comes_first` was asserting run ordering by
  comparing the two runs' PATHS. `_walk` follows an unseeded start roll and stops
  at the first dead end, so two runs can honestly walk the same route — the test
  failed perhaps one run in ten for a reason that had nothing to do with ordering.
  It now asserts on the outcomes, which is what it was actually testing.

- **Statuses 2.0: two sides, authored independently.** The first cut derived both
  halves of a status from one shared Condition + Reward, with Buff/Debuff deciding
  which behaviour each half got. That made the interesting cases unauthorable, so
  the sheet now carries an **`On Player Effect`** and an **`On Enemy Effect`**
  column, one per prose cell, and each names what that side DOES:

      <verb> "<condition>" [decay] [-> <reward>; <reward>; …]

  `goal` is a standing objective of the holder's own that pays when met; `clause`
  is ANDed onto goals and required; `bonus` is optional and claimable. `decay`
  sheds a stack on completion. Because the verb carries the behaviour, **Buff /
  Debuff drives no mechanic at all** — it is the HUD tint and the collection
  filter, nothing more. Marked is the case that motivated it: a `clause` with
  `decay` on the player and a paying `bonus` on the enemy, which one shared
  condition could only ever half-express. A `clause` may not carry a reward (it is
  a requirement, not a payout) and the generator rejects one rather than dropping
  it quietly; either side may be blank, which reads as inert.

  **Fractional time windows now read as time.** An `{expr}` hole can carry a
  format, and `{1+(1/2)^(X-2):hours}` renders as "1 hour 30 minutes" instead of
  "1.5 hours" — a window is something the player holds against a clock, not
  arithmetic to do mid-run. Rounded to the nearest minute, so Dexterity at five
  stacks reads "1 hour 8 minutes" rather than "1 hour 7.5 minutes".

  **Two relics hand statuses out**, the Slay the Spire pair that grant these same
  two stats there: **Vajra** is rewritten from "+1 Bash" to **"+1 Strength"**, and
  **Oddly Smooth Stone** is ported in from the legacy `items` sheet as **"+1
  Dexterity"** (art copied to `images2.0/items/`). Both stay `Pickup` items firing
  `item_acquired`, the shape Vajra already had, so the status lands when the relic
  is taken and stays for the run. Vajra was the spec's and README's stock example
  of a passive verb bonus; those references now name what they are actually
  describing instead.

  Condition text also gained `[singular|plural]` markers, so a status reads
  "increased 1 time" at one stack and "increased 3 times" at three rather than
  picking one and being wrong at the other.

  Sheet edits go through a new **`tools/_xlsx_surgery.py`**, which rewrites one
  sheet's two XML parts and copies every other zip entry through byte-for-byte —
  an openpyxl round-trip of this workbook silently drops its seven charts. It
  resolves a sheet's part BY NAME through the rels, because the number in
  `sheetN.xml` is not the sheet's rId (`items2.0` is rId4 and lives in sheet4.xml
  only by coincidence) and guessing that mapping is how you edit the wrong sheet.

- **Statuses 2.0 — balance by rewriting goals** (`statuses2.0`, spec §13). The run
  had no lever between "an item that grants a number" and "an enemy with a harder
  goal", so a location or an event had nothing to reach for. A **status** is that
  lever, and it works on the only currency the game has: it bolts a **clause onto
  a goal**. One status is authored as two pieces — a `Condition` and a `Reward` —
  and the four ways they can be arranged *are* the system. **A buff on the player**
  is an extra standing goal on the checklist ("If the difficulty is increased 2
  times, gain +2 Small Chests, +2 Bashes") that pays out every game you satisfy it.
  **A buff on an enemy** welds "and ‹condition›" onto that enemy's goal — required,
  so it is harder to remove. **A debuff on the player** welds its clause onto
  *every* enemy's goal and sheds a stack each game you complete one. **A debuff on
  an enemy** hangs an optional bonus off it — "and if you get 3 achievements, gain
  +3 Small Chests" — claimable for the reward. So a buff pays you and taxes the
  enemy; a debuff taxes you and pays out on the enemy, and each direction has its
  own counter. Three statuses ship: **Strength** and **Dexterity** (buffs, Slay the
  Spire) and **Marked** (debuff, Mewgenics). Stacking is **Intensity** — a second
  Marked is one Marked at 2, not two Markeds — and only debuffs decay, once per
  game rather than once per goal, so a game where you cleared four followers can't
  wipe a four-stack debuff whole. A buff persists for the run, because a buff *is*
  the reward and a timer would only make it a worse item.

  The sheet gained two machine-readable columns beside its prose (added by
  `tools/_statuses_sheet_setup.py`, which patches the two XML parts it needs
  instead of round-tripping the workbook through openpyxl and dropping its seven
  charts). `Condition` and `Reward` carry `{expr}` holes over **X**, the stack
  count, so a status can scale on whatever curve it likes: Strength counts a flat
  `{X}` while Dexterity's window is `{1+(1/2)^(X-2)}` hours — 3h at one stack, 2h
  at two, 1.5h at three, tightening toward a floor of one hour while the reward
  grows. `tools/generate_status_tres.py` normalises `a^b` into `pow(a, b)` and
  every integer literal into a float (Godot's `Expression` does integer division,
  so `1/2` was 0 and Dexterity's one-stack window came out as `pow(0, -1)` hours),
  and emits `[singular|plural]` markers the runtime resolves against the live X —
  one authored string reads "+1 Small Chest" and "+3 Small Chests" correctly.

  Runtime: statuses on the player live on `GameState.player_statuses`; statuses on
  an enemy ride the **body**, in the `GameLoop2` stack entry, so one applied to the
  current game's enemy is still on it when it walks onto the board. Both save.
  **`GameLoop2.goal_text_for(entry)` is now THE goal line** — the checklist, the
  enemy card, the scroll target picker and the headless `PlaySession2` driver all
  ask for it rather than reading `GoalEnemyData.goal`, which is only ever the
  unmodified stem. (Collection, the Atlas and the note modal still show the
  authored goal: they describe the enemy, not the run.) Content reaches the system
  through a new **`apply_status`** effect — `apply_status marked 2 target=all` in
  the item Effect DSL, with `player` / `current` / `all` / `random` targeting — and
  the player reports against it through `beat_game`'s new `claims` argument, which
  resolves **before** the board does, so beating an enemy and claiming its bonus in
  the same game pays both. The HUD grew a status strip under its numbers, and the
  report checklist grew the extra goal rows and bonus rows. 40 new tests in
  `test/test_statuses.gd`.

- **12 new games and 21 games' worth of new connections** ported from the
  spreadsheet (An Amazing Wizard, Atomic Owl, Barda, Katanaut, Nadir, Roulette
  Hero, Sandwalkers, Sir We Have an Orc Problem, Sword of the Necromancer and its
  Resurrection, Tiny Auto Knights, Tower Fortress), taking the catalog to 830. All
  five Atlas skies rebaked.

- **A way onward, a way out, and somewhere for a score to land** — three things
  the run was missing. **(1) The hub rule.** On a well-connected game the offering
  shows three of dozens of neighbours, and the seeded subset could come up all
  dead ends: Slay the Spire has 138 connections and 80 of them lead nowhere, so an
  unguarded draw stranded the run there about one time in five. Standing on a game
  with more than `HUB_CONNECTIONS` (20) connections now guarantees at least one
  card with more than `ONWARD_CONNECTIONS` (2) of its own. It takes the LAST slot,
  so it can never displace the reachable amulet, and it only ever offers a
  neighbour that exists — at a small node the thin offering is the honest shape of
  the graph and is left alone. **(2) Escape.** Some games won't go down. After
  `ESCAPE_AFTER_ATTEMPTS` (5) lost runs — past the shields any game grants, so the
  player has been paying Health to keep trying — an **🏃 Escape this game** button
  appears under Completed Game and leaves the game at any time without beating it.
  The BOARD resolves as it does on a missed goal — the goal-enemy walks onto it and
  follows you — and that is the price, paid twice over by the time the button
  shows; it exists to make the way out visible to a stuck player, not to discount
  it. But **an escape is not a beat**: the run doesn't bank the game (so no
  repeat-beat Dash, and the Atlas doesn't mark it), the "after beating a game"
  items don't fire, and neither the run's nor the lifetime beaten tally moves. The
  run clock still advances — the time was spent and the board closed in either
  way. A plain missed *report* still credits the game as it always has; walking
  away is the case that isn't allowed to count. Undoing back under the line takes
  the button away again. **(3) Rating flows into the tier list.** Submitting a score on the
  ★ Rate prompt now opens the tier-list board on top, so the score lands somewhere
  the player can see it and drag it into a row while the game is still fresh.
  "Maybe later" still just closes — declining to rate shouldn't hand you a screen
  you didn't ask for. `TierListScreen` sizes itself the way `Collection` does while
  it's there, which is what it always claimed to do.

- **Six more games, a new character, and a loadout that isn't the same twice** —
  the spreadsheet grew and the build caught up with it. `Roguelikes.xlsx` now
  carries **814 games and 1133 connections** (Into The Grid, Serpent's Gaze,
  TumbleSeed, Dark Light: Survivor, Arc Seed, For The Warp — every one of them
  wired into the influence graph, none an orphan), re-imported through
  `import-games-godot.py` with covers resolved and all five Atlas skies re-baked.
  **Regent** (Slay the Spire 2) joins the roster as the eleventh character, and a
  chunk of the existing roster was re-authored — Ironclad opens on 2 Bash,
  Manager on 2 Push, Minä on 2 Transmute, Zoe on Dash + Push, and several
  level-up conditions and rewards were rewritten (Isaac's now grants a Small
  Chest **and** a Scramble, which the reward parser reads as both).

  The sheet also gained a **Random** column, and with it a starting loadout that
  is not fully known until the run begins: `start_random` is N points spent
  across Bash / Dash / Push / Transmute / Scramble / Bombs when the run starts
  (`GameState.roll_start_random`), one independent roll each, so two points may
  land on the same verb. **Keys is deliberately out of the pool** — it is a verb
  on the sheet but nothing in the build opens with one yet, and a run that rolled
  its whole loadout into Keys would open on nothing at all. Erratic Deck and
  Rodney bring their whole loadout this way; the character screens show it as a
  gold **🎲 N random** pill rather than pretending to know which verbs a run will
  get, and the roll is announced to the toast channel and the run log when it
  happens, because a loadout that differs run to run otherwise just reads as the
  character screen being wrong.

- **The offering and the board on screen at once, and a beat between them** —
  four fixes to the stage, all of them one complaint: you could not see the run.
  **(1)** The offering had a full-width band above the two-column stage, so the
  cards you were choosing between and the enemies closing in on you were a scroll
  apart — the two halves of the same decision, never visible together. It now
  sits in the **left column above the checklist**, beside the board, which costs
  the covers half their size (`COVER_SIZE` 210×280 → 105×140) and buys the whole
  decision in one screen. Every badge row on a card is pinned to a whole number
  of lines, so a title that wraps no longer pushes its cover out of line with the
  rest of the row. **(2)** The board ran off the right edge. Its cell was a
  constant 84px while the grid grows a column per difficulty tier, so a 7×7
  Insane board needed 1395px of a 1280px page and the far columns were simply
  clipped away. The cell is now **fitted to a width budget**
  (`BattlefieldView.fitted_cell`) — full size at 4×4, tighter as the ground opens
  up, never below a readable floor — and the pressure strip and combat toolbar
  **flow** instead of adding their labels up into a minimum the whole panel had
  to honour. The page's scroll is `AUTO` rather than `DISABLED`, so anything that
  ever does overflow stays reachable instead of being cut off. **(3)** The report
  checklist's tick boxes were Godot's stock glyphs — a hairline outline drawn for
  a light editor theme, which against this palette read as an empty gap.
  `UITheme` now **draws its own**: a 24px, 3px-bordered box, gold-rimmed when
  empty and green-filled with a heavy tick when answered, and the whole row goes
  green with it. **(4)** The resolve animation — the only place the run's
  consequences are ever shown — used to hand straight back to the next offering
  the instant the last tween landed. It now hands over to a **Continue button**
  that says what just happened, so the strike and the advance get a beat to be
  read in before the screen moves on.

- **Backward influences are legal, and the completion stats count the whole
  catalog** — three corrections to rules that were stricter than the game is.
  **(1)** `tools/check_map_sync.py` treated any connection pointing at a game
  with an earlier year as an integrity violation. But Year is when a game became
  available to *influence* others, not when it stopped being *developed*, and a
  roguelike is very often a decades-long project — HyperRogue (2012) taking an
  idea from Crypt of the NecroDancer (2015) is a real event. Backward edges are
  now reported for eyeballing (a mistyped year looks identical) rather than
  rejected, and `tools/map_layout.py`, which was silently dropping them along
  with every same-year link, now draws all 1120 connections — the ones that can't
  use the downward comb sweep upward into the older game instead. **(2)** The
  Collection's *Enemies beaten in (x / y)* filtered `y` by game type, on the
  reasoning that an enemy only spawns at a game of its own type — but a survivor
  **follows you across games of every type**, so any enemy can be beaten at any
  game, and both denominators are now the full roster / full catalog. **(3)** The
  report and standing checklists lead with the **goal** and name the enemy after
  it (*"Defeat 10+ spiders — Spider"*), since the goal is the part being read
  for. Stun's wording caught up with the turn ladder too: it costs one **turn**,
  which the scroll and the enemy card now price against the current pace instead
  of promising "skips its next attack".

- **Amulet pressure: the enemies speed up as you close in** — the run had one
  difficulty axis and it ticked on its own, which made routing one-directional:
  the Amulet is the win condition, so every step toward it was strictly good.
  Enemies now take **more turns per game the nearer the Amulet you stand** — 1 at
  five hops or more, 2 at three or four, **3 at two or fewer** — where a turn is
  one action: strike from the front column, or step a column closer. One turn is
  exactly the strike-then-advance the loop always resolved, so the far band is
  the old game unchanged and the near bands are that beat repeated. Route wide
  and you fight a slow stack for more games; bum-rush and you fight a fast one
  for fewer, and the followers on your tail decide which is right. Everything
  else falls out of the same rule rather than being special-cased: an enemy two
  columns back now walks in **and** swings inside one game, a **stun** costs one
  turn (a third of a game at the doorstep, a whole one in the wilds), and
  **fulfilling a follower's goal** holds its fire for every turn of the game, so
  it's worth *more* the harder you push. Alongside it the battlefield now
  **gains a column and a row on every difficulty step** — 4×4 at Low up to 7×7 at
  Insane, on top of any Mine-r Constructions — which is the counterweight: the
  tier that makes the enemies heavier also gives you more ground to lose before
  they arrive. Both halves are on screen before you commit: a colour-coded
  **strip across the top of the board** (`⏱ ENEMY TURNS ×3`, a three-rung ladder,
  the hop count that caused it, and the board's size and tier), a line on **every
  offered card** saying whether taking it speeds the enemies up or slows them
  down, a badge on **each body** reading `×2` swings or `in 2` games with the
  threat colours following that rather than the raw column, freshly-grown cells
  that **light up and pulse**, and a resolve that **plays turn by turn**
  (`TURN 2 / 3`) instead of collapsing into one slide. See §7.4 of
  `docs/games-first-redesign.md`.

- **The Atlas rearranges itself, and grew a year-ringed second layout** — a filter on the
  Collection's Constellations used to dim stars where they stood, leaving the
  survivors scattered across their neighbours' holes. It now hands them to the
  new **`AtlasLayoutBuilder`** — a GDScript port of `tools/bake_atlas.py`'s
  layout half — and the sky is packed from scratch around whatever is left, with
  its own capitals. Filtering to Deckbuilders draws the deckbuilders' own
  constellations in ~120 ms; the whole catalog re-lays in ~0.5 s; and with
  nothing filtered the baked sky is still shown untouched. A **Layout** picker
  adds a second arrangement of the same graph: a **radial timeline**, one ring
  per release year with the earliest at the centre (Rogue 1980 dead middle, 43
  rings out to 2026), and the 83 games with no connections ringed around the
  outside. Only 712 of the graph's 1,115 links are
  tree branches, so branches draw solid and cross-links fade — `AtlasLayout` now
  carries a `parent` array so the view can tell them apart. Both modes honour
  every filter.

- **The route map fits its window** — the "Map to the Amulet" ladder is built
  inside a floating panel, and a `PanelContainer` takes whatever its children
  claim on the way in and never gives it back. A five-step route measures
  ~1090×668, so the window simply *became* that: 1787px tall, most of it below
  the bottom of the screen, legend and half the rungs unreachable, route still
  clipped. The window now sizes itself after the layout pass, and the opening
  view **zooms the route down to fit** (never up, and never past legible) so you
  see the whole road rather than a quarter of it and a scrollbar.

- **Traditional transmutes off its type, and the record follows the character** —
  Transmute kept the source's game type, which made it useless on a Traditional
  roguelike: trading one long haul (5 tries, not 3) for another is no relief. A
  Traditional game could become a random game of any *other* type. That is now a
  **setting** (Settings ▸ Transmute) rather than the law, and it is **off** by
  default — same-type is the rule every other type follows, and a Traditional
  player who wants Traditional games should keep getting them. Separately, the
  level-up row on the report checklist gained a **Notes** button — keyed to the
  (game, character) pair, the way an enemy note is keyed to (game, enemy) — and
  every defeat is now banked against the **character** as well as the game, so a
  character's page carries *Enemies beaten with* and *Levelled up at*.

- **The new sheet roster, and a board that can grow** — the catalog is up to
  **804 games and 1,115 connections** (47 games and 115 links added, every one of
  them with cover art), and the 2.0 rosters gained six goal-enemies (**Numbskull,
  Wringer, Gigantic Vermin, Nemean Chariot** off Hades, **Ice Slime**, **Spider
  Kitten**), two bosses (**Scylla**; **Mom's Heart**, which had been sitting on
  the sheet without a `.tres`), and one item — **Mine-r Construction**, which
  needed a rule the runtime didn't have. The battlefield's 4 x 4 was a pair of
  constants; it is now `GameLoop2.grid_cols()` / `grid_rows()`, base 4 plus one
  per copy of the item owned, so the board **gains a column of distance and a
  lane** the moment it's picked up (§7.3). The bodies already standing keep their
  column — the board grows behind them — but the overflow queue walks onto the new
  lane at once, and losing the item puts anything it would strand back in the
  queue rather than off the edge. The backdrop is rebuilt only when the size
  actually changes, so the repaint costs nothing on every other refresh.

- **The map is the star chart now** — "🗺 Map" (the header's, and the one on
  every offered card) opens the **Atlas with the route drawn across it**, and the
  layered ladder of decisions floats over it in a **movable window**: drag it by
  its header, and the sky underneath stays live — pannable, zoomable, clickable.
  The two halves are wired together: **clicking a game on the ladder flies the
  chart to it** and opens its card, **⌖ Frame route** puts the whole corridor back
  in frame, and framing keeps clear of whichever side the window is parked on, so
  the route is never centred underneath it. A card's map routes the chart from the
  game being *considered* — its star wears an **IF YOU GO HERE** marker in ember,
  between the green you-are-here and the gold Amulet — and the corridor drawn on
  the sky is the same graph as the ladder, edge for edge. The choose-your-start
  panel is the one exception: no chart is raised there, since a route drawn across
  the sky would point straight at the game the run is a search for.

- **Clearing the Amulet game wins the run** — and says so: the end screen reads
  **🏆 YOU WIN — THE AMULET IS YOURS**, names the game you took it on and how many
  games the run lasted, and closes the road strip on that game in gold.

- **The end of a run is a screen** — a finished run no longer just prints a line
  over an overworld that's still sitting there. `RunOverScreen` opens over the
  board with the verdict (**🏆 THE AMULET IS YOURS** / **💀 THE RUN ENDS HERE**),
  how it ended (*"Health hit 0 at Scourgebringer — 5 steps short of the
  Amulet"*), the run in numbers — character, games played and beaten, health,
  relics carried, difficulty reached, how far the Amulet still was, what was
  still following — and **the road you walked** as covers and arrows, closing on
  the Amulet with a dashed arrow across the stretch a lost run never covered
  (the same picture Run History draws). From there: another run, the run laid
  over the Atlas, the menu, or dismiss it to look at the board it ended on.

- **The board gets to finish** — reporting a game used to start the resolve
  animation and change the screen out from under it in the same breath: the
  offering came back, the page scrolled to the top, and the strike and the
  advance played to nobody. The run's state still moves on instantly (nothing
  waits on a tween), but the **view** is held: the stage keeps the shape it had
  while you were playing until the board has finished, and only then does the
  offering — or the end-of-run screen — take over. The advance was also being
  measured against a stale overflow-lane token, so an enemy walking onto the grid
  read as "didn't move" and never slid at all; the lane is now detached as well
  as freed, like every other layer on the board.

- **Every offered game says where it puts you** — above each card, before the
  art: **🏆 THE AMULET — the run ends here**, **★ OPTIMAL — n steps left** for a
  game on a shortest path, **→ Sideways** for one that's no closer, or **↩ Detour
  +n** for ground given away. Read off the same BFS the "Map to the Amulet" modal
  is layered from, so a card's badge and the map it opens can't disagree.

- **A map on every card** — a **🗺 Map** button above each cover (on the offering
  *and* on the choose-your-start panel) opens the optimal path to the Amulet **as
  it would stand if you took that game** — the whole road, not just a distance
  number. From the start picker the destination is drawn but deliberately not
  named (*The Amulet — ???*): the panel gives away the distance and nothing else.

- **The Atlas says where you are and what you came for** — the you-are-here and
  the Amulet used to be one more thin ring among the owned / hovered /
  transmuted rings. They're markers now: a halo, a cased ring pair and a printed
  badge (**YOU ARE HERE**, **THE AMULET — 5 STEPS**), drawn over everything and
  at every zoom, with an arrow parked on the edge of the view pointing the way
  when one is off screen. The header gains **📍 You** and **🏆 Amulet** buttons
  that jump to either end, the HUD carries the run in one line (*📍 Downwell → 🏆
  Rack and Slay (5 steps to go)*), and both are keyed in the legend.

- **A clicked game shows its whole cover** — the Atlas card used to crop the box
  art to a 248×124 letterbox. The card is the panel you opened to *look* at the
  game, so it now fits the entire picture to the card's width (scaled down, never
  cut, if that would make it too tall). The stars themselves still inscribe art in
  the circle the packing reserved for them.

- **Filters on the Collection's Constellations** — a filter row above the sky:
  **Constellations** (6 / 8 / 12), **Library** (owned / downloaded / not owned),
  **Type**, **Record** (beaten / never beaten / amulet won / has notes) and
  **Region** (one constellation), with a Clear button and a live *"88 of 757
  games"* count. Filters combine.

  A filter **re-lays the sky** rather than dimming stars where they stand.
  Dimming leaves the survivors scattered across the holes their neighbours left
  — a picture of the full catalog with gaps in it, not a map of what you asked
  for. So the survivors are handed to `AtlasLayoutBuilder` and laid out from
  scratch: filtering to Deckbuilders gives you *the deckbuilders' own*
  constellations, cut around their own capitals (Slay the Spire, Balatro, Luck
  be a Landlord, …). It takes ~120 ms for a slice like that and ~0.5 s for the
  whole catalog. With nothing filtered the **baked** sky is drawn untouched —
  it is the one that shipped and the one you have a sense of place in.

  **Region** is the exception that stays measured against the baked sky: a
  rebuilt sky cuts its own regions, so "games from the Slay the Spire
  constellation" has to keep meaning the canonical constellation. The capital
  count (6 / 8 / 12) picks which baked sky is the base — each is its own file
  (`atlas_layout_c6.tres` / `_c12.tres`) since the cut changes every region —
  and changing it clears the Region filter. The filter row only exists in the
  Collection's catalog view; a run's Atlas has no filters and never moves,
  because routes are drawn across it.

  **Right-drag is the pan button.** Left-drag still pans, but the left button has
  to decide between "moved the map" and "picked a star" and only counts as a pan
  past 5px; the right button only ever pans, so it moves the sky a pixel at a
  time.

- **Two layouts: Constellations and Tree** — a **Layout** picker at the head of
  the filter row switches how the same graph is arranged. *Constellations* is
  the star chart: hubs with their influence trees packed around them, with the
  **83 games that have no links at all scattered in a halo around the whole
  sky** instead of being packed in among the constellations as one-star
  "components" — they aren't part of any constellation, and out there they read
  as what they are: the catalog's unjoined edge. The halo is jittered but never
  overlapping: stars are dealt into three concentric bands so anything angularly
  adjacent is separated radially, and the ring's radius is solved from those
  bounds rather than picked.

  *Tree* is a radial timeline: **one ring per release year**, earliest at the
  centre. Rogue (1980) sits dead middle, 1996 is a ring, 2025 is a ring 108
  games wide, and the **83 games with no connections at all** are ringed around
  the outside. Rings are spaced by *time*, not by rank, so the years nobody
  shipped in (1981, 1985, 1988–89) read as real gaps and the 1980s are sparse
  while the 2020s are dense — which is the shape of the catalog. A ring is
  widened past its year's place only if it has too many games to fit otherwise.

  Within a ring, a game sits at the bearing its **branch** put it at, nudged
  apart only where two would touch. Re-spacing each ring evenly would be simpler
  but every ring would pick its own phase, and a game would end up at an
  unrelated bearing from its parent — branches would cross the disk rather than
  run out along it. The influence graph is not a tree either (only 712 of its
  1,115 links are branches), so branches draw solid and cross-links drop to a
  whisper. The tree honours every filter too.

- **"Beatable:" on the offering** — while choosing where to travel, a card shows
  small portraits of the enemies you have **already beaten at that game before**:
  the enemy standing there now, and anything currently following you. It is not a
  prediction — it is your own record saying this pair has worked, which is
  exactly what you want while deciding where to drag a follower. Hovering a
  portrait gives the goal, how many times it fell there and whatever note you
  wrote. A card with nothing proven stays clean.

- **Per-game enemy notes** — games now remember **which enemies were beaten on
  them**, and you can write down how. Every enemy line on the end-of-game
  checklist carries a **🗒 Notes** button on its right; the button shows a pen
  once something is written, so an annotated row reads at a glance. Ticking the
  goal (or a follower you also cleared) logs that enemy against that game.

  On a game's Atlas card, **🗒 Notes — beaten enemies (n)** opens the list: each
  enemy's **art**, its goal, how many times it fell there, and your note under
  it, most-beaten first. Notes can be **edited or deleted** from there as well as
  written on the checklist — you often only work out how you beat something after
  the run is over. Deleting clears the note alone; how many times the enemy fell
  there is a record of fact, not a note, and stays.

  The Collection's **Enemies** tab shows the same record from the other side:
  each enemy's detail lists the **games it has been beaten in**, with cover,
  count and note in the same format, editable in place. The **Games** tab carries
  the mirror of it — every enemy beaten at that game.

  Both sides carry a completion stat as **x / y**: an enemy's *Games beaten in
  (3 / 808)*, a game's *Enemies beaten in (4 / 77)*. `y` is **every pairing that
  could be recorded, which is all of them**. It used to be filtered by game type,
  on the reasoning that an enemy is *rolled* for a game of its own type — but
  spawning isn't the only way an enemy gets beaten somewhere. A survivor
  **follows you across games of every type**, and clearing its old goal records
  it against whatever you were playing at the time, so an Action enemy beaten
  during a Deckbuilder is ordinary. The type filter was excluding real, reachable
  pairings, which is why both call sites had to guard the display against reading
  *5 / 3*.

  A note belongs to the **pair**, not to the enemy — the same goal-enemy turns up
  on many games and how you cleared it is a fact about that combination. Notes
  are written where you actually beat the thing, which is when you remember how,
  and the Atlas panel is read-only. Stored in `game_stats.json` next to the rest
  of the lifetime record.

- **A star's rim is its genre; in the Collection, its middle is your record** —
  a game you've never played is drawn **solid in its own genre colour**, and one
  you have wears a **silver** pip once beaten or a **gold** one once you've won a
  run on it. Gold outranks silver, since winning a run implies beating it and the
  rarer fact is the one worth seeing. Putting the record in the core rather than
  on the rim keeps the sky readable **as genre at every zoom**, and a record
  reads as something *gained* rather than as the absence of dimming — the earlier
  "unplayed games are dimmed" rule is gone, since it washed out most of a catalog
  nobody has finished.

  The record is drawn **only in the Collection's Constellations**. During a run
  the sky is about the run — the route, where you stand, what you've bashed — and
  a lifetime marker competes with that, so the middles stay empty there. The
  info card still carries the numbers in either view, in the Collection's own
  vocabulary: **⚔ Beaten** and **👑 Amulet won**.

- **"Show constellation" in the Collection** — the Games tab gains a button that
  opens the whole catalog as the star chart, in **pure-catalog mode**: no run is
  laid over it. No route to the Amulet, no path taken, no you-are-here or Amulet
  rings, no strike-throughs on games bashed this run, and a transmuted node shows
  the game the catalog says lives there rather than what was pasted on it. It is
  titled *Constellations* rather than *Atlas* to make the difference plain.
  "Beaten" means the lifetime record here, where the in-run Atlas also counts what
  you've beaten on the way. Same sky, same layout — only what's drawn over it
  differs.

- **Run History, over the map** — the main menu's Run History is no longer a
  stub. Every finished run is kept as **the route it actually walked**: covers
  left to right in the order played, an arrow between each pair, the Amulet
  closing the row marked won or lost. A run that died short of the Amulet shows
  a **dashed** arrow across the stretch it never covered. The screen sits **on
  top of the Atlas**, so the strip is the route in order and the sky behind it is
  where that route went; **Show on map** throws a run onto it. Runs are written
  by `GameLoop2._finish_run`, now the single exit from a run, so one can't end
  without being recorded, and they persist in `game_stats.json` (capped at 40).

- **Bash and Transmute on the map** — a **bashed** game's star is struck through
  in red and every link into it turns red, because those routes no longer exist;
  its card says so, and so does any connection touching it. **Transmute is now a
  paste onto the spot**: it used to be a property of one offering, held locally
  by `Overworld2` and cleared on every move and scramble, so it evaporated the
  moment you walked on. It now lives in `GameLoop2` as node → replacement,
  survives moving, scrambling and saving, and the node plays that game for the
  rest of the run. `GameLoop2.game_at()` is the one place that answers "what game
  is actually here". The node keeps its place on the graph, so the map draws the
  pasted game's cover at the old spot with an ember ring and its card names both
  **Now** and **Was**; a connection card keeps naming the *original* games —
  the influence claim is between those — and adds a line saying what has been
  pasted over an endpoint.

- **Connection proof, and a card for the links themselves** — clicking a *line*
  on the Atlas now opens a card showing **both games side by side**, the
  influencer on the left with an arrow to the game it influenced, the claim in
  words ("X inspired Y"), and the **evidence** underneath. Links flagged in the
  sheet as a sequel or the same studio say so. A source that's a URL gets an
  **Open source** button; the ~280 that are notes ("check folder", "game
  credits") are shown as written rather than dressed up as links. Either game can
  be inspected from the card. Clicking a star still wins over a link under the
  same cursor, since near a hub the pointer is always over some line.

  This needed data the importer had been discarding. `Roguelikes.xlsx`'s
  `connections` sheet carries a **Source** column (884 of 1000 rows) and a
  **Dev/Series Relation** column (114 rows); `import-games-godot.py` read only
  the two game names and dropped both. `GameData` gains `influence_sources` and
  `influence_relations`, index-aligned with `games_influenced`, and the importer
  now carries them through. This closes the README's long-standing "connection
  proof" roadmap item — the evidence was gathered years ago and simply wasn't
  being imported.

  **Re-importing also caught the catalog up with the spreadsheet**, which it had
  drifted behind: **6 games** (How Many Dudes?, Inkbound, Mystery Chronicle: One
  Way Heroics, One Way Heroics, Runeveil, Zoominoes) and **11 net connections**
  that were authored in the sheet but had never reached `data/games/`. The
  catalog is now 757 games / 1000 connections, up from 751 / 988. This changes
  which routes exist, so runs will differ.

- **A staleness guard on the baked skies** — `data/atlas_layout*.tres` are
  generated and committed, so they can silently fall behind the catalog: a
  half-failed import, a hand-edited `.tres`, a merge that took one side. Star
  count alone never caught it — add a connection between two existing games and
  the count is identical while the map is wrong. The Atlas tests now rebuild the
  edge set from `data/games/*.tres` and compare it to each baked sky, and check
  every star is drawn at the size its real connection count says. A failure names
  the offending connection and tells you to re-run `tools/bake_atlas.py`.

- **The Atlas — all 751 games as a star chart** — a new full-screen map
  (`scripts/ui/AtlasView.gd`, opened from the main menu's **✦ Atlas** button, or
  from the run map's **✦ Star chart** button). Every game is a star: size is its
  connection count, the outline colour is its `GameType`. Games are grouped into
  **eight constellations** around the highest-degree hubs — Slay the Spire,
  The Binding of Isaac, Vampire Survivors, NetHack, FTL, Hades, Balatro,
  Spelunky Classic — with each game joining whichever capital it reaches in
  fewest hops. Detail follows zoom: dots and constellation names when zoomed out,
  links in the middle, every star named up close. Clicking a star isolates it —
  its links light up, the rest of the sky dims — and opens a card with the cover
  art, release year, connection count, home constellation, distance from its
  capital, and a **Play the real game** button where there's a launch target.
  While a run is under way the shortest path to the Amulet is drawn over the sky
  as an **ember trail** (green behind you, ember ahead), so the run map and the
  atlas are the same picture at two altitudes.

  There is **one sky per game filter**. Setting the path filter to *owned* (or
  *downloaded*) opens a different, independently laid out map — 457 games, its
  own capitals, Enter the Gungeon promoted where Balatro sits on the full map —
  because a route through an unowned game doesn't exist for that run and drawing
  it would be a lie.

  Positions are **baked, not computed at runtime** — `tools/bake_atlas.py` writes
  `data/atlas_layout*.tres`, and `import-games-godot.py` re-runs it for every
  filter, so editing the spreadsheet moves the sky. Inside a constellation each game orbits the game
  that influenced it, with subtrees packed as discs around their parent; a
  subtree's radius is *measured* from its realised layout rather than bounded
  from its children's, because the nested bound doubles at every level and threw
  deep chains thousands of units into the void. The bake verifies that no two
  stars overlap at their drawn radii and fails rather than writing a bad map.
  `Settings.game_filter` never moves a star — the atlas is the whole catalog.

Highlights from the most recent Godot sessions (newest first). The
spreadsheet-driven content below regenerates via the `tools/` importers, so
re-run them after pulling and review the diff.

- **Choose where you start, save the run, and bash that refills the slot** — a run
  now opens on a **choose-your-start panel**: three games, each a **different game
  type**, each **5–7 games from the randomly chosen amulet** (`RunGraph` retries
  the amulet until three genres can all fill that band rather than quietly
  offering a shorter route). The start is where you *begin* — no enemy spawns and
  no shields are granted — and its neighbours become the first offering.
  **Saving works end to end**: the overworld's **💾 Save** button names a run, the
  run keeps an **autosave** that is rewritten every time it moves and cleared the
  moment it ends, and the menu's **Continue** list resumes either. A save now
  carries all three halves of a run — GameState, `GameLoop2`'s enemy stack and
  destroyed games, and the overworld's own screen (the cards on the table, the
  game in play, the loot tray) — so a resumed run picks up exactly where it
  stopped. **Bash** still destroys a game for the rest of the run, and now
  **refills the slot it vacated** with another game *connected to where you are
  standing*, rolling a fresh goal-enemy for the replacement while every untouched
  card keeps the enemy it was already showing (bashing or transmuting one card
  used to silently re-roll the others). With nothing left to connect to, the slot
  goes with the game; bashing the **amulet game** or the **last card on the table**
  is refused, since both end the run rather than shape it. Also fixed: the
  overworld's registration as the mounted map was wiped by the run reset that
  immediately follows it, which had left scrolls unreadable and overworld actives
  (Ride the Bus) unusable for the whole run.

- **Shields are the tries: an attempt tracker, and a two-column playing screen** —
  Block is gone and **Shields** take its place as the *runs you get at a
  game*. Selecting a game grants **3** (or **5** for a Traditional roguelike);
  every run of it you lose is one tick of the new **attempt tracker**, which spends
  a shield, and once they're gone a lost run costs **1 Health** (0 Health ends the
  run there). Whatever is left when you report the game absorbs the followers' hits
  and then **expires with the game** — shields never bank forward. **Anchor** moved
  to a new **`game_selected`** trigger so its +1 Shield is a genuine extra try
  before you play, not a reward afterwards. While a game is in play the screen is
  **two columns**: on the left what you drive — the game, Play / Rate, the attempt
  strip, a tightened one-line-per-row checklist and Completed Game — and on the
  right what you read, the **battlefield with the pack (inventory + loot) under
  it**. Both halves fit one screen, where stacking them didn't. The stage keeps
  that shape **between games too** — the board is never hidden, and the checklist
  becomes a **standing-goals list** ("What you need to do": the character's
  level-up challenge and every follower's outstanding goal, tinted red once it's
  in the front column), so what you owe is answerable *before* you commit to a
  game rather than only after. The board draws the pool as
  **pips on the hero** and a tick pops one with a floating `-1 ◆` — or flashes the
  hero red for `-1 ♥` once the shields are gone. Each offered card shows the tries
  it grants, and since the pool is empty between games, hovering a card previews
  that grant in the HUD's Shields slot (`Shields +5`) instead of a flat 0.

- **Rating on a button, a bonus for rematches, revisits that redraw, and pickups
  that show their effects** — the tier-list prompt no longer pops itself up after
  a game; it opens from a **★ Rate** button (on the report panel, and on the
  select screen for the game you last reported), and the modal now actually
  covers the screen instead of leaving the board live behind it. Beating a game
  you have **already beaten this run** grants **+1 Dash**, called out as
  "⚡ Gain +1 Dash" above that game's cover in the offering (and on its hover
  preview), so doubling back is a real routing option; the clear is recorded on
  the run (`GameState.beaten_games`) and on the lifetime per-game tally the
  Collection and tier list read (`GameStats`). **Arriving** at a game salts the
  offering draw, so coming back to a node hands you a *different* subset of its
  neighbours rather than replaying the same three cards. Picking anything up now
  reports itself immediately: the HUD repaints off the state signals (Health /
  Max Health / verb counts no longer wait for the next game to resolve) and
  `GameState.add_item` diffs the run resources across the pickup to post a
  "Lunch: +2 Max Health, +2 Health" line — the toast strip is mounted on the
  overworld again, so those lines are visible at all.

- **Random Sized Chest + roster/content refresh** — the Vampire Survivors
  characters' level-up reward is a **Random Sized Chest**: the roll picks the
  chest's SIZE (Small 1 / Medium 2 / Large 3 / Huge 5 items) on the same
  75/20/5-with-a-10%-bump ladder as every other rarity draw
  (`Data.CHEST_SIZE_CHOICES`), rather than the rarity of what's inside. Ported
  **Poe Ratcho** and **Antonio Belpaese** plus new games, goal-enemies, and
  bosses from the sheet.

- **Inventory and loot beside the board; covers at box-art scale; the overworld
  split into three files** — the player's pack (inventory + a loot tray) stands
  in a column to the RIGHT of the battlefield grid, so a drop waits there to be
  claimed or skipped instead of standing on a cell. Cover art is drawn at its
  real 3:4 shape and ~1.5x bigger on the choice cards (210x280), in the
  Collection, in the rate-game modal, and on the report panel, which shows the
  game you went to play next to the enemy you went to beat. `Overworld2.gd` shed
  ~1000 lines to `BattlefieldView.gd` (the board, its animation, the Push/Bomb
  toolbar) and `EnemyInfoCard.gd` (the inspect card); the duplicated rarity rolls
  collapsed into `Data.roll_rarity_step` / `roll_item_rarity` and the
  crisp-texture helpers into `UITheme`.

- **Art reorganised into `images2.0/`** — every asset the games-first build uses
  moved to `images2.0/{games,items,enemies,bosses,characters,scrolls}/`, resolved
  from each sheet's `File` column. `images/` keeps only the pre-2.0 art that
  surviving `data/` resources still load.

- **Enemy footprints and multi-cell positioning** — an enemy occupies its whole
  `Size` footprint (`1x2`, `2x1`, `2x2`, or a shaped box like `2x3 L 90 CC`), and
  a placement is legal only when every solid cell is free. That single rule gives
  the board its behaviour: a wide body enters closer to the player and strikes
  sooner, a big body is a wall that stalls the queue behind it, an L leaves
  exactly the gap its notch describes, and **Push** needs the entire footprint to
  fit one column back. Art draws across the full bounding box and hit-testing
  follows the mask, not the box.

- **The MMBN-style grid battlefield with inline drops** — followers are drawn on
  a grid (columns = distance, rows = lanes) with the player on the left, 4x4 at
  the run's opening tier and a column and a row wider on each step past it.
  Enemies enter at the back, close one column per TURN (see the amulet-pressure
  entry above), and strike once any of their cells touch the front column; an
  overflow queue waits off-grid and slides on as space frees. Every defeated enemy's drop appears as loot to claim
  or skip instead of opening a reward screen.

- **Push + the Manager, and Deckbuilder promoted to a first-class game type** —
  **Push** (spend a charge to shove a follower one column back, delaying its next
  attack) arrived with the **Manager** character from Raccoin. The game types are
  now **Action / Deckbuilder / Traditional / Strategy** — `deckbuilder` and
  `traditional` were tags on Strategy and are authored on `GameData.type`
  directly, so each type draws its own goal-enemy pool.

- **Games-first item rewards and active item effects (§8)** — `items2.0` behaviour
  classes are wired end to end: `Pickup` (one-shot `item_acquired` effects),
  `Triggered` (the dominant `game_beaten` hook — Anchor, Burning Blood, Meat on
  the Bone), `Charged, N` (D6, Wand of Wishing), `Usable` (Ride the Bus), and
  `Passive` (Vajra's +1 Bash). Chests bank through `GameState.grant_chest` and
  redeem into `RewardScreen`s when the board is idle.

- **The games-first cut (§11)** — the simulated combat modes are gone: the
  deckbuilder / action / strategy scenes and scripts, combat cards and statuses,
  potions, spells, dice, and the combat enemy stat blocks were all removed (they
  live on in git history). What replaced them is `GameLoop2` — the goal-enemy stack,
  the games-beaten clock, the difficulty tiers and their boss rounds — plus
  `ScrollSystem` (identify-by-reading scrolls), the tiny Health / Max Health /
  Shield model, and the bash / dash / transmute / scramble / push verb layer.
  **The real video game you go and play is the combat.**
