extends Node

# Strategy floor entry point. Behaves two ways depending on how it's
# launched:
#   - Embedded (`GameState.character_id != &""`): one roguelike floor =
#     one strategy "game". Reads HP/gold/deck/spells from GameState on
#     entry; reaching the stairs signals `closed(true)` so the project
#     `Main.gd` returns to the overworld for verification + next-game
#     selection; player death signals `closed(false)` and the overworld
#     resets the run (matches the deckbuilder/action flows).
#   - Standalone (no character applied — running the scene from the
#     editor): applies Ironclad and seeds the demo loadout so the
#     prototype boots into something playable.

signal closed(was_victory: bool, target_game_id: StringName)

@onready var _renderer: StrategyDungeonRenderer = $DungeonRenderer
@onready var _hud: StrategyHUD = $HUD

const BattleViewScript := preload("res://scripts/strategy/combat/BattleView.gd")
const SpellsCatalogScript := preload("res://scripts/strategy/combat/SpellsCatalog.gd")

# Non-basic cards seeded into GameState.deck when the strategy prototype
# launches standalone (no character apply has happened). Gives Phase 6's
# Ability picker something to show until the full character flow is wired.
const _DEMO_ABILITY_CARDS: Array[StringName] = [
	&"cleave", &"twin_strike", &"iron_wave", &"thunderclap",
	&"pommel_strike", &"heavy_blade", &"anger", &"shrug_it_off", &"inflame",
]

var target_game_id: StringName = &""
var _embedded: bool = false   # set in _ready; true when launched from project Main

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _battle_overlay: CanvasLayer = null
var _game_over_overlay: CanvasLayer = null

func _ready() -> void:
	_rng.randomize()
	_embedded = GameState.character_id != &""
	if not _embedded:
		# Standalone bootstrap: apply Ironclad so GameState has HP/deck to
		# pull from. Mirrors ActionFloor's standalone path.
		var ironclad: CharacterData = Data.get_character(&"ironclad")
		if ironclad != null:
			GameState.reset_run()
			GameState.apply_character(ironclad)
	if target_game_id == &"":
		target_game_id = GameState.current_game_id
	StrategyTurnManager.connect("enemy_turns_started", _run_enemy_turns)
	StrategyCombatSession.connect("combat_started", _on_combat_started)
	StrategyCombatSession.connect("combat_ended", _on_combat_ended)
	_new_game()

func _new_game() -> void:
	if _game_over_overlay != null:
		_game_over_overlay.queue_free()
		_game_over_overlay = null
	if _battle_overlay != null:
		_battle_overlay.queue_free()
		_battle_overlay = null
	StrategyState.reset()
	_seed_demo_loadout()
	StrategyLog.add("Welcome to the dungeon. Good luck.", Color(0.8, 0.8, 1.0))
	StrategyLog.add("Arrow/HJKL move. > descend. , pick up. i inventory.", Color.GRAY)
	_load_floor()

func _seed_demo_loadout() -> void:
	# Strategy prototype runs without going through the deckbuilder
	# character-select flow, so GameState.deck / learned_spells are
	# empty. Seed both so Phase 6's Ability and Spellbook pickers have
	# something to show. Real character flows replace this entirely.
	if GameState.deck.is_empty():
		for card_id in _DEMO_ABILITY_CARDS:
			var c: CardData = Data.get_card(card_id)
			if c != null:
				GameState.deck.append(CardInstance.from_data(c))
		# Grant a weapon item so the strategy loadout's weapon slot has
		# something to equip standalone (add_item appends its weapon card).
		var pistol: ItemData = Data.get_item(&"blasma_pistol")
		if pistol != null:
			GameState.add_item(pistol)
	if GameState.learned_spells.is_empty():
		GameState.learned_spells = SpellsCatalogScript.default_starter_ids()

