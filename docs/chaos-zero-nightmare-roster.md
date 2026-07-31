# Brainstorm — Chaos Zero Nightmare goal-enemies & bosses

Candidate roster drawn from **Chaos Zero Nightmare** (2025), which is already a
node on the map (`data/games/chaos_zero_nightmare.tres`, `type = 2` →
**Deckbuilder**, tag `gacha`). Every entry below is therefore authored into the
**Deckbuilder** goal-enemy pool, and nothing here exists yet — the game currently
contributes zero enemies or bosses, so this is ~15 rows of the "content depth"
item on the roadmap (29 goal-enemies / 32 bosses against 751 games).

Nothing in this doc is wired up yet. It is written to be pasted into the
`enemies2.0` / `bosses2.0` sheets of `tools/Roguelikes.xlsx` and regenerated with
`tools/generate_goal_enemy_tres.py` / `tools/generate_boss_tres.py`.

## The design constraint these were written against

A goal-enemy's `source_game` is **flavour**; its `goal` is the thing you actually
do while playing *whichever* Deckbuilder game you picked. Snecko says "Slay the
Spire" but its goal ("randomly select your starting character") works in Balatro
or Monster Train just as well. So each row below takes a CZN *mechanic* — the
thing that makes that monster memorable — and turns it into a challenge any
deckbuilder run can satisfy on the honour system. None of them require owning or
playing CZN.

Damage follows the existing bands: normal enemies 1 / 2 / 3 by tier, bosses 3–5.

---

## Enemies (`enemies2.0`)

| Name | Type | Difficulty | Size | Game | Health | Damage | Goal Type | Goal | Ability | File | Tag |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Kurte | Deckbuilder | 1-Low | 1x1 | Chaos Zero Nightmare | 1 | 1 | Bounty | Defeat the same enemy type 5+ times | N/A | Kurte | swarm |
| Ghoul | Deckbuilder | 1-Low | 1x1 | Chaos Zero Nightmare | 1 | 1 | Bounty | Defeat an enemy that was summoned mid-fight | N/A | Ghoul | summon, undead |
| Carapace | Deckbuilder | 1-Low | 1x1 | Chaos Zero Nightmare | 1 | 1 | Bounty | Defeat an armoured or shelled enemy | N/A | Carapace | armor, bug |
| Armored Kurte | Deckbuilder | 2-Medium | 1x1 | Chaos Zero Nightmare | 1 | 2 | Feat | Break an enemy's armour in a single hit | N/A | ArmoredKurte | armor |
| Winged Carapace | Deckbuilder | 2-Medium | 1x2 | Chaos Zero Nightmare | 1 | 2 | Bounty | Defeat a flying enemy | N/A | WingedCarapace | bug, fly |
| Rock Carapace | Deckbuilder | 2-Medium | 2x2 | Chaos Zero Nightmare | 1 | 2 | Feat | Win a fight without playing a defensive card | N/A | RockCarapace | armor, stone |
| Deer Shadow | Deckbuilder | 3-High | 1x2 | Chaos Zero Nightmare | 1 | 3 | Feat | Defeat an enemy within 3 turns of it appearing | N/A | DeerShadow | shadow, timer |
| Mist Stalker | Deckbuilder | 3-High | 1x1 | Chaos Zero Nightmare | 1 | 3 | Restriction | Do not play the same card twice in one turn | N/A | MistStalker | mist |

Where each came from:

- **Kurte / Armored Kurte / Carapace / Winged Carapace / Rock Carapace** — the
  minion set Formica summons (the armoured and winged variants arrive when she
  drops low). They are the natural low-tier chaff, and `Winged Carapace` shares
  the `bug, fly` tag already used by Attack Fly, so it slots into the existing
  bug synergy for free.
- **Ghoul** — the three summons Soul Collector puts out at the start of a turn,
  which speed up every time they act. Pairs with Soul Collector below: if both
  are in the pool, "defeat a summoned enemy" reads as the same fight.
- **Deer Shadow** — a DPS check: fail to hurt it inside 3 action counts and it
  deals morale damage, escalating the longer it lives. That's a timer, so the
  goal is a timer.
- **Mist Stalker** — the one *invented* name here, standing in for City of Mist's
  regular encounters; use it only if the art exists, or drop it.

## Bosses (`bosses2.0`)

| Name | Type | Difficulty | Size | Game | Health | Damage | Goal Type | Goal | Ability | File | Tag |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Soul Collector | Deckbuilder | 1-Low | 2x2 | Chaos Zero Nightmare | 1 | 3 | Bounty | Defeat an enemy that summons reinforcements | N/A | SoulCollector | summon |
| Family Head | Deckbuilder | 2-Medium | 2x1 | Chaos Zero Nightmare | 1 | 4 | Feat | Win a fight in 3 turns or fewer | N/A | FamilyHead | fury |
| Sweet Dream | Deckbuilder | 2-Medium | 2x2 | Chaos Zero Nightmare | 1 | 4 | Restriction | Skip three card rewards in a row | N/A | SweetDream | card |
| Bercula | Deckbuilder | 3-High | 2x2 | Chaos Zero Nightmare | 1 | 4 | Bounty | Defeat an enemy that grows stronger every turn | N/A | Bercula | buff |
| Formica | Deckbuilder | 3-High | 2x2 | Chaos Zero Nightmare | 1 | 5 | Feat | Defeat 3+ summoned minions in one fight | N/A | Formica | summon, bug |
| Great Rift Colossus | Deckbuilder | 3-High | 2x3 L 90 CC | Chaos Zero Nightmare | 1 | 5 | Feat | Destroy an enemy's parts before killing it | N/A | GreatRiftColossus | stone, parts |
| Plague Lord | Deckbuilder | 4-Insane | 2x2 | Chaos Zero Nightmare | 1 | 5 | Feat | Defeat an enemy that reduces the damage it takes | N/A | PlagueLord | plague |

