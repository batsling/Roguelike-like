# Streaming: the OBS overlay, the clock and the radio

The build is stream-first, and this is everything about the stream side: setting
up the browser sources, sizing and scene layouts, the speedrun clock, the route
map source, what the lost-run forecast on the hero card means, and how the page
is tested. Roguelike Radio has its own page,
[`roguelike-radio.md`](roguelike-radio.md) (its §7 is the streamer's set-up).
The overlay's design history is §9 of
[`games-first-redesign.md`](games-first-redesign.md). This page was the README's
"The stream overlay" section until the README was split on 20 Oct 2026.

## Setting it up

The build is stream-first: the "combat" is you going off and playing a real game,
so for most of a stream **the Godot window is not on screen at all**. The overlay
is what the audience sees instead — and what tells them why this person is
playing Hollow Knight right now, and what happens if they fail.

It is **not a second Godot window**. `ObsCompanion` mirrors the run onto disk and
OBS renders the page:

```
user://obs/overlay.html   the page          ┐ reinstalled from obs/ at
user://obs/overlay.css    its styling       │ EVERY boot — edit the repo's
user://obs/overlay.js     its ticker        ┘ copies, not these
user://obs/top.html       ┐
user://obs/bottom.html    │ one page per source, GENERATED from overlay.html
user://obs/goals.html     │ at every boot — this is how you ask for a part of
user://obs/road.html      │ the page (see "One file per source" below)
user://obs/map.html       │
user://obs/timer.html     │
user://obs/radio.html     ┘ (the only one that makes a sound)
user://obs/custom.css     yours — created empty once, never overwritten
user://obs/state.js       the run, as `window.OBS_STATE = { … }`
user://obs/covers/        every picture the page shows, staged beside it
user://obs/radio/         the radio's current track, staged beside it
```

**Setting it up.** Settings → *Stream overlay* → tick "Mirror the run for OBS",
and copy the path it prints. In OBS: **add a Browser Source, tick "Local file"**,
point it at that `overlay.html`, and size it **352 × 880**.

(880 rather than a round number: the page tops out at ~781 on a pathological run
and the ticker needs ~91px of slack under it — see the tables below. A taller
source is harmless, just transparent. It was 680 before the speedrun clock,
which adds a card of its own — see "The speedrun clock" below.)

**Do not resize the scene item.** The Browser Source's own Width/Height is the
canvas the page renders into; stretching the item afterwards resamples the result
and softens the pixel art. Set 352 × 880 and leave the transform at 100%.

**The cards are a tint, and the text carries its own ground.** The card sits at
**0.30** alpha, so **70% of the capture survives** — the panel reads as a wash
over somebody's gameplay rather than a slab on top of it.

**`backdrop-filter` is not part of this page, and never worked where it runs.**
An OBS Browser Source renders to a *transparent texture* and OBS composites the
scene behind it afterwards, so inside the page there is nothing behind a card to
filter. Measured: screenshot the page with `omitBackground` and the card pixels
come back at the card's own alpha to three decimals — the filter contributed
exactly nothing. It only ever darkened the white page behind a **double-clicked**
`overlay.html`, which is why "glass" looked right to everyone who checked it that
way and like a flat brown slab on an actual stream.

That invalidated every contrast figure this page has ever carried, the **4.73**
quoted in three documents and the **4.96** that briefly replaced it alike: both
were measured with the capture *inside* the page. Composited the way OBS does it,
the 4.96 page scored **3.00**, and the old 0.45 "glass" scored **3.90** while
letting 55% through.

So the filter is **gone** rather than kept as decoration. A declaration that does
nothing where the page runs and something where it is previewed is precisely how
this survived two redesigns. What is left behaves identically in both places:

- **An alpha.** 0.30, swept against the sampler rather than chosen — 0.25 lands at
  4.2 and 0.20 at 3.9 even with the halo at full strength.
- **A halo on every glyph** (`--halo`), a stack of hard dark shadows, so what sits
  behind the strokes travels with them whatever the game is doing.
- **One real scrim**, on the cost line only. The sampler said `.cost-total` was
  the single thing the halo could not carry — the smallest bold text in the
  page's lightest colour, at 4.41 while everything else cleared — so that line
  gets a dark ground of its own instead of the whole page spending see-through to
  rescue it.

**`check_overlay.js` measures it the way OBS composites**: screenshot with
`omitBackground`, composite over a dark, a mid and a bright capture *outside* the
page, then split each line of text into glyph and ground by luminance and take
the ratio. Worst text on the page: **4.81:1** against an AA bar of 4.5. It also
asserts `backdrop-filter` stays `none`, so re-adding one fails here rather than
looking nice on somebody's desk.

**How tall the page gets.** It is content-height, so it grows with the run — the
figures below are the real page measured at **352 wide** (the heavy column is the
fixture `tools/check_overlay.js` asserts on; the others are that fixture scaled
up and down), and the last column is the one to size a source against.

| | light run | median | heavy (hour three) | pathological |
|---|---|---|---|---|
| `overlay.html` | 615 | 674 | 716 | **782** |
| `top.html` | 273 | 328 | 386 | **452** |
| `bottom.html` | 310 | 346 | 346 | **346** |
| `goals.html` | 310 | 346 | 346 | **346** |
| `road.html` | 116 | 116 | 116 | **116** |
| `timer.html` | 130 | 180 | 224 | **300** |

**Only the heavy column is measured and asserted** (`check_overlay.js` pins it,
so a card added or lost fails there rather than quietly making this table
wrong); the rest are that fixture scaled. The clock card is 93px with no splits
banked and grows by ~21px a split until the list hits its own cap
(`--split-height`, 96px by default), so a run's first game costs the page about
93px and a long run about 195.

**These are taller per row than the 440 column was, and that is the trade.** The
checklist went to 15px text on a column 88px narrower, so a long goal takes one
more wrapped line than it did — the page is a similar height while showing fewer,
larger rows. That is the point: a row you cannot read across a room is not a row.
The density pass that took the text to 13px went the other way and this reverses
it.

**The row itself is a 32px picture and its text, and nothing else.** The `□`/`✓`
checkbox each row used to open with is gone: it spent 21px of every row (the box
and its gutter) saying what the row already says twice — a finished goal is
struck through, dimmed, and its art drained to greyscale, and the row flashes
green at the moment it is crossed off. The art moved into that space and grew
from 24px to 32px, so the list opens on a column of faces. That is where the
28px this column lost came from: the checklist has more room for text than it
had at 380, not less.

**Almost nothing moves within a run size.** Everything that used to grow the page
is gone: the hero card's status strip (every status is a checklist row now), the
cost line's strip of swing marks (it is a label and two numbers), and the shields'
labelled row (they sit beside the health bar). `bottom.html` and `goals.html` stop
at 346 because the scroller is capped and walks the rest, and `road.html` is 116
whatever the run's length — a longer road is a wider strip, not a taller one.

**Below ~350 wide the headline stops being two columns** and stacks back into the
current game over the destination. At 352 each half has ~141px for its title,
which is still two words; take another 40 away and it is one word and an
ellipsis on both sides, which is worse than the stacked row the columns replaced.
**352 rather than a rounder 350 is deliberate** — 350 sits *on* that breakpoint,
and a default one rounding error away from rendering the other layout is a
default nobody has tested.

The one thing left that can push it is **the shields wrapping past the bar**:
about five fit on the line beside it before they take a second row. "Pathological"
above is thirty of them, which no run realistically reaches.

**The ticker is not in those numbers, on purpose.** It is pinned to the bottom of
the browser source and grows upward — at most three toasts, ~91px — so a burst
floats over the foot of the page instead of pushing it out the bottom of the
source, which is what used to happen, silently, at exactly the busiest moment of a
run.

**586 + 91 is where the 680 above comes from**: at that height a burst of toasts
lands in the slack under the page and never touches it, on any run. Shorter than
that and they float over the foot of the checklist for six seconds at a time,
which is survivable but avoidable. Taller is transparent either way.

## Stretching it

**The page fills whatever canvas the Browser Source gives it.** Widen the source
and the text columns take the slack — the covers, the art and the type stay their
own size, which is what "wider" should mean for a page that is mostly sentences.
Note that **wider is not bigger**: stretching does not change the type size, so if
the overlay reads *small* on a 720p stream that is `zoom` (below), not width.

**Vertically it is content-height by default**, which is why the tables above are
promises: the page is exactly as tall as the run makes it and a taller source has
transparent space under it. Add **`#fill`** to take the whole source instead —
the checklist grows into the slack, so a 900px source shows about eighteen rows
standing still where 620 shows nine. That is the only part of the page that wants
the room; everything above it is a fixed number of lines.

**To make the checklist SHORTER**, put `#overlay { --goal-height: 180px }` in
`user://obs/custom.css` — that is the scroller's ceiling (260px by default), and
the walker brings the rest of the list round rather than dropping it. Two more
knobs trade legibility for rows in the same space: `--goal-text` (15px) and
`--goal-art` (32px). Shrinking the card is the right lever here; scaling the OBS
scene item resamples the pixel art instead.

**To rename the chat command**, edit the `.lookup` line in `obs/overlay.html` —
it is plain text in the page, not something the game sends, because the game has
no idea what anyone's bot is called. If you would rather not touch the installed
file (it is overwritten from `res://obs/` at every boot), hide it from
`user://obs/custom.css` with `.lookup { display: none }` and put the command in
an OBS text source instead. Whatever it says, keep it to **one line**: it is the
only text on this page a viewer has to read character by character and type, and
`check_overlay.js` fails if it wraps or clips.

**And to change how see-through it is**, `#overlay { --card-bg: rgba(26,20,16,.2) }`
for more game, `.45` for more tint. That alpha is the only lever — do not reach
for `backdrop-filter`, which does nothing in OBS (above). Run
`node tools/check_overlay.js` after touching it: the contrast check composites
the way OBS does and will tell you exactly what you just spent.

`#fill` is a *modifier*, so it combines with the fragments below and any separator
works: `overlay.html#fill`, `bottom.html#fill`, `map.html#fill`.

To stop the column growing past a width you choose, put
`#overlay { --max-width: 352px }` in `user://obs/custom.css`.

## The speedrun clock

A run here is a stack of real games played one after another, which is a
speedrun with unusually long splits — so it is timed like one. `RunTimer` keeps
three numbers and the overlay draws all three:

- **this game's split**, with tenths, because a moving digit is what tells a
  viewer the clock is live rather than a frozen number on a dead overlay;
- **the run's total**, which keeps running across the gaps between games (the
  offering, a shop, an event) because those are time the run took;
