#!/usr/bin/env python3
"""
Generate Godot ItemData .tres files from the `items` sheet of
tools/Roguelikes.xlsx.

Mirrors generate_card_tres.py: the spreadsheet is the source of truth and the
.tres are produced by this tool. The structured information lives in the items
sheet's `Effect` column, a colon/semicolon DSL that parses into the ItemData
fields Godot consumes (triggers, card_grants, stat_bonuses, scaling, weapon /
verification, perfect, and the long tail of one-off flags).

  python3 tools/generate_item_tres.py            # regenerate every item with a .tres
  python3 tools/generate_item_tres.py --all      # also emit sheet rows with no .tres yet
  python3 tools/generate_item_tres.py --list      # print the parse without writing

Effect DSL (one item = `clause; clause; ...`, paren/bracket aware):
  passive:        passive: +3 strength, -2 discovery        -> stat_bonuses
  trigger:        combat_start: +10 block (self)            -> triggers[{on, effects}]
                  enemy_killed: 50% chance +2 hp
                  card_played if_type=attack: counter key=attacks_total every=10 -> gain_energy 1
                  turn_started if_turn=3: +18 block (self)
  card grant:     card_grant if_tag=strike: +1 bruise (enemy)
  scaling:        scaling: +1 strength per 20 max_hp
  weapon:         weapon: barrel; verify: <question> => <increment effects>
  perfect:        perfect: gain_hp 5          (perfect_effects)
                  perfect: verify ... => 50% ... (perfect_save_chance)
  flags / misc:   status_amplify:, attack_damage_bonus:, upgrade_card_types:,
                  stat_mirror:, stat_floor:, stat_gain_bonus:, negate_lethal:,
                  reroll_low_rarity:, carries_leftover_energy:,
                  lower_hp_damage_mult:, gold_spend_stat_per=N, level_up:,
                  charged (charge_cost N).

Targets are written in parens after an effect value: (self) / (enemy) /
(all_enemies) / (random_enemies count=2). Bare prose in parens (explanatory
notes) is ignored. See docs/sheet-authoring-handoff.md (Target 2).
"""

import argparse
import json
import os
import re
import sys

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "ITEMS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "items")
ITEM_IMG_DIR = os.path.join(PROJECT_ROOT, "images", "items")

# ItemData.ItemKind enum order.
KIND = {"passive": 0, "triggered": 1, "incremental": 1, "usable": 2,
        "weapon": 3, "scaling": 4, "pickup": 5, "charged": 6}
# ItemData.Rarity enum order.
RARITY = {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}

# Trigger prefixes that map onto a TriggerBus signal. combat_start/combat_end
# are accepted as aliases for the -ed forms the engine emits.
TRIGGER_SIGNALS = {
    "combat_start": "combat_started", "combat_started": "combat_started",
    "combat_end": "combat_ended", "combat_ended": "combat_ended",
    "enemy_spawned": "enemy_spawned", "enemy_killed": "enemy_killed",
    "item_acquired": "item_acquired", "item_used": "item_used",
    "turn_tick": "turn_tick", "turn_started": "turn_started",
    "turn_ended": "turn_ended", "attack_landed": "attack_landed",
    "attack_missed": "attack_missed", "damage_taken": "damage_taken",
    "curse_removed": "curse_removed", "curse_card_removed": "curse_card_removed",
    "curse_applied": "curse_applied", "card_played": "card_played",
    "potion_used": "potion_used",
}
# Hooks that fire frequently enough to suppress the generic trigger log line.
ALWAYS_SILENT = {"attack_landed", "attack_missed", "turn_tick", "damage_taken"}

# Tokens in a "+N <token>" payload that are first-class effect types rather than
# statuses. (In a passive: clause everything is a stat bonus instead.)
HEAL_TOKENS = {"hp"}
BLOCK_TOKENS = {"block"}

# Core stats targetable by gain_stat / temp_stat etc. — informational only; the
# parser does not gate on it.
TARGET_WORDS = {"self", "enemy", "all_enemies", "random_enemies", "same"}


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def slugify(name: str) -> str:
    s = name.strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def display_of(name: str) -> str:
    return re.sub(r"\s*\([^)]*\)\s*$", "", name).strip() or name


