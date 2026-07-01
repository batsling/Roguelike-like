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

# === Identity / progression ===
var character_id: StringName = &""
var save_name: String = ""
var current_game_id: StringName = &""
var start_game_id: StringName = &""
var amulet_game_id: StringName = &""
var visited_games: Array[StringName] = []
var beaten_games: Array[StringName] = []
var total_games_beaten: int = 0
# Count of games the player has *played* (entered + resolved, win or
# lose), as opposed to beaten. Drives the difficulty tier — see
# RunDifficulty.gd. The tier steps up every RunDifficulty.GAMES_PER_TIER
# games played.
var games_played: int = 0

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
var gold: int = 99

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
#   * action_active_item_id  — one USABLE consumable (pill), popped with Q.
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
	# Combats-won tally drives the enemy-spawn budget (first fight is gentler).
	if not TriggerBus.combat_ended.is_connected(_on_combat_ended_tally):
		TriggerBus.combat_ended.connect(_on_combat_ended_tally)

func _on_combat_ended_tally(ctx: Dictionary) -> void:
	# Dev test combats are exempt so testing never skews the run's spawn budget.
	if bool(ctx.get("dev", false)):
		return
	if bool(ctx.get("victory", false)):
		total_combats_completed += 1

func _on_game_beaten(_ctx: Dictionary) -> void:
	_tick_card_lifecycles()

func _on_curse_applied(ctx: Dictionary) -> void:
	fire_run_item_triggers("curse_applied", ctx)

func _on_curse_removed(ctx: Dictionary) -> void:
	fire_run_item_triggers("curse_removed", ctx)

func _on_curse_card_removed(ctx: Dictionary) -> void:
	fire_run_item_triggers("curse_card_removed", ctx)

func _on_potion_used(ctx: Dictionary) -> void:
	fire_run_item_triggers("potion_used", ctx)

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

# Number of CURSE-type cards currently in the deck (Greed, Regret, Guilty, …).
func curse_card_count() -> int:
	var n: int = 0
	for ci in deck:
		if ci is CardInstance and ci.data != null and ci.data.type == CardData.CardType.CURSE:
			n += 1
	return n

# Bumps each held curse card's games-beaten counter and drops any that have
# reached their destroy_after_games threshold (Guilty -> 3). Iterates back-to-
# front so removals don't invalidate the index.
func _tick_card_lifecycles() -> void:
	var removed: bool = false
	for i in range(deck.size() - 1, -1, -1):
		var ci = deck[i]
		if not (ci is CardInstance) or ci.data == null or ci.data.destroy_after_games < 0:
			continue
		ci.games_beaten_held += 1
		if ci.games_beaten_held >= ci.data.destroy_after_games:
			var was_curse_card: bool = ci.data.type == CardData.CardType.CURSE
			deck.remove_at(i)
			removed = true
			Notifications.notify("%s crumbled away." % ci.data.display_name,
				Color(0.7, 0.9, 0.7))
			# A curse card aging out of the deck is still "getting rid of a
			# curse card" (Golden Beetle).
			if was_curse_card:
				TriggerBus.emit_signal("curse_card_removed", {"card": ci.data})
	if removed:
		emit_signal("deck_changed")

# Saddles the player with a curse (skipping a game today; events / enemies
# later). Records it in active_curses. The penalty card is NOT granted here — a
# restriction curse drops its card only when the player admits on the
# verification screen that they failed the challenge (see Overworld).
func add_active_curse(curse: CurseData) -> CurseData:
	if curse == null:
		return null
	active_curses.append({"id": curse.id, "name": curse.display_name})
	Notifications.notify("Cursed: %s" % curse.display_name, Color(0.85, 0.6, 0.85))
	TriggerBus.emit_signal("curse_applied", {"curse": curse})
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
# item-choice screen the player opens to pick one item. Counters here bank
# chests that were granted outside the normal post-section reward flow
# (Golden Beetle grants one whenever a curse or curse card is removed); the
# overworld redeems them into RewardScreens when it's idle.
var pending_chests: int = 0

