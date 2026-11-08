class_name CustomizeScreen
extends Control

# CUSTOMIZATION (docs/customization.md; the owner, 8 Nov 2026), off the main menu:
# what the player has earned to look different, and the choice of what to wear.
#
#   Characters     each character's costumes, the ICON and the FULL portrait
#                  chosen separately (a Vampire Survivors costume is both, from
#                  one picture, and shows in both rows);
#   Icons          what stands in for 🗝, ✸ and 🏆 everywhere they are drawn;
#   Title Letters  which earned letters the main menu may spell with, a game at a
#                  time or a letter at a time — refused when what is left could
#                  not spell the title and the subtitle.
#
# Everything here is Cosmetics' state; the screen only shows it and asks it to
# change. A locked look is shown as a "?" with where it comes from, so the screen
# also says what is still to earn.

const TILE := 64
const LETTER_TILE := 40
const TABS := ["Characters", "Icons", "Title Letters"]
const KIND_NAMES := {"key": "Keys", "bomb": "Bombs", "difficulty": "Difficulty (the trophy)"}
const KIND_GLYPHS := {"key": "🗝", "bomb": "✸", "difficulty": "🏆"}

var _tab := 0
var _tab_buttons: Array[Button] = []
var _body: VBoxContainer
var _status: Label

static func open(parent: Node, tab: int = 0) -> CustomizeScreen:
	var s := CustomizeScreen.new()
	s._tab = tab
	parent.add_child(s)
	return s

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell()
	_refresh()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 36
	panel.offset_top = 32
	panel.offset_right = -36
	panel.offset_bottom = -32
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG_DEEP, UITheme.BORDER, 10, 18, 1))
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Customization"
	title.add_theme_font_size_override("font_size", UITheme.FONT_HERO)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	header.add_child(title)
	for i in TABS.size():
		var b := Button.new()
		b.name = "Tab%d" % i
		b.text = TABS[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func() -> void:
			_tab = i
			_refresh())
		header.add_child(b)
		_tab_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "✕  Close"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	_status.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	scroll.add_child(_body)

func _refresh() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match _tab:
		0: _build_characters()
		1: _build_icons()
		_: _build_letters()

func _say(text: String) -> void:
	_status.text = text
	Cosmetics.apply_glyph(_status)

# --- characters -------------------------------------------------------------------

func _build_characters() -> void:
	_say("Costumes are earned as rank-up rewards from the games they come from and the characters from those games. The icon and the full portrait are chosen separately.")
	var roster: Array = Data.all_characters2().filter(func(ch) -> bool:
		return not CosmeticCatalog.costumes_of(ch.id, "icon").is_empty() \
			or not CosmeticCatalog.costumes_of(ch.id, "full").is_empty())
	roster.sort_custom(func(a, b): return a.display_name < b.display_name)
	for ch in roster:
		var block := VBoxContainer.new()
		block.name = "Character_%s" % ch.id
		block.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
		_body.add_child(block)
		block.add_child(_heading(ch.display_name))
		for slot in CosmeticCatalog.SLOTS:
			var row := HFlowContainer.new()
			row.name = "Slot_%s" % slot
			row.add_theme_constant_override("h_separation", UITheme.GAP)
			row.add_theme_constant_override("v_separation", UITheme.GAP)
			block.add_child(row)
			var lbl := _dim("Icon" if slot == "icon" else "Full")
			lbl.custom_minimum_size = Vector2(48, TILE)
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(lbl)
			for t in costume_tiles(ch, slot, TILE, _refresh):
				row.add_child(t)

# --- icons --------------------------------------------------------------------------

func _build_icons() -> void:
	_say("Each stands in for its symbol everywhere it is drawn. A difficulty icon replaces the 🏆 and carries the Fracture number; Risk of Rain 2's changes with the level.")
	for kind in CosmeticCatalog.KINDS:
		var block := VBoxContainer.new()
		block.name = "Kind_%s" % kind
		block.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
		_body.add_child(block)
		block.add_child(_heading(KIND_NAMES[kind]))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", UITheme.GAP)
		row.add_theme_constant_override("v_separation", UITheme.GAP)
		block.add_child(row)
		var glyph: String = KIND_GLYPHS[kind]
		for t in slot_tiles(Cosmetics.icon_slot(kind), null, glyph, "Default — %s" % glyph,
				CosmeticCatalog.icons_of(kind), TILE, _refresh):
			row.add_child(t)

