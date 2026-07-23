class_name DeckbuilderCombat
extends Control

# Phase 1a deckbuilder combat. Owns per-combat state, runs turn lifecycle,
# resolves card play through the EffectSystem, applies damage/block with
# the full status math (Vulnerable, Weak, Frail, Power, Defense, etc.)
# matching the JS combat-engine rules.
#
# Entry point: pass an Array of EnemyData (or ids) via `enemies_to_spawn`
# before adding to tree, or use `start_combat(enemies)` after _ready.
#
# Enemy AI execution lives in the next commit (commit 7); for now the
# enemy plans a move on turn start but does not execute it.

signal combat_ended(victory: bool)
signal closed(was_victory: bool, target_game_id: StringName)

# Hard cap on how many enemies can share the battlefield. Spawns past this (event
# summons, slime Splits) are dropped so the row never overflows. Shared so other
# systems (the dev test-combat picker) agree on the same ceiling.
const MAX_ENEMIES := 5

# Configuration set by the caller before _ready (or via start_combat).
var enemies_to_spawn: Array = []
var target_game_id: StringName = &""
# Elite combats bump enemy HP, give the enemy a starting Power, and pay
# out a larger gold reward. Set by GameMap before add_child.
var is_elite: bool = false

# Dev test combat (DevTools): exempt from run-scope tallies like the
# combats-completed counter, so testing never skews the real run's spawn budget.
var dev_combat: bool = false

# Tuning constants for the elite multiplier — easy to dial in one place.
const ELITE_HP_MULT := 1.5
const ELITE_POWER_BONUS := 3
const ELITE_GOLD_MULT := 1.5

# ------------------------------------------------------------------
# Combat state — referenced by EffectSystem handlers via ctx.scene
# ------------------------------------------------------------------
var player: CombatActor = null
var enemies: Array[CombatActor] = []

# Pre-combat event carryover. "ambush" (the player got the drop) draws two
# extra cards on turn 1; "ambushed" (the enemy did) draws two fewer. Set from
# GameState.pending_ambush at combat start and spent on the opening hand.
var _ambush_draw_delta: int = 0

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []
var exhaust_pile: Array[CardInstance] = []

# Persistent in-combat modifiers registered by `boost_cards` effects.
# Each entry: {match_tag, match_type, match_id, stat, value}. Consulted
# in `_resolve_card` so the bonus folds into the effect's value before
# dispatch. Cleared at the start of each combat.
var card_boosts: Array = []

# Persistent in-combat listeners registered by `trigger` effects
# (After Image, Demon Form, etc). Each entry: {on, effect}. The combat
# emit sites call `_fire_power_triggers(name, ctx_extras)` which walks
# this list and routes matching ones through EffectSystem. Cleared at
# combat start.
var power_triggers: Array = []

# Consecutive-hit streaks (Dead Eye) now live on GameState so every combat
# mode shares them; see GameState.streak_* . deal_damage folds the bonus in via
# GameState.streak_attack_bonus and the attack_landed/attack_missed triggers
# grow/reset it through EffectSystem.

var energy: int = 0
var max_energy: int = 3
# Ice Cream: energy left unspent at end of turn, re-added at the start of the
# next turn (can push energy above max_energy). Cleared at combat start.
var _energy_carryover: int = 0
# Energy spent by the X-cost card currently resolving (Whirlwind / Skewer).
# Set per play in _resolve_card and threaded into effect ctx as x_value so
# `hits_from: "energy"` dmg effects repeat once per point. Replay re-uses the
# same X (the card was paid for once).
var _last_x_value: int = 0
# Cards the last `discard:all` (Storm of Steel) sent away this play. Read back
# by conjure `count_from: "discarded"` via the effect ctx scene.
var last_discard_count: int = 0
# Cards the last `exhaust:all` (Fiend Fire) sent away this play. Read back by
# dmg `hits_from: "exhausted"` via the effect ctx scene.
var last_exhaust_count: int = 0
# Nightmare's banked picks: [{data: CardData, upgraded: bool, count: int}].
# Filled by the picker on play, delivered to hand at the next turn start.
var _nightmare_pending: Array = []
var turn: int = 0
enum Phase { INIT, PLAYER, ENEMY, WON, LOST }
var phase: Phase = Phase.INIT

# Persistent enemy view widgets (created in start_combat, refreshed by
# _refresh_ui without rebuilding the row).
var _enemy_views: Array[EnemyView] = []
var _hand_views: Array[CardView] = []

# Targeting mode (card selected, waiting for enemy click)
var _selected_card: CardInstance = null
var _selected_item: ItemData = null
var _targeting: bool = false
# Following arrow shown while choosing an enemy target for a card.
var _targeting_arrow: TargetingArrow = null

# Loot (potions): the right-side Loot button opens a scrollable dropdown of the
# player's potions; using one starts the same targeting arrow as a card and the
# player clicks any target (an enemy or their own portrait). -1 = no potion
# currently being aimed.
var _selected_potion_index: int = -1
var _loot_button: Button = null
var _loot_dropdown: Control = null
var _loot_dropdown_list: VBoxContainer = null
var _loot_open: bool = false

# Drag-to-play state. _drag_card is the CardInstance being dragged; _drag_ghost
# is a floating CardView clone that follows the cursor (mirrors the HTML build's
# drag clone). Both null when no drag is in progress.
var _drag_card: CardInstance = null
var _drag_ghost: CardView = null
var _drag_hover_enemy: EnemyView = null
# Dynamic hover card: a small panel shown next to the enemy under the cursor
# while dragging a targeting card, previewing what the card would do to THAT
# enemy — including conditional rider effects (e.g. a Fire card only reads
# "Inflict 1 Burn" when the hovered enemy doesn't already have Burn).
var _hover_card: Control = null

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Status decay list and the Persistence-debuff set both live on Stats now
# (Stats.PERSISTENCE_DEBUFFS / Stats.status_apply_stacks), shared across all
# three combat modes.

# UI refs
@onready var _enemy_area: HBoxContainer = $Layout/Battlefield/EnemyArea
@onready var _player_portrait: TextureRect = $Layout/Battlefield/PlayerArea/PlayerPortrait
@onready var _player_name: Label = $Layout/Battlefield/PlayerArea/PlayerName

# Player HP bar + status badges shown under the portrait (mirrors the enemy
# panels). Built procedurally in _build_player_view, refreshed in _refresh_ui.
var _player_hp_bar: ProgressBar = null
var _player_hp_overlay: Label = null
var _player_status_row: HBoxContainer = null
var _player_poison_overlay: ColorRect = null
var _player_block_label: Label = null
var _player_block_badge: TextureRect = null

# Shared green poison tint used on every HP bar (player + enemies).
const POISON_BAR_COLOR := Color(0.35, 0.8, 0.3, 0.85)
# Shield art for the Block badge — the same Defense icon the enemy intent bar
# uses, so Block reads consistently across the player and enemy panels.
const BLOCK_SHIELD_PATH := "res://images/moves/Defense.png"
@onready var _hand_area: HBoxContainer = $Layout/Bottom/HandRow/HandArea
@onready var _end_turn_btn: Button = $Layout/Bottom/HandRow/EndTurnButton
@onready var _energy_label: Label = $Layout/Bottom/StatusBar/EnergyLabel
@onready var _hp_label: Label = $Layout/Bottom/StatusBar/HPLabel
@onready var _draw_btn: Button = $Layout/Bottom/StatusBar/DrawButton
@onready var _discard_btn: Button = $Layout/Bottom/StatusBar/DiscardButton
@onready var _exhaust_btn: Button = $Layout/Bottom/StatusBar/ExhaustButton
@onready var _block_label: Label = $Layout/Bottom/StatusBar/BlockLabel
@onready var _turn_label: Label = $Layout/Top/TurnLabel

func _ready() -> void:
	_rng.randomize()
	# Targeting arrow overlay (added last so it draws on top; ignores mouse so
	# enemy clicks still land).
	_targeting_arrow = TargetingArrow.new()
	add_child(_targeting_arrow)
	_end_turn_btn.pressed.connect(_on_end_turn)
	# GameState.hp is the run-HP truth and `player` mirrors it. An item acquired
	# mid-combat (e.g. Mango's +Max HP / +HP via item_acquired) writes straight to
	# GameState, so mirror it onto the live actor + HP bar at once instead of
	# waiting for the next combat to rebuild `player`. Auto-disconnects when freed.
	if not GameState.hp_changed.is_connected(_on_gamestate_hp_changed):
		GameState.hp_changed.connect(_on_gamestate_hp_changed)
	_draw_btn.pressed.connect(_on_pile_clicked.bind("draw"))
	_discard_btn.pressed.connect(_on_pile_clicked.bind("discard"))
	_exhaust_btn.pressed.connect(_on_pile_clicked.bind("exhaust"))
	_build_inventory_panel()
	_build_loot_panel()
	# Keep the Loot button's count + dropdown in sync as potions are gained/used
	# (loot mutations emit inventory_changed).
	if not GameState.inventory_changed.is_connected(_refresh_loot_button):
		GameState.inventory_changed.connect(_refresh_loot_button)
	# Pre-combat event used to fire here; events now live as dedicated
	# map nodes in the deckbuilder mini-map (Phase 2). Combat starts
	# immediately as long as the caller pre-populated enemies_to_spawn.
	if not enemies_to_spawn.is_empty():
		start_combat(enemies_to_spawn)

# On-screen item rack, pinned to the top of the screen above the battlefield
# (its own CanvasLayer so it draws over the combat UI, like the HTML inventory).
func _build_inventory_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.offset_top = 4
	layer.add_child(bar)
	var inv := CombatInventory.new()
	inv.columns = 12
	inv.tile_px = 40
	inv.show_title = false
	inv.on_use_requested = _on_item_use_requested
	bar.add_child(inv)

# Right-side Loot button + scrollable potion dropdown. Potions can only be used
# in combat, so the panel lives on the combat scene (its own CanvasLayer so it
# draws over the battlefield). Using a potion spawns the targeting arrow exactly
# like a card and the player clicks any target.
func _build_loot_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	holder.offset_left = -210
	holder.offset_right = -8
	holder.offset_top = 52
	holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	holder.add_theme_constant_override("separation", 4)
	layer.add_child(holder)

	_loot_button = Button.new()
	_loot_button.text = "Loot"
	_loot_button.custom_minimum_size = Vector2(202, 34)
	_loot_button.pressed.connect(_toggle_loot_dropdown)
	holder.add_child(_loot_button)

	_loot_dropdown = PanelContainer.new()
	_loot_dropdown.visible = false
	_loot_dropdown.custom_minimum_size = Vector2(202, 0)
	holder.add_child(_loot_dropdown)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(202, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_loot_dropdown.add_child(scroll)

	_loot_dropdown_list = VBoxContainer.new()
	_loot_dropdown_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_dropdown_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_loot_dropdown_list)

	_refresh_loot_button()

func _toggle_loot_dropdown() -> void:
	_loot_open = not _loot_open
	if _loot_open:
		_build_loot_rows()
	if _loot_dropdown != null:
		_loot_dropdown.visible = _loot_open

func _refresh_loot_button() -> void:
	if _loot_button == null:
		return
	var n: int = GameState.get_loot_count("potion")
	_loot_button.text = "Loot (%d)" % n
	if _loot_open:
		_build_loot_rows()

# (loot_items index, entry) pairs for every carried potion, in carry order.
func _potion_loot_entries() -> Array:
	var out: Array = []
	for i in range(GameState.loot_items.size()):
		var e = GameState.loot_items[i]
		if e is Dictionary and String(e.get("type", "")) == "potion":
			out.append({"index": i, "entry": e})
	return out

func _build_loot_rows() -> void:
	if _loot_dropdown_list == null:
		return
	for c in _loot_dropdown_list.get_children():
		c.queue_free()
	var entries: Array = _potion_loot_entries()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No potions."
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_loot_dropdown_list.add_child(empty)
		return
	for item in entries:
		_loot_dropdown_list.add_child(_make_loot_row(int(item["index"]), item["entry"]))

func _make_loot_row(loot_index: int, entry: Dictionary) -> Control:
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.tooltip_text = (potion.effect_text if potion != null and PotionSystem.is_identified(potion.id) else "Unidentified — use to learn what it does.")
	row.pressed.connect(_begin_potion_targeting.bind(loot_index))
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 6)
	row.add_child(hb)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(32, 32)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if potion != null:
		art.texture = PotionSystem.art_texture(potion)
	hb.add_child(art)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = PotionSystem.display_name(potion) if potion != null else "Potion"
	hb.add_child(label)
	return row

func _begin_potion_targeting(loot_index: int) -> void:
	if phase != Phase.PLAYER:
		GameLog.add("Potions can only be used on your turn.", Color(0.9, 0.7, 0.3))
		return
	if loot_index < 0 or loot_index >= GameState.loot_items.size():
		return
	var entry = GameState.loot_items[loot_index]
	if not (entry is Dictionary) or String(entry.get("type", "")) != "potion":
		return
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if potion == null:
		return
	# Close the dropdown and start aiming from the Loot button.
	_loot_open = false
	if _loot_dropdown != null:
		_loot_dropdown.visible = false
	_cancel_targeting()
	_selected_potion_index = loot_index
	_targeting = true
	if _targeting_arrow != null and _loot_button != null:
		var r: Rect2 = _loot_button.get_global_rect()
		_targeting_arrow.start(Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y))
	GameLog.add("Choose a target for %s (or click yourself)." % PotionSystem.display_name(potion),
		Color(0.7, 0.9, 1.0))
	_refresh_ui()

# Applies the aimed potion to `target` (an enemy or the player), identifies it,
# and consumes it. Shared by the enemy-click and player-portrait-click paths.
func _resolve_potion(loot_index: int, target: CombatActor) -> void:
	if loot_index < 0 or loot_index >= GameState.loot_items.size() or target == null:
		_cancel_targeting()
		return
	var entry = GameState.loot_items[loot_index]
	if not (entry is Dictionary) or String(entry.get("type", "")) != "potion":
		_cancel_targeting()
		return
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	_cancel_targeting()
	if potion == null:
		return
	var ctx := {"source": player, "scene": self, "mode": Stats.Mode.DECKBUILDER, "rng": _rng}
	# Cleave potions (Explosive Ampoule) hit EVERY living enemy — the deckbuilder
	# has no spatial throw, so cleave resolves as an all-enemy splash regardless of
	# which target the arrow picked, matching the legacy build.
	var logs: Array
	if potion.cleave:
		var living: Array = enemies.filter(func(e): return e != null and e.is_alive())
		logs = PotionSystem.apply_to_targets(potion, living, ctx)
	else:
		logs = PotionSystem.apply_to_target(potion, target, ctx)
	for line in logs:
		GameLog.add(line, PotionSystem.POTION_COLOR)
	PotionSystem.identify(potion.id)
	var detail: String = "on all enemies" if potion.cleave else "on %s" % (
		"you" if target == player else target.display_name)
	PotionSystem.notify_used(potion, detail)
	GameState.remove_loot_at(loot_index)
	potion_after_apply()

# --- Potion adapter hooks (called by PotionSystem) -------------------------

func potion_grant_energy(amount: int) -> bool:
	energy += amount
	_refresh_ui()
	return true

# Player HP/Max-HP changes route through GameState (the run-shared pool); the
# player CombatActor mirrors it, exactly like every other deckbuilder damage site.
func potion_player_hp_delta(delta: int) -> void:
	GameState.change_hp(delta)
	if player != null:
		player.hp = GameState.hp

func potion_player_maxhp_delta(delta: int) -> void:
	GameState.change_max_hp(delta)
	GameState.change_hp(delta)
	if player != null:
		player.max_hp = GameState.max_hp
		player.hp = GameState.hp

func potion_after_apply() -> void:
	_refresh_loot_button()
	_refresh_ui()
	_check_combat_end()

