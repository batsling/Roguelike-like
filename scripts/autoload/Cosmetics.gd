extends Node

# CUSTOMIZATION (docs/customization.md; the owner, 8 Nov 2026): what the player
# has EARNED to look different, and what they have chosen to WEAR.
#
#   * COSTUMES for a character's icon and full portrait, chosen separately;
#   * ICONS for keys, bombs, Luck, chests, Health, damage, gold, shields, Hunger and the trophy (a DIFFICULTY image stands
#     in for 🏆 wherever it is drawn, with the Fracture number on it; a CHEST image
#     stands in for 🎁, and a set of them is picked by the chest's size);
#   * which TITLE LETTERS the main menu may spell from — a whole game's, or one
#     letter at a time — as long as what is left can still spell the title and
#     the subtitle.
#
# EARNING mirrors TitleUnlocks, on purpose: how many looks an owner has earned is
# its share of its ranks (RankRewards.split, "looks"), never stored; WHICH ones came
# up is a random draw, stored per profile with who drew it. A game draws from its
# own units, a character from its games' and its own costumes
# (CosmeticCatalog.units_of_*). Nothing is ever locked again.
#
# WEARING is a choice per profile. A choice that is not unlocked (a profile switch,
# "Unlock everything" turned off) reads as the default rather than being cleared,
# so turning the test switch back on brings it back.

signal changed
signal look_unlocked(key: String)

const FILE := "customization.json"
# The main menu's two lines (MainMenu.tscn): every letter of both must stay
# spellable with what is switched on.
const TITLE_TEXTS := ["Roguelike-Like", "The Search for the Amulet of Nivlac"]

var _unlocked: Dictionary = {}     # unit key -> owner key ("game:hades")
var _worn: Dictionary = {}         # "costume:<character>:<slot>" / "icon:<kind>" -> unit key
var _letters_off: Dictionary = {}  # index key -> true
var _games_off: Dictionary = {}    # game id -> true
# RANDOM (the owner, 8 Nov 2026): a slot worn as RANDOM shows `_rolled[slot]`, rolled
# afresh at the start of every run (GameLoop2.start_run -> roll_random) among the
# default and every unlocked look that fits it. "" in `_rolled` is the default.
const RANDOM := "random"
var _rolled: Dictionary = {}       # slot key -> unit key or ""
# NEW LOOKS GLOW (the owner, 8 Nov 2026: "similar to how new letters do"): a look
# drawn but not yet shown on a screen that lets you wear it. Per profile, like
# TitleUnlocks' seen letters; `mark_seen` once shown.
var _seen: Dictionary = {}         # unit key -> true
var path_override: String = ""
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_load()
	refresh_unlocks(false)
	GameStats.changed.connect(func() -> void: refresh_unlocks(true))
	Profiles.profile_switched.connect(_on_profile_changed)
	Profiles.profile_wiped.connect(_on_profile_changed)
	Settings.unlock_everything_changed.connect(func(_on: bool) -> void: changed.emit())
	_watch_tree()

# --- earned ---------------------------------------------------------------------

func is_unlocked(key: String) -> bool:
	return Settings.unlock_everything or _unlocked.has(key)

func unlocked_keys() -> Array:
	var out: Array = _unlocked.keys()
	out.sort()
	return out

func drawn_for(owner: String) -> int:
	var n: int = 0
	for k in _unlocked:
		if String(_unlocked[k]) == owner:
			n += 1
	return n

# Who drew `key` ("game:hades"), or "" while it is locked.
func drawn_by(key: String) -> String:
	return String(_unlocked.get(key, ""))

func refresh_unlocks(announce: bool = true) -> void:
	RankRewards.batch(func() -> void: _refresh_unlocks(announce))

