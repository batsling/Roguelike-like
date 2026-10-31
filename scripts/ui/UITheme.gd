class_name UITheme
extends RefCounted

# Shared visual language for the games-first (2.0) UI. The screens are built in
# code, so before this they each hand-rolled their own colours and styleboxes and
# drifted apart. This centralises the palette — a warm, dark, parchment-and-ember
# fantasy look carried over from the original web build (its styles.css)
# — plus a ready-made Godot Theme so every Button / Panel / Label / input picks up
# a consistent style just by setting `theme = UITheme.make_theme()` on a screen
# root. Individual stylebox overrides (rarity tiles, enemy cards) still win where a
# screen needs something bespoke.

# --- Palette ---------------------------------------------------------------
# The surfaces come in palettes, one per backdrop that was on trial beside the
# main menu's red vortex: each is the five surfaces below plus the bat pattern's
# ground and bat. PALETTE names the one in use; the owner chose "rift" (31 Oct
# 2026). The others stay so a retune is one word.
const PALETTES := {
	"grey": {
		"well": Color(0.055, 0.053, 0.051),
		"bg_deep": Color(0.102, 0.098, 0.094),
		"bg": Color(0.125, 0.122, 0.118),
		"panel": Color(0.161, 0.157, 0.153),
		"panel_hi": Color(0.204, 0.200, 0.192),
		"border": Color(0.294, 0.286, 0.275),
		"bat_ground": Color("3b3a39"),
		"bat": Color("2f2e2d"),
	},
	"oxblood": {
		"well": Color(0.060, 0.039, 0.041),
		"bg_deep": Color(0.100, 0.065, 0.068),
		"bg": Color(0.125, 0.081, 0.085),
		"panel": Color(0.160, 0.104, 0.109),
		"panel_hi": Color(0.205, 0.133, 0.140),
		"border": Color(0.300, 0.195, 0.204),
		"bat_ground": Color(0.240, 0.132, 0.142),
		"bat": Color(0.165, 0.091, 0.097),
	},
	"crimson": {
		"well": Color(0.060, 0.033, 0.035),
		"bg_deep": Color(0.100, 0.055, 0.059),
		"bg": Color(0.125, 0.069, 0.074),
		"panel": Color(0.160, 0.088, 0.094),
		"panel_hi": Color(0.205, 0.113, 0.121),
		"border": Color(0.300, 0.165, 0.177),
		"bat_ground": Color(0.260, 0.091, 0.106),
		"bat": Color(0.175, 0.061, 0.071),
	},
	"rift": {
		"well": Color(0.060, 0.027, 0.030),
		"bg_deep": Color(0.100, 0.045, 0.050),
		"bg": Color(0.125, 0.056, 0.062),
		"panel": Color(0.160, 0.072, 0.080),
		"panel_hi": Color(0.205, 0.092, 0.102),
		"border": Color(0.300, 0.135, 0.150),
		"bat_ground": Color(0.300, 0.045, 0.068),
		"bat": Color(0.195, 0.029, 0.044),
	},
	"red_on_grey": {
		"well": Color(0.060, 0.053, 0.053),
		"bg_deep": Color(0.100, 0.088, 0.089),
		"bg": Color(0.125, 0.110, 0.111),
		"panel": Color(0.160, 0.141, 0.143),
		"panel_hi": Color(0.205, 0.180, 0.183),
		"border": Color(0.300, 0.264, 0.267),
		"bat_ground": Color("3b3a39"),
		"bat": Color(0.380, 0.095, 0.121),
	},
	"ember_black": {
		"well": Color(0.060, 0.036, 0.038),
		"bg_deep": Color(0.100, 0.060, 0.064),
		"bg": Color(0.125, 0.075, 0.079),
		"panel": Color(0.160, 0.096, 0.102),
		"panel_hi": Color(0.205, 0.123, 0.130),
		"border": Color(0.300, 0.180, 0.191),
		"bat_ground": Color(0.090, 0.045, 0.049),
		"bat": Color(0.270, 0.054, 0.073),
	},
}
const PALETTE := "rift"
const BG_DEEP: Color = PALETTES[PALETTE]["bg_deep"]     # page background
const BG: Color = PALETTES[PALETTE]["bg"]               # base surface
const PANEL: Color = PALETTES[PALETTE]["panel"]         # raised panel
const PANEL_HI: Color = PALETTES[PALETTE]["panel_hi"]   # hover / header
const BORDER: Color = PALETTES[PALETTE]["border"]       # hairline border
const WELL: Color = PALETTES[PALETTE]["well"]           # the darkest recess: pips, pills, ink on a chip

const ACCENT := Color(1.0, 0.541, 0.235)          # #ff8a3c ember orange
const ACCENT_DIM := Color(0.80, 0.40, 0.0)        # #cc6600 pressed / muted ember
const GOLD := Color(1.0, 0.80, 0.40)              # #ffcc66 highlight gold
const TEXT := Color(0.902, 0.835, 0.722)          # #e6d5b8 parchment text
const TEXT_DIM := Color(0.639, 0.624, 0.596)      # #a39f98 secondary text
const TEXT_FAINT := Color(0.45, 0.44, 0.42)       # tertiary / placeholders

const SUCCESS := Color(0.30, 0.78, 0.42)
# THE GO BUTTON: a green fill and rim for the one action a panel is there for
# (Play, Use, the active profile). Five screens each typed these in by hand.
const GO_FILL := Color(0.10, 0.22, 0.16)
const GO_FILL_HI := Color(0.14, 0.30, 0.21)
const GO_RIM := Color(0.4, 0.9, 0.6)
const GO_RIM_HI := Color(0.55, 1.0, 0.75)

# A STOP THE RUN WALKED AWAY FROM — a game visited and left standing, whether the
# goal was missed, the run escaped it (§3.2), or a teleport passed straight
# through without playing at all. Those are one colour because they are one fact:
# you were there and the game is still standing.
#
# Its own value rather than ACCENT, which the road already spends on "you are
# here": at a 1px border the two would be telling different things in nearly the
# same orange. This one is deeper and browner, and reads as orange beside SUCCESS
# green without competing with the accent ring on the current stop.
const UNBEATEN := Color(0.85, 0.47, 0.12)        # #d97821
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

