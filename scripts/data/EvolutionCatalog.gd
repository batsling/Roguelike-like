class_name EvolutionCatalog

# AUTO-GENERATED from tools/Roguelikes.xlsx (Evolutions sheet) by
# tools/generate_evolution_tres.py. Do not edit by hand — re-run the
# importer instead. Drives EvolutionSystem (requirement checks + the
# irreversible card swap) and the Collection screen's Evolutions tab.
#
# Each entry:
#   from_card    — base card id that transforms (and the 1st requirement)
#   to_card      — evolved card id it becomes
#   req2_kind    — "item_tag" | "item_id": how the 2nd requirement is met
#   req2_value   — the tag / id the player must own to satisfy req2
const EVOLUTIONS: Array = [
	{ "id": "king_bomber", "name": "King Bomber", "from_card": "lil_bomber", "to_card": "king_bomber", "req2_kind": "item_tag", "req2_value": "crown", "req1_label": "Lil' Bomber", "req2_label": "Any Crown Item", "description": "Gain 5-9 Gold on an enemy hit.", "img": "KingBomber" },
]
