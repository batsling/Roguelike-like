# Event sheet-authoring (`events2.0`)

Status: **the sheet format is settled and two events are authored. The
generator and the runtime are not built yet** — see §9 for what's left. Companion
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
same four columns for 2, 3 and 4. Twenty-seven columns in all — eleven for
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

Eleven event columns, then `Choice N` / `Repeat N` / `Result N` / `Effect N`
for N = 1…4.

| Column | Scope | Meaning |
|---|---|---|
| `Event` | event | Display name, and the id everything else keys off. |
| `Game` | event | The real game this is lifted from. Flavour credit (the modal's "From: *game*" line), and the target when `Where` is `Game`. |
| `Tier` | event | `All`, or a comma list of `Low` / `Medium` / `High` / `Insane`. Gates an event to part of the tier ladder, the same vocabulary `enemies2.0` gates on. |
| `Where` | event | Placement. `Dead End` (default — a node with one connection, §1), `Any`, or `Game` (only ever on its own `Game`, the way Abyssal Baths belongs to the Underdocks). |
| `Trigger` | event | `After` (default — fires once the game there is beaten, so it reads as an extra reward) or `Before` (fires on arrival, before the game is played, so it can hand you a goal for it). |
| `Rarity` | event | `Common` / `Uncommon` / `Rare`. Weights the roll, same ordering as items and scrolls. |
| `Limit` | event | Times per run. A number, or `None` for no limit. |
| `Image` | event | Art base name → `res://images2.0/events/<Image>.png`. Blank falls back to the de-spaced `Event`, matching every other 2.0 sheet. |
| `Prompt` | event | The prose at the top of the modal. |
| `Goal Met` | event | Printed when an `add_goal` this event handed out is completed. |
| `Goal Missed` | event | Printed when that goal's window closes unmet. |
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
`lose_stat <stat> N`, `lose_gold N`, `gain_scroll N`, and the two event-only
forms below.

There is **no `kill` / `end_run` token and there should not be one**: a `lose_hp`
that empties Health ends the run through the rule that already exists (§2), which
is how Abyssal Baths kills you in Slay the Spire 2 as well.

The two event-only forms carry the weight `locations-and-events-design.md` §6
asked them to:

```
needs <token>                  a gate — offered only if the player can pay
needs <Choice> <op> <n>        a gate — offered only at this point in the event
add_goal "<condition>" [for <n> games] -> <reward>; <reward>
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

An `add_goal` objective lands in its **own section of the post-game checklist**,
the *event goals*, separate from the enemy goals and the character's level-up
row. It has to be: an enemy goal is a debt that hits you when missed and an event
goal simply expires, and a checklist that renders both the same way is lying
about which one bites (`locations-and-events-design.md` §1 draws the same line
for locations).

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

## 6. The first worked example: Abyssal Baths

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

## 7. The second worked example: Battleworn Dummy

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
rest already exist.

---

## 8. Other shapes, for reference

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

## 9. What is still missing

The sheet is authorable now. Nothing reads it yet.

1. **`EventData2` + `tools/generate_event2_tres.py`** → `data/events2.0/`.
   Closest model is `generate_status_tres.py`, which already parses the reward
   tokens and the `{expr}` holes this sheet reuses — the new work is walking the
   numbered choice groups and the `Repeat` / `needs` semantics, not the DSL. Note
   the *existing*
   `generate_event_tres.py` reads the legacy `events` sheet and its combat-era
   d20 outcomes; it is not a starting point, it is the thing being replaced.
2. **Placement.** Assign an event to a node deterministically — seeded off the
   node id and the run seed, not rolled when the card is drawn — or the badge in
   step 3 will lie the moment the offering is redrawn. `Overworld2` already
   solves exactly this problem for the enemy behind a card (`_slot_enemies`
   keyed by `_offer_seed()`); the event assignment should follow it.
3. **The badge above the game choice.** There is already a badge row mounted
   above every cover for this: the `flag` Label at the top of
   `_make_choice_card`, which renders `🏆 THE AMULET` on the Amulet's card and an
   empty string of the same height everywhere else, so the covers stay in line.
   The event marker belongs on that row — same line, same discipline of
   reserving the space on every card.
4. **The event-goal section of the post-game checklist.** Where an `add_goal`
   objective lives while it is live: its condition, its countdown (`2 games
   left`), its reward, and the `Goal Met` / `Goal Missed` line when it resolves.
   Its own section, kept apart from the enemy goals — those are debts that hit
   you when missed, an event goal merely expires, and rendering them alike would
   misrepresent which one bites. `Overworld2._verify_box` is where the checklist
   is built.
5. **The modal.** One modal for events *and* `encounters`
   (`locations-and-events-design.md` §6) — not two. `EventModal.gd` is combat-era
   (d20 rolls against `charisma` / `dexterity` / `intelligence`, stats the
   redesign deleted) and is a rewrite, not an edit.
6. **`images2.0/events/`.** The folder does not exist yet; `Image` names point
   into it (`AbyssalBaths`, `BattlewornDummy`).
