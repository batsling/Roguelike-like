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
# Difficulty gates (§7.1): the run's tier steps up every RunDifficulty.
# GAMES_PER_TIER games (RunDifficulty.tier_for). On the game that crosses into a
# new tier, the offering becomes a BOSS round — a "⚠ BOSS INCOMING" banner shows
# above the choices and whichever game you pick spawns a boss (bosses are
# unskippable: no bash/transmute on a boss round).

# Phases of one selection.
enum Phase { SELECT, PLAYING, OVER }

# The normal offering is LIMITED (a subset of the reachable games) — Dash (§4) is
# the verb that bypasses it to reach any connected game. Kept small so the board
# reads at a glance; the amulet is always included when it's reachable so a win is
# never blocked by the cap.
const OFFER_COUNT := 5

# The current offering. Each entry:
#   {"game": GameData, "enemy": GoalEnemyData, "boss": bool, "amulet": bool}
# The enemy is rolled up-front so the hover preview and the enemy that actually
# spawns on click are the SAME roll.
var _choices: Array = []
var _boss_round: bool = false
var _phase: int = Phase.SELECT
var _chosen: Dictionary = {}          # the choice being played (Phase.PLAYING)
# Transmute overrides for the current position: reachable game id -> the off-graph
# game it was swapped to (§4). Cleared when the player moves on.
var _transmuted: Dictionary = {}
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
var _now_playing_img: TextureRect
var _launch_row: HBoxContainer
var _verify_box: VBoxContainer      # clean checklist: goal + level-up + follower goals
var _fulfil_checks: Array = []      # [{check: CheckBox, instance: int}]
var _goal_check: CheckBox           # the chosen game's main goal; null on a free game
var _levelup_check: CheckBox        # null when the character has no level-up
var _dash_mode: bool = false        # Dash (§4): offer ANY connected game
var _controls_row: HBoxContainer
var _stack: RichTextLabel           # battlefield summary line
# --- battlefield grid (§grid): the player on the left, a GRID_COLS x GRID_ROWS
# grid on the right where enemies close in one column per game beaten (MMBN-style).
# Enemies are not one-per-cell: each covers its GoalEnemyData footprint, so the
# board is drawn as a fixed grid of backdrop panels with a free-positioned OVERLAY
# on top holding one node per enemy, spanning that enemy's whole bounding box.
var _battlefield: HBoxContainer
var _hero_icon: TextureRect
var _hero_hp: Label
var _field: Control                  # fixed-size board the two layers stack inside
var _grid_cells: Array = []          # _grid_cells[row][col-1] -> backdrop PanelContainer
var _enemy_layer: Control            # free-positioned enemy + loot nodes, drawn over the board
var _enemy_nodes: Dictionary = {}    # instance -> the node currently drawing it
var _offgrid_box: VBoxContainer      # overflow queue just off the grid's right edge
var _drop_queue: Array = []          # ItemData dropped by kills, shown as field loot
var _selected_instance: int = 0      # clicked enemy the combat verbs target (0 = none)
var _push_btn: Button
var _bomb_btn: Button
var _target_label: Label
var _fx_layer: Control               # overlay for damage numbers + sliding ghosts
var _info_popup: Control             # the click-to-inspect enemy card (null when closed)
var _animating: bool = false         # a resolve animation is playing
var _log: RichTextLabel
var _scrolls_box: VBoxContainer
var _items_box: VBoxContainer       # owned items with Use buttons (§4/§8)
var _reward_open: bool = false      # a RewardScreen is currently showing

func _ready() -> void:
	_rng.randomize()
	_build_ui()
	if not GameLoop2.loop_changed.is_connected(_refresh):
		GameLoop2.loop_changed.connect(_refresh)
	if not GameLoop2.run_lost.is_connected(_on_run_lost):
		GameLoop2.run_lost.connect(_on_run_lost)
	if not GameLoop2.run_won.is_connected(_on_run_won):
		GameLoop2.run_won.connect(_on_run_won)
	# Register as the mounted overworld so overworld-active items (Ride the Bus,
	# Wand of Wishing) can route their effect here, and so item pickups refresh
	# the inventory panel.
	GameState.set_overworld_context(self)
	if not GameState.inventory_changed.is_connected(_refresh_items):
		GameState.inventory_changed.connect(_refresh_items)
	# Every defeated enemy banks a chest (§8); redeem them into RewardScreens when
	# the board is idle — one screen per chest, so several defeats in one game pop
	# several rewards in a row.
	if not TriggerBus.chest_granted.is_connected(_on_chest_granted):
		TriggerBus.chest_granted.connect(_on_chest_granted)
	# Every defeated enemy drops an item that appears inline on the battlefield as
	# collectable field loot (§8), instead of banking a RewardScreen chest.
	if not GameLoop2.enemy_defeated.is_connected(_on_enemy_defeated):
		GameLoop2.enemy_defeated.connect(_on_enemy_defeated)
	# The menu stashes the chosen 2.0 character here before entering the scene.
	var pending: StringName = GameState.get_meta("pending_character2", &"")
	if pending != &"":
		GameState.remove_meta("pending_character2")
	start_run(pending)

# --- public actions (buttons + tests call these) --------------------------

# Boot a fresh 2.0 run: roll a start/amulet graph, apply a 2.0 character loadout,
# and place the player on the start game so its neighbours become the first
# offering. `character_id` empty -> the first authored 2.0 character.
func start_run(character_id: StringName = &"") -> void:
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(_rng)
	var ch: CharacterData = Data.get_character2(character_id)
	if ch == null:
		var roster: Array = Data.all_characters2()
		ch = roster[0] if not roster.is_empty() else null
	GameLoop2.start_run(ch)
	if not pick.is_empty():
		var opts: Array = pick.get("options", [])
		var start_id: StringName = StringName(opts[_rng.randi() % opts.size()]["start_id"]) if not opts.is_empty() else &""
		GameState.start_game_id = start_id
		GameState.amulet_game_id = StringName(pick.get("amulet_id", ""))
		GameState.set_current_game(start_id)
	_phase = Phase.SELECT
	_dash_mode = false
	_banner.hide()
	_build_choices()
	_refresh()

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
	# Move to the graph SLOT (a transmuted card plays an off-graph game but keeps
	# its position on the route toward the amulet).
	GameState.set_current_game(_chosen["slot"])
	_phase = Phase.PLAYING
	_populate_play_panel()
	_refresh()

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
	var leveled: bool = _levelup_check != null and _levelup_check.button_pressed
	# Snapshot where everyone stands BEFORE the resolve, so the animation can play
	# the strike and the advance back from the old positions to the new ones.
	var before: Dictionary = _battlefield_positions()
	_close_enemy_info()
	var res: Dictionary = GameLoop2.beat_game(goal_met, fulfilled_instances)
	# "After beating a game" is the dominant 2.0 item trigger (§8): fire it now so
	# owned items react (Anchor +1 Block, Burning Blood +1 Health, Meat on the
	# Bone), the Harvesting stat pays out, charged actives tick, and the toast
	# shows. Defeated-enemy drops were already banked by beat_game above.
	if played_game != null:
		TriggerBus.game_beaten.emit({"game_id": played_game.id})
	# Level up (§3.1) — a fresh chance each game; skipped if the game just killed
	# the player.
	if leveled and not GameLoop2.run_over:
		_apply_level_up()
	GameState.games_played += 1
	_chosen = {}
	_transmuted.clear()   # transmutes apply only to the offering you moved from
	# Just like the older version: after playing a game, prompt to score it onto
	# the tier list (opt-in — the modal has a "Maybe later"). Fires on every path,
	# including the run-ending game.
	if played_game != null:
		_prompt_rating(played_game)
	if GameLoop2.run_over:
		_phase = Phase.OVER
		_refresh()
		_animate_resolve(before, res)
		return
	if was_amulet and goal_met:
		GameLoop2.clear_amulet()
		return
	_phase = Phase.SELECT
	_build_choices()
	_refresh()
	# Repaint first, then replay the strike + advance from the snapshot: the board
	# is already in its final state, the animation just shows how it got there.
	_animate_resolve(before, res)

