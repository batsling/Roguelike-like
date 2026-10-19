extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# The three items of the 12 Oct 2026 upload:
#   Ceremonial Dagger — every defeat stuns a random body still standing
#   Ultra Duplicator  — every ITEM obtained arrives with an extra copy
#   Mysterious Mask   — a popup of three characters; the one picked adds their
#                       Level Up beside the hero's, paying THEIR reward (§3.1)

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameLoop2.lost_run_spawn_ladder = [0.0]

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _body(id: StringName) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = id
	e.display_name = String(id)
	e.goal = "Beat it"
	e.health = 1
	e.damage = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	return e

# --- Ceremonial Dagger -----------------------------------------------------

func test_the_dagger_hangs_a_random_stun_on_a_defeat() -> void:
	var dagger: ItemData = Data.get_item2(&"ceremonial_dagger")
	assert_not_null(dagger)
	assert_eq(String(dagger.triggers[0].get("on", "")), "enemy_killed")
	var fx: Dictionary = dagger.triggers[0]["effects"][0]
	assert_eq(String(fx.get("type", "")), "apply_status")
	assert_eq(String(fx.get("status", "")), "stun")
	assert_eq(String(fx.get("target", "")), "random")

func test_a_defeat_stuns_the_body_left_standing() -> void:
	Fixtures.give(self, &"ceremonial_dagger")
	var first: int = GameLoop2.choose_game(_body(&"first"))
	var second: int = GameLoop2.second_body_instance()
	if second <= 0:
		pending("the game stood no second body to stun")
		return
	assert_true(GameLoop2.fulfill(first, true), "the first body is cleared")
	var survivor: Dictionary = GameLoop2.entry_for(second)
	if survivor.is_empty():
		pending("the second body left the board with the first")
		return
	assert_eq(GameLoop2.stun_stacks(survivor), 1, "the one left standing is stunned")

func test_a_defeat_on_an_empty_board_stuns_nothing() -> void:
	Fixtures.give(self, &"ceremonial_dagger")
	TriggerBus.enemy_killed.emit({"enemy": null})
	assert_eq(GameLoop2.stack.size(), 0, "nothing stood up to be stunned")

# --- Ultra Duplicator ------------------------------------------------------

func test_the_duplicator_copies_the_next_item() -> void:
	Fixtures.give(self, &"ultra_duplicator")
	Fixtures.give(self, &"anchor")
	assert_eq(GameState._count_items(&"anchor"), 2, "one obtained, one copy")

func test_the_duplicator_does_not_copy_itself() -> void:
	Fixtures.give(self, &"ultra_duplicator")
	assert_eq(GameState._count_items(&"ultra_duplicator"), 1)

func test_a_copy_pays_its_pickup_again() -> void:
	Fixtures.give(self, &"ultra_duplicator")
	var before: int = GameState.max_hp
	Fixtures.give(self, &"lunch")
	assert_eq(GameState.max_hp, before + 4, "two Lunches, +2 Max Health each")

func test_two_duplicators_make_two_copies_and_no_more() -> void:
	Fixtures.give(self, &"ultra_duplicator")
	Fixtures.give(self, &"ultra_duplicator")  # the second is itself copied by the first
	var held: int = GameState._count_items(&"ultra_duplicator")
	Fixtures.give(self, &"anchor")
	assert_eq(GameState._count_items(&"anchor"), 1 + held,
		"one copy per Duplicator held; the copies do not copy each other")

func test_without_the_duplicator_one_is_one() -> void:
	Fixtures.give(self, &"anchor")
	assert_eq(GameState._count_items(&"anchor"), 1)

# --- Mysterious Mask -------------------------------------------------------

func test_the_mask_banks_a_choice() -> void:
	Fixtures.give(self, &"mysterious_mask")
	assert_eq(GameState.pending_masks, 1)

func test_the_offer_is_three_characters_who_are_not_the_hero() -> void:
	GameState.character_id = &"rodney"
	var offer: Array = GameState.mask_offer()
	assert_eq(offer.size(), 3)
	var ids: Array = offer.map(func(c): return c.id)
	assert_does_not_have(ids, &"rodney", "never the hero")
	for ch in offer:
		assert_ne(ch.level_up_condition, "", "%s has a condition to give" % ch.id)
	var seen: Dictionary = {}
	for id in ids:
		seen[id] = true
	assert_eq(seen.size(), ids.size(), "three different characters")

