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
    python3 tools/influence_research.py cues      # wider read of those pages for the degree-1 games
    python3 tools/influence_research.py wanted FILE  # games not on the chart yet: find edges to it
    python3 tools/influence_research.py lang      # each studio's own language (+ --forums for subforums)
    python3 tools/influence_research.py forums    # Steam forum search, in English + the studio's language
    python3 tools/influence_research.py devcheck  # keep only forum posts with Steam's developer badge
    python3 tools/influence_research.py xsources  # who posted each X/Twitter source the sheet cites
    python3 tools/influence_research.py media     # interview videos + podcasts to listen to -> docs/influence-media.md
    python3 tools/influence_research.py status    # which candidates are in the sheet now (--tick marks them)

`devs` must run before everything after it, and `steam` before `lang` (it reads
the cached announcements). The three forum steps are rate-limited and resumable;
`--games targets` (the default) is the no-influence games, `--games all` is ~5x longer.
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

def steam_pages(aid, cache):
    """A game's store text and its developer's own announcements, cached on disk.

    Store text and `steam_community_announcements` are written by the developer,
    which is what makes a hit in them first-hand. Returns [(kind, url, text)].
    """
    fn = os.path.join(cache, f"{aid}.json")
    if os.path.exists(fn):
        return json.load(open(fn))
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
                # The feed's gid is NOT the id the store's news page uses, so a
                # store.steampowered.com/news/app/<aid>/view/<gid> link is dead.
                # Its own url redirects to the real announcement; cite where it lands.
                docs.append(("news", it["url"],
                             clean(it["title"] + " . " + it["contents"])))
    except Exception:
        pass
    json.dump(docs, open(fn, "w"))
    return docs


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
        docs = steam_pages(aid, cache)
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


# ── cues ────────────────────────────────────────────────────────────────────

# Wider than CLAIM: the phrasings a store page or devlog uses for a lineage
# without the word "inspired" — "from the creators of", "sequel to", "if you
# liked", "similar to". This is what found Despotism 3k -> Slime 3K and Luck be
# a Landlord -> Maze Mice, which `steam` missed because neither says "inspired".
CUE = re.compile(
    r"creators? of|makers? of|developers? (?:of|behind)|brought you|sequel to|"
    r"studio behind|team behind|same (?:solo )?developer|predecessors?|same universe|"
    r"continues the|if you (?:like|liked|enjoy|enjoyed|love|loved)|fans? of|"
    r"similar to|akin to|approach|touchstone|reference", re.I)


def degree_one(games, conns):
    deg = {}
    for a, b, *_ in conns:
        deg[a] = deg.get(a, 0) + 1
        deg[b] = deg.get(b, 0) + 1
    return [r[0] for r in games if deg.get(r[0]) == 1]


def cmd_cues(args):
    """A wider read of the pages `steam` cached, for pairs where one game is held
    on the map by a single edge (or --games all).

    Same text, looser net: CLAIM or CUE, next to another chart game's name, and
    the pair not already connected. It finds more noise than `steam` does, so it
    is pointed at the games where an extra edge matters most. Run `steam` first.
    Output: cues.md, for a person to read.
    """
    games, conns = load_sheet()
    devs = load_devs(args)
    have = connected(conns)
    pats = name_patterns([r[0] for r in games])
    # A leaf's lineage is as often on the OTHER game's page (Slime 3K's store
    # page is where Despotism 3k gets its second edge), so every page is read and
    # a hit is kept when either end of it is a leaf.
    leaves = set(degree_one(games, conns)) if args.games == "leaves" else None
    out = []
    for name in (r[0] for r in games):
        fn = wpath(args, os.path.join("pages", f"{devs.get(name, {}).get('aid')}.json"))
        if not os.path.exists(fn):
            continue
        for kind, url, text in json.load(open(fn)):
            for s in re.split(r"(?<=[.!?])\s+", text):
                if len(s) > 700 or not (CUE.search(s) or CLAIM.search(s)) or NOISE.search(s):
                    continue
                for g in named_in(s, pats, name):
                    if leaves is not None and name not in leaves and g not in leaves:
                        continue
                    if (g, name) not in have and (name, g) not in have:
                        out.append(f"## {name} <- {g} [{kind}] {url}\n   {s.strip()[:500]}\n")
    path = wpath(args, "cues.md")
    with open(path, "w") as f:
        f.write("# Wider cue scan — read every line; most are noise\n\n" + "".join(dict.fromkeys(out)))
    print(f"{len(set(out))} hits -> {path}")


# ── wanted ──────────────────────────────────────────────────────────────────

def cmd_wanted(args):
    """Games the owner wants on the chart but has no edge for yet.

    Takes a text file, one name per line ("#" starts a comment). Each name is
    looked up in the Steam store search, its store page and announcements are
    read the way `steam` reads a chart game's, and every sentence that makes a
    claim (CLAIM or CUE) next to a chart game's name is written to wanted.md.
    A name that matches no Steam app, or matches loosely, says so: the store
    search returns the nearest title, and a wrong game is worse than none.
    """
    games, _ = load_sheet()
    pats = name_patterns([r[0] for r in games])
    cache = wpath(args, "pages")
    os.makedirs(cache, exist_ok=True)
    norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
    names = [l.split("#")[0].strip() for l in open(args.file, encoding="utf8")]
    names = list(dict.fromkeys(n for n in names if n))

    def one(name):
        try:
            s = json.loads(get("https://store.steampowered.com/api/storesearch/?cc=us&l=en&term="
                               + urllib.parse.quote(name)))
        except Exception as e:
            return name, None, f"search failed: {e}", []
        items = s.get("items", [])
        exact = [i for i in items if norm(i["name"]) == norm(name)]
        pick = (exact or items[:1] or [None])[0]
        if pick is None:
            return name, None, "not on Steam", []
        note = "" if exact else f"closest match: {pick['name']}"
        out = []
        for kind, url, text in steam_pages(str(pick["id"]), cache):
            for sent in re.split(r"(?<=[.!?])\s+", text):
                if len(sent) > 700 or not (CLAIM.search(sent) or CUE.search(sent)) or NOISE.search(sent):
                    continue
                for g in named_in(sent, pats, pick["name"]):
                    out.append((g, kind, url, sent.strip()[:500]))
        return name, pick, note, out

    path = wpath(args, "wanted.md")
    found = 0
    with cf.ThreadPoolExecutor(6) as ex, open(path, "w") as f:
        f.write("# Wanted games: sentences naming a chart game — read every one\n\n")
        for name, pick, note, out in ex.map(one, names):
            app = f"https://store.steampowered.com/app/{pick['id']}/" if pick else "-"
            f.write(f"## {name}  ({app}{'; ' + note if note else ''})\n")
            seen = set()
            for g, kind, url, sent in out:
                if (g, sent[:80]) in seen:
                    continue
                seen.add((g, sent[:80]))
                f.write(f"- **{g}** [{kind}] {url}\n  {sent}\n")
            found += bool(out)
            f.write("\n")
    print(f"{len(names)} games, {found} with a hit -> {path}")


