extends Node

# Canonical run-persistent state. Survives between floors, resets on new run.
# Transient per-combat state lives in DeckbuilderCombat (and equivalents)
# and is not stored here.

signal hp_changed(new_hp: int, new_max: int)
signal gold_changed(new_gold: int)
signal stats_changed
signal deck_changed
signal inventory_changed
# Fired when a card permanently evolves into another (EvolutionSystem): carries
# the old + new card ids so id-keyed buff systems can follow the identity change.
signal card_evolved(from_id: StringName, to_id: StringName)
signal current_game_changed(game_id: StringName)
# A status on the PLAYER was applied, ticked, or removed (§13). The checklist and
# the HUD strip rebuild off this; enemy-side statuses ride GameLoop2.loop_changed.
signal player_statuses_changed
# Event goals / curse goals gained, ticked, resolved or expired.
signal event_goals_changed

# === Identity / progression ===
var character_id: StringName = &""
# The run's chosen deck (DeckCatalog id). Independent of the character: it only
# scopes combat/shop card rewards via deck_reward_tag(). Defaults to Random.
var selected_deck: StringName = &""
var save_name: String = ""
var current_game_id: StringName = &""
var start_game_id: StringName = &""
var amulet_game_id: StringName = &""
# A game the player has PINNED to route through on the way to the Amulet. Purely
# a planning mark — it doesn't gate anything, it just tells the star chart and the
# map-to-the-Amulet to draw the road that goes via this game instead of the
# straight-line shortest one (RunGraph.route_dag_via). &"" is the ordinary
# shortest route.
var route_waypoint: StringName = &""
var visited_games: Array[StringName] = []
# The run's WALK, in order, with the repeats left in — every game the player has
# stood on, appended the moment they arrive, ending on the game under their feet.
#
# `visited_games` is a SET with an order: it drops a game the second time the run
# reaches it, because its job is "which nodes has this run touched" (the map's
# trail, the atlas's history segments). That makes it the wrong list for drawing
# the road as a JOURNEY — a run that doubles back over a hub four times walked a
# road with four stops on it, and the strip that drew it from `visited_games`
# showed one. This is the list with the doubling-back still in it.
var path_taken: Array[StringName] = []
var beaten_games: Array[StringName] = []
# Every game the run has actually PLAYED — one entry per game, added the moment
# it is reported, whatever the report said. Beaten, failed or walked away from:
# you went there and you played it.
#
# Not the same list as either of its neighbours above, and the difference is the
# point. `visited_games` is the road behind you, written when you LEAVE a game,
# so the game under your feet is never on it. `beaten_games` is your record —
# only the ones you actually cleared. This is "have I been here before", which is
# what the returning-to-a-game Dash is paid for (Overworld2._grant_repeat_dash).
var played_games: Array[StringName] = []
var total_games_beaten: int = 0
# Count of games the player has *played* (entered + resolved, win or
# lose), as opposed to beaten. Drives the difficulty tier — see
# RunDifficulty.gd. The tier steps up every RunDifficulty.GAMES_PER_TIER
# games played.
var games_played: int = 0
# One number that identifies THIS run, drawn at reset_run and saved with it.
# Anything that has to be stable for a run but different between runs hashes
# against it — the offering's per-slot enemies are the first such thing,
# and it has to survive a save/load, not just an offering redraw.
var run_seed: int = 0

# Combats won this run. Drives the enemy-spawn budget: the first combat of a run
# (count 0) gets the gentle opening budget; see EnemySpawner. Bumped on victory
# via TriggerBus.combat_ended.
var total_combats_completed: int = 0

# Character level. Starts at 1; bumped when the player meets their
# character's level_up_condition on the verification modal (see Overworld's
# level-up flow and CharacterData level-up fields).
var player_level: int = 1

# Whether the most recently beaten game was "perfected" (beaten without
# losing a run). Set by the perfect-game verification step; read by
# perfect-aware items / future systems. Transient — not saved.
var last_game_perfected: bool = false

# Curse bookkeeping for the most recently cleared game, set by the post-game
# verification step (see Overworld._resolve_curse_penalties). Both count only
# RESTRICTION curses (the kind that can be "triggered" by breaking their rule).
# Read by overworld-encounter requirement gates (Deal with the Devil needs a
# triggered curse last game; the Angel Room needs 2+ held and none triggered).
# Transient — not saved.
var last_game_curses_held: int = 0
var last_game_curses_triggered: int = 0

# Mid-encounter resume that has to survive a combat scene-swap: when an overworld
# encounter launches a combat (the teleporter's "fight an elite first"), the
# overworld is freed and rebuilt, so the unfinished tail (e.g. the pending
# teleport) is stashed here and resumed when the fresh overworld re-opens.
var pending_encounter: Dictionary = {}

# === Player vitals ===
var max_hp: int = 75
var hp: int = 75
var max_energy: int = 3
var hand_size: int = 5

# === Stats ===
# Strength / Dexterity / Intelligence / Charisma drive the derived
# combat statuses (Power / Defense / Arcane / Persistence) and the
# event-roll bonuses. Constitution is roll-only for now. Speed is
# mode-interpreted (extra cards / move speed / tile-move speed) and
# starts at 0 — gained via items / level-up only.
var strength: int = 0
var dexterity: int = 0
var intelligence: int = 0
var charisma: int = 0
var constitution: int = 0
var luck: int = 0
var speed: int = 0

# Harvesting: after beating a game, the player gains gold equal to this
# stat (paid out by Stats on TriggerBus.game_beaten). Item-granted.
var harvesting: int = 0

# Crit: crit_chance is the player's base crit % (item-granted, may be
# negative). crit_damage is the % bonus a crit adds — 100 means a crit
# deals double damage. The live per-hit roll folds Luck in via
# Stats.crit_chance_percent(); see docs/stat-dispatcher.md.
var crit_chance: int = 0
var crit_damage: int = 100

# Regeneration: at the start of combat the player gains Regeneration status
# equal to this stat (1 HP healed per stack at end of turn). Item-granted.
var regeneration: int = 0

# === Economy ===
# Gold (docs/games-first-redesign.md §14). RUN-SCOPE: it is never carried between
# runs, so what a run opens with is entirely the character's `start_gold` (3
# across the roster today — exactly one Common item). It is earned a coin at a
# time off defeated enemies (1, or 3 for a boss) and spent at the hub shops.
#
# The numbers are deliberately tiny. This started at 99 with shop prices in the
# tens, inherited from the combat build; the whole HUD is designed to stay
# glanceable for the OBS companion window (§9), and a purse that fits in one
# digit is the version of that a viewer can read without pausing.
var gold: int = 0

# === Deck / items ===
# Each entry is a CardInstance (runtime wrapper around CardData) — see
# CardInstance.gd in scripts/runtime/. For Phase 1a we'll allow raw
# CardData here too and upgrade to wrappers when upgrades land.
var deck: Array = []
var inventory: Array = []                # Array[ItemData] — each entry is a duplicated Resource (see add_item)
var equipped_weapon: ItemData = null     # Also a duplicated Resource

# Cached sum of every inventory + equipped item's effective_stat_bonuses().
# Stats.get_value() reads this so consumers see base + item bonuses
# without each call site adding the bonus manually. Refreshed by
# _recompute_item_bonuses() whenever inventory mutates or an item is
# upgraded/downgraded. Excludes the health bucket — see _applied_item_*.
var item_stat_bonus: Dictionary = {}

# Fast guard for Stats.get_value: true while any owned item declares a
# stat_mirror (Paper Bag). Refreshed by _recompute_item_bonuses so the hot
# stat-read path can skip the inventory scan entirely when no mirror is owned.
var stat_mirror_active: bool = false

# Rock Bottom: stat-floor machinery. While any owned item declares a
# stat_floor list, the named stats can never read below the highest EFFECTIVE
# value they've ever reached this run (Isaac-style — a temporary buff that
# raises the value gets locked in permanently). stat_floor_active is the cheap
# guard for Stats.get_value's hot path; stat_floor_stats is the union set of
# floored stat ids (String -> true); stat_high_water records the running peaks
# (String -> int) and is persisted across saves.
var stat_floor_active: bool = false
var stat_floor_stats: Dictionary = {}
var stat_high_water: Dictionary = {}

# Cricket's Head: multiplicative stat scaling. While any owned item declares a
# stat_multipliers map, the product of every matching multiplier is applied to
# that stat's effective value (last, after flats/mirror/floor). stat_multiplier_active
# is the cheap hot-path guard; stat_multiplier maps stat id (String) -> float
# product. Rebuilt by _recompute_item_bonuses.
var stat_multiplier_active: bool = false
var stat_multiplier: Dictionary = {}

# Health-bucket stats (max_hp, max_energy) are applied as direct
# deltas to the GameState fields — never through item_stat_bonus — so
# reads of GameState.max_hp / max_energy stay authoritative without
# layering. The _applied_item_* fields remember our running
# contribution so a recompute moves only the delta.
var _applied_item_max_hp: int = 0
var _applied_item_max_energy: int = 0
# Per-verb delta this inventory currently applies to the games-first board verbs
# (a passive +1 Bash). The 2.0 verbs (bash/transmute/scramble/bombs/keys/
# dash/shields) are plain fields the loop spends directly — not read through
# Stats.get_value — so a passive stat_bonus on one is folded straight into the
# field and reversed when the item leaves, tracked here like _applied_item_max_hp.
var _applied_item_verbs: Dictionary = {}
const _ITEM_VERB_STATS := ["bash", "transmute", "scramble", "bombs", "keys", "dash", "shields",
	"block", "push", "game_choices"]

# Jelly (and any future SCALING rule that outputs max_hp): tracked exactly
# like _applied_item_max_hp above, but separately, since it's recomputed by a
# different pass (see _recompute_item_bonuses). Kept apart so a save's base
# max_hp can subtract both contributions independently.
var _applied_scaling_max_hp: int = 0

# Handcuffs: live max_hp ceiling while any owned item has caps_max_hp = true.
# -1 = no cap. Rebuilt every _recompute_item_bonuses call: set to the current
# max_hp the moment a capping item is (or becomes, e.g. on load) owned, held
# fixed while the item stays, cleared the moment none remain. Enforced in
# set_max_hp and the vitals pass below, so it covers every source of max_hp
# growth (level-ups, cards, potions, item scaling) uniformly.
var max_hp_cap: int = -1

# Monotonic id source for ItemData.instance_id. Each call to add_item
# bumps this so duplicated weapon Resources can be paired with their
# granted CardInstance (CardInstance.source_weapon_id) — and so save /
# load can rehydrate the link without name collisions across slots.
var _next_item_instance_id: int = 1

# Run-scope loot counters for the NON-itemized kinds (keys for now). Potions
# and scrolls are concrete entries in `loot_items` below; their counts are
# derived from it by get_loot_count so cards like Alchemize (add_loot "potion")
# and the Backpack keep working unchanged.
var loot: Dictionary = {
	"key": 0,
}

# Concrete loot the player is carrying, in pickup order. Each entry is a
# Dictionary:
#   potion: {"type": "potion", "id": StringName, "rarity": String}
#   scroll: {"type": "scroll", "rarity": String}   (inert stub — the scroll
#           system isn't ported yet, so these list but can't be used)
# Potions are usable only in combat (drink / throw). See PotionSystem.
#
# THE ARRAY IS PICKUP ORDER; WHERE A PIECE SITS IN THE 3x3 IS `pack_slot`
# (docs/games-first-redesign.md §4.3). The two used to be the same thing — slot i
# drew `loot_items[i]` — which meant an arrangement the player could make had to be
# one a dense array could hold, so a piece dragged into the middle of an empty pack
# slid back to the end. An entry now carries the slot it was PUT IN, and the array
# stays the order things were picked up in, which is what `loot_scrolls()`,
# `_drop_loot_of_type` and the toggle's peek all read. See `loot_layout`.
var loot_items: Array = []

# Identification is GLOBAL per potion type (StringName ids). Drinking, throwing,
# or paying to identify a potion reveals EVERY copy of that type for the rest of
# the run. Persisted with the save.
var identified_potion_types: Array[StringName] = []

# Sibling of identified_potion_types for SCROLLS. Reading a scroll (or a Scroll
# of Identify) reveals every copy of that type for the rest of the run; Scroll of
# Amnesia can un-identify them. Unidentified scrolls all share one mystery art
# (scrolls/Unidentified.png) — no per-run colour map like potions. See
# ScrollSystem. Persisted with the save.
var identified_scroll_types: Array[StringName] = []

# Per-run bottle-colour assignment for UNIDENTIFIED potions: potion id (String)
# -> an "Unidentified_<Color>" art base. Built lazily by PotionSystem so an
# unknown potion always shows the same mystery bottle within a run (and a
# different one next run). Persisted so a reloaded run keeps its colours.
var potion_color_map: Dictionary = {}

# ECHO CHAMBER'S MEMORY (§4.3): the loot entries the player has USED, oldest
# first. Run state rather than item state on purpose — the relic reads this, it
# does not carry it, so two Echo Chambers see one history and picking one up
# mid-run reads what the run already did. Written by LootSystem, which is also
# where the ordering rule (nothing echoes itself) lives.
var loot_used_memory: Array = []

# Sibling of identified_scroll_types for PILLS (§4.3). Taking a pill reveals its
# COLOUR for the rest of the run — both doses of it, in both directions, since a
# horse pill is the same capsule at a bigger size. Amnesia's horse dose clears
# this. Persisted with the save.
var identified_pill_types: Array[StringName] = []

# THE RUN'S ALPHABET: pill id (String) -> the art base under images2.0/pills/
# ("BlueCyan", whose horse dose is "BlueCyanHorse"). Dealt once per run by
# PillSystem from the 13 colours on disk, which leaves THREE colours unbound —
# the reason a pill can't be deduced by elimination once the other nine are
# known. Persisted, so a reloaded run keeps the alphabet it taught you.
var pill_color_map: Dictionary = {}

# === Incremental-item counters ===
# Progress counters that drive "every Nth …" items (Happy Flower, Nunchaku,
# Ornamental Fan, Shuriken, Pen Nib) and let the Backpack show how close each
# one is to its next proc. Bumped centrally by ItemTriggers.fire so every
# combat mode (deckbuilder card play, action loop, strategy ability) feeds the
# same counters; read back by EffectSystem's `counter` handler.
#
# Two "turn" clocks (they coincide in deckbuilder/strategy; they diverge in
# Action, which has no discrete turns):
#   * turn_started — a discrete turn / combat ROOM. Drives "on the Nth turn"
#     one-shots via if_turn (Horn Cleat). Room-based in Action.
#   * turn_tick    — the recurring heartbeat. Once per turn in deckbuilder/
#     strategy; on the real-time turn-tick timer in Action. Drives recurring
#     per-turn effects so they're paced by the timer, not by room transitions.
#
#   incremental_attacks_total  — Attacks played this RUN (persists across
#                                combats; reset only by reset_run). Nunchaku /
#                                Pen Nib read this.
#   incremental_attacks_turn   — Attacks played within the current turn window
#                                (reset every turn_tick — so timer-based in
#                                Action). Ornamental Fan / Shuriken.
#   incremental_turn_pulses    — Count of turn_tick heartbeats this combat
#                                (Happy Flower's "every N turns"). Read as the
#                                "turns" counter.
#   incremental_turn           — Current discrete turn / room number (set on
#                                turn_started). Not read by recurring counters;
#                                kept for display / debug.
var incremental_attacks_total: int = 0
var incremental_attacks_turn: int = 0
var incremental_turn_pulses: int = 0
var incremental_turn: int = 0

#   incremental_hp_losses      — Times the PLAYER lost HP this combat (each
#                                change_hp(-n) while a combat scene is live is
#                                one instance, whatever the source: enemy hits,
#                                DoT ticks, self-damage cards). Blood for
#                                Blood's cost_reduce_from counter.
#   incremental_discards_turn  — Cards discarded by effects within the current
#                                turn window (reset every turn_tick; the
#                                end-of-turn hand sweep doesn't count).
#                                Eviscerate's cost_reduce_from counter.
var incremental_hp_losses: int = 0
var incremental_discards_turn: int = 0

# Pen Nib: set true while the player's current (10th) Attack resolves so
# Stats.resolve_damage doubles its hits. Cleared at the start of the next
# card play and on combat/turn boundaries.
var pen_nib_double_active: bool = false

# Dead Eye: the current consecutive-hit streak, mirrored here so the Backpack
# can show the live "+N Dmg" number like the other incremental items. 0 when no
# streak is active. Derived from _streaks below.
var dead_eye_streak: int = 0

# Named consecutive-hit streaks (Dead Eye), centralized here so every combat
# mode (deckbuilder, action, strategy) grows and reads the same streak through
# EffectSystem + each scene's attack path — not just the deckbuilder. Keyed by
# streak id -> {count, target, attack_bonus, label}. The `target` is whatever
# actor object the scene passed (CombatActor / Unit); identity comparison
# detects target switches. Cleared at combat start.
var _streaks: Dictionary = {}

# Spells learned this run, addressed by SpellData.id. Drives the
# strategy/tactical Spellbook (Phase 6). Spell defs live in
# `SpellsCatalog` until designers ship .tres files for them.
var learned_spells: Array[StringName] = []

# === Action-mode loadout (StringName ids resolved via Data) ===
# Two manual click slots — left (LMB) and right (RMB). Only Strikes or
# weapon-granted cards may be slotted here; everything else in the deck
# plays automatically. Empty / unset means "auto-pick from deck on
# combat start".
var action_left_card_id: StringName = &""
var action_right_card_id: StringName = &""

# Cache of upgraded-form CardData duplicates for action mode, keyed by card id.
# Built lazily by effective_action_card_data so every upgraded copy of an id
# shares one resource (matching how base copies share Data.get_card's). Cleared
# on run reset.
var _action_upgraded_cache: Dictionary = {}

