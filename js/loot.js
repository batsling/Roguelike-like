// ===== LOOT.JS - Loot and Fish System =====
//
// This module contains all fish data and loot management functions.
// Fish can be caught during fishing minigames and sold in shops for gold.
//
// Fish Structure:
// - name: Fish name
// - rarity: Common, Uncommon, or Rare
// - type: Location type (Undead, Firey, Watery, Building, Chaos, General)
// - game: Source game
// - image: Image filename (without .png extension)

// ========================================
// FISH DATA
// ========================================

const FISH_DATA = [
  {
    name: "Hellfish",
    rarity: "Common",
    type: "Undead",
    game: "Hades",
    image: "hellfish"
  },
  {
    name: "Knucklehead",
    rarity: "Uncommon",
    type: "Undead",
    game: "Hades",
    image: "knucklehead"
  },
  {
    name: "Scyllascion",
    rarity: "Rare",
    type: "Undead",
    game: "Hades",
    image: "scyllascion"
  },
  {
    name: "Slavug",
    rarity: "Common",
    type: "Firey",
    game: "Hades",
    image: "slavug"
  },
  {
    name: "Chrustacean",
    rarity: "Uncommon",
    type: "Firey",
    game: "Hades",
    image: "chrustacean"
  },
  {
    name: "Flameater",
    rarity: "Rare",
    type: "Firey",
    game: "Hades",
    image: "flameater"
  },
  {
    name: "Chlam",
    rarity: "Common",
    type: "Watery",
    game: "Hades",
    image: "chlam"
  },
  {
    name: "Charp",
    rarity: "Uncommon",
    type: "Watery",
    game: "Hades",
    image: "charp"
  },
  {
    name: "Seamare",
    rarity: "Rare",
    type: "Watery",
    game: "Hades",
    image: "seamare"
  },
  {
    name: "Gupp",
    rarity: "Common",
    type: "Building",
    game: "Hades",
    image: "gupp"
  },
  {
    name: "Scuffer",
    rarity: "Uncommon",
    type: "Building",
    game: "Hades",
    image: "scuffer"
  },
  {
    name: "Stonewhal",
    rarity: "Rare",
    type: "Building",
    game: "Hades",
    image: "stonewhal"
  },
  {
    name: "Mati",
    rarity: "Common",
    type: "Chaos",
    game: "Hades",
    image: "mati"
  },
  {
    name: "Projelly",
    rarity: "Uncommon",
    type: "Chaos",
    game: "Hades",
    image: "projelly"
  },
  {
    name: "Voidskate",
    rarity: "Rare",
    type: "Chaos",
    game: "Hades",
    image: "voidskate"
  },
  {
    name: "Trout",
    rarity: "Common",
    type: "General",
    game: "Hades",
    image: "trout"
  },
  {
    name: "Bass",
    rarity: "Uncommon",
    type: "General",
    game: "Hades",
    image: "bass"
  },
  {
    name: "Sturgeon",
    rarity: "Rare",
    type: "General",
    game: "Hades",
    image: "sturgeon"
  },
  {
    name: "Minnow",
    rarity: "Common",
    type: "General",
    game: "Cult of the Lamb",
    image: "minnow"
  },
  {
    name: "Crab",
    rarity: "Common",
    type: "General",
    game: "Cult of the Lamb",
    image: "crab"
  },
  {
    name: "Salmon",
    rarity: "Uncommon",
    type: "General",
    game: "Cult of the Lamb",
    image: "salmon"
  },
  {
    name: "Tuna",
    rarity: "Uncommon",
    type: "General",
    game: "Cult of the Lamb",
    image: "tuna"
  },
  {
    name: "Blowfish",
    rarity: "Rare",
    type: "General",
    game: "Cult of the Lamb",
    image: "blowfish"
  },
  {
    name: "Octopus",
    rarity: "Rare",
    type: "General",
    game: "Cult of the Lamb",
    image: "octopus"
  },
  {
    name: "Squid",
    rarity: "Rare",
    type: "General",
    game: "Cult of the Lamb",
    image: "squid"
  },
  {
    name: "Swordfish",
    rarity: "Rare",
    type: "General",
    game: "Cult of the Lamb",
    image: "swordfish"
  },
  {
    name: "Lobster",
    rarity: "Rare",
    type: "General",
    game: "Cult of the Lamb",
    image: "lobster"
  }
];

