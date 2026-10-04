# Influence research — finding missing `connections` with first-hand sources

How to find influences the chart is missing, what counts as a source, and what
went wrong the first time so it doesn't again. The candidates found so far, with
quotes and links, are in `docs/influence-candidates.md`. It is laid out by what
the owner does next: lines to review (section 1 for games on the sheet, section
2 for games not added yet), what was checked and isn't an influence (3), rows
whose source needs a look (4), leads (5), what was searched without result (6),
and what is on the chart now (7). Videos and podcasts to listen to are in
`docs/influence-media.md` (see `media` below).

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
   "Roguelikes you don't have" (section 5 of `docs/influence-candidates.md`) and tell the
   owner: it's a game they may want to add. Check the chart's full names first
   (IVAN is there as `Iter Vehemens Ad Necem`).
4. **Record denials too.** "I love Vampire Survivors, but no" (Ron Gilbert, on
   Death by Scrolling) stops someone adding that edge later on a reviewer's say-so.
   Denials live in section 3 of `docs/influence-candidates.md`, with the
   things that looked like an influence and weren't.

## Where to look, and what each source was worth

Measured on the first pass (October 2026), over the 892 games on the chart:

| source | how | yield |
|---|---|---|
| Developer Steam announcements | `steam` subcommand: the Steam news API, `feedname == steam_community_announcements` only | **Best.** About 35 real edges out of 215 hits. Q&A posts and devlogs say "our main inspiration was…" outright |
| Steam store pages | same pass, `about_the_game` text | Good for "Inspired by: X, Y" lists and "From the creators of X" (a Dev/Series Relation) |
| Interviews and devlogs | web search per game, then read the page | Good for well-known games. Hades, Children of Morta, Crawl, Heat Signature and Death Road to Canada all came from here |
| Same developer | `samedev` subcommand | A lead, not a source. Use a pair only when the newer game's page says so |
| Steam discussion forums | `forums` then `devcheck` | **Poor and slow, but the badge makes it trustworthy.** 30 hits in the first 38 games, one from a developer. `devcheck` keeps only posts with Steam's developer badge. Run it last, on the games nothing else found |
| itch.io pages and devlogs | `itch` | Not measured yet. Aimed at the small games nothing else finds: a jam game's or a solo developer's itch page is often the only place they wrote about it. 4 of 8 well-known games tested were on itch under their exact title, and 2 of the 4 were someone else's upload, which is why each game's itch account is printed beside its Steam developer |
| Studio websites and press kits | `site` | Not measured yet. A press kit's History section is written by the studio for journalists. 6 of 8 tested had a site, and 3 a press page |
| Reddit | `reddit` | Not measured yet. Developer AMAs and "I made…" launch posts, plus r/roguelikedev (mostly Sharing Saturday). Read through the Arctic Shift archive, which rate-limits hard (see Traps) |
| Kickstarter campaigns | `kickstarter` | Not measured yet. A pitch says what it is like, often under an "Inspirations" heading. **Run it from your own computer**: Kickstarter refuses the cloud container |
| Roguelike Radio | `radio` | A listening list, not a source: 180 episodes since 2011, many with one game's developer as the guest. 43 chart games are named in an episode's title or notes |

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

