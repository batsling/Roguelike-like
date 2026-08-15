extends GutTest

# Ownership — the switch between the catalog's shipped "Owned" column and a list
# the player builds themselves, plus the Steam sync that seeds that list.
#
# The invariants worth defending: the spreadsheet column is never written to, so
# switching back restores it exactly; a sync only ever adds, so a game ticked by
# hand for a copy Steam has never heard of survives the next sync; and every
# filter in the game reads the switch rather than `GameData.owned` directly.

const SAMPLE_XML := """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<gamesList>
	<steamID64>76561197960287930</steamID64>
	<games>
		<game><appID>%d</appID><name>One</name></game>
		<game><appID>%d</appID><name>Two</name></game>
		<game><appID>999999999</appID><name>Not in the catalog</name></game>
	</games>
</gamesList>"""

var _saved_source: int = 0

func before_each() -> void:
	_saved_source = Ownership.source
	Ownership.set_source(Ownership.Source.MANUAL)
	Ownership._manual.clear()

func after_each() -> void:
	Ownership._manual.clear()
	Ownership.set_source(_saved_source)
	RunConfig.reset()

# Catalog games carrying a store link, which are the only ones a Steam sync can
# ever speak for.
func _linked_games(want: int) -> Array:
	var out: Array = []
	for g in Data.all_games():
		if g is GameData and (g as GameData).steam_app_id() != "":
			out.append(g)
			if out.size() >= want:
				break
	return out

# --- the switch ------------------------------------------------------------

func test_the_catalog_source_reads_the_shipped_column() -> void:
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	var owned_in_sheet: int = 0
	for g in Data.all_games():
		if g is GameData:
			assert_eq(Ownership.is_owned(g), (g as GameData).owned,
				"catalog source must be the .tres column verbatim")
			if (g as GameData).owned:
				owned_in_sheet += 1
	assert_eq(Ownership.owned_count(), owned_in_sheet)
	assert_true(owned_in_sheet > 0, "the shipped catalog does mark games owned")

func test_the_players_own_list_starts_empty_and_ignores_the_column() -> void:
	assert_eq(Ownership.owned_count(), 0, "a fresh manual list owns nothing")
	for g in Data.all_games():
		if g is GameData:
			assert_false(Ownership.is_owned(g),
				"not even games the catalog marks owned")

func test_switching_back_restores_the_catalogs_answer_exactly() -> void:
	var game: GameData = Data.all_games()[0]
	Ownership.set_manual_owned(game.id, not game.owned)
	var before: bool = game.owned
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	assert_eq(game.owned, before, "the .tres column is never written to")
	assert_eq(Ownership.is_owned(game), before)
	Ownership.set_source(Ownership.Source.MANUAL)
	assert_eq(Ownership.is_owned(game), not before, "and the manual list survived")

func test_ticking_a_game_is_refused_while_the_catalog_is_the_source() -> void:
	var game: GameData = Data.all_games()[0]
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	Ownership.set_manual_owned(game.id, true)
	assert_eq(Ownership.manual_count(), 0,
		"a tick that nothing would read must not be silently stored")
	assert_false(Ownership.is_editable())

func test_ticking_and_unticking_moves_the_answer() -> void:
	var game: GameData = Data.all_games()[0]
	assert_true(Ownership.toggle_manual(game.id), "toggle reports the new state")
	assert_true(Ownership.is_owned(game))
	assert_true(Ownership.owns_id(game.id), "and by id, for callers without the resource")
	assert_false(Ownership.toggle_manual(game.id))
	assert_false(Ownership.is_owned(game))

func test_clearing_empties_the_list_without_touching_the_catalog() -> void:
	for g in _linked_games(3):
		Ownership.set_manual_owned((g as GameData).id, true)
	assert_eq(Ownership.manual_count(), 3)
	Ownership.clear_manual()
	assert_eq(Ownership.manual_count(), 0)
	Ownership.set_source(Ownership.Source.SPREADSHEET)
	assert_true(Ownership.owned_count() > 0, "the catalog's column is still there")

