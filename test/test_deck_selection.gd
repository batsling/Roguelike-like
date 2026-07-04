extends GutTest

# Covers the deck/character split (DeckCatalog + GameState.selected_deck):
#   - the catalog's three decks and their reward tag filters
#   - deck_reward_tag follows the CHOSEN DECK while card_reward_tag (level-up)
#     stays on the CHARACTER, mirroring the HTML build where the two diverged
#   - reset_run restores the Random default
#   - GameStats deck-win recording: idempotent, per-character, and surviving a
#     save/load round-trip (including migration from the old bare-games shape)

func before_each() -> void:
	GameState.reset_run()

func after_each() -> void:
	GameState.reset_run()

# --- DeckCatalog -----------------------------------------------------------

func test_catalog_has_legacy_decks() -> void:
	var ids: Array = []
	for d in DeckCatalog.all():
		ids.append(String(d["id"]))
	assert_has(ids, "Random")
	assert_has(ids, "Ironclad")
	assert_has(ids, "Silent")

func test_tag_filters() -> void:
	assert_eq(String(DeckCatalog.tag_filter(&"Random")), "")
	assert_eq(String(DeckCatalog.tag_filter(&"Ironclad")), "ironclad")
	assert_eq(String(DeckCatalog.tag_filter(&"Silent")), "silent")
	# Unknown deck ids degrade to the unfiltered pool, never an error.
	assert_eq(String(DeckCatalog.tag_filter(&"nope")), "")

# --- GameState wiring ------------------------------------------------------

func test_deck_tag_follows_deck_not_character() -> void:
	var ironclad: CharacterData = Data.get_character(&"ironclad")
	assert_not_null(ironclad)
	GameState.apply_character(ironclad)
	GameState.selected_deck = &"Silent"
	# Combat/shop rewards follow the deck…
	assert_eq(String(GameState.deck_reward_tag()), "silent")
	# …while the level-up reward stays on the character's class.
	assert_eq(String(GameState.card_reward_tag()), "ironclad")

func test_random_deck_means_unfiltered() -> void:
	GameState.selected_deck = &"Random"
	assert_eq(String(GameState.deck_reward_tag()), "")

func test_reset_run_restores_default_deck() -> void:
	GameState.selected_deck = &"Ironclad"
	GameState.reset_run()
	assert_eq(String(GameState.selected_deck), String(DeckCatalog.DEFAULT_DECK_ID))

func test_deck_filtered_pool_only_has_deck_or_hero_cards() -> void:
	GameState.selected_deck = &"Silent"
	var pool: Array = Data.reward_card_pool(GameState.deck_reward_tag())
	assert_gt(pool.size(), 0, "Silent deck pool should not be empty")
	for c in pool:
		assert_true(c.tags.has("silent") or c.tags.has("hero"),
			"%s must be silent- or hero-tagged in the Silent deck pool" % c.id)

# --- GameStats deck wins ---------------------------------------------------

func test_record_deck_win_is_idempotent_and_per_character() -> void:
	var stats_backup: Dictionary = GameStats.stats
	var wins_backup: Dictionary = GameStats.deck_wins
	GameStats.deck_wins = {}
	GameStats.record_deck_win(&"ironclad", &"Silent")
	GameStats.record_deck_win(&"ironclad", &"Silent")
	assert_eq(GameStats.deck_wins_for(&"ironclad"), ["Silent"])
	assert_true(GameStats.has_deck_win(&"ironclad", &"Silent"))
	assert_false(GameStats.has_deck_win(&"ironclad", &"Random"))
	assert_false(GameStats.has_deck_win(&"silent", &"Silent"))
	# Empty ids are ignored (no run character / deck — nothing to record).
	GameStats.record_deck_win(&"", &"Silent")
	assert_false(GameStats.deck_wins.has(""))
	GameStats.stats = stats_backup
	GameStats.deck_wins = wins_backup
	GameStats.save_data()

func test_deck_wins_survive_save_load() -> void:
	var stats_backup: Dictionary = GameStats.stats
	var wins_backup: Dictionary = GameStats.deck_wins
	GameStats.deck_wins = {"ironclad": ["Random"]}
	GameStats.save_data()
	GameStats.load_data()
	assert_eq(GameStats.deck_wins_for(&"ironclad"), ["Random"])
	GameStats.stats = stats_backup
	GameStats.deck_wins = wins_backup
	GameStats.save_data()

func test_old_bare_games_stats_file_migrates() -> void:
	var stats_backup: Dictionary = GameStats.stats
	var wins_backup: Dictionary = GameStats.deck_wins
	# Write the pre-deck-wins shape: the bare game dictionary.
	var f := FileAccess.open(GameStats.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"hades": {"beaten": 2, "amulets": 1}}))
	f = null
	GameStats.load_data()
	assert_eq(GameStats.beaten_count(&"hades"), 2)
	assert_eq(GameStats.amulet_wins(&"hades"), 1)
	assert_eq(GameStats.deck_wins_for(&"ironclad"), [])
	GameStats.stats = stats_backup
	GameStats.deck_wins = wins_backup
	GameStats.save_data()
