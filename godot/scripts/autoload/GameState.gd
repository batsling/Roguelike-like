extends Node

# Canonical run-persistent state. Survives between floors, resets on new run.
# Transient per-combat state lives in DeckbuilderCombat (and equivalents)
# and is not stored here.

signal hp_changed(new_hp: int, new_max: int)
signal gold_changed(new_gold: int)
signal stats_changed
signal deck_changed
signal inventory_changed
signal current_game_changed(game_id: StringName)

# === Identity / progression ===
var character_id: StringName = &""
var save_name: String = ""
var current_game_id: StringName = &""
var start_game_id: StringName = &""
var amulet_game_id: StringName = &""
var visited_games: Array[StringName] = []
var beaten_games: Array[StringName] = []
var total_games_beaten: int = 0
# Count of games the player has *played* (entered + resolved, win or
# lose), as opposed to beaten. Drives the difficulty tier — see
# RunDifficulty.gd. The tier steps up every RunDifficulty.GAMES_PER_TIER
# games played.
var games_played: int = 0

# === Player vitals ===
var max_hp: int = 75
var hp: int = 75
var max_energy: int = 3
var hand_size: int = 5

# === Stats ===
# Strength / Dexterity / Intelligence / Charisma drive the derived
# combat statuses (Power / Defense / Arcane / Persistence) and the
# event-roll bonuses. Constitution is roll-only for now. Speed is
# mode-interpreted (extra cards / move speed / tile-move speed) and
# starts at 0 — gained via items / level-up only.
var strength: int = 0
var dexterity: int = 0
var intelligence: int = 0
var charisma: int = 0
var constitution: int = 0
var luck: int = 0
var speed: int = 0

# === Economy ===
var gold: int = 99

# === Deck / items ===
# Each entry is a CardInstance (runtime wrapper around CardData) — see
# CardInstance.gd in scripts/runtime/. For Phase 1a we'll allow raw
# CardData here too and upgrade to wrappers when upgrades land.
var deck: Array = []
var inventory: Array = []                # Array[ItemData] — each entry is a duplicated Resource (see add_item)
var equipped_weapon: ItemData = null     # Also a duplicated Resource

# Cached sum of every inventory + equipped item's effective_stat_bonuses().
# Stats.get_value() reads this so consumers see base + item bonuses
# without each call site adding the bonus manually. Refreshed by
# _recompute_item_bonuses() whenever inventory mutates or an item is
# upgraded/downgraded. Excludes the health bucket — see _applied_item_*.
var item_stat_bonus: Dictionary = {}

# Health-bucket stats (max_hp, max_energy) are applied as direct
# deltas to the GameState fields — never through item_stat_bonus — so
# reads of GameState.max_hp / max_energy stay authoritative without
# layering. The _applied_item_* fields remember our running
# contribution so a recompute moves only the delta.
var _applied_item_max_hp: int = 0
var _applied_item_max_energy: int = 0

# Monotonic id source for ItemData.instance_id. Each call to add_item
# bumps this so duplicated weapon Resources can be paired with their
# granted CardInstance (CardInstance.source_weapon_id) — and so save /
# load can rehydrate the link without name collisions across slots.
var _next_item_instance_id: int = 1

# Run-scope loot counters. Potions/scrolls aren't fleshed out yet, so
# for now each kind is just an int count — cards like Alchemize bump
# `loot.potion`. When the real potion/scroll catalogs land, these
# values will become arrays of concrete ids; the API (`add_loot`,
# `get_loot_count`) stays the same so consumers don't break.
var loot: Dictionary = {
	"potion": 0,
	"scroll": 0,
	"key": 0,
}

# Spells learned this run, addressed by SpellData.id. Drives the
# strategy/tactical Spellbook (Phase 6). Spell defs live in
# `SpellsCatalog` until designers ship .tres files for them.
var learned_spells: Array[StringName] = []