func test_nothing_the_player_does_writes_the_catalogs_column() -> void:
	# The sheet is upstream of data/games/*.tres and is regenerated from
	# tools/Roguelikes.xlsx, so a runtime write would be both a lie about what the
	# catalog says and something the next import silently reverts. Ticking games
	# and running a sync must leave every one of the 849 columns where it was.
	var before: Dictionary = {}
	for g in Data.all_games():
		if g is GameData:
			before[(g as GameData).id] = (g as GameData).owned
	for g in _linked_games(5):
		Ownership.set_manual_owned((g as GameData).id, true)
	Ownership.apply_appids(Ownership.parse_appids(SAMPLE_XML % [
		int((_linked_games(1)[0] as GameData).steam_app_id()), 620]))
	var moved: Array = []
	for g in Data.all_games():
		if g is GameData and (g as GameData).owned != before[(g as GameData).id]:
			moved.append((g as GameData).id)
	assert_eq(moved, [], "the catalog's own column is read-only at runtime")

# --- the filters read the switch ------------------------------------------

func test_the_owned_path_filter_follows_the_players_list() -> void:
	var game: GameData = Data.all_games()[0]
	var was: int = Settings.game_filter
	Settings.set_game_filter(Settings.GameFilter.OWNED)
	assert_false(RunGraph.passes_filter(game), "nothing is owned yet")
	Ownership.set_manual_owned(game.id, true)
	assert_true(RunGraph.passes_filter(game), "ticking it lets it onto the map")
	Settings.set_game_filter(was)

func test_the_custom_runs_library_filter_follows_the_players_list() -> void:
	var game: GameData = Data.all_games()[0]
	var owned_spec: Dictionary = RunConfig.default_spec()
	owned_spec["library"] = RunConfig.Library.OWNED
	var not_owned_spec: Dictionary = RunConfig.default_spec()
	not_owned_spec["library"] = RunConfig.Library.NOT_OWNED
	assert_false(RunConfig.spec_passes(owned_spec, game))
	assert_true(RunConfig.spec_passes(not_owned_spec, game))
	Ownership.set_manual_owned(game.id, true)
	assert_true(RunConfig.spec_passes(owned_spec, game))
	assert_false(RunConfig.spec_passes(not_owned_spec, game))

# --- reading a Steam profile ----------------------------------------------

func test_a_vanity_name_and_a_steam_id_address_different_paths() -> void:
	assert_true(Ownership.profile_url("batsling").contains("/id/batsling/games"),
		"a name is a vanity URL")
	assert_true(Ownership.profile_url("76561197960287930").contains("/profiles/76561197960287930/"),
		"a 17-digit number is a SteamID64")
	assert_true(Ownership.profile_url("https://steamcommunity.com/id/batsling/").contains("/id/batsling/games"),
		"and a pasted profile URL is accepted as-is")
	assert_true(Ownership.profile_url("batsling").ends_with("xml=1"),
		"every form asks for the XML rather than the web page")

func test_appids_are_read_out_of_the_games_list() -> void:
	var ids: PackedInt64Array = Ownership.parse_appids(SAMPLE_XML % [440, 620])
	assert_eq(ids.size(), 3)
	assert_true(ids.has(440) and ids.has(620) and ids.has(999999999))

func test_a_private_profile_is_recognised_from_the_body() -> void:
	# Steam answers a private profile with HTTP 200 and an error element, so the
	# status code alone would read as success.
	assert_true(Ownership.is_private_profile(
		"<response><error>This profile is private.</error></response>"))
	assert_false(Ownership.is_private_profile(SAMPLE_XML % [440, 620]))