**What the owner took from it (3 October 2026).** 20 of the degree-1 pass's
candidate pairs went into the sheet, plus the `Deat Road` typo fix: Exit the
Gungeon, Gnomes (three), Gordian Quest (two), Heavy Bullets, Let's! Revolution!
(two), Maze Mice, Moonlighter 2, Morbid Metal, Rabbit and Steel, Glyphica, five
survivors-likes on Slime 3K, and Enter the Gungeon on UnderMine. Three were
taken in a different shape than proposed, which is the normal case, not an
error: Spelunky went in as `Spelunky Classic`; UnderMine got Gungeon but not
Hades, from the same quote; and Dota Auto Chess → Slime 3K went in off the
store page's "a shop straight out of AutoChess", a feature-level line nobody
had written up. Despotism 3k → Slime 3K was left out, presumably because
Despotism 3k → Despot's Game → Slime 3K already carries the studio lineage.
The lines left open in section 1 are still open, not rejected.

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
python3 tools/influence_research.py wanted FILE  # games not on the chart yet (one name per line): sentences naming a chart game
python3 tools/influence_research.py lang      # each studio's own language; add --forums for subforums (~30 min)
python3 tools/influence_research.py forums    # ~1 h for the targets, English + the studio's language; resumable
python3 tools/influence_research.py devcheck  # opens each forum hit, keeps developer-badged posts
python3 tools/influence_research.py media     # interview videos + podcasts to listen to -> docs/influence-media.md
python3 tools/influence_research.py status    # which candidates are in the sheet now; --tick marks them
python3 tools/influence_research.py titles    # each game's Japanese/Chinese/Korean Steam title, ~20 min, cached; run before the scans
python3 tools/influence_research.py itch      # itch.io pages + devlogs -> .influence_work/itch.md
python3 tools/influence_research.py site      # studio websites + press kits -> .influence_work/site.md
python3 tools/influence_research.py reddit    # developer posts on Reddit + r/roguelikedev -> .influence_work/reddit.md
python3 tools/influence_research.py kickstarter  # campaign pages -> .influence_work/kickstarter.md; your machine only
python3 tools/influence_research.py radio     # Roguelike Radio episodes -> section 3 of docs/influence-media.md
```

**The four page scans** (`itch`, `site`, `reddit`, `kickstarter`) work alike.
Each reads the games with one connection or none by default (`--games few`;
`targets` and `all` also work), appends each game's raw pages to
`.influence_work/<scan>.jsonl` so a stopped run resumes, and writes
`<scan>.md`: every sentence that makes a claim beside another chart game's
name, for a pair the sheet doesn't have. `--write-only` rewrites the `.md`
from the cache, `--limit N` stops after N games. None of them proves who wrote
a page. Each line carries the account or site it came from: check it is the
developer before the quote goes in the candidate list.

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

### Interviews and podcasts: `media`

A developer often says what inspired them out loud and nowhere else: on a
podcast, in a showcase interview, on a YouTube channel that interviews indie
developers. Nobody can watch those but the owner, so `media` does the searching
and leaves the listening. For every game with `--max-degree` connections or
fewer (default 1), and every game whose connection has a placeholder Source
(`check folder`, `look at it`, a note about a Discord), it searches:

- **YouTube**, `"<game>" developer interview` and `"<game>" podcast`, read
  straight off the results page (no API key);
- **Apple Podcasts**, the iTunes Search API's episode search (no key, about 20
  calls a minute, hence `--delay 3.5` and a run of over half an hour).

It keeps a result only when the game is in the title (or right beside a cue in
the description) AND it reads like the developer talking: interview, Q&A, AMA,
postmortem, GDC, devlog, "joined by", "sits down with", or the developer's own
studio name (from `devs`, which is optional but helps a lot). It drops Let's
Plays, reviews, trailers, numbered episodes of a playthrough, roundup episodes
that list five games, and shows that only share the game's name. Raw results
are cached in `.influence_work/media.jsonl`, so `media --write-only` rewrites
the doc after a filter change without searching again, and a stopped run
resumes where it was.

The output is `docs/influence-media.md`: section 1 is the suspected
connections, each with **"Listen for: X (sheet says 'look at it')"**, and
section 2 is games held on by one connection or none. When a video confirms
an influence, the video is the Source, with a timestamp if possible
(`&t=754`). A podcast host's guess is not; the developer has to say it.

**Resuming it.** The first run was stopped at 158 of 512 games (fewest
connections first: all 61 games with none, and the one-connection games
alphabetically up to Elin).
Its results are saved, trimmed, in `tools/influence_research_media.jsonl`,
because `.influence_work/` doesn't survive a container restart. To continue:

```bash
mkdir -p .influence_work && cp tools/influence_research_media.jsonl .influence_work/media.jsonl
python3 tools/influence_research.py devs     # optional, ~6 min: studio names sharpen the filter
python3 tools/influence_research.py media    # skips the 158, ~30 min for the rest
```

Then copy `.influence_work/media.jsonl` back over the file in `tools/`
before committing. Ticks in `docs/influence-media.md` are kept across
rewrites (matched by URL), so listen and tick at any point.

**Roguelike Radio** is section 3 of the same doc, written by `radio`, which
reads the show's whole archive in two requests. An episode is listed under
every chart game its title or show notes name. `media` keeps section 3 when it
rewrites the doc, and `radio` keeps sections 1 and 2.

What it misses: interviews titled only with the developer's name ("Episode
40: Matt Glanville") unless the description names the game, and anything not
in English or not on YouTube or Apple Podcasts. The cues include
Japanese/Korean/Chinese/Spanish/Polish/Russian words for "interview", but the
searches are English.

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
in the script). **Run `titles` first so it can see the game names too.** It
asks Steam for every game's page in Japanese, Chinese and Korean and keeps the
localised title when it is in that script (Crown Trick is 不思议的皇冠,
Super Bullet Break is スーパーバレットブレイク). From then on `steam`, `cues`,
`wanted`, `forums`, the page scans and `radio` match a game by either name.
Before it, a Japanese announcement naming 風来のシレン matched nothing. Two
limits: a title shared by several games (不思議のダンジョン, the whole series)
is dropped, because it can't say which game is meant, and runs of under three
letters are dropped, because Skul's 小骨 is also just the words "small bone".
Sentences are now split at 。！？ as well, since Japanese and Chinese put no space
after a full stop. Before that, a whole CJK post counted as one "sentence", and
it was too long to be read at all. The `forums` pass searches each forum in English **and** in the language
`lang` found (`SEARCH_TERMS`). For a studio `lang` missed, set its entry in
`lang.json` by hand before running `forums`.

Among the games with no recorded influences, the studios to do this for first are: Crown Trick and Juicy
Realm (China), Skul, Magic Survival and Metallic Child (Korea), Super Bullet
Break, Million Depth and Auto Rogue (Japan).

### Everyone else

For interviews, web-search `"<game>" developer interview inspired`, then fetch
the page and find the actual quote. Never trust a search engine's summary of a
page: twice it attributed commenters' suggestions to the developer, and once
it credited Warriors: Abyss's producer with naming Hades II and Vampire
Survivors, which the interview it cited never says.

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
PR agency and a publisher). Those are listed in section 4 of
`docs/influence-candidates.md`.

### Proof screenshots: `tools/capture_proof.js`

The game's choice popup shows the Source of the connection you would walk, and
under it a screenshot of the proof: the developer's own sentence on the linked
page, highlighted. `capture_proof.js` makes those. For each connection with a
link it opens the page in headless Chromium, finds the sentence (the URL's
`#:~:text=` fragment when there is one, otherwise a claim sentence naming the
influencer, the earliest one on a tie), highlights it and crops around it.

