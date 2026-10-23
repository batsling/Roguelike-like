# Turn order: what fires first

One game, from the click on the map to the last screen after the report, in the
order the code runs it. Everything here resolves the instant a button is pressed;
the board's animation afterwards only replays it.

The spec says *why* each rule is what it is (`docs/games-first-redesign.md`, §2.1,
§3.2, §7.4, §19.5). This doc only says **in what order**, which the spec never
gathers in one place and which is the first question every new item, ability or
status raises: *is my hook early enough to see X, or late enough to see Y?*

**This doc is checked.** Under each section is an ` ```order ` block naming one
function and, line by line, pieces of its source that must appear in that order.
`python3 tools/check_turn_order.py` (CI, Content pipeline) fails when one goes
missing or moves above the line before it. When it fails, read what changed, then
fix the section's prose and its block **together** — never loosen a snippet just to
make it pass. A change that adds a step (a new signal, a new phase of the report)
should add a line to the block as well as a sentence above it; nothing can check
for a step the doc has never heard of.

A rendered view of this doc lives as a private page (*Turn Order Codex*) for the
owner. It is regenerated from this file; this file is the one that is true.

Legend used below: **signal** is a `TriggerBus` / `GameLoop2` signal; **items**
means relics and pack pieces answer it (§0); **board** means the enemies or the
ground act; **☠** marks a step that can end the run.

---

## 0. How any one trigger fires

Every "items" step goes through `GameState.fire_run_item_triggers(hook)`:

1. **Relics, in the order you got them** (the inventory, oldest first).
2. **The equipped weapon.**
3. **Pack passives**, in `LootPassives.active()` order — Blueprint copies and Link
   Cable neighbours included.
4. Each checks its **gates** first — its `if_…` conditions, then its loot
   conditions, then `once_per_game`, then `every N` — and only if all pass do its
   effects run, one after another, through `EffectSystem`.

A trigger that causes something else (gold, Health lost, a kill) fires *that*
hook right there, nested, before the outer trigger moves on to the next item. The
one loop guard: gold paid **inside** another trigger does not ask the pack
passives about `gold_gained` again. Relics are still asked, and the gold always
lands.

```order
scripts/autoload/GameState.gd :: fire_run_item_triggers
sources.append_array(inventory)
equipped_weapon
_fire_source_triggers(item, trigger_name
not (nested and trigger_name == "gold_gained")
LootPassives.active()
```

```order
scripts/autoload/GameState.gd :: _fire_source_triggers
_trigger_gates_pass(trig, ctx_extras)
_loot_gates_pass(trig, ctx_extras, loot)
once_per_game
"every"
_run_trigger(item, trig, ctx_extras, loot)
```

## 1. Picking a game

`Overworld2._begin_game`, one click on the map, before anything is played:

1. The game's and the character's **rank bars** are noted, for the end screen.
2. **Starting gear**, first game of the run only.
3. **The board is set up** (`GameLoop2.choose_game`):
   - the last game's lost runs, ticks and records are wiped;
   - a **spawn event** is counted — the board can grow and the tier can step here;
   - board: **Undying** bodies from last game stand back up, first;
   - board: the game's enemy is placed, then the second body (plus any a Fracture
     adds), each running its spawn-time abilities as it lands;
   - on the 4th spawn event, board: the **capstone boss** walks on →
     signal `boss_spawned` → items;
   - and if the tier stepped, a new **location** is dealt
     (`docs/locations-design.md`): its arrival runs last, on top of everything
     the spawn put down (bodies of its tag, tiles lit, poops stood up), then
     signal `location_changed`. The run's first location is dealt the same way by
     `start_run`, before the start is picked. Its popup waits for the page's next
     quiet moment.
4. The **difficulty step** is announced, if step 3 crossed one.
5. An **Event node fires its event now**, before the game. (Every other node rolls
   its event at the report.)
6. **Shields**: 3 Temporary Shields, 5 for a Traditional roguelike, fewer on some
   Fractures. *Then* signal `game_selected` → items (Anchor's +1 lands on top), the
   speedrun clock starts, the overlay updates.

```order
scripts/redesign2/Overworld2.gd :: _begin_game
GameLoop2.rank_start =
_grant_start_gear_once(game)
_commit_board_for_kind(game, enemy, tier)
_announce_difficulty_step(tier_before, board_before)
_fire_arrival_event(game)
GameLoop2.grant_selection_shields(game)
```

```order
scripts/autoload/GameLoop2.gd :: choose_game
_clear_attempts()
_count_spawn_event()
_pay_revivals()
_add_to_grid(inst, enemy
_spawn_second_body(
_capstone_if_due(
```

```order
scripts/autoload/GameLoop2.gd :: _capstone_if_due
_land_capstone_boss(type_key, tier)
_location_if_due()
```

```order
scripts/autoload/GameLoop2.gd :: enter_location
location_id = loc.id
_run_location_effect(effect)
location_changed.emit(location_id)
```

```order
scripts/autoload/GameLoop2.gd :: grant_selection_shields
GameState.shields += n
TriggerBus.game_selected.emit(
```

## 2. While you play

All player-driven, any order, any number of times; each press resolves fully
before the next can happen.

- **Tick a goal (Yes)** — one hit on that body (`GameLoop2.fulfill`) → the kill
  chain (§6). A survivor with Health left is **stunned** instead.
- **Tick a bonus / status goal** — pays through `EffectSystem` at once.
- **Use loot** — signal `loot_used` plus the kind's own (`card_used`,
  `potion_used`, `bomb_used`, `wand_used`) → items.
- **The weapon** — `weapon_charged`, `weapon_hit`, `weapon_stunned` → items; a hit
  runs the kill chain.
- **A bomb** — one hit to each normal body in the blast (bosses take none), mines
  caught in it go off; kill chain, no loot drop.
- **Lose a run** — the enemies take a turn (§3).

```order
scripts/autoload/GameLoop2.gd :: fulfill
cleared_this_game[instance] = true
_damage_enemy(idx, GOAL_HIT)
_defeat(e, true, res, fell, record, rift)
_stun_survivor(instance)
```

## 3. A lost run: the enemies' turn

`GameLoop2.log_attempt`. The only thing that moves the board during a game, and
everything in it is put back by Undo.

1. **Snapshot for Undo**: the board, Health, gold, both shield pools, your
   statuses, your inventory.
2. Signal `run_lost` → items, **before anything swings**: what an item hands out
   for a lost run (Ripple Basin's +1 Temporary Shield while no goal is done) is
   armour against this very turn's swing, not a consolation after it.
3. **One enemy turn** (`attempt_turn` → `_resolve_enemy_turn`):
   - **a0. The ground first.** Every body standing on a tile fires its turn-start
     effect (fire adds Burn, so the halved damage is on it before it swings). A
     body can die here → kill chain.
   - **a. Each body in board order gets ONE action:** already dead → skipped;
     **stunned** → sits it out; (on an *extra* turn only, the **Censer** holds the
     front columns out); an **intent** (Ritual, Defensive Stance, a spawner, a
     thief's getaway) → does that instead; **can't reach** → Ruthless bodies hit
     whatever is in the way, the rest wait for the step; **in reach** → an
     invisible body is revealed, then it swings → the hit chain (§7) ☠.
   - **b. The step.** Every body that hasn't acted closes a column, into free rows
     only. Entering a tile fires its on-enter effect (a mine goes off); loot lying
     there is pushed aside; the off-grid queue slides in as cells free. A body
     whose way is blocked tries Trample, then Agile's diagonal, and only then, if
     a **blocking unit** (a poop) is in the way, strikes it for 1 instead of
     stepping. A unit that breaks pays its On Destruction there and then.
   - **c. Turn-measured statuses wear off** — the one place a Stun stack ticks down.
4. The **lost-run spawn roll**, Luck included: a hit walks a body of this game's
   type on at the back column and resets the ladder; a miss climbs a rung. A hit
   is a spawn event, so the board can grow and a capstone boss can arrive →
   `boss_spawned`, and a new location can be dealt (§1).
5. The log line, then the animation replays the turn.

```order
scripts/autoload/GameLoop2.gd :: _walk_one
if fits_at(enemy, row, col - 1, inst):
push_through
move_diagonal
damage_unit(cell, 1)
```

```order
scripts/autoload/GameLoop2.gd :: log_attempt
_attempt_snapshots.append(_run_snapshot())
attempt_costs.append("turn")
TriggerBus.run_lost.emit(
attempt_turn()
_roll_lost_run_spawn()
attempt_logged.emit(
```

```order
scripts/autoload/GameLoop2.gd :: attempt_turn
_resolve_enemy_turn(turn, res)
_board_snapshot()
_check_stack("end of turn")
```

```order
scripts/autoload/GameLoop2.gd :: _resolve_enemy_turn
_fire_turn_start_cells()
_index_of(inst) < 0
is_stunned(entry)
censed_cols > 0
_take_intent(entry, res, taken)
can_strike(entry)
_ruthless_strike(entry, res)
_reveal(entry)
_take_hit(enemy_damage(entry), res)
_pay_recoil(entry, res)
_wear_statuses(entry, &"attack")
_attack_riders(entry, hit, res)
_advance_stack(
_wear_statuses(entry, &"turn")
```

```order
scripts/redesign2/Overworld2.gd :: log_attempt
_board.capture_positions()
GameLoop2.log_attempt()
_announce_attempt_turn(
_board.animate_resolve(
```

## 4. Handing the game in

The report button — beaten, missed and escaped all come through here.
`Overworld2.report` calls `GameLoop2.beat_game`, whose numbered steps are:

- **0.** Status payouts (enemy bonuses, your status goals), while every body
  they're claimed against is still on the board.
- **1.** Goals ticked *on the report* take their hit, all at once → kill chain;
  survivors are stunned. (Goals ticked earlier resolved in §2.) Burn's `instead`
  clears count as hits but not as goals met. Then the **end-of-game bill** is
  priced (Amulet pressure, +1 if nothing died, +1 always on an escape), and the
  game stops being in play.
- **2a.** board: **Predatory Scent** — if you had status goals and met none, those
  hunters take one extra turn; the Censer holds the front out of it. ☠
- **2a′.** board: **Fracture 8+** — the whole board takes one extra turn after a
  game won or escaped. ☠
- **2b.** **Status bills** (Burn's 3 damage), while shields still stand → hit chain.
- Leftover Temporary Shields **expire**, or **Barricade** banks them as Shields.
  Per-game loot counters and the lost-run tracker reset.
- **3.** Your status **clauses** tick, if any goal was completed this game.
- **3b.** Your **game-measured statuses** wear off (Bleed, Stun on you).
- **4.** board: **tiles** burn down a game.
- **4b.** board: **Fading** bodies tick (one that runs out dies, no loot); *then*
  **Restless Remains** corpses rise.
- **5.** **Potion statuses** run out.
- **5′.** board: the **end-of-game bodies** walk on (not for a teleport out). They
  act from your next lost run.
- The game's checklist record is cleared.

Then, back in `Overworld2.report`:

1. The **floor** is swept onto the haul; the **report chest** is queued (beaten,
   not escaped); status penalties are announced; each kill is recorded to the
   Atlas and the character.
2. An **event** is rolled for after the haul (not on a detour); a **Shop** node
   queues its shelf.
3. Signal `game_beaten` (any report but an escape, won or not) → items (Burning
   Blood), every charged item +1, Harvesting, the toast, the overlay.
4. Signal `game_won` (goal met) → items; then `game_perfected` (won with no lost
   run) → items.
5. The **game's own loot** (a scroll or a pill) is queued. Not on an escape.
6. Bookkeeping: game marked played, the clock's split banked, beats and perfects
   recorded (won only), the repeat-visit Dash.
7. **Level-ups**: the character's, then any Mask characters'.
8. **Event goals** resolve and tick; games played +1; a difficulty step is
   announced.
9. The **animation** replays the extra turns of 2a / 2a′, then §5.

```order
scripts/autoload/GameLoop2.gd :: beat_game
_resolve_status_claims(claims)
_resolve_instead_claims(claims)
_damage_enemy(idx, GOAL_HIT)
_stun_survivor(int(inst))
end_of_game_price(escaped)
game_in_play = false
_predators(claims)
Fracture.extra_turn()
_resolve_status_demands(claims, res)
GameState.banks_shields()
_clear_attempts()
_tick_player_clauses(goals_completed)
_wear_player_statuses()
_decay_tiles()
_tick_fading()
_raise_corpses()
_expire_timed_statuses()
_land_end_of_game_bodies(spawns_owed, escaped)
_clear_game_record()
```

```order
scripts/redesign2/Overworld2.gd :: report
GameLoop2.beat_game(
_sweep_floor_into_the_queue()
_queue_report_chests(
_announce_status_penalties(res)
_record_defeat(played_game, cleared)
EventSystem.roll_for_arrival(slot_here)
ShopSystem.is_shop(slot_here)
TriggerBus.game_beaten.emit(
TriggerBus.game_won.emit(
TriggerBus.game_perfected.emit(
_queue_loot_drop()
GameState.note_game_played(
RunTimer.finish_game(
GameState.note_game_beaten(
_apply_level_up()
_resolve_event_goal_rows()
GameState.games_played += 1
_announce_difficulty_step(tier_before, board_before)
_board.animate_resolve(
```

## 5. The screens after

Once the animation ends (`_end_resolve`):

1. If the run ended at any ☠ step, the **run-over screen** opens and nothing below
   happens.
2. The **end-of-game screen** — the haul: floor loot, kill drops, chests, the
   game's own loot, the boss warning, and *Go to Shop* on a Shop node. Autosave
   when it closes.
3. The **Collapse** screen, Fracture 10's Amulet only.
4. The **event** rolled at the report.
5. The **shop**, if this was a Shop node.

```order
scripts/redesign2/Overworld2.gd :: _end_resolve
_run_over_pending
_show_run_over()
_open_post_game()
```

```order
scripts/redesign2/Overworld2.gd :: _on_post_game_finished
autosave()
CollapseScreen.open(
_open_pending_event()
```

## 6. The kill chain

Any hit on a body — a goal, the weapon, a bomb, a tile, Bleed:

1. The damage is adjusted by the **body's statuses** (Marked doubles it).
2. Its own **Shield** eats the hit, if it has one. Stop.
3. **Health still above 0?** It survives. Stop.
4. **Off the board.** Then its stolen goods drop; then its **death abilities** in
   the order written (death tile, summon, Undying, corpse); then any **illusions**
   it made die too, each through this same chain. Chains stop 16 deep. Then the
   off-grid queue slides in.
5. **Chest points** are banked (a boss banks a boss chest), then **gold** →
   `gold_gained` → items.
6. **Your item's death tile** is laid where it fell.
7. Signal `enemy_killed` → items (Charm of the Vampire).
8. Signal `enemy_defeated` → its loot lands on the square it fell on; the shop and
   the overlay hear it.

```order
scripts/autoload/GameLoop2.gd :: _damage_enemy
StatusData.apply_damage_mods(
enemy_shield(entry) > 0
int(entry["health"]) > 0
_take_off_board(idx)
_body_died(entry, fell)
```

```order
scripts/autoload/GameLoop2.gd :: _body_died
graveyard.append(
_drop_stolen(entry, fell)
MAX_CHAIN
entry_ops_at(entry, &"death")
"illusionist"
_admit_offgrid()
```

```order
scripts/autoload/GameLoop2.gd :: _defeat
boss_chests.append(
chest_points += worth
GameState.change_gold(coins)
GameState.death_tile()
TriggerBus.enemy_killed.emit(
enemy_defeated.emit(enemy, fell)
```

## 7. The hit chain (an enemy hits you)

1. The **swing** is the body's damage with its Strength.
2. **Your statuses** adjust it (Marked doubles it).
3. **One shield stops the whole hit** — a Temporary Shield first, then a Shield.
   Piercing skips this.
4. The rest comes off **Health** → `health_lost` → items (Piggy Bank), *then*
   fragile items shatter.
5. **Health 0** → the run is over. ☠
6. Back on the body: **Bleed's recoil** is rolled, then its attack-measured
   statuses wear off (§3, step a).
7. **Riders**, only if the hit got past every shield, in the order written:
   Devour, a status, a curse, destroyed loot, a drained stat, a theft.

```order
scripts/autoload/GameLoop2.gd :: _take_hit
StatusData.apply_damage_mods(
GameState.shields > 0
GameState.bonus_shields > 0
GameState.change_hp(-overflow, source)
_finish_run(false)
```

```order
scripts/autoload/GameState.gd :: _on_health_lost
fire_run_item_triggers("health_lost", ctx)
_destroy_fragile_items()
```

```order
scripts/autoload/GameLoop2.gd :: _attack_riders
int(hit.get("blocked", 0)) > 0
entry_ops_at(entry, &"hit")
```
