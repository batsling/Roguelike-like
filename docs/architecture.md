# Architecture

How the Godot project is put together: the autoload singletons, every screen and
what it is for, the window, how content is loaded, Luck, and the conventions the
code follows. For what the game *is*, read [`rules.md`](rules.md); for why each
rule is the way it is, [`games-first-redesign.md`](games-first-redesign.md)
(the canonical spec — `§N` below refers to it). This page was the bulk of the
README until the README was split on 20 Oct 2026.

**Find your way into a big script with `tools/outline.py` before reading it.**
`GameLoop2.gd` and `Overworld2.gd` are each ~8k lines, about 45% comments, cut
into `# --- section ---` blocks; the outline lists each block's line range.

## Autoload singletons

Globals are registered in `project.godot` under `[autoload]` and live in
`scripts/autoload/`. They are always loaded and survive scene changes. There are
29; count them with `sed -n '/^\[autoload\]/,/^\[/p' project.godot | grep -c '="\*res://'`
rather than trusting a number in prose. (`RunDifficulty` and `BodyFacts` live in
the same folder but are static helpers, not autoloads.)

| Autoload | Responsibility |
|---|---|
| `GameState` | Canonical run-persistent state (inventory, HP, charges, position). Resets on new run. |
| `Data` | Loads every `.tres` under `res://data/…` at startup, exposes lookups by id, and owns the shared rarity ladder. |
| `EffectSystem` | Central dispatch for structured effects (`{type, value, target}`) applied via `EffectSystem.apply()`. |
| `TriggerBus` | Global signal hub wiring item/event triggers to game moments (`game_beaten`, `chest_granted`, …). |
| `Stats` | Stat dispatcher; loads `StatDefinition`s and answers stat queries, and rolls every random decision through Luck (below). `docs/archive/stat-dispatcher.md` is the combat-era design it began as. |
| `EventSystem` | Events (`docs/event-sheet-authoring.md`): dealing an event from the per-rarity shuffle bag when a game is played, the Requirement/`needs` gates, and resolving a choice into effects, an event goal, a curse, or a `chance` roll. Objects go through the same resolution. |
| `ObjectSystem` | Objects (`docs/object-sheet-authoring.md`): the machines standing in front of the player, spawning them by tag, and their state — jams, what has been blown off the run, and the Donation Machine's cross-run bank. |
| `GameLoop2` | The run loop: the spawn-event clock the difficulty reads (§19.6), the enemy stack, and the grid the followers advance across. Every game stands **two** bodies on the board and the Amulet its boss (§19.10; the node KINDS of §19.1 are retired), and the end of every game stands more up at the back (§19.5). **None of them belongs to the game.** There is no "this game's enemy": what walks on is a follower like every other body from the moment it lands — bombable, pushable, one ordinary row in the report checklist — and `arrivals` is only the record of which bodies came with the game in play, kept so a Scramble can supersede them. `Overworld2` is a view over it. It also owns the OPS every **ability** is built out of (§7.6): the catalogue in `data/abilities2.0` authors `trigger: op args` in its `Effect` column and this file dispatches on that rather than on the ability's id, so an ability composed of ops that already exist is a sheet row and nothing else. `ABILITY_OPS` is the list that exists, and the generator refuses to write a row naming anything outside it. The pure half of that — the queries over a body Dictionary (`entry_goal`, `entry_image`, `entry_phase`, `ability_lines`, `entry_tags`, the `entry_ability_*` family) — is **`BodyFacts.gd`**, a file of `static` functions that touch no run state at all; `GameLoop2` forwards each one, so `GameLoop2.entry_goal(entry)` still reads the same everywhere. See `docs/performance-backlog.md` §1b for why the ability behaviour did not come with it — `BodyFacts` gained the pure half of the op layer (`ops_at`, `has_op`, `op_row`, `resolve_op_args`) for the same reason, while the ops themselves run on the loop. |
| `ShopSystem` | Shops (`docs/games-first-redesign.md` §14, §19.10): the **shop bar** (`add_kill` on every defeat; full at `bar_target()`, 4 and a kill more per shop opened) and a shop **opened by the player** off it at any game without one (`open_at`; the hub games and the Shop node kind before it are retired). Each shop's three-item shelf, keyed by **node** id so a transmuted node keeps it, its keeper, prices, buying, and the Scramble reroll. State lives on `GameState` (`shops`, `shop_bar`), the same split `EventSystem` uses. |
| `RunTimer` | The **speedrun clock** (see "The speedrun clock" in [`streaming.md`](streaming.md)). Starts on the game the run stands on (`TriggerBus.game_selected`), banks a split per lost attempt, stops when the game is reported — beaten, missed or escaped — and keeps a running total for the whole run. Time is accumulated in `_process` rather than measured between timestamps, so a run left open overnight comes back where it was. Rides the save (`SaveSystem` `timer`), drawn as a one-row split strip in the Now Playing panel (with the full LiveSplit list behind `⏱`) and by the overlay. **It can be PAUSED** (`set_paused` / `toggle_pause`) — the clock counts real time for as long as the app is open, so answering the door should not cost the run twelve minutes; nothing else about the run pauses, and the pause rides the save. |
| `TitleUnlocks` | The main menu's **earned title letters**: a rank pays a radio song or a letter cut from a logo, 50/50 (`RankRewards`), and this draws the letters — a game's from its own logo, a character's from any — keeps them per profile (`title_letters.json`) and toasts each one. Rogue's own font is everyone's from the start (`TitleLetters.available()`, `docs/content-authoring.md` "Title letters"). |
| `Radio` | **Roguelike Radio** (`docs/roguelike-radio.md`): the player's own music, unlocked by playing the real games. Songs are rows of the `radio` sheet (`data/songs/`, `SongData`); the audio is the player's and sits in a folder they pick (by default `C:\Users\Owner\Documents\Roguelike Roguelike\radio` on Windows, `user://radio/` elsewhere), never in the repo. Each song belongs to a game, and the game EARNS songs: one per RANK (`GameRanks`, docs/games-first-redesign.md §20; wins and distinct goals fill a game's XP bar). Each one earned is drawn at random from that game's songs still locked, and the draws are kept per profile (`radio.json`); nothing is unlocked by hand. It keeps the clock itself (a position is `offset + (now - since)`) because the OBS page cannot talk back, and plays out of ONE speaker — `radio.html` in OBS, or the game window — chosen in its own screen (`RadioScreen`, the 📻 on the run header and the main menu). |
| `ObsCompanion` | The **stream overlay** (`docs/games-first-redesign.md` §9). Mirrors the run to `user://obs/` for an OBS **Browser Source** — no server, no port: the state is written as `state.js` (`window.OBS_STATE = {…}`), because a `file://` page may *load* a sibling as a script where it may not `fetch()` one. Registered **last** among the autoloads and a pure reader of the rest. Writes are debounced to 4/sec and deduped on content, over a 5-second heartbeat that lets the page tell "the run has not moved" from "the game is not running". The page itself lives in `obs/` and is reinstalled at every boot; `user://obs/custom.css` is the seam left alone for the streamer. See [`streaming.md`](streaming.md). |
| `ScrollSystem` | Scroll identification + reading (the unidentified-loot gamble). |
| `PillSystem` | Pills (`docs/games-first-redesign.md` §4.3): the per-run deal of 10 of the 13 capsule colours (three mean nothing, so the tenth pill can't be deduced), the 5% horse-dose roll on a drop, colour-scoped identification — either dose teaches both — and the ops a dose runs. Bad Trip names itself from your Health: at or below its own damage it heals to full and reads "Full Health" while that is true. |
| `PotionSystem` | Potions (`docs/potions-design.md`): the per-run deal of 15 of the 37 vials (22 mean nothing, which is what stops the fifteenth being deducible — and the deal is by COLOUR NAME, since Golden and Magenta each ship twice and an unknown bottle introduces itself by its colour), type-scoped identification that covers BOTH verbs at once, the art fallback for the six potions with no bottle of their own, and the two verbs themselves: `quaff_potion` applies the sheet's `On Player` side to the drinker, `throw_potion` takes an aimed cell in `ctx.target` and applies the `On Tile` side around it. The shapes an `area=` token names are the BOARD's (`GameLoop2.area_cells`); Sacred Bark widens one by a rung of `AREA_LADDER` rather than by a multiplier, because a grid has no way to be exactly twice as big. |
| `CardSystem` | Cards (`docs/cards-design.md`): the fourth loot consumable and the one that is **not a gamble** — no identification, no Preference, one use, what it does printed on it. What a card withholds is *which* card it is, and only while it is lying on a battlefield square: the floor draws its DECK'S icon (six icons over fourteen cards) and the hover names the deck and stops, and it turns over for good when it is picked up. That side is `LootSystem.art_texture(entry, face_up)`, false at three call sites and true everywhere else — "face down" is a fact about where the card is, not about the card. Owns the roster's ops too: the three teleports and the ? Card copy resolve as REQUESTS the overworld fulfils, and Temperance's `spawn_object` puts a named machine under the board through `ObjectSystem`. |
| `WandSystem` | Wands (`docs/wands-design.md`): the fifth loot consumable and the only one **not spent in a single use**. Every row authors 1-4 charges; zapping one spends a charge and leaves the wand in its slot, and only the last charge takes the wand with it. The per-run deal is 12 of 28 materials (16 mean nothing, which is what keeps the twelfth wand undeducible), and one zap identifies the type and **every charge behind it**. Eight of the twelve aim at a **Unit** — an enemy, a boss, or one of the player's own bodies (§17) — through the six verbs in `GameLoop2`'s wand-verbs block (`kill_instance`, `cancel_abilities`, `grant_ability`, `split_unit`, `polymorph_instance`, `teleport_unit`), all resolved by one `WandSystem._zap_unit`. A boss is a Unit like any other here, held in place by the one rule that keeps it a boss: **only its goal takes its last point of Health**, and Wand of Death is the single authored exception. The `Aim` column is what it wants pointed at it, in the weapons' words (`docs/loot-passives.md` §12.2) — `ray` is a line from you through the square in `ctx.target` that does its effect to every enemy it strikes, bouncing `bounce` times (`RayAim`), `none` fires where it stands, and `random` lands on a random enemy. An UNIDENTIFIED wand always asks for a square whatever its Aim, and draws no ray preview, or the aiming step would leak which half of the roster it is in — and for the same reason it does **not say how many charges it has**: the count is the rarity ladder read a second way (one on each Legendary, three or four on the Commons), so `LootSystem.charges_known` gates every surface that draws it while `LootSystem.charges` stays the unconditional mechanical answer. |
| `LootSystem` | The one place a piece of carried loot is SPENT. Each kind owns its own resolution; what they share is everything around a use — consuming the entry, **Echo Chamber**'s copies of the last three used, and the memory they read (`GameState.loot_used_memory`). It belongs to neither system because an echo of a pill can be a scroll. Isaac's ordering: the copies fire off the memory as it stood *before* this use, so nothing echoes itself and no echo is remembered. **A wand zap is copied like any other use** — the charge is spent once, by `use_loot`, and a copy only re-runs the zap (docs/loot-passives.md §9). **A passive piece is never spent at all** — a trinket, or a card whose line opens "Passive:" — and `use_loot` refuses one. What those pieces do from their slot is `LootPassives` (`scripts/runtime/`, docs/loot-passives.md): it hands each working piece to the relic runner as a relic-shaped source, resolves Blueprint's "the slot to its right" through the pack's arrangement (a Blueprint beside a piece you USE is used as that piece and spent, §2), and is why moving a piece can change what the pack does. |
| `GameLog` | Verbose run-scope message log (games taken, enemies that walked on, events, items, loot, shop purchases, lost runs) — the written record behind the toasts. Each line is stamped with the game the run was standing on when it was written, which is what lets **`RunLogScreen`** (the header's `🕮 History` button) group a run into its stops. |
| `Notifications` | Curated player-facing "important events" channel; the overworld mounts `NotificationToasts` to show them. A notice can carry a picture and a source key: every relic or pack passive that fires posts one with its art, and repeats from one source stack into one toast (`×N`) — docs/loot-passives.md §5. |
| `SaveSystem` | Save/load for a games-first run (`user://`): a named save per run plus the run's own autosave slot. Writes GameState, `GameLoop2`, and the overworld's on-screen state, and hands a loaded run back to the next `Overworld2` to boot. Written **beside and renamed over**, never straight onto the live file: `FileAccess.WRITE` truncates before the first byte lands, and the autosave is rewritten every time the run's position changes, so the old shape opened that window dozens of times a run on the one file the player never chose to keep. The payload is built first, written to `<path>.tmp`, and moved into place — the save on disk is wholly the old run or wholly the new one. |
| `Profiles` | **Save profiles** — separate players on one install. Owns the profile list (`user://profiles.cfg`) and the active one's directory (`user://profiles/<id>/`), which is where runs, stats, the tier list, ownership and the run-shaping prefs all live; every store asks `Profiles.path()` rather than naming a `user://` path itself. `switch_to()` flushes the profile being left and reloads all of them, then emits `profile_switched`. Window mode / size / dev mode stay **global** in `user://settings.cfg` — they describe the machine, not the player. An install that predates profiles is migrated into its first profile on boot. |
| `Settings` | Preferences, split by the profile line: **global** (window mode, window size, dev mode) in `user://settings.cfg`, **per-profile** (path filter, amulet rule, rifts) in the profile's own `prefs.cfg`. |
| `Ownership` | Which real games the player owns, and where that answer comes from: the catalog's shipped `GameData.owned` column, or **the player's own list**, built by ticking the mark at the top-left of a game's cover in the Collection. `Ownership.is_owned(game)` is the single read; every owned filter, the atlas's owned rings and the settings counts go through it, and the `.tres` column is never written to. Per-profile, in the active profile's `ownership.cfg`. There is deliberately **no Steam sync** — see the note at the top of `Ownership.gd` for what was tried and why it cannot work. |
| `GameTags` | The tags the player has added to or taken off a game **in game**, laid over the baked `GameData.tags` (`tags_of(game)` = the sheet's tags − removed + added) and the one place anything asks for a game's tags — `EventSystem.games_with_tag` routes on it, so an edit counts at once. Edited through `TagEditor` (`scripts/ui/TagEditor.gd`) on the Collection's game page and the run map's game card. Per-profile, in `tags.cfg`. **The sheet is never written from the game**: Settings → Game tags → *Export tags for all games* writes every game's tags, with what was added or removed in game, to `tools/tag_edits.json` (or the user folder, from an exported build), `tools/apply_tag_edits.py` writes that into the `games` sheet and re-imports, and on the next load every edit the baked data has caught up with drops out of the pending list by itself. |
| `RunConfig` | A **custom run**'s setup, held for the run it configures: three independent filters (**map** / **start** / **amulet**, each with library, genre, record and release-year axes), the run-length band, an optional named target game, and an optional **seed** (0 = roll one; `seed_for_run()` is what `GameState.reset_run` asks for the number the whole run is dealt from). Off by default, in which case `RunGraph` reads `Settings.game_filter` exactly as before. Written by `CustomRunScreen`, read by `RunGraph`, and saved with the run — the filters *are* the map, so a save resumed without them comes back on a different one. `RunConfig.describe()` is what the menu's Continue list prints on a custom run's row, read off that save's own stored block rather than off the loaded run. |
| `TierList` | Cross-run tier list / ranking store that outlives any single run. **Its colours live in `UITheme.TIER_COLORS`**, not on the tier screen, because every large cover in the game wears the player's tier in its top-right corner now (`UITheme.attach_tier_badge` — the collection, the game-choice modal, the offering cards, the route ladder, the atlas, the Now Playing panel, the run-over and run-history screens). A badge in a different red from the row the game sits in would be two answers to one question, so there is one list and both read it. The badge is a pill carrying the tier's own name in full — names are editable, so a renamed tier is drawn as the player wrote it — **centred on the art's top-right corner** rather than tucked inside it, so it reads as a mark pinned to the picture and gives back the corner it would otherwise cover. An unranked game draws nothing at all. Anything that draws a cover inside a clipping parent (the collection's rounded plate) hands the badge an unclipped layer of its own, or the overhang comes back cut into quarters. |
| `GameStats` | Cross-run lifetime stats, per game and per character: wins, Amulet wins, perfected visits, goals and level-ups — what `GameRanks` derives every rank from (§20), what the Collection's pages list — plus the Donation Machine's bank, the one number in the build that deliberately outlives a run. |
| `DevTools` | Developer panel (press `` ` ``), gated on `Settings.dev_mode`. Five tabs: **Grant** (items / scrolls / pills / statuses, with a player-or-enemy target picker — the item list is `DevTools.item_pool()`, the **2.0 set only**: it used to append the 112 combat-era relics (since deleted), which grant cleanly and then do nothing because no games-first code honours them), **Run** (vitals, every board verb, gold, chests, level, games played), **Board** (spawn a goal-enemy or boss; stun / push / bomb / defeat / remove or status any standing body), **Flow** (jump to a game, heal, clear the board, force the win or loss), **Events** (start any authored event where you stand and read the state of the shuffle bag, each row saying why it is or isn't turning up on its own — see [Authoring an event](content-authoring.md#authoring-an-event); the same tab spawns any **object** under the board, which is the only way to reach the non-event half of how a machine appears). Everything routes through the same public API the game uses. |

## Screens & flow

There are only two scenes. `MainMenu.tscn` boots the game and hands off to
`Overworld2.tscn`, which **is** the game — the simulated combat modes were cut in
the games-first redesign (§11), so the real video game you go and play is the
combat. Every screen past the menu is built in code, so `Overworld2.tscn` holds
nothing but a root node and its script. `MainMenu.tscn` is the exception and
always was: it lays out its title, buttons and save list in the editor like an
ordinary scene.

- **`MainMenu.gd`** — new run, character select, the **Continue** list of saved
  runs, the Collection, the tier list, Settings, and **Exit Game**. Quitting from
  here doesn't confirm: nothing is live on the menu and the saves are already on
  disk, so a prompt between the player and the door only ever gets in the way.
  **Exit Game is a MAIN MENU button and only works on the main menu.** It is
  moved to the bottom-right corner in code (`_move_quit_to_corner`), and that
  used to append it *last* — above `%ModalLayer`, where every screen the menu
  raises mounts — so the door out of the application sat on top of the character
  picker, the Collection and the Atlas, live and clickable through their own
  backdrops. The corner is mounted under the modal layer now.
  - **`CharacterPicker.gd`** — the roster in `data/characters2.0`, and the one
    screen between **Start Run** and being in a run: a four-wide grid of icon
    tiles on the left, the selected hero's full portrait beside its facts on the
    right, Confirm along the bottom. The detail half **never scrolls** — the
    facts stack to the *right* of the portrait rather than under it, which is
    what buys the room to fit a hero on one screen. It only reports which hero
    was picked (`chosen`); what that *means* — cancelling a pending resume,
    parking the choice, swapping scene — stays in `MainMenu._begin_run`. It was
    built inline in `MainMenu.gd` until it was 47% of that file, and it mounts on
    `%ModalLayer` rather than a `CanvasLayer` of its own so the Exit Game corner
    stays underneath it.
  - **`Collection.gd`** — the compendium: Games, Items, Characters, Enemies,
    Bosses, **Loot**, Events, Objects, Shopkeepers (each keeper's sheet columns put
    into words by `Collection.shopkeeper_rules`). The tabs share the title's row,
    compact (`_compact`), and so do the Loot sub-tabs. **An entry opens in a popup over the
    grid** (`_new_detail_panel` / `_select`), not a pane beside it: the grid
    never gives up a column, the picked cell stays lit underneath, and ◀ ▶ (or the
    arrow keys) step through the grid in layout order. Escape or a click on the
    backdrop closes it. Before that it was a right-hand pane, and before THAT one
    mounted open and empty — both cost the grid columns while you scan 1,000 covers.
    One property on one node covers every tab, because all eight are built by
    `_grid_and_detail`. `TierListScreen` does the same thing for the same reason.
    **A grid tile is a picture with a caption, not a stat line with a thumbnail.**
    The art takes most of the width its cell reserves, and the caption under it is
    the name plus at most one line of whatever the tab is sorted by — type and tier
    on an enemy, the rarity on an item, an event or an object, nothing at all on a
    character. Damage, footprints, health, choice counts and tag lists were all on
    the tiles once, and between them they could stack four lines of text under a
    58px picture. Every one of them is still in the detail panel, where the
    footprint is a drawn board rather than "▦ 2 x 2" — which is the reading worth
    having anyway.
    It is also **the only door onto the Atlas
    that is always open** — the Games tab's *✦ Show constellation* draws the same
    catalog as the star chart, which is why the main menu no longer carries an
    Atlas button of its own (Run History still lays its routes over the sky).
    Enemies and Bosses sort by A-Z, Tier, Damage and **Ability** — an ability is
    the one thing about a body that isn't a number, and it is what the roster is
    browsed for. **Loot is one tab with nine sub-tabs** —
    Scrolls, Pills, Potions, Cards, Wands, Trinkets, Bags, Weapons and Evolutions
    — because they are one thing to the run: one payout, one pack, one window, and
    nine top-level tabs would say the opposite. The sub-tab buttons sit in a row
    that WRAPS, since nine do not fit across the 1280 canvas. The tab's own count
    (`Collection.loot_total`) is every piece the sub-tabs list; evolutions are
    recipes whose results are weapons already counted, so they are not in it.
    **Every sub-tab is a grid of pictures that opens a popup**, the Items tab's
    shape (`_loot_cell` / `_show_loot_detail`): art, name and one caption in the
    grid, everything the piece says in the popup. **A piece with no art of its
    own loops through the run's disguises at random** (`_loot_art`, a Timer per
    cell, its own RNG so a mid-run visit cannot move the run's dice): every pill
    the capsules of `PillSystem.COLORS`, every wand the sticks of
    `WandSystem.MATERIALS`, an artless potion the vials of `PotionSystem.COLORS`.
    It shows what the piece looks like in a run — any of these — without pinning
    it to one colour, which would teach an association the game deals at random.
    A potion with identified art keeps it (that is a fact about the potion, not a
    per-run secret); a scroll without art wears the one shared Unidentified sheet.
    A card's popup shows **both sides**, face and deck icon, because the
    difference is the whole of what the kind withholds. A pill's popup shows
    **both doses**, since the 5% horse roll is the same colour and the same
    identification.
  - **`HowToPlayScreen.gd`** — **📖 How to Play**, the written manual: a chapter
    list down the left, one chapter down the right. Every word of it is data in
    **`HowToPlayText.gd`**, which the screen draws and does not read — so the
    text, which changes every time the build does, is edited without touching
    layout code. The manual's **numbers are interpolated from the constants that
    govern them** (`GameLoop2.SHIELDS_PER_GAME`, `RunDifficulty.FAR_HOPS`,
    `ShopSystem.BASE_PRICE`, `ShopSystem.STOCK_SLOTS` …), and `test_how_to_play.gd`
    asserts the prose still quotes them, so a balance change cannot leave the
    manual lying. The menu's **bottom-left corner is its table of contents** —
    built from the same array, opening chapters **by id** rather than by index.
  - **`CustomRunScreen.gd`** — **⚙ Custom Run**: build a run out of a chosen set of
    games. Three columns, because there are three independent questions — what
    **the map** is made of, which of those may be **the start**, and which may be
    **the amulet** — each with the same four axes (library, genre, record, release
    years) and a live count of the games that survive it. Under them, the run
    length (how many games from start to Amulet), an optional **seed**, and an
    optional **named target**, which composes with the band rather than overriding
    it. Begin hands the configuration to `RunConfig` and then opens the ordinary
    character picker, so a custom run is the normal flow with a screen in front of
    it.
    The **seed** is the run written down: type a number and the same run comes
    back — the same Amulet, the same opening three with the same bodies on them,
    the same drops, level-up rolls and capsule alphabet. Left blank the run rolls
    its own, which is what every run did before the box existed. It is a text
    field rather than a spinner because a seed is something you paste in off
    someone else's screenshot, and it is capped at 18 digits so what is on screen
    is always the seed you get. See `GameState.reset_run` for what one number
    reaches: it fixes Godot's global random stream, the overworld's own generator,
    and the three systems that keep a private one.
- **`Overworld2.gd`** — the run itself: the offering of games
  (cover cards), and
  then a two-column stage — checklist on the left (the standing goals while you're
  choosing, the honour-system report step + attempt tracker while you're playing;
  most boxes on it are a **confirm** that resolves the row on the spot, mid-game,
  and lock — see spec §2.1. The exception is the **`When beating a game:`**
  section: the player's standing status goals, the character's level-up and the
  goals authored `Ticked: game beaten` (spec §7.7) nest under one header there,
  and wear a ROUND box rather than a square one, and they ARM rather than resolve — the box goes on and off freely, there is no
  confirm, and handing the game in is what cashes it, because what they ask about
  is the game being beaten rather than the hour just spent. Their safeguard is on
  the **`✓ Completed Game`** confirm instead, which carries those rows again with
  the ticks as they stand and a **notes** field beside each: it is the moment
  that is final for them, and the only place their note can be asked for),
  the battlefield on the right with the player's pack (items **and** scrolls,
  one strip of tokens) above it. **The two halves point at each other**: hovering
  a goal row lights the body it belongs to on the board, and hovering a body
  lights its row — they are the same fact written twice, and nothing else answers
  "which of these lines is that thing" without reading names. Hosts the toast strip, so an item's effects
  announce themselves the moment it's picked up.

  **It fits one 1280×720 canvas, in every phase and at every board size**, with
  no horizontal scrollbar ever (the page's axis is `SHOW_NEVER` — still
  scrollable, never drawn) and no vertical one unless a run's checklist genuinely
  outgrows the page. That is the whole screen, not a small window:
  `window/stretch/mode="canvas_items"` scales that fixed canvas up to fill the
  display, so a 2560×1440 monitor draws this same page at 2×. Fitting the box is
  a constraint, not an accident, and the things below are what pay for it.

  **The Amulet is named from the first screen.** It used to be the run's one
  secret until a start had been committed to: the picker quoted the DISTANCE
  (`5 games from the Amulet`) and the maps drew the destination as an unnamed
  `The Amulet — ???` box that opened no card. All of that is gone. The start
  screen is built around it — its art and its name are the banner across the top
  (`StartPicker`), so each road's distance line only counts
  (`5 from the Amulet`, `_start_distance_text`; its popup's tooltip names the
  game), and the ladder a road opens names it on its last rung. (That ladder is the ladder alone — the star chart stays down on the
  start screen; see `RouteLadder.gd`.) Choosing a start is a routing decision, and
  the game the road ends on is half of what makes one road different from
  another.

  **And every card after the first says how far it is.** The distance used to be
  on the start cards and then nowhere: from the second choice on, a card said
  which *way* it went — the route badge, and only inside the popup it opened —
  but never how far there was left to go, which is the number the run is counting
  down. Each offered card now carries `N games away from the Amulet` in its own
  row, under the 🏆/🛒 flag and over the art, from
  `Overworld2.amulet_distance_text`; it says "the Amulet" rather than naming the
  game (the card is 150px wide, and the tooltip names it) and is blank on the
  Amulet's own card, where the flag a line above has already said it. The row is
  **paid for by merging the 🏆/🛒 flag and the ⚡ `+1 DASH` badge onto one line** —
  two stacked rows both blank on most cards — because the page's worst case (a
  shop under the board) has about two spare pixels and a third row does not
  fit in them. The **hover
  line under the cards** names what is *waiting* there and not the game itself —
  the mouse is on that cover with its title printed under it, the line is one line
  wide, and the goal is the half that was getting truncated to pay for the repeat.

  **The header is the road you have walked, and it never leaves the screen.**
  Across the top, between the health and gold chips and the `☰ Menu`: the games
  played as small covers with arrows between them — the same picture the
  end-of-run screen draws, live, for the whole run. It is the only view of the run
  as a *journey*; the checklist says what you owe, the board says what is chasing
  you, and neither said where you have been. The title moved to the right to make
  room, which is also the honest ranking of the two. Covers are small and unnamed
  (the name is on the hover) because the strip shares its row with everything else
  and the page still has to fit 720; past `STRIP_MAX_STOPS` the oldest stops are
  dropped behind an ellipsis.

  Two rules about what is on it. It is **games played only** — it does not close
  on the Amulet, because the road ahead has two screens of its own (the 🗺 map and
  the route ladder) and a cover for a game you have never been to, drawn beside
  the ones you have, reads as the next stop. And it **keeps the repeats**: it
  draws `GameState.walked_path()`, the run's walk in order, rather than
  `visited_games`, which is a set and so showed a run that doubled back over a hub
  four times as one stop.

  The whole bar is mounted on a **`CanvasLayer` of its own** (`HEADER_LAYER`, 135)
  rather than being the first row of the scrolling page: it stays put when the
  player scrolls to the bottom of a tall board, and it floats above every modal
  the run raises — the event (123), the game-choice popup (124), the map (130) —
  which is exactly where Health is most worth reading. It sits *below* the
  end-of-run verdict (150), and it stands down while the tier-list board is up,
  since that one is a full screen with its own way out. The page is inset by the
  bar's height (`_fit_page_under_header`), so nothing is hidden underneath it.

  **And so is everything else on the screen.** The bar is opaque, so anything
  centred on the viewport loses its top row to it. `_fit_page_under_header`
  publishes the bar's height as **`ModalScaffold.reserved_top`**, and three
  things read it: `ModalScaffold.centre` centres a modal in the band *below* the
  bar and never lets its top edge start above it; the map window
  (`RunMapModal`) sizes, opens and clamps its drag inside that band; and
  **`AtlasView` offsets its whole page down by it**, so the chart's own header —
  which holds its search box, its ✦ jump buttons and the `←  Back to the run`
  button that is the only way off it — lands under the bar instead of beneath it.
  It is cleared when the page leaves the tree and while the bar is down, so the
  main menu's own screens are unaffected.

  **Where the numbers are.** There is **no HUD strip** — every number is drawn
  once, by whatever owns it:
  - **the player** (Health, Shields, statuses) is on the **board's hero**:
    `♥ hp/max` under the portrait, the shields over it — one **shield sprite**
    each (`images2.0/general/Shield.png`), the ones that stay nearest the
    portrait and bare, the Temporary Shields this game granted after them and
    each wearing the **clock badge** (`Timer.png`) — and status pips between.
    The clock is the run's one mark for "this is going away": every status pip
    drawn from a borrowed stack carries it too, on the board, on the enemy card
    and on the checklist (`UITheme.timed_art`). The **shields that stay** are the
    exception that proves it — they also ride the header's Health chip, as the
    same sprite with no clock on it, because that pool is gained off the board and
    has to be readable with no board on screen.
    A shield **breaks on screen**: during a resolve the row is the playback's
    rather than the run's (`_shields_shown`), and each blow the loop marked
    `blocked` swells and fades one sprite as its damage number lands — the
    Temporary ones first, which is the far end of the row.
  - **the board's verbs** are on the **board's own bars**: its pressure bar ends
    `▦ 4×4 · Low` (that's the tier) and its toolbar buttons read `⇤ Push (1)` /
    `✸ Bomb (3)`.
  - **the choosing verbs** — **Bash / Dash / Transmute / Scramble** — are chips on
    a row under the offering, since all four change what is on the table. **All
    four are buttons.** Dash and Scramble act on the offering as a whole and fire
    on the press; Bash and Transmute need a target, so pressing one *arms* it —
    the offering becomes a row of targets, drawn in the verb's colour, and the
    click on a card is what spends the charge (`Overworld2._armed_verb`). Arming
    is free and cancelling costs nothing; a refused aim (bashing the Amulet) says
    why and stays armed.
  - **the shields a game grants** ride the offering's one-line hover, which also
    carries the enemy's **portrait** — sized by the line rather than setting its
    height, so it costs the page nothing (`OfferingCards.HOVER_ART`).
  - **everything else on the page describes itself on hover**, as a small themed
    card rather than Godot's grey tooltip — see "Hover cards" below.
  - **the pack has no heading.** A bordered strip of relic and scroll tiles is
    its own label, and that row is the page's whole margin against its 720p
    budget (with it, the page was already a pixel over before a shop mounted).
  - Keys and Chests aren't shown at all — Keys are deferred and unauthored, and a
    chest is redeemed the moment it lands.

  **The header carries no title.** It used to end in "Roguelike-like" in 20px
  gold, between the road walked and the buttons — about 180px of the one row in
  the game that never leaves the screen, spent naming the game the player already
  has open. It had been moved out of the left corner once already, to make room
  for Health, with the note that this "is also the honest ranking of the two";
  dropping it is the end of that same argument. The road strip is `EXPAND_FILL`,
  so it takes the width without anything else moving — and it is the thing that
  wanted it, being clipped and ellipsised past `STRIP_MAX_STOPS`.

  **`☰ Menu` is three named groups**, and it was four entries under one
  unlabelled rule. The three reference screens were reachable only from the MAIN
  MENU, so answering "what does this item do", "have I met this enemy" or "how
  does this actually work" meant abandoning the run to go and look. Ordered by
  what the entry does to the run, nearest-first:
  - **Information** — 📖 How to Play, ▣ Collection, 🏆 Tier List. Changes nothing,
    and it is the group opened mid-decision, so it is the one the cursor lands on.
  - **This run** — 💾 Save run, ⟳ New run.
  - **Game** — ⚙ Settings, ← Main menu, ⏻ Exit game. Last, and furthest from the
    cursor, because both doors out are in it.

  Each group heading is a **labelled** `add_separator`, drawn in the accent by
  the theme's new `PopupMenu` entries — which is what turns a list of eight into
  three lists of three. **The popup is on the palette**: `make_theme` dressed
  Button, CheckBox, Panel, Label, LineEdit, OptionButton, the separators and the
  scrollbars and never touched `PopupMenu`, so the menu came up as Godot's stock
  dropdown — a flat slab with a blue selection bar and a grey-on-grey heading — on
  a page of warm brown panels. **And it hangs from its own button**: left to
  itself `MenuButton` drops the popup below and LEFT-aligned, and `☰ Menu` is
  hard against the right edge of the canvas, so the popup overflowed, got clamped
  flush against the edge with no margin, and started ~50px left of the button that
  opened it. `Overworld2._place_menu_popup` right-aligns it to the button and
  clamps it inside the canvas, measured in `about_to_popup` off
  `get_contents_minimum_size` (the popup's `size` is a stale 0 before its first
  layout).
  **Every dropdown in the project is drawn by the same two theme entries.** There
  are thirteen `OptionButton`s across six screens — the Collection's type and
  record filters, the Atlas's mode and region pickers, Custom Run's four filter
  columns, the Dash panel's type filter and Settings' display, window-size and
  audio lists — and each is a bare `OptionButton.new()`, so the theme is the only
  thing deciding how any of them look. `test_design_tokens.gd` fails a screen that
  reaches for its own stylebox or font colour; a font SIZE stays a per-screen
  choice, since the Dash filter sits on the 720p-budgeted page. A chosen row wears
  a solid accent dot (`UITheme.popup_mark`) and an unchosen one wears nothing —
  Godot's stock pair is drawn for a light theme, so the ticked mark was a pale
  ring and the unticked a faint dark square, putting a smudge on every row. Exit is the only entry that asks
  first, since a live run is standing behind it — and it asks the question that
  is actually open, offering **Save & exit** beside Exit and Cancel rather than a
  bare "are you sure".

  **All four reference screens mount on a layer ABOVE the pinned header**
  (`Overworld2._open_full_screen`, at `UITheme.Layer.FULL_SCREEN`). Each replaces
  the run rather than sitting over it, and the bar floats over everything on this
  page — including their own Close button, which is the only way off them. The
  tier board used to answer that by standing the bar *down* for as long as it was
  up; going over it instead is what the Atlas and the end-of-run verdict have
  always done, and it is one less piece of state to get wrong. The layer is freed
  with the screen, so a visit does not leave an empty `CanvasLayer` behind.
  **`🗺 Map` and `→ Optimal Path` are two buttons, two destinations and two
  names**, and until the layout pass they were one word for both. The header's
  `🗺 Map` and the offering heading's `🗺 Map` both called `open_map`, so each
  raised the whole 882-star **Atlas** — and the *ladder*, which is what actually
  answers "where does this road go", arrived as a window on top of it. The chart
  is the **Map** and it is the header's, open from anywhere including mid-game;
  the ladder is the **Optimal Path** (`Overworld2.open_optimal_path`, and the
  per-road buttons on the start screen) and it opens alone. `RunMapModal`'s own
  title says `→ Optimal Path to the Amulet` for the same reason — it is not a map
  of anything, it is one shortest road drawn rung by rung.
  - **`StartPicker.gd`** — **the opening screen of a run**: what the Amulet is,
    and which road you open on. Three starts (`RunGraph.NUM_START_OPTIONS`),
    across genres and where the map allows at different distances, all 4–8 games
    from the Amulet (§19.3.2), each carrying a starting kit for its genre when
    Settings' starting gear is on (§19.3.4) — and the one you take is the run's
    first game, bodies and all. The Amulet gets the top of the screen with its art
    and its name; each road is a card with its cover, its distance
    (`N games from <the Amulet>`), the enemy standing on it and its goal, and two
    buttons — **→ Optimal Path** (the ladder, routed as it would be if you took
    that road) and **⚙ Details** (the ordinary `GameChoiceModal`). Click a road to
    select it, **Begin** to take it, the same preview-then-commit shape as
    `CharacterPicker`.
    It is **raised by `Overworld2` over its own page** (`_open_start_picker`),
    which is hidden underneath it along with the pinned header — the run is still
    rolled by `Overworld2.start_run`, because the reset that decides the seed has
    to happen before the map is drawn from it. The screen reports an index and
    `choose_start` does the rest, so a road taken by a player and one taken by a
    test go through the same door.
    This was `Phase.START_SELECT` drawn into the overworld's left column until the
    layout pass: the right-hand half of that screen was an empty board with an
    unpressable Push/Bomb toolbar on it, and the left half — heading, cards, hover
    line, verb chips, checklist — measured 647–675px of the 630 a 720p window
    leaves, so the first screen of every run opened behind a scrollbar with its
    last line sliced in half. It was also the one phase with **no fit test on it**;
    `test_screens_fit.gd` measures it now, over six re-rolls.
  - **`GameChoiceModal.gd`** — what clicking an offered card opens. A card is the
    cover, the name and the Amulet's flag; everything else about the decision
    lives here. The **optimal path from that game, drawn as the real route map**,
    takes the whole right-hand side from the top of the popup to its buttons, with
    the popup's ✕ over its corner. On the left, under the title: `🛒 Shop` when the
    player opened one there (its shelf in that line's hover), its connections with
    the shops among them, the
    Temporary Shields it grants (with the shield's own art), the pace it puts the
    board on, and **your record there** — one line, `⚔ Beaten N times · M
    enemies ›`, which opens the list of every enemy you have beaten at that game,
    the ones approaching now marked. Under **Enemies approaching**, each body is a
    row in the checklist's own format (portrait, goal — name, ❤/⚔), plus a `?` row
    for each body rolled on arrival. **Rate this game** sits with the buttons that
    answer it: **Travel**. (Bash and Transmute used to stand beside it and are
    armed from the offering's chips instead — this screen is about whether to go
    somewhere, not the place to bury two destructive verbs.) The cover is drawn
    small on purpose: it is the one thing you have already seen (it is what you
    clicked), and the room it gives back goes to the enemy and its goal. It decides
    nothing itself; every answer calls the overworld's `pick` / `bash_choice` /
    `transmute_choice`.
  - **`RouteLadder.gd`** — the shortest-path DAG as a **left-to-right map**: one
    column per step of the road, each column's games spread over the height it is
    given and nudged a little off the grid (by a hash of the game, so the same
    route always looks the same), ordered to cross as few arrows as possible, with
    green arrows between them. Each game is a **box filled with its cover**, its
    name along the bottom on a fade in the box's role colour (blue for you, ember
    for the Amulet, gold for an offer, near-black otherwise), and a 🛒 **shop
    marker as a badge on its top-right corner** where the player opened a shop
    (`shop_marker`); the arrows run from the
    middle of one box's right edge to the middle of the next one's left. Every name on a map shares
    one size. Given a `room`, the map is sized to it on both axes. Shared: the 🗺
    map window (`RunMapModal`) and `GameChoiceModal` draw the same map from it; the
    window spreads to its room when it is on its own, and draws at the map's
    natural size over the star chart, where the sky needs the space.
    Over the star chart the map window has **no Close of its own** — the chart
    owns the screen and its Close takes the window with it — so the button in its
    corner rolls it up to its title bar instead. Opened without a chart under it
    it is the only thing on screen, and there it keeps one — which is what the
    **start screen** gets: its `→ Optimal Path` opens the ladder ALONE, no chart,
    and on `StartPicker.MODAL_LAYER` so it lands above the screen that opened it
    rather than perfectly out of sight beneath it. The question on that screen is
    "which of these roads", the ladder is the answer to it, and 852 stars with
    nothing on them to orient by (the run has no position yet) is not; the chart
    is one `✦ Star chart` button away on the window itself.
    **Every box is named, the Amulet included**: the map used to draw the
    destination as `The Amulet — ???` on a start-picker map, and no longer does
    (see "The Amulet is named from the first screen" above).
  - **`HoverCard.gd` / `HoverPanel.gd` / `HoverBox.gd` / `HoverButton.gd`** — the small themed card
    that appears when the mouse rests on something you could click to read in
    full. Four things open a card when clicked — an **enemy** on the board, a
    **status** on a body, an **item** in the pack, and the **enemy-turns**
    readout on the pressure bar — and all four used to spend their hover on
    `tooltip_text`: grey system chrome with a wall of plain text in it, on a page
    that is otherwise entirely hand-drawn. They carry a *condensed version of the
    card* now: the art, the name in the thing's own colour, its statuses as pips,
    and the one or two lines that actually decide something.
    `HoverCard.attach(node, {...})` stores the model and seeds the plain
    fallback; the node has to be a `HoverPanel` (a PanelContainer) or a
    `HoverBox` (a VBoxContainer) or a `HoverButton`, or define the two-line
    `_make_custom_tooltip` override itself, because Godot only calls that on a
    Control's own script. All three wrappers fall back to `HoverCard.text_card`
    when no card is attached: the plain `tooltip_text` in a small box that wraps
    at `TEXT_WRAP` — Godot's stock tooltip never wraps, so a long one ran across
    the screen. Buttons on the run's screens are `HoverButton`s for that reason. A status's model comes from `StatusData.hover_card`,
    beside the string it replaces, so the board, the enemy card and the hero
    strip cannot describe the same status differently.
    **The offering is the one thing that gets none** — no card and no tooltip:
    the hover line under the cards already says what is waiting, and a popup over
    three covers being scanned is the noisiest possible way to repeat it.
  - **`BattlefieldView.gd`** — the board: the hero on the left with the shield
    pips over them, the grid the goal-enemies close in across, the off-field lane,
    the Push / Bomb toolbar, and the strike / advance animation. **Both verbs are
    armed then aimed**, and neither spends anything until the aiming click.
    Pressing `⇤ Push` arms it, clicking an enemy picks the body, and an arrow
    appears on every side of it a shove could legally land on — back, forward, or
    up/down, which is the only lane change on the board; the arrow is what
    spends. Pressing `✸ Bomb` arms it and the **click on a body is what fires
    it**, since a bomb has no direction to pick. Arming either puts the other
    away. Bomb used to go off on the button press, at whatever was still
    selected — routinely a body clicked several turns earlier to read its card,
    so the charge went into an enemy the player was not looking at.
    **The instruction is the board, not a caption**: arming lights every body the
    verb could land on (`armed_targets` / `ARMED_TINT`) and the toolbar stops
    printing "click an enemy" — a verb that has to caption its own highlight is a
    highlight that isn't working. **The enemy of the game you are
    playing stands on the board with the rest** (§7.2), drawn on a washed fill so
    it is tellable from its neighbours; the off-field lane is for bodies with
    nowhere to stand. Nothing is drawn over the top of a body — the boss skull and
    the "in 2" that used to be there covered the picture that identifies it.
  - **`EnemyInfoCard.gd`** — the click-to-inspect card for one enemy.
  - **`ShopModal2.gd`** — a shop (§14.4, §14.6, §19.10) as a pop-up framed like
    an event: the shopkeeper's name, line and portrait, the shelf, and Leave. Opened
    by the header's shop bar (`press_shop_bar`), the `🛒 Shop` button on the
    offering's heading (up for the whole visit) or the haul screen's "Go to Shop";
    loaded by path, like the event modal.
  - **`ShopPanel2.gd`** — the shelf inside it (§14).
    The shelf is drawn as **one row per item** — thumbnail, name, price — with
    the full card and its Buy button opening over the page on click. Three cards
    on the page ran the overworld to 1231px inside a 688px window; the page is a
    fixed 1280x720 canvas that `stretch/mode` scales into any window, so there is
    no monitor big enough to buy that space back. `ObjectPanel2` draws machines
    the same way for the same reason, and the board shrinks to a tighter height
    budget (`BattlefieldView.set_sharing_column`) while either is under it.
  - **`BossNoticeModal.gd`** — the "⚠ BOSS INCOMING" popup (§7.1), opened once per
    boss round. It replaced a banner strip that shoved the whole page down. Its
    boss portraits are **clickable**: each opens the ordinary `EnemyInfoCard` over
    the popup, read-only (no body exists yet, so no Push / Bomb), which is where
    "what does it want and what does it hit for" gets answered.
  - **`PostCombatScreen.gd`** — **the screen a game ends on** (§18). A report used
    to fire six independent surfaces — one relic modal per defeated body, the loot
    payout, the event, the shop appearing under the board, the boss notice, toasts
    under all of it — and the first two of those opened **on top of the resolve
    animation**, which is the one place the run's consequences are ever shown. The
    haul is one screen now, and it opens when the board has stopped moving: the
    verdict, the fight in numbers (out of `beat_game`'s result, which used to be
    thrown away), **every** relic chest down the left and the loot payout down the
    right at once, and the boss warning as a banner. All the
    chests together is the point: a queue hides what the *other* relics are, and
    there is often an order worth taking them in. A chest banked while the screen
    is up lands on it too (`add_chest`) rather than opening a `RewardScreen`
    underneath it. **The payout does not close on its last piece
    and has no Take/Leave buttons**: the piece has just gone into the pack, and the
    pack is the reason to still be looking.
    **★ Rate this game sits beside the cover**, and nowhere else in the run — it
    was on the play panel's checklist, which offered the score while the game was
    still in front of you. It saves and stays put rather than opening the
    tier-list board over a haul nobody has finished taking.
    **The chest shows the sum that sized it** (`chest_terms`): 🏆 +1, then a face
    per body with its own difficulty as its value, `=` the chest. Read off
    `GameLoop2.chest_point_breakdown()`, banked at each kill and claimed before
    the pool is spent — *not* re-derived from the report's defeat list, which
    misses a body a mine killed during a lost run.
    **One button out, and it names where it goes**: "Go to Event" when the node
    owes one (clicking it is what opens the event), "Go to Shop" at a game the
    player opened a shop at, "Travel on" otherwise; the event wins when both are owed. It
    counts what it is about to bin, because a Legendary left on the ground should
    be a decision and not a side effect of pressing Continue. The sections are the
    **real modals, embedded** (`ItemDropModal.embed` / `LootDropModal.embed` /
    `BossNoticeModal.embed`): same cards, same drag, same signals, minus the
    backdrop and the layer. The standalone modals stay, because
    `GameState.offer_loot` fires from `EffectSystem` and a payout that didn't
    arrive with a report has no haul screen to be part of. **The shelf is not
    here** — it was briefly borrowed and handed back, which left four sections
    fighting for a 720p canvas and an exit button pointing at something already on
    screen; the shop is a pop-up of its own (§14.4), and this screen keeps only the
    shop's node id so its button can name it and open it.
- **`RewardScreen.gd`** — chest rewards (level-ups, and the **Wand of Wishing**,
  which is a piece of loot rather than a relic now — `docs/wands-design.md` §5.2).
  **The obtain-any screen is its own layout**: reaching into the whole catalogue is a different decision
  from picking one of three cards, so `setup_obtain` takes the viewport (less a
  margin), shrinks the cards to art-name-and-class chips with the description in
  the hover card, and adds a search over both name and description — around thirty
  items on screen at 720p instead of three, rarest first. The chest a
  report pays doesn't open it either: a beaten game banks 1 point plus each
  defeated body's difficulty (Low 1 … Insane 4, bosses excluded — they bank a
  chest of their own), and `Overworld2._queue_report_chests` spends that on the
  size ladder and hands the chests to the post-combat screen (above). What a body
  drops **on the board** is a piece of LOOT, on the square it fell in
  (`GameLoop2.drops`, drawn wearing its own art by `BattlefieldView._drop_node`);
  whatever is still lying there when the game is reported is swept onto the
  post-combat screen too, win or lose.
- **`FloorLoot.gd` / `DragPackPanel.gd`** — how a piece leaves the floor. The
  token is a drag **handle**, not a button: dragging it mounts the pack to the
  left of the board for the length of the drag (`Overworld2._notification` on
  `NOTIFICATION_DRAG_BEGIN` → `_mount_drag_pack`), and dropping it in a slot, on
  the bin, or on nothing ends both. The grid is the same `LootGrid` every other
  loot surface draws; the one rule it adds is that a floor piece may land on an
  OCCUPIED slot, trading places with what was there — the evicted piece goes back
  onto the square the new one came off, so a full pack is a decision rather than a
  refusal. There is no click: it used to open a `LootDropModal` whose only job was
  to put those nine cells on screen.
- **`RateGameModal.gd`** — the 1-10 tier-list score for a game. Strictly opt-in:
  it only ever opens from a **★ Rate this game** button — on the game-choice
  popup, beside the cover on the end-of-game screen, and on the tier list.
- **`EventModal2.gd`** — an event (`docs/event-sheet-authoring.md`): the prompt,
  the art, the choices with what each costs printed on its button, and a loot
  table when the row `Opens With` one. Opened by the end-of-game screen's "Go to
  Event". (The combat era's D20 `EventModal` is
  deleted.)

### Screens added since this list was written

Each is built in code like the rest; the section of the spec or doc that owns
it says the rest.

| Script | What it is |
|---|---|
| `menu/ProfilePicker.gd` | Choose or make a save profile (`Profiles`) |
| `menu/MenuFallingArt.gd`, `MenuFallingArtLayer.gd` | The main menu's falling enemies, items, loot and covers (CLAUDE.md has the four things to know before touching it) |
| `ui/RunHistoryScreen.gd` | **Run History**: every finished run, its route laid over the star chart |
| `ui/RadioScreen.gd`, `RadioMiniPlayer.gd` | Roguelike Radio's screen and the 📻 player on the run header (`docs/roguelike-radio.md`) |
| `ui/SettingsModal.gd` | Settings, one row per setting in two columns |
| `ui/TagEditor.gd` | Edit a game's tags in game, on the Collection page and the run map's card (`GameTags`) |
| `ui/RankBadge.gd`, `RankFill.gd` | A game's or a character's rank on its cover, and the bar that fills on the end-of-game screen (§20) |
| `ui/EnemyNoteModal.gd` | The write-up for a (game, enemy) or (game, character) pair, also asked for on a goal's confirm (§2.1) |
| `ui/GoalsBeatenView.gd` | The goals beaten at a game, on the Collection's game page |
| `ui/ConfirmPanel.gd` | The shared "did you really?" confirm the checklist's ticks raise |
| `redesign2/CompletedGoalsPanel.gd` | The run's ✓ *N* done record, grouped by game (§2.1) |
| `redesign2/GraveyardPanel.gd` | Every body the run has put down |
| `redesign2/RunLogScreen.gd` | The header's 🕮 History: `GameLog` grouped into the run's stops |
| `redesign2/MaskChoiceModal.gd` | Mysterious Mask's pick of a second character's level-up (§3.1) |
| `redesign2/SmeltChoiceModal.gd` | Smelter: take a passive piece out of the pack and keep it working (`docs/loot-passives.md` §16) |
| `redesign2/CampScreen.gd` | The end-of-session Camp: Rest or the card a game beaten since the last camp dealt (`docs/rest-site-design.md`) |
| `redesign2/LocationPopup.gd` | A location's arrival popup, and the same popup off the strip's chip, where its actions are (`docs/locations-design.md`). Loaded by path, no `class_name` |
| `redesign2/LocationChip.gd` | The location on the board strip, beside the difficulty: its hover card and its click |
| `redesign2/CollapseScreen.gd` | Fracture 10's turnaround once the Amulet is beaten (`docs/fracture-design.md` §7) |
| `redesign2/LootWindow.gd`, `LootGrid.gd`, `LootSlot.gd`, `LootTrash.gd`, `LootDiscoveries.gd`, `LootUseModal.gd` | The pack: the loot grid, its slots and bin, "Known this run", and using a piece (`docs/loot-passives.md`) |
| `redesign2/OwnedPick.gd` | Pick one of the bodies on the board, for an effect that asks "which" |

### `scripts/runtime/` — the rules that are not screens

| Script | What it owns |
|---|---|
| `RunGraph.gd` | The real-games influence graph: neighbours, distances, the shortest-path DAG, picking the Amulet and the start panel (§19.3) |
| `Fracture.gd` | The ten difficulty levels: the ladder, the run's level, and the text every screen shows it with (`docs/fracture-design.md`) |
| `GameRanks.gd` | Game and character XP and ranks, derived from `GameStats`, never stored (§20) |
| `LootPassives.gd` | What a piece does from its pack slot, and every neighbour rule (`docs/loot-passives.md`) |
| `LootOps.gd` | The ops loot effects are built from |
| `WeaponSystem.gd` | Weapons: aiming, areas and the goal that charges them (`docs/loot-passives.md` §12) |
| `Camp.gd` | The Camp's rules: when one is owed, what it deals, Rest and Brace (`docs/rest-site-design.md`). Loaded by path, no `class_name` |
| `Locations.gd` | The location rules: the deal, the tag lean every roll goes through (`Locations.pick`), and what a location makes true while you are there (`docs/locations-design.md`). The state is `GameLoop2.location_*` |
| `RayAim.gd` | The ray that bounces (Ball x Pit's ball, Earthquake, the ray wands) |
| `AudioTags.gd` | Reads a music file's own tags, for filling the `radio` sheet from a folder |

`PlaySession2.gd` is the text-only precursor of the overworld, kept as a headless
harness for the loop.

## The window

The game opens **windowed** (`display/window/size/mode=0`). That is deliberate:
the core loop is leaving the game to go and play a real one and coming back to
report, so the player alt-tabs out several times a run — and a window is the only
mode that leaves the OS's own taskbar/dock on screen to do it with.

**The window and the canvas are two different numbers.** `viewport_width/height`
is the CANVAS — the fixed 1280x720 box the layout is built to fit — and it never
changes. `window_width/height_override` is how big the window that canvas is
scaled into opens: **2560x1440**, so a 1440p screen draws the page at 2x instead
of in a quarter of the desktop. `Settings.WINDOWED_SIZE` holds the same pair for
every later switch back to windowed, and a test pins the two together — if they
drift, the window resizes itself the moment you press F11 twice.

That size is a **request**. `Settings.windowed_fit()` clamps it to the screen's
usable rect (what is left once the taskbar / dock / menu bar have taken theirs)
*minus the window frame*, since the title bar sits outside the size being set —
so a smaller monitor gets as much as fits and the taskbar stays clear either way.
It is floored at 1280x720: a page shown whole under a taskbar beats a page
cropped to fit above one. The arithmetic is a pure static function precisely
because none of it can be exercised on a headless runner, which has no window
manager and therefore no decorations and no taskbar.

Both fullscreens are still on the list. `Settings → Display` offers **Windowed**,
**Windowed fullscreen (borderless)** (`FULLSCREEN` — a borderless window the size
of the screen, *not* `EXCLUSIVE_FULLSCREEN`) and **Exclusive fullscreen**; **F11**
toggles windowed ⟷ borderless from any screen, and the choice is persisted to
`user://settings.cfg`. Leaving either fullscreen re-fits and re-centres the
window, so "windowed" never comes back the size of the screen with the taskbar
still buried under it.

The stored preference lives under a **versioned key** (`Settings.DISPLAY_KEY`)
because the default moved from borderless to windowed after saves existed: a
`settings.cfg` written under the old default holds an explicit borderless value
for a player who never chose one, and reading a new key is what tells those two
apart — exactly once.

The **layout's size does not change with the monitor**. `stretch/mode` is
`canvas_items` over a fixed 1280×720, so a bigger screen draws the same page
bigger rather than giving it more room — which is exactly why the overworld is
built to fit 1280×720 and why `test_overworld2` pins that. `stretch/aspect` is
`expand` rather than the default `keep`, so a screen that isn't 16:9 gets its
extra pixels as real canvas instead of black bars (16:10 → 1280×800, ultrawide →
1706×720); `expand` can only ever give *more* than the base, so the one-screen
guarantee holds.

## Data as Godot Resources

All game content is authored as typed Godot **Resources** (`.tres`) under `data/`,
with their schemas defined in `scripts/resources/`:

`GameData`, `GoalEnemyData` (enemies and bosses), `CharacterData`, `ItemData`,
`AbilityData`, `StatusData`, `TileEffectData`, `UnitData`, `EventData2`,
`ObjectData`, `CurseData2`, `ShopkeeperData`, `SongData`, the loot kinds
(`ScrollData` + `ScrollNames`, `PillData`, `PotionData`, `CardData`, `WandData`,
`TrinketData`, `BagData`, `WeaponData`, `EvolutionData`), `StatDefinition`, and
`AtlasLayout` (the baked star chart). The combat-era `CurseData` and its
`data/curses/` set were deleted on 25 Oct 2026, with the pre-2.0 items and
characters.

(`TileEffectData` rather than `TileData` because Godot ships a native `TileData`
for TileMaps and a `class_name` that shadows one is a parse error — the sheet, the
data folder and the ids all stay "tile".)

`Data.gd` loads them all on startup and serves them by id, so gameplay code never
hardcodes content — it asks `Data` for it. Random draws all share one rarity
ladder there too (`Data.roll_rarity_step` / `roll_item_rarity`): 75/20/4/1
common/uncommon/rare/legendary (`Data.RARITY_WEIGHTS`, the one place to tune them).

## Luck

**Every point of Luck is a 50% chance of one more roll, and the better result is
kept.**

That is the whole model, and it applies to every random decision the run makes.
A coin is flipped per point and every heads buys a reroll. At 1 Luck a 25% chance
is really **34.4%** (`1 - 0.75 × 0.875`); at 3 Luck it is **49.8%**. Each point
multiplies the chance of missing by `1 - p/2`, so it is not `p × (1 + luck)`.

Negative Luck is the same machine pointed the other way — a coin per point, each
heads an extra roll, keep the **worse** — so a run at −2 sees that same 25% land
at **9.8%**.

> This replaced a guaranteed reroll per point, which itself replaced a
> 10%-per-point chance of *advantage* (roll twice, sometimes). The first did
> nothing nine times in ten at a single point; the second compounded hard, three
> Luck being four rolls at everything. A coin per point sits between them.

**Which way is "better"** cannot be guessed, so every roll site declares it
(`Stats.Favour`):

| | |
|---|---|
| **`HIGH`** | a bigger number or a success is what you want — the rarity ladder, a chest gamble, how many pickups a bombed machine scatters, the Donation Machine's 5% Luck payout |
| **`LOW`** | success is the bad outcome — the Donation Machine's jam, Curse of Decay's item downgrade |
| **`NONE`** | there is no better side, so Luck stays out — *which* of the twelve Commons you drew, whether a burst machine dropped a Blood Bag or an IV Bag, heads-or-tails on a pickup |

The one that reads backwards is worth spelling out: the Blood Donation Machine's
6.7% explosion is **`HIGH`**. Bursting pays an Event relic and one gold does
not, so Luck makes the machine *more* likely to go off in your face — which is
the outcome you were feeding it for. At 1 Luck the button reads **9.8%**, not
6.7%.

**Where it lives.** `Stats.roll_chance` / `roll_range` / `roll_rarity_step_with_luck`
are the four entry points, and `Data.roll_item_rarity` calls the last of them —
which is what makes "Luck affects every roll" true without thirty call sites
having to remember it. Item rewards, chest sizes, scrolls, shop stock and the
object pools all walk that one ladder.

**What the player sees.** A `🍀 Luck` chip sits with the verbs under the
offering, and any button quoting odds quotes the ones Luck **will actually
roll** — `Stats.effective_chance`. A button that said 6.7% to a player holding a
Clover would be lying to them about the thing they bought it for.

**Where it comes from.** The **Clover** (Uncommon, `items2.0`) is `+1 Luck` as a
passive bonus, so the Luck goes away with the item. The **Lucky Hat** (Common) is
the same point of Luck with a shorter life expectancy — it is destroyed by the
first enemy attack that costs Health, and the Luck leaves with it. The Donation
Machine pays a point on a 5% roll per coin. There is no cap.

## Conventions

- The repo tracks **source only**. Godot's generated `.godot/` cache, `*.import`,
  `*.uid`, and `export_presets.cfg` are gitignored and regenerate on open.
- Art filenames are **PascalCase** and matched to content ids by convention.
- The spreadsheet (`tools/Roguelikes.xlsx`) drives generated content — edit it
  there and regenerate rather than hand-editing generated `.tres` in bulk.
- **Headings and buttons are in Rogue's font, by one rule, not per screen.**
  `UITheme._on_node_added` (wired by `Settings`) looks once at each Label and
  Button entering the tree: a Label sized `FONT_SUB` or larger, or a Button at
  `FONT_BODY` or more that neither wraps nor runs to two lines, gets
  `UITheme.rogue_font()` (Px437 IBM VGA 8x16, a bitmap font) at 16px, or 32px from
  `FONT_DISPLAY` up. A control that sets its own font keeps it. So a new screen
  gets it for free; a heading that must NOT have it sets a font of its own.
- **Font sizes, gaps and CanvasLayer numbers come from `UITheme`.** There is a
  type scale (`FONT_MICRO` … `FONT_HERO`), a spacing scale (`GAP_NONE` …
  `GAP_SECTION`) and a z-order registry (`UITheme.Layer`). They exist because the
  file had a thorough colour system and nothing for the other two axes: 25
  distinct font sizes across the project (105 uses of `12`, 71 of `11`, 62 of
  `13`) and ~20 separations, every one typed at its call site. **The scales hold
  the values that were already in use** — naming them was the whole change, so
  nothing moved and nothing needed re-fitting. If the size you want is not on the
  list, take the nearest one.
- **Both axes are done project-wide.** Fonts went first, since naming a font
  size is a free rename; gaps followed screen by screen, because several on the
  run's screens are load-bearing to the pixel against a 720p budget and each had
  to be read before it was named (`docs/layout-review-backlog.md` has the
  history). `test_design_tokens.gd` reads
  the source and fails on a bare integer, with a list per axis —
  `MIGRATED_FONTS` / `MIGRATED_GAPS`, and `OFF_SCALE_FONTS` / `OFF_SCALE_GAPS` for
  values that genuinely cannot be named, each with a reason, the way
  `check_doc_paths.py` lists its deliberate exceptions. Both lists are also
  asserted **complete** against a walk of `scripts/`, so a new screen cannot ship
  bare integers by simply not being on it — which is the hole a single list had.