func start_combat(spawn_list: Array) -> void:
	# Fold any event-queued extra enemies (e.g. a fruit-fly swarm) into the
	# encounter before actors are built.
	_init_actors(_append_pending_spawns(spawn_list))
	_init_deck()
	_apply_derived_statuses()
	# Register the live context so the backpack can fire consumables into
	# this fight; the player CombatActor is the use target.
	GameState.set_combat_context(self, player)
	_build_player_portrait()
	_build_enemy_views()
	turn = 0
	max_energy = GameState.max_energy
	GameState.phase = GameState.Phase.COMBAT
	TriggerBus.emit_signal("combat_started", {"scene": self})
	_fire_item_triggers("combat_started")
	_fire_power_triggers("combat_started")
	_apply_event_ambush()
	_apply_pending_scroll_effects()
	_start_player_turn()

# Drains the scroll-scheduled carryover (Scroll of Scare Monster / Aggravate
# Monsters / Fire) into this fight via ScrollSystem, with deckbuilder closures
# that stun / buff / burn the live enemy CombatActors. Runs before the first
# player turn so stunned intents and the enemy buffs are in place from turn 1.
func _apply_pending_scroll_effects() -> void:
	var stun_fn := func(mode: String, count: int) -> void:
		var living: Array = enemies.filter(func(e): return e.is_alive())
		if mode == "all":
			for e in living:
				e.add_status(&"stun", 1)
		elif mode == "choose":
			# Player picks up to N enemies to Stun (auto-stuns all if N >= living).
			StunPickerModal.new().start(self, living, count)
		else: # random
			living.shuffle()
			for e in living.slice(0, count):
				e.add_status(&"stun", 1)
	var buff_fn := func(power: int, defense: int) -> void:
		for e in enemies:
			if not e.is_alive():
				continue
			if power != 0:
				e.add_status(&"power", power)
			if defense != 0:
				e.add_status(&"defense", defense)
	var fire_fn := func(amount: int) -> void:
		for e in enemies:
			if not e.is_alive():
				continue
			var dmg: int = amount
			if e.block > 0:
				var blocked: int = mini(e.block, dmg)
				e.block -= blocked
				dmg -= blocked
			e.hp = maxi(0, e.hp - dmg)
			GameLog.add("Scroll of Fire burns %s for %d." % [e.display_name, amount], Color(1.0, 0.5, 0.2))
	ScrollSystem.apply_pending_combat_effects(stun_fn, buff_fn, fire_fn)
	_build_enemy_views()
	_refresh_ui()

# Consumes GameState.pending_ambush into a turn-1 draw modifier: "ambush" adds
# two cards to the opening hand, "ambushed" removes two.
func _apply_event_ambush() -> void:
	match GameState.pending_ambush:
		"ambush":
			_ambush_draw_delta = 2
			GameLog.add("Ambush! You catch them off guard — draw 2 extra cards.", Color(0.7, 1.0, 0.7))
		"ambushed":
			_ambush_draw_delta = -2
			GameLog.add("Ambushed! Caught off guard — you draw 2 fewer cards.", Color(1.0, 0.6, 0.6))
	GameState.pending_ambush = ""

# Pulls queued event spawns (Array of {enemy, count}) into the spawn list and
# clears the queue so they fire exactly once, for the next combat only.
func _append_pending_spawns(spawn_list: Array) -> Array:
	if GameState.pending_spawn_enemies.is_empty():
		return spawn_list
	var combined: Array = spawn_list.duplicate()
	for entry in GameState.pending_spawn_enemies:
		var id: StringName = StringName(String(entry.get("enemy", "")))
		var count: int = int(entry.get("count", 0))
		for _i in range(count):
			combined.append(id)
	GameState.pending_spawn_enemies.clear()
	return combined

# Shows the player character's full art on the left of the battlefield, facing
# the enemy row. Pulls the portrait off the chosen CharacterData.
func _build_player_portrait() -> void:
	if _player_portrait == null:
		return
	var cd: CharacterData = Data.get_character(GameState.character_id)
	if cd != null:
		_player_portrait.texture = cd.portrait if cd.portrait != null else cd.icon
		_player_name.text = cd.display_name
	else:
		_player_name.text = "You"
	_build_player_view()

# Adds an HP bar (with an "x / y" overlay) and a status-badge row under the
# player portrait so the player can see their own HP / Weak / Frail / Blind /
# Block at a glance, the same way enemy panels do.
func _build_player_view() -> void:
	if _player_status_row != null:
		return
	var area: Node = _player_portrait.get_parent()
	if area == null:
		return
	# Make the portrait clickable so a potion can be aimed at the player ("drink
	# it yourself"). Only acts while a potion is being aimed; otherwise the click
	# is a harmless no-op.
	_player_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	if not _player_portrait.gui_input.is_connected(_on_player_portrait_input):
		_player_portrait.gui_input.connect(_on_player_portrait_input)

	var hp_holder := Control.new()
	hp_holder.custom_minimum_size = Vector2(0, 20)
	hp_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(hp_holder)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_hp_bar.show_percentage = false
	_player_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	# Player health bar is red, matching the enemy bars / the old HTML build.
	fill.bg_color = Color(0.78, 0.18, 0.18)
	_player_hp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.05, 0.05)
	_player_hp_bar.add_theme_stylebox_override("background", bg)
	hp_holder.add_child(_player_hp_bar)

	# Poison overlay: a green segment tinting the rightmost portion of the HP
	# fill equal to the pending poison damage (StS-style "this much HP will
	# rot"). Anchored by fraction so it tracks the bar at any width; positioned
	# in _refresh_player_view.
	_player_poison_overlay = ColorRect.new()
	_player_poison_overlay.color = POISON_BAR_COLOR
	_player_poison_overlay.visible = false
	_player_poison_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_hp_bar.add_child(_player_poison_overlay)

	_player_hp_overlay = Label.new()
	_player_hp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_hp_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_hp_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_hp_overlay.add_theme_font_size_override("font_size", 11)
	_player_hp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_holder.add_child(_player_hp_overlay)

	# Player block reads as a shield badge with the count inside it, parked at the
	# left end of the HP bar — the same Defense art + layout the enemy panels use,
	# so Block is consistent and sits right by the health bar (Slay the Spire-style).
	_player_block_badge = TextureRect.new()
	if ResourceLoader.exists(BLOCK_SHIELD_PATH):
		_player_block_badge.texture = load(BLOCK_SHIELD_PATH)
	_player_block_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_block_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_block_badge.custom_minimum_size = Vector2(24, 24)
	_player_block_badge.size = Vector2(24, 24)
	_player_block_badge.position = Vector2(-2, -4)
	_player_block_badge.modulate = Color(0.7, 0.85, 1.0)  # cool tint -> reads as Block
	_player_block_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_block_badge.visible = false
	hp_holder.add_child(_player_block_badge)

	_player_block_label = Label.new()
	_player_block_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_block_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_block_label.add_theme_font_size_override("font_size", 12)
	_player_block_label.add_theme_color_override("font_color", Color.WHITE)
	_player_block_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_player_block_label.add_theme_constant_override("outline_size", 4)
	_player_block_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_block_badge.add_child(_player_block_label)

	_player_status_row = HBoxContainer.new()
	_player_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_player_status_row.custom_minimum_size = Vector2(0, 32)
	_player_status_row.add_theme_constant_override("separation", 4)
	_player_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(_player_status_row)

# Tints the rightmost `poison` worth of an HP bar green to preview pending rot.
# overlay is a ColorRect child of the ProgressBar; anchors are set by HP/poison
# fraction so it works at any bar width. Hidden when the actor isn't poisoned.
func _update_poison_overlay(overlay: ColorRect, hp: int, max_hp: int, poison: int) -> void:
	if overlay == null:
		return
	if poison <= 0 or hp <= 0 or max_hp <= 0:
		overlay.visible = false
		return
	var shown: int = mini(poison, hp)
	overlay.anchor_left = float(hp - shown) / float(max_hp)
	overlay.anchor_right = float(hp) / float(max_hp)
	overlay.anchor_top = 0.0
	overlay.anchor_bottom = 1.0
	overlay.offset_left = 0.0
	overlay.offset_right = 0.0
	overlay.offset_top = 0.0
	overlay.offset_bottom = 0.0
	overlay.visible = true

# Mirror a GameState HP/Max-HP change (mid-combat item/event) onto the live actor
# so the HP bar updates immediately. The damage sites already keep them in step,
# so this is a no-op for them; the win is the item-acquired path that bypasses
# those sites.
func _on_gamestate_hp_changed(new_hp: int, new_max: int) -> void:
	if player == null:
		return
	player.hp = new_hp
	player.max_hp = new_max
	_refresh_player_view()

func _refresh_player_view() -> void:
	if player == null or _player_hp_bar == null:
		return
	_player_hp_bar.max_value = maxi(1, player.max_hp)
	_player_hp_bar.value = player.hp
	_player_hp_overlay.text = "%d / %d" % [player.hp, player.max_hp]
	if _player_block_badge != null:
		_player_block_badge.visible = player.block > 0
		_player_block_label.text = str(player.block)
	_update_poison_overlay(_player_poison_overlay, player.hp, player.max_hp,
		player.get_status(&"poison"))
	for c in _player_status_row.get_children():
		c.queue_free()
	for s in player.statuses.keys():
		var stacks: int = int(player.statuses[s])
		# Negative stacks (a status drained below 0) still show, in red.
		if stacks == 0:
			continue
		_player_status_row.add_child(_make_status_badge(s, stacks, player))
	# Played Powers badge on the same strip, after the statuses.
	for pid in player.powers.keys():
		_player_status_row.add_child(_make_power_badge(player.powers[pid]))

# Small status icon + stack-count badge, mirroring EnemyView's. Falls back to a
# coloured letter when a status has no icon art.
func _make_status_badge(status_name, stacks: int, actor = null) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(30, 30)
	# PASS (not IGNORE) so the badge receives hover and shows its tooltip — works
	# even though the row is IGNORE, since mouse filtering is per-control.
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.tooltip_text = Stats.status_tooltip(status_name, stacks)
	var tex: Texture2D = Stats.status_icon(status_name)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
	else:
		var letter := Label.new()
		letter.text = String(status_name).substr(0, 1).to_upper()
		letter.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", 15)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(letter)
	var count := Label.new()
	count.text = str(stacks)
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 13)
	# Negative stacks (drained below zero) read in red.
	count.add_theme_color_override("font_color",
		Color(1.0, 0.35, 0.3) if stacks < 0 else Color.WHITE)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 3)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(count)
	# Top-right addon marker: a lock for Permanent, a clock + turns for Temporary.
	_add_status_marker(holder, actor, status_name)
	return holder

# Power badge: the same 30×30 chip as a status badge, sourced from the played
# Power card itself — icon from images/powericons/<Img>Power.png, hover text
# from the card's (mechanical) description, count = copies played this combat.
func _make_power_badge(entry: Dictionary) -> Control:
	var card: CardData = entry.get("card")
	var count_val: int = int(entry.get("count", 1))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(30, 30)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.tooltip_text = Stats.power_tooltip(card, count_val)
	var icon := TextureRect.new()
	icon.texture = Stats.power_badge_icon(card)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	if count_val > 1:
		var count := Label.new()
		count.text = str(count_val)
		count.set_anchors_preset(Control.PRESET_FULL_RECT)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count.add_theme_font_size_override("font_size", 13)
		count.add_theme_color_override("font_color", Color.WHITE)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.add_theme_constant_override("outline_size", 3)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(count)
	return holder

# Adds the Permanent/Temporary marker overlay to a 30×30 status badge `holder`
# for `status_name` on `actor`. No-op for actors without the addon API.
func _add_status_marker(holder: Control, actor, status_name) -> void:
	if actor == null:
		return
	var sn := StringName(status_name)
	var marker: StatusMarker = null
	if actor.has_method("is_status_permanent") and actor.is_status_permanent(sn):
		marker = StatusMarker.new()
		marker.setup("lock")
	elif actor.has_method("is_status_temporary") and actor.is_status_temporary(sn):
		marker = StatusMarker.new()
		marker.setup("clock", actor.temporary_turns(sn))
	if marker != null:
		marker.position = Vector2(holder.custom_minimum_size.x - 13, -2)
		holder.add_child(marker)

func _build_enemy_views() -> void:
	for child in _enemy_area.get_children():
		child.queue_free()
	_enemy_views.clear()
	for i in range(enemies.size()):
		var view := EnemyView.new()
		var idx: int = i
		view.clicked.connect(func(): _on_enemy_clicked(idx))
		# add_child first so _ready builds the panel before setup() runs.
		_enemy_area.add_child(view)
		view.setup(enemies[i])
		_enemy_views.append(view)

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

func _init_actors(spawn_list: Array) -> void:
	player = CombatActor.from_player()
	enemies.clear()
	for entry in spawn_list:
		if enemies.size() >= MAX_ENEMIES:
			break
		var d: EnemyData = null
		if entry is EnemyData:
			d = entry
		elif entry is StringName or entry is String:
			d = Data.get_enemy(StringName(entry))
		if d != null:
			var actor: CombatActor = CombatActor.from_enemy(d, _rng)
			if is_elite:
				# Bump HP and grant a starting Power. Elite-specific
				# enemy data with bespoke patterns lands later.
				var bumped: int = int(actor.max_hp * ELITE_HP_MULT)
				actor.max_hp = bumped
				actor.hp = bumped
				actor.add_status(&"power", ELITE_POWER_BONUS)
			enemies.append(actor)

func _init_deck() -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	card_boosts.clear()
	power_triggers.clear()
	GameState.streak_clear()
	_energy_carryover = 0
	last_discard_count = 0
	last_exhaust_count = 0
	_nightmare_pending.clear()
	for c in GameState.deck:
		if c is CardData:
			draw_pile.append(CardInstance.from_data(c))
		elif c is CardInstance:
			# Clear any leftover per-combat cost discount (Empty Tome) so a new
			# fight starts from the card's real cost — and any unspent Setup
			# "free until played" override from a previous combat.
			c.combat_cost_delta = 0
			c.free_until_played = false
			draw_pile.append(c)
	_shuffle(draw_pile)
	_promote_innate()

# Innate: cards flagged innate start in the opening hand. draw_cards pulls
# from the BACK of draw_pile (pop_back), so moving the innate cards to the
# end after shuffling guarantees they're the first cards drawn on turn 1.
# Order among innate cards themselves is preserved. If more cards are innate
# than the opening hand size, the overflow stays on top and is simply drawn
# first on later turns — matching the "place on top of deck" wording.
func _promote_innate() -> void:
	var innate: Array[CardInstance] = []
	var rest: Array[CardInstance] = []
	for ci in draw_pile:
		if ci != null and ci.data != null and ci.data.innate:
			innate.append(ci)
		else:
			rest.append(ci)
	if innate.is_empty():
		return
	rest.append_array(innate)
	draw_pile = rest

func _apply_derived_statuses() -> void:
	# Stats autoload owns the universal derived statuses + drains
	# pending event statuses. Per-stat balance changes happen in the
	# StatDefinition .tres files, not here.
	Stats.apply_derived_statuses(player, Stats.Mode.DECKBUILDER)

# ------------------------------------------------------------------
# Turn lifecycle
# ------------------------------------------------------------------

