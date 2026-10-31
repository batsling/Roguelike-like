extends GutTest

# HEADINGS AND BUTTONS IN ROGUE'S FONT (UITheme "Rogue's font"): every Label at a
# heading's size and every Button labelled at FONT_BODY or more is set in the IBM
# PC font, at a crisp multiple of 16; small text, and a button that is really a
# sentence, keep the ordinary font.

func _added(c: Control) -> Control:
	add_child_autofree(c)
	await get_tree().process_frame   # the rule runs deferred, after the build
	await get_tree().process_frame
	return c

func _rogue(c: Control) -> bool:
	return c.has_theme_font_override("font") and c.get_theme_font("font") == UITheme.rogue_font()

func test_the_font_loads_and_draws_symbols_through_the_glyph_fonts() -> void:
	var f: Font = UITheme.rogue_font()
	assert_not_null(f, "Px437 loads")
	assert_true(f.has_char("A".unicode_at(0)), "with letters")
	assert_true(f.fallbacks.has(UITheme.glyph_font()), "and the symbol fonts behind it")

func test_a_heading_is_set_in_it_at_a_crisp_size() -> void:
	for spec in [[UITheme.FONT_SUB, 16], [UITheme.FONT_HEAD, 16], [UITheme.FONT_TITLE_LG, 16],
			[UITheme.FONT_DISPLAY, 32], [UITheme.FONT_HERO, 32]]:
		var l := Label.new()
		l.text = "Heading"
		l.add_theme_font_size_override("font_size", spec[0])
		await _added(l)
		assert_true(_rogue(l), "a %dpx heading is Rogue's" % spec[0])
		assert_eq(l.get_theme_font_size("font_size"), spec[1], "at %dpx" % spec[1])

func test_small_text_keeps_the_ordinary_font() -> void:
	var l := Label.new()
	l.text = "body"
	l.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	await _added(l)
	assert_false(_rogue(l), "13px prose stays readable")
	var plain := Label.new()
	plain.text = "no size of its own"
	await _added(plain)
	assert_false(_rogue(plain), "a label at the theme's size is body text")

func test_a_button_is_set_in_it_unless_it_is_a_sentence() -> void:
	var b := Button.new()
	b.text = "Map"
	await _added(b)
	assert_true(_rogue(b), "a button's label is Rogue's")
	assert_eq(b.get_theme_font_size("font_size"), 16)
	var chip := Button.new()
	chip.text = "x"
	chip.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	await _added(chip)
	assert_false(_rogue(chip), "a chip under FONT_BODY keeps the ordinary font")
	var wrapped := Button.new()
	wrapped.text = "Defeat a vampire with a melee weapon"
	wrapped.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	await _added(wrapped)
	assert_false(_rogue(wrapped), "a goal row that wraps reads in the ordinary font")
	var two := Button.new()
	two.text = "Lost a run\n+1 Enemy Turn"
	await _added(two)
	assert_false(_rogue(two), "and so does one on two lines")

func test_a_control_with_its_own_font_keeps_it() -> void:
	var l := Label.new()
	var mine := SystemFont.new()
	l.add_theme_font_override("font", mine)
	l.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	await _added(l)
	assert_eq(l.get_theme_font("font"), mine)
	assert_eq(l.get_theme_font_size("font_size"), UITheme.FONT_TITLE, "at its own size")

# A control freed in the frame between being added and the rule running (a screen
# built and torn down at once) is passed over quietly rather than erroring.
func test_a_control_freed_before_the_rule_runs_is_passed_over() -> void:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	add_child(l)
	l.free()
	await get_tree().process_frame
	UITheme._apply_rogue_rule(l)
	assert_true(true, "no crash on a freed control")
