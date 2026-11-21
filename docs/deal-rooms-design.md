# Devil and Angel Deals

The Binding of Isaac: Repentance's Devil Room and Angel Room, as two events any
player can be dealt, and Batsaac's mechanic of FINDING them the way Isaac does.
Asked for by the owner on 21 Nov 2026. The numbers come from the Repentance
wiki's Devil Room and Angel Room pages (bindingofisaacrebirth.wiki.gg; the
Fandom copy refuses scripts).

| what | where |
|---|---|
| the rules | `scripts/runtime/DealRooms.gd` |
| the state (saved with the event bag) | `GameState.deals` |
| the two events | `events` sheet → `data/events2.0/devil_room.tres`, `angel_room.tres` |
| the mechanic | `mechanics` sheet → `data/mechanics/devil_and_angel_deals.tres`, on Batsaac's `players` row |
| the item pools | the items sheet's `pools` column: `devil_room`, `angel_room` |
| the room on screen | `EventModal2` (`_render_deals`, `_deal_card`) |
| the bonus roll (Batsaac's, or anyone's relics) and the door | `Overworld2.report` → `DealRooms.roll_after_game`, `_open_pending_event` (`docs/turn-order.md` §4–5) |
| the odds chip | `Overworld2._build_deal_chip` / `_paint_deal_chip` |
| tests | `test/test_deal_rooms.gd` |
| art | `images2.0/events/`: `DevilRoom` / `AngelRoom` (the doors), `DevilStatue` / `AngelStatue`, `DevilRoomIcon` / `AngelRoomIcon` (the chip's marks), all the wiki's originals |

## 1. The gate: no enemy took your Health this game

Every deal room — drawn from the bag or found by Batsaac — needs a game in which
no ENEMY took any of the player's Health. "An enemy" is a hit that got past the
Shields (`HEALTH_SOURCE_ENEMY_ATTACK`) or a status's charge (`HEALTH_SOURCE_STATUS`,
Burn's bill). A hit a Shield stopped took no Health, so it does not count; nor does
anything the player did to themselves (an event's price, the Blood Donation
Machine, a pill, Hunger, a deal), because Isaac's red-heart-damage rule excludes
self-damage too. `DealRooms.note_health_lost` counts it off `TriggerBus.health_lost`;
`note_game_started` (from `GameLoop2.choose_game`) clears it.

On the events sheet it is the Requirement `enemy_hp_lost=0`, a gate stat like any
other (`EventSystem._run_stat`, `generate_event2_tres.GATE_STATS`).

## 2. The events

Both are **Rare**, **wordless** like the Arcade Room, and two buttons: **Enter**
(`Repeat: Stay`, `enter_deal_room`) and **Leave** (`nothing`).

- The picture is the **door** until you walk in, then the **statue**
  (`EventModal2._art`, `_render_deals` swaps the texture).
- **The bag deals only the Devil Room.** The Angel Room is never drawn
  (`EventSystem.blockers_for`: "only behind a Devil Room's door"); it is what a
  door turns out to be when it opens (§4).
- **A player with the mechanic never draws either** ("this player finds deal rooms
  by chance"): Batsaac's come through §3, so one game cannot pay two.

## 3. Batsaac's chance (Repentance's formula)

A **floor** is one difficulty-up boss's band: it begins when that boss walks on
(`GameLoop2._capstone_if_due` → `note_new_floor`, `_land_capstone_boss` →
`note_floor_boss`) and its **boss fight** is the game the boss leaves the board in
(`_take_off_board` → `note_off_board`; a boss leaves only by its goal). Champion
bosses and the Emperor's are not floor bosses. Before the first boss is floor 0.

After every game handed in (not a detour), `Overworld2.report` rolls
`DealRooms.roll_bonus`. The chance (`chance_parts`) is:

| term | value | Isaac's |
|---|---|---|
| never on the run's first game | 0 | no deal on Basement 1 |
| an enemy took Health this game | 0 | the gate (§1) |
| a door already opened this floor | 0 | one deal room a floor |
| base | 1% | 1% |
| the floor's boss fell this game | +35% | no red-heart damage against the boss |
| …and no enemy took Health since it walked on | +99% | no red-heart damage all floor |
| relics with `deal_chance` (Book of Revelations +17.5, The Book of Belial +12.5) | + | the same two, Afterbirth+ numbers |
| a door on this floor or the last | ×0.25 | seen less than two floors ago |
| a door two floors ago | ×0.5 | seen two floors ago |

Capped at 100%. Luck counts (`Favour.HIGH`: a door is what the player wants), and
the chip quotes the odds Luck will actually roll (`shown_chance`).

A hit opens a **bonus** door before the game's ordinary event, which stays queued
behind it (`_pending_deal`; `_on_event_finished` comes back to `_open_pending_event`
for it). The bonus spends no node.

**The chip** beside the Hunger pips (Batsaac only) shows the Devil's and the Angel's
share of the chance a door opens after this game, with the Isaac map marks, and a
tooltip listing every term.

### 3.1 Anyone else: the relics' chance, once a difficulty up

The owner, 21 Nov 2026: "holding things that give devil deal bonus should give
it to any player and it should show the %. It will trigger as a bonus event after
increasing difficulty". A player WITHOUT the mechanic who holds a relic with
`deal_chance` (Book of Revelations 17.5, The Book of Belial 12.5) gets exactly
that much — none of Batsaac's base or boss terms — cut by the same recent-door
multiplier (`item_chance_parts`). It is rolled ONCE per difficulty up, at the
report of the game the difficulty up lands in (`roll_item_bonus`, `rolled_floor`),
and is spent for that floor whether or not the game was clean; a game an enemy
took Health in, or a floor that already had its door, rolls nothing. A hit is the
same bonus door before the game's own event. `roll_after_game` is the one call the
report makes for both kinds of player.

The chip shows for them too (`chip_active`) while they hold such a relic, with the
chance that will be rolled and when.

## 4. Devil or Angel (Repentance's coin flips)

Decided when the door OPENS (`open_door` → `pick_kind`), for every player:

1. A deal ever paid for → Devil, for the rest of the run.
2. No Devil door seen yet this run → Devil. (So the first door is always the Devil's.)
3. The first Devil door was walked away from without entering → Angel, once.
4. Otherwise one 50% flip, plus a second 50% flip when 10 Gold or more went into a
   Donation Machine this floor (`note_donated`, from `ObjectSystem.donate`). Any flip
   landing makes it the Angel's. Luck stays out (`Favour.NONE`): neither side is
   the better one.

Isaac's other flips (Key Pieces, beggars, Rosary, Eucharist, confessionals) wait
for content that would carry them.

**Doors seen** are recorded for every door, bag or bonus, which is a difference
from Isaac (a Joker card's teleport does not count there): without it a player
without the mechanic could never be shown an Angel.

## 5. Inside

Walking in (`enter_deal_room` → `DealRooms.enter`) lays out **2, 3 or 4 items**,
weighted by Repentance's own layouts — the summed weights of every layout with that
many deals (Devil 14.85 / 5.65 / 0.25, about 72 / 27 / 1%) or items to choose from
(Angel 2.75 / 0.35 / 0.25, about 82 / 10 / 8%). Items are drawn from the room's
item pool (`ItemData.pools`), different and not already owned. **A short pool
shows fewer items** — nothing fills an empty slot (the owner: more items are
coming). Hearts, chests, fireplaces, spikes and the rooms' enemies are not carried
over.

- **Devil:** each item costs **Max Health by rarity — 2 / 4 / 6 / 8** for Common
  to Legendary (the owner's numbers). A price bigger than the Max Health held takes
  **all of it** (the owner's rule A, after Isaac's "as long as he has one Red
  Heart"). With **0 Max Health** the price is **3 Shields** (Isaac's three soul
  hearts). Paying for any one sets `deal_taken`.
- **Angel:** free; take one and the rest vanish.
- A deal that would leave no Max Health and no Shield is **red with ☠** and asks
  "Are you sure?" first, like every other press that can end the run.

The room closes with its event (`EventModal2._end_objects` → `close_room`).

## 6. Living on Shields

The owner's rule that came with this: **a run at 0 Health — or 0 Max Health —
lives while it holds permanent Shields** (`bonus_shields`; Temporary ones do not
count), as Isaac lives on soul hearts. Everywhere:

- `GameState.out_of_health()` (Health 0 and no Shields) is every death check's
  question (`GameLoop2._check_death`, `_take_hit`, `lose_health`). Shields
  changing re-asks it (`stats_changed`).
- **Max Health floors at 0**, not 1: `set_max_hp`, `lose_max_hp` (events, pills),
  Drain, the dev panel.
- **A Health bill that runs past the Health comes off the Shields**, one per point
  (`GameState.change_hp`, for any source but an enemy's hit or a status — those met
  the Shields first, and Pierce means past them).
- What counts as lethal measures against Health **and** Shields
  (`GameState.health_and_shields`: `EventSystem.is_lethal`, Bad Trip's save).

## 7. Not yet

- Bombing a statue (Uriel / Gabriel, Key Pieces), Krampus — "we can figure out the
  statue thing later".
- More items in the two pools, and the chance items (Pentagram, Goat Head, Black
  Candle, Eucharist, Rosary Bead, Act of Contrition) — the owner is adding items.
  The devil pool is five so far: Brimstone Bombs, The Mark, The Necronomicon, and
  (21 Nov 2026) The Book of Belial (Charged 3: +4 Temporary Strength; +12.5% deal chance) and
  Whore of Babylon (+3 Strength and +1 Speed at 2 Health or less).
