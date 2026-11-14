# Customization

The **✦ Customization** button in the main menu's Extras list (`scripts/menu/CustomizeScreen.gd`)
opens one screen with four tabs. Everything on it is earned by ranking up games
and characters, and every choice is saved per profile
(`user://profiles/<n>/customization.json`, the `Cosmetics` autoload).

| tab | what it changes |
|---|---|
| **Characters** | each character's **icon** and **full portrait**, chosen separately |
| **Hats** | what each **player** (Retro Bat, Batsaac) wears on its head (§7) |
| **Icons** | what is drawn in place of 🗝 (keys), ✸ (bombs), 🏆 (the trophy), 🍀 (Luck), 🎁 (a chest), ♥ (Health), ⚔ (damage), ◉ (gold) and 🛡 (a shield) |
| **Title Letters** | which earned letters the main menu's title may be spelled from |

## 1. Earning: a rank is a song, a letter or a look

A game at rank N, and a character at rank N, has earned N rewards. Before this
change each was a radio song or a title letter, 50/50. A third kind now joins
them: a **look**, which is one costume, one icon set or one hat (§7) (`RankRewards.split`).

- **One roll per rank, among the kinds with something left.** The order is
  letter, song, look, and the roll picks one of the kinds still open, evenly.
  With no looks to earn (nearly every game) that is the old coin exactly, so
  those games' history does not move. A game that HAS looks (Haste, Hades, the
  Isaac games, both Spires, Spelunky 2, Risk of Rain 2…) re-splits its ranks.
  Songs and letters already drawn are kept, because nothing is ever locked again.
- **Who pays which.** A **game**'s ranks draw that game's looks. A
  **character**'s ranks draw the looks of the games they come from, plus their
  own costumes (`CosmeticCatalog.units_of_character`).
- As with letters, how many have been earned is worked out from the rank, and
  WHICH ones came up is a random draw that is stored with who drew it. Each one
  is toasted as it arrives ("✦ New costume: Zoe — Clown").
- A test profile's **Unlock everything** reads every look as unlocked.

## 2. The catalog: the file name is the entry

`tools/build_cosmetics_index.py` writes `data/cosmetics.json` from the art
folders. Drop a PNG in and rerun it. CI and `test_customization.gd` fail while the
JSON is stale.

```
images2.0/characters/Costumes Icon/<Character>_<Costume>.png   the icon only
images2.0/characters/Costumes Full/<Character>_<Costume>.png   the full portrait only
images2.0/characters/Costumes Both/<Character>_<Costume>.png   one picture, both
images2.0/icons/Keys/<Name>_<Game>.png
images2.0/icons/Bombs/<Name>_<Game>.png
images2.0/icons/Difficulties/<Name>_<Game>[_<lo>-<hi>].png
images2.0/icons/Luck/<Name>_<Game>.png
images2.0/icons/Chests/<Name>_<Game>[_<lo>-<hi>].png
images2.0/icons/Health/<Name>_<Game>.png
images2.0/icons/Damage/<Name>_<Game>.png
images2.0/icons/Gold/<Name>_<Game>.png
images2.0/icons/Shields/<Name>_<Game>.png
images2.0/icons/Hunger/<Name>_<Game>.png
images2.0/hats/<Name>_<Game>.png                  a hat, its game's rank-up reward (§7)
images2.0/hats/Special/<Name>_<Game>.png          a hat earned some other way (§7)
```

- **An icon goes in at its best version, every time** (the owner, 13 Nov 2026).
  What gets pasted into a conversation is usually a wiki thumbnail: Brotato's
  four arrived at 60 px with a dither pattern and the wiki's originals were a
  clean 96. Before a file lands in `images2.0/icons/`, run
  `python3 tools/icon_research.py best "<Game>" <File.png>`, which fetches the
  wiki's original and every look-alike, largest first, and LOOK at them: a
  bigger file with a frame is a different icon. Say in the reply which version
  went in. Icons can also be researched for the owner to tick:
  [research.md](research.md) §6.8.
