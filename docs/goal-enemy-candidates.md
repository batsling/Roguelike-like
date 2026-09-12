# Goal → enemy candidates

Research notes for pairing goal prompts with real roguelike enemies and bosses,
in the same style as the rows in `data/enemies2.0/` and `data/bosses2.0/` (a real
creature whose flavour or mechanic *is* the goal).

Three parts. **Part 1** answers the ~120 prompts in the September 2026 batch.
**Part 2** goes the other way: sixteen games this project has never sourced from,
each roster read for the goals *it* suggests. **Part 3** does the same for the
twenty games already on the sheet. Nothing here is wired up: it is a shortlist to
paste into the `enemies` / `bosses` sheets of `tools/Roguelikes.xlsx` and
regenerate from.

## How to read it

- **type** is the suggested `goal_type` — `bounty` / `feat` / `fetch` /
  `restriction` / `discovery`, the five the project already uses. **tier** is
  `difficulty` — `LOW` / `MED` / `HIGH` / `INSANE`, the resource's four.
- **Every pick is a creature you meet on the field** — an enemy, a boss or a
  mini-boss — unless it is marked **◆NPC** (a non-hostile character) or
  **◆blind** (a Balatro blind, which the sheet already ships as bosses:
  `Cerulean Bell`, `The Club`, `The Goad`, `The Head`, `The Window`). Items,
  rooms, statuses, buildings and player abilities were stripped out in the audit
  pass — see [Audit](#audit-what-got-thrown-out) for what went and what replaced
  it.
- **?** means the creature or the detail is unconfirmed against a wiki. Check
  before it goes in the sheet.
- Creatures already in `data/` are not reused; where a prompt's obvious body was
  taken, the tie names the one that took it.

---

# Part 1 — the prompt list

## 1. Religion, ritual, pacts

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| pray | **High Priest** | NetHack | Head of all religious activity for a god; the temple he tends is where `#pray` happens | feat |
| Become religious | **The One Who Waits** | Cult of the Lamb | The final boss who makes you a cult leader | feat |
| Worship at an altar | **Aligned Cleric** | NetHack | Tends the co-aligned temple altar where sacrifice and worship happen | feat |
| Hexagon — ritual w/ multiple steps | **Hexaghost** | Slay the Spire | Activate → Divider → six flames lit one per attack → Inferno. A literal multi-step ritual on a six-sided body | feat |
| Make a devilish pact | **Satan** | The Binding of Isaac | Sheol's boss; Devil Rooms trade heart containers for items | feat |
| Trade health for resources | **Krampus** | The Binding of Isaac | The Devil Room's boss — the room where items cost heart containers | feat |
| Deal holy damage | **Uriel** (or **Gabriel**) | The Binding of Isaac | Angel Room mini-boss; fires beams of light in a cross pattern | feat |

## 2. Undead, corpses, resurrection

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Defeat skeleton | **Skeleton** (Black / White) | Crypt of the NecroDancer | The genre's baseline skeleton; the three Ball x Pit skeletons in `data/` are all "defeat with a ball" | bounty |
| Defeat zombie | **Zombie** | Crypt of the NecroDancer | Slow, relentless, never stops walking at you | bounty |
| Resurrect yourself 3 times and win | **Awakened One** | Slay the Spire | Dies, then stands back up with Curiosity | feat |
| Attack a deceased enemy | **Necromancer** | Shattered Pixel Dungeon | Raises a skeleton from a corpse and re-raises it | feat |
| Gain an extra life | **Ghost** | Crypt of the NecroDancer | Killed, then returns as the thing it was | feat |
| Bury a body | **Mummy** | NetHack | Wrapped and interred; graves are a real dungeon feature you dig into | feat |

## 3. Mushrooms, growth, splitting

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Obtain a mushroom | **Violet Fungus** | NetHack | A mushroom that fights back; its corpse is the mushroom you walk away with. `Fungi Beast` is taken by "Get infected" | fetch |
| Double your max health | **Slime Creature** | Dungeon Crawl Stone Soup | Two merge into a large slime creature, three into a very large one — HP doubles as they combine | feat |
| Grow in size | **Monster Lord** (any "lord" variant) | Crypt of the NecroDancer | Lords are twice the size of their counterpart with doubled HP and damage | feat |
| Attack X enemies at a time | **Larry Jr.** | The Binding of Isaac | A segmented worm — one enemy that is many targets | feat |

## 4. Footprint, formation, multi-target

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Gremlins could take up multiple spaces | **Gremlin Nob** | Slay the Spire | The oversized gremlin — the natural 2x2 body beside the 1x1 gang | feat |
| Taunt an enemy | **Gremlin Nob** | Slay the Spire | Enrage: gains Strength every time you play a Skill | feat |
| Have 5 of the same item | **Fat Gremlin** | Slay the Spire | One of the five drawn from the same small pool — doubles and triples are routine | fetch |
| Spiked — kill an enemy that damages you back | **Spiker** | Slay the Spire | Act 3 enemy behind Thorns: hitting it hurts you | bounty |
| | **Mad Gremlin** | Slay the Spire | Gains 1 Strength whenever it takes attack damage | bounty |
| Writhing Mass — randomly changes when you fail | **Writhing Mass** | Slay the Spire | Rerolls its intent and gains block every time you hit it | discovery |
| Have at least one ally, don't let them die / Centurion and Mystic | **Centurion and Mystic** | Slay the Spire | The Mystic heals and buffs the Centurion; kill the healer and the pair falls apart | feat |
| Attack all enemies on screen at once | **The Collector** | Slay the Spire | Summons torch heads continuously — the fight that exists to be swept | feat |
| Do 3 things at the same time (StS Act 3) | **Sentry** | Slay the Spire | Fought as a row of three, alternating Bolt and Beam — three problems on one turn | feat |

> "Attack all enemies on the screen at once" and "Attack 5+ or all enemies on
> screen at once" are the same goal. Collapse before it reaches the sheet.

## 5. Restrictions

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Win without melee physical attacks | **Floating Eye** | NetHack | The canonical never-melee-this monster: its passive gaze paralyses you | restriction |
| Beat a run without moving | **Oklob Plant** | Dungeon Crawl Stone Soup | Rooted forever and still lethal | restriction |
| Beat a run without taking damage | **The Concierge** | Dead Cells | The first boss, whose whole fight is a dodge pattern | restriction |
| Do not equip headgear if possible | **Knight Bullet Kin** | Enter the Gungeon | A bullet that survives on its helmet — shoot the helmet off and it dies | restriction |
| Get naked | **Nymph** | NetHack | Charms you into handing over worn armour, then teleports away with it | restriction |
| Do not kill any innocents | **Watchman** | NetHack | Peaceful until you swing; killing one is a murder and turns the Watch hostile | restriction |
| Use only one hand | **The Needle** ◆blind | Balatro | Play only 1 hand | restriction |
| Win with a negative modifier | **The Manacle** ◆blind | Balatro | −1 hand size for the blind | restriction |
| Don't use consumables | **The Water** ◆blind | Balatro | Start with 0 discards | restriction |
| Never skip an offered reward | **Greed** | The Binding of Isaac | The boss that takes everything on offer | restriction |
| Never purchase more than 2 things in a shop | **Super Greed** | The Binding of Isaac | Greed's escalation, a shop-flavoured body for a shop rule | restriction |
| Always choose highest difficulty | **Providence** | Risk of Rain | Final boss at the top of a difficulty bar that never stops climbing | restriction |
| Kill every enemy you run into | **I.D.P.D. Elite** | Nuclear Throne | They come through a portal specifically to find you | restriction |

## 6. Items: upgrade, downgrade, steal, hoard

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Upgrade a weapon or item | **Black Pudding** | NetHack | Corrodes your weapon every time you hit it — the monster that makes keeping gear upgraded the whole run | feat |
| Forge a weapon | **Gronk** | Muck | The boss whose drop is the crafting path to the game's best weapon | feat |
| Enchant an item 5+ times | **Warlock** | Shattered Pixel Dungeon | Its darts degrade what you carry; stacking enchantment anyway is the counter-goal | feat |
| Get an item or ability downgraded | **Disenchanter** | NetHack | Its touch strips enchantment off what you wield or wear | feat |
| | **Mind Flayer** | NetHack | Eats an intrinsic straight out of your head | feat |
| Steal an item from a shop | **Keystone Kops** | NetHack | Spawn the moment you leave a shop without paying and chase you. `Charon` holds "Steal from a shop" | feat |
| Obtain 5 max tier items in one run | **Aurelionite** | Risk of Rain 2 | The Halcyon Seed / red-item boss you fight to top out your inventory | fetch |
| Get some trash | **Chubs 'n' Nubs** | Mewgenics | The final encounter of The Junkyard — the boss made of what got thrown away | fetch |
| Acquire a diamond | **Golden Monkey** | Spelunky 2 | Drops gems when it is killed; the reason to chase one at all | fetch |
| Mine an ore | **Glyphid Praetorian** | Deep Rock Galactic: Survivor | A large melee glyphid that digs through terrain | fetch |
| Open 10 locked doors | **Mimic** | Shattered Pixel Dungeon | A locked chest that turns out to be a monster | feat |
| Break down a door | **Minotaur** | Crypt of the NecroDancer | Charges in a straight line and smashes through what is in the way | feat |
| Break through a wall | **Wallmonger** | Enter the Gungeon | A boss that *is* the wall | feat |

## 7. Machines, vehicles, construction

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Pilot a vehicle | **Treadnaught** | Enter the Gungeon | A tank piloted by a Tanker that got lucky and found it — the driver is visible and shootable | feat |
| Pilot a flying vehicle | **Xi Construct** | Risk of Rain 2 | A hovering machine that fights as a flying platform | feat |
| Repair a vehicle | **DM-200** | Shattered Pixel Dungeon | Dwarven machinery still running long after its keepers died | feat |
| Fix a machine | **DM-300** | Shattered Pixel Dungeon | The broken mining machine boss | feat |
| Destroy a building | **The Giant** | Dead Cells | A tier-2 boss large enough that the arena is part of the fight | feat |
| Build a house | **Goblin Leader** | Loop Hero | Spawns from a goblin camp *you* placed on the road — the only body on this list that appears because you built something | feat |

## 8. Water, liquids, weather, states of matter

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Touch water | **Strider** | The Binding of Isaac (Downpour) | Downpour is waist-deep water throughout, and Striders swim it — including over pits | feat |
| Enter a sewer | **Dingle** | The Binding of Isaac | The sewage boss (name from "dingleberry"). `Flushmaster` covers flushing | discovery |
| Take a bath or shower | **Rainmaker** | The Binding of Isaac (Downpour) | The boss of the flooded floor, who brings the rain down on you | feat |
| Change the weather | **Ukko** | Noita | Named for the Finnish god of the heavens; a thunder mage who brings the storm | feat |
| Carry 4 different liquids at once | **Slog of the Cloaca** | Caves of Qud | A unique creature made of the sludge of a game whose world model is liquids mixing | fetch |
| Drink a mystery liquid | **Ylialkemisti** | Noita | The high alchemist — unlabelled flasks, unpredictable results | feat |
| Become all 3 states of matter | **Limatoukka** | Noita | Noita's material sim is the only place this is literal. `Ice Slime` and `Lava Slime` hold two of the three | feat |

## 9. Time, speed, one-turn kills

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Defeat a boss in one second or one turn | **Gas Spore** | NetHack | Kill it and it detonates for enormous damage — the whole creature resolves in one hit | bounty |
| Beat the clock | **The Time Keeper** | Dead Cells | The boss built around time and its reversal | bounty |
| Have a character reach level 30 | **Death** (the Reaper) | Vampire Survivors | Arrives at the 30-minute mark — the game's hard timer with a scythe | bounty |
| Complete a weekly/daily run | **Deep Blues** | Crypt of the NecroDancer | The chess boss — the same puzzle for everyone who plays that day | feat |

## 10. Pets, allies, taming

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Pet a pet | **Cerberus** | Hades | You can pet the dog; in Hades II he returns as Infernal Cerberus and you fight him | feat |
| Feed an animal | **Little Dog** | NetHack | Feeding is how a pet stays yours | feat |
| Tame an enemy | **Leshy** | Cult of the Lamb | Darkwood's bishop, in the game where the defeated are indoctrinated into your flock | feat |
| Catch 5 creatures | **Kallamar** | Cult of the Lamb | Anchordeep's bishop — the water region, and the game's fishing | fetch |
| Do not win alone | **Theseus and the Minotaur** | Hades | Two bosses in one arena; the fight is about a pair that will not be split | feat |
| Have an enemy defeat 3 enemies | **Medusa** | NetHack | Her gaze does not care who is looking — she kills her own floor | feat |

## 11. Crossovers, meta, achievements

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Encounter an outside IP | **Dracula** | Dead Cells (Return to Castlevania) | A different studio's icon in a Dead Cells boss arena | discovery |
| Play a game in another language | **Kolmisilmä** | Noita | Every creature is named in Finnish and never translated — Suomuhauki is "scaled pike", not "dragon" | discovery |
| Achievement only 5% of players have | **Chrome Pyramid** | Caves of Qud | Highest-level non-unique creature in the game, surpassed only by 0lam — and killing one grants an achievement | bounty |
| Obtain a new achievement | **Hush** | The Binding of Isaac | The hidden boss behind the Blue Womb timer | bounty |
| Get 10 achievements in one run | **Delirium** | The Binding of Isaac | Shapeshifts through every boss in the game in one fight | feat |
| Enter a void | **Delirium** | The Binding of Isaac | Lives on The Void, the floor made of every other floor | discovery |
| Unlock a new character | **Ultra Greed** | The Binding of Isaac | Greed Mode's finale, and the unlock engine for half the roster | feat |
| Play as a character that looks like you | **Johannes** | Rogue Legacy | The final boss is your own ancestor | discovery |
| Beat a mini-game or a game inside a game | **The Resourceful Rat** | Enter the Gungeon | His second phase is a Punch-Out-style boxing match inside the boss fight | feat |
| Beat a game you'd give an 8+ | **Hades** (Lord of the Dead) | Hades | The final boss of the run everyone gives a 9 | bounty |
| Lose a run, do 1 push-up | **The Fallen** | The Binding of Isaac | Splits into two smaller copies when killed — charges you extra for every ending | feat |

## 12. Damage, crits, weapons

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Deal damage equal to your block | **Shield Gremlin** | Slay the Spire | Spends its existence handing out block | feat |
| Get maximum crit chance | **Amalaric Sniper** | Vampire Survivors | Fires a single aimed shot from off-screen for a huge chunk | feat |
| Defeat an enemy with a shotgun | **Shotgun Kin** / **Shotgrub** | Enter the Gungeon | Every Shotgun Kin variant has its own name; Shotgrub walks at you firing waving spreads | bounty |
| Overkill an enemy by double their HP | **Big Dog** | Nuclear Throne | The scrapyard boss you either delete or lose to | bounty |
| Improvised weapon | **Cockatrice** | NetHack | The famous improvisation: wield the corpse (with gloves) and petrify what you touch | feat |
| Defeat an enemy without violence | **Blobulin** | Enter the Gungeon | What the Devolver turns enemies into — you win by making it harmless | bounty |
| Have the number 100,000 appear | **Violet Vessel** ◆blind | Balatro | A finisher blind with a score requirement big enough to put six figures on screen | discovery |

## 13. Health, curses, the body

| Prompt | Pick | Game | The tie | type |
|---|---|---|---|---|
| Beat a boss with 1 health left | **The Lamb** | The Binding of Isaac | The final boss whose head keeps fighting after the body is gone | bounty |
| Go from 1 to max health | **Goo** | Shattered Pixel Dungeon | Regenerates in the water it sits in | feat |
| Reduce max health by half | **Mega Satan** | The Binding of Isaac | The end of the Devil-deal road, where max health is the currency | feat |
| Get hexed or cursed | **Hecate** | Hades II | The Witch of the Crossroads fights with hexes | feat |
| Puke | **Chub** | The Binding of Isaac | Eats and spits — the boss you can feed things to | feat |
| Defeat your parent | **Mom** | The Binding of Isaac | The parent, in the game named for a parent. `Mom's Heart` is taken by "Break a Heart" | bounty |
| Kill a parent | **Hades** (Lord of the Dead) | Hades | Zagreus' father, fought at the exit | bounty |
| Make someone cry | **Blue Baby (???)** | The Binding of Isaac | A crying child who attacks with his tears | feat |
| Destroy a planet | **Mithrix** | Risk of Rain 2 | Beat him on the moon of Petrichor V and it comes apart while you run for the ship | feat |
| Defeat a green creature | **Heket** | Cult of the Lamb | Anura's bishop — an enormous green frog | bounty |
| Read a book | **Book of Stabbing** | Slay the Spire | An Act 2 enemy that is a book | feat |
| Skip the tutorial | **Skelly** ◆NPC | Hades | The training-room dummy you are free to walk straight past | restriction |
| Train something to win/be fast/be strong | **Skelly** ◆NPC | Hades | Same body, other half: he exists to be practised on and rewards you for hitting targets | feat |

---

# Part 2 — sixteen more wikis, read for the goals they suggest

Every game below is one `data/` has never sourced from.

> **Worth noticing.** The live roster is 44 action, 27 deckbuilder, 23 strategy
> and **8 traditional**. Traditional is the starved pool — a run on traditional
> games draws from NetHack ×4, Crypt ×3, Rogue ×1. Six of the sixteen below are
> traditional roguelikes.

## Spelunky 2 — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Witch Doctor** | HIGH | feat | Sacrifice a creature you defeated | |
| **Vampire** | LOW | fetch | Drink blood | |
| **Olmec** | HIGH | bounty | Defeat an enemy you cannot damage | |
| **Angry Shopkeeper** | HIGH | feat | Get marked as a thief and finish the level anyway | |
| **Ghost** | MED | restriction | Stay on a level longer than it wants you to | |
| **Qilin** | LOW | feat | Ride an animal | |
| **Damsel** ◆NPC | MED | fetch | Carry a rescued NPC all the way to the exit | |
| **Golden Monkey** | MED | fetch | Acquire a gem or a diamond | |

Witch Doctors are worth double favour at Kali's altar, and pets are worth the
most of anything — the sacrifice goal costs you something either way. Olmec is
*indestructible*: the mattock and bombs do nothing, so "defeat what you cannot
damage" is literal.

## Darkest Dungeon — strategy

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **The Collector** | MED | fetch | Fill your inventory to its last slot | |
| **The Shambler** | HIGH | restriction | Play a whole level with no light source | |
| **Swine Prince** | MED | feat | Beat a boss by killing its small companion first | |
| **Madman** | MED | feat | Survive an enemy that never attacks you directly | |
| **The Countess** | HIGH | feat | Beat a boss while diseased or afflicted | |
| **Bone Courtier** | HIGH | restriction | Beat a boss without letting it summon anything | |
| **The Fanatic** | HIGH | feat | Lose a party member permanently and finish anyway | |
| **Thing From The Stars** | HIGH | discovery | Fight something that came from outside the world | |

The Collector ambushes when 13+ inventory slots are full; the Shambler ambushes
at torch level 0. Both are enemies *summoned by how you play* — exactly the
shape a goal wants. The Madman deals only stress, never damage.

## Monster Train — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Seraph** | HIGH | restriction | Win a fight where the enemy sets an extra rule | |
| **Lightwing** | HIGH | restriction | Defend one thing that must never be touched | |
| **Seraph the Diligent** | MED | feat | Upgrade the same unit three times | |
| **Avowed Gladiator** | MED | feat | Fight on more than one battlefield at once | ? |
| **Ragewing Assassin** | MED | bounty | Defeat the enemy that goes straight past your front line | ? |

Seraph spawns one Lightwing every round and they go for the pyre — the defence
goal belongs to the thing attacking it, not to the pyre. Seraph's variants (the
Temperant, the Chaste, the Diligent, the Patient) each impose a different rule.

