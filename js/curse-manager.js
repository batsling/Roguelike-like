/**
 * Curse Manager - Centralized curse handling utilities
 * Eliminates duplicate curse finding, applying, and consuming logic
 */

const CurseManager = {
  /**
   * Find all curses of a specific type
   * @param {string} type - Type keyword to search for (e.g., 'weakness', 'shroud', 'debt')
   * @returns {Array} - Array of matching curse objects
   */
  findByType(type) {
    if (!Array.isArray(gameState.activeCurses)) {
      return [];
    }

    const lowerType = type.toLowerCase();
    return gameState.activeCurses.filter(c =>
      c.name.toLowerCase().includes(lowerType)
    );
  },

  /**
   * Find the first curse of a specific type
   * @param {string} type - Type keyword to search for
   * @returns {Object|null} - First matching curse or null
   */
  findFirstByType(type) {
    const curses = this.findByType(type);
    return curses.length > 0 ? curses[0] : null;
  },

  /**
   * Check if player has a curse of a specific type
   * @param {string} type - Type keyword to search for
   * @returns {boolean} - Whether player has this type of curse
   */
  hasType(type) {
    return this.findByType(type).length > 0;
  },

  /**
   * Find curse by exact name
   * @param {string} name - Exact curse name
   * @returns {Object|null} - Matching curse or null
   */
  findByName(name) {
    if (!Array.isArray(gameState.activeCurses)) {
      return null;
    }

    return gameState.activeCurses.find(c => c.name === name) || null;
  },

  /**
   * Apply a curse's effect (for consuming/single-use curses)
   * @param {Object} curse - Curse object to apply
   * @returns {number} - Damage/penalty value from curse power
   */
  apply(curse) {
    if (!curse || !curse.power) {
      return 0;
    }

    return this.getPenalty(curse.power);
  },

  /**
   * Get penalty value from curse power
   * @param {string|number} power - Curse power level ("Low"/"Medium"/"High" or 1-4)
   * @returns {number} - Penalty value
   */
  getPenalty(power) {
    // Convert string power to numeric if needed
    const powerMap = { Low: 1, Medium: 2, High: 3 };
    const numericPower = typeof power === 'string' ? powerMap[power] : power;
    return CURSE_CONFIG.DAMAGE[numericPower] || 0;
  },

  /**
   * Consume a curse (remove it after use)
   * @param {Object|string} curseOrName - Curse object or curse name
   * @param {Object} options - Options
   * @param {boolean} options.updateUI - Whether to update UI (default: true)
   * @param {boolean} options.notify - Whether to show notification (default: false)
   * @returns {boolean} - Whether curse was found and removed
   */
  consume(curseOrName, options = {}) {
    const { updateUI = true, notify = false } = options;

    if (!Array.isArray(gameState.activeCurses)) {
      return false;
    }

    let index = -1;
    let curseName;

    // If it's a curse object with an _id, find by ID (for unique instances)
    if (typeof curseOrName === 'object' && curseOrName._id) {
      index = gameState.activeCurses.findIndex(c => c._id === curseOrName._id);
      curseName = curseOrName.name;
    } else {
      // Fall back to name-based removal (for backward compatibility)
      curseName = typeof curseOrName === 'string' ? curseOrName : curseOrName.name;
      index = gameState.activeCurses.findIndex(c => c.name === curseName);
    }

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
      if (typeof updateCursesDisplay === 'function') {
        updateCursesDisplay();
      }
      if (typeof updateTopBar === 'function') {
        updateTopBar();
      }
    }

    if (notify && typeof createNotification === 'function') {
      const color = (typeof COLORS !== 'undefined' && COLORS.WARNING) || '#ff9800';
      createNotification(`${curseName} consumed`, color, '✨');
    }

    return true;
  },

  /**
   * Apply and consume a weakness curse (common pattern)
   * Reduces damage by curse power, then removes the curse
   * @param {number} baseDamage - Base damage before curse reduction
   * @returns {Object} - { reducedDamage, curseFound, curseConsumed }
   */
  applyWeakness(baseDamage) {
    const weaknessCurse = this.findFirstByType('weakness');

    if (!weaknessCurse) {
      return {
        reducedDamage: baseDamage,
        curseFound: false,
        curseConsumed: false
      };
    }

    const penalty = this.getPenalty(weaknessCurse.power);
    const reducedDamage = Math.max(0, baseDamage - penalty);
    const consumed = this.consume(weaknessCurse, { updateUI: true, notify: false });

    return {
      reducedDamage,
      curseFound: true,
      curseConsumed: consumed,
      curseReduction: penalty
    };
  },

  /**
   * Apply and consume a debt curse (common pattern)
   * Reduces gold gain by curse power, then removes the curse
   * @param {number} baseGold - Base gold before curse reduction
   * @returns {Object} - { reducedGold, curseFound, curseConsumed }
   */
  applyDebt(baseGold) {
    const debtCurse = this.findFirstByType('debt');

    if (!debtCurse) {
      return {
        reducedGold: baseGold,
        curseFound: false,
        curseConsumed: false
      };
    }

    const penalty = this.getPenalty(debtCurse.power);
    const reducedGold = Math.max(0, baseGold - penalty);
    const consumed = this.consume(debtCurse, { updateUI: true, notify: false });

    return {
      reducedGold,
      curseFound: true,
      curseConsumed: consumed,
      curseReduction: penalty
    };
  },

  /**
   * Check and apply Curse of Shroud (stinky games logic)
   * @returns {Object} - { hasShroud, stinkyGamesCount }
   */
  checkShroud() {
    const shroudCurse = this.findFirstByType('shroud');

    if (!shroudCurse) {
      return {
        hasShroud: false,
        stinkyGamesCount: 0
      };
    }

    return {
      hasShroud: true,
      stinkyGamesCount: CURSE_CONFIG.SHROUD.STINKY_GAMES
    };
  },

  /**
   * Get all active curses
   * @returns {Array} - Array of all active curse objects
   */
  getAll() {
    return Array.isArray(gameState.activeCurses) ? gameState.activeCurses : [];
  },

  /**
   * Get curse count
   * @returns {number} - Number of active curses
   */
  getCount() {
    return this.getAll().length;
  },

  /**
   * Clear all curses
   * @param {Object} options - Options
   * @param {boolean} options.updateUI - Whether to update UI (default: true)
   * @param {boolean} options.notify - Whether to show notification (default: false)
   */
  clearAll(options = {}) {
    const { updateUI = true, notify = false } = options;

    if (!Array.isArray(gameState.activeCurses)) {
      return;
    }

    const count = gameState.activeCurses.length;
    gameState.activeCurses = [];

    if (updateUI) {
      if (typeof updateCursesDisplay === 'function') {
        updateCursesDisplay();
      }
      if (typeof updateTopBar === 'function') {
        updateTopBar();
      }
    }

    if (notify && count > 0 && typeof createNotification === 'function') {
      const color = (typeof COLORS !== 'undefined' && COLORS.SUCCESS) || '#4CAF50';
      createNotification(`All ${count} curses removed!`, color, '✨');
    }
  }
};

// Export for use in other files
if (typeof window !== 'undefined') {
  window.CurseManager = CurseManager;
}
