extends GutTest

# The manual (HowToPlayText) and the screen that draws it.
#
# Two things are worth pinning here and they are not the obvious one. Nobody
# needs a test that the prose is good. What a test CAN hold is that the manual
# stays drawable and stays TRUE:
#
#   * drawable — every block carries a kind the screen knows, so a new block
#     type added to the text without a matching branch in the screen fails here
#     rather than silently rendering nothing on one page;
#   * true — the numbers in the manual are read off the constants that govern
#     them, so a balance change cannot leave the manual quietly lying to the
#     player. The tests below assert the values in the prose ARE the values in
#     the code, which is what makes the interpolation load-bearing rather than
#     decorative.

const MENU := preload("res://scenes/menu/MainMenu.tscn")

# Every kind HowToPlayScreen._block / _table can draw.
const KINDS := ["p", "b", "h", "kv", "note", "step", "row"]


func _all_text() -> String:
	var parts: Array = []
	for ch in HowToPlayText.chapters():
		parts.append(String(ch.get("title", "")))
		parts.append(String(ch.get("blurb", "")))
		for block in ch.get("blocks", []):
			parts.append(String(block.get("t", "")))
			parts.append(String(block.get("v", "")))
			for cell in block.get("c", []):
				parts.append(String(cell))
	return "\n".join(parts)


# --- the manual as data -----------------------------------------------------

func test_every_chapter_is_complete() -> void:
	var chapters: Array = HowToPlayText.chapters()
	assert_gt(chapters.size(), 0, "there is a manual")
	for ch in chapters:
		var title: String = String(ch.get("title", ""))
		assert_ne(title, "", "a chapter has a title")
		assert_ne(String(ch.get("id", "")), "", "%s has an id" % title)
		assert_ne(String(ch.get("icon", "")), "", "%s has an icon" % title)
		assert_ne(String(ch.get("blurb", "")), "",
			"%s has a blurb — the menu's contents panel shows it" % title)
		assert_gt((ch.get("blocks", []) as Array).size(), 0,
			"%s has something in it" % title)


func test_chapter_ids_are_unique() -> void:
	# Ids are how the menu's contents panel opens a page, so two chapters
	# sharing one would make a button open the wrong chapter.
	var seen: Dictionary = {}
	for ch in HowToPlayText.chapters():
		var id: StringName = StringName(ch["id"])
		assert_false(seen.has(id), "%s is used once" % id)
		seen[id] = true


func test_every_block_is_one_the_screen_can_draw() -> void:
	for ch in HowToPlayText.chapters():
		for block in ch.get("blocks", []):
			var kind: String = String(block.get("k", ""))
			assert_true(KINDS.has(kind),
				"%s in %s is a kind the screen knows" % [kind, ch["title"]])
			if kind == "row":
				assert_gt((block.get("c", []) as Array).size(), 0,
					"a table row has cells")
			else:
				assert_ne(String(block.get("t", "")), "",
					"a %s block in %s says something" % [kind, ch["title"]])
			if kind == "kv":
				assert_ne(String(block.get("v", "")), "",
					"a definition in %s defines something" % ch["title"])


func test_no_format_specifier_survives_into_the_prose() -> void:
	# The manual interpolates constants, and GDScript's `%` binds tighter than
	# `+` — so a multi-line string built with concatenation puts the operator on
	# the LAST fragment only, and the "%d" in the first one is printed to the
	# player verbatim. That is a real bug this file shipped once; this is the
	# assertion that catches it next time.
	var text: String = _all_text()
	for spec in ["%d", "%s", "%f", "%x"]:
		assert_false(text.contains(spec),
			"no raw %s left unformatted in the manual" % spec)


# --- the manual agrees with the build ---------------------------------------

func test_the_shields_the_manual_quotes_are_the_shields_the_build_grants() -> void:
	var text: String = _all_text()
	assert_string_contains(text, "%d %ss" % [GameLoop2.SHIELDS_PER_GAME,
		GameState.TEMP_SHIELD_NAME])
	assert_string_contains(text, "%d — the long haul gets more" % GameLoop2.SHIELDS_TRADITIONAL)
	# And the two pools are named the way the rest of the build names them, so a
	# rename cannot leave the manual teaching a word nothing on screen says.
	assert_string_contains(text, GameState.TEMP_SHIELD_NAME)
	assert_string_contains(text, GameState.SHIELD_NAME)


