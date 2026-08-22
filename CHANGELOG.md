# Changelog

Newest first. This is the running narrative of what changed in the build and
why — it was the README's `## Recent changes` section until it grew to two
thirds of the README, at which point everyone reading the README to learn how
the project *works* was paying for it.

For how the project is laid out and how its systems fit together, see
[`README.md`](README.md); for the canonical spec of the current build, see
[`docs/games-first-redesign.md`](docs/games-first-redesign.md).

---

- **A tick is a confirm, and a confirm resolves NOW.**

  The report was the only moment anything on the checklist could happen. That was
  fine while a game was one long wait for a single point; it is wrong now that the
  board moves whenever you *fail* and a kill is something you can go and make — a
  goal cleared in the first hour sat unpaid for the rest of the evening, and its
  reward was behind a screen you had not reached.

  Every box on the checklist now asks once ("did you really?") and, on Yes,
  **resolves on the spot, mid-game**: the enemy takes its hit and drops its chest
  on the square it fell in, the bonus pays, the `demand` is answered, the level is
  taken, the event goal is claimed. Every row type, and losing runs gates none of
  it. **There are no take-backs** — the confirm is the safeguard, and past it the
  row locks, ticked and done. (Undo, beside the lost-run tracker, still takes back
  a *turn*; that one is the board's, not yours.)

  **The loop remembers, not the boxes.** The page rebuilds the checklist on every
  repaint, so `GameLoop2` keeps the per-game record instead: `cleared_this_game`
  and `instead_this_game` (a survivor of a mid-game clear still holds its fire for
  every turn of the report), `goals_met_this_game` (a player clause riding a goal
  still ticks for it), `answered_this_game` (a `demand` answered at noon is not
  billed at midnight), and `answered_rows` for the bonus / curse / level-up rows
  the others have no room for. All of it clears when the game is chosen or handed
  in, rides the undo snapshot, and is saved.

  **A body you killed still pays its bonus.** The report always resolved bonuses
  *before* goals so "an enemy you failed can still pay its bonus" held; with the
  goal resolving when it is ticked, the order is the player's. `_ghosts` keeps the
  entry a body defeated this game used to be, its row stays on the list, and
  `claim_enemy_bonus` reads it — otherwise ticking in the "wrong" order silently
  forfeited a reward that had been earned.

  The report is left with what is still outstanding, which in practice is nothing:
  `ticked_fulfilments` and `ticked_status_claims` skip any row that is pressed
  *and* locked, so nothing is ever hit or paid twice.

- **Chests land on the board, on the square the body fell in.**

  A defeated enemy's chest used to exist only as an entry in the page's drop
  queue, which meant the reward for clearing a goal was always *behind the report*
  — you could not have it until you had handed the game in. Now the loop owns a
  **floor** (`GameLoop2.drops`, cell → `{items, boss}`) and the chest is laid on
  the square the body died in: its leading cell, the one nearest you, so a long
  enemy leaves its loot at the end you were looking at.

  The board draws a pressable `✦` token there (`BattlefieldView._drop_node`,
  ringed thicker for a boss's) and reports the press through `drop_clicked` →
  `Overworld2.collect_floor_drop`, which opens the same `ItemDropModal` the haul
  screen would have used. The floor is a place a chest can be answered *earlier*,
  not a second kind of reward. Its hover card says how big the question is and
  that leaving it is allowed, and deliberately **does not list what is inside** —
  reading the answer off a tooltip would make opening it a formality.

  **A chest never blocks anybody.** `fits_at` does not consult the floor, so a
  body walks onto the square and the chest is shoved aside instead
  (`_displace_drop`, from `_move_entry`): nearest free square by squares walked,
  ties broken **away from the player**, off field when the board is full. Loot
  drifts back toward the wilds rather than into your lap, so crossing the board
  for a chest is worth something. A body cleared while it was still waiting in the
  off-grid queue has no square to fall in and its chest goes straight to the haul.

  **Reporting the game sweeps the floor** (`sweep_drops`, called from `report` the
  moment `beat_game` returns), so nothing is ever lost by walking past one — what
  you did not stop for is on the reward screen with everything else, including
  whatever the bodies that very report cleared just dropped. The floor saves and
  restores with the rest of the loop, and an item id the catalog no longer serves
  is dropped on the way in along with any chest it empties.

- **Extra turns: reporting a game no longer moves the board.**

  The amulet ladder was 1 / 2 / 3 turns per reported game, so every game handed
  in moved the stack whether or not the player had struggled at it. It is 0 / 1 /
  2 now, and the floor is the point: out in the wilds you can play a game, report
  it and walk away with the board exactly where you left it. The stack moves for
  two reasons and both are things that happened — **you failed** (a lost run, one
  turn each) or **you are close to the win** (this ladder).

  The readout says what it is: `⏱ EXTRA TURNS 0` / `1` / `2`, in the band's
  colour, with the hop count that caused it. Cards quote the same price
  ("Enemies speed up — 1 extra turn", "Still no extra turns"), the resolve's
  counter reads `EXTRA TURN 1 / 2`, and `RunDifficulty` is authored in those terms
  throughout (`EXTRA_FAR/MID/NEAR`, `extra_turns_for_hops`, `band_name`,
  `extra_text`, `ladder_text`).

  **The threat readouts had to move with it.** "2 swings landing for 2 damage next
  game" now reads zero for a game you are about to report, which is true and
  useless — so they are priced in LOST RUNS instead: "2 closing in, 2 swings for 4
  damage on every lost run", per-body `⚔3` for the swing one turn would throw, and
  `in 2` for the lost runs of walking it still owes. `attacks_next_game` →
  `attacks_in_turns` (defaulting to one turn), `games_until_strike` →
  `lost_runs_until_strike`, `stacked_damage_per_game` → `damage_per_lost_run`.

  Found while fixing the suite: the tests' `_tick()` helper was `beat_game`, which
  is how nearly every board test walked a body forward — and with a zero floor
  that walks nowhere. It is `attempt_turn()` now (`_turn()`), with `_report()`
  where a test is really about the end of a game. Two unbounded `while col > 1`
  march loops in other files would have hung the suite outright rather than
  failing; they are bounded and turn-driven now. And two test scripts were left
  calling the old `RunDifficulty` API — GUT **silently skips a script that will
  not parse**, so the suite came back green with 350 fewer tests in it. Both are
  fixed; it is worth remembering that a passing run with a smaller `Tests` count
  is a failing run.

---

- **Escape opens on the hit.**

  A game you cannot beat has always had a way out; the question was what earns
  it. It used to be five lost runs — a counter standing in for "this game is
  hurting you", because back then nothing else measured that. The board measures
  it directly now, so the gate is the thing itself: **Escape is offered the moment
  an enemy's attack takes Health off you during the game in play.**

  It falls straight out of the two changes above. Lose runs, the enemies take
  turns; a Temporary Shield stops the first swings outright; the door opens on the
  swing that gets past them. So the way out arrives exactly when the game starts
  costing the one thing you cannot make more of — and never merely because you
  were patient. `ESCAPE_AFTER_ATTEMPTS` is gone.

  A **swing only**: Burn's bill and an event's price cost real Health and do not
  open it, since neither is the game in front of you refusing to go down. It is a
  fact about the game in play — `GameLoop2.hurt_this_game`, cleared when a game is
  chosen and when one is reported, saved with the run, and rewound by an attempt's
  undo, so taking back the tick whose turn drew blood shuts the door again. The
  second door is untouched: a game this run has already beaten is escapable from
  the first second, because there is nothing left to prove at that one.

  The price is unchanged — the goal-enemy still follows you, the stack still takes
  its turns, and no beat is banked. Only the gate moved.

---

- **The two shield pools are named for the one thing that separates them.**

  What a game grants are **Temporary Shields** — they expire when it is reported.
  What is gained off the board (a pill, Barricade banking a resolved game) are
  plain **Shields** — they stay until something breaks one. That is the whole
  distinction, so it is the whole of the name; "Bonus Shields" said where they
  came from, which is the part nobody has to plan around.

  The FIELDS keep their older names, `shields` and `bonus_shields`: those are the
  keys every save is written with and the stat names authored content grants
  (`gain_stat shields 1` is Anchor, `gain_stat bonus_shields 2` is Balls of
  Steel), and swapping them would flip the meaning of a word inside every existing
  save and every `.tres` that says it — with the two names trading places, a
  single missed site would silently fill the wrong pool. So the mapping is stated
  once, at the fields, and the words the player reads come from
  `GameState.TEMP_SHIELD_NAME` / `SHIELD_NAME` through two helpers that agree
  their own plurals. Nothing types either name inline any more.

  Content text came from the sheet, not from a hand-edit: **Anchor** now reads
  "Gain +1 Temporary Shield" and **Barricade** "unspent Temporary Shields become
  Shields", edited in `tools/Roguelikes.xlsx` and regenerated. The pills needed no
  change — "Gain +2 Shields" was already exactly right for the pool they fill.

---

- **Shields stop hits, not attempts — and one shield stops a whole hit.**

  Two mechanics were wearing one resource. Shields were the TRIES at a game (a
  lost run spent one) *and* the armour you met the stack with, so every failed
  attempt at the real game was also a hole in the wall you were about to be hit
  through — punished twice for the same bad evening. They are split now.

  **A lost run costs a turn of the board and nothing else.** No shield is spent,
  so there is no limit on how many times you may fail at a game; what there is, is
  a board that is one turn closer every time you do. `next_attempt_cost` is gone
  (there is only one thing a tick can cost) and `can_log_attempt` replaces it;
  `attempts_on_shields` went with it, since no attempt is paid for with a shield
  any more and nothing on the strip goes hollow.

  **A shield stops one INSTANCE of damage** — the whole of it, whatever its size.
  A 3-damage swing breaks one shield and lands for nothing; so does a 1-damage
  one. That is deliberately blunt, and it is what makes the pool readable: three
  shields is three hits you don't take, and "which hits do these five points
  cover" is never a sum anyone has to do. It also makes a big hit the one you
  *want* a shield to meet, which is a thing to play around — a Push, a Stun —
  rather than arithmetic.

  The rule holds wherever damage lands: a follower's swing, Burn's "take 3
  Damage" bill, any `take_damage` effect, all through `_take_hit`. A `lose_hp`
  bill (an event's price, a machine's lever) is not damage and never was — it does
  not come through there and shields do not stop it. Marked still pierces. Enemy
  shields read the same rule (`_damage_enemy`): identical in practice today, since
  every hit in this game is worth exactly 1, and written that way so both sides of
  the board answer "what does a shield do" the same the day one isn't.

  Everything else about them is unchanged: granted on selection (3, or 5 for a
  Traditional), per-game pool spent before the pool that stays, and they expire
  when you report the game unless Barricade banks them.

  The word "tries" is gone from the UI with the mechanic — the manual, the card
  popup, the offering's hover line and the board's tooltips all say shields now,
  and say what one does.

---

- **Amulet pressure is BONUS turns now, not the turn count.**

  The ladder used to *be* how many turns the enemies took per game — ×1 out in
  the wilds, ×3 on the Amulet's doorstep — which quoted a stat where the player
  needed a price, and invited the wrong reading besides: that closing in makes
  the enemies act twice inside one beat. It doesn't. **Every enemy takes one turn
  per game reported, wherever the run is standing**, and closeness buys them
  BONUS turns on the end of the game — +0 / +1 / +2 — taken after every enemy has
  had its own.

  The totals are the ones the game already had (1 / 2 / 3): what changed is what
  the ladder is authored as and what the screens say. `RunDifficulty` owns
  `TURN_BASE` and `BONUS_FAR/MID/NEAR` with `bonus_turns_for_hops` as the ladder;
  `turns_for_hops` stays as base + bonus for the resolver, which counts turns
  rather than prices. The band name, colour and ladder text are all keyed on the
  bonus now, so nothing on this axis is left speaking the old units.

  **What the player sees.** The board's strip reads `⏱ ENEMY TURNS 1 +1`, and
  plain `1` in the Distant band — "no bonus" is a state worth reading as calm.
  Its three rungs are the same gauge with a clearer story: first pip the turn
  every game gives, the other two the Amulet's. Cards say the price — "Enemies
  speed up — +1 bonus turn", "Still no bonus turns" — and the resolve's counter
  names which half of the bargain each beat came from: `TURN 1 / 3`, then
  `BONUS TURN 1 / 2`. `beat_game`'s result carries `bonus_turns` so the board can
  say that without recomputing it.

---

- **A lost run gives the enemies a turn, and status goals wear their symbol.**

  **Out of shields, the board takes a turn.** A lost run used to cost a flat
  1 Health once the tries were gone, which billed the one price in the loop the
  board could not see: the enemies walking at you are the whole tension of a game,
  and running out of tries quietly stepped around them to move a number in the
  corner. Now the tick hands the stack **one turn** — the same
  `_resolve_enemy_turn` a reported game takes `enemy_turns()` of, so the ground
  burns whoever is standing on it, everything touching the front column swings for
  what its statuses make of its damage, everything behind it walks a column
  closer, and a stun costs one turn of either. It still costs Health, usually more
  than one; it costs it *through the board*, and it compounds, because the board a
  tick moves is the board the next tick moves again. Nobody holds their fire —
  that exemption is a fact about a *reported* game, and nothing has been reported.

  **A board with nothing in reach charges nothing**, deliberately: the turn is the
  cost, so a cleared stack has nothing to take and a body still walking in merely
  walks. The tick is logged all the same — it is what the escape hatch counts and
  what the pips draw.

  **The undo became a restore.** A refund works for a shield; a turn walks bodies,
  burns ground, breaks the trinkets that break on a hit and pays out whatever
  losing Health pays out. So the tick snapshots the board (`GameLoop2.serialize`)
  and the run's resources (`GameState.snapshot_run_resources` — Health, the purse,
  both shield pools, banked chests, the player's statuses, the pack) before it
  resolves, and the undo puts the whole thing back. Those snapshots are
  runtime-only, since a save carries the run and not its undo history, so a turn
  taken before a reload can't be taken back: `can_undo_attempt` says so and the
  undo button greys out with a tooltip rather than half-undoing something. The
  turn is watched, too — the board replays it with the same `animate_resolve` the
  end of a game uses, and a lethal one holds the end-of-run screen until the blow
  lands.

  Found on the way: the three attempt lists (`attempt_costs`, the payouts and now
  the snapshots) are indexed in lockstep but only the first was being cleared when
  a game closed out, which left a payout to be handed to the *next* game's first
  undo. They drop as one now (`_clear_attempts`).

  **Status goals lead with the symbol.** A status row on the checklist opened with
  its name and stack count ("Marked 3 —"), spending the widest part of a
  glanceable list saying what the art beside every other reading of that status
  already says. The row now leads with that same art and the prefix is the count
  alone ("×3 —"), with the status's own hover card on the chip so the symbol
  answers what it is rather than having to be memorised. The name comes back for a
  status with no art. Both checklists, plus the bonus, "or instead" and nullified
  rows.

---

- **The haul screen, second pass — and four things it turned up.**

  **Every chest at once.** They were drained one at a time, which is how the
  page's queue had always worked, and it hides exactly what the screen exists to
  show: when several relics land together, the thing you most need is what the
  *others* are. There is often an order — a relic that changes what a chest is
  worth should be taken before the chest it changes. So all of them are on the
  screen together, each still its own "which one of these", and a one-item chest
  lays out sideways (card left, Leave and Take stacked right) because stacked it
  was 135px and three of those put the third relic behind a scrollbar. A relic is
  **always a picture** now: both layouts drew art only when `item.image` was
  non-null, so an unarted row would have come up as a name over a gap.

  **The payout stays, and loses its buttons.** As a modal, the table emptying is
  the end of the question; here it is the opposite — the piece has just gone into
  the pack, and the pack is the reason to still be looking, because the next thing
  you usually want is to spend it. Take and "Leave the rest" go with it: the drag
  already puts a piece in the slot you want and the bin is "leave it" said with the
  hands. What is still on the table is counted on the way out, so nothing goes
  quietly. The two columns are top-aligned as well — centred, the offer floated
  down to the middle of the nine slots and its description read as having slipped
  under the pack.

  **Two things were opening underneath the screen.** The shop's item card mounts
  at CanvasLayer 122 and the screen is 128, so clicking a shelf row opened a card
  nobody could see and then produced it a screen too late; `ShopPanel2.card_layer`
  is the host's to set now. And `RewardScreen` mounts as an ordinary child of the
  page, so a chest banked mid-report — a level-up reward, Unstable Genome, a status
  paying out — was invisible until you had already left. Those land on the screen
  as chest sections, rolled on the same ladder the RewardScreen would have used.

  **A boss cancels the ways out, and now it says so.** A boss comes off the board
  on its goal alone, so an `instead` riding it buys nothing — and the way that was
  communicated was by drawing nothing at all. A Burn pip on a boss, no row on the
  checklist, no line on the card, no tick anywhere: indistinguishable from the burn
  having failed to apply. `nullified_alternatives_for` is the other half of the
  pair, and the checklist, the enemy card and the status hover all say it.

  **A status is authored per side, and the two are opposites.** Burn on you is an
  obligation that bites for 3; Burn on an enemy is a second way through its goal.
  The keyword strip under an item's description quoted the player's side, so Staff
  of Flame — "Apply +3 Burn to a target enemy" — had a footnote explaining what
  Burn does to *you*. Not a short version of the answer, the wrong half.
  `tooltip_both` prints one side when the other is inert and labels them when both
  do something. The enemy card had the same bug from the other end: an `instead`
  fell through to the clause branch and printed a clause Burn does not have.

  **A full bar means ready.** Every active was held back until the game had been
  reported — right for a Usable consumable, which wants a combat or an event around
  it, and wrong for a Charged one in the way that shows: the strip said the item
  was ready and then refused to fire it, offering "finish reporting this game
  first". D6, Staff of Flame and Mom's Bottle of Pills are all charged and all
  three do something wanted precisely while the board is live. A charge that cannot
  be spent when it is full is a charge permanently one game behind.

  **And loot is spendable whenever you want it.** The mid-report lock holds the
  pack *still* — nothing dragged, taken or binned — and it used to hold spending
  too, which was wrong twice over. Mid-game is exactly when a player knows what
  they want out of a piece: the body walking toward them is right there, a Scare
  Monster or a Scroll of Fire is the answer to it, and an unknown capsule is a
  gamble taken *because* of what is on the board. Scrolls were held back further
  still by an overworld-only rule of their own.

  The answer is a **fizzle, not a refusal**. A Use button that will not press
  teaches you the piece is unusable rather than that this moment is wrong for it.
  Only a **teleport** genuinely needs the map, and it comes back "it fizzles — you
  do not move"; every other scroll op lands fine mid-game, because the board is
  standing right there. And the piece is identified either way, since both systems
  identify before they apply anything — so the gamble still paid off. That is what
  makes a fizzle acceptable where a refusal was not: you spent the piece and got
  the information you spent it for.

  Two things fell out of that. **A relic that pays loot when it is picked up now
  pays it onto the table beside the card that paid it** — Mom's Coin Purse is four
  pills, and queueing them behind a screen the player has not left yet hid the
  payout until after the decision that earned it. And the autosave had a latent
  crash in it: the drop queue holds either shape — one entry for a game's own
  payout, the whole handful for a relic's grant — and `capture_view_state` cast
  both to a Dictionary, so a save taken with a grant still queued threw. It only
  started happening once the haul screen began autosaving on its way out.


- **A game now ends on a screen, and the Collection has a Loot tab.**

  **One screen instead of six surfaces.** Reporting a game used to fire a queue of
  unrelated questions at the player: one relic modal per defeated body, then the
  loot payout, then the event, then the shop appearing under the board, then the
  boss notice, with the toasts running underneath all of it. On a boss round at a
  hub that is five popups in a row, each re-centring on the same spot, each with
  its own Take/Leave, and nothing tying any of them to the game they came out of.

  And the first two of them opened **on top of the resolve animation**. Drops are
  queued in the middle of `beat_game` and were pumped on the next idle frame,
  while the board was still playing the strike and the advance back — the one
  place the run's consequences are ever *shown* — so you answered "do you want
  this relic" over the top of the blow that had just taken eight Health off you.

  So the haul is a screen (`PostCombatScreen`), and it opens when the board has
  stopped moving. The verdict — beaten, goal missed, or walked away, which are
  three different things. The fight in numbers, out of `beat_game`'s result, which
  until now was thrown away the moment the animation had played it: damage taken
  and blocked, goals cleared, what is still following, the tier and the board's
  growth. The relic chests down the left and the loot payout down the right **at
  the same time** rather than one after another. The hub's shelf. The boss warning
  as a banner. And **one button out**, which is the *event* when the node owes one
  — pressing it is what opens the event, so you leave the haul into the next thing
  rather than having the next thing dropped on you.

  **The sections are the real modals, embedded.** `ItemDropModal.embed`,
  `LootDropModal.embed` and `BossNoticeModal.embed` build the same cards, run the
  same selection and answer through the same signals; what they skip is the
  backdrop, the centring and the `CanvasLayer`. So the 3×3 on this screen is the
  inventory in the sense §4.3 means it, a chest is still "which one of these", and
  a boss portrait still opens its card. The standalone modals stay — that is the
  point of embedding rather than replacing — because `GameState.offer_loot` fires
  from `EffectSystem`, so an item, an event or a machine can hand loot over at any
  moment, and a payout that did not arrive with a report has no haul screen to be
  part of. `_pump_drops` suppresses itself only while a report is resolving.

  **The shelf is borrowed, not moved.** §14 chose the on-page mount deliberately —
  a shop blocks nothing and stays for the whole visit — and that is still right;
  what it never fixed was that a shop mounted below the fold on the frame you
  arrive is a shop you may not notice. So the same `ShopPanel2` node is mounted on
  this screen and reparented back under the board on the way out. The moment of
  arrival gets the shelf in front of you; the rest of the visit is unchanged.

  The way out **counts what it is about to bin**. A Legendary left on the ground
  should be a decision, not a side effect of pressing Continue.

  **The Collection's Scrolls tab is now a Loot tab**, with Scrolls and Pills as
  sub-tabs. They are one thing to the run — one 50/50 payout, one nine-piece pack,
  one window — and two top-level tabs said the opposite. Pills had no page at all
  before this, which is the half that was actually missing.

  A pill cell wears a **stand-in capsule and says so**. A pill carries no art of
  its own: its picture is the colour the run deals it out of `PillSystem.COLORS`,
  and the Collection opens from the main menu where no run has dealt one. Drawing
  each pill in some particular colour would teach an association the game
  randomises on purpose, so every cell wears the same capsule, dimmed, and the tab
  explains why. It shows **both doses** — the 5% horse roll is the same colour and
  the same identification, so a card showing only the normal one would be
  describing half of what taking it can do.


- **A piece of loot goes wherever you put it, and a use says what it did.**

  Two things the loot window was still getting wrong, both of them about the
  moment the player is actually looking at it.

  **The whole cell moves, and any slot is somewhere a piece can go.** A drag used
  to be the bare capsule following the cursor, which read as the art coming loose
  from its tile and gave you nothing to line up against the slot you were aiming
  at; it is the cell now — same border, same art, same name, at the size the grid
  draws one. And the slot it lands in is any of the nine. Free placement was the
  one thing the grid would not do, because a slot *was* an index into the dense
  `loot_items`, so a piece dragged into the far corner of an empty pack slid back
  to third place. The slot rides on the entry as `pack_slot` instead, and
  `GameState.loot_layout()` is the one place slots and indices are put back
  together — so the array stays dense and stays pickup order (which is what
  `loot_scrolls()` and the toggle's peek read), nothing in the loot code had to
  learn about holes, and the arrangement rides the save for free. A pack with a
  gap in the middle of it is an arrangement somebody wanted; the grid stopped
  tidying it away. A piece that was never placed still takes the lowest free slot,
  so a run that drags nothing sees the pack it always saw.

  **Taking a pill tells you what it did.** The use modal used to close the instant
  the piece resolved, which put the answer to *what did that do to me* in the run
  log on the far side of the page — the one place the player was not looking,
  having just been looking at the pill. On an unidentified capsule that is the
  entire minigame: the reason to swallow an unknown pill is to find out what it
  was, and finding out was happening off-screen. So a use ends on a screen that
  says it: the art, the name it turned out to have, its Preference, *what it turned
  out to be* when this use is what identified it, the effect's own lines, and where
  your Health landed when it moved. The pickers come first and the summary last — a
  request is part of what the piece did — and Cancel never reaches it, because
  backing out is not a use.

  **And every piece has something to say now.** The screen can only report what it
  is handed, and both systems return their logs *before* a request is fulfilled, so
  a piece whose whole effect is a request contributed no line at all: Teleportation,
  Telepills, Identify and Scare Monster all came out of a use reporting *"Nothing
  happens"*. `Overworld2.loot_teleport` returns the sentence it logs (with the
  distance from the Amulet, which is the fact the op is actually about), and
  `identify_scrolls_chosen` / `stun_enemies_chosen` return theirs and **name** what
  they touched — their silent `random` modes with them. Echo Chamber's replays are
  named on the outcome as well, since its copies land in the same merged logs and
  a run holding it was reading four pieces' worth of effects with no account of
  where three of them came from. Every scroll and both doses of every pill were
  taken through the real modal to check; a sweep in the suite keeps it that way as
  the catalog grows. One thing the sweep turned up: a stat dose had been saying
  *"You gain + 1 Luck"*, the sign a word away from its number — invisible in a run
  log, the first thing you read on a screen that exists to be read.

- **The loot window is a grid you handle, and the drop modal asks in front of
  it.**

  A design pass over the two inventories — the pack strip of relics, and the loot
  window that scrolls and pills moved into when pills arrived. The strip was fine.
  The loot side had drifted into being the least visible, least legible thing on
  a page whose consumables are what you spend turn to turn.

  **Loot can be rearranged, and a drop is placed rather than accepted.** The 3×3
  is `LootGrid` / `LootSlot` now, and it is the same widget in both places it is
  drawn: pieces drag between slots in the window, and the piece a game pays out is
  **dragged out of the drop modal into the slot you want it in** — the modal shows
  your pack beside the offer, so *"your pack is full"* is nine occupied slots
  rather than a sentence about something you cannot see. The buttons stay: **Take
  it** puts it in the first free slot, **Leave it** is still the answer the cap
  makes interesting. `loot_items` stays **dense** — a drag swaps two pieces or
  moves one to the end, never leaves a hole, because indices are what `use_loot`
  is addressed by. *(Superseded: a drag lands in any slot now — see the entry
  above.)*

  **Clicking a piece opens its card.** `LootInfoCard`, the twin of the relic's: a
  relic answered a click by opening its card and a pill answered a click with
  nothing at all, which is one class of object with two gestures, and the one that
  did nothing was the one whose whole subject is *what is this*. Click reads, drag
  moves, the button spends.

  **The run's alphabet has somewhere to live.** A folded *"Known this run"* at the
  foot of the window lists every colour and scroll the run has identified, with
  art and hover. The knowledge existed in `identified_pill_types` and was never
  drawn anywhere: the only time a colour was ever named was a toast that had
  scrolled away by the next game, which is an identification minigame with no
  record of itself. It **counts** the unlearned rather than listing them — naming
  them would hand back the deduction the three sitting-out colours prevent.

  **The horse dose is actually drawn oversized now.** The spec has always said the
  oversized capsule is how you know a horse pill is a horse pill; every surface
  drew loot through a *fixed* art box, which renders a 19px capsule and a 25px one
  at exactly the same size. Loot art goes through `LootSystem.art_tex` /
  `art_box`, which takes the ratio from `PillSystem.art_scale` — **measured from
  the two files**, so redrawing the art bigger draws it bigger.

  **The drop screen's pack is a live one, and there is a bin.** A full pack used
  to leave exactly two answers to a payout: leave it, or close the modal, go and
  spend something, and never get the payout back. Now every piece on that screen
  can be spent from it — a carried piece has its Use button, and spending one
  frees the slot the offer needs in front of the offer, with the drop still on the
  table because spending is not answering. The **offered piece can be used where
  it stands**, without ever being carried (`LootSystem.use_entry`): a Full Health
  that will not fit is not loot anyone should have to throw away, it costs no
  slot, and it is a real use — an unknown colour taken that way is identified,
  remembered and echoed like any other.

  And both surfaces that draw the grid now draw a **red bin** under it
  (`LootTrash`). Spending a piece is not the same as being rid of one: a pack of
  three known-Negative pills is full of loot the run will never willingly use, and
  reading the Amnesia scroll to make room is a worse answer than throwing it away.
  It lights up the moment you pick anything up anywhere in the viewport, it is a
  drop target only, and binning a carried piece asks first — it is the one gesture
  on either screen that destroys something and gives nothing back. Binning the
  offer is "Leave it", said with the hands, and asks nothing.

  **A payout of several pieces asks about all of them at once.** Mom's Coin Purse
  is four pills and Sacred Bark doubles what a grant pays; one offer per screen
  answered that by shovelling the rest into the pack and silently dropping
  whatever did not fit, which is the one thing the nine-piece cap exists to make
  into a decision. The offer is a list now — one cell per piece, each taken, used
  or binned on its own terms, scrolling past three rows rather than pushing its
  own buttons off screen — and **Take** takes as many as fit and leaves the rest
  on the table. Grants route through `GameState.offer_loot`, which rolls the
  pieces and hands them to whoever is listening and falls back to the direct grant
  when nobody is, so headless runs and the tests are unchanged.

  **And the pack that screen shows IS the inventory** — the same `LootGrid`, with
  rearranging, click-to-read, Use, the bin and the "Known this run" fold all
  working exactly as they do in the loot window. The only difference is the offer
  on the left. The fold is shared rather than copied (`LootDiscoveries.open` is
  static), since shut in one place and open in the other would be two answers to
  one question. When a payout, a full pack and an unfolded record together outrun
  a 720p canvas, the body scrolls and the answer buttons stay pinned under it — a
  modal whose buttons are below the fold looks unanswerable.

  **The loot toggle moved to the pack panel's foot**, as a thin full-width bar
  under the relics. That is its third home: at the tail of the relic row it hid
  under the toasts, and at the head it ate the left end of the strip the relics
  wrap into. On its own row it costs the relics no width, and the pack panel's own
  padding was trimmed to pay for the row — the page fits a 720p canvas with about
  five pixels to spare and the fit tests fail at +2.

  **Tab opens the pack.** The `backpack` action has been in `project.godot` since
  the combat build with nothing on the overworld listening for it — only the
  Collection, which reads it to close itself and is never on screen at the same
  time, so the key was free.

  And the rest of the pass: the **Preference** is a coloured chip on every surface
  that shows a piece rather than grey body text, on the one fact the decision
  turns on; the loot **toggle leads the pack strip** instead of trailing it, where
  it spent most of every report hidden under the notification toasts, and it
  carries the first few capsules and turns **red at 9/9**; cells are 48px art and
  11px names instead of 34px and 9px, with **two lines reserved for the name** so
  a short name stops pulling its Use button above its neighbours'; and every
  button on the loot screens is `UITheme.confirm_button` / `quiet_button` instead
  of Godot's default grey — the relic drop's take was green and 190px wide while
  the loot drop sitting behind it in the same queue was two identical grey
  buttons.

- **Pills: a second loot consumable, and the identification minigame held by a
  colour instead of by a type.**

  Ten pills (`pills2.0`), thirteen capsules, and every run deals ten of them and
  leaves **three colours meaning nothing** — which is the whole design, because
  it is what stops the tenth pill being deducible once the other nine are known.
  A pill never hides its art the way a scroll does; the capsule is the thing
  being learned. What it hides is the name and the Preference.

  **Every pill is two doses.** A drop rolls **5%** to arrive as the colour's
  oversized HORSE version, which reads its own effect column. The roll belongs to
  the piece of loot rather than to the type, so one colour can be carried both
  ways at once — and identification is the COLOUR's, so learning either dose
  learns both. Four horse doses are just a bigger number; the other four say
  something the normal dose cannot (Telepills' horse lands by distance from the
  Amulet, which is the only movement in the game that can drop you next to the
  goal).

  **Bad Trip names itself from your Health.** At or below its own damage it heals
  to full instead of killing you, and an identified Bad Trip therefore reads
  *"Full Health"* while you are in death range and *"Bad Trip"* the rest of the
  time. The label follows what the pill would DO right now, which is why two
  colours can both claim to be Full Health, and why it cannot be a stored name.

  **Bonus Shields** are the pool that is not per-game: gained off the board
  (Balls of Steel, horse Full Health) or banked out of a resolved game by
  **Barricade**, spent only once the game's own tries are gone — a lost run and
  an enemy's swing read the same order — and they never expire. They are drawn
  closest to the player, `◈` at the head of the hero's pips and on the header's
  Health chip, since a pool gained on the overworld has to be readable with no
  board on screen. Barricade's old rule (shields simply stop expiring) quietly
  made the per-game pool a second permanent pool with its own spend order; there
  is one permanent pool now and one relic that fills it.

  **Loot moved off the pack strip into a window of its own.** Nine pieces beside
  a run's relics is a second inventory wearing the first one's clothes, so there
  is a `Loot 4/9 ▾` toggle at the end of the strip's row, and it opens a 3×3 grid
  as a panel **over the board** — always nine slots, filled then empty, because
  the room left is the fact the cap makes interesting. It covers the battlefield
  rather than the offering: the pack strip stands on top of the board, so the
  window drops out of its own button, and the board is the half of the page that
  does not change while you decide which pill to take. Scrolls went with
  it — one window means one place to look — and
  `ScrollReadModal` became **`LootUseModal`**, because Echo Chamber means using
  either kind can hand back the other's follow-up.

  **`LootSystem`** owns everything that happens *around* a use: consuming the
  entry, **Echo Chamber**'s copies of the last three used, and the memory they
  read. It belongs to neither consumable system because an echo of a pill can be
  a scroll. The ordering is Isaac's — the copies fire off the memory as it stood
  BEFORE this use, so nothing echoes itself and no echo is remembered — and it
  composes with **Sacred Bark** rather than cancelling: one pill with both relics
  is two doses of it plus three echoes at two doses each.

  **Beating a game now pays one piece of loot**, a straight 50/50, asked about in
  the kill-drop queue rather than granted as a toast. Escaping pays nothing. With
  a nine-piece cap on the pack, taking loot is a decision, and a decision needs a
  question.

  Four relics move the number (Mom's Coin Purse, Mom's Bottle of Pills, Caffeine
  Pill, Lucky Foot) and one changes what spending it means (Echo Chamber). **Lucky
  Foot rerolls a Negative pill into a random Positive one — but the colour still
  identifies as what it actually is.** The relic changes the outcome, never the
  fact; any other reading starts lying to the player the moment the Foot leaves
  the pack.

  **Amnesia's horse dose takes its own name with it.** It identifies the colour on
  the way in and then forgets every identified piece of loot — and "every"
  includes the lesson taking it just taught, so the horse dose can never leave
  itself known. Its colour is learned from the NORMAL dose, which hands out a
  curse and forgets nothing.

- **The offering moved out of the overworld, and the split is finished.**

  **`OfferingCards.gd`** — 506 lines: the cards you choose your next game from in
  *both* choosing phases (the choose-your-start picker and the ordinary
  offering), the hover line under them, and the enemy portrait beside it. They
  share every widget below their two entry points because they are the same
  decision asked twice. `Overworld2.gd` is **4260 lines now, down from 5573** —
  a 24% cut across three splits, and the file is no longer dominated by any one
  mechanic.

  The page kept the three containers (`_choices_row`, `_preview`,
  `_preview_art`) and every verb a card fires on click (`open_choice`,
  `open_start_choice`, `preview_map`), so the offering decides what the cards
  *look* like and the page still decides what they *do*.

  **One behavioural substitution, and it is the interesting part.** The hover
  line's idle text differs between the two phases, which it read off the page's
  `_phase`. Rather than reach back for that, the class sets its own `_starting`
  flag in the two render entry points — the only things that can change which
  phase drew the cards. `_page.Phase.START_SELECT` would have worked (a const or
  enum does read through a `Node`-typed reference; that got checked rather than
  assumed) but it re-couples the class to the page's phase model for nothing.
  The verify pass asserts the flag flips in both directions.

- **The report checklist moved out of the overworld too.**

  The big one, and the second cut of the split above: **`ReportChecklist.gd`**,
  776 lines covering the left column in both of its states — the standing list
  while you're choosing, the tick-box report step while you're playing — plus the
  row↔body pairing that lights a goal and its enemy from either end.
  `Overworld2.gd` is **4707 lines now, down from 5573**.

  The backlog had this at 400 lines. It is 776 once `_populate_standing_checklist`
  and the binding come with it, and they belong to the same mechanic: the two
  lists are the same rows in two states and share the same container. For all
  that size it needed three things of the page — the board, the chosen game, and
  the container pair — because its seven tick-state arrays were only ever touched
  from inside it.

  **The state the tests read stayed put, as read-only properties.**
  `test_overworld2.gd` reads `_ui._verify_box`, `_ui._fulfil_checks`,
  `_ui._levelup_check`, `_ui._lit_instances` and `_ui._row_paints` straight off
  the page, 57 references' worth. `ReportChecklist` owns them under public names
  and the page publishes a getter for each, which works precisely because no test
  ever *reassigns* one — they read the array and tick the CheckBox it points at,
  which is what a player does to the same object. Not one test changed.

  Verified on screen as well as in assertions (`.claude/skills/verify/`): both
  states render, the boxes tick, and hovering still lights the body.

- **The pack strip moved out of the overworld, and a test stopped believing a
  playback is always one beat long.**

  `Overworld2.gd` had reached 5573 lines, more than double the next-biggest file,
  and the last item in [`docs/performance-backlog.md`](docs/performance-backlog.md)
  is splitting it. That file listed three candidate seams by guess. They are
  measured now — on **genuinely shared state**, the vars a region touches that are
  also touched from outside it — and the cleanest seam in the file was not on the
  list at all.

  **`PackStrip.gd`** is the first cut: the pack strip's ~250 lines of token,
  battery, counter-badge and hover building, which touched exactly `_items_box`
  and one read of `_phase`. The page still owns the container, still decides when
  to redraw, and still owns the reading card a token opens — `ItemInfoCard` is a
  page-level modal, not strip furniture. Everything a token does on click goes
  back through one of the page's public verbs (`read_scroll`, `use_item`,
  `open_item_card`), and `_refresh_items` / `item_hover` stayed put as one-line
  forwards, so not one call site moved — in the page or in the 4476-line test
  file that reads its privates off the instance.

  Two things worth knowing before the next cut, both written down in the backlog:
  **type the back-reference as `Node`, not `Overworld2`** (two `class_name`s that
  name each other are a cyclic reference Godot resolves badly), and **pass the
  phase in rather than reading it out** — `rebuild(reporting: bool)` is what left
  the strip depending on nothing about the page except three verbs.

  **And the test that only passed at one turn a game.**
  `test_the_offering_comes_back_while_the_board_still_plays` waited a fixed 1.2s
  for the board's resolve playback and then asserted it had finished. A playback
  is one beat per TURN (§7.4) at `FX_ATTACK_TIME + FX_SLIDE_TIME` = 0.89s, and
  the turn count is the run's distance band — 1 turn beyond 5 hops from the
  Amulet, 2 inside that, 3 inside 3. So the same report runs 0.89s, 1.78s or
  2.67s depending on where the random graph put the start, and the 1.2s await
  covered the first case only. It failed once here, passed on the rerun, and
  passed on the clean tree, which is exactly how this class of bug reads. It
  waits on `_resolving` itself now, with a 5.0s ceiling over the 2.67s worst
  case. Third one of these; the rule in `CLAUDE.md` keeps earning itself.

- **The ground answers for itself, a bomb is aimed at a square, and the tier
  list fits on the screen.**

  Four things that were each one step short of finished.

  **Fire lit under a body burns it now.** A tile effect landing on a cell
  somebody is standing on fires its `enemy_enters` list on the spot
  (`GameLoop2._fire_tile_on_standing`) instead of waiting for that body's next
  turn — the ground arriving under somebody is as much a meeting as somebody
  walking into the ground, and a Red Candle aimed at an occupied square used to
  read as a click that had missed. Only the *tile's* effects run, not the cell's
  unit's: the body did not step on anything, so a mine it was already standing on
  has no more reason to go off than it had a moment before. Fire that annihilates
  on arrival (onto a mine) bills nobody.

  **The ground carries a HoverCard**, the same card an enemy, an item and a
  status get, instead of Godot's grey system tooltip — art, the name in its own
  colour, what it does, and the **clock as a pip**: `⏱ 2 games left`, which is the
  one thing about a burning square that changes between one look and the next. A
  square with both a unit and a tile on it answers with **one** card, because
  "what is on this square" is one question.

  **A bomb can be spent on any square**, not only on a body
  (`GameLoop2.bomb_cell`) — which is what makes Hot Bombs a way to lay fire in
  front of the stack and Brimstone a way to aim a cross down a lane. A click on
  an occupied square still routes through the body-aimed path, so the target
  reaches the blast, the boss rule and the `bomb_used` trigger unchanged.

  **And the squares an armed verb could be pointed at are actually visible.** The
  cell picker was built out of `flat` Buttons, and a flat Button skips its
  stylebox entirely: Red Candle's eight legal cells were legal, clickable and
  completely unmarked. They are drawn now, in translucent fills over a warm ring,
  so a body standing on a lit square still reads through the wash.

  **The tier list shrinks to fit its window.** The point of a tier list is the
  comparison between its rows, and a row you have to scroll to is a row you
  cannot compare — so `TierListScreen` measures the space it was given and picks
  the largest tile size the whole board fits at, re-fitting on every rebuild and
  every window resize. About 300 beaten games fit a 720p window; past the
  legibility floor it scrolls rather than going on shrinking.

- **Tile effects and units — the board grew a floor.**

  Two things can now be on a cell that are not a body: a **tile effect**
  (something done to the ground, which stays put and acts on whoever walks in)
  and a **unit** (something of the player's standing on it). They **layer** — a
  unit stands on a tile effect — which is why they are two sheets, two resources
  and two dictionaries rather than one with a flag. Neither *blocks* anything:
  a body walks in and whatever is there reacts. Full spec:
  [§17](docs/games-first-redesign.md).

  **Fire** (`tiles2.0`) puts +1 Burn on anything that enters it *or* starts its
  turn on it. The pair of triggers is the whole point — a cell that only bit on
  entry would be free to park on, and one that only bit at turn start would be
  free to walk through. It burns for **3 games**, not 3 turns: how many turns a
  game buys is read off the distance to the Amulet (§7.4), so a tile authored in
  turns would be worth three times as much out in the wilds as it is on the
  Amulet's doorstep — the same content, strongest where it is needed least. The
  generator **refuses** a Decay cell written in turns rather than reinterpreting
  it. It ticks on every game *resolved*, beaten or missed: the ground burns for
  the time spent, not for the result.

  **Landmine** (`units2.0`) goes off under whoever steps on it — and it is a
  **proxy bomb**, which is the whole reason it is a unit rather than a one-off
  trap. It spends none of your Bombs, but everything that modifies a bomb
  modifies it, because `bomb()` and a mine now go through one `_explode`:
  Brimstone widens the blast to the row and column, Sticky stuns what survives,
  Blood Bombs pays its Health, Hot Bombs leaves Fire behind. It inherits the rest
  of a bomb's terms too — a body it destroys is *destroyed, not defeated*, so no
  drop and no gold.

  **Fire and a Landmine annihilate each other**, whichever arrived second: the
  heat sets the mine off and the blast blows the fire out. That fact is authored
  in the two sheets' `Interactions` columns — from **both ends**, because the two
  are one event and the player looks it up from whichever half they are holding —
  and the runtime unions them, so an interaction written on one side only still
  resolves.

  **The enemies route around a minefield.** `path_blockers` answers `mines` as
  well as `enemies` and `cells`, and a lane is ranked on all three in that order.
  Mines rank **below** bodies deliberately: a body in the lane is a wall that may
  never move, a mine is a toll paid once. An enemy that treated them as equally
  bad would rather queue forever behind a boss than step on a mine, which is not
  caution, it is a bug that reads as one. So the stack goes around when it has
  somewhere else to be and straight through when it doesn't.

  Four pieces of content reach the new ground. **Scroll of Fire** gained the
  middle clause its prose already promised (`apply_tile fire front`), so the
  strip that just burned the front line keeps burning whatever steps into it.
  **Red Candle** (Common, `Charged, 1`, shop) is the first item aimed at
  **ground** — `target=tile` is the tile-side twin of Staff of Flame's
  `target=enemy`, the board arms a cell picker instead of lighting up the stack,
  and `cols=2-3` fences the reach (never column 1, where it would be a free hit
  on whatever is already swinging; never the back, where nothing would cross it
  before it burned out). **Hot Bombs** (Uncommon) leaves Fire on every cell a
  blast covered — widened by Brimstone for free, since what it reads is the blast
  rather than the target, and reaching a mine's blast for the same reason.
  **Landmines** (Uncommon) lays one mine per game finished, on a cell with
  nothing on it at all.

  **Keywords.** An item or a scroll names a mechanic and has no room to explain
  it, so the card now carries a Slay-the-Spire-style strip of hover chips under
  its description — one registry (`scripts/ui/Keywords.gd`) covering statuses,
  tile effects and units alike, because from the reader's side "what is that?" is
  one question. Each kind writes its own words; the registry only finds the
  mentions. Matching is on word boundaries, so "Burn" does not light up inside
  "Burning Blood".

  On screen, a tile effect is a shallow strip hugging the **bottom edge** of its
  cell drawn **above** the bodies — above, because a fire tile under a 2x2 would
  be one nobody can see; shallow, because the point is to read the ground without
  losing the body standing on it. Units draw **under** the bodies, being on the
  floor. Neither steals a click: a per-cell hover sits in the lower layer, so a
  cell with a body on it answers with the body's card and bare ground answers
  with the ground.

  (`TileEffectData`, not `TileData` — Godot ships a native `TileData` for
  TileMaps and a `class_name` that shadows one is a parse error that takes the
  whole `.tres` folder down with it. The sheet, the data folder and the ids stay
  "tile".)

- **Marked is Burn-shaped now.**

  Its player side was a `clause` — a tax ANDed onto every enemy's goal — and is a
  **`demand`**: get X achievements, or take 3 Damage. The enemy side is untouched,
  so the status keeps the thing that made it interesting (a cost on your side, a
  payout on theirs) with the cost made of the same stuff Burn's is. The sheet's
  prose column had already said this; only the machine-readable cell was still
  describing the old one.

  The two demands differ in one place, and it is the place that matters: Burn is
  capped at 3 because its condition gets *easier* per stack on an enemy, while
  Marked's asks for more the deeper it goes on both sides and needs no ceiling.

  With that change nothing shipped has a player-side `clause` any more. The mode
  is still real and still implemented — `status_clauses` and
  `_tick_player_clauses` *are* it — so `test_statuses.gd` registers a synthetic
  status to exercise it rather than borrowing whichever shipped status happens to
  be shaped that way this month.

  Regenerating also picked up **Staff of Flame at `Charged, 2`** (down from 3),
  which the sheet had already been changed to.

- **Two ways to set something on fire, and Burn's two curves pulled apart.**

  **Burn on the player now asks for X items skipped, not 4-X** — so it costs
  *more* the deeper it stacks, and `Max: 3` is the ceiling on that. The enemy
  side keeps 4-X, which makes the two halves one rule read from either end of the
  board: Burn is bad for whoever is carrying it. Pay it down on yourself and the
  next game's asking price drops; pile it onto an enemy and its way out gets
  cheaper.

  **Scroll of Fire** (Hack, Negative) — `apply_status burn 3 player;
  apply_status burn 3 front`. The first scroll whose Effect cell is two clauses,
  and the first that burns the reader: +3 Burn on you and +3 on everything
  touching the front column. The scroll DSL grew semicolons for it (the same
  separator every other sheet's Effect column already used) and two targets:
  `player`, and `front` — the column that strikes next, tested with the same
  `in_front` the strike itself uses, so "about to hit me" and "what this lands
  on" cannot drift apart. You read it for the second half; the first half lands
  whether or not the room has anyone in it.

  **Staff of Flame** (Mewgenics, Rare, `Charged, 3`) — the first relic that has
  to be **pointed at something**. `target=enemy` is the sheet asking for a body
  to be picked rather than named by a rule, and `ItemData.wants_target()` already
  recognised exactly that word, so the item declares "aim me" in the same breath
  as what it does. The pack arms it, the board aims it — the same arm-then-aim
  bargain the Bomb makes, with the bodies lit and a Cancel that appears only
  while one is armed — and the **click** is what fires it and empties the bar. An
  item that spent its charge on the button press would be charging for a picker
  you then cancelled. A boss is a legal target, exactly as it is for a bomb: what
  a burned boss loses is its damage, not its condition.

  Alongside them, **Wand of Wishing regenerated as the sheet now has it**:
  `Usable, 1` rather than `Charged, 6`. The `.tres` had been carrying the old
  Type since before the sheet was edited — the drift only showed when the
  generator was next run.

- **Burn: a status that charges you, and a goal you can get out of.**

  Every status so far was a challenge you opted into and were paid for. **Burn**
  (Brutal Orchestra) is a debt, and it took two new modes to say so.

  On the player it is a **`demand`** — "You must skip or trash 4-X
  items/upgrades, or take 3 Damage". It is a row on every report step like a
  standing goal, and the only row whose *unticked* state does something: the 3
  Damage lands at the **end of the game, after the enemies have swung**, through
  the same resolver their swings use, so the tries that game granted absorb it
  before Health does. Answering it sheds a stack; missing it does not, so it
  keeps asking. A run the enemies already ended is never billed — there is no
  after for a game that killed you.

  On an enemy it is an **`instead`** — that body's goal grows "or instead skip or
  trash 4-X items/upgrades", and doing that clears it: same hit, same drop, same
  gold. What it does **not** do is go on the record. The enemy's condition was
  never set, so nothing is banked against the game it happened at (no "beaten in
  \<game\>", no note — the row deliberately carries no Notes button), and no
  player `clause` ticks off it either, since a goal nobody met carried nothing to
  satisfy. The two are separate lists through the whole report for exactly that
  reason. **Never on a boss:** a boss's goal is the whole of what the boss is.

  **It runs backwards, which is the design.** 4-X is 3 items at one stack and 1
  at three, so Burn gets *easier* the deeper it stacks — a fresh one you cannot
  pay bites for 3, and biting is what stacks it until you can. `Max: 3` is the
  floor under that, and the sheet's **`Stackable`** column learned to carry a
  ceiling for it, enforced on the way up for the player and for a body alike.

  Two sheet columns did real work here. **`Decrease`** ("N/A", "On Completion")
  is now the one place a status says how it depletes — the generator reads it as
  the truth and checks the older per-cell `decay` flags against it, so a status
  cannot say one thing in its column and another in a cell. And **`take_damage
  N`** joins the reward DSL as the counterpart to `lose_hp`: damage that resolves
  on the battlefield rather than a bill that comes straight off Health.

  In combat Burn **halves what the body deals** — a multiplier, so it is flat at
  every stack, and rounded the way every other hit is (2 and 3 come down to 1; a
  1-damage body is already as small as a hit gets). Nothing hands Burn out yet,
  the same as Marked: the vocabulary is there for a location, an item or an event
  to reach for.

- **Four items, two games, and the difference between a grant you keep and one
  you are renting.**

  **Lucky Hat** (+1 Luck), **Bionic Face Plating** (+3 Speed) and **Fortune
  Necklace** (+1 Gold on every game selected) are Mewgenics trinkets, and all
  three are fragile: an enemy attack that costs Health destroys them. **Ban
  Hammer** (Yet Another Zombie Survivors, +2 Bashes) rounds the set out and
  brought nothing new with it.

  The interesting half is what "passive" had to start meaning. `stat_bonuses`
  was already rented — Clover's Luck comes off with the clover — but a status
  had only one door into the run, `apply_status`, which hands it over and lets
  go. That is right for The Mark, whose Speed is yours after the item is gone,
  and wrong for a plating you can lose. **`status_bonuses`** is the second door:
  stacks held up by the inventory slot, put on by `add_item` and taken back by
  `remove_item_at`, taking back only their own share so a Speed gained any other
  way survives. The sheet says `passive_status: speed 3`; the Collection lists
  it next to the stat bonuses, because "what does holding this give me" is one
  question.

  **What breaks them is narrower than "damage" in both directions.** Shields
  absorb first (§3), so a swing they eat whole costs no Health and breaks
  nothing — the trinkets are protected by the same thing protecting you. And the
  Health a failed try charges, an event's bill, a curse's drain: all Health lost,
  none of them an attack, none of them break the hat. `health_lost` fires on all
  of it (that is what Piggy Bank is for), so `GameState.change_hp` now carries a
  `source` and `GameLoop2._take_hit` — the *only* path an enemy's damage reaches
  Health by — is the one caller that tags it as a swing. One swing that gets
  through breaks every fragile item at once.

  **Stigmata** now generates from the sheet's Effect column like everything else,
  spelling out both halves of what it pays: `gain_max_hp 2; gain_hp 2`. The raise
  fills its own container and the heal lands on top, so a full player still reads
  +2 Health — there is nowhere for the second half to go — and a wounded one gets
  four.

  **Arms of God** (Brotato, Diablo, Vampire Survivors) and **Chosen Garden**
  (Balatro) join the graph, along with Slay the Spire → **Montabi**: 854 games,
  1227 connections, and the draw.io map still agrees with the sheet about every
  one of them.

- **The UI stopped asking the host what a ⚔ looks like.**

  The item the last change uncovered, now closed. The UI is drawn out of about
  seventy symbols — ⚔ ☠ ⚡ 🏆 🎲 🍀 ⛏ ⚗ — and Godot's built-in font has exactly
  two of them (`−` and `≈`). A miss is answered by searching the **host's**
  installed fonts, during shaping, and the answer is not cached: ~2 ms every time
  a Label carrying one was created. **14.9 ms → 5.0 ms** for a Label carrying ten
  of them.

  It also means those glyphs were being drawn from whatever the player happened
  to have installed. The colour-emoji font a modern desktop ships **ignores the
  tint the theme asks for**, which is why the green SHOP badge had a blue trolley
  in it and the amber verb row had a gold trophy. They are monochrome now and take
  the colour they are given, which is what the design was always asking for.

  `fonts/` holds four Noto subsets — **72 glyphs in 28 KB**, only the characters
  the source actually draws, OFL, built by `tools/build_glyph_font.py` from the
  @fontsource packages. The script scans `scripts/**/*.gd` for what to include and
  *reports* anything it cannot cover rather than skipping it silently; today that
  is `▁` alone (no Noto web subset ships Block Elements), which still renders.

  **Three traps in what should have been a two-line change, all found by
  measuring:**

  - Declaring the subsets as theme fallbacks only got 15.4 → 12.4 ms. The base
    font runs its own system search on a miss and runs it **before** the
    fallbacks, so the expensive thing still happened. Turning that off on the
    base and putting a system-searching font at the **end** of the chain gets
    4.5 ms — and keeps the safety net, so a player's note in any language still
    renders off the tail.
  - The subsets' own vertical metrics then grew every line in the game by 9px,
    because Godot takes a font's height to be the **maximum** over the whole
    fallback chain. That grew the overworld by 63px and broke the "fits a 720p
    window" tests — which is exactly what those tests are for.
  - Matching the metrics by *ratio* fixed size 14 and broke 10, 12, 13, 15 and
    22, because Godot takes the **ceiling** of size × ratio and a rounding error
    lands differently at different sizes. The subsets are rescaled onto the base
    font's exact em grid (4096 upem, ascender 4378, descender 1200) instead, and
    a test now checks every size the UI uses.

- **The page stopped redrawing things that had not changed.**

  The last of `docs/performance-backlog.md`'s measured items: `Overworld2._refresh()`
  tore down and rebuilt the pack strip, the route strip, the board, the offering,
  the verb chips and the standing checklist on **every** loop signal, and
  `GameLoop2` emits 23 of those, several inside one resolve. **19.5 ms → 6.6 ms**
  per refresh, measured on a real run at the offering.

  **The measurement moved the whole plan.** The backlog blamed the offering cards
  and the pack strip; they are 1.5 ms and 0.3 ms. Half of the 19 ms was **five
  small verb chips** — ⛏ Bash, ⚡ Dash, ⚗ Transmute, 🎲 Scramble, 🍀 Luck — at
  10.9 ms. The same five chips in plain ASCII are 0.6 ms. The project ships no
  font file, so those glyphs miss Godot's built-in font and every newly created
  Label re-runs the system fallback search for them: about **2 ms per Label with
  a glyph in it**, paid on every rebuild. That is now item 1 of the backlog in its
  own right, since it is a cost on every screen and not only this one, and the
  fix for it is an asset decision rather than a code one.

  **Guards, not a signal split.** The backlog proposed deciding per emit site
  which parts of the page need repainting. Each of the three expensive sections
  instead keeps a signature of what it last drew and returns early when it would
  draw the same thing again. The difference matters: a split has to be re-judged
  every time an emit site is added, and forgetting one leaves a strip quietly
  showing a number that has moved — which is precisely the bug the comment on
  `_refresh_stats` records, a HUD strip repainting while the board waited, so a
  Hollow Heart off a kill-drop raised Max Health with nothing on screen saying so.
  A signature cannot rot that way: every signal still reaches every section, and
  each section still asks the same question about its own inputs. Nothing about
  the signal wiring changed, so the board's hero still repaints on `stats_changed`
  exactly as that comment requires.

  | | before | after |
  |---|---|---|
  | `_refresh_select_stats` | 10.0 ms | 0.003 ms |
  | `_populate_standing_checklist` | 3.0 ms | 0.005 ms |
  | `_render_controls` | 1.9 ms | 0.001 ms |
  | **`_refresh()`** | **19.5 ms** | **6.6 ms** |

  The remaining 6.6 ms is the board (2.3 ms) and the offering cards (1.3 ms),
  both left alone: the offering's cards carry a shop tooltip that reads live shop
  state, and a signature covering that is a wider promise than it is worth today.

  The one way a guard goes wrong is another function writing into the same
  container, leaving a signature describing content that is no longer there.
  There are exactly two, and both invalidate by hand: `_refresh` empties the
  controls row itself on the start panel, and the report step takes over the
  checklist box. Both have a test. Ten went in altogether, one per value in each
  signature, because the failure being guarded against is a value the rebuild
  reads and the signature forgot.

- **Two hot paths that were doing the work twice.**

  Items 1, 2 and 4 off `docs/performance-backlog.md`, measured before and after
  with a throwaway driver (`.claude/skills/verify/`) the same way the atlas
  numbers below were.

  **The star chart ran the whole sky once per star layer.** With a route on it
  the sky is drawn in three passes — scenery, then the roads, then the games the
  roads run between — so the corridor crosses the 700 stars it has nothing to do
  with and still tucks behind the cover art of the ones it does. That split is
  right and stays. What was wrong is how each pass found its half: it iterated
  all 852 stars and `continue`d past the ones belonging to the other pass, so
  drawing 852 stars cost 1704 iterations and 1704 `on_route()` dictionary hits,
  on every redraw, which is every pan step. The membership question is asked once
  per star now, into two `PackedInt32Array`s that each pass walks
  (`AtlasView.star_indices`). A/B'd in one process on one route: **1.245 ms →
  0.027 ms** per redraw, or 0.122 ms on the redraw right after the route moves
  and the partition is rebuilt. The four sites that invalidate the road now go
  through one `_clear_route_cache()`, because a partition outliving its route
  would draw last hop's corridor and there were three things to wipe at each of
  four places.

  **The route DAG was rebuilt by every caller that asked for it.** `bfs_distances`
  has been memoized for a long time, but the layer-and-edge assembly on top of it
  was not, and opening the map asks for it five times (the distance label, the
  ladder, the legend, and `shortest_distance` from every node card). Now memoized
  on `RunGraph` beside the BFS cache, and safe on exactly the same terms: nothing
  either depends on moves during a run — Bash takes a game out of the *offering*,
  not out of the map, and Transmute repaints which game sits on a node without
  touching an edge — so both are wiped together by `invalidate_cache()` when the
  filter changes. **0.317 ms → 0.001 ms** warm; one map open went from ~1.6 ms of
  DAG assembly to 0.012 ms. It lives on `RunGraph` rather than on the modal (the
  backlog's suggestion) because `AtlasView._build_trail` rebuilds the same route
  on every refresh too, and only the shared version catches that.

  Caching it meant the result is now a **shared** Dictionary, and one caller was
  writing into it: `route_dag_via` set `waypoint_depth` on what
  `shortest_path_dag` returned, which was free when every call rebuilt it and
  poison when there is one copy — the next unpinned caller would have read a join
  that wasn't there. It builds a wrapper around the shared arrays instead, and
  there is a test for exactly that.

  **The quadratic edge loop in the same function measured flat, and is worth
  writing down.** `Array.has()` against the next layer looked like an obvious
  linear scan inside a loop over each node's ~28 neighbours. A/B'd against the
  same route in the same process it was 0.322 ms with `Array.has()` and 0.308 ms
  with a `Dictionary` set per layer — noise. The layers of a real route are two or
  three games wide, not the 15+ the degree curve suggested, so the scan was never
  scanning anything. The set went in anyway (strictly better, measured no worse)
  but the memo was the entire win.

  **Three dead functions deleted** — `GameLoop2._pull_from_stack`,
  `Collection._item_rarity_color`, `Collection._all_enemies`. The scan that finds
  them is written into the backlog now, and comes back clean.

- **Seven Isaac relics, and the five pieces of machinery they needed.**

  Piggy Bank, There's Options, The Mark, Stigmata, Charm of the Vampire, D10 and
  Wooden Nickel had been sitting in the `items2.0` sheet with a Description, a
  Rating, a Type and an **empty Effect cell** — so the generator emitted seven
  `.tres` that read correctly on the card and did nothing at all. They are wired
  up now. Two of them cost nothing new (Stigmata is Max Health that arrives full
  plus a Bash; Wooden Nickel is a 50% `chance` on the shortest charge bar in the
  game). The other five each named a moment or a rule the games-first loop did
  not have, and that is most of what this change is.

  **`health_lost` — a hook for Health leaving, not for damage arriving.** Piggy
  Bank in Isaac reads "whenever you take damage"; here Shields absorb before
  Health does (§3), so a swing they eat whole is damage taken and costs nothing,
  and a relic paying for it would be paying for the absence of an injury. The
  card was reworded to **"Whenever you lose Health"** and the hook fires from
  `GameState.change_hp`, the choke point every drain in the 2.0 build funnels
  through — an enemy's overflow past the shields, an event's bill, the Health a
  failed try costs. It reports what *actually* came off rather than what was
  asked for, so a 5-point drain against 2 Health left is one loss of 2.

  A failed try is the one Health loss in the game that can be **taken back**, and
  the undo button would otherwise have been a coin press: tick, untick, tick,
  untick, +1 gold a cycle. `log_attempt` now measures what the tick paid out and
  `undo_attempt` hands it back, so "refunding exactly what it spent" includes
  what it earned.

  **Incremental relics, counted per copy and drawn on the art.** Charm of the
  Vampire pays every third defeated enemy, which needed both a counter and an
  `enemy_killed` hook to count (a *bombed* body is destroyed rather than
  defeated and never reaches `_defeat`, the same rule that decides whether it
  pays gold). The counter lives on the **inventory slot** — `ItemData.counter_value`,
  beside `current_charge`, round-tripping through saves the same way — and not
  on the run. That is Slay the Spire's rule and it is the right one twice over:
  two copies each count the same body once and each pay out on their own third,
  and a copy picked up mid-run starts at zero instead of inheriting a tally it
  was not present for. The number is drawn **bottom-right on the item's own art**,
  where the Spire draws it, because a relic counter belongs to the picture of the
  thing rather than to a caption beside it — just the count, since the threshold
  is what the item's text already says and only the count moves.

  **A dropped item is a chest — a Small one.** There's Options says "increase the
  chest size dropped from bosses by 1", and the build had no chest on that path
  at all: a defeated body rolled one relic and `ItemDropModal` asked Take it /
  Leave it. Restating that as *choose 1 of 1* is what let the relic exist without
  a second reward path. A boss's drop is now worth **1 chest point + 1 per copy**
  held, spent on the same size ladder a `[chest reward]` walks
  (`Data.chest_reward_sizes`), and at 2 or more the modal grows a row of cards to
  pick between — still one relic taken, still one "Leave it", because the answer
  to a chest is *which one* and not *how many*. Points past a Huge overflow into a
  second chest, so a stack keeps paying instead of running off the end of the
  ladder. Nothing changes for an ordinary body: 1 point, Small, the same single
  item and the same two buttons.

  **The D10 re-rolls the board against itself.** Every non-boss body is replaced
  by a fresh roll at *its own* tier and game type, so the board keeps its weight
  and only its faces change — the point of the relic is that the stack is a list
  of goals and one of them is a goal you cannot or will not do, not that a High
  board can be laundered into a Low one. The slot survives the swap (the square
  it stands on, and the statuses hung on it); Health does not, because Health
  here is goal completions and the goals just changed. Bosses shrug it off the
  way they shrug off a bomb. A re-rolled body can be a different *shape*, so the
  board is re-seated afterwards through the same rule a Mine-r Construction
  gain/loss uses — factored out of `sync_grid_bounds` as `_reseat_stack`.

  **`pools`, and shop items that turn up in shops.** The sheet's `pools` column
  was authored but never read. It answers a different question from `tags`
  (*where a relic is drawn from*, not what it is about), and `shop` is the first
  entry wired up: an item in it counts **double** when a hub's shelf is rolled,
  so Piggy Bank and There's Options are twice as likely to be standing at a shop
  as anything else of their rarity. A weight rather than a filter, deliberately —
  Isaac's shop pool is a separate table nothing else reaches, but against thirty
  relics and at most ten hubs a run, that would have made every shop the same two
  items every time. A shop relic still drops off a body, and a shelf can still
  come up three ordinary ones. `devil_room` and `angel_room` are stored for the
  encounters that will read them and are inert until those exist.

  Five cells of sheet-vs-`.tres` drift were folded back **up** into the
  spreadsheet on the way past (Lunch and Mango's descriptions, three blank tag
  cells) — hand-edits the sheet had never heard about, which the first
  regeneration after this commit would otherwise have thrown away.

- **The star chart stopped doing the same work twice.**

  Four fixes to the hottest loop in the project, found by measuring rather than
  reading. All four are in the per-star path the sky is drawn through, and
  together they take a redraw of the Collection's 852-star catalog view from
  **~10.9 ms of pure lookup to ~1.9 ms** — from two thirds of a 60fps frame,
  before anything is drawn, to a tenth of one.

  **`has_record(i)` recomputed a colour that was already in hand.** It is defined
  as `star_record_color(i).a > 0.0`, and the draw loop asked for both, one line
  apart — so every star made the GameStats round-trip twice. `record.a > 0.0`
  instead: **6.5 → 2.9 ms** over the sky.

  **`GameStats.get_stats` allocated a Dictionary for every game with no record**
  — which is most games — because it returns a fresh `{"beaten": 0, "amulets": 0}`
  on a miss, and both counts went through it. A pan across the chart was minting
  thousands of throwaway dictionaries a frame for two integers that are almost
  always zero. `beaten_count` and `amulet_wins` read `stats` directly now;
  `get_stats` keeps its contract for anything wanting the record as a whole.
  With the fix above, the pair costs **1.9 ms** where they cost 6.5.

  **`cover_count()` walked the whole sky on every redraw, for a HUD label.**
  It is called from `_refresh_hud`, which `_redraw` calls — so every pan step,
  zoom step and *selection change* re-counted 852 stars to decide whether the
  readout says "overview" or "12 showing art". It is memoized against the camera
  now (scale, offset, canvas size), since that is the only thing that can move
  it: **1.97 ms → 0.001 ms** on every call after the first.

  **And the per-star filter test was always true.** `passes_filter(i)` cost
  2.4 ms a pass answering "yes" 852 times: the catalog view rebuilds the sky out
  of the survivors (`_relayout` → `_filtered_ids`), so every star in `layout`
  passes by construction, and outside the catalog there are no filters at all.
  The `filtered_out` branch it fed — dimming a star in place — was unreachable
  code left from the older design where filtering dimmed the sky where it stood
  instead of re-laying it. Verified before removing: across eight filter
  settings, in both layout modes, every drawn star passes.

  **The rest of the pass is written up in `docs/performance-backlog.md`** — the
  double star sweep when a route is on the sky, `RunMapModal.map_data()` being
  uncached, `Overworld2._refresh()` rebuilding the whole page on every loop
  signal, three dead functions, and the case for splitting up a 5218-line file.

- **Nothing on the board belongs to a game any more.**

  There is no such thing as "this game's enemy". A card advertises what will walk
  on if you take it; once it has walked on it is a follower like every other body,
  and that is the whole of the relationship.

  **What that was, and what it cost.** `GameLoop2.current` pointed at the
  advertised body for the entire game, and four separate systems deferred to it.
  The board drew it in its own accent with a washed fill and a NOW PLAYING tag,
  and **refused to aim Push or Bomb at it** — so the one enemy standing right in
  front of you was the one enemy you could not remove. The report checklist gave
  it an emphasised **Goal —** box at the top and listed everything else under
  "Also cleared", as though clearing a goal you owed from three games ago were a
  different kind of act. The report panel drew its portrait beside the game's box
  art, pairing them. And `beat_game(goal_met)` folded two different claims into
  one flag.

  All four are gone. `current` is replaced by **`arrivals`** — a list of the
  handles that walked on with the game in play, kept for exactly two jobs
  (superseding them on a Scramble, and naming what landed) and consulted by
  nothing that makes a body special. `is_current` is out of `BattlefieldView`,
  `EnemyInfoCard`, `DevTools` and the board's `refresh()` signature entirely.

  **Beating the game and clearing an enemy are two separate claims now.**
  `report(beaten, fulfilled)`: pressing **✓ Completed Game** says you played and
  finished the real video game — that is what the run's beaten set, the
  repeat-visit Dash, the lifetime tally and the Amulet win read. What you did to
  the bodies is the tick boxes, one per enemy on the board, arrivals among them in
  board order. So you can finish a game and leave everything following you, or
  clear three old goals during a game you never finished, and the report says
  exactly that. It could not before: missing the goal box meant the game did not
  count as beaten either.

  **`clear_amulet` takes nothing off the board.** It used to defeat the body
  standing at the Amulet, because that body was the game's own. Whatever is
  standing there was already dealt with by the report that got you there — ticked
  or not, like every other enemy — so winning simply ends the run.

  **The report panel is the cover, centred.** The 72px enemy portrait beside it
  is gone; what is on the board is drawn on the board.

- **Hover cards everywhere, an armed Bomb, and three things that were in the
  way.**

  **Everything on the page describes itself on hover, as a card.** An enemy, a
  status, a relic and the enemy-turns readout all open something when clicked,
  and all four spent their hover on `tooltip_text` — grey system chrome with a
  wall of plain text in it, on a page that is otherwise entirely hand-drawn. The
  information was there and nobody read it. They carry a condensed version of the
  card now (`HoverCard` + the `HoverPanel` / `HoverBox` wrappers Godot's
  `_make_custom_tooltip` requires): the art, the name in the thing's own colour,
  its statuses as **pips** rather than three more lines of prose, and the one or
  two lines that decide something. A status's model comes from
  `StatusData.hover_card`, beside the string it replaces, so the board, the enemy
  card and the hero strip cannot describe the same status differently.

  **The offering gets none of it** — no card and no tooltip on an offered cover
  or a start card. The hover line under the cards already carries the enemy's
  portrait and its goal, and a popup over three covers while the mouse crosses
  them is the noisiest possible way to repeat it. The cards are for scanning.

  **Bomb is armed and aimed, like Push.** It used to fire on the button press, at
  whatever was still `selected_instance` — routinely a body clicked several turns
  earlier to read its card, so the charge went into an enemy the player was not
  looking at. Pressing `✸ Bomb` now arms it, clears the selection and lights every
  body it could land on; the CLICK is what spends the charge and disarms it. One
  press, one bomb. Arming either verb puts the other away.

  **And the instruction is the BOARD, not a caption.** The toolbar used to print
  "click an enemy" in its target slot while a verb was armed. It doesn't: the
  bodies you can click are the ones lit in `ARMED_TINT`, and a verb that has to
  caption its own highlight is a highlight that isn't working.

  **Exit Game only works on the main menu.** It is moved to the bottom-right
  corner in code, and that appended it *last* — above `%ModalLayer`, where every
  screen the menu raises mounts. So the door out of the application sat on top of
  the character picker, the Collection, the Atlas and the manual, live and
  clickable straight through their own backdrops.

  **The start picker's 🗺 Map opens the ladder alone**, no star chart. The
  question on that panel is "which of these three roads", the ladder is the answer
  to it, and 852 stars with nothing on them to orient by — the run has no position
  yet — is not. The chart is one `✦ Star chart` button away on the window itself.

  **The pack lost its "🎒 Inventory" heading**, and that turned out to be a bug
  fix rather than a tidy-up. A bordered strip of relic and scroll tiles is its own
  label, and the row it was spending was the page's entire margin: measured, the
  overworld was **626px of a 625px budget with the heading on**, before a shop was
  even mounted under the board.

  **Which uncovered a real one.** `test_the_page_still_fits_the_window_with_a_shop_on_it`
  mounted `hubs[0]` and stopped — one hub out of ten, chosen by the random graph.
  The shop's name was a Label with no clip, so its width was the hub's NAME
  length; that became the shop panel's minimum, then the right column's, and it
  took the room straight out of the LEFT column, where the checklist's goal text
  wrapped onto extra lines and grew the page. **"Enter the Gungeon", "Vampire
  Survivors", "The Binding of Isaac" and "Spelunky Classic" ran the overworld off
  the bottom of its own 720p window by up to 35px; "FTL", "Hades" and "Balatro"
  did not** — so the same bug passed or failed depending on the seed, which is
  what the intermittent failures were. The name is clipped and asks for no width
  of its own now, and the test walks every hub instead of the first one.

- **The Amulet is named from the first screen, and the header bar stopped eating
  the screens under it.**

  Four fixes to the map, the atlas and the offering, reported off one screenshot.

  **The Amulet is not a secret any more.** The choose-your-start panel used to
  give away the DISTANCE and nothing else: its cards read `5 games from the
  Amulet`, the map a card opened drew the destination as an unnamed
  `The Amulet — ???` rung that refused to open a card, and no star chart was
  raised from a start card in case the sky pointed straight at it. All of it is
  gone. `RouteLadder.node_name` names every rung, the `hide_amulet` option is
  deleted from `RouteLadder` / `RunMapModal` / `Overworld2.preview_map`, and the
  picker's heading, each card's distance line and the card's popup all quote the
  game itself (`Overworld2.amulet_name`, `_start_distance_text`). The one thing
  the flag was still doing usefully — suppressing the route pin before the run
  has anywhere to detour from — is now asked directly
  (`RunMapModal._run_has_position`).

  Choosing a start is a routing decision, and a routing decision made towards an
  unnamed box is made on the shape of the road alone. The games the road runs
  through, and the one it ends on, are the substance of it.

  **The enemy's portrait is back on the offering's hover.** It was an 84px framed
  panel with 64px art, then a bare line with no art at all — and the line alone
  lost the thing a hover is fastest at, since a player recognises a body by its
  picture long before they read its name. It is back beside the line, and it is
  **free**: the art is given a width (`Overworld2.HOVER_ART`) and takes its
  height from the row, so the hover row is the same 22px it was with nothing on
  it. That matters because the page has about four pixels of slack against its
  720p budget on its worst case (three arcade machines under the board), and a
  row that reserved 30px of height for art blew it — which the existing
  `_assert_fits` tests caught. It is hidden under the Runic Dome, on a free game,
  and on the stay-or-return pair.

  **The star chart had no way off it.** `AtlasView` is a full-screen page whose
  first row is its own header — the title, the search box, the ✦ jump buttons and
  Close. The run's header bar is pinned to the top of the screen on a layer above
  it and is opaque, so a chart drawn from y=0 had that entire row covered and no
  way back to the run but the Esc key. (A comment claimed the Atlas was mounted
  at layer 140, above the bar. It never was — it is a `top_level` child of the
  page.) The chart now starts below the bar, and its Close says where it goes:
  `←  Back to the run`.

  **And so does everything else the run raises.** `_fit_page_under_header` used to
  inset the page and nothing else; it now publishes the bar's height as
  **`ModalScaffold.reserved_top`**, and `ModalScaffold.centre` centres a modal in
  the band below it and never lets a panel's top edge start above it. That is the
  overlapped title in the screenshot: the game-choice popup grew past its nominal
  700px on a tall route, was centred on the whole viewport, and had the name of
  the game being decided about sliced off. `RunMapModal` reads it too, for its
  size, its opening position, its drag clamp and its node card. It is cleared
  when the page leaves the tree and while the bar is down, so the main menu's
  screens and the Collection are untouched.

- **The start band slid down a hop: starts are now 4–7 games from the Amulet,
  not 5–8.**

  `RunGraph.MIN_PATH_LENGTH` / `MAX_PATH_LENGTH` are 4 and 7. The whole window
  moved rather than just the floor, so the panel still spreads its cards over
  four possible lengths and still offers a genuine long/short choice — the run
  just starts closer.

  **Why the nominal number was never the real one.** The route a player walks is
  rarely the shortest one: the offering shows three of the node's neighbours
  (`Overworld2.BASE_OFFER_COUNT`) out of a mean degree near 28 on the full
  catalog, so the card that advances toward the Amulet is often simply not on the
  table. Simulated against the real graph — greedy play, always taking the offered
  card closest to the Amulet — a nominal 5-hop start costs a median of 15 games
  played, not 5.

  **What actually moved.** Almost all of it is on the SHORT card. Taking the
  shortest card offered, median games played falls 15 → 11 on the full catalog
  (12 → 10 owned-only). Taking the LONGEST card is unchanged — median 19 either
  way — because the drift above swamps the one hop the ceiling lost. So the band
  shift sharpened the rush option and left the scenic route alone.

  **And the short card is hotter now.** `RunDifficulty.FAR_HOPS` is still 5, so a
  4-hop start opens *inside* the 2-turn Closing band with no calm game at all,
  where a 5-hop start got one. Calm games over a rushing run fall from ~3 to ~0.5.
  Shorter and fought faster from the first card, which is the trade the band shift
  buys.

  The Amulet pool does not pay for it: the floor is what governs which games can
  be the goal, and lowering it only widens the pool (owned-only, the share of
  Amulets that can field the full two-genre panel goes 93% → 100%).

  One test moved with it. `test_run_map.gd::test_the_route_fits_the_window_it_opens_in`
  asserted that a fit which bottoms out at `FIT_ZOOM_MIN` must *overflow* the
  window. That was only usually true: `fit_zoom` aims at `FIT_SLACK` (96%) of the
  room, so a route whose true fit lands just under the floor is clamped back up
  and then still fits inside that margin. Rare at 5..8 depth, ordinary at 4..7. It
  now asserts the ladder FILLS the room to within the slack, which is what "the
  fit ran out of room" meant and is true of both cases.

- **Nothing spawns alone any more: every game brings an escort.**

  Combat was too easy in exactly one way. The stack only ever grew when the
  player *failed*, so a player who kept meeting goals never had a board to
  survive at all — and §7.3's footprints, §7.4's turn ladder, Stun, Push and the
  bombs were all machinery aimed at a board that was usually empty.

  Committing to a game now stands **two** bodies on it: its own enemy, and an
  **escort** rolled from the very pool that enemy came out of — same game type,
  same tier, same widening (`GameLoop2.roll_escort`). Another enemy that could
  have been waiting there.

  **Only the named enemy is the game's.** Beating the game and meeting its goal
  answers for that one alone; the escort keeps its own goal, which is an old goal
  from the moment it lands and clearable during any later game like every other
  follower's. So a game played *perfectly* still leaves one body on the board.
  The stack is the baseline now rather than the punishment — and none of it
  touches a number: no enemy hits harder, nothing has more Health, and every
  existing answer to a follower (goal, bomb, Stun, Push, fulfilment) works on it
  unchanged.

  **Two carve-outs, both so one difficulty rule is felt at a time.** A **boss
  spawns solo** — a tier change already swaps in the heavier, bomb-immune pool at
  triple gold, and doubling the bodies on that round would merge two steps into
  one wall. And **Scramble rerolls the pair**: `choose_game` supersedes the game
  in play, and the escort came with the enemy being rejected, so it leaves with
  it. Without that, a D6 charge would be a way to *buy* bodies, one per press —
  which is what `GameLoop2.current_escort` exists to prevent, and why it is
  written into the save.

  **The card promises the count and withholds the name.** The escort is rolled on
  ARRIVAL, not with the offering, so an offered card says `⚠ One more enemy spawns
  with it — which one is rolled on arrival` (the Runic Dome does not hide that —
  it was bought to hide *what* is waiting, not *how many*), and the body is named
  in the log and a notification the moment it lands. How many bodies a card puts
  on the board is part of the routing decision; which ones is not.

  Spelled out in [§7.5](docs/games-first-redesign.md) of the spec, and in the
  manual's *Enemies are goals* chapter.

  **Fixed while it was in there:** the battlefield heading counted the game in
  play twice. `_stack_summary` added 1 for the current game on top of
  `stack.size()`, from the era when that enemy waited off the field — it has
  stood on the board with everything else since §7.2, so the line read "3 closing
  in" over a board holding two. It was invisible while a playing board usually
  held one body; an escort beside it made the off-by-one look like the escort.

- **Statuses grew a combat side, Dexterity split in two, and `+X Small Chests`
  became one chest that gets bigger.**

  A status used to be goals and nothing else. It never touched a number on the
  board — that was the whole design of §13, and it is why an item, a location or
  a scroll could reach into the run's difficulty without any of them knowing what
  a goal is. That half is unchanged. What is new is a **combat side** beside it:
  three columns in `statuses2.0` (`Combat`, `EnemyOnly`, `Enemy Combat Effect`)
  and four numbers a status can now move.

  | | Goal side (unchanged) | Combat side (new) |
  |---|---|---|
  | **Strength** | difficulty increased X times | deals +X damage |
  | **Speed** | beaten in 1+(1/2)^(X-2) hours | closes +X tiles per turn |
  | **Dexterity** | X bosses beaten without getting hit | +X Shields |
  | **Marked** | you get X achievements | takes double damage, ignoring Shields |

  **Dexterity split.** The old Dexterity was a time-window buff wearing a name
  that described nothing about it. The window kept its goal, its curve and its
  reward and became **Speed** (Mewgenics); **Dexterity** is now the Slay the Spire
  relic's own reading of the word — a shield — with a boss-flawless goal of its
  own. Anything that referred to the old Dexterity means Speed.

  **A shield is a pool, not a stack count.** Applying Dexterity *grants* X shield
  points; each absorbs one damage and is gone. The body keeps its stacks
  afterwards (its goal clause is unchanged) and has no shield left — which is why
  `shield` is saved on the board entry beside `health` rather than recomputed on
  load, where it would hand back the point the body already spent.

  **A debuff is felt by whoever is carrying it.** `EnemyOnly` is set on all three
  buffs (Strength on the player would want a player attack to sit on, and this
  game has none) and cleared on Marked — so Marked on the *player* doubles the
  damage they take and takes it straight past the Shields, the tries, they were
  counting on to absorb it. That is the one place Buff/Debuff finally became a
  rule instead of a HUD tint, and it is spelled out in a column rather than
  inferred from the word.

  **The multipliers are flat and the bonuses scale.** Marked doubles at one stack
  and at four. A doubling that compounded per stack would turn a board where a hit
  is worth 1 into one where it is worth 16, off a status the player never chose to
  stack.

  Every number goes through one function per side —
  `StatusData.combat_totals(held, which)`, called by `GameLoop2.enemy_combat` and
  `GameState.combat_totals` alike — and lands in one place per direction:
  `GameLoop2._damage_enemy` (a met goal, a bomb and a scroll all resolve there) and
  `GameLoop2._take_hit`. There is nowhere for "does Marked pierce?" to get two
  answers.

  **`[chest reward]` replaced `+X Small Chests`.** Every scaling payout in the game
  used to read "+X Small Chests", which grew into X separate one-item screens each
  worth less than the last. A chest reward spends the same X as **chest points** on
  the size ladder instead — Small 1, Medium 2, Large 3, Huge 4, then greedily Huge
  plus one remainder — so 3 is a Large, 6 is a Huge and a Medium, 8 is two Huges.
  `Data.chest_reward_sizes` is the equation and `Data.chest_reward_text` the
  wording, reached from a status's reward text through a new `{X:chests}` hole
  format, so the checklist row and the reward screen quote the same chests. The
  verb payouts beside it drop to a flat `+1 Bash` / `+1 Dash`: the chest is what
  scales now.

  **Aggravate Monsters was rebuilt on Strength.** It used to arm a run-wide damage
  bonus that ticked away after a game; it now hands **+1 Strength to every body on
  the board**, which rides the enemy and never expires. Reading a Negative scroll
  is a lasting mistake rather than a bad couple of minutes.
  `GameLoop2.enemy_damage_bonus` and `aggravate()` are gone; a save written before
  this reads past those two keys.

  **Two new Slay the Spire boss relics**, both buying the same thing and charging
  differently for it. Each adds a **column and no row** — length without width, so
  the board gets deeper without the front line getting wider, which is the better
  half of Mine-r Construction's trade. **Philosophers Stone** pays for it by giving
  every enemy that *spawns* while it is held +1 Strength (bodies already on the
  board are not taxed retroactively). **Runic Dome** pays for it by hiding the
  enemy behind an offered game until you have committed to it — the hover line, the
  choice popup and the Beatable row all go dark together, and the followers already
  on the board stay visible, because the Dome only ever hid what has yet to spawn.

  On screen: the ⚔ badge and the enemy card now quote the *buffed* damage (with
  the authored number in brackets when a status has moved it), a ◆ shield badge
  sits beside the ❤ when there is one to spend, and every status tooltip carries
  its combat line at the live stack count.

- **The Steam sync is gone: Steam closed the door, and ticking a cover is one
  click anyway.**

  The owned-games list could be seeded from a Steam profile's public games page —
  no API key, just a profile name. It no longer can. Steam now answers that
  request with its **Sign In page**: HTTP 200, a 52 KB login document,
  `logged_in: false`, redirecting back to the URL asked for — and it does this
  for a profile whose "Game details" privacy is Public. There is no name, no
  setting and no header a player can change to get past it; the endpoint simply
  isn't served to anyone without a session cookie any more.

  Everything Steam-shaped is removed rather than left in place failing politely:
  the username field and Sync button, the dev-mode reply dump, the appid parsing
  and matching, and the tests around all of it. `GameData.steam_page` and the
  compendium's "Steam page" button stay — those open a store page in a browser,
  which has nothing to do with reading a library.

  What was weighed before removing it: the **Steam Web API** still works, since
  its key authenticates the caller rather than the player, but it costs the
  player a key to register and paste in; and the **local Steam install** can be
  parsed for installed games without any key, but only on the machine Steam is on
  and only for what is installed rather than what is owned. Against those, the
  tick sitting on each cover in the compendium is one click per game on a screen
  the player is already browsing. The tick won.

  `Ownership.gd` carries the whole story at the top, so the next person to think
  "we should sync this from Steam" finds out what happens before writing it.

- **The same two games stopped opening every run, and the menu lost its clutter.**

  **Starting games repeated because they were never randomised.** The Amulet is
  drawn at random from every candidate within `AMULET_SCORE_SLACK` of the best —
  but the START panel was a strict argmax: `_strict_starts_for` kept the single
  best-branching game per genre per distance, ties broken on the id, so for any
  given Amulet the two cards were fully determined. The well-connected games are
  the best start for MANY different Amulets, so a handful of them opened nearly
  every run. Measured over 400 runs of the full catalog: **63 distinct starts,
  the top ten taking 55.6% of the cards and one of them 15.6% on its own**, while
  the Amulet draw over the same runs produced 281 distinct goals.

  Starts now draw the way Amulets do — every candidate within `START_SCORE_SLACK`
  (3) of its cell's best advances to a random pick. The same 400 runs now give
  **150 distinct starts with the top ten at 32.4%**. The panel's SHAPE is
  unchanged: which genre and which distance each card offers is still ranked on
  the cell's best score, so only which game wears the card moves. A slack of 5
  measures identically, so the pools are already saturated at 3.

  **The menu.** The "A games-first roguelike" subtitle is gone. **Exit Game**
  moved out of the button column into the bottom-right corner — it is the one
  entry that isn't a way into the game, and it was sitting directly under
  Settings. The bottom-left How to Play contents panel is gone too; the button
  above Start Run was always the same door, and now it is the only one.

  **When a Steam sync fails it now says what Steam said.** The first real sync
  came back "Steam listed no games for <name>", which describes our own parse
  result rather than Steam's answer — and Steam does answer, in an `<error>`
  element it returns with HTTP 200 ("This profile is private.", "The specified
  profile could not be found."). That text is now read out and shown verbatim. A
  reply that isn't a game list at all is recognised separately, since a mistyped
  vanity name lands on a web page rather than an error document, and it says
  where to find the right name. Steam's raw reply is now saved on **every**
  failure rather than only in dev mode — asking a player to turn on dev mode and
  press another button is asking them to reproduce the failure — and the panel
  reports the path.

- **Profiles: more than one player on one install — and a tick on every cover.**

  **Save profiles**, the way Isaac and Balatro have them. The main menu grows a
  `👤 <name>` row with a **Switch** button, opening a list where you create,
  rename, delete and enter profiles. Each one keeps its own **runs, lifetime
  stats, tier list, owned-games list and run settings** (path filter, amulet rule,
  transmute rule) under `user://profiles/<id>/`; the window mode, window size and
  dev mode stay **global**, because they describe the machine the game is running
  on rather than the person playing it — switching profile to find your resolution
  changed would be a bug in every reading of it.

  The `Profiles` autoload owns the split. Stores no longer name a `user://` path
  of their own; they ask `Profiles.path()`, so `SaveSystem.SAVE_DIR`,
  `GameStats.SAVE_PATH`, `TierList.SAVE_PATH` and `Ownership.CONFIG_PATH` became
  functions — a const would have baked the first profile in for the session.
  Switching flushes the profile being left, reloads every store from the new
  directory and emits `profile_switched`.

  The failure mode this is really guarding against isn't files in the wrong
  folder, it's an autoload that **early-returns when its file is missing** and so
  keeps the last player's data in memory to hand to the next one. `Ownership` did
  exactly that; it now resets before loading, and `test_profiles.gd` asserts the
  isolation from both sides — a new profile sees nothing, and the first profile's
  data is still there when you switch back.

  An install that predates all this is migrated on first boot: the existing saves,
  stats, tier list and ownership file move into "Player 1", and the run-shaping
  keys are lifted out of the old `settings.cfg` — once, at migration, so profiles
  made later still start at the defaults.

  **"Clear All Data" is gone from the main menu**, and what replaced it is split
  by what it is *about*. The old button sat beside How to Play and promised more
  than it did — only saves, never stats or rankings — and once profiles existed
  it could have meant any of three things.

  - **Delete a profile** is on the **profile screen** (🗑), because it is a
    choice about which players exist. Never offered for the profile you are
    playing: you would be deleting the game out from under yourself.
  - **Wipe this profile** is in **Settings**, because it is about the player you
    already are — "start over as me". It empties the active profile (runs, stats,
    tier list, owned games, run settings) and keeps it. Disabled while a run is
    in progress, since a wipe deletes the save that run is running on.

  Both ask first, through a shared `ConfirmPanel`. Godot's `ConfirmationDialog`
  is a `Window`: it draws its own background from the DEFAULT theme regardless of
  the project's — setting `theme` on it does not help — so on this game's dark
  screen it arrived looking like a system error box. The replacement names the
  profile, spells out what is deleted, says it cannot be undone, and puts the
  destructive button in red beside a plain Cancel. Escape is a No.

  **The owned tick moved onto the cover art.** Every cell in the Collection's
  games grid wears a mark at the top-left of its image: a green ✔ for a game you
  own, an empty box for one you don't. On your own list it is the fastest way to
  say so — one click marks the game without opening its page, and if that game's
  page happens to be open it is rebuilt so the two can never disagree. On the
  catalog's list the mark is read-only and stops taking mouse input entirely, so
  a click there falls through and opens the game rather than hitting a dead spot
  in the corner of every cover.

- **Which games you own is now yours to answer — sync a Steam profile, or tick
  them off yourself.**

  The "Owned" column in `tools/Roguelikes.xlsx` is baked into all 849 game
  `.tres` and shipped to everyone, which made every owned-only filter — the
  path-selection setting, a custom run's library axis, the atlas's owned rings —
  a report on *one person's* shelf. `Ownership` (a new autoload) puts a second
  answer beside it and makes the choice a setting:

  - **The catalog's list** — `GameData.owned`, exactly as before, still the default.
  - **My own list** — a set of game ids kept in `user://ownership.cfg`.

  Under the second, **Settings → Which games you own** takes a Steam profile name
  (a vanity name, a SteamID64 or a pasted profile URL) and reads that profile's
  public games list — `steamcommunity.com/id/<name>/games?xml=1`, no API key and
  no account linking; the profile's *Game details* just has to be Public. Every
  appid it returns is matched against the store link the catalog already carries
  (`GameData.steam_app_id()`), which 585 of the 849 games have, and the matches
  are ticked. The panel reports what it matched *and* how many games have no
  Steam link at all, so a partial number reads as the catalog's coverage rather
  than as a failed sync.

  The rest is hand-editable: every game's page in the Collection (Tab) grows an
  **I own this** toggle, live while your own list is the source and showing the
  catalog's answer, disabled, when it isn't. Each cell in the games grid wears a
  `✔ owned` mark so you can see what's still unticked without opening it, and a
  tick repaints that one cell rather than rebuilding the grid — on 849 games a
  rebuild would lose your scroll position on every tick, which is precisely when
  you are working down a list of them. A sync only ever **adds** — a GOG, itch,
  emulated or borrowed copy ticked by hand is never wiped by the next one.

  In **dev mode**, the settings panel also offers **Save Steam's reply**, which
  writes the last reply Steam sent — headed by the URL asked for and the HTTP
  status — to `user://steam_reply.xml`. The reply is recorded before any of the
  checks that can reject it, so the dump is available for exactly the syncs that
  failed. The one part of this feature that can't be covered by a test is the
  live request itself, so when it misbehaves the artefact worth having is Steam's
  own answer rather than a description of it.

  The spreadsheet's column is never written to, so switching back restores it
  exactly and the manual list survives the round trip. `Ownership.is_owned()` is
  the single read — `RunGraph`, `RunConfig`, `AtlasView` and `SettingsModal` all
  go through it — and any move in the answer drops `RunGraph`'s adjacency cache
  the way a filter change does. One knock-on: `data/atlas_layout_owned.tres` is
  baked from the *catalog's* column, so on a player's own list the owned sky
  would draw a subgraph the run doesn't travel; the atlas falls back to the full
  sky there instead.

- **The header stops scrolling away, the road behind you stops showing games you
  have never been to, and a curse reads as a thing to do.**

  **The header is pinned to the screen.** Health, Gold, the road walked, the
  title and the `☰ Menu` were the first row *inside* the scrolling page, which
  meant the two numbers that end a run left the screen the moment you looked at
  the bottom of a tall board — and were behind every modal the run raises, which
  is exactly where Health is most worth reading (an event offering you a gamble is
  a question about a health bar you cannot see). The whole bar moved onto a
  `CanvasLayer` of its own at layer 135: over the event (123), the game-choice
  popup (124) and the map (130), under the two screens that stand in for the run
  rather than sit over it — the Atlas (140) and the end-of-run verdict (150) — and
  stood down while the tier-list board is up, since that one is a full screen with
  its own way out. The page is inset by the bar's height, so nothing hides beneath
  it, and the canvas-fitting rule measures the header alongside the page instead
  of through it.

  **…and the title and the menu keep the right-hand edge in every phase.** They
  used to start on the *left* on the start picker and jump right the moment the
  first game was taken. The road strip between them was `hide()`n until the run
  had a position, and a hidden Control takes no room, so there was nothing holding
  them out there. The strip stays mounted and expanding with nothing in it — it is
  the header's spacer as well as its picture.

  **The road walked is games played, and only games played.** The strip used to
  close on the **Amulet**, with the gap not yet covered drawn dashed. On the
  end-of-run screen that reads as a journey with somewhere to be; live in the
  header it read as a cover for a game you had never visited sitting directly
  beside the ones you had, as if it were the next stop. The Amulet is ahead of you
  and the road ahead already has two screens (the 🗺 map and the route ladder).

  **The road walked keeps its repeats.** Both strips and Run History drew from
  `visited_games`, which is a *set*: a run that went back to a hub three times
  showed one cover for three stops, so "the road you walked" was quietly the road
  you walked with the doubling-back edited out — and doubling back is a decision
  the player made and paid a Dash for. `GameState.path_taken` records the walk in
  order, repeats included, and `GameState.walked_path()` is the one
  implementation the four screens that draw this picture now share (with a
  fall-back that rebuilds the old road for a save written before it existed). The
  end-of-run road became a framed section of its own with a permanent horizontal
  scrollbar, a `9 games, 12 stops — 3 replays` count, and an `↻ visit 2` badge on
  a stop the run had stood on before.

  **A curse is a checklist row like any other now.** It used to be phrased as the
  rule it came from — "Curse of the Bell — If you don't ring a bell, spawn a
  random enemy when you report the game" — with a box that fired the penalty when
  you **checked** it. That made it the one row on the list whose tick meant the
  opposite of every other row's, and it read as a confession rather than as
  something to go and do. It is an **instruction with its price after it** now
  (`CurseData2.goal_text()`), and leaving it **unticked** is what bites:

  ```
  Poor Sleep         — don't use a rest site to replenish health  if failed, Spawn a random enemy  (3 games left)
  Injury             — don't go below half health                 if failed, Spawn a random enemy  (3 games left)
  Curse of the Bell  — ring a bell                                if failed, Spawn a random enemy  (permanent)
  ```

  Conditions authored as an absence ("you don't ring a bell") have the negation
  stripped rather than doubled, so nobody has to work out what "don't don't ring a
  bell" was supposed to mean. An empty box now means the same thing on every row
  of the checklist; only what failing costs is different.

  **Dashing lists the connected games A–Z.** A Dash is not a hand of three cards —
  off a hub it is twenty covers, and the question stops being "which of these
  three" and becomes "is the game I have in mind in here". The position-seeded
  shuffle that keeps a small offering from feeling like a menu is exactly wrong
  for a list you are searching.

  **…and dashing back to a game you have played leaves you a Dash up.** The
  offering prints `⚡ +1 DASH` on a game the run has played, and the usual way back
  to one *is* to spend a Dash, since the offering is three of a hub's twenty
  neighbours. Spend one to travel and earn one for the clear and the counter reads
  exactly what it read before: the card promised a charge and the player watched
  nothing happen. The trip is what the Dash paid for; the `+1` is what the *clear*
  pays, and the two are not the same transaction, so a return trip made by Dash
  now refunds the fare on top of the bonus.

- **A round of fixes across the screens, and one layout rule that was quietly
  cropping the board.**

  **The page could be wider than the canvas, and the battlefield was what fell
  off it.** The overworld is two columns — the offering on the left, the board on
  the right — inside a scroll region that deliberately draws no horizontal bar.
  The offering's heading is a whole sentence ("Choose where to start — three
  genres, all the same distance from the Amulet…") and it was a Label with no
  wrapping, so that sentence WAS the left column's minimum width: about 900px of
  the 1280 canvas, before the board asked for anything. The board went off the
  right edge and there was no bar to bring it back. The heading wraps now, which
  puts the page back at ~980px of minimum width.

  That is the cause; the guard against it recurring is the other half. A screen
  can now ask for the canvas it actually needs (`Settings.request_canvas_width`),
  and the stretch draws the whole page a little smaller inside the same window
  rather than cropping it. The overworld measures itself after every refresh and
  asks. Nothing is cropped whatever the board grows to, and the canvas goes back
  to 1280x720 when the screen does.

  **Settings grew a window size, and an Apply.** The display section could only
  change the MODE, and picking the mode you were already in did nothing at all —
  so there was no way to say "windowed, but at 1600x900". There is a size list
  now (fit-the-screen, 1280x720 up to 2560x1440), and an Apply that re-applies
  the section whatever it is currently set to. Every entry is still a request
  clamped to the desktop's usable rect, exactly as the default always was.

  **The manual's contents page is behind a button.** Fourteen chapter titles
  stood open in the corner of the title screen; they are one line now, and the
  corner hides itself entirely while anything is open over the menu — it is added
  after the modal layer, so it had been drawing on top of the Collection, the
  Atlas and the character picker.

  **The route ladder says how many ways there are on from each rung**, top right
  of the name, as the same `⛓ N` count the offering's own cards quote —
  `RunGraph.open_degree`, so a neighbour Bash destroyed is not counted as a door.
  And a rung OPENS: clicking one on the card popup's route raises the same game
  card the map window raises, minus the two things a preview cannot do (there is
  no chart on that screen to fly to, and no route to pin from a game you have not
  taken). The card itself moved to `RouteLadder.node_card_body` so both callers
  draw one card rather than two that drift.

  **Wording, where an event hands you something.** A curse is offered by its own
  name — "Injury: if you…, take 2 damage when you report the game · Lasts 3
  games" — instead of "Curse (3 games left): …", and an event goal is labelled
  "Event Goal:" rather than "Goal for 3 games:". The clock goes at the end of the
  sentence in both, because it is a clock and not part of the thing's name.

  **The shop's shelf is legible.** A slot was a 28px row with a 20px icon and one
  clipped line of "Name ◉ 5", so a long relic name ate the price — the one number
  a shelf exists to show. It is a small card now: art at more than twice the size,
  name and price on two lines beside it, and only the name is ever trimmed. The
  page still fits its window.

  **And a run of smaller things.** The shop's reroll now hears about Scramble
  arriving, so a charge the D6 just paid can be spent without leaving the shop and
  coming back. A machine that blows itself up inside an event has its card taken
  off the event, and leaving the Arcade Room takes its cabinets with it — precisely
  the ones it spawned, where the overworld used to clear the board outright and
  take a machine that was standing there beforehand with it. Walking out of a room
  no longer asks twice: a closing screen with nothing on it is not a beat, it is a
  second click. The returning Dash is paid for going back to a game the run has
  PLAYED, not only one it beat — the trip back is what earns it, the goal still has
  to be met on arrival. And the Collection opens in about two seconds instead of
  ten, because the Games tab was reading all 845 covers to draw the dozen cells on
  screen.

---

- **A written manual, and the menu's bottom-left corner is its contents page.**
  The 📖 How to Play button raised a "coming soon" box with two sentences in it.
  It now opens thirteen chapters.

  **What the research says, and what it changed here.** Minimalist instruction
  (Carroll's *minimal manual* work, and the tutorial-design advice that keeps
  rediscovering it) is consistent about four things, and each one moved
  something in this manual:

  * **Task order, not system order.** Chapter 1 is one whole run, menu to win,
    in the order you meet it — because a new player's first question is never
    "what is a status", it is "what do I do". The spec's own order (schemas,
    then systems, then screens) is exactly backwards for a reader.
  * **What, then how, then why.** Every mechanic is named, then operated, then
    justified, and the justification goes last so it can be skipped.
  * **Modular and self-contained.** Each chapter opens cold. That costs some
    repetition and is worth it: nobody reads a manual front to back, they open
    it at the bit they are stuck on — which is also why the corner panel lists
    chapters rather than being one more button.
  * **Error recovery is its own chapter.** "When it goes wrong" is §12 and it is
    the one written to be opened mid-run: I cannot do this goal, I already
    travelled, I am out of tries, four followers are killing me. The happy path
    is the part players work out for themselves.

  The one deliberate departure from the advice is leaning on text at all — the
  usual counsel is to teach by doing. This is the case where text is right: the
  mechanics are strategy-game mechanics (a routing puzzle over a real graph, a
  pressure ladder, a stack that compounds) and those are the ones nobody
  reverse-engineers from watching. The parts that ARE self-teaching — click a
  card and it opens, press Report and it asks — get a line each.

  **The manual cannot drift.** Every number in it is interpolated from the
  constant that governs it, and `test_how_to_play.gd` asserts the prose still
  quotes the build's own values, so a balance change fails the suite rather than
  turning the manual into a lie. It also asserts every block carries a kind the
  screen can draw, every chapter renders something, and — after this shipped
  broken once — that no raw `%d` survives into the prose: GDScript's `%` binds
  tighter than `+`, so a format operator on the end of a concatenated string
  formats only the last fragment.

  **Where it lives.** `HowToPlayText.gd` is every word, as data. `HowToPlayScreen.gd`
  draws seven block kinds and reads none of them. The menu's corner panel is
  built from the same array and opens chapters **by id**, so inserting a chapter
  in the middle cannot repoint the buttons under it.

---

- **The event line came off the cards, and a shop is now what happens instead of
  an event.** Two halves of the same correction.

  The card's popup carried `✦ An event fires here once the game is played.` —
  the last survivor of the era when placement was hashed onto particular nodes
  and routing towards an event was a decision. Every game pays one now, so the
  line was on all but two kinds of card and said nothing on any of them: **a
  fact that is always true is not information.** It is gone.

  And at a **hub** it was worse than uninformative, it was wrong-in-waiting.
  Both a shop and an event queued on the same arrival — the shop mounting under
  the board, the event opening a modal over it — so the shop the player had
  routed towards was something they had to dismiss an event to reach. A hub
  already *is* the thing that happens at a hub. `EventSystem.roll_for_arrival`
  now returns null at one, so the rule holds for every caller rather than for
  the overworld only, and it reads off the game actually PLAYED at the node:
  transmute a hub and the shop leaves with the game it belonged to, so the spot
  goes back to paying an event.

  What a card says about events is now what a hub card says. The `🛒 SHOP`
  flag's tooltip and the popup's shop row both spell out the trade — "no event
  fires here, the shop is what happens instead" — because it is the one way a
  hub costs differently from every other card on the board. The connection line's
  two headings became **exclusive** for the same reason: a hub neighbour counts
  under 🛒 and never under ✦, where counting it under both promised the same
  neighbour twice.

---

- **A card now says when the spot is not playing its own game, and the route
  says where the shops are.** Two small things the popup and the map could not
  answer, plus the spreadsheet's blind spot behind them.

  * **Transmuted, and what it was.** A transmuted node keeps its place on the
    graph and plays something else — but the card it opens speaks entirely for
    the REPLACEMENT: its cover, its type, its tries, the enemy standing there.
    The one fact it could not state was that it is a replacement at all. It now
    carries `⚗ Transmuted — was <game>` under the cover, and the tooltip says the
    part that actually decides the route: the connections are the OLD game's, so
    the ladder below is still the old game's road.
  * **🛒 on the rungs.** `RouteLadder` flags every rung a shop stands on, so both
    the 🗺 map window and the ladder inside a card show where the shelves are —
    "one step longer but it passes a shop" is a routing question and the ladder
    is where it gets asked. Read off the game actually PLAYED at the rung, not
    the rung's id: a transmuted spot plays an off-map game and off-map games are
    never hubs, so the shop leaves with the game it belonged to.
  * **The legends had to get SHORTER to fit it in.** Spelling out "🛒 = a shop
    stands there" under the map wrapped the hint to a second line, which cost the
    ladder above it enough height to push its zoom-to-fit past the legibility
    floor — caught by `test_run_map.gd::test_the_route_fits_the_window_it_opens_in`,
    which is exactly the failure that test exists to catch. Both legends are now
    terser than they were before the marker was added to them.

  **The Map Analysis sheet was reading 819 of 849 games.** `GAMES = 820` was
  written as a range with headroom and had quietly been overtaken by the
  catalog, so every degree, median, hub and genre count on the dashboard was
  computed over a truncated sheet. Ranges are 950/1400 now.

  With that fixed, the dashboard learned the distinction the game actually runs
  on — **owned against everything**. A run draws from the owned catalog
  (`RunConfig`'s default library), which is a little over half the sheet, so a
  hub count that does not say which catalog it means answers no question the
  game asks. Genre, degree bands and the per-year block each carry an Owned
  column beside their total (genre also gets Owned % and an All row), five new
  headline measures cover the owned catalog's size, share, average degree,
  junctions and dead ends, and there is a second hub table: **the 15 biggest
  hubs you own** — which is the shop map in table form, since a shop stands at
  each of them. The charts read the new columns as a second series rather than
  as new charts, and all eight now stack in one column: tiling them two and
  three across put them over the year and edge-span tables the moment those
  tables grew a column.

---

- **The shop had the same disease, worse — and it was there first.** A hub's
  shelf of three cards ran the page to **1231px inside a 688px window**, which
  predates machines entirely: anyone standing in a shop has been scrolling the
  overworld since shops moved onto the page.

  Measured the same way as the machines, and fixed the same way. A shelf item is
  now a **row** — thumbnail, name, price, dimmed when you cannot afford it, kept
  in place and greyed when it is sold — and the card it used to draw on the page
  opens over it on click, Buy button and all. Buying closes the card, because the
  purchase is the answer to the question the card asks. The shop's title, its
  "what's left" line, the purse and the reroll used to be a header block and a
  footer row: 90px of furniture around 30px of shelf. They are one line now.

  Two sizing lessons, both of which cost a measurement to find:

  * **A Button's minimum size is its content.** The rows are given a width, but
    one long relic name quietly pushed a row past it and the flow — measured to
    the pixel — wrapped the shelf onto a second line, undoing 34px. `clip_text`
    pins the row to the width it was given.
  * **The floor has to fit the width the column actually hands over**, which is
    less than the column's own width by the panel's padding. Measured exactly, a
    single rounding pixel wraps the line.

  A hub's shop now fits the window (669 of 688, from 1231). The one case still
  over is a hub carrying a shop AND spawned machines at the same time, which
  runs about 38px long.

- **The machines under the board no longer push the overworld off the screen.**
  Three of them ran the page to **1674px inside a 688px window**; it is 680 now,
  at every board size.

  The overworld is built to fit a fixed 1280x720 canvas — `stretch/mode` scales
  that box into whatever window you use, so a 2560x1440 monitor gets exactly the
  same 720 of vertical room a 720p one does — and the page uses 683 of it with
  **five pixels to spare**. There was never room under the board for a panel.
  A full `ObjectCard` is 341px: the art, the prompt, and two buttons each with a
  cost line and a ☠ warning under it.

  Three things were wrong, and all three are fixed:

  * **The board never gave anything up.** `FIELD_HEIGHT_BUDGET` is tuned so the
    board alone fits 720p, and it stayed at that budget with a shop or a rank of
    machines mounted below it. There is now a second, tighter budget in force
    while the board is SHARING ITS COLUMN (`set_sharing_column`), worth 119px on
    a 4x4 — and the board springs back to the full one when you travel on. It
    binds down to `CELL_MIN`, which is the floor and stays the floor: the board
    is readable or it is nothing.
  * **The flow container wasn't flowing.** The panel's `HFlowContainer` sizes to
    its column, the column sizes to its widest child, and the board narrows as it
    shrinks — so the column followed the board down to 443px and every machine
    wrapped onto a line of its own. The row now has a floor of two cards' width.
  * **The page was carrying the whole card.** It carries a **30px row** now —
    art, name, and the one fact worth reading without opening anything ("Jammed",
    "holds 37 gold") — and two rows fit across the column, so three machines are
    two lines. Clicking one opens the SAME `ObjectCard` over the page, buttons,
    cost lines and warnings intact. Nothing was cut; it moved one click away.
    A machine whose lever would end the run carries the ☠ on its row too, so the
    warning is on the page and not only behind the click.

  Click-outside closes a machine's card, unlike an event's: an event is a
  decision with a price on both sides, and a machine asks nothing of you.

- **An event can kill you, and now it says so and ends the run when it does.**
  Two halves of the same hole.

  **The run ends at 0 Health, wherever the 0 came from.** `GameLoop2` only ever
  checked for death at the two places it knew about — a lost try paid in Health
  (`log_attempt`) and an enemy's hit (`_take_hit`). Every other Health cost goes
  through `EffectSystem`, which moves the number and says nothing, so reaching
  into Scrap Ooze on your last point, one dip too many in Abyssal Baths, or the
  Blood Donation Machine's lever left the player standing at **0 Health with the
  run carrying on around them**. The loop now watches `GameState.hp_changed` and
  ends the run itself, through the same `_finish_run` every other ending uses —
  so the verdict screen, the history record and the cleared autosave all happen
  exactly as they do when an enemy lands the blow.

  The check is **deferred by a frame**, because a choice's effects are applied as
  a batch: a cell that spends Health and gives it back would otherwise read as
  fatal on the frame between the two. Where the batch LEAVES you is what counts.

  **A gamble that could kill you says "might".** The certain cost and the
  possible one are two different questions, and the player is owed both.
  `health_cost` still answers the first — what a press definitely spends, which
  is what says *"this will kill you"*. `possible_health_cost` answers the second:
  every `roll` in the effect list firing, plus the worse of a two-sided
  `chance`'s two branches, since a two-sided roll pays one of them whatever
  happens. When that worst case would end the run but the certain cost would
  not, the button reddens and the line under it reads *"☠ This might kill you."*
  — never both warnings at once.

  Same red either way, deliberately: the distinction the player acts on is in
  the words, and two shades of red is a difference nobody can read at a glance.
  The cost line stops just short of flat `DANGER` for a maybe, because it is a
  weaker claim. No authored event or object gambles with Health today — every
  `chance` payload in the sheet is a reward — so this shows up the day someone
  writes `chance 40% -> gain_chest small 1 else lose_hp 4`, and the tests build
  those choices by hand in the meantime.

  **A fatal press is painted as one.** `EventSystem.is_lethal` and its ☠ warning
  already existed, but the warning was a line of red text under a button that
  looked exactly like the safe one above it. A choice that would end the run now
  wears the warning itself — blood-dark fill, `DANGER` border, red label — in the
  event modal and on an object's card alike (`UITheme.lethal_box`). It is still
  **not disabled**: these are push-your-luck machines, and taking the decision
  away at the moment it gets interesting is worse than the death. An object's
  lever only reddens while it is actually offered — a jammed machine cannot carry
  out the threat.

  The event standing open when the run ends is **dismissed rather than closed**:
  closing one runs the chain that follows an event — refresh, autosave, the hub's
  shop — and the run it belonged to is over.

- **Fixed: a card popup could open five times taller than the window, with its
  buttons off the bottom of the screen.** Clicking a game on the start picker
  opened a `GameChoiceModal` that painted as a black screen with a route graph
  floating in it and nothing clickable anywhere — the run could not be started.

  On its FIRST frame the popup's content asks for an enormous minimum size: the
  labels have not wrapped yet and the route ladder has not been zoomed to fit
  (`_settle` runs deferred, after the panel has been laid out). The start
  picker's ladder is the worst case in the game, since its route runs the whole
  depth of the run — 1409×3832 inside a 1280×720 window. Godot grows a Control
  on a non-container parent to its content's minimum and never shrinks it back,
  so when the minimum dropped to a sane 1140×664 one frame later the panel
  stayed 3832 tall, and `centre` dutifully centred it: header off the top,
  Back / Start two thousand pixels below the bottom.

  `ModalScaffold.centre` now re-fits the panel to its combined minimum on every
  shape change, not only for the panels that asked to be content-sized. A fixed
  size is safe because it is written to `custom_minimum_size`, which is part of
  that minimum — the panel cannot shrink below what its caller asked for, and it
  can still grow when its content genuinely needs the room. The `FIT_CONTENT`
  meta the old two-branch version needed is gone with it. This is the moment the
  transient lets go: `minimum_size_changed` already fires exactly there.

- **A wordless event stacks its art over the choices.** The Arcade Room's
  `Prompt` and both `Result` cells are now blank on purpose: it is a room you
  walk into, a picture of a room, and two buttons — the prose it used to carry
  was describing what the illustration already showed.

  Blank cells were already legal (`parse_result_cell` returns an empty ladder,
  and `result_for` reads it as ""), but the modal was not built for an event with
  nothing to say. It painted the prompt Label unconditionally, so an empty one
  still claimed a line of height above the choices, and it put the illustration
  in its usual **left column** — which exists to keep a page of prose off the
  bottom of a 720p viewport, and with no page left a picture standing next to two
  lonely buttons in a half-empty column.

  So a blank `Prompt` now **stacks**: the art goes above the choices, centred and
  capped at 190px tall (the side column's 460 is affordable only because it costs
  no vertical room), and the buttons sit under it. The prompt Label is skipped
  when there is nothing in it, and the rule that separates a printed outcome from
  the prompt is skipped when there is no prompt above it to separate.

  The layout is decided **once, when the modal opens, from the `Prompt` alone** —
  a wordless event whose `Result` prose prints later keeps the shape it opened in
  rather than shunting its picture sideways mid-event.

- **Objects, an event after every game, and Luck that does something.**

  **✦ Objects (`objects2.0`).** A new content kind: a **machine you stand in
  front of**. Same authored shape as an event — one row, a prompt, choices in
  numbered column groups, Effect cells in the same reward DSL, resolved by the
  same `EventSystem` calls — and a separate kind for three reasons. An event is a
  room that opens, is answered and is over; an object **persists** while the run
  is on that game and ends when you travel on. An event arrives on its own; an
  object is **spawned**, and several can stand there at once. And an object is
  **stateful**: it jams, it gets blown up, and one of them keeps a bank that
  outlives the run.

  Where it draws depends on what spawned it. Spawned by an **event**, the
  machines are laid out *inside that event's modal* — the Arcade Room **is** the
  room the cabinets are in, so they are in there with you and the room's own
  `Leave` walks you out of both. Spawned by **anything else**, one stands under
  the board in the space a hub's shop takes, on the same argument the shop is
  there for: the run's rhythm is report the game → see the board → choose where
  to go, and neither a shop nor a machine may interrupt it.

  A machine's unavailable buttons are **drawn and greyed rather than dropped**,
  which is the one place an object's UI departs from an event's on purpose. An
  event's options are a list of things you may do; a machine is a physical thing,
  and its buttons do not vanish because you cannot afford them. The refusal goes
  *on* the button — **"Jammed"**, **"Full"**, **"Needs 1 Bomb"** — because the
  reason is the whole of what the player wants to know, which is also why
  `not_jammed` and `bank_space` are two gates and not one.

  **🩸 The Blood Donation Machine**, from Isaac, and it keeps Isaac's silence: no
  prompt, just the thing and two buttons. Pay 1 Health for 1 Gold as often as you
  can pay, with a **6.7%** chance per press that it bursts and pays a Blood Bag
  or an IV Bag instead of the coin. Or spend a Bomb for **2-4** loose pickups,
  each independently a heart or a coin. The button quotes both sides of the roll
  — `-1 Health · 93.3%: +1 Gold · 6.7%: +Blood Bag or IV Bag` — which needed two
  new things in the DSL: fractional percentages (one-in-fifteen is 6.7%, and
  rounding it would make the number on the button not the number that gets
  rolled) and a `chance … else …` form, because a gamble that pays nothing on a
  loss cannot say what this machine does.

  It is **not** gated on having Health to spare — Isaac lets you kill yourself on
  one of these and so does this. Taking the button away at 1 Health would remove
  the decision at exactly the moment it got interesting, so the warning does the
  work instead: the cost line **reddens** as the press gets closer to lethal, and
  says so outright — `⚠ You can die here` one press early, `☠ This will kill you`
  on the press that would. It is general rather than the machine's own, so
  Abyssal Baths' Linger reddens too, before its prose gets round to warning you.

  **🪙 The Donation Machine.** Gold in, and it does not come back out. The bank
  is **persistent across runs** (`GameStats`, `user://game_stats.json`), holds
  **999**, and is the only number in this build deliberately not about the
  current run — a bank you could empty by starting a new run would not be a bank.
  Each coin rolls **5%** for a point of Luck and **`{1+X}%`** to jam, where X is
  coins already in *this visit*, so the jam chance climbs 1%, 2%, 3%… while you
  stand there and resets when you travel on. Two independent rolls on one coin is
  what the new **`roll`** clause is for: `chance` is a cell's one headline gamble
  (it takes the `->` payload, prints the Chance Won / Chance Lost prose, and
  closes the thing), where a `roll` is a side effect that either fired or didn't,
  and you may have as many as you need. A jam is permanent for the run and the
  machine still turns up taking nothing; **bombing** it pays 2-5 gold out of the
  bank (capped at what it holds) and takes every donation machine off the run.

  **🕹 The Arcade Room** is the event that spawns them: a gold to enter, 2-3
  arcade-tagged machines inside, and a `Leave` that walks you out. Each slot
  rolls rarity independently and falls down the ladder when a rung is unstocked,
  so the same roll an item reward walks decides what is in the room. Duplicates
  are fine — an arcade with two Blood Donation Machines in it is an arcade — but
  never two Donation Machines, which would be two faces of one bank and the
  second a way around the first's jam.

  **✦ An event after every game.** Events used to hang off dead ends, with
  placement **hashed** from the node id and the run seed so an offered card's
  `✦ EVENT` badge could not change under the player. Both are gone. One fires
  after **every** game the run plays — win, loss or escape — because the games
  this is a graph of are hour-long roguelikes, and what the run needed was
  something to do between two of them.

  Which one you get is dealt from a **per-rarity shuffle bag**: roll the ladder,
  draw from that rarity's events not yet seen this run, reshuffle when it empties
  (never opening the new bag on the event that closed the old one), and **skip**
  an event gated out right now rather than burning it. Each **game** pays one
  event and is then spent, so walking a two-node loop is not a faucet; a
  `play_game` **detour** pays none, and neither does the Amulet.

  The `EVENT` badge came off the cards with the placement that justified it —
  with an event after every game there is no subset of nodes to badge, and no
  honest answer to "which event is over there" before the run arrives. The card's
  popup now says only that one *will* fire, and says nothing once that game has
  paid. `Limit` is gone from the sheet, and `Where` is blanked but kept for the
  per-location work.

  **🍀 Luck, rebuilt.** **Every point buys one more roll, and the better result
  is kept.** At 1 Luck a 25% chance is really 43.75%; at 3, 68%. It compounds
  rather than adding, and negative Luck is the same machine reversed. What it
  replaced was a 10%-per-point chance of *advantage*, which at a single point did
  nothing at all nine times in ten — not a tuning difference, but the difference
  between a stat you can feel on the first roll after picking up a Clover and one
  you could hold for a whole run and never observe.

  A reroll only means something when a roll has a side the player wants, so every
  call site **declares its direction** and the ones with no honest answer opt
  out: `HIGH` for the rarity ladder and a chest gamble, `LOW` for the Donation
  Machine's jam, `NONE` for which of the twelve Commons you drew or whether a
  burst machine dropped a Blood Bag or an IV Bag. The case that reads backwards
  is the Blood Donation Machine's explosion, which is `HIGH`: bursting pays a
  relic where the loss pays a coin, so Luck makes it *more* likely to go off in
  your face.

  Luck rides on **`Data.roll_item_rarity`** rather than at the call sites, which
  is what makes "it affects every roll" true without thirty places remembering
  it — item rewards, chest sizes, scrolls, shop stock and the object pools all
  walk that one ladder. Odds shown to the player are the ones Luck **will
  actually roll**: a button that said 6.7% to a player holding a Clover would be
  lying to them about the thing they bought it for.

  **Three new items and three new games.** The **Clover** (Uncommon, `+1 Luck` as
  a passive bonus, so it goes with the item), and the two Event relics the blood
  machine bursts: the **Blood Bag** (+2 Max Health, +8 Health) and the **IV Bag**
  (spend 1 Health for 1 Gold, **unlimited uses** — `Usable, 0` in the Type cell,
  where Ride the Bus is `Usable, 1` and is destroyed after one). Genome Guardian
  2, Inkshade and Netherworld Covenant join the catalog with their connections.

- **A run you can build, and the road you walked put at the top of the page.**

  **⚙ Custom Run.** The catalog is 846 games and the only say you had in which of
  them a run was made of was one global switch, three values wide. "A deckbuilder
  run", "only games I have never beaten", "send me at Balatro", "a short one" are
  all the same wish and none of them could be asked for. So: a setup screen off
  the main menu, and a `RunConfig` autoload behind it.

  It carries **three filters, not one**, because the three questions are
  genuinely independent — what **the map** is made of, which of those may be
  **the start**, and which may be **the amulet** — and the interesting runs come
  from the three disagreeing ("any map, a deckbuilder start, an amulet I've never
  won on"). Each has the same four axes: library, genre (a multi-select, since
  "Action or Deckbuilder" is a run someone wants and a dropdown cannot say it),
  your lifetime record, and a release-year range. The start and amulet filters
  select from **inside** the map rather than beside it, so a start filter can
  never offer an opening card no route could leave.

  Under them the **run length** — how many games from the start to the Amulet,
  which used to be a pair of constants — and an optional **named target**, which
  composes with the band rather than overriding it: name Balatro and set 4–6 and
  you are offered starts four to six games out from Balatro. A named target
  outranks every filter beside it, including `exclude_beaten_amulets`: you said a
  game, and a general preference does not get to overrule a specific instruction.

  Each column prints the count of games that survive it, live, which is what turns
  "is this run even possible" from something you discover by pressing Begin into
  something you read while you are choosing. Begin is disabled only for the things
  that genuinely cannot produce a run — a map filter that leaves nothing, an
  amulet filter with no game behind it, a target its own map excludes. A nine-game
  map is a warning, not a refusal; it is a strange run and it is a run. One
  warning is worth naming: the opening panel offers **one card per genre**, so a
  single-genre map opens on one card, and the screen says so before you take it.

  The filters ride in the **save**, because on a custom run the filters *are* the
  map: resumed without them the graph rebuilds off `Settings` and the run comes
  back standing on a node the new graph may not have.

  **The Continue list says which run a save is.** A custom run that reads exactly
  like an ordinary one on the save list is a run you cannot tell you are about to
  resume — and it is the one fact about a save that changes what resuming it
  means. Each row now carries its own `⚙` line ("map: Deckbuilder · start: never
  beaten · 4–6 games") built from the filters stored in that save, not from the
  live `RunConfig`, which is describing whatever run happens to be in memory.

  **And the suite is all green, with no Risky.** Two tests used to early-`return`
  when the run's random graph did not reach the case they were about, so *which*
  test reported "Did not assert" varied between runs and the noise was documented
  as expected. Neither needed to be that way. The Atlas's path-order test walked
  from wherever the run's random start landed and took the first unvisited
  neighbour it found — a dead end waiting to happen, since `visited_games` is a
  set and a walk that wanders into the fringe has nowhere left to go; it starts at
  the best-connected game in the catalog now and steers toward degree, so the case
  is reached every run. The route-map's fit test simply asserts the *other*
  branch: a route too big to fit legibly should bottom out at the legibility floor
  and scroll, which is a fact worth pinning rather than a reason to assert
  nothing.

  **And the road you walked is at the top of the screen.** The end-of-run screen
  has always drawn a run as a line of covers with arrows between them closing on
  the Amulet, and it is the clearest picture of a run this project has — shown
  once, on the screen that tells you it is over. It is in the header now, live,
  for the whole run: the games played, then a dashed arrow to the Amulet. The
  checklist says what you owe, the board says what is closing in, the route ladder
  says where you could go; none of them said where you have *been*, which is what
  a roguelike run actually is. The title gives up the centre for it and takes the
  right, which is the honest ranking of the two — the title is decoration and the
  strip is state. The covers are small and carry no name (that is on the hover)
  because the strip shares one 1280-wide row with the health chip, the gold chip,
  the title and the menu, and the page underneath still fits 720 without
  scrolling — which the three fit tests confirm it does.

- **Three new robots, a start that is a game, connections you can count, and a
  star chart that stops decoding the catalog to draw a dot.**

  **The start is the run's first game.** Taking one of the three opening cards
  used to be a free move: you landed on the game, nothing spawned, no tries were
  granted, and the run's first real game was whatever you travelled to from it.
  That made the opening decision cheap — three roads, no cost, and the thing you
  were actually choosing (which genre's enemy you would face first) happened one
  click later against a card you had not seen when you chose. Now the start
  *rolls its goal-enemy*, stands it on the board, hands over the game's tries and
  drops the run straight into the report step. The card opens the ordinary
  `GameChoiceModal` first — the enemy, its goal, the tries, the route, the
  connections — so nothing about it is a surprise. **Bash and Transmute are
  withheld there**: they reshape an *offering*, and three roads out of one run is
  not one. The run now opens with something to go and play.

  **Every card says how many doors it opens, and how many of them are worth
  walking through.** Above the cover, before anything else: `⛓ 14 connections ·
  ✦ 2 events · 🛒 1 shop`. Routing was the one decision the popup could not
  answer — it drew the shortest path to the Amulet beautifully and said nothing
  about how much *choice* the next node would give you, which is the difference
  between a hub and a corridor. Counted off `RunGraph` rather than off the
  sheet's raw `games_influenced`, so the number is doors this run can actually
  use: the filter's, the main-component prune's, and Bash's removals are all
  already taken out. Event placement is hashed off the node id, so quoting the
  count early gives away nothing that opening that neighbour's own card wouldn't.

  **Punch Off fights back.** "The Constructs turn to you menacingly!" used to be
  prose over a button that cost nothing up front, which made *I Can Take Them*
  the obviously correct press on a dead end — the one place the event format says
  an event may bite. It bites now: `spawn_enemy tag=robot 1` peels one of the
  Constructs' kin off and puts it on the board, and it is still following while
  you go and beat a mecha roguelike for the payout. Two fronts, which is what "I
  can take them" ought to have to mean. The `tag=` is new on the token and is the
  point of it — a plain `spawn_enemy` conjures whatever the roster hands over,
  which in a scene that has just told you exactly what is standing in front of
  you is a Leprechaun walking into a robot fight. The generator checks the tag
  against the `enemies2.0` Tag column, and a tagged roll widens by *difficulty*
  rather than by dropping the tag: the tag is what the row promised.

  **Three robots to be that robot** — Punch Construct (Slay the Spire 2), Love
  Bot and Robo-Cat (Mewgenics), from the sheet, with art. The Tag column already
  spoke in comma lists for the enemies that are more than one thing; `has_tag`
  now reads it as the set it always was, so Robo-Cat answers to `cat` and to
  `robot` both.

  **The Steam page is its own shortcut in the Atlas and the Collection.**
  `GameData.launch()` prefers the local install and only falls back to the store
  page — right for "play this", and it meant that for every game the player owns
  the Steam page had no way in at all, while for the ~800 they don't it was the
  only thing behind the entry. It is a separate button now, wherever a game is
  being *read* rather than played.

  **And the Atlas stops decoding the catalog to draw a dot.** The stutter had one
  cause, and it was a HUD label. `cover_count()` — "12 showing art", refreshed on
  every redraw, which means on every pan and zoom step — asked `shows_cover()` of
  all 845 stars, and `shows_cover()` answered by *loading the cover to measure
  it*. Panning the chart therefore walked ~200 MB of box art through the image
  decoder a few stars at a time, forever, because there was always another star
  that had not been asked yet. Two changes: a star answers "definitely too small"
  from its packing radius alone (the widest a cover can be for a given radius is
  fixed arithmetic, no art needed), and the count is bounded to what is on
  screen — which is also the more useful sentence. The per-star id conversion the
  draw loop repeated six times a star, three passes a frame, is now done once per
  sky. Nothing derived from the run or from the lifetime record is cached: those
  move from places that have no reason to tell a star chart about it.

- **A pass over the things the page gets wrong: scrollbars, where a modal opens,
  and what you can point at.**

  **The overworld never draws a horizontal scrollbar again.** The page is laid out
  to fit its width, so a bar under the whole thing was never the answer to
  anything — it is chrome that turns up when a layout hiccups (a canvas that has
  not settled into the window's aspect yet) and then sits there for the rest of
  the run. The axis is `SHOW_NEVER` rather than `DISABLED`: still scrollable by
  wheel and by code, so nothing is ever clipped out of reach, it simply never
  draws the bar.

  **The scrollbars are dressed in the project's own palette** — a dark inset
  trough and an ember grabber that lights under the pointer, both axes. Godot's
  stock bar is a light-grey capsule drawn for the editor, and on these near-black
  pages it was the one control that looked like it came from another program. The
  theme goes on the **window** as well as on each screen root, because every 2.0
  modal mounts on a CanvasLayer of its own and a CanvasLayer breaks the Control
  chain a theme travels down — which is why the modals were the ones still coming
  up grey.

  **A modal opens in the middle of the screen and stays there.** `ModalScaffold`
  centred the panel once, at build time, while it was still an empty shell with a
  width and no height — so the panel's *top* landed on the middle of the page and
  everything it then grew hung below that. The relic you just found opened against
  the bottom edge with its art off it. The panel now re-centres whenever it
  resizes *or* its content settles, and a panel built content-sized shrinks back
  to its content: a label reports an enormous minimum height until it has wrapped,
  and a Control on a non-container parent only ever grows to its minimum, never
  back. `BossNoticeModal` had hand-rolled half of this; it is one implementation
  now, and `ItemDropModal` — which had none of it — is the one that was visibly
  wrong.

  **The whole checklist row lights its enemy, not the two pixels of padding around
  the tick-box.** Godot hands `mouse_entered` to the one control under the cursor
  and not to its ancestors, so a row bound only on its frame reported nothing
  while the pointer was on the CheckBox — which is most of the row's width — or on
  the Notes button. Every descendant carries the binding now, and leaving is
  positional: crossing from the box to the button is one row, not a departure and
  an arrival.

  **The Boss Incoming popup's portraits open.** It names three bosses it is
  warning you about and had nothing to say about any of them; clicking one now
  opens the same card the battlefield opens — goal, damage, tier — over the popup,
  read-only, since no body exists to push or bomb yet.

  **A conjured enemy comes from the run's own difficulty.** A curse's bill and the
  Scroll of Create Monster roll through `roll_conjured_enemy` rather than
  `roll_enemy`: the offering's roll widens a thin bucket all the way out to "any
  enemy authored", which is right when a game must always get one and wrong for a
  body that is priced on nothing but the tier it came from. It may only step
  *down* to the nearest stocked tier — nothing is authored at Insane yet — and
  never up.

  **Curse of the Bell now bites when you forget.** Its condition reads *"you don't
  ring a bell"* rather than *"ring a bell"*: the other two curses in the roster are
  things you must avoid, and this is the one that is a thing you must remember,
  every game, forever. No code knows which way a curse points — the row composes
  from the Condition either way — so the inversion is a sentence in the sheet.

  **And the Relic Trader wants five relics before he shows up** (`relics >= 5`, a
  new Requirement stat). He lays out three offers, each spending one of yours
  against one you don't have, so a pack of one or two was a shelf with gaps in it.
  The five are five he would actually *take*: `relics` counts rollable relics
  only, since Starter, Boss and Event relics are excluded from a swap in both
  directions and counting them would let the gate pass on a pack he wouldn't
  touch.

- **The Relic Trader is three offers and one line.**

  The **Trade Nothing** button is gone. It was a fourth choice that existed to
  say what an empty list already says: a run he wants nothing from is shown no
  offers at all, and `EventModal2` answers a modal with no available choices with
  its own **Leave**. Keeping the decline made every *other* visit a four-button
  event whose fourth button was "no".

  And he says the same thing whichever row you point at — *"Hehehe Heh... Thank
  you!"* — instead of three sentences narrating a swap the button just named in
  full. `<give>` / `<get>` still work in result prose; this event simply spends
  them where the player needs them, on the offer rather than after it.

- **Boss relics, two Slay the Spire events, and every curse now costs an enemy.**

  The sheet arrived with four new relics, a new curse, a new game and two pieces
  of event art, and nothing behind any of them. This is what went behind them —
  plus one rule change that touched every curse in the roster.

  **A relic's Rating can now say where it came from, not just how rare it is.**
  `items2.0` had `Starter` as a special value already: a character's opening
  loadout, excluded from every random pool. **Boss** and **Event** join it as the
  same shape of thing — a flag beside the rarity rather than a fifth and sixth
  rung on it, because `ItemData.Rarity` and `Data.RarityStep` are the same four
  rungs with no holes and a shop's price is *base + the rung* (§14). A value
  nothing can ever roll would have put a hole in two ladders and a price list to
  express something that is not a rarity at all. `ItemData.is_rollable()` is now
  the single test every random draw makes, so drops, chests, shop shelves and the
  new Relic Trader are all excluded from the three classes by one rule instead of
  three remembered ones — and each class gets its own colour and its own word on
  the card, since a Boss relic drawn in Common grey is a lie every screen would
  then repeat.

  **Beating a boss drops a Boss relic.** Not a better roll on the ordinary table —
  a relic out of a pool nothing else can reach, with no rarity roll at all, since
  "which rarity did the boss roll" is not a question with an answer. Three of them
  are authored: **Sacred Bark** doubles every loot consumable; **Calling Bell**
  pays one Common, one Uncommon and one Rare and saddles you with a permanent
  curse; **Lord's Parasol** empties the next shop you walk into, free. The
  fallback if no Boss relic is authored is the ordinary roll, because a boss that
  drops nothing reads as a bug rather than as a thin catalogue.

  Sacred Bark doubles the **bad** scrolls too, and that is the point of it: a
  version that only doubled the upside would make reading an unidentified scroll a
  strictly better gamble than it is, which is the one thing the identification
  minigame cannot afford. The multiplier lands on named fields per effect rather
  than on every integer in the dict — a Teleportation scroll's `spread` is how far
  the landing may *vary*, and doubling that is not twice the scroll, it is a worse
  one.

  **Every curse now spawns an enemy instead of charging Health.** A curse used to
  cost `lose_hp 2`, which put it in competition with the enemy stack for the same
  resource and made "take the curse" a piece of arithmetic — two damage against
  whatever the reward was worth. `spawn_enemy` bills in the run's own currency
  instead: a body that has to be *beaten*, that follows you until it is, and whose
  cost depends on where the board already is rather than on a number. It is also
  the only penalty that gets worse the deeper the run goes, since the conjured
  enemy rolls at the current difficulty. A test asserts it across the whole roster
  rather than the two rows a test happens to name.

  Curse of the Bell needed one more thing: a curse that **never expires**. The
  `Timer` column takes `N/A` for it, which is a 0 on the resource and a -1 window
  on the run — a *blank* cell is still the three-game default, because "nobody
  filled this in" and "this is forever" must not be the same value.

  **Golden Idol** (Slay the Spire) is the first event whose price is a fraction of
  the player rather than a number: 25% of Max Health to outrun the boulder, 8% of
  it to hide, the Injury curse to smash it. The percentages are the source's and
  port directly — a percentage does not care that Health here is 5–10 rather than
  75 — but *printing* them does not, so an `{expr}` hole may now name the run
  (`MAX_HP` / `HP` / `GOLD` / `GAMES`) and the button says **-3 Health** instead of
  making the player do arithmetic at the moment they are choosing. Both costs floor
  at 1: 8% of 10 Health rounds to nothing, and a Hide that costs nothing is the
  obviously correct answer to a decision that is supposed to be hard.

  It is staged the way Abyssal Baths is — **Take** is `Stay` and the three escapes
  are gated behind it, while **Leave** is gated the other way, because once the
  corridor is full of rolling stone there is no such thing as walking out. That is
  five buttons, one more than the sheet had; the events tab now carries six
  `Choice N` groups, and a blank `Choice N` still ends the list, so every existing
  event is untouched.

  **Relic Trader** (Slay the Spire 2) is the first event whose choices are not the
  same choices twice: three offers, each pairing one relic you are carrying
  against one you are not. Placement is hashed so a card's badge cannot change
  under the player; a trade cannot be, because it depends on the pack rather than
  the node — so the offers are rolled once as the modal opens and held for as long
  as it is up. A run carrying one relic is shown **one** row, not three buttons
  that swap nothing.

  The whole event still lives in the spreadsheet. `<give>` and `<get>` are name
  holes the way `{...}` are arithmetic holes, and they work in the button label,
  the result prose and the mechanical line alike — the only thing GDScript knows
  about the Relic Trader is what those two mean. Neither half of a swap may be a
  Starter, Boss or Event relic, in either direction: a starter is the character you
  picked, a Boss relic is a boss you beat, an Event relic is an event you walked
  into, and none of them is a thing to find in a stranger's coat.

  **And the sheet caught up again** — one game (*Overworld*) and its NetHack edge,
  846 games / 1205 connections, sky re-baked.

---

- **Max Health now arrives full, and the sheet's newest upload is ported: 10
  games, 13 connections, 3 events, and a way out of the game.**

  Four changes that happened to land together, each small on its own.

  **The spreadsheet caught up.** `tools/Roguelikes.xlsx` had been uploaded twice
  without a regeneration behind it, so `data/` was ten games and thirteen
  connections behind the sheet it is generated from. `import-games-godot.py` +
  `bake_atlas.py` bring it to 845 games / 1204 connections, and
  `check_map_sync.py` agrees. Three new events came with it — **Jungle Maze
  Adventure**, **Morphic Grove** and **Whispering Hollow** — and they needed no
  new columns, which is the first time a batch of events hasn't.

  **`+N Max Health` means what it says everywhere else.** It used to raise the
  cap and leave the new room empty, which is defensible in the abstract (Max
  Health and Health are different resources) and wrong in practice: every game
  this project is a graph *of* hands you a full container. So `gain_max_hp N`
  now heals by what it raises — by what actually *landed*, so Handcuffs' cap
  can't be healed around — and the one item that genuinely meant an empty
  container, **Hollow Heart**, says so with a token of its own,
  `gain_empty_max_hp`. Lunch and Mango lose the second clause they used to need
  (`gain_max_hp 2; gain_hp 2` would now heal twice); Alien Baby heals along with
  the rest.

  **Losing Max Health is deliberately not the mirror of gaining it.** The cost
  takes the room and leaves the Health — 20/30 losing 5 is 20/25, and only a
  player who was already at full loses anything at all, because there is nowhere
  for the overflow to go. Emptying the container on top of the price the event
  already charged is two punishments for one choice, and Unrest Site charges
  enough as it is.

  **`lose_gold all`** joins the reward DSL as the one amount the sheet cannot
  write as a number: what it charges is settled when the choice is taken, not
  when the `.tres` is written, which is what lets Morphic Grove's Morphics be
  the same trade whether you walked in with 3 gold or 30. Gold only — `lose_hp
  all` is a death with extra steps.

  **And there is now a way to leave.** Neither menu had one: the only exits were
  the window's close button and the process. The main menu gets an **Exit Game**
  button that quits on the press (nothing is live there, saves are on disk, and
  a confirmation between the player and the door is pure friction), while the
  in-run `☰ Menu` gets an **Exit game** entry that asks first — offering **Save
  & exit** beside Exit and Cancel, since the open question is whether this run
  goes in the save list, not whether you meant to press the button. Save & exit
  quits only once a save has actually been written, so a blank name leaves you
  where you were.

- **The Abyssal Baths finally say something when you linger, and `Result` became
  a ladder to let them.**

  Linger and Exit Baths shipped with empty `Result` cells — the text could not be
  sourced at the time, and an invention presented as quotation was the one thing
  worse than a gap. So the one button in the game a player presses over and over
  answered with silence, and the way out of the water closed the modal without a
  word.

  Filling Linger's cell is what turned `Result` into a **ladder**. Slay the Spire
  2 does not repeat one line at you; it answers each dip with a hotter one and
  finishes on a warning:

  ```
  press 1   The temperature keeps rising! How long can you endure…
  press 2   It keeps getting hotter! The pool's bubbling sounds like laughter…
  press 3   …you have lost track of time and your mind... It's nice in here.
  press 4+  If you bathe any longer you will die.
  ```

  A `Result` cell is now `||`-separated rungs, **one per press, the last standing
  for every press after it**. That last part is what makes an unbounded ladder
  authorable at all: Linger's cost climbs forever, so its prose cannot enumerate
  forever, and a death warning that keeps warning while the player keeps pressing
  is the right behaviour rather than a fallback. It is the prose half of `{X}` —
  the numbers already escalated from one authored group (`{4+X}`), and now the
  voice escalates with them, still from one group and still one row of the sheet.

  A cell with no `||` in it is a one-rung ladder, so no event authored before this
  changed shape. More than one rung only means anything under `Repeat: Again` —
  `End` closes the event and `Stay` spends the choice — and the generator rejects
  the combination rather than letting unreachable prose rot in the sheet.

  **The five new strings are lower-confidence than the rest of the event.** Prompt,
  Immerse and Abstain are the game's own, read off the source; these were
  reconstructed from search-engine summaries because every site carrying them is
  blocked from the environment they were authored in. The order of the first two
  rungs is the least certain part. `docs/event-sheet-authoring.md` §7 says so where
  an author will see it, and correcting it is one cell and a regeneration.

- **An Events tab in the dev panel, and one statement of why an event turns up.**

  The panel's fifth tab lists every authored event with a **Start** button, but
  the button is the smaller half. The other column is the reason each event is or
  is not standing where you are:

  ```
  Scrap Ooze    (3 choices)    ✓ eligible here
  Unrest Site   (2 choices)    ✗ not a dead end, needs Health <= 70%
  Punch Off     (2 choices)    ✗ used 1/1 this run
  ```

  That is the part worth building. Placement is **hashed** from the node id and
  the run seed rather than rolled, so a card's `✦ EVENT` badge can never change
  under the player — and the same property means an author cannot reload their way
  into a new event, and an event that never appears says nothing about which of
  the five gates stopped it. Now every gate names itself. **Clear fired counts**
  and **Re-roll placement** sit above the list, because `Limit 1` is on every
  authored event and the second look at one is otherwise blocked by a counter.

  **The blockers and the roller are the same code.** `EventSystem.blockers_for`
  is the single statement of the gates and `_eligible_for` is now
  `blockers_for(...).is_empty()`, so the list an author reads cannot drift from
  the rule the game applies — a test asserts the two agree. `requirement_text`
  moved there too, out of `Collection`, and learned that the gate stats have
  names: `Hp <= 70%` reads `Health <= 70%` on the event's Collection page now as
  well as in the panel.

  **Starting one goes through `Overworld2.open_event`**, which queues it down the
  ordinary path rather than raising an `EventModal2` of its own — so a started
  event has the same finished handler, the same refresh and autosave, and a
  `play_game` choice really does post the run off to a tagged game. It refuses
  when a modal is already open, when the run is over, and — the one that matters —
  when an event is already **queued**, since overwriting that would eat the event
  the player actually walked to a dead end for.

  Also: the Collection stopped telling events they "fire on arrival". `Trigger:
  Before` is inert (§13), so that line was describing a spreadsheet cell rather
  than the build.

---

- **Two new games, and an event that rolls dice at you.**

  **The sheet's new games and connections are ported.** `Gordian Quest` (2020)
  and `Montabi` (2026) join `data/games/`, both with cover art, taking the map to
  **835 games and 1191 connections**. Four new edges came with them — Slay the
  Spire into Gordian Quest and Dice & Fold, Aethermancer and PokéRogue into Montabi
  — and `check_map_sync.py` now reads clean against the redrawn `Roguelikes.drawio`:
  every node matched by name, every Y position agreeing with its Year, and the
  only two entries left in the drift report are the pre-existing pair (the
  backward `Rogue → Beneath Apple Manor` line drawn on the map, and
  `Diablo → Escape The Mad Empire` recorded in the sheet but never drawn).

  **The Manager's level-up pays the gold it says it does.** Their `Reward` cell
  had grown "and +1 Gold" in the sheet, and the character generator dropped it on
  the floor: gold is not one of the run verbs `REWARD_VERBS` knows, so the token
  parsed to nothing and the level-up quietly paid only the Push. It parses now,
  and `GameState.apply_level_up_stats` gives it a branch of its own rather than a
  row in `_LEVEL_UP_ABILITY_FIELDS` — that loop writes its field with `set()`, and
  gold has to go through `change_gold` or the purse on screen never hears about it.

  **Scrap Ooze, and the `chance` token it needed.** The fifth authored event, and
  the first from the original Slay the Spire rather than Slay the Spire 2 — all
  four of its strings are the game's own, verbatim. Every event before it was
  settled the moment you pressed the button; you could be charged, gated, sent
  somewhere or handed an objective, but you always knew what the press bought.
  Scrap Ooze is nothing *but* the not-knowing, so it could not be authored at all
  until the Effect DSL learned to gamble:

  ```
  Reach Inside   Stay    lose_hp 1;      chance 25% -> gain_chest small 1
  Deeper         Again   lose_hp {2+X};  chance {35+10*X}% -> gain_chest small 1
  Leave          End     nothing
  ```

  Two column groups for one hand in the ooze, because that is the game's own
  button — Slay the Spire renames `[Reach Inside]` to `[Deeper]` after the first
  grab, which is exactly the staging `Repeat: Stay` already did for Immerse →
  Linger in the Baths. **The damage is this game's and the odds are the
  original's:** Slay the Spire opens at 3 HP against a 75 HP pool, and Health here
  is 5–10 — where 3 is a third to over half a character for a 25% shot — so, as
  asked for, the ladder starts at **1 and climbs by one per failed reach**. The
  25%, +10-per-failure odds are untouched, so a player who keeps reaching until it
  lands pays about 6 Health over about 2.7 reaches: more than a whole character at
  the low end, which is why the event belongs at a dead end you had to choose to
  walk toward. A relic is a Small chest — one item offered, so it reads as the
  random relic the original hands over rather than as a pick.

  **`chance` is an arrow verb, and a won roll closes the event.** `Again`
  describes what happens when you *lose*; there is nothing left to reach for once
  the relic is in your hand. Its percentage is an ordinary reward amount, so a
  `{expr}` hole climbs it exactly as one climbs a cost, and it is clamped to a real
  percentage so an unbounded ladder becomes a certainty instead of running past
  100. The prose comes from two new event-level columns, **`Chance Won` /
  `Chance Lost`** — the same argument `Goal Met` / `Goal Missed` already made,
  since an outcome decided by the roll belongs to the event's voice and not to
  the button that produced it, and both reaches print the same two lines.
  Alongside it, "must be the last clause" stopped being a rule written twice:
  `add_goal`, `play_game` and `chance` share one check now, and that single rule
  is also what keeps a cell to one arrow verb — a second could only appear after
  the first, which being last forbids.

  **The curses were already portable** — `curses2.0` has been a tab in
  `Roguelikes.xlsx` since the events sheet landed, and `generate_curse2_tres.py`
  regenerates both curses from it byte-identically. Nothing to do there.

  **And the README now has [Authoring an event](README.md#authoring-an-event)** —
  the how-to that `docs/event-sheet-authoring.md` never was, since that document
  argues for the format rather than explaining how to fill it in. Columns, the
  whole `Effect` token vocabulary, `Repeat` + `{X}`, art naming, how to reach a
  new event in a running game, and the exchange rate a dead-end event has to pay.
  Writing it turned up two things the sheet says but the build does not do, both
  now flagged where an author would hit them: **`Trigger: Before` is inert** (it
  parses, generates and is described in the Collection, and nothing reads it —
  every event fires after the game is beaten), and **a `needs <resource>` gate
  only checks, it does not deduct** — the design doc's "spend a key, take an item"
  was never true, and a choice that should cost the key has to write the charge
  itself. Every token in the new guide was run through the parser rather than
  transcribed from memory, which is what caught them.

---

- **Seven from playing it: the enemy on the board, the shop on the page.**

  **The enemy of the game you are playing now stands on the battlefield.** It
  used to wait in the off-field lane with a NOW PLAYING tag and walk onto the
  grid only once its game was reported — which is where the "one-game grace"
  came from. The grace is now a DISTANCE rather than a rule: the enemy spawns on
  the back column the moment you pick its game and closes in from there, taking
  its turns with every other body. Meeting its goal still defeats it before it
  acts at all, because goals met this game land their hits before the turns run;
  missing it means you have already watched it take a step. `GameLoop2.current`
  and that body's stack entry are now literally the same Dictionary, so there is
  exactly one record of its health, its statuses and its square — and every
  removal goes through one door (`_take_off_board`), because a body bombed out
  from under the report step used to be able to leave `has_current()` answering
  for an enemy that was not there.

  **The shop moved out of a modal and onto the page, under the board.** The run's
  rhythm is report the game → see what it cost you on the board → choose where to
  go next, and a full-screen shop dropped into the middle of that stopped
  everything to ask a question the player had not asked yet — while covering the
  two things the answer depends on. `ShopPanel2` mounts under the battlefield,
  blocks nothing, and stays for the whole visit: travelling on is what closes it,
  which is what walking out of a shop has always meant. It has no Leave button
  for the same reason. Because it can sit below the fold, a **`🛒 Shop ↓`**
  pointer floats at the foot of the screen until the panel is scrolled to.

  **The checklist and the board point at each other.** A goal on the list and a
  body on the field are the same fact written twice, and nothing said which line
  went with which enemy — four goals beside four bodies left the player matching
  them up by name. Hovering a goal row now lights the body it belongs to;
  hovering a body lights its row. One binding, both directions.

  **A boss round is a popup, not a strip.** "⚠ BOSS INCOMING" was a banner above
  the offering: it shoved the offering, the checklist and the board down the page
  at the moment they were being read, and then held a row of a one-screen layout
  for the whole round. It is `BossNoticeModal` now, opened once per round, with
  room for the part the strip never had space to say — a boss round is a
  different set of rules, not just a harder game — and the portraits of the
  bosses on the table.

  **A detour hands over no event of its own.** An event that posts the run off to
  another game (`play_game`, §10) had that game fire the event standing at ITS
  node on the way back, so beating the mecha game Punch Off sends you to gave you
  the stay-or-return question AND a second event dropped on top of it. A detour's
  destination is somewhere the run was *sent*, not somewhere it *routed to*, and
  nothing is waiting there. The detour's own far side is queued behind the
  resolve now, on the same path the event and the shop take, rather than being
  raised over an animation that is still playing.

  **…and that stay-or-return question is asked with the offering.** It was a
  ConfirmationDialog with two game names in a sentence, on the grounds that the
  interesting decision was taking the detour. That was wrong: it is the biggest
  routing decision the detour creates, and the run shows you a map for every
  ordinary step. It is now two cover cards on the offering, each opening the same
  `GameChoiceModal` every other card does — the route from there drawn as the
  real ladder, the shop and event flags, your record in the game — with the
  Travel button relabelled to what it actually does. The card drops the enemy
  block and the tries line, because no enemy is rolled and no game is being
  committed to: this question moves the run, it does not start a game.

  **Two things are no longer drawn over an enemy's picture.** The grid outline
  that was re-drawn on top of the art (so a sprite filling its square still
  showed a border) ruled a line across every body, and the boss skull and the
  "in 2" walking counter sat across the head of the art — on a 7×7 board's 46px
  cells, over most of what identifies the enemy. Both are gone. Nothing is lost:
  a boss is already drawn in the boss's own orange and carries its portrait
  beside its name on the checklist, and the walking still owed is the first line
  of the body's own hover.

---

- **Gold, and a shop at every hub on the map.**

  **A defeated enemy pays 1 gold, a boss 3, and that is the whole faucet.** The
  numbers are deliberately a tenth of the combat build's — gold used to start at
  99 and the Challenge Rift paid 50, at which scale a price is a rounding error
  and every purchase is automatic. A run is 6–12 games, so clearing most of your
  goals earns 8–15 gold against prices of 3–6: **two to four purchases in a whole
  run**, each of them a decision. It also keeps every figure on the HUD to one
  digit, which the OBS companion window (§9) is going to need.

  Gold **rides the drop, not the corpse** — it is paid inside the branch of
  `GameLoop2._defeat` that grants the item, which gets three rules for free. The
  current game's enemy pays. A follower whose old goal you fulfilled five games
  late pays exactly the same, because the goal was the price either way and
  taxing a slow solve would argue against the stack the whole run is built on.
  And a **bombed** enemy pays nothing: a bomb already drops no item, it is an
  escape from a goal you couldn't do, and letting it mint currency would make
  bombing the cheapest way to farm the shops.

  **Shops stand at the ten best-connected games on the map** — Slay the Spire,
  Vampire Survivors, Isaac, Hades, Balatro, Spelunky Classic, FTL, NetHack, Dead
  Cells, Enter the Gungeon on the full catalog, and whatever the ten biggest are
  on an OWNED run, since hubs are measured after the filter like every other
  degree question. The degree curve has a real shoulder at ten: the eleventh game
  down is in the low twenties with a long flat tail behind it.

  **This is a second routing axis, and it is the opposite shape to events.** An
  event hangs off a dead end — a two-game round trip for one game's reward, which
  is why it needs a badge to be worth taking at all. A hub is the *middle* of the
  map, rarely far off the road, so "swing through the big node" is cheap and
  repeatable. Until now every step was measured against one question, which was
  whether it took you closer to the Amulet. This is the second one.

  **The shelf is three items and it stays.** Stock rolls once and persists for the
  whole run; buying marks a slot sold rather than removing it. So a hub you
  cleared out is a hub you know is empty, and a hub you left two items at is a
  reason to come back — which is the point, and why **opening that game's card
  later lists what is still on its shelf and what it costs**. A shop you have
  never visited says only that one is there: the stock is what the first visit is
  for, and drawing a card must never decide what is in a shop you haven't walked
  into. Rerolling costs **1 Scramble**, not gold, because a shelf of three things
  you don't want is the same problem as an offering of three games you don't want
  and deserves the same answer — and pricing it in gold would let a rich player
  grind the whole 21-item catalog at one hub.

  **Every character now starts with 3 gold**, from a new `Gold` column on
  `characters2.0`. Three is exactly one Common item, so the first shop a run
  reaches is always worth walking into. It sits between `Health` and `Bash`
  rather than inside the verb block, because `Bash`..`Keys` is a contiguous range
  that both the generator and `GameState.START_RANDOM_POOL` walk. Gold does not
  carry between runs.

  **`Epic` is gone from `ItemData.Rarity`.** Nothing ever rolled it and nothing
  was ever authored at it — it existed only to make `ItemData.Rarity` and
  `Data.RarityStep` disagree about what the number 3 meant, which cost a
  translation function every time a rarity was rolled. Shop prices are "3 gold
  plus the rung", which is the third thing that wanted the ladder to have no
  holes in it. The two enums are now identical, `roll_item_rarity` is a
  pass-through, and one 2.0 item and two legacy ones moved from rarity 4 to 3.

- **Reaching the Amulet is the win, and three fixes around it.**

  **Beating the Amulet game wins the run — the goal box is a bonus.** It used to
  require BOTH: the Amulet game reported AND the goal-enemy standing there
  satisfied. So a player who walked the whole road, got to the Amulet game and
  beat it, but hadn't happened to "destroy an enemy spawner" on the way through,
  watched the run carry on as though nothing had happened. The entire run is a
  search for one game; arriving and playing it is the answer, and the enemy's
  goal is a bonus on top rather than the lock on the door. The report step says
  so now — the row reads "🏆 Amulet goal (bonus)" with a line under it — and the
  win is recorded against that game either way.

  **The health badge is no longer buried by the damage badge.** ❤ and ⚔ were
  anchored to opposite bottom corners of a body, so each grew from its own corner
  inwards — and the moment an enemy got a second swing, "⚔3×2" grew left and
  printed itself straight over the ❤. It bit exactly when it mattered most:
  multi-swing means the Amulet is close, which means the board is at its widest
  and its cells at their smallest (46px at 7×7), so the damage badge was at its
  longest over the least room. They share one row now — health left, damage
  right, a spacer between — which is identical to the old corners whenever both
  fit and simply cannot overlap when they don't. The badge also lost its space
  ("⚔3×2", not "⚔3 x2"), which is a whole character of width back.

  **A pickup repaints everything, not just the pack.** An item's payload lands on
  the run the instant it is taken — passive stat bonuses folded in, item_acquired
  effects already fired, a shield already spendable, a Mine-r Construction having
  already grown the board — but the handler relisted the pack and repainted the
  chip row only. The shield pips, the battlefield summary and the board itself
  went on quoting pre-pickup numbers until the next report refreshed them. The
  board is the one thing that waits: a repaint frees the bodies a resolve
  animation is mid-slide on, so a pickup during the playback defers its repaint
  to the end of it rather than wiping the animation it landed in.

  **Confirmed: escaping fires no "after game beaten" trigger.** It already
  didn't — everything hanging off finishing a game (the item hook, the Harvesting
  gold payout, the recharge tick charged actives live on) comes through
  TriggerBus.game_beaten, which sits inside the not-escaped branch. Now pinned by
  tests, in both directions: an escape fires none of it, a game played to a
  verdict fires it even when the goal was missed.

---

- **Four more from playing it, and one crash.**

  **Escape is open from the first second on a game you have played before.** The
  way out of a game you can't beat was gated behind five lost runs, which is the
  right price for a game you have never got through — the alternative is a player
  who quits the run instead — and exactly the wrong one for a game you have
  already cleared. There is nothing left to prove there, so being made to lose at
  it five more times to unlock the door is a tax on the least interesting thing
  in the run. `can_escape` now has two doors: the lost-runs rule for a game with
  no record, and immediately for one with. The tooltip says which is holding it
  open.

  It is the same escape either way — only the gate moved. The goal-enemy still
  walks onto the board, everything already out there still takes its turns, and
  the game still isn't credited (no drop, no event, no beat).

  **And BEATEN now means WON.** The escape reads the run's own beaten list, and
  that list was a lie: any report that wasn't an escape banked the game, a missed
  goal included. So "⚔ Beaten 11 times" counted visits, `has_beaten_game` meant
  "been here", and a game you had FAILED paid the repeat-beat Dash for failing it
  a second time. Every one of those reads as a claim about winning, in the UI and
  in the code, so all of them now require the goal to have actually been met —
  the run's list and count, the lifetime tally the Collection and tier list
  print, the amulet win, and the Dash.

  The escape's door is the RUN's list, not the lifetime one: a win in some run
  last week is not a fact about this one — different character, different board,
  and the shields have to be spent again either way. What it is for is the
  repeat, the game already cleared earlier in this same run, which is the card
  the offering flags with ⚡ +1 DASH and the one it is pure grind to be held at.

  One thing deliberately left wider: `TriggerBus.game_beaten`, which paces the
  "after beating a game" items, still fires on any game FINISHED rather than won
  (an escape is the only report that doesn't fire it). Every one of those items
  is balanced around firing once per game played, so narrowing it is a balance
  decision rather than a naming fix.

  **The compendium's grid art is half the size.** Games, items, characters and
  enemies were drawing 190/100/120/116px thumbnails, which fitted three game
  covers across; the compendium's job is to let you SCAN 833 games, and a grid
  you page through four at a time is a scrolling exercise. Halved, with the cells
  and the name faces brought down to match, a row holds five. The DETAIL panel is
  untouched: that is where you look at one piece of art properly, and it is the
  reason the grid doesn't have to.

  **Events are in the compendium.** They were the one 2.0 set it didn't carry and
  the set it helps most: an event fires once, mid-run, inside a modal you answer
  under pressure, and the three options you didn't take are then gone for good.
  The new tab lists every event with its art, rarity and choice count, and the
  detail panel carries the prompt, where on the map it can appear, its tier and
  state gates, and every choice in full — effects, goals, curses, repeats and
  locks. Search reaches the option text, because that is how anyone actually
  remembers one.

  **Dev mode was full of the old game.** The Add-item list appended
  `Data.all_items()` — the 112 combat-era relics from the build this one replaced
  — on top of the 21 that ship. They are `ItemData` too, so they listed and
  granted cleanly and then sat in the pack doing nothing, because no games-first
  code honours them. The pool is `DevTools.item_pool()` now, 2.0 only, with a
  test that says so.

  **A repaint under the cursor no longer errors.** Clicking an enemy repaints the
  board, which detaches every body on it — including the one the mouse is over,
  whose `mouse_exited` Godot then fires from inside the removal loop. That
  handler restores the body's draw order, so it called `move_child` on a parent
  mid-removal: "Parent node is busy setting up children". The hover handlers now
  stand down during a repaint (and on a node that has already been detached),
  which costs nothing — the repaint rebuilds every node they would have been
  reordering.

---

- **Five UI passes, all from playing it.**

  **It opens in a window now, and that is the default.** The game shipped
  borderless-fullscreen and the reasoning still holds as far as it went — you
  alt-tab out of this game constantly, and borderless swaps instantly where
  exclusive is a mode switch — but it skipped the step before: a window that
  covers the screen also covers the taskbar you are alt-tabbing *with*. So
  `project.godot` opens `mode=0` (WINDOWED). Both fullscreens stay on the
  Settings list and F11 still toggles; leaving either one now re-fits and
  re-centres the window instead of handing back a "window" the size of the
  screen.

  The window and the canvas are two different numbers, and only the canvas is
  1280x720. That stays exactly as it was — it is the box the layout is built to
  fit, and `stretch/mode` scales it into whatever the window is — while
  `window_width/height_override` opens the WINDOW at 2560x1440, so a 1440p screen
  draws the page at 2x rather than in a corner of the desktop. The size is a
  request: `Settings.windowed_fit()` clamps it to the screen's usable rect minus
  the window frame (the title bar sits outside the size being set, so a window
  fitted to the usable rect exactly still hangs its bottom edge under the
  taskbar), floored at 1280x720 because a page shown whole under a taskbar beats
  one cropped to fit above it. It is a pure static function because a headless
  runner has no window manager, and so no decorations and no taskbar to check any
  of this against. The saved preference moved to a versioned key
  (`Settings.DISPLAY_KEY`): a `settings.cfg` written under the old default holds
  an explicit borderless value for a player who never chose one, and reading a
  new key is what tells "never chose" apart from "chose the old default" —
  exactly once, after which a real choice sticks.

  **Push is a direction now, not a distance.** It shoved a body one column back
  and that was the whole verb: a delay, priced the same wherever it was spent. It
  now moves one body one cell in **any cardinal direction**, and the grid's own
  rules give each one a different job — back buys the games it takes to close in
  again, forward hands over a free step to unjam a column, and **up/down is a
  lane change**, which is the one move an enemy can never make for itself
  (`path_blockers` is written on enemies never changing lanes). Shoving a body
  into an occupied lane parks it behind whatever is there for good; shoving it
  out of one opens the road it was blocking.

  The interaction inverted with it. It used to be select-then-verb, which meant
  the Push button spent its life disabled explaining why. Now the verb is **armed
  first and aimed second**: press `⇤ Push`, click the enemy, and an arrow appears
  on every side of that body a shove could actually land on. Nothing is spent
  until an arrow is pressed, so arming, re-aiming and cancelling are all free —
  and a direction the rules refuse is never drawn rather than drawn and refused.
  `GameLoop2.push(instance, dir)` defaults to BACK, so the enemy card's one
  button, DevTools and the headless harness all still mean what they meant.

  **The choice popup's cover got out of the way.** At 210x280 the box art ate the
  left column of `GameChoiceModal` and pushed the enemy, its goal and the statuses
  riding on it under a scrollbar — and the cover is the one thing on that popup
  you have already seen, because it is what you clicked. It is 140x187 now and
  the enemy's portrait went up to 96px on the room it gave back.

  **The map window minimises instead of closing.** Over the star chart it had a
  Close of its own, a metre from the chart's Close, and pressing it threw away
  the route ladder you had just opened — the chart's own Close already takes both
  down together. The corner button rolls the window up to its title bar and
  unrolls it again, keeping its position and its width so the bar doesn't move
  under the cursor that clicked it. Opened *without* a chart under it (the start
  picker, or an unbaked atlas) the panel is the only thing on screen, and there —
  and only there — it still keeps a Close.

  **A repeat game says so on the card.** Beating a game you have already beaten
  this run pays +1 Dash, and that was stated only inside the popup — so the one
  card on the table worth revisiting looked exactly like the ones that aren't.
  There is a `⚡ +1 DASH` line above the cover now, mounted on every card and
  blank off a repeat, so one badge doesn't knock the other covers out of line.

---

- **Five things the events pass got wrong, found by playing it.**

  **A "Small Chest" was opening two items.** `gain_chest` carried the chest's
  SIZE as `choices` — small 1, medium 2, large 3, huge 5 — and the handler
  dropped it on the way to `grant_chest`, so every sized chest fell through to
  the reward screen's own default (`BASE_ITEM_CHOICES` plus Discovery). The size
  reaches the screen now, which also means the Battleworn Dummy's ladder is real:
  Setting 2 pays one item, Setting 3 pays three.

  **Two chests are one screen with two chests on it.** They used to open two
  screens back to back, which reads as a single screen flickering — you cannot
  weigh the second chest's offer against what you just took from the first, and
  nothing marks it as a different chest at all. `RewardScreen.setup_chests()`
  takes every banked chest at once and gives each a labelled group with its own
  roll and its own pick, so "+2 Small Chests" is visibly two chests of one item
  rather than one chest of two. A chest you have answered collapses to a ✓ and
  the screen waits for the rest.

  **An event goal is on the checklist the moment you take it.** Events fire when
  a game is beaten, so the goal lands while the player is still looking at the
  OFFERING — but the choosing-phase checklist only listed enemy goals, statuses
  and the level-up. Taking on "beat a game in 1 attempt" and then being shown
  nothing about it until after picking the next game is exactly backwards, since
  the goal is the thing that should inform that pick. Event goals and curses are
  read-only rows there now, countdowns included.

  **Enemies whose art fills the square have their border back.** The footprint
  tiles carry the threat colour, the selection ring and the hover cue, and they
  were drawn UNDER the art — fine for a sprite with space around it, invisible
  for one drawn edge to edge like the Wisp. There is a second, transparent,
  border-only tile over the art now, so a full-square enemy shows the same
  outline as every other and its threat colour is legible again.

  **Health is in the top-left corner and never moves.** It lived on the
  battlefield beside the hero, which meant the one number that ends the run was
  covered whenever anything mounted over the board — a chest, an event, a reward
  screen. It is a header chip now, repainted from the same `_refresh_stats` every
  `hp_changed` already routes through, and it goes white-hot under a quarter. The
  title gave up the left edge for it and took the centre.

  **And an event can be put away.** Beating a game that both drops a chest and
  fires an event used to stack three things on one screen while the board was
  still animating underneath them. The event modal has a **Hide** button (and
  Escape now hides rather than doing nothing): the panel and its click-blocker go,
  a "✦ *event* — resume" chip sits in the bottom-right corner — clear of the Menu
  button and the toasts — and nothing about the event resolves until it is
  brought back. Watch the board, take the chest, then answer the event.

- **Events are built.** The sheet had a format and four authored events and
  nothing that read them; now the run does. `CurseData2` / `EventData2` plus two
  generators turn `curses2.0` and `events2.0` into `data/`, a new `EventSystem`
  autoload owns placement and resolution, `EventModal2` is the screen it happens
  on, and `Overworld2` grew a badge and two checklist sections. 22 tests in
  `test/test_events2.gd`; the suite is 745 tests, 743 passing, 2 risky (the two
  documented early-returning graph tests).

  **The reward-token DSL still has exactly one implementation.**
  `generate_status_tres.py` owns it and the two new generators import it rather
  than learning `gain_chest small 1` a second and third way. It grew the cost
  half of its vocabulary for this (`lose_hp`, `lose_max_hp`, `lose_stat`,
  `lose_gold`, `heal_full`, `gain_loot`, `apply_status`, `obtain_item`,
  `nothing`) and every existing status regenerated byte-identical.

  **Placement is hashed, not rolled**, and that is the load-bearing decision in
  the whole feature. A card's badge is a promise about what is waiting at that
  node, and the offering is redrawn constantly — a bash refilling a slot, a
  scramble, an arrival. Roll the event when the card is drawn and the badge lies
  the moment anything redraws. So `EventSystem.event_for(node)` hashes the node
  id against a new `GameState.run_seed` (saved with the run, so it survives a
  reload and not just a redraw), exactly the way `_slot_enemies` keyed off
  `_offer_seed()` already pins the enemy behind a card.

  **The badge shares the Amulet's row.** `_make_choice_card` already mounts a
  fixed-height label above every cover, blank off the Amulet, so the covers stay
  in line — `✦ EVENT` goes there in accent orange, and the Amulet wins the row
  when a card is both, because winning the run outranks a bonus. The choice
  popup names the event, since that is where the routing decision actually gets
  made (§4.2).

  **Only a beaten game earns its event.** Escaping forfeits it and leaves it
  standing for a later visit, which keeps it a reward rather than a toll for
  arriving. The modal opens from `_end_resolve`, after the board has finished
  playing the resolve back, so it never lands on a moving battlefield.

  **The checklist now carries three kinds of row and three colours** — enemy
  goals green, event goals accent, curses purple (`UITheme.CURSE`, new). Both of
  the new kinds show their countdown, because an objective with a clock on it is
  a different decision on its last game than on its first and the player can see
  that clock nowhere else. A claimed event goal retires; a triggered curse does
  **not** — only its timer clears it, which is the entire difference between a
  bonus and a bill, and the one thing a test would have caught if it drifted.

  **`play_game` moves the player and nothing else does.** It picks a tagged game,
  runs it as an ordinary game — enemy and all — without counting as a route step,
  pays the `->` payload when it is beaten, then offers stay-or-return, with
  "stay" only when the game is really on the run graph (standing on a node with
  no edges is a dead run). When no game carries the tag it pays out anyway rather
  than swallowing a choice the player already made in good faith.

  One tool fix fell out: `_xlsx_surgery.write_grid` matched only the paired
  `<sheetData>` form, and a sheet that has never held a row writes it
  self-closing, so the first write to `curses2.0` would have resized the
  dimension and written nothing. It matches both now and raises if it finds
  neither.

  **The modal sizes itself to its content.** Two columns when there is art — the
  picture on the left, the words and the buttons on the right — because a
  full-height illustration plus the Abyssal Baths prompt plus four choices with a
  mechanical line each ran off the bottom of a 720p viewport in a single stack.
  Side by side, the art costs no vertical room; the panel then fits whatever is
  in it and only starts scrolling once that would overflow the window, art
  staying put beside the scrolling column. A two-option event is a small card, a
  nine-option one is a full-height panel with a scrollbar, and neither is padded
  out to the other's shape.

  One Godot trap on the way: centring a panel by writing `position` stores it as
  an offset from `anchor × parent_size`, and this modal's parent is a Control in
  a CanvasLayer that has no size yet when the fit pass first runs. With a
  zero-size parent the panel rendered half off the top-left corner. Writing the
  offsets directly is absolute and lands the same whenever it runs.

  **An event that sends you to a tag is not staged unless the tag has games.**
  Punch Off's whole bargain is "do the work and take everything" against "take
  the treasure and wear the Injury" — with no mecha game to go and play, the work
  option is a dead button. The pool is now checked before the event is placed,
  which is before the badge is drawn, so the badge stays honest. It also fixed a
  real bug: the destination roll used to sweep the whole catalog and ignore the
  run's game filter, so an OWNED run could be sent off to a game the player does
  not own. Gate and roll now read the *same* list — if those two disagreed, an
  event could advertise a detour it cannot deliver — and the rule is derived from
  the event's own content, so a future `play_game tag=<anything>` is covered
  without anyone remembering to ask.

  `docs/event-sheet-authoring.md` §12 is the map of what runs where.

- **Events have a home, and it is the dead ends.** Almost half the map is a leaf:
  330 of the 833 games have exactly one connection, and another 199 have two.
  Visiting a leaf is a **round trip** — a game in, a game back out the way you
  came — for one game's reward, and every card already quotes that cost to the
  player as a route badge. The hub rule (`HUB_CONNECTIONS`) fixed the *routing*
  half of this years ago by guaranteeing a way onward from a big node; nothing
  ever made the small node worth entering.

  So an **event fires after the game at a dead end is beaten**, on top of the
  normal drop. That one placement rule answers both of the questions that had
  been keeping events shelved — where they go, and why anyone routes into a
  corner — and it sets the exchange rate: a dead-end event should pay about one
  game's reward, because one extra game is exactly what the detour costs.

  The `events2.0` sheet is **one row per event**, like every other `*2.0` sheet,
  with the choices in numbered column groups — `Choice 1 | Repeat 1 | Result 1 |
  Effect 1`, then the same four for 2, 3 and 4. Twenty-eight columns. The reason
  the choices are *columns* rather than one packed `Choices` cell is that an
  event is mostly prose, and prose needs a cell of its own to be editable at all.
  That is how the old `events` sheet failed — catalogue metadata in the sheet,
  and every choice, outcome and effect hard-coded in an `AUTHORED` dict inside
  `generate_event_tres.py`, so the sheet could not hold the part of an event that
  *is* the event. Numbered groups keep every string in its own cell *and* keep
  the sheet sortable and filterable like the others.

  `Effect` is the **`statuses2.0` reward-token DSL, reused unchanged**, so a
  chest an event pays is the chest an item pays. `{X}` holes come with it — and
  inside an event **X is the number of times this choice has already been
  taken**, which together with the new `Repeat` column is the whole
  push-your-luck grammar. One authored group escalates on its own instead of four
  near-identical groups drifting apart the moment someone tunes them.

  **Abyssal Baths** (Slay the Spire 2, the Underdocks) is authored as the first
  event, in the game's own words — prompt and outcome text verbatim — because it
  is two-stage and exercises every column. `Immerse` is `Stay`: it keeps the
  event open but takes *itself* off the table, which is how a second stage fits
  on one row without a stage column. The loop is a different button, `Linger`,
  `Again` with `lose_hp {4+X}` — 4, then 5, then 6, exactly Slay the Spire 2's
  climb. And the two exits are gated against each other with the new
  `needs <Choice> <op> <n>` form: `Abstain`'s heal is offered only to someone who
  never got in (`needs Immerse = 0`), `Exit Baths` only to someone who did. That
  gate is load-bearing — without it the line is "bathe until nearly dead, then
  heal", which is what the original refuses to allow and what an earlier draft of
  this event accidentally permitted.

  The event uses only effect tokens that already exist, so it needs no new
  `EffectSystem` handler to run. Its *gains* are tuned to this game — +1 Max
  Health a dip, Abstain heals 3 — while its *costs* are still Slay the Spire 2's
  3, 4, 5, 6, which at a 5–10 Health pool makes the water a poor trade at every
  depth. The scaled costs are written down beside it in the doc; swapping is two
  cells, which is the point of the sheet being upstream.

  **Battleworn Dummy** (Slay the Spire 2, Glory) is the second event, and it is
  the one that proves the format bends. Its dialogue is verbatim; its *mechanic*
  can't be, because the original is three turns of combat against a dummy of
  chosen HP and this game has neither turns nor HP bars to swing at. What ports
  is its actual shape — pick your own difficulty, then go and prove it, on a
  clock. The 75 / 150 / 300 HP settings become **beat a game in 5 / 3 / 1
  attempt(s)**, and the three turns become **three games**:

      Setting 1  add_goal "beat a game in 5 attempts or fewer" for 3 games -> gain_scroll 1
      Setting 2  add_goal "beat a game in 3 attempts or fewer" for 3 games -> gain_chest small 1
      Setting 3  add_goal "beat a game in 1 attempt"           for 3 games -> gain_chest large 1

  Attempts were already the right currency: shields **are** the tries (§3.2) and
  `GameLoop2.attempts()` already counts them, so "beat a game in 1 attempt" asks
  nothing new of the run — only a checklist row to hang it on. `add_goal` gains a
  `for <n> games` window for this, and event goals get **their own section of the
  post-game checklist**, kept apart from the enemy goals: an enemy goal is a debt
  that hits you when missed, an event goal merely expires, and rendering them
  alike would misrepresent which one bites.

  It also earns the sheet two new columns. An `add_goal` event does not finish in
  the modal — it finishes on the checklist, up to three games later, long after
  the modal closed — so its two endings have nowhere to live in a choice's
  `Result`. **`Goal Met` and `Goal Missed`** are event-level, because they belong
  to the event's voice rather than to the option taken: the Dummy congratulates
  and insults you in exactly the same words whichever setting you picked.

  **Unrest Site** (Slay the Spire 2, the Overgrowth) is the third, and it was
  authored as a deliberate test of how far the format bends. It bent in exactly
  one place. The event only appears at **70% HP or below** — the whole bargain is
  about being hurt, and without that gate "heal to full" is a free top-up the
  curse buys nothing for — and nothing in the sheet could say so: `Tier` gates on
  the ladder, `Where` gates on the map, neither gates on the *player*. So there
  is now a **`Requirement`** column, the state gate, `hp <= 70%`.

  What it did **not** need a column for is the more interesting half. Unrest Site
  introduces a **third kind of objective**, and it arrives entirely through a
  token:

      Rest Anyways    heal_full; add_curse "you use a rest site to replenish
                      health" -> lose_hp 2
      Kill the Trees  lose_max_hp 2; gain_chest small 1

  An enemy goal is a **debt** — miss it and it follows you and hits. An event
  goal is a **bonus** — miss it and it merely expires. A **curse goal** is
  neither: a standing objective you want to *not* meet, that costs you every time
  you do meet it, for the **3 games** it lasts. It is the first thing in the game
  that punishes you for succeeding at the wrong thing, and its checklist rows
  read **purple** so the one objective you are trying to avoid never looks like
  the ones you are chasing.

  The rule that fell out is worth keeping: **a new kind of consequence should
  cost a token, not a column.** `add_curse` carries the kind, the kind picks the
  section and the colour, and the sheet never learns what a curse is. A
  `Goal Type` column would have been the tempting wrong answer — a new value for
  every kind, and a blank on every event that isn't it.

  (Not to be confused with the shelved `CurseData` / `data/curses` system,
  §5 of the spec. Same word, different thing: a curse goal is a checklist row,
  not a card.)

  Changed from the original, both requested: Max Health lost drops 8 → 2, and the
  random Relic becomes a small chest — which the outcome text was already
  describing, since the byrd spirits "drop a small box at your feet". At 5–10 Max
  Health, losing 2 is a 20–40% cut where 8 of 75 was 11%, so Kill the Trees is
  now the sharper option rather than the safe one.

  Curses are authored in a **new `curses2.0` sheet** and referenced by id —
  `add_curse poor_sleep` — the same relationship an item has with `statuses2.0`,
  so a curse's condition, penalty and lifetime are written once and any number of
  events can hand out the same one. Six columns: `Curse | Game | Condition |
  Penalty | Timer | Image`. The checklist row is **generated** from Condition +
  Penalty rather than authored as prose, so a curse's text cannot drift from what
  it does — the mistake the legacy `curses` sheet made. Two curses so far, and
  they are deliberately different flavours: **Poor Sleep** fires on something in
  the *real game you go and play* ("you use a rest site to replenish health"),
  **Injury** on this app's own state ("you go below half health"). Both `lose_hp
  2`, both 3 games — the same window `add_goal` uses, so the player is never
  tracking two countdowns at different speeds.

  **Punch Off** (Slay the Spire 2, the Underdocks) is the fourth event, and it
  does something no event has done yet: it **moves the player**.

      Nab              add_curse injury; gain_chest small 1
      I Can Take Them  play_game tag=mecha -> gain_loot 1; gain_chest small 2

  `play_game tag=mecha` drops them into a random game carrying that tag, off
  their route — `mecha` is a real tag on the `games` sheet with 14 games behind
  it. The game spawns its enemy and is played under the ordinary rules; beating
  the robots *is* beating the game, and the `->` payload lands on the far side.
  Then they **choose**: stay at that game if it is connected on the map, or
  return to the node they came from. Which is worth naming, because it is the
  inverse of where this whole entry started — a dead end *forces* a round trip on
  you, and this is the one event that hands the choice back. An event that begins
  as "two robots are fighting over some treasure" ends up being about routing.

  `gain_loot` is authored as a category rather than as `gain_scroll`: it resolves
  to a scroll today, since scrolls are the only loot type there is, and widens on
  its own as more are added without an event row being touched.

  And Punch Off needed **nothing** from the events sheet — no column, no
  rearrangement. Both of its new capabilities arrived as tokens, which is the
  rule from the entry above holding up under the first event authored after it.

  Format, column reference, DSL and what is still missing (two generators, the
  requirement check, the placement seed, the badge, the two checklist sections,
  `play_game`, the modal): `docs/event-sheet-authoring.md`.

- **`_xlsx_surgery` can create a sheet now.** `curses2.0` did not exist in the
  workbook and `write_grid` can only write to a sheet that does — it resolves the
  part through workbook.xml by name. `add_sheet(name)` appends an empty
  worksheet, which means keeping four things in agreement or Excel calls the file
  corrupt: the part itself, its `<sheet>` entry in workbook.xml, its Relationship
  in workbook.xml.rels, and — the easy one to miss — its Override in
  `[Content_Types].xml`, without which the workbook opens with the sheet silently
  absent. A new part also has to join `_entries`, not just `_dirty`, since that
  is the list `__exit__` writes from.

- **`_xlsx_surgery` dropped every row it wrote to an empty sheet.** `write_grid`
  matched `<sheetData>…</sheetData>` and nothing else, but a sheet that has never
  held a row writes it **self-closing** — `<sheetData/>`. Writing the first rows
  of `events2.0` therefore resized the sheet's `<dimension>` and wrote
  no cells, and said nothing about it. It matches both forms now and raises if it
  finds neither, so the failure can't be silent again.

- **An unknown item `Type` no longer becomes a passive in silence.** The sheet
  spells Vajra and Oddly Smooth Stone `Status`, a word `KIND` had never heard of,
  so both fell through the `KIND.get(…, 0)` default to PASSIVE — and a PASSIVE
  unwinds its grant when the item leaves, which for these two would quietly take
  the status back. `status` maps to PICKUP (grant once, keep) and an unrecognised
  `Type` now prints a warning naming the item instead of defaulting quietly.

- **It opens fullscreen now, and it is the right kind of fullscreen.** The layout
  was always meant to be played fullscreen and the project never went fullscreen
  — `display/window/size/mode` was unset, so it launched in a 1280×720 window,
  and there was no toggle anywhere in the game.

  It opens **borderless** (`mode=3`, Godot's `FULLSCREEN`) rather than exclusive
  (`4`), and that is a decision rather than a default: this game's loop is
  *leaving* it to go and play a real video game and coming back to report, so the
  player alt-tabs out several times a run. Exclusive makes every one of those a
  mode switch — black screen, resolution change, and sometimes a window that
  comes back on the wrong monitor. Borderless swaps instantly. Exclusive is still
  on the list for anyone who wants it. **F11** toggles from any screen (handled
  by the `Settings` autoload, so no screen has to forward it), **Settings →
  Display** offers all three, and the choice persists to `user://settings.cfg`.

  Worth writing down, because it is the fact the previous entry's whole
  one-screen exercise rests on: **fullscreen does not give the layout more room.**
  `stretch/mode` is `canvas_items` over a fixed 1280×720, so the logical viewport
  is 1280×720 on a 1080p monitor, a 1440p monitor and a 4K one alike — the same
  page, drawn bigger. Measured at 1920×1080, 2560×1440 and 2560×1600 to be sure.
  Fitting 1280×720 *is* fitting the screen.

  One thing did change with it: `stretch/aspect` goes from the default `keep` to
  **`expand`**. `keep` letterboxes anything that isn't 16:9 — a 16:10 monitor got
  bars top and bottom, an ultrawide got them at the sides — while `expand` hands
  those pixels back as real canvas (16:10 → 1280×**800**, 21:9 → **1706**×720).
  It can only ever give *more* than the base size, never less, so the one-screen
  guarantee is untouched and the tests that pin it still read as a floor. Checked
  on all four shapes: no bars, no scrollbars, borderless, covering the screen.

---

- **The whole overworld on one 720p screen.** The page had been growing a row at
  a time and was 130px past the bottom of the window it ships at; it now fits
  1280×720 with no scrollbar in either axis, in every phase, at every board size
  up to 7×7. Nothing was hidden to get there — every cut was a thing being drawn
  twice.

  **The HUD strip is gone.** Once the verbs moved out it was Health, Shields and
  a status strip, and the **board was already drawing all three on the hero** —
  `♥ hp/max` under the portrait, the shield pips over it, the player's status
  pips between them. The panel was quoting the board back at itself for 44px. The
  vitals / stats / pickup signals now land on the hero (`BattlefieldView.
  refresh_hero`, split out of `refresh`), so a Hollow Heart off a kill-drop moves
  Max Health on screen the instant it lands, which is what the strip was for.

  **The Tier / Push / Bombs row went the same way**, one commit after it arrived.
  The board draws those too, and always did: its pressure bar ends `▦ 4×4 · Low`
  and its toolbar buttons are literally `⇤ Push (1)` and `✸ Bomb (3)`. The
  choosing verbs — Bash, Dash, Transmute, Scramble — keep their chip row under the
  offering, because nothing else was drawing those.

  **The header is the title and one `☰ Menu`.** Save, New run and Main menu were
  three buttons parked across the top for the whole run and none of them is
  pressed while a decision is open, so they are menu entries now. The 🗺 Map
  wasn't admin — it is the road the offering is choosing the next step of — so it
  moved into the offering's own heading row, on the right.

  **The hover preview is one line** instead of a framed panel with a 64px
  portrait (84px → 22px). The popup draws the enemy at full size now; what a
  hover is for is the fastest read on the way past, so the line carries the
  enemy, the goal, and the **tries** — which is where the shield-grant preview
  landed when the HUD slot it used to live in went away.

  **Scrolls are tokens on the pack strip**, beside the relics, with a small Read
  above each. A scroll is a thing you carry and spend exactly like a Usable relic
  is, and it had been getting a titled panel of its own — first at the foot of
  the page under the log, then a second heading inside the pack. **The result
  line** moved off the bottom of the page into the panel that asked about the
  game, where it is the third copy of something that already toasts and is
  already in GameLog.

  **The board is fitted to a HEIGHT budget as well as a width one**
  (`FIELD_HEIGHT_BUDGET`). It had only ever been fitted across, which kept a 7×7
  board inside its column but still ran it off the bottom of the window; the cell
  edge now takes the smaller of the two fits. It binds on nothing but the big
  boards — a 4×4 is capped by `CELL_MAX` long before either budget is the
  constraint.

  And the **checklist rows wrap**. A level-up clause on one unwrapped CheckBox
  claimed 772px as its minimum width, which is what had been putting a horizontal
  scrollbar under the entire page.

---

- **The stats moved to what they do, and a card asks before it commits.** Two
  changes to the overworld's layout, both undoing the same problem: a decision
  and the things it needs were on opposite ends of the page.

  **The HUD is the player now, and nothing else.** It used to be twelve numbers
  in one strip across the top — Health, Shields, Tier, Bash, Dash, Push,
  Transmute, Scramble, Bombs, Keys, Scrolls, Chests — which is a strip nobody
  reads. Health and Shields stay where they were, top left, because they are what
  is true about *you*. Everything else went to sit under the thing it is spent
  on: **Bash / Dash / Transmute / Scramble** on a chip row beneath the offering,
  since every one of them changes what is on the table; **Tier / Push / Bombs**
  on a chip row beneath the board, since every one of them acts on the field. A
  charge you can fire from where it is drawn (Dash, Scramble) is a button there —
  which also retires the duplicate Dash and Scramble buttons that used to sit
  above the cards while their counts sat on the HUD. One that needs a target
  (Bash and Transmute pick a game; Push and Bombs pick an enemy) is a readout
  whose tooltip says where it actually gets pressed. **Scrolls** moved into the
  pack, which is where a carried thing belongs — they had their own panel at the
  foot of the page, below the whole two-column stage, filed under the log.
  **Keys and Chests came off entirely**: Keys are deferred and unauthored (§4),
  and a chest is redeemed the moment it lands, so its count was a zero the player
  never saw move.

  **Clicking a game opens it rather than taking it.** The offering was a routing
  decision made on a click, so every fact that decision needed had to be printed
  on the cover: a route badge, a pace warning, the tries it grants, a repeat
  bonus, a 🗺 Map button, a Beatable row, and the Bash/Transmute verbs. Seven
  stacked rows per card — which is why the covers had to be *halved* when the
  offering moved in beside the board, and the offering still ran taller than the
  board next to it. So the click asks instead. **`GameChoiceModal`** opens on the
  game: the **optimal path from there drawn as the real route ladder** — the same
  arrowed shortest-path graph the 🗺 map window shows, no longer one click
  further away than the decision it informs — beside the game at full cover size,
  its type and year, the tries, the pace, your record in it, and the enemy waiting
  there with the goal you would actually be playing for. Under all of it, the
  three buttons that answer the card: **Travel**, **Bash**, **Transmute**. The
  modal decides nothing itself — each button calls the same public verb the cards
  always called (`pick` / `bash_choice` / `transmute_choice`), so a headless test
  drives the run exactly as before.

  The card, freed of all that, is the **cover, the name, and the Amulet's flag**
  when it is the one — and the cover goes back up to 150x200 from the 105x140 it
  had been squeezed to.

  The ladder itself is now **`RouteLadder`**, lifted out of `RunMapModal` so the
  map window and the popup draw one graph from one place rather than two that can
  drift.

---

- **Statuses where you fight, items you can read, and a dev panel worth opening.**
  Four changes, all about seeing what the run is doing to you.

  **Statuses are on the board now.** The player's draw as art pips between the
  hero's portrait and their health — tries / who you are / what is riding you /
  what is left of you, top to bottom. An enemy's draw *below* its box, under the
  ❤/⚔ row. Those two badges were printed over the middle of the art at full size
  and were covering the enemy you were trying to recognise, so they are smaller
  now and sit straddling the box's bottom edge, leaving the picture the whole
  cell. Every pip carries the full hover text, built in one place
  (`StatusData.tooltip_for`) so the board, the enemy card and the HUD chip cannot
  drift apart: name and stack count, what that side DOES, the live line at that
  stack, and whether it decays. The enemy card grew a proper status row too — art,
  name, and the clause spelled out rather than left to a hover, since the card is
  where you have already stopped to read.

  **The pack separates reading from spending.** Clicking an item's tile opens an
  ItemInfoCard — big art, description, rarity / behaviour-class / charge / source
  chips, tags, and a Use button when it can fire. Firing now lives *above* the
  tile instead of on it: a Usable item gets a Use button, and a charged item gets
  a battery — one rectangle per charge, filling left to right, Isaac's active bar
  turned on its side — which becomes that same Use button at full. So the strip
  answers "how long until I can" and "can I now" in the same pixels, and
  inspecting an item can no longer spend a charge by mis-clicking it.

  **The dev panel is rebuilt** from three grant lists into four tabs. GRANT:
  items, scrolls, and statuses with a player / current / all / random target
  picker and a stack count, listing each status's mode on the side it is about to
  land on. RUN: vitals, every board verb, gold, banked chests, level, and games
  played (the difficulty tier is derived from it, so the panel moves the count
  rather than pretending the tier is a field). BOARD: spawn any goal-enemy or
  boss, and per standing body — by instance id — stun / push / bomb / defeat /
  remove, or hang a status on it. FLOW: jump to any game, heal, clear the board,
  force the win or the loss. Everything routes through the same public API the
  game uses, so the panel cannot drift into testing a path nothing else takes;
  three small public methods were added for the ones it needed
  (`GameLoop2.despawn` / `apply_status_to`, `Overworld2.travel_to_game`,
  `GameState.verb_value`). It also had two plain bugs: it built its layer visible
  and then flipped it, so the first `` ` `` press did nothing and only the second
  opened it, and its panel had no opaque background, so the whole overworld read
  straight through the tool you were using.

  `test_run_history.test_newest_run_comes_first` was asserting run ordering by
  comparing the two runs' PATHS. `_walk` follows an unseeded start roll and stops
  at the first dead end, so two runs can honestly walk the same route — the test
  failed perhaps one run in ten for a reason that had nothing to do with ordering.
  It now asserts on the outcomes, which is what it was actually testing.

- **Statuses 2.0: two sides, authored independently.** The first cut derived both
  halves of a status from one shared Condition + Reward, with Buff/Debuff deciding
  which behaviour each half got. That made the interesting cases unauthorable, so
  the sheet now carries an **`On Player Effect`** and an **`On Enemy Effect`**
  column, one per prose cell, and each names what that side DOES:

      <verb> "<condition>" [decay] [-> <reward>; <reward>; …]

  `goal` is a standing objective of the holder's own that pays when met; `clause`
  is ANDed onto goals and required; `bonus` is optional and claimable. `decay`
  sheds a stack on completion. Because the verb carries the behaviour, **Buff /
  Debuff drives no mechanic at all** — it is the HUD tint and the collection
  filter, nothing more. Marked is the case that motivated it: a `clause` with
  `decay` on the player and a paying `bonus` on the enemy, which one shared
  condition could only ever half-express. A `clause` may not carry a reward (it is
  a requirement, not a payout) and the generator rejects one rather than dropping
  it quietly; either side may be blank, which reads as inert.

  **Fractional time windows now read as time.** An `{expr}` hole can carry a
  format, and `{1+(1/2)^(X-2):hours}` renders as "1 hour 30 minutes" instead of
  "1.5 hours" — a window is something the player holds against a clock, not
  arithmetic to do mid-run. Rounded to the nearest minute, so Dexterity at five
  stacks reads "1 hour 8 minutes" rather than "1 hour 7.5 minutes".

  **Two relics hand statuses out**, the Slay the Spire pair that grant these same
  two stats there: **Vajra** is rewritten from "+1 Bash" to **"+1 Strength"**, and
  **Oddly Smooth Stone** is ported in from the legacy `items` sheet as **"+1
  Dexterity"** (art copied to `images2.0/items/`). Both stay `Pickup` items firing
  `item_acquired`, the shape Vajra already had, so the status lands when the relic
  is taken and stays for the run. Vajra was the spec's and README's stock example
  of a passive verb bonus; those references now name what they are actually
  describing instead.

  Condition text also gained `[singular|plural]` markers, so a status reads
  "increased 1 time" at one stack and "increased 3 times" at three rather than
  picking one and being wrong at the other.

  Sheet edits go through a new **`tools/_xlsx_surgery.py`**, which rewrites one
  sheet's two XML parts and copies every other zip entry through byte-for-byte —
  an openpyxl round-trip of this workbook silently drops its seven charts. It
  resolves a sheet's part BY NAME through the rels, because the number in
  `sheetN.xml` is not the sheet's rId (`items2.0` is rId4 and lives in sheet4.xml
  only by coincidence) and guessing that mapping is how you edit the wrong sheet.

- **Statuses 2.0 — balance by rewriting goals** (`statuses2.0`, spec §13). The run
  had no lever between "an item that grants a number" and "an enemy with a harder
  goal", so a location or an event had nothing to reach for. A **status** is that
  lever, and it works on the only currency the game has: it bolts a **clause onto
  a goal**. One status is authored as two pieces — a `Condition` and a `Reward` —
  and the four ways they can be arranged *are* the system. **A buff on the player**
  is an extra standing goal on the checklist ("If the difficulty is increased 2
  times, gain +2 Small Chests, +2 Bashes") that pays out every game you satisfy it.
  **A buff on an enemy** welds "and ‹condition›" onto that enemy's goal — required,
  so it is harder to remove. **A debuff on the player** welds its clause onto
  *every* enemy's goal and sheds a stack each game you complete one. **A debuff on
  an enemy** hangs an optional bonus off it — "and if you get 3 achievements, gain
  +3 Small Chests" — claimable for the reward. So a buff pays you and taxes the
  enemy; a debuff taxes you and pays out on the enemy, and each direction has its
  own counter. Three statuses ship: **Strength** and **Dexterity** (buffs, Slay the
  Spire) and **Marked** (debuff, Mewgenics). Stacking is **Intensity** — a second
  Marked is one Marked at 2, not two Markeds — and only debuffs decay, once per
  game rather than once per goal, so a game where you cleared four followers can't
  wipe a four-stack debuff whole. A buff persists for the run, because a buff *is*
  the reward and a timer would only make it a worse item.

  The sheet gained two machine-readable columns beside its prose (added by
  `tools/_statuses_sheet_setup.py`, which patches the two XML parts it needs
  instead of round-tripping the workbook through openpyxl and dropping its seven
  charts). `Condition` and `Reward` carry `{expr}` holes over **X**, the stack
  count, so a status can scale on whatever curve it likes: Strength counts a flat
  `{X}` while Dexterity's window is `{1+(1/2)^(X-2)}` hours — 3h at one stack, 2h
  at two, 1.5h at three, tightening toward a floor of one hour while the reward
  grows. `tools/generate_status_tres.py` normalises `a^b` into `pow(a, b)` and
  every integer literal into a float (Godot's `Expression` does integer division,
  so `1/2` was 0 and Dexterity's one-stack window came out as `pow(0, -1)` hours),
  and emits `[singular|plural]` markers the runtime resolves against the live X —
  one authored string reads "+1 Small Chest" and "+3 Small Chests" correctly.

  Runtime: statuses on the player live on `GameState.player_statuses`; statuses on
  an enemy ride the **body**, in the `GameLoop2` stack entry, so one applied to the
  current game's enemy is still on it when it walks onto the board. Both save.
  **`GameLoop2.goal_text_for(entry)` is now THE goal line** — the checklist, the
  enemy card, the scroll target picker and the headless `PlaySession2` driver all
  ask for it rather than reading `GoalEnemyData.goal`, which is only ever the
  unmodified stem. (Collection, the Atlas and the note modal still show the
  authored goal: they describe the enemy, not the run.) Content reaches the system
  through a new **`apply_status`** effect — `apply_status marked 2 target=all` in
  the item Effect DSL, with `player` / `current` / `all` / `random` targeting — and
  the player reports against it through `beat_game`'s new `claims` argument, which
  resolves **before** the board does, so beating an enemy and claiming its bonus in
  the same game pays both. The HUD grew a status strip under its numbers, and the
  report checklist grew the extra goal rows and bonus rows. 40 new tests in
  `test/test_statuses.gd`.

- **12 new games and 21 games' worth of new connections** ported from the
  spreadsheet (An Amazing Wizard, Atomic Owl, Barda, Katanaut, Nadir, Roulette
  Hero, Sandwalkers, Sir We Have an Orc Problem, Sword of the Necromancer and its
  Resurrection, Tiny Auto Knights, Tower Fortress), taking the catalog to 830. All
  five Atlas skies rebaked.

- **A way onward, a way out, and somewhere for a score to land** — three things
  the run was missing. **(1) The hub rule.** On a well-connected game the offering
  shows three of dozens of neighbours, and the seeded subset could come up all
  dead ends: Slay the Spire has 138 connections and 80 of them lead nowhere, so an
  unguarded draw stranded the run there about one time in five. Standing on a game
  with more than `HUB_CONNECTIONS` (20) connections now guarantees at least one
  card with more than `ONWARD_CONNECTIONS` (2) of its own. It takes the LAST slot,
  so it can never displace the reachable amulet, and it only ever offers a
  neighbour that exists — at a small node the thin offering is the honest shape of
  the graph and is left alone. **(2) Escape.** Some games won't go down. After
  `ESCAPE_AFTER_ATTEMPTS` (5) lost runs — past the shields any game grants, so the
  player has been paying Health to keep trying — an **🏃 Escape this game** button
  appears under Completed Game and leaves the game at any time without beating it.
  The BOARD resolves as it does on a missed goal — the goal-enemy walks onto it and
  follows you — and that is the price, paid twice over by the time the button
  shows; it exists to make the way out visible to a stuck player, not to discount
  it. But **an escape is not a beat**: the run doesn't bank the game (so no
  repeat-beat Dash, and the Atlas doesn't mark it), the "after beating a game"
  items don't fire, and neither the run's nor the lifetime beaten tally moves. The
  run clock still advances — the time was spent and the board closed in either
  way. A plain missed *report* still credits the game as it always has; walking
  away is the case that isn't allowed to count. Undoing back under the line takes
  the button away again. **(3) Rating flows into the tier list.** Submitting a score on the
  ★ Rate prompt now opens the tier-list board on top, so the score lands somewhere
  the player can see it and drag it into a row while the game is still fresh.
  "Maybe later" still just closes — declining to rate shouldn't hand you a screen
  you didn't ask for. `TierListScreen` sizes itself the way `Collection` does while
  it's there, which is what it always claimed to do.

- **Six more games, a new character, and a loadout that isn't the same twice** —
  the spreadsheet grew and the build caught up with it. `Roguelikes.xlsx` now
  carries **814 games and 1133 connections** (Into The Grid, Serpent's Gaze,
  TumbleSeed, Dark Light: Survivor, Arc Seed, For The Warp — every one of them
  wired into the influence graph, none an orphan), re-imported through
  `import-games-godot.py` with covers resolved and all five Atlas skies re-baked.
  **Regent** (Slay the Spire 2) joins the roster as the eleventh character, and a
  chunk of the existing roster was re-authored — Ironclad opens on 2 Bash,
  Manager on 2 Push, Minä on 2 Transmute, Zoe on Dash + Push, and several
  level-up conditions and rewards were rewritten (Isaac's now grants a Small
  Chest **and** a Scramble, which the reward parser reads as both).

  The sheet also gained a **Random** column, and with it a starting loadout that
  is not fully known until the run begins: `start_random` is N points spent
  across Bash / Dash / Push / Transmute / Scramble / Bombs when the run starts
  (`GameState.roll_start_random`), one independent roll each, so two points may
  land on the same verb. **Keys is deliberately out of the pool** — it is a verb
  on the sheet but nothing in the build opens with one yet, and a run that rolled
  its whole loadout into Keys would open on nothing at all. Erratic Deck and
  Rodney bring their whole loadout this way; the character screens show it as a
  gold **🎲 N random** pill rather than pretending to know which verbs a run will
  get, and the roll is announced to the toast channel and the run log when it
  happens, because a loadout that differs run to run otherwise just reads as the
  character screen being wrong.

- **The offering and the board on screen at once, and a beat between them** —
  four fixes to the stage, all of them one complaint: you could not see the run.
  **(1)** The offering had a full-width band above the two-column stage, so the
  cards you were choosing between and the enemies closing in on you were a scroll
  apart — the two halves of the same decision, never visible together. It now
  sits in the **left column above the checklist**, beside the board, which costs
  the covers half their size (`COVER_SIZE` 210×280 → 105×140) and buys the whole
  decision in one screen. Every badge row on a card is pinned to a whole number
  of lines, so a title that wraps no longer pushes its cover out of line with the
  rest of the row. **(2)** The board ran off the right edge. Its cell was a
  constant 84px while the grid grows a column per difficulty tier, so a 7×7
  Insane board needed 1395px of a 1280px page and the far columns were simply
  clipped away. The cell is now **fitted to a width budget**
  (`BattlefieldView.fitted_cell`) — full size at 4×4, tighter as the ground opens
  up, never below a readable floor — and the pressure strip and combat toolbar
  **flow** instead of adding their labels up into a minimum the whole panel had
  to honour. The page's scroll is `AUTO` rather than `DISABLED`, so anything that
  ever does overflow stays reachable instead of being cut off. **(3)** The report
  checklist's tick boxes were Godot's stock glyphs — a hairline outline drawn for
  a light editor theme, which against this palette read as an empty gap.
  `UITheme` now **draws its own**: a 24px, 3px-bordered box, gold-rimmed when
  empty and green-filled with a heavy tick when answered, and the whole row goes
  green with it. **(4)** The resolve animation — the only place the run's
  consequences are ever shown — used to hand straight back to the next offering
  the instant the last tween landed. It now hands over to a **Continue button**
  that says what just happened, so the strike and the advance get a beat to be
  read in before the screen moves on.

- **Backward influences are legal, and the completion stats count the whole
  catalog** — three corrections to rules that were stricter than the game is.
  **(1)** `tools/check_map_sync.py` treated any connection pointing at a game
  with an earlier year as an integrity violation. But Year is when a game became
  available to *influence* others, not when it stopped being *developed*, and a
  roguelike is very often a decades-long project — HyperRogue (2012) taking an
  idea from Crypt of the NecroDancer (2015) is a real event. Backward edges are
  now reported for eyeballing (a mistyped year looks identical) rather than
  rejected, and `tools/map_layout.py`, which was silently dropping them along
  with every same-year link, now draws all 1120 connections — the ones that can't
  use the downward comb sweep upward into the older game instead. **(2)** The
  Collection's *Enemies beaten in (x / y)* filtered `y` by game type, on the
  reasoning that an enemy only spawns at a game of its own type — but a survivor
  **follows you across games of every type**, so any enemy can be beaten at any
  game, and both denominators are now the full roster / full catalog. **(3)** The
  report and standing checklists lead with the **goal** and name the enemy after
  it (*"Defeat 10+ spiders — Spider"*), since the goal is the part being read
  for. Stun's wording caught up with the turn ladder too: it costs one **turn**,
  which the scroll and the enemy card now price against the current pace instead
  of promising "skips its next attack".

- **Amulet pressure: the enemies speed up as you close in** — the run had one
  difficulty axis and it ticked on its own, which made routing one-directional:
  the Amulet is the win condition, so every step toward it was strictly good.
  Enemies now take **more turns per game the nearer the Amulet you stand** — 1 at
  five hops or more, 2 at three or four, **3 at two or fewer** — where a turn is
  one action: strike from the front column, or step a column closer. One turn is
  exactly the strike-then-advance the loop always resolved, so the far band is
  the old game unchanged and the near bands are that beat repeated. Route wide
  and you fight a slow stack for more games; bum-rush and you fight a fast one
  for fewer, and the followers on your tail decide which is right. Everything
  else falls out of the same rule rather than being special-cased: an enemy two
  columns back now walks in **and** swings inside one game, a **stun** costs one
  turn (a third of a game at the doorstep, a whole one in the wilds), and
  **fulfilling a follower's goal** holds its fire for every turn of the game, so
  it's worth *more* the harder you push. Alongside it the battlefield now
  **gains a column and a row on every difficulty step** — 4×4 at Low up to 7×7 at
  Insane, on top of any Mine-r Constructions — which is the counterweight: the
  tier that makes the enemies heavier also gives you more ground to lose before
  they arrive. Both halves are on screen before you commit: a colour-coded
  **strip across the top of the board** (`⏱ ENEMY TURNS ×3`, a three-rung ladder,
  the hop count that caused it, and the board's size and tier), a line on **every
  offered card** saying whether taking it speeds the enemies up or slows them
  down, a badge on **each body** reading `×2` swings or `in 2` games with the
  threat colours following that rather than the raw column, freshly-grown cells
  that **light up and pulse**, and a resolve that **plays turn by turn**
  (`TURN 2 / 3`) instead of collapsing into one slide. See §7.4 of
  `docs/games-first-redesign.md`.

- **The Atlas rearranges itself, and grew a year-ringed second layout** — a filter on the
  Collection's Constellations used to dim stars where they stood, leaving the
  survivors scattered across their neighbours' holes. It now hands them to the
  new **`AtlasLayoutBuilder`** — a GDScript port of `tools/bake_atlas.py`'s
  layout half — and the sky is packed from scratch around whatever is left, with
  its own capitals. Filtering to Deckbuilders draws the deckbuilders' own
  constellations in ~120 ms; the whole catalog re-lays in ~0.5 s; and with
  nothing filtered the baked sky is still shown untouched. A **Layout** picker
  adds a second arrangement of the same graph: a **radial timeline**, one ring
  per release year with the earliest at the centre (Rogue 1980 dead middle, 43
  rings out to 2026), and the 83 games with no connections ringed around the
  outside. Only 712 of the graph's 1,115 links are
  tree branches, so branches draw solid and cross-links fade — `AtlasLayout` now
  carries a `parent` array so the view can tell them apart. Both modes honour
  every filter.

- **The route map fits its window** — the "Map to the Amulet" ladder is built
  inside a floating panel, and a `PanelContainer` takes whatever its children
  claim on the way in and never gives it back. A five-step route measures
  ~1090×668, so the window simply *became* that: 1787px tall, most of it below
  the bottom of the screen, legend and half the rungs unreachable, route still
  clipped. The window now sizes itself after the layout pass, and the opening
  view **zooms the route down to fit** (never up, and never past legible) so you
  see the whole road rather than a quarter of it and a scrollbar.

- **Traditional transmutes off its type, and the record follows the character** —
  Transmute kept the source's game type, which made it useless on a Traditional
  roguelike: trading one long haul (5 tries, not 3) for another is no relief. A
  Traditional game could become a random game of any *other* type. That is now a
  **setting** (Settings ▸ Transmute) rather than the law, and it is **off** by
  default — same-type is the rule every other type follows, and a Traditional
  player who wants Traditional games should keep getting them. Separately, the
  level-up row on the report checklist gained a **Notes** button — keyed to the
  (game, character) pair, the way an enemy note is keyed to (game, enemy) — and
  every defeat is now banked against the **character** as well as the game, so a
  character's page carries *Enemies beaten with* and *Levelled up at*.

- **The new sheet roster, and a board that can grow** — the catalog is up to
  **804 games and 1,115 connections** (47 games and 115 links added, every one of
  them with cover art), and the 2.0 rosters gained six goal-enemies (**Numbskull,
  Wringer, Gigantic Vermin, Nemean Chariot** off Hades, **Ice Slime**, **Spider
  Kitten**), two bosses (**Scylla**; **Mom's Heart**, which had been sitting on
  the sheet without a `.tres`), and one item — **Mine-r Construction**, which
  needed a rule the runtime didn't have. The battlefield's 4 x 4 was a pair of
  constants; it is now `GameLoop2.grid_cols()` / `grid_rows()`, base 4 plus one
  per copy of the item owned, so the board **gains a column of distance and a
  lane** the moment it's picked up (§7.3). The bodies already standing keep their
  column — the board grows behind them — but the overflow queue walks onto the new
  lane at once, and losing the item puts anything it would strand back in the
  queue rather than off the edge. The backdrop is rebuilt only when the size
  actually changes, so the repaint costs nothing on every other refresh.

- **The map is the star chart now** — "🗺 Map" (the header's, and the one on
  every offered card) opens the **Atlas with the route drawn across it**, and the
  layered ladder of decisions floats over it in a **movable window**: drag it by
  its header, and the sky underneath stays live — pannable, zoomable, clickable.
  The two halves are wired together: **clicking a game on the ladder flies the
  chart to it** and opens its card, **⌖ Frame route** puts the whole corridor back
  in frame, and framing keeps clear of whichever side the window is parked on, so
  the route is never centred underneath it. A card's map routes the chart from the
  game being *considered* — its star wears an **IF YOU GO HERE** marker in ember,
  between the green you-are-here and the gold Amulet — and the corridor drawn on
  the sky is the same graph as the ladder, edge for edge. The choose-your-start
  panel is the one exception: no chart is raised there, since a route drawn across
  the sky would point straight at the game the run is a search for.

- **Clearing the Amulet game wins the run** — and says so: the end screen reads
  **🏆 YOU WIN — THE AMULET IS YOURS**, names the game you took it on and how many
  games the run lasted, and closes the road strip on that game in gold.

- **The end of a run is a screen** — a finished run no longer just prints a line
  over an overworld that's still sitting there. `RunOverScreen` opens over the
  board with the verdict (**🏆 THE AMULET IS YOURS** / **💀 THE RUN ENDS HERE**),
  how it ended (*"Health hit 0 at Scourgebringer — 5 steps short of the
  Amulet"*), the run in numbers — character, games played and beaten, health,
  relics carried, difficulty reached, how far the Amulet still was, what was
  still following — and **the road you walked** as covers and arrows, closing on
  the Amulet with a dashed arrow across the stretch a lost run never covered
  (the same picture Run History draws). From there: another run, the run laid
  over the Atlas, the menu, or dismiss it to look at the board it ended on.

- **The board gets to finish** — reporting a game used to start the resolve
  animation and change the screen out from under it in the same breath: the
  offering came back, the page scrolled to the top, and the strike and the
  advance played to nobody. The run's state still moves on instantly (nothing
  waits on a tween), but the **view** is held: the stage keeps the shape it had
  while you were playing until the board has finished, and only then does the
  offering — or the end-of-run screen — take over. The advance was also being
  measured against a stale overflow-lane token, so an enemy walking onto the grid
  read as "didn't move" and never slid at all; the lane is now detached as well
  as freed, like every other layer on the board.

- **Every offered game says where it puts you** — above each card, before the
  art: **🏆 THE AMULET — the run ends here**, **★ OPTIMAL — n steps left** for a
  game on a shortest path, **→ Sideways** for one that's no closer, or **↩ Detour
  +n** for ground given away. Read off the same BFS the "Map to the Amulet" modal
  is layered from, so a card's badge and the map it opens can't disagree.

- **A map on every card** — a **🗺 Map** button above each cover (on the offering
  *and* on the choose-your-start panel) opens the optimal path to the Amulet **as
  it would stand if you took that game** — the whole road, not just a distance
  number. From the start picker the destination is drawn but deliberately not
  named (*The Amulet — ???*): the panel gives away the distance and nothing else.

- **The Atlas says where you are and what you came for** — the you-are-here and
  the Amulet used to be one more thin ring among the owned / hovered /
  transmuted rings. They're markers now: a halo, a cased ring pair and a printed
  badge (**YOU ARE HERE**, **THE AMULET — 5 STEPS**), drawn over everything and
  at every zoom, with an arrow parked on the edge of the view pointing the way
  when one is off screen. The header gains **📍 You** and **🏆 Amulet** buttons
  that jump to either end, the HUD carries the run in one line (*📍 Downwell → 🏆
  Rack and Slay (5 steps to go)*), and both are keyed in the legend.

- **A clicked game shows its whole cover** — the Atlas card used to crop the box
  art to a 248×124 letterbox. The card is the panel you opened to *look* at the
  game, so it now fits the entire picture to the card's width (scaled down, never
  cut, if that would make it too tall). The stars themselves still inscribe art in
  the circle the packing reserved for them.

- **Filters on the Collection's Constellations** — a filter row above the sky:
  **Constellations** (6 / 8 / 12), **Library** (owned / downloaded / not owned),
  **Type**, **Record** (beaten / never beaten / amulet won / has notes) and
  **Region** (one constellation), with a Clear button and a live *"88 of 757
  games"* count. Filters combine.

  A filter **re-lays the sky** rather than dimming stars where they stand.
  Dimming leaves the survivors scattered across the holes their neighbours left
  — a picture of the full catalog with gaps in it, not a map of what you asked
  for. So the survivors are handed to `AtlasLayoutBuilder` and laid out from
  scratch: filtering to Deckbuilders gives you *the deckbuilders' own*
  constellations, cut around their own capitals (Slay the Spire, Balatro, Luck
  be a Landlord, …). It takes ~120 ms for a slice like that and ~0.5 s for the
  whole catalog. With nothing filtered the **baked** sky is drawn untouched —
  it is the one that shipped and the one you have a sense of place in.

  **Region** is the exception that stays measured against the baked sky: a
  rebuilt sky cuts its own regions, so "games from the Slay the Spire
  constellation" has to keep meaning the canonical constellation. The capital
  count (6 / 8 / 12) picks which baked sky is the base — each is its own file
  (`atlas_layout_c6.tres` / `_c12.tres`) since the cut changes every region —
  and changing it clears the Region filter. The filter row only exists in the
  Collection's catalog view; a run's Atlas has no filters and never moves,
  because routes are drawn across it.

  **Right-drag is the pan button.** Left-drag still pans, but the left button has
  to decide between "moved the map" and "picked a star" and only counts as a pan
  past 5px; the right button only ever pans, so it moves the sky a pixel at a
  time.

- **Two layouts: Constellations and Tree** — a **Layout** picker at the head of
  the filter row switches how the same graph is arranged. *Constellations* is
  the star chart: hubs with their influence trees packed around them, with the
  **83 games that have no links at all scattered in a halo around the whole
  sky** instead of being packed in among the constellations as one-star
  "components" — they aren't part of any constellation, and out there they read
  as what they are: the catalog's unjoined edge. The halo is jittered but never
  overlapping: stars are dealt into three concentric bands so anything angularly
  adjacent is separated radially, and the ring's radius is solved from those
  bounds rather than picked.

  *Tree* is a radial timeline: **one ring per release year**, earliest at the
  centre. Rogue (1980) sits dead middle, 1996 is a ring, 2025 is a ring 108
  games wide, and the **83 games with no connections at all** are ringed around
  the outside. Rings are spaced by *time*, not by rank, so the years nobody
  shipped in (1981, 1985, 1988–89) read as real gaps and the 1980s are sparse
  while the 2020s are dense — which is the shape of the catalog. A ring is
  widened past its year's place only if it has too many games to fit otherwise.

  Within a ring, a game sits at the bearing its **branch** put it at, nudged
  apart only where two would touch. Re-spacing each ring evenly would be simpler
  but every ring would pick its own phase, and a game would end up at an
  unrelated bearing from its parent — branches would cross the disk rather than
  run out along it. The influence graph is not a tree either (only 712 of its
  1,115 links are branches), so branches draw solid and cross-links drop to a
  whisper. The tree honours every filter too.

- **"Beatable:" on the offering** — while choosing where to travel, a card shows
  small portraits of the enemies you have **already beaten at that game before**:
  the enemy standing there now, and anything currently following you. It is not a
  prediction — it is your own record saying this pair has worked, which is
  exactly what you want while deciding where to drag a follower. Hovering a
  portrait gives the goal, how many times it fell there and whatever note you
  wrote. A card with nothing proven stays clean.

- **Per-game enemy notes** — games now remember **which enemies were beaten on
  them**, and you can write down how. Every enemy line on the end-of-game
  checklist carries a **🗒 Notes** button on its right; the button shows a pen
  once something is written, so an annotated row reads at a glance. Ticking the
  goal (or a follower you also cleared) logs that enemy against that game.

  On a game's Atlas card, **🗒 Notes — beaten enemies (n)** opens the list: each
  enemy's **art**, its goal, how many times it fell there, and your note under
  it, most-beaten first. Notes can be **edited or deleted** from there as well as
  written on the checklist — you often only work out how you beat something after
  the run is over. Deleting clears the note alone; how many times the enemy fell
  there is a record of fact, not a note, and stays.

  The Collection's **Enemies** tab shows the same record from the other side:
  each enemy's detail lists the **games it has been beaten in**, with cover,
  count and note in the same format, editable in place. The **Games** tab carries
  the mirror of it — every enemy beaten at that game.

  Both sides carry a completion stat as **x / y**: an enemy's *Games beaten in
  (3 / 808)*, a game's *Enemies beaten in (4 / 77)*. `y` is **every pairing that
  could be recorded, which is all of them**. It used to be filtered by game type,
  on the reasoning that an enemy is *rolled* for a game of its own type — but
  spawning isn't the only way an enemy gets beaten somewhere. A survivor
  **follows you across games of every type**, and clearing its old goal records
  it against whatever you were playing at the time, so an Action enemy beaten
  during a Deckbuilder is ordinary. The type filter was excluding real, reachable
  pairings, which is why both call sites had to guard the display against reading
  *5 / 3*.

  A note belongs to the **pair**, not to the enemy — the same goal-enemy turns up
  on many games and how you cleared it is a fact about that combination. Notes
  are written where you actually beat the thing, which is when you remember how,
  and the Atlas panel is read-only. Stored in `game_stats.json` next to the rest
  of the lifetime record.

- **A star's rim is its genre; in the Collection, its middle is your record** —
  a game you've never played is drawn **solid in its own genre colour**, and one
  you have wears a **silver** pip once beaten or a **gold** one once you've won a
  run on it. Gold outranks silver, since winning a run implies beating it and the
  rarer fact is the one worth seeing. Putting the record in the core rather than
  on the rim keeps the sky readable **as genre at every zoom**, and a record
  reads as something *gained* rather than as the absence of dimming — the earlier
  "unplayed games are dimmed" rule is gone, since it washed out most of a catalog
  nobody has finished.

  The record is drawn **only in the Collection's Constellations**. During a run
  the sky is about the run — the route, where you stand, what you've bashed — and
  a lifetime marker competes with that, so the middles stay empty there. The
  info card still carries the numbers in either view, in the Collection's own
  vocabulary: **⚔ Beaten** and **👑 Amulet won**.

- **"Show constellation" in the Collection** — the Games tab gains a button that
  opens the whole catalog as the star chart, in **pure-catalog mode**: no run is
  laid over it. No route to the Amulet, no path taken, no you-are-here or Amulet
  rings, no strike-throughs on games bashed this run, and a transmuted node shows
  the game the catalog says lives there rather than what was pasted on it. It is
  titled *Constellations* rather than *Atlas* to make the difference plain.
  "Beaten" means the lifetime record here, where the in-run Atlas also counts what
  you've beaten on the way. Same sky, same layout — only what's drawn over it
  differs.

- **Run History, over the map** — the main menu's Run History is no longer a
  stub. Every finished run is kept as **the route it actually walked**: covers
  left to right in the order played, an arrow between each pair, the Amulet
  closing the row marked won or lost. A run that died short of the Amulet shows
  a **dashed** arrow across the stretch it never covered. The screen sits **on
  top of the Atlas**, so the strip is the route in order and the sky behind it is
  where that route went; **Show on map** throws a run onto it. Runs are written
  by `GameLoop2._finish_run`, now the single exit from a run, so one can't end
  without being recorded, and they persist in `game_stats.json` (capped at 40).

- **Bash and Transmute on the map** — a **bashed** game's star is struck through
  in red and every link into it turns red, because those routes no longer exist;
  its card says so, and so does any connection touching it. **Transmute is now a
  paste onto the spot**: it used to be a property of one offering, held locally
  by `Overworld2` and cleared on every move and scramble, so it evaporated the
  moment you walked on. It now lives in `GameLoop2` as node → replacement,
  survives moving, scrambling and saving, and the node plays that game for the
  rest of the run. `GameLoop2.game_at()` is the one place that answers "what game
  is actually here". The node keeps its place on the graph, so the map draws the
  pasted game's cover at the old spot with an ember ring and its card names both
  **Now** and **Was**; a connection card keeps naming the *original* games —
  the influence claim is between those — and adds a line saying what has been
  pasted over an endpoint.

- **Connection proof, and a card for the links themselves** — clicking a *line*
  on the Atlas now opens a card showing **both games side by side**, the
  influencer on the left with an arrow to the game it influenced, the claim in
  words ("X inspired Y"), and the **evidence** underneath. Links flagged in the
  sheet as a sequel or the same studio say so. A source that's a URL gets an
  **Open source** button; the ~280 that are notes ("check folder", "game
  credits") are shown as written rather than dressed up as links. Either game can
  be inspected from the card. Clicking a star still wins over a link under the
  same cursor, since near a hub the pointer is always over some line.

  This needed data the importer had been discarding. `Roguelikes.xlsx`'s
  `connections` sheet carries a **Source** column (884 of 1000 rows) and a
  **Dev/Series Relation** column (114 rows); `import-games-godot.py` read only
  the two game names and dropped both. `GameData` gains `influence_sources` and
  `influence_relations`, index-aligned with `games_influenced`, and the importer
  now carries them through. This closes the README's long-standing "connection
  proof" roadmap item — the evidence was gathered years ago and simply wasn't
  being imported.

  **Re-importing also caught the catalog up with the spreadsheet**, which it had
  drifted behind: **6 games** (How Many Dudes?, Inkbound, Mystery Chronicle: One
  Way Heroics, One Way Heroics, Runeveil, Zoominoes) and **11 net connections**
  that were authored in the sheet but had never reached `data/games/`. The
  catalog is now 757 games / 1000 connections, up from 751 / 988. This changes
  which routes exist, so runs will differ.

- **A staleness guard on the baked skies** — `data/atlas_layout*.tres` are
  generated and committed, so they can silently fall behind the catalog: a
  half-failed import, a hand-edited `.tres`, a merge that took one side. Star
  count alone never caught it — add a connection between two existing games and
  the count is identical while the map is wrong. The Atlas tests now rebuild the
  edge set from `data/games/*.tres` and compare it to each baked sky, and check
  every star is drawn at the size its real connection count says. A failure names
  the offending connection and tells you to re-run `tools/bake_atlas.py`.

- **The Atlas — all 751 games as a star chart** — a new full-screen map
  (`scripts/ui/AtlasView.gd`, opened from the main menu's **✦ Atlas** button, or
  from the run map's **✦ Star chart** button). Every game is a star: size is its
  connection count, the outline colour is its `GameType`. Games are grouped into
  **eight constellations** around the highest-degree hubs — Slay the Spire,
  The Binding of Isaac, Vampire Survivors, NetHack, FTL, Hades, Balatro,
  Spelunky Classic — with each game joining whichever capital it reaches in
  fewest hops. Detail follows zoom: dots and constellation names when zoomed out,
  links in the middle, every star named up close. Clicking a star isolates it —
  its links light up, the rest of the sky dims — and opens a card with the cover
  art, release year, connection count, home constellation, distance from its
  capital, and a **Play the real game** button where there's a launch target.
  While a run is under way the shortest path to the Amulet is drawn over the sky
  as an **ember trail** (green behind you, ember ahead), so the run map and the
  atlas are the same picture at two altitudes.

  There is **one sky per game filter**. Setting the path filter to *owned* (or
  *downloaded*) opens a different, independently laid out map — 457 games, its
  own capitals, Enter the Gungeon promoted where Balatro sits on the full map —
  because a route through an unowned game doesn't exist for that run and drawing
  it would be a lie.

  Positions are **baked, not computed at runtime** — `tools/bake_atlas.py` writes
  `data/atlas_layout*.tres`, and `import-games-godot.py` re-runs it for every
  filter, so editing the spreadsheet moves the sky. Inside a constellation each game orbits the game
  that influenced it, with subtrees packed as discs around their parent; a
  subtree's radius is *measured* from its realised layout rather than bounded
  from its children's, because the nested bound doubles at every level and threw
  deep chains thousands of units into the void. The bake verifies that no two
  stars overlap at their drawn radii and fails rather than writing a bad map.
  `Settings.game_filter` never moves a star — the atlas is the whole catalog.

Highlights from the most recent Godot sessions (newest first). The
spreadsheet-driven content below regenerates via the `tools/` importers, so
re-run them after pulling and review the diff.

- **Choose where you start, save the run, and bash that refills the slot** — a run
  now opens on a **choose-your-start panel**: three games, each a **different game
  type**, each **5–7 games from the randomly chosen amulet** (`RunGraph` retries
  the amulet until three genres can all fill that band rather than quietly
  offering a shorter route). The start is where you *begin* — no enemy spawns and
  no shields are granted — and its neighbours become the first offering.
  **Saving works end to end**: the overworld's **💾 Save** button names a run, the
  run keeps an **autosave** that is rewritten every time it moves and cleared the
  moment it ends, and the menu's **Continue** list resumes either. A save now
  carries all three halves of a run — GameState, `GameLoop2`'s enemy stack and
  destroyed games, and the overworld's own screen (the cards on the table, the
  game in play, the loot tray) — so a resumed run picks up exactly where it
  stopped. **Bash** still destroys a game for the rest of the run, and now
  **refills the slot it vacated** with another game *connected to where you are
  standing*, rolling a fresh goal-enemy for the replacement while every untouched
  card keeps the enemy it was already showing (bashing or transmuting one card
  used to silently re-roll the others). With nothing left to connect to, the slot
  goes with the game; bashing the **amulet game** or the **last card on the table**
  is refused, since both end the run rather than shape it. Also fixed: the
  overworld's registration as the mounted map was wiped by the run reset that
  immediately follows it, which had left scrolls unreadable and overworld actives
  (Ride the Bus) unusable for the whole run.

- **Shields are the tries: an attempt tracker, and a two-column playing screen** —
  Block is gone and **Shields** take its place as the *runs you get at a
  game*. Selecting a game grants **3** (or **5** for a Traditional roguelike);
  every run of it you lose is one tick of the new **attempt tracker**, which spends
  a shield, and once they're gone a lost run costs **1 Health** (0 Health ends the
  run there). Whatever is left when you report the game absorbs the followers' hits
  and then **expires with the game** — shields never bank forward. **Anchor** moved
  to a new **`game_selected`** trigger so its +1 Shield is a genuine extra try
  before you play, not a reward afterwards. While a game is in play the screen is
  **two columns**: on the left what you drive — the game, Play / Rate, the attempt
  strip, a tightened one-line-per-row checklist and Completed Game — and on the
  right what you read, the **battlefield with the pack (inventory + loot) under
  it**. Both halves fit one screen, where stacking them didn't. The stage keeps
  that shape **between games too** — the board is never hidden, and the checklist
  becomes a **standing-goals list** ("What you need to do": the character's
  level-up challenge and every follower's outstanding goal, tinted red once it's
  in the front column), so what you owe is answerable *before* you commit to a
  game rather than only after. The board draws the pool as
  **pips on the hero** and a tick pops one with a floating `-1 ◆` — or flashes the
  hero red for `-1 ♥` once the shields are gone. Each offered card shows the tries
  it grants, and since the pool is empty between games, hovering a card previews
  that grant in the HUD's Shields slot (`Shields +5`) instead of a flat 0.

- **Rating on a button, a bonus for rematches, revisits that redraw, and pickups
  that show their effects** — the tier-list prompt no longer pops itself up after
  a game; it opens from a **★ Rate** button (on the report panel, and on the
  select screen for the game you last reported), and the modal now actually
  covers the screen instead of leaving the board live behind it. Beating a game
  you have **already beaten this run** grants **+1 Dash**, called out as
  "⚡ Gain +1 Dash" above that game's cover in the offering (and on its hover
  preview), so doubling back is a real routing option; the clear is recorded on
  the run (`GameState.beaten_games`) and on the lifetime per-game tally the
  Collection and tier list read (`GameStats`). **Arriving** at a game salts the
  offering draw, so coming back to a node hands you a *different* subset of its
  neighbours rather than replaying the same three cards. Picking anything up now
  reports itself immediately: the HUD repaints off the state signals (Health /
  Max Health / verb counts no longer wait for the next game to resolve) and
  `GameState.add_item` diffs the run resources across the pickup to post a
  "Lunch: +2 Max Health, +2 Health" line — the toast strip is mounted on the
  overworld again, so those lines are visible at all.

- **Random Sized Chest + roster/content refresh** — the Vampire Survivors
  characters' level-up reward is a **Random Sized Chest**: the roll picks the
  chest's SIZE (Small 1 / Medium 2 / Large 3 / Huge 5 items) on the same
  75/20/5-with-a-10%-bump ladder as every other rarity draw
  (`Data.CHEST_SIZE_CHOICES`), rather than the rarity of what's inside. Ported
  **Poe Ratcho** and **Antonio Belpaese** plus new games, goal-enemies, and
  bosses from the sheet.

- **Inventory and loot beside the board; covers at box-art scale; the overworld
  split into three files** — the player's pack (inventory + a loot tray) stands
  in a column to the RIGHT of the battlefield grid, so a drop waits there to be
  claimed or skipped instead of standing on a cell. Cover art is drawn at its
  real 3:4 shape and ~1.5x bigger on the choice cards (210x280), in the
  Collection, in the rate-game modal, and on the report panel, which shows the
  game you went to play next to the enemy you went to beat. `Overworld2.gd` shed
  ~1000 lines to `BattlefieldView.gd` (the board, its animation, the Push/Bomb
  toolbar) and `EnemyInfoCard.gd` (the inspect card); the duplicated rarity rolls
  collapsed into `Data.roll_rarity_step` / `roll_item_rarity` and the
  crisp-texture helpers into `UITheme`.

- **Art reorganised into `images2.0/`** — every asset the games-first build uses
  moved to `images2.0/{games,items,enemies,bosses,characters,scrolls}/`, resolved
  from each sheet's `File` column. `images/` keeps only the pre-2.0 art that
  surviving `data/` resources still load.

- **Enemy footprints and multi-cell positioning** — an enemy occupies its whole
  `Size` footprint (`1x2`, `2x1`, `2x2`, or a shaped box like `2x3 L 90 CC`), and
  a placement is legal only when every solid cell is free. That single rule gives
  the board its behaviour: a wide body enters closer to the player and strikes
  sooner, a big body is a wall that stalls the queue behind it, an L leaves
  exactly the gap its notch describes, and **Push** needs the entire footprint to
  fit one column back. Art draws across the full bounding box and hit-testing
  follows the mask, not the box.

- **The MMBN-style grid battlefield with inline drops** — followers are drawn on
  a grid (columns = distance, rows = lanes) with the player on the left, 4x4 at
  the run's opening tier and a column and a row wider on each step past it.
  Enemies enter at the back, close one column per TURN (see the amulet-pressure
  entry above), and strike once any of their cells touch the front column; an
  overflow queue waits off-grid and slides on as space frees. Every defeated enemy's drop appears as loot to claim
  or skip instead of opening a reward screen.

- **Push + the Manager, and Deckbuilder promoted to a first-class game type** —
  **Push** (spend a charge to shove a follower one column back, delaying its next
  attack) arrived with the **Manager** character from Raccoin. The game types are
  now **Action / Deckbuilder / Traditional / Strategy** — `deckbuilder` and
  `traditional` were tags on Strategy and are authored on `GameData.type`
  directly, so each type draws its own goal-enemy pool.

- **Games-first item rewards and active item effects (§8)** — `items2.0` behaviour
  classes are wired end to end: `Pickup` (one-shot `item_acquired` effects),
  `Triggered` (the dominant `game_beaten` hook — Anchor, Burning Blood, Meat on
  the Bone), `Charged, N` (D6, Wand of Wishing), `Usable` (Ride the Bus), and
  `Passive` (Vajra's +1 Bash). Chests bank through `GameState.grant_chest` and
  redeem into `RewardScreen`s when the board is idle.

- **The games-first cut (§11)** — the simulated combat modes are gone: the
  deckbuilder / action / strategy scenes and scripts, combat cards and statuses,
  potions, spells, dice, and the combat enemy stat blocks were all removed (they
  live on in git history). What replaced them is `GameLoop2` — the goal-enemy stack,
  the games-beaten clock, the difficulty tiers and their boss rounds — plus
  `ScrollSystem` (identify-by-reading scrolls), the tiny Health / Max Health /
  Shield model, and the bash / dash / transmute / scramble / push verb layer.
  **The real video game you go and play is the combat.**
