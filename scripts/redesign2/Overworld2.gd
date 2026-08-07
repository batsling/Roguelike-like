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
# new tier, the offering becomes a BOSS round — a "⚠ BOSS INCOMING" banner shows
# above the choices and whichever game you pick spawns a boss (bosses are
# unskippable: no bash/transmute on a boss round).

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

# Shields — the tries at the game in play (§3). One steel-blue used by the HUD
# count, the attempt strip, and the pips on the board.
const SHIELD_BLUE := Color(0.62, 0.78, 0.95)

# Lost runs of the game in play before the Escape button appears (see
# can_escape). Five is past the shields any game grants, so reaching it means the
# player has been paying Health to keep trying.
const ESCAPE_AFTER_ATTEMPTS := 5

# The current offering. Each entry:
#   {"game": GameData, "enemy": GoalEnemyData, "boss": bool, "amulet": bool,
#    "repeat": bool}
# The enemy is rolled up-front so the hover preview and the enemy that actually
# spawns on click are the SAME roll. `repeat` marks a game already beaten this
# run — beating it again grants a Dash (REPEAT_BEAT_DASH).
var _choices: Array = []
# The opening choose-your-start offering (Phase.START_SELECT). Each entry:
#   {"game": GameData, "type": int, "path_len": int, "in_window": bool}
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
var _run_over_won: bool = false
var _run_over_screen: RunOverScreen = null
var _rng := RandomNumberGenerator.new()

# --- UI nodes (built in code) --------------------------------------------
var _hud: RichTextLabel
var _banner: Label
var _boss_banner: Label
var _preview: RichTextLabel
var _preview_img: TextureRect
var _choices_row: HFlowContainer
var _play_panel: VBoxContainer
var _now_playing: RichTextLabel
var _now_playing_img: TextureRect   # the goal-enemy art on the report panel
var _now_playing_cover: TextureRect # the chosen game's cover, beside it
var _launch_row: HBoxContainer
var _verify_box: VBoxContainer      # clean checklist: goal + level-up + follower goals
var _fulfil_checks: Array = []      # [{check: CheckBox, instance: int}]
var _goal_check: CheckBox           # the chosen game's main goal; null on a free game
var _levelup_check: CheckBox        # null when the character has no level-up
var _dash_mode: bool = false        # Dash (§4): offer ANY connected game
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
var _board_head: VBoxContainer       # the board's heading + summary line
var _inv_wrap: PanelContainer        # the carried items, in a strip above the board
var _scrolls_wrap: VBoxContainer
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
var _np_box: HBoxContainer
var _attempt_wrap: Control
var _done_btn: Button
# The board itself (§grid): the player on the left, a grid_cols() x grid_rows() grid on
# the right where enemies close in one column per game beaten (MMBN-style). It's a
# BattlefieldView — a view over GameLoop2 that reports Push / Bomb / inspect back
# here, since this screen owns the charges and the run.
var _board: BattlefieldView
var _info_popup: EnemyInfoCard      # the click-to-inspect enemy card (null when closed)
var _log: RichTextLabel
var _scrolls_box: VBoxContainer
# The pack strip above the grid: one small token per carried item (§4/§8).
var _items_box: HFlowContainer
# Drops a defeated enemy left, waiting to be ASKED about — one ItemDropModal at a
# time, in the order they fell (§8, _pump_drops). The modal in front of the
# player right now, or null when nothing is being asked.
var _drop_queue: Array = []         # [{item: ItemData}]
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
	if not GameState.stats_changed.is_connected(_refresh_hud):
		GameState.stats_changed.connect(_refresh_hud)
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
		})
	return out

# Take the offered start at `index` (choose-your-start, Phase.START_SELECT): the
# player lands on that game and its neighbours become the first offering. No enemy
# spawns and no shields are granted — the start is where you BEGIN, not a game you
# were sent to beat; the run's first pick is the first game you play.
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
	_start_options.clear()
	_phase = Phase.SELECT
	_build_choices()
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
		starts.append({
			"game": String(sg.id), "type": int(opt["type"]),
			"path_len": int(opt["path_len"]), "in_window": bool(opt.get("in_window", true)),
		})
	var choices: Array = []
	for c in _choices:
		choices.append(_serialize_choice(c))
	var visits: Dictionary = {}
	for gid in _visits.keys():
		visits[String(gid)] = int(_visits[gid])
	var drops: Array = []
	for d in _drop_queue:
		drops.append(String((d["item"] as ItemData).id))
	return {
		"phase": _phase,
		"start_options": starts,
		"choices": choices,
		"chosen": _serialize_choice(_chosen),
		"boss_round": _boss_round,
		"dash_mode": _dash_mode,
		"scramble_salt": _scramble_salt,
		"visits": visits,
		"drops": drops,
		"last_played_game": String(_last_played_game.id) if _last_played_game != null else "",
	}

func restore_view_state(view: Dictionary) -> void:
	_start_options.clear()
	for s in view.get("start_options", []):
		var sg: GameData = Data.get_game(StringName(s.get("game", "")))
		if sg != null:
			_start_options.append({
				"game": sg, "type": int(s.get("type", sg.type)),
				"path_len": int(s.get("path_len", 0)),
				"in_window": bool(s.get("in_window", true)),
			})
	_choices.clear()
	for c in view.get("choices", []):
		var restored: Dictionary = _deserialize_choice(c)
		if not restored.is_empty():
			_choices.append(restored)
	_chosen = _deserialize_choice(view.get("chosen", {}))
	_boss_round = bool(view.get("boss_round", false))
	_dash_mode = bool(view.get("dash_mode", false))
	_scramble_salt = int(view.get("scramble_salt", 0))
	_visits.clear()
	var vs: Dictionary = view.get("visits", {})
	for gid in vs.keys():
		_visits[StringName(gid)] = int(vs[gid])
	_drop_queue.clear()
	for iid in view.get("drops", []):
		var it: ItemData = Data.get_item2(StringName(iid))
		if it == null:
			it = Data.get_item(StringName(iid))
		if it != null:
			_drop_queue.append({"item": it})
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
func prompt_save() -> void:
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
		save_run(edit.text)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(440, 190))
	edit.grab_focus()
	edit.select_all()

