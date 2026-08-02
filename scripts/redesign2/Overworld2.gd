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
# This file owns the RUN: the offering, the report step, the pack column (the
# inventory with the loot tray under it), and the charges the combat verbs spend.
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
# the board with the pack (inventory + loot tray) under it.
var _left_col: VBoxContainer
var _right_col: VBoxContainer
var _report_panel: PanelContainer    # frames the checklist half (left)
var _stage_panel: PanelContainer     # frames the board (right, above the pack)
var _board_head: VBoxContainer       # the board's heading + summary line
var _pack_col: Control               # inventory + loot tray, under the board
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
# The parts of the checklist panel that need a game in hand: the now-playing row,
# the attempt strip and the Completed Game button. Hidden while you're choosing,
# where the panel is the standing-goals list instead.
var _np_box: HBoxContainer
var _attempt_wrap: Control
var _done_btn: Button
# The board itself (§grid): the player on the left, a GRID_COLS x GRID_ROWS grid on
# the right where enemies close in one column per game beaten (MMBN-style). It's a
# BattlefieldView — a view over GameLoop2 that reports Push / Bomb / inspect back
# here, since this screen owns the charges and the run.
var _board: BattlefieldView
var _info_popup: EnemyInfoCard      # the click-to-inspect enemy card (null when closed)
var _log: RichTextLabel
var _scrolls_box: VBoxContainer
# The side column right of the grid: the player's inventory, and under it the loot
# tray where a defeated enemy's drop waits to be claimed or skipped (§8).
var _items_box: VBoxContainer       # owned items with Use buttons (§4/§8)
var _loot_box: VBoxContainer
var _drop_queue: Array = []         # [{item: ItemData}] waiting in the loot tray
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
	# Every defeated enemy drops an item that lands in the loot tray beside the board
	# (§8), instead of banking a RewardScreen chest.
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
# are on the table, which game is in play, what's waiting in the loot tray. Neither
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

# Open the bird's-eye "Map to the Amulet" — the layered shortest-path graph from
# the current game down to the amulet (ported from the old web build). The current
# offering's reachable games are passed so the map can flag them as choices.
func open_map() -> void:
	var modal := preload("res://scripts/redesign2/RunMapModal.gd").new()
	var choice_ids: Array = []
	for c in _choices:
		choice_ids.append(c["slot"])
	modal.start(self, GameState.current_game_id, GameState.amulet_game_id, choice_ids)

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
	_close_enemy_info()
	var res: Dictionary = GameLoop2.beat_game(goal_met, fulfilled_instances)
	# "After beating a game" is the dominant 2.0 item trigger (§8): fire it now so
	# owned items react (Burning Blood +1 Health, Meat on the Bone's conditional
	# heal), the Harvesting stat pays out, charged actives tick, and the toast
	# shows. Defeated-enemy drops were already banked by beat_game above.
	# Remember WHICH enemies fell at this game, so the Atlas can list them later
	# alongside whatever the player wrote about them.
	if played_game != null:
		var goal_enemy: GoalEnemyData = _chosen.get("enemy")
		if goal_met and goal_enemy != null:
			GameStats.record_enemy_beaten(played_game.id, goal_enemy.id)
		for inst in fulfilled_instances:
			for entry in GameLoop2.stack:
				if int(entry.get("instance", -1)) == int(inst):
					var follower: GoalEnemyData = entry["enemy"]
					if follower != null:
						GameStats.record_enemy_beaten(played_game.id, follower.id)
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
	GameState.games_played += 1
	_chosen = {}
	# Rating is a BUTTON, never a pop-up: remember the game so the "★ Rate <game>"
	# button on the select screen can score it whenever the player feels like it.
	if played_game != null:
		_last_played_game = played_game
	if GameLoop2.run_over:
		_phase = Phase.OVER
		_refresh()
		_board.animate_resolve(before, res)
		return
	if was_amulet and goal_met:
		GameLoop2.clear_amulet()
		return
	_phase = Phase.SELECT
	_build_choices()
	_refresh()
	# Back to the offering — that's the decision now, so put it back on screen.
	_scroll_to_top()
	# The run moved, so the recovery point moves with it.
	autosave()
	# Repaint first, then replay the strike + advance from the snapshot: the board
	# is already in its final state, the animation just shows how it got there.
	_board.animate_resolve(before, res)

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
# of the same type. Allowed on a boss round — the replacement game still spawns a
# boss, because boss-ness follows the difficulty gate rather than the game.
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
	return nbrs.slice(0, cap)

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
# outside a loop resolve too — an item picked up from the loot tray or a chest
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
	_refresh_loot()
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
	# run has a position.
	_select_box.visible = _phase == Phase.SELECT or _phase == Phase.START_SELECT
	_scrolls_wrap.visible = _phase == Phase.SELECT
	_play_panel.visible = _phase != Phase.OVER
	_report_panel.visible = _phase != Phase.OVER
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
	type_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, 0)
	type_lbl.add_theme_font_size_override("font_size", 13)
	type_lbl.add_theme_color_override("font_color", accent.lerp(UITheme.TEXT, 0.35))
	card.add_child(type_lbl)

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
	name_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, 0)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	card.add_child(name_lbl)

	var dist := Label.new()
	dist.text = "%d games from the Amulet" % int(opt["path_len"])
	dist.tooltip_text = "The shortest route from %s to the hidden Amulet game." % game.display_name
	dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist.custom_minimum_size = Vector2(COVER_SIZE.x, 0)
	dist.add_theme_font_size_override("font_size", 12)
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

