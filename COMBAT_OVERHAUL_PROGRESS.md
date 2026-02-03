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

## Remaining Work

### 1. Combat UI (`js/main.js` - `showCombatModal`) - Needs Update
The existing combat modal uses the old D20 attack/defense system. It needs to be updated to:

1. **Display player dice pool** (character die, weapon die, ally dice)
2. **Show dice faces** with confirm/reroll buttons per die
3. **Enemy intent display** showing what enemies plan to do
4. **Status effect icons** for both player and enemies
5. **Spellbook UI** - collapsible panel showing available spells with mana costs
6. **Targeting interface** - click to select target for single-target moves
7. **Wide/Cleave highlighting** - show affected targets
8. **Energy/Mana display** - current and max
9. **Ally HP bars** - track ally health

### 2. Integration Points
To connect the new engine to the UI:

```javascript
// In showCombatModal(), replace initializeCombat with:
const characterData = CHARACTERS_DATA[selectedCharacter];
const weaponData = equippedWeapon ? WEAPONS_DATA.find(w => w.name === equippedWeapon.name) : null;
const combat = window.CombatEngine.initCombat([enemy], characterData, weaponData, activeAllies);

// UI event handlers needed:
- onDiceRoll(diceId) -> CombatEngine.rollPlayerDie(diceId)
- onDiceReroll(diceId) -> CombatEngine.rerollPlayerDie(diceId)
- onDiceConfirm(diceId, targets) -> CombatEngine.confirmDie(diceId, targets)
- onDash() -> CombatEngine.useDash()
- onCastSpell(spellName, targets) -> CombatEngine.castSpell(spellName, targets)
- onEndTurn() -> CombatEngine.endTurn()
```

### 3. Level-Up System
Need to implement:
- Level display in stats panel
- Level-up verification prompts (based on character.levelUpCondition)
- Stat bonus application on level up
- Random dice face upgrade on level up

### 4. Weapon Integration
Need to add:
- Weapon equip UI
- Weapon die added to combat pool when equipped
- Weapon tags (Finesse, Fishing Weight) applied during combat

## How to Test Current Implementation

1. Open browser console
2. Test combat engine directly:
```javascript
// Initialize test combat
const enemies = ENEMIES_DATA.filter(e => e.name === 'Cultist');
const character = CHARACTERS_DATA['rodney'];
const combat = CombatEngine.initCombat(enemies, character);

// Roll a die
CombatEngine.rollPlayerDie('character');

// Check state
console.log(CombatEngine.getCombatState());

// Confirm die (auto-targets)
CombatEngine.confirmDie('character', { self: true });

// End turn
CombatEngine.endTurn();
```

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
