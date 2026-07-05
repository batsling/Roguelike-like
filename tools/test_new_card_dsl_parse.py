#!/usr/bin/env python3
"""
Guards the DSL additions that shipped with the Warcry / Whirlwind / Skewer /
Storm of Steel / Sword Boomerang batch in generate_card_tres.py:

  - dmg:NxX          -> hits_from: "energy" (X-cost repeat, no fixed hits)
  - topdeck:N        -> put N cards from hand on top of the draw pile (Warcry)
  - discard:all      -> discard the whole hand (Storm of Steel)
  - conjure ... count=discarded -> count_from: "discarded"
  - the boomerang Attack archetype parses like any other shape

Run:

    python3 tools/test_new_card_dsl_parse.py
"""

import importlib.util
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "tools", "generate_card_tres.py")

spec = importlib.util.spec_from_file_location("generate_card_tres", GEN)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def one(dsl):
    on_play, _triggers, _destroy = gen.parse_effects(dsl)
    assert len(on_play) == 1, f"expected one effect from {dsl!r}, got {on_play}"
    return on_play[0]


def main():
    # X-cost repeat: dmg:5xX (Whirlwind) marks the effect to repeat per energy
    # spent instead of carrying a fixed hits count.
    ww = one("dmg:5xX:melee:cleave")
    assert ww == {"type": "dmg", "value": 5, "target": "all_enemies",
                  "damage_type": "melee", "hits_from": "energy"}, ww

    # Case-insensitive x marker, single-target form (Skewer).
    sk = one("dmg:7xx:melee")
    assert sk["hits_from"] == "energy" and sk["value"] == 7 and "hits" not in sk, sk

    # Fixed multi-hit is untouched (Twin Strike).
    ts = one("dmg:5x2:melee")
    assert ts.get("hits") == 2 and "hits_from" not in ts, ts

    # topdeck:N (Warcry) — player-choice by default, `random` flags engine pick.
    td = one("topdeck:1")
    assert td == {"type": "topdeck", "value": 1}, td
    tdr = one("topdeck:2:random")
    assert tdr == {"type": "topdeck", "value": 2, "random": True}, tdr

    # discard:all (Storm of Steel) — the whole hand, no picker.
    da = one("discard:all")
    assert da == {"type": "discard", "all": True}, da

    # conjure count=discarded — one per card the discard:all sent away.
    cj = one("conjure:shiv:hand:count=discarded")
    assert cj == {"type": "conjure", "card_id": "shiv", "destination": "hand",
                  "count": 1, "count_from": "discarded"}, cj
    cju = one("conjure:shiv+:hand:count=discarded")
    assert cju["card_id"] == "shiv+", cju

    # Storm of Steel's full row round-trips as two clauses in order.
    both, _t, _d = gen.parse_effects("discard:all; conjure:shiv:hand:count=discarded")
    assert [e["type"] for e in both] == ["discard", "conjure"], both

    # The boomerang archetype parses via the Attack column.
    shape, params, _rc = gen.parse_attack("Boomerang")
    assert shape == "boomerang" and params == {}, (shape, params)

    # Swing sizes ride the same size-word path Cleave now uses.
    shape2, params2, _rc2 = gen.parse_attack("Swing, Large")
    assert shape2 == "swing" and params2 == {"size": "large"}, (shape2, params2)

    print("test_new_card_dsl_parse: all assertions passed")


if __name__ == "__main__":
    main()
