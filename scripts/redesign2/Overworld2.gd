class_name Overworld2
extends Control

# Overworld2 — the games-first (2.0) overworld: a CLICK-TO-CHOOSE board that
# replaces the old walk-around-and-open-a-door overworld (docs/games-first-
# redesign.md §2 / §6 / §7). There is no walker and no doors: the player is shown
# the games reachable from where they are as cards (the game's COVER IMAGE with
# its NAME below), hovers a card to preview the goal-enemy that game would spawn,
# and clicks a card to travel there.
#
# It is a thin view over GameLoop2 + GameState (the same pattern as PlaySession2,
# which it supersedes as the real overworld panel): every action is a public
# method a headless test can call, and the whole UI refreshes on `loop_changed`.
#
# This file owns the RUN: the offering, the report step, the pack strip above the
# board, and the charges the combat verbs spend.
# Five pieces live next door. BattlefieldView (the board and its animation) and
# EnemyInfoCard (the click-to-inspect card) talk back through signals. PackStrip
# (the pack strip's tokens), ReportChecklist (the left column, in both its
# states) and OfferingCards (the cards you choose from, in both choosing phases)
# fill containers this page owns and call back through its public verbs.
#
# Difficulty gates (§7.1): the run's tier steps up every RunDifficulty.
# GAMES_PER_TIER games (RunDifficulty.tier_for). On the game that crosses into a
# new tier, the offering becomes a BOSS round — a "⚠ BOSS INCOMING" popup opens
# once (BossNoticeModal) and whichever game you pick spawns a boss.

# Phases of one selection. START_SELECT is the one-off opening phase: before the
# run has a position, the player picks WHERE TO START from three games, each a
# different genre and each the same distance band from the amulet (RunGraph).
enum Phase { SELECT, PLAYING, OVER, START_SELECT }

# The normal offering is LIMITED (a subset of the reachable games) — Dash (§4) is
# the verb that bypasses it to reach any connected game. Kept small so the board
# reads at a glance; the amulet is always included when it's reachable so a win is
# never blocked by the cap.
#
# The base offering is THREE cards. Items / level-ups / future effects widen it by
# granting the "game_choices" stat (GameState.game_choice_bonus), so the visible
# count is always read through offer_count() rather than the constant.
const BASE_OFFER_COUNT := 3

# The hub rule. A well-connected game has far more neighbours than the offering
# can show, so the seeded subset can come up all dead ends — three games that each
# lead nowhere — and the run stalls at exactly the node that should have opened
# it up. When the player stands on a game with MORE THAN HUB_CONNECTIONS
# connections, at least one card is guaranteed to be a game with MORE THAN
# ONWARD_CONNECTIONS connections of its own, so there is always a way onward.
#
# Only hubs get the guarantee: at a small node, a thin offering is the honest
# shape of where you are, and forcing an onward card there would quietly override
# the route the graph actually has.
const HUB_CONNECTIONS := 20
const ONWARD_CONNECTIONS := 2

# Beating a game you have ALREADY beaten this run pays a Dash charge (§4's "total
# select" verb). Revisiting is a real routing option — a node's offering is drawn
# from its neighbours, so a cleared game comes back around — and this is what
# makes doubling back worth considering instead of strictly worse. The offering
# labels those cards up-front so the bonus is a choice, not a surprise.
const REPEAT_BEAT_DASH := 1

# The Dash verb's colour, shared by its hint, its offering label, and the
# repeat-beat announcement so all three read as the same mechanic.
const DASH_BLUE := Color(0.5, 0.85, 1.0)
# The clover's own green — deliberately not the shop's, which is a place you can
# walk into, where this is a property of every roll.
const LUCK_GREEN := Color(0.55, 0.9, 0.55)

# Shields — the armour the game in play granted (§3). One steel-blue used by the HUD
# count, the attempt strip, and the pips on the board.
const SHIELD_BLUE := Color(0.62, 0.78, 0.95)

# The currency and shop colours live on UITheme (COIN_GOLD / SHOP_GREEN, §14) —
# the shop modal and the game popup need them too, and a modal reaching back into
# the screen that mounted it for a constant is a dependency cycle.

# The current offering. Each entry:
#   {"game": GameData, "enemy": GoalEnemyData, "boss": bool, "amulet": bool,
#    "repeat": bool}
# The enemy is rolled up-front so the hover preview and the enemy that actually
# spawns on click are the SAME roll. `repeat` marks a game already played this
# run — beating it again grants a Dash (REPEAT_BEAT_DASH).
var _choices: Array = []
# The opening choose-your-start offering (Phase.START_SELECT). Each entry:
#   {"game": GameData, "type": int, "path_len": int, "in_window": bool,
#    "enemy": GoalEnemyData}
# Rolled once by RunGraph at run start: three games of three different types, each
# MIN_PATH_LENGTH..MAX_PATH_LENGTH games from the (hidden) amulet. Cleared the
# moment a start is chosen.
var _start_options: Array = []
# The goal-enemy standing behind each offered SLOT, so bashing or transmuting one
# card doesn't silently re-roll the enemies behind the others. Keyed
# "<slot id>><game id>" (a transmuted slot plays a different game, so it earns a
# fresh roll) and wiped whenever the offering itself is re-drawn — a move, a
# scramble, or a difficulty-tier change (see _build_choices).
var _slot_enemies: Dictionary = {}
var _slot_enemy_key: String = ""
var _boss_round: bool = false
var _phase: int = Phase.SELECT
var _chosen: Dictionary = {}          # the choice being played (Phase.PLAYING)
# Scramble (§4) reroll counter. The offering is drawn in a STABLE position-seeded
# order so bashing one card doesn't reshuffle the rest; this salt is what a
# scramble changes, re-drawing which games fill the slots (and, through
# _build_choices, the enemies behind them).
var _scramble_salt: int = 0
# How many times the player has ARRIVED at each game this run (game id -> count),
# counted off GameState.current_game_changed. It salts the offering draw, so
# coming back to a game you've already stood on offers a DIFFERENT set of its
# neighbours rather than replaying the same three cards (see _offer_seed).
var _visits: Dictionary = {}
# BFS distances from the Amulet over the current graph, rebuilt with the offering
# (see _rebuild_amulet_distances). What every card's route badge is read off.
var _amulet_dist: Dictionary = {}
# True between a report and the end of the board's playback of it: the run has
# already moved on, but the screen is still showing how (see _hold_for_resolve).
# A lost run's enemy turn (§3) raises it too — it is the same playback — which is
# what `_attempt_resolve` below distinguishes.
var _resolving: bool = false
# …and true when the playback in flight is a TICK'S turn rather than a report's.
# The two end differently: a report hands the screen on to the haul, an event, a
# shop; a tick has none of those behind it and simply gives the board back.
var _attempt_resolve: bool = false
# An end-of-run screen owed to the player, held back until the board has finished
# playing the resolve that ended the run.
var _run_over_pending: bool = false
# An item picked up WHILE the board was playing a resolve back: the repaint it
# asked for is owed, and paid at _end_resolve rather than over the animation.
var _board_dirty: bool = false
# The event waiting to open once the board has finished playing its resolve back.
# An event fires AFTER the game at its node is played (docs/event-sheet-authoring.md
# §1) and the board is mid-animation at that moment, so it queues here the way the
# run-over screen does rather than opening over a moving battlefield.
var _pending_event: EventData2 = null
# The node that event was rolled for, so opening it can SPEND that node — one
# event per game, however many times the run walks back through it.
var _pending_event_node: StringName = &""
# Checklist bindings for the two event-borne sections. ReportChecklist owns them;
# these are read-only views under the names the tests reach for.
var _event_goal_checks: Array:
	get: return _checklist.event_goal_checks if _checklist != null else []
var _curse_goal_checks: Array:
	get: return _checklist.curse_goal_checks if _checklist != null else []
# The header's always-visible Health readout (see _build_health_chip).
var _health_chip: Label = null
var _gold_chip: Label = null
# The road walked, across the top of the page. Rebuilt on every refresh — it is a
# handful of TextureRects and the run only moves a few dozen times.
var _route_strip: HBoxContainer = null
# The header row itself, and the layer it floats on. Health / Gold / the road /
# the title / the menu, pinned to the top of the SCREEN rather than of the page —
# see _mount_header.
var _header: HBoxContainer = null
var _header_bar: PanelContainer = null
var _header_layer: CanvasLayer = null
# The transient-toast stack, held so it can be pushed clear of the header bar.
var _toasts: Control = null
# A `play_game` detour in flight (docs/event-sheet-authoring.md §10). The node to
# offer a way back to, and the payload that lands when the detour game is beaten.
var _play_return_to: StringName = &""
var _play_payload: Array = []
var _play_payload_text: String = ""
# The far side of that detour, when the run is standing on it: the game "head
# back" would return to, or &"" when nothing is being asked. While it is set the
# offering is showing TWO DESTINATION CARDS rather than an offering (see
# _build_return_choices), and every verb that redraws the offering is held.
var _return_choice: StringName = &""
# A detour whose stay-or-return question is owed once the board (and the event /
# shop the game may also have owed) has finished. The question is asked on the
# offering itself, so it has to wait for the same queue everything else does.
var _pending_detour: bool = false
# …and whether that detour's game was actually beaten, since the payout only
# lands on a game played to a verdict (an escape walks away from it).
var _detour_beaten: bool = false
var _event_modal: EventModal2 = null
# The hub whose shop is owed to the player once the board stops moving (§14).
# Set on the same terms an event is — the game at this node was played through
# and not escaped — because a shop and an event are the same kind of thing:
# what was waiting at the node, paid after the game rather than before it.
# &"" when nothing is owed.
var _pending_shop: StringName = &""
# The shop currently ON THE PAGE, under the board (ShopPanel2), and the pointer
# that says it is down there. The shop is no longer a modal: it is mounted below
# the battlefield and stays for the whole visit, so these live as long as the
# player stands at that hub rather than as long as a dialog is open.
var _shop_panel: ShopPanel2 = null
var _shop_hint: Control = null
# The machines standing at this game, in the same space and on the same terms
# (docs/object-sheet-authoring.md). Only ever mounted for objects spawned OUTSIDE
# an event — an event draws its own inside its modal, because the room the
# machines are in is the thing the event is.
var _object_panel: ObjectPanel2 = null
var _run_over_won: bool = false
var _run_over_screen: RunOverScreen = null
# THE SCREEN A GAME ENDS ON (PostCombatScreen), and the report it is about. The
# haul used to arrive as a queue of modals over an animating board and then an
# event on top of that; it is one screen now, opened once the playback has landed
# (_open_post_game). `_post_snapshot` is what `report` recorded on the way past —
# empty at every other moment, which is also how _end_resolve tells a report's
# animation from any other.
var _post_snapshot: Dictionary = {}
var _post_screen: PostCombatScreen = null
var _rng := RandomNumberGenerator.new()

# --- UI nodes (built in code) --------------------------------------------
# The verbs that are spent CHOOSING, as chips under the offering they act on.
# (The board's own verbs need no row of their own: BattlefieldView's toolbar
# buttons already read "⇤ Push (1)" / "✸ Bomb (3)", and its pressure bar ends in
# the run's tier.)
var _select_stats: HFlowContainer
# The open READING CARD, or null. Either an ItemInfoCard (a relic) or a
# LootInfoCard (a pill or a scroll) — they are the same slot on the screen and
# only one of them is ever up, so the field holds whichever it is. Typed as Control
# because the two share a shape (`close`, `closed`) rather than a base class.
var _item_card: Control = null
var _banner: Label
# The boss round announces itself as a POPUP (BossNoticeModal), not as a strip
# above the offering — see that file for why. This remembers which round has
# already been announced (`GameState.games_played` at the time), so the notice
# opens once when the round arrives rather than on every repaint of it.
var _boss_notice_for: int = -1
var _boss_notice: BossNoticeModal = null
var _preview: RichTextLabel
var _preview_art: TextureRect       # the hovered card's enemy, beside the line
var _choices_row: HFlowContainer
var _offering: OfferingCards = null
var _play_panel: VBoxContainer
var _now_playing: RichTextLabel
var _now_playing_cover: TextureRect # the chosen game's cover, beside it
var _launch_row: HBoxContainer
var _verify_box: VBoxContainer      # clean checklist: goal + level-up + follower goals
# The checklist itself — both states of the left column, and the row-to-body
# pairing (ReportChecklist). Built in _build_ui, once the two containers it fills
# exist. Everything below is a READ-ONLY VIEW of the state it owns, kept on the
# page under the names the rest of this file and the tests already use: the tests
# read these and then tick the CheckBoxes they point at, which is what a player
# does to the same objects.
var _checklist: ReportChecklist = null
var _fulfil_checks: Array:          # [{check: CheckBox, instance: int}]
	get: return _checklist.fulfil_checks if _checklist != null else []
# Statuses 2.0 (§13) on the report checklist. `_status_goal_checks` are the
# player's own BUFF goals — extra rows that pay when ticked, plus the `demand` rows
# that BITE when they are not; `_bonus_checks` are the OPTIONAL bonus objectives an
# enemy's `bonus` side hangs off it; `_instead_checks` are the "or instead" rows a
# burned enemy grows, each a second way to clear that body. All three are read into
# beat_game's `claims` on report; the required clauses (enemy buffs, player
# clauses) need no boxes of their own because they are folded into the goal line.
var _status_goal_checks: Array:     # [{check: CheckBox, status: StringName}]
	get: return _checklist.status_goal_checks if _checklist != null else []
var _bonus_checks: Array:           # [{check: CheckBox, instance: int, status: StringName}]
	get: return _checklist.bonus_checks if _checklist != null else []
var _instead_checks: Array:         # [{check: CheckBox, instance: int, status: StringName}]
	get: return _checklist.instead_checks if _checklist != null else []
var _levelup_check: CheckBox:       # null when the character has no level-up
	get: return _checklist.levelup_check if _checklist != null else null
# Checklist row -> board body (see _bind_row_to_body). `_row_paints` is instance
# -> the paint callables of every row written about that body; `_lit_instances`
# is what is lit right now, from whichever end the mouse is on.
var _row_paints: Dictionary:
	get: return _checklist.row_paints if _checklist != null else {}
var _lit_instances: Dictionary:
	get: return _checklist.lit_instances if _checklist != null else {}
var _dash_mode: bool = false        # Dash (§4): offer ANY connected game
# Was the game in hand reached BY a Dash? Read by report() so the return-trip
# Dash is not silently cancelled by the charge that paid for the trip.
var _dashed_here: bool = false

# --- repaint guards ---------------------------------------------------------
#
# THREE SECTIONS OF THE PAGE ARE REBUILT FROM SCRATCH ON EVERY LOOP SIGNAL, and
# GameLoop2 emits 23 of those, several of them inside one resolve. "Rebuilt"
# means _clear() and a fresh set of Controls — and a fresh Control carrying one
# of the verb glyphs costs about 2 ms to shape on its own. The project ships no
# font file, so ⛏ ⚡ ⚗ 🎲 🍀 miss Godot's built-in one and every new Label runs
# the system fallback search again: measured, five verb chips are 10.9 ms against
# 0.6 ms for the same five chips in plain ASCII. That was most of a 19 ms
# _refresh, on a page whose whole budget is one 60fps frame.
#
# So each of the three keeps a SIGNATURE of what it last drew and returns early
# when it would only draw the same thing again. The signature is derived from the
# very values the rebuild reads, which is what makes this safe: "unchanged"
# cannot mean anything except unchanged.
#
# WHY NOT SPLIT THE SIGNAL, which is what docs/performance-backlog.md proposed.
# A split decides per EMIT SITE which parts of the page need repainting, so it
# has to be re-judged every time an emit site is added, and forgetting one leaves
# a strip quietly showing a number that has moved — which is exactly the bug the
# comment on _refresh_stats records (a HUD strip repainting while the board
# waited, so a Hollow Heart off a kill-drop raised Max Health with nothing on
# screen saying so). A signature cannot rot that way: a new emit site still
# reaches every section, and every section still asks the same question about its
# own inputs.
#
# The one way this DOES go wrong is another function writing into the same
# container, leaving a signature that describes content which is no longer there.
# There are two such cases and both invalidate by hand: _refresh clears
# _controls_row itself on the start panel, and _populate_play_panel takes over
# the checklist box during the report step.
var _select_stats_sig: String = ""
var _controls_sig: String = ""
# The third signature lives with the section it guards, in ReportChecklist.

var _controls_row: HBoxContainer
var _stack: RichTextLabel           # battlefield summary line
# The offering half of the page (heading, verbs, cards, hover preview) — hidden
# once a game is in play, which is what frees the room for the stage below.
var _select_box: VBoxContainer
# Its heading, which says which question the cards below are asking: where to
# start the run (START_SELECT) or where to travel next (SELECT).
var _select_head: Label
# The STAGE, two columns wide: the report checklist on the left, and on the right
# the board with the pack strip (the carried items) above it.
var _left_col: VBoxContainer
var _right_col: VBoxContainer
var _report_panel: PanelContainer    # frames the checklist half (left)
var _stage_panel: PanelContainer     # frames the board (right, under the pack strip)
var _board_head: HBoxContainer       # the board's summary line + its verb chips
var _inv_wrap: PanelContainer        # the carried items, in a strip above the board
# The page's ScrollContainer. The stage is taller than a screen with the board on
# top, so picking a game scrolls the report half into reach (the board is a scroll
# up from there) and reporting scrolls back to the offering.
var _scroll: ScrollContainer
# The offering — the cards for both choosing phases and the hover line under
# them (OfferingCards). Built in _build_ui, once the three containers it fills
# exist. It also owns the hovered card's shield grant, which only its own hover
# line reads.
# Attempt tracker (§3) — the runs of the game in play you have lost.
var _attempt_count: Label
var _attempt_pips: Label
var _attempt_hint: Label
var _attempt_btn: Button
var _attempt_undo: Button
var _escape_btn: Button           # hidden until the game in play draws blood (can_escape)
# The parts of the checklist panel that need a game in hand: the now-playing row,
# the attempt strip and the Completed Game button. Hidden while you're choosing,
# where the panel is the standing-goals list instead.
var _np_box: VBoxContainer
var _attempt_wrap: Control
var _done_btn: Button
# The board itself (§grid): the player on the left, a grid_cols() x grid_rows() grid on
# the right where enemies close in one column per game beaten (MMBN-style). It's a
# BattlefieldView — a view over GameLoop2 that reports Push / Bomb / inspect back
# here, since this screen owns the charges and the run.
var _board: BattlefieldView
var _info_popup: EnemyInfoCard      # the click-to-inspect enemy card (null when closed)
var _choice_modal: GameChoiceModal = null   # the open offered-game popup, or null
var _log: RichTextLabel
# The pack strip above the grid: one small token per carried item (§4/§8).
# The page owns the container; PackStrip fills it (see _refresh_items).
var _items_box: HFlowContainer
var _pack: PackStrip = null
# The loot window (§4.3): its toggle sits at the end of the pack's row, and the
# 3x3 grid it opens FLOATS OVER THE LEFT COLUMN rather than dropping under the
# toggle. Opening it used to grow the pack panel downward, which pushed the board
# and re-flowed the right column every time the player looked at what they were
# carrying. `_loot_panel` is the mounted overlay, or null while it is shut.
var _loot_toggle_box: HBoxContainer
var _loot_panel: Control = null
var _loot_window: LootWindow = null
# The board rect the overlay was last placed against, so the frame hook can tell
# "the page moved" from "nothing happened" without re-placing every frame.
var _loot_anchor_rect: Rect2 = Rect2()
# The pack, mounted to the LEFT of the board for the length of a drag off the
# battlefield floor and nowhere near the page's layout (§8.2). Null the rest of
# the time, which is almost all of it — see `_notification`.
var _drag_pack: DragPackPanel = null
# What the run still owes the player an answer about — one modal at a time, in the
# order it landed (§8, _pump_drops). `_drop_modal` is the one in front of them
# right now, or null when nothing is being asked.
#
# Two shapes ride this queue, because a report pays two different things (§8.2):
#   {items: Array[ItemData]} — one CHEST, of which the player takes at most one.
#     A Small chest is a list of one, which is why the single-item shorthand
#     {item: ItemData} is still accepted (see _drop_items). Chests come from the
#     report now (the win, plus what was killed), not off individual bodies.
#   {loot: Array[Dictionary]}  — a handful of LOOT, each piece taken, used or
#     binned on its own terms. The pieces the bodies dropped on the floor, the
#     game's own payout, and anything a relic granted.
var _drop_queue: Array = []
var _drop_modal: Node = null
var _reward_open: bool = false      # a RewardScreen is currently showing
# The game most recently reported on. Rating is OPT-IN and never pops itself up
# (see _prompt_rating): this is what the "★ Rate <game>" button on the select
# screen scores, so a game can still be rated after you've moved on.
var _last_played_game: GameData = null

func _ready() -> void:
	_rng.randomize()
	_build_ui()
	if not GameLoop2.loop_changed.is_connected(_refresh):
		GameLoop2.loop_changed.connect(_refresh)
	if not GameLoop2.run_lost.is_connected(_on_run_lost):
		GameLoop2.run_lost.connect(_on_run_lost)
	if not GameLoop2.run_won.is_connected(_on_run_won):
		GameLoop2.run_won.connect(_on_run_won)
	# A ticked attempt animates on the board: a pip pops, or the hero takes the hit
	# once the shields are gone (§3).
	if not GameLoop2.attempt_logged.is_connected(_on_attempt_logged):
		GameLoop2.attempt_logged.connect(_on_attempt_logged)
	# Register as the mounted overworld so overworld-active items (Ride the Bus,
	# Wand of Wishing) can route their effect here, and so item pickups refresh
	# the inventory panel.
	GameState.set_overworld_context(self)
	# An item's effects have to show the moment it's picked up: a pickup fires its
	# item_acquired effects (Lunch's +2 Max Health / +2 Health) outside any loop
	# resolve, so the HUD is repainted off the state signals rather than waiting for
	# the next loop_changed.
	if not GameState.inventory_changed.is_connected(_on_inventory_changed):
		GameState.inventory_changed.connect(_on_inventory_changed)
	if not GameState.hp_changed.is_connected(_on_vitals_changed):
		GameState.hp_changed.connect(_on_vitals_changed)
	if not GameState.stats_changed.is_connected(_refresh_stats):
		GameState.stats_changed.connect(_refresh_stats)
	# A relic or an event GRANTING loot asks rather than filling the pack (§4.3).
	# Connected here rather than at the grant sites so anything that pays out loot —
	# an item, an event, the dev panel — comes through the same question, and so that
	# GameState can tell whether there is a screen to ask on at all: with nobody
	# connected it grants directly, which is what keeps headless runs and the tests
	# working unchanged.
	if not GameState.loot_offered.is_connected(_on_loot_offered):
		GameState.loot_offered.connect(_on_loot_offered)
	# Machines appearing or leaving. Off the signal rather than at the spawn
	# sites, so anything that spawns one — an event, the dev panel, whatever comes
	# next — puts it on the page without knowing the panel exists.
	if not ObjectSystem.objects_changed.is_connected(_sync_object_panel):
		ObjectSystem.objects_changed.connect(_sync_object_panel)
	# Gold moves on its own signal, not on stats_changed: a defeat pays mid-resolve
	# and a purchase pays with no loop event at all, so the purse would otherwise
	# sit on a stale number until something else happened to repaint the header.
	if not GameState.gold_changed.is_connected(_on_gold_changed):
		GameState.gold_changed.connect(_on_gold_changed)
	# A status applied off a loop resolve (a location entered, an item picked up)
	# changes what the checklist says the player has to DO, so it repaints the
	# screen rather than just the HUD strip (§13). Note _refresh rebuilds the
	# STANDING list only — a status landing mid-report updates the strip and waits,
	# because rebuilding the report step would throw away the boxes already ticked.
	if not GameState.player_statuses_changed.is_connected(_refresh):
		GameState.player_statuses_changed.connect(_refresh)
	# Arrivals salt the offering draw so a revisit isn't a rerun (§_offer_seed).
	if not GameState.current_game_changed.is_connected(_on_arrived):
		GameState.current_game_changed.connect(_on_arrived)
	# Every defeated enemy banks a chest (§8); redeem them into RewardScreens when
	# the board is idle — one screen per chest, so several defeats in one game pop
	# several rewards in a row.
	if not TriggerBus.chest_granted.is_connected(_on_chest_granted):
		TriggerBus.chest_granted.connect(_on_chest_granted)
	# Every defeated enemy drops an item, and the drop ASKS to be taken (§8) rather
	# than banking a RewardScreen chest.
	if not GameLoop2.enemy_defeated.is_connected(_on_enemy_defeated):
		GameLoop2.enemy_defeated.connect(_on_enemy_defeated)
	# A save being resumed takes precedence over booting a fresh run: the state is
	# already on GameState / GameLoop2, and this restores the screen over it.
	if SaveSystem.has_pending_resume():
		resume_run(SaveSystem.take_pending_view_state())
		return
	# The menu stashes the chosen 2.0 character here before entering the scene.
	var pending: StringName = GameState.get_meta("pending_character2", &"")
	if pending != &"":
		GameState.remove_meta("pending_character2")
	start_run(pending)

# --- public actions (buttons + tests call these) --------------------------

# Boot a fresh 2.0 run: roll the amulet and the three candidate starts, apply the
# 2.0 character loadout, and open on the CHOOSE-YOUR-START panel. The player has no
# position on the graph until choose_start() puts them on one, so the first real
# offering is drawn from whichever start they take. `character_id` empty -> the
# first authored 2.0 character.
func start_run(character_id: StringName = &"") -> void:
	# Whatever the last run left on the page goes with it: a verdict screen, a
	# resolve still being played back, an offering.
	_dismiss_run_over()
	_dismiss_post_game()
	_resolving = false
	_attempt_resolve = false
	_board.clear_fx()
	_visits.clear()
	_last_played_game = null
	_chosen = {}
	_choices.clear()
	_drop_queue.clear()
	_slot_enemies.clear()
	_slot_enemy_key = ""
	# …and everything a run can be standing in the middle of: a hub's shop, a
	# detour waiting to ask where to carry on from, a boss round already announced.
	_leave_node()
	_pending_shop = &""
	_pending_event = null
	_pending_event_node = &""
	_return_choice = &""
	_pending_detour = false
	_play_return_to = &""
	_play_payload = []
	_play_payload_text = ""
	_boss_notice_for = -1
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(_rng)
	var ch: CharacterData = Data.get_character2(character_id)
	if ch == null:
		var roster: Array = Data.all_characters2()
		ch = roster[0] if not roster.is_empty() else null
	GameLoop2.start_run(ch)
	# Belt and braces: whatever a run reset touches, this screen is still the
	# mounted overworld, and scrolls / overworld actives / saving all look it up.
	GameState.set_overworld_context(self)
	_dash_mode = false
	_dashed_here = false
	_scramble_salt = 0
	_banner.hide()
	_start_options = _build_start_options(pick)
	if _start_options.is_empty():
		# No graph to route (an empty / heavily filtered catalog): there is nothing
		# to choose between, so fall straight through to the ordinary offering
		# rather than parking the run on an empty panel.
		_phase = Phase.SELECT
		_build_choices()
		_refresh()
		return
	_phase = Phase.START_SELECT
	_refresh()
	_scroll_to_top()

# The choose-your-start cards from a RunGraph.pick_amulet_and_starts() result: the
# amulet is recorded on the run (hidden from the player — only the DISTANCE to it
# shows) and each option is resolved to its GameData. Options whose game is missing
# from the catalog are dropped rather than rendered as a blank card.
# Each option also carries the goal-enemy waiting at that game, because the start
# is now a game you PLAY rather than a doorstep you stand on (see choose_start) —
# and a card you are going to fight at has to say what is standing there before
# you press it, exactly as every other card in the run does.
func _build_start_options(pick: Dictionary) -> Array:
	var out: Array = []
	if pick.is_empty():
		return out
	GameState.amulet_game_id = StringName(pick.get("amulet_id", ""))
	for opt in pick.get("options", []):
		var g: GameData = Data.get_game(StringName(opt.get("start_id", "")))
		if g == null:
			continue
		out.append({
			"game": g,
			"type": int(opt.get("type", g.type)),
			"path_len": int(opt.get("path_len", 0)),
			"in_window": bool(opt.get("in_window", true)),
			# Rolled once, when the picker is built: a re-render must not reroll what
			# is waiting, or the card would say something different every repaint.
			# The run has not started, so this is always the Low tier and never a boss.
			"enemy": GameLoop2.roll_enemy(GameLoop2.game_type_key(g), _current_tier()),
		})
	return out

# One start option in the shape the offering's cards and GameChoiceModal read, so
# the whole of that machinery works on the picker without a second version of it.
# The start game is its own slot — nothing has been transmuted yet.
func _start_choice(index: int) -> Dictionary:
	if index < 0 or index >= _start_options.size():
		return {}
	var opt: Dictionary = _start_options[index]
	var game: GameData = opt["game"]
	return {
		"game": game, "enemy": opt.get("enemy"), "slot": game.id,
		"boss": false, "amulet": game.id == GameState.amulet_game_id,
		"repeat": GameState.has_played_game(game.id),
	}

# Clicking a start card opens the ordinary card popup over it — the enemy waiting
# there, its goal, the shields the game grants, the connections it opens onto, and
# the route from it. Bash and Transmute are withheld: they reshape an OFFERING,
# and the picker is three roads out of the same run rather than a table of cards
# that can be refilled.
func open_start_choice(index: int) -> GameChoiceModal:
	if _phase != Phase.START_SELECT or index < 0 or index >= _start_options.size():
		return null
	if _choice_modal != null and is_instance_valid(_choice_modal):
		return _choice_modal
	var opt: Dictionary = _start_options[index]
	var choice: Dictionary = _start_choice(index)
	var modal := GameChoiceModal.open(self, index, choice, {
		"route": {
			"text": _start_distance_text(int(opt["path_len"])),
			"tip": "The shortest route from %s to %s, the game this run ends on." % [
				opt["game"].display_name, amulet_name()],
			"color": UITheme.GOLD,
		},
		# The pace, stated ABSOLUTELY rather than as the offering's "speeds up /
		# slows down". There is nowhere to compare against yet — the run has no
		# position — and the amulet distances that comparison reads are not built
		# until the first offering is.
		"pace": _start_pace_note(int(opt["path_len"])),
		"shields": GameLoop2.shields_for_game(choice["game"]),
		"beatable": _beatable_row(choice),
		"escort": _escort_note(choice),
		"no_verbs": true,
		"action_text": "▶  Start at %s" % opt["game"].display_name,
		"action_tip": "Begin the run here — you go and play this game for real, right now.",
	})
	_choice_modal = modal
	modal.chose.connect(choose_start)
	modal.finished.connect(func(): _choice_modal = null)
	return modal

