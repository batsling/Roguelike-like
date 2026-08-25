class_name UITheme
extends RefCounted

# Shared visual language for the games-first (2.0) UI. The screens are built in
# code, so before this they each hand-rolled their own colours and styleboxes and
# drifted apart. This centralises the palette — a warm, dark, parchment-and-ember
# fantasy look carried over from the original web build (legacy-web/css/styles.css)
# — plus a ready-made Godot Theme so every Button / Panel / Label / input picks up
# a consistent style just by setting `theme = UITheme.make_theme()` on a screen
# root. Individual stylebox overrides (rarity tiles, enemy cards) still win where a
# screen needs something bespoke.

# --- Palette ---------------------------------------------------------------
# Warm near-blacks and embers rather than the old cold blue-greys.
const BG_DEEP := Color(0.078, 0.063, 0.047)      # #14100c page background
const BG := Color(0.114, 0.094, 0.071)           # #1d1812 base surface
const PANEL := Color(0.145, 0.122, 0.094)         # #251f18 raised panel
const PANEL_HI := Color(0.192, 0.161, 0.122)      # #312920 hover / header
const BORDER := Color(0.290, 0.247, 0.180)        # #4a3f2e hairline border

const ACCENT := Color(1.0, 0.541, 0.235)          # #ff8a3c ember orange
const ACCENT_DIM := Color(0.80, 0.40, 0.0)        # #cc6600 pressed / muted ember
const GOLD := Color(1.0, 0.80, 0.40)              # #ffcc66 highlight gold
const TEXT := Color(0.902, 0.835, 0.722)          # #e6d5b8 parchment text
const TEXT_DIM := Color(0.659, 0.612, 0.529)      # #a89c87 secondary text
const TEXT_FAINT := Color(0.46, 0.43, 0.38)       # tertiary / placeholders

const SUCCESS := Color(0.30, 0.78, 0.42)
const DANGER := Color(0.90, 0.33, 0.28)
# CURSE purple (docs/event-sheet-authoring.md §5). The checklist carries three
# kinds of objective and they bite differently — an enemy goal is a debt, an
# event goal a bonus, a curse a bill you pay for SUCCEEDING at the wrong thing.
# The one row you are trying not to complete must not read like the ones you are
# chasing, so it gets a colour of its own rather than borrowing DANGER.
const CURSE := Color(0.72, 0.45, 0.90)

# Rarity ramp (mirrors RarityStyle / legacy CSS): Common, Uncommon, Rare,
# Legendary.
const RARITY := [
	Color(0.72, 0.72, 0.72), Color(0.30, 0.69, 0.31),
	Color(0.61, 0.35, 0.71), Color(1.0, 0.80, 0.30),
]

# Game-type accent colours, indexed by GameData.GameType (Action, Strategy,
# Deckbuilder, Traditional).
const TYPE_COLORS := [
	Color(0.93, 0.42, 0.32),   # Action  — red-orange
	Color(0.46, 0.70, 0.95),   # Strategy — blue
	Color(0.70, 0.45, 1.0),    # Deckbuilder — violet
	Color(0.55, 0.80, 0.50),   # Traditional — green
]

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Legendary"]

# The RARITY ramp above is the four rungs a draw can roll. An ITEM also has three
# classes that are not rungs at all — Starter, Boss, Event (ItemData.ItemClass) —
# and each needs a colour, because a Boss relic painted in Common grey is a lie
# every screen would then repeat. Indexed by ItemData.ItemClass, so the first four
# entries are the ramp again and the last three are the classes.
const ITEM_CLASS_COLORS := [
	Color(0.72, 0.72, 0.72), Color(0.30, 0.69, 0.31),
	Color(0.61, 0.35, 0.71), Color(1.0, 0.80, 0.30),
	Color(0.40, 0.85, 0.95),   # Starter — the cyan the Collection already used
	Color(0.94, 0.33, 0.36),   # Boss — the only red on the ramp
	Color(0.98, 0.62, 0.22),   # Event — amber, next to no other accent
]

