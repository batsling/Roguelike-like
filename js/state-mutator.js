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
    health = Math.max(0, Math.min(health + delta, maxHealth));
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
    const { updateUI = true, notify = false } = options;

    const oldMaxHealth = maxHealth;
    maxHealth = Math.max(1, maxHealth + delta);
    gameState.maxHealth = maxHealth;

    // Also increase current health if it was at max
    if (health === oldMaxHealth) {
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
    const newValue = oldValue + delta;

    window[statName] = newValue;
    gameState[statName] = newValue;

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

    const itemName = inventory[index];
    inventory.splice(index, 1);
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

    gameState.activeCurses.push(curse);

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

    return true;
  }
};

// Export for use in other files
if (typeof window !== 'undefined') {
  window.StateMutator = StateMutator;
}
