class_name ShopPanel2
extends PanelContainer

# ShopPanel2 — the shop standing at a hub game (docs/games-first-redesign.md §14),
# mounted BELOW THE BATTLEFIELD on the page rather than opened over it.
#
# It was a modal, and the modal was the problem: the run's rhythm is report the
# game → see what it cost you on the board → choose where to go next, and a
# full-screen shop dropped into the middle of that stopped the whole screen to
# ask a question the player had not asked yet. It also covered the two things
# they had just come back to read — the board and the offering — so buying
# anything meant deciding without them.
#
# So the shop is now part of the page: it appears under the board when you beat a
# hub's game and STAYS THERE for the whole visit, until you travel on. Nothing is
# blocked while it is up, the offering is still one scroll away, and the decision
# "spend now or keep the gold" is made next to the board it will be spent on.
# Overworld2 floats a "🛒 Shop ↓" pointer at the foot of the screen until the
# panel has been scrolled to, so a shop below the fold is never a shop missed.
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
# Everything mechanical routes through ShopSystem; this file is the view. The two
# public verbs (buy / reroll) are what a headless test drives.

# Emitted when the shop takes itself down (the run ended under it). The host owns
# the panel's place on the page, so it is the host that removes it.
signal finished

# The cards flow rather than sitting in a fixed row: this panel shares the right
# column with the board, which is as wide as the board's own width budget, and a
# rigid 3-across row would have pushed that column wider than the page. Three fit
# side by side at the board's width; a narrower column wraps them instead.
const CARD_WIDTH := 178.0
const ART_PX := 72
# A shelf item's line on the page. Sized so a FULL SHELF fits across on ONE line
# — three rows and their gutters inside the ~548px the right column actually
# hands this panel, which is less than the column's own width by its padding.
# Measured tight rather than generous on purpose: a second line costs 34px the
# page does not have, and the flow wraps on a single pixel. The name ellipsizes
# on the longest relics; the row's tooltip carries the whole of it either way.
const ROW_WIDTH := 166.0
const ROW_HEIGHT := 28.0
const ROW_ICON := 20

var _game_id: StringName = &""
var _game: GameData = null
var _done: bool = false

var _cards_row: HFlowContainer = null
# The open item's card, if one is open. One at a time: you are looking at a thing
# on the shelf or you are not.
var _card_layer: CanvasLayer = null
var _purse: Label = null
var _reroll_btn: Button = null
var _subtitle: Label = null


# Mount a hub's shop into `parent`. Returns null when that game has no shop (or
# its shelf could not be rolled), so the caller can simply not have one.
static func mount(parent: Control, game_id: StringName) -> ShopPanel2:
	if ShopSystem.shop_for(game_id).is_empty():
		return null
	var panel := ShopPanel2.new()
	panel._game_id = game_id
	panel._game = Data.get_game(game_id)
	parent.add_child(panel)
	# Standing in it is what makes the stock public: from here on the game's card
	# quotes what's left rather than just saying a shop is here (§14).
	ShopSystem.mark_seen(game_id)
	GameLog.add("Shop: %s" % panel._shop_name(), UITheme.SHOP_GREEN)
	panel._build()
	return panel


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_FILL
	# Tight padding, load-bearing rather than taste: this panel and the machines'
	# are splitting the ~116px the page has left once the board is at its floor.
	add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.SHOP_GREEN.lerp(UITheme.BORDER, 0.4), 10, 6, 2))
	if not ShopSystem.shop_changed.is_connected(_on_shop_changed):
		ShopSystem.shop_changed.connect(_on_shop_changed)
	if not GameState.gold_changed.is_connected(_on_gold_changed):
		GameState.gold_changed.connect(_on_gold_changed)


func _exit_tree() -> void:
	if ShopSystem.shop_changed.is_connected(_on_shop_changed):
		ShopSystem.shop_changed.disconnect(_on_shop_changed)
	if GameState.gold_changed.is_connected(_on_gold_changed):
		GameState.gold_changed.disconnect(_on_gold_changed)