# ── steamcommunity.com (forums) ─────────────────────────────────────────────

class Community:
    """One request at a time to steamcommunity.com, `delay` seconds apart.

    RATE LIMIT. It answers "You've made too many requests recently" long before
    the store API complains. 8 s between requests held for about 40 games and
    then degraded; 15 s is the setting to use. On a limit it backs off a minute
    per attempt, up to six.
    """

    def __init__(self, delay):
        self.delay, self.last = delay, 0.0

    def get(self, url):
        for attempt in range(6):
            wait = self.delay - (time.time() - self.last)
            if wait > 0:
                time.sleep(wait)
            self.last = time.time()
            try:
                t = get(url)
            except Exception:
                t = ""
            if t and "too many requests" not in t:
                return t
            time.sleep(60 * (attempt + 1))
        return ""


def game_order(args, games):
    if args.games == "targets":
        tpath = wpath(args, "targets.json")
        if not os.path.exists(tpath):
            sys.exit("run `targets` first")
        return [x["name"] for x in json.load(open(tpath))]
    return [r[0] for r in games]


def resumable(path):
    """Games already in a jsonl output (error rows excepted, so they get redone)."""
    done = set()
    if os.path.exists(path):
        for line in open(path):
            rec = json.loads(line)
            if not rec.get("err"):
                done.add(rec["game"])
    return done


# ── lang ────────────────────────────────────────────────────────────────────

# What to search a studio's forum for, by language. Steam's forum search stems
# English ("inspired" also finds inspiration/inspiring) but not CJK, so those
# get two or three forms. Each term is one more rate-limited request per game.
SEARCH_TERMS = {
    "en": ["inspired", "influenced"],
    "ja": ["影響", "インスパイア", "参考"],
    "zh": ["灵感", "影响", "啟發"],
    "ko": ["영감", "영향"],
    "de": ["inspiriert", "beeinflusst"],
    "fr": ["inspiré", "influencé"],
    "es": ["inspirado", "influenciado"],
    "pt": ["inspirado", "influenciado"],
    "pl": ["inspirowany", "inspiracja"],
    "ru": ["вдохнов", "влияни"],
}

# Subforum names a studio creates for its home players.
SUBFORUM = [
    ("ja", r"日本語|日本"), ("zh", r"中文|简体|繁體|繁体|华语|華語"), ("ko", r"한국어|한국"),
    ("de", r"Deutsch"), ("fr", r"Français|Francais"), ("es", r"Español|Espanol"),
    ("pt", r"Português|Portugues|Brasil"), ("pl", r"Polski"), ("ru", r"Русский|Россия"),
]

STOPWORDS = {
    "en": "the and is of to in that it for with this you are",
    "de": "der die das und ist nicht ich wir mit für auch ein eine zu",
    "fr": "le la les et est des une pour avec nous dans que pas",
    "es": "el la los las y es que para con una por del nuestro",
    "pt": "não que para com uma nosso nossa são também mais você",
    "pl": "i w nie się na jest że to z do jak już",
}


def detect_language(text, min_letters=100):
    """Best guess at a text's language, by script first and then by stopwords.

    Returns (code, share) where share is how much of the text supports it. Kana
    means Japanese even beside kanji; hanzi without kana means Chinese.
    """
    if not text:
        return None, 0.0
    letters = [c for c in text if c.isalpha()]
    # Too short to say: "中文版即将推出" (Chinese version coming soon) is a
    # Japanese studio announcing a translation, and a one-line gif link once
    # read as Portuguese.
    if len(letters) < max(min_letters, 1):
        return None, 0.0
    n = len(letters)
    kana = sum(1 for c in letters if "぀" <= c <= "ヿ")
    hangul = sum(1 for c in letters if "가" <= c <= "힯")
    han = sum(1 for c in letters if "一" <= c <= "鿿")
    cyr = sum(1 for c in letters if "Ѐ" <= c <= "ӿ")
    if kana / n > 0.05:
        return "ja", (kana + han) / n
    if hangul / n > 0.1:
        return "ko", hangul / n
    if han / n > 0.1:
        return "zh", han / n
    if cyr / n > 0.2:
        return "ru", cyr / n
    words = re.findall(r"[a-zà-ÿąćęłńóśźż]+", text.lower())
    if len(words) < 30:
        return None, 0.0
    counts = {lang: sum(1 for w in words if w in set(sw.split())) for lang, sw in STOPWORDS.items()}
    best = max(counts, key=counts.get)
    # A non-English language has to out-score English in the same text: short
    # shared words ("de", "a", "con") otherwise turn English patch notes Spanish.
    if best != "en" and counts[best] <= counts["en"]:
        best = "en"
    return best, counts[best] / len(words)


