#!/usr/bin/env python3
"""
Generate Godot ActionEnemyData .tres files from the `enemiesA` sheet (action
enemies) in tools/Roguelikes.xlsx, slicing and normalising their frame art.

Mirrors tools/generate_enemy_tres.py (deckbuilder), but for real-time action
enemies. For each row it:

  * parses the schema columns into ActionEnemyData fields;
  * converts the player-relative `Size` to pixels (1 == PLAYER_RADIUS);
  * parses the packed `Animations` cell, locates each animation's source PNG in
    images/enemies/action_enemies/<Name>/ (named <id>_<anim>*.png), slices it by
    the declared grid (or treats the whole image as one frame), then NORMALISES
    every frame of the enemy onto a common square canvas: each frame is trimmed
    to its opaque bounds and re-centred on a square sized to the largest frame,
    so idle/attack/… share one scale and the head never pops between anims;
  * writes the per-frame PNGs to assets/enemies/<id>/<anim>_<i>.png and the
    .tres to data/action_enemies/<id>.tres.

Re-run safe: wipes each enemy's generated assets/enemies/<id>/ folder and its
.tres before rewriting. Hand-authored enemies in PRESERVE are left alone.

Requires: openpyxl, Pillow.
"""

import os
import re
import shutil

import openpyxl
from PIL import Image

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.path.join(SCRIPT_DIR, "Roguelikes.xlsx")
ART_SRC_ROOT = os.path.join(PROJECT_ROOT, "images", "enemies", "action_enemies")
ASSETS_OUT_ROOT = os.path.join(PROJECT_ROOT, "assets", "enemies")
TRES_OUT_DIR = os.path.join(PROJECT_ROOT, "data", "action_enemies")

# Hand-authored placeholder enemies that aren't on the sheet — never touch them.
PRESERVE = {"walker", "shooter"}

# Keep in sync with ActionCombat.PLAYER_RADIUS: `Size` is player-relative, so a
# sheet value of 1 maps to this many pixels of collision radius.
PLAYER_RADIUS = 18.0

DIFFICULTY = {"low": 0, "medium": 1, "med": 1, "high": 2, "boss": 3}
BEHAVIOR = {"walker": 0, "shooter": 1, "stationary": 2, "pacer": 3}

# Composite / directional sheet enemies. Cell-based slicing is too irregular for
# the Animations column, so it lives here. Each enemy is a list of layers (drawn
# back-to-front); each layer has a draw offset (source px, scaled by Size at
# draw) and a list of (anim_name, fps, loop, source) animations. `source` is
# ("file", path) for a whole-image single frame, or ("sheet", path, cell,
# [(row,col),...]) for cells out of a grid. Paths are relative to ART_SRC_ROOT.
# Facing is baked into the anim name suffix: walk_vert (up & down), walk_side
# (left = mirror of right). idle/idle_side resolve with a fallback to idle.
_GAPER_VERT = [(0, 1), (0, 2), (0, 3), (1, 0), (1, 1), (1, 2), (1, 3), (2, 0), (2, 1)]
_GAPER_SIDE = [(2, 2), (2, 3), (3, 0), (3, 1), (3, 2), (3, 3), (4, 0), (4, 1), (4, 2), (4, 3)]
_PACER_SIDE = [(2, 3), (3, 0), (3, 1), (3, 2), (3, 3), (4, 0), (4, 1), (4, 2), (4, 3)]

def _body_anims(sheet, vert, side, side_idle=None):
    a = [
        ("idle", 5.0, True, ("sheet", sheet, 32, [(0, 0)])),
        ("walk_vert", 12.0, True, ("sheet", sheet, 32, vert)),
        ("walk_side", 12.0, True, ("sheet", sheet, 32, side)),
    ]
    if side_idle is not None:
        a.append(("idle_side", 5.0, True, ("sheet", sheet, 32, [side_idle])))
    return a