# CURRENCY AND SHOPS (docs/games-first-redesign.md §14).
#
# COIN_GOLD is a deeper, brassier yellow than GOLD above, which this build has
# already spent on the AMULET — the run's title, the amulet flag on a card, the
# route badge. The two must not be confusable: one is the thing the whole run is
# a search for and the other is pocket change, and they can appear in the same
# row of the same card.
#
# SHOP_GREEN is deliberately not a gold at all, for the same reason. A shop's
# flag sits in the very slot the Amulet's flag uses, so it needs to be a
# different COLOUR, not a different shade of the same one.
#
# They live here rather than on Overworld2 because ShopModal2 and GameChoiceModal
# need them too, and a modal reaching back into the screen that mounted it for a
# colour is a dependency cycle — literally: it stopped the project compiling.
const COIN_GOLD := Color(0.98, 0.74, 0.20)
const SHOP_GREEN := Color(0.44, 0.82, 0.56)

static func rarity_color(i: int) -> Color:
	return RARITY[clampi(i, 0, RARITY.size() - 1)]

static func rarity_name(i: int) -> String:
	return RARITY_NAMES[clampi(i, 0, RARITY_NAMES.size() - 1)]

# The colour and the word for ONE ITEM, class included. Everything that draws an
# item goes through these rather than through rarity_color/rarity_name, so a Boss
# relic reads as a Boss relic on the drop modal, in the pack, in the Collection
# and in the dev panel without each of them being taught the rule separately.
static func item_color(item: ItemData) -> Color:
	if item == null:
		return TEXT_DIM
	return ITEM_CLASS_COLORS[clampi(item.item_class(), 0, ITEM_CLASS_COLORS.size() - 1)]

static func item_class_name(item: ItemData) -> String:
	return item.class_label() if item != null else ""

static func type_color(i: int) -> Color:
	return TYPE_COLORS[clampi(i, 0, TYPE_COLORS.size() - 1)]

# The colour a loot PREFERENCE reads in (§4.1/§4.3). Positive / Negative / Neutral
# is the single fact that decides whether a piece of loot is worth spending, and it
# was being drawn as muted grey body text on every surface that showed it. Here so
# the window tile, the drop modal and the use modal cannot disagree about what
# green means. An empty preference — the unidentified case — has no colour of its
# own on purpose: the gamble is the absence of this chip, not a grey one.
static func preference_color(preference: String) -> Color:
	match preference:
		"Positive":
			return SUCCESS
		"Negative":
			return DANGER
		"Neutral":
			return Color(0.55, 0.70, 0.90)
	return TEXT_DIM

# --- Stylebox builders -----------------------------------------------------

