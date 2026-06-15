#!/usr/bin/env python3
"""Generate Godot EventData .tres files from the `events` sheet of
tools/Roguelikes.xlsx, merged with the authored choice/outcome trees.

The spreadsheet is the single source of truth for an event's *catalogue
metadata* — Game, Type, Difficulty, Difficulty Roll, Rarity, Possible
Inputs / Outputs, Multipath, Img, Run Limit, Requirement, Tags. The
narrative (prompt + choices + outcomes + effects) is not in the sheet, so
it is authored here in AUTHORED, keyed by the row's `Img` value.

A row is only emitted if its `Img` has an authored entry, so partial /
freeform rows in the sheet are skipped until someone writes their choices.

Re-run after editing the sheet or AUTHORED:

    python3 tools/generate_event_tres.py

Reads the .xlsx with the stdlib (zipfile + ElementTree) so it needs no
third-party packages.
"""
import os
import re
import zipfile
from xml.etree import ElementTree as ET

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
XLSX_PATH = os.path.join(ROOT, "tools", "Roguelikes.xlsx")
OUT_DIR = os.path.join(ROOT, "data", "events")
EVENTS_SHEET = "events"
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


# ---------------------------------------------------------------------------
# Minimal .xlsx reader (stdlib only)
# ---------------------------------------------------------------------------

def _col_index(ref: str) -> int:
    letters = re.match(r"[A-Z]+", ref).group(0)
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def read_sheet(xlsx_path: str, sheet_name: str) -> list[dict]:
    """Return the sheet as a list of {header: value} dicts (row 1 = headers)."""
    z = zipfile.ZipFile(xlsx_path)

    shared: list[str] = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root.findall(NS + "si"):
            shared.append("".join(t.text or "" for t in si.iter(NS + "t")))

    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    rid_to_target = {
        r.get("Id"): r.get("Target")
        for r in rels
    }
    target = None
    for sheet in wb.iter(NS + "sheet"):
        if sheet.get("name") == sheet_name:
            rid = sheet.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
            target = rid_to_target[rid]
            break
    if target is None:
        raise KeyError(f"sheet {sheet_name!r} not found")
    if not target.startswith("xl/"):
        target = "xl/" + target

    grid: list[list[str]] = []
    root = ET.fromstring(z.read(target))
    for row in root.iter(NS + "row"):
        cells: dict[int, str] = {}
        max_c = -1
        for c in row.findall(NS + "c"):
            idx = _col_index(c.get("r"))
            t = c.get("t")
            v = c.find(NS + "v")
            inline = c.find(NS + "is")
            val = ""
            if t == "s" and v is not None:
                val = shared[int(v.text)]
            elif inline is not None:
                val = "".join(x.text or "" for x in inline.iter(NS + "t"))
            elif v is not None:
                val = v.text
            cells[idx] = (val or "").strip()
            max_c = max(max_c, idx)
        grid.append([cells.get(i, "") for i in range(max_c + 1)])

    if not grid:
        return []
    headers = grid[0]
    out = []
    for raw in grid[1:]:
        if not any(raw):
            continue
        out.append({headers[i]: (raw[i] if i < len(raw) else "") for i in range(len(headers))})
    return out


# ---------------------------------------------------------------------------
# Authored narrative — keyed by the sheet's Img value
# ---------------------------------------------------------------------------

def _sc(text, stat, outcomes, cid):
    return {"id": cid, "text": text, "type": "stat_check", "stat": stat, "outcomes": outcomes}


def _simple(text, desc, effects, cid):
    return {"id": cid, "text": text, "type": "simple", "outcome": {"description": desc, "effects": effects}}


def _o(desc, effects):
    return {"description": desc, "effects": effects}


_SERPENT_GOLD = ('Serpent: "Yeeeeeeessssssssssessss" Serpent: "Thisss will all be worthhh it." '
                 'Serpent: "..ssSSs..... ss... sssss....!" The serpent rears its head and blasts a '
                 'stream of gold upwards! It is amazing and terrifying simultaneously. You gather all '
                 'the gold, thank the snake, and get going.')