func _exit_tree() -> void:
	GameState.clear_overworld_context(self)
	_clear_fx()
	_close_enemy_info()
	if TriggerBus.chest_granted.is_connected(_on_chest_granted):
		TriggerBus.chest_granted.disconnect(_on_chest_granted)
	if GameState.inventory_changed.is_connected(_refresh_items):
		GameState.inventory_changed.disconnect(_refresh_items)

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

# Bash the offered game at `index` (§4): destroy it out of the pool for the run.
# Allowed on a boss round — but the boss is tied to the difficulty gate, not the
# game, so whatever game backfills the slot still spawns a boss.
func bash_choice(index: int) -> void:
	if _phase != Phase.SELECT or index < 0 or index >= _choices.size():
		return
	if GameLoop2.bash_game(_choices[index]["slot"]):
		_build_choices()
		_refresh()

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
		_transmuted[slot] = repl
		_build_choices()
		_refresh()

# Push a following enemy back one space (Manager's verb, §7.2): spend a Push
# charge to delay its next attack by a game. Targets a stacked follower by
# instance; GameLoop2.push guards the charge and membership, so a no-op just
# leaves the board unchanged.
func push_follower(instance: int) -> void:
	if GameLoop2.push(instance):
		_refresh()

# Bomb a following enemy (§4): spend a Bomb charge to remove it outright (no drop).
# Bosses are bomb-immune, so GameLoop2.bomb guards the target and the charge.
func bomb_follower(instance: int) -> void:
	if GameLoop2.bomb(instance):
		_refresh()

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

# The limited offering for the current position: reachable, non-bashed games in a
# stable position-seeded order, capped at OFFER_COUNT, with the amulet always kept
# when it's reachable. Stable so bashing/transmuting one card doesn't reshuffle
# the rest.
func _offered_ids() -> Array:
	var amulet: StringName = GameState.amulet_game_id
	var nbrs: Array = []
	for gid in RunGraph.neighbors(GameState.current_game_id):
		if not GameLoop2.is_bashed(gid):
			nbrs.append(gid)
	var cur := String(GameState.current_game_id)
	nbrs.sort_custom(func(a, b): return hash(cur + "|" + String(a)) < hash(cur + "|" + String(b)))
	# Dash (§4) bypasses the cap — every connected game is a valid target.
	if _dash_mode:
		return nbrs
	if amulet in nbrs and nbrs.size() > OFFER_COUNT:
		nbrs.erase(amulet)
		nbrs.push_front(amulet)
	return nbrs.slice(0, OFFER_COUNT)

func _build_choices() -> void:
	_choices.clear()
	_boss_round = _is_boss_round()
	var tier: int = _current_tier()
	var amulet: StringName = GameState.amulet_game_id
	for gid in _offered_ids():
		var game: GameData = _transmuted.get(gid, Data.get_game(gid))
		if game == null:
			continue
		var type_key: StringName = GameLoop2.game_type_key(game)
		var enemy: GoalEnemyData = GameLoop2.roll_boss(type_key, tier) if _boss_round else GameLoop2.roll_enemy(type_key, tier)
		_choices.append({
			"game": game, "enemy": enemy, "slot": gid,
			"boss": _boss_round, "amulet": gid == amulet,
		})

# --- rendering ------------------------------------------------------------

func _refresh(_a = null) -> void:
	if _hud == null:
		return
	_hud.text = _hud_text()
	_refresh_scrolls()
	_refresh_items()
	_stack.text = _stack_summary()
	_refresh_battlefield()
	if not GameLoop2.last_result.is_empty():
		_log.text = _result_text(GameLoop2.last_result)
	_boss_banner.get_parent().visible = _boss_round and _phase == Phase.SELECT
	_controls_row.visible = _phase == Phase.SELECT
	_choices_row.visible = _phase == Phase.SELECT
	_play_panel.get_parent().visible = _phase == Phase.PLAYING
	if _phase == Phase.SELECT:
		_render_controls()
		_render_choices()
	elif _phase == Phase.PLAYING:
		_now_playing.text = _now_playing_text()
		var np_tex: Texture2D = null if _chosen.is_empty() else _enemy_texture(_chosen)
		_now_playing_img.texture = np_tex
		_apply_crisp(_now_playing_img, np_tex)

func _render_controls() -> void:
	for c in _controls_row.get_children():
		c.queue_free()
	if _dash_mode:
		var hint := Label.new()
		hint.text = "⚡ Dash — pick ANY connected game:"
		hint.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
		_controls_row.add_child(hint)
		_controls_row.add_child(_mini_button("Cancel", cancel_dash))
	elif GameState.dash_charges > 0:
		var b := Button.new()
		b.text = "⚡ Dash — pick any connected (%d)" % GameState.dash_charges
		b.pressed.connect(dash)
		_controls_row.add_child(b)

func _render_choices() -> void:
	for c in _choices_row.get_children():
		c.queue_free()
	if _choices.is_empty():
		var l := Label.new()
		l.text = "No reachable games — dead end."
		_choices_row.add_child(l)
		return
	for i in range(_choices.size()):
		_choices_row.add_child(_make_choice_card(i, _choices[i]))
	_preview.text = "[i]Hover a game to see the enemy it would spawn.[/i]"
	_preview_img.texture = null

# One choice = the game's cover art with its name below, plus (off a boss round)
# small Bash/Transmute verbs when the player has charges. Hover updates the
# shared enemy preview.
func _make_choice_card(index: int, choice: Dictionary) -> Control:
	var game: GameData = choice["game"]
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	card.custom_minimum_size = Vector2(150, 0)

	var accent: Color = UITheme.DANGER if choice["boss"] else (UITheme.GOLD if choice["amulet"] else UITheme.type_color(int(game.type)))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 105)
	var frame_n := UITheme.flat(UITheme.BG, 8, 4, 1, UITheme.BORDER)
	var frame_h := UITheme.flat(UITheme.PANEL_HI, 8, 4, 2, accent)
	btn.add_theme_stylebox_override("normal", frame_n)
	btn.add_theme_stylebox_override("hover", frame_h)
	btn.add_theme_stylebox_override("pressed", frame_h)
	btn.add_theme_stylebox_override("focus", frame_h)
	btn.pressed.connect(func(): pick(index))
	btn.mouse_entered.connect(func(): _show_preview(index))
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
	name_lbl.custom_minimum_size = Vector2(140, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", accent if (choice["boss"] or choice["amulet"]) else UITheme.TEXT)
	card.add_child(name_lbl)

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
	return card

# Build the self-report panel for the chosen game: a launch button (when the
# game can be launched) and a fulfilment checkbox per following enemy so old
# goals can be cleared this game (§2).
func _populate_play_panel() -> void:
	for c in _launch_row.get_children():
		c.queue_free()
	for c in _verify_box.get_children():
		c.queue_free()
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
	_verify_box.add_child(_verify_head("Check off what you did this game:"))

	var enemy: GoalEnemyData = _chosen.get("enemy")
	if enemy != null and enemy.goal != "":
		var is_amulet: bool = bool(_chosen.get("amulet", false))
		var goal_text: String = "%s %s" % ["🏆 Amulet goal —" if is_amulet else "Goal —", enemy.goal]
		var goal_row := _verify_row(goal_text, UITheme.SUCCESS, true)
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
		var row := _verify_row("Also cleared: %s — %s" % [e.display_name, e.goal], UITheme.TEXT, false)
		_verify_box.add_child(row["row"])
		_fulfil_checks.append({"check": row["check"], "instance": int(entry["instance"])})

# Whether the chosen game's MAIN goal was met — true when its checkbox is ticked,
# or when the game had no enemy/goal to meet (a free game auto-clears).
func _goal_met() -> bool:
	return _goal_check == null or _goal_check.button_pressed

# One checklist row: a bordered CheckBox tinted `color`; `emphasise` gives the
# main-goal row a heavier border so it reads as the primary question.
func _verify_row(text: String, color: Color, emphasise: bool) -> Dictionary:
	var wrap := PanelContainer.new()
	var border: Color = color.lerp(UITheme.BORDER, 0.35)
	wrap.add_theme_stylebox_override("panel", UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 6, 8, 2 if emphasise else 1, border))
	var cb := CheckBox.new()
	cb.text = text
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_theme_color_override("font_color", color)
	wrap.add_child(cb)
	return {"row": wrap, "check": cb}

