# Combat System Overhaul Progress

## Completed

### 1. Data Layer (100%)
- **Excel Converter** (`convert-excel.js`) - Fully updated to parse all new sheets
- **Generated Data Files**:
  - `characters-data.js` - Characters with dice faces, energy, mana, level-up stats
  - `enemies-data.js` - Enemies with 6-sided dice and parsed effects
  - `allies-data.js` - Allies with dice and abilities
  - `weapons-data.js` - Weapons with combat dice
  - `items-data.js` - Updated with new item structure
  - `statuses-data.js` - Combat statuses (Burn, Poison, Dodge, etc.)
  - `moves-data.js` - Move definitions with stat bonuses
  - `addons-data.js` - Addon definitions (Cantrip, Cleave, Wide, etc.)
  - `spells-data.js` - Spells with costs, keywords, effects
  - `spell-keywords-data.js` - Spell keyword definitions
  - `curses-data.js` - Updated curses
  - `game-statuses-data.js` - Game board statuses

### 2. Combat Engine (100%)
- **New file**: `js/combat-engine.js`
- **Features implemented**:
  - Combat state management (`combatState`)
  - Player dice pool (character + weapon + ally dice)
  - Dice rolling with energy cost
  - Reroll system using reroll resource
  - Confirm/use dice mechanics
  - Stat scaling (STR→Dmg, DEX→Block, INT→Heal/Mana, CHA→Status)
  - Weapon Finesse tag support
  - Targeting system (single, Wide, Cleave, Overload)
  - Status effects processing (Burn, Poison, Dodge, Thorns, Frail, etc.)
  - Spell system with keywords (SingleCast, Channel, Cooldown, Deplete, Future)
  - Enemy intent system with Multi Attack
  - Ally HP tracking
  - Turn flow management
  - Cantrip immediate triggers
  - Exhert exhaustion mechanic
  - Dash → Dodge conversion
  - Confused status randomizing energy costs
  - Horn Cleat turn 2 block bonus

### 3. HTML Integration (100%)
- `index.html` updated with all new script includes

### 4. Combat UI (100%)
- **New file**: `js/combat-ui.js`
- **Features implemented**:
  - Player dice pool display with roll/confirm/reroll buttons
  - Enemy intent display showing what enemies plan to do
  - Status effect icons for player, allies, and enemies
  - Spellbook panel with spell costs and availability
  - Energy/Mana/Reroll resource bars
  - Enemy targeting via click selection
  - Auto-targeting for single-enemy encounters
  - Combat log with color-coded messages
  - Victory/defeat handling

### 5. Main.js Integration (100%)
- **New function**: `showDiceCombatModal()`
- **Features implemented**:
  - Enemy selection by difficulty and type
  - Character data loading from CHARACTERS_DATA
  - Weapon integration with WEAPONS_DATA
  - Player stat merging into combat
  - Victory rewards (gold based on difficulty)
  - Defeat handling with retry option
  - Available globally via `window.showDiceCombatModal()`

## Remaining Work

### 1. Level-Up System
Need to implement:
- Level display in stats panel
- Level-up verification prompts (based on character.levelUpCondition)
- Stat bonus application on level up
- Random dice face upgrade on level up

### 2. Ally System
Need to implement:
- Ally recruitment UI
- Ally tracking in game state (gameState.activeAllies)
- Ally HP persistence between combats

### 3. Combat Trigger Integration (DONE)
Completed:
- Added `useDiceCombat` toggle (default: true)
- Updated exploration.js to check toggle and call appropriate combat
- Added `window.toggleCombatSystem()` for easy switching
- Set via console: `window.useDiceCombat = true/false`

## How to Test

### Option 1: Direct Call (Browser Console)
```javascript
// Call the new dice combat modal directly
showDiceCombatModal();
```

### Option 2: Test Engine Only
```javascript
const enemies = ENEMIES_DATA.filter(e => e.name === 'Lemurian');
const character = CHARACTERS_DATA['rodney'];
const combat = window.CombatEngine.initCombat(enemies, character);

// Roll a die
window.CombatEngine.rollPlayerDie('character');

// Check state
console.log(window.CombatEngine.getCombatState());

// Confirm die with target
window.CombatEngine.confirmDie('character', { enemyId: 'enemy_0' });

// End turn
window.CombatEngine.endTurn();
```

### Option 3: Replace Old Combat Globally
```javascript
// In browser console, swap systems:
window.showCombatModal = window.showDiceCombatModal;
```
Then trigger any combat encounter in the game.

## API Reference

### CombatEngine Methods
- `initCombat(enemies[], characterData, weaponData?, allies[])` - Start combat
- `rollPlayerDie(diceId)` - Roll a die (costs energy)
- `rerollPlayerDie(diceId)` - Reroll a die (costs reroll)
- `confirmDie(diceId, targets)` - Confirm and apply die effects
- `useDash()` - Use dash to gain Dodge
- `castSpell(spellName, targets)` - Cast a spell (costs mana)
- `endTurn()` - End player turn, process enemy actions
- `getCombatState()` - Get current state
- `endCombat(victory)` - Clean up combat

### Combat State Structure
```javascript
{
  player: {
    health, maxHealth,
    energy, maxEnergy,
    mana, maxMana,
    stats: { strength, dexterity, intelligence, charisma },
    bonuses: { strength, dexterity, intelligence, charisma }, // /3
    block, statuses, rerolls, dash
  },
  enemies: [{
    id, name, type, difficulty,
    health, maxHealth, block, statuses,
    ability, dice, currentIntent, position
  }],
  allies: [{
    id, name, health, maxHealth,
    block, statuses, ability, isAlive, position
  }],
  playerDice: [{
    id, name, source, faces,
    currentFace, isRolled, isConfirmed, isExhausted
  }],
  turn, phase, log, spells,
  spellCooldowns, spellCasts, usedSingleCast
}
```
