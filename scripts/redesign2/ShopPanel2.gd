class_name ShopPanel2
extends PanelContainer

# ShopPanel2 — the shop standing at a Shop node (docs/games-first-redesign.md §14, §19.1),
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
# Shop node's game and STAYS THERE for the whole visit, until you travel on. Nothing is
# blocked while it is up, the offering is still one scroll away, and the decision
# "spend now or keep the gold" is made next to the board it will be spent on.
# Overworld2 floats a "🛒 Shop ↓" pointer at the foot of the screen until the
# panel has been scrolled to, so a shop below the fold is never a shop missed.
#
# THE SHELF IS THREE ITEMS AND IT STAYS. Every slot is drawn whether or not it
# has been bought — a sold one greys out and keeps its place — because the shelf
# persists for the whole run (ShopSystem) and a player coming back to a shop needs
# to recognise the shop they left. Reflowing two remaining items into the middle
# of the panel would make a return visit look like a fresh roll.
#
# WHAT THE PLAYER IS READING, and the order it's in: the price is the first thing
# on a card and the only thing that ever disables it, so "can I afford this" is
# answered before the item is even considered. An unaffordable card is dimmed and
# its button says the price rather than "Buy" — the number is the reason, so the
# number is what the button shows.
#
# AND THE HEADER SAYS "SHOP", NOT WHICH GAME'S SHOP. It used to be the game's own
# name with a sentence under it explaining that what you don't buy stays here.
# Both were furniture: the player knows which game they just beat — they are
# standing on its page, under its board — and the rule about the shelf persisting
# is something you learn once, not something worth re-reading at every shop. That
# is the panel's tooltip now, and the two lines they cost are spent on the shelf
# instead, which is the part that changes.
#
# SO A SHELF ROW CARRIES WHAT AN ITEM IS. Art, name, what it DOES, and the price —
# the description was the one thing you had to open a card to see, and it is the
# only one of the four that tells you whether the thing is worth the gold. The
# card is still there for the full text and the Buy button; the row is now enough
# to shop from without it.
#
# RARITY IS THE OUTLINE, the way the pack draws it (PackStrip._item_token): the
# row is tinted toward the item's class colour and edged in it, so a Legendary on
# a shelf and the same Legendary in your bag are recognisably one thing. It reads
# through UITheme.item_color rather than rarity_color, so a Boss relic reads as a
# Boss relic here as well.
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
# TALL ENOUGH TO SHOP FROM. The row was 28px with a 20px icon and one line of
# text reading "Name   ◉ 5", clipped — which meant that on the relics with long
# names (Bloody Lantern, Cracked Orb, Molten Egg) the clip ate the price, and the
# one number a shelf exists to show could only be found by opening the item. A
# thumbnail that small is not much of a picture either.
#
# So the row is a small card instead: art and name and price on the top line, and
# the item's own DESCRIPTION across the full width under them — what the thing
# does, which is the only one of the four that answers "is this worth the gold".
#
# WHERE THE HEIGHT COMES FROM, because it is not obvious and it is the reason the
# row could grow at all. The board is at its floor while it shares this column
# (BattlefieldView.FIELD_HEIGHT_BUDGET_SHARED clamps a 4x4 to CELL_MIN), so it
# cannot pay. But the page's height is the taller of its two columns, and on a
# shop's page that is the LEFT one — the checklist — by about sixty pixels. This
# panel is in the right column, so the room was already sitting there unused.
# `DESC_LINES` is where it is spent, and `test_the_page_still_fits_the_window_with_a_shop_on_it`
# is what holds the whole arrangement honest: raise either number and it says so.
const ROW_HEIGHT := 98.0
const ROW_ICON := 44
# How many lines of description a row shows before it ellipsizes. Three covers
# about nine relics in ten outright (the roster's descriptions run to a 43-char
# median and an 80-char ninetieth percentile, and this column fits ~30 a line);
# the longest few trim, and their card carries the whole of it.
const DESC_LINES := 3

# WHICH LAYER AN OPENED ITEM'S CARD GOES ON. 122 clears the page and everything
# mounted on it, which is right while this panel is under the board; it is NOT
# right while the panel is a section of the post-combat screen, which is itself a
# CanvasLayer at 128 — the card drew underneath it and only became visible once
# the player had left the screen, so a click on a shelf row looked like it had
# done nothing and then produced a popup a screen too late. The host sets this to
# clear itself.
var card_layer: int = 122

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


# Mount a Shop node's shop into `parent`. Returns null when that node has no shop (or
# its shelf could not be rolled), so the caller can simply not have one.
static func mount(parent: Control, game_id: StringName) -> ShopPanel2:
	if ShopSystem.shop_for(game_id).is_empty():
		return null
	var panel := ShopPanel2.new()
	panel._game_id = game_id
	# The game PLAYED there names it, which on a transmuted Shop node is the
	# replacement — the shelf rides the node (§19.2), the name the game you beat.
	panel._game = GameLoop2.game_at(game_id)
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
	# The reroll is bought with SCRAMBLE, and scramble moves for reasons that have
	# nothing to do with this shop — the D6 is used from the inventory two panels
	# up and pays one out. Without this the button kept the disabled state it was
	# painted with, so the charge the player had just spent an item to get could
	# not be spent here until something else happened to repaint the shop.
	if not GameState.stats_changed.is_connected(_on_stats_changed):
		GameState.stats_changed.connect(_on_stats_changed)