# Travel to the offered game at `index`: its goal-enemy spawns and we move there.
func pick(index: int) -> void:
	if _phase != Phase.SELECT or index < 0 or index >= _choices.size():
		return
	_chosen = _choices[index]
	# A Dash pick spends a charge (§4) — it's the "select any connected game" verb.
	if _dash_mode:
		GameState.dash_charges = maxi(0, GameState.dash_charges - 1)
		_dash_mode = false
	GameLoop2.choose_game(_chosen["enemy"])
	# Selecting the game hands over your TRIES at it (§3): 3 shields, 5 for a
	# Traditional roguelike, plus whatever "when a game is selected" items add.
	var granted: int = GameLoop2.grant_selection_shields(_chosen["game"])
	GameLog.add("%s — %d shields to spend on tries." % [_chosen["game"].display_name, granted],
		SHIELD_BLUE)
	# Move to the graph SLOT (a transmuted card plays an off-graph game but keeps
	# its position on the route toward the amulet).
	GameState.set_current_game(_chosen["slot"])
	_hover_grant = -1
	_phase = Phase.PLAYING
	_populate_play_panel()
	_refresh()
	# The board is the hero of the playing screen, so land on it: the page stays at
	# the top and the checklist under the grid is a scroll away.
	_scroll_to_top()
	# Committing to a game is a move worth recovering to — the shields it granted
	# and the tries you're about to log all hang off it.
	autosave()

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
# the way. After ESCAPE_AFTER_ATTEMPTS lost runs the player may walk away from the
# game in play at any point, without beating it.
#
# Escaping resolves the game exactly as reporting a missed goal does: the
# goal-enemy walks onto the board and follows you. That IS the price, and by the
# time it's offered it has already been paid twice over — five lost runs is the
# shields this game granted plus Health on top, with the front line closing in the
# whole time. The button exists to make the way out VISIBLE to a stuck player, not
# to discount it.
func can_escape() -> bool:
	return _phase == Phase.PLAYING and not _chosen.is_empty() \
		and not GameLoop2.run_over and GameLoop2.attempts() >= ESCAPE_AFTER_ATTEMPTS

# Leave the game in play. Whatever else the checklist has ticked still stands —
# a follower's goal you did clear, a level-up you did earn — because those are
# separate honour-system claims; escaping only answers the main goal, and it
# answers no.
func escape_game() -> void:
	if not can_escape():
		return
	var game: GameData = _chosen.get("game")
	var game_name: String = game.display_name if game != null else "this game"
	var msg: String = "Escaped %s after %d lost runs — its enemy comes with you." % [
		game_name, GameLoop2.attempts()]
	GameLog.add(msg, UITheme.ACCENT)
	Notifications.notify(msg, UITheme.ACCENT)
	report(false)

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
# From the START PICKER the destination is drawn without being named, and no
# chart is raised: the panel gives away the distance to the Amulet and nothing
# else, and a sky with the route drawn across it would point straight at the game
# the whole run is a search for.
func preview_map(game_id: StringName) -> Node:
	if game_id == &"" or GameState.amulet_game_id == &"":
		return null
	var game: GameData = Data.get_game(game_id)
	var starting: bool = _phase == Phase.START_SELECT
	return _open_route_map(game_id, [], {
		"preview": true,
		"hide_amulet": starting,
		"chart": not starting,
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
# self-report). `goal_met` resolves the current enemy; `fulfilled` is the list of
# FOLLOWING-enemy instances whose old goals you also fulfilled this game (§2) —
# each is defeated and drops. When null the ticked fulfilment checkboxes are read
# from the play panel. Resolves the loop, advances the difficulty clock, then
# rebuilds the next offering.
func report(goal_met: bool, fulfilled: Variant = null) -> void:
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
	# Was this game already cleared this run? Read BEFORE the beat is recorded, so
	# the second clear of a game is what pays the Dash (REPEAT_BEAT_DASH).
	var repeat_beat: bool = played_game != null and GameState.has_beaten_game(played_game.id)
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
	var res: Dictionary = GameLoop2.beat_game(goal_met, fulfilled_instances)
	# "After beating a game" is the dominant 2.0 item trigger (§8): fire it now so
	# owned items react (Burning Blood +1 Health, Meat on the Bone's conditional
	# heal), the Harvesting stat pays out, charged actives tick, and the toast
	# shows. Defeated-enemy drops were already banked by beat_game above.
	# Remember WHICH enemies fell at this game, so the Atlas can list them later
	# alongside whatever the player wrote about them.
	# Every defeat is banked twice: against the GAME it happened at (the Atlas's
	# "enemies beaten in <game>") and against the CHARACTER who did it (the
	# roster's trophy shelf). One call site, so the two can't disagree.
	if played_game != null:
		var goal_enemy: GoalEnemyData = _chosen.get("enemy")
		if goal_met and goal_enemy != null:
			_record_defeat(played_game, goal_enemy)
		for inst in fulfilled_instances:
			for entry in GameLoop2.stack:
				if int(entry.get("instance", -1)) == int(inst):
					var follower: GoalEnemyData = entry["enemy"]
					if follower != null:
						_record_defeat(played_game, follower)
					break
	if played_game != null:
		TriggerBus.game_beaten.emit({"game_id": played_game.id})
		# Bank the clear (and pay the repeat-beat Dash). Recorded after the item
		# trigger so a game_beaten item can't see a half-updated tally.
		GameState.note_game_beaten(played_game.id)
		if repeat_beat:
			_grant_repeat_dash(played_game)
		# Lifetime tally the Collection and the tier list read ("beaten N times"):
		# in the games-first loop this report step IS the verification, so a
		# confirmed game counts here. An amulet clear records the win instead (it
		# bumps `beaten` too).
		if was_amulet and goal_met:
			GameStats.record_amulet_win(played_game.id)
		else:
			GameStats.record_beaten(played_game.id)
	# Level up (§3.1) — a fresh chance each game; skipped if the game just killed
	# the player.
	if leveled and not GameLoop2.run_over:
		_apply_level_up()
		# Which game the level was taken at, so the character's page can list it
		# beside whatever the player wrote about doing it here.
		if played_game != null:
			GameStats.record_level_up(played_game.id, GameState.character_id)
	GameState.games_played += 1
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
	if was_amulet and goal_met:
		# Winning on the Amulet ends the run through GameLoop2 (-> _on_run_won),
		# and the last advance still deserves to be seen before the win screen.
		GameLoop2.clear_amulet()
		_hold_for_resolve(_board.animate_resolve(before, res, hp_before))
		return
	_phase = Phase.SELECT
	_build_choices()
	_refresh()
	# The run moved, so the recovery point moves with it.
	autosave()
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
	if _run_over_pending:
		_run_over_pending = false
		_show_run_over()

# The reward for beating a game you'd already cleared this run: +1 Dash (§4).
# Announced on both channels — the toast for the moment, the log for the record —
# because the HUD's Dash counter moving on its own reads as a bug.
func _grant_repeat_dash(game: GameData) -> void:
	GameState.dash_charges += REPEAT_BEAT_DASH
	var msg: String = "Beat %s again — +%d Dash." % [game.display_name, REPEAT_BEAT_DASH]
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
	_board.clear_fx()
	_close_enemy_info()
	if TriggerBus.chest_granted.is_connected(_on_chest_granted):
		TriggerBus.chest_granted.disconnect(_on_chest_granted)
	if GameState.inventory_changed.is_connected(_on_inventory_changed):
		GameState.inventory_changed.disconnect(_on_inventory_changed)
	if GameState.hp_changed.is_connected(_on_vitals_changed):
		GameState.hp_changed.disconnect(_on_vitals_changed)
	if GameState.stats_changed.is_connected(_refresh_hud):
		GameState.stats_changed.disconnect(_refresh_hud)
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
	var choices: int = GameState.take_pending_chest()   # -1 none / 0 default / N fixed
	_reward_open = true
	var screen := preload("res://scripts/ui/RewardScreen.gd").new()
	screen.closed.connect(func():
		_reward_open = false
		_redeem_pending_chests())
	add_child(screen)
	screen.setup_chest(maxi(0, choices))

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
	GameState.set_current_game(dest)
	var g: GameData = Data.get_game(dest)
	GameLog.add("Rode the bus to %s." % (g.display_name if g != null else String(dest)),
		Color(0.5, 0.85, 1.0))
	_phase = Phase.SELECT
	_dash_mode = false
	_build_choices()
	_refresh()

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

# Push a following enemy back one space (Manager's verb, §7.2): spend a Push
# charge to delay its next attack by a game. Targets a stacked follower by
# instance; GameLoop2.push guards the charge and membership, so a no-op just
# leaves the board unchanged.
func push_follower(instance: int) -> void:
	if GameLoop2.push(instance):
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
func _show_enemy_info(entry: Dictionary, col: int, is_current: bool) -> void:
	_close_enemy_info()
	var card := EnemyInfoCard.new()
	card.push_requested.connect(push_follower)
	card.bomb_requested.connect(bomb_follower)
	card.closed.connect(func(): _info_popup = null)
	_info_popup = card
	add_child(card)
	card.setup(entry, col, is_current)

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
	if _dash_mode:
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
			"repeat": GameState.has_beaten_game(game.id),
		})