func _verify_head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
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
				GameState.grant_chest(maxi(1, ch.level_up_reward_amount))
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
	_apply_crisp(_preview_img, tex)

# The enemy's art (§10.1) for a choice, or null when there's no enemy.
func _enemy_texture(choice: Dictionary) -> Texture2D:
	var e: GoalEnemyData = choice.get("enemy")
	return e.image if e != null else null

func _enemy_preview_text(choice: Dictionary) -> String:
	var e: GoalEnemyData = choice.get("enemy")
	var game: GameData = choice["game"]
	if e == null:
		return "[b]%s[/b]\n[i]No enemy — free game.[/i]" % game.display_name
	var kind: String = "[color=#e0b020][b]☠ BOSS[/b][/color] " if choice["boss"] else ""
	# Effective Health = goal completions to defeat it (Alien Baby makes it 2).
	var hp: int = GameLoop2.effective_health(e)
	var hp_txt: String = "%d goal%s to beat" % [hp, "" if hp == 1 else "s"]
	return "[b]%s[/b]  →  %s%s\n[b]GOAL (%s):[/b] %s   [i](%s / %s / %s / dmg %d)[/i]" % [
		game.display_name, kind, e.display_name,
		String(e.goal_type).capitalize(), e.goal,
		String(e.game_type).capitalize(), _tier_name(e), hp_txt, e.damage,
	]

func _now_playing_text() -> String:
	if _chosen.is_empty():
		return ""
	return "[b]Now playing:[/b] %s\n%s" % [_chosen["game"].display_name, _enemy_preview_text(_chosen)]

func _hud_text() -> String:
	return "[b]Health[/b] %d/%d   [b]Block[/b] %d      [b]Tier[/b] %s      [b]Bash[/b] %d  [b]Dash[/b] %d  [b]Push[/b] %d  [b]Transmute[/b] %d  [b]Scramble[/b] %d  [b]Bombs[/b] %d  [b]Keys[/b] %d  [b]Scrolls[/b] %d   [b]Chests[/b] %d" % [
		GameState.hp, GameState.max_hp, GameState.block,
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
	for c in _scrolls_box.get_children():
		c.queue_free()
	var scrolls: Array = GameState.loot_scrolls()
	_scrolls_box.visible = _phase == Phase.SELECT
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

# Owned items, each with its rarity-tinted name and — for USABLE / CHARGED
# actives — a Use button that's enabled only when the item can fire right now
# (a charged item needs a full bar; charged bars show their fill). Passive /
# triggered items list without a button. Mirrors the scrolls panel.
func _refresh_items() -> void:
	if _items_box == null:
		return
	for c in _items_box.get_children():
		c.queue_free()
	_items_box.visible = _phase != Phase.PLAYING
	if GameState.inventory.is_empty():
		var none := Label.new()
		none.text = "  (none)"
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		_items_box.add_child(none)
		return
	for item in GameState.inventory:
		if not (item is ItemData):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if item.image != null:
			icon.texture = item.image
		row.add_child(icon)
		var name_lbl := Label.new()
		var label_text: String = item.display_name
		if item.is_charged():
			label_text += "  [%d/%d]" % [item.current_charge, item.max_charge()]
		name_lbl.text = label_text
		name_lbl.tooltip_text = item.description
		var rar: int = clampi(int(item.rarity), 0, RewardScreen.RARITY_COLORS.size() - 1)
		name_lbl.add_theme_color_override("font_color", RewardScreen.RARITY_COLORS[rar])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		# Only actives get a Use button; a charged item shows a disabled "Charging"
		# until its bar fills.
		if item.kind == ItemData.ItemKind.USABLE or item.is_charged():
			var use_btn := Button.new()
			var ready: bool = GameState.can_fire_item(item)
			use_btn.text = "Use" if ready else ("Charging" if item.is_charged() else "Use")
			use_btn.disabled = not ready
			var target_item: ItemData = item
			use_btn.pressed.connect(func(): use_item(target_item))
			row.add_child(use_btn)
		_items_box.add_child(row)

# One-line header above the follower cards: how many are on your tail and the
# damage the stack lands on the next game beaten.
func _stack_summary() -> String:
	var following: int = GameLoop2.stack.size()
	if _phase == Phase.PLAYING and not _chosen.is_empty() and _chosen.get("enemy") != null:
		following += 1
	if following == 0:
		return "[b]Battlefield:[/b] clear"
	var dmg: int = GameLoop2.stacked_damage_per_game()
	return "[b]Battlefield[/b] — %d closing in, %d at the front dealing %d damage next game" % [
		following, GameLoop2.front_count(), dmg]

const _CELL: int = 84                # grid cell edge in px
const _CELL_SEP: int = 6
const _CELL_STEP: int = _CELL + _CELL_SEP
# A hovered enemy is lifted above every other body so an overlapped one can still
# be read in full — the one case where the back-to-front order is overridden.
const _Z_HOVER: int = 40

# A Control whose clickable area is only the cells its enemy actually FILLS, so
# the empty notch inside an L-shaped body stays clickable for whatever stands
# behind it — the bounding box is for drawing, the mask is for input.
class FootprintControl extends Control:
	var cells: Array = []            # Vector2i(col offset, row offset), solid only
	var cell_size: float = 84.0
	var step: float = 90.0

	func _has_point(point: Vector2) -> bool:
		for c in cells:
			if Rect2(Vector2(c.x, c.y) * step, Vector2(cell_size, cell_size)).has_point(point):
				return true
		return false

# Board size in px: GRID_COLS x GRID_ROWS cells with a gutter between them.
func _field_size() -> Vector2:
	return Vector2(
		GameLoop2.GRID_COLS * _CELL + (GameLoop2.GRID_COLS - 1) * _CELL_SEP,
		GameLoop2.GRID_ROWS * _CELL + (GameLoop2.GRID_ROWS - 1) * _CELL_SEP)

# Top-left of grid cell (`row`, `col`) inside the board (0-based row, 1-based col).
func _cell_pos(row: int, col: int) -> Vector2:
	return Vector2((col - 1) * _CELL_STEP, row * _CELL_STEP)

# Pixel size of a footprint `cols` wide and `rows` tall, gutters included — the
# rect an enemy's art is drawn across.
func _span_size(rows: int, cols: int) -> Vector2:
	return Vector2(cols * _CELL + (cols - 1) * _CELL_SEP,
		rows * _CELL + (rows - 1) * _CELL_SEP)

# The combat verbs live with the combat: Push and Bomb sit on a toolbar attached to
# the battlefield and act on the enemy you clicked. Each button explains why it's
# unavailable (no target / no charge / no room behind / boss) rather than vanishing,
# so the rules stay visible.
func _build_battle_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.text = "Click an enemy to inspect it:"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	bar.add_child(hint)

	_target_label = Label.new()
	_target_label.add_theme_font_size_override("font_size", 13)
	# Deliberately not expanding: the verbs must stay packed beside the field they
	# act on, not drift to the far edge of a full-width panel.
	_target_label.custom_minimum_size = Vector2(230, 0)
	bar.add_child(_target_label)

	_push_btn = Button.new()
	_push_btn.add_theme_font_size_override("font_size", 13)
	_push_btn.pressed.connect(func(): push_follower(_selected_instance))
	bar.add_child(_push_btn)

	_bomb_btn = Button.new()
	_bomb_btn.add_theme_font_size_override("font_size", 13)
	_bomb_btn.pressed.connect(func(): bomb_follower(_selected_instance))
	bar.add_child(_bomb_btn)
	return bar

# Re-label and enable/disable the combat verbs for the current selection.
func _refresh_battle_toolbar() -> void:
	if _push_btn == null:
		return
	var entry: Dictionary = _stack_entry(_selected_instance)
	var e: GoalEnemyData = entry.get("enemy") if not entry.is_empty() else null
	if e == null:
		_target_label.text = "no target selected"
		_target_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	else:
		_target_label.text = "▸ %s  (col %d, row %d)" % [
			e.display_name, int(entry.get("col", GameLoop2.SPAWN_COL)),
			int(entry.get("row", 0)) + 1]
		_target_label.add_theme_color_override("font_color", UITheme.ACCENT)

	_push_btn.text = "⇤  Push (%d)" % GameState.push
	var push_ok: bool = e != null and GameState.push > 0 and GameLoop2.can_push(_selected_instance)
	_push_btn.disabled = not push_ok
	if e == null:
		_push_btn.tooltip_text = "Select an enemy to push."
	elif GameState.push <= 0:
		_push_btn.tooltip_text = "No Push charges left."
	elif int(entry.get("col", 0)) + e.footprint_cols() - 1 >= GameLoop2.GRID_COLS:
		_push_btn.tooltip_text = "%s is already against the back edge — nowhere to push it." % e.display_name
	elif not push_ok:
		_push_btn.tooltip_text = "Something is parked behind %s — no room to shove it back." % e.display_name
	else:
		_push_btn.tooltip_text = "Shove %s back one column, buying the games it takes to close in again." % e.display_name

	_bomb_btn.text = "✸  Bomb (%d)" % GameState.bombs
	var bomb_ok: bool = e != null and GameState.bombs > 0 and not e.is_boss()
	_bomb_btn.disabled = not bomb_ok
	if e == null:
		_bomb_btn.tooltip_text = "Select an enemy to bomb."
	elif GameState.bombs <= 0:
		_bomb_btn.tooltip_text = "No Bombs left."
	elif e.is_boss():
		_bomb_btn.tooltip_text = "%s is a boss — bombs can't kill it." % e.display_name
	else:
		_bomb_btn.tooltip_text = "Destroy %s outright (it drops nothing)." % e.display_name

# The stack entry for an instance, or {} when it's gone / nothing is selected.
func _stack_entry(instance: int) -> Dictionary:
	if instance <= 0:
		return {}
	for entry in GameLoop2.stack:
		if int(entry.get("instance", 0)) == instance:
			return entry
	return {}

# Build the battlefield once: the hero on the left, then a GRID_COLS x GRID_ROWS
# grid of cells (col 1 = melee/front nearest the hero, col GRID_COLS = spawn), then
# a slim off-grid overflow lane on the right. Cells are reused each refresh so the
# layout stays put; only their contents change.
func _build_battlefield() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.BG, UITheme.BORDER, 10, 12, 1))
	# The frame stacks the combat toolbar over the field itself, and hosts the FX
	# layer that floats damage numbers / sliding enemies above both.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	frame.add_child(outer)
	outer.add_child(_build_battle_toolbar())
	_battlefield = HBoxContainer.new()
	_battlefield.add_theme_constant_override("separation", 14)
	_battlefield.alignment = BoxContainer.ALIGNMENT_BEGIN
	outer.add_child(_battlefield)

	# Animation overlay: ghost sprites and damage numbers are parented here so they
	# can travel across cells without being clipped by a cell's own rect.
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_fx_layer)

	# Hero column.
	var hero_box := VBoxContainer.new()
	hero_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_box.add_theme_constant_override("separation", 4)
	hero_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hero_frame := PanelContainer.new()
	hero_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 8, 8, 2, UITheme.ACCENT))
	_hero_icon = TextureRect.new()
	_hero_icon.custom_minimum_size = Vector2(96, 96)
	_hero_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_frame.add_child(_hero_icon)
	hero_box.add_child(hero_frame)
	_hero_hp = Label.new()
	_hero_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_hp.add_theme_font_size_override("font_size", 14)
	_hero_hp.add_theme_color_override("font_color", UITheme.DANGER.lerp(UITheme.TEXT, 0.35))
	hero_box.add_child(_hero_hp)
	_battlefield.add_child(hero_box)

	# The board: a fixed-size Control holding two stacked layers. The lower one is
	# the static backdrop — GRID_ROWS x GRID_COLS empty panels, column 1 nearest the
	# hero — and the upper one is where enemies and loot are positioned by hand,
	# because an enemy can span several cells and must be free to overlap its
	# neighbours.
	_field = Control.new()
	_field.custom_minimum_size = _field_size()
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_battlefield.add_child(_field)

	var cell_layer := Control.new()
	cell_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	cell_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(cell_layer)
	_grid_cells = []
	for row in range(GameLoop2.GRID_ROWS):
		var row_cells: Array = []
		for col in range(1, GameLoop2.GRID_COLS + 1):
			var cell := PanelContainer.new()
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.position = _cell_pos(row, col)
			cell.size = Vector2(_CELL, _CELL)
			cell.add_theme_stylebox_override("panel", _empty_cell_style())
			cell_layer.add_child(cell)
			row_cells.append(cell)
		_grid_cells.append(row_cells)

	_enemy_layer = Control.new()
	_enemy_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enemy_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_enemy_layer)

	# Off-field lane: enemies with no cell to stand in — the overflow queue, and the
	# game you're currently playing, whose enemy only steps onto the grid once you
	# report the result.
	var off_col := VBoxContainer.new()
	off_col.add_theme_constant_override("separation", 4)
	off_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var off_lbl := Label.new()
	off_lbl.text = "off field"
	off_lbl.add_theme_font_size_override("font_size", 10)
	off_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	off_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	off_col.add_child(off_lbl)
	_offgrid_box = VBoxContainer.new()
	_offgrid_box.add_theme_constant_override("separation", _CELL_SEP)
	off_col.add_child(_offgrid_box)
	_battlefield.add_child(off_col)
	return frame

