extends Node

# Save system. Two-layer storage:
#   * Numbered slots (slot_<N>.json) — retained for the autosave path
#     used by Overworld during a run and by quick F5/F9 save/load.
#   * Named saves (named/<sanitized>.json) — the HTML-parity flow where
#     the player names their run on New Game and picks it from the
#     Continue list. Each named save also tracks its display name and
#     a last-modified timestamp.
#
# Phase 1a: just enough to round-trip GameState. Will grow as more
# state is added.

const SAVE_DIR := "user://saves/"
const NAMED_SAVE_DIR := "user://saves/named/"
const NUM_SLOTS := 5

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NAMED_SAVE_DIR))

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
	return {
		"character_id": data.get("character_id", ""),
		"current_game": data.get("current_game_id", ""),
		"hp": data.get("hp", 0),
		"gold": data.get("gold", 0),
		"games_beaten": data.get("total_games_beaten", 0),
	}

func save(slot: int) -> bool:
	var path := slot_path(slot)
	return _write_save(path)

func _build_payload() -> Dictionary:
	return {
		"save_name": GameState.save_name,
		"saved_at": Time.get_unix_time_from_system(),
		"character_id": String(GameState.character_id),
		"current_game_id": String(GameState.current_game_id),
		"start_game_id": String(GameState.start_game_id),
		"amulet_game_id": String(GameState.amulet_game_id),
		"visited_games": _stringnames_to_strings(GameState.visited_games),
		"beaten_games": _stringnames_to_strings(GameState.beaten_games),
		"total_games_beaten": GameState.total_games_beaten,
		"max_hp": GameState.max_hp,
		"hp": GameState.hp,
		"max_energy": GameState.max_energy,
		"hand_size": GameState.hand_size,
		"strength": GameState.strength,
		"dexterity": GameState.dexterity,
		"intelligence": GameState.intelligence,
		"charisma": GameState.charisma,
		"constitution": GameState.constitution,
		"luck": GameState.luck,
		"speed": GameState.speed,
		"gold": GameState.gold,
		# Deck stores per-card upgrade state; inventory stores ids.
		"deck": _serialize_deck(GameState.deck),
		"inventory_ids": _item_ids(GameState.inventory),
		"equipped_weapon_id": String(GameState.equipped_weapon.id) if GameState.equipped_weapon != null else "",
		"dash": GameState.dash_charges,
		"reroll": GameState.reroll_charges,
		"fov_bonus": GameState.fov_bonus,
		"discovery": GameState.discovery,
		"action_basic_attack_id": String(GameState.action_basic_attack_id),
		"action_ability_ids": _stringnames_to_strings(GameState.action_ability_ids),
	}

func _write_save(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveSystem] could not open '%s' for write" % path)
		return false
	f.store_string(JSON.stringify(_build_payload(), "  "))
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
	GameState.current_game_id = StringName(data.get("current_game_id", ""))
	GameState.start_game_id = StringName(data.get("start_game_id", ""))
	GameState.amulet_game_id = StringName(data.get("amulet_game_id", ""))
	GameState.visited_games = _strings_to_stringnames(data.get("visited_games", []))
	GameState.beaten_games = _strings_to_stringnames(data.get("beaten_games", []))
	GameState.total_games_beaten = data.get("total_games_beaten", 0)
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
	GameState.gold = data.get("gold", 0)
	# Prefer the new "deck" key; fall back to legacy "deck_ids" for old saves.
	if data.has("deck"):
		GameState.deck = _resolve_deck(data.get("deck", []))
	else:
		GameState.deck = _resolve_deck_legacy(data.get("deck_ids", []))
	GameState.inventory = _resolve_items(data.get("inventory_ids", []))
	var weapon_id := String(data.get("equipped_weapon_id", ""))
	GameState.equipped_weapon = Data.get_item(StringName(weapon_id)) if weapon_id != "" else null
	GameState.dash_charges = data.get("dash", 0)
	GameState.reroll_charges = data.get("reroll", 0)
	GameState.fov_bonus = data.get("fov_bonus", 0)
	GameState.discovery = data.get("discovery", 0)
	GameState.action_basic_attack_id = StringName(data.get("action_basic_attack_id", ""))
	GameState.action_ability_ids = _strings_to_stringnames(data.get("action_ability_ids", []))
	# Broadcast a full sweep so HUDs / overlays subscribed to GameState
	# pick up the new state after a load.
	GameState.emit_signal("hp_changed", GameState.hp, GameState.max_hp)
	GameState.emit_signal("gold_changed", GameState.gold)
	GameState.emit_signal("stats_changed")
	GameState.emit_signal("deck_changed")
	GameState.emit_signal("inventory_changed")
	GameState.emit_signal("current_game_changed", GameState.current_game_id)

func _read(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	if err != OK:
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data

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
				out.append({
					"name": String(data.get("save_name", fname.get_basename())),
					"character_id": String(data.get("character_id", "")),
					"current_game": String(data.get("current_game_id", "")),
					"hp": int(data.get("hp", 0)),
					"max_hp": int(data.get("max_hp", 0)),
					"gold": int(data.get("gold", 0)),
					"games_beaten": int(data.get("total_games_beaten", 0)),
					"saved_at": int(data.get("saved_at", 0)),
				})
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

func _serialize_deck(deck: Array) -> Array:
	var out: Array = []
	for c in deck:
		if c is CardInstance:
			out.append({"id": String(c.data.id), "upgraded": c.upgraded})
		elif c is CardData:
			# Defensive: handle bare CardData if anything still appends it.
			out.append({"id": String(c.id), "upgraded": false})
	return out

func _resolve_deck(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		if not (e is Dictionary):
			continue
		var c: CardData = Data.get_card(StringName(e.get("id", "")))
		if c == null:
			continue
		out.append(CardInstance.from_data(c, bool(e.get("upgraded", false))))
	return out

func _resolve_deck_legacy(ids: Array) -> Array:
	var out: Array = []
	for s in ids:
		var c: CardData = Data.get_card(StringName(s))
		if c != null:
			out.append(CardInstance.from_data(c))
	return out

func _resolve_items(ids: Array) -> Array:
	var out: Array = []
	for s in ids:
		var it: ItemData = Data.get_item(StringName(s))
		if it != null:
			out.append(it)
	return out
