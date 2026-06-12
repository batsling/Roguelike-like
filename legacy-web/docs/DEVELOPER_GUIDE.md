# Developer Guide - Roguelike-like

This guide explains the codebase structure, new utility systems, and best practices for adding content.

## Table of Contents
1. [New Utility Systems](#new-utility-systems)
2. [Adding Content](#adding-content)
3. [Code Organization](#code-organization)
4. [Best Practices](#best-practices)
5. [Common Patterns](#common-patterns)

---

## New Utility Systems

### 1. Constants (`js/constants.js`)

**Purpose:** Centralized configuration for all magic numbers and hard-coded values.

**Usage:**
```javascript
// ❌ OLD WAY - Hard-coded values
health = Math.min(health + amount, 10);  // What's 10?
gold = Math.max(0, gold + 5);            // Why 5?

// ✅ NEW WAY - Named constants
health = Math.min(health + amount, GAME_BALANCE.INITIAL_MAX_HEALTH);
gold = Math.max(0, gold + delta);
```

**Available Constants:**

**Game Balance:**
```javascript
GAME_BALANCE.INITIAL_HEALTH          // 10
GAME_BALANCE.INITIAL_MAX_HEALTH      // 10
GAME_BALANCE.INITIAL_GOLD            // 0
GAME_BALANCE.DIFFICULTY.HIGH         // { threshold: 10, damage: 3, rollBonus: 4 }
GAME_BALANCE.ENCOUNTER_RATES.COMBAT  // 0.75 (75% chance)
GAME_BALANCE.SHOP_MIN_DISTANCE       // 4
```

**Layout & Positioning:**
```javascript
LAYOUT.NODE_SPACING        // 300 - Horizontal spacing
LAYOUT.MAX_NODES_PER_ROW   // 4 - Max choices per row
LAYOUT.CENTER_X            // 450 - Center of viewport
```

**Colors:**
```javascript
COLORS.PRIMARY             // '#cc6600'
COLORS.SUCCESS             // '#4CAF50'
COLORS.DANGER              // '#ff4444'
COLORS.STATS.STRENGTH      // '#ff4444'
COLORS.ARROWS.ACTIVE       // '#ffdd00'
```

**Storage Keys:**
```javascript
STORAGE_KEYS.GAME_STATE    // 'roguelikeState'
STORAGE_KEYS.SAVED_GAMES   // 'roguelikeGameSaves'
```

**To modify game balance:** Just edit `js/constants.js` instead of hunting through multiple files!

---

### 2. Storage Utility (`js/storage.js`)

**Purpose:** Safe localStorage operations with error handling.

**Old Way (Error-Prone):**
```javascript
// ❌ Can throw errors, no error handling
localStorage.setItem('key', JSON.stringify(data));
const loaded = JSON.parse(localStorage.getItem('key'));
```

**New Way (Safe):**
```javascript
// ✅ Returns success status, handles errors gracefully
const result = GameStorage.save(STORAGE_KEYS.GAME_STATE, gameState);
if (!result.success) {
  console.error('Save failed:', result.error);
  alert(result.error);  // User-friendly error
}

// ✅ Returns default value on error, never throws
const savedState = GameStorage.load(STORAGE_KEYS.GAME_STATE, null);
```

**API:**
```javascript
GameStorage.save(key, data)              // Returns { success, error? }
GameStorage.load(key, defaultValue)      // Returns data or default
GameStorage.remove(key)                  // Returns boolean
GameStorage.clear()                      // Returns boolean
GameStorage.has(key)                     // Returns boolean
GameStorage.getSize()                    // Returns bytes
GameStorage.getSizeFormatted()           // Returns "2.5 KB"
```

---

### 3. State Mutator (`js/state-mutator.js`)

**Purpose:** Centralized state updates with automatic UI synchronization.

**Old Way (Scattered, Inconsistent):**
```javascript
// ❌ Repeated 99+ times across codebase
health += 5;
gameState.health = health;
updateTopBar();
updateHealthDisplay();
updateGameStats();
createNotification('+5 Health', '#4CAF50', '💚');
```

**New Way (Centralized, Consistent):**
```javascript
// ✅ One line, handles everything
StateMutator.modifyHealth(5, { notify: true });
```

**API:**

**Health:**
```javascript
StateMutator.modifyHealth(delta, options)
// Options: { updateUI: true, notify: false, notifyMessage: null }
// Returns: { oldHealth, newHealth, changed }

StateMutator.modifyMaxHealth(delta, options)
// Same options and return value
```

**Gold:**
```javascript
StateMutator.modifyGold(delta, options)
// Returns: { oldGold, newGold, changed }
```

**Stats:**
```javascript
StateMutator.modifyStat('strength', delta, options)
// Valid stats: 'strength', 'dexterity', 'intelligence', 'charisma', 'luck'
// Returns: { oldValue, newValue, changed }
```

**Abilities:**
```javascript
StateMutator.modifyAbility('skip', delta, options)
// Valid abilities: 'skip', 'reroll', 'dash'
// Returns: { oldValue, newValue, changed }
```

**Inventory:**
```javascript
StateMutator.addItem(itemName, options)
StateMutator.removeItem(indexOrName, options)
// Returns: boolean (success)
```

**Curses:**
```javascript
StateMutator.addCurse(curseName, options)
StateMutator.removeCurse(curseName, options)
// Returns: boolean (success)
```

**Example:**
```javascript
// Before: 6 lines
health += 10;
gameState.health = health;
updateTopBar();
updateHealthDisplay();
updateGameStats();
createNotification('+10 Health', '#4CAF50', '💚');

// After: 1 line
StateMutator.modifyHealth(10, { notify: true });
```

---

## Adding Content

### Adding a New Item

**1. Add item data to `items-data.js`:**
```javascript
{
  name: "Ring of Power",
  rarity: "epic",
  type: "Passive",
  description: "Increases all stats by 1",
  image: "images/items/ring-of-power.png"
}
```

**2. Add item effect to `js/items.js` ITEM_EFFECTS:**
```javascript
"Ring of Power": {
  onAcquire: () => {
    StateMutator.modifyStat('strength', 1, { notify: true });
    StateMutator.modifyStat('dexterity', 1, { notify: true });
    StateMutator.modifyStat('intelligence', 1, { notify: true });
    StateMutator.modifyStat('charisma', 1, { notify: true });
    StateMutator.modifyStat('luck', 1, { notify: true });
  }
}
```

**For triggered items (e.g., "on enemy defeated"):**
```javascript
"Charm of the Vampire": {
  onAcquire: () => {
    // Runs once when acquired
  },
  onEnemyDefeated: () => {
    // Runs after every combat victory
    const chance = 0.50 + (luck * 0.05);
    if (Math.random() < chance) {
      StateMutator.modifyHealth(1, { notify: true });
    }
  }
}
```

**For usable items:**
```javascript
"Healing Potion": {
  canUse: () => {
    // Return true if item can be used right now
    return health < maxHealth;
  },
  onUse: () => {
    // What happens when used
    StateMutator.modifyHealth(5, { notify: true });
  }
}
```

---

### Adding a New Enemy

**1. Add enemy data to `enemies-data.js`:**
```javascript
{
  name: "Shadow Demon",
  difficulty: "High",
  successReward: "15 Gold",
  failureReward: "",
  image: "images/enemies/shadow-demon.png",
  description: "A creature of pure darkness"
}
```

**2. That's it!** The combat system automatically handles:
- Difficulty-based damage (uses `GAME_BALANCE.DIFFICULTY`)
- Reward parsing (extracts gold amounts)
- Image display
- Combat rolls

**No additional code needed!**

---

### Adding a New Event

**1. Add event data to `events-data.js`:**
```javascript
{
  name: "Mysterious Merchant",
  description: "A hooded figure offers you a deal...",
  options: [
    {
      text: "Trade 10 gold for a random item",
      emoji: "💰"
    },
    {
      text: "Trade 5 health for 20 gold",
      emoji: "💔"
    },
    {
      text: "Decline and leave",
      emoji: "🚶"
    }
  ]
}
```

**2. Add event handler to `js/main.js` (in `handleEventOption` function):**
```javascript
if (event.name === "Mysterious Merchant") {
  handleMysteriousMerchant(optionIndex);
}

// Then create handler function:
function handleMysteriousMerchant(optionIndex) {
  if (optionIndex === 0) {
    // Option 1: Trade gold for item
    if (gold >= 10) {
      StateMutator.modifyGold(-10);
      giveRandomItem();
    } else {
      alert('Not enough gold!');
      return;
    }
  } else if (optionIndex === 1) {
    // Option 2: Trade health for gold
    StateMutator.modifyHealth(-5);
    StateMutator.modifyGold(20, { notify: true });
  }

  closeGameModal();
  proceedAfterEvent();
}
```

---

### Adding a New Game

**1. Add to games-data.js:**
```javascript
{
  name: "My New Roguelike",
  year: 2024,
  type: "Action",
  connected: true,
  influenced: true,
  tags: ["Pixel Art", "Procedural"],
  gamesInfluenced: ["Other Game 1", "Other Game 2"],
  coverImage: "images/covers/my-new-roguelike.jpg"
}
```

**2. Make sure it's alphabetically sorted!**

**3. Add cover image:**
- Filename format: lowercase, hyphens, no apostrophes
- Example: "Don't Starve" → `dont-starve.jpg`
- Place in `images/covers/`

---

## Code Organization

### File Structure

```
/
├── index.html                 # Main HTML
├── DEVELOPER_GUIDE.md         # This file
├── README.md                  # User-facing docs
│
├── js/
│   ├── constants.js          # ⭐ NEW: All magic numbers
│   ├── storage.js            # ⭐ NEW: Safe localStorage
│   ├── state-mutator.js      # ⭐ NEW: State management
│   ├── data.js               # Global variables & initial state
│   ├── gameplay.js           # Game loop, node system, BFS
│   ├── main.js               # Modals, events, combat
│   ├── items.js              # Item effects system
│   ├── combat.js             # Combat logic
│   ├── events.js             # Event detection
│   ├── ui.js                 # UI updates, inventory
│   └── map.js                # Map modal rendering
│
├── *-data.js                  # Data files
│   ├── characters-data.js
│   ├── games-data.js
│   ├── items-data.js
│   ├── enemies-data.js
│   ├── events-data.js
│   └── curses-data.js
│
├── css/
│   └── styles.css            # All styles
│
└── images/
    ├── covers/               # Game cover images
    ├── items/                # Item images
    ├── enemies/              # Enemy images
    └── characters/           # Character portraits
```

---

## Best Practices

### DO ✅

**1. Use StateMutator for all state changes:**
```javascript
StateMutator.modifyHealth(5, { notify: true });
```

**2. Use constants instead of magic numbers:**
```javascript
if (distance >= GAME_BALANCE.SHOP_MIN_DISTANCE) {
  // Shops available
}
```

**3. Use GameStorage for localStorage:**
```javascript
GameStorage.save(STORAGE_KEYS.GAME_STATE, gameState);
```

**4. Return early to reduce nesting:**
```javascript
// ✅ Good
if (!game) return;
if (!gameState) return;
// Main logic here

// ❌ Bad
if (game) {
  if (gameState) {
    // Main logic nested
  }
}
```

**5. Add comments for complex logic:**
```javascript
// Calculate median position for Sugiyama layout algorithm
const mid = Math.floor(positions.length / 2);
```

### DON'T ❌

**1. Don't manually sync global variables:**
```javascript
// ❌ Bad
health += 5;
gameState.health = health;
updateTopBar();

// ✅ Good
StateMutator.modifyHealth(5);
```

**2. Don't use hard-coded numbers:**
```javascript
// ❌ Bad
if (gamesBeaten >= 10) { /* ... */ }

// ✅ Good
if (gamesBeaten >= GAME_BALANCE.DIFFICULTY.HIGH.threshold) { /* ... */ }
```

**3. Don't use inline styles in JavaScript:**
```javascript
// ❌ Bad
element.style.color = '#ff4444';

// ✅ Good
element.style.color = COLORS.DANGER;
```

**4. Don't ignore errors:**
```javascript
// ❌ Bad
try {
  localStorage.setItem(key, data);
} catch (e) {
  // Silent failure
}

// ✅ Good
const result = GameStorage.save(key, data);
if (!result.success) {
  alert(result.error);
}
```

---

## Common Patterns

### Modal Creation

```javascript
// Combat modal
createGameModal(`
  <div style="text-align: center;">
    <h2 style="color: ${COLORS.DANGER};">⚔️ Combat</h2>
    <img src="${enemy.image}" style="width: ${ICON_SIZES.ENEMY}px;">
    <p>${enemy.description}</p>
    <button onclick="handleCombatRoll()">Fight!</button>
  </div>
`);
```

### Teleportation

```javascript
// Teleport without triggering encounter
const x = LAYOUT.CENTER_X;
const y = gameState.currentY + LAYOUT.VERTICAL_GAP;
advance(gameName, x, y, null);  // null = no encounter
```

### Adding Item with Effect

```javascript
// Give item and trigger its onAcquire
StateMutator.addItem(itemName, { updateUI: true, notify: true });

if (ITEM_EFFECTS[itemName]?.onAcquire) {
  ITEM_EFFECTS[itemName].onAcquire();
}
```

### Damage with Curse Check

```javascript
// Apply damage with curse reduction
let damage = GAME_BALANCE.DIFFICULTY[difficulty].damage;

// Check for weakness curses
const weaknessCurses = gameState.activeCurses?.filter(c =>
  c.name.toLowerCase().includes('weakness')
);

if (weaknessCurses?.length > 0) {
  const weaknessCurse = weaknessCurses[0];
  damage -= getCurseDamage(weaknessCurse.power);
  damage = Math.max(0, damage);
  StateMutator.removeCurse(weaknessCurse.name, { notify: true });
}

StateMutator.modifyHealth(-damage, { notify: true });
```

---

## Troubleshooting

### "StateMutator is not defined"
- Make sure `js/state-mutator.js` is loaded in `index.html`
- Check browser console for script loading errors

### "COLORS is not defined"
- Make sure `js/constants.js` is loaded in `index.html`
- Ensure it loads **before** files that use it

### "GameStorage is not defined"
- Make sure `js/storage.js` is loaded in `index.html`
- Check for typos (it's `GameStorage`, not `Storage`)

### State not saving
```javascript
// Old way might fail silently
localStorage.setItem('key', data);  // ❌ No error handling

// New way shows errors
const result = GameStorage.save('key', data);
if (!result.success) {
  console.error(result.error);  // See what went wrong
}
```

---

## Performance Tips

### Batch UI Updates

```javascript
// ❌ Slow - updates UI 3 times
StateMutator.modifyHealth(5);
StateMutator.modifyGold(10);
StateMutator.modifyStat('strength', 2);

// ✅ Fast - updates UI once
StateMutator.modifyHealth(5, { updateUI: false });
StateMutator.modifyGold(10, { updateUI: false });
StateMutator.modifyStat('strength', 2, { updateUI: true });
```

### Use Event Delegation

```javascript
// ❌ Bad - creates listeners for each item
items.forEach(item => {
  item.addEventListener('click', handleClick);
});

// ✅ Good - single listener on parent
container.addEventListener('click', (e) => {
  const item = e.target.closest('.item');
  if (item) handleClick(item);
});
```

---

## Migration Guide

### Migrating Existing Code to Use Utilities

**Step 1: Replace localStorage calls**
```javascript
// Find all: localStorage.setItem
// Replace with: GameStorage.save

// Find all: localStorage.getItem
// Replace with: GameStorage.load
```

**Step 2: Replace state mutations**
```javascript
// Find pattern:
health += value;
gameState.health = health;
updateTopBar();

// Replace with:
StateMutator.modifyHealth(value);
```

**Step 3: Replace magic numbers**
```javascript
// Find: hard-coded numbers
// Check if constant exists in constants.js
// If not, add it, then use constant
```

---

## Future Improvements

Areas identified for potential future refactoring:

1. **Modal System** - Create reusable modal components
2. **Event System** - Move event handlers to event-data.js as callbacks
3. **Arrow Rendering** - Unify CSS and SVG arrow systems
4. **Tooltip System** - Consolidate 3 separate tooltip implementations
5. **TypeScript** - Add type safety for better developer experience

---

## Questions?

For questions or issues:
1. Check this guide
2. Check browser console for errors
3. Review `/js/constants.js`, `/js/storage.js`, `/js/state-mutator.js` for available APIs
4. Look at existing code for patterns

Remember: **Constants for config, Storage for saves, StateMutator for state!**