# The offered cover art, sized as BOX ART rather than as a thumbnail: the covers
# ship at 3:4 (528x704 / 300x450), so a 3:4 frame fills edge to edge with nothing
# letterboxed, and the game you're being offered is the biggest thing on the page.
# Three cards at this size still sit in one row on a 1280px viewport; a wider
# offering (the game_choices bonus) wraps in the HFlowContainer.
const COVER_SIZE := Vector2(210, 280)

# One choice = the game's cover art with its name below, plus (off a boss round)
# small Bash/Transmute verbs when the player has charges. Hover updates the
# shared enemy preview.
func _make_choice_card(index: int, choice: Dictionary) -> Control:
	var game: GameData = choice["game"]
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	card.custom_minimum_size = Vector2(COVER_SIZE.x + 10, 0)

	var accent: Color = UITheme.DANGER if choice["boss"] else (UITheme.GOLD if choice["amulet"] else UITheme.type_color(int(game.type)))

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
	bonus.custom_minimum_size = Vector2(COVER_SIZE.x, 0)
	bonus.add_theme_font_size_override("font_size", 13)
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
	name_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, 0)
	name_lbl.add_theme_font_size_override("font_size", 14)
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
	tries_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, 0)
	tries_lbl.add_theme_font_size_override("font_size", 12)
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
	# with its reward shown inline so the payoff reads at a glance.
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null and ch.level_up_condition != "":
		var lu_text: String = "Leveled up — %s" % ch.level_up_condition
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			lu_text += "   → %s" % ch.level_up_reward
		var lu_row := _verify_row(lu_text, UITheme.GOLD, false)
		_levelup_check = lu_row["check"]
		_verify_box.add_child(lu_row["row"])

	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var row := _verify_row("Also cleared: %s — %s" % [e.display_name, e.goal], UITheme.TEXT, false, e)
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
		# "dmg N" in words: the board's ⚔ badge is a fine-detail glyph that reads as
		# an ✕ at list-row sizes.
		_verify_box.add_child(_objective_row(
			"%s — %s   (dmg %d)" % [e.display_name, e.goal, e.damage], tint))

	if GameLoop2.stack.is_empty():
		var none := _verify_head("Nothing is following you — pick a game and take on its goal.")
		_verify_box.add_child(none)