# --- a slot's choices, shared with the character picker ---------------------------
#
# One tile per choice for a slot: the DEFAULT, RANDOM (🎲 — rolled again at the
# start of every run, Cosmetics.roll_random), then every look that fits it. A
# LOCKED look is its own picture as a black silhouette, like the Collection's
# unseen entries, with where it comes from on the hover; a look drawn since it was
# last shown GLOWS once, the way a new title letter does, and is then seen.

# A character's tiles for `slot` (icon or full).
static func costume_tiles(ch: CharacterData, slot: String, side: int, on_change: Callable) -> Array:
	var own: Texture2D = (ch.icon if ch.icon != null else ch.portrait) if slot == "icon" else ch.portrait
	return slot_tiles(Cosmetics.costume_slot(ch.id, slot), own, "", "%s — default" % ch.display_name,
		CosmeticCatalog.costumes_of(ch.id, slot), side, on_change)

static func slot_tiles(slot_key: String, default_tex: Texture2D, default_glyph: String,
		default_tip: String, looks: Array, side: int, on_change: Callable) -> Array:
	var chosen := Cosmetics.choice(slot_key)
	var pick := func(key: String) -> Callable:
		return func() -> void:
			Cosmetics.choose(slot_key, key)
			on_change.call()
	var out: Array = []
	out.append(tile(default_tex, default_glyph, chosen == "", false, false, default_tip,
		pick.call(""), side))
	var rolled: Dictionary = Cosmetics.costume_or_icon(slot_key) if chosen == Cosmetics.RANDOM else {}
	var random_tip := "Random — a different one every run, from the default and every look unlocked here."
	if chosen == Cosmetics.RANDOM:
		random_tip += "\nThis run: %s" % (String(rolled["name"]) if not rolled.is_empty() else "the default")
	var r := tile(null, "🎲", chosen == Cosmetics.RANDOM, false, false, random_tip,
		pick.call(Cosmetics.RANDOM), side)
	r.name = "Random"
	out.append(r)
	for e in looks:
		var key := String(e["key"])
		var locked := not Cosmetics.is_unlocked(key)
		var tip := _look_tip(e, locked)
		var images: Array = e.get("images", [])
		if images.size() > 1:
			tip += "\n" + "\n".join(images.map(func(i): return "%s — Fracture %d–%d" % [i["name"], i["min"], i["max"]]))
		var path := String(e.get("path", "")) if e.has("path") else CosmeticCatalog.image_for(e, 0)
		var t := tile(CosmeticCatalog.texture(path), "", chosen == key, locked,
			Cosmetics.is_new(key), tip, pick.call(key), side)
		t.set_meta("look", key)
		out.append(t)
	return out

# --- title letters ----------------------------------------------------------------

func _build_letters() -> void:
	_say("Switch a game's letters, or single letters, off to keep them out of the main menu's title. Whatever is left has to be able to spell the title and the subtitle.")
	var by_game := {}
	var p := TitleLetters.pool()
	for folder in p:
		for e in p[folder]:
			if TitleLetters.unit_key(e) != String(e["key"]):
				continue
			if not (TitleLetters.is_starter(e) or TitleUnlocks.is_unlocked(String(e["key"]))):
				continue
			(by_game.get_or_add(String(e.get("game", "")), []) as Array).append(e)
	var ids: Array = by_game.keys()
	ids.sort_custom(func(a, b) -> bool:
		if a == TitleLetters.STARTER_GAME or b == TitleLetters.STARTER_GAME:
			return a == TitleLetters.STARTER_GAME
		return _game_name(a) < _game_name(b))
	for g in ids:
		var block := VBoxContainer.new()
		block.name = "Game_%s" % g
		block.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
		_body.add_child(block)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UITheme.GAP)
		block.add_child(head)
		var check := CheckBox.new()
		check.name = "GameToggle"
		check.text = _game_name(g)
		check.button_pressed = Cosmetics.letters_game_on(g)
		check.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
		check.toggled.connect(func(on: bool) -> void:
			if not Cosmetics.set_letters_game(g, on):
				_refused(_game_name(g) + "'s letters")
			_refresh_keep_scroll())
		head.add_child(check)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", UITheme.GAP_TIGHT)
		row.add_theme_constant_override("v_separation", UITheme.GAP_TIGHT)
		block.add_child(row)
		var game_on := Cosmetics.letters_game_on(g)
		var pieces: Array = by_game[g]
		pieces.sort_custom(func(a, b): return _piece_order(a) < _piece_order(b))
		for e in pieces:
			var key := String(e["key"])
			var on := Cosmetics.letter_on(key)
			var t := _tile(TitleLetters.texture(String(e["path"])), "", on and game_on, false,
				_piece_name(e) + ("" if on else " — switched off"),
				func() -> void:
					if not Cosmetics.set_letter(key, not on):
						_refused(_piece_name(e))
					_refresh_keep_scroll(), LETTER_TILE, bool(e.get("pixel", false)))
			if not (on and game_on):
				t.modulate = Color(1, 1, 1, 0.35)
			row.add_child(t)