# --- rendering ------------------------------------------------------------

# Repaint just the HUD line. Its own function because the run resources move
# outside a loop resolve too — an item taken from a kill-drop or a chest
# changes Health / Max Health / a verb count the instant it lands, and the numbers
# on screen have to agree immediately.
func _refresh_hud(_a = null) -> void:
	if _hud == null:
		return
	_hud.text = _hud_text()

func _on_vitals_changed(_hp: int = 0, _max_hp: int = 0) -> void:
	_refresh_hud()

# A pickup changed the pack: relist the inventory AND repaint the HUD, since the
# item's stat bonuses / item_acquired effects have already landed on the run.
func _on_inventory_changed() -> void:
	_refresh_items()
	_refresh_hud()

func _refresh(_a = null) -> void:
	if _hud == null:
		return
	_refresh_hud()
	_refresh_scrolls()
	_refresh_items()
	_stack.text = "[b]Battlefield[/b]  —  " + _stack_summary()
	_board.refresh(_phase == Phase.PLAYING)
	_refresh_attempts()
	_refresh_stage()
	if not GameLoop2.last_result.is_empty():
		_log.text = _result_text(GameLoop2.last_result)
	_boss_banner.get_parent().visible = _boss_round and _phase == Phase.SELECT
	if _phase == Phase.START_SELECT:
		_select_head.text = "Choose where to start — three genres, all the same distance from the Amulet:"
		_clear(_controls_row)
		_render_start_choices()
		_populate_standing_checklist()
	elif _phase == Phase.SELECT:
		_select_head.text = "Choose a game to travel to:"
		_render_controls()
		_render_choices()
		# The standing goals change with the stack (a bomb, a fulfilment, a scroll),
		# so they're rebuilt with the rest of the screen. Safe here because nothing
		# in this list is a tick box holding player input — that only exists in the
		# report step, which _refresh deliberately doesn't touch.
		_populate_standing_checklist()
	elif _phase == Phase.PLAYING:
		_now_playing.text = _now_playing_text()
		var np_tex: Texture2D = null if _chosen.is_empty() else _enemy_texture(_chosen)
		_now_playing_img.texture = np_tex
		UITheme.apply_crisp(_now_playing_img, np_tex)
		# The cover of the game you're actually playing, so the report step shows the
		# thing you went to play next to the enemy you went to beat.
		var game: GameData = _chosen.get("game")
		_now_playing_cover.texture = game.cover_image if game != null else null

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
	_scrolls_wrap.visible = _phase == Phase.SELECT
	_play_panel.visible = _phase != Phase.OVER or _resolving
	_report_panel.visible = _phase != Phase.OVER or _resolving
	# The report-only parts of the panel: without a game in hand there is nothing to
	# launch, retry or complete.
	var playing: bool = _phase == Phase.PLAYING
	_np_box.visible = playing
	_attempt_wrap.visible = playing
	_done_btn.visible = playing

