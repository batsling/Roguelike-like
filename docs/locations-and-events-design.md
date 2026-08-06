# Locations & Events — design brainstorm

Status: **brainstorm / proposal.** Companion to `games-first-redesign.md`; nothing
here is built yet. Written to answer two questions: *do locations and events
overlap, and which should be built first?*

---

## 1. The frame: everything is a goal issuer

The redesign has exactly **one verb of interaction with the real world**: a line
on the post-game checklist that the player ticks honestly. Enemies, bosses, the
character level-up — all of them are the same object wearing different hats. A
thing is only a distinct *system* if it claims a distinct cell on this grid:

| Issuer | Scope (how long it's live) | If met | If missed | Who chose it |
|---|---|---|---|---|
| **Level-up** (character) | every game, forever | stat + reward | nothing | nobody — it's always on |
| **Goal-enemy** | the game it spawned on | item drop | it follows and hits for 1–3 | the router (comes with the card) |
| **Boss** | the game it spawned on | better item | heavier hits, bomb-immune | the tier ladder |
| **Location** | **the whole stay (~3 games)** | **goal effect** | **nothing — it expires** | **the player, at the floor pick** |
| **Event** | **usually the next game** | **the payoff you gambled for** | **the price you agreed to** | **the player, at the modal** |

Locations and events feel like they overlap because both cells were empty. Fill
them in and the collision goes away:

- **Location = the carrot.** Wide scope, no downside for failing, chosen once
  and lived in. It is the only thing on the grid that *rewards without
  threatening* — the run currently has no such axis. Every objective in the game
  today is a debt you must defuse.
- **Event = the wager.** Narrow scope, both stakes live, and you *opted in*. The
  only thing on the grid where missing costs you something you agreed to.

The real collision is elsewhere and it's worth naming: **events overlap with
`encounters`, not with locations.** See §6.

---

## 2. Recommendation: build locations first

1. **It fills the missing structural beat.** The run is currently flat — pick a
   card, play, report, repeat, with a boss every third game. There is no sense of
   place or descent. Locations are the floor you're standing on.
2. **It rides machinery that already exists.** The tier ladder already ticks
   every `GAMES_PER_TIER` games and already fires a boss round
   (`Overworld2._is_boss_round`). Locations need no new clock.
3. **It makes routing a real decision on a second axis.** Right now routing is
   distance-to-amulet plus game type. A floor pick adds terrain.
4. **Events are further from ready than they look.** The `EventModal` in the repo
   is combat-era: it rolls a d20 against `charisma` / `dexterity` /
   `intelligence`, stats the redesign deleted. And `EncounterData` already
   models the same moment with a parsed effect DSL and no runtime. "Build
   events" really means "build the encounter runtime" — a separate, lower-value
   job that should be done once, not twice (§6).

---

## 3. Locations = the floor, picked at the tier tick

> The `locations` sheet currently in `Roguelikes.xlsx` is **legacy content from
> the previous design** — its `Effect` column is per-*game* rather than
> per-location (every Isaac row shares one effect) and describes a combat model
> that no longer exists. The *shape* of that sheet is still worth keeping, and
> it's the reason this proposal works: see below.

**The key observation.** The old sheet, without meaning to, is already an
Isaac-style alternate-floor ladder:

| Game | Low | Medium | Hard |
|---|---|---|---|
| The Binding of Isaac | Basement / Burning Basement / Dross | Caves / Flooded Caves / Necropolis | Womb / Cathedral / The Void |
| Enter the Gungeon | Keep of the Lead Lord | Black Powder Mine / Hollow | Forge / Bullet Hell |
| Risk of Rain 2 | Titanic Plains / Aqueduct / Siphoned Forest / Wetland | Rallypoint / Abyssal / Sundered / Sulfur | Sky Meadow / Commencement |

Three tiers, several **alternates per tier**, grouped by source game. That is
exactly the shape of the run's tier ladder (Low → Medium → High → Insane, one
step every 3 games). So:

**When the tier ticks — the same moment the boss round fires — offer 2–3
locations of the new tier and let the player pick one.** That location is the
run's floor for the next ~3 games.

What a location does while you stand in it:

- **Biome tag** — softly biases which goal-enemies roll onto the offered cards
  (Burning Basement leans `fire`/`lava`, Necropolis leans `undead`). See §5 for
  why this must be *soft*.
- **Extra Effect** — applies on entry, and is the **price** of the spicier
  alternates. "Spawn 1 random enemy with the fire tag" is a cost, and that's
  correct: plain Basement is the safe pick, Burning Basement pays better and
  bites.