# One read-only checklist row: the same frame the tick-box rows use, without the
# box, so the standing list and the report step read as the same list in two
# states.
func _objective_row(text: String, color: Color) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, 1, color.lerp(UITheme.BORDER, 0.35)))
	var l := Label.new()
	l.text = "•  " + text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(l)
	return wrap

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
		enemy: GoalEnemyData = null) -> Dictionary:
	var wrap := PanelContainer.new()
	var border: Color = color.lerp(UITheme.BORDER, 0.35)
	wrap.add_theme_stylebox_override("panel", UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, 2 if emphasise else 1, border))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	wrap.add_child(line)
	var cb := CheckBox.new()
	cb.text = text
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_theme_font_size_override("font_size", 13)
	cb.add_theme_color_override("font_color", color)
	line.add_child(cb)
	if enemy != null:
		var game: GameData = _chosen.get("game")
		if game != null:
			line.add_child(_notes_button(game, enemy))
	return {"row": wrap, "check": cb}

# The per-row Notes button. Shows a filled glyph once something is written, so a
# game you've already annotated reads at a glance.
func _notes_button(game: GameData, enemy: GoalEnemyData) -> Button:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 11)
	b.tooltip_text = "Write down how you beat %s here" % enemy.display_name
	var refresh := func():
		var has: bool = GameStats.enemy_note(game.id, enemy.id).strip_edges() != ""
		b.text = "🗒 Notes ✎" if has else "🗒 Notes"
		b.add_theme_color_override("font_color", UITheme.GOLD if has else UITheme.TEXT_DIM)
	refresh.call()
	b.pressed.connect(func(): EnemyNoteModal.open(self, game, enemy, refresh))
	return b

func _verify_head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l

# Open the tier-list rating prompt for `game` (1-10 + optional notes). Submitting
# records the score via TierList (dropping the game into the Unranked tray the
# first time); "Maybe later" just closes it. Pre-fills when already rated so the
# player updates rather than starts over.
func _prompt_rating(game: GameData) -> void:
	if game == null:
		return
	var modal = preload("res://scripts/ui/RateGameModal.gd").new()
	modal.setup(game.id, game)
	modal.submitted.connect(func(score: int, notes: String):
		TierList.set_rating(game.id, score, notes)
		modal.queue_free())
	modal.dismissed.connect(func(): modal.queue_free())
	add_child(modal)

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
	return "[b]Health[/b] %d/%d   %s      [b]Tier[/b] %s      [b]Bash[/b] %d  [b]Dash[/b] %d  [b]Push[/b] %d  [b]Transmute[/b] %d  [b]Scramble[/b] %d  [b]Bombs[/b] %d  [b]Keys[/b] %d  [b]Scrolls[/b] %d   [b]Chests[/b] %d" % [
		GameState.hp, GameState.max_hp, _hud_shields(),
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

# Owned items in the pack column, each with its rarity-tinted name and — for
# USABLE / CHARGED actives — a Use button that's enabled only when the item can
# fire right now (a charged item needs a full bar; charged bars show their fill).
# Passive / triggered items list without a button. Mirrors the scrolls panel.
#
# The panel stays readable while a game is being reported, but the actives are
# locked for that stretch: the report step is mid-resolve, so firing an item there
# would land between "played the game" and "said what happened".
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
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UITheme.crisp_tex(item.image, 28))
		var name_lbl := Label.new()
		var label_text: String = item.display_name
		if item.is_charged():
			label_text += "  [%d/%d]" % [item.current_charge, item.max_charge()]
		name_lbl.text = label_text
		name_lbl.tooltip_text = item.description
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.add_theme_color_override("font_color", UITheme.rarity_color(int(item.rarity)))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		# Only actives get a Use button; a charged item shows a disabled "Charging"
		# until its bar fills.
		if item.kind == ItemData.ItemKind.USABLE or item.is_charged():
			var use_btn := Button.new()
			var ready: bool = GameState.can_fire_item(item) and not reporting
			use_btn.text = "Use" if ready else ("Charging" if item.is_charged() else "Use")
			use_btn.disabled = not ready
			if reporting:
				use_btn.tooltip_text = "Report this game first."
			var target_item: ItemData = item
			use_btn.pressed.connect(func(): use_item(target_item))
			row.add_child(use_btn)
		_items_box.add_child(row)

