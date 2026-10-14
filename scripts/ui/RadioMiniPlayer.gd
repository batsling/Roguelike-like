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
var ticker: Ticker = null
var back_button: Button = null
var play_button: Button = null
var skip_button: Button = null
var _controls: Array = []

# THE LAYOUT (the owner, Oct 2026: "more compact and make sense"): the 📻, then
# the cover WHOLE (letterboxed, never cropped: it is box art, and the title is
# often at the edge), then a stack of two — what is playing on top, scrolling,
# and the three buttons under it, smaller. The same footprint the row of four
# full-size buttons had, give or take, with the song named on it.
const TICKER_W := 128.0
const COMPACT_BUTTON_SHARE := 0.55   # the small buttons, as a share of the row height
const NATURAL_ROW_H := 40.0          # the height the header's own buttons stand at

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
	var row_h: float = size_px if size_px > 0.0 else NATURAL_ROW_H

	radio_button = _button("📻", func():
		if on_open.is_valid():
			on_open.call())
	radio_button.name = "RadioBtn"
	if size_px > 0.0:
		radio_button.custom_minimum_size = Vector2(size_px, size_px)
	if font > 0:
		radio_button.add_theme_font_size_override("font_size", font)
	add_child(radio_button)

	cover = TextureRect.new()
	cover.name = "NowPlayingCover"
	# 3:4, like every cover, at the row's height — and KEEP_ASPECT_CENTERED, so a
	# cover of any other shape is shown whole inside that box rather than cut.
	cover.custom_minimum_size = Vector2(roundf(row_h * 0.75), row_h)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)

	var stack := VBoxContainer.new()
	stack.name = "NowPlaying"
	stack.add_theme_constant_override("separation", UITheme.GAP_NONE)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)

	ticker = Ticker.new()
	ticker.name = "NowPlayingTicker"
	ticker.font_size = UITheme.FONT_SMALL if row_h < 44.0 else UITheme.FONT_BODY
	ticker.custom_minimum_size = Vector2(TICKER_W, row_h * (1.0 - COMPACT_BUTTON_SHARE))
	stack.add_child(ticker)

	var buttons := HBoxContainer.new()
	buttons.name = "RadioButtons"
	buttons.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(buttons)
	var small: float = roundf(row_h * COMPACT_BUTTON_SHARE)

	back_button = _button("⏮", func(): Radio.previous(), small)
	back_button.name = "RadioBack"
	back_button.tooltip_text = "Back — the start of this song, or the one before it."
	play_button = _button("⏸", func(): Radio.toggle_pause(), small)
	play_button.name = "RadioPlay"
	skip_button = _button("⏭", func(): Radio.next(), small)
	skip_button.name = "RadioSkip"
	skip_button.tooltip_text = "Skip to the next song."
	for b in [back_button, play_button, skip_button]:
		buttons.add_child(b)
	_controls = [cover, stack]

	refresh()

func _ready() -> void:
	# A METHOD, not a lambda: a bound method is disconnected when this node goes,
	# and the radio outlives every screen it sits on.
	if not Radio.changed.is_connected(refresh):
		Radio.changed.connect(refresh)

# `side` > 0: a small square button for the stack, with the small type.
func _button(text: String, cb: Callable, side: float = 0.0) -> Button:
	var b := HoverButton.new()
	b.text = text
	if side > 0.0:
		b.custom_minimum_size = Vector2(side * 1.3, side)
		b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		# The theme's button padding would make a 22px button 30px tall.
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb: StyleBox = b.get_theme_stylebox(state, "Button")
			if sb != null:
				var tight: StyleBox = sb.duplicate()
				tight.content_margin_top = 0
				tight.content_margin_bottom = 0
				tight.content_margin_left = UITheme.GAP_HAIR
				tight.content_margin_right = UITheme.GAP_HAIR
				b.add_theme_stylebox_override(state, tight)
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
	ticker.set_text("%s  —  %s" % [song.title, game.display_name] if game != null else song.title)
	ticker.tooltip_text = cover.tooltip_text
	radio_button.tooltip_text = "%s\n%s" % [cover.tooltip_text, radio_button.tooltip_text]
	play_button.text = "⏸" if Radio.is_playing() else "▶"
	play_button.tooltip_text = "Pause." if Radio.is_playing() else "Play."

# THE SCROLLING LINE: "Song — Game", gliding left in a fixed-width window and
# coming round again, the way a car radio's display does. A line that fits is
# left still, centred, because scrolling text that did not need to is noise.
class Ticker extends Control:
	const SPEED := 28.0     # pixels a second
	const GAP := 36.0       # between the end of the line and its next pass
	const HOLD := 1.5       # seconds it rests at the start of each pass
	var font_size: int = 11
	var _text: String = ""
	var _x: float = 0.0
	var _hold: float = HOLD

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_text(t: String) -> void:
		if t == _text:
			return
		_text = t
		_x = 0.0
		_hold = HOLD
		queue_redraw()

	func text_width() -> float:
		return get_theme_default_font().get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x

	func scrolls() -> bool:
		return text_width() > size.x

	func _process(delta: float) -> void:
		if not is_visible_in_tree() or not scrolls():
			return
		if _hold > 0.0:
			_hold -= delta
			return
		_x += SPEED * delta
		var loop: float = text_width() + GAP
		if _x >= loop:
			_x -= loop
			_hold = HOLD
		queue_redraw()

	func _draw() -> void:
		if _text == "":
			return
		var f: Font = get_theme_default_font()
		var w: float = text_width()
		var base: float = (size.y + f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
		var color: Color = UITheme.TEXT
		if w <= size.x:
			draw_string(f, Vector2((size.x - w) * 0.5, base), _text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			return
		draw_string(f, Vector2(-_x, base), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		draw_string(f, Vector2(-_x + w + GAP, base), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
