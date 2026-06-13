class_name StatDefinition
extends Resource

# Static metadata for one player stat. Loaded from .tres at startup
# by the Stats autoload; runtime values live on GameState.

@export var id: StringName              # &"strength" etc.; matches a GameState field
@export var display_name: String
@export_multiline var description: String

# True for stats that contribute +1/point to their own event roll
# (STR / DEX / INT / CHA / Constitution). Speed / Luck / Dash / FoV /
# Discovery don't roll directly.
@export var grants_event_roll_bonus: bool = true

# Universal derived combat status applied at combat start. The actor
# gains floor(get_value / derived_per) stacks. Empty means none.
@export var derived_status: StringName = &""
@export var derived_per: int = 1

# Bag of mode-specific numeric knobs. Keys are stat-specific; the
# Stats autoload methods read them with safe defaults. See
# docs/stat-dispatcher.md for the per-stat key map.
@export var mode_data: Dictionary = {}