# The shop's name. `shopkeeper` is the seam for the authored roster that is still
# to come — until a shop carries one, the hub's own game names the place, which
# is honest about what a shop currently is: the big node's storefront.
func _shop_name() -> String:
	var keeper: String = str(ShopSystem.peek(_game_id).get("shopkeeper", ""))
	if keeper != "":
		return keeper
	return "%s" % (_game.display_name if _game != null else String(_game_id))


# The game this shop belongs to — the host reads it to tell "the shop already on
# the page" from "the shop owed at the hub I just beat".
func game_id() -> StringName:
	return _game_id


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	root.add_child(_chrome_line())
	_cards_row = HFlowContainer.new()
	_cards_row.add_theme_constant_override("h_separation", 10)
	_cards_row.add_theme_constant_override("v_separation", 10)
	# Wide enough for TWO lines across, always — the same floor the machines' panel
	# carries and for the same reason. This flow sizes to the right column, the
	# column sizes to its widest child, and the board narrows as it shrinks to make
	# room for THIS panel; without a floor the shelf wraps to one item per line and
	# the shop grows in payment for the height the board just gave it.
	# Three rows, their two gutters, and a few pixels of slack — measured exactly,
	# a rounding pixel is enough to wrap the shelf onto a second line and cost 34px.
	_cards_row.custom_minimum_size.x = ROW_WIDTH * 3.0 + 2.0 * 10.0
	root.add_child(_cards_row)
	_render()


# The shop's whole chrome on ONE LINE: who it is, what is left, what you are
# holding, and the reroll. It was a title, a subtitle under it and a footer row
# with the purse and the button — 90px of furniture around 30px of shelf, on a
# page that has about 116px for the entire panel.
func _chrome_line() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "🛒  %s" % _shop_name()
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	# What is left on the shelf, and what you have to spend on it. The sentence
	# that used to say it ("what you don't buy stays here for next time") is the
	# panel's tooltip now — it is a rule to learn once, not a line to re-read at
	# every hub.
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 11)
	_subtitle.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_subtitle)

	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", 12)
	_purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_purse)

	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(0, 24)
	_reroll_btn.add_theme_font_size_override("font_size", 11)
	_reroll_btn.pressed.connect(func(): reroll())
	row.add_child(_reroll_btn)

	tooltip_text = "What you don't buy stays here for next time."
	return row


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

func _render() -> void:
	if _cards_row == null or not is_instance_valid(_cards_row):
		return
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()
	var shelf: Array = ShopSystem.stock(_game_id)
	for i in range(shelf.size()):
		_cards_row.add_child(_shelf_row(i, shelf[i]))
	_paint_chrome()


