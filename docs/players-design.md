# Players — design

**Status: built (13 Nov 2026).** Asked for and decided by the owner the same day.
Rules: `scripts/resources/PlayerData.gd` (the resource and each mechanic's words),
`scripts/runtime/HungerSystem.gd`, `scripts/runtime/WeaponSystem.gd` (the
unidentified roll). Screen: `scripts/menu/PlayerPicker.gd`. Sheet: `players` →
`tools/generate_player_tres.py` → `data/players/`. Tests: `test/test_players.gd`,
and the ladder's in `test/test_fracture.gd`.

## 1. What a player is

A run starts with **two picks**, in this order:

1. **The player**, and its **Fracture** (`PlayerPicker`). The player carries the
   run's extra **mechanics** and holds the Fracture ladder.
2. **The character** (`CharacterPicker`), as before. Any player can play any
   character, and characters keep their own locks (`docs/achievements.md`).

The player is `GameState.player_id`, saved with the run (a save from before
players is the basic player). Every rule that belongs to a player asks
`GameState.has_mechanic(&"...")`, never the player's id, so a second player with
Hunger needs a sheet row and no code.

Every player is an **original work**, not a character from a real game.

| Player | Mechanics | Unlock | Art |
|---|---|---|---|
| Basic | none — the game as it is | always | none: the picker draws the word "Basic" |
| Retro Bat | Hunger, Unidentified Weapons | beat 20 different traditional roguelikes | `images2.0/players/RetroBat.png` |
| Batsaac | none yet — the owner's to give | always (for now) | `images2.0/players/Batsaac.png` |

Retro Bat was called Batty for its first day (the owner renamed it, 13 Nov 2026);
its id is `retro_bat`, its achievement `player_retro_bat`.

**The art, at its best.** Retro Bat's is pixel art stored at its true size: the
owner's upload was the sprite drawn at 10× with exactly three colours, so it is
kept 1:1, and its empty border is trimmed (10×15) so it fills a frame rather than
sitting small in the middle of one. Batsaac's is PAINTED art — the crying bat
that sat in the custom images folder as IsaacBat, moved here — kept at full resolution
with only its transparent margin trimmed. Every screen draws both through
`UITheme.crisp_tex`, which scales pixel art without smoothing and painted art
with it.

### The sheet

`players`: `Name | Description | Mechanics | File`. `Mechanics` is a comma list of
`Hunger`, `Unidentified Weapons` (the generator's `MECHANICS`, mirroring
`PlayerData.MECHANICS`); blank is the basic player. `File` is the art's base name
in `images2.0/players/`. The art is named by PATH and loaded on first read, the
boot-load rule. What a mechanic SAYS is not on the sheet: the rules are code, so
`PlayerData.mechanic_line` keeps their words beside them.

What **unlocks** a player is a row of the `achievements` sheet under the
**Players** tab (`AchievementData.unlocks_player`), counted exactly like a
character's. Retro Bat's: `all runs`, `beat games traditional`, goal 20.

## 2. Fractures belong to the player

The ladder (`docs/fracture-design.md`) was per character until this change. Now:

- **Unlocking, the pick and the per-level win counts are the player's**:
  `GameStats.player_fracture_log`, read through `player_fracture_best`,
  `player_fracture_unlocked`, `player_fracture_pick`, `set_player_fracture_pick`
  and `player_fracture_wins`. `GameLoop2.start_run` takes the run's level from the
  player's pick. The run-over screen names the player ("Fracture 4 unlocked for
  Retro Bat"), and the Stats page counts **players** who cleared Fracture 10.
- **The basic player inherits the old ladder** (the owner's call). Until it has a
  record of its own, its best is the highest any character reached
  (`_legacy_ladder_best`, a won run from before Fractures counting as 0), its
  pick the highest any character had, and its per-level wins the characters'
  summed. Its first win writes its own record, never below what it inherited.
  Retro Bat starts at 0.
- **What stays on the character** is a record, not a lock: the highest Fracture a
  run was won at as them (`fracture_log[c].best`, their 🏆's number) and the
  levels their game wins were at (`fracture_sum`, their XP, `GameRanks`).
- **Unlock everything** (Settings → Profile) opens every player and every level of
  every player's ladder, and records nothing.

The Fracture row moved off the character select onto the player select, with its
numbers still spelled in unlocked title digits (`PlayerPicker.number_fracture_button`).

## 3. Characters give no stats

A character now gives exactly four things: its **level-up challenge**, its
**Health**, its **gold** and its **starting loot**. The owner, 13 Nov 2026:
stats come neither from the start nor from a level-up.

- The `characters` sheet lost its starting-verb columns — Bash, Dash, Push,
  Transmute, Scramble, Bombs, Keys and Random
  (`tools/oneshots/_characters_no_stats.py`). A run opens with every verb at 0.
- A level-up's `Reward` keeps what it pays — a chest, a card, loot, Max Health,
  gold — and loses its verb: Isaac's "+1 Scramble", the Manager's "+1 Push",
  Minä's "+1 Transmute" and Zoe's "+1 Dash". **Minä's and Zoe's rewards were
  nothing but a verb**, so their level-ups now pay nothing past the level itself
  (and its XP). That is for the owner to refill on the sheet if wanted.
- `generate_character2_tres.py` **refuses** a Reward that names a verb, rather
  than reading it as nothing.
- **The Erratic Deck's challenge** ("Beat a game while having selected a random
  starting build") was written against the Random column, which is gone. The
  wording is the owner's to revisit.

## 4. Hunger

`GameState.hunger`, saved with the run; rules in `HungerSystem`.

| | |
|---|---|
| Start | 3 (`START`) |
| Most | 5 (`MAX`) |
| A game handed in (beaten, missed, escaped) | −1 |
| …already at 0 | −2 Health instead (`STARVE_DAMAGE`) ☠ |
| A run lost already at 0 | −2 Health ☠ (Hunger itself is not touched) |
| Drinking any potion | +1 (a thrown potion feeds nothing) |
| Eating food | +1, and the piece is destroyed |

- **The drain only starts once you are empty**: the game that takes Hunger to 0
  costs nothing more; the NEXT thing — a game handed in or a run lost — costs
  Health. (The owner: "only when you're at zero and then do something.")
- **Where it fires** (`docs/turn-order.md`): last in `Overworld2.report`, after
  the game's own loot was queued, so food the haul is about to hand over cannot
  save you; and in `GameLoop2.log_attempt` after the enemies' turn. Both use
  `GameLoop2.lose_health`, which is not a hit — no shield stops it — and ends the
  run on the spot if Health runs out.
- **Food** is anything tagged `food` on its sheet row: relics (`items`) and loot
  (`trinkets` today). `HungerSystem.edible()` lists both.
- **The screen**: the bar is five drawn pips beside the character token at the
  top left of the header (drawn, not `■□` glyphs — a hollow box is what a missing
  character looks like on stream, BattlefieldView's ladder note). **Eat** sits
  beside it while there is food, greyed out at 5 so food is never wasted.
  Pressing it lights the food in the pack and on the relic strip (`OwnedPick`, the
  gesture Identify uses) and a click eats one. Both are hidden for a player
  without Hunger.
- The numbers are a first cut the owner expects to tune.

## 5. Unidentified weapons

A weapon the run **finds** — a drop, a chest, a shop shelf — is rolled when its
pack entry is made (`WeaponSystem.new_entry`): **−2 to +2 Stun**, weighted
40% unchanged, 20% each for +1 and −1, 10% each for +2 and −2
(`ROLL_WEIGHTS`). The entry carries `roll` and `roll_known`.

- **A starting weapon is never rolled**: the character's loadout and the
  genre's starting gear are handed over with `GameState.granting_start_kit` on.
- **Hidden until the first swing.** The name reads "Hero Sword +?", the tile wears
  a "+?" chip, and the card says the roll is unknown. The swing still lays it
  (`stun_for` adds a hidden roll), and the swing is what reveals it
  (`LootSystem.use_loot` → `WeaponSystem.reveal`). A **Scroll of Identify**
  reveals it too: an unknown weapon is unidentified, one fact per piece rather
  than per kind.
- **Once known it is an upgrade or a downgrade**, in the same "+X" the Enchant
  scroll already used: "Hero Sword +1", "Hero Sword -2"; +0 is just "Hero Sword".
  A swing never lays less than 0 Stun.
- **A known minus is CURSED**: `GameState.is_pinned` is true, and the piece stays
  exactly where it sits — no moving, turning, being swapped aside, dropping in
  the bin or smelting, and a bag holding it cannot move either. It can still be
  swung. **Before** it is known it is an ordinary piece and can be dropped: nobody
  knows to be stuck yet.
- **Anything that removes a curse removes it** — Scroll of Remove Curse lists each
  cursed weapon beside the curse goals, and its `all` and `random` modes draw from
  both. Lifting it (`lift_curse`) frees the piece and holds its Stun to at least
  1 from then on. The minus stays in its name.
- **An evolution keeps the roll**, known or not, curse and all: it is the same
  weapon grown, not a new find.

## 6. On the board: the player, with the character on it

The hero frame at the head of the board (`BattlefieldView`) draws the **player's**
art, and the character the run is played as rides on it as a round badge at its
top-left (`scripts/redesign2/CharacterBadge.gd`): their icon clipped to a circle
and ringed in gold. The owner, 13 Nov 2026.

- **Hovering the badge** opens the character's card (`CharacterBadge.card`): the
  full portrait, then their name and game, level and Health, how they level up
  and what it pays, the gold and loot they started with, and their line.
- **Hovering the frame** is the player: their name, who they are playing as, and
  each mechanic in a line.
- **A player with no art** (the basic player) leaves the frame to the character's
  full portrait, as it always was. There is then no badge, and hovering the frame
  opens the character's card.

**The header** (top left of the page) reads left to right the way the run was
picked: the PLAYER's token, then the character's, then the level. A player's token
is `PlayerData.icon` — `images2.0/players/Icon/<File>.png` when there is one, else
the full picture. Retro Bat's is its own sprite. Batsaac's is his FACE, cut out of
the painting (eyes, tears and mouth, and the base of the ears so it still reads as
a bat — the owner asked to zoom out that far), cut as a
CIRCLE (the owner's ask; the round mask is baked into the PNG with a smooth
edge, so it is round wherever it is drawn), and stored pre-shrunk at 52px, twice
the chip, then drawn with smoothing: art at or under
128px is otherwise drawn nearest-neighbour as pixel art, and a painting shrunk
that way, with no mipmaps, comes out as noise. The basic player, with no art, has
no token.