- **a banked split per game finished**, tinted by how the board closed on it —
  green beaten, orange missed, ember escaped — with `×N` for how many tries it
  took.

**It starts when the run STANDS ON a game**, not when the ▶ Play button is
pressed: that button only exists for games with a launch target authored
(`GameData.has_launch_target`), a small minority of the roster, so a clock hung
off it would read zero for most of a run. It stops when the game is reported —
beaten, missed *or* escaped, all three being the board closing.

**A lost attempt does not stop it.** A speedrun clock counts your failures. What
happens instead is that the attempt is banked as its own split, so a game's entry
reads as the list of how long each try at it took; undoing an attempt
(`GameLoop2.undo_attempt`) hands that time straight back, because an undo puts
the whole run back to before the tick and the clock is part of "before the tick".

**Time accumulates only while the game is running** — a `_process` sum, not the
difference of two timestamps — so a run left open overnight comes back where it
was rather than eight hours heavier. It rides the save, so a run played over
three evenings is one run.

**The page ticks it itself.** The payload carries a reading, not a stream: the
running seconds are deliberately excluded from `ObsCompanion`'s content dedupe
(otherwise every payload would differ and `state.js` would be rewritten four
times a second for a run in which nothing else moved), and `overlay.js` counts
forward from the moment the reading arrived — measured against its own
`performance.now()` rather than the payload's `at`, so a clock skew between the
game's machine and OBS cancels instead of showing. Every write re-bases it.

