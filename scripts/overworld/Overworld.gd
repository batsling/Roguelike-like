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

# How close (px) the freely-moving player must be to a door for it to become the
# active portal — about 1.5 tiles, so walking up to a door selects it.
const PORTAL_ACTIVATE_RADIUS := 48.0

signal portal_entered(game_id: StringName)
# Movement encounter: the player chose to fight the gate elite. Main launches the
# combat in `engine`, then re-opens the overworld with an encounter_combat outcome
# so the queued teleport (GameState.pending_encounter) resolves on victory.
signal encounter_elite_requested(engine: String)

@onready var _floor_bg: ColorRect = $Floor
@onready var _player: PlayerWalker = $Player
@onready var _hint: Label = $Hint

# Set by Main before add_child so the new scene knows what just
# happened. Empty {} means "no pending — fresh entry".
var pending_combat_outcome: Dictionary = {}

const BASE_PORTAL_COUNT := 3

var _portals: Array[PortalNode] = []
var _active_portal: PortalNode = null
# Full-screen selection modals (dash / verification / win / map / rate) live on
# this layer so they draw ABOVE the HUD's bottom log — added as plain children
# of the Node2D root they'd sit on the default canvas (layer 0) and the HUD
# CanvasLayer (layer 1) would render its log in front of their buttons.
var _modal_layer: CanvasLayer = null
var _win_overlay: Control = null
var _game_over_overlay: Control = null
var _verification_modal: Control = null
var _dash_modal: Control = null
# Winged Boots (overworld active): the same-year picker modal + the item being
# spent, so we can consume a use only when the player commits to a destination.
var _winged_modal: Control = null
var _winged_item: ItemData = null
var _map_view: RunMapView = null
var _section_reward_layer: CanvasLayer = null
var _chest_reward_layer: CanvasLayer = null
var _rate_modal: RateGameModal = null
# Door hover cue + click-to-open preview (game info + a mini run-map re-rooted at
# the hovered game). Hover just highlights; clicking opens the fitted modal.
var _hovered_portal: PortalNode = null
var _door_preview: Control = null
# Overworld encounter (shop / deal / teleporter / challenge) present in the
# current area — at most one, on the left or right. Kept across rerolls (same
# area) and re-rolled on a new area; see _ensure_encounter_for_area.
var _encounter_node: EncounterNode = null
var _active_encounter: EncounterNode = null
var _encounter_modal: EncounterModal = null
var _teleport_modal: Control = null
# The area id the current encounter belongs to, so a reroll keeps it but moving
# to a new game spawns a fresh one.
var _encounter_area_id: StringName = &""
# Game whose section reward is pending — set when a victory is handed to us,
# consumed when the item reward opens after the verification screen.
var _pending_reward_game_id: StringName = &""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Section-clear gold by run difficulty tier lives in CombatEconomy (the economy
# source of truth); awarded by the item-reward screen that follows the "Play the
# real game" verification.

func _ready() -> void:
	_rng.randomize()
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 10
	add_child(_modal_layer)
	_fit_background()
	get_viewport().size_changed.connect(_fit_background)
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_apply_player_avatar()
	_player.moved.connect(_on_player_moved)
	GameState.phase = GameState.Phase.OVERWORLD
	# Register so overworld_usable items (Winged Boots) fired from the backpack /
	# HUD route their item_used effect here (see GameState.use_item).
	GameState.set_overworld_context(self)
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

# Scroll of Teleportation: jump to another game chosen by BFS distance to the
# amulet (called by ScrollUseModal when a teleport request resolves on the
# overworld). `dir` is closer / same / farther / random; `max_steps` bounds how
# far the closer/farther jump moves relative to the current distance (0 = no
# bound). Mirrors the legacy _scrollTeleport pool selection.
func scroll_teleport(dir: String, max_steps: int) -> void:
	var amulet: StringName = GameState.amulet_game_id
	var current: StringName = GameState.current_game_id
	# Distance from the amulet to every reachable game == distance-to-amulet.
	var dist: Dictionary = {} if amulet == &"" else RunGraph.bfs_distances(amulet)
	var candidates: Array = []
	for gid in dist.keys():
		if gid != current and not GameState.beaten_games.has(gid):
			candidates.append(gid)
	if candidates.is_empty():
		Notifications.notify("The Scroll of Teleportation finds nowhere to send you.", ScrollSystem.SCROLL_COLOR)
		return
	var cur_dist: int = int(dist.get(current, 0))
	var pool: Array = []
	match dir:
		"closer":
			pool = candidates.filter(func(g): return int(dist[g]) < cur_dist and (max_steps <= 0 or cur_dist - int(dist[g]) <= max_steps))
			if pool.is_empty():
				pool = candidates.filter(func(g): return int(dist[g]) < cur_dist)
		"farther":
			pool = candidates.filter(func(g): return int(dist[g]) > cur_dist and (max_steps <= 0 or int(dist[g]) - cur_dist <= max_steps))
			if pool.is_empty():
				pool = candidates.filter(func(g): return int(dist[g]) > cur_dist)
		"same":
			pool = candidates.filter(func(g): return int(dist[g]) == cur_dist)
		_: # random
			pool = candidates
	if pool.is_empty():
		pool = candidates
	var target: StringName = pool[_rng.randi_range(0, pool.size() - 1)]
	GameState.set_current_game(target)
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_apply_player_avatar()
	_spawn_portals_for_current_game()
	_update_hint()
	var gd: GameData = Data.get_game(target)
	Notifications.notify("Teleported to %s!" % (gd.display_name if gd != null else String(target)),
		ScrollSystem.SCROLL_COLOR)

func _spawn_portals_for_current_game() -> void:
	_close_door_preview()
	_hovered_portal = null
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
	# Curse of Shroud: space choices contain one fewer option per copy held.
	var shroud_reduction: int = 0
	for shroud in GameState.active_affliction_effects("reduce_choices"):
		shroud_reduction += int(shroud.get("value", 1))
	target_count = maxi(1, target_count - shroud_reduction)
	target_count = mini(target_count, ids.size())
	var chosen: Array[StringName] = []
	for i in range(target_count):
		chosen.append(ids[i])

	_place_portals(chosen)

	GameLog.add("At %s. %d portals open." % [current.display_name, _portals.size()],
		Color(0.8, 0.9, 1.0))

	# Every area also hosts one encounter. Kept across rerolls (same area id),
	# re-rolled when we've moved to a different game.
	_ensure_encounter_for_area()

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
# Door hover preview — game info + a mini run-map re-centered on the hovered
# game, so you can see what it is and where it leads before committing.
# ------------------------------------------------------------------

# Polled each frame: highlight whichever door the mouse is over so the player
# knows it's clickable. Suppressed while a preview / modal is up or the walker is
# locked.
func _process(_delta: float) -> void:
	var locked: bool = _door_preview != null or (_player != null and _player.is_input_locked())
	var mouse: Vector2 = get_global_mouse_position()
	var new_hover: PortalNode = null
	if not locked:
		for p in _portals:
			if p.game_data != null and p.door_global_rect().has_point(mouse):
				new_hover = p
				break
	if new_hover == _hovered_portal:
		return
	if _hovered_portal != null and is_instance_valid(_hovered_portal):
		_hovered_portal.set_hovered(false)
	_hovered_portal = new_hover
	if _hovered_portal != null:
		_hovered_portal.set_hovered(true)

# Click-opened door preview: a centered, scrollable modal with the game's info
# and a mini run-map re-rooted at it. Sized to fit the viewport so the map never
# spills off-screen; the map scrolls if it's taller than the panel.
func _open_door_preview(game_id: StringName) -> void:
	_close_door_preview()
	var gd: GameData = Data.get_game(game_id)
	if gd == null:
		return
	if _player != null:
		_player.set_input_locked(true)
	if _hovered_portal != null and is_instance_valid(_hovered_portal):
		_hovered_portal.set_hovered(false)
		_hovered_portal = null

	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	modal.add_child(dim)

	var vp: Vector2 = get_viewport_rect().size
	var panel_w: float = minf(720.0, vp.x - 80.0)
	var panel_h: float = minf(640.0, vp.y - 80.0)
	var panel := PanelContainer.new()
	# custom_minimum_size pins the size (a Container otherwise shrinks to content).
	panel.custom_minimum_size = Vector2(panel_w, panel_h)
	panel.size = Vector2(panel_w, panel_h)
	panel.position = ((vp - panel.size) / 2.0).floor()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.12, 0.99)
	sb.border_color = Color(0.5, 0.4, 0.7, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	modal.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = gd.display_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	header.add_child(title)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(_close_door_preview)
	header.add_child(close)

	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	info.text = _preview_info_text(gd, game_id)
	vbox.add_child(info)

	if GameState.start_game_id != &"" and GameState.amulet_game_id != &"":
		var hdr := Label.new()
		hdr.text = "Map if you enter:"
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		vbox.add_child(hdr)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(scroll)
		var mini := MapGraphView.new()
		# Re-root the route at this game so the map shows where it leads onward.
		mini.build(game_id, GameState.amulet_game_id, game_id, "IF YOU ENTER")
		var bw: float = mini.get_base_size().x
		if bw > 0.0:
			mini.set_zoom(clampf((panel_w - 44.0) / bw, MapGraphView.ZOOM_MIN, 1.0))
		scroll.add_child(mini)

	_modal_layer.add_child(modal)
	_door_preview = modal

func _close_door_preview() -> void:
	if _door_preview != null:
		_door_preview.queue_free()
		_door_preview = null
		if _player != null:
			_player.set_input_locked(false)

func _preview_info_text(gd: GameData, game_id: StringName) -> String:
	var lines: Array = []
	if gd.year > 0:
		lines.append("Year: %d" % gd.year)
	lines.append("Type: %s" % RunGraph.type_label(gd.type))
	var tags: Array = []
	for t in gd.tags:
		tags.append(String(t))
	if not tags.is_empty():
		lines.append("Tags: %s" % ", ".join(tags))
	lines.append("Connections: %d" % RunGraph.neighbors(game_id).size())
	if game_id == GameState.amulet_game_id:
		lines.append("The Amulet — your goal")
	else:
		var hops: int = int(RunGraph.bfs_distances(game_id).get(GameState.amulet_game_id, -1))
		lines.append("Hops to Amulet: %s" % (str(hops) if hops >= 0 else "—"))
	return "\n".join(lines)

# ------------------------------------------------------------------
# Player interaction
# ------------------------------------------------------------------

func _on_player_moved(_pos: Vector2i) -> void:
	# Free pixel movement: the active door is the nearest portal within reach of
	# the player's actual position (not an exact tile match).
	var prev := _active_portal
	var nearest: PortalNode = null
	var nearest_d := PORTAL_ACTIVATE_RADIUS
	for p in _portals:
		var d: float = _player.position.distance_to(p.position)
		if d <= nearest_d:
			nearest_d = d
			nearest = p
	_active_portal = nearest
	if prev != _active_portal:
		if prev != null:
			prev.set_highlight(false)
		if _active_portal != null:
			_active_portal.set_highlight(true)
	_update_encounter_proximity()
	_update_hint()

# Mirror of the portal proximity check for the (single) area encounter: light it
# up + show its "press E" prompt when the player walks within reach.
func _update_encounter_proximity() -> void:
	var node := _encounter_node
	var near: bool = node != null and is_instance_valid(node) and not node.consumed \
		and _player.position.distance_to(node.position) <= node.activate_radius()
	var new_active: EncounterNode = node if near else null
	if new_active == _active_encounter:
		return
	if _active_encounter != null and is_instance_valid(_active_encounter):
		_active_encounter.set_active(false)
	_active_encounter = new_active
	if _active_encounter != null:
		_active_encounter.set_active(true)

func _update_hint() -> void:
	var actions := "WASD/arrows to walk"
	if _active_encounter != null and is_instance_valid(_active_encounter):
		actions = "[E] %s   |   " % _active_encounter.encounter.display_name + actions
	elif _active_portal != null:
		actions = "[E] Enter %s   |   " % _active_portal.game_data.display_name + actions
	actions += "   |   [R] Reroll (%d)   |   [Q] Dash (%d)   |   [M] Map" % [
		GameState.reroll_charges, GameState.dash_charges,
	]
	_hint.text = actions

func _unhandled_input(event: InputEvent) -> void:
	# Click a door to open its info + map preview.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _door_preview == null and _can_act() \
				and _hovered_portal != null and is_instance_valid(_hovered_portal) \
				and _hovered_portal.game_data != null:
			_open_door_preview(_hovered_portal.game_data.id)
			get_viewport().set_input_as_handled()
		return
	# Esc closes an open door preview before anything else handles it.
	if _door_preview != null and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_close_door_preview()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed):
		return
	if not _can_act():
		return
	if event.keycode == KEY_E and _active_encounter != null and is_instance_valid(_active_encounter):
		_open_encounter_modal()
	elif event.keycode == KEY_E and _active_portal != null:
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
	# Escape is intentionally NOT handled here: it falls through to the shared
	# PauseMenu (mounted by Main) so Esc opens the pause menu rather than bailing
	# straight to the main menu.