# Repaint the battlefield from the current loop state: place each following enemy
# in its grid cell (by column = distance), the just-picked enemy at the spawn
# column while its game is being played, the off-grid queue in the side lane, and
# any pending kill-drops as collectable field loot in free cells.
func _refresh_battlefield() -> void:
	if _battlefield == null:
		return
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	var hero_tex: Texture2D = null
	if ch != null:
		hero_tex = ch.icon if ch.icon != null else ch.portrait
	_hero_icon.texture = hero_tex
	_apply_crisp(_hero_icon, hero_tex)
	_hero_hp.text = "♥ %d/%d" % [GameState.hp, GameState.max_hp]

	# Clear the overlay and the overflow lane; the backdrop panels are static.
	for c in _enemy_layer.get_children():
		_enemy_layer.remove_child(c)
		c.queue_free()
	_enemy_nodes.clear()
	for c in _offgrid_box.get_children():
		c.queue_free()

	# Enemies standing on the board, drawn BACK-TO-FRONT: a body lower on the grid
	# is nearer the viewer, so it paints over the ones above it where their
	# bounding boxes overlap. Sorting by the bottom edge of the footprint (then the
	# top edge, then the column) makes a tall enemy hang in front of what it
	# reaches down past.
	var placed: Array = []
	for entry in GameLoop2.stack:
		if int(entry.get("col", GameLoop2.OFFGRID_COL)) <= GameLoop2.GRID_COLS:
			placed.append(entry)
	placed.sort_custom(func(a, b): return _draw_order_key(a) < _draw_order_key(b))
	for entry in placed:
		_add_enemy_node(entry, false)

	# Off-field: the overflow queue, plus the game you're playing right now — it
	# isn't on the stack yet and only walks onto the board when you report the
	# result (that entrance is the one-game grace made visible, §7.2).
	for entry in GameLoop2.stack:
		if int(entry.get("col", GameLoop2.OFFGRID_COL)) > GameLoop2.GRID_COLS:
			_offgrid_box.add_child(_offgrid_token(entry, false))
	if _phase == Phase.PLAYING and GameLoop2.has_current():
		_offgrid_box.add_child(_offgrid_token(GameLoop2.current, true))

	# Drop a selection that died / was bombed, then relabel the combat verbs.
	if _selected_instance > 0 and _stack_entry(_selected_instance).is_empty():
		_selected_instance = 0
	_refresh_battle_toolbar()

	# Pending kill-drops become collectable loot in the nearest free cells.
	_place_drops()

func _empty_cell_style() -> StyleBox:
	return UITheme.flat(UITheme.BG.lerp(UITheme.PANEL, 0.4), 6, 4, 1, UITheme.BORDER.lerp(UITheme.BG, 0.3))