# The loot tray under the inventory: one row per drop waiting to be claimed, with
# the item's art, its rarity-tinted name, and the Claim / Skip pair. Loot lives
# beside the board rather than on it, so a packed grid never hides a drop and the
# melee column stays about enemies (§8).
func _refresh_loot() -> void:
	if _loot_box == null:
		return
	_clear(_loot_box)
	if _drop_queue.is_empty() or _phase == Phase.OVER:
		_loot_box.add_child(_empty_note("no drops waiting"))
		return
	for drop in _drop_queue:
		_loot_box.add_child(_loot_row(drop))

# One waiting drop. The whole row is tinted by rarity so a Legendary reads at a
# glance from across the screen.
func _loot_row(drop: Dictionary) -> Control:
	var item: ItemData = drop["item"]
	var tint: Color = UITheme.rarity_color(int(item.rarity))
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", UITheme.flat(tint.lerp(UITheme.BG, 0.82), 6, 6, 1, tint.lerp(UITheme.BG, 0.35)))
	wrap.tooltip_text = "%s\n%s" % [item.display_name,
		item.description if String(item.description) != "" else "A dropped relic."]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UITheme.crisp_tex(item.image, 40))
	var name_lbl := Label.new()
	name_lbl.text = item.display_name
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_color_override("font_color", tint)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_lbl)
	var take := _mini_button("✓", func(): _collect_drop(drop))
	take.tooltip_text = "Claim %s" % item.display_name
	take.add_theme_color_override("font_color", UITheme.SUCCESS)
	row.add_child(take)
	var skip := _mini_button("✗", func(): _skip_drop(drop))
	skip.tooltip_text = "Leave it on the ground"
	row.add_child(skip)
	wrap.add_child(row)
	return wrap

# The dim "there's nothing here" line the pack panels show when they're empty.
func _empty_note(text: String) -> Label:
	var l := Label.new()
	l.text = "  (%s)" % text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	return l

# One-line header above the follower cards: how many are on your tail and the
# damage the stack lands on the next game beaten.
func _stack_summary() -> String:
	var following: int = GameLoop2.stack.size()
	if _phase == Phase.PLAYING and not _chosen.is_empty() and _chosen.get("enemy") != null:
		following += 1
	if following == 0:
		return "clear  —  nothing following you"
	var dmg: int = GameLoop2.stacked_damage_per_game()
	return "%d closing in, %d at the front dealing %d damage next game" % [
		following, GameLoop2.front_count(), dmg]


# --- kill-drops (§8) -------------------------------------------------------

# A defeated enemy dropped loot: roll an item and queue it in the loot tray under
# the inventory, where it waits to be claimed or skipped. Skipped once the run is
# over (win/lose screens take over the board).
func _on_enemy_defeated(_enemy: GoalEnemyData) -> void:
	if GameLoop2.run_over:
		return
	var item: ItemData = _roll_drop()
	if item == null:
		return
	_drop_queue.append({"item": item})
	# The resolve that produced this defeat also emits loop_changed -> _refresh,
	# which repaints the tray; repaint here too in case the defeat came from a
	# direct action (bomb never drops, fulfil does).
	_refresh_loot()

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
	_refresh_loot()

func _skip_drop(drop: Dictionary) -> void:
	if not _drop_queue.has(drop):
		return
	_drop_queue.erase(drop)
	GameLog.add("Skipped %s." % String(drop["item"].display_name), Color(0.8, 0.8, 0.8))
	_refresh_loot()


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

