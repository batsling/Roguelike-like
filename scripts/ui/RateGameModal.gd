class_name RateGameModal
extends Control

# Mandatory post-victory rating prompt. Shown right after the "Play the real
# game" verification screen each time a game is beaten. The player must pick a
# whole-number score (1-10) AND write at least some notes before Confirm
# unlocks — there's no skip. When the game was rated on a previous run the
# fields come in pre-filled so the player updates rather than starts over.
#
# Built entirely in code (no scene dependency) and runs PROCESS_MODE_ALWAYS so
# it keeps working if the tree is paused behind it. Emits `submitted(score,
# notes)`; the caller is responsible for persisting via TierList and freeing
# this modal.

signal submitted(score: int, notes: String)

const ACCENT := Color(1.0, 0.7, 0.25)

var _game_id: StringName = &""
var _score: int = 0
var _notes_edit: TextEdit
var _confirm_btn: Button
var _score_label: Label
var _score_buttons: Array[Button] = []

# Deferred-build state. The caller builds the modal, wires its `submitted`
# signal, and only then adds it to the tree, so setup() can run before we're
# in the tree. Centring the panel needs a valid viewport size, so we stash the
# inputs and defer the actual build to _ready() (guaranteed in-tree, full-rect).
# Building eagerly here used to lay the panel out against a zero-size rect,
# which left it stranded in the top-left corner.
var _gd: GameData = null
var _existing: Dictionary = {}
var _built: bool = false

# Safe to call before or after the node enters the tree. `gd` may be null (we
# fall back to the id).
func setup(game_id: StringName, gd: GameData) -> void:
	_game_id = game_id
	_gd = gd
	_existing = TierList.get_rating(game_id)
	if not _existing.is_empty():
		_score = int(_existing.get("score", 0))
	if is_inside_tree() and not _built:
		_built = true
		_build_ui(_gd, _existing)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Build now if setup() ran before we entered the tree.
	if not _built:
		_built = true
		_build_ui(_gd, _existing)

func _build_ui(gd: GameData, existing: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Centre the panel with an absolute position from the viewport size — the
	# same approach RewardScreen/CardRewardScreen use. We're guaranteed to be in
	# the tree here (build is deferred to _ready), so get_viewport_rect() is
	# valid. Anchors against our own rect proved fragile when this modal was
	# built before being sized, which dumped the panel in the top-left corner.
	var panel_size := Vector2(600, 500)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	panel.position = (get_viewport_rect().size - panel_size) / 2.0
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var game_name := String(_game_id)
	if gd != null:
		game_name = gd.display_name

	var title := Label.new()
	title.text = ("Update your rating" if not existing.is_empty() else "Rate this game")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = game_name
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	vbox.add_child(subtitle)

	# Optional cover so the player knows which game they're scoring.
	if gd != null and gd.cover_image != null:
		var cover := TextureRect.new()
		cover.texture = gd.cover_image
		cover.custom_minimum_size = Vector2(0, 120)
		cover.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(cover)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_score_label)

	# 1-10 as ten toggle-ish buttons.
	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 4)
	vbox.add_child(score_row)
	for n in range(1, 11):
		var b := Button.new()
		b.text = str(n)
		b.custom_minimum_size = Vector2(44, 40)
		b.toggle_mode = true
		b.pressed.connect(_on_score_pressed.bind(n))
		score_row.add_child(b)
		_score_buttons.append(b)

	var notes_label := Label.new()
	notes_label.text = "Notes (required)"
	notes_label.add_theme_font_size_override("font_size", 14)
	notes_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	vbox.add_child(notes_label)

	_notes_edit = TextEdit.new()
	_notes_edit.custom_minimum_size = Vector2(0, 120)
	_notes_edit.placeholder_text = "What did you think?"
	_notes_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not existing.is_empty():
		_notes_edit.text = String(existing.get("notes", ""))
	_notes_edit.text_changed.connect(_update_confirm_enabled)
	vbox.add_child(_notes_edit)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.custom_minimum_size = Vector2(0, 44)
	_confirm_btn.pressed.connect(_on_confirm)
	vbox.add_child(_confirm_btn)

	_refresh_score_buttons()
	_update_confirm_enabled()

func _on_score_pressed(n: int) -> void:
	_score = n
	_refresh_score_buttons()
	_update_confirm_enabled()

func _refresh_score_buttons() -> void:
	for i in _score_buttons.size():
		_score_buttons[i].button_pressed = (i + 1 == _score)
	if _score >= 1:
		_score_label.text = "Score: %d / 10" % _score
		_score_label.add_theme_color_override("font_color", ACCENT)
	else:
		_score_label.text = "Pick a score (1-10)"
		_score_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))

func _update_confirm_enabled(_unused := "") -> void:
	var has_notes := _notes_edit != null and _notes_edit.text.strip_edges() != ""
	_confirm_btn.disabled = not (_score >= 1 and has_notes)

func _on_confirm() -> void:
	if _score < 1 or _notes_edit.text.strip_edges() == "":
		return
	emit_signal("submitted", _score, _notes_edit.text.strip_edges())