func _refresh_unlocks(announce: bool) -> void:
	var fresh: Array = []
	var games := {}
	for e in CosmeticCatalog.all_units():
		games[String(e["game"])] = true
	var ids: Array = games.keys()
	ids.sort()
	for g in ids:
		var owner: String = RankRewards.game_key(StringName(g))
		var owed: int = int(RankRewards.for_game(StringName(g)).get("looks", 0)) - drawn_for(owner)
		_draw(CosmeticCatalog.units_of_game(StringName(g)), owed, owner, fresh)
	var roster: Array = Data.all_characters2()
	roster.sort_custom(func(a, b): return String(a.id) < String(b.id))
	for ch in roster:
		var owner: String = RankRewards.character_key(ch.id)
		var owed: int = int(RankRewards.for_character(ch.id).get("looks", 0)) - drawn_for(owner)
		_draw(CosmeticCatalog.units_of_character(ch.id), owed, owner, fresh)
	if fresh.is_empty():
		return
	_save()
	if announce:
		for key in fresh:
			_announce(key)
	changed.emit()

# The toast for a look just earned ("✦ New hat: Super Auto Pets — Top Hat").
func _announce(key: String) -> void:
	var e: Dictionary = CosmeticCatalog.entry(key)
	var unit := String(e.get("unit", ""))
	var what: String = unit if unit in ["costume", "hat"] \
		else {"key": "key icon", "bomb": "bomb icon", "difficulty": "difficulty icon",
			"luck": "Luck icon", "chest": "chest icon", "health": "Health icon",
			"damage": "damage icon", "gold": "gold icon", "shield": "shield icon",
			"hunger": "Hunger icon"}.get(
			String(e.get("kind", "")), "look")
	Notifications.notify("✦ New %s: %s" % [what, CosmeticCatalog.label(e)],
		Color(0.95, 0.8, 0.45), CosmeticCatalog.texture(
			(CosmeticCatalog.paths(e) + [""])[0]), "cosmetic")
	look_unlocked.emit(key)

# A SPECIAL HAT is earned by a rule of its own, never by a rank
# (CosmeticCatalog.is_special): the owner, 14 Nov 2026 — "don't add special hats
# except the abandon hat which can be unlocked by escaping 5 games in a row". The
# streak is the RUN's (GameState.escape_streak; the owner chose "within one run"),
# counted where every game is handed in (Overworld2.report's bookkeeping).
const ABANDON_HAT := "hat/abandon_hat"
const ABANDON_ESCAPES := 5
# key -> how it is earned, in words, for a locked tile's hover.
const SPECIAL_HATS := {ABANDON_HAT: "Escape %d games in a row in one run." % ABANDON_ESCAPES}
const SPECIAL_OWNER := "special"

# Called with the run's escape streak after every game handed in.
func note_escape_streak(streak: int) -> void:
	if streak >= ABANDON_ESCAPES:
		unlock_special(ABANDON_HAT)

# Unlock `key` outside the ranks; true if it was not already. Toasted like a rank's.
func unlock_special(key: String) -> bool:
	if _unlocked.has(key) or CosmeticCatalog.entry(key).is_empty():
		return false
	_unlocked[key] = SPECIAL_OWNER
	_save()
	_announce(key)
	changed.emit()
	return true

func _draw(pool: Array, owed: int, owner: String, fresh: Array) -> void:
	if owed <= 0:
		return
	var locked: Array = pool.filter(func(k): return not _unlocked.has(k))
	while owed > 0 and not locked.is_empty():
		var key: String = locked.pop_at(_rng.randi_range(0, locked.size() - 1))
		_unlocked[key] = owner
		fresh.append(key)
		owed -= 1

# --- worn -----------------------------------------------------------------------

static func costume_slot(character: StringName, slot: String) -> String:
	return "costume:%s:%s" % [character, slot]

static func icon_slot(kind: String) -> String:
	return "icon:%s" % kind

# A PLAYER's hat (docs/customization.md §7): one slot per player, so Retro Bat and
# Batsaac each keep their own.
static func hat_slot(player: StringName) -> String:
	return "hat:%s" % player

# What the player CHOSE for a slot: "" (the default), RANDOM, or a unit key.
func choice(slot_key: String) -> String:
	return String(_worn.get(slot_key, ""))

