class_name Overworld
extends Node2D

# Overworld scene. Owns walking + portal selection + verification ("Play the
# real game") + the post-combat item reward + autosave + win/lose UI. Does NOT
# own combat — Main creates the combat scene when this scene emits
# portal_entered, then hands the victory/defeat back so we run the
# play/verify -> item-reward flow here.
#
# On scene init the pending_combat_outcome field (set by Main before
# add_child) tells us "you just came back from a combat: it was a
# victory/defeat for game X." That kicks off the verification flow or
# the defeat reset.

const TILE_SIZE := 32
# Grid sized to fill the 1280x720 viewport so the walkable floor reaches every
# edge of the screen (40*32 = 1280, 22*32 = 704) — no bare background showing
# through around the play area.
const GRID_W := 40
const GRID_H := 22

const PORTAL_SCENE := preload("res://scenes/overworld/Portal.tscn")

# Portal row vertical position and horizontal spacing.
const PORTAL_Y := 4
const PORTAL_SPACING := 3
@warning_ignore("integer_division")
const SPAWN_POS := Vector2i(GRID_W / 2, GRID_H - 3)

signal portal_entered(game_id: StringName)

@onready var _floor_bg: ColorRect = $Floor
@onready var _player: PlayerWalker = $Player
@onready var _hint: Label = $Hint

# Set by Main before add_child so the new scene knows what just
# happened. Empty {} means "no pending — fresh entry".
var pending_combat_outcome: Dictionary = {}

const BASE_PORTAL_COUNT := 3

var _portals: Array[PortalNode] = []
var _active_portal: PortalNode = null
var _win_overlay: Control = null
var _verification_modal: Control = null
var _dash_modal: Control = null
var _map_view: RunMapView = null
var _section_reward_layer: CanvasLayer = null
var _chest_reward_layer: CanvasLayer = null
var _rate_modal: RateGameModal = null
# Game whose section reward is pending — set when a victory is handed to us,
# consumed when the item reward opens after the verification screen.
var _pending_reward_game_id: StringName = &""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Gold by run difficulty tier — matches the HTML prototype's per-victory table
# (Low 10 / Medium 15 / High 25 / Insane 35), keyed off the run tier. Awarded
# by the item-reward screen that follows the "Play the real game" verification.
const SECTION_GOLD_BY_TIER := [10, 15, 25, 35]

func _ready() -> void:
	_rng.randomize()
	_fit_background()
	get_viewport().size_changed.connect(_fit_background)
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_apply_player_avatar()
	_player.moved.connect(_on_player_moved)
	GameState.phase = GameState.Phase.OVERWORLD
	_spawn_portals_for_current_game()
	_update_hint()
	# Golden Beetle banks "chests" (item rewards) whenever a curse / curse card
	# is removed; redeem any that are pending into item-choice screens here.
	if not TriggerBus.chest_granted.is_connected(_on_chest_granted):
		TriggerBus.chest_granted.connect(_on_chest_granted)
	# Process whatever Main just handed us (combat result), if any.
	if not pending_combat_outcome.is_empty():
		var outcome := pending_combat_outcome
		pending_combat_outcome = {}
		call_deferred("_process_combat_outcome", outcome)
	else:
		# Fresh idle entry — redeem any chests banked while we were away.
		call_deferred("_redeem_pending_chests")

# Stretch the floor so it always covers the whole viewport — never leaves the
# bare window clear-colour (the "gray") showing past the grid.
func _fit_background() -> void:
	var vp: Vector2 = get_viewport_rect().size
	_floor_bg.size = Vector2(
		maxf(vp.x, GRID_W * TILE_SIZE),
		maxf(vp.y, GRID_H * TILE_SIZE))

# Swap the placeholder square marker for the chosen character's icon art so the
# overworld avatar matches who you're playing.
func _apply_player_avatar() -> void:
	var avatar: TextureRect = _player.get_node_or_null("Avatar")
	var square: ColorRect = _player.get_node_or_null("Sprite")
	var cd: CharacterData = Data.get_character(GameState.character_id)
	var tex: Texture2D = null
	if cd != null:
		tex = cd.icon if cd.icon != null else cd.portrait
	if avatar != null and tex != null:
		avatar.texture = tex
		avatar.visible = true
		if square != null:
			square.visible = false
	elif square != null:
		square.visible = true

# ------------------------------------------------------------------
# Portal placement
# ------------------------------------------------------------------

func _spawn_portals_for_current_game() -> void:
	for p in _portals:
		p.queue_free()
	_portals.clear()
	_active_portal = null

	var current: GameData = Data.get_game(GameState.current_game_id)
	if current == null:
		push_warning("[Overworld] no current game set")
		return

	var ids: Array[StringName] = _connected_game_ids(current.id)
	if ids.is_empty():
		GameLog.add("No connected games from %s." % current.display_name, Color(0.9, 0.7, 0.4))
		return

	# Shuffle then take 3 ± FoV. Mirrors the HTML's spawnChoices logic.
	_shuffle_ids(ids)
	var target_count: int = maxi(1, BASE_PORTAL_COUNT + Stats.get_value(&"fov_bonus"))
	target_count = mini(target_count, ids.size())
	var chosen: Array[StringName] = []
	for i in range(target_count):
		chosen.append(ids[i])

	_place_portals(chosen)

	GameLog.add("At %s. %d portals open." % [current.display_name, _portals.size()],
		Color(0.8, 0.9, 1.0))