# Action-mode item slots, assigned on the equipment screen:
#   * action_active_item_id  — one USABLE consumable item, popped with Q.
#                              Cleared when the item is spent.
#   * action_charged_item_id — one CHARGED active, fired with E. While slotted it
#                              is the only charged item that gains a charge per
#                              turn (the per-combat baseline still tops up all of
#                              them). Both slots are independent.
var action_active_item_id: StringName = &""
var action_charged_item_id: StringName = &""

# === Temporary (consumable) buffs ===
# Layers on top of base + item bonuses in Stats.get_value(). Populated by
# the `temp_stat` effect when a pill is used; lasts one combat
# (deckbuilder/strategy), one room (action), or until an event closes — then
# cleared by clear_temp_buffs() at the matching boundary.
var temp_stat_bonus: Dictionary = {}
# Per-turn temporary status stacks on the player (Prayer Beads' "+3 Brace until
# end of turn"). status_id (String) -> stacks added this turn. ItemTriggers
# strips these off the player actor at the next turn_started and clears the
# tally at combat boundaries, so the buff only survives the turn it was gained.
var temp_status_stacks: Dictionary = {}
# Block granted by a consumable (Percs) while resolving an event. Combat
# block lives on the player CombatActor; events have no actor, so this pool
# soaks the next chunk of event damage. Cleared with the temp buffs.
var event_block: int = 0

# Live combat context, registered by whichever combat scene is running so
# globally-invoked item uses (backpack / active slot) route their effects
# into the running fight. Empty when not in combat.
var combat_scene = null
var combat_player = null
# True while an EventModal is open — the only non-combat place a pill may be
# used (gates the backpack's Use button).
var event_active: bool = false
# Live overworld scene, registered while the player is on the map. Lets
# overworld_usable items (Winged Boots) route their item_used effect to the map
# so they can be fired from the backpack / overworld HUD. Null off the map.
var overworld_scene = null

# === Run-scope resources ===
# Skip is removed from the stat set — the only "skip" is the
# verification-screen "didn't play the real game" choice with the
# fixed HP penalty.
var dash_charges: int = 0
var reroll_charges: int = 0
var fov_bonus: int = 0
var discovery: int = 0

# === Games-first redesign (2.0) run-scope resources ===
# The no-combat rework's board-manipulation verbs + consumables (§4) and the
# carry-over Block (§3), all rendered as small ints on the OBS HUD (§9). In a
# 2.0 run, Health / Max Health reuse hp / max_hp (set from the character's
# base_max_hp at run start) and Dash reuses dash_charges above; only these are
# new. Granted via CharacterData start_* loadout, item effects (gain_stat),
# and level-up rewards. All default 0, so combat runs are unaffected.
# TEMPORARY SHIELDS — the armour the game you're playing granted (§3). A game
# hands you GameLoop2.shields_for_game() of them the moment you select it (3, or
# 5 for a Traditional game), and EACH ONE STOPS ONE INSTANCE OF DAMAGE: a
# 3-damage swing breaks one and lands for nothing, and so does a 1-damage one
# (GameLoop2._take_hit). Losing a run does NOT spend them — that costs a turn of
# the board instead (GameLoop2.log_attempt) — so what you carry into the report
# step is what the followers have to get through.
#
# Then they EXPIRE, which is the whole of what the word TEMPORARY is for: they do
# not carry into the next game (GameLoop2.beat_game clears them after the enemies
# have struck and advanced), unless Barricade banks the survivors into
# `bonus_shields` below. No cap.
#
# THE FIELD IS STILL `shields`, and deliberately: it is the key every save is
# written with and the stat name authored content grants (`gain_stat shields 1`
# is Anchor). Renaming it would flip the meaning of that word inside every
# existing save and every .tres that says it — and `bonus_shields` would have to
# take the name it just gave up, so a single missed site would silently fill the
# wrong pool. The player-facing names live in TEMP_SHIELD_NAME / SHIELD_NAME
# below, and every screen reads its words from there.
var shields: int = 0
# SHIELDS — the pool that is not per-game (§4.3). Gained off the board (Balls of
# Steel, horse Full Health) or banked out of a resolved game by Barricade, and
# unlike the temporary ones they do NOT expire: they stay until something breaks
# them, which is what makes one worth saving for the game after next.
#
# Spent LAST: a hit breaks a temporary shield first and only reaches these once
# those are gone. Drawn closest to the player — nearest the portrait on the
# board's hero, and on the header's Health chip, since a pool gained on the
# overworld has to be readable when no board is on screen.
var bonus_shields: int = 0

# THE TWO POOLS' PLAYER-FACING NAMES (§3.2), in one place because they are told
# apart by exactly one fact — whether they survive the game — and a screen that
# invented its own word for either would be describing a third thing.
#
#   `shields`        -> "Temporary Shield"   granted per game, expires with it
#   `bonus_shields`  -> "Shield"             kept until something breaks it
#
# The mapping reads backwards from the field names, which is the cost of not
# renaming the fields (see `shields` above). Everything the player reads goes
# through the helpers below, so the two can never drift apart on screen.
const TEMP_SHIELD_NAME := "Temporary Shield"
const SHIELD_NAME := "Shield"

# "1 Temporary Shield" / "3 Temporary Shields", and the same for the pool that
# stays. `n` is the count; the plural agrees with it.
static func temp_shields_text(n: int) -> String:
	return "%d %s%s" % [n, TEMP_SHIELD_NAME, "" if n == 1 else "s"]

static func shields_text(n: int) -> String:
	return "%d %s%s" % [n, SHIELD_NAME, "" if n == 1 else "s"]
var bash: int = 0
# Push (Manager's signature verb, from Raccoin): spend a charge to shove a
# following enemy back one space, delaying its next attack by a game (§7.2) —
# the same timing relief Stun gives, but player-triggered from a charge.
var push: int = 0
var transmute: int = 0
var scramble: int = 0
var bombs: int = 0
var keys: int = 0
# Extra game cards the overworld offers on top of Overworld2.BASE_OFFER_COUNT (the
# base 3 selections, §7). Items / level-ups / future effects raise this through the
# normal stat plumbing ("game_choices"), so widening the offering is a granted
# bonus rather than a rebuilt UI.
var game_choice_bonus: int = 0

# === Statuses 2.0 (docs/games-first-redesign.md §13) ===
# Statuses ON THE PLAYER, as status id -> stack count (X). A BUFF here is an extra
# standing goal on the checklist that pays its reward every game you satisfy it; a
# DEBUFF here bolts its clause onto EVERY enemy's goal and sheds a stack each game
# you complete one. Enemy-side statuses are not here — they belong to a body on the
# board, so they ride on the GameLoop2 stack entry (and its save blob) instead.
#
# Run-scope: cleared by reset_run, saved by SaveSystem. Never write this directly —
# apply_status / remove_status keep the zero-stack entries pruned so "is it on me?"
# is just a `has`.
#
# THESE ARE THE PERMANENT STACKS. Anything with a clock on it lives in the timed
# layer below and is summed on top for every read.
var player_statuses: Dictionary = {}

# THE TIMED LAYER (docs/potions-design.md §5.4) — stacks that expire on their own,
# as [{id: StringName, stacks: int, games: int, shield: int}] in the order they
# were applied. A potion drunk "until the end of the next combat" is a row here
# with `games` 1; `GameLoop2.beat_game` ticks every row down and drops the ones
# that run out, exactly where it burns the tiles down (§17).
#
# A LAYER RATHER THAN A CLOCK ON THE STACK COUNT, because a status can be half
# permanent and half borrowed: a run holding a Dexterity from an item and then
# drinking a Speed Potion has 2 that stay and 5 that go, and one integer cannot
# say that. So every read — status_stacks, status_list, combat_totals — asks
# `effective_statuses()` for permanent + timed, and a row expires WHOLE.
#
# `shield` is what that row's application handed out (§5.5). It is always 0 here:
# Dexterity's shield side is `EnemyOnly` (§13.4), so the player is never granted
# one. The field is on both holders' rows so the two layers stay one shape.
var timed_statuses: Array = []

# ---------------------------------------------------------------------------
# Event goals and curse goals (docs/event-sheet-authoring.md §5)
#
# The two kinds of objective an EVENT can leave behind after its modal closes.
# Both are run-scope, both tick down one per game played, and both live here
# rather than on GameLoop2's stack because neither is attached to an enemy — an
# enemy goal is a debt that follows you, these are a bonus and a bill.
#
#   event_goals  {event, condition, games_left, effects, effects_text}
#                Meet it -> pays `effects`, and it is done. Let it run out ->
#                nothing happens. Removed when met or when games_left hits 0.
#
#   curse_goals  {curse, event, games_left}
#                The INVERSE: meeting the condition costs you the curse's
#                penalty, and it does NOT go away — it can bite again next game.
#                Only the timer removes it. Condition, penalty and default timer
#                come from CurseData2 (data/curses2.0), so the same curse handed
#                out by two events is one authored thing.
# ---------------------------------------------------------------------------
var event_goals: Array = []
var curse_goals: Array = []
# event id -> times fired this run. Events have no per-run cap any more; this is
# the lifetime-of-the-run tally the Collection reads and the shuffle bag's record
# of what has come up.
var events_fired: Dictionary = {}
# THE BAG (EventSystem.roll_for_arrival). event id -> true for every event drawn
# since that rarity last reshuffled — an event does not come round again until
# every other one of its rarity has been seen. Drawing marks an event seen even
# if the player walks straight back out of it: seeing it is what was spent.
var events_seen: Dictionary = {}
# The last event drawn, so a reshuffle cannot hand back the one that just
# emptied the bag. The single thing a fresh bag is not allowed to open on.
var last_event_id: StringName = &""
# game id -> true once that game has paid its event. An event fires after every
# game, but each GAME only ever pays one: walking a loop between two nodes would
# otherwise be an event faucet at a game a pull.
var event_nodes_fired: Dictionary = {}

# ---------------------------------------------------------------------------
# SHOPS (docs/games-first-redesign.md §14). The logic lives in ShopSystem; this
# is the run-scope state it reads and writes, on the same split EventSystem uses.
#
#   hub_games   The run's ten shop games, FROZEN at the first ask and never
#               recomputed. RunGraph.hub_ids() is a live read of the graph, and
#               the graph can be rebuilt underneath a run (the game filter does
#               exactly that), so asking it twice is not guaranteed to give the
#               same ten. A shop that appeared or vanished mid-route would make
#               the flag on an offered card a lie, which is the one thing the
#               placement of every other badge in this build is designed around.
#
#   shops       game id -> that hub's shop, and it PERSISTS for the whole run:
#                 {"stock": [{item, price, sold}, …], "seen": bool}
#               Buying marks a slot sold rather than removing it, so what is left
#               can be listed on the card's popup next time the hub comes around
#               (§14) — a returning player is shopping from the same shelf they
#               left. `seen` is what separates "a shop is here" from "here is
#               what's in it": stock is only quoted once the player has stood in
#               it, so the first visit is still a discovery.
# ---------------------------------------------------------------------------
var hub_games: Array[StringName] = []
var shops: Dictionary = {}

# === Curses / status ===
var active_curses: Array = []            # Array[Dictionary] for now
var pending_combat_statuses: Array = []  # carryover from events

# Carryover from a pre-combat event into the next combat the player enters.
# Drained (and cleared) when that combat starts. All three modes honour them.
#   pending_ambush — "" / "ambush" (player gets the drop on the enemy) /
#                    "ambushed" (the enemy gets the drop on the player).
#   pending_spawn_enemies — Array of { "enemy": StringName, "count": int };
#                    extra enemies added on top of the encounter (deckbuilder).
var pending_ambush: String = ""
var pending_spawn_enemies: Array = []

# Carryover scroll effects that land at the START of the next combat, drained by
# each combat mode's start hook (ScrollSystem.apply_pending_combat_effects).
# Mirror how pending_ambush / pending_spawn_enemies already work cross-mode.
#   pending_enemy_buff — { "power": int, "defense": int } added to every enemy
#                        (Scroll of Aggravate Monsters).
#   pending_enemy_start_stun — { "all": bool, "count": int, "choose": int }:
#                        `all` stuns every enemy, `count` stuns that many random
#                        enemies, `choose` lets the player pick up to N to stun
#                        (Scroll of Scare Monster).
#   pending_fire_damage_all — flat fire damage dealt to every enemy at combat
#                        start (Scroll of Fire).
var pending_enemy_buff: Dictionary = {}
var pending_enemy_start_stun: Dictionary = {}
var pending_fire_damage_all: int = 0

# "A Note For Yourself" stores a card id here so the next encounter can hand it
# back. Empty until the player stores one; the event seeds a default the first
# time (see EventData note_for_yourself effect).
var note_for_yourself_card: StringName = &""

# === Phase ===
enum Phase { MENU, OVERWORLD, EVENT, COMBAT, DEAD, ESCAPE, WIN }
var phase: Phase = Phase.MENU

# ---------------------------------------------------------------------------
# Curse-card lifecycles (run scope)
# ---------------------------------------------------------------------------

func _ready() -> void:
	# GameState is the FIRST autoload, so TriggerBus doesn't exist yet during
	# _ready. Defer the connect until every autoload has been added.
	_connect_lifecycle_hooks.call_deferred()

func _connect_lifecycle_hooks() -> void:
	# Guilty (destroy_after_games) and any future game-count lifecycle ticks
	# fire on game_beaten — run-scope, so it counts in every combat mode.
	if not TriggerBus.game_beaten.is_connected(_on_game_beaten):
		TriggerBus.game_beaten.connect(_on_game_beaten)
	# "When a game is selected" — the hook the shield economy hangs on (Anchor's
	# +1 Shield, §3/§8). Run-scope and scene-less, like game_beaten below.
	if not TriggerBus.game_selected.is_connected(_on_game_selected):
		TriggerBus.game_selected.connect(_on_game_selected)
	# Run-scope curse triggers. These fire OUTSIDE combat (a curse is gained on
	# the verification screen, removed in the backpack/an event), so they can't
	# ride the per-combat ItemTriggers path. Route them through the scene-less
	# run-trigger runner instead (Vitality Orb on curse_applied; Golden Beetle
	# on curse_removed / curse_card_removed).
	if not TriggerBus.curse_applied.is_connected(_on_curse_applied):
		TriggerBus.curse_applied.connect(_on_curse_applied)
	if not TriggerBus.curse_removed.is_connected(_on_curse_removed):
		TriggerBus.curse_removed.connect(_on_curse_removed)
	if not TriggerBus.curse_card_removed.is_connected(_on_curse_card_removed):
		TriggerBus.curse_card_removed.connect(_on_curse_card_removed)
	# Potion use is a run-scope hook (fired from PotionSystem in any combat mode),
	# so route it through the scene-less runner like the curse_* hooks (Toy
	# Ornithopter heals on potion_used).
	if not TriggerBus.potion_used.is_connected(_on_potion_used):
		TriggerBus.potion_used.connect(_on_potion_used)
	# Spending a Bomb is a battlefield hook with no combat scene behind it
	# (GameLoop2 is scene-free), so it rides the same run-scope runner as the
	# hooks above — Blood Bombs' +1 Health lands on every bomb thrown.
	if not TriggerBus.bomb_used.is_connected(_on_bomb_used):
		TriggerBus.bomb_used.connect(_on_bomb_used)
	# Two more scene-less battlefield/run hooks on the same runner: a body being
	# defeated (Charm of the Vampire counts them) and the player's Health going
	# down (Piggy Bank pays on it). Both fire outside any combat scene, so the
	# effects behind them must be scene-free — which the 2.0 item set is.
	if not TriggerBus.enemy_killed.is_connected(_on_enemy_killed):
		TriggerBus.enemy_killed.connect(_on_enemy_killed)
	if not TriggerBus.health_lost.is_connected(_on_health_lost):
		TriggerBus.health_lost.connect(_on_health_lost)
	# Combats-won tally drives the enemy-spawn budget (first fight is gentler).
	if not TriggerBus.combat_ended.is_connected(_on_combat_ended_tally):
		TriggerBus.combat_ended.connect(_on_combat_ended_tally)
	# Jelly (deck_tag scaling) keys its max_hp bonus off deck weapon-card
	# count, which isn't covered by the inventory-mutation call sites that
	# already call _recompute_item_bonuses directly. deck_changed fires on
	# every deck mutation (add/remove/weapon pairing), so hook it here once.
	if not deck_changed.is_connected(_recompute_item_bonuses):
		deck_changed.connect(_recompute_item_bonuses)

func _on_combat_ended_tally(ctx: Dictionary) -> void:
	# Dev test combats are exempt so testing never skews the run's spawn budget.
	if bool(ctx.get("dev", false)):
		return
	if bool(ctx.get("victory", false)):
		total_combats_completed += 1

# A game was selected and its shields granted (§3). Owned items hooked on
# "game_selected" fire here — Anchor's +1 Shield lands on top of the grant, so the
# extra try is available for the runs you're about to play.
func _on_game_selected(ctx: Dictionary) -> void:
	fire_run_item_triggers("game_selected", ctx)

func _on_game_beaten(_ctx: Dictionary) -> void:
	# Games-first redesign (2.0): "after beating a game" is the dominant item
	# trigger (Burning Blood +1 Health, Meat on the Bone's conditional heal,
	# docs/games-first-redesign.md §8). game_beaten fires outside any combat
	# scene, so route owned items' game_beaten triggers through the scene-less
	# runner — only scene-free effects (gain_hp / gain_max_hp / gain_chest /
	# gain_stat) are valid here, which is exactly what the 2.0 items use.
	fire_run_item_triggers("game_beaten", _ctx)
	# Charged actives (D6, Wand of Wishing) "recharge over N beats" (§8) — with no
	# combat scenes in the 2.0 loop, a beaten game is the recharge tick.
	charge_all_items(1)

func _on_curse_applied(ctx: Dictionary) -> void:
	fire_run_item_triggers("curse_applied", ctx)

func _on_curse_removed(ctx: Dictionary) -> void:
	fire_run_item_triggers("curse_removed", ctx)