func _on_run_won() -> void:
	_phase = Phase.OVER
	_drop_queue.clear()
	SaveSystem.clear_autosave()
	_show_banner("🏆  You cleared the Amulet — you win!", Color(0.95, 0.8, 0.2))

func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.show()
	_boss_banner.get_parent().visible = false
	# The run is over: the offering and the report step are done with, and the board
	# drops to the page bottom showing the field the run ended on.
	_refresh_stage()
	_refresh_attempts()
	# The run is over, so any loot still on the ground is gone with it.
	_refresh_loot()

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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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

	# Everything that belongs to CHOOSING a game, in one box the phase toggles: the
	# offering and its verbs are irrelevant once you've committed to a game, and the
	# room they free is what lets the board and the checklist sit together below.
	_select_box = VBoxContainer.new()
	_select_box.add_theme_constant_override("separation", 8)
	root.add_child(_select_box)

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
	preview_box.add_child(_preview_img)
	_preview = _panel_label()
	_preview.custom_minimum_size = Vector2(0, 40)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_box.add_child(_preview)
	_select_box.add_child(preview_wrap)

	# THE STAGE, in two columns: the CHECKLIST on the left — what you're reading and
	# ticking while the real game is open — and on the right the BOARD with the PACK
	# under it, the two things you look at rather than drive. Side by side they both
	# fit a screen, where stacked they didn't.
	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 12)
	root.add_child(main_row)

	# Left column: takes the room the board doesn't need.
	_left_col = VBoxContainer.new()
	_left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main_row.add_child(_left_col)

	_report_panel = PanelContainer.new()
	_report_panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.ACCENT.lerp(UITheme.BORDER, 0.5), 12, 12, 1))
	_left_col.add_child(_report_panel)
	_play_panel = VBoxContainer.new()
	_play_panel.add_theme_constant_override("separation", 6)
	_report_panel.add_child(_play_panel)

	# Right column: the board, then the pack beneath it. Shrink-wrapped to the
	# board's real width so the checklist gets everything else.
	_right_col = VBoxContainer.new()
	_right_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_right_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_right_col.add_theme_constant_override("separation", 8)
	main_row.add_child(_right_col)

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
	_now_playing_cover.custom_minimum_size = COVER_SIZE * 0.36
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

	# The pack lives under the board: what you're carrying and what's waiting on the
	# ground belong with the field, not with the checklist you're ticking.
	_pack_col = _build_pack_column()
	_right_col.add_child(_pack_col)

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

# The pack that sits UNDER the grid in the right column: everything the player is
# carrying, then the loot tray. Both panels are always mounted — only their
# contents change — so the column doesn't jump around as items come and go. It
# fills the column, so it's as wide as the board above it (and falls back to
# PACK_WIDTH when the board is put away).
const PACK_WIDTH := 300

func _build_pack_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(PACK_WIDTH, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var inv_wrap := PanelContainer.new()
	inv_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 10, 1))
	var inv := VBoxContainer.new()
	inv.add_theme_constant_override("separation", 6)
	inv.add_child(_section("🎒  Inventory"))
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 4)
	inv.add_child(_items_box)
	inv_wrap.add_child(inv)
	col.add_child(inv_wrap)

	var loot_wrap := PanelContainer.new()
	loot_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.BG, UITheme.GOLD.lerp(UITheme.BORDER, 0.55), 10, 10, 1))
	var loot := VBoxContainer.new()
	loot.add_theme_constant_override("separation", 6)
	loot.add_child(_section("✦  Loot on the ground"))
	_loot_box = VBoxContainer.new()
	_loot_box.add_theme_constant_override("separation", 4)
	loot.add_child(_loot_box)
	loot_wrap.add_child(loot)
	col.add_child(loot_wrap)
	return col

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