Where each came from:

- **Soul Collector** (Blue Pot, the first chaos area) — a reinforcement action
  that recasts itself after a one-turn delay, three ghouls a turn that accelerate
  as they act, and periodic morale pressure. The summoning is the read.
- **Family Head** — gains Fury/Hunger every single turn and turns lethal in the
  back half. The counterplay *is* speed, so the goal is a turn limit.
- **Sweet Dream** — absorbs a random Combatant's card at the start of the turn
  and only gives it back after enough hits, with the hit requirement rising as
  its HP falls. The honour-system version of "you lost a card" is refusing three
  card rewards; it also plays nicely against the deckbuilder instinct to take
  every card.
- **Bercula** (Twin Star's Shadow) — buffs herself off her own dying allies, then
  makes herself the only targetable enemy.
- **Formica** — summons Kurte and Armored Kurte, and hits harder while minions
  are alive; at low HP she brings out the Carapaces. Authoring her alongside the
  five minions above gives one game a coherent little food chain.
- **Great Rift Colossus** — two arms and a head; the head is only attackable once
  both arms are gone, and the window on it is limited. **Name it "Great Rift
  Colossus", not "Colossus"** — `data/bosses2.0/colossus.tres` is already Risk of
  Rain's. This is also the natural first non-rectangular *boss*: `2x3 L 90 CC` is
  the shape Skeletal Bastion already uses, so the generator and the footprint
  mask handle it today, and an arms-and-head silhouette that leaves a notch on
  the grid is exactly what that column is for.
- **Plague Lord** (Burning Life) — cuts incoming damage with Encroaching Fear as
  you hit it, then escalates.

---

## If the `Ability` column ever ships

The roadmap lists `Ability` as authored-but-unused (`N/A` across all 69 rows) and
asks what it should do. This roster is a good excuse, because each of these
bosses has one mechanic that maps cleanly onto the *battlefield* layer rather
than the goal text — and the goal text stays the same either way, so these are
purely additive:

- **Soul Collector — `summons`**: on spawn, also pushes 2 Ghouls into the
  off-field queue. The grid already handles an overflow queue sliding on as space
  frees, so this needs no new UI.
- **Formica — `reinforce`**: when it advances into the front column, spawn one
  Carapace behind it. Punishes letting it walk.
- **Sweet Dream — `absorb`**: locks one inventory slot (its contents unusable)
  until the goal is met. Directly mirrors the card absorption and gives the
  scroll/item layer a reason to fear a boss.
- **Great Rift Colossus — `parts`**: `health = 3`, and Bombs only remove one
  part — the "arms first" rule in one line. Note this collides with the current
  boss rule (bosses are bomb-immune; only their goal removes them), so it is a
  deliberate exception, not a freebie.
- **Family Head — `fury`**: `damage` increases by 1 each time it strikes while
  unfulfilled. The cleanest possible escalation, and it answers the open "boss
  damage band above 1–3" question by making the band dynamic.
- **Plague Lord — `encroach`**: Push costs 2 charges instead of 1 against it.
- **Deer Shadow — `timer`**: if still stacked after 3 games beaten, it strikes
  every game instead of every other. A rare enemy that punishes stalling.

## Art needed

`images2.0/enemies/` — Kurte, ArmoredKurte, Carapace, WingedCarapace,
RockCarapace, Ghoul, DeerShadow, MistStalker.
`images2.0/bosses/` — SoulCollector, FamilyHead, SweetDream, Bercula, Formica,
GreatRiftColossus, PlagueLord.

PascalCase PNGs matching the `File` column, per the art conventions in the
README; anything missing falls back to the placeholder, so rows can land before
the art does.

## Caveats

- Monster names and mechanics were taken from public CZN guides (GameWith /
  Game8). The **mechanics** are well attested; the **chaos-area attribution** is
  less so — sources disagree on whether Family Head and Sweet Dream belong to
  City of Mist or Laboratory 0. That doesn't affect any field in the sheet
  (there's no "area" column) but it's worth knowing before writing flavour text.
- Some areas — Swamp of Judgement, The Foretold Ruin, Nebula Distortion — have
  bosses I couldn't get confirmed names for. If you want a second pass, those are
  where the remaining rows are.
- Six of the eight enemies here are Low/Medium tier, which is where the
  Deckbuilder pool is thinnest today; the two High-tier entries plus the
  Insane-tier Plague Lord are the ones that widen the late-run pool.

Sources: [City of Mist](https://gamewith.net/chaoszeronightmare/71129),
[Twin Star's Shadow](https://gamewith.net/chaoszeronightmare/71081),
[Blue Pot](https://gamewith.net/chaoszeronightmare/70804),
[Laboratory 0](https://gamewith.net/chaoszeronightmare/71537),
[Burning Life](https://gamewith.net/chaoszeronightmare/72851),
[Colossus](https://gamewith.net/chaoszeronightmare/71872).
