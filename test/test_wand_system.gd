extends GutTest

# Tests for the games-first (2.0) WandSystem (docs/wands-design.md): the roster,
# the material alphabet, the charge economy, the five-way loot split, and every op
# the sheet authors.
#
# WHAT THIS FILE IS REALLY ABOUT IS CHARGES, because that is the whole of what the
# fifth kind adds. Four kinds are spent once and leave; a wand spends one of six
# and stays, which touches the pack (LootSystem.use_loot), the relic that copies
# loot (Echo Chamber), and the pill that fills bars (48 Hour Energy). Each of those
# seams has a test here rather than only in the file that owns the other side.
#
# Nothing here drives the overworld. Wand of Wishing resolves as a REQUEST —
# `zap_wand` hands one back and is finished — so what this asserts about it is the
# shape of the request, which is the whole of the contract on this side of the
# seam. `test_overworld2.gd` owns the other side.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	return r

# A carried wand, FULL, exactly as a drop would hand it over.
func _entry(id: StringName) -> Dictionary:
	var w: WandData = Data.get_wand(id)
	assert_not_null(w, "wand '%s' is in the catalog" % id)
	if w == null:
		return {}
	return {"type": "wand", "id": id, "rarity": w.rarity,
		"charges": w.starting_charges()}

# --- The roster ------------------------------------------------------------

func test_every_wand_loads_with_a_charge_count_and_a_target_mode() -> void:
	var wands: Array = Data.all_wands()
	assert_eq(wands.size(), 4, "the sheet's 4 rows all generated")
	for w in wands:
		assert_true(w is WandData)
		var wand: WandData = w
		assert_ne(wand.display_name, "", "%s has a name" % wand.id)
		assert_ne(wand.description, "", "%s prints what it does" % wand.id)
		assert_gt(wand.starting_charges(), 0, "%s can be zapped" % wand.id)
		assert_true(wand.targeting in ["ray", "non_directional", "random"],
			"%s's Type is one of the three (%s)" % [wand.id, wand.targeting])
		for op in wand.effect:
			assert_true(op is Dictionary and String(op.get("op", "")) != "",
				"%s's ops are all named" % wand.id)

# THE ONE AUTHORED BLANK, and the reason the generator refuses every other one:
# Wand of Nothing writes `nothing` in its Effect cell, so an empty effect list is
# content here and a hole anywhere else (see generate_wand2_tres.parse_effect).
func test_only_the_wand_of_nothing_does_nothing() -> void:
	for w in Data.all_wands():
		var wand: WandData = w
		if wand.id == &"wand_of_nothing":
			assert_true(wand.effect.is_empty(), "the roster's joke is authored empty")
		else:
			assert_false(wand.effect.is_empty(), "%s does something" % wand.id)

func test_the_roster_covers_every_rung_of_the_ladder() -> void:
	var rungs: Dictionary = {}
	for w in Data.all_wands():
		rungs[(w as WandData).rarity_index()] = true
	assert_eq(rungs.size(), 4,
		"one wand per rarity — the ladder is what spreads the roster, not a weight")

# --- The material alphabet (§6) --------------------------------------------

# BOTH DIRECTIONS, which is the check test_pill_system.gd does not get: a file on
# disk that the const list has never heard of is art no run can ever show.
func test_the_material_list_matches_the_folder_in_both_directions() -> void:
	var dir := DirAccess.open("res://images2.0/wands_unidentified/")
	assert_not_null(dir, "the unidentified-wand folder is there")
	if dir == null:
		return
	var on_disk: Array = []
	for f in dir.get_files():
		if f.ends_with(".png"):
			on_disk.append(f.substr(0, f.length() - 4))
	on_disk.sort()
	var listed: Array = WandSystem.MATERIALS.duplicate()
	listed.sort()
	assert_eq(listed, on_disk,
		"WandSystem.MATERIALS is exactly the folder — art that is not listed is art "
		+ "no run can deal, and a listing with no file is one broken texture")

