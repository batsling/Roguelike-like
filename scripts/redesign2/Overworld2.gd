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
# Two pieces live next door — BattlefieldView (the board and its animation) and
# EnemyInfoCard (the click-to-inspect card) — and talk back through signals.
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

# Shields — the tries at the game in play (§3). One steel-blue used by the HUD
# count, the attempt strip, and the pips on the board.
const SHIELD_BLUE := Color(0.62, 0.78, 0.95)

# The currency and shop colours live on UITheme (COIN_GOLD / SHOP_GREEN, §14) —
# the shop modal and the game popup need them too, and a modal reaching back into
# the screen that mounted it for a constant is a dependency cycle.

# Lost runs of the game in play before the Escape button appears on a game this
# run has NOT already beaten (see can_escape — one it has is escapable from the
# first second). Five is past the shields any game grants, so reaching it means
# the player has been paying Health to keep trying.
const ESCAPE_AFTER_ATTEMPTS := 5

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
var _resolving: bool = false
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
# Checklist bindings for the two event-borne sections, cleared with the rest in
# _reset_checklist_state. Each entry is {check, index into GameState's array}.
var _event_goal_checks: Array = []
var _curse_goal_checks: Array = []
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
var _rng := RandomNumberGenerator.new()

# --- UI nodes (built in code) --------------------------------------------
# The verbs that are spent CHOOSING, as chips under the offering they act on.
# (The board's own verbs need no row of their own: BattlefieldView's toolbar
# buttons already read "⇤ Push (1)" / "✸ Bomb (3)", and its pressure bar ends in
# the run's tier.)
var _select_stats: HFlowContainer
var _item_card: ItemInfoCard = null # the open item reading card, or null
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
var _play_panel: VBoxContainer
var _now_playing: RichTextLabel
var _now_playing_cover: TextureRect # the chosen game's cover, beside it
var _launch_row: HBoxContainer
var _verify_box: VBoxContainer      # clean checklist: goal + level-up + follower goals
var _fulfil_checks: Array = []      # [{check: CheckBox, instance: int}]
# Statuses 2.0 (§13) on the report checklist. `_status_goal_checks` are the
# player's own BUFF goals — extra rows that pay when ticked, plus the `demand` rows
# that BITE when they are not; `_bonus_checks` are the OPTIONAL bonus objectives an
# enemy's `bonus` side hangs off it; `_instead_checks` are the "or instead" rows a
# burned enemy grows, each a second way to clear that body. All three are read into
# beat_game's `claims` on report; the required clauses (enemy buffs, player
# clauses) need no boxes of their own because they are folded into the goal line.
var _status_goal_checks: Array = [] # [{check: CheckBox, status: StringName}]
var _bonus_checks: Array = []       # [{check: CheckBox, instance: int, status: StringName}]
var _instead_checks: Array = []     # [{check: CheckBox, instance: int, status: StringName}]
var _levelup_check: CheckBox        # null when the character has no level-up
# Checklist row -> board body (see _bind_row_to_body). `_row_paints` is instance
# -> the paint callables of every row written about that body; `_lit_instances`
# is what is lit right now, from whichever end the mouse is on.
var _row_paints: Dictionary = {}
var _lit_instances: Dictionary = {}
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
var _checklist_sig: String = ""

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
# The shield grant of the card the mouse is over, or -1 when nothing is. Between
# games the pool is empty, so the HUD's Shields slot previews what the game you're
# pointing at would hand you instead of reading a flat 0 — the grant is part of the
# routing decision (a Traditional roguelike is worth 5).
var _hover_grant: int = -1
# Attempt tracker (§3) — the tries at the game in play.
var _attempt_count: Label
var _attempt_pips: Label
var _attempt_hint: Label
var _attempt_btn: Button
var _attempt_undo: Button
var _escape_btn: Button           # hidden until ESCAPE_AFTER_ATTEMPTS lost runs
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
var _items_box: HFlowContainer
# Drops a defeated enemy left, waiting to be ASKED about — one ItemDropModal at a
# time, in the order they fell (§8, _pump_drops). The modal in front of the
# player right now, or null when nothing is being asked.
# Each entry is one CHEST: {items: Array[ItemData]} — the things it is offering,
# of which the player takes at most one. A normal body's drop is a Small chest and
# so a list of one, which is why the single-item shorthand {item: ItemData} is
# still accepted (see _drop_items); There's Options is what makes a boss's longer.
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
	_resolving = false
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
# there, its goal, the tries the game grants, the connections it opens onto, and
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
		"tries": GameLoop2.shields_for_game(choice["game"]),
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
	var turns: int = RunDifficulty.turns_for_hops(hops)
	return {
		"text": "⏱ Enemies act ×%d turn%s there" % [turns, "" if turns == 1 else "s"],
		"color": RunDifficulty.turns_band_color(turns),
		"turns": turns,
		"tip": "Standing there, every enemy acts %d time%s per game.\n\n%s" % [
			turns, "" if turns == 1 else "s", RunDifficulty.turns_ladder_text(turns)],
	}

