class_name ActionAttackLibrary
extends Resource

# Central, editable definition of how each attack archetype behaves in the
# real-time Action arena. Mirrors ActionTranslation's philosophy: the per-card
# spreadsheet authoring stays terse (usually just the archetype name + a size
# word), while the feel — reach in pixels, AOE radii, swing arcs, projectile
# speed, smear look — is tuned in one place (data/action_attacks.tres).
#
# Reference it from anywhere via Data.action_attacks. ActionCombat calls
# resolve(card) once per cast to turn the card's attack_shape + attack_params
# into a fully-numeric spec it can deliver.
#
# === The vocabulary ===
#   poke      narrow short thrust (slim cone)            -> family "cone"
#   swing     arc swipe at melee reach (arc=360 = ring)  -> family "cone"
#   smash     filled AOE disc at a point in front        -> family "disc"
#   nova      filled AOE disc centred on the player      -> family "disc_self"
#   projectile travelling body; pierce/spread/crescent   -> family "projectile"
#   lob       thrown body that bursts where it lands      -> family "lob"
#   beam      instant full-length line from the player    -> family "beam"
#   homing    projectile that tracks a target             -> family "homing"
#   smite     instant direct hit on a target set          -> family "smite"
#   auto_aoe  auto-pick a target, AOE disc at its spot     -> family "auto_aoe"
#
# The bare size word (Short/Medium/Large/Full) maps to a length for the
# reach-based families (poke/swing/projectile/beam/homing) and to an AOE
# radius for the area families (smash/nova/lob/auto_aoe).

# Size word -> melee reach in px (poke/swing cone length).
@export var melee_reach_px: Dictionary = {
	"short": 95.0, "medium": 135.0, "large": 185.0,
}
# Size word -> projectile / beam travel distance in px.
@export var travel_px: Dictionary = {
	"short": 320.0, "medium": 620.0, "large": 950.0, "full": 2200.0,
}
# Size word -> AOE disc radius in px (smash/nova/lob/auto_aoe).
@export var radius_px: Dictionary = {
	"small": 80.0, "medium": 140.0, "large": 215.0,
}

# Default swing arc (degrees) and the narrower poke arc.
@export var swing_arc_deg: float = 110.0
@export var poke_arc_deg: float = 34.0
# Beam half-width (px) for the hit test, and the projectile fan width per
# `spread` bolt.
@export var beam_half_width: float = 26.0
@export var spread_fan_deg: float = 42.0
# Player projectile speed (px/s). Reused for homing/lob bodies.
@export var projectile_speed: float = 660.0

# Smear / FX look. Melee archetypes draw a white smear shaped to their hitbox.
@export var smear_color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var smear_duration: float = 0.14
@export var beam_color: Color = Color(0.85, 0.95, 1.0, 0.9)
@export var crescent_color: Color = Color(0.95, 0.97, 1.0, 1.0)

# Archetype -> family + default size/params. `size` is the default bare-size
# word for the archetype (interpreted as reach or radius per family).
const ARCHETYPES: Dictionary = {
	"poke":       {"family": "cone",       "size": "short"},
	"swing":      {"family": "cone",       "size": "medium"},
	"smash":      {"family": "disc",       "size": "medium"},
	"nova":       {"family": "disc_self",  "size": "medium"},
	"projectile": {"family": "projectile", "size": "medium"},
	"lob":        {"family": "lob",        "size": "medium"},
	"beam":       {"family": "beam",       "size": "full"},
	"homing":     {"family": "homing",     "size": "medium"},
	"smite":      {"family": "smite",      "size": "", "target": "nearest"},
	"auto_aoe":   {"family": "auto_aoe",   "size": "small", "target": "random"},
}

func _size_word(card_params: Dictionary, default_size: String) -> String:
	var s: String = String(card_params.get("size", "")).strip_edges().to_lower()
	return s if s != "" else default_size

func _lookup_px(table: Dictionary, word: String, fallback: float) -> float:
	if table.has(word):
		return float(table[word])
	return fallback

# Turn a card's attack_shape + attack_params into a numeric, ready-to-deliver
# spec. Unknown shapes fall back to a medium swing so a typo never crashes the
# arena (the caller only routes here when attack_shape is non-empty).
func resolve(card: CardData) -> Dictionary:
	var shape: String = String(card.attack_shape).strip_edges().to_lower()
	var base: Dictionary = ARCHETYPES.get(shape, ARCHETYPES["swing"])
	var p: Dictionary = card.attack_params if card.attack_params != null else {}
	var family: String = String(base["family"])
	var size_word: String = _size_word(p, String(base.get("size", "medium")))

	var spec: Dictionary = {
		"shape": shape,
		"family": family,
		"reach_px": 0.0,
		"arc_deg": 0.0,
		"radius_px": 0.0,
		"spread": maxi(1, int(p.get("spread", 1))),
		"target_mode": String(p.get("target", base.get("target", "nearest"))).to_lower(),
		"pierce": bool(p.get("pierce", false)),
		"crescent": bool(p.get("crescent", false)),
	}

	match family:
		"cone":
			spec["reach_px"] = _lookup_px(melee_reach_px, size_word, melee_reach_px["medium"])
			var default_arc: float = poke_arc_deg if shape == "poke" else swing_arc_deg
			spec["arc_deg"] = float(p.get("arc", default_arc))
		"disc", "disc_self", "lob", "auto_aoe":
			spec["radius_px"] = _lookup_px(radius_px, size_word, radius_px["medium"])
		"projectile", "homing":
			spec["reach_px"] = _lookup_px(travel_px, size_word, travel_px["medium"])
		"beam":
			spec["reach_px"] = _lookup_px(travel_px, size_word, travel_px["full"])
		_:
			pass
	return spec