func test_a_run_deals_every_wand_a_distinct_material_and_leaves_the_rest_spare() -> void:
	WandSystem.ensure_materials()
	var dealt: Array = []
	for w in Data.all_wands():
		var base: String = WandSystem.material_for((w as WandData).id)
		assert_ne(base, "", "%s wears something" % (w as WandData).id)
		assert_false(dealt.has(base), "no two wands wear the same stick")
		dealt.append(base)
	# THE FACT THE WHOLE IDENTIFICATION DESIGN RESTS ON, asserted rather than
	# trusted to arithmetic: 24 spares over 4 wands means knowing three tells you
	# nothing about the fourth.
	assert_eq(WandSystem.unused_materials().size(),
		WandSystem.MATERIALS.size() - Data.all_wands().size(),
		"every material the run did not deal is spare")
	assert_gt(WandSystem.unused_materials().size(), Data.all_wands().size(),
		"more spares than wands, which is what makes the last one undeducible")

func test_the_deal_survives_being_asked_twice() -> void:
	WandSystem.ensure_materials()
	var first: Dictionary = GameState.wand_material_map.duplicate()
	WandSystem.ensure_materials()
	assert_eq(GameState.wand_material_map, first,
		"idempotent — a reloaded run must keep the alphabet it has been learning")

func test_a_material_reads_back_to_the_wand_it_means() -> void:
	WandSystem.ensure_materials()
	var wand: WandData = Data.all_wands()[0]
	var base: String = WandSystem.material_for(wand.id)
	assert_eq(WandSystem.wand_for_material(base), wand)
	assert_null(WandSystem.wand_for_material("NoSuchStick_NetHack"))

func test_a_material_name_drops_the_game_it_came_from() -> void:
	assert_eq(WandSystem.material_name("Oak_NetHack"), "Oak")
	assert_eq(WandSystem.material_source("Oak_NetHack"), "NetHack")

# --- Identification (§6.5) -------------------------------------------------

func test_an_unknown_wand_is_named_for_its_material_and_a_known_one_for_itself() -> void:
	var entry: Dictionary = _entry(&"wand_of_fire")
	var masked: String = WandSystem.display_name(entry)
	assert_string_contains(masked, "Wand")
	assert_false(masked == "Wand of Fire", "the name is the gamble: %s" % masked)
	WandSystem.identify(&"wand_of_fire")
	assert_eq(WandSystem.display_name(entry), "Wand of Fire")

func test_zapping_identifies_the_type_and_every_charge_behind_it() -> void:
	var entry: Dictionary = _entry(&"wand_of_nothing")
	assert_false(WandSystem.is_identified(&"wand_of_nothing"))
	WandSystem.zap_wand(entry, {"rng": _rng()})
	# EVEN THE ONE THAT DID NOTHING. The gamble pays its information out whatever
	# the effect landed on — a wand you could spend six times without learning what
	# it was would be six gambles for the price of one slot.
	assert_true(WandSystem.is_identified(&"wand_of_nothing"),
		"the fizzle still teaches you what it was")

func test_the_preference_is_hidden_until_the_wand_is_known() -> void:
	var entry: Dictionary = _entry(&"wand_of_create_monster")
	assert_eq(WandSystem.preference(entry), "", "an unknown stick hints at nothing")
	WandSystem.identify(&"wand_of_create_monster")
	assert_eq(WandSystem.preference(entry), "Negative")

# --- Charges (§4.1) --------------------------------------------------------

func test_a_fresh_wand_carries_what_the_sheet_authored() -> void:
	var entry: Dictionary = _entry(&"wand_of_fire")
	assert_eq(WandSystem.charges_of(entry), 4)
	assert_eq(WandSystem.max_charges(entry), 4)

