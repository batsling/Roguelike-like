# Camp — the end-of-session rest

**Status: built** (the owner's design, 20 Oct 2026; made on the way out, the
same day). The rules are in
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

The second card names the game that dealt it ("from Hades") under what it does,
so the choice reads as what that game taught you. No cover: the two cards are
the same size and as big as the screen allows, read across a room on stream.

## 2a. The journey and the session, above the cards

The camp is also the session's recap, because it is the stream's outro:

- **The journey so far**: every stop the run has walked, repeats included
  (`GameState.walked_path`), cover to cover with the road's own arrows. Each is
  bordered green (beaten) or orange (walked away from), as on the header strip
  and the run-over screen. **This session's stops are lit and ringed thicker; the
  earlier ones are faded.**
- **The session in numbers** (`Camp.session_stats`): games played, beaten,
  goals done, enemies down, lost runs, the Health it gained or lost, and time
  played.

A **session** runs from one camp to the next, or from the run's start to its
first camp. `GameState.session_mark` (saved) records where the run's own records
stood when it began: the road's length, `GameLoop2.completed_goals`, RunTimer's
splits and clock, and Health. The stats are "now minus the mark", so nothing new
is counted. Making camp moves the mark.

**It fits 1280×720 whatever the run's length.** The road keeps to two rows:
- At first the stops are full size.
- On a longer road they shrink.
- On a longer one still, the oldest fold into a "+N earlier" chip, so this
  session's stops are always drawn.

## 3. When it can be made

- **Earned by a win.** `GameState.games_beaten_since_camp` records every game
  beaten since the last camp, one entry per win, repeats included. A camp needs
  at least one. Making camp empties the list, so a camp can't be made twice in a
  row, and quitting after every game earns no more than quitting once.
- **Game in play or not.** A session that ends mid-game (a long Traditional
  game that spans two streams) gets the whole camp, as long as a game was
  beaten since the last one. With none beaten, there is no camp, not even Rest.
- **Never a dead card.** The second card is drawn only from the beaten games
  whose card would do something right now:
  - Study needs something unidentified to study.
  - Tinker needs something with room for a charge.
  
  If none of them qualify, the camp offers Rest alone.
- **Dealt once, kept until a card is taken.** The deal is saved with the run
  (`GameState.camp_deal`), so going back to the run and leaving again shows the
  same two cards: closing and reopening can't reroll them. It is dealt again
  only if there was nothing to keep: Rest alone (a win since may have earned a
  second card), or a second card that would now do nothing.
- **Spent when the card pays.** Rest and Brace pay at once. Study and Tinker pay
  when their pick in the pack is answered. Their pick has a **Back**, and backing
  out (or a Study's Done with nothing picked) returns you to the run with the
  camp unspent. Draft is spent when its card is offered.

## 4. Where it is

- **Only on the way out of the run.** It isn't on the ☰ Menu. When a camp is
  owed, both doors out ask: the **Exit** dialog says so and adds **Make camp
  first** beside Save & exit, and **Main menu**, which otherwise leaves at once,
  opens the same question (`Overworld2.prompt_main_menu`, `_offer_camp`).
- **Taking a card saves the run and leaves for the main menu**, once its pick or
  its card offer is answered (Draft opens its own loot screen so the camp knows
  when). The camp screen's **Back to the run** cancels the exit and keeps the
  cards.
- The in-game manual teaches it in *Playing the game* → "Ending a session: make
  camp", so it is in [`rules.md`](rules.md) too.

`▲` is the menu's glyph because the UI fonts already ship it. A campfire 🔥 would
need `tools/build_glyph_font.py` re-run, which needs network access to
fontsource.

## 5. Not (yet)

- **The overlay doesn't show the last camp.** A "Last camp: Brace (from Hades)"
  line until the next game is chosen would give the next stream its opening.
  It would need a field on the run and a line in `ObsCompanion`'s payload.
- **Cards from tags.** The owner may later deal cards by a game's tags rather
  than (or as well as) its type. A card per individual game (Smith for Slay the
  Spire) was considered and turned down.
- **Bigger sessions.** Five wins deal the same one card as one win: more wins
  only widen the pool it is drawn from (a game beaten twice is twice as likely).
  The owner is thinking about whether a long session should pay more.
- **Rest at full Health does nothing.** Accepted: there is always a second card
  beside it, or the camp is Rest alone and costs nothing to take.
- **Fractures don't touch the camp.**
