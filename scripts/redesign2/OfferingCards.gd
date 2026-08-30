class_name OfferingCards
extends RefCounted

# The offering — the cards you choose your next game from, and the hover line
# under them (docs/games-first-redesign.md §4).
#
# Two sets of cards, because there are two choosing phases. START_SELECT draws
# the choose-your-start cards (render_start): one per offered start, each a
# different genre and each the same distance band from the amulet. SELECT draws
# the ordinary offering (render): the games reachable from where the run is
# standing, as covers with their names under them. They share the strip, the
# hover line and every widget below the top two functions, because they are the
# same decision asked twice.
#
# Split out of Overworld2 (docs/performance-backlog.md §1). The page owns the
# three containers this fills — `_choices_row`, `_preview` and `_preview_art`,
# built in Overworld2._build_ui — and everything a card does on click goes back
# through one of the page's public verbs (`open_choice`, `open_start_choice`,
# `preview_map`), so the offering decides what the cards LOOK like and the page
# still decides what they DO.
#
# `_page` is the Overworld2 that owns this offering, typed loosely because
# Overworld2 names OfferingCards and two class_names that name each other are a
# cyclic reference Godot resolves badly.
var _page: Node = null
var _row: HFlowContainer = null      # the page's _choices_row
var _line: RichTextLabel = null      # the page's _preview
var _art: TextureRect = null         # the page's _preview_art

# Which of the two phases drew the cards on the table. Tracked here rather than
# read off the page's `_phase` for the reason PackStrip takes its `reporting`
# flag as an argument: it keeps this class independent of the page's phase model,
# and the two render entry points are the only things that can change it —
# render_start runs only in START_SELECT and render only in SELECT.
var _starting: bool = false

# Tries the hovered card would grant, or -1 with nothing hovered. Owned here
# because only the hover line reads it; the page resets it when it commits to a
# game (reset_hover_grant).
var _hover_grant: int = -1

func _init(page: Node, row: HFlowContainer, line: RichTextLabel, art: TextureRect) -> void:
	_page = page
	_row = row
	_line = line
	_art = art

# Committing to a game drops the hover without repainting the line: the page is
# about to redraw the whole panel anyway, and the bare reset is what the two call
# sites did inline before this class existed. clear_hover_grant is the other one —
# the mouse leaving a card, which DOES repaint.
func reset_hover_grant() -> void:
	_hover_grant = -1

# The choose-your-start panel (Phase.START_SELECT): one card per offered start,
# each a different genre and each the same distance band from the amulet, so the
# decision is "which genre do I want to open on and route from", never "which of
# these is the short run".
func render_start() -> void:
	_starting = true
	_page._clear(_row)
	_hover_grant = -1
	if _page._start_options.is_empty():
		var l := Label.new()
		l.text = "No start could be rolled — check the game filter in Settings."
		_row.add_child(l)
		return
	for i in range(_page._start_options.size()):
		_row.add_child(_make_start_card(i, _page._start_options[i]))
	_line.text = _preview_idle_text()
	_show_hover_art({})