func _on_curse_card_removed(ctx: Dictionary) -> void:
	fire_run_item_triggers("curse_card_removed", ctx)

func _on_potion_used(ctx: Dictionary) -> void:
	fire_run_item_triggers("potion_used", ctx)

func _on_bomb_used(ctx: Dictionary) -> void:
	fire_run_item_triggers("bomb_used", ctx)

func _on_enemy_killed(ctx: Dictionary) -> void:
	fire_run_item_triggers("enemy_killed", ctx)

func _on_health_lost(ctx: Dictionary) -> void:
	fire_run_item_triggers("health_lost", ctx)
	# Fortune Necklace and friends shatter here rather than in _take_hit, so the
	# rule holds wherever an enemy's damage is applied from — and so the Shields
	# get their say first: this hook only runs on Health that actually came off.
	if String(ctx.get("source", "")) == HEALTH_SOURCE_ENEMY_ATTACK:
		_destroy_fragile_items()

# Every owned item flagged `destroyed_by_enemy_damage` goes at once — one swing
# that gets through breaks the whole set of trinkets, not the topmost one. Walked
# backwards so removing a slot doesn't shuffle the ones not yet looked at.
func _destroy_fragile_items() -> void:
	for i in range(inventory.size() - 1, -1, -1):
		var it = inventory[i]
		if it is ItemData and it.destroyed_by_enemy_damage:
			Notifications.notify("%s was destroyed." % it.display_name,
				Color(1.0, 0.55, 0.35))
			GameLog.add("%s was destroyed by the hit." % it.display_name,
				Color(1.0, 0.55, 0.35))
			remove_item_at(i)

# Fires every owned item's triggers whose `on:` matches `trigger_name`, with a
# scene-less context (source/target/scene/card = null). The run-scope sibling
# of ItemTriggers.fire — used for hooks that happen outside any combat scene
# (item_acquired, the curse_* hooks). Only scene-free effect handlers
# (gain_max_hp, gain_hp, gain_gold, gain_chest, …) are valid here; combat
# effects (dmg, block, …) silently no-op without a scene.
func fire_run_item_triggers(trigger_name: String, ctx_extras: Dictionary = {}) -> void:
	var sources: Array = []
	sources.append_array(inventory)
	if equipped_weapon != null:
		sources.append(equipped_weapon)
	for item in sources:
		if not (item is ItemData):
			continue
		for trig in item.triggers:
			if String(trig.get("on", "")) != trigger_name:
				continue
			if not bool(trig.get("silent", false)):
				GameLog.add("(%s triggers)" % item.display_name, Color(0.85, 0.9, 0.7))
			for effect in trig.get("effects", []):
				EffectSystem.apply(effect, {
					"source": null, "target": null, "scene": null,
					"card": ctx_extras.get("card"),
					# The owning item — lets a self-referential effect (Unstable
					# Genome's destroy_self) find and remove itself.
					"item": item,
				})

# --- Curse / curse-card tallies -------------------------------------------
# A "curse" (active_curses) and a "curse card" (a CURSE-type card in the deck)
# are DIFFERENT things. Death Orb / Du-Vu Doll / Vitality Orb count curses
# only; Golden Beetle counts both. Keep these two helpers the single source of
# truth so item effects (value_from / stacks_from) and the design stay aligned.

# Number of active curses the player is currently saddled with.
func curse_count() -> int:
	return active_curses.size()

# Evaluates an EncounterData.requirement_effect (an AND-list of comparison
# Dictionaries {field, cmp, value}) against current run-state. Empty list = no
# gate = always available. Unknown fields fail closed (the encounter won't spawn)
# so a typo never silently passes. Field vocabulary mirrors the requirement DSL
# the encounter generator parses.
func encounter_requirement_met(conds: Array) -> bool:
	for c in conds:
		if not (c is Dictionary):
			return false
		var field: String = String(c.get("field", ""))
		var want: int = int(c.get("value", 0))
		var have: int
		match field:
			"last_game.curses_held":
				have = last_game_curses_held
			"last_game.curses_triggered":
				have = last_game_curses_triggered
			"curses_held":
				have = curse_count()
			_:
				return false
		if not _cmp_int(have, String(c.get("cmp", "==")), want):
			return false
	return true

func _cmp_int(a: int, op: String, b: int) -> bool:
	match op:
		">=": return a >= b
		"<=": return a <= b
		">": return a > b
		"<": return a < b
		"==": return a == b
		"!=": return a != b
		_: return false

# Saddles the player with a curse (skipping a game today; events / enemies
# later). Records it in active_curses. The penalty card is NOT granted here — a
# restriction curse drops its card only when the player admits on the
# verification screen that they failed the challenge (see Overworld).
func add_active_curse(curse: CurseData) -> CurseData:
	if curse == null:
		return null
	# Curse of Vulnerability: each active COPY grants one extra duplicate of
	# whatever curse is being gained (including another Vulnerability, so
	# stacking Vulnerability compounds on the next grant). Counted from the
	# copies active BEFORE this grant, so a single call is bounded and never
	# recurses — it never re-checks its own freshly-appended entries.
	var copies: int = 1 + active_affliction_effects("duplicate_curse").size()
	for _i in range(copies):
		active_curses.append({"id": curse.id, "name": curse.display_name})
		TriggerBus.emit_signal("curse_applied", {"curse": curse})
	Notifications.notify(
		"Cursed: %s%s" % [curse.display_name, (" x%d" % copies) if copies > 1 else ""],
		Color(0.85, 0.6, 0.85))
	return curse

# Lifts an active curse (events / shrines / future "cleanse" effects). Removes
# the first active_curses entry matching `curse_id` and fires curse_removed so
# items react (Golden Beetle -> a chest). Returns the resolved CurseData that
# was lifted, or null if no such curse was active.
func remove_active_curse(curse_id: StringName) -> CurseData:
	for i in range(active_curses.size()):
		var entry = active_curses[i]
		if entry is Dictionary and StringName(entry.get("id", "")) == curse_id:
			active_curses.remove_at(i)
			var cd: CurseData = Data.get_curse(curse_id)
			var nm: String = cd.display_name if cd != null else String(curse_id)
			Notifications.notify("Curse lifted: %s" % nm, Color(0.7, 0.95, 0.8))
			TriggerBus.emit_signal("curse_removed", {"curse": cd})
			return cd
	return null

# === Chests (item rewards) =================================================
# A "chest" is the project's parlance for an item-reward — the gold-less
# item-choice screen the player opens to pick one item (docs/games-first-
# redesign.md §8.2). Every defeated enemy banks one (GameLoop2._defeat), and
# other sources (Golden Beetle on curse removal, level-up rewards, Unstable
# Genome) grant them too; the overworld redeems them into RewardScreens when
# it's idle, one screen per chest — so beating several enemies in one game pops
# several reward screens in a row.
var pending_chests: int = 0

# Per-chest choice count, one entry per pending chest, in grant order (§8.2:
# Small = 1 / Regular = 2 / Large = 3 / Legendary = 5 items offered). Kept in lock-step with
# pending_chests so the RewardScreen knows how many items to roll for the chest
# it's opening. `pending_chests` stays the authoritative count (tests read it).
var pending_chest_choices: Array[int] = []

# Grants `count` chests (item rewards), each offering `choices` items to pick
# from (0 = the RewardScreen's default of BASE_ITEM_CHOICES + Discovery). Banks
# them and announces via chest_granted so the overworld can open the item-choice
# screens.
func grant_chest(count: int = 1, choices: int = 0) -> void:
	if count <= 0:
		return
	pending_chests += count
	for _i in range(count):
		pending_chest_choices.append(choices)
	Notifications.notify("Gained %d Chest%s!" % [count, "" if count == 1 else "s"],
		Color(1.0, 0.85, 0.4))
	TriggerBus.emit_signal("chest_granted", {"count": count})

# Banks several chests of DIFFERENT sizes as one grant — what a `[chest reward]`
# pays out (§8.2), where "1 Huge and 1 Small" is one reward rather than two.
# grant_chest takes a single size for the whole batch, so calling it per chest
# would toast the player once per chest and fire chest_granted once per chest for
# something they were promised as one line. Announced once, at the size the reward
# actually was.
func grant_chests(sizes: Array) -> void:
	if sizes.is_empty():
		return
	pending_chests += sizes.size()
	for size in sizes:
		pending_chest_choices.append(int(Data.CHEST_SIZE_CHOICES[int(size)]))
	Notifications.notify("Gained %s!" % Data.chest_sizes_text(sizes),
		Color(1.0, 0.85, 0.4))
	TriggerBus.emit_signal("chest_granted", {"count": sizes.size()})

# Consumes one banked chest, returning its choice count (0 = screen default),
# or -1 if none were pending. The overworld calls this as it opens each
# item-reward screen.
func take_pending_chest() -> int:
	if pending_chests <= 0:
		return -1
	pending_chests -= 1
	return int(pending_chest_choices.pop_front()) if not pending_chest_choices.is_empty() else 0

# All active RESTRICTION curses resolved to CurseData, for the verification
# screen's "did you fulfil it?" rows. Afflictions are automatic and excluded.
func active_restriction_curses() -> Array:
	var out: Array = []
	for entry in active_curses:
		if not (entry is Dictionary):
			continue
		var cd: CurseData = Data.get_curse(StringName(entry.get("id", "")))
		if cd != null and cd.is_restriction():
			out.append(cd)
	return out

# A random curse from the catalog — the skip-a-game penalty draws from here.
func random_curse() -> CurseData:
	var all: Array = Data.all_curses()
	if all.is_empty():
		return null
	return all[randi() % all.size()]

# Every effect dict of `effect_type` among active curses' CurseData.effects —
# one entry per active_curses ROW, not per distinct curse, so a curse held
# twice (two identical entries, however that happened — bad luck on two random
# draws, or Vulnerability duplicating a grant) contributes its effect dict
# twice. Callers that stack (Decay's downgrade roll, Shroud's choice
# reduction, Vulnerability's duplicate count) use .size() or sum over this;
# callers that are just a boolean gate (Misfortune's disadvantage) only check
# is_empty(). Affliction effects are passive modifiers read directly by the
# systems they touch (item rewards, event dice rolls, overworld portal
# choices) rather than fired through EffectSystem — see CurseData.gd.
func active_affliction_effects(effect_type: String) -> Array:
	var out: Array = []
	for entry in active_curses:
		if not (entry is Dictionary):
			continue
		var cd: CurseData = Data.get_curse(StringName(entry.get("id", "")))
		if cd == null:
			continue
		for eff in cd.effects:
			if eff is Dictionary and String(eff.get("type", "")) == effect_type:
				out.append(eff)
	return out

# ---------------------------------------------------------------------------
# Mutation API — UI and combat scenes go through these so signals fire.
# ---------------------------------------------------------------------------

func reset_run() -> void:
	character_id = &""
	selected_deck = &""
	save_name = ""
	current_game_id = &""
	start_game_id = &""
	amulet_game_id = &""
	route_waypoint = &""
	visited_games.clear()
	path_taken.clear()
	beaten_games.clear()
	played_games.clear()
	total_games_beaten = 0
	games_played = 0
	run_seed = randi()
	total_combats_completed = 0
	player_level = 1
	last_game_perfected = false
	last_game_curses_held = 0
	last_game_curses_triggered = 0
	pending_encounter = {}
	max_hp = 75
	hp = 75
	max_energy = 3
	hand_size = 5
	strength = 0
	dexterity = 0
	intelligence = 0
	charisma = 0
	constitution = 0
	luck = 0
	speed = 0
	harvesting = 0
	crit_chance = 0
	crit_damage = 100
	# Zeroed, not defaulted to a purse: apply_character2 puts the character's
	# start_gold in immediately after, and a run booted without a character
	# should hold nothing rather than a stale number.
	gold = 0
	deck.clear()
	inventory.clear()
	equipped_weapon = null
	_reset_item_tracking()
	loot = {"key": 0}
	loot_items.clear()
	identified_potion_types.clear()
	identified_scroll_types.clear()
	identified_pill_types.clear()
	loot_used_memory.clear()
	potion_color_map.clear()
	# The run's pill alphabet is dealt fresh (§4.3) — the same ten pills wear
	# different capsules next run, which is the whole reason learning one is worth
	# anything.
	pill_color_map.clear()
	learned_spells.clear()
	action_left_card_id = &""
	action_right_card_id = &""
	action_active_item_id = &""
	action_charged_item_id = &""
	_action_upgraded_cache.clear()
	temp_stat_bonus.clear()
	event_block = 0
	combat_scene = null
	combat_player = null
	# overworld_scene is NOT cleared here. It is a SCENE-LIFECYCLE registration
	# (Overworld2 registers on mount and clears it in _exit_tree), not run state —
	# and a run reset happens while that scene is still mounted, since booting a run
	# is the first thing the overworld does. Clearing it here left the whole run
	# with no registered overworld: nothing able to move the run (can_use_scrolls),
	# overworld actives unusable (Ride the Bus), and a save unable to find the
	# screen to capture. The guarded clear_overworld_context is what ends the registration.
	event_active = false
	dash_charges = 0
	reroll_charges = 0
	fov_bonus = 0
	discovery = 0
	# Games-first (2.0) resources.
	shields = 0
	bonus_shields = 0
	bash = 0
	push = 0
	transmute = 0
	scramble = 0
	bombs = 0
	keys = 0
	game_choice_bonus = 0
	regeneration = 0
	stat_high_water.clear()
	stat_floor_active = false
	stat_floor_stats.clear()
	stat_multiplier_active = false
	stat_multiplier.clear()
	temp_status_stacks.clear()
	player_statuses.clear()
	timed_statuses.clear()
	event_goals.clear()
	curse_goals.clear()
	events_fired.clear()
	events_seen.clear()
	last_event_id = &""
	event_nodes_fired.clear()
	# The machines go with the run too — the jams, what was blown up, what has
	# been spawned. Not the Donation Machine's bank, which is the one thing here
	# that outlives a run on purpose (GameStats).
	ObjectSystem.reset_run()
	# The shops go with the run, and so does the hub list — a new run may be on a
	# different filter, so the ten biggest games are re-asked rather than reused.
	hub_games.clear()
	shops.clear()
	active_curses.clear()
	pending_chests = 0
	pending_chest_choices.clear()
	pending_combat_statuses.clear()
	pending_ambush = ""
	pending_spawn_enemies.clear()
	pending_enemy_buff.clear()
	pending_enemy_start_stun.clear()
	pending_fire_damage_all = 0
	note_for_yourself_card = &""
	Notifications.clear()
	phase = Phase.MENU

# Texture for the player marker in action / tactical combat. Prefers the
# character's small `icon`, falling back to the full `portrait`. Null when no
# character is selected (callers draw their default token instead).
func player_icon_texture() -> Texture2D:
	var cd: CharacterData = Data.get_character(character_id)
	if cd == null:
		return null
	return cd.icon if cd.icon != null else cd.portrait

# Single-letter marker for the ASCII overworld (the roguelike strategy floor):
# the first letter of the character's name, uppercased. Falls back to "@".
func player_initial() -> String:
	var cd: CharacterData = Data.get_character(character_id)
	if cd != null and String(cd.display_name) != "":
		return String(cd.display_name).substr(0, 1).to_upper()
	return "@"

# Games-first redesign (2.0) run-start loadout applier. The no-combat rework has
# no deck / energy / combat stats — a character brings only a tiny Health and the
# verb/consumable counts (docs/games-first-redesign.md §3), plus its starting
# items. Health / Max Health reuse hp / max_hp; the verbs map onto their same-
# named fields (Dash -> dash_charges). Starting items are acquired through the
# normal add_item path so pickups (Hollow Heart, Lunch, …) fire their
# item_acquired effects. Callers should reset_run() first (GameLoop2.start_run
# does), so this only sets the loadout, not the whole run.
func apply_character2(char_data: CharacterData) -> void:
	if char_data == null:
		return
	character_id = char_data.id
	max_hp = maxi(1, char_data.base_max_hp)
	hp = max_hp
	shields = 0
	bonus_shields = 0
	# The run's whole starting purse (§14) — gold never carries between runs, so
	# there is nothing else for this to add to. Set BEFORE the starting items, so
	# an item that reads gold on pickup sees what the run actually opens holding.
	set_gold(char_data.start_gold)
	bash = char_data.start_bash
	dash_charges = char_data.start_dash
	push = char_data.start_push
	transmute = char_data.start_transmute
	scramble = char_data.start_scramble
	bombs = char_data.start_bombs
	keys = char_data.start_keys
	# …then whatever the character brings UNROLLED (the sheet's Random column).
	# Done before the starting items so an item that reads a verb count on pickup
	# sees the loadout the run actually opens on. The roll is announced on both
	# channels: a loadout that differs run to run is the whole point of the
	# column, and a silent one just looks like the character screen lying.
	var rolled: Dictionary = roll_start_random(char_data.start_random)
	if not rolled.is_empty():
		var msg: String = "%s's random loadout: %s." % [
			char_data.display_name, describe_start_random(rolled)]
		Notifications.notify(msg, Color(1.0, 0.80, 0.40))
		GameLog.add(msg, Color(1.0, 0.80, 0.40))

	inventory.clear()
	_reset_item_tracking()
	for item_id in char_data.starting_items:
		add_item(Data.get_item2(item_id))
	# Pickups may have raised Max Health; open the run at the new full pool.
	hp = max_hp
	emit_signal("stats_changed")
	emit_signal("hp_changed", hp, max_hp)
	emit_signal("inventory_changed")

# The 2.0 verbs a character's Random points can land on. Keys is a verb on the
# sheet but there is nothing in the build for a key to open yet, so it is left
# out — a run that rolled its whole random loadout into Keys would open on
# nothing at all.
const START_RANDOM_POOL := ["bash", "dash", "push", "transmute", "scramble", "bombs"]

