# Changelog

Newest first. This is the running narrative of what changed in the build and
why — it was the README's `## Recent changes` section until it grew to two
thirds of the README, at which point everyone reading the README to learn how
the project *works* was paying for it.

For how the project is laid out and how its systems fit together, see
[`README.md`](README.md); for the canonical spec of the current build, see
[`docs/games-first-redesign.md`](docs/games-first-redesign.md).

---

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