# Take the offered start at `index` (choose-your-start, Phase.START_SELECT).
#
# The start used to be a doorstep: you landed on the game, nothing spawned, no
# shields were granted, and the run's first real game was whatever you travelled
# to from it. It is a GAME now — its goal-enemy spawns and stands on the board
# with the rest, it hands over its tries, and the run opens on the report panel
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
		GameLog.add("%s — %d shields to spend on tries." % [game.display_name, granted],
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
	var drops: Array = []
	for d in _drop_queue:
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
		"tries": GameLoop2.shields_for_game(choice["game"]),
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
	# Selecting the game hands over your TRIES at it (§3): 3 shields, 5 for a
	# Traditional roguelike, plus whatever "when a game is selected" items add.
	var granted: int = GameLoop2.grant_selection_shields(_chosen["game"])
	GameLog.add("%s — %d shields to spend on tries." % [_chosen["game"].display_name, granted],
		SHIELD_BLUE)
	# Move to the graph SLOT (a transmuted card plays an off-graph game but keeps
	# its position on the route toward the amulet).
	GameState.set_current_game(_chosen["slot"])
	_hover_grant = -1
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
	_phase = Phase.PLAYING
	_populate_play_panel()
	_refresh()
	# The board is the hero of the playing screen, so land on it: the page stays at
	# the top and the checklist under the grid is a scroll away.
	_scroll_to_top()
	# Committing to a game is a move worth recovering to — the shields it granted
	# and the tries you're about to log all hang off it.
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
# the game they're playing. Each try spends a shield; once the shields are gone a
# try costs Health, and Health hitting 0 ends the run right there. The board pops
# a pip / flashes the hero off GameLoop2's attempt_logged signal.
func log_attempt() -> String:
	var cost: String = GameLoop2.log_attempt()
	if cost == "":
		return ""
	var game: GameData = _chosen.get("game")
	var game_name: String = game.display_name if game != null else "this game"
	if cost == "shield":
		GameLog.add("Lost a run of %s — a shield goes (attempt %d)." % [game_name, GameLoop2.attempts()],
			SHIELD_BLUE)
	else:
		var msg: String = "Out of shields on %s — a lost run costs %d Health." % [
			game_name, GameLoop2.ATTEMPT_HEALTH_COST]
		GameLog.add(msg, UITheme.DANGER)
		Notifications.notify(msg, UITheme.DANGER)
	_refresh()
	return cost

# --- escaping a game you can't beat ---------------------------------------
#
# Some games won't go down, and a run shouldn't end because one of them sat in
# the way. The player may walk away from the game in play at any point, without
# beating it — either after ESCAPE_AFTER_ATTEMPTS lost runs, or immediately on a
# game this run has already beaten (see can_escape).
#
# Escaping resolves the BOARD exactly as reporting a missed goal does: the
# goal-enemy walks onto the board and follows you, and every enemy already on it
# still takes its turns. That IS the price, and on the lost-runs route it has
# already been paid twice over by the time the button appears — five lost runs is
# the shields this game granted plus Health on top, with the front line closing in
# the whole time. The button exists to make the way out VISIBLE to a stuck player,
# not to discount it.
#
# Where it PARTS from a missed report is the item trigger: the "after beating a
# game" items fire on any game FINISHED, win or lose, and an escape is the one
# report that doesn't fire them. Neither one banks a beat — beaten means won (see
# report) — so an escape and a miss are alike in earning no repeat-beat Dash, no
# Atlas mark and no movement in either beaten tally.
#
# TWO ways in. The five-lost-runs rule above is for a game this run has never got
# through: the way out has to be earned because the alternative is a player who
# quits the run instead. A game this run has ALREADY BEATEN is the opposite case —
# there is nothing left to prove, and being made to lose at it five more times to
# unlock the door is a tax on the one card the run cannot make interesting, so
# that door is open from the first second.
#
# It is the same escape either way: the enemy still walks onto the board, the
# board still takes its turns, and the game still isn't credited. Only the gate
# moves.
func can_escape() -> bool:
	if _phase != Phase.PLAYING or _chosen.is_empty() or GameLoop2.run_over:
		return false
	return beaten_this_run() or GameLoop2.attempts() >= ESCAPE_AFTER_ATTEMPTS

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
func escape_game() -> void:
	if not can_escape():
		return
	var game: GameData = _chosen.get("game")
	var game_name: String = game.display_name if game != null else "this game"
	var tries: int = GameLoop2.attempts()
	var msg: String = ("Escaped %s — its enemy comes with you." % game_name if tries == 0
		else "Escaped %s after %d lost run%s — its enemy comes with you." % [
			game_name, tries, "" if tries == 1 else "s"])
	GameLog.add(msg, UITheme.ACCENT)
	Notifications.notify(msg, UITheme.ACCENT)
	report(false, null, true)

# Take back the last tick — the tracker is hand-driven, so a mis-click has to be
# reversible. Refunds exactly what that try spent.
func undo_attempt() -> String:
	var cost: String = GameLoop2.undo_attempt()
	if cost != "":
		GameLog.add("Took back an attempt (refunded 1 %s)." % ("shield" if cost == "shield" else "Health"),
			UITheme.TEXT_DIM)
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
# step toward enemies that act three times a game instead of once.
#
# Returned as {"text", "color", "tip", "turns"} — same shape as route_note, and
# `turns` is the count the card would leave you on, so a test can assert the
# number without parsing the sentence.
func turn_note(choice: Dictionary) -> Dictionary:
	var here: int = steps_to_amulet(GameState.current_game_id)
	var there: int = steps_to_amulet(choice.get("slot", &""))
	# The Amulet card ends the run on the spot: what the enemies would have done
	# afterwards is moot, and saying "×3 turns" there would just be alarming.
	if bool(choice.get("amulet", false)):
		there = 0
	var now: int = RunDifficulty.turns_for_hops(here)
	var then: int = RunDifficulty.turns_for_hops(there)
	var color: Color = RunDifficulty.turns_band_color(then)
	var tip: String = ("Standing there, every enemy acts %d time%s per game.\n\n%s"
		% [then, "" if then == 1 else "s", RunDifficulty.turns_ladder_text(then)])
	if bool(choice.get("amulet", false)):
		return {"text": "", "color": color, "tip": tip, "turns": then}
	if then > now:
		return {
			"text": "⏱ Enemies speed up — ×%d turns" % then,
			"color": color, "turns": then,
			"tip": "Closing on the Amulet is what wakes them up: %d turns a game here, %d there.\n\n%s"
				% [now, then, RunDifficulty.turns_ladder_text(then)],
		}
	if then < now:
		return {
			"text": "⏱ Enemies slow down — ×%d turns" % then,
			"color": color, "turns": then,
			"tip": "Backing off buys you pace: %d turns a game here, %d there.\n\n%s"
				% [now, then, RunDifficulty.turns_ladder_text(then)],
		}
	return {
		"text": "⏱ Still ×%d turn%s" % [then, "" if then == 1 else "s"],
		"color": UITheme.TEXT_DIM, "turns": then, "tip": tip,
	}

# Read the carried scroll at loot index `idx` (Scrolls panel). Opens the 2.0
# read modal, which consumes the scroll and applies its effect (§4.1).
func read_scroll(idx: int) -> void:
	var modal := preload("res://scripts/redesign2/ScrollReadModal.gd").new()
	modal.finished.connect(_refresh)
	modal.start(self, idx, self)

# Scroll of Teleportation (§4.1): move to a random game ~the same graph distance
# from the Amulet as the current position (±`spread`), excluding the current game
# and the amulet. Falls back to any reachable-distance node if the band is empty.
func scroll_teleport(_dir: String, spread: int) -> void:
	var amulet: StringName = GameState.amulet_game_id
	if amulet == &"":
		return
	var dist: Dictionary = RunGraph.bfs_distances(amulet)
	var cur: StringName = GameState.current_game_id
	if not dist.has(cur):
		return
	var cur_d: int = int(dist[cur])
	var band: Array = []
	var any: Array = []
	for gid in dist.keys():
		if gid == cur or gid == amulet or GameLoop2.is_bashed(gid):
			continue
		any.append(gid)
		if absi(int(dist[gid]) - cur_d) <= spread:
			band.append(gid)
	var pool: Array = band if not band.is_empty() else any
	if pool.is_empty():
		GameLog.add("The teleport fizzles — nowhere to go.", Color(0.61, 0.35, 0.71))
		return
	var dest: StringName = pool[_rng.randi() % pool.size()]
	GameState.set_current_game(dest)
	var g: GameData = Data.get_game(dest)
	GameLog.add("Teleported to %s." % (g.display_name if g != null else String(dest)),
		Color(0.61, 0.35, 0.71))
	_dash_mode = false
	_build_choices()
	_refresh()

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
	var leveled: bool = _levelup_check != null and _levelup_check.button_pressed
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
		_show_run_over()
		return
	_open_pending_event()

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
	set_process(_shop_panel != null and is_instance_valid(_shop_panel))

func _process(_delta: float) -> void:
	_update_shop_hint()

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
	_hover_grant = -1
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
	# A non-charged overworld active (Ride the Bus) commits immediately, so spend
	# its use here (use_item defers the spend for cancellable pickers).
	var spend_after: bool = not item.is_charged() and item.overworld_usable
	GameState.use_item(item)
	if spend_after and GameState.inventory.has(item):
		GameState.consume_item_use(item)
	_refresh_items()

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

# The choose-your-start panel (Phase.START_SELECT): one card per offered start,
# each a different genre and each the same distance band from the amulet, so the
# decision is "which genre do I want to open on and route from", never "which of
# these is the short run".
func _render_start_choices() -> void:
	_clear(_choices_row)
	_hover_grant = -1
	if _start_options.is_empty():
		var l := Label.new()
		l.text = "No start could be rolled — check the game filter in Settings."
		_choices_row.add_child(l)
		return
	for i in range(_start_options.size()):
		_choices_row.add_child(_make_start_card(i, _start_options[i]))
	_preview.text = _preview_idle_text()
	_show_hover_art({})

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

# One start card: the cover, the game's name, its genre, and how many games stand
# between it and the Amulet — which is named, along with everything else on the
# road to it (see amulet_name).
func _make_start_card(index: int, opt: Dictionary) -> Control:
	var game: GameData = opt["game"]
	var accent: Color = RunGraph.type_color(int(opt["type"]))
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	card.custom_minimum_size = Vector2(COVER_SIZE.x + 10, 0)

	var type_lbl := Label.new()
	type_lbl.text = RunGraph.type_label(int(opt["type"]))
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE)
	type_lbl.add_theme_font_size_override("font_size", 13)
	type_lbl.add_theme_color_override("font_color", accent.lerp(UITheme.TEXT, 0.35))
	card.add_child(type_lbl)

	# The road this start opens on, before committing to it. The destination is
	# drawn unnamed — the distance is still the only thing the picker gives away
	# about the Amulet — but its SHAPE is exactly what makes one start different
	# from another, so it's on the table.
	card.add_child(_map_preview_button(game.id, game))

	var btn := Button.new()
	btn.custom_minimum_size = COVER_SIZE
	var frame_n := UITheme.flat(UITheme.BG, 8, 4, 1, UITheme.BORDER)
	var frame_h := UITheme.flat(UITheme.PANEL_HI, 8, 4, 2, accent)
	btn.add_theme_stylebox_override("normal", frame_n)
	btn.add_theme_stylebox_override("hover", frame_h)
	btn.add_theme_stylebox_override("pressed", frame_h)
	btn.add_theme_stylebox_override("focus", frame_h)
	# Opens the card rather than committing: the start is a game you go and play
	# now, so it gets the same "here is what's waiting, do you want it" popup every
	# other game in the run gets. No tooltip, for the same reason an offered card
	# has none — the hover line under the cards is where a start describes itself.
	btn.pressed.connect(func(): open_start_choice(index))
	btn.mouse_entered.connect(func(): _show_start_preview(index))
	btn.mouse_exited.connect(_clear_hover_grant)
	if game.cover_image != null:
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = game.cover_image
		btn.add_child(art)
	else:
		btn.text = game.display_name
		btn.add_theme_color_override("font_color", accent)
	card.add_child(btn)

	var name_lbl := Label.new()
	name_lbl.text = game.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, NAME_BOX_H)
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	card.add_child(name_lbl)

	var dist := Label.new()
	dist.text = _start_distance_text(int(opt["path_len"]))
	dist.tooltip_text = "The shortest route from %s to %s, the game this run ends on." % [
		game.display_name, amulet_name()]
	dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dist.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE * 2 + 2)
	dist.add_theme_font_size_override("font_size", BADGE_FONT)
	dist.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT, 0.35))
	card.add_child(dist)
	return card

func _show_start_preview(index: int) -> void:
	if index < 0 or index >= _start_options.size():
		return
	var opt: Dictionary = _start_options[index]
	# The same one-line hover the offering writes — the start is a game you play,
	# so what is waiting at it is readable without opening the card, exactly as it
	# is for every other card in the run.
	_hover_grant = GameLoop2.shields_for_game(opt["game"])
	var choice: Dictionary = _start_choice(index)
	_preview.text = "%s  ·  [color=#%s]%s[/color]" % [
		_hover_line(choice), UITheme.GOLD.to_html(false),
		_start_distance_text(int(opt["path_len"]))]
	_show_hover_art(choice)

func _render_choices() -> void:
	_clear(_choices_row)
	# The cards are rebuilt, so nothing is hovered any more.
	_hover_grant = -1
	if _choices.is_empty():
		var l := Label.new()
		l.text = "No reachable games — dead end."
		_choices_row.add_child(l)
		return
	for i in range(_choices.size()):
		_choices_row.add_child(_make_choice_card(i, _choices[i]))
	_preview.text = _preview_idle_text()
	_show_hover_art({})

# The offered cover art, back at the size it deserves. It was halved when the
# offering moved into the left column beside the board (COVER_SIZE was 105x140),
# because seven rows of badges were stacked around every cover and three of those
# columns had to fit side by side. The badges have gone into GameChoiceModal, so
# the art gets the room back.
const COVER_SIZE := Vector2(150, 200)

# The width of the enemy portrait on the hover line under the offering. Its
# HEIGHT is the line's, whatever that turns out to be — and that is the whole
# trick, because it is what makes the portrait FREE.
#
# The overworld is fitted to a 720p window with single-digit pixels to spare
# (test_overworld2's _assert_fits), and the page's worst case — three arcade
# machines under the board — sits within about four of them. A hover row that
# reserved even 30px of height for art blew that budget on its own. So the art
# fills the line instead of setting its height: same page, one more thing on it.
#
# That makes it small, which is the right size anyway. This is an IDENTIFIER for
# a body the player already knows — the same job, and the same scale, as the
# portraits on a card's Beatable row. The exhibit is in the popup the card opens,
# where the enemy is drawn at full size.
const HOVER_ART := 30.0

# The badge rows on a card: the name, plus two fixed-height flag lines above the
# cover — the Amulet / event flag, and the repeat game's +1 Dash. Everything else
# a card used to carry (the route, the pace, the tries, the map, the Beatable row,
# the Bash/Transmute verbs) lives in the popup the card opens.
const BADGE_FONT := 11
const BADGE_LINE := 15               # one line of BADGE_FONT, in px
# The game's NAME keeps a readable size, in its own fixed box, so a card whose
# title wraps to three lines doesn't sit a line taller than its neighbours.
const NAME_FONT := 13
const NAME_BOX_H := 51               # three lines of NAME_FONT — "Shotgun King:
                                     # The Final Checkmate" needs all three

# One choice = the game's cover art, its name, and — when it is the game the whole
# run is a search for — the Amulet's flag above it. Nothing else: clicking the
# card opens GameChoiceModal, which is where the route, the enemy, the tries and
# the verbs all get said properly, and where the game is actually chosen.
#
# Hover still updates the shared enemy preview under the row, so the offering can
# be read at a glance without opening anything.
# The shop flag's hover: the headline, plus the shelf itself once the player has
# actually been in there. Both come from ShopSystem so this and the popup's shop
# block cannot end up describing the same shelf differently.
func _shop_card_tooltip(game: GameData) -> String:
	# "…and no event" is worth a line here because it is the ONE place a hub
	# differs from every other card in what it costs you: a shop stands here
	# instead of an event, not as well as one (§12).
	var lines: Array = [ShopSystem.headline(game.id),
		"A shop stands here, so no event fires — this is what happens instead."]
	var stock: Array = ShopSystem.stock_lines(game.id)
	if not stock.is_empty():
		lines.append("")
		lines.append_array(stock)
	return "\n".join(lines)


