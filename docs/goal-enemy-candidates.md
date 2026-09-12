# Goal → enemy candidates

Research notes for pairing new goal prompts with real roguelike enemies and
bosses, in the same style as the existing rows in `data/enemies2.0/` and
`data/bosses2.0/` (a real creature whose flavour or mechanic *is* the goal).

Two parts. **Part 1** answers the ~120 prompts in the September 2026 batch.
**Part 2** goes the other way: sixteen games this project has never sourced
from, each roster read for the goals *it* suggests, whether or not a prompt
asked for them. Nothing here is wired up: it is a shortlist to paste into the
`enemies` / `bosses` sheets of `tools/Roguelikes.xlsx` and regenerate from.

## How to read it

- **Pick** — the creature. **Game** — where it comes from. **The tie** — why it
  belongs on that prompt.
- **type** is the suggested `goal_type`, using the five the project already
  uses: `bounty` (defeat something), `feat` (do something), `fetch` (obtain
  something), `restriction` (don't do something), `discovery` (witness / find
  something).
- A **?** in the confidence column means I could not confirm the creature or the
  detail against a wiki in this session — check it before it goes in the sheet.
  Everything unmarked is either confirmed by a wiki source below or is a
  first-order fact about a game this repo already sources from.
- Creatures already used in `data/` are deliberately **not** reused; where a
  prompt's obvious pick was taken, the second-best is given and the taken one is
  named in the tie.

---

# Part 1 — the prompt list

## 1. Religion, ritual, pacts

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| pray | **High Priest** | NetHack | Head of all religious activity for a god; `#pray` is the game's prayer verb and the temple he tends is where you do it | feat | |
| Become religious | **The One Who Waits** | Cult of the Lamb | The final boss who makes you a cult leader — the whole game is "become religious" | feat | |
| Worship at an altar | **Aligned Cleric** | NetHack | Tends the co-aligned temple altar; sacrificing and worshipping happens under him | feat | |
| Hexagon — complete a ritual w/ multiple steps | **Hexaghost** | Slay the Spire | Activate → Divider → each attack lights one of six flames → Inferno, then snuffs them. A literal multi-step ritual on a six-sided body | feat | |
| Make a devilish pact | **Satan** | The Binding of Isaac | Sheol's boss; Devil Rooms trade red heart containers for items. Krampus is taken by "Trade health for resources" | feat | |
| Trade health for resources | **Krampus** | The Binding of Isaac | The Devil Room's boss — the room where items cost heart containers, 1–2 each | feat | |
| Deal holy damage | **Uriel** (or **Gabriel**) | The Binding of Isaac | Angel Room mini-boss; fires beams of light in a cross pattern | feat | |
| Kill a God | *taken* | — | `The Creator` already carries this | — | |

## 2. Undead, corpses, resurrection

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Defeat skeleton | **Skeleton** (Black / White) | Crypt of the NecroDancer | The genre's baseline skeleton; the three Ball x Pit skeletons already in `data/` are all "defeat with a ball", so this one can carry the plain kill | bounty | |
| Defeat zombie | **Zombie** | Crypt of the NecroDancer | Slow, relentless, never stops walking at you | bounty | |
| Resurrect yourself 3 times and win | **Awakened One** | Slay the Spire | Dies, then stands back up with Curiosity — the boss that comes back | feat | |
| Attack a deceased enemy | **Necromancer** | Shattered Pixel Dungeon | Raises a skeleton from a corpse and re-raises it; the corpse is a target again | feat | |
| Gain an extra life | **Ghost** | Crypt of the NecroDancer | Killed, then returns as the thing it was — an extra life on the enemy's side | feat | |
| Bury a body | **Mummy** | NetHack | Wrapped and interred; NetHack graves are a real dungeon feature you dig into | feat | |

## 3. Mushrooms, growth, splitting

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Obtain a mushroom | **Violet Fungus** | NetHack | A mushroom that fights back; its corpse is the mushroom you walk away with. `Fungi Beast` is taken by "Get infected" | fetch | |
| Double your max health | **Slime Creature** | Dungeon Crawl Stone Soup | Two merge into a large slime creature, three into a very large one — HP and damage double as they combine | feat | |
| Grow in size | **Monster Lord** (any "lord" variant) | Crypt of the NecroDancer | Lords are twice the size of their normal counterpart with doubled HP and damage | feat | |
| Attack X enemies at a time | **Larry Jr.** | The Binding of Isaac | A segmented worm — one enemy that is many targets at once | feat | |

## 4. Footprint, formation, multi-target

*Your own notes on this cluster were already right; here they are with sources.*

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Gremlins could take up multiple spaces | **Gremlin Nob** | Slay the Spire | The oversized gremlin — the natural 2x2 body next to the 1x1 gremlin gang | feat | |
| Taunt an enemy | **Gremlin Nob** | Slay the Spire | Enrage: gains Strength every time you play a Skill. You provoke it by playing defensively | feat | |
| Have 5 of the same item | **Gremlin Gang** | Slay the Spire | Five gremlins drawn from the same small pool — doubles and triples are routine | fetch | |
| Spiked — kill an enemy that damages you back | **Spiker** | Slay the Spire | Act 3 enemy that sits behind Thorns: hitting it hurts you | bounty | |
| | **Mad Gremlin** | Slay the Spire | The other half of the same idea — gains 1 Strength whenever it takes attack damage | bounty | |
| Writhing Mass — randomly changes when you fail | **Writhing Mass** | Slay the Spire | Rerolls its intent and gains block every time you hit it — the same input never means the same thing twice | discovery | |
| Have at least one ally and don't let them die / Centurion and Mystic | **Centurion and Mystic** | Slay the Spire | The Mystic heals and buffs the Centurion; kill the healer and the pair falls apart | feat | |
| Attack all enemies on screen at once (and "Attack 5+ or all enemies") | **The Collector** | Slay the Spire | Summons torch heads continuously — the fight that exists to be swept | feat | |
| Do 3 things at the same time (StS Act 3) | **Sentries** | Slay the Spire | Three bodies, one encounter, alternating Bolt and Beam — three problems on the same turn | feat | |