func _render_controls() -> void:
	_clear(_controls_row)
	if _dash_mode:
		var hint := Label.new()
		hint.text = "⚡ Dash — pick ANY connected game:"
		hint.add_theme_color_override("font_color", DASH_BLUE)
		_controls_row.add_child(hint)
		_controls_row.add_child(_mini_button("Cancel", cancel_dash))
	elif GameState.dash_charges > 0:
		var b := Button.new()
		b.text = "⚡ Dash — pick any connected (%d)" % GameState.dash_charges
		b.pressed.connect(dash)
		_controls_row.add_child(b)
	if not _dash_mode and GameState.scramble > 0:
		var s := Button.new()
		s.text = "🎲 Scramble — reroll the %d choices (%d)" % [_choices.size(), GameState.scramble]
		s.tooltip_text = "Draws new games into the slots, each with a fresh goal-enemy."
		s.pressed.connect(scramble)
		_controls_row.add_child(s)
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
	_preview.text = "[i]Hover a start to see what it opens on.[/i]"
	_preview_img.texture = null

# One start card: the cover, the game's name, its genre, and how many games stand
# between it and the amulet. The amulet itself stays hidden — the distance is the
# only thing about it the panel gives away.
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
	btn.pressed.connect(func(): choose_start(index))
	btn.mouse_entered.connect(func(): _show_start_preview(index))
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
	dist.text = "%d games from the Amulet" % int(opt["path_len"])
	dist.tooltip_text = "The shortest route from %s to the hidden Amulet game." % game.display_name
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
	var game: GameData = opt["game"]
	_preview.text = "[b]%s[/b]  —  %s\n%d games from the Amulet.  [i]You start here; the run's first game is whatever you travel to from it.[/i]" % [
		game.display_name, RunGraph.type_label(int(opt["type"])), int(opt["path_len"])]
	_preview_img.texture = null

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
	_preview.text = "[i]Hover a game to see the enemy it would spawn.[/i]"
	_preview_img.texture = null

# The offered cover art. Still box art rather than a thumbnail — the covers ship
# at 3:4 (528x704 / 300x450), so a 3:4 frame fills edge to edge with nothing
# letterboxed — but at HALF the size it was drawn at when the offering had the
# full width of the page to itself. It now shares a column with the checklist,
# beside the board, and that is the trade: the cards are smaller, and the game
# you are choosing between and the enemies closing in on you are finally on
# screen at the same time. A wider offering (the game_choices bonus) wraps in
# the HFlowContainer.
const COVER_SIZE := Vector2(105, 140)

# The badge rows stacked above and below each cover (route, pace, repeat bonus,
# name). Every one of them is pinned to a whole number of lines at this font, so
# the covers in a row start and end at the same y whatever their text wraps to.
const BADGE_FONT := 11
const BADGE_LINE := 15               # one line of BADGE_FONT, in px
const ROUTE_LINES := 3               # "🏆 THE AMULET — the run ends here" at this width
const PACE_LINES := 2                # "⏱ Enemies speed up — ×2 turns"
# The game's NAME keeps a readable size rather than dropping to BADGE_FONT, so it
# gets its own two-line box — a card whose title wraps must not push its tries
# row below its neighbours'.
const NAME_FONT := 13
const NAME_BOX_H := 51               # three lines of NAME_FONT — "Shotgun King:
                                     # The Final Checkmate" needs all three