# turn_note's answer for a start: how fast the board runs at that distance from
# the Amulet, said outright. Same ladder, same colours — only the sentence is
# different, because there is no "here" to be faster or slower than.
func _start_pace_note(hops: int) -> Dictionary:
	var extra: int = RunDifficulty.extra_turns_for_hops(hops)
	return {
		"text": ("⏱ Reporting a game costs no turns there" if extra <= 0
			else "⏱ Reporting a game costs %s there" % RunDifficulty.extra_text(extra)),
		"color": RunDifficulty.band_color(extra),
		"turns": extra,
		"extra": extra,
		"tip": "Standing there, handing a game in gives the enemies %s.\n\n%s" % [
			RunDifficulty.extra_text(extra), RunDifficulty.ladder_text(extra)],
	}

# Take the offered start at `index` (choose-your-start, Phase.START_SELECT).
#
# The start used to be a doorstep: you landed on the game, nothing spawned, no
# shields were granted, and the run's first real game was whatever you travelled
# to from it. It is a GAME now — its goal-enemy spawns and stands on the board
# with the rest, it hands over its shields, and the run opens on the report panel
# with something to beat. Mechanically this is the commit half of `pick`, which
# is why it reads the same: one path, so a start and a travel cannot drift.
func choose_start(index: int) -> void:
	if _phase != Phase.START_SELECT or index < 0 or index >= _start_options.size():
		return
	var opt: Dictionary = _start_options[index]
	var game: GameData = opt["game"]
	GameState.start_game_id = game.id
	GameState.set_current_game(game.id)
	GameLog.add("Starting the run at %s (%s) — %d games from the Amulet." % [
		game.display_name, RunGraph.type_label(int(opt["type"])), int(opt["path_len"])],
		UITheme.GOLD)
	_chosen = _start_choice(index)
	_dashed_here = false
	_start_options.clear()
	# The offering behind the report panel is the start game's neighbours: the
	# checklist reads `_chosen`, but a Scramble or a Dash taken while playing needs
	# a table to act on, and so does the return from the report.
	_build_choices()
	if _chosen.get("enemy") != null:
		GameLoop2.choose_game(_chosen["enemy"],
			GameLoop2.game_type_key(game), _current_tier())
		_log_escort()
		var granted: int = GameLoop2.grant_selection_shields(game)
		GameLog.add("%s — %s, one hit stopped each." % [
			game.display_name, GameState.temp_shields_text(granted)],
			SHIELD_BLUE)
		_phase = Phase.PLAYING
		_populate_play_panel()
	else:
		# No goal-enemy could be rolled at all (an empty roster). There is nothing to
		# play for, so the start falls back to what it always was — a place to stand.
		_phase = Phase.SELECT
	_refresh()
	_scroll_to_top()
	# The run is now a real run — park a recovery point on it straight away.
	autosave()

# Resume a loaded save: the run state is already on GameState / GameLoop2 (see
# SaveSystem), so this only rebuilds the SCREEN over it. `view` is whatever
# capture_view_state() stored; an empty one (a save written outside the overworld,
# or a pre-2.0 save) falls back to a fresh offering at the saved position.
func resume_run(view: Dictionary) -> void:
	if view.is_empty():
		_phase = Phase.OVER if GameLoop2.run_over else Phase.SELECT
		_start_options.clear()
		_build_choices()
		_refresh()
		return
	restore_view_state(view)

# --- saving the run -------------------------------------------------------
#
# GameState + GameLoop2 hold the RUN (health, verbs, inventory, the enemy stack,
# the destroyed games); this screen holds the bit of it you can see — which cards
# are on the table, which game is in play, which drops are still unanswered. Neither
# half restores a usable run on its own, so the save carries both: SaveSystem
# writes the run and asks the mounted overworld for the view (capture_view_state),
# and a load hands the view back here (restore_view_state).

# One queued payout's entries, whichever shape it was queued in: a bare Dictionary
# (a game's own single piece) or an Array of them (a relic's grant). Deep-copied,
# because both sides of a save are handing the run its own state back.
func _loot_payload(raw) -> Variant:
	if raw is Array:
		var out: Array = []
		for entry in raw:
			if entry is Dictionary:
				out.append((entry as Dictionary).duplicate(true))
		return out
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}

func capture_view_state() -> Dictionary:
	var starts: Array = []
	for opt in _start_options:
		var sg: GameData = opt["game"]
		var se: GoalEnemyData = opt.get("enemy")
		starts.append({
			"game": String(sg.id), "type": int(opt["type"]),
			"path_len": int(opt["path_len"]), "in_window": bool(opt.get("in_window", true)),
			# The card says what is waiting at that start, and a save taken on the
			# picker has to come back saying the same thing.
			"enemy": String(se.id) if se != null else "",
		})
	var choices: Array = []
	for c in _choices:
		choices.append(_serialize_choice(c))
	var visits: Dictionary = {}
	for gid in _visits.keys():
		visits[String(gid)] = int(_visits[gid])
	# One entry per waiting CHEST, each an array of the ids it is offering — so a
	# boss's Medium chest comes back as the same two-item question after a reload
	# rather than collapsing into one. Older saves wrote a bare id per chest and
	# are read back as a chest of one (see the restore side).
	# A LOOT payout in the queue is saved as the entry itself rather than as a list
	# of ids — it is not an ItemData and has no catalogue row to be looked back up
	# by, since the horse roll on it already happened (§4.3).
	var drops: Array = []
	for d in _drop_queue:
		if d.has("loot"):
			# EITHER SHAPE. A game's own payout queues ONE entry (`_queue_loot_drop`)
			# and a relic's grant queues the whole handful (`_on_loot_offered`, which
			# is what Mom's Coin Purse pays) — LootDropModal has always taken both,
			# and this cast only ever saw the first. It threw on the second, taking
			# the autosave down with it, and the queue is only ever non-empty at a
			# save now that the post-combat screen hands its own drops back.
			drops.append({"loot": _loot_payload(d["loot"])})
			continue
		var ids: Array = []
		for it in _drop_items(d):
			ids.append(String((it as ItemData).id))
		drops.append(ids)
	return {
		"phase": _phase,
		"start_options": starts,
		"choices": choices,
		"chosen": _serialize_choice(_chosen),
		"boss_round": _boss_round,
		"dash_mode": _dash_mode,
		"dashed_here": _dashed_here,
		"scramble_salt": _scramble_salt,
		"return_choice": String(_return_choice),
		# The shop is a place on the page now, so a run saved standing in one comes
		# back standing in it (the shelf itself lives on GameState either way).
		"shop_open": String(_shop_panel.game_id()) if _shop_panel != null
			and is_instance_valid(_shop_panel) else "",
		"visits": visits,
		"drops": drops,
		"last_played_game": String(_last_played_game.id) if _last_played_game != null else "",
	}

func restore_view_state(view: Dictionary) -> void:
	_start_options.clear()
	for s in view.get("start_options", []):
		var sg: GameData = Data.get_game(StringName(s.get("game", "")))
		if sg != null:
			# A save written before starts carried an enemy (or one whose enemy has
			# left the catalog) rolls a fresh one rather than coming back to a card
			# with nothing standing on it.
			var se: GoalEnemyData = Data.get_goal_enemy_any(StringName(s.get("enemy", "")))
			if se == null:
				se = GameLoop2.roll_enemy(GameLoop2.game_type_key(sg), _current_tier())
			_start_options.append({
				"game": sg, "type": int(s.get("type", sg.type)),
				"path_len": int(s.get("path_len", 0)),
				"in_window": bool(s.get("in_window", true)),
				"enemy": se,
			})
	_choices.clear()
	for c in view.get("choices", []):
		var restored: Dictionary = _deserialize_choice(c)
		if not restored.is_empty():
			_choices.append(restored)
	_chosen = _deserialize_choice(view.get("chosen", {}))
	_boss_round = bool(view.get("boss_round", false))
	_dash_mode = bool(view.get("dash_mode", false))
	_dashed_here = bool(view.get("dashed_here", false))
	_scramble_salt = int(view.get("scramble_salt", 0))
	# A run saved on the stay-or-return screen comes back to it: `_choices` already
	# holds the two destination cards, and this is what makes them mean "move here"
	# rather than "travel and play".
	_return_choice = StringName(view.get("return_choice", ""))
	_visits.clear()
	var shop_open: StringName = StringName(view.get("shop_open", ""))
	if shop_open != &"":
		_mount_shop(shop_open)
	var vs: Dictionary = view.get("visits", {})
	for gid in vs.keys():
		_visits[StringName(gid)] = int(vs[gid])
	_drop_queue.clear()
	for raw in view.get("drops", []):
		if raw is Dictionary and (raw as Dictionary).has("loot"):
			_drop_queue.append({"loot": _loot_payload(raw["loot"])})
			continue
		# An older save wrote one id per chest; a current one writes the list the
		# chest is offering. Both land as a list here.
		var ids: Array = raw if raw is Array else [raw]
		var offer: Array = []
		for iid in ids:
			var it: ItemData = Data.get_item2(StringName(iid))
			if it == null:
				it = Data.get_item(StringName(iid))
			if it != null:
				offer.append(it)
		if not offer.is_empty():
			_drop_queue.append({"items": offer})
	_last_played_game = Data.get_game(StringName(view.get("last_played_game", "")))
	# The enemies behind the restored cards are the saved ones, so seed the slot
	# cache with them — otherwise the next repaint would roll new ones.
	_slot_enemies.clear()
	_slot_enemy_key = "%s|%d|%s" % [_offer_seed(), _current_tier(), str(_boss_round)]
	for c in _choices:
		var cg: GameData = c["game"]
		_slot_enemies["%s>%s" % [String(c["slot"]), String(cg.id)]] = c["enemy"]
	_phase = int(view.get("phase", Phase.SELECT))
	# A game recorded as in play whose card no longer resolves (content removed from
	# the catalog since the save) would leave the report step with nothing to report
	# on; drop back to choosing rather than to a broken panel.
	if _phase == Phase.PLAYING and _chosen.is_empty():
		_phase = Phase.SELECT
		_build_choices()
	if GameLoop2.run_over:
		_phase = Phase.OVER
	_banner.hide()
	if _phase == Phase.PLAYING:
		_populate_play_panel()
	_refresh()
	if _phase == Phase.OVER:
		if GameLoop2.won:
			_show_banner("🏆  You cleared the Amulet — you win!", Color(0.95, 0.8, 0.2))
		else:
			_show_banner("💀  Run lost — Health reached 0.", Color(0.9, 0.3, 0.25))
	_scroll_to_top()
	# A save taken with a drop still unanswered asks about it again on the way back
	# in — the question is the only place the item exists.
	_pump_drops()

# One offered card as plain data. The enemy's pool is recorded alongside its id
# because a goal-enemy and a boss can't be told apart by id alone on the way back.
func _serialize_choice(choice: Dictionary) -> Dictionary:
	if choice.is_empty():
		return {}
	var game: GameData = choice.get("game")
	var enemy: GoalEnemyData = choice.get("enemy")
	return {
		"slot": String(choice.get("slot", "")),
		"game": String(game.id) if game != null else "",
		"enemy": String(enemy.id) if enemy != null else "",
		"enemy_boss": enemy != null and enemy.is_boss(),
		"boss": bool(choice.get("boss", false)),
		"amulet": bool(choice.get("amulet", false)),
		"repeat": bool(choice.get("repeat", false)),
	}

func _deserialize_choice(raw) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var d: Dictionary = raw
	var game: GameData = Data.get_game(StringName(d.get("game", "")))
	if game == null:
		return {}
	var slot: String = String(d.get("slot", ""))
	return {
		"game": game,
		"enemy": Data.get_goal_enemy_any(StringName(d.get("enemy", ""))),
		"slot": StringName(slot if slot != "" else String(game.id)),
		"boss": bool(d.get("boss", false)),
		"amulet": bool(d.get("amulet", false)),
		"repeat": bool(d.get("repeat", false)),
	}

# The name a save defaults to: whatever this run was last saved as, else the
# character and where they are, which is what the Continue list shows anyway.
func default_save_name() -> String:
	if GameState.save_name.strip_edges() != "":
		return GameState.save_name
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	var who: String = ch.display_name if ch != null else "Run"
	var g: GameData = Data.get_game(GameState.current_game_id)
	return "%s — %s" % [who, g.display_name] if g != null else who

# Write the run to a named save. Returns false on a blank name or a failed write.
func save_run(save_name: String) -> bool:
	var nm: String = save_name.strip_edges()
	if nm == "":
		return false
	if not SaveSystem.save_named(nm):
		Notifications.notify("Couldn't write the save.", UITheme.DANGER)
		return false
	GameLog.add("Saved run as \"%s\"." % nm, UITheme.SUCCESS)
	Notifications.notify("Saved \"%s\"." % nm, UITheme.SUCCESS)
	return true

# The recovery point the run keeps on its own: rewritten every time the run
# actually moves — a start taken, a game picked, a game reported — so quitting or
# crashing costs at most the attempts logged since. A finished run clears it
# instead: Continue must never offer a run that's already over.
func autosave() -> void:
	if GameLoop2.run_over:
		SaveSystem.clear_autosave()
		return
	SaveSystem.autosave()

# The Save button: name the run, then write it. Re-saving under the same name
# overwrites, which is what "save my run" means the second time.
#
# `after_save` runs only if the write actually landed, which is what lets "Save &
# exit" be one press without ever quitting on top of a failed save — a blank name
# or an unwritable file leaves the player exactly where they were.
func prompt_save(after_save: Callable = Callable()) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Save run"
	dlg.ok_button_text = "Save"
	dlg.add_cancel_button("Cancel")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = "Name this save (an existing name is overwritten):"
	box.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = default_save_name()
	edit.custom_minimum_size = Vector2(360, 0)
	box.add_child(edit)
	dlg.add_child(box)
	dlg.register_text_enter(edit)
	dlg.confirmed.connect(func():
		var written: bool = save_run(edit.text)
		dlg.queue_free()
		if written and after_save.is_valid():
			after_save.call())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(440, 190))
	edit.grab_focus()
	edit.select_all()

# Open the offered game at `index` for inspection (§4). Clicking a card no longer
# commits to it: it raises GameChoiceModal, which shows the optimal path from that
# game drawn as the real route ladder, what is waiting there, what it costs, and
# the three buttons that answer the card — travel, bash, transmute.
#
# The modal decides nothing itself. Every answer comes straight back out to the
# public verb it was always spelled as (pick / bash_choice / transmute_choice), so
# the modal is a way of ASKING and nothing more, and a headless test can still
# drive the run by calling those verbs directly.
#
# Returns the modal (or null when there's nothing to open), so a test can answer
# it without a click.
func open_choice(index: int) -> GameChoiceModal:
	if _phase != Phase.SELECT or index < 0 or index >= _choices.size():
		return null
	if _choice_modal != null and is_instance_valid(_choice_modal):
		return _choice_modal
	var choice: Dictionary = _choices[index]
	var notes: Dictionary = {
		"route": route_note(choice),
		"pace": turn_note(choice),
		"shields": GameLoop2.shields_for_game(choice["game"]),
		"beatable": _beatable_row(choice),
		"enemy_hidden": _enemy_hidden(choice),
		"hidden_note": "The Runic Dome hides what is waiting there. You are routing on the game alone — the enemy, its goal and its damage are all found out on arrival.",
		"escort": _escort_note(choice),
	}
	# The stay-or-return question opens the same card for a different verb: it
	# MOVES the run rather than committing it to a game, so the card drops the two
	# things that would be lies on it (the enemy it would spawn, and the Bash /
	# Transmute that reshape an offering) and says what pressing it actually does.
	if _asking_return():
		var game: GameData = choice["game"]
		var staying: bool = bool(choice.get("stay", false))
		notes["move_only"] = true
		notes["action_text"] = ("▶  Stay at %s" if staying else "◀  Head back to %s") % game.display_name
		notes["action_tip"] = ("Carry on from here — the next offering is drawn from %s's neighbours."
			if staying else "Return to %s and carry on from there.") % game.display_name
		notes["move_note"] = ("You are already standing here. Nothing spawns — this only decides which game's neighbours the next offering is drawn from."
			if staying else "Nothing spawns on arrival. You go back to where the detour started and choose again from there.")
	var modal := GameChoiceModal.open(self, index, choice, notes)
	_choice_modal = modal
	modal.chose.connect(pick)
	modal.bashed.connect(bash_choice)
	modal.transmuted.connect(transmute_choice)
	modal.finished.connect(func(): _choice_modal = null)
	return modal

# Travel to the offered game at `index`: its goal-enemy spawns and we move there.
func pick(index: int) -> void:
	if _phase != Phase.SELECT or index < 0 or index >= _choices.size():
		return
	# The offering is showing the two ends of a detour rather than games to play,
	# so the same click means "stand here" instead of "go and play this" (§10).
	if _asking_return():
		_take_return_choice(index)
		return
	_chosen = _choices[index]
	# A Dash pick spends a charge (§4) — it's the "select any connected game" verb.
	_dashed_here = _dash_mode
	if _dash_mode:
		GameState.dash_charges = maxi(0, GameState.dash_charges - 1)
		_dash_mode = false
	# The GAME's type and the run's tier ride along so the escort (§7.5) is rolled
	# from the bucket this card's own enemy came out of. A transmuted card plays the
	# replacement game, so it is that game's type the escort answers to.
	GameLoop2.choose_game(_chosen["enemy"],
		GameLoop2.game_type_key(_chosen["game"]), _current_tier())
	_log_escort()
	# Selecting the game hands over your ARMOUR for it (§3): 3 shields, 5 for a
	# Traditional roguelike, plus whatever "when a game is selected" items add.
	var granted: int = GameLoop2.grant_selection_shields(_chosen["game"])
	GameLog.add("%s — %s, one hit stopped each." % [
		_chosen["game"].display_name, GameState.temp_shields_text(granted)],
		SHIELD_BLUE)
	# Move to the graph SLOT (a transmuted card plays an off-graph game but keeps
	# its position on the route toward the amulet).
	GameState.set_current_game(_chosen["slot"])
	if _offering != null:
		_offering.reset_hover_grant()
	# You have left the hub, so its shop comes off the page — the shelf itself
	# survives on ShopSystem, which is what makes coming back to it a real option.
	# The machines go too, and they do not survive: a Blood Donation Machine is
	# not a place you can come back to.
	_leave_node()
	# An armed verb doesn't survive committing to a game: the board it was aimed at
	# is about to be marched a column, and nothing has been spent either way.
	if _board != null:
		_board.cancel_push()
		_board.cancel_bomb()
		_board.cancel_item_aim()
	_phase = Phase.PLAYING
	_populate_play_panel()
	_refresh()
	# The board is the hero of the playing screen, so land on it: the page stays at
	# the top and the checklist under the grid is a scroll away.
	_scroll_to_top()
	# Committing to a game is a move worth recovering to — the shields it granted
	# and the lost runs you're about to log all hang off it.
	autosave()

# Say who came WITH the game's enemy (§7.5). Called at each of the three places a
# game is committed to, straight after choose_game, because the escort is the one
# thing about the board that the card could not tell you: it is rolled on arrival,
# so the player finds out here or not at all.
#
# It is a notification as well as a log line for that reason — the escort is the
# only body that appears without having been chosen, and a run of the log is not
# where a surprise should have to be noticed.
func _log_escort() -> void:
	var escort: GoalEnemyData = GameLoop2.escort_enemy()
	if escort == null:
		return
	var msg: String = "%s showed up too — it follows you until its goal is cleared." % escort.display_name
	GameLog.add(msg, UITheme.DANGER)
	Notifications.notify(msg, UITheme.DANGER)

# The attempt tracker (§3): the player ticks this every time they LOSE a run of
# the game they're playing. THE TICK COSTS A TURN OF THE BOARD — the enemies
# swing and close in, which can kill — and it costs nothing else: the shields are
# armour now, not tries, so failing at a game does not thin the wall you are
# about to meet the stack with (GameLoop2.log_attempt).
#
# A turn is the same beat the end of a game plays, so it is watched the same way:
# the positions are snapshotted first, the loop resolves, and the board replays
# the strike and the advance out of the snapshot (animate_resolve). `_resolving`
# goes up BEFORE the tick rather than after, because a lethal turn queues the
# end-of-run screen from inside it and that screen has to wait for the blow that
# caused it to land.
func log_attempt() -> String:
	if not GameLoop2.can_log_attempt():
		return ""
	var before: Dictionary = _board.capture_positions() if _board != null else {}
	var hp_before: int = GameState.hp
	_resolving = true
	_attempt_resolve = true
	var cost: String = GameLoop2.log_attempt()
	if cost == "":
		_resolving = false
		_attempt_resolve = false
		return ""
	var game: GameData = _chosen.get("game")
	_announce_attempt_turn(game.display_name if game != null else "this game",
		GameLoop2.last_attempt_turn)
	if GameLoop2.run_over:
		_phase = Phase.OVER
	_refresh()
	# Repaint first, then replay: the board is already in the state the turn left
	# it in, and the animation is how it got there (the same order report() uses).
	if _board != null:
		_hold_for_resolve(_board.animate_resolve(before, GameLoop2.last_attempt_turn, hp_before))
	else:
		_resolving = false
		_attempt_resolve = false
	return cost

# What a lost run just did. Two facts, because they are the two the player has to
# act on: the board took a turn (which is the price of every tick from the first
# one), and this is what that turn did — the Health it took, the shields that
# stopped it, or the fact that nobody was in reach and they all merely walked,
# which is the version that reads as "nothing happened" if it isn't said.
func _announce_attempt_turn(game_name: String, res: Dictionary) -> void:
	var took: int = int(res.get("damage_taken", 0))
	var blocked: int = int(res.get("blocked", 0))
	var msg: String = "Lost a run of %s (attempt %d) — the enemies take a turn." % [
		game_name, GameLoop2.attempts()]
	if took > 0:
		msg += " They hit you for %d." % took
	elif blocked > 0:
		msg += " Your shields stopped it."
	elif not (res.get("attacks", []) as Array).is_empty():
		msg += " Nothing landed."
	else:
		msg += " Nobody was in reach — they all close a column."
	GameLog.add(msg, UITheme.DANGER)
	Notifications.notify(msg, UITheme.DANGER)

# --- escaping a game you can't beat ---------------------------------------
#
# Some games won't go down, and a run shouldn't end because one of them sat in
# the way. The player may walk away from the game in play without beating it —
# ONCE IT HAS DRAWN BLOOD: the door opens the moment an enemy's attack takes
# Health off you during this game (GameLoop2.hurt_this_game), and it is open from
# the first second on a game this run has already beaten (see can_escape).
#
# THE GATE IS THE HIT, not a count of tries. It used to be five lost runs, from
# when a lost run spent a shield and then Health — a counter that stood in for
# "this game is hurting you" because nothing else measured it. Now the board
# measures it directly: a lost run hands the enemies a turn (§3.2), a Temporary
# Shield stops the first swings outright, and the door opens on the swing that
# gets past them. So the way out arrives exactly when the game has started
# costing you the one thing you cannot make more of, and never merely because you
# were patient.
#
# Escaping resolves the BOARD exactly as reporting a missed goal does: the
# goal-enemy walks onto the board and follows you, and every enemy already on it
# still takes its turns. That IS the price, and it has already been paid by the
# time the button appears. The button exists to make the way out VISIBLE to a
# stuck player, not to discount it.
#
# Where it PARTS from a missed report is the item trigger: the "after beating a
# game" items fire on any game FINISHED, win or lose, and an escape is the one
# report that doesn't fire them. Neither one banks a beat — beaten means won (see
# report) — so an escape and a miss are alike in earning no repeat-beat Dash, no
# Atlas mark and no movement in either beaten tally.
#
# THREE ways in.
#
# The HIT is for a game this run has never got through: the way out has to be
# earned, because the alternative is a player who quits the run instead.
#
# A game this run has ALREADY BEATEN is the opposite case — there is nothing left
# to prove, and being made to stand there and bleed to unlock the door is a tax
# on the one card the run cannot make interesting, so that door is open from the
# first second.
#
# AN EMPTY BOARD is the door that keeps the first one honest. Nothing on the
# board means nothing that can ever hurt you, so the hit gate could never open —
# a player standing on a game they cannot beat with a clear stack would be held
# there by a rule that was written to let them out. It costs them the same as any
# escape; there is simply nobody left for it to cost anything else.
#
# It is the same escape however you got in: the goal-enemy still follows you, the
# board still takes the turns the road charges for finishing a game (§7.4, which
# out in the wilds is none), and the game still isn't credited. Only the gate
# moves.
func can_escape() -> bool:
	if _phase != Phase.PLAYING or _chosen.is_empty() or GameLoop2.run_over:
		return false
	return beaten_this_run() or GameLoop2.hurt_this_game or GameLoop2.stack.is_empty()

# Whether the game in play is one this RUN has already beaten — won, with the
# goal met (see report(): "beaten means won").
#
# Run-scoped, not lifetime, and that is the point. A win in some run last week is
# not a fact about this one: the character is different, the board is different,
# and the shields this game grants have to be spent again either way. What the
# free escape is for is the REPEAT — the game already cleared earlier in this same
# run, the one the offering flags with ⚡ +1 DASH — because that is the card the
# run cannot make interesting a second time and the one it is pure grind to be
# held at.
func beaten_this_run() -> bool:
	var game: GameData = _chosen.get("game")
	return game != null and GameState.has_beaten_game(game.id)

# Leave the game in play. Whatever else the checklist has ticked still stands —
# a follower's goal you did clear, a level-up you did earn — because those are
# separate honour-system claims; escaping only answers the main goal, and it
# answers no.
#
# `force` skips the gate and nothing else. It is for the exits that are PAID FOR
# rather than earned — a teleport off the game (loot_teleport) is the only one
# today — so the price below is charged in full either way. The gate answers "has
# this game hurt you enough to deserve a way out"; a spent piece of loot is a
# different answer to the same question, not a way around the bill.
func escape_game(force: bool = false) -> void:
	if not force and not can_escape():
		return
	# Even forced, there has to BE a game in play to walk out of; report() would
	# refuse below anyway, and this keeps the log from announcing an escape that
	# never happened.
	if _phase != Phase.PLAYING or _chosen.is_empty() or GameLoop2.run_over:
		return
	var game: GameData = _chosen.get("game")
	var game_name: String = game.display_name if game != null else "this game"
	var tries: int = GameLoop2.attempts()
	var msg: String = ("Escaped %s — its enemy comes with you." % game_name if tries == 0
		else "Escaped %s after %d lost run%s — its enemy comes with you." % [
			game_name, tries, "" if tries == 1 else "s"])
	# Walking away is FINISHING a game as far as the road is concerned, so it is
	# charged for like one: the extra turns the Amulet's pull owes (§7.4) resolve
	# through the same report path a missed goal takes, below. Said out loud when
	# there are any, because "I escaped and then got hit twice" is otherwise a
	# surprise rather than a price.
	var extra: int = GameLoop2.enemy_turns()
	if extra > 0 and not GameLoop2.stack.is_empty():
		msg += " They still get %s on the way out." % RunDifficulty.extra_text(extra)
	GameLog.add(msg, UITheme.ACCENT)
	Notifications.notify(msg, UITheme.ACCENT)
	report(false, null, true)

# Take back the last tick — the tracker is hand-driven, so a mis-click has to be
# reversible. Puts the whole board the turn moved back where it was
# (GameLoop2._run_snapshot).
func undo_attempt() -> String:
	var cost: String = GameLoop2.undo_attempt()
	if cost == "":
		return ""
	# "shield" / "bonus" only come back from a save written when a try spent one
	# (GameLoop2.undo_attempt); a tick logged by this build always undoes a turn.
	var what: String = "the enemies' turn"
	if cost == "shield":
		what = GameState.temp_shields_text(1)
	elif cost == "bonus":
		what = GameState.shields_text(1)
	GameLog.add("Took back an attempt (%s)." % what, UITheme.TEXT_DIM)
	# The board is a different board now — bodies walked back, the ground it
	# burned is unburnt — so it is rebuilt rather than repainted in place.
	if cost == "turn" and _board != null:
		_board.clear_fx()
		_board.refresh()
	_refresh()
	return cost

# Dash (§4): a TOTAL select — bypass the limited offering and show every connected
# game so the player can move to any of them. Spends one dash charge on the pick.
func dash() -> void:
	if _asking_return():
		return
	if _phase != Phase.SELECT or GameState.dash_charges <= 0 or _dash_mode:
		return
	_dash_mode = true
	_build_choices()
	_refresh()

func cancel_dash() -> void:
	if not _dash_mode:
		return
	_dash_mode = false
	_build_choices()
	_refresh()

# Scramble (§4, granted by the D6): spend a charge to REROLL THE OFFERING — the
# games filling the three (or more, with a game_choices bonus) slots are drawn
# again from the reachable neighbours, each with a freshly-rolled goal-enemy. At a
# node with no more neighbours than the cap the slots can't change, so the reroll
# lands entirely on the enemies behind them; either way a scramble always changes
# what you're being offered. Returns true when a charge was spent.
func scramble() -> bool:
	if _asking_return():
		return false
	if _phase != Phase.SELECT or GameState.scramble <= 0 or _choices.is_empty():
		return false
	GameState.scramble -= 1
	_scramble_salt += 1
	# A transmute is pasted onto the NODE, not onto an offering, so re-drawing the
	# cards leaves it in place — the spot still plays the game you pasted there.
	_build_choices()
	GameLog.add("Scrambled the offering — %d new game(s) to choose from." % _choices.size(),
		Color(0.6, 0.75, 1.0))
	_refresh()
	return true