The same numbers are drawn beside the cover in the game's own Now Playing panel,
because a clock that only exists inside OBS is a clock the player has to alt-tab
to read.

## One file per source

The overlay is one column, but a scene usually wants the camera partway *down*
that column rather than under all of it — and OBS cannot interleave scene items
with the inside of a browser source. So the page renders part of itself, and
**each part is a file you browse to**:

| Browse to | Shows | Size |
|---|---|---|
| `overlay.html` | everything except the road and the map | 352 × 880 |
| `top.html` | the run card **and the clock** | 352 × 500 |
| `bottom.html` | checklist + ticker | 352 × 442 |
| `goals.html` | the checklist, and nothing else | 352 × 352 |
| `road.html` | the road walked so far | 352 × 116 |
| `map.html` | the road **ahead**, as a ladder | **2560 × 1440** (drawn 1:1 there; scale it in OBS) |
| `timer.html` | the speedrun clock and its splits | 352 × 360 (bigger type here — it is a source of its own) |
| `radio.html` | **Roguelike Radio**: the now-playing card, and the music itself (`docs/roguelike-radio.md`) | 352 × 100; set its Audio Monitoring to "Monitor and Output" to hear it |

**`top.html` + `bottom.html` is the whole default page, exactly once.** Every
card belongs to one of the two — the clock rides `top` with the run card — so
running both sources side by side does not give you two clocks ticking at each
other.

Add a Browser Source, tick **Local file**, browse to the one you want. Point
**several** at different files and put whatever you like between them; they read
the same `state.js`, so they stay in step for free.