# Grants `count` chests (item rewards). Banks them and announces via
# chest_granted so the overworld can open the item-choice screens.
func grant_chest(count: int = 1) -> void:
	if count <= 0:
		return
	pending_chests += count
	Notifications.notify("Gained %d Chest%s!" % [count, "" if count == 1 else "s"],
		Color(1.0, 0.85, 0.4))
	TriggerBus.emit_signal("chest_granted", {"count": count})

# Consumes one banked chest, returning true if one was available. The overworld
# calls this as it opens each item-reward screen.
func take_pending_chest() -> bool:
	if pending_chests <= 0:
		return false
	pending_chests -= 1
	return true

# The card a curse inflicts when its challenge is failed: its named penalty_card,
# else a random card from the `randomcurse` pool. Null when neither resolves.
func penalty_card_for(curse: CurseData) -> CardData:
	if curse == null:
		return null
	if curse.penalty_card != &"":
		return Data.get_card(curse.penalty_card)
	var pool: Array = []
	for c in Data.all_cards():
		if c is CardData and c.type == CardData.CardType.CURSE and c.tags.has("randomcurse"):
			pool.append(c)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

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

# ---------------------------------------------------------------------------
# Mutation API — UI and combat scenes go through these so signals fire.
# ---------------------------------------------------------------------------

func reset_run() -> void:
	character_id = &""
	save_name = ""
	current_game_id = &""
	start_game_id = &""
	amulet_game_id = &""
	visited_games.clear()
	beaten_games.clear()
	total_games_beaten = 0
	games_played = 0
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
	gold = 99
	deck.clear()
	inventory.clear()
	equipped_weapon = null
	_reset_item_tracking()
	loot = {"key": 0}
	loot_items.clear()
	identified_potion_types.clear()
	identified_scroll_types.clear()
	potion_color_map.clear()
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
	overworld_scene = null
	event_active = false
	dash_charges = 0
	reroll_charges = 0
	fov_bonus = 0
	discovery = 0
	regeneration = 0
	stat_high_water.clear()
	stat_floor_active = false
	stat_floor_stats.clear()
	stat_multiplier_active = false
	stat_multiplier.clear()
	temp_status_stacks.clear()
	active_curses.clear()
	pending_chests = 0
	pending_combat_statuses.clear()
	pending_ambush = ""
	pending_spawn_enemies.clear()
	pending_enemy_buff.clear()
	pending_enemy_start_stun.clear()
	pending_fire_damage_all = 0
	note_for_yourself_card = &""
	Notifications.clear()
	phase = Phase.MENU

# The current character's class card tag (e.g. &"ironclad"), used to scope card
# rewards to that class. Sourced from the character's level_up_card_tag — the
# canonical "cards are drawn from this class" tag — so both level-up and general
# combat rewards draw from the same class pool. Empty = the full reward pool.
func card_reward_tag() -> StringName:
	var cd: CharacterData = Data.get_character(character_id)
	return cd.level_up_card_tag if cd != null else &""

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

