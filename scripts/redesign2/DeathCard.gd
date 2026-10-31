extends Control

# THE BEAT BEFORE THE VERDICT, for a death outside a game (the owner, 31 Oct 2026:
# "if I die due to a potion or other out of combat reason, make sure it shows up
# and then click continue to get to the death screen").
#
# A death in a game report already has its beat: the board plays the blow back
# and the verdict waits for it (Overworld2._resolving). A death anywhere else — an
# event's bill, a pill off the haul table, a curse, a card — used to raise the
# end screen on the very frame Health hit 0, over whatever did it, so the thing
# that killed you was never seen. This card stands in that gap: the page under it
# is left exactly as the fatal moment left it (Health at 0, the event's or the
# haul's own screen still open behind), it says what happened in the words the
# run's log wrote, and Continue is what raises the end screen.
#
# A potion, scroll or pill used FROM THE PACK does not come here: its use screen
# is already the account of what it did, so the run waits for that screen's own
# button instead (LootUseModal.mark_fatal, Overworld2._hold_death).
#
# Loaded on demand (Overworld2.DEATH_CARD_SCRIPT), like the end screen, so it
# stays out of the page's cold compile (test_page_load.gd).

signal continued

# How many of the log's last lines it shows.
const LINES := 4
const ACCENT := UITheme.DANGER

var _layer: CanvasLayer = null
var lines: Array = []
var continue_button: Button = null

static func open(host: Node, log_lines: Array) -> Control:
	var card: Control = load("res://scripts/redesign2/DeathCard.gd").new()
	card.lines = log_lines
	card._layer = CanvasLayer.new()
	card._layer.layer = UITheme.Layer.VERDICT
	card._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(card._layer)
	card._layer.add_child(card)
	return card

# The log's last LINES lines, oldest first: what the run wrote on its way to 0.
static func recent_lines() -> Array:
	var out: Array = []
	var msgs: Array = GameLog.messages
	for i in range(maxi(0, msgs.size() - LINES), msgs.size()):
		var t: String = String((msgs[i] as Dictionary).get("text", "")).strip_edges()
		if t != "":
			out.append(t)
	return out

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	# No dismiss: the only way on is Continue.
	var panel := ModalScaffold.build_panel(self, ACCENT, Callable(), Vector2(440, 0))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP)
	margin.add_child(body)
	body.add_child(_label("💀  You died", ACCENT, UITheme.FONT_TITLE))
	body.add_child(_label("Health reached 0 — %d / %d." % [GameState.hp, GameState.max_hp],
		UITheme.TEXT_DIM, UITheme.FONT_TEXT))
	if not lines.is_empty():
		body.add_child(_label("What happened", UITheme.TEXT, UITheme.FONT_LEAD))
		for line in lines:
			body.add_child(_label("→  %s" % line, UITheme.TEXT_DIM, UITheme.FONT_TEXT))
	continue_button = UITheme.confirm_button("Continue", Vector2(150, 34))
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.pressed.connect(press_continue)
	body.add_child(continue_button)

func press_continue() -> void:
	continued.emit()
	close()

func close() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

func _label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 400
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
