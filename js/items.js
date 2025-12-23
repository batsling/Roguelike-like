// ===== ITEMS.JS - Item Effects System =====
//
// This module handles:
// - Item acquisition and effect application
// - Modular item effects for easy extension
// - Item stat modifications

// ===== ITEM EFFECTS REGISTRY =====
// Define all item effects here for easy maintenance and extension

const ITEM_EFFECTS = {
  // ===== STAT BOOST ITEMS =====

  "Ballistic Boots": {
    onAcquire: () => {
      dash += 1;
      gameState.dash = dash;
    }
  },

  "More Options": {
    onAcquire: () => {
      fov += 1;
      gameState.fov = fov;
      // Extra option in space choice is handled in game logic
    }
  },

  "Lucky Toe": {
    onAcquire: () => {
      luck += 1;
      gameState.luck = luck;
    }
  },

  "Lunch": {
    onAcquire: () => {
      maxHealth += 1;
      health += 1; // Heal for the same amount as max health gained
      gameState.maxHealth = maxHealth;
      gameState.health = health;
    }
  },

  "D6": {
    onAcquire: () => {
      reroll += 1;
      gameState.reroll = reroll;
    }
  },

  "Sunglasses": {
    onAcquire: () => {
      charisma += 2;
      gameState.charisma = charisma;
    }
  },

  "Oddly Smooth Stone": {
    onAcquire: () => {
      dexterity += 2;
      gameState.dexterity = dexterity;
    }
  },

  "Empty Tome": {
    onAcquire: () => {
      intelligence += 2;
      gameState.intelligence = intelligence;
    }
  },

  "Hollow Heart": {
    onAcquire: () => {
      maxHealth += 2;
      health += 2; // Heal for the same amount as max health gained
      gameState.maxHealth = maxHealth;
      gameState.health = health;
    }
  },

  "Vajra": {
    onAcquire: () => {
      strength += 2;
      gameState.strength = strength;
    }
  },

  // ===== ITEMS WITH TRADEOFFS =====

  "Bowler Hat": {
    onAcquire: () => {
      charisma += 3;
      dexterity -= 1;
      gameState.charisma = charisma;
      gameState.dexterity = dexterity;
    }
  },

  "Wings": {
    onAcquire: () => {
      dexterity += 3;
      intelligence -= 1;
      gameState.dexterity = dexterity;
      gameState.intelligence = intelligence;
    }
  },

  "Campfire": {
    onAcquire: () => {
      intelligence += 3;
      dexterity -= 1;
      gameState.intelligence = intelligence;
      gameState.dexterity = dexterity;
    }
  },

  "Wheat": {
    onAcquire: () => {
      strength += 3;
      intelligence -= 1;
      gameState.strength = strength;
      gameState.intelligence = intelligence;
    }
  },

  "Panda": {
    onAcquire: () => {
      maxHealth += 5;
      health += 5; // Heal for the same amount as max health gained
      luck += 2;
      strength -= 1;
      gameState.maxHealth = maxHealth;
      gameState.health = health;
      gameState.luck = luck;
      gameState.strength = strength;
    }
  },

  // ===== USABLE ITEMS =====

  "Scroll of Teleportation": {
    canUse: () => {
      // Can only use during game selection phase
      return gameState.phase === 'selection';
    },
    onUse: () => {
      // Teleport to a random connected game
      teleportToRandomGame();
    }
  },

  "Ride the Bus": {
    canUse: () => {
      // Can only use during game selection phase
      return gameState.phase === 'selection';
    },
    onUse: () => {
      // Teleport to a random Deckbuilder game
      teleportToRandomDeckbuilder();
    }
  }
};

// ===== ITEM ACQUISITION FUNCTION =====

/**
 * Apply item effects when acquired
 * @param {Object} item - The item being acquired
 */
function applyItemEffects(item) {
  if (!item || !item.name) {
    console.warn('Invalid item:', item);
    return;
  }

  const effects = ITEM_EFFECTS[item.name];

  if (effects) {
    // Apply onAcquire effect if it exists
    if (effects.onAcquire && typeof effects.onAcquire === 'function') {
      effects.onAcquire();
      console.log(`Applied effects for: ${item.name}`);
    }

    // Update UI after applying effects
    updateGameStats();
    updateTopBar();
  } else {
    // No effects defined yet - this is fine for items without passive stats
    console.log(`No effects defined for: ${item.name}`);
  }
}

