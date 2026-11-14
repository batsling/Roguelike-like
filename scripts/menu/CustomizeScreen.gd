class_name CustomizeScreen
extends Control

# CUSTOMIZATION (docs/customization.md; the owner, 8 Nov 2026), off the main menu:
# what the player has earned to look different, and the choice of what to wear.
#
#   Characters     each character's costumes, the ICON and the FULL portrait
#                  chosen separately (a Vampire Survivors costume is both, from
#                  one picture, and shows in both rows);
#   Icons          what stands in for 🗝, ✸, 🏆, 🍀, 🎁, ♥, ⚔ (as damage) and ◉
#                  everywhere they are drawn;
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
const KIND_NAMES := {"key": "Keys", "bomb": "Bombs", "difficulty": "Difficulty (the trophy)",
	"luck": "Luck", "chest": "Chests", "health": "Health", "damage": "Damage", "gold": "Gold",
	"shield": "Shields", "hunger": "Hunger"}
const KIND_GLYPHS := {"key": "🗝", "bomb": "✸", "difficulty": "🏆", "luck": "🍀", "chest": "🎁",
	"health": "♥", "damage": "⚔", "gold": "◉", "shield": "🛡", "hunger": "🍗"}

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
	_say("Each stands in for its symbol everywhere it is drawn. A difficulty icon replaces the 🏆 and carries the Fracture number; Risk of Rain 2's changes with the level. A chest icon replaces the 🎁; a set of several changes with the chest's size. A Health icon is your heart and every enemy's.")
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
		if CosmeticCatalog.icons_of(kind).is_empty():
			var none := _dim("No icons to earn yet.")
			none.custom_minimum_size = Vector2(0, TILE)
			none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(none)

# --- a slot's choices, shared with the character picker ---------------------------
#
# One tile per choice for a slot: RANDOM first (🎲 — rolled again at the start of
# every run, Cosmetics.roll_random), the DEFAULT, then every look that fits it. A
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
	var rolled: Dictionary = Cosmetics.costume_or_icon(slot_key) if chosen == Cosmetics.RANDOM else {}
	var random_tip := "Random — a different one every run, from the default and every look unlocked here."
	if chosen == Cosmetics.RANDOM:
		random_tip += "\nThis run: %s" % (String(rolled["name"]) if not rolled.is_empty() else "the default")
	var r := tile(null, "🎲", chosen == Cosmetics.RANDOM, false, false, random_tip,
		pick.call(Cosmetics.RANDOM), side)
	r.name = "Random"
	# RANDOM IS ALL THE WAY ON THE LEFT (the owner, 12 Nov 2026), then the default,
	# then every look. It was second, between the default and the looks.
	out.append(r)
	var d := tile(default_tex, default_glyph, chosen == "", false, false, default_tip,
		pick.call(""), side)
	d.name = "Default"
	out.append(d)
	for e in looks:
		var key := String(e["key"])
		var locked := not Cosmetics.is_unlocked(key)
		var tip := _look_tip(e, locked)
		var images: Array = e.get("images", [])
		if images.size() > 1:
			tip += "\n" + "\n".join(images.map(func(i): return "%s — %s" % [i["name"], CosmeticCatalog.range_text(e, i)]))
		var path := String(e.get("path", "")) if e.has("path") else CosmeticCatalog.image_for(e, 0)
		var t := tile(CosmeticCatalog.texture(path), "", chosen == key, locked,
			Cosmetics.is_new(key), tip, pick.call(key), side)
		# A SET OF SEVERAL ICONS SHOWS ALL OF THEM ON THE HOVER (the owner, 12 Nov
		# 2026): the tile has room for one picture, so a set (Risk of Rain 2's three
		# difficulties, Enter the Gungeon's four chests) would otherwise keep the
		# rest to itself until it was worn and met in a run.
		if images.size() > 1:
			HoverCard.attach(t, set_hover(e, locked))
			t.tooltip_text = tip   # the plain words stay whole for whoever reads them
		t.set_meta("look", key)
		out.append(t)
	return out

