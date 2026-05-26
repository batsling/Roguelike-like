class_name TreasureRoom
extends Control

# Treasure-node modal: offer 3 random items, player picks one (or
# skips entirely). Standalone Control; emits `closed` on selection.
#
# Phase 2 keeps the roll uniform across all items. Rarity weighting
# (Common / Uncommon / Rare / Legendary curves) lands when the wider
# rarity tables get tuned alongside the stat dispatcher.

signal closed

const OFFER_COUNT := 3

var _offers: Array = []                # Array of ItemData
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_roll_offers()
	_build_ui()

# ---------------------------------------------------------------------------

func _roll_offers() -> void:
	_offers.clear()
	var pool: Array = []
	for it in Data.all_items():
		if it is ItemData:
			pool.append(it)
	for _i in range(mini(OFFER_COUNT, pool.size())):
		var idx: int = _rng.randi() % pool.size()
		_offers.append(pool[idx])
		pool.remove_at(idx)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.04, 0.05, 0.85)
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(800, 500)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 20)
	title.size = Vector2(760, 32)
	title.text = "Treasure"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var hint := Label.new()
	hint.position = Vector2(20, 60)
	hint.size = Vector2(760, 22)
	hint.text = "Choose one item to take."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	panel.add_child(hint)

	var row := HBoxContainer.new()
	row.position = Vector2(20, 100)
	row.size = Vector2(760, 320)
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	if _offers.is_empty():
		var empty := Label.new()
		empty.text = "(The chest is empty.)"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(empty)
	else:
		for it in _offers:
			row.add_child(_make_offer_view(it))

	var skip_btn := Button.new()
	skip_btn.position = Vector2(320, 440)
	skip_btn.size = Vector2(160, 44)
	skip_btn.text = "Skip"
	skip_btn.pressed.connect(_on_skip)
	panel.add_child(skip_btn)

func _make_offer_view(item: ItemData) -> Control:
	# Card-like vertical layout: image on top, name, rarity, description.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 320)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(200, 160)
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	if item.image != null:
		img.texture = item.image
	vbox.add_child(img)

	var name_lbl := Label.new()
	name_lbl.text = item.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	vbox.add_child(name_lbl)

	var rarity_lbl := Label.new()
	rarity_lbl.text = "(%s)" % _rarity_label(item.rarity)
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.add_theme_font_size_override("font_size", 11)
	rarity_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(rarity_lbl)

	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.custom_minimum_size = Vector2(200, 40)
	desc.add_theme_font_size_override("normal_font_size", 11)
	desc.text = "[center]%s[/center]" % item.description
	vbox.add_child(desc)

	var take_btn := Button.new()
	take_btn.text = "Take"
	take_btn.custom_minimum_size = Vector2(180, 36)
	var item_ref: ItemData = item
	take_btn.pressed.connect(func(): _on_take(item_ref))
	vbox.add_child(take_btn)

	return card

# ---------------------------------------------------------------------------

func _on_take(item: ItemData) -> void:
	GameState.inventory.append(item)
	GameState.emit_signal("inventory_changed")
	GameLog.add("Took %s." % item.display_name, Color(0.7, 1.0, 0.7))
	TriggerBus.emit_signal("item_acquired", {"item": item})
	emit_signal("closed")

func _on_skip() -> void:
	GameLog.add("Left the treasure behind.", Color(0.7, 0.7, 0.7))
	emit_signal("closed")

func _rarity_label(rarity: int) -> String:
	match rarity:
		0: return "Common"
		1: return "Uncommon"
		2: return "Rare"
		3: return "Epic"
		4: return "Legendary"
		_: return "?"
