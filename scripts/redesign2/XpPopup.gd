extends Control
# XP, AS IT LANDS (the owner, 18 Nov 2026: "pop up the experience bars from the
# bottom right of the screen and show them growing and then do a popup if
# there's a level up").
#
# A goal ticked mid-game is written into the record at once, and a game's and a
# character's XP are read off that record (GameRanks), so the climb happens while
# the game is still on. This is where it is shown: a small card slides up out of
# the bottom-right corner with the game's and the character's rank bars, fills
# them from where they stood, holds, and slides away. A bar that crosses into a
# new rank raises the RANK UP banner in the middle of the screen once it has
# filled. Neither takes a click; both get out of the way on their own.
#
# One card at a time: a second gain while one is up REPLACES it, filling on from
# where the first started, so a burst of ticks is one climb, not a stack.
#
# Overworld2 watches for the gain (`_check_xp_gain`) and opens this BY PATH, like
# every screen the page only opens on demand (test_page_load.gd).

const SLIDE := 0.28
const HOLD := 2.4
const WIDTH := 380.0
const MARGIN := 16.0
const BANNER_HOLD := 1.6

var game_from: int = 0
var game_to: int = 0
var char_from: int = 0
var char_to: int = 0
var _game: GameData = null
var _char: CharacterData = null
var _card: PanelContainer = null
var _tween: Tween = null

static func open(host: Node, layer: CanvasLayer, game: GameData, gfrom: int, gto: int,
		character: CharacterData, cfrom: int, cto: int) -> Control:
	var pop = load("res://scripts/redesign2/XpPopup.gd").new()
	pop._game = game
	pop._char = character
	pop.game_from = gfrom
	pop.game_to = gto
	pop.char_from = cfrom
	pop.char_to = cto
	layer.add_child(pop)
	return pop

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_card = PanelContainer.new()
	_card.name = "XpCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(WIDTH, 0)
	_card.add_theme_stylebox_override("panel",
		UITheme.flat(Color(UITheme.BG_DEEP, 0.96), 10, 12, 2, UITheme.GOLD.lerp(UITheme.BORDER, 0.3)))
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)
	var gained: int = maxi(game_to - game_from, char_to - char_from)
	var head := Label.new()
	head.text = "+%d XP" % gained
	head.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	head.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(head)
	if _game != null and game_to > game_from:
		col.add_child(_bar_row(_game.cover_image, false, game_from, game_to, _game.display_name))
	if _char != null and char_to > char_from:
		col.add_child(_bar_row(_char.shown_icon(), true, char_from, char_to, _char.display_name))
	_play.call_deferred()

func _bar_row(art: Texture2D, character: bool, from: int, to: int, who: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if art != null:
		var pic: TextureRect = UITheme.crisp_tex(art, 34) if character else TextureRect.new()
		if not character:
			pic.texture = art
			pic.custom_minimum_size = Vector2(26, 34)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
	var bar: RankFill = RankFill.make(from, to, who, character, false)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	return row

# Up out of the corner, the bars fill (RankFill tweens itself), hold, back down.
func _play() -> void:
	if not is_inside_tree():
		return
	# Measured off its MINIMUM: on the frame it is built the container has not laid
	# itself out yet, and a size of zero parks the card off the corner.
	var want: Vector2 = _card.get_combined_minimum_size()
	_card.size = want
	var view: Vector2 = get_viewport_rect().size
	var shown := Vector2(view.x - want.x - MARGIN, view.y - want.y - MARGIN)
	_card.position = Vector2(shown.x, view.y + 4.0)
	_tween = create_tween()
	_tween.tween_property(_card, "position", shown, SLIDE) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(RankFill.FILL_TIME)
	_tween.tween_callback(_rank_up_banners)
	_tween.tween_interval(HOLD)
	_tween.tween_property(_card, "position", Vector2(shown.x, view.y + 4.0), SLIDE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(queue_free)

# The rank-ups this card's climb crossed, as [{who, rank}].
func rank_ups() -> Array:
	var out: Array = []
	if _game != null and GameRanks.rank_for(game_to) > GameRanks.rank_for(game_from):
		out.append({"who": _game.display_name, "rank": GameRanks.rank_for(game_to)})
	if _char != null and GameRanks.rank_for(char_to) > GameRanks.rank_for(char_from):
		out.append({"who": _char.display_name, "rank": GameRanks.rank_for(char_to)})
	return out

func _rank_up_banners() -> void:
	var ups: Array = rank_ups()
	for i in range(ups.size()):
		var banner := _banner(String(ups[i]["who"]), int(ups[i]["rank"]))
		get_parent().add_child(banner)
		banner.set_meta(&"delay", i * 0.5)
		_show_banner(banner, i * 0.5)

# RANK UP, in the middle of the screen: the word, whose, and the rank it reached.
func _banner(who: String, rank: int) -> Control:
	var wrap := CenterContainer.new()
	wrap.name = "RankUpBanner"
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel",
		UITheme.flat(Color(UITheme.BG_DEEP, 0.94), 14, 18, 3, UITheme.GOLD))
	wrap.add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var word := Label.new()
	word.text = "RANK UP!"
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_font_size_override("font_size", UITheme.FONT_DISPLAY)
	word.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(word)
	var line := Label.new()
	line.text = "%s  ·  Rank %d" % [who, rank]
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	line.add_theme_color_override("font_color", UITheme.TEXT)
	col.add_child(line)
	return wrap

func _show_banner(banner: Control, delay: float) -> void:
	banner.modulate.a = 0.0
	var card: Control = banner.get_child(0)
	card.pivot_offset = card.size * 0.5
	var tw := banner.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2(0.6, 0.6))
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(BANNER_HOLD)
	tw.tween_property(banner, "modulate:a", 0.0, 0.3)
	tw.tween_callback(banner.queue_free)
