#!/usr/bin/env python3
"""One-shot research: Megabonk's 21 hats, held for later (docs/customization.md §7).

The owner, 14 Nov 2026: "i know megabonk also has hats, can you see if you can find
them" — and then, of how they should unlock: "lets not deal with these yet, i'd
like to have unlocks for these with mechanics that don't exist yet". So they are
NOT in the game. This writes them to research/hats/, ready for when those
mechanics exist:

  research/hats/megabonk.csv        name, Megabonk's own unlock, Steam api name, file
  research/hats/megabonk/<Name>.png each hat, cut out of its achievement icon

WHERE THEY COME FROM. Every Megabonk hat (21, added in its update 1.0.64) is earned
by an achievement of the same name, so Steam's public achievement page lists them
all with their unlock text (the `a_hat…` api names). The wiki that may hold better
pictures, megabonk.wiki, was outside the session's network allowlist; the fandom
wiki has no hats page.

THE PICTURES are the achievement icons: 256px JPGs of pixel art on a framed,
vignetted background. Each hat has a pure black outline (every channel under ~10)
where even the darkest background has a channel at 27+, so the cut is a flood fill
from the edges walled by near-black — after thickening the outline by a couple of
pixels to close the JPEG's gaps in it, and then peeling that ring back off. Specks
under 1% of the largest piece are dropped (the frame's corners). The Clown's
outline needs a wider close; each icon tries 2 px, then wider, until the cut-out is
solid. They are kept facing as Megabonk draws them (front-on three-quarter views).

  python3 tools/oneshots/_hats_megabonk_research.py
"""

import collections
import csv
import io
import json
import os
import re
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "research", "hats")
APP = 3405340
PAGE = "https://steamcommunity.com/stats/%d/achievements/?l=english" % APP
ICON = "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/%d/" % APP
UA = {"User-Agent": "Mozilla/5.0 (Roguelike-like hat research)"}


def get(url: str) -> bytes:
	with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
		return r.read()


def hats() -> list:
	text = get(PAGE).decode("utf-8").replace('\\"', '"').replace("\\/", "/")
	found = {}
	for api, name, desc, icon in re.findall(
			r'\{"internal_key":\d+,"api_name":"(a_hat[^"]*)","name":"([^"]*)",'
			r'"description":"([^"]*)".*?"icon_achieved":"([^"]*)"', text):
		found[api] = (json.loads('"%s"' % name), json.loads('"%s"' % desc), icon)
	return [(api,) + v for api, v in sorted(found.items(), key=lambda kv: kv[1][0].lower())]


def _cut_once(img: Image.Image, close: int, wall: int = 24) -> Image.Image:
	w, h = img.size
	a = np.asarray(img.crop((11, 11, w - 11, h - 11))).astype(int)
	H, W, _ = a.shape
	is_wall = a.max(axis=2) < wall
	thick = np.asarray(Image.fromarray((is_wall * 255).astype("uint8"))
		.filter(ImageFilter.MaxFilter(close * 2 + 1))) > 0
	out = np.zeros((H, W), bool)
	q = collections.deque([(y, x) for x in range(W) for y in (0, H - 1)]
		+ [(y, x) for y in range(H) for x in (0, W - 1)])
	while q:
		y, x = q.popleft()
		if y < 0 or x < 0 or y >= H or x >= W or out[y, x] or thick[y, x]:
			continue
		out[y, x] = True
		q.extend([(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)])
	for _ in range(close + 1):
		grow = np.zeros_like(out)
		grow[1:, :] |= out[:-1, :]
		grow[:-1, :] |= out[1:, :]
		grow[:, 1:] |= out[:, :-1]
		grow[:, :-1] |= out[:, 1:]
		out |= grow & ~is_wall
	alpha = np.where(out, 0, 255)
	# Drop specks: pieces under 1% of the largest.
	lab = np.zeros((H, W), int)
	sizes = []
	for y in range(H):
		for x in range(W):
			if alpha[y, x] and not lab[y, x]:
				sizes.append(0)
				n = len(sizes)
				lab[y, x] = n
				q = collections.deque([(y, x)])
				while q:
					cy, cx = q.popleft()
					sizes[-1] += 1
					for dy in (-1, 0, 1):
						for dx in (-1, 0, 1):
							yy, xx = cy + dy, cx + dx
							if 0 <= yy < H and 0 <= xx < W and alpha[yy, xx] and not lab[yy, xx]:
								lab[yy, xx] = n
								q.append((yy, xx))
	keep = [i + 1 for i, s in enumerate(sizes) if s >= max(sizes) * 0.01]
	alpha = np.where(np.isin(lab, keep), 255, 0)
	res = Image.fromarray(np.dstack([a, alpha]).astype("uint8"), "RGBA")
	return res.crop(res.getbbox())


def cut(img: Image.Image) -> Image.Image:
	res = None
	for close in (2, 3, 4, 5, 6):
		res = _cut_once(img, close)
		if (np.asarray(res)[:, :, 3] > 0).mean() > 0.45:
			break
	return res


def main():
	pics = os.path.join(OUT, "megabonk")
	os.makedirs(pics, exist_ok=True)
	rows = []
	for api, name, desc, icon in hats():
		stem = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")
		img = Image.open(io.BytesIO(get(ICON + icon))).convert("RGB")
		cut(img).save(os.path.join(pics, stem + ".png"), optimize=True)
		rows.append({"Name": name, "Megabonk unlock": desc, "Steam api name": api,
			"File": "megabonk/%s.png" % stem})
		print(f"{stem}.png  {name}")
	with open(os.path.join(OUT, "megabonk.csv"), "w", newline="", encoding="utf-8") as f:
		w = csv.DictWriter(f, fieldnames=list(rows[0]))
		w.writeheader()
		w.writerows(rows)
	print(f"{len(rows)} hats -> research/hats/")


if __name__ == "__main__":
	main()
