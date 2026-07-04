class_name Shop
extends Control

# Standalone shop modal: 3 items + 2 cards + remove-card service. Used
# by merchant nodes on the deckbuilder map. Emits `closed` when the
# player picks Leave; the caller is responsible for free()ing.

signal closed

const ITEM_PRICES := {0: 8, 1: 15, 2: 25, 3: 35, 4: 40}
const CARD_PRICES := {0: 0, 1: 15, 2: 30, 3: 50, 4: 80}
const REMOVE_PRICE := 50
# Potions sell unidentified, priced by rarity index (Common..Legendary).
const POTION_PRICES := {0: 10, 1: 18, 2: 30, 3: 45}
# Pay to reveal one carried potion type.
const IDENTIFY_PRICE := 20

# Panel + section geometry. Kept here so the layout reads in one place; the
# shop is built entirely in code and shared by every combat (action floor +
# deckbuilder map), so this is the single source of its look.
const PANEL_SIZE := Vector2(900, 772)
const ITEM_CELL := Vector2(264, 188)

# Rarity colours mirror the rest of the UI (Backpack.RARITY_COLORS).
const RARITY_COLORS := [
	Color(0.78, 0.78, 0.78), Color(0.45, 0.85, 0.5),
	Color(0.4, 0.6, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.8, 0.3),
]

var _items: Array = []           # [{item: ItemData, price, purchased, buy_btn, cell}]
var _cards: Array = []           # [{card: CardData, price, purchased, buy_btn, view}]
var _potions: Array = []         # [{potion: PotionData, price, purchased, buy_btn, cell}]
var _potion_btns: Array[Button] = []
var _identify_btn: Button = null
var _remove_used: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _gold_label: Label
var _remove_btn: Button
var _item_btns: Array[Button] = []
var _card_btns: Array[Button] = []

func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_roll_inventory()
	_build_ui()
	_refresh_buttons()

# ---------------------------------------------------------------------------
# Inventory rolling
# ---------------------------------------------------------------------------

func _roll_inventory() -> void:
	_items.clear()
	_cards.clear()
	_remove_used = false

	for picked in Data.roll_weighted_items(3, _rng):
		_items.append({
			"item": picked,
			"price": int(ITEM_PRICES.get(picked.rarity, 10)),
			"purchased": false,
		})

	# Card stock follows the run's chosen deck, like the HTML shop did
	# (Random deck = unfiltered pool).
	var card_pool: Array = Data.reward_card_pool(GameState.deck_reward_tag())
	for _i in range(mini(2, card_pool.size())):
		var idx: int = _rng.randi() % card_pool.size()
		var picked: CardData = card_pool[idx]
		card_pool.remove_at(idx)
		_cards.append({
			"card": picked,
			"price": int(CARD_PRICES.get(picked.rarity, 20)),
			"purchased": false,
		})

	_potions.clear()
	for _i in range(2):
		var p: PotionData = Data.roll_potion(_rng)
		if p != null:
			_potions.append({
				"potion": p,
				"price": int(POTION_PRICES.get(p.rarity_index(), 15)),
				"purchased": false,
			})

