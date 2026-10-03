#!/usr/bin/env python3
"""Find influences missing from the `connections` sheet, with first-hand sources.

WHY THIS EXISTS. The chart is only as good as its edges, and an edge is only as
good as its source. The `connections` sheet's own Source column shows the
problem: hundreds of rows say `check folder`, `look at it` or nothing at all.
The rule for new rows is stricter — a DIRECT, FIRST-HAND source: the developer
saying it, in an interview, a devlog, a store page they wrote, or a post with
their name on it. A reviewer saying "it's like Isaac" is not one.

This script is the mechanical half of that research. It never writes the
workbook. It produces candidates; a person reads each quote and approves it,
and only approved rows go into the sheet (see `docs/influence-research.md` for
the whole method, what each source is worth, and the traps).

SUBCOMMANDS (all write into --work, default `.influence_work/`, gitignored):

    python3 tools/influence_research.py targets   # games with no influences / no connections
    python3 tools/influence_research.py devs      # Steam appid + developer for every game (~6 min)
    python3 tools/influence_research.py samedev   # same-developer pairs the sheet doesn't connect
    python3 tools/influence_research.py steam     # store pages + dev announcements -> triage.md
    python3 tools/influence_research.py forums    # Steam forum search, rate-limited, resumable

`devs` must run before `samedev`, `steam` and `forums`. `forums --games targets`
scans only the no-influence games (about an hour); `--games all` is ~5 hours.
"""

import argparse
import concurrent.futures as cf
import html
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

import openpyxl  # read-only here. NEVER save the workbook with it: it drops the charts.

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")
LEGACY = os.path.join(ROOT, "legacy-web", "data", "games-data.js")
UA = {"User-Agent": "Mozilla/5.0"}

# Chart game names that are also ordinary words (or a status/class name inside
# other games). They are matched case-sensitively and still produce noise:
# "Haste now affects…" in patch notes, "the Rogue class", "Roll the dice".
AMBIGUOUS = {
    "Rogue", "Hack", "Roll", "Crawl", "Omega", "Haste", "Rounds", "Ringer",
    "Morsels", "Gnomes", "Underdogs", "Drapline", "Wireworks", "Overworld",
    "Powder", "Talented", "Eldritch", "Cataclysm", "Sil", "Convoy", "Ragnarok",
    "From The Top", "Neophyte", "Heading Out", "Diablo", "Moria", "Larn",
}

# A sentence must say something like this to count as an influence claim.
CLAIM = re.compile(
    r"inspir|influenc|homage|love letter|tribute|spiritual successor|big fans? of|"
    r"heavily based|took (?:a lot )?from|borrow|in the vein|cues from|blend of|"
    r"mix of|\bmeets\b|cross between|"
    # Developers outside the English-speaking world often post in their own
    # language even on an English store page. Japanese, Chinese, Korean,
    # German, French, Spanish/Portuguese, Polish and Russian. The game they
    # name is often still written in Latin script, so the name match below works.
    r"影響|インスパイア|参考に|オマージュ|影响|灵感|启发|啟發|靈感|致敬|"
    r"영감|영향|오마주|inspiriert|beeinflusst|inspiré|influencé|hommage|"
    r"inspirad|influenciad|homenaje|homenagem|inspiracj|inspirowan|"
    r"вдохнов|влияни|отсылк", re.I)

# Sentences that name other games for reasons that are not influence. Crossovers
# ("X x Y"), bundles and sales are the bulk of what a Steam announcement scan
# finds, and none of them say anything about where a game came from.
NOISE = re.compile(
    r"bundle|% off|\bsale\b|discount|festival|wishlist|check out|award|nominat|"
    r"curator|streamer|showcase|publisher|our friends|fellow|alongside|Next Fest|"
    r"crossover|collab", re.I)


# ── workbook ────────────────────────────────────────────────────────────────

def load_sheet():
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    games = [r for r in list(wb["games"].iter_rows(values_only=True))[1:] if r[0]]
    conns = [r for r in list(wb["connections"].iter_rows(values_only=True))[1:] if r[0]]
    return games, conns