## Pokémon Mystery Dungeon — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Kecleon** | INSANE | bounty | Defeat a shopkeeper | |
| **Groudon** | HIGH | bounty | Defeat an enemy with ten times your health | |
| **Zapdos** | MED | bounty | Defeat an enemy you can then recruit | |
| **Rayquaza** | HIGH | bounty | Defeat a boss on your first attempt | |
| **Primal Dialga** | HIGH | discovery | Be rescued, or rescue someone else's failed run | ? |

Rob a Kecleon shop and the floor fills with **extremely powerful Kecleon moving
at double speed** — an honest INSANE tier, and theft is the only way to recruit
one. Groudon sits on 1600+ HP in Magma Cavern. The rescue system — a failed run
leaves a code another player can answer — has no equivalent anywhere on this
list.

## Cataclysm: Dark Days Ahead — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Zombie Master** | HIGH | discovery | Watch an enemy upgrade another enemy | |
| **Shocker Zombie** | LOW | bounty | Defeat an enemy that shocks you | |
| **Boomer** | LOW | feat | Get covered in something and keep fighting | |
| **Zombie Hulk** | HIGH | bounty | Defeat an enemy that knocks you through a wall | |
| **Mi-go** | HIGH | feat | Permanently change your own body | |
| **Skeletal Juggernaut** | HIGH | discovery | Play long enough that the enemies get worse | ? |
| **Chicken Walker** | MED | bounty | Defeat a walking machine | ? |