# ---------------------------------------------------------------------------
# UI build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	add_child(dim)

	# Clamp the panel to the viewport so the header never spills off the top of
	# the screen (the 772px design height is taller than a 720px window). When it
	# doesn't fit, the inner ScrollContainer lets the content scroll instead.
	var vp: Vector2 = get_viewport_rect().size
	var panel_h: float = minf(PANEL_SIZE.y, vp.y - 24.0)
	var panel_w: float = minf(PANEL_SIZE.x, vp.x - 24.0)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(panel_w, panel_h)
	panel.size = Vector2(panel_w, panel_h)
	panel.position = Vector2((vp.x - panel_w) / 2.0, maxf(12.0, (vp.y - panel_h) / 2.0)).round()
	panel.add_theme_stylebox_override("panel",
		_sb(Color(0.10, 0.09, 0.13, 0.98), Color(0.42, 0.33, 0.55, 0.9), 2, 14))
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(panel_w - 28.0, 0)
	scroll.add_child(root)

	# --- Header: shopkeeper title + live gold ---
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "🛒  Shop"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	header.add_child(title)
	_gold_label = Label.new()
	_gold_label.text = "Gold: %d" % GameState.gold
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	header.add_child(_gold_label)

	root.add_child(_section_header("ITEMS"))

	var items_row := HBoxContainer.new()
	items_row.add_theme_constant_override("separation", 16)
	items_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(items_row)
	for entry in _items:
		items_row.add_child(_build_item_cell(entry))

	root.add_child(_section_header("CARDS"))

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 22)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(cards_row)
	for entry in _cards:
		cards_row.add_child(_build_card_cell(entry))

	if not _potions.is_empty():
		root.add_child(_section_header("POTIONS"))
		var potions_row := HBoxContainer.new()
		potions_row.add_theme_constant_override("separation", 16)
		potions_row.alignment = BoxContainer.ALIGNMENT_CENTER
		root.add_child(potions_row)
		for entry in _potions:
			potions_row.add_child(_build_potion_cell(entry))

	root.add_child(_section_header("SERVICES"))

	var svc_row := HBoxContainer.new()
	svc_row.add_theme_constant_override("separation", 16)
	svc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(svc_row)
	_remove_btn = Button.new()
	_remove_btn.custom_minimum_size = Vector2(360, 46)
	_remove_btn.text = "✂  Remove a card  (%dg)" % REMOVE_PRICE
	_remove_btn.pressed.connect(_open_remove_picker)
	svc_row.add_child(_remove_btn)
	_identify_btn = Button.new()
	_identify_btn.custom_minimum_size = Vector2(360, 46)
	_identify_btn.text = "🔍  Identify a potion  (%dg)" % IDENTIFY_PRICE
	_identify_btn.pressed.connect(_open_identify_picker)
	svc_row.add_child(_identify_btn)

	var leave_row := HBoxContainer.new()
	leave_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(leave_row)
	var leave_btn := Button.new()
	leave_btn.custom_minimum_size = Vector2(200, 46)
	leave_btn.text = "Leave shop"
	leave_btn.pressed.connect(_on_leave)
	leave_row.add_child(leave_btn)

# A small uppercase section divider label.
func _section_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(1.0, 0.78, 0.4))
	return l

func _sb(fill: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]

# An item card: real item icon on top, name (rarity-coloured) + rarity, the
# item description, and a buy button showing the price.
func _build_item_cell(entry: Dictionary) -> Control:
	var item: ItemData = entry.item
	var rcol: Color = _rarity_color(item.rarity)

	var cell := PanelContainer.new()
	cell.custom_minimum_size = ITEM_CELL
	cell.add_theme_stylebox_override("panel",
		_sb(Color(0.14, 0.13, 0.18, 0.96), rcol.darkened(0.2), 1, 10))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	cell.add_child(vb)

	var icon := TextureRect.new()
	icon.texture = item.image
	icon.custom_minimum_size = Vector2(0, 58)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vb.add_child(icon)

	var name_l := Label.new()
	name_l.text = item.display_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", rcol)
	vb.add_child(name_l)

	var desc_l := Label.new()
	desc_l.text = item.description
	desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_l.add_theme_font_size_override("font_size", 11)
	desc_l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	vb.add_child(desc_l)

	var buy := Button.new()
	buy.pressed.connect(func(): _buy_item(entry))
	vb.add_child(buy)

	entry["cell"] = cell
	entry["buy_btn"] = buy
	_item_btns.append(buy)
	return cell

# A card offer: the real in-game CardView (so it reads exactly as it will in a
# fight) plus a buy button. Clicking the card itself also buys it.
func _build_card_cell(entry: Dictionary) -> Control:
	var card: CardData = entry.card

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var view := CardView.new()
	view.custom_minimum_size = Vector2(CardView.CARD_W, CardView.CARD_H)
	view.setup(CardInstance.from_data(card))
	view.play_requested.connect(func(_c): _buy_card(entry))
	vb.add_child(view)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(CardView.CARD_W, 40)
	buy.pressed.connect(func(): _buy_card(entry))
	vb.add_child(buy)

	entry["view"] = view
	entry["buy_btn"] = buy
	_card_btns.append(buy)
	return vb

