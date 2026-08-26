# Authoring an object (`objects2.0`)

An **object** is a machine you stand in front of.

It is the same authored shape as an event — one row, a prompt, choices in
numbered column groups, Effect cells in the shared reward DSL — and it is a
separate kind for three reasons:

| | event | object |
|---|---|---|
| **lifetime** | a room: opens, is answered, is gone | stands there while the run is on this game; travelling on ends it |
| **arrival** | fires on its own after every game | **spawned** — by an event, or by anything else that asks — and several at once |
| **state** | none beyond the run's | jams, gets blown up, and the Donation Machine's bank outlives the run |

Source of truth is the `objects2.0` sheet of `tools/Roguelikes.xlsx`, generated
into `data/objects2.0/*.tres` by `tools/generate_object2_tres.py`.

---

## 1. The columns

```
Name | Game | Tag | Image | Rarity | Limit | Unique
     | Where | Requirement | Trigger
     | Prompt | Chance Won | Chance Lost
     | Choice N | Repeat N | Result N | Effect N     ×6
```

| column | what it does |
|---|---|
| **Name** | the machine, and the id it is slugified into (`Donation Machine` → `donation_machine`) |
| **Game** | flavour credit — the real game this is lifted from. Shown on the Collection's page and nothing routes on it. |
| **Tag** | comma list. **Required**: a spawn asks by tag, so an untagged object is content nothing can reach. |
| **Rarity** | which rung of the ladder a spawn draws it from |
| **Limit** | times it may be spawned per run; blank = no limit |
| **Unique** | `Yes` = only one may stand in front of the player at a time |
| **Where / Requirement / Trigger** | reserved. Nothing reads them. They are the same three an event carries, ready for an object that stands on the map in its own right rather than being spawned. |
| **Prompt** | often blank, and that is authored rather than unfinished — the Blood Donation Machine keeps Isaac's silence |
| **Chance Won / Chance Lost** | the two endings of a `chance` roll, in the machine's voice |
| **Choice N …** | read left to right until a blank `Choice N`, exactly as on `events2.0` |

`Repeat`, `Result` and `Effect` mean precisely what they mean on an event — see
`docs/event-sheet-authoring.md`. A machine is usually `Repeat: Again`, because
the whole shape of one is "press this as many times as you can pay for it".

---

## 2. How a machine reaches the screen

Objects are **spawned**. Today that is an event (`spawn_object tag=arcade 2-3`)
or the dev panel's Events tab; the seam is the same either way, so anything
added later gets both places to appear for free.

Each spawn slot rolls **independently**:

1. roll the rarity ladder (Luck rerolls it, like every other roll in the build);
2. draw from that rung of the tag's objects, **falling down the ladder** to the
   nearest stocked rung when the rolled one is empty;
3. skip anything blown off the run, anything at its `Limit`, and anything
   `Unique` that is already standing there.

Duplicates are otherwise fine. An arcade with two Blood Donation Machines in it
is an arcade.

**Where it draws:**

- spawned by an **event** → inside that event's modal. The Arcade Room *is* the
  room the cabinets are in, so the machines are in there with you and the room's
  own `Leave` walks you out of both.
- spawned by **anything else** → under the board, in the space a hub's shop
  takes (`ObjectPanel2`). Nothing is blocked, and travelling on clears it.

The two places draw the machine at different sizes, and the reason is arithmetic
rather than taste. An event's modal is a screen of its own and shows the full
`ObjectCard` — art, prompt, every button with its cost line and its ☠ warning,
about 341px of it. The PAGE has roughly 124px to give: the overworld is built to
fit a fixed 1280×720 canvas (`stretch/mode` scales that box into any window, so
a 1440p monitor gets the same 720 of room) and it already uses 683 of it. So on
the page a machine is a **30px row** — art, name, and the one fact worth reading
without opening anything ("Jammed", "holds 37 gold"), plus a ☠ when a lever
there would end the run — and clicking it opens the same full card over the
page. Two rows fit across the column, so three machines cost two lines.

The board pays for the panel: while it is sharing its column it fits itself to a
tighter height budget (`BattlefieldView.set_sharing_column`) and springs back
when the machines go. It never shrinks past `CELL_MIN` — a board you cannot read
is not a saving.

---

## 3. The object verbs

On top of the whole shared reward DSL, an Effect cell may say:

| clause | what it does |
|---|---|
| `gain_pickups <lo>-<hi> hp\|gold` | that many loose pickups, each independently one of the listed kinds |
| `gain_item_of <id>\|<id>` | one named relic at random from the list |
| `donate_gold <n>` | purse → bank, capped at the machine's 999 |
| `bank_payout <lo>-<hi>` | bank → purse, capped at what the bank holds |
| `jam_object` | takes no more coins for the rest of the run |
| `destroy_object [run]` | gone. Bare = this machine; `run` = every one of its kind, off the run. |
| `spend_bomb <n>` | a Bomb spent off the battlefield — fires `bomb_used`, so Blood Bombs still pays |
| `spawn_object tag=<t> <lo>-<hi>` | put machines in front of the player (usable from `events2.0` too) |

