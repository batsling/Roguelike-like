class_name TitleLetters
extends Control

# The main menu's title and subtitle, spelled out of letters cut from real
# roguelikes' logos (tools/logo_letters.py, docs/content-authoring.md "Title
# letters"), each place's game drawn again every time the menu opens.
#
# THE INDEX IS WHAT MAKES IT LINE UP. A cut letter is a PNG with whatever the
# logo drew round it — a glow on every side, a shadow pushed down-left, an eye
# stalk, a knife — so the PNG's own middle is not the letter's. The tool records
# in images2.0/custom/title/index.json where the letter itself sits in each PNG
# (body_center / body_height down, body_center_x / body_width across, all
# fractions of the PNG; line_center, when present, is what sits on the line's
# middle instead of the box's — Uma Musume's dash centres its bar, not the
# sparkles over it), and this lays every piece out by that box: each letter
# is scaled so its own height is the line's (one scale, never width or height
# alone), centred on the line by its own middle, and spaced by its own width.
# Whatever hangs off a letter overflows the line rather than growing it, so a
# title with Repentance's knife I is no taller than one without.
#
# Decorations (decor_left/, decor_right/) stand at either end, one or both sides: a
# right one with no left (Demonic Mahjong's seal) stands at the right alone. A
# PAIR comes from one
# file stem — a crab's two claws, its two leg pairs, Uma Musume's runner and her
# trailing dash — never a claw facing legs. A left one with no right half of its
# own (Darkest Dungeon's torch) stands at the left alone.
#
# ROGUE'S OWN LETTERS ARE THE ONES YOU START WITH; THE LOGOS ARE EARNED (the owner,
# 31 Oct 2026). Every printable character of the IBM PC font Rogue was played in
# (tools/rogue_letters.py, `"game": "rogue"`) is always in the pool; a letter cut
# from a logo joins it once a rank has paid it (RankRewards: each game or
# character rank is a song or a letter, 50/50; TitleUnlocks keeps which). The
# menu spells from `available()`; `pool()` is still every piece, for the tests
# that hold each picture to its box. A Rogue letter matches the CASE of the text
# (`case` in the index) and is drawn with sharp pixels (`pixel`).

const ROOT := "res://images2.0/custom/title/"
const INDEX := ROOT + "index.json"
# The game whose letters are everyone's from the start.
const STARTER_GAME := "rogue"
# A character that is not a letter or a digit, and the folder it is filed under.
# Keep in step with tools/rogue_letters.py's PUNCT.
const PUNCT := {
	"-": "dash", "!": "exclaim", "\"": "quote", "#": "hash", "$": "dollar",
	"%": "percent", "&": "ampersand", "'": "apostrophe", "(": "paren_left",
	")": "paren_right", "*": "asterisk", "+": "plus", ",": "comma",
	".": "period", "/": "slash", ":": "colon", ";": "semicolon", "<": "less",
	"=": "equals", ">": "greater", "?": "question", "@": "at",
	"[": "bracket_left", "\\": "backslash", "]": "bracket_right", "^": "caret",
	"_": "underscore", "`": "backtick", "{": "brace_left", "|": "bar",
	"}": "brace_right", "~": "tilde",
}

# Of the line height: the gap between letters, a space, a decoration's size,
# and the room kept above and below the line so two rows do not touch.
const GAP := 0.06
const SPACE := 0.35
const DECOR_SIZE := 0.9
const PAD := 0.12
# How often a word that takes decorations gets a pair.
const DECOR_CHANCE := 0.5
# A lowercase letter's height, and how far a g or y hangs below the line, of a
# capital's: Rogue's own (7 and 3 of its 10 font pixels), so a logo's a and a
# Rogue a stand the same height side by side.
const X_HEIGHT := 0.7
const DESCENDER := 0.3
# Lowercase letters as tall as a capital, and the ones that hang below the line.
const ASCENDERS := "bdfhklt"
const DESCENDERS := "gjpqy"

# One letter as laid out: its entry, its texture, and where its letter box is.
class Placed:
	var entry: Dictionary
	var rect: TextureRect
	var body: Rect2      # the letter's own box, in `ink`'s coordinates
	var ch := ""         # the character it stands for ("" for a decoration)