def cmd_lang(args):
    """Work out each studio's language, so it can be searched in that language.

    The signals, strongest first:
      1. the developer's OWN writing: their Steam announcements (already cached
         by `steam`) and any developer-badged forum post `devcheck` has opened.
         A studio posting patch notes in Japanese is a Japanese studio;
      2. a forum subforum named for a language (日本語, 中文讨论区, 한국어…),
         which the studio or publisher sets up for its home players;
      3. the developer's name written in a non-Latin script.
    Players' thread titles are NOT used: Chinese and Russian players post on
    nearly every popular game's forum, so their titles say who plays it, not
    who made it.

    `--forums` adds signal 2 at one rate-limited request per game.
    """
    games, _ = load_sheet()
    devs = load_devs(args)
    order = game_order(args, games)
    cache = wpath(args, "pages")
    dev_posts = {}
    dpath = wpath(args, "devcheck.jsonl")
    if os.path.exists(dpath):
        for line in open(dpath):
            r = json.loads(line)
            for h in r.get("hits", []):
                if h.get("developer"):
                    dev_posts.setdefault(r["game"], []).append(h.get("dev_text", ""))
    out = wpath(args, "lang.json")
    result = json.load(open(out)) if os.path.exists(out) else {}
    community = Community(args.delay) if args.forums else None
    for name in order:
        v = devs.get(name, {})
        aid = v.get("aid")
        ev = []
        # 1. the developer's own writing
        own = []
        fn = os.path.join(cache, f"{aid}.json") if aid else ""
        if fn and os.path.exists(fn):
            own += [t for kind, url, t in json.load(open(fn)) if kind == "news"]
        own += dev_posts.get(name, [])
        tally = {}
        for t in own:
            lang, share = detect_language(t)
            if lang and lang != "en" and share > (0.15 if lang in ("ja", "zh", "ko", "ru") else 0.08):
                tally[lang] = tally.get(lang, 0) + 1
        # Developers mostly post English on Steam, so even a few native-language
        # posts mean something. A studio that LOCALISES (patch notes in five
        # languages) shows as a sprinkle well under 5%.
        for lang, k in tally.items():
            # Measured: a Chinese studio posted 8 of 102 in Chinese, a Japanese one
            # 1 of 12 in Japanese; Red Hook's 3 Korean posts of 329 are localisation.
            if k / len(own) >= 0.05:
                ev.append((lang, 3 if k >= 2 else 2, f"{k} of the developer's {len(own)} posts are in it"))
        # 2. a subforum named for a language
        if community and aid and not result.get(name, {}).get("forum_checked"):
            page = community.get(f"https://steamcommunity.com/app/{aid}/discussions/")
            names = [clean(m) for m in re.findall(
                r'href="https://steamcommunity.com/app/\d+/discussions/\d+/"[^>]*>(.*?)</a>', page, re.S)]
            for lang, pat in SUBFORUM:
                if any(re.search(pat, n) for n in names):
                    ev.append((lang, 2, "a subforum is named for it"))
        elif result.get(name, {}).get("subforum"):
            ev.append((result[name]["subforum"], 2, "a subforum is named for it"))
        # 3. the developer's name
        for dname in v.get("devs") or []:
            lang, share = detect_language(dname, min_letters=1)
            if lang in ("ja", "zh", "ko", "ru") and share > 0.3:
                ev.append((lang, 1, f"developer name '{dname}'"))
        score = {}
        for lang, w, _ in ev:
            score[lang] = score.get(lang, 0) + w
        best = max(score, key=score.get) if score else "en"
        result[name] = {"lang": best, "evidence": [e[2] + f" ({e[0]})" for e in ev],
                        "forum_checked": bool(community) or result.get(name, {}).get("forum_checked", False),
                        "subforum": next((e[0] for e in ev if e[1] == 2), None)}
        if best != "en":
            print(f"{name}: {best} — " + "; ".join(result[name]["evidence"]), flush=True)
        json.dump(result, open(out, "w"), indent=1, ensure_ascii=False)
    print(f"{sum(1 for r in result.values() if r['lang'] != 'en')} of {len(result)} games look non-English -> {out}")


# ── forums ──────────────────────────────────────────────────────────────────

def parse_search(page):
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


def cmd_forums(args):
    """Steam discussion search per game, for posts that name a chart game.

    Searches in English AND in the studio's own language when `lang` found one
    (SEARCH_TERMS). Appends one line per game to forums.jsonl and skips games
    already there, so it can be stopped and resumed at any point — and has to
    be, across container restarts.

    Almost every hit is a PLAYER ("take inspiration from Peglin", "it's probably
    inspired by Inscryption"). Run `devcheck` next: it keeps only the posts with
    Steam's developer badge.
    """
    games, _ = load_sheet()
    devs = load_devs(args)
    pats = name_patterns([r[0] for r in games])
    order = game_order(args, games)
    lpath = wpath(args, "lang.json")
    langs = json.load(open(lpath)) if os.path.exists(lpath) else {}
    out = wpath(args, "forums.jsonl")
    done = resumable(out)
    community = Community(args.delay)
    with open(out, "a") as f:
        for name in order:
            if name in done:
                continue
            aid = devs.get(name, {}).get("aid")
            lang = langs.get(name, {}).get("lang", "en")
            rec = {"game": name, "aid": aid, "lang": lang, "hits": []}
            terms = [(q, 2 if q == "inspired" else 1) for q in SEARCH_TERMS["en"]]
            if lang != "en":
                terms += [(q, 1) for q in SEARCH_TERMS.get(lang, [])]
            if aid:
                for q, pages in terms:
                    for p in range(1, pages + 1):
                        page = community.get(f"https://steamcommunity.com/app/{aid}/discussions/search/"
                                             f"?q={urllib.parse.quote(q)}&p={p}")
                        if not page:
                            rec["err"] = 1
                            break
                        for hit in parse_search(page):
                            hit["named"] = named_in(hit["snippet"], pats, name)
                            hit["query"] = q
                            if hit["named"] and hit["url"] not in {h["url"] for h in rec["hits"]}:
                                rec["hits"].append(hit)
                        if f"&p={p + 1}" not in page:
                            break
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            print(name, lang, len(rec["hits"]), flush=True)