func _can_act() -> bool:
	return _verification_modal == null and _win_overlay == null \
		and _game_over_overlay == null and _dash_modal == null \
		and _map_view == null and _section_reward_layer == null \
		and _chest_reward_layer == null and _winged_modal == null \
		and _door_preview == null and _encounter_modal == null \
		and _teleport_modal == null

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
	_modal_layer.add_child(_map_view)

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

	_modal_layer.add_child(modal)
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
# Overworld encounters — one per area (left/right), opened with E.
# ------------------------------------------------------------------

# Spawn weighting by rarity index (Common/Uncommon/Rare/Legendary). Higher =
# appears more often; mirrors the loot rarity bias.
const ENCOUNTER_RARITY_WEIGHT := [8, 4, 2, 1]

# Ensures the current area has its encounter. Same area (a reroll) keeps the
# existing node (so a consumed encounter stays consumed); arriving at a new game
# clears it and rolls a fresh one. "Every area has one" — so we always spawn when
# an eligible encounter exists.
func _ensure_encounter_for_area() -> void:
	if _encounter_node != null and is_instance_valid(_encounter_node) \
			and _encounter_area_id == GameState.current_game_id:
		return
	if _encounter_node != null and is_instance_valid(_encounter_node):
		_encounter_node.queue_free()
	_encounter_node = null
	_active_encounter = null
	_encounter_area_id = GameState.current_game_id

	var enc: EncounterData = _roll_encounter_for_area()
	if enc == null:
		return
	# Random side; sit at mid-height so the walker can reach it from spawn.
	var on_left: bool = _rng.randi() % 2 == 0
	var x: int = 3 if on_left else GRID_W - 4
	@warning_ignore("integer_division")
	var y: int = GRID_H / 2
	var node := EncounterNode.new()
	node.setup(enc, Vector2i(x, y))
	add_child(node)
	_encounter_node = node