func _make_choice_card(index: int, choice: Dictionary) -> Control:
	var game: GameData = choice["game"]
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	card.custom_minimum_size = Vector2(COVER_SIZE.x + 10, 0)

	var amulet: bool = bool(choice["amulet"])
	var accent: Color = UITheme.DANGER if choice["boss"] else (UITheme.GOLD if amulet else UITheme.type_color(int(game.type)))

	# THE ONE THING that has to be legible without opening anything: this is the
	# game the run ends on. The row is mounted on every card, blank off the Amulet,
	# so the flagged card's cover stays in line with the rest of the offering.
	#
	# There WAS an `✦ EVENT` badge in this row. It marked the handful of dead ends
	# carrying an event, back when placement was hashed onto specific nodes and
	# routing towards one was a decision. An event now fires after every game
	# played, so a badge on every card would say nothing — and the hash it
	# depended on is gone with it, which means there is no longer an honest answer
	# to "which event is at that node" before the run gets there.
	#
	# The SHOP badge (§14) is the row's other tenant. Its colour is deliberately
	# not a gold — see UITheme.SHOP_GREEN — because a gold badge sitting in the
	# Amulet's own slot is the one confusion this row cannot afford.
	var flag := Label.new()
	if amulet:
		flag.text = "🏆 THE AMULET"
		flag.tooltip_text = "Beat this game's goal and you win the run."
		flag.add_theme_color_override("font_color", UITheme.GOLD)
	elif ShopSystem.is_hub(game.id):
		flag.text = "🛒 SHOP"
		flag.tooltip_text = _shop_card_tooltip(game)
		flag.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	else:
		flag.text = ""
		flag.add_theme_color_override("font_color", UITheme.GOLD)
	flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flag.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE)
	flag.add_theme_font_size_override("font_size", BADGE_FONT)
	card.add_child(flag)

	# THE SECOND THING that has to be legible without opening anything: a game you
	# have already played this run pays a Dash for going back and beating it
	# (REPEAT_BEAT_DASH). It is the offering's only recurring free charge, and it
	# was only ever stated inside the popup — so the one card on the table that is
	# worth revisiting looked exactly like the ones that aren't. It rides ABOVE the
	# cover, next to the Amulet's flag, because it is a reason to open a card and
	# reasons to open a card belong where the card is being scanned.
	#
	# Like the flag, the row is mounted on EVERY card and left blank off a repeat,
	# so one +1 in the offering doesn't knock the other covers out of line.
	var dash_flag := Label.new()
	if bool(choice.get("repeat", false)):
		dash_flag.text = "⚡ +%d DASH" % REPEAT_BEAT_DASH
		dash_flag.tooltip_text = ("You have played %s already this run — go back and beat it and it pays %d Dash charge%s."
			% [game.display_name, REPEAT_BEAT_DASH, "" if REPEAT_BEAT_DASH == 1 else "s"])
	else:
		dash_flag.text = ""
	dash_flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dash_flag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dash_flag.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE)
	dash_flag.add_theme_font_size_override("font_size", BADGE_FONT)
	dash_flag.add_theme_color_override("font_color", DASH_BLUE)
	card.add_child(dash_flag)

	# NO TOOLTIP. The offering is the one place on the page that does NOT get a
	# hover card: the enemy's portrait and its goal are already written on the
	# hover line under the cards (see _show_preview), which is the same read the
	# card would be, and a popup over the covers while the mouse crosses three of
	# them is the noisiest possible way to say it. The cards are for scanning.
	var btn := Button.new()
	btn.custom_minimum_size = COVER_SIZE
	var frame_n := UITheme.flat(UITheme.BG, 8, 4, 1, UITheme.GOLD if amulet else UITheme.BORDER)
	var frame_h := UITheme.flat(UITheme.PANEL_HI, 8, 4, 2, accent)
	btn.add_theme_stylebox_override("normal", frame_n)
	btn.add_theme_stylebox_override("hover", frame_h)
	btn.add_theme_stylebox_override("pressed", frame_h)
	btn.add_theme_stylebox_override("focus", frame_h)
	btn.pressed.connect(func(): open_choice(index))
	btn.mouse_entered.connect(func(): _show_preview(index))
	btn.mouse_exited.connect(_clear_hover_grant)
	if game.cover_image != null:
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = game.cover_image
		btn.add_child(art)
	else:
		btn.text = game.display_name
		btn.add_theme_color_override("font_color", accent)
	card.add_child(btn)

	var name_lbl := Label.new()
	name_lbl.text = ("☠ " if choice["boss"] else ("🏆 " if amulet else "")) + game.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, NAME_BOX_H)
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT)
	name_lbl.add_theme_color_override("font_color", accent if (choice["boss"] or amulet) else UITheme.TEXT)
	card.add_child(name_lbl)
	return card

# The 🗺 button every offered card wears above its cover: opens the optimal path
# from that game to the Amulet. Full width of the card, so the row of covers stays
# in line whatever a card's route badge says.
func _map_preview_button(slot: StringName, game: GameData) -> Button:
	var b := Button.new()
	b.text = "🗺  Map"
	b.tooltip_text = "See the shortest route to the Amulet if you take %s." % game.display_name
	b.custom_minimum_size = Vector2(COVER_SIZE.x, 24)
	b.add_theme_font_size_override("font_size", BADGE_FONT)
	b.pressed.connect(func(): preview_map(slot))
	return b

# "Beatable:" — the enemies on the board right now that you have ALREADY beaten
# at this game before. Not a prediction: it's your own record saying this pair
# has worked, which is exactly what you want to know while choosing where to go
# with a follower stuck to you.
#
# Returns null when there's nothing to say, so an unproven card stays clean.
func _beatable_row(choice: Dictionary) -> Control:
	var game: GameData = choice.get("game")
	if game == null:
		return null
	# The enemy standing at this card, plus everything currently following you.
	# Under the Runic Dome the card's own enemy is left out: a "Beatable" pip is a
	# portrait with a name on it, so keeping it would hand back the exact thing
	# the relic is meant to be hiding. The FOLLOWERS stay — they are already on
	# the board and the Dome only ever hid what has yet to spawn.
	var on_board: Array = []
	var here: GoalEnemyData = choice.get("enemy")
	if here != null and not _enemy_hidden(choice):
		on_board.append(here)
	for entry in GameLoop2.stack:
		var follower: GoalEnemyData = entry.get("enemy")
		if follower != null:
			on_board.append(follower)

	var proven: Array = []
	var seen: Dictionary = {}
	for enemy in on_board:
		if seen.has(enemy.id):
			continue
		if GameStats.enemy_beaten_count(game.id, enemy.id) > 0:
			seen[enemy.id] = true
			proven.append(enemy)
	if proven.is_empty():
		return null

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = "Beatable:"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UITheme.SUCCESS)
	row.add_child(label)
	for enemy in proven:
		row.add_child(_beatable_pip(game, enemy))
	return row

# One enemy on the Beatable row: its portrait, with the record and whatever note
# was written on the hover — the note is the reason you know it's beatable.
func _beatable_pip(game: GameData, enemy: GoalEnemyData) -> Control:
	var times: int = GameStats.enemy_beaten_count(game.id, enemy.id)
	var note: String = GameStats.enemy_note(game.id, enemy.id).strip_edges()
	var tip: String = "%s — beaten here ×%d" % [enemy.display_name, times]
	if enemy.goal != "":
		tip += "\n%s" % enemy.goal
	if note != "":
		tip += "\n\n🗒 %s" % note
	if enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		art.custom_minimum_size = Vector2(20, 20)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.tooltip_text = tip
		return art
	# No portrait authored — fall back to the name rather than an empty gap.
	var chip := Label.new()
	chip.text = enemy.display_name
	chip.add_theme_font_size_override("font_size", 9)
	chip.add_theme_color_override("font_color", UITheme.SUCCESS)
	chip.tooltip_text = tip
	return chip

# Build the self-report panel for the chosen game: a launch button (when the
# game can be launched) and a fulfilment checkbox per following enemy so old
# goals can be cleared this game (§2).
func _populate_play_panel() -> void:
	# The report step and the standing checklist share _verify_box, so taking it
	# over here has to drop the standing list's signature — otherwise the next
	# return to the offering would match a signature describing rows this panel
	# replaced, and leave the report step's checklist on screen. Not guarded
	# itself: it holds the player's TICKS, and rebuilding it is what the tick
	# handlers rely on.
	_checklist_sig = ""
	_clear(_launch_row)
	_clear(_verify_box)
	_reset_checklist_state()
	if _chosen.is_empty():
		return
	var game: GameData = _chosen["game"]
	# "Open the real game" — launches the executable/shortcut in the game's
	# file_location column (falling back to its store page). Only games with a
	# launch target get the button.
	if game.has_launch_target():
		var play_btn := Button.new()
		play_btn.text = "▶  Play %s" % game.display_name
		play_btn.custom_minimum_size = Vector2(0, 38)
		play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play_btn.add_theme_stylebox_override("normal", UITheme.flat(Color(0.10, 0.22, 0.16, 0.9), 8, 8, 1, Color(0.4, 0.9, 0.6)))
		play_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		play_btn.pressed.connect(func(): game.launch())
		_launch_row.add_child(play_btn)
	# Manual "rate this game" entry point (the report step also auto-prompts after
	# you press Completed Game).
	var rate_btn := Button.new()
	rate_btn.text = "★  Rate this game"
	rate_btn.custom_minimum_size = Vector2(0, 38)
	rate_btn.add_theme_color_override("font_color", UITheme.GOLD)
	rate_btn.pressed.connect(func(): _prompt_rating(game))
	_launch_row.add_child(rate_btn)

	# One clean checklist of everything to verify this game. Tick what you actually
	# did, then press "Completed Game" once (§2 / §3.1):
	#   • EVERY ENEMY on the board, in one list — the ones that walked on when you
	#     took this game and the ones that have been following you for ten;
	#   • the character LEVEL-UP challenge;
	#   • the event and curse goals.
	#
	# THERE IS NO "GOAL" BOX. The enemy the card advertised used to get an
	# emphasised row of its own at the top, because it was the game's own enemy and
	# beating the game was what cleared it. Nothing is a game's own enemy any more
	# (GameLoop2.arrivals): a body that walked on this game and a body you have
	# owed since three games ago are the same kind of debt, and asking about them
	# in two different places said they were not.
	_verify_box.add_child(_verify_head("Tick what you did this game:"))

	# On the Amulet, playing the game is the win — not any goal on this list (see
	# report()). Said at the top, because a checklist is otherwise exactly where a
	# player would look for the win condition and not find it.
	if bool(_chosen.get("amulet", false)):
		var win_note := Label.new()
		win_note.text = "🏆  Completing this game wins the run — everything below is a bonus."
		win_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		win_note.add_theme_font_size_override("font_size", 12)
		win_note.add_theme_color_override("font_color", UITheme.GOLD)
		_verify_box.add_child(win_note)

	# The player's own standing rows (§13): challenges that pay out every game you
	# satisfy them, and the `demand` rows that CHARGE for every game you don't — so
	# they are on the report step of EVERY game rather than belonging to any one
	# enemy. A demand is tinted like the threat it is: on this list an unticked box
	# usually means a prize forgone, and on that one row it means a bill.
	for row in GameState.status_objectives():
		var sd: StatusData = row["status"]
		var stacks: int = int(row["stacks"])
		var srow := _verify_row(
			"%s %s" % [_status_prefix(sd, stacks), sd.objective_text(StatusData.PLAYER, stacks)],
			_status_row_tint(sd), false)
		_verify_box.add_child(srow["row"])
		_status_goal_checks.append({"check": srow["check"], "status": sd.id})

	# Level-up challenge (§3.1): a per-game Yes/No for the character's condition,
	# with its reward shown inline so the payoff reads at a glance. It carries its
	# own Notes button for the same reason the goal rows do — the condition is a
	# standing one, and how you satisfied it is a fact about THIS game.
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null and ch.level_up_condition != "":
		var lu_text: String = "Leveled up — %s" % ch.level_up_condition
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			lu_text += "   → %s" % ch.level_up_reward
		var lu_row := _verify_row(lu_text, UITheme.GOLD, false, null, ch)
		_levelup_check = lu_row["check"]
		_verify_box.add_child(lu_row["row"])

	# EVENT GOALS and CURSE GOALS (docs/event-sheet-authoring.md §5). Their own
	# sections, deliberately: the checklist now carries three kinds of objective
	# and they bite in three different ways. An enemy goal is a DEBT — miss it and
	# it follows you and hits. An event goal is a BONUS — miss it and it merely
	# expires. A curse is a BILL, and the only row here you tick to say you did
	# something WRONG. Rendering all three alike would misrepresent which one
	# hurts, so the curse rows are purple and sit apart.
	_add_event_goal_rows()

	# GOAL FIRST, then whose it is. The checklist is scanned for "what did I
	# actually do", and the goal is the part being answered — the enemy's name is
	# the label on it. Leading with the name made every row start with a proper
	# noun the player has to read past to reach the thing they're ticking.
	#
	# EVERY body on the board, on the same terms and in board order. The ones that
	# walked on when this game was taken are simply the last ones in the list.
	for entry in GameLoop2.stack:
		var inst: int = int(entry["instance"])
		var e: GoalEnemyData = entry["enemy"]
		var row := _verify_row("Cleared: %s — %s" % [
			GameLoop2.goal_text_for(entry), e.display_name], UITheme.TEXT, false, e, null, inst)
		_verify_box.add_child(row["row"])
		_fulfil_checks.append({"check": row["check"], "instance": inst})
		_add_instead_rows(entry)
		_add_bonus_rows(entry)