# ── devcheck ────────────────────────────────────────────────────────────────

def cmd_devcheck(args):
    """Open every forum hit and keep the ones written by the developer.

    Steam marks a developer's reply with the CSS class
    `commentthread_author_developer` on its author link. A hit URL ending in
    `#c<id>` is a reply, found by that id; one without is the thread's opening
    post. This is what turns "someone on the forum said" into a first-hand
    source. Output: devcheck.jsonl, one line per game, resumable.
    """
    fpath = wpath(args, "forums.jsonl")
    if not os.path.exists(fpath):
        sys.exit("run `forums` first")
    out = wpath(args, "devcheck.jsonl")
    done = resumable(out)
    community = Community(args.delay)
    pages = {}
    with open(out, "a") as f:
        for line in open(fpath):
            rec = json.loads(line)
            if rec["game"] in done or not rec["hits"]:
                continue
            for h in rec["hits"]:
                thread = h["url"].split("#")[0]
                if thread not in pages:
                    pages[thread] = community.get(thread)
                page = pages[thread]
                if not page:
                    rec["err"] = 1
                    continue
                m = re.search(r"#c(\d+)", h["url"])
                i = page.find(f'id="comment_{m.group(1)}"') if m else page.find("forum_op_header")
                block = ""
                if i >= 0:
                    # End at the next comment, or a badge further down the
                    # thread would be credited to this post.
                    j = page.find('id="comment_', i + 20)
                    block = page[i:j if j > 0 else i + 6000]
                h["developer"] = "_author_developer" in block
                body = re.search(r'class="(?:commentthread_comment_text|forum_op)[^"]*"[^>]*>(.*?)</div>', block, re.S)
                h["dev_text"] = clean(body.group(1))[:1500] if (h["developer"] and body) else ""
            rec["hits"] = [h for h in rec["hits"] if h.get("developer")] if not rec.get("err") else rec["hits"]
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            for h in rec["hits"]:
                if h.get("developer"):
                    print(f"{rec['game']} <- {h['named']} by {h['author']}: {h['url']}", flush=True)


# ── X / Twitter ─────────────────────────────────────────────────────────────

def read_tweet(url):
    """Author, date and text of one tweet, without logging in.

    x.com itself serves an empty JavaScript shell to anything not logged in, and
    profiles and timelines can't be read at all. The two embed endpoints that
    websites use to show a tweet still answer, so a tweet whose URL is known can
    be read and attributed. FINDING tweets has to go through a web search
    restricted to x.com, which indexes individual tweets with their text.
    """
    m = re.search(r"(?:x|twitter)\.com/([^/]+)/status(?:es)?/(\d+)", url or "")
    if not m:
        return None
    handle, tid = m.groups()
    try:
        j = json.loads(get(f"https://cdn.syndication.twimg.com/tweet-result?id={tid}&token=a", timeout=20))
        if j.get("__typename") == "TweetTombstone":
            # A deleted or withheld tweet answers with a tombstone, not an error.
            return {"handle": handle, "name": "", "date": "", "text": "",
                    "err": clean(j.get("tombstone", {}).get("text", {}).get("text", "deleted"))}
        user = j.get("user", {})
        return {"handle": user.get("screen_name", handle), "name": user.get("name", ""),
                "date": j.get("created_at", "")[:10], "text": clean(j.get("text", ""))}
    except Exception:
        pass
    try:
        j = json.loads(get("https://publish.twitter.com/oembed?omit_script=1&url="
                           + urllib.parse.quote(f"https://x.com/{handle}/status/{tid}"), timeout=20))
        body = re.search(r"<p[^>]*>(.*?)</p>", j.get("html", ""), re.S)
        date = re.findall(r">([A-Z][a-z]+ \d+, \d{4})</a>", j.get("html", ""))
        return {"handle": j.get("author_url", "").rsplit("/", 1)[-1], "name": j.get("author_name", ""),
                "date": date[-1] if date else "", "text": clean(body.group(1)) if body else ""}
    except Exception:
        return {"handle": handle, "name": "", "date": "", "text": "", "err": "unreadable (deleted or private?)"}


def cmd_xsources(args):
    """Read every X/Twitter source the `connections` sheet already cites.

    For each row it prints who posted the tweet and whether the text names the
    influencer. The question it answers: is this the developer talking, or a fan?
    A fan's tweet is not first-hand. A deleted tweet means the row needs a new
    source. Output: xsources.md, for a person to read.
    """
    _, conns = load_sheet()
    devs = json.load(open(wpath(args, "devs.json"))) if os.path.exists(wpath(args, "devs.json")) else {}
    rows = [r for r in conns if re.search(r"(?:x|twitter)\.com/[^/]+/status", str(r[4] or ""))]
    out = wpath(args, "xsources.md")
    with open(out, "w") as f:
        f.write("# X/Twitter sources in `connections`: who posted them\n\n")
        for r in rows:
            t = read_tweet(str(r[4])) or {}
            words = [w for w in re.findall(r"\w{4,}", r[0]) if w.lower() not in ("the", "with")]
            names_it = any(w.lower() in t.get("text", "").lower() for w in words) if words else False
            studio = ", ".join(devs.get(r[1], {}).get("devs") or [])
            f.write(f"## {r[0]} → {r[1]}\n"
                    f"- posted by **@{t.get('handle', '?')}** ({t.get('name', '')}), {t.get('date', '')}"
                    f"{' — ' + t['err'] if t.get('err') else ''}\n"
                    f"- influencee's Steam developer: {studio or 'unknown'}\n"
                    f"- names the influencer: {'yes' if names_it else '**no**'}\n"
                    f"- text: {t.get('text', '')[:400]}\n- {r[4]}\n\n")
            time.sleep(0.5)
    print(f"{len(rows)} X/Twitter sources -> {out}")


