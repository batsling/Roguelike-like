class_name ScrollNames
extends Resource

# The bag a run deals its unidentified scroll labels out of — the meaningless
# words an unread scroll introduces itself by until you find out what it does
# (docs/games-first-redesign.md §4.1).
#
# WHY THIS IS A RESOURCE AND NOT A `const` IN ScrollSystem. PillSystem.COLORS and
# PotionSystem.COLORS are const arrays in their autoloads, and both are matched to
# a FOLDER OF ART: the list exists to name files on disk, and a name that drifts
# from the folder is a broken texture. These are not files. They are content out
# of the `scrolls2.0` sheet — two authored columns with a source game credited
# against each row, exactly like every other row in this project — so they are
# generated into data/ by tools/generate_scroll2_tres.py and read from there.
#
# It is loaded BY PATH (ScrollSystem.NAMES_PATH), the way AtlasView loads
# data/atlas_layout.tres, rather than through `Data`: Data._load_dir keys a
# folder's resources by their `id`, and this is one singleton row rather than a
# catalog of them.
#
# TWO WAYS TO NAME A SCROLL, and the run flips a coin per scroll (§4.1):
#
#   * a WHOLE name off `names` — "ZELGO MER", "XIXAXA XOXAXA XUXAXA". These are
#     the authored labels, each one already a complete piece of nonsense.
#   * 2-5 PARTS off `parts`, joined with spaces — "ah bloto festr", "quo iky zep
#     ooze mep". The syllables are meaningless on their own and the run assembles
#     them fresh, which is what keeps the bag effectively bottomless: 39 parts
#     make far more labels than 36 whole names ever could.
#
# The sources are carried alongside so a label can credit the game it came from,
# the way a potion's vial credits NetHack or Shattered Pixel Dungeon
# (PotionSystem.color_source). `name_sources[i]` belongs to `names[i]` and
# `part_sources[i]` to `parts[i]`; a blank means the sheet credited nobody.

# The whole-label bag (the sheet's "Random Scroll Name" column).
@export var names: PackedStringArray = PackedStringArray()
@export var name_sources: PackedStringArray = PackedStringArray()

# The syllable bag the assembled labels are built from (the sheet's "Random
# Scroll Part" column).
@export var parts: PackedStringArray = PackedStringArray()
@export var part_sources: PackedStringArray = PackedStringArray()

# The game that authored a whole name, or "" when the sheet credited nobody.
func source_for_name(label: String) -> String:
	var i: int = names.find(label)
	return name_sources[i] if i >= 0 and i < name_sources.size() else ""

# The game that authored a syllable, or "" when the sheet credited nobody.
func source_for_part(part: String) -> String:
	var i: int = parts.find(part)
	return part_sources[i] if i >= 0 and i < part_sources.size() else ""

# Is there anything to deal? An empty book is a generator that has not been run,
# and ScrollSystem falls back to the flat "Unidentified Scroll" rather than
# handing every scroll the same blank label.
func is_empty() -> bool:
	return names.is_empty() and parts.is_empty()
