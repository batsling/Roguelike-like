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
# action, BattleUnit in strategy) — anything exposing get_status. Null (out of
# combat) returns the text untouched.
#
# `rich` controls colouring: true emits BBCode (green = buffed dmg, blue = buffed
# block, red = reduced) for RichTextLabel; false emits the bare number for plain
# Labels (strategy's card tiles), which still shows the scaled value.

const COL_DMG_UP := "7dff7d"
const COL_BLOCK_UP := "7dd4ff"
const COL_DOWN := "ff7d7d"

static var _re_cache: Dictionary = {}

static func scale_text(text: String, player, rich: bool = true) -> String:
	if player == null or text == "" or not player.has_method("get_status"):
		return text
	var power: int = player.get_status(&"power")
	var arcane: int = player.get_status(&"arcane")
	var defense: int = player.get_status(&"defense")
	var persistence: int = player.get_status(&"persistence")
	var weak: bool = player.get_status(&"weak") > 0
	var frail: bool = player.get_status(&"frail") > 0
	var out := text

	# Physical damage — "Deal NxM Dmg" then "Deal N Dmg". The magic variants are
	# spelled "... Magic Dmg", so the physical patterns never touch them.
	out = _sub(out, "Deal (\\d+)[xX](\\d+) Dmg", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._atk(base, power, weak)
		return "Deal %sx%s Dmg" % [CardScaling._num(v, base, COL_DMG_UP, rich), m.get_string(2)])
	out = _sub(out, "Deal (\\d+) Dmg", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._atk(base, power, weak)
		return "Deal %s Dmg" % CardScaling._num(v, base, COL_DMG_UP, rich))

	# Magic damage.
	out = _sub(out, "Deal (\\d+)[xX](\\d+) Magic Dmg", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._atk(base, arcane, weak)
		return "Deal %sx%s Magic Dmg" % [CardScaling._num(v, base, COL_DMG_UP, rich), m.get_string(2)])
	out = _sub(out, "Deal (\\d+) Magic Dmg", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._atk(base, arcane, weak)
		return "Deal %s Magic Dmg" % CardScaling._num(v, base, COL_DMG_UP, rich))

	# Block — "Gain N Block" / "Gain +N Block".
	out = _sub(out, "Gain \\+?(\\d+) Block", func(m):
		var base := int(m.get_string(1))
		var v := CardScaling._blk(base, defense, frail)
		return "Gain %s Block" % CardScaling._num(v, base, COL_BLOCK_UP, rich))

	# Persistence — "Inflict N <Status>" / "Apply N <Status>" for the debuffs
	# Persistence scales. Buffs ("Gain ...") and non-scaling debuffs (Blind …)
	# are left alone, matching Stats.status_apply_stacks.
	if persistence > 0:
		out = _sub(out, "(Inflict|Apply) (\\d+) ([A-Za-z_]+)", func(m):
			var verb := m.get_string(1)
			var base := int(m.get_string(2))
			var word := m.get_string(3)
			if not (StringName(word.to_lower()) in Stats.PERSISTENCE_DEBUFFS):
				return m.get_string(0)
			var v := base + persistence
			return "%s %s %s" % [verb, CardScaling._num(v, base, COL_DMG_UP, rich), word])

	return out

static func _atk(base: int, bonus: int, weak: bool) -> int:
	var v := base + bonus
	if weak:
		v = int(floor(v * 0.75))
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
