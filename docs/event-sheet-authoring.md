# Event sheet-authoring (`events2.0`)

Status: **the sheet format is settled and the first event is authored. The
generator and the runtime are not built yet** — see §8 for what's left. Companion
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

## 2. The shape of the sheet: one row per CHOICE

Every other `*2.0` sheet is one row per object. Events are not, and the reason is
worth stating because it is the whole format decision:

**an event is mostly prose, and it has a repeating sub-structure.** Pack four
choices into one delimited cell and the cell stops being editable in a
spreadsheet — which is precisely how the old `events` sheet failed. Look at what
it did: catalogue metadata in the sheet, and every choice, outcome and effect
hard-coded in an `AUTHORED` dict inside `tools/generate_event_tres.py`. The sheet
could not hold the part of an event that *is* the event.

So: **an event is a BLOCK of contiguous rows sharing an `Event` name.** The first
row carries the event's own columns *and* its first choice; each row below adds
another choice with the event columns left blank.

```
Event         │ Game             │ … │ Prompt          │ Choice  │ Repeat │ Result      │ Effect
Abyssal Baths │ Slay the Spire 2 │ … │ Steam curls off │ Immerse │ Again  │ The water … │ gain_max_hp 1; lose_hp {1+X}
Abyssal Baths │                  │   │                 │ Abstain │        │ You dry off │ gain_hp 2
```

You can read an event down the page, edit one outcome without touching the
others, and every piece of prose sits in its own cell where the formula bar can
show all of it.

Two rules follow from the block being the unit:

- **Row order is choice order.** The choices appear in the modal top to bottom in
  sheet order.
- **Don't sort the sheet.** Sorting scatters a block and an event loses its
  choices. `Event` is repeated on every row so a block is still *recoverable*
  after an accidental sort, and the generator will refuse a sheet where one
  `Event` name shows up in two separate blocks — which is what a sort looks like
  from the other end.

---

## 3. Columns

| Column | Scope | Meaning |
|---|---|---|
| `Event` | **every row** | Display name, and the block's grouping key. Repeated on choice rows — that is what makes filtering by event work and what catches an accidental sort. |
| `Game` | event | The real game this is lifted from. Flavour credit (the modal's "From: *game*" line), and the target when `Where` is `Game`. |
| `Tier` | event | `All`, or a comma list of `Low` / `Medium` / `High` / `Insane`. Gates an event to part of the tier ladder, the same vocabulary `enemies2.0` gates on. |
| `Where` | event | Placement. `Dead End` (default — a node with one connection, §1), `Any`, or `Game` (only ever on its own `Game`, the way Abyssal Baths belongs to the Underdocks). |
| `Trigger` | event | `After` (default — fires once the game there is beaten, so it reads as an extra reward) or `Before` (fires on arrival, before the game is played, so it can hand you a goal for it). |
| `Rarity` | event | `Common` / `Uncommon` / `Rare`. Weights the roll, same ordering as items and scrolls. |
| `Limit` | event | Times per run. A number, or `None` for no limit. |
| `Image` | event | Art base name → `res://images2.0/events/<Image>.png`. Blank falls back to the de-spaced `Event`, matching every other 2.0 sheet. |
| `Prompt` | event | The prose at the top of the modal. |
| `Choice` | choice | The button label. |
| `Repeat` | choice | What picking it does to the event — see §4. Blank = `End`. |
| `Result` | choice | The prose shown once the choice resolves. |
| `Effect` | choice | The machine-readable payload — see §5. |

A blank `Effect` is legal and means the choice does nothing mechanical, which is
a real thing an event wants (walking away should be authorable without inventing
a reward for it). Write `nothing` when the blank would read as unfinished.

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
row escalates on its own, instead of needing four near-identical rows that drift
apart the moment anyone tunes them.

An event with no reachable `End` is fine as long as some choice is `End` or the
modal always offers a way out; the generator will warn on a block where every
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
needs <token>            a gate — the choice is offered only if the player can pay
add_goal "<condition>" -> <reward>; <reward>
```

`needs` leads a cell (`needs keys 1; obtain_item` — spend a key, take an item).
`add_goal` bolts an extra objective onto the **next** game, paying its reward if
it is met and costing nothing if it is not; the condition is authored in the same
honour-system voice as an enemy goal. It is the token that makes an event native
to this game rather than imported from a deckbuilder — the gamble is whether you
can actually do the thing in the real game, not what a die says.

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

## 6. The worked example: Abyssal Baths

In Slay the Spire 2 it is an Underdocks event: **Immerse** is +2 Max HP for 3
damage and can be taken over and over with the damage climbing until it kills
you, and **Abstain** heals 10 and leaves. It survives translation almost intact,
because what makes it work is not its numbers but the fact that the exit is
always one click away and you keep not taking it.

The numbers do have to move. Health here is 5–10, not 75:

| | Slay the Spire 2 | `events2.0` | Why |
|---|---|---|---|
| Immerse | +2 Max HP, take 3, escalating | `gain_max_hp 1; lose_hp {1+X}` | Costs 1, then 2, then 3 — cumulative 10 by the fourth dip, so a full-health character really does die in there. |
| Abstain | Heal 10, leave | `gain_hp 2` | ~13% of max in Slay the Spire 2; 2 of 5–10 here is the same shrug. |

The pair interacts, which is what keeps it a decision instead of a slider:
`gain_hp` is capped by Max Health and Immerse *raises* Max Health, so bathing
twice and then abstaining nets +2 Max Health for 1 Health. The optimal line is
neither "never get in" nor "stay until it kills you", and the player has to find
it in their own HP total.

`Where: Dead End` is doing real work here, and not only because of §1 — an event
that can kill you is one you must have *chosen* to walk toward. Hanging it off a
node nobody is forced through is what makes it fair.

**These numbers are a first pass and are meant to be tuned in the sheet.** That is
the point of the sheet being upstream.

---

## 7. Other shapes, for reference

Not authored — these are here so the format can be read against more than one
event.

```
Event          Choice          Repeat   Effect
─────────────────────────────────────────────────────────────────────────────
Golden Idol    Take the idol   End      obtain_item; apply_status marked 1
               Leave it        End      nothing

The Colosseum  Challenge       End      add_goal "beat it without spending more
                                        than one try" -> gain_item; gain_item
               Watch           End      gain_gold 20

Locked Chest   Open it         End      needs keys 1; gain_chest medium 1
               Pry it open     End      lose_hp 2; gain_chest small 1
               Walk away       End      nothing
```

The Colosseum row is the `add_goal` shape and the one worth studying: the event
resolves instantly, but what it hands you is a *restriction on the next real
game*, and the payoff lands only if you pull it off.

---

## 8. What is still missing

The sheet is authorable now. Nothing reads it yet.

1. **`EventData2` + `tools/generate_event2_tres.py`** → `data/events2.0/`.
   Closest model is `generate_status_tres.py`, which already parses the reward
   tokens and the `{expr}` holes this sheet reuses — the new work is the block
   grouping and the `Repeat` column, not the DSL. Note the *existing*
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
4. **The modal.** One modal for events *and* `encounters`
   (`locations-and-events-design.md` §6) — not two. `EventModal.gd` is combat-era
   (d20 rolls against `charisma` / `dexterity` / `intelligence`, stats the
   redesign deleted) and is a rewrite, not an edit.
5. **`images2.0/events/`.** The folder does not exist yet; `Image` names point
   into it.
