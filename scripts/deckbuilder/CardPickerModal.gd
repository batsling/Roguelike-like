class_name CardPickerModal
extends Control

# Reusable mid-cast picker. The caller hands in a list of candidate
# CardInstances, an exact required count (min == max for now since no
# shipped card needs "up to N"), an accent colour for the panel, and a
# callback. The modal lets the player click cards to toggle selection,
# enables Confirm only when the count requirement is met, and fires
# the callback with the selected instances on confirm.
#
# Display-only — selection state lives inside this node and is handed
# back to the caller exactly once. Card mutations (discard / exhaust /
# upgrade / move) are the caller's responsibility.
#
# Usage:
#   var modal := CardPickerModal.new()
#   add_child(modal)
#   modal.show_picker({
#       "title": "Discard a card",
#       "candidates": hand,
#       "count": 1,
#       "accent": Color(0.95, 0.70, 0.30),  # discard orange
#       "confirm_label": "Discard",
#       "on_picked": Callable(self, "_on_picks"),
#   })

const CardViewScript := preload("res://scripts/deckbuilder/CardView.gd")

var _candidates: Array = []
var _selected: Array = []       # Array[CardInstance] in click order
var _required: int = 1
var _on_picked: Callable
var _confirm_btn: Button
var _counter_label: Label
var _views: Array = []          # Array[CardView] parallel to _candidates

func show_picker(opts: Dictionary) -> void:
	_candidates = opts.get("candidates", []).duplicate()
	_required = int(opts.get("count", 1))
	_on_picked = opts.get("on_picked", Callable())
	var title: String = String(opts.get("title", "Choose a card"))
	var accent: Color = opts.get("accent", Color(0.9, 0.9, 0.95))
	var confirm_label: String = String(opts.get("confirm_label", "Confirm"))
	_build(title, accent, confirm_label)

func _build(title: String, accent: Color, confirm_label: String) -> void:
	# _build runs after the caller has already add_child()ed this modal, and
	# set_anchors_preset on an in-tree Control KEEPS its current (zero) rect —
	# the offsets variant actually stretches it, so the backdrop dims the whole
	# screen and the panel centers instead of clipping at the origin.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# No dismiss callback: clicking outside must NOT close this modal because
	# the player has to make a choice. The blocker just swallows the click.
	# (Future "optional skip" would pass a dismiss Callable here.)
	var panel := ModalScaffold.build_panel(self, accent)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = title
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", accent)
	vbox.add_child(header)

	_counter_label = Label.new()
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_font_size_override("font_size", 12)
	_counter_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
	vbox.add_child(_counter_label)

	if _candidates.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(no eligible cards)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vbox.add_child(empty_lbl)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(880, 420)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(scroll)

		var grid := HFlowContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)

		for inst in _candidates:
			var view := CardViewScript.new()
			grid.add_child(view)
			view.setup(inst)
			view.set_enabled(true)
			view.play_requested.connect(_on_card_clicked.bind(view))
			_views.append(view)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	_confirm_btn = Button.new()
	_confirm_btn.text = confirm_label
	_confirm_btn.custom_minimum_size = Vector2(160, 36)
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	_refresh()

func _on_card_clicked(card: CardInstance, view: Control) -> void:
	if _selected.has(card):
		_selected.erase(card)
		view.set_selected(false)
	else:
		# Auto-evict the oldest selection when the picker is at the cap
		# rather than silently ignoring the click — feels less broken.
		if _selected.size() >= _required and _required > 0:
			var dropped: CardInstance = _selected.pop_front()
			for v in _views:
				if v.card == dropped:
					v.set_selected(false)
					break
		_selected.append(card)
		view.set_selected(true)
	_refresh()

func _refresh() -> void:
	_counter_label.text = "%d / %d selected" % [_selected.size(), _required]
	_confirm_btn.disabled = _selected.size() != _required or _required == 0

func _on_confirm() -> void:
	var picks: Array = _selected.duplicate()
	if _on_picked.is_valid():
		_on_picked.call(picks)
	queue_free()
