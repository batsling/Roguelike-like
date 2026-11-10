# Achievements

Things the player does that unlock something. For now what they unlock is
**characters**; the screen has a tab per kind of unlock, so a second kind is a
new tab rather than a new screen. The owner asked for it on 10 Nov 2026 and
chose the layout (rows, with a meter that fits how each one is counted).

## What there is

| Achievement | Unlocks | Counted | Condition |
|---|---|---|---|
| `manager` | Manager (Raccoin: Coin Pusher Roguelike) | in one run | Hold 3 different coin-tagged items or loot at the same time |
| `zoe` | Zoe (Haste) | across all runs | Perfect 10 games |
| `rodney` | Rodney | across all runs | Beat a traditional roguelike |

A character named by an achievement is **locked** until it is done. Every other
character is playable from the start.

## The two ways of counting

- **In one run** (`scope = "run"`): it has to happen inside a single run. The
  best run is remembered, with what it was holding, so the screen says "Best in
  one run: 2 of 3" and shows those pieces in its sockets. A worse run never
  lowers it.
- **Across all runs** (`scope = "lifetime"`): it adds up over every run and is
  read off the stats the game already keeps. A profile that had perfected ten
  games before this existed has Zoe from its first boot, with no toast.

What is counted is the `metric`:

- `tagged_held` — how many **different** relics and pieces of loot carrying
  `tag` the run holds at once: relics on the shelf, loot in the pack, and a
  passive piece the Smelter took out of it. Two copies of one trinket are one.
- `perfects` — every perfected game, summed over all games (ten perfects of one
  game count as ten).
- `games_beaten` — how many **different** games have been beaten; with a
  `game_type` (`traditional`), only games of that type.

Once done, an achievement stays done on that profile.

## Where it lives

| What | Where |
|---|---|
| One achievement | a row of the `achievements` sheet of `tools/Roguelikes.xlsx`, written out by `tools/generate_achievement_tres.py` as `data/achievements/<id>.tres`, an `AchievementData` (`scripts/resources/AchievementData.gd`). Edit the sheet, not the files |
| The rules | `scripts/runtime/Achievements.gd` — `measure`, `progress`, `is_done`, `character_locked`, `check` |
| What a profile has done | `GameStats.achievements` (`id -> {best, done, held}`), saved in `game_stats.json` |
| The screen | `scripts/ui/AchievementsScreen.gd`, opened by the main menu's ★ Achievements button |
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
| Unlocks | the character, by name or id as in the `characters` sheet. One row per character at most |
| Description | the sentence the player reads |
| Counted | `one run` or `all runs` |
| Condition | `hold <tag>` (one run), `perfect games` (all runs), or `beat games [<type>]` (all runs; type is `action`, `strategy`, `deckbuilder` or `traditional`) |
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

## Things to know

- **"Unlock everything"** (Settings → Profile) reads every achievement as done
  without recording anything, like the rest of the test profile.
- **The suite runs with `Achievements.bypass` on** (`test/pre_run_hook.gd`):
  nobody is locked and nothing is counted, so a test in another file that hands
  out three pennies raises no toast. `test_achievements.gd` turns it off.
- A run already in progress as a locked character can still be continued; the
  lock is on starting a new one.
