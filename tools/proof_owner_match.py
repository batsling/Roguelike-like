#!/usr/bin/env python3
"""Rename the owner's free-named proof uploads into the game's format.

The game reads a proof by the games' ids, influencer first, joined by three
hyphens: "slay_the_spire---tic_tactic.png" (an id is a game's file name in
data/games/ without the .tres). One file that proves several connections into
the same game is named for all of them, the influencers joined by one hyphen:
"hades-the_binding_of_isaac---going_under.png" (tools/_proof_names.py). A file
dropped into images2.0/proof/ under such a name needs nothing else. One dropped
in under any other name ("tic tactic sts.png", "going under hades, isaac,
gungeon, spelunky.png") is what this is for: it works out which connection(s)
the name means and, with --write, renames it into place — ONE file for all of
them, never a copy each. Screenshots (.png) and clips (.mp4 and the other
uploads tools/convert_proof_videos.py takes) alike; a clip still needs that
script run after, to become the .ogv the game plays.

How it reads a name:

  1. the INFLUENCED game is the longest game name the file name starts with
     (spaces and punctuation ignored, so "heiscoming" is He is Coming);
  2. the INFLUENCERS are that game's incoming connections whose name, initials
     (sts, lbal, ror2) or a known short form (isaac, gungeon, NT) appears in
     the REST of the file name. Only the rest: "dungeon" in "dungeon drafters"
     is the game's own name, not Mystery Dungeon.

It only proposes pairs that are connections on the sheet. It also reports any
file already in the id format whose ids aren't a connection (a typo).

    python3 tools/proof_owner_match.py           # print the proposals
    python3 tools/proof_owner_match.py --write   # and rename them into place
    python3 tools/proof_owner_match.py --pair "file.png" slay_the_spire tic_tactic
                                                 # one the guess can't place, by hand
                                                 # (ids or names; repeat for more pairs)

A connection that already has one of YOUR screenshots is never overwritten; the
upload is left in place and reported. A captured one (tools/proof_captured.json)
is replaced, and is yours from then on. A clip replaces the clip it overlaps
when it is converted (tools/convert_proof_videos.py says how).
"""
import glob
import json
import os
import re
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _proof_names as names  # noqa: E402

ROOT = names.ROOT
PROOF = names.PROOF
CAPTURED = os.path.join(ROOT, "tools", "proof_captured.json")
SHOT = ".png"
CLIPS = (".mp4", ".mov", ".m4v", ".webm", ".mkv")

# Short forms the owner uses that initials alone don't give.
SHORT = {
    "enter_the_gungeon": {"gungeon", "etg"},
    "the_binding_of_isaac": {"isaac", "boi", "tboi"},
    "dungeon_crawl_stone_soup": {"dcss"},
    "teamfight_tactics": {"tft"},
    "nuclear_throne": {"nt"},
    "backpack_battles": {"bpb", "backpackbattles"},
    "risk_of_rain_2": {"ror2"},
    "realm_of_the_mad_god": {"rotmg"},
    "20_minutes_till_dawn": {"20mtd"},
    "deep_rock_galactic_survivor": {"drgs"},
    "caves_of_qud": {"qud"},
    "nubby_s_number_factory": {"nubby"},
}


def words(s):
    # "Kādomon" is typed "kadomon": accents fold to their plain letter.
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = s.lower().replace("&", " and ").replace("-", " ")
    return re.sub(r"[^a-z0-9 ]", "", s).split()


def load_games():
    games = {}
    for f in glob.glob(os.path.join(ROOT, "data", "games", "*.tres")):
        t = open(f, encoding="utf8").read()
        gid = re.search(r'^id = &"([^"]+)"', t, re.M).group(1)
        name = re.search(r'^display_name = "(.*)"$', t, re.M).group(1)
        out = re.search(r"^games_influenced = Array\[StringName\]\(\[(.*)\]\)$", t, re.M)
        games[gid] = {"name": name, "out": re.findall(r'&"([^"]+)"', out.group(1)) if out else []}
    return games


def keys(gid, name):
    w = words(name)
    found = {" ".join(w), "".join(x[0] for x in w), "".join(x if x.isdigit() else x[0] for x in w)}
    if w[:1] == ["the"]:
        found |= {" ".join(w[1:]), "".join(x[0] for x in w[1:])}
    if len(w) > 1 and len(w[-1]) > 4:
        found.add(w[-1])
    if len(w) > 1 and len(w[0]) > 4:
        found.add(w[0])
    return {k for k in found | SHORT.get(gid, set()) if len(k) >= 2}


def propose(stem, games, incoming):
    spaced = " ".join(words(stem))
    glued = spaced.replace(" ", "")
    best = None
    for gid, g in games.items():
        w = words(g["name"])
        # "Kādomon: Hyper Auto Battlers" is written "kadomon": the part before a
        # colon is the name people use.
        head = words(g["name"].split(":")[0]) if ":" in g["name"] else []
        names = {"".join(w), "".join(w[1:]) if w[:1] == ["the"] else "", "".join(head) if len("".join(head)) > 3 else ""}
        for k in names - {""}:
            if glued.startswith(k) and (best is None or len(k) > best[1]):
                best = (gid, len(k))
    if best is None:
        return None, []
    # Cut the influenced name off the spaced form, letter by letter.
    seen, cut = 0, len(spaced)
    for i, ch in enumerate(spaced):
        if seen == best[1]:
            cut = i
            break
        if ch != " ":
            seen += 1
    rest = " " + spaced[cut:].strip() + " "
    rest_glued = rest.replace(" ", "")
    to = best[0]
    pairs = []
    for frm in incoming.get(to, []):
        ks = keys(frm, games[frm]["name"])
        if any(f" {k} " in rest or (len(k.replace(" ", "")) > 3 and k.replace(" ", "") in rest_glued) for k in ks):
            pairs.append([frm, to])
    return to, pairs


