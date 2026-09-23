# Layout review — what is still open

A UI/layout pass was done over every screen in the game: the twelve screens were
captured at the shipping canvas, measured, and read against the code behind them.
Most of what it found has been fixed (see the top of [`CHANGELOG.md`](../CHANGELOG.md)
for what and why). This is the remainder, written down so it can be picked up
cold in a later session.

Each item says **what** is wrong, **why it matters**, and **what it would take** —
because the sizing is the part that is expensive to re-derive.

**All eight items are now closed or down to a named remainder.** §1 is **decided**;
§3, §4, §5, §7 and §8 are **built or fixed**; §2's fonts and gaps are **done** as value-preserving renames, leaving 57
between-step gaps as an optional restyle; §6's
is **done**, both halves; and §7's empty `Continue` row is gone. Closed work is kept here with its reasoning rather than
deleted, so none of it gets asked again; a closed item says so in its heading, and
a half-closed one says which half.

> Two notes for whoever picks this up.
>
> **Colour claims need a pixel, not a screenshot.** Judging a dark surface by eye
> off a captured PNG produced one confidently wrong finding during the original
> pass (a dropdown reported as unthemed that was drawn in exactly
> `UITheme.PANEL`). Sample the rendered pixel — mount the screen, `await
> RenderingServer.frame_post_draw`, `get_viewport().get_texture().get_image()`,
> `get_pixelv()`.
>
> **The `verify` skill is how to look at any of this** — `.claude/skills/verify/`,
> Xvfb plus a temporary driver scene. Layout claims are cheap to check that way
> and expensive to guess at.

---

## 1. The tier list's palette — DECIDED, keep it

**Closed, not open.** `TierListScreen.TIER_COLORS` is the stock tiermaker ramp —
pastel red / orange / yellow / green / blue / purple — inside a game with a
deliberate warm ember-and-parchment palette, and `UNRANKED_COLOR` is a muted brown
that does match, which makes the six above it look more borrowed rather than less.
The question was put and the answer was **leave the colours as they are**.

**Why, so this does not get re-litigated.** S/A/B/C/D/F is legible *because* it is
the ramp everyone else uses — the borrowed look is the feature. Recolouring it to
six warm tones buys palette consistency on a screen that sits outside the run, and
pays for it in six tiers that are harder to tell apart at a glance.

A future pass that wants to narrow the gap anyway has one move that does not
touch the convention: pull the six slightly toward the ember palette (desaturate,
warm the whites) while keeping the hue ORDER recognisable. That is a different,
smaller change from replacing the ramp, and it is the only version worth
reopening. If it ever does change, the tier buttons in `RateGameModal` and the
move-to row read the same const array.

## 2. The spacing scale — fonts DONE, gaps DONE as a rename

**Done: fonts, project-wide.** All 47 screens that set a font size in code now
take it from the type scale; 259 bare integers became named steps in one pass.
Every replacement was value-preserving by construction (each integer mapped to the
token holding exactly that integer, and the diff was read back to prove every
changed line round-trips byte-identical), so nothing moved and nothing needed
re-fitting. `test_design_tokens.gd` keeps it that way with `MIGRATED_FONTS`, and
that list is asserted **complete** against a walk of `scripts/` — a new screen
cannot ship bare integers by not being on it.

**Done: gaps, project-wide, the same way.** Every `separation` / `h_separation` /
`v_separation` literal holding exactly a step's value — **223 across 41 files** —
became its `UITheme.GAP_*` name, and the diff was read back the same way: each of
the 223 changed lines, with the name swapped back for its number, matches the
original byte for byte. So nothing moved and no fit test needed looking at.
`MIGRATED_GAPS` now lists all 51 files that set a gap and is asserted complete
(`test_every_screen_that_sets_a_gap_is_on_the_gap_list`).

**What is left is a restyle, not a rename: 57 literals between two steps**, listed
per file in `OFF_SCALE_GAPS` — 1 and 3 as hairlines either side of `GAP_HAIR`,
5 / 7 / 9 as odd sizes, 14 and 18 between the loose steps, and a 22 and a 26 as
section breaks. Naming one means changing it, which is the line the font pass
drew too. The run screens' ones are load-bearing to the pixel on the 720p page and
should stay; the rest (Collection, Atlas, Tier List and the modals) can be snapped
one screen at a time, **looked at on the running screen**, and taken off the list
as they go. A new literal in any file is still caught — only the listed values,
in the file they are listed against, are allowed.

