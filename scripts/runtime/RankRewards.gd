class_name RankRewards
extends RefCounted

# WHAT A RANK PAYS: A SONG OR A TITLE LETTER, 50/50 (the owner, 31 Oct 2026: "letters
# can be unlocked when ranking up a character or game similar to music, should be
# 50/50").
#
# A game at rank N, and a character at rank N, has earned N rewards (GameRanks).
# Each one is a coin flip between a ROGUELIKE RADIO song (Radio) and a TITLE LETTER
# — one letter cut from a real logo, for the main menu's title (TitleUnlocks,
# TitleLetters). A game's letters are its own logo's; a character's come from any
# logo, and its songs from its music games.
#
# THE COIN IS WORKED OUT, NOT STORED. Rank k of owner `key` flips the same way
# every time (`coin`, an RNG seeded off the key and the rank), so how many of N
# ranks were songs is a pure function of the ranks — like the rank itself — and
# needs nothing saved: Radio asks for its share and TitleUnlocks for the other, and
# the two always add up to N. Which song or which letter comes up is still the
# draw's, and THAT is saved by whoever drew it.
#
# A SIDE THAT HAS RUN OUT PAYS THE OTHER. A rank that flips "letter" for a game
# whose letters are all earned is a song instead, and the reverse — so a game with
# no logo cut (nearly all of them) earns a song every rank, exactly as before
# letters existed, and a game with letters and no songs on the radio earns letters.
# Both run out: the rank still counts as a song, which draws nothing (as a rank
# past the end of a game's soundtrack always has).

# A test seam: true pays every rank as a song, as before letters existed, for the
# radio's tests (test_radio.gd), which are about songs and use Hades, a game with
# a logo cut.
static var songs_only: bool = false

# Of `rank` ranks, how many pay a song and how many a letter, for an owner with
# `songs` songs and `letters` letters to earn in all.
static func split(key: String, rank: int, songs: int, letters: int) -> Dictionary:
	if songs_only:
		letters = 0
	var s: int = 0
	var l: int = 0
	for k in range(1, rank + 1):
		if l < letters and (coin(key, k) or s >= songs):
			l += 1
		else:
			s += 1
	return {"songs": s, "letters": l}

# Whether rank `k` of `key` flips to a LETTER. Seeded through an RNG rather than
# read off the key's hash: a string hash's low bit follows the last character's,
# so "hades#1", "hades#2"… would simply alternate.
static func coin(key: String, k: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s#%d" % [key, k]).hash()
	return rng.randf() < 0.5

static func game_key(game: StringName) -> String:
	return "game:%s" % game

static func character_key(character: StringName) -> String:
	return "character:%s" % character

# A game's share of its ranks.
static func for_game(game: StringName) -> Dictionary:
	return split(game_key(game), GameRanks.rank(game), _game_song_count(game),
		_letter_count(game))

# A character's share of its ranks.
static func for_character(character: StringName) -> Dictionary:
	var songs: int = 0
	var ch: CharacterData = Data.get_character2(character)
	if ch != null:
		for g in ch.music_games:
			songs += _game_song_count(g)
	return split(character_key(character), GameRanks.character_rank(character),
		songs, _letter_count(&"", true))

# --- one refresh's counts -----------------------------------------------------
#
# A REFRESH ASKS ABOUT EVERY GAME, and each question used to scan all 3,112 songs
# and every logo piece: Radio's and TitleUnlocks' refreshes cost ~300 ms between
# them, on every GameStats.changed — a report fires several (owner, 5 Nov 2026:
# "things are a lot slower now in general"). Inside `batch` the counts are taken
# in one pass and remembered; outside it nothing is kept, so a song or a piece
# added at any moment (the tests write Data._songs directly) is always seen.
static var _memo: Dictionary = {}
static var _batching: int = 0

static func batch(work: Callable) -> void:
	if _batching == 0:
		_memo = {}
	_batching += 1
	work.call()
	_batching -= 1
	if _batching == 0:
		_memo = {}

static func _game_song_count(game: StringName) -> int:
	if _batching == 0:
		return Radio.game_songs(game).size()
	if not _memo.has("songs"):
		var by_game: Dictionary = {}
		for s in Radio.songs():
			var g: StringName = (s as SongData).game_id
			by_game[g] = int(by_game.get(g, 0)) + 1
		_memo["songs"] = by_game
	return int((_memo["songs"] as Dictionary).get(game, 0)) if game != &"" else 0

# A game's logo pieces, or (`all`) every piece.
static func _letter_count(game: StringName, all: bool = false) -> int:
	if _batching == 0:
		return TitleLetters.units().size() if all else TitleLetters.units_of(game).size()
	if not _memo.has("letters"):
		var by_game: Dictionary = {}
		var total: int = 0
		var p := TitleLetters.pool()
		for folder in p:
			for e in p[folder]:
				if not TitleLetters.is_starter(e) and TitleLetters.unit_key(e) == String(e["key"]):
					total += 1
					var g := String(e.get("game", ""))
					by_game[g] = int(by_game.get(g, 0)) + 1
		_memo["letters"] = by_game
		_memo["letters_all"] = total
	return int(_memo["letters_all"]) if all else int((_memo["letters"] as Dictionary).get(String(game), 0))
