extends Node

# PotionSystem (autoload). The cross-mode brain for the potion loot consumable:
#   * identification state + per-run mystery-bottle colours (stored on GameState)
#   * art / display-name resolution for identified vs unidentified potions
#   * the structured-effect applier shared by deckbuilder, action, and strategy
#   * throw range (Strength-scaled) + splash-area helpers
#
# Combat scenes own targeting UI and death/victory bookkeeping; they call
# apply_to_target / apply_to_targets to mutate actors and then refresh. Both
# CombatActor (deckbuilder/action) and BattleUnit (strategy) expose the same
# hp / max_hp / block / statuses / add_status / get_status surface, so one
# applier serves every mode.

# The mystery bottles an unidentified potion can wear (art under images/potions/).
const UNIDENTIFIED_COLORS: Array[String] = [
	"Unidentified_Red", "Unidentified_Orange", "Unidentified_Yellow",
	"Unidentified_Green", "Unidentified_Cyan", "Unidentified_Teal",
	"Unidentified_Violet", "Unidentified_Purple", "Unidentified_Brown",
	"Unidentified_Black", "Unidentified_Gray", "Unidentified_White",
]

# Base throw distance before Strength (player-widths in action / tiles in
# strategy), and how much Strength extends it: +1 per 2 points.
const THROW_BASE_RANGE: int = 4
const THROW_RANGE_PER_STRENGTH_DIV: int = 2

const POTION_COLOR := Color(0.6, 0.4, 0.75)

# ===========================================================================
# Identification
# ===========================================================================

func is_identified(id: StringName) -> bool:
	return GameState.identified_potion_types.has(id)

# Reveals a potion type for the rest of the run. Returns true if this call is
# what newly identified it (so callers can show a one-time "Identified!" toast).
func identify(id: StringName) -> bool:
	if id == &"" or GameState.identified_potion_types.has(id):
		return false
	GameState.identified_potion_types.append(id)
	var p: PotionData = Data.get_potion(id)
	var nm: String = p.display_name if p != null else String(id)
	Notifications.notify("Identified: %s!" % nm, POTION_COLOR)
	return true

func unidentify(id: StringName) -> void:
	GameState.identified_potion_types.erase(id)

# ===========================================================================
# Display: names, colours, art
# ===========================================================================

func display_name(potion: PotionData) -> String:
	if potion == null:
		return "Potion"
	return potion.display_name if is_identified(potion.id) else "Unidentified Potion"

# The per-run mystery-bottle colour art base for an unidentified potion. Mirrors
# the legacy getPotionColorMap: the whole map is built once per run by SHUFFLING
# the palette and assigning every potion type a colour up front (wrapping when
# there are more potions than colours), so a given potion wears a RANDOM bottle
# each run — the player can't memorise "red = Fire Potion" across runs. The map
# is persisted, so a reloaded run keeps its assignment.
func unidentified_color(id: StringName) -> String:
	_ensure_potion_color_map()
	var key := String(id)
	if not GameState.potion_color_map.has(key):
		# Defensive: a potion added after the map was built (shouldn't happen for
		# sheet content) gets a deterministic wrap slot.
		GameState.potion_color_map[key] = UNIDENTIFIED_COLORS[
			GameState.potion_color_map.size() % UNIDENTIFIED_COLORS.size()]
	return String(GameState.potion_color_map[key])

# Builds the per-run potion -> mystery-colour map if it hasn't been yet: shuffle
# the palette, then assign each loaded potion id a colour in turn (wrapping).
func _ensure_potion_color_map() -> void:
	if not GameState.potion_color_map.is_empty():
		return
	var shuffled: Array = UNIDENTIFIED_COLORS.duplicate()
	shuffled.shuffle()
	var i: int = 0
	for p in Data.all_potions():
		if p is PotionData:
			GameState.potion_color_map[String(p.id)] = shuffled[i % shuffled.size()]
			i += 1

# Texture for a potion: its real art once identified, else the run's mystery
# bottle. Returns null only if even the fallback art is missing.
func art_texture(potion: PotionData) -> Texture2D:
	if potion == null:
		return null
	var base: String
	if is_identified(potion.id):
		base = potion.art_file()
	else:
		base = unidentified_color(potion.id)
	var path := "res://images/potions/%s.png" % base
	if ResourceLoader.exists(path):
		return load(path)
	return null

# ===========================================================================
# Throw range + splash area (mode-aware)
# ===========================================================================

# Throw distance in the mode's units (action player-widths / strategy tiles):
# base 4, +1 per 2 Strength.
func throw_range() -> int:
	@warning_ignore("integer_division")
	return THROW_BASE_RANGE + GameState.strength / THROW_RANGE_PER_STRENGTH_DIV