/**
 * Add item to inventory and apply its effects
 * @param {Object} item - The item to add
 */
function acquireItem(item) {
  if (!item) return;

  // Add to inventory
  inventory.push(item);
  gameState.inventory = [...inventory];

  // Apply item effects
  applyItemEffects(item);

  // Update UI
  updateInventory();

  console.log(`Acquired: ${item.name}`);
}

// ===== HELPER FUNCTIONS =====

/**
 * Get item by name (for debugging/testing)
 * @param {string} name - Item name
 * @returns {Object|null} Item object or null
 */
function getItemByName(name) {
  return items.find(i => i.name === name) || null;
}

/**
 * Check if item has effects defined
 * @param {string} itemName - Item name
 * @returns {boolean} True if effects are defined
 */
function hasItemEffects(itemName) {
  return ITEM_EFFECTS.hasOwnProperty(itemName);
}

// ===== USABLE ITEMS SYSTEM =====

/**
 * Check if an item can be used right now
 * @param {Object} item - The item to check
 * @returns {boolean} True if the item can be used
 */
function canUseItem(item) {
  if (!item || item.type !== 'Usable') return false;

  const effects = ITEM_EFFECTS[item.name];
  if (!effects || !effects.canUse) return false;

  return effects.canUse();
}

/**
 * Use an item from inventory
 * @param {number} itemIndex - Index of item in inventory
 */
function useItem(itemIndex) {
  if (itemIndex < 0 || itemIndex >= inventory.length) {
    console.error('Invalid item index:', itemIndex);
    return;
  }

  const item = inventory[itemIndex];
  if (item.type !== 'Usable') {
    console.warn('Item is not usable:', item.name);
    return;
  }

  if (!canUseItem(item)) {
    console.warn('Cannot use item right now:', item.name);
    return;
  }

  const effects = ITEM_EFFECTS[item.name];
  if (effects && effects.onUse) {
    console.log(`Using item: ${item.name}`);
    effects.onUse();

    // Remove item from inventory after use
    inventory.splice(itemIndex, 1);
    gameState.inventory = [...inventory];

    // Update UI
    updateInventory();

    console.log(`Used and removed: ${item.name}`);
  }
}

/**
 * Teleport to a random connected game
 */
function teleportToRandomGame() {
  // Get all connected games
  const connectedGames = games.filter(g => g.connected === true);

  if (connectedGames.length === 0) {
    console.error('No connected games available!');
    return;
  }

  // Pick a random connected game
  const randomGame = connectedGames[Math.floor(Math.random() * connectedGames.length)];

  console.log(`Teleporting to: ${randomGame.name}`);

  // Clear current choices and advance to the selected game
  clearChoices();
  advanceGame(randomGame.name);
}

/**
 * Teleport to a random Deckbuilder game
 */
function teleportToRandomDeckbuilder() {
  // Get all connected Deckbuilder games
  const deckbuilderGames = games.filter(g => g.connected === true && g.type === 'Deckbuilder');

  if (deckbuilderGames.length === 0) {
    console.error('No connected Deckbuilder games available!');
    alert('No Deckbuilder games available to teleport to!');
    return;
  }

  // Pick a random Deckbuilder game
  const randomGame = deckbuilderGames[Math.floor(Math.random() * deckbuilderGames.length)];

  console.log(`Riding the bus to: ${randomGame.name}`);

  // Clear current choices and advance to the selected game
  clearChoices();
  advanceGame(randomGame.name);
}

// Export functions to global scope
window.applyItemEffects = applyItemEffects;
window.acquireItem = acquireItem;
window.getItemByName = getItemByName;
window.hasItemEffects = hasItemEffects;
window.canUseItem = canUseItem;
window.useItem = useItem;
window.teleportToRandomGame = teleportToRandomGame;
window.teleportToRandomDeckbuilder = teleportToRandomDeckbuilder;
window.ITEM_EFFECTS = ITEM_EFFECTS;
