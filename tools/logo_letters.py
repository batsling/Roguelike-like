#!/usr/bin/env python3
"""Cut a game's logo into one PNG per letter, for the main menu's title.

The title on the main menu is spelled out of letters cut from real roguelikes'
logos, and which game's letter stands in each place is drawn again every time
the game opens. This makes the letters. Each lands at

    images2.0/custom/title/<piece>/<game id>.png        e.g. title/r/balatro.png

so a folder holds every game's version of one letter, and a new logo's letters
join the pool with no code touched. A piece that is not a letter gets a name of
its own; `dash` is the one the title uses for its hyphen. What a logo has that is
no piece at all (Balatro's ace, Hades II's green II) is left out.

A logo is never just its letters cut apart. In most logos the letters SHARE an
outline (Balatro's B and A are joined by one stroke), some overlap (Balatro's T
crossbar is drawn in front of the R's top-left corner, so that corner was never
drawn at all), and a drop shadow runs under all of them at once. So a letter
taken with scissors comes out with a flat side where its neighbour was, a bite
out of it where it was hidden, and half of somebody else's shadow. What this
does instead:

  1. Finds each letter by its FILL (the light inside of the letterform, where
     the outline is dark), so letters that share an outline come apart cleanly.
     Two letters whose fills run together are parted along a line the logo's
     config gives (`splits`), and a part one letter hid of another is painted
     back in from the colours beside it (`restore`).
  2. Smooths each fill a little, then draws the outline as an even band around
     it. Inside that band the logo's own outline pixels are kept wherever they
     belong to this letter; where a neighbour was, the band is painted in the
     outline's own shades, learned from the logo's untouched edges by distance
     from the fill. So the outline matches the original and every side of every
     letter is one smooth curve.
  3. Re-casts the logo's drop shadow per letter. Its shape (how far it is pushed,
     which way, how thick its solid band is, how its glow fades) is MEASURED off
     the most isolated letter in the logo, then cast with its corners rounded so
     it curves with the letter rather than running off in straight lines.

A piece listed in `keep_original` (a playing card, an icon) has no outline to
rebuild: it keeps its own pixels and only gets the shadow.

    python3 tools/logo_letters.py tools/logo_letters/balatro.json
    python3 tools/logo_letters.py tools/logo_letters/balatro.json --preview out.png

The config, beside its source logo in tools/logo_letters/ (tools/ is .gdignored,
so Godot never imports the source), is JSON:

    game          the game's id in data/games/ — the file name every piece gets
    source        the logo, transparent background, as big as can be found
    pieces        {name: [x, y]} — a point inside each piece's fill, in source
                  pixels (the nearest fill pixel is used, so near is enough);
                  [[x, y], ...] for a piece whose fill is in several parts
    ignore        [[x, y], ...] — fill to leave out entirely (Balatro's ace)
    keep_original names of pieces that keep their own pixels (cards, icons)
    splits        [{"pieces": [upper, lower], "lower": name, "x_min": x,
                    "line": [[x, y], ...]}] — two pieces whose fills touch:
                  pixels at or right of x_min and on or below the line go to
                  `lower`, the rest to the other
    restore       [{"piece": name, "polygon": [[x, y], ...], "copy_column": x}]
                  — part of a piece another piece hid; it is added to the piece
                  and painted with the colours of the piece's column `copy_column`
    extra_ink     [{"piece": name, "polygon": [[x, y], ...], "clear": px}] — the
                  outline inside the polygon (ink and glow) belongs to the piece
                  however far from its fill, except within `clear` of another
                  piece's fill (default: the outline width). Hades' A's thorns,
                  which run down into the gap by the H
    fill          optional {"min_alpha": 200, "min_brightness": 140,
                  "min_channel": n} — what counts as fill. Defaults suit a light
                  fill in a dark outline; min_channel keeps a coloured glow out
                  of a white fill
    cut           scissors instead of paint: every pixel kept is the logo's own.
                  {"reach": px or {piece: px, "*": px} — how far from its fill a
                  piece reaches; "background": {"colour": [r, g, b],
                  "tolerance": n, "min_area": px, "grow": px, "spread_through":
                  {"min_green": n, "max_red": n}} — a shape behind the letters,
                  found as big regions of its colour (so a letter's own glow of
                  that colour is never it) and followed out through its glow;
                  "erase": [{"piece": name, "polygon": [[x, y], ...]}] — cut
                  away by hand (bits of the background's outline)}
    smooth        default true. false keeps the fill's own edge, spikes and all
                  (Hades' thorns), instead of smoothing it and opening/closing it
    shadow        default true (measured and re-cast). false for a logo whose
                  dark edge is ink, not a shadow
    outline       optional {"width": px, "clean_distance": px,
                  "match_tolerance": n, "ink_beyond": px} — the outline's width
                  if measuring gets it wrong; how far from other letters an edge
                  must be to learn from; keep an original outline pixel only if
                  within n of the outline's colour at that distance (so a
                  background shape touching the letter is painted over); and
                  how far past the width hand-inked outline is still kept.
                  For a spiky inked logo: "follow_original": true paints the
                  outline only where the logo drew something else (never into
                  the gaps between spikes), "keep_within": px keeps everything
                  the logo drew that near the letter (or {piece: px, "*": px}
                  for less near a busy background), and "drop_colours":
                  [[r, g, b], ...] are colours that are never the letter's,
                  within "drop_tolerance" (default 30)

How to add a logo: docs/content-authoring.md, "Title letters".
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as nd

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "images2.0" / "custom" / "title"

# How much each fill is smoothed before its outline is drawn round it. Enough
# to take the pixel-step wobble out of a hand-drawn edge, not enough to round
# off a serif.
FILL_SMOOTH_SIGMA = 2.5
# Opening then closing of each piece's fill, in pixels: drops slivers a split
# leaves behind and closes the notches it cuts.
OPEN_ITER, CLOSE_ITER = 3, 4
# The shadow's corners are rounded by this much, so its edge curves.
SHADOW_ROUND_SIGMA = 7.0


def _fill_mask(A: np.ndarray, cfg: dict) -> np.ndarray:
    f = cfg.get("fill", {})
    m = (A[..., 3] > f.get("min_alpha", 200)) & (A[..., :3].max(-1) > f.get("min_brightness", 140))
    if "min_channel" in f:  # white fills: every channel high, so a coloured glow is not fill
        m &= A[..., :3].min(-1) > f["min_channel"]
    return m


def _pieces(A: np.ndarray, fill: np.ndarray, cfg: dict) -> dict[str, np.ndarray]:
    """Each piece's fill, by the component its anchor point falls in."""
    H, W = fill.shape
    lab, _ = nd.label(fill)
    _, (iy, ix) = nd.distance_transform_edt(~fill, return_indices=True)
    # A piece is one point, or a list of points when its fill is in several
    # parts (Hades' D: a stem and a bowl the outline keeps apart).
    pieces = {}
    for name, pts in cfg["pieces"].items():
        pts = [pts] if isinstance(pts[0], (int, float)) else pts
        pieces[name] = np.isin(lab, [lab[iy[y, x], ix[y, x]] for x, y in pts])
    # Fill that belongs to nothing wanted (Balatro's ace) is taken out of the
    # logo first, so it neither becomes a piece nor joins its neighbour's.
    # Everything inside it goes too (the white in the card's corner A's).
    for x, y in cfg.get("ignore", []):
        fill &= ~nd.binary_fill_holes(lab == lab[iy[y, x], ix[y, x]])
    yy, xx = np.mgrid[0:H, 0:W]
    for sp in cfg.get("splits", []):
        a, b = sp["pieces"]
        lower = sp["lower"]
        upper = a if lower == b else b
        shared = pieces[a] | pieces[b]
        pts = np.array(sp["line"], float)
        line = np.interp(xx, pts[:, 0], pts[:, 1])
        low = shared & (xx >= sp.get("x_min", 0)) & (yy >= line)
        pieces[lower] = low
        pieces[upper] = shared & ~low
    # Stray bits of fill (a stripe's tip cut off by an outline) join the
    # piece they are nearest.
    claimed = np.zeros_like(fill)
    for m in pieces.values():
        claimed |= m
    names = list(pieces)
    owner = np.stack([nd.distance_transform_edt(~pieces[n]) for n in names]).argmin(0)
    for i, n in enumerate(names):
        pieces[n] = pieces[n] | (fill & ~claimed & (owner == i))
    return pieces