# The hover of an icon SET: every picture in it, each over what it is and when it
# is the one drawn. A locked set is silhouettes, like its tile.
static func set_hover(e: Dictionary, locked: bool) -> Dictionary:
	var g: GameData = Data.get_game(StringName(String(e["game"])))
	var game := g.display_name if g != null else String(e["game"])
	var gallery: Array = []
	for i in e.get("images", []):
		# Slay the Spire's Small Chest IS the Small chest: said once.
		var what := String(i["name"])
		var when := CosmeticCatalog.range_text(e, i)
		gallery.append({"art": CosmeticCatalog.texture(String(i["path"])), "dark": locked,
			"text": what if what == when else "%s\n%s" % [what, when]})
	var chest: bool = String(e.get("kind", "")) == "chest"
	return {
		"title": ("Locked — %s" % game) if locked else game,
		"accent": UITheme.TEXT_DIM if locked else UITheme.GOLD,
		"subtitle": "%d icons, one unlock" % gallery.size(),
		"gallery": gallery,
		"lines": ["The chest's size picks the picture. A boss's chest is the Boss Chest, or the highest one where there is none." if chest
			else "The run's Fracture picks the picture."],
		"note": ("A rank-up reward from %s, or a character from it." % game) if locked else "",
	}

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
	# BUILT A SLICE A FRAME, NOT ALL AT ONCE (the owner, 11 Nov 2026: "after
	# clicking the title letters tab it lagged a lot"). With every letter earned
	# this tab is 609 tiles, and each one's picture is loaded the first time it is
	# shown: measured, 2.6 s inside the click that opened the tab, with the screen
	# frozen on the tab before it. The work is the same; it is spread out. The
	# first slice is built here, inside the click, so the tab is never empty, and
	# the rest follows a few milliseconds a frame (`_build_letters_rest`).
	_letter_tiles.clear()
	_letter_checks.clear()
	_letters_gen += 1
	var todo: Array = []
	for g in ids:
		var pieces: Array = by_game[g]
		pieces.sort_custom(func(a, b): return _piece_order(a) < _piece_order(b))
		todo.append({"game": g, "pieces": pieces, "next": 0, "row": null})
	_letters_todo = todo
	# The pictures load on a thread while the tiles are built: of the 2.6 s, the
	# loading was most of it and building 609 buttons the rest.
	var paths: Array = []
	for job in todo:
		for e in job["pieces"]:
			paths.append(String(e["path"]))
	TitleLetters.request(paths)
	_build_letters_slice(LETTERS_FIRST_SLICE_MS, true)
	if not _letters_todo.is_empty() and is_inside_tree():
		_build_letters_rest(_letters_gen)

# How long one slice may build for. The first is inside the click and is kept
# short enough to feel like a click; the rest are a part of a frame each.
const LETTERS_FIRST_SLICE_MS := 12.0
const LETTERS_SLICE_MS := 10.0
var _letters_todo: Array = []
var _letters_gen: int = 0
# key -> {"tile": Button, "entry": Dictionary} and game -> CheckBox, so a switch
# repaints what is on screen instead of building all of it again.
var _letter_tiles: Dictionary = {}
var _letter_checks: Dictionary = {}

func _build_letters_rest(gen: int) -> void:
	while is_inside_tree() and gen == _letters_gen and _tab == 2 and not _letters_todo.is_empty():
		await get_tree().process_frame
		if not is_inside_tree() or gen != _letters_gen or _tab != 2:
			return
		_build_letters_slice(LETTERS_SLICE_MS)

# Whether every tile of the tab is built. Public so a test can wait for it.
func letters_built() -> bool:
	return _letters_todo.is_empty()

