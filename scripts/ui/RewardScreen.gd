class_name RewardScreen
extends Control

# Section-completion reward, shown by Main after the player beats an
# action / strategy / deckbuilder game. Mirrors the HTML prototype's
# post-victory rewards (the gold + item-choice portions):
#   * Gold: a flat amount keyed on the run difficulty tier
#     (Low 10 / Medium 15 / High 25 / Insane 35), granted immediately.
#   * Item choice: pick 1 of (2 + Discovery) items rolled at 75/20/5
#     common/uncommon/rare with luck advantage (rare has a 10% bump to
#     legendary), boons excluded, no dupes within a batch. Reroll if the
#     player has reroll charges; Skip to take nothing.

signal closed

const BASE_ITEM_CHOICES := 2

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Legendary"]
const RARITY_COLORS := [
	Color(0.78, 0.78, 0.78), Color(0.45, 0.85, 0.5),
	Color(0.4, 0.6, 1.0), Color(1.0, 0.8, 0.3),
]

var _gold: int = 0
var _game: GameData = null               # the real game this section represented
var _choices: Array = []                 # Array[ItemData] templates
var _rng := RandomNumberGenerator.new()
var _resolved: bool = false
var _started: bool = false
var _config_done: bool = false           # a setup* method has run
# Chest tuning (games-first §8.2). When >= 0, the number of items to offer is
# fixed (Small 1 / Regular 2 / Large 3) instead of the BASE + Discovery default.
var _choice_count_override: int = -1
# MULTI-CHEST. Two chests used to mean two screens, one after the other, which
# read as the same screen flickering — you cannot compare what the second one is
# offering against what you took from the first, and the second arrives with no
# signal that it is a different chest at all. One screen now, with a labelled
# group per chest and one pick from each. Empty = the ordinary single-chest path.
#   _chest_sizes    the choice count of each chest, in the order granted
#   _chest_choices  the rolled items for each, parallel to _chest_sizes
#   _chest_taken    which of them have been answered
var _chest_sizes: Array = []
var _chest_choices: Array = []
var _chest_taken: Array = []
# Screen title; "Reward!" for an enemy-drop chest, "Victory!" for the (legacy)
# section-completion reward.
var _title: String = "Victory!"
# When non-empty, the choices are this exact list of ItemData (no rarity roll) —
# Wand of Wishing's "obtain any item" full-catalog pick.
var _explicit_pool: Array = []

var _choices_box: HFlowContainer
var _reroll_btn: Button
var _play_btn: Button
var _title_line: Label
var _gold_line: Label

# gold: the amount to grant (Main computes it from the difficulty tier).
# game: the real game this section represented; when it has a launch target a
#       "Play the real game" button is shown. Optional — level-up item rewards
#       pass no game.
# Safe to call before or after the node enters the tree.
func setup(gold: int, game: GameData = null) -> void:
	_gold = gold
	_game = game
	_config_done = true
	if is_inside_tree() and not _started:
		_started = true
		_begin()

# Enemy-drop chest (games-first §8): a gold-less item-choice screen offering
# `choices` relics rolled by rarity from items2.0 (0 = the BASE + Discovery
# default). Add the node to the tree, then call this.
func setup_chest(choices: int = 0) -> void:
	_gold = 0
	_game = null
	_title = "Choose a Reward"
	_choice_count_override = choices if choices > 0 else -1
	_config_done = true
	if is_inside_tree() and not _started:
		_started = true
		_begin()

# Several banked chests at once (games-first §8.2). `sizes` is one choice-count
# per chest — [1, 1] is two Small chests — and each gets its own group with its
# own roll, so "2 Small Chests" is visibly two chests of one item rather than one
# chest of two.
func setup_chests(sizes: Array) -> void:
	if sizes.size() <= 1:
		setup_chest(int(sizes[0]) if sizes.size() == 1 else 0)
		return
	_gold = 0
	_game = null
	_title = "Choose a Reward"
	_chest_sizes = sizes.duplicate()
	_chest_taken.resize(_chest_sizes.size())
	_chest_taken.fill(false)
	_config_done = true
	if is_inside_tree() and not _started:
		_started = true
		_begin()

# Wand of Wishing "obtain any item": the choices are the given explicit list
# (the full items2.0 catalog), take one, no rarity roll and no reroll.
func setup_obtain(items: Array) -> void:
	_gold = 0
	_game = null
	_title = "Obtain Any Item"
	_explicit_pool = items.duplicate()
	_config_done = true
	if is_inside_tree() and not _started:
		_started = true
		_begin()

func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# If a setup* ran before we entered the tree, kick off now.
	if _config_done and not _started:
		_started = true
		_begin()