# RIFTS (docs/rifts-design.md §9): a game pulled into the map through a rift, not
# along an influence. A cold teal on a deep violet, the one pairing nothing else on
# the page uses — every warm colour here is already a claim (the Amulet, coins, the
# run's accent) and a rift is the one stop that is NOT an influence, so it should
# look like it came from somewhere else. RIFT is the line, badge and frame;
# RIFT_DEEP the dark of the swirl behind a rift card's cover.
const RIFT := Color(0.40, 0.92, 0.88)
const RIFT_DEEP := Color(0.20, 0.08, 0.34)
const RIFT_SHADER := preload("res://shaders/rift_swirl.gdshader")

# ---------------------------------------------------------------------------
# The type scale
# ---------------------------------------------------------------------------
#
# This file had a thorough colour system and nothing at all for the other two
# axes, so every font size and every gap in the game was a bare integer typed at
# its call site. A count of them: 25 distinct font sizes across the project —
# 105 uses of `12`, 71 of `11`, 62 of `13` — which is three sizes doing one job
# with nothing to say which is which, plus a long tail of one-offs.
#
# THE VALUES HERE ARE THE VALUES THAT WERE ALREADY BEING USED. Naming them is the
# whole change: nothing moves, nothing needs re-fitting, and the 720p budget the
# run screens are built to is untouched. What it buys is that the set is now
# countable and the next size someone reaches for is a named step rather than a
# fresh integer.
#
# If the size you want is not on this list, take the nearest one. A genuine
# one-off (a single hero line on a single screen) can stay a literal, but write
# down why — `test_type_scale.gd` scans the run screens and will ask.
const FONT_MICRO := 9        # a counter inside a badge
const FONT_TINY := 10        # a card's distance line, a pack tile's count
const FONT_SMALL := 11       # chips, badges, the second line of a row
const FONT_BODY := 12        # the UI's default line — buttons, most labels
const FONT_TEXT := 13        # prose meant to be READ rather than scanned
const FONT_LABEL := 14       # a named value beside its number
const FONT_LEAD := 15        # the first line of a block
const FONT_SUB := 16         # a sub-heading inside a panel
const FONT_HEAD := 18        # a panel's own heading
const FONT_TITLE := 20       # a screen's title
const FONT_TITLE_LG := 22    # a screen's title, where it is the subject
const FONT_DISPLAY := 26     # a verdict, a name at full size
const FONT_HERO := 28        # the largest thing on a screen

# ---------------------------------------------------------------------------
# The spacing scale
# ---------------------------------------------------------------------------
#
# Same story: ~20 distinct separation values, 60 uses of `8`, 56 of `6`, 43 of
# `10`. Same rule — these are the values already in use, named.
#
# EVERY GAP IN THE PROJECT IS ON THIS SCALE NOW. The 57 that sat between two
# steps were snapped by one rule, so none of them was a separate taste call: a
# value exactly between two steps goes to the SMALLER one (1->0, 3->2, 5->4,
# 7->6, 9->8, 14->12), and 18 to 16. A snap can therefore only take height away,
# never add it — which is what made it safe on the run's page, fitted to a 720p
# canvas with single digits to spare. The one exception is GAP_BREAK below.
const GAP_NONE := 0
const GAP_HAIR := 2
const GAP_TIGHT := 4
const GAP_SNUG := 6
const GAP := 8               # the default gap between two things in a stack
const GAP_WIDE := 10
const GAP_LOOSE := 12
const GAP_SECTION := 16      # between one section of a screen and the next
# Between the major blocks of a FULL screen — the run-over verdict and its route,
# the post-game haul's two halves. Added for the two gaps (22 and 26) that sat
# above the top step: snapping them to 16 squashed the two roomiest screens.
const GAP_BREAK := 24

# ---------------------------------------------------------------------------
# The z-order
# ---------------------------------------------------------------------------
#
# Every CanvasLayer number in the game, in one list. They were bare integers
# spread across ten files — 122, 123, 124, 128, 130, 131, 135, 136, 138, 140,
# 150 — describing a single global invariant that could only be checked by
# grepping for it, and the README's prose was the only place the order was
# written down. That has already cost something: the map opens above the haul
# screen, which is why `Overworld2._dismiss_route_map` has to exist.
#
# Read it top to bottom: later entries draw over earlier ones.
class Layer:
	const PICK_BANNER := 110   # "click a piece in your pack" — a caption on the page
	const MENU_SCREEN := 120   # a screen the MAIN MENU raises (custom run)
	const DROP := 122          # loot drop, an object's card
	const EVENT := 123         # the D20 event, the boss notice
	const CHOICE := 124        # an offered game's card
	const POST_COMBAT := 128   # the haul a game ends on
	const MAP := 130           # the route ladder, a loot use, a reading card
	const POST_COMBAT_CARD := 131  # a card opened off the haul screen
	const HEADER := 135        # the run's pinned bar — over the gameplay modals
	const START := 136         # the opening choose-a-road screen
	const START_MODAL := 138   # what that screen opens over itself
	const FULL_SCREEN := 140   # the star chart, a destructive confirm
	const CONFIRM := 141       # an event's confirm, over the chart
	const VERDICT := 150       # the run is over; nothing outranks this

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
static func chip(text: String, color: Color, font_size: int = FONT_SMALL) -> Control:
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

# --- Tier badges -----------------------------------------------------------
#
# WHERE THE PLAYER PUT THIS GAME, drawn in the top-right corner of its box art.
# The tier list (TierList, the cross-run store) is the one opinion the player has
# recorded about a game, and until now it was only readable on the tier-list
# screen — so every other screen that shows a cover at any size was showing a
# game the player had already ranked and saying nothing about it. A cover with an
# "S" on it answers "have I played this, and what did I think" before the name is
# read.
#
# THE COLOURS LIVE HERE NOW rather than on TierListScreen, which is where they
# were. Two screens drawing the same tier in two different colours is the one
# failure this badge cannot survive — the colour IS the content — so there is one
# list and the tier screen reads it out of here (its own TIER_COLORS is kept as
# an alias so nothing that named it has to change).
const TIER_COLORS := [
	Color(0.95, 0.42, 0.42), Color(0.97, 0.66, 0.4), Color(0.97, 0.85, 0.42),
	Color(0.66, 0.88, 0.5), Color(0.5, 0.78, 0.95), Color(0.76, 0.6, 0.95),
]