> The last two prompts on your list ("Attack all enemies on the screen at once"
> and "Attack 5+ or all enemies on screen at once") are the same goal. Worth
> collapsing to one row before it reaches the sheet.

## 5. Restrictions

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Win without using melee physical attacks | **Floating Eye** | NetHack | The canonical never-melee-this monster: hit it in melee and its passive gaze paralyses you for dozens of turns | restriction | |
| Beat a run without moving | **Oklob Plant** | Dungeon Crawl Stone Soup | Rooted in place forever and still lethal — the enemy that already beats the game without moving | restriction | |
| Beat a run without taking damage | **The Concierge** | Dead Cells | The first boss, and the one whose whole fight is a dodge pattern | restriction | ? |
| Do not equip headgear if possible | **Knight Bullet Kin** | Enter the Gungeon | A bullet that survives on its helmet — shoot the helmet off and it dies like any other | restriction | |
| Get naked | **Nymph** | NetHack | Charms you into handing over your worn armour, then teleports away with it | restriction | |
| Do not kill any innocents | **Watchman** | NetHack | Peaceful until you swing; killing one turns the whole Watch hostile and is a murder | restriction | |
| Use only one hand | **The Needle** | Balatro | Play only 1 hand — one hand, literally | restriction | |
| Win with a negative modifier | **The Manacle** | Balatro | −1 hand size for the blind: you win the round handicapped or not at all | restriction | |
| Don't use consumables | **The Water** | Balatro | Start with 0 discards — the blind that takes your consumable resource away | restriction | |
| Never skip an offered reward | **Greed** | The Binding of Isaac | The boss that takes everything on offer | restriction | |
| Never purchase more than 2 things in a single shop | **Super Greed** | The Binding of Isaac | Greed's escalation, and a shop-flavoured body for a shop rule | restriction | |
| Always choose highest difficulty available | **Providence** | Risk of Rain | The first game's final boss, at the top of a difficulty bar that never stops climbing | restriction | |
| Kill every enemy you run into | **I.D.P.D. Elite** | Nuclear Throne | They come through a portal specifically to find you — the faction that will not let you leave anything alive | restriction | |

## 6. Items: upgrade, downgrade, steal, hoard

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Upgrade a weapon or item | **Blacksmith's Apprentice** | Dead Cells | Appears in every passage between biomes and reforges your gear | feat | |
| Forge a weapon | **The Blacksmith** | Dead Cells | The Legendary Forge — spend cells, raise the quality tier of what the run hands you | feat | |
| Enchant an item 5+ times | **Warlock** | Shattered Pixel Dungeon | Its darts degrade what you carry; the counter-goal is stacking enchantment on it anyway | feat | ? |
| Get an item or ability downgraded | **Disenchanter** | NetHack | Its touch strips enchantment off whatever you are wielding or wearing | feat | |
| Steal an item from a shop | **Keystone Kops** | NetHack | Spawn the moment you walk out of a shop without paying, and chase you for it. `Charon` already holds "Steal from a shop", so this is the second body for the same idea | feat | |
| Obtain 5 max tier items in one run | **Aurelionite** | Risk of Rain 2 | The Halcyon Seed / red-item boss — the fight you take specifically to top out your inventory | fetch | ? |
| Get some trash | **Clog** | The Binding of Isaac (Dross) | Dross is the sewage-and-refuse alternative to Downpour; its bodies are literally made of what the dungeon threw away | fetch | ? |
| Acquire a diamond | **Crystal Guardian** | Shattered Pixel Dungeon | The caves' crystal enemy — the gem walks at you | fetch | ? |
| Mine an ore | **Mine Flayer** | Enter the Gungeon | Boss of the Black Powder Mine, the floor that exists to be dug | feat | ? |
| Open 10 locked doors | **Mimic** | Shattered Pixel Dungeon | A locked chest that turns out to be a monster — every locked thing, the hard way | feat | |
| Break down a door | **Minotaur** | Crypt of the NecroDancer | Charges in a straight line and smashes through what is in the way | feat | |
| Break through a wall | **Wallmonger** | Enter the Gungeon | A boss that *is* the wall; the fight ends with the wall gone | feat | |

## 7. Machines, vehicles, construction

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Pilot a vehicle | **Treadnaught** | Enter the Gungeon | A tank piloted by a Tanker that got lucky and found it — the driver is visible and shootable | feat | |
| | **I.D.P.D. Van** | Nuclear Throne | Bursts through a portal, drives through terrain, unloads troops | feat | |
| Pilot a flying vehicle | **Xi Construct** | Risk of Rain 2 | A hovering machine that fights as a flying platform | feat | ? |
| Repair a vehicle | **DM-200** | Shattered Pixel Dungeon | Dwarven machinery still running long after its keepers died | feat | |
| Fix a machine | **DM-300** | Shattered Pixel Dungeon | The broken mining machine boss — the whole fight is about the thing being out of repair | feat | |
| Destroy a building | **The Giant** | Dead Cells | A tier-2 boss large enough that the arena is part of the fight | feat | |
| Build a house | **Shamura** | Cult of the Lamb | Silk Cradle's spider bishop — the game where the loop between fights is building your settlement | feat | ? |