# One start card: the cover, the game's name, its genre, and how many games stand
# between it and the Amulet — which is named, along with everything else on the
# road to it (see _page.amulet_name).
func _make_start_card(index: int, opt: Dictionary) -> Control:
	var game: GameData = opt["game"]
	var accent: Color = RunGraph.type_color(int(opt["type"]))
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	card.custom_minimum_size = Vector2(COVER_SIZE.x + 10, 0)

	var type_lbl := Label.new()
	type_lbl.text = RunGraph.type_label(int(opt["type"]))
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE)
	type_lbl.add_theme_font_size_override("font_size", 13)
	type_lbl.add_theme_color_override("font_color", accent.lerp(UITheme.TEXT, 0.35))
	card.add_child(type_lbl)

	# The road this start opens on, before committing to it. The destination is
	# drawn unnamed — the distance is still the only thing the picker gives away
	# about the Amulet — but its SHAPE is exactly what makes one start different
	# from another, so it's on the table.
	card.add_child(_map_preview_button(game.id, game))

	var btn := Button.new()
	btn.custom_minimum_size = COVER_SIZE
	var frame_n := UITheme.flat(UITheme.BG, 8, 4, 1, UITheme.BORDER)
	var frame_h := UITheme.flat(UITheme.PANEL_HI, 8, 4, 2, accent)
	btn.add_theme_stylebox_override("normal", frame_n)
	btn.add_theme_stylebox_override("hover", frame_h)
	btn.add_theme_stylebox_override("pressed", frame_h)
	btn.add_theme_stylebox_override("focus", frame_h)
	# Opens the card rather than committing: the start is a game you go and play
	# now, so it gets the same "here is what's waiting, do you want it" popup every
	# other game in the run gets. No tooltip, for the same reason an offered card
	# has none — the hover line under the cards is where a start describes itself.
	btn.pressed.connect(func(): _page.open_start_choice(index))
	btn.mouse_entered.connect(func(): _show_start_preview(index))
	btn.mouse_exited.connect(clear_hover_grant)
	if game.cover_image != null:
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = game.cover_image
		btn.add_child(art)
	else:
		btn.text = game.display_name
		btn.add_theme_color_override("font_color", accent)
	card.add_child(btn)

	var name_lbl := Label.new()
	name_lbl.text = game.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, NAME_BOX_H)
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	card.add_child(name_lbl)

	var dist := Label.new()
	dist.text = _page._start_distance_text(int(opt["path_len"]))
	dist.tooltip_text = "The shortest route from %s to %s, the game this run ends on." % [
		game.display_name, _page.amulet_name()]
	dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dist.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE * 2 + 2)
	dist.add_theme_font_size_override("font_size", BADGE_FONT)
	dist.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT, 0.35))
	card.add_child(dist)
	return card

func _show_start_preview(index: int) -> void:
	if index < 0 or index >= _page._start_options.size():
		return
	var opt: Dictionary = _page._start_options[index]
	# The same one-line hover the offering writes — the start is a game you play,
	# so what is waiting at it is readable without opening the card, exactly as it
	# is for every other card in the run.
	_hover_grant = GameLoop2.shields_for_game(opt["game"])
	var choice: Dictionary = _page._start_choice(index)
	_line.text = "%s  ·  [color=#%s]%s[/color]" % [
		_hover_line(choice), UITheme.GOLD.to_html(false),
		_page._start_distance_text(int(opt["path_len"]))]
	_show_hover_art(choice)

func render() -> void:
	_starting = false
	_page._clear(_row)
	# The cards are rebuilt, so nothing is hovered any more.
	_hover_grant = -1
	if _page._choices.is_empty():
		var l := Label.new()
		l.text = "No reachable games — dead end."
		_row.add_child(l)
		return
	for i in range(_page._choices.size()):
		_row.add_child(_make_choice_card(i, _page._choices[i]))
	_line.text = _preview_idle_text()
	_show_hover_art({})

# The offered cover art, back at the size it deserves. It was halved when the
# offering moved into the left column beside the board (COVER_SIZE was 105x140),
# because seven rows of badges were stacked around every cover and three of those
# columns had to fit side by side. The badges have gone into GameChoiceModal, so
# the art gets the room back.
const COVER_SIZE := Vector2(150, 200)

# The width of the enemy portrait on the hover line under the offering. Its
# HEIGHT is the line's, whatever that turns out to be — and that is the whole
# trick, because it is what makes the portrait FREE.
#
# The overworld is fitted to a 720p window with single-digit pixels to spare
# (test_overworld2's _assert_fits), and the page's worst case — three arcade
# machines under the board — sits within about four of them. A hover row that
# reserved even 30px of height for art blew that budget on its own. So the art
# fills the line instead of setting its height: same page, one more thing on it.
#
# That makes it small, which is the right size anyway. This is an IDENTIFIER for
# a body the player already knows — the same job, and the same scale, as the
# portraits on a card's Beatable row. The exhibit is in the popup the card opens,
# where the enemy is drawn at full size.
const HOVER_ART := 30.0

# The badge rows on a card: the name, plus two fixed-height flag lines above the
# cover — the Amulet / event flag, and the repeat game's +1 Dash. Everything else
# a card used to carry (the route, the pace, the Temporary Shields, the map, the Beatable row,
# the Bash/Transmute verbs) lives in the popup the card opens.
const BADGE_FONT := 11
const BADGE_LINE := 15               # one line of BADGE_FONT, in px
# The distance line is a point smaller than the badges above it, and for a
# measured reason rather than a stylistic one — see _make_choice_card: at
# BADGE_FONT its longest sentence is 172px against a 160px card and wraps to a
# second line the page has no room for. At 10 it is 156px and stays on one.
const DIST_FONT := 10
# The game's NAME keeps a readable size, in its own fixed box, so a card whose
# title wraps to three lines doesn't sit a line taller than its neighbours.
const NAME_FONT := 13
const NAME_BOX_H := 51               # three lines of NAME_FONT — "Shotgun King:
                                     # The Final Checkmate" needs all three