# Rarity-weighted pick among encounters whose requirement gate is currently met.
func _roll_encounter_for_area() -> EncounterData:
	var eligible: Array = []
	var weights: Array = []
	for e in Data.all_encounters():
		if not (e is EncounterData):
			continue
		if not GameState.encounter_requirement_met(e.requirement_effect):
			continue
		eligible.append(e)
		var ri: int = clampi(e.rarity_index(), 0, ENCOUNTER_RARITY_WEIGHT.size() - 1)
		weights.append(ENCOUNTER_RARITY_WEIGHT[ri])
	if eligible.is_empty():
		return null
	var total: int = 0
	for w in weights:
		total += int(w)
	var roll: int = _rng.randi_range(1, total)
	for i in range(eligible.size()):
		roll -= int(weights[i])
		if roll <= 0:
			return eligible[i]
	return eligible.back()

func _open_encounter_modal() -> void:
	if _encounter_modal != null or _active_encounter == null:
		return
	_player.set_input_locked(true)
	var modal := EncounterModal.new()
	_encounter_modal = modal
	modal.closed.connect(_on_encounter_modal_closed)
	modal.elite_combat_requested.connect(_on_encounter_elite_requested)
	modal.teleport_requested.connect(_on_encounter_teleport_requested)
	_modal_layer.add_child(modal)
	modal.setup(_active_encounter.encounter, _active_encounter)