The zombie master *transforms* ordinary zombies into spitters and shockers, and
evolution is a real clock — hordes upgrade based on how long since the
Cataclysm. Mi-go appear in labs and temples and are the game's body-horror
surgeons. CDDA is also the only game here that can honestly carry **drink
milk**, **make a cake** and **smoke something**; those are ordinary recipes, and
still need bodies off the bestiary.

## Cogmind — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Behemoth** | INSANE | bounty | Defeat an enemy that takes up four spaces | |
| **Watcher** | HIGH | restriction | Clear a floor without ever being spotted | |
| **Programmer** | HIGH | discovery | Watch an enemy turn one of your allies against you | |
| **Hunter** | MED | discovery | Be tracked across floors by a pair that works together | |
| **Swarmer** | LOW | feat | Be surrounded on every side at once | |
| **Sentry** | LOW | bounty | Defeat an enemy that outguns you but cannot chase | |
| **Operator** | MED | feat | Hack a machine into doing what you want | |
| **Hauler** | HIGH | restriction | Win using only equipment taken off enemies | |
| **Recycler** | LOW | fetch | Get some scrap | |

Behemoths take up **four tiles instead of one** — the cleanest fit anywhere here
for the project's footprint system (§7.3). Watchers are unarmed and exist purely
to report you. Programmers corrupt other robots with EM weaponry, including
yours.