# An entry with no `charges` key is a FRESH wand, never an empty one — an old save
# or a hand-written entry should arrive usable rather than dead.
func test_an_entry_with_no_count_reads_as_full() -> void:
	var bare := {"type": "wand", "id": &"wand_of_fire"}
	assert_eq(WandSystem.charges_of(bare), 4, "missing is not the same fact as spent")

func test_zapping_from_the_pack_spends_a_charge_and_keeps_the_slot() -> void:
	GameState.add_wand_loot(&"wand_of_nothing")
	assert_eq(GameState.loot_items.size(), 1)
	LootSystem.use_loot(0, {"rng": _rng()})
	assert_eq(GameState.loot_items.size(), 1, "a wand with charges left stays put")
	assert_eq(WandSystem.charges_of(GameState.loot_items[0]), 5,
		"one charge off the six")

func test_the_last_charge_takes_the_wand_with_it() -> void:
	GameState.add_wand_loot(&"wand_of_nothing")
	for _i in range(6):
		LootSystem.use_loot(0, {"rng": _rng()})
	assert_eq(GameState.loot_items.size(), 0,
		"the sixth zap is the one that empties the slot")

func test_a_one_charge_wand_leaves_on_its_first_zap() -> void:
	GameState.add_wand_loot(&"wand_of_wishing")
	LootSystem.use_loot(0, {"rng": _rng()})
	assert_eq(GameState.loot_items.size(), 0, "one charge is one use, like every other kind")

func test_a_zapped_wand_does_not_move_out_of_its_slot() -> void:
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_wand_loot(&"wand_of_nothing")
	GameState.add_pill_loot(Data.all_pills()[0].id)
	LootSystem.use_loot(1, {"rng": _rng()})
	assert_eq(String(GameState.loot_items[1].get("type", "")), "wand",
		"index 1 is still the wand — firing it is not a rearrangement")
	assert_eq(GameState.loot_items.size(), 3)

func test_charges_can_be_topped_up_but_never_past_the_top() -> void:
	var entry: Dictionary = _entry(&"wand_of_fire")
	entry["charges"] = 1
	assert_true(WandSystem.add_charges(entry, 2))
	assert_eq(WandSystem.charges_of(entry), 3)
	assert_true(WandSystem.add_charges(entry, 99))
	assert_eq(WandSystem.charges_of(entry), 4, "clamped to what a fresh one holds")
	assert_false(WandSystem.add_charges(entry, 1),
		"a full wand reports that the bar did not move")

# --- Echo Chamber leaves wands alone entirely (§4.4) -----------------------

func test_a_wand_never_joins_the_echo_memory() -> void:
	GameState.add_wand_loot(&"wand_of_nothing")
	LootSystem.use_loot(0, {"rng": _rng()})
	assert_eq(LootSystem.used_memory().size(), 0,
		"nothing to copy — a wand copied three times would be four effects per charge")

func test_zapping_a_wand_fires_no_echoes_either() -> void:
	# The half that is easy to miss: a wand that replayed the memory without
	# joining it would be three free copies of your last pill, six times over.
	GameState.loot_used_memory.append({"type": "pill",
		"id": Data.all_pills()[0].id, "horse": false})
	var gold_before: int = GameState.gold
	var hp_before: int = GameState.hp
	GameState.add_wand_loot(&"wand_of_nothing")
	var out: Dictionary = LootSystem.use_loot(0, {"rng": _rng()})
	assert_eq(GameState.loot_used_memory.size(), 1, "the memory is untouched")
	assert_eq(GameState.gold, gold_before)
	assert_eq(GameState.hp, hp_before)
	assert_eq(out["logs"].size(), 1, "one line, and it is the wand's own")

# --- Aiming (§4.2) ---------------------------------------------------------

func test_an_unknown_wand_always_asks_for_a_square() -> void:
	# Even the one that turns out to fire where it stands. Asking only the
	# ray-shaped unknowns would say which half of the roster a mystery stick is in.
	for w in Data.all_wands():
		var wand: WandData = w
		assert_true(WandSystem.needs_target(_entry(wand.id)),
			"%s asks while it is still a mystery" % wand.id)