# Paint an enemy's footprint tiles for its current state. Hovering brightens the
# outline and lifts the fill (the "you can click this" cue); the selected enemy —
# the one the toolbar's Push / Bomb act on — keeps a thick accent ring. `frames`
# is one PanelContainer per cell the enemy fills, so an L reads as an L.
func _style_enemy_cell(frames: Array, accent: Color, is_current: bool, selected: bool, hovered: bool) -> void:
	var border: Color = accent
	var width: int = 3 if is_current else 2
	var fill: Color = UITheme.PANEL
	if selected:
		border = UITheme.ACCENT
		width = 4
		fill = UITheme.PANEL.lerp(UITheme.ACCENT, 0.14)
	if hovered:
		border = border.lerp(Color.WHITE, 0.55)
		width = maxi(width, 3)
		fill = fill.lerp(Color.WHITE, 0.09)
	var box: StyleBox = UITheme.flat(fill, 6, 2, width, border)
	for f in frames:
		if is_instance_valid(f):
			f.add_theme_stylebox_override("panel", box)

# Clicking an enemy targets it for the combat verbs and opens its info card.
func _on_enemy_clicked(instance: int, entry: Dictionary, col: int, is_current: bool) -> void:
	# The game you're currently playing isn't on the stack, so it can't be targeted
	# by Push / Bomb — but you can still read its card.
	_selected_instance = 0 if is_current else instance
	_show_enemy_info(entry, col, is_current)
	_refresh_battlefield()

# --- enemy info card ------------------------------------------------------

# A proper info card for a clicked enemy: dimmed backdrop, large art, and its
# goal / type / tier / stats laid out in readable blocks — plus the combat verbs
# aimed at this enemy, so you can act straight from the card you're reading.
func _show_enemy_info(entry: Dictionary, col: int, is_current: bool) -> void:
	var e: GoalEnemyData = entry.get("enemy")
	if e == null:
		return
	_close_enemy_info()
	var accent: Color = _col_accent(col, e.is_boss())
	var instance: int = int(entry.get("instance", 0))

	# Full-screen dimmer; clicking outside the card closes it.
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_enemy_info())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 14, 0, 2, accent))
	center.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)

	# Header band, tinted by threat (front column red, boss orange).
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UITheme.flat(accent.lerp(UITheme.BG, 0.72), 12, 14, 0))
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	header.add_child(head_row)
	var title := Label.new()
	title.text = ("☠  " if e.is_boss() else "") + e.display_name
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.5))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(_close_enemy_info)
	head_row.add_child(close_btn)
	body.add_child(header)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	pad.add_child(inner)
	body.add_child(pad)

	# Art beside the headline stats.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var art_frame := PanelContainer.new()
	art_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 10, 8, 1, accent.lerp(UITheme.BG, 0.4)))
	art_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var art := _crisp_tex(e.image, 132)
	art_frame.add_child(art)
	top.add_child(art_frame)

	var stat_col := VBoxContainer.new()
	stat_col.add_theme_constant_override("separation", 6)
	stat_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hp: int = int(entry.get("health", e.health))
	stat_col.add_child(_info_stat("❤", "Health", "%d goal%s to defeat" % [hp, "" if hp == 1 else "s"], Color(1.0, 0.5, 0.5)))
	stat_col.add_child(_info_stat("⚔", "Damage", "%d per game, from the front" % e.damage, Color(1.0, 0.8, 0.35)))
	stat_col.add_child(_info_stat("◎", "Position", _position_text(entry, col, is_current), accent))
	if e.footprint_rows() > 1 or e.footprint_cols() > 1:
		stat_col.add_child(_info_stat("▦", "Size", _size_text(e), UITheme.TEXT_DIM))
	var stun: int = int(entry.get("stun", 0))
	if stun > 0:
		stat_col.add_child(_info_stat("❄", "Frozen", "skips its next %d game(s)" % stun, Color(0.6, 0.8, 1.0)))
	top.add_child(stat_col)
	inner.add_child(top)

	# Type / tier / source chips.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.add_child(_info_chip(String(e.game_type).capitalize(), UITheme.ACCENT))
	chips.add_child(_info_chip("Tier %s" % _tier_name(e), UITheme.GOLD))
	if e.is_boss():
		chips.add_child(_info_chip("BOSS", Color(0.95, 0.55, 0.2)))
	if String(e.tag) != "":
		chips.add_child(_info_chip(String(e.tag), UITheme.TEXT_DIM))
	inner.add_child(chips)

	# The goal — the thing you actually have to do — gets its own panel.
	if e.goal != "":
		var goal_wrap := PanelContainer.new()
		goal_wrap.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 8, 12, 1, UITheme.GOLD.lerp(UITheme.BG, 0.55)))
		var goal_box := VBoxContainer.new()
		goal_box.add_theme_constant_override("separation", 3)
		var goal_hdr := Label.new()
		goal_hdr.text = "GOAL  (%s)" % String(e.goal_type).capitalize()
		goal_hdr.add_theme_font_size_override("font_size", 11)
		goal_hdr.add_theme_color_override("font_color", UITheme.GOLD)
		goal_box.add_child(goal_hdr)
		var goal_txt := Label.new()
		goal_txt.text = e.goal
		goal_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal_txt.custom_minimum_size = Vector2(460, 0)
		goal_txt.add_theme_font_size_override("font_size", 14)
		goal_box.add_child(goal_txt)
		goal_wrap.add_child(goal_box)
		inner.add_child(goal_wrap)

	if e.source_game != "":
		var src := Label.new()
		src.text = "From %s" % e.source_game
		src.add_theme_font_size_override("font_size", 12)
		src.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		inner.add_child(src)

	# Combat verbs, aimed at this enemy (a currently-played game isn't targetable).
	if not is_current and instance > 0:
		inner.add_child(HSeparator.new())
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 8)
		var can_push: bool = GameState.push > 0 and GameLoop2.can_push(instance)
		var pb := Button.new()
		pb.text = "⇤  Push back a column (%d)" % GameState.push
		pb.disabled = not can_push
		pb.tooltip_text = "The column behind is full — no room to shove it back." if (GameState.push > 0 and not can_push) else "Buys the games it takes to close back in."
		pb.pressed.connect(func():
			push_follower(instance)
			_close_enemy_info())
		acts.add_child(pb)
		var can_bomb: bool = GameState.bombs > 0 and not e.is_boss()
		var bb := Button.new()
		bb.text = "✸  Bomb (%d)" % GameState.bombs
		bb.disabled = not can_bomb
		bb.tooltip_text = "Bosses are bomb-immune." if e.is_boss() else "Destroys it outright — no drop."
		bb.pressed.connect(func():
			bomb_follower(instance)
			_close_enemy_info())
		acts.add_child(bb)
		inner.add_child(acts)

	_info_popup = overlay
	add_child(overlay)

func _close_enemy_info() -> void:
	if _info_popup != null and is_instance_valid(_info_popup):
		_info_popup.queue_free()
	_info_popup = null