static func flat(bg: Color, radius: int = 8, margin: int = 10, border_w: int = 0, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	return sb

# A button that would END THE RUN if pressed — the last point of Health spent on
# Scrap Ooze's reach, one dip too many in Abyssal Baths, the Blood Donation
# Machine's lever. It is deliberately NOT disabled: these are push-your-luck
# machines and taking the decision away is worse than the death. So the button
# carries the warning instead, in the same red the cost line under it runs in.
#
# Blood-dark rather than bright red: it has to read as dangerous at a glance and
# still be readable as a button with a label on it. Hover lifts towards DANGER,
# because the moment the cursor is on it is the moment the warning matters most.
static func lethal_box(hover: bool = false) -> StyleBoxFlat:
	return flat(DANGER.lerp(BG, 0.78 if hover else 0.86), 6, 6, 2, DANGER)

# A raised panel with a hairline border and a subtle top-lit gradient feel via a
# slightly brighter border. Used for HUD strips, detail panels, cards.
static func panel_box(bg: Color = PANEL, border: Color = BORDER, radius: int = 10, margin: int = 12, border_w: int = 1) -> StyleBoxFlat:
	return flat(bg, radius, margin, border_w, border)

# A glow-accented card border, e.g. a hovered / selected tile.
static func accent_box(accent: Color, bg: Color = PANEL, margin: int = 12) -> StyleBoxFlat:
	var sb := flat(bg, 10, margin, 2, accent)
	sb.border_width_left = 4
	return sb

# --- Buttons ---------------------------------------------------------------
#
# THE TWO WEIGHTS A CHOICE HAS. Every modal in the 2.0 build asks the same shape
# of question — one button that DOES the thing and one that walks away — and the
# pack's Use button, the relic drop's "Take it" and the loot drop's "Take it" had
# each grown their own version of the green. The loot surfaces were the ones that
# hadn't: they shipped Godot's default grey on both answers, which read as two
# equal options on a screen where one of them is the point.
#
# `confirm` is the affirmative: green plate, green rule, lifted on hover.
# `quiet` is the way out: the theme's own button, sized to match so the pair sits
# on one baseline. Both take a minimum size because the same pair is drawn at
# three scales (a 14px cell button, a 34px card button, a 42px modal button).
static func confirm_button(text: String, min_size: Vector2 = Vector2.ZERO, font_size: int = 0) -> Button:
	return action_button(text, SUCCESS, min_size, font_size)

# THE SAME AFFIRMATIVE PLATE IN A COLOUR OF ITS OWN — for the screen that offers
# TWO of them and needs the pair to be told apart. A potion's card is the one that
# does (docs/potions-design.md §4.5): Quaff and Throw are both things you are
# saying yes to, and the choice between them is the whole of what the kind is for,
# so two identical green plates would read as one button drawn twice.
#
# `confirm_button` is this in SUCCESS, which is the only colour anything else on
# the page wants.
static func action_button(text: String, color: Color,
		min_size: Vector2 = Vector2.ZERO, font_size: int = 0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	if font_size > 0:
		btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_stylebox_override("normal",
		flat(color.lerp(BG, 0.80), 8, 6, 1, color.lerp(BG, 0.30)))
	btn.add_theme_stylebox_override("hover",
		flat(color.lerp(BG, 0.62), 8, 6, 2, color))
	btn.add_theme_stylebox_override("pressed",
		flat(color.lerp(BG, 0.52), 8, 6, 2, color))
	btn.add_theme_stylebox_override("disabled",
		flat(BG.lerp(BORDER, 0.35), 8, 6, 1, BORDER))
	# FOCUS KEEPS THE COLOUR. A modal's confirm grabs focus when it opens, and the
	# theme's focus stylebox is drawn OVER `normal` — so without this the one button
	# the screen is steering you towards is the one that isn't wearing its own
	# colour. Same plate, brighter rule, which is what focus should say here.
	btn.add_theme_stylebox_override("focus",
		flat(color.lerp(BG, 0.62), 8, 6, 2, color.lerp(Color.WHITE, 0.35)))
	btn.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.45))
	btn.add_theme_color_override("font_hover_color", color.lerp(Color.WHITE, 0.7))
	btn.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn

static func quiet_button(text: String, min_size: Vector2 = Vector2.ZERO, font_size: int = 0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	if font_size > 0:
		btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_stylebox_override("normal", flat(PANEL_HI, 8, 6, 1, BORDER))
	btn.add_theme_stylebox_override("hover", flat(PANEL_HI.lerp(TEXT, 0.12), 8, 6, 1, TEXT_DIM))
	btn.add_theme_color_override("font_color", TEXT_DIM)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn

# A small labelled plate in one colour — a rarity, a preference, a charge count.
# Three screens had grown their own private `_chip` doing exactly this; new code
# comes through here so a chip is one shape wherever it is drawn.
static func chip(text: String, color: Color, font_size: int = 11) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		flat(color.lerp(BG, 0.74), 6, 5, 1, color.lerp(BG, 0.38)))
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(l)
	return wrap

# --- Texture helpers -------------------------------------------------------

