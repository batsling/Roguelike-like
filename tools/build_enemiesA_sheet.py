#!/usr/bin/env python3
"""
Build the `enemiesA` sheet (action-mode enemies) in tools/Roguelikes.xlsx.

Action enemies use a different schema from deckbuilder (`enemiesD`) — they are
real-time creatures with positions, projectiles and frame animations rather
than turn-based move patterns. The columns mirror ActionEnemyData.gd, with two
authoring conveniences:

  * `Size` is player-relative: 1 = the player's starting size. The importer
    (tools/generate_action_enemy_tres.py) multiplies by the player radius to get
    pixels.
  * `Animations` is a packed cell declaring which frame animations the enemy has
    and how to play / slice them. Grammar (`;`-separated):

        <name> @ <fps> <loop|once> [grid WxH]

    e.g.  idle @ 4 loop ; attack @ 8 once grid 32x32
    - no `grid` clause  -> the whole source PNG is a single frame
    - `grid WxH`        -> the source PNG is sliced into WxH cells, left-to-right
                           then top-to-bottom
    Source art lives in images/enemies/action_enemies/<Name>/, one PNG per
    animation named <id>_<anim>*.png (e.g. horf_idle.png, horf_attack_1.png).

Re-run safe: drops and rebuilds `enemiesA` each time. Leaves every other sheet
untouched.
"""

import os
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
XLSX_PATH = os.path.join(SCRIPT_DIR, "Roguelikes.xlsx")

HEADERS = [
    "Name", "Id", "Difficulty", "Weight", "Game", "Tag",
    "Min HP", "Max HP", "Contact Damage", "Attack Cooldown", "Attack Windup",
    "Attack Range", "Preferred Distance", "Projectile Speed", "Projectile Lifetime",
    "Move Speed", "Size", "Behavior",
    "Color", "Directional", "Layers", "Animations", "Ability",
]

# One dict per action enemy, keyed by HEADERS.
# NOTE: Gaper/Pacer/Gusher ship with empty Layers/Animations for now, so they
# render as colored circles until the body/head/gush art is sliced and wired
# (pending the body sheet direction mapping). Their mechanics already work.
ENEMIES = [
    {
        "Name": "Horf", "Id": "horf", "Difficulty": "Low", "Weight": 2,
        "Game": "The Binding of Isaac", "Tag": "",
        "Min HP": 25, "Max HP": 25, "Contact Damage": 6,
        "Attack Cooldown": 2.2, "Attack Windup": 0.35, "Attack Range": 480,
        "Preferred Distance": 0, "Projectile Speed": 200,
        "Projectile Lifetime": 5.0, "Move Speed": 0, "Size": 1,
        "Behavior": "Stationary",
        "Color": "0.8,0.1,0.1", "Directional": "No",
        "Layers": "", "Animations": "idle @ 4 loop ; attack @ 12 once grid 32x32",
        "Ability": "",
    },
    {
        "Name": "Gaper", "Id": "gaper", "Difficulty": "Low", "Weight": 3,
        "Game": "The Binding of Isaac", "Tag": "",
        "Min HP": 25, "Max HP": 25, "Contact Damage": 6,
        "Attack Cooldown": 1.0, "Attack Windup": 0.0, "Attack Range": 40,
        "Preferred Distance": 0, "Projectile Speed": 0,
        "Projectile Lifetime": 0, "Move Speed": 90, "Size": 1,
        "Behavior": "Walker",
        "Color": "0.9,0.6,0.55", "Directional": "No",
        "Layers": "", "Animations": "",
        "Ability": "OnDeath(pacer:80, gusher:20)",
    },
    {
        "Name": "Pacer", "Id": "pacer", "Difficulty": "Low", "Weight": 0,
        "Game": "The Binding of Isaac", "Tag": "",
        "Min HP": 25, "Max HP": 25, "Contact Damage": 6,
        "Attack Cooldown": 1.0, "Attack Windup": 0.0, "Attack Range": 40,
        "Preferred Distance": 0, "Projectile Speed": 0,
        "Projectile Lifetime": 0, "Move Speed": 70, "Size": 1,
        "Behavior": "Pacer",
        "Color": "0.85,0.5,0.5", "Directional": "No",
        "Layers": "", "Animations": "",
        "Ability": "",
    },
    {
        "Name": "Gusher", "Id": "gusher", "Difficulty": "Low", "Weight": 0,
        "Game": "The Binding of Isaac", "Tag": "",
        "Min HP": 25, "Max HP": 25, "Contact Damage": 6,
        "Attack Cooldown": 1.2, "Attack Windup": 0.0, "Attack Range": 40,
        "Preferred Distance": 0, "Projectile Speed": 180,
        "Projectile Lifetime": 3.0, "Move Speed": 60, "Size": 1,
        "Behavior": "Pacer",
        "Color": "0.7,0.1,0.1", "Directional": "No",
        "Layers": "", "Animations": "",
        "Ability": "RandomShots(count=1)",
    },
]


def main() -> int:
    wb = openpyxl.load_workbook(XLSX_PATH)  # default keeps formulas/tables

    if "enemiesA" in wb.sheetnames:
        del wb["enemiesA"]
    ws = wb.create_sheet("enemiesA")

    head_fill = PatternFill("solid", fgColor="7F2D2D")
    head_font = Font(bold=True, color="FFFFFF")
    for ci, name in enumerate(HEADERS, start=1):
        c = ws.cell(row=1, column=ci, value=name)
        c.fill = head_fill
        c.font = head_font

    wrap = Alignment(vertical="top", wrap_text=True)
    for ri, rec in enumerate(ENEMIES, start=2):
        for ci, name in enumerate(HEADERS, start=1):
            c = ws.cell(row=ri, column=ci, value=rec.get(name, ""))
            if name in ("Animations", "Ability", "Layers"):
                c.alignment = wrap

    widths = {"Name": 14, "Id": 12, "Game": 20, "Animations": 42,
              "Color": 14, "Behavior": 12, "Layers": 18, "Ability": 30}
    for ci, name in enumerate(HEADERS, start=1):
        ws.column_dimensions[ws.cell(row=1, column=ci).column_letter].width = widths.get(name, 11)
    ws.freeze_panes = "A2"

    wb.save(XLSX_PATH)
    print(f"[build_enemiesA] wrote enemiesA with {len(ENEMIES)} action enemies")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
