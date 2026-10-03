# Influence research — finding missing `connections` with first-hand sources

How to find influences the chart is missing, what counts as a source, and what
went wrong the first time so it doesn't again. The candidates found so far, with
quotes and links, are in `docs/influence-candidates.md`: the ones now in the sheet are ticked
✓ *on the chart*, and the rest are waiting for approval.

## The rules

1. **First-hand only.** The developer saying it: an interview where they answer
   in their own words, their devlog or blog, the store page they wrote, a Steam
   announcement, a forum post with the developer badge, or an in-game credit.
   A review, a wiki, a fan post or a journalist's summary is not a source.
2. **Nothing goes into the sheet until the owner has checked it.** The research
   produces a list of candidates. The owner ticks the ones they have verified,
   and only those become rows.
3. **Flag roguelikes the chart doesn't have.** When a developer names an
   influence that is itself a roguelike but isn't on the chart, list it under
   "Roguelikes you don't have" in `docs/influence-candidates.md` and tell the
   owner: it's a game they may want to add. Check the chart's full names first
   (IVAN is there as `Iter Vehemens Ad Necem`).
4. **Record denials too.** "I love Vampire Survivors, but no" (Ron Gilbert, on
   Death by Scrolling) stops someone adding that edge later on a reviewer's say-so.
   Denials live in section 3 of `docs/influence-candidates.md`.

## Where to look, and what each source was worth

Measured on the first pass (October 2026), over the 892 games on the chart:

| source | how | yield |
|---|---|---|
| Developer Steam announcements | `steam` subcommand: the Steam news API, `feedname == steam_community_announcements` only | **Best.** About 35 real edges out of 215 hits. Q&A posts and devlogs say "our main inspiration was…" outright |
| Steam store pages | same pass, `about_the_game` text | Good for "Inspired by: X, Y" lists and "From the creators of X" (a Dev/Series Relation) |
| Interviews and devlogs | web search per game, then read the page | Good for well-known games. Hades, Children of Morta, Crawl, Heat Signature and Death Road to Canada all came from here |
| Same developer | `samedev` subcommand | A lead, not a source. Use a pair only when the newer game's page says so |
| Steam discussion forums | `forums` then `devcheck` | **Poor and slow, but the badge makes it trustworthy.** 30 hits in the first 38 games, one from a developer. `devcheck` keeps only posts with Steam's developer badge. Run it last, on the games nothing else found |

**The degree-1 pass (October 2026)** went after the 335 games the map holds by a
single edge. Two things paid off. The `cues` read of the cached Steam pages
found the lineage that `steam` misses because it never says "inspired":
"from the creators of Despot's Game and Despotism 3K" (on Slime 3K's page, not
Despotism 3k's, which is why `cues` reads every page and keeps a hit when either
end is a leaf), "the same solo developer who brought you Luck be a Landlord",
"set in the same universe as its predecessors". Interviews worked for the
better-known sequels and spin-offs (Exit the Gungeon, Moonlighter 2, UnderMine,
Morbid Metal). For the rest, mostly survivors-likes and Balatro-likes, the
developer only ever names the one game the sheet already has: about 45 searched
by hand turned up new edges for five.

Most of the 80 games with no connections at all are small 2025–26 releases whose
developers never named an influence anywhere. Expect that, and don't lower the
bar to fill the gap.

## Running it

```bash
python3 tools/influence_research.py targets   # who to research
python3 tools/influence_research.py devs      # appid + developer for every game, ~6 min, cached
python3 tools/influence_research.py samedev   # same-studio leads
python3 tools/influence_research.py steam     # -> .influence_work/steam_triage.md, read every line
python3 tools/influence_research.py cues      # wider read of the same pages, for pairs touching a degree-1 game
python3 tools/influence_research.py lang      # each studio's own language; add --forums for subforums (~30 min)
python3 tools/influence_research.py forums    # ~1 h for the targets, English + the studio's language; resumable
python3 tools/influence_research.py devcheck  # opens each forum hit, keeps developer-badged posts
python3 tools/influence_research.py status    # which candidates are in the sheet now; --tick marks them
```

Everything goes into `.influence_work/` (gitignored). The `steam` pass caches
every page it fetches, so a rerun is fast.

**Developer badge.** On a Steam forum thread, a developer's reply has the CSS
class `commentthread_author_developer` on its author link. That's what
`devcheck` looks for, and it's what makes a forum post first-hand. It
confirmed Pluto's Roboquest reply on the Deadzone: Rogue forum.