# A potion offer: sold UNIDENTIFIED, so it shows the mystery bottle + a generic
# label. Buying drops it (still unidentified) into the loot belt.
func _build_potion_cell(entry: Dictionary) -> Control:
	var potion: PotionData = entry.potion
	var known: bool = PotionSystem.is_identified(potion.id)
	var rcol: Color = _rarity_color(potion.rarity_index())

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(220, 180)
	cell.add_theme_stylebox_override("panel",
		_sb(Color(0.14, 0.13, 0.18, 0.96), rcol.darkened(0.2), 1, 10))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	cell.add_child(vb)

	var icon := TextureRect.new()
	icon.texture = PotionSystem.art_texture(potion)
	icon.custom_minimum_size = Vector2(0, 58)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vb.add_child(icon)

	var name_l := Label.new()
	name_l.text = PotionSystem.display_name(potion)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", rcol)
	vb.add_child(name_l)

	var desc_l := Label.new()
	desc_l.text = potion.effect_text if known else "A mystery potion."
	desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_l.add_theme_font_size_override("font_size", 11)
	desc_l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	vb.add_child(desc_l)

	var buy := Button.new()
	buy.pressed.connect(func(): _buy_potion(entry))
	vb.add_child(buy)

	entry["cell"] = cell
	entry["buy_btn"] = buy
	_potion_btns.append(buy)
	return cell

func _buy_potion(entry: Dictionary) -> void:
	if entry.purchased or GameState.gold < entry.price:
		return
	GameState.spend_gold(entry.price)
	GameState.add_potion_loot(entry.potion.id)
	entry.purchased = true
	GameLog.add("Bought a potion for %dg." % entry.price, Color(0.7, 1.0, 0.7))
	_refresh_buttons()

# Pay to reveal one carried, still-unidentified potion type.
func _open_identify_picker() -> void:
	if GameState.gold < IDENTIFY_PRICE:
		return
	# Unique unidentified potion ids the player is carrying.
	var seen: Dictionary = {}
	var ids: Array = []
	for e in GameState.loot_potions():
		var pid := StringName(e.get("id", ""))
		if pid != &"" and not PotionSystem.is_identified(pid) and not seen.has(pid):
			seen[pid] = true
			ids.append(pid)
	if ids.is_empty():
		GameLog.add("No unidentified potions to identify.", Color(0.8, 0.8, 0.5))
		return

	var picker := Control.new()
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	picker.add_child(dim)
	var panel := Panel.new()
	panel.size = Vector2(560, 460)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	picker.add_child(panel)
	var title := Label.new()
	title.position = Vector2(20, 16)
	title.size = Vector2(520, 28)
	title.text = "Identify a potion  (%dg)" % IDENTIFY_PRICE
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 60)
	scroll.size = Vector2(520, 340)
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)
	for pid in ids:
		var potion: PotionData = Data.get_potion(pid)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(500, 40)
		# Show the mystery bottle colour so the player knows which they're paying for.
		btn.text = "Unidentified Potion (%s)" % PotionSystem.unidentified_color(pid).replace("Unidentified_", "")
		btn.pressed.connect(func(): _complete_identify(pid, picker))
		vbox.add_child(btn)
	var cancel := Button.new()
	cancel.position = Vector2(220, 410)
	cancel.size = Vector2(120, 40)
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): picker.queue_free())
	panel.add_child(cancel)
	add_child(picker)

func _complete_identify(pid: StringName, picker: Control) -> void:
	if GameState.gold < IDENTIFY_PRICE:
		picker.queue_free()
		return
	GameState.spend_gold(IDENTIFY_PRICE)
	PotionSystem.identify(pid)
	_refresh_buttons()
	picker.queue_free()

# ---------------------------------------------------------------------------
# Refresh + buy
# ---------------------------------------------------------------------------

func _refresh_buttons() -> void:
	for i in range(_item_btns.size()):
		_format_item_btn(_item_btns[i], _items[i])
	for i in range(_card_btns.size()):
		_format_card_btn(_card_btns[i], _cards[i])
	for i in range(_potion_btns.size()):
		_format_potion_btn(_potion_btns[i], _potions[i])
	if _gold_label != null:
		_gold_label.text = "Gold: %d" % GameState.gold
	if _remove_btn != null and not _remove_used:
		_remove_btn.disabled = GameState.gold < REMOVE_PRICE
	if _identify_btn != null:
		_identify_btn.disabled = GameState.gold < IDENTIFY_PRICE

