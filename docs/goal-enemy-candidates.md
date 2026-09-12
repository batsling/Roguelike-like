# Goal-enemy candidates

`docs/goal-candidates.csv` is the deliverable: **301 audited candidate rows** in
the exact column order of the `enemies` and `bosses` sheets of
`tools/Roguelikes.xlsx`, ready to paste and regenerate from. This file is the
companion — what the columns were filled in with, what the audit threw out, and
what is still unresolved.

Nothing here is wired up. `data/` is untouched.

**`python3 tools/check_goal_candidates.py` is the audit as a script.** Every
rule below that a row can break mechanically — the enums, `Health` 1, the Damage
mapping, the Size grammar (parsed with the generator's own `parse_size`, not a
copy of it), a duplicate `Name` / `File` / `Goal` / id inside the file or against
the live sheet, a `Game` the catalog does not spell that way, a `Type` that
disagrees with the game's own — is checked there, so the next pass does not have
to take this one's word for it. `--stats` prints the distribution tables quoted
below. It was written for the second pass, immediately found five rows the
first pass had got wrong, and has gated every row added since.

## The file

| | |
|---|---|
| Rows | 301 — **216 enemies, 85 bosses** |
| Games | 69, of which 51 are new to the project |
| Columns | `Sheet, Name, Type, Difficulty, Size, Game, Health, Damage, Goal Type, Goal, Ability, File, Tag, Phases` then two staging columns |
| Staging columns | `Confidence` (`ok` / `?`) and `Why this pairing` — **delete both before pasting**; the sheet has no such columns |

Split on the `Sheet` column: `enemies` rows go to the `enemies` sheet, `bosses`
rows to `bosses` (which has the extra trailing `Phases`, left blank —
Guillatina is currently the only multi-phase boss).

Conventions copied off the live rows rather than invented:

- **Health** is `1` on all 94 existing rows, so it is `1` on every row here.
- **Damage** is the difficulty index for enemies (1/2/3/4) and `3/5/7/9` for
  bosses. Every candidate follows that mapping exactly.
- **Difficulty** is `1-Low` … `4-Insane`; **Type** is `Action` / `Deckbuilder` /
  `Strategy` / `Traditional`; **Goal Type** is `Bounty` / `Feat` / `Fetch` /
  `Restriction` / `Discovery` — all title-case, as the generator expects.
- **Size** defaults to `1x1`, bosses to `2x2`, with a handful of deliberate
  exceptions (`Larry Jr.` 1x2, `Wallmonger` and `The Giant` 3x3, the Balatro
  blinds 1x1 like the five already shipped).
- **Ability** is `N/A` everywhere. Abilities are a separate authoring pass
  against the `abilities` sheet (§7.6) and guessing them here would only make
  work.
- **File** is the PascalCase of the name. No art exists for any of these yet; a
  missing PNG leaves `image` unset and the runtime uses a placeholder.

## Second pass — thirteen more wikis

The first pass drew on 44 games. This one adds **13**, all of them **owned** and
all of them already in `data/games/`, chosen where the file was thinnest rather
than where the games are most famous: **Traditional** was the starved pool and
takes 16 of the 37 new rows, **Strategy** was the smallest at 18 rows and takes
9. Action, already the biggest pool, takes 4.

| Game | Type | Rows | Wiki |
|---|---|---|---|
| Angband | Traditional | 3 + 2 bosses | thangorodrim.net, angband.readthedocs.io |
| Ancient Domains of Mystery | Traditional | 2 + 2 | ancardia.fandom.com, adomgb.info |
| Dungeons of Dredmor | Traditional | 2 + 1 | dungeonsofdredmor.fandom.com |
| Mystery Dungeon 2: Shiren the Wanderer | Traditional | 3 | mysterydungeonwiki.com |
| Tangledeep | Traditional | 1 | tangledeep.fandom.com |
| FTL | Strategy | 2 + 1 | ftl.fandom.com |
| Into the Breach | Strategy | 2 + 1 | intothebreach.fandom.com |
| Dwarf Fortress | Strategy | 1 + 2 | dwarffortresswiki.org |
| Dicey Dungeons | Deckbuilder | 2 + 1 | diceydungeons.fandom.com, wiki.diceydungeons.com |
| Hand of Fate | Deckbuilder | 2 + 1 | handoffate.fandom.com, hand-of-fate-2.fandom.com |
| Peglin | Deckbuilder | 1 + 1 | peglin.wiki.gg |
| Spelunky Classic | Action | 2 | spelunky.fandom.com |
| UnderMine | Action | 2 bosses | undermine.wiki.gg |