def split_top(s: str, sep: str) -> list:
    """Split on `sep` at bracket depth 0 (respecting () [] {})."""
    out, buf, depth = [], [], 0
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        if ch == sep and depth == 0:
            out.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    if buf:
        out.append("".join(buf))
    return [p.strip() for p in out if p.strip()]


def strip_notes(s: str):
    """Pull a trailing/inline target spec out of a payload token and drop any
    purely-prose parenthetical. Returns (clean_text, target, params)."""
    target = None
    params = {}
    # Find every (...) group; keep target groups, discard prose.
    def repl(m):
        nonlocal target, params
        inner = m.group(1).strip()
        toks = inner.split()
        if toks and toks[0].lower() in TARGET_WORDS:
            target = toks[0].lower()
            if target == "same":
                target = "same_target"
            for t in toks[1:]:
                if "=" in t:
                    k, v = t.split("=", 1)
                    params[k.strip()] = v.strip()
            return " "
        # not a target -> prose note, drop it
        return " "
    clean = re.sub(r"\(([^()]*)\)", repl, s)
    return re.sub(r"\s+", " ", clean).strip(), target, params


def _int(tok, default=0):
    try:
        return int(float(tok))
    except (ValueError, TypeError):
        return default


def _usable_uses(type_str, kind):
    # Uses-before-destroyed for a USABLE item, read from the Type cell's optional
    # count ("Usable, 3" -> 3). Bare "Usable" defaults to 1; non-usable items are
    # infinite (-1). Mirrors how "Charged, N" carries its charge cost.
    if kind != KIND["usable"]:
        return -1
    parts = [p.strip() for p in str(type_str or "").split(",")]
    if len(parts) > 1 and parts[1].isdigit():
        return max(1, int(parts[1]))
    return 1


def _kv(tokens):
    """Split tokens into positional list and key=value dict."""
    pos, kv = [], {}
    for t in tokens:
        if "=" in t and not t.startswith("="):
            k, v = t.split("=", 1)
            kv[k.strip()] = v.strip()
        else:
            pos.append(t)
    return pos, kv


# --------------------------------------------------------------------------
# effect-payload parsing
# --------------------------------------------------------------------------