```bash
export NODE_PATH=/opt/node-tools/node_modules     # cloud container; locally, npm install playwright
node tools/capture_proof.js --pilot              # 25 across every source kind, to check a change
node tools/capture_proof.js --skip youtube,podcast --resume   # the full run, ~6 s a link
node tools/capture_proof.js --only <game id>     # retry one game's connections
node tools/capture_proof.js --kind reddit        # Reddit only; run it from your own computer (below)
node tools/capture_proof.js --export             # copy them into images2.0/proof/ for the game
```

Results go to `.influence_work/proof/` with `report.json`, which records every
connection tried and why one failed (`blocked` with the HTTP status, `no-match`
with a screenshot of what the browser was shown). How each kind is handled:
X through the official embed; Steam with its age gate pre-answered; Reddit
through old.reddit.com, which shows the whole thread, comments included.

**Reddit has to be captured from a home connection.** Reddit blocks cloud
addresses outright ("You've been blocked by network security"), so from the
cloud container only the embed host works, and it renders a post but never its
comments, where the developer's word usually is. Those connections come back
`blocked`, with a note saying to run them at home. On your own computer, from
the repo root:

```bash
npm install playwright && npx playwright install chromium
node tools/capture_proof.js --kind reddit
node tools/capture_proof.js --export
```

then commit `images2.0/proof/`. The export there only adds and replaces Reddit
proofs: it deletes a game file only for a connection it KNOWS failed or that left
the sheet, never one its (Reddit-only) report doesn't mention. Videos and podcasts are
the owner's to source by hand (a YouTube clip can't be downloaded within its
terms), so `--skip youtube,podcast` leaves them out.

