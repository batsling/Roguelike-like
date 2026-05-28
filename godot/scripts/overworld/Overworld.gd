class_name Overworld
extends Node2D

# Overworld scene. Owns walking + portal selection + verification +
# autosave + win/lose UI. Does NOT own combat — Main creates the combat
# scene when this scene emits portal_entered.
#
# On scene init the pending_combat_outcome field (set by Main before
# add_child) tells us "you just came back from a combat: it was a
# victory/defeat for game X." That kicks off the verification flow or
# the defeat reset.

const TILE_SIZE := 32
const GRID_W := 30
const GRID_H := 18

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
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_floor_bg.size = Vector2(GRID_W * TILE_SIZE, GRID_H * TILE_SIZE)
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_player.moved.connect(_on_player_moved)
	GameState.phase = GameState.Phase.OVERWORLD
	_spawn_portals_for_current_game()
	_update_hint()
	# Process whatever Main just handed us (combat result), if any.
	if not pending_combat_outcome.is_empty():
		var outcome := pending_combat_outcome
		pending_combat_outcome = {}
		call_deferred("_process_combat_outcome", outcome)

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
	var target_count: int = maxi(1, BASE_PORTAL_COUNT + GameState.fov_bonus)
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
	# Undirected: outgoing edges + games that influenced this one.
	var result: Array[StringName] = []
	var src: GameData = Data.get_game(game_id)
	if src != null:
		for gid in src.games_influenced:
			if Data.get_game(gid) != null and not result.has(gid):
				result.append(gid)
	for g in Data.all_games():
		if g.id == game_id:
			continue
		for influenced_id in g.games_influenced:
			if influenced_id == game_id and not result.has(g.id):
				result.append(g.id)
	return result

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
	actions += "   |   [R] Reroll (%d)   |   [Q] Dash (%d)" % [
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
	return _verification_modal == null and _win_overlay == null and _dash_modal == null

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
	if gd != null:
		GameLog.add("Defeated %s." % gd.display_name, Color(0.6, 1.0, 0.6))

	# Amulet reached -> win overlay; skip verification on the last floor.
	if game_id == GameState.amulet_game_id:
		GameState.phase = GameState.Phase.WIN
		_show_win_overlay()
		return

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

const VERIFICATION_SKIP_HP_PENALTY := 33

# Per-weapon Yes/No state held while the modal is open. Populated when
# the modal builds the weapon section; consumed by _on_verification_yes
# at submit time. Keyed by weapon's instance_id.
var _weapon_verify_answers: Dictionary = {}

func _show_verification_modal(gd: GameData) -> void:
	if _verification_modal != null:
		return
	_player.set_input_locked(true)
	_weapon_verify_answers = {}

	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	modal.add_child(dim)

	# Inventory weapons drive the modal height — base 340 + a row per
	# weapon. The list keeps growing as weapon items get authored, so we
	# size from data rather than hard-coding for two.
	var weapons: Array = _collect_inventory_weapons()
	var panel_h: int = 340 + weapons.size() * 80

	var panel := Panel.new()
	panel.size = Vector2(620, panel_h)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	modal.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 24)
	title.size = Vector2(580, 32)
	title.text = "Verification"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var prompt := Label.new()
	prompt.position = Vector2(20, 72)
	prompt.size = Vector2(580, 70)
	var gd_name: String = gd.display_name if gd != null else "this game"
	prompt.text = "You defeated this floor's representation of %s. Did you play the real game?" % gd_name
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(prompt)

	# Weapon questions stack below the main prompt. Each row exposes a
	# Yes / No pair whose pressed handler writes into _weapon_verify_answers.
	var y: int = 150
	for w in weapons:
		_add_weapon_row(panel, w, y)
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
	skip_btn.text = "Skip  (-%d HP)" % VERIFICATION_SKIP_HP_PENALTY
	skip_btn.pressed.connect(_on_verification_skip)
	panel.add_child(skip_btn)

	add_child(modal)
	_verification_modal = modal

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

func _on_verification_yes() -> void:
	GameLog.add("Verified.", Color(0.7, 1.0, 0.7))
	_apply_weapon_verification_rewards()
	_close_verification()
	_after_verification()

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

func _on_verification_skip() -> void:
	GameState.change_hp(-VERIFICATION_SKIP_HP_PENALTY)
	GameLog.add("Skipped real game. (-%d HP)" % VERIFICATION_SKIP_HP_PENALTY,
		Color(0.9, 0.6, 0.4))
	_close_verification()
	if GameState.is_dead():
		_handle_defeat()
		return
	_after_verification()

func _close_verification() -> void:
	if _verification_modal != null:
		_verification_modal.queue_free()
		_verification_modal = null

func _after_verification() -> void:
	_save_run()
	GameLog.add("Autosaved.", Color(0.7, 0.8, 1.0))
	GameState.phase = GameState.Phase.OVERWORLD
	_player.set_input_locked(false)
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_spawn_portals_for_current_game()
	_update_hint()

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
