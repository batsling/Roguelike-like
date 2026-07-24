class_name CardRewardScreen
extends Control

# Card-reward choice, shown when a level-up (or other source) grants a card.
# Mirrors the HTML prototype's showCardRewardModal:
#   * Offers 3 (+ Discovery) unique cards, rolled at 75/20/5
#     common/uncommon/rare with luck advantage (no legendary bump — cards
#     top out at Rare in the reward roll).
#   * Pool is Data.reward_card_pool(tag_filter): a class tag (e.g. &"ironclad")
#     narrows it to that class plus universal "hero" cards.
#   * Each rolled card has a per-difficulty chance to come pre-upgraded
#     (Low 0% / Medium 25% / High+ 50%) when it can_upgrade.
#   * Click a card to select, then "Add to Deck"; Reroll spends a reroll
#     charge; Skip takes nothing.
#
# Reuses CardView (scripts/deckbuilder/CardView.gd) for the tiles. Emits
# `closed` when resolved so the caller can tear down its CanvasLayer.

signal closed

const W_COMMON := 75.0
const W_UNCOMMON := 20.0
const W_RARE := 5.0
const BASE_CARD_CHOICES := 3
# Reward tiles render much larger than the in-combat hand cards (art and all) so
# the card — especially its image — reads clearly during the choice.
const REWARD_CARD_SCALE := 1.7
# Pre-upgrade chance keyed by RunDifficulty tier (LOW, MEDIUM, HIGH, INSANE).
const UPGRADE_CHANCE_BY_TIER := [0.0, 0.25, 0.5, 0.5]

var _tag_filter: StringName = &""
var _choices: Array = []                 # Array[CardInstance]
var _rng := RandomNumberGenerator.new()
var _resolved: bool = false
var _started: bool = false
var _setup_called: bool = false
var _selected: CardInstance = null

var _choices_box: HBoxContainer
var _reroll_btn: Button
var _confirm_btn: Button
var _tiles: Array = []                    # Array[CardView], parallel to _choices

# tag_filter: class tag to narrow the pool (&"" = full reward pool).
# Safe to call before or after the node enters the tree.
func setup(tag_filter: StringName = &"") -> void:
	_tag_filter = tag_filter
	_setup_called = true
	if is_inside_tree() and not _started:
		_started = true
		_begin()

func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# If setup() ran before we entered the tree, kick off now.
	if _setup_called and not _started:
		_started = true
		_begin()

func _begin() -> void:
	_roll_choices()
	_refresh()

# ------------------------------------------------------------------
# UI
# ------------------------------------------------------------------

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# A CenterContainer auto-centers the panel at whatever size its content ends up
	# — so the panel always hugs however many cards were rolled instead of a fixed
	# rectangle with dead space (cleaner + handles Discovery's extra choices).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.10, 0.11, 0.15, 0.98)
	panel_style.set_corner_radius_all(16)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.35, 0.45, 0.65, 0.9)
	panel_style.set_content_margin_all(28)
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	panel.add_child(root)

	var title := Label.new()
	title.text = "Choose a card"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_choices_box = HBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 24)
	_choices_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_choices_box)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(btn_row)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Add to Deck"
	_confirm_btn.custom_minimum_size = Vector2(170, 42)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	_reroll_btn = Button.new()
	_reroll_btn.pressed.connect(_on_reroll)
	_reroll_btn.custom_minimum_size = Vector2(150, 42)
	btn_row.add_child(_reroll_btn)

	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.custom_minimum_size = Vector2(150, 42)
	skip_btn.pressed.connect(_on_skip)
	btn_row.add_child(skip_btn)

func _refresh() -> void:
	if _choices_box == null:
		return
	for c in _choices_box.get_children():
		c.queue_free()
	_tiles.clear()
	for ci in _choices:
		# Reward tiles read much bigger than in-combat hand cards. A scaled
		# CardView can't be an HBox child directly — the container fights the
		# scale and leaves dead space — so wrap it in a fixed-size Control (the
		# same pattern CardView.build_deck_cell uses) that reserves the scaled
		# footprint while the card scales cleanly inside it.
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(CardView.CARD_W, CardView.CARD_H) * REWARD_CARD_SCALE
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var view := CardView.new()
		view.setup(ci)
		view.scale = Vector2(REWARD_CARD_SCALE, REWARD_CARD_SCALE)
		view.play_requested.connect(_on_select)
		wrapper.add_child(view)
		_choices_box.add_child(wrapper)
		_tiles.append(view)
	if _confirm_btn != null:
		_confirm_btn.disabled = _selected == null
	if _reroll_btn != null:
		_reroll_btn.text = "Reroll (%d)" % GameState.reroll_charges
		_reroll_btn.disabled = GameState.reroll_charges <= 0

func _on_select(card: CardInstance) -> void:
	_selected = card
	for i in range(_tiles.size()):
		_tiles[i].set_selected(_choices[i] == card)
	if _confirm_btn != null:
		_confirm_btn.disabled = false

# ------------------------------------------------------------------
# Card rolling — mirrors js/cards.js showCardRewardModal.
# ------------------------------------------------------------------

func _roll_choices() -> void:
	_choices.clear()
	_selected = null
	var pool: Array = Data.reward_card_pool(_tag_filter)
	if pool.is_empty():
		return
	var discovery: int = Stats.get_value(&"discovery")
	var n: int = BASE_CARD_CHOICES + maxi(0, discovery)
	var upgrade_chance: float = _upgrade_chance()
	var attempts: int = 0
	while _choices.size() < n and attempts < 100:
		attempts += 1
		var target: int = _roll_rarity()
		var bucket: Array = pool.filter(func(c): return int(c.rarity) == target)
		if bucket.is_empty():
			bucket = pool
		var pick: CardData = bucket[_rng.randi_range(0, bucket.size() - 1)]
		var dup: bool = false
		for ci in _choices:
			if ci.data != null and ci.data.id == pick.id:
				dup = true
				break
		if dup:
			# Pool smaller than the requested count — stop once exhausted.
			if _choices.size() >= pool.size():
				break
			continue
		var upgraded: bool = pick.can_upgrade and upgrade_chance > 0.0 \
			and _rng.randf() < upgrade_chance
		_choices.append(CardInstance.from_data(pick, upgraded))

func _upgrade_chance() -> float:
	var tier: int = clampi(RunDifficulty.current_tier(), 0, UPGRADE_CHANCE_BY_TIER.size() - 1)
	return UPGRADE_CHANCE_BY_TIER[tier]

# Common/Uncommon/Rare weighted roll with luck advantage. Cards don't bump to
# legendary in the reward roll (unlike items), matching the HTML card modal.
func _roll_rarity() -> int:
	var roll: float = _roll_with_luck_advantage() * (W_COMMON + W_UNCOMMON + W_RARE)
	if roll < W_COMMON:
		return CardData.Rarity.COMMON
	elif roll < W_COMMON + W_UNCOMMON:
		return CardData.Rarity.UNCOMMON
	return CardData.Rarity.RARE

# Port of rollWithLuckAdvantage (js/data.js): positive luck has a luck*10%
# chance to take the better of two rolls, negative luck the worse.
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

func _on_confirm() -> void:
	if _resolved or _selected == null:
		return
	_resolved = true
	GameState.add_card_to_deck(_selected)
	GameLog.add("Added %s to your deck." % _selected.get_display_name(),
		Color(0.7, 1.0, 0.8))
	_finish()

func _on_skip() -> void:
	if _resolved:
		return
	_resolved = true
	GameLog.add("Skipped the card reward.", Color(0.8, 0.8, 0.8))
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
