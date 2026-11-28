extends Control
# THE RANK-UP REWARDS, SPUN FOR (the owner, 28 Nov 2026: "something to play when
# the player ranks up. It should look like a roulette and the player can spin it
# and then when it lands on something, that's the thing they unlock").
#
# Opened from the report's summary page (ReportSummary's 🛞 Rank-up rewards
# button) with every reward this game's ranks paid, which were HELD rather than
# toasted while the game was on (RankRewardQueue). One wheel per reward, one after
# another — the game's first, then the character's — each landing on what the
# rank already drew (RewardWheel); a card then shows it, with a button to use it
# at once: play the song, wear the costume or the hat, use the icon. A title
# letter has no button: it is in the title's pool the moment it is earned.
#
# THE WAY OUT IS NEVER LOCKED. ⏭ Skip all turns every wheel left into its card at
# once; with more than one reward, the last wheel ends on the cards of all of them
# (each with its button still), and Continue goes on to the haul. A page torn
# down before the player saw a reward (the summary skipped past by a caller)
# toasts it instead, so nothing is ever silent.
#
# Loaded BY PATH with no class_name, like every screen the run page only opens on
# demand (test_page_load.gd).

signal finished

const WHEEL_MAX := 400.0
const WHEEL_MIN := 240.0
const CARD_W := 820
const ART := 96
const ART_SMALL := 64
const TILE_W := 240

var rewards: Array = []
var index: int = 0
# The rewards already shown (a wheel landed, or Skip all): what was held back with
# each toast has run (RankRewardQueue.revealed).
var _revealed: Dictionary = {}
var _wheel: RewardWheel = null
var _content: VBoxContainer = null
var _counter: Label = null
var _action: Button = null
var _skip_all: Button = null
var _result_slot: VBoxContainer = null
var _hint: Label = null
var _done: bool = false
var _rng := RandomNumberGenerator.new()

func setup(list: Array) -> void:
	rewards = list
	_rng.randomize()
	name = "RankRewardPage"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = UITheme.BG_DEEP
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = ModalScaffold.reserved_top
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 12, 18, 2, UITheme.GOLD))
	center.add_child(card)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	card.add_child(_content)
	if rewards.is_empty():
		_show_all()
	else:
		_show_wheel()

# --- one wheel ----------------------------------------------------------------

func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_wheel = null
	_result_slot = null
	_hint = null

func _head(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	t.add_theme_color_override("font_color", UITheme.GOLD)
	row.add_child(t)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_counter = Label.new()
	_counter.name = "Counter"
	_counter.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	_counter.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_counter)
	return row

func _show_wheel() -> void:
	_clear()
	var e: Dictionary = rewards[index]
	_content.add_child(_head("🛞  Rank-up rewards"))
	_counter.text = "%d of %d" % [index + 1, rewards.size()]
	_content.add_child(_owner_row(String(e.get("owner", ""))))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP_BREAK)
	_content.add_child(body)
	var slices: Array = slices_for(e)
	var prize: int = _rng.randi_range(0, slices.size() - 1)
	slices[prize] = slice_of(e)
	_wheel = RewardWheel.make(slices, prize, wheel_side())
	_wheel.landed.connect(_on_landed)
	_wheel.spun.connect(_on_spun)
	body.add_child(_wheel)
	_result_slot = VBoxContainer.new()
	_result_slot.name = "Result"
	_result_slot.custom_minimum_size = Vector2(TILE_W + 60, 0)
	_result_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_result_slot.add_theme_constant_override("separation", UITheme.GAP)
	body.add_child(_result_slot)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "Click the wheel or press Spin — or grab it and drag it round the way the arrows point, then let go."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(TILE_W + 60, 0)
	_hint.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	_hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_result_slot.add_child(_hint)
	_content.add_child(_footer())
	_action.text = "Spin"
	UITheme.focus_soon(_action)

func _footer() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	_skip_all = UITheme.quiet_button("⏭  Skip all", Vector2(160, 44), UITheme.FONT_LABEL)
	_skip_all.name = "SkipAll"
	_skip_all.tooltip_text = "Show every reward now, without the wheels."
	_skip_all.pressed.connect(skip_all)
	row.add_child(_skip_all)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_action = UITheme.confirm_button("Spin", Vector2(220, 44), UITheme.FONT_LABEL)
	_action.name = "Action"
	_action.pressed.connect(press_action)
	row.add_child(_action)
	return row

