# data/

Game data files. Each file defines a global JS variable loaded by `index.html` before any game logic runs.

| File | Contents |
|---|---|
| `characters-data.js` | Playable characters and starting stats |
| `games-data.js` | Roguelike game library (used for the map/graph) |
| `items-data.js` | Items, equipment, trinkets |
| `enemies-data.js` | Enemies and bosses |
| `events-data.js` | Story events with choices and outcomes |
| `curses-data.js` | Curses |
| `allies-data.js` | Ally companions |
| `weapons-data.js` | Weapons |
| `cards-data.js` | Deck-building cards |
| `dice-data.js` | Dice types and faces |
| `statuses-data.js` | Status effects |
| `moves-data.js` | Move definitions |
| `addons-data.js` | Run modifiers / add-ons |
| `spells-data.js` | Spells |
| `spell-keywords-data.js` | Spell keyword definitions |
| `game-statuses-data.js` | In-game status effects for the board game layer |

## Editing data

Each file is a plain JS file. Edit directly and refresh the browser — no build step required.

## Generating from Excel

Use `scripts/convert-excel.js` to regenerate data files from `tools/Roguelikes.xlsx`.
