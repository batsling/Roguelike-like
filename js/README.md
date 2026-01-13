# JavaScript Module Architecture

This directory contains all JavaScript modules for the Roguelike-Like game. The codebase has been refactored into focused, maintainable modules with clear responsibilities.

## Module Overview

### 📊 Total Stats
- **15 modules** (down from massive single file)
- **main.js reduced by 41.5%** (6,757 → 3,950 lines)
- **Better maintainability** - Each module has clear responsibilities
- **Easier for LLMs** - Smaller, focused files are easier to understand

---

## Core Architecture

### 🎮 Game Data & State
- **`data.js`** - State management, game loading, save/load system
  - All state variables (health, gold, inventory, etc.)
  - Character data (PLAYER_CHARACTERS)
  - JSON file loading
  - Game state persistence

### 🖼️ UI & Display
- **`ui.js`** - All DOM manipulation and display updates
  - `updateTopBar()` - Health, gold, stats display
  - `updateInventory()` - Inventory rendering
  - `updateHealthDisplay()` - Health bar visualization
  - `updateGameStats()` - Stats sidebar
  - All visual element updates

### 🎨 Modal System (NEW - Extracted Jan 2025)
- **`modals.js`** - Centralized modal utilities (48 lines)
  - `createGameModal(content)` - Standard modal creation
  - `closeGameModal()` - Modal closing with fade animation
  - Used by all other modal-dependent systems

---

## Game Systems

### ⚔️ Combat & Encounters
- **`combat.js`** - Combat resolution and dice rolling
  - Enemy generation logic
  - D20 rolling with stat modifiers
  - Critical failure handling (Curse of Failure)
  - Success/failure outcomes
  - Curse trigger logic during combat

- **`events.js`** - Random events and special encounters
  - Event selection and validation
  - Requirement checking
  - Multi-stage event flows
  - Generic combat integration
  - 3 built-in events: Primordial Teleporter, Wild Muncher, Colosseum

- **`items.js`** - Item effects and interactions
  - `ITEM_EFFECTS` object defining all item behaviors
  - Passive, Usable, and Triggered item types
  - Stat modification helpers
  - Item acquisition/removal effects

### 🛒 Shop System (NEW - Extracted Jan 2025)
- **`shop.js`** - Complete shop system (309 lines)
  - `showShopModal()` - Displays shop with 3 random items
  - `leaveShop()` - Shop cleanup and state reset
  - Shop reroll system (0 → 5 → 10 → 15 gold progression)
  - Curse of Frugality price modifications
  - Item purchasing with price calculations

### 😈 Curse & Verification Systems (NEW - Extracted Jan 2025)
- **`verification.js`** - Curse and trait verification (625 lines)
  - `showCurseVerificationModal()` - Entry point for all verifications
  - `verifyCursesCombined()` - Combined modal for all curse types:
    - **Restriction curses** (purple): Blindness, Hubris I/II/III
    - **Manual curses** (orange): Devotion, Greed, Impulse, Haste, Guilt
    - **Trait effects** (blue): Precision Landing
  - `showPerfectGameVerificationModal()` - Legacy Precision Landing modal
  - `showDeathScreen()` - Death screen for curse damage
  - Helper functions: `getCurseMaxUses()`, `createCurseObject()`, `addCurse()`, `checkCurseDurations()`

---

## End-Game Systems

### 🚪 Escape Phase (NEW - Extracted Jan 2025)
- **`escape.js`** - Escape sequence and end-game (1,086 lines)
  - `startEscapePhase()` - Game selection modal (choose 3 games)
  - `showEscapeVisualization()` - Visual escape interface with player icon
  - `recordLostRun(index)` - Lost run tracking with HP penalty
  - `completeEscapeGame(index)` - Advance to next escape game
  - `updatePlayerIconPosition()` - Animated player movement
  - `showVictoryScreen()` - Victory display with final stats
  - `saveRunToHistory()` / `showRunHistory()` - Victory history tracking

### 📚 Collection System (NEW - Extracted Jan 2025)
- **`escape.js`** (also contains collection)
  - `showCollection()` - Collection viewer modal
  - `switchCollectionTab(tab)` - Switch between Games/Items/Enemies/Curses
  - `sortCollectionItems(sortType)` - Sort items by A-Z, Rarity, Game
  - `switchCurseTier(cardIndex, tier)` - Curse tier display (I, II, III)
  - 4 collection tabs:
    - **Games**: 532 games with covers and influence tooltips
    - **Items**: 22 items with images and descriptions
    - **Enemies**: All enemies with stats and images
    - **Curses**: All curses grouped by base name with tier switching