Same six passes as the first draft, and the same bar: a creature (not a room, an
item or a system), a goal that means something in **any** game of that type, and
nothing that reads like a row already in the file. What that bar threw out this
time:

| Cut | Why |
|---|---|
| **Ghost** (Spelunky Classic) | `Ghost` is already a Crypt of the NecroDancer row — same Name, same File, same id |
| **Olmec** (Spelunky Classic) | already in the file as a Spelunky 2 boss, carrying the better version of the same idea (*defeat an enemy you cannot damage*) |
| **Burrower** (Into the Breach) | *attacks from underground* is Risk of Rain's Magma Worm, *defeat an enemy that burrows* |
| **Knight Knight** (Peglin) | *an enemy in heavy armour* is Cogmind's Death Metal, *defeat an armoured enemy* |
| **Duke Dirtbeak** (Tangledeep) | *a giant bird* is Rogue Legacy 2's Lord of Owls, *defeat a bird* |
| **King Alien Lord** (Spelunky Classic) | *the leader of a hive* is Cataclysm's Chief, *defeat a leader* |
| **Blobber, Goo, Slime Hive, Demon Wall, Webber** | a fourth splitter, a third spawner, a second wall and a second web; all four ideas are already spoken for |

One row was **reworded rather than cut**: UnderMine's `Seer` opened as *beat a
boss without taking a hit*, which is Dead Cells' Concierge word for word. It is
now *beat a boss without healing* — a different rule on the same fight, and a
third member of the boss-under-a-rule family the ledger already tracks.

**What the checker found in the first pass's own rows.** Five rows named their
game `Pokemon Mystery Dungeon`, which is not a game: the catalog has six
Pokémon Mystery Dungeon titles and no such string, so `source_game` would have
pointed at nothing. Split by where each creature actually lives — Kecleon,
Groudon, Zapdos and Rayquaza to **Red and Blue Rescue Team**, Primal Dialga to
**Explorers of Sky**, which is the game its own `Why this pairing` note already
described. Nothing else in the 243 failed: the enums, the Damage mapping, the
Size grammar, the Name/File/Goal/id collisions and the game-type agreement were
all exactly as the first pass claimed.

## Third pass — eleven more wikis, aimed at Strategy

The second pass left **Strategy** the smallest pool at 27 rows; this one spends
five of its eleven games there and takes it to **37**. Deckbuilder gets two,
Traditional three, and Action — the biggest pool at 117 — gets one game and two
rows, on purpose.

| Game | Type | Rows | Wiki |
|---|---|---|---|
| Slice & Dice | Strategy | 2 | slice-and-dice.fandom.com, minmax.wiki |
| Shogun Showdown | Strategy | 2 + 1 boss | shogunshowdown.wiki.gg |
| Dome Keeper | Strategy | 2 | domekeeper.wiki.gg |
| Legend of Keepers | Strategy | 2 | legendofkeepers.fandom.com |
| Ring of Pain | Strategy | 1 boss | ring-of-pain.fandom.com |
| Backpack Hero | Deckbuilder | 1 + 1 | backpackhero.wiki.gg |
| Across the Obelisk | Deckbuilder | 2 | ato.fandom.com |
| Jupiter Hell | Traditional | 2 | jupiterhell.fandom.com |
| Rift Wizard | Traditional | 1 | riftwizard.fandom.com, riftwizard2.wiki.gg |
| Hoplite | Traditional | 2 | the game's own rules reference |
| Gunfire Reborn | Action | 1 + 1 | gunfirereborn.fandom.com |

**Legend of Keepers is the interesting one.** You play the dungeon, so its
*enemies* are the heroes raiding you — which is where `Defeat a hero` finally
comes from, a goal the first 280 rows never had a body for. Hoplite is the other
one worth reading: it is small enough that each demon is a single rule, and two
of those rules turn into goals nothing else in the file asks for — *beat a ranged
enemy by standing next to it* (its Archer cannot attack an adjacent tile at all)
and *use an enemy as cover* (its Wizard will not fire through another demon).

Cut or reworded, same bar as before:

| Change | Why |
|---|---|
| **Elite Lobster** (Gunfire Reborn) cut | *a giant crustacean* and *a giant serpent* are the same row twice, from the same game |
| **Tick** (Dome Keeper) reworded | *defeat several enemies with one attack* is Isaac's Larry Jr., *attack 5+ enemies at once*; it is now *defeat an enemy before it reaches you*, which is what a Tick actually threatens |
| **Fights in Tight Spaces** dropped whole | every body it has lands on a row that already exists — armoured, outgunned, grabs you, surrounded — and its one free idea (an environmental kill) is Flaming Fatty's *push an enemy into fire* |
| **Moonlighter** dropped whole | its mimics are the file's *chest that fights back*, its repair golem is Legend of Keepers' healer, its first boss is Prickwood |
| **Dicefolk** dropped whole | no individual creature name surfaced through search at all — 100+ chimeras and not one of them nameable from here |
| **Warden** (Shogun Showdown), **Medusa** and **Warlock** (Jupiter Hell) | the Name is already taken in the file, by a different creature from a different game |