func test_a_known_non_directional_wand_stops_asking() -> void:
	WandSystem.identify(&"wand_of_create_monster")
	assert_false(WandSystem.needs_target(_entry(&"wand_of_create_monster")),
		"there is nothing to point it at once you know that")
	WandSystem.identify(&"wand_of_fire")
	assert_true(WandSystem.needs_target(_entry(&"wand_of_fire")),
		"a ray still wants a square when you know exactly what it is")

func test_a_random_wand_keeps_asking_even_once_it_is_known() -> void:
	WandSystem.identify(&"wand_of_nothing")
	assert_true(WandSystem.needs_target(_entry(&"wand_of_nothing")),
		"it might want one — which is the whole of the disguise")

func test_random_resolves_to_one_of_the_two_real_modes() -> void:
	var wand: WandData = Data.get_wand(&"wand_of_nothing")
	var seen: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in range(200):
		seen[WandSystem.resolve_targeting(wand, rng)] = true
	assert_eq(seen.size(), 2, "both concrete modes come up over 200 zaps")
	assert_true(seen.has("ray") and seen.has("non_directional"))

func test_a_concrete_wand_resolves_to_itself_every_time() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	assert_eq(WandSystem.resolve_targeting(Data.get_wand(&"wand_of_fire"), rng), "ray")
	assert_eq(WandSystem.resolve_targeting(
		Data.get_wand(&"wand_of_wishing"), rng), "non_directional")

# --- The ops (§5) ----------------------------------------------------------

func test_the_wand_of_nothing_says_the_nothing_out_loud() -> void:
	var out: Dictionary = WandSystem.zap_wand(_entry(&"wand_of_nothing"), {"rng": _rng()})
	assert_eq(out["logs"], ["Nothing happens."])
	assert_eq(out["requests"].size(), 0)

func test_the_wand_of_wishing_hands_back_a_picker() -> void:
	var out: Dictionary = WandSystem.zap_wand(_entry(&"wand_of_wishing"), {"rng": _rng()})
	assert_eq(out["requests"].size(), 1)
	assert_eq(String(out["requests"][0].get("kind", "")), "obtain_item")
	assert_eq(String(out["requests"][0].get("pool", "")), "any")

func test_the_wand_of_create_monster_puts_a_body_on_the_board() -> void:
	var before: int = GameLoop2.stack.size()
	var out: Dictionary = WandSystem.zap_wand(
		_entry(&"wand_of_create_monster"), {"rng": _rng()})
	assert_eq(GameLoop2.stack.size(), before + 1, "one more thing to beat")
	assert_eq(out["logs"].size(), 1)
	assert_string_contains(String(out["logs"][0]), "answers the wand")

func test_the_wand_of_fire_burns_the_square_and_lights_the_ground() -> void:
	var cell := Vector2i(1, 0)
	var out: Dictionary = WandSystem.zap_wand(_entry(&"wand_of_fire"),
		{"rng": _rng(), "target": cell})
	assert_not_null(GameLoop2.tile_at(cell), "the ground catches")
	assert_eq(StringName(GameLoop2.tile_at(cell).id), &"fire")
	assert_true(str(out["logs"]).contains("Fire"), "and it says so: %s" % str(out["logs"]))

func test_a_ray_with_nowhere_to_land_fizzles_rather_than_no_opping() -> void:
	var out: Dictionary = WandSystem.zap_wand(_entry(&"wand_of_fire"), {"rng": _rng()})
	assert_eq(out["logs"].size(), 1)
	assert_string_contains(String(out["logs"][0]), "goes wide")

# --- The drop (§4) ---------------------------------------------------------

func test_a_kind_blind_drop_can_roll_a_wand() -> void:
	var found: bool = false
	for _i in range(300):
		if String(GameState.roll_loot_entry("loot").get("type", "")) == "wand":
			found = true
			break
	assert_true(found, "a wand is one of the five things a beaten game can pay")

