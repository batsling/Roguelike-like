class_name DashFilterBar
extends RefCounted

# THE DASH PANEL'S SEARCH, FILTER AND SORT (§4).
#
# An ordinary offering is three cards and needs none of this. A Dash is a LIST —
# a hub has twenty connections — and `_offered_ids` has said so in a comment for
# as long as it has sorted them A-Z: "the question stops being *which of these
# three* and becomes *is the game I have in mind in here*". These are the controls
# that question actually wants, and they are the Collection's, because a player
# who has used the search box there already knows how this one works.
#
# Split out of Overworld2 (docs/performance-backlog.md §1). It is the region that
# had ACCRETED since that document's seam table was last measured — 146 lines the
# table had never seen, which is the pattern §1 warns about in its own words: this
# file does not creep, it absorbs. It was also the most scattered thing in the
# page, four fragments up to 5,200 lines apart: the three filter values declared
# beside the Dash flag, the list filter down in offering construction, the bar
# itself a thousand lines below that, and its container built in `_build_ui`.
#
# The class owns the three filter values, the bar and its widgets. The PAGE still
# owns the offering, the phase and the graph; everything this needs from them it
# asks for (see the `_page.` calls below), and the page passes the Dash phase IN
# rather than this reaching back for `_dash_mode`.
#
# `_page` is the Overworld2 that owns this bar, typed loosely because Overworld2
# names DashFilterBar and two class_names that name each other are a cyclic
# reference Godot resolves badly.
var _page: Node = null

# ALL THREE ARE DASH-ONLY and reset every time a Dash is opened (see `reset`, and
# `Overworld2.dash`). A filter that outlived the panel would be a silently
# shortened offering the next time round, which is the one thing an offering must
# never be.
#
# The page publishes these as `_dash_search`, `_dash_sort` and `_dash_type` — with
# SETTERS, because `test_overworld2.gd` sets all three by hand to drive the panel
# without typing into it.
var search: String = ""
# &"name" (A-Z, the default), &"distance" (fewest steps left to the Amulet
# first) or &"year". Distance is the one this panel exists for: every dash target
# is one hop away, so "how far away" can only mean how far the AMULET still is
# from it, which is the number the whole run is counting down.
var sort: StringName = &"name"
# A GameData.GameType, or -1 for every type.
var type_filter: int = -1

# The bar itself, published as `_dash_bar`. Empty and hidden outside dash mode.
var bar: HFlowContainer = null
# Kept so a change to the sort or the type can repaint the LIST without rebuilding
# the bar the player is typing into. Published as `_dash_search_box`,
# `_dash_count_label` and `_dash_sort_buttons`.
var search_box: LineEdit = null
var count_label: Label = null
var sort_buttons: Array = []

func _init(page: Node) -> void:
	_page = page

# The container, built with the rest of the page and mounted on a row of its own
# BELOW the controls. Empty until a Dash opens.
func mount(parent: Control) -> void:
	bar = HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 4)
	bar.visible = false
	parent.add_child(bar)

# Take the panel back to the state it opens in. Called when a Dash is opened and
# when one is put down, so a search typed into one Dash can never quietly shorten
# the next.
func reset() -> void:
	search = ""
	sort = &"name"
	type_filter = -1

# ---------------------------------------------------------------------------
# The list itself
# ---------------------------------------------------------------------------

# NARROWING IS NOT BASHING. What is filtered out is still connected, still
# reachable and still there the moment the search box is cleared — this only
# decides what is DRAWN. That is why it lives here rather than in
# `Overworld2._sorted_neighbors`, which is what the ordinary three-card offering
# draws from and must never see a filter.
func filter(nbrs: Array) -> Array:
	var out: Array = []
	var term: String = search.strip_edges().to_lower()
	for gid in nbrs:
		var game: GameData = GameLoop2.game_at(gid)
		if game == null:
			continue
		if type_filter >= 0 and int(game.type) != type_filter:
			continue
		if term != "" and not term in game.display_name.to_lower():
			continue
		out.append(gid)
	# The page owns the tiebreak, because the ordinary offering sorts by it too.
	var by_name := Callable(_page, "_by_display_name")
	match sort:
		&"distance":
			# Fewest steps LEFT first. A game the distance map has no answer for
			# (-1, off the run's component) sorts to the back rather than to the
			# front, where a raw -1 would put it: "unknown" is not "nearly there".
			out.sort_custom(func(a, b):
				var da: int = _page.steps_to_amulet(a)
				var db: int = _page.steps_to_amulet(b)
				if da < 0:
					da = 1 << 30
				if db < 0:
					db = 1 << 30
				if da != db:
					return da < db
				return by_name.call(a, b))
		&"year":
			out.sort_custom(func(a, b):
				var ga: GameData = GameLoop2.game_at(a)
				var gb: GameData = GameLoop2.game_at(b)
				var ya: int = ga.year if ga != null else 0
				var yb: int = gb.year if gb != null else 0
				if ya != yb:
					return ya > yb
				return by_name.call(a, b))
		_:
			out.sort_custom(by_name)
	return out

