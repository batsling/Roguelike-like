# Potions — design & implementation plan

Companion to [`games-first-redesign.md`](games-first-redesign.md) (the canonical
spec). That doc's §4.1 is scrolls and its §4.3 is pills; this one is the **third
loot consumable**, and it is written the same way the pill work was: what a potion
is and why, then the code it lands in, then the order to build it.

Content source: the **`potions2.0`** sheet of `tools/Roguelikes.xlsx` (15 rows) and
the art in `images2.0/potions_identified/` (9 bottles) +
`images2.0/potions_unidentified/` (37 coloured vials).

Status: **design decisions locked, unbuilt.** Nothing in `scripts/` knows what a
potion is yet — but a surprising amount of the plumbing is already there, and §9.1
is the list.

---

## 1. Decisions locked

Eight forks were settled before any code, in the same discovery-pass style as the
[implementation plan](games-first-redesign-implementation-plan.md#1-decisions-locked-in-discovery):

| # | Decision | Choice |
|---|---|---|
| 1 | **What a quaffed buff IS** | **Timed player statuses.** Potions introduce the first status with a clock on it, and Strength / Dexterity / Speed grow a player-facing combat side to be worth gaining (§5). |
| 2 | **What a throw is aimed at** | **A cell.** Red Candle's ground picker (`BattlefieldView.aim_cells`), every square legal, empty ground included — areas centre on the cell (§4.2). |
| 3 | **Bottle art** | **All 37 colours, both sets mixed.** 15 potions bound per run, 22 sitting out (§6). |
| 4 | **Loot income** | **Three-way split.** Beating a game pays 1 piece: ⅓ scroll, ⅓ pill, ⅓ potion (§8). |
| 5 | **Throwing a Positive potion** | **It helps them.** A thrown Block Potion shields the body it lands on. That is what makes quaff-or-throw a second gamble on an unknown bottle (§2). |
| 6 | **How long "until the end of the next combat" is** | **Until the next game is resolved**, whichever game that is — it dies in `GameLoop2.beat_game` beside the tiles (§5.1). |
| 7 | **Potion of Raise Level** | **A free level-up**: the character's normal reward path, without the condition being met (§7.3). |
| 8 | **Scroll deltas** | **Same doc, same sheet pass** — the rarity column, Amnesia's widened forget and the rest are load-bearing for potions (§10). |

---

## 2. What a potion is (and why it is not a third pill)

The run already has two consumables that are one effect behind a mask:

- a **scroll** hides its *name* behind one shared Unidentified art, and reading it
  is the gamble (§4.1);
- a **pill** hides its *name* behind a colour dealt fresh each run, and swallowing
  it is the gamble (§4.3).

A potion is the first one that is **two effects in one bottle**. Every row of
`potions2.0` authors an `On Player` side and an `On Tile` side, and the player
chooses which one they are buying at the moment they spend it: **Quaff** it, or
**Throw** it at a square of the battlefield. That choice is the whole reason the
kind exists — a potion that could only be drunk would be a pill with different art.

**Preference describes the QUAFF, and the throw is usually its mirror.** Fire
Potion is `Negative` because drinking it costs 3 Health and sets you alight; thrown,
it is the strongest offensive piece of loot in the game. Block Potion is `Positive`
because drinking it is +2 Shields; thrown, it hands two shields to whatever is
standing there. So the sheet's Preference column is honest and the throw is not a
free upgrade — which is what keeps an **unidentified** potion a two-sided gamble
rather than a one-sided one:

> You know it is a bottle. You do not know whether it wants to be drunk or thrown,
> and the two are usually opposites.

That is the design, and it is why decision #5 went the way it did. A rule that made
thrown Positives fizzle would mean throwing an unknown bottle is *strictly safe*,
and a player who worked that out would throw every unknown — which is a
one-decision consumable wearing two verbs.

---

## 3. The roster, as authored

15 rows. `Quaff` is the sheet's `On Player`, `Throw` is its `On Tile`.

| Potion | Rarity | Pref. | Quaff | Throw | Art |
|---|---|---|---|---|---|
| Fire Potion | Common | Neg | Take 3 damage, gain +3 Burn | Fire tile, 1 damage, +3 Burn over a 3×3 | ✅ |
| Block Potion | Common | Pos | +2 Shields | 2 shields to what is there | ✅ |
| Speed Potion | Common | Pos | +5 Dexterity for a game | +5 Dexterity for a game | ✅ |
| Flex Potion | Common | Pos | +5 Strength for a game | +5 Strength for a game | ✅ |
| Dexterity Potion | Common | Pos | +2 Dexterity for a game | +1 Dexterity for a game | ✅ |
| Strength Potion | Common | Pos | +2 Strength for a game | +1 Strength for a game | ✅ |
| Explosive Ampoule | Common | Neg | Take 3 damage | 1 damage to the cell and its row | ✅ |
| Potion of Healing | Common | Pos | +2 Health | +2 Health to what is there | ✖ |
| Potion of Self-Mutilation | Common | Neg | Take 3 damage | 3 damage to what is there | ✖ |
| Potion of Uselessness | Common | Neutral | Nothing | Nothing | ✖ |
| Fysh Oil | Uncommon | Pos | +1 Strength and +1 Dexterity for a game | the same, to what is there | ✅ |
| Potion of Haste Self | Uncommon | Pos | +2 Speed for a game | +2 Speed for a game | ✖ |
| Fruit Juice | Rare | Pos | +2 Max Health | +2 Max Health to what is there | ✅ |
| Potion of Extra Healing | Rare | Pos | +5 Health | +5 Health to what is there | ✖ |
| Potion of Raise Level | Rare | Pos | +1 Level | — (N/A) | ✖ |

Four things the table says out loud:

- **10 Common / 2 Uncommon / 3 Rare** sits cleanly on the shared 75/20/5 ladder
  (`Data.roll_rarity_step`), so the roller needs no potion-specific weighting.
- **The throw is weaker per body and wider per square.** Dexterity and Strength
  Potions give the drinker +2 and a body +1; the Ampoule takes 3 off you and gives
  1 to a whole row. Area is what you are paying the difference for.
- **Slay the Spire's names came with Slay the Spire's meanings.** "Speed Potion" is
  +5 *Dexterity*, not Speed — that is what it does in its source game. `Potion of
  Haste Self` is the one that is actually Speed.
- **Six rows have no `File`.** They take the same fallback scrolls take (§6.3), and
  the two rows whose throw is `N/A` (Raise Level, and Uselessness by authorship)
  need the fizzle rule of §4.5.

---

## 4. The two verbs

### 4.1 Quaff

The existing spend path, unchanged: the Use button in the loot window, on the info
card, or on the drop modal's offer, going through `LootSystem.use_loot` /
`use_entry` so the piece is consumed, echoed and remembered exactly like a pill
(§4.3). `PotionSystem.quaff_potion` is the resolver, with `ScrollSystem.read_scroll`
and `PillSystem.take_pill`'s signature and answer shape:

```gdscript
{ "logs": Array[String], "requests": Array[Dictionary] }
```

### 4.2 Throw is aimed at a cell

A throw needs a target, and the target is **a square of the battlefield**, not a
body. That is Red Candle's rule (§17.3) and it is right here for the same reason it
is right there: a Fire Potion thrown at empty ground two columns in front of the
stack is one of the best things you can do with one, and a picker that only lit up
bodies would make that impossible.

So the board's existing ground picker does the work — `BattlefieldView.aim_cells`,
which today takes an `ItemData` and answers with every legal square. It needs one
generalisation: **aim at a thing that is not necessarily an item.** Either widen it
to accept a `{target_kind, col_min, col_max}` shape both `ItemData` and a potion
entry can produce, or hand it a tiny aim-request Dictionary. Do not fork it — one
highlight rule, one accepted-click rule, is the whole reason that function exists.

**Aim first, then confirm.** The use modal arms the picker and hides itself, the
player clicks a square, and the throw resolves with the cell already in hand:

```gdscript
LootSystem.use_loot(index, {"rng": rng, "verb": "throw", "target": cell})
```

`ctx.target` carrying a `Vector2i` is the existing convention —
`EffectSystem._effect_cells` reads exactly that key for `target=tile` items — so a
thrown potion and an aimed Red Candle arrive at the ground the same way. **This is
deliberately not a `request`.** A request is fulfilled *after* the piece resolved;
a throw has nothing to resolve until it knows where it landed, and routing it
through the request queue would mean an Echo Chamber replay asking for four targets
after the fact.

**The consequence for echoes and for Sacred Bark**, which has to be said now rather
than discovered later: an echoed potion re-throws **at the same cell**. The player
aimed once; the copies land where the original did, which is both the simple rule
and the one that reads correctly ("the bottle you threw, again").

### 4.3 The area words

`On Tile Effect` clauses take an `area=` token, resolved **relative to the aimed
cell**:

| `area=` | Cells |
|---|---|
| `cell` (default) | the square that was clicked |
| `row` | every column of that square's row |
| `col` | every row of that square's column |
| `3x3` | the square and its eight neighbours, clipped to the board |
| `board` | every square |

They belong on `GameLoop2` beside `target_cells` and `column_cells`, as
`GameLoop2.area_cells(cell, area)` — the board owns what a shape means, exactly as
it owns what `front` means today. Clipped, never wrapped: a 3×3 centred on the
corner of a 4×4 board is four squares, and that is a real cost of aiming at the
edge.

### 4.4 A throw is not a bomb

An Explosive Ampoule looks like a bomb and must not *be* one. It resolves through
`GameLoop2._damage_enemy` per body — the one place a hit on an enemy lands (§13.4)
— and **not** through `_explode`. Three things follow, all of them wanted:

- it does **not** fire `bomb_used`, so Blood Bombs is not paid by a potion;
- it is **not** widened by Brimstone or stunned-in by Sticky — the potion's own
  `area=` is its whole geometry;
- it costs no Bomb charge, because it costs a bottle.

What it *does* inherit is the fairness half of the bomb rules: a body killed by a
thrown potion is **destroyed, not defeated** (no drop, no gold — §4), and a **boss
takes no damage** from one, the same shrug it gives a bomb (§7.1). A Rare bottle
that one-shot a boss's health would make §7.1 a suggestion.

### 4.5 Fizzles, not refusals

The rule loot already lives by (§4.3): a Use button that will not press teaches the
player the piece is broken. Every dead end here is a fizzle instead, and the piece
is **identified either way** — `PotionSystem` identifies before it applies anything,
like both its siblings, so the gamble pays its information out even when the effect
lands on nothing:

- a throw at a square with **nothing on it** and no tile clause: *"It smashes on
  empty ground."*
- a **`N/A` throw** (Raise Level): the Throw button is not offered at all for a
  *known* potion — there is nothing to aim — and an **unknown** one that turns out
  to be Raise Level fizzles on impact. That asymmetry is correct: hiding the button
  for unknowns would leak which bottles have no throw.
- **Potion of Uselessness** does nothing, loudly, in both directions. It is the
  roster's joke and it should read as one on the outcome screen.

---

## 5. Timed buffs — the first thing in this game with a clock on it

Nine of the fifteen potions say **"until the end of the next combat"**, and nothing
in the build can express that today. Statuses are permanent until completed (§13),
tiles count games (§17), and the run's stats never expire. This is the one genuinely
new *system* potions need.

### 5.1 The rule

**A timed status dies when the next game is resolved.** One sentence, one hook:
`GameLoop2.beat_game`, in the same pass that burns the tiles down —

```gdscript
res["tiles_expired"]   = _decay_tiles()
res["statuses_expired"] = _expire_timed_statuses()   # new, beside it
```

— beaten or missed, walked away from or fought to a standstill, exactly like the
ground. Quaffed on the overworld it covers the next game you take; quaffed *during*
a game it covers the game in progress, and dies with it. That is decision #6 and it
is the version a player can hold in their head: **it lasts one game, and the game
you are standing in counts.**

It also means the expiry is *reported*. `beat_game`'s result dict is what the report
screen reads, so a buff running out says so on the screen where the game ended,
rather than vanishing between one look at the HUD and the next.

### 5.2 What the statuses have to DO first

Here is the prerequisite, and it is bigger than the potion work around it. In
`statuses2.0` today, Strength / Dexterity / Speed are all `EnemyOnly = Yes` (§13.4)
— their combat side is felt by a body, and their **player** side is a standing goal
clause. So "+5 Dexterity" on the player currently means *"if 5 bosses were beaten
without getting hit, gain a chest"*, which is not a thing that can expire in a game
and not what the potion means.

Three of the four need a player-facing meaning:

| Status | On a body (today) | Proposed on the player |
|---|---|---|
| **Dexterity** | `shield +{X}` — a pool that eats hits | **The same**: X Shields, into the non-expiring pool (§4.3). Falls straight out of `_grant_shield_for`. |
| **Strength** | `damage_dealt +{X}` — its hits land for more | **Damage the player deals**: +X on a bomb, a thrown potion, a Landmine. Today all of those are hardcoded to 1 (`BOMB_HIT`); this is what a player-side `damage_dealt` should read. |
| **Speed** | `tile_move +{X}` — closes X extra columns per step | **Buys turns back**: −X enemy turns per game, floored at 0, against the §7.4 pressure. Speed's own vocabulary, pointed at the clock instead of at a lane. |
| **Burn** | halves damage dealt | Already player-facing (`EnemyOnly = No`) — nothing to do. |

`StatusData.combat_totals(held, StatusData.PLAYER)` already aggregates the player's
side and `GameState.combat_totals()` already calls it; what is missing is `EnemyOnly`
being cleared on those three rows and the two or three read sites that would then
have something to read. **This is a sheet change plus a handful of call sites, and
it should land before the potions do** — a potion that grants a status nothing reads
is a potion that does nothing.

### 5.3 Where a clock lives

`GameState.player_statuses` is `id → stacks`, and a stack count has no room for an
expiry. Two options, and the second is the recommendation:

1. **A parallel dict** — `GameState.status_expiry: {id: games_left}`. Cheap, but it
   means a status can be half-timed: 3 permanent stacks and 2 that expire, one
   number, no way to know which go.
2. **A timed *layer*** — `GameState.timed_statuses: Array[{id, stacks, games}]`,
   summed into the existing reads (`status_stacks`, `combat_totals`,
   `status_objectives`) rather than stored in them. A potion's stacks are a separate
   row that expires whole; the permanent ones underneath never move. Two potions
   drunk before one game are two rows, both dying at the same `beat_game`.

Option 2 saves as one more array of dictionaries alongside `player_statuses` in
`SaveSystem`, draws as an ordinary status pip on the board's hero with a `⏱ 1 game`
line in its tooltip, and is the only one of the two that survives a run holding both
a permanent Dexterity and a Speed Potion.

---

## 6. Identification — 37 bottles, 15 potions, 22 sitting out

The pill pattern (§4.3) transplanted, and it is a better fit here than it was there:
a potion has a colour *and* a real identity behind it, which is the classic
roguelike shape the pills were an adaptation of.

### 6.1 The deal

`images2.0/potions_unidentified/` ships **37** vials — 25 from NetHack (16×16) and
12 from Shattered Pixel Dungeon (48×42), named `<Colour>_<Game>.png`. A run binds
**15** of them to the 15 potions and leaves **22 meaning nothing**, redealt next run.
The spare pile is what stops deduction: knowing fourteen colours tells you nothing
about the fifteenth, because it may well be one of the twenty-two that never drop.

That is `PillSystem.ensure_colors` almost verbatim, with one change worth making
while transplanting it: pills hold their alphabet in a **`const COLORS` list** so a
colour vanishing from disk fails as one broken texture rather than as a silently
smaller alphabet (and `test_pill_system.gd` checks the list against the folder).
Do the same — a `PotionSystem.COLORS` const of all 37, checked by a test in both
directions this time. `test_pill_system.gd` only checks one way, which is why art
that ships without being listed is art no run can ever show; do not inherit that.

### 6.2 The two art sets are two sizes, and the grid has to cope

16×16 next to 48×42 in one 3×3 grid, with 256×256 identified bottles behind them.
The machinery for this already exists and was built for exactly this problem:
`LootSystem.art_box` asks `PillSystem.art_scale` how much bigger a horse capsule's
own file is than a normal one and sizes the box **from the art rather than from a
constant** (§4.3). Potions want the opposite end of the same function: a *cap*, so
that a 256px identified bottle and a 16px vial both land in the cell's band without
one of them being a postage stamp. Route potion art through the same
`art_tex` / `art_box` pair; do not let a fourth surface pass a raw constant to
`UITheme.crisp_tex`.

### 6.3 Identified art, and the six with none

`File` → `res://images2.0/potions_identified/<File>.png`, resolved on identification.
A potion with a blank `File` — or one whose file does not resolve — **falls back to
the bottle it has been wearing all run**, which is the scroll rule (§4.1) pointed at
the thing potions have and scrolls do not. Never a null texture, and never a fifth
mystery art invented for the artless six.

---

## 7. The sheet and the effect DSL

### 7.1 Schema

    potions2.0: Name | Rarity | Preference | On Player | On Player Effect |
                On Tile | On Tile Effect | Reference | File

Prose column, machine column, in pairs — the `statuses2.0` shape (§13.1).
**Both machine columns are empty today**, for all 15 rows. Filling them is the
authoring half of this work and §7.3 is a proposed first pass at every cell.

`PotionData` (`scripts/resources/PotionData.gd`) carries
`id, display_name, rarity, preference, reference, file, quaff: Array, throw: Array`
plus `rarity_index()` and `art_file()`, both copied from `ScrollData`.
`tools/generate_potion2_tres.py` writes `data/potions2.0/*.tres`, importing nothing
and duplicating little: the clause parser is the scroll generator's, extended.

> **Check the class name before wiring it up.** `PotionData` does not shadow a
> native Godot class, but run
> `godot --headless --check-only --script scripts/resources/PotionData.gd` anyway —
> `TileEffectData` is named the way it is because that check was skipped once.

### 7.2 The grammar

Semicolons separate clauses, as everywhere else. The quaff side is almost entirely
verbs that already exist:

| Clause | From | Means |
|---|---|---|
| `take_damage <n>` | items | damage through `GameLoop2.damage_player` — shields stop it |
| `gain_hp <n>` / `gain_max_hp <n>` | pills | Health, Max Health |
| `gain_stat bonus_shields <n>` | pills | the pool that does not expire (§4.3) |
| `apply_status <status> <n> player` | scrolls | a status on the drinker |
| `none` | items | authored nothing (Uselessness) |
| **`games=<n>`** | **new** | on an `apply_status` clause: it expires after n games (§5.1). Default is permanent, so nothing already authored changes meaning. |
| **`gain_level <n>`** | **new** | the free level-up (§7.3) |

The throw side adds the geometry and the two things a body can be handed that a
tile effect could not:

| Clause | Means |
|---|---|
| `apply_tile <tile> [area=…]` | ground, through `GameLoop2.apply_tile` |
| `apply_status <status> <n> [area=…] [games=…]` | a status on every body the area covers |
| **`deal_damage <n> [area=…]`** | **new** — `_damage_enemy` per body, not a bomb (§4.4) |
| **`grant_shield <n> [area=…]`** | **new** — shield points onto the entry, the pool `_grant_shield_for` fills |
| **`grant_health <n> [area=…]`** | **new** — heals / raises a body's Health |
| `none` | the bottle smashes (§4.5) |

Three new ops and one new token. Everything else is vocabulary the sheet already
speaks, which is the bar a new consumable should have to clear.

### 7.3 A proposed first pass at all 30 cells

| Potion | `On Player Effect` | `On Tile Effect` |
|---|---|---|
| Fire Potion | `take_damage 3; apply_status burn 3 player` | `apply_tile fire area=cell; deal_damage 1 area=3x3; apply_status burn 3 area=3x3` |
| Block Potion | `gain_stat bonus_shields 2` | `grant_shield 2 area=cell` |
| Speed Potion | `apply_status dexterity 5 player games=1` | `apply_status dexterity 5 area=cell games=1` |
| Flex Potion | `apply_status strength 5 player games=1` | `apply_status strength 5 area=cell games=1` |
| Dexterity Potion | `apply_status dexterity 2 player games=1` | `apply_status dexterity 1 area=cell games=1` |
| Strength Potion | `apply_status strength 2 player games=1` | `apply_status strength 1 area=cell games=1` |
| Explosive Ampoule | `take_damage 3` | `deal_damage 1 area=row` |
| Fysh Oil | `apply_status strength 1 player games=1; apply_status dexterity 1 player games=1` | `apply_status strength 1 area=cell games=1; apply_status dexterity 1 area=cell games=1` |
| Fruit Juice | `gain_max_hp 2` | `grant_health 2 area=cell` |
| Potion of Healing | `gain_hp 2` | `grant_health 2 area=cell` |
| Potion of Extra Healing | `gain_hp 5` | `grant_health 5 area=cell` |
| Potion of Haste Self | `apply_status speed 2 player games=1` | `apply_status speed 2 area=cell games=1` |
| Potion of Raise Level | `gain_level 1` | `none` |
| Potion of Self-Mutilation | `take_damage 3` | `deal_damage 3 area=cell` |
| Potion of Uselessness | `none` | `none` |

**`gain_level`** (decision #7) fires the character's ordinary level-up reward path —
`GameState.apply_level_up_stats` with the character's `level_up_stats`, plus its
`level_up_reward_type` — with the condition simply not consulted. A Rare potion
paying the run's biggest single reward is the right size for the rung it sits on,
and it invents no new payout content.

---

## 8. Where potions come from

**The per-game payout becomes a three-way split** (decision #4).
`GameState.add_loot("loot", n)` and `roll_loot_entry("loot")` both currently read
`randi() % 2` in two places; that becomes one shared roll over three kinds, in one
place, so the two can never disagree about the odds. Same income, one more kind —
scrolls and pills each get rarer, which is the intended cost of a third alphabet.

`roll_potion()` on `Data` is `roll_scroll()`'s twin: rarity-weighted through
`roll_item_rarity` (so **Luck rides it for free**, §16), falling back to the whole
pool when the rolled bucket is empty.

**The relics.** Sacred Bark's description already says *"all Loot consumables
(Scrolls, Potions, etc)"* — it doubles a potion's named fields the moment potions
exist, and it doubles the **Negative** rows too (§4.1's rule, and the reason the
Bark is a decision). Echo Chamber replays potions like anything else, at the same
aimed cell (§4.2). **Lucky Foot stays pills-only**: its sheet cell is
`pills_positive` and its whole text is about pills. Whether it should widen is a
balance call for later, not a consequence of this work.

**No relic pays out a potion yet.** `EffectSystem` has `gain_scroll` / `gain_pill` /
`gain_loot`; add `gain_potion` alongside them so the sheet can author one the day
somebody wants to, and leave the roster alone in this pass.

---

## 9. The code plan

### 9.1 What already exists (the reuse map, verified)

The combat cut took `PotionSystem` out but left its footprints, and they are load
bearing in the best way — **the save format already has potions in it**:

- **`GameState.identified_potion_types`** — declared, reset by `reset_run`,
  serialized by `SaveSystem` (`identified_potion_types`), rehydrated on load.
- **`GameState.potion_color_map`** — same: declared, cleared, saved, restored.
- **`TriggerBus.potion_used`** — declared, and `GameState._on_potion_used` already
  forwards it to `fire_run_item_triggers("potion_used", ctx)`. A relic hanging off
  `potion_used` works the day a potion is used (`data/items/toy_ornithopter.tres`
  is one, from the old build).
- **`GameState.loot_items`'s schema comment** already documents
  `potion: {"type": "potion", "id": StringName, "rarity": String}` as an entry kind.
- **`LootSystem`** dispatches on `entry.type` in six places — every one of them a
  `match` with a `"scroll"` and a `"pill"` arm and a default.
- **`EffectSystem._effect_cells`** reads `ctx.target` as a `Vector2i` (§4.2).
- **`BattlefieldView.aim_cells`** is the ground picker (§4.2).
- **`GameLoop2`**: `apply_tile`, `apply_enemy_status`, `_damage_enemy`,
  `damage_player`, `column_cells`, `target_cells`, `_grant_shield_for`.
- **`Data.roll_item_rarity`** — the shared ladder, with Luck already folded in.

### 9.2 The work

| Area | Change |
|---|---|
| `scripts/resources/PotionData.gd` | New resource (§7.1). Needs an editor rescan before the suite can see the `class_name` — `godot --headless --editor --quit`. |
| `tools/generate_potion2_tres.py` | New generator → `data/potions2.0/`. Parses both effect columns with the scroll parser's clause loop plus `area=` / `games=`. |
| `scripts/autoload/PotionSystem.gd` | New autoload (**#23**) — the colour deal, identification, art, `quaff_potion`, `throw_potion`. Registered in `project.godot` (`;` comments, never `#`). |
| `scripts/autoload/Data.gd` | `_load_dir("res://data/potions2.0/", _potions)`, `get_potion` / `all_potions` / `roll_potion`. |
| `scripts/autoload/GameState.gd` | The three-way loot roll; `_add_random_potion_loot`; `add_potion_loot` for DevTools; `loot_potions()`; the timed-status layer (§5.3). |
| `scripts/autoload/LootSystem.gd` | A `"potion"` arm in each dispatch, plus `can_throw(entry)` — the only kind that answers yes. |
| `scripts/autoload/GameLoop2.gd` | `area_cells(cell, area)`; `_expire_timed_statuses()` in `beat_game`; a `grant_health` / `grant_shield` path onto an entry. |
| `scripts/autoload/EffectSystem.gd` | `gain_potion`; `deal_damage`; `gain_level`; `games=` on `apply_status`. |
| `scripts/autoload/SaveSystem.gd` | Serialize the timed layer. The two potion fields are **already saved**. |
| `scripts/redesign2/LootUseModal.gd` | A second button. **Quaff** and **Throw** side by side on a potion, one Use on everything else; the throw arms the picker, hides the modal, and resumes on the click. |
| `scripts/redesign2/BattlefieldView.gd` | Generalise `aim_cells` past `ItemData` (§4.2); a throw-armed state beside `bomb_mode` / `aiming_item`. |
| `scripts/redesign2/LootInfoCard.gd`, `LootGrid.gd`, `LootDropModal.gd`, `LootWindow.gd`, `LootDiscoveries.gd` | Potions are loot: they draw, drag, bin, offer and get listed under *Known this run* with no per-kind branching beyond the glyph. `LootSystem.glyph` needs a third one — 🧪. |
| `scripts/autoload/DevTools.gd` | Grant a named potion, identified or not, like `add_scroll_loot`. |
| `test/test_potion_system.gd` | New suite (§9.3). |
| `README.md` | The autoload table (22 → 23), the `data/` and `images2.0/` trees, the loot paragraphs. |
| `CHANGELOG.md` | The narrative entry. |

### 9.3 Tests

`test_pill_system.gd` and `test_scroll_system2.gd` are the templates. The ones that
are actually about potions rather than about loot:

- the run's deal binds 15 distinct colours and leaves 22 unbound; a reloaded run
  keeps its alphabet;
- **the colour list matches the folder in both directions** (§6.1);
- quaffing and throwing the same potion each identify it, and identification is one
  fact — throwing one teaches you what quaffing it would do;
- a fizzled throw (empty ground, `none` throw) still identifies;
- `area=3x3` clips at the board's edge and `area=row` covers `grid_cols()` cells on
  a grown board, not 4;
- a thrown potion does not fire `bomb_used` and is not widened by Brimstone (§4.4);
- a boss takes no damage from a thrown Ampoule;
- a timed status is gone after one `beat_game` and a permanent one of the same id
  underneath it is not (§5.3);
- Sacred Bark doubles a Negative potion's damage as well as a Positive one's
  shields;
- an echoed potion lands on the same cell as the throw that fired it.

---

## 10. The scroll deltas in the same sheet pass

`scrolls2.0` changed under the generator, and the changes matter to potions because
both kinds go through the same rarity roller and the same identification plumbing.

| Delta | What is true now | What to do |
|---|---|---|
| **`Rarity` column added** | `ScrollData.rarity` exists and `Data.roll_scroll` weights by `rarity_index()` — but `generate_scroll2_tres.py` never writes the field, so **every scroll is Common and the weighting is inert**. | Write `rarity` from the column. One line in the generator, then regenerate. This is the fix that makes the roller do what its comment says. |
| **`Scroll of Remove Curse` (new row)** | Rare, Positive, blank Effect. Curses are shelved (§5), so there is nothing for it to remove. | Generate it with an empty `effect` (it parses to `[]` already) and let it read as authored-but-inert, **or** hold the row out of the generator until curses come back. Recommendation: hold it out — a Rare bucket that is one scroll doing nothing is a worse roll than a Rare bucket that is empty and falls back to the pool. |
| **Amnesia widened** | Prose now says *"Forget 1 random **Identified Loot**"*, but the Effect cell still says `forget scroll 1`, and `ScrollSystem._forget_scrolls` only knows scrolls. | Make `forget`'s `kind` mean it: `forget loot 1` unidentifies across scrolls, pills **and potions**. The pills' horse Amnesia already authors `forget loot all`, so the verb was always meant to be kind-blind — it just has no implementation for the wide case. |
| **`Description` column added** | Authored prose the generator does not read; `LootSystem._scroll_line` reassembles a description from the ops instead. | Carry it onto `ScrollData.description` and prefer it where it is non-empty, falling back to the assembled line. Authored words beat generated ones, and potions should do this from day one rather than growing the same gap. |
| **Identify's `Notes`: "+25% find rate"** | No such concept exists. | A `find_weight` multiplier on the resource, applied inside the bucket after the rarity roll. Small, and it wants to exist on `PotionData` too — but it is the one delta here that is a **new mechanic**, so it can land after the rest. |

None of this is potion work, but items 1, 3 and 4 are things potions would otherwise
copy in their broken state.

---

## 11. Build order

1. **Statuses first** (§5.2) — clear `EnemyOnly` on Strength / Dexterity / Speed and
   give the player side something to read. Without this, nine of fifteen potions
   have no effect.
2. **The timed layer** (§5.3) + the `beat_game` expiry, with tests. Still no potions.
3. **The scroll deltas** (§10, items 1–4) — the generator fix and the widened
   `forget`, so potions are born into a working roller.
4. **Data**: `PotionData`, the generator, both Effect columns authored (§7.3),
   `Data` wiring, the editor rescan.
5. **`PotionSystem`**: the deal, identification, art, `quaff_potion`. Quaff only.
   At this point a potion is a pill with better art and it is fully playable.
6. **The throw**: `area_cells`, the three new ops, the picker generalisation, the
   second button.
7. **The income switch** to a three-way split (§8) — last, so the run is not paying
   out a kind that is only half built.
8. **README + CHANGELOG**, and `gain_potion` for whoever authors the first potion
   relic.

Steps 1–2 are the risky ones; 4–5 are mostly transcription from `PillSystem`.

---

## 12. Open questions

- **Fire Potion's tile clause.** *"Apply the Fire tile, Deal 1 Damage, and Apply +3
  Burn to everything in a 3×3 area centered on this tile"* — does the **fire tile**
  cover the whole 3×3, or only the aimed cell? §7.3 authors it as the centre cell
  only, because nine burning squares out of a 4×4 board's sixteen, for three games,
  off a **Common** bottle, is board-defining. Widening it is a one-token change
  (`area=3x3`) if that is what was meant.
- **Fruit Juice on a body.** "+2 Max Health" thrown at an enemy: §7.3 reads it as
  `grant_health`, since board entries carry `health` and not a max. A body with 3
  Health takes three bombs — which is the effect either way, and worth confirming
  is the intended punishment for throwing a Rare good potion at something.
- **Should a throw be spendable with an empty board?** §4.5 says yes (it is ground,
  and Fire ahead of the stack is the point). Worth checking that a throw during the
  **report step** is also fine — spending is allowed mid-report, only *moving* the
  pack is not (§4.3).
- **Does the pack cap want to move?** Three kinds sharing nine slots means a player
  who wants one of each carries fewer of each. That may be exactly right, and may be
  worth a re-look once potions are in a real run.
- **Lucky Foot and Sacred Bark's reach** (§8) — pills-only and everything,
  respectively, for now.