### 🎯 Bingo System (NEW - Extracted Jan 2025)
- **`bingo.js`** - Bingo grid and rewards (436 lines)
  - `BINGO_GOALS` - 40 goals (easy/normal/hard difficulty)
  - `generateBingoGrid()` - Creates 3x3 grid with difficulty distribution
    - 1 easy goal in center
    - 2 hard goals in random positions
    - 6 normal goals filling remaining spaces
  - `renderBingoGrid()` - Renders grid HTML with difficulty badges
  - `toggleBingoCell(index)` - Mark goals as complete
  - `checkForBingo()` - Detect completed lines (rows/columns/diagonals)
  - `grantBingoReward(bingoCount)` - Progressive reward system:
    - **All rewards**: +1 to all combat stats
    - **Reward 1-2**: Common items
    - **Reward 3**: Common items + 2 Reroll
    - **Reward 4**: Uncommon items
    - **Reward 5**: Uncommon items + 1 Skip
    - **Reward 6**: Rare items
    - **Reward 7**: Rare items + FoV & Discovery
    - **Reward 8**: Rare items + Dash
  - `giveRandomItems(rarity, bingoCount, bonusText)` - Item selection modal
  - Reward queue management for multiple bingos

---

## Player & Map Systems

### 👤 Character Selection (NEW - Extracted Jan 2025)
- **`character-select.js`** - Character selection UI (101 lines)
  - `populateIconCharacterView()` - Character grid display
  - `showIconCharacterDetails(charKey)` - Character info panel
  - Displays character stats, traits, and descriptions
  - Event listeners remain in main.js

### 🗺️ Map & Navigation
- **`map.js`** - SVG map visualization
  - Map loading and rendering
  - Pan and zoom controls
  - Player/amulet marker placement
  - Box highlighting for game locations
  - Map interaction handlers
  - Arrow system for visual connections

- **`gameplay.js`** - Game progression and pathfinding
  - `addNode()` - Creates visual path nodes
  - `renderGamePath()` - Renders dungeon path
  - `bfs()` - Breadth-first search for pathfinding
  - `getConnectedGames()` - Gets adjacent games
  - Node click handlers
  - Game progression logic

---

## Central Orchestration

### 🎯 Main Controller
- **`main.js`** - Game initialization and coordination (3,950 lines)
  - Initialization code
  - Event listener setup
  - Excel file upload handler
  - Tutorial toggle
  - Global window exports
  - Coordinates all other modules

**Key Responsibilities:**
- Sets up initial game state
- Registers event listeners
- Coordinates module interactions
- Handles special game states
- Manages global exports

---

## Module Dependencies

### Load Order (from index.html)
```html
<!-- Data first -->
<script src="js/data.js"></script>

<!-- Core systems -->
<script src="js/items.js"></script>
<script src="js/ui.js"></script>
<script src="js/combat.js"></script>
<script src="js/events.js"></script>
<script src="js/gameplay.js"></script>
<script src="js/map.js"></script>

<!-- UI modules (depend on core) -->
<script src="js/modals.js"></script>
<script src="js/shop.js"></script>
<script src="js/character-select.js"></script>
<script src="js/verification.js"></script>
<script src="js/escape.js"></script>
<script src="js/bingo.js"></script>

<!-- Main orchestrator (depends on everything) -->
<script src="js/main.js"></script>
```

### Dependency Graph
```
data.js
  ↓
items.js, ui.js, combat.js, events.js, gameplay.js, map.js
  ↓
modals.js → shop.js, verification.js, escape.js, bingo.js
  ↓
character-select.js
  ↓
main.js (orchestrates everything)
```

---

## Key Design Patterns

### 1. Modal System
All modals use the centralized `createGameModal()` and `closeGameModal()`:
```javascript
// Create modal
createGameModal(`<div>Your HTML content here</div>`);

// Close modal
closeGameModal();
```

### 2. State Management
All state stored in `gameState` object:
```javascript
gameState = {
  phase: 'selection',
  currentGame: 'Game Name',
  visitedGames: [],
  finishedGames: [],
  health: 10,
  // ... more state
};
```

### 3. Global Exports
Functions needed by other modules are exported to `window`:
```javascript
window.functionName = functionName;
```

### 4. Helper Functions
Utility functions reduce duplication:
- `updateStat(statName, value)` - Modify stats safely
- `createNotification(message, color, icon)` - Show notifications
- `determineEncounterType()` - Random encounter generation
- `getCursesByType(type)` - Filter curses
- `getPowerValue(power, values)` - Convert power levels

