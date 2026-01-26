/**
 * SHOP.JS - Shop System and Item Purchasing
 *
 * Responsibilities:
 * - Displaying shop modal with items for purchase
 * - Handling item purchases and gold transactions
 * - Shop reroll system with escalating costs
 * - Curse of Frugality price modifications
 * - Shop state management (items, reroll count)
 *
 * Key Functions:
 * - showShopModal(purchasedIndices) - Displays shop with 3 random items
 * - leaveShop() - Closes shop and resets shop state
 */

console.log('✅ SHOP.JS v3 loaded - weapon upgrade system active');

// ===== SHOP SYSTEM =====

function showShopModal(purchasedIndices = []) {
  if (items.length === 0) return;

  // Set phase to shop
  gameState.phase = 'shop';
  updateInventory(); // Refresh item UI to update usable item buttons

  // Initialize shop reroll counter if not present
  if (!gameState.shopRerollCount) {
    gameState.shopRerollCount = 0;
  }

  // Initialize shop upgrade counter if not present
  if (gameState.shopUpgradesUsed === undefined) {
    gameState.shopUpgradesUsed = 0;
  }

  // Store shop items in gameState if not already present (first time opening shop)
  if (!gameState.currentShopItems) {
    gameState.currentShopItems = [];
    const maxAttempts = 100; // Prevent infinite loop

    for (let i = 0; i < 3; i++) {
      let attempts = 0;
      let selectedItem = null;

      while (attempts < maxAttempts) {
        // Use luck-based rarity selection
      const targetRarity = selectRandomRarity();

      const rarityItems = items.filter(item => item.rarity && item.rarity.toLowerCase() === targetRarity.toLowerCase() && item.rarity !== 'N/A');
      if (rarityItems.length > 0) {
        const randomIndex = Math.floor(Math.random() * rarityItems.length);
        selectedItem = rarityItems[randomIndex];
      } else {
        // Fallback to any item if no items of target rarity
        const nonNAItems = items.filter(item => item.rarity !== 'N/A');
        const randomIndex = Math.floor(Math.random() * nonNAItems.length);
        selectedItem = nonNAItems[randomIndex];
      }

        // Check if this item is already in shop
        if (!gameState.currentShopItems.find(shopItem => shopItem.name === selectedItem.name)) {
          gameState.currentShopItems.push(selectedItem);
          break;
        }

        attempts++;
      }

      // If we couldn't find a unique item after max attempts, just add it anyway
      // (This should rarely happen unless there are very few items)
      if (attempts >= maxAttempts && selectedItem) {
        gameState.currentShopItems.push(selectedItem);
      }
    }
  }

  const shopItems = gameState.currentShopItems;

  // Check for Curse of Frugality - handle stacking
  const frugalityCurses = getCursesByType('frugality');
  const frugalityModifier = frugalityCurses.reduce((sum, curse) =>
    sum + getPowerValue(curse.power, { Low: 5, Medium: 10, High: 15 }), 0
  );
  const hasFrugality = frugalityCurses.length > 0;

  // Calculate reroll cost: free first time, then 5, 10, 15, etc.
  const rerollCost = gameState.shopRerollCount === 0 ? 0 : gameState.shopRerollCount * 5;
  const canReroll = reroll > 0;

  // Get rarity color helper
  const getRarityColor = (rarity) => {
    switch(rarity) {
      case 'Legendary': return '#ff6b00';
      case 'Rare': return '#9b59b6';
      case 'Uncommon': return '#4CAF50';
      case 'Common': return '#aaa';
      default: return '#888';
    }
  };

  // Build weapon upgrade panel
  let weaponUpgradeHTML = '';
  if (gameState.equippedWeapon) {
    const weapon = gameState.equippedWeapon;
    const currentLevel = gameState.weaponLevel || 1;
    const alreadyUpgraded = gameState.shopUpgradesUsed > 0;

    // Calculate upgrade cost based on current level (scales with level)
    const upgradeCost = currentLevel * 10;

    // Parse weapon description to extract level-specific effects
    const parseWeaponEffect = (description, level) => {
      // Match pattern like (lv1:small/lv2:normal/lv3:large)
      const levelPattern = /\(lv1:([^/]+)\/lv2:([^/]+)\/lv3:([^)]+)\)/;
      const match = description.match(levelPattern);

      if (match) {
        const effectValue = level === 1 ? match[1] : level === 2 ? match[2] : match[3];
        return description.replace(levelPattern, effectValue);
      }
      return description;
    };

    const currentEffect = parseWeaponEffect(weapon.description, currentLevel);
    const nextEffect = parseWeaponEffect(weapon.description, currentLevel + 1);

    const canUpgrade = !alreadyUpgraded && gold >= upgradeCost;
    const rarityColor = getRarityColor(weapon.rarity);

    weaponUpgradeHTML = `
      <div style="
        background: #2d2d2d;
        border-radius: 12px;
        border: 3px solid #ff9800;
        padding: 20px;
        margin-bottom: 20px;
      ">
        <h3 style="color: #ff9800; margin-top: 0; text-align: center; font-size: 18px;">⚔️ Weapon Upgrade</h3>
        <div style="display: flex; gap: 20px; align-items: center;">
          <div style="
            width: 80px;
            height: 80px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: rgba(0,0,0,0.3);
            border-radius: 8px;
            border: 2px solid ${rarityColor};
            flex-shrink: 0;
          ">
            <img src="${weapon.image}" alt="${weapon.name}" style="max-width: 70px; max-height: 70px; object-fit: contain;">
          </div>
          <div style="flex: 1;">
            <div style="font-weight: bold; font-size: 16px; color: white; margin-bottom: 5px;">${weapon.name}</div>
            <div style="color: #ff9800; font-size: 14px; margin-bottom: 10px;">Level ${currentLevel}</div>
            <div style="color: #ccc; font-size: 12px; margin-bottom: 8px;">
              <strong style="color: #4CAF50;">Current:</strong> ${currentEffect}
            </div>
            <div style="color: #ccc; font-size: 12px; margin-bottom: 10px;">
              <strong style="color: #ffb74d;">Next Level:</strong> ${nextEffect}
            </div>
            <button id="weapon-upgrade-btn" style="
              padding: 10px 20px;
              background: ${canUpgrade ? '#ff9800' : '#555'};
              border: none;
              border-radius: 6px;
              color: white;
              cursor: ${canUpgrade ? 'pointer' : 'not-allowed'};
              font-weight: bold;
              font-size: 14px;
              width: 100%;
            " ${!canUpgrade ? 'disabled' : ''}>
              ${alreadyUpgraded ? '✓ Upgraded This Shop' : gold >= upgradeCost ? `⬆️ Upgrade (${upgradeCost}💰)` : `💰 Need ${upgradeCost} Gold`}
            </button>
          </div>
        </div>
      </div>
    `;
  } else {
    weaponUpgradeHTML = `
      <div style="
        background: #2d2d2d;
        border-radius: 12px;
        border: 3px solid #555;
        padding: 20px;
        margin-bottom: 20px;
        text-align: center;
        color: #888;
      ">
        <h3 style="color: #666; margin-top: 0; font-size: 18px;">⚔️ Weapon Upgrade</h3>
        <p style="margin: 10px 0;">No weapon equipped</p>
        <p style="font-size: 12px; margin: 0;">Equip a weapon to upgrade it here!</p>
      </div>
    `;
  }

  // Build loot selling section
  let lootSellHTML = '';
  if (gameState.loot && gameState.loot.length > 0) {
    lootSellHTML = `
      <div style="
        background: #2d2d2d;
        border-radius: 12px;
        border: 3px solid #4488ff;
        padding: 20px;
        margin-bottom: 20px;
      ">
        <h3 style="color: #4488ff; margin-top: 0; text-align: center; font-size: 18px;">🐟 Sell Loot</h3>
        <p style="text-align: center; color: #aaa; font-size: 13px; margin-bottom: 15px;">Click on items to sell them for gold</p>
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 12px;">
    `;

    gameState.loot.forEach((lootItem, index) => {
      if (lootItem.isItem) {
        // Items from fish can't be sold here (they're in regular inventory)
        return;
      }

      const fish = lootItem.fish;
      const rarity = lootItem.rarity;
      const size = lootItem.size;
      const goldValue = getFishGoldValue(rarity, size);

      let rarityColor = '#aaa';
      if (rarity === 'Rare') rarityColor = '#ffd700';
      else if (rarity === 'Uncommon') rarityColor = '#66ddff';

      lootSellHTML += `
        <div class="loot-sell-item" data-index="${index}" style="
          background: rgba(68, 136, 255, 0.1);
          border: 2px solid ${rarityColor};
          border-radius: 8px;
          padding: 10px;
          cursor: pointer;
          transition: all 0.2s;
          text-align: center;
        " onmouseover="this.style.transform='scale(1.05)'; this.style.background='rgba(68, 136, 255, 0.2)';" onmouseout="this.style.transform='scale(1)'; this.style.background='rgba(68, 136, 255, 0.1)';" onclick="sellLootItem(${index})">
          <img src="images/fish/${fish.image}.png" style="width: 80px; height: 80px; object-fit: contain; margin-bottom: 5px;">
          <div style="font-size: 12px; font-weight: bold; color: #66ddff; margin-bottom: 3px;">${fish.name}</div>
          <div style="font-size: 10px; color: ${rarityColor}; margin-bottom: 5px;">${rarity} ${size}</div>
          <div style="font-size: 13px; font-weight: bold; color: #ffd700;">💰 ${goldValue}g</div>
        </div>
      `;
    });

    lootSellHTML += `
        </div>
      </div>
    `;
  }

  // Build items grid
  let itemsHTML = '<div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-top: 20px;">';

  shopItems.forEach((item, index) => {
    const isPurchased = purchasedIndices.includes(index);
    const rarityLower = item.rarity ? item.rarity.toLowerCase() : 'common';
    const basePrice = rarityLower === 'common' ? 10 : rarityLower === 'uncommon' ? 20 : rarityLower === 'rare' ? 30 : 50;
    const price = basePrice + frugalityModifier;
    const rarityColor = getRarityColor(item.rarity);

    // Get item image
    let imageUrl = item.image && item.image.trim() !== '' ? item.image : 'images/items/default.png';

    let priceDisplay = '';
    if (hasFrugality) {
      priceDisplay = `
        <div style="text-align: center; margin-top: 8px;">
          <div style="color: gold; font-weight: bold; font-size: 16px;">
            <span style="text-decoration: line-through; color: #888; margin-right: 8px; font-size: 14px;">${basePrice}</span>
            ${price}💰
          </div>
        </div>
      `;
    } else {
      priceDisplay = `
        <div style="text-align: center; margin-top: 8px;">
          <div style="color: gold; font-weight: bold; font-size: 16px;">${price}💰</div>
        </div>
      `;
    }

    itemsHTML += `
      <div style="
        background: #2d2d2d;
        border-radius: 12px;
        border: 3px solid ${rarityColor};
        padding: 15px;
        display: flex;
        flex-direction: column;
        align-items: center;
        transition: transform 0.2s;
        ${isPurchased ? 'opacity: 0.5;' : ''}
      " class="shop-item-card">
        <div style="
          width: 100px;
          height: 100px;
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 10px;
          background: rgba(0,0,0,0.3);
          border-radius: 8px;
          border: 2px solid ${rarityColor};
        ">
          <img src="${imageUrl}" alt="${item.name}" style="max-width: 90px; max-height: 90px; object-fit: contain;">
        </div>
        <div style="font-weight: bold; font-size: 16px; text-align: center; color: white; margin-bottom: 5px;">${item.name}</div>
        <div style="color: ${rarityColor}; font-size: 13px; text-transform: capitalize; margin-bottom: 8px;">${item.rarity}</div>
        <div style="color: #ccc; font-size: 12px; text-align: center; margin-bottom: 10px; min-height: 60px;">${item.description}</div>
        ${priceDisplay}
        <button class="shop-buy-btn" data-index="${index}" data-price="${price}" style="
          padding: 10px 20px;
          background: ${isPurchased ? '#555' : '#4CAF50'};
          border: none;
          border-radius: 6px;
          color: white;
          cursor: ${isPurchased ? 'not-allowed' : 'pointer'};
          font-weight: bold;
          margin-top: 10px;
          width: 100%;
          transition: all 0.2s;
        " ${gold < price || isPurchased ? 'disabled' : ''}>
          ${isPurchased ? '✓ Purchased' : (gold >= price ? 'Buy' : '💰 Too Expensive')}
        </button>
      </div>
    `;
  });

  itemsHTML += '</div>';

  createGameModal(`
    <div style="max-width: 800px; margin: 0 auto;">
      <h2 style="color: gold; margin-top: 0; text-align: center;">🛍️ Mystical Shop 🛍️</h2>
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; padding: 15px; background: #2d2d2d; border-radius: 8px;">
        <div style="color: gold; font-weight: bold; font-size: 18px;">💰 Your Gold: ${gold}</div>
        <div style="color: #4CAF50; font-weight: bold; font-size: 18px;">🔄 Rerolls: ${reroll}</div>
      </div>
      ${weaponUpgradeHTML}
      ${lootSellHTML}
      ${itemsHTML}
      <div style="display: flex; gap: 10px; margin-top: 20px;">
        <button id="shop-reroll-btn" style="
          flex: 1;
          padding: 12px;
          background: ${canReroll && gold >= rerollCost ? '#ff9800' : '#555'};
          border: none;
          border-radius: 6px;
          color: white;
          cursor: ${canReroll && gold >= rerollCost ? 'pointer' : 'not-allowed'};
          font-weight: bold;
          font-size: 14px;
        " ${!canReroll || gold < rerollCost ? 'disabled' : ''}>
          🔄 Reroll Shop ${rerollCost === 0 ? '(FREE!)' : `(${rerollCost}💰 + 1 Reroll)`}
        </button>
        <button onclick="leaveShop()" style="
          flex: 1;
          padding: 12px;
          background: #666;
          border: none;
          border-radius: 6px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 14px;
        ">Leave Shop</button>
      </div>
    </div>
  `);

  document.querySelectorAll('.shop-buy-btn').forEach(btn => {
    btn.onclick = (e) => {
      const itemIndex = parseInt(e.target.dataset.index);
      const price = parseInt(e.target.dataset.price);
      const item = shopItems[itemIndex];

      if (gold >= price) {
        gold -= price;
        gameState.gold = gold;
        acquireItem(item);

        // Track purchased items
        purchasedIndices.push(itemIndex);

        // Check for Curse of Frugality and remove only ONE after first purchase
        let curseWasRemoved = false;
        const frugalityCurses = getCursesByType('frugality');
        if (frugalityCurses.length > 0) {
          // Remove only the first frugality curse
          const curseIndex = gameState.activeCurses.indexOf(frugalityCurses[0]);
          if (curseIndex !== -1) {
            gameState.activeCurses.splice(curseIndex, 1);
            curseWasRemoved = true;
            updateCurseUI();
          }
        }

        saveCurrentGame();

        // If curse was removed, refresh the shop to show normal prices
        if (curseWasRemoved) {
          setTimeout(() => {
            showShopModal(purchasedIndices);
          }, 100);
        } else {
          // Otherwise just update button state
          e.target.textContent = '✓ Purchased';
          e.target.disabled = true;
          e.target.style.background = '#555';
          e.target.parentElement.style.opacity = '0.5';
        }
      }
    };
  });

  // Add weapon upgrade button handler
  const weaponUpgradeBtn = document.getElementById('weapon-upgrade-btn');
  if (weaponUpgradeBtn && gameState.equippedWeapon) {
    weaponUpgradeBtn.onclick = () => {
      const currentLevel = gameState.weaponLevel || 1;
      const upgradeCost = currentLevel * 10;
      const canUpgrade = gameState.shopUpgradesUsed === 0 && gold >= upgradeCost;

      if (canUpgrade) {
        // Deduct gold
        gold -= upgradeCost;
        gameState.gold = gold;

        // Increase weapon level (both in gameState and on weapon object)
        gameState.weaponLevel = currentLevel + 1;
        gameState.equippedWeapon.level = gameState.weaponLevel; // Keep weapon.level in sync

        // Track that we've used an upgrade this shop
        gameState.shopUpgradesUsed++;

        // Save and refresh shop to show updated weapon
        saveCurrentGame();
        updateEquipmentSlots(); // Update the equipment slot display
        showShopModal(purchasedIndices);

        // Show notification
        createNotification(`Upgraded ${gameState.equippedWeapon.name} to Level ${gameState.weaponLevel}!`, '#ff9800', '⬆️');
      }
    };
  }

  // Add reroll button handler
  const rerollBtn = document.getElementById('shop-reroll-btn');
  if (rerollBtn) {
    rerollBtn.onclick = () => {
      if (reroll > 0 && gold >= rerollCost) {
        // Deduct reroll and gold
        reroll -= 1;
        gold -= rerollCost;
        gameState.reroll = reroll;
        gameState.gold = gold;

        // Increment reroll counter for next reroll
        gameState.shopRerollCount++;

        // Clear current shop items to force regeneration
        gameState.currentShopItems = null;

        // Refresh shop (don't carry over purchased indices)
        saveCurrentGame();
        showShopModal([]);
      }
    };
  }
}

