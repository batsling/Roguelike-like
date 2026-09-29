# Loot passives: trinkets, passive cards, and where things sit in the pack

Some loot is never spent. A **trinket** (the sixth loot kind) and a **passive
card** (a card whose line opens "Passive:") sit in a cell of the 3x3 pack and work
from there, the way a relic works from the shelf. The idea comes from backpack
roguelikes like Backpack Battles: the pack is a space you arrange, and some pieces
care about what is next to them.

- Content: the `trinkets` sheet (11 Isaac trinkets and five Backpack Battles
  foods, §10-§11) and five passive rows on the
  `cards` sheet (Balatro's Blueprint, Chaos the Clown, Rocket, To the Moon,
  Trading Card), plus Slay the Spire's Barricade and Echo Form (§8).
- Code: `scripts/runtime/LootPassives.gd` (which pieces are working and what each
  resolves to), `GameState.fire_run_item_triggers` (the runner),
  `scripts/resources/TrinketData.gd` and the passive fields on `CardData`.
- Tests: `test/test_loot_passives.gd`.

## 1. What a passive piece is

- **It is never spent.** The pack draws a "Passive" plate where the Use button
  would be (at the button's height, so rows stay aligned). `LootSystem.use_loot`,
  `use_entry` and `CardSystem.play_card` all refuse one as a backstop.
- **It still costs a slot.** Nine cells are shared with everything you might want
  to use. That is the price of a trinket.
- **It can be moved and binned** like any other piece. Moving it can change what
  it does (§2), and binning it takes back everything it was holding up (§4).
- **It has no Preference and nothing hidden.** A trinket's line is readable from
  the moment it is found. `LootSystem.is_identified` answers true.
- **Trinkets are a sixth of the kind-blind drop** (`GameState.LOOT_KINDS`), so
  they come from game payouts and from defeated bodies like every other kind.
  Like the other five kinds, they are **not on shop shelves**: shops sell relics
  only (§14 of the spec).

## 2. Position: neighbours and Blueprint

The pack is read in **slots**, the cells the player sees, and never in array
indices (pickup order). `LootPassives.neighbour_slot(slot, dir)` answers "the slot
to the right / left / above / below". **Rows do not wrap**: nothing is to the
right of the last cell in a row. That makes the right-hand column a real cost for
a piece that reads its right neighbour — until a bag is attached there (§6):
adjacency is asked of the pack's CELLS (`GameState.pack_cells`), so a Blueprint on
the 3x3's right edge copies the piece in the first cell of a bag beside it.

**Blueprint** (`copy_right`) does whatever the piece to its right does. **It
copies ANY loot, not only passives**: it takes on the text of the piece it points
at.

- If the neighbour is a Goat Hoof, Blueprint holds up a second point of Speed.
  If it is a Swallowed Penny, it pays a second coin. If it is a food, it counts
  enemies defeated toward its own payout, and is that food to its neighbours
  (§11).
- **If the neighbour is a piece you USE** (a scroll, pill, potion, card or wand),
  Blueprint gets a Use button and is used AS that piece: the Use screen shows,
  aims and resolves a copy of the neighbour (`LootPassives.usable_copy`), and
  then **the Blueprint is gone**, the way the piece it copied would be. The
  neighbour is untouched. A copied wand zaps once and the Blueprint goes with it:
  it has no charges of its own. Copying an unidentified piece is a gamble on that
  piece, and a use that lands teaches it, as spending the piece would.
- **It chains**, as in Balatro: a Blueprint beside a Blueprint copies whatever
  that one copies. The walk stops at the first piece with a passive of its own,
  at the edge, at a non-passive piece (nothing to copy), or on a cycle.
- **It fires as itself.** The toast reads "Blueprint (Swallowed Penny): +1 Gold"
  with Blueprint's art, because Blueprint is the piece in your pack that did it.
- **It copies a counter without growing it.** A Blueprint beside a Rocket pays
  what the Rocket pays, but only the Rocket's own firing grows the payout (§4).
- Its hover says what it is copying right now ("Copying: Goat Hoof"), and its
  plate reads "Copies >".

Only `right` is authored. The other three directions exist in `neighbour_slot` for
the next piece that wants one.

### Every piece turns

Any piece can be turned, as bags can: **R or a right-click while it is in your
hand** turns it a quarter clockwise, and dropping it back on its own slot turns it
in place. The turn is saved on the entry as `rot` (quarter turns clockwise, absent
when 0) and the art is drawn turned. For most pieces that is all it is. **For a
piece that reads a neighbour it is which neighbour**: a Blueprint turned once
copies the piece below it, then to its left, then above it
(`LootPassives.facing`, `LootPassives.turned`). Its plate points the way it faces
("Copies v") and its hover says where.

**A piece that acts on a neighbour wears an arrow** on the edge of its cell,
pointing at that neighbour and poking into the gutter between them; it turns with
the piece, in hand too (`LootGrid.DirArrow`). Every surface asks one function,
`LootPassives.direction(entry)`, so **the next directional piece gets its arrow by
answering there** — add its field to that function and nothing in the grid changes. A floor piece taken in turned is still the
same piece (`DropQueue._same_piece` ignores `rot`).

## 3. Hooks, gates and verbs

Passives are authored in the **relic grammar** (spec §8.1) and compiled by
`generate_item_tres.parse_loot_passive`, which trinkets and passive cards share.
Each piece is handed to the relic runner as a relic-shaped `ItemData`
(`LootPassives.proxy`), so hooks, gates, chance rolls and Luck mean exactly what
they mean on a relic.

The generator **refuses** any relic field beyond triggers, `passive:`,
`passive_status:` and `copy_right`. Most relic flags are read straight off the
relic shelf, so a trinket authoring one would be a promise nothing keeps.

### Five new hooks

| Hook | Fires when | Emitted from | Used by |
|---|---|---|---|
| `game_won` | A game was actually **beaten**: the report said so and it was not an escape. Narrower than `game_beaten`, which is every game seen through, win or lose. | `Overworld2`, beside `game_beaten` | Isaac's Fork, Rocket, To the Moon |
| `shop_entered` | A Shop node's shelf opens where the player stands, once per arrival (not when a save reload re-mounts it). | `Overworld2._open_pending_shop` | Chaos the Clown |
| `boss_spawned` | A boss walks onto the board, whatever put it there. Fresh bodies only, so a save load does not re-fire it. | `GameLoop2._add_to_grid` | Hairpin |
| `loot_used` | A piece of loot was spent (a wand zap included, §9), once per use, never for its echoes. | `LootSystem._spend` | Endless Nameless |
| `card_binned` | A card of the loot kind went into the bin, from the pack or off the floor. | `GameState.discard_loot_at` / `note_loot_binned` | Trading Card |

`enemy_killed` now also carries `boss: bool`.

### Two new gates

- `if_boss` passes only when the hook's context says the body was a boss
  (Rocket: `enemy_killed if_boss:`).
- `once_per_game` fires at most once per game played (`GameState.games_played`).
  The claim is kept on the piece doing the firing, so a Blueprint copying Trading
  Card has a once-a-game of its own.

### New verbs

| Verb | What it does |
|---|---|
| `charge_random N` / `charge_random full` | Tops up one random relic or wand that has room (Charged Penny, Hairpin). |
| `drop_copy` | A duplicate of the piece the hook was about lands on a free square of the battlefield (Endless Nameless). A full board pays nothing. |
| `bump N` | Grows the counter on the firing piece (Rocket). A copy never bumps. |
| `gain_card N` | A named card grant (Deck of Cards). |
| `gain_gold N per=P of=<stat>` | N for every P of the stat, rounded down, read before this payout lands (To the Moon: `per=3 of=gold`). |
| `gain_gold N plus=counter` | N plus the counter on the piece whose passive this is (Rocket). |

### The coin-chain rule

**Gold a trigger paid never rolls the pack's pennies.** `gold_gained` reached from
*inside* another trigger is answered by relics (Dragon Fruit keeps its designed
chain off Lucky Fysh) and by no piece of loot. So Swallowed Penny beside
Counterfeit Penny is one coin per hit, never two, and two Counterfeits cannot feed
each other. Only gold the run itself paid reaches the pennies: a report, a body,
an event, a shop, a spent pill, an active relic.

### Rulings made while authoring

- "Complete a game" (Isaac's Fork, Rocket, To the Moon) means **won**: `game_won`.
- Swallowed Penny pays on **any Health lost** (the Piggy Bank hook), not only an
  enemy hit. Its sheet line was reworded to say so.
- "Trashing a card" means dragging a loot card into the bin: from the pack or off
  the floor, not declining an offer.
- "At the start of combat" (Wooden Cross) is `game_selected`, the hook Anchor uses
  for the same words.
- Rocket **scales permanently**, as in Balatro: +1 Gold per won game, and every
  boss defeated while it is held raises that by 2.

## 4. What rides on the piece, and what is held up by it

**Held up by the slot.** Stat grants (Lucky Toe's Luck) join
`GameState._recompute_item_bonuses` as extra sources. Status grants (Goat Hoof's
Speed) are the difference between what the arrangement wants now and what it was
holding (`_sync_pack_statuses`). Both are re-derived on every `inventory_changed`,
the one signal every pack change already emits. Like a relic, the pack only ever
gives back its own share: Speed gained any other way is untouched. On a save load
the restored statuses already contain the pack's share, so
`GameState.adopt_pack_statuses` adopts it rather than granting it twice.

**Riding the pack entry** (saved with the pack, as-is):

- `counter`: Rocket's growth. Drawn on the piece's art (bottom-left, `+2`) and
  quoted in its hover. It is read off the **source** piece, so a Blueprint pays
  what its Rocket pays.
- `once_game`: `{hook: games_played}` for `once_per_game` triggers, kept on the
  **firing** piece.

## 5. The toast

**Every trigger that did something says so, with its picture**, relics included.
`GameState._begin/_end_trigger_report` snapshot the run resources around a
trigger's effects. The difference becomes the line ("Bloody Penny: +1 Health"),
plus anything an effect that moves no resource wrote into `ctx.did` ("Hairpin:
D6 charged"). The toast is posted through `Notifications.notify(text, color,
icon, key)`.

- **A trigger that did nothing leaves no toast.** A missed 25% or a payout of 0 is
  silent, so a penny does not announce the three golds it ignored.
- **A nested trigger reports only its own effect.** Swallowed Penny's coin fires
  Dragon Fruit. The fruit's toast says "+1 Max Health", and the penny's says only
  "+1 Gold".
- **One source, one toast.** `NotificationToasts` keys live toasts by source. A
  repeat of the same line stacks ("Swallowed Penny: +1 Gold ×2") instead of piling
  up, and a different line from the same source replaces the old one.
- The art is drawn at 32px to the left of the line. `Notifications.history` keeps
  the icon with each entry.

## 6. Bags: the shape of the pack

**Bags are the seventh loot kind**, lifted from Backpack Battles, where the bags
you own ARE your inventory. A bag is not a piece that sits in the pack — it is
more pack.

- Content: the `bags` sheet (Leather Bag 2x2, Potion Belt 4x1 — four tall — Protective Purse
  1x1), generated into `data/bags2.0/` by `tools/generate_bag2_tres.py` as
  `BagData`. `Size` is "HxW", **rows first**, unrotated, the way the enemies sheet
  writes a footprint and the way the art is painted; any rectangle is allowed.
  The Effect column is the relic grammar, and **may be blank**: Leather Bag only
  adds room, and that is a whole design.
- Code: the pack's shape is `GameState.pack_bags` and the functions beside it
  (`place_bag`, `move_bag`, `remove_bag`, `can_place_bag`, `pack_cells`);
  `LootGrid` draws and drags it.
- Tests: `test/test_bags.gd`.

### The rules

- **The 3x3 is fixed**, at cells (0,0)-(2,2). It cannot be moved or binned.
- **A bag attaches edge to edge.** Every cell of the pack has to be reachable from
  the 3x3 through cells that share a side, so a new bag must touch the 3x3 or a bag
  that already does, and **a move or a removal that would strand another bag is
  refused**. There is **no size limit**.
- **What is in a bag moves with it**, rotation included.
- **A bag is binned only when empty**, and only if nothing hangs off it.
- **A bag takes no slot**, so a full pack never refuses one. A kind-blind grant
  into a full pack that rolls a bag still pays it.

### Slots, and why the contents ride along for free

A slot is still an integer. Slots 0-8 are the 3x3 in reading order, exactly as
before. Each bag's cells follow **in the order the bags were attached**, each bag's
in its own **unrotated** reading order. So a slot names *which bag's which cell*,
not a position: moving or turning a bag changes where its cells are drawn
(`pack_cell_of`) and never which slot a piece is in. Removing a bag is the one
change that renumbers, and `remove_bag` shifts the pieces in later bags down by
its size so each stays in its cell.

A row of `pack_bags` is `{id, rarity, x, y, rot}`: the cell the turned bag's
top-left sits on, and quarter turns clockwise. Anything its passive earns (a
once-a-game claim, an `every=N` count) rides the same row and is saved with it.

### Getting one onto the pack

A bag is **dragged onto the pack's edge** from wherever it arrives: the floor (the
drag-time pack appears as for any piece), or a report's table in the drop modal.
While a bag is in the air, every grid that would take it grows a one-cell ring of
empty space around the pack to drop onto, and shows a ghost of where it would land
(green) or what is in the way (red). **R or a right-click turns the bag in your
hand** a quarter turn; the turn is written into the drag payload, which is the same
Dictionary every drop target is handed.

A drop takes the placement that covers the cell under the pointer and whose middle
is nearest it. That is what makes one ring enough for any bag: point just past the
edge and a Potion Belt runs outward from there rather than being centred on the
pointer and landing half on the 3x3.

A grant with nobody to drag it (a headless run, "Take all", DevTools) attaches the
bag with `auto_place_bag`: the placement that grows the pack's bounding box least,
preferring right and down.

### Moving one

In the loot window, a bag is picked up by **the tab in its top-left cell**, or by
any empty cell of it. The grid moves it itself (`GameState.move_bag`): a move
changes nothing but the drawing, so there is nothing for a host to decide. Dropped
on the bin, an empty bag comes off after the usual confirmation.

### Drawing a bigger pack

`LootGrid` places each slot on its own cell and **shrinks every cell alike** when
the shape outgrows its box (`fit_scale`, never below `MIN_SCALE`). The box is four
columns by three and a half rows of full-size cells, so the 3x3 alone is always
drawn at full size and every 720p fit test still measures what it always did.

### What they do

Bag passives run through `LootPassives.active()` like any piece, as rows with
`slot: -1` and `bag: <index>`. Two gates and a counter were added for them, and are
available to any passive:

| Grammar | Means |
|---|---|
| `if_loot=<kind>` | The hook's piece was of this kind (read off `ctx.entry.type`). |
| `if_in_bag` | The hook's piece was spent from a cell of **this** bag. `loot_used` now carries `slot`, where the piece was when it was spent (-1 for one used where it stands). Refuses on anything that is not a bag. |
| `every=N` | Only every Nth firing that passed its other gates goes through. Counted on the firing piece. |

And two verbs: `gain_random_buff N` and `remove_random_debuff N`. **Randomly
gaining or losing a buff or debuff is always ONE STACK**: `gain_random_buff 2` is
two draws over the Buff-kind statuses, one stack each, and `remove_random_debuff 2`
is two draws over the Debuffs you carry, each taking one stack off (a borrowed,
timed stack before a permanent one). Neither ever moves a whole pile at once.

- **Protective Purse**: `game_selected: gain_stat shields 1`, the same words and
  hook as Wooden Cross.
- **Potion Belt**: `loot_used if_loot=potion if_in_bag once_per_game:
  gain_random_buff 1; loot_used if_loot=potion if_in_bag every=4:
  remove_random_debuff 1`. "The first time" was ruled to mean **once per game**.

Trinkets can be bigger than one cell now (§10).

## 7. The two non-passive additions from the same sheet pass

- **IV - The Emperor** (card, `spawn_boss`) summons a random boss of the game in
  play's type at the run's current tier, through `GameLoop2.summon_boss`, the same
  path the every-third-spawn capstone takes. It is not a spawn event, so it does
  not move the tier ladder.
- **Deck of Cards** (relic, Charged 2, `item_used: gain_card 1`) deals a card.

## 8. Barricade and Echo Form, held

Both were one-use cards that armed a run flag for the next game. Both are passive
cards now. They are **rules the run consults at one moment** rather than answers
to a hook, so each is a field on the card read by total across every working piece
(`LootPassives.total`). A Blueprint beside one counts as a second.

- **Barricade** (`bank_shields`): as every game resolves, unspent Temporary
  Shields become Shields for as long as a Barricade is at work in the pack.
  `GameState.banks_shields()` asks the pack; `GameLoop2.beat_game` did not change
  its question. The bank leaves a toast: "Barricade: kept 3 Temporary Shields as
  Shields".
- **Echo Form** (`echo_first_loot 1`): the **first** piece of loot used in each
  game plays one additional copy per Echo Form. `GameState.loot_uses_this_game`
  counts this game's copyable uses. `LootSystem._spend` reads the owed copies,
  counts the use, then resolves the copies, and `GameLoop2` zeroes the count as
  the game resolves. The count is saved, so a mid-game reload does not hand the
  copy out twice. A wand zap counts like any other use and is copied (§9). The
  copy leaves a toast: "Echo Form: Luck Up again".

The old run flags (`bank_shields_next`, `echo_loot_next_game`) and the card ops
that set them are removed. A save that still carries them loads fine; the keys
are ignored.

## 9. Every copy ability copies a wand zap

A wand used to stand outside Echo Chamber (and so outside Echo Form and Endless
Nameless) on the argument that a copied zap was extra effects for one charge.
That is what a copy is: a copied pill is extra effects for one pill. So a zap is
now copied like any other use.

- **The charge is spent once.** `LootSystem.use_loot` takes it before anything
  resolves; a copy only re-runs `WandSystem.zap_wand`, which spends nothing.
- **Echo Form** copies the zap in hand, at the same square it was aimed at.
- **Echo Chamber** remembers zaps and replays them. A remembered piece keeps
  where it was aimed (`echo_target`, stored as `[x, y]` so the saved memory stays
  JSON-safe). A replay uses the current use's aim when it has one, and the
  remembered square otherwise, so last game's Wand of Fire replayed off the back
  of a pill still has somewhere to land.
- **Endless Nameless** can duplicate a wand. The duplicate carries the charges the
  wand has after the zap, but never fewer than one, since the zap that set it off
  may have spent the last.
- The Use screen shows "Echo Chamber will also use…" over a wand as well.

## 10. Pieces bigger than one cell

The five foods are shaped: **Broccoli and Garlic are 2x1 (two tall), Carrot and
Cheese 1x2 (two wide), Cupcake 1x1**. `Size` on the `trinkets` sheet is "HxW",
**rows first**, unturned — as on the `bags` and `enemies` sheets, and as the art
is painted, so a piece's picture always runs the same way as the piece. The
generator takes any rectangle and writes `size` as `Vector2i(columns, rows)`. `GameState.piece_size` reads it; every other
kind is one cell.

- **One piece, several cells.** `loot_layout()` maps every cell a piece covers to
  its index, so "is this slot free" is still `layout[slot] == -1`. Its `pack_slot`
  is its **anchor**, the lowest slot it covers; `loot_slots_of(index)` lists them
  all. It is read ONCE by everything that walks the pack: `LootPassives.active()`
  counts a piece at its anchor only.
- **Room is a shape, not a count.** `loot_space()` is free cells. A big piece fits
  only where its rectangle is free: `loot_fits(entry)` and `find_piece_spot` (its
  own turn first, then a quarter turn, so a 2x1 goes in standing rather than not
  at all). A grant with no room for the shape is not paid, as a piece into a full
  pack is not.
- **A big piece lives inside one owner**: the 3x3 or one bag. Slots are numbered by
  who owns the cell (§6), so a piece across two owners would be torn apart when its
  bag moved.
- **Its footprint is kept in its owner's frame**: the anchor is the top-left of
  the rectangle in the bag's unturned reading order (`piece_slots`). A placement
  from the screen is asked by the cell the piece's top-left is dropped on
  (`piece_slots_from`).
- **Turning a bag turns what is in it.** `move_bag` adds the bag's turn to every
  piece in it, so a piece's `rot` is always the way it faces on screen. This also
  applies to 1x1 pieces: a Blueprint in a bag given a quarter turn now copies
  the piece below it.
- **Moving.** A piece lands with its top-left on the cell under the pointer. It
  swaps with **the one piece in its way**, which goes to the slot the mover came
  from if it fits there. Two pieces in the way, or a displaced piece with nowhere
  to go, is refused (`can_move_loot` asks first, and the grid only lights up
  where a drop would work). A piece off the floor trades the same way
  (`can_trade_into`, `swap_loot_entry_at`).
- **Turning** a big piece (R in hand, or dropping it back on itself) turns it
  about its top-left cell, and only onto free cells.
- **Drawing.** `LootGrid` draws a big piece once, from its anchor's cell, stretched
  over its footprint (`_place`). Its other cells are hidden, filled children, so
  child `i` is still slot `i`. The picture fills the footprint and gets a quarter
  turn of its own if it were ever painted the other way from the piece (`SpanArt`,
  `art_turn`) — a safety net, since the sheets' sizes match the art. The piece in
  your hand is held by its top-left cell and changes shape as it turns.
- A piece that cannot be seated anywhere (an old save, a debug grant into a crowded
  pack) is squeezed into one free cell rather than not drawn at all.

## 11. Food, and triggers that count enemies defeated

Backpack Battles items fire "every X seconds". Here that clock is **enemies
defeated**: `enemy_killed every=N: …`. The count is the `every=N` count Potion Belt
already used (§6). It rides on the firing piece, is saved with it, and **carries
from game to game**.

| Food | Every | Pays |
|---|---|---|
| Broccoli (2x1) | 6 | +2 Luck |
| Carrot (1x2) | 3 | one stack of a random debuff comes off |
| Cheese (1x2) | 4 | +5 empty Max Health, one stack of a random buff |
| Cupcake (1x1) | 6 | +5 Health, a stack of the buff you carry most of (`gain_top_buff`) |
| Garlic (2x1) | 4 | +3 Temporary Shields |

**Food comes round sooner beside other food.** A piece tagged `food` has the N of
each of its `enemy_killed every=N` triggers lowered by one for **every different
food touching it**, never below 1 (`LootPassives.every_for`):

- "Touching" is any cell of its footprint sharing a side with any cell of the
  other's (`adjacent_pieces`), so a 2x1 can have six neighbours.
- "Different" is by id, and **its own kind does not count**. A Garlic beside a
  Garlic is not a second food; a Garlic beside a Carrot and a Cheese counts to 2.
- A Blueprint copying a food is that food, both for its own count and to its
  neighbours.
- The count is **progress**, reset when it pays, not a remainder. So moving a
  Carrot 3 along beside a Cheese (4 becomes 3) pays on the next enemy, rather than
  wrapping round to zero.

**The number is on the piece.** A piece with an enemy-defeat trigger wears
`have/need` in the top-right corner of its art (`LootGrid._add_progress`): gold
normally, green when food beside it has lowered the target. Its hover says the
same in words and names the food helping it.

### Random buffs and debuffs are one stack

Randomly gaining or losing a buff or debuff is always **one stack** (§6):
`gain_random_buff N` is N draws of one stack each, and `remove_random_debuff N` is
N draws over the debuffs you carry, each taking one stack off.