func _begin() -> void:
	# The title / gold line may have been configured after _build_ui ran (the
	# overworld adds the node, then calls setup_chest), so sync them here.
	if _title_line != null:
		_title_line.text = _title
	if _gold_line != null:
		_gold_line.visible = _gold > 0
	# Reroll only makes sense for a rarity-rolled chest, not an obtain-any pick.
	if _reroll_btn != null:
		_reroll_btn.visible = _explicit_pool.is_empty()
	# Gold is granted immediately (HTML awards it on victory, not on click).
	if _gold > 0:
		GameState.change_gold(_gold)
		GameLog.add("Reward: +%d gold." % _gold, Color(1.0, 0.9, 0.3))
	if _play_btn != null:
		_play_btn.visible = _game != null and _game.has_launch_target()
		if _play_btn.visible:
			_play_btn.text = "▶ Play %s" % _game.display_name
	if not _chest_sizes.is_empty():
		_roll_every_chest()
	else:
		_roll_choices()
	_refresh()

# ------------------------------------------------------------------
# UI
# ------------------------------------------------------------------

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 460)
	panel.position = (get_viewport_rect().size - Vector2(820, 460)) / 2.0
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	_title_line = Label.new()
	_title_line.text = _title
	_title_line.add_theme_font_size_override("font_size", 26)
	_title_line.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
	_title_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title_line)

	_gold_line = Label.new()
	_gold_line.text = "+%d gold" % _gold
	_gold_line.add_theme_font_size_override("font_size", 18)
	_gold_line.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_gold_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_gold_line)

	# "Play the real game" — only meaningful when this section represented a
	# real game with a launch target. Hidden by default; _begin() reveals it.
	_play_btn = Button.new()
	_play_btn.text = "▶ Play the real game"
	_play_btn.custom_minimum_size = Vector2(260, 44)
	_play_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	_play_btn.visible = false
	_play_btn.pressed.connect(_on_play_real)
	root.add_child(_play_btn)

	var pick_lbl := Label.new()
	pick_lbl.text = "Choose an item:"
	pick_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	pick_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(pick_lbl)

	# A scroll-wrapped flow so a Large chest / the full obtain-any catalog wrap
	# and scroll instead of overflowing the panel.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 270)
	root.add_child(scroll)
	_choices_box = HFlowContainer.new()
	_choices_box.add_theme_constant_override("h_separation", 12)
	_choices_box.add_theme_constant_override("v_separation", 12)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_choices_box)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(btn_row)

	_reroll_btn = Button.new()
	_reroll_btn.pressed.connect(_on_reroll)
	btn_row.add_child(_reroll_btn)

	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.custom_minimum_size = Vector2(140, 40)
	skip_btn.pressed.connect(_on_skip)
	btn_row.add_child(skip_btn)

func _refresh() -> void:
	if _choices_box == null:
		return
	if _gold_line != null:
		_gold_line.text = "+%d gold" % _gold
	for c in _choices_box.get_children():
		c.queue_free()
	# The reroll button is labelled and sized HERE, before the multi-chest path
	# returns — leaving it to the tail meant a multi-chest screen showed it as an
	# unlabelled sliver next to Skip.
	if _reroll_btn != null:
		_reroll_btn.text = "Reroll (%d)" % GameState.reroll_charges
		_reroll_btn.disabled = GameState.reroll_charges <= 0
		_reroll_btn.custom_minimum_size = Vector2(140, 40)
	if not _chest_sizes.is_empty():
		_refresh_multi()
		return
	for item in _choices:
		_choices_box.add_child(_build_choice_tile(item))

# One column per chest, each headed and each answered on its own. A chest that
# has been taken from collapses to its answer, so the screen keeps showing what
# you already chose while you decide the next one.
func _refresh_multi() -> void:
	for i in range(_chest_sizes.size()):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)

		var head := Label.new()
		head.text = "%s Chest" % _size_name(int(_chest_sizes[i]))
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 15)
		head.add_theme_color_override("font_color",
			Color(0.6, 0.7, 0.6) if bool(_chest_taken[i]) else Color(1.0, 0.85, 0.4))
		col.add_child(head)

		if bool(_chest_taken[i]):
			var done := Label.new()
			done.text = "✓  taken"
			done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			done.custom_minimum_size = Vector2(230, 0)
			done.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6))
			col.add_child(done)
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			for item in (_chest_choices[i] as Array):
				row.add_child(_build_choice_tile(item, i))
			col.add_child(row)
		_choices_box.add_child(col)


func _size_name(choices: int) -> String:
	match choices:
		1: return "Small"
		2: return "Medium"
		3: return "Large"
		5: return "Huge"
		_: return "Reward"


func _roll_every_chest() -> void:
	_chest_choices.clear()
	for size in _chest_sizes:
		_choice_count_override = maxi(1, int(size))
		_roll_choices()
		_chest_choices.append(_choices.duplicate())
	_choice_count_override = -1


func _build_choice_tile(item: ItemData, chest: int = -1) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(230, 250)
	tile.add_theme_stylebox_override("panel", RarityStyle.panel(int(item.rarity), 12))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	tile.add_child(vbox)

	if item.image != null:
		var icon := TextureRect.new()
		icon.texture = item.image
		icon.custom_minimum_size = Vector2(96, 96)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)

	var rarity_idx: int = clampi(int(item.rarity), 0, RARITY_NAMES.size() - 1)
	var name_lbl := Label.new()
	name_lbl.text = "%s\n[%s]" % [item.display_name, RARITY_NAMES[rarity_idx]]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", RARITY_COLORS[rarity_idx])
	vbox.add_child(name_lbl)

	var desc := Label.new()
	desc.text = item.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(210, 0)
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc)

	var take := Button.new()
	take.text = "Take"
	take.pressed.connect(func(): _on_take(item, chest))
	vbox.add_child(take)
	return tile