func _place_portals(ids: Array[StringName]) -> void:
	var count := ids.size()
	var span := (count - 1) * PORTAL_SPACING
	@warning_ignore("integer_division")
	var x_start: int = (GRID_W - span) / 2
	for i in range(count):
		var gd: GameData = Data.get_game(ids[i])
		if gd == null:
			continue
		var portal: PortalNode = PORTAL_SCENE.instantiate()
		portal.setup(gd, Vector2i(x_start + i * PORTAL_SPACING, PORTAL_Y))
		add_child(portal)
		_portals.append(portal)

func _shuffle_ids(ids: Array[StringName]) -> void:
	for i in range(ids.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: StringName = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp

func _connected_game_ids(game_id: StringName) -> Array[StringName]:
	# Undirected adjacency, filtered by the active game-filter setting. Using
	# RunGraph.neighbors (rather than walking games_influenced ourselves) means
	# in-run portal choices only ever draw from the same eligible pool the
	# start/amulet path was generated from — in the restricted Owned/Downloaded
	# modes the next-game choices stay inside that pool too.
	return RunGraph.neighbors(game_id)

# ------------------------------------------------------------------
# Player interaction
# ------------------------------------------------------------------

func _on_player_moved(pos: Vector2i) -> void:
	var prev := _active_portal
	_active_portal = null
	for p in _portals:
		if p.grid_pos == pos:
			_active_portal = p
			break
	if prev != _active_portal:
		if prev != null:
			prev.set_highlight(false)
		if _active_portal != null:
			_active_portal.set_highlight(true)
	_update_hint()

func _update_hint() -> void:
	var actions := "WASD/arrows to walk"
	if _active_portal != null:
		actions = "[E] Enter %s   |   " % _active_portal.game_data.display_name + actions
	actions += "   |   [R] Reroll (%d)   |   [Q] Dash (%d)   |   [M] Map" % [
		GameState.reroll_charges, GameState.dash_charges,
	]
	_hint.text = actions

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if not _can_act():
		return
	if event.keycode == KEY_E and _active_portal != null:
		_enter_portal(_active_portal)
	elif event.keycode == KEY_R:
		_try_reroll()
	elif event.keycode == KEY_Q:
		_try_dash()
	elif event.keycode == KEY_M:
		_show_map()
	elif event.keycode == KEY_F5:
		if _save_run():
			GameLog.add("Saved.", Color(0.7, 0.9, 1.0))
		else:
			GameLog.add("Save failed.", Color(0.9, 0.5, 0.5))
	elif event.keycode == KEY_ESCAPE:
		# Quick "back to menu" — autosaves first so the run lives on the
		# Continue list.
		_save_run()
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

func _can_act() -> bool:
	return _verification_modal == null and _win_overlay == null and _dash_modal == null \
		and _map_view == null and _section_reward_layer == null \
		and _chest_reward_layer == null

# ------------------------------------------------------------------
# Run map — view-only overview of the route to the Amulet. Pauses the
# walker while open; closes back via the map's own M / Esc / Close.
# ------------------------------------------------------------------

func _show_map() -> void:
	if _map_view != null:
		return
	_player.set_input_locked(true)
	_map_view = RunMapView.new()
	_map_view.closed.connect(_on_map_closed)
	add_child(_map_view)

func _on_map_closed() -> void:
	_map_view = null
	_player.set_input_locked(false)

func _can_save_load() -> bool:
	return _can_act()

# ------------------------------------------------------------------
# Reroll — re-shuffle the portal selection. Costs 1 reroll charge.
# ------------------------------------------------------------------

func _try_reroll() -> void:
	if GameState.reroll_charges <= 0:
		GameLog.add("No rerolls available.", Color(0.9, 0.7, 0.4))
		return
	GameState.reroll_charges -= 1
	GameLog.add("Rerolled portals. (%d left)" % GameState.reroll_charges,
		Color(1.0, 0.85, 0.4))
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_active_portal = null
	_spawn_portals_for_current_game()
	_update_hint()

# ------------------------------------------------------------------
# Dash — pick a connected game, spawn its portal, then enter it.
# Costs 1 dash charge.
# ------------------------------------------------------------------

func _try_dash() -> void:
	if GameState.dash_charges <= 0:
		GameLog.add("No dashes available.", Color(0.9, 0.7, 0.4))
		return
	var current: GameData = Data.get_game(GameState.current_game_id)
	if current == null:
		return
	var ids: Array[StringName] = _connected_game_ids(current.id)
	if ids.is_empty():
		GameLog.add("Nowhere to dash to.", Color(0.9, 0.7, 0.4))
		return
	_show_dash_modal(ids)

func _show_dash_modal(ids: Array[StringName]) -> void:
	if _dash_modal != null:
		return
	_player.set_input_locked(true)

	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	modal.add_child(dim)

	var panel_w: float = 560.0
	var panel_h: float = mini(560, 160 + ids.size() * 56)
	var panel := Panel.new()
	panel.size = Vector2(panel_w, panel_h)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	modal.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 20)
	title.size = Vector2(panel_w - 40, 32)
	title.text = "Dash — choose a connected game"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 64)
	scroll.size = Vector2(panel_w - 40, panel_h - 132)
	panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for gid in ids:
		var gd: GameData = Data.get_game(gid)
		if gd == null:
			continue
		var btn := Button.new()
		btn.text = gd.display_name
		btn.custom_minimum_size = Vector2(0, 44)
		btn.pressed.connect(_on_dash_pick.bind(gid))
		list.add_child(btn)

	var cancel := Button.new()
	cancel.position = Vector2(panel_w / 2.0 - 80, panel_h - 56)
	cancel.size = Vector2(160, 40)
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_dash_cancel)
	panel.add_child(cancel)

	add_child(modal)
	_dash_modal = modal

