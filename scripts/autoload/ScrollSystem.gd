extends Node

# ScrollSystem (autoload). The cross-mode brain for the SCROLL loot consumable —
# the out-of-combat sibling of PotionSystem. Mirrors its structure:
#   * identification state (global per scroll type, stored on GameState)
#   * art / display-name resolution for identified vs unidentified scrolls
#   * the two-roll Intelligence check that picks an outcome tier
#   * the structured-effect applier for every scroll outcome
#   * the pending-combat carryover applier each combat mode calls at fight start
#
# Scrolls are usable only OUTSIDE combat. Reading one runs a d20 + Intelligence
# check vs DC 10 (success/fail), then a second d20 for the crit, choosing one of
# four outcome tiers (crit_good / good / bad / crit_bad). ScrollSystem applies
# that tier's effects. Effects that need a player CHOICE (which scroll to
# identify, which weapon to enchant, which food to take) or that move the player
# on the overworld (teleport) are returned as "requests" for the calling UI to
# fulfill — keeping this autoload free of scene/UI coupling, the same way
# PotionSystem leaves targeting to the combat scene.

const SCROLL_DC: int = 10
const CRIT_GOOD_THRESHOLD: int = 18   # 18/19/20 on the crit die = critical success
const CRIT_BAD_THRESHOLD: int = 3     # 1/2/3 on the crit die = critical failure
const SCROLL_COLOR := Color(0.61, 0.35, 0.71)

const TIER_LABELS := {
	"crit_good": "Critical Success",
	"good": "Success",
	"bad": "Failure",
	"crit_bad": "Critical Failure",
}
const TIER_COLORS := {
	"crit_good": Color(0.945, 0.769, 0.059),
	"good": Color(0.18, 0.80, 0.44),
	"bad": Color(0.90, 0.49, 0.13),
	"crit_bad": Color(0.906, 0.298, 0.235),
}

# ===========================================================================
# Identification (mirrors PotionSystem)
# ===========================================================================

func is_identified(id: StringName) -> bool:
	return GameState.identified_scroll_types.has(id)

# Reveals a scroll type for the rest of the run. Returns true if this call newly
# identified it (so callers can show a one-time toast).
func identify(id: StringName) -> bool:
	if id == &"" or GameState.identified_scroll_types.has(id):
		return false
	GameState.identified_scroll_types.append(id)
	var s: ScrollData = Data.get_scroll(id)
	var nm: String = s.display_name if s != null else String(id)
	Notifications.notify("Identified: %s!" % nm, SCROLL_COLOR)
	return true

func unidentify(id: StringName) -> void:
	GameState.identified_scroll_types.erase(id)

# ===========================================================================
# Display: names, art
# ===========================================================================

func display_name(scroll: ScrollData) -> String:
	if scroll == null:
		return "Scroll"
	return scroll.display_name if is_identified(scroll.id) else "Unidentified Scroll"

# The shared mystery-scroll art. preload (not a runtime load) so Godot always
# imports it — it isn't referenced by any .tres, so a plain load could miss it
# when the editor hasn't scanned the folder, which showed the ground drop as a
# bare circle instead of the scroll icon.
const UNIDENTIFIED_TEX: Texture2D = preload("res://images/scrolls/Unidentified.png")

# Texture for a scroll: its real art once identified, else the shared mystery
# scroll. Unlike potions there's no per-run colour map.
func art_texture(scroll: ScrollData) -> Texture2D:
	if scroll != null and is_identified(scroll.id):
		var path := "res://images/scrolls/%s.png" % scroll.art_file()
		if ResourceLoader.exists(path):
			return load(path)
	return UNIDENTIFIED_TEX

# ===========================================================================
# Outcome resolution — the two-roll Intelligence check
# ===========================================================================

