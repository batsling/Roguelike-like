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
# WHAT A KEEPER ADDS (§14.6), all through ShopSystem: their action buttons under
# the shelf (Steal, Bomb), and the machines standing in their room (Isaac's
# Donation Machine), which belong to the room the way an event's do — spawned on
# opening, gone on closing.
#
# UNLIKE AN EVENT, LEAVING DECIDES NOTHING. The shelf persists for the run
# (ShopSystem), so closing this is not an answer to anything: a click outside the
# panel closes it, and so do Escape and Leave. The button on the page stays for the
# whole visit and opens the same shelf again.
#
# The shelf itself is ShopPanel2, mounted inside — this file is only the frame.

# Emitted once when the pop-up closes, however it closed.
signal finished

const PANEL_WIDTH := 1000.0
const PORTRAIT_WIDTH := 220.0
const PORTRAIT_MAX_HEIGHT := 300.0
# The option column under the portrait: wide enough for a machine's row.
const OPTION_WIDTH := 260.0
# The machine a `donation_shelf` keeper always has in the room.
const DONATION_MACHINE := &"donation_machine"

var _node_id: StringName = &""
var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _shelf: ShopPanel2 = null
var _portrait_rect: Control = null
var _actions: VBoxContainer = null
var _objects_box: VBoxContainer = null
var _objects_before: Array = []
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

	# TWO SIDES: the keeper and everything you can DO here on the left (the
	# portrait, then their options: Steal, Bomb, the reroll, a machine in the room),
	# and on the right only what you can BUY, one row per kind on a shared grid.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	root.add_child(body)

	var side := VBoxContainer.new()
	side.name = "Options"
	side.custom_minimum_size.x = OPTION_WIDTH
	side.add_theme_constant_override("separation", UITheme.GAP)
	body.add_child(side)
	var portrait: Texture2D = keeper.portrait() if keeper != null else null
	if portrait != null and not ShopSystem.is_bombed(_node_id):
		_portrait_rect = _portrait(portrait)
		side.add_child(_portrait_rect)
	_actions = VBoxContainer.new()
	_actions.name = "Actions"
	_actions.add_theme_constant_override("separation", UITheme.GAP)
	side.add_child(_actions)

	var divider := ColorRect.new()
	divider.color = UITheme.BORDER
	divider.custom_minimum_size = Vector2(1, 0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(divider)

	_shelf = ShopPanel2.mount(body, _node_id, false)
	if _shelf != null:
		_shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_shelf.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		# Its item cards open over this pop-up, not under it.
		_shelf.card_layer = UITheme.Layer.CHOICE
		_shelf.finished.connect(close)
		var reroll: Button = _shelf.reroll_button()
		reroll.name = "Reroll"
		_style_option(reroll, UITheme.ACCENT)
		side.add_child(reroll)

	_objects_box = VBoxContainer.new()
	side.add_child(_objects_box)
	_open_room()

	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(180, 40)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	leave.pressed.connect(close)
	root.add_child(leave)

	if not ShopSystem.shop_changed.is_connected(_on_shop_changed):
		ShopSystem.shop_changed.connect(_on_shop_changed)
	if not GameState.stats_changed.is_connected(_paint_actions):
		GameState.stats_changed.connect(_paint_actions)
	_paint_actions()


# The keeper's name in the event's title style, and their line under it. A shop
# with no keeper says "Shop" and nothing else.
func _header(keeper: ShopkeeperData) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_NONE)
	var title := Label.new()
	title.name = "Title"
	title.text = "🛒  %s" % (keeper.display_name if keeper != null else "Shop")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.FONT_DISPLAY)
	title.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	col.add_child(title)
	if keeper != null and keeper.description != "":
		var line := Label.new()
		line.name = "Line"
		line.text = keeper.description
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
		line.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		col.add_child(line)
	if keeper != null and keeper.game_id != &"":
		var game: GameData = Data.get_game(keeper.game_id)
		if game != null:
			var from := Label.new()
			from.text = "From: %s" % game.display_name
			from.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			from.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
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
	rect.custom_minimum_size = Vector2(PORTRAIT_WIDTH,
		minf(PORTRAIT_WIDTH * aspect, PORTRAIT_MAX_HEIGHT))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_crisp(rect, tex)
	return rect


