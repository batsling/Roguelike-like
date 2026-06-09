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

# HTML rarity weights (js/data.js calculateRarityWeights): 75/20/5.
const W_COMMON := 75.0
const W_UNCOMMON := 20.0
const W_RARE := 5.0
const BASE_ITEM_CHOICES := 2

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [
	Color(0.78, 0.78, 0.78), Color(0.45, 0.85, 0.5),
	Color(0.4, 0.6, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.8, 0.3),
]

var _gold: int = 0
var _choices: Array = []                 # Array[ItemData] templates
var _rng := RandomNumberGenerator.new()
var _resolved: bool = false
var _started: bool = false

var _choices_box: HBoxContainer
var _reroll_btn: Button

# gold: the amount to grant (Main computes it from the difficulty tier).
# Safe to call before or after the node enters the tree.
func setup(gold: int) -> void:
	_gold = gold
	if is_inside_tree() and not _started:
		_started = true
		_begin()

func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# If setup() ran before we entered the tree, kick off now.
	if _gold > 0 and not _started:
		_started = true
		_begin()

func _begin() -> void:
	# Gold is granted immediately (HTML awards it on victory, not on click).
	if _gold > 0:
		GameState.change_gold(_gold)
		GameLog.add("Reward: +%d gold." % _gold, Color(1.0, 0.9, 0.3))
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

	var title := Label.new()
	title.text = "Victory!"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var gold_line := Label.new()
	gold_line.name = "GoldLine"
	gold_line.text = "+%d gold" % _gold
	gold_line.add_theme_font_size_override("font_size", 18)
	gold_line.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	gold_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(gold_line)

	var pick_lbl := Label.new()
	pick_lbl.text = "Choose an item:"
	pick_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	pick_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(pick_lbl)

	_choices_box = HBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 12)
	_choices_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_choices_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_choices_box)

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
	var gold_line := _choices_box.get_parent().get_node_or_null("GoldLine")
	if gold_line is Label:
		gold_line.text = "+%d gold" % _gold
	for c in _choices_box.get_children():
		c.queue_free()
	for item in _choices:
		_choices_box.add_child(_build_choice_tile(item))
	if _reroll_btn != null:
		_reroll_btn.text = "Reroll (%d)" % GameState.reroll_charges
		_reroll_btn.disabled = GameState.reroll_charges <= 0
		_reroll_btn.custom_minimum_size = Vector2(140, 40)

func _build_choice_tile(item: ItemData) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(230, 250)
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
	take.pressed.connect(func(): _on_take(item))
	vbox.add_child(take)
	return tile

# ------------------------------------------------------------------
# Item rolling — mirrors js/loot.js showItemChoiceModal + selectRandomRarity.
# ------------------------------------------------------------------

func _roll_choices() -> void:
	_choices.clear()
	var pool: Array = []
	for it in Data.all_items():
		if it is ItemData:
			pool.append(it)
	if pool.is_empty():
		return
	var discovery: int = Stats.get_value(&"discovery")
	var n: int = BASE_ITEM_CHOICES + maxi(0, discovery)
	var orb: bool = GameState.has_low_rarity_reroll()
	var attempts: int = 0
	while _choices.size() < n and attempts < 100:
		attempts += 1
		var target: int = _roll_rarity()
		var bucket: Array = pool.filter(func(it): return int(it.rarity) == target)
		if bucket.is_empty():
			bucket = pool
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

func _roll_rarity() -> int:
	var roll: float = _roll_with_luck_advantage() * (W_COMMON + W_UNCOMMON + W_RARE)
	var r: int
	if roll < W_COMMON:
		r = ItemData.Rarity.COMMON
	elif roll < W_COMMON + W_UNCOMMON:
		r = ItemData.Rarity.UNCOMMON
	else:
		r = ItemData.Rarity.RARE
	# Rare has a 10% bump to legendary (js/data.js selectRandomRarity).
	if r == ItemData.Rarity.RARE and _rng.randf() < 0.1:
		r = ItemData.Rarity.LEGENDARY
	return r

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

func _on_take(item: ItemData) -> void:
	if _resolved:
		return
	_resolved = true
	GameState.add_item(item)
	GameLog.add("Picked up %s." % item.display_name, Color(0.7, 1.0, 0.7))
	_finish()

func _on_skip() -> void:
	if _resolved:
		return
	_resolved = true
	GameLog.add("Skipped the item reward.", Color(0.8, 0.8, 0.8))
	_finish()

func _on_reroll() -> void:
	if _resolved or GameState.reroll_charges <= 0:
		return
	GameState.reroll_charges -= 1
	_roll_choices()
	_refresh()

func _finish() -> void:
	emit_signal("closed")
	queue_free()
