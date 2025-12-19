# JavaScript Modules

This directory contains the JavaScript modules for the Roguelike-Like game.

## Current Structure

### data.js
Contains:
- All state variables (games, items, inventory, health, gold, etc.)
- Character data (PLAYER_CHARACTERS)
- Data loading functions for JSON files
- Game state management

**Already modularized and ready to use!**

## Future Refactoring (To Do)

The remaining JavaScript in `roguelikebutton.html` can be further split into:

### ui.js (Recommended next step)
Should contain:
- `updateTopBar()` - Updates health, gold, rations display
- `updateHealthDisplay()` - Updates health bar visual
- `updateInventory()` - Renders inventory list
- `updateBeatenGamesList()` - Renders beaten games
- `updateSelectedGamesDisplay()` - Renders selected escape games
- `updateExcludedGamesList()` - Renders excluded games
- `updateEncounterHistory()` - Renders encounter history
- `updateGameStats()` - Updates stats sidebar in game view
- All DOM manipulation functions

### combat.js
Should contain:
- Enemy generation logic
- Combat dice rolling
- Stat checks and modifiers
- Success/failure outcomes
- Curse management

### gameplay.js
Should contain:
- `addNode()` - Creates visual path nodes
- `renderGamePath()` - Renders the dungeon path
- `bfs()` - Breadth-first search for pathfinding
- `getConnectedGames()` - Gets adjacent games
- Node click handlers
- Game progression logic

### map.js
Should contain:
- SVG map loading
- Pan and zoom controls
- Marker placement (player/amulet)
- Box highlighting
- Map interaction handlers

### events.js
Should contain:
- Random event selection
- Event option handling
- Event consequences
- Shop mechanics

### main.js
Should contain:
- Initialization code
- Event listener setup
- Excel file upload handler (until fully JSON-based)
- Tutorial toggle
- Pact of Punishment handlers

## How to Continue Refactoring

1. **Create a new module file** (e.g., `ui.js`)
2. **Copy relevant functions** from `roguelikebutton.html`
3. **Export functions** if needed:
   ```javascript
   window.updateTopBar = updateTopBar;
   ```
4. **Add script tag** to `index.html`:
   ```html
   <script src="js/ui.js"></script>
   ```
5. **Test** that everything still works
6. **Remove** the copied code from original file

## Benefits of Modularization

✅ Easier to find specific functionality
✅ Multiple people can work on different modules
✅ Smaller files are easier to understand
✅ Better separation of concerns
✅ Easier to test individual components

## Current Status

- ✅ CSS extracted to `css/styles.css`
- ✅ Data files extracted to `data/*.json`
- ✅ Data loading modularized in `js/data.js`
- ⏳ Remaining ~2500 lines of JS to be split