# --- the keeper's buttons ---------------------------------------------------

func _paint_actions() -> void:
	if _actions == null or not is_instance_valid(_actions):
		return
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	var steal: int = ShopSystem.keeper_number(_node_id, "steal")
	if steal > 0 and not bool(ShopSystem.peek(_node_id).get("stolen", false)):
		_actions.add_child(_action("Steal", "Steal ◉%d" % steal, UITheme.DANGER,
			true, func(): ShopSystem.steal(_node_id)))
	if ShopSystem.keeper_has(_node_id, "bombable") and not ShopSystem.is_bombed(_node_id):
		_actions.add_child(_action("Bomb", "✸  Bomb", UITheme.DANGER,
			ShopSystem.can_bomb(_node_id), func(): bomb()))
	_actions.visible = _actions.get_child_count() > 0

func _action(id: String, text: String, tint: Color, enabled: bool, press: Callable) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.disabled = not enabled
	_style_option(b, tint)
	b.pressed.connect(press)
	return b

# Every option in the column the same shape: full width, one height, its colour on
# the edge and the word.
func _style_option(b: Button, tint: Color) -> void:
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_FILL
	b.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	b.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.45))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", UITheme.flat(tint.lerp(UITheme.BG, 0.82), 6, 8, 1, tint.lerp(UITheme.BG, 0.4)))
	b.add_theme_stylebox_override("hover", UITheme.flat(tint.lerp(UITheme.BG, 0.68), 6, 8, 1, tint))
	b.add_theme_stylebox_override("pressed", UITheme.flat(tint.lerp(UITheme.BG, 0.58), 6, 8, 1, tint))
	b.add_theme_stylebox_override("disabled", UITheme.flat(UITheme.BG.lerp(UITheme.PANEL, 0.5), 6, 8, 1, UITheme.BORDER))
	b.add_theme_stylebox_override("focus", UITheme.flat(Color(0, 0, 0, 0), 6, 0, 0))

# Bomb the keeper: what it rolled comes up as a toast, and the keeper is gone.
func bomb() -> String:
	var got: String = ShopSystem.bomb(_node_id)
	if got == "":
		return got
	if _portrait_rect != null and is_instance_valid(_portrait_rect):
		_portrait_rect.queue_free()
		_portrait_rect = null
	# Gold says itself (the purse's toast); the rest are named.
	var say: String = {"steam_sale": "Steam Sale", "spider": "Spider",
		"nothing": "Nothing"}.get(got, "")
	if say != "":
		Notifications.notify(say, UITheme.SHOP_GREEN)
	return got

func _on_shop_changed(node: StringName) -> void:
	if node == _node_id:
		_paint_actions()


# --- the room's machines ----------------------------------------------------

# A `donation_shelf` keeper's room always has a Donation Machine in it. Spawned on
# opening and taken away on closing, as an event's machines are
# (ObjectSystem.clear_spawned_since), and drawn as the page draws machines: a
# compact row, its card one click away (ObjectPanel2).
var _machines: ObjectPanel2 = null

func _open_room() -> void:
	_objects_before = ObjectSystem.live.duplicate()
	if ShopSystem.keeper_has(_node_id, "donation_shelf"):
		ObjectSystem.spawn(DONATION_MACHINE, false)
		_machines = ObjectPanel2.mount(_objects_box)
		if _machines != null:
			_machines.card_layer = UITheme.Layer.CHOICE
			_machines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_machines.narrow()
	_objects_box.visible = _machines != null

func has_room_machines() -> bool:
	return _machines != null and is_instance_valid(_machines)


func close() -> void:
	if _done:
		return
	_done = true
	if _shelf != null and is_instance_valid(_shelf):
		_shelf.close_card()
	if ShopSystem.shop_changed.is_connected(_on_shop_changed):
		ShopSystem.shop_changed.disconnect(_on_shop_changed)
	if GameState.stats_changed.is_connected(_paint_actions):
		GameState.stats_changed.disconnect(_paint_actions)
	ObjectSystem.clear_spawned_since(_objects_before)
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		close()