func _load_floor() -> void:
	var map = StrategyMap.new()
	map.generate(_rng)
	StrategyState.map = map
	StrategyState.emit_signal("level_changed", StrategyState.dungeon_floor)

	var start = map.get_start_pos()

	if StrategyState.player == null:
		# HP/MaxHP come from GameState so the strategy floor shares vitals
		# with the deckbuilder/action sections. Attack/defense are still
		# strategy-local since the tactical combat layer uses its own
		# basic-attack constants (see BattleView.DEFAULT_BASIC_ATTACK).
		var player = StrategyEntity.new()
		player.grid_pos = start
		player.glyph = "@"
		player.color = Color.WHITE
		player.name = "you"
		player.is_player = true
		player.max_hp = maxi(1, GameState.max_hp)
		player.hp = clampi(GameState.hp, 0, player.max_hp)
		player.attack = 5; player.defense = 1
		StrategyState.player = player
		StrategyState.entities.append(player)
	else:
		StrategyState.player.grid_pos = start
		StrategyState.entities.clear()
		StrategyState.entities.append(StrategyState.player)

	_spawn_items()
	StrategyFOV.compute(StrategyState.map, StrategyState.player.grid_pos, 8)
	_refresh()
	StrategyTurnManager.start_player_turn()

func _spawn_items() -> void:
	StrategyState.map.items.clear()
	for rd in StrategyState.map.room_data:
		match rd.tag:
			"start":
				continue
			"treasure":
				# Treasure rooms always get 1-2 high-value items + gold.
				for _i in range(_rng.randi_range(1, 2)):
					_spawn_special_item_in(rd.rect)
				_spawn_gold_in(rd.rect, _rng.randi_range(25, 60))
			"stairs":
				# Often has a small reward at the stairs room.
				if _rng.randi() % 2 == 0:
					_spawn_special_item_in(rd.rect)
			"combat":
				# Combat rooms may contain loot the player can grab during/after the fight.
				if _rng.randi() % 2 == 0:
					_spawn_special_item_in(rd.rect)
				if _rng.randi() % 3 == 0:
					_spawn_gold_in(rd.rect, _rng.randi_range(5, 20))

func _spawn_special_item_in(room: Rect2i) -> void:
	var pos = _random_floor_pos_in(room)
	var roll = _rng.randi() % 10
	var item: StrategyItem
	if roll < 6:
		item = StrategyItem.make_health_potion(pos)
	elif roll < 8:
		item = StrategyItem.make_strength_scroll(pos)
	else:
		item = StrategyItem.make_lightning_scroll(pos)
	StrategyState.map.items.append(item)

func _spawn_gold_in(room: Rect2i, amount: int) -> void:
	var pos = _random_floor_pos_in(room)
	StrategyState.map.items.append(StrategyItem.make_gold(pos, amount))

func _random_floor_pos_in(room: Rect2i) -> Vector2i:
	for _attempt in range(20):
		var x = _rng.randi_range(room.position.x, room.position.x + room.size.x - 1)
		var y = _rng.randi_range(room.position.y, room.position.y + room.size.y - 1)
		var pos = Vector2i(x, y)
		var t = StrategyState.map.get_tile(pos.x, pos.y)
		if t == StrategyState.TileType.FLOOR and StrategyState.get_blocking_entity_at(pos) == null:
			return pos
	return room.get_center()

func _input(event: InputEvent) -> void:
	if StrategyState.phase == StrategyState.GamePhase.DEAD:
		# Embedded death routes through the overworld's run-reset flow —
		# the player uses the Continue button on the defeat overlay. R-key
		# in-place restart only makes sense for the standalone prototype.
		if not _embedded and event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_new_game()
		return

	if StrategyState.phase == StrategyState.GamePhase.WIN:
		return

	if StrategyState.phase == StrategyState.GamePhase.COMBAT:
		return  # battle overlay owns input during combat

	if not StrategyTurnManager.is_player_turn():
		return

	var player = StrategyState.player

	# Inventory screen handling
	if _hud.is_inventory_open():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_I or event.keycode == KEY_ESCAPE:
				_hud.hide_inventory()
			elif event.unicode >= ord('a') and event.unicode <= ord('z'):
				var idx = event.unicode - ord('a')
				if idx < player.inventory.size():
					var item = player.inventory[idx]
					var msg = item.use(player)
					if item.item_type != StrategyItem.ItemType.KEY:
						player.inventory.remove_at(idx)
					StrategyLog.add(msg, Color(0.8, 0.8, 1.0))
					_hud.hide_inventory()
					_end_player_turn()
		return

	var dir = Vector2i.ZERO
	if event.is_action_pressed("move_up", true): dir = Vector2i(0, -1)
	elif event.is_action_pressed("move_down", true): dir = Vector2i(0, 1)
	elif event.is_action_pressed("move_left", true): dir = Vector2i(-1, 0)
	elif event.is_action_pressed("move_right", true): dir = Vector2i(1, 0)
	elif event.is_action_pressed("move_upleft", true): dir = Vector2i(-1, -1)
	elif event.is_action_pressed("move_upright", true): dir = Vector2i(1, -1)
	elif event.is_action_pressed("move_downleft", true): dir = Vector2i(-1, 1)
	elif event.is_action_pressed("move_downright", true): dir = Vector2i(1, 1)
	elif event.is_action_pressed("wait", true):
		StrategyLog.add("You wait.", Color.GRAY)
		_end_player_turn()
		return
	elif event.is_action_pressed("descend", true):
		_try_descend()
		return
	elif event.is_action_pressed("pickup", true):
		_try_pickup()
		return
	elif event.is_action_pressed("show_inventory", true):
		_hud.show_inventory(player)
		return

	if dir == Vector2i.ZERO:
		return

	_try_move(player, dir)

