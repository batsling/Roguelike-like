class_name ShopModal2
extends Control

# ShopModal2 — the shop standing at a hub game (docs/games-first-redesign.md §14).
#
# Opens after the hub's game is beaten, on the same queue an event opens on: the
# board is usually still playing its resolve back when the game is reported, so
# Overworld2 holds this behind that animation rather than dropping it over the
# top (see `_pending_shop` there).
#
# THE SHELF IS THREE ITEMS AND IT STAYS. Every slot is drawn whether or not it
# has been bought — a sold one greys out and keeps its place — because the shelf
# persists for the whole run (ShopSystem) and a player coming back to a hub needs
# to recognise the shop they left. Reflowing two remaining items into the middle
# of the panel would make a return visit look like a fresh roll.
#
# WHAT THE PLAYER IS READING, and the order it's in: the price is the first thing
# on a card and the only thing that ever disables it, so "can I afford this" is
# answered before the item is even considered. An unaffordable card is dimmed and
# its button says the price rather than "Buy" — the number is the reason, so the
# number is what the button shows.
#
# Everything mechanical routes through ShopSystem; this file is the view. The
# three public verbs (buy / reroll / leave) are what a headless test drives.

signal finished

# Three cards side by side plus their margins. Wide rather than tall on purpose:
# the shop is three things compared against each other, which is a row.
const PANEL_SIZE := Vector2(760, 0)
const CARD_WIDTH := 216.0
const ART_PX := 84

var _game_id: StringName = &""
var _game: GameData = null
var _layer: CanvasLayer = null
var _done: bool = false

var _panel: PanelContainer = null
var _cards_row: HBoxContainer = null
var _purse: Label = null
var _reroll_btn: Button = null
var _subtitle: Label = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


static func open(host: Node, game_id: StringName) -> ShopModal2:
	var modal := ShopModal2.new()
	modal._start(host, game_id)
	return modal


func _start(host: Node, game_id: StringName) -> void:
	_game_id = game_id
	_game = Data.get_game(game_id)
	_layer = CanvasLayer.new()
	_layer.layer = 122
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if ShopSystem.shop_for(_game_id).is_empty():
		_close()
		return
	# Standing in it is what makes the stock public: from here on the game's card
	# quotes what's left rather than just saying a shop is here (§14).
	ShopSystem.mark_seen(_game_id)
	GameLog.add("Shop: %s" % _shop_name(), UITheme.SHOP_GREEN)
	_build()
	if not ShopSystem.shop_changed.is_connected(_on_shop_changed):
		ShopSystem.shop_changed.connect(_on_shop_changed)
	if not GameState.gold_changed.is_connected(_on_gold_changed):
		GameState.gold_changed.connect(_on_gold_changed)


# The shop's name. `shopkeeper` is the seam for the authored roster that is still
# to come — until a shop carries one, the hub's own game names the place, which
# is honest about what a shop currently is: the big node's storefront.
func _shop_name() -> String:
	var keeper: String = str(ShopSystem.peek(_game_id).get("shopkeeper", ""))
	if keeper != "":
		return keeper
	return "%s" % (_game.display_name if _game != null else String(_game_id))


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build() -> void:
	# No click-outside-to-close. Gold is scarce enough that leaving a shop is a
	# decision, and a stray click on the dim is not one.
	_panel = ModalScaffold.build_panel(self, UITheme.SHOP_GREEN, Callable(), PANEL_SIZE)
	_panel.custom_minimum_size = Vector2(PANEL_SIZE.x, 0)
	_panel.size = Vector2(PANEL_SIZE.x, 0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_header())
	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 12)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_cards_row)
	root.add_child(_footer())
	_render()


# Centre the panel ONCE IT HAS A HEIGHT. The panel is built with a width and no
# height so it can size to its own content, which means at build time it is
# 760x0 and ModalScaffold's `position = -size * 0.5` centres a zero-height box —
# the panel then grows DOWNWARDS from the middle of the screen and its footer
# (the purse, the reroll, the Leave button) falls off the bottom edge. It did
# exactly that until this existed.
#
# Offsets rather than `position`, for the same reason EventModal2._recentre uses
# them: `position` on a centre-anchored Control is stored relative to
# anchor × parent_size, and this modal's parent has not been sized yet when the
# first frame runs.
func _settle() -> void:
	await get_tree().process_frame
	if _panel == null or not is_instance_valid(_panel):
		return
	_panel.size = _panel.get_combined_minimum_size()
	var half: Vector2 = _panel.size * 0.5
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -half.x
	_panel.offset_top = -half.y
	_panel.offset_right = half.x
	_panel.offset_bottom = half.y


func _header() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "🛒  %s" % _shop_name()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	col.add_child(title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	col.add_child(_subtitle)
	return col


func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# The purse, bottom left — the same number as the header chip behind the
	# modal, repeated here because the modal covers that chip.
	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", 17)
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_purse)

	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(190, 40)
	_reroll_btn.pressed.connect(func(): reroll())
	row.add_child(_reroll_btn)

	var leave := Button.new()
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(120, 40)
	leave.pressed.connect(func(): leave_shop())
	row.add_child(leave)
	return row


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

func _render() -> void:
	if _cards_row == null or not is_instance_valid(_cards_row):
		return
	for child in _cards_row.get_children():
		child.queue_free()
	var shelf: Array = ShopSystem.stock(_game_id)
	for i in range(shelf.size()):
		_cards_row.add_child(_card(i, shelf[i]))
	_paint_chrome()
	# Re-centre on EVERY render, not just the first. A sold card drops its price
	# button's text and a reroll swaps in items with longer or shorter
	# descriptions, so the tallest card — and with it the panel — changes height
	# under the player. Without this the panel keeps its old offsets and drifts
	# off-centre as they shop.
	_settle.call_deferred()


