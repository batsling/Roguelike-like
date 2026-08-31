extends Control

# PlaySession2 — a minimal, self-contained play harness for the games-first loop
# (docs/games-first-redesign.md). It drives GameLoop2 + GameState with buttons so
# the no-combat loop can be played and validated end-to-end WITHOUT the overworld
# graph or the combat scenes (which stay untouched until the cut). It is also the
# seed of the real overworld panel and the OBS companion HUD (§9): the whole UI
# just reads GameLoop2 + GameState and refreshes on `loop_changed`.
#
# The UI is built in code (no bespoke .tscn wiring) and every action is a public
# method, so a headless test can drive a full run through the same entry points
# the buttons use.

const TYPES: Array[StringName] = [&"action", &"deckbuilder", &"traditional", &"strategy"]

var _hud: RichTextLabel
var _enemy: RichTextLabel
var _stack: RichTextLabel
var _log: RichTextLabel
var _banner: Label
var _beat_met: Button
var _beat_miss: Button
var _pick_buttons: Array = []

func _ready() -> void:
	_build_ui()
	if not GameLoop2.loop_changed.is_connected(_refresh):
		GameLoop2.loop_changed.connect(_refresh)
	if not GameLoop2.run_lost.is_connected(_on_run_lost):
		GameLoop2.run_lost.connect(_on_run_lost)
	if not GameLoop2.run_won.is_connected(_on_run_won):
		GameLoop2.run_won.connect(_on_run_won)
	# Open on a default run so the harness is immediately playable.
	restart(&"isaac")

# --- public actions (buttons + tests call these) --------------------------

func restart(character_id: StringName) -> void:
	var ch: CharacterData = Data.get_character2(character_id)
	if ch == null:
		var roster: Array = Data.all_characters2()
		ch = roster[0] if not roster.is_empty() else null
	GameLoop2.start_run(ch)
	_banner.hide()
	_set_pick_enabled(true)
	_refresh()

# Pick a game of `game_type` — rolls + spawns its goal-enemy at the run's tier.
func pick(game_type: StringName) -> void:
	if GameLoop2.run_over or GameLoop2.has_arrivals():
		return
	GameLoop2.choose_game_of_type(game_type, -1)
	_refresh()

# Report the result of playing the chosen game (the honour-system self-report).
func beat(goal_met: bool) -> void:
	if GameLoop2.run_over or not GameLoop2.has_arrivals():
		return
	GameLoop2.beat_game(goal_met)
	_refresh()

func scramble() -> void:
	GameLoop2.scramble()
	_refresh()

func bomb_first() -> void:
	if not GameLoop2.stack.is_empty():
		GameLoop2.bomb(int(GameLoop2.stack[0]["instance"]))
	_refresh()

func stun_first() -> void:
	if not GameLoop2.stack.is_empty():
		GameLoop2.stun(int(GameLoop2.stack[0]["instance"]))
	_refresh()

func push_first() -> void:
	if not GameLoop2.stack.is_empty():
		GameLoop2.push(int(GameLoop2.stack[0]["instance"]))
	_refresh()

# --- rendering ------------------------------------------------------------

func _refresh(_a = null) -> void:
	if _hud == null:
		return
	_hud.text = _hud_text()
	_enemy.text = _enemy_text()
	_stack.text = _stack_text()
	if not GameLoop2.last_result.is_empty():
		_log.text = _result_text(GameLoop2.last_result)
	var can_beat: bool = GameLoop2.has_arrivals() and not GameLoop2.run_over
	_beat_met.disabled = not can_beat
	_beat_miss.disabled = not can_beat
	_set_pick_enabled(not GameLoop2.has_arrivals() and not GameLoop2.run_over)

func _hud_text() -> String:
	return "[b]Health[/b] %d/%d    [b]Temp Shields[/b] %d  [b]Shields[/b] %d        [b]Bash[/b] %d  [b]Dash[/b] %d  [b]Push[/b] %d  [b]Transmute[/b] %d  [b]Scramble[/b] %d  [b]Bombs[/b] %d  [b]Keys[/b] %d    [b]Chests[/b] %d" % [
		GameState.hp, GameState.max_hp, GameState.shields, GameState.bonus_shields,
		GameState.bash, GameState.dash_charges, GameState.push, GameState.transmute,
		GameState.scramble, GameState.bombs, GameState.keys, GameState.pending_chests,
	]