# One choice = the game's cover art with its name below, plus (off a boss round)
# small Bash/Transmute verbs when the player has charges. Hover updates the
# shared enemy preview.
func _make_choice_card(index: int, choice: Dictionary) -> Control:
	var game: GameData = choice["game"]
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	card.custom_minimum_size = Vector2(COVER_SIZE.x + 10, 0)

	var accent: Color = UITheme.DANGER if choice["boss"] else (UITheme.GOLD if choice["amulet"] else UITheme.type_color(int(game.type)))

	# WHAT THIS CARD IS, as a route — the first thing on it, above the art: the
	# Amulet game itself, a step along a shortest path, or ground given away. The
	# offering is a routing decision and it shouldn't have to be reverse-engineered
	# from the map every time.
	var note: Dictionary = route_note(choice)
	var route := Label.new()
	route.text = String(note["text"])
	route.tooltip_text = String(note["tip"])
	route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Pinned to ROUTE_LINES tall, not left to grow: at half width these badges wrap
	# to a different number of lines per card ("OPTIMAL — 4 steps left" against
	# "Detour +1 — 6 steps left"), and a header that is a line taller on one card
	# pushes that card's cover out of line with the rest of the row.
	route.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE * ROUTE_LINES)
	route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	route.add_theme_font_size_override("font_size", BADGE_FONT)
	route.add_theme_color_override("font_color", note["color"])
	card.add_child(route)

	# …and what that ground costs in PACE (§7.4). Mounted on every card, blank on
	# the Amulet's, so one card carrying a warning doesn't shove its cover out of
	# line with the rest of the offering.
	var pace: Dictionary = turn_note(choice)
	var pace_lbl := Label.new()
	pace_lbl.text = String(pace["text"])
	pace_lbl.tooltip_text = String(pace["tip"])
	pace_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pace_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pace_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE * PACE_LINES)
	pace_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pace_lbl.add_theme_font_size_override("font_size", BADGE_FONT)
	pace_lbl.add_theme_color_override("font_color", pace["color"])
	card.add_child(pace_lbl)

	# …and the map that backs the claim up: the whole optimal road from this game
	# to the Amulet, without having to take it first.
	card.add_child(_map_preview_button(choice["slot"], game))

	# A game already beaten this run pays a Dash for beating it again — called out
	# ABOVE the cover so the bonus is visible while you're still choosing. The row is
	# mounted on EVERY card (blank when there's no bonus) so one flagged card doesn't
	# shove its cover down out of line with the rest of the offering.
	var repeat: bool = bool(choice.get("repeat", false))
	var bonus := Label.new()
	bonus.text = ("⚡ Gain +%d Dash" % REPEAT_BEAT_DASH) if repeat else ""
	if repeat:
		bonus.tooltip_text = "You've already beaten %s this run — beat it again for a Dash charge." % game.display_name
	bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bonus.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE)
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bonus.add_theme_font_size_override("font_size", BADGE_FONT)
	bonus.add_theme_color_override("font_color", DASH_BLUE)
	card.add_child(bonus)

	var btn := Button.new()
	btn.custom_minimum_size = COVER_SIZE
	var frame_n := UITheme.flat(UITheme.BG, 8, 4, 1, UITheme.BORDER)
	var frame_h := UITheme.flat(UITheme.PANEL_HI, 8, 4, 2, accent)
	btn.add_theme_stylebox_override("normal", frame_n)
	btn.add_theme_stylebox_override("hover", frame_h)
	btn.add_theme_stylebox_override("pressed", frame_h)
	btn.add_theme_stylebox_override("focus", frame_h)
	btn.pressed.connect(func(): pick(index))
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
	name_lbl.text = ("☠ " if choice["boss"] else ("🏆 " if choice["amulet"] else "")) + game.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, NAME_BOX_H)
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT)
	name_lbl.add_theme_color_override("font_color", accent if (choice["boss"] or choice["amulet"]) else UITheme.TEXT)
	card.add_child(name_lbl)

	# The tries this game hands you (§3): a Traditional roguelike is the long haul
	# and grants more, which is a real reason to route through one.
	var tries: int = GameLoop2.shields_for_game(game)
	var tries_lbl := Label.new()
	tries_lbl.text = "%s  %d tries" % ["◆".repeat(tries), tries]
	tries_lbl.tooltip_text = "Selecting %s grants %d shields — one per run of it you lose." % [
		game.display_name, tries]
	tries_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tries_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tries_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE)
	tries_lbl.add_theme_font_size_override("font_size", BADGE_FONT)
	tries_lbl.add_theme_color_override("font_color", SHIELD_BLUE)
	card.add_child(tries_lbl)

	# Bash/Transmute are available even on a boss round — the boss follows the
	# gate, so escaping a specific game still lands you on a boss.
	var verbs := HBoxContainer.new()
	verbs.alignment = BoxContainer.ALIGNMENT_CENTER
	if GameState.bash > 0:
		verbs.add_child(_mini_button("Bash", func(): bash_choice(index)))
	if GameState.transmute > 0:
		verbs.add_child(_mini_button("Transmute", func(): transmute_choice(index)))
	if verbs.get_child_count() > 0:
		card.add_child(verbs)
	var proven := _beatable_row(choice)
	if proven != null:
		card.add_child(proven)
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
	var on_board: Array = []
	var here: GoalEnemyData = choice.get("enemy")
	if here != null:
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
	_clear(_launch_row)
	_clear(_verify_box)
	_fulfil_checks.clear()
	_levelup_check = null
	_goal_check = null
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
	#   • the current game's GOAL (top) — ticked defeats its enemy, unticked leaves
	#     it following you;
	#   • the character LEVEL-UP challenge;
	#   • each FOLLOWING enemy whose old goal you also cleared this game.
	_verify_box.add_child(_verify_head("Tick what you did this game:"))

	var enemy: GoalEnemyData = _chosen.get("enemy")
	if enemy != null and enemy.goal != "":
		var is_amulet: bool = bool(_chosen.get("amulet", false))
		var goal_text: String = "%s %s" % ["🏆 Amulet goal —" if is_amulet else "Goal —", enemy.goal]
		var goal_row := _verify_row(goal_text, UITheme.SUCCESS, true, enemy)
		_goal_check = goal_row["check"]
		_verify_box.add_child(goal_row["row"])

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

	# GOAL FIRST, then whose it is. The checklist is scanned for "what did I
	# actually do", and the goal is the part being answered — the enemy's name is
	# the label on it. Leading with the name made every row start with a proper
	# noun the player has to read past to reach the thing they're ticking.
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var row := _verify_row("Also cleared: %s — %s" % [e.goal, e.display_name], UITheme.TEXT, false, e)
		_verify_box.add_child(row["row"])
		_fulfil_checks.append({"check": row["check"], "instance": int(entry["instance"])})

# The checklist while you're CHOOSING: the goals already on you — the character's
# level-up challenge, and every follower's outstanding goal (any of which you may
# clear during whatever game you pick next, §2). Answering "what do I need to do?"
# belongs BEFORE you commit to a game, not only after, so the panel keeps its place
# beside the board instead of appearing out of nowhere on pick.
#
# Read-only by design: there is nothing to report until a game is in play, so these
# are rows rather than tick boxes.
func _populate_standing_checklist() -> void:
	_clear(_launch_row)
	_clear(_verify_box)
	_fulfil_checks.clear()
	_levelup_check = null
	_goal_check = null
	_verify_box.add_child(_verify_head("What you need to do:"))

	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null and ch.level_up_condition != "":
		var lu_text: String = "Level up — %s" % ch.level_up_condition
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			lu_text += "   → %s" % ch.level_up_reward
		_verify_box.add_child(_objective_row(lu_text, UITheme.GOLD))

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
		_verify_box.add_child(_objective_row(
			"%s — %s   (dmg %d)" % [e.goal, e.display_name, e.damage], tint,
			_boss_icon(e)))

	if GameLoop2.stack.is_empty():
		var none := _verify_head("Nothing is following you — pick a game and take on its goal.")
		_verify_box.add_child(none)

# One read-only checklist row: the same frame the tick-box rows use, without the
# box, so the standing list and the report step read as the same list in two
# states. `icon` is the boss portrait, when the row belongs to one (_boss_icon).
func _objective_row(text: String, color: Color, icon: Texture2D = null) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, 1, color.lerp(UITheme.BORDER, 0.35)))
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

# Whether the chosen game's MAIN goal was met — true when its checkbox is ticked,
# or when the game had no enemy/goal to meet (a free game auto-clears).
func _goal_met() -> bool:
	return _goal_check == null or _goal_check.button_pressed