def connected(conns):
    return {(r[0], r[1]) for r in conns}


# ── helpers ─────────────────────────────────────────────────────────────────

def get(url, timeout=40):
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf8", "replace")


def clean(text):
    text = re.sub(r"\[/?[^\]]+\]|<[^>]+>", " ", text)  # BBCode and HTML
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def name_patterns(names):
    return [(g, re.compile(r"(?<![\w])" + re.escape(g) + r"(?![\w])",
                           0 if g in AMBIGUOUS else re.I))
            for g in names if len(g) > 2]


def named_in(sentence, pats, own):
    # `g in own` drops "Hades" from a Hades II sentence and the like.
    return [g for g, p in pats if g != own and g not in own and p.search(sentence)]


def wpath(args, name):
    os.makedirs(args.work, exist_ok=True)
    return os.path.join(args.work, name)


def load_devs(args):
    path = wpath(args, "devs.json")
    if not os.path.exists(path):
        sys.exit("run `devs` first")
    return json.load(open(path))


# ── targets ─────────────────────────────────────────────────────────────────

def cmd_targets(args):
    """Games with nothing pointing at them, oldest-added first.

    Git history was squashed, so "added a while ago" is approximated by the old
    web build's game list: a game in it was on the chart before the Godot port.
    """
    games, conns = load_sheet()
    incoming, outgoing = {}, {}
    for r in conns:
        outgoing[r[0]] = outgoing.get(r[0], 0) + 1
        incoming[r[1]] = incoming.get(r[1], 0) + 1
    legacy = set()
    if os.path.exists(LEGACY):
        legacy = set(re.findall(r'"name":\s*"((?:[^"\\]|\\.)*)"', open(LEGACY).read()))
    out = []
    for r in games:
        if incoming.get(r[0]):
            continue
        out.append({"name": r[0], "year": r[1], "steam": r[9],
                    "isolated": not outgoing.get(r[0]), "legacy": r[0] in legacy})
    json.dump(out, open(wpath(args, "targets.json"), "w"), indent=1)
    print(f"{len(out)} games with no influences; "
          f"{sum(x['isolated'] for x in out)} with no connections at all; "
          f"{sum(x['legacy'] for x in out)} were in the legacy build")


# ── devs ────────────────────────────────────────────────────────────────────

def cmd_devs(args):
    """Steam appid and developer for every game. Cached; reruns only fill gaps."""
    games, _ = load_sheet()
    path = wpath(args, "devs.json")
    cache = json.load(open(path)) if os.path.exists(path) else {}
    norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())

    def one(r):
        name, url = r[0], r[9]
        if name in cache and "err" not in cache[name]:
            return name, cache[name]
        try:
            m = re.search(r"/app/(\d+)", url or "")
            if m:
                aid = m.group(1)
            else:  # no Steam Page in the sheet: exact-name store search, or nothing
                s = json.loads(get("https://store.steampowered.com/api/storesearch/?cc=us&l=en&term="
                                   + urllib.parse.quote(name)))
                hit = [i for i in s.get("items", []) if norm(i["name"]) == norm(name)]
                if not hit:
                    return name, {"aid": None}
                aid = str(hit[0]["id"])
            d = json.loads(get("https://store.steampowered.com/api/appdetails?l=english"
                               "&filters=basic,developers,publishers&appids=" + aid))[aid]
            if not d.get("success"):
                return name, {"aid": aid, "fail": 1}
            d = d["data"]
            return name, {"aid": aid, "steamname": d.get("name"),
                          "devs": d.get("developers", []), "pubs": d.get("publishers", [])}
        except Exception as e:
            return name, {"err": str(e)}

    with cf.ThreadPoolExecutor(4) as ex:
        for name, v in ex.map(one, games):
            cache[name] = v
    json.dump(cache, open(path, "w"), indent=0)
    print(f"{len(cache)} games, {sum(1 for v in cache.values() if v.get('devs'))} with a developer")