func _on_dash_cancel() -> void:
	_close_dash_modal()
	_player.set_input_locked(false)

func _on_dash_pick(game_id: StringName) -> void:
	_close_dash_modal()
	var gd: GameData = Data.get_game(game_id)
	if gd == null:
		_player.set_input_locked(false)
		return
	GameState.dash_charges -= 1
	GameLog.add("Dashed to %s. (%d left)" % [gd.display_name, GameState.dash_charges],
		Color(0.5, 0.95, 1.0))
	# Replace the current portal set with just the dashed-to game, then
	# enter it. Visual: the chosen portal appears in the player's row of
	# portals briefly before the scene transitions.
	for p in _portals:
		p.queue_free()
	_portals.clear()
	_active_portal = null
	var only: Array[StringName] = [game_id]
	_place_portals(only)
	# Highlight the new portal, then enter after a short pause so the
	# player sees what they picked.
	if _portals.size() > 0:
		_portals[0].set_highlight(true)
	get_tree().create_timer(0.45).timeout.connect(_finish_dash.bind(game_id))

func _finish_dash(game_id: StringName) -> void:
	_player.set_input_locked(false)
	emit_signal("portal_entered", game_id)

func _close_dash_modal() -> void:
	if _dash_modal != null:
		_dash_modal.queue_free()
		_dash_modal = null

# ------------------------------------------------------------------
# Portal entry — hands off to Main via signal, which builds the
# Combat scene. Combat owns the pre-combat event from there on.
# ------------------------------------------------------------------

func _enter_portal(portal: PortalNode) -> void:
	GameLog.add("Entering %s..." % portal.game_data.display_name, Color(0.6, 1.0, 0.7))
	emit_signal("portal_entered", portal.game_data.id)

# ------------------------------------------------------------------
# Pending outcome from Main (after a combat closes)
# ------------------------------------------------------------------

func _process_combat_outcome(outcome: Dictionary) -> void:
	var was_victory: bool = outcome.get("victory", false)
	var game_id: StringName = StringName(String(outcome.get("game_id", "")))
	if was_victory:
		_handle_victory_for(game_id)
	else:
		_handle_defeat()

func _handle_victory_for(game_id: StringName) -> void:
	if game_id == &"":
		return
	var gd: GameData = Data.get_game(game_id)
	if not GameState.beaten_games.has(game_id):
		GameState.beaten_games.append(game_id)
	if not GameState.visited_games.has(game_id):
		GameState.visited_games.append(game_id)
	GameState.total_games_beaten += 1
	GameState.set_current_game(game_id)
	# Notify item / stat listeners (Harvesting gold payout lives in Stats).
	TriggerBus.emit_signal("game_beaten", {"game_id": game_id})
	if gd != null:
		GameLog.add("Defeated %s." % gd.display_name, Color(0.6, 1.0, 0.6))

	# Amulet reached -> win overlay; skip the play/verify + reward on the last
	# floor (reaching it IS the win). Still rate it first — every beaten game
	# gets a score/notes for the tier list. Record the amulet win (also counts
	# as a beat) for the lifetime stats.
	if game_id == GameState.amulet_game_id:
		GameState.phase = GameState.Phase.WIN
		GameStats.record_amulet_win(game_id)
		_show_rate_modal(game_id, _show_win_overlay)
		return

	# The item reward is granted after the verification screen, so remember
	# which game it represents for the reward roll's launch context.
	_pending_reward_game_id = game_id
	_show_verification_modal(gd)