func _exit_tree() -> void:
	if ShopSystem.shop_changed.is_connected(_on_shop_changed):
		ShopSystem.shop_changed.disconnect(_on_shop_changed)
	if GameState.gold_changed.is_connected(_on_gold_changed):
		GameState.gold_changed.disconnect(_on_gold_changed)
	if GameState.stats_changed.is_connected(_on_stats_changed):
		GameState.stats_changed.disconnect(_on_stats_changed)


# The shop's name. `shopkeeper` is the seam for the authored roster that is still
# to come — until a shop carries one, the game played there names the place.
func _shop_name() -> String:
	var keeper: String = str(ShopSystem.peek(_game_id).get("shopkeeper", ""))
	if keeper != "":
		return keeper
	return "%s" % (_game.display_name if _game != null else String(_game_id))


# What the HEADER says, which is not the same question. A shop with an authored
# shopkeeper is a place with a name and the name is worth the line; a shop without
# one is just the storefront of the game you are standing on, and saying that game's
# name over its own page is the screen repeating itself (see `_chrome_line`). So the
# fallback is the flat word rather than `_shop_name`'s.
func _header_name() -> String:
	var keeper: String = str(ShopSystem.peek(_game_id).get("shopkeeper", ""))
	return keeper if keeper != "" else "Shop"


# The NODE this shop belongs to — the host reads it to tell "the shop already on
# the page" from "the shop owed at the node I just beat".
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
	root.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	margin.add_child(root)

	root.add_child(_chrome_line())
	_cards_row = HFlowContainer.new()
	_cards_row.add_theme_constant_override("h_separation", UITheme.GAP_WIDE)
	_cards_row.add_theme_constant_override("v_separation", UITheme.GAP_WIDE)
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
	row.add_theme_constant_override("separation", UITheme.GAP)

	# JUST "SHOP". It used to be the hub's own name, and that was a mistake twice
	# over.
	#
	# It said nothing: the shop is mounted on the page of the game you are standing
	# at, under that game's board, beside that game's card. Naming it again is the
	# screen telling you where you are for the third time.
	#
	# And it cost the LEFT COLUMN width. A Label that neither wraps nor clips
	# reports its whole string as its MINIMUM width, and a game's name is a long
	# string: that minimum became the shop panel's, the panel's became the right
	# column's, and the right column's came straight out of the left — where the
	# checklist's goal text then wrapped onto extra lines and grew the page. A shop
	# with a long name was a taller page than one with a short name, by up to 39px
	# on a page with four to spare, so "Enter the Gungeon" ran the overworld off the
	# bottom of its window and "FTL" did not. The clip below fixed that; a constant
	# word ends it. (The clip stays anyway — it costs nothing and it is what stopped
	# the bug, so it should not have to be rediscovered if this ever takes a name
	# again.)
	var title := Label.new()
	title.text = "🛒  %s" % _header_name()
	title.tooltip_text = _shop_name()
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 0.0
	# It ASKS FOR NOTHING and takes a share of whatever is left over, so the panel's
	# width is set by the shelf below it (which is a fixed three rows) and never by
	# the header.
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_stretch_ratio = 0.75
	title.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	title.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	# ONLY WHEN THERE IS NOTHING LEFT. This used to read "3 items on the shelf. What
	# you don't buy stays here for next time." — a count of the three rows sitting
	# directly underneath it, and a rule of the game explained at every single shop.
	# The count is the shelf, and the rule is the panel's tooltip. What is left is
	# the one state the shelf cannot show by itself: an empty one.
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_subtitle.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_subtitle)

	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_purse)

	_reroll_btn = Button.new()
	_reroll_btn.custom_minimum_size = Vector2(0, 24)
	_reroll_btn.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
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