**These are generated, not authored.** Each is `overlay.html` with one line in
front of it — `window.OBS_VIEW = "map"` — written by `ObsCompanion._install_views`
at every boot, so there is exactly one copy of the markup in the repo and the
six view pages cannot drift from it.

**Why files and not `overlay.html#map`.** That was the original mechanism and it
is unusable in the only program it was for. With **Local file** ticked the field
is a *path*, not a URL, so the `#` is escaped and never becomes a fragment — and
unticking it to paste a `file:///…#map` URL into the URL box does not arrive
either. It worked in a browser, was asserted in `check_overlay.js`, documented
here, and could not be typed into OBS. If you have existing sources using a
fragment they still work — the page unions the two — but nothing needs one now.

**`#fill` is the one fragment still worth typing**, because it is a *modifier*
rather than a choice and combines with any of the above: `goals.html#fill` makes
the page take the whole source instead of being content-height, and gives the
slack to the checklist.

**`goals.html` and `bottom.html` differ by the ticker alone**, and that is the
whole reason `goals.html` exists. The ticker is pinned to the *bottom of the browser
source* and grows upward, so on a source sized to the checklist a burst of toasts
lands on the checklist for six seconds at a time. That is fine on the full column,
where they float over the foot of a page with slack under it, and not fine on a
source that *is* the list. Point a source at `goals.html` when the checklist has to
sit in a scene beside something else — it needs no cropping, and the run card,
the ticker and the road are all simply not drawn. The two measure the same height
because the ticker never contributed to it; what changes is what paints over it.

**The road is opt-in**, and it is the only piece that is. It is a horizontal
scroller, and at this width it could not be read: measured on a 22-stop run at
440, the stop
the player is standing on was fully on screen for **6 seconds in every 50** and
took 42 seconds to first appear — and every change to the road reset the walk to
the *start* of the run, which is exactly when a viewer looks up. What the road
uniquely says (which games were beaten, which the run walked away from) is worth a
source of its own on a between-games scene, at a width where it does not have to
scroll at all — a 22-stop run is 1008px wide. The **distance** it used to carry is
now on the headline, in a number that never moves.

## The route map — `map.html`

**The road's opposite number.** `road.html` is where the run has *been*: one cover
per stop, a sequence. `map.html` is where it can *go* — every optimal road from the game
in play to the Amulet — and it is a **graph, not a strip**, which is the whole
reason it is not just the road pointed the other way.

`RunGraph.shortest_path_dag()` answers in **layers, two or three games wide**:
there is usually more than one equally short way on, and choosing between them —
same distance, different goals, different loot — is the run's core decision. A
single line would draw a forced march and hide the only interesting thing on the
map. So it is drawn the way `RunMapModal` draws it in-game: rungs in layers, green
arrows between them — **straight lines with heads on them**, because a wire lives
entirely inside the gap between two layers where no box can be, so the curves this
started with were dodging a collision that cannot happen and read as wobble. The
head is what says the graph has a direction. Same colours as in-game
(`RouteLadder`'s blue for where you are,
ember for the Amulet, cyan for a rift).

**It runs left to right, and it is a full-screen source.** You on the left, the
Amulet on the right, each layer's choices stacked above one another — the way
the in-game maps run too, since the map redesign. Distance belongs on the
**long** axis. A 14-layer route gets 137px per layer across 1920 and only
77px down 1080, and the choices within a layer — never more than a handful — are
what the short axis is for. It also matches the road strip, which has always run
the same way.

It is a source you **toggle**: what you cut to while deciding where to go next,
not something a viewer needs on screen the whole time. Hide it in OBS, or put it
on a between-games scene.

| | |
|---|---|
| Source size | **2560 × 1440** — the stage it is drawn at, so this size renders 1:1 |
| Smaller sources | fine — the whole stage is scaled down to fit; never cropped |
| Bigger, or zoomed in OBS | the pixels are already there, which is the point of the stage |
| Changing the stage | `#overlay.only-map > .map { --stage-w: …; --stage-h: …; }` in your `custom.css` |
| Depth it holds | 14 layers, then it says `+N more layers … not drawn` |
| Deeper than fits | boxes shrink to a legibility floor, then the ladder scales |

**The map is drawn at a fixed stage and scaled into the source, and it is the only
piece here that is.** The ladder used to be solved into the *source's* own pixels,
which is right for a panel in a column and wrong for the one source people zoom: a
480-wide source drew a 480-wide ladder, and cranking that up in OBS enlarged 480
pixels of cover and type. Now the layout is always 2560 × 1440 and one transform
scales the whole stage into whatever source it is given — so scale the scene item
down to park the map in a corner and back up to read it, with the render already at
size either way. Keep the stage's **aspect** matching the source's, or the fit
leaves transparent bars on the short axis; the map is centred, never stretched.

