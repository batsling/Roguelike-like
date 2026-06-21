class_name CardScaling
extends RefCounted

# Rewrites a card's "Deal N Dmg" / "Gain N Block" / "Inflict N <Status>" numbers
# to the value the player would actually deal/gain/inflict right now, folding in
# the live in-combat statuses — mirroring the HTML getCardDisplayDescription:
#   Power       -> physical attack damage   (+ Weak cuts 25%)
#   Arcane      -> magic damage             (+ Weak cuts 25%)
#   Defense     -> Block gained             (+ Frail cuts 25%)
#   Persistence -> stacks of an inflicted PERSISTENCE_DEBUFFS debuff
# These are exactly the modifiers the shared resolvers (Stats.damage_bonus /
# resolve_block / status_apply_stacks) apply, so the display matches what lands
# in every combat mode. `player` is the player actor (CombatActor in deckbuilder/
# action, BattleUnit in strategy) — anything exposing get_status. Null player
# (out of combat) skips the status scaling.
#
# `card` (optional CardData) additionally folds item boosts that raise the
# card's own numbers (Strike Dummy: +3 Dmg) straight INTO the matched number, so
# they read as one value (Strike + Strike Dummy + 3 Power -> "Deal 12 Dmg") and
# scale with Power on top, instead of trailing as a separate "+3" note. When
# both player and card are absent/empty the text is returned untouched.
#
# `rich` controls colouring: true emits BBCode (green = buffed dmg, blue = buffed
# block, red = reduced) for RichTextLabel; false emits the bare number for plain
# Labels (strategy's card tiles), which still shows the scaled value.

const COL_DMG_UP := "7dff7d"
const COL_BLOCK_UP := "7dd4ff"
const COL_DOWN := "ff7d7d"

static var _re_cache: Dictionary = {}

static func scale_text(text: String, player, rich: bool = true, card: CardData = null, target = null) -> String:
	if text == "":
		return text
	var has_player: bool = player != null and player.has_method("get_status")
	var power: int = player.get_status(&"power") if has_player else 0
	var arcane: int = player.get_status(&"arcane") if has_player else 0
	var defense: int = player.get_status(&"defense") if has_player else 0
	var persistence: int = player.get_status(&"persistence") if has_player else 0
	var weak: bool = has_player and player.get_status(&"weak") > 0
	var frail: bool = has_player and player.get_status(&"frail") > 0

	# Incoming-damage modifiers read off the TARGET (when previewing an attack
	# against a specific enemy): Vulnerable (+50%, ceil, all dmg types), Bruise
	# (+1 flat per stack, melee/ranged only) and Brace (-1 flat per stack, all
	# types, min 1). Mirrors the incoming section of Stats.resolve_damage so the
	# previewed "Deal N Dmg" matches what actually lands on THAT enemy. No target
	# (in-hand display, out of combat) leaves these neutral.
	var has_tgt: bool = target != null and target.has_method("get_status")
	var tgt_vulnerable: bool = has_tgt and target.get_status(&"vulnerable") > 0
	var tgt_bruise: int = target.get_status(&"bruise") if has_tgt else 0
	var tgt_brace: int = target.get_status(&"brace") if has_tgt else 0

	# Item boosts that fold straight into the card's own numbers (Strike Dummy:
	# +3 to a Strike's Dmg). These ride the SAME number the player reads, so a
	# Strike with Strike Dummy + 3 Power shows "Deal 12 Dmg" (6 base + 3 boost +
	# 3 Power) — matching what actually resolves via CardInstance.get_effects.
	# Tracked in one-element cells so only the FIRST matching clause consumes the
	# boost (mirroring get_effects, which boosts the first effect of that type).
	var dmg_cell: Array = [0]
	var block_cell: Array = [0]
	if card != null:
		for b in CardMods.granted_boosts(card):
			match String(b.get("type", "")):
				"dmg": dmg_cell[0] += int(b.get("amount", 0))
				"block": block_cell[0] += int(b.get("amount", 0))
	if not has_player and dmg_cell[0] == 0 and block_cell[0] == 0:
		return text
	var out := text

	# Physical damage — "Deal NxM Dmg" then "Deal N Dmg". The magic variants are
	# spelled "... Magic Dmg", so the physical patterns never touch them.
	out = _sub(out, "Deal (\\d+)[xX](\\d+) Dmg", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._atk(base + CardScaling._take(dmg_cell), power, weak)
		v = CardScaling._incoming(v, tgt_vulnerable, tgt_bruise, tgt_brace, true)
		return "Deal %sx%s Dmg" % [CardScaling._num(v, base, COL_DMG_UP, rich), m.get_string(2)])
	out = _sub(out, "Deal (\\d+) Dmg", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._atk(base + CardScaling._take(dmg_cell), power, weak)
		v = CardScaling._incoming(v, tgt_vulnerable, tgt_bruise, tgt_brace, true)
		return "Deal %s Dmg" % CardScaling._num(v, base, COL_DMG_UP, rich))

	# Magic damage (Strike Dummy-style dmg boosts apply to the first dmg effect
	# of any kind, so the same cell feeds these too).
	out = _sub(out, "Deal (\\d+)[xX](\\d+) Magic Dmg", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._atk(base + CardScaling._take(dmg_cell), arcane, weak)
		v = CardScaling._incoming(v, tgt_vulnerable, 0, tgt_brace, false)
		return "Deal %sx%s Magic Dmg" % [CardScaling._num(v, base, COL_DMG_UP, rich), m.get_string(2)])
	out = _sub(out, "Deal (\\d+) Magic Dmg", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._atk(base + CardScaling._take(dmg_cell), arcane, weak)
		v = CardScaling._incoming(v, tgt_vulnerable, 0, tgt_brace, false)
		return "Deal %s Magic Dmg" % CardScaling._num(v, base, COL_DMG_UP, rich))

	# Block — "Gain N Block" / "Gain +N Block".
	out = _sub(out, "Gain \\+?(\\d+) Block", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._blk(base + CardScaling._take(block_cell), defense, frail)
		return "Gain %s Block" % CardScaling._num(v, base, COL_BLOCK_UP, rich))

	# Persistence — "Inflict N <Status>" / "Apply N <Status>" for the debuffs
	# Persistence scales. Buffs ("Gain ...") and non-scaling debuffs (Blind …)
	# are left alone, matching Stats.status_apply_stacks.
	if persistence > 0:
		out = _sub(out, "(Inflict|Apply) (\\d+) ([A-Za-z_]+)", func(m):
			var verb: String = m.get_string(1)
			var base := int(m.get_string(2))
			var word: String = m.get_string(3)
			if not (StringName(word.to_lower()) in Stats.PERSISTENCE_DEBUFFS):
				return m.get_string(0)
			var v := base + persistence
			return "%s %s %s" % [verb, CardScaling._num(v, base, COL_DMG_UP, rich), word])

	return out