# One choice = the game's cover art, its name, and — when it is the game the whole
# run is a search for — the Amulet's flag above it. Nothing else: clicking the
# card opens GameChoiceModal, which is where the route, the enemy, the shields and
# the verbs all get said properly, and where the game is actually chosen.
#
# Hover still updates the shared enemy preview under the row, so the offering can
# be read at a glance without opening anything.
# The shop flag's hover: the headline, plus the shelf itself once the player has
# actually been in there. Both come from ShopSystem so this and the popup's shop
# block cannot end up describing the same shelf differently.
func _shop_card_tooltip(game: GameData) -> String:
	# "…and no event" is worth a line here because it is the ONE place a hub
	# differs from every other card in what it costs you: a shop stands here
	# instead of an event, not as well as one (§12).
	var lines: Array = [ShopSystem.headline(game.id),
		"A shop stands here, so no event fires — this is what happens instead."]
	var stock: Array = ShopSystem.stock_lines(game.id)
	if not stock.is_empty():
		lines.append("")
		lines.append_array(stock)
	return "\n".join(lines)


func _make_choice_card(index: int, choice: Dictionary) -> Control:
	var game: GameData = choice["game"]
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	card.custom_minimum_size = Vector2(COVER_SIZE.x + 10, 0)

	var amulet: bool = bool(choice["amulet"])
	var accent: Color = UITheme.DANGER if choice["boss"] else (UITheme.GOLD if amulet else UITheme.type_color(int(game.type)))

	# THE ONE THING that has to be legible without opening anything: this is the
	# game the run ends on. The row is mounted on every card, blank off the Amulet,
	# so the flagged card's cover stays in line with the rest of the offering.
	#
	# There WAS an `✦ EVENT` badge in this row. It marked the handful of dead ends
	# carrying an event, back when placement was hashed onto specific nodes and
	# routing towards one was a decision. An event now fires after every game
	# played, so a badge on every card would say nothing — and the hash it
	# depended on is gone with it, which means there is no longer an honest answer
	# to "which event is at that node" before the run gets there.
	#
	# The SHOP badge (§14) is the row's other tenant. Its colour is deliberately
	# not a gold — see UITheme.SHOP_GREEN — because a gold badge sitting in the
	# Amulet's own slot is the one confusion this row cannot afford.
	#
	# IT SHARES ITS LINE WITH THE ⚡ DASH BADGE below. They were two stacked rows of
	# BADGE_LINE, both blank on most cards, and the page cannot afford a third: the
	# overworld fits a 720p canvas with about two spare pixels on its worst page
	# (a hub's shop under the board — test_overworld2's `_assert_fits`), so the
	# distance line under them had to be paid for out of the badges' own space.
	# Side by side they are 139px of the card's 160 at their widest
	# (`🏆 THE AMULET` + `⚡ +1 DASH`), which is the case that decided this.
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 4)
	badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_row.custom_minimum_size = Vector2(COVER_SIZE.x, BADGE_LINE)
	card.add_child(badge_row)

	var flag := Label.new()
	if amulet:
		flag.text = "🏆 THE AMULET"
		flag.tooltip_text = "Beat this game's goal and you win the run."
		flag.add_theme_color_override("font_color", UITheme.GOLD)
	elif ShopSystem.is_hub(game.id):
		flag.text = "🛒 SHOP"
		flag.tooltip_text = _shop_card_tooltip(game)
		flag.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	else:
		flag.text = ""
		flag.add_theme_color_override("font_color", UITheme.GOLD)
	flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flag.custom_minimum_size = Vector2(0, BADGE_LINE)
	flag.add_theme_font_size_override("font_size", BADGE_FONT)
	badge_row.add_child(flag)

	# THE SECOND THING that has to be legible without opening anything: a game you
	# have already played this run pays a Dash for going back and beating it
	# (_page.REPEAT_BEAT_DASH). It is the offering's only recurring free charge, and it
	# was only ever stated inside the popup — so the one card on the table that is
	# worth revisiting looked exactly like the ones that aren't. It rides ABOVE the
	# cover, ON the Amulet's flag's own line, because it is a reason to open a card
	# and reasons to open a card belong where the card is being scanned.
	#
	# Like the flag, it is mounted on EVERY card and left blank off a repeat, so one
	# +1 in the offering doesn't knock the other covers out of line.
	var dash_flag := Label.new()
	if bool(choice.get("repeat", false)):
		dash_flag.text = "⚡ +%d DASH" % _page.REPEAT_BEAT_DASH
		dash_flag.tooltip_text = ("You have played %s already this run — go back and beat it and it pays %d Dash charge%s."
			% [game.display_name, _page.REPEAT_BEAT_DASH, "" if _page.REPEAT_BEAT_DASH == 1 else "s"])
	else:
		dash_flag.text = ""
	dash_flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dash_flag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dash_flag.custom_minimum_size = Vector2(0, BADGE_LINE)
	dash_flag.add_theme_font_size_override("font_size", BADGE_FONT)
	dash_flag.add_theme_color_override("font_color", _page.DASH_BLUE)
	badge_row.add_child(dash_flag)

	# HOW FAR THAT GAME IS FROM THE AMULET — under the badges, over the art.
	#
	# The start cards have always carried the distance; the cards after them
	# carried only the DIRECTION, and only inside the popup they open
	# (Overworld2.route_note), so the number the whole run is counting down was the
	# one thing the offering never showed. It rides here because it is read while
	# the row of covers is being SCANNED, not after one has been opened.
	#
	# ONE LINE, at DIST_FONT rather than BADGE_FONT: the sentence is 156px at its
	# longest ("20 games away from the Amulet") against a card 160 wide, and at
	# BADGE_FONT it wraps to two — which is 16 more pixels than the page's worst
	# case has to give (see the badge row above). Blank on the Amulet's own card,
	# where the flag a line up has already said it.
	var dist := Label.new()
	dist.text = _page.amulet_distance_text(_page.steps_to_amulet(StringName(choice.get("slot", &""))))
	dist.tooltip_text = "%s is the Amulet — the game this run ends on." % _page.amulet_name()
	dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dist.custom_minimum_size = Vector2(0, BADGE_LINE)
	dist.add_theme_font_size_override("font_size", DIST_FONT)
	dist.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT, 0.35))
	card.add_child(dist)

	# NO TOOLTIP. The offering is the one place on the page that does NOT get a
	# hover card: the enemy's portrait and its goal are already written on the
	# hover line under the cards (see show_preview), which is the same read the
	# card would be, and a popup over the covers while the mouse crosses three of
	# them is the noisiest possible way to say it. The cards are for scanning.
	var btn := Button.new()
	btn.custom_minimum_size = COVER_SIZE
	# A CARD UNDER AN ARMED VERB IS A TARGET, and it is drawn as one. Bash and
	# Transmute are aimed from the chips below the offering (Overworld2._armed_verb),
	# and while one is up a click on this cover fires it instead of opening the card
	# — so the cards cannot look the way they do when a click means "tell me about
	# this". They wear the verb's own colour at rest, not only on hover.
	#
	# The Amulet is the exception under a Bash, because bashing it is refused (it
	# would destroy the run's goal): it keeps its gold frame and says why on the
	# hover, rather than lighting up as a target that then argues back.
	# Never on the stay-or-return pair (§10): those two cards MOVE the run rather
	# than offering it a game, there is no slot to reshape, and `open_choice` refuses
	# an armed click there — so lighting them as targets would be a promise the click
	# does not keep.
	var armed: StringName = &"" if _page._asking_return() else _page.armed_verb()
	var aimable: bool = armed != &"" and not (armed == &"bash" and amulet)
	# The verb's OWN colour, the one its chip and its prompt are already wearing
	# (Overworld2.BASH_ORANGE / UITheme.ACCENT) — three near-matches would read as
	# three mechanics rather than as one verb pointing at these cards.
	var aim_tint: Color = _page.BASH_ORANGE if armed == &"bash" else UITheme.ACCENT
	var rest_border: Color = UITheme.GOLD if amulet else UITheme.BORDER
	if aimable:
		rest_border = aim_tint
	var frame_n := UITheme.flat(
		aim_tint.lerp(UITheme.BG, 0.82) if aimable else UITheme.BG,
		8, 4, 2 if aimable else 1, rest_border)
	var frame_h := UITheme.flat(UITheme.PANEL_HI, 8, 4, 2, aim_tint if aimable else accent)
	btn.add_theme_stylebox_override("normal", frame_n)
	btn.add_theme_stylebox_override("hover", frame_h)
	btn.add_theme_stylebox_override("pressed", frame_h)
	btn.add_theme_stylebox_override("focus", frame_h)
	# The one place the offering carries a tooltip (see the note above about why it
	# normally does not): while a verb is armed the click means something other than
	# it usually does, and that is worth saying on the thing being clicked.
	if armed == &"bash":
		btn.tooltip_text = ("%s holds the Amulet — it cannot be bashed." % game.display_name
			) if amulet else ("⛏ Bash %s — it leaves the pool for the rest of the run."
			% game.display_name)
	elif armed == &"transmute":
		btn.tooltip_text = "⚗ Transmute %s — this spot plays a different game instead." % game.display_name
	btn.pressed.connect(func(): _page.open_choice(index))
	btn.mouse_entered.connect(func(): show_preview(index))
	btn.mouse_exited.connect(clear_hover_grant)
	if game.cover_image != null:
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = game.cover_image
		btn.add_child(art)
	else:
		btn.text = game.display_name
		btn.add_theme_color_override("font_color", accent)
	card.add_child(btn)

	var name_lbl := Label.new()
	name_lbl.text = ("☠ " if choice["boss"] else ("🏆 " if amulet else "")) + game.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(COVER_SIZE.x, NAME_BOX_H)
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT)
	name_lbl.add_theme_color_override("font_color", accent if (choice["boss"] or amulet) else UITheme.TEXT)
	card.add_child(name_lbl)
	return card

