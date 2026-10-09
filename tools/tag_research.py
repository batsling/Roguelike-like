#!/usr/bin/env python3
"""Suggest which games should carry which tags — into a research sheet, never the
games sheet.

WHY. A game's `Tags` (the `games` sheet, column F) are the theme it is ABOUT —
space, dice, undead, maritime — and they do real work: an event's detour
(`EventSystem.games_with_tag`) can only send the run to a game carrying the
tag it names. Most games carry none: 678 of 917 when this was written. Tagging
by hand means remembering, game by game, which of 31 themes each one has.

WHAT IT DOES. For every game with a Steam page it reads that page once — the
players' tags (the top 20, with vote counts) and the developer's "About This
Game" text — and matches both against EVIDENCE: for each tag on the sheet, the
Steam tags and the phrases that say a game has that theme. Every match that
names a tag the game doesn't already carry becomes a row in
`tools/Research.xlsx`:

    tag suggestions   one row per (game, suggested tag), with the evidence and
                      how strong it is. The `Owner` column is yours: write `yes`
                      or `no`; it is carried over every time this is rerun, so a
                      `no` never comes back as a fresh suggestion and a `yes`
                      waits there until you have typed the tag into `games`
                      (then the row drops off, because the game has the tag).
    new tag ideas     themes the vocabulary doesn't have, with the games that
                      would carry each: Steam tags like Pirates or Dinosaurs
                      that several games share. A new tag is a decision about
                      the game's design (an event has to want it), so these are
                      only listed.
    vocabulary        each tag on the sheet, the evidence that suggests it, and
                      how well that evidence finds the games ALREADY tagged —
                      the only measure of a rule's quality there is.

It never writes `tools/Roguelikes.xlsx`; the owner reads the suggestions and
types the ones they agree with into `games` themselves.

    python3 tools/tag_research.py              # fetch what isn't cached, write tools/Research.xlsx
    python3 tools/tag_research.py --write-only # rewrite from the cache, no fetching
    python3 tools/tag_research.py --stats      # print the vocabulary table, write nothing

Pages are cached in `.influence_work/tags/` (gitignored, shared with
influence_research.py's work folder). A first run reads ~800 Steam pages and
takes a few minutes; reruns only fetch games that are new.

A game with no Steam page gets no suggestions: the traditional roguelikes
mostly. Their themes are for the owner's memory.
"""

import argparse
import collections
import concurrent.futures as cf
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

import openpyxl  # reads Roguelikes.xlsx read-only; WRITES only Research.xlsx, which has no charts to lose
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.worksheet.datavalidation import DataValidation

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import research_book  # noqa: E402  the workbook every kind of research shares

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")
OUT = os.path.join(ROOT, "tools", "Research.xlsx")
CACHE = os.path.join(ROOT, ".influence_work", "tags")
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/130.0 Safari/537.36",
      # The age gate: without these a mature game's page is the gate, not the game.
      "Cookie": "birthtime=0; lastagecheckage=1-0-1990; mature_content=1; wants_mature_content=1"}