# --- the map ---------------------------------------------------------------
#
# "Map" means the STAR CHART with the route on it, and a movable window over the
# top holding the same route as a ladder of decisions. One route, drawn twice:
# the chart says where in the 751 games this corridor actually runs, the ladder
# says what the next three choices are. They're wired together — clicking a game
# on the ladder flies the chart to it, and the ladder's ⌖ button puts the whole
# corridor back in frame — and the window drags out of the way by its header,
# since the sky underneath stays live.

# The run's own map: from where the player stands to the Amulet, with the games
# currently on offer flagged.
func open_map() -> Node:
	var choice_ids: Array = []
	for c in _choices:
		choice_ids.append(c["slot"])
	return _open_route_map(GameState.current_game_id, choice_ids, {})

# The same map for a game you have NOT taken: the optimal road to the Amulet as
# it would stand if you picked this card. Every offered game carries a 🗺 button
# above its cover, because the whole decision is a routing decision and it
# shouldn't have to be made from a single distance number.
#
# The START PICKER's map is the LADDER ALONE — no star chart under it.
#
# It used to withhold the destination as well, which is over: the Amulet is named
# here like everywhere else (amulet_name). What it still withholds is the SKY. The
# question being asked on that panel is "which of these three roads do I want",
# and the answer to it is the ladder: seven rungs, in order, with the branch
# points on them. Raising the whole 852-star chart to answer it hands the player a
# galaxy to pan around before they have taken a single step — and the panel behind
# is the one screen where there is nothing on the chart to orient by, since the
# run has no position yet. The chart is one button away on the window itself
# (✦ Star chart) for anyone who wants it.
func preview_map(game_id: StringName) -> Node:
	if game_id == &"" or GameState.amulet_game_id == &"":
		return null
	var game: GameData = Data.get_game(game_id)
	return _open_route_map(game_id, [], {
		"preview": true,
		"chart": _phase != Phase.START_SELECT,
		"title": "🗺  If you take %s" % (game.display_name if game != null else String(game_id)),
	})

func _open_route_map(origin: StringName, choice_ids: Array, options: Dictionary) -> Node:
	var opts: Dictionary = options.duplicate()
	var wants_chart: bool = bool(opts.get("chart", true)) and AtlasView.load_layout() != null
	opts.erase("chart")
	if wants_chart:
		var atlas := AtlasView.new()
		# A preview routes the sky from the game being considered rather than from
		# where the player stands, so the corridor drawn on the chart is the one
		# the card is offering.
		if bool(opts.get("preview", false)):
			atlas.preview_origin = origin
		add_child(atlas)
		opts["atlas"] = atlas
		var modal := preload("res://scripts/redesign2/RunMapModal.gd").new()
		# Mounted UNDER the chart, so closing the chart takes its window with it.
		# The window frames the route on the chart itself, once it knows how much
		# of the sky it's covering.
		modal.start(atlas, origin, GameState.amulet_game_id, choice_ids, opts)
		return modal
	var solo := preload("res://scripts/redesign2/RunMapModal.gd").new()
	solo.start(self, origin, GameState.amulet_game_id, choice_ids, opts)
	return solo

# --- routing: how each offered card sits relative to the Amulet -------------
#
# Distances to the Amulet over the run's graph — the same BFS the "Map to the
# Amulet" modal is layered from, so a card's badge and the map it opens can never
# disagree. (Bashing removes a game from the OFFERING, not from the graph, so it
# doesn't move these numbers; RunGraph memoizes the BFS, and this is re-read with
# each offering so a change of amulet or game filter is picked up.)
func _rebuild_amulet_distances() -> void:
	_amulet_dist = {}
	if GameState.amulet_game_id == &"":
		return
	_amulet_dist = RunGraph.bfs_distances(GameState.amulet_game_id)

# Hops from `game_id` to the Amulet, or -1 when no route reaches it.
func steps_to_amulet(game_id: StringName) -> int:
	if game_id == &"":
		return -1
	if _amulet_dist.is_empty():
		_rebuild_amulet_distances()
	return int(_amulet_dist[game_id]) if _amulet_dist.has(game_id) else -1

# What a card is, as a route: is it the Amulet, does it step toward it, or does
# it cost you ground? Returned as {"text", "color", "tip"} so the card and its
# tests read the same words.
func route_note(choice: Dictionary) -> Dictionary:
	var slot: StringName = choice.get("slot", &"")
	if bool(choice.get("amulet", false)):
		return {
			"text": "🏆 THE AMULET — the run ends here",
			"color": UITheme.GOLD,
			"tip": "Beat this game's goal and you win the run.",
		}
	var here: int = steps_to_amulet(GameState.current_game_id)
	var there: int = steps_to_amulet(slot)
	if there < 0:
		return {
			"text": "⛔ No route to the Amulet",
			"color": UITheme.DANGER,
			"tip": "Nothing connects this game to the Amulet any more.",
		}
	var plural: String = "" if there == 1 else "s"
	if here >= 0 and there < here:
		return {
			"text": "★ OPTIMAL — %d step%s left" % [there, plural],
			"color": UITheme.SUCCESS,
			"tip": "On a shortest path: taking this leaves %d step%s to the Amulet." % [there, plural],
		}
	if here >= 0 and there == here:
		return {
			"text": "→ Sideways — still %d step%s" % [there, plural],
			"color": UITheme.TEXT_DIM,
			"tip": "No closer, no further: %d step%s to the Amulet either way." % [there, plural],
		}
	var lost: int = there - here if here >= 0 else 0
	return {
		"text": "↩ Detour +%d — %d step%s left" % [lost, there, plural],
		"color": UITheme.ACCENT,
		"tip": "This walks away from the Amulet: %d step%s left instead of %d." % [
			there, plural, maxi(here - 1, 0)],
	}

# What taking this card does to the PACE of the board (§7.4). The route badge
# above says how much ground a card gives or takes; this says what that ground
# costs, because the two are the same decision: every step toward the Amulet is a
# step toward enemies that take EXTRA TURNS every time you hand a game in.
#
# Out in the wilds that price is zero — reporting a game moves nobody, and the
# only thing that does is losing runs at it (§3.2). So the card is quoting what
# this stretch of road charges on top of your own failures.
#
# Returned as {"text", "color", "tip", "turns", "extra"} — same shape as
# route_note. `turns` and `extra` are the same number (every turn the end of a
# game hands out is an extra one now); both are there so a caller can ask for
# either without knowing that, and a test can assert the number without parsing
# the sentence.
func turn_note(choice: Dictionary) -> Dictionary:
	var here: int = steps_to_amulet(GameState.current_game_id)
	var there: int = steps_to_amulet(choice.get("slot", &""))
	# The Amulet card ends the run on the spot: what the enemies would have done
	# afterwards is moot, and saying "+2 extra turns" there would just be alarming.
	if bool(choice.get("amulet", false)):
		there = 0
	var now: int = RunDifficulty.extra_turns_for_hops(here)
	var then: int = RunDifficulty.extra_turns_for_hops(there)
	var color: Color = RunDifficulty.band_color(then)
	var tip: String = ("Standing there, handing a game in gives the enemies %s.\n\n%s"
		% [RunDifficulty.extra_text(then), RunDifficulty.ladder_text(then)])
	if bool(choice.get("amulet", false)):
		return {"text": "", "color": color, "tip": tip, "turns": then, "extra": then}
	if then > now:
		return {
			"text": "⏱ Enemies speed up — %s" % RunDifficulty.extra_text(then),
			"color": color, "turns": then, "extra": then,
			"tip": "Closing on the Amulet is what wakes them up: %s here, %s there.\n\n%s"
				% [RunDifficulty.extra_text(now), RunDifficulty.extra_text(then),
					RunDifficulty.ladder_text(then)],
		}
	if then < now:
		return {
			"text": "⏱ Enemies slow down — %s" % RunDifficulty.extra_text(then),
			"color": color, "turns": then, "extra": then,
			"tip": "Backing off buys you pace: %s here, %s there.\n\n%s"
				% [RunDifficulty.extra_text(now), RunDifficulty.extra_text(then),
					RunDifficulty.ladder_text(then)],
		}
	return {
		"text": "⏱ Still %s" % RunDifficulty.extra_text(then),
		"color": UITheme.TEXT_DIM, "turns": then, "extra": then, "tip": tip,
	}

# Spend the carried piece of loot at index `idx` (the loot window's Use button).
# Opens the one modal both kinds share, which consumes the entry, resolves it
# through its own system and fires Echo Chamber's copies (§4.1 / §4.3).
#
# ONE ENTRY POINT for scrolls and pills alike: the echo means using either kind
# can replay the other, so a path that only knew about scrolls would drop half of
# what its own use just did.
func use_loot(idx: int) -> void:
	var modal := preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.finished.connect(_refresh)
	modal.start(self, idx, self)

# The old name for it, kept because the scroll panel's tests and DevTools' grant
# path both say "read the scroll at this index" and mean exactly this.
func read_scroll(idx: int) -> void:
	use_loot(idx)

# A piece of loot asked to MOVE you (§4.1 Scroll of Teleportation, §4.3
# Telepills). Two shapes of landing zone, and the difference is the whole reason
# the horse dose is worth the 5% roll:
#
#   spread — a band around where you STAND: ~the same distance from the Amulet as
#            you already are, ±spread. Wherever you were in the run, you are still
#            about that far from the end of it.
#   amulet — a band around the AMULET itself, min..max steps out, regardless of
#            where you were. This is the only movement in the game that can drop
#            you next to the goal, which is why it is spelled as its own word
#            rather than as a `spread` with a big number.
#
# Both exclude the current game and the Amulet, and both fall back to any
# reachable node when their band is empty.
#
# IT ANSWERS IN WORDS, and the caller says them. A teleport is the one op on either
# consumable that resolves nowhere near the system that owns it — `read_scroll` and
# `take_pill` hand back a REQUEST and are finished — so the line that says where
# you ended up can only come from here. Returning it rather than only logging it is
# what lets the use modal's outcome screen report a Telepill at all: without it,
# the one piece of loot that moves you was also the one that said nothing about
# what it just did (see LootUseModal._do_teleport). "" means it never fired.
# The teleport had nowhere to put you. One sentence, and which one depends on
# whether an escape was bought on the way in: a fizzle after an escape is not a
# no-op, and a player told only "nothing happened" over a board that just took
# its turns has been told the wrong thing.
func _nowhere_to_go(escaped_out: bool) -> String:
	if escaped_out:
		return "You walk out of the game — but the teleport fizzles, and you stay put."
	return "The teleport fizzles — nowhere to go."

func loot_teleport(req: Dictionary) -> String:
	# A GAME IN PLAY IS ESCAPED, NOT A REASON TO FIZZLE. This used to return ""
	# mid-game on the grounds that moving the run while the player is halfway
	# through a game is not a thing the loop can mean. It is — it is called
	# escaping, the loop has had a word for it since it shipped, and walking out
	# of a game you cannot beat is the most useful moment a teleport will ever
	# have. So the teleport takes the way out on the player's behalf and then
	# moves them.
	#
	# IT FORCES THE ESCAPE PAST can_escape(). The ordinary gate wants the game to
	# have drawn blood first, so the exit is earned rather than free; a teleport
	# IS what earns it — the run spent a piece of loot on the door. What it does
	# NOT do is discount the escape's price: the goal-enemy still walks on and
	# follows you, the board still takes the turns finishing a game owes (§7.4),
	# and the game is still not credited. You are buying the exit, not a pardon.
	#
	# Both consumables that teleport come through here (Scroll of Teleportation
	# and the Telepill), so both escape. One rule for moving the run off a game.
	var escaped_out: bool = false
	if _phase == Phase.PLAYING:
		var leaving: GameData = _chosen.get("game")
		escape_game(true)
		# escape_game refuses on an empty _chosen; only claim the escape if the
		# phase actually moved, or a fizzle below would report one that never was.
		escaped_out = _phase != Phase.PLAYING
		# The way out can be the thing that kills you: escaping resolves the board,
		# and the turns it hands over are real. A run that ended on the way out has
		# nowhere to be teleported to, and the escape's own line is the last word.
		if GameLoop2.run_over or _phase == Phase.OVER:
			return "You escape %s — but you do not get out." % (
				leaving.display_name if leaving != null else "the game")
	# THE TWO "NO MAP TO MOVE ON" EXITS ALSO HAVE TO CARRY THE ESCAPE. "" is this
	# function's word for "it never fired", and the use screen turns it into "it
	# fizzles — you do not move" — which after an escape is a lie by omission: the
	# game WAS walked out of and the board took its turns for it.
	var amulet: StringName = GameState.amulet_game_id
	if amulet == &"":
		return _nowhere_to_go(escaped_out)
	var dist: Dictionary = RunGraph.bfs_distances(amulet)
	var cur: StringName = GameState.current_game_id
	if not dist.has(cur):
		return _nowhere_to_go(escaped_out)
	var to_amulet: bool = String(req.get("dir", "same")) == "amulet"
	var spread: int = int(req.get("spread", 1))
	var near: int = int(req.get("min", 1))
	var far: int = int(req.get("max", 3))
	var cur_d: int = int(dist[cur])
	var band: Array = []
	var any: Array = []
	for gid in dist.keys():
		if gid == cur or gid == amulet or GameLoop2.is_bashed(gid):
			continue
		any.append(gid)
		var d: int = int(dist[gid])
		if to_amulet:
			if d >= near and d <= far:
				band.append(gid)
		elif absi(d - cur_d) <= spread:
			band.append(gid)
	var pool: Array = band if not band.is_empty() else any
	if pool.is_empty():
		var fizzle: String = _nowhere_to_go(escaped_out)
		GameLog.add(fizzle, Color(0.61, 0.35, 0.71))
		return fizzle
	var dest: StringName = pool[_rng.randi() % pool.size()]
	GameState.set_current_game(dest)
	var g: GameData = Data.get_game(dest)
	# HOW FAR OUT IT PUT YOU, not only where. Distance from the Amulet is the fact
	# the whole op is about — `spread` keeps you about where you were and `amulet`
	# is the one move in the game that can drop you on the doorstep — and a landing
	# reported as a game's name alone is the half that doesn't say which happened.
	var landed := "Teleported to %s — %d step%s from the Amulet." % [
		g.display_name if g != null else String(dest),
		int(dist.get(dest, 0)), "" if int(dist.get(dest, 0)) == 1 else "s"]
	# Said on the outcome screen as well as in the log, because escaping is the
	# expensive half of what just happened and the modal only ever shows this
	# string. escape_game's own line went to the log and the notification toast;
	# this is the reader's copy of it, on the screen they are actually looking at.
	if escaped_out:
		landed = "You walk out of the game. " + landed
	GameLog.add(landed, Color(0.61, 0.35, 0.71))
	_dash_mode = false
	_build_choices()
	_refresh()
	return landed

# Report the outcome of actually playing the chosen game (the honour-system
# self-report). `fulfilled` is the list of enemy instances whose goals you
# cleared this game (§2) — every body on the board is a candidate, the ones that
# walked on when you took this game included — and each is hit, defeated and
# dropping at 0 Health. When null the ticked checkboxes are read from the play
# panel. Resolves the loop, advances the difficulty clock, then rebuilds the next
# offering.
#
# `escaped` marks the report as WALKING AWAY (escape_game) rather than finishing:
# the board still resolves and the run still moves on, but the game is not
# credited as beaten — see the `if not escaped` block below for exactly what that
# withholds.
# `beaten` is the honour-system answer to the only question this app actually
# asks: did you complete the real video game? It is what "✓ Completed Game"
# presses, and it drives the RECORD half of the report — the run's beaten set, the
# repeat-visit Dash, the lifetime tally, the Amulet win.
#
# It has nothing to do with the enemies. Clearing a goal is ticking that enemy's
# row (`fulfilled`), and beating the game clears nothing by itself — the two used
# to be one flag, back when the body standing there was the game's own and beating
# the game answered for it (GameLoop2.arrivals). So you can beat a game and leave
# everything on the board following you, or clear three old goals during a game
# you never finished, and the report says exactly that.
func report(beaten: bool, fulfilled: Variant = null, escaped: bool = false) -> void:
	if _phase != Phase.PLAYING or _chosen.is_empty():
		return
	# The board is about to play the whole resolve back — the front line striking,
	# the field closing in one column. Hold the screen on it: the run's state moves
	# on immediately (so nothing here waits on an animation), but the OFFERING
	# doesn't come back until the playback has finished. See _end_resolve.
	_resolving = true
	var played_game: GameData = _chosen.get("game")
	var fulfilled_instances: Array = fulfilled if fulfilled is Array else _ticked_fulfilments()
	var was_amulet: bool = bool(_chosen.get("amulet", false))
	# Had the run been to this game before? Read BEFORE this visit is recorded, so
	# it is the SECOND trip to a game that pays the Dash (REPEAT_BEAT_DASH).
	#
	# PLAYED before, not beaten before. Walking back to a game you failed is the
	# same journey as walking back to one you cleared, and the Dash is paid for
	# making it; what has to be earned on the return trip is the goal (see the
	# grant below, which still wants this visit to be a real win).
	var repeat_beat: bool = played_game != null and GameState.has_played_game(played_game.id)
	# The event standing at this SPOT, read before _chosen is cleared. Keyed off
	# the graph slot rather than the game, because an event belongs to the place
	# (a dead end, §1) — a transmuted card plays a different game on the same node.
	var slot_here: StringName = StringName(_chosen.get("slot", &""))
	# …unless the level was already TAKEN mid-game (§2.1). Ticking that row is a
	# confirm and it applies on the spot, so a locked box has been paid for and the
	# report must not pay for it twice. `disabled` is the mark of a resolved row
	# (ReportChecklist._lock_row).
	var leveled: bool = _levelup_check != null and _levelup_check.button_pressed \
		and not _levelup_check.disabled
	# Snapshot where everyone stands BEFORE the resolve, so the animation can play
	# the strike and the advance back from the old positions to the new ones.
	var before: Dictionary = _board.capture_positions()
	# …and how much Health was standing before any of them swung, so the board can
	# take it down one strike at a time instead of showing the total up front.
	var hp_before: int = GameState.hp
	# And what tier / board this game was fought on, so the step into the next one
	# can be announced rather than just silently happening (§7.3).
	var tier_before: int = _current_tier()
	var board_before := Vector2i(GameLoop2.grid_cols(), GameLoop2.grid_rows())
	_close_enemy_info()
	# The status half of the same self-report (§13): the player-buff goals ticked
	# and the enemy bonuses claimed. Read here, alongside the fulfilments, because
	# _end_resolve rebuilds the checklist and frees the boxes.
	var claims: Dictionary = _ticked_status_claims()
	# WHO is behind each ticked instance, read BEFORE the resolve. beat_game takes
	# a defeated body off the stack, so looking the instance up afterwards finds
	# nothing — which is exactly the enemies worth recording.
	var ticked_enemies: Dictionary = {}
	for inst in fulfilled_instances:
		for entry in GameLoop2.stack:
			if int(entry.get("instance", -1)) == int(inst):
				ticked_enemies[int(inst)] = entry.get("enemy")
				break
	# `clear_advertised` is false and always will be from here: the overworld's
	# checklist lists the bodies that walked on this game among all the others, so
	# they are already in `fulfilled_instances` if the player ticked them.
	var res: Dictionary = GameLoop2.beat_game(false, fulfilled_instances, claims)
	# THE FLOOR IS SWEPT AT THE REPORT (§8.2). Loot lying on the board belongs to
	# the game being played; handing the game in ends that, so anything nobody
	# stopped to pick up — including whatever the bodies this very report cleared
	# just dropped — goes onto the haul screen instead of sitting on a board the
	# next game rebuilds.
	_sweep_floor_into_the_queue()
	# …and the relic chest the evening earned, scaled by how much was killed and
	# how hard it was, paid only for a game you actually BEAT (§8.2). An escape is
	# not a win: the player walked away, and the bodies they cleared on the way out
	# keep their loot but buy no chest.
	_queue_report_chests(beaten and not escaped)
	# What a status charged for a game it went unanswered (§13, Burn). GameLoop2 is
	# a model node and says nothing to the player, so the bite is announced here,
	# on the same terms as a curse's.
	_announce_status_penalties(res)
	# "After beating a game" is the dominant 2.0 item trigger (§8): fire it now so
	# owned items react (Burning Blood +1 Health, Meat on the Bone's conditional
	# heal), the Harvesting stat pays out, charged actives tick, and the toast
	# shows. Defeated-enemy drops were already banked by beat_game above.
	# Remember WHICH enemies fell at this game, so the Atlas can list them later
	# alongside whatever the player wrote about them.
	# Every defeat is banked twice: against the GAME it happened at (the Atlas's
	# "enemies beaten in <game>") and against the CHARACTER who did it (the
	# roster's trophy shelf). One call site, so the two can't disagree.
	# One loop, because there is one kind of defeat: whatever you cleared, it was
	# cleared AT this game. The body that walked on when you took it used to be
	# recorded separately, off the `goal_met` flag, and that is gone with the flag.
	# Read off the snapshot taken before the resolve, not off the stack — the ones
	# worth recording are precisely the ones no longer standing on it.
	if played_game != null:
		for inst in ticked_enemies:
			var cleared: GoalEnemyData = ticked_enemies[inst]
			if cleared != null:
				_record_defeat(played_game, cleared)
	# Everything a game gets CREDITED for. An escape is the one report that earns
	# none of it: the player walked away, so the "after beating a game" items don't
	# fire and nothing about the game is banked. The run itself still advances —
	# see games_played below — because the time was spent and the board closed in
	# regardless.
	# Was this game a play_game DETOUR (§10)? A detour is not an arrival: the run
	# was sent to a game off its route by an event it has already resolved, and the
	# far side of it is the stay-or-return question, not a fresh node's contents.
	var on_detour: bool = _play_return_to != &""
	# The event, rolled here and queued for once the board stops moving. An event
	# fires after EVERY game — including one the player escaped and one whose goal
	# they missed, because the time was spent either way and the event is what the
	# run does between hour-long roguelikes rather than a prize for winning.
	#
	# NEVER on a detour, though. A detour's destination is a game the run was
	# posted to by the last event; letting that game hand over an event of its own
	# chained one straight into the next and dropped it on top of the stay-or-
	# return question. (Punch Off's "I Can Take Them" is the case that showed it:
	# beat the mecha game, get asked whether to stay, and get a second event over
	# the top of the asking.)
	if played_game != null and not on_detour:
		_pending_event = EventSystem.roll_for_arrival(slot_here)
		_pending_event_node = slot_here
	if played_game != null and not escaped:
		# The shop, if this was one of the run's ten hubs (§14). Queued on
		# exactly the same terms, and read off the GAME rather than the graph slot:
		# a shop belongs to the storefront of a particular big game, so a node
		# transmuted into something else is not that shop any more.
		if ShopSystem.is_hub(played_game.id):
			_pending_shop = played_game.id
		# The item trigger fires on FINISHING a game, win or lose. Note that this
		# is deliberately a wider net than the beat below: it is what paces the
		# "after beating a game" items, and every one of them is balanced around
		# firing once per game played.
		TriggerBus.game_beaten.emit({"game_id": played_game.id})
		# THE GAME'S OWN LOOT (§4.3): one piece, a straight 50/50 between a scroll
		# and a pill, asked about the way a kill drop is. On the same terms as the
		# trigger above — any game seen through, win or lose — because what it pays
		# for is the evening spent on it. An ESCAPE is the one report that earns
		# none of it, which is why this sits inside the `not escaped` block.
		_queue_loot_drop()

	# WHERE THE RUN HAS BEEN. Every report is a game played, whatever it said: a
	# missed goal was still an evening spent on that game, and so was walking away
	# from it. This is what the offering's ⚡ badge and the returning Dash read
	# (has_played_game), and it is deliberately a wider net than the beat below.
	if played_game != null:
		GameState.note_game_played(played_game.id)

	# BEATEN MEANS WON. This block used to sit inside the one above — any report
	# that wasn't an escape banked the game, a missed goal included — so "⚔ Beaten
	# 11 times" counted visits, `has_beaten_game` meant "been here", and a game you
	# had failed counted as a win in the UI. Every one of those reads as a claim
	# about winning, so all of them require the goal to have actually been met.
	#
	# Recorded after the item trigger above, so a game_beaten item can't see a
	# half-updated tally.
	if played_game != null and not escaped and beaten:
		# The run's own record: what the Atlas's "beaten this run" and the free
		# escape (can_escape) read. Run-scoped and wiped by reset_run — beating
		# something in a previous run is not a fact about this one.
		GameState.note_game_beaten(played_game.id)
		# …and the reward for coming back: a game the run had already played,
		# beaten this time (§4). The trip is what earns it, the win is what
		# confirms it.
		if repeat_beat:
			_grant_repeat_dash(played_game, _dashed_here)
		# The lifetime tally the Collection, the tier list and the Atlas read
		# ("beaten N times"). An amulet clear records the win instead — it bumps
		# `beaten` too.
		if was_amulet:
			GameStats.record_amulet_win(played_game.id)
		else:
			GameStats.record_beaten(played_game.id)
	elif played_game != null and not escaped and was_amulet:
		# The Amulet game finished WITHOUT its enemy's goal: still the run's win
		# (see the was_amulet branch below), so it is still the game the win goes
		# on the record against.
		GameStats.record_amulet_win(played_game.id)
	# Level up (§3.1) — a fresh chance each game; skipped if the game just killed
	# the player.
	if leveled and not GameLoop2.run_over:
		_apply_level_up()
		# Which game the level was taken at, so the character's page can list it
		# beside whatever the player wrote about doing it here.
		if played_game != null:
			GameStats.record_level_up(played_game.id, GameState.character_id)
	# The event/curse half of the same honour-system report (§5): claim the event
	# goals the player ticked and pay out the curses they owned up to. Read before
	# games_played moves, because the tick below is what ages them.
	_resolve_event_goal_rows()
	GameState.games_played += 1
	# Both kinds of standing objective age by one game. An expired event goal gets
	# its "missed" line; an expired curse says nothing, because nothing happened.
	for expired in GameState.tick_event_goals():
		var src: EventData2 = Data.get_event2(StringName(expired.get("event", &"")))
		if src != null and src.goal_missed != "":
			Notifications.notify(src.goal_missed, UITheme.DANGER)
			GameLog.add(src.goal_missed, UITheme.DANGER)
	# That count is what the difficulty tier is read off, so the board may have
	# just grown under the bodies standing on it (§7.3). Reconcile it and say so.
	if not GameLoop2.run_over:
		_announce_difficulty_step(tier_before, board_before)
	_chosen = {}
	# Rating is a BUTTON, never a pop-up: remember the game so the "★ Rate <game>"
	# button on the select screen can score it whenever the player feels like it.
	if played_game != null:
		_last_played_game = played_game
	if GameLoop2.run_over:
		_phase = Phase.OVER
		_refresh()
		# Repaint first, then replay the strike + advance from the snapshot: the
		# board is already in its final state, the animation just shows how it got
		# there. The end-of-run screen waits for it to land (_end_resolve).
		_hold_for_resolve(_board.animate_resolve(before, res, hp_before))
		return
	if was_amulet:
		# REACHING the Amulet game and playing it IS the run. It used to also
		# require the goal box — the goal-enemy standing there had to have its
		# condition met as well — so a player who got all the way to the Amulet
		# game and beat it, but hadn't happened to "destroy an enemy spawner"
		# while doing it, watched the run carry on as if nothing had happened.
		# The whole run is a search for one game; arriving and playing it is the
		# answer. The enemy's goal is a bonus on top, not the lock on the door.
		#
		# Winning ends the run through GameLoop2 (-> _on_run_won), and the last
		# advance still deserves to be seen before the win screen.
		GameLoop2.clear_amulet()
		_hold_for_resolve(_board.animate_resolve(before, res, hp_before))
		return
	_phase = Phase.SELECT
	_build_choices()
	_refresh()
	# The run moved, so the recovery point moves with it.
	autosave()
	# A play_game detour ends here (§10) — but it QUEUES rather than resolving on
	# the spot. Its payout and its stay-or-return question both belong on a screen
	# the player can see, and at this moment the board is still playing the resolve
	# back, so it waits behind that exactly as an event and a shop do (_end_resolve).
	if on_detour:
		_pending_detour = true
		_detour_beaten = not escaped
	# WHAT THIS REPORT WAS, for the screen the game ends on (_open_post_game).
	# Recorded here, on the one path that survives the report — a run that ended
	# and a run that just won have their own screen and took the two `return`s
	# above — and read once the board has finished playing the resolve back.
	_post_snapshot = {
		"game": played_game, "beaten": beaten, "escaped": escaped,
		"amulet": was_amulet, "res": res,
		"tier_before": tier_before, "board_before": board_before,
	}
	_hold_for_resolve(_board.animate_resolve(before, res, hp_before))

# The run just stepped up a difficulty tier, which widens the battlefield by a
# column and a row (§7.3). Reconcile the board's coordinates with its new size
# and announce BOTH halves of the step, because they pull in opposite directions
# and a player who only notices one will misread the other: the enemies get
# heavier, and the ground you have to lose before they reach you gets deeper.
#
# The new cells light up and pulse on the board itself (BattlefieldView's
# _rebuild_cells) — this is the words that go with them.
func _announce_difficulty_step(tier_before: int, board_before: Vector2i) -> void:
	var tier_now: int = RunDifficulty.tier_for(GameState.games_played)
	if tier_now == tier_before:
		return
	# Re-seat anything the old bounds had parked off-grid: a wider board is
	# somewhere for the overflow queue to finally stand.
	GameLoop2.sync_grid_bounds()
	var board_now := Vector2i(GameLoop2.grid_cols(), GameLoop2.grid_rows())
	var msg: String = "Difficulty up — %s." % RunDifficulty.tier_name(tier_now)
	if board_now != board_before:
		msg += " The battlefield grows to %d×%d." % [board_now.x, board_now.y]
	Notifications.notify(msg, UITheme.GOLD)
	GameLog.add(msg, UITheme.GOLD)