# Strategy/tactical card uses. Run-persistent: a slotted card spends a use
# each time it's played and the remaining count persists across combats AND
# across leaving / re-entering a strategy game within the run. Only refilled
# by "draw"-style effects (and future rest hooks). Keyed by CardData.id ->
# remaining uses; lazily seeded to the card's max on first read.
var card_uses: Dictionary = {}
# Default starting/max uses by CardData.Rarity (STARTER, COMMON, UNCOMMON,
# RARE, LEGENDARY). Stronger/rarer cards bring fewer uses. Overridden
# per-card by CardData.max_uses (>= 0).
const DEFAULT_CARD_USES_BY_RARITY := [4, 4, 3, 2, 2]

# === Action-mode loadout (StringName ids resolved via Data) ===
# Two manual click slots — left (LMB) and right (RMB). Only Strikes or
# weapon-granted cards may be slotted here; everything else in the deck
# plays automatically. Empty / unset means "auto-pick from deck on
# combat start".
var action_left_card_id: StringName = &""
var action_right_card_id: StringName = &""

# === Run-scope resources ===
# Skip is removed from the stat set — the only "skip" is the
# verification-screen "didn't play the real game" choice with the
# fixed HP penalty.
var dash_charges: int = 0
var reroll_charges: int = 0
var fov_bonus: int = 0
var discovery: int = 0

# === Curses / status ===
var active_curses: Array = []            # Array[Dictionary] for now
var pending_combat_statuses: Array = []  # carryover from events

# === Phase ===
enum Phase { MENU, OVERWORLD, EVENT, COMBAT, DEAD, ESCAPE, WIN }
var phase: Phase = Phase.MENU

# ---------------------------------------------------------------------------
# Mutation API — UI and combat scenes go through these so signals fire.
# ---------------------------------------------------------------------------

func reset_run() -> void:
	character_id = &""
	save_name = ""
	current_game_id = &""
	start_game_id = &""
	amulet_game_id = &""
	visited_games.clear()
	beaten_games.clear()
	total_games_beaten = 0
	games_played = 0
	max_hp = 75
	hp = 75
	max_energy = 3
	hand_size = 5
	strength = 0
	dexterity = 0
	intelligence = 0
	charisma = 0
	constitution = 0
	luck = 0
	speed = 0
	gold = 99
	deck.clear()
	inventory.clear()
	equipped_weapon = null
	_reset_item_tracking()
	loot = {"potion": 0, "scroll": 0, "key": 0}
	learned_spells.clear()
	card_uses.clear()
	action_left_card_id = &""
	action_right_card_id = &""
	dash_charges = 0
	reroll_charges = 0
	fov_bonus = 0
	discovery = 0
	active_curses.clear()
	pending_combat_statuses.clear()
	phase = Phase.MENU

func apply_character(char_data: CharacterData) -> void:
	character_id = char_data.id
	max_hp = char_data.base_max_hp
	hp = max_hp
	max_energy = char_data.base_max_energy
	hand_size = char_data.base_hand_size
	strength = char_data.base_strength
	dexterity = char_data.base_dexterity
	intelligence = char_data.base_intelligence
	charisma = char_data.base_charisma
	constitution = char_data.base_constitution
	luck = char_data.base_luck
	speed = char_data.base_speed

	deck.clear()
	for card_id in char_data.starting_deck:
		var c: CardData = Data.get_card(card_id)
		if c != null:
			deck.append(CardInstance.from_data(c))

	inventory.clear()
	_reset_item_tracking()
	for item_id in char_data.starting_items:
		var it: ItemData = Data.get_item(item_id)
		if it != null:
			var inst: ItemData = _append_item_internal(it, 0)
			# Starting weapon items grant their card too — apply_character
			# already emits deck_changed at the end so we don't here.
			_grant_weapon_card(inst)

	equipped_weapon = null
	if char_data.starting_weapon != &"":
		var w: ItemData = Data.get_item(char_data.starting_weapon)
		if w != null:
			equipped_weapon = w.duplicate(true)
			equipped_weapon.instance_id = _next_item_instance_id
			_next_item_instance_id += 1

	_recompute_item_bonuses()
	# Starting items may have raised max_hp; heal to that new full pool
	# so the player begins the run at full health regardless of bonuses.
	hp = max_hp

	emit_signal("stats_changed")
	emit_signal("hp_changed", hp, max_hp)
	emit_signal("deck_changed")
	emit_signal("inventory_changed")