## Curse of the Dead Gods — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Xucat' (the Witch)** | HIGH | feat | Carry four curses at the same time | |
| **Xak'olchir (Blood Hunter)** | LOW | feat | Pay for something with your own blood | |
| **Champion of Death** | MED | bounty | Defeat a champion to have a curse lifted | |
| **Dreadful Offspring** | HIGH | feat | Clear a room where every kill makes more enemies | |
| **Headless Guardian** | LOW | bounty | Defeat something that has already lost its head | |
| **The Wicked Twins** | HIGH | bounty | Defeat two bosses that share one fight | |
| **Infernal Jaguars** | LOW | bounty | Defeat a big cat | |
| **Malok paal (the Flesh Monstrosity)** | MED | bounty | Defeat something stitched together from other creatures | |

Corruption fills by opening doors, making blood offerings and taking dark hits;
you hold four curses before the fifth and final one lands, and the only cures
are killing a champion or giving up a cursed weapon.

## Griftlands — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Kashio** | MED | feat | Win an argument instead of a fight | |
| **Fellemo** | HIGH | feat | Turn someone sent to kill you into an ally | |
| **Plocka 'The Swab'** | HIGH | bounty | Break someone's will without hurting them | |
| **Jake Smuggler** | LOW | fetch | Take a contract and complete it | |
| **Arint** | LOW | discovery | Make an enemy who remembers you next run | |

Negotiation is a full parallel combat system — losing it starts a real fight,
winning it skips one. Griftlands is the only game here where "beat an enemy
without violence" is a *system* rather than a trick. All five named above are
Spark Barons or Jakes, i.e. people you actually fight or argue with.

## Tales of Maj'Eyal — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Weirdling Beast** | HIGH | bounty | Out-damage an enemy that heals to full | |
| **Ukruk the Fierce** | HIGH | feat | Survive a fight you were meant to lose | |
| **Bill the Stone Troll** | MED | feat | Unlock something permanent for every future run | |
| **Grand Corruptor** | HIGH | feat | Fight in a place that damages you every turn | |
| **Rak'Shor Cultist** | HIGH | discovery | Fight an enemy using your own abilities against you | |

The Weirdling Beast heals to full in a few turns and does it often. Ukruk is a
scripted ambush you are *not supposed to win*. Bill drops the Transmogrification
Chest, which then unlocks as a starting item for **all future characters** — a
goal about the save file, not the run. The Rak'Shor Cultist spawns a shade with
your appearance, stats and talents at 40% damage.

## Loop Hero — strategy

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **The Lich** | HIGH | bounty | Beat a boss you summoned yourself | |
| **Goblin Leader** | MED | feat | Build something that spawns enemies, on purpose | |
| **Harpy** | LOW | feat | Change the terrain and see what it spawns | |
| **Chest** | LOW | bounty | Defeat a treasure chest | |
| **Blood Clot** | MED | bounty | Defeat an enemy made of what you spilled | |

Every Loop Hero enemy spawns off a tile you placed: Harpy after a mountain peak,
Blood Clot every 4 days on a blood path, Spider next to a cocoon, Skeleton on a
cemetery, Ratwolf on a grove, Chest at the start of a loop on a battlefield. The
Lich is the Chapter I boss and the loop is what brings him.

## Wildfrost — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Frost Jailer** | LOW | feat | Free something that is frozen solid | |
| **Truffle** | LOW | bounty | Defeat a mushroom | |
| **Eye of the Storm** | HIGH | restriction | Win a fight using only status effects | |
| **Bamboozle** | MED | restriction | Win a fight where the rules are hidden from you | ? |
| **Krunker** | MED | bounty | Defeat an enemy that eats what you brought | ? |

## Deep Rock Galactic: Survivor — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Glyphid Praetorian** | LOW | fetch | Mine an ore | |
| **Warden** | MED | bounty | Defeat the enemy that is protecting the others | |
| **Bulk Detonator** | MED | feat | Survive an explosion that fills the screen | |
| **Oppressor** | MED | bounty | Defeat an enemy you cannot hurt from the front | |
| **Stingtail** | LOW | feat | Get grabbed, then get free | |
| **Web Spitter** | LOW | feat | Get stuck in place and break out | |

