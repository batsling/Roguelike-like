#!/usr/bin/env python3
"""One-off slicer for the hand-drawn Monstro boss sheet.

Monstro's art arrived as a single irregular sheet (9 scattered frames of
differing sizes) rather than the uniform grids the xlsx-driven
`generate_action_enemy_tres.py` expects, and Monstro is a hand-authored boss
(not in the enemiesA sheet), so this script does the slicing here.

It detects each frame's opaque bounds, then — mirroring the importer's
`normalise()` — trims and centres every frame on ONE shared square canvas sized
to the largest trimmed frame, so the sprite never pops size when switching
animations. Frames are written as `f1.png`..`f9.png` in `assets/enemies/monstro/`
(numbered top row 1-5, bottom row 6-9, matching how the animations in
`data/action_enemies/monstro.tres` reference them). Re-run safe.

    python3 tools/slice_monstro.py
"""
import os
from collections import deque
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "images/enemies/action_enemies/Bosses/Monstro/monstro.png")
OUT = os.path.join(ROOT, "assets/enemies/monstro")
A_THRESH = 8


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
    # Number the frames: top row 1-5, bottom row 6-9, each left-to-right.
    mid = im.size[1] // 2
    boxes.sort(key=lambda b: (0 if b[1] < mid else 1, b[0]))
    return boxes


def main():
    im = Image.open(SHEET).convert("RGBA")
    boxes = detect_boxes(im)
    if len(boxes) != 9:
        raise SystemExit(f"expected 9 frames, detected {len(boxes)}")

    trimmed = []
    for b in boxes:
        fr = im.crop((b[0], b[1], b[2] + 1, b[3] + 1))
        bb = fr.getchannel("A").getbbox()
        trimmed.append(fr.crop(bb) if bb else fr)
    side = max(max(t.width, t.height) for t in trimmed)

    os.makedirs(OUT, exist_ok=True)
    for n, t in enumerate(trimmed, start=1):
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(t, ((side - t.width) // 2, (side - t.height) // 2))
        canvas.save(os.path.join(OUT, f"f{n}.png"))
    print(f"[slice-monstro] wrote f1..f9 to {OUT} (canvas {side}x{side})")


if __name__ == "__main__":
    main()
