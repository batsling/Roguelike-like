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
#   swing     arc swipe at melee reach; the size word    -> family "cone"
#             sets the wrap (small = front, medium =
#             front + flanks, large = full 360 ring)
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

# Size word -> melee reach in px (poke/swing cone length). The sheet uses
# "Small" and "Short" interchangeably for melee (Anger/Neutralize/Claw are
# "Poke/Swing, Small"), so both words resolve to the short reach — without the
# alias they'd silently fall back to medium.
@export var melee_reach_px: Dictionary = {
	"short": 95.0, "small": 95.0, "medium": 135.0, "large": 185.0,
}
# Size word -> projectile / beam travel distance in px.
@export var travel_px: Dictionary = {
	"short": 320.0, "small": 320.0, "medium": 620.0, "large": 950.0, "full": 2200.0,
}
# Size word -> AOE disc radius in px (smash/nova/lob/auto_aoe).
@export var radius_px: Dictionary = {
	"small": 80.0, "medium": 140.0, "large": 215.0,
}

# Swing arcs by size word. A swing's size sets its wrap as well as its reach:
#   small  — just the space in front (the strategy grid's 3 front tiles)
#   medium — front plus the two flanks (the grid's 3 front + 2 side tiles)
#   large  — a full all-around ring (replaces the old "Swing, arc=360" spelling)
# An explicit arc=N param still overrides. "short" aliases small like reach does.
@export var swing_arc_by_size: Dictionary = {
	"short": 110.0, "small": 110.0, "medium": 200.0, "large": 360.0,
}
# Default swing arc (fallback for unknown size words) and the narrower poke arc.
@export var swing_arc_deg: float = 110.0
@export var poke_arc_deg: float = 34.0
# Arc the sweep_beam travels across as it pans left to right.
@export var sweep_beam_arc_deg: float = 150.0
# Beam half-width (px) for the hit test, and the projectile fan width per
# `spread` bolt.
@export var beam_half_width: float = 26.0
@export var spread_fan_deg: float = 42.0
# Player projectile speed (px/s). Reused for homing/lob bodies.
@export var projectile_speed: float = 660.0

# Smear / FX look. Melee archetypes draw a white smear shaped to their hitbox.
@export var smear_color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var smear_duration: float = 0.14
# Swing animation: the arc `swing` archetype isn't a static cone — it renders as
# a white blade sweeping across its arc over `swing_duration`, trailing
# `swing_trail_segments` fading copies for motion blur. Each enemy is struck the
# instant the blade crosses its angle (not all-at-once like an AOE), so the
# collision lines up with the visible swipe. A touch longer than smear_duration
# so the sweep reads as a swing rather than a flash.
@export var swing_duration: float = 0.22
@export var swing_trail_segments: int = 6
# bounce: seconds between hops, and the travelling-orb radius (px). The orb is
# tinted by the card's element (Elements.color) so the bounce reads in-theme.
@export var bounce_interval: float = 0.18
@export var bounce_orb_radius: float = 12.0
# boomerang: the thrown blade's travel speed (px/s) and its live hit radius —
# the blade carries this hitbox for its WHOLE flight, so any enemy it passes
# through gets clipped, not just the enemies it was aimed at.
@export var boomerang_speed: float = 560.0
@export var boomerang_hit_radius: float = 30.0
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
	# beam fires one instant full-length line; the `sweep` subtype (Sweeping Beam)
	# makes it pan left-to-right across a wide arc instead, striking each enemy as
	# the beam crosses its angle (handled in ActionCombat off spec.sweep).
	"beam":       {"family": "beam",       "size": "full"},
	"homing":     {"family": "homing",     "size": "medium"},
	"smite":      {"family": "smite",      "size": "", "target": "nearest"},
	"auto_aoe":   {"family": "auto_aoe",   "size": "small", "target": "random"},
	# bounce: a thrown body that hops between random enemies, applying the card's
	# effects on each landing. Bounce count comes from the effect repeat (`times`
	# / dmg `xN`); the visual is a travelling orb tinted by the card's element.
	"bounce":     {"family": "bounce",     "size": "", "target": "random"},
	# boomerang (Sword Boomerang): a thrown spinning blade that flies to N
	# random enemies in sequence (N = the dmg effect's xN repeat; the next
	# target is picked only on arrival at the current one) and then returns to
	# the player. The blade is a live body with an always-on hitbox
	# (boomerang_hit_radius), so enemies it merely passes through get clipped
	# too — it can land more than N hits. See ActionCombat._process_boomerangs.
	"boomerang":  {"family": "boomerang",  "size": "", "target": "random"},
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
		# Explosive (Lil' Bomber): a projectile that bursts into an AOE on impact.
		# The direct hit deals nothing; the blast deals the card's effects to every
		# enemy in `blast_px`. blast_px is sized off the same word that sets travel
		# (Medium -> the Medium disc radius), defaulting to the medium disc.
		"explosive": bool(p.get("explosive", false)),
		"blast_px": 0.0,
		# sweep (Sweeping Beam): a beam that pans across an arc rather than firing
		# as one instant line. Only meaningful on the beam family.
		"sweep": bool(p.get("sweep", false)),
	}
	if spec["explosive"]:
		spec["blast_px"] = _lookup_px(radius_px, size_word, radius_px["medium"])

	match family:
		"cone":
			spec["reach_px"] = _lookup_px(melee_reach_px, size_word, melee_reach_px["medium"])
			# Swings wrap wider as they grow: the size word picks the arc
			# (small = front, medium = front + flanks, large = full ring).
			# Pokes stay a narrow thrust; an explicit arc= always wins.
			var default_arc: float = poke_arc_deg if shape == "poke" \
				else _lookup_px(swing_arc_by_size, size_word, swing_arc_deg)
			spec["arc_deg"] = float(p.get("arc", default_arc))
		"disc", "disc_self", "lob", "auto_aoe":
			spec["radius_px"] = _lookup_px(radius_px, size_word, radius_px["medium"])
		"projectile", "homing":
			spec["reach_px"] = _lookup_px(travel_px, size_word, travel_px["medium"])
		"beam":
			spec["reach_px"] = _lookup_px(travel_px, size_word, travel_px["full"])
			# The sweep subtype pans the beam across this arc as it fires.
			if spec["sweep"]:
				spec["arc_deg"] = float(p.get("arc", sweep_beam_arc_deg))
		_:
			pass
	return spec

# Stretch a resolved spec's spatial extents by the player's Range multiplier
# (Stats.action_range_multiplier). Touches reach_px (melee/projectile/beam),
# radius_px (disc AOEs and self-novas), and blast_px (explosive bursts) so every
# attack family reaches a little farther per Range point. mult == 1.0 is a no-op.
# Only the player's casts route through here; enemy attacks don't use this lib.
func apply_range_to_spec(spec: Dictionary, mult: float) -> void:
	if mult == 1.0 or spec == null:
		return
	for key in ["reach_px", "radius_px", "blast_px"]:
		if spec.has(key) and float(spec[key]) > 0.0:
			spec[key] = float(spec[key]) * mult
