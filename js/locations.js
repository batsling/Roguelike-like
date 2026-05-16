// ===== LOCATIONS.JS - Location Data and Management =====
//
// This module contains all location data from different roguelike games.
// Each location has game-specific effects that trigger during gameplay.
//
// Location Structure:
// - name: Location name
// - difficulty: Easy, Medium, or Hard
// - game: Source game
// - type: Environmental type (Building, Firey, Undead, etc.)
// - effect: Game-specific effect description

// ========================================
// ENTER THE GUNGEON LOCATIONS
// ========================================
// Effect: Guns are 20% more likely to show up
const GUNGEON_LOCATIONS = [
  {
    name: "Keep of the Lead Lord",
    difficulty: "Easy",
    game: "Enter the Gungeon",
    type: "Building",
    effect: "Guns are 20% more likely to show up"
  },
  {
    name: "Black Powder Mine",
    difficulty: "Medium",
    game: "Enter the Gungeon",
    type: "Underground",
    effect: "Guns are 20% more likely to show up"
  },
  {
    name: "Hollow",
    difficulty: "Medium",
    game: "Enter the Gungeon",
    type: "Icey",
    effect: "Guns are 20% more likely to show up"
  },
  {
    name: "Forge",
    difficulty: "Hard",
    game: "Enter the Gungeon",
    type: "Firey",
    effect: "Guns are 20% more likely to show up"
  },
  {
    name: "Bullet Hell",
    difficulty: "Hard",
    game: "Enter the Gungeon",
    type: "Undead",
    effect: "Guns are 20% more likely to show up"
  }
];