## 8. Water, liquids, weather, states of matter

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Touch water | **Strider** | The Binding of Isaac (Downpour) | Downpour is waist-deep water throughout, and Striders swim it — including over pits | feat | ? |
| Enter a sewer | **Dingle** | The Binding of Isaac | The sewage boss (name from "dingleberry"); Dross is the sewer floor. `Flushmaster` already covers flushing | discovery | |
| Take a bath or shower | **Rainmaker** | The Binding of Isaac (Downpour) | The boss of the flooded floor, who brings the rain down on you | feat | ? |
| Change the weather | **Ukko** | Noita | Named for the Finnish god of the heavens; a thunder mage who brings the storm with him | feat | |
| Carry 4 different liquids at once | **Slog of the Cloaca** | Caves of Qud | A creature made of the sludge of a game whose whole world model is liquids mixing | fetch | ? |
| Drink a mystery liquid | **Ylialkemisti** | Noita | The high alchemist — unlabelled flasks, unpredictable results | feat | |
| Become all 3 states of matter | **Limatoukka** | Noita | Noita's material sim is the only place this goal is literal: the same substance as liquid, solid and gas. `Ice Slime` and `Lava Slime` already hold two of the three | feat | ? |

## 9. Time, speed, one-turn kills

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Defeat a boss in one second or one turn | **Gas Spore** | NetHack | Kill it and it detonates for enormous damage — the whole creature resolves in a single hit | bounty | |
| Beat the clock | **The Time Keeper** | Dead Cells | The boss built around time and its own reversal | bounty | |
| Have a character reach level 30 | **Death** | Vampire Survivors | Arrives at the 30-minute mark — the game's hard timer, wearing a scythe | bounty | |
| Complete a weekly/daily run | **Deep Blues** | Crypt of the NecroDancer | The chess boss — daily-challenge furniture, and a fight that is the same puzzle for everyone that day | feat | ? |
| Beat a run without moving | *see §5* | — | — | — | |

## 10. Pets, allies, taming

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Pet a pet | **Cerberus** | Hades | You can pet the dog. In Hades II he comes back as Infernal Cerberus and you fight him first | feat | |
| Feed an animal | **Little Dog** | NetHack | Feeding is how you keep a pet tame; a hungry pet stops being yours | feat | |
| Tame an enemy | **Leshy** | Cult of the Lamb | Darkwood's bishop, in the game where defeated creatures are indoctrinated into your flock | feat | |
| Catch 5 creatures | **Kallamar** | Cult of the Lamb | Anchordeep's bishop — the water region, which is also where the game's fishing lives | fetch | ? |
| Do not win alone | **Theseus and the Minotaur** | Hades | Two bosses in one arena; the fight is about a pair that will not be split | feat | |
| Have an enemy defeat 3 enemies | **Medusa** | NetHack | Her gaze does not care who is looking — she kills her own floor | feat | |

## 11. Crossovers, meta, achievements

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Encounter an outside IP | **Dracula** | Dead Cells (Return to Castlevania) | A different studio's icon, standing in a Dead Cells boss arena | discovery | |
| Play a game in another language | **Kolmisilmä** | Noita | Every creature in Noita is named in Finnish and the game never translates them — Suomuhauki is "scaled pike", not "dragon" | discovery | |
| Get an achievement only 5% or less of players have | **Chrome Pyramid** | Caves of Qud | The highest-level non-unique creature in the game, surpassed only by 0lam — and killing one grants an achievement | bounty | |
| Obtain a new achievement | **Hush** | The Binding of Isaac | The hidden boss behind the Blue Womb timer — a first kill you will remember | bounty | |
| Get 10 achievements in one run | **Delirium** | The Binding of Isaac | Shapeshifts through every boss in the game in one fight — ten things at once, made flesh | feat | |
| Enter a void | **Delirium** | The Binding of Isaac | Lives on The Void, the floor made of every other floor | discovery | |
| Unlock a new character | **Ultra Greed** | The Binding of Isaac | Greed Mode's finale, and the unlock engine for half the roster | feat | |
| Play as a character that looks like you | **Johannes** | Rogue Legacy | The final boss is your own ancestor; the whole game is inheriting a face | discovery | |
| Beat a mini-game or a game inside of a game | **The Resourceful Rat** | Enter the Gungeon | His second phase drops you into a Punch-Out-style boxing minigame inside the boss fight | feat | |
| Beat a game you'd give an 8+ | **Hades** (Lord of the Dead) | Hades | The final boss of the run everyone gives a 9 | bounty | |
| Whenever you lose a run, also do 1 push-up | **The Fallen** | The Binding of Isaac | Splits into two smaller copies when killed — the enemy that charges you extra for every ending | feat | ? |

## 12. Damage, crits, weapons

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Deal damage equal to your block | **Shield Gremlin** | Slay the Spire | Spends its whole existence handing out block — the fight where block is the resource | feat | |
| Get maximum crit chance | **Amalaric Sniper** | Vampire Survivors | Fires a single aimed shot from off-screen for a huge chunk — the game's one true crit | feat | |
| Defeat an enemy with a shotgun | **Shotgun Kin** / **Shotgrub** | Enter the Gungeon | Every Shotgun Kin variant has its own name; Shotgrub walks at you firing waving spreads | bounty | |
| Overkill an enemy by double their Health | **Big Dog** | Nuclear Throne | The scrapyard boss you either delete or lose to — no middle | bounty | |
| Improvised weapon | **Cockatrice** | NetHack | The famous improvisation: wield the corpse (with gloves) and turn everything you touch to stone | feat | |
| Defeat an enemy without violence | **Blobulin** | Enter the Gungeon | The thing the Devolver gun turns enemies into — you win the fight by making it something harmless | bounty | |
| Use star power | **Selene** | Hades II | Grants the Path of Stars — lunar/stellar power as an explicit boon line | feat | ? |
| Have the number 100,000 appear | **Violet Vessel** | Balatro | A finisher blind with a score requirement large enough that six figures show up on screen | discovery | |

