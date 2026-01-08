// ===== ITEMS.JS - Item Effects System =====
//
// This module handles:
// - Item acquisition and effect application
// - Modular item effects for easy extension
// - Item stat modifications

// ===== HELPER FUNCTIONS =====

// Create and display a notification popup
function createNotification(text, bgColor = '#8B4513', emoji = '') {
  const notification = document.createElement('div');
  notification.textContent = `${emoji} ${text}`;
  notification.style.cssText = `
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    padding: 30px 50px;
    background: ${bgColor};
    color: white;
    border: 3px solid rgba(255, 255, 255, 0.3);
    border-radius: 12px;
    font-size: 24px;
    font-weight: bold;
    z-index: 10000;
    box-shadow: 0 8px 24px rgba(0,0,0,0.5);
    text-align: center;
    opacity: 0;
    transition: opacity 0.3s;
  `;
  document.body.appendChild(notification);

  setTimeout(() => notification.style.opacity = '1', 10);
  setTimeout(() => notification.style.opacity = '0', 1500);
  setTimeout(() => notification.remove(), 1800);
}

// Update a stat and sync it with gameState
function updateStat(statName, change) {
  const statMap = {
    strength: () => { strength += change; gameState.strength = strength; },
    dexterity: () => { dexterity += change; gameState.dexterity = dexterity; },
    intelligence: () => { intelligence += change; gameState.intelligence = intelligence; },
    charisma: () => { charisma += change; gameState.charisma = charisma; },
    dash: () => { dash += change; gameState.dash = dash; },
    reroll: () => { reroll += change; gameState.reroll = reroll; },
    skip: () => { skip += change; gameState.skip = skip; },
    discovery: () => { discovery += change; gameState.discovery = discovery; },
    fov: () => { fov += change; gameState.fov = fov; }
  };

  statMap[statName]?.();
  if (typeof updateGameStats === 'function') updateGameStats();
}