// ========================================
// THE BINDING OF ISAAC LOCATIONS
// ========================================
// Effect: All games in this Location have a 10% chance to be Holy, Devilish, or Stinky
const ISAAC_LOCATIONS = [
  {
    name: "Basement",
    difficulty: "Easy",
    game: "The Binding of Isaac",
    type: "Building",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    name: "Burning Basement",
    difficulty: "Easy",
    game: "The Binding of Isaac",
    type: "Firey",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    name: "Dross",
    difficulty: "Easy",
    game: "The Binding of Isaac",
    type: "Sewage",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    name: "Caves",
    difficulty: "Medium",
    game: "The Binding of Isaac",
    type: "Underground",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    name: "Flooded Caves",
    difficulty: "Medium",
    game: "The Binding of Isaac",
    type: "Watery",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    name: "Necropolis",
    difficulty: "Medium",
    game: "The Binding of Isaac",
    type: "Undead",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    name: "Womb",
    difficulty: "Hard",
    game: "The Binding of Isaac",
    type: "Living",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    name: "Cathedral",
    difficulty: "Hard",
    game: "The Binding of Isaac",
    type: "Holy",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    name: "The Void",
    difficulty: "Hard",
    game: "The Binding of Isaac",
    type: "Chaos",
    effect: "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  }
];

// ========================================
// HADES LOCATIONS
// ========================================
// Effect: When the player enters this location, they will chose one of 3 Gods which will Give the player its Boon Item
const HADES_LOCATIONS = [
  {
    name: "Tartarus",
    difficulty: "Easy",
    game: "Hades",
    type: "Undead",
    effect: "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    name: "Asphodel",
    difficulty: "Easy",
    game: "Hades",
    type: "Firey",
    effect: "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    name: "Elysium",
    difficulty: "Medium",
    game: "Hades",
    type: "Watery",
    effect: "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    name: "Chaos",
    difficulty: "Medium",
    game: "Hades",
    type: "Chaos",
    effect: "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    name: "Temple of Styx",
    difficulty: "Hard",
    game: "Hades",
    type: "Building",
    effect: "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  }
];

// ========================================
// RISK OF RAIN 2 LOCATIONS
// ========================================
// Effect: The Difficulty level has a 50% chance to increase by +1 after beating a game,
//         but whenever a player beats a game, they can open an extra chest for 10 Gold
const RISK_OF_RAIN_LOCATIONS = [
  {
    name: "Titanic Plains",
    difficulty: "Easy",
    game: "Risk of Rain 2",
    type: "General",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Abandoned Aqueduct",
    difficulty: "Easy",
    game: "Risk of Rain 2",
    type: "Desert",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Siphoned Forest",
    difficulty: "Easy",
    game: "Risk of Rain 2",
    type: "Icey",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Wetland Aspect",
    difficulty: "Easy",
    game: "Risk of Rain 2",
    type: "Swampy",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Rallypoint Delta",
    difficulty: "Medium",
    game: "Risk of Rain 2",
    type: "Icey",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Abyssal Depths",
    difficulty: "Medium",
    game: "Risk of Rain 2",
    type: "Firey",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Sundered Grove",
    difficulty: "Medium",
    game: "Risk of Rain 2",
    type: "General",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Sulfur Pools",
    difficulty: "Medium",
    game: "Risk of Rain 2",
    type: "Poisonous",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Sky Meadow",
    difficulty: "Hard",
    game: "Risk of Rain 2",
    type: "Sky",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    name: "Commencement",
    difficulty: "Hard",
    game: "Risk of Rain 2",
    type: "Lunar",
    effect: "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  }
];

// ========================================
// CAVES OF QUD LOCATIONS
// ========================================
// Effect: If the player changes their physical appearance (not attire) in a run,
//         there's a 50% chance to upgrade and 50% chance to downgrade a random passive item
const CAVES_OF_QUD_LOCATIONS = [
  {
    name: "Salt Marsh",
    difficulty: "Easy",
    game: "Caves of Qud",
    type: "Swampy",
    effect: "If the player changes their physical appearance (not attire) in a run, there's a 50% chance to upgrade and 50% chance to downgrade a random passive item"
  },
  {
    name: "Asphalt Mines",
    difficulty: "Easy",
    game: "Caves of Qud",
    type: "Underground",
    effect: "If the player changes their physical appearance (not attire) in a run, there's a 50% chance to upgrade and 50% chance to downgrade a random passive item"
  },
  {
    name: "Salt Dunes",
    difficulty: "Medium",
    game: "Caves of Qud",
    type: "Underground",
    effect: "If the player changes their physical appearance (not attire) in a run, there's a 50% chance to upgrade and 50% chance to downgrade a random passive item"
  },
  {
    name: "Flower fields",
    difficulty: "Medium",
    game: "Caves of Qud",
    type: "General",
    effect: "If the player changes their physical appearance (not attire) in a run, there's a 50% chance to upgrade and 50% chance to downgrade a random passive item"
  },
  {
    name: "Deep Jungle",
    difficulty: "Hard",
    game: "Caves of Qud",
    type: "Swampy",
    effect: "If the player changes their physical appearance (not attire) in a run, there's a 50% chance to upgrade and 50% chance to downgrade a random passive item"
  },
  {
    name: "Moon Stair",
    difficulty: "Hard",
    game: "Caves of Qud",
    type: "Lunar",
    effect: "If the player changes their physical appearance (not attire) in a run, there's a 50% chance to upgrade and 50% chance to downgrade a random passive item"
  }
];

// ========================================
// COMBINED LOCATIONS DATA
// ========================================
const LOCATIONS_DATA = [
  ...GUNGEON_LOCATIONS,
  ...ISAAC_LOCATIONS,
  ...HADES_LOCATIONS,
  ...RISK_OF_RAIN_LOCATIONS,
  ...CAVES_OF_QUD_LOCATIONS
];

// ========================================
// LOCATION ORGANIZATION
// ========================================

// Games per difficulty tier before advancing
const DIFFICULTY_TIER_SIZE = 4;
const DIFFICULTY_THRESHOLDS = { MEDIUM: 4, HARD: 8, INSANE: 12 };

// Organize locations by difficulty
const locationsByDifficulty = {
  easy: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Easy'),
  medium: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Medium'),
  hard: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Hard'),
  insane: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Hard') // Insane reuses Hard locations
};

// Organize locations by game
const locationsByGame = {
  gungeon: GUNGEON_LOCATIONS,
  isaac: ISAAC_LOCATIONS,
  hades: HADES_LOCATIONS,
  riskOfRain: RISK_OF_RAIN_LOCATIONS,
  cavesOfQud: CAVES_OF_QUD_LOCATIONS
};

// ========================================
// LOCATION SELECTION FUNCTIONS
// ========================================

/**
 * Get a random location based on difficulty tier
 * @param {string} difficulty - 'Easy', 'Medium', 'Hard', or 'Insane'
 * @returns {Object|null} Random location object or null if none available
 */
function getRandomLocation(difficulty) {
  const difficultyKey = difficulty.toLowerCase();
  const locations = locationsByDifficulty[difficultyKey] || locationsByDifficulty.hard;

  if (locations.length === 0) return null;

  // Pick a random game first so each game gets equal representation,
  // then pick a random location from that game.
  const gameNames = [...new Set(locations.map(l => l.game))];
  const chosenGame = gameNames[Math.floor(Math.random() * gameNames.length)];
  const gameLocations = locations.filter(l => l.game === chosenGame);
  return gameLocations[Math.floor(Math.random() * gameLocations.length)];
}

/**
 * Get difficulty tier based on player progress.
 * Each tier spans DIFFICULTY_TIER_SIZE games.
 * @param {number} beatenGamesCount - Number of games the player has beaten
 * @returns {string} 'Easy', 'Medium', 'Hard', or 'Insane'
 */
function getDifficultyTier(beatenGamesCount) {
  if (beatenGamesCount < DIFFICULTY_THRESHOLDS.MEDIUM) {
    return 'Easy';
  } else if (beatenGamesCount < DIFFICULTY_THRESHOLDS.HARD) {
    return 'Medium';
  } else if (beatenGamesCount < DIFFICULTY_THRESHOLDS.INSANE) {
    return 'Hard';
  } else {
    return 'Insane';
  }
}

// ========================================
// LOCATION EFFECT UTILITIES
// ========================================

/**
 * Get the game that a location belongs to
 * @param {Object} location - Location object
 * @returns {string} Game name
 */
function getLocationGame(location) {
  return location.game;
}

/**
 * Check if a location is from a specific game
 * @param {Object} location - Location object
 * @param {string} gameName - Name of the game to check
 * @returns {boolean} True if location is from the specified game
 */
function isLocationFromGame(location, gameName) {
  return location.game === gameName;
}

/**
 * Get all locations from a specific game
 * @param {string} gameName - Name of the game
 * @returns {Array} Array of location objects
 */
function getLocationsByGame(gameName) {
  return LOCATIONS_DATA.filter(loc => loc.game === gameName);
}

// ========================================
// LOCATION EFFECT HANDLERS
// ========================================

/**
 * Check if location has Enter the Gungeon effect (guns more likely)
 * @param {Object} location - Location object
 * @returns {boolean} True if location increases gun spawn rate
 */
function hasGunSpawnBoost(location) {
  return isLocationFromGame(location, "Enter the Gungeon");
}

/**
 * Check if location has Isaac effect (Holy/Devilish/Stinky chance)
 * @param {Object} location - Location object
 * @returns {boolean} True if location adds special game modifiers
 */
function hasIsaacModifiers(location) {
  return isLocationFromGame(location, "The Binding of Isaac");
}

/**
 * Check if location has Hades effect (God Boon selection)
 * @param {Object} location - Location object
 * @returns {boolean} True if location offers God Boons
 */
function hasGodBoonChoice(location) {
  return isLocationFromGame(location, "Hades");
}

/**
 * Check if location has Risk of Rain 2 effect (difficulty increase chance + extra chest)
 * @param {Object} location - Location object
 * @returns {boolean} True if location has RoR2 scaling effect
 */
function hasScalingReward(location) {
  return isLocationFromGame(location, "Risk of Rain 2");
}

/**
 * Check if location has Caves of Qud effect (appearance change verification)
 * @param {Object} location - Location object
 * @returns {boolean} True if location has appearance change effect
 */
function hasAppearanceEffect(location) {
  return isLocationFromGame(location, "Caves of Qud");
}

/**
 * Apply location-specific logic based on game effect
 * @param {Object} location - Current location
 * @returns {Object} Effect details for the location
 */
function getLocationEffectDetails(location) {
  const effects = {
    hasEffect: true,
    game: location.game,
    description: location.effect,
    type: null,
    parameters: {}
  };

  if (hasGunSpawnBoost(location)) {
    effects.type = 'gunSpawnBoost';
    effects.parameters = { bonusChance: 0.20 }; // 20% increase
  } else if (hasIsaacModifiers(location)) {
    effects.type = 'isaacModifiers';
    effects.parameters = {
      modifierChance: 0.10, // 10% chance
      modifiers: ['Holy', 'Devilish', 'Stinky']
    };
  } else if (hasGodBoonChoice(location)) {
    effects.type = 'godBoonChoice';
    effects.parameters = {
      numberOfGods: 3,
      chooseOne: true
    };
  } else if (hasScalingReward(location)) {
    effects.type = 'scalingReward';
    effects.parameters = {
      difficultyIncreaseChance: 0.50, // 50% chance
      extraChestCost: 10 // 10 gold
    };
  } else if (hasAppearanceEffect(location)) {
    effects.type = 'appearanceChange';
    effects.parameters = {
      upgradeChance: 0.50, // 50% chance to upgrade
      downgradeChance: 0.50 // 50% chance to downgrade
    };
  }

  return effects;
}

// ========================================
// LOCATION EFFECT APPLICATION
// ========================================

/**
 * Apply location-specific effects during gameplay
 * Called at appropriate times based on the effect type
 */

/**
 * Apply Enter the Gungeon effect - boost weapon item spawn rate
 * @param {Array} items - Available items to choose from
 * @param {Object} location - Current location
 * @returns {Array} Modified item pool with boosted weapon chances
 */
function applyGunSpawnBoost(items, location) {
  if (!hasGunSpawnBoost(location)) {
    return items;
  }

  // Create a modified item pool where weapons appear 20% more
  const weaponItems = items.filter(item => item.type === 'Weapon');
  const nonWeaponItems = items.filter(item => item.type !== 'Weapon');

  // Calculate how many extra weapon copies to add (20% boost)
  const weaponBoostCount = Math.ceil(weaponItems.length * 0.2);

  // Add extra copies of weapons to the pool
  const boostedWeapons = [];
  for (let i = 0; i < weaponBoostCount; i++) {
    const randomWeapon = weaponItems[Math.floor(Math.random() * weaponItems.length)];
    if (randomWeapon) {
      boostedWeapons.push(randomWeapon);
    }
  }

  return [...nonWeaponItems, ...weaponItems, ...boostedWeapons];
}

/**
 * Apply Isaac effect - chance for games to have Holy/Devilish/Stinky status
 * This should be called when games are being set up or visited
 * @param {string} gameName - Name of the game
 * @param {Object} location - Current location
 */
function applyIsaacModifiers(gameName, location) {
  if (!hasIsaacModifiers(location)) {
    return;
  }

  // 10% chance for each modifier
  const roll = Math.random();

  if (roll < 0.10) {
    // Apply Holy status
    if (typeof addGameStatus === 'function') {
      addGameStatus(gameName, 'holy', '✨');
    }
  } else if (roll < 0.20) {
    // Apply Devilish status
    if (typeof addGameStatus === 'function') {
      addGameStatus(gameName, 'devilish', '👹');
    }
  } else if (roll < 0.30) {
    // Apply Stinky status
    if (typeof addGameStatus === 'function') {
      addGameStatus(gameName, 'stinky', '💩');
    }
  }
}

/**
 * Check if we should show Hades God Boon choice
 * @param {Object} location - Current location
 * @returns {boolean} True if Hades boon choice should be offered
 */
function shouldOfferHadesBoon(location) {
  return hasGodBoonChoice(location);
}

/**
 * Apply Risk of Rain 2 effect - chance to increase difficulty after beating game
 * Also offers extra chest opportunity
 * @param {Object} location - Current location
 * @returns {Object} Effect results {difficultyIncreased: boolean, offerExtraChest: boolean}
 */
function applyRiskOfRainEffect(location) {
  const result = {
    difficultyIncreased: false,
    offerExtraChest: false
  };

  if (!hasScalingReward(location)) {
    return result;
  }

  // 50% chance to increase difficulty
  if (Math.random() < 0.5) {
    result.difficultyIncreased = true;
  }

  // Always offer extra chest for 10 gold
  result.offerExtraChest = true;

  return result;
}

/**
 * Show Risk of Rain 2 extra chest offer — costs 10 Gold
 * @param {Function} onComplete - Called after the player accepts or declines
 */
function showRoRExtraChestOffer(onComplete) {
  const overlay = document.createElement('div');
  overlay.id = 'ror-chest-overlay';
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.75);z-index:10000;display:flex;align-items:center;justify-content:center;';

  const gold = (typeof gameState !== 'undefined' && gameState.gold) || 0;
  const canAfford = gold >= 10;

  overlay.innerHTML = `
    <div style="background:#1a1a2e;border:2px solid #ff6600;border-radius:12px;padding:28px 32px;max-width:320px;text-align:center;color:white;box-shadow:0 8px 32px rgba(0,0,0,0.8);">
      <div style="font-size:28px;margin-bottom:8px;">🌧️</div>
      <div style="font-size:17px;font-weight:bold;color:#ff6600;margin-bottom:6px;">Risk of Rain 2</div>
      <div style="font-size:13px;color:#ccc;margin-bottom:18px;">Open an extra chest?</div>
      <div style="font-size:22px;color:#ffd700;font-weight:bold;margin-bottom:22px;">10 Gold ${canAfford ? '' : '<span style="font-size:12px;color:#f44336;">(not enough)</span>'}</div>
      <div style="display:flex;gap:12px;justify-content:center;">
        <button id="ror-chest-yes" style="padding:9px 20px;background:${canAfford ? '#cc5500' : '#555'};border:none;border-radius:8px;color:white;font-size:14px;font-weight:bold;cursor:${canAfford ? 'pointer' : 'not-allowed'};opacity:${canAfford ? 1 : 0.6};">Open Chest</button>
        <button id="ror-chest-no" style="padding:9px 20px;background:#333;border:1px solid #666;border-radius:8px;color:#ccc;font-size:14px;cursor:pointer;">Skip</button>
      </div>
    </div>`;

  document.body.appendChild(overlay);

  const finish = () => {
    overlay.remove();
    if (typeof onComplete === 'function') onComplete();
  };

  document.getElementById('ror-chest-yes').onclick = () => {
    const currentGold = (typeof gameState !== 'undefined' && gameState.gold) || 0;
    if (currentGold < 10) {
      if (typeof createNotification === 'function') createNotification('Not enough Gold!', '#f44336', '💰');
      finish();
      return;
    }
    gameState.gold -= 10;
    if (typeof updateTopBar === 'function') updateTopBar();
    overlay.remove();
    if (typeof showItemChoiceModal === 'function') {
      showItemChoiceModal(onComplete);
    } else {
      finish();
    }
  };

  document.getElementById('ror-chest-no').onclick = finish;
}

/**
 * Show Hades boon selection - exactly 2 boons, cannot be rerolled
 * Displays when entering or arriving at a Hades location
 * @param {boolean} shouldSpawnChoices - Whether to spawn next game choices after selection (default true)
 */
function showHadesBoonSelection(shouldSpawnChoices = true) {

  // Get all boon items
  const allBoons = items.filter(item => item.type === 'Boon');

  const boonCount = 3;
  if (allBoons.length < boonCount) {
    console.error('Not enough boons available!');
    return;
  }

  // Select exactly 3 random boons
  const selectedBoons = [];
  const availableBoons = [...allBoons];

  for (let i = 0; i < boonCount; i++) {
    const randomIndex = Math.floor(Math.random() * availableBoons.length);
    selectedBoons.push(availableBoons[randomIndex]);
    availableBoons.splice(randomIndex, 1);
  }

  // Create modal HTML
  let modalHTML = `
    <div style="text-align: center; max-width: 1000px; margin: 0 auto;">
      <h2 style="color: #ba55d3; margin-top: 0; font-size: 28px;">🌟 Divine Boons 🌟</h2>
      <p style="color: #aaa; font-size: 16px; margin: 15px 0 25px 0;">
        Three Gods offer you their boons. Choose one — each boon applies a status to at least one game choice each round.
      </p>
      <div style="display: flex; gap: 20px; justify-content: center; margin-top: 20px; flex-wrap: wrap;">
  `;

  selectedBoons.forEach((boon, index) => {
    modalHTML += `
      <div class="boon-choice-card" data-index="${index}" style="
        flex: 1;
        max-width: 300px;
        padding: 25px;
        background: linear-gradient(135deg, rgba(138, 43, 226, 0.2), rgba(75, 0, 130, 0.2));
        border: 3px solid #8a2be2;
        border-radius: 12px;
        cursor: pointer;
        transition: transform 0.2s, box-shadow 0.2s;
      " onmouseover="this.style.transform='scale(1.05)'; this.style.boxShadow='0 8px 24px rgba(138, 43, 226, 0.5)';" onmouseout="this.style.transform='scale(1)'; this.style.boxShadow='none';">
        <div style="width: 150px; height: 150px; margin: 0 auto 15px auto; overflow: hidden; border-radius: 8px; background: rgba(0,0,0,0.3);">
          <img src="${boon.image}" alt="${boon.name}" style="width: 100%; height: 100%; object-fit: cover;">
        </div>
        <h3 style="color: #ba55d3; margin: 15px 0 10px 0; font-size: 20px;">${boon.name}</h3>
        <p style="color: #ccc; font-size: 13px; margin: 10px 0; line-height: 1.6;">${boon.description}</p>
      </div>
    `;
  });

  modalHTML += `
      </div>
      <p style="color: #888; font-size: 12px; margin-top: 20px; font-style: italic;">
        Choose wisely — this selection cannot be rerolled. Meeting your boon's condition rewards +1 Str, Dex, Int, Cha.
      </p>
    </div>
  `;

  createGameModal(modalHTML);

  // Add click handlers for boon selection
  document.querySelectorAll('.boon-choice-card').forEach((card, index) => {
    card.onclick = () => {
      const selectedBoon = selectedBoons[index];
      acquireItem(selectedBoon);
      closeGameModal();

      // Show notification
      setTimeout(() => {
        if (typeof createNotification === 'function') {
          createNotification(`Received ${selectedBoon.name}!`, '#8a2be2', '🌟');
        }

        // After notification, spawn next game choices (only if not starting boon)
        if (shouldSpawnChoices) {
          setTimeout(() => {
            if (typeof spawnChoices === 'function') {
              spawnChoices();
            }
          }, 300);
        }
      }, 100);
    };
  });
}

// ========================================
// EXPORTS
// ========================================

// Export location data
window.LOCATIONS_DATA = LOCATIONS_DATA;
window.GUNGEON_LOCATIONS = GUNGEON_LOCATIONS;
window.ISAAC_LOCATIONS = ISAAC_LOCATIONS;
window.HADES_LOCATIONS = HADES_LOCATIONS;
window.RISK_OF_RAIN_LOCATIONS = RISK_OF_RAIN_LOCATIONS;
window.CAVES_OF_QUD_LOCATIONS = CAVES_OF_QUD_LOCATIONS;

// Export organized data
window.locationsByDifficulty = locationsByDifficulty;
window.locationsByGame = locationsByGame;

// Export selection functions
window.getRandomLocation = getRandomLocation;
window.getDifficultyTier = getDifficultyTier;
window.DIFFICULTY_TIER_SIZE = DIFFICULTY_TIER_SIZE;
window.DIFFICULTY_THRESHOLDS = DIFFICULTY_THRESHOLDS;

// Export utility functions
window.getLocationGame = getLocationGame;
window.isLocationFromGame = isLocationFromGame;
window.getLocationsByGame = getLocationsByGame;

// Export effect handler functions
window.hasGunSpawnBoost = hasGunSpawnBoost;
window.hasIsaacModifiers = hasIsaacModifiers;
window.hasGodBoonChoice = hasGodBoonChoice;
window.hasScalingReward = hasScalingReward;
window.hasAppearanceEffect = hasAppearanceEffect;
window.getLocationEffectDetails = getLocationEffectDetails;

// Export effect application functions
window.applyGunSpawnBoost = applyGunSpawnBoost;
window.applyIsaacModifiers = applyIsaacModifiers;
window.shouldOfferHadesBoon = shouldOfferHadesBoon;
window.showHadesBoonSelection = showHadesBoonSelection;
window.applyRiskOfRainEffect = applyRiskOfRainEffect;
window.showRoRExtraChestOffer = showRoRExtraChestOffer;