# Strategy splash footprint as a set of tile offsets around the impact tile.
# Normal potions splash a plus (the tile + its 4 orthogonal neighbours);
# cleave potions cover a radius-2 diamond (3x3 block plus one tile out on each
# side — manhattan distance <= 2).
func strategy_splash_offsets(cleave: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var reach: int = 2 if cleave else 1
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			if abs(dx) + abs(dy) <= reach:
				out.append(Vector2i(dx, dy))
	return out

# Action splash radius in PIXELS, given the player's on-screen width. Normal
# throws make a tight splash (~1.5 widths); cleave potions burst wider (~3).
func action_splash_radius(player_width: float, cleave: bool) -> float:
	return player_width * (3.0 if cleave else 1.5)

# ===========================================================================
# Effect application
# ===========================================================================

# Apply every effect of `potion` to one target actor.
#   ctx keys: source (player actor, for damage scaling), scene (combat scene,
#   for energy / refresh), mode (Stats.Mode), rng (optional).
# Returns a list of human-readable log lines (the scene logs / toasts them).
func apply_to_target(potion: PotionData, target, ctx: Dictionary) -> Array:
	var logs: Array = []
	if potion == null or target == null:
		return logs
	for effect in potion.effects:
		if effect is Dictionary:
			var line: String = _apply_one(effect, potion, target, ctx)
			if line != "":
				logs.append(line)
	return logs

# Apply to a list of targets (cleave / thrown AOE). Each target gets the full
# effect set. Returns the flattened log lines.
func apply_to_targets(potion: PotionData, targets: Array, ctx: Dictionary) -> Array:
	var logs: Array = []
	for t in targets:
		logs.append_array(apply_to_target(potion, t, ctx))
	return logs

func _apply_one(effect: Dictionary, potion: PotionData, target, ctx: Dictionary) -> String:
	var op := String(effect.get("op", ""))
	var tname: String = _target_name(target)
	match op:
		"damage":
			return _apply_damage(effect, target, ctx, tname)
		"block":
			var amt: int = int(effect.get("value", 0))
			if "block" in target:
				target.block = int(target.block) + amt
			return "%s: +%d Block to %s" % [potion.display_name, amt, tname]
		"status":
			var sid := StringName(effect.get("status", ""))
			var stacks: int = int(effect.get("stacks", 0))
			if sid != &"" and stacks != 0 and target.has_method("add_status"):
				target.add_status(sid, stacks)
				if bool(effect.get("temp", false)):
					_register_temp_status(target, sid, stacks, ctx)
			return "%s: %d %s on %s" % [potion.display_name, stacks, _pretty_status(sid), tname]
		"energy":
			var e: int = int(effect.get("value", 0))
			var scene = ctx.get("scene")
			if scene != null and scene.has_method("potion_grant_energy") and scene.potion_grant_energy(e):
				return "%s: +%d Energy" % [potion.display_name, e]
			return "%s: no effect here (no Energy)" % potion.display_name
		"maxhp":
			var v: int = int(effect.get("value", 0))
			_apply_maxhp(target, v)
			return "%s: +%d Max HP and HP to %s" % [potion.display_name, v, tname]
		_:
			return ""

func _apply_damage(effect: Dictionary, target, ctx: Dictionary, tname: String) -> String:
	var base: int = int(effect.get("value", 0))
	var source = ctx.get("source")
	var mode: int = int(ctx.get("mode", Stats.Mode.DECKBUILDER))
	var rng: RandomNumberGenerator = ctx.get("rng")
	var dmg_effect := {"damage_type": String(effect.get("damage_type", "magic"))}
	var res: Dictionary = Stats.resolve_damage(source, target, base, dmg_effect, mode, rng)
	if bool(res.get("missed", false)):
		return "Missed %s!" % tname
	if bool(res.get("dodged", false)):
		return "%s dodged!" % tname
	var loss: int = int(res.get("hp_loss", 0))
	if "hp" in target:
		target.hp = maxi(0, int(target.hp) - loss)
		if loss > 0 and ("dead" in target) and target.hp <= 0:
			target.dead = true
	var crit: String = " (CRIT)" if bool(res.get("crit", false)) else ""
	return "Dealt %d damage to %s%s!" % [loss, tname, crit]

# Fruit Juice: +max AND heal. On the player this routes through GameState (so
# the run-persistent pool moves) and mirrors back onto the combat actor; on any
# other target it just bumps the actor's own pool.
func _apply_maxhp(target, v: int) -> void:
	if v == 0:
		return
	if ("is_player" in target) and target.is_player:
		GameState.change_max_hp(v)
		GameState.change_hp(v)
		if "max_hp" in target:
			target.max_hp = GameState.max_hp
		if "hp" in target:
			target.hp = GameState.hp
	else:
		if "max_hp" in target:
			target.max_hp = int(target.max_hp) + v
		if "hp" in target:
			target.hp = mini(int(target.hp) + v, int(target.max_hp))

# Speed / Flex "for 1 turn": let the scene strip the buff at the next turn
# boundary if it supports it (turn-based modes); otherwise it lingers for the
# room (action has no turns), matching the agreed per-mode adaptation.
func _register_temp_status(target, sid: StringName, stacks: int, ctx: Dictionary) -> void:
	var scene = ctx.get("scene")
	if scene != null and scene.has_method("potion_register_temp_status"):
		scene.potion_register_temp_status(target, sid, stacks)

func _target_name(target) -> String:
	if target == null:
		return "target"
	if ("is_player" in target) and target.is_player:
		return "you"
	if "display_name" in target and String(target.display_name) != "":
		return String(target.display_name)
	if "unit_name" in target and String(target.unit_name) != "":
		return String(target.unit_name)
	return "target"

func _pretty_status(sid: StringName) -> String:
	return String(sid).capitalize()