def parse_one_effect(raw, default_target="enemy", in_grant=False):
    """Parse a single payload effect (already comma-split) -> dict or None.
    Returns ('boost', {...}) when the effect should land in a card_grant's
    `boost` array instead of `effects`. Wrapper verbs (chance/counter/if_hp)
    are matched on the RAW text first so a trailing target like `(self)` stays
    attached to the inner effect rather than the wrapper."""
    raw = (raw or "").strip()
    if not raw:
        return None

    # N% chance [=>] <inner>
    m = re.match(r"^(\d+)%\s*chance\s*(?:=>)?\s*(.+)$", raw, re.I)
    if m:
        inner = parse_one_effect(m.group(2), default_target)
        eff = {"type": "chance", "percent": int(m.group(1))}
        if isinstance(inner, dict):
            eff["effect"] = inner
        return eff

    # counter key=K every=N -> <inner>
    m = re.match(r"^counter\s+(.+?)\s*->\s*(.+)$", raw, re.I)
    if m:
        _, kv = _kv(m.group(1).split())
        inner = parse_one_effect(m.group(2), default_target)
        eff = {"type": "counter", "key": kv.get("key", ""),
               "every": _int(kv.get("every", 0))}
        eff["effects"] = [inner] if isinstance(inner, dict) else []
        return eff

    # if_hp above/below F -> <inner>
    m = re.match(r"^if_hp\s+(above|below)\s+([0-9.]+)\s*->\s*(.+)$", raw, re.I)
    if m:
        inner = parse_one_effect(m.group(3), "self")
        eff = {"type": "if_hp", m.group(1).lower(): float(m.group(2))}
        if isinstance(inner, dict):
            eff["effect"] = inner
        return eff

    # +Replay N -> a card-grant addon keyword (matched before strip_notes eats
    # the explanatory paren).
    m = re.match(r"^\+?replay\s+(\d+)\b", raw, re.I)
    if m:
        n = int(m.group(1))
        return ("addon", "replay" if n == 1 else "replay:%d" % n)

    text, target, params = strip_notes(raw)
    if not text:
        return None
    non_lethal = "non_lethal" in raw.lower()
    toks = text.split()
    verb = toks[0].lower()

    # dmg [N|all_enemies] [value_from=..] [xN] [type=..]
    if verb == "dmg":
        rest, kv = _kv(toks[1:])
        eff = {"type": "dmg"}
        val = None
        for t in rest:
            tl = t.lower()
            if tl in TARGET_WORDS:
                target = "all_enemies" if tl == "all_enemies" else tl
            elif re.match(r"^x\d+$", tl):
                eff["value_mult"] = int(tl[1:])
            elif re.match(r"^-?\d+$", t):
                val = int(t)
        if "value_from" in kv:
            eff["value_from"] = kv["value_from"]
        if "value_mult" in kv:
            eff["value_mult"] = _int(kv["value_mult"])
        if "type" in kv:
            eff["damage_type"] = kv["type"]
        if val is not None:
            eff["value"] = val
        if in_grant:
            return ("boost", {"type": "dmg", "field": "value",
                              "amount": eff.get("value", 0)})
        eff["target"] = target or "all_enemies" if "value_from" in eff else (target or default_target)
        return eff

    # simple scalar verbs: verb N
    SCALAR = {"draw", "gain_energy", "gain_gold", "gain_max_hp", "gain_hp",
              "gain_chest", "lose_hp", "heal", "block"}
    if verb in SCALAR:
        rest, kv = _kv(toks[1:])
        nums = [int(x) for x in rest if re.match(r"^-?\d+$", x)]
        eff = {"type": verb, "value": nums[0] if nums else 0}
        # block/heal default to the player; draw etc. only carry an explicit
        # target. A bare "enemy" target is the EffectSystem default and stays
        # implicit, matching the hand-authored .tres.
        tgt = target or ("self" if verb in ("block", "heal") else None)
        if tgt and tgt != "enemy":
            eff["target"] = tgt
        if verb == "lose_hp" and non_lethal:
            eff["non_lethal"] = True
        return eff

    if verb == "gain_stat":
        rest, _ = _kv(toks[1:])
        return {"type": "gain_stat", "stat": rest[0] if rest else "",
                "value": _int(rest[1]) if len(rest) > 1 else 0}

    if verb == "temp_stat":
        rest, _ = _kv(toks[1:])
        stat = rest[0] if rest else ""
        val = next((_int(x) for x in rest[1:] if re.match(r"^[+-]?\d+$", x)), 0)
        return {"type": "temp_stat", "stat": stat, "value": val}

    if verb == "roll_block":
        _, kv = _kv(toks[1:])
        return {"type": "roll_block", "sides": _int(kv.get("sides", 0)),
                "target": target or "self"}

    # overworld_jump <scope> [count=N] — an overworld active (Winged Boots). When
    # used on the map it flies the player to one of `count` games matching `scope`
    # (today: same_year). Marks the item overworld_usable so it can be fired from
    # the backpack / overworld HUD; the move itself is run by the Overworld scene.
    if verb == "overworld_jump":
        rest, kv = _kv(toks[1:])
        return {"type": "overworld_jump",
                "scope": rest[0] if rest else "same_year",
                "count": _int(kv.get("count", 3))}

    if verb == "roll_gold":
        m2 = re.search(r"\[([^\]]*)\]", text)
        amounts = [int(x) for x in re.findall(r"-?\d+", m2.group(1))] if m2 else []
        return {"type": "roll_gold", "amounts": amounts}

    if verb == "upgrade_random_cards":
        _, kv = _kv(toks[1:])
        return {"type": "upgrade_random_cards",
                "card_type": kv.get("card_type", ""),
                "count": _int(kv.get("count", 0))}

    if verb in ("free_random_hand_card", "attack_double"):
        return {"type": verb}

    # reduce_card_cost <amount> [count=N] [tag=X] [type=Y] — Empty Tome.
    # Cost reduction on N random cards matching the filter, for the combat.
    if verb == "reduce_card_cost":
        rest, kv = _kv(toks[1:])
        nums = [int(x) for x in rest if re.match(r"^-?\d+$", x)]
        if nums:
            amount = abs(nums[0])
        elif "amount" in kv:
            amount = abs(_int(kv["amount"], 1))
        else:
            amount = 1
        count = _int(kv["count"], 1) if "count" in kv else 1
        return {"type": "reduce_card_cost",
                "amount": max(1, amount),
                "count": max(1, count),
                "if_card_tag": kv.get("tag", kv.get("if_card_tag", "")),
                "if_card_type": kv.get("type", kv.get("if_card_type", ""))}

    # "reset <key>" -> clears a named streak counter (Dead Eye on a miss).
    if verb == "reset":
        rest = [t for t in toks[1:] if re.match(r"^[a-z_]+$", t)]
        return {"type": "streak_reset", "key": rest[0]} if rest else None

    # "+N <token>" or "-N <token>" — status / heal / block / add_max_hp / stat
    m = re.match(r"^([+-]?[\dX]+)\s+([a-z_]+)(?:\s+(.*))?$", text, re.I)
    if m:
        amount_raw, token, tail = m.group(1), m.group(2).lower(), (m.group(3) or "")
        tail_toks = tail.split()
        _, tail_kv = _kv(tail_toks)
        is_x = amount_raw.upper().strip("+-") == "X"
        amount = _int(amount_raw)
        # streak: "+1 dead_eye streak" -> handled in parse_payload
        if "streak" in tail_toks or token == "streak":
            return None
        if token in HEAL_TOKENS:
            return {"type": "heal", "value": amount, "target": target or "self"}
        if token in BLOCK_TOKENS:
            return {"type": "block", "value": amount, "target": target or "self"}
        if token == "enemy_max_hp":
            return {"type": "add_max_hp", "value": amount}
        # status (optionally _temp) with stacks or stacks_from
        eff_type = "status"
        if "temp" in tail_toks:
            eff_type = "status_temp"
        eff = {"type": eff_type, "status": token}
        if is_x and "stacks_from" in tail_kv:
            eff["stacks_from"] = tail_kv["stacks_from"]
        else:
            eff["stacks"] = amount
        # Inherit the trigger's default target (combat_started -> self, etc.).
        # A bare "enemy" stays implicit (EffectSystem default); grants spell it.
        tgt = target or default_target
        if tgt != "enemy":
            eff["target"] = tgt
        elif in_grant:
            eff["target"] = "enemy"
        if "count" in params:
            eff["count"] = _int(params["count"])
        return eff

    # bare verb fallthrough
    return {"type": verb}


