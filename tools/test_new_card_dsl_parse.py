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

    # gain:power:2:temp (Flex) — a Temporary buff routes through status_temp so
    # the stacks are shed at the next turn boundary. Plain gain stays "status".
    fx = one("gain:power:2:temp")
    assert fx == {"type": "status_temp", "status": "power", "stacks": 2,
                  "target": "self"}, fx
    fxu = one("gain:power:4:temporary")
    assert fxu["type"] == "status_temp" and fxu["stacks"] == 4, fxu
    plain = one("gain:power:2")
    assert plain["type"] == "status", plain

    # dmg:N:melee:per=COUNTER (Finisher) — the flat value becomes the per-unit
    # amount (value_mult) and the counter names the dynamic source (value_from).
    fin = one("dmg:6:melee:per=attacks_this_turn")
    assert fin == {"type": "dmg", "value": 6, "target": "enemy",
                   "damage_type": "melee", "value_from": "attacks_this_turn",
                   "value_mult": 6}, fin

    # gain:<status>:X (Doppelganger) — the stack count is the energy spent on
    # the play (stacks_from: "energy"), the status mirror of dmg:NxX. The
    # upgraded X+1 form adds a flat stacks_bonus on top.
    dg = one("gain:next_turn_draw:X")
    assert dg == {"type": "status", "status": "next_turn_draw", "stacks": 0,
                  "stacks_from": "energy", "target": "self"}, dg
    dgu = one("gain:next_turn_energy:X+1")
    assert dgu == {"type": "status", "status": "next_turn_energy", "stacks": 0,
                   "stacks_from": "energy", "target": "self",
                   "stacks_bonus": 1}, dgu
    # Case-insensitive x, and plain numeric gains are untouched.
    dgl = one("gain:next_turn_draw:x")
    assert dgl["stacks_from"] == "energy" and "stacks_bonus" not in dgl, dgl
    nd = one("gain:no_draw:1")
    assert nd == {"type": "status", "status": "no_draw", "stacks": 1,
                  "target": "self"}, nd

    # --- The Burn / Blood for Blood / … port batch ---------------------------

    # dmg ... if_hand=all_attacks (Clash) gates the hit on an all-Attack hand.
    cl = one("dmg:14:melee:if_hand=all_attacks")
    assert cl == {"type": "dmg", "value": 14, "target": "enemy",
                  "damage_type": "melee", "if_hand": "all_attacks"}, cl

    # if_target:STATUS:<verb> (Dropkick) wraps a scene effect behind a gate on
    # the picked enemy's status — target "enemy" is explicit so strategy
    # doesn't default the wrapper to self.
    dk = one("if_target:vulnerable:gain_energy:1")
    assert dk == {"type": "if_target_status", "status": "vulnerable",
                  "target": "enemy",
                  "effect": {"type": "gain_energy", "value": 1}}, dk

    # exhaust:all + dmg hits=exhausted (Fiend Fire) mirror discard:all +
    # count=discarded.
    ea = one("exhaust:all")
    assert ea == {"type": "exhaust", "all": True}, ea
    ff = one("dmg:7:ranged:hits=exhausted")
    assert ff == {"type": "dmg", "value": 7, "target": "enemy",
                  "damage_type": "ranged", "hits_from": "exhausted"}, ff

    # drawn: <clause> (Endless Agony) is a card-level trigger like eot:.
    on_play_d, trig_d, _dd = gen.parse_effects(
        "dmg:4:ranged; drawn: conjure:self:hand")
    assert len(on_play_d) == 1 and on_play_d[0]["type"] == "dmg", on_play_d
    assert trig_d == [{"on": "drawn", "effects": [
        {"type": "conjure", "card_id": "self", "destination": "hand",
         "count": 1}]}], trig_d

    # cost_reduce:per=COUNTER (Blood for Blood / Eviscerate) stays in the
    # effect list at parse time; card_tres pops it into cost_reduce_from.
    cr = one("cost_reduce:per=hp_losses")
    assert cr == {"type": "cost_reduce", "from": "hp_losses"}, cr

    # --- The Flechettes / Go for the Eyes / … port batch ----------------------

    # dmg ... hits=skills_in_hand (Flechettes): one hit per Skill in hand,
    # resolved at play time — the hand-count sibling of hits=exhausted.
    fl = one("dmg:4:ranged:hits=skills_in_hand")
    assert fl == {"type": "dmg", "value": 4, "target": "enemy",
                  "damage_type": "ranged", "hits_from": "skills_in_hand"}, fl

    # dmg ... cleave:if_draw=empty (Grand Finale): the kv gate coexists with
    # the positional cleave modifier on the same clause.
    gf = one("dmg:50:ranged:cleave:if_draw=empty")
    assert gf == {"type": "dmg", "value": 50, "target": "all_enemies",
                  "damage_type": "ranged", "if_draw": "empty"}, gf

    # inflict ... if_intent=attack (Go for the Eyes): the inflict is gated on
    # the target telegraphing an attack.
    ge = one("inflict:weak:1:if_intent=attack")
    assert ge == {"type": "status", "status": "weak", "stacks": 1,
                  "target": "enemy", "if_target_intent": "attack"}, ge

    # topdeck:N:from=discard (Headbutt): the pick pool is the discard pile.
    hb = one("topdeck:1:from=discard")
    assert hb == {"type": "topdeck", "value": 1, "from": "discard"}, hb

    # lose_hp:N (Hemokinesis / Bloodletting) is the plain HP-cost verb.
    hk = one("lose_hp:2")
    assert hk == {"type": "lose_hp", "value": 2}, hk

    # --- The Immolate / Masterful Stab / Perfected Strike / ... port batch ----

    # cost_increase:per=COUNTER (Masterful Stab): the surcharge mirror of
    # cost_reduce -- stays in the effect list at parse time; card_tres pops it
    # into cost_increase_from.
    ci = one("cost_increase:per=hp_losses")
    assert ci == {"type": "cost_increase", "from": "hp_losses"}, ci

    # dmg ... bonus=N:per_name=STR (Perfected Strike): +N damage per card in
    # the combat deck whose name contains STR (lower-cased at parse time).
    ps = one("dmg:6:melee:bonus=2:per_name=Strike")
    assert ps == {"type": "dmg", "value": 6, "target": "enemy",
                  "damage_type": "melee", "bonus_per_card_name": "strike",
                  "bonus_per_card": 2}, ps

    # Immolate's magic cleave + Burn conjure round-trips as two clauses.
    imm, _ti, _di = gen.parse_effects(
        "dmg:21:magic:cleave; conjure:burn:discard")
    assert imm[0] == {"type": "dmg", "value": 21, "target": "all_enemies",
                      "damage_type": "magic"}, imm
    assert imm[1] == {"type": "conjure", "card_id": "burn",
                      "destination": "discard", "count": 1}, imm

    # Rampage's positive self-boost (Glass Knife's twin, positive value).
    rp = one("boost_cards:id=rampage:dmg:5")
    assert rp == {"type": "boost_cards", "match_id": "rampage",
                  "stat": "dmg", "value": 5}, rp

    # The auto_aoe archetype takes an explicit target + a size word (Immolate).
    shape_i, params_i, _rci = gen.parse_attack("Auto_aoe, target=nearest, Large")
    assert shape_i == "auto_aoe" and params_i == {"target": "nearest",
                                                  "size": "large"}, (shape_i, params_i)

    # --- The Slice / Sneaky Strike / Unload / Searing Blow ... port batch -----

    # if_counter:COUNTER:<clause> (Sneaky Strike): resolve the wrapped effect
    # only when the named incremental counter is > 0 -- the counter sibling of
    # the if_target wrapper.
    sn = one("if_counter:discards_this_turn:gain_energy:2")
    assert sn == {"type": "if_counter", "counter": "discards_this_turn",
                  "effect": {"type": "gain_energy", "value": 2}}, sn

    # discard:all:non_attack (Unload) / exhaust:all:non_attack (Sever Soul):
    # the hand sweeps spare Attack cards.
    ul = one("discard:all:non_attack")
    assert ul == {"type": "discard", "all": True, "only": "non_attack"}, ul
    sv = one("exhaust:all:non_attack")
    assert sv == {"type": "exhaust", "all": True, "only": "non_attack"}, sv
    # The unfiltered sweeps are untouched.
    assert one("discard:all") == {"type": "discard", "all": True}
    assert one("exhaust:all") == {"type": "exhaust", "all": True}

    # sequential_upgrade:N (Searing Blow) stays in the effect list at parse
    # time; card_tres pops it into CardData.sequential_upgrade_step and forces
    # can_upgrade.
    sb = one("sequential_upgrade:3")
    assert sb == {"type": "sequential_upgrade", "step": 3}, sb

    # Unload's 4-projectile fan rides the projectile archetype's spread param.
    shape_u, params_u, _rcu = gen.parse_attack("Projectile, Medium, spread=4")
    assert shape_u == "projectile" and params_u == {"size": "medium",
                                                    "spread": 4}, (shape_u, params_u)

    # Blood/Dark/Fire rider: damaging elemental cards surface the always-on
    # element inflict at the end of their card text.
    dmg_eff = [{"type": "dmg", "value": 12}]
    assert gen.element_rider("Deal 12 Dmg Fire Melee.", "fire", dmg_eff) == \
        "Deal 12 Dmg Fire Melee. Inflict 1 Burn."
    assert gen.element_rider("Lose 2 Health. Deal 15 Dmg.", "blood", dmg_eff) == \
        "Lose 2 Health. Deal 15 Dmg. Inflict 1 Bleed."
    # No double-append when the rider is already there.
    assert gen.element_rider("Deal 12 Dmg. Inflict 1 Burn.", "fire", dmg_eff) == \
        "Deal 12 Dmg. Inflict 1 Burn."
    # No dmg effect -> no rider; Poison keeps its condition -> no rider.
    assert gen.element_rider("Gain 5 Block.", "fire",
                             [{"type": "block", "value": 5}]) == "Gain 5 Block."
    assert gen.element_rider("Deal 6 Dmg.", "poison", dmg_eff) == "Deal 6 Dmg."

    # The boomerang archetype parses via the Attack column.
    shape, params, _rc = gen.parse_attack("Boomerang")
    assert shape == "boomerang" and params == {}, (shape, params)

    # Swing sizes ride the same size-word path Cleave now uses.
    shape2, params2, _rc2 = gen.parse_attack("Swing, Large")
    assert shape2 == "swing" and params2 == {"size": "large"}, (shape2, params2)

    print("test_new_card_dsl_parse: all assertions passed")


if __name__ == "__main__":
    main()