Wardens mind-link nearby enemies and hand them damage reduction — kill the
linker, not the linked. Praetorians dig terrain, which makes them a better body
for mining than a boss who merely lives in a mine.

## Streets of Rogue — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Gorilla** | LOW | feat | Free something that then fights for you | |
| **Werewolf** | MED | discovery | Meet something that turns into something else | |
| **Cop** | HIGH | restriction | Finish a level without killing anyone | |
| **Bartender** ◆NPC | LOW | feat | Serve someone a drink | |

Gorillas make "strong allies or enemies" depending on how you meet them, which
is the goal in one body.

## Skul: The Hero Slayer — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **The First Hero** | HIGH | bounty | Defeat another game's protagonist | |
| **Elder Ent: Yggdrasil** | MED | bounty | Defeat a tree | |
| **Distorted Goddess: Chimera** | MED | bounty | Defeat something made of several creatures | |
| **Alexander, Emperor of Caerleon** | HIGH | bounty | Defeat an emperor | |
| **The Adventurer** | LOW | restriction | Play a whole run as the monster | ? |

## Inscryption — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Leshy** | HIGH | discovery | Catch the game itself cheating against you | |
| **The Angler** | MED | bounty | Defeat an enemy that takes your things mid-fight | |
| **The Trapper** | LOW | fetch | Trade a pelt for a creature | |
| **The Prospector** | LOW | feat | Turn something you own into currency | |
| **Grimora** | HIGH | feat | Leave a permanent record of a dead character | |
| **P03** | HIGH | discovery | Let a machine take the run away from you | |
| **The Unfinished Boss** | MED | bounty | Defeat something that was never finished | |

The Trapper turns your killed cards into **pelts**; the Trader then buys them
back as creatures — a two-step loop nothing else here has. The Act III Uberbots
include one P03 never completed.

## Brogue — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Dar Blademaster** | MED | feat | Free a caged enemy and fight beside it | |
| **Paralytic Bloat** | MED | feat | Lose a full turn to paralysis and live | |
| **Phantom** | LOW | feat | Fight something you cannot see | |
| **Goblin Conjurer** | LOW | feat | Let a summoned thing land the killing blow | |
| **Warden of Yendor** | HIGH | discovery | Go deeper than the run required you to | |

Captives are found chained in the early dungeon and freed by walking into them —
the one recruit in the genre that costs nothing but a detour.

---

# Part 3 — the games already on the sheet

Same treatment for the twenty games `data/` already draws from. These matter
more than they look: a run filters goal-enemies by the picked game's **type**,
so depth inside a game the sheet already has is depth the pool can actually use.

## Mewgenics — strategy

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Fenrir** | MED | bounty | Defeat an enemy that hides and lays traps | |
| **Boris** | MED | bounty | Pop something swollen | |
| **Chubs 'n' Nubs** | LOW | fetch | Get some trash | |

Fenrir hides in the grass and seeds traps your cats will step on; Boris is a
bloated 200 HP cat at the end of the Sewers; Chubs 'n' Nubs closes the Junkyard.

## Muck — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Bob** | HIGH | feat | Build a vehicle and leave in it | |
| **Gronk** | MED | feat | Forge a weapon | |
| **Woodman** | LOW | feat | Chop down a tree | |
| **Wyvern** | MED | bounty | Defeat a flying beast | |
| **Chief** | MED | bounty | Defeat a leader | |

Bob is the last thing you kill once the boat is built and you set sail — which
makes him the only creature on any of these lists who can carry *build a
vehicle* honestly.

## Ball x Pit — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Skeleton King** | MED | bounty | Defeat a crowned undead | |
| **Sabertooth** | MED | bounty | Defeat an extinct animal | |
| **Lord of Owls** | LOW | bounty | Defeat a bird | |
| **Shroom Swarm** | MED | bounty | Defeat a mushroom colony | |

## Enter the Gungeon — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Old King** | MED | bounty | Defeat a king and take the crown | |
| **Kill Pillars** | MED | bounty | Defeat four enemies that share one fight | |
| **High Priest** | HIGH | bounty | Defeat a priest | |
| **Mine Flayer** | MED | bounty | Defeat something in a mine | |

Note the collision: NetHack's **High Priest** is Part 1's body for *pray*, and
Gungeon has a boss of the same name. Two different games, so both can ship — but
give them different goals, as above, or the HUD will read oddly.

## Crypt of the NecroDancer — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **King Conga** | MED | fetch | Wear a crown | |
| **The Necrodancer** | HIGH | restriction | Never miss a beat | |
| **Coral Riff** | MED | bounty | Defeat a musician | |
| **Death Metal** | HIGH | bounty | Defeat a boss on the hardest track | ? |

## Slay the Spire — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **The Guardian** | MED | feat | Make an enemy change form | |
| **Giant Head** | HIGH | bounty | Defeat an enemy that punishes you for being slow | |
| **Nemesis** | HIGH | restriction | Win against something immune to half your damage | |

## The Binding of Isaac — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Dogma** | MED | feat | Break a screen | |
| **Gurdy** | MED | bounty | Defeat an enemy made of other enemies | |
| **Monstro** | LOW | bounty | Defeat an enemy that jumps on you | |
| **The Beast** | HIGH | bounty | Reach an ending most players never see | |

## Hades / Hades II — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Bone Hydra** | MED | bounty | Defeat an enemy with more than one head | |
| **The Furies** | MED | discovery | Meet the same boss wearing a different face | |
| **Charybdis** | HIGH | feat | Get swallowed | |

## NetHack — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Wizard of Yendor** | INSANE | bounty | Defeat a boss that keeps coming back | |
| **Mind Flayer** | HIGH | feat | Lose an ability permanently and win anyway | |

## Risk of Rain — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Scavenger** | HIGH | bounty | Defeat an enemy carrying your items | |
| **Magma Worm** | MED | bounty | Defeat an enemy that burrows | |
| **Imp Overlord** | HIGH | bounty | Defeat something from another dimension | |
| **Parent** | MED | bounty | Defeat an enemy that grabs and throws you | |

## Balatro — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **The Wall** ◆blind | MED | discovery | Clear a score twice the size it should be | |
| **The Eye** ◆blind | HIGH | restriction | Never repeat yourself | |
| **The Ox** ◆blind | MED | feat | Lose all your money in one go | |

## Brotato — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **The Mother** | MED | bounty | Defeat an enemy that spawns its own children | |
| **Monk Elite** | MED | bounty | Defeat a religious enemy | |

Brotato's `Colossus` would collide with Risk of Rain's `Colossus`, already on the
sheet — skip it.

## Rogue Legacy 2 — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Jonah** | MED | feat | Be swallowed whole | |
| **Cain** | HIGH | bounty | Defeat a sibling | |
| **Estuary Lamech** | MED | restriction | Beat the first boss with no upgrades bought | |
| **Byarrrith and Halpharrr** | HIGH | bounty | Defeat two enemies that share one health bar | ? |