# Drains a one-element boost cell: returns its value once, then leaves it 0 so
# only the first matching clause is boosted.
static func _take(cell: Array) -> int:
	var v: int = cell[0]
	cell[0] = 0
	return v

static func _atk(base: int, bonus: int, weak: bool) -> int:
	var v := base + bonus
	if weak:
		v = int(floor(v * 0.75))
	return maxi(0, v)

# Folds the target's incoming-damage statuses onto an already power/weak-scaled
# hit, in the same order Stats.resolve_damage applies them: Vulnerable (+50%,
# ceil) → Bruise (+1/stack, physical only) → Brace (-1/stack, min 1, all types).
static func _incoming(v: int, vulnerable: bool, bruise: int, brace: int, physical: bool) -> int:
	if vulnerable:
		v = int(ceil(v * 1.5))
	if physical:
		v += bruise
	if brace > 0 and v > 0:
		v = maxi(1, v - brace)
	return maxi(0, v)

static func _blk(base: int, defense: int, frail: bool) -> int:
	var v := base + defense
	if frail:
		v = int(floor(v * 0.75))
	return maxi(0, v)

# Renders a (possibly changed) number: unchanged -> bare digits; changed ->
# coloured+bold BBCode when rich, else just the new number.
static func _num(v: int, base: int, up_col: String, rich: bool) -> String:
	if v == base:
		return str(base)
	if not rich:
		return str(v)
	var col := up_col if v > base else COL_DOWN
	return "[color=#%s][b]%d[/b][/color]" % [col, v]

# Single-pass regex replace with a computed replacement (GDScript RegEx.sub has
# no callback form). The callback receives the RegExMatch and returns its
# replacement; building from match boundaries avoids re-scanning injected text.
static func _sub(text: String, pattern: String, cb: Callable) -> String:
	var re: RegEx = _re_cache.get(pattern)
	if re == null:
		re = RegEx.new()
		re.compile(pattern)
		_re_cache[pattern] = re
	var result := ""
	var last := 0
	for m in re.search_all(text):
		result += text.substr(last, m.get_start() - last)
		result += String(cb.call(m))
		last = m.get_end()
	result += text.substr(last)
	return result