AUTHORED = {
    "WatchingEyeballs": {
        "id": "watching_eyeballs",
        "prompt": "{name} stumbles upon a dark hole. Numerous eyes peer out from the darkness.",
        "choices": [
            _sc("Sneak By", "dexterity", {
                "crit_good": _o("{name} sneaks by the spooky looking crack, getting into a position to ambush!", [{"type": "combat_flag", "flag": "ambush"}]),
                "good": _o("{name} carefully sneaks by the wall and nothing appears to happen.", [{"type": "none"}]),
                "bad": _o("The eyes glare directly at {name} as {name} attempts to sneak by... {name} bolts into a sprint in order to get away as quickly as possible!", [{"type": "combat_status", "status": "fear", "stacks": 1}]),
                "crit_bad": _o("{name} approaches the crack in the wall, trying to discern what creature's eyes are staring at it... The unnerving gaze of the eyeballs terrifies {name}, and they run for their life, right into an ambush!", [{"type": "combat_status", "status": "fear", "stacks": 2}, {"type": "combat_flag", "flag": "ambushed"}]),
            }, "sneak"),
            _sc("Examine", "intelligence", {
                "crit_good": _o("{name} discovers the scary looking eyes were just large coins, glinting in the dim light!", [{"type": "item_tagged", "tag": "coin"}]),
                "good": _o("After closer examination, {name} discovers it was just a trick of the light... The eyes were coins!", [{"type": "gold_range", "min": 10, "max": 20}]),
                "bad": _o("{name} looks directly at the eyes, no one wanting to move first. Their eyes begin to water in pain as they resist the urge to blink. {name} doesn't say anything and turns and runs in terror!", [{"type": "combat_status", "status": "fear", "stacks": 2}]),
                "crit_bad": _o("{name} moves its face close to the hole and peers inside... {name} howls in pain as something sharp from within the hole lashes out and stabs its eye! Get an Eye Item.", [{"type": "active_curse", "curse": "curse_of_ocular_trauma"}, {"type": "item_tagged", "tag": "eye"}]),
            }, "examine"),
            _sc("Bash", "strength", {
                "crit_good": _o("{name} bats at the eyes with lightning fast strikes, dispatching them with ease!", [{"type": "item_tagged", "tag": "eye"}]),
                "good": _o("{name} smashes the eyes into concave lumps of flesh!", [{"type": "heal", "value": 5}]),
                "bad": _o("{name} moves closely to strike the eyes, but they suddenly flash with a blinding brightness!", [{"type": "combat_status", "status": "blind", "stacks": 4}]),
                "crit_bad": _o("{name} reaches into the dark hole with its arm to swat at the eyes, but pokes themself in the face on the sharp edges of the hole instead! Get an Eye Item.", [{"type": "active_curse", "curse": "curse_of_ocular_trauma"}, {"type": "item_tagged", "tag": "eye"}]),
            }, "bash"),
        ],
    },
    "FruitBasket": {
        "id": "fruit_basket",
        "prompt": "{name} discovers a basket of fruit. The warm smell of fresh citrus and bananas lingers in the air. A refreshing reprieve!",
        "choices": [
            _sc("Eat", "constitution", {
                "crit_good": _o("The fruit is tasty! {name} gobbles up the whole basket.", [{"type": "heal_percent", "value": 50}]),
                "good": _o("Warm juice from the fruit runs down their chin as {name} devours the delicious fruit.", [{"type": "heal_percent", "value": 20}]),
                "bad": _o("{name} bites into a piece of fruit, then spits it out in disgust! It's poisoned!", [{"type": "combat_status", "status": "poison", "stacks": 3}]),
                "crit_bad": _o("The fruit tastes great, at first... But after {name} devours it, they look down and notice that the remains are all rotted. {name} begins to feel sick as poison sets in...", [{"type": "combat_status", "status": "poison", "stacks": 4}]),
            }, "fruit_eat"),
            _sc("Destroy", "strength", {
                "crit_good": _o("{name} tears open the fruit and pokes through the remains, looking for something useful...", [{"type": "item_tagged", "tag": "seed"}]),
                "good": _o("{name} crushes the fruit, spraying juice everywhere. It smells nice but nothing happens...", [{"type": "none"}]),
                "bad": _o("{name} pushes the basket of fruit over and steps on the fruit, squeezing their juices out onto the ground.", [{"type": "none"}]),
                "crit_bad": _o("{name} smashes the fruit, and a swarm of fruit flies surround {name}!", [{"type": "spawn_enemies", "enemy": "fly", "min": 6, "max": 8}]),
            }, "fruit_destroy"),
            _sc("Examine", "intelligence", {
                "crit_good": _o("Upon closer inspection, {name} notices that the fruit is shimmering in the dim light. {name} carefully bites into the ripe fruit... It's the most delicious thing they've ever tasted!", [{"type": "heal", "value": 15}, {"type": "combat_status", "status": "buffer", "stacks": 1}]),
                "good": _o("{name} examines the fruit in the basket and finds one that looks fresh.", [{"type": "heal", "value": 5}]),
                "bad": _o("As {name} was examining the fruit, {name} was not paying attention to its surroundings... It's a trap!", [{"type": "combat_flag", "flag": "ambushed"}]),
                "crit_bad": _o("{name} picks up one of the strange fruits, and it rots in its hands! {name} jumps back in fear as the whole basket begins to rapidly decompose!", [{"type": "combat_status", "status": "fear", "stacks": 5}]),
            }, "fruit_examine"),
        ],
    },
    "ANoteForYourself": {
        "id": "note_for_yourself",
        "prompt": "You spot a loose brick within a pillar that catches your eye.",
        "choices": [
            _simple("Take and Give", 'You find a folded note and {storedCard} inside. It reads "The Heart awaits." This is your handwriting.', [{"type": "note_for_yourself", "default_card": "iron_wave"}], "take_and_give"),
            _simple("Ignore", '"What is going on?"', [{"type": "none"}], "ignore"),
        ],
    },
    "TheSsssserpent": {
        "id": "the_ssssserpent",
        "prompt": ('You walk into a room to find a large hole in the ground. As you approach the hole, an '
                   'enormous serpent creature appears from within. Serpent: "Ho hooo! Hello hello! what '
                   'have we got here? Hello adventurer, I ask a simple question." Serpent: "The most '
                   'fulfilling of lives is that in which you can buy anything!" Serpent: "Do you agree?"'),
        "choices": [
            _simple("Agree", _SERPENT_GOLD, [{"type": "gain_gold", "value": 100}, {"type": "curse_card", "card": "greed"}], "serpent_agree"),
            _sc("Charm", "charisma", {
                "crit_good": _o(_SERPENT_GOLD, [{"type": "gain_gold", "value": 150}, {"type": "curse_card", "card": "greed"}]),
                "good": _o(_SERPENT_GOLD, [{"type": "gain_gold", "value": 125}, {"type": "curse_card", "card": "greed"}]),
                "bad": _o(_SERPENT_GOLD, [{"type": "gain_gold", "value": 75}, {"type": "curse_card", "card": "greed"}]),
                "crit_bad": _o(_SERPENT_GOLD, [{"type": "gain_gold", "value": 50}, {"type": "curse_card", "card": "greed"}]),
            }, "serpent_charm"),
            _simple("Disagree", "The serpent stares at you with a look of extreme disappointment.", [{"type": "none"}], "serpent_disagree"),
        ],
    },
}