# ---------------------------------------------------------------------------
# The bar
# ---------------------------------------------------------------------------
#
# BUILT ONCE PER DASH, not once per refresh. Everything else on this page is torn
# down and redrawn whenever anything changes, which is fine for labels and fatal
# for a text field: rebuilding the LineEdit under the player mid-word takes the
# focus and the caret with it, and the search box would be unusable. So the bar is
# built when a Dash opens and torn down when it closes, and a change to any of its
# three controls repaints the CARDS only (see `_repaint`).

func rebuild(dash_mode: bool) -> void:
	if bar == null:
		return
	sort_buttons.clear()
	search_box = null
	count_label = null
	_page._clear(bar)
	bar.visible = dash_mode
	if not dash_mode:
		return

	search_box = LineEdit.new()
	search_box.placeholder_text = "Search…"
	search_box.text = search
	search_box.custom_minimum_size = Vector2(150, 0)
	search_box.add_theme_font_size_override("font_size", 12)
	# Live rather than debounced: a Dash offers the games CONNECTED to where you
	# stand — a couple of dozen at the worst hub — so re-filtering is a sort of a
	# short list, not the Collection's sweep of 865.
	search_box.text_changed.connect(func(t: String):
		search = t
		_repaint())
	bar.add_child(search_box)

	bar.add_child(_sort_button("A-Z", &"name",
		"Alphabetical, so a game you have in mind is where you expect it."))
	# THE ONE THIS PANEL EXISTS FOR. Every dash target is one hop from here, so
	# the only distance worth sorting on is how much road is LEFT after taking it.
	bar.add_child(_sort_button("Closest to Amulet", &"distance",
		"Fewest games left between there and %s." % _page.amulet_name()))
	bar.add_child(_sort_button("Newest", &"year",
		"Most recently released first."))

	var type_opt := OptionButton.new()
	type_opt.add_item("All types", -1)
	for i in [GameData.GameType.ACTION, GameData.GameType.STRATEGY,
			GameData.GameType.DECKBUILDER, GameData.GameType.TRADITIONAL]:
		type_opt.add_item(RunGraph.type_label(i), i)
	for i in range(type_opt.item_count):
		if type_opt.get_item_id(i) == type_filter:
			type_opt.select(i)
	type_opt.add_theme_font_size_override("font_size", 12)
	type_opt.focus_mode = Control.FOCUS_NONE
	type_opt.item_selected.connect(func(idx: int):
		type_filter = type_opt.get_item_id(idx)
		_repaint())
	bar.add_child(type_opt)

	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(count_label)
	refresh_count()

# THE BAR IS REBUILT ON THE TRANSITION AND ONLY ON IT. A dozen paths drop out of
# dash mode (a pick, a report, arming a verb, a teleport), and none of them should
# have to remember to tear the bar down — but rebuilding it on every refresh would
# take the focus and the caret out of the search box every time the player typed a
# letter. Comparing what the bar is SHOWING against the mode is what tells the two
# cases apart.
func sync_to_mode(dash_mode: bool) -> void:
	if bar != null and bar.visible != dash_mode:
		rebuild(dash_mode)

# One of the three sort buttons. Pressed-looking when it is the one in force, so
# the row says which order the list is in without a label.
func _sort_button(text: String, key: StringName, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_pressed = sort == key
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE      # so tabbing stays in the search box
	b.pressed.connect(func():
		sort = key
		for other in sort_buttons:
			if is_instance_valid(other):
				other.button_pressed = other == b
		_repaint())
	sort_buttons.append(b)
	return b

# "7 of 20" — and it is not decoration. A search that matches nothing leaves an
# empty strip, which reads exactly like a dead end (the offering's own empty state
# says "No reachable games"); this is what tells the player the games are still
# there and the box is what is hiding them.
#
# Both counts come off the page: what it is SHOWING is the offering it built, and
# what it COULD show is the neighbour list before this filter ran.
func refresh_count() -> void:
	if count_label == null or not is_instance_valid(count_label):
		return
	var shown: int = _page.dash_visible_count()
	var total: int = _page.dash_total_count()
	count_label.text = ("%d game%s" % [total, "" if total == 1 else "s"]
		if shown == total else "%d of %d" % [shown, total])

# The page's entry point, with the Dash phase passed in rather than read out.
func apply(dash_mode: bool) -> void:
	if not dash_mode:
		return
	_repaint()

# A control on the bar moved: redraw the CARDS and leave the bar alone, so the
# search box keeps the focus and the caret the player is typing at.
#
# The guard is the bar's OWN visibility rather than the page's phase: a widget on
# a hidden bar cannot be pressed, so "the bar is up" is both the truth this needs
# and the only part of the phase this class has any business knowing.
func _repaint() -> void:
	if bar == null or not bar.visible:
		return
	_page._build_choices()
	_page._render_choices()
	refresh_count()
