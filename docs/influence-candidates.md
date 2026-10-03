# Influence candidates — for review

Tick `[x]` on the ones you've checked and approve. Only ticked rows get added to the `connections` sheet.
A line marked **✓ *on the chart*** is a row in the sheet now; what is still `[ ]` is what's left to decide.
`python3 tools/influence_research.py status` re-checks this list against the sheet, and `--tick` marks the new ones.

**Status (3 October 2026):** 96 lines are ticked. They cover 99 new rows, a first-hand source for
Vampire Survivors → Slime 3K, and two Spelunky Classic rows the sheet already had. Section 1 is all in except six lines: the three for 30XX, the two for Choo Choo
Survivor 2 (all store-page lists) and Hades → Nowhere Prophet. The 19 other open lines are the weaker
leads in sections 2 and 4d.
**New in section 4f (owned games with 0–1 connections):** 4 strong lines (7 rows), every one for an owned game with no connections today, and 1 weaker.
**New in section 4e (the degree-1 pass):** 14 strong lines (16 rows; eight of them give nine degree-1 games a second edge, since the Touhou row joins two) and 9 weaker ones, all unticked.
Format: **Influencer → Influencee** — quote — source.

How these were found, and how to find more: `docs/influence-research.md`.
Steam forum scan: **paused at 54 of 130** no-influence games. Progress is in `tools/influence_research_forums.jsonl`.

---

## 1. Strong — developer names the game as an influence