## What the audit checked, and what it changed

Six passes over every row. The first two were the expensive ones.

**1. Is it a creature?** About thirty picks were not enemies or bosses at all —
altars, items, rooms, statuses, buildings, player abilities, whole game systems,
and friendly NPCs. Each was replaced with a real body from the same game or cut:

| Was | What it actually is | Now |
|---|---|---|
| Kali / Kapala / Mech | an altar, an item, a vehicle | **Witch Doctor**, **Vampire**, **Qilin** |
| Occultist | a *player* hero | **Thing From The Stars** |
| The Pyre | the thing you defend | **Lightwing**, the angel attacking it |
| Monster House / Empty Belly / Trap tile | a room, a status, furniture | **Groudon**; other two cut |
| Recruited Pokémon | an ally | **Zapdos** — beat it, then recruit it |
| Terminal / Salvaged parts | a machine, items | **Operator**, **Hauler** |
| Corruption / Blinding Greed / blood offering | curses and gauges | **Xucat'**, **Xak'olchir**, **Champion of Death** |
| Negotiation / Grudge / Job board / Resolve | systems | **Kashio**, **Arint**, **Jake Smuggler**, **Plocka** |
| Escort / cursed artifact / unlock condition | an NPC, an item, nothing | **Bill the Stone Troll**, **Grand Corruptor**, **Rak'Shor Cultist** |
| Camp / Treasury | buildings and cards | **Goblin Leader**, **Chest** (a real Loop Hero enemy) |
| Pet / Frozen Traveller / Frost | allies, a status | **Frost Jailer**, **Truffle**, **Eye of the Storm** |
| Molly / Drilldozer | friendly machines | **Web Spitter**, **Oppressor** |
| Hypnotizer / Knockout / Bank vault | an item, a verb, a room | **Gorilla**, **Cop**; vault cut |
| skull swap / awakened skull / Little Bone | abilities, the player | the four Skul bosses |
| Blood cost / Death card | a cost, an item | **Grimora**, **P03**, **The Unfinished Boss** |
| The Blacksmith and Apprentice | Dead Cells NPCs | **Black Pudding**, **Gronk** |
| Selene | a Hades II boon-giver | nothing — *use star power* stays open |
| Gremlin Gang / Sentries | encounters, not creatures | **Fat Gremlin**, **Sentry** |
| Skelly / Damsel / Bartender | non-hostile NPCs | **Bullet Kin**, **Dar Blademaster**; Bartender cut |
| Ink Eel | a GBrogue variant, not base Brogue | **Phantom** |

**2. Does the goal make sense for the pool it lands in?** A goal is attempted in
whatever game the player picked of that **Type** — not in the enemy's own game.
Anything that could only ever happen in its source game was rewritten to the
thing it is really about:

- "Defeat a champion to have a curse lifted" → **Defeat an enemy while cursed**
- "Trade a pelt for a creature" → **Trade a monster drop for something better**
- "Be rescued, or rescue someone else's failed run" → cut; Primal Dialga now
  carries **Defeat a boss that controls time**
- "Defeat a treasure chest" → **Defeat a chest that fights back** (mimics are
  everywhere)
- "Break someone's will without hurting them" → **Make an enemy flee or
  surrender**
- "Never miss a beat" → **Do not pause the game**
- "Make an enemy who remembers you next run" → **Meet an enemy that remembers a
  past run**
- **Beat a run without moving** was impossible as written in most games and is
  now **Win a fight without moving**.

**3. Boss budget.** The first draft had 134 bosses. A boss here is the
tier-change slot, not "this creature is a boss in its own game" — the live sheet
keeps about two per game. 67 bosses now, 1.8 per game, no game over three. The
67 demotions are all still perfectly good goal-enemies; the workbook already
ships elites like `Fungi Beast` and `Shelled Parasite` as ordinary rows.

**4. Difficulty.** Two passes. Difficulty is how hard the **goal** is in a normal
run, not how hard the creature is in its own game — "defeat a big cat" is Low
even when the cat is a boss, "clear a floor unseen" is High on an unarmed enemy.
The result lands on the live sheet's own shape:

| | Low | Medium | High | Insane |
|---|---|---|---|---|
| first pass (243) | 109 | 90 | 35 | 9 |
| second pass (+37) | 11 | 15 | 7 | 4 |
| third pass (+21) | 7 | 9 | 4 | 1 |
| candidates (301) | 127 | 114 | 46 | 14 |
| live sheet (94) | 43 | 32 | 15 | 4 |
| as a share | 42% vs 46% | 38% vs 34% | 15% vs 16% | 5% vs 4% |

The second pass leans a tier harder than the first — 4 of its 37 rows are Insane
against 9 of the first 243 — because the games it read are where the genre keeps
its long hauls: Angband's level 100, ADOM's emperor lich, FTL's flagship. That
moves the whole file about a point off the live sheet's shape in each direction,
which is close enough to leave alone rather than pad with filler Lows.

**5. Collisions.** Checked by `tools/check_goal_candidates.py` against the live
sheet and inside the candidate set: **no duplicate `Name`, no duplicate `File`,
no duplicate `Goal`, and no collision with any of the 94 existing rows** on any
of the three, plus the id each `Name` slugifies to. Three near misses worth
knowing:

- NetHack and Enter the Gungeon both have a **High Priest**. Both ship, with
  opposite verbs — NetHack's was reassigned to the **Aleax** so *pray* keeps a
  body and Gungeon's High Priest takes *defeat a priest*.
- Brotato's `Colossus` would have collided with Risk of Rain's, already on the
  sheet. Dropped.
- `Lich` (Gungeon, shipped) and `The Lich` (Loop Hero, candidate) generate
  distinct ids but read alike on the HUD. Your call.
- Angband's **Grip** and Dredmor's **Diggle** are both the first thing their
  game shows you, and both stayed: one is *defeat a named enemy* (uniques are a
  Traditional fixture), the other *defeat an enemy guarding its young*.

**6. Type balance.** The starved pool was **Traditional** — 8 of 94 live rows,
so a run on traditional games was drawing from NetHack ×4, Crypt ×3, Rogue ×1.
The candidates now add **86 traditional rows** across fifteen traditional
roguelikes (NetHack, Crypt, Rogue, Brogue, DCSS, Caves of Qud, Shattered PD,
Cogmind, Cataclysm: DDA, Tales of Maj'Eyal, Pokémon Mystery Dungeon, and from
the second pass Angband, ADOM, Dungeons of Dredmor, Shiren and Tangledeep).

The second-smallest pool was **Strategy**, which the first pass left at 18 rows
drawn almost entirely from Mewgenics and Brutal Orchestra. The second pass spent
three of its thirteen games there (FTL, Into the Breach, Dwarf Fortress) and took
it to 27; the third spent five of eleven (Slice & Dice, Shogun Showdown, Dome
Keeper, Legend of Keepers, Ring of Pain) and took it to **37**. Across the whole
file: Action 117, Traditional 91, Deckbuilder 56, Strategy 37 — still the
sheet's lean, with the thin end pulled up twice.

Strategy is the pool where a goal is hardest to write, which is why it stayed
thin: the type covers everything from a fortress sim to a four-tile tactics
board, so a goal has to survive both. The ones that work are about POSITION and
UPKEEP rather than about hitting things — *repair something an enemy has broken*,
*defeat an enemy before it reaches you*, *defeat the enemy that is making the
others stronger*.

## Overlap ledger

Kept-on-purpose neighbours: same idea, different `Goal Type`, `Difficulty`, or
physical act. Anything that could not clear that bar was cut rather than
reworded.