# The unit a slot shows now — a RANDOM slot's roll — or "" for the default.
func _shown_key(slot_key: String) -> String:
	var key := choice(slot_key)
	if key == RANDOM:
		if not _rolled.has(slot_key):
			_roll(slot_key)
		key = String(_rolled.get(slot_key, ""))
	return key if key != "" and is_unlocked(key) else ""

# The costume `character` wears in `slot` (icon or full), or {} for the default.
func costume(character: StringName, slot: String) -> Dictionary:
	var key := _shown_key(costume_slot(character, slot))
	return CosmeticCatalog.entry(key) if key != "" else {}

# `key` is "" (the default), RANDOM, or a costume's unit key.
func set_costume(character: StringName, slot: String, key: String) -> void:
	_choose(costume_slot(character, slot), key)

# The icon set worn for `kind` (key, bomb, difficulty, luck, chest), or {} for the default glyph.
func icon(kind: String) -> Dictionary:
	var key := _shown_key(icon_slot(kind))
	return CosmeticCatalog.entry(key) if key != "" else {}

func set_icon(kind: String, key: String) -> void:
	_choose(icon_slot(kind), key)

# The hat `player` wears, or {} for none.
func hat(player: StringName) -> Dictionary:
	var key := _shown_key(hat_slot(player))
	return CosmeticCatalog.entry(key) if key != "" else {}

func set_hat(player: StringName, key: String) -> void:
	_choose(hat_slot(player), key)

# `pl`'s full picture in the hat it wears (HatArt), or its own art when it wears
# none or has no spot for one.
func player_art(pl: PlayerData) -> Texture2D:
	if pl == null:
		return null
	var e := hat(pl.id)
	if e.is_empty() or pl.portrait == null:
		return pl.portrait
	return HatArt.wear(pl.portrait, CosmeticCatalog.texture(String(e.get("path", ""))), pl.hat_spot)

# What a slot shows now, a costume's or an icon set's entry ({} for the default).
func costume_or_icon(slot_key: String) -> Dictionary:
	var key := _shown_key(slot_key)
	return CosmeticCatalog.entry(key) if key != "" else {}

func choose(slot_key: String, key: String) -> void:
	_choose(slot_key, key)

func _choose(slot_key: String, key: String) -> void:
	if key == "":
		_worn.erase(slot_key)
	else:
		_worn[slot_key] = key
	_rolled.erase(slot_key)
	if key == RANDOM:
		_roll(slot_key)   # a pick to show before the first run rolls one
	_save()
	changed.emit()

# The looks a slot can roll: the default ("") and every unlocked look that fits.
func options(slot_key: String) -> Array:
	var parts := slot_key.split(":")
	var pool: Array = []
	if parts[0] == "costume":
		pool = CosmeticCatalog.costumes_of(StringName(parts[1]), parts[2])
	elif parts[0] == "hat":
		pool = CosmeticCatalog.hats()
	else:
		pool = CosmeticCatalog.icons_of(parts[1])
	var out: Array = [""]
	for e in pool:
		if is_unlocked(String(e["key"])):
			out.append(String(e["key"]))
	return out

func _roll(slot_key: String) -> void:
	var opts := options(slot_key)
	_rolled[slot_key] = String(opts[_rng.randi_range(0, opts.size() - 1)])

# Every RANDOM slot rolls again. GameLoop2.start_run calls it, so each run is
# dressed afresh; the roll is saved, so the menu and the run agree on it.
func roll_random() -> void:
	var any := false
	for slot_key in _worn:
		if String(_worn[slot_key]) == RANDOM:
			_roll(String(slot_key))
			any = true
	if any:
		_save()
		changed.emit()

# --- new looks ------------------------------------------------------------------

# Drawn by a rank and not yet shown where it can be worn: it glows.
func is_new(key: String) -> bool:
	return _unlocked.has(key) and not _seen.has(key)

func mark_seen(keys: Array) -> void:
	var moved := false
	for k in keys:
		if _unlocked.has(String(k)) and not _seen.has(String(k)):
			_seen[String(k)] = true
			moved = true
	if moved:
		_save()

