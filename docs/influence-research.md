# Influence research — finding missing `connections` with first-hand sources

How to find influences the chart is missing, what counts as a source, and what
went wrong the first time so it doesn't again. This is the `connections` kind
of the project's research ([research.md](research.md) covers all eight). The
candidates found so far, with quotes and links, are rows in
`research/connections.csv`, reviewed by the owner in the `connections` sheet of
`tools/Research.xlsx`. Each row's `Status` says what the owner does next:
`to review` (a pair of games on the sheet), `waiting for game row` (a game not
added yet), `not an influence` (checked, and no), `source check` (a row already
on the sheet whose source needs a look), `lead`, `nothing found` (searched
without result) and `on sheet`. Until October 2026 these were sections 1–7 of a
markdown doc, `docs/influence-candidates.md`; `tools/_research_migrate.py` moved
every line into a row word for word, and the doc's research log is now the
last section here. Videos and podcasts to listen to are in
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
   a `lead` row of `research/connections.csv` (Heading "Roguelikes you don't have") and tell the
   owner: it's a game they may want to add. Check the chart's full names first
   (IVAN is there as `Iter Vehemens Ad Necem`).
4. **Record denials too.** "I love Vampire Survivors, but no" (Ron Gilbert, on
   Death by Scrolling) stops someone adding that edge later on a reviewer's say-so.
   Denials are `not an influence` rows of `research/connections.csv`, with the
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
| Bluesky | `bluesky`: the studio's own account (matched by the Steam developer's name), read back through posts and replies, plus a post search | **Measured once, thin but real.** Over the 386 games with one connection or none: 63 lines, one strong find (Mumpitz Games naming four chart games for Sir, We Have an Orc Problem). Most lines are publishers plugging other games, and fan accounts that share a studio's name. Uses `api.bsky.app`: `public.api.bsky.app` answers 403 from the cloud container |
| Substack | `substack`: Substack's own search, public posts read in full | **Nothing first-hand** over the same 386 games: every hit was a journalist or newsletter writing about the game |
| Patreon | `patreon`: finds the campaign only | **Can't be read from here**: the API returns post text empty without a login and post pages answer 403. About 13 real developer pages among 124 name matches, listed in section 5 of the candidates doc |
| Video captions | `transcripts`, **your computer only** | Not measured yet. Reads the media doc's videos for every chart game said, with a timestamped link |
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

