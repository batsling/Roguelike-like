#!/usr/bin/env python3
"""Propose which connection(s) each of the owner's proof screenshots proves.

The owner drops screenshots into images2.0/proof/ named however reads well to
them: "tic tactic sts.png", "going under hades, isaac, gungeon, spelunky.png",
"dungeons and degenerate gamblers, ballionaire, and crop rotation to luck be a
landlord.png". The game looks a proof up by the connection's two ids, so each
file needs a line in tools/proof_owner_map.json saying which pairs it proves.

This reads every PNG not in the map yet and proposes its pairs:

  1. the INFLUENCED game is the longest game name the file name starts with
     (spaces and punctuation ignored, so "heiscoming" is He is Coming);
  2. the INFLUENCERS are that game's incoming connections whose name, initials
     (sts, lbal, ror2) or a known short form (isaac, gungeon, NT) appears in
     the REST of the file name. Only the rest: "dungeon" in "dungeon drafters"
     is the game's own name, not Mystery Dungeon.

It only proposes pairs that are edges on the sheet, so a screenshot proving a
connection the sheet doesn't have is reported, never mapped.

    python3 tools/proof_owner_match.py           # print the proposals
    python3 tools/proof_owner_match.py --write   # and add them to the map

Read the proposals before --write. A typo ("abolisk", "backback") or a file
that runs the other way (one influencer, several games) won't match, and
is listed for a hand-written line.
"""
import glob
import json
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROOF = os.path.join(ROOT, "images2.0", "proof")
MAP = os.path.join(ROOT, "tools", "proof_owner_map.json")

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


def main():
    games = load_games()
    incoming = {}
    for gid, g in games.items():
        for o in g["out"]:
            incoming.setdefault(o, []).append(gid)
    mapping = json.load(open(MAP, encoding="utf8"))
    new, stuck = {}, []
    for f in sorted(glob.glob(os.path.join(PROOF, "*.png")), key=str.lower):
        name = os.path.basename(f)
        # "<From> → <To>.png" are the game's copies (capture_proof.js --export),
        # not the owner's screenshots.
        if name in mapping or " → " in name or "__" in name:
            continue
        to, pairs = propose(name[:-4], games, incoming)
        if pairs:
            new[name] = pairs
            print(f"{name}\n    " + "\n    ".join(f"{games[a]['name']} -> {games[b]['name']}" for a, b in pairs))
        else:
            why = "no game name at the start" if to is None else \
                f"{games[to]['name']}: none of its influencers named ({', '.join(games[x]['name'] for x in incoming.get(to, [])) or 'it has none'})"
            stuck.append(f"{name}  [{why}]")
    if stuck:
        print("\nNEEDS A HAND-WRITTEN LINE (typo, other direction, or not on the sheet):\n  " + "\n  ".join(stuck))
    print(f"\n{len(new)} proposed, {len(stuck)} not matched")
    if "--write" in sys.argv and new:
        mapping.update(new)
        about = {k: v for k, v in mapping.items() if k.startswith("_")}
        rest = dict(sorted(((k, v) for k, v in mapping.items() if not k.startswith("_")), key=lambda kv: kv[0].lower()))
        json.dump({**about, **rest}, open(MAP, "w", encoding="utf8"), indent=1, ensure_ascii=False)
        print(f"added to {os.path.relpath(MAP, ROOT)}")


if __name__ == "__main__":
    main()
