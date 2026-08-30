# Potions — design & implementation plan

Companion to [`games-first-redesign.md`](games-first-redesign.md) (the canonical
spec). That doc's §4.1 is scrolls and its §4.3 is pills; this one is the **third
loot consumable**, and it is written the same way the pill work was: what a potion
is and why, then the code it lands in, then the order to build it.

Content source: the **`potions2.0`** sheet of `tools/Roguelikes.xlsx` (15 rows) and
the art in `images2.0/potions_identified/` (9 bottles) +
`images2.0/potions_unidentified/` (37 coloured vials).

Status: **decisions locked; steps 1-4 of §11 are BUILT.** The timed-status
layer, its expiry, its wording and the shield claw-back shipped (§5, and the
CHANGELOG entry that opens with *"Statuses can be borrowed"*), with
`test/test_timed_statuses.gd` covering them — 26 tests. The scroll deltas (§10,
§10.1) followed: the generator's rarity fix, `description`, `find_weight`, the
kind-blind `forget`, `identify_loot` and `remove_curse` with its picker. Then the
data: `PotionData`, `tools/generate_potion2_tres.py`, **§7.3's 30 effect cells
written into the sheet** (decision #30) and `Data.roll_potion`, so all 15 potions
now load as content. Then `PotionSystem` (autoload #23) and the QUAFF verb: the
vial deal, identification, art, `quaff_potion`, and the potion arm on every
kind-blind surface. **The THROW is the whole of what is left** — step 5, plus the
three smaller steps after it. §9.1 is the plumbing that already exists for them.

Picking this up in a fresh session: [`potions-handoff.md`](potions-handoff.md) has
the branch, the state of the suite, the next step in order, and the repo-specific
traps worth knowing before touching any of it.

*A bare §x.y is a section of this document. The spec's own §4.1 (scrolls) and §4.3
(pills) collide with the numbering here, so those two are always written **spec
§4.1** / **spec §4.3**; every other spec reference (§7.4, §13, §17, …) has no twin
here and is left plain.*

---

## 1. Decisions locked

Thirty forks were settled before any code, in the same discovery-pass style as the
[implementation plan](games-first-redesign-implementation-plan.md#1-decisions-locked-in-discovery):

| # | Decision | Choice |
|---|---|---|
| 1 | **What a quaffed buff IS** | **The status's own player side, with a clock.** Strength / Dexterity / Speed already hand their holder a standing goal (§13); a potion grants that goal for one game. No new combat side, no `EnemyOnly` changes (§5.2). |
| 2 | **What a throw is aimed at** | **A cell.** Red Candle's ground picker (`BattlefieldView.aim_cells`), every square legal, empty ground included — areas centre on the cell (§4.2). |
| 3 | **Bottle art** | **All 37 colours, both sets mixed.** 15 potions bound per run, 22 sitting out (§6). |
| 4 | **Loot income** | **Three-way split.** Beating a game pays 1 piece: ⅓ scroll, ⅓ pill, ⅓ potion (§8). |
| 5 | **Throwing a Positive potion** | **It helps them.** A thrown Block Potion shields the body it lands on. That is what makes quaff-or-throw a second gamble on an unknown bottle (§2). |
| 6 | **How long "until the end of the next combat" is** | **Until the next game is resolved**, whichever game that is — it dies in `GameLoop2.beat_game` beside the tiles (§5.1). |
| 7 | **Potion of Raise Level** | **A free level-up**: the character's normal reward path, without the condition being met (§7.3). |
| 8 | **Scroll deltas** | **Same doc, same sheet pass** — the rarity column, Amnesia's widened forget and the rest are load-bearing for potions (§10). |
| 9 | **How a one-game goal scales** | **X as authored.** A +5 potion asks for five of the thing in one game and pays for five: a longer shot at a bigger prize, not a strictly better bottle (§5.2). |
| 10 | **A clause with a clock** | **Reads that way.** A thrown buff carries the same one-game clock on the body, and every line that quotes the goal says so out loud (§5.3). |
| 11 | **Fire Potion's throw** | **The whole 3×3 catches fire** — tile, damage and Burn all cover the area (§7.3). |
| 12 | **Healing thrown at a body** | **Max Health raises its maximum; healing heals it if it can be healed.** A full-health body is a wasted bottle (§4.6). |
| 13 | **Scroll of Identify** | **Widens to any loot** — scroll, pill or potion — symmetric with Amnesia (§10). |
| 14 | **Other potion sources** | **None yet.** The ⅓ loot payout is the only tap; shops, drops and boss rewards are later calls (§8). |
| 15 | **The pack cap** | **Stays 9**, but `LOOT_CAPACITY` becomes a *function* so a future relic can raise it (§8.1). |
| 16 | **What the run pays for a throw** | Same as a quaff: one piece of loot, echoed and remembered identically. A throw is not a bomb and spends no charge (§4.4). |
| 17 | **Landmines and damage** | **A mine goes off when it is stood on OR when it takes damage** — a thrown potion, a bomb blast, anything. A third trigger on the unit sheet, and a change to §17 rather than to potions (§4.7). |
| 18 | **What an unknown bottle is called** | **By its colour** — "Swirly Potion", "Ruby Potion". Pills never spell a colour out; potions do, because 37 of them cannot be told apart in text otherwise (§6.4). |
| 19 | **Sacred Bark's reach on a potion** | **Values AND geometry** — damage, healing, status stacks, shields, *and* the area: a 3×3 becomes 5×5, a line becomes the cross (§8.2). |
| 20 | **`find_weight`** | **A weight inside the rarity bucket.** Identify was 1.25× as likely as the other Commons; rarity keeps meaning what it means (§10). **Superseded for Identify only:** it now authors a weight of **0** (never drawn from the pool) and arrives as a flat **10% of every loot drop**, taken off the top by `GameState.roll_loot_entry` — see games-first-redesign §4.1. The field and the weighted pick stay exactly as designed for every other scroll. |
| 21 | **Scroll of Remove Curse** | **Ships with a real effect.** Curse GOALS are live (three authored, events and the Calling Bell hand them out) — `remove_curse choose 1` retires one (§10.1). |
| 22 | **What identifying teaches** | **Both sides at once.** Identification is of the TYPE: drink the swirly one and you know what throwing it does too (§6.5). |
| 23 | **A timed Dexterity's shields** | **Unspent shields expire with it.** A departure from §13.4's "handed out, not recomputed", and the one place a clock reaches back into a pool (§5.5). |
| 24 | **The mine's damage trigger** | **A third trigger word**, `damaged:`, on `units2.0` — which makes it a §17.1 spec edit (§4.7). |
| 25 | **Stacking** | **One piece, one slot.** Two Fire Potions cost two slots, like everything else in the pack (§8.1). |
| 26 | **A wide body under a wide throw** | **Once per body.** A 3×3 clause dedupes to instances like a bomb blast; the fire tile it leaves still bills per cell on later turns (§4.3). |
| 27 | **Confirming a throw** | **No confirmation.** Arming a picker and clicking a square are two deliberate acts already (§4.2). |
| 28 | **Potion of Uselessness** | **Uncommon**, not Common — the joke, met less often. Sheet edit made (§3). |
| 29 | **The six potions with no art** | **The fallback IS the design.** An identified potion with no `File` keeps showing its run colour, permanently (§6.3). |
| 30 | **Who fills the 30 empty effect cells** | **The next build session**, through `_xlsx_surgery` from §7.3 — so the workbook is not hand-edited in the meantime (it is a binary blob; concurrent edits do not merge). **Done**, in `tools/_potions2_effect_cells.py`. |

---

## 2. What a potion is (and why it is not a third pill)

The run already has two consumables that are one effect behind a mask:

- a **scroll** hides its *name* behind one shared Unidentified art, and reading it
  is the gamble (spec §4.1);
- a **pill** hides its *name* behind a colour dealt fresh each run, and swallowing
  it is the gamble (spec §4.3).

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
| Fysh Oil | Uncommon | Pos | +1 Strength and +1 Dexterity for a game | the same, to what is there | ✅ |
| Potion of Uselessness | Uncommon | Neutral | Nothing | Nothing | ✖ |
| Potion of Haste Self | Uncommon | Pos | +2 Speed for a game | +2 Speed for a game | ✖ |
| Fruit Juice | Rare | Pos | +2 Max Health | +2 Max Health to what is there | ✅ |
| Potion of Extra Healing | Rare | Pos | +5 Health | +5 Health to what is there | ✖ |
| Potion of Raise Level | Rare | Pos | +1 Level | — (N/A) | ✖ |

Four things the table says out loud:

- **9 Common / 3 Uncommon / 3 Rare** sits cleanly on the shared 75/20/5 ladder
  (`Data.roll_rarity_step`), so the roller needs no potion-specific weighting.
  Uselessness moved up a rung (decision #28): at one of ten Commons it was ~7.5% of
  potion drops and, once potions take their third of the payout, ~2.5% of **all**
  loot spent on a bottle that does nothing in either direction. The joke is worth
  keeping and worth meeting less often. The edit is made — through
  `tools/_potions2_uselessness_uncommon.py`, which goes via `_xlsx_surgery` because
  an openpyxl round-trip of this workbook silently drops its seven charts.
- **The throw is weaker per body and wider per square.** Dexterity and Strength
  Potions give the drinker +2 and a body +1; the Ampoule takes 3 off you and gives
  1 to a whole row. Area is what you are paying the difference for.
- **Slay the Spire's names came with Slay the Spire's meanings.** "Speed Potion" is
  +5 *Dexterity*, not Speed — that is what it does in its source game. `Potion of
  Haste Self` is the one that is actually Speed.
- **Six rows have no `File`, and are not waiting for one.** They wear their run
  colour permanently (§6.3, decision #29). The two rows whose throw is `N/A` —
  Raise Level, and Uselessness by authorship — need the fizzle rule of §4.5.

---

## 4. The two verbs

### 4.1 Quaff

The existing spend path, unchanged: the Use button in the loot window, on the info
card, or on the drop modal's offer, going through `LootSystem.use_loot` /
`use_entry` so the piece is consumed, echoed and remembered exactly like a pill
(spec §4.3). `PotionSystem.quaff_potion` is the resolver, with `ScrollSystem.read_scroll`
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

**And it does not ask** (decision #27). Arming the picker and clicking a square are
two deliberate acts, and a dialog between them would sit in front of the fastest
board verb in the game. The bin asks before it destroys a carried piece (spec §4.3)
because a drag can *end* somewhere by accident; a throw cannot land anywhere the
player did not click. Throwing an identified Fruit Juice at a boss is a mistake the
run log will describe, not one the UI will prevent.

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

**A body in the area is hit ONCE, however many of the squares it covers**
(decision #26). A 2×2 standing under a 3×3 throw takes 1 damage and +3 Burn, not 4
and 12. That follows the bomb rather than the tile: `_blast_instances` resolves a
blast's cells to *instances* and dedupes, while a fire tile bills per cell every
turn (§17.2) — and the difference between them is the difference between a thing
that happens once and ground that keeps happening. A thrown potion is the first
kind. Wide bodies still pay for being wide, just on the clock rather than on impact:
the Fire tile the bottle leaves behind bills all four of that 2×2's cells, every
turn, for three games.

So the area resolves twice, and the two passes are not the same list: **cells** for
the tile clauses, **deduped instances** for everything aimed at a body.

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
thrown potion is **destroyed, not defeated** (no drop, no gold — spec §4), and a **boss
takes no damage** from one, the same shrug it gives a bomb (§7.1). A Rare bottle
that one-shot a boss's health would make §7.1 a suggestion.

### 4.5 Fizzles, not refusals

The rule loot already lives by (spec §4.3): a Use button that will not press teaches the
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

### 4.6 Healing a body

Decision #12. Board entries carry `health` and nothing else — how much a body
*started* with is answered by `GameLoop2.effective_health(enemy)`, recomputed
rather than stored. Two of the three healing potions need more than that, so an
entry gains a **`max_health`**, seeded from `effective_health` the moment the body
spawns and serialized beside `health` and `shield`:

- **`grant_max_health`** (Fruit Juice) raises the ceiling *and* the current pool by
  the same amount, so a full-health body stays full and a damaged one keeps the
  damage it has taken. A 1-Health goblin becomes a 3-Health goblin: three bombs,
  not one. That is the price of a misthrown Rare bottle.
- **`grant_health`** (Potion of Healing, Extra Healing) heals **up to that
  ceiling** and no further. Thrown at an undamaged body it is a wasted potion, and
  the outcome screen says so — *"It is already whole."* Thrown at the boss you have
  been chipping at for three games, it is a disaster.

`max_health` is worth having anyway: it is the number an enemy health bar has been
drawing without ever being told, and a bomb chipping a 3-Health body currently has
nothing to draw a fraction against.

### 4.7 What a throw sets off

Decision #17, and it is properly a §17 change rather than a potion one: **a Landmine
detonates when it takes damage, not only when it is stood on.** Today `units2.0`
authors it as `enemy_enters: detonate` and that is the only way one ever goes off
(bar the fire interaction). It gains a second trigger — a mine caught in a thrown
Ampoule's row goes up, and so does one caught in a bomb blast, or in anything else
that ever damages ground.

This is the right reading of the unit's own sheet row: it has **Health 1**, and a
thing with a Health that nothing can damage is carrying a number for decoration.

Three consequences to build deliberately:

- **The blast is the MINE's, not the potion's.** A mine going off runs
  `GameLoop2._explode`, which is where Brimstone widens, Sticky stuns, Hot Bombs
  lays fire and `bomb_used` pays Blood Bombs. So a potion that sets one off *does*
  reach the pack's bomb upgrades — through the mine, which is exactly what a proxy
  bomb is for (§17.2). What stays un-upgraded is the potion's **own** `deal_damage`:
  Brimstone does not widen a bottle.
- **Chains stay finite** for the reason they already do: every detonation spends the
  unit that caused it, and `MAX_CHAIN` is the belt to that brace. A Fire Potion over
  a 3×3 of mines is a big, terminating chain.
- **Order matters.** Resolve the potion's damage on bodies first, then detonate
  whatever mines the area covered — the same ordering `_explode` already uses when
  it lays Hot Bombs' fire after its damage, so a body killed by the bottle is gone
  before the mine's blast looks for targets.

**It is authored as a third trigger word** (decision #24): `damaged: detonate` on the
unit's Effect column, beside the two that exist. That makes it a **§17.1 spec edit**,
because that section says the pair is the whole vocabulary on purpose — and the
reason to spend the edit rather than infer the behaviour from the `Health` column is
that the next unit will want to react to damage *differently*. A barrel that simply
breaks, a totem that fires something off when shot: those are `damaged:` clauses that
are not `detonate`, and a rule hardcoded to "0 Health runs your detonate" cannot
express either. The trigger says what happens; the Health column says how much it
takes. `generate_unit_tres.py` imports the tile generator's parsers, so the word is
added once and both sheets can speak it.

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

### 5.2 A quaffed buff is the status's OWN player side, borrowed for a game

Decision #1, and it is the decision that makes this whole feature small. A status
already has a player side (§13): it hands its holder a **standing goal**. Dexterity
on you is *"if X bosses — or all the game's bosses, whichever is fewer — were
beaten without getting hit, gain a chest reward"*;
Strength is *"if the difficulty is increased X times, gain a chest reward and +1
Bash"*; Speed is *"if beaten in ⟨time⟩ or less, gain a chest reward and +1 Dash"*.
**A potion grants that goal for one game.** The bottle contributes the clock, not a
new meaning.

That kills the prerequisite this doc originally carried. `EnemyOnly` stays as it is,
§13.4 does not move, no status grows a player-facing combat number, and no call site
has to learn to read one. What the potions need is the clock and nothing else.

It also changes what a buff potion *is*, and the change is for the better: a quaffed
buff is an **opportunity, not a stat**. Flex Potion is not "you hit harder"; it is
one game in which raising the difficulty five times pays a Huge chest and a Bash.
You drink it because of the game you are about to take.

**X is as authored** (decision #9). A +5 potion asks for five of the thing inside
one game and pays for five of it; a +2 asks for two and pays for two. So Speed
Potion (+5 Dexterity) is not a bigger Dexterity Potion (+2) — it is a longer shot at
a bigger prize, and on most games it is a ticket that does not come in. That is
accepted deliberately: both are known quantities the moment the bottle is
identified, and choosing which game to spend the long shot on is the play. It does
mean the four rows that move real numbers — Block, Fruit Juice, and the two healing
potions — are the roster's reliable half, and the status rows are its swingy half.

**Not everything a potion applies is timed.** Fire Potion's `+3 Burn` on the drinker
carries **no** clock: Burn is a debt (§13), and a debt that expires by itself is a
suggestion. Only the rows whose prose says *"until the end of the next combat"* are
authored with `games=1`.

### 5.3 A clause with a clock has to read that way

Decision #10. Thrown, a buff lands on a **body**, where the same status is a
`clause` — it ANDs onto that enemy's goal and tightens it. It carries the same
one-game clock, and **every line that quotes the goal says so**:

- `GameLoop2.goal_text_for(entry)` is THE goal line (§13.3) — the checklist, the
  enemy card, the target pickers and the headless `PlaySession2` driver all read it.
  A timed clause renders inline: *"…and the difficulty must be increased 3 times
  (this game only)"*.
- The player's claimable rows come from `GameState.status_objectives()`; a timed one
  reads the same way on the report checklist.
- The pips both sides draw go through `StatusData.tooltip_for`, the one place a
  status's hover text is built, so a `⏱ this game` line there covers the board's
  hero, the enemy box and the HUD chip at once — the shape a tile's `⏱ 2 games left`
  already uses (§17.5).

A clause the player cannot tell is temporary is a clause they will plan a route
around and be wrong about, so this is not decoration: it is the difference between
a thrown buff being a mistake and being a trap.

### 5.4 Where the clock lives

`GameState.player_statuses` is `id → stacks` and a board entry's `statuses` dict is
the same shape. A stack count has no room for an expiry, so the clock rides beside
it as a **timed layer** rather than inside it:

```gdscript
GameState.timed_statuses: Array   # [{id, stacks, games, shield, instance}, …]
entry["timed_statuses"]: Array    # the same, per body
```

summed into the existing reads (`status_stacks`, `status_clauses`,
`GameLoop2.enemy_combat`) rather than stored in them. The
alternative — a parallel `{id: games_left}` dict — cannot describe a status that is
half permanent and half borrowed, which is exactly what a run holding a permanent
Dexterity and then drinking a Speed Potion has. A layer expires **whole**: two
potions drunk before one game are two rows, both dying at the same `beat_game`.

It saves as one more array beside `player_statuses` in `SaveSystem`, and inside
`GameLoop2.serialize()` for the board's copy — the same place `statuses` and
`shield` already live.

One ordering rule while we are here: a status that decays on completion (§13.1)
sheds its stack from the **timed** row first, since that row is leaving anyway.
Nothing in the potion roster applies a decaying status, so this costs nothing today
and stops the first one that does from quietly eating a permanent stack. A decay
that DOES name a row — a claimed checklist row, below — sheds from that row instead
(`GameState.remove_status_instance`), because "this objective paid out" is a fact
about one row and not about the status.

#### The checklist is one row per instance; the HUD is one chip

`status_objectives()` is the one read that does **not** sum the layers. Every
temporary application is its own instance — Reptile Trinket fires on each potion,
so three potions are three borrowed Strengths, each with its own clock — and each
gets its own row on the checklist, beside a row for the stacks the run **owns**.
They are separate offers with separate deadlines and separate payouts, and a merged
row could only ever quote one of them. The same split runs through the bill: a
`demand` held permanently and a borrowed one on top of it are two obligations, each
missed on its own.

Every such row carries a `key` — the bare status id for the permanent bucket,
`"<id>#<instance>"` for a borrowed one — and that key is what the tick box, the
`answered_this_game` record, the report's `claims.status_goals` and
`claim_player_objective` all pass around. The permanent bucket keeping the bare id
is what lets a save or a report written before instances existed still land.

**The HUD is deliberately the other way round.** `status_list()` still merges
everything into one icon and one number, because what a stack *does* is felt as a
total: a permanent Strength 1 under a borrowed Strength 3 hits like 4, so it reads
like 4. Only the goals split.

### 5.5 A timed Dexterity takes its shields back

Decision #23, and it is the one rule in this doc that knowingly departs from the
spec. §13.4 is explicit: **shields are a pool the status hands out, not a reading of
the stack count.** Dexterity 2 grants two shield points, each stops one whole hit
and is gone, and the body keeps its two Dexterity stacks afterwards with no shield
left — which is why `shield` is saved on the board entry beside `health` rather than
recomputed on load.

A thrown Speed Potion is +5 Dexterity, so under that rule alone it hands a body
**five shields**: five hits absorbed, from a Common bottle, permanently. So the clock
reaches into the pool: **when a timed status expires, it takes back what it granted
and has not been spent.**

The bookkeeping is one field on the timed row rather than a new system:

```gdscript
{"id": &"dexterity", "stacks": 5, "games": 1, "granted_shield": 5}
```

and on expiry the body's pool drops by `min(granted_shield, current shield)`. That
`min` is the whole rule, and it is what makes it honest when the shields came from
more than one place: five granted and three already eaten means two come off, not
five, and a pool refilled by something else in the meantime is not raided to pay a
debt the potion no longer has.

**Permanent Dexterity is untouched.** A status applied by an item, a location or a
scroll grants its shields exactly as §13.4 says and never takes them back — the
claw-back belongs to the clock, not to the status, which is what keeps this a potion
rule rather than a rewrite of shields.

---

## 6. Identification — 37 bottles, 15 potions, 22 sitting out

The pill pattern (spec §4.3) transplanted, and it is a better fit here than it was there:
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
constant** (spec §4.3). Potions want the opposite end of the same function: a *cap*, so
that a 256px identified bottle and a 16px vial both land in the cell's band without
one of them being a postage stamp. Route potion art through the same
`art_tex` / `art_box` pair; do not let a fourth surface pass a raw constant to
`UITheme.crisp_tex`.

### 6.3 Identified art, and the six with none

`File` → `res://images2.0/potions_identified/<File>.png`, resolved on identification.
A potion with a blank `File` — or one whose file does not resolve — **falls back to
the bottle it has been wearing all run**, which is the scroll rule (spec §4.1) pointed at
the thing potions have and scrolls do not. Never a null texture, and never a fifth
mystery art invented for the artless six.

**That fallback is the design, not scaffolding** (decision #29). Six rows — the two
healings, Raise Level, Haste Self, Self-Mutilation and Uselessness — have no `File`
and are not waiting for one. An identified potion with no art of its own keeps
showing the bottle it wore all run, which is honest: the colour is a real fact about
that potion in that run, and it is the fact the player learned it by. So this is not
an art TODO and the doc does not list it as a gap.

### 6.4 An unknown bottle names its colour

Decision #18, and it is the one place potions deliberately *depart* from pills. A
pill's mystery is a capsule the run never spells out: the "Known this run" fold
names colours by art alone, because a game that wrote "green is Bad Trip" would be
handing back deductions the three spare capsules exist to prevent (spec §4.3).

Potions go the other way. `PotionSystem.display_name` answers **"Swirly Potion"**,
"Ruby Potion", "Effervescent Potion" — the colour off the art file's own name —
and only once identified does it become "Potion of Extra Healing". Three reasons
the pills' rule does not transfer:

- **Thirty-seven vials cannot be told apart in text.** Two NetHack bottles at 16px
  in a 48px cell are a colour swatch and little else; a run log reading "you drank
  an unidentified potion" four times has recorded nothing at all.
- **It costs no deduction.** Naming a colour is not naming what is *in* it. The 22
  sitting out do the same work they do for pills, and they do it whether or not the
  player can say "amber" out loud.
- **It is the genre's own voice.** *You drink the swirly potion.* The colours are
  NetHack's and Shattered Pixel Dungeon's exact adjectives, and they are better
  writing than anything a mask would put in their place.

So the file name is content: `Swirly_NetHack.png` → colour "Swirly", source
"NetHack". The generator's job on `PotionSystem.COLORS` is to carry both halves,
since the source game is worth showing on a card the same way every other row in
this project credits where it came from.

### 6.5 One bottle, one fact

Decision #22: **identification is of the TYPE, and it covers both sides.** Drink an
unknown swirly bottle, find out it was Fire Potion, and you now know what *throwing*
a swirly one does as well — its card shows quaff and throw together from then on,
and every future swirly bottle is a known quantity in both directions.

This is the scroll's rule (identify a type, know the type) rather than a new one,
and it is the version that keeps the *interesting* decision in front of the player.
The alternative — learn only the side you used — is thirty facts instead of fifteen,
and it turns the quaff-or-throw choice into a research task: you would throw bottles
you had already drunk purely to fill in the other half of the page. The choice
should be *which of these two things do I want right now*, and that only works once
both halves are on the card.

It also means the pill's rule about doses carries over cleanly: a pill is one colour
learned from either dose (spec §4.3), and a potion is one colour learned from either
verb.

---

## 7. The sheet and the effect DSL

### 7.1 Schema

    potions2.0: Name | Rarity | Preference | On Player | On Player Effect |
                On Tile | On Tile Effect | Reference | File

Prose column, machine column, in pairs — the `statuses2.0` shape (§13.1). Both
machine columns were empty for all 15 rows; §7.3 was the proposed first pass and
is now what the sheet says, written by `tools/_potions2_effect_cells.py`.

`PotionData` (`scripts/resources/PotionData.gd`) carries
`id, display_name, rarity, preference, reference, file, quaff: Array, throw: Array`
plus `rarity_index()` and `art_file()`, both copied from `ScrollData`. **As built
it also carries the two PROSE columns** — `quaff_text` and `throw_text` — because
an identified potion shows both halves at once (§6.5) and the sheet's words beat
words assembled from ops, which is the lesson §10 learned on `ScrollData`. It has
`ops(verb)` / `line(verb)` in place of the pill's `ops(horse)` / `line(horse)`, and
`has_throw()` for §4.5's button rule. **No `find_weight`**: `potions2.0` has no
Notes column to author one in, and a field nothing can write is the mistake
`rarity` was making until §10 caught it.
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
| `gain_stat bonus_shields <n>` | pills | the pool that does not expire (spec §4.3) |
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
| **`grant_health <n> [area=…]`** | **new** — heals a body, capped at its `max_health` (§4.6) |
| **`grant_max_health <n> [area=…]`** | **new** — raises a body's ceiling and its current pool together (§4.6) |
| `none` | the bottle smashes (§4.5) |

Four new ops and one new token. Everything else is vocabulary the sheet already
speaks, which is the bar a new consumable should have to clear.

### 7.3 A proposed first pass at all 30 cells

| Potion | `On Player Effect` | `On Tile Effect` |
|---|---|---|
| Fire Potion | `take_damage 3; apply_status burn 3 player` | `apply_tile fire area=3x3; deal_damage 1 area=3x3; apply_status burn 3 area=3x3` |
| Block Potion | `gain_stat bonus_shields 2` | `grant_shield 2 area=cell` |
| Speed Potion | `apply_status dexterity 5 player games=1` | `apply_status dexterity 5 area=cell games=1` |
| Flex Potion | `apply_status strength 5 player games=1` | `apply_status strength 5 area=cell games=1` |
| Dexterity Potion | `apply_status dexterity 2 player games=1` | `apply_status dexterity 1 area=cell games=1` |
| Strength Potion | `apply_status strength 2 player games=1` | `apply_status strength 1 area=cell games=1` |
| Explosive Ampoule | `take_damage 3` | `deal_damage 1 area=row` |
| Fysh Oil | `apply_status strength 1 player games=1; apply_status dexterity 1 player games=1` | `apply_status strength 1 area=cell games=1; apply_status dexterity 1 area=cell games=1` |
| Fruit Juice | `gain_max_hp 2` | `grant_max_health 2 area=cell` |
| Potion of Healing | `gain_hp 2` | `grant_health 2 area=cell` |
| Potion of Extra Healing | `gain_hp 5` | `grant_health 5 area=cell` |
| Potion of Haste Self | `apply_status speed 2 player games=1` | `apply_status speed 2 area=cell games=1` |
| Potion of Raise Level | `gain_level 1` | `none` |
| Potion of Self-Mutilation | `take_damage 3` | `deal_damage 3 area=cell` |
| Potion of Uselessness | `none` | `none` |

**Fire Potion covers the whole 3×3 with all three clauses** (decision #11): nine
squares of burning ground, 1 damage and +3 Burn on everything standing in them. On
a 4×4 board that is nine of sixteen cells alight for three games, which makes a
Common bottle the most board-changing thing in the loot pool — deliberately. It is
the piece the run throws at a packed front line, and it is also 3 damage and 3 Burn
on **you** if you drink it not knowing what it is. That asymmetry is the whole
argument for the kind (§2), stated as loudly as the roster can state it.

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
exist, and it doubles the **Negative** rows too (spec §4.1's rule, and the reason the
Bark is a decision). Echo Chamber replays potions like anything else, at the same
aimed cell (§4.2). **Lucky Foot stays pills-only**: its sheet cell is
`pills_positive` and its whole text is about pills. Whether it should widen is a
balance call for later, not a consequence of this work.

**No relic pays out a potion yet.** `EffectSystem` has `gain_scroll` / `gain_pill` /
`gain_loot`; add `gain_potion` alongside them so the sheet can author one the day
somebody wants to, and leave the roster alone in this pass.

**And that payout is the only tap** (decision #14). No shop shelf slot, no enemy
drop, no boss bonus — a kind that arrives from four directions at once is a kind
nobody can balance the first time. The ⅓ is a number that can be turned; four
sources are four numbers that have to be turned together.

### 8.1 The pack, and a cap that can move

Nine slots now hold three alphabets, and the squeeze is the point: a third kind
makes *"leave it"* a harder answer, which is what the cap is for (spec §4.3). **It stays
nine** (decision #15).

But `GameState.LOOT_CAPACITY` is a `const`, and a future relic that hands the run a
bigger bag would have to unpick every surface that reads it. So it becomes a
**function** in this pass — `GameState.loot_capacity()`, base 9 plus whatever the
inventory adds, the shape `GameLoop2.grid_cols()` already uses for the board — and
the two things that hardcode a 3×3 read from it:

- `LootGrid` derives its rows and columns from the capacity rather than from a
  literal 3 (a 12-slot pack is 4×3), and the empty slots stay part of the drawing,
  since "the grid is always the cap" is what makes the room left readable;
- `LootWindow`'s toggle turns red at *capacity*, not at 9.

**And a piece is a piece** (decision #25). Two Fire Potions are two slots, and two
bottles of the same unknown colour are two slots — no `×2` badges, no counts. The
cap is the pressure, and a stack is a quiet way of raising it for whichever run got
lucky with duplicates. It also keeps every surface that draws, drags, spends and
bins a slot addressing exactly one entry, which is what makes the drop modal's
offer-index tracking (spec §4.3) work at all.

**No relic ships with it.** This is the seam, not the feature — and the seam is
cheap now and expensive later, because the loot window is fitted to a 720p canvas
with about five pixels to spare (spec §4.3) and a fourth row is a fit test away from
failing. Whoever authors the bigger bag inherits that problem knowingly rather than
discovering it.

### 8.2 What Sacred Bark doubles

The Bark doubles **named fields per op**, never every integer in the dict — that is
`ScrollSystem.LOOT_SCALED_FIELDS`, and the reason it exists is that a Teleportation
scroll's `spread` is how far a landing may *vary*, and doubling that is not twice
the scroll, it is a worse one. Potions get their own table in the same shape, and
decision #19 puts **four** kinds of number in it:

| Op | Doubled |
|---|---|
| `take_damage`, `deal_damage` | `value` |
| `gain_hp`, `gain_max_hp`, `grant_health`, `grant_max_health` | `value` |
| `apply_status` | `value` (the stacks) |
| `gain_stat bonus_shields`, `grant_shield` | `value` |
| **every throw clause** | **`area`** — see the ladder below |
| `gain_level` | `value` |

**The area is the unusual one**, and it is unusual because a grid has no way to be
exactly twice as big. So the Bark widens by **one step of a shape ladder** rather
than by a multiplier:

| `area=` | Doubled |
|---|---|
| `cell` | `cell` — a radius of 0 doubles to 0 |
| `3x3` | `5x5` |
| `row` / `col` | the **cross** — that row *and* that column |
| `board` | `board` |

Two of those want saying out loud. **A bottle aimed at one square still hits one
square**, because the radius the potion authored is zero and twice nothing is
nothing — a Bark that turned every single-target throw into a nine-cell blast would
make the aiming pointless, which is not what doubling a potion should mean.
**A line becomes the cross** because that is the widening this game already has a
word for: it is exactly what Brimstone does to a bomb (spec §4), so a doubled
Explosive Ampoule reads as a shape the player has seen before.

Everything else about the Bark holds: it doubles the **Negative** rows too — a
Barked Fire Potion is 6 damage to the drinker — because a relic that only doubled
the upside would make drinking an unknown bottle a strictly better gamble than it
is, and that is the one thing an identification minigame cannot afford (spec §4.1).
Burn's `Max: 3` still caps on the way up, so the Barked Burn clause lands at 3.

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
  is one, from the old build). *Since resolved:* the signal was declared and
  emitted by nothing — `PotionSystem.notify_used` is now the choke point, hit once
  by `quaff_potion` and once by `throw_potion`, and Reptile Trinket is the 2.0 item
  on the other end of it.
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
| `scripts/autoload/GameState.gd` | `remove_curse_goal(index)` (§10.1); the three-way loot roll; `_add_random_potion_loot`; `add_potion_loot` for DevTools; `loot_potions()`; the timed-status layer (§5.4); `LOOT_CAPACITY` → `loot_capacity()` (§8.1). |
| `scripts/autoload/LootSystem.gd` | A `"potion"` arm in each dispatch, plus `can_throw(entry)` — the only kind that answers yes. |
| `scripts/autoload/GameLoop2.gd` | `area_cells(cell, area)`; `_expire_timed_statuses()` in `beat_game`, for the player and every body; `max_health` on an entry (§4.6) and the `grant_health` / `grant_max_health` / `grant_shield` paths onto one; the timed half of `goal_text_for` (§5.3). |
| `scripts/autoload/EffectSystem.gd` | `gain_potion`, and `games=` on `apply_status` — **both halves**: the handler alone is a verb the sheet can write and silently get nothing from, so `generate_item_tres.py` learned to parse them in the same pass. **`deal_damage` and `gain_level` were NOT added here**, deliberately: the potion path dispatches through `PotionSystem`'s own table, not this one, and an item-side `deal_damage` needs a target/area vocabulary on `items2.0` that nothing is asking for. Register them the day a sheet cell wants one. |
| `scripts/autoload/ScrollSystem.gd` | `identify_loot` (widened, §10); `forget` across all three kinds; `remove_curse` + its picker (§10.1); the potion half of `LOOT_SCALED_FIELDS`, area ladder included (§8.2). |
| `scripts/resources/StatusData.gd` | `tooltip_for` grows the `⏱ this game` line, so every pip that draws a timed status says so (§5.3). |
| `scripts/autoload/SaveSystem.gd` | Serialize the timed layer. The two potion fields are **already saved**. |
| `scripts/redesign2/LootUseModal.gd` | A second button. **Quaff** and **Throw** side by side on a potion, one Use on everything else; the throw arms the picker, hides the modal, and resumes on the click. |
| `scripts/redesign2/BattlefieldView.gd` | Generalise `aim_cells` past `ItemData` (§4.2); a throw-armed state beside `bomb_mode` / `aiming_item`. |
| `scripts/redesign2/LootInfoCard.gd`, `LootGrid.gd`, `LootDropModal.gd`, `LootWindow.gd`, `LootDiscoveries.gd` | Potions are loot: they draw, drag, bin, offer and get listed under *Known this run* with no per-kind branching beyond the glyph. `LootSystem.glyph` needs a third one — 🧪. **`LootDiscoveries` was the one that did need real work**, because it does not read a kind-blind list: it walks each catalog and asks that system whether the row is identified, so a third alphabet is a third walk, a third row and a second *unlearned* count. A pill's spares must stay unnamed and so must a potion's 22 vials — but a LEARNED bottle is listed by its own name, where a learned pill is listed by nothing but its capsule. |
| `scripts/ui/Collection.gd` | The Loot tab has two sub-tabs (`LOOT_SCROLLS` / `LOOT_PILLS`) and needs a third. Unlike pills — which draw one stand-in capsule so the catalog can't teach the run's alphabet — a potion's catalog cell shows its **identified** art where it has one, since that is not a per-run secret. |
| `scripts/autoload/DevTools.gd` | Grant a named potion, identified or not, like `add_scroll_loot`. |
| `tools/generate_unit_tres.py` + the `units2.0` sheet + spec §17.1 | The `damaged:` trigger and the Landmine's `damaged: detonate` (§4.7). §17.1's "the pair is the whole vocabulary" line becomes a trio. |
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
  underneath it is not (§5.4) — on the player and on a body;
- `goal_text_for` on a body carrying a timed clause contains the expiry wording, and
  the same clause without a clock does not (§5.3);
- a thrown healing potion on a full-health body heals nothing, and `grant_max_health`
  raises the ceiling and the pool together (§4.6);
- Sacred Bark doubles a Negative potion's damage as well as a Positive one's
  shields;
- an echoed potion lands on the same cell as the throw that fired it;
- a thrown `deal_damage` over a cell holding a Landmine detonates it, the mine's own
  blast carries the pack's bomb upgrades and the potion's damage does not, and a 3×3
  of mines chains to a stop (§4.7);
- an unidentified potion names its colour and an identified one does not (§6.4);
- Sacred Bark widens a 3×3 to 5×5 and a row to the cross, and leaves a `cell` alone
  (§8.2);
- `remove_curse` lifts the Calling Bell's permanent row, and fizzles with no curse
  held (§10.1);
- a timed Dexterity's unspent shields come off the body when it expires, shields it
  already spent do not come out of a later pool, and a PERMANENT Dexterity's shields
  survive (§5.5);
- quaffing an unknown potion identifies its throw side too (§6.5);
- a 2×2 body under a 3×3 throw takes the clause ONCE, and the fire tile left behind
  bills all four of its cells on the next turn (§4.3).

---

## 10. The scroll deltas in the same sheet pass

`scrolls2.0` changed under the generator, and the changes matter to potions because
both kinds go through the same rarity roller and the same identification plumbing.

> **BUILT** (§11 step 2). The table below is kept in the tense it was written in —
> "What is true now" describes the state this step found, not the state it left.
> All six rows are done; the CHANGELOG entry opening *"Every scroll in the game was
> Common"* is what actually landed, and where it and this table disagree, it is the
> one describing the build.

| Delta | What is true now | What to do |
|---|---|---|
| **`Rarity` column added** | `ScrollData.rarity` exists and `Data.roll_scroll` weights by `rarity_index()` — but `generate_scroll2_tres.py` never writes the field, so **every scroll is Common and the weighting is inert**. | Write `rarity` from the column. One line in the generator, then regenerate. This is the fix that makes the roller do what its comment says. |
| **`Scroll of Remove Curse` (new row)** | Rare, Positive, blank Effect — and it has a real job (§10.1). | Author `remove_curse choose 1` and build the op. |
| **Amnesia widened** | Prose now says *"Forget 1 random **Identified Loot**"*, but the Effect cell still says `forget scroll 1`, and `ScrollSystem._forget_scrolls` only knows scrolls. | Make `forget`'s `kind` mean it: `forget loot 1` unidentifies across scrolls, pills **and potions**. The pills' horse Amnesia already authors `forget loot all`, so the verb was always meant to be kind-blind — it just has no implementation for the wide case. |
| **`Description` column added** | Authored prose the generator does not read; `LootSystem._scroll_line` reassembles a description from the ops instead. | Carry it onto `ScrollData.description` and prefer it where it is non-empty, falling back to the assembled line. Authored words beat generated ones, and potions should do this from day one rather than growing the same gap. |
| **Identify's `Notes`: "+25% find rate"** | No such concept exists. | Decision #20: a `find_weight` float on the resource, applied as a **weight inside the rolled rarity bucket** — after the 75/20/5 roll picks Common, Identify is drawn at 1.25× the weight of the other Commons. Rarity keeps meaning what it means, which a flat "25% of scroll drops are Identify" would break. One field, one weighted pick, and it wants to exist on `PotionData` too. **The flat share won in the end** — see decision #20's supersession note: 1.25× inside a Common bucket, behind a three-way kind split, came out at about one drop in forty, which is too rare for the scroll that teaches you the other two alphabets. The Notes cell now reads "Not rolled with the other scrolls: 10% of every loot drop is this one instead", and the generator turns that into a weight of 0. |
| **Identify widens with Amnesia** (decision #13) | `identify_scrolls choose 1` only ever offers carried **scrolls** (`ScrollSystem._carried_unidentified_scroll_ids`). | Rename the op `identify_loot` and let it offer any unidentified carried piece — scroll, pill or potion. With three alphabets in one pack a scroll-only Identify is dead weight two thirds of the time, and it is the exact mirror of the Amnesia change directly above: one verb that forgets loot, one that learns it. The picker in `LootUseModal._pick_identify` already lists candidates by name and art — it needs the candidate list widened, not rebuilt. Keep `identify_scrolls` parsing as an alias so an old cell still resolves. |

None of this is potion work, but every row of it is something potions would
otherwise copy in its broken state.

### 10.1 Remove Curse has something to remove

**A correction to an earlier draft of this doc, which read the spec's §5 too fast.**
§5 shelves the combat-era **curse CARDS** (`CurseData`, `data/curses/`, the 16-card
gambit layer). It does not shelve **curse GOALS**, which are live, authored and
drawn on screen every game:

- `data/curses2.0/` holds three — **Curse of the Bell**, **Injury**, **Poor Sleep**
  — generated from the `curses2.0` sheet onto `CurseData2`;
- `GameState.curse_goals` carries them, `ReportChecklist` draws them as the rows you
  are trying *not* to tick, and `trigger_curse_goal` bills you when you admit to one;
- **events hand them out** (`EffectSystem._h_add_curse` → `GameState.add_curse_goal`),
  the Amnesia pill hands out a random one, and the **Calling Bell** relic arrives
  carrying Curse of the Bell permanently.

So a Rare scroll that removes one is not a placeholder — it is a good card, and its
best target is the one row in the game that **never expires on its own**: the Bell's,
whose `Timer` is `N/A` and which `add_curse_goal` therefore stores as `games_left =
-1`. Everything else on that list clears itself in three games.

The op is `remove_curse choose|random|all N`, in the shape `identify_loot` and
`stun_enemies` already use — a `request` back to `LootUseModal`, a picker listing
the held curses by name and condition, and a line naming what was lifted. It needs
one new function, `GameState.remove_curse_goal(index)`: the list has `add`, `has`,
`trigger` and `tick`, and nothing that takes a row off it early.

> **Do not reach for `GameState.remove_active_curse`.** That is the *card* system's
> removal and it operates on a different list. Same word, different thing — the
> warning `CurseData2.gd` opens with.

A fizzle when the player holds none — *"Nothing is weighing on you."* — and the
scroll is identified either way (§4.5).

---

## 11. Build order

1. ~~**The timed layer** (§5.4) + the `beat_game` expiry + the wording (§5.3) + the
   shield claw-back (§5.5), with tests.~~ **DONE.** `GameState.timed_statuses` and
   the twin on each board entry, `GameLoop2._expire_timed_statuses` beside
   `_decay_tiles`, `StatusData.clock_note` / `clock_suffix` through every surface
   that draws a pip or a goal line, and `apply_status(id, stacks, games)` /
   `apply_enemy_status(..., games)` as the way in. One thing the build turned up
   that the design had not: the authored ceiling has to apply to what the layer
   ADDS and not to the permanent count under it, or a read clamps stacks that
   §13.1 is careful to let tick down.
2. ~~**The scroll deltas** (§10) — the generator's rarity fix, `description`, the
   widened `forget` and `identify`, `find_weight`, and `remove_curse` with its
   picker (§10.1).~~ **DONE.** Potions are born into a roller and a picker that
   already work for more than one kind. Three things the build settled that the
   plan had left open: the kind-blind half of `forget` and `identify` lives on
   **`LootSystem`** (`identified_types`, `unidentify`, `forget_identified`,
   `carried_unidentified`), which is where the potion arm goes in step 4 — one
   line, and no call site changes; `find_weight` is read out of the **Notes
   column's prose** rather than from a column of its own, so `PotionData` gets the
   same treatment; and Identify's candidates are **entries, deduped per type**,
   which is what makes an unknown potion offerable at all.
3. ~~**Data**: `PotionData`, the generator, both Effect columns authored (§7.3),
   `Data` wiring, the editor rescan.~~ **DONE.** All 30 cells are written
   (`tools/_potions2_effect_cells.py`) and all 15 rows load, 9/3/3 on the shared
   ladder. Two things the build turned up: Raise Level's `On Tile` PROSE cell is
   the sheet's `N/A` as well as its effect, so one potion in fifteen has no throw
   line for a card to draw — step 4 has to read a blank there as *"this one cannot
   be thrown"* rather than as missing text; and the two effect columns are
   different enough that the generator parses them in two dialects, refusing a
   quaff verb in a throw cell and vice versa, which is what caught the difference
   in the first place.
4. ~~**`PotionSystem`**: the deal, identification, art, `quaff_potion`. Quaff only.
   At this point a potion is a pill with better art and it is fully playable.~~
   **DONE.** Two things the build turned up. **The deal has to be by colour NAME,
   not by file**: Golden and Magenta each ship in both art sets, and two bottles
   answering "Golden Potion" break decision #18's whole point, so the bag is drawn
   from one vial per distinct name. And **`gain_level` needed the level-up path
   extracted** — one level (stats + the character's reward, no condition) is
   `GameState.grant_level_up` now, and `Overworld2` keeps the condition and the
   bonus-level chain, which are the parts about EARNING one.
5. ~~**The throw**: `area_cells`, `max_health` on an entry, the four new ops, the
   picker generalisation, the second button — and the Landmine's damage trigger
   (§4.7), which is the one piece of this step that is not potion code.~~
   **DONE.** `GameLoop2.area_cells` / `area_instances`, `max_health` on every
   board entry (seeded, serialized, re-seeded on a Scramble, and drawn as `❤2/3`
   where it differs), `PotionSystem.throw_potion` with the six throw ops and
   §8.2's `AREA_LADDER`, `BattlefieldView.aim_cells` widened to take an aim
   REQUEST, a second button in `LootUseModal`, and `damaged:` in the tile/unit
   effect DSL with the Landmine authoring it.

   Three things the build settled that the plan had left open. **The `damaged:`
   list runs with the unit still standing on the cell**, not after it has been
   taken off: `detonate` goes back through `detonate_unit`, which is what spends
   the unit and carries the bomb modifiers, and which refuses a cell with nothing
   on it — §4.7's ordering argument was about the fire a detonation lays, which
   `detonate_unit` already handles. **A throw is refused while the drop screen is
   up**, because that screen owns the whole window and a picker armed under it
   lights squares nobody can reach; the bottle is not spent, so the modal says so
   and the player quaffs it or carries it out. And **arming a throw closes the
   loot window and the info card**, which float over the board for the same
   reason.
6. ~~**`loot_capacity()`** (§8.1) — the seam for a bigger bag, no relic.~~
   **DONE.** The const is the BASE now and `GameState.loot_capacity()` is what
   every surface reads; `LootGrid` derives its columns from it rather than from a
   literal 3.
7. ~~**The income switch** to a three-way split (§8) — last, so the run is not
   paying out a kind that is only half built.~~ **DONE.**
   `GameState.roll_loot_kind()` is the one roll both kind-blind callers ask, which
   is the half of this the plan was really about: the two of them each spelled
   `randi() % 2` out for themselves, and that is two places for the odds to drift
   the day one is tuned.
8. ~~**README + CHANGELOG**, and `gain_potion` for whoever authors the first potion
   relic.~~ **DONE**, plus the Collection's third sub-tab — and `gain_potion` was
   already registered on `EffectSystem`, written in step 4 and never called.

**All eight steps are built.** Step 1 was the risky one and step 5 is where the
new gameplay turned out to be, exactly as this list guessed. What is left is
tuning rather than construction: see §12 for the two questions the build could not
answer by itself.

---

## 12. Open questions

- ~~**A throw during the report step.**~~ **Answered: it works, and it is fine.**
  The picker is drawn on the board's own arrow layer and nowhere else, so the
  checklist beside it keeps its own rules and nothing the report has locked
  becomes clickable. Verified on screen mid-report.
- **Fysh Oil's two clauses under Sacred Bark.** The Bark doubles *named fields per
  op*, so a two-clause potion doubles both clauses — 2 Strength and 2 Dexterity.
  Correct, but worth eyeballing against the one-clause rows once it is in.
- ~~**Does `area` doubling leave a `cell` alone?**~~ **Built as §8.2 says: yes.**
  A radius of zero doubles to zero, so a Barked Block Potion still shields one
  body. The alternative (`cell` → `3x3`) makes every single-target throw a blast
  under the Bark, which reads as a different relic.
- **Lucky Foot's reach** — pills-only for now (§8). Sacred Bark and Echo Chamber
  already cover all three kinds.
