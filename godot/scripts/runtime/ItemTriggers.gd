class_name ItemTriggers
extends RefCounted

# Shared item-trigger runner used by every combat mode (deckbuilder, action,
# strategy) so the same declarative item data fires identically everywhere.
# Each mode calls fire() at the matching moment, passing its own scene (which
# exposes the EffectSystem callbacks heal / deal_damage / gain_block / …), the
# player actor used as the effect `source`, and the living-enemy list used to
# resolve `target: enemy` / `all_enemies`.
#
# Extracted from DeckbuilderCombat._fire_item_triggers; behaviour is identical.

static func fire(trigger_name: String, scene, player, enemies: Array,
		ctx_extras: Dictionary = {}, turn: int = 0) -> void:
	# Centralized incremental-item counters. Bumped here (once per event,
	# before any item fires) so the same card_played / turn_started hooks feed
	# the counters identically in every combat mode — the `counter` effect
	# handler then reads them back. Done unconditionally; it's a couple of int
	# adds whether or not an incremental item is owned.
	match trigger_name:
		"combat_started":
			GameState.incremental_on_combat_started()
			# Fresh combat: drop any leftover per-turn temp-status tally (Prayer
			# Beads). The player actor is rebuilt each combat, so only the tally
			# needs clearing.
			GameState.temp_status_stacks.clear()
		"turn_started":
			GameState.incremental_on_turn_started(turn)
			# Expire temporary statuses gained on the previous turn (Prayer
			# Beads' Brace, which is gained during the enemy phase). Strip
			# exactly the tracked amount off the player so any permanent stacks
			# of the same status (e.g. Garlic's Brace) survive.
			_expire_temp_statuses(player)
		"turn_tick":
			GameState.incremental_on_turn_tick()
			# turn_tick is the recurring turn boundary in Action and Strategy
			# (neither re-fires turn_started), so temp statuses expire here too.
			# Idempotent: deckbuilder fires both at turn start, and the second
			# call just finds an empty tally.
			_expire_temp_statuses(player)
		"card_played":
			# A new card play ends the previous card's Pen Nib window.
			GameState.pen_nib_double_active = false
			if _card_type_is(_event_card_data(ctx_extras.get("card")), "attack"):
				GameState.incremental_on_attack()

	var sources: Array = []
	sources.append_array(GameState.inventory)
	if GameState.equipped_weapon != null:
		sources.append(GameState.equipped_weapon)
	var event_card = ctx_extras.get("card")
	var event_target = ctx_extras.get("target")
	for item in sources:
		if not (item is ItemData):
			continue
		for trig in item.triggers:
			if String(trig.get("on", "")) != trigger_name:
				continue
			# Turn-gated triggers (Horn Cleat: +Block on the Nth turn). if_turn
			# = 0 / absent means "every time".
			var turn_gate: int = int(trig.get("if_turn", 0))
			if turn_gate > 0 and turn != turn_gate:
				continue
			# card_played filters (Mummified Hand / Duplicator's grant gate):
			# gate on the played card's tag / id / type. event_card may be a
			# CardInstance (deckbuilder) or a raw CardData (action/strategy),
			# so resolve to CardData once.
			var card_data = _event_card_data(event_card)
			var tag_gate: String = String(trig.get("if_card_tag", ""))
			if tag_gate != "" and (card_data == null or not card_data.tags.has(tag_gate)):
				continue
			var id_gate: String = String(trig.get("if_card_id", ""))
			if id_gate != "" and (card_data == null or String(card_data.id) != id_gate):
				continue
			# card_type gate (Duplicator: weapon ATTACK cards; Mummified Hand:
			# powers). Matches against CardData's type enum name.
			var type_gate: String = String(trig.get("if_card_type", ""))
			if type_gate != "" and (card_data == null or not _card_type_is(card_data, type_gate)):
				continue
			# High-frequency triggers (Dead Eye fires on every landed attack)
			# opt out of the generic "(X triggers)" line to keep the log clean;
			# they post their own targeted message from the effect handler.
			if not bool(trig.get("silent", false)):
				GameLog.add("(%s triggers)" % item.display_name, Color(0.85, 0.9, 0.7))
			for effect in trig.get("effects", []):
				_apply(effect, scene, player, enemies, event_card, event_target)

# Removes the temp-status stacks recorded since the last turn boundary from the
# player actor and clears the tally (Prayer Beads). Subtracts only the tracked
# amount, so permanent stacks of the same status are left untouched.
static func _expire_temp_statuses(player) -> void:
	if GameState.temp_status_stacks.is_empty():
		return
	if player != null and player.has_method("add_status"):
		for status_id in GameState.temp_status_stacks.keys():
			var stacks: int = int(GameState.temp_status_stacks[status_id])
			if stacks > 0:
				player.add_status(StringName(status_id), -stacks)
	GameState.temp_status_stacks.clear()

static func _apply(effect: Dictionary, scene, player, enemies: Array,
		event_card, event_target) -> void:
	var t_str: String = effect.get("target", "self")
	if t_str == "all_enemies":
		for e in enemies:
			if e != null and e.is_alive():
				EffectSystem.apply(effect, {
					"source": player, "target": e, "scene": scene, "card": event_card,
				})
		return
	# "random_enemies": apply to `count` distinct living enemies, chosen at
	# random (Raven Feather inflicts Soul Link on 2 random enemies). Falls
	# back to however many are alive if fewer than `count` remain.
	if t_str == "random_enemies":
		var living: Array = []
		for e in enemies:
			if e != null and e.is_alive():
				living.append(e)
		living.shuffle()
		var count: int = int(effect.get("count", 1))
		for i in range(mini(count, living.size())):
			EffectSystem.apply(effect, {
				"source": player, "target": living[i], "scene": scene, "card": event_card,
			})
		return
	var tgt = player
	if t_str == "enemy":
		# Prefer the card's target (card_played path); otherwise the first
		# living enemy so a "target: enemy" proc still lands somewhere.
		if event_target != null and event_target.is_alive():
			tgt = event_target
		else:
			for e in enemies:
				if e != null and e.is_alive():
					tgt = e
					break
	EffectSystem.apply(effect, {
		"source": player, "target": tgt, "scene": scene, "card": event_card,
	})

# Maps a CardData.type enum index to its lowercase name and compares against
# `wanted` (e.g. "attack"). Keeps the if_card_type gate readable in item data.
const _TYPE_NAMES: Array[String] = [
	"attack", "skill", "power", "dice", "status", "curse", "training",
]

# Resolve the played-card context to a CardData. Deckbuilder passes a
# CardInstance (.data holds the CardData); action/strategy pass a CardData
# directly. Returns null when there's no card.
static func _event_card_data(event_card):
	if event_card == null:
		return null
	if event_card is CardData:
		return event_card
	if "data" in event_card:
		return event_card.data
	return null

static func _card_type_is(data, wanted: String) -> bool:
	if data == null:
		return false
	var idx: int = int(data.type)
	if idx < 0 or idx >= _TYPE_NAMES.size():
		return false
	return _TYPE_NAMES[idx] == wanted.to_lower()
