/**
 * State Mutator - Centralized state management utilities
 * Handles all game state mutations with consistent UI updates and notifications
 */

const StateMutator = {
  /**
   * Modify player health with bounds checking and UI updates
   * @param {number} delta - Amount to change health by (positive or negative)
   * @param {Object} options - Configuration options
   * @param {boolean} options.updateUI - Whether to update UI (default: true)
   * @param {boolean} options.notify - Whether to show notification (default: false)
   * @param {string} options.notifyMessage - Custom notification message
   * @returns {Object} - { oldHealth, newHealth, changed }
   */
  modifyHealth(delta, options = {}) {
    const { updateUI = true, notify = false, notifyMessage = null } = options;

    const oldHealth = health;
    let effectiveDelta = delta;

    // Check for Reactive Trauma Plate - prevents lethal damage once
    if (delta < 0 && (health + delta) <= 0) {
      const traumaPlateIndex = inventory.findIndex(item => item.name === 'Reactive Trauma Plate');
      if (traumaPlateIndex !== -1) {

        // Remove the item
        if (inventory[traumaPlateIndex].quantity && inventory[traumaPlateIndex].quantity > 1) {
          inventory[traumaPlateIndex].quantity--;
        } else {
          inventory.splice(traumaPlateIndex, 1);
        }
        gameState.inventory = [...inventory];

        // Negate all damage (keep health at current value)
        effectiveDelta = 0;

        // Show notification
        setTimeout(() => {
          if (typeof createNotification === 'function') {
            createNotification('Reactive Trauma Plate negated all damage!', '#ff6b00', '🛡️');
          }
        }, 100);

        // Update inventory UI
        if (typeof updateInventory === 'function') {
          updateInventory();
        }
      }
    }

    health = Math.max(0, Math.min(health + effectiveDelta, maxHealth));
    gameState.health = health;

    if (updateUI) {
      if (typeof updateTopBar === 'function') updateTopBar();
      if (typeof updateHealthDisplay === 'function') updateHealthDisplay();
      if (typeof updateGameStats === 'function') updateGameStats();
    }

    if (notify && delta !== 0) {
      const message = notifyMessage || `${delta > 0 ? '+' : ''}${delta} Health`;
      const color = delta > 0 ? COLORS.SUCCESS : COLORS.DANGER;
      const icon = delta > 0 ? '💚' : '💔';
      if (typeof createNotification === 'function') {
        createNotification(message, color, icon);
      }
    }

    return { oldHealth, newHealth: health, changed: oldHealth !== health };
  },

  /**
   * Modify maximum health with UI updates
   * @param {number} delta - Amount to change max health by
   * @param {Object} options - Configuration options
   * @returns {Object} - { oldMaxHealth, newMaxHealth, changed }
   */
  modifyMaxHealth(delta, options = {}) {
    const { updateUI = true, notify = false, onlyMax = false } = options;

    const oldMaxHealth = maxHealth;
    maxHealth = Math.max(1, maxHealth + delta);
    gameState.maxHealth = maxHealth;

    // Also increase current health if it was at max — unless onlyMax is set
    if (!onlyMax && health === oldMaxHealth) {
      health = maxHealth;
      gameState.health = health;
    }

    if (updateUI) {
      if (typeof updateTopBar === 'function') updateTopBar();
      if (typeof updateHealthDisplay === 'function') updateHealthDisplay();
      if (typeof updateGameStats === 'function') updateGameStats();
    }

    if (notify && delta !== 0) {
      const message = `${delta > 0 ? '+' : ''}${delta} Max Health`;
      if (typeof createNotification === 'function') {
        createNotification(message, COLORS.INFO, '💪');
      }
    }

    return { oldMaxHealth, newMaxHealth: maxHealth, changed: oldMaxHealth !== maxHealth };
  },

  /**
   * Modify maximum energy with UI updates
   * @param {number} delta - Amount to change max energy by
   * @param {Object} options - Configuration options
   * @returns {Object} - { oldMaxEnergy, newMaxEnergy, changed }
   */
  modifyMaxEnergy(delta, options = {}) {
    const { updateUI = true, notify = false } = options;

    const oldMaxEnergy = gameState.maxEnergy || 2;
    const newMaxEnergy = Math.max(1, oldMaxEnergy + delta);
    gameState.maxEnergy = newMaxEnergy;

    if (updateUI) {
      if (typeof updateTopBar === 'function') updateTopBar();
      if (typeof updateGameStats === 'function') updateGameStats();
    }

    if (notify && delta !== 0) {
      const message = `${delta > 0 ? '+' : ''}${delta} Max Energy`;
      if (typeof createNotification === 'function') {
        createNotification(message, COLORS.INFO, '⚡');
      }
    }

    return { oldMaxEnergy, newMaxEnergy, changed: oldMaxEnergy !== newMaxEnergy };
  },

  /**
   * Modify discovery stat with UI updates
   * @param {number} delta - Amount to change discovery by
   * @param {Object} options - Configuration options
   * @returns {Object} - { oldValue, newValue, changed }
   */
  modifyDiscovery(delta, options = {}) {
    const { updateUI = true, notify = false } = options;

    const oldValue = discovery || 0;
    discovery = oldValue + delta;
    gameState.discovery = discovery;

    if (updateUI) {
      if (typeof updateGameStats === 'function') updateGameStats();
      if (typeof updateTopBar === 'function') updateTopBar();
    }

    if (notify && delta !== 0) {
      const message = `${delta > 0 ? '+' : ''}${delta} Discovery`;
      if (typeof createNotification === 'function') {
        createNotification(message, COLORS.INFO, '🔍');
      }
    }

    return { oldValue, newValue: discovery, changed: oldValue !== discovery };
  },

  /**
   * Modify player gold with UI updates
   * @param {number} delta - Amount to change gold by
   * @param {Object} options - Configuration options
   * @returns {Object} - { oldGold, newGold, changed }
   */
  modifyGold(delta, options = {}) {
    const { updateUI = true, notify = false, notifyMessage = null } = options;

    const oldGold = gold;
    gold = Math.max(0, gold + delta);
    gameState.gold = gold;

    if (updateUI) {
      if (typeof updateTopBar === 'function') updateTopBar();
      if (typeof updateGoldDisplay === 'function') updateGoldDisplay();
      if (typeof updateGameStats === 'function') updateGameStats();
    }

    if (notify && delta !== 0) {
      const message = notifyMessage || `${delta > 0 ? '+' : ''}${delta} Gold`;
      const color = delta > 0 ? COLORS.GOLD : COLORS.WARNING;
      const icon = delta > 0 ? '💰' : '💸';
      if (typeof createNotification === 'function') {
        createNotification(message, color, icon);
      }
    }

    return { oldGold, newGold: gold, changed: oldGold !== gold };
  },

  /**
   * Modify a player stat (strength, dexterity, etc.)
   * @param {string} statName - Name of stat to modify
   * @param {number} delta - Amount to change stat by
   * @param {Object} options - Configuration options
   * @returns {Object} - { oldValue, newValue, changed }
   */
  modifyStat(statName, delta, options = {}) {
    const { updateUI = true, notify = false } = options;

    const validStats = ['strength', 'dexterity', 'intelligence', 'charisma', 'luck'];

    if (!validStats.includes(statName)) {
      console.error(`Invalid stat name: ${statName}`);
      return { oldValue: 0, newValue: 0, changed: false };
    }

    const oldValue = window[statName] || 0;
    let newValue = oldValue + delta;

    window[statName] = newValue;
    gameState[statName] = newValue;

    // Rock Bottom: prevent stat from falling below its historical peak
    if (typeof enforceRockBottom === 'function') {
      enforceRockBottom(statName, oldValue);
      newValue = (typeof window[statName] !== 'undefined' ? window[statName] : newValue) || newValue;
    }

    if (updateUI) {
      if (typeof updateGameStats === 'function') updateGameStats();
      if (typeof updateTopBar === 'function') updateTopBar();
    }

    if (notify && delta !== 0) {
      const statNameCap = statName.charAt(0).toUpperCase() + statName.slice(1);
      const message = `${delta > 0 ? '+' : ''}${delta} ${statNameCap}`;
      const color = COLORS.STATS[statName] || COLORS.INFO;
      if (typeof createNotification === 'function') {
        createNotification(message, color, '⚡');
      }
    }

    return { oldValue, newValue, changed: oldValue !== newValue };
  },

  /**
   * Modify an ability count (skip, reroll, dash)
   * @param {string} abilityName - Name of ability to modify
   * @param {number} delta - Amount to change ability by
   * @param {Object} options - Configuration options
   * @returns {Object} - { oldValue, newValue, changed }
   */
  modifyAbility(abilityName, delta, options = {}) {
    const { updateUI = true, notify = false } = options;

    const validAbilities = ['skip', 'reroll', 'dash'];

    if (!validAbilities.includes(abilityName)) {
      console.error(`Invalid ability name: ${abilityName}`);
      return { oldValue: 0, newValue: 0, changed: false };
    }

    const oldValue = window[abilityName] || 0;
    const newValue = Math.max(0, oldValue + delta);

    window[abilityName] = newValue;
    gameState[abilityName] = newValue;

    if (updateUI) {
      if (typeof updateAbilitiesDisplay === 'function') updateAbilitiesDisplay();
      if (typeof updateTopBar === 'function') updateTopBar();
    }

    if (notify && delta !== 0) {
      const abilityIcon = { skip: '⏭', reroll: '🔄', dash: '⚡' }[abilityName];
      const message = `${delta > 0 ? '+' : ''}${delta} ${abilityName.charAt(0).toUpperCase() + abilityName.slice(1)}`;
      if (typeof createNotification === 'function') {
        createNotification(message, COLORS.INFO, abilityIcon);
      }
    }

    return { oldValue, newValue, changed: oldValue !== newValue };
  },

  /**
   * Add an item to inventory
   * @param {string} itemName - Name of item to add
   * @param {Object} options - Configuration options
   * @returns {boolean} - Success status
   */
  addItem(itemName, options = {}) {
    const { updateUI = true, notify = false } = options;

    if (!Array.isArray(inventory)) {
      console.error('Inventory is not an array');
      return false;
    }

    inventory.push(itemName);
    gameState.inventory = inventory;

    if (updateUI && typeof updateInventory === 'function') {
      updateInventory();
    }

    if (notify) {
      if (typeof createNotification === 'function') {
        createNotification(`Acquired: ${itemName}`, COLORS.SUCCESS, '📦');
      }
    }

    return true;
  },

  /**
   * Remove an item from inventory
   * @param {number|string} itemIndexOrName - Index or name of item to remove
   * @param {Object} options - Configuration options
   * @returns {boolean} - Success status
   */
  removeItem(itemIndexOrName, options = {}) {
    const { updateUI = true, notify = false } = options;

    if (!Array.isArray(inventory)) {
      console.error('Inventory is not an array');
      return false;
    }

    let index;
    if (typeof itemIndexOrName === 'number') {
      index = itemIndexOrName;
    } else {
      index = inventory.indexOf(itemIndexOrName);
    }

    if (index < 0 || index >= inventory.length) {
      console.error('Invalid item index:', itemIndexOrName);
      return false;
    }

    const item = inventory[index];
    const itemName = typeof item === 'string' ? item : item.name;

    // Handle quantity for item stacking
    if (item.quantity && item.quantity > 1) {
      item.quantity--;
    } else {
      inventory.splice(index, 1);
    }
    gameState.inventory = inventory;

    if (updateUI && typeof updateInventory === 'function') {
      updateInventory();
    }

    if (notify) {
      if (typeof createNotification === 'function') {
        createNotification(`Used: ${itemName}`, COLORS.WARNING, '✨');
      }
    }

    return true;
  },

  /**
   * Add a curse to active curses
   * @param {string} curseName - Name of curse to add
   * @param {Object} options - Configuration options
   * @returns {boolean} - Success status
   */
  addCurse(curseName, options = {}) {
    const { updateUI = true, notify = false } = options;

    if (!curses) {
      console.error('Curses data not loaded');
      return false;
    }

    const curse = curses.find(c => c.name === curseName);
    if (!curse) {
      console.error(`Curse not found: ${curseName}`);
      return false;
    }

    if (!Array.isArray(gameState.activeCurses)) {
      gameState.activeCurses = [];
    }

    // Create a unique instance of the curse with a unique ID
    const curseInstance = {
      ...curse,
      _id: `${curseName}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
    };

    gameState.activeCurses.push(curseInstance);

    // Parse description for "Add X to (your) Deck" and add the card
    const descMatch = (curseInstance.description || '').match(/[Aa]dd ([^.]+?) to(?: your)? [Dd]eck/);
    if (descMatch) {
      const cardRef = descMatch[1].trim();
      let cardToAdd = null;
      const allCards = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [];
      if (/a random curse/i.test(cardRef)) {
        const curseCards = allCards.filter(c => c.type === 'Curse');
        if (curseCards.length > 0) cardToAdd = curseCards[Math.floor(Math.random() * curseCards.length)];
      } else {
        cardToAdd = allCards.find(c => c.name === cardRef);
      }
      const addFn = (typeof window !== 'undefined' && typeof window.addCardToDeck === 'function')
        ? window.addCardToDeck
        : (typeof addCardToDeck === 'function' ? addCardToDeck : null);
      if (cardToAdd && addFn) {
        addFn({ ...cardToAdd });
        curseInstance._cardAdded = cardToAdd.name;
      }
    }

    if (updateUI) {
      if (typeof updateCursesDisplay === 'function') updateCursesDisplay();
      if (typeof updateTopBar === 'function') updateTopBar();
    }

    if (notify) {
      if (typeof createNotification === 'function') {
        createNotification(`Cursed: ${curseName}`, COLORS.DANGER, '😈');
      }
    }

    return true;
  },

  /**
   * Remove a curse from active curses
   * @param {string} curseName - Name of curse to remove
   * @param {Object} options - Configuration options
   * @returns {boolean} - Success status
   */
  removeCurse(curseName, options = {}) {
    const { updateUI = true, notify = false } = options;

    if (!Array.isArray(gameState.activeCurses)) {
      return false;
    }

    const index = gameState.activeCurses.findIndex(c => c.name === curseName);
    if (index === -1) {
      return false;
    }

    // Remove associated curse card from deck if any
    const curseObj = gameState.activeCurses[index];
    if (curseObj && curseObj._cardAdded && Array.isArray(gameState.deck)) {
      const cardIdx = gameState.deck.findIndex(c => c.name === curseObj._cardAdded);
      if (cardIdx !== -1) {
        gameState.deck.splice(cardIdx, 1);
        if (typeof createNotification === 'function') {
          createNotification(`${curseObj._cardAdded} removed from deck.`, '#888', '🗑️');
        }
      }
    }

    gameState.activeCurses.splice(index, 1);

    if (updateUI) {
      if (typeof updateCursesDisplay === 'function') updateCursesDisplay();
      if (typeof updateTopBar === 'function') updateTopBar();
    }

    if (notify) {
      if (typeof createNotification === 'function') {
        createNotification(`Curse removed: ${curseName}`, COLORS.SUCCESS, '✨');
      }
    }

    // Trigger onCurseRemoved effects for triggered items (like Golden Beetle)
    if (typeof triggerOnCurseRemoved === 'function') {
      triggerOnCurseRemoved();
    }

    return true;
  }
};

// Export for use in other files
if (typeof window !== 'undefined') {
  window.StateMutator = StateMutator;
}