ALL_DIFFS = ["easy", "medium", "hard", "insane"]


# ---------------------------------------------------------------------------
# Row -> .tres
# ---------------------------------------------------------------------------

def _split_list(cell: str) -> list[str]:
    if not cell or cell.strip().upper() in ("N/A", "NONE", ""):
        return []
    return [p.strip() for p in cell.split(",") if p.strip()]


def _difficulty_tags(cell: str) -> list[str]:
    c = (cell or "").strip()
    if not c or c.lower() == "all":
        return []
    return [d.strip().lower() for d in c.split(",") if d.strip()]


def _run_limit(cell: str) -> int:
    c = (cell or "").strip()
    if not c or c.upper() == "N/A":
        return 0
    try:
        return int(float(c))
    except ValueError:
        return 0


def _int(cell: str) -> int:
    try:
        return int(float((cell or "0").strip()))
    except ValueError:
        return 0


def _esc(s: str) -> str:
    return (s or "").replace("\\", "\\\\").replace('"', '\\"')


def fmt_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return f'"{_esc(v)}"'
    if isinstance(v, list):
        return "[" + ", ".join(fmt_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{fmt_value(k)}: {fmt_value(val)}" for k, val in v.items()) + "}"
    raise TypeError(f"Unsupported value type {type(v).__name__}: {v!r}")