# The 🗺 button every offered card wears above its cover: opens the optimal path
# from that game to the Amulet. Full width of the card, so the row of covers stays
# in line whatever a card's route badge says.
func _map_preview_button(slot: StringName, game: GameData) -> Button:
	var b := Button.new()
	b.text = "🗺  Map"
	b.tooltip_text = "See the shortest route to the Amulet if you take %s." % game.display_name
	b.custom_minimum_size = Vector2(COVER_SIZE.x, 24)
	b.add_theme_font_size_override("font_size", BADGE_FONT)
	b.pressed.connect(func(): _page.preview_map(slot))
	return b

# "Beatable:" — the enemies on the board right now that you have ALREADY beaten
# at this game before. Not a prediction: it's your own record saying this pair
# has worked, which is exactly what you want to know while choosing where to go
# with a follower stuck to you.
#
# Returns null when there's nothing to say, so an unproven card stays clean.
func beatable_row(choice: Dictionary) -> Control:
	var game: GameData = choice.get("game")
	if game == null:
		return null
	# The enemy standing at this card, plus everything currently following you.
	# Under the Runic Dome the card's own enemy is left out: a "Beatable" pip is a
	# portrait with a name on it, so keeping it would hand back the exact thing
	# the relic is meant to be hiding. The FOLLOWERS stay — they are already on
	# the board and the Dome only ever hid what has yet to spawn.
	var on_board: Array = []
	var here: GoalEnemyData = choice.get("enemy")
	if here != null and not enemy_hidden(choice):
		on_board.append(here)
	for entry in GameLoop2.stack:
		var follower: GoalEnemyData = entry.get("enemy")
		if follower != null:
			on_board.append(follower)

	var proven: Array = []
	var seen: Dictionary = {}
	for enemy in on_board:
		if seen.has(enemy.id):
			continue
		if GameStats.enemy_beaten_count(game.id, enemy.id) > 0:
			seen[enemy.id] = true
			proven.append(enemy)
	if proven.is_empty():
		return null

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = "Beatable:"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UITheme.SUCCESS)
	row.add_child(label)
	for enemy in proven:
		row.add_child(_beatable_pip(game, enemy))
	return row