LAYER_SLICES = {
    "gaper": [
        {"layer": "body", "offset": (0.0, 0.0),
         "anims": _body_anims("Gaper/gaper_body_sheet.png", _GAPER_VERT, _GAPER_SIDE)},
        {"layer": "head", "offset": (0.0, -10.0), "anims": [
            # Idle = the open-eyed bloody resting head (head-only frame 0,1), NOT
            # gaper_idle.png which is a full head+body sprite and would double the
            # body. Attack opens to the wide gape (1,1).
            ("idle", 5.0, True, ("sheet", "Gaper/gaper_head_sheet.png", 32, [(0, 1)])),
            ("attack", 10.0, False, ("sheet", "Gaper/gaper_head_sheet.png", 32, [(0, 1), (1, 1)])),
        ]},
    ],
    "pacer": [
        {"layer": "body", "offset": (0.0, 0.0),
         "anims": _body_anims("Pacer/pacer_body_sheet.png", _GAPER_VERT, _PACER_SIDE, side_idle=(2, 2))},
    ],
    "gusher": [
        {"layer": "body", "offset": (0.0, 0.0),
         "anims": _body_anims("Gusher/gusher_body_sheet.png", _GAPER_VERT, _PACER_SIDE, side_idle=(2, 2))},
        # gush geyser layer deferred — frame layout of gusher_gush_sheet.png TBD.
    ],
}


def parse_ability(cell):
    """Parse the packed `Ability` column. Returns a dict with any of:
      split_into (str), split_count (int),
      on_death (list of (id, weight)), random_shots (int).
    Abilities are `/`-separated; each is Keyword(args) or a bare Keyword.
    """
    out = {"split_into": "", "split_count": 0, "on_death": [], "random_shots": 0}
    if not cell:
        return out
    for part in str(cell).split("/"):
        part = part.strip()
        if not part or part.upper() == "N/A":
            continue
        m = re.match(r"^(\w+)\s*(?:\((.*)\))?\s*$", part)
        if not m:
            print(f"  WARNING: unparseable ability {part!r}")
            continue
        kw, args = m.group(1).lower(), (m.group(2) or "").strip()
        if kw == "ondeath":
            for entry in args.split(","):
                entry = entry.strip()
                if not entry:
                    continue
                eid, _, w = entry.partition(":")
                out["on_death"].append((eid.strip(), int(w) if w.strip() else 1))
        elif kw == "split":
            bits = [b.strip() for b in args.split(",")]
            if len(bits) >= 2:
                out["split_count"] = int(bits[0])
                out["split_into"] = bits[1]
        elif kw == "randomshots":
            n = re.search(r"count\s*=\s*(\d+)", args)
            out["random_shots"] = int(n.group(1)) if n else 1
        else:
            print(f"  note: ability '{kw}' not handled by importer yet (parked)")
    return out


def parse_layers(cell):
    """Parse the `Layers` column: 'body @ 0,0 ; head @ 0,-10' ->
    ([names], [(x,y), ...]). Empty = single implicit layer ([], [])."""
    names, offsets = [], []
    if not cell:
        return names, offsets
    for part in str(cell).split(";"):
        part = part.strip()
        if not part:
            continue
        name, _, off = part.partition("@")
        names.append(name.strip())
        x, y = 0.0, 0.0
        if off.strip():
            xy = off.split(",")
            x = float(xy[0])
            y = float(xy[1]) if len(xy) > 1 else 0.0
        offsets.append((x, y))
    return names, offsets

ANIM_RE = re.compile(
    r"^\s*(\w+)\s*@\s*([\d.]+)\s*(loop|once)\s*(?:grid\s+(\d+)\s*x\s*(\d+))?\s*$",
    re.IGNORECASE,
)


def parse_color(text) -> str:
    """'r,g,b[,a]' -> a Godot Color(...) literal. Falls back to a red."""
    try:
        parts = [float(x) for x in str(text).split(",")]
    except (ValueError, AttributeError):
        parts = []
    while len(parts) < 3:
        parts.append(0.3)
    if len(parts) < 4:
        parts.append(1.0)
    return "Color(%s)" % ", ".join(_num(p) for p in parts[:4])


