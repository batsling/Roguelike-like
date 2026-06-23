class_name OverworldHUD
extends CanvasLayer

# Persistent HUD for the overworld. Top bar shows player vitals + run
# progress; bottom panel shows the last N GameLog messages. Subscribes
# to GameState + GameLog signals so it stays in sync without anyone
# having to call refresh() by hand.

const LOG_LINES := 5
const FONT_SIZE := 13

var _top_label: Label
var _log_label: RichTextLabel

func _ready() -> void:
	# Top bar
	var top_bg := ColorRect.new()
	top_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bg.offset_left = 0
	top_bg.offset_right = 0
	top_bg.offset_top = 0
	top_bg.offset_bottom = 30
	top_bg.color = Color(0.05, 0.06, 0.10, 0.85)
	add_child(top_bg)

	_top_label = Label.new()
	_top_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_label.offset_left = 8
	_top_label.offset_right = -8
	_top_label.offset_top = 4
	_top_label.offset_bottom = 26
	_top_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_top_label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	add_child(_top_label)

	# Bottom log
	var log_bg := ColorRect.new()
	log_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	log_bg.offset_top = -100
	log_bg.offset_bottom = 0
	log_bg.offset_left = 0
	log_bg.offset_right = 0
	log_bg.color = Color(0.05, 0.06, 0.10, 0.85)
	add_child(log_bg)

	_log_label = RichTextLabel.new()
	_log_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_log_label.offset_top = -96
	_log_label.offset_bottom = -4
	_log_label.offset_left = 8
	_log_label.offset_right = -8
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = false
	_log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	add_child(_log_label)

	# Always-visible item rack, the same CombatInventory widget the combat modes
	# use — every owned item shows as a tile, and activatable ones (Winged Boots,
	# charged actives) get a Use button gated by GameState.can_fire_item. With no
	# on_use_requested hook it fires straight through GameState.use_item. Parked on
	# the right side (like action keeps its rack off the play area), growing down
	# from the top-right so it clears the centered door row and the vitals bar.
	var inv := CombatInventory.new()
	inv.columns = 2
	inv.tile_px = 44
	inv.show_title = true
	inv.title_text = "Items"
	inv.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inv.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inv.grow_vertical = Control.GROW_DIRECTION_END
	inv.offset_right = -8
	inv.offset_top = 40
	add_child(inv)

	# Hook signals so the HUD auto-refreshes.
	GameState.hp_changed.connect(_on_state_changed)
	GameState.gold_changed.connect(_on_state_changed)
	GameState.stats_changed.connect(_on_state_changed)
	GameState.deck_changed.connect(_on_state_changed)
	GameState.inventory_changed.connect(_on_state_changed)
	GameState.current_game_changed.connect(_on_state_changed)
	GameLog.message_added.connect(_on_message)

	_refresh_top()
	_refresh_log()

func _on_state_changed(_a = null, _b = null) -> void:
	_refresh_top()

func _on_message(_text: String, _color: Color) -> void:
	_refresh_log()

func _refresh_top() -> void:
	var game_name := "?"
	if GameState.current_game_id != &"":
		var g: GameData = Data.get_game(GameState.current_game_id)
		if g != null:
			game_name = g.display_name
	var amulet_name := "?"
	if GameState.amulet_game_id != &"":
		var a: GameData = Data.get_game(GameState.amulet_game_id)
		if a != null:
			amulet_name = a.display_name
	var diff_tier: int = RunDifficulty.current_tier()
	var diff_text: String = "%s (%d/%d)" % [
		RunDifficulty.tier_name(diff_tier), RunDifficulty.current_tier_value(),
		RunDifficulty.tier_value(RunDifficulty.MAX_TIER)]
	_top_label.text = "HP %d/%d  Gold %d  Deck %d  Inv %d   |   STR %d DEX %d INT %d CHA %d CON %d LCK %d SPD %d HRV %d CRIT %d%%   |   At: %s -> %s   |   Beaten: %d  Played: %d  Difficulty: %s" % [
		GameState.hp, GameState.max_hp,
		GameState.gold,
		GameState.deck.size(),
		GameState.inventory.size(),
		Stats.get_value(&"strength"), Stats.get_value(&"dexterity"), Stats.get_value(&"intelligence"),
		Stats.get_value(&"charisma"), Stats.get_value(&"constitution"), Stats.get_value(&"luck"),
		Stats.get_value(&"speed"), Stats.get_value(&"harvesting"), Stats.crit_chance_percent(),
		game_name, amulet_name,
		GameState.total_games_beaten, GameState.games_played, diff_text,
	]

func _refresh_log() -> void:
	var recent: Array = GameLog.get_recent(LOG_LINES)
	var lines := ""
	for i in range(recent.size()):
		var m: Dictionary = recent[i]
		var col: Color = m.get("color", Color.WHITE)
		var alpha: float = 1.0 - float(recent.size() - 1 - i) * 0.16
		alpha = clampf(alpha, 0.4, 1.0)
		var hex := col.to_html(false)
		var a_hex := "%02x" % int(alpha * 255.0)
		lines += "[color=#%s%s]%s[/color]\n" % [hex, a_hex, String(m.get("text", ""))]
	_log_label.text = lines