var placed: Array[Placed] = []
var line_height := 0.0
# The letters, laid out from x = 0 and centred in this control. This control
# asks for no width of its own, so a title wider than the menu's buttons
# overflows both ways rather than stretching the button column to match.
var ink := Control.new()
var ink_width := 0.0
# A space's width, of the line height (SPACE unless make() was given another).
var space := SPACE
# The gap between letters, of the line height (GAP unless make() was given another).
var gap := GAP

func _init() -> void:
	ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ink)
	resized.connect(_centre)

func _centre() -> void:
	ink.position = Vector2((size.x - ink_width) * 0.5, size.y * 0.5 - line_height * 0.5)

static var _pool_cache: Dictionary = {}

# Every piece by folder ("a", "dash", "decor_left"…), from the tool's index.
static func pool() -> Dictionary:
	if not _pool_cache.is_empty():
		return _pool_cache
	var text := FileAccess.get_file_as_string(INDEX)
	var idx = JSON.parse_string(text) if text != "" else null
	if not (idx is Dictionary):
		return {}
	for rel in idx:
		var e: Dictionary = (idx[rel] as Dictionary).duplicate()
		e["key"] = rel
		e["path"] = ROOT + rel
		e["folder"] = rel.get_base_dir()
		e["stem"] = rel.get_file().get_basename()
		(_pool_cache.get_or_add(e["folder"], []) as Array).append(e)
	for k in _pool_cache:
		(_pool_cache[k] as Array).sort_custom(func(x, y): return x["path"] < y["path"])
	return _pool_cache

static func _folder_for(ch: String) -> String:
	return PUNCT.get(ch, ch.to_lower())

# --- what can be earned, and what has been ------------------------------------

# Whether `e` is one of Rogue's, which everyone has.
static func is_starter(e: Dictionary) -> bool:
	return String(e.get("game", "")) == STARTER_GAME

# The key a piece is EARNED under: its own, except a right decoration with a left
# half of the same stem, which comes with that left (a pair is earned as one). A
# right decoration standing alone (Demonic Mahjong's seal) is a unit of its own.
static func unit_key(e: Dictionary) -> String:
	if String(e.get("folder", "")) == "decor_right":
		var stem := String(e["stem"])
		for l in pool().get("decor_left", []):
			if String(l["stem"]) == stem:
				return String(l["key"])
	return String(e["key"])

# Every piece a rank can pay, by its index key ("h/hades.png"): every cut letter,
# and each decoration PAIR as its left half (the right comes with it). Sorted, so a
# draw over it is repeatable.
static func units() -> Array:
	var out: Array = []
	var p := pool()
	for folder in p:
		for e in p[folder]:
			if not is_starter(e) and unit_key(e) == String(e["key"]):
				out.append(String(e["key"]))
	out.sort()
	return out

# The pieces `game`'s own ranks pay out of: its logo's.
static func units_of(game: StringName) -> Array:
	var out: Array = []
	var p := pool()
	for folder in p:
		for e in p[folder]:
			if String(e.get("game", "")) == String(game) and not is_starter(e) \
					and unit_key(e) == String(e["key"]):
				out.append(String(e["key"]))
	out.sort()
	return out

# The pool the menu spells from: Rogue's letters, and every piece that has been
# earned (TitleUnlocks). A decoration's right half is earned with its left.
static func available() -> Dictionary:
	var p := pool()
	var tu: Node = Engine.get_main_loop().root.get_node_or_null(^"TitleUnlocks") \
		if Engine.get_main_loop() is SceneTree else null
	var out := {}
	for folder in p:
		var keep: Array = []
		for e in p[folder]:
			var key: String = unit_key(e)
			if is_starter(e) or (tu != null and tu.is_unlocked(key)):
				keep.append(e)
		if not keep.is_empty():
			out[folder] = keep
	return out