# A TextureRect that draws `tex` inside a `size` x `size` box, aspect preserved,
# and renders it CRISPLY (nearest-neighbour) when the source is smaller than the
# box — small pixel art scaled up must not blur, while already-large art such as
# game cover scans keeps smooth filtering.
static func crisp_tex(tex: Texture2D, size: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_crisp(tr, tex)
	return tr

# The same rule applied to an existing TextureRect after its texture is assigned,
# for art that is set dynamically rather than at build time.
static func apply_crisp(tr: TextureRect, tex: Texture2D) -> void:
	var box: Vector2 = tr.custom_minimum_size
	if tex != null and (tex.get_width() < int(box.x) or tex.get_height() < int(box.y)):
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE

# --- Check boxes -----------------------------------------------------------
#
# The tick box the report checklist is built out of, drawn rather than themed:
# Godot's stock `checked`/`unchecked` icons are a hairline outline meant for a
# light editor theme, and against BG they read as an empty gap. These are 24px,
# 3px-bordered, and change COLOUR as well as contents between the two states, so
# "did I tick that one?" is answerable from across the panel.

const CHECK_ICON := 24               # icon edge in px
const CHECK_BORDER := 3              # border thickness

# Empty: a gold-rimmed hollow square. Ticked: green-rimmed, green-washed, with a
# heavy pale tick across it. `dim` is the disabled pair — same shapes, drained.
static func check_icon(ticked: bool, dim: bool = false) -> ImageTexture:
	var n := CHECK_ICON
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var border: Color = SUCCESS if ticked else GOLD.lerp(TEXT_DIM, 0.30)
	var fill: Color = SUCCESS.lerp(BG, 0.62) if ticked else BG.lerp(Color.BLACK, 0.30)
	var tick: Color = SUCCESS.lerp(Color.WHITE, 0.75)
	if dim:
		border = border.lerp(BG, 0.6)
		fill = fill.lerp(BG, 0.6)
		tick = tick.lerp(BG, 0.6)
	for y in range(n):
		for x in range(n):
			var edge: bool = x < CHECK_BORDER or y < CHECK_BORDER \
				or x >= n - CHECK_BORDER or y >= n - CHECK_BORDER
			img.set_pixel(x, y, border if edge else fill)
	if ticked:
		# Two strokes, drawn fat: the short down-leg then the long up-stroke.
		_stroke(img, Vector2(5.5, 12.0), Vector2(10.0, 17.0), tick, 3.0)
		_stroke(img, Vector2(10.0, 17.0), Vector2(18.5, 6.5), tick, 3.0)
	return ImageTexture.create_from_image(img)

# Paint a `width`-thick line into `img` by distance-to-segment, so the diagonal
# leg of the tick comes out even rather than stair-stepped.
static func _stroke(img: Image, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var seg: Vector2 = to - from
	var len_sq: float = seg.length_squared()
	var half: float = width * 0.5
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var t: float = 0.0 if len_sq <= 0.0 else clampf((p - from).dot(seg) / len_sq, 0.0, 1.0)
			var d: float = p.distance_to(from + seg * t)
			if d <= half:
				img.set_pixel(x, y, color)
			elif d <= half + 1.0:
				# One pixel of feathering, so the stroke isn't jagged.
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(color, half + 1.0 - d))

# --- Theme -----------------------------------------------------------------

# One Theme shared by all 2.0 screens. Assign with `theme = UITheme.make_theme()`
# on the screen root; children inherit it. Cheap to rebuild, but callers usually
# cache it via `shared()`.
static var _shared: Theme = null

static func shared() -> Theme:
	if _shared == null:
		_shared = make_theme()
	return _shared


# Put the shared theme on a subtree the screen's own theme cannot reach.
#
# A theme travels down CONTROL parents. Every 2.0 modal mounts itself on a
# CanvasLayer of its own so it floats above a page that scrolls — and a
# CanvasLayer is not a Control, so the chain stops dead there and everything
# inside comes up in Godot's stock light grey. (The window's theme is no help
# either; it does not cross the layer.) Each of those roots calls this on itself,
# which is one line each and the only thing that works.
static func dress(control: Control) -> void:
	if control != null and control.theme == null:
		control.theme = shared()

# --- the glyph font --------------------------------------------------------
#
# THE UI IS DRAWN OUT OF SYMBOLS — ⚔ ☠ ⚡ 🏆 🎲 🍀 ⛏ ⚗ and about seventy more —
# and Godot's built-in font has exactly two of them. A miss is answered by
# searching the HOST's installed fonts, during shaping, and the answer is not
# cached: measured, that is ~2 ms every time a Label carrying one is created, and
# it was half the cost of a full overworld repaint. It also meant those glyphs
# were drawn from whatever the player happened to have installed, so the game
# looked different on different machines — the same ⚗ beige here and purple
# there, and the colour-emoji fonts a modern desktop ships ignore the tint the
# theme asks for, which is how a green SHOP badge got a blue trolley in it.
#
# So the glyphs are SHIPPED: four Noto subsets under fonts/, holding only the
# characters this project actually draws, about 25 KB in total, built by
# tools/build_glyph_font.py (run it when the set of glyphs changes; it reports
# anything it could not cover). They are declared as FALLBACKS on Godot's own
# font rather than replacing it, so every letter of ordinary text is rendered by
# exactly the font it was before and only the symbols move.
#
# Monochrome on purpose — see the note in the build script. A glyph that carries
# its own colours cannot be tinted, and tinting them is how the page tells Bash
# from Dash.
const GLYPH_FONTS := [
	"res://fonts/NotoSansSymbols2-Subset.ttf",
	"res://fonts/NotoEmoji-Subset.ttf",
	"res://fonts/NotoSansSymbols-Subset.ttf",
	"res://fonts/NotoSansMath-Subset.ttf",
]

static var _glyph_font: Font = null

# Godot's default font with the shipped symbol subsets chained behind it. Null
# only if the base font is somehow unavailable, in which case every screen keeps
# working exactly as it did before this existed — the host search comes back.
#
# THE ORDER IS THE WHOLE POINT, and it took measuring to get right. Declaring the
# subsets as fallbacks is not enough on its own: the BASE font runs its own
# system search on a miss, and it runs it BEFORE the fallbacks are consulted, so
# the expensive thing still happened and the subsets were answering a question
# already answered. Turning that search off on the base and putting a
# system-searching font at the END of the chain gets both halves — the subsets
# are asked first and answer instantly, and anything they don't have (a player's
# note in a language we ship no glyphs for, a symbol added to the UI before this
# font was rebuilt) still falls through to the host exactly as it always did.
#
# Measured, on a Label carrying ten glyphs:
#     base search on, no subsets  (as it was)   15.4 ms
#     subsets declared, base search still on    12.4 ms
#     subsets, base search off, system last      4.5 ms
# and a character NOTHING here ships still renders, off the tail of the chain.
static func glyph_font() -> Font:
	if _glyph_font != null:
		return _glyph_font
	var base: Font = ThemeDB.fallback_font
	if base == null:
		return null
	var fallbacks: Array[Font] = []
	for path in GLYPH_FONTS:
		if ResourceLoader.exists(path):
			var f: Font = load(path)
			if f != null:
				fallbacks.append(f)
	if fallbacks.is_empty():
		return null
	# Duplicated, because ThemeDB.fallback_font is Godot's own shared resource and
	# the rest of the engine is entitled to find it as it was.
	if base is FontFile:
		var quiet: FontFile = (base as FontFile).duplicate()
		quiet.allow_system_fallback = false
		base = quiet
	# The safety net, last: everything the subsets don't carry still renders.
	var host := SystemFont.new()
	host.allow_system_fallback = true
	fallbacks.append(host)
	var variation := FontVariation.new()
	variation.base_font = base
	variation.fallbacks = fallbacks
	_glyph_font = variation
	return _glyph_font

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	# Every Control under this theme, unless it overrides its own font.
	var glyphs: Font = glyph_font()
	if glyphs != null:
		t.default_font = glyphs

	# --- Button ---
	var btn_n := flat(PANEL, 8, 8, 1, BORDER)
	btn_n.content_margin_left = 14
	btn_n.content_margin_right = 14
	var btn_h := flat(PANEL_HI, 8, 8, 1, ACCENT.lerp(BORDER, 0.35))
	btn_h.content_margin_left = 14
	btn_h.content_margin_right = 14
	var btn_p := flat(ACCENT_DIM.lerp(BG, 0.35), 8, 8, 1, ACCENT)
	btn_p.content_margin_left = 14
	btn_p.content_margin_right = 14
	var btn_d := flat(BG, 8, 8, 1, BORDER.lerp(BG, 0.5))
	btn_d.content_margin_left = 14
	btn_d.content_margin_right = 14
	var btn_f := flat(PANEL_HI, 8, 8, 2, ACCENT)
	btn_f.content_margin_left = 14
	btn_f.content_margin_right = 14
	t.set_stylebox("normal", "Button", btn_n)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("disabled", "Button", btn_d)
	t.set_stylebox("focus", "Button", btn_f)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)
	t.set_color("font_focus_color", "Button", GOLD)

	# --- CheckBox --- (transparent so it sits on panels cleanly)
	var clear := StyleBoxEmpty.new()
	t.set_stylebox("normal", "CheckBox", clear)
	t.set_stylebox("hover", "CheckBox", clear)
	t.set_stylebox("pressed", "CheckBox", clear)
	t.set_stylebox("focus", "CheckBox", clear)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	# Godot's stock check glyphs are a thin grey outline drawn for a light theme,
	# and on these near-black panels they all but vanish — the report checklist is
	# the one place the player is actually ANSWERING something, so its boxes are
	# drawn here instead: a chunky bordered square, gold-rimmed when empty and
	# filled green with a heavy tick when answered.
	t.set_icon("unchecked", "CheckBox", check_icon(false))
	t.set_icon("checked", "CheckBox", check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", check_icon(false, true))
	t.set_icon("checked_disabled", "CheckBox", check_icon(true, true))
	t.set_icon("radio_unchecked", "CheckBox", check_icon(false))
	t.set_icon("radio_checked", "CheckBox", check_icon(true))
	t.set_icon("radio_unchecked_disabled", "CheckBox", check_icon(false, true))
	t.set_icon("radio_checked_disabled", "CheckBox", check_icon(true, true))
	t.set_constant("h_separation", "CheckBox", 10)
	t.set_constant("check_v_offset", "CheckBox", 0)

	# --- Panel / PanelContainer ---
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())

	# --- Label ---
	t.set_color("font_color", "Label", TEXT)

	# --- RichTextLabel ---
	t.set_color("default_color", "RichTextLabel", TEXT)

	# --- LineEdit ---
	var le := flat(BG, 6, 6, 1, BORDER)
	t.set_stylebox("normal", "LineEdit", le)
	var le_f := flat(BG, 6, 6, 2, ACCENT)
	t.set_stylebox("focus", "LineEdit", le_f)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)

	# --- OptionButton --- (reuse the button look)
	t.set_stylebox("normal", "OptionButton", btn_n.duplicate())
	t.set_stylebox("hover", "OptionButton", btn_h.duplicate())
	t.set_stylebox("pressed", "OptionButton", btn_p.duplicate())
	t.set_stylebox("focus", "OptionButton", btn_f.duplicate())
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", GOLD)

	# --- Separators ---
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = BORDER
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	# --- Scrollbars ---
	# Godot's stock bar is a light-grey capsule on a light-grey trough, drawn for
	# the editor's theme: on these near-black pages it is the one control that
	# still looks like it came from a different program. It is also the only piece
	# of chrome the player touches on every screen — the overworld, the Collection,
	# the Atlas, every modal with a long list — so it gets the same treatment the
	# buttons got: a dark inset trough and an ember grabber that lights on hover.
	#
	# Both axes, and `grabber_pressed` as well as `grabber_highlight`, because a
	# bar you are dragging that stops reacting reads as a dropped drag.
	for axis in ["VScrollBar", "HScrollBar"]:
		var trough := StyleBoxFlat.new()
		trough.bg_color = BG_DEEP.lerp(BG, 0.5)
		trough.set_corner_radius_all(6)
		var grab := StyleBoxFlat.new()
		grab.bg_color = BORDER.lerp(ACCENT, 0.25)
		grab.set_corner_radius_all(6)
		var grab_hi := StyleBoxFlat.new()
		grab_hi.bg_color = ACCENT.lerp(BORDER, 0.35)
		grab_hi.set_corner_radius_all(6)
		var grab_press := StyleBoxFlat.new()
		grab_press.bg_color = ACCENT
		grab_press.set_corner_radius_all(6)
		# Slim: the margins run along the bar's thin axis, so the grabber is a
		# stripe down the middle of the trough rather than filling it.
		for sb in [trough, grab, grab_hi, grab_press]:
			if axis == "VScrollBar":
				sb.content_margin_left = 3
				sb.content_margin_right = 3
			else:
				sb.content_margin_top = 3
				sb.content_margin_bottom = 3
		t.set_stylebox("scroll", axis, trough)
		t.set_stylebox("scroll_focus", axis, trough)
		t.set_stylebox("grabber", axis, grab)
		t.set_stylebox("grabber_highlight", axis, grab_hi)
		t.set_stylebox("grabber_pressed", axis, grab_press)
	return t
