extends Node

# Save system. Two-layer storage:
#   * Numbered slots (slot_<N>.json) — slot AUTOSAVE_SLOT is the run's own
#     recovery point, rewritten by the overworld every time the run's position
#     changes and cleared when the run ends.
#   * Named saves (named/<sanitized>.json) — the player names a run from the
#     overworld's Save button and picks it back up from the menu's Continue list.
#     Each named save also tracks its display name and a last-modified timestamp.
#
# A save carries THREE things, and a resumable run needs all three:
#   1. GameState — the run's identity, vitals, verbs, inventory, and the games it
#      has visited / beaten.
#   2. GameLoop2 — the enemy stack, the destroyed (bashed) games, the attempt
#      tracker, and whether the run is already over.
#   3. The overworld's VIEW — which cards are on the table, which game is in play,
#      what's waiting in the loot tray. Collected from the mounted overworld
#      (capture_view_state) rather than reached into from here.
# Loading applies 1 and 2 immediately; 3 is handed to the overworld if one is
# mounted, and otherwise parked in pending_view_state for the next one to boot
# (which is how the menu's Continue works — load, change scene, restore).

const SAVE_DIR := "user://saves/"
const NAMED_SAVE_DIR := "user://saves/named/"
const NUM_SLOTS := 5
# The slot the run's own recovery point lives in.
const AUTOSAVE_SLOT := 0
# Bumped when the payload shape changes. 1 = the pre-2.0 combat-era shape (no
# games-first loop state); 2 = the games-first run.
const SAVE_VERSION := 2

# The overworld view state of a just-loaded save, waiting for an overworld to boot
# and claim it (see take_pending_view_state). Empty when nothing is pending.
var pending_view_state: Dictionary = {}
var _resume_pending: bool = false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NAMED_SAVE_DIR))

# --- resume handshake ------------------------------------------------------

# True while a loaded save is waiting for an overworld to restore itself from.
func has_pending_resume() -> bool:
	return _resume_pending

# Claim the pending view state, clearing the flag. Returns {} for a save written
# outside the overworld (or a version-1 save), which the overworld treats as "just
# rebuild the offering where the run stands".
func take_pending_view_state() -> Dictionary:
	var view: Dictionary = pending_view_state
	pending_view_state = {}
	_resume_pending = false
	return view

# Drop a parked resume without consuming it — what starting a FRESH run does, so
# a load the player then backed out of can't hijack the new run's boot.
func cancel_pending_resume() -> void:
	pending_view_state = {}
	_resume_pending = false

# --- the autosave slot -----------------------------------------------------

func autosave() -> bool:
	return save(AUTOSAVE_SLOT)

func has_autosave() -> bool:
	return has_save(AUTOSAVE_SLOT)

func clear_autosave() -> void:
	delete_slot(AUTOSAVE_SLOT)

func load_autosave() -> bool:
	return load_slot(AUTOSAVE_SLOT)

func slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

func list_slots() -> Array:
	var out: Array = []
	for i in range(NUM_SLOTS):
		out.append({
			"slot": i,
			"exists": has_save(i),
			"summary": _peek(i) if has_save(i) else {},
		})
	return out

func _peek(slot: int) -> Dictionary:
	var data := _read(slot)
	if data.is_empty():
		return {}
	return _summary(data, String(data.get("save_name", "")), slot)

# One save's headline, shared by the slot list, the named list, and the Continue
# list so all three describe a run the same way. `slot` is -1 for a named save.
func _summary(data: Dictionary, display_name: String, slot: int = -1) -> Dictionary:
	return {
		"name": display_name,
		"slot": slot,
		"autosave": slot == AUTOSAVE_SLOT,
		"character_id": String(data.get("character_id", "")),
		"current_game": String(data.get("current_game_id", "")),
		"hp": int(data.get("hp", 0)),
		"max_hp": int(data.get("max_hp", 0)),
		"gold": int(data.get("gold", 0)),
		"games_beaten": int(data.get("total_games_beaten", 0)),
		"games_played": int(data.get("games_played", 0)),
		"saved_at": int(data.get("saved_at", 0)),
		"version": int(data.get("save_version", 1)),
	}

# The Continue list: the run's own recovery point first (it's the most recent
# thing that happened by definition), then every named save, newest first. A
# version-1 save (the pre-2.0 combat era) is skipped — it has no games-first run
# in it to resume.
func list_resumable() -> Array:
	var out: Array = []
	if has_autosave():
		var auto_data := _read(AUTOSAVE_SLOT)
		if not auto_data.is_empty() and int(auto_data.get("save_version", 1)) >= 2:
			out.append(_summary(auto_data, "Autosave", AUTOSAVE_SLOT))
	for entry in list_named():
		if int(entry.get("version", 1)) >= 2:
			out.append(entry)
	return out