# The pieces for `text`, one per character (a space is an empty dictionary).
# Prefers a game not yet used in this word, so a title is a real mix.
static func pick(text: String, rng: RandomNumberGenerator, from: Dictionary = {}) -> Array:
	var p := from if not from.is_empty() else pool()
	var used := {}
	var out := []
	for ch in text:
		if ch == " ":
			out.append({})
			continue
		# A piece with a `case` (Rogue's) only stands for its own case of a letter.
		var want_case: String = "" if ch.to_upper() == ch.to_lower() \
			else ("upper" if ch == ch.to_upper() else "lower")
		var opts: Array = (p.get(_folder_for(ch), []) as Array).filter(
			func(o): return not o.has("case") or String(o["case"]) == want_case)
		# A capital place takes a capital SHAPE when there is one: Darkest
		# Dungeon's r as the title's R read as a T (the owner, 31 Oct 2026). A
		# lowercase shape stands there only when nothing else can.
		if want_case == "upper":
			var caps := opts.filter(func(o): return String(o.get("form", "")) != "lower")
			if not caps.is_empty():
				opts = caps
		if opts.is_empty():
			out.append({"missing": ch})
			continue
		var fresh := opts.filter(func(o): return not used.has(o["game"]))
		var choose: Array = fresh if not fresh.is_empty() else opts
		var e: Dictionary = choose[rng.randi() % choose.size()]
		used[e["game"]] = true
		out.append(e)
	return out

# A matching left and right decoration, a left one alone when it has no right half
# (Darkest Dungeon's torch), a right one alone when it has no left (Demonic
# Mahjong's seal: then the left is {}), or [] for none. Each decoration belongs
# to one row: the title's, or the subtitle's when the index marks it `subtitle`
# (the crab's legs, the owner, 1 Nov 2026), so `subtitle` picks from those alone.
static func pick_decor(rng: RandomNumberGenerator, from: Dictionary = {}, subtitle: bool = false) -> Array:
	var p := from if not from.is_empty() else pool()
	var row := func(e): return bool(e.get("subtitle", false)) == subtitle
	var right := {}
	for e in p.get("decor_right", []):
		right[e["stem"]] = e
	# one choice per decoration: each left (with its right, if it has one), and
	# each right that has no left at all
	var choices: Array = (p.get("decor_left", []) as Array).filter(row)
	for e in (p.get("decor_right", []) as Array).filter(row):
		if unit_key(e) == String(e["key"]):
			choices.append(e)
	if choices.is_empty():
		return []
	var pick_: Dictionary = choices[rng.randi() % choices.size()]
	if String(pick_["folder"]) == "decor_right":
		return [{}, pick_]
	return [pick_, right[pick_["stem"]]] if right.has(pick_["stem"]) else [pick_]

static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	# Not imported yet (a fresh checkout before the editor has scanned): read the
	# PNG straight off disk, so the menu still has its title.
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null

# How tall a logo letter stands for `ch`, and where its top is, both of the line
# height (the line runs from the capitals' top, 0, to the baseline, 1). THE
# TEXT'S CASE DECIDES, not the logo's (the owner, 31 Oct 2026): a capital place
# is the whole line whatever stands in it. In a lowercase place a CAPITAL is
# drawn as a small cap, the x-height on the baseline, even for a k or an l (a
# full-height capital mid-word read as a capital). A lowercase-SHAPED letter
# (`form` in the index) is drawn as one: the x-height, the whole line for a tall
# one (b d f h k l t, and an i with its dot), its tail below the line for a g j
# p q y. Rogue's
# letters (`case`) are drawn in a shared band already and keep it.
#
# A piece's `size` (from its config: the owner's eye, as Dead Cells' thin letters
# drawn a little bigger) then grows or shrinks that on the baseline, and its
# `drop` moves it down (Balatro's A sat high).
static func _size(e: Dictionary, ch: String) -> Vector2:
	var c := _case_size(e, ch)
	var f := float(e.get("size", 1.0))
	return Vector2(c.x * f, 1.0 - (1.0 - c.y) * f + float(e.get("drop", 0.0)))