# One "icon — label — value" row in the info card's stat column.
func _info_stat(icon: String, label: String, value: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ico := Label.new()
	ico.text = icon
	ico.add_theme_font_size_override("font_size", 16)
	ico.add_theme_color_override("font_color", color)
	ico.custom_minimum_size = Vector2(22, 0)
	row.add_child(ico)
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	name_lbl.custom_minimum_size = Vector2(76, 0)
	row.add_child(name_lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 14)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	return row

func _info_chip(text: String, color: Color) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", UITheme.flat(color.lerp(UITheme.BG, 0.72), 6, 6, 1, color.lerp(UITheme.BG, 0.35)))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35))
	wrap.add_child(l)
	return wrap

# Plain-language description of where an enemy stands and what that means. `col`
# is its FRONT column — the leading edge is what decides when it strikes, so a
# wide body reads as closer than its left-hand corner alone would suggest.
func _position_text(entry: Dictionary, col: int, is_current: bool) -> String:
	if is_current:
		return "off field — steps in when you report this game"
	if col >= GameLoop2.OFFGRID_COL:
		return "off field — waiting for room on the board"
	var lane: String = "row %d, " % (int(entry.get("row", 0)) + 1)
	if col <= 1:
		return lane + "front column — strikes every game"
	return "%scolumn %d — %d game(s) from striking" % [lane, col, col - 1]

# How much board an enemy takes up, spelled out for the info card.
func _size_text(e: GoalEnemyData) -> String:
	var cells: int = e.footprint_cells().size()
	var box: String = "%d x %d" % [e.footprint_rows(), e.footprint_cols()]
	if cells == e.footprint_rows() * e.footprint_cols():
		return "%s — %d cells of the board" % [box, cells]
	# A shaped body (an L) fills fewer cells than its box; say so, since the gap
	# is a real hole other enemies can stand in.
	var raw: String = String(e.size)
	var space: int = raw.find(" ")
	var shape: String = raw.substr(space + 1) if space >= 0 else ""
	return "%s %s — %d cells, the rest is a gap" % [box, shape, cells]

# The accent colour for an enemy whose front edge is at grid column `col`: red at
# the front (about to strike), amber a column back, gold farther out, orange for
# a boss.
func _col_accent(col: int, is_boss: bool) -> Color:
	if is_boss:
		return Color(0.95, 0.55, 0.2)
	if col <= 1:
		return UITheme.DANGER
	if col == 2:
		return Color(1.0, 0.62, 0.24)
	return UITheme.GOLD

# Sort key for painting order: bodies lower on the board draw over the ones above
# them, so the bottom edge of the footprint leads, then its top edge, then column.
func _draw_order_key(entry: Dictionary) -> int:
	var e: GoalEnemyData = entry.get("enemy")
	var row: int = int(entry.get("row", 0))
	var rows: int = e.footprint_rows() if e != null else 1
	return (row + rows - 1) * 10000 + row * 100 + int(entry.get("col", 1))

# Add one enemy to the overlay, spanning its whole footprint. Each cell it fills
# gets a tinted frame (so a 2x3 L visibly reads as an L), the art is drawn across
# the FULL bounding box — never cropped to the solid cells, so the parts poking
# out of the shape stay visible — and ❤ health / ⚔ damage / status badges sit in
# the corners. The current (now-playing) enemy gets a thicker border.
func _add_enemy_node(entry: Dictionary, is_current: bool) -> Control:
	var e: GoalEnemyData = entry.get("enemy")
	if e == null:
		return null
	var row: int = int(entry.get("row", 0))
	var col: int = int(entry.get("col", 1))
	var rows: int = e.footprint_rows()
	var cols: int = e.footprint_cols()
	var cells: Array = e.footprint_cells()
	var front: int = GameLoop2.GRID_COLS
	for off in cells:
		front = mini(front, col + int(off.x))

	var stun: int = int(entry.get("stun", 0))
	var accent: Color = _col_accent(front, e.is_boss())
	if stun > 0:
		accent = accent.lerp(Color(0.5, 0.7, 1.0), 0.5)
	var inst: int = int(entry.get("instance", 0))
	var selected: bool = inst > 0 and inst == _selected_instance

	# The node covers the bounding box, but only answers the mouse over the cells
	# the enemy really fills — an L's notch belongs to whoever stands in it.
	var node := FootprintControl.new()
	node.cells = cells
	node.cell_size = float(_CELL)
	node.step = float(_CELL_STEP)
	node.position = _cell_pos(row, col)
	node.size = _span_size(rows, cols)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.set_meta("instance", inst)
	_enemy_layer.add_child(node)
	_enemy_nodes[inst] = node

	# One frame per filled cell, positioned inside the node.
	var frames: Array = []
	for off in cells:
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.position = Vector2(off.x, off.y) * float(_CELL_STEP)
		frame.size = Vector2(_CELL, _CELL)
		node.add_child(frame)
		frames.append(frame)
	_style_enemy_cell(frames, accent, is_current, selected, false)

	# Enemies are click-to-inspect: hovering brightens the outline to advertise it
	# and lifts the whole body above its neighbours so an overlapped enemy can be
	# seen in full; clicking selects it and opens its info card.
	node.mouse_entered.connect(func():
		node.z_index = _Z_HOVER
		_style_enemy_cell(frames, accent, is_current, inst == _selected_instance, true))
	node.mouse_exited.connect(func():
		node.z_index = 0
		_style_enemy_cell(frames, accent, is_current, inst == _selected_instance, false))
	node.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_enemy_clicked(inst, entry, front, is_current))

	# One full-rect holder so corner-anchored overlays position correctly. It's
	# also what the resolve animation hides while a ghost slides into place.
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(holder)
	node.set_meta("holder", holder)

	# Art (or a tinted silhouette when the enemy has no image) across the whole
	# bounding box, aspect preserved so nothing is squashed or cut off.
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if e.image != null:
		art.texture = e.image
		if e.image.get_width() < _CELL or e.image.get_height() < _CELL:
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		art.modulate = accent
	holder.add_child(art)
	_add_enemy_badges(holder, entry, e, accent, selected)
	return node

# Overlay badges on an enemy's holder: boss skull top, health bottom-left, damage
# bottom-right, and the stun marker when frozen. All non-blocking so the cell
# tooltip still shows.
func _add_enemy_badges(holder: Control, entry: Dictionary, e: GoalEnemyData,
		accent: Color, selected: bool) -> void:
	var stun: int = int(entry.get("stun", 0))
	if e.is_boss():
		var skull := _corner_badge("☠", accent)
		skull.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 2)
		holder.add_child(skull)

	var hp: int = int(entry.get("health", e.health))
	var hp_lbl := _corner_badge("❤%d" % hp, Color(1.0, 0.5, 0.5))
	hp_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 2)
	holder.add_child(hp_lbl)

	var dmg_lbl := _corner_badge("⚔%d" % e.damage, Color(1.0, 0.8, 0.35))
	dmg_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
	holder.add_child(dmg_lbl)

	if stun > 0:
		var frozen := _corner_badge("❄", Color(0.6, 0.8, 1.0))
		frozen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 2)
		holder.add_child(frozen)

	# A selected enemy carries a marker so it's obvious which one the Push / Bomb
	# buttons on the toolbar are aimed at.
	if selected:
		var pin := _corner_badge("▸", UITheme.ACCENT)
		pin.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
		holder.add_child(pin)

# A single full-rect Control child of a cell PanelContainer, inside which art and
# corner-anchored overlays lay out freely (the PanelContainer stretches this one
# holder to fill; the holder itself imposes no layout on its children).
func _cell_holder(cell: PanelContainer) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(holder)
	return holder

# A small pill label used for the health / damage / status badges on a cell.
func _corner_badge(text: String, color: Color, font_size: int = 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A token for an enemy that has no cell on the field: either the overflow queue,
# or the game you're playing right now (which enters the grid when you report it).
# Clickable like a grid cell, with the same hover cue.
func _offgrid_token(entry: Dictionary, is_current: bool = false) -> Control:
	var e: GoalEnemyData = entry.get("enemy")
	var accent: Color = UITheme.ACCENT if is_current else UITheme.GOLD
	if e != null and e.is_boss():
		accent = Color(0.95, 0.55, 0.2)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(_CELL if is_current else 44, _CELL if is_current else 44)
	var paint := func(hovered: bool) -> void:
		var border: Color = accent.lerp(Color.WHITE, 0.55) if hovered else accent.lerp(UITheme.BG, 0.25)
		var fill: Color = UITheme.PANEL.lerp(UITheme.BG, 0.3)
		if hovered:
			fill = fill.lerp(Color.WHITE, 0.09)
		cell.add_theme_stylebox_override("panel", UITheme.flat(fill, 5, 2, 2 if is_current else 1, border))
	paint.call(false)
	if e != null:
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.mouse_entered.connect(func(): paint.call(true))
		cell.mouse_exited.connect(func(): paint.call(false))
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_enemy_clicked(int(entry.get("instance", 0)), entry, GameLoop2.OFFGRID_COL, is_current))
		cell.set_meta("instance", int(entry.get("instance", 0)))
		var holder := _cell_holder(cell)
		cell.set_meta("holder", holder)
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if e.image != null:
			art.texture = e.image
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			art.modulate = accent
		holder.add_child(art)
		# The game in play is labelled, so it reads as "waiting to enter" rather
		# than as another queued enemy.
		if is_current:
			var tag := _corner_badge("NOW PLAYING", UITheme.ACCENT, 9)
			tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 2)
			holder.add_child(tag)
			var dmg := _corner_badge("⚔%d" % e.damage, Color(1.0, 0.8, 0.35))
			dmg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
			holder.add_child(dmg)
	return cell

# --- resolve animation ----------------------------------------------------

const _FX_ATTACK_TIME: float = 0.55   # how long the front-line strike phase runs
const _FX_SLIDE_TIME: float = 0.34    # how long the advance slide takes