func _try_move(player: StrategyEntity, dir: Vector2i) -> void:
	var dest = player.grid_pos + dir

	if not StrategyState.map.is_walkable(dest):
		return

	player.grid_pos = dest
	_after_player_step(dest)
	_end_player_turn()

func _after_player_step(pos: Vector2i) -> void:
	# Auto-pickup (gold).
	var picked: Array = []
	for it in StrategyState.map.items:
		if it.grid_pos == pos and it.auto_pickup:
			picked.append(it)
	for it in picked:
		match it.item_type:
			StrategyItem.ItemType.GOLD:
				# Gold persists across sections — route to the shared GameState.
				GameState.change_gold(it.amount)
				StrategyLog.add("You pick up %d gold." % it.amount, Color(1.0, 0.9, 0.3))
		StrategyState.map.items.erase(it)

	# Trap reveal/trigger.
	var tile = StrategyState.map.get_tile(pos.x, pos.y)
	if tile == StrategyState.TileType.TRAP_HIDDEN:
		StrategyState.map.set_tile(pos.x, pos.y, StrategyState.TileType.TRAP_REVEALED)
		var dmg = 3 + StrategyState.dungeon_floor
		StrategyState.player.hp -= dmg
		StrategyLog.add("A trap springs! You take %d damage." % dmg, Color(1.0, 0.4, 0.4))

	# Combat trigger: entering an uncleared combat room (skip if a trap killed the player).
	if not StrategyState.player.is_alive():
		return
	var rd = StrategyState.get_room_at(pos)
	if rd != null and rd.tag == "combat" and not rd.cleared and not rd.encounter.is_empty():
		_trigger_combat(rd)

func _trigger_combat(rd: StrategyRoomData) -> void:
	var enc_str := ""
	for i in range(rd.encounter.size()):
		if i > 0: enc_str += ", "
		enc_str += str(rd.encounter[i])
	StrategyLog.add("Combat! %s" % enc_str, Color(1.0, 0.6, 0.4))
	StrategyCombatSession.enter_combat(rd, rd.encounter)

func _on_combat_started(room_data, encounter: Array, battle_map, turn_manager) -> void:
	if _battle_overlay != null:
		_battle_overlay.queue_free()
	_battle_overlay = BattleViewScript.new()
	add_child(_battle_overlay)
	_battle_overlay.set_encounter(room_data, encounter, battle_map, turn_manager)
	# Register the live context so the backpack can fire pills into this
	# battle, targeting the player unit.
	GameState.set_combat_context(_battle_overlay, _battle_overlay.get_player_unit())

func _on_combat_ended(result: String) -> void:
	# Consumable buffs last one battle.
	GameState.clear_combat_context()
	GameState.clear_temp_buffs()
	if _battle_overlay != null:
		_battle_overlay.queue_free()
		_battle_overlay = null
	if result == "defeat":
		_on_player_defeated()
		return
	StrategyLog.add("Victory!", Color(0.6, 1.0, 0.6))
	# Walking into the combat room consumed the player's step; finish that turn now.
	_end_player_turn()

func _try_descend() -> void:
	var tile = StrategyState.map.get_tile(StrategyState.player.grid_pos.x, StrategyState.player.grid_pos.y)
	if tile != StrategyState.TileType.STAIRS_DOWN:
		StrategyLog.add("There are no stairs here.", Color.GRAY)
		return
	# In the project flow one strategy game = one roguelike floor. The
	# staircase closes the floor with a victory and the overworld handles
	# verification + the next game. Standalone keeps the multi-floor demo
	# loop so the prototype scene is still playable on its own.
	if _embedded:
		_close_floor(true)
		return
	StrategyState.dungeon_floor += 1
	StrategyLog.add("You descend to floor %d." % StrategyState.dungeon_floor, Color(0.8, 1.0, 0.8))
	_load_floor()