func _on_encounter_modal_closed() -> void:
	# A shopkeeper (or any encounter that asked to stay available) is NOT consumed,
	# so it keeps its [E] prompt and isn't greyed out — the player can walk back up
	# and open it again. Its stock persists on the node, so re-opening isn't a free
	# re-roll. One-time encounters (Deals, Challenges) still consume as before.
	var keep: bool = _encounter_modal != null and _encounter_modal.keep_available
	_encounter_modal = null
	if not keep and _active_encounter != null and is_instance_valid(_active_encounter):
		_active_encounter.mark_consumed()
	_active_encounter = null
	_player.set_input_locked(false)
	_update_hint()
	_save_run()
	# An encounter (Deal/Challenge) may have banked an item chest; redeem now.
	_redeem_pending_chests()

# Movement encounter chose to engage: stash the teleport tail and ask Main to run
# the gate-elite combat. The overworld is about to be freed by the scene-swap, so
# we do no further cleanup here.
func _on_encounter_elite_requested(engine: String, resume: Dictionary) -> void:
	_encounter_modal = null
	GameState.pending_encounter = resume
	emit_signal("encounter_elite_requested", engine)

# Pure-teleport encounter (no gate fight): apply immediately.
func _on_encounter_teleport_requested(spec: Dictionary) -> void:
	_apply_encounter_teleport(spec)