func _handle_defeat() -> void:
	GameLog.add("---- Run ended ----", Color(0.9, 0.7, 0.7))
	# Delete the named save so a dead run can't be reloaded.
	if GameState.save_name != "":
		SaveSystem.delete_named(GameState.save_name)
	SaveSystem.delete_slot(0)
	# Defeat sends the player back to the main menu — picking another
	# start/amulet pair is a menu action, not an overworld one.
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

func _save_run() -> bool:
	# Prefer the run's named save (set on New Game). Fall back to slot 0
	# for the debug-bootstrap flow that runs scenes/Main.tscn directly.
	if GameState.save_name != "":
		return SaveSystem.save_named(GameState.save_name)
	return SaveSystem.save(0)

# ------------------------------------------------------------------
# Verification modal — honour-system prompt after each beaten game.
# ------------------------------------------------------------------

# Skipping the real game costs this fraction of MAX HP (rounded up) and saddles
# the player with a random curse — no reward.
const VERIFICATION_SKIP_HP_PERCENT := 20

# The HP the skip currently costs, given the player's max HP.
func _verification_skip_hp_cost() -> int:
	return ceili(GameState.max_hp * VERIFICATION_SKIP_HP_PERCENT / 100.0)

# Per-weapon Yes/No state held while the modal is open. Populated when
# the modal builds the weapon section; consumed by _on_verification_yes
# at submit time. Keyed by weapon's instance_id.
var _weapon_verify_answers: Dictionary = {}

# Yes/No state for the optional perfect-game and level-up questions on the
# verification modal. Default false (No) so an unanswered question grants
# nothing. Reset each time the modal opens.
var _perfect_answer: bool = false
var _levelup_answer: bool = false

# Per-active-curse "did you fulfil it?" answers, curse id -> bool (true = fulfilled).
# Default true so inaction isn't a penalty; a No on submit drops the penalty card.
var _curse_verify_answers: Dictionary = {}

func _show_verification_modal(gd: GameData) -> void:
	if _verification_modal != null:
		return
	_player.set_input_locked(true)
	_weapon_verify_answers = {}
	_perfect_answer = false
	_levelup_answer = false
	_curse_verify_answers = {}

	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	modal.add_child(dim)

	# Optional extra question rows: the "perfect game" row is always shown
	# (beating without losing a run pays a flat gold bonus); the "level up"
	# row appears when the character has a level-up condition.
	var show_perfect: bool = true
	var char_data: CharacterData = Data.get_character(GameState.character_id)
	var show_levelup: bool = char_data != null and char_data.level_up_condition != ""

	# Inventory weapons drive the modal height — base 400 (title + prompt +
	# the Play/Save action row) + a row per weapon. The list keeps growing as
	# weapon items get authored, so we size from data rather than hard-coding
	# for two. Perfect and level-up rows add their own 80px slices.
	var weapons: Array = _collect_inventory_weapons()
	# Active restriction curses each get a "did you fulfil it?" row — a No drops
	# the curse's penalty card.
	var curses: Array = GameState.active_restriction_curses()
	var extra_rows: int = weapons.size() + int(show_perfect) + int(show_levelup) + curses.size()
	var panel_h: int = 400 + extra_rows * 80

	var panel := Panel.new()
	panel.size = Vector2(620, panel_h)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	modal.add_child(panel)

	var gd_name: String = gd.display_name if gd != null else "this game"

	var title := Label.new()
	title.position = Vector2(20, 24)
	title.size = Vector2(580, 32)
	title.text = "Play %s" % gd_name
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var prompt := Label.new()
	prompt.position = Vector2(20, 72)
	prompt.size = Vector2(580, 70)
	prompt.text = "You cleared this floor's representation of %s. Go play the real game — then verify below to claim your reward." % gd_name
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(prompt)

	# Play-the-real-game + safe-save row. The real game can take a while to
	# beat, so the player can launch it straight from here and save the run so
	# they can quit and resume later without losing progress.
	var action_y: int = 150
	if gd != null and gd.has_launch_target():
		var play_btn := Button.new()
		play_btn.position = Vector2(40, action_y)
		play_btn.size = Vector2(360, 44)
		play_btn.text = "▶ Play %s" % gd_name
		play_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		play_btn.pressed.connect(_on_verification_play.bind(gd))
		panel.add_child(play_btn)

	var save_btn := Button.new()
	save_btn.position = Vector2(420, action_y)
	save_btn.size = Vector2(160, 44)
	save_btn.text = "Save run"
	save_btn.pressed.connect(_on_verification_save)
	panel.add_child(save_btn)

	# Opt-in rating — never forced. Sits in the panel's top-right corner so the
	# player can score the game whenever they like (or update a prior rating).
	var rate_btn := Button.new()
	rate_btn.position = Vector2(450, 20)
	rate_btn.size = Vector2(150, 30)
	rate_btn.text = "★ Rate this game"
	rate_btn.add_theme_font_size_override("font_size", 13)
	rate_btn.pressed.connect(func(): _show_rate_modal(gd.id if gd != null else &"", func(): pass))
	panel.add_child(rate_btn)

	# Weapon questions stack below the Play/Save row. Each row exposes a
	# Yes / No pair whose pressed handler writes into _weapon_verify_answers.
	var y: int = 210
	for w in weapons:
		_add_weapon_row(panel, w, y)
		y += 80

	if show_perfect:
		_add_question_row(panel,
			"Did you Perfect this game? (beat it without losing a run) — +%d gold" % PERFECT_GOLD_BONUS,
			y, func(value: bool): _perfect_answer = value)
		y += 80

	if show_levelup:
		var lvl_text: String = "Level Up (Lv.%d) — %s" % [
			GameState.player_level, char_data.level_up_condition]
		_add_question_row(panel, lvl_text, y,
			func(value: bool): _levelup_answer = value)
		y += 80

	# Active curses: "did you honour this restriction?" Default Yes; a No on
	# submit inflicts the curse's penalty card. The curse itself stays active.
	for cu in curses:
		var cid: StringName = cu.id
		_add_question_row(panel,
			"%s — %s  (Fulfilled?)" % [cu.display_name, cu.challenge],
			y, func(value: bool): _curse_verify_answers[cid] = value, true)
		y += 80

	var yes_btn := Button.new()
	yes_btn.position = Vector2(40, panel_h - 80)
	yes_btn.size = Vector2(260, 56)
	yes_btn.text = "Confirm"
	yes_btn.pressed.connect(_on_verification_yes)
	panel.add_child(yes_btn)

	var skip_btn := Button.new()
	skip_btn.position = Vector2(320, panel_h - 80)
	skip_btn.size = Vector2(260, 56)
	skip_btn.text = "Skip  (-%d HP, +Curse)" % _verification_skip_hp_cost()
	skip_btn.pressed.connect(_on_verification_skip)
	panel.add_child(skip_btn)

	add_child(modal)
	_verification_modal = modal

