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

// ============================================================
// Top-level curse + game-status helpers (Phase 3 extraction from main.js)
// ============================================================
//
// These are kept as top-level functions (not CurseManager methods) for
// minimum-diff migration from main.js. The naming is inconsistent with
// the CurseManager.* methods above; Phase 4 cleanup may consolidate.
//
// addCurse is a wrapper around StateMutator.addCurse that emits
// notifications + updates the dev-tools curses list. Other callers of
// the same effect should prefer StateMutator.addCurse directly.

function addCurse(curseOrName) {
  // Extract curse name if an object was passed
  const curseName = typeof curseOrName === 'string' ? curseOrName : curseOrName.name;

  if (!curseName) {
    console.error('Invalid curse data:', curseOrName);
    return false;
  }

  // Use StateMutator to add the curse with UI updates
  return StateMutator.addCurse(curseName, { updateUI: true, notify: false });
}

/**
 * Get maximum uses for a curse based on its power level
 * @param {string} power - Power level ('High', 'Medium', 'Low')
 * @returns {number} - Maximum uses
 */
function getCurseMaxUses(power) {
  if (power === 'High') return 3;
  if (power === 'Medium') return 2;
  return 1; // Low or default
}

/**
 * Check and update curse durations after game events
 * @param {string} eventType - Type of event ('game_beaten', etc.)
 */
function checkCurseDurations(eventType = 'game_beaten') {
  if (!gameState || !gameState.activeCurses) return;

  // Initialize tracker if it doesn't exist
  if (!gameState.cursesTracker) {
    gameState.cursesTracker = {};
  }

  // Get list of restriction curses that were verified (from verification modal)
  const cursesToIncrement = gameState.restrictionCursesProcessed || [];

  // Track which curses to remove after iteration
  const cursesToRemove = [];

  // Process each active curse
  gameState.activeCurses.forEach(curse => {
    const trackerId = curse.id || curse.name;

    // Initialize tracker for this curse if it doesn't exist
    if (!gameState.cursesTracker[trackerId]) {
      gameState.cursesTracker[trackerId] = { gamesBeaten: 0 };
    }

    const tracker = gameState.cursesTracker[trackerId];

    // Check if this curse has a game-based duration
    let shouldIncrement = false;
    if (curse.duration && curse.duration.match(/(\d+)\s+game/i)) {
      // If it's a restriction curse, check if it was verified
      if (cursesToIncrement.includes(curse.id)) {
        shouldIncrement = true;
      }
      // If it's a manual curse (not in verification list), always increment
      else if (curse.automatic === 'Manual' || !curse.automatic) {
        shouldIncrement = true;
      }
    }

    // Increment the counter if needed
    if (shouldIncrement) {
      tracker.gamesBeaten = (tracker.gamesBeaten || 0) + 1;
    }

    // Check if curse duration is complete
    if (curse.duration) {
      const match = curse.duration.match(/(\d+)\s+game/i);
      if (match) {
        const requiredGames = parseInt(match[1]);
        if (tracker.gamesBeaten >= requiredGames) {
          cursesToRemove.push(curse);
        }
      }
    }
  });

  // Remove completed curses
  cursesToRemove.forEach(curse => {
    CurseManager.consume(curse);
    const trackerId = curse.id || curse.name;
    delete gameState.cursesTracker[trackerId];

    if (typeof createNotification === 'function') {
      createNotification(`${curse.name} duration complete!`, '#4CAF50', '✨');
    }
  });

  // Clear the processed list for next time
  gameState.restrictionCursesProcessed = [];

  // Update UI if curses were removed
  if (cursesToRemove.length > 0) {
    if (typeof updateActiveCursesList === 'function') {
      updateActiveCursesList();
    }
    if (typeof updateCursesDisplay === 'function') {
      updateCursesDisplay();
    }
  }
}

// ===== GAME STATUS EFFECTS SYSTEM =====

/**
 * Add a status effect to a game
 * @param {string} gameName - Name of the game
 * @param {string} statusName - Name of the status effect (e.g. 'stinky', 'portal')
 * @param {string} icon - Emoji icon for the status (optional, will be looked up if not provided)
 */