**Why it mattered.** It was the reason layout changes were expensive here. "Give
this column 26px back" meant auditing eight numbers by hand and writing a comment
explaining each — which is exactly what the overworld's own history records.

**The off-scale sizes are closed too.** The font pass deliberately left 22
literals alone — naming them would have meant *changing* them, and a restyle does
not belong inside a rename. They have since been snapped as a separate, deliberate
pass, each checked on the running screen:

| was | uses | now | why |
|---|---|---|---|
| 17 | 11 | `FONT_HEAD` (18) | eight were `SettingsModal` section headings; a heading size onto the heading step |
| 24 | 7 | `FONT_TITLE_LG` (22) | all seven are titles. 24 was equidistant between 22 and 26, so the tie went to the step whose comment says "a screen's title" |
| 21 | 2 | `FONT_TITLE_LG` (22) | titles again, and the nearest step |
| 30 | 1 | `FONT_HERO` (28) | `Collection`'s title, which was drift rather than a decision — it now matches the tier board's |
| 34 | 1 | `FONT_HERO` (28) | `RunOverScreen`'s verdict, the biggest reduction at −6px; still the largest thing on its screen |

Fit was checked rather than assumed, since five of these got BIGGER: `SettingsModal`
already scrolls by design (1816px of content in a 624px view), so +8px across eight
headings changes nothing there, and `RunOverScreen` still fits with no overflow.
**`OFF_SCALE_FONTS` is now an empty dict** — kept rather than deleted, as the
pressure valve for the next size that genuinely cannot be named.

## 3. The Collection's grid — ALL THREE DONE

Three separate things on the screen where 865 covers are browsed. It is the
second-most-used screen in the game after the run itself.

**a. ~~The grid is bottom-clipped with no scroll affordance.~~ DONE.** The second
row was cut flat at the panel edge with nothing saying more was below — there was
a scrollbar, but it is a slim stripe you have to hunt for. There is now a 26px
band of the panel's own colour under the last visible row (`Collection.GRID_FADE_H`,
`_new_grid` / `_update_grid_fade`), up only while there IS more below and stood
down at the bottom of the list. It is a SIBLING of the ScrollContainer, not a
child — a child scrolls with the content and slides away exactly when it is
needed — so the two are stacked in a plain Control by anchors.

**b. ~~The beaten-checkbox sits on top of the cover art.~~ DONE.** It was inset
into every cover's top-left: the one piece of state a cell carries, drawn over the
one thing that identifies the game, on 865 cells. Worth knowing before touching
it — it is not decoration, it is a BUTTON, and on the player's own list it is the
fastest way to mark a game owned without opening its page. So it moved rather than
went: it is on the stat line under the cover now, beside the ⚔ / 👑 counts, which
keeps the click and frees the art. The ticks still read as a column down the grid
because every cell is the same width and the row is centred, and
`_game_cell_height` counts the row at the taller of tick-or-text so the cell
cannot clip its own last line.

**c. ~~Cover aspect ratios vary wildly.~~ DONE.** Some 4:3, some square, some
tall, so the grid read as ragged. The premise needed one correction first: the
covers were ALREADY letterboxed into a fixed 3:4 box
(`STRETCH_KEEP_ASPECT_CENTERED`), so the raggedness was never the art overflowing
— it was the leftover around it being the cell's own background, which made each
cover look like a different shape floating in a different amount of nothing.

So the fix is a **plate behind the art** (`COVER_PLATE`, `_cover_plate`), slightly
lighter than the cell, which turns that leftover into a deliberate surround: every
cell now shows the same rectangle whatever shape its cover is. Cropping to a common
ratio was the alternative and was rejected — it cuts the edges off non-3:4 art, and
some of the 865 covers carry their title there. Nothing is cropped and nothing is
scaled up, so `UITheme.is_pixel_art` does not come into it.

## 4. The tier list's `Unranked` lane — FIXED

