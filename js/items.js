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
      health = Math.min(health + 4, maxHealth); // Cap health to max health
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
      health = Math.min(health + 2, maxHealth); // Cap health to max health
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
      health = Math.min(health + 5, maxHealth); // Cap health to max health
      luck += 2;
      strength -= 1;
      gameState.maxHealth = maxHealth;
      gameState.health = health;
      gameState.luck = luck;
      gameState.strength = strength;
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
        const oldHealth = health;
        health = Math.min(health + 1, maxHealth);
        gameState.health = health;

        if (health > oldHealth) {
          console.log(`Charm of the Vampire: Healed +1 health (${oldHealth} → ${health})`);
          if (typeof updateHealthDisplay === 'function') {
            updateHealthDisplay();
          }
          if (typeof updateTopBar === 'function') {
            updateTopBar();
          }
          // Show notification
          if (typeof createGameModal !== 'undefined') {
            setTimeout(() => {
              const notification = document.createElement('div');
              notification.style.cssText = `
                position: fixed;
                top: 50%;
                left: 50%;
                transform: translate(-50%, -50%);
                background: rgba(76, 175, 80, 0.9);
                color: white;
                padding: 20px 40px;
                border-radius: 12px;
                font-size: 18px;
                font-weight: bold;
                z-index: 10001;
                box-shadow: 0 4px 20px rgba(0,0,0,0.5);
                animation: fadeIn 0.3s;
              `;
              notification.textContent = '🧛 Charm of the Vampire: +1 Health!';
              document.body.appendChild(notification);
              setTimeout(() => {
                notification.style.animation = 'fadeOut 0.3s';
                setTimeout(() => notification.remove(), 300);
              }, 1500);
            }, 100);
          }
        }
      }
    }
  },

  "Cursed Slash": {
    onAcquire: () => {
      // Lose half of max health (rounded down)
      const healthLoss = Math.floor(maxHealth / 2);
      maxHealth -= healthLoss;
      health = Math.max(0, health - healthLoss); // Lose current health too

      gameState.maxHealth = maxHealth;
      gameState.health = health;

      console.log(`Cursed Slash: Lost ${healthLoss} max health and current health`);

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
        if (typeof createGameModal !== 'undefined') {
          setTimeout(() => {
            const notification = document.createElement('div');
            notification.style.cssText = `
              position: fixed;
              top: 50%;
              left: 50%;
              transform: translate(-50%, -50%);
              background: rgba(156, 39, 176, 0.9);
              color: white;
              padding: 20px 40px;
              border-radius: 12px;
              font-size: 18px;
              font-weight: bold;
              z-index: 10001;
              box-shadow: 0 4px 20px rgba(0,0,0,0.5);
              animation: fadeIn 0.3s;
            `;
            notification.textContent = '⚔️ Cursed Slash: +1 Health!';
            document.body.appendChild(notification);
            setTimeout(() => {
              notification.style.animation = 'fadeOut 0.3s';
              setTimeout(() => notification.remove(), 300);
            }, 1500);
          }, 100);
        }
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
 * Teleport to a random connected game of a specific type
 * @param {string|null} gameType - The type of game to teleport to (e.g., 'Deckbuilding', 'Action', 'Traditional', 'Strategy')
 *                                  If null or undefined, teleports to any connected game
 * @returns {boolean} - Returns true if teleport was successful, false otherwise
 */
function teleportToRandomGameOfType(gameType = null) {
  // Filter connected games, optionally by type
  let filteredGames;
  if (gameType) {
    filteredGames = games.filter(g => g.connected === true && g.type === gameType);
    console.log(`Looking for connected ${gameType} games...`);
  } else {
    filteredGames = games.filter(g => g.connected === true);
    console.log('Looking for any connected games...');
  }

  if (filteredGames.length === 0) {
    const errorMsg = gameType
      ? `No connected ${gameType} games available!`
      : 'No connected games available!';
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

  // Generate position and encounter type
  const x = 450; // Center position
  const y = gameState.currentY + 200;

  // Determine encounter type (same logic as spawnChoices)
  const encounterRoll = Math.random() * 100;
  let encounterType;

  if (encounterRoll < 75) {
    encounterType = 'combat';
  } else if (encounterRoll < 90) {
    encounterType = 'event';
  } else {
    encounterType = 'shop';
  }

  // Advance to the selected game
  advance(randomGame.name, x, y, encounterType);
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

  // Start with connected games only
  let filteredGames = games.filter(g => g.connected === true);

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
    alert('No games match your criteria!');
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

        // Teleport to selected game
        const selectedGame = games.find(g => g.name === gameName);
        if (selectedGame) {
          const x = 450;
          const y = gameState.currentY + 200;

          // Determine encounter type
          const encounterRoll = Math.random() * 100;
          let encounterType;
          if (encounterRoll < 75) {
            encounterType = 'combat';
          } else if (encounterRoll < 90) {
            encounterType = 'event';
          } else {
            encounterType = 'shop';
          }

          advance(selectedGame.name, x, y, encounterType);
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
window.ITEM_EFFECTS = ITEM_EFFECTS;
