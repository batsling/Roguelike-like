extends Control
# THE GAME JUST PLAYED, BEFORE THE HAUL (the owner, 18 Nov 2026: "before going to
# that section of the reward screen, there will be a screen that has the game you
# just beat/escaped and the experience points u got and what you got them from,
# with the bar going up as much as it did").
#
# Laid over the reward screen (PostCombatScreen) as its first page, so the haul is
# already built underneath and nothing about how a report resolves changes:
# Continue takes this page away and the inventory with the table is what is left.
# Everything on it is drawn by the reward screen's own builders — the header with
# the game's and the character's rank bars, the tally, a level-up, the chest's sum
# and who is still following — so the two pages cannot disagree.
#
# Loaded BY PATH with no class_name, like every screen the run page only opens on
# demand (test_page_load.gd).

signal continued

var _screen: Node = null
var _card: PanelContainer = null
var _scroll: ScrollContainer = null
var _body: VBoxContainer = null

func setup(screen: Node) -> void:
	_screen = screen
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
	card.custom_minimum_size = Vector2(760, 0)
	card.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 12, 18, 2, screen._accent()))
	center.add_child(card)
	_card = card
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP)
	card.add_child(col)

	# HOW IT WENT, on one line: the cover, the verdict and the game.
	col.add_child(screen._compact_header())
	# THE MIDDLE SCROLLS, THE WAY OUT DOESN'T (the owner, 20 Nov 2026: "it didn't
	# fit on my screen and i couldn't see the continue"). Two full bars, a level-up
	# and a mask's level-up are taller than a laptop screen, so everything between
	# the header and Continue sits in a scroll box that is exactly as tall as it
	# needs to be when there is room, and as tall as the window allows when there
	# isn't (`_fit`). Continue is never in it.
	_scroll = ScrollContainer.new()
	_scroll.name = "Body"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", UITheme.GAP)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	var body: VBoxContainer = _body
	# THE TWO BARS ARE THE PAGE (the owner, 18 Nov 2026: "make the two experience
	# bars the focus"): the game's and the character's, at full size, each filling
	# from where it stood when the game was picked, and under each the list of
	# what it was for and how much each thing gave. No tally of stats here.
	var g: GameData = screen.game()
	if g != null and screen._snap.has("rank_to"):
		body.add_child(_bar_block(g.cover_image, false,
			int(screen._snap.get("rank_from", 0)), int(screen._snap["rank_to"]),
			g.display_name, _with_perfect(screen._snap.get("xp_sources", []))))
	var ch: CharacterData = Data.get_character2(StringName(screen._snap.get("character_id", "")))
	if screen._snap.has("character_rank_to"):
		body.add_child(_bar_block(ch.shown_icon() if ch != null else null, true,
			int(screen._snap.get("character_rank_from", 0)),
			int(screen._snap["character_rank_to"]),
			String(screen._snap.get("character_name", "")),
			_with_perfect(screen._snap.get("character_xp_sources", []))))
	# The rest of the report, smaller, under the bars.
	var lvl: Control = screen._level_up_panel()
	if lvl != null:
		body.add_child(lvl)
	for masked in screen._snap.get("mask_level_ups", []):
		var m: Control = screen._level_up_block(masked)
		if m != null:
			body.add_child(m)
	# …and how the chest size was worked out. Who is still following is not said
	# here any more (the owner, 20 Nov 2026: "no need to show still following").
	var sum: Control = screen._chest_sum_row()
	if sum != null:
		body.add_child(sum)

	# THE RANK-UPS' REWARDS, HELD FOR THE WHEEL while the game was on
	# (RankRewardQueue): taken here, the game's first and then the character's.
	var owners: Array = []
	if g != null:
		owners.append(RankRewards.game_key(g.id))
	owners.append(RankRewards.character_key(StringName(screen._snap.get("character_id", ""))))
	rewards = RankRewardQueue.take(owners)
	var go := UITheme.confirm_button("Continue  →", Vector2(220, 44), UITheme.FONT_LABEL)
	go.name = "Continue"
	go.pressed.connect(proceed)
	if rewards.is_empty():
		go.size_flags_horizontal = Control.SIZE_SHRINK_END
		col.add_child(go)
		UITheme.focus_soon(go)
	else:
		# TWO WAYS ON (the owner, 28 Nov 2026: "make the rank up rewards its own
		# button or the player can click a skip and proceed"): the wheel page, or
		# straight to the haul with the rewards toasted the way they always were.
		# The skip keeps the name Continue: it is the same way on it always was.
		var row := HBoxContainer.new()
		row.name = "Exits"
		row.add_theme_constant_override("separation", UITheme.GAP)
		row.size_flags_horizontal = Control.SIZE_SHRINK_END
		go.text = "Skip  →"
		go.tooltip_text = "On to the haul. The rewards are yours either way; they are announced as you go."
		UITheme.tint_action_button(go, UITheme.TEXT_DIM)
		row.add_child(go)
		var spin := UITheme.action_button("🎡  Rank-up rewards (%d)" % rewards.size(),
			UITheme.GOLD, Vector2(260, 44), UITheme.FONT_LABEL)
		spin.name = "Rewards"
		spin.tooltip_text = "Spin the wheel for what each rank-up unlocked."
		spin.pressed.connect(open_rewards)
		row.add_child(spin)
		col.add_child(row)
		UITheme.focus_soon(spin)
	_fit.call_deferred()