# ── samedev ─────────────────────────────────────────────────────────────────

def cmd_samedev(args):
    """Same-studio pairs that aren't connected — candidates for Dev/Series Relation.

    Same developer is NOT itself a source. Use a pair only when the newer game's
    own page says so ("From the Creators of…"). Non-Latin developer names
    normalise to nothing and match each other, so read every pair.
    """
    games, conns = load_sheet()
    devs = load_devs(args)
    year = {r[0]: r[1] for r in games}
    have = connected(conns)
    norm = lambda s: re.sub(r"\b(inc|llc|ltd|games|studios?|co|gmbh|entertainment|interactive)\b",
                            "", re.sub(r"[^a-z0-9 ]", "", s.lower())).strip()
    by = {}
    for n, v in devs.items():
        for dv in v.get("devs") or []:
            if norm(dv):
                by.setdefault(norm(dv), set()).add(n)
    seen = set()
    for group in by.values():
        for a in group:
            for b in group:
                if a == b or (year.get(a) or 0) > (year.get(b) or 0):
                    continue
                if (a, b) in have or (b, a) in have or (b, a) in seen:
                    continue
                seen.add((a, b))
                print(f"{a} ({year.get(a)}) -> {b} ({year.get(b)})  dev={devs[a].get('devs')}")


# ── steam ───────────────────────────────────────────────────────────────────

def cmd_steam(args):
    """Every chart game's store page and developer announcements, scanned for
    sentences that make an influence claim AND name another chart game.

    Store text and `steam_community_announcements` are written by the developer,
    so a hit is first-hand — but only once a person has read the sentence: most
    hits are crossovers, sales, or a game's name used as an ordinary word.
    """
    games, conns = load_sheet()
    devs = load_devs(args)
    have = connected(conns)
    pats = name_patterns([r[0] for r in games])
    cache = wpath(args, "pages")
    os.makedirs(cache, exist_ok=True)

    def one(item):
        name, v = item
        aid = v.get("aid")
        if not aid:
            return []
        fn = os.path.join(cache, f"{aid}.json")
        if os.path.exists(fn):
            docs = json.load(open(fn))
        else:
            docs = []
            try:
                s = json.loads(get(f"https://store.steampowered.com/api/appdetails?l=english&appids={aid}"))[aid]
                if s.get("success"):
                    docs.append(("store", f"https://store.steampowered.com/app/{aid}/",
                                 clean(s["data"].get("about_the_game", "") + " . "
                                       + s["data"].get("short_description", ""))))
            except Exception:
                pass
            try:
                j = json.loads(get("https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/"
                                   f"?appid={aid}&count=400&maxlength=0"))
                for it in j.get("appnews", {}).get("newsitems", []):
                    # Only the developer's own posts; the feed also carries press articles.
                    if it.get("feedname") == "steam_community_announcements":
                        docs.append(("news", f"https://store.steampowered.com/news/app/{aid}/view/{it['gid']}",
                                     clean(it["title"] + " . " + it["contents"])))
            except Exception:
                pass
            json.dump(docs, open(fn, "w"))
        out = []
        for kind, url, text in docs:
            for s in re.split(r"(?<=[.!?])\s+", text):
                if len(s) > 600 or not CLAIM.search(s) or NOISE.search(s):
                    continue
                for g in named_in(s, pats, name):
                    if (g, name) not in have and (name, g) not in have:
                        out.append((name, g, kind, url, s[:500]))
        return out

    hits = []
    with cf.ThreadPoolExecutor(8) as ex:
        for o in ex.map(one, devs.items()):
            hits += o
    first = {}
    for h in hits:
        first.setdefault((h[0], h[1]), h)
    path = wpath(args, "steam_triage.md")
    with open(path, "w") as f:
        f.write("# Steam text candidates — the sentence names another chart game; "
                "direction is NOT decided, read each one\n\n")
        for (src, other), h in sorted(first.items()):
            f.write(f"## {src} mentions {other} [{h[2]}]\n   {h[4]}\n   {h[3]}\n")
    print(f"{len(first)} unconnected pairs -> {path}")