**Closed.** Its label tile was narrower than the six above it and its lane started
17px further left. The diagnosis in this doc was measured and held exactly:
`_build_tier_row` puts a `LineEdit` in the label cell because a tier can be
renamed, `_build_unranked_row` puts a plain `Label` because "Unranked" cannot,
both set the same `custom_minimum_size` of `LABEL_CELL * _scale`, and the
`LineEdit`'s larger intrinsic minimum pushed the six tier cells past it. Measured
at 1280x720: tier cells **72.75px**, Unranked **55.68px** — and 55.68 is exactly
`LABEL_CELL.x * _scale` at the 0.58 the board was fitted to, so the tray was the
one sitting on the minimum, as described.

**The fix names the real cause**: a `LineEdit`'s intrinsic width is
`minimum_character_width` em-spaces (Godot's default is 4), so
`add_theme_constant_override("minimum_character_width", 0)` lets the cell be the
width the const says. All seven lanes now measure identically and every zone
starts at the same x. It also makes `_board_height` honest, since that was
already assuming a label cell of `LABEL_CELL.x * s` when fitting the board.

## 5. The tier list's empty state — FIXED

**Closed.** With nothing rated the board was seven empty lanes and nothing else,
under a subtitle offering three things (click a game, drag it, rename a tier) that
all need a game to be there already. Rating is strictly opt-in and offered from
exactly one place, so a player could reach this board with no idea how to fill it.

Now the subtitle becomes `Nothing rated yet` and a line under the tray names the
one way in and where it lands: *"Finish a game and choose ★ Rate this game on the
haul screen. It arrives in Unranked, and you drag it up from there."* Both halves
are checked against the code — `RateGameModal` is the only entry point, and
`TierList.ensure_present` is what puts a freshly-rated game in the tray rather
than in a tier. `EMPTY_NOTE_H` is counted by `_board_height`, because a height the
fit does not know about is a height the board overflows by.

## 6. `MainMenu.tscn` is authored in the editor and re-skinned in code

**What.** It is the only editor-authored scene in the project (every other screen
is built in code). Its background, title and subtitle colours are set in the
`.tscn` — and then overwritten at `_ready` by `MainMenu._style_menu()`, which
reaches in by node path (`get_node_or_null("Center/Panel/TitleBox/Title")` and
six more).

**Why it matters.** Two things. The editor preview shows colours no player ever
sees, so the one scene you *can* design visually lies about itself. And renaming
a node in the editor silently disables its styling — `get_node_or_null` returns
null and the function moves on without a word.

**HALF DONE: the lookups fail loudly now.** `_style_menu` used
`get_node_or_null` down four hardcoded paths behind `is` checks, so a rename
silently skipped the styling and the menu came up in raw `.tscn` colours with
nothing said. All four are `%UniqueName` now, which does not care where the node
sits and raises if it is genuinely gone. `Background`, `Title` and `Subtitle`
were given `unique_name_in_owner` in the scene to match the nine nodes that
already had it — and `StartRunBtn` was the tell that this was the right shape: it
ALREADY had a unique name and was already reached as `%StartRunBtn` eleven lines
above, while `_style_menu` walked a four-deep path to the same node.

**DONE: the duplicated colours.** The scene now authors the background, title and
subtitle at their real `UITheme` values (`BG_DEEP`, `GOLD`, `TEXT_DIM`), and
`_style_menu` no longer repaints them, so the editor preview is what a player
sees. The copy is pinned rather than trusted:
`test_main_menu.gd::test_the_scene_is_authored_in_the_themes_own_colours`
instantiates the scene WITHOUT running `_ready` and compares all three to the
theme, so a theme change that leaves the scene behind fails a test instead of
drifting. What stays in code is the Start Run button's stylebox, which a scene
cannot share with the theme the way it can share a colour.

## 7. The main menu — BUILT: the game's art falls past it

**What it was.** A 320px column centred in a 1280px canvas, in a game whose
entire content is 865 pieces of cover art. The first screen anyone sees, and it
said the least of any screen in the project.

**What it is now.** `MenuFallingArt` fills the two-thirds that said nothing:
characters, enemies, items, loot and game covers drifting down BOTH sides of the
button column, each tumbling slowly at its own rate and direction and fading out
into the dark at the bottom. Constant fall speed rather than accelerating — they
fall past, not away. It keeps running under the modals, so the menu behind the
character picker is alive, and there is a Settings toggle under Display for
anyone who wants a still background.

**The second pass** (72 pieces rather than 52, a narrower clear band, and the
pools grown to match) changed two things worth writing down:

- **The playable characters fall past too**, and they come through `Data` whole
  rather than through the shuffle. Eleven portraits against some 250 other small
  pieces would be about five of a 112-entry pool drawn at random, and on an
  unlucky launch none at all — a roster that shows up some nights and not others
  is a bug nobody can reproduce. They fall at the two-cell size: a character is
  not a pill, and nothing here stands on the grid for a footprint to be read off.
- **The top does not fade any more.** It used to spend the first tenth of the
  height fading a piece in, which is exactly where a piece is newest — the eye
  that follows one down watched it appear out of nothing. Taking the fade away
  exposed what it had been hiding: `_spawn` could drop a fresh piece a fifth of
  the way DOWN the screen. Pieces now enter wholly above the top edge at their
  full alpha, staggered over a third of a screen so the returns are not a row of
  arrivals on one invisible line. The bottom fade is untouched — that one is what
  makes the floor read as a drop rather than as an edge.

**The three things that were wrong while building it**, none of which is visible
in code review:

- **The mix was all one kind.** Pieces filled to `PIECE_COUNT` inside the first
  second while the texture pool was still loading, so every one was drawn from
  whatever had decoded first — measured at **0 covers of 52** on screen, with the
  cover share only arriving as pieces recycled about thirty seconds later. Nothing
  spawns now until the pool is whole (~1s), and the opening fill scatters pieces
  across the screen rather than dropping them in from above. It is the only fill
  that does: every piece after it enters from above the top edge.
- **Sprites with a baked-in background fall as tiles.** All 28 of
  `wands_unidentified/` are 16x16 with an **opaque** teal ground, and they showed
  as teal diamonds. They are RGBA files in which every pixel is alpha 1 — having
  an alpha CHANNEL proves nothing, which is why the check is `_is_cutout`
  (does the border have any see-through pixel?) rather than a look at the format.
  Seven of the 54 enemies and four of the 40 bosses are the same; the folder came
  off the list and the guard catches the stragglers.
- **Covers cannot be held at source size.** 336 of them at 528x704 is 236 MB on
  disk and ~1.5 MB each in memory. A fixed pool (26 at first, 34 now) is baked
  down on the way in to roughly the 96px they are drawn at, and the pool is
  decoded a few textures per frame so the project's startup screen never hitches.
- **A bigger enemy has to fall bigger**, which is why the enemy art comes from
  `GoalEnemyData` and not from `images2.0/enemies/`: the resource carries the
  footprint beside the picture, and the folder knows nothing about the grid. A
  piece draws at the bounding box's longest side times the base edge. Scaling it
  up then found a second bug — `_column_x` placed a piece's CENTRE at the clear
  band's edge, so a 138px enemy reached half its width into the buttons, and the
  test meant to catch that had its half-width subtracted where it should have
  been added. Both fixed; the check is now whether the WHOLE piece clears.
- **The same picture must not fall twice at once.** 52 pieces drawn at random
  from a pool of ~116 duplicated constantly. Pool entries are handed out off a
  free list and returned on recycle — which is also why both pools are sized off
  `PIECE_COUNT` rather than chosen on their own: a pool only a little larger than
  the screen holds runs the free list dry, the fallback kind takes over, and the
  mix drifts away from `COVER_SHARE` on its own.

**DONE: the empty Continue row.** With no saves the button is hidden rather than
standing disabled as `Continue (no saved runs)`, a full row saying nothing on
every first launch (`MainMenu._refresh_continue_button`,
`test_continue_is_hidden_when_there_is_nothing_to_continue`). It comes back the
moment a save exists.

**Left as a taste call, not a defect:** whether the profile row and How to Play
belong where they are. Nothing about either is broken, so it waits for someone
who wants them somewhere else.

## 8. Character picker nits — FIXED

All three, measured before and after at 1280x720.

- **Row heights.** Row 1 measured 137px against 122 for rows 2 and 3 (the doc
  guessed ~14; it was 15), because "Antonio Belpaese" wraps to two lines and
  `TILE_SIZE` is a minimum, not a fixed size — and a `GridContainer` row is as
  tall as its tallest cell. Fixed by `_equalise_tiles`, which levels every tile
  to the tallest AFTER layout. Two predictions were tried first and both came up
  exactly 7px short — `line height × 2`, and the font's own
  `get_multiline_string_size` — because a wrapped `Label` also carries the theme's
  line spacing, which font metrics do not report. Measuring the laid-out tiles
  cannot be wrong that way. Spread is now 0.00.
- **The void under the detail panel** measured 144px, not ~180. The cause was a
  mismatch: `right` was already `SHRINK_CENTER` while `left` was `SHRINK_BEGIN`,
  so the portrait hung from the top, the facts floated at the middle, and all the
  slack pooled under the portrait. Both are centred now. Checked against the WHOLE
  roster before changing it, because nothing on this panel scrolls and centring an
  overflow would clip both ends: the tallest hero (Manager, 318px) leaves 124px.
- **The footer gap** measured 478px. `🎲 Random` now sits beside `Confirm` with
  `Cancel` alone on the left — which is what the dice button's own comment already
  argued for ("would make this the one button on the screen that starts a run
  without the Confirm beside it") and what the layout contradicted. 10px apart now.

---

## FIXED: the checklist grew a row per body, with no ceiling

Found by `test_the_page_still_fits_the_window_with_a_shop_on_it` when §19.5's
failure spawns landed. **Not caused by them** — they only made it common.

**Re-measured before fixing, and the write-up had the wrong trigger.** It blamed
the shop. At the time of the fix the shop panel made no difference: the right
column measured 565–591px either way. What overflowed was the LEFT column on its
own, at 720p:

| Bodies | Left column (before) | Page (before) | Page (after) |
|---|---|---|---|
| 0 | 403 | 591 | 591 |
| 3 | 576 | 591 | 601 |
| 4 | 627 | **627** | 625 |
| 5 | 678 | **678** | 625 |
| 8 | — | — | 625 |

Room is 625. Each body adds a checklist row of **~51px**, so the page went over
at four bodies, shop or no shop, and the stack has no upper bound.

**The fix is a ceiling, and the load-bearing line is one flag.** `_verify_box`
sits in its own `ScrollContainer` (`Overworld2._verify_scroll`), whose height
`_fit_checklist` sets to the smaller of the checklist and the room the left column
has left under the window, never less than `CHECKLIST_FLOOR` (~two rows). The
earlier attempt at exactly this took an empty board's page to 1928px. The cause
was the scroll's **horizontal mode**: left on AUTO, the scroll lays its child out
at its minimum width, every autowrapped goal wraps a word a line, and the height
the cap is computed from is nonsense. With `SCROLL_MODE_DISABLED` the scroll hands
the box its own width. `test_a_crowded_board_does_not_push_the_page_past_the_window`
asserts that directly (the box is as wide as the scroll), because it is the half
that fails without anyone noticing.

The budget is read off the live page rather than a constant: the scroll's height,
less the page outside the two columns, less the rest of the left column. A taller
window gets a taller checklist, and anything else in the left column that grows
is paid for out of the checklist. It refits on the box's and the left column's
`minimum_size_changed` and on the page scroll's `resized`, deferred and coalesced.
A change under a pixel is ignored, so its own resize settles in one step.

Shrinking the row was the alternative and was rejected, as before: it buys a fixed
number of bodies and then loses to the same arithmetic.

The shop fit test now stands **eight** extra bodies instead of clearing the board.

---

## Where the fixed items are written up

The original pass and everything it changed are in [`CHANGELOG.md`](../CHANGELOG.md),
newest first — the start screen, Map vs Optimal Path, the toasts, the design
tokens and z-order registry, the collapsing detail panes, the star chart's
ambient links, the run's menu, and the dropdown palette. [`README.md`](../README.md)'s
"Screens & flow" section is the current description of how each screen works.