# The two event-borne sections of the checklist. Both count down in games, and
# both show how long is left — an objective with a clock on it is a different
# decision on its last game than on its first, and the player cannot see the
# clock anywhere else.
func _add_event_goal_rows() -> void:
	for i in range(GameState.event_goals.size()):
		var goal: Dictionary = GameState.event_goals[i]
		var left: int = int(goal.get("games_left", 0))
		var text: String = "Event goal — %s   → %s   (%d %s left)" % [
			goal.get("condition", ""), goal.get("effects_text", ""),
			left, "game" if left == 1 else "games"]
		var row := _verify_row(text, UITheme.ACCENT, false)
		_verify_box.add_child(row["row"])
		_event_goal_checks.append({"check": row["check"], "index": i})

	for i in range(GameState.curse_goals.size()):
		var entry: Dictionary = GameState.curse_goals[i]
		var cd: CurseData2 = Data.get_curse2(StringName(entry.get("curse", &"")))
		if cd == null:
			continue
		var left: int = int(entry.get("games_left", 0))
		# A CURSE IS A ROW LIKE ANY OTHER: an instruction, ticked if you followed
		# it, with what it costs you written after it. It used to be phrased as the
		# rule instead — "If you use a rest site to replenish health, spawn a random
		# enemy when you report the game" — with a box that fired the penalty when
		# you CHECKED it. That made it the one row on this list whose tick meant the
		# opposite of every other row's, and it read as a confession rather than as
		# something to go and do. Unticked is the failure here exactly as it is on
		# the goal above it; the difference is only what failing costs.
		var text: String = "%s — %s   if failed, %s   (%s)" % [
			cd.display_name, cd.goal_text(), cd.penalty_text,
			CurseData2.window_text(left)]
		var row := _verify_row(text, UITheme.CURSE, false)
		_verify_box.add_child(row["row"])
		_curse_goal_checks.append({"check": row["check"], "index": i})


# Pay out whatever the player ticked in those two sections. Claims are resolved
# HIGHEST INDEX FIRST because claiming an event goal removes it from the array,
# and a low-index removal would shift every index recorded after it.
func _resolve_event_goal_rows() -> void:
	var claimed: Array = []
	for entry in _event_goal_checks:
		var check: CheckBox = entry.get("check")
		if check != null and is_instance_valid(check) and check.button_pressed:
			claimed.append(int(entry.get("index", -1)))
	claimed.sort()
	claimed.reverse()
	for idx in claimed:
		var goal: Dictionary = GameState.claim_event_goal(idx)
		if goal.is_empty():
			continue
		var src: EventData2 = Data.get_event2(StringName(goal.get("event", &"")))
		var line: String = src.goal_met if src != null and src.goal_met != "" else \
			"Event goal met — %s." % goal.get("effects_text", "")
		Notifications.notify(line, UITheme.ACCENT)
		GameLog.add(line, UITheme.ACCENT)

	# A curse fires but does NOT clear — that is what separates it from a goal.
	# Breaking it twice across two games costs twice; only the timer removes it.
	#
	# UNTICKED is what fires it. The row is an instruction (see
	# _add_event_goal_rows), so a box left empty says the player did not follow it
	# — the same thing an empty box says on every other row of the checklist.
	var triggered: Array = []
	for entry in _curse_goal_checks:
		var check: CheckBox = entry.get("check")
		if check != null and is_instance_valid(check) and not check.button_pressed:
			triggered.append(int(entry.get("index", -1)))
	for idx in triggered:
		var fired: Dictionary = GameState.trigger_curse_goal(idx)
		if fired.is_empty():
			continue
		var cd: CurseData2 = Data.get_curse2(StringName(fired.get("curse", &"")))
		if cd != null:
			var line: String = "%s bites — %s." % [cd.display_name, cd.penalty_text]
			Notifications.notify(line, UITheme.CURSE)
			GameLog.add(line, UITheme.CURSE)


# Every `demand` the report left unanswered, and what it cost (§13). Says what the
# hit was for AND what stopped it: a burn the tries absorbed whole took no Health,
# and a line that only quoted the 3 would read as a lie next to an unmoved bar.
func _announce_status_penalties(res: Dictionary) -> void:
	for raw in res.get("status_penalties", []):
		if not (raw is Dictionary):
			continue
		var bite: Dictionary = raw
		var sd: StatusData = Data.get_status(StringName(bite.get("status", &"")))
		if sd == null:
			continue
		var dealt: int = int(bite.get("damage", 0))
		var blocked: int = int(bite.get("blocked", 0))
		var line: String = "%s bites — %d damage" % [sd.display_name, dealt]
		if blocked > 0:
			line += ", %d absorbed by the tries" % blocked
		line += "."
		Notifications.notify(line, UITheme.DANGER)
		GameLog.add(line, UITheme.DANGER)

