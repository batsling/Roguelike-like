#!/usr/bin/env python3
"""
Guards the boost_cards matcher parsing in generate_card_tres.py.

The runtime (DeckbuilderCombat / ActionCombat / BattleView via Stats) supports
matching a boost by tag=, id=, or type=. The sheet -> .tres generator must emit
the right match_* field for each. tag= shipped with Accuracy; id=/type= were
added for Claw ("increase the damage of ALL Claws"). Run:

    python3 tools/test_card_boost_parse.py
"""

import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "tools", "generate_card_tres.py")

spec = importlib.util.spec_from_file_location("generate_card_tres", GEN)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def boost_for(dsl):
    """Parse a single-clause boost_cards line into its effect dict."""
    on_play, _triggers, _destroy = gen.parse_effects(dsl)
    assert len(on_play) == 1, f"expected one effect from {dsl!r}, got {on_play}"
    return on_play[0]


def main():
    # tag= (Accuracy) -> match_tag, no id/type.
    acc = boost_for("boost_cards:tag=shiv:dmg:4")
    assert acc == {"type": "boost_cards", "match_tag": "shiv", "stat": "dmg", "value": 4}, acc

    # id= (Claw) -> match_id. This is the matcher the runtime already understood
    # but the generator used to drop.
    claw = boost_for("boost_cards:id=claw:dmg:2")
    assert claw == {"type": "boost_cards", "match_id": "claw", "stat": "dmg", "value": 2}, claw

    # type= -> match_type.
    typ = boost_for("boost_cards:type=attack:block:3")
    assert typ == {"type": "boost_cards", "match_type": "attack", "stat": "block", "value": 3}, typ

    # Negative values parse (a debuff-style boost).
    neg = boost_for("boost_cards:id=claw:dmg:-1")
    assert neg["value"] == -1, neg

    # Claw, full row: dmg first, boost_cards second, so the played card never
    # buffs its own hit (the boost registers after the damage resolves).
    full, _t, _d = gen.parse_effects("dmg:3:melee; boost_cards:id=claw:dmg:2")
    assert full[0]["type"] == "dmg" and full[0]["value"] == 3, full
    assert full[1] == {"type": "boost_cards", "match_id": "claw", "stat": "dmg", "value": 2}, full

    print("test_card_boost_parse: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