# Where every enemy is drawn right now: instance -> global Rect2 of its cell (or
# off-field token). Captured before a resolve and again after, so the difference
# is exactly the movement to animate.
func _battlefield_positions() -> Dictionary:
	var out: Dictionary = {}
	if _battlefield == null:
		return out
	for inst in _enemy_nodes:
		var node: Control = _enemy_nodes[inst]
		if is_instance_valid(node):
			out[int(inst)] = node.get_global_rect()
	if _offgrid_box != null:
		for tok in _offgrid_box.get_children():
			if tok.has_meta("instance") and int(tok.get_meta("instance")) > 0:
				out[int(tok.get_meta("instance"))] = tok.get_global_rect()
	return out

# The holder Control of whichever node currently draws `instance`, so it can be
# hidden while its ghost slides in.
func _holder_for_instance(instance: int) -> Control:
	var node: Variant = _enemy_nodes.get(instance)
	if node != null and is_instance_valid(node) and node.has_meta("holder"):
		return node.get_meta("holder")
	if _offgrid_box != null:
		for tok in _offgrid_box.get_children():
			if tok.has_meta("instance") and int(tok.get_meta("instance")) == instance:
				return tok.get_meta("holder") if tok.has_meta("holder") else null
	return null

func _clear_fx() -> void:
	if _fx_layer == null:
		return
	for c in _fx_layer.get_children():
		c.queue_free()

# Play back the resolve the player just triggered: the front line strikes (each
# attacker flashes and throws its damage number at the hero, who recoils), then
# the whole field slides one column closer — including the game you just reported,
# which walks in from off-field onto the spawn column.
func _animate_resolve(before: Dictionary, res: Dictionary) -> void:
	if _fx_layer == null or not is_inside_tree():
		return
	_clear_fx()
	var after: Dictionary = _battlefield_positions()
	_animating = true

	# 1. The strike: flash each attacker where it stood and float its damage.
	var hero_rect: Rect2 = _hero_icon.get_global_rect()
	var struck: bool = false
	for a in res.get("attacks", []):
		if not (a is Dictionary) or not a.has("damage"):
			continue
		var inst: int = int(a.get("instance", 0))
		if not before.has(inst):
			continue
		struck = true
		var from: Rect2 = before[inst]
		_spawn_strike_flash(from)
		_spawn_damage_number(int(a["damage"]), from, hero_rect)
	if struck:
		_punch_hero()

	# 2. The advance: ghost-slide every enemy whose cell changed, after the strike
	#    has played. The real art stays hidden until its ghost lands.
	for inst in after.keys():
		if not before.has(inst):
			continue
		var from_rect: Rect2 = before[inst]
		var to_rect: Rect2 = after[inst]
		if from_rect.position.distance_to(to_rect.position) < 2.0:
			continue
		_spawn_slide_ghost(inst, from_rect, to_rect)

	# Release the animating flag once the whole sequence has played out.
	var done := create_tween()
	done.tween_interval(_FX_ATTACK_TIME + _FX_SLIDE_TIME)
	done.tween_callback(func(): _animating = false)

# A white burst over an attacking enemy's cell.
func _spawn_strike_flash(rect: Rect2) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.75)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.size = rect.size
	_fx_layer.add_child(flash)
	flash.global_position = rect.position
	var t := flash.create_tween()
	t.tween_property(flash, "modulate:a", 0.0, 0.42).set_trans(Tween.TRANS_SINE)
	t.tween_callback(flash.queue_free)

# A damage number thrown from the attacker toward the hero.
func _spawn_damage_number(amount: int, from: Rect2, hero: Rect2) -> void:
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(lbl)
	lbl.global_position = from.position + Vector2(from.size.x * 0.25, 0)
	var target: Vector2 = hero.position + Vector2(hero.size.x * 0.25, -18)
	var t := lbl.create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "global_position", target, _FX_ATTACK_TIME * 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, _FX_ATTACK_TIME * 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.set_parallel(false)
	t.tween_callback(lbl.queue_free)

# The hero recoils when the front line connects.
func _punch_hero() -> void:
	if _hero_icon == null:
		return
	_hero_icon.pivot_offset = _hero_icon.size * 0.5
	var t := _hero_icon.create_tween()
	t.tween_property(_hero_icon, "scale", Vector2(1.14, 0.9), 0.09).set_trans(Tween.TRANS_BACK)
	t.tween_property(_hero_icon, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var f := _hero_icon.create_tween()
	f.tween_property(_hero_icon, "modulate", Color(1.0, 0.55, 0.55), 0.09)
	f.tween_property(_hero_icon, "modulate", Color.WHITE, 0.34)

# Slide a copy of an enemy from where it stood to where it now stands, hiding the
# real one until it lands.
func _spawn_slide_ghost(instance: int, from_rect: Rect2, to_rect: Rect2) -> void:
	var entry: Dictionary = _stack_entry(instance)
	var e: GoalEnemyData = entry.get("enemy") if not entry.is_empty() else null
	var ghost := TextureRect.new()
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if e != null and e.image != null:
		ghost.texture = e.image
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.size = from_rect.size
	_fx_layer.add_child(ghost)
	ghost.global_position = from_rect.position

	var holder: Control = _holder_for_instance(instance)
	if holder != null:
		holder.modulate.a = 0.0

	var t := ghost.create_tween()
	t.tween_interval(_FX_ATTACK_TIME)
	t.set_parallel(true)
	t.tween_property(ghost, "global_position", to_rect.position, _FX_SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(ghost, "size", to_rect.size, _FX_SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.chain().tween_callback(func():
		if is_instance_valid(holder):
			holder.modulate.a = 1.0
		ghost.queue_free())

# --- inline kill-drops (§8) ------------------------------------------------

# A defeated enemy dropped loot: roll an item and queue it as collectable field
# loot. Skipped once the run is over (win/lose screens take over the board).
func _on_enemy_defeated(_enemy: GoalEnemyData) -> void:
	if GameLoop2.run_over:
		return
	var item: ItemData = _roll_drop()
	if item == null:
		return
	_drop_queue.append({"item": item})
	# The resolve that produced this defeat also emits loop_changed -> _refresh,
	# which repaints the battlefield and places the drop; repaint here too in case
	# the defeat came from a direct action (bomb never drops, fulfil does).
	if _battlefield != null:
		_refresh_battlefield()

# Roll one drop item from the games-first reward pool, weighted by rarity the same
# way the RewardScreen chest roll is (§8).
func _roll_drop() -> ItemData:
	var pool: Array = Data.reward_item2_pool()
	if pool.is_empty():
		return null
	var target: int = _roll_drop_rarity()
	var bucket: Array = pool.filter(func(it): return int(it.rarity) == target)
	if bucket.is_empty():
		bucket = pool
	return bucket[_rng.randi_range(0, bucket.size() - 1)]

func _roll_drop_rarity() -> int:
	var roll: float = _rng.randf() * 100.0
	if roll < 75.0:
		return ItemData.Rarity.COMMON
	if roll < 95.0:
		return ItemData.Rarity.UNCOMMON
	if _rng.randf() < 0.1:
		return ItemData.Rarity.LEGENDARY
	return ItemData.Rarity.RARE

# Place each queued drop as collectable loot in the nearest free cell (front
# column and top rows first), overflowing into the side lane if the grid is
# packed. A cell is free when no enemy's FOOTPRINT covers it, so loot can land in
# the notch of an L-shaped body. Called at the end of every battlefield repaint.
func _place_drops() -> void:
	if _phase == Phase.OVER or _drop_queue.is_empty():
		return
	var taken: Dictionary = GameLoop2.occupancy()
	var qi: int = 0
	for col in range(1, GameLoop2.GRID_COLS + 1):
		for row in range(GameLoop2.GRID_ROWS):
			if qi >= _drop_queue.size():
				return
			if taken.has(Vector2i(col, row)):
				continue
			var node := _make_drop_node(_drop_queue[qi])
			node.position = _cell_pos(row, col)
			node.size = Vector2(_CELL, _CELL)
			# Loot is added after every enemy, so it stays reachable on a busy board.
			_enemy_layer.add_child(node)
			qi += 1
	# Grid is full — the remaining drops wait as tokens in the overflow lane.
	while qi < _drop_queue.size():
		_offgrid_box.add_child(_drop_token(_drop_queue[qi]))
		qi += 1

# One cell of collectable loot: the item's art, a rarity-tinted border, and a
# Collect / Skip pair of buttons.
func _make_drop_node(drop: Dictionary) -> PanelContainer:
	var cell := PanelContainer.new()
	var item: ItemData = drop["item"]
	var col: Color = UITheme.rarity_color(int(item.rarity))
	cell.add_theme_stylebox_override("panel", UITheme.flat(col.lerp(UITheme.BG, 0.55), 6, 2, 2, col))
	cell.tooltip_text = "%s\n%s" % [item.display_name, item.description if String(item.description) != "" else "A dropped relic."]
	var holder := _cell_holder(cell)

	if item.image != null:
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.texture = item.image
		if item.image.get_width() < _CELL or item.image.get_height() < _CELL:
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(art)

	var tag := _corner_badge("✦ LOOT", col.lerp(Color.WHITE, 0.4))
	tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 2)
	holder.add_child(tag)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 2)
	btns.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 2)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var take := _mini_button("✓", func(): _collect_drop(drop))
	take.tooltip_text = "Collect %s" % item.display_name
	take.add_theme_color_override("font_color", UITheme.SUCCESS)
	var skip := _mini_button("✗", func(): _skip_drop(drop))
	skip.tooltip_text = "Skip this drop"
	btns.add_child(take)
	btns.add_child(skip)
	holder.add_child(btns)
	return cell

