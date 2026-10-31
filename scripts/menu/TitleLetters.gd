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
# Decorations (decor_left/, decor_right/) stand at either end as a PAIR from one
# file stem — a crab's two claws, its two leg pairs, Uma Musume's runner and her
# trailing dash — never a claw facing legs.
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

# One letter as laid out: its entry, its texture, and where its letter box is.
class Placed:
	var entry: Dictionary
	var rect: TextureRect
	var body: Rect2      # the letter's own box, in `ink`'s coordinates

var placed: Array[Placed] = []
var line_height := 0.0
# The letters, laid out from x = 0 and centred in this control. This control
# asks for no width of its own, so a title wider than the menu's buttons
# overflows both ways rather than stretching the button column to match.
var ink := Control.new()
var ink_width := 0.0
# A space's width, of the line height (SPACE unless make() was given another).
var space := SPACE

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

# Every piece a rank can pay, by its index key ("h/hades.png"): every cut letter,
# and each decoration PAIR as its left half (the right comes with it). Sorted, so a
# draw over it is repeatable.
static func units() -> Array:
	var out: Array = []
	var p := pool()
	for folder in p:
		if folder == "decor_right":
			continue
		for e in p[folder]:
			if not is_starter(e):
				out.append(String(e["key"]))
	out.sort()
	return out

# The pieces `game`'s own ranks pay out of: its logo's.
static func units_of(game: StringName) -> Array:
	var out: Array = []
	var p := pool()
	for folder in p:
		if folder == "decor_right":
			continue
		for e in p[folder]:
			if String(e.get("game", "")) == String(game) and not is_starter(e):
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
			var key: String = String(e["key"])
			if folder == "decor_right":
				key = "decor_left/" + String(e["key"]).get_file()
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
		if opts.is_empty():
			out.append({"missing": ch})
			continue
		var fresh := opts.filter(func(o): return not used.has(o["game"]))
		var choose: Array = fresh if not fresh.is_empty() else opts
		var e: Dictionary = choose[rng.randi() % choose.size()]
		used[e["game"]] = true
		out.append(e)
	return out

# A matching left and right decoration, or [] for none.
static func pick_decor(rng: RandomNumberGenerator, from: Dictionary = {}) -> Array:
	var p := from if not from.is_empty() else pool()
	var right := {}
	for e in p.get("decor_right", []):
		right[e["stem"]] = e
	var pairs := (p.get("decor_left", []) as Array).filter(func(e): return right.has(e["stem"]))
	if pairs.is_empty():
		return []
	var left: Dictionary = pairs[rng.randi() % pairs.size()]
	return [left, right[left["stem"]]]

static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	# Not imported yet (a fresh checkout before the editor has scanned): read the
	# PNG straight off disk, so the menu still has its title.
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null

# A word laid out at `height` px a letter, no wider than `max_width`.
static func make(text: String, height: float, rng: RandomNumberGenerator,
		decorated: bool = false, max_width: float = 0.0, word_gap: float = SPACE) -> TitleLetters:
	var w := TitleLetters.new()
	w.space = word_gap
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var from := available()
	var pieces := pick(text, rng, from)
	var decor := pick_decor(rng, from) if decorated and rng.randf() < DECOR_CHANCE else []
	w._lay_out(pieces, decor, height)
	if max_width > 0.0 and w.ink_width > max_width:
		w._lay_out(pieces, decor, height * max_width / w.ink_width)
	return w

func _lay_out(pieces: Array, decor: Array, height: float) -> void:
	for c in ink.get_children():
		ink.remove_child(c)
		c.queue_free()
	placed.clear()
	line_height = height
	var x := 0.0
	var seq: Array = []
	if not decor.is_empty():
		seq.append([decor[0], true])
	for e in pieces:
		seq.append([e, false])
	if not decor.is_empty():
		seq.append([decor[1], true])
	for i in seq.size():
		var e: Dictionary = seq[i][0]
		var is_decor: bool = seq[i][1]
		if i > 0:
			x += height * GAP
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
		var target := height * (DECOR_SIZE if is_decor else 1.0)
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
		rect.position = Vector2(
			x + slot * 0.5 - float(e.get("body_center_x", 0.5)) * tw * s,
			height * 0.5 - float(e.get("line_center", e.get("body_center", 0.5))) * th * s)
		ink.add_child(rect)
		var p := Placed.new()
		p.entry = e
		p.rect = rect
		p.body = Rect2(x, height * 0.5 - target * 0.5, slot, target)
		placed.append(p)
		x += slot
	ink_width = x
	ink.size = Vector2(x, height)
	custom_minimum_size = Vector2(0.0, height * (1.0 + 2.0 * PAD))
	size = Vector2(x, custom_minimum_size.y)
	_centre()