# Launches the real game from the verification screen. Mirrors RewardScreen's
# "Play the real game" button — the launch now lives here, on the screen shown
# before the item reward.
func _on_verification_play(gd: GameData) -> void:
	if gd == null:
		return
	if gd.launch():
		GameLog.add("Launching %s…" % gd.display_name, Color(0.6, 1.0, 0.8))
	else:
		GameLog.add("Couldn't launch %s — check the file path." % gd.display_name,
			Color(1.0, 0.6, 0.6))

# Saves the run from the verification screen so the player can quit and resume
# while the real game (which can take a while) is being played.
func _on_verification_save() -> void:
	if _save_run():
		GameLog.add("Saved. Safe to quit and resume later.", Color(0.7, 0.9, 1.0))
		Notifications.notify("Run saved — safe to quit.", Color(0.7, 0.9, 1.0))
	else:
		GameLog.add("Save failed.", Color(0.9, 0.5, 0.5))

func _collect_inventory_weapons() -> Array:
	# Equipped weapon isn't a verification target today (no card-link
	# pairing in inventory); only inventory weapon items count.
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.kind == ItemData.ItemKind.WEAPON and not it.verification_effects.is_empty():
			out.append(it)
	return out

func _add_weapon_row(panel: Panel, weapon: ItemData, y: int) -> void:
	var label := Label.new()
	label.position = Vector2(20, y)
	label.size = Vector2(580, 24)
	var lvl_suffix: String = (" (Lv%d)" % weapon.weapon_level) if weapon.weapon_level > 1 else ""
	label.text = "%s%s — %s" % [weapon.display_name, lvl_suffix, weapon.verification_question]
	panel.add_child(label)

	var group := ButtonGroup.new()

	var yes := Button.new()
	yes.position = Vector2(20, y + 28)
	yes.size = Vector2(120, 40)
	yes.text = "Yes"
	yes.toggle_mode = true
	yes.button_group = group
	yes.toggled.connect(func(pressed: bool): _on_weapon_answer(weapon.instance_id, true, pressed))
	panel.add_child(yes)

	var no := Button.new()
	no.position = Vector2(150, y + 28)
	no.size = Vector2(120, 40)
	no.text = "No"
	no.toggle_mode = true
	no.button_group = group
	no.button_pressed = true
	no.toggled.connect(func(pressed: bool): _on_weapon_answer(weapon.instance_id, false, pressed))
	panel.add_child(no)
	# Default: No, so failing to answer doesn't grant a free bonus.
	_weapon_verify_answers[weapon.instance_id] = false

func _on_weapon_answer(weapon_id: int, value: bool, pressed: bool) -> void:
	if pressed:
		_weapon_verify_answers[weapon_id] = value

