# Customization

The **✦ Customization** button in the main menu's top-left row, beside How to Play, (`scripts/menu/CustomizeScreen.gd`)
opens one screen with three tabs. Everything on it is earned by ranking up games
and characters, and every choice is saved per profile
(`user://profiles/<n>/customization.json`, the `Cosmetics` autoload).

| tab | what it changes |
|---|---|
| **Characters** | each character's **icon** and **full portrait**, chosen separately |
| **Icons** | what is drawn in place of 🗝 (keys), ✸ (bombs) and 🏆 (the trophy) |
| **Title Letters** | which earned letters the main menu's title may be spelled from |

## 1. Earning: a rank is a song, a letter or a look

A game at rank N, and a character at rank N, has earned N rewards. Before this
change each was a radio song or a title letter, 50/50. A third kind now joins
them: a **look**, which is one costume or one icon set (`RankRewards.split`).

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
```

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

Each slot (a character's icon or full portrait, or the key, bomb or difficulty
icon) offers:

- **Default:** the character's own art, or the glyph.
- **🎲 Random:** a different look every run, rolled at `GameLoop2.start_run`
  (`Cosmetics.roll_random`) from the default and every unlocked look that fits.
  The roll is saved, so the menu shows what this run wears; its tooltip names it.
- **Every look** that fits. A **locked** one is its own picture as a black
  silhouette, like the Collection's unseen entries, with where it comes from on
  the hover.
- **New looks glow.** A look drawn since it was last shown pulses three times,
  using `LogoProgress`'s glow for new title letters, and is then marked seen
  (`Cosmetics.is_new` / `mark_seen`, per profile). This happens wherever its tile
  is first shown: the Customization screen or the picker.

## 4. Wearing an icon: every 🗝 ✸ 🏆, everywhere

The owner's words: "everywhere means everywhere, and with the number on top of
it too". The UI writes these three as text inside ordinary Labels and Buttons,
so `Cosmetics` watches the tree's `node_added` while any icon is worn. Each
Label or Button whose text holds one of the three gets the glyph swapped for
spaces, and the picture is laid over that gap (`apply_glyph`, `_place_glyph`).
On a 🏆, the Fracture level is written over the picture in `Fracture.COLOR`.

- **Which level**: a node's `glyph_level` meta if it has one, otherwise the run's
  own Fracture during a run and 0 outside one. A level of 0 shows no number, as
  with the cup. `RankBadge` passes each trophy's own best level and sets
  `glyph_number = false`, because it already draws that number.
- **Text set after a node enters the tree** is not seen by the watch, so a site
  that rewrites its text calls `Cosmetics.apply_glyph(node)` itself: the board's
  Bomb button, both win banners and the Customization screen's own status line.
- **Limit:** a glyph inside text that wraps by width (not by `\n`) is placed as if
  the line did not wrap. Every 🗝 ✸ 🏆 in the UI today either starts its line or
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
nothing fails CI. Every unlocked costume and icon falls too, taken
whole like the characters, and a character falls in the costume it wears. On a
brand-new profile nothing falls until something has been seen.