# What says a game has each theme. `steam` is Steam's own tag names (exact,
# case-insensitive); `text` is a pattern over the developer's store text. Both
# were tuned against the games already tagged (see the vocabulary sheet): a
# rule that also fires on half the untagged catalog is a rule about something
# else. A phrase has to be about the GAME's world, so `text` patterns avoid
# words with an everyday sense ("train your skills", "a sea of enemies").
EVIDENCE = {
    "space": {"steam": ["Space", "Space Sim"],
              "text": r"\b(?:outer space|spaceships?|starships?|space station|galax(?:y|ies)|"
                      r"star systems?|asteroids?|interstellar)\b"},
    # The owner files the peg-and-pinball games here too (Peglin, Ballionaire):
    # they are the casino's machines, not a sport.
    "casino": {"steam": ["Gambling", "Casino", "Poker", "Pinball"],
               "text": r"\b(?:casinos?|slot machines?|slots|poker|blackjack|roulette|gambl\w+|pachinko|plinko|"
                       r"pinball|coin pusher)\b"},
    "dice": {"steam": ["Dice"], "text": r"\b(?:dice|d6|d20)\b"},
    "undead": {"steam": ["Zombies"],
               "text": r"\b(?:undead|skeletons?|zombies?|necromanc\w+|liches?|ghouls?)\b"},
    "mecha": {"steam": ["Mechs"], "text": r"\b(?:mechs?|mecha|giant robots?)\b"},
    "tower defense": {"steam": ["Tower Defense"], "text": r"\btower defen[cs]e\b"},
    # Farming counts: Atomicrops, Crop Rotation and Another Farm Roguelike are all `food`.
    "food": {"steam": ["Cooking", "Food", "Farming Sim", "Farming", "Agriculture"],
             "text": r"\b(?:cook(?:ing)?|recipes?|chefs?|restaurants?|ingredients?|kitchen)\b"},
    "pokémon": {"steam": ["Creature Collector"],
                "text": r"\b(?:monster[- ]tam\w+|tame (?:wild )?(?:monsters|creatures)|catch(?:ing)? "
                        r"(?:monsters|creatures)|creature[- ]collect\w*|pok[eé]mon)\b"},
    "touhou": {"steam": [], "text": r"\b(?:touhou|gensokyo)\b"},
    "maritime": {"steam": ["Pirates", "Naval", "Naval Combat", "Sailing", "Underwater"],
                 "text": r"\b(?:pirates?|sailors?|sailing|naval|ocean|high seas|ships? captain|"
                         r"captain (?:a|your) ship|underwater)\b"},
    # Never "bullet hell", the genre half the catalog is.
    "hell": {"steam": ["Demons"], "text": r"(?<!bullet )(?<!bullet-)\bhell\b|\b(?:inferno|demons?|devils?|underworld)\b"},
    "mining": {"steam": ["Mining"], "text": r"\b(?:mining|miners?|mine (?:for|deeper|ores?))\b|\bdig(?:ging)? deep"},
    "knights": {"steam": [], "text": r"\bknights?\b"},
    "chess": {"steam": ["Chess"], "text": r"\bchess\b"},
    "rhythm": {"steam": ["Rhythm"], "text": r"\brhythm\b|\bto the beat\b"},
    "sports": {"steam": ["Sports", "Football (Soccer)", "Football (American)", "Basketball", "Golf",
                         "Baseball", "Tennis", "Bowling", "Mini Golf", "Hockey", "Volleyball"],
               "text": r"\b(?:football|footy|soccer|basketball|golf|baseball|tennis|bowling|hockey)\b"},
    "words": {"steam": ["Word Game", "Typing"], "text": r"\b(?:word game|spell(?:ing)? words|letter tiles|typing)\b"},
    # Anime and Horror are as often an art style or a mood on Steam as a theme,
    # and the owner tags only the games that ARE one (licensed anime, horror
    # games), so the Steam tag has to be in the top five to count as strong.
    "anime": {"steam": ["Anime"], "text": r"\banime\b", "strong_rank": 5},
    "vampire": {"steam": ["Vampires", "Vampire"], "text": r"\bvampir\w*"},
    "horror": {"steam": ["Horror", "Psychological Horror", "Survival Horror"],
               "text": r"\bhorror\b", "strong_rank": 5},
    "cats": {"steam": ["Cats"], "text": r"\b(?:cats?|kittens?|feline)\b"},
    "gacha": {"steam": [], "text": r"\bgacha\b"},
    "crab": {"steam": [], "text": r"\b(?:crabs?|crustaceans?)\b"},
    "mahjong": {"steam": ["Mahjong"], "text": r"\bmah[- ]?jong\b"},
    "train": {"steam": ["Trains"], "text": r"\b(?:locomotives?|railways?|railroads?|train cars?|steam trains?)\b"},
    "racing": {"steam": ["Racing", "Driving", "Combat Racing"], "text": r"\b(?:racing|race cars?)\b"},
    "beat 'em up": {"steam": ["Beat 'em up"], "text": r"\bbeat[- ]'?em[- ]up\b"},
    "western": {"steam": ["Western"], "text": r"\b(?:wild west|cowboys?|gunslingers?|outlaws?)\b"},
    "viking": {"steam": ["Vikings"], "text": r"\b(?:vikings?|norse)\b"},
    "cyberpunk": {"steam": ["Cyberpunk"], "text": r"\bcyberpunk\b"},
    "antagonist": {"steam": ["Villain Protagonist"],
                   "text": r"\bplay (?:as )?(?:the )?(?:villain|bad guys?|dungeon (?:lord|master|keeper))\b"},
}

