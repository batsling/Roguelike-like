extends Control

# The games-first (2.0) "spend a piece of loot" flow, as a self-contained
# full-screen modal (§4.1 scrolls, §4.3 pills). The loot window opens one with
# start(host, loot_index, overworld); the modal owns the rest:
#   1. show the piece — its art and, when the type is UNIDENTIFIED, a masked name
#      and no Preference, because that mask is the gamble the player is taking.
#   2. on Use: LootSystem.use_loot, which consumes the entry, resolves it through
#      whichever system owns it, and fires Echo Chamber's copies of the last three
#      used. Then walk the returned `requests` (identify-which / stun-which /
#      teleport) through small pickers.
#   3. SAY WHAT IT DID, on the screen you did it on — see `_show_outcome`.
#   4. emit `finished` and free itself so the page refreshes.
#
# IT IS ONE MODAL FOR BOTH KINDS deliberately. A pill needs fewer words than a
# scroll, but the two need the same THREE things — a look at what you are about
# to spend, a confirm, and somewhere for a follow-up choice to be made — and the
# echo means either kind can hand back a request that belongs to the other.
#
# Built entirely in code (no scene file), on its own CanvasLayer so it always
# centers over the overworld regardless of what opened it.

signal finished
# The piece was actually SPENT, as against the player backing out — `finished`
# fires either way, and a caller that has to know the difference (the drop modal,
# for which "used the offer" ends the drop and "cancelled" leaves it on the table)
# cannot tell from `finished` alone.
signal used

# The entry being spent: {"type": "scroll"|"pill", "id": …, "horse": …}.
var _entry: Dictionary = {}
# Which slot it is being spent OUT OF, or -1 for a LOOSE piece — the one a game has
# just paid out, taken on the spot instead of carried (§4.3). The difference is
# only whether a slot is emptied first; see LootSystem.use_entry.
var _loot_index: int = -1
# The CanvasLayer this modal sits on. 120 clears the page; a use opened from ON TOP
# of another modal has to clear that one too, and the drop modal is 122 — so the
# caller that opened it says how high to go rather than this screen guessing.
var layer_index: int = 120
var _requests: Array = []
# What the use turned out to have done — filled in by `_on_read` and read by
# `_show_outcome`, which is the last screen before this modal takes itself away.
var _outcome_logs: Array = []
# The piece was a gamble and is not one any more: this use is what identified it.
var _newly_learned: bool = false
# Health as it stood the instant before the piece resolved, so the outcome can show
# where it landed rather than only what was subtracted.
var _hp_before: int = 0
var _max_hp_before: int = 0
# What Echo Chamber replayed on top of this use, by name. The relic's copies land
# in the same merged `logs` as the piece's own, so without this the outcome screen
# is four pieces' worth of effects and no account of where three of them came from.
var _echoed: Array = []
var _panel: PanelContainer = null
var _body: VBoxContainer = null
var _layer: CanvasLayer = null
var _overworld: Node = null
var _rng := RandomNumberGenerator.new()

const ACCENT := Color(0.61, 0.35, 0.71)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()

# Entry point for a CARRIED piece. `overworld` is the Overworld2 scene (for
# teleport fulfilment).
func start(host: Node, loot_index: int, overworld: Node) -> void:
	_mount(host)
	if loot_index < 0 or loot_index >= GameState.loot_items.size():
		_finish()
		return
	var entry = GameState.loot_items[loot_index]
	if not (entry is Dictionary) or not entry.has("id"):
		_finish()
		return
	_overworld = overworld
	_entry = (entry as Dictionary).duplicate(true)
	_loot_index = loot_index
	_show_intro()

# Entry point for a LOOSE piece — one that is not in the pack, which is the drop
# modal's offer taken on the spot rather than carried. Nothing is removed from the
# pack when it fires; everything else about spending it is identical, which is why
# both paths land in the same screen.
func start_entry(host: Node, entry: Dictionary, overworld: Node) -> void:
	_mount(host)
	if entry.is_empty() or not entry.has("id"):
		_finish()
		return
	_overworld = overworld
	_entry = entry.duplicate(true)
	_loot_index = -1
	_show_intro()

func _mount(host: Node) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = layer_index
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)

func _is_pill() -> bool:
	return String(_entry.get("type", "")) == "pill"

# ---------------------------------------------------------------------------
# Intro screen — show the scroll and offer Read.
# ---------------------------------------------------------------------------