**Everything is sized from one number, and that is what makes it readable.** The
rung's width is solved for from the room the source gives it — on *both* axes,
since a shallow wide route is bound by its tallest layer and a deep narrow one by
its length — and the covers, the type, the gaps and the arrow weight are all
fractions of it. The ladder is the same object at 100px and at 300px.

**It used to be 152px forever.** The first version had a fixed rung and a fit that
only ever scaled *down*, so a 1920 × 1080 source drew exactly the ladder a 640
one did and surrounded it with a thousand pixels of empty card — going full screen
made the map **worse**. Nothing caught it, because every assertion was about the
ladder fitting *inside* the panel, which an under-sized ladder satisfies
perfectly. `check_overlay.js` now asserts the rung, the cover and the name are all
materially bigger at 1920 than at 640, and that the ladder fills at least 70% of
one axis.

**Every rung is a cover and a name, the way the in-game boxes are.** The cover
fills the whole box — cropped from near the top, where the title art lives, never
letterboxed — and the name sits on a dark band across its foot, up to two lines.
The cover is what a viewer recognises — box art is how anyone reads a shelf — and
the name is what they can actually search for, which is most of the point of
putting a map on a stream. The game's **node kind** (combat, event, shop…) is a
badge straddling the top-right corner in the kind's own colour, exactly where
`RouteLadder.kind_marker` puts it; `Here` / `Amulet` / `Beaten` / `Rift` is a
small tag top-left. A game you have **already beaten** is drained to greyscale and
tagged, because revisiting is legal and its goal is rolled fresh, but you know the
game.

**The layers are scattered, not stacked in a block**, the same as in-game: each
column spreads down the height it is given, its order comes from
`RouteLadder.order_layers` (so arrows cross as little as they can), and every
inner box is nudged by `RouteLadder.jitter` — the same per-game nudge the in-game
map uses, sent in the payload as `nudge`, so a game sits off-grid the same way on
stream as on screen. The start and the Amulet stay put.

**It shows the shortest road**, the same `RunGraph.shortest_path_dag` the in-game
maps draw. (A game could once be *pinned* to bend the route through it; that was
removed, so there is only ever one road to show.)

**Two empty states, two different sentences.** Standing on the Amulet says so
("The Amulet is under your feet"); no road at all says *that* instead. Neither is
a blank panel, which is what a viewer reads as a broken source.

`#offline` is in none of these lists, so a source that is up before the game is
still says so. The ticker rides with `bottom.html` and not with `goals.html`.

## A scene layout that fits

**C — camera inside the overlay column.** The recommended one: the camera sits
between the overlay's halves, and the game keeps 81% of the width.

| Source | Position | Size |
|---|---|---|
| Game capture | `0, 0` | `1560 × 877` (16:9) |
| **Overlay `top.html`** | `1564, 0` | `352 × 262` |
| Camera | `1564, 274` | `352 × 198` (16:9) |
| **Overlay `bottom.html`** | `1564, 482` | `352 × 442` |
| **Overlay `road.html`** | `1564, 936` | `352 × 116` |
| Chat | `0, 885` | `1560 × 195` |

**The narrower column gives the game 88px back**, which is the point of the pass:
the capture goes from `1472` to `1560` wide, and the camera under `top.html` from 248
to 198 tall — it is 16:9 of the column, so it shrinks with it, and the room that
frees goes to the checklist below. 262 + 198 + 442 + 116 is 1018 of the 1080, gaps
included, and the road still fits.

`top.html` gets 262 against a ceiling of 256 — it grew from 234 when the checklist's
text did, so this is the row with the least slack in the column. `bottom.html` gets
442 rather than its content height of 346 because the ticker is pinned to the foot
of its source: the extra 96 is where a burst of toasts lands instead of on the
checklist. If you would rather not spend it, use **`goals.html`** at `352 × 352` —
same list, no ticker — and give the road the difference.

**Chat still cannot go in the column.** 162px of chat is still not chat. It goes in the
bar under the game, or on a second monitor. If chat *must* sit directly under the
camera, that is a second sidebar and the game pays for it — see A.

**A — three columns, nothing overlaps.** Camera top-left, chat directly under it,
overlay on the right.