# Build tiles until `budget_ms` has gone, at least one. Always finishes the tile
# it is on; a game's heading and row are made with its first tile.
#
# `wait` lets it sit on a picture that is still loading. The first slice does (the
# tab must not open empty); the rest stop at one that is not in yet and come back
# next frame, so a slow disk costs time and never a frozen screen.
func _build_letters_slice(budget_ms: float, wait: bool = false) -> void:
	var start: int = Time.get_ticks_usec()
	while not _letters_todo.is_empty():
		var job: Dictionary = _letters_todo[0]
		var g: String = String(job["game"])
		if job["row"] == null:
			job["row"] = _letters_block(g)
		var pieces: Array = job["pieces"]
		var i: int = int(job["next"])
		if i < pieces.size() and not wait \
				and not TitleLetters.is_loaded(String(pieces[i]["path"])):
			var waiting: Node = (job["row"] as Control).get_parent()
			if waiting.get_parent() == null:
				_body.add_child(waiting)
			return
		if i < pieces.size():
			(job["row"] as Control).add_child(_letter_tile(pieces[i]))
			job["next"] = i + 1
		var done: bool = int(job["next"]) >= pieces.size()
		var out_of_time: bool = (Time.get_ticks_usec() - start) / 1000.0 >= budget_ms
		# A GAME'S BLOCK GOES ON THE PAGE WHOLE where it can: a tile added to a row
		# that is not in the tree yet costs nothing to lay out, where one added to a
		# row on screen re-sorts the page. It is put up early only when the slice
		# runs out part-way through it, so a slice always shows what it built.
		if done or out_of_time:
			var block: Node = (job["row"] as Control).get_parent()
			if block.get_parent() == null:
				_body.add_child(block)
		if done:
			_letters_todo.pop_front()
		if out_of_time:
			return

# One game's heading (its checkbox) and the row its letters go in.
func _letters_block(g: String) -> Control:
	var block := VBoxContainer.new()
	block.name = "Game_%s" % g
	block.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
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
		_sync_letters())
	head.add_child(check)
	_letter_checks[g] = check
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITheme.GAP_TIGHT)
	row.add_theme_constant_override("v_separation", UITheme.GAP_TIGHT)
	block.add_child(row)
	return row

func _letter_tile(e: Dictionary) -> Button:
	var key := String(e["key"])
	# The press reads the switch as it stands, not as it stood when the tile was
	# built: the tile outlives the switch now.
	var t := _tile(TitleLetters.texture(String(e["path"])), "", false, false, "",
		func() -> void:
			if not Cosmetics.set_letter(key, not Cosmetics.letter_on(key)):
				_refused(_piece_name(e))
			_sync_letters(), LETTER_TILE, bool(e.get("pixel", false)))
	_letter_tiles[key] = {"tile": t, "entry": e}
	_paint_letter(t, e)
	return t

# A tile as its switches stand: ringed and bright when it is in the title's pool,
# dim when it or its whole game is switched off.
func _paint_letter(t: Button, e: Dictionary) -> void:
	var key := String(e["key"])
	var on: bool = Cosmetics.letter_on(key)
	var lit: bool = on and Cosmetics.letters_game_on(String(e.get("game", "")))
	var box := UITheme.panel_box(UITheme.PANEL, UITheme.GOLD if lit else UITheme.BORDER,
		6, 4, 2 if lit else 1)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.add_theme_stylebox_override(st, box)
	t.tooltip_text = _piece_name(e) + ("" if on else " — switched off")
	t.modulate = Color.WHITE if lit else Color(1, 1, 1, 0.35)

# Repaint every tile and checkbox on the tab from the switches. A switch used to
# tear the whole tab down and build it again (150 ms, and the scroll put back by
# hand); nothing about a switch changes WHICH tiles there are.
func _sync_letters() -> void:
	for key in _letter_tiles:
		var row: Dictionary = _letter_tiles[key]
		if is_instance_valid(row["tile"]):
			_paint_letter(row["tile"], row["entry"])
	for g in _letter_checks:
		var check: CheckBox = _letter_checks[g]
		if is_instance_valid(check):
			check.set_pressed_no_signal(Cosmetics.letters_game_on(String(g)))

func _refused(what: String) -> void:
	_say.call_deferred("Can't switch off %s: without it the title or the subtitle would have a letter nothing else can spell." % what)

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
	# A HoverButton, so a tile's hover is the game's own card (HoverCard) and a set
	# of several icons can show all of them (set_hover).
	var b: Button = HoverButton.new()
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
		# A look much bigger than its tile (a 330px icon in 64px) goes through its
		# mipmaps rather than being point-shrunk (UITheme.fit_art).
		if not pixel and maxi(tex.get_width(), tex.get_height()) > (side - inset * 2) * 2:
			tr.texture = UITheme.smooth_copy(tex)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