# Steam tags that describe a THEME (what the game is about) rather than a genre,
# mechanic or art style — the only ones worth proposing as new sheet tags.
THEMES = {
    "Aliens", "Dinosaurs", "Dragons", "Ninja", "Samurai", "Robots", "Post-apocalyptic", "Lovecraftian",
    "Mythology", "Medieval", "Steampunk", "Dark Fantasy", "Military", "Fishing", "Magic", "Supernatural",
    "Nature", "Underground", "Superhero", "Time Travel", "Martial Arts", "Hunting", "Crime", "Detective",
    "Heist", "Music", "Political", "Science", "Gothic", "Dystopian", "Alternate History", "World War II",
    "World War I", "Cold War", "Wizards", "Witches", "Elves", "Dwarves", "Gods", "Ghosts", "Werewolves",
    "Dungeons & Dragons", "Birds", "Dog", "Horses", "Insects", "Mars", "Faith", "Snow", "Desert", "Jungle",
    "Island", "Japan", "Egypt", "Hacking", "Spaceships", "Bikes", "Capitalism", "Archery", "Swordplay",
    "Tanks", "Submarine", "Naval", "Pirates", "Space", "Zombies", "Vampires", "Cats", "Trains", "Western",
    "Vikings", "Cyberpunk", "Mining", "Chess", "Dice", "Gambling", "Rhythm", "Anime", "Horror", "Demons",
    "Creature Collector", "Tower Defense", "Cooking", "Sports", "Farming Sim", "Mechs", "Poker", "Pinball",
}
NEW_TAG_MIN = 4  # a theme on fewer games than this is not worth a tag an event could name


# ── Steam ───────────────────────────────────────────────────────────────────

def get(url, timeout=40):
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf8", "replace")


def clean(text):
    text = re.sub(r"<br\s*/?>|</p>|</li>|</h\d>", ". ", text)
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def parse_store(page):
    """{"tags": [[name, votes], ...], "about": str} out of a store page's HTML."""
    m = re.search(r"InitAppTagModal\(\s*\d+,\s*(\[.*?\])\s*,", page, re.S)
    tags = [[t["name"], t.get("count", 0)] for t in json.loads(m.group(1))] if m else []
    snippet = re.search(r'class="game_description_snippet"[^>]*>(.*?)</div>', page, re.S)
    i = page.find('id="game_area_description"')
    about = ""
    if i >= 0:
        # The description ends where the system requirements begin; the rest
        # of the page (curators, reviews, the tag modal's script) is not the
        # developer's and must not be read as if it were.
        stops = [j for j in (page.find(s, i) for s in ('id="game_area_content_descriptors"', 'autocollapse sys_req',
                                                        'sysreq_contents', 'id="game_area_legal"',
                                                        'id="responsive_apppage_reviewblock_ctn"')) if j > 0]
        part = page[page.find(">", i) + 1:min(stops + [i + 30000])]
        about = clean(re.sub(r"<(script|style)\b.*?</\1>", " ", part, flags=re.S | re.I))
    return {"tags": tags, "about": clean(snippet.group(1)) + " . " + about if snippet else about}


def store_page(aid):
    """A game's tags and store text, cached. None if Steam wouldn't say."""
    fn = os.path.join(CACHE, f"{aid}.json")
    if os.path.exists(fn):
        return json.load(open(fn, encoding="utf8"))
    for attempt in range(4):
        try:
            page = get(f"https://store.steampowered.com/app/{aid}/?l=english")
            break
        except urllib.error.HTTPError as e:
            if e.code not in (429, 503):
                return None
            time.sleep(30 * (attempt + 1))
        except Exception:
            time.sleep(5 * (attempt + 1))
    else:
        return None
    rec = parse_store(page)
    if not rec["tags"] and "app_tag" not in page:
        return None  # a redirect to the store front (delisted) or the age gate: not cached, so a rerun retries
    json.dump(rec, open(fn, "w", encoding="utf8"), ensure_ascii=False)
    return rec