**The two-connection pass (October 2026)** went after the 213 games the map
holds by two edges (140 when it started; new rows lifted the rest from one).
All got the automated passes; the 113 never searched by hand then got a hand
search in batches: every source their rows already cite reread for any chart
game (Reddit threads through the Arctic Shift archive, which answered with a
`User-Agent` header and refused Python's default), the Steam page, and a web
search. Yield: three strong lines (Isaac → Tape to Tape, FTL and Hades →
Beyond the Long Night, Desktop Dungeons → I Am Overburdened) and about a dozen
weaker ones, most of them one feature (Noita's spell system behind Sephiria's
inventory). As useful were the rows whose cited source turned out not to say
it: Road Not Taken's FTL and Don't Starve come from Wikipedia paraphrasing a
pitch, Synthetik: Legion Rising's Risk of Rain isn't in the AMA it cites, and
I Am Overburdened's two RogueBasin rows aren't what its developer names.
Small games behave like the degree-1 survivors-likes did: the developer names
the one or two games the sheet already has, and nothing else.

**The four-connection pass (October 2026)** began with the 33 of 63 games
never named in the candidates doc. Rereading cited sources and scanning every
developer post on each Steam page turned up one strong line (Skul → Dunjungle,
which the Steam scan missed at first because it matched full titles only:
developers write "Skul", not "Skul: The Hero Slayer", so match the part before
the colon too) and two weaker ones. As at three connections, the bigger yield
was in the rows themselves: a store page that sources three Ouroboros King rows
better than the Reddit post they cite, and a same-studio row (StarVaders →
Dicevaders) with no Source and no Dev/Series mark.
The second batch (the other 30) added two strong lines, both from developers'
replies deep in Reddit threads the sheet already cited (Into the Breach → Lost
For Swords, Diablo → Tangledeep). It also found a bug worth knowing about: the
Arctic Shift `comments/tree` endpoint nests replies under
`data.replies.data.children`, and a walk that only reads the top level sees
none of a developer's answers in an AMA. Walk the whole tree.

**The five-connection pass (October 2026)** covered all 29 such games and gave
the best yield of the degree passes: eight lines, four of them on one game.
Dungeons of Dredmor's only recorded influence was RogueBasin's NetHack, yet
its lead developer had named four chart games in a single 2011 interview
answer. Old, well-known games whose rows lean on RogueBasin are worth a direct
search for the developers' own words; the wiki infobox often isn't where they
said it.

**The wiki-sourced rows (October 2026).** 88 rows cite only RogueBasin or
Wikipedia; the 63 not already discussed were searched for the developer's own
words, in three batches. About two thirds now have one, most often in a place
nobody had looked: the game's own README, changelog or manual (Angband's
version history, Sil's changelog, Linley Henzell's 1997 manual, Larn's 1986
README, IVAN's design notes in its CVS source), and four turned out to be code
forks that want `Yes` under Dev/Series Relation. Two things are worth reusing.
**RogueBasin's page history says who typed an infobox line** (the MediaWiki API,
`api.php?action=query&prop=revisions&rvprop=user|timestamp|content&rvdir=newer`;
WebFetch gets 403, curl works), and for ten rows it was the developer's own
account, which makes the wiki line first-hand. **Wikipedia's citation doesn't
always say what Wikipedia says**: Rogue Legacy's Spelunky and Isaac, Luck be a
Landlord's Slay the Spire and Backpack Hero's two rows rest on articles that
never quote the developer on it. Several 2014–16 developers said "Spelunky",
which by then meant HD (the chart's `Spelunky`), not `Spelunky Classic`.

Most of the 80 games with no connections at all are small 2025–26 releases whose
developers never named an influence anywhere. Expect that, and don't lower the
bar to fill the gap.

## Running it

```bash
python3 tools/influence_research.py new       # the games added since the last pass: every scan below that works from here
python3 tools/influence_research.py new --mark  # ...once their findings are rows in research/connections.csv
python3 tools/influence_research.py status --tick  # rows the owner has added to the sheet -> `on sheet`
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
python3 tools/influence_research.py bluesky   # studios' own Bluesky accounts + a post search -> .influence_work/bluesky.md
python3 tools/influence_research.py substack  # Substack posts naming the game -> .influence_work/substack.md
python3 tools/influence_research.py patreon   # which studios have a Patreon (text needs a login) -> .influence_work/patreon.md
python3 tools/influence_research.py transcripts  # captions of the media doc's videos -> transcripts.md; your machine only
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

### New games: `new`

Every game the owner adds gets researched, without anyone having to ask.
`research/ledger.json` (checked in, shared by every kind of research; this is
its `connections` entry) holds the date each game was researched; the 899 that were on the chart before it existed say
`before 2026-10-07`, which the passes above covered. A game on the sheet and
not in it is new, and `import-games-godot.py` lists those after every import.

`new` runs, over just those games: `devs` (for the whole catalog, so the
same-studio check has something to compare against; cached after the first
run), their Steam store text and developer announcements, `itch`, `site`,
`reddit`, `bluesky`, and `media` (YouTube; Apple Podcasts only if it answers,
which it doesn't from the cloud: those rows are cached with an error so a run
at home redoes them). `media` also folds the new games into
`docs/influence-media.md` and its cache back into `tools/`, exactly as a full
`media` run does. One source refusing (Arctic Shift throttles hard) stops that
source only. Then it writes `.influence_work/new_games.md`, one section per
game:

- every first-hand sentence naming a chart game it isn't connected to;
- **influence claims that name no chart game**: the developer's "inspired by"
  lines about games off the chart, which is where a roguelike the chart lacks
  shows up (rule 3), and where non-roguelike influences show the trail is cold;
- same-studio games on the chart, and whether they are connected;
- other chart games' cached Steam text naming it (only if `steam` has run);
- videos and podcasts to listen to;
- search links for the hand half.

The hand half is the part that usually pays: a web search per game for an
interview, a devlog or a press release. The October 2026 batch shows why: the
scans found nothing first-hand for most of the eighteen, while a Japanese
interview gave Lumencraft's whole influence list. Write up what holds up as
rows in `research/connections.csv` (`to review` for a pair of chart games, `lead`
for a roguelike the chart lacks, `nothing found` for a game searched with
nothing found), then `new --mark`.

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

**It has searched everything it qualifies for.** The first run stopped at 158
of 512 games; the second (October 2026) finished the other 350, with `devs`
run first so studio names sharpened the filter: 508 games searched, 275 with
something to listen to (111 suspected connections to confirm, 164 games with
few connections). Rewritten against the sheet after the owner's October 2026
upload: 506 games qualify, all searched, 272 with something to listen to (108
to confirm, 164 with few connections). Elewar, Keeper's Toll and Rogue Lords
dropped out of section 1 because their rows have real links now, and Rogue
Blight came in with two interviews with its developer. **Rewrite it with
`devs` run first**: `devs.json` lives in `.influence_work/` and isn't saved,
and without studio names the same cache drops to about 240 games. The results are saved in `tools/influence_research_media.jsonl`
(13 MB, each result's text cut to 400 characters), because `.influence_work/`
doesn't survive a container restart. To rewrite the doc after a filter change,
or to search games added to the sheet since:

```bash
mkdir -p .influence_work && cp tools/influence_research_media.jsonl .influence_work/media.jsonl
python3 tools/influence_research.py media --write-only   # just rewrite the doc
python3 tools/influence_research.py media                # search only games not in the cache
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

### Reading the interviews instead of listening: `transcripts` (your computer)

`media` finds the interviews; `transcripts` reads them. For every unticked
video in `docs/influence-media.md` it fetches the captions (manual English if
there are any, else YouTube's auto-captions in the video's own language, so a
German interview's game names survive), finds every chart game said in them,
and writes `.influence_work/transcripts.md`: each game a video names, a link
that starts the video at that moment (`&t=754`), and the words around it, with
the moments near influence words ("inspired", "loved", "based on", "fans of")
listed first. A pair already on the sheet is marked, because a clip of that
moment is the proof it is missing. **It finds places to listen, not sources**:
auto-captions mishear names, and naming a game isn't saying it shaped yours.
The clip you cut from the moment is the proof, as before.

**It only runs on your own computer.** From the cloud container YouTube answers
"Sign in to confirm you're not a bot", and the caption mirrors (Invidious,
Piped, youtubetranscript.com) are refused the same way.

```bash
pip install yt-dlp
python3 tools/influence_research.py transcripts --limit 20        # try a few first
python3 tools/influence_research.py transcripts --cookies-from-browser firefox  # if YouTube asks you to sign in
python3 tools/influence_research.py transcripts --game "Rogue Blight"           # one game's videos
```

Transcripts are cached in `.influence_work/transcripts.jsonl` and a rerun
resumes; `--write-only` rewrites the `.md` from it. `--include-heard` reads the
ticked lines too.

**Podcasts** need speech-to-text: `pip install faster-whisper`, then add
`--podcasts`. It downloads each episode (Apple Podcasts via the iTunes lookup,
Roguelike Radio from the post's mp3 link), transcribes it on your CPU and
deletes the audio. The `small` model takes very roughly ten to twenty minutes
per hour of audio, and section 1 alone is about 300 episodes, so point it at
games with `--game` or cap it with `--limit`. `--model base` is faster and
mishears more names.

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
PR agency and a publisher). Those are `source check` rows of
`research/connections.csv`.

### Proof screenshots: `tools/capture_proof.js`

The game's choice popup shows the Source of the connection you would walk, and
under it a screenshot of the proof: the developer's own sentence on the linked
page, highlighted. `capture_proof.js` makes those. For each connection with a
link it opens the page in headless Chromium, finds the sentence (the URL's
`#:~:text=` fragment when there is one, otherwise a claim sentence naming the
influencer, the earliest one on a tie), highlights it and crops around it.

**What the crop shows**, the first of these that fits in 900px:

1. the whole **message** the sentence is in: a Steam forum post with its author
   and date, a Reddit comment, a quoted post. A reply that quotes the developer
   (or Steam's pinned "Answer" box) loses a tie to the developer's own post, and
   a player's post loses one to a post carrying Steam's `[developer]` badge.
   **A question comes with its answer**: when the sentence is a player's
   question ("do the hero position on party work like darkest dungeon?"), the
   developer's first reply after it is shot too and stacked under it; when it is
   the developer's answer, the post the link points at (`#c<id>`), or the nearest
   earlier question naming either game, is stacked above it;
2. the whole **paragraph**: the `<p>`, or the run between two blank lines when
   the page is one block split by `<br>`s (Steam store pages and forum posts
   are). A one-line paragraph takes its neighbours with it, up to 400px;
3. the sentence with a few lines either side.

The shot is taken in the viewport after the page has stopped moving, not off a
full-page screenshot: Playwright's full-page mode resizes the viewport, Steam's
store re-lays itself out, and the old crop landed on the "More like this"
carousel. **Before the shot, everything that covered a proof once is cleared**:
log-in walls and the translucent veil behind them go (Facebook's "See more on
Facebook" sat over Anomaly Collapse's post and greyed out Dungeon Clawler's
reel); "Read more" / "See more" buttons that unfold in place are pressed (a link
reading "read more" goes elsewhere, so it is left alone); every fixed or sticky
bar is hidden whatever its size, site headers included (Game*Spark's menu sat
over the line naming Inscryption, from a 0px-tall sticky wrapper that the old
"shoot below the header" measurement never saw); and a video playing under a
caption is hidden, so a frame can't bury the words. A long X post (cut at "Show more" in the
embed) is rendered in full, its text read from `api.fxtwitter.com` and handed to
X's own embed. A name of three words or more is also found by its initials in
capitals (ADOM, DCSS, FTL). A passage marked in the URL (`#:~:text=`) can run over
several paragraphs and is framed whole, and its prefix picks the post out from a
page title repeating the same words. Names a page writes differently go in
`ALIASES` in the script ("Faster Than Light" for FTL), and a hyphen inside a
name is optional ("Bumbo"). A short name in capitals counts too ("FTL"), and so does
the part after a colon ("Shiren the Wanderer"). A `weak` page match, where only
the influenced game is named, stays in `.influence_work/proof/` for a look but
is not exported; it is listed in `docs/proof-missing.md` instead. A weak tweet
is still exported, because the picture is the whole post and the name the check
missed is usually in it ("Isaac"). If the post has a picture, it is shown,
since that is often where the name is. `--status weak,no-match` retries only the
connections the report last left in those states.

```bash
export NODE_PATH=/opt/node-tools/node_modules     # cloud container; locally, npm install playwright
node tools/capture_proof.js --pilot              # 25 across every source kind, to check a change
node tools/capture_proof.js --skip youtube,podcast --jobs 3   # the full run, three at a time
node tools/capture_proof.js --only <game id>     # retry one game's connections
node tools/capture_proof.js --conn hades---going_under,balatro---runeborn   # exactly these
node tools/capture_proof.js --kind reddit        # Reddit only
node tools/capture_proof.js --export             # copy them into images2.0/proof/ for the game
node tools/capture_proof.js --translate          # set tools/proof_translations.json under its proofs
```

`--jobs` beyond the machine's core count is slower, not faster: each job is a
Chromium, and four cores with five jobs ran at a load of 12.

Results go to `.influence_work/proof/` with `report.json`, which records every
connection tried and why one failed (`blocked` with the HTTP status, `no-match`
with a screenshot of what the browser was shown). How each kind is handled:
X through the official embed; Steam with its age gate pre-answered.

**Reddit is captured through its embed, steered by an archive.** Reddit refuses
cloud addresses on reddit.com and old.reddit.com ("You've been blocked by network
security"), but answers on embed.reddit.com, the host it serves to other
websites. That host renders one post (folded under "Read more", which is
pressed) or one comment, never a thread. So the thread is read from the
[Arctic Shift](https://arctic-shift.photon-reddit.com) archive of Reddit, which
says WHICH post or comment says it (the same scoring as a page, with the
original poster, usually the developer, ahead of a commenter at a tie), and the
picture is Reddit's own embed of exactly that one. A comment comes with the
comment it answers stacked above it, and a player's question with the original
poster's reply stacked below it: Balatro → Runeborn is "how are you planning to
stand out?" and then "we were heavily inspired by Balatro". What this can't
capture, and `docs/proof-missing.md` lists for you: a video or picture post (the
embed shows no text for those), a comment removed or edited since it was
archived, and a thread the archive never saw.

The export deletes a game file only for a connection it KNOWS failed or that
left the sheet, never one its report doesn't mention, so a run of one kind
(`--kind reddit`) can't wipe the rest. Videos and podcasts are the owner's to
source by hand (a YouTube clip can't be downloaded within its terms), so
`--skip youtube,podcast` leaves them out.

**A proof in another language keeps its original**, with an English translation
set in a box underneath. The translations live in `tools/proof_translations.json`
(`"brotato---cluckmech_oasis.png": {"from": "Chinese", "text": "…"}`), and
`--translate` sets them; `--export` runs it too, so a re-captured proof gets its
translation back. Each entry keeps the fingerprint of its finished picture, so
running it twice changes nothing, and a picture replaced since (a fresh capture,
or one you uploaded) gets its translation set under it again.

**One name format for every proof.** The game reads one PNG per connection
(PNG is the owner's call), named by the two games' ids, influencer first,
joined by three hyphens: `slay_the_spire---tic_tactic.png`. An id is a game's file name
in `data/games/` without `.tres`; ids are only lower-case letters, digits and
underscores, so the hyphens split a name one way only. A screenshot that proves
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

**A clip instead of a screenshot.** When the proof is a developer SAYING it — a
stream, a podcast — drop the video in as `<influencer id>---<influenced id>.mp4`
and run `python3 tools/convert_proof_videos.py`. Godot plays only Ogg Theora, so
the script writes `<pair>.ogv` (capped at 720p) and `<pair>.poster.jpg` (a frame a
quarter of the way in) beside the MP4, which stays as the source and is not
shipped. In the game the proof slot shows the poster with a ▶, and a click plays
the clip over the popup, sound and all (click it to pause, click outside it, ✕ or
Esc to close). A clip wins over a screenshot of the same connection. The script
keys its outputs to each MP4's sha1 (`tools/proof_videos.json`), so a re-run only
converts what is new or replaced; CI runs `--check`, and
`test_every_proof_clip_has_its_playable_video_and_poster` fails on a clip that
was pushed without it. Name the file with the game's id, not its name: an
apostrophe or an accent becomes `_` (`don_t_starve_together`, `pok_rogue`).

**Seeing it on the sheet.** Two columns on the `connections` sheet. `Proof`
(F) holds every row's proof file name without the extension
(`slay_the_spire---tic_tactic`), whether or not the file exists yet, so a new
screenshot can be saved under a name copied straight out of the cell.
`Needs Proof` (G) says `Yes` when the row has no proof in the folder and isn't
a Dev/Series row, `No` otherwise; filtering it for `Yes` is the to-do list
(`docs/proof-missing.md` is the same list plus the Dev/Series rows, grouped by
why each is missing). Dev/Series rows never need a proof, though one can be
added anyway. Both are written FROM the folder by
`python3 tools/proof_column.py` (`--check` says whether they are stale) and
nothing reads them back, so re-run that after adding proofs rather than typing
into them.
A name typed there by hand is not checked against anything: the October 2026
upload typed `…---sepheria` for Sephiria and `…_dungeon_master` for Legend of
Keepers (the game is "Dungeon *Manager*"), and the files carried the same typos,
so nothing in the game would have shown them. Upload under any name and let
`proof_owner_match.py` and `proof_column.py` write the ids.

**Upload into `images2.0/proof/` itself, not a subfolder.** The game looks in
that folder only, and so do `proof_owner_match.py`, `proof_column.py` and the
test above, so a file in a subfolder (`proof temp/`, say) is invisible to all of
them: no proof in the game, and no warning either. `not-on-sheet/` below is the
one subfolder on purpose.

**`docs/proof-missing.md` is regenerated from a local file.** `capture_proof.js
--missing` reads `.influence_work/proof/report.json`, which a capture run writes
and git doesn't keep, so in a fresh checkout it fails until `--untried` or a full
run has rebuilt it. Between runs, removing the lines for connections that have a
proof now (and fixing the section counts) gives the same document.

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
pilot found a source that undercuts its own row (Rogue Voltage, a
`source check` row of `research/connections.csv`), and a status of `ok` only means a sentence
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
- **Apple Podcasts from the cloud container.** In October 2026 the iTunes
  Search API answered 403 to every request from the container, and `media` sat
  waiting on it. YouTube still answered. The two new games were searched on
  YouTube alone and cached with an `err`, so a `media` run from your own
  computer redoes them with podcasts included.
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

## Research log

What each pass covered, moved here from the old candidates doc when the candidates moved to `research/connections.csv`.

- **First passes**: games with no connections and no recorded influences (the strong and weaker leads that opened this list), then about 45 best-known games with only one recorded influence, in five passes.
- **Steam forum scan**: paused at 54 of the 130 no-influence games; progress is in `tools/influence_research_forums.jsonl`. It found one developer post (Roboquest → Deadzone: Rogue, now on the chart). The other forum matches were players' suggestions and guesses.
- **Native-language pass**: studios that don't work in English, searched in their own language (Japanese, Korean, Chinese, Russian).
- **Degree-1 pass (October 2026)**: the 335 games the map holds by a single connection, through their Steam pages and `cues`, plus about 45 hand searches.
- **Owned pass (October 2026)**: every owned game with no connection or one, by hand.
- **Your wanted list (October 2026)**: 84 games not on the sheet yet, all by hand.
- **Early classics (October 2026)**: 19 pre-2010 games with no recorded influence or one, by hand. Three new edges (GearHead, Shiren, Omega), two weaker, and first-hand sources for four rows sourced to wikis.
- **Early classics, second round (October 2026)**: 20 more, 1990s console roguelikes and 2010–14 indies with no recorded influence. Three new edges on Cardinal Quest and one on Baroque, plus first-hand sources for Rogue → ToeJam & Earl, Rogue → Torneko (in English) and Torneko → Baroque.
- **2015–17 round (October 2026)**: 15 influential games from 2015–17 with few recorded influences, Darkest Dungeon first. Thin: their developers mostly name games off the chart (X-Com, Dark Souls, Super Metroid, Magic) or confirm rows already on the sheet. One weaker pair (In Celebration of Violence) from a publisher's announcement.
- **Four connections, first batch (October 2026)**: 33 games never named here. One strong line (Skul → Dunjungle), two weaker, source fixes for three Ouroboros King rows and Dicevaders.
- **Four connections, second batch (October 2026)**: the other 30. Two strong lines (Into the Breach → Lost For Swords, Diablo → Tangledeep), one weaker, and first-hand sources for five rows. The Reddit reread now walks reply trees.
- **Five connections (October 2026)**: all 29. Four strong lines on Dungeons of Dredmor, two on GoNNER, one on Order Automatica, and Hoplite in Fights in Tight Spaces' pitch (weaker).
- **Six connections (October 2026)**: all 15. Nova Drift → 20 Minutes Till Dawn and Diablo → Soulstone Survivors (both strong).
- **Seven connections (October 2026)**: all 11. No new lines; first-hand sources for four rows and a doubt on Diablo → Halls of Torment.
- **Eight connections (October 2026)**: all six. No new lines; a first-hand source for Enter the Gungeon → Gunfire Reborn.
- **The `look at it` rows (October 2026)**: all 78. First-hand sources for nine rows; two strong lines (Inscryption → Dice A Million, Isaac → Keeper's Toll) and two weaker ones found on the way.
- **The `check folder` rows (October 2026)**: 207, of which 196 have a screenshot now. Of the other eleven, one gets a proof (Torneko → Dungeon Drafters), four on Ember Knights have nothing, and a CNC interview is a linkable source for the existing Dead Cells → Scourgebringer row (first written up here as a new line by mistake).
- **The rows with no link (October 2026)**: 167, of which 139 are Dev/Series. Of the 28 others, first-hand sources for nine (Hadean Tactics, Rogue Lords, Caves of Qud, Castle of the Winds, Hack, two on Elona, GnollHack, Ultimate ADOM), and the Discord-sourced ones need screenshots.
- **Early classics, variants and console games (October 2026)**: 12 Angband/NetHack variants and Japanese console roguelikes, the Japanese ones in Japanese too. No new edges; first-hand sources for NetHack → Slash'EM and NetHack → Pathos.
- **New games on the sheet (October 2026)**: Slayblade, added with no connection, through its store page and developer posts. Nothing first-hand; it is in section 6. The owner's upload also put 24 rows on the sheet, 13 of them lines from this doc, and replaced RogueBasin's NetHack → Dungeons of Dredmor with Gaslamp's four.
- **Bluesky, Substack and Patreon (October 2026)**: the 386 games with one connection or none. Four strong lines on Sir, We Have an Orc Problem (Bluesky); nothing first-hand on Substack; Patreon's developer pages listed for reading logged in.
- **The RogueBasin and Wikipedia rows (October 2026)**: the 63 of 88 not already discussed. Most get the developer's own words (section 4), several via RogueBasin page histories showing the developer typed the infobox; four code forks to mark Dev/Series; four rows whose Wikipedia citation doesn't say it; thirteen weaker lines in section 1.
- **The second October upload (October 2026)**: all eighteen new games, the first batch through `influence_research.py new`, which runs the cloud-friendly scans over just the games missing from `tools/influence_researched.json`. Two weaker lines on Conquest Dark (one unconfirmed), better sources for Kingdom: New Lands → Crab God and Noita → Lumencraft, one roguelike the chart lacks (Teleglitch), and nothing first-hand for the ten new games with no connection.
- **The third October upload (October 2026)**: all four new games. Nothing first-hand: two came with their rows and proofs, and the two with no connection (Moonsigil Atlas, Touhou: Red Empress Devil) have only journalists' comparisons.