| Source | Position | Size |
|---|---|---|
| Camera | `0, 0` | `384 × 216` |
| Chat | `0, 224` | `384 × 856` |
| Game capture | `392, 200` | `1152 × 648` (16:9) |
| **Overlay** | `1552, 0` | `352 × 680` |

The game drops to 60% of the width and the middle column carries ~430px of dead
band above and below it — the unavoidable cost of two sidebars with a fixed 16:9
rectangle between them.

**B — full-bleed game, columns over its edges.** Game `0, 0` at `1920 × 1080`;
camera `16, 16` at `384 × 216`; chat `16, 240` at `384 × 700`; overlay
`1552, 16` at `352 × 680`. The game keeps every pixel and the columns cover ~20%
of the width at each edge. The games on this map are *real* games with their own
HUDs, so check the one you are about to play — a minimap in a covered corner is
the failure case.

Either way the columns can swap sides; nothing on the overlay cares which edge it
is on.

**If the overlay reads small** for viewers on 720p or a phone, don't scale the
scene item — put `#overlay { zoom: 1.25; }` in `user://obs/custom.css` and set the
Browser Source to **475 × 800**. `zoom` re-lays the page out at the larger size,
so the text is rendered crisply rather than resampled, and the sprites stay sharp
because everything pixel-art on this page already carries
`image-rendering: pixelated`.

**Why a script file and not JSON over `fetch()`.** OBS renders the page from a
`file://` URL, and Chromium refuses every `fetch()`/XHR a `file://` page makes at
a sibling file — there is no origin to grant, so it is a CORS failure with no fix
short of launching OBS with `--allow-file-access-from-files`. A `<script src>`
has no such restriction. So the state is written *as* an assignment and
`overlay.js` re-loads it four times a second with a cache-buster on the end. No
server, no port.

**And nothing the page loads may point outside its own folder**, which is the
other half of the same rule and cost a stream to learn. The covers used to travel
as absolute `<img src="file:///…/images2.0/games/x.png">`, straight at the repo or
at the `.pck` extraction. Chromium treats an absolute `file://` URL as a *local
resource load* and refuses it from any document that is not itself `file://` —
and **OBS does not serve a local page as a `file://` document**. So the overlay's
text was perfect and every single picture on it was missing, in the one place the
overlay is ever used. Double-clicking `overlay.html` to check *makes* it a
`file://` document, so the page looked fine everywhere except in OBS.

`state.js` never had the bug, because the page pulls it as a **sibling**: a
relative URL resolves against whatever base the browser gave the document. The
art travels that way now — `ObsCompanion._stage()` copies each picture into
`user://obs/covers/` and the payload carries `covers/<hash>-<name>`. Only the art
a run actually shows is staged (a full run measured 135 files, 33 MB), the hash
prefix keeps the thirty-three duplicate basenames in `images/` and `images2.0/`
apart, and the Windows drive-letter hazard the old absolute URLs had to dodge
cannot arise in a relative one. If you restyle the page, keep it to relative
URLs; `tools/check_overlay.js` now serves the page over http and asserts every
`<img>` decoded, which is the only way this class of bug is visible.

**And the route map is a fourth source**, at `map.html`: the road *ahead*
as a branching ladder, drawn at a fixed 2560 × 1440 stage and toggled on when you
want it. See
"The route map" above.

**It is two cards, on a 352px column that is mostly the game.** The first is the
run: the game in play and the game the run is for, **side by side in two columns**
with the distance labelling the second,
then health with **the shields as sprites on the same line**, then **what the
next lost run costs** as a label and two numbers — `On next loss  −2 Shields,
−7 Health`, or `N/A` when nothing lands. The second is
**the checklist as it ticks**,
which is the page's centre of gravity: every row wearing its own art, scrolling
itself when there is more of it than there is room, flashing a row green as it is
crossed off. It is headed by **`!roguelikelike for challenge details`** and then
**THE GOALS** — the chat command first, because it is the answer to the question
the rows underneath it raise, and it is the only route off this page a viewer
has. **The road** walked so far, ending on the Amulet, is the same strip
`RunOverScreen` draws at the end of a run — it is drawn live but lives at
`road.html`, its own source, rather than on the default column.