# The OPTIONAL bonus rows an enemy's `bonus` sides hang off it (§13) — "and if you get 3
# achievements, gain +3 Small Chests". A row of its own rather than part of the
# goal line, because claiming it is a separate decision from meeting the goal: an
# enemy you failed can still pay its bonus, and one you beat need not have.
# The "or instead" rows a burned enemy grows (§13) — the SECOND WAY to clear this
# body, ticked when the player did the alternative rather than the goal.
#
# A row of its own and not a second reading of the goal row, because the two answer
# different questions and the run records them differently: ticking the goal says
# the enemy's condition was met, and this one says it never was. So this row
# deliberately carries NO Notes button — `_verify_row` only grows one when it is
# handed the enemy — since a note here would be a note about how you beat a goal you
# didn't do. Same reason `_ticked_status_claims` keeps these out of the fulfilments
# the report records defeats from.
func _add_instead_rows(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var instance: int = int(entry.get("instance", 0))
	for row in GameLoop2.alternatives_for(entry):
		var sd: StatusData = row["status"]
		var stacks: int = int(row["stacks"])
		var irow := _verify_row("%s or instead: %s" % [
			_status_prefix(sd, stacks), sd.alternative_text(StatusData.ENEMY, stacks)],
			UITheme.GOLD.lerp(UITheme.TEXT, 0.3), false, null, null, instance)
		_verify_box.add_child(irow["row"])
		_instead_checks.append({"check": irow["check"], "instance": instance,
			"status": sd.id})

func _add_bonus_rows(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var instance: int = int(entry.get("instance", 0))
	for row in GameLoop2.bonus_objectives_for(entry):
		var sd: StatusData = row["status"]
		var stacks: int = int(row["stacks"])
		var brow := _verify_row(
			"%s %s" % [_status_prefix(sd, stacks), sd.objective_text(StatusData.ENEMY, stacks)],
			UITheme.GOLD.lerp(UITheme.TEXT, 0.3), false, null, null, instance)
		_verify_box.add_child(brow["row"])
		_bonus_checks.append({"check": brow["check"], "instance": instance, "status": sd.id})

# What colour a player-side status row reads in. GOLD is the checklist's colour
# for "something you can earn"; a `demand` is the one row where leaving the box
# empty COSTS something, so it takes the danger tint the curse rows established.
func _status_row_tint(status: StatusData) -> Color:
	return UITheme.DANGER if status.is_demand(StatusData.PLAYER) else UITheme.GOLD

# How a status announces itself on a checklist row: its name and stack count.
# "Marked 3 —" carries the X the rest of the line was written against, which is
# the number the player has to hold in their head while they play.
func _status_prefix(status: StatusData, stacks: int) -> String:
	return "%s %d —" % [status.display_name, stacks]

# Every per-game checklist binding, dropped together. Five parallel arrays that
# must be cleared as one — a stale CheckBox left in any of them is a claim read
# off a freed node on the next report.
func _reset_checklist_state() -> void:
	# The rows are about to be freed, and with them every paint bound to a body.
	# Nothing is lit on a list that no longer exists, so the board is told too.
	_row_paints.clear()
	if not _lit_instances.is_empty():
		_lit_instances = {}
		if _board != null:
			_board.highlight([])
	_fulfil_checks.clear()
	_status_goal_checks.clear()
	_bonus_checks.clear()
	_instead_checks.clear()
	_event_goal_checks.clear()
	_curse_goal_checks.clear()
	_levelup_check = null

# The checklist while you're CHOOSING: the goals already on you — the character's
# level-up challenge, and every follower's outstanding goal (any of which you may
# clear during whatever game you pick next, §2). Answering "what do I need to do?"
# belongs BEFORE you commit to a game, not only after, so the panel keeps its place
# beside the board instead of appearing out of nowhere on pick.
#
# Read-only by design: there is nothing to report until a game is in play, so these
# are rows rather than tick boxes.
func _populate_standing_checklist() -> void:
	var sig: String = _standing_checklist_sig()
	if sig == _checklist_sig and _verify_box.get_child_count() > 0:
		return
	_checklist_sig = sig
	_clear(_launch_row)
	_clear(_verify_box)
	_reset_checklist_state()
	_verify_box.add_child(_verify_head("What you need to do:"))

	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null and ch.level_up_condition != "":
		var lu_text: String = "Level up — %s" % ch.level_up_condition
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			lu_text += "   → %s" % ch.level_up_reward
		_verify_box.add_child(_objective_row(lu_text, UITheme.GOLD))

	# Event goals and curses, read-only (docs/event-sheet-authoring.md §5). These
	# have to be here and not only on the report step: an event fires the moment a
	# game is beaten, and the goal it hands over lands while the player is still
	# looking at the OFFERING. Listing it only once a game is picked meant taking
	# on "beat a game in 1 attempt" and then being shown nothing about it until
	# after the decision it was supposed to inform.
	for goal in GameState.event_goals:
		var left: int = int(goal.get("games_left", 0))
		_verify_box.add_child(_objective_row("Event goal — %s   → %s   (%d %s left)" % [
			goal.get("condition", ""), goal.get("effects_text", ""),
			left, "game" if left == 1 else "games"], UITheme.ACCENT))
	for entry in GameState.curse_goals:
		var cd: CurseData2 = Data.get_curse2(StringName(entry.get("curse", &"")))
		if cd == null:
			continue
		var left: int = int(entry.get("games_left", 0))
		# The same instruction the report step will ask about, because this list is
		# headed "What you need to do" and the answer for a curse is the thing to
		# do, not the rule it is derived from.
		_verify_box.add_child(_objective_row("%s — %s   if failed, %s   (%s)" % [
			cd.display_name, cd.goal_text(), cd.penalty_text,
			CurseData2.window_text(left)], UITheme.CURSE))

	# The player's standing status buffs (§13) — goals that belong to no enemy and
	# are available at whatever game gets picked next.
	for row in GameState.status_objectives():
		var sd: StatusData = row["status"]
		var stacks: int = int(row["stacks"])
		_verify_box.add_child(_objective_row(
			"%s %s" % [_status_prefix(sd, stacks), sd.objective_text(StatusData.PLAYER, stacks)],
			_status_row_tint(sd)))

	# Followers, tinted the way the board tints them: the ones in the front column
	# are the goals worth clearing first, because they hit next game.
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var urgent: bool = GameLoop2.in_front(entry)
		var tint: Color = UITheme.DANGER if urgent else UITheme.GOLD.lerp(UITheme.TEXT, 0.4)
		# Goal first, then whose it is — same order as the report step, since these
		# are the same list in two states and the goal is what's being read for.
		# "dmg N" in words: the board's ⚔ badge is a fine-detail glyph that reads as
		# an ✕ at list-row sizes.
		var inst: int = int(entry.get("instance", 0))
		_verify_box.add_child(_objective_row(
			"%s — %s   (dmg %d)" % [GameLoop2.goal_text_for(entry), e.display_name, e.damage],
			tint, _boss_icon(e), inst))
		# The way out of that goal, if something burned this body (§13) — read here
		# rather than only on the report step, because it is a reason to play the
		# next game differently and this list is what is read before choosing one.
		for alt in GameLoop2.alternatives_for(entry):
			var asd: StatusData = alt["status"]
			var astacks: int = int(alt["stacks"])
			_verify_box.add_child(_objective_row("%s or instead: %s" % [
				_status_prefix(asd, astacks),
				asd.alternative_text(StatusData.ENEMY, astacks)],
				UITheme.GOLD.lerp(UITheme.TEXT, 0.3), null, inst))
		for bonus in GameLoop2.bonus_objectives_for(entry):
			var sd: StatusData = bonus["status"]
			var stacks: int = int(bonus["stacks"])
			_verify_box.add_child(_objective_row(
				"%s %s" % [_status_prefix(sd, stacks), sd.objective_text(StatusData.ENEMY, stacks)],
				UITheme.GOLD.lerp(UITheme.TEXT, 0.3), null, inst))

	if GameLoop2.stack.is_empty() and GameState.status_objectives().is_empty():
		var none := _verify_head("Nothing is following you — pick a game and take on its goal.")
		_verify_box.add_child(none)

# Everything the standing checklist draws, as one string — the guard for the
# rebuild above (see the repaint-guard block near the top of the file).
#
# It quotes the SAME calls the rebuild does rather than a summary of them
# (`goal_text_for` is the row's actual text, `in_front` is its tint), so a row
# whose wording changes for any reason at all changes the signature with it. That
# costs those calls twice on a rebuild, which is fine: they are string work, and
# what a rebuild actually pays for is the Labels.
#
# `_launch_row` is not represented because this function always leaves it empty —
# only the report step (_populate_play_panel) puts anything in it.
func _standing_checklist_sig() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null:
		parts.append("%s/%s" % [ch.level_up_condition, ch.level_up_reward])
	parts.append(str(GameState.event_goals))
	parts.append(str(GameState.curse_goals))
	for row in GameState.status_objectives():
		parts.append("%s:%d" % [String((row["status"] as StatusData).id), int(row["stacks"])])
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		parts.append("%d:%s:%s:%d:%s" % [int(entry.get("instance", 0)),
			GameLoop2.goal_text_for(entry), e.display_name, e.damage,
			str(GameLoop2.in_front(entry))])
		for alt in GameLoop2.alternatives_for(entry):
			parts.append("/%s:%d" % [String((alt["status"] as StatusData).id),
				int(alt["stacks"])])
		for bonus in GameLoop2.bonus_objectives_for(entry):
			parts.append("+%s:%d" % [String((bonus["status"] as StatusData).id),
				int(bonus["stacks"])])
	return "|".join(parts)

# --- the checklist and the board, pointing at each other -------------------
#
# A goal on the checklist and a body on the board are the same fact written
# twice, and until now nothing said which line went with which enemy: a list of
# four goals beside a board of four bodies left the player matching them up by
# name. So the pair is LIT FROM EITHER END. Hovering a goal row brightens the
# enemies it belongs to; hovering an enemy brightens its row. One binding does
# both directions, because they are the same relation read from opposite sides.
#
# `instance` 0 means the row belongs to no body (the level-up challenge, an event
# goal, a player status): those rows bind nothing and stay inert.

# Bind one checklist row to one body. `paint` is called with whether the row
# should read as lit; it is kept per instance so the board's hover can find it.
#
# Call this once the row is FULLY BUILT: the whole row is the hover target, and
# what makes that work is walking what is actually in it.
func _bind_row_to_body(row: Control, instance: int, paint: Callable) -> void:
	if instance <= 0:
		return
	var rows: Array = _row_paints.get(instance, [])
	rows.append(paint)
	_row_paints[instance] = rows
	# The frame passes its clicks on, as it always has — it is a highlight, not a
	# button, and the page under it scrolls.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_bind_hover(row, func(): _light_bodies([instance]), func(): _light_bodies([]))


# Hover on a ROW, not on the sliver of it nothing else claimed.
#
# Godot sends mouse_entered to the ONE control under the cursor — a MOUSE_FILTER
# PASS ancestor hears nothing while a STOP child has the pointer. A checklist row
# is a frame containing a full-width CheckBox and a Notes button, both STOP, so
# binding the frame alone left the goal lighting its enemy only from the two or
# three pixels of padding around the box: hover the row anywhere a player would
# actually aim and nothing happened. So every descendant carries the same pair.
#
# The exit is positional rather than a plain "leave one of them": crossing from
# the checkbox to the Notes button fires an exit and an enter in the same frame,
# and treating that as a departure made the highlight flicker along the row. If
# the pointer is still inside the frame, the row was never left.
func _bind_hover(frame: Control, on_enter: Callable, on_exit: Callable) -> void:
	var leave := func() -> void:
		if not is_instance_valid(frame) or not frame.get_global_rect().has_point(
				frame.get_global_mouse_position()):
			on_exit.call()
	for node in _hover_targets(frame):
		if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			# A Label is IGNORE by default and never reports anything; it is also
			# most of a checklist row's width. PASS lets it report the hover while
			# still handing the click to whatever is underneath.
			node.mouse_filter = Control.MOUSE_FILTER_PASS
		node.mouse_entered.connect(on_enter)
		node.mouse_exited.connect(leave)


# `frame` and every Control under it.
func _hover_targets(frame: Control) -> Array:
	var out: Array = [frame]
	for child in frame.get_children():
		if child is Control:
			out.append_array(_hover_targets(child))
	return out

# Light `instances` on the BOARD (and, so the two halves never disagree, the rows
# that belong to them). Passing [] clears.
func _light_bodies(instances: Array) -> void:
	var want: Dictionary = {}
	for inst in instances:
		want[int(inst)] = true
	if want == _lit_instances:
		return
	var touched: Dictionary = _lit_instances.duplicate()
	for inst in want:
		touched[inst] = true
	_lit_instances = want
	for inst in touched:
		for paint in _row_paints.get(inst, []):
			if (paint as Callable).is_valid():
				(paint as Callable).call(_lit_instances.has(inst))
	if _board != null:
		_board.highlight(_lit_instances.keys())

# The other direction: the mouse crossed a body on the board.
func _on_enemy_hovered(instance: int, hovered: bool) -> void:
	_light_bodies([instance] if hovered else [])

# One read-only checklist row: the same frame the tick-box rows use, without the
# box, so the standing list and the report step read as the same list in two
# states. `icon` is the boss portrait, when the row belongs to one (_boss_icon);
# `instance` is the body on the board this goal belongs to, which is what pairs
# the row with the enemy in both directions (_bind_row_to_body).
func _objective_row(text: String, color: Color, icon: Texture2D = null,
		instance: int = 0) -> Control:
	var wrap := PanelContainer.new()
	var idle: StyleBox = UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, 1,
		color.lerp(UITheme.BORDER, 0.35))
	var lit: StyleBox = UITheme.flat(color.lerp(UITheme.BG, 0.78), 5, 4, 2,
		color.lerp(Color.WHITE, 0.35))
	wrap.add_theme_stylebox_override("panel", idle)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	wrap.add_child(line)
	if icon != null:
		line.add_child(_boss_icon_rect(icon))
	var l := Label.new()
	l.text = "•  " + text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(l)
	# Bound last: the hover covers what is IN the row, so the row has to be in it.
	_bind_row_to_body(wrap, instance, func(is_lit: bool) -> void:
		if is_instance_valid(wrap):
			wrap.add_theme_stylebox_override("panel", lit if is_lit else idle))
	return wrap

# A BOSS is the one thing on the checklist that isn't just another line of text:
# it's the difficulty gate the run is standing in front of (§7.1). Its portrait
# rides beside its name in both checklists, so "which of these is the boss" is
# answered by looking rather than by remembering the name.
const BOSS_ICON_SIZE := 26

func _boss_icon(enemy: GoalEnemyData) -> Texture2D:
	if enemy == null or not enemy.is_boss():
		return null
	return enemy.image

func _boss_icon_rect(icon: Texture2D) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 4, 2, 1, Color(0.95, 0.55, 0.2)))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.tooltip_text = "Boss"
	frame.add_child(UITheme.crisp_tex(icon, BOSS_ICON_SIZE))
	return frame