func _start_player_turn() -> void:
	turn += 1
	phase = Phase.PLAYER
	# Turn-scoped skills expire NOW — after the enemy turn, so Flame Barrier's
	# registered retaliation covered every enemy hit — not at the player's own
	# end of turn. Drops `until: "turn_end"` triggers (Rage / Flame Barrier)
	# and wipes the matching Skill-type marker icons (rage / flame_barrier /
	# double_tap) off the status strip.
	power_triggers = Stats.expire_turn_triggers(power_triggers)
	Stats.clear_skill_markers(player)
	energy = max_energy
	# Ice Cream: pour last turn's leftover energy on top (may exceed max).
	if _energy_carryover > 0:
		energy += _energy_carryover
		GameLog.add("Ice Cream: +%d bonus energy!" % _energy_carryover, Color(0.7, 1.0, 0.7))
		_energy_carryover = 0
	# Next Turn Energy (Flying Knee / Doppelganger): banked stacks pour onto the
	# refreshed pool now, then the status clears ("Lose all when triggered").
	var nt_energy: int = Stats.consume_status(player, &"next_turn_energy")
	if nt_energy > 0:
		energy += nt_energy
		GameLog.add("Next Turn Energy: +%d energy." % nt_energy, Color(0.7, 1.0, 0.85))
	# Barricade: block is not removed at the start of the turn. Blur buys the
	# same reprieve one turn at a time (consuming a stack — see block_persists).
	if not Stats.block_persists(player):
		player.block = 0
	# Next Turn Block (Dodge and Roll): banked stacks pour through gain_block
	# now — after the reset above, so the payout isn't wiped — then the status
	# clears ("Lose all when triggered"). Frail/Defense apply at payout time.
	var nt_block: int = Stats.consume_status(player, &"next_turn_block")
	if nt_block > 0:
		gain_block(player, nt_block)
		GameLog.add("Next Turn Block: +%d Block." % nt_block, Color(0.7, 0.85, 1.0))
	_cancel_targeting()
	# Pre-roll enemy intents for this turn
	for e in enemies:
		if e.is_alive():
			_roll_intent(e)
	var draw_count: int = GameState.hand_size
	if turn == 1:
		# Speed grants extra cards on the opening hand only.
		draw_count += Stats.deckbuilder_bonus_draws_turn_1()
		# Ambush carryover adjusts the opening hand (+2 ambush / -2 ambushed).
		draw_count += _ambush_draw_delta
	# Next Turn Draw (Predator / Doppelganger): banked stacks join the
	# turn-start hand, then the status clears.
	var nt_draw: int = Stats.consume_status(player, &"next_turn_draw")
	if nt_draw > 0:
		draw_count += nt_draw
		GameLog.add("Next Turn Draw: +%d card%s." % [nt_draw, "s" if nt_draw > 1 else ""],
			Color(0.7, 0.95, 1.0))
	draw_cards(maxi(0, draw_count))
	# Nightmare: the copies picked LAST turn arrive with the turn-start hand.
	_deliver_nightmare_copies()
	# Confused (Snecko): re-randomize every hand card's cost each turn. Runs after
	# the draw so retained cards get a fresh roll too. The hand cost display reads
	# get_cost(), so the randomized number shows and is what play charges.
	_apply_confused_to_hand()
	TriggerBus.emit_signal("turn_started", {"turn": turn, "scene": self})
	_fire_item_triggers("turn_started")
	_fire_power_triggers("turn_started")
	# Recurring turn heartbeat (here it coincides with turn start; Action runs
	# it off a timer). Drives Happy Flower + the per-turn attack-window reset.
	TriggerBus.emit_signal("turn_tick", {"turn": turn, "scene": self})
	_fire_item_triggers("turn_tick")
	# Deckbuilder charges EVERY charged active each turn.
	GameState.charge_all_items(1)
	_refresh_ui()

func _on_end_turn() -> void:
	if phase != Phase.PLAYER:
		return
	_cancel_targeting()
	# Well-Laid Plans (retain-typed turn_ended triggers): before the hand
	# discards, pick up to N cards to keep this turn. The picker is async —
	# the actual turn end resumes from the confirm callback; without the
	# power (or an empty hand) fall straight through.
	var wlp: int = Stats.retain_total(power_triggers)
	if wlp > 0 and not hand.is_empty():
		_open_picker({
			"title": "Well-Laid Plans — Retain up to %d" % mini(wlp, hand.size()),
			"candidates": hand.duplicate(),
			"count": mini(wlp, hand.size()),
			"up_to": true,
			"accent": Color(0.6, 0.9, 1.0),
			"confirm_label": "Retain",
			"on_picked": Callable(self, "_apply_wlp_picks"),
		})
		return
	_finish_end_turn()

# Well-Laid Plans confirm: stamp the picks with a one-turn Retain, then run
# the turn end that was deferred while the picker was open.
func _apply_wlp_picks(picks: Array) -> void:
	for pick in picks:
		if pick is CardInstance:
			pick.retain_this_turn = true
			GameLog.add("Well-Laid Plans: %s is Retained." % pick.get_display_name(),
				Color(0.6, 0.9, 1.0))
	_finish_end_turn()

func _finish_end_turn() -> void:
	if phase != Phase.PLAYER:
		return
	# Snapshot the curse cards in hand (and the hand size, for Regret) BEFORE
	# discard. Their eot effects are applied AFTER status decay below, so a
	# status they grant (Doubt -> Weak) survives into the next turn instead of
	# being decayed away the instant it's applied.
	var eot_curses: Array = hand.duplicate()
	var eot_hand_size: int = hand.size()
	# Ice Cream: bank whatever energy is still unspent for next turn.
	if energy > 0 and GameState.has_energy_carryover_item():
		_energy_carryover = energy
	# Discard hand. Ethereal cards exhaust instead of discarding if they
	# would still be in hand at end of turn (Carnage). Retain cards stay
	# in hand. The TriggerBus emit lets items react to each exhausted
	# card (mirrors the deckbuilder's normal exhaust_card flow).
	var kept: Array[CardInstance] = []
	while not hand.is_empty():
		var c: CardInstance = hand.pop_back()
		# Mummified Hand's "free this turn" discount expires now (clear it on
		# every card leaving hand, retained ones included).
		c.temp_cost_override = -999
		if c.data != null and (c.data.retain or c.granted_retain or c.retain_this_turn):
			# c.granted_retain: Retain granted to this specific card by Scroll of
			# Enchant Weapon (crit success), in addition to the card's own retain.
			# c.retain_this_turn: Well-Laid Plans' end-of-turn pick — one turn only.
			c.retain_this_turn = false
			kept.append(c)
		elif c.data != null and c.data.sly:
			_resolve_sly_on_discard(c)
			discard_pile.append(c)
		elif c.data != null and c.data.ethereal:
			exhaust_pile.append(c)
			GameLog.add("%s is Ethereal — exhausted." % c.data.display_name, Color(0.75, 0.85, 1.0))
			TriggerBus.emit_signal("card_exhausted", {"card": c, "scene": self})
			_fire_power_triggers("card_exhausted", {"card": c})
		else:
			discard_pile.append(c)
	hand = kept
	TriggerBus.emit_signal("turn_ended", {"turn": turn, "scene": self})
	_fire_item_triggers("turn_ended")
	_fire_power_triggers("turn_ended")
	# Per-turn DoT tick (Poison/Burn/Regen/Leeches). Bleed is excluded here
	# (tick_bleed = false) — in the deckbuilder it's attack-triggered, not a
	# turn-boundary DoT (see _resolve_card / deckbuilder_bleed_on_attack).
	Stats.tick_actor_statuses(player, self, false)
	# Decay player statuses BEFORE enemies act so debuffs the player
	# just applied to enemies survive through the enemy turn. do_grow = false:
	# deckbuilder Bleed never grows, it's cleared wholesale below.
	_decay_statuses(player)
	# All ranks of Bleed are lost at end of the player's turn — on the player
	# and on every enemy (Bleed is a within-your-turn, attack-synergy status).
	# Choked (Choke) shares the wipe: it only punishes cards played this turn.
	Stats.clear_bleed(player)
	Stats.clear_status_stacks(player, &"choked")
	for _e in enemies:
		Stats.clear_bleed(_e)
		Stats.clear_status_stacks(_e, &"choked")
	# Curse cards' end-of-turn effects land here — AFTER decay — so a status they
	# grant the player (Doubt -> Weak, Punctured Eye -> Blind) persists to the next
	# turn. HP-loss curses (Decay/Regret) resolve here too; a lethal one is caught
	# by the combat-end check just below.
	_fire_curse_triggers("eot", eot_curses, eot_hand_size)
	phase = Phase.ENEMY
	_refresh_ui()

	if _check_combat_end():
		return

	_execute_enemy_turn()

	if _check_combat_end():
		return

	# Enemies tick and decay after their actions.
	for e in enemies:
		if e.is_alive():
			Stats.tick_actor_statuses(e, self, false)
			_decay_statuses(e)

	# An enemy may have died from their own Bleed tick — re-check.
	if _check_combat_end():
		return

	_start_player_turn()

func _execute_enemy_turn() -> void:
	# Split spawns are collected and applied after the loop so we never mutate
	# `enemies` mid-iteration; consumed splitters are marked dead by _perform_split.
	var split_spawns: Array[CombatActor] = []
	for enemy in enemies:
		if not enemy.is_alive() or not player.is_alive():
			continue
		# Block resets at the start of the enemy's own action phase
		# (matches JS rules); Barricade keeps it.
		if not Stats.keeps_block(enemy):
			enemy.block = 0
		# Stunned (Scroll of Scare Monster): the enemy does nothing this turn. The
		# stun stack steps down by 1 in the end-of-turn decay below.
		if enemy.get_status(&"stun") > 0:
			GameLog.add("%s is Stunned and does nothing." % enemy.display_name, Color(0.9, 0.85, 0.5))
			continue
		var move: Dictionary = enemy.planned_move
		if move.is_empty():
			continue
		if move.get("split", false):
			split_spawns.append_array(_perform_split(enemy))
			continue
		GameLog.add("%s: %s" % [enemy.display_name, move.get("display", "?")],
			Color(0.9, 0.8, 0.6))
		var effects: Array = move.get("effects", [])
		for effect in effects:
			if not enemy.is_alive() or not player.is_alive():
				break
			var tgt: CombatActor = _resolve_enemy_effect_target(enemy, effect.get("target", "player"))
			var ctx := {
				"source": enemy,
				"target": tgt,
				"scene": self,
				"card": null,
			}
			EffectSystem.apply(effect, ctx)
	if not split_spawns.is_empty():
		_commit_split_spawns(split_spawns)

# Spawn this splitter's copies (each at its CURRENT HP) and consume the parent.
# Returns the new actors; the caller commits them to `enemies` after the loop.
func _perform_split(splitter: CombatActor) -> Array[CombatActor]:
	var spawns: Array[CombatActor] = []
	var child_data: EnemyData = Data.get_enemy(splitter.split_into)
	if child_data == null:
		return spawns
	var child_hp: int = maxi(1, splitter.hp)
	for _i in splitter.split_count:
		var child: CombatActor = CombatActor.from_enemy(child_data, _rng)
		child.max_hp = child_hp
		child.hp = child_hp
		spawns.append(child)
	GameLog.add("%s splits into %d %s!" % [splitter.display_name,
		splitter.split_count, child_data.display_name], Color(0.7, 1.0, 0.7))
	splitter.dead = true   # the parent is consumed by the split
	return spawns

# Drop consumed splitters, fold in the new copies, and rebuild the enemy row.
func _commit_split_spawns(spawns: Array[CombatActor]) -> void:
	var survivors: Array[CombatActor] = []
	for e in enemies:
		if e.is_alive():
			survivors.append(e)
	# Respect the battlefield cap — a split into a full row drops the overflow.
	var room: int = maxi(0, MAX_ENEMIES - survivors.size())
	if room > 0:
		survivors.append_array(spawns.slice(0, room))
	enemies = survivors
	_build_enemy_views()
	_refresh_ui()

func _resolve_enemy_effect_target(enemy: CombatActor, target_str: String) -> CombatActor:
	match target_str:
		"player":
			return player
		"self":
			return enemy
		_:
			return player

func _check_combat_end() -> bool:
	if phase == Phase.WON or phase == Phase.LOST:
		return true
	if not player.is_alive():
		phase = Phase.LOST
		GameState.phase = GameState.Phase.DEAD
		GameLog.add("You have been defeated.", Color(1.0, 0.4, 0.4))
		TriggerBus.emit_signal("combat_ended", {"victory": false, "scene": self, "dev": dev_combat})
		emit_signal("combat_ended", false)
		# Consumable buffs last one combat — drop them and the live context.
		GameState.clear_combat_context()
		GameState.clear_temp_buffs()
		_show_end_overlay(false)
		_refresh_ui()
		return true
	var any_alive := false
	for e in enemies:
		if e.is_alive():
			any_alive = true
			break
	if not any_alive:
		phase = Phase.WON
		GameLog.add("Victory!", Color(0.4, 1.0, 0.6))
		# Items with combat_ended triggers fire on victory only.
		_fire_item_triggers("combat_ended")
		TriggerBus.emit_signal("combat_ended", {"victory": true, "scene": self, "dev": dev_combat})
		emit_signal("combat_ended", true)
		_award_combat_gold()
		_award_combat_consumable()
		# Consumable buffs last one combat — drop them and the live context.
		GameState.clear_combat_context()
		GameState.clear_temp_buffs()
		# Per-combat card cost discounts (Empty Tome) expire with the fight.
		for c in GameState.deck:
			if c is CardInstance:
				c.combat_cost_delta = 0
		_refresh_ui()
		_show_reward_modal()
		return true
	return false

# Gold reward tiers match the JS combat-flow (20 / 35 / 55g) keyed on
# total_games_beaten so harder runs pay better. Elite multiplier lands
# alongside the elite floor in Phase 2 commit 10.
var _last_gold_award: int = 0

func _award_combat_gold() -> void:
	var amt: int = 20
	if GameState.total_games_beaten >= 10:
		amt = 55
	elif GameState.total_games_beaten >= 5:
		amt = 35
	if is_elite:
		amt = int(amt * ELITE_GOLD_MULT)
	_last_gold_award = amt
	GameState.change_gold(amt)
	GameLog.add("You loot %d gold." % amt, Color(1.0, 0.9, 0.3))

# Every deckbuilder combat also drops one consumable (50/50 a potion or an inert
# scroll stub). Dev test-combats are exempt so testing doesn't hand out loot.
func _award_combat_consumable() -> void:
	if dev_combat:
		return
	var e: Dictionary = GameState.grant_random_consumable_loot(_rng)
	if e.is_empty():
		return
	if String(e.get("type", "")) == "potion":
		var p: PotionData = Data.get_potion(StringName(e.get("id", "")))
		Notifications.notify("Found a potion: %s" % (PotionSystem.display_name(p) if p != null else "Potion"),
			PotionSystem.POTION_COLOR)
	else:
		Notifications.notify("Found an Unidentified Scroll.", Color(0.6, 0.5, 0.8))
	_refresh_loot_button()

# ------------------------------------------------------------------
# Item triggers — declarative ItemData.triggers fan-out
# ------------------------------------------------------------------

func _fire_item_triggers(trigger_name: String, ctx_extras: Dictionary = {}) -> void:
	# Delegates to the shared runner so every combat mode fires items the same
	# way. ctx_extras forwards the played card / its target for card_played.
	ItemTriggers.fire(trigger_name, self, player, enemies, ctx_extras, turn)

# ------------------------------------------------------------------
# End-of-combat overlay
# ------------------------------------------------------------------

var _end_overlay: Control = null