// ========================================
// FISH SELECTION FUNCTIONS
// ========================================

/**
 * Select a random fish based on location type, with rarity and size
 * @param {Object} location - Current location object (has .type property)
 * @returns {Object} Fish object with rarity, size, and data
 */
function selectRandomFish(location) {
  // Step 1: Determine rarity (affected by luck)
  // Base: 50% Common, 30% Uncommon, 15% Rare, 5% Item with "fish" tag
  let commonChance = 50;
  let uncommonChance = 30;
  let rareChance = 15;
  let itemChance = 5;

  // Apply luck modifiers (-3%/+2%/+1% for common/uncommon/rare)
  if (typeof luck !== 'undefined') {
    commonChance = Math.max(0, commonChance - (luck * 3));
    uncommonChance = Math.min(100, uncommonChance + (luck * 2));
    rareChance = Math.min(100, rareChance + (luck * 1));
  }

  // Normalize to ensure total is 100%
  const total = commonChance + uncommonChance + rareChance + itemChance;
  commonChance = (commonChance / total) * 100;
  uncommonChance = (uncommonChance / total) * 100;
  rareChance = (rareChance / total) * 100;
  itemChance = (itemChance / total) * 100;

  const rarityRoll = Math.random() * 100;
  let selectedRarity;

  if (rarityRoll < itemChance) {
    // 5% chance: Give random item with "fish" tag
    const fishTaggedItems = items.filter(item =>
      item.tags && item.tags.toLowerCase().includes('fish')
    );

    if (fishTaggedItems.length > 0) {
      const randomItem = fishTaggedItems[Math.floor(Math.random() * fishTaggedItems.length)];
      return {
        isItem: true,
        item: randomItem
      };
    } else {
      // Fallback to rare fish if no fish-tagged items exist
      selectedRarity = 'Rare';
    }
  } else if (rarityRoll < itemChance + rareChance) {
    selectedRarity = 'Rare';
  } else if (rarityRoll < itemChance + rareChance + uncommonChance) {
    selectedRarity = 'Uncommon';
  } else {
    selectedRarity = 'Common';
  }

  // Step 2: Determine size (affected by luck)
  // Base: 50% Small, 35% Medium, 15% Large
  let smallChance = 50;
  let mediumChance = 35;
  let largeChance = 15;

  // Apply luck modifiers (-3%/+2%/+1% for small/medium/large)
  if (typeof luck !== 'undefined') {
    smallChance = Math.max(0, smallChance - (luck * 3));
    mediumChance = Math.min(100, mediumChance + (luck * 2));
    largeChance = Math.min(100, largeChance + (luck * 1));
  }

  // Normalize
  const sizeTotal = smallChance + mediumChance + largeChance;
  smallChance = (smallChance / sizeTotal) * 100;
  mediumChance = (mediumChance / sizeTotal) * 100;
  largeChance = (largeChance / sizeTotal) * 100;

  const sizeRoll = Math.random() * 100;
  let selectedSize;

  if (sizeRoll < largeChance) {
    selectedSize = 'Large';
  } else if (sizeRoll < largeChance + mediumChance) {
    selectedSize = 'Medium';
  } else {
    selectedSize = 'Small';
  }

  // Step 3: Select fish based on location type
  // If location type is General or no fish of that type exist: 100% General
  // Otherwise: 75% location type, 25% General

  const locationType = location?.type || 'General';

  // Get fish matching the rarity
  const fishByRarity = FISH_DATA.filter(f => f.rarity === selectedRarity);

  // Get fish matching location type and rarity
  const locationTypeFish = fishByRarity.filter(f => f.type === locationType);
  const generalFish = fishByRarity.filter(f => f.type === 'General');

  let selectedFish;

  if (locationType === 'General' || locationTypeFish.length === 0) {
    // Only general fish
    if (generalFish.length > 0) {
      selectedFish = generalFish[Math.floor(Math.random() * generalFish.length)];
    } else {
      // Fallback to any fish of this rarity
      selectedFish = fishByRarity[Math.floor(Math.random() * fishByRarity.length)];
    }
  } else {
    // 75% location type, 25% general
    const typeRoll = Math.random() * 100;

    if (typeRoll < 75 && locationTypeFish.length > 0) {
      selectedFish = locationTypeFish[Math.floor(Math.random() * locationTypeFish.length)];
    } else if (generalFish.length > 0) {
      selectedFish = generalFish[Math.floor(Math.random() * generalFish.length)];
    } else {
      // Fallback to location type fish
      selectedFish = locationTypeFish[Math.floor(Math.random() * locationTypeFish.length)];
    }
  }

  return {
    isItem: false,
    fish: selectedFish,
    rarity: selectedRarity,
    size: selectedSize
  };
}