# As big as the window lets it be: the header, the owner's row and the buttons
# are taken off what is left under the pinned header bar.
func wheel_side() -> float:
	var room: float = get_viewport_rect().size.y - ModalScaffold.reserved_top - 230.0 \
		if is_inside_tree() else WHEEL_MAX
	return clampf(room, WHEEL_MIN, WHEEL_MAX)

# The one button: Spin, then (while it turns) Skip, then Next or the way out.
func press_action() -> void:
	if _wheel == null:
		finish()
	elif _wheel.has_landed():
		next()
	elif _wheel.is_spinning():
		_wheel.skip()
	else:
		_wheel.spin()

func _on_spun() -> void:
	if _hint != null:
		_hint.text = "Click it again to stop it where it's going."
	_action.text = "Skip  ⏭"

func _on_landed() -> void:
	var e: Dictionary = rewards[index]
	_reveal(index)
	if _hint != null:
		_hint.queue_free()
		_hint = null
	_result_slot.add_child(reward_card(e, ART))
	var last: bool = index >= rewards.size() - 1
	_action.text = ("Next reward  →" if not last else
		("All rewards  →" if rewards.size() > 1 else "Continue  →"))
	_skip_all.visible = not last
	UITheme.focus_soon(_action)

# On to the next wheel, or, after the last, the cards of every reward (with one
# reward its own card was the last thing shown, so straight out).
func next() -> void:
	if index < rewards.size() - 1:
		index += 1
		_show_wheel()
	elif rewards.size() > 1:
		_show_all()
	else:
		finish()

# Every wheel left, turned into its card at once.
func skip_all() -> void:
	for i in range(rewards.size()):
		_reveal(i)
	_show_all()

func _show_all() -> void:
	_clear()
	_content.add_child(_head("🛞  Rank-up rewards"))
	_counter.text = "%d unlocked" % rewards.size()
	var scroll := ScrollContainer.new()
	scroll.name = "All"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var room: float = get_viewport_rect().size.y - ModalScaffold.reserved_top - 200.0
	scroll.custom_minimum_size = Vector2(0, clampf(room, 160.0, 460.0))
	_content.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.name = "Cards"
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", UITheme.GAP_LOOSE)
	flow.add_theme_constant_override("v_separation", UITheme.GAP_LOOSE)
	scroll.add_child(flow)
	for e in rewards:
		flow.add_child(reward_card(e, ART_SMALL))
	var row := HBoxContainer.new()
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_action = UITheme.confirm_button("Continue  →", Vector2(220, 44), UITheme.FONT_LABEL)
	_action.name = "Action"
	_action.pressed.connect(finish)
	row.add_child(_action)
	_content.add_child(row)
	UITheme.focus_soon(_action)

func finish() -> void:
	if _done:
		return
	_done = true
	for i in range(rewards.size()):
		_reveal(i)
	finished.emit()

func _reveal(i: int) -> void:
	if _revealed.has(i) or i >= rewards.size():
		return
	_revealed[i] = true
	RankRewardQueue.revealed(rewards[i])

# Torn down before the player saw it all: the rest are toasted, as they would have
# been without the wheel.
func _exit_tree() -> void:
	for i in range(rewards.size()):
		if not _revealed.has(i):
			_revealed[i] = true
			RankRewardQueue.tell(rewards[i])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		press_action()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _wheel != null:
			skip_all()
		else:
			finish()
		get_viewport().set_input_as_handled()

# --- whose reward -------------------------------------------------------------

func _owner_row(owner: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Owner"
	row.add_theme_constant_override("separation", UITheme.GAP)
	var who: Dictionary = owner_of(owner)
	var tex: Texture2D = who.get("texture")
	if tex != null:
		var pic: TextureRect = UITheme.crisp_tex(tex, 40)
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)
	var name_l := Label.new()
	name_l.text = "%s ranked up" % String(who.get("name", "")) if String(who.get("name", "")) != "" \
		else "Ranked up"
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_l.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	name_l.add_theme_color_override("font_color", UITheme.TEXT)
	row.add_child(name_l)
	return row