# ── matching ────────────────────────────────────────────────────────────────

def load_games():
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    out = []
    for r in list(wb["games"].iter_rows(values_only=True))[1:]:
        if not r[0]:
            continue
        m = re.search(r"/app/(\d+)", str(r[9] or ""))
        out.append({"name": str(r[0]).strip(), "year": r[1], "type": r[2],
                    "tags": [t.strip().lower() for t in str(r[5] or "").split(",") if t.strip()],
                    "aid": m.group(1) if m else None,
                    "steam": str(r[9] or "").strip()})
    return out


def sentence_with(text, m):
    """The sentence around a match, trimmed for a cell."""
    dot = text.rfind(". ", 0, m.start())
    a = max(dot + 2 if dot >= 0 else 0, m.start() - 160)
    b = text.find(". ", m.end())
    b = min(b if b > 0 else len(text), m.end() + 160)
    return text[a:b].strip()


def evidence_for(rec, tag, name=""):
    """(strength, evidence text) for one tag on one game, or None. `rec` is its
    Steam page (None when it has none: then only the title can speak).

    strong — a Steam tag in the page's top ten (top five for a rule with
             `strong_rank`), or a Steam tag AND the store text or the title
    medium — a Steam tag further down the twenty, or the title alone
             (Knights in Tight Spaces, Hell Maiden: a lot of tags start there)
    weak   — the store text only, saying it at least twice
    """
    rule = EVIDENCE[tag]
    want = {s.lower() for s in rule["steam"]}
    ranked = [(i + 1, n) for i, (n, _) in enumerate((rec or {}).get("tags", [])) if n.lower() in want]
    about = (rec or {}).get("about", "")
    hits = list(re.finditer(rule["text"], about, re.I))
    titled = re.search(rule["text"], name, re.I)
    bits = [f'Steam tag "{n}" (#{i} of {len(rec["tags"])})' for i, n in ranked]
    if titled:
        bits.append(f'the title says "{titled.group(0)}"')
    if hits:
        words = sorted({h.group(0).lower() for h in hits})
        bits.append(f'store text says {", ".join(words[:4])} ({len(hits)}×): "{sentence_with(about, hits[0])}"')
    if ranked and (ranked[0][0] <= rule.get("strong_rank", 10) or hits or titled):
        return "strong", "; ".join(bits)
    if ranked or titled:
        return "medium", "; ".join(bits)
    if len(hits) >= 2:  # once is a passing word: "choose a Knight, a Rogue or a Wizard"
        return "weak", "; ".join(bits)
    return None


def analyse(games, pages):
    """(suggestions, vocabulary rows, new-tag ideas)."""
    sugg = []
    found = collections.Counter()   # tag -> games already tagged that the evidence finds
    tagged = collections.Counter()  # tag -> games already tagged that have a page
    for g in games:
        rec = pages.get(g["name"])
        for tag in EVIDENCE:
            ev = evidence_for(rec, tag, g["name"])
            if tag in g["tags"]:
                tagged[tag] += 1
                found[tag] += bool(ev)
            elif ev:
                sugg.append(dict(g, tag=tag, strength=ev[0], evidence=ev[1]))
    order = {"strong": 0, "medium": 1, "weak": 2}
    sugg.sort(key=lambda s: (s["name"].lower(), order[s["strength"]], s["tag"]))
    per_tag = collections.Counter(s["tag"] for s in sugg)
    strong = collections.Counter(s["tag"] for s in sugg if s["strength"] == "strong")
    vocab = []
    have_count = collections.Counter(t for g in games for t in g["tags"])
    for tag, rule in EVIDENCE.items():
        vocab.append([tag, have_count[tag], found[tag],
                      f"{found[tag] / tagged[tag]:.0%}" if tagged[tag] else "—",
                      per_tag[tag], strong[tag], ", ".join(rule["steam"]) or "—", rule["text"]])
    for tag in sorted(set(have_count) - set(EVIDENCE)):
        vocab.append([tag, have_count[tag], "", "", "", "", "no rule yet — add one to EVIDENCE", ""])
    # Themes nobody can tag yet: a Steam theme tag no rule claims, on enough games.
    claimed = {s.lower() for r in EVIDENCE.values() for s in r["steam"]}
    ideas = collections.defaultdict(list)
    for g in games:
        rec = pages.get(g["name"])
        for i, (n, _) in enumerate((rec or {}).get("tags", [])):
            if n in THEMES and n.lower() not in claimed and i < 15:
                ideas[n].append(g["name"])
    ideas = sorted(((n, gs) for n, gs in ideas.items() if len(gs) >= NEW_TAG_MIN), key=lambda x: -len(x[1]))
    return sugg, vocab, ideas