# Generic Yes/No toggle row used by the perfect-game, level-up and curse
# questions. `setter` receives the chosen bool whenever a button is pressed.
# `default_value` is the pre-selected answer (No for reward questions so an
# unanswered one grants nothing; Yes for curses so inaction isn't a penalty).
func _add_question_row(panel: Panel, text: String, y: int, setter: Callable, default_value: bool = false) -> void:
	var label := Label.new()
	label.position = Vector2(20, y)
	label.size = Vector2(580, 24)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(label)

	var group := ButtonGroup.new()

	var yes := Button.new()
	yes.position = Vector2(20, y + 28)
	yes.size = Vector2(120, 40)
	yes.text = "Yes"
	yes.toggle_mode = true
	yes.button_group = group
	yes.button_pressed = default_value
	yes.toggled.connect(func(pressed: bool):
		if pressed:
			setter.call(true))
	panel.add_child(yes)

	var no := Button.new()
	no.position = Vector2(150, y + 28)
	no.size = Vector2(120, 40)
	no.text = "No"
	no.toggle_mode = true
	no.button_group = group
	no.button_pressed = not default_value
	no.toggled.connect(func(pressed: bool):
		if pressed:
			setter.call(false))
	panel.add_child(no)
	setter.call(default_value)

func _on_verification_yes() -> void:
	GameLog.add("Verified.", Color(0.7, 1.0, 0.7))
	# Only a verified beat counts toward the lifetime tally — skipping the real
	# game (the other branch) deliberately doesn't.
	GameStats.record_beaten(_pending_reward_game_id)
	_apply_weapon_verification_rewards()
	_resolve_perfect_game()
	_resolve_curse_penalties()
	_close_verification()
	# Rate the game right after the play/verify screen, then resume. Level-up
	# can open its own (async) reward UI, so we hand it a callback that finishes
	# verification once the whole level-up chain resolves.
	_show_rate_modal(_pending_reward_game_id, func() -> void:
		_resolve_level_up(_after_verification))

func _apply_weapon_verification_rewards() -> void:
	# Walk inventory weapons; for each Yes, dispatch verification_effects
	# through EffectSystem with the item's instance_id + weapon_level in
	# context. Handlers (bump_card_effect) read those to find the paired
	# CardInstance and apply the per-level bonus.
	for it in GameState.inventory:
		if not (it is ItemData) or it.kind != ItemData.ItemKind.WEAPON:
			continue
		if not _weapon_verify_answers.get(it.instance_id, false):
			continue
		var ctx: Dictionary = {
			"source": null, "target": null, "scene": null, "card": null,
			"source_weapon_instance_id": it.instance_id,
			"level": it.weapon_level,
		}
		for eff in it.verification_effects:
			EffectSystem.apply(eff, ctx)
		GameLog.add("%s: earned reward!" % it.display_name, Color(1.0, 0.7, 0.3))

# For each active curse the player admitted they FAILED (answered No), drop its
# penalty card into the deck. The curse stays active (semi-permanent), so it's
# re-asked next game.
func _resolve_curse_penalties() -> void:
	for cid in _curse_verify_answers.keys():
		if _curse_verify_answers[cid]:
			continue   # fulfilled — no penalty
		var curse: CurseData = Data.get_curse(StringName(cid))
		if curse == null:
			continue
		var card: CardData = GameState.penalty_card_for(curse)
		if card != null:
			GameState.add_card_to_deck(card)
			GameLog.add("Failed %s — %s added to your deck." % [curse.display_name, card.display_name],
				Color(0.85, 0.6, 0.85))
			Notifications.notify("Curse penalty: %s" % card.display_name, Color(0.85, 0.6, 0.85))

# ------------------------------------------------------------------
# Perfect-game verification — "beat without losing a run".
# ------------------------------------------------------------------

# Flat gold paid out whenever the player perfects a game. Perfect-aware
# items (Clown Shoes et al) stack their own rewards on top of this.
const PERFECT_GOLD_BONUS := 10

# Reads the perfect question answer, applies Clown-Shoes-style saves, records
# the outcome on GameState, pays the flat gold bonus, and fires every
# perfect-aware item's reward. Asked after every game.
func _resolve_perfect_game() -> void:
	var perfected: bool = _perfect_answer
	# Clown Shoes: each copy gets a chance to upgrade a "No" into a perfect.
	if not perfected:
		for it in GameState.inventory:
			if not (it is ItemData) or it.perfect_save_chance <= 0.0:
				continue
			if randf() < it.perfect_save_chance:
				perfected = true
				Notifications.notify("%s: treated as a Perfect!" % it.display_name,
					Color(1.0, 0.85, 0.3))
				break
	GameState.last_game_perfected = perfected
	if not perfected:
		GameLog.add("Not a perfect game.", Color(0.7, 0.7, 0.7))
		return
	GameState.change_gold(PERFECT_GOLD_BONUS)
	GameLog.add("Perfect game! +%d gold." % PERFECT_GOLD_BONUS, Color(1.0, 0.85, 0.3))
	# Fire every perfect-aware item's reward effects (scene-less context).
	var ctx: Dictionary = {"source": null, "target": null, "scene": null, "card": null}
	for it in GameState.inventory:
		if it is ItemData and it.perfect_aware and not it.perfect_effects.is_empty():
			EffectSystem.apply_all(it.perfect_effects, ctx)
			GameLog.add("%s: earned reward!" % it.display_name, Color(1.0, 0.7, 0.3))

