# Cards — design & implementation

Companion to [`games-first-redesign.md`](games-first-redesign.md) (the canonical
spec). That doc's §4.1 is scrolls and its §4.3 is pills;
[`potions-design.md`](potions-design.md) is the third loot consumable. This one is
the **fourth**, and it is the one that breaks the pattern the other three share.

Content source: the **`cards`** sheet of `tools/Roguelikes.xlsx` (13 rows), the
faces in `images2.0/cards/` (13 PNGs) and the deck icons in
`images2.0/cards_icons/` (5 PNGs).

Status: **BUILT.** `CardData`, `tools/generate_card2_tres.py`, the sheet's 13
Effect cells, `CardSystem` (autoload #24), the four-way loot split, the floor
mask, the six new ops, the Collection's Cards page and the dev panel's Cards
grant all shipped together, with `test/test_card_system.gd` covering them.

*A bare §x is a section of this document. Spec sections are written **spec §4.3**
and so on, because the numbering collides.*

---

## 1. Why a fourth kind

The run already had three consumables and they were all selling the same thing.

A scroll, a pill and a potion are each an **unknown** you spend to find out what it
was. The alphabets differ — parchment titles, capsule colours, bottle colours — and
the resolution differs, but the decision the player makes is identical every time:
*is this the moment to gamble a slot?* Three variations on one question is two more
than a run needs, and a fourth in that shape would have been indefensible.

So a card is the other question. **What it does is printed on it.** You pick it up,
you read it, and from then on the only decision left is *when*. That makes it the
one piece of loot a player can plan around, and it is worth having exactly because
the other three cannot be planned around at all.

---

## 2. What a card is

| | Card | The other three |
|---|---|---|
| **Identification** | None. There is no identified/unidentified state for a card and no way to reach one. | The whole point. |
| **Preference** | None. | Positive / Negative / Neutral, hidden until known. |
| **Uses** | One, always. | One, always. |
| **Per-run disguise** | None in the pack. | A dealt title, capsule or bottle. |
| **What it withholds** | Which card it is, and only while it is **on the floor**. | What it does, until it is spent. |

Three consequences fall straight out of that, and each is a place the code says so:

- `LootSystem.is_identified` **answers `true` for a card** — not "identified", a
  state it has no access to, but the honest answer to what every kind-blind
  surface is actually asking: *is anything about this hidden from the player?* It
  is what keeps a card out of `carried_unidentified`, so Scroll of Identify never
  offers to tell you something you can already read.
- `LootSystem.preference` **answers `""`**, and every surface that draws a
  preference chip or badge now checks before drawing one. An empty coloured chip
  next to the kind reads as a fact the screen forgot to fill in.
- `LootDiscoveries` **has no Cards row.** The fold is a record of what the run has
  learned; a run learns nothing about cards, and "Cards: 13 of 13" would be a
  record of the player having read the Collection.

---

## 3. Face down on the floor

The one thing a card does withhold is **which card it is, while it is lying on a
battlefield square.**

A card on the floor draws its **deck's icon** — `Isaac_Major_Arcana`,
`Isaac_Playing_Cards`, `Balatro_Playing_Cards`, `Isaac_MTG_Cards`,
`Slay_the_Spire_Ironclad_Rare` — and its hover says the deck and nothing more.
Thirteen cards wear five icons — two decks of five, and three decks of one — so a
face-down arcanum or playing card narrows the guess to five without answering it.
Pick it up and it turns over for good.

The three lonely decks (Balatro, the Ironclad rare, the MTG icon) **do** name
their card outright when it is face down. That is the roster's shape rather than a
hole in the mask: the two crowded decks are where the guessing happens, and
`test_card_system.gd` pins the split (`LONELY_DECKS`) so the day a fourth Balatro
card arrives, somebody decides on purpose.

That makes the floor's question *"is a Major Arcana worth a slot?"* — a real
question, because the five arcana in the roster do five unrelated things (Shields,
Health, two different teleports and a machine) — and it is answered by walking over
rather than by drinking something. It is the only
place in the build where a piece of loot is a chest again.

**Where the two sides are told apart:** `LootSystem.art_texture(entry, face_up)`
and `display_name` / `description` / `hover_card` beside it. `face_up` is **false
at exactly three call sites** and true everywhere else:

| Site | Why |
|---|---|
| `BattlefieldView._drop_node` | The token on the square. |
| `BattlefieldView.drop_hover` | Its hover card. |
| `FloorLoot._get_drag_data` → `LootGrid.preview_cell(entry, false)` | The thing in your hand mid-drag. Without this, drag-and-cancel is a free look at every card on the board. |

**`face_up` is a parameter, not a field on the entry.** "Face down" is not a fact
about the card, it is a fact about *where the card is* — and an entry carrying it
would have to be flipped by whoever moved it, which is every drag, every eviction,
every swap. One missed site is a card that stays face down in the pack forever.

**What is NOT masked:** the drop modal's offer, the haul screen, the pack. Those
are not the floor, and the decision each of them asks — *take it or leave it* —
needs the card readable. The mask is about walking over to a square and spending a
slot on a guess.

---

## 4. Where cards come from

**The per-game payout, and nothing else** — the same single tap the other three
have (potions-design decision #14).

`GameState.LOOT_KINDS` is now `["scroll", "pill", "potion", "card"]` and
`roll_loot_kind()` draws one uniformly: **an even 25 / 25 / 25 / 25.** Cards are
the least dangerous kind, which is the obvious argument for a smaller share — and
a smaller share is exactly what would make the run's one legible piece of loot the
one it rarely sees. The four are equals at the drop and unequal in what they ask
of you, which is the trade the kinds exist to offer.

**The Identify tenth did not move.** `IDENTIFY_DROP_CHANCE` is still 0.10, taken
off the top of the kind-blind drop and of an explicit scroll one. A quarter of
every drop is now a kind Identify has nothing to say about, so the scroll is worth
marginally less than it was in the abstract — and worth exactly the same to the run
that needs it, which is the run holding four unknown capsules. That run's odds
should not depend on how many cards it happened to draw.

**Rarity** rides the shared 75/20/5 ladder through `Data.roll_card`, so Luck
reaches a card drop for free. The roster is **3 Common / 4 Uncommon / 6 Rare** —
the opposite shape to the other three kinds, and deliberate: a card is one use and
a known quantity, so the interesting ones can afford to be the good ones. What
keeps that from being free is the ladder, which reaches the Rare rung on about one
card drop in twenty.

---

## 5. The roster

Thirteen rows, `cards` sheet: `Name | Rarity | Description | Effect | Image |
Icon Image`. `Image` is the face, `Icon Image` is the back — and the back is also
where the credit comes from, since the icon file names the game and the deck, so
`source_game` and `set_name` are read off it by the generator rather than authored
twice.

| Card | Rarity | Effect cell | Notes |
|---|---|---|---|
| Barricade | Rare | `bank_shields_next` | §5.1 |
| Ride the Bus | Uncommon | `teleport_type deckbuilder` | §5.2 |
| V - The Hierophant | Common | `gain_stat bonus_shields 2` | |
| VI - The Lovers | Common | `gain_hp 2` | |
| IX - The Hermit | Uncommon | `teleport_hub` | §5.2 |
| XIV - Temperance | Common | `spawn_object blood_donation_machine` | §5.3 |
| 0 - The Fool | Uncommon | `teleport_start` | §5.2 |
| 2 of Clubs | Rare | `double_stat bombs floor=2` | §5.4 |
| 2 of Diamonds | Rare | `double_stat gold floor=2` | §5.4 |
| 2 of Hearts | Rare | `double_stat hp` | §5.4 |
| Queen of Hearts | Rare | `gain_hp 1-20` | §5.5 |
| Ancient Recall | Rare | `gain_loot card 3` | §5.6 |
| ? Card | Uncommon | `copy_item` | §5.7 |

Two `Image` cells were corrected in the same pass, because both named a file that
is not on disk and a card whose art cannot be found draws nothing:
`VITheHierophant` → `VTheHierophant` (VI is The Lovers), and `?Card` →
`QuestionMarkCard`. The `?` is spelled out in the id as well
(`question_mark_card`), because the ordinary slug rule would have produced the id
`card`.

### 5.1 Barricade — the relic that became one use

Barricade and Ride the Bus were **relics** until this pass, and both were tagged
`card` in the items sheet all along. Both rows are now deleted from `items`, and
`data/items2.0/barricade.tres` and `ride_the_bus.tres` with them. A piece of
content that exists as two kinds at once is two things to balance and two things
to find.

Barricade **changes meaning** in the move, which is the interesting half. As a
relic it banked *every* resolved game's unspent Temporary Shields, forever, from
the moment it was picked up. As a card it arms `GameState.bank_shields_next`, and
the **next** game to resolve banks its leftovers — then the flag goes down.

`GameState.banks_shields()` is still the only reader, so `GameLoop2.beat_game` did
not have to learn the difference; what it gained is one line disarming the flag
**outside** the `shields > 0` branch. A next game that ended with its cover already
broken is a game the card was there for, and disarming only on a successful bank
would hold the promise open until a game happened to end with shields standing —
which is a different card.

The `bank_shields` **item** keyword left the vocabulary with the relic: Barricade
was its only author, and a sheet keyword nothing can write is a keyword that rots.

### 5.2 The three teleports

`teleport_type` (every Deckbuilder game on the map), `teleport_hub` (the nearest
hub, measured in roads) and `teleport_start` (the game the run opened on) are one
move with three pools. They land in `Overworld2.card_teleport` → `_teleport_into`,
which is the old `teleport_to_type` generalised: the same shared `_reachable`
filter, the same forced escape of whatever is in play, the same "off the bus is ON
the game" arrival.

They resolve as **requests**, like Scroll of Teleportation and for the same reason:
`play_card` hands one back and is finished, because the sentence saying where you
ended up can only come from whoever moved you.

**The Hermit's ties are drawn between rather than resolved by array order.** Two
hubs two steps away are two equally good answers, and taking the first would make
the card quietly deterministic.

### 5.3 Temperance — a machine under the board

Temperance is the only card that puts something on the page rather than a number in
the run, and the only one whose effect **persists after the card is spent**.

It calls `ObjectSystem.spawn(&"blood_donation_machine")` — a **named** object, where
an event's `spawn_object` rolls one off a tag. An arcade is a room full of whatever
cabinets it has; a tarot card is a promise about which one you get.

Everything after that is machinery that already existed
([`object-sheet-authoring.md`](object-sheet-authoring.md)). The spawn emits
`objects_changed`, `Overworld2._sync_object_panel` answers it, and `ObjectPanel2`
mounts **under the battlefield, where a hub's shop mounts** — not in a popup. That
is the whole difference from the Arcade Room event, which draws its cabinets inside
its own modal because the arcade *is* a room you are standing in. A card gives you
no room to be in, so the machine stands where a shop would: on the page, blocking
nothing.

Three properties fall out of using that path rather than a new one:

- **It works during a game.** The right column is built once, not per phase, so the
  panel survives `Phase.SELECT` → `Phase.PLAYING` and the machine is pressable
  while the board is live. `_sync_board_budget` shrinks the board's cells to pay
  for it, exactly as it does for a shop.
- **It goes when you travel on.** `_leave_node` → `ObjectSystem.clear()`, which is
  what an object's lifetime has always been.
- **An event does not eat it.** One repair was needed here: an event modal owns the
  screen while it is up, so `_sync_object_panel` takes the panel down when
  `objects_changed` fires during one — and the modal's own cleanup
  (`clear_spawned_since`) is such a fire. Nothing emitted afterwards, so a machine
  that was standing at the game *before* the event kept living in `ObjectSystem`
  with no panel to press it on. `_on_event_finished` now asks once more.

### 5.4 The three twos

`double_stat <what> [floor=<n>]`, three times over. Double what you are holding;
where you are holding none, `floor` is what you get instead — which is the sheet's
"if you have no Bombs then Gain +2", and the whole reason the card is not dead in
the hand of a player who spent everything.

**2 of Hearts authors no floor**, which is the roster's one asymmetry: a run at 0
Health is a run that is over, so the case the floor exists for cannot happen.

Health doubling is capped by Max Health, like every other heal, and the log says
what **landed** rather than what was asked for.

### 5.5 Queen of Hearts

`gain_hp 1-20` — the same op as The Lovers with a range instead of a value,
because "gain Health" is one thing and the range is how much. The roll goes through
`Stats.roll_range` at `Favour.HIGH` like every other range in the project, so **Luck
reaches it**; a uniform 1-20 would be the one number on the board Luck could not
touch. And the line distinguishes "+18 Health" from "+3 of the 18 rolled fits",
because a screen that reported the roll over a bar that moved by three would be
lying about the card the player just spent.

### 5.6 Ancient Recall

`gain_loot card 3` → `GameState.offer_loot("card", 3)`, which **offers** rather
than grants. The pack holds nine and the run may be carrying eight; `offer_loot`
is the call that asks instead of silently swallowing the surplus, and it falls back
to a direct grant where nothing is listening, which is what keeps it working
headless.

### 5.7 ? Card

Copies a **USABLE** relic's `item_used` effect and **spends none of its uses**.

Charged actives are deliberately not in the picker: a charged relic's cost *is* its
bar, and a card that fired one for free would read "skip the only cost that item
has". A USABLE's cost is a use, and copying one spends none — which is the whole of
what "copy" means here.

It resolves as a request (`copy_item`) with the candidates attached, and
`LootUseModal._pick_copy_item` draws it. Unlike the other pickers it is **one press
and done** rather than toggle-and-confirm: those choose up to N and need a commit
step for the count, and a confirm button under a single selection is a second click
that asks nothing. The rows carry each relic's own description, because the player
is choosing between *effects* here rather than between names.

---

## 6. Where the code lives

| Thing | File |
|---|---|
| Schema | `scripts/resources/CardData.gd` |
| Generator | `tools/generate_card2_tres.py` → `data/cards2.0/*.tres` |
| Sheet one-shots | `tools/_cards_effect_cells.py`, `tools/_items_drop_card_relics.py` |
| Brain | `scripts/autoload/CardSystem.gd` (autoload #24) |
| Rolling | `Data.roll_card`, `CardSystem.roll_card_loot`, `GameState.roll_loot_entry` |
| Kind-blind arms | `LootSystem` (every function in its describe and knowledge sections) |
| Floor mask | `BattlefieldView._drop_node` / `drop_hover`, `FloorLoot`, `LootGrid` |
| Requests | `LootUseModal._do_card_teleport` / `_pick_copy_item` |
| Teleports | `Overworld2.card_teleport` / `_teleport_into` / the three pools |
| Catalog | `Collection._populate_cards` (the Loot tab's fourth sub-tab) |
| Dev grants | `DevTools._list_cards` |
| Tests | `test/test_card_system.gd` |

**The ops are `CardSystem`'s own**, not `EffectSystem`'s `type`-keyed event
vocabulary — for the reason scrolls and pills do not reuse it either. A loot effect
returns `{ logs, requests }` so the piece can be echoed, replayed and reported on
one screen; an `EffectSystem` handler returns nothing at all.

Which means cards go through `LootSystem.use_loot` like everything else, so **Echo
Chamber replays them**, `loot_used_memory` remembers them, and a doubled Ancient
Recall offers six.

---

## 7. What is not done

- **No card sources beyond the payout.** No shop shelf slot, no boss bonus. Same
  call potions made (decision #14): a kind that arrives from four directions at
  once is a kind nobody can balance the first time.
- **`spawn_object` on a card takes an id, not a tag.** The tag form exists on
  `EffectSystem` for events; if a card ever wants "a random arcade cabinet" the
  DSL has room for it and `CardSystem._spawn_object` does not.
- **Nothing reads `TriggerBus.card_used` yet.** It is emitted once per play from
  `CardSystem.notify_used`, including for a card that fizzled, and is there for the
  relic that will eventually want it — the way Reptile Trinket wants `potion_used`.