func apply_character(char_data: CharacterData) -> void:
	character_id = char_data.id
	max_hp = char_data.base_max_hp
	hp = max_hp
	max_energy = char_data.base_max_energy
	hand_size = char_data.base_hand_size
	strength = char_data.base_strength
	dexterity = char_data.base_dexterity
	intelligence = char_data.base_intelligence
	charisma = char_data.base_charisma
	constitution = char_data.base_constitution
	luck = char_data.base_luck
	speed = char_data.base_speed

	deck.clear()
	for card_id in char_data.starting_deck:
		# Generic basics (strike/defend) resolve to this character's variant
		# (strike_ironclad/…) when one exists. See Data.variant_card_id.
		var c: CardData = Data.get_card_for_character(card_id, char_data.id)
		if c != null:
			deck.append(CardInstance.from_data(c))

	# A run always opens with the character's basic Strike bound to left click,
	# so the player can attack from the very first action-combat room without
	# first visiting the Gear screen. They can still swap it there.
	var strike_card: CardData = Data.get_card_for_character(&"strike", char_data.id)
	if strike_card != null:
		action_left_card_id = strike_card.id

	inventory.clear()
	_reset_item_tracking()
	for item_id in char_data.starting_items:
		var it: ItemData = Data.get_item(item_id)
		if it != null:
			var inst: ItemData = _append_item_internal(it, 0)
			# Starting weapon items grant their card too — apply_character
			# already emits deck_changed at the end so we don't here.
			_grant_weapon_card(inst)

	equipped_weapon = null
	if char_data.starting_weapon != &"":
		var w: ItemData = Data.get_item(char_data.starting_weapon)
		if w != null:
			equipped_weapon = w.duplicate(true)
			equipped_weapon.instance_id = _next_item_instance_id
			_next_item_instance_id += 1

	_recompute_item_bonuses()
	# Starting items may have raised max_hp; heal to that new full pool
	# so the player begins the run at full health regardless of bonuses.
	hp = max_hp

	emit_signal("stats_changed")
	emit_signal("hp_changed", hp, max_hp)
	emit_signal("deck_changed")
	emit_signal("inventory_changed")

# Clears the bookkeeping that tracks item-granted bonuses and instance ids.
# Shared by reset_run() and apply_character() so the two can't drift apart.
func _reset_item_tracking() -> void:
	item_stat_bonus = {}
	_applied_item_max_hp = 0
	_applied_item_max_energy = 0
	_next_item_instance_id = 1
	_gold_spent_accum = 0
	incremental_attacks_total = 0
	incremental_attacks_turn = 0
	incremental_turn_pulses = 0
	incremental_turn = 0
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

# A fresh combat began: per-combat counters restart; the run-wide attack
# total carries over.
func incremental_on_combat_started() -> void:
	incremental_turn = 0
	incremental_turn_pulses = 0
	incremental_attacks_turn = 0
	pen_nib_double_active = false
	streak_clear()

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
	current_game_id = id
	emit_signal("current_game_changed", id)

func set_max_hp(new_max: int, heal_to_full: bool = false) -> void:
	# Routes through Stats so Constitution auto-gain fires off the
	# delta. Pass heal_to_full=true to restore HP to the new max
	# (e.g., on level-up). Otherwise current HP is just clamped.
	var old_max: int = max_hp
	max_hp = max(1, new_max)
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

func change_hp(delta: int) -> void:
	set_hp(hp + delta)

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

func _pretty_stat(stat: String) -> String:
	return stat.capitalize()

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
func grant_run_stat(stat: String, value: int) -> void:
	if value == 0:
		return
	var amt: int = value
	if value > 0:
		amt += stat_gain_bonus_for(stat)
	var field: String = _LEVEL_UP_ABILITY_FIELDS.get(stat, stat)
	set(field, int(get(field)) + amt)
	emit_signal("stats_changed")

# Sacred Orb: true while any owned item rerolls low-rarity item drops.
func has_low_rarity_reroll() -> bool:
	for it in inventory:
		if it is ItemData and it.reroll_low_rarity:
			return true
	return false

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

# Pills may only be used in combat or while an event roll is open.
func can_use_items() -> bool:
	return combat_scene != null or event_active

# Whether `item` can be fired right now. USABLE pills need a combat/event
# context; CHARGED actives only need a full bar and can be popped from any
# screen (combat, backpack, a reward screen).
func can_fire_item(item: ItemData) -> bool:
	if item == null or inventory.find(item) == -1:
		return false
	if item.is_charged():
		return item.is_fully_charged()
	if item.kind == ItemData.ItemKind.USABLE:
		# Overworld actives (Winged Boots) fire only on the map — never in combat,
		# where their effect would no-op and waste a use. Ordinary pills are the
		# inverse: combat/event only.
		if item.overworld_usable:
			return overworld_scene != null
		return can_use_items()
	return false