# Returns from the gate-elite combat: win -> resolve the queued teleport; loss ->
# end the run like any overworld defeat.
func _resolve_encounter_combat(victory: bool) -> void:
	var resume: Dictionary = GameState.pending_encounter
	GameState.pending_encounter = {}
	if not victory:
		_handle_defeat()
		return
	GameState.phase = GameState.Phase.OVERWORLD
	if resume.has("teleport"):
		_apply_encounter_teleport(resume["teleport"])
	else:
		_spawn_portals_for_current_game()
		_update_hint()

# Applies a parsed teleport effect: a single {dir} jumps now; a {choose:[...]}
# pops a small picker first.
func _apply_encounter_teleport(spec: Dictionary) -> void:
	if spec.has("choose"):
		_show_teleport_choice(spec["choose"])
		return
	_do_encounter_teleport(String(spec.get("dir", "nearby")))

func _do_encounter_teleport(dir: String) -> void:
	# BFS-relative directions reuse the existing scroll teleport; encounter-only
	# directions (nearby / previous) resolve against the run graph + history.
	if dir in ["closer", "farther", "same", "random"]:
		scroll_teleport(dir, 0)
		return
	var target: StringName = _encounter_teleport_target(dir)
	if target == &"":
		Notifications.notify("The portal finds nowhere to send you.", Color(0.7, 0.8, 1.0))
		_spawn_portals_for_current_game()
		_update_hint()
		return
	GameState.set_current_game(target)
	_player.setup(SPAWN_POS, Rect2i(0, 0, GRID_W, GRID_H))
	_apply_player_avatar()
	_spawn_portals_for_current_game()
	_update_hint()
	var gd: GameData = Data.get_game(target)
	Notifications.notify("Teleported to %s!" % (gd.display_name if gd != null else String(target)),
		Color(0.6, 0.9, 1.0))

