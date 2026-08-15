extends GutTest

# Save profiles — separate players on one install.
#
# The invariant the whole feature rests on is ISOLATION: nothing saved under one
# profile may be readable, writable or even visible under another. That is easy
# to get right for files (they're in different directories) and easy to get wrong
# for the autoloads that hold those files in memory, which is where these tests
# spend most of their time — a store that early-returns when its file is missing
# keeps the previous player's data and quietly hands it to the next one.

var _origin: String = ""
var _made: Array = []

func before_each() -> void:
	_origin = Profiles.active_id
	_made = []

func after_each() -> void:
	if Profiles.has_profile(_origin):
		Profiles.switch_to(_origin)
	for id in _made:
		if id != Profiles.active_id:
			Profiles.delete(id)
	_made = []

func _make(profile_name: String) -> String:
	var id: String = Profiles.create(profile_name)
	_made.append(id)
	return id

# --- the list --------------------------------------------------------------

func test_there_is_always_a_profile_to_be_playing() -> void:
	assert_gt(Profiles.count(), 0, "boot creates one if there is none")
	assert_ne(Profiles.active_id, "", "and one of them is active")
	assert_true(Profiles.has_profile(Profiles.active_id))
	assert_ne(Profiles.active_name(), "", "with a name to show in the menu")

func test_creating_a_profile_does_not_enter_it() -> void:
	var before: String = Profiles.active_id
	var id: String = _make("Second Player")
	assert_ne(id, "", "the profile was made")
	assert_eq(Profiles.active_id, before,
		"creating and entering are two decisions, in that order")
	assert_eq(Profiles.name_of(id), "Second Player")

func test_a_profile_needs_a_name() -> void:
	assert_eq(Profiles.create("   "), "", "whitespace is not a name")
	assert_eq(Profiles.create(""), "")

func test_names_are_tidied_not_rejected() -> void:
	var id: String = _make("  Bat   sling  ")
	assert_eq(Profiles.name_of(id), "Bat sling", "trimmed, and runs of space collapsed")
	var long_id: String = _make("x".repeat(Profiles.MAX_NAME_LEN + 20))
	assert_eq(Profiles.name_of(long_id).length(), Profiles.MAX_NAME_LEN, "and capped")

func test_two_profiles_can_share_a_name_without_sharing_a_directory() -> void:
	# The name is the player's; the id is the directory. Two "Player 1"s must not
	# end up reading each other's saves.
	var a: String = _make("Twin")
	var b: String = _make("Twin")
	assert_ne(a, b, "same name, different id")
	assert_eq(Profiles.name_of(a), Profiles.name_of(b))

func test_renaming_keeps_everything_but_the_name() -> void:
	var id: String = _make("Before")
	assert_true(Profiles.rename(id, "After"))
	assert_eq(Profiles.name_of(id), "After")
	assert_true(Profiles.has_profile(id), "same profile, same id")
	assert_false(Profiles.rename(id, "  "), "and it still needs a name")
	assert_eq(Profiles.name_of(id), "After")

func test_the_last_profile_cannot_be_deleted() -> void:
	# Deleting it would leave the game with nowhere to save, and the next boot
	# would silently invent a replacement — which reads as "my profile vanished".
	while Profiles.count() > 1:
		for p in Profiles.list():
			if str(p["id"]) != Profiles.active_id:
				Profiles.delete(str(p["id"]))
	assert_eq(Profiles.count(), 1)
	assert_false(Profiles.delete(Profiles.active_id), "refused")
	assert_eq(Profiles.count(), 1)

# --- isolation -------------------------------------------------------------

func test_each_profile_writes_to_its_own_directory() -> void:
	var a: String = _make("Dir A")
	var b: String = _make("Dir B")
	Profiles.switch_to(a)
	var a_dir: String = Profiles.dir()
	var a_saves: String = SaveSystem.save_dir()
	Profiles.switch_to(b)
	assert_ne(Profiles.dir(), a_dir, "the profile directory moved")
	assert_ne(SaveSystem.save_dir(), a_saves, "and the saves moved with it")
	assert_true(SaveSystem.save_dir().begins_with(Profiles.dir()),
		"saves live under the active profile")
	assert_true(GameStats.save_path().begins_with(Profiles.dir()))
	assert_true(TierList.save_path().begins_with(Profiles.dir()))
	assert_true(Ownership.config_path().begins_with(Profiles.dir()))
	assert_true(Settings.prefs_path().begins_with(Profiles.dir()))

