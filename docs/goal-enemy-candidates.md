# Goal-enemies: the candidate file, and what shipped from it

`docs/goal-candidates.csv` holds **316 audited candidate rows** in the exact
column order of the `enemies` and `bosses` sheets of `tools/Roguelikes.xlsx`.
It was built over four passes of wiki reading and, **as of this change, all
316 rows are pasted into the workbook and generated into `data/`** — the file
is now the record of how each row was chosen rather than a queue waiting to be
pasted.

This document is the companion: what the columns were filled in with, the rules
a row has to pass, what the audit threw out, and what is still open.

## Status

| | Before | After |
|---|---|---|
| `enemies` sheet | 54 rows | **279** |
| `bosses` sheet | 40 rows | **131** |
| `data/enemies2.0/` | 54 `.tres` | **279** |
| `data/bosses2.0/` | 40 `.tres` | **131** |
| Games with a body in the game | 22 | **84** |

Two things are deliberately NOT done, and both are their own pass:

- **No art.** Every one of the 316 rows resolves to no PNG — 223 of the 279
  goal-enemies and most of the bosses now draw a placeholder. A picture dropped
  into `images2.0/enemies/` or `images2.0/bosses/` under the row's `File` name is
  all it takes to light one up; that is what the `File` column is for and why it
  is the PascalCase of the name.

  **The placeholder had to be built to land this**, in two places, and the second
  one was not cosmetic:

  - `BattlefieldView` set `art.modulate = accent` on a TextureRect with no
    texture and called that a "tinted silhouette" — a TextureRect with no
    texture paints nothing, so an artless body was an empty square with its
    health and damage badges floating in it.
  - `ReportChecklist._enemy_icon_rect` returned **null** for a body with no
    picture, and the buff strip (§13) hangs UNDER that chip — so an artless
    body's statuses had nowhere to be drawn and its checklist row quietly
    stopped saying what the board was saying. `test_overworld2` caught it.

  Both now draw the body's **initial** — in the cell's accent on the board,
  sized to its footprint; in the row's tint on the checklist — which is how the
  games this one is played on top of drew their monsters before anybody had art.
  `test_obs_companion`'s "every body has a face" assertion became a **ratchet**
  for the same reason: art coverage may rise and may not fall (98 of 410 today),
  which still catches art that stops resolving without asserting something the
  project has decided is not true yet.
- **No abilities.** `Ability` is `N/A` on all 316. Abilities are authored
  against the `abilities` sheet (§7.6) and guessing them here would only make
  work for whoever does that pass properly.

`tools/_candidates_to_sheet.py` is the paste, kept because it is the thing that
did it: it splits on the `Sheet` column, drops the two staging columns, and
inserts each row after the last row sharing its Type and Difficulty so the
sheets stay grouped the way they already were.

## The file

| | |
|---|---|
| Rows | 316 — **225 enemies, 91 bosses** |
| Games | 80, of which 62 had no body in the game before |
| Columns | `Sheet, Name, Type, Difficulty, Size, Game, Health, Damage, Goal Type, Goal, Ability, File, Tag, Phases` then two staging columns |
| Staging columns | `Confidence` (`ok` / `?`) and `Why this pairing` — not columns the sheets have; `_candidates_to_sheet.py` drops them |

**`python3 tools/check_goal_candidates.py` is the audit as a script**, and CI
runs it. Every rule below that a row can break mechanically — the enums,
`Health` 1, the Damage mapping, the Size grammar (parsed with the generator's
own `parse_size`, not a copy of it), a duplicate `Name` / `File` / `Goal` / id
inside the file, a `Game` the catalog does not spell that way, a `Type` that
disagrees with the game's own — is checked there. Now that the rows have
shipped it also checks the other direction: **every row must still match its
sheet row cell for cell**, so the file and the workbook cannot drift apart
without the build saying so. A row that has NOT shipped is checked the old way
instead — it must not collide with anything already live.
`--stats` prints the tables quoted below. It was written for the second pass,
immediately found five rows the first pass had got wrong, and has gated every
row added since.

Conventions copied off the live rows rather than invented:

- **Health** is `1` on all 94 rows that were already live, so it is `1` here.
- **Damage** is the difficulty index for enemies (1/2/3/4) and `3/5/7/9` for
  bosses. Every row follows that mapping exactly.
- **Difficulty** is `1-Low` … `4-Insane`; **Type** is `Action` / `Deckbuilder` /
  `Strategy` / `Traditional`; **Goal Type** is `Bounty` / `Feat` / `Fetch` /
  `Restriction` / `Discovery` — all title-case, as the generator expects.
- **Size** defaults to `1x1`, bosses to `2x2`, with a handful of deliberate
  exceptions (`Larry Jr.` 1x2, `Wallmonger` and `The Giant` 3x3, `Abyssal
  Serpent` 1x3, the Balatro blinds 1x1 like the five already shipped).
