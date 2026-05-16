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
  // Luck grants advantage on the roll (10% per luck point chance to roll twice, take higher)
  const commonChance = 50, uncommonChance = 30, rareChance = 15, itemChance = 5;

  const rarityRoll = rollWithLuckAdvantage() * 100;
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
  // Luck grants advantage on the roll (10% per luck point chance to roll twice, take higher)
  const smallChance = 50, mediumChance = 35, largeChance = 15;

  const sizeRoll = rollWithLuckAdvantage() * 100;
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

  // Update loot display if it's open
  if (typeof updateLootDisplay === 'function') {
    updateLootDisplay();
  }
}

// ========================================
// LOOT DISPLAY FUNCTIONS
// ========================================

/**
 * Show the loot modal with tabbed display: Fish | Scrolls | Potions
 */
function showLootModal() {
  if (!gameState.loot) gameState.loot = [];

  const modalHTML = `
    <div style="text-align:center; min-width:340px; max-width:700px;">
      <h2 style="color:#66ddff; margin-top:0;">🎒 Loot</h2>
      <div id="loot-display" style="min-height:200px; text-align:left;">
        ${getLootHTML()}
      </div>
      <button onclick="closeGameModal()" style="margin-top:16px; padding:10px 24px; background:#555; border:none; color:white; border-radius:6px; cursor:pointer; font-weight:bold; font-size:14px;">
        Close
      </button>
    </div>
  `;

  createGameModal(modalHTML);
}


/**
 * Get HTML for displaying loot items by tab
 * @returns {string} HTML string
 */
function getLootHTML() {
  if (!gameState.loot) gameState.loot = [];
  if (gameState.loot.length === 0) {
    return `<div style="text-align:center;padding:40px;color:#888;font-style:italic;">No loot yet.</div>`;
  }

  const scrollsHTML = _getScrollsLootHTML();
  const potionsHTML = _getPotionsLootHTML();

  // Fish / items section

  // Build fish/item cards
  const fishLoot = gameState.loot.filter(l => !l.type || l.type === 'fish' || l.isItem);
  let fishHTML = '';
  if (fishLoot.length > 0) {
    let cards = '<div style="display:grid; grid-template-columns:repeat(auto-fill,minmax(150px,1fr)); gap:12px; padding:4px;">';
    gameState.loot.forEach((lootItem, index) => {
      if (lootItem.type === 'scroll' || lootItem.type === 'potion') return;
      if (lootItem.isItem) {
        const item = lootItem.item;
        cards += `
          <div style="background:linear-gradient(135deg,rgba(100,50,150,0.2),rgba(50,25,75,0.2));border:2px solid #8a2be2;border-radius:8px;padding:12px;text-align:center;">
            <img src="images/items/${item.image}.png" alt="${item.name}" style="width:100%;height:90px;object-fit:contain;border-radius:6px;background:rgba(0,0,0,0.3);padding:4px;">
            <div style="margin-top:8px;font-weight:bold;color:#ba55d3;font-size:13px;">${item.name}</div>
          </div>`;
      } else {
        const fish = lootItem.fish, rarity = lootItem.rarity, size = lootItem.size;
        const goldValue = getFishGoldValue(rarity, size);
        const bc = rarity === 'Rare' ? '#ffd700' : rarity === 'Uncommon' ? '#66ddff' : '#999';
        cards += `
          <div style="background:linear-gradient(135deg,rgba(50,100,150,0.2),rgba(25,50,75,0.2));border:2px solid ${bc};border-radius:8px;padding:12px;text-align:center;" onmouseover="showLootTooltip(${index},event)" onmouseout="hideLootTooltip()" onmousemove="moveLootTooltip(event)">
            <img src="images/fish/${fish.image}.png" alt="${fish.name}" style="width:100%;height:90px;object-fit:contain;border-radius:6px;background:rgba(0,0,0,0.3);padding:4px;">
            <div style="margin-top:8px;font-weight:bold;color:#66ddff;font-size:13px;">${fish.name}</div>
            <div style="color:${bc};font-size:11px;">${rarity} · ${size}</div>
            <div style="color:#ffd700;font-size:12px;font-weight:bold;">💰 ${goldValue}g</div>
          </div>`;
      }
    });
    cards += '</div>';
    fishHTML = `<div style="margin-bottom:16px;"><div style="font-size:12px;font-weight:bold;color:#888;text-transform:uppercase;letter-spacing:0.6px;margin-bottom:8px;">🐟 Fish &amp; Items</div>${cards}</div>`;
  }

  // Assemble sections
  const sections = [potionsHTML, scrollsHTML, fishHTML].filter(Boolean).join('');
  return `<div style="padding:16px;">${sections || '<div style="text-align:center;color:#888;font-style:italic;">No loot yet.</div>'}</div>`;
}