# ONE SHELF ITEM, as a small card on the page.
#
# The card the row OPENS is 250px of art, name, kind, description and a Buy
# button, and three of those put the overworld 543px past the bottom of the
# window. So the shelf is not three cards; it is three rows carrying everything
# you decide with — the picture, the name, what it does, and the price — with the
# full card a click away for the Buy button and the untrimmed text.
#
# Laid out as a top line and a paragraph: art, name and price across the top
# (the price is the number the whole panel exists to answer, so it never trims),
# and the description under both of them at the row's FULL width, because 95px of
# leftover column beside a 44px icon is not a width you can read a sentence in.
#
# THE ROW WEARS THE ITEM'S RARITY — a background tinted toward the class colour
# and a border in it, the same two lines the pack uses on its tokens
# (PackStrip._item_token). That is why the styleboxes are built here per item
# rather than left to the theme: a Button's `normal` is what carries the outline.
func _shelf_row(slot: int, entry: Dictionary) -> Control:
	var item: ItemData = Data.get_item2(StringName(entry.get("item", &"")))
	var sold: bool = bool(entry.get("sold", false))
	var price: int = ShopSystem.price_of(entry)
	var afford: bool = ShopSystem.can_afford(entry)
	# item_color, not rarity_color: a Boss relic has a class of its own and should
	# read as one here exactly as it does in the pack and on the drop modal.
	var tint: Color = UITheme.item_color(item)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(ROW_WIDTH, ROW_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	if item == null:
		btn.text = "(empty)"
		btn.disabled = true
		return btn

	# The rarity dress. A sold slot keeps its place and loses its colour — the
	# shelf has to stay recognisable on a second visit, which is the whole reason
	# what you don't buy stays here.
	var edge: Color = UITheme.TEXT_FAINT if sold else tint.lerp(UITheme.BG, 0.45)
	var fill: Color = tint.lerp(UITheme.BG, 0.90 if sold else 0.86)
	btn.add_theme_stylebox_override("normal", UITheme.flat(fill, 6, 0, 2, edge))
	btn.add_theme_stylebox_override("disabled", UITheme.flat(fill, 6, 0, 2, edge))
	# Hover and press lift the same box rather than replacing it, so the outline
	# never changes colour under the cursor — the border means rarity and nothing
	# else.
	btn.add_theme_stylebox_override("hover",
		UITheme.flat(tint.lerp(UITheme.BG, 0.78), 6, 0, 2, tint))
	btn.add_theme_stylebox_override("pressed",
		UITheme.flat(tint.lerp(UITheme.BG, 0.72), 6, 0, 2, tint))
	btn.add_theme_stylebox_override("focus", UITheme.flat(Color(0, 0, 0, 0), 6, 0, 0))

	# The contents are CHILDREN of the button rather than its own icon-and-text.
	# A Button lays those out as one line and clips the lot, which is what put the
	# price behind the ellipsis; children can be laid out as a card, and only the
	# name and the description are ever given up to a trim. They ignore the mouse,
	# so the whole row is still one button.
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 5)
	pad.add_theme_constant_override("margin_bottom", 5)
	btn.add_child(pad)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(body)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(line)

	var art := UITheme.crisp_tex(item.image, ROW_ICON)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(art)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = item.display_name
	# The name trims before the price does: the price is the one number the panel
	# exists to show, and the tooltip and the card both repeat the name in full.
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.custom_minimum_size.x = 0.0
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	name_lbl.add_theme_color_override("font_color",
		UITheme.TEXT_FAINT if sold else tint)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "Sold" if sold else "◉ %d" % price
	price_lbl.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	price_lbl.add_theme_color_override("font_color", UITheme.TEXT_FAINT if sold
		else (UITheme.COIN_GOLD if afford else UITheme.DANGER))
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(price_lbl)

	# WHAT THE THING DOES, across the whole row rather than in the column beside
	# the art. Wrapped to DESC_LINES and ellipsized after them, so a long relic
	# trims instead of growing the row and taking the page off the bottom of the
	# window — and `custom_minimum_size.x = 0` so the sentence never reports its
	# own length as a width the panel has to honour, which is the bug the header
	# above used to have.
	var desc := Label.new()
	desc.text = item.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.max_lines_visible = DESC_LINES
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.clip_text = true
	desc.custom_minimum_size.x = 0.0
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	desc.add_theme_color_override("font_color",
		UITheme.TEXT_FAINT if sold else UITheme.TEXT_DIM)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(desc)

	# One you cannot afford is dimmed rather than dropped or disabled — you can
	# still open it and read it, you just cannot buy it yet.
	btn.modulate.a = 0.55 if sold else (1.0 if afford else 0.78)
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
	layer.layer = card_layer
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
	col.add_theme_constant_override("separation", UITheme.GAP)
	margin.add_child(col)
	col.add_child(_card(slot, shelf[slot]))

	var done := Button.new()
	done.text = "Put it back"
	done.custom_minimum_size = Vector2(0, 32)
	done.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
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
		_subtitle.text = "Sold out — nothing left on the shelf." if left == 0 else ""
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
	box.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
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
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	name_lbl.add_theme_color_override("font_color", tint)
	box.add_child(name_lbl)

	var kind := Label.new()
	kind.text = _kind_line(item)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	kind.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(kind)

	var desc := Label.new()
	desc.text = item.description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	var buy_btn := Button.new()
	buy_btn.custom_minimum_size = Vector2(0, 32)
	buy_btn.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
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


# Scramble moved. Only the chrome carries it — the shelf itself is unchanged —
# so the reroll button is repainted rather than the whole panel rebuilt.
func _on_stats_changed() -> void:
	if is_inside_tree():
		_paint_chrome()