# Cycled, because the player's tier NAMES are editable and the file may hold more
# rows than there are colours here.
static func tier_color(index: int) -> Color:
	if index < 0:
		return TEXT_FAINT
	return TIER_COLORS[index % TIER_COLORS.size()]

# The badge's height, and where it sits relative to the corner. A pill rather
# than a fixed square: tier names are free text (§TierList.set_tier_name), so "S"
# draws as a circle and "Masterpiece" draws as a capsule of the same height with
# the whole word in it. The name is never truncated — a tier the player renamed
# is a tier they care about the wording of.
const TIER_BADGE_H := 22

# CENTRED ON THE CORNER, not tucked inside it: the badge's own centre sits on the
# art's top-right corner, so it reads as a mark pinned TO the picture rather than
# as something printed on it, and it gives back the corner of the art it was
# covering. 0.5 is exactly centred; 0.0 would put it back flush inside the edge.
const TIER_BADGE_OUT := 0.5
# Under this the art is too small to give a corner away — a cover that narrow is
# already a thumbnail, and a 22px pill on it is a label with a picture behind it
# rather than the other way round. It is the FLOOR and not the rule: which
# screens carry the badge at all is each screen's own call, and this only stops a
# 54px row thumbnail wearing one if a caller hands it over.
const TIER_BADGE_MIN_ART := 72.0

# The pill for `game_id`, or null when the player has not placed that game in a
# tier (which is most games, most of the time — an unranked game draws nothing
# rather than drawing an empty badge).
static func tier_badge(game_id, height: int = TIER_BADGE_H) -> Control:
	var tier: int = TierList.tier_of(game_id)
	if tier < 0:
		return null
	var name: String = ""
	if tier < TierList.tier_names.size():
		name = String(TierList.tier_names[tier])
	if name == "":
		return null
	var color: Color = tier_color(tier)
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(height, height)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Filled with the tier's own colour rather than tinted towards the background
	# the way `chip` is: this badge sits on box art, which is any colour at all,
	# and the only thing that reads on all of it is a solid plate with a dark
	# outline around it.
	wrap.add_theme_stylebox_override("panel",
		flat(color, height / 2, 0, 1, BG_DEEP))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(margin)
	var l := Label.new()
	l.text = name
	l.add_theme_font_size_override("font_size", FONT_TEXT)
	# Dark on the bright plate. Every tier colour is a pastel, so the readable
	# text on all six is the same near-black rather than a per-tier choice.
	l.add_theme_color_override("font_color", WELL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(l)
	return wrap

# Hang the badge in the top-right corner of `art` — the ONE call every screen
# makes, so the badge is in the same corner at the same size everywhere and a
# screen that shows a cover cannot get it subtly wrong.
#
# `art` is the Control the picture is drawn in (a TextureRect, usually): the
# badge becomes its child and anchors to its corner, so it follows the art
# wherever the layout puts it without the caller doing any arithmetic. A
# no-op for an unranked game, a null art, or art too small to spare the corner
# — so callers can hand it everything and let the rules decide.
static func attach_tier_badge(art: Control, game_id, min_art: float = TIER_BADGE_MIN_ART) -> void:
	if art == null or not is_instance_valid(art):
		return
	# A CONTAINER LAYS OUT EVERY CHILD IT HAS, anchors and all, so a badge added to
	# one is not a badge in a corner — it is stretched to fill the whole box, and
	# the first thing this drew was a solid tier-coloured rectangle over every
	# ranked cover in the collection. The picture inside is a plain Control and
	# anchors fine, and it has already been fitted to the container, so its corner
	# IS the container's corner: hand the badge to it instead.
	if art is Container:
		for child in art.get_children():
			if child is Control and not (child is Container):
				attach_tier_badge(child, game_id, min_art)
				return
		return
	var box: Vector2 = art.custom_minimum_size
	if box.x <= 0.0:
		box = art.size
	if min_art > 0.0 and box.x > 0.0 and box.x < min_art:
		return
	var badge: Control = tier_badge(game_id)
	if badge == null:
		return
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_END
	# Half the badge hangs outside the art on each of the two edges it meets, which
	# is what "centred on the corner" means. It is the HEIGHT on both axes and not
	# the width: a long tier name grows to the LEFT (grow_horizontal BEGIN), so the
	# amount standing outside the right edge is the same for "S" and for
	# "Masterpiece" and the corner always looks alike.
	var out: float = float(tier_badge_overhang())
	badge.offset_right = out
	badge.offset_top = -out
	# ON THE PICTURE'S CORNER, not the box's. A TextureRect that letterboxes
	# (KEEP_ASPECT_CENTERED) and is handed a box wider than its picture draws the
	# picture in the middle of it, and a badge on the box's corner then floats in
	# the empty band beside the art: the Atlas card's cover, stretched to the
	# card's width, wore its badge at the card's edge. So it follows the drawn
	# picture whenever the box is resized.
	if art is TextureRect and (art as TextureRect).stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		var tr := art as TextureRect
		var place := func() -> void:
			if tr.texture == null or not is_instance_valid(badge):
				return
			var tex: Vector2 = tr.texture.get_size()
			if tex.x <= 0.0 or tex.y <= 0.0 or tr.size.x <= 0.0 or tr.size.y <= 0.0:
				return
			var k: float = minf(tr.size.x / tex.x, tr.size.y / tex.y)
			var drawn: Vector2 = tex * k
			badge.offset_right = out - (tr.size.x - drawn.x) * 0.5
			badge.offset_top = -out + (tr.size.y - drawn.y) * 0.5
		tr.resized.connect(place)
	# ANYTHING THAT CLIPS WOULD CUT IT IN QUARTERS. The badge deliberately overhangs
	# now, and several of these covers sit inside a parent with `clip_contents` on
	# (the collection's plate rounds off square art that way, the route strip and
	# the atlas canvas scroll). Clipping is the parent's business and not something
	# to switch off from here — so the callers that clip hand the badge a parent
	# that does not, and this only has to not clip itself.
	art.clip_contents = false
	art.add_child(badge)

# A RIFT THAT NEEDS A KEY wears one: a 🗝 disc centred on the BOTTOM edge of its
# cover, half hanging off it, so the price is on the picture itself and a keyed
# rift card reads differently from a rift that is simply on the map
# (docs/rifts-design.md §8). The top-right corner is the tier badge's, which is
# why this is the bottom. Follows the drawn picture under a letterbox, the same
# way the tier badge does. `lift` raises it off the edge, for a cover whose
# bottom middle already carries a RankBadge (the game popup).
const KEY_BADGE_SIZE := 28

static func attach_key_badge(art: Control, lift: float = 0.0) -> void:
	if art == null or not is_instance_valid(art):
		return
	var badge := PanelContainer.new()
	badge.name = "KeyBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", flat(BG, KEY_BADGE_SIZE / 2, 0, 2, RIFT))
	var glyph := Label.new()
	glyph.text = "🗝"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", FONT_SUB)
	glyph.add_theme_color_override("font_color", GOLD)
	badge.add_child(glyph)
	badge.custom_minimum_size = Vector2(KEY_BADGE_SIZE, KEY_BADGE_SIZE)
	badge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var half: float = float(KEY_BADGE_SIZE) * 0.5
	badge.offset_left = -half
	badge.offset_right = half
	badge.offset_top = -half - lift
	badge.offset_bottom = half - lift
	if art is TextureRect and (art as TextureRect).stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		var tr := art as TextureRect
		var place := func() -> void:
			if tr.texture == null or not is_instance_valid(badge):
				return
			var tex: Vector2 = tr.texture.get_size()
			if tex.x <= 0.0 or tex.y <= 0.0 or tr.size.y <= 0.0:
				return
			var drawn_h: float = tex.y * minf(tr.size.x / tex.x, tr.size.y / tex.y)
			var gap: float = (tr.size.y - drawn_h) * 0.5 + lift
			badge.offset_top = -half - gap
			badge.offset_bottom = half - gap
		tr.resized.connect(place)
	art.clip_contents = false
	art.add_child(badge)

