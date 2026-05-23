extends Node

# Multi-slot save system. Slots live in user://saves/slot_<N>.json.
# Phase 1a: just enough to round-trip GameState. Will grow as more
# state is added.

const SAVE_DIR := "user://saves/"
const NUM_SLOTS := 5

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))

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
			"summary": _peek(i) if has_save(i) else null,
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
	var payload := {
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
		"luck": GameState.luck,
		"gold": GameState.gold,
		# Deck stores per-card upgrade state; inventory stores ids.
		"deck": _serialize_deck(GameState.deck),
		"inventory_ids": _item_ids(GameState.inventory),
		"equipped_weapon_id": String(GameState.equipped_weapon.id) if GameState.equipped_weapon != null else "",
		"dash": GameState.dash_charges,
		"reroll": GameState.reroll_charges,
		"skip": GameState.skip_charges,
		"fov_bonus": GameState.fov_bonus,
		"discovery": GameState.discovery,
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("[SaveSystem] could not open slot %d for write" % slot)
		return false
	f.store_string(JSON.stringify(payload, "  "))
	return true

func load_slot(slot: int) -> bool:
	var data := _read(slot)
	if data.is_empty():
		return false
	GameState.reset_run()
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
	GameState.luck = data.get("luck", 0)
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
	GameState.skip_charges = data.get("skip", 0)
	GameState.fov_bonus = data.get("fov_bonus", 0)
	GameState.discovery = data.get("discovery", 0)
	return true

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