# One enemy on the Beatable row: its portrait, with the record and whatever note
# was written on the hover — the note is the reason you know it's beatable.
func _beatable_pip(game: GameData, enemy: GoalEnemyData) -> Control:
	var times: int = GameStats.enemy_beaten_count(game.id, enemy.id)
	var note: String = GameStats.enemy_note(game.id, enemy.id).strip_edges()
	var tip: String = "%s — beaten here ×%d" % [enemy.display_name, times]
	if enemy.goal != "":
		tip += "\n%s" % enemy.goal
	if note != "":
		tip += "\n\n🗒 %s" % note
	if enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		art.custom_minimum_size = Vector2(20, 20)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.tooltip_text = tip
		return art
	# No portrait authored — fall back to the name rather than an empty gap.
	var chip := Label.new()
	chip.text = enemy.display_name
	chip.add_theme_font_size_override("font_size", 9)
	chip.add_theme_color_override("font_color", UITheme.SUCCESS)
	chip.tooltip_text = tip
	return chip

func show_preview(index: int) -> void:
	if index < 0 or index >= _page._choices.size():
		return
	# A destination card grants no shields — it isn't a game being started (§10).
	_hover_grant = -1 if _page._asking_return() else GameLoop2.shields_for_game(_page._choices[index]["game"])
	_line.text = _hover_line(_page._choices[index])
	_show_hover_art(_page._choices[index])