- **Location goal** — a standing bonus objective, live for the whole stay,
  tickable in **any** game played there, paying its Goal Effect on completion.
  Missing it costs nothing; it just expires when you descend.

The floor pick becomes a genuine bargain — *how much extra threat will I take on
for a reward I might not even be able to earn?* — and it lands on a beat the run
already has (the boss round), so it costs one new screen, not a new loop.

---

## 4. The authoring rule: location goals are tallies

This is the thing that keeps a location from being a second enemy.

Look at Burning Basement as drafted:

```
Name: Burning Basement | Goal Type: Feat | Goal: Set 10+ enemies on fire
Goal Effect: Gain +1 Small Chest | Enemy: fire
```

Structurally that is **identical to a goal-enemy** — same `Goal Type` vocabulary
(`Feat` is one of the five already in `enemies2.0`), same tier gate, same
reward-on-completion, same tag. Drop it in as-is and the player sees two
checkboxes in one checklist with no way to tell why one is a "location" and one
is an "enemy."

Two changes fix it, and both fall out of scope:

**(a) A location goal spans several games — and several *different real
roguelikes*.** You might play Isaac, then Hades, then NetHack while standing in
the Burning Basement. So a location goal can never be as specific as an enemy
goal. It has to be **biome-flavoured but mechanically generic**, and it has to
**accumulate**:

> **Enemy goals are one-shots. Location goals are tallies.**
> *"Defeat an enemy that splits"* (one act, one game) vs.
> *"Set 10+ enemies on fire"* (a counter, any game here).

The `10+` in the draft is already right — that instinct is the whole rule. Make
it the authoring law and the two never read alike.

**(b) A location goal has no failure state.** It pays or it expires. That is
what makes it the carrot and keeps the checklist legible: threats are the ones
that follow you, bonuses are the ones that don't.

The `Limit` column then earns its keep as the payout cap — `None` for a one-shot
tally, or `3` for a repeatable one ("+1 Small Chest each time, up to 3").

---

## 5. Goals that fit the biomes

Cross-game, accumulative, honour-system checkable. Two grammars work:

- **Tally** — "N+ times across the stay" (the default).
- **Streak** — "in every game this stay" (rarer, spikier, good for hard tiers).

| Biome | Tally goals | Streak / restriction goals |
|---|---|---|
| **Fiery** | Set 10+ enemies on fire · Destroy 5+ things with an explosion | Take burn/fire damage in every game here |
| **Icy** | Freeze or slow 10+ enemies | Immobilise something in every game here |
| **Undead** | Defeat 15+ undead · Have 3+ enemies revive or resurrect | Die and come back |
| **Watery** | Obtain 3+ fish or liquids | Be submerged / drown once per game |
| **Underground** | Break or dig through 10+ pieces of terrain | Reach the deepest floor you can in each game |
| **Sewage** | Defeat 10+ vermin · Pick up 3+ things you'd rather not | Be poisoned or filthy in every game |
| **Holy** | Receive 3+ blessings, boons, or prayers | Refuse every deal, pact, or devil offer this stay |
| **Chaos** | Take the random/unknown option 5+ times · Reroll 3+ times | Never take the first option offered |
| **Poisonous** | Poison 10+ enemies | Survive a game at 1 HP |
| **Sky** | Fall from a great height 3+ times | Leave the ground in every game |
| **Lunar** | Acquire 2+ cursed or double-edged items | Keep a cursed item for the whole stay |
| **Living** | Consume 5+ organic things | Enter something's body |
| **Desert** | Go 2 games without picking up a healing item | Beat a game with no consumables spent |
| **Swampy** | Get stuck, slowed, or trapped 5+ times | — |
| **Building** | Open 10+ doors or locked containers | Break into somewhere you weren't meant to go |
| **General** | Collect 6+ items | Beat every game this stay first try |

The two that carry the most weight are **Holy** ("refuse every deal") and
**General** ("beat every game first try") — both are *restrictions on the meta
layer itself* rather than on the real game, which is a flavour the enemy pool
can't produce. Worth leaning into: locations are the only issuer positioned to
put rules on the app's own systems (shields, chests, deals, routing).

---

## 6. Where events actually go

**Events collide with `encounters`, not with locations.** Both are one-shot,
between-games, modal-with-choices. The evidence:

- `Deal with the Devil` exists in **both** sheets.
- The newer rows on the `events` sheet (Primordial Teleporter, A Wild Muncher,
  The Colosseum) are shaped exactly like encounters — prose prompt, 2–4 choices,
  structured effects.
- `EncounterData` is the further-along of the two: it has a real effect DSL
  (`offer_items`, `teleport`, `shop`, `challenge`, `win`/`lose`), a generator,
  and a requirement/gating model. Its header says outright that the *node + modal
  that consume `effects`* are still to come.
