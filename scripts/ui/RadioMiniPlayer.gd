class_name RadioMiniPlayer
extends HBoxContainer

# ROGUELIKE RADIO, AT A GLANCE (docs/roguelike-radio.md): the 📻 that opens the
# radio screen, and — while a song is loaded — the cover of the game it came
# from, then ⏮ ⏸ ⏭. Back, pause and skip are what a player reaches for most, and
# they used to be a screen away; the cover says whose song it is without a word.
#
# One widget for both places the radio sits: the main menu's top-right corner and
# the run's header. Each says how big it is (`size_px`, `font`), and what the 📻
# opens (`on_open`), because those are the two things the places differ in.

var on_open: Callable = Callable()
# The height of every control in the row (0: the buttons' own height, as the
# rest of a header row has), and the glyphs' font size (0: the theme's).
var size_px: float = 0.0
var font: int = 0

var radio_button: Button = null
var cover: TextureRect = null
var back_button: Button = null
var play_button: Button = null
var skip_button: Button = null
var _controls: Array = []

static func make(open_cb: Callable, height: float, font_size: int) -> RadioMiniPlayer:
	var p := RadioMiniPlayer.new()
	p.on_open = open_cb
	p.size_px = height
	p.font = font_size
	p._build()
	return p

func _build() -> void:
	name = "RadioMiniPlayer"
	add_theme_constant_override("separation", UITheme.GAP_SNUG)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	radio_button = _button("📻", func():
		if on_open.is_valid():
			on_open.call())
	radio_button.name = "RadioBtn"
	add_child(radio_button)

	cover = TextureRect.new()
	cover.name = "NowPlayingCover"
	# 3:4, like every cover; in a row of natural height it takes the row's.
	cover.custom_minimum_size = Vector2(size_px * 0.75, size_px) if size_px > 0.0 \
		else Vector2(24, 0)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.clip_contents = true
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)

	back_button = _button("⏮", func(): Radio.previous())
	back_button.name = "RadioBack"
	back_button.tooltip_text = "Back — the start of this song, or the one before it."
	play_button = _button("⏸", func(): Radio.toggle_pause())
	play_button.name = "RadioPlay"
	skip_button = _button("⏭", func(): Radio.next())
	skip_button.name = "RadioSkip"
	skip_button.tooltip_text = "Skip to the next song."
	for b in [back_button, play_button, skip_button]:
		add_child(b)
	_controls = [cover, back_button, play_button, skip_button]

	refresh()

func _ready() -> void:
	# A METHOD, not a lambda: a bound method is disconnected when this node goes,
	# and the radio outlives every screen it sits on.
	if not Radio.changed.is_connected(refresh):
		Radio.changed.connect(refresh)

func _button(text: String, cb: Callable) -> Button:
	var b := HoverButton.new()
	b.text = text
	if size_px > 0.0:
		b.custom_minimum_size = Vector2(size_px, size_px)
	if font > 0:
		b.add_theme_font_size_override("font_size", font)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

# Show the now-playing half only while there is a song to show; keep the tooltips
# and the pause glyph true to the radio.
func refresh() -> void:
	if radio_button == null:
		return
	var song: SongData = Radio.current_song()
	radio_button.tooltip_text = "Roguelike Radio — every song you have unlocked, the stations and the volume."
	for c in _controls:
		(c as Control).visible = song != null
	if song == null:
		return
	var game: GameData = Data.get_game(song.game_id)
	cover.texture = game.cover_image if game != null else null
	cover.visible = cover.texture != null
	cover.tooltip_text = "Now playing %s%s." % [song.title,
		(" — %s" % game.display_name) if game != null else ""]
	radio_button.tooltip_text = "%s\n%s" % [cover.tooltip_text, radio_button.tooltip_text]
	play_button.text = "⏸" if Radio.is_playing() else "▶"
	play_button.tooltip_text = "Pause." if Radio.is_playing() else "Play."
