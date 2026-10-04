#!/usr/bin/env python3
"""Rename the owner's proof screenshots into the game's "From → To.png" format.

The game reads one file per connection, named for the two games in the
direction of the influence: "Slay the Spire → Tic Tactic.png". The owner
uploads screenshots to images2.0/proof/ under whatever name reads well:
"tic tactic sts.png", "going under hades, isaac, gungeon, spelunky.png",
"dungeons and degenerate gamblers, ballionaire, and crop rotation to luck be a
landlord.png". This works out which connection(s) each upload proves and, with
--write, renames it into place: one copy per connection when it proves several,
then the upload itself is removed. Every file it writes is added to
tools/proof_owner.json, which is what stops a captured page ever replacing it.

How it reads a name:

  1. the INFLUENCED game is the longest game name the file name starts with
     (spaces and punctuation ignored, so "heiscoming" is He is Coming);
  2. the INFLUENCERS are that game's incoming connections whose name, initials
     (sts, lbal, ror2) or a known short form (isaac, gungeon, NT) appears in
     the REST of the file name. Only the rest: "dungeon" in "dungeon drafters"
     is the game's own name, not Mystery Dungeon.

It only proposes pairs that are edges on the sheet, so a screenshot proving a
connection the sheet doesn't have is reported, never renamed.

    python3 tools/proof_owner_match.py           # print the proposals
    python3 tools/proof_owner_match.py --write   # and rename them into place
    python3 tools/proof_owner_match.py --pair "file.png" "Slay the Spire" "Tic Tactic"
                                                 # one the guess can't place, by hand
                                                 # (repeat the flag for more pairs)

Read the proposals before --write. A typo ("abolisk", "backback"), a file that
runs the other way (one influencer, several games), or a word shared by two
games ("survivors") won't match or may match wrong: use --pair for those.
A connection that already has one of YOUR screenshots is never overwritten;
the upload is left in place and reported.
"""
import glob
import json
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROOF = os.path.join(ROOT, "images2.0", "proof")
OWNER = os.path.join(ROOT, "tools", "proof_owner.json")
ARROW = " → "


def proof_name(name):
    """The same rule as GameChoiceModal.proof_file_name and capture_proof.js."""
    name = name.replace(":", " -")
    name = re.sub(r'[<>"/\\|?*]', "", name)
    return re.sub(r"\s+", " ", name).strip().rstrip(".")

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


def rename(name, pairs, games, owned):
    """Copy one upload to each connection's file; drop the upload if all landed."""
    src = os.path.join(PROOF, name)
    data = open(src, "rb").read()
    clashes = []
    for a, b in pairs:
        dest = proof_name(games[a]["name"]) + ARROW + proof_name(games[b]["name"]) + ".png"
        if dest in owned and os.path.exists(os.path.join(PROOF, dest)) \
                and open(os.path.join(PROOF, dest), "rb").read() != data:
            clashes.append(dest)
            continue
        open(os.path.join(PROOF, dest), "wb").write(data)
        owned.add(dest)
        print(f"  -> {dest}")
    if clashes:
        print(f"  KEPT {name}: you already have a screenshot for " + ", ".join(clashes))
    else:
        os.remove(src)
        if os.path.exists(src + ".import"):
            os.remove(src + ".import")


def main():
    games = load_games()
    incoming = {}
    for gid, g in games.items():
        for o in g["out"]:
            incoming.setdefault(o, []).append(gid)
    owner = json.load(open(OWNER, encoding="utf8"))
    owned = set(owner["files"])
    write = "--write" in sys.argv

    # --pair FILE FROM TO, by display name, for what the guess can't place.
    by_name = {proof_name(g["name"]).lower(): gid for gid, g in games.items()}
    hand = {}
    args = sys.argv[1:]
    for i, arg in enumerate(args):
        if arg == "--pair":
            file, a, b = args[i + 1:i + 4]
            ida, idb = by_name.get(proof_name(a).lower()), by_name.get(proof_name(b).lower())
            if ida is None or idb is None:
                sys.exit(f"--pair: no game called {a if ida is None else b!r}")
            if idb not in games[ida]["out"]:
                sys.exit(f"--pair: {a} -> {b} is not a connection on the sheet")
            hand.setdefault(file, []).append([ida, idb])
    for file, pairs in hand.items():
        print(file)
        rename(file, pairs, games, owned)
    if hand:
        write = True

    new, stuck = {}, []
    for f in sorted(glob.glob(os.path.join(PROOF, "*.png")), key=str.lower):
        name = os.path.basename(f)
        # "From → To.png" is already in place.
        if ARROW in name or name in hand:
            continue
        to, pairs = propose(name[:-4], games, incoming)
        if pairs:
            new[name] = pairs
            print(f"{name}\n    " + "\n    ".join(f"{games[a]['name']} -> {games[b]['name']}" for a, b in pairs))
            if "--write" in sys.argv:
                rename(name, pairs, games, owned)
        else:
            why = "no game name at the start" if to is None else \
                f"{games[to]['name']}: none of its influencers named ({', '.join(games[x]['name'] for x in incoming.get(to, [])) or 'it has none'})"
            stuck.append(f"{name}  [{why}]")
    if stuck:
        print("\nNOT PLACED (a typo, the other direction, or not on the sheet) - use --pair:\n  " + "\n  ".join(stuck))
    print(f"\n{len(new)} matched, {len(stuck)} not placed" + ("" if write else " (nothing renamed: add --write)"))
    if write:
        owner["files"] = sorted(owned, key=str.lower)
        json.dump(owner, open(OWNER, "w", encoding="utf8"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