And two gate forms that ask the **machine** rather than the player:

```
needs not_jammed
needs bank_space
```

They exist as two separate flags rather than one so the greyed-out button can say
**"Jammed"** and **"Full"** — different refusals, said differently.

### `roll` vs `chance`

Both roll. They are not the same thing:

```
chance 6.7% -> gain_item_of blood_bag|iv_bag; destroy_object else gain_gold 1
roll 5% gain_stat luck 1
```

- **`chance`** is the cell's one headline gamble. It claims the `->` payload,
  prints the object's `Chance Won` / `Chance Lost` prose, and winning it closes
  the thing. Its `else` half is what pays on a loss — the Blood Donation
  Machine's needle goes in either way, and what comes back is a coin or a burst
  machine.
- **`roll`** is an independent proc: no prose, does not close anything, and as
  many per cell as you need. The Donation Machine puts two on one coin.

Percentages may be **fractional** (`6.7%`) and may carry a `{expr}` hole that
climbs per press (`{1+X}%`, where X is presses so far **on this machine, this
visit**). That is the whole of how the Donation Machine's jam chance escalates
and resets: a fresh machine has a fresh X.

### `{ITEM}`

In `Chance Won`, `{ITEM}` is replaced with whichever relic the `gain_item_of`
actually rolled — "The machine exploded, and IV Bag appeared."

---

## 4. The two authored machines

### Blood Donation Machine (`arcade`)

No prompt. Two buttons.

```
Give Blood   Again   lose_hp 1;
                     chance 6.7% -> gain_item_of blood_bag|iv_bag; destroy_object
                                 else gain_gold 1
Bomb                 needs bombs 1; spend_bomb 1; gain_pickups 2-4 hp|gold; destroy_object
```

The button reads `-1 Health · 93.3%: +1 Gold · 6.7%: +Blood Bag or IV Bag`, with
**both numbers moving with your Luck** — at 1 Luck the burst is really 12.95%
and the button says 13%, because a button that still said 6.7% would be lying to
a player who bought a Clover for exactly this. Exploding is the outcome Luck
pushes *toward*: a relic beats a coin.

**It is not gated on having Health to spare.** Isaac lets you kill yourself on
one of these and so does this: the button stays live all the way down. What
stands between the player and that is the warning, not a lock:

```
-1 Health · 93.3%: +1 Gold · 6.7%: +Blood Bag or IV Bag
☠  This will kill you.
```

**Red means dead, and nothing else does.** The button, its cost line and the
warning under it all fire on one condition — this press can end the run
(`EventSystem.is_deadly` / `danger_color` / `lethal_warning`) — and a press you
can walk away from is drawn exactly like a free one however steep it is. Two
earlier versions of this are gone: the cost line used to warm through pink as
the Health left ran down, and a second warning ("⚠ You can die here — this
leaves you at 1 Health") fired one press early on anything that took you within
one more of the same cost. Both fired on most of the costly buttons in the game,
which taught the player to read past a colour and a line that were about to
matter.

What replaced the early warning is a **second press**: clicking a red button
raises an "Are you sure?" (`EventSystem.confirm_deadly`) naming the cost and the
Health you are holding. A death here is the run, and a run is hours of somebody
actually playing real games — it is worth one more click. Events get the same
treatment: Abyssal Baths' Linger climbs until it can kill, and the press that
can is the one that turns red and asks.

Bursting or bombing ends **that** machine. Another may still turn up.

### Donation Machine (`arcade`, `Unique`)

```
Give Gold   Again   needs gold 1; needs not_jammed; needs bank_space;
                    donate_gold 1; roll 5% gain_stat luck 1; roll {1+X}% jam_object
Bomb                needs bombs 1; spend_bomb 1; bank_payout 2-5; destroy_object run
```

The bank is **one bank, shared by every Donation Machine, persistent across
runs** (`GameStats.donation_bank_total`, in `user://game_stats.json`). It is the
only number in this build that deliberately outlives a run — a bank you could
empty by starting a new run would not be a bank. It holds up to **999**; at the
cap the button greys out as **Full**, and you can still bomb it.

The jam chance climbs **1%, 2%, 3%…** while you stand there and resets to 1% when
you travel on. An actual jam is permanent for the run — a jammed machine still
turns up, it just takes nothing. A **bombed** one takes every donation machine off
the run, which is the trade: the bank, or the run's donation machines.

---

## 5. Things that will bite you

- **An untagged object can never spawn.** The generator refuses one.
- **`Unique` is not `Limit`.** `Unique` is "two may not stand together";
  `Limit` is "this may only ever be spawned N times this run".
- **A machine has no `Leave` button** unless you author one. You leave by
  travelling on, and an event that spawned machines leaves them with its own
  `Leave`. A machine whose every button is spent and gone should have destroyed
  itself instead.
- **`destroy_object` without `run` only removes the one you pressed.** If the
  machine should be off the run, say `run` — the sheet is the only place that
  distinction is stated.
- **Ranges are literals.** `2-4` is fine, `{2+X}-4` is not: a spread is quoted on
  a button up front, and a spread whose ends move per press is a number nobody
  can read.