func test_owned_games_do_not_follow_the_player_into_another_profile() -> void:
	var a: String = _make("Owner")
	var b: String = _make("Newcomer")
	var game: GameData = Data.all_games()[0]

	Profiles.switch_to(a)
	Ownership.set_source(Ownership.Source.MANUAL)
	Ownership.set_manual_owned(game.id, true)
	assert_true(Ownership.is_owned(game))

	Profiles.switch_to(b)
	assert_eq(Ownership.manual_count(), 0,
		"a new profile starts with an empty list, not the last player's")
	assert_eq(Ownership.source, Ownership.Source.SPREADSHEET,
		"and at the default source")

	Profiles.switch_to(a)
	assert_true(Ownership.is_owned(game), "and the first player's list came back")
	assert_eq(Ownership.source, Ownership.Source.MANUAL)

func test_lifetime_stats_do_not_follow_the_player() -> void:
	var a: String = _make("Stats A")
	var b: String = _make("Stats B")
	var game: GameData = Data.all_games()[0]

	Profiles.switch_to(a)
	var was: int = GameStats.beaten_count(game.id)
	GameStats.record_beaten(game.id)
	assert_eq(GameStats.beaten_count(game.id), was + 1)

	Profiles.switch_to(b)
	assert_eq(GameStats.beaten_count(game.id), 0, "the new profile has played nothing")

	Profiles.switch_to(a)
	assert_eq(GameStats.beaten_count(game.id), was + 1, "and the record came back")

func test_run_settings_do_not_follow_the_player() -> void:
	var a: String = _make("Prefs A")
	var b: String = _make("Prefs B")

	Profiles.switch_to(a)
	Settings.set_game_filter(Settings.GameFilter.OWNED)
	Profiles.switch_to(b)
	assert_eq(Settings.game_filter, Settings.GameFilter.ALL,
		"a new profile takes the default filter, not the last player's")
	Profiles.switch_to(a)
	assert_eq(Settings.game_filter, Settings.GameFilter.OWNED, "and it came back")
	Settings.set_game_filter(Settings.GameFilter.ALL)

func test_the_window_and_dev_mode_are_shared_by_every_profile() -> void:
	# These describe the machine, not the player. Switching profile to find your
	# resolution changed would be a bug in every reading of it.
	var a: String = _make("Global A")
	var b: String = _make("Global B")
	Profiles.switch_to(a)
	var mode: int = Settings.display_mode
	var size: Vector2i = Settings.windowed_size
	Profiles.switch_to(b)
	assert_eq(Settings.display_mode, mode, "window mode is global")
	assert_eq(Settings.windowed_size, size, "so is the window size")

func test_deleting_a_profile_takes_its_directory_with_it() -> void:
	var doomed: String = _make("Doomed")
	Profiles.switch_to(doomed)
	Ownership.set_source(Ownership.Source.MANUAL)
	Ownership.set_manual_owned(Data.all_games()[0].id, true)
	var dir_path: String = ProjectSettings.globalize_path(Profiles.dir())
	assert_true(DirAccess.dir_exists_absolute(dir_path), "it has a directory")
	Profiles.switch_to(_origin)
	assert_true(Profiles.delete(doomed))
	assert_false(DirAccess.dir_exists_absolute(dir_path), "and it is gone from disk")
	assert_false(Profiles.has_profile(doomed))
	_made.erase(doomed)

func test_deleting_the_profile_being_played_moves_the_player_somewhere_real() -> void:
	var other: String = _make("Standby")
	var doomed: String = _make("Playing")
	Profiles.switch_to(doomed)
	assert_eq(Profiles.active_id, doomed)
	assert_true(Profiles.delete(doomed), "you can delete the one you're in")
	assert_ne(Profiles.active_id, doomed, "but you don't stay in it")
	assert_true(Profiles.has_profile(Profiles.active_id),
		"the game is always in a profile that exists")
	_made.erase(doomed)
	assert_true(Profiles.has_profile(other))

# --- the index -------------------------------------------------------------

func test_the_list_survives_a_reload() -> void:
	var id: String = _make("Persisted")
	Profiles._load_index()
	assert_true(Profiles.has_profile(id), "the profile came back")
	assert_eq(Profiles.name_of(id), "Persisted")
	assert_true(Profiles.has_profile(Profiles.active_id), "and so did the active one")

