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
var _stack: RichTextLabel           # "Following you" summary line
var _stack_box: HFlowContainer      # "Following you" enemy cards
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
	GameLoop2.beat_game(goal_met, fulfilled_instances)
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
		return
	if was_amulet and goal_met:
		GameLoop2.clear_amulet()
		return
	_phase = Phase.SELECT
	_build_choices()
	_refresh()

func _exit_tree() -> void:
	GameState.clear_overworld_context(self)
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
	_refresh_followers()
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
	return "[b]%s[/b]  →  %s%s\n[b]GOAL (%s):[/b] %s   [i](%s / %s / dmg %d)[/i]" % [
		game.display_name, kind, e.display_name,
		String(e.goal_type).capitalize(), e.goal,
		String(e.game_type).capitalize(), _tier_name(e), e.damage,
	]

func _now_playing_text() -> String:
	if _chosen.is_empty():
		return ""
	return "[b]Now playing:[/b] %s\n%s" % [_chosen["game"].display_name, _enemy_preview_text(_chosen)]

func _hud_text() -> String:
	return "[b]Health[/b] %d/%d   [b]Block[/b] %d      [b]Tier[/b] %s      [b]Bash[/b] %d  [b]Dash[/b] %d  [b]Transmute[/b] %d  [b]Scramble[/b] %d  [b]Bombs[/b] %d  [b]Keys[/b] %d  [b]Scrolls[/b] %d   [b]Chests[/b] %d" % [
		GameState.hp, GameState.max_hp, GameState.block,
		RunDifficulty.tier_name(_current_tier()),
		GameState.bash, GameState.dash_charges, GameState.transmute,
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
		return "[b]Following you:[/b] none"
	return "[b]Following you[/b] — %d on your tail, %d damage next game" % [
		following, GameLoop2.stacked_damage_per_game()]

# Rebuild the "Following you" cards. Each shows the enemy's art, name, a countdown
# to when it will hit ("X Games away"), and its Health / Damage; the rest of its
# info surfaces on hover (tooltip). The just-picked enemy (PLAYING phase) is shown
# too — it can't hit this game (the one-game grace, §7.2), so it first strikes 2
# games out unless you clear its goal.
func _refresh_followers() -> void:
	if _stack_box == null:
		return
	for c in _stack_box.get_children():
		c.queue_free()
	if _phase == Phase.PLAYING and not _chosen.is_empty():
		var cur: GoalEnemyData = _chosen.get("enemy")
		if cur != null:
			_stack_box.add_child(_follower_card(cur, 2, 0, true))
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var stun: int = int(entry.get("stun", 0))
		# A stacked enemy hits on the very next game beaten; each Stun pushes that
		# one game later.
		_stack_box.add_child(_follower_card(e, 1 + stun, stun, false))

func _follower_card(e: GoalEnemyData, games_away: int, stun: int, is_current: bool) -> Control:
	var accent: Color
	if e.is_boss():
		accent = Color(0.95, 0.55, 0.2)
	elif games_away <= 1:
		accent = UITheme.DANGER
	elif games_away == 2:
		accent = Color(1.0, 0.62, 0.24)
	else:
		accent = UITheme.GOLD

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 8, 8, 2 if is_current else 1, accent))
	card.custom_minimum_size = Vector2(150, 0)
	card.tooltip_text = _follower_tooltip(e, games_away, stun, is_current)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	if e.image != null:
		var art := _crisp_tex(e.image, 64)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(art)

	var nm := Label.new()
	nm.text = ("☠ " if e.is_boss() else "") + e.display_name
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(138, 0)
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", accent)
	vb.add_child(nm)

	var when := Label.new()
	when.text = ("Hits next game!" if games_away <= 1 else "%d games away" % games_away) + ("  (stunned)" if stun > 0 else "")
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	when.add_theme_font_size_override("font_size", 12)
	when.add_theme_color_override("font_color", accent)
	vb.add_child(when)

	var stats := Label.new()
	stats.text = "❤ %d    ⚔ %d dmg" % [e.health, e.damage]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 11)
	stats.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	vb.add_child(stats)
	return card

func _follower_tooltip(e: GoalEnemyData, games_away: int, stun: int, is_current: bool) -> String:
	var lines: Array = [e.display_name + ("  (BOSS)" if e.is_boss() else "")]
	if e.goal != "":
		lines.append("Goal (%s): %s" % [String(e.goal_type).capitalize(), e.goal])
	lines.append("Type: %s  •  Tier %s" % [String(e.game_type).capitalize(), _tier_name(e)])
	if e.source_game != "":
		lines.append("From: %s" % e.source_game)
	lines.append("Health %d  •  Damage %d / game" % [e.health, e.damage])
	if is_current:
		lines.append("Just started following — first hits in %d games unless you clear its goal." % games_away)
	elif stun > 0:
		lines.append("Stunned — skips its next %d attack(s)." % stun)
	if String(e.tag) != "":
		lines.append("Tag: %s" % String(e.tag))
	return "\n".join(lines)

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
	_show_banner("💀  Run lost — Health reached 0.", Color(0.9, 0.3, 0.25))

func _on_run_won() -> void:
	_phase = Phase.OVER
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
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	add_child(root)

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

	root.add_child(_section("Following you:"))
	_stack = _panel_label()
	root.add_child(_stack)
	_stack_box = HFlowContainer.new()
	_stack_box.add_theme_constant_override("h_separation", 10)
	_stack_box.add_theme_constant_override("v_separation", 10)
	root.add_child(_stack_box)
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