## Rogue — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Xeroc** | MED | discovery | Be fooled by something disguised as loot | |
| **Aquator** | LOW | feat | Have your armour ruined and keep going | |

## Ember Knights — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Praxis** | HIGH | bounty | Defeat someone who sends others to fight you | |
| **Plague Bringer** | MED | feat | Win while poisoned | ? |
| **The Architect** | HIGH | bounty | Defeat a boss that builds its own arena | ? |

## Dungeon Clawler — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Prickwood** | LOW | bounty | Defeat the first thing that stops you | |
| **Bee Queen** | MED | feat | Get something sticky in your way | ? |

The Dungeon Clawler wiki's enemy page is still a stub, so names past Prickwood
need checking in-game.

## Forward: Escape the Fold — strategy

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Daemon Master** | HIGH | bounty | Defeat the second-to-last thing between you and the end | |
| **Strong Daemon Master** | INSANE | bounty | Defeat the last card in the deck | |

Bosses in FORWARD are randomised except the last two, which are always the
Daemon Master and the Strong Daemon Master — a guaranteed pair to build on.

---

# Audit: what got thrown out

The first pass of Part 2 included things that are not creatures. All of the
following were replaced with a real body from the same game, or cut:

| Was | What it actually is | Replaced by |
|---|---|---|
| Kali | an altar | **Witch Doctor** (Spelunky 2) |
| Kapala | an item | **Vampire** (Spelunky 2) |
| Mech | a vehicle | **Qilin** (a rideable creature) |
| Occultist | a *player* hero | **Thing From The Stars** (Darkest Dungeon) |
| The Pyre | an object you defend | **Lightwing** (the thing attacking it) |
| Train floor | a location | **Avowed Gladiator** |
| Champion / Stygian frost unit / Awoken sapling | your own cards | **Seraph the Diligent**; other two cut |
| Monster House | a room | **Groudon** (PMD) |
| Empty Belly | a status | cut — NetHack and CDDA cover food |
| Trap tile | dungeon furniture | cut |
| Recruited Pokémon | an ally | **Zapdos** (beat it, then recruit it) |
| Scrap vehicle | a construction | **Bob** (Muck) — see Part 3 |
| Mutagen / water purifier | items | **Mi-go**; water row cut |
| Evolved horde | a mechanic | **Skeletal Juggernaut** ? |
| Terminal | a machine | **Operator** (Cogmind) |
| Salvaged parts | items | **Hauler** (Cogmind) |
| Corruption / Blinding Greed / blood offering / temple trap | curses and mechanics | **Xucat'**, **Xak'olchir**, **Champion of Death**, **Dreadful Offspring** |
| Negotiation / Grudge / Job board / Resolve | systems | **Kashio**, **Arint**, **Jake Smuggler**, **Plocka** |
| Escort / cursed artifact / unlock condition | an NPC, an item, nothing | **Bill the Stone Troll**, **Grand Corruptor**, **Rak'Shor Cultist** |
| Camp / Treasury | buildings and cards | **Goblin Leader**, **Chest** (Chest is a real Loop Hero enemy) |
| Pet / Frozen Traveller / Frost | allies and a status | **Frost Jailer**, **Truffle**, **Eye of the Storm** |
| Molly / Drilldozer | friendly machines | **Web Spitter**, **Oppressor** |
| Hypnotizer / Knockout / Bank vault | an item, a verb, a room | **Gorilla**, **Cop**; vault cut |
| Skull swap / second head / awakened skull / Little Bone | abilities and the player | **First Hero**, **Yggdrasil**, **Chimera**, **Alexander** |
| Blood cost / Death card | a cost and an item | **Grimora**, **P03**, **The Unfinished Boss** |
| Ally / Lumenstone | generic, an item | **Goblin Conjurer**, **Warden of Yendor** |
| Ink Eel | a GBrogue variant, not base Brogue | **Phantom** |

Part 1 lost three of its own on the same test:

- **The Blacksmith** and **Blacksmith's Apprentice** (Dead Cells) are NPCs you
  never fight → **Black Pudding** (NetHack) for *upgrade a weapon*, **Gronk**
  (Muck) for *forge a weapon*.
- **Selene** (Hades II) is a boon-giver, not an enemy → *use star power* has no
  body and stays open.
- **Clog** (Isaac) could not be confirmed as an enemy → **Chubs 'n' Nubs**
  (Mewgenics) for *get some trash*, with Cogmind's **Recycler** as the alternate.
- **Gremlin Gang** is an encounter, not a creature → **Fat Gremlin**;
  **Sentries** → **Sentry**.