// Determine encounter type based on weighted roll
function determineEncounterType() {
  const encounterRoll = Math.random() * 100;
  if (encounterRoll < 75) return 'combat';
  if (encounterRoll < 90) return 'event';
  return 'shop';
}

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
      StateMutator.modifyMaxHealth(1);
      StateMutator.modifyHealth(4);
    }
  },

  "D6": {
    onAcquire: () => {
      StateMutator.modifyAbility('reroll', 1);
    }
  },

  "Sunglasses": {
    onAcquire: () => {
      StateMutator.modifyStat('charisma', 2);
    }
  },

  "Oddly Smooth Stone": {
    onAcquire: () => {
      StateMutator.modifyStat('dexterity', 2);
    }
  },

  "Empty Tome": {
    onAcquire: () => {
      StateMutator.modifyStat('intelligence', 2);
    }
  },

  "Hollow Heart": {
    onAcquire: () => {
      StateMutator.modifyMaxHealth(2);
      StateMutator.modifyHealth(2);
    }
  },

  "Vajra": {
    onAcquire: () => {
      StateMutator.modifyStat('strength', 2);
    }
  },

  // ===== ITEMS WITH TRADEOFFS =====

  "Bowler Hat": {
    onAcquire: () => {
      StateMutator.modifyStat('charisma', 3);
      StateMutator.modifyStat('dexterity', -1);
    }
  },

  "Wings": {
    onAcquire: () => {
      StateMutator.modifyStat('dexterity', 3);
      StateMutator.modifyStat('intelligence', -1);
    }
  },

  "Campfire": {
    onAcquire: () => {
      StateMutator.modifyStat('intelligence', 3);
      StateMutator.modifyStat('dexterity', -1);
    }
  },

  "Wheat": {
    onAcquire: () => {
      StateMutator.modifyStat('strength', 3);
      StateMutator.modifyStat('intelligence', -1);
    }
  },

  "Panda": {
    onAcquire: () => {
      StateMutator.modifyMaxHealth(5);
      StateMutator.modifyHealth(5);
      StateMutator.modifyStat('luck', 2);
      StateMutator.modifyStat('strength', -1);
    }
  },

  // ===== TRIGGERED ITEMS =====

  "Charm of the Vampire": {
    onAcquire: () => {
      // No immediate effect on acquire
      console.log('Acquired Charm of the Vampire - will trigger on enemy defeats');
    },
    onEnemyDefeated: () => {
      // 50% base chance + (5% * luck)
      const baseChance = 0.50;
      const luckBonus = (luck || 0) * 0.05;
      const totalChance = baseChance + luckBonus;

      const roll = Math.random();
      console.log(`Charm of the Vampire: rolled ${roll.toFixed(2)} vs ${totalChance.toFixed(2)} chance`);

      if (roll < totalChance) {
        // Heal +1 health (can't exceed max health)
        const result = StateMutator.modifyHealth(1);

        if (result.changed) {
          console.log(`Charm of the Vampire: Healed +1 health (${result.oldHealth} → ${result.newHealth})`);
          // Show notification
          setTimeout(() => {
            createNotification('Charm of the Vampire: +1 Health!', COLORS.SUCCESS, '🧛');
          }, 100);
        }
      }
    }
  },

  "Cursed Slash": {
    onAcquire: () => {
      // Lose half of max health (rounded down)
      const healthLoss = Math.floor(maxHealth / 2);
      const oldMaxHealth = maxHealth;
      const oldHealth = health;

      maxHealth -= healthLoss;
      // Cap current health to new max, but don't reduce it otherwise
      health = Math.min(health, maxHealth);
      // Ensure player doesn't die (minimum 1 HP)
      health = Math.max(1, health);

      gameState.maxHealth = maxHealth;
      gameState.health = health;

      console.log(`Cursed Slash: Max health ${oldMaxHealth} → ${maxHealth}, Current health ${oldHealth} → ${health}`);

      if (typeof updateHealthDisplay === 'function') {
        updateHealthDisplay();
      }
      if (typeof updateTopBar === 'function') {
        updateTopBar();
      }
    },
    onEnemyDefeated: () => {
      // Always heal +1 health when defeating an enemy
      const oldHealth = health;
      health = Math.min(health + 1, maxHealth);
      gameState.health = health;

      if (health > oldHealth) {
        console.log(`Cursed Slash: Healed +1 health (${oldHealth} → ${health})`);
        if (typeof updateHealthDisplay === 'function') {
          updateHealthDisplay();
        }
        if (typeof updateTopBar === 'function') {
          updateTopBar();
        }
        // Show notification
        setTimeout(() => {
          createNotification('Cursed Slash: +1 Health!', 'rgba(156, 39, 176, 0.9)', '⚔️');
        }, 100);
      }
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
  },

  "Winged Boots": {
    canUse: () => {
      // Can only use during game selection phase
      return gameState.phase === 'selection';
    },
    onUse: () => {
      // Get current game's year
      const currentGameObj = games.find(g => g.name === gameState.currentGame);
      if (!currentGameObj) {
        console.error('Current game not found!');
        alert('Cannot determine current location!');
        return;
      }

      const currentYear = currentGameObj.year;
      console.log(`Using Winged Boots - Current year: ${currentYear}`);

      // Show selection of 3 games from the same year
      selectedTeleport({
        numChoices: 3,
        year: currentYear,
        title: `Choose Your Destination (${currentYear})`
      });
    }
  },

  "The Poop": {
    canUse: () => {
      // Can use anytime (though most useful during selection)
      return true;
    },
    onUse: () => {
      const currentGame = gameState.currentGame;
      if (!currentGame) {
        alert('No current game to apply status to!');
        return;
      }

      // Check if already has stinky status
      if (typeof hasGameStatus === 'function' && hasGameStatus(currentGame, 'stinky')) {
        alert(`${currentGame} is already stinky!`);
        return;
      }

      // Add stinky status to current game
      if (typeof addGameStatus === 'function') {
        addGameStatus(currentGame, 'stinky', '💩');
        console.log(`Applied stinky status to ${currentGame}`);

        // Refresh current node to show status icon
        if (typeof updateNodeStatusIcons === 'function') {
          const currentNode = document.querySelector('.node.current');
          if (currentNode) {
            updateNodeStatusIcons(currentNode);
          }
        }

        // Show notification
        setTimeout(() => {
          createNotification(`${currentGame} is now STINKY!`, 'rgba(139, 69, 19, 0.95)', '💩');
        }, 100);
      }
    }
  },

  "Ventricle Razor": {
    uses: 2, // Can create 2 portals
    canUse: () => {
      // Can use anytime
      return true;
    },
    onUse: () => {
      const currentGame = gameState.currentGame;
      if (!currentGame) {
        alert('No current game to apply status to!');
        return;
      }

      // Check if already has portal status
      if (typeof hasGameStatus === 'function' && hasGameStatus(currentGame, 'portal')) {
        alert(`${currentGame} already has a portal!`);
        return;
      }

      // Check how many portals exist
      const existingPortals = typeof getGamesWithStatus === 'function'
        ? getGamesWithStatus('portal')
        : [];

      if (existingPortals.length >= 2) {
        alert('Maximum of 2 portals can exist at once!');
        return;
      }

      // Add portal status to current game
      if (typeof addGameStatus === 'function') {
        addGameStatus(currentGame, 'portal', '🌀');
        console.log(`Applied portal status to ${currentGame}`);

        // Refresh current node to show status icon
        if (typeof updateNodeStatusIcons === 'function') {
          const currentNode = document.querySelector('.node.current');
          if (currentNode) {
            updateNodeStatusIcons(currentNode);
          }
        }

        // Show notification
        setTimeout(() => {
          createNotification(`Portal created at ${currentGame}!`, 'rgba(75, 0, 130, 0.95)', '🌀');
        }, 100);

        // Refresh the game view to add portal connections
        if (existingPortals.length === 1) {
          // Two portals now exist, refresh choices if we're in selection phase
          if (gameState.phase === 'selection' && typeof spawnChoices === 'function') {
            setTimeout(() => spawnChoices(), 500);
          }
        }
      }
    }
  },

  "Golden Beetle": {
    onAcquire: () => {
      console.log('Acquired Golden Beetle - will trigger when curses are removed');
    },
    onCurseRemoved: () => {
      // Grant one chest
      console.log('Golden Beetle: Curse removed, granting chest');

      // Show notification
      setTimeout(() => {
        createNotification('Golden Beetle: Gained a Chest!', COLORS.RARE, '🪲');
      }, 100);

      // Grant a chest (normal type by default)
      if (typeof offerItemReward === 'function') {
        setTimeout(() => {
          offerItemReward('normal');
        }, 500);
      }
    }
  },

  "Vitality Orb": {
    onAcquire: () => {
      console.log('Acquired Vitality Orb - will trigger when curses are obtained');
    },
    onCurseAdded: () => {
      // Increase max health by 1 and heal by 1
      console.log('Vitality Orb: Curse added, increasing max health');

      const oldMaxHealth = maxHealth;
      const result = StateMutator.modifyMaxHealth(1);

      if (result.changed) {
        console.log(`Vitality Orb: Max Health increased (${oldMaxHealth} → ${result.newMaxHealth})`);

        // Show notification
        setTimeout(() => {
          createNotification('Vitality Orb: +1 Max Health!', COLORS.SUCCESS, '🔮');
        }, 100);
      }
    }
  },

  "Wand of Wishing": {
    uses: 1,
    canUse: () => {
      // Can use anytime
      return true;
    },
    onUse: () => {
      // Show special item selection UI (like collection view)
      showWandOfWishingSelection();
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

  // Create a copy of the item to track uses
  const itemCopy = { ...item };

  // Initialize uses for Usable items
  if (itemCopy.type === 'Usable') {
    const effects = ITEM_EFFECTS[itemCopy.name];
    // Default to 1 use, or use the value from ITEM_EFFECTS
    itemCopy.uses = (effects && effects.uses) || 1;
  }

  // Add to inventory
  inventory.push(itemCopy);
  gameState.inventory = [...inventory];

  // Apply item effects (for Passive and Triggered items)
  applyItemEffects(itemCopy);

  // Update UI
  updateInventory();

  console.log(`Acquired: ${itemCopy.name}${itemCopy.uses ? ` (${itemCopy.uses} uses)` : ''}`);
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
    console.log(`Using item: ${item.name} (${item.uses || 1} uses remaining)`);
    effects.onUse();

    // Decrement uses
    if (item.uses && item.uses > 1) {
      item.uses--;
      gameState.inventory = [...inventory];
      console.log(`${item.name} used. ${item.uses} uses remaining.`);
    } else {
      // Remove item from inventory when uses reach 0
      inventory.splice(itemIndex, 1);
      gameState.inventory = [...inventory];
      console.log(`Used and removed: ${item.name}`);
    }

    // Update UI
    updateInventory();
  }
}

/**
 * Teleport to a random connected game of a specific type
 * @param {string|null} gameType - The type of game to teleport to (e.g., 'Deckbuilding', 'Action', 'Traditional', 'Strategy')
 *                                  If null or undefined, teleports to any connected game
 * @returns {boolean} - Returns true if teleport was successful, false otherwise
 */
function teleportToRandomGameOfType(gameType = null) {
  // Filter connected games, optionally by type, excluding current game
  let filteredGames;
  if (gameType) {
    filteredGames = games.filter(g =>
      g.connected === true &&
      g.type === gameType &&
      g.name !== gameState.currentGame
    );
    console.log(`Looking for connected ${gameType} games (excluding current)...`);
  } else {
    filteredGames = games.filter(g =>
      g.connected === true &&
      g.name !== gameState.currentGame
    );
    console.log('Looking for any connected games (excluding current)...');
  }

  if (filteredGames.length === 0) {
    const errorMsg = gameType
      ? `No other connected ${gameType} games available!`
      : 'No other connected games available!';
    console.error(errorMsg);
    alert(errorMsg);
    return false;
  }

  // Pick a random game from filtered list
  const randomGame = filteredGames[Math.floor(Math.random() * filteredGames.length)];

  const teleportMsg = gameType
    ? `Teleporting to ${gameType} game: ${randomGame.name}`
    : `Teleporting to: ${randomGame.name}`;
  console.log(teleportMsg);

  // Generate position
  const x = 450; // Center position
  const y = gameState.currentY + 200;

  // Advance to the selected game without triggering an encounter
  advance(randomGame.name, x, y, null);
  return true;
}

/**
 * Teleport to a random connected game (any type)
 */
function teleportToRandomGame() {
  return teleportToRandomGameOfType(null);
}

/**
 * Teleport to a random Deckbuilding game
 */
function teleportToRandomDeckbuilder() {
  return teleportToRandomGameOfType('Deckbuilding');
}

/**
 * Show a selection popup and teleport to the chosen game
 * @param {Object} options - Filter and display options
 * @param {number} options.numChoices - Number of games to show (default: 3)
 * @param {number|null} options.year - Filter by specific year (optional)
 * @param {string|null} options.type - Filter by game type (optional)
 * @param {Array<string>|null} options.tags - Filter by tags (optional, matches ANY tag)
 * @param {string} options.title - Title for the selection modal (default: "Choose Your Destination")
 * @returns {boolean} - Returns true if teleport was initiated, false otherwise
 */
function selectedTeleport(options = {}) {
  const {
    numChoices = 3,
    year = null,
    type = null,
    tags = null,
    title = "Choose Your Destination"
  } = options;

  // Start with connected games only, excluding current game
  let filteredGames = games.filter(g =>
    g.connected === true &&
    g.name !== gameState.currentGame
  );

  // Apply year filter
  if (year !== null) {
    filteredGames = filteredGames.filter(g => g.year === year);
  }

  // Apply type filter
  if (type !== null) {
    filteredGames = filteredGames.filter(g => g.type === type);
  }

  // Apply tags filter (matches if game has ANY of the specified tags)
  if (tags !== null && Array.isArray(tags) && tags.length > 0) {
    filteredGames = filteredGames.filter(g =>
      g.tags && Array.isArray(g.tags) && tags.some(tag => g.tags.includes(tag))
    );
  }

  // Check if we have enough games
  if (filteredGames.length === 0) {
    alert('No other games match your criteria!');
    return false;
  }

  // Randomly select games from filtered list
  const shuffled = [...filteredGames].sort(() => Math.random() - 0.5);
  const selectedGames = shuffled.slice(0, Math.min(numChoices, shuffled.length));

  // Build filter description for subtitle
  let filterDesc = [];
  if (year !== null) filterDesc.push(`Year: ${year}`);
  if (type !== null) filterDesc.push(`Type: ${type}`);
  if (tags !== null && tags.length > 0) filterDesc.push(`Tags: ${tags.join(', ')}`);
  const subtitle = filterDesc.length > 0 ? filterDesc.join(' • ') : 'Connected Games';

  // Create the modal HTML
  const gamesHTML = selectedGames.map(game => `
    <div class="teleport-choice" data-game-name="${game.name}" style="
      background: linear-gradient(145deg, #3a3430, #2a2420);
      border: 2px solid #cc6600;
      border-radius: 12px;
      padding: 20px;
      margin: 10px 0;
      cursor: pointer;
      transition: all 0.2s ease;
      text-align: center;
    ">
      <h3 style="color: #f39c12; margin: 0 0 10px 0; font-size: 18px;">${game.name}</h3>
      <div style="display: flex; justify-content: center; gap: 15px; margin-bottom: 10px;">
        <span style="color: #888; font-size: 14px;">📅 ${game.year}</span>
        <span style="color: #4a9eff; font-size: 14px;">🎮 ${game.type}</span>
      </div>
      ${game.tags && game.tags.length > 0 ? `
        <div style="color: #999; font-size: 12px; margin-top: 8px;">
          🏷️ ${game.tags.join(', ')}
        </div>
      ` : ''}
    </div>
  `).join('');

  // Show modal using createGameModal
  if (typeof createGameModal === 'function') {
    createGameModal(`
      <div style="text-align: center;">
        <h2 style="color: #f39c12; margin-top: 0;">${title}</h2>
        <p style="color: #888; margin-bottom: 20px; font-size: 14px;">${subtitle}</p>
        <div style="max-height: 400px; overflow-y: auto;">
          ${gamesHTML}
        </div>
      </div>
    `);

    // Add click handlers to teleport choices
    document.querySelectorAll('.teleport-choice').forEach(choice => {
      choice.onmouseenter = () => {
        choice.style.background = 'linear-gradient(145deg, #cc6600, #aa5500)';
        choice.style.borderColor = '#ff8800';
        choice.style.transform = 'translateY(-2px)';
        choice.style.boxShadow = '0 4px 12px rgba(204, 102, 0, 0.4)';
      };
      choice.onmouseleave = () => {
        choice.style.background = 'linear-gradient(145deg, #3a3430, #2a2420)';
        choice.style.borderColor = '#cc6600';
        choice.style.transform = '';
        choice.style.boxShadow = '';
      };
      choice.onclick = () => {
        const gameName = choice.dataset.gameName;
        console.log(`Player selected: ${gameName}`);

        // Close modal
        if (typeof closeGameModal === 'function') {
          closeGameModal();
        }

        // Teleport to selected game without triggering an encounter
        const selectedGame = games.find(g => g.name === gameName);
        if (selectedGame) {
          const x = 450;
          const y = gameState.currentY + 200;

          advance(selectedGame.name, x, y, null);
        }
      };
    });
  } else {
    console.error('createGameModal function not found!');
    return false;
  }

  return true;
}

/**
 * Trigger onEnemyDefeated effects for all items in inventory that have this trigger
 * Call this function when the player successfully defeats an enemy
 */
function triggerOnEnemyDefeated() {
  if (!inventory || inventory.length === 0) {
    return;
  }

  console.log('Triggering onEnemyDefeated effects...');

  // Check each item in inventory for onEnemyDefeated trigger
  inventory.forEach(item => {
    if (!item || !item.name) return;

    const itemEffects = ITEM_EFFECTS[item.name];
    if (itemEffects && typeof itemEffects.onEnemyDefeated === 'function') {
      console.log(`Triggering ${item.name} onEnemyDefeated effect`);
      itemEffects.onEnemyDefeated();
    }
  });
}

/**
 * Trigger onCurseAdded effects for all items in inventory that have this trigger
 * Call this function when the player obtains a new curse
 */
function triggerOnCurseAdded() {
  if (!inventory || inventory.length === 0) {
    return;
  }

  console.log('Triggering onCurseAdded effects...');

  // Check each item in inventory for onCurseAdded trigger
  inventory.forEach(item => {
    if (!item || !item.name) return;

    const itemEffects = ITEM_EFFECTS[item.name];
    if (itemEffects && typeof itemEffects.onCurseAdded === 'function') {
      console.log(`Triggering ${item.name} onCurseAdded effect`);
      itemEffects.onCurseAdded();
    }
  });
}

/**
 * Trigger onCurseRemoved effects for all items in inventory that have this trigger
 * Call this function when the player removes a curse
 */
function triggerOnCurseRemoved() {
  if (!inventory || inventory.length === 0) {
    return;
  }

  console.log('Triggering onCurseRemoved effects...');

  // Check each item in inventory for onCurseRemoved trigger
  inventory.forEach(item => {
    if (!item || !item.name) return;

    const itemEffects = ITEM_EFFECTS[item.name];
    if (itemEffects && typeof itemEffects.onCurseRemoved === 'function') {
      console.log(`Triggering ${item.name} onCurseRemoved effect`);
      itemEffects.onCurseRemoved();
    }
  });
}

/**
 * Show Wand of Wishing item selection UI
 * Displays all unlocked items in a collection-style grid with hover tooltips
 */
function showWandOfWishingSelection() {
  if (!items || items.length === 0) {
    alert('No items available!');
    return;
  }

  // Filter for unlocked items only (defaults to true if not specified)
  // Also exclude the Wand of Wishing itself
  const unlockedItems = items.filter(item => item.unlocked !== false && item.name !== 'Wand of Wishing');

  // Sort items by rarity then alphabetically
  const rarityOrder = { 'legendary': 4, 'rare': 3, 'uncommon': 2, 'common': 1 };
  const sortedItems = [...unlockedItems].sort((a, b) => {
    const rarityDiff = (rarityOrder[b.rarity] || 0) - (rarityOrder[a.rarity] || 0);
    if (rarityDiff !== 0) return rarityDiff;
    return a.name.localeCompare(b.name);
  });

  // Get rarity color
  const getRarityColor = (rarity) => {
    switch(rarity) {
      case 'legendary': return '#ff6b00'; // Orange/gold
      case 'rare': return '#9b59b6';      // Purple
      case 'uncommon': return '#4CAF50';  // Green
      case 'common': return '#aaa';       // Gray
      default: return '#888';
    }
  };

  // Create items grid HTML
  const itemsHTML = sortedItems.map(item => `
    <div class="wand-item-card" data-item-name="${item.name.replace(/"/g, '&quot;')}" style="
      background: rgba(0,0,0,0.3);
      border: 2px solid ${getRarityColor(item.rarity)};
      border-radius: 8px;
      padding: 12px;
      display: flex;
      flex-direction: column;
      gap: 8px;
      transition: all 0.2s;
      cursor: pointer;
      position: relative;
    ">
      <img
        src="${item.image || 'images/items/no-item.svg'}"
        alt="${item.name}"
        style="
          width: 100%;
          height: 96px;
          object-fit: contain;
          border-radius: 6px;
          background: rgba(0,0,0,0.2);
          image-rendering: pixelated;
        "
        onerror="this.style.display='none';"
      />
      <div style="text-align: center; font-size: 13px; font-weight: bold; color: ${getRarityColor(item.rarity)}; word-wrap: break-word;">
        ${item.name}
      </div>
      <div style="font-size: 10px; color: ${getRarityColor(item.rarity)}; text-align: center; text-transform: uppercase; font-weight: bold;">
        ${item.rarity}
      </div>
      <div class="item-tooltip" style="display: none; position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); background: #2a2420; color: #e6d5b8; padding: 15px; border: 2px solid ${getRarityColor(item.rarity)}; border-radius: 8px; font-size: 13px; z-index: 100000; min-width: 300px; max-width: 400px; white-space: normal; box-shadow: 0 8px 24px rgba(0,0,0,0.7); pointer-events: none;">
        <div style="font-weight: bold; margin-bottom: 8px; color: ${getRarityColor(item.rarity)}; font-size: 15px;">${item.name}</div>
        <div style="color: #888; font-size: 11px; margin-bottom: 10px;">${item.type} • ${item.game || 'Unknown'}</div>
        <div style="line-height: 1.6;">${item.description || 'No description'}</div>
      </div>
    </div>
  `).join('');

  // Show modal
  if (typeof createGameModal === 'function') {
    createGameModal(`
      <div style="width: 90vw; max-width: 1200px; max-height: 85vh; overflow: hidden; display: flex; flex-direction: column;">
        <h2 style="color: #ff6b00; margin: 0 0 15px 0; text-align: center;">✨ Wand of Wishing ✨</h2>
        <p style="color: #aaa; text-align: center; margin-bottom: 20px; font-size: 14px;">
          Choose any item to add to your inventory
        </p>
        <div style="flex: 1; overflow-y: auto; padding: 10px;">
          <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 15px;">
            ${itemsHTML}
          </div>
        </div>
        <div style="text-align: center; margin-top: 15px; padding-top: 15px; border-top: 2px solid #444;">
          <button onclick="closeGameModal();" style="padding: 10px 30px; background: #444; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold;">Cancel</button>
        </div>
      </div>
    `);

    // Add hover and click handlers
    document.querySelectorAll('.wand-item-card').forEach(card => {
      const tooltip = card.querySelector('.item-tooltip');

      card.onmouseenter = (e) => {
        e.currentTarget.style.transform = 'translateY(-5px) scale(1.05)';
        e.currentTarget.style.boxShadow = '0 10px 30px rgba(255, 107, 0, 0.4)';
        if (tooltip) tooltip.style.display = 'block';
      };

      card.onmouseleave = (e) => {
        e.currentTarget.style.transform = '';
        e.currentTarget.style.boxShadow = '';
        if (tooltip) tooltip.style.display = 'none';
      };

      card.onclick = (e) => {
        const itemName = e.currentTarget.dataset.itemName;
        const selectedItem = items.find(i => i.name === itemName);

        if (selectedItem) {
          console.log(`Wand of Wishing: Selected ${itemName}`);

          // Acquire the item
          acquireItem(selectedItem);

          // Close modal
          if (typeof closeGameModal === 'function') {
            closeGameModal();
          }

          // Show notification
          setTimeout(() => {
            createNotification(`Wished for ${itemName}!`, 'rgba(255, 107, 0, 0.95)', '✨');
          }, 100);
        }
      };
    });
  } else {
    console.error('createGameModal function not found!');
  }
}

// Export functions to global scope
window.applyItemEffects = applyItemEffects;
window.acquireItem = acquireItem;
window.getItemByName = getItemByName;
window.hasItemEffects = hasItemEffects;
window.canUseItem = canUseItem;
window.useItem = useItem;
window.teleportToRandomGameOfType = teleportToRandomGameOfType; // Random teleport by type
window.selectedTeleport = selectedTeleport; // Selected teleport with filters
window.teleportToRandomGame = teleportToRandomGame;
window.teleportToRandomDeckbuilder = teleportToRandomDeckbuilder;
window.triggerOnEnemyDefeated = triggerOnEnemyDefeated; // Trigger onEnemyDefeated effects
window.triggerOnCurseAdded = triggerOnCurseAdded; // Trigger onCurseAdded effects
window.triggerOnCurseRemoved = triggerOnCurseRemoved; // Trigger onCurseRemoved effects
window.showWandOfWishingSelection = showWandOfWishingSelection; // Wand of Wishing UI
window.ITEM_EFFECTS = ITEM_EFFECTS;
