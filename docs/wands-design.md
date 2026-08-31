# Wands — design & implementation

Companion to [`games-first-redesign.md`](games-first-redesign.md) (the canonical
spec). That doc's §4.1 is scrolls and its §4.3 is pills;
[`potions-design.md`](potions-design.md) is the third loot consumable and
[`cards-design.md`](cards-design.md) the fourth. This one is the **fifth**, and it
is the one that stops being loot the moment you spend it — and then carries on
being loot anyway.

Content source: the **`wands`** sheet of `tools/Roguelikes.xlsx` (4 rows) and the
28 sticks in `images2.0/wands_unidentified/`. There is no `images2.0/wands/` folder
and none is wanted (§6.3).

Status: **BUILT.** `WandData`, `tools/generate_wand2_tres.py`, the sheet's 4 Effect
cells, `WandSystem` (autoload #25), the five-way loot split, the charge economy,
the aim step, the widened `charge` op and the Collection's Wands page all shipped
together, with `test/test_wand_system.gd` covering them.

*A bare §x is a section of this document. Spec sections are written **spec §4.3**
and so on, because the numbering collides.*

---

## 1. Why a fifth kind

The four kinds already covered both halves of one question. A scroll, a pill and a
potion are each an unknown you spend to find out what it was; a card is the one you
can read before spending. Between them, "what is this?" is a settled question, and
a fifth alphabet of mysteries would have been a fourth variation on a trade the run
already makes three times.

So a wand asks a different question, and it asks it of the **pack** rather than of
the piece. Every other kind is one slot for one effect: you pick the moment, you
spend it, the slot comes back. A wand is one slot for **four to six** effects, and
it holds that slot until it is empty.

That turns the pack cap — nine pieces, spec §4.3 — from a background constraint
into the thing the kind is about. A Wand of Fire is four Scrolls of Fire that you
must carry all at once, in one slot, and cannot put down half of. Whether that is
a good trade depends on what else is in the bag, which is a question no other piece
of loot has ever made the player ask.

---

## 2. What a wand is

**One piece of loot with a charge count on it.** Zapping it spends one charge and
leaves the wand in the pack; zapping the last one spends the wand.

It is a **gamble** like a scroll, a pill and a potion, and not like a card: an
unknown wand hides its name, its Preference and its effect behind a material the
run dealt it, and the only way to learn what it is is to fire it. What makes the
gamble different in kind is what you win. Learning that the swirly bottle was Fire
Potion tells you something about a bottle you no longer have; learning that the
oak stick is Wand of Fire tells you something about **the five charges still in
your hand**. The first zap is the price of the other five.

Three consequences, and each is a rule somewhere in the code:

- **The charge is on the entry, not on the resource.** Two Wands of Fire in one
  pack are two different amounts of wand. `WandSystem.charges_of(entry)` reads the
  pack row and `spend_charge` writes it back, exactly as a pill's dose rides on its
  entry rather than on `PillData`.
- **Identification covers every charge at once.** One zap and the whole stick is
  known. A wand that had to be learned six times would be six gambles for the price
  of one slot, which is the opposite of what the kind is for.
- **It stands outside Echo Chamber entirely** (§4.4).

---

## 3. The material, and the twenty-four spares

An unidentified wand introduces itself by its **material** — "Oak Wand", "Iridium
Wand", "Runed Wand" — which is the potions' rule (potions-design §6.4) rather than
the pills', for the same reason: 28 sticks cannot be told apart in a run log any
other way, and naming the wood is not naming what is in it.

`WandSystem.MATERIALS` is the 28 files in `images2.0/wands_unidentified/`, as a
const list rather than a directory scan — the deal has to be reproducible from the
save (`GameState.wand_material_map` stores names, not indices), and a file going
missing should fail as one broken texture rather than as a silently smaller
alphabet. `test_wand_system.gd` checks the list against the folder **in both
directions**; art that ships without being listed is art no run can ever show,
which is the one gap `test_pill_system.gd` still has.

**Twenty-four sticks are dealt to nothing**, which is the widest spare pile in the
project: six spares per wand, against the potions' one-and-a-half and the pills'
three-in-thirteen. It has to be, because the roster is four. With four materials
over four wands the fourth would be free the moment you knew the other three; with
twenty-eight, knowing three narrows the fourth to one of twenty-five.

---

## 4. Spending one

### 4.1 The charge, and the slot

`LootSystem.use_loot` is the one place this lives, and it is one branch:

```
a wand with charges left  →  spend one, write it back to the same slot, resolve
a wand on its last charge →  remove it from the pack, resolve
everything else           →  remove it from the pack, resolve
```

The charge comes off **before** the effect resolves, for the same reason a consumed
piece leaves the pack first: a wand that grants loot must not find itself still
holding the charge it is being fired with, and the "3 / 6" the outcome screen reads
has to be what is left rather than what there was.

A zapped wand **does not move slots**. `loot_items[index]` is replaced in place, so
every other piece keeps its index (`use_loot` is addressed by them) and the player's
arrangement survives firing something in the middle of it.

**A loose wand spends a charge too.** `use_entry` is `use_loot` with no slot to
settle — the offer taken on the spot rather than carried (spec §4.3) — and it is the
one place a wand could have fired for free, since there is no pack row to write the
count back to. It mutates the entry it was handed instead.

**The count comes back on the result**, as `charges_left`. The screen reporting a
use holds its own copy of the entry, and on the pack path that copy was made *before*
the charge came off, so a modal reading its own `_entry` would print the count as it
stood a moment ago. Every other kind's result has no such key, because nothing else
is counting.

### 4.2 Aiming

The sheet's `Type` column is what a wand wants pointed at it:

| `Type` | `targeting` | means |
|---|---|---|
| Ray | `ray` | a square of the board, picked the way a thrown potion's is |
| Non-Directional | `non_directional` | nothing; it fires where it stands |
| Random | `random` | one of the other two, **rolled fresh on every zap** |

`random` is authored on exactly one row and that is not an accident. Wand of
Nothing does nothing, so the only thing that could ever give it away is behaving
identically twice — and a wand that asks for a square one zap and not the next is a
wand you cannot rule anything out about.

**An unidentified wand always asks for a square**, whatever its type, and that is
`WandSystem.needs_target`'s whole job. Asking only the ray-shaped unknowns would
tell the player which half of the roster a mystery stick belongs to before they had
spent anything, which is exactly the fact the gamble is selling. A known
non-directional wand stops asking; a known ray keeps asking; a known `random` keeps
asking, because it might want one.

The picker is the **potion throw's**, reused (`Overworld2.begin_loot_throw`), and
nothing is spent while the player is aiming: the charge comes off in `use_loot`
when the square is clicked, so backing out of the picker costs nothing. What is
*not* shared is `_verb` — a potion's throw is one of its two verbs and the player
chose it; a wand has one verb, and it is Zap.

### 4.3 The cell reaches the ops

`ctx.target` carries a `Vector2i`, the same key `EffectSystem._effect_cells` and
`PotionSystem.throw_potion` already read, so an aimed wand and an aimed Red Candle
reach the ground the same way. A clause's `area=` is measured from that cell;
`area=board` needs no cell at all and works on a wand fired blind.

### 4.4 Echo Chamber does not see it

**A wand is never echoed, and zapping one fires no echoes either.** The two halves
are one rule — the relic copies pieces that were *consumed* — and both are needed:

- A wand copied three times would be four effects for one charge. Echo Chamber
  would be worth most on the kind that already gets to fire six times.
- A wand that replayed the memory **without** joining it would be three free copies
  of your last pill, once per charge, for the price of one slot. Nothing else in
  the pack can pay a relic six times.

So `LootSystem.use_entry` skips both the queue and the memory for a wand, and
`LootUseModal` does not draw the "Echo Chamber will also use…" note over one.

---

## 5. The roster

Four rows, one per rung of the rarity ladder — which makes the shared ladder do all
the work. At its 75/20/5 with the Rare rung's 10% bump to Legendary, `Data.roll_wand`
gives Nothing on three drops in four, Create Monster on one in five, Fire on about
one in twenty-two and Wishing on about one in two hundred (before Luck, which rides
the same roll). None of that spread is authored anywhere except in the four rarity
words.

| Wand | Rarity | Charges | Type | Effect cell |
|---|---|---|---|---|
| **Wand of Nothing** | Common | 6 | Random | `nothing` |
| **Wand of Create Monster** | Uncommon | 6 | Non-Directional | `spawn_enemy current` |
| **Wand of Fire** | Rare | 4 | Ray | `apply_status burn 3 target=enemy; apply_tile fire` |
| **Wand of Wishing** | Legendary | 1 | Non-Directional | `obtain_item any` |

**The charge count is the rarity ladder read a second way.** The Legendary has one
charge and the two cheapest have six, which is what lets a Common wand and a
Legendary one sit in the same pack without the Common being strictly worse: six
zaps of nothing is still six chances to have been holding something else.

### 5.1 Wand of Nothing — the joke that has to be authored

`nothing` is a **verb** in the effect DSL, and every other empty Effect cell is
refused by the generator. A blank cell cannot be told apart from a row somebody has
not filled in yet, so the sheet says the nothing out loud. (The potions generator
takes the opposite line and reads a blank as authored, which is why a Potion of
Uselessness typo would ship silently. This is the better rule; potions predate it.)

### 5.2 Wand of Wishing — the relic that became a wand

It was an `Usable, 1` item in `items2.0` with the same `obtain_item any` effect.
Having it in two kinds at once would have meant a run could hold a relic and a
piece of loot that are the same NetHack wand with two different rules for spending
it, so the item row is gone from the `items` sheet and `data/items2.0/` and the art
went with it. What did **not** move is the machinery: `EffectSystem._h_obtain_item`,
`Overworld2.obtain_any_item` and `RewardScreen.setup_obtain` are all still there and
still the full-catalog picker — the wand hands back an `obtain_item` **request** and
`LootUseModal._do_obtain_item` opens the same screen.

One thing to know about the roster after this: **no item is `overworld_usable` any
more.** The flag and `PackStrip.fires_while_reporting` still work and are still
right; there is simply no content wearing them, exactly as happened to the USABLE
kind when Ride the Bus became a card (cards-design §5.1).

### 5.3 Wand of Fire

Scroll of Fire's pair of clauses, aimed instead of fixed to the front column: +3
Burn on whatever is standing on the square, and the Fire tile on the square itself.
It goes through `GameLoop2.apply_tile`, so fire laid on a mine annihilates with it
and fire laid under a body bites it on the spot (spec §17), exactly as a thrown
potion's would.

### 5.4 Wand of Create Monster

Scroll of Create Monster's op, six times over. It rolls at the run's **own**
difficulty, which is what keeps a Negative piece of loot expensive: a cost that
stayed flat while the roster climbed would stop being a cost.

---

## 6. What the player sees

### 6.1 In the pack

The tile carries **two** corner plates. Bottom-right is the Preference badge every
other kind wears (`?` while unknown); **bottom-left is the charge count**, and it
is drawn whether or not the stick is known. The button under it says **Zap** rather
than Use, which is the one place a 40px tile can say that pressing this does not
empty the slot.

### 6.2 Charges are never hidden

How many zaps are left is not part of the gamble. It is what the player is buying a
slot for, and a mystery wand you cannot count is a mystery about whether to carry
it as well as about what it does. So the count appears on the tile, in the hover
subtitle beside the Preference, in the description line, and on the outcome screen
("5 of 6 charges left." / "The wand is spent.") — known or not.

### 6.3 There is no identified wand art

`WandData.file` exists and `WandSystem.art_texture` prefers
`images2.0/wands/<File>.png` where it resolves, but **no row has one and none is
waiting for one**. An identified wand keeps showing the material it has worn all
run, which is honest: the material is a real fact about that wand in that run, and
it is the fact the player learned it by. This is the potions' §6.3 fallback applied
to the whole roster rather than to six of fifteen.

The Collection's Wands page therefore draws **no art at all** — a stand-in stick
would be showing a material that means nothing, since the association is randomised
every run. It draws the charge count and the targeting mode instead, in words
("aimed at a square", "fires where you stand", "aimed, or not — it varies").

### 6.4 Known this run

`LootDiscoveries` grows a fourth alphabet: Wands, beside Pills, Scrolls and
Potions, with the unlearned **counted and never listed** for the reason the other
three are — a row of blanks that could be counted would give the spares away. Cards
are still absent, because there is no such thing as an identified card.

---

## 7. Charging a wand

**Anything that charges items charges wands, and says so.** A wand runs on charges
in exactly the sense a D6 does — a bar that empties as you spend it and can be
filled back up — so the op that fills bars fills these too.

The pool is `GameState.chargeable_things()`: every charged relic in the inventory
plus every wand in the pack **with room in it**. Each is topped up through
`charge_thing`, which is the single place that knows a relic's bar lives on the
relic and a wand's lives on the pack entry. `PillSystem._charge` is written against
those two functions rather than against the halves, so a relic and a wand can never
drift on what "charged it" means.

Two rules ride on it:

- **The name a charge line writes is the one the run knows.** A pill that reported
  charging "Wand of Fire" over a stick the player had never zapped would identify it
  for free, and the charge is not the gamble. `charge_thing_name` goes through
  `LootSystem.display_name`, so an unknown wand is charged by its material.
- **Beating a game does not charge a wand.** `GameState.charge_all_items` runs on
  every beaten game and is the relics' and only the relics'. A relic's bar refilling
  on its own is what makes it a relic; a wand's charges are the whole of what you
  found, and a wand that topped itself up every game would be an infinite one — six
  Wands of Fire for the price of a slot, and no reason ever to spend the last charge.

**48 Hour Energy's card was reworded in the sheet** to "…Chargeable Items and
Wands" (both doses), because a pill whose card promises items while the effect
quietly tops up a wand is the card lying about what it does.

---

## 8. Where the code lives

| Piece | File |
|---|---|
| Schema | `scripts/resources/WandData.gd` |
| Generator | `tools/generate_wand2_tres.py` (+ the one-shot `tools/_wands_sheet_setup.py`) |
| Content | `data/wands2.0/*.tres` (4) |
| Brain | `scripts/autoload/WandSystem.gd` (autoload #25) |
| Catalog | `Data.get_wand` / `all_wands` / `roll_wand` |
| Run state | `GameState.wand_material_map`, `identified_wand_types`, `LOOT_KINDS`, `add_wand_loot`, `chargeable_wands` / `chargeable_things` / `charge_thing*` |
| Spending | `LootSystem.use_loot` (the charge branch), `use_entry` (the loose charge), `_spend` (the echo exception, and `charges_left` on the result), `is_wand`, `must_aim`, `charges` |
| Screens | `LootUseModal` (`_arm_aim`, `_do_obtain_item`, the charges line), `LootGrid` (the count plate, the Zap button), `LootDiscoveries` (the Wands row), `Collection` (the Wands page) |
| Save | `SaveSystem` — `identified_wand_types` + `wand_material_map`; the charges ride inside `loot_items` |
| Signal | `TriggerBus.wand_used` — once per **charge** |
| Tests | `test/test_wand_system.gd` (42) |

---

## 9. What is not done

- **No item watches `wand_used` yet.** The signal is emitted and is the only loot
  signal that can fire six times off one piece, which is what a relic reading it
  would have to be priced against.
- **No wand has art of its own** (§6.3). This is the design today rather than a
  gap, but the `file` field and the `images2.0/wands/` lookup are there for the row
  that wants one.
- **Nothing recharges a wand except 48 Hour Energy**, because it is the only
  content that authors `charge`. Everything needed for a second such piece is in
  place (§7).
- **The roster is four.** A fifth of every drop comes off it, so it will repeat; the
  sheet is where that gets fixed, and nothing in the code caps it.
- **`gain_loot` is authored by no row.** The op is implemented because a wand that
  pays out is the obvious next row and it was one function.