func test_a_rolled_wand_arrives_full() -> void:
	var entry: Dictionary = WandSystem.roll_wand_loot(_rng())
	assert_eq(String(entry.get("type", "")), "wand")
	assert_eq(WandSystem.charges_of(entry), WandSystem.max_charges(entry),
		"what was found is what the card says — a half-spent drop is unreadable")

# --- The pack's kind-blind surfaces ---------------------------------------

func test_a_wand_reads_as_a_wand_everywhere_the_pack_asks() -> void:
	var entry: Dictionary = _entry(&"wand_of_fire")
	assert_eq(LootSystem.kind_name(entry), "Wand")
	assert_eq(LootSystem.use_verb(entry), "Zap")
	assert_true(LootSystem.is_wand(entry))
	assert_false(LootSystem.can_throw(entry), "a wand is zapped, never thrown")
	assert_eq(LootSystem.charges(entry), [4, 4])
	assert_eq(LootSystem.charges({"type": "pill", "id": &"x"}), [0, 0],
		"no other kind is counting")

func test_the_hover_says_the_charges_whether_or_not_the_stick_is_known() -> void:
	var entry: Dictionary = _entry(&"wand_of_fire")
	assert_string_contains(String(LootSystem.hover_card(entry).get("subtitle", "")),
		"4 / 4 charges")
	WandSystem.identify(&"wand_of_fire")
	assert_string_contains(String(LootSystem.hover_card(entry).get("subtitle", "")),
		"4 / 4 charges")

func test_an_unknown_wand_still_counts_its_charges_in_words() -> void:
	var entry: Dictionary = _entry(&"wand_of_fire")
	entry["charges"] = 2
	assert_string_contains(LootSystem.description(entry), "2 charges left")

# --- Identify and Amnesia reach wands like every other alphabet (§10) -----

func test_identify_and_forget_both_know_about_wands() -> void:
	WandSystem.identify(&"wand_of_fire")
	assert_true(LootSystem.identified_types("wand").has(&"wand_of_fire"))
	assert_true(LootSystem.identified_types("loot").has(&"wand_of_fire"))
	LootSystem.unidentify(&"wand_of_fire")
	assert_false(WandSystem.is_identified(&"wand_of_fire"),
		"Amnesia takes a wand back the way it takes a bottle back")

func test_an_unknown_wand_is_a_candidate_for_identify() -> void:
	GameState.add_wand_loot(&"wand_of_fire")
	var candidates: Array = LootSystem.carried_unidentified()
	assert_eq(candidates.size(), 1)
	assert_eq(String(candidates[0].get("type", "")), "wand")
	assert_true(LootSystem.identify(candidates[0]), "and identifying it is news")

# --- Charging a wand (§7) --------------------------------------------------

func test_a_wand_with_room_is_something_a_charge_can_land_on() -> void:
	GameState.add_wand_loot(&"wand_of_fire")
	assert_eq(GameState.chargeable_wands().size(), 0, "a full wand has no room")
	GameState.loot_items[0]["charges"] = 1
	assert_eq(GameState.chargeable_wands().size(), 1)
	assert_true(GameState.chargeable_things().size() >= 1,
		"and it is in the pool the charge op draws from")

func test_the_charge_op_fills_a_wand_and_names_it() -> void:
	GameState.add_wand_loot(&"wand_of_fire")
	GameState.loot_items[0]["charges"] = 1
	var out: Dictionary = PillSystem.take_pill(
		{"type": "pill", "id": &"48_hour_energy", "horse": false}, {"rng": _rng()})
	assert_eq(WandSystem.charges_of(GameState.loot_items[0]), 4,
		"three charges, one wand, nothing else in the pack to take them")
	assert_true(str(out["logs"]).contains("charged"),
		"and the pill says what it charged: %s" % str(out["logs"]))