def parse_payload(payload, default_target="enemy", in_grant=False):
    """Parse a trigger payload into (effects[], boosts[], addons[])."""
    effects, boosts, addons = [], [], []
    parts = split_top(payload, ",")
    i = 0
    while i < len(parts):
        part = parts[i]
        low = part.lower()
        # streak pair: "+K name streak (target)" [+ a following "reset"]
        sm = re.match(r"^\+?(\d+)\s+([a-z_]+)\s+streak", low)
        if sm:
            key = sm.group(2)
            # "(same target)" == the enemy just hit (stored as target enemy).
            effects.append({"type": "streak_hit", "key": key,
                            "attack_bonus": True, "label": "",
                            "target": "enemy"})
            i += 1
            continue
        eff = parse_one_effect(part, default_target, in_grant)
        if isinstance(eff, tuple):
            if eff[0] == "boost":
                boosts.append(eff[1])
            elif eff[0] == "addon":
                addons.append(eff[1])
        elif eff is not None:
            effects.append(eff)
        i += 1
    return effects, boosts, addons


# --------------------------------------------------------------------------
# clause parsing -> ItemData field accumulation
# --------------------------------------------------------------------------

def parse_passive(payload):
    bonuses = {}
    for part in split_top(payload, ","):
        part, _, _ = strip_notes(part)
        # Stat names are matched case-insensitively and stored lowercase so a
        # sheet entry like "-2 Strength" still lands on the `strength` field.
        m = re.match(r"^([+-]?\d+)\s+([a-zA-Z_]+)$", part)
        if m:
            bonuses[m.group(2).lower()] = int(m.group(1))
    return bonuses