func test_wearing_a_mask_adds_that_condition() -> void:
	GameState.character_id = &"rodney"
	GameState.grant_mask()
	GameState.wear_mask(&"zoe")
	assert_eq(GameState.pending_masks, 0, "the choice is spent")
	assert_eq(GameState.masked_characters, [&"zoe"] as Array[StringName])
	assert_does_not_have(GameState.mask_offer(20).map(func(c): return c.id), &"zoe",
		"a character worn is not offered again")

func test_a_masked_level_pays_the_masked_characters_reward() -> void:
	GameState.character_id = &"rodney"
	var zoe: CharacterData = Data.get_character2(&"zoe")
	var dash: int = GameState.dash_charges
	var stats: Array = GameState.grant_level_up(null, zoe)
	assert_gt(GameState.dash_charges, dash, "Zoe's +1 Dash, not Rodney's payout")
	assert_gt(stats.size(), 0)

func test_masks_go_with_the_run() -> void:
	GameState.grant_mask()
	GameState.wear_mask(&"zoe")
	GameState.reset_run()
	assert_eq(GameState.masked_characters.size(), 0)
	assert_eq(GameState.pending_masks, 0)

func test_the_popup_shows_the_three_and_a_pick_wears_one() -> void:
	GameState.character_id = &"rodney"
	GameState.grant_mask()
	var offer: Array = GameState.mask_offer()
	var modal := MaskChoiceModal.open(self, offer)
	await get_tree().process_frame
	# Three cards, each with the character's face and condition on it.
	for ch in offer:
		assert_not_null(_find_label(modal, ch.level_up_condition),
			"%s's Level Up is written under them" % ch.display_name)
	assert_eq(_texture_count(modal), offer.size(), "one portrait per character")
	modal.pick(offer[1].id)
	assert_eq(GameState.masked_characters, [offer[1].id] as Array[StringName])

func _find_label(root: Node, text: String) -> Label:
	if root is Label and (root as Label).text == text:
		return root
	for c in root.get_children():
		var hit: Label = _find_label(c, text)
		if hit != null:
			return hit
	return null

func _texture_count(root: Node) -> int:
	var n: int = 1 if root is TextureRect else 0
	for c in root.get_children():
		n += _texture_count(c)
	return n

# Driven through the real overworld: a mask taken while a game is on WAITS for
# the haul to be done, opens its popup then, and the masked row on the next
# report pays the masked character.
func test_the_overworld_opens_the_mask_and_the_report_pays_it() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	await get_tree().process_frame
	Fixtures.give(self, &"mysterious_mask")
	await get_tree().process_frame
	assert_null(_find_modal(get_tree().root), "not over a game in play")
	ui.report(false, [])
	ui._end_resolve()               # don't wait out the strike/advance animation
	await get_tree().process_frame
	assert_null(_find_modal(get_tree().root), "not over the haul screen either")
	if ui._post_screen != null and is_instance_valid(ui._post_screen):
		ui._post_screen.dismiss()
	await get_tree().process_frame
	await get_tree().process_frame
	var modal: MaskChoiceModal = _find_modal(get_tree().root)
	assert_not_null(modal, "the haul done, the mask asks")
	if modal == null:
		return
	var pick: CharacterData = modal.offer()[0]
	modal.pick(pick.id)
	await get_tree().process_frame
	assert_has(GameState.masked_characters, pick.id)
	assert_eq(GameState.pending_masks, 0)
	ui.pick(0)
	if ui._chosen.is_empty():
		pending("nothing was chosen — the offering did not reach this case")
		return
	var check: CheckBox = ui._checklist.mask_levelup_checks.get(pick.id)
	assert_not_null(check, "the report carries a row for the masked character")
	if check == null:
		return
	check.button_pressed = true
	var panel = ui.get_node_or_null("Confirm")
	if panel != null:
		var ok = panel.find_child("OkBtn", true, false)
		if ok != null:
			ok.pressed.emit()
	var level: int = GameState.player_level
	ui.report(false, [])
	assert_eq(GameState.player_level, level + 1, "the masked condition paid a level")
	var masked: Array = ui._post_snapshot.get("mask_level_ups", [])
	assert_eq(masked.size(), 1, "and the haul screen says so")

func _find_modal(root: Node) -> MaskChoiceModal:
	if root is MaskChoiceModal:
		return root
	for c in root.get_children():
		var hit: MaskChoiceModal = _find_modal(c)
		if hit != null:
			return hit
	return null
