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

Once done, an achievement stays done on that profile.

## Where it lives

| What | Where |
|---|---|
| One achievement | `data/achievements/<id>.tres`, an `AchievementData` (`scripts/resources/AchievementData.gd`). Written by hand: there is no sheet for them yet |
| The rules | `scripts/runtime/Achievements.gd` — `measure`, `progress`, `is_done`, `character_locked`, `check` |
| What a profile has done | `GameStats.achievements` (`id -> {best, done, held}`), saved in `game_stats.json` |
| The screen | `scripts/ui/AchievementsScreen.gd`, opened by the main menu's ★ Achievements button |
| The lock | `scripts/menu/CharacterPicker.gd`: a locked hero is a silhouette, can be looked at (the panel says what unlocks them and how close the profile is), cannot be confirmed, and is never rolled by the dice |
| Tests | `test/test_achievements.gd` |

`Achievements.check()` runs whenever what the run holds changes
(`GameState.inventory_changed`) and whenever the stats do (`GameStats.changed`).
It only looks at achievements still open. Finishing one raises a toast.

## Adding one

1. Write `data/achievements/<id>.tres` with a `tab`, an `order`, the character
   it unlocks, a one-sentence `description`, a `scope`, a `metric` and a `goal`.
2. If it is counted a new way, add the metric to `AchievementData`'s enum and to
   `Achievements.measure`.
3. A new `tab` name is a new tab on the screen by itself.

## Things to know

- **"Unlock everything"** (Settings → Profile) reads every achievement as done
  without recording anything, like the rest of the test profile.
- **The suite runs with `Achievements.bypass` on** (`test/pre_run_hook.gd`):
  nobody is locked and nothing is counted, so a test in another file that hands
  out three pennies raises no toast. `test_achievements.gd` turns it off.
- A run already in progress as a locked character can still be continued; the
  lock is on starting a new one.