func _refused(what: String) -> void:
	_say.call_deferred("Can't switch off %s: without it the title or the subtitle would have a letter nothing else can spell." % what)

func _refresh_keep_scroll() -> void:
	var scroll: ScrollContainer = _body.get_parent()
	var v := scroll.scroll_vertical
	var msg := _status.text
	_refresh()
	_status.text = msg
	(func() -> void: scroll.scroll_vertical = v).call_deferred()

# Letters A to Z (a capital before its small letter), then digits, then the rest.
func _piece_order(e: Dictionary) -> String:
	var folder := String(e.get("folder", ""))
	var group := "0" if folder.length() == 1 and folder >= "a" and folder <= "z" \
		else ("1" if folder.length() == 1 else ("3" if folder.begins_with("decor") else "2"))
	return "%s%s%s%s" % [group, folder, "1" if String(e.get("case", "")) == "lower" else "0", e["key"]]

func _piece_name(e: Dictionary) -> String:
	var folder := String(e.get("folder", ""))
	if folder.begins_with("decor"):
		return "decoration"
	if folder.length() == 1:
		var c := String(e.get("case", ""))
		return folder.to_lower() if c == "lower" else folder.to_upper()
	return folder.replace("_", " ")

func _game_name(g: String) -> String:
	var game: GameData = Data.get_game(StringName(g))
	return game.display_name if game != null else g.capitalize()

# --- pieces -------------------------------------------------------------------------

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	l.add_theme_color_override("font_color", UITheme.GOLD)
	return l

func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l

# Where a look comes from, and whether it is still to earn.
static func _look_tip(e: Dictionary, locked: bool) -> String:
	var g: GameData = Data.get_game(StringName(String(e["game"])))
	var game := g.display_name if g != null else String(e["game"])
	var name := String(e["name"])
	if locked:
		return "Locked — %s\nA rank-up reward from %s, or a character from it." % [name, game]
	return "%s — from %s" % [name, game]

func _tile(tex: Texture2D, glyph: String, selected: bool, locked: bool, tip: String,
		on_press: Callable, side: int = TILE, pixel: bool = false) -> Button:
	return tile(tex, glyph, selected, locked, false, tip, on_press, side, pixel)

# `pixel` draws the picture with sharp pixels however it is scaled (a title letter
# the index marks `pixel`: Rogue's, Dungeon Crawl Stone Soup's).
static func tile(tex: Texture2D, glyph: String, selected: bool, locked: bool, new: bool,
		tip: String, on_press: Callable, side: int = TILE, pixel: bool = false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(side, side)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	var box := UITheme.panel_box(UITheme.PANEL, UITheme.GOLD if selected else UITheme.BORDER,
		6, 4, 2 if selected else 1)
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, box)
	if tex != null:
		var inset := maxi(2, side / 16)
		var tr := UITheme.crisp_tex(tex, side - inset * 2, pixel)
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = inset
		tr.offset_top = inset
		tr.offset_right = -inset
		tr.offset_bottom = -inset
		if locked:
			tr.modulate = Color(0, 0, 0, 1)   # the silhouette
		b.add_child(tr)
	else:
		b.text = glyph if not locked else "?"
		b.set_meta("glyph_level", 0)
		b.set_meta("glyph_art_text", glyph)   # a default tile keeps its glyph
		b.add_theme_font_size_override("font_size",
			UITheme.FONT_TITLE if side >= 48 else UITheme.FONT_SUB)
	if locked:
		b.disabled = true
		b.mouse_filter = Control.MOUSE_FILTER_PASS   # the hover still says where it comes from
		return b
	if new:
		# Glows once it is on screen, then it has been seen.
		b.tree_entered.connect(func() -> void:
			Cosmetics.glow(b)
			Cosmetics.mark_seen([String(b.get_meta("look", ""))]), CONNECT_ONE_SHOT)
	b.pressed.connect(on_press)
	return b
