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
      health += 3;
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
      gameState.maxHealth = maxHealth;
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
      luck += 2;
      strength -= 1;
      gameState.maxHealth = maxHealth;
      gameState.luck = luck;
      gameState.strength = strength;
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

// Export functions to global scope
window.applyItemEffects = applyItemEffects;
window.acquireItem = acquireItem;
window.getItemByName = getItemByName;
window.hasItemEffects = hasItemEffects;
window.ITEM_EFFECTS = ITEM_EFFECTS;
