extends CanvasLayer

# CHOOSING SOMETHING YOU OWN, IN THE PACK ITSELF (the owner, 18 Oct 2026). A use
# that asks "which of your pieces" — which to destroy (Prepared), which to identify,
# which to charge, which relic to copy — used to open a popup that drew the pack a
# second time as a grid of buttons. It works the way the Bomb does now: the use
# screen gets out of the way, the pack and the relic strip light up the pieces that
# can be chosen, and clicking one IS choosing it. The pieces are where the player
# has been arranging them all run, and that is where they are recognised.
#
# This object is the pick's STATE and its banner — the one line at the bottom of
# the screen saying what the clicks are for — and nothing else. The loot grid and
# the pack strip ask it `candidate_for` / `is_selected` as they draw, and hand a
# click to `choose`; the page owns the redraw (`_refresh_items`), and whoever
# opened the pick gets the answer through `on_done`.
#
# Loaded by path from Overworld2 rather than given a class_name, for the reason the
# use modal is: it is on screen only on demand, and the page's compile should not
# pay for it (test_page_load.gd).
#
# THE CLICK THAT COMPLETES THE COUNT RESOLVES IT, with no confirm after (decision
# #27, the Bomb's rule): choosing is a deliberate act, and a picked piece can be
# clicked again to put it back before the count is met. A pick of "UP TO" N — an
# identify, where fewer is a fine answer — also carries a Done button.

# Everything that can be chosen: pack entries (Dictionaries) and relics (ItemData),
# held by identity.
var candidates: Array = []
# How many the pick wants. Clamped to the candidates at `setup`.
var need: int = 1
# True: exactly `need` (the price of a card). False: up to `need` (Done ends it).
var exact: bool = true
# A pack entry that is not itself a candidate but is the SAME KIND as one stands for
# it — Identify lists one row per type/id, and every copy of an unknown pill is
# that pill.
var by_kind: bool = false
var selected: Array = []
var accent: Color = UITheme.ACCENT
# "destroy", "identify", "charge", "copy" — the verb the banner asks with.
var verb: String = "choose"
# Called once with the chosen things (candidates, never the stand-ins).
var on_done: Callable = Callable()
# What redraws the pack and the strip after a click (the page's `_refresh_items`).
var on_change: Callable = Callable()

var _label: Label = null
var _done_btn: Button = null
var _finished: bool = false

func _init() -> void:
	# Over the page and its floating loot panel, under every modal (120+): the
	# banner is a caption on the page, not a screen of its own.
	layer = UITheme.Layer.PICK_BANNER

func setup(cfg: Dictionary) -> void:
	candidates = (cfg.get("candidates", []) as Array).duplicate()
	exact = bool(cfg.get("exact", true))
	by_kind = bool(cfg.get("by_kind", false))
	verb = String(cfg.get("verb", "choose"))
	accent = cfg.get("accent", UITheme.ACCENT)
	need = clampi(int(cfg.get("count", 1)), 1, maxi(1, candidates.size()))
	_build()

# The candidate `thing` stands for, or null when it cannot be chosen.
func candidate_for(thing):
	for c in candidates:
		if is_same(c, thing):
			return c
	if by_kind and thing is Dictionary:
		for c in candidates:
			if c is Dictionary and _kind(c) == _kind(thing):
				return c
	return null

func is_selected(thing) -> bool:
	var c = candidate_for(thing)
	return c != null and selected.any(func(s): return is_same(s, c))

# A click on `thing` in the pack or the strip.
func choose(thing) -> void:
	if _finished:
		return
	var c = candidate_for(thing)
	if c == null:
		return
	var at: int = -1
	for i in range(selected.size()):
		if is_same(selected[i], c):
			at = i
	if at >= 0:
		selected.remove_at(at)
	elif selected.size() < need:
		selected.append(c)
	if selected.size() >= need:
		finish()
		return
	_update_label()
	if on_change.is_valid():
		on_change.call()

func finish() -> void:
	if _finished:
		return
	_finished = true
	var chosen: Array = selected.duplicate()
	queue_free()
	if on_done.is_valid():
		on_done.call(chosen)

func is_finished() -> bool:
	return _finished

static func _kind(entry: Dictionary) -> String:
	return "%s/%s" % [entry.get("type", ""), entry.get("id", "")]

func _where() -> String:
	var loot: bool = candidates.any(func(c): return c is Dictionary)
	var relic: bool = candidates.any(func(c): return c is ItemData)
	if loot and relic:
		return "in your pack or relics"
	return "among your relics" if relic else "in your pack"

func _prompt() -> String:
	var noun: String = "piece" if need == 1 else "pieces"
	if candidates.all(func(c): return c is ItemData):
		noun = "relic" if need == 1 else "relics"
	return "Click %s%d %s %s to %s." % ["up to " if not exact else "", need, noun, _where(), verb]

func _build() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var panel := PanelContainer.new()
	panel.name = "PickBanner"
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG.lerp(accent, 0.12), 8, 10, 2, accent))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -UITheme.GAP_SECTION
	holder.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	panel.add_child(row)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	_label.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.5))
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)
	if not exact:
		_done_btn = UITheme.confirm_button("Done", Vector2(80, 28))
		_done_btn.pressed.connect(finish)
		row.add_child(_done_btn)
	_update_label()

func _update_label() -> void:
	if _label == null:
		return
	var text: String = _prompt()
	if need > 1:
		text += "  (%d/%d)" % [selected.size(), need]
	_label.text = text