# Whether a SCROLL can be read right now. Scrolls are an overworld-only
# consumable (some effects, like Teleportation, only make sense there, and the
# rest carry over into whatever comes next) — so reading is gated strictly to
# the Overworld scene being mounted, not merely "outside combat". Shops, rest
# sites, treasure rooms, event modals, and any in-progress deckbuilder/action/
# strategy run all leave overworld_scene null, so scrolls are blocked there too.
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
	if _grant_weapon_card(inst):
		emit_signal("deck_changed")
	_recompute_item_bonuses()
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
	TriggerBus.emit_signal("item_acquired", {"item": inst})
	emit_signal("inventory_changed")
	return inst

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

# Canonical "add a card to the player's deck" entry. Accepts a CardInstance
# or a CardData (wrapped into a fresh instance). Applies egg auto-upgrades
# (upgrade_card_types) before the card lands, appends, and fires deck_changed.
# Card rewards and shop purchases route through here; the starting deck and
# weapon-granted cards stay direct (no eggs at character start, and weapon
# cards are a managed pair).
func add_card_to_deck(card) -> CardInstance:
	var ci: CardInstance = null
	if card is CardInstance:
		ci = card
	elif card is CardData:
		ci = CardInstance.from_data(card)
	if ci == null:
		return null
	# Egg items auto-upgrade a freshly added card whose type matches, as long
	# as the card supports upgrading and isn't already upgraded.
	if not ci.upgraded and ci.data != null and ci.data.can_upgrade \
			and _deck_add_should_upgrade(ci.data):
		ci.upgraded = true
		Notifications.notify("%s was upgraded by an Egg!" % ci.data.display_name,
			Color(1.0, 0.72, 0.3))
	# Vorpal weapons roll their bound combat type + weight once, at acquisition,
	# so the badge is visible immediately and the roll persists with the save.
	ci.roll_vorpal_if_needed()
	deck.append(ci)
	emit_signal("deck_changed")
	return ci

func _deck_add_should_upgrade(card_data: CardData) -> bool:
	for item in inventory:
		if not (item is ItemData) or item.upgrade_card_types.is_empty():
			continue
		for t in item.upgrade_card_types:
			if ItemTriggers._card_type_is(card_data, String(t)):
				return true
	return false

# Upgrades up to `count` random, not-yet-upgraded, upgradeable deck cards of the
# given type (Whetstone -> "attack", War Paint -> "skill"; "" = any type). A
# permanent deck change, so the upgrade is read in every combat mode via
# CardInstance.get_effective_effects. Returns the display names upgraded (for
# logging). card_type matches CardData.type via the shared ItemTriggers mapper.
func upgrade_random_deck_cards(card_type: String, count: int) -> Array:
	var pool: Array = []
	for ci in deck:
		if ci is CardInstance and not ci.upgraded and ci.data != null \
				and ci.data.can_upgrade \
				and (card_type == "" or ItemTriggers._card_type_is(ci.data, card_type)):
			pool.append(ci)
	pool.shuffle()
	var names: Array = []
	for i in range(mini(maxi(0, count), pool.size())):
		pool[i].upgraded = true
		names.append(pool[i].data.display_name)
	if not names.is_empty():
		emit_signal("deck_changed")
	return names

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

func _grant_weapon_card(inst: ItemData) -> bool:
	# Internal: if `inst` is a weapon with a linked card_id, append a
	# CardInstance tagged with the item's instance_id. Caller decides
	# whether to fire deck_changed (apply_character batches the emit).
	if inst == null:
		return false
	if inst.kind != ItemData.ItemKind.WEAPON or inst.weapon_card_id == &"":
		return false
	var card_def: CardData = Data.get_card(inst.weapon_card_id)
	if card_def == null:
		return false
	var ci: CardInstance = CardInstance.from_data(card_def)
	ci.source_weapon_id = inst.instance_id
	deck.append(ci)
	return true