func _show_end_overlay(victory: bool) -> void:
	if _end_overlay != null:
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(480, 260)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	overlay.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 24)
	title.size = Vector2(440, 48)
	title.text = "VICTORY!" if victory else "DEFEAT"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if victory else Color(1.0, 0.5, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var info := Label.new()
	info.position = Vector2(20, 92)
	info.size = Vector2(440, 60)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	if victory:
		info.text = "HP %d / %d   Turn %d" % [GameState.hp, GameState.max_hp, turn]
	else:
		info.text = "The run ends."
	panel.add_child(info)

	var btn := Button.new()
	btn.position = Vector2(120, 180)
	btn.size = Vector2(240, 56)
	# On defeat the button leads to the run-level Game Over screen (shown by
	# the overworld once this combat closes), not straight to the menu.
	btn.text = "Next combat" if victory else "Continue"
	btn.pressed.connect(func(): _close(victory))
	panel.add_child(btn)

	add_child(overlay)
	_end_overlay = overlay

func _close(was_victory: bool) -> void:
	emit_signal("closed", was_victory, target_game_id)
	queue_free()

# ------------------------------------------------------------------
# Card reward modal — shown after victory, before the end overlay.
# ------------------------------------------------------------------

var _reward_modal: Node = null

func _show_reward_modal() -> void:
	if _reward_modal != null:
		return
	# No offerable cards (empty pool) — skip straight to the victory overlay.
	if Data.reward_card_pool().is_empty():
		_show_end_overlay(true)
		return
	# Shared card-reward UI (rolling, selection, reroll, skip, deck-add all
	# live in CardRewardScreen). Hosted on its own layer above the combat.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var reward := CardRewardScreen.new()
	layer.add_child(reward)
	_reward_modal = layer
	reward.closed.connect(func():
		if _reward_modal != null:
			_reward_modal.queue_free()
			_reward_modal = null
		_close(true))
	# Scope the offered cards to the run's chosen DECK (e.g. the Ironclad deck
	# offers ironclad-tagged cards regardless of character). The Random deck's
	# empty tag falls back to the full reward pool inside reward_card_pool().
	reward.setup(GameState.deck_reward_tag())

func _decay_statuses(actor: CombatActor) -> void:
	# do_grow = false: deckbuilder Bleed is attack-triggered and wiped each
	# turn (see _on_end_turn), so it must never grow at the turn boundary.
	Stats.decay_actor_statuses(actor, false)

# ------------------------------------------------------------------
# Card play
# ------------------------------------------------------------------

# Energy a card costs to play right now, including the Fear surcharge
# (+1 per non-Skill card while the player is afraid). All play-time cost gates
# and the energy deduction route through this so the number the player is
# charged matches what the hand shows. CardInstance.get_cost() stays the card's
# own context-free cost (used by shop / rest / collection).
func _card_cost(card: CardInstance) -> int:
	return card.get_cost() + Stats.fear_card_surcharge(player, card)

# Confused (Snecko): true while the player carries the status.
func _is_confused() -> bool:
	return player != null and player.get_status(&"confused") > 0

# Re-roll every hand card's cost to a random 0..max_energy value while Confused.
# A no-op otherwise. temp_cost_override is the same absolute-override slot the
# hand/play sites already honour, so the randomized cost is what's shown and paid.
func _apply_confused_to_hand() -> void:
	if not _is_confused():
		return
	for c in hand:
		c.temp_cost_override = _rng.randi_range(0, max_energy)

func _try_play_card(card: CardInstance) -> void:
	if phase != Phase.PLAYER:
		return
	if _card_cost(card) > energy:
		GameLog.add("Not enough energy for %s." % card.get_display_name(), Color(0.9, 0.7, 0.3))
		return
	# If we're already targeting and the same card is clicked, cancel.
	if _targeting and _selected_card == card:
		_cancel_targeting()
		return
	if card.wants_target():
		_selected_card = card
		_targeting = true
		if _targeting_arrow != null:
			# Stem the arrow from the played card itself (top-center of its
			# hand view) so it visibly originates from the card.
			_targeting_arrow.start(_card_arrow_origin(card))
		GameLog.add("Choose a target for %s." % card.get_display_name(), Color(0.7, 0.9, 1.0))
		_refresh_ui()
	else:
		_resolve_card(card, null)

func _on_player_portrait_input(event: InputEvent) -> void:
	# Drinking a potion yourself: click your own portrait while aiming one.
	if _selected_potion_index < 0 or not _targeting:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_resolve_potion(_selected_potion_index, player)
		accept_event()

func _on_enemy_clicked(idx: int) -> void:
	if not _targeting:
		return
	if idx < 0 or idx >= enemies.size():
		return
	var tgt: CombatActor = enemies[idx]
	if not tgt.is_alive():
		return
	if _selected_potion_index >= 0:
		_resolve_potion(_selected_potion_index, tgt)
		return
	if _selected_item != null:
		var item := _selected_item
		_cancel_targeting()
		if GameState.use_item(item, tgt):
			GameLog.add("Used %s on %s." % [item.display_name, tgt.display_name],
				Color(0.85, 0.9, 1.0))
		return
	if _selected_card == null:
		return
	var card := _selected_card
	_cancel_targeting()
	_resolve_card(card, tgt)

# Global point the targeting arrow stems from: the top-center (edge facing the
# enemies) of the played card's hand view. Falls back to the hand row's
# bottom-center if the view can't be located.
func _card_arrow_origin(card: CardInstance) -> Vector2:
	for view in _hand_views:
		if view.card == card:
			var r: Rect2 = view.get_global_rect()
			return Vector2(r.position.x + r.size.x * 0.5, r.position.y)
	return global_position + Vector2(size.x * 0.5, size.y - 80.0)

func _cancel_targeting() -> void:
	_selected_card = null
	_selected_item = null
	_selected_potion_index = -1
	_targeting = false
	if _targeting_arrow != null:
		_targeting_arrow.stop()
	_refresh_ui()

# Use button on the item rack. Enemy-aimed items (potions that throw at a foe)
# pop the targeting arrow and resolve on the next enemy click; everything else
# fires immediately. Mirrors the card targeting flow.
func _on_item_use_requested(item: ItemData, origin: Vector2) -> void:
	if phase != Phase.PLAYER:
		return
	if not GameState.can_fire_item(item):
		if item.is_charged() and not item.is_fully_charged():
			Notifications.notify("%s is charging (%d/%d)." % [
				item.display_name, item.current_charge, item.max_charge()],
				Color(0.9, 0.8, 0.5))
		return
	if item.wants_target() and _has_living_enemy():
		_cancel_targeting()
		_selected_item = item
		_targeting = true
		if _targeting_arrow != null:
			_targeting_arrow.start(origin)
		GameLog.add("Choose a target for %s." % item.display_name, Color(0.7, 0.9, 1.0))
		_refresh_ui()
		return
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.85, 0.9, 1.0))

func _has_living_enemy() -> bool:
	for e in enemies:
		if e != null and e.is_alive():
			return true
	return false

# ------------------------------------------------------------------
# Drag-to-play — press a card and drag it onto the field. Non-targeting
# cards play when dropped anywhere outside the hand; targeted cards only
# play when dropped on a live enemy. Mirrors the HTML build's drag flow.
# ------------------------------------------------------------------

func _on_card_drag_started(card: CardInstance) -> void:
	if phase != Phase.PLAYER:
		return
	# Unplayable cards (curses) can't be played — don't even start the drag.
	if card.data != null and card.data.unplayable:
		GameLog.add("%s is unplayable." % card.get_display_name(), Color(0.8, 0.6, 0.8))
		return
	if _card_cost(card) > energy:
		GameLog.add("Not enough energy for %s." % card.get_display_name(), Color(0.9, 0.7, 0.3))
		return
	# Drag and click-targeting are mutually exclusive; drop any active pick.
	_cancel_targeting()
	_drag_card = card
	# Dim the source card in hand while its ghost is out on the field.
	for v in _hand_views:
		if v.card == card:
			v.modulate = Color(1, 1, 1, 0.3)
	# Floating clone that tracks the cursor.
	_drag_ghost = CardView.new()
	add_child(_drag_ghost)
	_drag_ghost.setup(card)
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.modulate = Color(1, 1, 1, 0.9)
	_drag_ghost.z_index = 200
	# Targeted cards get the aim arrow + lit-up enemy row.
	if card.wants_target():
		if _targeting_arrow != null:
			_targeting_arrow.start(_card_arrow_origin(card))
		for view in _enemy_views:
			view.set_targetable(true)
	_update_drag(get_global_mouse_position())

func _update_drag(pos: Vector2) -> void:
	if _drag_ghost != null:
		_drag_ghost.global_position = pos - Vector2(CardView.CARD_W, CardView.CARD_H) * 0.5
	# Highlight whichever live enemy sits under the cursor.
	var hovered: EnemyView = _enemy_view_at(pos)
	if hovered != _drag_hover_enemy:
		if _drag_hover_enemy != null and is_instance_valid(_drag_hover_enemy):
			_drag_hover_enemy.modulate = Color.WHITE
		_drag_hover_enemy = hovered
		if hovered != null:
			hovered.modulate = Color(1.3, 1.3, 1.3)
		_update_ghost_preview(hovered)

func _finish_drag(pos: Vector2) -> void:
	var card := _drag_card
	_clear_drag_visuals()
	if card == null or phase != Phase.PLAYER or not (card in hand):
		return
	# Unplayable cards (curses) sit in hand but can't be played manually.
	if card.data != null and card.data.unplayable:
		return
	if _card_cost(card) > energy:
		return
	if card.wants_target():
		# Targeted: only resolves when dropped on a live enemy.
		var view: EnemyView = _enemy_view_at(pos)
		if view != null:
			var idx: int = _enemy_views.find(view)
			if idx >= 0 and idx < enemies.size() and enemies[idx].is_alive():
				_resolve_card(card, enemies[idx])
	else:
		# Non-targeting: plays anywhere except dropped back onto the hand.
		if _hand_area != null and _hand_area.get_global_rect().has_point(pos):
			return
		_resolve_card(card, null)

func _cancel_drag() -> void:
	_clear_drag_visuals()

func _clear_drag_visuals() -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null
	if _drag_hover_enemy != null and is_instance_valid(_drag_hover_enemy):
		_drag_hover_enemy.modulate = Color.WHITE
	_drag_hover_enemy = null
	_clear_hover_card()
	if _targeting_arrow != null:
		_targeting_arrow.stop()
	_drag_card = null
	# Restores dimmed hand-card modulate + clears enemy targetable highlight.
	_refresh_ui()

# Re-points the floating drag ghost's number preview at the enemy under the
# cursor (or clears it), so the card's OWN "Deal N Dmg" rewrites to what would
# land on THAT enemy — folding in its Vulnerable / Bruise / Brace — instead of a
# separate damage number popping up next to the enemy. Non-targeting drags and
# empty hovers fall back to the plain self-scaled card text.
func _update_ghost_preview(view: EnemyView) -> void:
	if _drag_ghost == null or _drag_card == null:
		return
	var target_actor: CombatActor = null
	if view != null and _drag_card.wants_target():
		var idx: int = _enemy_views.find(view)
		if idx >= 0 and idx < enemies.size() and enemies[idx].is_alive():
			target_actor = enemies[idx]
	_drag_ghost.set_preview_target(target_actor)

func _clear_hover_card() -> void:
	if _hover_card != null:
		_hover_card.queue_free()
		_hover_card = null

func _enemy_view_at(pos: Vector2) -> EnemyView:
	for i in range(_enemy_views.size()):
		var view: EnemyView = _enemy_views[i]
		if not is_instance_valid(view):
			continue
		if i >= enemies.size() or not enemies[i].is_alive():
			continue
		if view.get_global_rect().has_point(pos):
			return view
	return null

func _resolve_card(card: CardInstance, target_enemy: CombatActor) -> void:
	# X-cost cards (cost -1) spend ALL remaining energy; the amount becomes X
	# for their hits_from: "energy" effects. Fixed-cost cards pay normally.
	if card.get_cost() < 0:
		_last_x_value = maxi(0, energy)
		energy = 0
	else:
		_last_x_value = 0
		energy -= _card_cost(card)
	# Setup's "free until played" ends here — the card has now been played.
	card.free_until_played = false
	# Burst doubles the next SKILL played this turn. Snapshot the stacks BEFORE
	# the card's own effects resolve so the Burst that grants the stack never
	# doubles itself (mirrors how Rage/Double Tap can't self-proc).
	var burst_armed: bool = card.is_skill() and player.get_status(&"burst") > 0
	TriggerBus.emit_signal("card_played", {
		"card": card, "target": target_enemy, "scene": self,
	})
	# Power-card triggers fire BEFORE the card's own effects resolve.
	# This is the right order for "Whenever you play a card …" Powers
	# because the Power being played hasn't registered its trigger
	# yet, so it doesn't self-trigger.
	_fire_power_triggers("card_played", {"card": card})
	# Rage listens on the attack-only sibling event. Fired before the card's
	# effects like card_played, so an Attack that grants Rage can't self-proc.
	if card.is_attack():
		_fire_power_triggers("attack_played", {"card": card})
	_fire_item_triggers("card_played", {"card": card, "target": target_enemy})

	# Choked bites on the card PLAY, before its effects — so the play that
	# inflicts Choked never procs itself, and every later play (any card
	# type) costs the choked enemy its stacks.
	Stats.choked_on_card_played(enemies, self)

	_apply_card_effects(card, target_enemy)

	# The card has fully resolved its primary play. card_resolved is a
	# general post-resolution hook (after card_played + the effects, before
	# discard/exhaust); fired once, not per Replay.
	TriggerBus.emit_signal("card_resolved", {
		"card": card, "target": target_enemy, "scene": self,
	})
	_fire_item_triggers("card_resolved", {"card": card, "target": target_enemy})

	# Replay addon: the card re-resolves its own effects N extra times.
	# Carried natively (CardData.addons) or granted by an item — Duplicator
	# gives weapon attack cards Replay 1. Resolved through CardMods so the
	# count folds native + granted in one place.
	var replays: int = CardMods.replay_count(card.data)
	for _i in replays:
		replay_card_effects(card, target_enemy)

	# Double Tap: the next Attack played this turn resolves its effects twice.
	# One stack per doubled Attack (the upgraded card banks 2). Consumed after
	# the Replay pass so the doubling is one clean extra resolution.
	if card.is_attack() and player.get_status(&"double_tap") > 0:
		player.add_status(&"double_tap", -1)
		GameLog.add("Double Tap: %s is played twice!" % card.get_display_name(),
			Color(0.85, 0.7, 1.0))
		replay_card_effects(card, target_enemy)

	# Burst: the next Skill played this turn resolves its effects twice — the
	# Skill sibling of Double Tap. Gated on the pre-effects snapshot so a
	# freshly-played Burst never doubles itself.
	if burst_armed and player.get_status(&"burst") > 0:
		player.add_status(&"burst", -1)
		GameLog.add("Burst: %s is played twice!" % card.get_display_name(),
			Color(0.85, 0.7, 1.0))
		replay_card_effects(card, target_enemy)

	# Bleed (deckbuilder rule): once an ATTACK card has fully resolved (incl.
	# Replays), everything afflicted with Bleed takes raw HP = its stacks — the
	# player for their own Bleed, each enemy for theirs. Runs AFTER resolution
	# so stacks added/removed by the card count. Non-attack cards don't proc it.
	if card.is_attack():
		var bleeders: Array = [player]
		bleeders.append_array(enemies)
		Stats.deckbuilder_bleed_on_attack(bleeders, self)

	# Playing a card fires any on_play_other curse in hand (Pain: lose HP when
	# you play another card). Curse cards are unplayable, so `card` is never a
	# curse here. (Action/strategy translate on_play_other -> on_action.)
	_fire_curse_triggers("on_play_other", hand, hand.size())

	# Fear: playing a Skill card steadies the player — shed 1 Fear stack. Fires
	# once per played Skill (not per Replay), the deckbuilder-side decay rule.
	if card.is_skill() and player.get_status(&"fear") > 0:
		player.add_status(&"fear", -1)
		GameLog.add("Fear -1 (Skill played).", Color(0.7, 0.9, 1.0))

	# Destroy: the card is removed from the run deck permanently when played. It
	# leaves hand (no discard/exhaust pile) and is dropped from GameState.deck so
	# it never returns. Takes precedence over exhaust/discard below.
	if card.data.destroy:
		hand.erase(card)
		GameState.destroy_card_instance(card)
		GameLog.add("%s is Destroyed — removed from your deck." % card.get_display_name(),
			Color(0.9, 0.55, 0.55))
		TriggerBus.emit_signal("card_exhausted", {"card": card, "scene": self})
		_fire_power_triggers("card_exhausted", {"card": card})
	# Cards with the exhaust flag exhaust. Powers are simply used — their
	# effect lives on the player for the combat — so they leave hand without
	# entering any pile and do NOT count as an exhaust (Feel No Pain and
	# card_exhausted triggers stay quiet).
	elif card.data.exhaust:
		exhaust_card(card)
	elif card.is_power():
		hand.erase(card)
		Stats.register_power(player, card.data)
	else:
		# from_play: a Sly card that was just played normally must NOT re-trigger
		# its play-on-discard as it heads to the pile (that would double-resolve).
		discard_card(card, true)
	_refresh_ui()
	# Killing the last enemy with a card ends combat immediately.
	_check_combat_end()

