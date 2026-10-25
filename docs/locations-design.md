# Locations — design

Status: **built** (23 Oct 2026). Six locations are authored in the `locations`
sheet; 45 more are candidates in `research/locations.csv`, and 106 effects to
match them with are in `research/location_effects.csv`.

This replaces the location half of
[archive/locations-and-events-design.md](archive/locations-and-events-design.md), the earlier
brainstorm. That doc gave every location a GOAL, and had the player pick one of
two or three at each difficulty step. The owner dropped both:

- **A location has no goal.** The checklist already has goals from enemies,
  the level-up, statuses and curses. A location goal read like one more enemy
  row, and writing a unique goal for every area was not interesting.
- **The player does not choose.** A location is dealt and announced.

What a location brings instead is a **temporary rule change for one stretch of
the run**, which nothing else has:

| | lasts | chosen? |
|---|---|---|
| statuses, curses | until removed | no |
| Fractures | the whole run | yes, before it starts |
| events | one moment | yes |
| **locations** | **from one difficulty up to the next** | **no — dealt** |

## 1. When a location is dealt

- **At the start of the run.** `GameLoop2.start_run` deals a Low one before
  the start is picked.
- **At every difficulty up.** The tier counts spawns (every 4th, or 3rd on a
  Fracture). `GameLoop2._capstone_if_due`, which ends every spawn path, calls
  `_location_if_due` after the capstone boss. When the tier is higher than the
  one the location was dealt for, a new one of the new tier is dealt.

