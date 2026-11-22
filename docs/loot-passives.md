# Loot passives: trinkets, passive cards, and where things sit in the pack

Some loot is never spent. A **trinket** (the sixth loot kind) and a **passive
card** (a card whose sheet `Type` is `Passive`) sit in a cell of the 3x3 pack and work
from there, the way a relic works from the shelf. The idea comes from backpack
roguelikes like Backpack Battles: the pack is a space you arrange, and some pieces
care about what is next to them.

- Content: the `trinkets` sheet (11 Isaac trinkets, five Backpack Battles
  foods and the Whetstone, §10-§12) and five passive rows on the
  `cards` sheet (Balatro's Blueprint, Chaos the Clown, Credit Card, Rocket, To
  the Moon, Trading Card), plus Slay the Spire's Barricade and Echo Form (§8).
- Code: `scripts/runtime/LootPassives.gd` (which pieces are working and what each
  resolves to), `GameState.fire_run_item_triggers` (the runner),
  `scripts/resources/TrinketData.gd` and the passive fields on `CardData`.
- Tests: `test/test_loot_passives.gd`, and `test/test_weapons.gd` for §11's charges,
  §12's weapons, §13's evolutions and the hover glow (§2).
- **`Type` is a column now** on `cards` and `trinkets` (`Usable` / `Passive` /
  `Charged`), shown as a chip on the piece's hover — so a Description says what
  the piece does and no longer opens with "Passive:" or "Triggered:". The card
  generator reads `Type`, not the prose, to decide whether a card is played or
  held. `scrolls`, `potions` and `wands` grew a `Tags` column the same way.

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

**A piece that acts on a neighbour wears an arrow** on the edge of its cell for
each direction it acts in, pointing at that neighbour and poking into the gutter
between them; they turn with the piece, in hand too, big pieces included
(`LootGrid.DirArrow`). Every surface asks one function,
`LootPassives.directions(entry)`, which reads a copier's `copy_neighbour` and the
`dirs` of a `weapon_stun` or `weapon_retrigger` aura (Whetstone up and down,
Duplicator and the Hero swords all four). It used to read only `copy_neighbour`,
so Blueprint was the one piece with an arrow. **The next directional piece gets its
arrows by answering there**: add its field to that function and nothing in the
grid changes.

**A piece is picked up on the press** (`LootSlot._gui_input`, `FloorLoot._gui_input`
call `force_drag`), not once the mouse has moved past Godot's drag threshold, so
holding the button is holding the piece and R or a right-click turns it straight
away. A floor piece taken in turned is still the
same piece (`DropQueue._same_piece` ignores `rot`).

## 3. Hooks, gates and verbs

Passives are authored in the **relic grammar** (spec §8.1) and compiled by
`item_dsl.parse_loot_passive`, which trinkets and passive cards share.
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
| `shop_entered` | The player walks into a shop where they stand, the first time the door is opened on an arrival (not when a save reload re-mounts it). | `Overworld2.open_shop` | Chaos the Clown |
| `boss_spawned` | A boss walks onto the board, whatever put it there. Fresh bodies only, so a save load does not re-fire it. | `GameLoop2._add_to_grid` | Hairpin |
| `loot_used` | A piece of loot was spent (a wand zap included, §9), once per use, never for its echoes. | `LootSystem._spend` | Endless Nameless |
| `card_binned` | A card of the loot kind went into the bin, from the pack or off the floor. | `GameState.discard_loot_at` / `note_loot_binned` | Trading Card |

`enemy_killed` now also carries `boss: bool`.

Two more came with the 14 Oct 2026 upload, both run-scope like the five above:

| Hook | Fires when | Emitted from | Used by |
|---|---|---|---|
| `weapon_charged` | A charge **landed** on a weapon in the pack, from anything that charges one (its goal, a penny, a Hairpin). Once per charging, whatever its size; a full weapon that took nothing fires nothing. | `GameState.charge_loot_entry` | Dumb Bell (+1 Strength for the next game), Well-Done Steak (+1 Health) |
| `game_perfected` | A game **won with no lost run logged** on this visit: the game ranks' perfected visit (spec §20.1). Narrower than `game_won`, and fired beside it. | `Overworld2`, beside `game_won` | Performance Based Health Insurance |

