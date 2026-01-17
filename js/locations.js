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
// COMBINED LOCATIONS DATA
// ========================================
const LOCATIONS_DATA = [
  ...GUNGEON_LOCATIONS,
  ...ISAAC_LOCATIONS,
  ...HADES_LOCATIONS,
  ...RISK_OF_RAIN_LOCATIONS
];

// ========================================
// LOCATION ORGANIZATION
// ========================================

// Organize locations by difficulty
const locationsByDifficulty = {
  easy: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Easy'),
  medium: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Medium'),
  hard: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Hard')
};

// Organize locations by game
const locationsByGame = {
  gungeon: GUNGEON_LOCATIONS,
  isaac: ISAAC_LOCATIONS,
  hades: HADES_LOCATIONS,
  riskOfRain: RISK_OF_RAIN_LOCATIONS
};

// ========================================
// LOCATION SELECTION FUNCTIONS
// ========================================

/**
 * Get a random location based on difficulty tier
 * @param {string} difficulty - 'Easy', 'Medium', or 'Hard'
 * @returns {Object|null} Random location object or null if none available
 */
function getRandomLocation(difficulty) {
  const difficultyKey = difficulty.toLowerCase();
  const locations = locationsByDifficulty[difficultyKey] || locationsByDifficulty.easy;

  if (locations.length === 0) {
    return null;
  }

  const randomIndex = Math.floor(Math.random() * locations.length);
  return locations[randomIndex];
}

/**
 * Get difficulty tier based on player progress
 * @param {number} beatenGamesCount - Number of games the player has beaten
 * @returns {string} 'Easy', 'Medium', or 'Hard'
 */
function getDifficultyTier(beatenGamesCount) {
  if (beatenGamesCount < 5) {
    return 'Easy';
  } else if (beatenGamesCount < 10) {
    return 'Medium';
  } else {
    return 'Hard';
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
      console.log(`Isaac location effect: ${gameName} is now Holy!`);
    }
  } else if (roll < 0.20) {
    // Apply Devilish status
    if (typeof addGameStatus === 'function') {
      addGameStatus(gameName, 'devilish', '👹');
      console.log(`Isaac location effect: ${gameName} is now Devilish!`);
    }
  } else if (roll < 0.30) {
    // Apply Stinky status
    if (typeof addGameStatus === 'function') {
      addGameStatus(gameName, 'stinky', '💩');
      console.log(`Isaac location effect: ${gameName} is now Stinky!`);
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
    console.log('Risk of Rain location effect: Difficulty will increase!');
  }

  // Always offer extra chest for 10 gold
  result.offerExtraChest = true;

  return result;
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

// Export organized data
window.locationsByDifficulty = locationsByDifficulty;
window.locationsByGame = locationsByGame;

// Export selection functions
window.getRandomLocation = getRandomLocation;
window.getDifficultyTier = getDifficultyTier;

// Export utility functions
window.getLocationGame = getLocationGame;
window.isLocationFromGame = isLocationFromGame;
window.getLocationsByGame = getLocationsByGame;

// Export effect handler functions
window.hasGunSpawnBoost = hasGunSpawnBoost;
window.hasIsaacModifiers = hasIsaacModifiers;
window.hasGodBoonChoice = hasGodBoonChoice;
window.hasScalingReward = hasScalingReward;
window.getLocationEffectDetails = getLocationEffectDetails;

// Export effect application functions
window.applyGunSpawnBoost = applyGunSpawnBoost;
window.applyIsaacModifiers = applyIsaacModifiers;
window.shouldOfferHadesBoon = shouldOfferHadesBoon;
window.applyRiskOfRainEffect = applyRiskOfRainEffect;
