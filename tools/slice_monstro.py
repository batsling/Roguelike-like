#!/usr/bin/env python3
"""One-off slicer for the hand-drawn Monstro boss sheet.

Monstro's art arrived as a single irregular sheet (9 scattered frames of
differing sizes) rather than the uniform grids the xlsx-driven
`generate_action_enemy_tres.py` expects, and Monstro is a hand-authored boss
(not in the enemiesA sheet), so this script does the slicing here.

It mirrors the importer's `normalise()` exactly — trim each frame to its opaque
bounds, then centre every frame on ONE shared square canvas sized to the largest
trimmed frame — so the sprite never pops size when switching animations. Output
lands in `assets/enemies/monstro/<anim>_<n>.png`, referenced by
`data/action_enemies/monstro.tres`. Re-run safe.

    python3 tools/slice_monstro.py
"""
import os
from collections import deque
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "images/enemies/action_enemies/Bosses/Monstro/monstro.png")
OUT = os.path.join(ROOT, "assets/enemies/monstro")
A_THRESH = 8

# Animation layout: each entry maps an anim name to the sheet frames that make
# it up, in play order. Frames are addressed by their detected slot (row, then
# left-to-right) so the mapping survives a re-detect. Slots (see the sheet):
#   row0: 0 idle-a  1 idle-b  2 mouth-open  3 crouch(squished)  4 airborne(tall)
#   row1: 5 pancake 6 scream  7 grin        8 worried
# jump = the crouch, airborne = the stretched oval, land = the flat pancake,
# attack (vomit) = mouth-open -> full scream. Grin/worried are left spare.
ANIMS = [
    ("idle", [0, 1]),
    ("jump", [3]),
    ("airborne", [4]),
    ("land", [5]),
    ("attack", [2, 6]),
]


def detect_boxes(im):
    W, H = im.size
    px = im.load()
    seen = [[False] * W for _ in range(H)]
    boxes = []
    for y in range(H):
        for x in range(W):
            if px[x, y][3] > A_THRESH and not seen[y][x]:
                q = deque([(x, y)])
                seen[y][x] = True
                minx = maxx = x
                miny = maxy = y
                cnt = 0
                while q:
                    cx, cy = q.popleft()
                    cnt += 1
                    minx = min(minx, cx); maxx = max(maxx, cx)
                    miny = min(miny, cy); maxy = max(maxy, cy)
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < W and 0 <= ny < H and px[nx, ny][3] > A_THRESH and not seen[ny][nx]:
                                seen[ny][nx] = True
                                q.append((nx, ny))
                if cnt >= 40:  # ignore stray specks
                    boxes.append((minx, miny, maxx, maxy))
    # Slot order: split into two rows by y, each left-to-right.
    mid = im.size[1] // 2
    boxes.sort(key=lambda b: (0 if b[1] < mid else 1, b[0]))
    return boxes


def main():
    im = Image.open(SHEET).convert("RGBA")
    boxes = detect_boxes(im)
    if len(boxes) < 7:
        raise SystemExit(f"expected >=7 frames, detected {len(boxes)}")

    # Crop every frame we reference, trim to opaque bounds.
    trimmed = {}
    for _, idxs in ANIMS:
        for i in idxs:
            b = boxes[i]
            fr = im.crop((b[0], b[1], b[2] + 1, b[3] + 1))
            bb = fr.getchannel("A").getbbox()
            trimmed[i] = fr.crop(bb) if bb else fr

    # Shared square canvas sized to the largest trimmed frame (importer parity).
    side = max(max(t.width, t.height) for t in trimmed.values())

    os.makedirs(OUT, exist_ok=True)
    for name, idxs in ANIMS:
        for n, i in enumerate(idxs):
            t = trimmed[i]
            canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            canvas.paste(t, ((side - t.width) // 2, (side - t.height) // 2))
            canvas.save(os.path.join(OUT, f"{name}_{n}.png"))
    print(f"[slice-monstro] wrote frames to {OUT} (canvas {side}x{side})")
    for name, idxs in ANIMS:
        print(f"  {name}: {len(idxs)} frame(s)")


if __name__ == "__main__":
    main()
