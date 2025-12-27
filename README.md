# Roguelike Game Documentation

## Table of Contents
- [Overview](#overview)
- [Recent Updates](#recent-updates)
- [Curse System](#curse-system)
- [Items System](#items-system)
- [Game Status Effects](#game-status-effects)
- [Events System](#events-system)
- [Combat System](#combat-system)
- [Teleport System](#teleport-system)
- [Developer Tools](#developer-tools)
- [Code Optimization](#code-optimization)
- [Creating New Content](#creating-new-content)
- [Common Issues](#common-issues)

---

## Overview

A roguelike game where players navigate through a graph of connected video games, encountering combat, events, and shops. The game features a comprehensive curse system, item effects, and dynamic gameplay mechanics.

**Key Features:**
- D20-based combat and event resolution
- 11 unique curse types across 3 categories (Restriction, Manual, Automatic)
- Player-verified curse tracking system with combined verification modal
- Extensive item system (passive, usable, and triggered)
- Game status effects (portals, stinky games)
- Escape sequence after finding the amulet
- Save/load system with multiple save slots
- Comprehensive developer tools
- Dynamic difficulty scaling based on progress

---

## Recent Updates

### Version 3.0 - Manual & Restriction Curses (December 2024)

**New Curse Categories:**
- **Restriction Curses** (Purple): Must implement specific restrictions (Blindness, Hubris)
- **Manual Curses** (Orange): Player-verified actions (Devotion, Greed, Impulse, Haste)
- **Automatic Curses** (Red): Original automatic curses (Failure, Weakness, Vulnerability, Shroud, Frugality)

**Curse Verification System:**
- Combined verification modal after beating each game
- Conditional tracking for restriction curses (only count if possible to implement)
- Player-reported tracking for manual curses (resets, skips, time limits, etc.)
- Unique curse ID system for independent tracking of duplicate curses

**New Manual Curses:**
- **Devotion**: Lose HP for each run reset
- **Greed**: Lose HP for skipping items/upgrades in-game
- **Impulse**: Lose HP for not choosing topmost/leftmost options
- **Haste**: Lose HP if game not beaten within time limit

**New Restriction Curses:**
- **Blindness**: Must randomly choose character/loadout (highest tier ticks first)
- **Hubris**: Must raise difficulty (tracked separately by tier)

**Difficulty Scaling:**
- Difficulty now based on games beaten (not distance traveled)
- Low (0-4 games), Medium (5-9 games), High (10+ games)

**UI Improvements:**
- Game hover tooltips use horizontal space for long connection lists
- Tooltips respect top bar boundaries (no more clipping)
- Three-category curse display with color-coding
- Higher tier curses displayed above lower tiers within same category

**Bug Fixes:**
- Fixed curse tracking not incrementing after first game
- Fixed Blindness curses incrementing multiple times per game
- Fixed curse progress display showing 0/X instead of updating
- Fixed curses taking extra turn to expire when added mid-game

### Version 2.0 - Curse System & Optimization (December 2024)

**New Curse System:**
- **5 Curse Types**: Failure, Weakness, Vulnerability, Shroud, and Frugality
- **Stacking Mechanics**: Multiple instances of the same curse stack for increased effect
- **Power Levels**: Each curse has Low/Medium/High power affecting intensity
- **Visual Indicators**: Curses display in both game panel and dev tools
- **Critical Failure**: Curse of Failure now auto-loses combat on natural 1

**Code Optimizations:**
- ~360+ lines of code removed across 4 major files
- Added helper functions to eliminate duplication
- Modern JavaScript patterns (optional chaining, nullish coalescing, reduce)
- Fisher-Yates shuffle algorithm for better randomization
- Improved maintainability and performance

**Bug Fixes:**
- Fixed UI not clearing items/curses when returning to menu after death
- SVG arrows now properly visible on game paths
- Curse displays properly sync between game panel and dev tools

---

## Curse System

### Overview

Curses are negative status effects that persist across encounters and modify gameplay. They are gained by failing combat or through specific items, and are consumed when triggered.

### Curse Types

#### 1. **Curse of Failure** 😱
- **Trigger**: Rolling a natural 1 (d20 = 1) in combat
- **Effect**:
  - Deals damage based on power level (Low: 2 HP, Medium: 3 HP, High: 4 HP)
  - **CRITICAL FAILURE**: Auto-loses combat regardless of total roll
  - Shows dramatic popup notification
  - All Failure curses trigger simultaneously and stack damage
- **Removal**: Consumed when triggered (all instances removed at once)
- **Stack Behavior**: Multiple Failure curses deal combined damage

**Example**: Rolling a 1 with 2 Medium Failure curses → Take 6 damage + auto-lose combat

---

#### 2. **Curse of Weakness** 💪
- **Trigger**: Any combat roll (main combat or dev tools)
- **Effect**:
  - Subtracts from combat roll (Low: -2, Medium: -3, High: -4)
  - Shows as "- Weakness Penalty: X" in combat results
  - Only ONE Weakness curse consumed per combat
- **Removal**: Consumed on first combat roll
- **Stack Behavior**: First curse is consumed, others remain for future combats

**Example**: Rolling 15 + 4 Strength - 3 Weakness = 16 total (then Weakness curse is removed)

---

#### 3. **Curse of Vulnerability** 🎯
- **Trigger**: When receiving any new curse
- **Effect**:
  - Duplicates the incoming curse
  - Limited uses based on power (Low: 1, Medium: 2, High: 3)
  - Automatically removed when uses exhausted
- **Removal**: After triggering set number of times
- **Stack Behavior**: Multiple Vulnerability curses can each duplicate incoming curses

**Example**: Gaining a Failure curse with active Medium Vulnerability → Receive 2 Failure curses instead

---

#### 4. **Curse of Shroud** 🌫️
- **Trigger**: During game choice spawning
- **Effect**:
  - Hides one game choice from the player
  - Always leaves at least one choice visible
  - Limited uses based on power (Low: 1, Medium: 2, High: 3)
  - Automatically removed when uses exhausted
- **Removal**: Consumed each time choices are spawned
- **Stack Behavior**: Multiple Shroud curses can hide multiple choices

**Example**: Normal 3 choices with one Shroud curse → Only 2 choices shown

---

#### 5. **Curse of Frugality** 💰
- **Trigger**: When purchasing items in the shop
- **Effect**:
  - Increases all shop prices (Low: +5g, Medium: +10g, High: +15g)
  - Shows strikethrough of original price
  - ONE curse removed after first purchase
- **Removal**: Consumed on first shop purchase
- **Stack Behavior**: All Frugality curses add to price, but only first is consumed

**Example**: Shop with 2 Medium Frugality curses → All items cost +20g (both curses shown), first purchase removes one curse

---

#### 6. **Curse of Devotion** 🙏
- **Category**: Manual (Player-verified)
- **Trigger**: After beating a game (verification modal)
- **Effect**:
  - Player reports how many times they reset the run
  - Deals damage per reset (Low: 1 HP, Medium: 2 HP, High: 3 HP)
  - Lasts for 2 games beaten
- **Removal**: After completing duration requirement
- **Stack Behavior**: Multiple Devotion curses combine damage

**Example**: With Devotion II, resetting 3 times and beating the game → Take 6 damage (3 resets × 2 HP)

---

#### 7. **Curse of Greed** 💎
- **Category**: Manual (Player-verified)
- **Trigger**: After beating a game (verification modal)
- **Effect**:
  - Player reports how many items/upgrades they skipped in-game
  - Deals damage per skip (Low: 1 HP, Medium: 2 HP, High: 3 HP)
  - Lasts for 2 games beaten
- **Removal**: After completing duration requirement
- **Stack Behavior**: Multiple Greed curses combine damage

---

#### 8. **Curse of Impulse** ⚡
- **Category**: Manual (Player-verified)
- **Trigger**: After beating a game (verification modal)
- **Effect**:
  - Player reports how many times they didn't pick topmost/leftmost option
  - Deals damage per bad pick (Low: 1 HP, Medium: 2 HP, High: 3 HP)
  - Lasts for 1 game beaten
- **Removal**: After completing duration requirement
- **Stack Behavior**: Multiple Impulse curses combine damage

---

#### 9. **Curse of Haste** ⏱️
- **Category**: Manual (Player-verified)
- **Trigger**: After beating a game (verification modal)
- **Effect**:
  - Player confirms if they beat the game within time limit
  - Time limits: 4 hours (Low), 3 hours (Medium), 2 hours (High)
  - Deals 2 HP damage if time limit exceeded
  - Lasts for 1 game beaten
- **Removal**: After completing duration requirement
- **Stack Behavior**: Multiple Haste curses combine damage

---

#### 10. **Curse of Blindness** 🎲
- **Category**: Restriction (Conditional tracking)
- **Trigger**: After beating a game (verification modal)
- **Effect**:
  - Must randomly choose character/loadout at game start
  - Player confirms "Yes, did it" or "No/Not possible"
  - Only ticks down if implemented
  - Lasts for 1/2/3 games (Low/Medium/High)
- **Removal**: After completing duration requirement
- **Special**: When multiple Blindness curses exist, only highest tier increments at a time

**Example**: Blindness I (1 game) + Blindness III (3 games) → Blindness III ticks to 3/3 first, then Blindness I ticks to 1/1

---

#### 11. **Curse of Hubris** 💪
- **Category**: Restriction (Conditional tracking)
- **Trigger**: After beating a game (verification modal)
- **Effect**:
  - Must raise difficulty once/twice/thrice (Low/Medium/High)
  - Player confirms "Yes, did it" or "No/Not possible"
  - Only ticks down if implemented
  - Lasts for 1 game beaten
- **Removal**: After completing duration requirement
- **Special**: Different tiers tracked separately (can answer differently for each tier)

**Example**: Can say "Yes" for Hubris I (raised once) but "No" for Hubris III (couldn't raise thrice) in same game

---

### Curse Verification Modal

After beating each game, a combined verification modal appears showing all active manual and restriction curses:

**Restriction Curses (Purple):**
- "Did you implement [restriction]?"
- Options: "Yes, did it" or "No/Not possible"
- Only increments if player confirms "Yes"

**Manual Curses (Orange):**
- Input fields for player-reported values (resets, skips, etc.)
- Always increments regardless of value
- Damage calculated based on reported numbers

**Order of Display:**
- Restriction curses first (Blindness, Hubris by tier)
- Manual curses second (Devotion, Greed, Impulse, Haste)
- Within each category, higher tiers displayed above lower tiers

---

### Curse UI Display

**Game Panel (Right Sidebar):**
- Shows active curses with name, stat, and power
- Updates in real-time when curses are added/removed
- Displays in format: "Curse Name (Stat-Power)"

**Dev Tools:**
- Separate "Active Curses" panel showing all curses
- Add/remove curses for testing
- Real-time synchronization with game panel

**Combat Screen:**
- Weakness penalty shown as "- Weakness Penalty: X"
- Failure triggers show "CRITICAL FAILURE" in red
- Curse messages displayed after roll results

---

### Curse Power Levels

#### Automatic Curses

| Power  | Failure | Weakness | Vulnerability | Shroud | Frugality |
|--------|---------|----------|---------------|--------|-----------|
| Low    | 2 HP    | -2 roll  | 1 use         | 1 use  | +5 gold   |
| Medium | 3 HP    | -3 roll  | 2 uses        | 2 uses | +10 gold  |
| High   | 4 HP    | -4 roll  | 3 uses        | 3 uses | +15 gold  |

#### Manual Curses

| Power  | Devotion (per reset) | Greed (per skip) | Impulse (per bad pick) | Haste (time limit) |
|--------|---------------------|------------------|------------------------|-------------------|
| Low    | 1 HP, 2 games       | 1 HP, 2 games    | 1 HP, 1 game          | 4 hours, 2 HP     |
| Medium | 2 HP, 2 games       | 2 HP, 2 games    | 2 HP, 1 game          | 3 hours, 2 HP     |
| High   | 3 HP, 2 games       | 3 HP, 2 games    | 3 HP, 1 game          | 2 hours, 2 HP     |

#### Restriction Curses

| Power  | Blindness (duration) | Hubris (difficulty raises) |
|--------|---------------------|---------------------------|
| Low    | 1 game              | 1 raise, 1 game           |
| Medium | 2 games             | 2 raises, 1 game          |
| High   | 3 games             | 3 raises, 1 game          |

---

### Curse Management

**Gaining Curses:**
- Fail combat encounters (curse matches enemy stat)
- Use the Cursed Goblet item (+1 random curse)
- Dev tools for testing

**Removing Curses:**
- Use the Lucky Toe item (consume for +1 luck)
- Curses self-remove when triggered/consumed
- Dev tools "Clear All Curses" button

**Stack Behavior:**
- Same curse type can stack multiple times
- Each instance tracks its own power level
- Removal behavior varies by curse type (see individual descriptions)

---

## Items System

### Item Structure

All items are defined in the `items` array in `games-data.js` with the following structure:

```javascript
{
  name: "Item Name",
  rarity: "common" | "uncommon" | "rare",
  type: "Passive" | "Usable" | "Triggered",
  description: "What the item does"
}
```

### Item Types

- **Passive**: Items that apply effects when acquired and remain in inventory
- **Usable**: Items that can be activated during specific game phases
- **Triggered**: Items that activate automatically when specific conditions are met (e.g., defeating an enemy)

### Creating Item Effects

Item effects are defined in `js/items.js` in the `ITEM_EFFECTS` object:

```javascript
const ITEM_EFFECTS = {
  "Item Name": {
    // For passive items - runs once when acquired
    onAcquire: () => {
      updateStat('strength', 2); // Uses helper function
    },

    // For usable items - check if item can be used
    canUse: () => {
      return gameState.phase === 'selection';
    },

    // For usable items - runs when player uses the item
    onUse: () => {
      teleportToRandomGame();
    },

    // For usable items - number of times item can be used (default: 1)
    uses: 2,

    // For triggered items - runs when player defeats an enemy
    onEnemyDefeated: () => {
      health = Math.min(health + 1, maxHealth);
      gameState.health = health;
    }
  }
}
```

### Helper Functions

**Modern item system includes:**

```javascript
// Update a stat and sync with gameState
updateStat('strength', 2);  // Adds 2 strength

// Display notification popup
createNotification('Found treasure!', '#4CAF50', '✨');

// Determine random encounter type (75% combat, 15% event, 10% shop)
const encounterType = determineEncounterType();
```

### Available Stats

- `strength` - Combat stat
- `dexterity` - Combat stat
- `intelligence` - Combat stat
- `charisma` - Combat stat
- `health` - Current health (0 = death)
- `maxHealth` - Maximum health
- `gold` - Currency
- `dash` - Number of extra movement options
- `fov` - Field of view (number of game choices shown)
- `luck` - Affects shop prices and rewards
- `reroll` - Number of item reroll charges
- `skip` - Number of skip charges
- `discovery` - Number of discovery charges (extra item choices)

### Game Phases

Items can check `gameState.phase` to determine usability:
- `'selection'` - Player is choosing which game to visit
- `'combat'` - Player is in combat
- `'event'` - Player is in an event
- `'shop'` - Player is in the shop
- `'escape'` - Player is in the escape sequence (has amulet)

---

## Game Status Effects

### Overview

Game status effects are persistent markers that can be applied to games. Status icons appear on game nodes (current, past, and choice nodes) and modify how games behave in selections.

### Status Effect Functions

```javascript
// Add a status effect to a game
addGameStatus(gameName, statusName, icon)

// Remove a status effect from a game
removeGameStatus(gameName, statusName)

// Check if a game has a specific status
hasGameStatus(gameName, statusName)

// Get all statuses for a game
getGameStatuses(gameName)

// Get all games with a specific status
getGamesWithStatus(statusName)
```

### Built-in Status Effects

**The Poop (Stinky) 💩**
- Effect: Game is deprioritized in selections (appears last)
- Applied via: The Poop item
- Visual: 💩 icon on game node

**Ventricle Razor (Portal) 🌀**
- Effect: Creates instant connections between portal-marked games
- Applied via: Ventricle Razor item (max 2 portals)
- Visual: 🌀 icon on game node
- When standing on a portal, all other portals appear as choices

---

## Events System

Events are defined in `events-data.js` and follow this structure:

```javascript
{
  name: "Event Name",
  power: "Low" | "Medium" | "High",
  description: "Event description",
  stat: "Strength" | "Dexterity" | "Intelligence" | "Charisma",
  rollCheck: 10,  // DC (Difficulty Check) for the roll
  successReward: "10 gold",  // or "common item", "uncommon item", "rare item"
  failureConsequence: "Lose 1 health"
}
```

### Event Difficulty

Event difficulty determines the DC (roll check needed):
- **Low**: DC 8-12 (easier checks)
- **Medium**: DC 13-16 (moderate checks)
- **High**: DC 17-20 (harder checks)

---

## Combat System

### Combat Flow

1. Enemy appears with stat check requirement (Strength/Dex/Int/Cha)
2. Player rolls 1d20 + relevant stat modifier
3. **Curse of Weakness** applies penalty if active
4. **Curse of Failure** triggers on natural 1 (auto-lose + damage)
5. Compare total to enemy's DC (rollCheck)
6. If success: Player gets reward
7. If failure: Player takes damage based on difficulty

### Combat Damage

Combat damage is determined by enemy power level:
- **Low**: 1 damage on failure
- **Medium**: 2 damage on failure
- **High**: 3 damage on failure

### Critical Failure

Rolling a natural 1 (d20 = 1) with active Curse of Failure:
- Shows "⚠️ CRITICAL FAILURE" message
- Combat is automatically lost (regardless of total roll)
- All Failure curses trigger for combined damage
- All Failure curses are removed after triggering

---

## Teleport System

### Random Teleport by Type

```javascript
teleportToRandomGameOfType(gameType)
```

**Parameters**:
- `gameType` (string|null): Filter by game type, or `null` for any game

**Behavior**:
- Only teleports to games with `connected: true`
- Generates random encounter type via `determineEncounterType()`
- Shows error if no matching games found

### Selected Teleport (Player Choice)

```javascript
selectedTeleport({
  numChoices: 3,
  year: 2020,
  type: 'Deckbuilding',
  tags: ['roguelike'],
  title: "Choose Your Destination"
})
```

All parameters are optional except for defining at least one filter.

---

## Developer Tools

The game includes comprehensive dev tools at the bottom of the page:

### Items Dev Tools (📦)
- Add specific or random items
- Remove items from inventory
- View current inventory

### Curses Dev Tools (😈)
- Add specific curses (by type, stat, power)
- Add random curses
- Remove individual or all curses
- View active curses with full details

### Encounters Dev Tools (⚔️)
- Trigger combat (specific stat/power)
- Trigger random events
- Quick actions: Shop, Item Choice
- View encounter history

### Usage Tips
- Dev tools require an active run for most features
- Changes affect active game state
- Use for testing balance and edge cases
- Curse testing helps verify UI synchronization

---

## Code Optimization

### Recent Performance Improvements

**Helper Functions Added:**
- `getCursesByType()` - Unified curse filtering
- `getPowerValue()` - Centralized power level conversions
- `getPlayerStat()` - Simplified stat lookups
- `updateCurseUI()` - Consolidated display updates
- `createNotification()` - Reusable notification system
- `determineEncounterType()` - Standard encounter generation
- `shuffleArray()` - Fisher-Yates shuffle (better randomization)

**Code Reduction:**
- ~360 lines removed across 4 files
- Eliminated duplicate notification blocks (4 instances)
- Consolidated curse filtering (6 instances)
- Removed deprecated functions (110+ lines)

**Modern JavaScript Patterns:**
- Optional chaining (`?.`) for safer null checks
- Nullish coalescing (`??`) for better defaults
- Array methods (reduce, filter, map) over forEach
- Template literals for cleaner string building

**Algorithm Improvements:**
- Fisher-Yates shuffle replaces biased `.sort()` method
- Better randomization distribution
- Improved status icon management

---

## Creating New Content

### Adding a New Curse-Related Item

```javascript
// In games-data.js
{
  name: "Cursed Goblet",
  rarity: "rare",
  type: "Usable",
  description: "Gain a random curse for power"
}

// In js/items.js
"Cursed Goblet": {
  canUse: () => true,
  onUse: () => {
    // Get random curse type
    const curseTypes = ['failure', 'weakness', 'vulnerability', 'shroud', 'frugality'];
    const randomType = curseTypes[Math.floor(Math.random() * curseTypes.length)];

    // Find matching curse template
    const matchingCurses = curses.filter(c =>
      c.name.toLowerCase().includes(randomType)
    );

    if (matchingCurses.length > 0) {
      const curse = matchingCurses[Math.floor(Math.random() * matchingCurses.length)];
      addCurse(curse);
    }
  }
}
```

### Adding a New Passive Item

```javascript
// In games-data.js
{
  name: "Ring of Power",
  rarity: "rare",
  type: "Passive",
  description: "+3 Strength, +3 Intelligence"
}

// In js/items.js
"Ring of Power": {
  onAcquire: () => {
    updateStat('strength', 3);
    updateStat('intelligence', 3);
  }
}
```

---

## Common Issues

### Curse UI Not Syncing
- Ensure `updateCurseUI()` is called after curse changes
- Check that both `updateCursesDisplay` and `updateActiveCursesList` are exported
- Verify gameState.activeCurses exists

### Item Effects Not Working
- Check that item name in `ITEM_EFFECTS` exactly matches name in `items` array
- Use `updateStat()` helper for stat modifications
- Call appropriate update functions after changes

### Combat Critical Failure Not Triggering
- Verify Curse of Failure is in active curses
- Check that d20 roll = 1 (not total roll)
- Ensure `getCursesByType('failure')` returns curses

### Teleport Not Working
- Verify target games have `connected: true`
- Check filter criteria aren't too restrictive
- Ensure `gameState.phase === 'selection'` for usable items

---

## Tips and Best Practices

### Curse Balance
- Failure: High risk, high impact (can end runs)
- Weakness: Consistent penalty, stackable
- Vulnerability: Exponential growth if not managed
- Shroud: Reduces player agency (annoying but not deadly)
- Frugality: Economic pressure (delays progress)

### Item Balance
- Common items: +1 to single stat or small effect
- Uncommon items: +2 to single stat or moderate effect
- Rare items: +3 to stat, multiple effects, or powerful abilities
- Items with tradeoffs: +3 to one stat, -1 to another

### Testing with Dev Tools
```javascript
// Test curse stacking
addCurse(getCurseByName("Curse of Failure (Strength-Medium)"))
addCurse(getCurseByName("Curse of Failure (Strength-High)"))

// Test critical failure
// Set health high, add failures, trigger combat with Strength stat

// Test Vulnerability cascade
addCurse(getCurseByName("Curse of Vulnerability (Any-High)"))
// Then fail a combat to see duplication
```

---

**For more information, check the inline code documentation in `/js/` files.**