| Idea | A | B | How they differ |
|---|---|---|---|
| Stealing | `Steal from a shop` (Charon, Fetch) | Keystone Kops, Feat, Med — *escape* it | taking vs escaping |
| Stealing | Angry Shopkeeper, Feat, Med | Kecleon, Bounty, Insane | verb and two tiers |
| Allies | Mystic, Feat, Med — a fight | The Fanatic, Feat, High — a floor | duration and tier |
| Allies | Dar Blademaster, Feat, Med — train one | Ogre, Feat, Med — free one | different act, different game type |
| Taming | Leshy, Feat, Med | Gorilla, Bounty, Low | keep it vs kill it |
| Enemy kills enemy | `Have an enemy defeat another enemy` (Marshmallow) | Goblin Conjurer, Feat, Low | whose side the killer is on |
| Curses | Hecate, Feat, Med — get one | Xucat', Feat, High — hold four | count and tier |
| Upgrades | Black Pudding, Feat, Low — a weapon | Warlock, Feat, High — 5+ enchants | count and tier |
| Upgrades | Bill the Stone Troll, Feat, Med | Warlock, Feat, High | every future run vs this one |
| Sacrifice | Witch Doctor, Feat, Med | Xak'olchir, Feat, Low | whose blood |
| Health as currency | `Trade health for resources` (Krampus, Feat, Low) | Mega Satan, Feat, High — halve your max | scale and tier |
| Explosions | Gas Spore, Bounty, Med — kill in one turn | Bulk Detonator, Feat, Low — survive one | killing vs surviving |
| Not killing | Watchman, Restriction, Med — spare innocents | Cop, Restriction, High — spare everyone | scope and tier |
| Stealth | `Become undetectable` (Stalker, Feat) | Watcher, Restriction, High — a whole floor | a moment vs a rule |
| Spawners | `Destroy an enemy spawner` (Carcass, Bounty) | Dreadful Offspring, Feat, Med | kill the source vs clear the room |
| Two-in-one | The Wicked Twins, Bounty, Med — two | Kill Pillars, Bounty, Low — four | count and tier |
| Crowns | King Conga, Fetch, Low — wear one | Old King, Bounty, Low — take one | Fetch vs Bounty |
| Swallowed | Jonah, Feat, Med | Charybdis, Feat, Med | different game types, so different pools |
| Priests | Aleax, Feat, Med — pray | High Priest, Bounty, Low — kill one | opposite verbs |
| Vehicles | Treadnaught, Feat, Med — pilot | Bob, Feat, High — build | DM-200 repairs sits between them |
| Trapped | `Trap an enemy in place` (Spider Kitten, Feat) | Web Spitter, Feat, Low | who is stuck |
| Transform | The Guardian, Feat, Low — make it happen | Werewolf, Discovery, Low | cause vs witness |
| Trash | Chubs 'n' Nubs, Fetch, Low (Strategy) | Recycler, Fetch, Low (Traditional) | same goal, different type pools — a run only ever sees one |
| Made of something | Wisp *fire*, Big Chunk *stone*, Blood Clot *blood*, Gurdy *other enemies* | Bronze Colossus *metal*, Snowman *ice or snow* | an established family; each names a different material and no game has two |
| Final bosses | Rebel Flagship, Bounty, Insane — beat it | Rayquaza *first attempt*, Strong Daemon Master *hardest difficulty* | the clause is the goal; the plain one had no owner until FTL |
| Title bosses | Lord Dredmor, Feat, High — the boss the game is NAMED after | Rebel Flagship, Bounty, Insane — the LAST one | often not the same body, and not the same search |
| Boss under a rule | The Concierge *no damage taken*, Bone Courtier *no summons* | Seer, Restriction, Insane — *no healing* | three different rules on the same shape of fight |
| First thing you meet | Snake, Bounty, Low — an enemy in the first room | Prickwood, Bounty, Low — the first BOSS of a run | enemy vs boss, and two different pools |
| Out-something-ed | Grunt, Traditional — *outguns you* | Scarab, Strategy — *outranges you* | firepower vs reach, and a run sees one pool |
| Propping up the others | Warden, Action — *protecting* the others | Psion, Strategy — *making the others stronger* | a shield vs a buff |
| Eggs | Diggle, Bounty, Low — kill the parent standing over them | Spider Leader, Feat, Med — destroy the egg itself | opposite ends of the same nest |
| The weakest thing | Mamel, Bounty, Low — defeat it | Boldor, Bounty, Med — defeat its KING | same species, one tier apart |
| Propping up the others | Warden *protects*, Psion *buffs* | Priestess, Bounty, Med — *heals* | three roles, three verbs; Weirdling Beast heals only ITSELF |
| Immobile | Turret, Bounty, Med — *cannot move* | Olmec, Bounty, Med — *cannot be damaged* | what the enemy can't do is the whole difference |
| Phases | The Shogun, Feat, Insane — a boss with more than one | Bone Hydra, Bounty — an enemy with more than one HEAD | one is a fight that restarts, one is anatomy |
| Summoned bodies | Carcass *kill the spawner*, Dreadful Offspring *clear the room* | Bones, Bounty, Low — kill the summoned thing itself | three points on the same chain |

Cut as true duplicates: a second freeze (Stygian Guard), a second splitter (Pink
Jelly), a second thief (Brogue Monkey), a second summoner (Ogre Shaman, Brood
Nexus, Reptomancer), a second shrink (SoR shrink ray), a second drunk (Smith), a
second level-30 (ToME prodigies), a second do-not-backtrack (Loop Hero's loop), a
second no-magic (ToME antimagic), a second two-boss fight (Donu and Deca), a
second dragon (Dragon Prince), and Brotato's `Colossus`. The second pass added
six more: Spelunky Classic's `Ghost` and `Olmec` (both already in the file under
another game), Into the Breach's `Burrower`, Peglin's `Knight Knight`,
Tangledeep's `Duke Dirtbeak` and Spelunky Classic's `King Alien Lord`. The third
added Gunfire Reborn's `Elite Lobster`, and three whole games — Fights in Tight
Spaces, Moonlighter and Dicefolk — that produced nothing a row did not already
say.

