# Roguelike Game Documentation

## Table of Contents
- [Overview](#overview)
- [Recent Updates](#recent-updates)
- [Collection System](#collection-system)
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

**Architecture:**
The codebase is organized into focused, maintainable modules. See [js/README.md](js/README.md) for detailed module documentation.
- **15 JavaScript modules** with clear responsibilities
- **main.js reduced by 41.5%** (6,757 → 3,950 lines)
- **6 new modules extracted** (Jan 2025): modals, shop, character-select, verification, escape, bingo
- **Better maintainability** for both humans and LLMs

---

## Recent Updates

### Version 5.0 - Weapon System & Combat Enhancements (January 2026)

**Weapon System:**
- **Weapon Bonuses**: Weapons can now accumulate stat bonuses through verification triggers
- **Per-Weapon Stats**: Each weapon tracks its own level and bonuses independently
- **Weapon Leveling**: Weapons level up (1-3) through combining duplicates or shop upgrades
  - Level 1 → 2: 10 gold or combine duplicate
  - Level 2 → 3: 20 gold or combine duplicate
- **Weapon Swapping**: Bonuses stored on weapons persist when equipping/unequipping
- **Verification Rewards**: Weapons grant bonuses based on current level (not cumulative)

**New Item Types:**
- **Scaling Items**: Items that dynamically calculate bonuses (cannot be upgraded like Passives)
  - Example: Beefy Ring - grants +1 Attack per 10 max health

**Combat Enhancements:**
- **Block Mechanic**: Block absorbs damage before health
  - Block granted by items like Calipers
  - Block does NOT persist between turns
- **Combat Tooltips**: Fixed hovering tooltips for items in combat
  - Tooltips moved to document.body to avoid z-index stacking issues
  - Unique IDs prevent conflicts with inventory tooltips
- **Combat Turn Tracking**: Turn-based effects now properly trigger on specific turns

**Passive Item System:**
- **Upgrade/Downgrade System**: All Passive items can be upgraded/downgraded
  - Supported stats: strength, dexterity, intelligence, charisma, dash, reroll, skip, discovery, fov, luck, maxHealth, block
  - Items split when upgraded/downgraded if quantity > 1
  - Modifiers displayed in item tooltips
- **Stat Modifiers**: Each passive tracks individual stat changes
- **Block Support**: Passive items can now modify block values

**New Weapons (7 total):**
1. **Lil' Bomber** (Common): Gains (+1/+2/+3) Strength per level when killing with bombs
2. **Slutty Rocket** (Uncommon): Gains (+1/+2/+3) Attack per level when killing with fire
3. **Blood Magic** (Rare): Permanently grants (+1/+2/+3) max health when killing at full health
4. **Dexecutioner** (Uncommon): Gains (+1/+2/+3) Dexterity per level when killing with piercing attacks
5. **Barrel** (Uncommon): Grants (1/2/3) random fish per level when obtaining fish
6. **Blasma Pistol** (Common): Grants (small/normal/large) chest per level when opening 10+ chests

**New Passive Items:**
1. **Beefy Ring** (Rare, Scaling): Gain +1 Attack per 10 max health
2. **Focus Crystal** (Common): Gain +1 Attack if melee weapon equipped
3. **Calipers** (Rare): On turn 2 of combat, gain +5 Block (upgradeable/downgradeable)

**New Active Items:**
1. **Fire Potion** (Uncommon): Deal 10 damage to enemy in combat (single use)

**Weapon Tooltip Enhancements:**
- **Accumulated Bonuses Display**: Tooltips show all non-zero weapon bonuses
  - Format: "Accumulated Bonuses: +7 Strength • +3 Attack"
  - Green styling distinguishes bonuses from description
- **Level Display**: Weapon level shown in tooltip and equipment slot
- **Works for All Locations**: Inventory, equipment slot, and combat tooltips

**Technical Improvements:**
- **Scalable Passive System**: `recalculateScalablePassives()` dynamically calculates bonuses
- **Weapon Bonus System**: `getWeaponBonuses()` retrieves weapon-stored bonuses
- **Total Bonus Calculation**: `getTotalBonuses()` combines all bonus sources
- **Effective Stats**: `getEffectiveStat()` returns base stat + all bonuses
- **Combat State Integration**: Combat system uses effective stats including weapon bonuses

**UI/UX Improvements:**
- Fixed combat item tooltips appearing behind modal
- Items bar moved to top of combat area
- Weapon level badge displayed in equipment slot (orange, top-right)
- Combat tooltips use unique IDs to prevent cleanup conflicts
- Block display in combat UI

### Version 4.0 - Collection System & Visual Improvements (January 2025)

**New Collection Feature:**
- **Collection Menu Button**: New orange-gradient button on main menu
- **Three Collection Tabs**:
  - **Games Tab**: All 532 games displayed in responsive grid with cover images
  - **Items Tab**: All 22 items with local images and descriptions
  - **Enemies Tab**: All enemies with images, power levels, and stats
- **Interactive Tooltips**: Hover over games in Collection to see full game info, cover, and influence connections
- **Responsive Grid Layout**: Auto-fill columns (150px minimum) with hover effects

**Game Data Expansion:**
- **7 New Games Added**: Drill Core, Flick Shot Rogues, Granvir, House of Necrosis, Spellmasons, There Are No Orcs, Word Play
- **Total Games**: 532 (up from 525)
- **Total Connections**: 650 influence relationships (up from 645)
- **All Games Alphabetically Sorted**: Verified alphabetical order maintained

**Visual & Image Improvements:**
- **405+ Game Covers**: Game cover images properly linked to all available covers
- **Local Item Images**: All 22 items now use local images from `images/items/` (no more imgur URLs)
- **object-fit: contain**: Game covers now use `contain` instead of `cover` to handle different aspect ratios
  - Prevents cropping of manually added covers
  - Properly displays varying image sizes without distortion
- **Cover Image Handling**: Supports different image dimensions and aspect ratios gracefully

**Tooltip Enhancements:**
- **3-Column Grid Layout**: Influenced/influencer games now display in 3 columns for better horizontal space usage
- **Renamed "Influenced"**: Changed "Influences:" to "Influenced:" for better grammar
- **Reduced Font Size**: Influence games now use 10px font for more compact display
- **Game Cover Positioning**: Game cover appears next to game info at top of tooltip
- **Collection Integration**: Same tooltip system works in both map screen and Collection

**UI/UX Fixes:**
- **Arrow Cleanup**: Map arrows now properly cleared when returning to main menu
  - Prevents arrows from appearing on main menu or other screens
  - Arrows cleared on death, escape death, curse death, and manual return
- **Z-Index Corrections**: Buttons now always appear above arrows
  - Disabled buttons maintain z-index: 100 (arrows have z-index: 0)
  - Fixed issue where dotted yellow and gray arrows appeared over grayed-out buttons
  - Applied to Skip, Finished, and all ability buttons

**Technical Improvements:**
- **clearAllArrows()**: New function to remove all CSS arrows when leaving dungeon
- **PascalCase Image Paths**: Item images follow consistent naming (e.g., `BallisticBoots.png`)
- **Image Fallbacks**: Proper fallback handling for missing covers (`no-cover.svg`) and items (`no-item.svg`)
- **Cache-Busting**: Updated resource versions to v=19

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

## Collection System

### Overview

The Collection is a comprehensive catalog accessible from the main menu that displays all games, items, and enemies in the game. It provides an organized view of content with interactive tooltips and visual previews.

**Key Features:**
- Accessible via orange "Collection" button on main menu
- Three organized tabs: Games, Items, and Enemies
- Responsive grid layouts with hover effects
- Interactive game tooltips showing influence connections
- Local image support for all content types

---

### Collection Tabs

#### Games Tab

Displays all 532 games in an alphabetical grid format:

**Features:**
- **Cover Images**: Shows game cover art (or placeholder for games without covers)
- **Game Information**: Name, year, and type displayed below cover
- **Interactive Tooltips**: Hover over any game to see:
  - Full game details (year, type)
  - Game cover image
  - Games it influenced (purple, 3-column grid)
  - Games that influenced it (green, 3-column grid)
- **Hover Effects**: Cards lift and border highlights on hover
- **Grid Layout**: Responsive auto-fill (150px minimum per card)

**Visual Details:**
- Cover images use `object-fit: contain` to preserve aspect ratios
- Supports varying image sizes without distortion
- 2:3 aspect ratio for cover display
- Dark background (#1a1a1a) for image containers

**Example Game Card:**
```
┌─────────────────┐
│   [Cover Art]   │
│                 │
│   Game Name     │
│  2020 • Action  │
└─────────────────┘
```

---

#### Items Tab

Displays all 22 items with visual representations:

**Features:**
- **Item Images**: Local PNG images from `images/items/`
- **Item Details**: Name and description
- **Hover Effects**: Green border highlight (#4CAF50) on hover
- **Grid Layout**: Same responsive grid as games (150px minimum)

**Visual Details:**
- Images use `object-fit: contain` with 120px height
- Items displayed with proper transparency
- Consistent PascalCase naming (e.g., `BallisticBoots.png`)

**Example Item Card:**
```
┌─────────────────┐
│                 │
│  [Item Image]   │
│                 │
│   Item Name     │
│  Description... │
└─────────────────┘
```

---

#### Enemies Tab

Displays all enemies with stats and images:

**Features:**
- **Enemy Images**: Local images from enemy data
- **Enemy Details**: Name, power level, and stat
- **Roll Information**: Shows DC requirement for success
- **Hover Effects**: Red border highlight (#f44336) on hover
- **Grid Layout**: Same responsive grid (150px minimum)

**Visual Details:**
- Images use `object-fit: contain` with 120px height
- Power level and stat shown in red (#ff6666)
- DC displayed as "Roll X to succeed"

**Example Enemy Card:**
```
┌─────────────────┐
│                 │
│ [Enemy Image]   │
│                 │
│   Enemy Name    │
│ Medium • Strength│
│  Roll 12 to win │
└─────────────────┘
```

---

### Collection UI/UX

**Opening Collection:**
- Click orange "Collection" button on main menu
- Modal opens with Games tab selected by default
- Can switch between tabs without closing modal

**Tab Switching:**
- Click tab buttons at top of modal
- Active tab highlighted in orange (#ff9800)
- Inactive tabs shown in gray (#555)
- Content area updates immediately

**Grid Behavior:**
- Automatically adjusts columns based on screen width
- Minimum 150px per card
- Auto-fill creates responsive layout
- 15px gap between cards
- Cards maintain consistent sizing

**Closing Collection:**
- Click orange "Close" button at bottom
- Click outside modal (on dark overlay)
- Returns to main menu

---

### Collection Technical Details

**Image Paths:**

```javascript
// Games
game.coverImage = "images/covers/game-name.jpg"
// or null for placeholder

// Items
item.image = "images/items/ItemName.png"

// Enemies
enemy.imageUrl = "https://i.imgur.com/image.png"
```

**Tooltip Integration:**

The Collection uses the same `showTooltip()` function as the map screen:

```javascript
onmousemove="if (typeof showTooltip === 'function')
  showTooltip(event, 'Game Name');"
onmouseleave="if (typeof hideTooltip === 'function')
  hideTooltip();"
```

**Grid Styling:**

```css
display: grid;
grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
gap: 15px;
```

**Fallback Images:**
- Games without covers: `images/covers/no-cover.svg`
- Items without images: `images/items/no-item.svg`
- Enemies without images: `images/enemies/no-enemy.svg`

---

### Collection Functions

**Main Functions:**

```javascript
// Show collection modal
showCollection()

// Switch between tabs
switchCollectionTab('games' | 'items' | 'enemies')

// Close collection
closeGameModal()
```

**Location:**
- Collection UI: `js/main.js` (lines 3720-3883)
- Tab switching logic: `switchCollectionTab()` function
- Modal creation: `createGameModal()` function

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

### Overview

Events are special encounters that offer meaningful choices and can lead to teleportation, item trading, or combat scenarios. The event system features a requirement system, multi-stage event flows, and integration with the generic combat system.

**Key Features:**
- Event requirement validation (inventory checks, etc.)
- Multi-stage events with state tracking
- Generic combat integration for event-triggered fights
- Teleportation without encounter triggers
- Player choice modals with detailed option descriptions

---

### Event Structure

Events are defined in `events-data.js` and follow this structure:

```javascript
{
  name: "Event Name",
  description: "Event description shown to player",
  options: [
    "Option 1 (Details about what happens)",
    "Option 2 (Details about what happens)",
    "Option 3 (Details about what happens)"
  ],
  requirement: {
    type: "minItems",  // Requirement type
    value: 4           // Requirement threshold
  } // or null for no requirements
}
```

### Event Requirements

Events can specify requirements that must be met before appearing:

**Supported Requirement Types:**
- `minItems`: Player must have at least X items in inventory

**Example:**
```javascript
requirement: {
  type: "minItems",
  value: 4
}
```

**Implementation:**
The `checkEventRequirement()` function validates requirements before showing events:
```javascript
function checkEventRequirement(event) {
  if (!event.requirement) return true;

  switch (event.requirement.type) {
    case 'minItems':
      return inventory.length >= event.requirement.value;
    default:
      return true;
  }
}
```

**To Add New Requirement Types:**
1. Add new case to `checkEventRequirement()` in `js/main.js`
2. Define requirement in event's `requirement` object

---

### Built-in Events

#### 1. **Primordial Teleporter** 🌀

An ancient teleporter guarded by Stone Golems that offers three distinct paths.

**Options:**
1. **Enter the teleporter** (Teleport to random Action game)
   - Immediately teleports to a random Action-type game
   - No encounter triggers on arrival
   - Quick escape option

2. **Interact with the teleporter, then enter it** (Go back 3 difficulty, teleport to starting game)
   - Reduces difficulty by removing 3 finished games from progress
   - Teleports back to your starting game
   - Useful for reducing difficulty when struggling

3. **Fight off the Stone Golems** (Fight 3 Stone Golems in a row)
   - Triggers 3 consecutive Stone Golem fights
   - Each fight uses the generic combat system
   - Success: Gain 10 gold per fight
   - Failure: Take 2 damage per fight
   - Cursed Slash properly triggers on victories

**Implementation Details:**
```javascript
handlePrimordialTeleporter(optionIndex) {
  if (optionIndex === 0) {
    // Random Action game teleport
    teleportToRandomGameOfType('Action');
  } else if (optionIndex === 1) {
    // Reduce difficulty + return to start
    gameState.finishedGames = gameState.finishedGames.slice(0, -3);
    advance(gameState.startGame.name, x, y, null);
  } else if (optionIndex === 2) {
    // 3 Stone Golem fights
    gameState.stoneGolemFightsRemaining = 3;
    triggerStoneGolemFight();
  }
}
```

---

#### 2. **A Wild Muncher Appears** 🟢

A hungry green chest that trades items for luck-based rewards.

**Requirements:**
- Requires 4+ items in inventory to appear

**Options:**
1. **Feed it four items** (Trade 4 items for 2 items based on luck)
   - Player selects 4 items from inventory
   - Receives 2 items with rarity based on luck stat
   - Higher luck = better chance at rare items

2. **Feed it two items** (Trade 2 items for 1 item based on luck)
   - Player selects 2 items from inventory
   - Receives 1 item with rarity based on luck stat
   - Lower investment, lower reward

3. **Leave it hungry**
   - No trade occurs
   - Exit event with no changes

**Item Selection:**
- Modal shows all inventory items
- Click to select/deselect items
- Confirm button activates when exact count selected
- Back button returns to event choices

**Rarity Calculation:**
```javascript
function selectRandomRarity() {
  const roll = Math.random() * 100;
  const luckBonus = luck * 2; // Each luck point = 2% bonus

  if (roll < 10 + luckBonus) return 'Legendary';
  if (roll < 25 + luckBonus) return 'Epic';
  if (roll < 50 + luckBonus) return 'Rare';
  if (roll < 75) return 'Uncommon';
  return 'Common';
}
```

**Implementation Details:**
```javascript
handleWildMuncher(optionIndex) {
  if (optionIndex === 0) {
    showItemSelectionForMuncher(4, 2); // Trade 4 for 2
  } else if (optionIndex === 1) {
    showItemSelectionForMuncher(2, 1); // Trade 2 for 1
  } else {
    closeGameModal(); // Leave hungry
  }
}
```

---

#### 3. **The Colosseum** ⚔️

A roaring arena that tests player skill through consecutive battles.

**Stage 1: Initial Encounter**
- Player is teleported to random unconnected Action game
- Must beat the game to proceed
- No encounter triggers on teleportation

**Stage 2: The Choice** (After first victory)
- **Escape the arena** (Return to original game)
  - Safe exit with guaranteed item from victory
  - Returns to game where event was triggered

- **Challenge the Champion** (Fight another action game not connected to the rest of the map)
  - Teleports to another random unconnected Action game
  - Must beat the game, then verify attempts

**Stage 3: Champion Verification** (If challenged)
- Modal asks: "Did it take you three or less attempts?"
- **Yes**: Receive 2 luck-based random items
- **No**: Lose 3 health
- Returns to original game after resolution

**State Management:**
```javascript
gameState.colosseumState = {
  stage: 'first_fight' | 'choice' | 'champion',
  returnGame: gameName // Original game to return to
}
```

**Flow Diagram:**
```
Event Trigger → First Fight → Beat Game → Item Choice →
  ↓
Show Choices Modal → Escape (return) OR Challenge Champion →
  ↓
Champion Fight → Beat Game → Item Choice → Attempts Verification →
  ↓
Rewards/Penalty → Return to Original Game
```

**Implementation Details:**
```javascript
handleColosseum(optionIndex) {
  if (!gameState.colosseumState) {
    // First encounter - start first fight
    gameState.colosseumState = {
      stage: 'first_fight',
      returnGame: gameState.currentGame
    };
    // Teleport to unconnected game
    const unconnectedGames = games.filter(g =>
      !g.connected || g.name === gameState.amuletGame?.name
    );
    advance(randomGame.name, x, y, null);
  } else if (gameState.colosseumState.stage === 'choice') {
    if (optionIndex === 0) {
      // Escape - return to original game
      advance(returnGame.name, x, y, null);
      delete gameState.colosseumState;
    } else if (optionIndex === 1) {
      // Challenge champion
      gameState.colosseumState.stage = 'champion';
      // Teleport to another unconnected game
    }
  }
}
```

---

### Generic Combat System

The event system includes a reusable combat function for event-triggered fights:

```javascript
triggerCombat(enemy, onSuccess, onFailure, powerLevel)
```

**Parameters:**
- `enemy` (object): Enemy data with name, stat, rollCheck, successReward, etc.
- `onSuccess` (function|null): Callback when player wins combat
- `onFailure` (function|null): Callback when player loses combat
- `powerLevel` (string): 'Low', 'Medium', or 'High' for damage scaling

**Features:**
- Full integration with Cursed Slash and other triggered items
- Consistent UI with regular combat encounters
- Customizable success/failure behaviors
- Automatic reward processing for gold

**Example Usage:**
```javascript
const stoneGolem = enemies.find(e => e.name === 'Stone Golem');

triggerCombat(
  stoneGolem,
  () => {
    // Custom success behavior
    createNotification('Victory!', '#4CAF50', '⚔️');
    triggerNextFight();
  },
  () => {
    // Custom failure behavior
    createNotification('Defeated...', '#ff4444', '💀');
    returnToEvent();
  },
  'Medium'
);
```

**Combat Result Handling:**
```javascript
function handleGenericCombatResult(success, powerLevel) {
  if (success) {
    // Trigger item effects (e.g., Cursed Slash healing)
    triggerOnEnemyDefeated();
    // Apply rewards
    // Call custom success callback
  } else {
    // Apply damage based on power level
    const damage = powerLevel === 'Low' ? 1 :
                   powerLevel === 'Medium' ? 2 : 3;
    health = Math.max(0, health - damage);
    // Call custom failure callback
  }
}
```

---

### Event Flow Management

**Event Modal Display:**
```javascript
showEventModal(specificEvent)
```
- Displays event choices to player
- Validates requirements before showing events
- Stores current event in `gameState.currentEvent`
- Filters available events based on requirements

**Event Choice Handling:**
```javascript
handleEventChoice(event, option)
```
- Routes to specific event handler based on event name
- Records choice in encounter history
- Calls appropriate handler function

**Multi-Stage Events:**
Events can track state across multiple game completions using `gameState`:
```javascript
// Example: Colosseum tracking
gameState.colosseumState = {
  stage: 'first_fight',
  returnGame: 'Starting Game Name'
}

// Check state in finished button handler
if (gameState.colosseumState?.stage === 'first_fight') {
  // Show item choice, then Colosseum choices
  showItemChoiceModal(() => {
    gameState.colosseumState.stage = 'choice';
    showColosseumChoices();
  });
}
```

**Teleportation Without Encounters:**
All event teleportations pass `null` as encounterType to skip combat/shop/event:
```javascript
advance(gameName, x, y, null); // null = skip encounter
```

---

### Creating New Events

**Step 1: Define Event Data**

Add event to `events-data.js`:
```javascript
{
  name: "Mysterious Merchant",
  description: "A hooded figure offers strange wares...",
  options: [
    "Buy random item (10 gold)",
    "Sell an item (5 gold)",
    "Ignore merchant"
  ],
  requirement: {
    type: "minGold",
    value: 10
  }
}
```

**Step 2: Add Requirement Validation** (if needed)

Update `checkEventRequirement()` in `js/main.js`:
```javascript
case 'minGold':
  return gold >= event.requirement.value;
```

**Step 3: Create Event Handler**

Add handler function in `js/main.js`:
```javascript
function handleMysteriousMerchant(optionIndex) {
  if (optionIndex === 0) {
    // Buy item
    if (gold >= 10) {
      gold -= 10;
      const randomItem = items[Math.floor(Math.random() * items.length)];
      acquireItem(randomItem);
      closeGameModal();
    }
  } else if (optionIndex === 1) {
    // Sell item
    showItemSelectionModal((selectedIndex) => {
      removeItem(selectedIndex);
      gold += 5;
      closeGameModal();
    });
  } else {
    // Ignore
    closeGameModal();
  }
}
```

**Step 4: Register Handler**

Add to `handleEventChoice()` in `js/main.js`:
```javascript
if (event.name === "Mysterious Merchant") {
  handleMysteriousMerchant(optionIndex);
}
```

**Step 5: Export Functions** (if needed)

Add to window exports at bottom of `js/main.js`:
```javascript
window.handleMysteriousMerchant = handleMysteriousMerchant;
```

---

### Event System Functions Reference

**Core Functions:**
```javascript
// Show event modal to player
showEventModal(specificEvent)

// Handle player's event choice
handleEventChoice(event, option)

// Check if event requirements are met
checkEventRequirement(event)

// Generic combat for events
triggerCombat(enemy, onSuccess, onFailure, powerLevel)

// Handle combat results
handleGenericCombatResult(success, powerLevel)
```

**Event-Specific Handlers:**
```javascript
// Primordial Teleporter
handlePrimordialTeleporter(optionIndex)
triggerStoneGolemFight()
handleStoneGolemResult(success)

// Wild Muncher
handleWildMuncher(optionIndex)
showItemSelectionForMuncher(itemsToFeed, itemsToReceive)
feedMuncher(indices, itemsToReceive)

// Colosseum
handleColosseum(optionIndex)
showColosseumChoices()
handleChampionResult()
completeChampionSuccess()
completeChampionFailure()
```

**Helper Functions:**
```javascript
// Remove item and reverse its stat effects
removeItemAndReverseStats(index)

// Select rarity based on luck stat
selectRandomRarity()

// Teleport without triggering encounters
advance(gameName, x, y, null)
```

---

### Event Requirements System

**Built-in Requirement Types:**

| Type | Description | Check |
|------|-------------|-------|
| `minItems` | Minimum inventory items | `inventory.length >= value` |

**Example Requirement:**
```javascript
requirement: {
  type: "minItems",
  value: 4
}
```

**Custom Requirements:**
To add new requirement types, extend `checkEventRequirement()`:

```javascript
function checkEventRequirement(event) {
  if (!event.requirement) return true;

  switch (event.requirement.type) {
    case 'minItems':
      return inventory.length >= event.requirement.value;
    case 'minGold':
      return gold >= event.requirement.value;
    case 'hasItem':
      return inventory.some(item => item.name === event.requirement.value);
    case 'minDifficulty':
      return gameState.finishedGames?.length >= event.requirement.value;
    default:
      return true;
  }
}
```

---

### Event Best Practices

**Event Design:**
- Provide meaningful choices with clear consequences
- Include parenthetical details in option text
- Consider risk/reward balance
- Test multi-stage event flows thoroughly

**State Management:**
- Use `gameState` for persistent event data
- Clean up state after event completion
- Verify state exists before accessing properties

**Teleportation:**
- Always pass `null` as encounterType for event teleports
- Track return location for multi-stage events
- Use unconnected games for special encounters

**Combat Integration:**
- Use `triggerCombat()` for consistent behavior
- Include `triggerOnEnemyDefeated()` in success handlers
- Provide custom callbacks for event-specific logic

**UI/UX:**
- Add Back buttons for item selection modals
- Show detailed consequences in option text
- Provide clear success/failure feedback
- Update progress indicators (difficulty, distance)

---

### Event Difficulty

For events that use stat checks (via generic combat):
- **Low**: DC 8-12, 1 damage on failure
- **Medium**: DC 13-16, 2 damage on failure
- **High**: DC 17-20, 3 damage on failure

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