# HOW FAR THE BADGE STANDS OUT past the art's top and right edges.
static func tier_badge_overhang() -> int:
	return ceili(float(TIER_BADGE_H) * TIER_BADGE_OUT)

# `cover` with room kept for its tier badge's overhang: a MarginContainer with the
# overhang as its top and right margins, or `cover` itself for an unranked game.
#
# The badge hangs half off the corner by design, and that half lands on whatever
# is next to the cover: under the text beside it (laid out after it, so drawn on
# top), or past the edge of a scroll area, which cuts it off. The Collection's
# game page and the game popup lost the top of the badge and its right side to
# exactly those two. Handing the layout the overhang as margin is what gives the
# badge somewhere to hang. Call it on the OUTERMOST box of the cover (after
# RankBadge.wrap, which owns the bottom overhang).
static func tier_badge_room(cover: Control, game_id) -> Control:
	if cover == null or TierList.tier_of(game_id) < 0:
		return cover
	var out: int = tier_badge_overhang()
	var room := MarginContainer.new()
	room.name = "TierBadgeRoom"
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.size_flags_horizontal = cover.size_flags_horizontal
	room.size_flags_vertical = cover.size_flags_vertical
	room.add_theme_constant_override("margin_top", out)
	room.add_theme_constant_override("margin_right", out)
	room.add_theme_constant_override("margin_left", 0)
	room.add_theme_constant_override("margin_bottom", 0)
	room.add_child(cover)
	return room

# --- General art -----------------------------------------------------------
#
# images2.0/general/ is the art that belongs to no one piece of content: symbols
# the UI itself is written in, used wherever the rule they stand for applies.
# Preloaded rather than looked up per call — they are two small sprites drawn
# dozens of times a repaint, and a `load()` on each would be a disk hit per pip.

# The armour a game grants (§3). One sprite per point, over the hero.
const SHIELD_ART: Texture2D = preload("res://images2.0/general/Shield.png")

# THE CLOCK. Anything TEMPORARY carries it in its bottom-right corner — a status
# borrowed for a game or two (docs/potions-design.md §5.3), a shield that expires
# when this game is reported. It is one badge with one meaning: what it is on is
# going away, and the tooltip says when.
const TIMER_ART: Texture2D = preload("res://images2.0/general/Timer.png")

# How much of the icon the clock takes, the floor it never goes under, and how
# far it hangs off the corner.
#
# THE FLOOR IS THE POINT. The badge is a stopwatch — a ring, a face and two hands
# — and at half of a 16px enemy pip it stopped being any of those and became a
# pale smudge in the corner. Below about 14px there is no drawing that survives,
# so the small pips get a badge that is large RELATIVE to them and overhangs
# further, which is the trade a corner badge is for: the art it sits on is still
# recognisable with a bite out of one corner, and an unreadable badge is worth
# nothing at any size.
const TIMER_FRACTION: float = 0.5
const TIMER_MIN: int = 14
const TIMER_OVERHANG: float = 0.3

# `tex` at `size`, with the clock in its corner when `timed`. Returns the plain
# TextureRect otherwise, so an untimed icon costs exactly what it did before this
# badge existed.
static func timed_art(tex: Texture2D, size: int, timed: bool) -> Control:
	var art := crisp_tex(tex, size)
	if not timed:
		return art
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size, size)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(art)
	var badge := crisp_tex(TIMER_ART, maxi(TIMER_MIN, int(round(size * TIMER_FRACTION))))
	var edge: float = badge.custom_minimum_size.x
	# Bottom-right, hanging off by TIMER_OVERHANG of its own edge. Anchored rather
	# than laid out: the clock is drawn OVER the art, and a container would push the
	# art aside to make room for it.
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -edge + edge * TIMER_OVERHANG
	badge.offset_top = -edge + edge * TIMER_OVERHANG
	badge.offset_right = edge * TIMER_OVERHANG
	badge.offset_bottom = edge * TIMER_OVERHANG
	wrap.add_child(badge)
	return wrap