# Rolls the success die (d20 + Intelligence vs DC 10) then the crit die, and
# returns the resolved tier plus the numbers so the UI can show the math.
# Returns { roll1, int_stat, total1, success, roll2, is_crit, tier }.
func resolve_outcome(rng: RandomNumberGenerator = null) -> Dictionary:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var int_stat: int = GameState.intelligence
	var roll1: int = int(Stats.roll_d20_event(r, "normal")["used"])
	var total1: int = roll1 + int_stat
	var success: bool = total1 >= SCROLL_DC
	var roll2: int = int(Stats.roll_d20_event(r, "normal")["used"])
	var is_crit: bool = (roll2 >= CRIT_GOOD_THRESHOLD) if success else (roll2 <= CRIT_BAD_THRESHOLD)
	var tier: String
	if success and is_crit:
		tier = "crit_good"
	elif success:
		tier = "good"
	elif is_crit:
		tier = "crit_bad"
	else:
		tier = "bad"
	return {
		"roll1": roll1, "int_stat": int_stat, "total1": total1, "success": success,
		"roll2": roll2, "is_crit": is_crit, "tier": tier,
	}

# ===========================================================================
# Effect application
# ===========================================================================

# Apply every effect of a scroll's resolved tier. Non-interactive effects mutate
# GameState immediately; effects that need a player choice or overworld movement
# are collected into `requests` for the caller to fulfill (see the fulfilment
# helpers below). Returns { "logs": Array[String], "requests": Array[Dictionary] }.
#   ctx (optional): { "rng": RandomNumberGenerator }
func apply_outcome(scroll: ScrollData, tier: String, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	if scroll == null:
		return out
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for effect in scroll.outcome_effects(tier):
		if effect is Dictionary:
			_apply_one(effect, out, rng)
	return out

func _apply_one(effect: Dictionary, out: Dictionary, rng: RandomNumberGenerator) -> void:
	var op := String(effect.get("op", ""))
	match op:
		"nothing":
			pass
		"buff_enemies":
			var b: Dictionary = GameState.pending_enemy_buff
			b["power"] = int(b.get("power", 0)) + int(effect.get("power", 0))
			b["defense"] = int(b.get("defense", 0)) + int(effect.get("defense", 0))
			GameState.pending_enemy_buff = b
			out["logs"].append("Enemies will be aggravated next combat.")
		"spawn_enemies":
			_spawn_enemies(int(effect.get("count", 1)), int(effect.get("max_weight", 5)), rng, out)
		"stun_enemies":
			_schedule_stun(String(effect.get("mode", "all")), int(effect.get("count", 1)), out)
		"identify_scrolls":
			_identify_scrolls(String(effect.get("mode", "all")), int(effect.get("count", 1)), rng, out)
		"self_damage":
			var sd: int = int(effect.get("value", 0))
			GameState.change_hp(-sd)
			out["logs"].append("You take %d %s damage." % [sd, String(effect.get("element", "fire"))])
		"damage_enemies_next":
			GameState.pending_fire_damage_all += int(effect.get("value", 0))
			out["logs"].append("Enemies will be burned next combat.")
		"destroy":
			_destroy(String(effect.get("kind", "item")), int(effect.get("count", 1)), rng, out)
		"heal":
			var h: int = int(effect.get("value", 0))
			GameState.change_hp(h)
			out["logs"].append("You rest and recover %d Health." % h)
		"ambush":
			GameState.pending_ambush = "ambushed"
			out["logs"].append("You will be Ambushed in your next combat.")
		"gain_status":
			GameState.pending_combat_statuses.append({
				"status": StringName(String(effect.get("status", ""))),
				"stacks": int(effect.get("stacks", 1)),
			})
			out["logs"].append("You enter your next combat with %d %s." % [
				int(effect.get("stacks", 1)), String(effect.get("status", "")).capitalize()])
		"forget":
			_forget(String(effect.get("kind", "scroll")), int(effect.get("count", 1)), rng, out)
		"create_food":
			_create_food(String(effect.get("mode", "random")), int(effect.get("count", 1)),
				String(effect.get("rarity", "")), rng, out)
		"enchant_weapon":
			_weapon_effect("enchant", effect, rng, out)
		"vorpalize_weapon":
			_weapon_effect("vorpalize", effect, rng, out)
		"teleport":
			out["requests"].append({
				"kind": "teleport",
				"dir": String(effect.get("dir", "random")),
				"max_steps": int(effect.get("max_steps", 0)),
			})
		_:
			push_warning("ScrollSystem: unknown effect op '%s'" % op)

# --- spawn_enemies (Scroll of Create Monster) ------------------------------
func _spawn_enemies(count: int, max_weight: int, rng: RandomNumberGenerator, out: Dictionary) -> void:
	# Only spawn enemies at or below the run's current difficulty tier (and never
	# bosses), so a scroll can't conjure something out of band. RunDifficulty's
	# Tier (LOW/MEDIUM/HIGH/INSANE) shares 0-2 ints with EnemyData.Difficulty
	# (LOW/MEDIUM/HIGH), so the comparison lines up; BOSS is excluded explicitly.
	var tier_cap: int = RunDifficulty.current_tier()
	var eligible: Array = Data.all_enemies().filter(func(e):
		return e is EnemyData and e.weight <= max_weight \
			and int(e.difficulty) != EnemyData.Difficulty.BOSS \
			and int(e.difficulty) <= tier_cap)
	if eligible.is_empty():
		return
	for _i in range(count):
		var chosen: EnemyData = eligible[rng.randi_range(0, eligible.size() - 1)]
		GameState.pending_spawn_enemies.append({"enemy": chosen.id, "count": 1})
	out["logs"].append("%d extra enem%s added to your next combat." % [count, "y" if count == 1 else "ies"])

# --- stun_enemies (Scroll of Scare Monster) --------------------------------
func _schedule_stun(mode: String, count: int, out: Dictionary) -> void:
	var s: Dictionary = GameState.pending_enemy_start_stun
	match mode:
		"all":
			s["all"] = true
			out["logs"].append("All enemies will be Stunned at the start of your next combat.")
		"random":
			s["count"] = int(s.get("count", 0)) + count
			out["logs"].append("%d random enem%s will be Stunned next combat." % [count, "y" if count == 1 else "ies"])
		"choose":
			s["choose"] = int(s.get("choose", 0)) + count
			out["logs"].append("You'll choose up to %d enem%s to Stun next combat." % [count, "y" if count == 1 else "ies"])
	GameState.pending_enemy_start_stun = s

# --- identify_scrolls (Scroll of Identify) ---------------------------------
func _identify_scrolls(mode: String, count: int, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var unknown := _carried_unidentified_scroll_ids()
	if mode == "all":
		for id in unknown:
			identify(id)
		out["logs"].append("All carried scrolls identified.")
	elif mode == "random":
		for _i in range(count):
			if unknown.is_empty():
				break
			var idx: int = rng.randi_range(0, unknown.size() - 1)
			identify(unknown[idx])
			unknown.remove_at(idx)
	else: # choose
		if unknown.is_empty():
			out["logs"].append("No unidentified scrolls to identify.")
			return
		out["requests"].append({"kind": "identify_scrolls", "count": count, "candidates": unknown})

# Distinct scroll ids the player is carrying that aren't identified yet.
func _carried_unidentified_scroll_ids() -> Array:
	var seen := {}
	var ids: Array = []
	for l in GameState.loot_scrolls():
		var id: StringName = l.get("id", &"")
		if id != &"" and not is_identified(id) and not seen.has(id):
			seen[id] = true
			ids.append(id)
	return ids

# --- destroy (Scroll of Fire) ----------------------------------------------
func _destroy(kind: String, count: int, rng: RandomNumberGenerator, out: Dictionary) -> void:
	if kind == "item":
		for _i in range(count):
			if GameState.inventory.is_empty():
				break
			var idx: int = rng.randi_range(0, GameState.inventory.size() - 1)
			var nm: String = String(GameState.inventory[idx].display_name) if GameState.inventory[idx] != null else "item"
			GameState.remove_item_at(idx)
			out["logs"].append("%s was destroyed by fire." % nm)
	else:
		# scroll / potion loot entries
		for _i in range(count):
			var indices: Array = []
			for j in range(GameState.loot_items.size()):
				var l = GameState.loot_items[j]
				if l is Dictionary and String(l.get("type", "")) == kind:
					indices.append(j)
			if indices.is_empty():
				break
			var pick: int = indices[rng.randi_range(0, indices.size() - 1)]
			GameState.remove_loot_at(pick)
			out["logs"].append("A %s was destroyed by fire." % kind)

# --- forget (Scroll of Amnesia) --------------------------------------------
func _forget(kind: String, count: int, rng: RandomNumberGenerator, out: Dictionary) -> void:
	match kind:
		"scroll":
			_forget_from(GameState.identified_scroll_types, count, rng, func(id): unidentify(id))
			out["logs"].append("You forget what some scrolls do.")
		"potion":
			_forget_from(GameState.identified_potion_types, count, rng, func(id): PotionSystem.unidentify(id))
			out["logs"].append("You forget what some potions do.")
		"spell":
			_forget_from(GameState.learned_spells, count, rng, func(id): GameState.learned_spells.erase(id))
			out["logs"].append("You forget %d spell%s." % [count, "" if count == 1 else "s"])

# Forget `count` (-1 = all) random ids from `pool`, invoking `forget_fn` on each.
# The forget_fn does the actual removal, so we snapshot the targets first.
func _forget_from(pool: Array, count: int, rng: RandomNumberGenerator, forget_fn: Callable) -> void:
	var work: Array = pool.duplicate()
	var n: int = work.size() if count < 0 else mini(count, work.size())
	for _i in range(n):
		if work.is_empty():
			break
		var idx: int = rng.randi_range(0, work.size() - 1)
		var id = work[idx]
		work.remove_at(idx)
		forget_fn.call(id)

# --- create_food (Scroll of Create Food) -----------------------------------
func _create_food(mode: String, count: int, rarity: String, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var pool := _food_pool(rarity)
	if pool.is_empty():
		out["logs"].append("No food could be conjured.")
		return
	if mode == "choose":
		var choices: Array = []
		for _i in range(maxi(2, count)):
			choices.append(pool[rng.randi_range(0, pool.size() - 1)])
		out["requests"].append({"kind": "create_food", "choices": choices})
	else: # random
		for _i in range(count):
			var item: ItemData = pool[rng.randi_range(0, pool.size() - 1)]
			GameState.add_item(item)
			out["logs"].append("You receive %s." % item.display_name)

# Food items, optionally rarity-filtered. "common" -> Common only; "uncommon+"
# -> Uncommon and above; "" -> any food. ItemData.rarity is the COMMON=0 enum.
func _food_pool(rarity: String) -> Array:
	var food: Array = Data.all_items().filter(func(it):
		return it is ItemData and it.tags.has("food"))
	if rarity == "common":
		var c := food.filter(func(it): return int(it.rarity) == 0)
		return c if not c.is_empty() else food
	if rarity == "uncommon+":
		var u := food.filter(func(it): return int(it.rarity) >= 1)
		return u if not u.is_empty() else food
	return food

# --- enchant / vorpalize (deck weapon scrolls) -----------------------------
func _weapon_effect(kind: String, effect: Dictionary, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var weapons := weapon_attack_cards()
	if weapons.is_empty():
		out["logs"].append("You own no Weapon Attack cards to affect.")
		return
	if String(effect.get("target", "random")) == "choose":
		out["requests"].append({
			"kind": "pick_weapon", "op": kind,
			"dmg": int(effect.get("dmg", 0)), "retain": bool(effect.get("retain", false)),
			"cards": weapons,
		})
		return
	var card: CardInstance = weapons[rng.randi_range(0, weapons.size() - 1)]
	if kind == "enchant":
		enchant_card(card, int(effect.get("dmg", 0)), bool(effect.get("retain", false)))
		out["logs"].append("%s was enchanted." % card.data.display_name)
	else:
		vorpalize_card(card, int(effect.get("dmg", 0)), rng)
		out["logs"].append("%s was vorpalized." % card.data.display_name)

# Weapon Attack CardInstances in the run deck (tag "weapon" + Attack type).
func weapon_attack_cards() -> Array:
	return GameState.deck.filter(func(ci):
		return ci is CardInstance and ci.data != null and ci.data.is_attack() and ci.data.tags.has("weapon"))

# ===========================================================================
# Fulfilment helpers (called by the UI after a request's choice is made)
# ===========================================================================

func identify_scrolls_chosen(ids: Array) -> void:
	for id in ids:
		identify(id)

# Enchant: +Dmg via persistent effect_bonuses on the card's first damage effect
# (honored by CardInstance.get_effects in every mode) plus optional Retain.
func enchant_card(card: CardInstance, dmg: int, retain: bool) -> void:
	if card == null or card.data == null:
		return
	if dmg != 0:
		var idx: int = _first_damage_effect_index(card.data)
		if idx >= 0:
			if not card.effect_bonuses.has(idx):
				card.effect_bonuses[idx] = {}
			card.effect_bonuses[idx]["value"] = int(card.effect_bonuses[idx].get("value", 0)) + dmg
	if retain:
		card.granted_retain = true
	GameState.emit_signal("deck_changed")

# Vorpalize: stamp a Vorpal roll straight onto the instance (the deck/evolution
# code already anticipates scroll-stamped Vorpal), plus an optional flat +Dmg.
func vorpalize_card(card: CardInstance, dmg: int, rng: RandomNumberGenerator = null) -> void:
	if card == null or card.data == null:
		return
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	card.vorpal_type = r.randi_range(0, 2)
	card.vorpal_weight = r.randi_range(1, 5)
	if dmg != 0:
		enchant_card(card, dmg, false)
	GameState.emit_signal("deck_changed")

func give_food_item(item: ItemData) -> void:
	if item != null:
		GameState.add_item(item)

func _first_damage_effect_index(card: CardData) -> int:
	for i in range(card.effects.size()):
		var e = card.effects[i]
		if e is Dictionary and String(e.get("type", "")).findn("dmg") >= 0:
			return i
	return -1

# ===========================================================================
# Pending carryover — applied at the START of every combat by each mode's hook
# ===========================================================================

# Drains the scroll-scheduled carryover into a freshly built combat. `stun_fn`,
# `buff_fn` and `fire_fn` are small per-mode closures that know how to stun /
# buff / damage that mode's enemy actors, so this one applier serves all three
# combat scenes. Any may be an invalid Callable to skip that effect.
#   stun_fn(mode, count) -> void   (mode: "all"|"random"|"choose")
#   buff_fn(power, defense) -> void
#   fire_fn(amount) -> void
func apply_pending_combat_effects(stun_fn: Callable, buff_fn: Callable, fire_fn: Callable) -> void:
	var stun: Dictionary = GameState.pending_enemy_start_stun
	if not stun.is_empty() and stun_fn.is_valid():
		if bool(stun.get("all", false)):
			stun_fn.call("all", 0)
		if int(stun.get("count", 0)) > 0:
			stun_fn.call("random", int(stun["count"]))
		if int(stun.get("choose", 0)) > 0:
			stun_fn.call("choose", int(stun["choose"]))
	GameState.pending_enemy_start_stun = {}

	var buff: Dictionary = GameState.pending_enemy_buff
	if not buff.is_empty() and buff_fn.is_valid():
		buff_fn.call(int(buff.get("power", 0)), int(buff.get("defense", 0)))
	GameState.pending_enemy_buff = {}

	if GameState.pending_fire_damage_all > 0 and fire_fn.is_valid():
		fire_fn.call(GameState.pending_fire_damage_all)
	GameState.pending_fire_damage_all = 0
