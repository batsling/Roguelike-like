class_name ProofView
extends RefCounted

# A CONNECTION'S PROOF, SHOWN: the thumbnail that stands in a proof slot and the
# full-size view a click on it opens. Two screens show a proof — the game card
# (GameChoiceModal's source block) and the full map's connection card (AtlasView)
# — and they used to carry a copy each, which had already drifted (the map's clip
# had no ✕). Both build from here now.
#
# The lookup — which file proves which connection — stays on GameChoiceModal
# (`proof_texture`, `proof_video`, `proof_poster`), where the naming rules live.
#
# Node names are what the tests find: "ProofFrame" (the clickable thumbnail),
# "Proof" (its picture), "PlayMark" (the ▶ on a clip), "ProofView" (the shade a
# click opens) and "ProofVideo" (the clip playing in it).

# The thumbnail for the connection from -> to, or null when it has no proof on
# file. A screenshot is scaled to the slot's WIDTH and no further (never up:
# blowing a line of text past its own size only blurs it), so text stays
# readable; a tall one shows its top `max_h` px and is read in full by clicking.
# A clip is its poster with a ▶ over it. A click calls `on_open(tex, video)`,
# `video` null for a screenshot.
static func thumb(from_id: StringName, to_id: StringName, max_h: float,
		on_open: Callable) -> Control:
	var video: VideoStream = GameChoiceModal.proof_video(from_id, to_id)
	var tex: Texture2D = GameChoiceModal.proof_poster(from_id, to_id) if video != null \
		else GameChoiceModal.proof_texture(from_id, to_id)
	if tex == null:
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	# The frame clips; the picture inside is sized from the frame's width each
	# time the slot settles, which a TextureRect's own stretch modes can't do
	# (they fit BOTH ways, which is what shrank a tweet to 140px tall).
	var frame := Control.new()
	frame.name = "ProofFrame"
	frame.clip_contents = true
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.tooltip_text = "Click to play the clip" if video != null else "Click to read it full size"
	var art := TextureRect.new()
	art.name = "Proof"
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	if video != null:
		# A ▶ over the poster's middle, so the thumbnail reads as a clip at a glance
		# and not as a screenshot of a video.
		var play := Label.new()
		play.name = "PlayMark"
		play.text = "▶"
		play.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		play.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		play.set_anchors_preset(Control.PRESET_FULL_RECT)
		play.mouse_filter = Control.MOUSE_FILTER_IGNORE
		play.add_theme_font_size_override("font_size", UITheme.FONT_HERO)
		play.add_theme_color_override("font_color", Color.WHITE)
		play.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		play.add_theme_constant_override("outline_size", 8)
		frame.add_child(play)
	var more := Label.new()
	more.text = "Click to read all of it"
	more.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	more.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	more.visible = false
	box.add_child(frame)
	box.add_child(more)
	var fit := func():
		var scale: float = minf(1.0, frame.size.x / float(tex.get_width())) if frame.size.x > 0.0 else 1.0
		var shown: Vector2 = tex.get_size() * scale
		art.position = Vector2.ZERO
		art.size = shown
		frame.custom_minimum_size.y = minf(shown.y, max_h)
		more.visible = video == null and shown.y > max_h + 0.5
	frame.resized.connect(fit)
	fit.call()
	frame.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			frame.accept_event()
			on_open.call(tex, video))
	return box

# THE PROOF OVER `host`, full size: the screenshot at its own size (or the
# window's, less `margin` each side, if it is bigger), or the clip PLAYING at
# `shape` scaled to the window. A click on the clip pauses and resumes it (and
# starts it again once it has finished); any other click, or the clip's ✕, calls
# `on_close` — which frees the shade (the host keeps the handle, for Escape).
# Added to `host` and returned.
static func overlay(host: Control, tex: Texture2D, video: VideoStream, shape: Vector2,
		margin: Vector2, on_close: Callable) -> Control:
	var shade := ColorRect.new()
	shade.name = "ProofView"
	shade.color = Color(UITheme.BG_DEEP, 0.92 if video != null else 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var window: Vector2 = host.get_viewport_rect().size
	var room: Vector2 = window - margin * 2.0
	if shape.x <= 0.0 or shape.y <= 0.0:
		shape = Vector2(16, 9)
	var fit: float = minf(room.x / shape.x, room.y / shape.y)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(centre)
	var player: VideoStreamPlayer = null
	if video != null:
		player = VideoStreamPlayer.new()
		player.name = "ProofVideo"
		player.stream = video
		player.expand = true
		player.custom_minimum_size = shape * fit
		player.mouse_filter = Control.MOUSE_FILTER_STOP
		player.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		player.tooltip_text = "Click to pause or play"
		player.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				player.accept_event()
				if not player.is_playing():
					player.paused = false
					player.play()
				else:
					player.paused = not player.paused)
		centre.add_child(player)
		var close := Button.new()
		close.text = "✕"
		close.tooltip_text = "Close (Esc)"
		close.position = Vector2(window.x - margin.x - 40.0, margin.y * 0.5)
		close.pressed.connect(on_close)
		shade.add_child(close)
	else:
		# Never scaled UP: a screenshot of text blurs past its own size.
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = shape * minf(1.0, fit)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		centre.add_child(art)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			shade.accept_event()
			on_close.call())
	host.add_child(shade)
	if player != null:
		player.play()
	return shade