# One checklist row: a bordered CheckBox tinted `color`; `emphasise` gives the
# main-goal row a heavier border so it reads as the primary question. Kept to a
# single tight line each — the stage above it is the board, and the checklist has
# to stay a glanceable list rather than a stack of cards.
# One checklist line. When `enemy` is given the row also carries a Notes button
# on the right, for writing down how this enemy was actually beaten AT this game
# — the note belongs to the pair, and the Atlas surfaces it on the game later.
func _verify_row(text: String, color: Color, emphasise: bool,
		enemy: GoalEnemyData = null, character: CharacterData = null,
		instance: int = 0) -> Dictionary:
	var wrap := PanelContainer.new()
	var border: Color = color.lerp(UITheme.BORDER, 0.35)
	var width: int = 2 if emphasise else 1
	var idle: StyleBox = UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, width, border)
	# The WHOLE ROW answers, not just the box: a ticked row goes green-washed and
	# green-rimmed, so a filled checklist reads at a glance from the board beside
	# it rather than needing each little box squinted at in turn.
	var ticked_box: StyleBox = UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.80), 5, 4,
		maxi(width, 2), UITheme.SUCCESS.lerp(UITheme.BORDER, 0.15))
	# …and a LIT row is the third state: the board beside this list is pointing at
	# the body this goal belongs to (see _bind_row_to_body).
	var lit: StyleBox = UITheme.flat(color.lerp(UITheme.BG, 0.78), 5, 4,
		maxi(width, 2), color.lerp(Color.WHITE, 0.35))
	var ticked := {"on": false}
	var paint := func(is_lit: bool) -> void:
		if not is_instance_valid(wrap):
			return
		if bool(ticked["on"]):
			wrap.add_theme_stylebox_override("panel", ticked_box)
		else:
			wrap.add_theme_stylebox_override("panel", lit if is_lit else idle)
	wrap.add_theme_stylebox_override("panel", idle)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	wrap.add_child(line)
	# A boss's own portrait, right where its name is about to be read.
	var boss_art: Texture2D = _boss_icon(enemy)
	if boss_art != null:
		line.add_child(_boss_icon_rect(boss_art))
	var cb := CheckBox.new()
	cb.text = text
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A level-up clause reads "Use sorrow or self-inflicted pain as a weapon →
	# Gain +1 Small Chest and +1 Scramble", and an unwrapped CheckBox claims every
	# pixel of that as its minimum width — which is what pushed the left column to
	# 772px and put a horizontal scrollbar under the whole page. Wrapped, the row
	# is as tall as it needs and as wide as it is given.
	cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cb.add_theme_font_size_override("font_size", 13)
	cb.add_theme_color_override("font_color", color)
	cb.add_theme_color_override("font_pressed_color", color)
	cb.add_theme_color_override("font_hover_color", UITheme.GOLD)
	cb.toggled.connect(func(on: bool):
		ticked["on"] = on
		paint.call(_lit_instances.has(instance))
		cb.add_theme_color_override("font_color",
			UITheme.SUCCESS.lerp(Color.WHITE, 0.55) if on else color))
	line.add_child(cb)
	var game: GameData = _chosen.get("game")
	if game != null:
		if enemy != null:
			line.add_child(_notes_button(game, enemy))
		elif character != null:
			line.add_child(_levelup_notes_button(game, character))
	# Bound last: the hover covers what is IN the row, so the row has to be in it.
	_bind_row_to_body(wrap, instance, paint)
	return {"row": wrap, "check": cb}

# The per-row Notes button. Shows a filled glyph once something is written, so a
# game you've already annotated reads at a glance.
func _notes_button(game: GameData, enemy: GoalEnemyData) -> Button:
	return _note_button_for(
		"Write down how you beat %s here" % enemy.display_name,
		func(): return GameStats.enemy_note(game.id, enemy.id),
		func(refresh): EnemyNoteModal.open(self, game, enemy, refresh))

# The same button for the level-up row, writing the (game, character) note.
func _levelup_notes_button(game: GameData, character: CharacterData) -> Button:
	return _note_button_for(
		"Write down how you hit %s's level-up here" % character.display_name,
		func(): return GameStats.level_up_note(game.id, character.id),
		func(refresh): EnemyNoteModal.open_level_up(self, game, character, refresh))

# Shared shape for both: `read` answers the current text (so the glyph can say
# whether there is one) and `open` is handed the refresh to call on save.
func _note_button_for(tip: String, read: Callable, open: Callable) -> Button:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 11)
	b.tooltip_text = tip
	var refresh := func():
		var has: bool = String(read.call()).strip_edges() != ""
		b.text = "🗒 Notes ✎" if has else "🗒 Notes"
		b.add_theme_color_override("font_color", UITheme.GOLD if has else UITheme.TEXT_DIM)
	refresh.call()
	b.pressed.connect(func(): open.call(refresh))
	return b

func _verify_head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l

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
	var out: Array = []
	for f in _fulfil_checks:
		if is_instance_valid(f["check"]) and f["check"].button_pressed:
			out.append(f["instance"])
	return out

# The ticked STATUS rows, in the shape beat_game's `claims` wants (§13): the
# player-side rows met this game (the buff goals, and the `demand` rows whose price
# is dodged by answering them), the enemy bonus objectives claimed, and the goals
# cleared the OTHER way.
#
# The `instead` ticks are a separate list all the way through — never folded into
# `_ticked_fulfilments` — because the report records a defeat for every fulfilment
# it is handed, and these are exactly the clears that must leave no record.
#
# Returned even when nothing at all is ticked, unlike before: an EMPTY report is
# the answer a missed `demand` is billed for, and a caller handed {} could not tell
# "nothing was ticked" from "no checklist asked".
func _ticked_status_claims() -> Dictionary:
	var goals: Array = []
	for s in _status_goal_checks:
		if is_instance_valid(s["check"]) and s["check"].button_pressed:
			goals.append(s["status"])
	var bonuses: Array = []
	for b in _bonus_checks:
		if is_instance_valid(b["check"]) and b["check"].button_pressed:
			bonuses.append({"instance": b["instance"], "status": b["status"]})
	var instead: Array = []
	for i in _instead_checks:
		if is_instance_valid(i["check"]) and i["check"].button_pressed:
			instead.append({"instance": i["instance"], "status": i["status"]})
	return {"status_goals": goals, "bonuses": bonuses, "instead": instead}

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
		GameState.player_level += 1
		GameState.apply_level_up_stats(ch.level_up_stats)
		match String(ch.level_up_reward_type):
			"item", "chest":
				# A sized chest (Zagreus' Large -> 3) carries its own choice
				# count; an unsized one passes 0 and takes the screen's default.
				GameState.grant_chest(maxi(1, ch.level_up_reward_amount),
					maxi(0, ch.level_up_reward_chest_choices))
			"random_sized_chest":
				# Vampire Survivors characters: the chest's SIZE is rolled
				# (Data.CHEST_SIZE_CHOICES) instead of fixed — Small..Huge on the
				# same odds as every other rarity draw.
				GameState.grant_chest(maxi(1, ch.level_up_reward_amount), Data.roll_chest_size_choices(_rng))
			"scroll":
				GameState.add_loot("scroll", maxi(1, ch.level_up_reward_amount))
			_:
				pass
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