- `EventModal.gd` is the further-behind one: 27k of combat-era d20 stat checks
  against `charisma` / `dexterity` / `intelligence` — stats the redesign removed.

So: **build one modal, not two.** Keep `EncounterData` as the schema, port the
good event rows into it, and let "event" and "encounter" be two *flavours* in one
pool (the `Type` column already buckets Deal / Shop / Movement / Challenge — add
`Event`).

### What replaces the d20

The Slay-the-Spire feel the design wants — *the player decides to do something to
fulfil part of the event* — survives the redesign fine; it just changes currency.
There's no stat to roll against, but there are four things the player can be
asked to spend:

1. **A verb or consumable** — a bomb, a scramble, a transmute, a key.
2. **A shield** — one of your tries at the next game. Sharpest cost in the game.
3. **Health** — the blunt one (Deal with the Devil already does this).
4. **A goal** — *take on this restriction for the next game.*

The fourth is the interesting one, and it's what makes events native rather than
imported: **an event choice can hand you a goal instead of resolving instantly.**

> **The Colosseum.** *Challenge the Champion* → your next game gains an extra
> goal: beat it without spending more than one try. Meet it, take 2 items. Miss
> it, lose 3 health.

Now the gamble isn't a dice roll, it's *whether you can actually pull it off in
the real game* — which is the whole premise of the app-as-DM. And events, enemies
and locations all speak one language.

### And *where* they fire

Two slots, either of which works, and they don't compete with locations:

- **On the floor pick** — a location can carry an arrival event, so the event is
  the *narration* of entering a place rather than a separate node type. This is
  the tidiest option and it makes locations and events allies.
- **On the offering** — one card in the offering is an event instead of a game.
  Costs no floor structure, but competes with a game pick, which is a real price
  in a run measured in games.

Start with arrival events on locations. It reuses the floor-pick screen you're
already building and gives every location a voice.

---

## 7. Proposed schema

```
Name | Game | Difficulty | Biome | Goal Type | Goal | Goal Effect | Limit | Extra Effect | Enemy Tag | File
```

Changes from the drafted columns:

- **Keep `Biome`** (the old sheet's `Type`: Fiery / Icy / Undead / Watery / …).
  It's the display identity and the axis that makes two same-tier alternates feel
  different. `Enemy Tag` is the *mechanical* half of the same idea and should stay
  a separate column, because the two won't always line up (§8).
- **`Goal Type`** — reuse the enemy vocabulary (Bounty / Fetch / Feat /
  Restriction / Discovery), so the checklist can render both from one code path.
- **`Limit`** — payout cap: `None` = pays once, `N` = repeatable up to N.
- **`Extra Effect`** — the price of entry, applied on arrival.

---

## 8. One real gap to plan around: the tag pools are thin

The `Enemy Tag` bias sounds cheap but the data won't support a hard filter yet.

- `fire` **is not a tag in `enemies2.0`.** The full tag vocabulary today is:
  `bug, fly, alien, undead, skeleton, spider, slime, ice, lava, mushroom, beetle,
  cat, fish, goblin, rodent, rat, gun, god`. Burning Basement would have to bias
  toward `lava`, which is one enemy (Lava Slime).
- The roll is **already** filtered by game type + tier. Some buckets are a single
  enemy: `Traditional / Low` is Leprechaun, `Traditional / High` is Jabberwock.
  Add a tag filter on top and those buckets go empty.

**So the bias must be soft**: prefer a tagged enemy, fall back to the normal
type+tier roll when the pool comes up empty. `GameLoop2._pick_by_type_tier`
already widens exactly this way (type+tier → type → tier → anything) — add tag as
one more preferred bucket at the front and the existing fallback chain handles
the rest. Nothing breaks while content is thin, and locations get sharper on
their own as the tag vocabulary grows.

---

## 9. Suggested build order

1. **`LocationData` + generator + the sheet redo** — pure data, no runtime risk,
   mirrors `generate_goal_enemy_tres.py` closely.
2. **The floor-pick screen at the tier tick** — 2–3 alternates, biome, goal,
   goal effect, extra effect. Hangs off `_is_boss_round()`.
3. **Location goal on the checklist** — one more row in `_verify_box`, ticking a
   tally that persists across games instead of resolving on one.
4. **Soft tag bias in the enemy roll** — one bucket in `_pick_by_type_tier`.
5. **Extra Effect verbs** — start with just `spawn enemy with tag`; the rest as
   locations need them.
6. *Then* the encounter/event modal, once the floor gives events somewhere to
   live.