# A drop shown as a token in the overflow lane (used when the grid is packed).
func _drop_token(drop: Dictionary) -> Control:
	var item: ItemData = drop["item"]
	var col: Color = UITheme.rarity_color(int(item.rarity))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if item.image != null:
		icon.texture = item.image
	row.add_child(icon)
	row.add_child(_mini_button("✓", func(): _collect_drop(drop)))
	row.add_child(_mini_button("✗", func(): _skip_drop(drop)))
	row.tooltip_text = item.display_name
	return row

func _collect_drop(drop: Dictionary) -> void:
	if not _drop_queue.has(drop):
		return
	_drop_queue.erase(drop)
	var item: ItemData = drop["item"]
	GameState.add_item(item)
	GameLog.add("Collected %s." % item.display_name, Color(0.7, 1.0, 0.7))
	_refresh_battlefield()

func _skip_drop(drop: Dictionary) -> void:
	if not _drop_queue.has(drop):
		return
	_drop_queue.erase(drop)
	GameLog.add("Skipped %s." % String(drop["item"].display_name), Color(0.8, 0.8, 0.8))
	_refresh_battlefield()

# A TextureRect that renders `tex` crisply (nearest-neighbour) when it's small
# pixel art scaled up, keeping smooth filtering for already-large art.
func _crisp_tex(tex: Texture2D, size: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null and (tex.get_width() < size or tex.get_height() < size):
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr

# Toggle nearest-neighbour on an already-built TextureRect after its texture is
# assigned, so dynamically-set enemy art stays crisp when it's small pixel art.
func _apply_crisp(tr: TextureRect, tex: Texture2D) -> void:
	if tex != null and (tex.get_width() < int(tr.custom_minimum_size.x) or tex.get_height() < int(tr.custom_minimum_size.y)):
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE

func _result_text(res: Dictionary) -> String:
	var parts: Array = []
	if int(res.get("drops", 0)) > 0:
		parts.append("%d drop(s)" % int(res["drops"]))
	if int(res.get("damage_taken", 0)) > 0:
		parts.append("took %d damage" % int(res["damage_taken"]))
	if int(res.get("blocked", 0)) > 0:
		parts.append("blocked %d" % int(res["blocked"]))
	if parts.is_empty():
		parts.append("no effect")
	return "[i]Last game: %s.[/i]" % ", ".join(parts)

func _tier_name(e: GoalEnemyData) -> String:
	return ["Low", "Medium", "High", "Insane"][clampi(int(e.difficulty), 0, 3)]

func _on_run_lost() -> void:
	_phase = Phase.OVER
	_drop_queue.clear()
	_show_banner("💀  Run lost — Health reached 0.", Color(0.9, 0.3, 0.25))

func _on_run_won() -> void:
	_phase = Phase.OVER
	_drop_queue.clear()
	_show_banner("🏆  You cleared the Amulet — you win!", Color(0.95, 0.8, 0.2))

func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.show()
	_choices_row.visible = false
	_play_panel.get_parent().visible = false
	_boss_banner.get_parent().visible = false

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

	root.add_child(_section("Choose a game to travel to:"))
	# Controls row (Dash) — populated per refresh.
	_controls_row = HBoxContainer.new()
	_controls_row.add_theme_constant_override("separation", 8)
	root.add_child(_controls_row)
	_choices_row = HFlowContainer.new()
	_choices_row.add_theme_constant_override("h_separation", 12)
	_choices_row.add_theme_constant_override("v_separation", 10)
	root.add_child(_choices_row)

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
	root.add_child(preview_wrap)

	# Verification card — shown once a game is chosen (the honour-system self-
	# report). Wrapped in a bordered panel so it reads as a distinct "report your
	# result" step. The wrapper carries the visibility toggle (see _refresh).
	var play_wrap := PanelContainer.new()
	play_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.ACCENT.lerp(UITheme.BORDER, 0.5), 12, 16, 1))
	_play_panel = VBoxContainer.new()
	_play_panel.add_theme_constant_override("separation", 10)
	play_wrap.add_child(_play_panel)
	_play_panel.set_meta("wrap", play_wrap)

	var verify_hdr := Label.new()
	verify_hdr.text = "◆  Report your result"
	verify_hdr.add_theme_font_size_override("font_size", 15)
	verify_hdr.add_theme_color_override("font_color", UITheme.GOLD)
	_play_panel.add_child(verify_hdr)

	var np_box := HBoxContainer.new()
	np_box.add_theme_constant_override("separation", 14)
	_now_playing_img = _enemy_image_rect()
	_now_playing_img.custom_minimum_size = Vector2(112, 112)
	var img_frame := PanelContainer.new()
	img_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 8, 6, 1, UITheme.BORDER))
	img_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	img_frame.add_child(_now_playing_img)
	np_box.add_child(img_frame)
	_now_playing = _panel_label()
	_now_playing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_playing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	np_box.add_child(_now_playing)
	_play_panel.add_child(np_box)

	# Launch-the-real-game row (populated per game — only games with a launch
	# target get a button).
	_launch_row = HBoxContainer.new()
	_launch_row.add_theme_constant_override("separation", 8)
	_play_panel.add_child(_launch_row)

	# Verification checklist (populated per game): the main goal, the character's
	# level-up challenge, and any following enemy whose goal you also cleared. Tick
	# what you did, then press the single Completed Game button below.
	_verify_box = VBoxContainer.new()
	_verify_box.add_theme_constant_override("separation", 4)
	_play_panel.add_child(_verify_box)

	_play_panel.add_child(HSeparator.new())
	var done := Button.new()
	done.text = "✓  Completed Game"
	done.custom_minimum_size = Vector2(0, 46)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.add_theme_stylebox_override("normal", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.5), 8, 10, 2, UITheme.SUCCESS))
	done.add_theme_stylebox_override("hover", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.35), 8, 10, 2, UITheme.SUCCESS))
	done.add_theme_color_override("font_color", UITheme.SUCCESS.lerp(Color.WHITE, 0.45))
	done.add_theme_font_size_override("font_size", 17)
	done.pressed.connect(func(): report(_goal_met()))
	_play_panel.add_child(done)
	play_wrap.hide()
	root.add_child(play_wrap)

	root.add_child(_section("Scrolls (read on the overworld):"))
	_scrolls_box = VBoxContainer.new()
	_scrolls_box.add_theme_constant_override("separation", 4)
	root.add_child(_scrolls_box)

	root.add_child(_section("Items:"))
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 4)
	root.add_child(_items_box)

	root.add_child(_section("Battlefield  —  enemies close in one column each game:"))
	_stack = _panel_label()
	root.add_child(_stack)
	root.add_child(_build_battlefield())
	_log = _panel_label()
	root.add_child(_log)

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

func _mini_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b