function addGameStatus(gameName, statusName, icon) {
  if (!gameState.gameStatusEffects) {
    gameState.gameStatusEffects = {};
  }

  if (!gameState.gameStatusEffects[gameName]) {
    gameState.gameStatusEffects[gameName] = [];
  }

  // Check if status already exists
  const existing = gameState.gameStatusEffects[gameName].find(s => s.name === statusName);
  if (existing) {
    return;
  }

  // Look up icon if not provided
  if (!icon) {
    const statusIcons = {
      'charmed': '💕',
      'devilish': '👹',
      'holy': '✨',
      'marked': '🎯',
      'portal': '🌀',
      'shielded': '🛡️',
      'shocked': '⚡',
      'soaked': '💧',
      'stinky': '💩',
      'timed': '⏱️'
    };
    icon = statusIcons[statusName.toLowerCase()] || '❓';
  }

  gameState.gameStatusEffects[gameName].push({
    name: statusName,
    icon: icon
  });


  // Refresh the display if we're looking at this game
  if (typeof updateGameDisplay === 'function') {
    updateGameDisplay();
  }
}

/**
 * Remove a status effect from a game
 * @param {string} gameName - Name of the game
 * @param {string} statusName - Name of the status effect to remove
 */
function removeGameStatus(gameName, statusName) {
  if (!gameState.gameStatusEffects || !gameState.gameStatusEffects[gameName]) {
    return;
  }

  const index = gameState.gameStatusEffects[gameName].findIndex(s => s.name === statusName);
  if (index !== -1) {
    gameState.gameStatusEffects[gameName].splice(index, 1);

    // Clean up empty arrays
    if (gameState.gameStatusEffects[gameName].length === 0) {
      delete gameState.gameStatusEffects[gameName];
    }

    // Refresh the display
    if (typeof updateGameDisplay === 'function') {
      updateGameDisplay();
    }
  }
}

/**
 * Check if a game has a specific status effect
 * @param {string} gameName - Name of the game
 * @param {string} statusName - Name of the status effect
 * @returns {boolean} - True if the game has the status
 */
function hasGameStatus(gameName, statusName) {
  if (!gameState.gameStatusEffects || !gameState.gameStatusEffects[gameName]) {
    return false;
  }

  return gameState.gameStatusEffects[gameName].some(s => s.name === statusName);
}

/**
 * Get all status effects for a game
 * @param {string} gameName - Name of the game
 * @returns {Array} - Array of status objects
 */
function getGameStatuses(gameName) {
  if (!gameState.gameStatusEffects || !gameState.gameStatusEffects[gameName]) {
    return [];
  }

  return gameState.gameStatusEffects[gameName];
}

/**
 * Get all games with a specific status
 * @param {string} statusName - Name of the status effect
 * @returns {Array} - Array of game names
 */
function getGamesWithStatus(statusName) {
  if (!gameState.gameStatusEffects) {
    return [];
  }

  const gamesWithStatus = [];
  for (const [gameName, statuses] of Object.entries(gameState.gameStatusEffects)) {
    if (statuses.some(s => s.name === statusName)) {
      gamesWithStatus.push(gameName);
    }
  }

  return gamesWithStatus;
}

/**
 * Trigger status effects when visiting a game
 * Status effects scale by difficulty: Low (0-4 games), Medium (5-9), High (10+)
 * @param {string} gameName - Name of the game being visited
 */
