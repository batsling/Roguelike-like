extends GutTest

# Validates the four events ported from the legacy HTML/Excel content
# (Watching Eyeballs, Fruit Basket, A Note For Yourself, The Ssssserpent)
# and the supporting plumbing they rely on: the new event-effect vocabulary,
# the Fly swarm enemy, the item-by-tag lookup, and the ambush / spawn / note
# carryover fields on GameState.
#
# These are data-layer checks (no EventModal UI) so they pin the content and
# the cross-references without needing a live combat scene.

const PORTED_EVENTS := [
	"watching_eyeballs", "fruit_basket", "note_for_yourself", "the_ssssserpent",
]

# Effect "type" values EventModal._apply_event_effect knows how to resolve.
const HANDLED_EFFECTS := [
	"none", "heal", "heal_percent", "lose_hp", "gain_gold", "gold_range",
	"lose_gold", "combat_status", "item_tagged", "curse_card", "active_curse",
	"combat_flag", "spawn_enemies", "note_for_yourself",
]

func _all_effects(ev: EventData) -> Array:
	var out: Array = []
	for choice in ev.choices:
		if choice.has("outcome"):
			out.append_array(choice["outcome"].get("effects", []))
		for key in choice.get("outcomes", {}).keys():
			out.append_array(choice["outcomes"][key].get("effects", []))
	return out

# --- The events exist and are well-formed --------------------------------

func test_all_ported_events_load() -> void:
	for id in PORTED_EVENTS:
		var ev: EventData = Data.get_event(StringName(id))
		assert_not_null(ev, "event '%s' should load" % id)
		assert_false(ev.choices.is_empty(), "event '%s' has choices" % id)

func test_legacy_placeholder_events_removed() -> void:
	# The original Godot-authored sample events were dropped in favour of the
	# ported content; the pool should be exactly the four ported events.
	assert_eq(Data.all_events().size(), PORTED_EVENTS.size(),
		"only the ported events remain in the pool")
	for stale in ["bandit_ambush", "cursed_chest", "merchant_offer"]:
		assert_null(Data.get_event(StringName(stale)),
			"stale event '%s' should be gone" % stale)

func test_every_effect_type_is_handled() -> void:
	for id in PORTED_EVENTS:
		var ev: EventData = Data.get_event(StringName(id))
		for eff in _all_effects(ev):
			var t: String = String(eff.get("type", ""))
			assert_true(HANDLED_EFFECTS.has(t),
				"effect '%s' in '%s' is handled by EventModal" % [t, id])

# --- Cross-referenced content exists -------------------------------------

func test_fly_swarm_enemy_exists_but_is_unweighted() -> void:
	var fly: EnemyData = Data.get_enemy(&"fly")
	assert_not_null(fly, "Fruit Basket summons the Fly enemy")
	assert_eq(fly.weight, 0, "Fly never appears in the random roster")

func test_ssssserpent_and_eyeballs_curses_exist() -> void:
	assert_not_null(Data.get_card(&"greed"), "The Ssssserpent grants the Greed curse card")
	assert_not_null(Data.get_curse(&"curse_of_ocular_trauma"),
		"Watching Eyeballs inflicts Curse of Ocular Trauma")
	assert_not_null(Data.get_card(&"iron_wave"),
		"A Note For Yourself defaults to Iron Wave")

func test_item_tags_resolve_to_real_items() -> void:
	for tag in ["coin", "eye", "seed"]:
		assert_false(Data.items_with_tag(StringName(tag)).is_empty(),
			"at least one item is tagged '%s'" % tag)
		assert_not_null(Data.random_item_by_tag(StringName(tag)),
			"random_item_by_tag('%s') returns an item" % tag)

func test_random_item_by_tag_returns_null_for_unknown_tag() -> void:
	assert_null(Data.random_item_by_tag(&"definitely_not_a_real_tag"))

# --- Carryover state -------------------------------------------------------

func test_reset_run_clears_event_carryover() -> void:
	GameState.pending_ambush = "ambush"
	GameState.pending_spawn_enemies.append({"enemy": &"fly", "count": 3})
	GameState.note_for_yourself_card = &"strike"
	GameState.reset_run()
	assert_eq(GameState.pending_ambush, "", "ambush flag cleared on reset")
	assert_true(GameState.pending_spawn_enemies.is_empty(), "spawn queue cleared on reset")
	assert_eq(GameState.note_for_yourself_card, &"", "stored note card cleared on reset")