func _encounter_teleport_target(dir: String) -> StringName:
	var current: StringName = GameState.current_game_id
	match dir:
		"nearby":
			var nbrs: Array = _connected_game_ids(current)
			var pool: Array = nbrs.filter(func(g): return not GameState.beaten_games.has(g))
			if pool.is_empty():
				pool = nbrs
			if pool.is_empty():
				return &""
			return pool[_rng.randi_range(0, pool.size() - 1)]
		"previous":
			# The game visited just before the current one.
			var vg: Array = GameState.visited_games
			var idx: int = vg.find(current)
			if idx > 0:
				return vg[idx - 1]
			for i in range(vg.size() - 1, -1, -1):
				if vg[i] != current:
					return vg[i]
			return &""
		_:
			return &""

func _show_teleport_choice(options: Array) -> void:
	if _teleport_modal != null:
		return
	_player.set_input_locked(true)
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	modal.add_child(dim)
	var panel := Panel.new()
	panel.size = Vector2(420, 80 + options.size() * 52)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	modal.add_child(panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(20, 16)
	vb.size = Vector2(380, panel.size.y - 32)
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Teleport where?"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)
	for opt in options:
		var dir: String = String(opt)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 40)
		btn.text = _teleport_dir_label(dir)
		btn.pressed.connect(func() -> void:
			_close_teleport_modal()
			_do_encounter_teleport(dir)
		)
		vb.add_child(btn)
	_modal_layer.add_child(modal)
	_teleport_modal = modal

func _teleport_dir_label(dir: String) -> String:
	match dir:
		"nearby": return "A nearby connected game"
		"previous": return "Back to the previous game"
		"random": return "A completely random game"
		_: return dir.capitalize()

func _close_teleport_modal() -> void:
	if _teleport_modal != null:
		_teleport_modal.queue_free()
		_teleport_modal = null
	_player.set_input_locked(false)

func _exit_tree() -> void:
	# Hand off the overworld registration when this scene is freed (Main swaps to
	# combat). Guarded so a newly-spawned Overworld that already registered wins.
	GameState.clear_overworld_context(self)

# ------------------------------------------------------------------
# Winged Boots — overworld active. Fired from the backpack / HUD (routed here by
# GameState.use_item -> EffectSystem.overworld_jump). Flies to one of up to
# `count` games sharing the current game's year, then enters it like a Dash. The
# item's use is spent only on a committed pick (consume_item_use), so cancelling
# or finding no destination costs nothing.
# ------------------------------------------------------------------

func begin_overworld_jump(item: ItemData, scope: String, count: int) -> void:
	if _winged_modal != null or _dash_modal != null:
		return
	var current: GameData = Data.get_game(GameState.current_game_id)
	if current == null:
		return
	var ids: Array[StringName] = []
	if scope == "same_year":
		ids = RunGraph.same_year_games(current.id)
	if ids.is_empty():
		GameLog.add("Winged Boots: no other %d games to fly to." % current.year,
			Color(0.9, 0.7, 0.4))
		return
	ids.shuffle()
	if ids.size() > count:
		ids = ids.slice(0, count)
	_winged_item = item
	_show_winged_modal(ids)

