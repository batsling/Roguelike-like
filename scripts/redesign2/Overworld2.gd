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
var _fulfil_box: VBoxContainer
var _fulfil_checks: Array = []      # [{check: CheckBox, instance: int}]
var _stack: RichTextLabel
var _log: RichTextLabel

func _ready() -> void:
	_rng.randomize()
	_build_ui()
	if not GameLoop2.loop_changed.is_connected(_refresh):
		GameLoop2.loop_changed.connect(_refresh)
	if not GameLoop2.run_lost.is_connected(_on_run_lost):
		GameLoop2.run_lost.connect(_on_run_lost)
	if not GameLoop2.run_won.is_connected(_on_run_won):
		GameLoop2.run_won.connect(_on_run_won)
	start_run()

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
	_banner.hide()
	_build_choices()
	_refresh()

# Travel to the offered game at `index`: its goal-enemy spawns and we move there.
func pick(index: int) -> void:
	if _phase != Phase.SELECT or index < 0 or index >= _choices.size():
		return
	_chosen = _choices[index]
	GameLoop2.choose_game(_chosen["enemy"])
	# Move to the graph SLOT (a transmuted card plays an off-graph game but keeps
	# its position on the route toward the amulet).
	GameState.set_current_game(_chosen["slot"])
	_phase = Phase.PLAYING
	_populate_play_panel()
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
	var fulfilled_instances: Array = fulfilled if fulfilled is Array else _ticked_fulfilments()
	var was_amulet: bool = bool(_chosen.get("amulet", false))
	GameLoop2.beat_game(goal_met, fulfilled_instances)
	GameState.games_played += 1
	_chosen = {}
	_transmuted.clear()   # transmutes apply only to the offering you moved from
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
	_stack.text = _stack_text()
	if not GameLoop2.last_result.is_empty():
		_log.text = _result_text(GameLoop2.last_result)
	_boss_banner.visible = _boss_round and _phase == Phase.SELECT
	_choices_row.visible = _phase == Phase.SELECT
	_play_panel.visible = _phase == Phase.PLAYING
	if _phase == Phase.SELECT:
		_render_choices()
	elif _phase == Phase.PLAYING:
		_now_playing.text = _now_playing_text()
		_now_playing_img.texture = null if _chosen.is_empty() else _enemy_texture(_chosen)

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

	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(140, 105)
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
	card.add_child(btn)

	var name_lbl := Label.new()
	name_lbl.text = ("☠ " if choice["boss"] else ("🏆 " if choice["amulet"] else "")) + game.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(140, 0)
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
	for c in _fulfil_box.get_children():
		c.queue_free()
	_fulfil_checks.clear()
	if _chosen.is_empty():
		return
	var game: GameData = _chosen["game"]
	if game.has_launch_target():
		var play_btn := Button.new()
		play_btn.text = "▶ Play %s" % game.display_name
		play_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		play_btn.pressed.connect(func(): game.launch())
		_launch_row.add_child(play_btn)
	if not GameLoop2.stack.is_empty():
		var hdr := Label.new()
		hdr.text = "Also fulfilled a follower's goal this game? Tick it:"
		hdr.add_theme_font_size_override("font_size", 13)
		hdr.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		_fulfil_box.add_child(hdr)
		for entry in GameLoop2.stack:
			var e: GoalEnemyData = entry["enemy"]
			var cb := CheckBox.new()
			cb.text = "%s — %s" % [e.display_name, e.goal]
			_fulfil_box.add_child(cb)
			_fulfil_checks.append({"check": cb, "instance": int(entry["instance"])})

# The instances the player ticked as fulfilled this game.
func _ticked_fulfilments() -> Array:
	var out: Array = []
	for f in _fulfil_checks:
		if is_instance_valid(f["check"]) and f["check"].button_pressed:
			out.append(f["instance"])
	return out

func _show_preview(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	_preview.text = _enemy_preview_text(_choices[index])
	_preview_img.texture = _enemy_texture(_choices[index])

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
	return "[b]Health[/b] %d/%d   [b]Block[/b] %d      [b]Tier[/b] %s      [b]Bash[/b] %d  [b]Dash[/b] %d  [b]Transmute[/b] %d  [b]Scramble[/b] %d  [b]Bombs[/b] %d  [b]Keys[/b] %d   [b]Chests[/b] %d" % [
		GameState.hp, GameState.max_hp, GameState.block,
		RunDifficulty.tier_name(_current_tier()),
		GameState.bash, GameState.dash_charges, GameState.transmute,
		GameState.scramble, GameState.bombs, GameState.keys, GameState.pending_chests,
	]

func _stack_text() -> String:
	if GameLoop2.stack.is_empty():
		return "[b]Following enemies:[/b] none"
	var lines: Array = ["[b]Following enemies[/b] (%d dmg/game):" % GameLoop2.stacked_damage_per_game()]
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var stun: int = int(entry.get("stun", 0))
		lines.append("  • %s — dmg %d%s — goal: %s" % [
			e.display_name, e.damage,
			("  [stunned x%d]" % stun) if stun > 0 else "", e.goal,
		])
	return "\n".join(lines)

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
	_play_panel.visible = false
	_boss_banner.visible = false

# --- UI construction ------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	title.text = "Games-First — Overworld"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
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
	root.add_child(_hud)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.hide()
	root.add_child(_banner)

	_boss_banner = Label.new()
	_boss_banner.text = "⚠  BOSS INCOMING  ⚠"
	_boss_banner.add_theme_font_size_override("font_size", 20)
	_boss_banner.add_theme_color_override("font_color", Color(0.95, 0.55, 0.2))
	_boss_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_banner.hide()
	root.add_child(_boss_banner)

	root.add_child(_section("Choose a game to travel to:"))
	_choices_row = HFlowContainer.new()
	_choices_row.add_theme_constant_override("h_separation", 12)
	_choices_row.add_theme_constant_override("v_separation", 10)
	root.add_child(_choices_row)

	# Hover preview: the enemy's art beside its name + goal.
	var preview_box := HBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 12)
	_preview_img = _enemy_image_rect()
	preview_box.add_child(_preview_img)
	_preview = _panel_label()
	_preview.custom_minimum_size = Vector2(0, 40)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_box.add_child(_preview)
	root.add_child(preview_box)

	# Play panel — shown once a game is chosen (the honour-system self-report).
	_play_panel = VBoxContainer.new()
	_play_panel.add_theme_constant_override("separation", 8)
	var np_box := HBoxContainer.new()
	np_box.add_theme_constant_override("separation", 12)
	_now_playing_img = _enemy_image_rect()
	np_box.add_child(_now_playing_img)
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

	# Old-goal fulfilment checklist (populated per game from the follower stack):
	# tick any following enemy whose goal you also fulfilled while playing (§2).
	_fulfil_box = VBoxContainer.new()
	_fulfil_box.add_theme_constant_override("separation", 2)
	_play_panel.add_child(_fulfil_box)

	var report_row := HBoxContainer.new()
	report_row.add_theme_constant_override("separation", 8)
	var met := Button.new()
	met.text = "Beat it — Goal MET ✓"
	met.pressed.connect(func(): report(true))
	report_row.add_child(met)
	var miss := Button.new()
	miss.text = "Beat it — Goal NOT met ✗"
	miss.pressed.connect(func(): report(false))
	report_row.add_child(miss)
	_play_panel.add_child(report_row)
	_play_panel.hide()
	root.add_child(_play_panel)

	root.add_child(_section("Following you:"))
	_stack = _panel_label()
	root.add_child(_stack)
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
	l.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
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
