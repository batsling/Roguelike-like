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

    body          {piece: [y_top, y_bottom]} — source rows the letter itself fills,
                  for a piece with something attached (an eye stalk, a knife,
                  slime); its width is then measured over those rows only, so
                  a stalk off to one side cannot pull the letter's middle with
                  it. Otherwise the letter's box is measured from its face
                  (fill), so glow, shadow and outline never shift it. The index
                  records it as body_center / body_height (vertical) and
                  body_center_x / body_width (horizontal), fractions of the PNG
    centre        {piece: [y_top, y_bottom]} — source rows to sit on the line's
                  middle, for a decoration whose own middle is not the part
                  that should line up (Uma Musume's dash: its bar, not the
                  sparkles above it). Unlike `body` it leaves the size alone;
                  the index records it as line_center
    lowercase     [piece, ...] — pieces drawn as lowercase letters (a small a,
                  not a capital A); the index records "form": "lower". A
                  lowercase place in the title draws every letter at Rogue's
                  x-height unless it is a tall one (b d f h k l t, and a
                  lowercase-shaped i), and lets a lowercase g j p q y hang below
    size          {piece or "*": factor} — drawn this many times as big as its
                  case makes it, grown or shrunk on the baseline (Dead Cells'
                  thin letters a little bigger, Darkest Dungeon's k smaller)
    pad           {piece or "*": fraction} — that much of the line height kept
                  clear on each side of the piece (Dead Cells' flame)
    styles        [variant, ...] — piece variants (the part after the dot) drawn
                  at another size than the rest of the logo; each is sized as a
                  line of its own in images2.0/custom/title/index.json
    pixel_grid    {"x0", "y0", "x1", "y1", "pitch", "palette", "tolerance"} —
                  rebuild pixel art from a blurry screenshot: one palette colour
                  per logo pixel on the measured grid, the rest see-through
    game          the game's id in data/games/ — the file name every piece gets
    source        the logo, transparent background, as big as can be found
    pieces        {name: [x, y]} — a point inside each piece's fill, in source
                  pixels. The name is the letter; "g.2" is a second G from the
                  same logo (title/g/<game>__2.png). The nearest fill pixel
                  is used, so near is enough;
                  [[x, y], ...] for a piece whose fill is in several parts
    ignore        [[x, y], ...] — fill to leave out entirely (Balatro's ace)
    adopt_strays  default true: fill that is no piece's joins the nearest one.
                  false when that fill is whole letters left out on purpose
    keep_original names of pieces that keep their own pixels (cards, icons)
    splits        [{"pieces": [upper, lower], "lower": name, "x_min": x,
                    "line": [[x, y], ...]}] — two pieces whose fills touch:
                  pixels at or right of x_min and on or below the line go to
                  `lower`, the rest to the other
    restore       [{"piece": name, "polygon": [[x, y], ...], "copy_column": x}]
                  — part of a piece another piece hid; it is added to the piece
                  and painted with the colours of the piece's column `copy_column`
    extra_ink     [{"piece": name, "polygon": [[x, y], ...], "clear": px,
                    "loose": bool}] — the
                  outline inside the polygon (ink and glow) belongs to the piece
                  however far from its fill, except within `clear` of another
                  piece's fill (default: the outline width). Hades' A's thorns,
                  which run down into the gap by the H; loose keeps parts
                  that do not touch the letter (blood drops)
    fill          optional {"min_alpha": 200, "min_brightness": 140,
                  "min_channel": n} — what counts as fill. Defaults suit a light
                  fill in a dark outline; min_channel keeps a coloured glow out
                  of a white fill; "max_brightness": n with "min_brightness":
                  -1 makes fill the DARK pixels (black letters, Mewgenics);
                  "rows": [y0, y1] keeps fill to those rows; "exclude_white": n
                  and "exclude_grey": {"spread", "below"} leave a white sticker
                  border and a grey shadow out of the fill; "inside_white": n makes fill what a
                  white line encloses; "region": [[x, y], ...] keeps fill to a
                  polygon; "not_colour": [r, g, b] (with
                  "not_tolerance") makes fill everything that is not the plate
                  the letters sit on; "close": n with "close_region": [x0, y0,
                  x1, y1] shuts cracks that cross a letter
    cut           scissors instead of paint: every pixel kept is the logo's own.
                  {"reach": px or {piece: px, "*": px} — how far from its fill a
                  piece reaches; "background": {"colour": [r, g, b],
                  "tolerance": n, "min_area": px, "grow": px, "spread_through":
                  {"min_green": n, "max_red": n}} — a shape behind the letters,
                  found as big regions of its colour (so a letter's own glow of
                  that colour is never it) and followed out through its glow;
                  "erase": [{"piece": name, "polygon": [[x, y], ...],
                  "colour": [r, g, b], "tolerance": n}] — cut away by hand
                  (bits of the background's outline); with a colour, only that
                  colour inside the polygon goes (a mark, not the ink round it);
                  "band": {"colour": [r, g, b], "width": px, "close": n,
                  "open": n, "skip": [pieces]} — for letters set in a plate:
                  the letter tidied into one shape, with an even band of the
                  plate's colour round it instead of the plate as cut. Also
                  for a rough inked outline (red Hades): "shape": "round",
                  "join": 0 (keep gaps split on purpose), "visible_face": true,
                  "face_colour": [r, g, b], "shape": "source" (with "max_brightness",
                  "min_alpha", "edge_smooth", "min_width", "max_width",
                  "outline_open", "fill_small_holes": px) takes the band's shape from the
                  logo's own outline, cleaned, "face_defringe": px recolours the face's rim from just inside,
                  "face_min_brightness": n recolours darker flecks on the face
                  (width 0: the face alone, no outline), "edge_soft": n and "edge_sharp": n set how soft the scaled
                  edges are (low soft, high sharp: crisp), "upscale_soft": n softens the
                  edges as they are scaled up, "keep": [{"piece", "polygon"}] for
                  ink drawn past the outline (a spike); "colour": "plate"
                  takes the band from the nearest plate pixel ("plate_max": n
                  and "plate_gap": px keep light edge pixels out of it), "whole_letter"
                  bands the face with its own outline and counters (Uma Musume),
                  "hole_colour" paints another face showing in a hole;
                  "as_drawn": [{"piece", "polygon"}] (in cut) — inside the
                  polygon, the logo's own pixels exactly (no redraw), over a
                  band grown round the rest of the letter;
                  "extrude": {"dx", "dy", "colour", "skip"} (in cut) gives a
                  block letter its 3D side by sweeping its face (Isaac);
                  "outline_max": n keeps only dark pixels past the face (not
                  a glow), "side": {"dy", "dx"} adds the dark 3D side the face
                  sweeps over, "close_dark": n brings in dark counters;
                  "shared_outline": true or [pieces] (in cut) lets a line two
                  letters share belong to both;
                  "hard_edge": [pieces] — pixel-font letters, every pixel fully
                  on or off; "scale": n — write the letters n times the logo's
                  size, shapes redrawn crisp (for a small source logo; an
                  inked logo is redrawn in two tones, face and outline);
                  "despeckle": px — specks up to that size on a letter's face
                  are filled with "fill_colour"; "restore": [{"piece": name,
                  "polygon": [[x, y], ...]}] — part of a letter another is
                  drawn over, rebuilt in "fill_colour" with an outline of
                  "outline_width" in "outline_colour"}
                  "min_part": px drops loose flecks smaller than that;
                  "silhouette": true scales letters with a clean edge;
                  "keep_small_holes": px keeps dark marks inside a letter;
                  "recast_shadow": {"spread", "dx", "dy", "blur", "alpha",
                  "colour"} draws the logo's shadow again from each letter's
                  own shape (measured off the logo);
                  "own_by_shadow": {"dx", "dy", "grow"} gives a drop shadow to
                  the letter casting it, not the nearest one;
                  "smooth_scale": true scales the cut as it is, smoothly
                  (a painted logo kept with its soft shadow);
                  "pixel_outline": {"colour", "width"} draws an even ring of
                  whole pixels round the face;
                  "outline_colours": [[r, g, b], ...] keeps only those colours
                  past the face (a pixel-art letter's edge);
                  "keep_min_alpha": n keeps only pixels that solid past the face
                  (the outline, not a soft shadow), and the 2x/4x silhouette
                  keeps their own alpha;
                  "see_through": [{"polygon", "max_brightness"}] makes the
                  backing showing through gaps in a polygon see-through;
                  "defringe": px recolours the outermost px of a letter from
                  just inside it (no dark rim from the backing it sat on)
    assign        [{"from": piece, "to": piece, "polygon": [[x, y], ...]}] —
                  fill inside the polygon moved from one piece to another
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
    if "exclude_white" in f:  # a white sticker border round the logo is no letter
        m &= ~(A[..., :3].min(-1) > f["exclude_white"])
    if "exclude_grey" in f:  # nor is a grey drop shadow (low saturation, not bright)
        g = f["exclude_grey"]
        m &= ~(((A[..., :3].max(-1) - A[..., :3].min(-1)) < g.get("spread", 25))
               & (A[..., :3].max(-1) < g.get("below", 215)))
    if "max_brightness" in f:  # dark letters on nothing (Mewgenics' black ink)
        m &= A[..., :3].max(-1) <= f["max_brightness"]
    if "min_channel" in f:  # white fills: every channel high, so a coloured glow is not fill
        m &= A[..., :3].min(-1) > f["min_channel"]
    if "not_colour" in f:  # fill is anything that is not the plate the letters sit on
        m = (A[..., 3] > f.get("min_alpha", 200)) & (
            np.abs(A[..., :3] - np.array(f["not_colour"])).max(-1) > f.get("not_tolerance", 14))
    if "inside_white" in f:
        # letters whose face sits inside a white line (Uma Musume): fill is
        # what the white line encloses, less the white itself
        wl = (A[..., 3] > 200) & (A[..., :3].min(-1) > f["inside_white"])
        m = nd.binary_fill_holes(wl) & ~wl & (A[..., 3] > 200)
    if "colours" in f:  # pixel art: fill is exactly these palette colours (Loop Hero)
        m = np.zeros(A.shape[:2], bool)
        for col in f["colours"]:
            m |= (A[..., 3] > 0) & (np.abs(A[..., :3] - np.array(col)).max(-1) <= f.get("tolerance", 6))
    if "rows" in f:  # only these rows of the logo (one line of a two-line logo)
        m = m.copy()
        m[: f["rows"][0]] = False
        m[f["rows"][1]:] = False
    if "region" in f:  # only fill inside this polygon (a figure that touches a plate)
        m &= _polygon_mask(m.shape, f["region"])
    if "close" in f:
        # cracks drawn across a letter would split it into parts; close them,
        # but only inside the region given (not across gaps between letters)
        x0, y0, x1, y1 = f.get("close_region", [0, 0, m.shape[1], m.shape[0]])
        sub = nd.binary_closing(m[y0:y1, x0:x1], iterations=f["close"], border_value=0)
        m = m.copy()
        m[y0:y1, x0:x1] |= sub
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
    # Fill inside a polygon moved from one piece to another (red Hades: the A's
    # middle band runs on into the D's stem along the slash).
    for asg in cfg.get("assign", []):
        moved = pieces[asg["from"]] & _polygon_mask((H, W), asg["polygon"])
        pieces[asg["from"]] &= ~moved
        pieces[asg["to"]] |= moved
    # Stray bits of fill (a stripe's tip cut off by an outline) join the
    # piece they are nearest. Off for a logo whose other fill is whole letters
    # that are not wanted (Gungeon's repeated E's and T's).
    if not cfg.get("adopt_strays", True):
        return pieces
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


def _upscale(A, out, box, band_masks, s, hard=False, face=None, silhouette=False, silhouette_cut=0,
             edge_soft=None, sharp=2.5):
    """A letter at `s` times the logo's resolution, so it stays crisp on a big
    title. A small source shown large is the blur this exists to avoid.

    A pixel-font letter is scaled pixel for pixel (each source pixel a sharp
    block). A plate letter has its SHAPES redrawn at the new size, the letter's
    edge and its band each as one clean anti-aliased curve, while what is
    inside the letter (texture, cracks, stripes) is scaled pixel for pixel:
    smooth scaling softened every stripe and highlight inside the letter.
    """
    x0, y0, x1, y1 = box
    w, h = (x1 - x0) * s, (y1 - y0) * s
    crop = Image.fromarray(out[y0:y1, x0:x1])

    def cover(mask, sigma=0.0, sharp=2.5):
        # the mask scaled smoothly, then sharpened to a one-pixel soft edge;
        # with sigma, softened first so a curve has no source-pixel steps
        m = nd.gaussian_filter(mask.astype(float), sigma) if sigma else mask.astype(float)
        v = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), float) / 255
        return np.clip((v - 0.5) * sharp + 0.5, 0, 1)

    def extend(colours, mask):
        # each pixel takes the colour of the nearest pixel in mask, scaled up
        _, (iy, ix) = nd.distance_transform_edt(~mask, return_indices=True)
        return np.asarray(Image.fromarray(colours[iy, ix].clip(0, 255).astype(np.uint8))
                          .resize((w, h), Image.NEAREST), float)

    if silhouette:
        # One-colour letters (Mewgenics): the shape redrawn as one clean
        # anti-aliased edge at the new size, the colour run out under it.
        sil = out[y0:y1, x0:x1, 3] > (silhouette_cut if silhouette_cut else 127)
        rgb = extend(out[y0:y1, x0:x1, :3].astype(float), sil)
        if silhouette_cut:
            # a translucent outline (Slay the Spire's) keeps its own alpha;
            # only the shape's edge is redrawn crisp
            shape = cover(sil)
            inside_a = extend(np.repeat(out[y0:y1, x0:x1, 3:4].astype(float), 3, -1), sil)[..., 0] / 255
            alpha = shape * inside_a
        else:
            a_hi = np.asarray(Image.fromarray(out[y0:y1, x0:x1, 3]).resize((w, h), Image.LANCZOS), float) / 255
            alpha = np.clip((a_hi - 0.5) * 2.5 + 0.5, 0, 1)
        return Image.fromarray(np.dstack([rgb.clip(0, 255), alpha * 255]).astype(np.uint8))
    if face is not None and not hard and band_masks is None:
        # An inked logo (red Hades): two tones, the face and the outline round
        # it, each edge redrawn as one clean curve at the new size.
        cut_px = out[y0:y1, x0:x1].astype(float)
        f = face[y0:y1, x0:x1]
        sil = cut_px[..., 3] > 127
        ink = sil & ~f
        c_face = cover(f)
        rgb = extend(cut_px[..., :3], f) * c_face[..., None] + extend(cut_px[..., :3], ink if ink.any() else sil) * (1 - c_face[..., None])
        return Image.fromarray(np.dstack([rgb.clip(0, 255), cover(sil) * 255]).astype(np.uint8))
    if hard or band_masks is None:
        return crop.resize((w, h), Image.NEAREST)
    clean, grown, plate = (m[y0:y1, x0:x1] if m.ndim >= 2 else m for m in band_masks[:3])
    if plate.ndim == 3:  # a band in colours that vary: scaled with it
        plate = np.asarray(Image.fromarray(plate.clip(0, 255).astype(np.uint8)).resize((w, h), Image.NEAREST), float)
    soft = band_masks[3] if len(band_masks) > 3 else 0

    # the letter's colours, run out past its edge so the redrawn edge never
    # shows the plate's black from inside
    _, (iy, ix) = nd.distance_transform_edt(~clean, return_indices=True)
    inside = out[y0:y1, x0:x1, :3][iy, ix].clip(0, 255).astype(np.uint8)
    # pixel art keeps its pixels; a painted logo (Slay the Spire) is scaled
    # smoothly, or its brushwork turns into blocks
    hi = np.asarray(Image.fromarray(inside).resize((w, h), Image.LANCZOS if soft >= 2 else Image.NEAREST), float)
    es = edge_soft if edge_soft is not None else soft * 0.6
    c_letter, c_band = cover(clean, es, sharp), cover(grown, es, sharp)
    if not (grown & ~clean).any():
        rgb = hi  # no band (Slay the Spire, outline dropped): the edge stays the letter's colour
        # smooth scaling rings a little darker beside a sharp change of shade;
        # the letter's own darkest shade bounds it
        lo = np.percentile(out[y0:y1, x0:x1, :3][clean].max(-1), 0.5) if clean.any() else 0
        dull = rgb.max(-1) < lo
        if dull.any() and (~dull).any():
            _, (dy_, dx_) = nd.distance_transform_edt(dull, return_indices=True)
            rgb = rgb[dy_, dx_]
    else:
        rgb = hi * c_letter[..., None] + plate * (1 - c_letter[..., None])
    rgb = np.broadcast_to(rgb, (h, w, 3))
    alpha = np.maximum(c_letter, c_band)
    return Image.fromarray(np.dstack([rgb.clip(0, 255), alpha * 255]).astype(np.uint8))


def cut(cfg_path: Path, preview: Path | None = None) -> list[Path]:
    cfg = json.loads(cfg_path.read_text())
    src = cfg_path.parent / cfg["source"]
    A = np.array(Image.open(src).convert("RGBA")).astype(float)
    pg = cfg.get("pixel_grid")
    if pg:
        # A blurry screenshot of pixel art (Spelunky Classic): one colour per
        # logo pixel, sampled at the middle of its block on the measured grid,
        # snapped to the logo's palette; anything nearer no palette colour
        # is background and see-through.
        x0, y0, p_ = pg["x0"], pg["y0"], pg["pitch"]
        cols, rows = int((pg["x1"] - x0) / p_), int((pg["y1"] - y0) / p_)
        pal = np.array(pg["palette"], float)
        small = np.zeros((rows, cols, 4))
        samp = np.zeros((rows, cols, 3))
        for r_ in range(rows):
            for c_ in range(cols):
                cx, cy = x0 + (c_ + 0.5) * p_, y0 + (r_ + 0.5) * p_
                blk = A[int(cy - 3):int(cy + 4), int(cx - 3):int(cx + 4), :3].reshape(-1, 3)
                col = np.median(blk, 0)
                d_ = np.abs(pal - col).max(-1)
                if d_.min() <= pg.get("tolerance", 24):
                    small[r_, c_, :3] = pal[d_.argmin()]
                    small[r_, c_, 3] = 255
                samp[r_, c_] = col
        # a pixel or two INSIDE a letter whose colour matched nothing (a
        # crack shade) is still the letter's: nearest palette colour
        on = small[..., 3] > 0
        gaps = nd.binary_fill_holes(on) & ~on
        lab_g, ng = nd.label(gaps)
        if ng:
            sz = nd.sum(gaps, lab_g, range(1, ng + 1))
            for gi in np.flatnonzero(sz <= pg.get("fill_gaps", 3)):
                for r_, c_ in zip(*np.where(lab_g == gi + 1)):
                    small[r_, c_, :3] = pal[np.abs(pal - samp[r_, c_]).max(-1).argmin()]
                    small[r_, c_, 3] = 255
        A = small
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
    obs = (cfg.get("cut") or {}).get("own_by_shadow")
    if obs:
        # A drop shadow belongs to the letter that casts it: pixels go to
        # the letter whose face OR shadow (face pushed by the shadow's
        # offset) is nearest, so a close neighbour does not take a bite out
        # of the shadow (Slay the Spire 2's a and y).
        Ds = []
        for n_ in names:
            cast = _extrude(pieces[n_], obs.get("grow", 0), obs["dx"], obs["dy"])
            Ds.append(nd.distance_transform_edt(~cast))
        owner = np.stack(Ds).argmin(0)
        for i_, n_ in enumerate(names):  # a letter's own face is always its own
            owner[pieces[n_]] = i_
        # ...and a pixel that touches another face directly is that face's
        # outline, not this letter's shadow
        near = np.stack([D[n_] for n_ in names])
        close = near.min(0) <= obs.get("outline", 6)
        owner[close] = near.argmin(0)[close]
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
    body_centers = {}
    body_heights = {}
    body_xs = {}
    body_widths = {}
    line_centers = {}
    out_dir_game = cfg["game"]
    for i, n in enumerate(names):
        mine = owner == i
        f = pieces[n]
        rgb = np.zeros((H, W, 3))
        band_masks = None
        face = None
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
            fill_colour = np.array(cut.get("fill_colour", [255, 255, 255]), float)
            painted = np.zeros((H, W), bool)
            # Specks of the outline's colour on a letter's face (red Hades'
            # spatter) are filled in with the face's colour.
            if cut.get("despeckle"):
                holes = nd.binary_fill_holes(f) & ~f
                lab_h, nh = nd.label(holes)
                if nh:
                    sizes = nd.sum(holes, lab_h, range(1, nh + 1))
                    specks = np.isin(lab_h, 1 + np.flatnonzero(sizes <= cut["despeckle"]))
                    f = f | specks
                    painted |= specks
            # A part of this letter another letter is drawn over, rebuilt: the
            # polygon filled with the letter's face colour, given an outline of
            # the logo's own width and colour round it.
            restored = np.zeros((H, W), bool)
            for rs in cut.get("restore", []):
                if rs["piece"] == n:
                    restored |= _polygon_mask((H, W), rs["polygon"])
            if restored.any():
                f = f | restored
                painted |= restored
            ds = nd.distance_transform_edt(~f)
            # shared_outline: a white line between two letters belongs to both
            so = cut.get("shared_outline")
            shared = bool(so) and (so is True or n in so)  # true, or a list of pieces
            keep = f | ((a > 0) & ~background & (True if shared else mine) & (ds <= reach))
            if cut.get("own_by_shadow"):
                # each letter keeps its whole shadow, up to where a neighbour's
                # own face and outline begin
                d_other = np.min([D[o_] for o_ in names if o_ != n], 0) if len(names) > 1 else np.full((H, W), 1e9)
                keep = f | ((a > 0) & ~background & (ds <= reach) & mine
                            & (d_other > cut["own_by_shadow"].get("outline", 6)) & ~fill)
            if shared:
                # ...but never past it into the next letter's face (counters a
                # letter encloses come back with whole_letter's hole filling)
                keep &= f | ~fill
            if "outline_min" in cut:
                # past the face, only the white line itself (not the plate)
                keep &= f | (A[..., :3].min(-1) >= cut["outline_min"])
            if "outline_colours" in cut:
                # past the face, only the letter's own edge colours (pixel art)
                ok = np.zeros((H, W), bool)
                for col in cut["outline_colours"]:
                    ok |= np.abs(A[..., :3] - np.array(col)).max(-1) <= 6
                keep &= f | ok
            if "keep_min_alpha" in cut:
                # past the face, only what is solid enough: the outline, not
                # the soft shadow fading out round it (Slay the Spire)
                keep &= f | (a >= cut["keep_min_alpha"])
            if "outline_max" in cut:
                # past the face, only the dark outline (not the glow round it)
                keep &= f | (A[..., :3].max(-1) <= cut["outline_max"])
            if "side" in cut:
                # a 3D side drawn straight below the face (Repentance): the dark
                # pixels the face sweeps over going down, however far from it
                sw = f.copy()
                for k in range(1, cut["side"]["dy"] + 1):
                    sw |= nd.shift(f, (k, round(cut["side"].get("dx", 0) * k / cut["side"]["dy"])), order=0, cval=False)
                keep |= sw & (A[..., :3].max(-1) <= cut.get("outline_max", 60)) & (a > 200)
            if cut.get("close_dark"):
                # dark counters (S's notches, A's holes) a letter wraps round
                closed = nd.binary_closing(keep, np.ones((3, 3)), iterations=cut["close_dark"], border_value=0)
                keep |= closed & (A[..., :3].max(-1) <= cut.get("outline_max", 60)) & (a > 200)
            for ex in cfg.get("extra_ink", []):
                if ex["piece"] == n:
                    d_other = np.min([D[o] for o in names if o != n], 0)
                    keep |= (_polygon_mask((H, W), ex["polygon"]) & (a > 0) & ~background
                             & (d_other > ex.get("clear", 4)))
            for er in cut.get("erase", []):
                if er["piece"] == n:
                    gone = _polygon_mask((H, W), er["polygon"])
                    if "colour" in er:  # only that colour inside it (a mark, not the ink round it)
                        gone &= np.abs(A[..., :3] - np.array(er["colour"])).max(-1) <= er.get("tolerance", 40)
                    keep &= ~gone
            # only what is joined to the letter (diagonals count: a thorn's tip
            # is often a pixel wide)
            lab_k, _ = nd.label(keep, structure=np.ones((3, 3)))
            keep &= np.isin(lab_k, np.unique(lab_k[f & (lab_k > 0)]))
            for ex in cfg.get("extra_ink", []):
                if ex["piece"] == n and ex.get("loose"):
                    # drops that fly free of the letter (Repentance's blood) kept too
                    keep |= _polygon_mask((H, W), ex["polygon"]) & (a > 0) & ~background
            if cut.get("keep_small_holes"):
                # dark marks drawn inside a letter (rivets, bevel lines) stay;
                # a real counter, bigger, stays see-through
                holes = nd.binary_fill_holes(keep) & ~keep
                lab_h, nh = nd.label(holes)
                if nh:
                    sizes = nd.sum(holes, lab_h, range(1, nh + 1))
                    keep |= np.isin(lab_h, 1 + np.flatnonzero(sizes <= cut["keep_small_holes"]))
            for st_ in cut.get("see_through", []):
                # the backing showing through a gap (Nuclear Throne's slime):
                # see-through, not a dark mark
                if st_.get("piece", n) == n:
                    keep &= ~(_polygon_mask((H, W), st_["polygon"])
                              & (A[..., :3].max(-1) <= st_.get("max_brightness", 20)))
            rgb[keep] = A[keep][:, :3]
            al[keep] = a[keep] / 255
            rc = cut.get("recast_shadow")
            if rc:
                # The logo's shadow re-cast from this letter's own shape (Slay
                # the Spire 2: a soft dark band, nudged down-left), so a close
                # neighbour never clips it: the face over it, as drawn.
                m_ = nd.distance_transform_edt(~keep) <= rc["spread"]
                sh_ = nd.gaussian_filter(nd.shift(m_.astype(float), (rc["dy"], rc["dx"]), order=0),
                                         rc.get("blur", 2)) * rc.get("alpha", 160) / 255
                sh_ = np.where(keep, 0, sh_)
                out_a_ = al + sh_ * (1 - al)
                rgb = (rgb * al[..., None] + np.array(rc.get("colour", [0, 0, 0]), float) * (sh_ * (1 - al))[..., None]) \
                    / np.maximum(out_a_, 1e-6)[..., None]
                al = out_a_
            if cut.get("defringe"):
                # The letter's outermost pixels are a blend into the backing it
                # was cut from (Nuclear Throne's black): each takes the colour
                # of the nearest pixel further in, so no dark rim is left. The
                # shape is unchanged, holes and dark marks inside included.
                dn = nd.distance_transform_edt(keep)
                inner = keep & (dn > cut["defringe"])
                if inner.any():
                    _, (iy, ix) = nd.distance_transform_edt(~inner, return_indices=True)
                    rim = keep & ~inner
                    rgb[rim] = A[iy[rim], ix[rim], :3]
                    al[rim] = np.maximum(al[rim], 1.0)
            rgb[painted] = fill_colour
            al[painted] = 1
            if cut.get("min_part"):
                # loose flecks (streak ends, spatter) cut off from the letter
                lab_p, npart = nd.label(al > 0, structure=np.ones((3, 3)))
                if npart > 1:
                    sizes = nd.sum(al > 0, lab_p, range(1, npart + 1))
                    small = np.isin(lab_p, 1 + np.flatnonzero(sizes < cut["min_part"]))
                    al[small] = 0
                    keep &= ~small
                    painted &= ~small
            face = (f & keep) | painted  # fill that was erased is no face
            if restored.any():
                ow = cut.get("outline_width", 7)
                # measured from what is left of the face once erasing is done,
                # so a cut end gets its outline too
                dv = nd.distance_transform_edt(~((f & keep) | painted))
                ring = (dv > 0) & (dv <= ow) & (nd.distance_transform_edt(~restored) <= ow + 1)
                rgb[ring] = cut.get("outline_colour", [240, 20, 10])
                al[ring] = 1
                if cut.get("min_part"):  # and any sliver of that outline left loose
                    lab_p, npart = nd.label(al > 0, structure=np.ones((3, 3)))
                    sizes = nd.sum(al > 0, lab_p, range(1, npart + 1))
                    al[np.isin(lab_p, 1 + np.flatnonzero(sizes < cut["min_part"]))] = 0
            if cut.get("pixel_outline") and n not in cut.get("pixel_outline_skip", []):
                # pixel art: one even ring of the edge colour round the face,
                # holes included (Loop Hero's black edge is broken by the disc)
                po = cut["pixel_outline"]
                ring = nd.binary_dilation(f, structure=np.ones((3, 3)), iterations=po.get("width", 1)) & ~f
                rgb[ring] = po["colour"]
                al[ring] = 1
            if n in cut.get("hard_edge", []):
                # pixel-font letters: each pixel fully on or off, no soft fringe
                on = al >= 0.5
                al[:] = on
                rgb[~on] = 0
            ex_cfg = cut.get("extrude")
            if ex_cfg and n not in ex_cfg.get("skip", []):
                # A block-letter logo (Isaac): the face, and the 3D side made by
                # sweeping the face along the logo's depth, so a side the next
                # letter hid is whole again; in the side's own colour.
                face_m = f.copy()
                side = face_m.copy()
                steps = max(abs(ex_cfg["dx"]), abs(ex_cfg["dy"]))
                for k in range(1, steps + 1):
                    # a shift that falls off the edge, never wraps round to the other side
                    side |= nd.shift(face_m, (round(ex_cfg["dy"] * k / steps),
                                              round(ex_cfg["dx"] * k / steps)), order=0, cval=False)
                rgb[:] = 0
                al[:] = 0
                rgb[side] = ex_cfg["colour"]
                rgb[face_m] = A[face_m][:, :3]
                al[side] = 1
                band_masks = (face_m, side, np.array(ex_cfg["colour"], float), 0)
            band_cfg = cut.get("band")
            if band_cfg and n not in band_cfg.get("skip", []):
                # A plate logo (Gungeon): the letter's edge is the plate showing
                # round it. Rather than whatever plate falls within reach (which
                # follows every crack that touches the edge and leaves blotches),
                # the letter is tidied into one clean shape and given an even
                # band of the plate's colour, with the logo's 45-degree corners.
                st4 = nd.generate_binary_structure(2, 1)
                # the face as it stands once erasing is done
                base = (f & keep) | painted if band_cfg.get("visible_face") else f
                if band_cfg.get("whole_letter"):
                    # the letter is its face AND its own outline, counters too
                    base = nd.binary_fill_holes(keep & (a > 200))
                clean = base
                if band_cfg.get("close", 3):
                    clean = nd.binary_closing(clean, st4, iterations=band_cfg.get("close", 3))
                if band_cfg.get("open", 1):
                    # (thin slivers off: the slash's white streak caught in an outline)
                    clean = nd.binary_opening(clean, st4, iterations=band_cfg.get("open", 1))
                if band_cfg.get("smooth"):
                    # ticks and hooks a ragged hand-drawn face leaves, smoothed off
                    clean = nd.gaussian_filter(clean.astype(float), band_cfg["smooth"]) > 0.5
                if band_cfg.get("fill_small_holes"):
                    # dark dashes drawn inside a face (Everything is Crab's i
                    # and s) are filled with the face's own colour; real
                    # counters, bigger, stay open
                    hl = nd.binary_fill_holes(clean) & ~clean
                    lab_h, nh = nd.label(hl)
                    if nh:
                        sz = nd.sum(hl, lab_h, range(1, nh + 1))
                        small = np.isin(lab_h, 1 + np.flatnonzero(sz <= band_cfg["fill_small_holes"]))
                        _, (hy, hx) = nd.distance_transform_edt(~clean, return_indices=True)
                        A[small, :3] = A[hy[small], hx[small], :3]
                        clean = clean | small
                if cut.get("min_part"):
                    lab_c, ncl = nd.label(clean, structure=np.ones((3, 3)))
                    if ncl:
                        sizes = nd.sum(clean, lab_c, range(1, ncl + 1))
                        clean &= ~np.isin(lab_c, 1 + np.flatnonzero(sizes < cut["min_part"]))
                # The band's outer edge is grown from the WHOLE letter, its
                # parts joined across the plate lines between them first, so the
                # edge runs straight past a join instead of dipping in a V
                # between the two parts' corners.
                # (a SQUARE closing: a diamond one leaves a small V of its own)
                # An inked logo whose letters are split on purpose (red Hades'
                # slash) sets join 0, so its gaps stay open.
                # A part kept exactly as drawn (Repentance's blood) is no part of
                # the shape the band is grown round: the band rings the letter
                # alone, and the drawn part sits over it
                drawn = np.zeros((H, W), bool)
                for ad in cut.get("as_drawn", []):
                    if ad["piece"] == n:
                        drawn |= _polygon_mask((H, W), ad["polygon"])
                clean = clean & ~drawn
                whole = clean
                if band_cfg.get("join", 5):
                    whole = nd.binary_closing(clean, np.ones((3, 3)), iterations=band_cfg["join"] if "join" in band_cfg else 5,
                                              border_value=0) | clean
                if band_cfg.get("shape") == "source":
                    # the logo's OWN outline shape (Slay the Spire's is heavier
                    # below), told from the shadow by its colour, then given
                    # a clean smooth edge and one even colour
                    src_ol = (keep & (a >= band_cfg.get("min_alpha", 100))
                              & (A[..., :3].max(-1) <= band_cfg.get("max_brightness", 35)))
                    grown = nd.binary_fill_holes(src_ol | whole) & nd.binary_dilation(src_ol | whole, iterations=2)
                    grown = nd.binary_opening(nd.binary_closing(grown, st4, iterations=2), st4, iterations=1) | whole
                    if band_cfg.get("min_width"):
                        # where the outline was shared with a neighbour (and so
                        # cut away), at least the logo's usual width all round
                        grown |= nd.distance_transform_edt(~whole) <= band_cfg["min_width"]
                    if band_cfg.get("max_width"):
                        # nor wider than the logo ever draws it: bits of a
                        # neighbour's outline or the shadow stay out
                        grown &= nd.distance_transform_edt(~whole) <= band_cfg["max_width"]
                    if band_cfg.get("outline_open"):
                        # small bumps and nicks along the outer edge, rounded off
                        r_ = band_cfg["outline_open"]
                        disk = (np.add.outer(np.arange(-r_, r_ + 1) ** 2, np.arange(-r_, r_ + 1) ** 2) <= r_ * r_)
                        grown = nd.binary_closing(nd.binary_opening(grown, disk), disk) | whole
                    grown = nd.gaussian_filter(grown.astype(float), band_cfg.get("edge_smooth", 1.2)) > 0.5
                    # counters stay open: only fill holes the source outline filled
                    hole_open = nd.binary_fill_holes(whole | src_ol) & ~(whole | src_ol) & (a < band_cfg.get("min_alpha", 100))
                    grown &= ~nd.binary_opening(hole_open, iterations=1)
                    grown |= whole
                elif band_cfg.get("shape") == "round":  # serif letters: an even band, round corners
                    grown = nd.distance_transform_edt(~whole) <= band_cfg.get("width", 5)
                else:
                    grown = whole.copy()
                    for k in range(band_cfg.get("width", 5)):  # square, cross, square...: an octagon
                        grown = nd.binary_dilation(grown, structure=np.ones((3, 3)) if k % 2 == 0 else st4)
                # ink the logo drew past any outline (red Hades' A spike) kept
                for kp in band_cfg.get("keep", []):
                    if kp["piece"] == n:
                        grown |= _polygon_mask((H, W), kp["polygon"]) & keep & ~clean & (a > 127)
                face_rgb = rgb.copy()
                rgb[:] = 0
                al[:] = 0
                if "face_colour" in band_cfg:
                    rgb[clean] = band_cfg["face_colour"]
                else:
                    rgb[clean] = A[clean][:, :3]
                if band_cfg.get("face_defringe"):
                    # smoothing can pull a notch of the dropped outline into the
                    # face: those pixels take the nearest face colour too
                    gained = clean & ~f
                    if gained.any() and f.any():
                        _, (gy, gx) = nd.distance_transform_edt(~f, return_indices=True)
                        rgb[gained] = A[gy[gained], gx[gained], :3]
                    # the face's outermost pixels blend into the outline that is
                    # being dropped; they take the colour just inside instead
                    dn = nd.distance_transform_edt(clean)
                    inner = clean & (dn > band_cfg["face_defringe"])
                    if inner.any():
                        _, (iy, ix) = nd.distance_transform_edt(~inner, return_indices=True)
                        rim = clean & ~inner & f
                        rgb[rim] = A[iy[rim], ix[rim], :3]
                if "face_min_brightness" in band_cfg:
                    # dark flecks the outline left on the face (Slay the Spire's
                    # brushwork where the grey met the gold) take the colour of
                    # the nearest bright face pixel
                    bright = clean & (rgb.max(-1) >= band_cfg["face_min_brightness"])
                    dull = clean & ~bright
                    if dull.any() and bright.any():
                        _, (by, bx) = nd.distance_transform_edt(~bright, return_indices=True)
                        rgb[dull] = rgb[by[dull], bx[dull]]
                if "hole_colour" in band_cfg:
                    # another face showing inside this letter's hole (Repentance's
                    # C) is painted over in the hole's own colour
                    other = nd.binary_dilation(clean & ~keep & fill, iterations=3) & clean & ~f
                    rgb[other] = band_cfg["hole_colour"]  # with its soft edge
                al[clean] = 1
                ring = grown & ~clean
                if band_cfg["colour"] == "plate":
                    # the band in the plate's own colours (Uma Musume's plate
                    # is a gradient), each pixel from the nearest plate pixel
                    # only the plate OUTSIDE the word's white line: between the
                    # letters it is mixed with their faces and lines
                    wl = (a > 200) & (A[..., :3].min(-1) > band_cfg.get("plate_white", 200))
                    word = nd.binary_dilation(nd.binary_fill_holes(wl), iterations=band_cfg.get("plate_gap", 3))
                    plate = (a > 240) & ~word
                    if "plate_max" in band_cfg:
                        # the white line's soft edge is no plate: no light spots in the band
                        plate &= A[..., :3].min(-1) <= band_cfg["plate_max"]
                    _, (iy, ix) = nd.distance_transform_edt(~plate, return_indices=True)
                    band_rgb = A[iy, ix, :3]
                    rgb[ring] = band_rgb[ring]
                    band_masks = (clean, grown, band_rgb, band_cfg.get("upscale_soft", band_cfg.get("smooth", 0)))
                else:
                    rgb[ring] = band_cfg["colour"]
                    band_masks = (clean, grown, np.array(band_cfg["colour"], float), band_cfg.get("upscale_soft", band_cfg.get("smooth", 0)))
                al[ring] = 1
                dr = drawn & (a > 0)
                rgb[dr] = A[dr][:, :3]  # so the letter's box takes them in
                al[dr] = a[dr] / 255
                face = None
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
        # where the letter itself sits in the piece, from 0 (top) to 1: a
        # piece with something attached above or below (an eye stalk, a
        # knife, slime) is centred on the line by its letter, not its whole
        # The letter's own box, measured from its face (the fill), so a glow,
        # a shadow pushed to one side or an outline never moves its centre or
        # changes its size; `body` rows in the config override the height for
        # a piece with something attached (an eye stalk, a knife, slime).
        fy, fx = np.where(pieces[n] & (out[..., 3] > 0))
        if fy.size == 0:
            fy, fx = np.where(out[..., 3] > 127)
        by0, by1 = fy.min(), fy.max() + 1
        bd = cfg.get("body", {}).get(n)
        if bd:
            # and its width from those rows only, so a stalk or a drip off
            # to one side cannot pull the letter's middle with it
            by0, by1 = bd
            rows = (fy >= by0) & (fy < by1)
            if rows.any():
                fx = fx[rows]
        bx0, bx1 = fx.min(), fx.max() + 1
        body_centers[n] = ((by0 + by1) / 2 - y0) / (y1 - y0)
        # `centre`: these rows sit on the line instead of the box's middle.
        # The box (and so the size) is left as measured
        cr = cfg.get("centre", {}).get(n)
        if cr:
            line_centers[n] = ((cr[0] + cr[1]) / 2 - y0) / (y1 - y0)
        body_heights[n] = (by1 - by0) / (y1 - y0)
        body_xs[n] = ((bx0 + bx1) / 2 - x0) / (x1 - x0)
        body_widths[n] = (bx1 - bx0) / (x1 - x0)
        # "g.2" is a second G from the same logo: title/g/<game>__2.png. Two
        # underscores, never one: slay_the_spire's second e was once
        # e/slay_the_spire_2.png, the very file slay_the_spire_2's e is.
        letter, _, variant = n.partition(".")
        dest = OUT_DIR / letter / (f"{out_dir_game}__{variant}.png" if variant else f"{out_dir_game}.png")
        dest.parent.mkdir(parents=True, exist_ok=True)
        img = Image.fromarray(out[y0:y1, x0:x1])
        scale = int((cut or {}).get("scale", 1))
        if scale > 1 and (cut or {}).get("smooth_scale"):
            # a painted logo with a soft shadow (Slay the Spire 2): scaled as
            # it is, smoothly, colour weighted by alpha so edges stay clean
            crop = out[y0:y1, x0:x1].astype(float)
            al_ = crop[..., 3:4] / 255
            pre = np.concatenate([crop[..., :3] * al_, crop[..., 3:4]], -1).clip(0, 255).astype(np.uint8)
            big = np.asarray(Image.fromarray(pre).resize(((x1 - x0) * scale, (y1 - y0) * scale), Image.LANCZOS), float)
            ab = big[..., 3:4] / 255
            col = np.where(ab > 0, big[..., :3] / np.maximum(ab, 1e-6), 0)
            px = np.concatenate([col, big[..., 3:4]], -1).clip(0, 255).astype(np.uint8)
            # the faint specks smooth scaling rings off a cut edge
            lab_s, ns = nd.label(px[..., 3] > 0, structure=np.ones((3, 3)))
            if ns > 1:
                sizes = nd.sum(px[..., 3] > 0, lab_s, range(1, ns + 1))
                px[np.isin(lab_s, 1 + np.flatnonzero(sizes < sizes.max() * 0.01))] = 0
            img = Image.fromarray(px)
        elif scale > 1:
            img = _upscale(A, out, (x0, y0, x1, y1), band_masks, scale,
                           hard=n in (cut or {}).get("hard_edge", []), face=face,
                           silhouette=bool((cut or {}).get("silhouette")),
                           silhouette_cut=(cut or {}).get("keep_min_alpha", 0),
                           edge_soft=((cut or {}).get("band") or {}).get("edge_soft"),
                           sharp=((cut or {}).get("band") or {}).get("edge_sharp", 2.5))
        for ad in (cut or {}).get("as_drawn", []):
            if ad["piece"] != n:
                continue
            # Inside this polygon the logo's own pixels, untouched: no band, no
            # redraw (Repentance's blood, which a glow round every drop ruins).
            # where the logo drew nothing, the letter's own outline stays
            poly = (_polygon_mask((H, W), ad["polygon"]) & (a > 0))[y0:y1, x0:x1]
            src = A[y0:y1, x0:x1].clip(0, 255).astype(np.uint8)
            if img.size != (x1 - x0, y1 - y0):
                src = np.asarray(Image.fromarray(src).resize(img.size, Image.LANCZOS))
                poly = np.asarray(Image.fromarray((poly * 255).astype(np.uint8)).resize(img.size, Image.NEAREST)) > 127
            # laid OVER the letter, not swapped in: the drawn part's soft edge
            # would otherwise punch see-through gaps in the outline under it
            top = np.zeros_like(src)
            top[poly] = src[poly]
            base_img = img.convert("RGBA")
            base_img.alpha_composite(Image.fromarray(top))
            img = base_img
        if scale > 1:
            # the redraw can leave a pixel or two of anti-aliasing alone at a
            # corner: anything that small and apart from the letter goes
            px = np.array(img)
            lab_s, ns = nd.label(px[..., 3] > 0, structure=np.ones((3, 3)))
            if ns > 1:
                sizes = nd.sum(px[..., 3] > 0, lab_s, range(1, ns + 1))
                px[np.isin(lab_s, 1 + np.flatnonzero(sizes < 10 * scale * scale))] = 0
                img = Image.fromarray(px)
        img.save(dest, optimize=True)
        written.append(dest)
        print(f"  {dest.relative_to(ROOT)}  {img.width}x{img.height}")

    # The index: which config, game and style made each piece, so the title can
    # size every line of every logo against its own letters (a logo's small
    # line is not drawn at its big line's height).
    index_path = OUT_DIR / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    index = {k: v for k, v in index.items() if v.get("config") != cfg_path.name}
    for n_, dest_ in zip(names, written):
        _, _, variant_ = n_.partition(".")
        index[str(dest_.relative_to(OUT_DIR))] = {
            "game": cfg["game"],
            "config": cfg_path.name,
            # pieces drawn at another size in the same logo (Gungeon's pink
            # line, Nuclear Throne's THRONE) are listed as styles of their own
            "style": cfg_path.stem + ("__" + variant_ if variant_ in cfg.get("styles", []) else ""),
            "body_center": round(body_centers[n_], 4),
            # the letter's own height as a share of the piece's, so every
            # letter can be drawn the same size whatever is attached to it
            "body_height": round(body_heights[n_], 4),
            "body_center_x": round(body_xs[n_], 4),
            "body_width": round(body_widths[n_], 4),
        }
        # `size` and `pad` are the owner's eye on a piece, by name or "*" for
        # the whole config: drawn this many times as big (on the baseline), and
        # this much of the line kept clear either side (TitleLetters)
        for key in ("size", "pad"):
            val = cfg.get(key, {}).get(n_, cfg.get(key, {}).get("*"))
            if val is not None:
                index[str(dest_.relative_to(OUT_DIR))][key] = val
        if n_ in cfg.get("lowercase", []):
            # a lowercase SHAPE (Darkest Dungeon's a, Slay the Spire's e): the
            # title draws it at the x-height in a lowercase place, and lets a
            # g or y hang below the line (TitleLetters._size)
            index[str(dest_.relative_to(OUT_DIR))]["form"] = "lower"
        if n_ in line_centers:
            # what sits on the line's middle, when it is not the box's middle
            index[str(dest_.relative_to(OUT_DIR))]["line_center"] = round(line_centers[n_], 4)
    index_path.write_text(json.dumps(dict(sorted(index.items())), indent=1) + "\n")
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
    # Every config's files, so two logos can never write the same one (a
    # game id ending in a digit once made two of them share files).
    owners = {}
    for c in sorted(Path(__file__).resolve().parent.joinpath("logo_letters").glob("*.json")):
        cfg = json.loads(c.read_text())
        for piece in cfg["pieces"]:
            letter, _, variant = piece.partition(".")
            path = f"{letter}/{cfg['game']}" + (f"__{variant}" if variant else "") + ".png"
            if path in owners and owners[path] != (c.name, piece):
                print(f"error: {path} is written by both {owners[path][0]} ({owners[path][1]}) "
                      f"and {c.name} ({piece})", file=sys.stderr)
                return 1
            owners[path] = (c.name, piece)
    for c in args.configs:
        print(c)
        cut(c, args.preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