func _show_intro() -> void:
	_rebuild_panel()
	var identified: bool = LootSystem.is_identified(_entry)
	# At the dose's OWN size (§4.3): a horse capsule is drawn oversized here as it is
	# everywhere else, because it is the one fact about a dose the player can always
	# read off the picture. This used to be a fixed 96px box, which normalised the
	# two doses to the same size on the very screen that asks you to commit to one.
	var art: TextureRect = LootSystem.art_tex(_entry, 96)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(art)
	_body.add_child(_heading("%s %s" % [LootSystem.glyph(_entry), LootSystem.display_name(_entry)],
		ACCENT, 22))
	var summary: String = LootSystem.description(_entry)
	if identified:
		# THE PREFERENCE AS A CHIP, in its own colour. This is the fact the whole
		# decision turns on and it was a line of grey body text — the same weight as
		# the sentence under it, on a screen whose only question is "do you want this
		# to happen to you".
		_body.add_child(_chip_row([
			UITheme.chip(LootSystem.kind_name(_entry), LootSystem.LOOT_COLOR),
			UITheme.chip(LootSystem.preference(_entry),
				UITheme.preference_color(LootSystem.preference(_entry))),
		]))
		_body.add_child(_muted(summary))
		# The KEYWORD STRIP (§17), on the same terms an item card carries one: what
		# a Scroll of Fire does is written in the names of three mechanics, and the
		# reader is about to spend it on the strength of that sentence. Only on an
		# IDENTIFIED piece — an unidentified one deliberately says nothing about what
		# it does, and a strip naming Burn and Fire under "this is a gamble" would
		# give the whole thing away.
		Keywords.attach(_body, summary)
	else:
		_body.add_child(_chip_row([
			UITheme.chip(LootSystem.kind_name(_entry), LootSystem.LOOT_COLOR),
			UITheme.chip("Unidentified", UITheme.TEXT_DIM),
		]))
		if _is_pill():
			# A pill hides its NAME, never its capsule (§4.3) — the art above is the
			# thing being learned, so the gamble line says what is unknown rather than
			# pretending the tile is a mystery.
			_body.add_child(_muted("You have never taken this one. Its Preference could be Positive, Negative, or Neutral — taking it is how you find out what the colour means."))
		else:
			_body.add_child(_muted("Unidentified — reading it is a gamble. Its Preference could be Positive, Negative, or Neutral."))
	if _echo_note() != "":
		_body.add_child(_muted(_echo_note()))
	# ONE ROW, TWO WEIGHTS. The confirm and the way out used to be two stacked
	# default-grey buttons, which is the same screen furniture saying the two answers
	# are equally likely — on the relic drop sitting right behind this one in the
	# queue, the take is green and 190px wide. Same question, same shape now.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var cancel := UITheme.quiet_button("Cancel", Vector2(120, 38))
	cancel.pressed.connect(_finish)
	actions.add_child(cancel)
	var read_btn := UITheme.confirm_button(
		"Take Pill →" if _is_pill() else "Read Scroll →", Vector2(170, 38), 15)
	read_btn.pressed.connect(_on_read)
	actions.add_child(read_btn)
	_body.add_child(actions)
	read_btn.grab_focus()

# What Echo Chamber is about to add, named rather than left as a surprise: the
# relic changes what SPENDING one piece of loot means, and a player who cannot see
# the three copies coming cannot plan around them (§4.3).
func _echo_note() -> String:
	if GameState.loot_echo_depth() <= 0:
		return ""
	var names: Array = _echo_names()
	if names.is_empty():
		return "Echo Chamber: nothing used yet for it to copy."
	return "Echo Chamber will also use: %s." % ", ".join(PackedStringArray(names))

# The pieces Echo Chamber is about to replay, newest first. Read BEFORE the use —
# `LootSystem` pushes this use onto the same memory as it resolves, so asking
# afterwards gets an answer that includes the piece you just spent.
func _echo_names() -> Array:
	var depth: int = GameState.loot_echo_depth()
	var memory: Array = LootSystem.used_memory()
	if depth <= 0 or memory.is_empty():
		return []
	var names: Array = []
	for i in range(memory.size() - 1, maxi(0, memory.size() - depth) - 1, -1):
		names.append(LootSystem.display_name(memory[i]))
	return names

