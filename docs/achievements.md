# Achievements

Things the player does that unlock something: **characters**, since 13 Nov
2026 **players** (`docs/players-design.md`), and since 14 Nov a special **hat**
(`docs/customization.md` §7). The screen has a tab per kind of
unlock, so the second kind was a new tab rather than a new screen. The owner asked for it on 10 Nov 2026 and
chose the layout (rows, with a meter that fits how each one is counted).

## What there is

| Achievement | Unlocks | Counted | Condition |
|---|---|---|---|
| `manager` | Manager (Raccoin: Coin Pusher Roguelike) | in one run | Hold 3 different coin-tagged items or loot at the same time |
| `zoe` | Zoe (Haste) | across all runs | Perfect 10 different games |
| `rodney` | Rodney | across all runs | Beat a traditional roguelike |
| `player_retro_bat` | the player Retro Bat (Players tab) | across all runs | Beat 20 different traditional roguelikes |
| `hat_abandon_hat` | the Abandon Hat (Hats tab) | in one run | Escape 5 games in a row |

A character or player named by an achievement is **locked** until it is done.
Every other one is playable from the start. A row under the `Players` tab names a
player in its `Unlocks` cell and writes `unlocks_player`; under `Characters` it
writes `unlocks_character`. Its id is the player's prefixed `player_`, so a
player and a character can share a name. A row under the `Hats` tab names a
SPECIAL hat (one in `images2.0/hats/Special/`, which no rank draws) and writes
`unlocks_cosmetic`, its catalog key; its id is prefixed `hat_`. Finishing it
unlocks the hat (`Cosmetics.unlock_special`), whose own toast is the
announcement, and a hat already owned reads as done.

## The two ways of counting

- **In one run** (`scope = "run"`): it has to happen inside a single run. The
  best run is remembered, with what it was holding, so the screen says "Best in
  one run: 2 of 3" and shows those pieces in its sockets. A worse run never
  lowers it.
- **Across all runs** (`scope = "lifetime"`): it adds up over every run and is
  read off the stats the game already keeps. A profile that had perfected ten
  different games before this existed has Zoe from its first boot, with no toast.

What is counted is the `metric`:

- `tagged_held` — how many **different** relics and pieces of loot carrying
  `tag` the run holds at once: relics on the shelf, loot in the pack, and a
  passive piece the Smelter took out of it. Two copies of one trinket are one.
- `perfects` — how many **different** games have been perfected (one game
  perfected ten times is one).
- `games_beaten` — how many **different** games have been beaten; with a
  `game_type` (`traditional`), only games of that type.
- `escape_streak` — how many games in a row the run has escaped
  (`GameState.escape_streak`), counted in one run; the best streak is kept.
  `Cosmetics.note_escape_streak` asks for the count after every game handed
  in, since neither the pack nor the stats move on an escape.

Once done, an achievement stays done on that profile.

## Where it lives

| What | Where |
|---|---|
| One achievement | a row of the `achievements` sheet of `tools/Roguelikes.xlsx`, written out by `tools/generate_achievement_tres.py` as `data/achievements/<id>.tres`, an `AchievementData` (`scripts/resources/AchievementData.gd`). Edit the sheet, not the files |
| The rules | `scripts/runtime/Achievements.gd` — `measure`, `progress`, `is_done`, `character_locked`, `check` |
| What a profile has done | `GameStats.achievements` (`id -> {best, done, held}`), saved in `game_stats.json` |
| The Stats tab's numbers | `scripts/runtime/CompletionStats.gd` |
| The screen | `scripts/ui/AchievementsScreen.gd`, opened by ★ Achievements in the main menu's Extras list |
| The lock | `scripts/menu/CharacterPicker.gd`: a locked hero is a silhouette, can be looked at (the panel says what unlocks them and how close the profile is), cannot be confirmed, and is never rolled by the dice |
| Tests | `test/test_achievements.gd` |

`Achievements.check()` runs whenever what the run holds changes
(`GameState.inventory_changed`) and whenever the stats do (`GameStats.changed`).
It only looks at achievements still open. Finishing one raises a toast.

## The sheet

`achievements`: `Tab | Unlocks | Description | Counted | Condition | Goal`, one
row per achievement, listed on the screen in sheet order.

| Column | What goes in it |
|---|---|
| Tab | the tab it is filed under (`Characters`). A new name is a new tab |
| Unlocks | the character, by name or id as in the `characters` sheet (a player under `Players`, a special hat by name under `Hats`). One row per character, player or hat at most |
| Description | the sentence the player reads |
| Counted | `one run` or `all runs` |
| Condition | `hold <tag>` (one run), `perfect games` (all runs), `beat games [<type>]` (all runs; type is `action`, `strategy`, `deckbuilder` or `traditional`), or `escape games in a row` (one run) |
| Goal | how many it takes |

## Adding one

1. Add a row to the `achievements` sheet.
2. `python3 tools/generate_achievement_tres.py`. It refuses, by name, a
   character that does not exist, a Condition it cannot read, and a Condition
   counted the wrong way (`hold` across all runs).
3. If it is counted a new way, add the clause to the generator's
   `parse_condition`, the metric to `AchievementData`'s enum and the count to
   `Achievements.measure`, in the same commit.

The folder is rewritten, not added to: a row deleted from the sheet takes its
achievement with it. `check_data_sync.py` (CI) holds the folder to the sheet.

## The Stats tab

The last tab of the Achievements screen is a completion page (the owner, 10 Nov
2026): everything the profile has done, in sections, each line out of how many
there are. `scripts/runtime/CompletionStats.gd` has the numbers; nothing is
stored for it, every count is read when the page opens.

| Section | Lines |
|---|---|
| Achievements | unlocked, per tab |
| Games | different games beaten, perfected, won as the Amulet, beaten on Fracture 10, Amulets won on Fracture 10, each out of every game in the catalog; totals ("73 wins in all") beside them |
| Enemies | different enemies beaten, different bosses beaten, and every defeat in all |
| Characters | characters with an Amulet win, characters who cleared Fracture 10, and a line per character (games, Amulets, perfects, best Fracture) |
| Collection Discovered | what has been seen of each kind the Collection veils |
| Unlocks Earned | Radio songs, title letters, costumes and icons |
| Run Records | runs played and won, different goals completed, level-ups, the Donation Machine's best. No totals, so not part of the meter |

**The meter.** A section's meter is the average of its lines that have a total,
so each line counts the same whatever it is out of. The overall meter is the
average of the sections', so Achievements weigh as much as the thousand games.
A percentage is rounded down: 100% is only shown for everything.

Two things `GameStats` keeps for this page:

- `fracture_best` on a game's row, the highest Fracture it has been beaten at
  (`game_fracture_best`). It is only recorded from now on; for older wins it is
  the most the record can prove (the Amulet's best, or the first win's level),
  so "beaten on Fracture 10" can read low on an old profile.
- `runs_played` and `runs_won`, because the run history is capped at 40. An
  older profile starts them at what its history holds.

"Unlock everything" completes nothing here: the page counts what is on record.

## Things to know

- **"Unlock everything"** (Settings → Profile) reads every achievement as done
  without recording anything, like the rest of the test profile.
- **The suite runs with `Achievements.bypass` on** (`test/pre_run_hook.gd`):
  nobody is locked and nothing is counted, so a test in another file that hands
  out three pennies raises no toast. `test_achievements.gd` turns it off.
- A run already in progress as a locked character can still be continued; the
  lock is on starting a new one.
