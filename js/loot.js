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
    image: "chalm"
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
  },
  {
    name: "Scorching Sunfish",
    rarity: "Uncommon",
    type: "Firey",
    game: "Don't Starve Together",
    image: "scorching-sunfish"
  },
  {
    name: "Ice Bream",
    rarity: "Uncommon",
    type: "Icey",
    game: "Don't Starve Together",
    image: "ice-bream"
  },
  {
    name: "Mudfish",
    rarity: "Common",
    type: "Swampy",
    game: "Don't Starve Together",
    image: "mudfish"
  },
  {
    name: "Bitty Baitfish",
    rarity: "Rare",
    type: "General",
    game: "Don't Starve Together",
    image: "bitty-baitfish"
  },
  {
    name: "Sweetish Fish",
    rarity: "Common",
    type: "Swampy",
    game: "Don't Starve Together",
    image: "sweetish-fish"
  },
  {
    name: "Runty Guppy",
    rarity: "Uncommon",
    type: "General",
    game: "Don't Starve Together",
    image: "runty-guppy"
  },
  {
    name: "Smolt Fry",
    rarity: "Common",
    type: "General",
    game: "Don't Starve Together",
    image: "smolt-fry"
  },
  {
    name: "Needlenosed Squirt",
    rarity: "Common",
    type: "General",
    game: "Don't Starve Together",
    image: "needlenosed-squirt"
  },
  {
    name: "Jiffy",
    rarity: "Common",
    type: "Undead",
    game: "Hades II",
    image: "jiffy"
  },
  {
    name: "Goldfish",
    rarity: "Uncommon",
    type: "Undead",
    game: "Hades II",
    image: "goldfish"
  },
  {
    name: "Styxeon",
    rarity: "Rare",
    type: "Undead",
    game: "Hades II",
    image: "styxeon"
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
      item.tags && Array.isArray(item.tags) && item.tags.some(tag => typeof tag === 'string' && tag.toLowerCase().includes('fish'))
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
 * Check if player has Barrel item and trigger bonus fish
 * Should be called after obtaining any fish
 * @param {number} numFishObtained - Number of fish obtained in this event
 */
function triggerBarrelBonusFish(numFishObtained) {
  if (numFishObtained < 1) return;

  // Check if player has Barrel
  const hasBarrel = inventory.some(item => item.name === 'Barrel');
  if (!hasBarrel) return;

  // Determine bonus fish count based on weapon level (1/2/3)
  const weaponLevel = gameState.weaponLevel || 1;
  const bonusFishCount = weaponLevel; // Level 1 = 1 fish, Level 2 = 2 fish, Level 3 = 3 fish

  console.log(`Barrel triggered! Giving ${bonusFishCount} bonus fish`);

  // Give bonus fish
  for (let i = 0; i < bonusFishCount; i++) {
    const bonusFish = selectRandomFish(gameState.location);
    addToLoot(bonusFish);
  }

  // Show notification
  if (typeof createNotification === 'function') {
    createNotification(`Barrel gave ${bonusFishCount} bonus fish!`, '#ff9800', '🛢️');
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
// LOOT DISPLAY FUNCTIONS
// ========================================

/**
 * Show the loot modal with all fish/items in the loot inventory
 */
function showLootModal() {
  if (!gameState.loot) {
    gameState.loot = [];
  }

  const lootHTML = getLootHTML();

  const modalHTML = `
    <div style="text-align: center;">
      <h2 style="color: #66ddff; margin-top: 0;">Loot Inventory</h2>
      <p style="color: #aaa; margin-bottom: 20px;">
        Fish and items that can be sold at shops
      </p>
      <div id="loot-display" style="min-height: 200px;">
        ${lootHTML}
      </div>
      <button onclick="closeGameModal()" style="margin-top: 20px; padding: 12px 24px; background: #555; border: none; color: white; border-radius: 6px; cursor: pointer; font-weight: bold; font-size: 16px;">
        Close
      </button>
    </div>
  `;

  createGameModal(modalHTML);
}

/**
 * Get HTML for displaying loot items
 * @returns {string} HTML string
 */
function getLootHTML() {
  if (!gameState.loot || gameState.loot.length === 0) {
    return `
      <div style="text-align: center; padding: 40px; color: #888; font-style: italic;">
        No loot yet - catch some fish!
      </div>
    `;
  }

  let html = '<div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 15px; padding: 20px;">';

  gameState.loot.forEach((lootItem, index) => {
    if (lootItem.isItem) {
      // Regular item (from 5% chance)
      const item = lootItem.item;
      const imagePath = `images/items/${item.image}.png`;

      html += `
        <div class="loot-item" data-index="${index}" style="
          background: linear-gradient(135deg, rgba(100, 50, 150, 0.2), rgba(50, 25, 75, 0.2));
          border: 2px solid #8a2be2;
          border-radius: 8px;
          padding: 15px;
          cursor: pointer;
          transition: transform 0.2s, box-shadow 0.2s;
        " onmouseover="this.style.transform='scale(1.05)'; this.style.boxShadow='0 4px 12px rgba(138, 43, 226, 0.5)';" onmouseout="this.style.transform='scale(1)'; this.style.boxShadow='none';">
          <img src="${imagePath}" alt="${item.name}" style="width: 100%; height: 120px; object-fit: contain; object-position: center; border-radius: 6px; background: rgba(0,0,0,0.3); padding: 5px;">
          <div style="margin-top: 10px; font-weight: bold; color: #ba55d3; font-size: 14px;">${item.name}</div>
          <div style="margin-top: 5px; color: #888; font-size: 12px;">Item</div>
        </div>
      `;
    } else {
      // Fish
      const fish = lootItem.fish;
      const rarity = lootItem.rarity;
      const size = lootItem.size;
      const goldValue = getFishGoldValue(rarity, size);
      const imagePath = `images/fish/${fish.image}.png`;

      // Determine border color by rarity
      let borderColor = '#666';
      let rarityColor = '#aaa';
      if (rarity === 'Rare') {
        borderColor = '#ffd700';
        rarityColor = '#ffd700';
      } else if (rarity === 'Uncommon') {
        borderColor = '#66ddff';
        rarityColor = '#66ddff';
      } else {
        borderColor = '#999';
        rarityColor = '#999';
      }

      html += `
        <div class="loot-item" data-index="${index}" style="
          background: linear-gradient(135deg, rgba(50, 100, 150, 0.2), rgba(25, 50, 75, 0.2));
          border: 2px solid ${borderColor};
          border-radius: 8px;
          padding: 15px;
          cursor: pointer;
          transition: transform 0.2s, box-shadow 0.2s;
        " onmouseover="showLootTooltip(${index}, event)" onmouseout="hideLootTooltip()" onmousemove="moveLootTooltip(event)">
          <img src="${imagePath}" alt="${fish.name}" style="width: 100%; height: 120px; object-fit: contain; object-position: center; border-radius: 6px; background: rgba(0,0,0,0.3); padding: 5px;">
          <div style="margin-top: 10px; font-weight: bold; color: #66ddff; font-size: 14px;">${fish.name}</div>
          <div style="margin-top: 5px; color: ${rarityColor}; font-size: 12px;">${rarity} - ${size}</div>
          <div style="margin-top: 5px; color: #ffd700; font-size: 13px; font-weight: bold;">💰 ${goldValue}g</div>
        </div>
      `;
    }
  });

  html += '</div>';
  return html;
}

/**
 * Update the loot display (if modal is open)
 */
function updateLootDisplay() {
  const lootDisplay = document.getElementById('loot-display');
  if (lootDisplay) {
    lootDisplay.innerHTML = getLootHTML();
  }
}

/**
 * Show tooltip for loot item
 */
function showLootTooltip(index, event) {
  if (!gameState.loot || !gameState.loot[index]) return;

  const lootItem = gameState.loot[index];

  if (lootItem.isItem) {
    // Show item tooltip (use existing item tooltip if available)
    if (typeof showTooltip === 'function') {
      showTooltip(lootItem.item, event);
    }
  } else {
    // Show fish tooltip
    const fish = lootItem.fish;
    const rarity = lootItem.rarity;
    const size = lootItem.size;
    const goldValue = getFishGoldValue(rarity, size);
    const healthValue = getFishHealthValue(rarity, size);

    const tooltipHTML = `
      <div style="text-align: left;">
        <div style="font-weight: bold; color: #66ddff; font-size: 16px; margin-bottom: 8px;">${fish.name}</div>
        <div style="color: #aaa; font-size: 13px; margin-bottom: 4px;"><strong>Game:</strong> ${fish.game}</div>
        <div style="color: #aaa; font-size: 13px; margin-bottom: 4px;"><strong>Type:</strong> ${fish.type}</div>
        <div style="color: #ffd700; font-size: 13px; margin-bottom: 4px;"><strong>Rarity:</strong> ${rarity}</div>
        <div style="color: #88ff88; font-size: 13px; margin-bottom: 4px;"><strong>Size:</strong> ${size}</div>
        <div style="color: #ffd700; font-size: 14px; margin-top: 8px; font-weight: bold;">💰 Sell: ${goldValue}g</div>
        <div style="color: #ff6666; font-size: 14px; margin-top: 4px; font-weight: bold;">❤️ Sushi: ${healthValue} HP</div>
      </div>
    `;

    // Create or update tooltip
    let tooltip = document.getElementById('loot-tooltip');
    if (!tooltip) {
      tooltip = document.createElement('div');
      tooltip.id = 'loot-tooltip';
      tooltip.style.cssText = `
        position: fixed;
        background: rgba(0, 0, 0, 0.95);
        color: #fff;
        padding: 12px;
        border-radius: 8px;
        border: 2px solid #66ddff;
        z-index: 100000;
        pointer-events: none;
        max-width: 300px;
        box-shadow: 0 4px 16px rgba(0,0,0,0.8);
      `;
      document.body.appendChild(tooltip);
    }

    tooltip.innerHTML = tooltipHTML;
    tooltip.style.display = 'block';
    tooltip.style.left = (event.clientX + 15) + 'px';
    tooltip.style.top = (event.clientY + 15) + 'px';
  }
}

/**
 * Move tooltip with mouse
 */
function moveLootTooltip(event) {
  const tooltip = document.getElementById('loot-tooltip');
  if (tooltip && tooltip.style.display === 'block') {
    tooltip.style.left = (event.clientX + 15) + 'px';
    tooltip.style.top = (event.clientY + 15) + 'px';
  }
}

/**
 * Hide loot tooltip
 */
function hideLootTooltip() {
  const tooltip = document.getElementById('loot-tooltip');
  if (tooltip) {
    tooltip.style.display = 'none';
  }
}

// ========================================
// FISHING MINIGAME
// ========================================

/**
 * Start the fishing minigame
 * @param {number} numAttempts - Number of fishing attempts (default 3)
 * @param {function} onComplete - Callback when fishing is complete, receives array of caught fish
 */
function startFishingMinigame(numAttempts = 3, onComplete) {
  const caughtFish = [];
  let currentAttempt = 0;

  // Timing for each attempt (decreasing)
  const attemptTimings = [3000, 2000, 1000]; // ms to click after button activates

  function doFishingAttempt() {
    currentAttempt++;

    if (currentAttempt > numAttempts) {
      // Fishing complete
      if (onComplete) {
        onComplete(caughtFish);
      }
      return;
    }

    // Show fishing UI
    showFishingAttemptUI(currentAttempt, numAttempts, attemptTimings[currentAttempt - 1], (caught, fishData) => {
      if (caught && fishData) {
        caughtFish.push(fishData);
      }
      // Continue to next attempt after a brief delay
      setTimeout(() => {
        doFishingAttempt();
      }, 500);
    });
  }

  doFishingAttempt();
}

/**
 * Show the UI for a single fishing attempt
 */
function showFishingAttemptUI(attemptNumber, totalAttempts, clickWindow, onAttemptComplete) {
  // Create or update fishing modal
  const modalHTML = `
    <div id="fishing-container" style="text-align: center; padding: 40px;">
      <h3 style="color: #66ddff; margin-bottom: 20px;">Fishing Minigame - Attempt ${attemptNumber} of ${totalAttempts}</h3>

      <div style="position: relative; display: flex; align-items: flex-end; justify-content: center; gap: 40px; margin-bottom: 30px;">
        <!-- Left side: Character and caught fish display above -->
        <div style="display: flex; flex-direction: column; align-items: center; gap: 20px; margin-right: 40px;">
          <!-- All caught fish display (persistent across attempts, above character) -->
          <div id="all-caught-fish-container" style="display: flex; justify-content: center; gap: 15px; min-height: 180px; flex-wrap: wrap; max-width: 450px;"></div>

          <!-- Character Image -->
          <div id="fishing-character" style="width: 250px; height: 250px;">
            ${gameState?.character && PLAYER_CHARACTERS[gameState.character] ?
              `<img src="${PLAYER_CHARACTERS[gameState.character].icon}" style="width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated;">` :
              ''
            }
          </div>
        </div>

        <!-- Water Rectangle -->
        <div id="water-container" style="position: relative; width: 600px; height: 400px; background: linear-gradient(180deg, #87ceeb 0%, #4682b4 100%); border-radius: 12px; box-shadow: 0 4px 20px rgba(68, 136, 255, 0.4); overflow: hidden;">
          <!-- Fishing Button (exclamation mark) will be positioned randomly inside -->
          <button id="fishing-btn" style="
            position: absolute;
            width: 80px;
            height: 80px;
            font-size: 48px;
            background: #555;
            border: 4px solid #666;
            border-radius: 50%;
            cursor: pointer;
            transition: all 0.2s;
            opacity: 0;
            pointer-events: none;
            left: 50%;
            top: 50%;
            transform: translate(-50%, -50%);
          ">!</button>
        </div>
      </div>

      <div id="fishing-message" style="min-height: 30px; color: #ffd700; font-size: 18px; font-weight: bold;"></div>
    </div>
  `;

  // Check if modal already exists
  const existingModal = document.querySelector('.game-modal');
  if (existingModal) {
    // Update existing modal content (only on first attempt)
    if (attemptNumber === 1) {
      existingModal.innerHTML = modalHTML;
    } else {
      // Update only the attempt counter
      const container = document.getElementById('fishing-container');
      if (container) {
        const header = container.querySelector('h3');
        if (header) {
          header.textContent = `Fishing Minigame - Attempt ${attemptNumber} of ${totalAttempts}`;
        }
      }
    }
  } else {
    // Create new modal
    createGameModal(modalHTML);
  }

  const fishingBtn = document.getElementById('fishing-btn');
  const fishingMessage = document.getElementById('fishing-message');

  let buttonActive = false;
  let buttonClicked = false;
  let activationTimeout;
  let expirationTimeout;

  // Random delay before button activates (3-10 seconds)
  const activationDelay = 3000 + Math.random() * 7000;

  fishingMessage.textContent = 'Wait for the !...';

  // Handle clicks on water container (early click = failure)
  const waterContainer = document.getElementById('water-container');
  const handleWaterClick = () => {
    if (!buttonActive && !buttonClicked) {
      buttonClicked = true;
      clearTimeout(activationTimeout);

      // Failed by clicking too early
      fishingMessage.textContent = 'Too early! The fish got away...';
      fishingBtn.disabled = true;
      fishingBtn.style.background = '#ff4444';
      fishingBtn.style.borderColor = '#ff6666';
      fishingBtn.style.cursor = 'not-allowed';
      fishingBtn.style.opacity = '0.5';

      // Add miss indicator to persistent container
      const allCaughtContainer = document.getElementById('all-caught-fish-container');
      if (allCaughtContainer) {
        const missCard = document.createElement('div');
        missCard.innerHTML = `
          <div style="animation: fishCatch 0.5s ease-out;">
            <div style="display: inline-block; padding: 15px; background: rgba(100, 50, 50, 0.3); border: 3px solid #ff4444; border-radius: 12px; width: 130px; height: 130px; display: flex; align-items: center; justify-content: center;">
              <div style="font-size: 48px;">❌</div>
            </div>
          </div>
        `;
        allCaughtContainer.appendChild(missCard);
      }

      setTimeout(() => {
        onAttemptComplete(false, null);
      }, 1500);
    }
  };

  // Attach early click handler to water container
  waterContainer.onclick = handleWaterClick;

  activationTimeout = setTimeout(() => {
    // Activate button
    buttonActive = true;

    // Position button randomly within the water container
    // Water container is 600px wide and 400px tall, button is 80px
    // So we can position from 0 to (600-80) and 0 to (400-80)
    const maxX = 520; // 600 - 80
    const maxY = 320; // 400 - 80
    const randomX = Math.random() * maxX;
    const randomY = Math.random() * maxY;

    fishingBtn.style.left = randomX + 'px';
    fishingBtn.style.top = randomY + 'px';
    fishingBtn.style.transform = 'none'; // Remove the centering transform

    fishingBtn.disabled = false;
    fishingBtn.style.background = '#4488ff';
    fishingBtn.style.borderColor = '#66aaff';
    fishingBtn.style.cursor = 'pointer';
    fishingBtn.style.opacity = '1';
    fishingBtn.style.pointerEvents = 'auto';
    fishingBtn.style.boxShadow = '0 0 30px rgba(68, 136, 255, 0.8)';
    fishingMessage.textContent = 'CLICK NOW!';

    // Set expiration timer
    expirationTimeout = setTimeout(() => {
      if (!buttonClicked) {
        // Failed to click in time
        fishingMessage.textContent = 'It got away...';
        fishingBtn.disabled = true;
        fishingBtn.style.background = '#555';
        fishingBtn.style.cursor = 'not-allowed';
        fishingBtn.style.opacity = '0.3';
        fishingBtn.style.pointerEvents = 'none';

        // Add miss indicator to persistent container
        const allCaughtContainer = document.getElementById('all-caught-fish-container');
        if (allCaughtContainer) {
          const missCard = document.createElement('div');
          missCard.innerHTML = `
            <div style="animation: fishCatch 0.5s ease-out;">
              <div style="display: inline-block; padding: 15px; background: rgba(100, 50, 50, 0.3); border: 3px solid #ff4444; border-radius: 12px; width: 130px; height: 130px; display: flex; align-items: center; justify-content: center;">
                <div style="font-size: 48px;">❌</div>
              </div>
            </div>
          `;
          allCaughtContainer.appendChild(missCard);
        }

        setTimeout(() => {
          onAttemptComplete(false, null);
        }, 1500);
      }
    }, clickWindow);
  }, activationDelay);

  // Use onmousedown instead of onclick to trigger on press
  fishingBtn.onmousedown = (e) => {
    e.stopPropagation(); // Prevent water container click from firing

    if (buttonClicked) return;

    if (!buttonActive) {
      return; // Should never happen since button is invisible when inactive
    }

    buttonClicked = true;
    clearTimeout(expirationTimeout);

    // Success! Catch a fish
    fishingMessage.textContent = 'You caught something!';
    fishingBtn.style.background = '#44ff44';
    fishingBtn.style.borderColor = '#66ff66';

    // Select a random fish based on location
    const fishResult = selectRandomFish(gameState.location);

    // Create the fish/item card HTML
    let cardHTML = '';

    if (fishResult.isItem) {
      // Caught an item instead of fish
      const item = fishResult.item;
      cardHTML = `
        <div style="animation: fishCatch 0.5s ease-out;">
          <div style="display: inline-block; padding: 15px; background: linear-gradient(135deg, rgba(138, 43, 226, 0.3), rgba(75, 0, 130, 0.3)); border: 3px solid #8a2be2; border-radius: 12px; box-shadow: 0 0 40px rgba(138, 43, 226, 0.6);">
            <img src="images/items/${item.image}.png" style="width: 100px; height: 100px; object-fit: contain;">
            <div style="margin-top: 8px; font-size: 16px; font-weight: bold; color: #ba55d3;">${item.name}</div>
            <div style="margin-top: 3px; color: #aaa; font-size: 12px;">Special Item!</div>
          </div>
        </div>
      `;
    } else {
      // Caught a fish
      const fish = fishResult.fish;
      const rarity = fishResult.rarity;
      const size = fishResult.size;
      const goldValue = getFishGoldValue(rarity, size);

      // Track fish catch
      incrementFishCaught(fish.name, size);

      let rarityColor = '#aaa';
      if (rarity === 'Rare') rarityColor = '#ffd700';
      else if (rarity === 'Uncommon') rarityColor = '#66ddff';

      cardHTML = `
        <div style="animation: fishCatch 0.5s ease-out;">
          <div style="display: inline-block; padding: 15px; background: linear-gradient(135deg, rgba(68, 136, 255, 0.3), rgba(34, 68, 128, 0.3)); border: 3px solid ${rarityColor}; border-radius: 12px; box-shadow: 0 0 40px ${rarityColor}80;">
            <img src="images/fish/${fish.image}.png" style="width: 100px; height: 100px; object-fit: contain;">
            <div style="margin-top: 8px; font-size: 16px; font-weight: bold; color: #66ddff;">${fish.name}</div>
            <div style="margin-top: 3px; color: ${rarityColor}; font-size: 12px;">${rarity} - ${size}</div>
            <div style="margin-top: 3px; color: #ffd700; font-weight: bold; font-size: 13px;">💰 ${goldValue}g</div>
          </div>
        </div>
      `;
    }

    // Add to the persistent container above character
    const allCaughtContainer = document.getElementById('all-caught-fish-container');
    if (allCaughtContainer) {
      const permanentCard = document.createElement('div');
      permanentCard.innerHTML = cardHTML;
      allCaughtContainer.appendChild(permanentCard);
    }

    // Add CSS animation if not already present
    if (!document.getElementById('fishing-animations')) {
      const style = document.createElement('style');
      style.id = 'fishing-animations';
      style.textContent = `
        @keyframes fishCatch {
          0% { transform: translateY(50px); opacity: 0; }
          100% { transform: translateY(0); opacity: 1; }
        }
      `;
      document.head.appendChild(style);
    }

    setTimeout(() => {
      onAttemptComplete(true, fishResult);
    }, 2000);
  };
}

// ========================================
// SUSHI BAR EVENT
// ========================================

/**
 * Show the Sushi Bar event - goes directly to fishing minigame
 */
function showSushiBarEvent() {
  // Start fishing minigame directly (event description already shown)
  startSushiBarFishing();
}

/**
 * Start the fishing portion of the Sushi Bar event
 */
function startSushiBarFishing() {
  // Start fishing minigame with 3 attempts
  startFishingMinigame(3, (caughtFish) => {
    // Show results based on catches
    if (caughtFish.length === 0) {
      // No fish caught - failure prompt
      showSushiBarFailure();
    } else {
      // Fish caught - success prompt with choices
      showSushiBarSuccess(caughtFish);
    }
  });
}

/**
 * Show failure prompt (no fish caught)
 */
function showSushiBarFailure() {
  const failureHTML = `
    <div style="text-align: center; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #888; margin-top: 0;">🍣 No Catch Today</h2>
      <p style="color: #e6d5b8; font-size: 16px; line-height: 1.6; margin: 20px 0;">
        You can tell the man is disappointed, but he tells you that the fish just might not have been biting today.
      </p>
      <button onclick="closeGameModal()" style="
        margin-top: 20px;
        padding: 12px 30px;
        background: #555;
        border: none;
        color: white;
        border-radius: 8px;
        cursor: pointer;
        font-weight: bold;
        font-size: 16px;
      ">Continue</button>
    </div>
  `;

  createGameModal(failureHTML);
}

/**
 * Show success prompt with choices
 */
function showSushiBarSuccess(caughtFish) {
  const successHTML = `
    <div style="text-align: center; max-width: 700px; margin: 0 auto;">
      <h2 style="color: #ffd700; margin-top: 0;">🍣 Successful Catch!</h2>
      <p style="color: #e6d5b8; font-size: 16px; line-height: 1.6; margin: 20px 0;">
        The old man congratulates you on the successful catch, and offers to have the nearby chef prepare some sushi.
      </p>

      <div style="display: flex; gap: 20px; justify-content: center; margin-top: 30px;">
        <button onclick="keepFishFromSushiBar()" style="
          flex: 1;
          max-width: 300px;
          padding: 15px 20px;
          background: linear-gradient(145deg, #4488ff, #2255cc);
          border: 2px solid #66aaff;
          color: white;
          border-radius: 8px;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
          transition: transform 0.2s;
        " onmouseover="this.style.transform='scale(1.05)'" onmouseout="this.style.transform='scale(1)'">
          🎒 Keep the Fish<br>
          <span style="font-size: 13px; opacity: 0.8;">Sell them later for gold</span>
        </button>

        <button onclick="convertFishToSushi()" style="
          flex: 1;
          max-width: 300px;
          padding: 15px 20px;
          background: linear-gradient(145deg, #ff6666, #cc3333);
          border: 2px solid #ff8888;
          color: white;
          border-radius: 8px;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
          transition: transform 0.2s;
        " onmouseover="this.style.transform='scale(1.05)'" onmouseout="this.style.transform='scale(1)'">
          🍱 Prepare Sushi<br>
          <span style="font-size: 13px; opacity: 0.8;">Exchange fish for health</span>
        </button>
      </div>
    </div>
  `;

  createGameModal(successHTML);

  // Store caught fish in temporary state
  window.tempSushiBarFish = caughtFish;
}

/**
 * Keep all fish - add to loot inventory
 */
function keepFishFromSushiBar() {
  if (window.tempSushiBarFish) {
    const numFish = window.tempSushiBarFish.length;

    window.tempSushiBarFish.forEach(fishData => {
      addToLoot(fishData);
    });

    if (typeof createNotification === 'function') {
      createNotification(`Added ${numFish} fish to loot!`, '#4488ff', '🐟');
    }

    window.tempSushiBarFish = null;
  }

  closeGameModal();
}

/**
 * Convert fish to sushi - show selection UI
 */
function convertFishToSushi() {
  if (!window.tempSushiBarFish || window.tempSushiBarFish.length === 0) {
    closeGameModal();
    return;
  }

  const fishList = window.tempSushiBarFish;

  let fishHTML = '<div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 15px; padding: 20px;">';

  fishList.forEach((fishData, index) => {
    if (fishData.isItem) {
      // Item can't be converted to sushi, skip
      return;
    }

    const fish = fishData.fish;
    const rarity = fishData.rarity;
    const size = fishData.size;
    const healthValue = getFishHealthValue(rarity, size);

    let rarityColor = '#aaa';
    if (rarity === 'Rare') rarityColor = '#ffd700';
    else if (rarity === 'Uncommon') rarityColor = '#66ddff';

    fishHTML += `
      <div class="sushi-fish-option" data-index="${index}" style="
        background: linear-gradient(135deg, rgba(68, 136, 255, 0.2), rgba(34, 68, 128, 0.2));
        border: 3px solid ${rarityColor};
        border-radius: 12px;
        padding: 15px;
        cursor: pointer;
        transition: transform 0.2s, box-shadow 0.2s;
      " onmouseover="this.style.transform='scale(1.05)'; this.style.boxShadow='0 4px 12px ${rarityColor}80';" onmouseout="this.style.transform='scale(1)'; this.style.boxShadow='none';" onclick="selectFishForSushi(${index})">
        <img src="images/fish/${fish.image}.png" style="width: 100%; height: 140px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); padding: 10px;">
        <div style="margin-top: 10px; font-weight: bold; color: #66ddff; font-size: 16px;">${fish.name}</div>
        <div style="margin-top: 5px; color: ${rarityColor}; font-size: 13px;">${rarity} - ${size}</div>
        <div style="margin-top: 8px; color: #ff6666; font-size: 15px; font-weight: bold;">❤️ +${healthValue} HP</div>
      </div>
    `;
  });

  fishHTML += '</div>';

  const selectionHTML = `
    <div style="text-align: center;">
      <h2 style="color: #ffd700; margin-top: 0;">🍱 Select Fish to Convert to Sushi</h2>
      <p style="color: #aaa; margin-bottom: 20px;">
        Click on fish to exchange them for health. Unconverted fish will be added to your loot.
      </p>
      ${fishHTML}
      <button onclick="finishSushiConversion()" style="
        margin-top: 20px;
        padding: 12px 30px;
        background: #44aa44;
        border: none;
        color: white;
        border-radius: 8px;
        cursor: pointer;
        font-weight: bold;
        font-size: 16px;
      ">Done</button>
    </div>
  `;

  createGameModal(selectionHTML);

  // Track which fish have been converted
  window.tempSushiConvertedIndices = new Set();
}

/**
 * Select a fish for sushi conversion
 */
function selectFishForSushi(index) {
  if (!window.tempSushiBarFish || !window.tempSushiBarFish[index]) return;

  const fishData = window.tempSushiBarFish[index];
  if (fishData.isItem) return; // Can't convert items

  const rarity = fishData.rarity;
  const size = fishData.size;
  const healthValue = getFishHealthValue(rarity, size);

  // Add health
  health = Math.min(health + healthValue, maxHealth);
  gameState.health = health;

  if (typeof updateTopBar === 'function') {
    updateTopBar();
  }

  if (typeof createNotification === 'function') {
    createNotification(`+${healthValue} HP from sushi!`, '#ff6666', '❤️');
  }

  // Mark as converted
  if (!window.tempSushiConvertedIndices) {
    window.tempSushiConvertedIndices = new Set();
  }
  window.tempSushiConvertedIndices.add(index);

  // Remove the card from UI
  const card = document.querySelector(`.sushi-fish-option[data-index="${index}"]`);
  if (card) {
    card.style.opacity = '0.3';
    card.style.pointerEvents = 'none';
    card.innerHTML += '<div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); font-size: 48px;">✓</div>';
    card.style.position = 'relative';
  }
}

/**
 * Finish sushi conversion - add remaining fish to loot
 */
function finishSushiConversion() {
  if (window.tempSushiBarFish) {
    // Add unconverted fish to loot
    window.tempSushiBarFish.forEach((fishData, index) => {
      if (!window.tempSushiConvertedIndices || !window.tempSushiConvertedIndices.has(index)) {
        addToLoot(fishData);
      }
    });

    const remainingCount = window.tempSushiBarFish.length - (window.tempSushiConvertedIndices?.size || 0);
    if (remainingCount > 0 && typeof createNotification === 'function') {
      createNotification(`Added ${remainingCount} fish to loot!`, '#4488ff', '🐟');
    }

    window.tempSushiBarFish = null;
    window.tempSushiConvertedIndices = null;
  }

  closeGameModal();
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
window.showLootModal = showLootModal;
window.updateLootDisplay = updateLootDisplay;
window.showLootTooltip = showLootTooltip;
window.moveLootTooltip = moveLootTooltip;
window.hideLootTooltip = hideLootTooltip;
window.startFishingMinigame = startFishingMinigame;
window.showSushiBarEvent = showSushiBarEvent;
window.startSushiBarFishing = startSushiBarFishing;
window.keepFishFromSushiBar = keepFishFromSushiBar;
window.convertFishToSushi = convertFishToSushi;
window.selectFishForSushi = selectFishForSushi;
window.finishSushiConversion = finishSushiConversion;
