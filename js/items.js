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
          setTimeout(() => {
            createNotification('Charm of the Vampire: +1 Health!', 'rgba(76, 175, 80, 0.9)', '🧛');
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
  const encounterType = determineEncounterType();

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
          const encounterType = determineEncounterType();

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