func _paint_chrome() -> void:
	if _purse != null and is_instance_valid(_purse):
		_purse.text = "◉  %d gold" % GameState.gold
		_purse.add_theme_color_override("font_color",
			UITheme.COIN_GOLD if GameState.gold > 0 else UITheme.TEXT_FAINT)
	if _subtitle != null and is_instance_valid(_subtitle):
		var left: int = ShopSystem.remaining(_game_id).size()
		_subtitle.text = ("Sold out — nothing left on the shelf." if left == 0
			else "%d item%s on the shelf. What you don't buy stays here." % [
				left, "" if left == 1 else "s"])
	if _reroll_btn != null and is_instance_valid(_reroll_btn):
		var charges: int = GameState.scramble
		_reroll_btn.text = "🎲  Reroll  (Scramble %d)" % charges
		_reroll_btn.disabled = not ShopSystem.can_reroll(_game_id)
		_reroll_btn.tooltip_text = ("Spend 1 Scramble to redraw all three slots."
			if charges >= ShopSystem.REROLL_COST
			else "Needs a Scramble charge — you have none.")


func _card(slot: int, entry: Dictionary) -> Control:
	var item: ItemData = Data.get_item2(StringName(entry.get("item", &"")))
	var sold: bool = bool(entry.get("sold", false))
	var price: int = ShopSystem.price_of(entry)
	var afford: bool = ShopSystem.can_afford(entry)
	var tint: Color = UITheme.rarity_color(int(item.rarity)) if item != null else UITheme.TEXT_DIM

	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	wrap.size_flags_vertical = Control.SIZE_FILL
	# A sold slot keeps its place and loses its colour. Dimming rather than
	# removing is what makes the shelf recognisable on a second visit.
	wrap.add_theme_stylebox_override("panel", RarityStyle.panel(
		int(item.rarity) if item != null else 0, 10) if not sold
		else UITheme.flat(UITheme.BG, 8, 10, 1, UITheme.BORDER))
	wrap.modulate.a = 0.45 if sold else (1.0 if afford else 0.72)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	wrap.add_child(box)

	if item == null:
		var missing := Label.new()
		missing.text = "(empty)"
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		box.add_child(missing)
		return wrap

	var art := UITheme.crisp_tex(item.image, ART_PX)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)

	var name_lbl := Label.new()
	name_lbl.text = item.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", tint)
	box.add_child(name_lbl)

	var kind := Label.new()
	kind.text = _kind_line(item)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_font_size_override("font_size", 11)
	kind.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(kind)

	var desc := Label.new()
	desc.text = item.description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(0, 38)
	buy_btn.add_theme_font_size_override("font_size", 15)
	if sold:
		buy_btn.text = "Sold"
		buy_btn.disabled = true
	else:
		buy_btn.text = "◉  %d" % price
		buy_btn.disabled = not afford
		if afford:
			buy_btn.add_theme_stylebox_override("normal",
				UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.55), 8, 8, 2, UITheme.SUCCESS))
			buy_btn.add_theme_stylebox_override("hover",
				UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.35), 8, 8, 2, UITheme.SUCCESS))
			buy_btn.add_theme_color_override("font_color", UITheme.SUCCESS.lerp(Color.WHITE, 0.5))
			buy_btn.tooltip_text = "Buy %s for %d gold." % [item.display_name, price]
		else:
			buy_btn.tooltip_text = "%d gold — you have %d." % [price, GameState.gold]
	buy_btn.pressed.connect(func(): buy(slot))
	box.add_child(buy_btn)
	return wrap


# Mirrors ItemDropModal._kind_line — an item has to read the same way whether it
# fell off an enemy or is being sold to you.
func _kind_line(item: ItemData) -> String:
	var rarity: String = UITheme.rarity_name(int(item.rarity))
	match item.kind:
		ItemData.ItemKind.USABLE:
			return "%s · active" % rarity
		ItemData.ItemKind.TRIGGERED:
			return "%s · triggered" % rarity
		_:
			if item.is_charged():
				return "%s · charges" % rarity
			return "%s · passive" % rarity


# ---------------------------------------------------------------------------
# Verbs — public so a headless test can shop without a click
# ---------------------------------------------------------------------------

func buy(slot: int) -> bool:
	var bought: ItemData = ShopSystem.buy(_game_id, slot)
	if bought == null:
		return false
	Notifications.notify("Bought %s." % bought.display_name, UITheme.SHOP_GREEN)
	return true


func reroll() -> bool:
	return ShopSystem.reroll(_game_id)


func leave_shop() -> void:
	_close()


func _on_shop_changed(game_id: StringName) -> void:
	if game_id == _game_id:
		_render()


func _on_gold_changed(_amount: int = 0) -> void:
	# A purchase repaints through shop_changed already; this catches gold moving
	# for any other reason while the shop is open, so the prices never lie about
	# what is affordable.
	_render()


func _close() -> void:
	if _done:
		return
	_done = true
	if ShopSystem.shop_changed.is_connected(_on_shop_changed):
		ShopSystem.shop_changed.disconnect(_on_shop_changed)
	if GameState.gold_changed.is_connected(_on_gold_changed):
		GameState.gold_changed.disconnect(_on_gold_changed)
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_close()
