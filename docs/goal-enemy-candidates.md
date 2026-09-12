# Goal → enemy candidates

Research notes for pairing new goal prompts with real roguelike enemies and
bosses, in the same style as the existing rows in `data/enemies2.0/` and
`data/bosses2.0/` (a real creature whose flavour or mechanic *is* the goal).

Written against the ~120 prompts in the September 2026 batch. Nothing here is
wired up: it is a shortlist to paste into the `enemies` / `bosses` sheets of
`tools/Roguelikes.xlsx` and regenerate from.

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