# --- waiting out the board's playback --------------------------------------
#
# The resolve animation is the only place the run's consequences are ever SHOWN:
# what hit you, what closed in. The run's state moves on the instant the game is
# reported (nothing here waits on a tween) and so does the SCREEN — the next
# offering is already back on the left of the page while the board plays the
# strikes and the advance out on the right. The two halves are side by side, so
# neither has to wait for the other, and there is nothing to press in between.
#
# What IS still held back is the end-of-run screen: the blow that killed you is
# the last thing worth watching, and a verdict dropped on top of it wipes it off
# mid-flight. That's what `_resolving` marks now.

func _hold_for_resolve(seconds: float) -> void:
	if seconds <= 0.0 or not is_inside_tree():
		_end_resolve()
		return
	# process_always, so a resolve that opens a modal (a reward chest pausing the
	# tree) still finishes rather than stranding the screen mid-animation.
	get_tree().create_timer(seconds, true, false, true).timeout.connect(_end_resolve)

# The board has finished: hand the screen over to whatever the playback was
# standing in front of — today, only the end-of-run screen.
func _end_resolve() -> void:
	if not _resolving:
		return
	_resolving = false
	_refresh_stage()
	# The tracker's buttons go dead for the length of a playback (a second tick
	# mid-animation would be resolving a turn onto a board still sliding through
	# the last one), so the flag coming down has to repaint them. Without this a
	# lost run's own playback left "Lost a run" and "Undo" greyed until something
	# else happened to refresh the page.
	_refresh_attempts()
	# A pickup during the playback deferred its board repaint to here (see
	# _on_inventory_changed) — the board is the player's again now.
	if _board_dirty:
		_board_dirty = false
		_board.refresh()
	if _run_over_pending:
		_run_over_pending = false
		# A run that just ended has no room for either. The shop matters as much as
		# the event here: the Amulet game can itself be a hub (they are the
		# best-connected games on the map, so it is not a rare pairing), and
		# winning the run is not a cue to go shopping.
		_pending_event = null
		_pending_event_node = &""
		_pending_shop = &""
		_post_snapshot = {}
		_attempt_resolve = false
		_show_run_over()
		return
	# A LOST RUN'S TURN (§3) ends here rather than going down the chain a report
	# ends in: nothing was reported, so there is no haul, no event and no shop
	# waiting behind the playback. What there CAN be is a drop the turn shook loose
	# — a body a mine took off the board — held back while the board was moving.
	if _attempt_resolve:
		_attempt_resolve = false
		_open_next_drop.call_deferred()
		return
	_open_post_game()

# --- the screen a game ends on (PostCombatScreen) ---------------------------

# Hand the haul over to one screen: the relics that fell, the loot the game paid,
# the hub's shelf, the boss warning, and the numbers behind all of it.
#
# It opens HERE and nowhere earlier, which is the whole point. The drops are
# queued in the middle of `GameLoop2.beat_game` and used to be pumped straight
# onto the screen — on the next idle frame, with the board still playing the
# strike and the advance back behind them. The resolve animation is the only
# place the run's consequences are ever SHOWN, and it was being asked to share
# the screen with "do you want this relic".
#
# Nothing else that reaches _end_resolve has a report behind it, and those carry
# straight on down the chain they always did.
func _open_post_game() -> void:
	if _post_snapshot.is_empty():
		_open_pending_event()
		return
	var snap: Dictionary = _post_snapshot
	_post_snapshot = {}
	# The queue is the screen's now. It stays a queue on the page's side (an
	# out-of-band offer still opens its own modal, see _pump_drops) — this is only
	# what THIS report put in it.
	var drops: Array = _drop_queue.duplicate()
	_drop_queue.clear()
	# THE BOSS WARNING, taken over from _maybe_announce_boss rather than left to
	# open behind this screen. A boss round is announced between two games, and
	# this screen is what stands between them; marking the round announced here is
	# what stops the popup arriving afterwards to say it again.
	var boss_tier: String = ""
	var bosses: Array = []
	if _boss_round and not GameLoop2.run_over and _boss_notice_for != GameState.games_played:
		_boss_notice_for = GameState.games_played
		boss_tier = RunDifficulty.tier_name(_current_tier())
		for choice in _choices:
			if bool(choice.get("boss", false)) and choice.get("enemy") != null:
				bosses.append(choice.get("enemy"))
	# THE SHELF, on the same terms _open_pending_shop mounts one: only where the
	# player is actually STANDING. Claimed off `_pending_shop` when it is, so the
	# chain behind this screen doesn't mount a second one; left there when it
	# isn't, for that method to turn down for the same reason it always has.
	var shop_id: StringName = _pending_shop
	if shop_id != &"" and not GameLoop2.run_over and shop_id == _hub_underfoot():
		_pending_shop = &""
	else:
		shop_id = &""
	_post_screen = PostCombatScreen.open(self, snap, drops,
		_pending_event != null, shop_id, boss_tier, bosses)
	var screen: PostCombatScreen = _post_screen
	_post_screen.finished.connect(func(): _on_post_game_finished(screen))

# The player is done with the haul: give the shelf back to the page and carry on
# down the chain the report always ended in — the event, then the shop, then the
# boss notice, then the detour question.
func _on_post_game_finished(screen: PostCombatScreen) -> void:
	_post_screen = null
	if screen != null and is_instance_valid(screen):
		var shop: ShopPanel2 = screen.release_shop()
		if shop != null:
			_adopt_shop(shop)
	_refresh()
	autosave()
	_open_pending_event()

# Take the shelf the post-combat screen borrowed and put it back under the board,
# where §14 says a shop lives for the rest of the visit. The panel is the same
# node the player was just buying from — reparented rather than rebuilt, so a
# card left open and the shelf's own scroll position survive the handover.
func _adopt_shop(panel: ShopPanel2) -> void:
	if _right_col == null:
		panel.queue_free()
		return
	_clear_shop()
	_right_col.add_child(panel)
	_shop_panel = panel
	panel.finished.connect(func():
		_shop_panel = null
		_sync_board_budget())
	_sync_board_budget()
	# Same two asks as _mount_shop: the panel has no height until the page has laid
	# it out, so "is it on screen" is unanswerable until after that.
	_update_shop_hint()
	_update_shop_hint.call_deferred()

# Pull the screen off the wall for a reset. `abandon` rather than `dismiss`: the
# player is not leaving the haul, the run is ending under it, and firing the way
# out here would resume a dead run's event chain in the middle of start_run.
func _dismiss_post_game() -> void:
	if _post_screen != null and is_instance_valid(_post_screen):
		_post_screen.abandon()
	_post_screen = null
	_post_snapshot = {}

# Open the queued event, if any. The offering behind it is already rebuilt, so
# the modal lands on the screen the player is about to act on rather than on a
# board mid-resolve.
#
# A node never owes both any more. The shop still opens behind the event here,
# and the ordering is kept deliberately rather than collapsed into one path: a
# hub pays no event (§14.4), so `_pending_event` is null at exactly the arrivals
# `_pending_shop` is set on, and the fall-through below is the whole story. It
# stays written as an order because the day something else queues an event on an
# arrival — an item, a scroll — the shop should still come second: an event is a
# decision with consequences and a shop is spending, so the money should be spent
# knowing how the event went.
func _open_pending_event() -> void:
	var ev: EventData2 = _pending_event
	var node: StringName = _pending_event_node
	_pending_event = null
	_pending_event_node = &""
	if ev == null:
		_open_pending_shop()
		return
	_event_modal = EventModal2.open(self, ev, node)
	_event_modal.finished.connect(_on_event_finished)

# Raise `ev` here and now, outside the beat-a-game path that normally queues one.
# The dev panel's event starter is the caller: authoring an event means wanting to
# look at it, and waiting for placement to hash it onto a leaf you can reach is
# not a workflow. It goes through _open_pending_event rather than calling
# EventModal2 itself, so a started event is wired up exactly as a real one — the
# same finished handler, the same refresh and autosave, and `play_game` actually
# posting the run off to a tagged game.
#
# Returns false when the screen is not in a state to hold one.
func open_event(ev: EventData2) -> bool:
	# `_pending_event` already holding one means a real event is queued behind a
	# resolve that is still playing; overwriting it would silently eat the event
	# the run actually earned.
	if ev == null or GameLoop2.run_over or _event_modal != null or _pending_event != null:
		return false
	_pending_event = ev
	_open_pending_event()
	return _event_modal != null

func _on_event_finished(play_request: Dictionary) -> void:
	_event_modal = null
	# Machines an event put in front of you belong to that event, and the modal
	# has already taken them away (EventModal2._end_objects) — precisely the ones
	# it spawned, where this used to clear the board outright and take a machine
	# that was standing at the game before the event with it.
	_refresh()
	autosave()
	if not play_request.is_empty():
		# The event is sending the player off to another game. The shop stays owed
		# and opens when that detour comes back through _end_resolve, rather than
		# being dropped over the top of a game about to start.
		_start_play_game(play_request)
		return
	_open_pending_shop()

# Mount the shop owed at this hub, if any (§14) — under the board, where it stays
# for the whole visit. Nothing is blocked by it and nothing waits on it, so the
# chain carries straight on to the boss notice.
func _open_pending_shop() -> void:
	var gid: StringName = _pending_shop
	_pending_shop = &""
	# Only where the player is actually STANDING. As a modal a shop could be raised
	# anywhere; as a place on the page it cannot, and the one path that gets here
	# from somewhere else is a node that owed both an event and a shop, where the
	# event posted the run off to another game (§10). The spec calls that pairing
	# unreal (every authored event is `Where: Dead End`, and a hub is the opposite
	# of one), and a shop mounted under the board while the run stands two games
	# away from it would be a worse answer than no shop.
	if gid != &"" and not GameLoop2.run_over and gid == _hub_underfoot():
		_mount_shop(gid)
	_maybe_announce_boss()

# The id of the game the run is standing on, read through the transmute map — a
# transmuted node plays a different game, and a shop belongs to the storefront of
# a particular big game rather than to the spot (§14).
func _hub_underfoot() -> StringName:
	var game: GameData = GameLoop2.game_at(GameState.current_game_id)
	return game.id if game != null else &""

# --- the shop on the page (§14) --------------------------------------------

# Put `gid`'s shop under the battlefield and raise the pointer to it. Replaces
# whatever shop was there — you can only be standing in one.
func _mount_shop(gid: StringName) -> void:
	_clear_shop()
	if _right_col == null:
		return
	_shop_panel = ShopPanel2.mount(_right_col, gid)
	if _shop_panel == null:
		return
	_shop_panel.finished.connect(func():
		_shop_panel = null
		_sync_board_budget())
	_sync_board_budget()
	# The panel has no height until the page has laid it out, and "is it on screen"
	# is unanswerable before then — so ask once now (the pointer goes up) and again
	# after the layout has happened (it may already be in view on a short board).
	_update_shop_hint()
	_update_shop_hint.call_deferred()

# Everything mounted under the board because the run is STANDING HERE: the hub's
# shop and any machines. Both have the same lifetime — travelling on ends them —
# and they differ in what survives it. A shop's shelf lives on in ShopSystem, so
# coming back to a hub is a real option; a machine is simply gone, and the next
# one you meet is a different machine with its own press counts.
func _leave_node() -> void:
	_clear_shop()
	_clear_objects()
	ObjectSystem.clear()


# --- the machines on the page (docs/object-sheet-authoring.md) -------------

# Bring the under-board panel into line with what ObjectSystem is holding: mount
# it when machines appear, take it down when the last one goes. Driven off the
# signal rather than called at the spawn sites, so a machine spawned from the dev
# panel, from an item, or from anything added later lands on the page without
# that caller knowing the panel exists.
func _sync_object_panel() -> void:
	if not ObjectSystem.has_live() or GameLoop2.run_over:
		_clear_objects()
		return
	# An event showing its own machines owns them for as long as it is open; a
	# second copy under the board would be the same buttons twice.
	if _event_modal != null and is_instance_valid(_event_modal):
		_clear_objects()
		return
	if _object_panel != null and is_instance_valid(_object_panel):
		return
	if _right_col == null:
		return
	_object_panel = ObjectPanel2.mount(_right_col)
	if _object_panel != null:
		_object_panel.finished.connect(func():
			_object_panel = null
			_sync_board_budget())
	_sync_board_budget()


func _clear_objects() -> void:
	if _object_panel != null and is_instance_valid(_object_panel):
		_object_panel.close()
	_object_panel = null
	_sync_board_budget()


# The board pays for whatever is mounted under it. The right column is 626px of
# a 688px page — the overworld is built to fit a 720p canvas with about five
# pixels to spare — so a shop or a rank of machines below the board has nowhere
# to come from but the board itself. It shrinks its cells while it is sharing the
# column and springs back when it stops, which is when you travel on.
func _sync_board_budget() -> void:
	var shared: bool = (_object_panel != null and is_instance_valid(_object_panel)) \
		or (_shop_panel != null and is_instance_valid(_shop_panel))
	if BattlefieldView.set_sharing_column(shared) and _board != null:
		_board.refit()

# The shop closes when you travel on, which is what leaving a shop has always
# meant. Also called by _mount_shop, which is replacing one rather than leaving
# the node — which is why this stays separate from _leave_node.
func _clear_shop() -> void:
	if _shop_panel != null and is_instance_valid(_shop_panel):
		_shop_panel.close()
	_shop_panel = null
	_sync_board_budget()
	_update_shop_hint()

# The "🛒 Shop ↓" pointer: shown while a shop is mounted and has NOT been scrolled
# to. The whole point of moving the shop into the page is that it doesn't
# interrupt — which is also how a shop below the fold gets missed entirely, so
# the one thing that does reach over the page is a pointer at it.
func _update_shop_hint() -> void:
	if _shop_hint == null:
		return
	var up: bool = _shop_panel != null and is_instance_valid(_shop_panel) and not _shop_in_view()
	_shop_hint.visible = up
	# Only worth watching while there is a shop to point at. "Has it been scrolled
	# to yet" cannot be answered off the scroll signal alone — the value moves
	# before the layout does, so the answer measured at that moment is one frame
	# stale and the pointer stayed up over a shop in plain view.
	set_process(_wants_process())

# Two things want a frame hook: the shop pointer above, and the loot overlay,
# which has to FOLLOW the board it is standing on. One gate for both, so neither
# can switch the other off — which is exactly what happened when each called
# set_process with only its own answer.
func _wants_process() -> bool:
	return (_shop_panel != null and is_instance_valid(_shop_panel)) \
		or (_loot_panel != null and is_instance_valid(_loot_panel))

func _process(_delta: float) -> void:
	_update_shop_hint()
	_follow_loot_overlay()

# Keep the loot overlay on the board when the page moves under it. `item_rect_
# changed` on the board is not enough: a report regrows the LEFT column, which
# shifts the board's GLOBAL rect without its own local rect changing, so the
# signal never fires and the panel drifts off by the difference. Comparing the
# anchor's global rect each frame is a couple of float compares and cannot miss.
func _follow_loot_overlay() -> void:
	if _loot_panel == null or not is_instance_valid(_loot_panel):
		return
	if _stage_panel == null or not is_instance_valid(_stage_panel):
		return
	var now: Rect2 = _stage_panel.get_global_rect()
	if now == _loot_anchor_rect:
		return
	_place_loot_overlay()

# Is any of the shop panel inside the scroll viewport? Measured against the
# viewport's own rect rather than the page's, because "on screen" is what the
# pointer is about.
func _shop_in_view() -> bool:
	if _shop_panel == null or not is_instance_valid(_shop_panel) or _scroll == null:
		return false
	if _shop_panel.size.y <= 0.0:
		return false        # not laid out yet — treat it as still below the fold
	var top: float = _shop_panel.global_position.y - _scroll.global_position.y
	return top < _scroll.size.y - SHOP_HINT_REVEAL

# How much of the shop has to be on screen before the pointer stands down. A
# sliver of a panel edge is not "you have seen the shop".
const SHOP_HINT_REVEAL := 60.0

# An item bought down there is a pickup like any other, so it comes back through
# GameState.inventory_changed (_on_inventory_changed) exactly as a drop does —
# the shop needs no repaint hook of its own.


# --- the boss round announces itself (§7.1) --------------------------------

# The last thing shown between two games, when the offering that just came back
# is a boss round. It is last on purpose: the event and the shop are the previous
# game's aftermath, and this is about the decision in front of you, so it should
# be the thing still on screen when the popup chain runs out.
#
# Once per round, keyed on the games-played count the round belongs to — the
# offering is redrawn by a bash, a transmute and a scramble as well as by a
# report, and a warning that reopened on each of those would be a warning the
# player learns to click through.
func _maybe_announce_boss() -> void:
	var due: bool = _phase == Phase.SELECT and _boss_round and not GameLoop2.run_over \
		and _boss_notice_for != GameState.games_played and _boss_notice == null
	if not due:
		_finish_pending_detour()
		return
	_boss_notice_for = GameState.games_played
	var bosses: Array = []
	for choice in _choices:
		if bool(choice.get("boss", false)) and choice.get("enemy") != null:
			bosses.append(choice.get("enemy"))
	_boss_notice = BossNoticeModal.open(self,
		RunDifficulty.tier_name(_current_tier()), bosses)
	_boss_notice.finished.connect(func():
		_boss_notice = null
		_finish_pending_detour())

# The reward for going back to a game the run had already played and beating it
# this time: +1 Dash (§4).
#
# `by_dash` REFUNDS the charge the trip itself cost, and it is the whole reason
# this takes an argument. The offering prints "⚡ +1 DASH" on a game you have
# played, and the usual way to get back to one is to spend a Dash — the offering
# is three of a hub's twenty neighbours, so the game you want is rarely on the
# table. Spend one to travel, earn one for the clear, and the counter reads
# exactly what it read before: the card promised a charge and the player watched
# nothing happen. The trip is what the Dash paid for; the +1 is what the CLEAR
# pays, and the two are not the same transaction.
#
# Announced on both channels — the toast for the moment, the log for the record —
# because the HUD's Dash counter moving on its own reads as a bug.
func _grant_repeat_dash(game: GameData, by_dash: bool = false) -> void:
	var gained: int = REPEAT_BEAT_DASH + (1 if by_dash else 0)
	GameState.dash_charges += gained
	var msg: String = "Back at %s, and beaten — +%d Dash." % [game.display_name, REPEAT_BEAT_DASH]
	if by_dash:
		msg += " The Dash that took you there comes back too."
	Notifications.notify(msg, DASH_BLUE)
	GameLog.add(msg, DASH_BLUE)

# A try was logged (or taken back): the board shows it. An undo just repaints —
# there's nothing to celebrate about a correction.
func _on_attempt_logged(cost: String, undone: bool) -> void:
	if not undone:
		_board.play_attempt_fx(cost)

# Count an arrival so a later visit to the same game draws a different offering.
func _on_arrived(game_id: StringName) -> void:
	if game_id == &"":
		return
	_visits[game_id] = int(_visits.get(game_id, 0)) + 1

func _exit_tree() -> void:
	GameState.clear_overworld_context(self)
	# The header bar goes with the page. Leaving its height published would push
	# the main menu's own modals down by a strip that no longer exists.
	ModalScaffold.reserved_top = 0.0
	# The wider canvas belongs to THIS page (see _fit_canvas_to_page). The menu is
	# laid out for the standard one, so it goes back with the screen that asked
	# for it.
	Settings.reset_canvas_width()
	_board.clear_fx()
	_close_enemy_info()
	if TriggerBus.chest_granted.is_connected(_on_chest_granted):
		TriggerBus.chest_granted.disconnect(_on_chest_granted)
	if GameState.inventory_changed.is_connected(_on_inventory_changed):
		GameState.inventory_changed.disconnect(_on_inventory_changed)
	if GameState.hp_changed.is_connected(_on_vitals_changed):
		GameState.hp_changed.disconnect(_on_vitals_changed)
	if GameState.stats_changed.is_connected(_refresh_stats):
		GameState.stats_changed.disconnect(_refresh_stats)
	if ObjectSystem.objects_changed.is_connected(_sync_object_panel):
		ObjectSystem.objects_changed.disconnect(_sync_object_panel)
	if GameState.gold_changed.is_connected(_on_gold_changed):
		GameState.gold_changed.disconnect(_on_gold_changed)
	if GameState.current_game_changed.is_connected(_on_arrived):
		GameState.current_game_changed.disconnect(_on_arrived)

# --- reward chests (§8) ---------------------------------------------------

# A chest was banked (an enemy drop, a level-up reward, Unstable Genome, …).
# Redeem on the next idle frame so it runs after the current resolve finishes.
func _on_chest_granted(_ctx: Dictionary) -> void:
	call_deferred("_redeem_pending_chests")

# Opens one RewardScreen for the next pending chest; chains to the following
# chest when it closes, so a multi-defeat game shows its rewards back-to-back.
func _redeem_pending_chests() -> void:
	if _reward_open or not is_inside_tree():
		return
	if GameState.pending_chests <= 0:
		return
	# ON THE HAUL SCREEN, if one is up. A chest banked during a report — a level-up
	# reward, Unstable Genome firing on the beat, a status paying out — used to open
	# a RewardScreen as an ordinary child of this page, which is BELOW the
	# post-combat screen's CanvasLayer: the player saw nothing, and then found a
	# reward screen waiting the moment they left. It belongs with the rest of the
	# haul anyway, so it goes there as one more chest section.
	if _post_screen != null and is_instance_valid(_post_screen):
		_hand_chests_to_post_game()
		return
	# EVERY banked chest at once, not one screen each. Two chests used to open two
	# screens back to back, which reads as one screen flickering — you cannot weigh
	# the second chest's offer against what you just took, and nothing marks it as
	# a different chest. One screen with a labelled group per chest says what you
	# actually got: "2 Small Chests" is two chests of one item, not one of two.
	var sizes: Array = []
	while GameState.pending_chests > 0:
		var choices: int = GameState.take_pending_chest()  # -1 none / 0 default / N
		if choices < 0:
			break
		sizes.append(maxi(0, choices))
	if sizes.is_empty():
		return
	_reward_open = true
	var screen := preload("res://scripts/ui/RewardScreen.gd").new()
	screen.closed.connect(func():
		_reward_open = false
		_redeem_pending_chests())
	add_child(screen)
	screen.setup_chests(sizes)

# Drain every banked chest onto the post-combat screen. Rolled through the same
# `_roll_chest` a defeated body's drop uses — which is the same pool and the same
# rarity ladder the RewardScreen rolls on (`Data.roll_item_rarity` /
# `reward_item2_pool_of`), so a chest is the same chest whichever surface asks
# about it.
#
# `take_pending_chest` hands back the CHOICE COUNT, where 0 means "the reward
# screen's own default" — BASE_ITEM_CHOICES plus Discovery — so that reading is
# spelled out here rather than collapsed to one card. A chest that offered one
# item where the RewardScreen would have offered three is a silent nerf to every
# level-up in the run.
func _hand_chests_to_post_game() -> void:
	var discovery: int = maxi(0, Stats.get_value(&"discovery"))
	while GameState.pending_chests > 0:
		var choices: int = GameState.take_pending_chest()
		if choices < 0:
			break
		var count: int = choices if choices > 0 else RewardScreen.BASE_ITEM_CHOICES + discovery
		var offer: Array = _roll_chest(false, maxi(1, count))
		if offer.is_empty():
			continue
		if _post_screen != null and is_instance_valid(_post_screen):
			_post_screen.add_chest(offer)
		else:
			# The screen went while we were draining: fall back to the queue the
			# page's own modal drains, rather than losing the chest.
			_drop_queue.append({"items": offer})
			_pump_drops()

# --- overworld item actions (routed here by EffectSystem, §8) --------------

# Ride the Bus: teleport to a random game of `type_key` currently reachable on
# the map (falls back to any game of that type in the pool). Rebuilds the
# offering from the new position.
func teleport_to_type(type_key: StringName) -> void:
	var cur: StringName = GameState.current_game_id
	var same_type: Array = []
	for g in Data.all_games():
		if not (g is GameData) or g.id == cur or GameLoop2.is_bashed(g.id):
			continue
		if GameLoop2.game_type_key(g) == type_key:
			same_type.append(g.id)
	if same_type.is_empty():
		GameLog.add("Ride the Bus finds no %s game to reach." % String(type_key),
			Color(0.8, 0.6, 0.4))
		return
	var dest: StringName = same_type[_rng.randi() % same_type.size()]
	var g: GameData = Data.get_game(dest)
	GameLog.add("Rode the bus to %s." % (g.display_name if g != null else String(dest)),
		Color(0.5, 0.85, 1.0))
	travel_to_game(dest)

# Move the run to `game_id` outright and rebuild the offering around it — the
# landing half of every teleport (Ride the Bus, and the dev panel's jump). Does
# not resolve a game or touch the board; it only changes where you are standing.
func travel_to_game(game_id: StringName) -> void:
	if Data.get_game(game_id) == null:
		return
	_leave_node()
	GameState.set_current_game(game_id)
	_phase = Phase.SELECT
	_dash_mode = false
	_chosen = {}
	_build_choices()
	_refresh()

# `play_game tag=<tag>` — the one event token that MOVES the player (§10).
#
# Punch Off's "I Can Take Them" sends you off to a random mecha roguelike. It is
# not a reward and not a goal: you go and play a game that is not on your route,
# it spawns its enemy and runs under the ordinary rules — beating the robots IS
# beating the game — and the payload lands on the far side of it.
#
# What makes it a routing decision rather than a free game is the far side: when
# it resolves you CHOOSE whether to stay there or come back. Which is the exact
# inverse of §1, where a dead end forces the round trip on you.
func _start_play_game(request: Dictionary) -> void:
	var tag: StringName = StringName(String(request.get("tag", "")).to_lower())
	var dest: StringName = _random_game_with_tag(tag)
	if dest == &"":
		# Nothing in the catalog carries the tag (or everything that does is
		# bashed). Pay the payload anyway rather than swallowing the choice the
		# player already made — they picked the hard option in good faith.
		GameLog.add("No %s game to reach — the payoff lands anyway." % tag, UITheme.ACCENT)
		for eff in request.get("effects", []):
			EffectSystem.apply(eff, {})
		return
	# The run is being posted off this node, so anything standing at it goes.
	_leave_node()
	_play_return_to = GameState.current_game_id
	_play_payload = (request.get("effects", []) as Array).duplicate(true)
	_play_payload_text = String(request.get("effects_text", ""))

	var game: GameData = Data.get_game(dest)
	var tier: int = _current_tier()
	var enemy: GoalEnemyData = GameLoop2.roll_enemy(GameLoop2.game_type_key(game), tier)
	_chosen = {
		"game": game, "enemy": enemy, "slot": dest,
		"boss": false, "amulet": dest == GameState.amulet_game_id,
		"repeat": GameState.has_played_game(game.id),
	}
	GameLoop2.choose_game(enemy, GameLoop2.game_type_key(game), tier)
	_log_escort()
	GameLoop2.grant_selection_shields(game)
	GameState.set_current_game(dest)
	_dash_mode = false
	# A detour is posted by an event, not paid for with a charge, so there is
	# nothing for the return-trip Dash to refund at the far end of it.
	_dashed_here = false
	if _offering != null:
		_offering.reset_hover_grant()
	_phase = Phase.PLAYING
	_populate_play_panel()
	_refresh()
	_scroll_to_top()
	GameLog.add("Off to %s — a %s game." % [game.display_name, tag], UITheme.ACCENT)
	autosave()


# The destination pool is EventSystem's, not this screen's: the same list that
# gated the event onto the node in the first place (§10). If these two ever
# disagreed, an event would advertise a detour it could not deliver.
func _random_game_with_tag(tag: StringName) -> StringName:
	var pool: Array = EventSystem.games_with_tag(tag)
	pool.erase(GameState.current_game_id)
	if pool.is_empty():
		return &""
	return pool[_rng.randi() % pool.size()]


# The queued far side of a detour, run once everything else the report owed has
# been shown (the resolve, an event, the shop, a boss warning). Nothing happens
# here unless a detour is actually in flight.
func _finish_pending_detour() -> void:
	if not _pending_detour:
		return
	_pending_detour = false
	_finish_play_game(_detour_beaten)


# The far side of a play_game detour: pay the payload, then offer the choice the
# original event promised — stay here, or go back where you came from. Staying is
# only offered when this game is actually ON the run graph; a game reached by tag
# may be off-map entirely, and standing on a node with no edges is a dead run.
func _finish_play_game(beaten: bool) -> void:
	var payload: Array = _play_payload
	var payload_text: String = _play_payload_text
	var back: StringName = _play_return_to
	_play_payload = []
	_play_payload_text = ""
	_play_return_to = &""
	if beaten:
		for eff in payload:
			EffectSystem.apply(eff, {})
		if payload_text != "":
			Notifications.notify("The detour pays: %s." % payload_text, UITheme.ACCENT)
			GameLog.add("The detour pays: %s." % payload_text, UITheme.ACCENT)
	elif payload_text != "":
		GameLog.add("You walked away — the detour pays nothing.", UITheme.TEXT_DIM)

	var here: StringName = GameState.current_game_id
	var can_stay: bool = not RunGraph.is_off_map(here) and RunGraph.degree(here) > 0
	if not can_stay:
		if back != &"":
			travel_to_game(back)
		return
	_ask_stay_or_return(back)


# "Stay, or head back?" — asked with the SAME SCREEN the run asks every other
# where-do-I-go question with: two cover cards on the offering, each opening the
# full card popup (GameChoiceModal) with the route from there drawn as the real
# ladder, the shop and event flags, and your record in the game.
#
# It used to be a ConfirmationDialog with the two game names in a sentence, on the
# grounds that the interesting decision was taking the detour and this was only
# its bookkeeping. That was wrong: it is a ROUTING decision, and the biggest one
# the detour creates — the whole point of being posted off your route is that you
# are now somewhere else, and "is this a better place to carry on from?" cannot be
# answered from two names. A player who is shown the map for every ordinary step
# and a sentence for this one is being asked to guess exactly when it matters.
func _ask_stay_or_return(back: StringName) -> void:
	if back == &"" or Data.get_game(back) == null:
		return
	_return_choice = back
	_phase = Phase.SELECT
	_dash_mode = false
	_chosen = {}
	_build_return_choices()
	_refresh()
	_scroll_to_top()