function _getScrollsLootHTML() {
  const scrolls = (gameState.loot || []).map((l, i) => ({ ...l, _idx: i })).filter(l => l.type === 'scroll');
  if (scrolls.length === 0) {
    return `<div style="text-align:center; padding:40px; color:#888; font-style:italic;">No scrolls yet.</div>`;
  }

  let html = '<div style="display:grid; grid-template-columns:repeat(auto-fill,minmax(150px,1fr)); gap:12px; padding:4px;">';
  scrolls.forEach(item => {
    const data = typeof SCROLLS_DATA !== 'undefined' ? SCROLLS_DATA.find(s => s.name === item.name) : null;
    const displayName = typeof getScrollDisplayName === 'function' ? getScrollDisplayName(item.name) : item.name;
    const imgPath = (data && typeof getScrollImagePath === 'function') ? getScrollImagePath(data) : 'images/scrolls/Unidentified.png';
    const borderColor = typeof _rarityBorder === 'function' ? _rarityBorder(item.rarity) : '#888';
    const rarityColor = typeof _rarityColor === 'function' ? _rarityColor(item.rarity) : '#aaa';
    const canUse = gameState.phase !== 'combat';
    html += `
      <div onclick="useScrollFromLoot(${item._idx})" style="
        background:linear-gradient(135deg,rgba(100,50,150,0.18),rgba(50,25,75,0.18));
        border:2px solid ${borderColor}; border-radius:8px; padding:12px; text-align:center;
        cursor:${canUse ? 'pointer' : 'not-allowed'}; opacity:${canUse ? '1' : '0.55'};"
        ${canUse ? `onmouseenter="this.style.borderColor='#c39be0'" onmouseleave="this.style.borderColor='${borderColor}'"` : ''}>
        <img src="${imgPath}" alt="${displayName}" style="width:100%;height:80px;object-fit:contain;border-radius:6px;background:rgba(0,0,0,0.3);padding:4px;" onerror="this.src='images/scrolls/Unidentified.png'">
        <div style="margin-top:6px;font-weight:bold;color:#c39be0;font-size:12px;">${displayName}</div>
        <div style="color:${rarityColor};font-size:10px;margin-top:2px;">${item.rarity}</div>
        <div style="color:#888;font-size:10px;margin-top:4px;">${canUse ? '📜 Click to use' : '🔒 Outside combat'}</div>
      </div>`;
  });
  html += '</div>';
  return `<div style="margin-bottom:16px;"><div style="font-size:12px;font-weight:bold;color:#888;text-transform:uppercase;letter-spacing:0.6px;margin-bottom:8px;">📜 Scrolls</div>${html}</div>`;
}

function _getPotionsLootHTML() {
  const potions = (gameState.loot || []).map((l, i) => ({ ...l, _idx: i })).filter(l => l.type === 'potion');
  if (potions.length === 0) return '';

  let html = '<div style="display:grid; grid-template-columns:repeat(auto-fill,minmax(150px,1fr)); gap:12px; padding:4px;">';
  potions.forEach(item => {
    const data = typeof POTIONS_DATA !== 'undefined' ? POTIONS_DATA.find(p => p.name === item.name) : null;
    const displayName = typeof getPotionDisplayName === 'function' ? getPotionDisplayName(item.name) : 'Unidentified Potion';
    const imgPath = (data && typeof getPotionImagePath === 'function') ? getPotionImagePath(data) : 'images/potions/Unidentified.png';
    const borderColor = typeof _rarityBorder === 'function' ? _rarityBorder(item.rarity) : '#888';
    const rarityColor = typeof _rarityColor === 'function' ? _rarityColor(item.rarity) : '#aaa';
    const canUse = gameState.phase === 'combat';
    html += `
      <div onclick="${canUse ? `usePotionFromLoot(${item._idx})` : ''}" style="
        background:linear-gradient(135deg,rgba(50,100,150,0.18),rgba(25,50,75,0.18));
        border:2px solid ${borderColor}; border-radius:8px; padding:12px; text-align:center;
        cursor:${canUse ? 'pointer' : 'default'}; opacity:${canUse ? '1' : '0.7'};"
        ${canUse ? `onmouseenter="this.style.borderColor='#6ab4ff'" onmouseleave="this.style.borderColor='${borderColor}'"` : ''}>
        <img src="${imgPath}" alt="${displayName}" style="width:100%;height:80px;object-fit:contain;border-radius:6px;background:rgba(0,0,0,0.3);padding:4px;" onerror="this.src='images/potions/Unidentified.png'">
        <div style="margin-top:6px;font-weight:bold;color:#6ab4ff;font-size:12px;">${displayName}</div>
        <div style="color:${rarityColor};font-size:10px;margin-top:2px;">${item.rarity}</div>
        <div style="color:#888;font-size:10px;margin-top:4px;">${canUse ? '🧪 Click to use' : '🔒 Use in combat'}</div>
      </div>`;
  });
  html += '</div>';
  return `<div style="margin-bottom:16px;"><div style="font-size:12px;font-weight:bold;color:#888;text-transform:uppercase;letter-spacing:0.6px;margin-bottom:8px;">🧪 Potions</div>${html}</div>`;
}

/**
 * Update the loot display (if modal is open)
 */
function updateLootDisplay() {
  const lootDisplay = document.getElementById('loot-display');
  if (lootDisplay) lootDisplay.innerHTML = getLootHTML();
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
window._lootTabBtn = _lootTabBtn;
window._getScrollsLootHTML = _getScrollsLootHTML;
window._getPotionsLootHTML = _getPotionsLootHTML;
