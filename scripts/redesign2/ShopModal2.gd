class_name ShopModal2
extends Control

# ShopModal2 — the shop at a Shop node, as a pop-up (docs/games-first-redesign.md
# §14.4, §14.6). It opens when the player asks for it: the 🛒 Shop button on the
# offering's heading (Overworld2._shop_btn), or the haul screen's "Go to Shop"
# exit. Nothing opens it by itself.
#
# IT LOOKS LIKE AN EVENT ON PURPOSE. A shopkeeper is someone you meet at a place,
# which is what an event is, so the frame is EventModal2's: a centred panel over a
# dimmed page, the keeper's portrait in a column on the left, the name over the
# top, their line under it, and the shelf where an event's choices would be.
# Without a keeper there is no portrait and no line, and the title is "Shop".
#
# UNLIKE AN EVENT, LEAVING DECIDES NOTHING. The shelf persists for the run
# (ShopSystem), so closing this is not an answer to anything: a click outside the
# panel closes it, and so do Escape and Leave. The button on the page stays for the
# whole visit and opens the same shelf again.
#
# The shelf itself is ShopPanel2, mounted inside — this file is only the frame.

# Emitted once when the pop-up closes, however it closed.
signal finished

const PANEL_WIDTH := 640.0
const PORTRAIT_WIDTH := 180.0

var _node_id: StringName = &""
var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _shelf: ShopPanel2 = null
var _done: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


# Open the shop at `node_id` over `host`. Returns null when that node has no shop
# (or its shelf could not be rolled), so the caller can simply not have one.
static func open(host: Node, node_id: StringName) -> ShopModal2:
	if ShopSystem.shop_for(node_id).is_empty():
		return null
	var modal := ShopModal2.new()
	modal._node_id = node_id
	modal._layer = CanvasLayer.new()
	modal._layer.layer = UITheme.Layer.EVENT
	modal._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(modal._layer)
	modal._layer.add_child(modal)
	modal._build()
	return modal


func node_id() -> StringName:
	return _node_id

# The shelf inside, for the tests and for the page's own "what is open" checks.
func shelf() -> ShopPanel2:
	return _shelf


func _build() -> void:
	_panel = ModalScaffold.build_panel(self, UITheme.SHOP_GREEN, Callable(self, "close"),
		Vector2(PANEL_WIDTH, 0))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	margin.add_child(root)

	var keeper: ShopkeeperData = ShopSystem.keeper_for(_node_id)
	root.add_child(_header(keeper))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	root.add_child(body)
	var portrait: Texture2D = keeper.portrait() if keeper != null else null
	if portrait != null:
		body.add_child(_portrait(portrait))
	_shelf = ShopPanel2.mount(body, _node_id, false)
	if _shelf != null:
		_shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Its item cards open over this pop-up, not under it.
		_shelf.card_layer = UITheme.Layer.CHOICE
		_shelf.finished.connect(close)

	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(140, 32)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	leave.pressed.connect(close)
	root.add_child(leave)


# The keeper's name in the event's title style, and their line under it. A shop
# with no keeper says "Shop" and nothing else.
func _header(keeper: ShopkeeperData) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_NONE)
	var title := Label.new()
	title.name = "Title"
	title.text = "🛒  %s" % (keeper.display_name if keeper != null else "Shop")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	title.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	col.add_child(title)
	if keeper != null and keeper.description != "":
		var line := Label.new()
		line.name = "Line"
		line.text = keeper.description
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		line.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		col.add_child(line)
	if keeper != null and keeper.game_id != &"":
		var game: GameData = Data.get_game(keeper.game_id)
		if game != null:
			var from := Label.new()
			from.text = "From: %s" % game.display_name
			from.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			from.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
			from.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
			col.add_child(from)
	return col


# The portrait column, EventModal2._art_column's shape: fixed width, height from
# the picture's own aspect, top-aligned with the shelf.
func _portrait(tex: Texture2D) -> Control:
	var rect := TextureRect.new()
	rect.name = "Portrait"
	rect.texture = tex
	var aspect: float = float(tex.get_height()) / maxf(1.0, float(tex.get_width()))
	rect.custom_minimum_size = Vector2(PORTRAIT_WIDTH, minf(PORTRAIT_WIDTH * aspect, 320.0))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_crisp(rect, tex)
	return rect


func close() -> void:
	if _done:
		return
	_done = true
	if _shelf != null and is_instance_valid(_shelf):
		_shelf.close_card()
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		close()
