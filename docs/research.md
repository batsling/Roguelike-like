# Research — every game, for everything it could give this one

The project is a graph of real games, and each of them has more to give than its
place on the map: who it influenced, what it is about, and the monsters, items,
events, heroes, statuses and places this game can borrow. Research is how that
gets found. It is organised as **eight kinds**, one system, one entry point
(`tools/research.py`), one review workbook (`tools/Research.xlsx`) and one ledger.

| kind | the question asked of a game | rows land on | how it is researched |
|---|---|---|---|
| connections | which chart games influenced it, in its developer's words | `connections` | `tools/influence_research.py`, then by hand: **[influence-research.md](influence-research.md)** |
| tags | which of the sheet's themes it carries | `games` (Tags) | `tools/tag_research.py`, from Steam; nothing by hand |
| goals | which enemies and bosses would carry a good goal | `enemies`, `bosses` (and `goals`) | its wiki, by hand: §6.1, and **[goal-enemy-candidates.md](goal-enemy-candidates.md)** |
| loot | which items could become loot, and of which kind | `items`, `trinkets`, `cards`, `weapons`, `bags`, `wands`, `potions`, `scrolls` | its wiki, by hand: §6.2 |
| events | which events or encounters could become an event | `events` | its wiki, by hand: §6.3 |
| characters | which playable characters could become a character | `characters` | its wiki, by hand: §6.4 |
| statuses | which status effects and curses could become one here | `statuses`, `curses` | its wiki, by hand: §6.5 |
| locations | which places or map objects could become a location or object | `locations`, `objects` | its wiki, by hand: §6.6 |

**The rule that does not change:** nothing goes into `tools/Roguelikes.xlsx`
until the owner has said `yes` to it. Research produces candidates. The owner
decides which become content.

---

## 1. Where things are

| path | what | checked in |
|---|---|---|
| `research/<kind>.csv` | the candidates, one file per kind. **The source of truth.** | yes |
| `research/ledger.json` | `{game: {kind: "date[: note]"}}`: what has been researched | yes |
| `research/wikis.json` | each game's wiki, how sure the match is, and how much it documents per kind | yes |
| `research/.gdignore` | keeps Godot from importing the CSVs as translation tables | yes |
| `tools/Research.xlsx` | where the owner reviews: a sheet per kind, built from the CSVs | yes |
| `.research_work/` | cached wiki reads and per-game briefs | no |
| `.influence_work/` | the influence scans' and tag research's caches | no |

`Research.xlsx` sheets: `about` (how to review), `status` (coverage and what is
next), one per candidate kind, then `tag suggestions` / `new tag ideas` /
`vocabulary` / `tags about` from the tag research. A hidden `_built` sheet and a
hidden `_base` column are how `sync` tells the owner's edits apart (§3).

## 2. The columns

Every candidate kind uses **the target sheet's own columns**, so a ticked row can
be pasted, then the same staging columns:

| column | holds |
|---|---|
| `Why it fits` | the case for the row: what the thing is in its game, and how it would play here |
| `Source` | the exact page it came from (a wiki article, a store page) |
| `Confidence` | `ok`, or `check` when it was written from a summary or a detail could not be confirmed (`?` in the goal file means the same) |
| `Status` | where the row stands: `to review`, `waiting for game row`, `lead`, `source check`, `not an influence`, `nothing found`, `on sheet` |
| `Owner`, `Owner Notes` | the owner's: `yes` / `no`, and anything they want to say |
| `ID` | a stable key, assigned by `build`. Never edit it |

`Effect` cells are left blank on purpose: the owner writes the mechanics.