# Clears the bookkeeping that tracks item-granted bonuses and instance ids.
# Shared by reset_run() and apply_character() so the two can't drift apart.
func _reset_item_tracking() -> void:
	item_stat_bonus = {}
	_applied_item_max_hp = 0
	_applied_item_max_energy = 0
	_next_item_instance_id = 1

func set_current_game(id: StringName) -> void:
	current_game_id = id
	emit_signal("current_game_changed", id)

func set_max_hp(new_max: int, heal_to_full: bool = false) -> void:
	# Routes through Stats so Constitution auto-gain fires off the
	# delta. Pass heal_to_full=true to restore HP to the new max
	# (e.g., on level-up). Otherwise current HP is just clamped.
	var old_max: int = max_hp
	max_hp = max(1, new_max)
	if heal_to_full:
		hp = max_hp
	else:
		hp = mini(hp, max_hp)
	Stats.note_max_hp_change(max_hp, old_max)
	emit_signal("hp_changed", hp, max_hp)
	# SCALING items keyed off max_hp (Beefy Ring) need a refresh whenever
	# the pool moves outside of the inventory-recompute path. Guarded by
	# old_max != max_hp so a no-op set doesn't churn the cache.
	if old_max != max_hp:
		_recompute_item_bonuses()

func change_max_hp(delta: int) -> void:
	set_max_hp(max_hp + delta)

func set_hp(new_hp: int) -> void:
	hp = clamp(new_hp, 0, max_hp)
	emit_signal("hp_changed", hp, max_hp)

func change_hp(delta: int) -> void:
	set_hp(hp + delta)

func set_gold(new_gold: int) -> void:
	gold = max(0, new_gold)
	emit_signal("gold_changed", gold)

func change_gold(delta: int) -> void:
	set_gold(gold + delta)

func is_dead() -> bool:
	return hp <= 0

# ---------------------------------------------------------------------------
# Inventory mutation — every add goes through here so each entry is its
# own duplicated Resource. Two copies of the same item never share state,
# which lets the upgrade/downgrade mechanic (and any future per-item
# interaction) target a single slot without leaking into the others.
# ---------------------------------------------------------------------------

func add_item(template: ItemData) -> ItemData:
	# `template` is the shared Resource loaded from .tres. We duplicate
	# deeply so triggers/tags/stat_bonuses can never alias between slots.
	# Weapon items also append their linked CardInstance to the deck
	# with source_weapon_id set, sealing the bidirectional pair.
	if template == null:
		return null
	var inst: ItemData = _append_item_internal(template, 0)
	if _grant_weapon_card(inst):
		emit_signal("deck_changed")
	_recompute_item_bonuses()
	# Fire item_acquired triggers AFTER the inventory + stat recompute so
	# the pickup hook sees the new max_hp (Lunch's +8 HP lands on top of
	# the +8 Max HP its stat_bonuses just contributed). Scene-less — only
	# handlers that don't need a combat scene (gain_hp, gain_gold, …) are
	# valid here.
	for trig in inst.triggers:
		if String(trig.get("on", "")) != "item_acquired":
			continue
		for effect in trig.get("effects", []):
			EffectSystem.apply(effect, {
				"source": null, "target": null, "scene": null, "card": null,
			})
	TriggerBus.emit_signal("item_acquired", {"item": inst})
	emit_signal("inventory_changed")
	return inst

func _grant_weapon_card(inst: ItemData) -> bool:
	# Internal: if `inst` is a weapon with a linked card_id, append a
	# CardInstance tagged with the item's instance_id. Caller decides
	# whether to fire deck_changed (apply_character batches the emit).
	if inst == null:
		return false
	if inst.kind != ItemData.ItemKind.WEAPON or inst.weapon_card_id == &"":
		return false
	var card_def: CardData = Data.get_card(inst.weapon_card_id)
	if card_def == null:
		return false
	var ci: CardInstance = CardInstance.from_data(card_def)
	ci.source_weapon_id = inst.instance_id
	deck.append(ci)
	return true

