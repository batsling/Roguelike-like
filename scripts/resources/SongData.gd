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

# The game the song belongs to. Playing that game EARNS songs, and each one earned
# is drawn at random from this game's songs still locked (Radio.earned has the
# rule). There is no per-song rule any more: the sheet's `Unlock` and `Count`
# columns went in October 2026. A song with no game is never drawn.
@export var game_id: StringName = &""

# The file name in the radio folder, exactly as the sheet spells it. A song has
# no picture of its own: it shows its game's cover (the sheet's `Image` column
# went on 12 Oct 2026).
@export var file: String = ""
# Each tag is a station the radio can be tuned to. `menu` (Radio.MENU_TAG) also
# makes it its game's menu song: the first song that game gives.
@export var tags: PackedStringArray = PackedStringArray()