# The glow itself, shared by every screen that shows a look: LogoProgress's pulse.
const GLOW := Color(2.4, 2.1, 1.5)
const GLOW_PULSES := 3
const GLOW_PULSE_SECS := 0.45

static func glow(node: CanvasItem) -> void:
	var tw := node.create_tween().set_loops(GLOW_PULSES)
	tw.tween_property(node, "modulate", GLOW, GLOW_PULSE_SECS * 0.4)
	tw.tween_property(node, "modulate", Color.WHITE, GLOW_PULSE_SECS * 0.6)

# A character's portrait and icon as worn: the costume's picture, else its own.
func portrait_of(ch: CharacterData) -> Texture2D:
	if ch == null:
		return null
	var e := costume(ch.id, "full")
	var t: Texture2D = CosmeticCatalog.texture(String(e.get("path", ""))) if not e.is_empty() else null
	return t if t != null else ch.portrait

func icon_of(ch: CharacterData) -> Texture2D:
	if ch == null:
		return null
	var e := costume(ch.id, "icon")
	var t: Texture2D = CosmeticCatalog.texture(String(e.get("path", ""))) if not e.is_empty() else null
	if t != null:
		return t
	return ch.icon if ch.icon != null else portrait_of(ch)

# The picture standing in for `glyph` (🗝, ✸, 🏆, 🍀 or 🎁) at `level`, or null
# when the default glyph is worn. `level` is the Fracture for a trophy and the
# chest's size (0 Small … 3 Huge) for a gift.
const GLYPHS := {"🗝": "key", "✸": "bomb", "🏆": "difficulty", "🍀": "luck", "🎁": "chest",
	"♥": "health", "◉": "gold", "🛡": "shield"}

# A SHIELD IS ALSO DRAWN AS A PICTURE, not only written as 🛡: the pips over the
# hero, the chip beside the Health, the Camp's Rest, the OBS overlay. Each asks
# here, so a worn shield icon is on those too; unworn it is the basic 🛡 as art.
func shield_art() -> Texture2D:
	var e := icon("shield")
	var t: Texture2D = CosmeticCatalog.texture(CosmeticCatalog.image_for(e, 0)) if not e.is_empty() else null
	return t if t != null else UITheme.SHIELD_ART

# HUNGER IS ONLY EVER DRAWN (docs/players-design.md §4): five of these stand in
# the header for a player with Hunger. The worn Hunger icon, else the basic 🍗
# as art (tools/build_hunger_art.py).
func hunger_art() -> Texture2D:
	var e := icon("hunger")
	var t: Texture2D = CosmeticCatalog.texture(CosmeticCatalog.image_for(e, 0)) if not e.is_empty() else null
	return t if t != null else UITheme.HUNGER_ART
# DAMAGE IS ⚔ ONLY WHERE A NODE SAYS SO (the owner, 13 Nov 2026). The crossed swords
# are also "beaten" on every record line, the Combat button and the weapons tab,
# and a damage icon has no business on any of those. So a node that writes ⚔ as
# DAMAGE marks itself (`as_damage`), and only a marked node's ⚔ is swapped.
const SCOPED := {"⚔": "damage"}
const META_DAMAGE := "glyph_damage"

static func as_damage(node: Node) -> Node:
	node.set_meta(META_DAMAGE, true)
	return node

# The glyphs `c` may have swapped: every plain one, and ⚔ when it is marked.
func _glyphs_of(c: Node) -> Dictionary:
	if c != null and c.has_meta(META_DAMAGE):
		var both: Dictionary = GLYPHS.duplicate()
		both.merge(SCOPED)
		return both
	return GLYPHS

func glyph_texture(glyph: String, level: int = 0) -> Texture2D:
	var kind: String = GLYPHS.get(glyph, SCOPED.get(glyph, ""))
	if kind == "":
		return null
	var e := icon(kind)
	if e.is_empty():
		return null
	return CosmeticCatalog.texture(CosmeticCatalog.image_for(e, level))