func test_a_sync_marks_the_catalog_games_the_library_contains() -> void:
	var linked: Array = _linked_games(2)
	assert_eq(linked.size(), 2, "the catalog has games with Steam links")
	var a: GameData = linked[0]
	var b: GameData = linked[1]
	var report: Dictionary = Ownership.apply_appids(
		Ownership.parse_appids(SAMPLE_XML % [int(a.steam_app_id()), int(b.steam_app_id())]))
	assert_true(Ownership.is_owned(a), "a game in the library is now owned")
	assert_true(Ownership.is_owned(b))
	assert_eq(int(report["matched"]), 2, "and only the two the catalog knows")
	assert_eq(int(report["added"]), 2)
	assert_eq(int(report["appids"]), 3, "the third appid isn't a game we catalogue")
	assert_true(int(report["catalog_linked"]) > 0,
		"the report says how many games a sync could ever speak for")

func test_a_second_sync_adds_nothing_and_says_so() -> void:
	var linked: Array = _linked_games(1)
	var a: GameData = linked[0]
	var ids: PackedInt64Array = Ownership.parse_appids(SAMPLE_XML % [int(a.steam_app_id()), 0])
	Ownership.apply_appids(ids)
	var second: Dictionary = Ownership.apply_appids(ids)
	assert_eq(int(second["added"]), 0)
	assert_eq(int(second["already"]), 1, "it was already ticked")
	assert_true(Ownership.is_owned(a))

func test_a_sync_never_unticks_a_game_the_player_marked_by_hand() -> void:
	# The reason the manual list is the player's and not Steam's: a GOG, itch,
	# emulated or borrowed copy has no appid to match, and must not be wiped by
	# the next sync.
	var unlinked: GameData = null
	for g in Data.all_games():
		if g is GameData and (g as GameData).steam_app_id() == "":
			unlinked = g
			break
	assert_not_null(unlinked, "the catalog has games with no Steam link")
	Ownership.set_manual_owned(unlinked.id, true)
	var linked: Array = _linked_games(1)
	Ownership.apply_appids(Ownership.parse_appids(
		SAMPLE_XML % [int((linked[0] as GameData).steam_app_id()), 0]))
	assert_true(Ownership.is_owned(unlinked), "the hand-ticked game is still owned")

func test_an_empty_name_fails_before_any_request_goes_out() -> void:
	var report: Dictionary = await Ownership.sync_from_steam("   ")
	assert_false(report["ok"])
	assert_ne(str(report["error"]), "", "and says why")

# --- the diagnostic dump ---------------------------------------------------
#
# The live request is the one half of the sync that can't be exercised in a test
# (it needs steamcommunity.com), so when it misbehaves the useful artefact is
# Steam's own reply rather than a description of it.

func test_there_is_nothing_to_dump_before_a_sync_has_run() -> void:
	Ownership._last_reply = ""
	Ownership._last_reply_url = ""
	assert_false(Ownership.has_last_reply())
	assert_eq(Ownership.dump_last_reply(), "", "and asking writes no file")

func test_the_dump_carries_the_reply_and_what_was_asked_for() -> void:
	Ownership._last_reply = SAMPLE_XML % [440, 620]
	Ownership._last_reply_url = "https://steamcommunity.com/id/batsling/games?tab=all&xml=1"
	Ownership._last_reply_status = 200
	assert_true(Ownership.has_last_reply())
	var path: String = Ownership.dump_last_reply()
	assert_ne(path, "", "the dump reports where it landed")
	var f: FileAccess = FileAccess.open(Ownership.REPLY_DUMP_PATH, FileAccess.READ)
	assert_not_null(f, "and the file is there to read")
	var text: String = f.get_as_text()
	f.close()
	assert_true(text.contains("<appID>440</appID>"), "the reply is in it verbatim")
	assert_true(text.contains("/id/batsling/games"), "headed by the URL asked for")
	assert_true(text.contains("http status: 200"), "and the status that came back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ownership.REPLY_DUMP_PATH))

# --- persistence -----------------------------------------------------------

func test_the_list_survives_a_save_and_load() -> void:
	var linked: Array = _linked_games(2)
	for g in linked:
		Ownership.set_manual_owned((g as GameData).id, true)
	Ownership.steam_username = "batsling"
	Ownership.save_ownership()
	Ownership._manual.clear()
	Ownership.load_ownership()
	assert_eq(Ownership.manual_count(), 2)
	for g in linked:
		assert_true(Ownership.is_owned(g), "%s came back owned" % (g as GameData).id)
	assert_eq(Ownership.source, Ownership.Source.MANUAL, "and the source came back")
	assert_eq(Ownership.steam_username, "batsling")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ownership.config_path()))