func test_an_unknown_active_id_falls_back_rather_than_writing_nowhere() -> void:
	# An active id with no profile behind it would leave every store writing to
	# `user://profiles//` — one shared directory wearing no one's name.
	var real: String = Profiles.active_id
	Profiles.active_id = "does_not_exist"
	Profiles._save_index()
	Profiles._load_index()
	assert_true(Profiles.has_profile(Profiles.active_id), "fell back to a real profile")
	Profiles.switch_to(real) if Profiles.active_id != real else null
	Profiles.active_id = real
	Profiles._save_index()

func test_a_profile_directory_is_never_the_root() -> void:
	assert_true(Profiles.dir().begins_with(Profiles.ROOT))
	assert_gt(Profiles.dir().length(), Profiles.ROOT.length() + 1,
		"there is an id between the root and the files")
	assert_true(Profiles.path("x.cfg").ends_with("/x.cfg"))

# --- wiping ----------------------------------------------------------------
#
# The main menu's "Clear All Data" button is gone; this is what replaced it. The
# difference from delete is that the profile survives — it is "start over as me",
# so it is offered on the profile being played, which delete never is.

func test_wiping_empties_a_profile_but_keeps_it() -> void:
	var id: String = _make("Wipe me")
	Profiles.switch_to(id)
	var game: GameData = Data.all_games()[0]
	Ownership.set_source(Ownership.Source.MANUAL)
	Ownership.set_manual_owned(game.id, true)
	GameStats.record_beaten(game.id)
	Settings.set_game_filter(Settings.GameFilter.OWNED)

	assert_true(Profiles.wipe(id))
	assert_true(Profiles.has_profile(id), "the profile is still there")
	assert_eq(Profiles.name_of(id), "Wipe me", "with its name")
	assert_eq(Profiles.active_id, id, "and is still the one being played")
	assert_eq(GameStats.beaten_count(game.id), 0, "its stats are gone")
	assert_eq(Ownership.manual_count(), 0, "its owned list is gone")
	assert_eq(Ownership.source, Ownership.Source.SPREADSHEET, "back to the default source")
	assert_eq(Settings.game_filter, Settings.GameFilter.ALL, "and its run settings")

func test_wiping_leaves_somewhere_for_saves_to_go() -> void:
	# The wipe deletes the saves directory the game is holding open. Something has
	# to put it back, or the next save writes into a directory that isn't there.
	var id: String = _make("Wipe saves")
	Profiles.switch_to(id)
	assert_true(Profiles.wipe(id))
	assert_true(DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(SaveSystem.save_dir())),
		"the saves directory was recreated")
	assert_true(DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(SaveSystem.named_save_dir())))

func test_wiping_one_profile_leaves_the_others_alone() -> void:
	var keep: String = _make("Keeper")
	var doomed: String = _make("Wiped")
	var game: GameData = Data.all_games()[0]

	Profiles.switch_to(keep)
	GameStats.record_beaten(game.id)
	var kept: int = GameStats.beaten_count(game.id)

	Profiles.switch_to(doomed)
	GameStats.record_beaten(game.id)
	assert_true(Profiles.wipe(doomed))
	assert_eq(GameStats.beaten_count(game.id), 0)

	Profiles.switch_to(keep)
	assert_eq(GameStats.beaten_count(game.id), kept, "the other profile is untouched")

func test_wiping_a_profile_you_are_not_playing_does_not_touch_your_data() -> void:
	var other: String = _make("Elsewhere")
	var mine: String = _make("Mine")
	var game: GameData = Data.all_games()[0]
	Profiles.switch_to(other)
	GameStats.record_beaten(game.id)
	Profiles.switch_to(mine)
	GameStats.record_beaten(game.id)
	var before: int = GameStats.beaten_count(game.id)
	assert_true(Profiles.wipe(other), "wiped from outside it")
	assert_eq(GameStats.beaten_count(game.id), before,
		"the profile being played is unaffected")
	Profiles.switch_to(other)
	assert_eq(GameStats.beaten_count(game.id), 0, "and the wiped one is empty")

func test_wiping_an_unknown_profile_is_refused() -> void:
	assert_false(Profiles.wipe("no_such_profile"))


# --- the profile picker asks before it destroys anything --------------------
#
# Wipe and delete are both unrecoverable, so neither may act on the press of a
# button. These tests press them and assert that what they threaten is still
# there — the dialog is raised, and nothing happens until it is confirmed.

func _picker() -> ProfilePicker:
	var p := ProfilePicker.new()
	add_child_autofree(p)
	return p