def _num(v) -> str:
    """Render a number without a trailing .0 only when it's an int-ish float."""
    f = float(v)
    return str(int(f)) if f == int(f) else repr(f)


def parse_animations(cell):
    """[(name, fps, loop_bool, grid_w_or_None, grid_h_or_None), ...]"""
    out = []
    if not cell:
        return out
    for chunk in str(cell).split(";"):
        chunk = chunk.strip()
        if not chunk:
            continue
        m = ANIM_RE.match(chunk)
        if not m:
            raise ValueError(f"unparseable animation spec: {chunk!r}")
        name, fps, mode, gw, gh = m.groups()
        out.append((
            name.lower(), float(fps), mode.lower() == "loop",
            int(gw) if gw else None, int(gh) if gh else None,
        ))
    return out


def slice_frames(img: Image.Image, grid_w, grid_h):
    """Cut `img` into frames. No grid -> [img]. Grid -> row-major cells."""
    if not grid_w or not grid_h:
        return [img]
    frames = []
    cols = img.width // grid_w
    rows = img.height // grid_h
    for r in range(rows):
        for c in range(cols):
            box = (c * grid_w, r * grid_h, (c + 1) * grid_w, (r + 1) * grid_h)
            frames.append(img.crop(box))
    return frames


def normalise(frames):
    """Trim each frame to its opaque bounds, then centre all on one square
    canvas sized to the largest trimmed frame. Keeps scale consistent across
    every animation of the enemy."""
    trimmed = []
    for fr in frames:
        fr = fr.convert("RGBA")
        bbox = fr.getchannel("A").getbbox()  # bounds of non-transparent pixels
        trimmed.append(fr.crop(bbox) if bbox else fr)
    side = max((max(t.width, t.height) for t in trimmed), default=1)
    out = []
    for t in trimmed:
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(t, ((side - t.width) // 2, (side - t.height) // 2))
        out.append(canvas)
    return out


def find_anim_source(folder, eid, anim):
    """Source PNGs for <id>_<anim>*.png in numeric/lexical order."""
    if not os.path.isdir(folder):
        return []
    prefix = f"{eid}_{anim}"
    hits = [f for f in os.listdir(folder)
            if f.lower().startswith(prefix.lower()) and f.lower().endswith(".png")]
    return [os.path.join(folder, f) for f in sorted(hits)]


def build_enemy(rec):
    eid = str(rec["Id"]).strip()
    name = str(rec["Name"]).strip()
    src_folder = os.path.join(ART_SRC_ROOT, name)
    out_folder = os.path.join(ASSETS_OUT_ROOT, eid)

    # Wipe + recreate this enemy's generated art folder.
    if os.path.isdir(out_folder):
        shutil.rmtree(out_folder)
    os.makedirs(out_folder, exist_ok=True)

    if eid in LAYER_SLICES:
        build_layered_enemy(rec, eid, name, out_folder, LAYER_SLICES[eid])
        return

    anims = parse_animations(rec.get("Animations"))
    # Gather every raw frame across all animations first, so they can be
    # normalised onto ONE shared square canvas (consistent scale/centering, no
    # size pop when switching anims).
    pending = []   # (name, fps, loop, [raw frames])
    for (aname, fps, loop, gw, gh) in anims:
        sources = find_anim_source(src_folder, eid, aname)
        if not sources:
            print(f"  WARNING [{eid}] no art for animation '{aname}' "
                  f"(looked for {eid}_{aname}*.png in {src_folder})")
            continue
        raw = []
        for path in sources:
            raw.extend(slice_frames(Image.open(path), gw, gh))
        pending.append((aname, fps, loop, raw))

    flat = normalise([fr for (_, _, _, raw) in pending for fr in raw])

    anim_meta = []          # (name, fps, loop, frame_count)
    frame_asset_names = []  # res:// frame order matching anim_meta
    cursor = 0
    for (aname, fps, loop, raw) in pending:
        for i in range(len(raw)):
            fr = flat[cursor + i]
            fname = f"{aname}_{i}.png"
            fr.save(os.path.join(out_folder, fname))
            frame_asset_names.append(f"{eid}/{fname}")
        cursor += len(raw)
        anim_meta.append((aname, fps, loop, len(raw)))

    write_tres(rec, eid, name, anim_meta, frame_asset_names)
    nframes = len(frame_asset_names)
    print(f"[generate-action-enemy] {eid}: {len(anim_meta)} anims, {nframes} frames")


def _extract_src(src):
    """Return a list of PIL RGBA frames for a LAYER_SLICES source spec."""
    if src[0] == "file":
        return [Image.open(os.path.join(ART_SRC_ROOT, src[1])).convert("RGBA")]
    _, path, cell, cells = src
    im = Image.open(os.path.join(ART_SRC_ROOT, path)).convert("RGBA")
    return [im.crop((c * cell, r * cell, c * cell + cell, r * cell + cell)) for (r, c) in cells]


def build_layered_enemy(rec, eid, name, out_folder, layers_cfg):
    """Composite/directional path: slice each layer's animations and centre every
    frame on ONE shared canvas (no trim — preserves the artist's cell alignment
    and the relative scale between layers so the head sits on the body)."""
    extracted = []  # (layer, anim, fps, loop, [frames])
    for layer in layers_cfg:
        for (aname, fps, loop, src) in layer["anims"]:
            extracted.append((layer["layer"], aname, fps, loop, _extract_src(src)))

    allfr = [f for (_, _, _, _, frames) in extracted for f in frames]
    cw = max((f.width for f in allfr), default=1)
    ch = max((f.height for f in allfr), default=1)

    anim_meta = []
    frame_assets = []
    for (layer, aname, fps, loop, frames) in extracted:
        for i, f in enumerate(frames):
            cv = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            cv.paste(f, ((cw - f.width) // 2, (ch - f.height) // 2))
            fn = f"{layer}_{aname}_{i}.png"
            cv.save(os.path.join(out_folder, fn))
            frame_assets.append(f"{eid}/{fn}")
        anim_meta.append((f"{layer}.{aname}", fps, loop, len(frames)))

    lnames = [l["layer"] for l in layers_cfg]
    loffsets = [l["offset"] for l in layers_cfg]
    write_tres(rec, eid, name, anim_meta, frame_assets, (lnames, loffsets))
    print(f"[generate-action-enemy] {eid}: {len(lnames)} layers, "
          f"{len(anim_meta)} anims, {len(frame_assets)} frames (canvas {cw}x{ch})")


def write_tres(rec, eid, name, anim_meta, frame_assets, layers_override=None):
    size_px = float(rec["Size"]) * PLAYER_RADIUS
    difficulty = DIFFICULTY.get(str(rec["Difficulty"]).strip().lower(), 0)
    behavior = BEHAVIOR.get(str(rec["Behavior"]).strip().lower(), 0)
    # Directional if the column says so OR any animation carries a facing suffix.
    directional = str(rec.get("Directional", "")).strip().lower() in ("yes", "true", "1")
    if any(str(a[0]).endswith(("_vert", "_side")) for a in anim_meta):
        directional = True

    # ext_resources: script (id 1) + one Texture2D per frame (ids 2..).
    ext = ['[ext_resource type="Script" path="res://scripts/resources/ActionEnemyData.gd" id="1"]']
    frame_ids = []
    for i, asset in enumerate(frame_assets):
        rid = str(i + 2)
        frame_ids.append(rid)
        ext.append(f'[ext_resource type="Texture2D" path="res://assets/enemies/{asset}" id="{rid}"]')
    load_steps = 1 + len(frame_assets) + 1

    anim_names = ", ".join(f'"{a[0]}"' for a in anim_meta)
    anim_fps = ", ".join(_num(a[1]) for a in anim_meta)
    anim_loop = ", ".join("1" if a[2] else "0" for a in anim_meta)
    anim_counts = ", ".join(str(a[3]) for a in anim_meta)
    frames_arr = ", ".join(f'ExtResource("{rid}")' for rid in frame_ids)

    ab = parse_ability(rec.get("Ability"))
    split_into = ab["split_into"]
    split_count = ab["split_count"]
    od_ids = ", ".join(f'"{i}"' for (i, _w) in ab["on_death"])
    od_weights = ", ".join(str(w) for (_i, w) in ab["on_death"])
    if layers_override is not None:
        layer_names, layer_offsets = layers_override
    else:
        layer_names, layer_offsets = parse_layers(rec.get("Layers"))
    lnames = ", ".join(f'"{n}"' for n in layer_names)
    loffsets = ", ".join(f"Vector2({_num(x)}, {_num(y)})" for (x, y) in layer_offsets)
    tag = str(rec.get("Tag") or "").strip()
    tags = f'PackedStringArray("{tag}")' if tag else "PackedStringArray()"

    lines = [
        f'[gd_resource type="Resource" script_class="ActionEnemyData" '
        f'load_steps={load_steps} format=3 uid="uid://action_enemy_{eid}"]',
        "",
        *ext,
        "",
        "[resource]",
        'script = ExtResource("1")',
        f"id = &\"{eid}\"",
        f'display_name = "{name}"',
        f"difficulty = {difficulty}",
        f"weight = {int(rec['Weight'])}",
        f"hp_min = {int(rec['Min HP'])}",
        f"hp_max = {int(rec['Max HP'])}",
        f"contact_damage = {int(rec['Contact Damage'])}",
        f"attack_cooldown = {_num(rec['Attack Cooldown'])}",
        f"attack_windup = {_num(rec.get('Attack Windup') or 0)}",
        f"attack_range = {_num(rec['Attack Range'])}",
        f"preferred_distance = {_num(rec['Preferred Distance'])}",
        f"projectile_speed = {_num(rec['Projectile Speed'])}",
        f"projectile_lifetime = {_num(rec['Projectile Lifetime'])}",
        f"move_speed = {_num(rec['Move Speed'])}",
        f"size = {_num(size_px)}",
        f"behavior = {behavior}",
        f"color = {parse_color(rec.get('Color'))}",
        f'source_game = "{str(rec.get("Game") or "").strip()}"',
        f"tags = {tags}",
        f"split_into = &\"{split_into}\"",
        f"split_count = {split_count}",
        f"random_shots = {ab['random_shots']}",
        f"on_death_ids = PackedStringArray({od_ids})",
        f"on_death_weights = PackedInt32Array({od_weights})",
        f"layer_names = PackedStringArray({lnames})",
        f"layer_offsets = PackedVector2Array({loffsets})",
        f"directional = {'true' if directional else 'false'}",
        f"anim_names = PackedStringArray({anim_names})",
        f"anim_fps = PackedFloat32Array({anim_fps})",
        f"anim_loop = PackedByteArray({anim_loop})",
        f"anim_frame_counts = PackedInt32Array({anim_counts})",
        f"anim_frames = Array[Texture2D]([{frames_arr}])",
        "",
    ]
    os.makedirs(TRES_OUT_DIR, exist_ok=True)
    with open(os.path.join(TRES_OUT_DIR, f"{eid}.tres"), "w") as f:
        f.write("\n".join(lines))


def main() -> int:
    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if "enemiesA" not in wb.sheetnames:
        print("ERROR: no enemiesA sheet — run build_enemiesA_sheet.py first")
        return 1
    ws = wb["enemiesA"]
    hdr = [c.value for c in ws[1]]
    col = {name: i for i, name in enumerate(hdr)}

    count = 0
    for row in ws.iter_rows(min_row=2, values_only=True):
        if not row or not row[col["Id"]]:
            continue
        rec = {name: row[col[name]] for name in hdr if name}
        eid = str(rec["Id"]).strip()
        if eid in PRESERVE:
            print(f"  skip {eid} (preserved hand-authored enemy)")
            continue
        build_enemy(rec)
        count += 1
    print(f"[generate-action-enemy] wrote {count} action enemies")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
