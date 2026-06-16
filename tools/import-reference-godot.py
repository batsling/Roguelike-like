#!/usr/bin/env python3
"""
Generate the Godot reference catalog (statuses + addons) from
tools/Roguelikes.xlsx.

Reads the `statusesnew` and `addonsnew` sheets — the set actually wired into
the Godot build — and writes scripts/data/ReferenceCatalog.gd, a
script exposing two const Arrays the Collection screen renders. Mirrors the
other tools/import-*-godot.py importers (data lives in the sheet, code is
generated) so the catalog stays in sync with the Excel source.
"""

import openpyxl
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx")
OUT_PATH = os.path.join(PROJECT_ROOT, "scripts", "data", "ReferenceCatalog.gd")
STATUS_ICON_DIR = os.path.join(PROJECT_ROOT, "images", "statuses")


def esc(s) -> str:
    s = "" if s is None else str(s).strip()
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").replace("\r", " ")


def yes(v) -> str:
    return "true" if str(v).strip().lower() in ("yes", "true", "y", "1") else "false"


def slugify(name) -> str:
    # Mirrors generate_card_tres.slugify so an addon's runtime key matches the
    # slug baked into CardData.addons ("Fishing Weight" -> fishing_weight). Used
    # as the fallback when the sheet's Key column is blank.
    s = ("" if name is None else str(name)).strip().lower()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def rows(sheet):
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for row in sheet.iter_rows(min_row=2, values_only=True):
        if not row or row[0] is None or str(row[0]).strip() == "":
            continue
        yield {headers[i]: row[i] for i in range(min(len(headers), len(row)))}


def main() -> int:
    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    for need in ("statusesnew", "addonsnew"):
        if need not in wb.sheetnames:
            print(f"ERROR: sheet '{need}' missing", file=sys.stderr)
            return 1

    status_lines = []
    missing_icons = []
    for r in rows(wb["statusesnew"]):
        icon = esc(r.get("Icon"))
        if icon and not os.path.exists(os.path.join(STATUS_ICON_DIR, icon + ".png")):
            missing_icons.append(icon)
        status_lines.append(
            "\t{{ \"name\": \"{name}\", \"description\": \"{desc}\", \"type\": \"{type}\", "
            "\"stackable\": {stack}, \"decay\": \"{decay}\", \"who\": \"{who}\", "
            "\"preference\": \"{pref}\", \"rarity\": \"{rar}\", \"icon\": \"{icon}\" }},".format(
                name=esc(r.get("Name")), desc=esc(r.get("Description")), type=esc(r.get("Type")),
                stack=yes(r.get("Stackable")), decay=esc(r.get("Decay")), who=esc(r.get("Who")),
                pref=esc(r.get("Preference")), rar=esc(r.get("Rarity")), icon=icon))

    addon_lines = []
    for r in rows(wb["addonsnew"]):
        # Machine-readable DSL columns (see docs/addon-sheet-authoring-handoff.md):
        #   Key  — runtime slug the engine matches (falls back to slugify(Name))
        #   Hook — which dispatch slot the behavior runs in (effect_dmg_bonus /
        #          effect_retarget / effect_flag drive AddonSystem today; the
        #          effect_value / card_replay / structural rows are declarative
        #          for now and handled elsewhere).
        #   Expr — closed-vocabulary parameter for the hook (gold/10, fish,
        #          enemy->all_enemies, indiscriminate, …); empty for the rest.
        key = esc(r.get("Key")) or slugify(r.get("Name"))
        addon_lines.append(
            "\t{{ \"name\": \"{name}\", \"deckbuilder\": \"{db}\", \"action\": \"{ac}\", "
            "\"strategy\": \"{st}\", \"has_value\": {hv}, \"attaches_to\": \"{at}\", "
            "\"forms\": \"{forms}\", \"key\": \"{key}\", \"hook\": \"{hook}\", "
            "\"expr\": \"{expr}\" }},".format(
                name=esc(r.get("Name")), db=esc(r.get("Deckbuilder")), ac=esc(r.get("Action")),
                st=esc(r.get("Strategy")), hv=yes(r.get("Has Value")),
                at=esc(r.get("Can Be Attatched To")),
                forms=esc("" if str(r.get("Forms")).strip() in ("N/A", "None") else r.get("Forms")),
                key=key, hook=esc(r.get("Hook")), expr=esc(r.get("Expr"))))

    out = []
    out.append("class_name ReferenceCatalog")
    out.append("")
    out.append("# AUTO-GENERATED from tools/Roguelikes.xlsx (statusesnew + addonsnew sheets)")
    out.append("# by scripts/import-reference-godot.py. Do not edit by hand — re-run the")
    out.append("# importer instead. Drives the Collection screen's Reference tab; the set")
    out.append("# here matches the statuses/addons actually wired into the Godot build.")
    out.append("")
    out.append("const STATUSES: Array = [")
    out.extend(status_lines)
    out.append("]")
    out.append("")
    out.append("const ADDONS: Array = [")
    out.extend(addon_lines)
    out.append("]")
    out.append("")

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(out))

    print(f"[import-reference-godot] {len(status_lines)} statuses, {len(addon_lines)} addons "
          f"-> {os.path.relpath(OUT_PATH, PROJECT_ROOT)}")
    if missing_icons:
        print(f"[import-reference-godot] WARNING missing status icons: {missing_icons}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