func _on_read() -> void:
	# Through LootSystem rather than straight into ScrollSystem: consuming the
	# entry, Echo Chamber's replay of the last three pieces used, and the memory
	# this use joins are all things that happen AROUND a use and belong to neither
	# consumable system (§4.3). What comes back is the merged result — this scroll's
	# logs and requests plus every echo's — so a teleport fired twice is fulfilled
	# twice rather than silently once.
	#
	# A LOOSE piece (`_loot_index < 0`) goes through `use_entry` instead, which is
	# the same thing minus the slot there was never anything in.
	#
	# READ BEFORE, NOT AFTER. Whether this use is what taught the player the piece,
	# and what their Health was when they took it, are both facts about the moment
	# before it resolved — and taking a pill is precisely the thing that changes them.
	var known_before: bool = LootSystem.is_identified(_entry)
	_hp_before = GameState.hp
	_max_hp_before = GameState.max_hp
	# Same reason: the use joins the echo memory as it resolves, so what the echoes
	# WERE can only be read from in front of it.
	_echoed = _echo_names()
	var result: Dictionary = LootSystem.use_entry(_entry, {"rng": _rng}) if _loot_index < 0 \
		else LootSystem.use_loot(_loot_index, {"rng": _rng})
	used.emit()
	if _loot_index < 0:
		GameLog.add("Used %s where you stood, without carrying it."
			% LootSystem.display_name(_entry), ACCENT)
	for line in result.get("logs", []):
		GameLog.add(String(line), ACCENT)
	_outcome_logs = result.get("logs", [])
	_newly_learned = not known_before and LootSystem.is_identified(_entry)
	_requests = result.get("requests", [])
	_process_next_request()

# ---------------------------------------------------------------------------
# Requests — interactive follow-ups returned by the use (and by its echoes)
# ---------------------------------------------------------------------------

func _process_next_request() -> void:
	if _requests.is_empty():
		# The pickers come FIRST and the summary last, because a request is part of
		# what the piece did: a Scroll of Identify has nothing to report until you have
		# chosen, and a Telepill has moved you by the time it does.
		_show_outcome()
		return
	var req: Dictionary = _requests.pop_front()
	match String(req.get("kind", "")):
		"identify_scrolls":
			_pick_identify(req)
		"stun_enemies":
			_pick_stun(req)
		"teleport":
			_do_teleport(req)
		_:
			_process_next_request()

# --- Identify which scrolls (choose up to N) -------------------------------
func _pick_identify(req: Dictionary) -> void:
	var candidates: Array = req.get("candidates", [])
	var max_pick: int = int(req.get("count", 1))
	var selected: Dictionary = {}
	_rebuild_panel()
	_body.add_child(_heading("Identify Scrolls", ACCENT, 20))
	_body.add_child(_muted("Choose up to %d to identify." % max_pick))
	for id in candidates:
		var s: ScrollData = Data.get_scroll(id)
		var nm: String = s.display_name if s != null else String(id)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "📜 " + nm
		btn.toggled.connect(func(on): _toggle_select(selected, id, on, max_pick, btn))
		_body.add_child(btn)
	var confirm := UITheme.confirm_button("Identify Selected", Vector2(180, 34))
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm.pressed.connect(func():
		_report(ScrollSystem.identify_scrolls_chosen(selected.keys()))
		_process_next_request())
	_body.add_child(confirm)

# --- Stun which following enemy (choose up to N) ---------------------------
func _pick_stun(req: Dictionary) -> void:
	var max_pick: int = int(req.get("count", 1))
	var selected: Dictionary = {}   # instance -> true
	_rebuild_panel()
	_body.add_child(_heading("Scare a Monster", ACCENT, 20))
	if GameLoop2.stack.is_empty():
		_body.add_child(_muted("No following enemies to Stun."))
		_report("There was nothing following you to Stun.")
		_body.add_child(_continue_button())
		return
	_body.add_child(_muted("Choose up to %d following enemy to Stun (it loses its next turn — %s)."
		% [max_pick, ScrollSystem.stun_worth()]))
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var inst: int = int(entry["instance"])
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s — %s" % [e.display_name, GameLoop2.goal_text_for(entry)]
		btn.toggled.connect(func(on): _toggle_select(selected, inst, on, max_pick, btn))
		_body.add_child(btn)
	var confirm := UITheme.confirm_button("Stun Selected", Vector2(180, 34))
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm.pressed.connect(func():
		_report(ScrollSystem.stun_enemies_chosen(selected.keys()))
		_process_next_request())
	_body.add_child(confirm)

func _toggle_select(selected: Dictionary, key, on: bool, max_pick: int, btn: Button) -> void:
	if on:
		if selected.size() >= max_pick:
			btn.set_pressed_no_signal(false)
			return
		selected[key] = true
	else:
		selected.erase(key)

# --- Teleport — fulfilled by the overworld --------------------------------
#
# The one op on either consumable that resolves nowhere near the system that owns
# it: `read_scroll` and `take_pill` hand back a request and are finished, so the
# line saying where you ended up can only come from whoever moved you.
func _do_teleport(req: Dictionary) -> void:
	var landed: String = ""
	if _overworld != null and _overworld.has_method("loot_teleport"):
		# It writes its own log line — it is the overworld's move, and it happens
		# whether a modal asked for it or not — so this only picks the sentence up.
		landed = String(_overworld.loot_teleport(req))
	if landed != "":
		_report(landed, false)
	else:
		# No overworld to move you, or nowhere on it to go. Either way the piece was
		# spent, so the outcome says the nothing that happened rather than reporting
		# an empty screen.
		_report("It fizzles — you do not move.")
	_process_next_request()