func _show_preview(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	# A destination card grants no tries — it isn't a game being started (§10).
	_hover_grant = -1 if _asking_return() else GameLoop2.shields_for_game(_choices[index]["game"])
	_preview.text = _hover_line(_choices[index])
	_show_hover_art(_choices[index])

# The portrait beside the hover line: the body this card would put on the board.
#
# Blank for the stay-or-return pair (they spawn nothing), for a free game with no
# enemy, and under the Runic Dome — the relic hides WHAT is waiting, and a picture
# gives that away far more completely than a name would.
func _show_hover_art(choice: Dictionary) -> void:
	if _preview_art == null or not is_instance_valid(_preview_art):
		return
	var tex: Texture2D = null
	if not choice.is_empty() and not choice.has("stay") and not _enemy_hidden(choice):
		tex = _enemy_texture(choice)
	_preview_art.texture = tex
	_preview_art.visible = tex != null

# The mouse left a card: the line stays as a reference, but the grant number and
# the portrait go with the hover, so neither can advertise a game you're not
# pointing at.
func _clear_hover_grant() -> void:
	_show_hover_art({})
	if _hover_grant < 0:
		return
	_hover_grant = -1
	_preview.text = _preview_idle_text()

# What the hover line says with nothing hovered — which is a different sentence
# when the two cards on the table are the ends of a detour rather than games to
# go and play (§10).
func _preview_idle_text() -> String:
	if _phase == Phase.START_SELECT:
		return "[i]Hover a start to see what it opens on.[/i]"
	if _asking_return():
		return "[i]The detour is over. Open either game to see the road from it, then take the one you want to carry on from.[/i]"
	return "[i]Hover a game to see the enemy it would spawn — click it for the route, the goal and the way in.[/i]"

# The enemy's art (§10.1) for a choice, or null when there's no enemy.
func _enemy_texture(choice: Dictionary) -> Texture2D:
	var e: GoalEnemyData = choice.get("enemy")
	return e.image if e != null else null

# Runic Dome (§7.1): whether this card's enemy is hidden. Only ever true for a
# game being OFFERED — the relic buys a column of board with the routing decision,
# not with the game you are standing on, so the moment a game is committed to its
# enemy is on the board and describes itself like any other.
func _enemy_hidden(choice: Dictionary) -> bool:
	if not GameState.hides_upcoming_enemies():
		return false
	if choice.get("enemy") == null:
		return false
	var landed: Dictionary = GameLoop2.arrival()
	return landed.is_empty() or landed.get("enemy") != choice.get("enemy")

# What a hidden card says instead. Named rather than inlined because three
# screens say it (the hover line, the now-playing panel, GameChoiceModal) and
# they must not each invent their own wording for the same blank.
const HIDDEN_ENEMY_TEXT := "something you can't see"

# THE ESCORT (§7.5), said before it exists. The second body is rolled on ARRIVAL,
# so a card cannot name it — but it must not stay quiet about it either: "how many
# bodies does this put on the board" is half of what the routing decision is
# about, and a card that showed one enemy and delivered two would be lying by
# omission. So the card promises the count and withholds the name.
const ESCORT_WARNING := "⚠ One more enemy spawns with it — which one is rolled on arrival."
const ESCORT_WARNING_SHORT := "⚠ +1 more"

# Whether committing to `choice` will put a SECOND body on the board. False for a
# BOSS round — a boss spawns solo, the tier change being step-up enough on its own
# (GameLoop2._spawn_escort) — for a free game with no enemy at all, and for the
# stay-or-return card, which spawns nothing either way.
func _escort_expected(choice: Dictionary) -> bool:
	if choice.is_empty() or choice.has("stay"):
		return false
	if choice.get("enemy") == null or bool(choice.get("boss", false)):
		return false
	return not Data.all_goal_enemies().is_empty()

# The escort's line for a card: a WARNING while the game is still an offer, and
# the body's NAME once the game has been committed to and the roll has happened.
# Empty when this card brings no escort. One function, because the offering, the
# popup and the now-playing panel all have to say the same thing about it.
func _escort_note(choice: Dictionary) -> String:
	var landed: Dictionary = GameLoop2.arrival()
	if not landed.is_empty() and choice.get("enemy") != null \
			and landed.get("enemy") == choice.get("enemy"):
		var escort: GoalEnemyData = GameLoop2.escort_enemy()
		return "" if escort == null else "⚠ %s spawned alongside it." % escort.display_name
	return ESCORT_WARNING if _escort_expected(choice) else ""

# The hover, on ONE line: the enemy this card would put on the board, the goal you
# would be playing for, and the TRIES it hands you. The tries used to be a slot on
# the HUD that previewed on hover; the HUD has gone, and this is the line that was
# already answering "what is that card" — so the number rides here instead of
# being the last thing keeping a panel alive.
func _hover_line(choice: Dictionary) -> String:
	var game: GameData = choice["game"]
	var e: GoalEnemyData = choice.get("enemy")
	if choice.has("stay"):
		return "[b]%s[/b]  ·  [i]%s[/i]" % [game.display_name,
			"stay here and carry on from this game"
			if bool(choice["stay"]) else "head back and carry on from there"]
	var tries: String = "  ·  [color=#%s]◆ %d tries[/color]" % [
		SHIELD_BLUE.to_html(false), _hover_grant] if _hover_grant >= 0 else ""
	if e == null:
		return "[b]%s[/b]  ·  [i]no enemy — free game[/i]%s" % [game.display_name, tries]
	# The escort rides even the hidden line: the Dome hides WHAT is waiting, and how
	# many bodies arrive is not part of what it was bought to hide.
	var escort: String = "  ·  [color=#%s]%s[/color]" % [
		UITheme.DANGER.to_html(false), ESCORT_WARNING_SHORT] if _escort_expected(choice) else ""
	# Under the Runic Dome there is no enemy line to give: the goal is the enemy's,
	# so hiding the name and quoting the goal would give the whole thing away.
	if _enemy_hidden(choice):
		return "[b]%s[/b]  →  [i]%s[/i]%s%s" % [
			game.display_name, HIDDEN_ENEMY_TEXT, escort, tries]
	var kind: String = "[color=#e0b020]☠ [/color]" if choice["boss"] else ""
	return "[b]%s[/b]  →  %s%s  ·  %s%s%s" % [
		game.display_name, kind, e.display_name,
		GameLoop2.goal_text_for(_preview_entry(choice)), escort, tries]

# The board entry to read a `choice`'s goal line off (§13). Once the card has been
# taken, that is the live body it put on the board, statuses and all. For an
# OFFERED card there is no body yet — but the player's own clauses tax every
# enemy's goal, so the preview is built against a bare stand-in rather than
# falling back to the unmodified stem: what a card will actually cost you is part
# of the routing decision, not a surprise waiting on the report step.
func _preview_entry(choice: Dictionary) -> Dictionary:
	var landed: Dictionary = GameLoop2.arrival()
	if not landed.is_empty() and landed.get("enemy") == choice.get("enemy"):
		return landed
	return {"enemy": choice.get("enemy"), "statuses": {}}

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
	_health_chip.text = "♥  %d / %d" % [GameState.hp, GameState.max_hp]
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

# The pack, as a STRIP of small tokens above the board rather than a list of
# named rows beside it. A run ends up carrying a dozen relics and a dozen named
# rows is a column taller than the battlefield; at 34px a whole pack is two rows
# of art. The name, the rarity, what it does and how to fire it all move into the
# tooltip, which is where they were being read from anyway.
#
# An ACTIVE (USABLE / CHARGED) token is the button: clicking it fires the item
# when it can fire, and it wears a gold ring to say so. Passive and triggered
# items are just art. Actives are locked while a game is being reported — the
# report step is mid-resolve, so firing an item there would land between "played
# the game" and "said what happened".
const ITEM_TOKEN := 34
# Height of the Use button / charge battery that sits above an active item's tile.
const ITEM_USE_H := 14

func _refresh_items() -> void:
	if _items_box == null:
		return
	_clear(_items_box)
	var reporting: bool = _phase == Phase.PLAYING
	var scrolls: Array = GameState.loot_scrolls()
	if GameState.inventory.is_empty() and scrolls.is_empty():
		_items_box.add_child(_empty_note("nothing carried yet"))
		return
	for item in GameState.inventory:
		if not (item is ItemData):
			continue
		_items_box.add_child(_item_token(item, reporting))
	# Scrolls ride the same strip. loot_scrolls() preserves pickup order; each is
	# mapped back to its loot_items index so reading one consumes the right entry.
	for entry in scrolls:
		_items_box.add_child(_scroll_token(GameState.loot_items.find(entry), entry, reporting))

# One carried scroll, as a token on the pack strip (§4.1). It is drawn like an
# item's tile and read like an item's Use button — one click, because reading IS
# the only thing a scroll does and there is no card to separate looking from
# spending. Locked while a game is being reported, exactly as an active item is:
# the report step is mid-resolve, and a teleport landing there would fall between
# "played the game" and "said what happened".
func _scroll_token(idx: int, entry: Dictionary, reporting: bool) -> Control:
	var scroll: ScrollData = Data.get_scroll(StringName(entry.get("id", "")))
	var name: String = ScrollSystem.display_name(scroll) if scroll != null else "Scroll"
	var tint: Color = UITheme.ACCENT
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.tooltip_text = "📜 %s\n%s" % [name,
		"Locked while you're reporting a game." if reporting else "Click to read it — this spends the scroll."]

	var read := Button.new()
	read.text = "Read"
	read.disabled = reporting
	read.custom_minimum_size = Vector2(ITEM_TOKEN, ITEM_USE_H)
	read.add_theme_font_size_override("font_size", 9)
	read.tooltip_text = col.tooltip_text
	read.add_theme_stylebox_override("normal", UITheme.flat(tint.lerp(UITheme.BG, 0.55), 3, 0, 1, tint))
	read.add_theme_stylebox_override("hover", UITheme.flat(tint.lerp(UITheme.BG, 0.35), 3, 0, 1, tint))
	read.add_theme_color_override("font_color", UITheme.TEXT)
	read.pressed.connect(func(): read_scroll(idx))
	col.add_child(read)

	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.86), 5, 3, 1, tint.lerp(UITheme.BG, 0.45)))
	tile.tooltip_text = col.tooltip_text
	col.add_child(tile)
	var art := UITheme.crisp_tex(ScrollSystem.art_texture(scroll) if scroll != null else null, ITEM_TOKEN)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(art)
	return col

# One item in the pack: the art tile, with its FIRING control above it when the
# item has one. Reading and spending are deliberately separate gestures — clicking
# the tile opens the item's card (§ItemInfoCard), and only the control above it
# ever spends a charge, so inspecting an item can't cost you one.
#
# A USABLE item gets a plain Use button. A CHARGED item gets a battery: one
# rectangle per charge, filling as it recharges, and at full it becomes the same
# Use button — so the bar answers "how long until I can" and "can I now" in the
# same strip of pixels.
func _item_token(item: ItemData, reporting: bool) -> Control:
	var tint: Color = UITheme.item_color(item)
	var active: bool = item.kind == ItemData.ItemKind.USABLE or item.is_charged()
	var ready: bool = active and GameState.can_fire_item(item) and not reporting

	# Bottom-aligned so every art tile sits on one baseline whether or not the item
	# above it grew a Use button — a ragged row of tiles reads as a bug.
	var col := HoverBox.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	# The whole column answers the hover, not only the art tile — the Use button
	# and the battery override it with their own, so every pixel of an item says
	# something rather than the gap above the tile saying nothing.
	var card: Dictionary = item_hover(item, active, ready, reporting)
	HoverCard.attach(col, card)
	if active:
		col.add_child(_item_fire_control(item, ready, reporting))

	var tile := HoverPanel.new()
	var border: Color = UITheme.GOLD if ready else tint.lerp(UITheme.BG, 0.45)
	tile.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.86), 5, 3, 2 if ready else 1, border))
	HoverCard.attach(tile, card)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	col.add_child(tile)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(ITEM_TOKEN, ITEM_TOKEN)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(stack)
	var art := UITheme.crisp_tex(item.image, ITEM_TOKEN)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(art)
	var badge: Control = _counter_badge(item)
	if badge != null:
		stack.add_child(badge)

	var target_item: ItemData = item
	tile.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			open_item_card(target_item))
	return col

# An INCREMENTAL relic's counter, drawn in the bottom-right corner of its own art
# — Slay the Spire's relic counters, in the same corner and for the same reason:
# the number belongs to the picture of the thing, so a row of relics can be read
# in one glance without any of them growing a caption.
#
# Just the number it is ON, not "2/3". The threshold is what the item's text says
# and does not change; the count is the only part that moves, and a fraction
# doubles the pixels to say the same thing. Returns null for everything that is
# not incremental, which is almost every item.
#
# Public in spirit — the drop modal and the shop shelf draw the same tiles — but
# they show TEMPLATES, whose counter is always 0, so only the pack calls it.
func _counter_badge(item: ItemData) -> Control:
	var spec: Dictionary = item.incremental_spec()
	if spec.is_empty():
		return null
	var count: int = maxi(0, item.counter_value)
	var wrap := PanelContainer.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Its own dark plate rather than bare text on the art: item art is 852 games'
	# worth of colours and a naked glyph is illegible over half of them.
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.06, 0.06, 0.09, 0.88), 3, 3, 1, UITheme.GOLD))
	var label := Label.new()
	label.text = str(count)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UITheme.GOLD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(label)
	return wrap