# --- the glyphs on screen ----------------------------------------------------------
#
# A WORN ICON IN PLACE OF ITS GLYPH (Customization, docs/customization.md). The UI
# writes keys as 🗝, bombs as ✸, the trophy as 🏆, Luck as 🍀, a chest as 🎁, Health
# as ♥ (yours and an enemy's alike), gold as ◉ and damage as ⚔ inside ordinary text. When the
# player wears an icon for one, this swaps the glyph in a Label's or a Button's
# text for room (spaces) and lays the picture over that room, with the Fracture
# number on a trophy's (the owner, 8 Nov 2026: "everywhere means everywhere, and
# with the number on top of it too").
#
# EVERY LABEL AND BUTTON GETS IT WITHOUT ASKING: this watches the tree's
# node_added and runs `apply_glyph` (deferred, so the text a builder sets after add_child
# is there) on each one while any icon is worn. Text set AFTER that — a count that
# ticks, a banner reused — calls `Cosmetics.apply_glyph` itself.
#
# Per node, as metadata:
#   glyph_level  (int)   the level to pick the picture by: the Fracture for a
#                        trophy (default: the run's own, 0 outside a run), which
#                        is also the number on it, and the chest's SIZE for a
#                        gift (0 Small … 3 Huge; default 0);
#   glyph_number (bool)  false where the node draws its own number (RankBadge).
#
# WHAT IT CANNOT PLACE: a glyph inside text that wraps onto a second line by width
# (rather than by "\n"). Its line is measured as if it did not wrap, so the
# picture lands where the unwrapped text would put it; every 🗝 ✸ 🏆 🍀 🎁 in the UI
# today starts its line or sits in a one-line label.


func _watch_tree() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if (n is Label or n is Button) and _any_icon_worn():
		_check_glyph.call_deferred(n)

func _check_glyph(n: Variant) -> void:
	if not is_instance_valid(n):
		return
	var t: String = n.text
	for g in _glyphs_of(n):
		if t.contains(g):
			apply_glyph(n)
			return

func _any_icon_worn() -> bool:
	for k in CosmeticCatalog.KINDS:
		if _worn.has("icon:%s" % k):
			return true
	return false

const GLYPH_NODE := "GlyphArt"
const META_TEXT := "glyph_art_text"
const ICON_SCALE := 1.1

# The level a node's picture is chosen and numbered by. Only the trophy rides the
# run's Fracture when the node says nothing: a gift's level is a chest's size, and
# a chest nobody sized is the smallest.
func glyph_level_of(c: Node, glyph: String = "🏆") -> int:
	if c.has_meta("glyph_level"):
		return int(c.get_meta("glyph_level"))
	if glyph != "🏆":
		return 0
	return Fracture.level() if GameState.phase != GameState.Phase.MENU else 0

func apply_glyph(c: Variant) -> void:
	if not is_instance_valid(c) or not (c is Label or c is Button):
		return
	var text: String = c.text
	if c.has_meta(META_TEXT) and String(c.get_meta(META_TEXT)) == text:
		_place_glyph.call_deferred(c)
		return
	var level := 0
	var found := ""
	var tex: Texture2D = null
	var at := -1
	for g in _glyphs_of(c):
		var i := text.find(g)
		if i >= 0 and (at < 0 or i < at):
			var lv := glyph_level_of(c, g)
			var t: Texture2D = glyph_texture(g, lv)
			if t != null:
				found = g
				tex = t
				at = i
				level = lv
	var old: Node = c.get_node_or_null(GLYPH_NODE)
	if found == "":
		if old != null and not c.has_meta(META_TEXT):
			old.queue_free()
		elif old != null and String(c.get_meta(META_TEXT)) != text:
			old.queue_free()
			c.remove_meta(META_TEXT)
		return
	var font: Font = c.get_theme_font("font")
	var fs: int = c.get_theme_font_size("font_size")
	var side: float = font.get_height(fs) * ICON_SCALE
	var room := _room(font, fs)
	var out := text.substr(0, at) + room + text.substr(at + found.length())
	var holder: TextureRect = old as TextureRect
	if holder == null:
		holder = TextureRect.new()
		holder.name = GLYPH_NODE
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		holder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		c.add_child(holder, false, Node.INTERNAL_MODE_BACK)
	# Drawn without the chop (UITheme.fit_art): a big picture through its mipmaps,
	# pixel art at a whole multiple of its own size.
	UITheme.fit_art(holder, tex, side)
	holder.set_meta("at", at)
	holder.set_meta("room", room.length())
	var num: Label = holder.get_node_or_null("Level")
	var show_number: bool = found == "🏆" and level > 0 and bool(c.get_meta("glyph_number", true))
	if show_number:
		if num == null:
			num = Label.new()
			num.name = "Level"
			num.mouse_filter = Control.MOUSE_FILTER_IGNORE
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			num.add_theme_color_override("font_color", Fracture.COLOR)
			num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			num.add_theme_constant_override("outline_size", 3)
			num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			holder.add_child(num)
		num.text = str(level)
	elif num != null:
		num.queue_free()
	c.text = out
	c.set_meta(META_TEXT, out)
	if not c.has_meta("glyph_art_wired"):
		c.set_meta("glyph_art_wired", true)
		c.resized.connect(_place_glyph.bind(c))
	_place_glyph(c)