func _show_winged_modal(ids: Array[StringName]) -> void:
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
	title.text = "Winged Boots — fly to a same-year game"
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
		btn.text = "%s (%d)" % [gd.display_name, gd.year]
		btn.custom_minimum_size = Vector2(0, 44)
		btn.pressed.connect(_on_winged_pick.bind(gid))
		list.add_child(btn)

	var cancel := Button.new()
	cancel.position = Vector2(panel_w / 2.0 - 80, panel_h - 56)
	cancel.size = Vector2(160, 40)
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_winged_cancel)
	panel.add_child(cancel)

	_modal_layer.add_child(modal)
	_winged_modal = modal

func _on_winged_cancel() -> void:
	# No commit -> no use spent.
	_close_winged_modal()
	_winged_item = null
	_player.set_input_locked(false)

func _on_winged_pick(game_id: StringName) -> void:
	_close_winged_modal()
	var gd: GameData = Data.get_game(game_id)
	if gd == null:
		_winged_item = null
		_player.set_input_locked(false)
		return
	# Commit: spend one Winged Boots use (it may shatter on the last charge).
	if _winged_item != null:
		GameState.consume_item_use(_winged_item)
		_winged_item = null
	GameLog.add("Winged Boots: flew to %s." % gd.display_name, Color(0.7, 0.9, 1.0))
	# Replace the portal set with just the chosen game and enter it, mirroring Dash.
	for p in _portals:
		p.queue_free()
	_portals.clear()
	_active_portal = null
	var only: Array[StringName] = [game_id]
	_place_portals(only)
	if _portals.size() > 0:
		_portals[0].set_highlight(true)
	get_tree().create_timer(0.45).timeout.connect(_finish_dash.bind(game_id))

func _close_winged_modal() -> void:
	if _winged_modal != null:
		_winged_modal.queue_free()
		_winged_modal = null

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
	# A Movement encounter's gate-elite fight returns here, not a game floor: on a
	# win resolve the queued teleport, on a loss end the run like any overworld
	# combat. Skips the verification / section-reward flow (no game was beaten).
	if outcome.get("encounter_combat", false):
		_resolve_encounter_combat(bool(outcome.get("victory", false)))
		return
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
		# A won run also checks off the (character, deck) pair for the
		# "Beaten With Deck" checklist on character select / Collection.
		GameStats.record_deck_win(GameState.character_id, GameState.selected_deck)
		_show_rate_modal(game_id, _show_win_overlay)
		return

	# The item reward is granted after the verification screen, so remember
	# which game it represents for the reward roll's launch context.
	_pending_reward_game_id = game_id
	_show_verification_modal(gd)

func _handle_defeat() -> void:
	GameState.phase = GameState.Phase.DEAD
	GameLog.add("---- Run ended ----", Color(0.9, 0.7, 0.7))
	# Delete the named save so a dead run can't be reloaded.
	if GameState.save_name != "":
		SaveSystem.delete_named(GameState.save_name)
	SaveSystem.delete_slot(0)
	# Losing all HP ends the run with a Game Over screen. The screen's
	# button then sends the player back to the main menu — picking another
	# start/amulet pair is a menu action, not an overworld one.
	_show_game_over_overlay()

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

# Per-active-curse "did you fulfil it?" answers, one bool per row (index-
# matched to _curse_verify_curses below) rather than keyed by curse id —
# active_restriction_curses() can return the same curse twice (two random
# draws landing on the same restriction), and an id-keyed dict would alias
# those rows onto a single answer. Default true so inaction isn't a penalty;
# a No on submit drops that row's penalty card.
var _curse_verify_answers: Array = []
# The CurseData backing each _curse_verify_answers row, captured when the
# modal opens so _resolve_curse_penalties can resolve each row independently
# without re-querying active_restriction_curses() (whose order/contents must
# stay aligned with the answers array for the whole modal's lifetime).
var _curse_verify_curses: Array = []