# Effect types that operate on the player / combat scene rather than a chosen
# actor. They're routed to the player so they resolve once even on cards played
# without an enemy target. deal_damage/status/etc. are NOT in here — those still
# default to the enemy.
const _SCENE_EFFECT_TYPES := [
	"draw", "gain_energy", "lose_energy", "discard", "exhaust", "exhaust_self",
	"topdeck", "conjure", "conjure_random", "recall", "gain_gold", "gain_loot", "gain_chest",
	"roll_gold", "upgrade_hand", "upgrade_random_cards", "boost_cards",
	"free_random_hand_card", "reduce_card_cost",
	# Ironclad skills batch: Entrench/Limit Break act on the player, Havoc /
	# Dual Wield / Exhume act on the piles — all must fire on a targetless play.
	"double_stat", "autoplay_top", "copy_from_hand", "exhume",
	# Silent/Defect skills batch: Hologram/Seek browse the piles, Bullet Time
	# frees the hand, Nightmare banks a pick — all targetless plays.
	"retrieve", "free_hand", "nightmare",
	# Power installs (After Image / Envenom / Barricade / Well-Laid Plans):
	# they arm the scene/player, so a targetless play must still resolve them.
	"trigger", "keep_block", "retain",
]

func _is_scene_effect(effect_type: String) -> bool:
	return effect_type in _SCENE_EFFECT_TYPES

func _apply_card_effects(card: CardInstance, target_enemy: CombatActor) -> void:
	# Resolves a card's own effect list against the picked target. Split out
	# of _resolve_card so the Replay addon can re-run JUST the effects (no
	# energy cost, no card_resolved emit, no discard).
	for raw_effect in card.get_effects():
		var effect: Dictionary = _apply_card_boosts(raw_effect, card)
		effect = Stats.apply_addons_to_effect(effect, card.data)
		# Vorpal rides the physical card instance (per-instance roll), so stamp it
		# here where the CardInstance is in scope; deal_damage reads it per target.
		effect = card.apply_vorpal_to_effect(effect)
		# Scene-scoped effects (draw, gain energy, etc.) ignore any actor target —
		# they act on the player/scene. Default them to "self" so they still fire
		# when a card was played WITHOUT picking an enemy (e.g. Shrug It Off's
		# "Draw 1", Adrenaline's energy/draw). Otherwise they'd fall to the
		# default "enemy" target and get dropped when no enemy is selected.
		var default_target: String = "self" if _is_scene_effect(effect.get("type", "")) else "enemy"
		var t_str: String = effect.get("target", default_target)
		# Indiscriminate (Blood Magic) skips the manual picker — re-route
		# enemy-targeted dmg through random_enemy so a seed target lands
		# and _h_dmg can re-roll per hit from there.
		if effect.get("indiscriminate", false) and t_str == "enemy" and target_enemy == null:
			t_str = "random_enemy"
		var targets: Array = []
		match t_str:
			"enemy":
				if target_enemy != null:
					targets = [target_enemy]
			"all_enemies":
				for e in enemies:
					if e.is_alive():
						targets.append(e)
			"self":
				targets = [player]
			"player":
				targets = [player]
			"random_enemy":
				var live: Array = []
				for e in enemies:
					if e.is_alive():
						live.append(e)
				if not live.is_empty():
					targets = [live[_rng.randi() % live.size()]]
			_:
				if target_enemy != null:
					targets = [target_enemy]
				else:
					targets = [player]

		for tgt in targets:
			var ctx := {
				"source": player,
				"target": tgt,
				"scene": self,
				"card": card,
				"x_value": _last_x_value,
			}
			EffectSystem.apply(effect, ctx)

func replay_card_effects(card: CardInstance, target_enemy) -> void:
	# Replay addon: re-run a card's effects one extra time. Effects only —
	# the card has already paid its cost and fired card_resolved, so this
	# just re-resolves the hit(s)/block/etc. If the first pass already
	# cleared the room, the dmg handlers no-op on the dead target.
	if card == null:
		return
	# Only ever replay damage onto a living enemy. If the first hit cleared
	# the picked target, pass null: single-target effects no-op, while
	# all_enemies effects still sweep whatever enemies remain, and self
	# effects (block/heal) always re-apply. This also guards the case where
	# no enemies are left — we must never replay an attack onto ourselves.
	var tgt: CombatActor = null
	if target_enemy is CombatActor and not target_enemy.is_player and target_enemy.is_alive():
		tgt = target_enemy
	_apply_card_effects(card, tgt)
	GameLog.add("%s replays!" % card.data.display_name, Color(0.7, 1.0, 0.7))
	_check_combat_end()

# ------------------------------------------------------------------
# Curse cards (CardData.triggers)
# ------------------------------------------------------------------

# Fires the triggered effects of every curse card currently in hand whose `on`
# matches `trigger` ("eot" / "on_play_other"). The owning curse is both source
# and target — self-inflicted (target "self"). `per: "card_in_hand"` effects
# (Regret) scale by the cards in hand.
func _fire_curse_triggers(trigger: String, cards: Array, hand_size: int) -> void:
	for c in cards:
		if c == null or c.data == null or c.data.triggers.is_empty():
			continue
		for trig in c.data.triggers:
			if String(trig.get("on", "")) != trigger:
				continue
			for raw in trig.get("effects", []):
				if not (raw is Dictionary):
					continue
				var effect: Dictionary = _resolve_curse_effect(raw, hand_size)
				if effect.is_empty():
					continue
				EffectSystem.apply(effect, {
					"source": player, "target": player, "scene": self, "card": c,
				})
	_refresh_ui()

# Resolves the deckbuilder `per` scaler — Regret's `per: "card_in_hand"` (× cards
# in hand right now). A zero multiplier returns an empty dict so the caller skips
# the no-op hit. on_action / per_action are STRATEGY concepts the translators map
# to; the deckbuilder never sees them.
func _resolve_curse_effect(effect: Dictionary, hand_size: int) -> Dictionary:
	if String(effect.get("per", "")) != "card_in_hand":
		return effect
	var n: int = hand_size
	if n <= 0:
		return {}
	var out: Dictionary = effect.duplicate()
	out.erase("per")
	out["value"] = int(effect.get("value", 1)) * n
	GameLog.add("Regret: %d card(s) in hand — lose %d HP." % [n, int(out["value"])],
		Color(0.9, 0.6, 0.7))
	return out

# ------------------------------------------------------------------
# Effect callbacks (invoked by EffectSystem handlers via ctx.scene)
# ------------------------------------------------------------------

# Applies a damaging effect's element on-hit side effect (Elements registry) to
# a target that just took a connecting hit. No-op when the effect has no element
# or the element's condition isn't met.
func _apply_element_on_hit(effect: Dictionary, source, target) -> void:
	var oh: Dictionary = Elements.on_hit_status(effect.get("element", ""), target, null)
	if oh.is_empty():
		return
	apply_status(target, StringName(oh["status"]), int(oh["stacks"]), source)

func deal_damage(source: CombatActor, target: CombatActor, base_amount: int, effect: Dictionary) -> void:
	if target == null or not target.is_alive():
		return
	var damage_type: String = String(effect.get("damage_type", "melee"))

	# A player melee/ranged swing at an enemy is an "attack" for streak
	# items (Dead Eye). Fold any active streak bonus into the swing BEFORE
	# resolving so Power/Weak/Vulnerable treat it like the rest of the hit.
	var is_player_attack: bool = source != null and source.is_player \
		and (damage_type == "melee" or damage_type == "ranged") \
		and not target.is_player
	if is_player_attack:
		base_amount += GameState.streak_attack_bonus(target)

	# Vorpal: flat bonus when this swing's bound mode (here, Deckbuilder) and the
	# target's weight match the card's roll. Added to base so Power/Vulnerable/etc.
	# still layer on top, matching the other pre-resolve flat bonuses.
	base_amount += Stats.vorpal_damage_bonus(effect, target, Stats.Mode.DECKBUILDER)

	# Canonical damage math lives in Stats.resolve_damage (Blind whiff,
	# Power/Weak, Vulnerable, Dodge, block soak) so all three modes agree.
	# The scene-specific tail below — logging, triggers, Soul Link, death,
	# Infuse, Thorns — stays here.
	var res := Stats.resolve_damage(source, target, base_amount, effect, Stats.Mode.DECKBUILDER, _rng)
	if res.missed:
		var who: String = "You" if source.is_player else source.display_name
		GameLog.add("%s swings blind and misses!" % who, Color(0.85, 0.85, 0.55))
		_float_text(target, "MISS", FloatingNumbers.MISS_COLOR)
		# A whiff breaks Dead Eye's streak.
		if is_player_attack:
			TriggerBus.emit_signal("attack_missed",
				{"source": source, "target": target, "scene": self})
			_fire_item_triggers("attack_missed", {"target": target})
		return
	if res.dodged:
		GameLog.add("%s dodges!" % target.display_name, Color(0.7, 0.9, 1.0))
		return
	if res.get("buffered", false):
		var bwho: String = "You" if target.is_player else target.display_name
		GameLog.add("%s's Buffer absorbs the blow!" % bwho, Color(0.8, 0.9, 1.0))
	# Element "Effect on Attack": a connecting elemental hit applies its on-hit
	# status (Fire -> Burn, Blood -> Bleed, Poison -> Poison, …) per the Elements
	# registry. Fires on a landed hit regardless of block; the registry gates the
	# per-element condition.
	_apply_element_on_hit(effect, source, target)
	# Gold on hit (King Bomber evolution): a connecting player hit on an enemy
	# grants random gold (fires on contact regardless of block).
	if source != null and source.is_player and not target.is_player:
		GameState.gain_gold_on_hit(effect, _rng)
	var amount: int = int(res.hp_loss)
	var absorbed: int = int(res.blocked)

	if amount > 0:
		if target.is_player:
			GameState.change_hp(-amount)
			target.hp = GameState.hp
		else:
			target.hp = maxi(0, target.hp - amount)
			_maybe_rewrite_split_intent(target)
		_float_number(target, amount)
		var who := "you" if target.is_player else target.display_name
		GameLog.add("%s takes %d damage." % [who.capitalize(), amount], Color(1.0, 0.6, 0.6))
		TriggerBus.emit_signal("damage_taken", {
			"target": target, "attacker": source, "amount": amount, "scene": self,
		})
		_fire_power_triggers("damage_taken")
		# Lifesteal: the attacker heals for the unblocked HP it just dealt to a
		# foe. `amount` is post-block HP loss, matching the legacy rule. Self-hits
		# (curse cards) and reflected reactions never lifesteal.
		if bool(effect.get("lifesteal", false)) and source != null and source != target \
				and not effect.get("no_reaction", false):
			heal(source, amount)
			var lsy := "You" if source.is_player else source.display_name
			GameLog.add("%s drains %d HP (Lifesteal)." % [lsy, amount], Color(0.7, 1.0, 0.7))
		# Item reactions to the PLAYER taking damage (Prayer Card, Prayer Beads).
		# Gated to the player so "whenever you take damage" never fires off an
		# enemy being hit.
		if target.is_player:
			_fire_item_triggers("damage_taken", {"target": target})
		# Soul Link propagation. Bird Head's status: whenever a soul-linked
		# actor loses HP, every other soul-linked actor takes the same raw
		# loss. Guarded by effect.from_soul_link so the cascade can't loop
		# back through itself.
		if not effect.get("from_soul_link", false) and target.get_status(&"soul_link") > 0:
			_propagate_soul_link(target, amount)
		if target.hp <= 0:
			target.dead = true
			GameLog.add("%s is defeated!" % target.display_name, Color(0.6, 1.0, 0.6))
			# Blood Magic / Infuse addon: when a dmg effect carrying
			# `infuse: N` lands the killing blow, the player gains N
			# Max HP. Deckbuilder + strategy fire on every kill; action
			# rolls a 10% chance per hit in ActionCombat.
			var infuse_stacks: int = int(effect.get("infuse", 0))
			if infuse_stacks > 0 and source != null and source.is_player:
				GameState.set_max_hp(GameState.max_hp + infuse_stacks, false)
				GameLog.add("Infuse: gained %d Max HP." % infuse_stacks,
					Color(0.85, 0.65, 1.0))
			if not target.is_player:
				TriggerBus.emit_signal("enemy_killed", {"enemy": target, "scene": self})
				_fire_item_triggers("enemy_killed")
				_fire_power_triggers("enemy_killed")
				Stats.process_corpse_explosion(target, self)
	elif absorbed > 0:
		var who := "your" if target.is_player else (target.display_name + "'s")
		GameLog.add("%s block absorbs %d." % [who, absorbed], Color(0.7, 0.8, 1.0))

	# Thorns / Bleed Thorns: triggers on any LANDED melee hit (past
	# miss and dodge), including fully-blocked ones. Routed through the
	# Stats helper so strategy combat can call the same code from its
	# trample / knockback / jump-on events later. no_reaction stops the
	# attacker's own thorns from recursing back when this reflect hits.
	var landed_melee: bool = (amount > 0 or absorbed > 0) \
		and damage_type == "melee" \
		and not effect.get("no_reaction", false) \
		and source != null and source != target
	if landed_melee:
		Stats.fire_contact_reactions(target, source, self)

	# Envenom-style powers: the player's unblocked Attack damage. The victim
	# rides in as the trigger target so an inner `inflict` lands on it.
	# Reactions (thorns reflects, soul link) never re-trigger it.
	if amount > 0 and is_player_attack and not effect.get("no_reaction", false):
		_fire_power_triggers("unblocked_attack", {"target": target})

	# Flame Barrier-style triggers: an ENEMY attack that lands on the player
	# (block counts — it's a contact, like thorns). The attacker rides in as
	# the trigger target so the inner retaliation dmg lands on it; its element
	# rider (Fire -> 1 Burn) applies per contact via deal_damage. no_reaction
	# guards the retaliation itself from re-triggering anything.
	var landed_on_player: bool = (amount > 0 or absorbed > 0) \
		and target.is_player \
		and source != null and not source.is_player \
		and (damage_type == "melee" or damage_type == "ranged") \
		and not effect.get("no_reaction", false)
	if landed_on_player:
		_fire_power_triggers("hit_by_attack", {"target": source})

	TriggerBus.emit_signal("damage_dealt", {
		"source": source, "target": target, "amount": amount, "scene": self,
	})
	_fire_power_triggers("damage_dealt")

	# The attack connected (block counts; miss/dodge already returned above).
	# Dead Eye's streak grows here. Skip a killing blow — the streak against a
	# dead enemy is never read (the next hit is a new target, which resets),
	# and emitting with a corpse would make item target-resolution fall back
	# to a different living enemy.
	if is_player_attack and target.is_alive():
		TriggerBus.emit_signal("attack_landed",
			{"source": source, "target": target, "scene": self})
		_fire_item_triggers("attack_landed", {"target": target})

func apply_dot(target: CombatActor, amount: int, source_name: String) -> void:
	# Direct HP loss from end-of-turn status ticks (Bleed today; Burn /
	# Poison once their ticks land). Bypasses block, Weak, Vulnerable,
	# and never re-triggers thorns — DoTs are NOT contact events.
	if target == null or not target.is_alive() or amount <= 0:
		return
	# Intangible (Wraith Form): each instance of HP loss clamps to 1.
	amount = Stats.intangible_clamp(target, amount)
	if target.is_player:
		GameState.change_hp(-amount)
		target.hp = GameState.hp
	else:
		target.hp = maxi(0, target.hp - amount)
		_maybe_rewrite_split_intent(target)
	_float_number(target, amount)
	var who := "You" if target.is_player else target.display_name
	GameLog.add("%s takes %d %s damage." % [who, amount, source_name],
		Color(1.0, 0.5, 0.6))
	if target.get_status(&"soul_link") > 0:
		_propagate_soul_link(target, amount)
	if target.hp <= 0:
		target.dead = true
		GameLog.add("%s is defeated!" % target.display_name, Color(0.6, 1.0, 0.6))
		if not target.is_player:
			TriggerBus.emit_signal("enemy_killed", {"enemy": target, "scene": self})
			_fire_item_triggers("enemy_killed")
			_fire_power_triggers("enemy_killed")
			Stats.process_corpse_explosion(target, self)