Kinds that land on several sheets carry a `Sheet` column naming which one
(`loot`, `statuses`, `locations`, `goals`). `loot` spans eight sheets with
different columns, so it keeps the ones they share and puts a single sheet's
own fields in `Extra` as `key=value; key=value` (a wand's `Charges=3`, a
weapon's `Aim=front; Area=3x1; Goal=…; Charge=3`).

`connections` keeps its old doc's lines whole: `Text` is the line as it was
written (quote, attribution and all), `Heading` the section it sat under, and
one row per pair the line proposes, so a three-game quote can be ticked pair by
pair.

## 3. The review loop

1. A session writes rows into `research/<kind>.csv`, runs `research.py check`
   and `research.py build`, and commits the CSV with the rebuilt workbook.
2. The owner opens `tools/Research.xlsx`, writes `yes` or `no` in the yellow
   `Owner` column, and may correct any other cell too (a goal's wording, a
   rarity). They upload the workbook back to the same path.
3. The next session runs **`python3 tools/research.py sync`** before anything
   else. It brings the owner's edits into the CSVs and rebuilds.

`sync` works row by row through a hidden `_base` column: the hash of each row as
it was last built. If only the owner changed a row, their version wins. If only
the CSV changed (a session edited it since the build), the CSV wins. If both
did, the owner's `Owner` and `Owner Notes` are taken, the CSV's other cells are
kept, and the clash is printed with both versions so a person settles it. A row
the owner adds without an `ID` becomes a new candidate. A row they delete is
reported and kept: the way to turn one down is `no`, so the idea isn't proposed
again.

A `yes` row waits in the workbook until it is pasted into `Roguelikes.xlsx`.
From then on, `build` sees it there and sets its Status to `on sheet` by itself,
for every kind (for connections, when the pair is a row). Pasting is a separate
step, done by the owner or by a session the owner asks to do it, always through
`tools/_xlsx_surgery.py` (never openpyxl on `Roguelikes.xlsx`). For goals,
`tools/_candidates_to_sheet.py` pastes the `yes` rows, but it has a known gap:
see its docstring.

## 4. Commands

```bash
python3 tools/research.py sync                # FIRST, if the owner has uploaded Research.xlsx
python3 tools/research.py status              # coverage per kind; -v also lists what is next
python3 tools/research.py next loot -n 5      # the next games for a kind
python3 tools/research.py wikis               # find wikis for games not looked for yet
python3 tools/research.py wikis "Some Game"   # look again for one (after renaming it, say)
python3 tools/research.py brief "Hades"       # a game's dossier -> .research_work/briefs/hades.md
python3 tools/research.py page "Hades" "Charon" "Megaera"           # pages as plain text
python3 tools/research.py page "Hades" --category "Boons" --chars 400   # a whole category, briefly
python3 tools/research.py mark loot "Hades" --note "9 rows"         # after writing a game's rows
python3 tools/research.py check               # CI runs this
python3 tools/research.py build               # CSVs -> Research.xlsx
python3 tools/research.py new                 # every kind, for games just added (§7)
```

`brief` puts everything about one game in one file: its row on the games
sheet, what it already gives the game (every sheet), what is already a
candidate, and for each kind the wiki's list articles and categories with
every page title in them. Read it first. Then read the pages with `page`, which
fetches 50 at a time and keeps an infobox's `key: value` lines (where a wiki
keeps a monster's health or an item's effect).

## 5. Which games, in what order

The owner chose **owned games first, best-documented first**. `next <kind>`
applies that: games not yet in the ledger for that kind, owned before not
owned, then by how many pages the game's wiki keeps in that kind's categories
(plus a little per list article), then the oldest. `--unowned` widens it to the
whole chart once the owned games are done.

Research **by game, not by kind**. One game's wiki answers all six wiki kinds,
so a session takes a game, reads its brief once, writes its rows for every kind
it has something for, and marks each kind:

```bash
python3 tools/research.py mark goals  "Hades" --note "6 rows"
python3 tools/research.py mark loot   "Hades" --note "11 rows"
python3 tools/research.py mark events "Hades" --note "nothing usable: its encounters are fights"
```

A kind with nothing is still marked, with a note saying why, so it is not
searched again. The ledger is the only record of "searched, nothing found" for
the wiki kinds: it is cheap, which is the point.

The 80 games of the old goal passes are marked for `goals` with the note
"from search summaries, before the wikis were reachable". The wikis were blocked
then, so those rows were written blind. Every one of those games is worth a
second pass with the wiki open, which means taking its ledger entry out first.

## 6. Writing a candidate

Six rules hold for every kind:

1. **It is a real thing in that game**, named the way the game names it, with
   the page it came from in `Source`. A wiki describing what is IN a game is a
   fine source. That is different from influences, where only the developer's
   own words count.
2. **Translate, don't transcribe.** The question is never "what does it do
   there" but "what would it do here". This game is played on top of other
   games: the run is a map of real games, a "fight" is going off and playing
   one, and everything reads back through goals, chests, health, gold and the
   verbs (Bash, Dash, Push, Transmute, Scramble). `Why it fits` says which part of
   this game the thing plugs into.