**Resuming the forum scan.** It writes one line per game and skips games already
done. Its progress is saved in `tools/influence_research_forums.jsonl` (54 of the
130 no-influence games when it was paused). To pick it up:

```bash
mkdir -p .influence_work && cp tools/influence_research_forums.jsonl .influence_work/forums.jsonl
python3 tools/influence_research.py targets && python3 tools/influence_research.py devs
python3 tools/influence_research.py forums      # continues from game 55
```

Copy the file back into `tools/` before the session ends. A cloud container can
restart and take `.influence_work/` with it; that happened once mid-scan.

### Developers who don't work in English: search in their language

A studio from Japan, China, Korea, Germany, France, Poland and so on gives its
best interviews to its home press, and in its own language. An English-only
search finds the English reviewers' guesses and misses the developer. So for
any game whose developer is not English-speaking:

1. **Find out what language the studio works in.** `lang` does the first pass
   and writes `.influence_work/lang.json` with its evidence. The best evidence
   is the **developer's own writing**, and the Steam discussion forum is where
   it most often shows: developers reply to their home players in their own
   language, and studios open a subforum for them (日本語, 中文讨论区, 한국어).
   In order of strength:
   - the developer's posts: their Steam announcements, and forum replies
     carrying the developer badge (`devcheck` collects these, so rerun `lang`
     after it);
   - a subforum named for a language (`lang --forums` reads each forum index);
   - the developer's name in a non-Latin script.

   **Players' posts don't count.** Chinese and Russian players post on nearly
   every popular game's forum, so their thread titles say who plays a game, not
   who made it. A one-line developer post doesn't count either: Mimic Logic's
   studio posted 「中文版即将推出」 ("Chinese version coming soon"). That's
   a Japanese studio announcing a translation, and `lang` ignores posts under
   100 letters for that reason.

   Most developers post English on Steam even at home. Of the 130 no-influence
   games, the announcements alone identified only three non-English studios
   (Geometry Arena, Super Bullet Break, Auto Rogue), while Crown Trick, Skul and
   the rest were known only from outside. So after `lang`, also check the studio's
   website or Wikipedia page, and open the forum to look at what the badged
   developer writes.
2. **Find the game's native title.** Many games ship under a different name at
   home. Search under both, and under the studio's native name.
3. **Search in that language**, with these terms beside the title:

   | language | "inspired by" / "influenced by" / "interview" |
   |---|---|
   | Japanese | 影響を受けた, インスパイア, 参考にした, オマージュ, インタビュー, 開発者 |
   | Chinese (simplified / traditional) | 灵感来自 / 靈感來自, 受到…启发 / 啟發, 致敬, 参考, 采访 / 專訪, 开发者 |
   | Korean | 영감을 받은, 영향을 받은, 오마주, 인터뷰, 개발자 |
   | German | inspiriert von, beeinflusst von, Interview, Entwickler |
   | French | inspiré par, influencé par, entretien, interview, développeur |
   | Spanish / Portuguese | inspirado en / por, influenciado, entrevista, desarrollador / desenvolvedor |
   | Polish | inspirowany, inspiracja, wywiad, twórcy |
   | Russian | вдохновлён, вдохновение, влияние, интервью, разработчик |

4. **Look where that country's developers talk:** their own X/Twitter account
   (often in the native language even when the Steam page is English), note.com
   and 4Gamer / Famitsu / Game Watch for Japan, Bilibili, TapTap and Zhihu for
   China, Inven / This Is Game / Ruliweb for Korea, and the studio's own blog.
5. **Quote the original and translate it** in the candidate list, so the owner
   can check the translation against the source.

The `steam` pass already recognises these words in announcements (see `CLAIM`
in the script), but it only matches when the game's name is written in Latin
script. The `forums` pass searches each forum in English **and** in the language
`lang` found (`SEARCH_TERMS`). For a studio `lang` missed, set its entry in
`lang.json` by hand before running `forums`.

Among the games with no recorded influences, the studios to do this for first are: Crown Trick and Juicy
Realm (China), Skul, Magic Survival and Metallic Child (Korea), Super Bullet
Break, Million Depth and Auto Rogue (Japan).

### Everyone else

For interviews, web-search `"<game>" developer interview inspired`, then fetch
the page and find the actual quote. Never trust a search engine's summary of a
page: twice it attributed commenters' suggestions to the developer.