# ── media (interview videos and podcasts) ───────────────────────────────────

MEDIA = os.path.join(ROOT, "docs", "influence-media.md")
# A source that isn't a link is a connection the owner believes in but can't
# point at yet: `check folder`, `look at it`, a note about a Discord. Those are
# the "suspected" rows, and an interview is the likeliest place to confirm one.
def _placeholder(row):
    src = str(row[4] or "").strip()
    return not src.startswith("http") and str(row[3] or "").strip().lower() != "yes"

# What makes a result worth a listen. A title has to name the game AND say one
# of these; "Dome Keeper gameplay" names the game and says nothing.
MEDIA_CUE = re.compile(
    r"interview|developer|\bdevs?\b|creator|designer|director|founder|"
    r"\bq ?& ?a\b|\bama\b|post-?mortem|\bgdc\b|making of|behind the|devlog|"
    r"talks? (?:to|with)|chat(?:ting)? with|sits? down|joins us|joined by|guest|\bfeat\.|\bft\.|"
    r"インタビュー|開発者|인터뷰|개발자|采访|访谈|开发者|entrevista|wywiad|интервью|разработчик", re.I)
# Words that mean a player, not a developer, is talking. Dropped unless the
# title is ALSO an interview ("Dev reacts to my run" survives).
MEDIA_NOISE = re.compile(
    r"gameplay|let'?s play|walkthrough|\breview\b|trailer|tier list|first look|"
    r"guide|tips|speedrun|\bmod\b|#shorts|playthrough|\bep\.? ?\d|\bpart \d|\bday \d|\brun \d",
    re.I)
MEDIA_STRONG = re.compile(r"interview|\bq ?& ?a\b|\bama\b|post-?mortem|\bgdc\b|developer|"
                          r"インタビュー|인터뷰|采访|访谈|entrevista|wywiad|интервью", re.I)


def _short_name(name):
    """`Slime 3K: Rise Against Despot` is said aloud as `Slime 3K`."""
    head = re.split(r"\s*[:\-–]\s+", name)[0]
    return head if len(head) >= 4 and head != name else None


def _mentions(text, name):
    flags = 0 if name in AMBIGUOUS else re.I
    for n in filter(None, (name, _short_name(name))):
        if re.search(r"(?<![\w])" + re.escape(n) + r"(?![\w])", text, flags):
            return True
    return False


def _yt_search(query):
    """YouTube's own results page; the data is a JSON blob in the HTML. No key."""
    page = get("https://www.youtube.com/results?hl=en&search_query=" + urllib.parse.quote(query))
    m = re.search(r"var ytInitialData = (\{.*?\});</script>", page)
    if not m:
        return []
    out = []
    def walk(o):
        if isinstance(o, dict):
            v = o.get("videoRenderer")
            if v and v.get("videoId"):
                txt = lambda k: "".join(r.get("text", "") for r in (v.get(k) or {}).get("runs", [])) \
                    or (v.get(k) or {}).get("simpleText", "")
                snip = " ".join("".join(r.get("text", "") for r in s.get("snippetText", {}).get("runs", []))
                                for s in v.get("detailedMetadataSnippets", []))
                out.append({"url": "https://www.youtube.com/watch?v=" + v["videoId"],
                            "title": txt("title"), "by": txt("ownerText"),
                            "length": txt("lengthText"), "when": txt("publishedTimeText"),
                            "text": snip})
                return
            for x in o.values():
                walk(x)
        elif isinstance(o, list):
            for x in o:
                walk(x)
    walk(json.loads(m.group(1)))
    return out


class _Paced:
    """Apple's search API allows about 20 calls a minute; go a little under."""
    def __init__(self, delay):
        self.delay, self.last = delay, 0.0

    def get(self, url):
        wait = self.last + self.delay - time.time()
        if wait > 0:
            time.sleep(wait)
        self.last = time.time()
        for attempt in range(4):
            try:
                return get(url)
            except Exception as e:
                if "403" not in str(e) and "429" not in str(e):
                    raise
                time.sleep(60 * (attempt + 1))
        raise RuntimeError("rate limited")


