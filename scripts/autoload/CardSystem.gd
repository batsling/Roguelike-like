extends Node

# CardSystem (autoload) — the games-first (2.0) CARD brain (docs/cards-design.md).
#
# A card is the fourth loot consumable and the first one that is NOT A GAMBLE.
# Scrolls, pills and potions all sell the same trade — spend it to find out what
# it was — and three alphabets of that trade is two more than the run needs. A
# card is spent for what is printed on it: one use, one effect, no identification,
# no Preference, no run-dealt disguise.
#
# WHAT IT WITHHOLDS IS WHICH CARD, AND ONLY WHILE IT IS ON THE FLOOR (§3). A piece
# lying on a battlefield square is face down, and what shows is its SET — the tarot
# deck, the playing cards, the Ironclad's rares. Thirteen cards wear five icons —
# two decks of five and three decks of one — so a face-down arcanum narrows the
# guess to five without ever answering it. (The three one-card decks do name theirs;
# see docs/cards-design.md §3 for why that is the roster's shape rather than a hole
# in the mask.) Pick it up and it turns over for good: the pack draws the face,
# names it, prints its line, and nothing about it is hidden again.
#
# That is why this file has no `identify`, no colour map and no `unidentify`, where
# the other three systems have all three — and why LootSystem's knowledge section
# answers for a card without ever asking here. A card is always known; what changes
# is where it is.
#
# THE OPS ARE ITS OWN. Cards do not reuse EffectSystem's `type`-keyed event
# vocabulary, for the reason scrolls and pills do not: a loot effect returns
# { logs, requests } so the piece can be echoed, replayed and reported on one
# screen, and an EffectSystem handler returns nothing at all. The three verbs that
# genuinely need the map — the teleports — hand back a REQUEST and are finished,
# exactly as Scroll of Teleportation does.
#
# Content lives in the `cards` sheet of tools/Roguelikes.xlsx, generated into
# data/cards2.0/*.tres by tools/generate_card2_tres.py.

const CARD_COLOR := Color(0.86, 0.72, 0.44)

# The word a face-down card answers to when the run has to name one in a log line.
# It is not "Card": a floor token already says WHICH DECK it is, and a log that
# said less than the token would be the one place the run withheld something it
# had already shown.
const FACE_DOWN_NAME := "Card"


# ===========================================================================
# Rolling one
# ===========================================================================

# One card as a carried loot entry — roll_potion_loot's twin. `rarity` rides on
# the entry the way it does for every other kind, so the drop modal can chip it
# without loading the resource.
func roll_card_loot(rng: RandomNumberGenerator = null) -> Dictionary:
	var card: CardData = Data.roll_card(rng)
	if card == null:
		return {}
	return {"type": "card", "id": card.id, "rarity": card.rarity}


func data_for(entry: Dictionary) -> CardData:
	return Data.get_card(StringName(entry.get("id", "")))


# ===========================================================================
# Spending one
# ===========================================================================

# THE SINGLE CHOKE POINT for "a card was spent" (TriggerBus.card_used), beside
# PotionSystem.notify_used and hit by nothing else. A card that fizzled — a
# teleport with nowhere to go, a copy with nothing to copy — was still spent, so
# this fires for those too.
func notify_used(card: CardData) -> void:
	if card == null:
		return
	TriggerBus.card_used.emit({"card": card.id})