- `<Character>` is the display name with underscores (`Antonio_Belpaese`), and
  what follows it is the costume's title (`Slay_the_Spire_2` → "Slay the Spire
  2", `Clown_B&W` → "Clown B&W").
- **A costume's game** is the game its title names (Ironclad's *Slay the Spire 2*,
  the sequel), or the tool's `OVERRIDES` (Isaac's *Rebirth* and *Rebirth
  Descent* → Rebirth, *Stray* → Mewgenics, Zagreus's *Hades 2* → `hades_ii`), or
  else the character's own first game (Ironclad's *Rest* → Slay the Spire, Isaac's
  *Descent* → The Binding of Isaac, all of Zoe's → Haste).
- **A Both costume is one unlock.** Vampire Survivors' are one small picture
  used as the icon and as the full portrait, so each one appears in both rows of
  the Characters tab.
- **An icon's game** is the longest game id its name ends with; what comes before
  it is the icon's own name (`Chthonic_Key_Hades` → "Chthonic Key", Hades).
- **A difficulty with a `_<lo>-<hi>` range is one image in a SET.** Every file of
  that game is one unlock, and the Fracture level picks the image: Risk of Rain
  2's Drizzle covers 0–3, Rainstorm 4–7 and Monsoon 8–10
  (`CosmeticCatalog.image_for`).
- **A chest's `_<lo>-<hi>` range is the chest's SIZE, not the Fracture:** 0 Small,
  1 Medium, 2 Large, 3 Huge (`Data.ChestSize`). Enter the Gungeon's D, C, B and A
  chests are `0-0`, `1-1`, `2-2` and `3-3`: one unlock, all four at once, and the
  chest on screen picks the picture, so the same rung of the ladder that colours
  its glow picks its letter.