func remove_item_at(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var removed: ItemData = inventory[index]
	inventory.remove_at(index)
	# Pair removal: a weapon item carries the source_weapon_id its card
	# was tagged with. Strip every deck card pointing back at this slot.
	if removed is ItemData and removed.kind == ItemData.ItemKind.WEAPON and removed.instance_id != 0:
		_remove_deck_cards_for_weapon(removed.instance_id)
	_recompute_item_bonuses()
	emit_signal("inventory_changed")

func remove_card_at(deck_index: int) -> void:
	# Inverse of the weapon-removes-card path. If the card was weapon-
	# granted (source_weapon_id != 0), find and drop the paired item too
	# so the pair never desyncs. Combat-only mutations (exhaust, discard)
	# don't route through here — those operate on the per-combat piles.
	if deck_index < 0 or deck_index >= deck.size():
		return
	var card = deck[deck_index]
	deck.remove_at(deck_index)
	var weapon_id: int = 0
	if card is CardInstance:
		weapon_id = card.source_weapon_id
	if weapon_id != 0:
		for i in range(inventory.size() - 1, -1, -1):
			var it = inventory[i]
			if it is ItemData and it.instance_id == weapon_id:
				inventory.remove_at(i)
				_recompute_item_bonuses()
				emit_signal("inventory_changed")
				break
	emit_signal("deck_changed")

func _remove_deck_cards_for_weapon(weapon_instance_id: int) -> void:
	# Internal: drop every CardInstance whose source_weapon_id matches.
	# Iterates back-to-front so removals don't invalidate the index.
	var changed: bool = false
	for i in range(deck.size() - 1, -1, -1):
		var c = deck[i]
		if c is CardInstance and c.source_weapon_id == weapon_instance_id:
			deck.remove_at(i)
			changed = true
	if changed:
		emit_signal("deck_changed")

func set_equipped_weapon(template: ItemData) -> void:
	# Same duplication contract as add_item — the equipped weapon also
	# carries per-instance upgrade_level / instance_id so the future
	# weapon-as-equipment flow can pair with its card the same way
	# inventory weapons do.
	if template == null:
		equipped_weapon = null
	else:
		equipped_weapon = template.duplicate(true)
		equipped_weapon.instance_id = _next_item_instance_id
		_next_item_instance_id += 1
	_recompute_item_bonuses()
	emit_signal("inventory_changed")

func _append_item_internal(template: ItemData, upgrade_level: int) -> ItemData:
	# Internal: duplicates and appends without firing the recompute /
	# signal. apply_character batches several adds and recomputes once
	# at the end. Always mints a fresh instance_id so weapon coupling
	# survives even when add_item is bypassed.
	var inst: ItemData = template.duplicate(true)
	inst.upgrade_level = upgrade_level
	inst.instance_id = _next_item_instance_id
	_next_item_instance_id += 1
	inventory.append(inst)
	return inst

# Picks a random Passive (anything with a non-zero non-health stat bonus)
# and bumps its upgrade_level by `delta`. Returns a dict with the chosen
# item and its new level, or null if no eligible item exists. Save the
# loop here for the future "Curse of Decay" / event reward hooks.
func upgrade_random_passive(delta: int) -> Dictionary:
	var eligible: Array = []
	for it in inventory:
		if it is ItemData and it.is_upgradeable_passive():
			eligible.append(it)
	if eligible.is_empty():
		return {}
	var picked: ItemData = eligible[randi() % eligible.size()]
	picked.upgrade_level += delta
	# Recompute already emits stats_changed; we add inventory_changed so
	# HUDs that key off inventory state (Vajra+1 tooltips, etc.) refresh.
	_recompute_item_bonuses()
	emit_signal("inventory_changed")
	return {"item": picked, "delta": delta, "new_level": picked.upgrade_level}

# Walks inventory + equipped_weapon and rebuilds item_stat_bonus from
# every effective_stat_bonuses() pass. Vitals (max_hp, max_energy) are
# applied as direct deltas — the _applied_item_* fields track our
# running contribution so an upgrade or remove only moves the change.
func _recompute_item_bonuses() -> void:
	var totals: Dictionary = {}
	var max_hp_total: int = 0
	var max_energy_total: int = 0
	var sources: Array = []
	sources.append_array(inventory)
	if equipped_weapon != null:
		sources.append(equipped_weapon)
	for it in sources:
		if not (it is ItemData):
			continue
		var eff: Dictionary = it.effective_stat_bonuses()
		for stat in eff.keys():
			var v: int = int(eff[stat])
			if v == 0:
				continue
			if stat == "max_hp":
				max_hp_total += v
			elif stat == "max_energy":
				max_energy_total += v
			else:
				totals[stat] = int(totals.get(stat, 0) + v)

	# Vitals are applied as direct deltas (NOT through set_max_hp) so we
	# don't trigger Constitution auto-gain on every inventory mutation
	# or save load. Auto-gain stays reserved for level-up-style events.
	var hp_delta: int = max_hp_total - _applied_item_max_hp
	if hp_delta != 0:
		max_hp = maxi(1, max_hp + hp_delta)
		hp = mini(hp, max_hp)
		_applied_item_max_hp = max_hp_total
		emit_signal("hp_changed", hp, max_hp)

	var en_delta: int = max_energy_total - _applied_item_max_energy
	if en_delta != 0:
		max_energy = maxi(0, max_energy + en_delta)
		_applied_item_max_energy = max_energy_total

	# Second pass: SCALING items. Resolved against the post-vitals state so
	# a Beefy Ring + Alien Baby combo sees the bumped max_hp. Output goes
	# into item_stat_bonus alongside flat bonuses; reads through Stats see
	# both transparently. Scaling never writes vitals — that would re-enter
	# this function via set_max_hp and loop forever.
	for it in sources:
		if not (it is ItemData) or it.scaling.is_empty():
			continue
		for rule in it.scaling:
			var out_stat: String = String(rule.get("stat", ""))
			var per: int = int(rule.get("per", 0))
			var per_val: int = int(rule.get("value", 0))
			var src_stat: String = String(rule.get("of", ""))
			if out_stat == "" or per <= 0 or per_val == 0 or src_stat == "":
				continue
			if out_stat == "max_hp" or out_stat == "max_energy":
				push_warning("ItemData.scaling: '%s' cannot output vitals" % it.id)
				continue
			var src_amount: int = int(get(src_stat))
			@warning_ignore("integer_division")
			var stacks: int = src_amount / per
			if stacks == 0:
				continue
			totals[out_stat] = int(totals.get(out_stat, 0)) + per_val * stacks

	item_stat_bonus = totals
	emit_signal("stats_changed")

# ---------------------------------------------------------------------------
# Loot (potions / scrolls / keys)
# ---------------------------------------------------------------------------

func add_loot(kind: String, amount: int = 1) -> void:
	if amount == 0:
		return
	if not loot.has(kind):
		push_warning("GameState.add_loot: unknown kind '%s'" % kind)
		return
	loot[kind] = maxi(0, int(loot[kind]) + amount)
	emit_signal("inventory_changed")

func get_loot_count(kind: String) -> int:
	return int(loot.get(kind, 0))

# ---------------------------------------------------------------------------
# Strategy/tactical card uses (run-persistent)
# ---------------------------------------------------------------------------

# Starting / maximum uses for a card: the per-card override when set,
# otherwise a rarity-based default that cost shaves down — stronger
# (higher-cost) cards bring fewer uses. cost 0-1 keeps the full rarity
# value; each point above 1 removes a use (X-cost cards count as 1).
func max_card_uses(card: CardData) -> int:
	if card == null:
		return 0
	if card.max_uses >= 0:
		return card.max_uses
	var base: int = 3
	var r: int = card.rarity
	if r >= 0 and r < DEFAULT_CARD_USES_BY_RARITY.size():
		base = DEFAULT_CARD_USES_BY_RARITY[r]
	var cost: int = card.cost
	if cost < 0:  # X-cost
		cost = 1
	return maxi(1, base - maxi(0, cost - 1))

# Remaining uses for a card, lazily seeded to its max on first read so a
# freshly acquired card always starts full.
func get_card_uses(card: CardData) -> int:
	if card == null:
		return 0
	if not card_uses.has(card.id):
		card_uses[card.id] = max_card_uses(card)
	return int(card_uses[card.id])

# Spend one use. Returns false (and changes nothing) if none remain.
func spend_card_use(card: CardData) -> bool:
	if card == null:
		return false
	var remaining: int = get_card_uses(card)
	if remaining <= 0:
		return false
	card_uses[card.id] = remaining - 1
	return true

# Restore up to `n` uses, capped at the card's max. Returns how many were
# actually restored (0 if already full).
func recharge_card_use(card: CardData, n: int = 1) -> int:
	if card == null or n <= 0:
		return 0
	var cur: int = get_card_uses(card)
	var cap: int = max_card_uses(card)
	var restored: int = mini(n, maxi(0, cap - cur))
	if restored > 0:
		card_uses[card.id] = cur + restored
	return restored

# ---------------------------------------------------------------------------
# Action-mode loadout
# ---------------------------------------------------------------------------

# Returns { "left": CardData|null, "right": CardData|null, "auto": Array[CardData] }.
#
# `left`/`right` are the two manual click slots (LMB/RMB). Only Strikes or
# weapon-granted cards are eligible; if unset, the first eligible deck card
# is auto-picked so the arena is always playable. `auto` is the auto-play
# pool: every other deck card except non-playable types (Curse/Status/
# unplayable). Powers are included — they cycle and resolve on a cooldown
# like everything else. Duplicates are preserved (three Strikes in the deck
# means three entries in the pool).
func get_action_loadout() -> Dictionary:
	var left: CardData = Data.get_card(action_left_card_id)
	var right: CardData = Data.get_card(action_right_card_id)
	if left == null:
		left = _auto_pick_click(&"")
	if right == null:
		var left_is_strike: bool = left != null and left.tags.has("strike")
		right = _auto_pick_click(left.id if left != null else &"", left_is_strike)

	# Build the auto pool from the deck, holding back one copy each of the
	# left/right cards (the rest of their copies still auto-play).
	var skip_left: bool = left != null
	var skip_right: bool = right != null
	var auto: Array = []
	for c in deck:
		if not (c is CardInstance) or c.data == null:
			continue
		var data: CardData = c.data
		if skip_left and data.id == left.id:
			skip_left = false  # consumed one copy for the left slot
			continue
		if skip_right and data.id == right.id:
			skip_right = false  # consumed one copy for the right slot
			continue
		if data.unplayable:
			continue
		if data.type == CardData.CardType.CURSE or data.type == CardData.CardType.STATUS:
			continue
		auto.append(data)
	return {"left": left, "right": right, "auto": auto}

# True if the card id may be slotted into a click slot: it's a Strike
# (tagged) or a weapon-granted card (some deck instance links to a weapon).
func is_click_eligible(card_id: StringName) -> bool:
	if card_id == &"":
		return false
	var card: CardData = Data.get_card(card_id)
	if card != null and card.tags.has("strike"):
		return true
	for c in deck:
		if c is CardInstance and c.data != null and c.data.id == card_id and c.source_weapon_id != 0:
			return true
	return false

func _auto_pick_click(exclude_id: StringName, forbid_strike: bool = false) -> CardData:
	# Prefer a Strike; otherwise the first weapon-granted card. Skips
	# `exclude_id` so left and right don't auto-pick the same card, and
	# `forbid_strike` enforces one-Strike-at-a-time across the two slots.
	if not forbid_strike:
		for c in deck:
			if not (c is CardInstance) or c.data == null:
				continue
			if c.data.id == exclude_id:
				continue
			if c.data.tags.has("strike"):
				return c.data
	for c in deck:
		if not (c is CardInstance) or c.data == null:
			continue
		if c.data.id == exclude_id:
			continue
		if c.source_weapon_id != 0:
			return c.data
	return null
