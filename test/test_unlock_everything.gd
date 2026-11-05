extends GutTest

# THE TEST PROFILE (Settings.unlock_everything, Settings -> Profile). While it is
# on, every lock a profile has reads as open — Fracture levels, radio songs,
# title letters, the Donation Machine's shelf — and nothing is recorded, so off
# gives back exactly what the profile earned. Per profile, in prefs.cfg.

const HERO := &"ironclad"

var _fracture_log: Dictionary
var _prefs := ConfigFile.new()
var _had_prefs := false

func before_all() -> void:
	# The setter saves to the REAL profile's prefs.cfg (the suite shares user://
	# with the game): keep the file as it was and put it back after.
	_had_prefs = _prefs.load(Settings.prefs_path()) == OK

func after_all() -> void:
	if _had_prefs:
		_prefs.save(Settings.prefs_path())
	Settings.unlock_everything = false

func before_each() -> void:
	_fracture_log = GameStats.fracture_log.duplicate(true)
	GameStats.fracture_log = {}
	Settings.unlock_everything = false

func after_each() -> void:
	Settings.set_unlock_everything(false)
	GameStats.fracture_log = _fracture_log
	GameState.reset_run()
	GameLoop2.reset()
	RunConfig.reset()
	SaveSystem.cancel_pending_resume()
	SaveSystem.clear_all_saves()

func _song(id: String) -> SongData:
	var s := SongData.new()
	s.id = StringName(id)
	return s

func test_every_fracture_level_is_open_without_a_win() -> void:
	assert_eq(GameStats.fracture_unlocked(HERO), 0, "a fresh character has only Fracture 0")
	Settings.set_unlock_everything(true)
	assert_eq(GameStats.fracture_unlocked(HERO), Fracture.MAX, "a test profile has every level")
	GameStats.set_fracture_pick(HERO, Fracture.MAX)
	assert_eq(GameStats.fracture_pick(HERO), Fracture.MAX, "and can pick the top one")
	assert_eq(GameStats.fracture_best(HERO), -1, "but no win was recorded for it")
	Settings.set_unlock_everything(false)
	assert_eq(GameStats.fracture_unlocked(HERO), 0, "off gives back what was earned")
	assert_eq(GameStats.fracture_pick(HERO), 0, "and the pick is held to it again")

func test_every_song_plays_and_none_is_drawn() -> void:
	var song := _song("unlock_everything_probe")
	assert_false(Radio.is_unlocked(song), "an undrawn song is locked")
	Settings.set_unlock_everything(true)
	assert_true(Radio.is_unlocked(song), "a test profile has every song")
	assert_false(Radio.is_drawn(song), "without drawing it")
	Settings.set_unlock_everything(false)
	assert_false(Radio.is_unlocked(song), "off locks it again")

func test_every_title_letter_and_none_is_drawn() -> void:
	var key := "unlock_everything_probe"
	var before: Array = TitleUnlocks.unlocked_keys()
	assert_false(TitleUnlocks.is_unlocked(key))
	watch_signals(TitleUnlocks)
	Settings.set_unlock_everything(true)
	assert_signal_emitted(TitleUnlocks, "changed", "the title is told to redraw")
	assert_true(TitleUnlocks.is_unlocked(key), "a test profile has every letter")
	assert_eq(TitleUnlocks.unlocked_keys(), before, "nothing was drawn for it")

func test_a_run_starts_with_the_full_donation_shelf() -> void:
	var best: int = GameStats.donation_best_total
	GameStats.donation_best_total = 0
	Settings.set_unlock_everything(true)
	GameLoop2.start_run(Data.get_character2(HERO))
	assert_eq(ShopSystem.donation_slots(GameState.donation_best),
		int(ShopSystem.DONATION_TIERS[0][1]), "the machine's top tier, with nothing banked")
	assert_eq(GameStats.donation_best(), 0, "and the bank is not touched")
	GameStats.donation_best_total = best

func test_it_belongs_to_the_profile_and_survives_a_reload() -> void:
	Settings.set_unlock_everything(true)
	Settings.unlock_everything = false
	Settings.load_settings()
	assert_true(Settings.unlock_everything, "read back from this profile's prefs.cfg")
	var cfg := ConfigFile.new()
	cfg.load(Settings.prefs_path())
	assert_true(bool(cfg.get_value("profile", "unlock_everything", false)), "in the profile's own file")