---

## Module Statistics

| Module | Lines | Purpose | Extracted |
|--------|-------|---------|-----------|
| `data.js` | ~800 | State & data loading | Pre-existing |
| `ui.js` | ~600 | DOM updates | Pre-existing |
| `combat.js` | ~500 | Combat resolution | Pre-existing |
| `events.js` | ~700 | Event system | Pre-existing |
| `gameplay.js` | ~900 | Game progression | Pre-existing |
| `map.js` | ~400 | Map visualization | Pre-existing |
| `items.js` | ~500 | Item effects | Pre-existing |
| **`modals.js`** | **48** | **Modal utilities** | **Jan 2025** |
| **`shop.js`** | **309** | **Shop system** | **Jan 2025** |
| **`character-select.js`** | **101** | **Character UI** | **Jan 2025** |
| **`verification.js`** | **625** | **Curse verification** | **Jan 2025** |
| **`escape.js`** | **1,086** | **Escape & collection** | **Jan 2025** |
| **`bingo.js`** | **436** | **Bingo system** | **Jan 2025** |
| `main.js` | 3,950 | Orchestration | Reduced from 6,757 |

**Total reduction:** 2,807 lines removed from main.js (41.5%)

---

## Benefits of Current Architecture

### ✅ Maintainability
- Each file has a single, clear responsibility
- Easy to locate specific functionality
- Changes are isolated to relevant modules

### ✅ Readability
- Smaller files are easier to understand
- Clear module boundaries
- Logical organization

### ✅ LLM-Friendly
- Smaller context windows needed
- Focused modules reduce confusion
- Clear dependencies

### ✅ Collaboration
- Multiple developers can work on different modules
- Reduced merge conflicts
- Clear ownership of functionality

### ✅ Testing
- Easier to test individual modules
- Clear input/output boundaries
- Isolated functionality

---

## Adding New Features

### Example: Adding a New Modal-Based System

1. **Create new module file** (e.g., `js/new-system.js`)
2. **Import modal utilities:**
   ```javascript
   // Modal utilities already loaded via modals.js
   createGameModal(content);
   closeGameModal();
   ```
3. **Define your system:**
   ```javascript
   function showNewSystem() {
     createGameModal(`
       <div>
         <h2>New System</h2>
         <button onclick="handleNewSystemAction()">Action</button>
       </div>
     `);
   }

   function handleNewSystemAction() {
     // Your logic here
     closeGameModal();
   }
   ```
4. **Export functions:**
   ```javascript
   window.showNewSystem = showNewSystem;
   window.handleNewSystemAction = handleNewSystemAction;
   ```
5. **Add script tag to index.html** (before main.js):
   ```html
   <script src="js/new-system.js?v=1"></script>
   ```

---

## Refactoring Guidelines

### When to Extract a Module
- ✅ Functionality > 200 lines
- ✅ Clear, single responsibility
- ✅ Used by multiple parts of the codebase
- ✅ Can be tested independently

### When to Keep in main.js
- ❌ Initialization code
- ❌ Event listener setup
- ❌ Global coordination logic
- ❌ Small utility functions (< 50 lines)

### Best Practices
1. **Keep modules focused** - One responsibility per file
2. **Document dependencies** - Note what each module needs
3. **Export clearly** - Only export what's needed
4. **Test thoroughly** - Verify nothing broke after extraction
5. **Update documentation** - Keep this README current

---

## Future Improvements

### Potential Optimizations
- **ES6 modules** - Convert to `import`/`export` syntax
- **Module bundling** - Use webpack or vite for production
- **Type safety** - Add JSDoc or TypeScript
- **Testing** - Add unit tests for each module
- **Documentation** - Add inline JSDoc comments

### Not Recommended
- **Over-modularization** - Don't split too much
- **Circular dependencies** - Avoid modules depending on each other
- **Global state pollution** - Keep exports minimal

---

## Troubleshooting

### Module Not Found
- Check script tag order in index.html
- Verify file path is correct
- Check for typos in filename

### Function Not Defined
- Ensure function is exported: `window.functionName = functionName`
- Check script load order (dependencies first)
- Look for typos in function name

### Broken Functionality After Extraction
- Verify all code was moved correctly
- Check global variable dependencies
- Test thoroughly in browser console
- Review `gameState` access patterns

---

**For detailed API documentation, see the root README.md**
**For game feature documentation, see individual module comments**