# The portrait beside the hover line: the body this card would put on the board.
#
# Blank for the stay-or-return pair (they spawn nothing), for a free game with no
# enemy, and under the Runic Dome — the relic hides WHAT is waiting, and a picture
# gives that away far more completely than a name would.
func _show_hover_art(choice: Dictionary) -> void:
	if _art == null or not is_instance_valid(_art):
		return
	var tex: Texture2D = null
	if not choice.is_empty() and not choice.has("stay") and not enemy_hidden(choice):
		tex = _enemy_texture(choice)
	_art.texture = tex
	_art.visible = tex != null

# The mouse left a card: the line stays as a reference, but the grant number and
# the portrait go with the hover, so neither can advertise a game you're not
# pointing at.
func clear_hover_grant() -> void:
	_show_hover_art({})
	if _hover_grant < 0:
		return
	_hover_grant = -1
	_line.text = _preview_idle_text()

# What the hover line says with nothing hovered — which is a different sentence
# when the two cards on the table are the ends of a detour rather than games to
# go and play (§10).
func _preview_idle_text() -> String:
	if _starting:
		return "[i]Hover a start to see what it opens on.[/i]"
	if _page._asking_return():
		return "[i]The detour is over. Open either game to see the road from it, then take the one you want to carry on from.[/i]"
	return "[i]Hover a game to see the enemy it would spawn — click it for the route, the goal and the way in.[/i]"

# The enemy's art (§10.1) for a choice, or null when there's no enemy.
func _enemy_texture(choice: Dictionary) -> Texture2D:
	var e: GoalEnemyData = choice.get("enemy")
	return e.image if e != null else null

# Runic Dome (§7.1): whether this card's enemy is hidden. Only ever true for a
# game being OFFERED — the relic buys a column of board with the routing decision,
# not with the game you are standing on, so the moment a game is committed to its
# enemy is on the board and describes itself like any other.
func enemy_hidden(choice: Dictionary) -> bool:
	if not GameState.hides_upcoming_enemies():
		return false
	if choice.get("enemy") == null:
		return false
	var landed: Dictionary = GameLoop2.arrival()
	return landed.is_empty() or landed.get("enemy") != choice.get("enemy")

# What a hidden card says instead. Named rather than inlined because three
# screens say it (the hover line, the now-playing panel, GameChoiceModal) and
# they must not each invent their own wording for the same blank.
const HIDDEN_ENEMY_TEXT := "something you can't see"

# THE ESCORT (§7.5), said before it exists. The second body is rolled on ARRIVAL,
# so a card cannot name it — but it must not stay quiet about it either: "how many
# bodies does this put on the board" is half of what the routing decision is
# about, and a card that showed one enemy and delivered two would be lying by
# omission. So the card promises the count and withholds the name.
const ESCORT_WARNING := "⚠ One more enemy spawns with it — which one is rolled on arrival."
const ESCORT_WARNING_SHORT := "⚠ +1 more"

# Whether committing to `choice` will put a SECOND body on the board. False for a
# BOSS round — a boss spawns solo, the tier change being step-up enough on its own
# (GameLoop2._spawn_escort) — for a free game with no enemy at all, and for the
# stay-or-return card, which spawns nothing either way.
func _escort_expected(choice: Dictionary) -> bool:
	if choice.is_empty() or choice.has("stay"):
		return false
	if choice.get("enemy") == null or bool(choice.get("boss", false)):
		return false
	return not Data.all_goal_enemies().is_empty()