**"When entered" means the first game picked there, once** (the owner, 23 Oct).
Dealing a location sets `location_arrival_due`; its arrive effects run at the
next node arrival — `choose_game`, after that arrival's bodies and capstone —
and never again. So the run's
first location arrives with its first game rather than onto an empty board, and
a difficulty up that lands mid-game (a lost run's spawn) or at a game's end never
drops bodies into a game already being played. A Scramble is not entering. When
the location is dealt by the arrival itself, it is entered by that same arrival
([turn-order.md](turn-order.md) §1).

`Locations.deal(tier)` picks a random location authored at that tier, skipping
the one being left when it can. A tier with none authored steps **down** to the
nearest tier that has one, the way an enemy roll widens. An empty roster deals
nothing and the run carries on without a location. That is the suite's case:
`test/pre_run_hook.gd` empties the roster, as it does the shopkeepers.

A save from before locations comes back with `location_tier` -2. It adopts the
tier it is at, and the next step is the first that deals.

## 2. What a location does

The sheet's `Effect` column, read by `tools/generate_location_tres.py`.
Clauses are separated by `;` and sit under a header:

| header | when | effects |
|---|---|---|
| `arrive:` | once, when it is dealt | `spawn_enemy <tag> <n>`, `place_tile <tile> <n>`, `place_unit <tag> <n> [favour=<unit>:<pct>]`, or **anything an item's Effect column can say** |
| `while:` | as long as the run is there | `damage_taken_mult <x>`, `offering_rift <n>`, `push_mult <n>` |
| `action <limit>:` | a button, up to `<limit>` times | `<cost> => <pay>`. Cost: `lose_max_hp <n>` or `spend <stat> <n>` (keys, bombs, gold, bash, dash, transmute, scramble, push, shields, bonus_shields). Pay: `gain_chest <size> [<tag>]`, or any item effect |

**The item grammar is the fallback.** An `arrive:` clause or an action's payout
that is not one of the location's own verbs is read by
`item_dsl.parse_one_effect` and run through `EffectSystem.apply`. So
`gain_stat bombs 2`, `heal_full`, `spawn_boss`, `add_curse injury`,
`gain_scroll 2` and `apply_unit landmine random_empty` all work with no new
code. That is why 52 of the 106 effect ideas are already writable.

The eight authored:

| location | tier | Effect |
|---|---|---|
| Burning Basement | Low | `arrive: spawn_enemy fire 1; place_tile fire 2` |
| Dross | Low | `arrive: place_unit poop 2 favour=poop:80` |
| The Hive | Medium | `arrive: spawn_enemy bug 2` |
| Caves | High | `arrive: spawn_enemy spider 2; place_tile web 3` |
| Dark Room | High | `while: damage_taken_mult 2; action 4: lose_max_hp 2 => gain_chest small devilish` |
| The Chest | High | `while: damage_taken_mult 2; action 4: spend keys 1 => gain_chest small` |
| The Moon | High | `arrive: spawn_enemy alien 1; while: push_mult 3` |
| The Void | Insane | `while: offering_rift 1` |

The `Effect` cells were written from the owner's `Description`s by
`tools/oneshots/_locations_effect_column_setup.py` (Caves and The Moon by
`tools/oneshots/_units_destruction_effect_setup.py`). The descriptions are what the
player reads, and the Effect is what runs.

### 3. The pieces each one needed

- **`damage_taken_mult`** is folded into `GameState.combat_totals()`. So a
  swing, a status's bill and every preview of them (the strip, the OBS overlay)
  read the same doubled number.
- **A tagged chest** (`gain_chest small devilish`). `GameState.grant_chest`
  takes a pool, kept in step with the choice counts in `pending_chest_pools`.
  Both chest screens (the RewardScreen between games, the haul screen after
  one) draw such a chest only from items carrying that tag or pool
  (`Data.reward_item2_pool_tagged`), leaned, with no rarity roll. A word that
  nothing rollable carries rolls an ordinary chest. Today only The Mark is
  `devilish`, so the Dark Room's chest is The Mark until more items are tagged.
- **`offering_rift`** (The Void). `Overworld2._add_location_rift_cards` makes one
  card of every offering a Rift Key card that costs no key (`free_rift`). It
  REPLACES an ordinary card, never the Amulet and never the last card on a
  shortest road. With nothing safe to replace it is added past the end. It
  respects Settings → rifts.
- **`push_mult`** (The Moon). `Locations.push_mult()`: the Push verb moves its
  body that many cells for its one charge (the first as ever, the rest on
  `shove`'s terms, as far as there is room), and a weapon's shove goes that
  many times its squares.
- **Actions** are greyed with their reason when they cannot be paid, like a
  machine's buttons: `GameLoop2.location_action_blocked`. Lose Max Health never
  takes the last point of it.

## 4. The tag lean

`Tag Type` (a comma list) and `Tag % Up` (0.2 = +20%). While the run is in a
location, **anything carrying one of its tags weighs 1 + Tag % Up** in whatever
roll it is in. Several matching tags count once. The lean works **inside** the
bucket the roll already chose: an enemy still matches the game's type and the
run's tier, and an item still lands on its rarity rung. A lean never trades the
genre or the difficulty away, and it never forces anything.

It is `Locations.pick(bucket, rng)`, and it is in every roll a tag means
something to:

| roll | where |
|---|---|
| enemies, escorts, bosses, conjured bodies | `GameLoop2._pick_by_type_tier`, `roll_conjured_enemy` |
| relics in a chest (both screens), boss relics | `RewardScreen._roll_choices`, `DropQueue.roll_drop` / `roll_chest` |
| trinkets, cards, wands, weapons, bags, potions | `Data._roll_by_rarity` |
| scrolls (the lean multiplies the find rate, so 0 is still never) | `Data._pick_by_find_weight` |
| shop shelves (on top of the shop pool's own weight) | `ShopSystem._weighted_pick` |
| objects, item grants (`gain_item_per_rarity`, `gain_random_item`) | `Data.roll_object_by_tag`, `EffectSystem` |
| the units a location lays | `GameLoop2._roll_location_unit` |

Pills have no tags, so they are never leaned. **With no lean, `pick` makes
exactly the draw it replaced**, on the same stream and in the same order.
Seeded runs, saves and tests are unaffected; `test_locations.gd` holds that.

## 5. Blocking units: the poops

Dross lays poops, the first units that BLOCK (the sheet's Effect `block`;
`UnitData.blocks`). The units sheet gained two columns for them:

- **On Destruction** — what the unit leaves when its Health runs out, in the
  owner's words. Since 23 Oct the generator reads the machine version beside it,
  **On Destruction Effect**: parts with a `N%` are one weighted draw; a bare
  part always happens. Outcomes: `loot`, `spawn_enemy <tag>`, `gold <n>`,
  `heal <n>`, `give <loot id>`. An enemy that crawls out stands on the unit's
  square, or the nearest one its shape fits; it walks on at the back only when
  the board has no room for it at all.
- **Tag** — what the unit is (`poop`), for picking units by tag and for the lean.

On the board:

- `fits_at` treats a blocking unit's cell as taken. So no step, spawn, push
  or Trample stands a body there, and the spawn shove plans around it.
- A body whose step it stops tries Trample, then Agile, and only then
  **strikes the poop for what it would hit you for** (`enemy_damage`:
  Strength, Burn's halving, a Fracture, a rift; never less than 1) instead of
  stepping (`_walk_one`). Only when the poop blocks its step: a Ranged body does
  not shoot one from range.
- The player breaks it with anything that hits the ground: a bomb, a thrown
  potion. **It pays whoever breaks it** (`_unit_destroyed`). That gives a
  Golden Poop a reason to be bombed before the stack chews through it.
- A unit with more than 1 Health wears a ❤ badge on the board, and its hover
  card says it is a wall.

## 6. Showing it

- **The DIFFICULTY strip** over the board (it was "AMULET PRESSURE") is two
  lines: the tier, its four pips (Low to Insane) and the location; then the
  spawns to the next boss, the Amulet's distance with its pressure pips, and
  what ending this game costs. The panel keeps the pressure band's colour, and
  the boss warning still takes the second line's place while it is up.
- **The arrival popup** (`scripts/redesign2/LocationPopup.gd`, loaded by path
  so it stays out of the page's compile): "YOU ENTER", the name, tier and
  source game, the art, the description, the lean in words, and the actions as
  buttons, plus a gold line while its arrival is still waiting for the next
  game. `GameLoop2.location_unseen` is the flag, saved with the run. The
  page opens it at its next quiet moment: not over the start screen, the
  board's playback, the haul screen, a reward or another popup. Each of those,
  when it closes, asks again.
- **The chip** (`LocationChip`) sits at the right of the DIFFICULTY strip's
  first line, after the tier and its pips, because the two change at the same
  moment. It
  shows a thumbnail and the name. Hovering shows the art at a readable size and
  everything the popup says. A hover card cannot hold a button, so clicking
  reopens the popup, and that is where the actions are used.
- **The manual** has a Locations section under Bosses and difficulty, and the
  poops under The ground.

## 7. Saving

`location_id`, `location_tier`, `location_uses` (per action), `location_unseen`
and `location_arrival_due` are saved by `GameLoop2.serialize`. A location since
deleted from the sheet loads as none. The art is 1920×1200, so `LocationData.image`
loads lazily, like a game cover.

## 8. Adding one

1. A row in the `locations` sheet: Name, Game, Difficulty (`1-Low` …
   `4-Insane`), Description, Effect, Tag Type, Tag % Up, Img.
2. Its art in `images2.0/locations/<Img>.png`.
3. `python3 tools/generate_location_tres.py`. It refuses an Effect it cannot
   read, a tile or unit tag that does not exist, and an empty Effect.
   `check_data_sync.py` (CI) runs it with every other generator.

Ideas for step 1 are in `Research.xlsx`: the `locations` sheet (45 places from
the chart's games, each with a description and, where possible, its Effect)
and the `location_effects` sheet (106 effects to match to places). The effects are also on one
readable page, grouped: [location-effects.md](location-effects.md). See
[research.md](research.md) §6.6–6.7.

## 9. What the ideas are waiting for

Most of the 54 effects marked "not ready" are waiting for one of these. Each
one would unlock several effects at once:

| piece | unlocks |
|---|---|
| a `game_ended:` header (an effect at the end of every game here) | Laid Charges, Every Step Burns, Hold the Line, Ziggurat |
| a `leave:` header (an effect when the location is left) | ATM's debt |
| location-scoped item flags (`heal_multiplier`, `gold_per_enemy`, `loot_multiplier`, `base_chest_bonus`, `boss_chest_bonus`, `hide_spawns`, `grid_length`, `bomb_cardinal`, `spawn_status`) | No Healing, Double Healing, Rich Veins, Double Loot, Bigger Chests, Bosses Pay More, Fog, Long Corridor, Bombardier, Bolstered Ranks, Swift Ground, Armoured, Bloodied Arena |
| granting an ability to every body while here | Haunted, Trampling Herd, Restless Dead, Agile Foes, Hunting Ground, Tanky Brutes |
| a shelf off any game beaten here | Market Day, Black Market, Tristram |
| location-scoped Fracture rules | Thin Air, Relentless, Tower of Sisyphus |
| verb locks, Camp switches, an event skip or double | Dud Powder, Locked Doors, No Rest, Campfire, Quiet Roads, Busy Roads |