func _try_pickup() -> void:
	var player = StrategyState.player
	var items = StrategyState.map.items
	for i in range(items.size()):
		if items[i].grid_pos == player.grid_pos:
			if items[i].auto_pickup:
				continue  # already handled by _after_player_step
			if player.inventory.size() >= StrategyEntity.MAX_INVENTORY:
				StrategyLog.add("Your pack is full!", Color.RED)
				return
			var item = items[i]
			player.inventory.append(item)
			items.remove_at(i)
			StrategyLog.add("You pick up the %s." % item.item_name, Color(0.8, 0.8, 1.0))
			_end_player_turn()
			return
	StrategyLog.add("There is nothing here to pick up.", Color.GRAY)

func _end_player_turn() -> void:
	var player = StrategyState.player
	StrategyFOV.compute(StrategyState.map, player.grid_pos, 8)
	_check_death()
	if StrategyState.phase == StrategyState.GamePhase.PLAYING:
		_refresh()
		StrategyTurnManager.end_player_turn()
	else:
		_refresh()

func _run_enemy_turns() -> void:
	# Phase 1+2: floor enemies no longer exist; encounters live in room data
	# until combat triggers. Keep the turn cycle alive for future allies.
	_check_death()
	_refresh()
	StrategyTurnManager.end_enemy_turns()

func _check_death() -> void:
	var player = StrategyState.player
	if player == null or not player.is_alive():
		_on_player_defeated()

# Phase 9: end-of-run path. Routed from both the combat-defeat signal and
# overworld death (e.g. a trap finishing the player off). Sets DEAD, logs,
# and shows the project-style defeat overlay matching DeckbuilderCombat.
func _on_player_defeated() -> void:
	if StrategyState.phase == StrategyState.GamePhase.DEAD and _game_over_overlay != null:
		return
	StrategyState.phase = StrategyState.GamePhase.DEAD
	StrategyLog.add("You have died.", Color.RED)
	_refresh()
	_show_game_over_overlay()

func _show_game_over_overlay() -> void:
	if _game_over_overlay != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 20  # above the battle overlay (which uses layer 10)
	add_child(layer)
	_game_over_overlay = layer

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(480, 260)
	panel.position = (get_viewport().get_visible_rect().size - panel.size) / 2.0
	layer.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 24)
	title.size = Vector2(440, 48)
	title.text = "DEFEAT"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var info := Label.new()
	info.position = Vector2(20, 92)
	info.size = Vector2(440, 60)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.text = "The run ends. Floor %d." % StrategyState.dungeon_floor
	panel.add_child(info)

	var btn := Button.new()
	btn.position = Vector2(120, 180)
	btn.size = Vector2(240, 56)
	# Embedded floor: close back to the overworld so the project
	# Main can run the standard defeat flow (run restart, etc).
	# Standalone: in-place restart matching the prototype loop.
	if _embedded:
		btn.text = "Continue"
		btn.pressed.connect(_close_defeat)
	else:
		btn.text = "Restart run"
		btn.pressed.connect(_new_game)
	panel.add_child(btn)

func _close_defeat() -> void:
	_close_floor(false)

# Floor exit (stairs or defeat). Syncs vitals back to GameState, frees
# any open overlays, and emits the close signal so project Main can
# advance the overworld flow.
func _close_floor(was_victory: bool) -> void:
	_sync_vitals_to_gamestate()
	if _battle_overlay != null:
		_battle_overlay.queue_free()
		_battle_overlay = null
	if _game_over_overlay != null:
		_game_over_overlay.queue_free()
		_game_over_overlay = null
	emit_signal("closed", was_victory, target_game_id)
	queue_free()

func _sync_vitals_to_gamestate() -> void:
	if StrategyState.player == null:
		return
	GameState.set_hp(StrategyState.player.hp)

func _refresh() -> void:
	var player = StrategyState.player
	if player != null:
		_renderer.center_on(player.grid_pos)
	_renderer.queue_redraw()
	_hud.update_status(player, StrategyState.dungeon_floor)