def parse_multipliers(payload):
    """Parse "strength 1.5, dexterity 2" -> {"strength": 1.5, "dexterity": 2.0}.
    Cricket's Head: stat_multiply: strength 1.5. Each owned copy multiplies the
    named stat's effective value; copies stack multiplicatively (see GameState)."""
    out = {}
    for part in split_top(payload, ","):
        part, _, _ = strip_notes(part)
        m = re.match(r"^([a-zA-Z_]+)\s+([0-9]*\.?[0-9]+)$", part.strip())
        if m:
            out[m.group(1).lower()] = float(m.group(2))
    return out


def parse_scaling(payload):
    # "+1 strength per 20 max_hp"
    m = re.match(r"^\+?(\d+)\s+([a-z_]+)\s+per\s+(\d+)\s+([a-z_]+)", payload.strip())
    if m:
        return [{"stat": m.group(2), "value": int(m.group(1)),
                 "per": int(m.group(3)), "of": m.group(4)}]
    return []


def parse_verify_effects(rhs):
    """Parse the '=> ...' side of a verify clause into verification_effects."""
    rhs = rhs.strip()
    # "+1/+2 Blind"  -> bump_card_effect stacks increments [1,2]
    m = re.match(r"^([+-]?\d+)\s*/\s*([+-]?\d+)\s+(\w+)$", rhs)
    if m:
        return [{"type": "bump_card_effect", "effect_index": 0,
                 "field": "stacks", "increments": [int(m.group(1)), int(m.group(2))]}]
    # "1/2 random fish" -> bump value
    m = re.match(r"^(\d+)\s*/\s*(\d+)\s+", rhs)
    if m:
        return [{"type": "bump_card_effect", "effect_index": 0,
                 "field": "value", "increments": [int(m.group(1)), int(m.group(2))]}]
    # "gain_gold 10/20"
    m = re.match(r"^gain_gold\s+(\d+)\s*/\s*(\d+)$", rhs)
    if m:
        return [{"type": "gain_gold", "increments": [int(m.group(1)), int(m.group(2))]}]
    # "bump effect#0.infuse +1/+2"
    m = re.match(r"^bump\s+effect#(\d+)\.(\w+)\s+([+-]?\d+)\s*/\s*([+-]?\d+)$", rhs)
    if m:
        return [{"type": "bump_card_effect", "effect_index": int(m.group(1)),
                 "field": m.group(2), "increments": [int(m.group(3)), int(m.group(4))]}]
    return []


