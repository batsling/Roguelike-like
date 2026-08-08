# Event sheet-authoring (`events2.0`)

Status: **the sheet format is settled and four events are authored. The
generator and the runtime are not built yet** — see §12 for what's left. Companion
to `games-first-redesign.md` and `locations-and-events-design.md` §6, which
argued events should wait for somewhere to live. §1 is that somewhere.

---

## 1. Why events exist: the dead end has to pay

Almost half the map is a dead end. Over the `connections` sheet as it stands:

| Connections | Games | Share |
|---|--:|--:|
| 0 (off-map, pruned) | 81 | 9.7% |
| **1 — a leaf** | **330** | **39.6%** |
| 2 | 199 | 23.9% |
| 3+ | 223 | 26.8% |

A leaf is a **round trip**: you spend a game getting there and a game getting
back out the way you came, and you are handed one game's worth of reward for two
games of run. Under the amulet-distance badge on every card (`route_note`, so the
cost is quoted to the player up front) that is not a choice, it is a mistake with
a label on it. The hub rule in `Overworld2` (`HUB_CONNECTIONS`) already
compensates for the *routing* half of this — it guarantees a way onward from a
big node — but nothing has ever made the leaf itself worth entering.

**An event is what the leaf pays.** It fires *after* the game there is beaten, on
top of the normal enemy drop, so the detour buys a second reward that the main
line does not offer. That single placement rule answers both of the questions
this sheet was opened for: where events go, and why anyone would walk into a
corner of the map.

It also sets the exchange rate. **A dead-end event should be worth roughly one
game's reward** — a Small Chest, a verb charge, a couple of Health — because one
extra game is exactly what the round trip costs. Pay less and the leaf is still a
mistake; pay more and the optimal line is to bounce off every leaf on the map.

---

## 2. The shape of the sheet: one row per EVENT

**One row per event, like every other `*2.0` sheet.** The choices live in
numbered column groups: `Choice 1 | Repeat 1 | Result 1 | Effect 1`, then the
same four columns for 2, 3 and 4. Twenty-eight columns in all — twelve for
the event, four groups of four.

```
Event         │ … │ Prompt        │ Choice 1 │ Repeat 1 │ Result 1  │ Effect 1              │ Choice 2 │ Repeat 2 │ …
Abyssal Baths │ … │ You discover… │ Immerse  │ Stay     │ The liquid│ gain_max_hp 1; lose…  │ Linger   │ Again    │ …
```

The one constraint worth understanding is **why the choices are columns rather
than one packed cell.** An event is mostly prose, and prose needs a cell of its
own — one you can widen, wrap, and read in the formula bar. Squeeze four choices
into a single delimited `Choices` cell and the cell stops being editable, which
is exactly how the old `events` sheet failed: catalogue metadata in the sheet,
and every choice, outcome and effect hard-coded in an `AUTHORED` dict inside
`tools/generate_event_tres.py`, because the sheet could not hold the part of an
event that *is* the event. Numbered groups keep every string in its own cell
*and* keep one event on one row.

What that buys, beyond the row count: the sheet **sorts and filters like the
others**. Sort by `Game`, filter to `Where = Dead End`, count rows to count
events — all the ordinary spreadsheet moves work, none of which survive a format
where one event spans several rows.

**Four groups is a soft cap**, picked to fit the real events (Abyssal Baths, the
widest one here, uses all four). A fifth choice is four more columns and one more
turn of the generator's loop, not a redesign. The generator reads groups left to
right and stops at the first blank `Choice N`, so an event with two choices just
leaves the last eight cells empty.

---

## 3. Columns

Twelve event columns, then `Choice N` / `Repeat N` / `Result N` / `Effect N`
for N = 1…4.

