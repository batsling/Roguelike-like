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

var _game_id: StringName = &""
var _game: GameData = null
var _done: bool = false

var _cards_row: HFlowContainer = null
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
	add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.SHOP_GREEN.lerp(UITheme.BORDER, 0.4), 12, 12, 2))
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
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	root.add_child(_header())
	_cards_row = HFlowContainer.new()
	_cards_row.add_theme_constant_override("h_separation", 10)
	_cards_row.add_theme_constant_override("v_separation", 10)
	root.add_child(_cards_row)
	root.add_child(_footer())
	_render()


func _header() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)

	var title := Label.new()
	title.text = "🛒  %s" % _shop_name()
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	col.add_child(title)

	_subtitle = Label.new()
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 11)
	_subtitle.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	col.add_child(_subtitle)
	return col


# The purse and the reroll, and no Leave button: there is nothing to leave. The
# shop is a part of the page now, and travelling to the next game is what closes
# it — which is the same thing walking out of a shop has always meant.
func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", 15)
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_purse)

	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(180, 32)
	_reroll_btn.add_theme_font_size_override("font_size", 12)
	_reroll_btn.pressed.connect(func(): reroll())
	row.add_child(_reroll_btn)
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
		_cards_row.add_child(_card(i, shelf[i]))
	_paint_chrome()


func _paint_chrome() -> void:
	if _purse != null and is_instance_valid(_purse):
		_purse.text = "◉  %d gold" % GameState.gold
		_purse.add_theme_color_override("font_color",
			UITheme.COIN_GOLD if GameState.gold > 0 else UITheme.TEXT_FAINT)
	if _subtitle != null and is_instance_valid(_subtitle):
		var left: int = ShopSystem.remaining(_game_id).size()
		_subtitle.text = ("Sold out — nothing left on the shelf." if left == 0
			else "%d item%s on the shelf. What you don't buy stays here for next time." % [
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
	Notifications.notify("Bought %s." % bought.display_name, UITheme.SHOP_GREEN)
	return true


func reroll() -> bool:
	return ShopSystem.reroll(_game_id)


# Take the shop off the page — the player has travelled on, or the run ended.
func close() -> void:
	if _done:
		return
	_done = true
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