# The control above an active item's tile. Full charge (or a Usable item, which
# has none) reads "Use" and fires; a partial charge is the battery, showing how
# many beats are left before it does.
func _item_fire_control(item: ItemData, ready: bool, reporting: bool) -> Control:
	if ready:
		var btn := Button.new()
		btn.text = "Use"
		btn.custom_minimum_size = Vector2(ITEM_TOKEN + 6, ITEM_USE_H)
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_stylebox_override("normal",
			UITheme.flat(Color(0.10, 0.22, 0.16, 0.95), 4, 1, 1, Color(0.4, 0.9, 0.6)))
		btn.add_theme_stylebox_override("hover",
			UITheme.flat(Color(0.14, 0.30, 0.21, 1.0), 4, 1, 1, Color(0.55, 1.0, 0.75)))
		btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = "Use %s" % item.display_name
		var target_item: ItemData = item
		btn.pressed.connect(func(): use_item(target_item))
		return btn
	if item.is_charged():
		return _charge_battery(item, reporting)
	# A Usable item that can't fire right now (mid-report) — the slot stays, greyed,
	# so the row doesn't reflow the moment a game is picked up.
	var idle := Button.new()
	idle.text = "Use"
	idle.disabled = true
	idle.custom_minimum_size = Vector2(ITEM_TOKEN + 6, ITEM_USE_H)
	idle.add_theme_font_size_override("font_size", 10)
	idle.tooltip_text = "Finish reporting this game first."
	return idle

# A charged item's meter: one rectangle per charge, filled left to right. Isaac's
# active-item bar turned on its side — the shape answers "how many beats left"
# without reading a number, and it sits where the Use button will be so the swap
# at full charge is the same strip changing state rather than a new control.
func _charge_battery(item: ItemData, reporting: bool) -> Control:
	var maxc: int = maxi(1, item.max_charge())
	var have: int = clampi(item.current_charge, 0, maxc)
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(ITEM_TOKEN + 6, ITEM_USE_H)
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.10, 0.10, 0.13, 0.9), 2, 2, 1, UITheme.BORDER))
	wrap.tooltip_text = "%s — %d/%d charged%s" % [item.display_name, have, maxc,
		"; finish reporting this game to use it" if reporting else ""]
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 1)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(cells)
	for i in range(maxc):
		var seg := PanelContainer.new()
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.custom_minimum_size = Vector2(3, ITEM_USE_H - 6)
		var filled: bool = i < have
		seg.add_theme_stylebox_override("panel", UITheme.flat(
			UITheme.GOLD.lerp(UITheme.BG, 0.15) if filled else Color(0.18, 0.18, 0.22, 0.9),
			1, 0, 0))
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cells.add_child(seg)
	return wrap

# Open the reading card for one item. Firing from the card routes through the same
# use_item the token's button does, so there is one spend path.
func open_item_card(item: ItemData) -> void:
	if item == null:
		return
	_close_item_card()
	var active: bool = item.kind == ItemData.ItemKind.USABLE or item.is_charged()
	var usable: bool = active and GameState.can_fire_item(item) and _phase != Phase.PLAYING
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

# Everything the old named row said, in the tooltip the token carries.
# The hover model for a carried item: the condensed version of the card its click
# opens (ItemInfoCard). Its art, its name in its class colour, what it does, and
# — for an active item — whether it can be fired right now, which is the one fact
# about a relic that changes what you do in the next second.
#
# Public, and named for the thing rather than for the tooltip, because the shop's
# shelf and the drop modal describe the same items and should come through here.
func item_hover(item: ItemData, active: bool, ready: bool, reporting: bool) -> Dictionary:
	var sub: String = UITheme.item_class_name(item)
	if item.is_charged():
		sub += "  ·  %d/%d charged" % [item.current_charge, item.max_charge()]
	var counter: Dictionary = item.incremental_spec()
	if not counter.is_empty():
		sub += "  ·  %d/%d" % [item.counter_value, int(counter["every"])]
	var note: String = ""
	if active:
		if ready:
			note = "▸ Click the tile above to use it."
		elif reporting:
			note = "▸ Report this game first."
		elif item.is_charged():
			note = "▸ Charging."
	return {
		"title": item.display_name,
		"subtitle": sub,
		"accent": UITheme.item_color(item),
		"art": item.image,
		"lines": [String(item.description)],
		"note": note,
	}

# The dim "there's nothing here" line the pack panels show when they're empty.
func _empty_note(text: String) -> Label:
	var l := Label.new()
	l.text = "  (%s)" % text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	return l

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
	var dmg: int = GameLoop2.stacked_damage_per_game()
	var swings: int = 0
	for entry in GameLoop2.stack:
		swings += GameLoop2.attacks_next_game(entry)
	return "%d closing in, %d swing%s landing for %d damage next game" % [
		following, swings, "" if swings == 1 else "s", dmg]


# --- kill-drops (§8) -------------------------------------------------------

# A defeated enemy dropped loot: roll the chest it left and queue it. The queue is
# drained one ItemDropModal at a time (_pump_drops) — the kill ASKS whether you
# want what fell off it, rather than leaving it in a tray to be noticed. Skipped
# once the run is over (win/lose screens take over the board).
#
# ONE ITEM OFF A BODY IS A CHEST — a Small one, "choose 1 of 1" (§8.2). Saying it
# that way is what lets There's Options exist without a second reward path: the
# relic buys chest POINTS on a boss's drop, those points are spent on the same
# size ladder a [chest reward] walks (Data.chest_reward_sizes), and a Medium chest
# is the same modal offering two. A body that isn't a boss always drops the Small
# one, so the common case is untouched — same single item, same two buttons.
func _on_enemy_defeated(enemy: GoalEnemyData) -> void:
	if GameLoop2.run_over:
		return
	var from_boss: bool = enemy != null and enemy.is_boss()
	var points: int = 1 + (GameState.boss_chest_bonus() if from_boss else 0)
	var queued: bool = false
	# Points past a Huge overflow into a SECOND chest rather than off the end of
	# the ladder, which is the whole reason to spend them through Data — so a
	# stack of There's Options keeps paying, one more question at a time.
	for size in Data.chest_reward_sizes(points):
		var offer: Array = _roll_chest(from_boss, int(Data.CHEST_SIZE_CHOICES[size]))
		if offer.is_empty():
			continue
		_drop_queue.append({"items": offer})
		queued = true
	if queued:
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
	_open_next_drop.call_deferred()

func _open_next_drop() -> void:
	if _drop_modal != null and is_instance_valid(_drop_modal):
		return
	if _drop_queue.is_empty() or not is_inside_tree():
		return
	if _phase == Phase.OVER or GameLoop2.run_over:
		return
	var drop: Dictionary = _drop_queue[0]
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
	var item: ItemData = chosen if chosen != null and offered.has(chosen) \
		else (offered[0] if not offered.is_empty() else null)
	if item == null:
		return
	GameState.add_item(item)
	GameLog.add("Collected %s." % item.display_name, Color(0.7, 1.0, 0.7))
	Notifications.notify("Took %s." % item.display_name, UITheme.item_color(item))

func _skip_drop(drop: Dictionary) -> void:
	if not _drop_queue.has(drop):
		return
	_drop_queue.erase(drop)
	var names: Array = []
	for it in _drop_items(drop):
		names.append(String((it as ItemData).display_name))
	if not names.is_empty():
		GameLog.add("Left %s behind." % ", ".join(names), Color(0.8, 0.8, 0.8))


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
		parts.append("%d shield(s) expired with the game" % int(res["shields_expired"]))
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
	# covers being drawn half-size (COVER_SIZE).
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
	# So the art is back, BESIDE the line and sized BY it (see HOVER_ART): the row
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
	_preview_art.custom_minimum_size = Vector2(HOVER_ART, 0)
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
	_inv_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 8, 1))
	_inv_wrap.size_flags_horizontal = Control.SIZE_FILL
	var inv_box := VBoxContainer.new()
	inv_box.add_theme_constant_override("separation", 4)
	_inv_wrap.add_child(inv_box)
	# NO HEADING. It used to carry a "🎒  Inventory" line, and a strip of relics
	# and scrolls in a bordered panel does not need to be told what it is — the
	# tokens are the label. That row is also the page's whole margin: the overworld
	# is fitted to a 720p window and, with the heading on, the pack panel alone put
	# it a pixel OVER (626 of 625) before a shop was even mounted under the board.
	#
	# ONE strip, relics and scrolls together. A scroll is a thing you are carrying
	# and spend, exactly like a Usable relic is, and it used to get a whole second
	# titled panel of its own — first at the foot of the page under the log, then
	# as a second heading in here. As tokens on the same row they cost the pack
	# nothing but the tiles themselves.
	_items_box = HFlowContainer.new()
	_items_box.add_theme_constant_override("h_separation", 4)
	_items_box.add_theme_constant_override("v_separation", 4)
	inv_box.add_child(_items_box)
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
	_now_playing_cover.custom_minimum_size = COVER_SIZE * 0.72
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
	_attempt_btn.text = "Lost a run  −1"
	_attempt_btn.tooltip_text = "Tick every run of this game you lose."
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

# Repaint the attempt strip: the count, the pips (filled = shields still standing,
# hollow = tries already spent on one), and what the next lost run will cost.
func _refresh_attempts() -> void:
	if _attempt_count == null:
		return
	var attempts: int = GameLoop2.attempts()
	var spent: int = GameLoop2.attempts_on_shields()
	var left: int = GameState.shields
	_attempt_count.text = "Attempts  %d" % attempts
	_attempt_count.add_theme_color_override("font_color",
		UITheme.TEXT if attempts == 0 else UITheme.ACCENT)
	_attempt_pips.text = "◆".repeat(left) + "◇".repeat(spent)
	_attempt_pips.tooltip_text = "%d shield(s) left of the %d this game granted." % [left, left + spent]
	if left > 0:
		_attempt_hint.text = "Shields %d — the next lost run spends one." % left
		_attempt_hint.add_theme_color_override("font_color", SHIELD_BLUE)
	else:
		_attempt_hint.text = "No shields left — the next lost run costs %d Health." % GameLoop2.ATTEMPT_HEALTH_COST
		_attempt_hint.add_theme_color_override("font_color", UITheme.DANGER)
	var live: bool = _phase == Phase.PLAYING and not GameLoop2.run_over
	_attempt_btn.disabled = not live
	_attempt_undo.disabled = not live or attempts == 0
	# The escape hatch is up from the first second on a game the player has been
	# through before, and otherwise only once they have lost enough runs to have
	# earned it — where it goes away again if they undo back under the line. The
	# tooltip says WHICH rule is holding the door open, because "why can I leave
	# this one and not that one" is the whole question the button raises.
	if _escape_btn != null:
		_escape_btn.visible = can_escape()
		var why: String = ("You already beat this one this run, so there is nothing to prove — leave whenever you like."
			if beaten_this_run()
			else "%d lost runs is enough." % GameLoop2.attempts())
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
