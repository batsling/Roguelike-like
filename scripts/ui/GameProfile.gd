extends RefCounted
# A GAME'S PROFILE, as a hover card: the map's game card without its buttons —
# the name, the cover with its rank, the genre, and the facts (released,
# connections, times beaten, Amulet wins, owned, enemies beaten). Built from the
# run's header strip (the owner, 20 Nov 2026: "you can hover over any of the
# games to see its profile"), with an optional first line saying what the game
# is to this run ("you are here", "the Amulet — 6 steps").
#
# No class_name and loaded BY PATH (HoverCard.of), because the page only builds
# one when the mouse asks for it (test_page_load.gd).

const WIDTH := 272.0
const ART_WIDTH := 248.0

static func build(game: GameData, note: String = "", note_color: Color = UITheme.ACCENT) -> Control:
	if game == null:
		return null
	var panel := PanelContainer.new()
	panel.name = "GameProfile"
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(Color(UITheme.PANEL, 0.985), 8, 12, 1, UITheme.BORDER))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP)
	panel.add_child(box)
	fill(box, game, note, note_color)
	return panel

# The profile's contents, into `box`: what the hover card and the map's rift
# card both show.
static func fill(box: VBoxContainer, game: GameData, note: String = "",
		note_color: Color = UITheme.ACCENT) -> void:
	var title := Label.new()
	title.text = game.display_name
	title.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = ART_WIDTH
	box.add_child(title)
	if note != "":
		var n := Label.new()
		n.text = note
		n.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		n.add_theme_color_override("font_color", note_color)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size.x = ART_WIDTH
		box.add_child(n)
	if game.cover_image != null:
		var cover := UITheme.card_art(game.cover_image, ART_WIDTH)
		UITheme.attach_tier_badge(cover, game.id)
		box.add_child(RankBadge.wrap(cover, game.id))
	var chip := Label.new()
	chip.text = RunGraph.type_label(game.type).to_upper()
	chip.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	chip.add_theme_color_override("font_color", RunGraph.type_color(game.type))
	box.add_child(chip)

	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	box.add_child(facts)
	for f in facts_for(game):
		facts.add_child(_fact(String(f[0]), String(f[1])))

# The facts as [label, value] rows, worded as the map's card words them. Public
# so a test can read what the profile says.
static func facts_for(game: GameData) -> Array:
	var out: Array = []
	if game.year > 0:
		out.append(["Released", str(game.year)])
	out.append(["Connections", str(RunGraph.degree(game.id))])
	var beaten_times: int = GameStats.beaten_count(game.id)
	out.append(["⚔ Beaten", ("%d time%s" % [beaten_times, "" if beaten_times == 1 else "s"])
		if beaten_times > 0 else "never"])
	var amulet_runs: int = GameStats.amulet_wins(game.id)
	if amulet_runs > 0:
		out.append(["👑 Amulet won", "%d run%s" % [amulet_runs, "" if amulet_runs == 1 else "s"]])
	if GameState.has_beaten_game(game.id):
		out.append(["Status", "beaten this run"])
	out.append(["Owned", "yes" if Ownership.is_owned(game) else "no"])
	var possible: int = GameLoop2.possible_enemies_at(game).size()
	var fought: int = GameStats.enemies_for(game.id).size()
	if possible > 0 or fought > 0:
		out.append(["Enemies beaten", "%d / %d" % [fought, maxi(possible, fought)]])
	return out

static func _fact(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size.x = 96
	k.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	k.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	v.add_theme_color_override("font_color", UITheme.TEXT)
	row.add_child(v)
	return row