# Spend `points` of unrolled starting loadout across START_RANDOM_POOL, one
# independent roll each (so two points may land on the same verb). Returns the
# roll as a verb -> amount dictionary, which is what the character screens and
# the run log say out loud — a loadout that differs run to run has to be
# ANNOUNCED, or it reads as the numbers being wrong.
func roll_start_random(points: int) -> Dictionary:
	var rolled: Dictionary = {}
	for _i in range(maxi(0, points)):
		var verb: String = START_RANDOM_POOL[randi() % START_RANDOM_POOL.size()]
		var field: String = String(_LEVEL_UP_ABILITY_FIELDS.get(verb, verb))
		set(field, int(get(field)) + 1)
		rolled[verb] = int(rolled.get(verb, 0)) + 1
	return rolled

# "+2 Bash, +1 Dash" for a roll_start_random() result, in pool order so the same
# roll always reads the same way. "" when nothing was rolled.
func describe_start_random(rolled: Dictionary) -> String:
	var parts: Array = []
	for verb in START_RANDOM_POOL:
		var n: int = int(rolled.get(verb, 0))
		if n > 0:
			parts.append("+%d %s" % [n, _pretty_stat(verb)])
	return ", ".join(parts)

# Clears the bookkeeping that tracks item-granted bonuses and instance ids.
# Shared by reset_run() and apply_character() so the two can't drift apart.
func _reset_item_tracking() -> void:
	item_stat_bonus = {}
	_applied_item_max_hp = 0
	_applied_item_max_energy = 0
	_applied_item_verbs = {}
	_applied_scaling_max_hp = 0
	max_hp_cap = -1
	_next_item_instance_id = 1
	_gold_spent_accum = 0
	incremental_attacks_total = 0
	incremental_attacks_turn = 0
	incremental_turn_pulses = 0
	incremental_turn = 0
	incremental_hp_losses = 0
	incremental_discards_turn = 0
	pen_nib_double_active = false
	_streaks.clear()
	dead_eye_streak = 0

# === Incremental-item counter API ===
# Called from ItemTriggers.fire so every combat mode keeps the same counters.

# A player Attack was played (deckbuilder card, action-loop card, strategy
# ability). Bumps the run-wide and per-turn attack tallies.
func incremental_on_attack() -> void:
	incremental_attacks_total += 1
	incremental_attacks_turn += 1

# A discrete turn / combat room began: remember its number for if_turn-gated
# one-shots (room-based in Action). Does NOT touch the recurring per-turn
# window — that rides turn_tick so it can be timer-based in Action.
func incremental_on_turn_started(turn_no: int) -> void:
	incremental_turn = turn_no
	pen_nib_double_active = false

# The recurring turn heartbeat fired (once per turn in deckbuilder/strategy; on
# the real-time turn-tick timer in Action). Advances Happy Flower's "turns"
# count and resets the per-turn attack window (Ornamental Fan / Shuriken).
func incremental_on_turn_tick() -> void:
	incremental_turn_pulses += 1
	incremental_attacks_turn = 0
	incremental_discards_turn = 0

# A fresh combat began: per-combat counters restart; the run-wide attack
# total carries over.
func incremental_on_combat_started() -> void:
	incremental_turn = 0
	incremental_turn_pulses = 0
	incremental_attacks_turn = 0
	incremental_hp_losses = 0
	incremental_discards_turn = 0
	pen_nib_double_active = false
	streak_clear()

# A card was discarded by an EFFECT this turn (Acrobatics' pick, All-Out
# Attack's random toss, Storm of Steel's hand dump). Called from the scenes'
# discard paths — never from the end-of-turn hand sweep, which isn't "you
# Discarded a Card this turn". Feeds Eviscerate's cost_reduce_from.
func incremental_on_discard() -> void:
	incremental_discards_turn += 1

# One "time you lost Health this combat" (Blood for Blood's discount).
# Deckbuilder/action player HP funnels through change_hp, which reports here;
# strategy battles damage the player UNIT directly (GameState.hp syncs at
# battle end), so BattleView reports its player HP losses explicitly.
func incremental_on_player_hp_loss() -> void:
	incremental_hp_losses += 1

# Current value of a named counter, used by the `counter` effect handler and
# the Backpack progress badge.
func incremental_value(key: String) -> int:
	match key:
		"attacks_total":
			return incremental_attacks_total
		"attacks_this_turn":
			return incremental_attacks_turn
		"turns":
			return incremental_turn_pulses
		"hp_losses":
			return incremental_hp_losses
		"discards_this_turn":
			return incremental_discards_turn
	return 0

# === Streak API (Dead Eye) ===
# Shared by every combat mode through EffectSystem's streak_hit / streak_reset
# handlers and each scene's attack path. A landed player attack grows the
# streak against the hit target; switching targets or whiffing resets it; the
# streak's count is folded into outgoing player attacks vs the same target.

# A landed player attack grows the named streak. Switching targets resets the
# count first (the bonus only rewards staying on one enemy), then this hit
# counts as 1.
func streak_register_hit(key: String, target, attack_bonus: bool, label: String) -> void:
	if key == "" or target == null:
		return
	var s: Dictionary = _streaks.get(key, {"count": 0, "target": null})
	if s.get("target") != target:
		s["count"] = 0
	s["target"] = target
	s["attack_bonus"] = attack_bonus
	s["label"] = label
	s["count"] = int(s.get("count", 0)) + 1
	_streaks[key] = s
	_sync_dead_eye_streak()

# A whiff (Blind) or target switch wipes the named streak entirely.
func streak_reset(key: String) -> void:
	if key == "":
		return
	_streaks.erase(key)
	_sync_dead_eye_streak()

# Sum every attack_bonus streak currently locked onto `target`, to fold into an
# outgoing attack. Logs the exact bonus so the player sees what just landed.
func streak_attack_bonus(target) -> int:
	if _streaks.is_empty() or target == null:
		return 0
	var bonus: int = 0
	for key in _streaks:
		var s: Dictionary = _streaks[key]
		if not bool(s.get("attack_bonus", false)) or s.get("target") != target:
			continue
		var n: int = int(s.get("count", 0))
		if n <= 0:
			continue
		bonus += n
		var label: String = String(s.get("label", ""))
		if label == "":
			label = String(key)
		GameLog.add("%s: +%d Dmg (streak %d)!" % [label, n, n], Color(0.7, 1.0, 0.7))
	return bonus

func streak_clear() -> void:
	_streaks.clear()
	dead_eye_streak = 0

func _sync_dead_eye_streak() -> void:
	var s: Dictionary = _streaks.get("dead_eye", {})
	dead_eye_streak = int(s.get("count", 0))

func set_current_game(id: StringName) -> void:
	# Record the game we're leaving so the map's journey trail can show where the
	# player has been (mirrors the old web build's gameState.visitedGames). The
	# first placement (current_game_id == "") and no-op re-sets add nothing.
	if current_game_id != &"" and current_game_id != id and not visited_games.has(current_game_id):
		visited_games.append(current_game_id)
	# The walk, repeats and all (see path_taken). Written on ARRIVAL rather than on
	# departure, so the game under the player's feet is always the last entry and
	# the strip that draws it needs no "…and here" fix-up on the end.
	if id != &"" and current_game_id != id:
		path_taken.append(id)
	current_game_id = id
	# Arriving at the game you pinned to route through spends the pin: the detour
	# is done, and the road on from here is just the road.
	if route_waypoint == id:
		route_waypoint = &""
	emit_signal("current_game_changed", id)

# Records that the player BEAT `game_id` this run and reports whether that was a
# REPEAT — a game already on `beaten_games`. Revisiting is legal (the offering is
# drawn from the neighbours of wherever you stand, so a game can come back
# around), and beating one again is worth a Dash (see Overworld2.report).
func note_game_beaten(game_id: StringName) -> bool:
	if game_id == &"":
		return false
	total_games_beaten += 1
	if beaten_games.has(game_id):
		return true
	beaten_games.append(game_id)
	return false

# True once `game_id` has been beaten at least once this run.
func has_beaten_game(game_id: StringName) -> bool:
	return beaten_games.has(game_id)

# Records that the run PLAYED `game_id` and reports whether it had played it
# before. Called for every report — a missed goal and a walk-out are both games
# you went and played.
func note_game_played(game_id: StringName) -> bool:
	if game_id == &"":
		return false
	if played_games.has(game_id):
		return true
	played_games.append(game_id)
	return false

# True once the run has played `game_id` at all — so the offering can flag it as
# a return, and its Dash bonus, before the player commits.
#
# PLAYED, not beaten. Going back to a game you failed is the same journey back as
# going to one you cleared, and the Dash is paid for making it: what has to be
# earned on the return trip is the goal, not the trip.
func has_played_game(game_id: StringName) -> bool:
	return played_games.has(game_id)

# THE ROAD WALKED, oldest stop first and ending on the game under the player's
# feet — one implementation, because four screens draw this same picture (the
# header strip, the end-of-run verdict, Run History's saved runs, the Atlas) and
# a run that reads as five stops in one place and seven in another is a bug in
# whichever of them the player looked at second.
#
# REPEATS INCLUDED. `path_taken` is the walk; the fall-back below rebuilds the
# best road available from `visited_games` for a save written before the walk was
# recorded, which necessarily has the repeats already dropped.
func walked_path() -> Array[StringName]:
	if not path_taken.is_empty():
		return path_taken.duplicate()
	var out: Array[StringName] = []
	for id in visited_games:
		out.append(StringName(id))
	if current_game_id != &"" and (out.is_empty() or out[out.size() - 1] != current_game_id):
		out.append(current_game_id)
	return out

func set_max_hp(new_max: int, heal_to_full: bool = false) -> void:
	# Routes through Stats so Constitution auto-gain fires off the
	# delta. Pass heal_to_full=true to restore HP to the new max
	# (e.g., on level-up). Otherwise current HP is just clamped.
	var old_max: int = max_hp
	var capped_max: int = new_max
	if max_hp_cap >= 0:
		capped_max = mini(capped_max, max_hp_cap)
	max_hp = max(1, capped_max)
	if heal_to_full:
		hp = max_hp
	else:
		hp = mini(hp, max_hp)
	Stats.note_max_hp_change(max_hp, old_max)
	emit_signal("hp_changed", hp, max_hp)
	# SCALING items keyed off max_hp (Beefy Ring) need a refresh whenever
	# the pool moves outside of the inventory-recompute path. Guarded by
	# old_max != max_hp so a no-op set doesn't churn the cache.
	if old_max != max_hp:
		_recompute_item_bonuses()

func change_max_hp(delta: int) -> void:
	set_max_hp(max_hp + delta)

func set_hp(new_hp: int) -> void:
	hp = clamp(new_hp, 0, max_hp)
	emit_signal("hp_changed", hp, max_hp)

# `source` names WHAT took the Health, and is passed through to the health_lost
# ctx. Almost nothing needs it — Piggy Bank pays on any loss, which is what
# "whenever" means — but the destructible trinkets (§8.1) break only on an enemy
# attack, and a signal that says "Health went down by 2" cannot tell a swing from
# the bill an event just handed you. HEALTH_SOURCE_ENEMY_ATTACK is the only tag
# with a rule behind it today; the default of "" reads as "some other drain".
const HEALTH_SOURCE_ENEMY_ATTACK := "enemy_attack"
# Damage a STATUS charged (Burn's 3 at the end of a game it went unpaid, §13). It
# resolves on the battlefield like a swing — the tries absorb it, the player's own
# statuses scale it — but nothing swung it, so the destructible trinkets (§8.1)
# survive a burn. A relic that breaks "when an enemy hits you" should not be
# destroyed by a bill the player ran up themselves.
const HEALTH_SOURCE_STATUS := "status"

func change_hp(delta: int, source: String = "") -> void:
	# Each in-combat HP loss is one "time you lost Health this combat" for
	# Blood for Blood's discount — deckbuilder/action player HP loss (enemy
	# hits, DoT ticks, self-damage cards) funnels through here. Gated on a
	# live combat scene so event/overworld drains never count.
	if delta < 0 and combat_scene != null:
		incremental_on_player_hp_loss()
	var before: int = hp
	set_hp(hp + delta)
	# "You lost Health" (Piggy Bank, §8.1) — fired on what ACTUALLY came off,
	# not on what was asked for, so a 5-point drain against 2 Health left is one
	# loss of 2 and a drain against 0 is no event at all. Every Health loss in
	# the run funnels through here (an enemy swing's overflow past the Shields,
	# the Health a failed try costs, an event's bill, IV Bag), which is why the
	# hook lives at this choke point rather than on the battlefield: the relic
	# says "whenever", and the overworld is a place Health is lost too.
	if hp < before:
		TriggerBus.health_lost.emit({"amount": before - hp, "source": source})

func set_gold(new_gold: int) -> void:
	gold = max(0, new_gold)
	emit_signal("gold_changed", gold)

func change_gold(delta: int) -> void:
	set_gold(gold + delta)

# Gold-on-hit rider (King Bomber evolution): an attack effect carrying
# gold_on_hit_min/max grants a random amount in that range when it connects with
# an enemy. Shared by all three combat modes so the roll + log live in one place.
# `rng` lets each mode pass its seeded generator; null falls back to a global one.
var _gold_on_hit_rng: RandomNumberGenerator = null
func gain_gold_on_hit(effect: Dictionary, rng: RandomNumberGenerator = null) -> void:
	var hi: int = int(effect.get("gold_on_hit_max", 0))
	if hi <= 0:
		return
	var lo: int = int(effect.get("gold_on_hit_min", 0))
	if lo > hi:
		lo = hi
	var r: RandomNumberGenerator = rng
	if r == null:
		if _gold_on_hit_rng == null:
			_gold_on_hit_rng = RandomNumberGenerator.new()
			_gold_on_hit_rng.randomize()
		r = _gold_on_hit_rng
	var amt: int = r.randi_range(maxi(0, lo), hi)
	if amt <= 0:
		return
	change_gold(amt)
	GameLog.add("Gold on hit: +%d Gold." % amt, Color(1.0, 0.85, 0.35))

# Gold the player actively SPENDS (shop purchases, card removal, …). Deducts
# and counts toward Keeper's Sack. Use this — NOT change_gold — wherever the
# player chooses to pay: gold lost to events / curses must not count as
# "spending."
func spend_gold(amount: int) -> void:
	if amount <= 0:
		return
	change_gold(-amount)
	_track_gold_spent(amount)

# Keeper's Sack: accumulate gold spent and grant +1 to a random core stat for
# every `gold_spend_stat_per` gold crossed. Cumulative so small spends add up.
var _gold_spent_accum: int = 0

func _track_gold_spent(amount: int) -> void:
	var per: int = _gold_spend_stat_per()
	if per <= 0 or amount <= 0:
		return
	@warning_ignore("integer_division")
	var before: int = _gold_spent_accum / per
	_gold_spent_accum += amount
	@warning_ignore("integer_division")
	var after: int = _gold_spent_accum / per
	var gains: int = after - before
	if gains > 0:
		apply_level_up_stats({"random": gains})
		Notifications.notify("Keeper's Sack: +%d random stat!" % gains, Color(1.0, 0.85, 0.3))

# Smallest positive gold-spend threshold among owned items (Keeper's Sack: 10).
# 0 when no such item is owned.
func _gold_spend_stat_per() -> int:
	var best: int = 0
	for item in inventory:
		if item is ItemData and item.gold_spend_stat_per > 0:
			if best == 0 or item.gold_spend_stat_per < best:
				best = item.gold_spend_stat_per
	return best

# Combined Little Knife multiplier: the player's attacks deal this much extra
# to lower-HP targets. 1.0 when no such item is owned. Read by resolve_damage.
func lower_hp_damage_mult() -> float:
	var mult: float = 1.0
	for item in inventory:
		if item is ItemData and item.lower_hp_damage_mult > 1.0:
			mult *= item.lower_hp_damage_mult
	return mult

func is_dead() -> bool:
	return hp <= 0

# ---------------------------------------------------------------------------
# Level-up
# ---------------------------------------------------------------------------

# Core stats that live as direct GameState fields and can be levelled.
const _LEVEL_UP_DIRECT_STATS := [
	"strength", "dexterity", "intelligence", "charisma",
	"constitution", "luck", "speed",
]
# Ability keys that map onto a differently-named run-scope field.
const _LEVEL_UP_ABILITY_FIELDS := {
	"dash": "dash_charges",
	"reroll": "reroll_charges",
	"fov": "fov_bonus",
	"discovery": "discovery",
	# Games-first (2.0) verbs — map onto same-named GameState fields so both the
	# level-up reward path (apply_level_up_stats) and item grants (grant_run_stat)
	# route "+1 Transmute" etc. correctly (docs/games-first-redesign.md §3.1/§4).
	"bash": "bash",
	"push": "push",
	"transmute": "transmute",
	"scramble": "scramble",
	"bombs": "bombs",
	"keys": "keys",
	# Shields are the per-game tries (§3). "block" is kept as an alias so item
	# Effect columns authored against the old name still land on the right field.
	"shields": "shields",
	"block": "shields",
	# The pool that does not expire (§4.3). Its own field rather than an alias of
	# `shields`, because the two differ in exactly the way that matters: one dies
	# with the game that granted it and one does not.
	"bonus_shields": "bonus_shields",
	# "+1 Game Choices" widens the overworld offering past its base 3 cards (§7).
	"game_choices": "game_choice_bonus",
}
# Stats eligible for the "random" allocation bucket.
const _LEVEL_UP_RANDOM_POOL := ["strength", "dexterity", "intelligence", "charisma"]