# The rank-up rewards this page holds, and the wheel page while it is up.
var rewards: Array = []
var _rewards_told: bool = false
const REWARD_PAGE_SCRIPT := "res://scripts/redesign2/RankRewardPage.gd"
var _reward_page: Control = null

# The wheel page, over this one; its Continue goes on to the haul.
func open_rewards() -> Control:
	if rewards_page() != null:
		return _reward_page
	_rewards_told = true
	_reward_page = load(REWARD_PAGE_SCRIPT).new()
	add_child(_reward_page)
	_reward_page.setup(rewards)
	_reward_page.finished.connect(proceed)
	return _reward_page

func rewards_page() -> Control:
	return _reward_page if _reward_page != null and is_instance_valid(_reward_page) \
		and not _reward_page.is_queued_for_deletion() else null

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)

# Taken down without Continue or the wheel (the haul abandoned under it): the
# rewards it held are toasted rather than lost to silence.
func _exit_tree() -> void:
	if not _rewards_told:
		_rewards_told = true
		for e in rewards:
			RankRewardQueue.tell(e)

# The scroll box's height: the body's own, capped at what the window has left
# once the pinned header bar, the card's chrome, the header line and Continue are
# taken off. Public so a test can ask for it after changing the window.
const MARGIN := 16.0

func _fit() -> void:
	if _scroll == null or not is_instance_valid(_scroll) or not is_inside_tree():
		return
	var want: float = _body.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = 0.0
	var chrome: float = _card.get_combined_minimum_size().y
	var room: float = get_viewport_rect().size.y - ModalScaffold.reserved_top \
		- MARGIN * 2.0 - chrome
	_scroll.custom_minimum_size.y = maxf(80.0, minf(want, room))

func _unhandled_input(event: InputEvent) -> void:
	if rewards_page() != null:
		return
	if event.is_action_pressed("ui_accept") and not rewards.is_empty():
		open_rewards()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		proceed()
		get_viewport().set_input_as_handled()

# On to the haul. Public so a test, or the page, can move past it. Rewards the
# wheel never showed are toasted now (the wheel page toasts any it did not reach).
func proceed() -> void:
	if is_queued_for_deletion():
		return
	if not _rewards_told:
		_rewards_told = true
		for e in rewards:
			RankRewardQueue.tell(e)
	continued.emit()
	queue_free()

# ONE BAR: the picture, the big rank bar, and a row per source of its XP —
# "+100  Beat the game" — so the number on each thing is readable at a glance.
const BAR_ART := 64