# ONE SHELF ITEM, as a line on the page.
#
# The card below is 250px of art, name, kind, description and a Buy button, and
# three of them put the overworld 543px past the bottom of the window — the page
# is a fixed 1280x720 canvas with about five pixels spare, and this panel and the
# board are sharing what is left. So the page keeps what you SHOP by — the
# picture, the name, the price, and whether you can afford it — and the card
# opens over it when you want to read what the thing actually does.
func _shelf_row(slot: int, entry: Dictionary) -> Control:
	var item: ItemData = Data.get_item2(StringName(entry.get("item", &"")))
	var sold: bool = bool(entry.get("sold", false))
	var price: int = ShopSystem.price_of(entry)
	var afford: bool = ShopSystem.can_afford(entry)
	var tint: Color = UITheme.rarity_color(int(item.rarity)) if item != null else UITheme.TEXT_DIM

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(ROW_WIDTH, ROW_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_constant_override("icon_max_width", ROW_ICON)
	# CLIPPED, so the row is the width it was given rather than the width its
	# label wants. A Button's minimum size is its content, so one long relic name
	# quietly pushed the row past ROW_WIDTH, and the flow — which is measured to
	# the pixel — wrapped the shelf onto a second line.
	btn.clip_text = true
	if item == null:
		btn.text = "(empty)"
		btn.disabled = true
		return btn
	btn.icon = item.image
	btn.text = "%s   ◉ %d" % [item.display_name, price]
	btn.add_theme_color_override("font_color", tint)
	if sold:
		btn.text = "%s   Sold" % item.display_name
		btn.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	# A sold slot keeps its place and loses its colour, and one you cannot afford
	# is dimmed rather than dropped — the shelf has to stay recognisable on a
	# second visit, which is the whole reason what you don't buy stays here.
	btn.modulate.a = 0.45 if sold else (1.0 if afford else 0.72)
	btn.tooltip_text = "%s — %s\n\n%s\n\n%s" % [
		item.display_name, _kind_line(item), item.description,
		"Click to look at it." if not sold else "Already bought."]
	btn.pressed.connect(func(): open_card(slot))
	return btn


# The item, opened: the SAME card the shelf used to draw on the page, with its
# Buy button, over the page on a layer of its own. Buying closes it — the
# purchase is the answer to the question the card asks.
func open_card(slot: int) -> Node:
	close_card()
	var shelf: Array = ShopSystem.stock(_game_id)
	if slot < 0 or slot >= shelf.size():
		return null
	var layer := CanvasLayer.new()
	layer.layer = 122
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_card_layer = layer

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	# Click-outside closes it: looking at a thing on a shelf and putting it back
	# is a complete answer, and the shop asks nothing of you.
	var panel := ModalScaffold.build_panel(root, UITheme.SHOP_GREEN,
		Callable(self, "close_card"), Vector2(CARD_WIDTH + 60.0, 0))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	col.add_child(_card(slot, shelf[slot]))

	var done := Button.new()
	done.text = "Put it back"
	done.custom_minimum_size = Vector2(0, 32)
	done.add_theme_font_size_override("font_size", 13)
	done.pressed.connect(close_card)
	col.add_child(done)
	return layer


func close_card() -> void:
	if _card_layer != null and is_instance_valid(_card_layer):
		_card_layer.queue_free()
	_card_layer = null


func _paint_chrome() -> void:
	if _purse != null and is_instance_valid(_purse):
		_purse.text = "◉ %d" % GameState.gold
		_purse.add_theme_color_override("font_color",
			UITheme.COIN_GOLD if GameState.gold > 0 else UITheme.TEXT_FAINT)
	if _subtitle != null and is_instance_valid(_subtitle):
		var left: int = ShopSystem.remaining(_game_id).size()
		_subtitle.text = ("Sold out — nothing left on the shelf." if left == 0
			else "%d item%s on the shelf. What you don't buy stays here for next time." % [
				left, "" if left == 1 else "s"])
	if _reroll_btn != null and is_instance_valid(_reroll_btn):
		var charges: int = GameState.scramble
		_reroll_btn.text = "🎲 %d" % charges
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
		int(item.rarity) if item != null else 0, 8) if not sold
		else UITheme.flat(UITheme.BG, 8, 8, 1, UITheme.BORDER))
	wrap.modulate.a = 0.45 if sold else (1.0 if afford else 0.72)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
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
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", tint)
	box.add_child(name_lbl)

	var kind := Label.new()
	kind.text = _kind_line(item)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_font_size_override("font_size", 10)
	kind.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(kind)

	var desc := Label.new()
	desc.text = item.description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(0, 32)
	buy_btn.add_theme_font_size_override("font_size", 14)
	if sold:
		buy_btn.text = "Sold"
		buy_btn.disabled = true
	else:
		buy_btn.text = "◉  %d" % price
		buy_btn.disabled = not afford
		if afford:
			buy_btn.add_theme_stylebox_override("normal",
				UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.55), 8, 6, 2, UITheme.SUCCESS))
			buy_btn.add_theme_stylebox_override("hover",
				UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.35), 8, 6, 2, UITheme.SUCCESS))
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
	# The card was open to answer "do I want this"; the answer is in hand.
	close_card()
	Notifications.notify("Bought %s." % bought.display_name, UITheme.SHOP_GREEN)
	return true


func reroll() -> bool:
	return ShopSystem.reroll(_game_id)


# Take the shop off the page — the player has travelled on, or the run ended.
func close() -> void:
	if _done:
		return
	_done = true
	close_card()
	finished.emit()
	queue_free()


func _on_shop_changed(game_id_changed: StringName) -> void:
	if game_id_changed == _game_id:
		_render()


func _on_gold_changed(_amount: int = 0) -> void:
	# A purchase repaints through shop_changed already; this catches gold moving
	# for any other reason while the shop is up, so the prices never lie about
	# what is affordable.
	_render()