def sha1(data):
    import hashlib
    return hashlib.sha1(data).hexdigest()


def ext_of(name):
    low = name.lower()
    return next((e for e in (SHOT,) + CLIPS if low.endswith(e)), None)


def rename(name, pairs, ledger):
    """Move one upload to the file named for all its connections (one per
    influenced game, when a --pair list spans several); drop the upload if all
    landed."""
    src = os.path.join(PROOF, name)
    data = open(src, "rb").read()
    ext = ext_of(name)
    by_game = {}
    for a, b in pairs:
        by_game.setdefault(b, []).append(a)
    shots = names.proofs((SHOT,)) if ext == SHOT else {}
    clashes, landed = [], []
    for b, influencers in by_game.items():
        dest = names.name(influencers, b) + ext
        # A screenshot already proving one of these: a captured one makes way, one
        # of yours stays, and so does this upload. (A clip settles its overlaps
        # when it is converted.)
        old = {shots[(a, b)] for a in influencers if (a, b) in shots} - {dest}
        if os.path.exists(os.path.join(PROOF, dest)):
            old.add(dest)
        mine = [f for f in sorted(old) if ledger.get(f) != sha1(open(os.path.join(PROOF, f), "rb").read())
                and open(os.path.join(PROOF, f), "rb").read() != data]
        if mine:
            clashes += mine
            continue
        for f in old - {dest}:
            os.remove(os.path.join(PROOF, f))
            ledger.pop(f, None)
            print(f"  replaced {f}")
        open(os.path.join(PROOF, dest), "wb").write(data)
        ledger.pop(dest, None)          # the owner's now
        landed.append(dest)
        print(f"  -> {dest}")
    if clashes:
        print(f"  KEPT {name}: you already have a proof there: " + ", ".join(clashes))
    elif name not in landed:
        os.remove(src)
        if os.path.exists(src + ".import"):
            os.remove(src + ".import")


def main():
    games = load_games()
    incoming = {}
    for gid, g in games.items():
        for o in g["out"]:
            incoming.setdefault(o, []).append(gid)
    captured = json.load(open(CAPTURED, encoding="utf8"))
    ledger = captured["files"]
    write = "--write" in sys.argv

    # --pair FILE FROM TO, by id or display name, for what the guess can't place.
    def game_id(x):
        if x in games:
            return x
        key = " ".join(words(x))
        return next((gid for gid, g in games.items() if " ".join(words(g["name"])) == key), None)
    hand = {}
    args = sys.argv[1:]
    for i, arg in enumerate(args):
        if arg == "--pair":
            file, a, b = args[i + 1:i + 4]
            ida, idb = game_id(a), game_id(b)
            if ida is None or idb is None:
                sys.exit(f"--pair: no game called {a if ida is None else b!r}")
            if idb not in games[ida]["out"]:
                sys.exit(f"--pair: {games[ida]['name']} -> {games[idb]['name']} is not a connection on the sheet")
            hand.setdefault(file, []).append([ida, idb])
    for file, pairs in hand.items():
        print(file)
        rename(file, pairs, ledger)
    if hand:
        write = True

    graph = {gid: set(g["out"]) for gid, g in games.items()}
    new, stuck, typos = {}, [], []
    for f in sorted(glob.glob(os.path.join(PROOF, "*")), key=str.lower):
        name = os.path.basename(f)
        ext = ext_of(name)
        if ext is None:
            continue
        stem = name[:-len(ext)]
        if names.pairs(stem):
            # Already in the format: only check it names real connections.
            why = names.problems(stem, graph)
            if why:
                typos.append(f"{name}  [{'; '.join(why)}]")
            continue
        if name in hand:
            continue
        to, pairs = propose(stem, games, incoming)
        if pairs:
            new[name] = pairs
            print(f"{name}\n    " + "\n    ".join(f"{games[a]['name']} -> {games[b]['name']}" for a, b in pairs))
            if "--write" in sys.argv:
                rename(name, pairs, ledger)
        else:
            why = "no game name at the start" if to is None else \
                f"{games[to]['name']}: none of its influencers named ({', '.join(games[x]['name'] for x in incoming.get(to, [])) or 'it has none'})"
            stuck.append(f"{name}  [{why}]")
    if stuck:
        print("\nNOT PLACED (a typo, the other direction, or not on the sheet) - use --pair:\n  " + "\n  ".join(stuck))
    if typos:
        print("\nNAMED LIKE A PROOF BUT NOT A CONNECTION ON THE SHEET (check the ids and the order, influencer first):\n  " + "\n  ".join(typos))
    print(f"\n{len(new)} matched, {len(stuck)} not placed" + ("" if write else " (nothing renamed: add --write)"))
    if write:
        json.dump(captured, open(CAPTURED, "w", encoding="utf8"), indent=1)
        open(CAPTURED, "a").write("\n")


if __name__ == "__main__":
    main()