# ------------------------------------------------------------------
# Item rolling — mirrors js/loot.js showItemChoiceModal + selectRandomRarity.
# ------------------------------------------------------------------

func _roll_choices() -> void:
	_choices.clear()
	# Obtain-any (Wand of Wishing): offer the exact catalog list, no rarity roll.
	if not _explicit_pool.is_empty():
		_choices = _explicit_pool.duplicate()
		return
	# Enemy-drop relics come from the games-first items2.0 table (§8).
	var pool: Array = Data.reward_item2_pool()
	if pool.is_empty():
		return
	var discovery: int = Stats.get_value(&"discovery")
	var n: int = _choice_count_override if _choice_count_override >= 0 else BASE_ITEM_CHOICES + maxi(0, discovery)
	n = maxi(1, mini(n, pool.size()))
	var orb: bool = GameState.has_low_rarity_reroll()
	var attempts: int = 0
	while _choices.size() < n and attempts < 100:
		attempts += 1
		var bucket: Array = Data.reward_item2_pool_of(_roll_rarity())
		var pick: ItemData = bucket[_rng.randi_range(0, bucket.size() - 1)]
		# Sacred Orb: reroll low-rarity picks — Commons always, Uncommons 25%.
		# Re-loops (re-rolling rarity) until the pick survives, biasing the
		# offered choices toward higher rarities.
		if orb:
			if int(pick.rarity) == ItemData.Rarity.COMMON:
				continue
			if int(pick.rarity) == ItemData.Rarity.UNCOMMON and _rng.randf() < 0.25:
				continue
		var dup: bool = false
		for c in _choices:
			if c.id == pick.id:
				dup = true
				break
		if not dup:
			_choices.append(pick)

# The shared 75/20/5 ladder (Data.roll_item_rarity), rolled through this screen's
# luck advantage instead of a flat random draw.
func _roll_rarity() -> int:
	return Data.roll_item_rarity(_rng, _roll_with_luck_advantage())

# Port of rollWithLuckAdvantage (js/data.js): roll in [0,1); positive luck has
# a luck*10% chance to take the better of two rolls, negative luck the worse.
func _roll_with_luck_advantage() -> float:
	var lv: int = Stats.get_value(&"luck")
	var r: float = _rng.randf()
	if lv > 0 and _rng.randf() < float(lv) * 0.1:
		return maxf(r, _rng.randf())
	if lv < 0 and _rng.randf() < float(absi(lv)) * 0.1:
		return minf(r, _rng.randf())
	return r

# ------------------------------------------------------------------
# Actions
# ------------------------------------------------------------------

func _on_take(item: ItemData, chest: int = -1) -> void:
	if _resolved:
		return
	# Multi-chest: one pick per chest, and the screen only closes once every chest
	# has been answered. Taking from one must not silently forfeit the others.
	if chest >= 0 and not _chest_sizes.is_empty():
		if bool(_chest_taken[chest]):
			return
		_chest_taken[chest] = true
		GameState.add_item(item)
		GameLog.add("Picked up %s." % item.display_name, Color(0.7, 1.0, 0.7))
		if _chest_taken.has(false):
			_refresh()
			return
		_resolved = true
		_finish()
		return
	_resolved = true
	GameState.add_item(item)
	GameLog.add("Picked up %s." % item.display_name, Color(0.7, 1.0, 0.7))
	_finish()

func _on_skip() -> void:
	if _resolved:
		return
	_resolved = true
	var left: int = 0
	for taken in _chest_taken:
		if not taken:
			left += 1
	if left > 0:
		GameLog.add("Skipped %d chest%s." % [left, "" if left == 1 else "s"],
			Color(0.8, 0.8, 0.8))
	else:
		GameLog.add("Skipped the item reward.", Color(0.8, 0.8, 0.8))
	_finish()

func _on_play_real() -> void:
	if _game == null:
		return
	if _game.launch():
		GameLog.add("Launching %s…" % _game.display_name, Color(0.6, 1.0, 0.8))
	else:
		GameLog.add("Couldn't launch %s." % _game.display_name, Color(1.0, 0.6, 0.6))
		if _play_btn != null:
			_play_btn.text = "Couldn't launch — check the file path"
			_play_btn.disabled = true

func _on_reroll() -> void:
	if _resolved or GameState.reroll_charges <= 0:
		return
	GameState.reroll_charges -= 1
	if _chest_sizes.is_empty():
		_roll_choices()
	else:
		# Rerolls the chests still open; a chest already answered keeps its answer.
		var kept: Array = _chest_choices.duplicate()
		_roll_every_chest()
		for i in range(_chest_choices.size()):
			if bool(_chest_taken[i]):
				_chest_choices[i] = kept[i]
	_refresh()

func _finish() -> void:
	emit_signal("closed")
	queue_free()