## Still open

- **Use star power** — no enemy in any of the 69 games carries it.
- **Drink milk**, **make a cake**, **smoke something** — all three are ordinary
  Cataclysm: DDA items, but no body on its bestiary is *about* them yet.
- **14 rows are marked `?`** in the Confidence column, all of them from the
  first pass: the creature or the detail could not be confirmed against a wiki
  page. They are spread thin (Monster Train ×2, CDDA ×2, Wildfrost ×2, Ember
  Knights ×2, and singles elsewhere) and each needs a look before it ships. The
  second pass added none — every one of its 37 rows names a creature that came
  back in a wiki result, which is why it is 37 rows and not 90.
- **Tangledeep, Peglin and Spelunky Classic are under-read.** Each gave up one
  or two rows before its wiki stopped surfacing bodies through search, and each
  plainly has more: Tangledeep's whole Monsterpedia, Peglin's Slimedrop line and
  its eight bosses, Spelunky's Classic bestiary. They are a search-quality
  limit, not a content limit.
- **UnderMine contributed two bosses and no ordinary enemies**, which is the
  wrong shape for a game — its normal roster (the peons, the bombers, the
  gloomcaps) never surfaced with enough detail to write a goal from.
- **The third pass is boss-light**: 4 bosses in 21 rows, against the file's
  overall 28%. Small games have one or two bosses and search surfaces the
  ordinary roster first, so Slice & Dice, Dome Keeper, Legend of Keepers, Across
  the Obelisk, Jupiter Hell, Rift Wizard and Hoplite all ship enemies only. Each
  of them has a boss worth a row when someone can read the page rather than the
  search result.
- **Every pass so far has been limited by the same thing**, and it is worth
  saying once: the egress proxy blocks the wikis, so every row in this file was
  written off a search summary. That is why the yield per game keeps falling —
  the first pass took the games whose rosters search knows by heart, and what is
  left is games where you have to open the bestiary.
- Every game whose wiki lists enemies as a stub — **Dungeon Clawler** especially
  — has more to give than the two rows here.
- **Brutal Orchestra** and **Gnomes** are on the sheet but produced nothing this
  pass; neither wiki surfaced a usable roster through search.

## Sources

Wikis read, by game. Direct fetching is blocked from this environment — the
egress proxy refuses fandom, wiki.gg and the rest alike — so both passes read
these through search results rather than page by page; that is the reason for
the `?` column, and for the three under-read games above.

### Third pass