# {name, texture} of a RankRewards owner key ("game:hades", "character:zagreus").
static func owner_of(owner: String) -> Dictionary:
	var id := StringName(owner.get_slice(":", 1))
	if owner.begins_with("game:"):
		var g: GameData = Data.get_game(id)
		return {"name": g.display_name if g != null else String(id), "texture": g.cover_image if g != null else null}
	if owner.begins_with("character:"):
		var ch: CharacterData = Data.get_character2(id)
		return {"name": ch.display_name if ch != null else String(id), "texture": ch.shown_icon() if ch != null else null}
	return {}

# --- the slices ---------------------------------------------------------------

# A reward's slice: its picture, a ♪ on a song's cover, sharp pixels for pixel art.
static func slice_of(e: Dictionary) -> Dictionary:
	return slice_for(String(e.get("kind", "")), String(e.get("key", "")))

static func slice_for(kind: String, key: String) -> Dictionary:
	var tex: Texture2D = null
	var glyph: String = ""
	var pixel: bool = false
	match kind:
		"song":
			var song: SongData = Data.get_song(StringName(key))
			var g: GameData = Data.get_game(song.game_id) if song != null else null
			tex = g.cover_image if g != null else null
			glyph = "♪"
		"letter":
			var path: String = TitleLetters.ROOT + key
			if key != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
				tex = TitleLetters.texture(path)
			pixel = tex != null and CosmeticCatalog.is_pixel_art(tex)
		"look":
			var c: Dictionary = CosmeticCatalog.entry(key)
			tex = CosmeticCatalog.texture((CosmeticCatalog.paths(c) + [""])[0])
			pixel = CosmeticCatalog.is_pixel_art(tex)
	if tex == null and glyph == "":
		glyph = "✦"
	return {"texture": tex, "glyph": glyph, "pixel": pixel, "kind": kind, "key": key}

# The wheel's other slices, for show: what the same game or character could give,
# a few of each kind taken in turn, so a wheel reads as songs AND letters AND
# looks. Fewer than a wheel's worth goes round again.
func slices_for(e: Dictionary) -> Array:
	var owner: String = String(e.get("owner", ""))
	var id := StringName(owner.get_slice(":", 1))
	var prize_key: String = String(e.get("key", ""))
	var songs: Array = []
	var letters: Array = []
	var looks: Array = []
	if owner.begins_with("game:"):
		songs = Radio.game_songs(id).map(func(s): return String((s as SongData).id))
		letters = TitleLetters.units_of(id)
		looks = CosmeticCatalog.units_of_game(id)
	elif owner.begins_with("character:"):
		var ch: CharacterData = Data.get_character2(id)
		if ch != null:
			for g in ch.music_games:
				songs.append_array(Radio.game_songs(g).map(func(s): return String((s as SongData).id)))
		letters = TitleLetters.units()
		looks = CosmeticCatalog.units_of_character(id)
	var lists: Array = []
	for pair in [["song", songs, 2], ["letter", letters, 3], ["look", looks, 4]]:
		var keys: Array = (pair[1] as Array).filter(func(k): return String(k) != prize_key)
		_shuffle(keys)
		lists.append([pair[0], keys.slice(0, int(pair[2]))])
	var picks: Array = []
	var more: bool = true
	while picks.size() < RewardWheel.SLICES - 1 and more:
		more = false
		for l in lists:
			if not (l[1] as Array).is_empty() and picks.size() < RewardWheel.SLICES - 1:
				picks.append([l[0], (l[1] as Array).pop_front()])
				more = true
	_shuffle(picks)
	var out: Array = []
	for p in picks:
		out.append(slice_for(String(p[0]), String(p[1])))
	var filler: Array = out.duplicate()
	if filler.is_empty():
		filler = [slice_of(e)]
	while out.size() < RewardWheel.SLICES:
		out.append(filler[out.size() % filler.size()])
	return out

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

# --- a reward's card, and using it --------------------------------------------