func _propagate_soul_link(origin: CombatActor, amount: int) -> void:
	# Bird Head / Soul Link: every other actor carrying soul_link takes
	# the same raw HP loss (block, weak, vulnerable, thorns are all
	# bypassed — it's a sympathetic wound, not a hit). Damage routes
	# through deal_damage with from_soul_link=true so this can't recurse
	# back into the cascade. Block bypass is intentional: a soul-linked
	# tank cannot absorb the chain hit for everyone else.
	if amount <= 0:
		return
	var victims: Array = []
	for e in enemies:
		if e != origin and e.is_alive() and e.get_status(&"soul_link") > 0:
			victims.append(e)
	if player != origin and player.is_alive() and player.get_status(&"soul_link") > 0:
		victims.append(player)
	for v in victims:
		# Bypass block, Weak, Vulnerable, and reactions — sympathetic loss,
		# not a hit. A soul-linked tank cannot eat the chain damage for the
		# rest of the link.
		if v.is_player:
			GameState.change_hp(-amount)
			v.hp = GameState.hp
		else:
			v.hp = maxi(0, v.hp - amount)
			_maybe_rewrite_split_intent(v)
		var who_v: String = "you" if v.is_player else v.display_name
		GameLog.add("Soul Link bleeds %d into %s." % [amount, who_v], Color(0.8, 0.5, 1.0))
		TriggerBus.emit_signal("damage_taken", {
			"target": v, "attacker": null, "amount": amount, "scene": self,
		})
		if v.hp <= 0:
			v.dead = true
			GameLog.add("%s is defeated!" % v.display_name, Color(0.6, 1.0, 0.6))
			if not v.is_player:
				TriggerBus.emit_signal("enemy_killed", {"enemy": v, "scene": self})
				_fire_item_triggers("enemy_killed")
				_fire_power_triggers("enemy_killed")
				Stats.process_corpse_explosion(v, self)

func gain_block(target: CombatActor, base_amount: int) -> void:
	if target == null:
		return
	# Shared block math: Defense status adds, Frail cuts 25% (see Stats).
	target.block += Stats.resolve_block(base_amount, target, true)

# Every enemy still standing — shared shape with BattleView so cross-mode
# helpers (Fire Breathing) can sweep the field without knowing the mode.
func living_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.is_alive():
			out.append(e)
	return out

# Pops a floating number over an actor: red for HP lost, green for HP healed.
# Enemies float over their EnemyView; the player (no avatar) floats over the HP
# readout.
func _float_number(target: CombatActor, amount: int, color: Color = FloatingNumbers.DAMAGE_COLOR) -> void:
	if amount <= 0 or not is_inside_tree():
		return
	var pos: Variant = _float_anchor_pos(target)
	if pos == null:
		return
	FloatingNumbers.spawn(self, pos, amount, color)

# "MISS" / other floating text over an actor, reusing the same anchor logic.
func _float_text(target: CombatActor, text: String, color: Color = FloatingNumbers.DAMAGE_COLOR) -> void:
	if not is_inside_tree():
		return
	var pos: Variant = _float_anchor_pos(target)
	if pos == null:
		return
	FloatingNumbers.spawn_text(self, pos, text, color)

# Local-space anchor point over `target`'s HP label / enemy view, or null.
func _float_anchor_pos(target: CombatActor) -> Variant:
	var anchor: Control = null
	if target != null and target.is_player:
		anchor = _hp_label
	else:
		var idx: int = enemies.find(target)
		if idx >= 0 and idx < _enemy_views.size():
			anchor = _enemy_views[idx]
	if anchor == null:
		return null
	return anchor.global_position - global_position + anchor.size * 0.5

func heal(target: CombatActor, amount: int) -> void:
	if target == null or amount <= 0:
		return
	var before: int = target.hp
	if target.is_player:
		GameState.change_hp(amount)
		target.hp = GameState.hp
	else:
		target.hp = mini(target.max_hp, target.hp + amount)
	_float_number(target, target.hp - before, FloatingNumbers.HEAL_COLOR)

# Leeches drain -> player heal. Called by Stats.tick_actor_statuses when a
# leeched enemy bleeds HP into the player (Jar of Leeches).
func leech_to_player(amount: int) -> void:
	if amount <= 0:
		return
	heal(player, amount)
	GameLog.add("Leeches drain %d into you." % amount, Color(0.7, 1.0, 0.7))

func apply_status(target, status: StringName, stacks: int, source = null) -> void:
	# Shared apply (guard + Persistence + add) lives in Stats.apply_status_to so
	# all three modes agree; deckbuilder's reaction is the status_applied bus +
	# Power-card triggers. Skip the reaction when nothing actually landed.
	var applied: int = Stats.apply_status_to(target, status, stacks, source)
	if applied == 0:
		return
	TriggerBus.emit_signal("status_applied", {
		"target": target, "status": status, "stacks": applied, "scene": self,
	})
	_fire_power_triggers("status_applied")

# ------------------------------------------------------------------
# Pile helpers — also called from EffectSystem default handlers
# ------------------------------------------------------------------

func draw_cards(n: int) -> Array:
	# Returns the cards actually drawn (Escape Plan's skill_block rider reads
	# them back). No Draw (Battle Trance): every further draw this turn is
	# suppressed. The status decays at end of turn (DECAY_STATUSES), so the
	# next turn-start hand is unaffected — the card draws its 3 first, then
	# locks the door.
	var drawn: Array = []
	if n > 0 and player != null and player.get_status(&"no_draw") > 0:
		GameLog.add("No Draw — no cards drawn.", Color(1.0, 0.7, 0.5))
		return drawn
	for _i in range(n):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			while not discard_pile.is_empty():
				draw_pile.append(discard_pile.pop_back())
			_shuffle(draw_pile)
		var c: CardInstance = draw_pile.pop_back()
		hand.append(c)
		drawn.append(c)
		# Confused: a card's cost is rolled the moment it's drawn (covers mid-turn
		# draws from card effects, not just the turn-start hand).
		if _is_confused():
			c.temp_cost_override = _rng.randi_range(0, max_energy)
		TriggerBus.emit_signal("card_drawn", {"card": c, "scene": self})
		_fire_power_triggers("card_drawn", {"card": c})
		# Evolve / Fire Breathing listen on the draw's card type. May draw
		# further cards (safe: this loop pops its own count) or kill enemies.
		if c.data != null and c.data.type == CardData.CardType.STATUS:
			_fire_power_triggers("status_drawn", {"card": c})
		if c.data != null and (c.data.type == CardData.CardType.STATUS
				or c.data.type == CardData.CardType.CURSE):
			_fire_power_triggers("status_or_curse_drawn", {"card": c})
		# Card-level `drawn` triggers (Endless Agony: conjure a copy of itself
		# to hand). The conjured copy arrives without being drawn, so it can't
		# cascade — only real draws re-fire this.
		_fire_drawn_triggers(c)
	_check_combat_end()
	_refresh_ui()
	return drawn

# Fires a card's own `drawn` triggers the moment it is drawn (Endless Agony).
# Card-level, like the curse eot/on_play_other triggers — the effects resolve
# with the drawn card as ctx.card so conjure:self copies IT.
func _fire_drawn_triggers(c: CardInstance) -> void:
	if c == null or c.data == null or c.data.triggers.is_empty():
		return
	for trig in c.data.triggers:
		if String(trig.get("on", "")) != "drawn":
			continue
		for eff in trig.get("effects", []):
			if eff is Dictionary:
				EffectSystem.apply(eff, {
					"source": player, "target": player, "scene": self, "card": c,
				})

func discard_card(card: CardInstance, from_play: bool = false) -> void:
	hand.erase(card)
	# "Free this turn" (Mummified Hand / conjure_random's free mint) ends the
	# moment the card leaves hand — without this a played free card would
	# reshuffle back in still costing 0.
	if card != null:
		card.temp_cost_override = -999
	# Sly: a card resolves its effects the moment it would be discarded, then
	# still heads to the discard pile. Skipped when the card is being discarded
	# AS PART OF a normal play (from_play) — it already resolved, so re-firing
	# here would double it.
	if not from_play and card != null and card.data != null and card.data.sly:
		_resolve_sly_on_discard(card)
	# An effect-driven discard (not the played card routing to the pile) is a
	# "Card Discarded this turn" for Eviscerate's discount.
	if not from_play:
		GameState.incremental_on_discard()
	discard_pile.append(card)
	TriggerBus.emit_signal("card_discarded", {"card": card, "scene": self})
	_fire_power_triggers("card_discarded", {"card": card})
	_refresh_ui()

func _resolve_sly_on_discard(card: CardInstance) -> void:
	# Sly: play the card's effects as it leaves hand (end of turn, a discard
	# effect, …). Auto-targets a random live enemy since there's no manual pick
	# on the discard path. No energy cost — it triggers off the discard, not a
	# play. The caller files it into the discard pile afterward.
	if card == null:
		return
	var tgt: CombatActor = null
	var live: Array = []
	for e in enemies:
		if e.is_alive():
			live.append(e)
	if not live.is_empty():
		tgt = live[_rng.randi() % live.size()]
	GameLog.add("%s is Sly — it plays as it's discarded!" % card.get_display_name(),
		Color(0.8, 1.0, 0.8))
	# A Sly resolve isn't a paid play — no energy was spent, so X is 0 here.
	_last_x_value = 0
	_apply_card_effects(card, tgt)
	_check_combat_end()

func exhaust_card(card: CardInstance) -> void:
	hand.erase(card)
	# Free-this-turn override ends as the card leaves hand (see discard_card).
	if card != null:
		card.temp_cost_override = -999
	exhaust_pile.append(card)
	TriggerBus.emit_signal("card_exhausted", {"card": card, "scene": self})
	_fire_power_triggers("card_exhausted", {"card": card})
	_fire_card_exhausted_triggers(card)
	_refresh_ui()

# Fires a card's own `exhausted` triggers the moment IT is exhausted
# (Sentinel: "If this Card is Exhausted, Gain 2 Energy") — the exhaust
# sibling of _fire_drawn_triggers. Reads the upgrade-effective triggers so
# Sentinel+ pays its bigger refund.
func _fire_card_exhausted_triggers(c: CardInstance) -> void:
	if c == null or c.data == null:
		return
	for trig in c.data.get_effective_triggers(c.upgraded):
		if String(trig.get("on", "")) != "exhausted":
			continue
		for eff in trig.get("effects", []):
			if eff is Dictionary:
				EffectSystem.apply(eff, {
					"source": player, "target": player, "scene": self, "card": c,
				})

func conjure_card(card_id: StringName, destination: String, count: int, source_card, force_upgraded: bool = false) -> void:
	# Generic conjure: drop `count` copies of `card_id` into the named
	# pile. `card_id == &"self"` copies the played card (Anger) and
	# preserves its upgrade state — playing an upgraded Anger conjures
	# an upgraded Anger. For any other id we look up the static
	# CardData from `Data` so the same call works for status cards
	# (Dazed, Wound), curses, etc.
	#
	# Upgrade flag for non-self conjures: either pass `force_upgraded`
	# explicitly, or append "+" to the card_id (e.g. `&"shiv+"`).
	# The "+" suffix matches the game's display convention so sheet
	# authors can write `conjure:shiv+:hand:3` and have it Just Work.
	#
	# `destination`: "hand" / "draw" / "discard". An unknown destination
	# logs a warning and is treated as discard so a typo in the sheet
	# doesn't silently swallow the effect. Draw pile additions are
	# shuffled in so the copy isn't deterministically on top.
	var data: CardData = null
	var upgraded := false
	if card_id == &"self":
		if source_card == null or not (source_card is CardInstance):
			return
		data = source_card.data
		upgraded = source_card.upgraded
	else:
		var id_str: String = String(card_id)
		if id_str.ends_with("+"):
			upgraded = true
			id_str = id_str.substr(0, id_str.length() - 1)
		if force_upgraded:
			upgraded = true
		data = Data.get_card(StringName(id_str))
		if data == null:
			push_warning("conjure_card: unknown card id '%s'" % card_id)
			return
		if upgraded and not data.can_upgrade:
			# Asking for an upgraded form of a card that can't upgrade
			# (e.g. status cards) — silently fall back to base form.
			upgraded = false
	for _i in range(count):
		var copy: CardInstance = CardInstance.from_data(data, upgraded)
		match destination:
			"hand":
				hand.append(copy)
			"draw":
				draw_pile.append(copy)
			"discard":
				discard_pile.append(copy)
			_:
				push_warning("conjure_card: unknown destination '%s'" % destination)
				discard_pile.append(copy)
	if destination == "draw":
		_shuffle(draw_pile)
	_refresh_ui()

# Random-mint conjure (White Noise / Infernal Blade / Distraction): mint
# `count` random `card_type` cards from the run's conjure pool — the reward
# pool scoped to the deck picked on the New Run screen (Data.conjure_card_pool)
# — into the named pile. `free` makes a hand conjure cost 0 for THIS turn via
# temp_cost_override, the same slot Mummified Hand uses; it's cleared when the
# card leaves hand (end of turn, play, discard).
func conjure_random_card(card_type: String, destination: String, count: int, free: bool, _source_card) -> void:
	var pool: Array = Data.conjure_card_pool(card_type)
	if pool.is_empty():
		push_warning("conjure_random_card: no %s cards in the conjure pool" % card_type)
		return
	for _i in range(maxi(1, count)):
		var data: CardData = pool[_rng.randi() % pool.size()]
		var copy: CardInstance = CardInstance.from_data(data)
		var made_free: bool = free and destination == "hand"
		if made_free:
			copy.temp_cost_override = 0
		match destination:
			"hand":
				hand.append(copy)
			"draw":
				draw_pile.append(copy)
			_:
				discard_pile.append(copy)
		GameLog.add("Conjured %s%s." % [data.display_name,
			" — it costs 0 this turn" if made_free else ""], Color(0.7, 1.0, 0.7))
	if destination == "draw":
		_shuffle(draw_pile)
	_refresh_ui()

func gain_energy(amount: int) -> void:
	energy += amount
	_refresh_ui()

func lose_energy(amount: int) -> void:
	energy = maxi(0, energy - amount)
	_refresh_ui()

func make_random_hand_card_free(exclude = null) -> void:
	# Mummified Hand: pick a random card in hand (other than the power that
	# just triggered this) whose cost is above 0 and set it to cost 0 for the
	# rest of the turn. Cleared when the card leaves hand (see _on_end_turn).
	var candidates: Array = []
	for c in hand:
		if c == exclude:
			continue
		if c.get_cost() > 0:
			candidates.append(c)
	if candidates.is_empty():
		return
	var pick: CardInstance = candidates[_rng.randi() % candidates.size()]
	pick.temp_cost_override = 0
	GameLog.add("Mummified Hand: %s costs 0 this turn!" % pick.data.display_name,
		Color(0.7, 1.0, 0.7))
	_refresh_ui()

func reduce_random_card_cost(count: int, amount: int, tag: String, type: String) -> void:
	# Empty Tome: at combat start, pick `count` random cards from this fight's
	# deck matching the filter (weapon Attack) and shave `amount` off their cost
	# for the rest of the combat. The discount rides on the CardInstance, so it
	# follows the card through draw/hand/discard and is cleared in _init_deck.
	var pool: Array[CardInstance] = []
	for src in [draw_pile, hand, discard_pile]:
		for c in src:
			if c is CardInstance and c.get_cost() > 0 \
					and ItemTriggers.card_matches(c.data, tag, type) and not pool.has(c):
				pool.append(c)
	if pool.is_empty():
		return
	pool.shuffle()
	for i in mini(count, pool.size()):
		var pick: CardInstance = pool[i]
		pick.combat_cost_delta -= amount
		GameLog.add("Empty Tome: %s costs %d less this combat!" % [pick.data.display_name, amount],
			Color(0.7, 1.0, 0.7))
	_refresh_ui()

# ------------------------------------------------------------------
# Discard / card-boost effect plumbing (deckbuilder)
# ------------------------------------------------------------------

