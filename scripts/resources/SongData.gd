class_name SongData
extends Resource

# ONE SONG ON ROGUELIKE RADIO (docs/roguelike-radio.md).
#
# Source of truth is the `radio` sheet of tools/Roguelikes.xlsx, generated into
# data/songs/*.tres by tools/generate_song_tres.py. Edit the sheet, not these.
#
# THE AUDIO IS NOT PART OF THE RESOURCE. It is the player's own music, sitting
# in their radio folder (Radio.FOLDER) on their own machine, and `file` is only
# the name to look for there. A song whose file is missing is still listed — as
# "file not found" — so a typo in the sheet reads as a typo rather than as a
# song that never existed.

@export var id: StringName
@export var title: String = ""
@export var artist: String = ""
@export var album: String = ""
# 0 when the sheet left it blank.
@export var year: int = 0

# The game the song belongs to, and the one whose record unlocks it.
@export var game_id: StringName = &""

# How it unlocks:
#   &"enemies" — `count` DISTINCT goal-enemies defeated at `game_id`, each
#              counted once however often it was re-cleared
#              (GameStats.distinct_enemies_count) — "Defeat 5 distinct enemies
#              in Balatro",
#   &"wins"  — `game_id` reported beaten `count` times (GameStats.beaten_count),
#   &""      — no rule yet, which keeps it LOCKED. That is the owner's call, not
#              a default to "free": a row being authored should not start
#              playing on stream before its rule is decided.
@export var unlock: StringName = &""
@export var count: int = 0

# The file name in the radio folder, exactly as the sheet spells it.
@export var file: String = ""
# Album art, as a res:// path; "" means "use the game's cover".
@export var image_path: String = ""
# Each tag is a station the radio can be tuned to.
@export var tags: PackedStringArray = PackedStringArray()