Slice & Dice ([1](https://slice-and-dice.fandom.com/wiki/Category:Enemies),
[2](https://minmax.wiki/slice-and-dice/monsters),
[3](https://slice-and-dice.fandom.com/wiki/Lich)) ·
Shogun Showdown ([1](https://shogunshowdown.wiki.gg/wiki/Enemies),
[2](https://shogunshowdown.wiki.gg/wiki/Bosses),
[3](https://shogunshowdown.wiki.gg/wiki/The_Shogun)) ·
Dome Keeper ([1](https://domekeeper.wiki.gg/wiki/Enemies),
[2](https://domekeeper.wiki.gg/wiki/Sortable_Enemy_List),
[3](https://domekeeper.wiki.gg/wiki/Walker)) ·
Legend of Keepers ([1](https://legendofkeepers.fandom.com/wiki/Monsters),
[2](https://legendofkeepers.fandom.com/wiki/Heroes)) ·
Ring of Pain ([1](https://ring-of-pain.fandom.com/wiki/Owl_(Boss)),
[2](https://www.pcinvasion.com/ring-of-pain-enemy-guide/)) ·
Backpack Hero ([1](https://backpackhero.wiki.gg/wiki/Bestiary),
[2](https://backpackhero.wiki.gg/wiki/Frozen_Heart)) ·
Across the Obelisk ([1](https://ato.fandom.com/wiki/Enemies),
[2](https://ato.fandom.com/wiki/Bosses),
[3](https://ato.fandom.com/wiki/The_Wolf_Wars)) ·
Jupiter Hell ([1](https://jupiterhell.fandom.com/wiki/Enemies),
[2](https://classic.jupiterhell.com/wiki/Enemies)) ·
Rift Wizard ([1](https://riftwizard.fandom.com/wiki/Monsters),
[2](https://riftwizard2.wiki.gg/wiki/Monsters)) ·
Hoplite ([1](https://github.com/ychalier/hoplite/blob/master/RULES.md),
[2](https://en.wikipedia.org/wiki/Hoplite_(video_game))) ·
Gunfire Reborn ([1](https://gunfirereborn.fandom.com/wiki/Enemies),
[2](https://gunfirereborn.fandom.com/wiki/Category:Bosses),
[3](https://gunfirereborn.fandom.com/wiki/Lu_Wu))

### Second pass

Angband ([1](http://thangorodrim.net/spoilers/monsters_short.html),
[2](https://angband.readthedocs.io/en/latest/guide.html)) ·
Ancient Domains of Mystery ([1](https://ancardia.fandom.com/wiki/Cat_lord),
[2](https://ancardia.fandom.com/wiki/Cats),
[3](http://www.adomgb.info/adomgb-3-6.html)) ·
Dungeons of Dredmor ([1](https://dungeonsofdredmor.fandom.com/wiki/Enemies),
[2](https://dungeonsofdredmor.fandom.com/wiki/Diggle),
[3](https://dungeonsofdredmor.fandom.com/wiki/Arch_Diggle)) ·
Mystery Dungeon 2: Shiren the Wanderer ([1](https://mysterydungeonwiki.com/wiki/Shiren:Mamel_Family),
[2](https://mysterydungeonwiki.com/wiki/Shiren:Pacorepkin_Family),
[3](https://mysterydungeonwiki.com/wiki/Shiren:Original_Monster_Families)) ·
Tangledeep ([1](https://tangledeep.fandom.com/wiki/Bosses),
[2](https://tangledeep.fandom.com/wiki/Champions),
[3](https://tangledeep.fandom.com/wiki/Monsterpedia)) ·
FTL ([1](https://ftl.fandom.com/wiki/Enemy_Ships),
[2](https://ftl.fandom.com/wiki/The_Rebel_Flagship),
[3](https://ftl.fandom.com/wiki/Boarding)) ·
Into the Breach ([1](https://intothebreach.fandom.com/wiki/Vek),
[2](https://intothebreach.fandom.com/wiki/Spider_Leader),
[3](https://intothebreach.fandom.com/wiki/Blobber)) ·
Dwarf Fortress ([1](https://dwarffortresswiki.org/index.php/DF2014:Megabeast),
[2](https://dwarffortresswiki.org/index.php/DF2014:Forgotten_beast),
[3](https://dwarffortresswiki.org/index.php/DF2014:Titan)) ·
Dicey Dungeons ([1](https://diceydungeons.fandom.com/wiki/Enemies),
[2](https://wiki.diceydungeons.com/doku.php?id=enemies),
[3](https://diceydungeons.fandom.com/wiki/Witch)) ·
Hand of Fate ([1](https://handoffate.fandom.com/wiki/Courts),
[2](https://hand-of-fate-2.fandom.com/wiki/Bosses),
[3](https://hand-of-fate-2.fandom.com/wiki/Major_Suits)) ·
Peglin ([1](https://peglin.wiki.gg/wiki/Category:Enemies),
[2](https://peglin.wiki.gg/wiki/Category:Bosses),
[3](https://peglin.fandom.com/wiki/Encirclepedia)) ·
Spelunky Classic ([1](https://spelunky.fandom.com/wiki/Enemies_(Classic)),
[2](https://spelunky.fandom.com/wiki/Category:Spelunky_Classic_Enemies)) ·
UnderMine ([1](https://undermine.wiki.gg/wiki/Bosses_and_Mini_Bosses),
[2](https://undermine.wiki.gg/wiki/Seer,_World's_Heart))

### First pass

Slay the Spire ([1](https://slaythespire.wiki.gg/wiki/Hexaghost),
[2](https://slaythespire.wiki.gg/wiki/Gremlins),
[3](https://slaythespire.wiki.gg/wiki/Slay_the_Spire_2:Monsters)) ·
NetHack ([1](https://nethackwiki.com/wiki/Prayer),
[2](https://nethackwiki.com/wiki/High_priest),
[3](https://nethackwiki.com/wiki/Stealing_from_shops)) ·
The Binding of Isaac ([1](https://bindingofisaacrebirth.wiki.gg/wiki/Devil_Room),
[2](https://bindingofisaacrebirth.wiki.gg/wiki/Angel),
[3](https://bindingofisaacrebirth.wiki.gg/wiki/Downpour)) ·
Enter the Gungeon ([1](https://enterthegungeon.wiki.gg/wiki/Treadnaught),
[2](https://enterthegungeon.wiki.gg/wiki/Shotgun_Kin),
[3](https://enter-the-gungeon-archive.fandom.com/wiki/Bosses)) ·
Risk of Rain ([1](https://riskofrain.wiki.gg/wiki/Monsters),
[2](https://riskofrain2.wiki.gg/wiki/Monsters)) ·
Dead Cells ([1](https://deadcells.wiki.gg/wiki/Bosses)) ·
Hades ([1](https://hades2.wiki.fextralife.com/Bosses),
[2](https://hades2.wiki.fextralife.com/Enemies)) ·
Cult of the Lamb ([1](https://cult-of-the-lamb.fandom.com/wiki/Bosses)) ·
Noita ([1](https://noita.wiki.gg/wiki/Creatures),
[2](https://noita.wiki.gg/wiki/Hiisi)) ·
Caves of Qud ([1](https://wiki.cavesofqud.com/wiki/Creatures),
[2](https://wiki.cavesofqud.com/wiki/Chrome_pyramid)) ·
Shattered Pixel Dungeon ([1](https://pixeldungeon.fandom.com/wiki/Shattered_Pixel_Dungeon/Enemies)) ·
Crypt of the NecroDancer ([1](https://necrodancer.miraheze.org/wiki/Monsters)) ·
Vampire Survivors ([1](https://vampire.survivors.wiki/w/Enemies)) ·
Dungeon Crawl Stone Soup ([1](http://crawl.chaosforge.org/Slime_creature)) ·
Nuclear Throne ([1](https://nuclear-throne.fandom.com/wiki/I.D.P.D.)) ·
Spelunky 2 ([1](https://spelunky.fandom.com/wiki/Bestiary_(2)),
[2](https://spelunky.wiki/wiki/Spelunky_2:Kali_Altar)) ·
Darkest Dungeon ([1](https://darkestdungeon.wiki.gg/wiki/Enemies_(Darkest_Dungeon)),
[2](https://darkestdungeon.wiki.gg/wiki/Bosses_(Darkest_Dungeon))) ·
Monster Train ([1](https://monster-train.fandom.com/wiki/Enemies),
[2](https://monster-train.fandom.com/wiki/Seraph)) ·
Pokémon Mystery Dungeon ([1](https://bulbapedia.bulbagarden.net/wiki/Kecleon_Shop),
[2](https://www.serebii.net/mysteriousdungeon/bosses.shtml)) ·
Cataclysm: DDA ([1](https://cataclysmdda.miraheze.org/wiki/Zombies),
[2](https://srgnis.github.io/cdda-wiki/cdda_wiki/Zombie_master.html)) ·
Cogmind ([1](https://www.moddb.com/games/cogmind/news/robots)) ·
Curse of the Dead Gods ([1](https://curseofthedeadgods.fandom.com/wiki/Enemies),
[2](https://curseofthedeadgods.fandom.com/wiki/Category:Champions_and_Bosses)) ·
Griftlands ([1](https://griftlands.fandom.com/wiki/Enemies),
[2](https://griftlands.fandom.com/wiki/Spark_Barons)) ·
Tales of Maj'Eyal ([1](https://te4.org/wiki/Bill_the_Stone_Troll),
[2](https://te4.org/wiki/Weirdling_Beast),
[3](https://te4.org/wiki/Grand_Corruptor)) ·
Loop Hero ([1](https://loophero.fandom.com/wiki/Enemies)) ·
Wildfrost ([1](https://wildfrost.fandom.com/wiki/Bosses/minibosses)) ·
Deep Rock Galactic: Survivor ([1](https://deeprockgalactic.wiki.gg/wiki/Survivor:Creatures)) ·
Streets of Rogue ([1](https://streetsofrogue.fandom.com/wiki/Gorilla)) ·
Skul ([1](https://skul.fandom.com/wiki/Bosses)) ·
Inscryption ([1](https://inscryption.fandom.com/wiki/Leshy),
[2](https://inscryption.fandom.com/wiki/Uberbots)) ·
Brogue ([1](https://brogue.fandom.com/wiki/Monster_Class),
[2](https://brogue.fandom.com/wiki/Allies)) ·
Mewgenics ([1](https://mewgenics.wiki.gg/wiki/Bosses)) ·
Ball x Pit ([1](https://ballxpit.wiki.gg/wiki/Enemies)) ·
Muck ([1](https://muck.fandom.com/wiki/Category:Boss)) ·
Rogue Legacy 2 ([1](https://rogue-legacy-2.fandom.com/wiki/Bosses)) ·
Brotato ([1](https://brotato.wiki.fextralife.com/Enemies)) ·
Ember Knights ([1](https://emberknights.wiki.gg/wiki/Enemies)) ·
Dungeon Clawler ([1](https://dungeon-clawler.fandom.com/wiki/Enemies)) ·
FORWARD: Escape the Fold ([1](https://forward.fandom.com/wiki/Enemies))