# ── forums ──────────────────────────────────────────────────────────────────

def cmd_forums(args):
    """Steam discussion search per game, for posts that name a chart game.

    RATE LIMIT. steamcommunity.com answers "You've made too many requests
    recently" to the search page long before the store API complains. 8 s between
    requests held for about 40 games and then degraded; 15 s is the setting to
    use. On a limit the script backs off a minute per attempt. It appends one line
    per game to forums.jsonl and skips games already there, so it can be stopped
    and resumed at any point — and has to be, across container restarts.

    Almost every hit is a PLAYER ("take inspiration from Peglin", "it's probably
    inspired by Inscryption"). Only a post from the developer counts: open the
    thread and look for the developer badge, or first-person wording ("our game").
    """
    games, _ = load_sheet()
    devs = load_devs(args)
    pats = name_patterns([r[0] for r in games])
    if args.games == "targets":
        tpath = wpath(args, "targets.json")
        if not os.path.exists(tpath):
            sys.exit("run `targets` first")
        order = [x["name"] for x in json.load(open(tpath))]
    else:
        order = [r[0] for r in games]
    out = wpath(args, "forums.jsonl")
    done = set()
    if os.path.exists(out):
        for line in open(out):
            rec = json.loads(line)
            if not rec.get("err"):
                done.add(rec["game"])
    last = [0.0]

    def fetch(url):
        for attempt in range(6):
            wait = args.delay - (time.time() - last[0])
            if wait > 0:
                time.sleep(wait)
            last[0] = time.time()
            try:
                t = get(url)
            except Exception:
                t = ""
            if t and "too many requests" not in t:
                return t
            time.sleep(60 * (attempt + 1))
        return ""

    def parse(page):
        res = []
        for block in page.split('class="post_searchresult"')[1:]:
            title = re.search(r"forum_topic_name[^>]*>(.*?)</div>", block, re.S)
            author = re.findall(r'class="whiteLink"[^>]*>([^<]+)', block)
            for m in re.finditer(r'href="([^"]+discussions/[^"]+)"\s*>\s*<div class="forum_searchresult_reply_borderfix">'
                                 r'</div>\s*<div class="forum_searchresult_reply_inner">(.*?)</div>', block, re.S):
                res.append({"url": m.group(1), "snippet": clean(m.group(2))[:600],
                            "author": author[0] if author else "",
                            "title": clean(title.group(1)) if title else ""})
        return res

    with open(out, "a") as f:
        for name in order:
            if name in done:
                continue
            aid = devs.get(name, {}).get("aid")
            rec = {"game": name, "aid": aid, "hits": []}
            if aid:
                # Steam's forum search stems: "inspired" also finds inspiration/inspiring.
                for q, pages in (("inspired", 2), ("influenced", 1)):
                    for p in range(1, pages + 1):
                        page = fetch(f"https://steamcommunity.com/app/{aid}/discussions/search/?q={q}&p={p}")
                        if not page:
                            rec["err"] = 1
                            break
                        for hit in parse(page):
                            hit["named"] = named_in(hit["snippet"], pats, name)
                            if hit["named"]:
                                rec["hits"].append(hit)
                        if f"&p={p + 1}" not in page:
                            break
            f.write(json.dumps(rec) + "\n")
            f.flush()
            print(name, len(rec["hits"]), flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work", default=os.path.join(ROOT, ".influence_work"))
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("targets")
    sub.add_parser("devs")
    sub.add_parser("samedev")
    sub.add_parser("steam")
    fp = sub.add_parser("forums")
    fp.add_argument("--games", choices=["targets", "all"], default="targets")
    fp.add_argument("--delay", type=float, default=15.0)
    args = ap.parse_args()
    {"targets": cmd_targets, "devs": cmd_devs, "samedev": cmd_samedev,
     "steam": cmd_steam, "forums": cmd_forums}[args.cmd](args)


if __name__ == "__main__":
    main()
