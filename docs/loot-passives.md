# Loot passives: trinkets, passive cards, and where things sit in the pack

Some loot is never spent. A **trinket** (the sixth loot kind) and a **passive
card** (a card whose line opens "Passive:") sit in a cell of the 3x3 pack and work
from there, the way a relic works from the shelf. The idea comes from backpack
roguelikes like Backpack Battles: the pack is a space you arrange, and some pieces
care about what is next to them.

- Content: the `trinkets` sheet (11 Isaac trinkets) and five passive rows on the
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
a piece that reads its right neighbour. `LootPassives.pack_columns` is the one
statement of the grid's width, and `LootGrid` draws with it.

**Blueprint** (`copy_right`) does whatever the piece to its right does:

- If the neighbour is a Goat Hoof, Blueprint holds up a second point of Speed.
  If it is a Swallowed Penny, it pays a second coin.
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
| `gain_gold N per=P of=<stat>` | N for every P of the stat, rounded down, read before this payout lands (To the Moon: `per=5 of=gold`). |
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

## 6. Size (not yet)

The `trinkets` sheet has a `Size` column ("1x1"). The generator reads it into
`TrinketData.size` and **refuses anything but 1x1** until the pack learns shapes.
Multi-cell pieces (Backpack Battles-style 1x2 / 2x2 / L shapes) were deliberately
left for later. When they come, `neighbour_slot` and `loot_layout` are where the
shape has to be taught.

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