and one more gate, **`if_shields`**: passes when a Shield was still standing as
the game ended, Temporary or not (Knight Cap: `game_beaten if_shields:`). The
report reads `shields_left` in `GameLoop2.beat_game` before the Temporary ones
expire, and passes it on `game_beaten`'s context.

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
| `gain_gold N per=P of=<stat>` | N for every P of the stat, rounded down, read before this payout lands (To the Moon: `per=5 of=gold`, Balatro's rate since 17 Nov 2026). A purse in debt (Credit Card) counts as 0. |
| `gain_gold N plus=counter` | N plus the counter on the piece whose passive this is (Rocket). |
| `break_into <item_id>` / `break_into random_item` | The firing piece **leaves the pack** and a relic takes its place: a named one, or a random one off the reward pool (Bag Lunch -> Lunch, Wish Bone). Its own verb because a `N% chance` wraps exactly one effect. A Blueprint copying one is the piece that fired, so the Blueprint is what breaks. |

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
  the floor, not declining an offer. **Destroying loot is trashing it** (the owner,
  18 Oct 2026): every effect that destroys a piece goes through
  `GameState.destroy_loot_at`, so a destroyed card pays Trading Card, whose line
  now says "when destroying a card", and the piece joins the run's destroyed pile
  that Exhume draws from (docs/cards-design.md §5.9).
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

**An attached bag says what it does on hover** (`LootGrid.bag_hover`): its tab and
each of its empty cells carry the bag's card — name, size, the room it adds and its
Effect — with the cell's own line ("Empty — room for…", "Drag this empty cell…")
as the note. A filled cell still shows the piece in it.

**What is in your hand is the size of the pack under it** (`LootGrid.scale_under`).
A pack with bags is shrunk to fit its box, so the piece or bag being dragged is
rescaled every frame to the drawn size of whichever grid is under the pointer, and
keeps the size it was picked up at when over none. The haul screen gives its pack
a wider box (`LootGrid.fit_width`, `PostCombatScreen.LEFT_MIN`) so a bagged pack
shrinks only as far as the screen really needs.

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

## 8. Barricade, Echo Form and Credit Card, held

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

- **Credit Card** (`gold_debt 20`, Balatro, Uncommon; the owner, 17 Nov 2026: "allow
  the player to go into -20 gold in the shop"): `GameState.gold_debt_limit()` sums
  it. **Only a shop purchase or a gold reroll goes below 0**:
  `ShopSystem.can_afford` checks `gold - price >= -limit`, and the shop pays with
  `spend_gold(price, true)`. Everything else stops at 0, or at the debt already
  owed (`GameState.set_gold`): a loss cannot make the debt deeper, `lose_gold all`
  cannot wipe it, and a gain pays it down. The debt stays after the card leaves,
  as in Balatro. The shop's purse shows "(credit to -20)" and turns red in debt.
  The generator refuses `gold_debt` on a trinket or a weapon.

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
- **A big piece can sit across owners** (23 Oct): half in the 3x3 and half in a
  bag, or across two bags. It is then **in every bag under it**, once per bag:
  two Fanny Packs under one Longsword are two chances at the extra charge, and
  Potion Belt's `if_in_bag` and Holdall's count both see it
  (`GameState.bags_of_slot`). Slots are numbered by who owns the cell (§6), so
  such a piece keeps the slots it covers as a list (`pack_cells`, written by
  `_seat`), and **a bag under it cannot move or turn** (`bag_is_straddled`) —
  that would pull the piece in two. Move the piece off it first. Removing an
  earlier bag shifts the list down the way it shifts every `pack_slot`.
- **Inside one owner its footprint is kept in that owner's frame**: the anchor is the top-left of
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

## 11. Food, and triggers that count CHARGES

Backpack Battles items fire "every X seconds". Here that clock is **charges**: a
defeated enemy is +1 Charge, and the food pays at N — `enemy_killed charges=N: …`.
The count is the `every=N` count Potion Belt already used (§6), flagged `charges`.
It rides on the firing piece, is saved with it, and **carries from game to game**.

**A food is Chargeable Loot.** Because the count IS its charges, anything that
charges loot reaches it too — Charged Penny, Hairpin, 48 Hour Energy, a Fanny
Pack's extra (§12) — through the one door `GameState.charge_loot_entry`, which
counts one charge at a time through the same `_count_every` a defeated enemy
does and pays through the same `_run_trigger`. Fully charging a food pays it once.
Those sources' Descriptions say "Chargeable Items and Loot".

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
  Carrot 3 along beside a Cheese (4 becomes 3) pays on its **next charge**, rather
  than on the spot or wrapping round to zero. The piece is **READY**: its corner
  chip reads `+1` in the accent colour, its hover says "READY — it pays on its next
  charge", and the move that made it ready raises a toast ("…needs one more charge
  to pay"). Only a move can make a food ready — a charge that reaches the number
  pays and starts again — so `GameState._note_ready_foods` toasts exactly the
  newly-ready ones on each pack change (and a save loaded with one ready is not
  news).
- **The rule is printed on every food**, carried or not (`LootSystem.FOOD_RULE`),
  because it is what decides where one goes.

**The number is on the piece.** A piece with an enemy-defeat trigger wears
`have/need` in the top-right corner of its art (`LootGrid._add_progress`): gold
normally, green when food beside it has lowered the target, `+1` when READY. Its
hover says the same in words ("2 / 4 charges") and names the food helping it.

### Random buffs and debuffs are one stack

Randomly gaining or losing a buff or debuff is always **one stack** (§6):
`gain_random_buff N` is N draws of one stack each, and `remove_random_debuff N` is
N draws over the debuffs you carry, each taking one stack off.

## 12. Weapons — the eighth kind

A **weapon** sits in the pack like a trinket (it has a footprint and neighbours),
is **aimed at the board like a thrown potion**, and **charges off its own goal**.
Eleven, all from the `weapons` sheet (`tools/generate_weapon_tres.py` →
`data/weapons2.0/`, `WeaponData`; runtime in `scripts/runtime/WeaponSystem.gd`).

**Charging.** A weapon is found **empty**. Its goal (the sheet's `Goal` column,
written by `apply_goals_sheet.py` from `goals` — Owner Sheet `weapon`) sits on the
report checklist under **Any time:** while it is carried, one row per weapon
(keyed by the entry's `uid`, so two Hero Swords are two rows). Ticking it is +1
Charge, **at most once per game**: the row is keyed per game and locks once
confirmed, and the entry's `goal_game` refuses a second charge in the same game by
any other door. It resolves the moment it is confirmed, so **a game you then lose
still charges the weapon**. It is Chargeable Loot, so everything else that charges
loot charges it too. At `Charge` (3) it is **READY**.

**Swinging.** Until it is full, the pack tile's button is the same segmented
gold battery an item wears in the relic strip (`PackStrip.battery`), one segment
per charge; when the last one lands it becomes **Swing**. The
board lights the squares the weapon's `Aim` allows; hovering one previews the
squares its `Area` would hit from there, in the weapon's orange; clicking one
swings. Every enemy covered takes the Stun **once**, however many of its squares
are covered. The swing spends every charge and the weapon stays in its slot.

| Aim | where you may click |
|---|---|
| `any` | every square |
| `front` / `back` | column 1 (next to you) / the spawn column |
| `column N` | that column |
| `enemy` | a square an enemy stands on |
| `none` | nothing — laid from the front column's middle row |
| `random` | nothing — each strike lands on a random enemy standing on the board (its square nearest you), and whiffs on an empty board |
| `ray` (`bounce N`) | every square — the click is a **direction**: see §12.1 |

| Area | what it hits, from the clicked square |
|---|---|
| `cell` `row` `col` `cross` `3x3` `5x5` `board` | the words potions already had |
| `plus` / `diagonals` | the square and its 4 side / 4 diagonal neighbours |
| `RxC` | a rectangle, **rows first**: rows **centred** on the click (an even height puts the extra row below), columns running **away** from you starting at it. `3x3`/`5x5` stay the centred-square words. |
| drawing | rows split by `/`; `#` hit, `.` skipped, `O` the click (hit); left is toward you — `.#./#O#/.#.` is a plus |

Shapes are clipped, never wrapped (`GameLoop2.area_cells`, so potions can use the
new words too). The generator refuses an Area or Aim it cannot read.

**The Effect cell** is `stun N`, optionally followed by `push <dir> N`
(`right` is away from you, `left` toward you, `up`, `down`) and, on a `ray`,
`bounce N` (which may equally be written in Aim: `ray, bounce 1`). **Hero Longsword** is
`stun 2, push right 1`: after the Stun lands, every body it covered is shoved one
square back — free (`GameLoop2.shove`, not the Push verb), farthest-first so a line
moves together, as far as each fits. The **Type** column is `Melee` or `Ranged`.

**What the board shows afterwards.** Every swing writes `GameLoop2.last_strike`
— each strike's squares and the bodies it covered — and the board washes those
squares in the weapon's orange (numbered when there was more than one strike),
pulsing once, until the board next moves (a lost run's turn, a game chosen or
reported). A Brimstone blast writes it too. This is what tells the player where a
`random` strike went.

### 12.1 The ray (Earthquake, and the wands)

`ray` is **Ball x Pit's ball**, asked for with **Earthquake** (Ball x Pit, The
Makeshift Sisyphus's starting weapon: `ray`, `3x3`, `stun 1, bounce 1`), and it is
the wands' Aim too (§12.2). The geometry is `scripts/runtime/RayAim.gd`, one walk
over the board shared by everything that fires one.

- **It leaves from you**: the middle of the hero's column, beside the board's left
  edge — board point (0.5, rows/2), where column *c* spans x ∈ [c, c+1).
- **The click only says which way.** The line runs from you through the centre of
  the clicked square and **carries on past it** until it meets something.
- **An enemy** is struck. **A wall** — the top, the bottom or the back edge — is
  met. Either way, with a bounce left the ray **mirrors like a ball** off the face
  it crossed (a vertical edge flips it left-right, a horizontal one up-down; at an
  exact corner the vertical edge is met first) and travels on, one bounce spent.
  With none left **it stops**: on the enemy, or on the last square before the wall.
- **Your side is not a wall.** A ray mirrored back out past the left edge has gone
  home and ends there, its remaining bounces unspent.
- **Every enemy it struck takes the effect**, each **once** however often the line
  comes back to it — so a `bounce 1` ray that hits one enemy, mirrors off it and
  hits a second does the effect to both. A ray that struck nobody lands on the
  square it stopped on (so a Wand of Fire still sets that square alight), and one
  that went home lands nowhere.
- **A weapon's Area is laid at each enemy struck**, not at the square clicked:
  Earthquake's 3x3 shakes the ground round every body its rock hits, and a body
  under two of those squares is still stunned once (`WeaponSystem.ray_hit_cells`).
- **The board previews the whole path while you aim**, bounces included: hovering
  a square draws the line (a ring at each bounce, a dot where it stops) over the
  squares it would hit, in white — the same trace the click then fires, so the
  preview cannot disagree with the swing. Afterwards `last_strike` carries the line
  (`strike.ray`) and the board draws it in the weapon's orange over what it hit.
- A ray that keeps finding walls always ends: each wall or enemy spends a bounce,
  so a ray crosses the board at most `bounce + 1` times.

### 12.2 Wands aim in the same words

The `wands` sheet's `Type` column is now **`Aim`**, read in the weapons'
vocabulary (`generate_wand2_tres.parse_aim` calls `generate_weapon_tres.parse_aim`):
`Ray, Bounce 1` is the ray above (nine of the twelve wands), `Non-Directional` is
`none`, and `Random` is the weapons' `random` — the zap lands on a random enemy.
`any`, `front`, `back`, `column N` and `enemy` fence the click the way a weapon's
do (`WandSystem.aim_cells`), and the effect lands on the square clicked.

`WandData.targeting` became `aim`, `aim_column` and `bounce`. A ray wand runs its
**per-square clauses once per impact** — a status on an enemy, damage, a tile, the
six unit verbs — and everything else **once per zap** (a pick of any item, a body
called up, a status on you, an `area=board` clause): `WandSystem._per_impact`.
Each impact is followed to where its body stands now (`RayAim.live_cell`), so a
teleport on the first does not misplace the second.

**An unknown wand still asks for any square** and **draws no line** — the fence or
the path would say what kind of stick it is (`WandSystem.previews_ray`). Once known,
a ray wand previews its path like a weapon. Wand of Nothing's old disguise — a
`random` that rolled "aimed or not" afresh on every zap — is gone with the column:
`random` now means what it means on a weapon, and the wand still does nothing
wherever it lands.

**More strikes, more firings.**
- **Replays** (Lightning Ring, Thunder Loop — `replay_on_use +1 max=4`): every swing
  leaves the weapon +1 Replay, up to 4; each Replay is one more strike per swing
  (so 1, then 2, … up to 5 strikes). Kept on the pack entry as `replays`, so **it
  rides an evolution** — a Lightning Ring that has earned 3 is a Thunder Loop with 3.
- **Duplicator** (trinket — `weapon_retrigger +1 dirs=adjacent`): a weapon beside it
  fires its whole swing once more (`WeaponSystem.retriggers_for`). An aimed swing
  fires at the same square, so the Stun stacks; a random one rolls new targets.
- **Bloody Tear** (`weapon_hit if_self: gain_hp 1`): a new hook, `weapon_hit`, fires
  once per body per strike, stunned or not.

**What sharpens a swing** (`WeaponSystem.stun_parts`, shown in the hover):
- the weapon's own `stun N`;
- `weapon_stun +N dirs=…` on a neighbour — **Whetstone** (`dirs=up,down`) and the
  **Hero swords** (`dirs=adjacent`) — each such piece once, turned with the piece;
  a Hero sword's aura is for *other* weapons;
- `stun_per_food +N per=M` — **Stankus' Toothpick**: +1 for every 2 food pieces
  touching it (pieces, not kinds: two Garlics are two food);
- `stun_bonus` on the piece itself — Stun it has GAINED for the run, and
  `stun_game` for this game only: an **Upgrade** (§19). **Scroll of Enchant
  Weapon** (`enchant_weapon random 1`) gives a random weapon in the pack +1; it
  moves, saves and evolves with the piece, and the hover says "Upgraded: +1
  Stun". **An upgraded weapon wears its +X**: its name everywhere is "Sword +1"
  (`LootSystem.display_name`, through `WeaponSystem.plus_suffix`) and its tile
  carries a "+1" chip on the art's top-left corner (`LootGrid._add_plus`).
  `WeaponSystem.plus_of` is the one number both read (it asks
  `LootUpgrade.bonus_of`). With no weapon carried, the scroll does nothing and
  stays unread.

Under **Link Cable** (§15) every aura reaches every weapon in the pack, and the
Toothpick counts every food piece.

**King Bomber** pays through a new hook, `weapon_stunned` (once per body a swing
stuns, with the swinging weapon's slot) and a new gate, `if_self`.

**`enemy_stunned`** (22 Nov 2026, Envenom) is the wider hook: once per body a
WEAPON or an ATTACK card stuns, with that body as `target`, so a held piece's
`apply_status … target=enemy` lands on it (`GameState._run_trigger` passes a hook's
`target` on when it names a body). A Stun from a scroll, a bomb or an item is not
it. Its sibling **`enemy_turn_started`** fires at every enemy turn's start, after the
ground (Noxious Fumes, `target=front2`: the two columns nearest you).

**It stands outside the copies.** A swing is three games of goals, so Echo Form,
Echo Chamber and Endless Nameless do not see it (`LootSystem.use_loot`), and a
Blueprint pointed at a weapon copies its passive (a Hero sword's aura) but never
its swing.

**Bags.** **Fanny Pack**'s `charge_bonus 10%`: a charge landing on a piece in it
has a 10% chance to land twice (`GameState._bag_charge_bonus`) — weapons, wands and
food alike. **Holdall**'s `gain_stat shields 1 per=2 of=unidentified_in_bag`
counts the unidentified pieces in its own cells.

**Drops.** Weapons are a loot kind with weight **1** of 19 (half a trinket's).

## 13. Evolutions

The `evolutions` sheet (`generate_evolution_tres.py` → `data/evolutions2.0/`,
`EvolutionData`): **Name** (what it becomes), **Requirement 1** (the weapon that
evolves — it always turns), **Requirement 2** (`Any [N] Item(s) or Trinket(s) with
"tag"`, or the NAME of one item or trinket — Thunder Loop's `Duplicator`,
`EvolutionData.need_id`), **Outcome** (`Consume All` uses the tagged things up, `Consume None` keeps
them). Both weapon names are checked against `weapons` at generation.

A requirement counts **wherever it is held** — a relic on the shelf (Crown) or a
trinket anywhere in the pack. When one of a weapon's evolutions is met, its pack
button reads **Evolve** and its card has an **Evolve →** button; with more eligible
things than needed, the player picks which. The new weapon keeps the old one's
charges (capped), `uid`, goal claim, Replays and place — re-seated where it fits if the
bigger shape no longer does (`WeaponSystem.evolve`).

## 14. The hover glow

Hovering a pack piece lights the pieces it works on in **green** and the pieces
working on it in **blue** (`LootPassives.influence`, drawn by
`LootGrid.light_influence`). One answer for every neighbour rule: a copier and its
target, a `weapon_stun` piece and the weapons it reaches, a food and each
different food touching it, and the food feeding Stankus' Toothpick.

## 15. Link Cable — every piece touches every other

**Link Cable** is a relic (`items`, Rare, `link_loot`, from Batomon Showdown):
**"All Loot count as adjacent to each other."** With one owned, every piece in
the pack counts as touching every other piece, **in every direction** — and that
includes the rules that only look ONE way (the owner's call, 12 Oct 2026). So:

| rule | unlinked | linked |
|---|---|---|
| Whetstone (`weapon_stun dirs=up,down`) | the weapon above and below | every weapon in the pack |
| Hero swords, Duplicator (`dirs=adjacent`) | weapons on any side | every weapon in the pack |
| food (§11) | each different food touching it | each different food in the pack |
| Stankus' Toothpick | food pieces touching it | every food piece in the pack |
| Blueprint (`copy_right`, §2) | the piece it faces (and its chain) | **every passive in the pack** |

**Blueprint copies every passive** (the owner picked this over "unchanged" and
"pick one"): every piece is to its right, so it runs each passive piece's
passive at once — one `active()` row per piece it copies, each marked `linked`.
It skips other copiers, which would only be the same list again, so two
Blueprints beside a Goat Hoof are the hoof and two copies, not a pyramid. A
linked row keeps its `every=N` count and its once-a-game claim under a key
naming the passive it runs (`LootPassives.count_key`), so a Blueprint copying a
Garlic and a Carrot counts the two apart. **Using** a Blueprint is unchanged: it
is used as the piece it actually faces (`usable_copy`), and its arrow still
points there; its hover lists everything it copies.

The grid itself does not change — `neighbour_slot` is still geometry, a dragged
piece still lands where it is dropped — so every rule asks
`LootPassives.linked()` (→ `GameState.links_loot`) first and, when it says yes,
stops asking the grid: `adjacent_pieces`, `copied`, `_works_on` (the hover glow)
and `WeaponSystem.aura_targets`. **A new neighbour rule has to answer there too**,
or it will be the one rule the cable does not reach.

The cable arriving or leaving is an inventory change, so the pack's held-up
statuses and its ready food are recomputed then (`_on_pack_changed`), like a
move.

## 16. Smelter — a piece that leaves the pack and keeps working

**Smelter** is a relic (`items`, Uncommon, The Binding of Isaac: Rebirth, Type
`Passive, Charged, 3`): **"Consume a Loot with a passive effect and treat it as
an item. Doubles the chances of finding trinkets."**

- **The Type is two words.** `Charged` decides how it is used, so it is a
  charged item (`item_dsl._kind_of`): three games to fill, and
  `Charged, 3` is read wherever `Charged` sits in the cell. The passive half is
  `loot_kind_weight: {trinket: 2}`: while it is held, the trinket kind's weight
  in the kind-blind loot roll is doubled (`GameState.loot_kind_weight`).
- **Using it is a pick** (the owner's call, 14 Oct 2026). The overworld opens
  `SmeltChoiceModal` with every piece that can be smelted, and the Smelter
  fires, spending its charge, only on the pick
  (`GameState.smelt_target` -> the `smelt` effect). Closing it costs nothing, and
  an empty list says so and spends nothing, as an aiming item's cancel does.
- **The piece leaves the pack and works from the shelf.** It goes into
  `GameState.smelted_loot` (saved with the run) and `LootPassives.active()` runs
  it after the bags, with `slot` -1: its stat and status grants stay held up,
  its triggers still fire, and a food keeps counting where it left off. It is
  drawn on the relic strip in the Smelter's colour, with a hover.
- **Only a piece that works on its own can go in** (`GameState.can_smelt`). One
  that works through where it sits (Blueprint's copy, the Whetstone and
  Duplicator auras, Stankus' Toothpick) has no neighbours off the grid, so it
  would be smelted into nothing, and is refused. A weapon is swung, not held,
  so it is not passive loot.

## 17. Gecko Gi — a status that costs no Health

**Gecko Gi** is a trinket (`trinkets`, Rare, 2x2, Backpack Battles): **"Burn
does not deal damage to the Player."** Its Effect is `harmless_status burn`,
which compiles to `TrinketData.harmless_statuses` (a list, so a later piece can
name several: `harmless_status burn,marked`).

- **Only the damage is waived.** Burn still lands on you, still stacks, still
  has a 1-in-4 chance to set a scroll alight, and its row is still on the
  checklist: paying it still sheds a stack. What changes is the price of NOT
  paying it. In `GameLoop2._resolve_status_demands` a `take_damage` penalty whose
  status a working piece wards (`LootPassives.warding`) is skipped, and the bill
  is recorded with `damage` 0 and `warded_by` set, so the report says
  "Burn bites — Gecko Gi takes it, no damage." rather than nothing.
- **The checklist row says so first.** A warded demand's row ends
  "(Gecko Gi: no damage)", because "or take 3 Damage" over a bill that will not
  land would misstate what skipping it costs.
- **It is held like any passive**: read off `LootPassives.active()`, so a
  Blueprint copying it wards too, and a smelted Gecko Gi (§16) keeps working
  from the shelf. Cards, bags and weapons refuse the keyword in their
  generators. It is a trinket's rule.

## 18. Curse cards

**A curse is a card in the pack** since 14 Nov 2026. The owner: *"get rid of
curse goals. These curses will now count as cards (not available in the basic
loot drop)."* Before that, a curse was a row on the post-game checklist that
you were trying not to complete. If you completed it anyway, an enemy spawned.
That row, its timer and its penalty are all gone.

- **Content.** The `curses` sheet, generated by `tools/generate_curse2_tres.py`
  into `data/curses2.0/` as **`CardData`** with `loot_type` `Curse`
  (`CardData.is_curse`). It is not part of the `cards` sheet, and
  `Data.all_cards()` leaves curses out. `Data.get_card` still finds one, so a
  carried curse is an ordinary `{type: card, id}` entry
  (`GameState.curse_entry`) that every surface already knows how to draw, name
  and describe. Its art lives in `images2.0/curses/` (`CardData.art_folder`).
  The columns are `Curse | Type | Game | Description | Effect | Keywords | Tag
  | Image`.
- **There is more than one kind of curse.** The owner: "multiple types of curses
  that all count as curses". A **curse card** is a row of this sheet with `Type`
  `Card`, which is every row today. A **cursed weapon** (Retro Bat's
  Unidentified Equipment, `docs/players-design.md` §5) is a curse too, but it comes
  from a weapon's roll rather than a row. Both count: `GameState.is_curse`,
  `curse_count` (with `curse_card_count` for the cards alone), the inventory's
  Curses list and the Scroll of Remove Curse all take either. The generator
  refuses any `Type` other than `Card` until something reads it.
- **It is a passive piece.** It is never spent and works from its cell. Its
  `Effect` uses the passive-card grammar, so **Blueprint copies a curse's
  effect** like any other passive's. Curse of the Bell, Injury and Poor Sleep
  have no effect and only take up space. **Debt** is `game_beaten: lose_gold 2`,
  which costs 2 Gold every time a game is finished, win or lose. **Guilty** is
  `enemy_killed every=5: remove_self`. That is food's counted trigger (§11), so
  its square shows `have/need` like a food's, and `remove_self` takes it out of
  the pack on the fifth kill (`GameState.expire_curse_card`). Like
  `break_into`, a Blueprint copying Guilty is the piece that goes. Their card text is composed by the generator from their
  **keywords** ("Eternal: can't be destroyed."), so it cannot claim a rule the
  card does not have. The keywords also show on the hover and as chips on the
  placement modal.
- **It is never in the ordinary loot drop.** `Data.roll_card` draws only from
  the `cards` sheet. A curse arrives only through `GameState.add_curse_card`,
  which is reached by an event's `add_curse`, the Calling Bell, the Amnesia
  pill, the Hexer and the Lacerator. `add_curse random` draws only curses
  tagged `random`, so Curse of the Bell is never dealt at random.
- **It is placed on the loot modal, and that modal has no Skip.** `add_curse_card`
  puts the entry on `GameState.pending_curses` (saved with the run) and emits
  `curse_offered`. The page's `DropQueue` then opens `LootDropModal.open_curse`
  (layer `CURSE`, above the event and haul screens), ahead of anything else
  waiting. The curse cannot go in the bin (`LootGrid.can_trash`), and `leave()`
  refuses. **If the pack is full, the player has to use or bin something to
  make room.** The modal only lets a curse go unplaced when no room can be
  made, because every carried piece is itself a curse or pinned
  (`LootDropModal.no_way_in`). With no page listening (headless runs and
  tests), `place_curse_headless` takes the first free cell and, if the pack is
  full, destroys the last piece that is allowed to leave.
  Curses are kept out of `DropQueue.queue` deliberately. The haul screen takes
  that queue over at a report, and you can walk away from what is on its table.
- **The player can never take a curse out of the pack.** That covers the bin,
  putting it down on the board, trading it for a piece off the floor
  (`swap_loot_entry_at`), an event's `lose_card` price, a thief's theft, a
  `lose a card` cost and the Smelter. `GameState.can_leave_pack` is the single
  rule for all of these, and it is false for a curse and for a pinned piece.
- **UNMOVABLE: it can't be moved.** The keyword pins the curse where it was
  placed (`CardData.movable` false, `GameState.is_pinned`),
  exactly like a cursed weapon. It cannot be moved, turned or swapped, and its
  bag stays put too (`bag_holds_pinned`). This is **Poor Sleep**.
- **ETHEREAL: it goes away after 3 games.** The generator writes the keyword as
  a `game_beaten every=3: remove_self` trigger (`ETHEREAL_TRIGGER`), so it counts
  games finished, win or lose, and its square shows the count as `1/3` in games
  rather than ⚡ charges (`LootPassives.COUNTED_HOOKS`). This is **Clumsy**.
- **NORMALITY'S `limit_actions N`.** This is a curse's own Effect clause
  (`CardData.action_limit`). While the curse is carried, the player may take no
  more than N usable actions each game, counted in
  `GameState.actions_this_game`, which resets where the game resolves and is
  saved. The actions are a relic active fired (`can_fire_item` and `use_item`),
  any piece of pack loot used, whether from the pack, off a table or thrown
  (`LootSystem.use_loot` / `use_entry`, wand zaps and weapon swings included;
  Echo copies are not actions). The board verbs (Bash, Dash, Push, Transmute,
  Scramble, Bombs) are **not** actions: they counted for one commit, and the
  owner took them out as too complicated. Each door asks
  `can_take_action` first, so a refused press costs nothing, and calls
  `note_action` once the action goes through. The pack's Use buttons and the
  relic strip grey out at the limit. Two Normalities give the smaller limit, not
  the sum.
- **Two hooks only the curses use** (`TriggerBus`, the relic grammar):
  `action_taken` fires on every action Normality counts (`note_action`), and
  **Pain** is `action_taken: lose_hp 1`. `game_ending` fires at the end of a game
  (not an escape) at the step a status's bill lands, while the game's Temporary
  Shields still stand (`GameLoop2.beat_game`, `docs/turn-order.md` §4 2c).
  **Decay** is `game_ending: take_damage 1`, a hit a Shield can block. **Regret**
  is `game_ending: lose_hp_per_loot 2`, which costs 1 Health per 2 pieces in the
  pack and on the board, rounded down; it is Health, not a hit, so no Shield
  stops it. All three are ordinary triggers, so Blueprint copies them.
- **ETERNAL: it can't be destroyed.** No effect can destroy it
  (`CardData.destroyable` false, `GameState.can_destroy`).
  `destroy_loot_at` refuses it, and every effect that picks victims leaves it
  out of the pick: Prepared, the row-burners, Degradation and the Scroll of
  Remove Curse. This is **Curse of the Bell**. A curse that *is* destroyed or
  lifted is simply gone. It does not go on the destroyed pile, so Exhume cannot
  return it, and Trading Card does not pay for it.
- **The Scroll of Remove Curse** lifts any Destroyable curse card
  (`GameState.lift_curse_card`), alongside cursed weapons.

| Curse | Type | Keywords | Dealt at random | Given by |
|---|---|---|---|---|
| Curse of the Bell | Card | Eternal | no | the Calling Bell |
| Injury | Card | — | yes | Punch Off, Golden Idol, the Lacerator, random deals |
| Poor Sleep | Card | Unmovable | no | Unrest Site |
| Guilty | Card | — (leaves after 5 kills) | yes | random deals |
| Debt | Card | — (−2 Gold per game) | yes | random deals |
| Clumsy | Card | Ethereal | yes | random deals |
| Normality | Card | — (3 loot/active uses a game) | yes | random deals |
| Decay | Card | — (1 damage at the end of a game) | yes | random deals |
| Pain | Card | — (−1 Health per loot/active use) | yes | random deals |
| Regret | Card | — (−1 Health per 2 pieces, end of a game) | yes | random deals |
| Greed | Card | Eternal | no | Sunken Treasury's Second Chest |

Tests: `test/test_curse_cards.gd` covers the pack rules, `test_overworld2.gd`'s
curse-card block covers the modal, and the sources are covered where they live
(`test_events2`, `test_enemy_abilities`, `test_items2`, `test_pill_system`,
`test_scroll_system2`).

## 19. Upgrade — +1 on a weapon, or on a card with an Upgrade Type

The owner, 14 Nov 2026: *"Upgrading a card in this game should be Upgrade 1 Loot.
At the moment that includes all attacks and all weapons. It gives a base +1 stun
to them stacking indefinitely."* Slay the Spire's Upgrade, translated.

- **Code:** `scripts/runtime/LootUpgrade.gd` is the rule — what can be upgraded
  (`can_upgrade`), what is carried that could be (`upgradeable`), and how much a
  piece has (`run_bonus`, `game_bonus`, `bonus_of`). Every reader asks it, so a
  new kind becomes upgradeable by being answered there.
- **What can be upgraded:** a **weapon** (it grows its Stun), and a **card whose
  `cards` row names an `Upgrade Type`** (the owner, 17 Nov 2026: "Different cards
  can be upgraded, not just attacks" — and "Power cards should not be able to
  upgrade, only the cards I've selected"). The column is `CardData.upgrade_types`;
  `N/A` means never. What each type grows is `LootUpgrade.grows`, one table:

  | Upgrade Type | grows | cards |
  |---|---|---|
  | Stun | each `stun` clause | Bullseye, Cleave, Fiend Fire, Finisher, Iron Wave, Pommel Strike, Reaper |
  | Shield | each `gain_stat shields` | After Image (its trigger), Iron Wave, Second Wind, Shrug it Off, Stack |
  | Charge | `charge_pick` | Bloodletting, Offering |
  | Potion | `gain_loot potion` | Alchemize |
  | Loot | `gain_loot` | Prepared |
  | Destroy | `destroy_pick` | Prepared |

  A card can name more than one type, and an upgrade then grows every one of
  them: Prepared (Loot, Destroy), and Iron Wave (Shield, Stun — the owner,
  20 Nov 2026: an upgraded Iron Wave is Shield 2 and Stun 2).

  `tools/generate_card2_tres.py` refuses a row whose type names a clause the card
  does not have (its `UPGRADE_CLAUSES` mirrors `grows`), and
  `test_loot_upgrade.gd` holds the `.tres` to the same rule.
- **What it does:** +1 to each growing clause's **base** number, per upgrade, no
  cap. A weapon's swing adds it to its sheet's Stun (`WeaponSystem.stun_parts`,
  "Upgraded" in the breakdown). A card adds it to **each growing clause's own
  number before `per` multiplies it** (`LootUpgrade.grown`, called by
  `CardSystem.play_card` and, for a passive card's trigger, by
  `GameState._run_trigger`): an upgraded Fiend Fire is Stun 2 for *each* piece
  destroyed, an upgraded Stack 2 Shield per other card used — the owner chose this
  over a flat +1 on top. Other clauses (Bullseye's Marked, Offering's Health) do
  not grow.
- **Downgraded** (Retro Bat's roll, `docs/players-design.md` §5 — every
  upgradeable card can be found at -2..+2): the same numbers shrink. Stun stops at
  0 (it does nothing below that); a **Shield clause goes negative and takes Shield
  away**, down to none (the owner: "Block or charges can be lost through this" —
  `GameState.NON_NEGATIVE_RUN_STATS`); charges, potions, loot and destroys stop at
  0, and a clause at 0 asks for nothing. A lifted curse holds each at 1.
- **Where it is kept:** on the pack entry. `stun_bonus` is for the run — the key
  Scroll of Enchant Weapon already wrote, so the +X, the swing and an evolution
  all read one number whichever door the upgrade came through. `stun_game` is for
  this game only; the report erases it at the step it zeroes
  `cards_used_this_game` (`LootUpgrade.clear_game_bonuses`), however the game
  ended. Both ride a weapon's evolution and are saved with the pack.
- **How it shows:** an upgraded card wears its +X like a weapon — "Cleave +1"
  face up, the "+1" chip on its tile, and "Upgraded: +1 Stun to each Stun it
  applies." (or "+1 Shield to each Shield it gives", and so on per type) under its
  description. An upgraded piece whose roll is still HIDDEN reads **"Cleave +1?"**
  (the owner, 17 Nov 2026; `WeaponSystem.hidden_plus`): the upgrade is known, the
  question mark is the roll on top. A this-game upgrade is in the same +X, and the
  chip's tooltip says how much of it goes when the game ends.
- **The numbers in its text are live** (the owner, 20 Nov 2026;
  `scripts/runtime/LiveNumbers.gd`): "Apply Stun 1" on a +1 Cleave reads "Apply
  Stun 2", in **green** above the sheet's number and **red** below it (a known
  downgrade). Strength and Dexterity on you show the same way, on every piece whose
  text names an applied Stun or a Shield gain — cards, weapons' swings, relics,
  trinkets, bags, pills, potions (spec §13.4). A hidden roll is left out of the
  text, as it is left out of `stun_parts`. The "Upgraded: …" line stays under
  the description to say why the number moved.
- **The token:** `upgrade_loot [N] [pick|random] [run|game]` — one parser
  (`item_dsl._upgrade_loot`) shared by the reward DSL and the item DSL, handled by
  `EffectSystem._h_upgrade_loot`. In an **event** it defaults to `pick`: the modal
  steps aside (no resume chip), the page lights the upgradeable pieces in the pack
  through `Overworld2.begin_owned_pick` (verb "upgrade"), and the click is the
  choice; **Back** returns to the event with the button unspent. With no page that
  can run a pick, the handler rolls one instead. On a **relic** it defaults to
  `random`. The button reads "Upgrade 1 Loot"; the epilogue names the piece
  ("Upgraded Cleave +1").
- **The gate:** `upgradeable` joined the event Requirement stats — upgradeable
  cards and weapons carried. The owner chose to hold a whole event back rather than show a
  dead button when there is nothing to upgrade.

| Source | Upgrades | Lasts |
|---|---|---|
| **Ominous Forge** (Rare event, Slay the Spire) — Forge | 1 piece the player picks | the run |
| **Warped Tongs** (Event relic, from the Forge's Rummage) | 1 random piece at the start of every game | that game |
| Scroll of Enchant Weapon | 1 random **weapon** | the run |

Warped Tongs is Slay the Spire's "At the start of your turn, Upgrade a random card
in your hand for the rest of combat", moved onto Anchor's hook (`game_selected`,
"At the start of combat") because a game here is one combat. Its description:
"At the start of combat, Upgrade 1 random Loot for the rest of combat".

**Bloodletting and Offering place their charges ONE PICK AT A TIME** (the owner,
17 Nov 2026): `LootUseModal._pick_charge` asks once per charge, in the pack and the
relic strip like every owned pick, and comes back with one fewer each time, so
Offering's four can go 2 + 1 + 1 or all on one thing. Only things with room are
offered; the charges land as they are picked, and one line reports them all.

Tests: `test/test_loot_upgrade.gd`.

## 20. Chests — loot you open

**The owner, 18 Nov 2026:** "Chests will now be treated as loot in the sense that
you can move it around in your inventory" — and, asked, *pack item, open any
time*. A chest is the ninth kind of loot (`type: "chest"`), and
`scripts/runtime/ChestLoot.gd` is the whole of its rule:

- **Where it comes from.** Every chest a report pays (`GameLoop2.claim_chests`)
  and every chest banked while the reward screen is up (a level-up's) lies on that
  screen's **table** (`PostCombatScreen`), first, beside the loot the bodies
  dropped. A chest left on the table is lost with the rest.
- **What it holds.** Its relics are rolled when it is earned, as they always
  were, and kept on the entry as ids (`offer`), so a save carries it and the
  seeded stream is drawn in the same order. `choices` is how many it offers (its
  size, `ItemDropModal.chest_rank`), `boss` and `pool` how it was rolled — what
  a Reroll asks again (`PostCombatScreen.reroll_chests` for every chest on the
  table, the chest's own Reroll once it is open).
- **Opening.** Its cell's button reads **Open** (`LootSystem.use_verb`). Opening
  takes it off the table or out of the pack, pays its gold (`Data.chest_gold`),
  and asks which relic to take on the same `ItemDropModal` every chest uses,
  above whatever screen it was opened from (`ChestLoot.open`). From the pack it
  opens anywhere, mid-game included (`Overworld2.open_carried_chest`).
- **How it looks.** The chest icon the player wears (Customization, by size; a
  Boss chest is its own rung), or the same gift its popup draws, rendered per
  size in the popup's colours (`images2.0/general/Chest*.png`). In a pack or
  table cell it is drawn with the popup's own badge — the glow behind the gift
  and its stars arced over it. No Preference badge: it is not a gamble. Under the
  board, "Beat it:" draws each chest with the popup's own badge — the glow and
  the arced stars (`ItemDropModal.gift_badge`).
- **Between games.** A chest banked with no reward screen up (a potion's
  level-up, a location's trade) is rolled and offered as chest loot on the
  ordinary loot screen (`Overworld2._redeem_pending_chests`).

## 21. Structures — pieces that count the structures around them

**The owner, 20 Nov 2026:** "I'd like to focus on the structure mechanic by adding
items with the structure tag." Backpack Hero's structures, as `trinkets` rows
tagged `structure`, all four from that game:

| Piece | Rarity | Size | At the start of combat (`game_selected`) |
|---|---|---|---|
| **Brick** | Common | 1x1 | +1 Temporary Shield per structure **beside** it (the four sides) |
| **Brick Wall** | Uncommon | 1x2 (two wide) | +1 per structure beside it **or diagonal** to it |
| **Roof** | Rare | 1x2 (two wide) | +1 per structure **anywhere in the columns under it**, touching or not |
| **Masonry Tools** | Legendary | 1x1 | not a structure; see below |

Each starts at 0: a Brick on its own pays nothing. The owner chose Backpack Hero's
own reach for each (Brick sides only, Brick Wall diagonals too) and a Temporary
Shield (Wooden Cross's).

- **The rule is `LootPassives.structures_counted(entry, count)`**, and the three
  counts are `of=` sources of `gain_stat`: `gain_stat shields 1 per=1
  of=structures_beside` / `structures_around` / `structures_below`
  (`EffectSystem._h_gain_stat`, beside Holdall's `unidentified_in_bag`). A new
  structure piece is a sheet row, not code.
- **A structure counts once**, however many of its cells touch the piece, and a
  piece never counts itself. A Roof is a structure too, so a Brick beside it counts it.
- **"Below" turns with the Roof**, like Whetstone's up and down: turned upside
  down it counts the structures above it. It wears an arrow that way
  (`LootPassives.directions`).
- **A Blueprint copying a structure is one**, as one copying a food is that food
  (`is_structure` asks what a piece runs), and it counts from where the Blueprint
  sits, since it is the piece that fires.
- **Link Cable** (§15): every other structure in the pack counts, the Roof's
  included.
- **Hovering** a structure piece lights the structures it counts (`_works_on`).

**Masonry Tools** — "At the end of combat, add a Brick to a random empty space in
this row": `game_beaten: place_in_row brick`. The owner chose **every game end, won
or lost** (`game_beaten`, not `game_won`) and **its own row as drawn**, bag cells
on that row included. A full row places nothing. The row is the screen's, whichever
way the tools are turned. The verb `place_in_row <trinket>` (`EffectSystem._h_place_in_row`)
takes any trinket id.

The art is the Backpack Hero wiki's original sprites (`Brick.png`,
`Brickwall.png`, `Roof.png`, `Masonry_Tools.png`). Tests: `test/test_structures.gd`.