func _format_potion_btn(btn: Button, entry: Dictionary) -> void:
	if entry.purchased:
		btn.text = "SOLD"
		btn.disabled = true
		if entry.has("cell") and entry.cell != null:
			entry.cell.modulate = Color(0.55, 0.55, 0.55)
		return
	btn.text = "Buy  •  %dg" % entry.price
	btn.disabled = GameState.gold < entry.price

func _format_item_btn(btn: Button, entry: Dictionary) -> void:
	if entry.purchased:
		btn.text = "SOLD"
		btn.disabled = true
		if entry.has("cell") and entry.cell != null:
			entry.cell.modulate = Color(0.55, 0.55, 0.55)
		return
	btn.text = "Buy  •  %dg" % entry.price
	btn.disabled = GameState.gold < entry.price

func _format_card_btn(btn: Button, entry: Dictionary) -> void:
	if entry.purchased:
		btn.text = "SOLD"
		btn.disabled = true
		if entry.has("view") and entry.view != null:
			entry.view.set_enabled(false)
		return
	btn.text = "Buy  •  %dg" % entry.price
	btn.disabled = GameState.gold < entry.price

func _buy_item(entry: Dictionary) -> void:
	if entry.purchased or GameState.gold < entry.price:
		return
	GameState.spend_gold(entry.price)
	GameState.add_item(entry.item)
	entry.purchased = true
	GameLog.add("Bought %s for %dg." % [entry.item.display_name, entry.price], Color(0.7, 1.0, 0.7))
	_refresh_buttons()

func _buy_card(entry: Dictionary) -> void:
	if entry.purchased or GameState.gold < entry.price:
		return
	GameState.spend_gold(entry.price)
	GameState.add_card_to_deck(entry.card)
	entry.purchased = true
	GameLog.add("Bought %s for %dg." % [entry.card.display_name, entry.price], Color(0.7, 1.0, 0.7))
	_refresh_buttons()

# ---------------------------------------------------------------------------
# Remove-card service
# ---------------------------------------------------------------------------

func _open_remove_picker() -> void:
	if _remove_used or GameState.gold < REMOVE_PRICE:
		return
	var picker := Control.new()
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	picker.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(640, 520)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	picker.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 16)
	title.size = Vector2(600, 28)
	title.text = "Remove a card  (%dg)" % REMOVE_PRICE
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 60)
	scroll.size = Vector2(600, 400)
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	for idx in range(GameState.deck.size()):
		var c = GameState.deck[idx]
		if not (c is CardInstance):
			continue
		var inst: CardInstance = c
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(580, 36)
		btn.text = "[%d] %s   --  %s" % [inst.get_cost(), inst.get_display_name(), inst.get_description()]
		var captured_idx: int = idx
		var captured_picker: Control = picker
		btn.pressed.connect(func(): _complete_remove(captured_idx, captured_picker))
		vbox.add_child(btn)

	var cancel_btn := Button.new()
	cancel_btn.position = Vector2(260, 470)
	cancel_btn.size = Vector2(120, 40)
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): picker.queue_free())
	panel.add_child(cancel_btn)

	add_child(picker)

func _complete_remove(deck_idx: int, picker: Control) -> void:
	if deck_idx < 0 or deck_idx >= GameState.deck.size():
		picker.queue_free()
		return
	var removed: CardInstance = GameState.deck[deck_idx]
	GameState.deck.remove_at(deck_idx)
	GameState.spend_gold(REMOVE_PRICE)
	GameState.emit_signal("deck_changed")
	GameLog.add("Removed %s from your deck." % removed.data.display_name, Color(0.85, 0.9, 0.7))
	_remove_used = true
	if _remove_btn != null:
		_remove_btn.text = "(Remove used)"
		_remove_btn.disabled = true
	_refresh_buttons()
	picker.queue_free()

func _on_leave() -> void:
	emit_signal("closed")
