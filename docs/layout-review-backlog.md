# Layout review — what is still open

A UI/layout pass was done over every screen in the game: the twelve screens were
captured at the shipping canvas, measured, and read against the code behind them.
Most of what it found has been fixed (see the top of [`CHANGELOG.md`](../CHANGELOG.md)
for what and why). This is the remainder, written down so it can be picked up
cold in a later session.

Each item says **what** is wrong, **why it matters**, and **what it would take** —
because the sizing is the part that is expensive to re-derive.

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

## 1. The tier list is on a different palette from the game

**What.** `TierListScreen.TIER_COLORS` is the stock tiermaker ramp — pastel
red / orange / yellow / green / blue / purple — inside a game with a deliberate
warm ember-and-parchment palette (`UITheme`). `UNRANKED_COLOR` is a muted brown
that does match, which makes the six above it look more borrowed, not less.

**Why it matters.** It is the last screen in the project drawn in colours that are
not the project's. The modal surface (`ModalScaffold.PANEL_BG`) and every popup
were brought onto the palette in this pass; these were not.

**What it would take.** One const array. The real work is the decision, not the
edit: S/A/B/C/D/F *as a convention* is legible precisely because it is the same
ramp everyone else uses, so replacing it with six warm tones may cost more than
it buys. Worth putting the question before doing it. If it changes, the tier
buttons in `RateGameModal` and the move-to row read the same colours.

## 2. The type and spacing scales cover the run screens only

**What.** `UITheme` gained a type scale (`FONT_MICRO` … `FONT_HERO`), a spacing
scale (`GAP_NONE` … `GAP_SECTION`) and a z-order registry (`UITheme.Layer`), and
nine run screens were migrated onto them — 129 font sizes and 88 gaps. The other
~31 screens still hold bare integers: `Collection.gd` (2518 lines),
`AtlasView.gd` (2794), `RunOverScreen.gd`, `LootDropModal.gd`, `EventModal2.gd`
and the rest.

**Why it matters.** It is the reason layout changes are expensive here. "Give this
column 26px back" means auditing eight numbers by hand and writing a comment
explaining each — which is exactly what the overworld's own history records.

**What it would take.** Mechanical, one file at a time. The scale holds the values
already in use, so a migration is a pure rename with no visual change and no
re-fitting. `test_design_tokens.gd` has the machinery: add the file to `MIGRATED`
and it will fail on any bare integer left behind; genuinely off-scale values go in
`OFF_SCALE_ALLOWED` with a reason. Most of those are gaps that are load-bearing to
the pixel on the 720p-budgeted page — do not snap one to the nearest step.

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