func test_the_pressure_ladder_the_manual_prints_is_the_real_one() -> void:
	var text: String = _all_text()
	for hops in [0, 2, 3, 4, 5, 9]:
		var extra: int = RunDifficulty.extra_turns_for_hops(hops)
		assert_string_contains(text, "%d" % extra)
	assert_string_contains(text, "%d or more" % RunDifficulty.FAR_HOPS)


func test_the_economy_the_manual_quotes_is_the_real_one() -> void:
	var text: String = _all_text()
	assert_string_contains(text, "+%d gold" % GameLoop2.GOLD_PER_ENEMY)
	assert_string_contains(text, "+%d gold" % GameLoop2.GOLD_PER_BOSS)
	assert_string_contains(text, "Common %d" % ShopSystem.BASE_PRICE)
	assert_string_contains(text, "Legendary %d" % (ShopSystem.BASE_PRICE + 3))
	assert_string_contains(text, "%d best-connected games" % RunGraph.NUM_HUBS)
	assert_string_contains(text, "%d items, rolled once" % ShopSystem.STOCK_SLOTS)


func test_the_escape_rule_the_manual_quotes_is_the_real_one() -> void:
	# The gate is a HIT now, not a count of lost runs (§3.2) — so the manual must
	# be teaching the hit, and must not be quoting a threshold that no longer
	# exists anywhere in the build.
	var text: String = _all_text()
	assert_string_contains(text, "takes Health off you during this game")
	assert_false(text.contains("lost runs, or immediately"),
		"the old five-lost-runs gate is gone from the manual too")


# --- the screen -------------------------------------------------------------

func test_every_chapter_draws() -> void:
	# The real assertion is that nothing throws and every page puts SOMETHING on
	# the screen — a chapter whose blocks all fell through the match in _block
	# would come out blank rather than erroring.
	var screen := HowToPlayScreen.new()
	add_child_autofree(screen)
	await wait_frames(2)
	for i in range(HowToPlayText.chapters().size()):
		screen.go_to(i)
		await wait_frames(1)
		assert_gt(screen._body.get_child_count(), 0,
			"chapter %d drew something" % (i + 1))


func test_a_chapter_opens_by_id_not_by_position() -> void:
	# The menu's contents panel passes ids precisely so that inserting a chapter
	# in the middle does not repoint every button below it.
	var screen := HowToPlayScreen.new()
	add_child_autofree(screen)
	await wait_frames(2)
	for ch in HowToPlayText.chapters():
		var id: StringName = StringName(ch["id"])
		screen.go_to(id)
		assert_eq(String(screen._title_label.text).strip_edges(),
			("%s  %s" % [ch["icon"], ch["title"]]).strip_edges(),
			"go_to(%s) opened %s" % [id, ch["title"]])


func test_an_unknown_id_opens_the_first_chapter_rather_than_nothing() -> void:
	var screen := HowToPlayScreen.new()
	add_child_autofree(screen)
	await wait_frames(2)
	screen.go_to(&"no_such_chapter")
	assert_eq(screen._index, 0, "an unknown page falls back to the beginning")


func test_the_pager_stops_at_both_ends() -> void:
	var screen := HowToPlayScreen.new()
	add_child_autofree(screen)
	await wait_frames(2)
	screen.go_to(0)
	assert_true(screen._prev_btn.disabled, "nothing before the first chapter")
	assert_false(screen._next_btn.disabled)
	screen.go_to(HowToPlayText.chapters().size() - 1)
	assert_false(screen._prev_btn.disabled)
	assert_true(screen._next_btn.disabled, "nothing after the last one")


func _buttons_in(node: Node) -> Array:
	var out: Array = []
	if node is Button:
		out.append(node)
	for c in node.get_children():
		out.append_array(_buttons_in(c))
	return out


# --- the menu's one way into the manual ------------------------------------
#
# The bottom-left corner panel (a contents list with every chapter) is gone: the
# button above Start Run is the only entry point now, so the menu has one door
# into the manual rather than two.

func test_the_menu_opens_the_manual_from_its_button() -> void:
	var menu = MENU.instantiate()
	add_child_autofree(menu)
	await wait_frames(2)
	assert_null(menu.get_node_or_null("HowToPlayCorner"),
		"the corner panel is gone from the menu")
	menu._on_how_to_play()
	await wait_frames(2)
	var opened: HowToPlayScreen = null
	for c in menu._modal_layer.get_children():
		if c is HowToPlayScreen:
			opened = c
	assert_not_null(opened, "the button still opens the manual")