function triggerGameStatusEffects(gameName) {
  const statuses = getGameStatuses(gameName);
  if (!statuses || statuses.length === 0) return;

  // Calculate difficulty tier based on games beaten (same as combat)
  const gamesBeaten = gameState.totalGamesBeaten || 0;
  const _status_thresholds = (typeof DIFFICULTY_THRESHOLDS !== 'undefined') ? DIFFICULTY_THRESHOLDS : { MEDIUM: 4, HARD: 8, INSANE: 12 };
  let difficultyTier = 'Low';
  let curseSuffix = 'I';

  if (gamesBeaten >= _status_thresholds.HARD) {
    difficultyTier = 'High';
    curseSuffix = 'III';
  } else if (gamesBeaten >= _status_thresholds.MEDIUM) {
    difficultyTier = 'Medium';
    curseSuffix = 'II';
  }


  // Process each status effect
  statuses.forEach(status => {
    let message = '';
    let isPositive = false;

    switch(status.name.toLowerCase()) {
      case 'charmed':
        // Give Curse of Affection scaled by difficulty
        const affectionCurseName = `Curse of Affection ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const affectionCurse = CURSES_DATA.find(c => c.name === affectionCurseName);
          if (affectionCurse && typeof addCurse === 'function') {
            addCurse(affectionCurse);
            message = `${status.icon} Charmed! Gained ${affectionCurseName}`;
          }
        }
        break;

      case 'devilish':
        // Lose 2 health
        StateMutator.modifyHealth(-2);
        message = `${status.icon} Devilish aura deals 2 damage!`;
        break;

      case 'holy': {
        // Gain 2 health
        const oldHealth = health;
        StateMutator.modifyHealth(2);
        message = `${status.icon} Holy blessing restores ${health - oldHealth} health!`;
        isPositive = true;
        break;
      }

      case 'marked':
        // Give Curse of the Hunter scaled by difficulty
        const hunterCurseName = `Curse of the Hunter ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const hunterCurse = CURSES_DATA.find(c => c.name === hunterCurseName);
          if (hunterCurse && typeof addCurse === 'function') {
            addCurse(hunterCurse);
            message = `${status.icon} Marked! Gained ${hunterCurseName}`;
          }
        }
        break;

      case 'portal':
        // Portal is handled by exploration.js, no trigger effect
        break;

      case 'shielded':
        // Give Curse of Obstruction scaled by difficulty
        const obstructionCurseName = `Curse of Obstruction ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const obstructionCurse = CURSES_DATA.find(c => c.name === obstructionCurseName);
          if (obstructionCurse && typeof addCurse === 'function') {
            addCurse(obstructionCurse);
            message = `${status.icon} Shielded! Gained ${obstructionCurseName}`;
          }
        }
        break;

      case 'shocked':
        // Give Curse of the Dazed scaled by difficulty
        const dazedCurseName = `Curse of the Dazed ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const dazedCurse = CURSES_DATA.find(c => c.name === dazedCurseName);
          if (dazedCurse && typeof addCurse === 'function') {
            addCurse(dazedCurse);
            message = `${status.icon} Shocked! Gained ${dazedCurseName}`;
          }
        }
        break;

      case 'soaked':
        // Give Curse of the Damp scaled by difficulty
        const dampCurseName = `Curse of the Damp ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const dampCurse = CURSES_DATA.find(c => c.name === dampCurseName);
          if (dampCurse && typeof addCurse === 'function') {
            addCurse(dampCurse);
            message = `${status.icon} Soaked! Gained ${dampCurseName}`;
          }
        }
        break;

      case 'stinky':
        // Stinky is handled by exploration.js, no trigger effect
        break;

      case 'timed':
        // Give Curse of Haste scaled by difficulty
        const hasteCurseName = `Curse of Haste ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const hasteCurse = CURSES_DATA.find(c => c.name === hasteCurseName);
          if (hasteCurse && typeof addCurse === 'function') {
            addCurse(hasteCurse);
            message = `${status.icon} Timed! Gained ${hasteCurseName}`;
          }
        }
        break;
    }

    if (message) {
      showNotification(message, isPositive ? 'positive' : 'negative');
    }
  });

  // Update top bar to reflect health/curse changes
  if (typeof updateTopBar === 'function') {
    updateTopBar();
  }

  // Check for death
  if (health <= 0) {
    StateMutator.setHealth(0);
    if (typeof handleDeath === 'function') {
      handleDeath('status effect');
    }
  }
}

if (typeof window !== 'undefined') {
  window.addCurse                 = addCurse;
  window.getCurseMaxUses          = getCurseMaxUses;
  window.checkCurseDurations      = checkCurseDurations;
  window.addGameStatus            = addGameStatus;
  window.removeGameStatus         = removeGameStatus;
  window.hasGameStatus            = hasGameStatus;
  window.getGameStatuses          = getGameStatuses;
  window.getGamesWithStatus       = getGamesWithStatus;
  window.triggerGameStatusEffects = triggerGameStatusEffects;
}


// Phase 5: window-exports added for ESM transition (functions/vars called cross-file).
window.CurseManager = CurseManager;
window.addCurse = addCurse;
window.addGameStatus = addGameStatus;
window.checkCurseDurations = checkCurseDurations;
window.getCurseMaxUses = getCurseMaxUses;
window.getGameStatuses = getGameStatuses;
window.getGamesWithStatus = getGamesWithStatus;
window.hasGameStatus = hasGameStatus;
window.removeGameStatus = removeGameStatus;
window.triggerGameStatusEffects = triggerGameStatusEffects;
