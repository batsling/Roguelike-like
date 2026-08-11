# Event sheet-authoring (`events2.0`)

Status: **built, illustrated and running.** Eight events authored, generators
and runtime in place, art in `images2.0/`, tests in `test/test_events2.gd`. §15 is how it runs and the little
that's left. Companion to `games-first-redesign.md` and
`locations-and-events-design.md` §6, which argued events should wait for
somewhere to live — §1 is that somewhere.

```bash
python3 tools/_curses2_sheet_setup.py    # (re)lay the curses2.0 sheet
python3 tools/_events2_sheet_setup.py    # (re)lay the events2.0 sheet
python3 tools/generate_curse2_tres.py    # sheet -> data/curses2.0/
python3 tools/generate_event2_tres.py    # sheet -> data/events2.0/
```

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
same four columns for 2, 3 and 4. Thirty columns in all — fourteen for
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

Fourteen event columns, then `Choice N` / `Repeat N` / `Result N` / `Effect N`
for N = 1…6.

| Column | Scope | Meaning |
|---|---|---|
| `Event` | event | Display name, and the id everything else keys off. |
| `Game` | event | The real game this is lifted from. Flavour credit (the modal's "From: *game*" line), and the target when `Where` is `Game`. |
| `Tier` | event | `All`, or a comma list of `Low` / `Medium` / `High` / `Insane`. Gates an event to part of the tier ladder, the same vocabulary `enemies2.0` gates on. |
| `Where` | event | Placement. `Dead End` (default — a node with one connection, §1), `Any`, or `Game` (only ever on its own `Game`, the way Abyssal Baths belongs to the Underdocks). |
| `Requirement` | event | A condition on the **run state** that must hold before the event can appear at all — `<stat> <op> <value>`, a trailing `%` reading against the maximum (`hp <= 70%`). Blank = always eligible. `Tier` gates on the ladder, `Where` on the map, this on the player. |
| `Trigger` | event | `After` (default — fires once the game there is beaten, so it reads as an extra reward) or `Before` (fires on arrival, before the game is played, so it can hand you a goal for it). **`Before` is not implemented** — see §15. |
| `Rarity` | event | `Common` / `Uncommon` / `Rare`. Weights the roll, same ordering as items and scrolls. |
| `Limit` | event | Times per run. A number, or `None` for no limit. |
| `Image` | event | Art base name → `res://images2.0/events/<Image>.png`. Blank falls back to the de-spaced `Event`, matching every other 2.0 sheet. |
| `Prompt` | event | The prose at the top of the modal. |
| `Goal Met` | event | Printed when a goal this event handed out has its condition **met**. |
| `Goal Missed` | event | Printed when that goal's window closes unmet. Curses never expire, so they leave it blank. |
| `Chance Won` | event | Printed when a `chance` roll (§5) lands. Blank on events with no gamble. |
| `Chance Lost` | event | Printed when it doesn't. |
| `Choice N` | choice | The button label. **Blank ends the event's choice list** — the generator stops reading groups here. |
| `Repeat N` | choice | What picking it does to the event — see §4. Blank = `End`. |
| `Result N` | choice | The prose shown once the choice resolves. A **ladder**: `||`-separated rungs, one per press, the last standing for every press after — see §4.1. |
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

**`Chance Won` / `Chance Lost` are the same argument, for the same reason.** A
gamble's outcome is decided by the roll rather than by which button produced it,
so a choice's own `Result` cannot hold it — and where an event has several ways
to take the same gamble, they all print the same two strings. Scrap Ooze (§11) is
the case: `[Reach Inside]` and `[Deeper]` are two column groups and one hand in
the ooze, and Slay the Spire has one success line and one failure line between
them. When a choice rolls, whichever of these applies **replaces** its `Result`,
so a rolling choice normally leaves that cell blank. Leave both blank on an event
that never gambles — the generator rejects them otherwise, since nothing would
ever print them.

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

### 4.1 `Result` is a ladder too

`Again` escalates a choice's **numbers** from one authored group, via `{X}`
(§5.1). Without a matching move for the prose, the one button a player presses
over and over would be the one that answers with the same sentence every time —
or, as Abyssal Baths shipped, with nothing at all.

So a `Result` cell is **`||`-separated rungs, one per press**, and the **last
rung stands for every press after it**:

```
Result 2   The temperature keeps rising! … || It keeps getting hotter! … || … || If you bathe any longer you will die.
```

A cell with no `||` in it is a one-rung ladder, which is what almost every choice
is and what every event authored before this one still holds — the format did not
change under them.

Three things worth knowing:

- **The last rung sticking is what makes an unbounded ladder authorable.**
  Linger's cost climbs forever, so its prose cannot enumerate forever. The final
  rung is the death warning, and a warning that keeps printing while the player
  keeps pressing is the correct behaviour rather than a fallback.
- **A blank rung mid-ladder is legal** — that press prints only the mechanical
  line. A choice is allowed to go quiet before it speaks again.
- **More than one rung only makes sense under `Again`.** `End` closes the event
  and `Stay` spends the choice, so under either one every rung past the first is
  unreachable; the generator rejects it rather than letting the prose rot
  silently.

`||` and not `|`, so a `[singular|plural]` agreement marker (§5.1) can still
appear inside the prose.

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
| `gain_max_hp N` | The cap **and the Health to fill it** — a new container arrives full, which is what "+2 Max Health" means in every game this map is drawn from. Pays the heal that actually landed, so Handcuffs' cap can't be healed around. |
| `gain_empty_max_hp N` | The cap **alone**. The other half of the split, for the item or event that means an empty container and has to say so (Hollow Heart). |
| `gain_gold N` | Gold. |
| `gain_item <item_id>` | A **named** `items2.0` relic, handed straight over. The one reward token that says *which* item, for an event built around a specific one (Golden Idol, §12). The generator checks the id against the sheet, so a typo is an error rather than a choice that silently pays nothing. |
| `spawn_enemy [N]` | Conjures N enemies at the run's current difficulty straight onto the following stack — the same thing the Scroll of Create Monster does. **This is what every curse costs** (§6). |

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

Two of the costs do not simply mirror their gains, and both asymmetries are
deliberate:

- **`lose_gold all`** charges the whole purse. It is the one amount the sheet
  cannot write as a number, because what it costs is settled when the choice is
  taken rather than when the `.tres` is written — which is what lets Morphic
  Grove be the same trade at 3 gold and at 30. `all` is a `lose_gold`
  amount only: `lose_hp all` is a death with extra steps, and there is already a
  clearer way to author one.
- **`lose_max_hp N` does not cost Health.** `gain_max_hp` hands over the Health
  to fill the room it makes; its mirror takes only the room. Health moves solely
  when it no longer *fits* — 20/30 losing 5 is 20/25, while 30/30 losing 5 is
  25/25 and there is nowhere else for it to go. An emptied container on top of
  the cost the event already charged is two punishments for one choice.

`gain_loot` is a **category**, not a synonym: it resolves to a scroll today,
because scrolls are the only loot type there is, and widens on its own as more
are added — no event row ever gets touched for it.

There is **no `kill` / `end_run` token and there should not be one**: a `lose_hp`
that empties Health ends the run through the rule that already exists (§2), which
is how Abyssal Baths kills you in Slay the Spire 2 as well.

The event-only forms carry the weight `locations-and-events-design.md` §6
asked them to:

```
needs <token>                  a gate — offered only if the player can pay
needs <Choice> <op> <n>        a gate — offered only at this point in the event
add_goal  "<condition>" [for <n> games] -> <reward>; <reward>
add_curse <curse> [for <n> games]
play_game tag=<tag> -> <reward>; <reward>
chance <p>% -> <reward>; <reward>
```

`add_goal`, `play_game` and `chance` are **arrow verbs**: everything past the
`->` is their payload, so each has to be the last clause in its cell. That single
rule is also what keeps a cell to one arrow verb — a second one could only appear
after the first, which being last forbids — so there is no separate check for two
of them fighting over the payload, and none is needed.

`needs` leads a cell. Its resource form is a **check, not a charge**: `needs
keys 1` asks whether the player has a key, and nothing deducts it. A choice that
should cost the key writes the charge itself — `needs keys 1; lose_stat keys 1;
gain_chest medium 1` — which keeps "may I offer this" and "what it costs"
separable, so a gate can also guard something it doesn't consume.

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

`chance` is the only token whose payout is not settled by pressing the button.
It **rolls**: `p` percent for the `->` payload, nothing otherwise, and the costs
in front of it are charged either way — the acid burns whether or not there was a
relic in the ooze. `p` is an ordinary amount, so `{25+10*X}` climbs it per press
exactly as `{4+X}` climbs a cost, and it is clamped to a real percentage so an
unbounded ladder simply becomes a certainty rather than running past 100.

Two things fall out of it that are worth stating plainly. **A won roll closes the
event**, whatever `Repeat` says — `Again` describes what happens when you *lose*,
and there is nothing left to reach for once the relic is in your hand. And the
prose comes from `Chance Won` / `Chance Lost` (§3) rather than from the choice's
`Result`, because the outcome is the roll's and not the button's. Scrap Ooze
(§11) is where it comes from.

That gives the checklist **three kinds of objective**, and they are genuinely
different animals:

| | Issued by | Condition met | Condition not met | Lifetime |
|---|---|---|---|---|
| **Enemy goal** | the card you took | the enemy dies, its item drops | it follows you and hits every game | until met |
| **Event goal** | `add_goal` | pays its reward | **nothing** — it expires | `for <n> games` |
| **Curse goal** | `add_curse` | **you take the penalty**, every time | nothing | its `Timer` — 3 games by default, or permanent |

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

**X is not the only name bound.** A hole may also read the run itself —
`MAX_HP`, `HP`, `GOLD`, `GAMES` — which is what lets a cost be a **fraction of
the player** rather than a number. The Golden Idol (§12) charges 25% of Max
Health as `lose_hp {max(1,round(0.25*MAX_HP))}`, and the same machinery that
prints "-5 Health" for a `{4+X}` hole prints "-3 Health" for this one. Two
authoring notes fall out of it:

- **Round in the hole, not in your head.** The effect rounds the number it
  applies; the button formats the number it prints. Write `round(...)` and the
  two agree — leave it out and a 2.5 is dealt as 3 and printed as 2.5.
- **Floor small percentages at 1.** Health here is 5–10, not 75, so 8% of it
  rounds to nothing for half the roster. `max(1, ...)` is the difference between
  a cost and a button that claims to hurt and doesn't.

### 5.2 `<give>` and `<get>` — name holes

`{...}` holes carry arithmetic. `<give>` and `<get>` carry a **name**, and they
exist for one event: the Relic Trader (§13), whose three offers are built out of
what the player is actually carrying. The sheet writes the sentence —
*"He takes `<give>` off you… and presses `<get>` into your palm"* — and the run
fills in the two relics.

They work in the `Choice` label, the `Result` prose and the mechanical line
alike, so the whole event stays authored in the spreadsheet: the only thing
GDScript knows about the Relic Trader is what `<give>` and `<get>` mean. An
unfilled hole (the Collection's event page, where there is no run and no pack)
reads "a relic", so the sentence still scans outside a run.

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
| `Timer` | Games it lasts before expiring. **3** unless a curse says otherwise. `N/A` (or `None` / `Permanent`) means it **never** expires — Curse of the Bell, which arrives with the Calling Bell relic and stays for the run. A **blank** cell is still the three-game default: "nobody filled this in" and "this is forever" must not be the same value. |
| `Image` | Art base name under `images2.0/curses/`. |

The roster:

| Curse | From | Condition | Penalty | Timer |
|---|---|---|---|--:|
| **Poor Sleep** | Unrest Site | you use a rest site to replenish health | `spawn_enemy` | 3 |
| **Injury** | Punch Off, Golden Idol | you go below half health | `spawn_enemy` | 3 |
| **Curse of the Bell** | the Calling Bell relic | ring a bell | `spawn_enemy` | permanent |

**Every curse pays in enemies.** The penalty column used to charge Health, which
put a curse in competition with the enemy stack for the same resource and made
"take the curse" a piece of arithmetic: two damage against whatever the reward
was worth. `spawn_enemy` bills in the run's own currency instead — a body that
has to be *beaten*, that follows you until it is, and whose cost depends on where
the board already is rather than on a number. It is also the only penalty that
gets worse the deeper the run goes, since the conjured enemy rolls at the current
difficulty. A test asserts this holds for the whole roster rather than for the
rows a test happens to name, so a curse authored later has to say why if it wants
to be the exception.

**The checklist row is generated, not authored.** `Condition` + `Penalty` compose
into *"If you use a rest site to replenish health, spawn a random enemy when you
report the game"*, so a curse's text cannot drift from what it actually does.
There is no prose column to keep in sync, which is the mistake the legacy `curses`
sheet made.

The flavours are deliberately different, and it's worth keeping that spread as
more are authored:

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
climbs 4, 5, 6. What the player actually feels is now **one lower than each of
those**, because a `gain_max_hp` arrives with the Health to fill it (§5): the
first dip nets -2 and the Lingers net 3, 4, 5. That is a real softening of an
event that was already a bad trade, and it did not come from this cell — it came
from the rule changing under it.

At a 5–10 Health pool the water is still a bad trade at every depth: the first
dip nets a fifth of a character for +1 Max Health, and nobody who has done the
arithmetic gets in. If the event plays as a dead option, this is the cell to look
at, and the scaled costs would read:

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

### Linger's prose is a ladder, and it is the reason §4.1 exists

Linger's and Exit Baths' `Result` cells were blank for a long time — the text
could not be sourced, and an invention presented as quotation was the one thing
worse than a gap. They are now filled, and filling Linger's is what turned
`Result` into a ladder (§4.1).

The point is that Linger is **not one string**. Slay the Spire 2 answers each dip
with a hotter line and finishes on a warning:

| Press | Rung |
|--:|---|
| 1 | *The temperature keeps rising! How long can you endure before the steam cooks you from within?* |
| 2 | *It keeps getting hotter! The pool's bubbling sounds like laughter. IT'S SO HOT!* |
| 3 | *You wonder if this is what it's like to live in the Village of Demons? You have bathed so long you have lost track of time and your mind... It's nice in here. Really fantastic.* |
| 4+ | *If you bathe any longer you will die.* |

The fourth rung is last, so it stands for every press after it. That is the
event's whole voice working the way its numbers already did: `{4+X}` says the
dip costs one more, and the ladder says the water is one degree hotter, from the
same single authored group. Exit Baths gets its one line — *"The heat finally
gets to you, and you hop out of the bath."* — because a choice that closes the
modal should say why.

**Provenance, and the standard this repo set itself.** Prompt, Immerse and
Abstain are the game's own text, read off the source. These five strings are
**not** at the same confidence: every site carrying them is blocked from the
environment this was authored in, so they were reconstructed from search-engine
summaries of the untapped.gg and wiki.gg event pages. The wording held consistent
across several independent queries; the **order of the first two rungs is the
least certain part**. Check them against the game before treating them as
quotation — this is one cell of the sheet, and correcting it is one edit and a
regeneration.

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

## 11. The fifth worked example: Scrap Ooze

Slay the Spire's Act 1 event — the **first one here from the original game**
rather than from Slay the Spire 2. All four strings are the game's own, verbatim,
with its inline colour markup (`#r`, `#y`, `@…@`) stripped and its `NL` breaks
flattened.

It is the event that made the sheet learn to **gamble**. Everything before it was
settled the moment you pressed the button: you could be charged, gated, sent
somewhere or handed an objective, but you always knew what the press bought.
Scrap Ooze is nothing *but* the not-knowing, so it could not be authored at all
until `chance` existed.

| | Offered when | `Repeat` | `Effect` |
|---|---|---|---|
| **Reach Inside** | your hand is still clean | `Stay` | `lose_hp 1; chance 25% -> gain_chest small 1` |
| **Deeper** | you have already reached once | `Again` | `needs Reach Inside > 0; lose_hp {2+X}; chance {35+10*X}% -> gain_chest small 1` |
| **Leave** | always | `End` | `nothing` |

**Two column groups for one hand in the ooze**, and that is not duplication — it
is the game's own button. Slay the Spire renames `[Reach Inside]` to `[Deeper]`
after the first grab, which is precisely the staging `Stay` already does
(§4): the first reach spends itself and reveals the loop, exactly as Immerse
reveals Linger in the Baths. The two share one success line and one failure line,
which is what `Chance Won` / `Chance Lost` are for (§3).

### The damage is this game's; the odds are the original's

Slay the Spire opens at **3 HP** and climbs by one per attempt, against a 75 HP
pool — 4% of a character for the first grab. Health here is **5–10**
(`games-first-redesign.md` §3), where 3 is 30–60%: a third to over half a
character to find out whether there was anything in the pile at all, which nobody
who has done the arithmetic pays for a 25% shot. **As requested, the ladder
starts at 1 and climbs by one per failed reach** — 1, 2, 3, 4 — and that is the
whole of what changed:

```
Reach Inside   lose_hp 1        25%
Deeper         lose_hp {2+X}    {35+10*X}%      X = Deepers already taken
```

The first reach is still a steeper share of the pool than the original's (10–20%
against 4%), which is the right direction for an event that has to be worth about
one game's reward (§1) — it just is not the *ruinous* share 3 would have been.

The **odds are untouched**: 25%, +10 per failure. Because the two ladders climb
together the decision sharpens rather than flattens — the fourth reach is a 55%
shot for 4 Health where the first was a 25% shot for 1 — and a player who keeps
reaching until it lands pays **about 6 Health over about 2.7 reaches**. That is
more than a whole character at the low end of the pool, which is the next point.

Contrast §7, where the Baths' gains were rescaled and their costs were not. Here
both halves of the trade were looked at, and only one of them needed moving.

**A relic is a Small chest**, the mapping Punch Off and Unrest Site already use.
Small means *one* item offered, so it reads as the random relic Slay the Spire
hands over rather than as a pick from three. `obtain_item` would have been the
wrong token — that is Wand of Wishing's any-item-in-the-catalogue picker, which
is a far better prize than 25% of one should ever buy.

### It can kill you, and that is the point

The ladder is unbounded and `Again` never stops offering, so a player who keeps
reaching runs out of Health before the odds run out of room. That is the Abyssal
Baths rule (§7) and the reason both events sit at `Where: Dead End`: an event
with a way to die in it has to be one you *chose* to walk toward.

The button says the number, as always — "−3 Health · 55%: +1 Small Chest" — so
the escalation never has to be discovered by losing to it.

### What it needed from the format

Two event columns and one token. The columns are the second instance of a rule
§3 already set, not a new idea: an ending that is not any single choice's ending
lives at event level. The token is the fourth of them, and `chance` joins
`add_goal` and `play_game` as an **arrow verb** — which is what turned "must be
the last clause" from a rule written twice into one shared check written once.

---

## 12. The sixth worked example: Golden Idol

Slay the Spire's Act 1 shrine, and the first event whose price is a **percentage
of the player** rather than a number.

| | |
|---|---|
| `Where` | Dead End |
| `Limit` | 1 |
| `Prompt` | *"You stumble into a hidden chamber. In the centre of the room, sitting on a pedestal, is a golden idol worth a fortune. The plinth it rests on is worn smooth, and the floor around it is not."* |

| Choice | Repeat | Effect |
|---|---|---|
| **Take** | `Stay` | `gain_item golden_idol` |
| **Leave** | `End` | `needs Take = 0; nothing` |
| **Outrun** | `End` | `needs Take > 0; lose_hp {max(1,round(0.25*MAX_HP))}` |
| **Smash** | `End` | `needs Take > 0; add_curse injury` |
| **Hide** | `End` | `needs Take > 0; lose_max_hp {max(1,round(0.08*MAX_HP))}` |

### It is staged, and that is why it needed a fifth column group

The original is two screens: take or leave, and then — with the boulder already
moving — outrun, smash, or hide. That is the Abyssal Baths trick (§7) pointed at
a different problem: **Take is `Stay`**, so pressing it spends the button and
leaves the event open, and the three escapes are gated `needs Take > 0` so they
are invisible until it has been. **Leave is gated the other way** (`needs Take =
0`), because once the corridor is full of rolling stone there is no such thing as
walking out.

Five buttons is one more than the format had. Widening the sheet to six groups
was the whole cost — a blank `Choice N` still ends the list, so every existing
event is untouched and the two spare groups cost nothing.

### The percentages are the source's; the numbers are this game's

25% of Max Health and 8% of it are Slay the Spire's own figures, and they are the
one part of that game's damage that ports directly: a percentage does not care
that Health here is 5–10 rather than 75. What does not port is *printing* them.
"Take 25% of your Max Health" is a sum the player has to do at the exact moment
they are choosing, so the hole resolves against `MAX_HP` (§5.1) and the button
says **-3 Health**.

The `max(1, ...)` on both is not decoration. 8% of 10 Health rounds to nothing,
and a Hide that costs nothing is the obviously correct answer to an event that is
supposed to be a real decision.

### Smash is where a curse comes from something other than an event's own text

The third escape hands out `injury` — the curse Punch Off (§10) already uses.
Nothing was authored twice for it: the curse lives in `curses2.0`, and the second
event that wants it names it. That is the whole argument for §6 being a sheet
rather than a column.

---

## 13. The seventh worked example: Relic Trader

Slay the Spire 2's shadowy figure, and the first event whose **choices are not
the same choices twice**.

| | |
|---|---|
| `Where` | Dead End |
| `Limit` | 1 |
| `Prompt` | *"You turn a corner and suddenly, a shadowy figure is just standing there. He pivots to face you. 'Welcome! What're ya trading?'…"* |

| Choice | Effect | Result |
|---|---|---|
| **Take the Top One** | `trade_relic 1` | *"He takes `<give>` off you with both hands… and presses `<get>` into your palm…"* |
| **Take the Middle One** | `trade_relic 2` | *"'Good eye.' `<give>` vanishes into the lining. `<get>` arrives in its place, still warm."* |
| **Take the Bottom One** | `trade_relic 3` | *"…comes up with `<get>`. `<give>` is gone from your pack by the time he stands."* |
| **Trade Nothing** | `nothing` | *"You decline. The cloak closes…"* |

### The offers are rolled once, when the event opens

Placement is hashed so a card's badge cannot change under the player (§15). A
trade cannot be: it depends on the **inventory**, not on the node. So the three
pairings are rolled once, in `EventSystem.begin_event`, and held for as long as
the modal is up — re-rolling per repaint would rename the button under the
cursor, which is the same failure the hashed placement exists to prevent.

Each offer pairs one relic you hold against one you don't, with no relic on the
block twice and no two rows offering the same thing. **A run carrying one relic
is shown one row**, not three buttons that swap nothing: a `trade_relic` choice
with no offer behind it is simply not offered, which is the same gate machinery
`needs` uses.

### Both halves are drawn from the rollable pool only

No Starter, no Boss, no Event relic, in either direction
(`games-first-redesign.md` §8). A starter is the character you picked, a Boss
relic is a boss you beat, an Event relic is an event you walked into — none of
them is a thing to find in a stranger's coat, and none of them is a thing a
stranger should be able to take off you.

### What it needed from the format: a name hole

`{...}` resolves arithmetic. Naming a relic needed `<give>` / `<get>` (§5.2), and
that is the entire addition. The sentences — including which of the three rows
gets which phrasing — are in the spreadsheet, so the event is as portable as
every other one: GDScript knows what the two holes mean and nothing else about
the Relic Trader.

---

## 14. Other shapes, for reference

Not authored — these are here so the format can be read against more than one
event.

Shown a group per line for legibility; on the sheet each event is one row and
these run left to right.

```
Locked Chest    Choice 1 Open it       │ End │ needs keys 1; gain_chest medium 1
                Choice 2 Pry it open   │ End │ lose_hp 2; gain_chest small 1
                Choice 3 Walk away     │ End │ nothing
```

That is the plain shape — pick one, it resolves, the event closes — which is what
most events are and what the worked examples above deliberately are not. (The
Golden Idol used to be sketched here as the other plain one. It is authored now,
and it turned out not to be plain at all: see §12.)

---

## 15. How it runs

Built and under test (`test/test_events2.gd`). The pieces, and the one thing each
of them is really solving:

| Piece | Where | The problem it solves |
|---|---|---|
| `CurseData2`, `EventData2` | `scripts/resources/` | the schemas the sheet generates into |
| `generate_curse2_tres.py`, `generate_event2_tres.py` | `tools/` | sheet → `data/curses2.0/`, `data/events2.0/` |
| `EventSystem` | `scripts/autoload/` | placement, gates, resolving a choice |
| `event_goals` / `curse_goals` | `GameState` | run state, saved and reset with the run |
| `EventModal2` | `scripts/redesign2/` | the screen an event happens on |
| the badge, the checklist rows | `Overworld2` | telling the player before and after |
| the **Events** tab | `DevTools` | authoring: start one anywhere, and see which gate is hiding it |

**`EventSystem.blockers_for` is the one statement of the gates.** `_eligible_for`
is `blockers_for(...).is_empty()`, and the dev panel prints the same list in
words — so "why is my event not turning up" is answered by the code that decides
it, and the answer cannot drift from the decision. Placement being hashed rather
than rolled (below) is what makes that necessary: an author cannot reload their
way into a new event, so the gates have to be able to say what they are doing.
Starting one from the panel goes through `Overworld2.open_event`, which queues it
down the ordinary path rather than raising a modal of its own.

**The reward-token DSL has one implementation.** `generate_status_tres.py` owns
it; the two new generators import it rather than re-parsing `gain_chest small 1`
a second and third way. Extending it for events (`lose_*`, `heal_full`,
`gain_loot`, `apply_status`, `nothing`, and later `gain_item`, `spawn_enemy`,
`trade_relic`) left every existing status byte-identical.

**An event's live content is rolled in `begin_event`.** Almost every event is the
same event every time it fires, and everything about it can therefore live in the
`.tres`. The Relic Trader (§13) is the exception — its offers are built out of the
player's pack — so there is one hook, called once as the modal opens, for an
event to roll what the run has to tell it. Anything rolled there survives every
repaint of the modal and nothing else, which is exactly the lifetime such content
wants.

**Placement is hashed, not rolled.** `EventSystem.event_for(node)` hashes the
node id against `GameState.run_seed` (new, saved with the run). The offering is
redrawn constantly — a bash refilling a slot, a scramble, an arrival — and a
rolled event would change under the player between seeing the badge and taking
the card. `_slot_enemies` keyed off `_offer_seed()` solves the same problem for
the enemy behind a card; this follows it. The badge cannot lie.

**The badge shares the Amulet's row.** `_make_choice_card` already mounts a
fixed-height label above every cover, blank off the Amulet, so the covers stay in
line. `✦ EVENT` goes there in accent orange, and the Amulet wins the row when a
card is both — winning the run outranks a bonus. `GameChoiceModal` names the
event, since the popup is where the routing decision is actually made (§4.2).

**Only a beaten game earns its event.** Escaping forfeits it and leaves it
standing for a later visit, which is what keeps it a reward rather than a toll
for arriving. The modal is queued and opened from `_end_resolve`, after the board
has finished playing the resolve back, so it never lands on a moving battlefield.

**Three kinds of checklist row, three colours.** Enemy goals green, event goals
accent, curses `UITheme.CURSE` purple. Event goals and curses both show their
countdown, because an objective with a clock on it is a different decision on its
last game than on its first and the player can see that clock nowhere else. A
claimed event goal retires; a triggered curse does *not* — only its timer clears
it, which is the whole difference between a bonus and a bill.

**`play_game` is the only token that moves you.** It picks a tagged game, runs it
as an ordinary game (enemy and all) without counting as a route step, pays the
`->` payload when it is beaten, then offers stay-or-return — stay only when the
game is actually on the run graph, since standing on a node with no edges is a
dead run.

**And an event that sends you to a tag is not staged unless that tag has games.**
Punch Off's bargain is "do the work and take everything" against "take the
treasure and wear the Injury"; with no mecha game to go and play, the work option
is a dead button and the event is a worse version of itself. So
`EventSystem.games_with_tag()` is consulted *before the event is placed*, which
means before the badge is drawn — the badge stays honest. That pool respects the
run's game filter, so an OWNED run is only ever sent somewhere the player owns,
and it is the *same* list the destination roll uses: if the gate and the roll
disagreed, an event could advertise a detour it cannot deliver. The rule is
derived from the event's own content rather than authored in a `Requirement`
cell, so a future `play_game tag=<anything>` gets the same protection without
anyone remembering to ask for it.

**The modal sizes itself to its content.** Two columns when there is art — the
picture on the left, the words and the buttons on the right — so a full-height
illustration costs no vertical room. The panel then fits whatever is in it and
only starts scrolling once that would overflow the window, with the art staying
put beside the scrolling column. A two-option event is a small card; a
nine-option one is a full-height panel with a scrollbar. Neither is padded out to
the other's shape.

### What is still left

1. **The `encounters` merge.** `locations-and-events-design.md` §6 argues for one
   modal serving events *and* `encounters`. `EventModal2` is the modal that
   should absorb them; the combat-era `scripts/events/EventModal.gd` (d20 rolls
   against stats the redesign deleted) is now dead weight and can go with them.
2. **`Trigger: Before` is authorable but inert.** The column parses, generates
   into `EventData2.trigger` and is described in the Collection — and nothing
   reads it. `Overworld2` queues an event from `_end_resolve`, so every event
   fires after the game is beaten whatever the cell says. An arrival-time event
   is the one that could hand you a goal *for the game you are about to play*,
   which is a shape §8 wants; until it exists, leave the column on `After`.
3. **More events.** Eight events against ~330 leaves means most dead ends are
   still plain. Nothing structural stands in the way, and it is getting easier
   rather than harder: the five events before these needed three new columns
   between them, while Jungle Maze Adventure, Morphic Grove and Whispering
   Hollow needed no new columns at all and one new token (`lose_gold all`, §5).