# Applies a level-up stat block (see CharacterData.level_up_stats). Returns a
# list of human-readable "+N Stat" strings for logging / notifications. Stat
# changes emit stats_changed; max_hp routes through set_max_hp and heals the
# new pool so a level-up always feels like a full top-up of the gained HP.
func apply_level_up_stats(stats: Dictionary) -> Array:
	var applied: Array = []
	var touched: bool = false
	for stat in _LEVEL_UP_DIRECT_STATS:
		var v: int = int(stats.get(stat, 0))
		if v != 0:
			if v > 0:
				v += stat_gain_bonus_for(stat)  # Snowball amplifies positive gains
			set(stat, int(get(stat)) + v)
			applied.append("+%d %s" % [v, _pretty_stat(stat)])
			touched = true
	for key in _LEVEL_UP_ABILITY_FIELDS.keys():
		var av: int = int(stats.get(key, 0))
		if av != 0:
			var field: String = _LEVEL_UP_ABILITY_FIELDS[key]
			set(field, int(get(field)) + av)
			applied.append("+%d %s" % [av, _pretty_stat(key)])
			touched = true
	var hp_gain: int = int(stats.get("max_hp", 0))
	if hp_gain != 0:
		change_max_hp(hp_gain)
		change_hp(hp_gain)
		applied.append("+%d Max HP" % hp_gain)
	# Gold gets its own branch rather than a row in _LEVEL_UP_ABILITY_FIELDS: that
	# loop writes its field with set(), and gold has to go through change_gold so
	# gold_changed fires and the purse on screen keeps up.
	var gold_gain: int = int(stats.get("gold", 0))
	if gold_gain != 0:
		change_gold(gold_gain)
		applied.append("+%d Gold" % gold_gain)
	var random_n: int = int(stats.get("random", 0))
	for _i in range(maxi(0, random_n)):
		var pick: String = _LEVEL_UP_RANDOM_POOL[randi() % _LEVEL_UP_RANDOM_POOL.size()]
		var amt: int = 1 + stat_gain_bonus_for(pick)  # Snowball amplifies the pick
		set(pick, int(get(pick)) + amt)
		applied.append("+%d %s (random)" % [amt, _pretty_stat(pick)])
		touched = true
	if touched:
		emit_signal("stats_changed")
	return applied

# ONE LEVEL, paid in full: the level counter, the character's stat block, and the
# character's own reward type. Returns apply_level_up_stats' "+N Stat" strings.
#
# THE CONDITION IS NOT CONSULTED HERE. Whether a level was EARNED is the caller's
# question — Overworld2 asks it when a game is reported, and Potion of Raise Level
# does not ask it at all (potions-design §7.3, decision #7). That is the whole
# point of the split: a Rare potion pays the run's biggest single reward by firing
# the ordinary path rather than by inventing a payout of its own, and it can only
# do that if the payout is reachable without the condition attached to it.
#
# It also does not roll a BONUS level. Chaining is Overworld2's rule about earning
# several at once, not part of what one level is worth.
func grant_level_up(rng: RandomNumberGenerator = null) -> Array:
	var ch: CharacterData = Data.get_character2(character_id)
	if ch == null:
		return []
	player_level += 1
	var applied: Array = apply_level_up_stats(ch.level_up_stats)
	match String(ch.level_up_reward_type):
		"item", "chest":
			# A sized chest (Zagreus' Large -> 3) carries its own choice count; an
			# unsized one passes 0 and takes the screen's default.
			grant_chest(maxi(1, ch.level_up_reward_amount),
				maxi(0, ch.level_up_reward_chest_choices))
		"random_sized_chest":
			# Vampire Survivors characters: the chest's SIZE is rolled instead of
			# fixed — Small..Huge on the same odds as every other rarity draw.
			var r: RandomNumberGenerator = rng
			if r == null:
				r = RandomNumberGenerator.new()
				r.randomize()
			grant_chest(maxi(1, ch.level_up_reward_amount), Data.roll_chest_size_choices(r))
		"scroll":
			add_loot("scroll", maxi(1, ch.level_up_reward_amount))
		_:
			pass
	return applied

# A run verb's value WITHOUT the contribution owned items currently make to it.
# This is what a save stores, exactly like max_hp: the load restores the base and
# then _recompute_item_bonuses re-applies the item bonuses, so a passive in the pack
# can't add its +1 Bash again on every save/load round-trip. Aliased stat names
# ("shields" / "block" both being the shields field) are summed once per FIELD, so
# an item declaring either is accounted for exactly once.
func base_verb_value(stat: String) -> int:
	var field: String = _LEVEL_UP_ABILITY_FIELDS.get(stat, stat)
	var applied: int = 0
	for verb in _ITEM_VERB_STATS:
		if String(_LEVEL_UP_ABILITY_FIELDS.get(verb, verb)) == field:
			applied += int(_applied_item_verbs.get(verb, 0))
	return int(get(field)) - applied

func _pretty_stat(stat: String) -> String:
	# "block" is the legacy authoring name for the per-game pool, and `shields` is
	# its field name — both of them are what the player reads as TEMPORARY SHIELDS
	# (§3.2). `bonus_shields` is the pool that stays, and is simply Shields.
	if stat == "block" or stat == "shields":
		return TEMP_SHIELD_NAME + "s"
	if stat == "bonus_shields":
		return SHIELD_NAME + "s"
	return stat.capitalize()

# Alien Baby: extra Health every goal-enemy spawns with — i.e. how many EXTRA
# goal completions it takes to defeat one (docs/games-first-redesign.md §8).
# Summed across owned items' stat_bonuses["enemy_health"] so copies stack.
func enemy_health_bonus() -> int:
	var bonus: int = 0
	for it in inventory:
		if it is ItemData and not it.stat_bonuses.is_empty():
			bonus += int(it.stat_bonuses.get("enemy_health", 0))
	if equipped_weapon is ItemData and not equipped_weapon.stat_bonuses.is_empty():
		bonus += int(equipped_weapon.stat_bonuses.get("enemy_health", 0))
	return bonus

# Snowball: total flat bonus owned items add whenever the player gains a
# permanent point of `stat`. Summed across the inventory so duplicate Snowballs
# stack. 0 for the common no-amplifier case.
func stat_gain_bonus_for(stat: String) -> int:
	var bonus: int = 0
	for it in inventory:
		if it is ItemData and not it.stat_gain_bonus.is_empty():
			bonus += int(it.stat_gain_bonus.get(stat, 0))
	return bonus

# Permanent run-scope stat grant used by the `gain_stat` effect (Secret
# Technique Instructions: +1 Dash on a perfected game). Resolves ability stats
# (dash/reroll/fov/discovery) to their backing field, applies Snowball-style
# amplifiers to positive gains, and broadcasts the change.
# The LIVE value of a board verb by its stat name — the read to grant_run_stat's
# write, resolving "dash" to dash_charges through the same field map so the two
# can't disagree about where a verb lives. Unlike base_verb_value this is the
# number the run actually has, item bonuses folded in.
func verb_value(stat: String) -> int:
	var field: String = _LEVEL_UP_ABILITY_FIELDS.get(stat, stat)
	var v: Variant = get(field)
	return int(v) if v != null else 0

func grant_run_stat(stat: String, value: int) -> void:
	if value == 0:
		return
	var amt: int = value
	if value > 0:
		amt += stat_gain_bonus_for(stat)
	var field: String = _LEVEL_UP_ABILITY_FIELDS.get(stat, stat)
	set(field, int(get(field)) + amt)
	emit_signal("stats_changed")

# ---------------------------------------------------------------------------
# Statuses 2.0 on the PLAYER (§13)
#
# Stacks are INTENSITY, not duration: applying Marked twice is one Marked at 2,
# which is why every call here adds into the existing count instead of appending.
# A status may author a CEILING on that (Burn's "Max: 3") and apply_status is where
# the player's side of it is enforced.
# An id with no StatusData behind it is refused rather than stored — a status the
# catalog can't describe would show up on the checklist as a blank goal.
# ---------------------------------------------------------------------------

# Add `stacks` of `status_id` to the player. Returns the new stack count (0 when
# the id is unknown). A negative `stacks` ticks it down, same as remove_status.
#
# `games` > 0 makes the application TEMPORARY (§5.4 of docs/potions-design.md): it
# becomes a row in the timed layer instead of permanent stacks, and expires whole
# after that many games are resolved. The default of 0 is permanent, so every
# existing caller means exactly what it always meant.
func apply_status(status_id: StringName, stacks: int = 1, games: int = 0) -> int:
	if stacks == 0:
		return status_stacks(status_id)
	var status: StatusData = Data.get_status(status_id)
	if status == null:
		push_warning("GameState.apply_status: no status '%s' in the catalog" % status_id)
		return 0
	# A timed application is a new row rather than an addition to an old one: two
	# potions drunk before one game are two clocks, and each has to be able to run
	# out on its own. Only a GAIN can be timed — a negative `stacks` is a decay and
	# goes down the permanent path, where remove_status spends the timed rows first.
	if games > 0 and stacks > 0:
		timed_statuses.append({
			"id": status_id, "stacks": stacks, "games": games, "shield": 0,
		})
		player_statuses_changed.emit()
		return status_stacks(status_id)
	var total: int = int(player_statuses.get(status_id, 0)) + stacks
	# The authored ceiling (Burn's "Max: 3"), applied on the way UP only: a status
	# already over its cap — from a save written before the cap, or from a cap the
	# sheet lowered — still ticks down normally rather than being frozen there.
	if stacks > 0:
		total = maxi(int(player_statuses.get(status_id, 0)), status.cap_stacks(total))
	if total <= 0:
		player_statuses.erase(status_id)
		total = 0
	else:
		player_statuses[status_id] = total
	player_statuses_changed.emit()
	return status_stacks(status_id)

# Tick `stacks` off a player status (default 1), removing it at zero. Returns what
# is left. This is the decay path for a decaying side completed this game.
#
# THE TIMED ROWS GO FIRST, soonest expiry first — a stack that is leaving anyway is
# the one to spend on a decay, and taking the permanent one instead would let a
# borrowed status quietly eat a status the run actually owns.
func remove_status(status_id: StringName, stacks: int = 1) -> int:
	var left: int = absi(stacks)
	for row in _timed_rows_for(status_id):
		if left <= 0:
			break
		var take: int = mini(left, int(row["stacks"]))
		row["stacks"] = int(row["stacks"]) - take
		left -= take
	_prune_timed()
	if left > 0 and player_statuses.has(status_id):
		return apply_status(status_id, -left)
	player_statuses_changed.emit()
	return status_stacks(status_id)

# Permanent + timed, which is what every status question about the player means.
#
# THE CEILING IS APPLIED TO WHAT THE TIMED LAYER ADDS, never to the permanent
# count underneath it. Burn's "Max: 3" is a rule about the way UP (§13.1): stacks
# already over it — from a save written before the cap, or a cap the sheet lowered
# — tick down one at a time rather than being frozen there, and a read that
# clamped them would freeze exactly the case the permanent path is careful about.
# So a borrowed stack cannot lift a status past its cap, and cannot lower it
# either.
func status_stacks(status_id: StringName) -> int:
	var permanent: int = int(player_statuses.get(status_id, 0))
	var total: int = permanent
	for row in timed_statuses:
		if StringName(row.get("id", &"")) == status_id:
			total += int(row.get("stacks", 0))
	if total <= permanent:
		return maxi(0, total)
	var status: StatusData = Data.get_status(status_id)
	return maxi(permanent, status.cap_stacks(total)) if status != null else total

# The stacks of `status_id` that are NOT going anywhere. The wording rules read
# this: a clause is only "this game only" when nothing permanent is holding it up
# (§5.3).
func permanent_stacks(status_id: StringName) -> int:
	return int(player_statuses.get(status_id, 0))

# How many games until this status leaves the player entirely — 0 for one that is
# not going anywhere (no timed rows, or permanent stacks underneath it), otherwise
# the soonest row's clock. This is the number the goal line and the pip quote.
func status_games_left(status_id: StringName) -> int:
	if int(player_statuses.get(status_id, 0)) > 0:
		return 0
	var soonest: int = 0
	for row in timed_statuses:
		if StringName(row.get("id", &"")) != status_id:
			continue
		var games: int = int(row.get("games", 0))
		if games > 0 and (soonest == 0 or games < soonest):
			soonest = games
	return soonest

# Every status on the player as id -> effective stacks. The dictionary the two
# aggregate readers (status_list, combat_totals) work from, so neither of them has
# to know the timed layer exists.
func effective_statuses() -> Dictionary:
	var out: Dictionary = {}
	for id in player_statuses.keys():
		out[id] = status_stacks(id)
	for row in timed_statuses:
		var id: StringName = StringName(row.get("id", &""))
		if id != &"" and not out.has(id):
			out[id] = status_stacks(id)
	return out

# The timed rows carrying `status_id`, soonest expiry first.
func _timed_rows_for(status_id: StringName) -> Array:
	var rows: Array = timed_statuses.filter(
		func(r): return StringName(r.get("id", &"")) == status_id)
	rows.sort_custom(func(a, b): return int(a.get("games", 0)) < int(b.get("games", 0)))
	return rows

# Drop the rows a decay emptied. Rows are dictionaries held by reference, so the
# subtraction above lands on the real ones and this only clears the husks.
func _prune_timed() -> void:
	timed_statuses = timed_statuses.filter(func(r): return int(r.get("stacks", 0)) > 0)

# One game has been resolved: tick every timed row down and drop what ran out.
# Returns the dropped rows so the caller can report them — `GameLoop2.beat_game`
# does, beside the tiles that went out in the same pass (§17).
func tick_timed_statuses() -> Array:
	var expired: Array = []
	var kept: Array = []
	for row in timed_statuses:
		row["games"] = int(row.get("games", 0)) - 1
		if int(row["games"]) <= 0:
			expired.append(row)
		else:
			kept.append(row)
	timed_statuses = kept
	if not expired.is_empty():
		player_statuses_changed.emit()
	return expired

func has_status(status_id: StringName) -> bool:
	return status_stacks(status_id) > 0

# Every status on the player as [{status: StatusData, stacks: int}], in catalog
# order so the HUD strip and the checklist don't reshuffle between frames the way
# a raw Dictionary iteration would. Statuses whose resource has gone missing are
# skipped rather than yielding a null row.
func status_list() -> Array:
	var held: Dictionary = effective_statuses()
	var out: Array = []
	for s in Data.all_statuses():
		var sd: StatusData = s
		if held.has(sd.id):
			# `games` rides every row so the surfaces that draw one — the checklist,
			# the hero's pips, the HUD chip — can say it is temporary without each
			# of them going back to the timed layer to ask (§5.3).
			out.append({"status": sd, "stacks": int(held[sd.id]),
				"games": status_games_left(sd.id)})
	return out

# The statuses whose PLAYER side is claimable — a `goal` or a `bonus` (§13). These
# are the extra checklist rows, each paying its own reward when ticked. Selected on
# the side's MODE, not on Buff/Debuff: what a side does is what the sheet says it
# does, and nothing stops a debuff from offering the player a way to earn.
func status_objectives() -> Array:
	var out: Array = []
	for row in status_list():
		if (row["status"] as StatusData).is_claimable(StatusData.PLAYER):
			out.append(row)
	return out

# What the player's statuses add up to IN COMBAT (§13.4) — the other half of the
# status mechanic, the half that moves a number instead of a goal.
#
# Most statuses contribute nothing here: `StatusData.enemy_only` is set on every
# buff, because Strength on the player would want a player attack to sit on and
# this game has none. What comes through is the DEBUFFS, which are felt by whoever
# is carrying them — Marked doubles the damage the player takes and takes it past
# their Shields, exactly as it does on an enemy. Same aggregator either side, so
# the two can't drift.
func combat_totals() -> Dictionary:
	return StatusData.combat_totals(effective_statuses(), StatusData.PLAYER)

# The statuses whose PLAYER side is a `clause` — the requirements that get ANDed
# onto every enemy's goal.
func status_clauses() -> Array:
	var out: Array = []
	for row in status_list():
		if (row["status"] as StatusData).is_clause(StatusData.PLAYER):
			out.append(row)
	return out

# Save blob for the player's statuses: plain String -> int, JSON-safe.
# --- event goals / curse goals: the run-scope API ---------------------------

# Take on an event goal. `games` is the window in games played; 0 or less reads
# as one game, since a goal with no window is a goal you can never meet.
func add_event_goal(event_id: StringName, condition: String, games: int,
		effects: Array, effects_text: String) -> void:
	event_goals.append({
		"event": event_id,
		"condition": condition,
		"games_left": maxi(1, games),
		"effects": effects.duplicate(true),
		"effects_text": effects_text,
	})
	event_goals_changed.emit()

# Take on a curse. `games` of 0 means "use the curse's own Timer", so re-tuning
# the curse re-tunes every event that hands it out. An unknown id is refused
# rather than stored — a curse the catalog can't describe is a blank purple row.
func add_curse_goal(curse_id: StringName, event_id: StringName = &"", games: int = 0) -> bool:
	var cd: CurseData2 = Data.get_curse2(curse_id)
	if cd == null:
		push_warning("GameState.add_curse_goal: unknown curse '%s'" % curse_id)
		return false
	# -1 is PERMANENT, and it is what a curse with a Timer of 0 (the sheet's `N/A`)
	# becomes. The sign is the whole distinction: tick_event_goals decrements a
	# positive window and leaves a negative one alone, so nothing has to go back to
	# the catalogue to find out whether this row can ever clear.
	var window: int = games if games > 0 else cd.timer
	curse_goals.append({
		"curse": curse_id,
		"event": event_id,
		"games_left": -1 if window <= 0 else window,
	})
	event_goals_changed.emit()
	return true

func has_curse_goal(curse_id: StringName) -> bool:
	for c in curse_goals:
		if StringName(c.get("curse", &"")) == curse_id:
			return true
	return false

# The player ticked an event goal on the checklist: pay it and retire it.
# Returns the goal that was claimed, or {} when the index is stale.
func claim_event_goal(index: int) -> Dictionary:
	if index < 0 or index >= event_goals.size():
		return {}
	var goal: Dictionary = event_goals[index]
	event_goals.remove_at(index)
	for eff in goal.get("effects", []):
		EffectSystem.apply(eff, {})
	event_goals_changed.emit()
	return goal

