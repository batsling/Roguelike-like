# Goal-enemy candidates

`docs/goal-candidates.csv` is the deliverable: **243 audited candidate rows** in
the exact column order of the `enemies` and `bosses` sheets of
`tools/Roguelikes.xlsx`, ready to paste and regenerate from. This file is the
companion — what the columns were filled in with, what the audit threw out, and
what is still unresolved.

Nothing here is wired up. `data/` is untouched.

## The file

| | |
|---|---|
| Rows | 243 — **176 enemies, 67 bosses** |
| Games | 44, of which 24 are new to the project |
| Columns | `Sheet, Name, Type, Difficulty, Size, Game, Health, Damage, Goal Type, Goal, Ability, File, Tag, Phases` then two staging columns |
| Staging columns | `Confidence` (`ok` / `?`) and `Why this pairing` — **delete both before pasting**; the sheet has no such columns |

Split on the `Sheet` column: `enemies` rows go to the `enemies` sheet, `bosses`
rows to `bosses` (which has the extra trailing `Phases`, left blank —
Guillatina is currently the only multi-phase boss).

Conventions copied off the live rows rather than invented:

- **Health** is `1` on all 94 existing rows, so it is `1` on all 243.
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
| candidates (243) | 109 | 90 | 35 | 9 |
| live sheet (94) | 43 | 32 | 15 | 4 |
| as a share | 45% vs 46% | 37% vs 34% | 14% vs 16% | 4% vs 4% |

**5. Collisions.** Checked by script against `data/`, and inside the candidate
set: **no duplicate `Name`, no duplicate `File`, no duplicate `Goal`, and no
collision with any of the 94 existing rows** on any of the three. Two near
misses worth knowing:

- NetHack and Enter the Gungeon both have a **High Priest**. Both ship, with
  opposite verbs — NetHack's was reassigned to the **Aleax** so *pray* keeps a
  body and Gungeon's High Priest takes *defeat a priest*.
- Brotato's `Colossus` would have collided with Risk of Rain's, already on the
  sheet. Dropped.
- `Lich` (Gungeon, shipped) and `The Lich` (Loop Hero, candidate) generate
  distinct ids but read alike on the HUD. Your call.

**6. Type balance.** The starved pool was **Traditional** — 8 of 94 live rows,
so a run on traditional games was drawing from NetHack ×4, Crypt ×3, Rogue ×1.
The candidates add **70 traditional rows** across ten traditional roguelikes
(NetHack, Crypt, Rogue, Brogue, DCSS, Caves of Qud, Shattered PD, Cogmind,
Cataclysm: DDA, Tales of Maj'Eyal, Pokémon Mystery Dungeon). Action is still the
biggest pool at 111, matching the sheet's existing lean.

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

Cut as true duplicates: a second freeze (Stygian Guard), a second splitter (Pink
Jelly), a second thief (Brogue Monkey), a second summoner (Ogre Shaman, Brood
Nexus, Reptomancer), a second shrink (SoR shrink ray), a second drunk (Smith), a
second level-30 (ToME prodigies), a second do-not-backtrack (Loop Hero's loop), a
second no-magic (ToME antimagic), a second two-boss fight (Donu and Deca), a
second dragon (Dragon Prince), and Brotato's `Colossus`.

## Still open

- **Use star power** — no enemy in any of the 44 games carries it.
- **Drink milk**, **make a cake**, **smoke something** — all three are ordinary
  Cataclysm: DDA items, but no body on its bestiary is *about* them yet.
- **14 rows are marked `?`** in the Confidence column: the creature or the
  detail could not be confirmed against a wiki page from this session. They are
  spread thin (Monster Train ×2, CDDA ×2, Wildfrost ×2, Ember Knights ×2, and
  singles elsewhere) and each needs a look before it ships.
- Every game whose wiki lists enemies as a stub — **Dungeon Clawler** especially
  — has more to give than the two rows here.
- **Brutal Orchestra** and **Gnomes** are on the sheet but produced nothing this
  pass; neither wiki surfaced a usable roster through search.

## Sources

Wikis read for this pass, by game. Direct fetching is blocked from this
environment, so these were read through search results rather than page by page;
that is the reason for the `?` column.

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