**Every row of the checklist carries its own picture**, and that is the layout's
one big idea. A goal *is* an enemy (§7.2), so a body's row wears its face and, on
the corner of it, the damage that body lands if the run is lost; a status's row
wears its pip art and its stack total; a curse's and an event's wear theirs. **The
character's own goal leads the list** — `Level up — <condition>`, wearing the
portrait, with `Isaac · Level 3` under it. `ReportChecklist` has always drawn that
row and this page never did, so the one goal belonging to the *character* was the
one goal a viewer could not see; the portrait and the name live there now rather
than on a hero card of their own. It goes **first** here where the checklist files
it after the statuses, and that is deliberate: the report panel does not scroll, so
where a row sits costs nothing, while on a fifteen-body run this list does and a
row near the end is a row nobody watching ever sees. That
one change paid for three others — the hero card's status strip went (every
player-side status is claimable, so every one already had a row here, and the
strip was saying it twice), the cost line stopped drawing a *parallel* strip of
faces the viewer had to match against this one, and the six kinds of row stopped
being told apart by **text colour alone**, which was the weakest encoding on a
page read across a room through a lossy encode.

## What a lost run costs

The most important thing on the overlay, and the reason the hero card is shaped
the way it is. A lost run is not an abstract penalty: the enemies take a turn
(§3.2), every body that can reach you swings once, **one shield stops one hit
outright whatever that hit was for**, and the swings past your last shield are
what reaches Health.

That rule is invisible in a summed "12 incoming" — two shields against three
small swings is a completely different position from two shields against one
enormous one — so the page counts the two separately: **`On next loss  −2
Shields, −12 Health`**, with "Health" rather than "damage" because the bar
directly above says `7 / 20` and the two numbers a viewer has to connect should
have the same name. It was a sentence ("2 shields break, −12 Health"), which read
better and wrapped to a second line on a busy board — at the top of the card,
where a height that changes is a page that moves under a viewer who looked up for
two seconds. The same forecast
is hatched onto the health bar over the HP that would go, and one that would end
the run says so in words.

**Who is throwing each swing is answered on the checklist**, not here. This line
used to draw one mark per swing — the body's own face at 28px, badged with a
shield when the swing was eaten whole or with the damage when it was not — because
it was the only place the page said *who*, and the boss's swing and the fly's are
not the same problem. Now every body has a row in the checklist with its face and
its own damage on the corner, so the identity sits beside the sentence naming it
instead of in a parallel strip the viewer had to align against the real list by
eye. The art holds up at that size because the roster's is bold and
silhouette-driven — checked by rendering the widest range in the set (a 19×10
sprite through a 734×841 painting) at four sizes, not assumed. A row with no art
falls back to an initial; a test asserts every goal-enemy and boss has some, so it
doesn't.

**And a board that cannot reach you still does not make the line vanish**: it
reads `N/A`, in the blue it wears when there is nothing to be red about. A row
that disappears moves everything under it, which is the one thing this card must
not do.

The page used to spell out how long the quiet would last — *"nothing reaches you
for at least 2 more lost runs"* — and that is now the widest line on the card
spent on the least urgent thing it says. The number is still computed and still in
the payload as `threat.turns_away`, from `GameLoop2.turns_until_strike`, which is
`can_strike`'s own inequality (`_front_col <= 1 + strike_range`) solved for turns
so the two cannot drift. **It is measured against each body's own reach, never
against column 1**: a Ranged body swings from several columns back, and counting
steps to the front line would promise a quiet turn to somebody a Host can already
shoot. It is also a **floor** — a blocked lane, a stun, a turn spent on an ability
all make the real wait longer, never shorter. Anyone restyling the page can put it
back in a line of `overlay.js`.

`ObsCompanion._threat()` mirrors `GameLoop2._take_hit` step for step rather than
re-deriving the arithmetic — damage-taken mods first, a swing modded to nothing
spends no shield, Pierce takes both pools past, timed shields block first — and
excludes the bodies that sit a turn out (stunned, out of reach). Reach
is `can_strike`, not `in_front`: a Ranged body hits from further back. It is a
forecast, not a promise, since an ability can spend a body's turn on something
else, and **nothing in it mutates** — a test asserts the live shield pools are
untouched by forecasting, and another one takes the prediction and then makes the
board resolve a real `attempt_turn()` to check the Health that actually went.

Four things worth knowing if you change it:

- **A game has no goal of its own, so the overlay has no headline goal line.**
  The goals are the **bodies'** goals — every body following the run, not just
  the one that arrived with the game in play (§7.2) — plus what a status, an
  event or a curse is asking of the player. The checklist is the whole of it, and
  a row belongs to the body or the clause that owns it, never to the game.
- **Goal text is always `GameLoop2.goal_text_for`**, never `enemy.goal` — the
  resource's stem says nothing about the clauses a status has bolted on (§13).
- **Nothing on this page may guess at a rule the game owns.** The cost forecast
  mirrors `_take_hit`; the goal text comes from `goal_text_for`; the pip tint
  comes from `_status_pip`'s rule. An overlay that promises a shield will hold
  and then watches Health go is worse than one that says nothing at all.