# One checklist row: a bordered CheckBox tinted `color`; `emphasise` gives the
# main-goal row a heavier border so it reads as the primary question. Kept to a
# single tight line each — the stage above it is the board, and the checklist has
# to stay a glanceable list rather than a stack of cards.
# One checklist line. When `enemy` is given the row also carries a Notes button
# on the right, for writing down how this enemy was actually beaten AT this game
# — the note belongs to the pair, and the Atlas surfaces it on the game later.
func _verify_row(text: String, color: Color, emphasise: bool,
		enemy: GoalEnemyData = null, character: CharacterData = null) -> Dictionary:
	var wrap := PanelContainer.new()
	var border: Color = color.lerp(UITheme.BORDER, 0.35)
	var width: int = 2 if emphasise else 1
	var idle: StyleBox = UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, width, border)
	# The WHOLE ROW answers, not just the box: a ticked row goes green-washed and
	# green-rimmed, so a filled checklist reads at a glance from the board beside
	# it rather than needing each little box squinted at in turn.
	var ticked_box: StyleBox = UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.80), 5, 4,
		maxi(width, 2), UITheme.SUCCESS.lerp(UITheme.BORDER, 0.15))
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
	cb.add_theme_font_size_override("font_size", 13)
	cb.add_theme_color_override("font_color", color)
	cb.add_theme_color_override("font_pressed_color", color)
	cb.add_theme_color_override("font_hover_color", UITheme.GOLD)
	cb.toggled.connect(func(on: bool):
		wrap.add_theme_stylebox_override("panel", ticked_box if on else idle)
		cb.add_theme_color_override("font_color",
			UITheme.SUCCESS.lerp(Color.WHITE, 0.55) if on else color))
	line.add_child(cb)
	var game: GameData = _chosen.get("game")
	if game != null:
		if enemy != null:
			line.add_child(_notes_button(game, enemy))
		elif character != null:
			line.add_child(_levelup_notes_button(game, character))
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
	return TierListScreen.open(self)

# The instances the player ticked as fulfilled this game.
func _ticked_fulfilments() -> Array:
	var out: Array = []
	for f in _fulfil_checks:
		if is_instance_valid(f["check"]) and f["check"].button_pressed:
			out.append(f["instance"])
	return out

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
	_preview.text = _enemy_preview_text(_choices[index])
	var tex: Texture2D = _enemy_texture(_choices[index])
	_preview_img.texture = tex
	UITheme.apply_crisp(_preview_img, tex)
	# The HUD previews this game's shield grant while the mouse is on it.
	_hover_grant = GameLoop2.shields_for_game(_choices[index]["game"])
	_refresh_hud()

# The mouse left a card: the enemy preview stays (it's a reference panel), but the
# HUD's grant preview goes, so it can never advertise a game you're not pointing at.
func _clear_hover_grant() -> void:
	if _hover_grant < 0:
		return
	_hover_grant = -1
	_refresh_hud()

# The enemy's art (§10.1) for a choice, or null when there's no enemy.
func _enemy_texture(choice: Dictionary) -> Texture2D:
	var e: GoalEnemyData = choice.get("enemy")
	return e.image if e != null else null

func _enemy_preview_text(choice: Dictionary) -> String:
	var e: GoalEnemyData = choice.get("enemy")
	var game: GameData = choice["game"]
	# A rematch pays a Dash — stated on the preview as well as the card, so it also
	# shows on the report panel for the game you're playing.
	var repeat: String = ""
	if bool(choice.get("repeat", false)):
		repeat = "\n[color=#80d9ff]⚡ Already beaten this run — beating it again grants +%d Dash.[/color]" % REPEAT_BEAT_DASH
	if e == null:
		return "[b]%s[/b]\n[i]No enemy — free game.[/i]%s" % [game.display_name, repeat]
	var kind: String = "[color=#e0b020][b]☠ BOSS[/b][/color] " if choice["boss"] else ""
	# Effective Health = goal completions to defeat it (Alien Baby makes it 2).
	var hp: int = GameLoop2.effective_health(e)
	var hp_txt: String = "%d goal%s to beat" % [hp, "" if hp == 1 else "s"]
	return "[b]%s[/b]  →  %s%s\n[b]GOAL (%s):[/b] %s   [i](%s / %s / %s / dmg %d)[/i]%s" % [
		game.display_name, kind, e.display_name,
		String(e.goal_type).capitalize(), e.goal,
		String(e.game_type).capitalize(), RunDifficulty.tier_name(int(e.difficulty)), hp_txt, e.damage,
		repeat,
	]

func _now_playing_text() -> String:
	if _chosen.is_empty():
		return ""
	return "[b]Now playing:[/b] %s\n%s" % [_chosen["game"].display_name, _enemy_preview_text(_chosen)]

# The HUD's Shields slot. While a game is in play it's the live pool. While you're
# choosing, the pool is empty (they expired with the last game), so hovering a card
# previews what THAT game would grant — the number is part of the choice, not a
# flat 0 that reads as "you're out".
func _hud_shields() -> String:
	if _phase == Phase.SELECT and _hover_grant >= 0:
		return "[b]Shields[/b] [color=#%s]+%d[/color]" % [SHIELD_BLUE.to_html(false), _hover_grant]
	return "[b]Shields[/b] %d" % GameState.shields

func _hud_text() -> String:
	# Health is quoted off the BOARD while a resolve plays back, so the two places
	# it's printed can't disagree: the hero's line comes down one strike at a time
	# (BattlefieldView.animate_resolve) and the HUD comes down with it.
	var hp: int = _board.shown_hp() if _board != null else GameState.hp
	return "[b]Health[/b] %d/%d   %s      [b]Tier[/b] %s      [b]Bash[/b] %d  [b]Dash[/b] %d  [b]Push[/b] %d  [b]Transmute[/b] %d  [b]Scramble[/b] %d  [b]Bombs[/b] %d  [b]Keys[/b] %d  [b]Scrolls[/b] %d   [b]Chests[/b] %d" % [
		hp, GameState.max_hp, _hud_shields(),
		RunDifficulty.tier_name(_current_tier()),
		GameState.bash, GameState.dash_charges, GameState.push, GameState.transmute,
		GameState.scramble, GameState.bombs, GameState.keys,
		GameState.get_loot_count("scroll"), GameState.pending_chests,
	]