3. **Check the brief's "already in this game" first.** A candidate that
   duplicates something live, or another game's candidate, is noise.
4. **Leave Effect blank.** Describe the intent in `Description` (or `Result N`
   for events) in the sheet's voice ("Gain +1 Shield…"), and leave the mechanic
   to the owner.
5. **`File` / `Image` is the PascalCase of the Name**, where its art will hang.
6. **Quality over coverage.** A game that gives two good rows is better than
   one that gives twenty mediocre ones, and "nothing usable" is an answer.

### 6.1 goals → `research/goals.csv`

The rules are in [goal-enemy-candidates.md](goal-enemy-candidates.md) ("How a
row is judged") and `tools/check_goal_candidates.py` enforces the mechanical
ones. In short: **it must be a creature**; **the goal is attempted in whatever
game of that Type the player picked**, so it has to make sense there, not only
in its source game; bosses are the tier-change slot (about two per game, never
over three); Health `1`; Damage `1/2/3/4` by tier (`3/5/7/9` for bosses);
`Ability` is `N/A` (abilities are their own pass). `Ticked` is blank (`any
time`) or `game beaten`; `Count` is blank or 2+, enemies only. Every goal is
authored in the `goals` sheet once a row is pasted (CLAUDE.md).

### 6.2 loot → `research/loot.csv`

Pick the sheet by how the thing is USED in its game:

| it is… | sheet | notes |
|---|---|---|
| an always-on pickup, a relic, a passive item | `items` (relics) | Rarity is the sheet's `Rating`: Common / Uncommon / Rare, or Boss / Event / Starter. Type: Passive, Triggered, Pickup, `Charged, N`, `Usable, N` |
| small, positional, coin-like, or caring about its neighbours | `trinkets` | Type Passive or Charged; Size `1x1` usually ([loot-passives.md](loot-passives.md)) |
| played once, or a held card | `cards` | Type Usable or Passive |
| a weapon you swing or fire | `weapons` | aimed like a thrown potion, charged by its own goal: `Extra` gives Aim, Area, Goal, Charge |
| something that holds other things | `bags` | Size is its shape |
| a charged zapper | `wands` | `Extra`: Charges; Type Ray / Non-Directional / Random |
| a drink or a thrown flask | `potions` | Preference Positive / Negative / Neutral |
| read once, for an effect | `scrolls` | Preference as potions |

Rarity is Common / Uncommon / Rare (`Legendary` exists on wands only). Map the
source game's rarity rather than inventing one. `Tags` are the themes the piece
belongs to (`coin`, `food`, `blood`), as on the live rows.

### 6.3 events → `research/events.csv`

An event fires after **every** game the run plays and is worth about one game's
reward ([event-sheet-authoring.md](event-sheet-authoring.md) §1.1). Good
candidates are the source game's own events: a prompt, two to four choices, and
a tension between them (a cost for a gain, a gamble, a "leave it alone"). Fill
`Event`, `Game`, `Rarity` (`Common` unless it is special), `Prompt` (the
situation, in the game's voice), and per choice `Choice N` (the button) and
`Result N` (what happens, in words). `Tier` is `All` and `Trigger` `After`, as
on every live row. `Effect N` stays blank. An event that is really a fight, a
shop or a rest site is not an event here.

### 6.4 characters → `research/characters.csv`

A character is a run's hero. Copy the live rows' scale: Health 7–8, Gold 3, and
about two points of verbs (Bash, Dash, Push, Transmute, Scramble, Bombs, Keys,
Random) that say what the hero is like. `Level Up` is a goal attempted in a
winning game ("Beat a game while …", always `game beaten`). `Reward` is its
payout (a chest), `Description` the game's own one-line pitch, and `Starting
loadout` names a piece of loot, live or a candidate.

### 6.5 statuses → `research/statuses.csv`

Two sheets. A **status** (`Sheet` statuses, Type Buff or Debuff) changes a goal:
`On Player` says what it does to the goal you carry ("You must beat a game while
… or take 3 Damage"), `On Enemy` what it does to a body's, and `Combat` what it
does on the board. A **curse** (`Sheet` curses) has a `Condition` ("you go below
half health"), a `Penalty`, and a `Timer`. `What it does there` holds the source
game's own rule, so the translation can be judged against it.

### 6.6 locations → `research/locations.csv`

Two sheets. A **location** (`Sheet` locations) is a place with a goal and a
payout: `Difficulty`, `Goal Type`, `Goal`, `Goal Effect` ("Gain +1 Small
Chest") and the enemy `Tag` it favours. An **object** (`Sheet` objects) is
something standing in an event, with choices (an arcade machine, a shrine):
`Tag` groups it (`arcade`), and `Choices` lists its buttons and what each does,
in words.

## 7. When games are added

CLAUDE.md's porting steps hand off to one command:

```bash
python3 tools/research.py new
```

It takes every game with no ledger entry, runs `influence_research.py new`
(connections) and `tag_research.py` (tags), finds the new games' wikis, writes
a brief for each, and prints the hand work left. Then, for each new game:

1. **connections**: read `.influence_work/new_games.md`, search the web per game
   ([influence-research.md](influence-research.md)), write what holds up as
   rows in `research/connections.csv`, then `influence_research.py new --mark`.
2. **goals, loot, events, characters, statuses, locations**: read its brief and
   the pages it lists, write rows, then `research.py mark <kind> <game>` for
   every kind, rows or not.
3. `research.py check && research.py build`, and commit the CSVs, the ledger,
   `wikis.json` and `Research.xlsx` together.

`new` does not write the ledger. Each kind is marked once its rows are written,
so a session cut short leaves the gap visible in `status`.

## 8. Wikis

`wikis` finds a game's wiki by trying the addresses a community would pick:
`<title>.fandom.com` and `<title>.wiki.gg`, with and without "the", the
title before a subtitle, and the series name for a sequel (Spelunky 2 shares
Spelunky's wiki). Fandom's own search is behind Cloudflare and can't be used
from here, which is why it guesses. The first full run (October 2026) found a
wiki for **333 of the 921 games**: 204 on Fandom, 125 on wiki.gg, and the four
communities on their own domains listed in `KNOWN_WIKIS`.

A guessed address finds whatever owns the name, so each find is judged twice:

- **by name**: `match: sure` when the wiki is named after the game, subtitle
  and all; `check` when one name only contains the other: a series wiki
  ("Spelunky Wiki" for Spelunky 2) or the game a subtitle hangs off ("Dragon
  Quest Wiki", 17,000 articles, for Young Yangus). Read a `check` wiki's pages
  knowing they may be about another game in the series.
- **by main page**: a name match is kept `sure` only if the main page says
  roguelike (or -lite) or the release year, or the wiki keeps at least five
  pages of enemies or items. Otherwise it drops to `check`. This is what caught
  `ragnarok.fandom.com` (a Ragnarök fan wiki), `ringer.fandom.com` (a TV
  series) and `omega.fandom.com` (a web series), now set by hand to no wiki.
  `blurb` holds the first lines of the main page for a person to judge by;
  `signal` records what it said (`null` when it could not be read).

Each record also holds `counts` (pages in each kind's categories, which is what
`next` ranks by), `categories` (the ones that matched, biggest first) and
`pages` (the list articles that exist, such as "Status Effects": statuses
rarely get a category of their own).

To correct a game by hand, edit its entry and add `"set": "by hand"` (with a
`note` saying why), which every later run leaves alone.

**Go gently.** The first run fired eight threads at Fandom unpaced, and Fandom
rate-limited this client for a while (HTTP 429, and a Cloudflare challenge on
`action=parse`). `fetch` now paces every request per host family (one per
`PACE` seconds across all threads) and sleeps as long as a 429 asks. Reading a
page goes through `action=query` (raw wikitext), never `action=parse`.
Wikipedia also rate-limits and PCGamingWiki refuses the cloud container, but
neither describes a game's contents anyway.

## 9. What is not built yet

- **Main-page blurbs are missing for most wikis.** Fandom was rate-limiting
  this client when they were read, so most records have no `blurb` or
  `signal` yet (and are judged by name alone). `research.py wikis --blurbs`
  reads them again without rediscovering anything; run it in a later session.

- **Pasting `yes` rows** is manual for every kind except goals, and the goals
  paste has the `goals`-sheet gap its docstring describes. Build each paste when
  the first `yes` rows for that kind arrive, so it is written against real rows.
- **Tags** stay in the workbook only (no CSV): they are regenerated from Steam
  on every run and the owner's marks are carried by `tag_research.py` itself, as
  before.