# The picture, what it is, and the button that uses it (none for a letter).
func reward_card(e: Dictionary, art: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "RewardCard"
	card.custom_minimum_size = Vector2(TILE_W, 0)
	card.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.GOLD.lerp(UITheme.BORDER, 0.4), 10, 12, 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	card.add_child(col)
	var s: Dictionary = slice_of(e)
	var tex: Texture2D = s.get("texture")
	if tex != null:
		# A letter in the wheel's glow, as on its slice: a black one reads.
		var pic: Control = RewardWheel.glowing(tex, art) if String(e.get("kind", "")) == "letter" \
			else UITheme.crisp_tex(tex, art)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(pic)
	var text: String = String(e.get("text", ""))
	var cut: int = text.find(": ")
	var what := Label.new()
	what.text = text.substr(0, cut) if cut >= 0 else ""
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	what.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(what)
	var title := Label.new()
	title.name = "Title"
	title.text = text.substr(cut + 2) if cut >= 0 else text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	title.add_theme_color_override("font_color", UITheme.TEXT)
	col.add_child(title)
	Cosmetics.apply_glyph(what)
	var use: Button = use_button(e)
	if use != null:
		col.add_child(use)
	return card

# The button that uses a reward at once, or null: ▶ Play now for a song, Wear on
# <character / player> for a costume or a hat, Use this icon for an icon set. A
# second press puts back what was there before.
func use_button(e: Dictionary) -> Button:
	var key: String = String(e.get("key", ""))
	match String(e.get("kind", "")):
		"song":
			return _song_button(Data.get_song(StringName(key)))
		"look":
			return _look_button(key)
	return null

func _song_button(song: SongData) -> Button:
	if song == null:
		return null
	var b := UITheme.action_button("", UITheme.GOLD, Vector2(0, 36), UITheme.FONT_BODY)
	b.name = "Use"
	var paint := func() -> void:
		if not Radio.is_playable(song):
			b.text = "No recording yet"
			b.disabled = true
			b.tooltip_text = "It's on Roguelike Radio's list, and plays once its file is added."
		else:
			b.text = "⏸  Pause" if Radio.current == song.id and Radio.is_playing() else "▶  Play now"
	b.pressed.connect(func() -> void:
		if Radio.current == song.id:
			Radio.toggle_pause()
		else:
			Radio.play_song(song.id)
		paint.call())
	paint.call()
	return b

# The slots a look goes in, and what its button says: [slots, label].
static func look_slots(key: String) -> Array:
	var c: Dictionary = CosmeticCatalog.entry(key)
	match String(c.get("unit", "")):
		"costume":
			var ch := StringName(String(c.get("character", "")))
			var cd: CharacterData = Data.get_character2(ch)
			var slot: String = String(c.get("slot", "icon"))
			var slots: Array = [Cosmetics.costume_slot(ch, "icon"), Cosmetics.costume_slot(ch, "full")] \
				if slot == "both" else [Cosmetics.costume_slot(ch, slot)]
			return [slots, "Wear on %s" % (cd.display_name if cd != null else String(ch))]
		"hat":
			var pl: PlayerData = hat_wearer()
			if pl == null:
				return [[], ""]
			return [[Cosmetics.hat_slot(pl.id)], "Wear on %s" % pl.display_name]
		"icon":
			return [[Cosmetics.icon_slot(String(c.get("kind", "")))], "Use this icon"]
	return [[], ""]

# Who a hat goes on: the run's player, or the first player with a spot for one
# when the run's has none.
static func hat_wearer() -> PlayerData:
	var pl: PlayerData = Data.get_player(GameState.player_id)
	if pl != null and pl.hat_spot.z > 0.0:
		return pl
	for p in Data.all_players():
		if (p as PlayerData).hat_spot.z > 0.0:
			return p
	return null

func _look_button(key: String) -> Button:
	var got: Array = look_slots(key)
	var slots: Array = got[0]
	if slots.is_empty():
		return null
	var before: Array = slots.map(func(s): return Cosmetics.choice(String(s)))
	var b := UITheme.action_button("", UITheme.GOLD, Vector2(0, 36), UITheme.FONT_BODY)
	b.name = "Use"
	var worn := func() -> bool:
		for s in slots:
			if Cosmetics.choice(String(s)) != key:
				return false
		return true
	var paint := func() -> void:
		b.text = ("✓  %s  ·  undo" % ("In use" if String(got[1]) == "Use this icon" else "Wearing")) \
			if worn.call() else String(got[1])
	b.pressed.connect(func() -> void:
		var on: bool = worn.call()
		for i in range(slots.size()):
			var back: String = String(before[i])
			Cosmetics.choose(String(slots[i]), ("" if back == key else back) if on else key)
		paint.call())
	paint.call()
	return b
