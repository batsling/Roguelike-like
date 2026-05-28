class_name Shop
extends Control

# Standalone shop modal: 3 items + 2 cards + remove-card service. Used
# by merchant nodes on the deckbuilder map. Emits `closed` when the
# player picks Leave; the caller is responsible for free()ing.

signal closed

const ITEM_PRICES := {0: 8, 1: 15, 2: 25, 3: 35, 4: 40}
const CARD_PRICES := {0: 0, 1: 15, 2: 30, 3: 50, 4: 80}
const REMOVE_PRICE := 50

var _items: Array = []           # [{item: ItemData, price, purchased}]
var _cards: Array = []           # [{card: CardData, price, purchased}]
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

	var item_pool: Array = []
	for it in Data.all_items():
		if it is ItemData:
			item_pool.append(it)
	for _i in range(mini(3, item_pool.size())):
		var idx: int = _rng.randi() % item_pool.size()
		var picked: ItemData = item_pool[idx]
		item_pool.remove_at(idx)
		_items.append({
			"item": picked,
			"price": int(ITEM_PRICES.get(picked.rarity, 10)),
			"purchased": false,
		})

	var card_pool: Array = []
	for c in Data.all_cards():
		if c is CardData and c.rarity != CardData.Rarity.STARTER:
			card_pool.append(c)
	for _i in range(mini(2, card_pool.size())):
		var idx: int = _rng.randi() % card_pool.size()
		var picked: CardData = card_pool[idx]
		card_pool.remove_at(idx)
		_cards.append({
			"card": picked,
			"price": int(CARD_PRICES.get(picked.rarity, 20)),
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

	var panel := Panel.new()
	panel.size = Vector2(840, 620)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 16)
	title.size = Vector2(800, 28)
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	_gold_label = Label.new()
	_gold_label.position = Vector2(680, 20)
	_gold_label.size = Vector2(140, 24)
	_gold_label.text = "Gold: %d" % GameState.gold
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	panel.add_child(_gold_label)

	# Items
	var items_title := Label.new()
	items_title.position = Vector2(20, 60)
	items_title.size = Vector2(800, 22)
	items_title.text = "Items"
	items_title.add_theme_font_size_override("font_size", 16)
	panel.add_child(items_title)

	var items_row := HBoxContainer.new()
	items_row.position = Vector2(20, 92)
	items_row.size = Vector2(800, 140)
	items_row.add_theme_constant_override("separation", 14)
	items_row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(items_row)
	for entry in _items:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(220, 130)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		var e: Dictionary = entry
		var b: Button = btn
		btn.pressed.connect(func(): _buy_item(e, b))
		items_row.add_child(btn)
		_item_btns.append(btn)

	# Cards
	var cards_title := Label.new()
	cards_title.position = Vector2(20, 246)
	cards_title.size = Vector2(800, 22)
	cards_title.text = "Cards"
	cards_title.add_theme_font_size_override("font_size", 16)
	panel.add_child(cards_title)

	var cards_row := HBoxContainer.new()
	cards_row.position = Vector2(20, 278)
	cards_row.size = Vector2(800, 140)
	cards_row.add_theme_constant_override("separation", 14)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(cards_row)
	for entry in _cards:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(220, 130)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		var e: Dictionary = entry
		var b: Button = btn
		btn.pressed.connect(func(): _buy_card(e, b))
		cards_row.add_child(btn)
		_card_btns.append(btn)

	# Services
	var svc_title := Label.new()
	svc_title.position = Vector2(20, 432)
	svc_title.size = Vector2(800, 22)
	svc_title.text = "Services"
	svc_title.add_theme_font_size_override("font_size", 16)
	panel.add_child(svc_title)

	_remove_btn = Button.new()
	_remove_btn.position = Vector2(80, 464)
	_remove_btn.size = Vector2(320, 50)
	_remove_btn.text = "Remove a card  (%dg)" % REMOVE_PRICE
	_remove_btn.pressed.connect(_open_remove_picker)
	panel.add_child(_remove_btn)

	var leave_btn := Button.new()
	leave_btn.position = Vector2(340, 552)
	leave_btn.size = Vector2(160, 48)
	leave_btn.text = "Leave shop"
	leave_btn.pressed.connect(_on_leave)
	panel.add_child(leave_btn)

# ---------------------------------------------------------------------------
# Refresh + buy
# ---------------------------------------------------------------------------

func _refresh_buttons() -> void:
	for i in range(_item_btns.size()):
		_format_item_btn(_item_btns[i], _items[i])
	for i in range(_card_btns.size()):
		_format_card_btn(_card_btns[i], _cards[i])
	if _gold_label != null:
		_gold_label.text = "Gold: %d" % GameState.gold
	if _remove_btn != null and not _remove_used:
		_remove_btn.disabled = GameState.gold < REMOVE_PRICE

func _format_item_btn(btn: Button, entry: Dictionary) -> void:
	var item: ItemData = entry.item
	if entry.purchased:
		btn.text = "SOLD\n%s" % item.display_name
		btn.disabled = true
		return
	btn.text = "%s\n(%s)\n\n%dg" % [item.display_name, _rarity_label(item.rarity), entry.price]
	btn.disabled = GameState.gold < entry.price

func _format_card_btn(btn: Button, entry: Dictionary) -> void:
	var card: CardData = entry.card
	if entry.purchased:
		btn.text = "SOLD\n%s" % card.display_name
		btn.disabled = true
		return
	btn.text = "[%d] %s\n(%s)\n\n%dg" % [card.cost, card.display_name, _rarity_label(card.rarity), entry.price]
	btn.disabled = GameState.gold < entry.price

func _buy_item(entry: Dictionary, _btn: Button) -> void:
	if entry.purchased or GameState.gold < entry.price:
		return
	GameState.change_gold(-entry.price)
	GameState.add_item(entry.item)
	entry.purchased = true
	GameLog.add("Bought %s for %dg." % [entry.item.display_name, entry.price], Color(0.7, 1.0, 0.7))
	_refresh_buttons()

func _buy_card(entry: Dictionary, _btn: Button) -> void:
	if entry.purchased or GameState.gold < entry.price:
		return
	GameState.change_gold(-entry.price)
	GameState.deck.append(CardInstance.from_data(entry.card))
	GameState.emit_signal("deck_changed")
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
	GameState.change_gold(-REMOVE_PRICE)
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

# ---------------------------------------------------------------------------

func _rarity_label(rarity: int) -> String:
	match rarity:
		0: return "Starter"
		1: return "Common"
		2: return "Uncommon"
		3: return "Rare"
		4: return "Legendary"
		_: return "?"