# The open confirmation panel, or null. It is an ordinary Control in the picker
# (not a ConfirmationDialog — a Window draws its own background from the default
# theme and lands on a dark screen looking like a system error box).
func _confirm_of(picker: ProfilePicker) -> Control:
	return picker.get_node_or_null("Confirm")

func _press(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	assert_not_null(btn, "the confirmation offers %s" % button_name)
	btn.emit_signal("pressed")

func test_wiping_asks_first_and_does_nothing_until_told() -> void:
	var id: String = _make("Ask me")
	Profiles.switch_to(id)
	var game: GameData = Data.all_games()[0]
	GameStats.record_beaten(game.id)

	var picker := _picker()
	picker._confirm_wipe(id)
	var confirm: Control = _confirm_of(picker)
	assert_not_null(confirm, "a confirmation is raised")
	assert_true(_text_under(confirm).contains("Ask me"), "naming the profile at stake")
	assert_true(_text_under(confirm).contains("cannot be undone"),
		"and saying it cannot be undone")
	assert_eq(GameStats.beaten_count(game.id), 1, "and nothing is wiped yet")

	_press(confirm, "OkBtn")
	assert_eq(GameStats.beaten_count(game.id), 0, "confirming does the wipe")

func test_cancelling_a_wipe_leaves_everything_where_it_was() -> void:
	var id: String = _make("Changed my mind")
	Profiles.switch_to(id)
	var game: GameData = Data.all_games()[0]
	GameStats.record_beaten(game.id)

	var picker := _picker()
	picker._confirm_wipe(id)
	_press(_confirm_of(picker), "CancelBtn")
	assert_eq(GameStats.beaten_count(game.id), 1, "the run record survived")

func test_deleting_asks_first_and_does_nothing_until_told() -> void:
	var id: String = _make("Doomed but asked")
	var picker := _picker()
	picker._confirm_delete(id)
	var confirm: Control = _confirm_of(picker)
	assert_not_null(confirm, "a confirmation is raised")
	assert_true(_text_under(confirm).contains("Doomed but asked"))
	assert_true(Profiles.has_profile(id), "and the profile is still there")

	_press(confirm, "OkBtn")
	assert_false(Profiles.has_profile(id), "confirming deletes it")
	_made.erase(id)

func test_cancelling_a_delete_keeps_the_profile() -> void:
	var id: String = _make("Spared")
	var picker := _picker()
	picker._confirm_delete(id)
	_press(_confirm_of(picker), "CancelBtn")
	assert_true(Profiles.has_profile(id))

func test_only_one_confirmation_can_be_open_at_a_time() -> void:
	# Two stacked "are you sure?" panels would leave the second answering for the
	# first, on actions that cannot be undone.
	var a: String = _make("First ask")
	var b: String = _make("Second ask")
	var picker := _picker()
	picker._confirm_wipe(a)
	picker._confirm_delete(b)
	var open_panels: int = 0
	for c in picker.get_children():
		if c is Control and not c.is_queued_for_deletion() and str(c.name).begins_with("Confirm"):
			open_panels += 1
	assert_eq(open_panels, 1, "the first is dismissed when the second opens")
	# And the survivor is the one a lookup finds — a dying panel must not keep
	# the name, or the picker answers questions with a panel already on its way out.
	var live: Control = picker.get_node_or_null("Confirm")
	assert_not_null(live)
	assert_false(live.is_queued_for_deletion(), "the panel found by name is the live one")
	assert_true(_text_under(live).contains("Second ask"), "and it is the second question")

func test_wipe_and_delete_do_not_wear_the_same_icon() -> void:
	# One empties the profile, the other removes it. Both are unrecoverable and
	# they sit side by side, so they must not look like the same button.
	var other: String = _make("Row under test")
	var picker := _picker()
	var wipes: Array = []
	var dels: Array = []
	for row in picker._list.get_children():
		for c in row.get_child(0).get_children():
			if c is Button and str(c.tooltip_text).begins_with("Wipe"):
				wipes.append(c.text)
			elif c is Button and str(c.tooltip_text).begins_with("Delete"):
				dels.append(c.text)
	assert_gt(wipes.size(), 0, "there are wipe buttons")
	assert_gt(dels.size(), 0, "and delete buttons")
	assert_eq(wipes[0], "🗑", "wipe is the bin")
	assert_ne(dels[0], wipes[0], "delete is not a second bin")

# Every Label under `node`, joined — the confirmation's words, whoever laid them
# out.
func _text_under(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + " "
	for c in node.get_children():
		out += _text_under(c)
	return out