# The two destinations as offering cards. No enemy is rolled for either: this
# question moves the run, it does not start a game — whichever way it goes, the
# offering at the far end is what picks the next game (and rolls its enemy).
func _build_return_choices() -> void:
	_choices.clear()
	var here: StringName = GameState.current_game_id
	var amulet: StringName = GameState.amulet_game_id
	_rebuild_amulet_distances()
	for gid in [here, _return_choice]:
		var game: GameData = GameLoop2.game_at(gid)
		if game == null:
			continue
		_choices.append({
			"game": game, "enemy": null, "slot": gid,
			"boss": false, "amulet": gid == amulet,
			"repeat": GameState.has_played_game(game.id),
			"stay": gid == here,
		})

func _asking_return() -> bool:
	return _return_choice != &""

# Answer it. Staying needs nothing but the offering rebuilt around where the run
# already stands; heading back is an ordinary teleport to the node it came from.
func _take_return_choice(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	var choice: Dictionary = _choices[index]
	var back: StringName = _return_choice
	_return_choice = &""
	var game: GameData = choice.get("game")
	if bool(choice.get("stay", false)):
		GameLog.add("Carried on from %s." % (game.display_name if game != null else "the detour"),
			UITheme.ACCENT)
		_build_choices()
		_refresh()
		autosave()
		return
	travel_to_game(back)
	autosave()


# Wand of Wishing: obtain any one item — opens a RewardScreen listing the full
# items2.0 catalog (non-starter) to pick from.
func obtain_any_item() -> void:
	if _reward_open:
		return
	_reward_open = true
	var screen := preload("res://scripts/ui/RewardScreen.gd").new()
	screen.closed.connect(func():
		_reward_open = false
		_redeem_pending_chests())
	add_child(screen)
	screen.setup_obtain(Data.reward_item2_pool())

# Fire an owned USABLE / CHARGED item from the overworld inventory panel.
func use_item(item: ItemData) -> void:
	if item == null or not GameState.can_fire_item(item):
		return
	# AN ITEM THAT AIMS IS ARMED HERE AND FIRED ON THE BOARD (Staff of Flame).
	# Nothing is spent by this press: GameState.use_item empties a charged bar the
	# moment it fires, so an item whose effect needs a body picked has to wait for
	# the pick — otherwise cancelling the picker would cost the charge anyway.
	if item.wants_target():
		aim_item(item)
		return
	# A non-charged overworld active (Ride the Bus) commits immediately, so spend
	# its use here (use_item defers the spend for cancellable pickers).
	var spend_after: bool = not item.is_charged() and item.overworld_usable
	GameState.use_item(item)
	if spend_after and GameState.inventory.has(item):
		GameState.consume_item_use(item)
	_refresh_items()

# Arm an aiming item over the board: the bodies light up, and the click on one is
# what fires it (see _on_item_aimed). Refused — loudly, and without spending
# anything — when there is nothing out there to point it at, which is the one
# case the pack cannot see from where its button is.
func aim_item(item: ItemData) -> void:
	if _board == null or not is_instance_valid(_board):
		return
	_close_item_card()
	var at_ground: bool = item.target_kind() == &"tile"
	if not _board.begin_item_aim(item):
		# Two different emptinesses (§17): a body-aimed relic has nobody to point
		# at, a ground-aimed one has no square inside the columns it authored — a
		# board narrower than its reach. Both are refused without spending
		# anything, and both say which it was.
		var empty: String = ("The board has no tile %s can reach." % item.display_name
			if at_ground else "Nothing is following you — %s has nothing to aim at."
			% item.display_name)
		GameLog.add(empty, UITheme.TEXT_DIM)
		Notifications.notify(empty, UITheme.TEXT_DIM)
		return
	Notifications.notify("Click a tile to aim %s." % item.display_name
		if at_ground else "Click an enemy to aim %s." % item.display_name,
		UITheme.ACCENT)

# The board handing back an armed item and the body it was pointed at. THIS is
# where it fires and where the charge goes — the instance rides `use_item`'s
# target into the effect ctx, which is how `apply_status … target=enemy` knows
# which body the player meant.
func _on_item_aimed(item: ItemData, instance: int) -> void:
	if item == null or instance <= 0 or not GameState.can_fire_item(item):
		return
	if not GameState.use_item(item, instance):
		return
	var entry: Dictionary = GameLoop2.entry_for(instance)
	var enemy: GoalEnemyData = entry.get("enemy") if not entry.is_empty() else null
	if enemy != null:
		GameLog.add("%s is aimed at %s." % [item.display_name, enemy.display_name],
			Color(1.0, 0.72, 0.4))
	_refresh_items()
	if _board != null and is_instance_valid(_board):
		_board.refresh()

# The board handing back an armed item and the CELL it was pointed at (Red Candle,
# §17). The twin of _on_item_aimed above, and deliberately its own function: the
# cell rides `use_item`'s target as a Vector2i, which is how `apply_tile …
# target=tile` knows which square the player meant, and the log names the ground
# rather than a body.
func _on_item_aimed_at_cell(item: ItemData, cell: Vector2i) -> void:
	if item == null or not GameState.can_fire_item(item):
		return
	if not GameState.use_item(item, cell):
		return
	GameLog.add("%s is aimed at column %d, row %d." % [
		item.display_name, cell.x, cell.y + 1], Color(1.0, 0.72, 0.4))
	_refresh_items()
	if _board != null and is_instance_valid(_board):
		_board.refresh()

# --- throwing a potion at the board (docs/potions-design.md §4.2) -----------

# The use modal armed a THROW. The picker goes up on the board, the modal takes
# itself off screen, and the click on a square brings it back — so the overworld
# only has to hold the waiting screen and hand it the cell.
#
# Returns false when there is no board to aim at, which the modal turns into a
# fizzle rather than a refusal: a Use button that will not press teaches the
# player the piece is broken (§4.5).
var _throw_modal: Node = null

func begin_loot_throw(modal: Node, entry: Dictionary, index: int) -> bool:
	if _board == null or not is_instance_valid(_board):
		return false
	# NOT FROM UNDERNEATH THE DROP SCREEN. A drop is a question with a deadline —
	# take it, use it, or leave it — and it owns the whole screen while it is being
	# answered (§4.3). A picker armed under it would light up squares the player
	# cannot reach, and the offer would sit unanswered while they tried. The bottle
	# is not spent, so the answer is "quaff it here or carry it out", and the modal
	# says which.
	if _drop_modal != null and is_instance_valid(_drop_modal):
		return false
	if not _board.begin_loot_throw(entry, index):
		return false
	_throw_modal = modal
	# GET OFF THE BOARD. The loot window is a panel that floats OVER the
	# battlefield (§4.3) and the info card is full-screen — a picker armed behind
	# either of them lights up squares the player cannot reach. They are put away
	# rather than left open, which is also the honest reading of what is happening:
	# the pack is closed, the bottle is in your hand, and the next click is where
	# it lands.
	if _loot_window != null:
		_loot_window.open = false
		refresh_loot_window()
	_close_item_card()
	Notifications.notify("Click a square to throw %s." % LootSystem.display_name(entry),
		UITheme.ACCENT)
	return true

# The board handing back a thrown piece and the square it landed on. The modal
# that armed it does the spending — it is the screen holding the slot index, the
# echo names and the Health it is about to report against — so this only routes.
#
# A throw with NO modal waiting (a dev grant, a reload mid-aim) is still resolved
# here rather than dropped: the piece was aimed and the player clicked, and the
# only thing missing is somewhere to print the outcome.
func _on_loot_thrown_at_cell(entry: Dictionary, index: int, cell: Vector2i) -> void:
	var modal: Node = _throw_modal
	_throw_modal = null
	if modal != null and is_instance_valid(modal) and modal.has_method("resolve_throw"):
		modal.resolve_throw(cell)
	else:
		var ctx := {"verb": "throw", "target": cell}
		var res: Dictionary = LootSystem.use_entry(entry, ctx) if index < 0 \
			else LootSystem.use_loot(index, ctx)
		for line in res.get("logs", []):
			GameLog.add(String(line), LootSystem.LOOT_COLOR)
	_refresh()
	if _board != null and is_instance_valid(_board):
		_board.refresh()

# The throw was put away without landing. Nothing was spent, so the modal comes
# back to where it was — the player is choosing again, not being told their bottle
# has gone missing.
func _on_loot_throw_cancelled(_entry: Dictionary, _index: int) -> void:
	var modal: Node = _throw_modal
	_throw_modal = null
	if modal != null and is_instance_valid(modal) and modal.has_method("throw_cancelled"):
		modal.throw_cancelled()

# Bash the offered game at `index` (§4): destroy it out of the pool for the rest of
# the run — it is never offered again — and REFILL its slot from the same pool the
# offering is drawn from, i.e. another game connected to where the player is
# standing (_backfill_id_for). The replacement gets its own freshly-rolled
# goal-enemy while the untouched cards keep theirs. When this node has no other
# connection left to give, the slot simply goes: bashing is destruction, not a
# guaranteed reroll.
#
# Two bashes are refused outright, because both end the run rather than shape it:
# the AMULET game (destroying the goal makes the run unwinnable) and the LAST card
# on the board with nothing to replace it (destroying it leaves nowhere to travel).
#
# Allowed on a boss round — the boss is tied to the difficulty gate, not the game,
# so whatever backfills the slot still spawns a boss.
func bash_choice(index: int) -> void:
	if _asking_return():
		return
	if _phase != Phase.SELECT or index < 0 or index >= _choices.size():
		return
	var choice: Dictionary = _choices[index]
	var slot: StringName = choice["slot"]
	var game: GameData = choice["game"]
	if bool(choice.get("amulet", false)):
		var amulet_msg: String = "%s holds the Amulet — bashing it would end the run's goal." % game.display_name
		GameLog.add(amulet_msg, UITheme.DANGER)
		Notifications.notify(amulet_msg, UITheme.DANGER)
		return
	# Resolved BEFORE the bash, while the slot is still on the board.
	var replacement: StringName = _backfill_id_for(slot)
	if replacement == &"" and _choices.size() <= 1:
		var stuck_msg: String = "Nothing else connects to here — bashing %s would leave nowhere to go." % game.display_name
		GameLog.add(stuck_msg, UITheme.DANGER)
		Notifications.notify(stuck_msg, UITheme.DANGER)
		return
	if not GameLoop2.bash_game(slot):
		return
	# A transmute on the destroyed slot dies with it, and so does its cached enemy.
	GameLoop2.transmuted.erase(slot)
	_slot_enemies.erase("%s>%s" % [String(slot), String(game.id)])
	_build_choices()
	_refresh()
	if replacement != &"":
		var repl: GameData = Data.get_game(replacement)
		var repl_name: String = repl.display_name if repl != null else String(replacement)
		GameLog.add("Bashed %s — %s takes its place." % [game.display_name, repl_name],
			Color(1.0, 0.72, 0.4))
		Notifications.notify("Bashed %s → %s" % [game.display_name, repl_name],
			Color(1.0, 0.72, 0.4))
	else:
		GameLog.add("Bashed %s — nothing else connects here, so the slot goes with it." % game.display_name,
			Color(1.0, 0.72, 0.4))

# Transmute the offered game at `index` (§4): swap it for a random off-graph game
# of the same type — or, for a Traditional game, of any OTHER type, since trading
# one long haul for another is no relief. Allowed on a boss round — the
# replacement game still spawns a boss, because boss-ness follows the difficulty
# gate rather than the game.
func transmute_choice(index: int) -> void:
	if _asking_return():
		return
	if _phase != Phase.SELECT or index < 0 or index >= _choices.size():
		return
	var slot: StringName = _choices[index]["slot"]
	var on_map: Array = []
	for c in _choices:
		on_map.append(c["slot"])
	var repl: GameData = GameLoop2.transmute_game(slot, on_map)
	if repl != null:
		# GameLoop2 records the paste against the NODE, so it survives moving on,
		# scrambling, and saving — the spot plays that game for the rest of the run.
		_build_choices()
		_refresh()

# Push a following enemy one space (Manager's verb, §7.2): spend a Push charge to
# shove it back (delaying its next attack by a game), forward, or across into
# another lane. Targets a stacked follower by instance; GameLoop2.push guards the
# charge, the membership and the room in the destination, so a no-op just leaves
# the board unchanged.
#
# `dir` defaults to BACK for the callers that predate the four directions — the
# enemy info card's single button and the headless harness.
func push_follower(instance: int, dir: Vector2i = GameLoop2.PUSH_BACK) -> void:
	if GameLoop2.push(instance, dir):
		_refresh()

# Bomb a following enemy (§4): spend a Bomb charge to deal it 1 damage (no drop
# when that kills it). A boss can be bombed but takes none of the damage, so the
# charge only buys Sticky Bombs' stun there. GameLoop2.bomb guards the charge.
func bomb_follower(instance: int) -> void:
	if GameLoop2.bomb(instance):
		_refresh()

# A bomb spent on GROUND rather than on a body (§17). The board hands back the
# square; the loop spends the charge and sets the blast off there, which is worth
# doing on an empty cell whenever the pack has made a bomb leave something behind
# (Hot Bombs) or reach past its own square (Brimstone).
func bomb_cell(cell: Vector2i) -> void:
	if not GameLoop2.bomb_cell(cell):
		return
	GameLog.add("A bomb goes off at column %d, row %d." % [cell.x, cell.y + 1],
		Color(1.0, 0.72, 0.4))
	_refresh()

# --- enemy info card ------------------------------------------------------

# The board reports a clicked enemy; the card is opened HERE because it dims the
# whole screen and the board itself lives inside the scrolling page.
func _show_enemy_info(entry: Dictionary, col: int) -> void:
	_close_enemy_info()
	var card := EnemyInfoCard.new()
	card.push_requested.connect(push_follower)
	card.bomb_requested.connect(bomb_follower)
	card.closed.connect(func(): _info_popup = null)
	_info_popup = card
	add_child(card)
	card.setup(entry, col)

func _close_enemy_info() -> void:
	if _info_popup != null and is_instance_valid(_info_popup):
		_info_popup.close()
	_info_popup = null

# --- offering construction ------------------------------------------------

# Whether the upcoming selection crosses a difficulty gate (§7.1). The tier steps
# up every GAMES_PER_TIER games played, so a boss round lands whenever the games-
# played count is a positive multiple of that step.
func _is_boss_round() -> bool:
	var gp: int = GameState.games_played
	return gp > 0 and gp % RunDifficulty.GAMES_PER_TIER == 0

# The difficulty tier of the CURRENT offering. A boss round is the CAPSTONE of the
# tier the player just cleared (§7.1): the game-4 boss is Low and beating it is
# what advances the run to Medium, so a boss rolls at tier_for(games_played - 1),
# one below the normal-game formula. Once the run reaches Insane the cap holds, so
# Insane bosses keep appearing every GAMES_PER_TIER games.
func _current_tier() -> int:
	var gp: int = GameState.games_played
	if _is_boss_round():
		return RunDifficulty.tier_for(gp - 1)
	return RunDifficulty.tier_for(gp)

# How many game cards the offering shows: the base three plus whatever
# "game_choices" bonus the run has been granted (never below one, or there'd be
# nothing to pick). Items / effects widen the offering through this.
func offer_count() -> int:
	return maxi(1, BASE_OFFER_COUNT + GameState.game_choice_bonus)

# The limited offering for the current position: reachable, non-bashed games in a
# stable position-seeded order, capped at offer_count(), with the amulet always
# kept when it's reachable. Stable so bashing/transmuting one card doesn't
# reshuffle the rest — only a Scramble (which bumps _scramble_salt) re-draws it.
func _offered_ids() -> Array:
	var amulet: StringName = GameState.amulet_game_id
	var nbrs: Array = _sorted_neighbors()
	# Dash (§4) bypasses the cap — every connected game is a valid target.
	#
	# And it is the one offering that is a LIST rather than a hand of cards: a hub
	# has twenty connections, so the Dash panel is twenty covers deep and the
	# question stops being "which of these three" and becomes "is the game I have
	# in mind in here". A seeded shuffle is exactly wrong for that — it is there to
	# stop a three-card offering feeling like a menu, and this one IS a menu. Sorted
	# by name, a player looking for a particular game can find it by eye.
	if _dash_mode:
		nbrs.sort_custom(_by_display_name)
		return nbrs
	var cap: int = offer_count()
	if amulet in nbrs and nbrs.size() > cap:
		nbrs.erase(amulet)
		nbrs.push_front(amulet)
	return _guarantee_onward(nbrs.slice(0, cap), nbrs)

# The hub rule (HUB_CONNECTIONS / ONWARD_CONNECTIONS): standing on a hub, at least
# one offered card must lead somewhere. If the seeded slice came up all dead ends,
# swap the first onward game from the rest of the pool into the LAST slot — last
# so the amulet, which _offered_ids pushed to the front precisely so the cap can
# never hide it, is the one card this can't displace.
#
# `offered` is returned unchanged whenever the rule doesn't apply: off a hub, when
# a card already leads onward, or when this hub genuinely has no onward neighbour
# left (every one of them bashed or a dead end) — the guarantee promises a card
# that exists, not one invented for the occasion.
func _guarantee_onward(offered: Array, pool: Array) -> Array:
	if RunGraph.degree(GameState.current_game_id) <= HUB_CONNECTIONS:
		return offered
	for gid in offered:
		if RunGraph.degree(gid) > ONWARD_CONNECTIONS:
			return offered
	for gid in pool:
		if offered.has(gid) or RunGraph.degree(gid) <= ONWARD_CONNECTIONS:
			continue
		offered[offered.size() - 1] = gid
		return offered
	return offered

# Every game connected to where the player stands that is still in the pool, in
# the offering's stable order. This IS the pool an offered slot is drawn from — so
# it's also the pool a BASHED slot is refilled from (see _backfill_id_for): a
# destroyed game is replaced by another game connected to the same node, not by
# something off the route.
func _sorted_neighbors() -> Array:
	var nbrs: Array = []
	for gid in RunGraph.neighbors(GameState.current_game_id):
		if not GameLoop2.is_bashed(gid):
			nbrs.append(gid)
	var seed_key := _offer_seed()
	nbrs.sort_custom(func(a, b): return hash(seed_key + String(a)) < hash(seed_key + String(b)))
	return nbrs

# A-Z by the name printed on the card, case- and number-aware ("Spelunky 2" after
# "Spelunky", not between "Spelunky 10" and "Spelunky"). Falls back to the id for
# a game the catalogue has lost, so the sort can never crash the offering.
func _by_display_name(a, b) -> bool:
	return _display_name_of(a).naturalnocasecmp_to(_display_name_of(b)) < 0

func _display_name_of(id) -> String:
	var game: GameData = GameLoop2.game_at(StringName(id))
	if game == null:
		game = Data.get_game(StringName(id))
	return game.display_name if game != null else String(id)

# The game that would slide into the offering if `bashed_slot` were destroyed: the
# next connected, un-bashed game that isn't already on one of the other cards. &""
# when this node's connections are exhausted — the offering just loses the card.
func _backfill_id_for(bashed_slot: StringName) -> StringName:
	var offered: Dictionary = {}
	for c in _choices:
		offered[StringName(c["slot"])] = true
	for gid in _sorted_neighbors():
		if gid == bashed_slot or offered.has(gid):
			continue
		return gid
	return &""

# What the offering draw is keyed on. Stable for as long as the player stands
# where they are — bashing or transmuting one card must not reshuffle the others —
# and changed by exactly two things: a Scramble (_scramble_salt), and ARRIVING
# here again (_visits). The visit count is what makes a REVISIT a fresh decision:
# the same node hands you a different subset of its neighbours the second time
# through. (At a node with no more neighbours than the cap the slots can't change,
# so the reroll lands on the goal-enemies behind them, which are rolled fresh on
# every _build_choices anyway.)
func _offer_seed() -> String:
	var cur: StringName = GameState.current_game_id
	return "%s|%d|%d|" % [String(cur), _scramble_salt, int(_visits.get(cur, 0))]

func _build_choices() -> void:
	_choices.clear()
	# The distances the route badges quote are re-read with the offering rather
	# than cached for the run — the amulet and the game filter both outlive a
	# single draw, and neither is this screen's to assume.
	_rebuild_amulet_distances()
	_boss_round = _is_boss_round()
	var tier: int = _current_tier()
	# The enemy behind a slot is remembered for as long as the offering itself
	# stands, so re-drawing the cards (a bash refilling a slot, a transmute swapping
	# one) leaves the OTHER cards' enemies exactly as they were. Moving, scrambling
	# or crossing a difficulty gate is what re-rolls them.
	var enemy_key: String = "%s|%d|%s" % [_offer_seed(), tier, str(_boss_round)]
	if enemy_key != _slot_enemy_key:
		_slot_enemies.clear()
		_slot_enemy_key = enemy_key
	var amulet: StringName = GameState.amulet_game_id
	for gid in _offered_ids():
		var game: GameData = GameLoop2.game_at(gid)
		if game == null:
			continue
		var type_key: StringName = GameLoop2.game_type_key(game)
		var slot_key: String = "%s>%s" % [String(gid), String(game.id)]
		var enemy: GoalEnemyData = _slot_enemies.get(slot_key)
		if enemy == null:
			enemy = GameLoop2.roll_boss(type_key, tier) if _boss_round else GameLoop2.roll_enemy(type_key, tier)
			_slot_enemies[slot_key] = enemy
		_choices.append({
			"game": game, "enemy": enemy, "slot": gid,
			"boss": _boss_round, "amulet": gid == amulet,
			# Judged on the GAME, not the slot: a transmuted card plays the
			# replacement game, so that's the clear the Dash bonus keys off.
			"repeat": GameState.has_played_game(game.id),
		})

# --- rendering ------------------------------------------------------------

func _on_vitals_changed(_hp: int = 0, _max_hp: int = 0) -> void:
	_refresh_stats()

# A pickup changed the pack — so repaint EVERYTHING, not just the pack and the
# chip row.
#
# An item's payload lands on the run the instant it is picked up: passive
# stat_bonuses are folded in, item_acquired effects have already fired, a shield
# grant is already spendable, and a Mine-r Construction has already grown the
# board (GameLoop2.sync_grid_bounds hangs off this same signal). This used to
# relist the pack and repaint the chips only, which left the shield pips, the
# battlefield summary and the board itself quoting numbers from before the
# pickup until the next report came along to refresh them.
func _on_inventory_changed() -> void:
	if _stack == null:
		return
	_refresh_items()
	_refresh_stats()
	_refresh_attempts()
	_stack.text = "[b]Battlefield[/b]  —  " + _stack_summary()
	_refresh_stage()
	# The board is the one thing that has to wait. A repaint frees every body on
	# it, and the resolve animation is sliding those bodies — so a pickup that
	# lands mid-playback (an enemy drop, an event's payout) would wipe the
	# animation it arrived in the middle of. Deferred to _end_resolve instead,
	# which is the moment the board is the player's again.
	if _resolving:
		_board_dirty = true
		return
	_board.refresh()

func _refresh(_a = null) -> void:
	if _stack == null:
		return
	_refresh_stats()
	_refresh_items()
	_refresh_route_strip()
	_stack.text = "[b]Battlefield[/b]  —  " + _stack_summary()
	_board.refresh()
	_refresh_attempts()
	_refresh_stage()
	if not GameLoop2.last_result.is_empty():
		_log.text = _result_text(GameLoop2.last_result)
	if _phase == Phase.START_SELECT:
		# The Amulet is NAMED here, and named first: it is the thing all three roads
		# end on, so it belongs at the front of the sentence the roads are chosen in.
		_select_head.text = "The Amulet is %s. Choose where to start — three genres, all the same distance from it. The run opens on the one you take:" % amulet_name()
		# The start panel empties the controls row itself rather than going through
		# _render_controls, so the guard has to be told: a signature describing a
		# row that something else has since emptied is the one way it goes stale.
		_clear(_controls_row)
		_controls_sig = ""
		_render_start_choices()
		_populate_standing_checklist()
	elif _phase == Phase.SELECT:
		_select_head.text = ("Stay here, or head back? — open either to see where it leaves you:"
			if _asking_return() else "Choose a game to travel to:")
		_render_controls()
		_render_choices()
		# The standing goals change with the stack (a bomb, a fulfilment, a scroll),
		# so they're rebuilt with the rest of the screen. Safe here because nothing
		# in this list is a tick box holding player input — that only exists in the
		# report step, which _refresh deliberately doesn't touch.
		_populate_standing_checklist()
	elif _phase == Phase.PLAYING:
		_now_playing.text = _now_playing_text()
		# The cover of the game you are actually playing, and nothing else: what is
		# on the board is on the board (see the row's own comment).
		var game: GameData = _chosen.get("game")
		_now_playing_cover.texture = game.cover_image if game != null else null
	_fit_canvas_to_page.call_deferred()

# --- the page's own width --------------------------------------------------
#
# THE PAGE IS TWO COLUMNS AND THEY DO NOT SHRINK. The left is the offering — three
# covers side by side, or more with a game_choices bonus — and the right is the
# battlefield, which gains a column per difficulty tier. Neither is padded: both
# are as narrow as their contents allow already. So on a big board with a wide
# offering the pair is simply wider than the 1280 canvas, and what happened then
# was that the right-hand edge of the board went off the page — the scroll region
# hosting it draws no horizontal bar (SHOW_NEVER), by design, because a bar there
# is chrome rather than a fix.
#
# The fix is the other way round: the CANVAS is fitted to the page. The layout
# says how wide it needs to be, Settings widens the canvas to match, and the
# stretch draws the whole thing a little smaller inside the same window. Nothing
# is cropped and nothing has to be redesigned for the largest board it will ever
# have to hold.
#
# Deferred and measured off the ROOT's combined minimum size, because that is the
# one number that already accounts for every column, gutter and margin on the
# page — and it is only correct once Godot has laid the frame out, which is why
# every caller comes through call_deferred.
func _fit_canvas_to_page() -> void:
	if _scroll == null or not is_instance_valid(_scroll) or not is_inside_tree():
		return
	var root: Control = _scroll.get_child(0) as Control if _scroll.get_child_count() > 0 else null
	if root == null:
		return
	# The scroll's own left/right offsets are outside the content and have to be
	# paid for too, or the page fits by exactly the width of its margins.
	#
	# The HEADER is measured alongside it rather than through it: it used to be the
	# first row of `root` and so was already inside this number, and it is now on a
	# layer of its own (_mount_header). Left out, a long road-walked strip would
	# push the title and the menu off the right edge of a canvas that had been
	# fitted to the columns underneath and nothing else.
	var needed: float = root.get_combined_minimum_size().x
	if _header_bar != null and is_instance_valid(_header_bar):
		needed = maxf(needed, _header_bar.get_combined_minimum_size().x)
	Settings.request_canvas_width(int(ceil(needed + 32.0)))

# --- the road walked, across the top of the page ---------------------------
#
# The end-of-run screen has always drawn the run as a line of covers with arrows
# between them, and it is the clearest picture of a run this project has. It only
# ever appeared once the run was over. This is the same picture, live, in the
# header — games PLAYED only, oldest first, ending on the one underfoot.
#
# It has to share one 1280-wide row with the health chip, the gold chip, the
# title and the menu, and the page underneath it must still fit 720 without
# scrolling — so the covers are SMALL (STRIP_COVER) and carry no name, with the
# name on the hover instead. That is the trade the header can afford: the strip's
# job here is the SHAPE of the run, not a readable list of it, and the names are a
# tooltip away for anyone who wants them.
const STRIP_COVER := Vector2(34, 45)
const STRIP_ARROW := 15.0
# Past this many stops the oldest ones are dropped and an ellipsis stands in for
# them. A run of eight games fits comfortably; a run that has doubled back over a
# hub a dozen times does not, and the recent end of the road is the half worth
# keeping.
const STRIP_MAX_STOPS := 12

func _refresh_route_strip() -> void:
	if _route_strip == null:
		return
	_clear(_route_strip)
	# Nothing to draw before the run has a position. The strip stays MOUNTED and
	# expanding even when it is empty, rather than hiding: it is the header's
	# spacer as well as its picture, and a hidden Control takes no room — which is
	# what used to let the title and the menu slide to the LEFT of the header on
	# the start picker and jump to the right the moment the first game was taken.
	if _phase == Phase.START_SELECT or GameState.current_game_id == &"":
		return

	# GAMES PLAYED, and only games played. The strip used to close on the AMULET,
	# with the gap not yet walked drawn dashed — which meant the header carried a
	# cover for a game the player had never been to, sitting right beside the ones
	# they had, reading as "and then you went here". The road ahead has two screens
	# of its own (the 🗺 map and the route ladder); this one is the road BEHIND.
	#
	# Repeats included (GameState.walked_path): going back to a game is a real stop
	# on the road and the strip is the only place that says the run doubled back.
	var stops: Array = GameState.walked_path()

	var trimmed: bool = stops.size() > STRIP_MAX_STOPS
	if trimmed:
		stops = stops.slice(stops.size() - STRIP_MAX_STOPS)
	if trimmed:
		var more := Label.new()
		more.text = "…"
		more.tooltip_text = "Earlier games are off the end of the strip — the full road is on the 🗺 map."
		more.custom_minimum_size = Vector2(16, STRIP_COVER.y)
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		more.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		_route_strip.add_child(more)

	# `here` is the LAST stop, not every stop that happens to be this game: a run
	# that came back to a hub has that hub on the strip twice and only one of them
	# is where the player is standing.
	var last: int = stops.size() - 1
	for i in range(stops.size()):
		_route_strip.add_child(_strip_stop(stops[i], i == last))
		if i < last:
			_route_strip.add_child(_strip_arrow())

	# The strip takes the room the title and the chips leave and no more; anything
	# past that is clipped rather than allowed to push the menu button off the page.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_strip.add_child(spacer)

# One cover on the strip. `is_here` rings the game you are standing on; every
# other stop is a plain frame. There is no Amulet tile any more — see
# _refresh_route_strip: this strip is the road behind, and the Amulet is ahead.
func _strip_stop(id: StringName, is_here: bool) -> Control:
	var game: GameData = GameLoop2.game_at(id)
	if game == null:
		game = Data.get_game(id)
	var border: Color = UITheme.ACCENT if is_here else UITheme.BORDER
	var width: int = 2 if is_here else 1
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG_DEEP, 3, 1, width, border))
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_meta("stop", id)
	var name_text: String = game.display_name if game != null else String(id)
	frame.tooltip_text = ("▶ %s — you are here" if is_here else "%s") % name_text

	if game != null and game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = STRIP_COVER
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(art)
	else:
		var blank := Label.new()
		blank.custom_minimum_size = STRIP_COVER
		blank.text = name_text.substr(0, 2)
		blank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		blank.add_theme_font_size_override("font_size", 11)
		blank.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		frame.add_child(blank)
	return frame