# ── the research sheet ─────────────────────────────────────────────────────

SUGG_HEAD = ["Game", "Year", "Type", "Current Tags", "Suggested Tag", "Strength", "Owner", "Evidence", "Steam Page"]


def owner_marks():
    """{(game, tag): what the owner wrote} from the Research.xlsx being replaced."""
    if not os.path.exists(OUT):
        return {}
    wb = openpyxl.load_workbook(OUT, read_only=True, data_only=True)
    if "tag suggestions" not in wb.sheetnames:
        return {}
    rows = list(wb["tag suggestions"].iter_rows(values_only=True))
    head = list(rows[0]) if rows else []
    if not {"Game", "Suggested Tag", "Owner"} <= set(head):
        return {}
    gi, ti, oi = head.index("Game"), head.index("Suggested Tag"), head.index("Owner")
    return {(r[gi], r[ti]): r[oi] for r in rows[1:] if r[gi] and r[oi] not in (None, "")}


def write_book(games, pages, sugg, vocab, ideas):
    marks = owner_marks()
    # A suggestion the owner turned down stays listed with their `no`, even if
    # the evidence has since gone, so it is never re-proposed as new.
    live = {(s["name"], s["tag"]) for s in sugg}
    by_name = {g["name"]: g for g in games}
    for (name, tag), mark in marks.items():
        g = by_name.get(name)
        if (name, tag) not in live and g and tag not in g["tags"]:
            sugg.append(dict(g, tag=tag, strength="—", evidence="(no longer found; kept for your mark)"))
    sugg.sort(key=lambda s: (s["name"].lower(), {"strong": 0, "medium": 1, "weak": 2}.get(s["strength"], 3), s["tag"]))

    # Research.xlsx is shared with tools/research.py: replace only this
    # script's three sheets and keep every other one.
    wb = research_book.open_book(OUT)
    bold = Font(bold=True)
    fill = {"strong": PatternFill("solid", fgColor="C6EFCE"), "medium": PatternFill("solid", fgColor="FFEB9C"),
            "weak": PatternFill("solid", fgColor="F2F2F2")}

    ws = research_book.replace_sheet(wb, "tag suggestions")
    ws.append(SUGG_HEAD)
    for s in sugg:
        ws.append([s["name"], s["year"], s["type"], ", ".join(s["tags"]), s["tag"], s["strength"],
                   marks.get((s["name"], s["tag"])), s["evidence"], s["steam"]])
        if s["strength"] in fill:
            ws.cell(ws.max_row, 6).fill = fill[s["strength"]]
    dv = DataValidation(type="list", formula1='"yes,no"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f"G2:G{max(ws.max_row, 2)}")
    for col, w in zip("ABCDEFGHI", (34, 6, 11, 18, 14, 9, 7, 110, 50)):
        ws.column_dimensions[col].width = w

    ws2 = research_book.replace_sheet(wb, "new tag ideas")
    ws2.append(["Steam Theme", "Games", "Which games"])
    for n, gs in ideas:
        ws2.append([n, len(gs), ", ".join(sorted(gs, key=str.lower))])
    for col, w in zip("ABC", (22, 7, 160)):
        ws2.column_dimensions[col].width = w

    ws3 = research_book.replace_sheet(wb, "vocabulary")
    ws3.append(["Tag", "Games tagged", "…that the evidence finds", "Recall",
                "Suggestions", "…strong", "Steam tags used", "Store-text pattern"])
    for row in vocab:
        ws3.append(row)
    for col, w in zip("ABCDEFGH", (14, 8, 9, 7, 9, 7, 50, 80)):
        ws3.column_dimensions[col].width = w

    # Its own notes sheet: `about` belongs to research.py and covers every kind.
    ws4 = research_book.replace_sheet(wb, "tags about")
    with_page = sum(1 for g in games if pages.get(g["name"]))
    for line in [
        "Tag suggestions — written by `python3 tools/tag_research.py`. Nothing here is on the games sheet.",
        "",
        f"{len(games)} games; {with_page} with a Steam page read; "
        f"{sum(1 for g in games if not g['tags'])} carry no tag yet.",
        f"{len([s for s in sugg if s['strength'] == 'strong'])} strong, "
        f"{len([s for s in sugg if s['strength'] == 'medium'])} medium and "
        f"{len([s for s in sugg if s['strength'] == 'weak'])} weak suggestions.",
        "",
        "strong = a Steam tag in the page's top ten, or a Steam tag and the store text agreeing.",
        "medium = a Steam tag lower down the twenty Steam shows.",
        "weak = the developer's store text alone. Read the quoted sentence: \"skeleton crew\" is not undead.",
        "",
        "Owner column: write yes or no. It survives a rerun. A yes stays until you type the tag into the "
        "games sheet; a no keeps the row from coming back as new.",
        "Recall (vocabulary sheet) = of the games already carrying a tag, how many the evidence finds. "
        "A low one means the rule misses that theme; tell Claude and it can widen the rule.",
        "",
        "Rerun after adding games or tags: python3 tools/tag_research.py",
    ]:
        ws4.append([line])
    ws4.column_dimensions["A"].width = 130

    for sheet in (ws, ws2, ws3):
        for c in sheet[1]:
            c.font = bold
        sheet.freeze_panes = "A2"
        sheet.auto_filter.ref = sheet.dimensions
    for row in ws.iter_rows(min_row=2):
        row[7].alignment = Alignment(wrap_text=False)
    research_book.save(wb, OUT)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--write-only", action="store_true", help="use the cache only, no fetching")
    ap.add_argument("--stats", action="store_true", help="print the vocabulary table and write nothing")
    ap.add_argument("--threads", type=int, default=4)
    args = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    games = load_games()
    todo = [g for g in games if g["aid"]]
    pages = {}
    if args.write_only or args.stats:
        for g in todo:
            fn = os.path.join(CACHE, f"{g['aid']}.json")
            if os.path.exists(fn):
                pages[g["name"]] = json.load(open(fn, encoding="utf8"))
    else:
        fresh = sum(1 for g in todo if not os.path.exists(os.path.join(CACHE, f"{g['aid']}.json")))
        print(f"{len(todo)} games with a Steam page, {len(todo) - fresh} cached, {fresh} to fetch", flush=True)
        with cf.ThreadPoolExecutor(args.threads) as ex:
            for g, rec in zip(todo, ex.map(lambda g: store_page(g["aid"]), todo)):
                if rec:
                    pages[g["name"]] = rec
    sugg, vocab, ideas = analyse(games, pages)
    if args.stats:
        print("%-14s %6s %6s %6s %6s %6s" % ("tag", "tagged", "found", "recall", "sugg", "strong"))
        for r in vocab:
            print("%-14s %6s %6s %6s %6s %6s" % tuple(r[:6]))
        print(f"\n{len(sugg)} suggestions over {len({s['name'] for s in sugg})} games; "
              f"{len(ideas)} new-tag ideas")
        return
    write_book(games, pages, sugg, vocab, ideas)
    print(f"{len(pages)} pages read; {len(sugg)} suggestions over {len({s['name'] for s in sugg})} games, "
          f"{len(ideas)} new-tag ideas -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