# Play `entry` ({type, id}). Returns { "logs": Array[String],
# "requests": Array[Dictionary] } — the contract ScrollSystem.read_scroll,
# PillSystem.take_pill and PotionSystem.quaff_potion all answer with, so one
# caller can spend any of the four.
#   ctx (optional): { "rng": RandomNumberGenerator }
func play_card(entry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	var card: CardData = data_for(entry)
	if card == null:
		return out
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for e in card.effect:
		if e is Dictionary:
			_apply_one(e, out, rng)
	notify_used(card)
	return out


func _apply_one(effect: Dictionary, out: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var op := String(effect.get("op", ""))
	match op:
		"gain_hp":
			_gain_hp(effect, out, rng)
		"gain_stat":
			_gain_stat(effect, out)
		"double_stat":
			_double_stat(effect, out)
		"gain_loot":
			_gain_loot(effect, out)
		"bank_shields_next":
			_bank_shields_next(out)
		"spawn_object":
			_spawn_object(effect, out)
		"teleport_type":
			# The three teleports are the overworld's to fulfil, for the reason
			# Scroll of Teleportation's is: moving the run can mean escaping the
			# game in play, and only whoever moved you can say where you ended up.
			out["requests"].append({"kind": "card_teleport", "dest": "type",
				"game_type": String(effect.get("game_type", ""))})
		"teleport_hub":
			out["requests"].append({"kind": "card_teleport", "dest": "hub"})
		"teleport_start":
			out["requests"].append({"kind": "card_teleport", "dest": "start"})
		"copy_item":
			out["requests"].append({"kind": "copy_item",
				"candidates": copyable_items()})
		_:
			push_warning("CardSystem: unknown effect op '%s'" % op)


# The Lovers is a flat amount; Queen of Hearts is a roll between two. Both are the
# same op, because "gain Health" is one thing and the range is how much — and a
# card that authored two ops for that would be two lines on a screen that has room
# for one.
#
# THE ROLL IS FAVOURED, like every other range in the project (Stats.roll_range):
# Luck is what makes a Queen of Hearts worth holding rather than spending, and a
# uniform 1-20 would be the one number on the board that Luck could not reach.
func _gain_hp(effect: Dictionary, out: Dictionary, rng: RandomNumberGenerator) -> void:
	var amount: int = int(effect.get("value", 0))
	if effect.has("min") or effect.has("max"):
		amount = Stats.roll_range(rng, int(effect.get("min", 1)),
			int(effect.get("max", 1)), Stats.Favour.HIGH)
	if amount == 0:
		return
	var before: int = GameState.hp
	GameState.change_hp(amount)
	var landed: int = GameState.hp - before
	# WHAT LANDED, not what was asked for. Health is capped by Max Health, and a
	# Queen of Hearts that rolled 18 into a run three short of full has given you
	# three — saying "+18 Health" over a bar that moved by three is the screen
	# lying about the card the player just spent.
	if landed <= 0:
		out["logs"].append("You are already as healthy as you can get.")
	elif landed < amount:
		out["logs"].append("+%d Health — %d of the %d rolled fits."
			% [landed, landed, amount])
	else:
		out["logs"].append("+%d Health." % landed)


func _gain_stat(effect: Dictionary, out: Dictionary) -> void:
	var stat := String(effect.get("stat", ""))
	var value: int = int(effect.get("value", 0))
	if stat == "" or value == 0:
		return
	GameState.grant_run_stat(stat, value)
	out["logs"].append("+%d %s." % [value, _stat_word(stat)])


# WHAT THE THREE TWOS DO. Double what you are holding; where you are holding none,
# a `floor` is what you get instead — which is the sheet's "if you have no Bombs
# then Gain +2", and the whole reason the card is not dead in the hand of a player
# who spent everything.
#
# 2 of Hearts AUTHORS NO FLOOR, and that is the roster's one asymmetry: a run at 0
# Health is a run that is over, so the case the floor exists for cannot happen.
func _double_stat(effect: Dictionary, out: Dictionary) -> void:
	var stat := String(effect.get("stat", ""))
	var have: int = _stat_value(stat)
	if have < 0:
		push_warning("CardSystem: cannot double unknown stat '%s'" % stat)
		return
	var gain: int = have
	if have == 0:
		gain = int(effect.get("floor", 0))
		if gain == 0:
			out["logs"].append("You have no %s to double." % _stat_word(stat))
			return
	if stat == "hp":
		var before: int = GameState.hp
		GameState.change_hp(gain)
		var landed: int = GameState.hp - before
		out["logs"].append("Health doubles — +%d." % landed if landed > 0
			else "Your Health is already full.")
		return
	if stat == "gold":
		# GOLD HAS ITS OWN SETTER and needs it: `set_gold` is what emits
		# `gold_changed`, which is the signal the header's purse is drawn off.
		# `grant_run_stat` would move the number and leave the screen showing the
		# old one until something else happened to repaint it.
		GameState.change_gold(gain)
		out["logs"].append("+%d Gold%s." % [gain, "" if have > 0 else " — you had none"])
		return
	GameState.grant_run_stat(stat, gain)
	out["logs"].append("+%d %s%s." % [gain, _stat_word(stat),
		"" if have > 0 else " — you had none"])


# The pools `double_stat` may read, and the ONE place the word maps to the field.
# -1 means "not something this card can double", which is louder than 0: 0 is a
# legitimate answer that the `floor` clause is written for.
func _stat_value(stat: String) -> int:
	match stat:
		"gold":
			return GameState.gold
		"bombs":
			return GameState.bombs
		"keys":
			return GameState.keys
		"hp":
			return GameState.hp
	return -1


# What a stat is called in front of a player. EventSystem's table rather than a
# second one here, and rather than PillSystem's `capitalize()`: The Hierophant
# grants `bonus_shields`, which capitalises to "Bonus Shields" — a pool by a name
# no other screen in the game uses for it (GameState.SHIELD_NAME is "Shield").
func _stat_word(stat: String) -> String:
	return String(EventSystem.GATE_STAT_NAMES.get(stat, stat.capitalize()))


# Ancient Recall: three more cards, OFFERED rather than granted (§4.3). The pack
# holds nine and the run may be carrying eight — `offer_loot` is the call that asks
# instead of silently swallowing the surplus, and it falls back to a direct grant
# where nothing is listening, which is what keeps this working headless.
func _gain_loot(effect: Dictionary, out: Dictionary) -> void:
	var kind := String(effect.get("kind", "loot"))
	var count: int = int(effect.get("count", 1))
	if count <= 0:
		return
	GameState.offer_loot(kind, count)
	var what: String = "card" if kind == "card" else "piece"
	out["logs"].append("%d more %s%s." % [count, what, "" if count == 1 else "s"])


# Barricade: arm the bank for ONE game resolution. The relic this replaces read
# off the inventory and banked every game's leftovers forever; the card banks the
# next one's and is then gone, which is the same rule spent once.
func _bank_shields_next(out: Dictionary) -> void:
	GameState.bank_shields_next = true
	out["logs"].append("The next game's unspent %ss will become %ss."
		% [GameState.TEMP_SHIELD_NAME, GameState.SHIELD_NAME])


# Temperance: put a named machine under the board. NAMED, where an event's
# `spawn_object` rolls one off a tag — an arcade is a room full of whatever
# cabinets it has, and a tarot card is a promise about which one you get.
#
# It goes through ObjectSystem like every other spawn, so the machine lands under
# the battlefield the way a hub's shop does (Overworld2._sync_object_panel), is
# pressable while a game is in play, and is gone when the run travels on.
func _spawn_object(effect: Dictionary, out: Dictionary) -> void:
	var id := StringName(String(effect.get("object", "")))
	var obj: ObjectData = Data.get_object2(id)
	if obj == null:
		push_warning("CardSystem: no object named '%s' to spawn" % id)
		return
	var inst: Dictionary = ObjectSystem.spawn(id)
	if inst.is_empty():
		# Blown off the run, or at its run limit. The card was still spent, so this
		# says the nothing that happened rather than reporting a machine that is
		# not there.
		out["logs"].append("The %s does not come — this run is done with it."
			% obj.display_name)
		return
	out["logs"].append("A %s stands at this game. It is here until you travel on."
		% obj.display_name)


# ? Card: the USABLE relics in the pack, as the picker's candidates.
#
# USABLE ONLY, and charged actives are deliberately not in the list: a charged
# relic's cost is its bar, and a card that fired one for free would be a card that
# reads "skip the only cost that item has". A USABLE's cost is a use, and copying
# one spends none — which is the whole of what "copy" means here.
func copyable_items() -> Array:
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.kind == ItemData.ItemKind.USABLE and not it.is_charged():
			out.append(it)
	return out


# Fire one copied relic's `item_used` triggers, spending NOTHING. The ctx is
# GameState.use_item's, minus everything that belongs to actually using it: no
# `consume_item_use`, no `item_used` on the bus (the relic was not used — a card
# was), no charge drained.
func copy_item(item: ItemData) -> String:
	if item == null or GameState.inventory.find(item) == -1:
		return ""
	var on_overworld: bool = GameState.combat_scene == null \
		and item.overworld_usable and GameState.overworld_scene != null
	var ctx := {
		"source": GameState.combat_player,
		"target": GameState.combat_player,
		"scene": GameState.overworld_scene if on_overworld else GameState.combat_scene,
		"card": null,
		"item": item,
	}
	for trig in item.triggers:
		if String(trig.get("on", "")) != "item_used":
			continue
		EffectSystem.apply_all(trig.get("effects", []), ctx)
	return "The card copies %s." % item.display_name


# ===========================================================================
# Describing one
# ===========================================================================

# The name a card answers to. `face_up` is the one axis a card has: in the pack it
# is itself, and on the floor it is a card of its deck and nothing more.
func display_name(entry: Dictionary, face_up: bool = true) -> String:
	var card: CardData = data_for(entry)
	if card == null:
		return FACE_DOWN_NAME
	if face_up:
		return card.display_name
	return set_label(card)


# "Major Arcana", "Playing Cards", "Ironclad Rare" — what a face-down card says it
# is. Falls back to the bare word when a row ships without an icon, which shows the
# player less than the design intends rather than a blank token.
func set_label(card: CardData) -> String:
	if card == null or card.set_name == "":
		return FACE_DOWN_NAME
	return card.set_name


# What the card does, in words — the sheet's own prose, and only face up. A card on
# the floor answers with its deck, which is the whole of what a face-down card is
# telling you.
func description(entry: Dictionary, face_up: bool = true) -> String:
	var card: CardData = data_for(entry)
	if card == null:
		return ""
	if face_up:
		return card.description
	if card.source_game != "":
		return "A face-down %s card from %s. Pick it up to see which."\
			% [set_label(card), card.source_game]
	return "A face-down card. Pick it up to see which."


# The face, or the back. The two art folders are the two sides, and this is the one
# place either is loaded — every surface that draws a card goes through LootSystem,
# which goes through here, so the floor and the pack can never disagree about which
# side is showing.
func art_texture(entry: Dictionary, face_up: bool = true) -> Texture2D:
	var card: CardData = data_for(entry)
	if card == null:
		return null
	if not face_up:
		var back: Texture2D = _load_art("cards_icons", card.icon_file())
		if back != null:
			return back
		# A set with no icon on disk shows its face rather than nothing. It leaks
		# what the design would rather withhold, and a blank square on the board
		# leaks that something is broken, which is worse.
	return _load_art("cards", card.art_file())


func _load_art(folder: String, base: String) -> Texture2D:
	if base == "":
		return null
	var path := "res://images2.0/%s/%s.png" % [folder, base]
	if not ResourceLoader.exists(path):
		return null
	return load(path)
