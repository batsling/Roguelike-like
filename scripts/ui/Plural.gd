class_name Plural
extends RefCounted

# A count and its noun, agreeing. "1 drop(s)" reads like a form being filled in,
# and "1 games" like a bug — which it is. Every line that prints a number of
# something goes through here rather than tacking on an `s`.
#
#   Plural.count(1, "drop")             -> "1 drop"
#   Plural.count(3, "drop")             -> "3 drops"
#   Plural.count(2, "piece of loot", "pieces of loot") -> "2 pieces of loot"
#   Plural.word(n, "game")              -> "game" / "games", for a number printed
#                                          somewhere else in the sentence

# The noun for `n` of it. The plural defaults to the singular plus "s"; pass it
# for the irregular ones (`piece of loot` / `pieces of loot`, `body` / `bodies`).
static func word(n: int, singular: String, plural: String = "") -> String:
	if n == 1:
		return singular
	return plural if plural != "" else singular + "s"

# "<n> <noun>", the noun agreeing with n.
static func count(n: int, singular: String, plural: String = "") -> String:
	return "%d %s" % [n, word(n, singular, plural)]