# Rebuild the Scrolls panel: one Read button per carried scroll, showing its
# identified name/art or the Unidentified mask (§4.1). Reading is always allowed
# from the overworld. Only shown in the SELECT phase so it can't be opened while
# a game is mid-report.
func _refresh_scrolls() -> void:
	if _scrolls_box == null:
		return
	_clear(_scrolls_box)
	var scrolls: Array = GameState.loot_scrolls()
	if scrolls.is_empty():
		var none := Label.new()
		none.text = "  (none)"
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		_scrolls_box.add_child(none)
		return
	# loot_scrolls() preserves pickup order; map each back to its loot_items index
	# so read_scroll consumes the right entry.
	for entry in scrolls:
		var idx: int = GameState.loot_items.find(entry)
		var s: ScrollData = Data.get_scroll(StringName(entry.get("id", "")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if s != null:
			icon.texture = ScrollSystem.art_texture(s)
		row.add_child(icon)
		var name_lbl := Label.new()
		name_lbl.text = ScrollSystem.display_name(s) if s != null else "Scroll"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var read_btn := Button.new()
		read_btn.text = "Read"
		read_btn.pressed.connect(func(): read_scroll(idx))
		row.add_child(read_btn)
		_scrolls_box.add_child(row)

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

func _refresh_items() -> void:
	if _items_box == null:
		return
	_clear(_items_box)
	if GameState.inventory.is_empty():
		_items_box.add_child(_empty_note("nothing carried yet"))
		return
	var reporting: bool = _phase == Phase.PLAYING
	for item in GameState.inventory:
		if not (item is ItemData):
			continue
		_items_box.add_child(_item_token(item, reporting))

func _item_token(item: ItemData, reporting: bool) -> Control:
	var tint: Color = UITheme.rarity_color(int(item.rarity))
	var active: bool = item.kind == ItemData.ItemKind.USABLE or item.is_charged()
	var ready: bool = active and GameState.can_fire_item(item) and not reporting

	var tile := PanelContainer.new()
	var border: Color = UITheme.GOLD if ready else tint.lerp(UITheme.BG, 0.45)
	tile.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.86), 5, 3, 2 if ready else 1, border))
	tile.tooltip_text = _item_tip(item, active, ready, reporting)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(ITEM_TOKEN, ITEM_TOKEN)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(stack)
	var art := UITheme.crisp_tex(item.image, ITEM_TOKEN)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(art)
	# A charged item's bar is the one number that changes on its own, so it stays
	# printed on the token instead of hiding in the tooltip.
	if item.is_charged():
		var charge := Label.new()
		charge.text = "%d/%d" % [item.current_charge, item.max_charge()]
		charge.add_theme_font_size_override("font_size", 9)
		charge.add_theme_color_override("font_color", UITheme.GOLD if ready else UITheme.TEXT_DIM)
		charge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		charge.add_theme_constant_override("outline_size", 4)
		charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		charge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
		stack.add_child(charge)

	if ready:
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var target_item: ItemData = item
		tile.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				use_item(target_item))
	return tile

# Everything the old named row said, in the tooltip the token carries.
func _item_tip(item: ItemData, active: bool, ready: bool, reporting: bool) -> String:
	var tip: String = "%s  ·  %s" % [item.display_name, UITheme.rarity_name(int(item.rarity))]
	if item.is_charged():
		tip += "  [%d/%d]" % [item.current_charge, item.max_charge()]
	if String(item.description) != "":
		tip += "\n%s" % item.description
	if active:
		if ready:
			tip += "\n▸ Click to use."
		elif reporting:
			tip += "\n▸ Report this game first."
		elif item.is_charged():
			tip += "\n▸ Charging."
	return tip

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
func _stack_summary() -> String:
	var following: int = GameLoop2.stack.size()
	if _phase == Phase.PLAYING and not _chosen.is_empty() and _chosen.get("enemy") != null:
		following += 1
	if following == 0:
		return "clear  —  nothing following you"
	var dmg: int = GameLoop2.stacked_damage_per_game()
	var swings: int = 0
	for entry in GameLoop2.stack:
		swings += GameLoop2.attacks_next_game(entry)
	return "%d closing in, %d swing%s landing for %d damage next game" % [
		following, swings, "" if swings == 1 else "s", dmg]


# --- kill-drops (§8) -------------------------------------------------------

# A defeated enemy dropped loot: roll an item and queue it. The queue is drained
# one ItemDropModal at a time (_pump_drops) — the kill ASKS whether you want what
# fell off it, rather than leaving it in a tray to be noticed. Skipped once the
# run is over (win/lose screens take over the board).
func _on_enemy_defeated(_enemy: GoalEnemyData) -> void:
	if GameLoop2.run_over:
		return
	var item: ItemData = _roll_drop()
	if item == null:
		return
	_drop_queue.append({"item": item})
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
	var modal = ItemDropModal.open(self, drop["item"])
	_drop_modal = modal
	modal.answered.connect(func(taken: bool):
		_drop_modal = null
		if taken:
			_collect_drop(drop)
		else:
			_skip_drop(drop)
		# Whatever is behind it in the queue is the next question.
		_pump_drops())

# Roll one drop item from the games-first reward pool, weighted by rarity the same
# way the RewardScreen chest roll is (§8) — minus the luck advantage, which is the
# chest's own bonus.
func _roll_drop() -> ItemData:
	var bucket: Array = Data.reward_item2_pool_of(Data.roll_item_rarity(_rng))
	if bucket.is_empty():
		return null
	return bucket[_rng.randi_range(0, bucket.size() - 1)]

func _collect_drop(drop: Dictionary) -> void:
	if not _drop_queue.has(drop):
		return
	_drop_queue.erase(drop)
	var item: ItemData = drop["item"]
	GameState.add_item(item)
	GameLog.add("Collected %s." % item.display_name, Color(0.7, 1.0, 0.7))
	Notifications.notify("Took %s." % item.display_name, UITheme.rarity_color(int(item.rarity)))