- **4 is a boss's chest** (`CosmeticCatalog.BOSS_CHEST`), a rung above Huge that
  only a chest of boss relics stands on (`ItemDropModal.is_boss_chest`). Slay the
  Spire's set is Small `0-0`, Medium `1-1`, Large `2-3` (Large and Huge) and Boss
  `4-4`, so its Boss Chest is drawn for a boss's chest and nothing else. A set
  with no picture for 4 draws its highest (Gungeon's A chest): `image_for` gives
  any level above every range the highest image.
- **A picture's name need not be the size it stands for.** Risk of Rain's Small
  Chest is `0-0`, its Large Chest `1-1` (a Medium) and its Golden Chest `2-3`
  (Large and Huge, and a boss's). The hover says both: "Large Chest, Medium Chest".

## 3. Wearing a costume

`CharacterData.shown_portrait()` / `shown_icon()` return the costume being worn,
else the character's own art. Every screen that draws a character reads these
two and not `portrait` / `icon`: the picker, the run page and its board, the
report, the Collection, the radio, the masks, the OBS overlay and the menu's
falling art. **A new screen that draws a character should do the same.** A
costume that is not unlocked (after a profile switch, or with "Unlock everything"
turned off) reads as the default and is not cleared, so it comes back when it
is unlocked again.

### Choosing in the character picker

The picker (`CharacterPicker._costume_rows`) has a band across the foot of the
detail panel for every hero with costumes: an **Icon** strip and a **Full** strip.
They hold the same choices as the Customization screen, because both use
`CustomizeScreen.slot_tiles`. A strip scrolls sideways rather than wrapping, and
the panel never scrolls. A change redraws the portrait and the hero's grid token
at once.

### Every slot's choices

Each slot (a character's icon or full portrait, or the key, bomb, difficulty,
Luck, chest, Health, damage, gold or shield icon) offers:

- **Default:** the character's own art, or the glyph.
- **🎲 Random:** a different look every run, rolled at `GameLoop2.start_run`
  (`Cosmetics.roll_random`) from the default and every unlocked look that fits.
  The roll is saved, so the menu shows what this run wears; its tooltip names it.
- **Every look** that fits. A **locked** one is its own picture as a black
  silhouette, like the Collection's unseen entries, with where it comes from on
  the hover.
- **A set of several icons shows all of them on the hover.** A tile has room for
  one picture, so a set (Risk of Rain 2's three difficulties, Enter the Gungeon's
  four chests) hovers as a card with every picture in it, each over its name and
  when it is the one drawn (`CustomizeScreen.set_hover`, `HoverCard`'s `gallery`).
  Locked, the pictures are silhouettes like the tile. **A new set gets this for
  free; a new place that shows a set's tile should attach the same card.**
- **New looks glow.** A look drawn since it was last shown pulses three times,
  using `LogoProgress`'s glow for new title letters, and is then marked seen
  (`Cosmetics.is_new` / `mark_seen`, per profile). This happens wherever its tile
  is first shown: the Customization screen or the picker.

## 4. Wearing an icon: every 🗝 ✸ 🏆 🍀 🎁 ♥ ◉, everywhere, and ⚔ where it is damage

The owner's words: "everywhere means everywhere, and with the number on top of
it too". The UI writes these as text inside ordinary Labels and Buttons,
so `Cosmetics` watches the tree's `node_added` while any icon is worn. Each
Label or Button whose text holds one of them gets the glyph swapped for
spaces, and the picture is laid over that gap (`apply_glyph`, `_place_glyph`).
On a 🏆, the Fracture level is written over the picture in `Fracture.COLOR`.

- **Which level**: a node's `glyph_level` meta if it has one, otherwise the run's
  own Fracture during a run and 0 outside one. A level of 0 shows no number, as
  with the cup. `RankBadge` passes each trophy's own best level and sets
  `glyph_number = false`, because it already draws that number.
- **One picture per node:** the first worn glyph in a node's text is the one
  swapped. Nothing in the UI today writes two of them in one Label.
- **A gift's level is the chest's size** (0 Small … 3 Huge, 4 a boss's), again from
  `glyph_level`, and it carries no number. The drop window's gift passes its own
  rung (`ItemDropModal._gift_badge`); the "N Chests" heading and the report's
  chest sum pass their biggest chest's. A 🎁 with no `glyph_level` is drawn as the
  smallest chest: only the trophy falls back to the run's Fracture.
- **♥ is THE heart**, the player's and every enemy's. Enemies used to be drawn
  with ❤ (U+2764), which a worn Health icon would not have covered;
  `test_customization.gd` fails a script that writes it.
- **⚔ is damage only where a node says so.** The crossed swords are also "beaten"
  on every record line, the Combat button and the weapons tab. A node that writes
  ⚔ as DAMAGE marks itself with `Cosmetics.as_damage(node)` (the board's damage
  badge, the game card's stat pair, the enemy card's Damage row), and only a
  marked node's ⚔ is swapped. **A new place that shows damage has to mark it.**
- **A site that measures text before it is on a node** asks
  `Cosmetics.roomed(text, font, size, damage)` for the text as it will stand: a
  picture's room is a little wider than its glyph, and the board fits a body's
  ♥ and ⚔ badges to its width (`BattlefieldView.stat_row_width`).
- **A shield is 🛡, written AND drawn.** In text it is the glyph (an enemy's
  shield badge, the inventory, a blocked hit). Where shields stand as pictures
  (the pips over the hero, the chip beside the Health, the Camp's Rest, the OBS
  overlay) the picture is `Cosmetics.shield_art()`: the worn shield icon, else
  `UITheme.SHIELD_ART`, which is that same glyph drawn once by
  `tools/build_shield_art.py`. **Draw a shield with `Cosmetics.shield_art()`,
  never `UITheme.SHIELD_ART` directly.** The pixel shield that used to be the
  default is Brutal Orchestra's icon to earn.
- **Hunger is only ever drawn**, five to the bar in the header for a player with
  Hunger (`docs/players-design.md` §4): `Cosmetics.hunger_art()`, the worn Hunger
  icon, else `UITheme.HUNGER_ART` — the 🍗 glyph drawn once in Hunger's amber by
  `tools/build_hunger_art.py`, the way the shield's is. To earn (the owner's yes,
  14 Nov 2026): Mewgenics' Food, Vampire Survivors' Floor Chicken and Loop Hero's
  Food Supply. A big PAINTED icon (over 128 px) is shrunk with Lanczos, once,
  to the icon's real size in SCREEN pixels and drawn 1:1 (`UITheme.shrunk`,
  `screen_scale`): nothing generates mipmaps, so sampling it straight broke
  Mewgenics' outline into dots, and shrinking to twice the size and letting the
  GPU halve it again made it blurry. Pixel art (128 px or under) is drawn as it
  always was. The basic 🍗 is drawn at 256 px so it is shrunk the clean way.
- **Gold is ◉**: the purse chip, the shop's purse, prices and gold Reroll, the
  Steal action and the inventory's Gold line. A kind with nothing to earn says so
  on its row ("No icons to earn yet").
- **Text set after a node enters the tree** is not seen by the watch, so a site
  that rewrites its text calls `Cosmetics.apply_glyph(node)` itself: the board's
  Bomb button, both win banners, the "N Chests" heading, the Health and gold
  chips, the hero's Health line, the shop's purse, prices and Reroll, and the
  Customization screen's own status line.
- **Limit:** a glyph inside text that wraps by width (not by `\n`) is placed as if
  the line did not wrap. Every one of these glyphs in the UI today either starts its line or
  sits in a one-line label.

## 5. Title letters

Two kinds of switch: a whole game's letters (its checkbox) and one letter at a
time (its tile). Rogue's starter font can be switched off too. **A switch-off
is refused** when what would be left could not spell both "Roguelike-Like" and
"The Search for the Amulet of Nivlac" (`Cosmetics.can_spell`, using the same
rule as `TitleLetters.pick`). `TitleLetters.available()` leaves out whatever is
switched off. If the earned letters shrink underneath the switches, it ignores
them rather than leave a hole in the title. The menu redraws the title when the
screen closes.

## 6. The menu's falling art shows only what has been seen

`MenuFallingArt` drops only what the player has seen in a run (`GameStats.seen`,
the same rule as the Collection's "???"): games, enemies, bosses, items, loot and
characters. Loot art is matched by name against every kind at once, using each
piece's id and its `art_file()`. That is how Ride the Bus and Barricade, which are
cards whose pictures sit in `items/`, and the scrolls (art "Identify", id
`scroll_of_identify`) are found. The pill capsules and the scrolls' Unidentified
back fall once any of their kind has been seen. Covers are matched by each game's
own `cover_path`. `test_menu_falling_art.gd` marks everything seen and requires
every picture in those folders to match, so a new picture whose name matches
nothing fails CI. Every unlocked costume, icon and hat falls too, taken
whole like the characters, and a character falls in the costume it wears. On a
brand-new profile nothing falls until something has been seen.

## 7. Hats: what a player wears

Asked for and decided by the owner on 14 Nov 2026: hats on the **players**, the
way pets wear them in Super Auto Pets. Not on the characters.

- **What there is.** Super Auto Pets' 88 current hats: every one the wiki lists as
  *Play to Unlock* (70) or bought in its Hat store (18), at the CURRENT picture,
  never "Previous Version". The only special hat is the **Abandon Hat**. The
  pictures are the wiki's original files, **mirrored** on the way in, because the
  wiki draws every hat facing right and the players face the other way. They were
  fetched by `tools/oneshots/_hats_super_auto_pets.py`, which also mends two of
  the wiki's typos ("Rude Hate", "Flat top Hat"). Its play-to-unlock "Real Bucket
  Hat" links the same file as the bought Bucket Hat, so the two are one hat.
- **Earning.** A hat is a look like a costume or an icon (§1), and it belongs to
  its game, so **Super Auto Pets' ranks pay its hats**. That game has no radio
  songs, so each of its ranks is a hat or one of its title letters, and only
  hats once the letters are all drawn. **No character's ranks draw a hat**
  (`CosmeticCatalog.units_of_character` skips them), even a character from that
  game. A `Special/` hat carries `"special": true` in the index, and
  `units_of_game` leaves it out, so no rank ever draws it.
- **The Abandon Hat** is earned by **escaping five games in a row in one run**.
  The owner chose "within one run": `GameState.escape_streak` is the run's,
  saved with it and zeroed by `reset_run`. `Overworld2.report` counts it in its
  bookkeeping step, where every game is handed in: an escape adds one (a
  teleport out is an escape too), and any other report sets it back to 0. It
  then asks `Cosmetics.note_escape_streak`.
  **The rule is an achievement** (the owner, 14 Nov 2026): a row of the
  `achievements` sheet under the `Hats` tab (`hat_abandon_hat`: one run,
  `escape games in a row`, goal 5; [achievements.md](achievements.md)). The
  number of escapes and the sentence a locked tile's hover shows
  (`Cosmetics.special_how`) are that row's `Goal` and `Description`, the
  Achievements screen lists it with the best streak so far, and finishing it
  unlocks the hat and toasts it like a rank's. A profile that earned the hat
  before it had a row has the achievement from its first boot.
- **Where it sits: a spot per picture, on the sheet.** The `players` sheet's
  `Hat` column holds `x, y, width, tilt` (generator:
  `tools/generate_player_tres.py` → `PlayerData.hat_spot`).
  `x, y` is where the hat's **brim** lands, as a percent of the picture across
  and down. The brim is the point 50% across and 75% down the hat picture
  (`HatArt.ANCHOR`). `width` is the hat's width as a percent of the picture's,
  and `tilt` is degrees clockwise about the brim. A blank `Hat` means no spot,
  and that player wears nothing (Basic, who has no picture). The owner placed
  both: Batsaac's flat, "very slightly to the left" of centre (`46, 31, 42, 0`);
  Retro Bat's on his right ear, leaning out the way Super Auto Pets leans its
  hats, picked off a sheet of ear and tilt previews (`74, 20, 55, 35`).
- **Wearing.** `HatArt.wear` COMPOSES the hat into the picture once and caches
  it. Every screen that draws a player's full picture as themselves asks
  `PlayerData.shown_portrait()` (`Cosmetics.player_art`) and gets the player in
  their hat: the player picker's tiles and portrait, and the hero on the board.
  **A new screen that draws a player should do the same.** The header's small
  token (`PlayerData.icon`) is always bare, the owner's call ("icon shouldn't
  have a hat"), and so is an achievement's picture of a player still to unlock. A hat taller than the room above the head grows the canvas upward
  rather than being cut off. Pixel art (Retro Bat, 10×15) is first scaled up
  in whole pixels so the hat keeps its painted detail; a small painted picture
  is scaled up smoothly.
- **Choosing.** Each player has its own slot (`Cosmetics.hat_slot`,
  `"hat:<player>"`) with 🎲 Random, No hat and every hat. Locked hats show as
  silhouettes. The choices are the same on the Customization screen's Hats tab
  (a preview of the player in what they wear, then the tiles) and in a strip
  across the foot of the player picker (`PlayerPicker._fill_hat_row`). Both use
  `CustomizeScreen.hat_tiles`. Tests: `test/test_hats.gd`.

- **Not yet: Megabonk's hats.** Megabonk has 21 (its update 1.0.64), each earned
  by an achievement of the same name. All 21 are researched and held in
  `research/hats/`: `megabonk.csv` (name, Megabonk's own unlock, Steam api name)
  and a cut-out picture of each, made from its Steam achievement icon by
  `tools/oneshots/_hats_megabonk_research.py`. They are **not in the game**: the
  owner wants them unlocked by mechanics that don't exist yet ("lets not deal
  with these yet"). When those exist, the pictures go in `images2.0/hats/` like
  Super Auto Pets' did. megabonk.wiki may have better pictures; it was outside
  this session's network allowlist.