# The player admitted doing the cursed thing: pay the penalty. The curse STAYS —
# that is what separates it from an event goal. Only the timer clears it.
func trigger_curse_goal(index: int) -> Dictionary:
	if index < 0 or index >= curse_goals.size():
		return {}
	var entry: Dictionary = curse_goals[index]
	var cd: CurseData2 = Data.get_curse2(StringName(entry.get("curse", &"")))
	if cd == null:
		return {}
	for eff in cd.penalty:
		EffectSystem.apply(eff, {})
	event_goals_changed.emit()
	return entry

# Lift a curse off the run early — Scroll of Remove Curse (potions-design §10.1).
# Returns the row that came off, or {} when the index is stale.
#
# THE LIST HAD NO WAY OFF IT BUT THE CLOCK. add / has / trigger / tick were the
# whole API, and `trigger` is the opposite of this one: it pays the bill and leaves
# the curse standing, because meeting a curse's condition is not how you are rid of
# it. Removal is a thing an effect does TO the list, and nothing could do it.
#
# Its best target is the one row that never leaves on its own: Curse of the Bell's
# Timer is N/A, which add_curse_goal stores as games_left = -1. Everything else
# clears itself in three games, and a scroll that hurries that along is a fair Rare;
# a scroll that can lift the permanent one is the reason it exists.
#
# NOT remove_active_curse (above) — that is the shelved curse CARD system and it
# operates on a different list. Same word, different thing (CurseData2).
func remove_curse_goal(index: int) -> Dictionary:
	if index < 0 or index >= curse_goals.size():
		return {}
	var entry: Dictionary = curse_goals[index]
	curse_goals.remove_at(index)
	event_goals_changed.emit()
	return entry

# One game has been played. Ticks both lists and drops whatever ran out.
# Returns the EXPIRED event goals so the caller can print their "missed" line —
# expired curses need no announcement, since nothing happened.
func tick_event_goals() -> Array:
	var expired: Array = []
	var kept: Array = []
	for goal in event_goals:
		goal["games_left"] = int(goal.get("games_left", 0)) - 1
		if int(goal["games_left"]) <= 0:
			expired.append(goal)
		else:
			kept.append(goal)
	event_goals = kept
	var kept_curses: Array = []
	for c in curse_goals:
		# A permanent curse (games_left < 0) neither counts down nor comes off.
		if int(c.get("games_left", 0)) < 0:
			kept_curses.append(c)
			continue
		c["games_left"] = int(c.get("games_left", 0)) - 1
		if int(c["games_left"]) > 0:
			kept_curses.append(c)
	curse_goals = kept_curses
	event_goals_changed.emit()
	return expired

func serialize_event_goals() -> Dictionary:
	return {
		"goals": event_goals.duplicate(true),
		"curses": curse_goals.duplicate(true),
		"fired": events_fired.duplicate(true),
		# The bag has to ride the save or a reload would re-offer an event the run
		# had already spent, which is the one thing the bag exists to prevent.
		"seen": events_seen.keys(),
		"last": String(last_event_id),
		"nodes": event_nodes_fired.keys(),
		"objects": ObjectSystem.to_save(),
	}

func restore_event_goals(data: Dictionary) -> void:
	event_goals.clear()
	curse_goals.clear()
	events_fired.clear()
	events_seen.clear()
	event_nodes_fired.clear()
	for g in data.get("goals", []):
		if g is Dictionary:
			event_goals.append(g.duplicate(true))
	for c in data.get("curses", []):
		if c is Dictionary:
			curse_goals.append(c.duplicate(true))
	for k in data.get("fired", {}).keys():
		events_fired[StringName(k)] = int(data["fired"][k])
	for k in data.get("seen", []):
		events_seen[StringName(k)] = true
	for k in data.get("nodes", []):
		event_nodes_fired[StringName(k)] = true
	last_event_id = StringName(data.get("last", ""))
	ObjectSystem.from_save(data.get("objects", {}))

# --- shops (§14) -----------------------------------------------------------
#
# The frozen hub list and every shop's shelf, as JSON-safe data. Both have to
# ride the save: re-deriving the hubs on load would re-ask a graph that may have
# been rebuilt since, and re-rolling the stock would hand a player who reloaded a
# different shop from the one they walked out of.

func serialize_shops() -> Dictionary:
	var hubs: Array = []
	for gid in hub_games:
		hubs.append(String(gid))
	var shelves: Dictionary = {}
	for gid in shops.keys():
		shelves[String(gid)] = (shops[gid] as Dictionary).duplicate(true)
	return {"hubs": hubs, "shops": shelves}

func restore_shops(data: Dictionary) -> void:
	hub_games.clear()
	shops.clear()
	for raw in data.get("hubs", []):
		hub_games.append(StringName(raw))
	var shelves: Dictionary = data.get("shops", {})
	for key in shelves.keys():
		var shelf = shelves[key]
		if shelf is Dictionary:
			shops[StringName(key)] = (shelf as Dictionary).duplicate(true)
	event_goals_changed.emit()

func serialize_statuses() -> Dictionary:
	var out: Dictionary = {}
	for id in player_statuses.keys():
		out[String(id)] = int(player_statuses[id])
	return out

# Restore from that blob. Ids the catalog no longer knows are DROPPED rather than
# restored as blank goals — the same call a stale enemy id gets in GameLoop2.
func restore_statuses(data: Dictionary) -> void:
	player_statuses.clear()
	for key in data.keys():
		var id := StringName(key)
		var stacks: int = int(data[key])
		if stacks > 0 and Data.get_status(id) != null:
			player_statuses[id] = stacks
	player_statuses_changed.emit()

# The TIMED layer's own blob (§5.4 of docs/potions-design.md), as a list rather
# than a dict: two rows can carry the same status id on two different clocks, so
# there is no key to hold them apart. A row whose status the catalog no longer
# knows is dropped, like the permanent ones above.
func serialize_timed_statuses() -> Array:
	var out: Array = []
	for row in timed_statuses:
		out.append({
			"id": String(row.get("id", "")),
			"stacks": int(row.get("stacks", 0)),
			"games": int(row.get("games", 0)),
			"shield": int(row.get("shield", 0)),
		})
	return out

func restore_timed_statuses(rows) -> void:
	timed_statuses.clear()
	if not (rows is Array):
		return
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var id := StringName(raw.get("id", ""))
		var stacks: int = int(raw.get("stacks", 0))
		var games: int = int(raw.get("games", 0))
		if stacks <= 0 or games <= 0 or Data.get_status(id) == null:
			continue
		timed_statuses.append({
			"id": id, "stacks": stacks, "games": games,
			"shield": int(raw.get("shield", 0)),
		})
	player_statuses_changed.emit()

# --- the undo snapshot (§3) ------------------------------------------------
#
# What a lost run's ENEMY TURN can reach, captured and put back as one — the undo
# behind GameLoop2's attempt tracker, which cannot refund a turn the way it
# refunds a shield (see GameLoop2._run_snapshot for the whole of that argument).
#
# The board itself is GameLoop2's; this is the run RESOURCES half: the Health a
# swing took, the purse losing it minted (Piggy Bank), both shield pools, the
# chests a trigger banked on the way through, the player's own statuses, and the
# inventory the hit may have thinned (the trinkets that shatter on an enemy
# attack, §8.1).
#
# The inventory is held by REFERENCE. add_item mints a distinct copy per slot, so
# the array is the pack: putting the same objects back is putting the same items
# back, with their charges and instance ids intact, and _recompute_item_bonuses
# re-derives everything they were contributing to the run's numbers.
func snapshot_run_resources() -> Dictionary:
	return {
		"hp": hp,
		# The BASE ceiling, with what the pack is contributing subtracted out —
		# exactly as a save writes it (SaveSystem._build_payload), and for the same
		# reason: the restore below re-derives the pack's share, and a stored total
		# would be that share counted twice.
		"base_max_hp": max_hp - _applied_item_max_hp - _applied_scaling_max_hp,
		"gold": gold,
		"shields": shields,
		"bonus_shields": bonus_shields,
		"pending_chests": pending_chests,
		"pending_chest_choices": pending_chest_choices.duplicate(),
		"statuses": serialize_statuses(),
		"inventory": inventory.duplicate(),
	}

