class_name SongLibrary
extends Resource

# Every song of Roguelike Radio in ONE file, data/songs.tres, written by
# tools/generate_song_tres.py from the `radio` sheet (docs/roguelike-radio.md).
#
# One file rather than a .tres per song, because there are 3,112 of them and each
# file costs an open, a parse and a cache entry: as separate files they were the
# largest single cost of the game's boot (~390 ms of Data's start), and as one
# they load in about half that. Edit the sheet, not this.
@export var songs: Array = []