func _show_verification_modal(gd: GameData) -> void:
	if _verification_modal != null:
		return
	_player.set_input_locked(true)
	_weapon_verify_answers = {}
	_perfect_answer = false
	_levelup_answer = false
	_curse_verify_answers = []
	_curse_verify_curses = []

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
	# the curse's penalty card. A curse held twice yields two entries here (and
	# two rows below), each answered and resolved independently.
	var curses: Array = GameState.active_restriction_curses()
	_curse_verify_curses = curses
	_curse_verify_answers.resize(curses.size())
	_curse_verify_answers.fill(true)
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
	# Indexed (not id-keyed) so two rows for the same duplicated curse each
	# keep their own answer instead of aliasing onto one.
	for i in range(curses.size()):
		var cu: CurseData = curses[i]
		var row_idx: int = i  # fresh binding per iteration for the closure below
		_add_question_row(panel,
			"%s — %s  (Fulfilled?)" % [cu.display_name, cu.challenge],
			y, func(value: bool): _curse_verify_answers[row_idx] = value, true)
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

	_modal_layer.add_child(modal)
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
	# Record this game's curse outcome for encounter requirement gates: how many
	# restriction curses were carried, and how many were broken ("triggered").
	# Row-indexed (not id-keyed) so a curse held twice counts — and can be
	# broken — as two, independent of any other row sharing its curse id.
	GameState.last_game_curses_held = _curse_verify_curses.size()
	var triggered: int = 0
	for i in range(_curse_verify_curses.size()):
		if not _curse_verify_answers[i]:
			triggered += 1
	GameState.last_game_curses_triggered = triggered
	for i in range(_curse_verify_curses.size()):
		if _curse_verify_answers[i]:
			continue   # fulfilled — no penalty
		var curse: CurseData = _curse_verify_curses[i]
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
	_modal_layer.add_child(modal)

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
	var gold: int = CombatEconomy.section_reward_gold(tier)
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
	title.text = "YOU WIN!"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(20, 108)
	subtitle.size = Vector2(600, 32)
	subtitle.text = "You claimed the Amulet and completed the run."
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

	_modal_layer.add_child(overlay)
	_win_overlay = overlay

func _on_new_run_pressed() -> void:
	if _win_overlay != null:
		_win_overlay.queue_free()
		_win_overlay = null
	# New run flow is the menu's job — start/amulet/character selection
	# happen there, not here.
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

# ------------------------------------------------------------------
# Game Over overlay — shown when the player loses all HP in any combat.
# Mirrors the win overlay so a lost run gets the same run-level send-off
# (stats recap + a button back to the menu) instead of an abrupt cut to
# the main menu. Every combat mode funnels its defeat through
# _handle_defeat, so this single overlay covers deckbuilder, action, and
# strategy fights alike.
# ------------------------------------------------------------------

func _show_game_over_overlay() -> void:
	if _game_over_overlay != null:
		return
	_player.set_input_locked(true)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.02, 0.02, 0.88)
	overlay.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(640, 360)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	overlay.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 32)
	title.size = Vector2(600, 64)
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(20, 108)
	subtitle.size = Vector2(600, 32)
	subtitle.text = "You fell in combat."
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.95, 0.9, 0.9))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subtitle)

	var stats := Label.new()
	stats.position = Vector2(20, 160)
	stats.size = Vector2(600, 64)
	stats.text = "Games beaten: %d   Gold: %d" % [
		GameState.total_games_beaten,
		GameState.gold,
	]
	stats.add_theme_font_size_override("font_size", 16)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(stats)

	var btn := Button.new()
	btn.position = Vector2(220, 270)
	btn.size = Vector2(200, 56)
	btn.text = "Main Menu"
	btn.pressed.connect(_on_game_over_pressed)
	panel.add_child(btn)

	_modal_layer.add_child(overlay)
	_game_over_overlay = overlay

func _on_game_over_pressed() -> void:
	if _game_over_overlay != null:
		_game_over_overlay.queue_free()
		_game_over_overlay = null
	# The run is already over (save deleted in _handle_defeat) — a new run
	# is picked from the menu, same as the win overlay's flow.
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