/**
 * Calculate the gold value of a fish based on rarity and size
 * Medium Common = 10g, Medium Uncommon = 20g, Medium Rare = 50g
 * Small = half, Large = double
 * @param {string} rarity - Common, Uncommon, or Rare
 * @param {string} size - Small, Medium, or Large
 * @returns {number} Gold value
 */
function getFishGoldValue(rarity, size) {
  let baseValue = 10; // Medium Common = 10g

  if (rarity === 'Uncommon') {
    baseValue = 20;
  } else if (rarity === 'Rare') {
    baseValue = 50;
  }

  if (size === 'Small') {
    return Math.floor(baseValue / 2);
  } else if (size === 'Large') {
    return baseValue * 2;
  }

  return baseValue;
}

/**
 * Calculate the health value of a fish when converted to sushi
 * Medium Common = 2HP, Medium Uncommon = 4HP, Medium Rare = 6HP
 * Small = half, Large = double
 * @param {string} rarity - Common, Uncommon, or Rare
 * @param {string} size - Small, Medium, or Large
 * @returns {number} Health value
 */
function getFishHealthValue(rarity, size) {
  let baseValue = 2; // Medium Common = 2HP

  if (rarity === 'Uncommon') {
    baseValue = 4;
  } else if (rarity === 'Rare') {
    baseValue = 6;
  }

  if (size === 'Small') {
    return Math.floor(baseValue / 2);
  } else if (size === 'Large') {
    return baseValue * 2;
  }

  return baseValue;
}

/**
 * Add a fish (or item) to the loot inventory
 * @param {Object} lootItem - Fish object with fish, rarity, size or item object
 */
function addToLoot(lootItem) {
  if (!gameState.loot) {
    gameState.loot = [];
  }

  gameState.loot.push(lootItem);
  console.log('Added to loot:', lootItem);

  // Update loot display if it's open
  if (typeof updateLootDisplay === 'function') {
    updateLootDisplay();
  }
}

/**
 * Remove a fish from the loot inventory
 * @param {number} index - Index of the fish in the loot array
 */
function removeFromLoot(index) {
  if (!gameState.loot || index < 0 || index >= gameState.loot.length) {
    console.error('Invalid loot index:', index);
    return;
  }

  gameState.loot.splice(index, 1);
  console.log('Removed from loot at index:', index);

  // Update loot display if it's open
  if (typeof updateLootDisplay === 'function') {
    updateLootDisplay();
  }
}

// ========================================
// EXPORTS
// ========================================

window.FISH_DATA = FISH_DATA;
window.selectRandomFish = selectRandomFish;
window.getFishGoldValue = getFishGoldValue;
window.getFishHealthValue = getFishHealthValue;
window.addToLoot = addToLoot;
window.removeFromLoot = removeFromLoot;