**One name format for every proof.** The game reads one PNG per connection
(PNG is the owner's call), named by the two games' ids, influencer first,
joined by a hyphen: `slay_the_spire-tic_tactic.png`. An id is a game's file name
in `data/games/` without `.tres`; ids are only lower-case letters, digits and
underscores, so the hyphen splits a name one way only. A screenshot that proves
several connections is saved once under each: one image naming Hades, Isaac,
Gungeon and Spelunky as Going Under's influences is four files.

**Adding your own.** Drop a screenshot into `images2.0/proof/` named that way and
you're done. Or drop it in under any name ("tic tactic sts.png", "going under
hades, isaac, gungeon, spelunky.png") and run `python3
tools/proof_owner_match.py`: it proposes the connection(s) each name means and
lists what it couldn't place; `--write` renames them into place (one copy per
connection). For a name it can't read, `--pair "file.png" slay_the_spire
tic_tactic` (ids or game names). It also flags a file in the id format whose ids
aren't a connection on the sheet, and so does the test suite
(`test_every_proof_is_named_for_a_real_connection`), so a typo can't ship
silently.

**Your screenshots win.** `tools/proof_captured.json` lists the files
`capture_proof.js --export` copied in, each with a sha1 of its bytes, and an
export only ever replaces or deletes a file still listed with that sha1.
Anything else in the folder is yours, including a captured file you uploaded
over: its bytes no longer match, so it drops off the list and is yours from
then on.

Two uploads prove connections the sheet doesn't have yet (Brotato → Bounty of
One, Enter the Gungeon → Dungreed). They wait, already named, in
`images2.0/proof/not-on-sheet/`: move them up a folder once their rows exist.

The script picks a sentence, it doesn't judge one. **Look at the images**: the
pilot found a source that undercuts its own row (Rogue Voltage, section 4 of
`docs/influence-candidates.md`), and a status of `ok` only means a sentence
naming the game was found.

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
- **Arctic Shift's rate limit.** The Reddit archive answers HTTP 422 "Timeout.
  Maybe slow down a bit" both when a search really runs out of time and when
  it is rate-limiting you, and from the cloud container it rate-limited after
  a dozen quick requests and stayed that way for over half an hour. `reddit`
  waits and retries, and after five minutes of refusals on one search it
  stops rather than spend ~45 minutes a game recording nothing. The games done
  so far are saved and a rerun resumes. A run is about nine searches a game:
  use `--delay 6` or more, and run it from your own computer if the container
  is being throttled.
- **Names in other spellings.** A space, a colon and a dash between words now
  count as the same, because people write "Dungeon Crawl: Stone Soup" for the
  sheet's `Dungeon Crawl Stone Soup`. A name found only inside a longer chart
  name doesn't count either ("Crawl" in "Dungeon Crawl", "Omega" in "Omega
  Labyrinth"). Both rules apply to every scan.
- **Sites that block fetches.** Several interview sites return 403 to the web
  fetcher, and web.archive.org was unreachable from the cloud container. If the
  quote can't be read, it isn't a source yet. Leave it out and say why.

## Sequels

The owner's rule: **a sequel only gets an influence its predecessor doesn't
already have.** If Strange Adventures in Infinite Space is on the sheet as an
influence on Weird Worlds, a quote saying it also shaped Infinite Space III adds
nothing, because the series edge already carries it. Check the earlier game's
influences before listing one for a sequel, and when an interview is about a
series, put the edge on the first game it applies to. The sequel's own new
influences (Hades on Moonlighter 2, which Moonlighter never had) are the ones
worth listing.

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
python3 tools/influence_research.py status --tick   # tick them and move them to section 7
```

`status` matches the names on each `- [ ]` line against the sheet exactly, and
only the pairs **before the line's ` — `**. Everything after the dash is the
quote, and a `same as **A → B**` cross-reference there is not part of the line:
until that rule, the five Slime 3K lines stayed open after the owner added them,
because the Despotism 3k pair they point at was left out on purpose. So keep a
line's own pairs in front of the dash. If
the owner added a row under a different name than the doc uses, it reports the
line as unmatched or open instead of guessing. That happens when the doc names a
series or a remake and the sheet names one game, for example "Shiren the
Wanderer" added as `Mystery Dungeon 2: Shiren the Wanderer`, or "Spelunky" added
as `Spelunky Classic`. Change the doc line to the row that was added, say so in
a note, and run it again. Lines in section 2 name games that aren't on the
sheet yet, so `status` lists them as waiting for their game row instead.

When adding new findings, put each line in section 1 or 2 under Strong or
Weaker, in its sorted place (by the game that gets the connection). Write every
line so it stands alone: a second pair from the same quote says `same quote as
**A → B**` rather than just `same`, because `--tick` moves lines one at a time.