// Function to leave shop and reset reroll counter
function leaveShop() {
  // Reset shop state
  gameState.currentShopItems = null;
  gameState.shopRerollCount = 0;
  gameState.shopUpgradesUsed = 0; // Reset weapon upgrade counter
  gameState.phase = 'selection';

  // Save and close
  saveCurrentGame();
  closeGameModal();

  // Update inventory to refresh usable item buttons
  if (typeof updateInventory === 'function') {
    updateInventory();
  }
}

// Clear shop items when closing shop modal
const originalCloseGameModal = window.closeGameModal;
window.closeGameModal = function() {
  if (gameState.phase === 'shop') {
    delete gameState.currentShopItems;
    gameState.shopRerollCount = 0; // Reset reroll count for next shop
    gameState.shopUpgradesUsed = 0; // Reset weapon upgrade counter for next shop
    gameState.phase = null;
  }
  if (typeof originalCloseGameModal === 'function') {
    originalCloseGameModal();
  }
};

/**
 * Sell a loot item for gold
 * @param {number} index - Index in the loot array
 */
function sellLootItem(index) {
  if (!gameState.loot || !gameState.loot[index]) return;

  const lootItem = gameState.loot[index];
  if (lootItem.isItem) return; // Can't sell items here

  const rarity = lootItem.rarity;
  const size = lootItem.size;
  const goldValue = getFishGoldValue(rarity, size);

  // Add gold
  gold += goldValue;
  gameState.gold = gold;

  // Remove from loot
  if (typeof removeFromLoot === 'function') {
    removeFromLoot(index);
  } else {
    gameState.loot.splice(index, 1);
  }

  // Show notification
  if (typeof createNotification === 'function') {
    createNotification(`Sold for ${goldValue} gold!`, '#ffd700', '💰');
  }

  // Save game
  saveCurrentGame();

  // Refresh shop to update gold and loot display
  // Find currently purchased items by checking if buttons are disabled
  const purchasedIndices = [];
  document.querySelectorAll('.shop-buy-btn').forEach((btn, idx) => {
    if (btn.disabled && btn.textContent === '✓ Purchased') {
      purchasedIndices.push(idx);
    }
  });

  showShopModal(purchasedIndices);
}

// Export shop functions
window.showShopModal = showShopModal;
window.leaveShop = leaveShop;
window.sellLootItem = sellLootItem;