func save(slot: int) -> bool:
	var path := slot_path(slot)
	return _write_save(path)

func _build_payload() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"save_name": GameState.save_name,
		"saved_at": Time.get_unix_time_from_system(),
		"character_id": String(GameState.character_id),
		"selected_deck": String(GameState.selected_deck),
		"current_game_id": String(GameState.current_game_id),
		"start_game_id": String(GameState.start_game_id),
		"amulet_game_id": String(GameState.amulet_game_id),
		"visited_games": _stringnames_to_strings(GameState.visited_games),
		"beaten_games": _stringnames_to_strings(GameState.beaten_games),
		"total_games_beaten": GameState.total_games_beaten,
		"games_played": GameState.games_played,
		"player_level": GameState.player_level,
		# Save the BASE vitals (without item contribution). The item
		# bonuses are re-applied on load through _recompute_item_bonuses,
		# which would otherwise double-count whatever max_hp/max_energy
		# items grant. Jelly's scaling contribution is tracked separately
		# (_applied_scaling_max_hp) and must be subtracted too.
		"max_hp": GameState.max_hp - GameState._applied_item_max_hp - GameState._applied_scaling_max_hp,
		"hp": GameState.hp,
		"max_energy": GameState.max_energy - GameState._applied_item_max_energy,
		"hand_size": GameState.hand_size,
		"strength": GameState.strength,
		"dexterity": GameState.dexterity,
		"intelligence": GameState.intelligence,
		"charisma": GameState.charisma,
		"constitution": GameState.constitution,
		"luck": GameState.luck,
		"speed": GameState.speed,
		"harvesting": GameState.harvesting,
		"crit_chance": GameState.crit_chance,
		"crit_damage": GameState.crit_damage,
		"regeneration": GameState.regeneration,
		"gold": GameState.gold,
		# Per-slot entries preserve upgrade_level so two copies of the
		# same item keep their independent state across save/load.
		# inventory_ids kept for legacy reads.
		"inventory": _serialize_inventory(GameState.inventory),
		"inventory_ids": _item_ids(GameState.inventory),
		"equipped_weapon_id": String(GameState.equipped_weapon.id) if GameState.equipped_weapon != null else "",
		"equipped_weapon_level": GameState.equipped_weapon.upgrade_level if GameState.equipped_weapon != null else 0,
		"equipped_weapon_instance_id": GameState.equipped_weapon.instance_id if GameState.equipped_weapon != null else 0,
		"equipped_weapon_lvl": GameState.equipped_weapon.weapon_level if GameState.equipped_weapon != null else 1,
		# Persist the id counter so newly-added items after a load don't
		# collide with weapon instance_ids on cards still in the deck.
		"next_item_instance_id": GameState._next_item_instance_id,
		# Run-wide Attack tally for incremental items (Nunchaku / Pen Nib);
		# per-turn / per-combat counters are combat-scoped and not saved.
		"incremental_attacks_total": GameState.incremental_attacks_total,
		"dash": GameState.dash_charges,
		"reroll": GameState.reroll_charges,
		"fov_bonus": GameState.fov_bonus,
		"discovery": GameState.discovery,
		# Rock Bottom's per-stat high-water marks. Floor itself is rebuilt from
		# inventory on load; the peaks must survive so they aren't lost.
		"stat_high_water": GameState.stat_high_water.duplicate(),
		"action_left_card_id": String(GameState.action_left_card_id),
		"action_right_card_id": String(GameState.action_right_card_id),
		"action_active_item_id": String(GameState.action_active_item_id),
		"action_charged_item_id": String(GameState.action_charged_item_id),
		# Loot (potions): concrete carried entries + global per-type identification
		# + this run's mystery-bottle colour assignment.
		"loot_items": GameState.loot_items.duplicate(true),
		"identified_potion_types": _stringnames_to_strings(GameState.identified_potion_types),
		"identified_scroll_types": _stringnames_to_strings(GameState.identified_scroll_types),
		"potion_color_map": GameState.potion_color_map.duplicate(),
		"loot_keys": int(GameState.loot.get("key", 0)),
		# === games-first (2.0) run state ===
		# The board verbs and the per-game shields are stored WITHOUT the bonus
		# owned items contribute (base_verb_value), exactly like max_hp above: the
		# load restores the base and _recompute_item_bonuses re-applies the item
		# half, so a passive (+1 Bash) can't compound across save/load cycles.
		"shields": GameState.base_verb_value("shields"),
		"bash": GameState.base_verb_value("bash"),
		"push": GameState.base_verb_value("push"),
		"transmute": GameState.base_verb_value("transmute"),
		"scramble": GameState.base_verb_value("scramble"),
		"bombs": GameState.base_verb_value("bombs"),
		"keys": GameState.base_verb_value("keys"),
		"game_choice_bonus": GameState.base_verb_value("game_choices"),
		"pending_chests": GameState.pending_chests,
		"pending_chest_choices": Array(GameState.pending_chest_choices),
		"total_combats_completed": GameState.total_combats_completed,
		# The enemy stack, the destroyed games, the attempt tracker.
		"loop": GameLoop2.serialize(),
		# What the overworld has on screen, when one is mounted to ask.
		"overworld": _capture_view_state(),
	}

