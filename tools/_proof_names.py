"""The proof folder's file names, read and written the one way the game does.

A proof is `images2.0/proof/<name>.<ext>`, and the name says which connections
it proves: the influencers' ids, joined by ONE hyphen, then THREE hyphens and
the influenced game's id.

    slay_the_spire---tic_tactic              Slay the Spire -> Tic Tactic
    balatro-inscryption---black_jacket       Balatro -> Black Jacket and
                                             Inscryption -> Black Jacket

An id is only lower-case letters, digits and underscores, so a name splits one
way only. One file for several connections is for a clip in which a developer
names several influences: the same video under five names was five copies.
GameChoiceModal.proof_pairs reads names the same way.
"""

import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROOF = os.path.join(ROOT, "images2.0", "proof")
GAMES = os.path.join(ROOT, "data", "games")

STEM = re.compile(r"^([a-z0-9_]+(?:-[a-z0-9_]+)*)---([a-z0-9_]+)$")

# The longest name (without its extension) a proof may have. A file name is 255
# characters on every system, but Godot's import cache names a clip's poster
# `<name>.poster.jpg-<32 hex>.ctex`, 49 more; and on Windows, without long paths
# turned on, a whole path stops at 260, of which the clone's own folder and
# `.godot/imported/` take a share. 150 leaves room for all of it. The longest
# name the connections sheet asks for today is 111 (seven influences into Crab
# Champions).
MAX_STEM = 150


def pairs(stem):
    """[(from, to), ...] for a proof's name, or [] for a name that isn't one."""
    m = STEM.match(stem)
    if not m:
        return []
    return [(a, m.group(2)) for a in m.group(1).split("-")]


def name(influencers, influenced):
    """The name of one proof for these connections: influencers sorted, each once."""
    return "-".join(sorted(set(influencers))) + "---" + influenced


def proofs(exts):
    """{(from, to): file name} for every file in the folder ending in one of exts."""
    out = {}
    for f in sorted(os.listdir(PROOF)):
        for ext in exts:
            if f.endswith(ext):
                for pair in pairs(f[:-len(ext)]):
                    out[pair] = f
    return out


def connections():
    """{game id: set of the ids it influenced}, from data/games/."""
    out = {}
    for path in glob.glob(os.path.join(GAMES, "*.tres")):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        m = re.search(r"^games_influenced = Array\[StringName\]\(\[(.*)\]\)$", text, re.M)
        out[os.path.basename(path)[:-5]] = set(re.findall(r'&"([^"]+)"', m.group(1))) if m else set()
    return out


def problems(stem, graph):
    """Why this name can't be a proof, as a list of reasons ([] when it can)."""
    found = pairs(stem)
    if not found:
        return ["not <influencer id>[-<influencer id>...]---<influenced id>"]
    why = []
    if len(stem) > MAX_STEM:
        why.append("%d characters, over the %d a proof's name can be" % (len(stem), MAX_STEM))
    for a, b in found:
        if a not in graph:
            why.append("%s is not a game in data/games/" % a)
        elif b not in graph:
            why.append("%s is not a game in data/games/" % b)
        elif b not in graph[a]:
            why.append("%s -> %s is not a connection on the sheet" % (a, b))
    return sorted(set(why))