### X / Twitter

`xsources` reads every X/Twitter source the `connections` sheet cites and reports
who posted it, when, and whether the text names the influencer. x.com itself
gives anything not logged in an empty page, and profiles and timelines can't be
read, but the embed endpoints websites use (`cdn.syndication.twimg.com` and
`publish.twitter.com/oembed`) still return one tweet's text and author. A
deleted tweet comes back as a "tombstone", which the script reports.

That makes X good for **checking** a known tweet and poor for **finding** one.
Search engines index only some tweets, ignore quoted phrases, and mostly return
fans and news accounts. Searching x.com for ten unconnected games found nothing
first-hand. When a developer's handle is known, the useful move is to read the
specific tweets other sources link to.

The first check (82 rows) found every tweet still readable except one deleted,
almost all posted by the game's own account, and two posted by someone else (a
PR agency and a publisher). Those are listed in section 6 of
`docs/influence-candidates.md`.

## Traps

- **Game names that are ordinary words.** Rogue, Hack, Roll, Crawl, Haste,
  Rounds, Omega and others match patch notes ("Haste now affects…"), class names
  ("the Rogue class") and "Roll the dice". `AMBIGUOUS` in the script matches them
  case-sensitively; read the sentence anyway. "Crawl" in a sentence about
  *Dungeon Crawl Stone Soup* is not Powerhoof's Crawl.
- **Crossovers, bundles and sales** name other games constantly and say nothing
  about influence. `NOISE` drops most of them; a few get through.
- **Direction.** "X is inspired by Y" on Y's page can be Y advertising X. Read
  who wrote the sentence and which game it is about. Some posts are a publisher
  promoting a *different* game in its catalogue.
- **The sheet's own names.** A dev says "Binding of Isaac", the sheet has
  `The Binding of Isaac`. A dev says "Shiren the Wanderer", the sheet has a
  dozen Shiren entries. Pick the row deliberately and note it.
- **Feature-level claims.** "Inspired two of our relics" or "our pixel art took
  from Stoneshard" is real but small. They go in the "weaker" section for the
  owner to decide.
- **Journalist paraphrase.** "He also singles out Dead Cells" is the writer's
  words, not the developer's. Weaker section, labelled as such.
- **Steam rate limits.** The store and news APIs tolerate 8 parallel requests.
  The community forum search does not: it answers "too many requests" after a
  few quick hits. Use `--delay 15`.
- **Steam announcement links.** The news API's `gid` is not the id the store's
  news page uses, so `store.steampowered.com/news/app/<appid>/view/<gid>` opens
  to nothing. Follow the item's own `url` (`curl -sL -o /dev/null -w
  '%{url_effective}'`) and cite where it lands, a
  `steamcommunity.com/games/<appid>/announcements/detail/<id>` page. If it lands
  on the bare announcement list, the developer has removed the post. Say so, and
  point to the news feed, which still has its text.
- **Sites that block fetches.** Several interview sites return 403 to the web
  fetcher, and web.archive.org was unreachable from the cloud container. If the
  quote can't be read, it isn't a source yet. Leave it out and say why.

## Adding approved rows

Approved candidates go into the `connections` sheet: Influencer, Influencee,
Influencer Time (the influencer's year), Dev/Series Relation (`Yes` for
same-studio pairs), and the source URL. Edit through `tools/_xlsx_surgery.py`
like the `tools/_connections_*.py` one-shots (never by saving with openpyxl,
which drops the workbook's charts), then run `python3 tools/import-games-godot.py`.
`tools/_connections_stolen_realm_survivors.py` is the closest worked example.

The owner usually adds rows straight into the sheet, so afterwards bring the
candidate list up to date:

```bash
python3 tools/influence_research.py status          # what's in the sheet now, and any name it can't match
python3 tools/influence_research.py status --tick   # tick those lines ✓ on the chart
```

`status` matches the names on each `- [ ]` line against the sheet exactly. If
the owner added a row under a different name than the doc uses, it reports the
line as unmatched or open instead of guessing. That happens when the doc names a
series or a remake and the sheet names one game, for example "Shiren the
Wanderer" added as `Mystery Dungeon 2: Shiren the Wanderer`, or "Spelunky" added
as `Spelunky Classic`. Change the doc line to the row that was added, say so in
a note, and run it again.