# Put one back. Through the setters where there is one (set_hp, set_gold) so the
# HUD hears about it — an undo that leaves the Health line reading the number the
# hit took it to would be worse than no undo at all.
func restore_run_resources(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	# The ceiling, put back as base + WHAT THE PACK IS CURRENTLY CONTRIBUTING, so
	# that _recompute_item_bonuses below — which works in deltas against those same
	# applied totals — lands on base + what the RESTORED pack contributes.
	max_hp = maxi(1, int(snap.get("base_max_hp",
		max_hp - _applied_item_max_hp - _applied_scaling_max_hp))
		+ _applied_item_max_hp + _applied_scaling_max_hp)
	shields = maxi(0, int(snap.get("shields", shields)))
	bonus_shields = maxi(0, int(snap.get("bonus_shields", bonus_shields)))
	pending_chests = maxi(0, int(snap.get("pending_chests", pending_chests)))
	pending_chest_choices.clear()
	for choices in snap.get("pending_chest_choices", []):
		pending_chest_choices.append(int(choices))
	restore_statuses(snap.get("statuses", {}))
	inventory = (snap.get("inventory", inventory) as Array).duplicate()
	# The bonuses the pack contributes are DERIVED, never stored, so they are
	# re-derived rather than snapshotted: a broken trinket that comes back has to
	# come back with whatever it was granting.
	_recompute_item_bonuses()
	inventory_changed.emit()
	# Health last: max_hp and the item bonuses above are what it is clamped
	# against, so a pack that was carrying +Max Health has to be back on before the
	# number it raised is written.
	set_hp(int(snap.get("hp", hp)))
	set_gold(int(snap.get("gold", gold)))

# Whether the pack already holds an item of this id. Ownership is by ID, not by
# instance: add_item duplicates the .tres template into the slot, so the copies
# are distinct Resources that share the id they were minted from. The shops ask
# this to prefer stocking something the player hasn't got (ShopSystem._draw_one).
func has_item(item_id: StringName) -> bool:
	if item_id == &"":
		return false
	for it in inventory:
		if it is ItemData and it.id == item_id:
			return true
	return equipped_weapon is ItemData and equipped_weapon.id == item_id

# How many relics in the pack a random draw could also have produced — the ones
# the Relic Trader will take, the ones a swap may hand back. Starter, Boss and
# Event relics are none of those (ItemData.is_rollable), so an event that gates on
# "five relics" is asking about five he would actually touch rather than about the
# size of the pack.
func tradeable_relic_count() -> int:
	var n: int = 0
	for it in inventory:
		if it is ItemData and it.is_rollable():
			n += 1
	return n

# Sacred Orb: true while any owned item rerolls low-rarity item drops.
func has_low_rarity_reroll() -> bool:
	for it in inventory:
		if it is ItemData and it.reroll_low_rarity:
			return true
	return false

# True while any owned item sets the named ItemData bool. The games-first run-loop
# flags (keep_shields / bomb_stun / bomb_cardinal) change a RULE rather than move
# a number, so GameLoop2 reads them off the inventory instead of firing effects.
func _any_item_flag(field: String) -> bool:
	for it in inventory:
		if it is ItemData and bool(it.get(field)):
			return true
	return false

# Barricade: the Temporary Shields a resolved game left standing become ordinary
# Shields (§4.3) — the pool that stays — instead of expiring with the game that
# granted them.
func banks_shields() -> bool:
	return _any_item_flag("bank_shields")

# Lucky Foot: a Negative pill rerolls into a random Positive one (§4.3).
func pills_reroll_positive() -> bool:
	return _any_item_flag("pills_positive")

# Echo Chamber: how many previously-used pieces of loot a use ALSO fires (§4.3),
# or 0 while nothing in the pack echoes. The DEEPEST copy wins rather than the
# sum: two Echo Chambers are the same three-loot memory read twice over, and
# adding them would make the second copy quietly the strongest relic in the game.
func loot_echo_depth() -> int:
	var depth: int = 0
	for it in inventory:
		if it is ItemData:
			depth = maxi(depth, int(it.echo_loot))
	return depth

# Sticky Bombs: whatever a bomb hits and fails to destroy is stunned (§4.1).
func bombs_stun() -> bool:
	return _any_item_flag("bomb_stun")

# Brimstone Bombs: a bomb blasts down the target's whole row and column (§4).
func bombs_cardinal() -> bool:
	return _any_item_flag("bomb_cardinal")

# Hot Bombs: the TILE EFFECT a bomb's blast leaves on every cell it covered (§17),
# or &"" while nothing in the pack does that. An id rather than a bool, so the
# blast lays what the item names; the FIRST one owned wins, since two items each
# wanting to leave different ground behind is a content question rather than a
# runtime one, and stacking them would silently double the ground a bomb hands
# out. Read by GameLoop2._explode — so it reaches a Landmine going off too.
func bomb_tile() -> StringName:
	for it in inventory:
		if it is ItemData and StringName(it.bomb_tile) != &"":
			return StringName(it.bomb_tile)
	return &""

# Mine-r Construction: how many columns AND rows the battlefield has grown by
# (§7.3). This one counts rather than answering a bool — the grid is a number,
# so a second copy is a second column and a second lane. GameLoop2.grid_cols /
# grid_rows add it to their base.
func grid_growth() -> int:
	var n: int = 0
	for it in inventory:
		if it is ItemData and it.grid_grow:
			n += 1
	return n

# Philosophers Stone / Runic Dome: how many extra COLUMNS the battlefield has,
# on top of grid_growth's columns-and-rows (§7.3). Length without width: more
# ground to cross, and no extra lane — so the front line still holds grid_rows()
# attackers and the column is bought purely as time.
func grid_length_growth() -> int:
	var n: int = 0
	for it in inventory:
		if it is ItemData and it.grid_length_grow:
			n += 1
	return n

# Runic Dome: whether the enemy behind an OFFERED game is hidden until the game
# is committed to (§7.1). One copy is enough — you cannot be more blind than
# blind — so this answers a bool where the two above count.
func hides_upcoming_enemies() -> bool:
	return _any_item_flag("hide_spawns")

# Philosophers Stone: the statuses every newly spawned enemy arrives carrying, as
# id -> stacks (§13.4). Summed across copies, so two Stones mean +2 Strength on
# each body rather than the second one doing nothing.
func spawn_statuses() -> Dictionary:
	var out: Dictionary = {}
	for it in inventory:
		if not (it is ItemData) or (it as ItemData).spawn_statuses.is_empty():
			continue
		for id in (it as ItemData).spawn_statuses.keys():
			var key := StringName(id)
			out[key] = int(out.get(key, 0)) + int((it as ItemData).spawn_statuses[id])
	return out

# Sacred Bark: what every loot consumable resolves at. MULTIPLIES the copies
# together — "double the effect" applied twice is quadruple, not double — and
# returns 1 when nothing owned changes it, so callers can multiply unconditionally.
func loot_multiplier() -> int:
	var mult: int = 1
	for it in inventory:
		if it is ItemData and it.loot_multiplier > 1:
			mult *= it.loot_multiplier
	return mult

# Golden Idol: the extra Gold every defeated enemy pays on top of its drop (§14).
# SUMS the copies, because this one is an amount rather than a rate.
func enemy_gold_bonus() -> int:
	var n: int = 0
	for it in inventory:
		if it is ItemData:
			n += it.gold_per_enemy
	return n

# Lord's Parasol: walking into a shop empties its shelf into the pack (§14).
func sweeps_shops() -> bool:
	return _any_item_flag("shop_sweep")

# There's Options: extra chest POINTS on a boss's drop (§8.2). SUMS the copies,
# like enemy_gold_bonus — a second one is a second rung, not a second doubling.
# 0 when nothing owned changes it, which leaves a boss dropping the Small chest
# every body drops.
func boss_chest_bonus() -> int:
	var n: int = 0
	for it in inventory:
		if it is ItemData:
			n += it.boss_chest_bonus
	return n

# ---------------------------------------------------------------------------
# Usable consumables + temporary buffs
# ---------------------------------------------------------------------------

# Combat scenes register themselves here at start (and clear at end) so the
# global backpack / action active-slot can fire a pill's effects into the
# live fight without holding a direct reference to the scene.
func set_combat_context(scene, player) -> void:
	combat_scene = scene
	combat_player = player

func clear_combat_context() -> void:
	combat_scene = null
	combat_player = null

# The overworld scene registers itself while the map is up so overworld_usable
# items can route their item_used effect to it (Winged Boots' map jump).
func set_overworld_context(scene) -> void:
	overworld_scene = scene

func clear_overworld_context(scene = null) -> void:
	# Guarded clear: only wipe if the caller is the scene we hold (or no scene
	# given), so a freshly-spawned Overworld registering before the old one's
	# _exit_tree fires can't be clobbered.
	if scene == null or overworld_scene == scene:
		overworld_scene = null

# A USABLE item may only be fired in combat or while an event roll is open.
# ("Pill" used to be this file's word for a USABLE consumable item, from the
# combat era. It means the §4.3 loot consumable now — a different thing entirely,
# which is not an item and is not fired through here — so the old jargon is gone
# from the two comments that still carried it.)
func can_use_items() -> bool:
	return combat_scene != null or event_active

# Whether `item` can be fired right now. USABLE items need a combat/event
# context; CHARGED actives only need a full bar and can be popped from any
# screen (combat, backpack, a reward screen).
func can_fire_item(item: ItemData) -> bool:
	if item == null or inventory.find(item) == -1:
		return false
	if item.is_charged():
		return item.is_fully_charged()
	if item.kind == ItemData.ItemKind.USABLE:
		# Overworld actives (Winged Boots) fire only on the map — never in combat,
		# where their effect would no-op and waste a use. Ordinary USABLE items are
		# the inverse: combat/event only.
		if item.overworld_usable:
			return overworld_scene != null
		return can_use_items()
	return false

# Whether the OVERWORLD is mounted and able to act on a loot effect that needs it.
#
# This used to be the gate on reading a scroll at all — scrolls were an
# overworld-only consumable, on the reasoning that Teleportation only makes sense
# there and the rest carry over into whatever comes next. That is no longer the
# rule (§4.3): every piece of loot can be spent whenever the player wants it, and
# the one op that genuinely needs the map — a teleport — FIZZLES instead of being
# refused, which is a better answer than a Use button that will not press.
#
# What is left is the question `Overworld2.loot_teleport` and the overworld actives
# ask: is there a map here to move on. Kept under its old name because that is what
# it has always meant underneath.
func can_use_scrolls() -> bool:
	return overworld_scene != null

# Activates a USABLE consumable OR a CHARGED active from inventory: fires its
# item_used triggers through EffectSystem (routed into the live combat scene
# when one is registered, else scene-less). A USABLE spends a use and is dropped
# when depleted; a CHARGED active empties its bar to recharge. Returns true if
# the item fired.
func use_item(item: ItemData, target = null) -> bool:
	if not can_fire_item(item):
		return false
	# `target` is the enemy chosen via the targeting arrow for items that aim at
	# an enemy (ItemData.wants_target). Self-aimed effects still route to the
	# source, so a null target just keeps the old self-only behaviour.
	# Off the map combat_scene is null; an overworld active routes its effect to
	# the registered overworld scene instead so it can open its map UI.
	var on_overworld: bool = combat_scene == null and item.overworld_usable and overworld_scene != null
	var ctx := {
		"source": combat_player,
		"target": target if target != null else combat_player,
		"scene": overworld_scene if on_overworld else combat_scene,
		"card": null,
		"item": item,
	}
	for trig in item.triggers:
		if String(trig.get("on", "")) != "item_used":
			continue
		EffectSystem.apply_all(trig.get("effects", []), ctx)
	# Surface the activation as a toast so the outcome of using an item is always
	# visible (individual effects may add their own specific `notify` on top, e.g.
	# Wooden Nickel's "+N gold").
	Notifications.notify("Used %s" % item.display_name, Color(0.8, 0.95, 1.0))
	TriggerBus.emit_signal("item_used", {"item": item})
	if item.is_charged():
		# Empty the bar; it refills via the charging hooks.
		item.current_charge = 0
	elif on_overworld:
		# Deferred: an overworld active opens an async, cancellable picker; the
		# Overworld spends the use (consume_item_use) only once the player commits,
		# so cancelling — or finding nowhere to go — wastes nothing.
		pass
	else:
		consume_item_use(item)
	_recompute_item_bonuses()
	emit_signal("inventory_changed")
	return true

# Spends one USABLE charge and drops the item when depleted (clearing the action
# slot if it pointed at the final copy). max_uses == -1 is infinite (no-op). Split
# out of use_item so deferred overworld actives can spend on commit. Refreshes
# bonuses + inventory listeners since the inventory may have changed.
func consume_item_use(item: ItemData) -> void:
	if item == null or item.max_uses <= 0:
		return
	item.max_uses -= 1
	if item.max_uses <= 0:
		if action_active_item_id == item.id and _count_items(item.id) <= 1:
			action_active_item_id = &""
		inventory.erase(item)
		# A spent item leaves for the same reasons any other does, so it gives
		# back its passive statuses too — this is the one removal path that does
		# not go through remove_item_at.
		_apply_status_bonuses(item, -1)
	_recompute_item_bonuses()
	emit_signal("inventory_changed")

# ---------------------------------------------------------------------------
# Charged-item charging. Items never declare cadence; these are called from the
# central hooks: combat_ended (all modes, +1 to every charged item) and the
# per-turn handlers (deckbuilder = all; action = the equipped active slot only).
# ---------------------------------------------------------------------------

# Adds `amount` charge to every charged item, clamped to each item's cost.
func charge_all_items(amount: int = 1) -> void:
	if amount == 0:
		return
	var changed: bool = false
	for it in inventory:
		if it is ItemData and it.is_charged():
			changed = _charge_item(it, amount) or changed
	if changed:
		emit_signal("inventory_changed")

# Adds charge to the (first) charged item matching `id` — Action's single active
# slot tops up only its equipped item per turn.
func charge_item_by_id(id: StringName, amount: int = 1) -> void:
	if id == &"" or amount == 0:
		return
	for it in inventory:
		if it is ItemData and it.id == id and it.is_charged():
			if _charge_item(it, amount):
				emit_signal("inventory_changed")
			return

# Every relic in the pack that runs on charges — 48 Hour Energy's targets (§4.3).
# The carried copies, not the templates, since what a charge lands on is a bar
# that exists.
func chargeable_items() -> Array:
	return inventory.filter(func(it): return it is ItemData and it.is_charged())

# Public front for _charge_item: tops one relic's bar up by `amount` and reports
# whether the bar actually moved, so a caller can tell "charged it" from "it was
# already full" and say the right thing.
func charge_item(it: ItemData, amount: int) -> bool:
	if not (it is ItemData) or not it.is_charged() or amount == 0:
		return false
	var moved: bool = _charge_item(it, amount)
	if moved:
		emit_signal("inventory_changed")
	return moved

# Clamps one item's bar; returns true if its fill actually moved.
func _charge_item(it: ItemData, amount: int) -> bool:
	var before: int = it.current_charge
	it.current_charge = clampi(it.current_charge + amount, 0, it.max_charge())
	return it.current_charge != before

func _count_items(id: StringName) -> int:
	var n: int = 0
	for it in inventory:
		if it is ItemData and it.id == id:
			n += 1
	return n

# Adds to the temporary stat layer that Stats.get_value() folds in. Used by
# the `temp_stat` effect; cleared at the combat/room/event boundary.
func add_temp_stat(stat: StringName, amount: int) -> void:
	if amount == 0:
		return
	var key := String(stat)
	temp_stat_bonus[key] = int(temp_stat_bonus.get(key, 0)) + amount
	emit_signal("stats_changed")

func add_event_block(amount: int) -> void:
	event_block = maxi(0, event_block + amount)

# Drains event_block against incoming event damage, returning the HP loss
# left after the shield soaks what it can.
func absorb_event_damage(amount: int) -> int:
	if amount <= 0 or event_block <= 0:
		return maxi(0, amount)
	var soaked: int = mini(event_block, amount)
	event_block -= soaked
	return amount - soaked

# Wipes consumable buffs. Called at combat end (deckbuilder/strategy), on
# leaving a room (action), and when an event closes.
func clear_temp_buffs() -> void:
	if temp_stat_bonus.is_empty() and event_block == 0:
		return
	temp_stat_bonus.clear()
	event_block = 0
	emit_signal("stats_changed")

# ---------------------------------------------------------------------------
# Inventory mutation — every add goes through here so each entry is its
# own duplicated Resource. Two copies of the same item never share state,
# which lets the upgrade/downgrade mechanic (and any future per-item
# interaction) target a single slot without leaking into the others.
# ---------------------------------------------------------------------------

func add_item(template: ItemData) -> ItemData:
	# `template` is the shared Resource loaded from .tres. We duplicate
	# deeply so triggers/tags/stat_bonuses can never alias between slots.
	# Weapon items also append their linked CardInstance to the deck
	# with source_weapon_id set, sealing the bidirectional pair.
	if template == null:
		return null
	var inst: ItemData = _append_item_internal(template, 0)
	# Charged actives start full (Isaac-style) unless the item opts out.
	if inst.is_charged():
		inst.current_charge = inst.max_charge() if inst.starts_charged else 0
	# An incremental relic counts from zero, whenever in the run it is taken —
	# the template's counter is a schema default and never a tally, but a copy
	# minted from a duplicated INSTANCE (Duplicator, the dev panel) would inherit
	# one, so the slot is zeroed here rather than trusted.
	inst.counter_value = 0
	# Curse of Decay: a passive item obtained while it's active has a chance
	# to arrive already downgraded. Holding it twice rolls twice, independently.
	if inst.kind == ItemData.ItemKind.PASSIVE:
		var hits: int = 0
		for decay in active_affliction_effects("item_downgrade_chance"):
			if randi() % 100 < int(decay.get("percent", 50)):
				hits += 1
		if hits > 0:
			inst.upgrade_level -= hits
			Notifications.notify(
				"%s arrived decayed%s." % [inst.display_name, (" x%d" % hits) if hits > 1 else ""],
				Color(0.7, 0.55, 0.4))
	# Snapshot the run resources BEFORE anything the pickup does lands, so the
	# pickup can REPORT what it changed. An item's payload is its passive
	# stat_bonuses (a passive +1 Bash, folded in by the recompute below) plus its
	# item_acquired effects (Lunch: +2 Max Health, +2 Health) — both used to land
	# silently, so the numbers moved with nothing saying so, which reads as "the
	# item did nothing".
	var before: Dictionary = run_resource_snapshot()
	_recompute_item_bonuses()
	# The status half of the passive grant, put up alongside the stat bonuses the
	# recompute just folded in, and for the same reason: it is held UP by the
	# slot. remove_item_at takes it back down.
	_apply_status_bonuses(inst, 1)
	# Fire item_acquired triggers AFTER the inventory + stat recompute so
	# the pickup hook sees the new max_hp (Lunch's +8 HP lands on top of
	# the +8 Max HP its stat_bonuses just contributed). Scene-less — only
	# handlers that don't need a combat scene (gain_hp, gain_gold, …) are
	# valid here.
	for trig in inst.triggers:
		if String(trig.get("on", "")) != "item_acquired":
			continue
		for effect in trig.get("effects", []):
			EffectSystem.apply(effect, {
				"source": null, "target": null, "scene": null, "card": null,
			})
	# Everything the pickup moved — passive stat_bonuses and item_acquired effects
	# alike — in one player-facing line.
	var gained: String = describe_resource_gains(before)
	if gained != "":
		Notifications.notify("%s: %s" % [inst.display_name, gained], Color(0.7, 1.0, 0.7))
		GameLog.add("%s: %s" % [inst.display_name, gained], Color(0.7, 1.0, 0.7))
	TriggerBus.emit_signal("item_acquired", {"item": inst})
	emit_signal("inventory_changed")
	return inst

# The run resources a pickup / effect can move, as one flat dictionary. Paired
# with describe_resource_gains to turn "an item was acquired" into "+2 Max
# Health, +2 Health" without every item having to author a `notify` string.
# Keyed by the player-facing name, in HUD order.
func run_resource_snapshot() -> Dictionary:
	return {
		"Health": hp, "Max Health": max_hp, "Shields": shields,
		"Bash": bash, "Dash": dash_charges, "Push": push,
		"Transmute": transmute, "Scramble": scramble, "Bombs": bombs,
		"Keys": keys, "Chests": pending_chests, "Gold": gold,
	}

# Human-readable diff between `before` (from run_resource_snapshot) and now,
# e.g. "+2 Max Health, +2 Health". Empty when nothing moved.
func describe_resource_gains(before: Dictionary) -> String:
	var parts: Array = []
	var now: Dictionary = run_resource_snapshot()
	for key in now.keys():
		var delta: int = int(now[key]) - int(before.get(key, now[key]))
		if delta != 0:
			parts.append("%s%d %s" % ["+" if delta > 0 else "", delta, key])
	return ", ".join(parts)

# Total bonus stacks any owned status-amplify item adds when `status_id` is
# inflicted on an enemy (Empty Syringe -> +1 Bleed / Poison). Called from
# CombatActor.add_status so it works across every combat mode.
func status_amplify_bonus(status_id: StringName) -> int:
	var key: String = String(status_id)
	var bonus: int = 0
	for item in inventory:
		if item is ItemData and not item.status_amplify.is_empty():
			bonus += int(item.status_amplify.get(key, 0))
	return bonus

# True when an owned item makes the player immune to gaining `status_id` (Ginger
# → "weak", Turnip → "frail"). Called from the player actor's add_status so the
# block lands in every combat mode regardless of where the status came from.
func is_status_immune(status_id: StringName) -> bool:
	var key: String = String(status_id)
	for item in inventory:
		if item is ItemData and not item.status_immunity.is_empty():
			if key in item.status_immunity:
				return true
	return false

# Flat per-hit damage every owned item grants to the player's attacks of the
# given damage_type (Focus Crystal -> +1 melee). Read by Stats.damage_bonus.
func attack_damage_bonus(damage_type: String) -> int:
	var bonus: int = 0
	for item in inventory:
		if item is ItemData and not item.attack_damage_bonus.is_empty():
			bonus += int(item.attack_damage_bonus.get(damage_type, 0))
	return bonus

# True when any owned item carries leftover energy across turns (Ice Cream).
# Combat scenes gate their per-turn energy carry-over on this.
func has_energy_carryover_item() -> bool:
	for item in inventory:
		if item is ItemData and item.carries_leftover_energy:
			return true
	return false

# Paper Bag (and any future mirror item): the pool of stat ids whose maximum
# `stat_id` reads as while owned, merged across every owned item. Empty when no
# item mirrors this stat. Read by Stats.get_value() on every lookup, so the
# derived value tracks temporary buffs live. Weapon slot can't hold a mirror
# item, so inventory is the only source.
func stat_mirror_pool(stat_id: StringName) -> Array:
	var pool: Array = []
	var key := String(stat_id)
	for item in inventory:
		if not (item is ItemData) or item.stat_mirror.is_empty():
			continue
		if not item.stat_mirror.has(key):
			continue
		for s in item.stat_mirror[key]:
			var sn := StringName(s)
			if not pool.has(sn):
				pool.append(sn)
	return pool

func remove_item_at(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var gone: ItemData = inventory[index] as ItemData
	inventory.remove_at(index)
	if gone != null:
		_apply_status_bonuses(gone, -1)
	_recompute_item_bonuses()
	emit_signal("inventory_changed")

# Puts an item's `status_bonuses` up (direction 1) or takes them back down (-1).
# apply_status prunes a stack count that reaches zero, so an item leaving cannot
# leave a hollow entry behind; and because it is additive rather than a set, a
# second copy of the same passive stacks and only its own share comes off when it
# goes. Statuses gained any OTHER way (The Mark's pickup, an event) are untouched
# — the item only ever gives back exactly what it put in.
func _apply_status_bonuses(item: ItemData, direction: int) -> void:
	if item == null or item.status_bonuses.is_empty():
		return
	for key in item.status_bonuses.keys():
		var stacks: int = int(item.status_bonuses[key]) * direction
		if stacks != 0:
			apply_status(StringName(key), stacks)

# Removes a specific owned item instance by reference (Unstable Genome's
# destroy_self). No-op if it isn't in the inventory.
func remove_item(item: ItemData) -> void:
	var idx: int = inventory.find(item)
	if idx >= 0:
		remove_item_at(idx)

# Reactive Trauma Plate: if the player owns a lethal-negating item, destroy one
# copy and report it. Called from Stats.resolve_damage the instant a hit would
# drop the player to 0 HP, so the negation lands in every combat mode.
func consume_lethal_guard() -> bool:
	for i in range(inventory.size()):
		var it = inventory[i]
		if it is ItemData and it.negate_lethal:
			GameLog.add("%s shatters, negating a lethal blow!" % it.display_name,
				Color(1.0, 0.55, 0.35))
			remove_item_at(i)
			return true
	return false

func set_equipped_weapon(template: ItemData) -> void:
	# Same duplication contract as add_item — the equipped weapon also
	# carries per-instance upgrade_level / instance_id so the future
	# weapon-as-equipment flow can pair with its card the same way
	# inventory weapons do.
	if template == null:
		equipped_weapon = null
	else:
		equipped_weapon = template.duplicate(true)
		equipped_weapon.instance_id = _next_item_instance_id
		_next_item_instance_id += 1
	_recompute_item_bonuses()
	emit_signal("inventory_changed")

func _append_item_internal(template: ItemData, upgrade_level: int) -> ItemData:
	# Internal: duplicates and appends without firing the recompute /
	# signal. apply_character batches several adds and recomputes once
	# at the end. Always mints a fresh instance_id so weapon coupling
	# survives even when add_item is bypassed.
	var inst: ItemData = template.duplicate(true)
	inst.upgrade_level = upgrade_level
	inst.instance_id = _next_item_instance_id
	_next_item_instance_id += 1
	inventory.append(inst)
	return inst

# Picks a random Passive (anything with a non-zero non-health stat bonus)
# and bumps its upgrade_level by `delta`. Returns a dict with the chosen
# item and its new level, or null if no eligible item exists. Save the
# loop here for the future "Curse of Decay" / event reward hooks.
func upgrade_random_passive(delta: int) -> Dictionary:
	var eligible: Array = []
	for it in inventory:
		if it is ItemData and it.is_upgradeable_passive():
			eligible.append(it)
	if eligible.is_empty():
		return {}
	var picked: ItemData = eligible[randi() % eligible.size()]
	picked.upgrade_level += delta
	# Recompute already emits stats_changed; we add inventory_changed so
	# HUDs that key off inventory state (passive-bonus tooltips, etc.) refresh.
	_recompute_item_bonuses()
	emit_signal("inventory_changed")
	return {"item": picked, "delta": delta, "new_level": picked.upgrade_level}

# Deck-tag card counting backed the combat `of: "deck_tag:<tag>"` item scaling.
# The deck is gone with the combat cut (§11), so this is always 0 now; kept as a
# stub so the item-scaling recompute below stays valid for any legacy 1.0 item.
func _count_deck_cards_with_tag(_tag: String) -> int:
	return 0

# Applies a delta-tracked, Handcuffs-aware contribution to live max_hp.
# `total` is the nominal (uncapped) running total a source wants to
# contribute this recompute; `applied` is how much of it actually landed on
# live max_hp last time. Returns the new `applied` value. When max_hp_cap
# suppresses part of an increase, the returned value under-reports `total` on
# purpose — that gap is what lets a later cap removal (Handcuffs sold) replay
# the missing delta instead of losing it permanently.
func _apply_capped_max_hp_delta(total: int, applied: int) -> int:
	var delta: int = total - applied
	if delta == 0:
		return applied
	var new_max: int = max_hp + delta
	if max_hp_cap >= 0:
		new_max = mini(new_max, max_hp_cap)
	var actual_delta: int = new_max - max_hp
	max_hp = maxi(1, new_max)
	hp = mini(hp, max_hp)
	emit_signal("hp_changed", hp, max_hp)
	return applied + actual_delta

# Walks inventory + equipped_weapon and rebuilds item_stat_bonus from
# every effective_stat_bonuses() pass. Vitals (max_hp, max_energy) are
# applied as direct deltas — the _applied_item_* fields track our
# running contribution so an upgrade or remove only moves the change.
func _recompute_item_bonuses() -> void:
	var totals: Dictionary = {}
	var max_hp_total: int = 0
	var max_energy_total: int = 0
	var sources: Array = []
	sources.append_array(inventory)
	if equipped_weapon != null:
		sources.append(equipped_weapon)

	# Handcuffs: (re)establish the max_hp ceiling. Snapshotting here (rather
	# than only on acquisition) means a fresh pickup locks in the value it
	# owned at the moment it's added, AND a save load — which restores
	# inventory before this runs — locks in the restored base value the same
	# way. Clearing the moment no capping item remains lets max_hp grow again.
	var has_cap_item: bool = false
	for it in sources:
		if it is ItemData and it.caps_max_hp:
			has_cap_item = true
			break
	if has_cap_item:
		if max_hp_cap < 0:
			max_hp_cap = max_hp
	else:
		max_hp_cap = -1

	for it in sources:
		if not (it is ItemData):
			continue
		var eff: Dictionary = it.effective_stat_bonuses()
		for stat in eff.keys():
			var v: int = int(eff[stat])
			if v == 0:
				continue
			if stat == "max_hp":
				max_hp_total += v
			elif stat == "max_energy":
				max_energy_total += v
			else:
				totals[stat] = int(totals.get(stat, 0) + v)

	# Vitals are applied as direct deltas (NOT through set_max_hp) so we
	# don't trigger Constitution auto-gain on every inventory mutation
	# or save load. Auto-gain stays reserved for level-up-style events.
	_applied_item_max_hp = _apply_capped_max_hp_delta(max_hp_total, _applied_item_max_hp)

	var en_delta: int = max_energy_total - _applied_item_max_energy
	if en_delta != 0:
		max_energy = maxi(0, max_energy + en_delta)
		_applied_item_max_energy = max_energy_total

	# Second pass: SCALING items. Resolved against the post-vitals state so
	# a Beefy Ring + Alien Baby combo sees the bumped max_hp. Non-vital output
	# goes into item_stat_bonus alongside flat bonuses; reads through Stats see
	# both transparently. max_hp output (Jelly) is tracked separately below,
	# through the same capped-delta path as the flat pass above.
	var scaling_max_hp_total: int = 0
	for it in sources:
		if not (it is ItemData) or it.scaling.is_empty():
			continue
		for rule in it.scaling:
			var out_stat: String = String(rule.get("stat", ""))
			var per: int = int(rule.get("per", 0))
			var per_val: int = int(rule.get("value", 0))
			var src_stat: String = String(rule.get("of", ""))
			if out_stat == "" or per <= 0 or per_val == 0 or src_stat == "":
				continue
			if out_stat == "max_energy":
				push_warning("ItemData.scaling: '%s' cannot output max_energy" % it.id)
				continue
			var src_amount: int
			if src_stat.begins_with("deck_tag:"):
				src_amount = _count_deck_cards_with_tag(src_stat.substr(9))
			else:
				src_amount = int(get(src_stat))
			@warning_ignore("integer_division")
			var stacks: int = src_amount / per
			if stacks == 0:
				continue
			var contribution: int = per_val * stacks
			if out_stat == "max_hp":
				scaling_max_hp_total += contribution
			else:
				totals[out_stat] = int(totals.get(out_stat, 0)) + contribution
	_applied_scaling_max_hp = _apply_capped_max_hp_delta(scaling_max_hp_total, _applied_scaling_max_hp)

	item_stat_bonus = totals
	# Passive board-verb bonuses (a passive +1 Bash): fold the delta into the plain
	# GameState verb field and drop the key from item_stat_bonus so it never also
	# double-counts through Stats.get_value.
	for verb in _ITEM_VERB_STATS:
		var desired: int = int(item_stat_bonus.get(verb, 0))
		var applied: int = int(_applied_item_verbs.get(verb, 0))
		if desired != applied:
			var field: String = _LEVEL_UP_ABILITY_FIELDS.get(verb, verb)
			set(field, maxi(0, int(get(field)) + (desired - applied)))
			_applied_item_verbs[verb] = desired
		item_stat_bonus.erase(verb)
	# Cache whether any owned item mirrors a stat onto a pool (Paper Bag), so
	# Stats.get_value can skip the per-read inventory scan in the common case.
	stat_mirror_active = false
	for it in sources:
		if it is ItemData and not it.stat_mirror.is_empty():
			stat_mirror_active = true
			break
	# Rock Bottom: rebuild the union of floored stats so Stats.get_value can
	# gate its high-water clamp on a single bool + dict lookup. high-water
	# marks are NOT cleared here — they persist for the run even if the item
	# is briefly removed and re-added.
	stat_floor_active = false
	stat_floor_stats = {}
	for it in sources:
		if it is ItemData and not it.stat_floor.is_empty():
			stat_floor_active = true
			for s in it.stat_floor:
				stat_floor_stats[String(s)] = true
	# Cricket's Head: rebuild the product of stat multipliers across owned items
	# (copies stack multiplicatively). Stats.get_value applies these last.
	stat_multiplier_active = false
	stat_multiplier = {}
	for it in sources:
		if not (it is ItemData) or it.stat_multipliers.is_empty():
			continue
		stat_multiplier_active = true
		for s in it.stat_multipliers.keys():
			var m: float = float(it.stat_multipliers[s])
			stat_multiplier[String(s)] = float(stat_multiplier.get(String(s), 1.0)) * m
	emit_signal("stats_changed")

# ---------------------------------------------------------------------------
# Loot (scrolls / pills / keys)
# ---------------------------------------------------------------------------

# THE PACK HOLDS NINE (docs/games-first-redesign.md §4.3). Beating a game pays a
# piece of loot and one relic pays four at once, so without a ceiling the window
# that draws them is a list of unbounded height and the drop stops being a
# decision. Nine is a 3x3 grid, which is the shape the window is.
const LOOT_CAPACITY := 9

func loot_is_full() -> bool:
	return loot_items.size() >= LOOT_CAPACITY

# How many more pieces will fit. The drop modal asks with this rather than
# refusing after the fact — "you can't carry this" is an answer the player should
# get before they take it, not a grant that silently evaporates.
func loot_space() -> int:
	return maxi(0, LOOT_CAPACITY - loot_items.size())

func add_loot(kind: String, amount: int = 1) -> void:
	if amount == 0:
		return
	match kind:
		"scroll", "pill", "potion":
			# Each unit becomes a concrete entry (gained unidentified; the owning
			# system resolves identity on use). A negative amount drops that many
			# of the kind instead.
			if amount > 0:
				for _i in range(amount):
					if loot_is_full():
						break
					match kind:
						"scroll":
							_add_random_scroll_loot()
						"pill":
							_add_random_pill_loot()
						_:
							_add_random_potion_loot()
			else:
				_drop_loot_of_type(kind, -amount)
		"loot":
			# The KIND-BLIND grant: beating a game pays "1 loot", and which kind it
			# is a straight 50/50 (§4.3). Rolled per unit, so +2 loot is two coins
			# rather than two of one thing.
			if amount > 0:
				for _i in range(amount):
					if loot_is_full():
						break
					add_loot("scroll" if randi() % 2 == 0 else "pill", 1)
				return
			_drop_loot_of_type("scroll", -amount)
		_:
			if not loot.has(kind):
				push_warning("GameState.add_loot: unknown kind '%s'" % kind)
				return
			loot[kind] = maxi(0, int(loot[kind]) + amount)
	emit_signal("inventory_changed")

func get_loot_count(kind: String) -> int:
	match kind:
		"scroll", "pill", "potion":
			var n: int = 0
			for l in loot_items:
				if l is Dictionary and String(l.get("type", "")) == kind:
					n += 1
			return n
		"loot":
			return loot_items.size()
		_:
			return int(loot.get(kind, 0))

# Concrete scroll loot entries the player is carrying, in pickup order.
func loot_scrolls() -> Array:
	return loot_items.filter(func(l): return l is Dictionary and String(l.get("type", "")) == "scroll")

# The same for pills. Each entry carries its own `horse` flag: the 5% roll happens
# at DROP time and belongs to the piece of loot, not to the pill type, so one
# colour can be held both ways at once (§4.3).
func loot_pills() -> Array:
	return loot_items.filter(func(l): return l is Dictionary and String(l.get("type", "")) == "pill")

# And for potions. No per-entry roll of any kind: a potion's rarity is authored
# and its colour belongs to the run, so the entry carries only what it is.
func loot_potions() -> Array:
	return loot_items.filter(func(l): return l is Dictionary and String(l.get("type", "")) == "potion")

func _add_random_scroll_loot() -> void:
	loot_items.append(roll_loot_entry("scroll"))

func _add_random_pill_loot() -> void:
	var entry: Dictionary = PillSystem.roll_pill_loot()
	if not entry.is_empty():
		loot_items.append(entry)

func _add_random_potion_loot() -> void:
	var entry: Dictionary = PotionSystem.roll_potion_loot()
	if not entry.is_empty():
		loot_items.append(entry)

# Roll one piece of loot WITHOUT granting it. The per-game drop (§4.3) asks before
# it hands anything over — the pack holds nine and the answer is sometimes no — so
# the roll and the taking are two steps rather than one.
#   kind: "scroll" | "pill" | "loot" (the kind-blind 50/50)
func roll_loot_entry(kind: String = "loot") -> Dictionary:
	var want: String = kind
	if want == "loot":
		want = "scroll" if randi() % 2 == 0 else "pill"
	if want == "pill":
		return PillSystem.roll_pill_loot()
	if want == "potion":
		return PotionSystem.roll_potion_loot()
	var s: ScrollData = Data.roll_scroll()
	if s == null:
		# No scrolls loaded — keep the old inert stub so counts/UI don't break.
		return {"type": "scroll", "rarity": "Common"}
	return {"type": "scroll", "id": s.id, "rarity": s.rarity}

# Put a rolled entry in the pack. Refuses once the pack is full rather than
# silently dropping it, so the caller can say so.
func take_loot_entry(entry: Dictionary) -> bool:
	if entry.is_empty() or loot_is_full():
		return false
	loot_items.append(entry.duplicate(true))
	emit_signal("inventory_changed")
	return true

# OFFER `n` pieces of loot rather than granting them (§4.3).
#
# The difference matters because of the cap. `add_loot` pushes pieces in until the
# pack is full and then silently drops the rest, which is fine for a payout of one
# into an empty pack and wrong for everything else: Mom's Coin Purse pays four
# pills at once, Sacred Bark doubles a grant, and a run carrying seven pieces would
# have the surplus vanish without ever being told. The cap is the whole reason
# taking loot is a decision, so a grant that runs into it has to ask.
#
# The pieces are rolled HERE, so what the screen offers is what the run actually
# rolled, and handed over on `loot_offered`. When nothing is listening — a headless
# run, PlaySession2, the tests — it falls back to the direct grant, which keeps
# this a pure state change everywhere there is no UI to ask on.
signal loot_offered(entries: Array)

func offer_loot(kind: String, n: int) -> void:
	if n <= 0:
		return
	if not has_connections("loot_offered"):
		add_loot(kind, n)
		return
	var entries: Array = []
	for _i in range(n):
		var entry: Dictionary = roll_loot_entry(kind)
		if not entry.is_empty():
			entries.append(entry)
	if entries.is_empty():
		return
	loot_offered.emit(entries)

# Take a rolled entry INTO A CHOSEN SLOT of the 3x3 — the drop modal's drag (§4.3).
# The same refusal as `take_loot_entry` when the pack is full, and the piece lands
# in the slot it was dropped on rather than at the end of the array: `slot` is
# WHERE IT GOES, which is the whole point of dragging it somewhere. A slot that is
# taken (or out of range) falls back to the first free one, so a stale payload puts
# the piece in the pack rather than dropping it on the floor.
func take_loot_entry_at(entry: Dictionary, slot: int) -> bool:
	if entry.is_empty() or loot_is_full():
		return false
	var layout: Array = loot_layout()
	var where: int = slot
	if where < 0 or where >= LOOT_CAPACITY or layout[where] != -1:
		where = layout.find(-1)
	if where < 0:
		return false
	_freeze_loot_layout(layout)
	var taken: Dictionary = entry.duplicate(true)
	taken["pack_slot"] = where
	loot_items.append(taken)
	emit_signal("inventory_changed")
	return true

# Grant a SPECIFIC scroll id as loot (DevTools grant). Emits so loot UI refreshes.
func add_scroll_loot(id: StringName) -> void:
	var s: ScrollData = Data.get_scroll(id)
	if s == null:
		return
	loot_items.append({"type": "scroll", "id": s.id, "rarity": s.rarity})
	emit_signal("inventory_changed")

# Grant a SPECIFIC pill id as loot, at whichever dose is asked for (DevTools
# grant). Deliberately NOT capped: a debug grant that silently did nothing when
# the pack was full would read as a broken command.
func add_pill_loot(id: StringName, horse: bool = false) -> void:
	var p: PillData = Data.get_pill(id)
	if p == null:
		return
	loot_items.append({"type": "pill", "id": p.id, "horse": horse})
	emit_signal("inventory_changed")

# And a SPECIFIC potion id, uncapped for the same reason. `ensure_colors` first,
# so a granted bottle has a vial to wear even in a run that has never seen one.
func add_potion_loot(id: StringName) -> void:
	var p: PotionData = Data.get_potion(id)
	if p == null:
		return
	PotionSystem.ensure_colors()
	loot_items.append({"type": "potion", "id": p.id, "rarity": p.rarity})
	emit_signal("inventory_changed")

# ---------------------------------------------------------------------------
# The 3x3 the loot window draws (§4.3)
# ---------------------------------------------------------------------------
#
# WHERE A PIECE SITS AND WHERE IT IS IN THE ARRAY ARE TWO DIFFERENT FACTS. Indices
# into `loot_items` are what `use_loot` and `remove_loot_at` are addressed by and
# they have to stay dense; slots are what the player arranges and they are allowed
# to have holes in them — an arrangement with a gap in the middle is the arrangement
# somebody wanted, and a pack that quietly closed it up was refusing to be tidied.
#
# So the slot rides on the entry as `pack_slot`, and this is the one place the two
# are put back together: slot -> index into `loot_items`, or -1 for a free slot.
#
# A piece with NO slot of its own — anything `add_loot` or a save from before this
# existed put in the pack — takes the lowest free one, in pickup order. That is
# exactly what the dense array used to do, so a run that never drags anything sees
# the pack it always saw.
func loot_layout() -> Array:
	var layout: Array = []
	layout.resize(LOOT_CAPACITY)
	layout.fill(-1)
	var homeless: Array = []
	for i in range(loot_items.size()):
		var entry = loot_items[i]
		var slot: int = int(entry.get("pack_slot", -1)) if entry is Dictionary else -1
		if slot >= 0 and slot < LOOT_CAPACITY and layout[slot] == -1:
			layout[slot] = i
		else:
			homeless.append(i)
	for i in homeless:
		var free: int = layout.find(-1)
		if free < 0:
			break
		layout[free] = i
	return layout

# Which piece is in a slot (index into `loot_items`), or -1 if it is empty.
func loot_index_at_slot(slot: int) -> int:
	if slot < 0 or slot >= LOOT_CAPACITY:
		return -1
	return int(loot_layout()[slot])

# Where the piece at `index` is drawn, or -1 if it isn't carried.
func loot_slot_of(index: int) -> int:
	return int(loot_layout().find(index))

# Write the arrangement the grid is currently DRAWING onto the entries themselves.
# Called before any rearrangement, because a piece that was only implicitly in slot
# 2 (by being third in the array) would otherwise slide the moment something else
# claimed a slot ahead of it — the player would drag one piece and watch two move.
func _freeze_loot_layout(layout: Array) -> void:
	for slot in range(layout.size()):
		var index: int = int(layout[slot])
		if index >= 0 and index < loot_items.size() and loot_items[index] is Dictionary:
			loot_items[index]["pack_slot"] = slot

# Move the piece in slot `from` to slot `to` — the pack grid's drag (§4.3).
#
# ANY SLOT IS A PLACE A PIECE CAN GO. Dropping onto a piece SWAPS the two; dropping
# onto an EMPTY slot puts the piece there and leaves the slot it came from empty,
# wherever in the grid that is. Both arguments are slots in the 3x3, not indices
# into `loot_items` — see `loot_layout`.
#
# Returns whether anything actually moved, so a drag onto a piece's own slot is a
# no-op rather than a redraw.
func move_loot(from: int, to: int) -> bool:
	if from < 0 or from >= LOOT_CAPACITY or to < 0 or to >= LOOT_CAPACITY or from == to:
		return false
	var layout: Array = loot_layout()
	var moving: int = int(layout[from])
	if moving < 0:
		return false
	_freeze_loot_layout(layout)
	var displaced: int = int(layout[to])
	loot_items[moving]["pack_slot"] = to
	if displaced >= 0:
		loot_items[displaced]["pack_slot"] = from
	emit_signal("inventory_changed")
	return true

# Removes the loot entry at `index` (called after a potion is drunk / thrown).
func remove_loot_at(index: int) -> void:
	if index >= 0 and index < loot_items.size():
		loot_items.remove_at(index)
		emit_signal("inventory_changed")

func _drop_loot_of_type(type: String, count: int) -> void:
	for _i in range(count):
		for j in range(loot_items.size() - 1, -1, -1):
			if loot_items[j] is Dictionary and String(loot_items[j].get("type", "")) == type:
				loot_items.remove_at(j)
				break