# ------------------------------------------------------------------
# Level-up — character-specific stats + reward, with Crown bonus chance.
# ------------------------------------------------------------------

# Runs the level-up chain if the player answered Yes, then calls on_done.
# Always invokes on_done exactly once (synchronously when there's no level-up,
# asynchronously when a reward UI is involved).
func _resolve_level_up(on_done: Callable) -> void:
	var char_data: CharacterData = Data.get_character(GameState.character_id)
	if char_data == null or char_data.level_up_condition == "" or not _levelup_answer:
		on_done.call()
		return
	_level_up_once(char_data, on_done)

# Applies one level-up (stats + reward), then rolls the Crown bonus: on a hit
# it recurses for another level, otherwise calls on_done.
func _level_up_once(char_data: CharacterData, on_done: Callable) -> void:
	GameState.player_level += 1
	var applied: Array = GameState.apply_level_up_stats(char_data.level_up_stats)
	var summary: String = (": " + ", ".join(applied)) if not applied.is_empty() else ""
	GameLog.add("Level Up! (Lv.%d)%s" % [GameState.player_level, summary],
		Color(1.0, 0.85, 0.3))
	Notifications.notify("Level Up! Lv.%d" % GameState.player_level, Color(1.0, 0.85, 0.3))
	_grant_level_up_reward(char_data, func():
		if _roll_bonus_level_up():
			Notifications.notify("Crown: Bonus Level Up!", Color(1.0, 0.85, 0.3))
			_level_up_once(char_data, on_done)
		else:
			on_done.call())

# Grants the character's level-up reward. Simple rewards resolve inline;
# `item` opens a RewardScreen and defers on_done to its closed signal.
func _grant_level_up_reward(char_data: CharacterData, on_done: Callable) -> void:
	match String(char_data.level_up_reward_type):
		"gold":
			var amount: int = maxi(0, char_data.level_up_reward_amount)
			GameState.change_gold(amount)
			GameLog.add("Level-up reward: +%d gold." % amount, Color(1.0, 0.9, 0.3))
			on_done.call()
		"scroll_and_potion":
			GameState.add_loot("scroll", 1)
			GameState.add_loot("potion", 1)
			GameLog.add("Level-up reward: +1 Scroll, +1 Potion.", Color(0.8, 0.9, 1.0))
			on_done.call()
		"card":
			_show_level_up_card_reward(char_data.level_up_card_tag, on_done)
		"item":
			_show_level_up_item_reward(on_done)
		_:
			on_done.call()