# The escort's line for a card: a WARNING while the game is still an offer, and
# the body's NAME once the game has been committed to and the roll has happened.
# Empty when this card brings no escort. One function, because the offering, the
# popup and the now-playing panel all have to say the same thing about it.
func escort_note(choice: Dictionary) -> String:
	var landed: Dictionary = GameLoop2.arrival()
	if not landed.is_empty() and choice.get("enemy") != null \
			and landed.get("enemy") == choice.get("enemy"):
		var escort: GoalEnemyData = GameLoop2.escort_enemy()
		return "" if escort == null else "⚠ %s spawned alongside it." % escort.display_name
	return ESCORT_WARNING if _escort_expected(choice) else ""

# The hover, on ONE line: the enemy this card would put on the board, the goal you
# would be playing for, and the TEMPORARY SHIELDS it hands you. They used to be a slot on
# the HUD that previewed on hover; the HUD has gone, and this is the line that was
# already answering "what is that card" — so the number rides here instead of
# being the last thing keeping a panel alive.
#
# IT DOES NOT REPEAT THE GAME'S NAME. It used to open "Spelunky  →  …", which is
# the one thing on the line the player already has: their mouse is on that game's
# cover, with its title printed under it. The line is one line wide and the goal
# is the half that gets truncated, so the name was being paid for out of the only
# fact here that isn't already on screen. The stay-or-return pair is the exception
# below — there the game IS the answer, so those two keep their names.
func _hover_line(choice: Dictionary) -> String:
	var game: GameData = choice["game"]
	var e: GoalEnemyData = choice.get("enemy")
	if choice.has("stay"):
		return "[b]%s[/b]  ·  [i]%s[/i]" % [game.display_name,
			"stay here and carry on from this game"
			if bool(choice["stay"]) else "head back and carry on from there"]
	var tries: String = "  ·  [color=#%s]◆ %s[/color]" % [
		_page.SHIELD_BLUE.to_html(false),
		GameState.temp_shields_text(_hover_grant)] if _hover_grant >= 0 else ""
	if e == null:
		return "[i]no enemy — free game[/i]%s" % tries
	# The escort rides even the hidden line: the Dome hides WHAT is waiting, and how
	# many bodies arrive is not part of what it was bought to hide.
	var escort: String = "  ·  [color=#%s]%s[/color]" % [
		UITheme.DANGER.to_html(false), ESCORT_WARNING_SHORT] if _escort_expected(choice) else ""
	# Under the Runic Dome there is no enemy line to give: the goal is the enemy's,
	# so hiding the name and quoting the goal would give the whole thing away.
	if enemy_hidden(choice):
		return "[i]%s[/i]%s%s" % [HIDDEN_ENEMY_TEXT, escort, tries]
	var kind: String = "[color=#e0b020]☠ [/color]" if choice["boss"] else ""
	return "%s[b]%s[/b]  ·  %s%s%s" % [
		kind, e.display_name, _goal_line(_preview_entry(choice)), escort, tries]

# The goal with its ADD-ONS COLOURED IN PLACE (§13) — red for a condition a status
# added to it, green for one offered (a way out, a bonus).
#
# The other two screens that draw these give each add-on an indented row of its own
# (UITheme.addon_row); this one cannot, because it is one line under a cover and
# the goal is already the half of it that gets truncated. So it keeps the sentence
# `goal_text_for` writes and tints the clauses inside it, which is the same
# distinction in the room there is to draw it: the words that make the goal harder
# are red wherever the player meets them.
func _goal_line(entry: Dictionary) -> String:
	var line: String = GameLoop2.entry_goal(entry)
	for addon in GameLoop2.goal_addons_for(entry):
		# The bonus stays off this line, as it always has — `goal_text_for` never
		# carried it, because it is not part of what the goal asks.
		if String(addon["kind"]) == "bonus":
			continue
		line += "  [color=#%s]%s %s[/color]" % [
			UITheme.addon_color(bool(addon["required"])).to_html(false),
			addon["joiner"], addon["text"]]
	return line

# The board entry to read a `choice`'s goal line off (§13). Once the card has been
# taken, that is the live body it put on the board, statuses and all. For an
# OFFERED card there is no body yet — but the player's own clauses tax every
# enemy's goal, so the preview is built against a bare stand-in rather than
# falling back to the unmodified stem: what a card will actually cost you is part
# of the routing decision, not a surprise waiting on the report step.
func _preview_entry(choice: Dictionary) -> Dictionary:
	var landed: Dictionary = GameLoop2.arrival()
	if not landed.is_empty() and landed.get("enemy") == choice.get("enemy"):
		return landed
	return {"enemy": choice.get("enemy"), "statuses": {}}