# The mounted overworld's view of the run, or {} when the save is taken from
# somewhere else (the menu, a test). Guarded on the method so any future screen
# that registers as the overworld context isn't required to implement it.
func _capture_view_state() -> Dictionary:
	var ow = GameState.overworld_scene
	if ow == null or not is_instance_valid(ow) or not ow.has_method("capture_view_state"):
		return {}
	return ow.capture_view_state()

func _write_save(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveSystem] could not open '%s' for write" % path)
		return false
	f.store_string(JSON.stringify(_build_payload(), "  "))
	# Closed explicitly rather than on scope exit: the Continue list re-reads a
	# save the same frame it was written (the autosave), and that read must see the
	# whole file.
	f.close()
	return true

func load_slot(slot: int) -> bool:
	var data := _read(slot)
	if data.is_empty():
		return false
	_apply_save_data(data)
	return true

func _apply_save_data(data: Dictionary) -> void:
	GameState.reset_run()
	GameState.save_name = String(data.get("save_name", ""))
	GameState.character_id = StringName(data.get("character_id", ""))
	GameState.selected_deck = StringName(data.get("selected_deck", ""))
	GameState.current_game_id = StringName(data.get("current_game_id", ""))
	GameState.start_game_id = StringName(data.get("start_game_id", ""))
	GameState.amulet_game_id = StringName(data.get("amulet_game_id", ""))
	GameState.visited_games = _strings_to_stringnames(data.get("visited_games", []))
	GameState.beaten_games = _strings_to_stringnames(data.get("beaten_games", []))
	GameState.total_games_beaten = data.get("total_games_beaten", 0)
	GameState.games_played = data.get("games_played", 0)
	GameState.player_level = data.get("player_level", 1)
	GameState.max_hp = data.get("max_hp", 75)
	GameState.hp = data.get("hp", GameState.max_hp)
	GameState.max_energy = data.get("max_energy", 3)
	GameState.hand_size = data.get("hand_size", 5)
	GameState.strength = data.get("strength", 0)
	GameState.dexterity = data.get("dexterity", 0)
	GameState.intelligence = data.get("intelligence", 0)
	GameState.charisma = data.get("charisma", 0)
	GameState.constitution = data.get("constitution", 0)
	GameState.luck = data.get("luck", 0)
	GameState.speed = data.get("speed", 0)
	GameState.harvesting = data.get("harvesting", 0)
	GameState.crit_chance = data.get("crit_chance", 0)
	GameState.crit_damage = data.get("crit_damage", 100)
	GameState.regeneration = data.get("regeneration", 0)
	GameState.gold = data.get("gold", 0)
	GameState.incremental_attacks_total = int(data.get("incremental_attacks_total", 0))
	# Prefer the new per-slot inventory; fall back to legacy id list.
	if data.has("inventory"):
		GameState.inventory = _resolve_inventory(data.get("inventory", []))
	else:
		GameState.inventory = _resolve_items(data.get("inventory_ids", []))
	var weapon_id := String(data.get("equipped_weapon_id", ""))
	if weapon_id != "":
		var w_tpl: ItemData = _lookup_item(StringName(weapon_id))
		if w_tpl != null:
			GameState.equipped_weapon = w_tpl.duplicate(true)
			GameState.equipped_weapon.upgrade_level = int(data.get("equipped_weapon_level", 0))
			GameState.equipped_weapon.instance_id = int(data.get("equipped_weapon_instance_id", 0))
			GameState.equipped_weapon.weapon_level = int(data.get("equipped_weapon_lvl", 1))
		else:
			GameState.equipped_weapon = null
	else:
		GameState.equipped_weapon = null
	# Restore the item instance-id counter.
	GameState._next_item_instance_id = maxi(1, int(data.get("next_item_instance_id", 1)))
	# The BASE run verbs go in before the recompute below, which is what re-applies
	# the item half on top of them (Vajra's +1 Bash). Setting them afterwards would
	# either wipe the item contribution or bake it in twice, depending on the verb.
	GameState.dash_charges = int(data.get("dash", 0))
	GameState.shields = int(data.get("shields", 0))
	GameState.bash = int(data.get("bash", 0))
	GameState.push = int(data.get("push", 0))
	GameState.transmute = int(data.get("transmute", 0))
	GameState.scramble = int(data.get("scramble", 0))
	GameState.bombs = int(data.get("bombs", 0))
	GameState.keys = int(data.get("keys", 0))
	GameState.game_choice_bonus = int(data.get("game_choice_bonus", 0))
	# Reset the running item contribution so _recompute starts fresh
	# against the saved base stats (which already had bonuses applied
	# when the save was written, but we save the base — see below).
	GameState._applied_item_max_hp = 0
	GameState._applied_item_max_energy = 0
	GameState._applied_scaling_max_hp = 0
	GameState._applied_item_verbs = {}
	GameState.item_stat_bonus = {}
	GameState._recompute_item_bonuses()
	GameState.reroll_charges = data.get("reroll", 0)
	GameState.fov_bonus = data.get("fov_bonus", 0)
	GameState.discovery = data.get("discovery", 0)
	# Restore Rock Bottom's high-water marks after the floor set is rebuilt
	# above by _recompute_item_bonuses. Coerce keys/values to String/int so a
	# JSON-decoded dict slots straight into the live read path.
	GameState.stat_high_water = {}
	var hw_saved: Dictionary = data.get("stat_high_water", {})
	for k in hw_saved.keys():
		GameState.stat_high_water[String(k)] = int(hw_saved[k])
	GameState.action_left_card_id = StringName(data.get("action_left_card_id", ""))
	GameState.action_right_card_id = StringName(data.get("action_right_card_id", ""))
	GameState.action_active_item_id = StringName(data.get("action_active_item_id", ""))
	GameState.action_charged_item_id = StringName(data.get("action_charged_item_id", ""))
	# Loot: rehydrate carried potion/scroll entries (coercing the JSON string
	# ids back to StringName), the global identification set, and the run's
	# mystery-bottle colour map.
	GameState.loot_items.clear()
	for entry in data.get("loot_items", []):
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry.duplicate()
		if e.has("id"):
			e["id"] = StringName(e["id"])
		GameState.loot_items.append(e)
	var ident: Array[StringName] = []
	for s in data.get("identified_potion_types", []):
		ident.append(StringName(s))
	GameState.identified_potion_types = ident
	var sident: Array[StringName] = []
	for s in data.get("identified_scroll_types", []):
		sident.append(StringName(s))
	GameState.identified_scroll_types = sident
	GameState.potion_color_map = {}
	var cm: Dictionary = data.get("potion_color_map", {})
	for k in cm.keys():
		GameState.potion_color_map[String(k)] = String(cm[k])
	GameState.loot["key"] = int(data.get("loot_keys", 0))
	GameState.pending_chests = int(data.get("pending_chests", 0))
	GameState.pending_chest_choices.clear()
	for n in data.get("pending_chest_choices", []):
		GameState.pending_chest_choices.append(int(n))
	GameState.total_combats_completed = int(data.get("total_combats_completed", 0))
	GameState.phase = GameState.Phase.OVERWORLD
	# The games-first enemy stack, destroyed games and attempt tracker. Order-free
	# against the GameState half above: the loop reads GameState.shields when it
	# RESOLVES a game, never while restoring itself.
	GameLoop2.restore(data.get("loop", {}))
	GameState.emit_signal("hp_changed", GameState.hp, GameState.max_hp)
	GameState.emit_signal("gold_changed", GameState.gold)
	GameState.emit_signal("stats_changed")
	GameState.emit_signal("deck_changed")
	GameState.emit_signal("inventory_changed")
	GameState.emit_signal("current_game_changed", GameState.current_game_id)
	# The overworld's own view. A live overworld takes it now (an in-run reload);
	# otherwise it waits for the next one to boot, which is how the menu's Continue
	# hands a run to a freshly-loaded Overworld2 scene.
	var view: Dictionary = data.get("overworld", {})
	var ow = GameState.overworld_scene
	if ow != null and is_instance_valid(ow) and ow.has_method("resume_run"):
		pending_view_state = {}
		_resume_pending = false
		ow.resume_run(view)
	else:
		pending_view_state = view
		_resume_pending = true