func _enemy_text() -> String:
	if not GameLoop2.has_arrivals():
		return "[i]No game chosen — pick a game type below to spawn its enemy.[/i]"
	var e: GoalEnemyData = GameLoop2.arrival()["enemy"]
	var boss_tag: String = "  [color=#e0b020][b]☠ BOSS[/b][/color]" if e.is_boss() else ""
	# Who came WITH it (§7.5). Named here rather than left to be spotted in the
	# stack below, because the escort is the one body on that list the player did
	# not choose.
	var escort: GoalEnemyData = GameLoop2.escort_enemy()
	var escort_line: String = "" if escort == null else \
		"\n[color=#e06060]⚠ %s spawned alongside it — its goal is on the stack below.[/color]" % escort.display_name
	return "[b]Now playing:[/b] %s%s  ([i]%s / %s / dmg %d[/i])\n[b]GOAL (%s):[/b] %s%s" % [
		e.display_name, boss_tag, String(e.game_type).capitalize(),
		RunDifficulty.tier_name(int(e.difficulty)), e.damage, String(e.goal_type).capitalize(),
		GameLoop2.goal_text_for(GameLoop2.arrival()), escort_line,
	]

func _stack_text() -> String:
	if GameLoop2.stack.is_empty():
		return "[b]Following enemies:[/b] none"
	var lines: Array = ["[b]Following enemies[/b] (%d per lost run):" % GameLoop2.damage_per_lost_run()]
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var stun: int = GameLoop2.stun_stacks(entry)
		lines.append("  • %s — dmg %d%s — goal: %s" % [
			e.display_name, e.damage,
			("  [stunned x%d]" % stun) if stun > 0 else "",
			GameLoop2.goal_text_for(entry),
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


# Spawn a boss at the run's current tier (§7.1 bosses appear on a tier change).
func pick_boss() -> void:
	if GameLoop2.run_over or GameLoop2.has_arrivals():
		return
	GameLoop2.choose_boss(&"", -1)
	_refresh()

func _on_run_lost() -> void:
	_show_banner("💀  Run lost — Health reached 0.", Color(0.9, 0.3, 0.25))

func _on_run_won() -> void:
	_show_banner("🏆  You cleared the Amulet — you win!", Color(0.95, 0.8, 0.2))

func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.show()
	_set_pick_enabled(false)
	_beat_met.disabled = true
	_beat_miss.disabled = true

func _set_pick_enabled(on: bool) -> void:
	for b in _pick_buttons:
		b.disabled = not on

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
	header.add_child(_title("Games-First — play harness"))
	var menu_btn := Button.new()
	menu_btn.text = "← Menu"
	menu_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn"))
	header.add_child(menu_btn)
	root.add_child(header)
	_hud = _panel_label()
	root.add_child(_hud)
	_enemy = _panel_label()
	root.add_child(_enemy)
	_stack = _panel_label()
	root.add_child(_stack)
	_log = _panel_label()
	root.add_child(_log)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.hide()
	root.add_child(_banner)

	# Pick-a-game row.
	root.add_child(_section("1 · Pick a game (spawns its enemy):"))
	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 8)
	for t in TYPES:
		var b := Button.new()
		b.text = String(t).capitalize()
		b.pressed.connect(func(): pick(t))
		pick_row.add_child(b)
		_pick_buttons.append(b)
	var boss_btn := Button.new()
	boss_btn.text = "☠ Boss (tier change)"
	boss_btn.pressed.connect(pick_boss)
	pick_row.add_child(boss_btn)
	_pick_buttons.append(boss_btn)
	root.add_child(pick_row)

	# Beat / result row.
	root.add_child(_section("2 · Play the real game, then report:"))
	var beat_row := HBoxContainer.new()
	beat_row.add_theme_constant_override("separation", 8)
	_beat_met = Button.new()
	_beat_met.text = "Beat — Goal MET ✓"
	_beat_met.pressed.connect(func(): beat(true))
	beat_row.add_child(_beat_met)
	_beat_miss = Button.new()
	_beat_miss.text = "Beat — Goal NOT met ✗"
	_beat_miss.pressed.connect(func(): beat(false))
	beat_row.add_child(_beat_miss)
	root.add_child(beat_row)

	# Verbs row.
	root.add_child(_section("Verbs / consumables:"))
	var verb_row := HBoxContainer.new()
	verb_row.add_theme_constant_override("separation", 8)
	verb_row.add_child(_action_button("Scramble enemy", scramble))
	verb_row.add_child(_action_button("Bomb 1st follower", bomb_first))
	verb_row.add_child(_action_button("Stun 1st follower", stun_first))
	verb_row.add_child(_action_button("Push 1st follower", push_first))
	root.add_child(verb_row)

	# Character restart row.
	root.add_child(_section("Restart as:"))
	var char_row := HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 8)
	for ch in Data.all_characters2():
		if ch is CharacterData:
			var cid: StringName = ch.id
			char_row.add_child(_action_button(ch.display_name, func(): restart(cid)))
	root.add_child(char_row)

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	return l

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
	r.custom_minimum_size = Vector2(0, 28)
	return r

func _action_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