static func _case_size(e: Dictionary, ch: String) -> Vector2:
	if ch == "" or e.has("case") or ch == ch.to_upper():
		return Vector2(1.0, 0.0)
	if String(e.get("form", "")) != "lower":
		return Vector2(X_HEIGHT, 1.0 - X_HEIGHT)  # a capital: small caps, even for a k
	if ASCENDERS.contains(ch) or ch == "i":
		return Vector2(1.0, 0.0)
	if DESCENDERS.contains(ch):
		return Vector2(X_HEIGHT + DESCENDER, 1.0 - X_HEIGHT)
	return Vector2(X_HEIGHT, 1.0 - X_HEIGHT)

# A word laid out at `height` px a letter, no wider than `max_width`.
static func make(text: String, height: float, rng: RandomNumberGenerator,
		decorated: bool = false, max_width: float = 0.0, word_gap: float = SPACE,
		letter_gap: float = GAP, subtitle: bool = false) -> TitleLetters:
	var w := TitleLetters.new()
	w.space = word_gap
	w.gap = letter_gap
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var from := available()
	var pieces := pick(text, rng, from)
	var decor := pick_decor(rng, from, subtitle) if decorated and rng.randf() < DECOR_CHANCE else []
	w._lay_out(pieces, decor, height, text)
	if max_width > 0.0 and w.ink_width > max_width:
		w._lay_out(pieces, decor, height * max_width / w.ink_width, text)
	return w

# `text` is what `pieces` spell, one character each: its case sizes them (_size).
func _lay_out(pieces: Array, decor: Array, height: float, text: String = "") -> void:
	for c in ink.get_children():
		ink.remove_child(c)
		c.queue_free()
	placed.clear()
	line_height = height
	var x := 0.0
	var seq: Array = []
	if not decor.is_empty() and not (decor[0] as Dictionary).is_empty():
		seq.append([decor[0], true, ""])
	for j in pieces.size():
		seq.append([pieces[j], false, text[j] if j < text.length() else ""])
	if decor.size() > 1 and not (decor[1] as Dictionary).is_empty():
		seq.append([decor[1], true, ""])
	for i in seq.size():
		var e: Dictionary = seq[i][0]
		var is_decor: bool = seq[i][1]
		if i > 0:
			x += height * gap
		if e.is_empty() or e.has("missing"):
			x += height * space
			continue
		var tex := texture(e["path"])
		if tex == null:
			x += height * SPACE
			continue
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var bh := float(e.get("body_height", 1.0))
		var bw := float(e.get("body_width", 1.0))
		# a decoration is centred at DECOR_SIZE; a letter is sized by its case
		var size_top := Vector2(DECOR_SIZE, 0.5 - DECOR_SIZE * 0.5) if is_decor \
			else _size(e, String(seq[i][2]))
		var target := height * size_top.x
		# room kept clear either side of it (Dead Cells' flame), of the line
		var pad := height * float(e.get("pad", 0.0))
		x += pad
		var s := target / (th * bh)          # one scale: the letter's own height to the line's
		var slot := tw * s * bw              # the letter's own width
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bool(e.get("pixel", false)):
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.size = Vector2(tw * s, th * s)
		# its box's top at size_top.y; a decoration's line_center (Uma Musume's
		# dash: its bar) sits on the line's middle instead
		var bc := float(e.get("body_center", 0.5))
		var top := height * size_top.y - (bc - bh * 0.5) * th * s
		if is_decor and e.has("line_center"):
			top = height * 0.5 - float(e["line_center"]) * th * s
		if is_decor:
			# never down into the row below: Darkest Dungeon's torch hangs its
			# handle far under the line, and covered the subtitle's first letters
			top = minf(top, height * (1.0 + PAD) - th * s)
		rect.position = Vector2(x + slot * 0.5 - float(e.get("body_center_x", 0.5)) * tw * s, top)
		ink.add_child(rect)
		var p := Placed.new()
		p.entry = e
		p.rect = rect
		p.body = Rect2(x, height * size_top.y, slot, target)
		p.ch = String(seq[i][2])
		placed.append(p)
		x += pad
		x += slot
	ink_width = x
	ink.size = Vector2(x, height)
	custom_minimum_size = Vector2(0.0, height * (1.0 + 2.0 * PAD))
	size = Vector2(x, custom_minimum_size.y)
	_centre()