def parse_item(row):
    name = str(row["Name"]).strip()
    iid = slugify(name)
    fields = {
        "id": iid,
        "display_name": display_of(name),
        "kind": KIND.get(str(row.get("Type", "")).split(",")[0].strip().lower(), 0),
        "rarity": RARITY.get(str(row.get("Rating", "")).strip().lower(), 0),
        "starter": str(row.get("Rating", "")).strip().lower() == "starter",
        "description": str(row.get("Description") or "").strip(),
        "triggers": [],
        "card_grants": [],
        "stat_bonuses": {},
        "stat_multipliers": {},
        "scaling": [],
    }
    # USABLE pills are spent on use. The count comes from the Type cell:
    # "Usable, 3" -> 3 uses before the item is destroyed; bare "Usable" -> 1.
    # Everything else is infinite-use (-1).
    fields["max_uses"] = _usable_uses(row.get("Type", ""), fields["kind"])
    raw = str(row.get("Effect") or "").strip()
    label = fields["display_name"]

    clauses = split_top(raw, ";")
    last_trigger = None  # for continuation effects
    pending_weapon = None
    for clause in clauses:
        # split prefix : payload at depth 0
        head, _, payload = _split_head(clause)
        key = head.strip()
        kl = key.lower()
        kl0 = kl.split()[0] if kl else ""

        if kl0 == "passive":
            fields["stat_bonuses"].update(parse_passive(payload))
            last_trigger = None
        elif kl0 == "stat_multiply":
            fields["stat_multipliers"].update(parse_multipliers(payload))
            last_trigger = None
        elif kl0 in TRIGGER_SIGNALS:
            on = TRIGGER_SIGNALS[kl0]
            gates = _gates(kl)
            effects, boosts, addons = parse_payload(payload, default_target="self"
                                                    if on in ("combat_started", "turn_started", "turn_ended", "item_acquired")
                                                    else "enemy")
            _apply_labels(effects, label)
            trig = {"on": on}
            trig.update(gates)
            silent = on in ALWAYS_SILENT or _has_counter_or_streak(effects)
            if silent:
                trig["silent"] = True
            trig["effects"] = effects
            fields["triggers"].append(trig)
            last_trigger = trig
        elif kl0 == "card_grant":
            gates = _gates(kl)
            grant = {}
            if "if_card_tag" in gates:
                grant["if_card_tag"] = gates["if_card_tag"]
            if "if_card_type" in gates:
                grant["if_card_type"] = gates["if_card_type"]
            effects, boosts, addons = parse_payload(payload, default_target="enemy", in_grant=True)
            if effects:
                grant["effects"] = effects
            if boosts:
                grant["boost"] = boosts
            if addons:
                grant["addons"] = addons
            fields["card_grants"].append(grant)
            last_trigger = None
        elif kl0 == "scaling":
            fields["scaling"] = parse_scaling(payload)
            last_trigger = None
        elif kl0 == "weapon":
            fields["weapon_card_id"] = payload.strip()
            pending_weapon = True
            last_trigger = None
        elif kl0 == "verify":
            q, _, rhs = payload.partition("=>")
            fields["verification_question"] = q.strip()
            fields["verification_effects"] = parse_verify_effects(rhs)
            last_trigger = None
        elif kl0 == "perfect":
            _parse_perfect(fields, payload)
            last_trigger = None
        elif kl0 == "status_amplify":
            fields["status_amplify"] = _amp(payload)
            last_trigger = None
        elif kl0 == "status_immunity":
            # "status_immunity: weak, frail" -> PackedStringArray of status ids the
            # player can no longer gain (Ginger, Turnip).
            fields["status_immunity"] = [t.strip().lower()
                                         for t in split_top(payload, ",") if t.strip()]
            last_trigger = None
        elif kl0 == "attack_damage_bonus":
            fields["attack_damage_bonus"] = _brace_dict(payload)
            last_trigger = None
        elif kl0 == "upgrade_card_types":
            fields["upgrade_card_types"] = [payload.split()[0].strip()] if payload.split() else []
            last_trigger = None
        elif kl0 == "stat_mirror":
            fields["stat_mirror"] = _mirror(payload)
            last_trigger = None
        elif kl0 == "stat_floor":
            fields["stat_floor"] = _bracket_list(payload)
            last_trigger = None
        elif kl0 == "stat_gain_bonus":
            fields["stat_gain_bonus"] = _brace_dict(payload)
            last_trigger = None
        elif kl0 == "negate_lethal":
            fields["negate_lethal"] = True
            last_trigger = None
        elif kl0 == "reroll_low_rarity":
            fields["reroll_low_rarity"] = True
            last_trigger = None
        elif kl0 == "carries_leftover_energy":
            fields["carries_leftover_energy"] = True
            last_trigger = None
        elif kl0 == "lower_hp_damage_mult":
            fields["lower_hp_damage_mult"] = float(re.search(r"[0-9.]+", payload).group(0))
            last_trigger = None
        elif kl0.startswith("gold_spend_stat_per"):
            fields["gold_spend_stat_per"] = _int(re.search(r"\d+", clause).group(0))
            last_trigger = None
        elif kl0 == "level_up":
            mm = re.search(r"(\d+)%", payload)
            fields["bonus_level_up_chance"] = (int(mm.group(1)) / 100.0) if mm else 0.0
            last_trigger = None
        elif kl0 == "charged":
            mm = re.search(r"charge_cost\s+(\d+)", clause)
            fields["charge_cost"] = int(mm.group(1)) if mm else 0
            last_trigger = None
        else:
            # continuation: a bare effect (e.g. "if_hp above 0.5 -> lose_hp 10")
            if last_trigger is not None:
                effects, _, _ = parse_payload(clause, default_target="self")
                _apply_labels(effects, label)
                last_trigger["effects"].extend(effects)

    # An item that runs an overworld_jump (Winged Boots) is usable on the map, so
    # mark it: the runtime enables its backpack / overworld-HUD use button there.
    for trig in fields["triggers"]:
        for eff in trig.get("effects", []):
            if isinstance(eff, dict) and eff.get("type") == "overworld_jump":
                fields["overworld_usable"] = True

    return fields