- **The road says how each stop went.** Green for a game beaten on that visit,
  **orange (`UITheme.UNBEATEN`) for one the run walked away from** — a missed
  goal, an escape (§3.2), or a teleport that passed straight through without
  playing at all. One colour, because to the road they are one fact: you were
  there and the game is still standing. The same two colours are used by the
  overworld's own header strip and by `RunOverScreen`, all three reading
  `GameState.walked_outcomes()`.
- **Statuses and shields are drawn, not written.** They are `StatusData.image` /
  `UITheme.SHIELD_ART` with `UITheme.TIMER_ART` in the corner for anything
  borrowed — the same art as `BattlefieldView._status_pip`, quoted from the same
  constants so the board and the stream cannot disagree. The colour follows **what
  the side does** (gold for a `bonus`/`goal`, red for anything that taxes), never
  Buff/Debuff. The shields sit **beside the health bar** rather than in a row of
  their own: the labels existed to keep two strips apart, and with the statuses
  gone to the checklist there is nothing left to confuse them with — so they read
  as the armour standing in front of that health, and the page saves a line. A
  status rides its checklist row at 26px instead.
- **A status's row is one instance; its badge is the total.** `status_objectives()`
  is one row per instance (a permanent Strength 1 and a borrowed Strength 3 are
  two offers with two deadlines) while `status_list()` totals them, because what a
  stack *does* is felt as a total. The hero card's pip strip was the only thing
  carrying that total, so the badge on the row's art carries it now — that is the
  one thing cutting the strip could have lost, and a test pins it.
- **The rows are read from `GameLoop2`/`GameState`, never from `ReportChecklist`.**
  That is a Control tree which only exists while the overworld is on screen, and
  being right when the game window is behind a stream is the whole job.

**Testing the page itself.** `test/test_obs_companion.gd` pins the *payload* — its
shape, that no `Resource` escapes into it, that the swing forecast matches the
turn the board really takes. It cannot say anything about the page, because the
page is a browser and GUT is Godot. `tools/check_overlay.js` is the other half: it
renders `obs/overlay.html` in headless Chromium against a heavy synthetic run and
asserts the things that only exist once it is on a screen — that `hidden` really
hides, that the road's outcome colours survive the cascade, that the checklist and
the road actually walk while payloads keep arriving, that a burst of toasts stays
inside the browser source, that an undrawable payload is announced rather than
frozen over, and the heights the tables above promise.

Its last check is the odd one out and worth knowing about: it serves the same
fixture **over http** and asks every `<img>` whether it decoded. That is not a
question about the page at all — it is about the URLs `ObsCompanion` writes, and
it exists because every other check here, and every hand-check anyone ever did,
loaded the page as a `file://` document and so could not see the broken-art bug
above. If you are adding a check about art, make sure it runs against a page that
is *not* `file://`, or it is checking the case that already worked.

```bash
npm install playwright-core          # once
node tools/check_overlay.js          # --browser=/path/to/chrome if it can't find one
```

It is deliberately not wired into GUT — different runtime, different dependency —
so run it by hand when anything under `obs/` changes. Every check in it is a
regression that shipped once.

**And look at it with real content, not only the fixture.**
`tools/dump_obs_payload.gd` drives a real `Overworld2`, walks a few games, and
writes an actual `ObsCompanion.payload()` to JSON, which you can drop in beside
the page as `state.js`:

```bash
OBS_DUMP_TO=/tmp/obs_state.json godot --headless -s addons/gut/gut_cmdln.gd \
    -gdir=res://tools -gprefix=dump_ -gselect=dump_obs_payload.gd -gexit
```

The fixture is synthetic on purpose — it has to force states a real run reaches
rarely, and be reproducible. The cost is that it never disagrees with itself:
every fixture that ever exercised this page named its own hero, which is how
`_hero()` came to look the character up in `Data.get_character` (the two-strong
combat-era roster) while the run is dealt from `get_character2` (eleven). Ten of
the eleven drew a **nameless, portraitless hero card for an entire stream**, and
no test could see it because no test used a real character id. One real payload
showed it immediately. A test walks the roster now, but the lesson is the tool:
render the real thing occasionally.

`obs/` holds plain `.html`/`.css`/`.js`, which Godot does not treat as resources.
Running from source they are read straight out of `res://obs/`; if you ever
**export** the project, add `*.html, *.css, *.js` to the export preset's
"Filters to export non-resource files" or `ObsCompanion` will warn that the page
is missing. (`export_presets.cfg` is gitignored, so this cannot be committed for
you.)