| Column | Scope | Meaning |
|---|---|---|
| `Event` | event | Display name, and the id everything else keys off. |
| `Game` | event | The real game this is lifted from. Flavour credit (the modal's "From: *game*" line), and the target when `Where` is `Game`. |
| `Tier` | event | `All`, or a comma list of `Low` / `Medium` / `High` / `Insane`. Gates an event to part of the tier ladder, the same vocabulary `enemies2.0` gates on. |
| `Where` | event | Placement. `Dead End` (default — a node with one connection, §1), `Any`, or `Game` (only ever on its own `Game`, the way Abyssal Baths belongs to the Underdocks). |
| `Requirement` | event | A condition on the **run state** that must hold before the event can appear at all — `<stat> <op> <value>`, a trailing `%` reading against the maximum (`hp <= 70%`). Blank = always eligible. `Tier` gates on the ladder, `Where` on the map, this on the player. |
| `Trigger` | event | `After` (default — fires once the game there is beaten, so it reads as an extra reward) or `Before` (fires on arrival, before the game is played, so it can hand you a goal for it). |
| `Rarity` | event | `Common` / `Uncommon` / `Rare`. Weights the roll, same ordering as items and scrolls. |
| `Limit` | event | Times per run. A number, or `None` for no limit. |
| `Image` | event | Art base name → `res://images2.0/events/<Image>.png`. Blank falls back to the de-spaced `Event`, matching every other 2.0 sheet. |
| `Prompt` | event | The prose at the top of the modal. |
| `Goal Met` | event | Printed when a goal this event handed out has its condition **met**. |
| `Goal Missed` | event | Printed when that goal's window closes unmet. Curses never expire, so they leave it blank. |
| `Choice N` | choice | The button label. **Blank ends the event's choice list** — the generator stops reading groups here. |
| `Repeat N` | choice | What picking it does to the event — see §4. Blank = `End`. |
| `Result N` | choice | The prose shown once the choice resolves. |
| `Effect N` | choice | The machine-readable payload — see §5. |

Group order is display order: the choices appear in the modal top to bottom as
`Choice 1`, `Choice 2`, ….

A blank `Effect N` is legal and means the choice does nothing mechanical, which
is a real thing an event wants (walking away should be authorable without
inventing a reward for it). Write `nothing` when the blank would read as
unfinished. A blank `Result N` is legal too — the modal then prints only the
mechanical line — which is how a choice whose flavour text you haven't got yet
stays authorable.

**Why `Goal Met` / `Goal Missed` are event columns and not choice columns.** An
event that hands out a goal (§5, `add_goal`) does not finish in the modal; it
finishes on the checklist, up to several games later, long after the modal is
closed. Those two endings therefore need somewhere that is not a choice's
`Result`. They sit at event level because they belong to the event's *voice*
rather than to which option was taken — the Battleworn Dummy congratulates and
insults you in exactly the same words whichever setting you chose. Leave both
blank on an event that grants no goal.

---

## 4. `Repeat` — the column that makes push-your-luck authorable

Most events are "pick one of three, done". The interesting ones are not, and this
one column is what separates them:

| Value | What happens after the choice resolves |
|---|---|
| `End` *(blank, the default)* | The event closes. |
| `Again` | The event stays open and this choice is **still available**. |
| `Again xN` | Same, but at most N times in total. |
| `Stay` | The event stays open, but this choice is now **spent**. |

`Again` is the whole of the push-your-luck grammar. Combined with `{X}` (§5.1) —
which counts how many times *this choice has already been taken* — one authored
group escalates on its own, instead of needing four near-identical groups that
drift apart the moment anyone tunes them.

`Stay` is the quieter one, and it is what makes a **staged** event fit on a
single row. A `Stay` choice keeps the event open but takes itself off the table,
so what's on offer afterwards is different from what was on offer before — which
is a second stage, without a second row or a stage column. Abyssal Baths (§6) is
built on exactly this: `Immerse` is `Stay`, so the first dip is a one-time act
and the *loop* is a different button.

An event with no reachable `End` is fine as long as some choice is `End` or the
modal always offers a way out; the generator will warn on an event where every
choice is `Again`, because that is an event you cannot leave.

---

## 5. The `Effect` DSL

**It is the `statuses2.0` reward-token DSL**, so a chest an event pays is the
chest an item pays and the chest a status pays (`games-first-redesign.md` §8.2).
Tokens are separated by `;`.

The table is ordered by **what a token costs to support**, which is the thing
worth knowing before authoring with it. Tier A is free, tier B is a parser
addition, tier C is engine work.

**A — parsed by `generate_status_tres.py` today, run by `EffectSystem` today.**
Author freely; these cost nothing.

| Token | Meaning |
|---|---|
| `gain_chest [small\|medium\|large\|huge] N` | Reward chests. The size sets the number of choices offered. |
| `gain_stat <stat> N` | A verb or consumable charge: `bash`, `dash`, `push`, `transmute`, `scramble`, `bombs`, `keys`, `shields`. |
| `gain_hp N` | Health. **Capped by Max Health** (`set_hp` clamps). |
| `gain_max_hp N` | The cap. Does *not* auto-heal — Max Health and Health are independent (§3). |
| `gain_gold N` | Gold. |

**B — `EffectSystem` has the handler; the reward-DSL parser has to learn the
word.** No engine work, just the generator.

| Token | Handler |
|---|---|
| `lose_hp N` | `lose_hp` |
| `apply_status <name> N` | `apply_status` — a `statuses2.0` status on the player |
| `obtain_item` | `obtain_item` |
| `random_item_choice N` | `random_item_choice` — pick 1 of N |
| `nothing` | *(no-op; write it where a blank cell would read as unfinished)* |

**C — needs a new handler as well.** Worth it, but budget for it:
`lose_stat <stat> N`, `lose_gold N`, `lose_max_hp N`, `heal_full`,
`gain_loot N`, and the four event-only forms below.

`gain_loot` is a **category**, not a synonym: it resolves to a scroll today,
because scrolls are the only loot type there is, and widens on its own as more
are added — no event row ever gets touched for it.

There is **no `kill` / `end_run` token and there should not be one**: a `lose_hp`
that empties Health ends the run through the rule that already exists (§2), which
is how Abyssal Baths kills you in Slay the Spire 2 as well.

The two event-only forms carry the weight `locations-and-events-design.md` §6
asked them to:

```
needs <token>                  a gate — offered only if the player can pay
needs <Choice> <op> <n>        a gate — offered only at this point in the event
add_goal  "<condition>" [for <n> games] -> <reward>; <reward>
add_curse <curse> [for <n> games]
play_game tag=<tag> -> <reward>; <reward>
```

`needs` leads a cell (`needs keys 1; obtain_item` — spend a key, take an item).

Its second form is what lets one row hold a **staged** event: the gate names
another `Choice N` in the same event and compares how often it has been taken, so
`needs Immerse > 0` means "only once they're in the water" and
`needs Immerse = 0` means "only while they're still dry". The two forms are told
apart by the comparison operator, which the pick-count form always carries and
the resource form never does.


`add_goal` bolts an extra objective onto the **next** game, paying its reward if
it is met and costing nothing if it is not; the condition is authored in the same
honour-system voice as an enemy goal. It is the token that makes an event native
to this game rather than imported from a deckbuilder — the gamble is whether you
can actually do the thing in the real game, not what a die says.

`for <n> games` widens that window from the next game to the next *n*, counting
down one per game played and expiring unmet at zero. It is what lets an event
translate a **turn limit** — the Battleworn Dummy's three turns become three
games (§7) — and it is the difference between a goal you must hit immediately and
one you have room to line up.

`add_curse` is the same token **inverted**: a standing objective you want to
*not* meet, which costs you every time you do. It takes a **curse id from the
`curses2.0` sheet** (§6) rather than an inline condition, exactly as an item
takes a status id — the curse's condition, penalty and lifetime are authored
once and any number of events can hand out the same one. It carries a window
like `add_goal` does, defaulting to the curse's own `Timer`; `for <n> games`
overrides it. Unrest Site (§9) is where it comes from.

`play_game` is the odd one out: it hands over neither a reward nor a goal but
**sends the player somewhere**. `play_game tag=mecha` drops them into a random
game carrying that tag, off their route, which spawns its enemy and is played
under the ordinary rules — beating the game is the whole of it. The `->` payload
lands on the far side, when they beat it. Afterwards they **choose** whether to
stay at that game (if it is connected on the map) or return to the node they came
from. Punch Off (§10) is where it comes from, and note what that choice is: a
round trip you are allowed to decline, which is the exact thing §1 says a dead
end forces on you.

That gives the checklist **three kinds of objective**, and they are genuinely
different animals:

| | Issued by | Condition met | Condition not met | Lifetime |
|---|---|---|---|---|
| **Enemy goal** | the card you took | the enemy dies, its item drops | it follows you and hits every game | until met |
| **Event goal** | `add_goal` | pays its reward | **nothing** — it expires | `for <n> games` |
| **Curse goal** | `add_curse` | **you take the penalty**, every time | nothing | its `Timer` — 3 games by default |

Each gets **its own section of the post-game checklist**, and that separation is
the point rather than decoration: an enemy goal is a debt that bites when missed,
an event goal is a bonus that merely lapses, and a curse is a bill that arrives
when you *succeed* at the wrong thing. A checklist that renders all three alike
is lying about which one hurts (`locations-and-events-design.md` §1 draws the
same line for locations). **Curse rows read purple**, so the one objective on the
list you are trying to avoid never looks like the ones you are chasing.

Event goals and curse goals tick to the **same three-game clock** by default,
which is deliberate: whatever the checklist is carrying, it clears at about the
same rate, and the player is never tracking two different countdowns.

Two things this is *not*. It is not the shelved `CurseData` / `data/curses`
system (`games-first-redesign.md` §5) — same word, different thing: a curse goal
is a row on the checklist, not a card, and nothing should wire the two together.
And `Goal Met` never means "it went well" — it means the condition happened. On a
curse that is the bad outcome. The sign lives in the token, not in the column
name.

Abyssal Baths (§6) is deliberately authored out of tiers A and B only, so the
first event needs no new effect handler to run.

### 5.1 `{X}` inside an event

`{expr}` holes work exactly as they do on `statuses2.0` — arithmetic evaluated at
apply time through Godot's `Expression`, with the same `a^b` → `pow(a, b)`
normalisation and the same `[singular|plural]` agreement markers.

**What changes is what X is bound to.** On a status X is the stack count. **In an
event, X is the number of times this choice has already been taken** — 0 on the
first pick, 1 on the second. That binding plus `Repeat: Again` is the entire
escalation mechanism.

A consequence worth authoring around: because the next cost is a pure function of
X, the modal can render it on the button ("Immerse — costs 3 Health") without
anyone authoring a warning. Slay the Spire 2 has to tell you the baths are about
to kill you; here the button can just say so, and no column is needed for it.

---

## 6. The `curses2.0` sheet

A curse is authored **once**, in its own sheet, and referenced by id from any
event that hands it out — the same relationship an item has with `statuses2.0`.
Six columns:

| Column | Meaning |
|---|---|
| `Curse` | Display name, and the id events reference (slugified: `Poor Sleep` → `poor_sleep`). |
| `Game` | The real game it is lifted from. |
| `Condition` | What you must avoid doing, in the honour-system voice the goals use. |
| `Penalty` | What it costs when you do it — the same reward-token DSL, pointed the other way. |
| `Timer` | Games it lasts before expiring. **3** unless a curse says otherwise. |
| `Image` | Art base name under `images2.0/curses/`. |

The roster:

| Curse | From | Condition | Penalty | Timer |
|---|---|---|---|--:|
| **Poor Sleep** | Unrest Site | you use a rest site to replenish health | `lose_hp 2` | 3 |
| **Injury** | Punch Off | you go below half health | `lose_hp 2` | 3 |

**The checklist row is generated, not authored.** `Condition` + `Penalty` compose
into *"If you use a rest site to replenish health, take 2 damage at the end of
combat"*, so a curse's text cannot drift from what it actually does. There is no
prose column to keep in sync, which is the mistake the legacy `curses` sheet made.

The two are deliberately different flavours, and it's worth keeping that spread
as more are authored:

- **Poor Sleep points at the real game.** A rest site is a thing in whatever
  roguelike you go off and play, checked on the honour system. That is the flavour
  only this app can produce — the curse follows you out of the modal and into
  Hades, and the app never has to know what a rest site looks like there.
- **Injury points at the run.** Half health is this app's own number, so it fires
  off state the app can see.

Three games is the default because it matches `add_goal`'s window: whatever the
checklist is carrying, it clears at about the same rate, and the player is never
tracking two countdowns at different speeds.

---

## 7. The first worked example: Abyssal Baths

Slay the Spire 2's Underdocks event, authored with **the game's own text
verbatim** — `Prompt` and the `Result` strings are quoted, not paraphrased.

It is worth reading closely because it is **two-stage**, and that is what
exercises every column here:

| | Offered when | `Repeat` | `Effect` |
|---|---|---|---|
| **Immerse** | you're still dry | `Stay` | `gain_max_hp 1; lose_hp 3` |
| **Linger** | you're in the water | `Again` | `needs Immerse > 0; gain_max_hp 1; lose_hp {4+X}` |
| **Abstain** | you're still dry | `End` | `needs Immerse = 0; gain_hp 3` |
| **Exit Baths** | you're in the water | `End` | `needs Immerse > 0; nothing` |

Three things fall out of that, and each one is a column earning its place:

- **`Immerse` is `Stay`, not `Again`.** The first dip is a one-time act; the loop
  is a *different button*. That is the whole of the staging, and it costs no
  stage column — a `Stay` choice removes itself, so what is on offer afterwards
  is necessarily different.
- **`{4+X}` is the escalation, exactly.** Slay the Spire 2's Lingers cost 4, then
  5, then 6, climbing by one; X counts Lingers already taken, so one authored
  group reproduces the whole ladder.
- **The two exits are gated against each other, and that gate is load-bearing.**
  Abstain's heal is available *only* to someone who never got in. Without it the
  optimal line is "bathe until nearly dead, then heal", which is precisely
  what Slay the Spire 2 refuses to allow — and which an earlier draft of this
  event, with a single ungated Abstain, accidentally allowed.

### The gains are tuned; the costs still aren't

Health in this game is **5–10, not 75**, so Slay the Spire 2's numbers cannot all
come across. The **gains** have been brought down to this game's scale: +1 Max
Health a dip rather than +2, and Abstain heals 3 rather than 10.

The **costs have not moved with them** — Immerse is still 3 and Linger still
climbs 4, 5, 6. At a 5–10 Health pool that makes the water a bad trade at every
depth: the first dip alone can cost a third of a character for +1 Max Health, and
nobody who has done the arithmetic gets in. If the event plays as a dead option,
this is the cell to look at, and the scaled costs would read:

```
Immerse   gain_max_hp 1; lose_hp 1
Linger    needs Immerse > 0; gain_max_hp 1; lose_hp {2+X}
```

— 1, then 2, then 3, cumulative 10 by the fourth dip, so a full-health character
really does die in there, which is the point of the event. **It is two cells, and
it is a tuning call, which is why it is in the sheet and not in code.**

`Where: Dead End` is doing real work here, and not only because of §1 — an event
that can kill you is one you must have *chosen* to walk toward. Hanging it off a
node nobody is forced through is what makes it fair.

**Two `Result` cells are blank on purpose.** Linger's and Exit Baths' flavour
text could not be sourced (every site carrying them is unreachable from here), so
they are left empty rather than filled with an invention presented as quotation.
Fill them from the game.

---

## 8. The second worked example: Battleworn Dummy

Slay the Spire 2's Glory event. **All four dialogue strings are the game's own,
verbatim** — prompt, the pass message, the failure message. What is *not* a port
is the mechanic, and the gap between those two is the point of this example.

The original is a combat puzzle: pick a dummy with 75, 150 or 300 HP and you have
three turns to break it. This game has no turns and no HP bars to swing at, so a
literal translation has nothing to translate. What survives is the event's actual
shape — **pick your own difficulty, then go and prove it, on a clock**:

| Slay the Spire 2 | here |
|---|---|
| a 75 / 150 / 300 HP dummy | beat a game in **5 / 3 / 1 attempt(s)** |
| three turns to do it | **three games** to do it (`for 3 games`) |
| potion / 2 upgrades / relic | scroll / small chest / large chest |
| fail and get nothing | the goal expires and pays nothing |

```
Setting 1   add_goal "beat a game in 5 attempts or fewer" for 3 games -> gain_scroll 1
Setting 2   add_goal "beat a game in 3 attempts or fewer" for 3 games -> gain_chest small 1
Setting 3   add_goal "beat a game in 1 attempt"           for 3 games -> gain_chest large 1
```

**Attempts are already the currency this needs.** Shields *are* the tries (§3.2)
and `GameLoop2.attempts()` already counts them, so "beat a game in 1 attempt"
asks nothing new of the run — only a checklist row to hang it on. That is why
this abstraction is the right one and a damage-total one would not have been:
it re-uses a number the player is already watching.

**The three turns became three games rather than one.** That is what `for 3
games` is for, and it is a better translation than "the next game" would have
been — the original gives you *room to work*, and a one-game window would have
turned a difficulty choice into a coin flip on whichever game happened to be next.

**This is the event that needs `Goal Met` / `Goal Missed`.** Everything the Dummy
says after you pick a setting, it says games later, through the checklist. There
is no choice `Result` that can hold "YOU PASS THE TRAINING!" — by then the modal
is long gone. Both strings are the same whichever setting was chosen, which is
why they sit at event level (§3).

`Setting N` keeps its in-game button name. The rest of each in-game label —
"Fight a 75 HP dummy. Procure 1 random Potion." — is Slay the Spire 2's
*mechanical* line rather than its dialogue, and the modal renders ours off the
`Effect` instead: "Beat a game in 5 attempts or fewer. Gain 1 Scroll." The
dialogue is exact; the mechanics are the abstraction.

Reward mapping: a potion is this game's **scroll** (§4.1, the consumable you
gamble on), "upgrade 2 cards" has no counterpart at all so it becomes the
middle rung of the chest ladder, and a relic is a **large chest** — three items
to choose from, which is unambiguously the best of the three and matches Setting
3 being the hardest ask. `gain_scroll` is the one tier-C token here (§5); the
rest already exist. (Punch Off, §10, spends its scroll through `gain_loot`
instead — the Dummy names the scroll directly because *that* is what it pays,
where Punch Off's "standard combat reward" is whatever loot happens to be.)

---

## 9. The third worked example: Unrest Site

Slay the Spire 2's Overgrowth event. Prompt and both `Result` strings verbatim.
It is here because it bends the format in two places at once, which is the real
test of whether a schema is malleable or just wide.

| | `Effect` |
|---|---|
| **Rest Anyways** | `heal_full; add_curse "you use a rest site to replenish health" -> lose_hp 2` |
| **Kill the Trees** | `lose_max_hp 2; gain_chest small 1` |

**It needed a new column, and only one.** In Slay the Spire 2 this event only
appears at **70% HP or below** — the whole bargain is about being hurt, and
without that gate "heal to full" is a free top-up that the curse buys nothing
for. Nothing in the sheet could say so: `Tier` gates on the ladder and `Where`
gates on the map, but neither can gate on the *player*. Hence **`Requirement`**,
the state gate, and the answer to "does this need reorganising" is: that column,
and nothing else.

**It needed no column for the new goal kind.** A curse goal is a third species of
objective (§5) — one you want to *not* meet — and it arrives entirely through
`add_curse`, which names a curse from `curses2.0` (§6). The token carries the kind, the kind picks the checklist section and
the purple, and the sheet is none the wiser. That is the property worth
protecting as more events land: **new kinds of consequence should cost a token,
not a column.** A `Goal Type` column would have been the tempting wrong answer —
it would have to grow a new value for every kind, and every event that isn't that
kind would carry a blank.

### The curse

> *If you use a rest site to replenish health, take 2 damage at the end of
> combat.*

Slay the Spire 2 hands you a card called Poor Sleep; here it is a row on the
checklist, authored in `curses2.0` (§6) and referenced from the event as
`add_curse poor_sleep`. It lasts **3 games** — its `Timer` — so it is a weight on
the next stretch of run rather than a permanent tax. And note what the condition
points at:
a rest site **in the real game you are playing**, checked on the honour system
like every other goal in this app. That is the shape events should reach for —
the curse follows you out of the modal and into Hades, and the app never has to
know what a rest site looks like there.

### Changes from the original

Both requested: Max Health lost drops from **8 to 2**, and the random Relic
becomes a **small chest** — which the outcome text was already describing, since
the byrd spirits "drop a small box at your feet".

Worth knowing while tuning: 2 of this game's 5–10 Max Health is a **20–40% cut**
where 8 of 75 was 11%, so Kill the Trees is now the sharper of the two options
rather than the safe one. That may well be the intent — it makes resting the
default and the chest something you genuinely pay for — but it is a different
event from the original in a way the numbers alone don't announce.

---

## 10. The fourth worked example: Punch Off

Slay the Spire 2's Underdocks event. Prompt and both `Result` strings verbatim.

| | `Effect` |
|---|---|
| **Nab** | `add_curse injury; gain_chest small 1` |
| **I Can Take Them** | `play_game tag=mecha -> gain_loot 1; gain_chest small 2` |

The bargain survives intact — take the treasure and wear the Injury, or do the
work and take everything — but the second option is a **new kind of thing for an
event to do**. It doesn't pay out and it doesn't set a goal: it *sends the player
somewhere*.

`play_game tag=mecha` drops them into a random game carrying that tag, off their
route. `mecha` is a real tag on the `games` sheet with **14 games** behind it, so
the roll has somewhere to land — worth checking before authoring a `play_game`
against any tag, since the thin end of that vocabulary has single-game buckets.
The game spawns its enemy and is played under the ordinary rules; **beating the
robots is beating the game**, and the `->` payload lands on the far side of it.

**Then the player chooses: stay, or go back.** If the mecha game is connected on
the map they may simply carry on from there; otherwise — or if they'd rather —
they return to the node they came from. That is worth naming, because it is the
exact inverse of the thing this whole document starts from: §1 says a dead end
*forces* a round trip on you, and this is the one event that hands the choice
back. An event that started as "two robots are fighting over some treasure" ends
up being about routing, which is the right place for this game's events to land.

Reward mapping: a relic is a **small chest**, and relic + potion + standard
combat reward is **2 small chests + 1 loot**. `gain_loot` is authored as a
category rather than as `gain_scroll` — it resolves to a scroll today, since
scrolls are the only loot type there is, and widens on its own as more are added
without any event row being touched.

`Requirement: games >= 6` carries the original's "Floor 6 or later" — depth,
which this run measures in games played rather than floors.

### What it needed from the format: nothing

No new column, no rearrangement. Both of its new capabilities arrived as tokens
— `play_game` and a curse reference — which is the rule §9 set out holding up
under the first event authored after it. The one structural change this round was
a **new sheet** (`curses2.0`), not a new shape for this one.

---

## 11. Other shapes, for reference

Not authored — these are here so the format can be read against more than one
event.

Shown a group per line for legibility; on the sheet each event is one row and
these run left to right.

```
Golden Idol     Choice 1 Take the idol │ End │ obtain_item; apply_status marked 1
                Choice 2 Leave it      │ End │ nothing

Locked Chest    Choice 1 Open it       │ End │ needs keys 1; gain_chest medium 1
                Choice 2 Pry it open   │ End │ lose_hp 2; gain_chest small 1
                Choice 3 Walk away     │ End │ nothing
```

Both are the plain shape — pick one, it resolves, the event closes — which is
what most events are and what the two worked examples above deliberately are
not.

---

## 12. What is still missing

The sheet is authorable now. Nothing reads it yet.

1. **`CurseData2` + `tools/generate_curse2_tres.py`** → `data/curses2.0/`. The
   smaller job and the one the events now depend on, since `add_curse` resolves
   an id against it. Six columns, no nesting; closest model is
   `generate_scroll2_tres.py`.
2. **`EventData2` + `tools/generate_event2_tres.py`** → `data/events2.0/`.
   Closest model is `generate_status_tres.py`, which already parses the reward
   tokens and the `{expr}` holes this sheet reuses — the new work is walking the
   numbered choice groups and the `Repeat` / `needs` semantics, not the DSL. Note
   the *existing*
   `generate_event_tres.py` reads the legacy `events` sheet and its combat-era
   d20 outcomes; it is not a starting point, it is the thing being replaced.
3. **`Requirement` evaluation.** The state gate has to be checked *before* the
   badge is drawn, not when the modal opens — an event advertised on a card and
   then not delivered is worse than one that never showed. Which means the gate
   is read against the run state at offering time, and an event whose
   requirement lapses between the card and the arrival has to resolve one way or
   the other rather than silently vanishing.
4. **Placement.** Assign an event to a node deterministically — seeded off the
   node id and the run seed, not rolled when the card is drawn — or the badge in
   step 5 will lie the moment the offering is redrawn. `Overworld2` already
   solves exactly this problem for the enemy behind a card (`_slot_enemies`
   keyed by `_offer_seed()`); the event assignment should follow it.
5. **The badge above the game choice.** There is already a badge row mounted
   above every cover for this: the `flag` Label at the top of
   `_make_choice_card`, which renders `🏆 THE AMULET` on the Amulet's card and an
   empty string of the same height everywhere else, so the covers stay in line.
   The event marker belongs on that row — same line, same discipline of
   reserving the space on every card.
6. **The two new checklist sections.** *Event goals* — condition, countdown
   (`2 games left`), reward, and the `Goal Met` / `Goal Missed` line when they
   resolve. And *curse goals* — permanent, no countdown, **purple**, listing what
   it costs you rather than what it pays. Kept apart from the enemy goals and
   from each other for the reason in §5: the three bite differently and a
   checklist that flattens them is lying. `Overworld2._verify_box` is where the
   checklist is built; `UITheme` has no purple yet (the nearest is the palette
   entry at `Color(0.61, 0.35, 0.71)`) and will want a named constant so the
   modal, the checklist row and the HUD chip all agree.
7. **The modal.** One modal for events *and* `encounters`
   (`locations-and-events-design.md` §6) — not two. `EventModal.gd` is combat-era
   (d20 rolls against `charisma` / `dexterity` / `intelligence`, stats the
   redesign deleted) and is a rewrite, not an edit.
8. **`play_game`.** The one token that moves the player. It needs to pick a
   tagged game, run it as an ordinary game (enemy and all) without it counting as
   a route step, pay the `->` payload on the win, and then offer stay-or-return —
   stay only when the game is in the run graph. `Overworld2.travel_to_game` and
   `teleport_to_type` are the two nearest existing verbs.
9. **`images2.0/events/` and `images2.0/curses/`.** Neither folder exists yet;
   `Image` names point into them (`AbyssalBaths`, `BattlewornDummy`, `UnrestSite`,
   `PunchOff`; `PoorSleep`, `Injury`).