def _packed(items: list[str]) -> str:
    return "PackedStringArray(" + ", ".join(f'"{_esc(i)}"' for i in items) + ")"


def emit_tres(row: dict, authored: dict) -> str:
    eid = authored["id"]
    img = (row.get("Img") or "").strip()
    has_img = bool(img)
    load_steps = 3 if has_img else 2

    lines = [
        f'[gd_resource type="Resource" script_class="EventData" load_steps={load_steps} format=3 uid="uid://event_{eid}"]',
        "",
        '[ext_resource type="Script" path="res://scripts/resources/EventData.gd" id="1_event"]',
    ]
    if has_img:
        lines.append(f'[ext_resource type="Texture2D" path="res://images/events/{img}.png" id="2_img"]')
    lines += [
        "",
        "[resource]",
        'script = ExtResource("1_event")',
        f'id = &"{eid}"',
        f'display_name = "{_esc(row.get("Name", ""))}"',
        f'prompt = "{_esc(authored["prompt"])}"',
        f'choices = {fmt_value(authored["choices"])}',
        f'difficulty_tags = {_packed(_difficulty_tags(row.get("Difficulty", "")))}',
        f'run_limit = {_run_limit(row.get("Run Limit", ""))}',
        f'source_game = "{_esc(row.get("Game", ""))}"',
        f'rarity = "{_esc(row.get("Rarity", "Common") or "Common")}"',
        f'tags = {_packed(_split_list(row.get("Tags", "")))}',
        f'event_type = "{_esc(row.get("Type", ""))}"',
        f'difficulty_roll = {_int(row.get("Diffuculty Roll", row.get("Difficulty Roll", "0")))}',
        f'requirement = "{_esc(row.get("Requirement", "None") or "None")}"',
        f'inputs = {_packed(_split_list(row.get("Possible Inputs", "")))}',
        f'outputs = {_packed(_split_list(row.get("Possible Outputs", "")))}',
        f'multipath = {"true" if (row.get("Multipath", "").strip().lower() == "yes") else "false"}',
    ]
    if has_img:
        lines.append('image = ExtResource("2_img")')
    return "\n".join(lines) + "\n"


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rows = read_sheet(XLSX_PATH, EVENTS_SHEET)
    written = 0
    for row in rows:
        img = (row.get("Img") or "").strip()
        authored = AUTHORED.get(img)
        if authored is None:
            continue
        path = os.path.join(OUT_DIR, f"{authored['id']}.tres")
        with open(path, "w") as f:
            f.write(emit_tres(row, authored))
        print(f"Wrote {path}")
        written += 1
    print(f"Done — {written} event(s) imported from the '{EVENTS_SHEET}' sheet.")


if __name__ == "__main__":
    main()