# THE NAME IT USES IS THE ONE THE RUN KNOWS. A pill that wrote "Wand of Fire" over
# a stick the player has never zapped would identify it for free, and the charge is
# not the gamble.
func test_charging_an_unknown_wand_does_not_name_it() -> void:
	GameState.add_wand_loot(&"wand_of_fire")
	GameState.loot_items[0]["charges"] = 1
	var out: Dictionary = PillSystem.take_pill(
		{"type": "pill", "id": &"48_hour_energy", "horse": false}, {"rng": _rng()})
	assert_false(str(out["logs"]).contains("Wand of Fire"),
		"the charge does not spoil the stick: %s" % str(out["logs"]))
	assert_false(WandSystem.is_identified(&"wand_of_fire"))

# A BEATEN GAME DOES NOT (§7). A wand that topped itself up every game would be an
# infinite wand, and no reason ever to spend the last charge.
func test_beating_a_game_charges_relics_but_never_wands() -> void:
	GameState.add_wand_loot(&"wand_of_fire")
	GameState.loot_items[0]["charges"] = 1
	GameState.charge_all_items(1)
	assert_eq(WandSystem.charges_of(GameState.loot_items[0]), 1,
		"the per-game tick is the relics' and only the relics'")

# --- The save (§6) ---------------------------------------------------------

func test_a_half_spent_wand_and_its_alphabet_survive_a_round_trip() -> void:
	WandSystem.ensure_materials()
	GameState.add_wand_loot(&"wand_of_fire")
	GameState.loot_items[0]["charges"] = 2
	WandSystem.identify(&"wand_of_fire")
	var material: String = WandSystem.material_for(&"wand_of_fire")
	assert_true(SaveSystem.save_named("wand-round-trip"), "the run saves")
	GameState.reset_run()
	assert_eq(GameState.wand_material_map.size(), 0, "reset really did clear it")
	assert_true(SaveSystem.load_named("wand-round-trip"), "and comes back")
	assert_eq(WandSystem.material_for(&"wand_of_fire"), material,
		"a reloaded run keeps the alphabet it spent the run learning")
	assert_true(WandSystem.is_identified(&"wand_of_fire"))
	assert_eq(WandSystem.charges_of(GameState.loot_items[0]), 2,
		"and the stick comes back as spent as it was")
	SaveSystem.clear_all_saves()

# --- a LOOSE wand: the drop's offer, spent where you stand (§4.1) ----------
#
# `use_entry` is `use_loot` with no slot to settle, and a wand is the one kind
# where that difference could have swallowed something: there is no pack row to
# write a charge back to, so a wand taken on the spot could have fired for free.

func test_a_loose_wand_still_spends_a_charge() -> void:
	var entry: Dictionary = _entry(&"wand_of_nothing")
	LootSystem.use_entry(entry, {"rng": _rng()})
	assert_eq(WandSystem.charges_of(entry), 5,
		"a wand used where you stand costs a charge like any other")
	assert_eq(GameState.loot_items.size(), 0, "and it was never in the pack")

func test_the_result_carries_what_is_left_on_both_paths() -> void:
	var loose: Dictionary = LootSystem.use_entry(_entry(&"wand_of_fire"),
		{"rng": _rng(), "target": Vector2i(1, 0)})
	assert_eq(int(loose.get("charges_left", -1)), 3, "loose: 4 - 1")
	GameState.add_wand_loot(&"wand_of_fire")
	var packed: Dictionary = LootSystem.use_loot(0,
		{"rng": _rng(), "target": Vector2i(1, 0)})
	assert_eq(int(packed.get("charges_left", -1)), 3, "and the pack path agrees")

func test_only_a_wand_reports_a_charge_count() -> void:
	GameState.add_scroll_loot(&"scroll_of_fire")
	var out: Dictionary = LootSystem.use_loot(0, {"rng": _rng()})
	assert_false(out.has("charges_left"), "no other kind is counting")
