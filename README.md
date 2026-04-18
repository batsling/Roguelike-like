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
  - [Combat Flow](#combat-flow)
  - [Energy System](#energy-system)
  - [Card Hand](#card-hand)
  - [Card Types](#card-types)
  - [Card Rarities](#card-rarities)
  - [Card Effects Reference](#card-effects-reference)
  - [Combat Statuses](#combat-statuses)
  - [Enemy Intents](#enemy-intents)
  - [Enemy Ability Triggers](#enemy-ability-triggers)
  - [Spawning and Transformation](#spawning-and-transformation)
  - [Pigment Card Mechanics](#pigment-card-mechanics)
  - [Draw / Discard / Exhaust Piles](#draw--discard--exhaust-piles)
  - [Enemy Encounter System](#enemy-encounter-system)
  - [Card Rewards](#card-rewards)
  - [Shop Card Services](#shop-card-services)
  - [Weapons and Cards](#weapons-and-cards)
  - [Deck Management](#deck-management)
- [Teleport System](#teleport-system)
- [Developer Tools](#developer-tools)
- [Code Optimization](#code-optimization)
- [Creating New Content](#creating-new-content)
- [Common Issues](#common-issues)

---

## Overview

A roguelike game where players navigate through a graph of connected video games, encountering card-based combat, events, and shops. The game features a full Slay the Spire–style card system, a comprehensive curse system, item effects, and dynamic gameplay mechanics.

**Key Features:**
- STS-style card-based combat (hand, energy, draw/discard/exhaust piles)
- 11 unique curse types across 3 categories (Restriction, Manual, Automatic)
- Player-verified curse tracking system with combined verification modal
- Extensive item system (passive, usable, and triggered)
- Card deck system (collect cards, upgrade, remove at shop)
- Weight-based enemy encounter system with difficulty tiers
- Game status effects (portals, stinky games)
- Escape sequence after finding the amulet
- Save/load system with multiple save slots
- Comprehensive developer tools
- Dynamic difficulty scaling based on progress

**Architecture:**
The codebase is organized into focused, maintainable modules. See [js/README.md](js/README.md) for detailed module documentation.
- **15+ JavaScript modules** with clear responsibilities
- **combat-engine.js**: Card resolution, status effects, enemy AI
- **combat-ui.js**: Fan-arc hand rendering, drag-to-play, targeting mode
- **cards.js**: Deck management, card rewards, shop card services
- **Better maintainability** for both humans and LLMs

---

## Recent Updates

### Version 6.2 - Pre-Combat Event System (April 2026)

**New Event System:**
- Every combat encounter is now preceded by a pre-combat event with meaningful choices
- Two-roll D20 mechanics: Roll 1 = success check (D20 + stat vs difficulty), Roll 2 = critical check (D20 vs 18 — need 18, 19, or 20)
- Luck advantage: each Luck point gives 10% chance to roll two dice and take the best, checked independently per roll
- Difficulty thresholds scale with location: Easy = 11, Medium = 13, Hard = 15
- Click-to-roll visual UI: player sees threshold needed, clicks die(s) to roll with spin animation
- Event image + player full image shown side-by-side on the choice screen

**New Combat Statuses:**
- **Fear**: non-Attack cards cost +1 energy; lose 1 Fear stack each time an Attack card is played
- **Blind**: 30% miss chance on attacks; "MISS!" floating popup appears over the target on a miss

**New Combat Flags:**
- **Ambush**: player draws +2 extra cards on the first turn of the next combat
- **Ambushed**: player draws 2 fewer cards on the first turn of the next combat

**First Event — Watching Eyeballs (Mewgenics):**
- Three choices: Sneak By (Dexterity), Examine (Intelligence), Bash (Strength)
- 12 outcomes total covering ambush, fear, blind, gold, items, and Curse of Ocular Trauma

**Adding Events:**
- No code changes required — add an entry with an `image` property to `events-data.js` and it appears automatically
- See the [Events System](#events-system) section for the full guide and effect type reference

---

### Version 6.1 - Advanced Enemy Mechanics (March 2026)

**Pattern-Based Execution (all enemies):**
- Dice arrays in enemy data are now legacy — all enemies execute their `pattern` string exclusively
- `rollEnemyIntent` strips the `"Always: "` prefix and parses the description for both ordered and random enemies
- Random probability splits (`50% desc / 50% desc`) are handled with proper weighted random selection
- Forgetful enemies cycle through all branches before repeating, using branch index tracking

**New Complex Enemy Mechanics:**
- **Pain**: Enemy self-damage that bypasses block, thorns, and dodge entirely (direct HP reduction)
- **Spawning**: When an enemy is defeated or on a spawn trigger, a new enemy replaces the dead slot using `spawnEnemyAtSlot()`, fully initialized from `ENEMIES_DATA`
- **Alter (Transformation)**: An enemy transforms into a new form, changing name/pattern/ability/image while keeping current HP
- **Add Pigment**: Enemy adds a random Pigment (status) card to the player's hand or deck depending on pattern text
- **Consume Pigment**: Enemy consumes a random Pigment card from anywhere (hand/draw/discard) and gains Power + Block in return
- **Skinning Homunculus Reactive**: When an ally takes non-ranged damage, enemies with the `"When another ally takes Melee Dmg"` ability inject a `1 Frail Overload` effect into their intent mid-turn
- **Overload / Wide on Inflict**: Status infliction with Overload or Wide addons applies the status to the player AND all allies simultaneously

**On-Death Trigger System:**
- `onEnemyDefeated(enemy)` fires when an enemy's HP reaches 0 (from damage or Fading expiry)
- A one-time guard (`onDeathTriggered` flag) prevents double-triggering
- `executeWhenDefeatedClause` parses the `"When Defeated, ..."` ability text and handles: Spawn X, N% chance, probability splits (`60% X / 40% Y`), adjacent ally damage, and Strength Save checks

**Improved Pattern Parsing:**
- `parseSimplePatternDesc` now handles `NxM Dmg` multi-hit notation (e.g., `5x4 Dmg` → 4 hits of 5 damage)
- `Gain`/`Get` prefix before a status correctly flags it as a self-buff instead of an infliction
- `parsePatternDescToEffects` has dedicated keyword branches for `AddPigment` and `ConsumePigment` before falling through to general parsing
- `parseStartingAbilities` rewritten to correctly handle all enemy ability formats: `Fading N`, `Multi Attack N`, `Stagger N%`, `Immune to X`, and generic `N StatusName`

**New Functions:**
- `spawnEnemyAtSlot(enemyName, position)` — creates full enemy state, rolls initial intent, updates display
- `consumeRandomPigmentCard()` — finds a random `isStatusCard` card across all piles and removes it
- `onEnemyDefeated(enemy)` — fires death trigger from ability string
- `executeWhenDefeatedClause(enemy, clause)` — executes parsed death trigger text
- `addRandomPigmentToDeck()` in `cards.js` — adds a random pigment to the discard pile (shuffled in on next reshuffle)

---

### Version 6.0 - Card-Based Combat System (March 2026)

**Complete Combat Rewrite:**
- **STS-style card hand**: Up to 5 cards dealt per turn, displayed in a fan arc
- **Energy system**: 3 energy per turn (configurable via `gameState.maxEnergy`); cards cost 1–3 energy
- **Draw / Discard / Exhaust piles**: Full three-pile system; discard reshuffled into draw when empty
- **Card types**: Attack, Skill, Power, Dice, Status
- **Card rarities**: Starter, Common, Uncommon, Rare (Starter excluded from rewards)
- **Targeting mode**: Click a card → click an enemy to play; AoE cards skip targeting
- **Drag-to-play**: Drag a card up from the hand to play it (also activates targeting for single-target cards)
- **Enemy intents**: Each enemy shows its next action from its `pattern` column before acting
- **Card rewards**: Post-combat modal offers 3 random cards weighted by luck
- **Shop card services**: Upgrade a card (75g), remove a card (50g), buy 2 cards for sale
- **Status cards (Pigments)**: Auto-exhausted when played; cleared from deck after combat
- **Dice cards**: Randomly roll a face on play; each face has its own effect
- **Weapon cards**: Acquiring a weapon item adds its matching card to the deck

**New Modules:**
- `js/combat-engine.js` — Full card resolution engine (effects, status effects, enemy AI, AoE, dice)
- `js/combat-ui.js` — Full STS-style combat UI (fan hand, pile overlay, drag, tooltips, HP diffs)
- `js/cards.js` — Deck management, card reward modal, shop services, status card cleanup

**Key Technical Details:**
- Hand fan uses `transform: rotate(Xdeg) translateY(Ypx)` with `transform-origin: bottom center`
- Pile viewer is a `position:fixed; z-index:20000` overlay (does NOT destroy the combat modal)
- `checkCombatEnd` delegates to `main.js` override via `window.CombatUI.checkCombatEnd`
- `gameState.maxEnergy` is respected on combat init (items like Busted Crown set this)
- AoE detection pre-scans full card description before iterating effect parts

---

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

Displays all items with visual representations:

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

Every combat encounter is preceded by a **pre-combat event** — a short encounter where the player makes a meaningful choice before fighting. Events use a two-roll D20 system and are defined entirely in `events-data.js` with no code changes needed.

**How the flow works:**
1. Player clicks a combat node on the map
2. Event modal appears — shows an image, flavour text, and 2–4 choice buttons
3. Player picks a choice → rolls D20 + stat vs difficulty threshold → rolls D20 for critical
4. Outcome is shown (description + effect summary)
5. Player clicks **Continue to Combat** → combat starts

**Roll system:**
- **Roll 1 (Success check):** D20 + your stat ≥ difficulty (11 Easy / 13 Medium / 15 Hard)
- **Roll 2 (Critical check):** D20 ≥ 18 — need an 18, 19, or 20 (no stat bonus)
- **Luck advantage:** Each Luck point gives 10% chance to roll two dice and take the best, applied independently to each roll
- Four outcomes: `crit_good` (success + critical), `good` (success), `bad` (fail), `crit_bad` (fail + critical)

---

### Adding a New Event (Step-by-Step)

**Step 1 — Add the image**

Put the event image in `images/events/YourEventName.png`. Any size works; it displays as a wide banner strip.

**Step 2 — Add the event to `events-data.js`**

Open `events-data.js` and paste a new entry inside the `EVENTS_DATA` array (before the closing `];`). Use this template:

```javascript
{
  id: 'your_event_id',          // unique, lowercase, underscores
  name: 'Your Event Name',
  description: '{name} walks into a situation. Something happens.',
  image: 'images/events/YourEventName.png',
  game: 'GameNameHere',         // optional — which game universe this belongs to
  choices: [
    {
      text: 'Do the thing',
      type: 'stat_check',
      stat: 'strength',         // strength / dexterity / intelligence / charisma
      outcomes: {
        crit_good: {
          description: '{name} does the thing perfectly!',
          effects: [{ type: 'heal', value: 5 }]
        },
        good: {
          description: '{name} does the thing well enough.',
          effects: [{ type: 'none' }]
        },
        bad: {
          description: '{name} fails to do the thing.',
          effects: [{ type: 'combat_status', status: 'weak', stacks: 1 }]
        },
        crit_bad: {
          description: '{name} fails spectacularly.',
          effects: [{ type: 'combat_status', status: 'vulnerable', stacks: 2 }]
        }
      }
    }
    // add more choices here, separated by commas
  ]
}
```

That's it — no code changes. The event is automatically added to the pool and will appear before combats.

---

### Full Effect Type Reference

Paste any of these into an outcome's `effects` array (it's always an array, even with one effect):

#### Nothing
```javascript
{ type: 'none' }
```

#### Heal HP
```javascript
{ type: 'heal', value: 5 }   // restore 5 HP (capped at max)
```

#### Gold (fixed)
```javascript
{ type: 'gold', value: 15 }  // gain 15 gold (negative = lose gold)
```

#### Gold (random range)
```javascript
{ type: 'gold_range', min: 10, max: 20 }  // gain 10–20 gold
```

#### Random item with a tag
```javascript
{ type: 'item_tagged', tag: 'coin' }  // award a random item tagged 'coin'
{ type: 'item_tagged', tag: 'eye' }   // award a random item tagged 'eye'
```
The tag must match one of the item's `tags` array values in `items-data.js` (case-insensitive).
Items currently tagged `coin`: **Old Coin**. Items tagged `eye`: **Dead Eye**, **Glass Eye**.

#### Curse (named)
```javascript
{ type: 'curse', value: 'Curse of Frugality' }
```

#### Curse (scaled by location difficulty — Easy/Medium/Hard → I/II/III)
```javascript
{ type: 'curse_difficulty', curseBase: 'Curse of Ocular Trauma' }
// gives "Curse of Ocular Trauma I" on Easy, "...II" on Medium, "...III" on Hard
```
Make sure the three tiers exist in `curses-data.js`.

#### Combat status at start of next combat
```javascript
{ type: 'combat_status', status: 'fear',       stacks: 1 }
{ type: 'combat_status', status: 'blind',      stacks: 4 }
{ type: 'combat_status', status: 'weak',       stacks: 2 }
{ type: 'combat_status', status: 'vulnerable', stacks: 1 }
{ type: 'combat_status', status: 'frail',      stacks: 2 }
{ type: 'combat_status', status: 'poison',     stacks: 3 }
{ type: 'combat_status', status: 'burn',       stacks: 2 }
```
Any combat status name works here — it is applied to the player at the start of the next fight.

#### Ambush / Ambushed (draw adjustment on turn 1)
```javascript
{ type: 'combat_flag', flag: 'ambush' }    // draw +2 cards on turn 1
{ type: 'combat_flag', flag: 'ambushed' }  // draw -2 cards on turn 1
```

#### Multiple effects in one outcome
```javascript
effects: [
  { type: 'combat_status', status: 'fear', stacks: 2 },
  { type: 'combat_flag', flag: 'ambushed' }
]
```

---

### Stat Check Reference

| `stat` value | Stat shown | Icon |
|---|---|---|
| `strength` | Strength | 💪 |
| `dexterity` | Dexterity | 🤸 |
| `intelligence` | Intelligence | 🧠 |
| `charisma` | Charisma | 💬 |

The player's stat value is added as a flat bonus to the d20 roll. Higher stat → lower effective target number shown to the player.

**Difficulty thresholds by location:**

| Location difficulty | Roll needed (before stat bonus) |
|---|---|
| Easy | 11 |
| Medium | 13 |
| Hard | 15 |

---

### Using `{name}` in Text

Both `description` (the opening flavour text) and each outcome's `description` support `{name}`, which is replaced with the player character's name at display time.

```javascript
description: '{name} stumbles upon a dark hole. Numerous eyes peer out from the darkness.'
// → "Mitch stumbles upon a dark hole. Numerous eyes peer out from the darkness."
```

---

### Complete Working Example

This is the **Watching Eyeballs** event, already in the game. Use it as a reference:

```javascript
{
  id: 'watching_eyeballs',
  name: 'Watching Eyeballs',
  description: '{name} stumbles upon a dark hole. Numerous eyes peer out from the darkness.',
  image: 'images/events/WatchingEyeballs.png',
  game: 'Mewgenics',
  choices: [
    {
      text: 'Sneak By',
      type: 'stat_check',
      stat: 'dexterity',
      outcomes: {
        crit_good: {
          description: '{name} sneaks by the spooky looking crack, getting into a position to ambush!',
          effects: [{ type: 'combat_flag', flag: 'ambush' }]
        },
        good: {
          description: '{name} carefully sneaks by the wall and nothing appears to happen.',
          effects: [{ type: 'none' }]
        },
        bad: {
          description: 'The eyes glare directly at {name}… {name} bolts into a sprint!',
          effects: [{ type: 'combat_status', status: 'fear', stacks: 1 }]
        },
        crit_bad: {
          description: 'The unnerving gaze terrifies {name}, running right into an ambush!',
          effects: [
            { type: 'combat_status', status: 'fear', stacks: 2 },
            { type: 'combat_flag', flag: 'ambushed' }
          ]
        }
      }
    },
    {
      text: 'Examine',
      type: 'stat_check',
      stat: 'intelligence',
      outcomes: {
        crit_good: {
          description: '{name} discovers the eyes were just large coins glinting in the dim light!',
          effects: [{ type: 'item_tagged', tag: 'coin' }]
        },
        good: {
          description: 'After closer examination — the eyes were coins!',
          effects: [{ type: 'gold_range', min: 10, max: 20 }]
        },
        bad: {
          description: '{name} locks eyes with the darkness and runs in terror!',
          effects: [{ type: 'combat_status', status: 'fear', stacks: 2 }]
        },
        crit_bad: {
          description: 'Something sharp lashes out and stabs {name}'s eye!',
          effects: [{ type: 'curse_difficulty', curseBase: 'Curse of Ocular Trauma' }]
        }
      }
    },
    {
      text: 'Bash',
      type: 'stat_check',
      stat: 'strength',
      outcomes: {
        crit_good: {
          description: '{name} bats at the eyes with lightning fast strikes!',
          effects: [{ type: 'item_tagged', tag: 'eye' }]
        },
        good: {
          description: '{name} smashes the eyes into concave lumps of flesh!',
          effects: [{ type: 'heal', value: 5 }]
        },
        bad: {
          description: 'The eyes flash with a blinding brightness!',
          effects: [{ type: 'combat_status', status: 'blind', stacks: 4 }]
        },
        crit_bad: {
          description: '{name} reaches into the hole and pokes themself in the face on the sharp edges!',
          effects: [{ type: 'curse_difficulty', curseBase: 'Curse of Ocular Trauma' }]
        }
      }
    }
  ]
}
```

---

### How `curse_difficulty` Works

When you use `{ type: 'curse_difficulty', curseBase: 'Curse of Something' }`, the engine:
1. Checks the current location's difficulty (Easy / Medium / Hard)
2. Appends ` I`, ` II`, or ` III` to the base name
3. Looks up that exact name in `curses-data.js` and applies it
4. If the curse description contains `"Add X to your Deck"`, it also adds that card automatically

So for `curseBase: 'Curse of Ocular Trauma'`, you need all three in `curses-data.js`:
- `Curse of Ocular Trauma I`
- `Curse of Ocular Trauma II`
- `Curse of Ocular Trauma III`

---

### How Combat Statuses from Events Work

`combat_status` effects are stored in `gameState.pendingCombatStatuses` after the event resolves. When the next combat starts (`initCombat`), they are applied to the player's starting statuses and the list is cleared. The player enters the fight already affected.

**Fear** — non-Attack cards cost +1 energy; lose 1 Fear stack each time you play an Attack card.

**Blind** — 30% miss chance on attacks. When a miss happens a "MISS!" popup appears over the target. Stacks = duration in turns.

---

### Event Engine Files

| File | Purpose |
|---|---|
| `events-data.js` | All event definitions — **this is the only file you edit** to add events |
| `js/event-engine.js` | Renders the UI screens, rolls dice, applies effects |

The engine only picks events that have an `image` property, so old-format entries in the same file are skipped automatically.

---


## Combat System

### Overview

Combat uses a Slay the Spire–style card system. Each encounter is a turn-based fight between the player and one or more enemies. The player draws cards from their deck each turn, spends energy to play them, and ends the turn to let enemies act.

---

### Combat Flow

```
Start of Combat
  → initCombat() shuffles deck, draws 5 cards, restores energy
  ↓
Player's Turn
  → Draw 5 cards (or remaining draw pile + reshuffled discard)
  → Each card costs 1–3 energy (shown on card)
  → Play cards by clicking or dragging
  → Single-target cards enter targeting mode; click an enemy to resolve
  → AoE cards (Cleave, Indiscriminate, "all enemies") hit every enemy instantly
  → End Turn button: discard hand, enemies act, draw 5 again
  ↓
Enemy Turn
  → Each enemy executes its next intent (shown in banner before it acts)
  → Intents cycle through the enemy's pattern list
  ↓
Check Win / Loss
  → All enemies dead → victory, card reward modal
  → Player HP ≤ 0 → defeat, game over
```

---

### Energy System

- **Starting energy**: 3 per turn (default)
- **Maximum energy**: Controlled by `gameState.maxEnergy`; items like Busted Crown increase it
- Energy is **fully restored** at the start of each player turn
- Cards that cost more energy than available cannot be played

---

### Card Hand

- **Hand size**: Up to 5 cards drawn per turn (hard cap: 10)
- Cards are displayed in a **fan arc** at the bottom of the screen
- Hover a card to expand it and see a full tooltip
- Drag a card upward or click it to play it
- A targeting banner appears when a single-target card is selected; click an enemy to confirm

---

### Card Types

| Type | Description |
|------|-------------|
| **Attack** | Deals damage to one or all enemies |
| **Skill** | Non-damage effects: block, healing, buffs, debuffs |
| **Power** | Persistent effects that last the entire combat |
| **Dice** | Rolls a random face on play; each face has a different effect |
| **Status** | Temporary cards (e.g., Pigments); auto-exhausted when played, cleared from deck after combat |

---

### Card Rarities

| Rarity | Source |
|--------|--------|
| **Starter** | Character starting deck; never offered as rewards |
| **Common** | Most frequent in reward pool |
| **Uncommon** | Moderate chance; better effects |
| **Rare** | Least frequent; most powerful |

Rarity chances are weighted by the player's **Luck** stat (same system as items).

---

### Card Effects Reference

Effects are parsed from card `description` strings. Supported keywords:

| Keyword | Engine Behavior |
|---------|----------------|
| `Deal X Dmg` | Deals X damage (modified by Strength for Attack cards) |
| `Gain X Block` | Adds X block (absorbs damage before HP) |
| `Heal X Health` | Restores X HP to the player |
| `Take X Dmg` | Player takes X damage (self-harm cards) |
| `Draw X Cards` | Draws X additional cards from draw pile |
| `Gain X Energy` | Adds X energy this turn |
| `Apply X [Status]` | Applies a combat status (Burn, Poison, Stun, Weak, Vulnerable, etc.) |
| `Enemy loses X Power` | Reduces target enemy's Power stat |
| `Gain +X [Stat] until end of combat` | Temporary stat boost for the current combat |
| `Cleave` / `Indiscriminate` / `all enemies` | Card hits all enemies (AoE) |
| `Exhaust` | Card is removed from this combat after being played |

**Dice cards** use a `"N: effect text\n..."` format — one line per face. A random face is rolled on play and its text resolved as a normal card effect.

---

### Combat Statuses

Status effects are tracked per-entity in the `statuses` dictionary on each combatant.

#### Player / Enemy Statuses

| Status | Effect |
|--------|--------|
| **Burn** | Takes damage at end of turn; does not apply if `immune_burn` is set |
| **Poison** | Stacks; takes damage each turn then decreases by 1 |
| **Stun** | Target skips their next action |
| **Weak** | Reduces outgoing damage by 25% |
| **Vulnerable** | Increases incoming damage by 50% |
| **Frail** | Reduces block gain |
| **Power** | Generic bonus to damage and/or defense |
| **Block** | Absorbs incoming damage before HP; does not persist between turns |

#### Enemy-Only Statuses (from Ability string)

| Status | Effect |
|--------|--------|
| **Fading N** | Counts down each turn; when it hits 0 the enemy dies (fires `onEnemyDefeated`) |
| **Multi Attack N** | Enemy executes its pattern N times per turn |
| **Forgetful** | Enemy cycles through probability branches without repeating before resetting |
| **Immune to X** | Enemy is immune to the named status (e.g., `immune_burn`) |
| **Pain N** | Enemy deals N direct damage to itself — bypasses block, thorns, and dodge entirely |

#### Inflict Addons

| Addon | Effect |
|-------|--------|
| **Overload** | Applies the status to the player AND all allies |
| **Wide** | Alias for Overload |
| *(none)* | Applies only to the player |

---

### Enemy Intents

Before each enemy turn, the enemy's **intent** is shown in a banner above its card. All enemies execute their `pattern` string — the old dice arrays are legacy and ignored.

#### Pattern Formats

| Format | Meaning |
|--------|---------|
| `Always: <desc>` | Executes `<desc>` every turn |
| `Turn 1: <desc> / Turn 2: <desc> / ...` | Ordered rotation; `Next:` suffix loops the list |
| `50% <desc1> / 50% <desc2>` | Random weighted branch selection |

#### Pattern Description Keywords

| Keyword | Effect |
|---------|--------|
| `N Dmg` | Deals N damage to the player |
| `NxM Dmg` | Deals N damage M times (multi-hit) |
| `N Block` | Enemy gains N block |
| `N Heal` | Enemy heals N HP |
| `Gain N <Status>` / `Get N <Status>` | Enemy applies the status to itself |
| `N <Status>` | Enemy inflicts N stacks of status on the player |
| `N <Status> Overload` | Inflicts N on player AND all allies |
| `Add N random Pigment to hand/deck` | Adds a random pigment card to the player's hand or deck |
| `Consume N random Pigment for X Power, Y Block` | Consumes a random pigment from any pile; gains X Power and Y Block |

---

### Enemy Ability Triggers

Complex enemy behaviors are declared in the `ability` field of each enemy and parsed at runtime.

#### Starting Ability Formats

| Format | Effect |
|--------|--------|
| `N StatusName` | Enemy starts combat with N stacks of the named status |
| `Fading N` | Enemy starts with a Fading countdown of N turns |
| `Multi Attack N` | Enemy acts N times per turn |
| `Stagger N%` | Enemy staggers (skips next action) when its HP crosses certain thresholds |
| `Immune to X` | Sets `immune_X` flag; blocks the named status |

#### Death Triggers

Death trigger text follows the format `When Defeated, <clause>` in the ability string. Supported clause types:

| Clause | Effect |
|--------|--------|
| `Spawn <EnemyName>` | Spawns a new enemy from ENEMIES_DATA, replacing this enemy's slot |
| `N% Spawn <EnemyName>` | N% chance to spawn |
| `60% Spawn X / 40% Spawn Y` | Weighted random spawn choice |
| `N Dmg to adjacent allies` | Deals N damage to enemies in adjacent position slots |
| `Strength Save DC N or take X Dmg` | Player rolls vs DC; failure takes X damage |

#### Reactive Abilities

| Ability Text | Trigger | Effect |
|-------------|---------|--------|
| `When another ally takes Melee Dmg` | Any non-ranged attack on an ally | Injects `1 Frail Overload` into this enemy's current turn intent |

---

### Spawning and Transformation

#### `spawnEnemyAtSlot(enemyName, position)`
- Looks up `enemyName` in `ENEMIES_DATA` (case-insensitive)
- Randomizes HP within `hpMin`–`hpMax` range
- Initializes all fields: statuses, pattern type, stagger threshold, intent
- Replaces the dead enemy at `position`; appends if no dead enemy exists
- Immediately rolls and displays initial intent

#### `alter` (Transformation)
- Triggered by `Alter <FormName>` in a pattern description
- Transforms the enemy's name, ability, pattern, image, and stagger threshold in place
- **Current HP is preserved** — only form data changes
- Merges new starting statuses from the new form's ability string
- Immediately rerolls intent for the new form

---

### Pigment Card Mechanics

**Pigment cards** (Status type, `isStatusCard: true`) are temporary cards that enemies can interact with:

| Enemy Action | Effect |
|-------------|--------|
| Add Pigment to hand | Calls `addRandomPigmentToHand()` — picks a random pigment from CARDS_DATA and adds it to combat hand |
| Add Pigment to deck | Calls `addRandomPigmentToDeck()` — adds to discard pile (shuffled into draw on next reshuffle) |
| Consume Pigment | `consumeRandomPigmentCard()` — searches hand → draw pile → discard pile and removes one random pigment; then awards the enemy Power + Block |

---

### Draw / Discard / Exhaust Piles

- **Draw pile**: Cards left to draw from this combat. Displayed as a number button (bottom-left).
- **Discard pile**: Cards played or discarded this turn. Displayed as a number button (bottom-right).
- **Exhaust pile**: Cards permanently removed for this combat (Power cards, Status cards, cards with `Exhaust` keyword). Not reshuffled.
- When the draw pile is empty and the player needs to draw, the discard pile is reshuffled into the draw pile.
- Click either pile button to open an overlay showing all cards in that pile.

---

### Enemy Encounter System

Enemies are selected using a **weight-based budget system** tied to difficulty tier:

| Tier | Games Beaten | Budget Range |
|------|-------------|--------------|
| Low | 0–4 | Small budget |
| Medium | 5–9 | Medium budget |
| High | 10+ | Large budget |

Each enemy has a `weight` and a `cost`. Encounters are assembled by randomly picking enemies within the budget, weighted by their `weight` value. This ensures multiple weak enemies or a single strong enemy depending on the roll.

---

### Card Rewards

After winning combat, a **card reward modal** appears offering 3 random cards:
- Cards drawn from the non-Starter, non-Status reward pool
- Rarity weighted by the player's Luck stat
- Player selects one card to add to their deck, or skips
- `showCardRewardModal()` in `js/cards.js`

---

### Shop Card Services

The shop offers two one-time services per visit:

| Service | Cost | Description |
|---------|------|-------------|
| **Upgrade a Card** | 75 gold | Permanently upgrades one deck card (improved effect or reduced cost) |
| **Remove a Card** | 50 gold | Permanently removes one deck card from the run |

The shop also shows **2 cards for sale** at random prices. Purchasing adds them to the deck immediately.

---

### Weapons and Cards

Acquiring a **weapon item** (type `weapon` or tag `weapon`) automatically adds a matching card to the player's deck. The card is identified by matching the weapon's name in `CARDS_DATA`. This is handled by a hook on `window.acquireItem` in `js/cards.js`.

---

### Deck Management

The deck viewer modal (`showDeckModal()`) shows all cards in the player's current deck with rarity, type, cost, and description. Accessible from the inventory/UI during a run.

**Deck state in `gameState`:**
```javascript
gameState.deck        // All cards the player owns (persistent across encounters)
gameState.hand        // Cards in hand during combat
gameState.drawPile    // Cards left to draw this combat
gameState.discardPile // Cards played this combat
```

---

### Key Files

| File | Responsibility |
|------|---------------|
| `js/combat-engine.js` | Card resolution, status effects, enemy AI, pattern execution, spawning, death triggers |
| `js/combat-ui.js` | Fan-arc hand, drag-to-play, pile overlay, targeting mode, HP diff animations |
| `js/cards.js` | Deck management, card reward modal, shop services, pigment card helpers |
| `data/cards-data.js` | Card definitions (name, type, rarity, cost, description, upgrade data) |
| `data/enemies-data.js` | Enemy definitions (HP, pattern, ability, weight/cost for encounter budget) |
| `data/statuses-data.js` | Combat status effect definitions |

**Key combat-engine.js functions:**

| Function | Purpose |
|----------|---------|
| `rollEnemyIntent(enemy)` | Parses the enemy's `pattern` string and populates `currentIntent` |
| `executeEnemyActions(enemy)` | Resolves each intent item: Dmg, Block, Heal, Inflict, Spawn, Alter, AddPigment, ConsumePigment, Pain |
| `parsePatternDescToEffects(desc)` | Converts a pattern description string into effect objects |
| `parseSimplePatternDesc(text)` | Tokenizes text into effects; handles NxM multi-hit and Gain/Get self-buffs |
| `parseStartingAbilities(abilityStr)` | Extracts starting statuses from an ability string (Fading, Multi Attack, Immune to, etc.) |
| `spawnEnemyAtSlot(name, pos)` | Creates and inserts a new enemy from ENEMIES_DATA at the given position |
| `onEnemyDefeated(enemy)` | Fires the enemy's "When Defeated" ability clause (one-shot guard) |
| `executeWhenDefeatedClause(enemy, clause)` | Parses and executes death trigger text (Spawn, Dmg, Strength Save, probability) |
| `consumeRandomPigmentCard()` | Removes a random `isStatusCard` card from any pile |
| `dealDamage(target, amount, addons)` | Applies damage with block/thorns/dodge resolution; fires death trigger and reactive hooks |
| `processStatusEffects(target)` | Applies per-turn status ticks (Burn, Poison, Fading, etc.) |

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

### Card Not Playing When Clicked
- Ensure the card has sufficient energy to play (`combat.energy >= card.cost`)
- Single-target cards require clicking an enemy after selecting the card — check that a valid target exists
- Check browser console for `[CombatEngine] playCard` errors

### Pile Overlay Closing Combat
- `_showCombatPile()` must use a `position:fixed` div appended to `document.body`, NOT `createGameModal()` (which destroys the combat screen)
- Verify `js/combat-ui.js` builds a standalone overlay with `z-index:20000`

### Cards Dealing No Damage / Effects Not Resolving
- Card description must use exact keywords (e.g. `Deal X Dmg`, not `deals X damage`)
- Dice card faces must follow the `"N: effect text"` format, one per line
- Check `resolveCardEffect` in `js/combat-engine.js` for supported keywords

### maxEnergy Not Being Applied
- Items set `gameState.maxEnergy`; `initCombat` must read this first
- Verify `combat.energy = gameState.maxEnergy || characterData.energy || 2` in `initCombat`

### Game Over Not Triggering After Player Death
- `checkCombatEnd()` in `combat-ui.js` delegates to `window.CombatUI.checkCombatEnd` (set by `main.js`)
- If `main.js` override is not running, check that `window.CombatUI` is exported at bottom of `combat-ui.js`

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