def _split_head(clause):
    """Split a clause into (head, ':', payload) at depth-0 first colon, but not
    on a '://' or inside brackets. The head is the trigger prefix + gates."""
    depth = 0
    for i, ch in enumerate(clause):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        elif ch == ":" and depth == 0:
            return clause[:i], ":", clause[i + 1:]
    return clause, "", ""


def _gates(head_lower):
    g = {}
    for m in re.finditer(r"if_turn\s*=\s*(\d+)", head_lower):
        g["if_turn"] = int(m.group(1))
    for m in re.finditer(r"if_type\s*=\s*([a-z_]+)", head_lower):
        g["if_card_type"] = m.group(1)
    for m in re.finditer(r"if_tag\s*=\s*([a-z_]+)", head_lower):
        g["if_card_tag"] = m.group(1)
    return g


def _has_counter_or_streak(effects):
    for e in effects:
        if e.get("type") in ("counter", "streak_hit", "streak_reset"):
            return True
    return False


def _apply_labels(effects, label):
    for e in effects:
        if e.get("type") in ("counter", "streak_hit"):
            e["label"] = label
            _apply_labels(e.get("effects", []), label)


def _parse_perfect(fields, payload):
    p = payload.strip()
    m = re.search(r"(\d+)%\s*to\s*treat", p, re.I)
    if "verify" in p.lower() and m:
        fields["perfect_save_chance"] = int(m.group(1)) / 100.0
        fields["perfect_aware"] = True
        return
    eff = parse_one_effect(p, "self")
    if isinstance(eff, dict):
        fields["perfect_effects"] = [eff]
        fields["perfect_aware"] = True


def _amp(payload):
    out = {}
    for part in split_top(payload, ","):
        part, _, _ = strip_notes(part)
        m = re.match(r"^([+-]?\d+)\s+([a-z_]+)$", part)
        if m:
            out[m.group(2)] = int(m.group(1))
    return out


def _brace_dict(payload):
    m = re.search(r"\{([^}]*)\}", payload)
    inner = m.group(1) if m else payload
    out = {}
    for part in inner.split(","):
        if ":" in part:
            k, v = part.split(":", 1)
            out[k.strip()] = _int(v.strip())
    return out


def _mirror(payload):
    m = re.search(r"\{(.*)\}", payload)
    inner = m.group(1) if m else payload
    km = re.match(r"\s*([a-z_]+)\s*:\s*\[([^\]]*)\]", inner)
    if km:
        return {km.group(1): [x.strip() for x in km.group(2).split(",") if x.strip()]}
    return {}


def _bracket_list(payload):
    m = re.search(r"\[([^\]]*)\]", payload)
    inner = m.group(1) if m else payload
    return [x.strip() for x in inner.split(",") if x.strip()]


# --------------------------------------------------------------------------
# .tres emission
# --------------------------------------------------------------------------

def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def packed(items) -> str:
    return "PackedStringArray(%s)" % ", ".join('"%s"' % gd_str(i) for i in items)


def gd_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return '"%s"' % gd_str(v)
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join('"%s": %s' % (gd_str(k), gd_value(val)) for k, val in v.items()) + "}"
    raise TypeError(type(v))