func _read(slot: int) -> Dictionary:
	return _read_path(slot_path(slot))

func delete_slot(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))

# ---------------------------------------------------------------------------
# Named saves — used by the HTML-parity Continue list. The on-disk
# filename is a sanitized version of the display name; the original
# display name is stored inside the payload (`save_name`) so list_named()
# can render it as the player typed it.
# ---------------------------------------------------------------------------

func _sanitize_save_name(save_name: String) -> String:
	var s := save_name.strip_edges().to_lower()
	var out := ""
	for i in s.length():
		var c := s[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
	if out == "":
		out = "save"
	return out

func named_save_path(save_name: String) -> String:
	return NAMED_SAVE_DIR + _sanitize_save_name(save_name) + ".json"

func has_named_save(save_name: String) -> bool:
	return FileAccess.file_exists(named_save_path(save_name))

func save_named(save_name: String) -> bool:
	GameState.save_name = save_name
	return _write_save(named_save_path(save_name))

func load_named(save_name: String) -> bool:
	var data := _read_path(named_save_path(save_name))
	if data.is_empty():
		return false
	_apply_save_data(data)
	return true

func delete_named(save_name: String) -> void:
	var path := named_save_path(save_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# Returns a sorted-by-recency list of {name, character_id, current_game,
# hp, gold, games_beaten, saved_at}. Empty list if no named saves yet.
func list_named() -> Array:
	var out: Array = []
	var dir := DirAccess.open(NAMED_SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var data := _read_path(NAMED_SAVE_DIR + fname)
			if not data.is_empty():
				out.append(_summary(data, String(data.get("save_name", fname.get_basename()))))
		fname = dir.get_next()
	out.sort_custom(func(a, b): return int(a["saved_at"]) > int(b["saved_at"]))
	return out

func clear_all_saves() -> void:
	for i in range(NUM_SLOTS):
		delete_slot(i)
	var dir := DirAccess.open(NAMED_SAVE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(NAMED_SAVE_DIR + fname))
		fname = dir.get_next()

func _read_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data

# ---------------------------------------------------------------------------

func _stringnames_to_strings(arr: Array) -> Array:
	var out: Array = []
	for s in arr:
		out.append(String(s))
	return out

func _strings_to_stringnames(arr: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for s in arr:
		out.append(StringName(s))
	return out

func _item_ids(inv: Array) -> Array:
	var out: Array = []
	for it in inv:
		if it is ItemData:
			out.append(String(it.id))
	return out

# Resolve a saved item id against the 2.0 pool first (the run's item economy),
# then the legacy 1.0 pool, so either round-trips.
func _lookup_item(id: StringName) -> ItemData:
	var it: ItemData = Data.get_item2(id)
	return it if it != null else Data.get_item(id)

func _resolve_items(ids: Array) -> Array:
	# Legacy id-list path. Each entry becomes a fresh duplicate at
	# upgrade_level 0 so the per-slot contract still holds when loading
	# pre-upgrade saves.
	var out: Array = []
	for s in ids:
		var it: ItemData = _lookup_item(StringName(s))
		if it != null:
			out.append(it.duplicate(true))
	return out

func _serialize_inventory(inv: Array) -> Array:
	# Per-slot save: {id, upgrade_level, instance_id, weapon_level}.
	# instance_id is the pairing key for CardInstance.source_weapon_id;
	# both must round-trip together for weapon coupling to survive load.
	var out: Array = []
	for it in inv:
		if it is ItemData:
			out.append({
				"id": String(it.id),
				"upgrade_level": it.upgrade_level,
				"instance_id": it.instance_id,
				"weapon_level": it.weapon_level,
				"current_charge": it.current_charge,
			})
	return out

func _resolve_inventory(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		if not (e is Dictionary):
			continue
		var tpl: ItemData = _lookup_item(StringName(e.get("id", "")))
		if tpl == null:
			continue
		var inst: ItemData = tpl.duplicate(true)
		inst.upgrade_level = int(e.get("upgrade_level", 0))
		inst.instance_id = int(e.get("instance_id", 0))
		inst.weapon_level = int(e.get("weapon_level", 1))
		# Charged actives: restore the bar (default to full for legacy saves).
		if inst.is_charged():
			inst.current_charge = int(e.get("current_charge",
				inst.max_charge() if inst.starts_charged else 0))
		out.append(inst)
	return out
