# Layout review — what is still open

A UI/layout pass was done over every screen in the game: the twelve screens were
captured at the shipping canvas, measured, and read against the code behind them.
Most of what it found has been fixed (see the top of [`CHANGELOG.md`](../CHANGELOG.md)
for what and why). This is the remainder, written down so it can be picked up
cold in a later session.

Each item says **what** is wrong, **why it matters**, and **what it would take** —
because the sizing is the part that is expensive to re-derive.

**Eight items, of which six are open.** §1 is **decided** (keep the tier-list
palette) and §2's font half is **done** (all 47 screens on the type scale); both
are kept here with their reasoning rather than deleted, so neither gets asked
again. A closed item says so in its heading.

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

## 2. The spacing scale covers the run screens only — fonts are done

**Done: fonts, project-wide.** All 47 screens that set a font size in code now
take it from the type scale; 259 bare integers became named steps in one pass.
Every replacement was value-preserving by construction (each integer mapped to the
token holding exactly that integer, and the diff was read back to prove every
changed line round-trips byte-identical), so nothing moved and nothing needed
re-fitting. `test_design_tokens.gd` keeps it that way with `MIGRATED_FONTS`, and
that list is asserted **complete** against a walk of `scripts/` — a new screen
cannot ship bare integers by not being on it.

**Still open: gaps, ~38 screens.** `MIGRATED_GAPS` is the original nine run
screens. `Collection.gd` (2518 lines), `AtlasView.gd` (2794), `RunOverScreen.gd`,
`EventModal2.gd` and the rest still type their separations at the call site.

**Why it matters.** It is the reason layout changes are expensive here. "Give this
column 26px back" means auditing eight numbers by hand and writing a comment
explaining each — which is exactly what the overworld's own history records.

**What it would take.** One file at a time, and **slower than the font pass was**:
a gap is not a free rename. Several on the run screens are load-bearing to the
pixel on the 720p-budgeted page, so each one has to be read before it is named —
do not snap one to the nearest step. Add the file to `MIGRATED_GAPS` and the test
will fail on any bare integer left behind; genuinely off-scale values go in
`OFF_SCALE_GAPS` with a reason.

**What the font pass turned up, which is the other half of this item.** Five sizes
have no step on the scale, so they were left as literals in `OFF_SCALE_FONTS`
rather than silently restyled — naming them means *changing* them, and a restyle
does not belong in a rename. Each is an open question:

| size | uses | where | the question |
|---|---|---|---|
| 17 | 11 | eight `SettingsModal` section headings, plus `AtlasView`, `RouteLadder`, `RunOverScreen` | `FONT_HEAD` is 18. Snapping is a 1px restyle on a modal nobody has re-fitted — the biggest cluster and the likeliest yes |
| 24 | 7 | seven screen/modal titles | sits between `FONT_TITLE_LG` (22) and `FONT_DISPLAY` (26); second-biggest group |
| 21 | 2 | `EventModal2`, `ItemInfoCard` titles | between `FONT_TITLE` (20) and `FONT_TITLE_LG` (22) |
| 30 | 1 | `Collection`'s screen title | every other screen's title is 20 or 22, so this one is drift rather than a decision |
| 34 | 1 | `RunOverScreen`'s verdict | the largest type in the game; a genuine one-off, and arguably fine as one |

Two ways to close it: snap each to its nearest step (a real visual change — fit
must be re-checked with the `verify` skill, not reasoned about), or promote the
ones that are doing a job into named steps. 17 and 24 together are 18 of the 22
uses, so they are the decision; 30 is almost certainly just a stray.

## 3. The Collection's grid

Three separate things on the screen where 865 covers are browsed. It is the
second-most-used screen in the game after the run itself.

**a. The grid is bottom-clipped with no scroll affordance.** The second row of
cards is cut flat at the panel edge and nothing says more is below — there *is* a
scrollbar, but it is a hairline you have to hunt for. A fade, a partial row, or a
visible bar would each answer it.

**b. The beaten-checkbox sits on top of the cover art**, top-left of every cell.
It is the one piece of state each cell carries and it is drawn over the one thing
that identifies the game.

**c. Cover aspect ratios vary wildly** — some 4:3, some square, some tall — so the
grid is ragged. The cells are uniform; the art inside them is not. Letterboxing
into a fixed box, or cropping to a common ratio, would settle it. Worth checking
what that does to pixel-art covers first (`UITheme.is_pixel_art` exists for
exactly this kind of decision).

## 4. The tier list's `Unranked` lane does not line up

**What.** Its label tile is narrower than the six above it and its lane starts
about 17px further left.

**Why it happens** (this is the part worth not re-deriving): `_build_tier_row`
puts a `LineEdit` in the label cell, because a tier can be renamed.
`_build_unranked_row` puts a plain `Label` in it, because "Unranked" cannot. Both
set the same `custom_minimum_size` of `LABEL_CELL * _scale`, but a `LineEdit` has
a larger intrinsic minimum width, so the tier cells are pushed wider than the
minimum and the Unranked cell sits exactly on it.

**What it would take.** Measure both at runtime first — do not guess at the
number. Then either give both cells the same computed width, or give the Unranked
cell a control with the same intrinsic minimum.

## 5. The tier list has no empty state

**What.** With nothing rated, the board is six empty lanes and (since the detail
pane now collapses) nothing else. It does not say what puts a game on it.

**Why it matters.** Rating is strictly opt-in and only ever offered from the haul
screen's `★ Rate this game`, so a player can reach this board with no idea how to
fill it.

**What it would take.** A line in the empty region naming the one way in. Small.

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

**What it would take.** Either put the real colours in the scene and delete the
re-skinning, or accept that the scene is a skeleton and make the lookups fail
loudly (`get_node` rather than `get_node_or_null`, or a `@onready` with `%`
unique names). The second is smaller; the first is the one that makes the scene
honest.

## 7. The main menu is the emptiest screen in the game

**What.** A 320px column centred in a 1280px canvas — see the capture in the
original pass — in a game whose entire content is 865 pieces of cover art.
`Continue (no saved runs)` takes a full row to say nothing.

**Why it matters.** It is the first screen anyone sees and it says the least of
any screen in the project.

**What it would take.** This is a design question, not a fix. Worth asking before
building: whether the menu should show anything of the collection behind it, what
happens to the disabled Continue row, whether the profile row and How to Play
belong where they are. Treat it the way the start screen was treated — question
first, then build.

## 8. Character picker nits

Three small things on one screen:

- **Row 1 of the roster grid is ~14px taller than rows 2 and 3**, because
  "Antonio Belpaese" wraps to two lines and nothing sets a uniform tile height.
  `TILE_SIZE` is a minimum, not a fixed size.
- **The detail panel is top-aligned with roughly 180px of void beneath it.**
- **`Cancel` / `🎲 Random` sit about 480px from `Confirm`** at the other end of
  the footer.

None is load-bearing; together they are why the screen reads as unfinished next
to the start screen it now sits before.

---

## Where the fixed items are written up

The original pass and everything it changed are in [`CHANGELOG.md`](../CHANGELOG.md),
newest first — the start screen, Map vs Optimal Path, the toasts, the design
tokens and z-order registry, the collapsing detail panes, the star chart's
ambient links, the run's menu, and the dropdown palette. [`README.md`](../README.md)'s
"Screens & flow" section is the current description of how each screen works.