def item_tres(row):
    f = parse_item(row)
    iid = f["id"]
    img_name = display_of(str(row["Name"]).strip())
    img_file = str(row.get("File") or "").strip() or img_name
    img_res = None
    for cand in (img_file, img_name):
        if os.path.exists(os.path.join(ITEM_IMG_DIR, cand + ".png")):
            img_res = "res://images/items/%s.png" % cand
            break

    lines = []
    load_steps = 3 if img_res else 2
    lines.append('[gd_resource type="Resource" script_class="ItemData" load_steps=%d '
                 'format=3 uid="uid://item_%s"]' % (load_steps, iid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/ItemData.gd" id="1_item"]')
    if img_res:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img_res)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_item")')
    lines.append('id = &"%s"' % iid)
    lines.append('display_name = "%s"' % gd_str(f["display_name"]))
    lines.append("kind = %d" % f["kind"])
    lines.append("rarity = %d" % f["rarity"])
    if f.get("starter"):
        lines.append("starter = true")
    lines.append('description = "%s"' % gd_str(f["description"]))
    lines.append("triggers = %s" % gd_value(f["triggers"]))
    if f["card_grants"]:
        lines.append("card_grants = %s" % gd_value(f["card_grants"]))
    lines.append("stat_bonuses = %s" % gd_value(f["stat_bonuses"]))
    if f.get("stat_multipliers"):
        lines.append("stat_multipliers = %s" % gd_value(f["stat_multipliers"]))
    if f["scaling"]:
        lines.append("scaling = %s" % gd_value(f["scaling"]))
    # one-off fields, emitted only when present
    for key, gd in [
        ("status_amplify", lambda v: gd_value(v)),
        ("status_immunity", lambda v: packed(v)),
        ("upgrade_card_types", lambda v: packed(v)),
        ("attack_damage_bonus", lambda v: gd_value(v)),
        ("carries_leftover_energy", lambda v: "true"),
        ("lower_hp_damage_mult", lambda v: str(v)),
        ("gold_spend_stat_per", lambda v: str(v)),
        ("stat_mirror", lambda v: gd_value(v)),
        ("stat_floor", lambda v: packed(v)),
        ("negate_lethal", lambda v: "true"),
        ("stat_gain_bonus", lambda v: gd_value(v)),
        ("reroll_low_rarity", lambda v: "true"),
        ("overworld_usable", lambda v: "true"),
        ("charge_cost", lambda v: str(v)),
        ("weapon_card_id", lambda v: '&"%s"' % gd_str(v)),
        ("verification_question", lambda v: '"%s"' % gd_str(v)),
        ("verification_effects", lambda v: gd_value(v)),
        ("perfect_aware", lambda v: "true"),
        ("perfect_effects", lambda v: gd_value(v)),
        ("perfect_save_chance", lambda v: str(v)),
        ("bonus_level_up_chance", lambda v: str(v)),
    ]:
        if key in f and f[key] not in (None, [], {}, 0, False, ""):
            lines.append("%s = %s" % (key, gd(f[key])))
    if f["kind"] == KIND["charged"] or f.get("charge_cost"):
        lines.append("starts_charged = true")
    else:
        lines.append("max_uses = %d" % f["max_uses"])
    src = str(row.get("Reference") or row.get("Game") or "").strip()
    # source_game comes from the existing .tres; keep blank if unknown
    lines.append('source_game = "%s"' % gd_str(src if src.upper() not in ("", "N/A") else ""))
    tags = [t.strip() for t in str(row.get("tags") or "").split(",")
            if t.strip() and t.strip().lower() not in ("n/a", "none")]
    lines.append("tags = %s" % packed(tags))
    if img_res:
        lines.append('image = ExtResource("2_img")')
    return iid, "\n".join(lines) + "\n"


def rows(sheet):
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for r in sheet.iter_rows(min_row=2, values_only=True):
        if not r or r[0] is None:
            continue
        yield dict(zip(headers, r))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true",
                    help="also emit rows that have no existing .tres yet")
    ap.add_argument("--list", action="store_true",
                    help="print parses, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    sheet = wb["items"]
    existing = {f[:-5] for f in os.listdir(OUT_DIR) if f.endswith(".tres")}

    written = []
    for row in rows(sheet):
        iid = slugify(str(row["Name"]).strip())
        if not args.all and iid not in existing:
            continue
        iid2, text = item_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (iid2, text))
            continue
        with open(os.path.join(OUT_DIR, iid2 + ".tres"), "w", encoding="utf-8") as fh:
            fh.write(text)
        written.append(iid2)
    if not args.list:
        print("Wrote %d item .tres to %s" % (len(written), OUT_DIR))


if __name__ == "__main__":
    main()