func discard_cards(n: int, source_card = null, random: bool = false) -> void:
	# Two paths: random (All-Out Attack) silently picks; player-choice
	# (Acrobatics et al, the default) opens the CardPickerModal. Both
	# exclude the card being played so a "Deal X. Discard 1." card
	# can't route itself through discard. Silently drops the request
	# when the hand is empty.
	if n <= 0:
		return
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		pool.append(c)
	if pool.is_empty():
		return
	if random:
		var picks: Array = []
		for _i in range(n):
			if pool.is_empty():
				break
			var pick: CardInstance = pool[_rng.randi() % pool.size()]
			pool.erase(pick)
			picks.append(pick)
		_apply_discard_picks(picks)
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Discard %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": _PILE_COLORS["discard"],
			"confirm_label": "Discard",
			"on_picked": Callable(self, "_apply_discard_picks"),
		})

func _apply_discard_picks(picks: Array) -> void:
	for pick in picks:
		discard_card(pick)
		GameLog.add("Discarded %s." % pick.get_display_name(), Color(0.9, 0.7, 0.4))

func exhaust_cards(n: int, source_card = null, random: bool = false) -> void:
	# Mirror of `discard_cards` but routes picks to the exhaust pile.
	# Same exclusion rule for the card being played.
	if n <= 0:
		return
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		pool.append(c)
	if pool.is_empty():
		return
	if random:
		var picks: Array = []
		for _i in range(n):
			if pool.is_empty():
				break
			var pick: CardInstance = pool[_rng.randi() % pool.size()]
			pool.erase(pick)
			picks.append(pick)
		_apply_exhaust_picks(picks)
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Exhaust %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": _PILE_COLORS["exhaust"],
			"confirm_label": "Exhaust",
			"on_picked": Callable(self, "_apply_exhaust_picks"),
		})

func _apply_exhaust_picks(picks: Array) -> void:
	for pick in picks:
		exhaust_card(pick)
		GameLog.add("Exhausted %s." % pick.get_display_name(), Color(0.7, 0.7, 0.8))

func topdeck_cards(n: int, source_card = null, random: bool = false, from_pile: String = "hand", free_until_played: bool = false) -> void:
	# Warcry: put N cards from hand on TOP of the draw pile. Player-choice by
	# default (CardPickerModal); `random` skips the picker. Excludes the played
	# card — it's mid-resolve and heads to discard/exhaust, not the deck.
	# `from_pile: "discard"` (Headbutt) pools the pick from the discard pile
	# instead; the played card can't be picked there either (it's still
	# mid-resolve, not yet in discard).
	# `free_until_played` (Setup): the placed card costs 0 until it is played —
	# the override rides the CardInstance across pile moves and turn ends.
	if n <= 0:
		return
	var pool: Array = []
	for c in (discard_pile if from_pile == "discard" else hand):
		if c == source_card:
			continue
		pool.append(c)
	if pool.is_empty():
		return
	if random:
		var picks: Array = []
		for _i in range(n):
			if pool.is_empty():
				break
			var pick: CardInstance = pool[_rng.randi() % pool.size()]
			pool.erase(pick)
			picks.append(pick)
		_apply_topdeck_picks(picks, free_until_played)
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Put %d card%s on top of your draw pile" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": _PILE_COLORS["draw"],
			"confirm_label": "Place on top",
			"on_picked": _apply_topdeck_picks.bind(free_until_played),
		})

func _apply_topdeck_picks(picks: Array, free_until_played: bool = false) -> void:
	# draw_cards pops from the BACK of draw_pile, so appending puts the pick on
	# top. Multiple picks land in click order: the last appended is drawn first.
	# Picks may come from hand (Warcry) or the discard pile (Headbutt); erase
	# from both — erase on the pile that doesn't hold the card is a no-op.
	for pick in picks:
		hand.erase(pick)
		discard_pile.erase(pick)
		draw_pile.append(pick)
		if free_until_played:
			pick.free_until_played = true
		GameLog.add("Put %s on top of the draw pile%s." % [pick.get_display_name(),
			" — it is free until played" if free_until_played else ""],
			Color(0.6, 1.0, 0.7))
	_refresh_ui()

func discard_hand(source_card = null, only: String = "") -> int:
	# Storm of Steel: discard the entire hand (minus the card being played) and
	# record the count so a following conjure `count_from: "discarded"` can
	# mint one Shiv per card. `only: "non_attack"` (Unload) spares the Attacks.
	# Returns the number discarded.
	var doomed: Array = []
	for c in hand:
		if c == source_card:
			continue
		if only == "non_attack" and c.is_attack():
			continue
		doomed.append(c)
	for c in doomed:
		discard_card(c)
	last_discard_count = doomed.size()
	if last_discard_count > 0:
		GameLog.add("Discarded your hand (%d card%s)." % [
			last_discard_count, "s" if last_discard_count > 1 else ""],
			Color(0.9, 0.7, 0.4))
	return last_discard_count

func exhaust_hand(source_card = null, only: String = "") -> int:
	# Fiend Fire: exhaust the entire hand (minus the card being played) and
	# record the count so a following dmg `hits_from: "exhausted"` can land one
	# hit per card. `only: "non_attack"` (Sever Soul) spares the Attacks.
	# Returns the number exhausted. exhaust_card fires the card_exhausted
	# triggers per card, so Feel No Pain / Dark Embrace react to each one.
	var doomed: Array = []
	for c in hand:
		if c == source_card:
			continue
		if only == "non_attack" and c.is_attack():
			continue
		doomed.append(c)
	for c in doomed:
		exhaust_card(c)
	last_exhaust_count = doomed.size()
	if last_exhaust_count > 0:
		GameLog.add("Exhausted your hand (%d card%s)." % [
			last_exhaust_count, "s" if last_exhaust_count > 1 else ""],
			Color(0.7, 0.7, 0.8))
	return last_exhaust_count

# Havoc: play the top card of the draw pile at no cost, then exhaust it.
# The autoplayed card counts as a played card (card_played / attack_played
# powers react) but pays no energy; attacks land on a random living enemy.
# An X-cost card autoplays with X = 0. A Power registers and is consumed
# (powers are never exhausted); everything else heads to the exhaust pile
# when `exhaust_it` (or its own Exhaust flag) says so.
func autoplay_top_card(exhaust_it: bool, _source_card = null) -> void:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			GameLog.add("Havoc: no cards left to play.", Color(0.85, 0.85, 0.55))
			return
		while not discard_pile.is_empty():
			draw_pile.append(discard_pile.pop_back())
		_shuffle(draw_pile)
	var c: CardInstance = draw_pile.pop_back()
	GameLog.add("Havoc plays %s!" % c.get_display_name(), Color(0.85, 0.7, 1.0))
	TriggerBus.emit_signal("card_played", {"card": c, "target": null, "scene": self})
	_fire_power_triggers("card_played", {"card": c})
	if c.is_attack():
		_fire_power_triggers("attack_played", {"card": c})
	var tgt: CombatActor = null
	if c.wants_target():
		var live: Array = living_enemies()
		if not live.is_empty():
			tgt = live[_rng.randi() % live.size()]
	var prev_x: int = _last_x_value
	_last_x_value = 0
	_apply_card_effects(c, tgt)
	_last_x_value = prev_x
	if c.is_power():
		# Powers are simply used — never exhausted (matches the played route).
		Stats.register_power(player, c.data)
	elif exhaust_it or (c.data != null and c.data.exhaust):
		exhaust_pile.append(c)
		TriggerBus.emit_signal("card_exhausted", {"card": c, "scene": self})
		_fire_power_triggers("card_exhausted", {"card": c})
		_fire_card_exhausted_triggers(c)
	else:
		discard_pile.append(c)
	_refresh_ui()
	_check_combat_end()

# Dual Wield: pick an Attack or Power card in hand, conjure `count` copies of
# it to hand (upgrade state preserved). Player-choice via the picker; the
# count rides on the pending dict so the async confirm knows how many.
var _pending_copy_count: int = 1

func copy_from_hand_cards(count: int, filter: String, source_card = null) -> void:
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		if filter == "attack_or_power" and not (c.is_attack() or c.is_power()):
			continue
		pool.append(c)
	if pool.is_empty():
		GameLog.add("No Attack or Power cards in hand to copy.", Color(0.85, 0.85, 0.55))
		return
	_pending_copy_count = maxi(1, count)
	_open_picker({
		"title": "Choose a card to copy (%d cop%s to hand)" % [
			_pending_copy_count, "ies" if _pending_copy_count > 1 else "y"],
		"candidates": pool,
		"count": 1,
		"accent": Color(0.85, 0.7, 1.0),
		"confirm_label": "Copy",
		"on_picked": Callable(self, "_apply_copy_pick"),
	})

func _apply_copy_pick(picks: Array) -> void:
	for pick in picks:
		if not (pick is CardInstance):
			continue
		for _i in range(_pending_copy_count):
			hand.append(CardInstance.from_data(pick.data, pick.upgraded))
		GameLog.add("Conjured %d cop%s of %s to hand." % [
			_pending_copy_count, "ies" if _pending_copy_count > 1 else "y",
			pick.get_display_name()], Color(0.7, 1.0, 0.7))
	_refresh_ui()

# Exhume: pick a card from the exhaust pile back to hand. Another Exhume
# can't be retrieved (the StS rule — no infinite loop).
func exhume_cards(n: int, source_card = null) -> void:
	var pool: Array = []
	for c in exhaust_pile:
		if c == source_card:
			continue
		if c.data != null and c.data.id == &"exhume":
			continue
		pool.append(c)
	if pool.is_empty():
		GameLog.add("Exhume: nothing to retrieve from the exhaust pile.",
			Color(0.85, 0.85, 0.55))
		return
	var count: int = mini(n, pool.size())
	_open_picker({
		"title": "Exhume %d card%s to your hand" % [count, "s" if count > 1 else ""],
		"candidates": pool,
		"count": count,
		"accent": _PILE_COLORS["exhaust"],
		"confirm_label": "Exhume",
		"on_picked": Callable(self, "_apply_exhume_picks"),
	})

func _apply_exhume_picks(picks: Array) -> void:
	for pick in picks:
		exhaust_pile.erase(pick)
		hand.append(pick)
		GameLog.add("Exhumed %s to hand." % pick.get_display_name(),
			Color(0.7, 1.0, 0.7))
	_refresh_ui()

# Hologram / Seek (retrieve via EffectSystem): move N cards from the named
# pile ("discard" / "draw") to hand, player's choice via the picker — the
# pile-browsing sibling of exhume_cards.
func retrieve_cards(n: int, from_pile: String, source_card = null) -> void:
	var src: Array = discard_pile if from_pile == "discard" else draw_pile
	var pool: Array = []
	for c in src:
		if c == source_card:
			continue
		pool.append(c)
	if pool.is_empty():
		GameLog.add("Nothing to retrieve from the %s pile." % from_pile,
			Color(0.85, 0.85, 0.55))
		return
	var count: int = mini(n, pool.size())
	_open_picker({
		"title": "Put %d card%s from your %s pile into your hand" % [
			count, "s" if count > 1 else "", from_pile],
		"candidates": pool,
		"count": count,
		"accent": _PILE_COLORS["discard" if from_pile == "discard" else "draw"],
		"confirm_label": "Take",
		"on_picked": Callable(self, "_apply_retrieve_picks"),
	})

func _apply_retrieve_picks(picks: Array) -> void:
	for pick in picks:
		discard_pile.erase(pick)
		draw_pile.erase(pick)
		hand.append(pick)
		GameLog.add("Put %s into your hand." % pick.get_display_name(),
			Color(0.7, 1.0, 0.7))
	_refresh_ui()

# Bullet Time (free_hand via EffectSystem): every card currently in hand costs
# 0 for the rest of THIS turn — the whole-hand form of Mummified Hand's free
# pick, riding the same temp_cost_override slot (cleared when a card leaves
# hand, so nothing stays free past the turn).
func make_hand_free(exclude = null) -> void:
	var freed: int = 0
	for c in hand:
		if c == exclude:
			continue
		c.temp_cost_override = 0
		freed += 1
	if freed > 0:
		GameLog.add("Bullet Time: your hand is free to play this turn!",
			Color(0.7, 1.0, 0.7))
	_refresh_ui()

# Nightmare (via EffectSystem): choose a card in hand; at the start of the
# player's NEXT turn, `count` copies of it (upgrade state preserved) arrive in
# hand. The pick is banked scene-side in _nightmare_pending and delivered by
# _deliver_nightmare_copies right after the turn-start draw.
func nightmare_cards(count: int, source_card = null) -> void:
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		pool.append(c)
	if pool.is_empty():
		GameLog.add("Nightmare: no card in hand to copy.", Color(0.85, 0.85, 0.55))
		return
	_open_picker({
		"title": "Nightmare — Conjure %d copies next turn" % count,
		"candidates": pool,
		"count": 1,
		"accent": Color(0.75, 0.6, 1.0),
		"confirm_label": "Choose",
		"on_picked": _apply_nightmare_pick.bind(count),
	})

func _apply_nightmare_pick(picks: Array, count: int) -> void:
	for pick in picks:
		if not (pick is CardInstance) or pick.data == null:
			continue
		_nightmare_pending.append({
			"data": pick.data, "upgraded": pick.upgraded, "count": count,
		})
		GameLog.add("Nightmare: %d copies of %s will arrive next turn." % [
			count, pick.get_display_name()], Color(0.75, 0.6, 1.0))

func _deliver_nightmare_copies() -> void:
	if _nightmare_pending.is_empty():
		return
	var pending: Array = _nightmare_pending.duplicate()
	_nightmare_pending.clear()
	for entry in pending:
		var data: CardData = entry.get("data")
		if data == null:
			continue
		for _i in range(maxi(1, int(entry.get("count", 1)))):
			hand.append(CardInstance.from_data(data, bool(entry.get("upgraded", false))))
		GameLog.add("Nightmare delivers %d copies of %s!" % [
			int(entry.get("count", 1)), data.display_name], Color(0.75, 0.6, 1.0))
	_refresh_ui()

func recall_cards(from_pile: String, to_pile: String, filter: Dictionary) -> void:
	# Move (not copy) cards matching `filter` from `from_pile` to
	# `to_pile`. The only shipped filter today is `{"cost": N}`
	# (All for One). Extend with tag= / type= / id= when a second
	# consumer needs them.
	var src: Array = _pile_for(from_pile)
	if src.is_empty():
		return
	var matched: Array = []
	for inst in src:
		if _filter_matches(inst, filter):
			matched.append(inst)
	if matched.is_empty():
		return
	for inst in matched:
		src.erase(inst)
		match to_pile:
			"hand":
				hand.append(inst)
			"draw":
				draw_pile.append(inst)
			"discard":
				discard_pile.append(inst)
			_:
				push_warning("recall_cards: unknown destination '%s'" % to_pile)
				discard_pile.append(inst)
	if to_pile == "draw":
		_shuffle(draw_pile)
	GameLog.add("Recalled %d card%s from %s." % [
		matched.size(), "s" if matched.size() > 1 else "", from_pile,
	], Color(0.6, 1.0, 0.8))
	_refresh_ui()

func _filter_matches(inst: CardInstance, filter: Dictionary) -> bool:
	if filter == null or filter.is_empty():
		return true
	if filter.has("cost") and inst.get_cost() != int(filter["cost"]):
		return false
	if filter.has("tag") and not inst.data.tags.has(String(filter["tag"])):
		return false
	if filter.has("type") and inst.data.type != int(filter["type"]):
		return false
	if filter.has("id") and inst.data.id != StringName(String(filter["id"])):
		return false
	return true