func _show_level_up_card_reward(tag_filter: StringName, on_done: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var reward := CardRewardScreen.new()
	layer.add_child(reward)
	reward.closed.connect(func():
		layer.queue_free()
		on_done.call())
	reward.setup(tag_filter)

func _show_level_up_item_reward(on_done: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var reward := RewardScreen.new()
	layer.add_child(reward)
	reward.closed.connect(func():
		layer.queue_free()
		on_done.call())
	# No gold component — the level-up gold table is separate (this is the
	# item-choice reward only).
	reward.setup(0)

# Rolls every Crown-style item's bonus_level_up_chance; returns true if any hit.
func _roll_bonus_level_up() -> bool:
	for it in GameState.inventory:
		if it is ItemData and it.bonus_level_up_chance > 0.0:
			if randf() < it.bonus_level_up_chance:
				return true
	return false

func _on_verification_skip() -> void:
	var cost: int = _verification_skip_hp_cost()
	GameState.change_hp(-cost)
	# Skipping the real game also saddles the player with a random curse.
	var curse: CurseData = GameState.add_active_curse(GameState.random_curse())
	var curse_name: String = curse.display_name if curse != null else "a curse"
	GameLog.add("Skipped real game. (-%d HP, gained %s)" % [cost, curse_name],
		Color(0.9, 0.6, 0.4))
	_close_verification()
	if GameState.is_dead():
		_handle_defeat()
		return
	# Rating is opt-in (the "★ Rate this game" button on the verification
	# screen), so skipping just proceeds to the reward flow.
	_after_verification()

func _close_verification() -> void:
	if _verification_modal != null:
		_verification_modal.queue_free()
		_verification_modal = null

# Opt-in rate-out-of-10 + notes prompt, opened from the "★ Rate this game"
# button on the verification screen. Records the rating in the cross-run
# TierList (also dropping the game into the Unranked tray the first time) and
# then runs `continuation`. Dismissing ("Maybe later") just runs `continuation`
# without recording anything.
func _show_rate_modal(game_id: StringName, continuation: Callable) -> void:
	if game_id == &"":
		continuation.call()
		return
	if _rate_modal != null:
		return
	var gd: GameData = Data.get_game(game_id)
	var modal := RateGameModal.new()
	modal.setup(game_id, gd)
	var close_modal := func() -> void:
		if _rate_modal != null:
			_rate_modal.queue_free()
			_rate_modal = null
	modal.submitted.connect(func(score: int, notes: String) -> void:
		TierList.set_rating(game_id, score, notes)
		close_modal.call()
		continuation.call())
	modal.dismissed.connect(func() -> void:
		close_modal.call()
		continuation.call())
	_rate_modal = modal
	add_child(modal)

func _after_verification() -> void:
	_save_run()
	GameLog.add("Autosaved.", Color(0.7, 0.8, 1.0))
	# Item reward (gold + one item choice) comes *after* the play/verify screen.
	_show_section_reward(_pending_reward_game_id)

# ------------------------------------------------------------------
# Section reward — gold + one item choice, shown after verification. The
# launch button on the reward screen stays hidden here (the "Play the real
# game" action lives on the verification screen that preceded this), so the
# reward is purely about claiming loot.
# ------------------------------------------------------------------

func _show_section_reward(_game_id: StringName) -> void:
	var tier: int = RunDifficulty.current_tier()
	var gold: int = SECTION_GOLD_BY_TIER[clampi(tier, 0, SECTION_GOLD_BY_TIER.size() - 1)]
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_section_reward_layer = layer
	var reward := RewardScreen.new()
	layer.add_child(reward)
	reward.closed.connect(_on_section_reward_closed)
	reward.setup(gold)

func _on_section_reward_closed() -> void:
	if _section_reward_layer != null:
		_section_reward_layer.queue_free()
		_section_reward_layer = null
	_pending_reward_game_id = &""
	_save_run()
	GameState.phase = GameState.Phase.OVERWORLD
	_player.set_input_locked(false)
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_spawn_portals_for_current_game()
	_update_hint()
	# A section reward can have minted chests indirectly (an item picked there
	# that removes a curse, etc.); drain them now that we're idle again.
	_redeem_pending_chests()

# ------------------------------------------------------------------
# Chests — the project's term for an item reward. Golden Beetle banks one
# whenever a curse or curse card is removed; we redeem each into a gold-less
# item-choice screen, one at a time, whenever the overworld is idle.
# ------------------------------------------------------------------

func _on_chest_granted(_ctx: Dictionary) -> void:
	# Only redeem inline when nothing else owns the screen. If a modal/reward is
	# up, the chest stays banked and is drained when that flow closes (or on the
	# next idle overworld entry).
	if _can_act():
		_redeem_pending_chests()

func _redeem_pending_chests() -> void:
	if _chest_reward_layer != null or not _can_act():
		return
	if not GameState.take_pending_chest():
		return
	_player.set_input_locked(true)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_chest_reward_layer = layer
	var reward := RewardScreen.new()
	layer.add_child(reward)
	reward.closed.connect(_on_chest_reward_closed)
	# Gold-less: a chest is purely an item choice.
	reward.setup(0)

func _on_chest_reward_closed() -> void:
	if _chest_reward_layer != null:
		_chest_reward_layer.queue_free()
		_chest_reward_layer = null
	_player.set_input_locked(false)
	_save_run()
	# More banked? Redeem the next one (chest screens chain until empty).
	if GameState.pending_chests > 0:
		call_deferred("_redeem_pending_chests")

# ------------------------------------------------------------------
# Win overlay (Amulet reached)
# ------------------------------------------------------------------

func _show_win_overlay() -> void:
	if _win_overlay != null:
		return
	_player.set_input_locked(true)
	# Delete the autosave so a finished run can't be reloaded into.
	SaveSystem.delete_slot(0)
	if GameState.save_name != "":
		SaveSystem.delete_named(GameState.save_name)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.05, 0.02, 0.85)
	overlay.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(640, 360)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	overlay.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 32)
	title.size = Vector2(600, 64)
	title.text = "RUN COMPLETE"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(20, 108)
	subtitle.size = Vector2(600, 32)
	subtitle.text = "You reached the Amulet."
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subtitle)

	var stats := Label.new()
	stats.position = Vector2(20, 160)
	stats.size = Vector2(600, 64)
	stats.text = "Floors cleared: %d   HP: %d / %d   Gold: %d" % [
		GameState.total_games_beaten,
		GameState.hp, GameState.max_hp, GameState.gold,
	]
	stats.add_theme_font_size_override("font_size", 16)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(stats)

	var btn := Button.new()
	btn.position = Vector2(220, 270)
	btn.size = Vector2(200, 56)
	btn.text = "New Run"
	btn.pressed.connect(_on_new_run_pressed)
	panel.add_child(btn)

	add_child(overlay)
	_win_overlay = overlay

func _on_new_run_pressed() -> void:
	if _win_overlay != null:
		_win_overlay.queue_free()
		_win_overlay = null
	# New run flow is the menu's job — start/amulet/character selection
	# happen there, not here.
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
