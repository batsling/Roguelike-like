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
	return split(game_key(game), GameRanks.rank(game), Radio.game_songs(game).size(),
		TitleLetters.units_of(game).size())

# A character's share of its ranks.
static func for_character(character: StringName) -> Dictionary:
	return split(character_key(character), GameRanks.character_rank(character),
		Radio.character_songs(character).size(), TitleLetters.units().size())