def _polygon_mask(shape, pts) -> np.ndarray:
    from PIL import ImageDraw
    img = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(img).polygon([tuple(p) for p in pts], fill=1)
    return np.array(img).astype(bool)


def _extrude(m: np.ndarray, r: int, dx: int, dy: int) -> np.ndarray:
    """`m` grown by `r`, then dragged (dx, dy): the union of every step."""
    m = nd.binary_dilation(m, iterations=r)
    out = m.copy()
    steps = max(abs(dx), abs(dy), 1)
    for s in range(1, steps + 1):
        out |= np.roll(np.roll(m, round(dy * s / steps), 0), round(dx * s / steps), 1)
    return out


def _measure_shadow(A, solid, pieces, keep_original):
    """Fit the logo's drop shadow on its most isolated letter.

    Returns (r, dx, dy, hard_alpha(d), glow_alpha(d)) where the shadow is the
    body extruded by (r, dx, dy), solid near the body and fading with
    distance d from it, then a glow fading with distance from the solid part.
    """
    a = A[..., 3].astype(float)
    names = [n for n in pieces if n not in keep_original]
    D = {n: nd.distance_transform_edt(~pieces[n]) for n in pieces}
    best_name, best_room = None, -1
    for n in names:
        others = np.min([D[o] for o in pieces if o != n], 0)
        room = np.percentile(others[pieces[n]], 90)
        if room > best_room:
            best_name, best_room = n, room
    n = best_name
    others = np.min([D[o] for o in pieces if o != n], 0)
    body = solid & (D[n] <= 30) & (D[n] <= others)
    zone = others > max(60.0, best_room * 0.6)
    hard = (a >= 150) & (a < 254)
    best = None
    for r in (6, 8, 10, 12):
        for dx in range(-24, 25, 4):
            for dy in range(-24, 25, 4):
                e = _extrude(body, r, dx, dy) & ~solid
                inter = (e & hard & zone).sum()
                uni = ((e | hard) & zone).sum()
                score = inter / max(uni, 1)
                if best is None or score > best[0]:
                    best = (score, r, dx, dy)
    _, r, dx, dy = best
    e = _extrude(body, r, dx, dy)
    db = nd.distance_transform_edt(~body)
    de = nd.distance_transform_edt(~e)
    hd, ha = [], []
    for k in range(1, int(r + max(abs(dx), abs(dy))) + 1, 2):
        s = zone & e & ~solid & (db > k - 1) & (db <= k + 1)
        if s.sum() > 20:
            hd.append(k)
            ha.append(np.median(a[s]))
    gd, ga = [0.0], [None]
    for k in range(1, 40, 2):
        s = zone & (a < 150) & ~e & (de > k - 1) & (de <= k + 1)
        if s.sum() > 20:
            gd.append(k)
            ga.append(np.median(a[s]))
    ga[0] = ga[1] if len(ga) > 1 else 0.0
    if not hd:
        hd, ha = [0], [0.0]
    print(f"  shadow from '{n}': grow {r}, push ({dx}, {dy}), "
          f"solid {int(ha[0])}->{int(ha[-1])}, glow {int(ga[0])}->{int(ga[-1])} over {gd[-1]}px "
          f"(fit {best[0]:.2f})")
    return r, dx, dy, (np.array(hd), np.array(ha)), (np.array(gd), np.array(ga, float))


