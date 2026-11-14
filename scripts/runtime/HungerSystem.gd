class_name HungerSystem
extends RefCounted

# HUNGER (docs/players-design.md §4; the owner, 13 Nov 2026) — one of Retro Bat's two
# mechanics, and any player's whose sheet row names it. The number lives on
# GameState.hunger and is saved with the run; these are the rules over it.
#
#   - A run opens at START, and never holds more than MAX.
#   - Every game FINISHED (beaten, lost or escaped — every report) costs 1.
#   - At 0 the drain starts: a game finished, or a run lost inside one, with the
#     stomach ALREADY empty costs STARVE_DAMAGE Health instead. The game that
#     takes you to 0 does not hurt; the next thing you do does.
#   - Drinking any potion is +1 (PotionSystem.quaff_potion); eating a piece
#     tagged `food` — a relic or a piece of loot — is +1 and destroys it
#     (`eat`, from the Consume button). Thrown potions feed nothing. At MAX
#     nothing can be eaten: the button greys out rather than waste the food.
#
# The numbers are a first cut the owner expects to tune.

const START := 3
const MAX := 5
const STARVE_DAMAGE := 2
# The Health source a starving loss is billed as (GameState.change_hp).
const SOURCE := "hunger"
const FOOD_TAG := "food"
const COLOR := Color(0.92, 0.66, 0.30)

static func active() -> bool:
	return GameState.has_mechanic(&"hunger")

# A fresh run's stomach. Called by GameLoop2.start_run once the player is set.
static func begin_run() -> void:
	GameState.hunger = START if active() else 0
	GameState.hunger_changed.emit(GameState.hunger)

static func is_full() -> bool:
	return GameState.hunger >= MAX

# +n Hunger, capped at MAX. Returns how much actually went in.
static func feed(n: int = 1, what: String = "") -> int:
	if not active() or n <= 0:
		return 0
	var before: int = GameState.hunger
	GameState.hunger = mini(MAX, before + n)
	var gained: int = GameState.hunger - before
	if gained > 0:
		GameState.hunger_changed.emit(GameState.hunger)
		GameLog.add("%s: +%d Hunger (%d/%d)." % [what if what != "" else "Ate",
			gained, GameState.hunger, MAX], COLOR)
	return gained

# A game was handed in (Overworld2.report — beaten, missed or escaped). Returns
# the Health it cost, 0 when it only cost Hunger. ☠: the loss can end the run.
static func game_finished() -> int:
	if not active():
		return 0
	if GameState.hunger <= 0:
		return starve("You finished a game starving")
	GameState.hunger -= 1
	GameState.hunger_changed.emit(GameState.hunger)
	if GameState.hunger == 0:
		Notifications.notify("You are starving. Eat before you finish another game.",
			UITheme.DANGER)
	return 0

# A run was lost inside a game (GameLoop2.log_attempt). Costs nothing until the
# stomach is empty; then it is the same bill a finished game is.
static func run_lost() -> int:
	if not active() or GameState.hunger > 0:
		return 0
	return starve("You lost a run starving")

static func starve(why: String) -> int:
	var before: int = GameState.hp
	GameLoop2.lose_health(STARVE_DAMAGE, SOURCE)
	var lost: int = before - GameState.hp
	var msg := "%s: -%d Health." % [why, lost]
	Notifications.notify(msg, UITheme.DANGER)
	GameLog.add(msg, UITheme.DANGER)
	return lost

# --- eating -------------------------------------------------------------------

# Whether a relic or a piece of loot is food: its own tags (Locations.tags_of
# reads both kinds the same way).
static func is_food(def: Resource) -> bool:
	return def != null and Locations.tags_of(def).has(FOOD_TAG)

# Everything the run could eat right now: the relics (ItemData) on the shelf,
# then the pack's pieces (their loot Dictionaries) in slot order — the shape
# OwnedPick takes as candidates, so the Eat button lights them where they sit.
static func edible() -> Array:
	var out: Array = []
	if not active():
		return out
	for it in GameState.inventory:
		if it is ItemData and is_food(it):
			out.append(it)
	for e in GameState.loot_items:
		if e is Dictionary and is_food(Achievements.loot_def(e)):
			out.append(e)
	return out

# Whether the Eat button is live: something to eat and room to eat it.
static func can_eat() -> bool:
	return active() and not is_full() and not edible().is_empty()

static func name_of(thing) -> String:
	if thing is ItemData:
		return (thing as ItemData).display_name
	if thing is Dictionary:
		return Achievements.held_name("%s/%s" % [String(thing.get("type", "")),
			String(thing.get("id", ""))])
	return "food"

# Eat one thing `edible()` listed: the piece is destroyed and the stomach takes
# +1. Returns false (and eats nothing) when full, or the thing is no longer held
# or is not food.
static func eat(thing) -> bool:
	if not active() or is_full():
		return false
	var name: String = name_of(thing)
	if thing is ItemData:
		var i: int = GameState.inventory.find(thing)
		if i < 0 or not is_food(thing):
			return false
		GameState.remove_item_at(i)
	elif thing is Dictionary:
		var j: int = -1
		for k in range(GameState.loot_items.size()):
			if is_same(GameState.loot_items[k], thing):
				j = k
				break
		if j < 0 or not is_food(Achievements.loot_def(thing)):
			return false
		GameState.destroy_loot_at(j)
	else:
		return false
	feed(1, "Ate %s" % name)
	return true
