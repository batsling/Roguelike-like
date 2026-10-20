# Camp — the end-of-session rest

**Status: built** (the owner's design, 20 Oct 2026). The rules are in
`scripts/runtime/Camp.gd`, the screen is `scripts/redesign2/CampScreen.gd`, and
the flow is `Overworld2.open_camp` / `camp_choose`. Tests: `test/test_camp.gd`.
Section numbers (§3.2, …) refer to
[`games-first-redesign.md`](games-first-redesign.md).

## 1. Why

A run lasts a day or two of streaming, so it is played in **sessions**: each
stream ends with a save, and the next opens with a load. Before the camp, that
boundary wasn't part of the game. The between-game decision (which card to take,
§4.2) comes about once per game, and a game can take hours. The camp adds one
decision per stream session, at a moment the stream already has: the outro. Its
result is also the next stream's opening line.

**Name.** It is called **Camp** and not "rest site", because a curse goal already
uses that phrase about the *real* game: Poor Sleep, "you use a rest site to
replenish health", means a campfire in Slay the Spire or similar. Two things
answering to one name would make that curse ambiguous.

## 2. The rule

Making camp offers **two cards, and you take one**:

| Card | When | What it does |
|---|---|---|
| **Rest** | always | +2 Health, up to max (`Camp.REST_HEAL`) |
| **one more** | dealt from a random game beaten since the last camp, by that game's type | see below |

| Type of the game it came from | Card | What it does |
|---|---|---|
| Traditional | **Study** | identify one piece of loot you carry, chosen in the pack |
| Deckbuilder | **Draft** | a random card, through the ordinary loot offer, so a full pack is asked rather than refused |
| Strategy | **Tinker** | 2 charges (`Camp.CHARGE_AMOUNT`) into one thing you carry that takes a charge, chosen in the pack |
| Action | **Brace** | +1 Shield, the kind that stays until something breaks it (§3.2) |

The second card shows the cover of the game that dealt it ("from Hades"), so the
choice reads as what that game taught you.

## 3. When it can be made

- **Earned by a win.** `GameState.games_beaten_since_camp` records every game
  beaten since the last camp, one entry per win, repeats included. A camp needs
  at least one. Making camp empties the list, so a camp can't be made twice in a
  row, and quitting after every game earns no more than quitting once.
- **Only between games.** A game in play has a board that is mid-turn, so the
  menu entry is dark while one is.
- **Never a dead card.** The second card is drawn only from the beaten games
  whose card would do something right now:
  - Study needs something unidentified to study.
  - Tinker needs something with room for a charge.
  
  If none of them qualify, the camp offers Rest alone.
- **Spent the moment a card is taken**, before any pick it opens. Putting that
  pick away therefore can't leave the camp open to be made again.

## 4. Where it is

- **☰ Menu → ▲ Make camp**, under *This run*, beside Save run. While it is shut,
  its tooltip says why: a game is in play, nothing has been beaten since the
  last camp, or the run is over.
- **Exit asks.** When a camp is owed, the Exit dialog says so and adds **Make
  camp first** beside Save & exit.
- **Making camp saves the run** and says it is safe to close. It doesn't quit
  for you: a card that opens a pick or a loot offer needs the page.
- The in-game manual teaches it in *Playing the game* → "Ending a session: make
  camp", so it is in [`rules.md`](rules.md) too.

`▲` is the menu's glyph because the UI fonts already ship it. A campfire 🔥 would
need `tools/build_glyph_font.py` re-run, which needs network access to
fontsource.

## 5. Not (yet)

- **The overlay doesn't show the last camp.** A "Last camp: Brace (from Hades)"
  line until the next game is chosen would give the next stream its opening.
  It would need a field on the run and a line in `ObsCompanion`'s payload.
- **A game's own camp card.** A `Camp` column on the `games` sheet could let one
  game replace its type's card: Smith for Slay the Spire, the Mirror for Hades.
  Worth adding once the type cards have been played with.
- **A Traditional game that spans two streams.** The camp is shut while a game is
  in play, so a session that ends mid-game ends without one. The game's win
  earns the camp at the end of the next session. The open question is whether a
  mid-game session end should get Rest alone.
- **Fractures don't touch the camp.**