def cut(cfg_path: Path, preview: Path | None = None) -> list[Path]:
    cfg = json.loads(cfg_path.read_text())
    src = cfg_path.parent / cfg["source"]
    A = np.array(Image.open(src).convert("RGBA")).astype(float)
    H, W = A.shape[:2]
    a = A[..., 3]
    fill = _fill_mask(A, cfg)
    solid = a >= 254
    keep_original = set(cfg.get("keep_original", []))
    smooth = cfg.get("smooth", True)
    oc = cfg.get("outline", {})
    pieces = _pieces(A, fill, cfg)

    # The logo's outline, learned from edges no neighbour touches: its width,
    # and its colour at each distance from the fill.
    D = {n: nd.distance_transform_edt(~m) for n, m in pieces.items()}
    srt = np.sort(np.stack(list(D.values())), 0)
    d1, d2 = srt[0], srt[1] if len(D) > 1 else srt[0] + 1e9
    clean = solid & ~fill & (d2 > oc.get("clean_distance", 120))
    edge = solid & ~nd.binary_erosion(solid)
    widths = d1[edge & clean & (d1 > 0) & (d1 < 60)]
    T = float(oc.get("width", np.median(widths) if widths.size else 19.0))
    lut = np.zeros((int(T) + 3, 3))
    for k in range(len(lut)):
        m = clean & (d1 > k - 0.5) & (d1 <= k + 0.5)
        lut[k] = np.median(A[m][:, :3], 0) if m.sum() > 50 else lut[max(k - 1, 0)]
    print(f"  outline {T:.0f}px wide")

    # Parts one piece hid of another, painted back from the piece's own column.
    restored = {}
    restored_rgb = A[..., :3].copy()
    yy, xx = np.mgrid[0:H, 0:W]
    for rs in cfg.get("restore", []):
        m = _polygon_mask((H, W), rs["polygon"]) & ~pieces[rs["piece"]]
        col = int(rs["copy_column"])
        restored_rgb[m] = A[yy[m], col, :3]
        restored[rs["piece"]] = restored.get(rs["piece"], np.zeros_like(m)) | m

    # Every piece's fill tidied: restored, then opened (slivers off) and closed
    # (notches shut); a pixel that adds takes the colour of the nearest one.
    st = nd.generate_binary_structure(2, 1)
    colour = {}
    for n in pieces:
        before = pieces[n] | restored.get(n, False)
        base = np.where(restored.get(n, np.zeros((H, W), bool))[..., None], restored_rgb, A[..., :3])
        if n in keep_original or not smooth:
            pieces[n], colour[n] = before, base
            continue
        tidy = nd.binary_closing(nd.binary_opening(before, st, iterations=OPEN_ITER), st, iterations=CLOSE_ITER)
        _, (iy, ix) = nd.distance_transform_edt(~before, return_indices=True)
        colour[n] = np.where((tidy & ~before)[..., None], base[iy, ix], base)
        pieces[n] = tidy

    D = {n: nd.distance_transform_edt(~m) for n, m in pieces.items()}
    names = list(pieces)
    owner = np.stack([D[n] for n in names]).argmin(0)
    shadow = cfg.get("shadow", True)
    if shadow:
        r, dx, dy, (hd, ha), (gd, ga) = _measure_shadow(A, solid, pieces, keep_original)

    # Counters (the holes in B, A, O...) stay as open as the logo drew them.
    clear = a < 40
    cl, _ = nd.label(clear)
    border = np.unique(np.concatenate([cl[0], cl[-1], cl[:, 0], cl[:, -1]]))
    holes = clear & ~np.isin(cl, border)

    # Cut mode: a shape behind the letters (Hades II's green II) is found as
    # the BIG regions of its colour, so the small bits of a similar glow on
    # the letters' own spikes are never mistaken for it.
    cut = cfg.get("cut")
    background = np.zeros((H, W), bool)
    if cut and "background" in cut:
        bg = cut["background"]
        near = (a > 0) & (np.abs(A[..., :3] - np.array(bg["colour"])).max(-1) <= bg.get("tolerance", 40))
        lab_g, ng = nd.label(near)
        if ng:
            sizes = nd.sum(near, lab_g, range(1, ng + 1))
            background = np.isin(lab_g, 1 + np.flatnonzero(sizes >= bg.get("min_area", 3000)))
        if bg.get("grow"):
            # the soft edge where the shape blends into its own outline;
            # never into a letter's fill
            background = nd.binary_dilation(background, iterations=bg["grow"]) & ~fill
        if "spread_through" in bg:
            # its glow fades out in shades of its own colour: follow it outward
            # through those shades only, never across ink or a letter's fill
            st_ = bg["spread_through"]
            glowish = ((a > 0) & (A[..., 1] >= st_.get("min_green", 200))
                       & (A[..., 0] <= st_.get("max_red", 150)) & ~fill)
            background = nd.binary_propagation(background, mask=glowish | background)

    written = []
    out_dir_game = cfg["game"]
    for i, n in enumerate(names):
        mine = owner == i
        f = pieces[n]
        rgb = np.zeros((H, W, 3))
        al = np.zeros((H, W))
        if n in keep_original:
            body = nd.binary_dilation(nd.binary_fill_holes(f), iterations=2) & (a > 0) & mine
            rgb[body] = A[body][:, :3]
            al[body] = a[body] / 255
        elif cut:
            # Scissors, not paint: every pixel kept is the logo's own, as drawn.
            # The letter is everything within `reach` of its fill on its side of
            # the cut, less the background shape and anything erased by hand.
            reach = cut.get("reach", 60)
            if isinstance(reach, dict):
                reach = reach.get(n, reach.get("*", 60))
            ds = nd.distance_transform_edt(~f)
            keep = f | ((a > 0) & ~background & mine & (ds <= reach))
            for ex in cfg.get("extra_ink", []):
                if ex["piece"] == n:
                    d_other = np.min([D[o] for o in names if o != n], 0)
                    keep |= (_polygon_mask((H, W), ex["polygon"]) & (a > 0) & ~background
                             & (d_other > ex.get("clear", 4)))
            for er in cut.get("erase", []):
                if er["piece"] == n:
                    keep &= ~_polygon_mask((H, W), er["polygon"])
            # only what is joined to the letter (diagonals count: a thorn's tip
            # is often a pixel wide)
            lab_k, _ = nd.label(keep, structure=np.ones((3, 3)))
            keep &= np.isin(lab_k, np.unique(lab_k[f & (lab_k > 0)]))
            rgb[keep] = A[keep][:, :3]
            al[keep] = a[keep] / 255
        else:
            fs = nd.gaussian_filter(f.astype(float), FILL_SMOOTH_SIGMA) > 0.5 if smooth else f
            ds = nd.distance_transform_edt(~fs)
            idx = np.clip(np.round(ds).astype(int), 0, len(lut) - 1)
            band = (ds > 0) & (ds <= T + 0.5) & ~f
            if oc.get("follow_original"):
                # Paint the outline only where the logo drew SOMETHING: over
                # what is not this letter's (Hades' II), never into the gaps
                # between its thorns, so the silhouette stays the logo's own.
                band &= a > 40
            orig = band & solid & mine & ~fill & (ds <= T - 1.5)
            # Hand-inked outlines run thicker than their usual width in places;
            # that extra ink is kept, out to `ink_beyond` past the width.
            beyond = oc.get("ink_beyond", 0)
            if beyond:
                orig |= solid & mine & ~fill & (ds > 0) & (ds <= T + beyond) & ~f
            # A pixel near the letter that is not the colour its outline has at
            # that distance is something else's (Hades' green II): repainted.
            tol = oc.get("match_tolerance")
            if tol is not None:
                orig &= np.abs(A[..., :3] - lut[idx]).max(-1) <= tol
            # Spikes: everything the logo drew within `keep_within` of the
            # letter is kept as drawn (thorns and all), except a colour that is
            # some other shape's (the II's green). Close to the fill a matching
            # colour is the glow, and stays.
            within = oc.get("keep_within", 0)
            if isinstance(within, dict):  # per piece; "*" for the rest
                within = within.get(n, within.get("*", 0))
            if within:
                far = solid & mine & ~fill & (ds > 0) & (ds <= within)
                for c in oc.get("drop_colours", []):
                    far &= ~((np.abs(A[..., :3] - np.array(c)).max(-1) <= oc.get("drop_tolerance", 30)) & (ds > 8))
                orig |= far
            rgb[f] = colour[n][f]
            al[f] = 1
            rgb[band] = lut[idx[band]]
            al[band] = np.clip(T + 0.5 - ds[band], 0, 1)
            rgb[orig] = A[orig][:, :3]
            al[orig] = 1
            al[holes & band] = np.minimum(al[holes & band], a[holes & band] / 255)
        body = al > 0.5
        if n not in keep_original and (oc.get("ink_beyond", 0) or oc.get("keep_within", 0)):
            # ink with none of the letter's fill in it is someone else's (a
            # part like Hades' A curl, drawn apart from the A, keeps its own)
            lab_b, nb = nd.label(al > 0)
            own = np.unique(lab_b[f & (lab_b > 0)])
            stray = (lab_b > 0) & ~np.isin(lab_b, own)
            al[stray] = 0
            body &= ~stray
        if not shadow:
            sh = np.zeros((H, W))

        # The shadow: the body extruded, its corners rounded so it curves, solid
        # near the body and fading out, then a glow beyond.
        if shadow:
            hard = nd.gaussian_filter(_extrude(body, r, dx, dy).astype(float), SHADOW_ROUND_SIGMA) > 0.5
            hard |= body
            db = nd.distance_transform_edt(~body)
            sh = np.where(hard, np.interp(db, hd, ha) / 255, 0.0)
            sh[body] = ha[0] / 255  # hidden under the body; keeps the blur off its edge
            de = nd.distance_transform_edt(~hard)
            sh = np.maximum(sh, np.where(~hard, np.interp(de, gd, ga, right=0) / 255, 0))
            sh = nd.gaussian_filter(sh, 0.8)

        out_a = al + sh * (1 - al)
        out_rgb = (rgb * al[..., None]) / np.maximum(out_a, 1e-6)[..., None]
        out = np.dstack([out_rgb, out_a * 255]).clip(0, 255).astype(np.uint8)
        ys, xs = np.where(out[..., 3] > 1)
        x0, x1 = max(xs.min() - 2, 0), min(xs.max() + 3, W)
        y0, y1 = max(ys.min() - 2, 0), min(ys.max() + 3, H)
        dest = OUT_DIR / n / f"{out_dir_game}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(out[y0:y1, x0:x1]).save(dest, optimize=True)
        written.append(dest)
        print(f"  {dest.relative_to(ROOT)}  {x1 - x0}x{y1 - y0}")

    if preview:
        ims = [Image.open(p) for p in written]
        h = max(i.height for i in ims)
        w = sum(i.width for i in ims) + 30 * len(ims) + 30
        sheet = Image.new("RGBA", (w, h + 60), (255, 0, 255, 255))
        x = 30
        for im in ims:
            sheet.alpha_composite(im, (x, 30 + h - im.height))
            x += im.width + 30
        sheet.convert("RGB").save(preview)
        print(f"  preview: {preview}")
    return written


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("configs", nargs="+", type=Path, help="tools/logo_letters/<game>.json")
    ap.add_argument("--preview", type=Path, help="also write every piece side by side on magenta")
    args = ap.parse_args()
    for c in args.configs:
        print(c)
        cut(c, args.preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