### Games with no connections at all
- [x] **Mystery Dungeon 2: Shiren the Wanderer → Crown Trick** ✓ *on the chart* — "we drew inspiration from the classic Shiren The Wanderer … in the 'synchronous turn-based combat'." — [Steam dev post](https://steamcommunity.com/games/1000010/announcements/detail/1712958942358263915) *(names the series; added as `Mystery Dungeon 2: Shiren the Wanderer`)*
- [x] **Backpack Hero → Footgun: Underground** ✓ *on the chart* — "Games like Backpack Heroes and Peglin were particularly impactful…" — [Rogueliker interview](https://rogueliker.com/footgun-underground-interview/)
- [x] **Peglin → Footgun: Underground** ✓ *on the chart* — same quote — [Rogueliker interview](https://rogueliker.com/footgun-underground-interview/)
- [x] **Brotato → Footgun: Underground** ✓ *on the chart* — "Brotato was where we got the idea of the merge mechanic for the item upgrade system." — [Rogueliker interview](https://rogueliker.com/footgun-underground-interview/)
- [x] **Nuclear Throne → Death Road to Canada** ✓ *on the chart* — Kepa Auwae: "Wasteland Kings was also an inspiration for the animations." *(Wasteland Kings = Nuclear Throne's prototype title)* — [Cheerful Ghost interview](https://cheerfulghost.com/jdodson/posts/1590/interview-with-death-road-to-canada-s-kepa-auwae)
- [x] **Diablo → Crawl** ✓ *on the chart* — Barney Cumming: "Diablo is a big influence…" — [Toogy Talk interview](https://toogytime.wordpress.com/2014/12/16/toogy-talk-crawl-an-interview-with-barney-cumming-of-powerhoof/)
- [x] **The Binding of Isaac → Crawl** ✓ *on the chart* — "Binding of Isaac worked as a less direct influence … I was very inspired by my wrongly-interpreted imaginings of what Isaac would be like" — [Toogy Talk interview](https://toogytime.wordpress.com/2014/12/16/toogy-talk-crawl-an-interview-with-barney-cumming-of-powerhoof/)
- [x] **FTL → Heat Signature** ✓ *on the chart* — Tom Francis: "Partly inspired by FTL, I show everything I can in 'natural' numbers." — [pentadact dev blog](https://www.pentadact.com/2015-09-25-natural-numbers-in-game-design/)
- [x] **Peglin → Kill the Brickman** ✓ *on the chart* — "Peglin, one of our biggest inspirations when Making Kill the Brickman" — [Steam dev post](https://steamcommunity.com/games/3123120/announcements/detail/502834694432228039)
- [x] **Endgame of Devil → Arcane Trigger** ✓ *on the chart* *(Dev/Series Relation)* — "From the Creators of 'Endgame of Devil'" — [Steam store page](https://store.steampowered.com/app/2981070/)

### Games with no recorded influences (they influence others)
- [x] **Enter the Gungeon → Hades** ✓ *on the chart* — Greg Kasavin: "Enter The Gungeon, The Binding Of Isaac, Darkest Dungeon, Spelunky, Rogue Legacy and Wizard Of Legend were just a few of the games we looked at that had excellent lessons in their structure and moment-to-moment play." — [GamesRadar](https://www.gamesradar.com/modern-roguelikes-are-in-great-shape-but-where-does-the-genre-go-next/)
- [x] **The Binding of Isaac → Hades** ✓ *on the chart* — same quote
- [x] **Darkest Dungeon → Hades** ✓ *on the chart* — same quote
- [x] **Spelunky Classic → Hades** ✓ *on the chart* *(the quote says Spelunky; added as Spelunky Classic)* — same quote
- [x] **Rogue Legacy → Hades** ✓ *on the chart* — same quote
- [x] **Wizard of Legend → Hades** ✓ *on the chart* — same quote
- [x] **The Binding of Isaac → Children of Morta** ✓ *on the chart* — Amir Fassihi: "other roguelike games like The Binding of Isaac, Rogue Legacy, Nuclear Throne." — [Cliqist Q&A](https://cliqist.com/2015/01/30/children-morta-interview/)
- [x] **Rogue Legacy → Children of Morta** ✓ *on the chart* — same quote
- [x] **Nuclear Throne → Children of Morta** ✓ *on the chart* — same quote
- [x] **Inscryption → Buckshot Roulette** ✓ *on the chart* — Mike Klubnika: "Overall, the mechanics and their presentation are mainly inspired by Inscryption." — [Steam Q&A post](https://steamcommunity.com/games/2835570/announcements/detail/4181107834755509907)

### Games already on the chart
- [ ] **The Binding of Isaac → 30XX** — "the replayability of a modern Roguelike (Binding of Isaac, Enter the Gungeon, Dead Cells, etc)" — [Steam store page](https://store.steampowered.com/app/1029210/)
- [ ] **Enter the Gungeon → 30XX** — same
- [ ] **Dead Cells → 30XX** — same
- [x] **Luck be a Landlord → Aotenjo: Infinite Hands** ✓ *on the chart* — "draws inspiration from many card-based rogue-like games such as Balatro, Luck be a Landlord, Monster Train, and Slay the Spire" — [Steam dev Q&A](https://steamcommunity.com/games/3066570/announcements/detail/4356754561281185320)
- [x] **Monster Train → Aotenjo: Infinite Hands** ✓ *on the chart* — same
- [x] **Slay the Spire → Aotenjo: Infinite Hands** ✓ *on the chart* — same
- [x] **Luck be a Landlord → Chosen Garden** ✓ *on the chart* — "We've drawn inspiration from classics like Balatro and Luck be a Landlord" — [Steam dev post](https://steamcommunity.com/games/3923750/announcements/detail/503962497384974869)
- [ ] **Vampire Survivors → Choo Choo Survivor 2** — "inspired by games like Vampire Survivors and Dome Keeper" — [Steam store page](https://store.steampowered.com/app/3494210/)
- [ ] **Dome Keeper → Choo Choo Survivor 2** — same
- [x] **Slay the Spire → Cross Blitz** ✓ *on the chart* — "inspired by … Hearthstone and Slay the Spire" — [Steam dev post](https://steamcommunity.com/games/1619520/announcements/detail/3692434297316940519)
- [x] **Diablo → Curse of the Dead Gods** ✓ *on the chart* — "Video games also heavily contributed to our inspirations with Diablo 3, and Gauntlet (2014) … or Hades" — [Steam dev post](https://steamcommunity.com/games/1123770/announcements/detail/1697231221626410268)
- [x] **Hades → Curse of the Dead Gods** ✓ *on the chart* — same
- [x] **Into the Breach → Dome Keeper** ✓ *on the chart* — "the biggest influences on Dome Keeper are Kingdom and Into the Breach." — [Steam dev post](https://steamcommunity.com/games/1637320/announcements/detail/4673137508062083951)
- [x] **Spelunky Classic → Feed the Deep** ✓ *on the chart* — "inspired by the likes of Dome Keeper and Spelunky" *(the sheet already had it as Spelunky Classic; this is the first-hand source for that row)* — [Steam store page](https://store.steampowered.com/app/2332260/)
- [x] **Backpack Hero → God of Weapons** ✓ *on the chart* — "Backpack Hero is the inspiration for the Inventory Management part of our game" — [Steam dev post](https://steamcommunity.com/games/2342950/announcements/detail/3801662447199262264)
- [x] **Diablo → God of Weapons** ✓ *on the chart* — "I just so happen to grow up with Diablo, so the gem system is our way of bringing the classics into our game." — [Steam dev post](https://steamcommunity.com/games/2342950/announcements/detail/524208404882784298)
- [x] **Magic Survival → HoloCure: Save the Fans!** ✓ *on the chart* — "gameplay heavily inspired by Vampire Survivors and Magic Survival" — [Steam store page](https://store.steampowered.com/app/2420510/)
- [x] **Magic Survival → Spirit Hunters: Infinite Horde** ✓ *on the chart* — "The combat … is inspired by Magical Survival and Vampire Survivors." — [Steam dev post](https://steamcommunity.com/games/1914580/announcements/detail/3096792662638547858)
- [x] **The Binding of Isaac → Nordic Ashes: Survivors of Ragnarok** ✓ *on the chart* — "inspired by top games like The Binding of Isaac and Rogue Legacy" — [Steam dev post](https://steamcommunity.com/games/2068280/announcements/detail/5301322539098227375)
- [x] **Rogue Legacy → Nordic Ashes: Survivors of Ragnarok** ✓ *on the chart* — same
- [ ] **Hades → Nowhere Prophet** — on its dialogue-driven writing: "Actually Hades was a big influence on that." — [Steam dev post](https://steamcommunity.com/games/NowhereProphet/announcements/detail/498341245287925959)
- [x] **868-Hack → Order Automatica** ✓ *on the chart* — "inspired by the games of Michael Brough, such as 868-hack and Cinco Paus." — [Steam dev post](https://steamcommunity.com/games/2105840/announcements/detail/670626757615813587)
- [x] **Slice & Dice → Order Automatica** ✓ *on the chart* — "This system takes inspiration from roguelikes like Shotgun King and Slice & Dice" — [Steam dev post](https://steamcommunity.com/games/2105840/announcements/detail/526488742956893954)
- [x] **Diablo → Our Darker Purpose** ✓ *on the chart* — "Don't Starve and FTL were also huge influences, as well as mainstream classic games like Diablo and Zelda" — [Steam dev post](https://steamcommunity.com/games/262790/announcements/detail/1694779751808309596)
- [x] **Don't Starve → Our Darker Purpose** ✓ *on the chart* — same
- [x] **Diablo → Picayune Dreams** ✓ *on the chart* — "Inspirations … Diablo (power scaling and item visualization)" — [Steam store page](https://store.steampowered.com/app/2088840/)
- [x] **Enter the Gungeon → Roboquest** ✓ *on the chart* — "modern roguelites such as Dead Cells, Enter the Gungeon, and Nuclear Throne" — [Steam dev post](https://steamcommunity.com/games/692890/announcements/detail/4599817768902300278)
- [x] **Peglin → Rogue Voltage** ✓ *on the chart* — "roguelikes, that served as inspiration for Rogue Voltage, such as Peglin, Backpack Hero and recently Backpack Battles" — [Steam dev post](https://steamcommunity.com/games/1494560/announcements/detail/4187858160655360600)
- [x] **Backpack Battles → Rogue Voltage** ✓ *on the chart* — same
- [x] **Slay the Spire → Rogue: Genesia** ✓ *on the chart* — "I thought of making a mix of Slay the Spire and Vampire Survivors." — [Steam dev post](https://steamcommunity.com/games/2067920/announcements/detail/3908626109457877555)
- [x] **Brogue → Rift Wizard** ✓ *on the chart* — "inspired by classics such as Nethack, Dungeon Crawl Stone Soup, Brogue, and Tales of Maj'Eyal" — [Steam store page](https://store.steampowered.com/app/1271280/)
- [x] **Brotato → Star Survivor** ✓ *on the chart* — "big call for those games I got inspirations from: Vampire Survivor, Brotato, SoulStone Survivors, 20 Minutes Till Dawn, Rogue: Genesia, Spellbook Demonslayers, Void Scrappers, Boneraiser Minions, Nova Drift…" — [Steam store page](https://store.steampowered.com/app/2060750/)
- [x] **Soulstone Survivors → Star Survivor** ✓ *on the chart* — same
- [x] **20 Minutes Till Dawn → Star Survivor** ✓ *on the chart* — same
- [x] **Rogue: Genesia → Star Survivor** ✓ *on the chart* — same
- [x] **Spellbook Demonslayers → Star Survivor** ✓ *on the chart* — same
- [x] **Void Scrappers → Star Survivor** ✓ *on the chart* — same
- [x] **Boneraiser Minions → Star Survivor** ✓ *on the chart* — same
- [x] **Nova Drift → Star Survivor** ✓ *on the chart* — same
- [x] **Dicey Dungeons → Words Can Kill** ✓ *on the chart* — "a spelling roguelike game hugely inspired by Slay the Spire and Dicey Dungeons." — [Steam dev post](https://steamcommunity.com/games/1732090/announcements/detail/3328736922033412095)

### Better source for a row already in the sheet
- [x] **Vampire Survivors → Slime 3K: Rise Against Despot** ✓ *on the chart* *(source currently "look at it")* — "inspired by games like Vampire Survivors and auto-chess games." — [Steam dev post](https://steamcommunity.com/games/1227280/announcements/detail/4522268823003961902)

---

## 2. Weaker — paraphrased, feature-level, or vague

- [ ] **Risk of Rain 2 → Godbreakers** — journalist relaying the devs' presentation: "To The Sky also gave specific shoutouts to Risk Of Rain 2, and of course, Hades." — [DualShockers](https://www.dualshockers.com/godbreakers-hands-on-preview-reveal/)
- [ ] **Hades → Godbreakers** — same
- [x] **Dead Cells → Hades** ✓ *on the chart* — journalist paraphrase: "He also singles out Dead Cells for its crisp, responsive feel" — [GamesRadar](https://www.gamesradar.com/modern-roguelikes-are-in-great-shape-but-where-does-the-genre-go-next/)
- [x] **Slay the Spire → Hades** ✓ *on the chart* — journalist paraphrase: "…and Slay The Spire for its character choices and endgame Ascension modes" — same
- [ ] **Spelunky → Heat Signature** — "a Story Generator … the common thread between my love for Deus Ex, Spelunky and Invisible Inc." — [pentadact](https://www.pentadact.com/2017-09-27-heat-signatures-launch-and-first-player-legend/)
- [ ] **Hades → Arcanium: Rise of Akhan** — "A mix of Hades' 'Heats' system and Slay the Spire's 'Ascension' system" — [Steam dev post](https://steamcommunity.com/games/1056840/announcements/detail/3031459393707667773)
- [ ] **Cogmind → Jupiter Hell** — "a new general purpose level generator (inspired by the awesome roguelike Cogmind)" — [Steam dev post](https://steamcommunity.com/games/811320/announcements/detail/1610515908993060550)
- [ ] **Die in the Dungeon → Peglin** *(backwards by the chart's years: the sheet dates Die in the Dungeon 2025 and Peglin 2022. The post is a later Peglin update crediting Die in the Dungeon's early-access version, so it only fits if you're happy with an edge running back in time)* — "Die in the Dungeon: (inspired 2 of the new relics :) )" — [Steam dev post](https://steamcommunity.com/games/1296610/announcements/detail/3639508760838054968)
- [ ] **Sil → Tangledeep** — one job "Inspired by the roguelike Sil" — [Steam dev post](https://steamcommunity.com/games/628770/announcements/detail/1464092108240056336)
- [ ] **Astral Ascent → Voin** — forge mechanic "pretty much inspired by The Forge from Astral Ascent" — [Steam dev post](https://steamcommunity.com/games/2464530/announcements/detail/3860212413410895582)
- [x] **Stoneshard → The Last Spell** ✓ *on the chart* — pixel-art inspiration — [Steam dev post](https://steamcommunity.com/games/1105670/announcements/detail/2996568545566483264)
- [ ] **Heretic's Fork → Slime 3K: Rise Against Despot** — "a new ability that pays tribute to Heretic's Fork" — [Steam dev post](https://steamcommunity.com/games/2348610/announcements/detail/4025723667734553082)
- [x] **Revita → Tiny Rogues** ✓ *on the chart* — "BenStar has been an inspiration for myself ever since I caught my first glimpse of Revita." *(Revita → Tiny Rogues is already on the sheet; this is a first-hand source for it.)* — [Steam dev post](https://steamcommunity.com/games/2088570/announcements/detail/6770639657665738311)
- [x] **Risk of Rain 2 → Soulstone Survivors** ✓ *on the chart* — said of their next project, then "(which also became a core concept of Soulstone Survivors)" — [Steam dev post](https://steamcommunity.com/games/2066020/announcements/detail/538872373928001896)
- [ ] **The Binding of Isaac → Picayune Dreams** — "Schism had similar inspirations as Picayune Dreams, following … The Binding of Isaac and Nuclear Throne." — [Steam post](https://steamcommunity.com/games/2088840/announcements/detail/3685688504882617185)
- [ ] **Nuclear Throne → Picayune Dreams** — same
- [ ] **Balatro → Slots & Daggers** — "I had thought about gambling and casino-style mechanics, and how they have inspired very successful recent titles like Balatro or Vampire Survivors." — [indiegames.wtf interview](https://indiegames.wtf/interviews/slots-daggers-the-roguelite-between-luck-and-strategy/)
- [ ] **Vampire Survivors → Slots & Daggers** — same

---

## 3. Do NOT add — the developer denies it
- **Vampire Survivors → Death by Scrolling** — Ron Gilbert: "I love Vampire Survivors, but no." — [grumpygamer](https://www.grumpygamer.com/dbs_history/)
- **Blue Prince** — Tonda Ros says no roguelike or deckbuilder influence on the core design — [Thinky Games](https://thinkygames.com/features/interview-how-myst-riven-and-tabletop-games-built-the-foundation-of-blue-prince/)
- **Loop Hero** — devs say no specific game inspired it — [Game Rant](https://gamerant.com/loop-hero-interview/)

---

## 4. Steam forum scan — developer posts (partial: 54 of 130 games)

- [x] **Roboquest → Deadzone: Rogue** ✓ *on the chart* *(no connections yet)* — "Pluto", answering "How is this game compared to Roboquest?": "Roboquest's a great game! Definitely helped inspire some of our gameplay. We will have crossplay enabled once our game goes live on consoles…" — [Steam forum](https://steamcommunity.com/app/3228590/discussions/0/591779267908673222/#c591779267908675739) *(Pluto's reply carries Steam's developer badge, so this is the developer)*

The other forum matches so far are players (suggestions and guesses), not developers.

## 4b. Native-language sources (studios that don't work in English)

Quotes are in the original language with a translation. Check the translation against the source before ticking.

- [x] **Uma Musume: Pretty Derby → Drapline** ✓ *on the chart* *(both have no connections yet)* — KANAWO: 「主に『プリンセスメーカー』や『ウマ娘 プリティーダービー』、『モンスターファーム』などの育成シミュレーションゲームは理想形として大いに参考にしています。」 ("We referenced raising sims like Princess Maker, Uma Musume Pretty Derby and Monster Rancher heavily, as the ideal form.") — [Game*Spark interview](https://www.gamespark.jp/article/2025/07/24/155340.html)
  - *Slay the Spire → Drapline was checked and isn't sourced.* KANAWO's own list of influences (above) doesn't include it, and neither do the game's Steam page or announcements. The only comparison ("Slay the Spire とか学園アイドルマスターとか、そういった感じだ", "it's like Slay the Spire or Gakuen Idolmaster") is from a player's note.com write-up. — [note.com](https://note.com/ipusiro/n/n3a8ffeb83ef8)
- [x] **Rounds → Section 13** ✓ *on the chart* *(both have no connections yet)* — 박재은 PD (Park Jae-eun): 「그는 '섹션 13' 개발에 영감을 준 게임으로 랜드폴게임즈의 로그라이크 PvP 게임 '라운즈(ROUNDS)'를 꼽았다.」 ("He named Landfall's roguelike PvP game ROUNDS as a game that inspired Section 13's development", for its gun effects.) *(reporter's paraphrase of what the PD said, at Gamescom 2024)* — [Daum / gamescom interview](https://v.daum.net/v/pIwu8NNfMg?f=p)
- [x] **Slay the Spire → Super Bullet Break** ✓ *on the chart* — BeXide president 南治 (Minamiji): 「開発スタッフのひとりが『Slay the Spire』が好きで、ローグライク（ローグライト）って方向でやってみたら…いいんじゃないかって案が出てきまして」 ("One of the dev staff liked Slay the Spire, and the idea came up to try the roguelike direction.") — [Gamecast interview](https://www.gamecast-blog.com/archives/66001023.html)
- [x] **Mystery Dungeon 2: Shiren the Wanderer → Million Depth** ✓ *on the chart* — αPop (director): 「ゲームシステムの面では、『風来のシレン』シリーズから影響を受けています。」 ("On the game-system side, it was influenced by the Shiren the Wanderer series.") He names *Shiren 6 (Serpentcoil Island)* as his favourite game. The quote is about the series; added as `Mystery Dungeon 2: Shiren the Wanderer`. — [Game*Spark interview](https://www.gamespark.jp/article/2025/12/23/160936.html)
- [x] **Hades → Metallic Child** ✓ *on the chart* — 한대훈 (Han Dae-hoon, director): 「하데스를 플레이했는데, 너무 잘 만들었던 거죠… 거기서 자극을 받았고… 기준치가 올라간 거죠.」 ("I played Hades and it was so well made… I was spurred on by it, and my bar went up.") He gives this as why development ran three years instead of one. — [Ruliweb interview](https://bbs.ruliweb.com/news/read/152932)
- [x] **Dota Auto Chess → Despot's Game** ✓ *on the chart* — Nikolai Kuznetsov (Konfa Games): «На месте "X" были, например, "Герои меча и магии", Beat Cop в России и Auto Chess. Победили последние.» ("For 'X' [take X, add permadeath and randomness] we had Heroes of Might and Magic, Beat Cop and Auto Chess. The last one won.") Also: the class abilities "это тоже от Auto Chess" ("are also from Auto Chess"). *(Says "Auto Chess"; the sheet's row is `Dota Auto Chess`.)* — [DTF interview](https://dtf.ru/gamedev/141739-otzyvy-i-obshenie-na-meropriyatiyah-uchat-luchshe-lyubyh-kursov-beseda-s-avtorom-rogalika-despots-game)
- [x] **Inscryption → Lethal Dungeon** ✓ *on the chart* — にほへ (Nihohe Soft): 「『Inscryption』や『Shadowverse』など色んなカードゲームにも影響を受けていますが、『Baba Is You』には特に影響を受けています。」 ("I was influenced by card games like Inscryption and Shadowverse, and especially by Baba Is You.") *(Baba Is You isn't on the chart.)* — [Game*Spark interview](https://www.gamespark.jp/article/2026/05/10/166209.html)

### Checked in the native language: not influences
- **Skul**: "Dead Cells became the benchmark" is about sales targets, not design. — [Inven](https://www.inven.co.kr/webzine/news/?news=302719)
- **Loop Hero**: Russian interviews also say no specific inspiration ("Трудно назвать конкретные примеры", "Hard to name specific examples"), and the artist had never heard of Eador, the game players compare it to. — [DTF](https://dtf.ru/gamedev/660318-igrok-dolzhen-iskat-uyazvimosti-i-brat-ih-na-vooruzhenie-beseda-s-avtorami-loop-hero), [Skillbox](https://skillbox.ru/media/gamedev/intervyu_s_avtorami_loop_hero_geymdzhemy_rabota_s_krupnym_izdatelem_i_sovety_novichkam/)
- **Million Depth ← SUPERHOT**: αPop says he hadn't heard of it when he built the time-stop system, and has avoided playing it. — [AUTOMATON](https://automaton-media.com/articles/interviewsjp/million-depth-20251010-361085/)
- **Juicy Realm ← Isaac / Nuclear Throne / Gungeon**: only a news write-up says so. SpaceCan's own dev log and the Gcores feature name no games.

### Leads not yet confirmed
- **Gumballs & Dungeons**: Baidu Baike says the producer's letter (制作者的信) names 《地牢爬行》 and 《符石守护者》 as inspirations. The letter itself wasn't found, and which games those titles are needs checking.

## 4c. Hand search, round 3

- [x] **FTL → Guild of Dungeoneering** ✓ *on the chart* — Colm Larkin: "Design inspirations to me were playing games like FTL and Spelunky which took the rogue-like idea and ran with it." — [Gamasutra interview](https://www.gamedeveloper.com/business/paper-heroes-colm-larkin-and-guild-of-dungeoneering)
- [x] **Spelunky Classic → Guild of Dungeoneering** ✓ *on the chart* *(the quote says Spelunky; added as Spelunky Classic)* — same quote
- [x] **NetHack → Realm of the Mad God** ✓ *on the chart* — Alex Carobus: "RotMG was really born out of a love of roguelikes, arcade games and a deep disappointment with MMOs… I wanted to make an MMO that was as fun to play as an old arcade game, as re-playable as NetHack or Spelunky" — [Road to the IGF interview](https://www.gamedeveloper.com/design/road-to-the-igf-spry-fox-s-and-wild-shadow-studios-i-realm-of-the-mad-god-i-#:~:text=re-playable)
- [x] **Spelunky Classic → Realm of the Mad God** ✓ *on the chart* — same quote *(RotMG is 2010, so this is the 2008 freeware Spelunky; Spelunky (2012) came after it)*

### Roguelikes you don't have, named as influences
Games a developer names that aren't on the chart but are roguelikes themselves, so they may be worth adding:

- **Prospector** (2011, freeware space roguelike) → Approaching Infinity. IBOL, first-hand: "I will admit, I got oxygen and data from prospector" — [his blog, "My Inspiration"](https://ibol17.wordpress.com/inspiration/)
- **PernAngband** (Angband variant) → Tales of Maj'Eyal: ToME began as a PernAngband fork; its lineage, not a quote.
- **Shadowcrypt** (2014, Steam) → Dark Devotion, *if you count it as a roguelike*. Louis Denizet: "At this time the game was inspired by Steam game Shadowcrypt" — [itch.io prototype page](https://louis-denizet.itch.io/dark-devotion-prototype)

### Off the chart (only if you add the game)
- **Beneath Apple Manor** ← Dragon Maze (Apple II), Colossal Cave Adventure, and D&D. Don Worth, by email to the CRPG Addict. — [CRPG Addict](http://crpgaddict.blogspot.com/2012/12/game-79-beneath-apple-manor-1978.html)
- **Dota Auto Chess** ← Mahjong (Drodo Studio). — [SCMP / Abacus](https://www.scmp.com/abacus/games/article/3029173/how-popular-pc-gaming-hit-was-influenced-ancient-game-mahjong)
- **Curious Expedition** ← *The Adventures of Tintin* comics ("one big inspiration we already had for the first game"). — [GamingBolt](https://gamingbolt.com/curious-expedition-2-interview-roguelike-expeditions)
- **Drapline** also names Princess Maker, Monster Rancher, Rance X and the Atelier series; **Lethal Dungeon** also names Baba Is You and Shadowverse.
- **Captain Forever Remix** ← Battleships Forever: "The core idea was inspired by Sean 'th15' Chan's Battleships Forever." (Farbs) — [post-mortem](http://farbs.org/captain-forever-post-mid-something-mortem-pt-i)
- **Granvir** ← Armored Core (the expensive-ammo idea) and Persona (alternating missions and downtime), from its developer. — [Game Dev Journey](https://www.gamedevjourney.co.uk/home/developer-diaries/unity-diaries/granvir)
- **OTXO** ← Hotline Miami; **Death Road to Canada** ← Rebuild, Oregon Trail, River City Ransom; **Battle Brothers** ← X-COM, Jagged Alliance, Mount & Blade; **Don't Starve** ← Minecraft, Lost in Blue; **Rogue** ← Colossal Cave Adventure; **SNKRX** ← Nimble Quest, Dota Underlords (from the first pass)

### Searched, nothing first-hand found
West of Dead (its interview names only comic artists), Seraph's Last Stand (based on the Flash game Heli Attack), Bleak Sword (Souls series), Heroes of Hammerwatch, Popup Dungeon (tabletop games), Block Tower TD, Super House of Dead Ninjas, Morsels, Ringer, Wireworks, Goblin Sushi, Coal LLC, Auto Rogue, Geometry Arena, Elden Ring Nightreign, Crown Trick (beyond its Steam post), Cubic Cosmos, The Fable, The King is Watching, Loot River, Stories from the Outbreak, Necroking, Necrosmith, Sword of Fargoal (from McCord's own Gammaquest II), CastlevaniaRL, DoomRL, Kingdom: New Lands (began as a horse animation, no game named), Cryptark, Double Dragon Gaiden, Bloons TD 6: Rogue Legends, Flick Shot Rogues and Evolings (German studios, searched in German too), Node Farm, No-Skin. "Closer to Peglin" for Flick Shot Rogues is a journalist's description, not the studio's.

## 4d. Games with only one recorded influence (group 2), first pass

Searched about 45 of the 328 games that have exactly one outside influence on the sheet, starting with the best-known.

- [x] **Weird Worlds: Return to Infinite Space → FTL** ✓ *on the chart* — Subset Games: "The core gameplay interactions were largely inspired by boardgames like Red November and Battlestar Galactica while the pacing and exploration was influenced by computer games like Weird Worlds and Spelunky." — [RPG Codex interview](https://rpgcodex.net/content.php?id=8133)
- [x] **Dwarf Fortress → Caves of Qud** ✓ *on the chart* — Jason Grinblat, asked "What games influenced Caves of Qud the most?": "Ancient Domains of Mystery (ADoM), Dwarf Fortress, Morrowind, and Star Control II." — [Review Fix interview](https://reviewfix.com/2018/08/review-fix-exclusive-inside-caves-of-qud/)
- [x] **Rogue → Unexplored** ✓ *on the chart* — Joris Dormans: "the whole tradition of roguelikes is still very important to us, so there is basically everything that builds up to Unexplored 1, from Brogue to Rogue itself to Nethack and all the influences that they carry over." — [The Young Folks interview](https://www.theyoungfolks.com/video-games/154551/interview-joris-dormans-details-the-gameplay-and-story-of-unexplored-2/)
- [x] **NetHack → Unexplored** ✓ *on the chart* — same quote
- [x] **Enter the Gungeon → Neon Abyss** ✓ *on the chart* — Yop (lead designer): "for Neon Abyss, we drew more inspiration from well-known roguelikes like The Binding of Isaac, Enter the Gungeon, and Dead Cells." — [GameGrin interview](https://www.gamegrin.com/articles/developer-interview-neon-abyss-2-veewo-games/)
- [x] **Dead Cells → Neon Abyss** ✓ *on the chart* — same quote
- [x] **Nuclear Throne → Spellmasons** ✓ *on the chart* — Jordan O'Leary: 「インスピレーションを主に受けたのは、『Nuclear Throne』『Magicka』、iOSの『Hopile』、そして『Into the Breach』です。中でも一番大きな影響を受けたのは、『Into the Breach』ですね。」 ("My main inspirations were Nuclear Throne, Magicka, Hoplite on iOS, and Into the Breach. Into the Breach was the biggest.") *("Hopile" is the interview's misspelling of Hoplite.)* — [Game*Spark interview](https://www.gamespark.jp/article/2023/02/15/127110.html)
- [x] **Hoplite → Spellmasons** ✓ *on the chart* — same quote

#### Second pass
- [x] **NetHack → Ancient Domains of Mystery** ✓ *on the chart* — Thomas Biskup, on how ADOM started: "at that time I had played games like DND, Rogue, Hack and NetHack (and seen Omega) and loved the genre… But when I started diving into the NetHack sources (which seemed to be the most detailed and thus most interesting candidate) I quickly learned how advanced and complicated those sources were. Which lead me to believe that it might be much simpler to write a game of my own." — [@Play interview](https://www.gamedeveloper.com/design/-play-86-interview-with-adom-creator-dr-thomas-biskup)
- [x] **Ziggurat → Immortal Redneck** ✓ *on the chart* — Crema's devlog: "INSPIRATION: Our main references are Ziggurat and Rogue Legacy, but there are bits of other roguelites here and there as well as some old school shooters." — [itch.io devlog](https://itch.io/t/9805/immortal-redneck-the-definitive-redneck-fps-roguelite)
- [x] **Enter the Gungeon → Immortal Redneck** ✓ *on the chart* — Paños (Crema), asked which past games influenced it: "we took many things from many games: Redneck Rampage, Doom, Quake, Unreal Tournament, Serious Sam, Rogue Legacy, Enter the Gungeon, Spelunky…" — [Review Fix interview](https://reviewfix.com/2018/03/review-fix-exclusive-inside-immortal-redneck/)
- [x] **Spelunky Classic → Immortal Redneck** ✓ *on the chart* — same quote *(the sheet has both Spelunky and Spelunky Classic; added as Spelunky Classic)*

#### Third pass
- [x] **FTL → Nuclear Throne**, **Spelunky Classic → Nuclear Throne**, **The Binding of Isaac → Nuclear Throne** ✓ *on the chart* *(Spelunky added as Spelunky Classic)* *(medium: the journalist's paraphrase of Rami Ismail, and worded as a description)* — "Wasteland Kings [Nuclear Throne's working title] can also be described as a mix of other people's games: FTL, Spelunky and The Binding of Isaac, Ismail says." — [Engadget](https://engadget.com/2013/08/15/wasteland-kings-is-vlambeers-next-big-little-game)

#### Fourth pass
- [x] **Spelunky Classic → Mr. Sun's Hatbox** ✓ *on the chart* *(the sheet already had it as Spelunky Classic)* — Kenny Sun: "I stole that idea and combined it with elements from another favorite game of mine, Spelunky." and "I stole the boomerang from Spelunky" — [Road to the IGF 2023](https://www.gamedeveloper.com/road-to-igf-2023/road-to-the-igf-2023-kenny-sun-s-mr-sun-s-hatbox) *(the sheet has only Spelunky Classic as an influence; from the timing this is Spelunky, 2012)*

#### Fifth pass
- [x] **Soulstone Survivors → Vampire Hunters**, **Brotato → Vampire Hunters** ✓ *on the chart* — Tiago Zaidan (Gamecraft Studios), asked what games influenced it: "The two most obvious influences are Vampire Survivors and Doom, but we also drew a lot of inspiration from COD Zombies, Serious Sam, and Killing Floor. During development, we were additionally influenced by other survivors games like Soulstone Survivors and Brotato." — [What's It Like interview](https://www.whatsitlike.com.au/interview-with-tiago-zaidan-vampire-hunters/) ([archived copy](https://web.archive.org/web/20250811102650/https://www.whatsitlike.com.au/interview-with-tiago-zaidan-vampire-hunters/), if the site won't open for you)
- [x] **Enter the Gungeon → Patch Quest** ✓ *on the chart* — Lychee Game Labs' solo developer, asked what inspired the game: "The basic gameplay resembles Enter the Gungeon or the Binding of Isaac. But the monster-taming element feels more like Pokemon or Super Mario Odyssey." — [Niche Gamer interview](https://nichegamer.com/patch-quest-interview/) *(the live page blocks fetching; it was read in an archived copy. "Resembles" is his word, in his answer to the inspiration question, and Isaac, already on the sheet, is in the same sentence)*
- [x] **Dicey Dungeons → Sol Cesto** ✓ *on the chart* — Géraud Zucchini, in French: « Dicey Dungeon (Terry Cavanagh, 2019) a été une influence. » ("Dicey Dungeons was an influence.") — [Vallées de l'Etrange interview](https://valleesdeletrange.wordpress.com/2026/03/09/sol-cesto-le-bandit-manchot-et-ses-deux-tetes-entretien-avec-chariospirale-et-docgeraud/)
- [x] **Inscryption → Sol Cesto** ✓ *on the chart* — same answer: « Inscryption aussi, mais plus pour la partie ambiance, le côté puzzle méta. » ("Inscryption too, but more for the atmosphere and the meta-puzzle side.") *(limited to atmosphere and the meta-puzzle)*
- [x] **Enter the Gungeon → Cavity Busters** ✓ *on the chart* — the developer, on the game's itch.io page: "At first glance, Cavity Busters looks like an Enter the Gungeon or Binding of Isaac clone. While both are huge inspirations, Cavity Busters plays much different." — [itch.io](https://spacemyfriend.itch.io/cavity-busters)

### Weaker
- [ ] **Sunless Sea → Abandon Ship** *(unconfirmed)* — attributed to Fireblade Software: "We always wondered why a game didn't exist that combined the tactical combat of games like FTL with the exploration mechanics of titles such as Sunless Sea". The only source is a Gamewatcher article that blocks fetching, so I couldn't read it in context. Gary Burchell's own interview names only FTL. — [Gamewatcher](https://www.gamewatcher.com/news/2017-04-10-abandon-ship-is-a-fantasy-ship-exploration-game-that-combines-ftl-with-sunless-sea), [Big Boss Battle](https://bigbossbattle.com/abandon-ship-interview-fireblade-softwares-gary-burchell/)
- [x] **Rogue → Ancient Domains of Mystery** ✓ *on the chart* — same Biskup quote: Rogue is among the games he'd played and loved before starting. It isn't named as a model the way NetHack is.
- [x] **Omega → Caves of Qud** ✓ *on the chart* — Brian Bucklew, on starting out: "I was playing games like Omega and Atom [ADOM], and roguelikes like that, that had these big worlds" — [RPG Site interview](https://www.rpgsite.net/interview/20000-brian-bucklew-caves-of-qud-interview-expansions-switch-port-unity-controller-support-coffee)
- [x] **Don't Starve → Sunless Sea** ✓ *on the chart* — a journalist relaying Failbetter's announcement: "Failbetter cites as their influences FTL, Don't Starve, Elite, Sid Meier's Pirates". Failbetter's own post wasn't found. — [Quarter to Three](https://www.quartertothree.com/fp/2013/07/30/ten-things-you-should-know-about-sunless-sea/)
- [x] **Larn → Castle of the Winds**, **Omega → Castle of the Winds**, **NetHack → Castle of the Winds** ✓ *on the chart* *(the interviewer's summary, not Rick Saada's own words)* — "he started work on a program inspired by his love of Rogue, Noah Morgan's Larn, the Laurence Brothers' Omega and Nethack" — [Game Developer interview](https://www.gamedeveloper.com/game-platforms/playing-catch-up-i-castle-of-the-winds-i-rick-saada)
- [ ] **Slay the Spire → Drop Duchy**, **Dicey Dungeons → Drop Duchy** *(journalists only)* — Digital Trends: "Drop Duchy takes some immediate notes from a much different game: Slay the Spire"; Polygon: "not unlike Dicey Dungeons or Balatro". The developer's 16 devlogs name only Balatro. — [Digital Trends](https://www.digitaltrends.com/gaming/drop-duchy-puzzle-game-preview/)
- [ ] **Diablo → SULFUR** *(UI only)* — Perfect Random: "When we updated the UI for the Steam Deck, we had taken inspiration from games like Diablo, Escape from Tarkov, and thankfully Resident Evil 4." — "How We Make SULFUR Feel at Home on Steam Deck", Steam announcement, Oct 2024 *(its page no longer opens, so it looks removed; the text is still in Steam's [news feed](https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=2124120&count=100&maxlength=0), search it for "Diablo")*
- [x] **Returnal → SULFUR**, **Iter Vehemens Ad Necem → SULFUR** ✓ *on the chart* *(paraphrase; IVAN is the chart's Iter Vehemens Ad Necem)* — GameDiscoverCo's writer: "the devs cite everything from NetHack-influenced 2D roguelike IVAN (!) to games like Returnal and Dark Souls" — [GameDiscoverCo](https://newsletter.gamediscover.co/p/how-sulfur-sold-50k-real-fast-and)
- [ ] **Rogue Legacy → In Celebration of Violence**, **The Binding of Isaac → In Celebration of Violence** *(a pitch comparison, not worded as inspiration)* — Julian Edison, on the store page: "This is like if The Binding of Isaac and Dark Souls got smushed together. And Rogue Legacy is is there too. And Hammerwatch." — [Steam](https://store.steampowered.com/app/509570)
- [ ] **NetHack → Approaching Infinity** *(admiration, not called an influence)* — IBOL: "I'm much more impressed with stuff like nethack, where 'the dev team thinks of everything'. I don't think of everything, but I like to throw my players the occasional curve-ball." — [BlindiRL interview](https://www.blindirl.com/august-12-24/)
- [ ] **Dead Cells → Curse of the Dead Gods** (feature) — "Vault rooms (Cursed Chests in Dead Cells): A new room type inspired by the Cursed Chest in Dead Cells!" — [Steam dev post](https://steamcommunity.com/games/1123770/announcements/detail/3046097994804047794)

### Checked: the developer says no
- **Balatro ← Slay the Spire**: LocalThunk had never played it and "cut myself off from the genre at that point intentionally". — [GamesRadar](https://www.gamesradar.com/astonishingly-balatros-creator-had-never-even-played-slay-the-spire-and-intentionally-cut-myself-off-from-roguelikes-to-create-the-best-game-possible/)
- **Dicey Dungeons ← Slay the Spire**: Terry Cavanagh avoided playing it because the two games explore the same design space; both come from Dream Quest. — [Wireframe](https://wireframe.raspberrypi.com/articles/dicey-dungeons-terry-cavanagh-interview)
- **Cogmind ← Paradroid**: Josh Ge had never heard of it before release. Cogmind came from Battletech and a forum post. — [@Play interview](https://www.gamedeveloper.com/design/-play-87-interview-with-josh-ge-creator-of-cogmind)
- **Dungeons & Degenerate Gamblers ← Balatro**: asked on itch.io "inspired by balatro?", the developer replied "Nope!" and linked LocalThunk's own tweet noting it was announced before Balatro. — [itch.io](https://purplemosscollectors.itch.io/dndg), [Mental Health Gaming interview](https://www.mentalhealthgaming.com/interview-with-a-degenerate/)

### Searched, nothing new beyond what the sheet has
Spelunky Classic (NetHack is on the sheet; a Dwarf Fortress claim couldn't be traced to Derek Yu), Downwell, Pixel Dungeon, Desktop Dungeons, Luck be a Landlord, Vampire Survivors (its other influences, Castlevania and Lapis x Labyrinth, aren't on the chart), Monster Train, Super Auto Pets, Peglin, Griftlands, Darkest Dungeon 2, Void Bastards, Crying Suns, Tower of Guns, Eldritch, Hand of Fate, Ring of Pain (Monster Train is a journalist's claim; the Isaac mention is about games he plays), Gunfire Reborn, Revita, Nova Drift, Book of Demons, Dwarf Fortress, Brogue, Dungeons of Dredmor, Noita (its Steam page and Road to the IGF name only Spelunky).
Second pass: Larn, Tales of Maj'Eyal (its lineage runs through PernAngband, which isn't on the chart), Teamfight Tactics, Monster Slayers, Dungreed, Strafe (Spelunky; the sheet already has Spelunky Classic), Sundered, Star of Providence, Fear & Hunger (NetHack is already on the sheet), BPM: Bullets Per Minute (the "Binding of Isaac" line couldn't be traced to the developers), Have a Nice Death (the studio says it has "fans of" Isaac, FTL, Dead Cells and Hades, not that they influenced the game), Witchfire, Deep Rock Galactic: Survivor, Dave the Diver (Torneko is already on the sheet), 20 Minutes Till Dawn, Absolum, StarVaders (its origin is two board games, Bullet and Under Falling Skies), Lost in Random: The Eternal Die.
Third pass: Sil, Golden Krone Hotel, 868-Hack (Rogue is on the sheet; the other inspirations are Race for the Galaxy, DOTA and SpaceChem), The Flame in the Flood, Coin Crypt (Spelunky Classic is on the sheet; also Dominion and Terry Cavanagh's Nexus City prototype), Legend of Dungeon, Convoy, Renowned Explorers, Synthetik, Trials of Fire, Roguebook, Banners of Ruin, Vault of the Void, Muck, Terraformers, Swordship, A Robot Named Fight (Isaac is on the sheet; also Super Metroid), Caveblazers.
Fourth pass: Moria (Rogue only), Angband (Moria only), Wall World (a journalist says Alawar are Dome Keeper fans; Dome Keeper is already on the sheet), Gordian Quest (Slay the Spire is on the sheet; also D&D, Path of Exile, Wizardry, Ultima), Rogue Lords (reviewers only), Hadean Tactics, Knock on the Coffin Lid (Slay the Spire, already on the sheet), Voidigo (the developer is a fan of Nuclear Throne, already on the sheet, and Monster Hunter; Enter the Gungeon comes only from reviewers).
Fifth pass: Rocket Rats, Bloodshed (Blood and Hexen, off the chart), Scarlet Tower, Rogue Heroes: Ruins of Tasos (Zelda / A Link to the Past, off the chart), Breach Wanderers (Slay the Spire is on the sheet; also Magic and Hearthstone), Starlight Revolver (Hades is on the sheet; also Gaia Online, Club Penguin, MapleStory), Sworn (Hades confirmed by the developer), Yasha: Legends of the Demon Blade (no first-hand source found even for the existing Hades row), Tower Dominion, Drop Duchy (Balatro confirmed, feature-level; also Carcassonne, Cartographers, Dorfromantik per Polygon's paraphrase), Primordialis, Solitairica (Puzzle Quest, off the chart; FTL wasn't found in the developer's words), Hand of Fate 2, Rampage Knights (Golden Axe, off the chart), Approaching Infinity (Prospector, Star Control 2 and others, off the chart), Cupiclaw (Luck be a Landlord confirmed; also Yakuza's UFO Catcher and Part-Time UFO). Metal Slug Tactics (Into the Breach confirmed; XCOM 2 only when the interviewer raised it), Ballionaire (Luck be a Landlord confirmed; the art took from Parappa the Rapper, Katamari Damacy, Pikuniku, Undertale), He is Coming, Aethermancer (the studio's own Monster Sanctuary, off the chart), Katanaut (Dead Cells confirmed; also Katana Zero, Ninja Gaiden, Dead Space), Helskate (Risk of Rain is a reviewer's comparison), Zorbus (tabletop D&D only), Dark Devotion (Shadowcrypt and Dark Souls, off the chart; Diablo is the press's word), The Void Rains Upon Her Heart (Isaac confirmed; also Undertale and Kirby), Colt Canyon (Nuclear Throne confirmed; also Hotline Miami, Hunt: Showdown and Sandstorm. Retrific is German, not Spanish).

## 4e. Games with only one connection (degree 1), October 2026

A pass over the games that touch the map by a single edge (335 of them after the October import; 244 not already covered above). Every one got the automated sweep: their own Steam store page and developer announcements, read for "from the creators of", "sequel to", "inspired by", "fans of" and the like next to another chart game's name, and `samedev` filtered to them. About 45 of the better-known ones were also searched by hand for interviews. Most of the rest are survivors-likes and Balatro-likes whose developers only ever name the one game the sheet already has.

### Strong
- [ ] **Despotism 3k → Slime 3K: Rise Against Despot** *(Dev/Series Relation)* — Konfa Games, on Slime 3K's store page: "this action-packed roguelite from the creators of Despot's Game and Despotism 3K." — [Steam store page](https://store.steampowered.com/app/2348610/)
- [ ] **Halls of Torment → Slime 3K: Rise Against Despot** — same store page: "We tried to blatantly clone games like Vampire Survivors, Halls of Torment, Brotato, Soulstone Survivors and 20 Minutes Till Dawn, but our crazy exp[eriments]…" *(Vampire Survivors is already on the sheet)* — [Steam store page](https://store.steampowered.com/app/2348610/)
- [ ] **Brotato → Slime 3K: Rise Against Despot** — same
- [ ] **Soulstone Survivors → Slime 3K: Rise Against Despot** — same
- [ ] **20 Minutes Till Dawn → Slime 3K: Rise Against Despot** — same
- [ ] **Luck be a Landlord → Maze Mice** *(Dev/Series Relation)* — "Gameplay designed by the same solo developer who brought you Luck be a Landlord." — [Steam store page](https://store.steampowered.com/app/3385370/)
- [ ] **Risk of Rain 2 → Risk of Rain Returns** *(Dev/Series Relation)* — Hopoo: "Dive into the iconic roguelike full of unique loot combinations, enhanced with new Survivors, overhauled multiplayer, fan favorite content from Risk of Rain 2, and more!" — [Steam store page](https://store.steampowered.com/app/1337520/)
- [ ] **Strange Adventures in Infinite Space → Infinite Space III: Sea of Stars** *(Dev/Series Relation)* — "Infinite Space III: Sea of Stars is a single-player science fiction roguelike set in the same universe as its predecessors, Strange Adventures in Infinite Space and Weird Worlds." *(Weird Worlds is already on the sheet. **Probably skip under the sequel rule:** Strange Adventures is already an influence on Weird Worlds, the game before it.)* — [Steam dev post](https://steamcommunity.com/games/seaofstars/announcements/detail/89304099614504744)
- [ ] **Touhou Genso Wanderer: Lotus Labyrinth R → Touhou Genso Wanderer: Foresight** *(Dev/Series Relation)* — "FORESIGHT continues the Touhou Genso Wanderer series" *(both games are degree 1 now, so this joins two leaves)* — [Steam store page](https://store.steampowered.com/app/1847150/)
- [ ] **Downwell → Exit the Gungeon** — Dave Crooks (Dodge Roll): "It started closer to a hybrid between Super Crate Box and shoot 'em ups like The Raiden Project than Enter the Gungeon. It later incorporated more and more features from Gungeon, becoming a more 'traditional' bullet hell game, and Downwell was a touchstone for us in terms of level flow and game speed." — [Game Developer](https://www.gamedeveloper.com/design/building-i-enter-the-gungeon-i-s-dungeon-climbing-spin-off-i-exit-the-gungeon-i-)
- [ ] **Hades → Moonlighter 2: The Endless Vault** — Israel Mallén (Digital Sun): "you've seen that the progression is clearly inspired by Hades in terms of choosing your path, choosing which upgrade you want. It's a huge inspiration" — [TheGamer](https://www.thegamer.com/moonlighter-2-the-endless-vault-preview-inteview-hades-inspired/). Also Luis Pérez (co-design director): "We take less of a Binding of Isaac approach and more of a Hades approach to the map." — [Game Rant](https://gamerant.com/moonlighter-2-endless-vault-interview/)
- [ ] **Returnal → Morbid Metal** — Felix Schade, on the level structure: "The way this is structured is very much inspired by games like Returnal and partly Risk of Rain 2." *(Risk of Rain 2 is already on the sheet)* — [GamingBolt interview](https://gamingbolt.com/morbid-metal-interview-shapeshifting-level-design-combat-and-more)
- [ ] **Enter the Gungeon → UnderMine**, **Hades → UnderMine** — Clint Tasker (Thorium), asked "which games inspired you the most when developing UnderMine": "We take inspiration from a lot of games, old and new. There are contemporaries that we respect a lot like The Binding of Isaac, Enter the Gungeon, and Hades. We look to the past a lot, too. Pilfers were inspired by Dragon Quest's slimes, the hub building was inspired by Soul Blazer, and 2D Zeldas loom large in everything we do." *(Isaac → UnderMine is already on the sheet. The question was about the series, so these go on UnderMine, not UnderMine 2: under the sequel rule, UnderMine 2 inherits them.)* — [Screen Hype](https://www.screenhype.co.uk/undermine-2-interview-thorium-entertainment-exclusive/)
- [ ] **Darkest Dungeon → Gordian Quest**, **Diablo → Gordian Quest** — Mixed Realms, under "Our inspirations, and vision for the game": "these days, we look to titles like Darkest Dungeon, Slay the Spire and Path of Exile. As for our vision, we want to provide the answer to these two questions: - What if action RPGs like Diablo came in a turn-based, card battle format?" *(Gordian Quest isn't degree 1; this turned up in the same sweep. Slay the Spire is already on the sheet.)* — [Steam dev post](https://steamcommunity.com/games/981430/announcements/detail/3728349046587300862)

### Weaker
- [ ] **Slay the Spire 2 → Chaos Zero Nightmare** *(one mode; backwards by the chart's years, which date Chaos Zero Nightmare 2025 and Slay the Spire 2 2026: the multiplayer came in an update)* — Choi Seung-hyun (live director): "As you said, it is true that we are preparing multiplayer by being inspired by the multi-mode of Slay the Spire 2." *(both games are degree 1)* — [Inven Global](https://www.invenglobal.com/articles/21302/chaos-zero-nightmare-at-half-year-mark-an-inflection-point-for-strengthening-core-gameplay-and-expanding-ip)
- [ ] **Inkbound → Monster Train 2** *(Dev/Series Relation; one feature)* — ModusPwnenz (Shiny Shoe design team): "The idea behind the swappable Pyre Hearts was similar to the trinkets from Inkbound" — [Steam dev post](https://steamcommunity.com/games/2742830/announcements/detail/572625355297261274)
- [ ] **Balatro → Glyphica: Typing Survival** *(one feature)* — "We envision augmentations to be like Balatro's jokers, and players' favorite augmentations can be equipped to suit their playstyle." — [Steam dev post](https://steamcommunity.com/games/2400160/announcements/detail/4686648941196507636)
- [ ] **Darkest Dungeon → Witch's Apocalyptic Journey** *(main menu only)* — "Option A: Illustrated Main Menu Inspired by the composition style of games like Darkest Dungeon" — [Steam dev post](https://steamcommunity.com/games/3709430/announcements/detail/708899744197379051)
- [ ] **Nuclear Throne → Paper Animal Adventure** *(one character)* — "Fish now uses the Pew skill instead of the default Tackle skill. This makes him feel a bit more like in Nuclear Throne:)" — [Steam dev post](https://steamcommunity.com/games/1982120/announcements/detail/4685522407036138977)
- [ ] **Diablo → Keeper's Toll** *(a comparison)* — "Our character classes are akin to those found in classic RPGs like Diablo, each boasting a distinctive play style." — [Steam dev post](https://steamcommunity.com/games/2002220/announcements/detail/6055700197101811842)
- [ ] **The Binding of Isaac → Crown Trick**, **Crypt of the NecroDancer → Crown Trick** *(comparisons, in the same devlog as the Shiren line in section 1)* — "Our game differs from the big map setting of Shiren The Wanderer. Instead, our game is similar to The Binding of Isaac: Rebirth with an underground labyrinth of rooms as the setting." and "The well-known music battle game Crypt of the NecroDancer also uses a similar combat system." — [Steam dev post](https://steamcommunity.com/games/1000010/announcements/detail/1712958942358263915)
- [ ] **Neophyte → Tiny Rogues** *(an homage item)* — Tiny Rogues patch notes, "Homages to awesome games!": "Neophyte is a mini topdown action roguelike. I played this game even before it was available on Steam and immediately fell in love with it! I asked the developer RegalPigeon about some secret Neophyte lore that I could use to get inspiration for a good reference." Same post, on Revita: "The lead developer BenStar has been an inspiration for myself ever since I caught my first glimpse of Revita." *(Revita → Tiny Rogues is already on the sheet; this is a first-hand source for it.)* — [Steam dev post](https://steamcommunity.com/games/2088570/announcements/detail/6770639657665738311)
- [ ] **Downwell → Gunlocked 2** *(a nickname the developer adopts)* — "finally add that roguelike-inspired mode to properly earn the "Reverse Downwell" comparison (sort of)." — [Steam dev post](https://steamcommunity.com/games/3492830/announcements/detail/768552869317051448)

### Checked: not an influence
- **Monster Train 2 / Balatro, Inscryption**: those are a crossover event (the Wonderous Boxes post), not influences.
- **Pyrene / Slay the Spire**: named as what the team set out *not* to make ("Pyrene is a far cry from that, which was our intention from the start").
- **Curious Expedition 2 / Spelunky**: the shout-out to Spelunky and Darius Kazemi's generator lessons is in a post about the studio's next game, Mother Machine, which isn't on the chart.
- **Slay the Spire 2 / Balatro**: Casey Yano compares endless modes ("games like Balatro do a better job"), not an influence.
- **Windblown**: "The initial inspiration was to create a game like Ragnarok Online". That's the MMO, not the chart's Ragnarok.
- **Death Road to Canada / Wayward**: "previous games I've done like Wayward Souls" is Rocketcat's own earlier game. The chart's Wayward is a different game.
- **TerraTech Legion**: its "We think you'll love TerraTech Legion if you enjoy…" list (Vampire Survivors, Brotato, Halls of Torment and a dozen more) is marketing, not influence.
- **Dice Legends / Balatro**: shares Balatro's composer, nothing more. **Kill the Brickman / Vampire Survivors**: poncle publishes it.

### Searched, nothing first-hand beyond the sheet's one edge
Inkbound (Shiny Shoe name EverQuest and Splatoon 3; Diablo and DOTA are the press's), Wild Bastards (Outlaws and spaghetti westerns), Tower Fortress (Downwell; Metroid is off the chart), Astrea: Six-Sided Oracles (Slay the Spire, plus the board game Quarriors and Magic), Moon Hunters (Secret of Mana, 80 Days, Princess Maker 2; a Diablo world-gen remark is in a GameSkinny interview that returns 403), Windblown (Hades comparisons are all the press's), Boyfriend Dungeon, Skul (a Dead Cells crossover, not an influence), Nunholy, Gatekeeper, The Rogue Prince of Persia (Dead Cells confirmed; Sands of Time is off the chart), Trash of the Titans, Dwarves: Glory, Death and Loot, Warsim (podcast interviews only), Mainframe Defenders (Cogmind, plus the original X-COM), LoneStar, Full Mojo Rampage (Isaac confirmed on the Nicalis blog), Hellboy Web of Wyrd (a GameSpot interview headlined "mix Hades gameplay" returns 403), Vampire Crawlers, Rogue Legacy 2 (its Dead Cells cue is Digital Trends's), Monster Train 2 (Mark Cooke names no game), Gambonanza (Balatro confirmed, plus The Queen's Gambit), Passant, Lunchbreak Tactics, Dead Weight, Sir We Have an Orc Problem, Rangedrifter, Touhou: Lost Branch of Legend, Tainted Grail: Conquest, Temtem: Swarm, Warhammer Survivors (built on the Vampire Survivors engine), Morimens (Slay the Spire confirmed), Synthetik 2, Talespinner, Unexplored 2 (Lord of the Rings, D&D), Neon Abyss 2 (American Gods), Spelunky 2, For the King 2 (Wizardry, Final Fantasy, Ultima, Secret of Mana), Heroes of Hammerwatch II, Cadence of Hyrule, Tears of Metal, Worlds Upon the Wind, The Magus Circle, Oddcore.

## 4f. Owned games with no connection or one, October 2026

The owned-only map is what the Owned filter plays, and it has proportionally more stranded games than the full one: 39 owned games with no connection and 200 with one. This pass took the 130 of them not already named anywhere above. All 130 had their Steam pages read by `cues`. The 25 with **no** connection were then searched by hand one by one, since nothing reaches them at all, along with about a dozen of the better-known one-connection games. Four of the 25 come out with an edge.

### Strong
- [ ] **Hades → Rabbit and Steel** *(no connections today)* — mino_dev: "There's a number of inspirations I could list; the way the roguelike items work is probably closest to something like Hades. But really the main inspiration was 'what if my last game, but roguelike and MMO raid mechanics?'" — [GameDiscoverCo](https://newsletter.gamediscover.co/p/how-rabbit-and-steel-raided-its-way). Also to GamesRadar, on the original Hades: it "had some really good design that I could learn from" — [GamesRadar](https://www.gamesradar.com/games/roguelike/a-4000-hour-final-fantasy-14-diehard-made-his-own-mmo-raid-infused-roguelike-and-its-tearing-it-up-on-steam-beating-the-4-year-sales-of-his-last-game-in-24-hours/). *(Final Fantasy XIV raids and his own Maiden and Spell are the rest; neither is on the chart.)*
- [ ] **Spelunky → Heavy Bullets** *(no connections today; 2014, so probably `Spelunky` rather than Spelunky Classic, but pick the row)* — Terri Vellmann: "A dificuldade acho que teve muita influencia de jogos que tenho jogado como Spelunky, Hotline Miami e outros, onde o jogador realmente precisa conquistar a vitória, e não recebe tudo de mão beijada." ("I think the difficulty was heavily influenced by games I've been playing like Spelunky, Hotline Miami and others, where the player really has to earn the win and isn't handed everything.") — [Rubber Chicken Games interview](https://rubberchickengames.com/2014/10/14/entrevista-a-terri-vellmann-criador-de-heavy-bullets/). Also, in English: "I like how those mechanics work, and the randomized level generation is something I'm interested in not only in playing, but also from the development point of view." — [Game Developer](https://www.gamedeveloper.com/design/-i-heavy-bullets-i-is-modern-day-indie-game-development-dressed-in-90s-neon)
- [ ] **Hoplite → Let's! Revolution!**, **Into the Breach → Let's! Revolution!** *(no connections today)* — BUCK's own postmortem: "Unlike in Hoplite or Into the Breach (which quickly became two of our big inspirations for the turn-based combat), enemies in Let's! Revolution! attack regardless of the player's position, effectively giving them infinite range." — [Game Developer](https://www.gamedeveloper.com/production/prototyping-i-let-s-revolution-i-transforming-i-minesweeper-i-into-a-turn-based-strategy-roguelike)
- [ ] **Brotato → Gnomes**, **Loop Hero → Gnomes**, **Tiny Rogues → Gnomes** *(no connections today; medium: the interviewer relaying the developer, not a direct quote)* — Chris Zukowski: "Tommy said that other than Tower Defense games his specific influences were the shop of Brotato, the adjacency perk system came straight out of Loop Hero, and Tiny Rogues also was an important influence." — [How To Market A Game](https://howtomarketagame.com/2025/08/13/gnomes-tower-defense-with-10-month-dev-time-hits-367484/)

### Weaker
- [ ] **Risk of Rain 2 → Beat Blast** *(no connections today; one UI decision)* — "Also we are removing exact stat numbers from passive descriptions, similar to how Risk of Rain 2 does it." — [Steam dev post](https://steamcommunity.com/games/1072640/announcements/detail/2900836612645372764)

### Searched, nothing first-hand
No connection: Octogeddon (George Fan names the arcade game Tapper), Slasher's Keep (Dark Messiah is a store-page comparison), Go Mecha Ball, Haste (Landfall's own Rounds, but nothing says so), Squeaky Squad, Stick It to the Stickman, Pogo Rogue, We Need To Go Deeper (Don't Starve comparisons are the press's), Demonlore (its press kit names genres only), Dungeon Deathball (Into the Breach is a reviewer's), DIG: Deep In Galaxies, Dice With Death, Fairy Tail: Dungeons, Mechanibot, Overlooting, RogueSlide, Tangy TD (a Path of Exile skill tree, off the chart), Cursorblade. *(Double Dragon Gaiden was searched in 4c.)*
One connection, confirming only the edge the sheet has: Corpse Keeper, Crop Rotation, Emberward, Repetendium, Death Skid Marks (Hotline Miami, off the chart), Tinyfolks, Golfie, Dogpile, Freaky Awesome (Mandragora's announcement post returns 403), Deep Dungeons of Doom, Astronarch (names "the auto battler craze of 2019", no game), Just King.

## 5. Same-studio leads (not sources on their own)

`python3 tools/influence_research.py samedev` lists studio pairs the sheet doesn't connect. Add one only when the newer game's own page says so, as Arcane Trigger's does above. Examples it found: Knights in Tight Spaces → 2 Fights in 2 Tight Spaces, Ziggurat → Army of Ruin, Spirits Abyss → Voids Vigil, Cell Command → Genome Guardian 2, Children of Morta → Wizard of Legend 2 (same studio, Dead Mage). From the October degree-1 pass: Fury Unleashed → Yet Another Zombie Survivors (Awesome Games Studio; their "spiritual successor to Fury Unleashed" post is about Hellreaper, which isn't on the chart), Super Bullet Break → Yohane the Parhelion (BeXide; only a bundle), Kitty Survivors → Elemental Survivors → Pairs & Perils (Little Horror Studios), Dungeon Rushers → Legend of Keepers / Sandwalkers (Goblinz), Immortal Redneck → Temtem: Swarm (Crema), FLERP → Facehand (foolsroom). None of the newer games' pages says so.

## 6. Existing rows whose source needs a look

From `python3 tools/influence_research.py xsources`, which reads the sheet's 82 X/Twitter sources:

- **Nuclear Throne → Ogre Chambers 2222** and **Scourgebringer → Ogre Chambers 2222**: the cited tweet was **deleted by its author**. The rows need a new source. — https://x.com/AntennaGames/status/2062052913199956449
- **Dead Cells → Galactic Glitch** and **Enter the Gungeon → Galactic Glitch**: posted by **JF Games, a PR agency**, not the developer (Crunchy Leaf Games). The wording ("Inspired by Dead Cells, Enter the Gungeon and the classic browser game Bubble Tanks") reads like the studio's own marketing copy, so the influence is probably right, but a developer source would be better. — https://x.com/JFGamesPR/status/1803711115047625170
- **The Binding of Isaac → Dead Estate**: posted by **2 Left Thumbs, the publisher**, not the developer (Milkbar Lads): "Dead Estate was largely inspired by Isaac!" — https://x.com/2_left_thumbs/status/1625686255093813249

The other 77 are the game's own developer or studio account.

From the group-2 hand search, rows with no first-hand source found:

- **Dead Cells → Aethermancer**: nothing from Moi Rai Games names Dead Cells; the studio's devlogs, interviews and store page compare it only to their own Monster Sanctuary.
- **Hades → Yasha: Legends of the Demon Blade**: only reviewers say 7QUARK wanted "their own version of Hades"; nothing from the studio was found in English, Korean or Japanese.
