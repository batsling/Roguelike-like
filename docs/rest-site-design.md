# Camp — the end-of-session rest (design)

**Status: proposal for the owner to edit. Nothing here is built.** Section
numbers (§3.2, §7.4, …) refer to [`games-first-redesign.md`](games-first-redesign.md).

## 1. Why

A run spans one or two days of streaming, so it is split into **sessions**:
each stream ends with a save, and the next one opens with a load. Today that
boundary isn't part of the game. Saving is a menu item, and the run picks up
exactly where it left off.

The between-game decision (which card to take, §4.2) comes about once per game,
which can be hours apart. The camp adds one decision per stream session, at a
moment the stream already has: the outro. It also gives the next stream an
opening line ("last time we camped and took…").

**Name.** It is called **Camp** and not "rest site", because a curse goal already
uses that phrase about the *real* game. Poor Sleep reads "you use a rest site
to replenish health", meaning a campfire in Slay the Spire or similar. Two
different things answering to one name would make that curse ambiguous.

## 2. When it is offered

- **A menu entry, `🔥 Make camp`**, under *This run*, beside 💾 Save run. Making
  camp resolves the choice, saves, and returns to the main menu, because it is
  how a session ends.
- **Main menu / Exit game ask once**: *"You've beaten N games since your last
  camp. Make camp before you go?"* with **Make camp**, **Just save** and
  **Cancel**. Nothing forces it: closing the stream without a choice must stay
  possible.
- **Only between games, never with one in play.** A game in play is a board
  mid-turn, and the camp should not reach into it. A Traditional game that spans
  two streams is the case this rule makes awkward (see §6).

## 3. What it offers: one card per game beaten since the last camp

The camp deals **one option per game beaten since the last camp**, each drawn
from that game's **type pool**, plus a **Rest** card that is always there. You
take **one**.

- **Beaten**, not merely played. A missed or escaped game earns nothing here,
  which fits the run's existing rule that beaten means won (§19).
- **Capped at three game cards**, the three most recently beaten, so the screen
  stays a choice rather than a list. Two games of the same type deal two
  different options from that pool.
- **The counter resets at camp** (`GameState.games_beaten_since_camp`, saved with
  the run). This stops it being farmed: with no game beaten since the last camp,
  *Make camp* is just Rest. Quitting after every game earns one card a game,
  which is no better than quitting once after three games.

Each card shows the **game's cover** and the option, so the choice reads as
"what this game taught me". A game played on stream turns into a thing you
carry.

### 3.1 The pools (first draft, built from verbs that already exist)

| Type | Options (one is dealt per beaten game) | Why this type |
|---|---|---|
| **Traditional** | **Identify**: name one unidentified scroll, pill or potion kind · **Study**: +1 Luck for the rest of the run | the genre of identification and long knowledge |
| **Deckbuilder** | **Purge**: remove one curse goal or one player status · **Draw**: +1 random card | thinning and drafting |
| **Action** | **Brace**: +2 Shields (the pool that stays, §3.2) · **Sharpen**: charge one weapon | reflexes and armour |
| **Strategy** | **Scout**: push every body on the board back one column · **Plan**: +1 Scramble | position and tempo |
| *(always)* | **Rest**: +2 Health, up to max | the floor, so a camp is never empty |

These are placeholders in the run's own vocabulary. Most map onto effect
clauses that already exist (`gain_stat` for Luck, Health, Shields and Scramble;
`gain_loot` for a card; Scroll of Identify's `identify_loot`; `remove_curse`),
so the pools can be data, not code (§5). Scout (push the whole board back) and
Sharpen (charge a chosen weapon) would be new clauses.

### 3.2 Later: a game's own camp option

A `Camp` column on the `games` sheet would let a game replace its type's draw
with its own option, for example:

- Slay the Spire: **Smith**, evolve one piece
- Hades: **Mirror**, +1 Max Health
- Darkest Dungeon: **Hamlet**, remove every player status

That is what makes beating a *particular* game worth something at camp. It
should be added only once the type pools have been played with.

## 4. On stream

- The camp screen should be **readable as a scene**: the covers of the games
  beaten this session in a row, the options under them, the choice made live.
- The overlay carries **"Last camp: Brace (from Hades)"** until the next game is
  chosen, so the next stream opens on it.
- `RunTimer` already stops when the application closes (it sums `_process`
  time), so the camp needs nothing from the clock. The session's own time could
  appear on the camp screen as a recap line.

## 5. Where it would live

- `data/camp2.0/`, from a `camp` sheet (`Type`, `Name`, `Effect`, `Weight`), so
  the pools are authored like everything else. The `games` sheet's `Camp`
  column comes later (§3.2).
- `GameState.games_beaten_since_camp: Array[StringName]`, appended in
  `Overworld2.report` beside the other beat records, cleared at camp, saved.
- `CampScreen.gd`, built in code like every other screen past the menu.
- The `Make camp` menu entry and the leave-prompt on `MenuItem.MAIN_MENU` /
  `EXIT_GAME`.
- A chapter in `HowToPlayText.gd`, which flows into `docs/rules.md`.

## 6. Open questions for the owner

1. **The Traditional game that spans two streams.** Allow a camp with a game in
   play (Rest only, or the cards earned before it)? Or ask the player to camp at
   the last game boundary?
2. **Rest's size.** Is +2 Health right, against characters with 5–10 Health?
3. **The cap of three.** Three most recent, or let the player pick which games
   to "spend"?
4. **Fractures.** Should a high Fracture weaken the camp (no Rest card, say), or
   leave it alone?
5. **Run-ending choices.** Should the last camp before the Amulet be special?