- **Shamura** was a weak fit for *build a house* → **Goblin Leader** (Loop Hero).
- Two survive as flagged **◆NPC** because the goal *is* the NPC: **Skelly**
  (Hades' training dummy, which you do hit) and **Damsel** (Spelunky 2) and
  **Bartender** (Streets of Rogue). Your call whether the sheet wants them.

# Overlap ledger

Kept-on-purpose neighbours: same idea, different `goal_type`, `difficulty`, or
physical act. Anything that could not clear that bar was cut rather than
reworded.

| Idea | A | B | How they differ |
|---|---|---|---|
| Stealing | `Steal from a shop` (Charon, fetch) | Keystone Kops, feat, MED — *survive* it | taking vs escaping |
| Stealing | Angry Shopkeeper, feat, HIGH | Kecleon, bounty, INSANE | feat vs bounty, two tiers apart |
| Allies | `Centurion and Mystic`, feat | Escort → **Bill the Stone Troll** replaced it; see ToME | — |
| Allies | Dar Blademaster (Brogue), feat, MED | Frost Jailer (Wildfrost), feat, LOW | free-and-fight vs thaw; tiers apart |
| Taming | Leshy (CotL), feat, MED | Gorilla (SoR), feat, LOW | permanent convert vs freed-on-the-spot |
| Enemy kills enemy | `Have an enemy defeat another enemy` (Marshmallow) | Goblin Conjurer (Brogue), feat, LOW | whose side the killer is on |
| Curses | Hecate, feat, MED — *get* hexed | Xucat', feat, HIGH — hold **four** | count and tier |
| Light | The Shambler, restriction, HIGH — no light at all | The Necrodancer, restriction, HIGH — no missed beat | different sense entirely |
| Upgrades | Black Pudding, feat — a weapon | Seraph the Diligent, feat, MED — a unit ×3 | different object and count |
| Upgrades | Warlock, feat, HIGH — 5+ enchants | Bill the Stone Troll, feat, MED — permanent unlock | this run vs every future run |
| Sacrifice | Witch Doctor, feat, HIGH | Xak'olchir, feat, LOW — your own blood | whose blood, and tier |
| Health as currency | `Trade health for resources` (Krampus, feat) | Xak'olchir, feat, LOW | heart containers vs a blood price |
| Explosions | Gas Spore, bounty — one-turn kill | Bulk Detonator, feat, MED — survive one | killing vs surviving |
| Not killing | Watchman, restriction, MED — spare innocents | Cop (SoR), restriction, HIGH — spare *everyone* | scope and tier |
| Stealth | `Become undetectable` (Stalker, feat) | Watcher, restriction, HIGH — a whole floor | a moment vs a rule |
| Spawners | `Destroy an enemy spawner` (Carcass, bounty) | Dreadful Offspring, feat, HIGH | kill the source vs clear the room anyway |
| Two-in-one fights | The Wicked Twins, bounty, HIGH — two | Kill Pillars, bounty, MED — four | count and tier |
| Crowns | King Conga, fetch, MED — wear one | Old King, bounty, MED — take one | fetch vs bounty |
| Kings | Old King (Gungeon) | Alexander (Skul), bounty, HIGH | tier, and emperor vs king |
| Swallowed | Jonah (RL2), feat, MED | Charybdis (Hades II), feat, HIGH | tier |
| Priests | High Priest (NetHack), feat — pray | High Priest (Gungeon), bounty, HIGH — kill one | same name, opposite verb |
| Vehicles | Treadnaught, feat — pilot | Bob (Muck), feat, HIGH — build | DM-200 repairs sits between; three verbs |
| Trapped in place | `Trap an enemy in place` (Spider Kitten, feat) | Web Spitter, feat, LOW — it happens to you | who is stuck |

Cut as true duplicates: a second freeze (Stygian Guard), a second splitter
(Pink Jelly), a second thief (Brogue Monkey), a second summoner (Ogre Shaman,
Brood Nexus, Reptomancer), a second shrink (SoR shrink ray), a second drunk
(Smith), a second level-30 (ToME prodigies), a second do-not-backtrack (Loop
Hero's loop), a second no-magic (ToME antimagic), a second two-boss fight (Donu
and Deca), a second dragon (Dragon Prince), and Brotato's `Colossus` against
Risk of Rain's.

# Still open

- **Use star power** — no enemy anywhere carries it; Selene is an NPC.
- **Drink milk**, **make a cake**, **smoke something** — Cataclysm: DDA has all
  three as items. The bodies need a pass over its bestiary.
- Twelve rows carry a **?** and need confirming in-game or on a wiki page I
  could not open from here.

## Sources

Part 1:

- [Hexaghost — Slay the Spire Wiki](https://slaythespire.wiki.gg/wiki/Hexaghost) ·
  [Gremlins](https://slaythespire.wiki.gg/wiki/Gremlins) ·
  [Strength](https://slaythespire.wiki.gg/wiki/Strength) ·
  [Slay the Spire 2: Monsters](https://slaythespire.wiki.gg/wiki/Slay_the_Spire_2:Monsters)
- [Prayer — NetHack Wiki](https://nethackwiki.com/wiki/Prayer) ·
  [High priest](https://nethackwiki.com/wiki/High_priest) ·
  [Aligned cleric](https://nethackwiki.com/wiki/Aligned_priest) ·
  [Altar](https://nethackwiki.com/wiki/Altar) ·
  [Stealing from shops](https://nethackwiki.com/wiki/Stealing_from_shops) ·
  [Item theft](https://nethackwiki.com/wiki/Theft_(attack)) ·
  [Curse items](https://nethackwiki.com/wiki/Curse_items)
- [Slime creature — CrawlWiki](http://crawl.chaosforge.org/Slime_creature)
- [Devil Room — Isaac Wiki](https://bindingofisaacrebirth.wiki.gg/wiki/Devil_Room) ·
  [Angel](https://bindingofisaacrebirth.wiki.gg/wiki/Angel) ·
  [Dingle](https://bindingofisaacrebirth.wiki.gg/wiki/Dingle) ·
  [Downpour](https://bindingofisaacrebirth.wiki.gg/wiki/Downpour) ·
  [Dross](https://bindingofisaacrebirth.wiki.gg/wiki/Dross) ·
  [Larry Jr.](https://bindingofisaacrebirth.wiki.gg/wiki/Larry_Jr.)
- [Treadnaught — Enter the Gungeon Wiki](https://enterthegungeon.wiki.gg/wiki/Treadnaught) ·
  [Shotgun Kin](https://enterthegungeon.wiki.gg/wiki/Shotgun_Kin) ·
  [Shotgrub](https://enterthegungeon.wiki.gg/wiki/Shotgrub_(Enemy)) ·
  [Knight Bullet Kin](https://enterthegungeon.wiki.gg/wiki/Knight_Bullet_Kin) ·
  [Keybullet Kin](https://enterthegungeon.wiki.gg/wiki/Keybullet_Kin) ·
  [Bosses](https://enter-the-gungeon-archive.fandom.com/wiki/Bosses)
- [I.D.P.D. Van — Nuclear Throne Wiki](https://nuclear-throne.fandom.com/wiki/I.D.P.D._Van) ·
  [I.D.P.D.](https://nuclear-throne.fandom.com/wiki/I.D.P.D.)
- [Mithrix — Risk of Rain 2 Wiki](https://riskofrain2.wiki.gg/wiki/Mithrix) ·
  [Monsters](https://riskofrain2.wiki.gg/wiki/Monsters) ·
  [Beetle Queen](https://riskofrain2.wiki.gg/wiki/Beetle_Queen) ·
  [Monsters (Risk of Rain 1)](https://riskofrain.wiki.gg/wiki/Monsters)
- [Bosses — Dead Cells Wiki](https://deadcells.wiki.gg/wiki/Bosses) ·
  [The Blacksmith](https://deadcells.wiki.gg/wiki/The_Blacksmith)
- [All Bosses — Hades 2 Wiki](https://hades2.wiki.fextralife.com/Bosses) ·
  [All Enemies](https://hades2.wiki.fextralife.com/Enemies)
- [Bosses — Cult of the Lamb Wiki](https://cult-of-the-lamb.fandom.com/wiki/Bosses)
- [Hiisi — Noita Wiki](https://noita.wiki.gg/wiki/Hiisi) ·
  [Creatures](https://noita.wiki.gg/wiki/Creatures) ·
  [Suomuhauki](https://noita.wiki.gg/wiki/Suomuhauki)
- [Chrome pyramid — Caves of Qud Wiki](https://wiki.cavesofqud.com/wiki/Chrome_pyramid) ·
  [Creatures](https://wiki.cavesofqud.com/wiki/Creatures) ·
  [Golgotha](https://wiki.cavesofqud.com/wiki/Golgotha)
- [Shattered Pixel Dungeon — Enemies](https://pixeldungeon.fandom.com/wiki/Shattered_Pixel_Dungeon/Enemies) ·
  [Bosses](https://pixeldungeon.fandom.com/wiki/Shattered_Pixel_Dungeon/Bosses)
- [Monsters — Crypt of the NecroDancer Wiki](https://necrodancer.miraheze.org/wiki/Monsters) ·
  [Minibosses](https://necrodancer.miraheze.org/wiki/Minibosses)
- [Amalaric Sniper — Vampire Survivors Wiki](https://vampire.survivors.wiki/w/Amalaric_Sniper) ·
  [Enemies](https://vampire.survivors.wiki/w/Enemies)

Part 2:

- [Bestiary (2) — Spelunky Wiki](https://spelunky.fandom.com/wiki/Bestiary_(2)) ·
  [Olmec](https://spelunky.fandom.com/wiki/Olmec_(2)) ·
  [Kali Altar](https://spelunky.wiki/wiki/Spelunky_2:Kali_Altar) ·
  [Shopkeeper](https://spelunky.fandom.com/wiki/Spelunky_2:Shopkeeper)
- [Enemies — Darkest Dungeon Wiki](https://darkestdungeon.wiki.gg/wiki/Enemies_(Darkest_Dungeon)) ·
  [Bosses](https://darkestdungeon.wiki.gg/wiki/Bosses_(Darkest_Dungeon)) ·
  [Shambler](https://darkestdungeon.wiki.gg/wiki/Shambler_(Darkest_Dungeon))
- [Enemies — Monster Train Wiki](https://monster-train.fandom.com/wiki/Enemies) ·
  [Units](https://monster-train.fandom.com/wiki/Units) ·
  [Seraph](https://monster-train.fandom.com/wiki/Seraph)
- [Kecleon Shop — Bulbapedia](https://bulbapedia.bulbagarden.net/wiki/Kecleon_Shop) ·
  [Boss (Rescue Team) — Pokémon Wiki](https://pokemon.fandom.com/wiki/Boss_(Rescue_Team)) ·
  [PMD bosses — Serebii](https://www.serebii.net/mysteriousdungeon/bosses.shtml)
- [Zombies — Cataclysm: DDA wiki](https://cataclysmdda.miraheze.org/wiki/Zombies) ·
  [Zombie master](https://srgnis.github.io/cdda-wiki/cdda_wiki/Zombie_master.html) ·
  [Monsters](https://srgnis.github.io/cdda-wiki/cdda_wiki/Monsters.html)
- [Robots — Cogmind devlog](https://www.moddb.com/games/cogmind/news/robots) ·
  [65 Robot Hacks](https://www.gridsagegames.com/blog/2018/08/65-robot-hacks/)
- [Enemies — Curse of the Dead Gods Wiki](https://curseofthedeadgods.fandom.com/wiki/Enemies) ·
  [Champions and Bosses](https://curseofthedeadgods.fandom.com/wiki/Category:Champions_and_Bosses) ·
  [Curses](https://curseofthedeadgods.fandom.com/wiki/Curses)
- [Enemies — Griftlands Wiki](https://griftlands.fandom.com/wiki/Enemies) ·
  [Spark Barons](https://griftlands.fandom.com/wiki/Spark_Barons) ·
  [Jakes](https://griftlands.fandom.com/wiki/Jakes)
- [Weirdling Beast — Tales of Maj'Eyal](https://te4.org/wiki/Weirdling_Beast) ·
  [Ukruk the Fierce](https://te4.org/wiki/Ukruk_the_Fierce) ·
  [Bill the Stone Troll](https://te4.org/wiki/Bill_the_Stone_Troll) ·
  [Grand Corruptor](https://te4.org/wiki/Grand_Corruptor) ·
  [Rak'Shor Cultist](https://te4.org/wiki/Rak%27Shor_Cultist)
- [Enemies — Loop Hero Wiki](https://loophero.fandom.com/wiki/Enemies) ·
  [Buildings](https://loophero.fandom.com/wiki/Buildings)
- [Bosses/minibosses — Wildfrost Wiki](https://wildfrost.fandom.com/wiki/Bosses/minibosses) ·
  [Enemies](https://wildfrostwiki.com/Enemies) ·
  [Heart of the Storm](https://wildfrostwiki.com/Heart_of_the_Storm)
- [Survivor:Creatures — Deep Rock Galactic Wiki](https://deeprockgalactic.wiki.gg/wiki/Survivor:Creatures)
- [Gorilla — Streets of Rogue Wiki](https://streetsofrogue.fandom.com/wiki/Gorilla)
- [Bosses — Skul Wiki](https://skul.fandom.com/wiki/Bosses) ·
  [Distorted Goddess: Chimera](https://skul.fandom.com/wiki/Distorted_Goddess:_Chimera) ·
  [Elder Ent: Yggdrasil](https://skul.fandom.com/wiki/Elder_Ent:_Yggdrasil)
- [Leshy — Inscryption Wiki](https://inscryption.fandom.com/wiki/Leshy) ·
  [The Prospector](https://inscryption.fandom.com/wiki/The_Prospector) ·
  [Uberbots](https://inscryption.fandom.com/wiki/Uberbots) ·
  [The Unfinished Boss](https://inscryption.fandom.com/wiki/The_Unfinished_Boss)
- [Monster Class — Brogue Wiki](https://brogue.fandom.com/wiki/Monster_Class) ·
  [Goblin Conjurer](https://brogue.fandom.com/wiki/Goblin_Conjurer) ·
  [Monkey](https://brogue.fandom.com/wiki/Monkey) ·
  [Allies](https://brogue.fandom.com/wiki/Allies)

Part 3:

- [Bosses — Mewgenics Wiki](https://mewgenics.wiki.gg/wiki/Bosses) ·
  [Enemies](https://mewgenics.wiki.gg/wiki/Enemies)
- [Enemies — BALL x PIT Wiki](https://ballxpit.wiki.gg/wiki/Enemies)
- [Category:Boss — Muck Wiki](https://muck.fandom.com/wiki/Category:Boss) ·
  [Category:Enemy](https://muck.fandom.com/wiki/Category:Enemy)
- [Bosses — Rogue Legacy 2 Wiki](https://rogue-legacy-2.fandom.com/wiki/Bosses) ·
  [Enemies](https://rogue-legacy-2.fandom.com/wiki/Enemies)
- [Enemies — Brotato Wiki](https://brotato.wiki.fextralife.com/Enemies)
- [Enemies — Ember Knights Wiki](https://emberknights.wiki.gg/wiki/Enemies)
- [Enemies — Dungeon Clawler Wiki](https://dungeon-clawler.fandom.com/wiki/Enemies)
- [Enemies — FORWARD: Escape the Fold Wiki](https://forward.fandom.com/wiki/Enemies)
- [Bosses — Brutal Orchestra Wiki](https://brutalorchestra.wiki.gg/wiki/Bosses) ·
  [Enemies](https://brutalorchestra.wiki.gg/wiki/Enemies)