func _strip_arrow() -> Control:
	var a := RunHistoryScreen.RouteArrow.new()
	a.custom_minimum_size = Vector2(STRIP_ARROW, STRIP_COVER.y)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return a

# The stops the strip is showing right now, oldest first. Public so a test can
# check the picture against the run without reading TextureRects.
func route_strip_stops() -> Array:
	var out: Array = []
	if _route_strip == null:
		return out
	for c in _route_strip.get_children():
		if c is PanelContainer and c.has_meta("stop"):
			out.append(c.get_meta("stop"))
	return out

# Put the page back at the top. Both phase changes want it: picking a game lands
# you on the board, reporting lands you back on the offering.
func _scroll_to_top() -> void:
	if _scroll != null:
		_scroll.set_deferred("scroll_vertical", 0)

# The stage is the same shape in both phases — checklist left, board (and the pack
# under it) right — because both halves matter whether or not a game is in play.
# What changes is the checklist's CONTENT: while you're choosing it lists the goals
# already on you (§ _populate_standing_checklist), and while you're playing it
# becomes the report step for the game in hand. The offering sits above the pair
# and disappears once you've committed.
func _refresh_stage() -> void:
	if _stage_panel == null:
		return
	# The offering box hosts the choose-your-start cards too, so it's up in both
	# choosing phases; the scrolls panel isn't — there's nothing to read before the
	# run has a position. Both come straight back the moment a game is reported,
	# resolve animation or not: the board plays out beside the offering, not
	# instead of it (_hold_for_resolve).
	var choosing: bool = _phase == Phase.SELECT or _phase == Phase.START_SELECT
	_select_box.visible = choosing
	# The offering's frame goes with it, or an empty bordered box sits above the
	# checklist between games.
	var select_wrap = _select_box.get_meta("wrap", null)
	if select_wrap is Control:
		(select_wrap as Control).visible = choosing
	_play_panel.visible = _phase != Phase.OVER or _resolving
	_report_panel.visible = _phase != Phase.OVER or _resolving
	# The report-only parts of the panel: without a game in hand there is nothing to
	# launch, retry or complete.
	var playing: bool = _phase == Phase.PLAYING
	_np_box.visible = playing
	_attempt_wrap.visible = playing
	_done_btn.visible = playing
	# The page just changed height around the shop, so where it sits relative to
	# the window has changed with it.
	_update_shop_hint()

# The row above the offering. Dash and Scramble used to keep their buttons here
# AND their counts on the HUD; they are one chip apiece on the stat row under the
# offering now (_refresh_select_stats), so the only thing left to say up here is
# that a Dash is currently open — that's a MODE the offering is in, and it has to
# be stated where the cards it changes are.
func _render_controls() -> void:
	# Three inputs, and the row is empty for most of a run — so the guard is on the
	# signature alone rather than on the signature plus a child count, since "no
	# children" is a legitimate thing for it to have last drawn.
	var sig: String = "%s|%s|%s" % [str(_asking_return()), str(_dash_mode),
		String(_last_played_game.id) if _last_played_game != null else ""]
	if sig == _controls_sig:
		return
	_controls_sig = sig
	_clear(_controls_row)
	if _asking_return():
		var note := Label.new()
		note.text = "The detour is over — pick where the run carries on from."
		note.add_theme_color_override("font_color", UITheme.ACCENT)
		_controls_row.add_child(note)
		return
	if _dash_mode:
		var hint := Label.new()
		hint.text = "⚡ Dash — pick ANY connected game:"
		hint.add_theme_color_override("font_color", DASH_BLUE)
		_controls_row.add_child(hint)
		_controls_row.add_child(_mini_button("Cancel", cancel_dash))
	# Rating is opt-in and lives on a button (it never pops itself up): the game you
	# last reported on stays scorable from here until you report another.
	if _last_played_game != null:
		var game: GameData = _last_played_game
		var rate := Button.new()
		rate.text = "★ Rate %s" % game.display_name
		rate.tooltip_text = "Score %s 1-10 on your tier list." % game.display_name
		rate.add_theme_color_override("font_color", UITheme.GOLD)
		rate.pressed.connect(func(): _prompt_rating(game))
		_controls_row.add_child(rate)

# --- the offering ------------------------------------------------------------
#
# The cards you choose your next game from, in both choosing phases, and the
# hover line under them, all live in OfferingCards. The page owns the three
# containers it fills (_choices_row, _preview, _preview_art) and decides when
# they are redrawn; these forwards keep the names the rest of this file, and the
# tests, already call.

func _render_start_choices() -> void:
	if _offering != null:
		_offering.render_start()

func _render_choices() -> void:
	if _offering != null:
		_offering.render()

func _show_preview(index: int) -> void:
	if _offering != null:
		_offering.show_preview(index)

func _clear_hover_grant() -> void:
	if _offering != null:
		_offering.clear_hover_grant()

# The "you can beat this" row a card and its popup both wear, and the two lines
# the escort warning is written as — read by the offered-game popup
# (GameChoiceModal) as well as by the cards themselves.
func _beatable_row(choice: Dictionary) -> Control:
	return _offering.beatable_row(choice)

func _enemy_hidden(choice: Dictionary) -> bool:
	return _offering.enemy_hidden(choice) if _offering != null else false

func _escort_note(choice: Dictionary) -> String:
	return _offering.escort_note(choice) if _offering != null else ""

# The Amulet, by name.
#
# It used to be the run's one secret until a start had been committed to: the
# picker quoted the DISTANCE and the maps drew the destination as an unnamed box.
# That is over — the Amulet is named from the first screen of the run, because
# choosing a start is a routing decision and the game the road ends on is half of
# what makes one road different from another.
#
# Falls back to "the Amulet" rather than an empty string, so the lines that quote
# it still read as sentences before an amulet has been rolled (the main menu's
# custom-run preview, and any test that builds a card without a run).
func amulet_name() -> String:
	var game: GameData = Data.get_game(GameState.amulet_game_id)
	return game.display_name if game != null else "the Amulet"

# The distance line every start card wears, and the same line inside the popup it
# opens: how far the Amulet is AND which game it is. One function because the two
# must not drift, and because "5 games from Guild of Dungeoneering" is the whole
# sentence — the number on its own was never the interesting half.
func _start_distance_text(hops: int) -> String:
	return "%d game%s from %s" % [hops, "" if hops == 1 else "s", amulet_name()]

# --- the report checklist ---------------------------------------------------
#
# The left column in both its states — the standing list while you're choosing,
# the tick-box report step while you're playing — and the pairing between a
# checklist row and a body on the board all live in ReportChecklist. The page
# owns the two containers it fills (_verify_box, _launch_row) and decides when it
# is rebuilt; these forwards keep the names the rest of this file, and the tests,
# already call. A few of them (verify_row, hover_targets, light_bodies) have no
# caller left in here and exist for the tests, which drive the checklist through
# the page the way a player does.

func _populate_play_panel() -> void:
	if _checklist != null:
		_checklist.populate_play_panel()

func _populate_standing_checklist() -> void:
	if _checklist != null:
		_checklist.populate_standing()

func _resolve_event_goal_rows() -> void:
	if _checklist != null:
		_checklist.resolve_event_goals()

func _announce_status_penalties(res: Dictionary) -> void:
	if _checklist != null:
		_checklist.announce_status_penalties(res)

func _bind_row_to_body(row: Control, instance: int, paint: Callable) -> void:
	if _checklist != null:
		_checklist.bind_row_to_body(row, instance, paint)

func _light_bodies(instances: Array) -> void:
	if _checklist != null:
		_checklist.light_bodies(instances)

func _on_enemy_hovered(instance: int, hovered: bool) -> void:
	if _checklist != null:
		_checklist.on_enemy_hovered(instance, hovered)

func _hover_targets(frame: Control) -> Array:
	return _checklist.hover_targets(frame) if _checklist != null else [frame]

func _verify_row(text: String, color: Color, emphasise: bool,
		enemy: GoalEnemyData = null, character: CharacterData = null,
		instance: int = 0) -> Dictionary:
	return _checklist.verify_row(text, color, emphasise, enemy, character, instance)

# Open the tier-list rating prompt for `game` (1-10 + optional notes). Submitting
# records the score via TierList (dropping the game into the Unranked tray the
# first time) and then OPENS THE TIER LIST on top, so the score the player just
# gave lands somewhere they can see it and drag it into a row while the game is
# still fresh. "Maybe later" just closes, and takes them nowhere — declining to
# rate shouldn't hand them a screen they didn't ask for. Pre-fills when already
# rated so the player updates rather than starts over.
func _prompt_rating(game: GameData) -> void:
	if game == null:
		return
	var modal = preload("res://scripts/ui/RateGameModal.gd").new()
	modal.setup(game.id, game)
	modal.submitted.connect(func(score: int, notes: String):
		TierList.set_rating(game.id, score, notes)
		modal.queue_free()
		open_tier_list())
	modal.dismissed.connect(func(): modal.queue_free())
	add_child(modal)

# The tier-list board over the run. Its own method so the rating flow and any
# future entry point open it the same way, and so a headless test can drive it.
func open_tier_list() -> TierListScreen:
	var screen := TierListScreen.open(self)
	# The one screen the overworld opens that REPLACES the page rather than sitting
	# over it: it is a full-screen board with its own header and its own way out,
	# and the run's header bar floats above everything on this page — including
	# that way out. So the bar stands down for as long as the board is up. (The
	# Atlas and the end-of-run verdict need no such handling: they are mounted on
	# layers above HEADER_LAYER and cover it on their own.)
	_show_header(false)
	screen.tree_exiting.connect(func(): _show_header(true))
	return screen

# Whether the pinned header bar is drawn. The page keeps its inset either way —
# a screen standing in front of it is not a cue to reflow what is behind it.
func _show_header(shown: bool) -> void:
	if _header_layer != null and is_instance_valid(_header_layer):
		_header_layer.visible = shown
	# A bar that isn't drawn is standing on nothing, and a screen that stood in
	# front of it must not be pushed down by a strip it can't see.
	_publish_header_strip(shown)

# The instances the player ticked as fulfilled this game.
func _ticked_fulfilments() -> Array:
	return _checklist.ticked_fulfilments() if _checklist != null else []

# The ticked STATUS rows, in the shape beat_game's `claims` wants (§13). Returned
# even when nothing at all is ticked: an EMPTY report is the answer a missed
# `demand` is billed for, and a caller handed {} could not tell "nothing was
# ticked" from "no checklist asked".
func _ticked_status_claims() -> Dictionary:
	if _checklist == null:
		return {"status_goals": [], "bonuses": [], "instead": []}
	return _checklist.ticked_status_claims()

# Apply one level-up for the 2.0 character (§3.1): its level_up_stats plus the
# reward, then re-roll for a Crown-style bonus level. Reuses GameState's existing
# apply_level_up_stats (its stat vocabulary already covers the 2.0 verbs) and the
# grant_chest/add_loot reward paths — no combat machinery. Capped so a 100%
# bonus-chance item can't loop forever.
func _apply_level_up() -> void:
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch == null or ch.level_up_condition == "":
		return
	var bonus_levels: int = 0
	while true:
		# One level, stats and reward — GameState.grant_level_up. What is left here
		# is the two things that are about EARNING one rather than about what one is
		# worth: the condition checked above, and the bonus-level chain below.
		# Potion of Raise Level calls the same function with neither.
		GameState.grant_level_up(_rng)
		if bonus_levels >= 10 or not _roll_bonus_level_up():
			break
		bonus_levels += 1
	# Zoe's condition is literally "Perfect a Game" — mark the perfect flag so
	# perfect-aware items can fire on it.
	if ch.level_up_condition.to_lower().contains("perfect"):
		GameState.last_game_perfected = true

# Bank one enemy defeat against both records that care about it: the game it
# happened at, and the character who was playing.
func _record_defeat(game: GameData, enemy: GoalEnemyData) -> void:
	GameStats.record_enemy_beaten(game.id, enemy.id)
	GameStats.record_character_enemy(GameState.character_id, enemy.id)

# Crown (§8): true if any owned item's bonus_level_up_chance rolls a hit.
func _roll_bonus_level_up() -> bool:
	for it in GameState.inventory:
		if it is ItemData and it.bonus_level_up_chance > 0.0 and randf() < it.bonus_level_up_chance:
			return true
	return false


# The line beside the cover on the report panel: WHAT YOU ARE PLAYING, and what
# taking it put on the board.
#
# It used to print the whole enemy preview here — the enemy's name, its goal, its
# stats — as though the game came with a boss attached. It doesn't
# (GameLoop2.arrivals): what walked on is on the board and in the checklist with
# everything else, so this says that it walked on and stops. The one thing that IS
# a fact about the game keeps its line: a rematch pays a Dash.
func _now_playing_text() -> String:
	if _chosen.is_empty():
		return ""
	var out: String = "[b]Now playing:[/b] %s" % _chosen["game"].display_name
	var arrived: Array = []
	var landed: Dictionary = GameLoop2.arrival()
	if not landed.is_empty() and landed.get("enemy") != null:
		arrived.append((landed["enemy"] as GoalEnemyData).display_name)
	var escort: GoalEnemyData = GameLoop2.escort_enemy()
	if escort != null:
		arrived.append(escort.display_name)
	if arrived.is_empty():
		out += "\n[i]Nothing walked on with it.[/i]"
	else:
		out += "\n[color=#%s]%s walked onto the board — tick %s below if you clear %s.[/color]" % [
			UITheme.DANGER.to_html(false), " and ".join(arrived),
			"them" if arrived.size() > 1 else "it",
			"their goals" if arrived.size() > 1 else "its goal"]
	if bool(_chosen.get("repeat", false)):
		out += "\n[color=#80d9ff]⚡ Already beaten this run — beating it again grants +%d Dash.[/color]" % REPEAT_BEAT_DASH
	return out

# --- the run's numbers, where they are spent ------------------------------
#
# There is no HUD strip any more. It was twelve numbers across the top of the
# page, then two (Health and Shields) plus a status strip once the verbs moved
# out — and those last two were never its own reading anyway: the BOARD draws the
# hero with `♥ hp/max` under the portrait, the shield pips over it, and the
# player's status pips between them (BattlefieldView._hero_hp / _hero_shields /
# _hero_statuses). The panel was quoting the board back at itself for 44px and a
# separator, so it is gone and the board is the one place the player's own state
# is drawn.
#
# What is left is the two chip rows, each under the thing its charges are spent
# on. They repaint together, and they repaint off the same signals the HUD did:
# an item from a kill-drop or a chest can hand you a Bash between one frame and
# the next, and the number on screen has to agree immediately.
# The always-on Health readout. Mounted on the header rather than in the stats
# strip so that nothing — no modal, no reward screen, no scroll position — can
# put it out of sight. Repainted from _refresh_stats, which every hp_changed and
# stats_changed already routes through.
func _build_health_chip() -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.18, 0.06, 0.06, 0.85), 8, 8, 1, UITheme.DANGER.lerp(UITheme.BORDER, 0.4)))
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_health_chip = Label.new()
	_health_chip.add_theme_font_size_override("font_size", 18)
	_health_chip.add_theme_color_override("font_color", Color(1.0, 0.62, 0.62))
	_health_chip.tooltip_text = "Health. At zero the run ends."
	wrap.add_child(_health_chip)
	_paint_health_chip()
	return wrap


# The purse, immediately right of Health in the header (§14). It sits there for
# the same reason Health does: it is a number the player has to be able to check
# without leaving whatever is mounted over the board, and a shop's prices are
# meaningless without it. Health first, gold second — one ends the run, the other
# only decides what you can afford.
func _build_gold_chip() -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.16, 0.13, 0.05, 0.85), 8, 8, 1, UITheme.GOLD.lerp(UITheme.BORDER, 0.4)))
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_chip = Label.new()
	_gold_chip.add_theme_font_size_override("font_size", 18)
	_gold_chip.add_theme_color_override("font_color", UITheme.COIN_GOLD)
	_gold_chip.tooltip_text = ("Gold. +%d for every enemy you defeat, +%d for a boss."
		+ "\nSpent at the shops standing on the map's biggest games."
		+ "\nIt does not carry over — a run ends with whatever you didn't spend.") % [
			GameLoop2.GOLD_PER_ENEMY, GameLoop2.GOLD_PER_BOSS]
	wrap.add_child(_gold_chip)
	_paint_gold_chip()
	return wrap

func _paint_gold_chip() -> void:
	if _gold_chip == null or not is_instance_valid(_gold_chip):
		return
	_gold_chip.text = "◉  %d" % GameState.gold
	# Dimmed at zero: an empty purse is worth reading as empty rather than as a
	# number, since it's the state where every shop price is out of reach.
	_gold_chip.add_theme_color_override("font_color",
		UITheme.COIN_GOLD.lerp(UITheme.TEXT_DIM, 0.55) if GameState.gold <= 0 else UITheme.COIN_GOLD)


func _paint_health_chip() -> void:
	if _health_chip == null or not is_instance_valid(_health_chip):
		return
	# THE SHIELDS THAT STAY RIDE THE HEALTH CHIP (§4.3). They are the one pool gained off
	# the board — a pill taken on the overworld, a game Barricade banked — so they
	# have to be readable when no board is on screen, and the number they matter
	# most beside is the one they are standing in front of.
	_health_chip.text = "♥  %d / %d" % [GameState.hp, GameState.max_hp]
	if GameState.bonus_shields > 0:
		_health_chip.text += "   ◈ %d" % GameState.bonus_shields
		_health_chip.tooltip_text = ("Health. At zero the run ends."
			+ "\n\n◈ %s — gained off the board, used after the game's own Temporary"
			+ " Shields are gone, and they never expire.") % GameState.shields_text(
				GameState.bonus_shields)
	else:
		_health_chip.tooltip_text = "Health. At zero the run ends."
	# It goes white-hot at a quarter left, because the number people miss is the
	# one that stopped being comfortable rather than the one that hit zero.
	var frac: float = float(GameState.hp) / maxf(1.0, float(GameState.max_hp))
	_health_chip.add_theme_color_override("font_color",
		UITheme.DANGER.lerp(Color.WHITE, 0.35) if frac <= 0.25 else Color(1.0, 0.62, 0.62))


func _on_gold_changed(_amount: int = 0) -> void:
	_paint_gold_chip()


func _refresh_stats(_a = null) -> void:
	_paint_health_chip()
	_paint_gold_chip()
	_refresh_select_stats()
	# …and the hero with them, because the board is where Health, Shields and the
	# player's statuses are now drawn. These signals used to land on a HUD strip
	# that repainted immediately while the board waited for the next full refresh;
	# with the strip gone they have to reach the hero, or a Hollow Heart taken off
	# a kill-drop raises Max Health with nothing on screen saying so.
	if _board != null:
		_board.refresh_hero()

# --- the stats that moved out of the HUD ------------------------------------

const STAT_FONT := 13

# One stat, as a chip: the glyph, the name and the count, dimmed to nothing when
# there is nothing to spend.
#
# A verb the player can fire FROM HERE (Dash, Scramble — both act on the offering
# as a whole) is a real button. One that needs a target (Bash and Transmute both
# act on a specific offered game, Push and Bombs on a specific enemy) is a
# readout, and its tooltip says where it actually gets spent, so a charge is never
# a number with no visible way to use it.
func _stat_chip(text: String, count: int, tint: Color, tip: String,
		fire: Callable = Callable()) -> Control:
	var live: bool = count > 0
	if fire.is_valid() and live:
		var b := Button.new()
		b.text = text
		b.tooltip_text = tip
		b.add_theme_font_size_override("font_size", STAT_FONT)
		b.add_theme_stylebox_override("normal", UITheme.flat(tint.lerp(UITheme.BG, 0.78), 6, 8, 1, tint.lerp(UITheme.BG, 0.4)))
		b.add_theme_stylebox_override("hover", UITheme.flat(tint.lerp(UITheme.BG, 0.58), 6, 8, 1, tint))
		b.add_theme_color_override("font_color", tint)
		b.pressed.connect(fire)
		return b
	var color: Color = tint if live else UITheme.TEXT_FAINT
	var chip := PanelContainer.new()
	chip.tooltip_text = tip
	chip.add_theme_stylebox_override("panel",
		UITheme.flat(color.lerp(UITheme.BG, 0.86), 6, 8, 1, color.lerp(UITheme.BG, 0.55)))
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", STAT_FONT)
	label.add_theme_color_override("font_color", color)
	chip.add_child(label)
	return chip

# The charges that are spent CHOOSING — mounted under the offering, because every
# one of them changes what is on the table rather than what is on the board.
func _refresh_select_stats() -> void:
	if _select_stats == null:
		return
	# Everything drawn below is one of these six, so the signature is the whole of
	# what a rebuild could possibly change: the four verb counts, Luck (its own
	# chip, and the odds quoted in that chip's tooltip), and _dash_mode, which
	# decides whether Dash is a live button or a readout.
	var luck: int = Stats.get_value(&"luck")
	var sig: String = "%d|%d|%d|%d|%d|%s" % [GameState.bash, GameState.dash_charges,
		GameState.transmute, GameState.scramble, luck, str(_dash_mode)]
	if sig == _select_stats_sig and _select_stats.get_child_count() > 0:
		return
	_select_stats_sig = sig
	_clear(_select_stats)
	_select_stats.add_child(_stat_chip("⛏ Bash %d" % GameState.bash, GameState.bash,
		Color(1.0, 0.72, 0.4),
		"Destroy an offered game outright — it leaves the pool for good and another connected game takes the slot.\nSpent from a game's card: click one and press Bash."))
	_select_stats.add_child(_stat_chip("⚡ Dash %d" % GameState.dash_charges,
		GameState.dash_charges, DASH_BLUE,
		"Ignore the offering and travel to ANY connected game.\nClick to pick your destination.",
		dash if not _dash_mode else Callable()))
	_select_stats.add_child(_stat_chip("⚗ Transmute %d" % GameState.transmute, GameState.transmute,
		UITheme.ACCENT,
		"Swap an offered game for a random off-graph game of the same type.\nSpent from a game's card: click one and press Transmute."))
	_select_stats.add_child(_stat_chip("🎲 Scramble %d" % GameState.scramble, GameState.scramble,
		UITheme.GOLD,
		"Redraw the whole offering — new games in the slots, each with a fresh goal-enemy.",
		scramble))
	# Luck rides with the verbs rather than in the header beside Health and Gold,
	# because it is not a resource you spend — it is a thing that is true about
	# every roll the run makes, and the verbs are where the player is already
	# reading what they can do to the offering. Drawn even at zero, so the stat is
	# discoverable before a Clover ever turns up.
	_select_stats.add_child(_stat_chip("🍀 Luck %d" % luck, luck, LUCK_GREEN,
		"Every roll in the run is made %d extra time%s and the %s result kept.\n"
		% [absi(luck), "" if absi(luck) == 1 else "s",
			"better" if luck >= 0 else "worse"]
		+ "Rarity ladders, event gambles, machine odds — anything with a better "
		+ "side to land on.\nA 25%% chance is really %s%% at this much Luck."
		% EventSystem.percent_text(Stats.effective_chance(25.0, Stats.Favour.HIGH))))

# The pack strip above the board is built by PackStrip; the page owns the
# container and decides WHEN it is redrawn, the strip decides what goes in it.
# `_phase` is read here rather than there so the strip needs nothing of the
# page's state — only the one bit of it that changes what a token can do.
func _refresh_items() -> void:
	if _pack != null:
		_pack.rebuild(_phase == Phase.PLAYING)
	refresh_loot_window()

# Redraw the loot toggle and, when it is open, the panel it opens. Public because
# the window itself calls it after a toggle — the window owns whether it is open,
# the page owns when anything gets redrawn.
func refresh_loot_window() -> void:
	if _loot_window == null:
		return
	_loot_window.rebuild(_phase == Phase.PLAYING)

# TAB OPENS THE PACK. The `backpack` action has been sitting in project.godot with
# nothing on the overworld listening for it — only the Collection, which reads it
# to close itself and is never on screen at the same time as this, so the key was
# free. The loot window is the thing you open and shut most often in a run, and it
# is the only pack surface that has to be opened at all.
#
# Not while a modal is up: a drop is being decided, a card is being read, or the
# run is over, and in all three the pack behind them is not the thing the key is
# about. Nothing else on this page takes a key, so this is the whole of its input.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("backpack"):
		return
	if _loot_window == null or _phase == Phase.OVER:
		return
	if _drop_modal != null and is_instance_valid(_drop_modal):
		return
	if _item_card != null and is_instance_valid(_item_card):
		return
	_loot_window.open = not _loot_window.open
	refresh_loot_window()
	get_viewport().set_input_as_handled()

# Mount the loot window's panel OVER THE BOARD (§4.3). A page child rather than a
# row in the pack, so opening it moves nothing.
#
# It opens on the BATTLEFIELD, directly under the toggle that opened it: the pack
# strip sits on top of the board, so the window drops out of its own button rather
# than appearing across the page from it. The board is also the right thing to
# cover — it is a picture of what is chasing you, which does not change while you
# decide which pill to take, where the offering on the left is the decision you
# might be taking the pill in order to make.
#
# Positioned against `_stage_panel`'s own rect rather than at a hardcoded corner,
# so it lands on the board whatever size the page gave it, and clamped so a narrow
# window can't push it off an edge. Nudged below the header for the same reason
# every modal is: the header is opaque and drawn over the page.
func mount_loot_overlay(panel: Control) -> void:
	unmount_loot_overlay()
	if panel == null:
		return
	_loot_panel = panel
	panel.top_level = true
	add_child(panel)
	_place_loot_overlay()
	# The board's rect is not final when a panel is built mid-frame, and it keeps
	# moving afterwards as the page settles — a toast arriving, the checklist
	# growing a row, a report regrowing the left column. So the placement FOLLOWS
	# the board (see _follow_loot_overlay) rather than being computed once, and one
	# deferred pass catches the settle that has already happened.
	set_process(_wants_process())
	_place_loot_overlay.call_deferred()

func unmount_loot_overlay() -> void:
	if _loot_panel != null and is_instance_valid(_loot_panel):
		_loot_panel.queue_free()
	_loot_panel = null
	_loot_anchor_rect = Rect2()
	set_process(_wants_process())

func _place_loot_overlay() -> void:
	if _loot_panel == null or not is_instance_valid(_loot_panel):
		return
	var anchor: Control = _stage_panel if _stage_panel != null and is_instance_valid(_stage_panel) \
		else _left_col
	if anchor == null or not is_instance_valid(anchor):
		return
	# SIZED TO ITS CONTENTS, not to the page. A floating Control is anchored to its
	# parent's rect, and this page is as tall as the whole scrolling document — so
	# left alone the panel stretched to 1043px and hung off the bottom of the
	# window with 700px of its own background under a 258px grid.
	_loot_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_loot_panel.size = _loot_panel.get_combined_minimum_size()
	# CENTRED ON THE BOARD, not pinned to its corner: the board is wider than the
	# window and a panel in the top-left of it reads as something that has come
	# loose. Clamped to the screen afterwards, so a board pushed off the bottom of a
	# short window still leaves the whole panel reachable.
	var on: Rect2 = anchor.get_global_rect()
	_loot_anchor_rect = _stage_panel.get_global_rect() if _stage_panel != null \
		and is_instance_valid(_stage_panel) else on
	var size: Vector2 = _loot_panel.size
	var screen: Vector2 = get_viewport_rect().size
	var x: float = clampf(on.position.x + (on.size.x - size.x) * 0.5,
		4.0, maxf(4.0, screen.x - size.x - 4.0))
	var y: float = clampf(on.position.y + 8.0,
		ModalScaffold.reserved_top + 4.0, maxf(ModalScaffold.reserved_top + 4.0,
			screen.y - size.y - 4.0))
	_loot_panel.global_position = Vector2(x, y)

# Open the reading card for one item. Firing from the card routes through the same
# use_item the token's button does, so there is one spend path.
func open_item_card(item: ItemData) -> void:
	if item == null:
		return
	_close_item_card()
	var active: bool = item.kind == ItemData.ItemKind.USABLE or item.is_charged()
	# The same rule the pack strip's own Use button spends, asked in one place: a
	# CHARGED active fires whenever its bar is full, the report step included, and
	# a USABLE consumable still waits for the game to be reported.
	var usable: bool = active and GameState.can_fire_item(item) \
		and PackStrip.fires_while_reporting(item, _phase == Phase.PLAYING)
	var card := ItemInfoCard.new()
	card.use_requested.connect(use_item)
	card.closed.connect(func(): _item_card = null)
	add_child(card)
	_item_card = card
	card.setup(item, usable)

func _close_item_card() -> void:
	if _item_card != null and is_instance_valid(_item_card):
		_item_card.close()
	_item_card = null