func remove_item_at(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var removed: ItemData = inventory[index]
	inventory.remove_at(index)
	# Pair removal: a weapon item carries the source_weapon_id its card
	# was tagged with. Strip every deck card pointing back at this slot.
	if removed is ItemData and removed.kind == ItemData.ItemKind.WEAPON and removed.instance_id != 0:
		_remove_deck_cards_for_weapon(removed.instance_id)
	_recompute_item_bonuses()
	emit_signal("inventory_changed")

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

func remove_card_at(deck_index: int) -> void:
	# Inverse of the weapon-removes-card path. If the card was weapon-
	# granted (source_weapon_id != 0), find and drop the paired item too
	# so the pair never desyncs. Combat-only mutations (exhaust, discard)
	# don't route through here — those operate on the per-combat piles.
	if deck_index < 0 or deck_index >= deck.size():
		return
	var card = deck[deck_index]
	# Eternal cards (Greed) can never be removed from the deck.
	if card is CardInstance and card.data != null and card.data.eternal:
		Notifications.notify("%s is Eternal — it can't be removed." % card.data.display_name,
			Color(0.85, 0.6, 0.9))
		return
	deck.remove_at(deck_index)
	# Removing a CURSE-type card is a "got rid of a curse card" event
	# (Golden Beetle reacts to it). Distinct from curse_removed, which is an
	# active_curses entry leaving.
	if card is CardInstance and card.data != null and card.data.type == CardData.CardType.CURSE:
		TriggerBus.emit_signal("curse_card_removed", {"card": card.data})
	var weapon_id: int = 0
	if card is CardInstance:
		weapon_id = card.source_weapon_id
	if weapon_id != 0:
		for i in range(inventory.size() - 1, -1, -1):
			var it = inventory[i]
			if it is ItemData and it.instance_id == weapon_id:
				inventory.remove_at(i)
				_recompute_item_bonuses()
				emit_signal("inventory_changed")
				break
	emit_signal("deck_changed")

# Destroy addon: permanently remove a specific physical card (by reference)
# from the run deck when it's played/used. Self-initiated, so it bypasses the
# Eternal guard in remove_card_at (a card removing ITSELF is its whole point).
# No-op if the card isn't in the deck (already gone, or a combat-only copy).
func destroy_card_instance(card: CardInstance) -> bool:
	if card == null:
		return false
	var idx: int = deck.find(card)
	if idx < 0:
		return false
	deck.remove_at(idx)
	if card.data != null and card.data.type == CardData.CardType.CURSE:
		TriggerBus.emit_signal("curse_card_removed", {"card": card.data})
	if card.source_weapon_id != 0:
		for i in range(inventory.size() - 1, -1, -1):
			var it = inventory[i]
			if it is ItemData and it.instance_id == card.source_weapon_id:
				inventory.remove_at(i)
				_recompute_item_bonuses()
				emit_signal("inventory_changed")
				break
	emit_signal("deck_changed")
	return true

# Destroy in Action mode: the loadout is flattened to CardData, so destroy the
# FIRST deck CardInstance sharing this CardData's id (one physical copy per
# destroy event). Returns true if a copy was removed.
func destroy_first_card_with_id(card_data) -> bool:
	if card_data == null:
		return false
	for c in deck:
		if c is CardInstance and c.data != null and c.data.id == card_data.id:
			return destroy_card_instance(c)
	return false

# Action mode flattens the deck to CardData for its auto-slots, so per-instance
# Vorpal state isn't on the played card. Recover it by looking up the first deck
# CardInstance sharing this CardData's id. Returns { type, weight } or {} when
# the card carries no live Vorpal roll.
func vorpal_for_card_data(card_data) -> Dictionary:
	if card_data == null:
		return {}
	for c in deck:
		if c is CardInstance and c.data != null and c.data.id == card_data.id:
			c.roll_vorpal_if_needed()
			if c.vorpal_type >= 0 and c.vorpal_weight > 0:
				return {"type": c.vorpal_type, "weight": c.vorpal_weight}
			return {}
	return {}

func _remove_deck_cards_for_weapon(weapon_instance_id: int) -> void:
	# Internal: drop every CardInstance whose source_weapon_id matches.
	# Iterates back-to-front so removals don't invalidate the index.
	var changed: bool = false
	for i in range(deck.size() - 1, -1, -1):
		var c = deck[i]
		if c is CardInstance and c.source_weapon_id == weapon_instance_id:
			deck.remove_at(i)
			changed = true
	if changed:
		emit_signal("deck_changed")

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
	# HUDs that key off inventory state (Vajra+1 tooltips, etc.) refresh.
	_recompute_item_bonuses()
	emit_signal("inventory_changed")
	return {"item": picked, "delta": delta, "new_level": picked.upgrade_level}

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
	var hp_delta: int = max_hp_total - _applied_item_max_hp
	if hp_delta != 0:
		max_hp = maxi(1, max_hp + hp_delta)
		hp = mini(hp, max_hp)
		_applied_item_max_hp = max_hp_total
		emit_signal("hp_changed", hp, max_hp)

	var en_delta: int = max_energy_total - _applied_item_max_energy
	if en_delta != 0:
		max_energy = maxi(0, max_energy + en_delta)
		_applied_item_max_energy = max_energy_total

	# Second pass: SCALING items. Resolved against the post-vitals state so
	# a Beefy Ring + Alien Baby combo sees the bumped max_hp. Output goes
	# into item_stat_bonus alongside flat bonuses; reads through Stats see
	# both transparently. Scaling never writes vitals — that would re-enter
	# this function via set_max_hp and loop forever.
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
			if out_stat == "max_hp" or out_stat == "max_energy":
				push_warning("ItemData.scaling: '%s' cannot output vitals" % it.id)
				continue
			var src_amount: int = int(get(src_stat))
			@warning_ignore("integer_division")
			var stacks: int = src_amount / per
			if stacks == 0:
				continue
			totals[out_stat] = int(totals.get(out_stat, 0)) + per_val * stacks

	item_stat_bonus = totals
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
# Loot (potions / scrolls / keys)
# ---------------------------------------------------------------------------

func add_loot(kind: String, amount: int = 1) -> void:
	if amount == 0:
		return
	match kind:
		"potion":
			# Each unit becomes a concrete, rarity-rolled potion entry. Negative
			# amounts drop the most-recently-gained potions (rare, but keep the
			# old API total-safe).
			if amount > 0:
				for _i in range(amount):
					_add_random_potion_loot()
			else:
				_drop_loot_of_type("potion", -amount)
		"scroll":
			# Each unit becomes a concrete, rarity-rolled scroll entry (gained
			# unidentified; ScrollSystem resolves identity on read).
			if amount > 0:
				for _i in range(amount):
					_add_random_scroll_loot()
			else:
				_drop_loot_of_type("scroll", -amount)
		_:
			if not loot.has(kind):
				push_warning("GameState.add_loot: unknown kind '%s'" % kind)
				return
			loot[kind] = maxi(0, int(loot[kind]) + amount)
	emit_signal("inventory_changed")

func get_loot_count(kind: String) -> int:
	match kind:
		"potion", "scroll":
			var n: int = 0
			for l in loot_items:
				if l is Dictionary and String(l.get("type", "")) == kind:
					n += 1
			return n
		_:
			return int(loot.get(kind, 0))

# Concrete potion loot entries the player is carrying, in pickup order. The loot
# UIs list these.
func loot_potions() -> Array:
	return loot_items.filter(func(l): return l is Dictionary and String(l.get("type", "")) == "potion")

# Concrete scroll loot entries the player is carrying, in pickup order.
func loot_scrolls() -> Array:
	return loot_items.filter(func(l): return l is Dictionary and String(l.get("type", "")) == "scroll")

func _add_random_potion_loot() -> void:
	var p: PotionData = Data.roll_potion()
	if p != null:
		loot_items.append({"type": "potion", "id": p.id, "rarity": p.rarity})

func _add_random_scroll_loot() -> void:
	var s: ScrollData = Data.roll_scroll()
	if s != null:
		loot_items.append({"type": "scroll", "id": s.id, "rarity": s.rarity})
	else:
		# No scrolls loaded — keep the old inert stub so counts/UI don't break.
		loot_items.append({"type": "scroll", "rarity": "Common"})

# Grant a SPECIFIC potion id as loot (DevTools grant, shop purchase). Emits so
# any open loot UI refreshes.
func add_potion_loot(id: StringName) -> void:
	var p: PotionData = Data.get_potion(id)
	if p == null:
		return
	loot_items.append({"type": "potion", "id": p.id, "rarity": p.rarity})
	emit_signal("inventory_changed")

# Grant a SPECIFIC scroll id as loot (DevTools grant). Emits so loot UI refreshes.
func add_scroll_loot(id: StringName) -> void:
	var s: ScrollData = Data.get_scroll(id)
	if s == null:
		return
	loot_items.append({"type": "scroll", "id": s.id, "rarity": s.rarity})
	emit_signal("inventory_changed")

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

# Post-combat consumable reward: 50/50 a concrete potion or an (inert) scroll
# stub, mirroring the legacy selectRandomPotionOrScroll split. Returns the entry
# added so the caller can toast it; {} if nothing could be granted.
func grant_random_consumable_loot(rng: RandomNumberGenerator = null) -> Dictionary:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	if r.randf() < 0.5:
		var p: PotionData = Data.roll_potion(r)
		if p != null:
			var e := {"type": "potion", "id": p.id, "rarity": p.rarity}
			loot_items.append(e)
			emit_signal("inventory_changed")
			return e
	var s: ScrollData = Data.roll_scroll(r)
	var e2: Dictionary
	if s != null:
		e2 = {"type": "scroll", "id": s.id, "rarity": s.rarity}
	else:
		e2 = {"type": "scroll", "rarity": "Common"}
	loot_items.append(e2)
	emit_signal("inventory_changed")
	return e2

# ---------------------------------------------------------------------------
# Action-mode loadout
# ---------------------------------------------------------------------------

# Returns { "left": CardData|null, "right": CardData|null, "auto": Array[CardData] }.
#
# `left`/`right` are the two manual click slots (LMB/RMB). Only Strikes or
# weapon-granted cards are eligible; if unset, the first eligible deck card
# is auto-picked so the arena is always playable. `auto` is the auto-play
# pool: every other deck card except non-playable types (Curse/Status/
# unplayable). Powers are included — they cycle and resolve on a cooldown
# like everything else. Duplicates are preserved (three Strikes in the deck
# means three entries in the pool).
func get_action_loadout() -> Dictionary:
	# Resolve each click slot to a concrete deck instance when its chosen id is
	# present in the deck, so an UPGRADED copy fires its upgraded numbers (action
	# otherwise flattens to base CardData). Falls back to a base CardData (id with
	# no live instance) and then to an auto-picked instance.
	var left_inst: CardInstance = _find_deck_instance(action_left_card_id, [])
	var right_inst: CardInstance = _find_deck_instance(action_right_card_id, [left_inst])

	var left: CardData = _effective_action_card(left_inst)
	if left == null and action_left_card_id != &"":
		left = Data.get_card(action_left_card_id)
	if left == null:
		left_inst = _auto_pick_click(&"", false, [])
		left = _effective_action_card(left_inst)

	var right: CardData = _effective_action_card(right_inst)
	if right == null and action_right_card_id != &"":
		right = Data.get_card(action_right_card_id)
	if right == null:
		var left_is_strike: bool = left != null and left.tags.has("strike")
		right_inst = _auto_pick_click(left.id if left != null else &"", left_is_strike, [left_inst])
		right = _effective_action_card(right_inst)

	# Build the auto pool from the deck, holding back the two click instances (by
	# identity, so mixed base/upgraded copies of the same id are distinguished).
	var held: Array = []
	if left_inst != null:
		held.append(left_inst)
	if right_inst != null:
		held.append(right_inst)
	var auto: Array = []
	for c in deck:
		if not (c is CardInstance) or c.data == null:
			continue
		var hi: int = held.find(c)
		if hi != -1:
			held.remove_at(hi)  # consumed one copy for a click slot
			continue
		var data: CardData = c.data
		if data.unplayable:
			continue
		if data.type == CardData.CardType.CURSE or data.type == CardData.CardType.STATUS:
			continue
		auto.append(_effective_action_card(c))
	return {"left": left, "right": right, "auto": auto}

# The CardData action should fire for a deck instance: the shared base resource,
# or — for an upgraded instance — a cached duplicate carrying the upgraded
# effects/cost/description. Action keys per-card state (cooldowns, use caps) by
# CardData identity, so every upgraded copy of an id resolves to ONE cached
# resource, exactly like base copies share Data.get_card's resource.
func _effective_action_card(inst: CardInstance) -> CardData:
	if inst == null or inst.data == null:
		return null
	return effective_action_card_data(inst.data, inst.upgraded)

# Public form for callers that hold a base CardData + a known upgrade flag (the
# action conjure path resolving `shiv+`). Returns the base resource untouched
# when not upgraded (or the card can't upgrade).
func effective_action_card_data(base: CardData, upgraded: bool) -> CardData:
	if base == null:
		return null
	if not upgraded or not base.can_upgrade:
		return base
	var key: StringName = base.id
	if not _action_upgraded_cache.has(key):
		_action_upgraded_cache[key] = _make_upgraded_card_data(base)
	return _action_upgraded_cache[key]

func _make_upgraded_card_data(base: CardData) -> CardData:
	# Shallow-duplicate the resource (image/script/flags carried over) and fold in
	# the upgrade-only fields. Upgrade in this project changes exactly effects /
	# cost / description (keywords are shared), so nothing else needs touching.
	var dup: CardData = base.duplicate() as CardData
	dup.effects = base.get_effective_effects(true).duplicate(true)
	dup.cost = base.get_effective_cost(true)
	dup.description = base.get_effective_description(true)
	dup.display_name = base.display_name + "+"
	dup.can_upgrade = false
	return dup

# First deck instance with `card_id`, skipping any already-claimed instances
# (so two slotted Strikes resolve to two different physical cards).
func _find_deck_instance(card_id: StringName, exclude: Array) -> CardInstance:
	if card_id == &"":
		return null
	for c in deck:
		if c is CardInstance and c.data != null and c.data.id == card_id and not (c in exclude):
			return c
	return null

# True if the card id may be slotted into a click slot: it's a Strike
# (tagged) or a weapon-granted card (some deck instance links to a weapon).
func is_click_eligible(card_id: StringName) -> bool:
	if card_id == &"":
		return false
	var card: CardData = Data.get_card(card_id)
	if card != null and card.tags.has("strike"):
		return true
	for c in deck:
		if c is CardInstance and c.data != null and c.data.id == card_id and c.source_weapon_id != 0:
			return true
	return false

func _auto_pick_click(exclude_id: StringName, forbid_strike: bool = false, exclude: Array = []) -> CardInstance:
	# Prefer a Strike; otherwise the first weapon-granted card. Skips
	# `exclude_id` (so left and right don't auto-pick the same id), any instance
	# in `exclude` (the other slot's physical card), and enforces
	# one-Strike-at-a-time across the two slots via `forbid_strike`. Returns the
	# deck INSTANCE so the caller can keep its upgrade state + hold it back.
	if not forbid_strike:
		for c in deck:
			if not (c is CardInstance) or c.data == null:
				continue
			if c.data.id == exclude_id or c in exclude:
				continue
			if c.data.tags.has("strike"):
				return c
	for c in deck:
		if not (c is CardInstance) or c.data == null:
			continue
		if c.data.id == exclude_id or c in exclude:
			continue
		if c.source_weapon_id != 0:
			return c
	return null