# --- goal ADD-ON rows (§13) ------------------------------------------------
#
# A goal picks up clauses (GameLoop2.goal_addons_for), and until now every screen
# read them as one run-on sentence: "Defeat 10+ bugs and you must beat 2 bosses
# without getting hit or instead skip or trash 3 items/upgrades". Three different
# things joined by two conjunctions, in one colour, on one line — and the one
# question the player is asking of that line is which half of it makes the goal
# HARDER.
#
# So an add-on is drawn as its own indented row instead: the status's own symbol,
# then the phrase, in RED when the add-on is a condition added to the goal and
# GREEN when it is something offered (a second way out, or a free bonus). The
# colour is the whole point — it is the difference between "this is now also
# required of you" and "here is a way through" — so it lives here, once, rather
# than being decided by each screen that draws one.
#
# Both halves are static so the three screens that draw these (the game-choice
# modal, the enemy card, and the offering's hover line, which colours the words
# in place because it has only the one line) cannot disagree about which is which.
const ADDON_ICON: int = 18
const ADDON_INDENT: int = 14

static func addon_color(required: bool) -> Color:
	return DANGER if required else SUCCESS

# One add-on as a row. `addon` is a `GameLoop2.goal_addons_for` entry; `width` is
# the row's minimum, since these live in narrow columns and the phrase wraps.
static func addon_row(addon: Dictionary, width: float = 0.0,
		font_size: int = FONT_BODY) -> Control:
	var tint: Color = addon_color(bool(addon.get("required", false)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	# The indent is a spacer rather than a margin on the label: the icon has to be
	# indented with the words, or the row reads as a second goal rather than as
	# something hanging off the one above it.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(ADDON_INDENT, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	var status: StatusData = addon.get("status")
	if status != null and status.image != null:
		# The same chip the board's pips and the checklist's rows use, clock badge
		# and all — a borrowed clause is a different offer from a permanent one.
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel",
			flat(BG, 4, 2, 1, tint.lerp(BORDER, 0.35)))
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.add_child(timed_art(status.image, ADDON_ICON,
			int(addon.get("games", 0)) > 0))
		row.add_child(frame)
	var l := Label.new()
	# The joiner leads the phrase — "and", "or instead" — because it is what says
	# how this row relates to the goal above it, and a row that starts straight in
	# on the condition reads like a second goal. A bonus carries its own lead in its
	# wording and so has none here, which is why this joins rather than formats.
	l.text = ("%s %s" % [String(addon.get("joiner", "")),
		String(addon.get("text", ""))]).strip_edges()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", tint)
	if width > 0.0:
		l.custom_minimum_size = Vector2(width - ADDON_INDENT - ADDON_ICON - 12, 0)
	row.add_child(l)
	if status != null:
		row.tooltip_text = "%s — %s" % [status.display_name,
			("this is required of you as well" if bool(addon.get("required", false))
				else "this is offered, not required")]
	return row

# --- Texture helpers -------------------------------------------------------

# A TextureRect that draws `tex` inside a `size` x `size` box, aspect preserved,
# and renders it CRISPLY (nearest-neighbour) when the source is smaller than the
# box — small pixel art scaled up must not blur, while already-large art such as
# game cover scans keeps smooth filtering.
#
# `force` says "nearest-neighbour whatever the sizes are", for the few callers
# that know their art is a sprite even when it happens to be drawn small.
#
# THIS IS THE ONE COPY OF THE RULE. It has been written out by hand three times
# in this project — the Collection's own `_tex_rect`, the main menu's `_char_tex`
# and HoverCard's inline TextureRect (test_overworld2 has the regression that
# caught the last one) — and each hand-rolled copy is a place the game's pixel
# art can start blurring on its own.
# Cover art on a card is shown WHOLE — a card is where you went to LOOK at the
# game, so nothing is cropped off it. The frame is the size the picture actually
# needs: fitted to `width`, and shrunk further if that would make it taller than
# `max_height` — never letterboxed, never cut. Moved here from AtlasView (which
# forwards) so the route ladder's card can draw it without compiling the star
# chart into every page load.
const CARD_ART_MAX_HEIGHT := 300.0

static func card_art_size(tex: Texture2D, width: float,
		max_height: float = CARD_ART_MAX_HEIGHT) -> Vector2:
	if tex == null or width <= 0.0 or tex.get_width() <= 0 or tex.get_height() <= 0:
		return Vector2.ZERO
	var aspect: float = float(tex.get_height()) / float(tex.get_width())
	var box := Vector2(width, width * aspect)
	if max_height > 0.0 and box.y > max_height:
		box = Vector2(max_height / aspect, max_height)
	return box

static func card_art(tex: Texture2D, width: float,
		max_height: float = CARD_ART_MAX_HEIGHT) -> TextureRect:
	var art := TextureRect.new()
	art.texture = tex
	art.custom_minimum_size = card_art_size(tex, width, max_height)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# KEEP_ASPECT_CENTERED, not COVERED: the whole picture, letterbox rather than
	# crop if a container ever hands it a box of a different shape.
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return art

static func crisp_tex(tex: Texture2D, size: int, force: bool = false) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_crisp(tr, tex, force)
	return tr

# The same rule applied to an existing TextureRect after its texture is assigned,
# for art that is set dynamically rather than at build time.
static func apply_crisp(tr: TextureRect, tex: Texture2D, force: bool = false) -> void:
	if force or is_pixel_art(tex, tr.custom_minimum_size) or is_small_art(tex):
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE

# True when `tex` is smaller than the `box` it will be drawn in, so scaling it up
# would soften it — the cue that it is pixel art and wants nearest-neighbour.
# Public because a couple of callers draw the art themselves (the Collection's
# footprint board lays the enemy over the grid at a computed size) and still want
# the same answer this theme gives everything else.
static func is_pixel_art(tex: Texture2D, box: Vector2) -> bool:
	return tex != null and (tex.get_width() < int(box.x) or tex.get_height() < int(box.y))

# True when `tex` is small enough that it can only be pixel art, whatever box it is
# drawn in. `is_pixel_art` only catches art being blown UP; a 64px sprite shrunk
# into a 26px checklist chip, or drawn across a footprint the size of its own
# pixels, was left on linear filtering and came out soft — and the roster's
# smaller enemies (16x16 to ~120px) are exactly the ones drawn as pixel art.
const SMALL_ART_MAX := 128

static func is_small_art(tex: Texture2D) -> bool:
	return tex != null and maxi(tex.get_width(), tex.get_height()) <= SMALL_ART_MAX

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
#
# `armed` IS THE SECOND SHAPE, and it is a ROUND box rather than a square one.
#
# WHY A SECOND SHAPE EXISTS AT ALL. Every box on the report checklist looked the
# same while meaning two different things (docs/games-first-redesign.md §7.7).
# A SQUARE box RESOLVES: pressing it raises a confirm and then the enemy takes
# its hit, its loot lands on the board, and there are no take-backs. A ROUND box
# only ARMS: it is a claim you are holding, it goes on and off as often as you
# like, and handing the game in is what cashes it. That is the difference between
# an action and a promise, and it was carried by nothing but the section header
# the row happened to be under.
#
# Round for the promise is the right way round: a radio-ish ring already reads as
# "a state I am in" where a square reads as "a button I press", which is exactly
# the distinction being drawn. The COLOURS stay identical across both shapes, so
# ticked still reads as ticked at a glance and only the silhouette says which
# kind of row it is.
static func check_icon(ticked: bool, dim: bool = false,
		armed: bool = false) -> ImageTexture:
	var n := CHECK_ICON
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var border: Color = SUCCESS if ticked else GOLD.lerp(TEXT_DIM, 0.30)
	var fill: Color = SUCCESS.lerp(BG, 0.62) if ticked else BG.lerp(Color.BLACK, 0.30)
	var tick: Color = SUCCESS.lerp(Color.WHITE, 0.75)
	if dim:
		border = border.lerp(BG, 0.6)
		fill = fill.lerp(BG, 0.6)
		tick = tick.lerp(BG, 0.6)
	if armed:
		img.fill(Color(0, 0, 0, 0))
		# ANTI-ALIASED ON BOTH EDGES, by coverage. It used to test each pixel's
		# distance against the two radii and paint it one colour or the other, with
		# a single faded pixel outside — so the outer edge was soft and the INNER
		# one, where the gold ring meets the dark fill, was a hard staircase all the
		# way round. That inner edge is the one the eye reads as the circle. Each
		# pixel now takes how much of it lies inside each radius (a signed
		# distance, clamped to one pixel's width) and blends accordingly.
		var mid: float = n * 0.5
		var outer: float = mid - 0.75
		var inner: float = outer - CHECK_BORDER
		for y in range(n):
			for x in range(n):
				var d: float = Vector2(x + 0.5 - mid, y + 0.5 - mid).length()
				var in_outer: float = clampf(outer - d + 0.5, 0.0, 1.0)
				if in_outer <= 0.0:
					continue
				var in_inner: float = clampf(inner - d + 0.5, 0.0, 1.0)
				var c: Color = border.lerp(fill, in_inner)
				c.a *= in_outer
				img.set_pixel(x, y, c)
	else:
		for y in range(n):
			for x in range(n):
				var edge: bool = x < CHECK_BORDER or y < CHECK_BORDER \
					or x >= n - CHECK_BORDER or y >= n - CHECK_BORDER
				img.set_pixel(x, y, border if edge else fill)
	if ticked:
		# Two strokes, drawn fat: the short down-leg then the long up-stroke.
		# Pulled in a little on the round box so the long leg stays inside the ring.
		if armed:
			_stroke(img, Vector2(6.5, 12.0), Vector2(10.0, 16.0), tick, 3.0)
			_stroke(img, Vector2(10.0, 16.0), Vector2(17.0, 7.5), tick, 3.0)
		else:
			_stroke(img, Vector2(5.5, 12.0), Vector2(10.0, 17.0), tick, 3.0)
			_stroke(img, Vector2(10.0, 17.0), Vector2(18.5, 6.5), tick, 3.0)
	return ImageTexture.create_from_image(img)

# THE MARK A BODY'S GOAL WEARS WHEN BEATING THE GAME IS WHAT SETTLES IT — a
# pennant on a staff, drawn rather than shipped as a glyph.
#
# The rows in that section all lead with a picture that says whose goal it is: a
# status leads with its own symbol, the level-up with the character's face. A
# body leads with its portrait, which says which body but not which KIND of goal
# — and in a section where every other row is settled the same way, the flag is
# what marks the finish the row is waiting on.
#
# Drawn, not a glyph, so it needs no `tools/build_glyph_font.py` rebuild and
# cannot fall through to a host font search (CLAUDE.md).
static func finish_flag(size: int, tint: Color = GOLD) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var s: float = size / 22.0        # the shape is authored at 22px
	var staff_x: float = 6.0 * s
	_stroke(img, Vector2(staff_x, 3.5 * s), Vector2(staff_x, 18.5 * s),
		tint, maxf(1.5, 2.0 * s))
	# The pennant: a triangle off the top of the staff, filled by a point-in-
	# triangle test so the diagonal is even at any size.
	var a := Vector2(staff_x + 1.0 * s, 4.0 * s)
	var b := Vector2(17.0 * s, 8.0 * s)
	var c := Vector2(staff_x + 1.0 * s, 12.0 * s)
	for y in range(size):
		for x in range(size):
			var p := Vector2(x, y)
			if _in_triangle(p, a, b, c):
				img.set_pixel(x, y, tint)
	return ImageTexture.create_from_image(img)

static func _in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1: float = (p - b).cross(a - b)
	var d2: float = (p - c).cross(b - c)
	var d3: float = (p - a).cross(c - a)
	var neg: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var pos: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (neg and pos)

# The mark on a chosen row of a dropdown, and the nothing on an unchosen one.
#
# Godot's stock pair is drawn for a light theme — the same problem the CheckBox
# icons above were replaced for. On these panels the ticked one is a pale ring
# and the UNTICKED one is a faint dark square, so every row of an OptionButton's
# list wore a smudge and the one that was actually selected barely stood out from
# the ones that were not.
#
# Chosen is a solid accent dot; unchosen is EMPTY. A dropdown is a list of things
# you could pick, not a set of boxes to answer, so an unpicked row wants no mark
# at all — which also means the one with a mark is unmissable.
const POPUP_MARK := 16

static func popup_mark(on: bool) -> ImageTexture:
	var n := POPUP_MARK
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if on:
		var mid := (n - 1) * 0.5
		var r := n * 0.28
		for y in range(n):
			for x in range(n):
				# Distance-based, so the dot has a soft edge instead of a staircase.
				var d: float = Vector2(x - mid, y - mid).length()
				if d <= r:
					img.set_pixel(x, y, ACCENT)
				elif d <= r + 1.0:
					img.set_pixel(x, y, Color(ACCENT.r, ACCENT.g, ACCENT.b, r + 1.0 - d))
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

# The swirl behind a rift game's cover (rift_swirl.gdshader), as a full-rect
# ColorRect that ignores the mouse. `seed` staggers its phase so two rift cards
# side by side don't turn in step. The caller insets the cover over it, so the
# swirl shows as a ring round the art as well as in any letterbox.
static func rift_backdrop(seed: float = 0.0) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = RIFT_SHADER
	mat.set_shader_parameter("rift_color", RIFT)
	mat.set_shader_parameter("deep_color", RIFT_DEEP)
	mat.set_shader_parameter("base_color", BG_DEEP.lerp(RIFT_DEEP, 0.3))
	mat.set_shader_parameter("seed", seed)
	rect.material = mat
	return rect

# The bat pattern (menu_bats.gdshader) as a full-rect ColorRect that ignores the
# mouse: the owner's bat on their pattern's lattice, drifting down and to the left.
const BATS_SHADER := preload("res://shaders/menu_bats.gdshader")
const BATS_ART := preload("res://images2.0/custom/menu_bat.png")


static func bat_backdrop() -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BATS_SHADER
	mat.set_shader_parameter("bat", BATS_ART)
	mat.set_shader_parameter("base", PALETTES[PALETTE]["bat_ground"])
	mat.set_shader_parameter("ink", PALETTES[PALETTE]["bat"])
	rect.material = mat
	rect.resized.connect(func() -> void: mat.set_shader_parameter("size", rect.size))
	return rect

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

# --- Rogue's font, for headings and buttons -----------------------------------
#
# THE HEADINGS AND THE BUTTONS ARE SET IN THE FONT ROGUE WAS PLAYED IN (the owner,
# 31 Oct 2026, after seeing the whole UI in it: "do the headings and buttons
# version"). Px437 IBM VGA 8x16 (fonts/, CC BY-SA 4.0 — the title's starting
# letters are cut from the same font, tools/rogue_letters.py).
#
# IT IS A BITMAP FONT, DRAWN FOR 16px, and that decides everything here. At any
# other size its pixels land unevenly; below 16 it falls apart (the mock-up of the
# whole UI in it was unreadable in the 9–13px lines). So:
#   * only text at FONT_SUB (16) or larger becomes a heading, and a button whose
#     own size is at least FONT_BODY (12) — the chips and pills under that keep
#     the ordinary font;
#   * its size is SNAPPED to a whole multiple of 16 (`rogue_size`): 16 for every
#     heading up to FONT_TITLE_LG, 32 for the verdict-sized ones;
#   * antialiasing off and positions on whole pixels, so the pixels stay square.
#
# ONE RULE IN ONE PLACE rather than a hundred call sites: every Label and Button
# that enters the tree is looked at once, a frame later, after the code building
# it has set its size (`_on_node_added`, wired by Settings). Symbols the font lacks
# (⚔ ☠ 🏆 …) fall through to the glyph fonts as they always have.
const ROGUE_FONT_PATH := "res://fonts/Px437_IBM_VGA_8x16.ttf"
const ROGUE_PX := 16
# The rule is on unless something turns it off (a test that measures the
# ordinary font's metrics could; nothing does today).
static var rogue_headings: bool = true
static var _rogue_font: Font = null

static func rogue_font() -> Font:
	if _rogue_font != null:
		return _rogue_font
	var f: FontFile = null
	if ResourceLoader.exists(ROGUE_FONT_PATH):
		var res = load(ROGUE_FONT_PATH)
		if res is FontFile:
			f = (res as FontFile).duplicate()
	if f == null:
		# Not imported yet (a fresh checkout before the editor has scanned).
		f = FontFile.new()
		if f.load_dynamic_font(ProjectSettings.globalize_path(ROGUE_FONT_PATH)) != OK:
			return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.allow_system_fallback = false
	var chain: Array[Font] = []
	var glyphs: Font = glyph_font()
	if glyphs != null:
		chain.append(glyphs)
	f.fallbacks = chain
	_rogue_font = f
	return _rogue_font

# The crisp size for text that asked for `size`: 16, or 32 for the largest.
static func rogue_size(size: int) -> int:
	return ROGUE_PX * 2 if size >= FONT_DISPLAY else ROGUE_PX

# Whether `c` is set in Rogue's font: a heading-sized Label, or a Button whose
# text is at least FONT_BODY.
static func wants_rogue(c: Control) -> bool:
	if c is Label:
		return c.has_theme_font_size_override("font_size") \
			and c.get_theme_font_size("font_size") >= FONT_SUB
	if c is Button:
		# A button that WRAPS or runs to a second line is a sentence you click (a
		# checklist goal, the lost-run tracker), not a label on a button: in a
		# monospace font eight pixels to the letter it is cut off, so it reads in
		# the ordinary one.
		var b := c as Button
		if b.autowrap_mode != TextServer.AUTOWRAP_OFF or b.text.contains("\n"):
			return false
		return c.get_theme_font_size("font_size") >= FONT_BODY
	return false

# Set `c` in Rogue's font, at its snapped size. Safe to call twice.
static func use_rogue(c: Control) -> void:
	var f: Font = rogue_font()
	if f == null or c == null:
		return
	c.add_theme_font_override("font", f)
	c.add_theme_font_size_override("font_size", rogue_size(c.get_theme_font_size("font_size")))

static func _on_node_added(node: Node) -> void:
	if rogue_headings and (node is Label or node is Button):
		_apply_rogue_rule.call_deferred(node)

static func _apply_rogue_rule(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var c := node as Control
	# A control that chose its own font (the title letters' fallbacks, a
	# monospace readout) keeps it.
	if c.has_theme_font_override("font"):
		return
	if wants_rogue(c):
		use_rogue(c)

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_LABEL
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

	# --- PopupMenu ---
	#
	# THE LAST STOCK CONTROL IN THE GAME. This theme dressed Button, CheckBox,
	# Panel, Label, LineEdit, OptionButton, the separators and the scrollbars, and
	# never touched PopupMenu — so every dropdown in the project was still Godot's
	# default: a flat near-black slab with a blue selection bar and a grey-on-grey
	# heading, sitting on a page of warm brown panels and parchment text. That is
	# the run's `☰ Menu`, the Collection's type and record filters, the Atlas's
	# region picker and Custom Run's four filter columns — every one of them.
	#
	# Same surface as a panel, same ember hover as a button, so a dropdown looks
	# like the thing that opened it.
	var pop_bg := flat(PANEL, 8, 6, 1, BORDER)
	t.set_stylebox("panel", "PopupMenu", pop_bg)
	var pop_hover := flat(PANEL_HI, 6, 0, 1, ACCENT.lerp(BORDER, 0.35))
	t.set_stylebox("hover", "PopupMenu", pop_hover)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_FAINT)
	# A LABELLED separator is a group heading, so it is drawn like one: the accent,
	# not the same colour as the items under it. Godot draws the label centred on
	# the rule, which is exactly the shape a heading wants.
	t.set_color("font_separator_color", "PopupMenu", ACCENT)
	t.set_font_size("separator_font_size", "PopupMenu", FONT_SMALL)
	var pop_sep := StyleBoxLine.new()
	pop_sep.color = BORDER
	pop_sep.thickness = 1
	t.set_stylebox("separator", "PopupMenu", pop_sep)
	t.set_constant("v_separation", "PopupMenu", GAP_TIGHT)
	t.set_constant("item_start_padding", "PopupMenu", GAP_WIDE)
	t.set_constant("item_end_padding", "PopupMenu", GAP_WIDE)
	# The chosen row's mark. Every OptionButton in the project draws its list
	# through these — the Collection's type and record filters, the Atlas's mode
	# and region pickers, Custom Run's four columns, the Dash panel's type filter,
	# Settings' display and window-size lists — so a dropdown marks its selection
	# the same way everywhere. See `popup_mark`: an accent dot when chosen, and
	# nothing at all when not.
	for on_name in ["checked", "radio_checked"]:
		t.set_icon(on_name, "PopupMenu", popup_mark(true))
	for off_name in ["unchecked", "radio_unchecked"]:
		t.set_icon(off_name, "PopupMenu", popup_mark(false))

	# --- the stock tooltip ---
	#
	# Most hovers are a HoverCard (HoverPanel / HoverButton / HoverBox), but any
	# Control left on a plain `tooltip_text` gets Godot's stock tooltip, which was
	# grey system chrome. Dressed here as HoverCard.text_card is, so the stragglers
	# at least look like the same family. (It still cannot wrap: a long one wants
	# one of the Hover classes.)
	#
	# Godot wraps EVERY tooltip in a TooltipPanel, a HoverCard included — which drew
	# a second frame round each card. So the panel is empty and the box is the
	# stock LABEL's own (TooltipLabel is a Label variation), and a card is drawn
	# exactly as HoverCard built it.
	t.set_stylebox("panel", "TooltipPanel", StyleBoxEmpty.new())
	t.set_stylebox("normal", "TooltipLabel", flat(Color(BG_DEEP, 0.985), 6, 8, 1, BORDER))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FONT_BODY)

	# --- Window / AcceptDialog ---
	#
	# THE RUN'S SAVE AND EXIT PROMPTS WERE STOCK GREY. They are real Windows
	# (AcceptDialog / ConfirmationDialog), and a Window draws two things this theme
	# never named: its FRAME and title bar (`embedded_border` on Window) and the
	# body behind its text and buttons (`panel` on AcceptDialog). Their buttons and
	# line edit already came up in the game's look — Godot hands a parent's theme
	# down into a child window — so the dialogs read as a brown button stuck on a
	# grey slab. Named here, every dialog in the project takes the modal look: the
	# panel surface, an ember rim, and a gold title.
	#
	# The border box draws the title bar too, by reaching OUT past the window's
	# rect: `expand_margin_top` is the bar's height and must match `title_height`,
	# or the title is drawn half off its own bar.
	var title_h: int = 36
	var frame := flat(PANEL, 10, 0, 1, ACCENT.lerp(BORDER, 0.35))
	frame.set_expand_margin_all(GAP)
	frame.expand_margin_top = title_h
	t.set_stylebox("embedded_border", "Window", frame)
	var frame_dim: StyleBoxFlat = frame.duplicate()
	frame_dim.border_color = BORDER
	t.set_stylebox("embedded_unfocused_border", "Window", frame_dim)
	t.set_constant("title_height", "Window", title_h)
	t.set_color("title_color", "Window", GOLD)
	t.set_font_size("title_font_size", "Window", FONT_HEAD)
	t.set_stylebox("panel", "AcceptDialog", flat(PANEL, 0, GAP_LOOSE))
	t.set_constant("buttons_separation", "AcceptDialog", GAP_WIDE)

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