- **File** is the PascalCase of the Name, which is where the art will hang.

## How a row is judged

Six rules, applied to every row in every pass. The first two are the expensive
ones.

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

**3. Boss budget.** A boss here is the tier-change slot, not "this creature is a
boss in its own game" — the live sheet keeps about two per game. The first
draft had 134 bosses and was cut to 67; the file now has 91 across
80 games, and no game is over three. Demotions are not losses: the
workbook already ships elites like `Fungi Beast` and `Shelled Parasite` as
ordinary rows.

**4. Difficulty.** Difficulty is how hard the **goal** is in a normal run, not
how hard the creature is in its own game — "defeat a big cat" is Low even when
the cat is a boss, "clear a floor unseen" is High on an unarmed enemy. The
result tracks the live sheet's own shape:

| | Low | Medium | High | Insane |
|---|---|---|---|---|
| first pass (243) | 109 | 90 | 35 | 9 |
| second pass (+37) | 11 | 15 | 7 | 4 |
| third pass (+21) | 7 | 9 | 4 | 1 |
| fourth pass (+15) | 4 | 6 | 4 | 1 |
| all 316 | 131 | 120 | 50 | 15 |
| live sheet before this (94) | 43 | 32 | 15 | 4 |
| as a share | 41% vs 46% | 38% vs 34% | 16% vs 16% | 5% vs 4% |

The later passes lean a tier harder than the first, because the games they read
are where the genre keeps its long hauls — Angband's level 100, ADOM's emperor
lich, FTL's flagship, POWDER's arch-daemon. That moves the whole file about a
point off the sheet's old shape in each direction, which is close enough to
leave alone rather than pad with filler Lows.

**5. Collisions.** No duplicate `Name`, `File`, `Goal` or slugified id inside
the file or against what was already live — checked by script, not by eye.
Near misses worth knowing:

- NetHack and Enter the Gungeon both have a **High Priest**. Both ship, with
  opposite verbs — NetHack's was reassigned to the **Aleax** so *pray* keeps a
  body and Gungeon's High Priest takes *defeat a priest*.
- Brotato's `Colossus` would have collided with Risk of Rain's, already on the
  sheet. Dropped.
- `Lich` (Gungeon, shipped) and `The Lich` (Loop Hero) generate distinct ids but
  read alike on the HUD. Your call.
- Diablo's **Skeleton King** ships as **King Leoric**, because Ball x Pit's
  crowned undead already had the name.
- Angband's **Grip** and Dredmor's **Diggle** are both the first thing their
  game shows you, and both stayed: one is *defeat a named enemy*, the other
  *defeat an enemy guarding its young*.

**6. Type balance.** The starved pool was **Traditional** — 8 of 94 live rows,
so a run on traditional games drew from NetHack ×4, Crypt ×3, Rogue ×1. The
second-smallest was **Strategy**, 18 rows drawn almost entirely from Mewgenics
and Brutal Orchestra. Each later pass was aimed at whichever was thinnest:

| | Action | Traditional | Deckbuilder | Strategy |
|---|---|---|---|---|
| candidate rows | 124 | 94 | 56 | 42 |

Strategy is the pool where a goal is hardest to write, which is why it stayed
thin longest: the type covers everything from a fortress sim to a four-tile
tactics board, so a goal has to survive both. The ones that work are about
POSITION and UPKEEP rather than about hitting things — *repair something an
enemy has broken*, *defeat an enemy before it reaches you*, *defeat the enemy
that is making the others stronger*.

## Where the rows came from

Four passes, 80 games, every one of them **owned** and already in
`data/games/`. Yield per game falls steadily across the passes for one reason:
the egress proxy blocks the wikis, so every row here was written off a search
summary. The first pass took the games whose rosters search knows by heart; what
is left is games where you have to open the bestiary.

### First pass — 243 rows, 46 games

The bulk of the file, and the one that set every convention above. Its sources
are listed at the end.

### Second pass — 37 rows, 13 games

Aimed at **Traditional** (16 rows) and **Strategy** (9).