# The spaces a picture is laid over, at this font.
func _room(font: Font, fs: int) -> String:
	var side: float = font.get_height(fs) * ICON_SCALE
	var space_w: float = maxf(font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 1.0)
	return " ".repeat(ceili(side / space_w))

# `text` as it will stand once its glyph has made room for a worn picture, for a
# site that MEASURES text before it is on a node (the board's stat badges, fitted
# to a body's width). Unchanged when nothing it holds is worn. `damage` reads ⚔
# as damage, as a node marked `as_damage` does.
func roomed(text: String, font: Font, fs: int, damage: bool = false) -> String:
	if not _any_icon_worn():
		return text
	var at := -1
	var found := ""
	for g in GLYPHS:
		var i := text.find(g)
		if i >= 0 and (at < 0 or i < at) and not icon(String(GLYPHS[g])).is_empty():
			at = i
			found = g
	if damage:
		for g in SCOPED:
			var i := text.find(g)
			if i >= 0 and (at < 0 or i < at) and not icon(String(SCOPED[g])).is_empty():
				at = i
				found = g
	if found == "":
		return text
	return text.substr(0, at) + _room(font, fs) + text.substr(at + found.length())

# Lay the picture over the room left for it.
func _place_glyph(c: Variant) -> void:
	if not is_instance_valid(c):
		return
	var holder: TextureRect = c.get_node_or_null(GLYPH_NODE)
	if holder == null:
		return
	var font: Font = c.get_theme_font("font")
	var fs: int = c.get_theme_font_size("font_size")
	var side: float = font.get_height(fs) * ICON_SCALE
	var text: String = c.text
	var at: int = int(holder.get_meta("at", 0))
	var line_start: int = text.rfind("\n", at - 1) + 1 if at > 0 else 0
	var line_end: int = text.find("\n", at)
	if line_end < 0:
		line_end = text.length()
	var line: String = text.substr(line_start, line_end - line_start)
	var line_idx: int = text.substr(0, line_start).count("\n")
	var lines: int = text.count("\n") + 1
	var prefix_w: float = font.get_string_size(text.substr(line_start, at - line_start),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var room_w: float = font.get_string_size(" ".repeat(int(holder.get_meta("room", 1))),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var line_w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var style: StyleBox = c.get_theme_stylebox("normal")
	var ml: float = style.get_margin(SIDE_LEFT) if style != null else 0.0
	var mr: float = style.get_margin(SIDE_RIGHT) if style != null else 0.0
	var mt: float = style.get_margin(SIDE_TOP) if style != null else 0.0
	var mb: float = style.get_margin(SIDE_BOTTOM) if style != null else 0.0
	var inner_w: float = c.size.x - ml - mr
	var align: int = (c as Label).horizontal_alignment if c is Label else (c as Button).alignment
	var x0: float = ml
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x0 = ml + maxf((inner_w - line_w) * 0.5, 0.0)
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x0 = ml + maxf(inner_w - line_w, 0.0)
	var lh: float = font.get_height(fs)
	if c is Label:
		lh += float((c as Label).get_theme_constant("line_spacing"))
	var block: float = lh * lines
	var inner_h: float = c.size.y - mt - mb
	var y0: float = mt + (inner_h - block) * 0.5
	if c is Label:
		var va: int = (c as Label).vertical_alignment
		if va == VERTICAL_ALIGNMENT_TOP:
			y0 = mt
		elif va == VERTICAL_ALIGNMENT_BOTTOM:
			y0 = mt + inner_h - block
	holder.size = Vector2(side, side)
	holder.position = Vector2(x0 + prefix_w + (room_w - side) * 0.5, y0 + line_idx * lh + (lh - side) * 0.5)
	var num: Label = holder.get_node_or_null("Level")
	if num != null:
		num.add_theme_font_size_override("font_size", maxi(int(side * 0.55), 8))

# --- title letters --------------------------------------------------------------

func letters_game_on(game: String) -> bool:
	return not _games_off.has(game)

func letter_on(key: String) -> bool:
	return not _letters_off.has(key)

# Whether a title piece (a TitleLetters pool entry) may be spelled with.
func piece_on(e: Dictionary) -> bool:
	return letters_game_on(String(e.get("game", ""))) and letter_on(TitleLetters.unit_key(e))

# Switching a game's letters (or one letter) on or off. Off is refused, returning
# false, when what would be left cannot spell both lines.
func set_letters_game(game: String, on: bool) -> bool:
	if on:
		_games_off.erase(game)
	else:
		_games_off[game] = true
		if not can_spell():
			_games_off.erase(game)
			return false
	_save()
	changed.emit()
	return true

func set_letter(key: String, on: bool) -> bool:
	if on:
		_letters_off.erase(key)
	else:
		_letters_off[key] = true
		if not can_spell():
			_letters_off.erase(key)
			return false
	_save()
	changed.emit()
	return true

# Whether the pieces switched on (and earned) spell every character of the title
# and the subtitle, by the same rule TitleLetters.pick uses.
func can_spell(texts: Array = TITLE_TEXTS) -> bool:
	return spells(TitleLetters.available_with(true), texts)

func spells(from: Dictionary, texts: Array = TITLE_TEXTS) -> bool:
	# An empty pool is not "every piece" here (TitleLetters.pick reads it that way).
	if from.is_empty():
		return false
	for t in texts:
		for p in TitleLetters.pick(String(t), _rng, from):
			if (p as Dictionary).has("missing"):
				return false
	return true

# --- saved per profile ------------------------------------------------------------

func _on_profile_changed() -> void:
	_load()
	refresh_unlocks(false)
	changed.emit()

func _path() -> String:
	return path_override if path_override != "" else Profiles.path(FILE)

func _load() -> void:
	_unlocked = {}
	_worn = {}
	_letters_off = {}
	_games_off = {}
	_rolled = {}
	_seen = {}
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	for k in d.get("unlocked", {}):
		_unlocked[String(k)] = String(d["unlocked"][k])
	for k in d.get("worn", {}):
		_worn[String(k)] = String(d["worn"][k])
	for k in d.get("letters_off", []):
		_letters_off[String(k)] = true
	for k in d.get("games_off", []):
		_games_off[String(k)] = true
	for k in d.get("rolled", {}):
		_rolled[String(k)] = String(d["rolled"][k])
	for k in d.get("seen", []):
		_seen[String(k)] = true

func _save() -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return
	var off: Array = _letters_off.keys()
	off.sort()
	var goff: Array = _games_off.keys()
	goff.sort()
	var seen: Array = _seen.keys()
	seen.sort()
	f.store_string(JSON.stringify({"unlocked": _unlocked, "worn": _worn,
		"letters_off": off, "games_off": goff, "rolled": _rolled, "seen": seen}, "  ", true))

func reset_for_tests() -> void:
	_unlocked = {}
	_worn = {}
	_letters_off = {}
	_games_off = {}
	_rolled = {}
	_seen = {}
	_save()
	changed.emit()