## 13. Health, curses, the body

| Prompt | Pick | Game | The tie | type | ? |
|---|---|---|---|---|---|
| Beat a boss with 1 health left | **The Lamb** | The Binding of Isaac | The final boss whose head keeps fighting after the body is gone — a sliver that refuses to die | bounty | ? |
| Go from 1 to max health | **Goo** | Shattered Pixel Dungeon | Regenerates in the water it sits in — the enemy that heals itself back to full in front of you | feat | |
| Reduce max health by half | **Mega Satan** | The Binding of Isaac | The end of the Devil-deal road, where max health is the currency you have been spending | feat | |
| Get hexed or cursed | **Hecate** | Hades II | The Witch of the Crossroads fights with hexes | feat | |
| Puke | **Chub** | The Binding of Isaac | Eats and spits — the boss you can feed things to | feat | |
| Defeat your parent | **Mom** | The Binding of Isaac | The parent, in the game named for a parent. `Mom's Heart` is taken by "Break a Heart" | bounty | |
| Kill a parent | **Hades** (Lord of the Dead) | Hades | Zagreus' father, fought at the exit | bounty | |
| Make someone cry | **Blue Baby (???)** | The Binding of Isaac | A crying child who attacks with his tears | feat | ? |
| Destroy a planet | **Mithrix** | Risk of Rain 2 | Beat him on the moon of Petrichor V and the moon starts coming apart while you run for the ship | feat | |
| Defeat a green creature | **Heket** | Cult of the Lamb | Anura's bishop — an enormous green frog | bounty | |
| Read a book | **Book of Stabbing** | Slay the Spire | An Act 2 enemy that is a book, with a multi-attack you learn by reading its intent | feat | |
| Skip the tutorial | **Skelly** | Hades | The training-room dummy you are free to walk straight past | restriction | |
| Train something to win/be fast/be strong | **Skelly** | Hades | Same body, other half: he exists to be practised on, and rewards you for hitting targets | feat | |

---

## Still open

Six prompts where I did not find a pick I would stand behind. Ideas, not
recommendations:

- **To smoke something** — no clean roguelike body. Closest is a thief's smoke
  bomb (Shattered Pixel Dungeon's bandits vanish in one), or a Noita gas cloud.
- **Drink milk** — Isaac is the obvious game (Mom's Milk exists as an item) but
  no *enemy* carries it. Worth a pass over Mewgenics' roster, which this project
  already mines heavily and which is full of food.
- **Make a cake** — Cult of the Lamb's cooking pot is the mechanic; it has no
  boss attached. Dungeon Clawler or Mewgenics may have a body for it.
- **Get some trash** / **Acquire a diamond** — the picks above are guesses at
  the right floor rather than confirmed creature names.
- **Use star power** — Selene is an NPC, not an enemy. If the project wants an
  enemy, the Hades II celestial bosses are the place to look.

## Duplicates worth collapsing before this reaches the sheet

- "Attack all enemies on the screen at once" and "Attack 5+ or all enemies on
  screen at once" are the same goal.
- "Defeat your parent" and "Kill a parent" differ only in wording; they are given
  two different bodies above (Isaac's Mom, Hades) so both can survive if you want
  them to.
- "Beat a run without moving" already has a body under Restrictions and is listed
  twice in the prompt list.

---

# Part 2 — sixteen more wikis, read for the goals they suggest

Part 1 started from the prompts and went looking for bodies. This part starts
from a roster and asks what goals it is *already* about. Every game below is one
`data/` has never sourced from.

Each row carries the four fields the sheet needs beyond name and art:
**type** = `game_type` (action / deckbuilder / traditional / strategy),
**tier** = `difficulty` (`LOW` / `MED` / `HIGH` / `INSANE`, the resource's four),
**goal type**, and the goal text. `?` still means unconfirmed.

> **One thing worth noticing before picking.** The live roster is 44 action,
> 27 deckbuilder, 23 strategy and **8 traditional**. Traditional is the starved
> pool — a run on traditional games is drawing from NetHack ×4, Crypt ×3 and
> Rogue ×1. Six of the sixteen games below are traditional roguelikes, and
> they are where this list pays for itself.

## Spelunky 2 — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Kali** (altar) | HIGH | feat | Sacrifice something you were relying on | |
| **Kapala** | LOW | fetch | Drink blood | |
| **Olmec** | HIGH | bounty | Defeat an enemy you cannot damage | |
| **Angry Shopkeeper** | HIGH | feat | Get marked as a thief and finish the level anyway | |
| **Ghost** | MED | restriction | Stay on a level longer than it wants you to | |
| **Damsel** | MED | fetch | Carry a rescued NPC all the way to the exit | |
| **Qilin** (mount) | LOW | feat | Ride an animal | |
| **Mech** | MED | bounty | Crush an enemy with something you are riding | |
| **Golden Monkey** | MED | fetch | Acquire a gem or diamond | ? |

Notes: Kali takes live and dead bodies for favour and pays the most for **pets** —
that is what makes the sacrifice goal bite. The Kapala is a skullcup you drink
blood from; it is its own goal, not a health goal. Olmec is *indestructible* —
mattock and bombs do nothing — so "defeat what you cannot damage" is literal.

## Darkest Dungeon — strategy

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **The Collector** | MED | fetch | Fill your inventory to its last slot | |
| **The Shambler** | HIGH | restriction | Play a whole level with no light source | |
| **Swine Prince** | MED | feat | Beat a boss by killing its small companion first | |
| **Madman** | MED | feat | Survive an enemy that never attacks you directly | |
| **The Countess** | HIGH | feat | Beat a boss while diseased or afflicted | |
| **Bone Courtier** | HIGH | restriction | Beat a boss without letting it summon anything | |
| **Occultist** | MED | feat | Heal yourself with something that can also hurt you | |
| **The Fanatic** | HIGH | feat | Lose a party member permanently and finish anyway | |

Notes: the Collector ambushes when 13+ inventory slots are full and the Shambler
ambushes at torch level 0 — both are enemies *summoned by how you play*, which
is exactly the shape a goal wants. The Madman only deals stress, never damage.

## Monster Train — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Seraph** | HIGH | restriction | Win a fight where the enemy sets an extra rule | |
| **The Pyre** | HIGH | restriction | Defend one thing that must never be touched | |
| **Stygian Guard frost unit** | MED | bounty | Kill an enemy with a status effect rather than a hit | |
| **Awoken sapling** | MED | feat | Out-heal an enemy's damage for three turns straight | |
| **Champion** (any clan) | MED | feat | Upgrade the same unit three times | |
| **Train floor** | MED | feat | Fight on more than one battlefield at once | |

Notes: Seraph is the run's final boss and comes in variants (the Temperant, the
Chaste, the Diligent, the Patient) that each impose a different rule on the
fight — one body, many restrictions, which suits a pool that wants variety.

## Pokémon Mystery Dungeon — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Kecleon** | INSANE | bounty | Defeat a shopkeeper | |
| **Monster House** | HIGH | feat | Survive a room that is nothing but enemies | |
| **Recruited Pokémon** | MED | fetch | Recruit three different species in one run | |
| **Empty Belly** | MED | feat | Let your hunger hit zero and survive it | |
| **Rescue Team** | HIGH | discovery | Be rescued, or rescue someone else's failed run | |
| **Trap tile** | LOW | discovery | Step on a trap you already knew was there | |

Notes: rob a Kecleon shop and the floor fills with **extremely powerful Kecleon
moving at double speed** — beating one is genuinely an INSANE-tier goal, and
theft is the only way to recruit one. The rescue system (a failed run leaves a
code another player can answer) has no equivalent anywhere else on this list.

## Cataclysm: Dark Days Ahead — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Zombie Master** | HIGH | discovery | Watch an enemy upgrade another enemy | |
| **Shocker Zombie** | LOW | bounty | Defeat an enemy that shocks you | |
| **Boomer** | LOW | feat | Get covered in something and keep fighting | |
| **Zombie Hulk** | HIGH | bounty | Defeat an enemy that can knock you through a wall | |
| **Evolved horde** | HIGH | discovery | Play long enough that the enemies get worse | |
| **Scrap vehicle** | INSANE | feat | Build a working vehicle out of parts | |
| **Mutagen** | HIGH | feat | Permanently change your own body | |
| **Water purifier** | LOW | fetch | Obtain clean drinking water | |

Notes: the zombie master *transforms* ordinary zombies into spitters and
shockers, and zombie evolution is a real clock — hordes upgrade based on how
long it has been since the Cataclysm. CDDA is also the one game on this list
that can honestly carry **drink milk**, **make a cake** and **smoke something**;
all three are ordinary recipes/items there. Bodies for those three still need
picking off the bestiary.

## Cogmind — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Behemoth** | INSANE | bounty | Defeat an enemy that takes up four spaces | |
| **Watcher** | HIGH | restriction | Clear a floor without ever being spotted | |
| **Programmer** | HIGH | discovery | Watch an enemy turn one of your allies against you | |
| **Hunter** | MED | discovery | Be tracked across floors by a pair that works together | |
| **Swarmer** | LOW | feat | Be surrounded on every side at once | |
| **Sentry** | LOW | bounty | Defeat an enemy that outguns you but cannot chase | |
| **Terminal** | MED | feat | Hack a machine into doing what you want | |
| **Salvaged parts** | HIGH | restriction | Win using only equipment taken off enemies | |
| **Recycler** | LOW | fetch | Get some scrap or trash | ? |

Notes: Behemoths take up **four tiles instead of one** — the cleanest fit on
this whole list for the project's footprint system (§7.3). Watchers are unarmed
and exist purely to report you, which is what makes a stealth restriction land.

## Curse of the Dead Gods — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Corruption** | HIGH | feat | Carry four curses at the same time | |
| **Blinding Greed** | MED | restriction | Win a fight while your gold rots on the floor | |
| **Cadaverous Infestation** | HIGH | feat | Clear a room where every kill makes more enemies | |
| **Champion** | MED | bounty | Defeat a champion to have a curse lifted | |
| **Blood offering** | LOW | feat | Pay for something with your own blood | |
| **Temple trap** | MED | bounty | Kill an enemy with a trap you did not place | |

Notes: corruption fills by opening doors, making blood offerings and taking dark
hits; you can hold four curses before the fifth and final one lands, and the
only cures are killing a champion or giving up a cursed weapon. That is a whole
family of goals off one gauge.

## Griftlands — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Negotiation** | MED | feat | Win an argument instead of a fight | |
| **Sal** | HIGH | feat | Turn someone sent to kill you into an ally | |
| **Grudge** | LOW | discovery | Make an enemy who remembers you next time | |
| **Job board** | LOW | fetch | Take a contract and complete it | |
| **Resolve** | HIGH | bounty | Break someone's will without hurting them | |

Notes: negotiation is a full parallel combat system — losing it starts a real
fight, winning it skips one. Griftlands is the only game here where "beat an
enemy without violence" is a *system* rather than a trick.

## Tales of Maj'Eyal — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Weirdling Beast** | HIGH | bounty | Out-damage an enemy that heals to full | |
| **Ukruk the Fierce** | HIGH | feat | Survive a fight you were meant to lose | |
| **Escort** | MED | restriction | Keep an NPC alive for a whole level | |
| **Cursed artifact** | LOW | feat | Destroy a magic item on purpose | |
| **Unlock condition** | MED | discovery | Unlock a class by doing something unrelated to it | |

Notes: the Weirdling Beast heals to full in a few turns and does it often — an
honest DPS-race goal. Ukruk appears in a scripted ambush you are *not supposed
to win*, which is a goal all by itself.

## Loop Hero — strategy

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **The Lich** | HIGH | bounty | Beat a boss you summoned yourself | |
| **Goblin Leader** | MED | feat | Build something that spawns enemies, on purpose | |
| **Ratwolf** | LOW | feat | Make a specific enemy appear by changing the map | |
| **Treasury** | MED | restriction | Win by hoarding rather than by fighting | |
| **Camp** | MED | feat | Build a house | |

Notes: Loop Hero is the right home for **build a house** — the camp (War Camp,
Smithy, Mud Hut, Field Kitchen, 23 buildings) is the between-run loop, and the
Goblin Leader literally spawns from a camp *you* placed next to the road.

## Wildfrost — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Frozen Traveller** | LOW | feat | Thaw something frozen solid | |
| **Pet** | LOW | discovery | Start a run with a companion you earned earlier | |
| **Area boss** | MED | bounty | Defeat an enemy that gets worse the longer you wait | ? |
| **Frost / Snow** | HIGH | restriction | Win a fight using only status effects | |

Notes: companions are freed from ice blocks in the Frozen Travellers event, and
pets are unlocked one at a time by completing set goals — the game already
thinks in the project's own vocabulary.

## Deep Rock Galactic: Survivor — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Glyphid Praetorian** | LOW | fetch | Mine an ore | |
| **Warden** | MED | bounty | Defeat the enemy that is protecting the others | |
| **Bulk Detonator** | MED | feat | Survive an explosion that fills the screen | |
| **Drilldozer** | MED | feat | Escort a machine to where it is going | |
| **Stingtail** | LOW | feat | Get grabbed, then get free | |
| **Molly** | LOW | fetch | Call in a resupply | |

Notes: Praetorians dig through terrain, which makes them a better body for
**mine an ore** than Part 1's Mine Flayer guess. Wardens mind-link nearby
enemies and hand them damage reduction — kill the linker, not the linked.

## Streets of Rogue — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Gorilla** | LOW | bounty | Defeat a beast in melee | |
| **Hypnotizer Mark II** | LOW | feat | Turn an enemy against its own side | |
| **Knockout** | HIGH | restriction | Finish a level without killing anyone | |
| **Bartender** | LOW | feat | Serve someone a drink | |
| **Werewolf** | MED | discovery | Play as something that turns into something else | |
| **Bank vault** | MED | feat | Blow open a locked vault | |

## Skul: The Hero Slayer — action

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Little Bone** | LOW | restriction | Play a whole run as a skeleton | |
| **Skull swap** | MED | feat | Change which character you are, mid-run | |
| **Second head slot** | LOW | feat | Carry two loadouts and use both in one fight | |
| **Awakened skull** | MED | feat | Upgrade an ability into its stronger form | |
| **The Hero** | HIGH | bounty | Defeat another game's protagonist | |

Notes: Skul equips **two heads at once** and swaps between them in combat, and
each head is a different moveset — the cleanest body on the list for a
mid-run identity change, and the obvious pairing for the headgear restriction.

## Inscryption — deckbuilder

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Leshy** | HIGH | discovery | Catch the game itself cheating against you | |
| **The Angler** | MED | bounty | Defeat an enemy that takes your things mid-fight | |
| **The Trapper** | LOW | fetch | Trade a pelt for a creature | |
| **The Prospector** | LOW | feat | Turn something you own into currency | |
| **Blood cost** | LOW | feat | Sacrifice one of your own to play another | |
| **Death card** | HIGH | feat | Leave a permanent record of a dead character | |

Notes: the Trapper turns your killed cards into **pelts**, and then the Trader
buys them back as creatures — a two-step loop no other game here has. Death
cards persist into later runs, which is a goal about the save file, not the run.

## Brogue — traditional

| Pick | tier | goal type | Goal | ? |
|---|---|---|---|---|
| **Captive monster** | MED | feat | Free a caged enemy and fight beside it | |
| **Paralytic Bloat** | MED | feat | Lose a full turn to paralysis and live | |
| **Ink Eel** | LOW | feat | Fight something you cannot see | |
| **Ally** | LOW | feat | Let an ally land the killing blow | |
| **Lumenstone** | HIGH | discovery | Go deeper than the run required you to | |

Notes: captives are found chained in the early dungeon and freed by walking into
them — the one "recruit" in the genre that costs nothing but a detour.

---

# Overlap ledger

Kept-on-purpose neighbours. Each pair sits on the same idea but differs in
`goal_type`, in `difficulty`, or in what the player physically does — which is
the bar you set. Anything that could not clear it was cut rather than reworded.

| Idea | A | B | How they differ |
|---|---|---|---|
| Stealing | `Steal from a shop` (Charon, fetch) | Keystone Kops, feat, MED — *survive* the theft | act: taking vs escaping |
| Stealing | Angry Shopkeeper, feat, HIGH | Kecleon, bounty, INSANE | feat vs bounty, and two tiers apart |
| Allies | `Centurion and Mystic`, feat | Escort (ToME), restriction, MED | keeping one alive is a rule, not an act |
| Allies | Captive monster (Brogue), feat, MED | Frozen Traveller (Wildfrost), feat, LOW | free-then-fight vs thaw-and-keep; tiers apart |
| Taming | Leshy (CotL), feat, MED | Hypnotizer (SoR), feat, LOW | permanent convert vs turn-them-mid-fight |
| Enemy kills enemy | `Have an enemy defeat another enemy` (Marshmallow) | Let an ally land the killing blow (Brogue), LOW | whose side the killer is on |
| Curses | Hecate, feat, MED — *get* hexed | Corruption, feat, HIGH — hold **four** | count and tier |
| Light | The Shambler, restriction, HIGH — no light at all | Temple torch (CotDG), restriction, MED | total vs partial; tiers apart |
| Upgrades | Blacksmith's Apprentice, feat — a weapon | Awakened skull, feat, MED — an ability | different object |
| Upgrades | Warlock, feat, HIGH — 5+ enchants | Champion (MT), feat, MED — 3 upgrades | count and tier |
| Sacrifice | Kali, feat, HIGH — something you relied on | Blood cost (Inscryption), feat, LOW | stakes and tier |
| Health as currency | `Trade health for resources` (Krampus, feat) | Blood offering (CotDG), feat, LOW | heart containers vs a blood price; tiers apart |
| Explosions | Gas Spore, bounty — one-turn kill | Bulk Detonator, feat, MED — survive one | killing vs surviving |
| Not killing | Watchman, restriction, MED — spare innocents | Knockout (SoR), restriction, HIGH — spare *everyone* | scope and tier |
| Stealth | `Become undetectable` (Stalker, feat) | Watcher, restriction, HIGH — a whole floor | a moment vs a rule for the level |
| Spawners | `Destroy an enemy spawner` (Carcass, bounty) | Cadaverous Infestation, feat, HIGH | kill the source vs clear the room anyway |
| Water | `Touch water` (Strider, feat) | Clean water (CDDA), fetch, LOW | touching vs obtaining |
| Hunger | `Don't eat any food` (Famine, restriction) | Empty Belly (PMD), feat, MED | a rule vs a survival act — good pair, keep both |
| Vehicles | Treadnaught, feat — pilot | Scrap vehicle (CDDA), feat, INSANE — build | DM-200 repairs sit between them; three tiers, three verbs |

Cut as true duplicates, for the record: a second "freeze an enemy" (Stygian
Guard → reframed to status-kill), a second "defeat a splitter" (Cadaverous →
reframed), a second thief (Brogue Monkey), a second summoner (Ogre Shaman, Brood
Nexus), a second shrink (SoR shrink ray), a second drunk (Smith), a second
"reach level 30" (ToME prodigies), a second "do not backtrack" (Loop Hero's
loop), and a second "do not use magic" (ToME antimagic).

# Revisions to Part 1

Part 2 turned up better bodies for four rows that were guesses:

- **Mine an ore** — Glyphid Praetorian (DRG: Survivor) replaces Mine Flayer.
- **Build a house** — Loop Hero's camp replaces Shamura.
- **Acquire a diamond** — Spelunky 2's Golden Monkey replaces Crystal Guardian.
- **Get some trash** — Cogmind's Recycler replaces Isaac's Clog.

And three of Part 1's six open prompts now have a home game, if not yet a body:
**drink milk**, **make a cake** and **smoke something** are all ordinary
Cataclysm: DDA items. **Use star power** is still open.

## Sources

- [Hexaghost — Slay the Spire Wiki](https://slaythespire.wiki.gg/wiki/Hexaghost)
- [Gremlin Nob — Slay the Spire Wiki](https://slaythespire.wiki.gg/wiki/Gremlins)
- [Strength / Mad Gremlin — Slay the Spire Wiki](https://slaythespire.wiki.gg/wiki/Strength)
- [Slay the Spire 2: Monsters](https://slaythespire.wiki.gg/wiki/Slay_the_Spire_2:Monsters)
- [Prayer — NetHack Wiki](https://nethackwiki.com/wiki/Prayer) ·
  [High priest](https://nethackwiki.com/wiki/High_priest) ·
  [Aligned cleric](https://nethackwiki.com/wiki/Aligned_priest) ·
  [Altar](https://nethackwiki.com/wiki/Altar)
- [Stealing from shops — NetHack Wiki](https://nethackwiki.com/wiki/Stealing_from_shops) ·
  [Item theft](https://nethackwiki.com/wiki/Theft_(attack)) ·
  [Curse items](https://nethackwiki.com/wiki/Curse_items)
- [Slime creature — CrawlWiki](http://crawl.chaosforge.org/Slime_creature)
- [Devil Room — The Binding of Isaac: Rebirth Wiki](https://bindingofisaacrebirth.wiki.gg/wiki/Devil_Room)
- [Angel — The Binding of Isaac: Rebirth Wiki](https://bindingofisaacrebirth.wiki.gg/wiki/Angel)
- [Dingle](https://bindingofisaacrebirth.wiki.gg/wiki/Dingle) ·
  [Downpour](https://bindingofisaacrebirth.wiki.gg/wiki/Downpour) ·
  [Dross](https://bindingofisaacrebirth.wiki.gg/wiki/Dross) ·
  [Larry Jr.](https://bindingofisaacrebirth.wiki.gg/wiki/Larry_Jr.)
- [Treadnaught — Enter the Gungeon Wiki](https://enterthegungeon.wiki.gg/wiki/Treadnaught) ·
  [Shotgun Kin](https://enterthegungeon.wiki.gg/wiki/Shotgun_Kin) ·
  [Shotgrub](https://enterthegungeon.wiki.gg/wiki/Shotgrub_(Enemy)) ·
  [Knight Bullet Kin](https://enterthegungeon.wiki.gg/wiki/Knight_Bullet_Kin) ·
  [Keybullet Kin](https://enterthegungeon.wiki.gg/wiki/Keybullet_Kin)
- [I.D.P.D. Van — Nuclear Throne Wiki](https://nuclear-throne.fandom.com/wiki/I.D.P.D._Van) ·
  [I.D.P.D.](https://nuclear-throne.fandom.com/wiki/I.D.P.D.)
- [Mithrix — Risk of Rain 2 Wiki](https://riskofrain2.wiki.gg/wiki/Mithrix) ·
  [Monsters](https://riskofrain2.wiki.gg/wiki/Monsters) ·
  [Beetle Queen](https://riskofrain2.wiki.gg/wiki/Beetle_Queen)
- [Bosses — Dead Cells Wiki](https://deadcells.wiki.gg/wiki/Bosses) ·
  [The Blacksmith](https://deadcells.wiki.gg/wiki/The_Blacksmith) ·
  [The Blacksmith's Apprentice](https://deadcells.wiki.gg/wiki/The_Blacksmith's_Apprentice)
- [All Bosses — Hades 2 Wiki](https://hades2.wiki.fextralife.com/Bosses) ·
  [All Enemies](https://hades2.wiki.fextralife.com/Enemies)
- [Bosses — Cult of the Lamb Wiki](https://cult-of-the-lamb.fandom.com/wiki/Bosses)
- [Hiisi — The Noita Wiki](https://noita.wiki.gg/wiki/Hiisi) ·
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

- [Olmec — Spelunky Wiki](https://spelunky.fandom.com/wiki/Olmec_(2)) ·
  [Kali Altar](https://spelunky.wiki/wiki/Spelunky_2:Kali_Altar) ·
  [Shopkeeper](https://spelunky.fandom.com/wiki/Spelunky_2:Shopkeeper)
- [Enemies — Darkest Dungeon Wiki](https://darkestdungeon.wiki.gg/wiki/Enemies_(Darkest_Dungeon)) ·
  [Bosses](https://darkestdungeon.wiki.gg/wiki/Bosses_(Darkest_Dungeon)) ·
  [Shambler](https://darkestdungeon.wiki.gg/wiki/Shambler_(Darkest_Dungeon))
- [Units — Monster Train Wiki](https://monster-train.fandom.com/wiki/Units) ·
  [Seraph](https://monster-train.fandom.com/wiki/Seraph)
- [Kecleon Shop — Bulbapedia](https://bulbapedia.bulbagarden.net/wiki/Kecleon_Shop) ·
  [Kecleon Shops (dungeons) — Mystery Dungeon Franchise Wiki](https://mysterydungeonwiki.com/wiki/Rescue_Team:Kecleon_Shops_(dungeons))
- [Zombies — Cataclysm: DDA wiki](https://cataclysmdda.miraheze.org/wiki/Zombies) ·
  [Zombie master](https://srgnis.github.io/cdda-wiki/cdda_wiki/Zombie_master.html) ·
  [Monsters](https://srgnis.github.io/cdda-wiki/cdda_wiki/Monsters.html)
- [Robots — Cogmind (ModDB devlog)](https://www.moddb.com/games/cogmind/news/robots) ·
  [Cogmind — TV Tropes](https://tvtropes.org/pmwiki/pmwiki.php/VideoGame/Cogmind)
- [Curses — Curse of the Dead Gods Wiki](https://curseofthedeadgods.fandom.com/wiki/Curses) ·
  [Enemies](https://curseofthedeadgods.fandom.com/wiki/Enemies)
- [Sal — Griftlands Wiki](https://griftlands.fandom.com/wiki/Sal) ·
  [Characters in Griftlands — TV Tropes](https://tvtropes.org/pmwiki/pmwiki.php/Characters/Griftlands)
- [Weirdling Beast — Tales of Maj'Eyal](https://te4.org/wiki/Weirdling_Beast) ·
  [Ukruk the Fierce](https://te4.org/wiki/Ukruk_the_Fierce) ·
  [Monsters](https://te4.org/wiki/Category:Monsters)
- [Enemies — Loop Hero Wiki](https://loophero.fandom.com/wiki/Enemies) ·
  [Buildings](https://loophero.fandom.com/wiki/Buildings)
- [Companions — Wildfrost Wiki](https://wildfrost.fandom.com/wiki/Companions) ·
  [Pets](https://wildfrost.fandom.com/wiki/Pets) ·
  [Bosses/minibosses](https://wildfrost.fandom.com/wiki/Bosses/minibosses)
- [Survivor:Creatures — Deep Rock Galactic Wiki](https://deeprockgalactic.wiki.gg/wiki/Survivor:Creatures) ·
  [Creatures](https://deeprockgalactic.wiki.gg/wiki/Creatures)
- [Gorilla — Streets of Rogue Wiki](https://streetsofrogue.fandom.com/wiki/Gorilla) ·
  [Streets of Rogue Wiki](https://streetsofrogue.fandom.com/wiki/Streets_of_Rogue_Wiki)
- [Skulls — Skul: The Hero Slayer Wiki](https://skul.fandom.com/wiki/Skulls)
- [Leshy — Inscryption Wiki](https://inscryption.fandom.com/wiki/Leshy) ·
  [The Prospector](https://inscryption.fandom.com/wiki/The_Prospector)
- [Monkey — Brogue Wiki](https://brogue.fandom.com/wiki/Monkey) ·
  [Monsters](https://brogue.wiki/wiki/Category:Monster)