| Game | Type | Rows | Wiki |
|---|---|---|---|
| Spelunky Classic | Action | 2 enemies | spelunky.fandom.com |
| UnderMine | Action | 2 bosses | undermine.wiki.gg |
| Dicey Dungeons | Deckbuilder | 2 enemies, 1 boss | diceydungeons.fandom.com |
| Hand of Fate | Deckbuilder | 2 enemies, 1 boss | handoffate.fandom.com |
| Peglin | Deckbuilder | 1 enemy, 1 boss | peglin.wiki.gg |
| Dwarf Fortress | Strategy | 1 enemy, 2 bosses | dwarffortresswiki.org |
| FTL | Strategy | 2 enemies, 1 boss | ftl.fandom.com |
| Into the Breach | Strategy | 2 enemies, 1 boss | intothebreach.fandom.com |
| Ancient Domains of Mystery | Traditional | 2 enemies, 2 bosses | ancardia.fandom.com, adomgb.info |
| Angband | Traditional | 3 enemies, 2 bosses | thangorodrim.net, angband.readthedocs.io |
| Dungeons of Dredmor | Traditional | 2 enemies, 1 boss | dungeonsofdredmor.fandom.com |
| Mystery Dungeon 2: Shiren the Wanderer | Traditional | 3 enemies | mysterydungeonwiki.com |
| Tangledeep | Traditional | 1 enemy | tangledeep.fandom.com |

### Third pass — 21 rows, 11 games

Aimed at **Strategy**, five of eleven games.

| Game | Type | Rows | Wiki |
|---|---|---|---|
| Gunfire Reborn | Action | 1 enemy, 1 boss | gunfirereborn.fandom.com |
| Across the Obelisk | Deckbuilder | 2 enemies | ato.fandom.com |
| Backpack Hero | Deckbuilder | 1 enemy, 1 boss | backpackhero.wiki.gg |
| Dome Keeper | Strategy | 2 enemies | domekeeper.wiki.gg |
| Legend of Keepers: Career of a Dungeon Manager | Strategy | 2 enemies | legendofkeepers.fandom.com |
| Ring of Pain | Strategy | 1 boss | ring-of-pain.fandom.com |
| Shogun Showdown | Strategy | 2 enemies, 1 boss | shogunshowdown.wiki.gg |
| Slice & Dice | Strategy | 2 enemies | slice-and-dice.fandom.com, minmax.wiki |
| Hoplite | Traditional | 2 enemies | the game's own rules reference |
| Jupiter Hell | Traditional | 2 enemies | jupiterhell.fandom.com |
| Rift Wizard | Traditional | 1 enemy | riftwizard.fandom.com |

**Legend of Keepers is the one worth reading.** You play the dungeon, so its
*enemies* are the heroes raiding you — which is where `Defeat a hero` comes
from, a goal the file never had a body for. **Hoplite** is the other: small
enough that each demon is a single rule, and two of those rules became goals
nothing else asks for — *beat a ranged enemy by standing next to it* (its Archer
cannot attack an adjacent tile at all) and *use an enemy as cover* (its Wizard
will not fire through another demon).

### Fourth pass — 15 rows, 10 games

| Game | Type | Rows | Wiki |
|---|---|---|---|
| Diablo | Action | 2 bosses | diablo.fandom.com |
| Don't Starve | Action | 1 enemy, 1 boss | dontstarve.wiki.gg |
| Halls of Torment | Action | 2 enemies | hot.fandom.com |
| Wizard of Legend | Action | 1 enemy | wizardoflegend.fandom.com |
| Shotgun King: The Final Checkmate | Strategy | 2 enemies, 1 boss | shotgun-king.fandom.com |
| Super Auto Pets | Strategy | 1 enemy | superautopets.fandom.com |
| The Last Spell | Strategy | 1 boss | thelastspell.fandom.com |
| Dungeonmans | Traditional | 1 enemy | dungeonmans.fandom.com |
| Powder | Traditional | 1 boss | powderrl.fandom.com, roguebasin.com |
| Torneko's Great Adventure: Mystery Dungeon | Traditional | 1 enemy | mysterydungeonwiki.com, dragonquest.fandom.com |

The last pass also **closed the `Confidence` column**. Fourteen rows from the
first pass were marked `?` — the creature or the detail could not be confirmed
— and every one was checked against a wiki page: Aleax, Voidling, Skeletal
Juggernaut, Chicken Walker, Bamboozle, Krunker, Brogue's captive Ogre, Death
Metal, Byarrrith and Halpharrr, Plague Bringer, The Architect, Bee Queen,
Avowed Gladiator and Ragewing Assassin. All fourteen turned out to be real
creatures and all fourteen kept their goal; several `Why this pairing` notes
were rewritten to say what the page actually says. **Two were filed under the
wrong game**: Avowed Gladiator and Ragewing Assassin are **Monster Train 2**
enemies, not Monster Train. The file now carries no `?` rows at all.

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

## What was cut

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

- **Art for all 316 of them.** Nothing else in this list matters as much: a
  goal-enemy with no picture is a placeholder on the board.
- **Abilities.** `Ability` is `N/A` on every row, so 316 bodies walk and swing
  and do nothing else. That is a pass against the `abilities` sheet (§7.6).
- **Use star power** — no enemy in any of the 80 games carries it.
- **Drink milk**, **make a cake**, **smoke something** — all three are ordinary
  Cataclysm: DDA items, but no body on its bestiary is *about* them yet.