# The same gesture for a piece of loot: clicking one in the window opens its card,
# and firing it from there goes back through `use_loot` — the same verb the
# window's own Use button calls, so reading a pill can never spend it (§4.3).
# It rides `_item_card` because the two cards are the same slot on the screen and
# only one of them can be open at a time.
func open_loot_card(index: int) -> void:
	if index < 0 or index >= GameState.loot_items.size():
		return
	var entry = GameState.loot_items[index]
	if not (entry is Dictionary):
		return
	_close_item_card()
	var card := LootInfoCard.new()
	card.use_requested.connect(use_loot)
	card.closed.connect(func(): _item_card = null)
	add_child(card)
	_item_card = card
	# ALWAYS SPENDABLE (§4.3). The mid-report lock holds the pack still; it does
	# not stop a piece being used, and a piece whose effect cannot land right now
	# fizzles rather than being refused.
	card.setup(entry, index, true)

# The hover model for a carried item, kept on the page as the name the shop's
# shelf and the drop modal already reach for. PackStrip.item_hover is the one
# implementation.
func item_hover(item: ItemData, active: bool, ready: bool, reporting: bool) -> Dictionary:
	return PackStrip.item_hover(item, active, ready, reporting)

# One-line header above the follower cards: how many are on your tail and the
# damage the stack lands on the next game beaten — which, once enemies take more
# than one turn a game, includes the rank behind the front line, because it walks
# into range and swings before the game is out (§7.4). Counting the swings rather
# than the bodies is what keeps this line honest at three turns a game.
#
# The count is `stack` and nothing else. It used to add one for the game in play,
# from the era when that enemy waited off the field and was not in the stack — it
# has stood on the board with everything else since §7.2, so the extra 1 was
# counting it twice, and the line said "3 closing in" over a board holding two.
# Noticed because the escort (§7.5) makes every playing board a two-body board,
# where an off-by-one reads as the escort having been counted rather than as the
# old bug it is.
func _stack_summary() -> String:
	var following: int = GameLoop2.stack.size()
	if following == 0:
		return "clear  —  nothing following you"
	# Priced in LOST RUNS (§3.2), because that is the threat the player is deciding
	# against: reporting a game moves nobody out in the wilds, and what the strip
	# has to answer is "what does it cost me to go and fail at this again".
	var dmg: int = GameLoop2.damage_per_lost_run()
	var swings: int = 0
	for entry in GameLoop2.stack:
		swings += GameLoop2.attacks_in_turns(entry)
	if swings == 0:
		return "%d closing in, none of them in reach yet" % following
	return "%d closing in, %d swing%s for %d damage on every lost run" % [
		following, swings, "" if swings == 1 else "s", dmg]


# --- kill-drops (§8) -------------------------------------------------------

# A defeated enemy dropped LOOT: roll the piece it left and lay it on the square
# it died in. Skipped once the run is over (win/lose screens take over the board).
#
# WHY LOOT AND NOT A RELIC (§8.2). A body used to drop a chest, and a chest is a
# question the board is not allowed to answer: its card deliberately does not say
# what is inside, so what stood on the square was a gold glyph standing in for an
# offer you could only read by opening it. A scroll, a pill or a potion IS a
# thing — it can be drawn as itself, on its own square, and recognised across the
# board while a body is still walking at you. So the floor pays loot, and the
# relics moved to the reward screen where the choosing belongs
# (GameLoop2.claim_chests, spent in _queue_report_chests).
#
# One piece per body, rolled on the same three-way scroll/pill/potion split as a
# game's own payout (§4.3) — a boss included. What a body is worth in RELICS is
# its difficulty, and that is banked rather than dropped (GameLoop2._defeat).
func _on_enemy_defeated(enemy: GoalEnemyData, cell: Vector2i) -> void:
	if GameLoop2.run_over:
		return
	var from_boss: bool = enemy != null and enemy.is_boss()
	var entry: Dictionary = GameState.roll_loot_entry("loot")
	if entry.is_empty():
		return
	# ON THE FLOOR, where the body fell (§8.2). A kill you make mid-game puts its
	# payout on the board in front of you rather than behind a screen you have not
	# reached yet — that is what makes clearing a goal DURING a game worth doing.
	# What nobody picks up is swept onto the haul screen when the game is reported
	# (_sweep_floor_into_the_queue).
	if cell == GameLoop2.OFF_FIELD \
			or GameLoop2.place_drop(cell, entry, from_boss) == GameLoop2.OFF_FIELD:
		# Nowhere on the board for it — a body still in the off-grid queue has no
		# square to fall in, and a full floor has no room left. It goes straight to
		# the screen the game ends on, which is where an unclaimed piece ends up
		# anyway.
		_drop_queue.append({"loot": [entry]})
		_pump_drops()
	if _board != null:
		_board.refresh()

# --- picking a piece up off the floor (§8.2) -------------------------------
#
# THE GESTURE IS THE WHOLE INTERACTION. Dragging a token off a board square
# (`FloorLoot`) puts the pack on screen beside the board for as long as the piece
# is in the air (`DragPackPanel`), and letting go — in a slot, on the bin, or on
# nothing at all — ends both.
#
# It replaces a click that opened the LootDropModal, whose entire contribution to
# a one-piece decision was drawing the nine slots this drag now drops straight
# into. The modal is still what a REPORT's handful is answered on; it is no longer
# the toll on picking one thing up.

# A piece dragged off the floor and into slot `slot` of the 3x3.
#
# TWO OUTCOMES, and which one it is depends on whether that slot was occupied:
#   free   — the piece goes in and the square is cleared.
#   filled — the two TRADE: the carried piece comes out and lands on the square
#            this one came off, which is the answer to a full pack that only a
#            floor take can give (LootGrid.can_accept). The square is never left
#            empty by a swap, so a mistake costs a drag rather than a piece.
func take_floor_loot(entry: Dictionary, slot: int, cell: Vector2i) -> void:
	if GameLoop2.run_over or entry.is_empty():
		return
	var held: Dictionary = GameLoop2.drop_at(cell)
	# The square is what says the piece is still there to be taken. A payload from a
	# drag whose square has since been swept (a report resolving underneath it) is
	# refused rather than minting a second copy of the piece.
	if held.is_empty() or _floor_loot(held) != entry:
		return
	var displaced: Dictionary = GameState.swap_loot_entry_at(entry, slot)
	if displaced.is_empty() and not GameState.take_loot_entry_at(entry, slot):
		return
	GameLoop2.take_drop(cell)
	if not displaced.is_empty():
		# Back onto the square the new piece came off — and NOT as a boss's drop
		# whatever was on that square before, because a piece out of your own pack
		# was not left there by anything.
		GameLoop2.place_drop(cell, displaced)
		GameLog.add("Traded %s for %s." % [LootSystem.display_name(displaced),
			LootSystem.display_name(entry)], Color(0.72, 0.62, 0.86))
	else:
		GameLog.add("Picked up %s." % LootSystem.display_name(entry),
			Color(0.72, 0.62, 0.86))
	if _board != null:
		_board.refresh()
	refresh_loot_window()

# A piece dragged off the floor and onto the bin. It ASKS FIRST, on the same terms
# a carried piece binned in the loot window does (LootTrash.confirm): this is the
# one gesture on the board that destroys something and gives nothing back, and it
# is a strictly worse outcome than the thing that happens if you do nothing at all
# — a piece left lying is swept onto the haul screen and is still yours.
func bin_floor_loot(cell: Vector2i) -> void:
	if GameLoop2.run_over:
		return
	var entry: Dictionary = _floor_loot(GameLoop2.drop_at(cell))
	if entry.is_empty():
		return
	LootTrash.confirm(self, LootSystem.display_name(entry), func():
		# Re-read on the way through: the confirmation is a screen the player spends
		# time on, and the square may have been swept by a report behind it.
		if _floor_loot(GameLoop2.drop_at(cell)) != entry:
			return
		GameLoop2.take_drop(cell)
		GameLog.add("Threw away %s." % LootSystem.display_name(entry),
			Color(0.8, 0.8, 0.8))
		if _board != null:
			_board.refresh())

# THE PACK, MOUNTED FOR THE LENGTH OF A DRAG. `NOTIFICATION_DRAG_BEGIN` reaches
# every Control in the tree the moment a drag starts anywhere in the viewport,
# which is the one signal that means "the player's hand is full" — so the page
# hangs the panel off it and takes it away again on DRAG_END.
#
# Only for a piece off the FLOOR. Dragging inside the loot window or the drop
# modal already has a pack in front of it, and a second one arriving beside the
# board would be the page answering a question nobody asked.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			var data = get_viewport().gui_get_drag_data() if get_viewport() != null else null
			if data is Dictionary and (data as Dictionary).has("floor"):
				_mount_drag_pack()
		NOTIFICATION_DRAG_END:
			_unmount_drag_pack()

func _mount_drag_pack() -> void:
	_unmount_drag_pack()
	if GameLoop2.run_over:
		return
	_drag_pack = DragPackPanel.build(take_floor_loot, bin_floor_loot)
	_drag_pack.top_level = true
	add_child(_drag_pack)
	_place_drag_pack()

func _unmount_drag_pack() -> void:
	if _drag_pack != null and is_instance_valid(_drag_pack):
		_drag_pack.queue_free()
	_drag_pack = null

# TO THE LEFT OF THE BOARD, vertically centred on it. The piece is on the board
# and the pack is where it is going, so the drag runs right-to-left across the
# page and the panel sits at the end of that run rather than on top of where it
# started — covering the square the piece came off, and the squares around it,
# which is where a drag has to be able to end harmlessly.
#
# Placed once: the panel lives for the length of one drag, and the board does not
# move during one. Clamped to the screen so a page that has been squeezed puts it
# somewhere reachable rather than off an edge, and held below the header the way
# every other floating surface is.
func _place_drag_pack() -> void:
	if _drag_pack == null or not is_instance_valid(_drag_pack):
		return
	var anchor: Control = _stage_panel if _stage_panel != null and is_instance_valid(_stage_panel) \
		else _left_col
	if anchor == null or not is_instance_valid(anchor):
		return
	_drag_pack.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_drag_pack.size = _drag_pack.get_combined_minimum_size()
	var on: Rect2 = anchor.get_global_rect()
	var size: Vector2 = _drag_pack.size
	var screen: Vector2 = get_viewport_rect().size
	var x: float = clampf(on.position.x - size.x - DragPackPanel.BOARD_GAP,
		4.0, maxf(4.0, screen.x - size.x - 4.0))
	var y: float = clampf(on.position.y + (on.size.y - size.y) * 0.5,
		ModalScaffold.reserved_top + 4.0, maxf(ModalScaffold.reserved_top + 4.0,
			screen.y - size.y - 4.0))
	_drag_pack.global_position = Vector2(x, y)

# One floor square's payload as the loot entry the modals deal in. The loop stores
# the entry whole (it is scene-free and JSON-safe already), so this is only the
# unwrapping — and the guard for a save written when the floor still held relics.
func _floor_loot(held: Dictionary) -> Dictionary:
	var entry = held.get("loot")
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}

# Everything still lying on the board when a game is reported goes onto the haul
# screen (§8.2/§18): the floor belongs to the game being played, and what the
# player did not stop to pick up is still theirs to answer for once.
#
# ONE TABLE, not one question per square. Three bodies leaving three pieces is a
# handful of loot, and LootDropModal has always taken a list — asking about them
# one modal at a time would put the ninth-slot decision to the player three times
# over with a different third of the answer each time.
#
# Swept whatever the report said. The loot was earned by the KILL, which already
# happened; only the relic chest is a reward for beating the game (claim_chests).
func _sweep_floor_into_the_queue() -> void:
	var swept: Array = []
	for held in GameLoop2.sweep_drops():
		var entry: Dictionary = _floor_loot(held)
		if not entry.is_empty():
			swept.append(entry)
	if not swept.is_empty():
		_drop_queue.append({"loot": swept})

# THE RELICS THE EVENING EARNED (§8.2), spent and queued for the haul screen.
#
# A game beaten is worth one chest point on its own — a Small chest for a win with
# nothing standing on the board — and every non-boss body defeated since the last
# report adds its own difficulty on top: Low 1, Medium 2, High 3, Insane 4. The
# total is spent on the SAME ladder every scaling payout in the game walks
# (`Data.chest_reward_sizes`): the chest grows Small → Medium → Large → Huge, and
# past Huge it splits into a second chest rather than running off the end. Three
# High kills on a game you beat is 10 points — two Huge chests and a Medium.
#
# Which is the whole reason the relics left the floor. Paid a body at a time they
# were N Small chests, each worth less than the last and each its own question;
# paid at the report they are one growing reward that describes the evening.
#
# NOTHING FOR A GAME YOU DIDN'T BEAT. The loot the bodies dropped is already on
# the floor and stays yours (it was earned by the kill) — the chest is what
# beating the game buys, and GameLoop2.claim_chests is where that gate lives.
# A BOSS chest is the exception it always was: it is paid whether or not the game
# went your way, rolled from the boss pool, and kept as a chest OF ITS OWN beside
# the kill chest rather than folded into its points — There's Options buys size on
# that chest, not on this one.
#
# Queued rather than granted through `GameState.grant_chests`: a grant fires
# `chest_granted`, which opens a RewardScreen on the next idle frame — over the
# top of a board still playing the resolve back. The queue is the path that waits
# (see _pump_drops), and it is where a defeated body's chest always went.
func _queue_report_chests(beaten: bool) -> void:
	if GameLoop2.run_over:
		# The run ended on this report; the win/lose screen owns the page now, and
		# the pool goes with the run rather than being carried into a screen that
		# will never ask about it.
		GameLoop2.claim_chests(false)
		return
	var granted: Array = []
	for chest in GameLoop2.claim_chests(beaten):
		var from_boss: bool = bool((chest as Dictionary).get("boss", false))
		for size in Data.chest_reward_sizes(int((chest as Dictionary).get("points", 0))):
			var offer: Array = _roll_chest(from_boss, int(Data.CHEST_SIZE_CHOICES[size]))
			if offer.is_empty():
				continue
			_drop_queue.append({"items": offer})
			granted.append(size)
	if granted.is_empty():
		return
	# ONE LINE for the lot (§8.2). A reward promised as one line has to arrive as
	# one line, so a win that paid a Huge and a Medium says so once rather than
	# toasting twice — the two are still two chests, separately rolled and
	# separately answered, on the screen itself.
	Notifications.notify("Gained %s!" % Data.chest_sizes_text(granted),
		Color(1.0, 0.85, 0.4))
	GameLog.add("Gained %s." % Data.chest_sizes_text(granted), Color(1.0, 0.85, 0.4))

# Roll the game's loot payout and queue the question (§4.3). Queued rather than
# granted so the nine-piece cap can be answered by the player: a full pack turns
# the payout into "spend something or leave this", and that is a decision the run
# should be making out loud.
func _queue_loot_drop() -> void:
	if GameLoop2.run_over:
		return
	var entry: Dictionary = GameState.roll_loot_entry("loot")
	if entry.is_empty():
		return
	_drop_queue.append({"loot": entry})
	_pump_drops()

# A GRANT of loot, asked about rather than pushed into the pack (§4.3). Mom's Coin
# Purse pays four pills at once and Sacred Bark doubles what a grant pays; shovelled
# straight in, the surplus over the nine-piece cap used to vanish without a word.
# GameState.offer_loot rolls the pieces and calls here, and they arrive as ONE
# question with all of them on the table rather than as four modals in a row.
#
# Behind the same queue as everything else, so a game that paid its own piece AND
# fired a relic asks in the order they landed.
func _on_loot_offered(entries: Array) -> void:
	if GameLoop2.run_over or entries.is_empty():
		return
	# ONTO THE HAUL SCREEN when one is up. A relic taken from a chest ON that
	# screen can pay loot the instant it is picked up, and the table it belongs on
	# is six inches to the right of the card that paid it — queueing it behind a
	# screen the player has not left yet would hide the payout until after the
	# decision that earned it.
	if _post_screen != null and is_instance_valid(_post_screen) \
			and _post_screen.add_loot(entries):
		return
	_drop_queue.append({"loot": entries.duplicate(true)})
	_pump_drops()

# Ask about the next waiting drop, if nothing else is already asking. Several
# defeats in one report queue behind each other rather than stacking modals.
#
# Deferred, because a defeat lands in the MIDDLE of GameLoop2.beat_game: the run
# is still mid-resolve, the board hasn't repainted and the report step hasn't
# handed over yet. Opening on the next idle frame puts the question after all of
# that, over a screen that has finished moving.
func _pump_drops() -> void:
	if _drop_modal != null and is_instance_valid(_drop_modal):
		return
	if _drop_queue.is_empty() or not is_inside_tree():
		return
	if _phase == Phase.OVER or GameLoop2.run_over:
		return
	# NOT WHILE A REPORT IS RESOLVING. Everything a report drops belongs to the
	# post-combat screen, which opens when the board has finished playing the
	# resolve back (_open_post_game) and takes the whole queue with it. Pumping
	# here is what used to put "do you want this relic" over the top of the strike
	# that had just taken eight Health off the player.
	#
	# A REPORT and A LOST RUN'S TURN (§3) both set `_resolving`, and both for the
	# same reason: a board mid-playback is not a place to put a modal. The turn has
	# no post-combat screen behind it to hand the queue to, so _end_resolve pumps
	# it itself the moment the playback lands. An offer that arrives at any OTHER
	# moment — a relic firing on the overworld, a machine, an event's payout —
	# still asks for itself, on its own modal, immediately.
	if _resolving:
		return
	_open_next_drop.call_deferred()

func _open_next_drop() -> void:
	if _drop_modal != null and is_instance_valid(_drop_modal):
		return
	if _drop_queue.is_empty() or not is_inside_tree():
		return
	if _phase == Phase.OVER or GameLoop2.run_over:
		return
	var drop: Dictionary = _drop_queue[0]
	# A LOOT payout rides the same queue as the relics a body left (§4.3), because
	# they are the same question asked about different things and a game can hand
	# over both. It asks in its own modal — a scroll is not an ItemData and the
	# nine-piece cap is a sentence only this one has to say.
	if drop.has("loot"):
		# Spendable, always. There is no longer a condition under which loot cannot
		# be used (§4.3): the mid-report lock holds the pack still, and a piece whose
		# effect cannot land right now fizzles rather than being refused. The flag
		# stays on the call because this screen must not assume the rule — the day
		# something else CAN forbid a use, it comes in here.
		var loot_modal := LootDropModal.open(self, drop["loot"], true)
		_drop_modal = loot_modal
		# `taken` is what ended up in the pack. THE SCREEN PLACES ITS OWN takes (§4.3):
		# with several offers, and uses and bins interleaved between them, the slot
		# the player chose is only meaningful at the instant they choose it. So the
		# page's job here is the log and the refresh, not the taking.
		loot_modal.answered.connect(func(taken: Array):
			_drop_modal = null
			_drop_queue.pop_front()
			_note_loot_taken(taken)
			_pump_drops())
		return
	var modal = ItemDropModal.open(self, _drop_items(drop))
	_drop_modal = modal
	modal.answered.connect(func(taken: bool, chosen: ItemData):
		_drop_modal = null
		if taken:
			_collect_drop(drop, chosen)
		else:
			_skip_drop(drop)
		# Whatever is behind it in the queue is the next question.
		_pump_drops())

# Roll one drop item from the games-first reward pool, weighted by rarity the same
# way the RewardScreen chest roll is (§8) — minus the luck advantage, which is the
# chest's own bonus.
#
# A BOSS pays out of the boss pool instead, with no rarity roll at all: a boss
# relic is not a rung on the ladder, it is a thing only a boss drops, so "which
# rarity did the boss roll" is not a question with an answer (§7.1). Falls back to
# the ordinary roll if no boss relics are authored, because a boss that drops
# nothing would read as a bug rather than as a thin catalogue.
func _roll_drop(from_boss: bool = false) -> ItemData:
	if from_boss:
		var boss_pool: Array = Data.boss_item2_pool()
		if not boss_pool.is_empty():
			return boss_pool[_rng.randi_range(0, boss_pool.size() - 1)]
	var bucket: Array = Data.reward_item2_pool_of(Data.roll_item_rarity(_rng))
	if bucket.is_empty():
		return null
	return bucket[_rng.randi_range(0, bucket.size() - 1)]

# `count` DISTINCT items for one chest, each rolled by _roll_drop. Distinct is a
# preference and not a rule, the same way the shop shelf treats it: two of the
# same relic side by side is not a choice, but a thin pool still owes a full
# chest, so the draw gives up after a few tries rather than shrinking the offer.
# Fewer than `count` only when the pool itself is empty.
func _roll_chest(from_boss: bool, count: int) -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < maxi(1, count) and tries < 40:
		tries += 1
		var item: ItemData = _roll_drop(from_boss)
		if item == null:
			break
		if not out.has(item):
			out.append(item)
	return out

# The items one queued chest is offering. `items` is the canonical shape; the
# single-item `{item: …}` shorthand is still read so a save written before chests
# had a size — and the tests that hand-build a drop — keep working.
func _drop_items(drop: Dictionary) -> Array:
	var items: Array = drop.get("items", [])
	if not items.is_empty():
		return items
	var one = drop.get("item")
	return [one] if one is ItemData else []

func _collect_drop(drop: Dictionary, chosen: ItemData = null) -> void:
	if not _drop_queue.has(drop):
		return
	_drop_queue.erase(drop)
	var offered: Array = _drop_items(drop)
	# Defaults to the first thing offered, so a caller that doesn't care which —
	# a test, a one-item chest — doesn't have to name it.
	collect_drop_item(chosen if chosen != null and offered.has(chosen)
		else (offered[0] if not offered.is_empty() else null))

# TAKING ONE RELIC, wherever the chest was asked about. The queue bookkeeping above
# belongs to the page's own modal; this is the half that touches the run, and the
# post-combat screen — which holds its chests itself, off the queue — calls it
# directly so a relic taken there is granted, logged and announced identically.
func collect_drop_item(item: ItemData) -> void:
	if item == null:
		return
	GameState.add_item(item)
	GameLog.add("Collected %s." % item.display_name, Color(0.7, 1.0, 0.7))
	Notifications.notify("Took %s." % item.display_name, UITheme.item_color(item))

# …and leaving them, on the same terms.
func skip_drop_items(items: Array) -> void:
	var names: Array = []
	for it in items:
		if it is ItemData:
			names.append(String((it as ItemData).display_name))
	if not names.is_empty():
		GameLog.add("Left %s behind." % ", ".join(names), Color(0.8, 0.8, 0.8))

# What the player kept off a payout, written down — the public name for
# _note_loot_taken, so the post-combat screen's embedded payout reports through
# exactly the path the standalone modal does.
func note_loot_taken(taken: Array) -> void:
	_note_loot_taken(taken)

# What the player kept off a payout, written down. The pieces are ALREADY in the
# pack — the drop screen places each one as it is resolved, because with several
# offers on the table and uses and bins between them, the slot a piece was dropped
# into stops meaning anything the moment the next one moves (§4.3). So this is the
# log and the redraw, and nothing else.
func _note_loot_taken(taken: Array) -> void:
	for entry in taken:
		if entry is Dictionary:
			GameLog.add("Collected %s." % LootSystem.display_name(entry),
				Color(0.7, 1.0, 0.7))
	if not taken.is_empty():
		_refresh_items()

func _skip_drop(drop: Dictionary) -> void:
	if not _drop_queue.has(drop):
		return
	_drop_queue.erase(drop)
	skip_drop_items(_drop_items(drop))


func _result_text(res: Dictionary) -> String:
	var parts: Array = []
	if int(res.get("drops", 0)) > 0:
		parts.append("%d drop(s)" % int(res["drops"]))
	if int(res.get("damage_taken", 0)) > 0:
		parts.append("took %d damage" % int(res["damage_taken"]))
	if int(res.get("blocked", 0)) > 0:
		parts.append("shields absorbed %d" % int(res["blocked"]))
	if int(res.get("attempts", 0)) > 0:
		parts.append("%d attempt(s)" % int(res["attempts"]))
	# Shields belong to the game that granted them; say so when some went unused.
	if int(res.get("shields_expired", 0)) > 0:
		parts.append("%s expired with the game" % GameState.temp_shields_text(
			int(res["shields_expired"])))
	if parts.is_empty():
		parts.append("no effect")
	return "[i]Last game: %s.[/i]" % ", ".join(parts)

func _on_run_lost() -> void:
	_phase = Phase.OVER
	_drop_queue.clear()
	SaveSystem.clear_autosave()
	_show_banner("💀  Run lost — Health reached 0.", Color(0.9, 0.3, 0.25))
	_queue_run_over(false)

func _on_run_won() -> void:
	_phase = Phase.OVER
	_drop_queue.clear()
	SaveSystem.clear_autosave()
	_show_banner("🏆  You cleared the Amulet — you win!", Color(0.95, 0.8, 0.2))
	_queue_run_over(true)

# --- the end of the run ----------------------------------------------------
#
# A run that ends has an END SCREEN (RunOverScreen): the verdict, the run in
# numbers, and the road it walked. The banner stays as the line on the page
# behind it, so dismissing the screen leaves a finished run that still says so.
#
# The screen waits for the board when the run ended DURING a resolve — the blow
# that killed you is the last thing worth watching, and it plays before the
# verdict lands on top of it.

func _queue_run_over(did_win: bool) -> void:
	if _run_over_screen != null and is_instance_valid(_run_over_screen):
		return
	_run_over_won = did_win
	if _resolving:
		_run_over_pending = true
		return
	_show_run_over()