func upgrade_hand_cards(count_or_all, source_card = null, random: bool = false) -> void:
	# `count_or_all` is an int (pick N) or the string "all" (skip the
	# picker and upgrade everything eligible). Cards with
	# `can_upgrade = false` (Dazed / Wound / status) are filtered out.
	# Already-upgraded cards are also filtered so the player isn't
	# offered no-op picks.
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		# can_take_upgrade folds the can_upgrade / already-upgraded checks and
		# keeps sequential cards (Searing Blow) eligible forever.
		if not (c is CardInstance and c.can_take_upgrade()):
			continue
		pool.append(c)
	if pool.is_empty():
		return
	var all_mode: bool = (typeof(count_or_all) == TYPE_STRING and String(count_or_all).to_lower() == "all")
	if all_mode:
		_apply_upgrade_picks(pool)
		return
	var n: int = int(count_or_all)
	if n <= 0:
		return
	if random:
		var picks: Array = []
		for _i in range(n):
			if pool.is_empty():
				break
			var pick: CardInstance = pool[_rng.randi() % pool.size()]
			pool.erase(pick)
			picks.append(pick)
		_apply_upgrade_picks(picks)
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Upgrade %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": Color(0.6, 0.9, 1.0),
			"confirm_label": "Upgrade",
			"on_picked": Callable(self, "_apply_upgrade_picks"),
		})

func _apply_upgrade_picks(picks: Array) -> void:
	for pick in picks:
		pick.apply_upgrade()
		GameLog.add("Upgraded %s." % pick.get_display_name(), Color(0.6, 0.9, 1.0))
	_refresh_ui()

func _open_picker(opts: Dictionary) -> void:
	# One picker at a time; tear down any pre-existing modal so a
	# chained mid-cast trigger (e.g. Power-armed Discard) can't stack
	# two pickers on top of each other.
	var prev := get_node_or_null("CardPickerModal")
	if prev != null:
		prev.queue_free()
	var modal := CardPickerModal.new()
	modal.name = "CardPickerModal"
	add_child(modal)
	modal.show_picker(opts)

func add_card_boost(boost: Dictionary) -> void:
	card_boosts.append(boost)
	var label: String = _boost_label(boost)
	GameLog.add("Active boost: %s." % label, Color(0.7, 1.0, 0.7))

func register_trigger(on: String, inner_effect: Dictionary, until: String = "") -> void:
	if on == "" or inner_effect.is_empty():
		return
	var entry: Dictionary = {"on": on, "effect": inner_effect}
	# `until: "turn_end"` (Rage / Flame Barrier): the listener expires at the
	# start of the player's NEXT turn (after the enemy turn) — see
	# Stats.expire_turn_triggers in _start_player_turn.
	if until != "":
		entry["until"] = until
	power_triggers.append(entry)
	GameLog.add("Trigger armed on %s%s." % [on,
		" (this turn)" if until == "turn_end" else ""], Color(0.7, 1.0, 0.7))

func _fire_power_triggers(event_name: String, ctx_extras: Dictionary = {}) -> void:
	# Walks the power_triggers list and dispatches every entry whose
	# `on` matches `event_name`. ctx_extras lets the caller pass
	# event-specific bits (the card that was just played, or the victim
	# of the hit for `target`-carrying events like unblocked_attack) into
	# the inner effect's context. The inner effect's target resolves the
	# same way a played card's would: `all_enemies` fans out over the
	# living field (Fire Breathing), `enemy` lands on the event's target
	# (Envenom's poison on the struck foe), anything else is the player.
	if power_triggers.is_empty():
		return
	for trig in power_triggers:
		if String(trig.get("on", "")) != event_name:
			continue
		var inner: Dictionary = trig.get("effect", {})
		if inner.is_empty():
			continue
		var targets: Array = []
		match String(inner.get("target", "self")):
			"all_enemies":
				targets = living_enemies()
			"enemy":
				var t: Variant = ctx_extras.get("target")
				if t != null:
					targets = [t]
			_:
				targets = [player]
		for tgt in targets:
			EffectSystem.apply(inner, {
				"source": player,
				"target": tgt,
				"scene": self,
				"card": ctx_extras.get("card"),
			})

func _boost_label(boost: Dictionary) -> String:
	var who := ""
	if String(boost.get("match_tag", "")) != "":
		who = "tag=%s" % boost.match_tag
	elif String(boost.get("match_type", "")) != "":
		who = "type=%s" % boost.match_type
	elif String(boost.get("match_id", "")) != "":
		who = "id=%s" % boost.match_id
	return "%s %s +%d" % [who, boost.get("stat", "dmg"), int(boost.get("value", 0))]

func _apply_card_boosts(effect: Dictionary, card: CardInstance) -> Dictionary:
	# Returns either the original effect or a copy with the value bumped
	# by every matching active boost. Only `dmg` and `block` effects
	# scale today; cost boosts route through CardInstance.temp_cost_override.
	# The matcher + fold-in math is shared with action/strategy via Stats so
	# all three modes agree on tag/type/id matching.
	if card == null:
		return effect
	return Stats.apply_card_boosts(effect, card.data, card_boosts)

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ------------------------------------------------------------------
# Enemy intent
# ------------------------------------------------------------------

# A hit that drops a splitter to/below half HP mid-turn must overwrite its
# ALREADY-ROLLED intent for the turn that's about to resolve — not wait for
# the next _roll_intent — or the enemy would still telegraph (and execute)
# its old attack this turn and only show Splitting one turn late.
func _maybe_rewrite_split_intent(enemy: CombatActor) -> void:
	if enemy == null or enemy.is_player or enemy.planned_move.get("split", false):
		return
	if Stats.should_split(enemy):
		enemy.planned_move = {"display": "Splitting", "split": true, "effects": [], "intent_type": "buff"}

func _roll_intent(enemy: CombatActor) -> void:
	# Split overrides the normal pattern: a slime at/below half HP telegraphs
	# "Splitting" instead of attacking and spawns its copies when it acts.
	if Stats.should_split(enemy):
		enemy.planned_move = {"display": "Splitting", "split": true, "effects": [], "intent_type": "buff"}
		return
	if enemy.data == null or enemy.data.pattern.is_empty():
		enemy.planned_move = {}
		return
	var pattern: Array = enemy.data.pattern

	# Turn 1 special-case: any move marked first_turn_only wins outright.
	if turn == 1:
		for m in pattern:
			if m.get("first_turn_only", false):
				enemy.planned_move = _annotate_intent(enemy, m)
				return

	# Weighted random selection ignoring first_turn_only moves.
	var pool: Array = []
	var total_weight := 0
	for m in pattern:
		if m.get("first_turn_only", false):
			continue
		var w: int = m.get("weight", 1)
		pool.append({"move": m, "weight": w})
		total_weight += w
	if total_weight <= 0 or pool.is_empty():
		enemy.planned_move = {}
		return
	var roll := _rng.randi_range(1, total_weight)
	var acc := 0
	for entry in pool:
		acc += entry.weight
		if roll <= acc:
			enemy.planned_move = _annotate_intent(enemy, entry.move)
			return
	enemy.planned_move = _annotate_intent(enemy, pool[-1].move)

# Returns a copy of a chosen pattern move tagged with the data EnemyView needs to
# draw an StS-style intent: `intent_type` (attack/defend/debuff/buff/heal) for the
# icon, plus `intent_dmg` / `intent_hits` for attacks so the panel shows the
# damage number instead of the raw move text (e.g. a Louse shows "6", not
# "Bite (5-7)"). Duplicated so the shared pattern data is never mutated; the
# determined roll is resolved here and cached on the enemy so the value shown is
# exactly what the attack deals.
func _annotate_intent(enemy: CombatActor, move: Dictionary) -> Dictionary:
	var m: Dictionary = move.duplicate(true)
	var effects: Array = m.get("effects", [])
	m["intent_type"] = _classify_intent(effects)
	if m["intent_type"] == "attack":
		var per_hit: int = 0
		var hits: int = 0
		for e in effects:
			if e is Dictionary and String(e.get("type", "")) == "dmg":
				per_hit = _predict_intent_damage(enemy, e)
				hits += 1
		if hits > 0:
			m["intent_dmg"] = per_hit
			m["intent_hits"] = hits
	return m

# Buckets a move's effects into one intent category for the icon. Damage wins
# (attack), then block (defend), then a debuff applied to the player, then a
# self-buff / heal. Mirrors the old HTML's getIntentType.
func _classify_intent(effects: Array) -> String:
	var has_block := false
	var has_player_debuff := false
	var has_buff := false
	var has_heal := false
	for e in effects:
		if not (e is Dictionary):
			continue
		match String(e.get("type", "")):
			"dmg":
				return "attack"
			"block", "roll_block":
				has_block = true
			"heal", "gain_hp":
				has_heal = true
			"status":
				var tgt: String = String(e.get("target", "player"))
				if tgt == "player":
					has_player_debuff = true
				else:
					has_buff = true
			"gain_stat", "add_max_hp", "gain_max_hp":
				has_buff = true
	if has_block:
		return "defend"
	if has_player_debuff:
		return "debuff"
	if has_heal:
		return "heal"
	if has_buff:
		return "buff"
	return "unknown"

# Side-effect-free damage preview for the intent number: resolves the move's
# determined roll (cached on the enemy, so it matches the real hit) and the
# per-turn ramp, then hands the fold to the shared Stats.predict_hit —
# Power/Weak on the attacker, Vulnerable/Bruise on the player, and the
# Intangible clamp to 1, exactly like the real hit (StS shows a 1 or 1xN
# intent while Wraith Form is up). _refresh_ui re-predicts, so the number
# drops the moment the power is played and recovers as it decays.
func _predict_intent_damage(enemy: CombatActor, effect: Dictionary) -> int:
	var base: int = int(effect.get("value", 0))
	var det: Variant = effect.get("determined", null)
	if det is Array and (det as Array).size() >= 2:
		var lo: int = int(det[0])
		var hi: int = int(det[1])
		var key: String = String(effect.get("determined_key", "dmg_%d_%d" % [lo, hi]))
		base = Stats.resolve_determined(enemy, key, lo, hi, _rng)
	# Per-turn scaling (Transient): +M for each completed turn, mirroring _h_dmg so
	# the shown intent ramps with the real attack. Folded into the base before Power
	# (which Shifting may have driven negative) so the preview matches the hit.
	var per_turn: int = int(effect.get("per_turn", 0))
	if per_turn != 0 and "turns_taken" in enemy:
		base += per_turn * int(enemy.turns_taken)
	return Stats.predict_hit(enemy, player, base, effect, Stats.Mode.DECKBUILDER)

# ------------------------------------------------------------------
# UI
# ------------------------------------------------------------------

# Lowercase phase name for the turn HUD (preserves the pre-enum label text).
func _phase_label() -> String:
	match phase:
		Phase.INIT: return "init"
		Phase.PLAYER: return "player"
		Phase.ENEMY: return "enemy"
		Phase.WON: return "won"
		Phase.LOST: return "lost"
	return "?"

func _refresh_ui() -> void:
	_turn_label.text = "Turn %d   Phase: %s%s" % [
		turn, _phase_label(),
		"   [TARGETING]" if _targeting else "",
	]
	_energy_label.text = "Energy: %d / %d" % [energy, max_energy]
	_hp_label.text = "HP: %d / %d" % [player.hp if player else 0, player.max_hp if player else 0]
	_block_label.text = "Block: %d" % (player.block if player else 0)
	_draw_btn.text = "Draw: %d" % draw_pile.size()
	_discard_btn.text = "Discard: %d" % discard_pile.size()
	_exhaust_btn.text = "Exhaust: %d" % exhaust_pile.size()

	_refresh_player_view()

	# Re-predict attack intents against the live state so a damaged Transient
	# (Shifting drops its Power on the hit) shows its reduced number immediately,
	# rather than the value rolled at the start of the turn.
	for e in enemies:
		if not e.is_alive() or e.planned_move.is_empty():
			continue
		if String(e.planned_move.get("intent_type", "")) != "attack":
			continue
		for eff in e.planned_move.get("effects", []):
			if eff is Dictionary and String(eff.get("type", "")) == "dmg":
				e.planned_move["intent_dmg"] = _predict_intent_damage(e, eff)
				break

	# Enemies — refresh existing views instead of rebuilding.
	for view in _enemy_views:
		view.refresh()
		view.set_targetable(_targeting)

	# Hand — reconcile views in place instead of freeing and rebuilding the
	# whole row every refresh (which ran on every draw/discard/status tick).
	# Grow or shrink _hand_views to match the hand, then re-point each
	# surviving view at its current card; setup() -> refresh() repaints it.
	while _hand_views.size() < hand.size():
		var view := CardView.new()
		view.play_requested.connect(_try_play_card)
		view.drag_started.connect(_on_card_drag_started)
		# add_child first so _ready builds the child controls before setup().
		_hand_area.add_child(view)
		_hand_views.append(view)
	while _hand_views.size() > hand.size():
		var extra: CardView = _hand_views.pop_back()
		_hand_area.remove_child(extra)
		extra.queue_free()
	var live_enemies: Array = living_enemies()
	for i in range(hand.size()):
		var card_inst: CardInstance = hand[i]
		var view: CardView = _hand_views[i]
		view.setup(card_inst)
		view.set_enabled((phase == Phase.PLAYER) and (_card_cost(card_inst) <= energy))
		view.set_selected(_targeting and _selected_card == card_inst)
		# Conditional-payoff glow (Dropkick): light the card while some living
		# enemy satisfies its if_target gate.
		view.set_condition_active(
			Stats.if_target_gate_live(card_inst.get_effects(), live_enemies))


func _input(event: InputEvent) -> void:
	# Drag-to-play takes priority: while a card is being dragged, follow the
	# cursor and resolve / cancel on release.
	if _drag_card != null:
		if event is InputEventMouseMotion:
			_update_drag(event.global_position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_drag(event.global_position)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_drag()
			# Consume it so the shared PauseMenu doesn't also open on this Esc.
			get_viewport().set_input_as_handled()
		return
	# Right-click or ESC cancels targeting.
	if not _targeting:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_targeting()
		# Consume it so the shared PauseMenu doesn't also open on this Esc.
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_targeting()

# ------------------------------------------------------------------
# Pile viewer overlay (Draw / Discard / Exhaust)
# ------------------------------------------------------------------

const _PILE_TITLES := {
	"draw": "Draw Pile",
	"discard": "Discard Pile",
	"exhaust": "Exhaust Pile",
}
const _PILE_COLORS := {
	"draw": Color(0.40, 0.85, 0.45),
	"discard": Color(0.95, 0.70, 0.30),
	"exhaust": Color(0.65, 0.65, 0.72),
}

func _pile_for(kind: String) -> Array:
	match kind:
		"draw": return draw_pile
		"discard": return discard_pile
		"exhaust": return exhaust_pile
		_: return []

func _on_pile_clicked(kind: String) -> void:
	# Cancel any in-progress targeting so the modal doesn't trap input.
	if _targeting:
		_cancel_targeting()
	_show_pile_overlay(kind)

func _show_pile_overlay(kind: String) -> void:
	# Tear down any existing overlay so re-clicking refreshes the view.
	var prev := get_node_or_null("PileOverlay")
	if prev != null:
		prev.queue_free()

	var pile: Array = _pile_for(kind)
	var sorted_pile: Array = pile.duplicate()
	# Draw pile is shuffled - sort alphabetically so the player can scan
	# without inferring draw order (matches the JS behavior).
	if kind == "draw":
		sorted_pile.sort_custom(func(a, b):
			return a.get_display_name().to_lower() < b.get_display_name().to_lower())

	var overlay := Control.new()
	overlay.name = "PileOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var color: Color = _PILE_COLORS.get(kind, Color.WHITE)
	var title: String = _PILE_TITLES.get(kind, "Pile")

	# Click outside the panel closes the overlay.
	var panel := ModalScaffold.build_panel(overlay, color, func(): overlay.queue_free())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "%s  (%d)" % [title, pile.size()]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", color)
	vbox.add_child(header)

	if kind == "draw":
		var note := Label.new()
		note.text = "(sorted alphabetically — draw order is hidden)"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		vbox.add_child(note)

	if sorted_pile.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(empty)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vbox.add_child(empty_lbl)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(880, 420)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(scroll)

		var grid := HFlowContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)

		for inst in sorted_pile:
			var view := CardView.new()
			grid.add_child(view)
			view.setup(inst)
			# Display-only — never enable play from the pile view.
			view.set_enabled(false)
			view.set_selected(false)

	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(close_row)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 36)
	close_btn.pressed.connect(func(): overlay.queue_free())
	close_row.add_child(close_btn)