func _skip_drop(drop: Dictionary) -> void:
	if not _drop_queue.has(drop):
		return
	_drop_queue.erase(drop)
	GameLog.add("Left %s behind." % String(drop["item"].display_name), Color(0.8, 0.8, 0.8))


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
	_boss_banner.get_parent().visible = false
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
	# AUTO rather than DISABLED. The page is laid out to fit its width — the board
	# fits itself to a budget, the bars flow — but DISABLED doesn't clamp anything
	# that doesn't, it CLIPS it, and a board hanging off the right edge with no way
	# to reach it is exactly the failure this is guarding against. Nothing should
	# ever be wide enough to raise the bar; if something is, it stays reachable.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	_scroll = scroll
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "The Search for the Amulet"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var map_btn := Button.new()
	map_btn.text = "🗺 Map"
	map_btn.pressed.connect(open_map)
	header.add_child(map_btn)
	var save_btn := Button.new()
	save_btn.text = "💾 Save"
	save_btn.tooltip_text = "Save this run — pick it back up from Continue on the main menu."
	save_btn.pressed.connect(prompt_save)
	header.add_child(save_btn)
	var restart_btn := Button.new()
	restart_btn.text = "⟳ New run"
	restart_btn.pressed.connect(func(): start_run())
	header.add_child(restart_btn)
	var menu_btn := Button.new()
	menu_btn.text = "← Menu"
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn"))
	header.add_child(menu_btn)
	root.add_child(header)

	_hud = _panel_label()
	var hud_panel := PanelContainer.new()
	hud_panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 10, 1))
	hud_panel.add_child(_hud)
	root.add_child(hud_panel)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.hide()
	root.add_child(_banner)

	_boss_banner = Label.new()
	_boss_banner.text = "⚠   BOSS INCOMING   ⚠"
	_boss_banner.add_theme_font_size_override("font_size", 20)
	_boss_banner.add_theme_color_override("font_color", Color(1.0, 0.62, 0.24))
	_boss_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var boss_wrap := PanelContainer.new()
	boss_wrap.add_theme_stylebox_override("panel", UITheme.flat(Color(0.20, 0.08, 0.05, 0.9), 10, 8, 2, UITheme.DANGER.lerp(UITheme.ACCENT, 0.4)))
	boss_wrap.add_child(_boss_banner)
	_boss_banner.set_meta("wrap", boss_wrap)
	boss_wrap.hide()
	root.add_child(boss_wrap)

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

	_select_head = _section("Choose a game to travel to:")
	_select_box.add_child(_select_head)
	# Controls row (Dash) — populated per refresh.
	_controls_row = HBoxContainer.new()
	_controls_row.add_theme_constant_override("separation", 8)
	_select_box.add_child(_controls_row)
	_choices_row = HFlowContainer.new()
	_choices_row.add_theme_constant_override("h_separation", 12)
	_choices_row.add_theme_constant_override("v_separation", 10)
	_select_box.add_child(_choices_row)

	# Hover preview: the enemy's art beside its name + goal.
	var preview_wrap := PanelContainer.new()
	preview_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 10, 1))
	var preview_box := HBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 12)
	preview_wrap.add_child(preview_box)
	_preview_img = _enemy_image_rect()
	_preview_img.custom_minimum_size = Vector2(64, 64)
	preview_box.add_child(_preview_img)
	_preview = _panel_label()
	_preview.custom_minimum_size = Vector2(0, 24)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_box.add_child(_preview)
	_select_box.add_child(preview_wrap)

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
	var inv_head := _section("🎒  Inventory")
	inv_head.add_theme_font_size_override("font_size", 13)
	inv_box.add_child(inv_head)
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

	# Board header: what the field is doing, on one line. The summary already names
	# the battlefield, so there's no section label above it.
	_board_head = VBoxContainer.new()
	_stack = _panel_label()
	_board_head.add_child(_stack)
	stage_box.add_child(_board_head)

	_board = BattlefieldView.new()
	# The HUD's Health quotes the board's, so it has to repaint when the board's
	# does — that's every strike of a resolve playback.
	_board.shown_hp_changed.connect(func(_hp): _refresh_hud())
	_board.push_requested.connect(push_follower)
	_board.bomb_requested.connect(bomb_follower)
	_board.enemy_inspected.connect(_show_enemy_info)
	stage_box.add_child(_board)


	# --- the report checklist (left column, shown while a game is in play) ----

	# One tight row: the cover, the enemy, and the goal text — sized down from the
	# old card, because the board beside it is the biggest thing on the page.
	_np_box = HBoxContainer.new()
	var np_box := _np_box
	np_box.add_theme_constant_override("separation", 10)
	_now_playing_cover = TextureRect.new()
	_now_playing_cover.custom_minimum_size = COVER_SIZE * 0.72
	_now_playing_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_now_playing_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var cover_frame := PanelContainer.new()
	cover_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 6, 4, 1, UITheme.BORDER))
	cover_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cover_frame.add_child(_now_playing_cover)
	np_box.add_child(cover_frame)
	_now_playing_img = _enemy_image_rect()
	_now_playing_img.custom_minimum_size = Vector2(72, 72)
	var img_frame := PanelContainer.new()
	img_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 6, 4, 1, UITheme.BORDER))
	img_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	img_frame.add_child(_now_playing_img)
	np_box.add_child(img_frame)
	_now_playing = _panel_label()
	_now_playing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_playing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	done.pressed.connect(func(): report(_goal_met()))
	_play_panel.add_child(done)

	# The way out, directly under the way through — they resolve the same step, so
	# they belong together. Hidden until ESCAPE_AFTER_ATTEMPTS lost runs, and
	# deliberately quieter than Completed Game: this is the concession, not the
	# goal. Tinted like the attempt strip's damage rather than its success green,
	# because the enemy still follows you out.
	_escape_btn = Button.new()
	_escape_btn.text = "🏃  Escape this game"
	_escape_btn.tooltip_text = ("Leave without beating it. The goal-enemy walks onto the "
		+ "board and follows you, exactly as reporting a missed goal does.")
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

	_scrolls_wrap = VBoxContainer.new()
	_scrolls_wrap.add_theme_constant_override("separation", 4)
	_scrolls_wrap.add_child(_section("Scrolls (read on the overworld):"))
	_scrolls_box = VBoxContainer.new()
	_scrolls_box.add_theme_constant_override("separation", 4)
	_scrolls_wrap.add_child(_scrolls_box)
	root.add_child(_scrolls_wrap)

	_log = _panel_label()
	root.add_child(_log)

	# The toast layer: pickups, item procs and the repeat-beat Dash all post to
	# Notifications, and this is what makes them visible the instant they happen. It
	# used to be mounted by the (now cut) combat host, so nothing showed them.
	# Mounted on THIS screen (full-rect) rather than a bare CanvasLayer — the toast
	# stack anchors to its parent's top-right corner, and a Control hung straight off
	# a CanvasLayer has no rect to anchor to, which parks the stack off-screen.
	add_child(NotificationToasts.new())

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
	# The escape hatch only exists once the player has lost enough runs to have
	# earned it, and it goes away again if they undo back under the line.
	if _escape_btn != null:
		_escape_btn.visible = can_escape()

func _enemy_image_rect() -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(96, 96)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t

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

func _mini_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b