# --- what Steam says when it says no ---------------------------------------
#
# The live request is the one part of this that no test can exercise, and the
# first real sync came back "Steam listed no games" — a message that describes
# our own parse result rather than Steam's answer. Steam explains itself in an
# <error> element; repeating it beats guessing.

func test_steams_own_error_is_read_out_of_the_reply() -> void:
	assert_eq(Ownership.steam_error_in(
		"<response><error>This profile is private.</error></response>"),
		"This profile is private.")
	assert_eq(Ownership.steam_error_in(
		"<response><error>The specified profile could not be found.</error></response>"),
		"The specified profile could not be found.")
	assert_eq(Ownership.steam_error_in(SAMPLE_XML % [440, 620]), "",
		"a good reply has no error to report")

func test_a_cdata_wrapped_error_is_still_read() -> void:
	# Steam wraps some fields in CDATA, and the words are what matter either way.
	assert_eq(Ownership.steam_error_in(
		"<response><error><![CDATA[This profile is private.]]></error></response>"),
		"This profile is private.")

func test_markup_inside_an_error_is_stripped() -> void:
	assert_eq(Ownership.steam_error_in(
		"<error>Profile <b>not</b> found.</error>"), "Profile not found.")

func test_the_privacy_hint_names_the_setting_to_change() -> void:
	# "Set your profile to public" is the wrong instruction — the profile can be
	# public while the games list is not. It is the Game details setting.
	assert_true(Ownership.PRIVACY_HINT.contains("Game details"))

# --- asking the way a browser asks -----------------------------------------

func test_steam_is_asked_with_a_browser_user_agent() -> void:
	# Godot identifies itself as GodotEngine/<version> by default, and
	# steamcommunity serves non-browser agents something other than the page. A
	# sync that returns 200 with no games in it is what that looks like.
	var joined: String = " ".join(PackedStringArray(Ownership.STEAM_HEADERS))
	assert_true(joined.contains("User-Agent:"), "a User-Agent is sent")
	assert_false(joined.contains("Godot"), "and it is not Godot's own")
	assert_true(joined.contains("Mozilla/5.0"))

func test_the_games_page_json_is_read_when_the_xml_is_not_there() -> void:
	# `xml=1` is an old parameter on a page Steam has rewritten more than once.
	# When the reply is the ordinary page instead, the games are still in it.
	var page := '<html><script>var rgGames = [{"appid":440,"name":"One"},{"appid":620,"name":"Two"}];</script></html>'
	var ids: PackedInt64Array = Ownership.parse_appids(page)
	assert_eq(ids.size(), 2, "both games were read out of the page")
	assert_true(ids.has(440) and ids.has(620))

func test_the_xml_shape_still_wins_when_both_are_present() -> void:
	var mixed := (SAMPLE_XML % [440, 620]) + '<script>{"appid":999}</script>'
	var ids: PackedInt64Array = Ownership.parse_appids(mixed)
	assert_false(ids.has(999), "the games list is the answer, not the page around it")
	assert_true(ids.has(440))

func test_the_games_url_is_the_one_steam_serves_today() -> void:
	var url: String = Ownership.profile_url("batsling1234")
	assert_true(url.contains("/id/batsling1234/games/"),
		"the games page, with the trailing slash Steam's own links carry")
	assert_true(url.ends_with("xml=1"))