func _bar_block(art: Texture2D, character: bool, from: int, to: int, who: String,
		rows: Array) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 14, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	wrap.add_child(row)
	if art != null:
		var pic: TextureRect = UITheme.crisp_tex(art, BAR_ART) if character else TextureRect.new()
		if not character:
			pic.texture = art
			pic.custom_minimum_size = Vector2(BAR_ART * 0.75, BAR_ART)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var bar: RankFill = RankFill.make(from, to, who, character, false)
	bar.large = true
	bar.name = "CharacterBar" if character else "GameBar"
	col.add_child(bar)
	if rows.is_empty():
		var none := Label.new()
		none.text = "No XP this game." if to <= from else ""
		none.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
		none.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		col.add_child(none)
	# A TILE PER SOURCE, the Collection's way (GoalsBeatenView): its picture, its
	# name, and the XP it gave under both (the owner, 18 Nov 2026).
	var flow := HFlowContainer.new()
	flow.name = "Sources"
	flow.add_theme_constant_override("h_separation", UITheme.GAP_LOOSE)
	flow.add_theme_constant_override("v_separation", UITheme.GAP)
	col.add_child(flow)
	for r in rows:
		flow.add_child(_source_tile(r))
	return wrap

# PERFECT IS ALWAYS SAID when the game was beaten with no lost run, even where it
# paid nothing: its XP is paid once per game (and once per character), so a second
# perfect is "+0", and the page still says it was one.
func _with_perfect(rows: Array) -> Array:
	if not bool(_screen._snap.get("perfect", false)):
		return rows
	for r in rows:
		if String(r.get("kind", "")) == "perfect":
			return rows
	var out: Array = rows.duplicate()
	out.append({"kind": "perfect", "label": "Perfect", "xp": 0})
	return out

const TILE_W := 84
const TILE_ART := 44
const KIND_GLYPHS := {"wins": "🏆", "perfect": "★", "amulet": "✦", "fracture": Fracture.GLYPH}

func _source_tile(r: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.name = "Source"
	col.custom_minimum_size = Vector2(TILE_W, 0)
	col.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	var kind: String = String(r.get("kind", ""))
	var key := StringName(String(r.get("key", "")))
	var tex: Texture2D = null
	match kind:
		"enemy", "boss":
			var e: GoalEnemyData = Data.get_goal_enemy_any(key)
			tex = e.image if e != null else null
		"character":
			var c: CharacterData = Data.get_character2(key)
			tex = c.shown_icon() if c != null else null
		"weapon":
			var w: WeaponData = Data.get_weapon(key)
			tex = LootPassives.load_weapon_art(w) if w != null else null
		"status":
			var st: StatusData = Data.get_status(key)
			tex = st.image if st != null else null
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(TILE_ART + 8, TILE_ART + 8)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var gold: bool = kind == "perfect"
	frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG_DEEP, 6, 4, 1,
		UITheme.GOLD if gold else UITheme.BORDER))
	if tex != null:
		var art := UITheme.crisp_tex(tex, TILE_ART)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.add_child(art)
	else:
		var g := Label.new()
		g.text = String(KIND_GLYPHS.get(kind, "✦"))
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
		g.add_theme_color_override("font_color", UITheme.GOLD)
		frame.add_child(g)
	col.add_child(frame)
	var name := Label.new()
	name.text = String(r.get("label", ""))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.max_lines_visible = 2
	name.custom_minimum_size = Vector2(TILE_W, 0)
	name.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	name.add_theme_color_override("font_color", UITheme.GOLD if gold else UITheme.TEXT)
	col.add_child(name)
	var xp := Label.new()
	xp.name = "SourceXp"
	xp.text = "+%d xp" % int(r.get("xp", 0))
	xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	xp.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(xp)
	if kind == "perfect" and int(r.get("xp", 0)) == 0:
		col.tooltip_text = "Beaten with no lost run. Its XP is paid once, the first time."
	return col

static func source_text(rows: Array) -> String:
	var parts: PackedStringArray = []
	for r in rows:
		parts.append("+%d %s" % [int(r.get("xp", 0)), String(r.get("label", ""))])
	return "  ·  ".join(parts)
