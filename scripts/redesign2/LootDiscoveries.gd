class_name LootDiscoveries
extends RefCounted

# "KNOWN THIS RUN" — the record of what the run has identified, folded shut
# (docs/games-first-redesign.md §4.3).
#
# A pill is learned as a COLOUR and only for this run: the ten the run dealt, of
# thirteen that exist. Before this existed, the only time a colour was ever named
# was a toast that had scrolled away by the next game — an identification minigame
# with no record of itself, where a player who learned that green is Bad Trip on
# game three had nowhere to go and check on game eleven.
#
# WHAT IT WILL NOT SAY is which of the three spare colours sat out. Naming an
# unlearned pill would hand back exactly the deduction the spares exist to prevent
# — nine known colours must not tell you what the tenth is — so the unlearned are
# COUNTED and never listed.
#
# THREE ALPHABETS NOW (docs/potions-design.md). A potion is learned the same way
# and for the same run only: 15 of 37 vials are dealt and 22 mean nothing, which
# is a much bigger spare pile than the pills' three and the reason the fifteenth
# potion is undeducible. The unlearned are counted here too — and what the record
# never writes down for either kind is a COLOUR beside a name it has not learned.
#
# THREE ALPHABETS AND NOT FOUR, THOUGH THERE ARE FOUR KINDS. Cards are absent from
# this fold on purpose (docs/cards-design.md §2): there is no such thing as an
# identified card, so a run learns nothing about them and there is nothing here for
# it to remember. A "Cards: 13 of 13" row would be a record of the player having
# read the Collection.
#
# It is a class rather than a method on the loot window because BOTH surfaces that
# draw the pack draw it: the window, and the reward screen, whose right-hand side
# is the inventory and not a picture of one. `open` is static for the same reason
# — it is one preference about one thing, and a fold that was shut in the window
# and open on the reward screen would be two answers to the same question.

# Shared by every surface that draws the fold, and sticky across rebuilds: it is a
# thing you consult, not a thing you read every time you open the pack, so it
# starts shut and stays however the player last left it.
static var open: bool = false

# How much of a panel the fold is allowed to take once it is open. A run that has
# learned all ten colours and all seven scrolls has seventeen rows to show, and
# both panels are already three cells tall inside a 720p window — left to grow it
# would push itself off the bottom of the screen, which is the one thing a floating
# panel must never do. So the record gets a fixed slice and scrolls inside it.
const HEIGHT := 108
const WIDTH := LootSlot.CELL_W * 3

# The whole section: the toggle, and — when open — the record under it. `on_toggle`
# is what redraws the surface that owns it, since the fold changes its height.
static func build(on_toggle: Callable, max_height: int = HEIGHT) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var pills: Array = known_pills()
	var scrolls: Array = known_scrolls()
	var potions: Array = known_potions()
	var learned: int = pills.size() + scrolls.size() + potions.size()

	var toggle := UITheme.quiet_button(
		"%s  Known this run — %d learned" % ["▾" if open else "▸", learned],
		Vector2(0, 20), 11)
	toggle.tooltip_text = "The pills, scrolls and potions this run has identified.\n" \
		+ "A pill's name belongs to its colour, and a potion's to its bottle — " \
		+ "both only until the run ends."
	toggle.pressed.connect(func():
		open = not open
		if on_toggle.is_valid():
			on_toggle.call())
	box.add_child(toggle)
	if not open:
		return box

	if learned == 0:
		box.add_child(note("Nothing yet. Spending an unknown piece is what teaches you what it was."))
		return box

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(WIDTH, max_height)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	box.add_child(scroll)

	if not pills.is_empty():
		inner.add_child(_row("Pills", pills))
	if not scrolls.is_empty():
		inner.add_child(_row("Scrolls", scrolls))
	if not potions.is_empty():
		inner.add_child(_row("Potions", potions))
	# What is left to learn, as a NUMBER rather than as a list of names — see the
	# header: a row of blanks that could be counted would give the spares away.
	#
	# The two masked alphabets get a line each rather than one summed line, because
	# the words are not interchangeable: a pill is a COLOUR the run dealt out of 13,
	# a potion is a BOTTLE dealt out of 37, and "7 more out there" over both would
	# be a number the player cannot use for either.
	var unknown: int = maxi(0, Data.all_pills().size() - pills.size())
	if unknown > 0:
		inner.add_child(note("%d more colour%s out there, unlearned." % [
			unknown, "" if unknown == 1 else "s"]))
	var corked: int = maxi(0, Data.all_potions().size() - potions.size())
	if corked > 0:
		inner.add_child(note("%d more bottle%s out there, unlearned." % [
			corked, "" if corked == 1 else "s"]))
	return box

static func _row(heading: String, entries: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var head := Label.new()
	head.text = heading
	head.add_theme_font_size_override("font_size", 10)
	head.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	col.add_child(head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.custom_minimum_size = Vector2(WIDTH, 0)
	col.add_child(flow)
	for entry in entries:
		flow.add_child(_chip(entry))
	return col

# One learned piece: its art and its name, at a size that fits several to a row.
# It carries the same hover card the pack's own slots do, so "what does green do
# again" is answered in the place the question is asked.
static func _chip(entry: Dictionary) -> Control:
	var wrap := HoverPanel.new()
	var pref: String = LootSystem.preference(entry)
	var tint: Color = UITheme.preference_color(pref)
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.84), 5, 3, 1, tint.lerp(UITheme.BG, 0.55)))
	HoverCard.attach(wrap, LootSystem.hover_card(entry))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)
	var art: TextureRect = LootSystem.art_tex(entry, 16)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var name := Label.new()
	name.text = LootSystem.display_name(entry)
	name.add_theme_font_size_override("font_size", 10)
	name.add_theme_color_override("font_color", UITheme.TEXT)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name)
	return wrap

# Every pill colour this run has identified, as loot entries at the NORMAL dose —
# identification belongs to the colour and covers both doses, so the record shows
# the one the player will meet nine times in ten.
static func known_pills() -> Array:
	var out: Array = []
	for pill in Data.all_pills():
		if PillSystem.is_identified(pill.id):
			out.append({"type": "pill", "id": pill.id, "horse": false})
	return out

static func known_scrolls() -> Array:
	var out: Array = []
	for scroll in Data.all_scrolls():
		if ScrollSystem.is_identified(scroll.id):
			out.append({"type": "scroll", "id": scroll.id})
	return out

# Every potion this run has identified. A known bottle draws its OWN art and its
# own name here (LootSystem goes through PotionSystem for both), which is the
# whole difference from a pill: what a potion turns out to be is a fact the player
# has bought, and the vial it arrived in stops being the thing it is called.
static func known_potions() -> Array:
	var out: Array = []
	for potion in Data.all_potions():
		if PotionSystem.is_identified(potion.id):
			out.append({"type": "potion", "id": potion.id})
	return out

static func note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH, 0)
	return l
