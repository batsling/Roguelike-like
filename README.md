# Roguelike Game Documentation

## Table of Contents
- [Items System](#items-system)
- [Game Status Effects](#game-status-effects)
- [Events System](#events-system)
- [Teleport System](#teleport-system)
- [Combat System](#combat-system)
- [Developer Tools](#developer-tools)
- [Recent Updates](#recent-updates)

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
      strength += 2;
      gameState.strength = strength;
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
      // Triggered effect logic
      health = Math.min(health + 1, maxHealth);
      gameState.health = health;
    }
  }
}
```

### Passive Item Examples

**Stat Boost Items** (add stats when acquired):
```javascript
"Sunglasses": {
  onAcquire: () => {
    charisma += 2;
    gameState.charisma = charisma;
  }
}
```

**Health Items** (add max health and heal):
```javascript
"Hollow Heart": {
  onAcquire: () => {
    maxHealth += 2;
    health = Math.min(health + 2, maxHealth); // Cap health to max
    gameState.maxHealth = maxHealth;
    gameState.health = health;
  }
}
```

**Items with Tradeoffs** (positive and negative effects):
```javascript
"Bowler Hat": {
  onAcquire: () => {
    charisma += 3;
    dexterity -= 1;
    gameState.charisma = charisma;
    gameState.dexterity = dexterity;
  }
}
```

**Special Stat Items**:
```javascript
"Ballistic Boots": {
  onAcquire: () => {
    dash += 1;  // Increases movement options
    gameState.dash = dash;
  }
},
"More Options": {
  onAcquire: () => {
    fov += 1;  // Increases field of view (more game choices)
    gameState.fov = fov;
  }
},
"Lucky Toe": {
  onAcquire: () => {
    luck += 1;  // Improves shop prices and rewards
    gameState.luck = luck;
  }
},
"D6": {
  onAcquire: () => {
    reroll += 1;  // Adds item reroll charge
    gameState.reroll = reroll;
  }
}
```

### Usable Item Examples

**Basic Teleport**:
```javascript
"Scroll of Teleportation": {
  canUse: () => {
    return gameState.phase === 'selection';
  },
  onUse: () => {
    teleportToRandomGame();  // Teleports to any connected game
  }
}
```

**Filtered Teleport**:
```javascript
"Ride the Bus": {
  canUse: () => {
    return gameState.phase === 'selection';
  },
  onUse: () => {
    teleportToRandomDeckbuilder();  // Teleports to Deckbuilding game
  }
}
```

**Player-Choice Teleport**:
```javascript
"Winged Boots": {
  canUse: () => {
    return gameState.phase === 'selection';
  },
  onUse: () => {
    const currentGameObj = games.find(g => g.name === gameState.currentGame);
    if (!currentGameObj) {
      alert('Cannot determine current location!');
      return;
    }

    const currentYear = currentGameObj.year;

    // Show selection of 3 games from the same year
    selectedTeleport({
      numChoices: 3,
      year: currentYear,
      title: `Choose Your Destination (${currentYear})`
    });
  }
}
```

**Multi-Use Items**:
```javascript
"Ventricle Razor": {
  uses: 2, // Can be used twice before being removed from inventory
  canUse: () => {
    return true; // Can use anytime
  },
  onUse: () => {
    // Apply portal status to current game
    addGameStatus(gameState.currentGame, 'portal', '🌀');
  }
}
```

### Triggered Item Examples

**Items that trigger on enemy defeats**:

```javascript
"Charm of the Vampire": {
  onAcquire: () => {
    console.log('Acquired Charm of the Vampire');
  },
  onEnemyDefeated: () => {
    // 50% base chance + (5% * luck) to heal
    const baseChance = 0.50;
    const luckBonus = (luck || 0) * 0.05;
    const totalChance = baseChance + luckBonus;

    if (Math.random() < totalChance) {
      health = Math.min(health + 1, maxHealth);
      gameState.health = health;
    }
  }
},

"Cursed Slash": {
  onAcquire: () => {
    // Lose half of max health immediately
    const healthLoss = Math.floor(maxHealth / 2);
    maxHealth -= healthLoss;
    health = Math.max(0, health - healthLoss);
    gameState.maxHealth = maxHealth;
    gameState.health = health;
  },
  onEnemyDefeated: () => {
    // Always heal +1 health when defeating an enemy
    health = Math.min(health + 1, maxHealth);
    gameState.health = health;
  }
}
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

### Status Effect Items

**The Poop** - Applies "stinky" status:
```javascript
"The Poop": {
  canUse: () => true,
  onUse: () => {
    // Apply stinky status to current game
    addGameStatus(gameState.currentGame, 'stinky', '💩');

    // Refresh current node to show icon immediately
    const currentNode = document.querySelector('.node.current');
    if (currentNode) {
      updateNodeStatusIcons(currentNode);
    }
  }
}
```

**Effect**: Stinky games are deprioritized in game selections (appear last in the shuffled list).

**Ventricle Razor** - Applies "portal" status:
```javascript
"Ventricle Razor": {
  uses: 2, // Can create 2 portals
  canUse: () => true,
  onUse: () => {
    // Apply portal status to current game
    addGameStatus(gameState.currentGame, 'portal', '🌀');

    // Refresh current node to show icon immediately
    const currentNode = document.querySelector('.node.current');
    if (currentNode) {
      updateNodeStatusIcons(currentNode);
    }
  }
}
```

**Effect**: When standing on a portal game, all other portal games appear as extra choices (creates instant long-distance connections). Maximum 2 portals can exist at once.

### Status Icon Display

- Status icons appear in the **top-left corner** of game nodes
- Icons use `pointer-events: none` so tooltips work normally
- Icons appear on **all node types**: current, past, choice, and selection
- Multiple status effects stack horizontally
- Icons auto-refresh when status is applied via `updateNodeStatusIcons()`

### Implementation Notes

- Status effects are stored in `gameState.gameStatusEffects` as `{ gameName: [{ name, icon }, ...] }`
- Stinky games are filtered separately and added to the end of choices
- Portal games are added to choices when player is on a portal-marked game
- Status icons persist across game sessions when saved

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

  // Rewards for success
  successReward: "10 gold",  // or "common item", "uncommon item", "rare item"

  // Consequences for failure
  failureConsequence: "Lose 1 health",  // or "Lose 5 gold"
}
```

### Event Difficulty

Event difficulty determines the DC (roll check needed):
- **Low**: DC 8-12 (easier checks)
- **Medium**: DC 13-16 (moderate checks)
- **High**: DC 17-20 (harder checks)

### Event Outcomes

**Success Rewards**:
- Gold: `"10 gold"`, `"20 gold"`, etc.
- Items: `"common item"`, `"uncommon item"`, `"rare item"`
- Can combine: `"15 gold and common item"`

**Failure Consequences**:
- Health loss: `"Lose 1 health"`, `"Lose 2 health"`, etc.
- Gold loss: `"Lose 5 gold"`, `"Lose 10 gold"`, etc.

### Event Rolling

Events use D20 + stat modifier vs DC:
```
Roll = 1d20 + stat modifier
Success if Roll >= DC
```

Example:
- Event requires Strength check DC 12
- Player rolls 8, has Strength +4
- Total = 8 + 4 = 12 (Success!)

---

## Teleport System

### Random Teleport by Type

```javascript
teleportToRandomGameOfType(gameType)
```

**Parameters**:
- `gameType` (string|null): Filter by game type, or `null` for any game

**Game Types**:
- `'Deckbuilding'`
- `'Action'`
- `'Traditional'`
- `'Strategy'`
- `null` (any type)

**Example Usage**:
```javascript
// Teleport to any connected game
teleportToRandomGameOfType(null);
teleportToRandomGame();  // Shorthand

// Teleport to a Deckbuilding game
teleportToRandomGameOfType('Deckbuilding');
teleportToRandomDeckbuilder();  // Shorthand
```

**Behavior**:
- Only teleports to games with `connected: true`
- Shows error if no matching games found
- Generates random encounter type (75% combat, 15% event, 10% shop)
- Advances player to the selected game

### Selected Teleport (Player Choice)

```javascript
selectedTeleport(options)
```

**Parameters**:
```javascript
{
  numChoices: 3,              // How many games to show (default: 3)
  year: 2020,                 // Filter by year (optional)
  type: 'Deckbuilding',       // Filter by type (optional)
  tags: ['roguelike', 'rpg'], // Filter by tags - matches ANY tag (optional)
  title: "Choose Your Destination"  // Modal title (default shown)
}
```

**Example Usage**:

Show 3 games from 2020:
```javascript
selectedTeleport({
  numChoices: 3,
  year: 2020,
  title: "Choose a Game from 2020"
});
```

Show 5 Deckbuilding games:
```javascript
selectedTeleport({
  numChoices: 5,
  type: 'Deckbuilding',
  title: "Choose a Deckbuilder"
});
```

Show games with specific tags:
```javascript
selectedTeleport({
  numChoices: 4,
  tags: ['roguelike', 'turn-based'],
  title: "Choose a Roguelike"
});
```

Combine multiple filters:
```javascript
selectedTeleport({
  numChoices: 3,
  year: 2018,
  type: 'Action',
  tags: ['roguelike'],
  title: "Choose a 2018 Action Roguelike"
});
```

**Behavior**:
- Always filters to `connected: true` games first
- Shows modal with clickable game cards
- Displays game name, year, type, and tags
- Player clicks to teleport to chosen game
- Returns `false` if no games match criteria
- If fewer games exist than `numChoices`, shows all matching games

**Filter Logic**:
- `year`: Exact match (`game.year === year`)
- `type`: Exact match (`game.type === type`)
- `tags`: Matches if game has ANY of the specified tags (OR logic)

---

## Combat System

### Enemy Structure

Enemies are defined in `enemies-data.js`:

```javascript
{
  name: "Enemy Name",
  power: "Low" | "Medium" | "High",
  stat: "Strength" | "Dexterity" | "Intelligence" | "Charisma",
  rollCheck: 12,  // DC for the combat check
  successReward: "10 gold",
  failureTrigger: "Lose 2 health"  // Now auto-calculated, just template text
}
```

### Combat Difficulty and Damage

Combat damage is determined by enemy power level:
- **Low**: 1 damage on failure
- **Medium**: 2 damage on failure
- **High**: 3 damage on failure

### Combat Flow

1. Enemy appears with stat check requirement
2. Player rolls 1d20 + relevant stat modifier
3. Compare total to enemy's DC (rollCheck)
4. If success: Player gets reward
5. If failure: Player takes damage based on difficulty

### Curses

When failing combat, player may gain a curse:
- Curses match the failed enemy's stat and power level
- Curses apply -1 penalty to specific stat checks
- Example: "Curse of Weakness (Strength-Medium)" = -1 to Medium Strength checks

---

## Game Data Structure

### Games (games-data.js)

```javascript
{
  name: "Game Name",
  year: 2020,
  type: "Deckbuilding" | "Action" | "Traditional" | "Strategy",
  tags: ["roguelike", "turn-based"],  // Optional
  connected: true,  // Can player reach this game?
  connections: ["Other Game 1", "Other Game 2"]  // Games this connects to
}
```

**Important**: Only games with `connected: true` can be visited by the player.

### Connection Rules

- Connections are directional (A → B doesn't mean B → A)
- Total connections in game: 635
- Connected games form the playable graph
- Unconnected games exist but can't be reached

---

## Creating New Content

### Adding a New Passive Item

1. Add item to `items` array in `games-data.js`:
```javascript
{
  name: "Ring of Power",
  rarity: "rare",
  type: "Passive",
  description: "+3 Strength, +3 Intelligence"
}
```

2. Add effects to `ITEM_EFFECTS` in `js/items.js`:
```javascript
"Ring of Power": {
  onAcquire: () => {
    strength += 3;
    intelligence += 3;
    gameState.strength = strength;
    gameState.intelligence = intelligence;
  }
}
```

3. Update UI displays (automatically handled by `updateGameStats()`)

### Adding a New Usable Item

1. Add item to `items` array in `games-data.js`:
```javascript
{
  name: "Magic Compass",
  rarity: "uncommon",
  type: "Usable",
  description: "Teleport to any game from the 1980s"
}
```

2. Add effects to `ITEM_EFFECTS` in `js/items.js`:
```javascript
"Magic Compass": {
  canUse: () => {
    return gameState.phase === 'selection';
  },
  onUse: () => {
    selectedTeleport({
      numChoices: 5,
      year: 1980,
      title: "Choose a Classic (1980s)"
    });
  }
}
```

### Adding a New Event

Add to `events` array in `events-data.js`:
```javascript
{
  name: "Ancient Puzzle",
  power: "Medium",
  description: "You find an ancient puzzle mechanism...",
  stat: "Intelligence",
  rollCheck: 14,
  successReward: "uncommon item",
  failureConsequence: "Lose 2 health"
}
```

### Adding a New Enemy

Add to `enemies` array in `enemies-data.js`:
```javascript
{
  name: "Shadow Assassin",
  power: "High",
  stat: "Dexterity",
  rollCheck: 18,
  successReward: "20 gold and rare item",
  failureTrigger: "Lose 3 health"  // Auto-calculated based on power
}
```

---

## Tips and Best Practices

### Item Balance
- Common items: +1 to single stat or small effect
- Uncommon items: +2 to single stat or moderate effect
- Rare items: +3 to stat, or multiple effects, or powerful usable abilities
- Items with tradeoffs: +3 to one stat, -1 to another

### Event Balance
- Low difficulty: DC 8-12, small rewards/consequences
- Medium difficulty: DC 13-16, moderate rewards/consequences
- High difficulty: DC 17-20, large rewards/consequences

### Teleport Items
- Random teleports: Good for common/uncommon items
- Filtered teleports: Good for uncommon items
- Player-choice teleports: Good for rare items (more control = more valuable)

### Testing
- Use browser console to test functions:
  ```javascript
  teleportToRandomGame()
  selectedTeleport({ numChoices: 3, year: 2020 })
  acquireItem(getItemByName("Winged Boots"))
  useItem(0)  // Use first item in inventory
  ```

---

## Developer Tools

The game includes a comprehensive dev tools section at the bottom of the page for testing and debugging. This section is divided into three columns:

### Items Dev Tools (📦)

**Add Item**:
- Select a specific item from the dropdown to add it to your inventory
- Click "Add Random Item" to get a random item
- Useful for testing item effects and interactions

**Remove Item**:
- Select an item from your current inventory to remove it
- Click "Remove Random Item" to remove a random item
- Use this to test edge cases and clean up inventory

**Current Inventory**:
- Displays all items currently in the player's inventory
- Auto-updates when items are added or removed

### Curses Dev Tools (😈)

**Add Curse**:
- Select a specific curse from the dropdown (shows curse name, stat, and power level)
- Click "Add Selected Curse" to add it to the active curses list
- Click "Add Random Curse" for a random curse
- Great for testing curse mechanics without failing combat

**Remove Curse**:
- Select a curse from active curses to remove it
- Click "Clear All Curses" to remove all curses at once
- Useful for resetting curse state during testing

**Active Curses**:
- Shows all currently active curses with their details
- Auto-updates when curses are added or removed
- Curses shown here will also appear in the right sidebar during gameplay

### Encounters Dev Tools (⚔️)

**Trigger Combat**:
- Select stat (Strength/Dexterity/Intelligence/Charisma) and power level (Low/Medium/High)
- Click "Start Combat" to immediately trigger a combat encounter
- Bypasses normal encounter randomization for specific testing scenarios

**Trigger Event**:
- Click "Random Event" to trigger a random event encounter
- Uses the same 15% event spawn logic but triggered on demand

**Quick Actions**:
- **Trigger Shop**: Immediately opens the shop modal (requires active run)
- **Trigger Item Choice**: Opens the item reward selection modal (requires active run)
- Perfect for testing shop mechanics and item choices without playing through a game

**Recent Encounters**:
- Shows history of recent combat and event encounters
- Helps track testing progress

### Usage Tips

1. **Testing Items**: Add items to test their effects, then remove them to reset
2. **Testing Curses**: Add curses to see how they appear in the UI and affect gameplay
3. **Testing Combat**: Trigger specific stat/power combats to test difficulty balance
4. **Testing Rewards**: Use Quick Actions to test shop and item reward systems repeatedly

### Important Notes

- Dev tools require an active run to work properly (except for basic add/remove functions)
- Changes made with dev tools affect the active game state but won't persist across browser reloads unless saved
- Use the dev tools to quickly iterate on balance and test edge cases

---

## Common Issues

### Item Effects Not Working
- Check that item name in `ITEM_EFFECTS` exactly matches name in `items` array
- Verify you're updating both the global variable AND `gameState.variableName`
- Call `updateGameStats()` and `updateTopBar()` after stat changes

### Teleport Not Working
- Verify target games have `connected: true`
- Check that filters aren't too restrictive (no matching games)
- Ensure `gameState.phase === 'selection'` for usable items

### Events Not Triggering
- Events have 15% spawn chance (75% combat, 10% shop, 15% event)
- Check that events exist in `events-data.js`
- Verify event structure matches required format