- **Under-read games.** Tangledeep, Peglin, Spelunky Classic, Dungeon Clawler
  and UnderMine each gave up one or two rows before search stopped surfacing
  bodies, and each plainly has more — Tangledeep's whole Monsterpedia, Peglin's
  Slimedrop line and its eight bosses, UnderMine's peons and bombers. A
  search-quality limit, not a content limit.
- **The later passes are boss-light** — the third ran 4 bosses in 21 rows —
  because search surfaces a small game's ordinary roster before its bosses.
- **No Insane ENEMY exists for Action or Deckbuilder.** Both types have Insane
  bosses (7 and 1) and no ordinary body at that tier, which is how it was before
  these rows landed too — the file added 15 Insane rows and every one went to
  Strategy, Traditional, or a boss slot. Worth an authoring pass of its own: an
  Insane goal on an ordinary Action body is a hard thing to write, which is
  presumably why nobody has.
- **Games that produced nothing**: Brutal Orchestra and Gnomes (no roster
  surfaced), Fights in Tight Spaces, Moonlighter, Roguebook, Deck of Ashes,
  Dicefolk and Neon Abyss (every body landed on a row that already exists, or no
  creature could be named at all).

## Sources

Wikis read, by game. Direct fetching is blocked from this environment — the
egress proxy refuses fandom, wiki.gg and the rest alike — so all four passes
read these through search results rather than page by page.

### Fourth pass

Shotgun King: The Final Checkmate ([1](https://shotgun-king.fandom.com/wiki/White_Pieces),
[2](https://shotgun-king.fandom.com/wiki/Pawn),
[3](https://shotgun-king.fandom.com/wiki/Queen)) ·
Diablo ([1](https://diablo.fandom.com/wiki/The_Butcher_(Diablo_I)),
[2](https://diablo.fandom.com/wiki/Skeleton_King_(Diablo_I)),
[3](https://diablo-archive.fandom.com/wiki/Monsters_(Diablo_I))) ·
Wizard of Legend ([1](https://wizardoflegend.fandom.com/wiki/Enemies),
[2](https://wizardoflegend.fandom.com/wiki/Master_Sura)) ·
Halls of Torment ([1](https://hot.fandom.com/wiki/Category:Boss),
[2](https://hot.fandom.com/wiki/Forgotten_Viaduct),
[3](https://hot.fandom.com/wiki/Haunted_Caverns)) ·
The Last Spell ([1](https://thelastspell.fandom.com/wiki/Bosses),
[2](https://thelastspell.fandom.com/wiki/Monsters)) ·
Don't Starve ([1](https://dontstarve.wiki.gg/wiki/Monster),
[2](https://dontstarve.wiki.gg/wiki/Deerclops),
[3](https://dontstarve.wiki.gg/wiki/Category:Boss_Monsters)) ·
Super Auto Pets ([1](https://superautopets.fandom.com/wiki/Pets),
[2](https://superautopets.fandom.com/wiki/Whale)) ·
Dungeonmans ([1](https://dungeonmans.fandom.com/wiki/Monsters)) ·
Torneko's Great Adventure ([1](https://mysterydungeonwiki.com/wiki/Torneko_1:Monster),
[2](https://dragonquest.fandom.com/wiki/Torneko%27s_Great_Adventure)) ·
Powder ([1](https://powderrl.fandom.com/wiki/Overview),
[2](https://www.roguebasin.com/index.php/POWDER))

Pages read to close the `?` column: Wildfrost
([1](https://wildfrost.fandom.com/wiki/Bosses/minibosses)) · Ember Knights
([1](https://ember-knights-game.fandom.com/wiki/Praxis)) · Monster Train 2
([1](https://monstertrain2.miraheze.org/wiki/Avowed_Gladiator),
[2](https://monstertrain2.miraheze.org/wiki/Chosen_Assassin)) · Cataclysm: DDA
([1](https://cddawiki.danmakudan.com/wiki/index.php/Skeletal_juggernaut)) ·
Rogue Legacy 2 ([1](https://gamerant.com/rogue-legacy-2-how-defeat-void-beasts-byarrrith-halpharrr/)) ·
Crypt of the NecroDancer ([1](https://necrodancer.miraheze.org/wiki/Death_Metal)) ·
Dungeon Clawler ([1](https://dungeon-clawler.fandom.com/wiki/Enemies)) · NetHack
([1](https://nethackwiki.com/wiki/Minion), [2](https://nethackwiki.com/wiki/Aleax)) ·
Risk of Rain 2 ([1](https://riskofrain2.wiki.gg/wiki/Voidling)) · Brogue
([1](https://brogue.fandom.com/wiki/Cage), [2](https://brogue.fandom.com/wiki/Allies))

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