func _show_run_over() -> void:
	# Nothing left to spend it on, and nothing under the board to scroll to.
	_leave_node()
	# An event can now be the thing that KILLS you (a Health cost taken on the
	# last point of it), and it is still standing open over the board when it
	# does. Dismissed rather than closed: closing an event runs the chain that
	# follows one — refresh, autosave, the hub's shop — and the run it belonged
	# to is over.
	if _event_modal != null and is_instance_valid(_event_modal):
		_event_modal.dismiss()
	_event_modal = null
	# The haul screen goes the same way, and for the same reason: a pill taken off
	# the table there can be the thing that kills you (Bad Trip on the last point
	# of Health), and abandoning it rather than dismissing it stops the way out of
	# a finished run resuming its event chain from under the verdict.
	_dismiss_post_game()
	if not is_inside_tree():
		return
	if _run_over_screen != null and is_instance_valid(_run_over_screen):
		return
	var screen := RunOverScreen.open(self, _run_over_won)
	_run_over_screen = screen
	screen.restart_requested.connect(func(): start_run())
	screen.menu_requested.connect(func():
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn"))
	screen.finished.connect(func(): _run_over_screen = null)

# The end screen, while one is up — so a run can't stack two of them, and so a
# fresh run clears the old verdict off the page.
func _dismiss_run_over() -> void:
	_run_over_pending = false
	if _run_over_screen != null and is_instance_valid(_run_over_screen):
		_run_over_screen._close()
	_run_over_screen = null

func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.show()
	# The run is over: the offering and the report step are done with, and the board
	# drops to the page bottom showing the field the run ended on.
	_refresh_stage()
	_refresh_attempts()
	# The run is over, so anything still waiting to be asked about goes with it.
	_drop_queue.clear()

# --- UI construction ------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.shared()
	# The board's height budget is static (there is only ever one board), so a
	# screen that opens with nothing under the board has to say so — otherwise a
	# previous run's shop would leave every later board fitted for a column it is
	# no longer sharing.
	BattlefieldView.set_sharing_column(false)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG_DEEP
	add_child(bg)
	# The page is taller than a screen (HUD, choices, play panel, battlefield, log),
	# so host it in a ScrollContainer — everything stays reachable and the battlefield
	# no longer falls off the bottom on short displays.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -16
	# SHOW_NEVER, not AUTO and not DISABLED. The page is laid out to fit its width
	# — the board fits itself to a budget, the bars flow — so a horizontal bar
	# under the whole page is never the answer to anything: it is a strip of
	# chrome that turns up when a layout hiccups (a canvas that has not settled
	# into the window's aspect yet is the one that started this) and then sits
	# there for the rest of the run. DISABLED would be the wrong cure, because it
	# CLIPS instead of clamping and a board hanging off the right edge with no way
	# to reach it is worse than the bar. SHOW_NEVER keeps the axis scrollable — by
	# wheel, by drag, by code — and simply never draws the bar.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	_scroll = scroll
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	# The header is the title and ONE button. Map / Save / New run / Menu were four
	# buttons across the top, and only one of them is ever pressed mid-decision:
	# the Map, which belongs with the offering it is a map OF (see _select_head).
	# The other three are run admin, and run admin folds into the menu it was
	# already sitting next to.
	# HEALTH, TITLE, MENU — in that order, and health is first for a reason. It
	# used to live only on the battlefield, beside the hero, which meant the one
	# number that ends the run was off-screen whenever anything was mounted over
	# the board: a chest, an event, a reward screen. It is the top-left corner of
	# the page now and it never moves. The title gives up the left edge for it and
	# takes the centre.
	# …and between the health and the menu, THE ROAD YOU HAVE WALKED — the same
	# cover-and-arrow strip the end-of-run screen draws, at the top of the page for
	# the whole run rather than once it is over. It is the one picture of the run as
	# a JOURNEY: the checklist says what you owe, the board says what is chasing
	# you, the route ladder says where you could go — and none of them said where
	# you have been. That is the thing a roguelike run is, and it was only ever
	# shown on the screen that tells you it has finished.
	#
	# The title gives up the centre for it and takes the right, which is also the
	# honest ranking: the title is decoration, and the strip is state.
	#
	# AND IT NEVER LEAVES THE SCREEN. The header used to be the first row of the
	# page inside the ScrollContainer, which meant the two numbers that end the run
	# scrolled away the moment the player looked at the bottom of a tall board —
	# and disappeared entirely behind every modal the run raises, which is where
	# Health is most worth reading (an event that offers you a gamble is a decision
	# about the health bar you cannot see). So it is mounted on a CanvasLayer of its
	# own, above the gameplay modals (event 123, choice 124, map 130) and below the
	# screens that REPLACE the run rather than sit over it (atlas 140, the verdict
	# 150). The page below is inset by exactly its height (_fit_page_under_header),
	# so nothing is ever hidden underneath it.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.add_child(_build_health_chip())
	header.add_child(_build_gold_chip())
	_route_strip = HBoxContainer.new()
	_route_strip.add_theme_constant_override("separation", 0)
	_route_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_route_strip.clip_contents = true
	header.add_child(_route_strip)
	var title := Label.new()
	title.text = "The Search for the Amulet"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(title)
	header.add_child(_build_menu_button())
	_header = header
	_mount_header(header)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.hide()
	root.add_child(_banner)

	# THE STAGE, in two columns. LEFT is the run's paperwork, top to bottom in the
	# order it's read: the OFFERING (which game next) above the CHECKLIST (what to
	# tick while that game is open). RIGHT is the BOARD with the PACK under it —
	# the things you look at rather than drive.
	#
	# The offering used to sit full-width ABOVE the pair, which meant the board was
	# a scroll away from the cards being chosen between; the two halves of the same
	# decision — "where do I go" and "what is closing in on me" — were never on
	# screen together. Stacked into the left column they are, at the cost of the
	# covers being drawn half-size (OfferingCards.COVER_SIZE).
	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 12)
	root.add_child(main_row)

	# Left column: takes the room the board doesn't need.
	_left_col = VBoxContainer.new()
	_left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_left_col.add_theme_constant_override("separation", 10)
	main_row.add_child(_left_col)

	# Everything that belongs to CHOOSING a game, in one box the phase toggles: the
	# offering and its verbs are irrelevant once you've committed to a game, and the
	# room they free goes to the checklist that replaces them.
	var select_panel := PanelContainer.new()
	select_panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.ACCENT.lerp(UITheme.BORDER, 0.5), 12, 12, 1))
	_select_box = VBoxContainer.new()
	_select_box.add_theme_constant_override("separation", 8)
	select_panel.add_child(_select_box)
	_select_box.set_meta("wrap", select_panel)
	_left_col.add_child(select_panel)

	# The offering's heading, with the MAP on the other end of it. The map is the
	# whole road this panel is choosing the next step of, so it belongs to the
	# panel rather than to the page's title bar — and a button here is one the
	# mouse is already near when the question comes up.
	var select_head_row := HBoxContainer.new()
	select_head_row.add_theme_constant_override("separation", 8)
	_select_head = _section("Choose a game to travel to:")
	_select_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_select_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# WRAPPED, and it matters more than a heading usually does. A Label that does
	# not wrap reports the whole sentence as its MINIMUM width, and this one is a
	# whole sentence: the start picker's "Choose where to start — three genres, all
	# the same distance from the Amulet…" set the left column's minimum at ~900px
	# all by itself, which plus the board is wider than the canvas — and the board,
	# on the far side of the page, is what got pushed off it. The heading is the
	# most compressible thing on this screen and it was the thing dictating the
	# layout.
	_select_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	select_head_row.add_child(_select_head)
	var map_btn := Button.new()
	map_btn.text = "🗺  Map"
	map_btn.tooltip_text = "The whole road ahead: every shortest path from here to the Amulet."
	map_btn.add_theme_font_size_override("font_size", 12)
	map_btn.pressed.connect(open_map)
	select_head_row.add_child(map_btn)
	_select_box.add_child(select_head_row)
	# Controls row (Dash) — populated per refresh.
	_controls_row = HBoxContainer.new()
	_controls_row.add_theme_constant_override("separation", 8)
	_select_box.add_child(_controls_row)
	_choices_row = HFlowContainer.new()
	_choices_row.add_theme_constant_override("h_separation", 12)
	_choices_row.add_theme_constant_override("v_separation", 10)
	_select_box.add_child(_choices_row)

	# Hover preview: the enemy's PORTRAIT and one line about it, side by side.
	#
	# It was a framed panel with 64px art and two lines of goal text (84px of page),
	# then it was a bare line with no art at all — and the line alone lost the thing
	# a hover is actually fastest at. A player recognises a body by its picture long
	# before they read its name, and the picture is what says "I have fought that
	# before" while the cursor is still moving.
	#
	# So the art is back, BESIDE the line and sized BY it (see OfferingCards.HOVER_ART):
	# the row
	# is the same 22px it was with no art on it, and the page's 720p budget doesn't
	# move by a pixel. The row also keeps that height whether or not anything is
	# hovered, so running the cursor along the offering never reflows the column
	# underneath.
	var hover_row := HBoxContainer.new()
	hover_row.add_theme_constant_override("separation", 8)
	_preview_art = TextureRect.new()
	# Width only. The height comes from the row — SIZE_FILL against a line whose
	# floor the label sets — and EXPAND_IGNORE_SIZE stops the texture's own
	# dimensions from claiming any of it.
	_preview_art.custom_minimum_size = Vector2(OfferingCards.HOVER_ART, 0)
	_preview_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_art.size_flags_vertical = Control.SIZE_FILL
	_preview_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# HIDDEN, not merely empty: an untextured TextureRect still claims its width and
	# would indent the idle line away from the left edge.
	_preview_art.visible = false
	hover_row.add_child(_preview_art)
	_preview = _panel_label()
	_preview.custom_minimum_size = Vector2(0, 22)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hover_row.add_child(_preview)
	_select_box.add_child(hover_row)
	# Built here rather than in _ready: it fills these three, so it cannot exist
	# before they do.
	_offering = OfferingCards.new(self, _choices_row, _preview, _preview_art)

	# The choosing charges, at the foot of the panel they're spent in. They used to
	# be four numbers in the middle of a twelve-number HUD strip at the top of the
	# page — a Bash charge is only ever spent on a card in this box, and this is
	# where it should be readable from.
	_select_stats = HFlowContainer.new()
	_select_stats.add_theme_constant_override("h_separation", 6)
	_select_stats.add_theme_constant_override("v_separation", 4)
	_select_box.add_child(_select_stats)

	_report_panel = PanelContainer.new()
	_report_panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.ACCENT.lerp(UITheme.BORDER, 0.5), 12, 12, 1))
	_left_col.add_child(_report_panel)
	_play_panel = VBoxContainer.new()
	_play_panel.add_theme_constant_override("separation", 6)
	_report_panel.add_child(_play_panel)

	# Right column: the pack, then the board under it. Shrink-wrapped to the
	# board's real width so the checklist gets everything else.
	_right_col = VBoxContainer.new()
	_right_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_right_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_right_col.add_theme_constant_override("separation", 8)
	main_row.add_child(_right_col)

	# What you're carrying, in a strip ABOVE the field it gets spent on. It used to
	# sit under the board, which on a 7x7 grid is a screen and a half down the page:
	# the items were out of sight at exactly the moment the board was telling you
	# how much trouble you were in. As a strip it is only as tall as the rows of
	# tokens it needs (see _refresh_items), so the board keeps the room.
	_inv_wrap = PanelContainer.new()
	# MARGIN 6, not the 8 the other panels use, and separation 3 rather than 4. The
	# loot bar at the foot of this panel (below) is a row the panel did not used to
	# have, and the page it lives on is fitted to a 720p canvas with about five
	# pixels to spare — so the row is paid for out of this panel's own padding
	# rather than out of the board's height. Every one of these numbers is load
	# bearing: test_the_page_still_fits_the_window_* fails at +2.
	_inv_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 6, 1))
	_inv_wrap.size_flags_horizontal = Control.SIZE_FILL
	var inv_box := VBoxContainer.new()
	inv_box.add_theme_constant_override("separation", 3)
	_inv_wrap.add_child(inv_box)
	# NO HEADING. It used to carry a "🎒  Inventory" line, and a strip of relics
	# and scrolls in a bordered panel does not need to be told what it is — the
	# tokens are the label. That row is also the page's whole margin: the overworld
	# is fitted to a 720p window and, with the heading on, the pack panel alone put
	# it a pixel OVER (626 of 625) before a shop was even mounted under the board.
	#
	# THE STRIP IS THE RELICS AGAIN. Scrolls rode it for as long as a scroll or two
	# was all the loot there was; pills doubled the kinds and the per-game drop made
	# carrying nine ordinary, and nine more tiles in here is a second inventory
	# pretending to be a strip. Loot lives in its own window now (§4.3) — opened by
	# the toggle on the same row, so it is one click from the relics rather than a
	# panel that is always in the way.
	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 6)
	inv_box.add_child(strip_row)
	_items_box = HFlowContainer.new()
	_items_box.add_theme_constant_override("h_separation", 4)
	_items_box.add_theme_constant_override("v_separation", 4)
	_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_row.add_child(_items_box)
	_pack = PackStrip.new(self, _items_box)
	#
	# THE LOOT TOGGLE IS THE PANEL'S FOOT, full width, under the relics.
	#
	# It has now been in three places, and the two it left were each wrong in their
	# own way. At the TAIL of the relic row it sat under the notification toasts — a
	# right-anchored column drawn over the page — so the one control that says you
	# are carrying any loot at all spent most of every report hidden behind
	# "Acquired Anchor." At the HEAD of that row it was clear of them, but it ate
	# the left end of the strip the relics wrap into, which costs a relic tile a
	# whole row the moment the pack gets long.
	#
	# On its own row it costs the relics no width at all, and being full width it is
	# a bar rather than a button — which is the shape a "the rest of what you are
	# carrying is through here" control should have been all along. THIN, because the
	# page is fitted to a 720p canvas with a handful of pixels spare (see
	# test_the_page_still_fits_the_window_*): the bar is drawn at
	# LootWindow.TOGGLE_H and the capsules it carries are sized to sit inside that,
	# so stacking it under the strip costs the panel about twenty pixels rather than
	# a row's worth.
	_loot_toggle_box = HBoxContainer.new()
	_loot_toggle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_box.add_child(_loot_toggle_box)
	_loot_window = LootWindow.new(self, _loot_toggle_box)
	_right_col.add_child(_inv_wrap)

	_stage_panel = PanelContainer.new()
	_stage_panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.ACCENT.lerp(UITheme.BORDER, 0.5), 12, 12, 1))
	_stage_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_right_col.add_child(_stage_panel)
	var stage_box := VBoxContainer.new()
	stage_box.add_theme_constant_override("separation", 8)
	_stage_panel.add_child(stage_box)

	# Board header: what the field is doing, on one line.
	#
	# There is no Tier / Push / Bombs row here, and there was briefly: the board
	# DRAWS all three itself and always did. Its pressure bar ends in "▦ 4×4 · Low"
	# — that "Low" is the tier — and its toolbar's two buttons are literally
	# "⇤ Push (1)" and "✸ Bomb (3)". A second row saying the same numbers cost the
	# page ~60px to repeat the board back at itself, which is exactly the mistake
	# the HUD strip was making with Health.
	_board_head = HBoxContainer.new()
	_stack = _panel_label()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_head.add_child(_stack)
	stage_box.add_child(_board_head)

	_board = BattlefieldView.new()
	_board.push_requested.connect(push_follower)
	_board.bomb_requested.connect(bomb_follower)
	_board.bomb_cell_requested.connect(bomb_cell)
	_board.item_aimed.connect(_on_item_aimed)
	_board.item_aimed_at_cell.connect(_on_item_aimed_at_cell)
	_board.loot_thrown_at_cell.connect(_on_loot_thrown_at_cell)
	_board.loot_throw_cancelled.connect(_on_loot_throw_cancelled)
	_board.enemy_inspected.connect(_show_enemy_info)
	# The board points back at the checklist: hovering a body lights the goal row
	# written about it (_bind_row_to_body).
	_board.enemy_hovered.connect(_on_enemy_hovered)
	stage_box.add_child(_board)


	# --- the report checklist (left column, shown while a game is in play) ----

	# One tight row: the game's cover and what you are doing with it.
	#
	# THE ENEMY'S PORTRAIT IS NOT ON IT. There used to be a second 72px frame here
	# holding the art of "this game's enemy", drawn beside the box art as if the
	# two were a pair. They are not a pair and never were a fact about the game:
	# the body that walked on when you took this card is a follower like every
	# other from the moment it lands (GameLoop2.arrivals), and it is already drawn
	# where every other body is — on the board, to the right. Showing it here said
	# the game owned it.
	#
	# The cover takes the space back and is CENTRED in the row, because a lone
	# frame hard against the left edge of a panel reads as the first of two things
	# with the second one missing.
	# A COLUMN, and the cover centred at the top of it. As a row with the portrait
	# gone the cover was left hard against the left edge with the text beside it,
	# which reads as the first of two things with the second one missing — the
	# shape the old pair left behind. Stacked, the box art is the heading of the
	# panel and the line about what walked on sits under it.
	_np_box = VBoxContainer.new()
	var np_box := _np_box
	np_box.add_theme_constant_override("separation", 8)
	_now_playing_cover = TextureRect.new()
	_now_playing_cover.custom_minimum_size = OfferingCards.COVER_SIZE * 0.72
	_now_playing_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_now_playing_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var cover_frame := PanelContainer.new()
	cover_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 6, 4, 1, UITheme.BORDER))
	cover_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cover_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cover_frame.add_child(_now_playing_cover)
	np_box.add_child(cover_frame)
	_now_playing = _panel_label()
	_now_playing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	np_box.add_child(_now_playing)
	_play_panel.add_child(np_box)

	# Launch-the-real-game row (populated per game — only games with a launch
	# target gets a button) + the opt-in Rate button.
	_launch_row = HBoxContainer.new()
	_launch_row.add_theme_constant_override("separation", 6)
	_play_panel.add_child(_launch_row)

	# The attempt tracker (§3) — the thing you press between runs of the real game.
	_attempt_wrap = _build_attempt_strip()
	_play_panel.add_child(_attempt_wrap)

	# Verification checklist (populated per game): the main goal, the character's
	# level-up challenge, and any following enemy whose goal you also cleared. Tick
	# what you did, then press the single Completed Game button below.
	_verify_box = VBoxContainer.new()
	_verify_box.add_theme_constant_override("separation", 3)
	_play_panel.add_child(_verify_box)
	# Built here rather than in _ready: it fills these two containers, so it cannot
	# exist before they do.
	_checklist = ReportChecklist.new(self, _verify_box, _launch_row)

	var done := Button.new()
	_done_btn = done
	done.text = "✓  Completed Game"
	done.custom_minimum_size = Vector2(0, 40)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.add_theme_stylebox_override("normal", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.5), 8, 8, 2, UITheme.SUCCESS))
	done.add_theme_stylebox_override("hover", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.35), 8, 8, 2, UITheme.SUCCESS))
	done.add_theme_color_override("font_color", UITheme.SUCCESS.lerp(Color.WHITE, 0.45))
	done.add_theme_font_size_override("font_size", 15)
	# Pressing it IS the claim: "I completed this game." What you did to the
	# enemies is the checklist above it, ticked row by row.
	done.pressed.connect(func(): report(true))
	_play_panel.add_child(done)

	# The way out, directly under the way through — they resolve the same step, so
	# they belong together. Hidden until ESCAPE_AFTER_ATTEMPTS lost runs, and
	# deliberately quieter than Completed Game: this is the concession, not the
	# goal. Tinted like the attempt strip's damage rather than its success green,
	# because the enemy still follows you out.
	_escape_btn = Button.new()
	_escape_btn.text = "🏃  Escape this game"
	_escape_btn.custom_minimum_size = Vector2(0, 30)
	_escape_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_escape_btn.add_theme_font_size_override("font_size", 13)
	_escape_btn.add_theme_stylebox_override("normal",
		UITheme.flat(UITheme.ACCENT.lerp(UITheme.BG, 0.78), 6, 8, 1, UITheme.ACCENT.lerp(UITheme.BG, 0.45)))
	_escape_btn.add_theme_stylebox_override("hover",
		UITheme.flat(UITheme.ACCENT.lerp(UITheme.BG, 0.6), 6, 8, 1, UITheme.ACCENT))
	_escape_btn.add_theme_color_override("font_color", UITheme.ACCENT)
	_escape_btn.pressed.connect(escape_game)
	_play_panel.add_child(_escape_btn)

	# What the last game did to you, at the foot of the panel that asked you about
	# it. It had a full-width line of its own at the very bottom of the page — a
	# third copy of a result that already fires as a toast and is already kept in
	# GameLog, and one that pushed the board a row further down to say it.
	_log = _panel_label()
	_log.add_theme_font_size_override("font_size", 12)
	_play_panel.add_child(_log)


	# The pointer at the shop under the board (§14). Mounted OUTSIDE the
	# ScrollContainer, on the page itself, because its whole job is to be visible
	# while the thing it points at is not.
	_shop_hint = _build_shop_hint()
	add_child(_shop_hint)
	# It stands down the moment the shop is scrolled to. The page is watched while
	# a shop is up (see _update_shop_hint) rather than sampled on the scroll signal,
	# which fires before the layout it would be measured against.
	set_process(false)

	# The toast layer: pickups, item procs and the repeat-beat Dash all post to
	# Notifications, and this is what makes them visible the instant they happen. It
	# used to be mounted by the (now cut) combat host, so nothing showed them.
	# Mounted on THIS screen (full-rect) rather than a bare CanvasLayer — the toast
	# stack anchors to its parent's top-right corner, and a Control hung straight off
	# a CanvasLayer has no rect to anchor to, which parks the stack off-screen.
	_toasts = NotificationToasts.new()
	add_child(_toasts)
	# …and the stack starts BELOW the header bar, which is opaque and drawn over
	# the toasts' layer: its own 56px inset was written against a page with no bar
	# pinned across the top of it.
	_fit_page_under_header()

# --- the header, pinned to the screen --------------------------------------

# Where the header floats. Above every modal the RUN raises (scroll 120, item
# drop / shop card 122, event and boss notice 123, game choice 124, map 130) and
# below the two screens that stand in for the run rather than over it: the Atlas
# (140) and the end-of-run verdict (150). A run whose Health has already hit 0
# has nothing left for a Health chip to say, and the Atlas is a different page.
const HEADER_LAYER := 135

# Mount `header` on its own CanvasLayer, in a bar across the top of the screen.
#
# The bar is OPAQUE, and that is the whole reason it is a PanelContainer rather
# than a bare row: it floats over an event's dimmed backdrop, and a line of text
# with a modal's scrim showing through it is unreadable at exactly the moment it
# matters most.
func _mount_header(header: Control) -> void:
	_header_layer = CanvasLayer.new()
	_header_layer.layer = HEADER_LAYER
	# The run's modals pause the tree behind them; the header is a readout, and a
	# readout that stops repainting while an event is open is the bug this is
	# fixing in a different shape.
	_header_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_header_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The page underneath keeps its clicks everywhere the bar itself isn't.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A theme does not cross a CanvasLayer, so the chips, the menu button and its
	# popup would otherwise be drawn in Godot's stock grey.
	UITheme.dress(root)
	_header_layer.add_child(root)

	_header_bar = PanelContainer.new()
	_header_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_header_bar.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG_DEEP, 0, 8, 1, UITheme.BORDER.lerp(UITheme.BG_DEEP, 0.4)))
	_header_bar.add_child(header)
	root.add_child(_header_bar)

	# The page starts below the bar, whatever height the bar turns out to be — the
	# route strip's covers set it, and a future row would change it again.
	_header_bar.resized.connect(_fit_page_under_header)
	_fit_page_under_header()

# Inset the scrolling page by the header's height, so the first row of the page
# clears the bar floating over it.
func _fit_page_under_header() -> void:
	if _header_bar == null or not is_instance_valid(_header_bar):
		return
	var bar: float = maxf(_header_bar.size.y, _header_bar.get_combined_minimum_size().y)
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.offset_top = 16.0 + bar
	if _toasts != null and is_instance_valid(_toasts):
		_toasts.offset_top = bar
	# And the same for everything that opens OVER the page. The bar is opaque and
	# floats above the modals, so a modal centred on the whole screen loses its top
	# to it — which is how the game-choice popup lost its title and the Atlas lost
	# the Close button that is the only way off it.
	_publish_header_strip(_header_layer == null or _header_layer.visible)

# Tell the shared modal machinery how much of the top of the screen this page's
# header bar is standing on — or that it isn't standing on any, when the bar is
# down or the page is gone. Everything that centres itself on screen reads this.
func _publish_header_strip(shown: bool) -> void:
	if not shown or _header_bar == null or not is_instance_valid(_header_bar):
		ModalScaffold.reserved_top = 0.0
		return
	ModalScaffold.reserved_top = maxf(_header_bar.size.y,
		_header_bar.get_combined_minimum_size().y)

# "🛒 Shop ↓" — the pointer at the shop mounted under the board. It floats at the
# bottom of the SCREEN (not of the page), over everything, until the shop has
# been scrolled into view; pressing it scrolls there.
#
# This is the one thing the inline shop still owes the old modal. A popup could
# not be missed and did not have to advertise itself; a panel below the fold can
# be both, and a shop the player never noticed is worse than the interruption
# that moving it out of the way was meant to avoid.
func _build_shop_hint() -> Control:
	var wrap := PanelContainer.new()
	wrap.visible = false
	wrap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	wrap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	wrap.offset_bottom = -18
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.SHOP_GREEN.lerp(UITheme.BG, 0.72), 10, 6, 2, UITheme.SHOP_GREEN))
	var btn := Button.new()
	btn.text = "🛒  Shop      ↓"
	btn.flat = true
	btn.tooltip_text = "A shop is open under the battlefield — scroll down to it."
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", UITheme.SHOP_GREEN.lerp(Color.WHITE, 0.45))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_scroll_to_shop)
	wrap.add_child(btn)
	# The arrow breathes rather than sitting still: the pointer is competing with a
	# page the player is already reading, and a static chip at the bottom edge is
	# exactly the kind of thing an eye filters out.
	var t: Tween = wrap.create_tween().set_loops()
	t.tween_property(wrap, "modulate:a", 0.55, 0.7).set_trans(Tween.TRANS_SINE)
	t.tween_property(wrap, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	return wrap

# Take the page to the shop. Pressing the pointer is the shortcut for the scroll
# it is asking for, so it does the scroll itself.
func _scroll_to_shop() -> void:
	if _shop_panel == null or not is_instance_valid(_shop_panel) or _scroll == null:
		return
	var target: float = _scroll.scroll_vertical \
		+ (_shop_panel.global_position.y - _scroll.global_position.y) - 40.0
	_scroll.scroll_vertical = int(maxf(0.0, target))
	_update_shop_hint()

# The attempt tracker (§3): the strip the player drives between runs of the real
# game. "Lost a run" is the only destructive button on the page, so it's tinted
# like damage and paired with an undo; the pips and the hint spell out what the
# next press will cost — a shield while any are left, Health after that.
func _build_attempt_strip() -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(SHIELD_BLUE.lerp(UITheme.BG, 0.88), 6, 8, 1, SHIELD_BLUE.lerp(UITheme.BG, 0.55)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	wrap.add_child(row)

	_attempt_btn = Button.new()
	_attempt_btn.text = "Lost a run  ⚔"
	_attempt_btn.tooltip_text = ("Tick every run of this game you lose.\n"
		+ "Each tick gives the enemies a turn — they swing and close in. It costs "
		+ "you no shields: there is no limit on how many times you may fail, only "
		+ "a board that is a turn closer every time you do.")
	_attempt_btn.custom_minimum_size = Vector2(0, 30)
	_attempt_btn.add_theme_font_size_override("font_size", 13)
	_attempt_btn.add_theme_stylebox_override("normal", UITheme.flat(UITheme.DANGER.lerp(UITheme.BG, 0.62), 6, 8, 1, UITheme.DANGER.lerp(UITheme.BG, 0.35)))
	_attempt_btn.add_theme_stylebox_override("hover", UITheme.flat(UITheme.DANGER.lerp(UITheme.BG, 0.45), 6, 8, 1, UITheme.DANGER))
	_attempt_btn.pressed.connect(log_attempt)
	row.add_child(_attempt_btn)

	_attempt_undo = Button.new()
	_attempt_undo.text = "Undo"
	_attempt_undo.tooltip_text = "Take back the last attempt."
	_attempt_undo.custom_minimum_size = Vector2(56, 30)
	_attempt_undo.pressed.connect(undo_attempt)
	row.add_child(_attempt_undo)

	_attempt_count = Label.new()
	_attempt_count.add_theme_font_size_override("font_size", 13)
	row.add_child(_attempt_count)

	_attempt_pips = Label.new()
	_attempt_pips.add_theme_font_size_override("font_size", 16)
	_attempt_pips.add_theme_color_override("font_color", SHIELD_BLUE)
	row.add_child(_attempt_pips)

	_attempt_hint = Label.new()
	_attempt_hint.add_theme_font_size_override("font_size", 12)
	_attempt_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attempt_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_attempt_hint)
	return wrap

# Repaint the attempt strip: how many runs have been lost, the shields still
# standing (one pip each, and a lost run does not spend them), and what the next
# press does.
func _refresh_attempts() -> void:
	if _attempt_count == null:
		return
	var attempts: int = GameLoop2.attempts()
	var left: int = GameState.shields
	var bonus: int = GameState.bonus_shields
	_attempt_count.text = "Lost runs  %d" % attempts
	_attempt_count.add_theme_color_override("font_color",
		UITheme.TEXT if attempts == 0 else UITheme.ACCENT)
	# The shields, and nothing hollow beside them: a lost run doesn't spend one, so
	# there is no "already used" state to draw. The pool that STAYS leads the row in
	# its own glyph, the way the board's hero draws them (§4.3).
	_attempt_pips.text = "◈".repeat(bonus) + "◆".repeat(left)
	_attempt_pips.tooltip_text = ("◆ %s — each one stops a single hit outright, "
		+ "however big it is, and they go when you report the game.") % GameState.temp_shields_text(left)
	if bonus > 0:
		_attempt_pips.tooltip_text += ("\n◈ %s — used after those, and they stay.") % (
			GameState.shields_text(bonus))
	# What the next press ACTUALLY does, in the terms the board is in: not a
	# number off the corner of the screen but a move by everything standing on it.
	# Said before it happens, because it is the reason to stop playing this game
	# and report it (§3).
	_attempt_hint.text = "Every lost run gives the enemies a turn — your shields stay."
	_attempt_hint.add_theme_color_override("font_color", UITheme.DANGER)
	var live: bool = _phase == Phase.PLAYING and not GameLoop2.run_over
	_attempt_btn.disabled = not live or _resolving
	# A TURN CAN ONLY BE TAKEN BACK BY THE SESSION THAT PLAYED IT (§3): its undo is
	# a snapshot of the board, and a save carries the run rather than its undo
	# history. The button says which of the two it is rather than going grey with
	# no explanation.
	var can_undo: bool = live and attempts > 0 and not _resolving and GameLoop2.can_undo_attempt()
	_attempt_undo.disabled = not can_undo
	_attempt_undo.tooltip_text = ("Take back the last attempt."
		if can_undo or attempts == 0 or _resolving
		else "The enemies' turn was taken before this run was reloaded — it can't be taken back.")
	# The escape hatch is up from the first second on a game the player has been
	# through before, and otherwise only once they have lost enough runs to have
	# earned it — where it goes away again if they undo back under the line. The
	# tooltip says WHICH rule is holding the door open, because "why can I leave
	# this one and not that one" is the whole question the button raises.
	if _escape_btn != null:
		_escape_btn.visible = can_escape()
		var why: String = "Something on the board got through and took Health off you — that is enough."
		if beaten_this_run():
			why = "You already beat this one this run, so there is nothing to prove — leave whenever you like."
		elif GameLoop2.stack.is_empty():
			why = "Nothing is on the board to hold you here."
		_escape_btn.tooltip_text = ("Leave without beating it. %s\n\nWhatever walked on "
			+ "when you took this game stays on the board and follows you, and every enemy "
			+ "still takes its turns — escaping resolves the board exactly as an unticked "
			+ "checklist does. What it does NOT do is credit the game: no drop, no event, "
			+ "and it doesn't count as beaten.") % why

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UITheme.ACCENT.lerp(UITheme.TEXT, 0.25))
	return l

func _panel_label() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(0, 24)
	return r

# Empty a rebuilt panel. The children are DETACHED as well as freed: queue_free
# alone leaves them in the tree until the end of the frame, so two refreshes in one
# frame — a pick that resolves and repaints immediately — would stack two copies of
# the same list.
func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

# The run's admin, behind one button. Save, New run and the way back to the main
# menu were three buttons parked across the top of the page for the whole run,
# and none of them is pressed while a decision is open — so they fold into the
# menu they were already standing next to.
enum MenuItem { SAVE, NEW_RUN, MAIN_MENU, EXIT_GAME }

func _build_menu_button() -> MenuButton:
	var mb := MenuButton.new()
	mb.text = "☰  Menu"
	mb.flat = false
	mb.tooltip_text = "Save this run, start a new one, go back to the main menu, or leave."
	var pop: PopupMenu = mb.get_popup()
	pop.add_item("💾   Save run", MenuItem.SAVE)
	pop.add_item("⟳   New run", MenuItem.NEW_RUN)
	pop.add_separator()
	pop.add_item("←   Main menu", MenuItem.MAIN_MENU)
	pop.add_item("⏻   Exit game", MenuItem.EXIT_GAME)
	pop.id_pressed.connect(menu_action)
	return mb

# Public so a test can press a menu entry without opening the popup.
func menu_action(id: int) -> void:
	match id:
		MenuItem.SAVE:
			prompt_save()
		MenuItem.NEW_RUN:
			start_run()
		MenuItem.MAIN_MENU:
			get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
		MenuItem.EXIT_GAME:
			prompt_quit()

# The door out, and the one exit that asks first — a live run is standing behind
# it. The autosave (see `autosave()`) means leaving is never a total loss, so the
# question is not "are you sure" but "in the save list or not", and the dialog
# offers the three answers that are actually different: name it and go, go, stay.
#
# Returned so a test can answer it without a click.
func prompt_quit() -> ConfirmationDialog:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Exit game"
	dlg.dialog_text = ("Leave the game?\n\nThis run is autosaved up to your last move, "
		+ "so Continue will pick it back up. Save it under a name to keep it in the "
		+ "save list as well.")
	dlg.ok_button_text = "Exit"
	dlg.get_cancel_button().text = "Cancel"
	dlg.add_button("Save & exit", true, "save_and_exit")
	dlg.confirmed.connect(quit_game)
	dlg.custom_action.connect(func(action: StringName):
		if action == &"save_and_exit":
			dlg.queue_free()
			prompt_save(quit_game))
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(480, 230))
	return dlg

func quit_game() -> void:
	get_tree().quit()

func _mini_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b