def _podcasts(paced, name):
    d = json.loads(paced.get("https://itunes.apple.com/search?media=podcast&entity=podcastEpisode"
                             "&limit=50&term=" + urllib.parse.quote(_short_name(name) or name)))
    out = []
    for r in d.get("results", []):
        ms = r.get("trackTimeMillis") or 0
        out.append({"url": r.get("trackViewUrl", "").split("&uo=")[0],
                    "title": r.get("trackName", ""), "by": r.get("collectionName", ""),
                    "length": "%d min" % (ms // 60000) if ms else "",
                    "when": (r.get("releaseDate") or "")[:10],
                    "text": clean(r.get("description") or r.get("shortDescription") or "")[:600]})
    return out


def _near(text, name, span=150):
    """A cue within `span` characters of the game's name: in a podcast blurb that
    covers six games, "joined by the developer" belongs to the one beside it."""
    flags = 0 if name in AMBIGUOUS else re.I
    for n in filter(None, (name, _short_name(name))):
        for m in re.finditer(r"(?<![\w])" + re.escape(n) + r"(?![\w])", text, flags):
            if MEDIA_CUE.search(text[max(0, m.start() - span):m.end() + span]):
                return True
    return False


def _keep(hit, name, devs):
    """A hit worth listing, and why. None to drop it.

    The cue has to be in the title or the channel/show name ("Shacknews
    Interviews"), or right beside the game's name in the description, or the
    studio has to be named. A cue anywhere in a description is not enough: fan
    podcasts and Let's Plays say "dev" somewhere in nearly every blurb.
    """
    head = hit["title"]
    body = head + " " + hit["text"]
    # The game in the title, or beside a cue in the description. A show that
    # merely shares the name ("Dice With Death - A Dungeons & Dragons podcast")
    # names it in every blurb and is never about the game.
    if not (_mentions(head, name) or _near(hit["text"], name)) or _mentions(hit["by"], name):
        return None
    dev = any(d and len(d) > 3 and re.search(r"(?<![\w])" + re.escape(d) + r"(?![\w])",
                                              body + " " + hit["by"], re.I) for d in devs)
    cue = MEDIA_CUE.search(head) or MEDIA_CUE.search(hit["by"]) or _near(hit["text"], name)
    if not (cue or dev):
        return None
    if MEDIA_NOISE.search(head) and not MEDIA_STRONG.search(head):
        return None
    # "Episode 204: Rise & Shine / Undertale / Thumper / …" is a roundup.
    if len(re.findall(r" / |, | \| | & ", head)) >= 2 and not MEDIA_STRONG.search(head):
        return None
    why = sorted({m.group(0).lower() for m in MEDIA_CUE.finditer(head + " " + hit["by"])})[:3]
    if dev:
        why.append("names the developer")
    elif not why:
        why.append("cue in the description")
    hit["why"] = why
    hit["score"] = (2 * bool(MEDIA_STRONG.search(head)) + 2 * dev
                    + bool(MEDIA_CUE.search(head)) + bool(_mentions(head, name)))
    return hit


def media_targets(games, conns, max_degree):
    """Games worth an interview hunt: few connections, or a connection whose
    source is a placeholder. Returns {name: {"degree", "suspected": [...]}}."""
    deg, sus = {}, {}
    for r in conns:
        deg[r[0]] = deg.get(r[0], 0) + 1
        deg[r[1]] = deg.get(r[1], 0) + 1
        if _placeholder(r):
            # The influencee is the one who would have said it.
            sus.setdefault(r[1], []).append((r[0], str(r[4] or "").strip()))
    out = {}
    for r in games:
        n = r[0]
        if deg.get(n, 0) <= max_degree or n in sus:
            out[n] = {"year": r[1], "degree": deg.get(n, 0), "suspected": sus.get(n, [])}
    return out


def cmd_media(args):
    """Interview videos and podcast episodes to listen to, per game.

    Nobody can read a video, so this does the searching and leaves the listening
    to a person: for each game with `--max-degree` connections or fewer, or with
    a connection whose Source is a placeholder (`check folder`, `look at it`), it
    searches YouTube and Apple Podcasts and keeps results whose title or
    description names the game AND reads like the developer talking (interview,
    podcast, Q&A, postmortem, GDC, devlog, or the studio's own name). It writes
    `docs/influence-media.md`, a checklist that says what to listen for.

    Results are cached in --work/media.jsonl and the run resumes, because Apple's
    API allows about 20 calls a minute (`--delay`, default 3.5 s) and 600 games
    is over half an hour. YouTube is searched in parallel and isn't paced.
    `devs` first is optional but helps: the studio's name in a result is the
    best sign the developer is in it.
    """
    games, conns = load_sheet()
    targets = media_targets(games, conns, args.max_degree)
    dpath = wpath(args, "devs.json")
    devs = json.load(open(dpath)) if os.path.exists(dpath) else {}
    out = wpath(args, "media.jsonl")
    done = resumable(out)
    todo = [n for n in sorted(targets, key=lambda n: (targets[n]["degree"], n.lower())) if n not in done]
    if args.limit:
        todo = todo[:args.limit]
    if args.write_only:
        return write_media_doc(targets, out, devs, args.per_game)
    paced = _Paced(args.delay)
    print(f"{len(targets)} games to search, {len(done)} cached, {len(todo)} to go", flush=True)

    def videos(name):
        q = name + (" roguelike" if name in AMBIGUOUS else "")
        hits, seen = [], set()
        try:
            for query in (f'"{q}" developer interview', f'"{q}" podcast'):
                for h in _yt_search(query):
                    if h["url"] not in seen:
                        seen.add(h["url"])
                        hits.append(h)
        except Exception as e:
            return hits, str(e)
        return hits, None

    with cf.ThreadPoolExecutor(3) as ex, open(out, "a") as f:
        futures = {n: ex.submit(videos, n) for n in todo}
        for name in todo:
            names = _studio(devs, name)
            rec = {"game": name, "videos": [], "podcasts": []}
            vids, err = futures[name].result()
            try:
                pods = _podcasts(paced, name)
            except Exception as e:
                pods, err = [], err or str(e)
            if err:
                rec["err"] = err
            # Raw results are cached and filtered when the doc is written, so
            # the filter can be tuned (`media --write-only`) without searching again.
            rec["videos"], rec["podcasts"] = vids, pods
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            v, p = _filtered(rec, name, names, args.per_game)
            print("%-45s %d videos, %d podcasts%s" % (name[:45], len(v), len(p),
                                                     "  (error: %s)" % err[:60] if err else ""), flush=True)
    write_media_doc(targets, out, devs, args.per_game)


def _media_line(kind, h, heard=()):
    meta = " · ".join(x for x in (h["by"], h["length"], h["when"]) if x)
    why = (" — " + ", ".join(h["why"])) if h.get("why") else ""
    title = h["title"].replace("[", "(").replace("]", ")").replace("|", "/")
    return "- [%s] %s [%s](%s) — %s%s" % ("x" if h["url"] in heard else " ", kind, title, h["url"], meta, why)


def _studio(devs, name):
    """The developer's names. Not the publisher: "Devolver" is in a hundred
    podcasts that never mention this game's developer."""
    return [d for d in (devs.get(name) or {}).get("devs") or [] if len(d) > 4]


def _filtered(rec, name, names, per_game):
    pick = lambda hits: sorted(filter(None, (_keep(dict(h), name, names) for h in hits)),
                               key=lambda h: -h["score"])[:per_game]
    return pick(rec["videos"]), pick(rec["podcasts"])


def write_media_doc(targets, jsonl, devs, per_game):
    recs = {}
    if os.path.exists(jsonl):
        for line in open(jsonl):
            r = json.loads(line)
            if r["game"] in targets:
                v, p = _filtered(r, r["game"], _studio(devs, r["game"]), per_game)
                recs[r["game"]] = dict(r, videos=v, podcasts=p)  # a rerun's line replaces the old one
    found = {n: r for n, r in recs.items() if n in targets and (r["videos"] or r["podcasts"])}
    # The doc is rewritten on every run, and the owner ticks lines in it as they
    # listen. Carry those ticks over by URL, or a resumed search would undo them.
    heard = set()
    if os.path.exists(MEDIA):
        heard = set(re.findall(r"^- \[x\] \w+ \[.*?\]\((\S+?)\)", open(MEDIA, encoding="utf8").read(), re.M))
    sus = sorted((n for n in found if targets[n]["suspected"]), key=str.lower)
    low = sorted((n for n in found if not targets[n]["suspected"]),
                 key=lambda n: (targets[n]["degree"], n.lower()))
    lines = [
        "# Interviews and podcasts to listen to",
        "",
        "Videos and podcast episodes where a developer may say what inspired their game, found by "
        "`python3 tools/influence_research.py media`. Nothing here has been watched: each line is a search "
        "result whose title or description names the game and reads like the developer talking. "
        "Expect some misses (a fan podcast, a different game with the same name).",
        "",
        "**How to use it.** Pick a game, listen, and if the developer names an influence, add the row to "
        "`connections` with the video or episode as the Source, and a timestamp if you can "
        "(`youtube.com/watch?v=…&t=754`). Tick the line either way, so the next pass knows it was heard. "
        "The rules for what counts are in `docs/influence-research.md`.",
        "",
        "| | games | results |",
        "|---|---|---|",
        "| 1. Confirm a suspected connection | %d | %d |" % (len(sus), sum(len(found[n]["videos"]) + len(found[n]["podcasts"]) for n in sus)),
        "| 2. Games with %s connection%s | %d | %d |" % (
            "few", "s", len(low), sum(len(found[n]["videos"]) + len(found[n]["podcasts"]) for n in low)),
        "",
        "Searched %d of the %d games that qualify%s; %d had nothing that looked like the developer talking." % (
            len(recs), len(targets),
            "" if len(recs) >= len(targets) else
            " (fewest connections first; `media` picks up where it stopped, see `docs/influence-research.md`)",
            len(recs) - len(found)),
        "",
        "---",
        "",
        "## 1. Confirm a suspected connection",
        "",
        "The sheet connects these, but the Source is a note rather than a link. Listen for the game named.",
        "",
    ]
    def block(n):
        t, r = targets[n], found[n]
        out = ["### %s (%s) — %d connection%s" % (n, t["year"] or "?", t["degree"], "" if t["degree"] == 1 else "s"), ""]
        if t["suspected"]:
            out.append("Listen for: " + "; ".join('**%s** (sheet says "%s")' % (a, s or "nothing")
                                                for a, s in t["suspected"]))
            out.append("")
        out += [_media_line("video", h, heard) for h in r["videos"]]
        out += [_media_line("podcast", h, heard) for h in r["podcasts"]]
        return out + [""]
    for n in sus:
        lines += block(n)
    lines += ["## 2. Games with few connections", "",
              "Held on the map by one connection or none. Listen for any game on the chart.", ""]
    for n in low:
        lines += block(n)
    open(MEDIA, "w", encoding="utf8").write("\n".join(lines).rstrip() + "\n")
    print("wrote %s: %d games with something to listen to" % (os.path.relpath(MEDIA, ROOT), len(found)))


# ── status ──────────────────────────────────────────────────────────────────

CANDIDATES = os.path.join(ROOT, "docs", "influence-candidates.md")
# `**Influencer → Influencee**`, the format every candidate line uses. Anything
# after it on the line (the quote, the source) is left alone.
CANDIDATE = re.compile(r"\*\*([^*→]+?) → ([^*]+?)\*\*")
# The doc is laid out by what the owner does next: sections 1 and 2 hold the
# open lines (2 is games not on the sheet yet), section 7 the ones now in the
# sheet. These headings are how `status` finds its way around it.
WANTED_SECTION = "## 2."
DONE_SECTION = "## 7."


def _line_pairs(line):
    """The pairs a candidate line PROPOSES: the bold pairs before its ` — `.

    After the dash comes the quote, and a line that shares one says so with
    `same as **A → B**`. That pair is a cross-reference, not part of the line:
    counting it kept **Brotato → Slime 3K** open after the owner added it,
    because the Despotism 3k pair it pointed at was (deliberately) left out.
    """
    return list(CANDIDATE.finditer(line.split(" — ", 1)[0]))


def _pair_key(line):
    p = CANDIDATE.findall(line)
    return (p[0][1].lower(), p[0][0].lower()) if p else ("~", line)


def _recount(text):
    """Refresh the line counts in the table at the top of the doc."""
    count, sec, sub = {}, "", ""
    for line in text.split("\n"):
        if line.startswith("## "):
            sec, sub = line[:5], ""
        elif line.startswith("### "):
            sub = line
        elif line.startswith("- [ ] ") or line.startswith("- [x] "):
            kind = "weaker" if "Weaker" in sub else "strong"
            count[(sec, kind)] = count.get((sec, kind), 0) + 1
            count[(sec, "all")] = count.get((sec, "all"), 0) + 1
    def row(label, sec):
        return "| %s | %d strong, %d weaker |" % (label, count.get((sec, "strong"), 0), count.get((sec, "weaker"), 0))
    text = re.sub(r"\| 1\. To review: games on the sheet \|[^\n]*", row("1. To review: games on the sheet", "## 1."), text)
    text = re.sub(r"\| 2\. To review: games you want to add \|[^\n]*", row("2. To review: games you want to add", "## 2."), text)
    return re.sub(r"\| 7\. Done: on the chart \|[^\n]*", "| 7. Done: on the chart | %d |" % count.get(("## 7.", "all"), 0), text)


def cmd_status(args):
    """Which candidates in `docs/influence-candidates.md` are in the sheet now.

    The owner adds approved rows to `connections` by hand, so the candidate list
    falls behind the sheet. This reads both and prints, per open `- [ ]` line,
    whether every pair on it is a row now. With --tick those lines are ticked,
    marked `✓ on the chart`, and moved into section 7 in their sorted place, so
    sections 1 and 2 only ever hold what is left to review.

    A name the sheet doesn't have exactly (the doc says "Spelunky", or a series,
    where the sheet names one game) is reported rather than guessed: fix the
    line to name the row the owner picked, and run it again. In section 2 the
    games are not on the sheet yet by definition, so a missing name there is
    reported as waiting for its game row, not as a misspelling.
    """
    games, conns = load_sheet()
    have = {(str(a).strip().lower(), str(b).strip().lower()) for a, b, *_ in conns}
    names = {str(r[0]).strip().lower() for r in games}
    lines = open(CANDIDATES, encoding="utf8").read().split("\n")
    added, still_open, unknown, waiting = [], [], [], []
    section = ""
    for i, line in enumerate(lines):
        if line.startswith("## "):
            section = line
            continue
        if not line.startswith("- [ ] ") or section.startswith(DONE_SECTION):
            continue
        pairs = [m.groups() for m in _line_pairs(line)]
        if not pairs:
            continue
        missing = list(dict.fromkeys(n for p in pairs for n in p if n.strip().lower() not in names))
        if all((a.strip().lower(), b.strip().lower()) in have for a, b in pairs):
            added.append(i)
        elif missing and section.startswith(WANTED_SECTION):
            waiting.append((i, missing))
        elif missing:
            unknown.append((i, missing))
        else:
            still_open.append(i)
    for i in added:
        print("in the sheet  %4d  %s" % (i + 1, " ; ".join("%s → %s" % m.groups() for m in _line_pairs(lines[i]))))
    for i, missing in unknown:
        print("name?         %4d  not a sheet name: %s" % (i + 1, ", ".join(missing)))
    for i, missing in waiting:
        print("no game row   %4d  add to `games` first: %s" % (i + 1, ", ".join(missing)))
    print("%d open line(s) are in the sheet, %d are not, %d name a game the sheet spells "
          "differently, %d wait for a game row" % (len(added), len(still_open), len(unknown), len(waiting)))
    if not (args.tick and added):
        return
    moved = []
    for i in added:
        line = lines[i]
        end = _line_pairs(line)[-1].end()
        moved.append("- [x] " + line[6:end] + " ✓ *on the chart*" + line[end:])
    keep = [l for n, l in enumerate(lines) if n not in set(added)]
    start = next(n for n, l in enumerate(keep) if l.startswith(DONE_SECTION))
    stop = next((n for n in range(start + 1, len(keep)) if keep[n].startswith("## ")), len(keep))
    body = [l for l in keep[start + 1:stop] if l.startswith("- [x] ")]
    first = next(n for n in range(start + 1, stop) if keep[n].startswith("- [x] "))
    last = max(n for n in range(start + 1, stop) if keep[n].startswith("- [x] "))
    keep[first:last + 1] = sorted(body + moved, key=_pair_key)
    open(CANDIDATES, "w", encoding="utf8").write(_recount("\n".join(keep)))
    print("ticked %d line(s) and moved them to section 7 of %s"
          % (len(added), os.path.relpath(CANDIDATES, ROOT)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work", default=os.path.join(ROOT, ".influence_work"))
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("targets")
    sub.add_parser("devs")
    sub.add_parser("samedev")
    sub.add_parser("steam")
    sub.add_parser("xsources")
    sub.add_parser("wanted").add_argument("file", help="text file, one game name per line")
    sub.add_parser("cues").add_argument("--games", choices=["leaves", "all"], default="leaves")
    mp = sub.add_parser("media")
    mp.add_argument("--max-degree", type=int, default=1, help="search games with this many connections or fewer")
    mp.add_argument("--per-game", type=int, default=4, help="results kept per game, each of videos and podcasts")
    mp.add_argument("--delay", type=float, default=3.5, help="seconds between Apple Podcasts searches")
    mp.add_argument("--write-only", action="store_true", help="rewrite the doc from the cache, no searching")
    mp.add_argument("--limit", type=int, default=0, help="stop after this many games (0 = all)")
    sub.add_parser("status").add_argument("--tick", action="store_true",
                                          help="tick the candidate lines that are in the sheet now")
    for name in ("lang", "forums", "devcheck"):
        sp = sub.add_parser(name)
        sp.add_argument("--games", choices=["targets", "all"], default="targets")
        sp.add_argument("--delay", type=float, default=15.0)
    sub.choices["lang"].add_argument("--forums", action="store_true",
                                     help="also read each game's forum index for language subforums")
    args = ap.parse_args()
    {"targets": cmd_targets, "devs": cmd_devs, "samedev": cmd_samedev, "steam": cmd_steam,
     "lang": cmd_lang, "forums": cmd_forums, "devcheck": cmd_devcheck, "xsources": cmd_xsources, "status": cmd_status,
     "cues": cmd_cues, "wanted": cmd_wanted, "media": cmd_media}[args.cmd](args)


if __name__ == "__main__":
    main()