# Add a line to what the outcome screen will say. `log_it` because every other line
# on that screen came back through `use_loot` and was written to the run log in
# `_on_read`, and a fulfilment's line has to reach both — except where whoever
# fulfilled it has already logged its own. The log and the screen must never be
# able to say different things, or say the same thing twice.
# Silently ignores "" so a caller can hand over whatever it has.
func _report(line: String, log_it: bool = true) -> void:
	if line == "":
		return
	_outcome_logs.append(line)
	if log_it:
		GameLog.add(line, ACCENT)

# ---------------------------------------------------------------------------
# What it did
# ---------------------------------------------------------------------------

# THE SCREEN THAT SAYS WHAT HAPPENED. Taking a pill used to close this modal the
# instant it resolved, which meant the answer to "what did that do to me" was a
# couple of lines in the run log on the far side of the page — the one place the
# player was not looking, having just been looking here. On an UNIDENTIFIED capsule
# that is the entire minigame: the whole reason to swallow an unknown pill is to
# find out what it was, and finding out was happening off-screen.
#
# So the piece gets one more screen. It is the same furniture as the intro — the
# art, the name, the chips — said in the past tense, with the effect underneath it:
#
#   * WHAT IT TURNED OUT TO BE, when this use is what identified it. The capsule is
#     right there above the line, so "this one is Bad Trip" is the colour being
#     named without the colour ever having to be written down (see LootDiscoveries
#     for why the run never spells a colour out).
#   * WHAT IT DID, as the lines the effect itself reported — the same ones the log
#     gets, so the two can never say different things.
#   * WHERE YOUR HEALTH LANDED, when it moved. "You lose 4 Health" is the size of
#     the hit; the number that decides what to do next is the one left afterwards.
func _show_outcome() -> void:
	_rebuild_panel()
	var art: TextureRect = LootSystem.art_tex(_entry, 96)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(art)
	_body.add_child(_heading("%s %s" % [LootSystem.glyph(_entry),
		LootSystem.display_name(_entry)], ACCENT, 22))

	var chips: Array = [UITheme.chip(LootSystem.kind_name(_entry), LootSystem.LOOT_COLOR)]
	var pref: String = LootSystem.preference(_entry)
	if pref != "":
		chips.append(UITheme.chip(pref, UITheme.preference_color(pref)))
	_body.add_child(_chip_row(chips))

	if _newly_learned:
		_body.add_child(_heading("You know what this one is now." if not _is_pill()
			else "Now you know what this capsule is.", PillSystem.PILL_COLOR, 14))

	# WHOSE LINES THESE ARE. Echo Chamber's copies resolve into the same merged
	# `logs` as the piece's own, so a run holding the relic reads four pieces' worth
	# of effects here — and without this, no account of where three of them came
	# from. Named before the lines, since it is the frame they are read in.
	if not _echoed.is_empty():
		_body.add_child(_muted("Echo Chamber also used: %s."
			% ", ".join(PackedStringArray(_echoed))))

	# The effect, line by line. A piece whose ops all no-opped (a charge into a pack
	# with nothing chargeable, an Amnesia with nothing to forget) reports that
	# itself, so the empty case here is only the piece that had nothing to say.
	if _outcome_logs.is_empty():
		_body.add_child(_muted("Nothing happens."))
	else:
		for line in _outcome_logs:
			_body.add_child(_muted(String(line)))

	if GameState.hp != _hp_before or GameState.max_hp != _max_hp_before:
		var health := _heading("Health %d / %d" % [GameState.hp, GameState.max_hp],
			UITheme.DANGER if GameState.hp < _hp_before else UITheme.SUCCESS, 16)
		_body.add_child(health)

	var done := UITheme.confirm_button("Done", Vector2(150, 36), 15)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(_finish)
	_body.add_child(done)
	done.grab_focus()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _continue_button() -> Button:
	var b := UITheme.confirm_button("Continue", Vector2(150, 34))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_process_next_request)
	return b

func _finish() -> void:
	finished.emit()
	if _layer != null:
		_layer.queue_free()
	else:
		queue_free()

func _rebuild_panel() -> void:
	for c in get_children():
		c.queue_free()
	_panel = ModalScaffold.build_panel(self, ACCENT, Callable(), Vector2(440, 460))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(404, 420)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(scroll)
	_panel.add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

func _heading(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# A centred row of chips — what this is, and what it would do to you.
func _chip_row(chips: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for c in chips:
		row.add_child(c)
	return row

func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
