// ===== UI.JS - All DOM Manipulation and Display Updates =====
//
// This module handles all visual updates to the UI including:
// - Top bar (health, gold, rations)
// - Inventory display

console.log('✅ UI.JS v34 loaded - weapon deep copy fix active + comprehensive debugging');

// Check for equipment slots on DOM ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    const weaponSlot = document.getElementById('weapon-slot');
    const amuletSlot = document.getElementById('amulet-slot');
    console.log('🎯 DOM Ready - Equipment slots check:', {
      weaponSlot: !!weaponSlot,
      amuletSlot: !!amuletSlot
    });
  });
} else {
  const weaponSlot = document.getElementById('weapon-slot');
  const amuletSlot = document.getElementById('amulet-slot');
  console.log('🎯 Immediate - Equipment slots check:', {
    weaponSlot: !!weaponSlot,
    amuletSlot: !!amuletSlot
  });
}
// - Game lists and selections
// - Encounter history
// - Game state stats sidebar

// ===== TOP BAR UPDATES =====

function updateTopBar() {
  // Update floating HUD (now at bottom of screen)
  const gameHealth = document.getElementById('game-health');
  const gameGold = document.getElementById('game-gold');
  const gameLevel = document.getElementById('game-level');
  const gameAlliesCount = document.getElementById('game-allies-count');

  if (gameHealth) {
    gameHealth.textContent = `${health}/${maxHealth}`;
  }

  if (gameGold) {
    gameGold.textContent = gold;
  }

  if (gameLevel && typeof gameState !== 'undefined') {
    gameLevel.textContent = gameState.playerLevel || 1;
  }

  if (gameAlliesCount && typeof gameState !== 'undefined') {
    gameAlliesCount.textContent = (gameState.activeAllies || []).length;
  }

  // Update stats panel health/gold if they exist
  const statsHealth = document.getElementById('stats-health');
  const statsGold = document.getElementById('stats-gold');

  if (statsHealth) {
    statsHealth.textContent = `${health}/${maxHealth}`;
  }

  if (statsGold) {
    statsGold.textContent = gold;
  }
}

function updateHealthDisplay() {
  // Legacy function - now handled by updateTopBar
  updateTopBar();
}

function updateGoldDisplay() {
  // Legacy function - now handled by updateTopBar
  updateTopBar();
}

// ===== LOCATION DISPLAY =====

function updateLocationDisplay(gameName, gameDescription) {
  const locationName = document.getElementById('location-name');
  const locationType = document.getElementById('location-type');
  const locationGame = document.getElementById('location-game');
  const locationEffect = document.getElementById('location-effect');
  const tierLabel = document.getElementById('tier-label');
  const currentDifficulty = document.getElementById('current-difficulty');
  const locationSection = document.getElementById('location-display-section');

  if (!locationName || !tierLabel) return;

  // Get the current location from gameState
  const location = gameState?.location;

  if (location) {
    // Update location name (the actual location name, not the game name)
    locationName.textContent = location.name || 'Current Location';

    // Update location type with color coding
    if (locationType) {
      const type = location.type || 'Unknown';
      // Color code based on type
      const typeColors = {
        'Undead': '#9b59b6',
        'Firey': '#e74c3c',
        'Watery': '#3498db',
        'Building': '#95a5a6',
        'Chaos': '#e67e22',
        'General': '#2ecc71'
      };
      const color = typeColors[type] || '#aaa';
      locationType.textContent = type;
      locationType.style.color = color;
    }

    // Update the source game
    if (locationGame) {
      locationGame.textContent = location.game;
    }

    // Update the location effect
    if (locationEffect) {
      locationEffect.textContent = location.effect || 'No effect';
    }

    // Store description for tooltip
    if (locationSection) {
      locationSection.dataset.description = location.effect || 'No effect';
    }
  } else {
    // Fallback to game name if no location is set
    locationName.textContent = gameName || 'Current Location';
    if (locationType) {
      locationType.textContent = 'Unknown';
      locationType.style.color = '#aaa';
    }
    if (locationGame) {
      locationGame.textContent = 'No location selected';
    }
    if (locationEffect) {
      locationEffect.textContent = 'No effect';
    }
    if (locationSection) {
      locationSection.dataset.description = gameDescription || 'No description available';
    }
  }

  // Calculate difficulty tier
  const difficulty = gameState.totalGamesBeaten || 0;
  let tier = 'easy';
  let tierText = 'Easy';
  let rangeText = '0-4';

  if (difficulty >= 10) {
    tier = 'hard';
    tierText = 'Hard';
    rangeText = '10+';
  } else if (difficulty >= 5) {
    tier = 'medium';
    tierText = 'Medium';
    rangeText = '5-9';
  }

  // Update tier display with range inside
  tierLabel.innerHTML = `${tierText}<br><span class="tier-range">${rangeText}</span>`;
  tierLabel.className = `tier-label ${tier}`;

  // Update current difficulty
  if (currentDifficulty) {
    currentDifficulty.textContent = `Current Difficulty: ${difficulty}`;
  }
}

// Location tooltip
let locationTooltip;

function initLocationTooltip() {
  locationTooltip = document.getElementById('location-hover-tooltip');
  const locationSection = document.getElementById('location-display-section');

  if (!locationTooltip || !locationSection) return;

  locationSection.addEventListener('mouseenter', (e) => {
    showLocationTooltip(e);
  });

  locationSection.addEventListener('mousemove', (e) => {
    if (locationTooltip && locationTooltip.classList.contains('visible')) {
      positionLocationTooltip(e);
    }
  });

  locationSection.addEventListener('mouseleave', () => {
    hideLocationTooltip();
  });
}

function showLocationTooltip(e) {
  const locationType = document.getElementById('location-type');
  const locationGame = document.getElementById('location-game');
  const locationEffect = document.getElementById('location-effect');

  if (!locationTooltip || !locationType || !locationGame || !locationEffect) return;

  const typeColors = {
    'Undead': '#9b59b6',
    'Firey': '#e74c3c',
    'Watery': '#3498db',
    'Building': '#95a5a6',
    'Chaos': '#e67e22',
    'General': '#2ecc71'
  };

  const typeText = locationType.textContent;
  const typeColor = typeColors[typeText] || '#aaa';

  locationTooltip.innerHTML = `
    <div class="location-tooltip-row">
      <div class="location-tooltip-label">Type:</div>
      <div class="location-tooltip-value" style="color: ${typeColor};">${typeText}</div>
    </div>
    <div class="location-tooltip-row">
      <div class="location-tooltip-label">From:</div>
      <div class="location-tooltip-value" style="font-style: italic;">${locationGame.textContent}</div>
    </div>
    <div class="location-tooltip-row">
      <div class="location-tooltip-label">Effect:</div>
      <div class="location-tooltip-value">${locationEffect.textContent}</div>
    </div>
  `;

  positionLocationTooltip(e);
  locationTooltip.classList.add('visible');
}

function positionLocationTooltip(e) {
  if (!locationTooltip) return;

  const tooltipRect = locationTooltip.getBoundingClientRect();
  let x = e.clientX + 15;
  let y = e.clientY + 15;

  // Keep tooltip on screen
  if (x + tooltipRect.width > window.innerWidth) {
    x = e.clientX - tooltipRect.width - 15;
  }
  if (y + tooltipRect.height > window.innerHeight) {
    y = e.clientY - tooltipRect.height - 15;
  }

  locationTooltip.style.left = x + 'px';
  locationTooltip.style.top = y + 'px';
}

function hideLocationTooltip() {
  if (locationTooltip) {
    locationTooltip.classList.remove('visible');
  }
}

// Initialize location display tooltip
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    initLocationTooltip();
  });
} else {
  initLocationTooltip();
}

// ===== INVENTORY DISPLAY =====

// Global inventory sort mode (default: 'type')
window.inventorySortMode = window.inventorySortMode || 'type';

/**
 * Update the compact items display at the top of the left sidebar (#game-stats).
 * Shows all items as small icons; usable items have a "Use" button.
 * Incremental items show their current progress counter.
 */
function updateSidebarItems() {
  const section = document.getElementById('sidebar-items-section');
  const grid = document.getElementById('sidebar-items-grid');
  if (!section || !grid) return;

  const items = typeof inventory !== 'undefined' ? inventory : [];
  if (items.length === 0) {
    section.style.display = 'none';
    return;
  }
  section.style.display = 'block';

  const getRarityColor = (rarity) => {
    switch ((rarity || '').toLowerCase()) {
      case 'legendary': return '#ff6b00';
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      case 'common': return '#aaa';
      default: return '#888';
    }
  };

  // Get incremental counter for a given item name
  function getIncrementalBadge(item) {
    const cs = window.CombatEngine ? window.CombatEngine.getCombatState() : null;
    const inc = cs && cs.incrementals;
    let cur = null, max = null;
    switch (item.name) {
      case 'Pen Nib':        cur = inc ? inc.attacksTotal % 10 : (typeof gameState !== 'undefined' ? (gameState.runAttacks || 0) % 10 : 0); max = 10; break;
      case 'Nunchaku':       cur = inc ? inc.attacksTotal % 10 : (typeof gameState !== 'undefined' ? (gameState.runAttacks || 0) % 10 : 0); max = 10; break;
      case 'Happy Flower':   cur = cs ? (cs.turn - 1) % 3 : 0; max = 3; break;
      case 'Ornamental Fan': cur = inc ? inc.attacksThisTurn % 4 : 0; max = 4; break;
      case 'Shuriken':       cur = inc ? inc.attacksThisTurn % 3 : 0; max = 3; break;
    }
    if (cur === null) return '';
    return `<div style="position:absolute;bottom:1px;left:1px;background:rgba(0,0,0,0.9);color:#ffcc44;padding:1px 3px;border-radius:3px;font-size:8px;font-weight:bold;border:1px solid #ffcc44;">${cur}/${max}</div>`;
  }

  grid.innerHTML = items.map((item, idx) => {
    const color = getRarityColor(item.rarity);
    let imgSrc = item.image && item.image.trim() ? item.image : '';
    if (imgSrc && imgSrc.includes('imgur.com/') && !imgSrc.includes('i.imgur.com')) {
      imgSrc = imgSrc.replace('imgur.com/', 'i.imgur.com/');
      if (!imgSrc.match(/\.(png|jpg|jpeg|gif)$/i)) imgSrc += '.png';
    }

    const isUsable = item.type === 'Usable' || item.type === 'Active';
    const isIncremental = (item.type || '').toLowerCase() === 'incremental';
    const canUse = isUsable && typeof canUseItem === 'function' && canUseItem(item);
    const incBadge = isIncremental ? getIncrementalBadge(item) : '';

    const quantityBadge = item.quantity && item.quantity > 1
      ? `<div style="position:absolute;top:1px;right:1px;background:rgba(0,0,0,0.9);color:white;padding:1px 3px;border-radius:3px;font-size:8px;font-weight:bold;border:1px solid #ffaa00;">${item.quantity}</div>`
      : '';

    const useBtn = isUsable
      ? `<button onclick="event.stopPropagation(); if(typeof useItem==='function') useItem(${idx});" title="${canUse ? 'Use' : 'Cannot use now'}" style="position:absolute;bottom:0;left:0;right:0;font-size:8px;padding:1px;background:${canUse ? '#4CAF50' : '#555'};color:${canUse ? 'white' : '#888'};border:none;border-radius:0 0 4px 4px;cursor:${canUse ? 'pointer' : 'not-allowed'};font-weight:bold;${canUse ? '' : 'opacity:0.6;'}">${canUse ? 'USE' : '—'}</button>`
      : '';

    return `<div title="${item.name}: ${item.description}" style="position:relative;width:40px;height:40px;border:2px solid ${color};border-radius:6px;background:rgba(0,0,0,0.5);overflow:visible;flex-shrink:0;">
      ${imgSrc
        ? `<img src="${imgSrc}" alt="${item.name}" style="width:100%;height:100%;object-fit:contain;border-radius:4px;" onerror="this.style.display='none'">`
        : `<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;font-size:18px;">🎒</div>`}
      ${quantityBadge}${incBadge}${useBtn}
    </div>`;
  }).join('');
}
window.updateSidebarItems = updateSidebarItems;

function updateInventory() {
  const inventoryDiv = document.getElementById('inventory');
  const removeItemSelect = document.getElementById('removeItemSelect');

  if (inventoryDiv) {
    inventoryDiv.innerHTML = '';
  }
  if (removeItemSelect) {
    removeItemSelect.innerHTML = '<option value="">-- Select an Item --</option>';
  }

  inventory.forEach((item, index) => {
    // Get display name (with stat modifiers for passive items)
    const displayName = (item.type === 'Passive' && typeof getPassiveDisplayName === 'function')
      ? getPassiveDisplayName(item)
      : (item.displayName || item.name);

    if (inventoryDiv) {
      const itemDiv = document.createElement('div');
      itemDiv.className = 'inventory-item';
      itemDiv.innerHTML = `
        <strong>${displayName}</strong> (${item.rarity})
        <span class="remove-item" onclick="removeItem(${index})">×</span>
        <p>${item.description}</p>
        <p><em>Type: ${item.type}</em></p>
      `;
      inventoryDiv.appendChild(itemDiv);
    }

    if (removeItemSelect) {
      const option = document.createElement('option');
      option.value = index;
      option.textContent = `${displayName} (${item.rarity})`;
      removeItemSelect.appendChild(option);
    }
  });

  if (removeItemSelect) removeItemSelect.disabled = inventory.length === 0;
  const removeSelectedItem = document.getElementById('removeSelectedItem');
  const removeRandomItem = document.getElementById('removeRandomItem');
  if (removeSelectedItem) removeSelectedItem.disabled = inventory.length === 0;
  if (removeRandomItem) removeRandomItem.disabled = inventory.length === 0;

  // Update game items sidebar if it exists
  const gameItemsList = document.getElementById('game-items-list');
  if (gameItemsList) {
    console.log('Updating game-items-list, inventory length:', inventory.length, 'sort mode:', window.inventorySortMode);
    if (inventory.length === 0) {
      gameItemsList.innerHTML = '<div class="empty-inventory">No items yet</div>';
    } else {
      // Sort inventory based on current mode
      // Keep all items including weapon duplicates
      const sortedInventory = [...inventory]
        .map((item, idx) => ({ item, idx }))
        .sort((a, b) => {
          if (window.inventorySortMode === 'alphabetical') {
            return a.item.name.localeCompare(b.item.name);
          } else if (window.inventorySortMode === 'rarity') {
            const rarityOrder = { 'common': 0, 'uncommon': 1, 'rare': 2, 'epic': 3, 'legendary': 4 };
            const aRarity = rarityOrder[a.item.rarity?.toLowerCase()] ?? 0;
            const bRarity = rarityOrder[b.item.rarity?.toLowerCase()] ?? 0;
            return bRarity - aRarity; // Higher rarity first
          } else {
            // Default: type sort (weapons first, then usable, then passive)
            const typeOrder = { 'Weapon': 0, 'Usable': 1, 'Passive': 2 };
            const aOrder = typeOrder[a.item.type] ?? 3;
            const bOrder = typeOrder[b.item.type] ?? 3;
            return aOrder - bOrder;
          }
        });

      console.log('Sorted inventory order:', sortedInventory.map(x => x.item.name).join(', '));
      console.log('📦 First 3 items with full data:', sortedInventory.slice(0, 3).map(x => ({
        name: x.item.name,
        type: x.item.type,
        rarity: x.item.rarity,
        image: x.item.image
      })));

      gameItemsList.innerHTML = sortedInventory.map(({ item, idx }) => {
        let imageUrl = item.image && item.image.trim() !== ''
          ? item.image
          : 'https://via.placeholder.com/70?text=%3F';

        // Fix imgur URLs
        if (imageUrl.includes('imgur.com/') && !imageUrl.includes('i.imgur.com')) {
          imageUrl = imageUrl.replace('imgur.com/', 'i.imgur.com/');
          if (!imageUrl.match(/\.(png|jpg|jpeg|gif)$/i)) {
            imageUrl += '.png';
          }
        }

        // Get rarity color for border
        const getRarityColor = (rarity) => {
          switch(rarity?.toLowerCase()) {
            case 'legendary': return '#ff6b00';
            case 'rare': return '#9b59b6';
            case 'uncommon': return '#4CAF50';
            case 'common': return '#aaa';
            default: return '#888';
          }
        };

        const rarityColor = getRarityColor(item.rarity);

        const isUsable = item.type === 'Usable' || item.type === 'Active';
        const canUse = isUsable && typeof canUseItem === 'function' && canUseItem(item);
        const isWeapon = item.type === 'Weapon';

        return `
          <div class="item-display-container" data-item-index="${idx}" style="
            position: relative;
            display: inline-block;
            transition: transform 0.2s ease;
          ">
            <div class="item-display-image" style="
              cursor: pointer;
              position: relative;
            ">
              <img src="${imageUrl}"
                   alt="${item.name}"
                   loading="lazy"
                   style="width: 70px; height: 70px; object-fit: contain; border-radius: 6px; display: block; background: #1a1a1a; padding: 2px; border: 3px solid ${rarityColor};"
                   onerror="if(this.src!=='https://via.placeholder.com/70?text=%3F'){this.src='https://via.placeholder.com/70?text=%3F';this.classList.add('image-error');}">
              ${item.quantity && item.quantity > 1 ? `
                <div class="item-quantity-badge" style="
                  position: absolute;
                  top: 2px;
                  right: 2px;
                  background: rgba(0, 0, 0, 0.85);
                  color: white;
                  padding: 2px 5px;
                  border-radius: 3px;
                  font-size: 11px;
                  font-weight: bold;
                  border: 1px solid #ffaa00;
                  z-index: 15;
                ">x${item.quantity}</div>
              ` : ''}
              ${isWeapon && item.level && item.level > 1 ? `
                <div class="item-level-badge" style="
                  position: absolute;
                  top: 2px;
                  right: 2px;
                  background: #ffaa44;
                  color: #000;
                  padding: 2px 5px;
                  border-radius: 4px;
                  font-size: 11px;
                  font-weight: bold;
                  z-index: 15;
                  line-height: 1;
                ">Lv${item.level}</div>
              ` : ''}
              ${isUsable ? `
                <button class="item-use-button"
                        data-item-index="${idx}"
                        style="
                          position: absolute;
                          bottom: 2px;
                          left: 2px;
                          right: 2px;
                          padding: 2px 4px;
                          font-size: 10px;
                          background: ${canUse ? '#4CAF50' : '#555'};
                          color: ${canUse ? 'white' : '#888'};
                          border: 1px solid ${canUse ? '#2E7D32' : '#333'};
                          border-radius: 3px;
                          cursor: ${canUse ? 'pointer' : 'not-allowed'};
                          font-weight: bold;
                          text-transform: uppercase;
                          z-index: 10;
                        "
                        ${!canUse ? 'disabled' : ''}>
                  Use${item.uses && item.uses > 1 ? ` x${item.uses}` : ''}
                </button>
              ` : ''}
              ${isWeapon ? (() => {
                const isDuplicate = gameState.equippedWeapon && item.name === gameState.equippedWeapon.name;
                const canUpgrade = isDuplicate && (gameState.weaponLevel || 1) < 3;

                if (canUpgrade) {
                  return `
                    <div style="position: absolute; bottom: 2px; left: 2px; right: 2px; display: flex; gap: 1px; z-index: 10;">
                      <button class="item-equip-button"
                              data-item-index="${idx}"
                              style="
                                flex: 1;
                                padding: 1px 2px;
                                font-size: 8px;
                                background: #ff9800;
                                color: white;
                                border: 1px solid #f57c00;
                                border-radius: 2px;
                                cursor: pointer;
                                font-weight: bold;
                                text-transform: uppercase;
                              ">
                        Equip
                      </button>
                      <button class="item-upgrade-button"
                              data-item-index="${idx}"
                              style="
                                flex: 1;
                                padding: 1px 2px;
                                font-size: 8px;
                                background: #4CAF50;
                                color: white;
                                border: 1px solid #2E7D32;
                                border-radius: 2px;
                                cursor: pointer;
                                font-weight: bold;
                                text-transform: uppercase;
                              ">
                        Upgrade
                      </button>
                    </div>
                  `;
                } else {
                  return `
                    <button class="item-equip-button"
                            data-item-index="${idx}"
                            style="
                              position: absolute;
                              bottom: 2px;
                              left: 2px;
                              right: 2px;
                              padding: 1px 2px;
                              font-size: 8px;
                              background: #ff9800;
                              color: white;
                              border: 1px solid #f57c00;
                              border-radius: 2px;
                              cursor: pointer;
                              font-weight: bold;
                              text-transform: uppercase;
                              z-index: 10;
                            ">
                      Equip
                    </button>
                  `;
                }
              })() : ''}
            </div>
          </div>
        `;
      }).join('');

      // Add tooltip and hover effect event listeners after rendering
      const itemContainers = gameItemsList.querySelectorAll('.item-display-container');
      itemContainers.forEach((container) => {
        const itemIdx = parseInt(container.dataset.itemIndex);
        const div = container.querySelector('.item-display-image');

        // Add hover scale effect
        container.onmouseenter = e => {
          container.style.transform = 'scale(1.1)';
          container.style.zIndex = '100';
          showItemTooltip(e, inventory[itemIdx]);
        };

        container.onmousemove = e => {
          moveItemTooltip(e);
        };

        container.onmouseleave = e => {
          container.style.transform = '';
          container.style.zIndex = '';
          hideItemTooltip();
        };
      });

      // Add use button event listeners
      const useButtons = gameItemsList.querySelectorAll('.item-use-button');
      useButtons.forEach((button) => {
        button.onclick = (e) => {
          e.stopPropagation(); // Prevent triggering tooltip
          const itemIndex = parseInt(button.dataset.itemIndex);
          if (typeof useItem === 'function') {
            useItem(itemIndex);
          }
        };
      });

      // Add equip button event listeners
      const equipButtons = gameItemsList.querySelectorAll('.item-equip-button');
      equipButtons.forEach((button) => {
        button.onclick = (e) => {
          e.stopPropagation(); // Prevent triggering tooltip
          const itemIndex = parseInt(button.dataset.itemIndex);
          equipWeapon(itemIndex);
        };
      });

      // Add upgrade button event listeners
      const upgradeButtons = gameItemsList.querySelectorAll('.item-upgrade-button');
      upgradeButtons.forEach((button) => {
        button.onclick = (e) => {
          e.stopPropagation(); // Prevent triggering tooltip
          const itemIndex = parseInt(button.dataset.itemIndex);
          upgradeWeapon(itemIndex);
        };
      });
    }
  }

  // Update stats panel and equipment slots
  updateGameStats();
  updateEquipmentSlots();
  updateSidebarItems();
}

// ===== WEAPON EQUIP/UNEQUIP FUNCTIONS =====

function equipWeapon(itemIndex) {
  console.log('🔫 equipWeapon called with index:', itemIndex, 'inventory length:', inventory.length);

  if (itemIndex < 0 || itemIndex >= inventory.length) {
    console.error('Invalid item index:', itemIndex);
    return;
  }

  const weapon = inventory[itemIndex];
  console.log('🔫 Weapon from inventory:', weapon);

  if (weapon.type !== 'Weapon') {
    console.error('Item is not a weapon:', weapon);
    return;
  }

  // If there's already an equipped weapon, add it back to inventory
  if (gameState.equippedWeapon) {
    const previousWeapon = {
      name: gameState.equippedWeapon.name,
      type: gameState.equippedWeapon.type,
      rarity: gameState.equippedWeapon.rarity,
      description: gameState.equippedWeapon.description,
      image: gameState.equippedWeapon.image,
      reference: gameState.equippedWeapon.reference,
      tags: gameState.equippedWeapon.tags,
      quantity: 1,
      level: gameState.weaponLevel || 1 // Store current weapon level
    };
    // Preserve accumulated bonuses if they exist
    if (gameState.equippedWeapon.bonuses) {
      previousWeapon.bonuses = {...gameState.equippedWeapon.bonuses};
    }
    inventory.push(previousWeapon);
    console.log('🔫 Previous weapon returned to inventory with level:', previousWeapon.name, previousWeapon.level, 'bonuses:', previousWeapon.bonuses);
  }

  // Create a proper copy of the weapon to avoid reference issues
  gameState.equippedWeapon = {
    name: weapon.name,
    type: weapon.type,
    rarity: weapon.rarity,
    description: weapon.description,
    image: weapon.image,
    reference: weapon.reference,
    tags: weapon.tags,
    quantity: 1
  };
  // Restore accumulated bonuses if they exist
  if (weapon.bonuses) {
    gameState.equippedWeapon.bonuses = {...weapon.bonuses};
  }
  gameState.weaponLevel = weapon.level || 1; // Restore weapon level or default to 1

  // Remove weapon from inventory (since it's now equipped)
  inventory.splice(itemIndex, 1);

  console.log('🔫 Weapon equipped to gameState:', gameState.equippedWeapon);
  console.log('🔫 Weapon level set to:', gameState.weaponLevel);
  console.log('🔫 Weapon removed from inventory at index:', itemIndex);

  // Update UI
  updateInventory();
  updateEquipmentSlots();

  if (typeof createNotification === 'function') {
    const levelText = gameState.weaponLevel > 1 ? ` (Lv${gameState.weaponLevel})` : '';
    createNotification(`Equipped ${weapon.name}${levelText}`, '#ff9800', '⚔️');
  }

  console.log('✅ Weapon equipped successfully:', weapon.name, 'Level:', gameState.weaponLevel);
}

function upgradeWeapon(itemIndex) {
  console.log('⬆️ upgradeWeapon called with index:', itemIndex);

  if (itemIndex < 0 || itemIndex >= inventory.length) {
    console.error('Invalid item index:', itemIndex);
    return;
  }

  if (!gameState.equippedWeapon) {
    console.error('No weapon equipped');
    return;
  }

  const weapon = inventory[itemIndex];
  console.log('⬆️ Weapon from inventory:', weapon);

  if (weapon.type !== 'Weapon') {
    console.error('Item is not a weapon:', weapon);
    return;
  }

  if (weapon.name !== gameState.equippedWeapon.name) {
    console.error('Weapon does not match equipped weapon');
    return;
  }

  const currentLevel = gameState.weaponLevel || 1;

  if (currentLevel >= 3) {
    if (typeof createNotification === 'function') {
      createNotification('Weapon is already max level!', '#ff6b6b', '⚠️');
    }
    return;
  }

  // Level up the weapon (both in gameState and on weapon object)
  gameState.weaponLevel = currentLevel + 1;
  gameState.equippedWeapon.level = gameState.weaponLevel; // Keep weapon.level in sync

  // Remove the duplicate weapon from inventory
  inventory.splice(itemIndex, 1);

  // Update UI
  updateInventory();
  updateEquipmentSlots();

  if (typeof createNotification === 'function') {
    createNotification(`${weapon.name} upgraded to Level ${gameState.weaponLevel}!`, '#4CAF50', '⬆️');
  }

  console.log('✅ Weapon upgraded to level:', gameState.weaponLevel);
}

function unequipWeapon() {
  if (!gameState.equippedWeapon) {
    return;
  }

  // Add weapon back to inventory with its current level
  const weaponToReturn = {
    name: gameState.equippedWeapon.name,
    type: gameState.equippedWeapon.type,
    rarity: gameState.equippedWeapon.rarity,
    description: gameState.equippedWeapon.description,
    image: gameState.equippedWeapon.image,
    reference: gameState.equippedWeapon.reference,
    tags: gameState.equippedWeapon.tags,
    quantity: 1,
    level: gameState.weaponLevel || 1 // Store current weapon level
  };
  // Preserve accumulated bonuses if they exist
  if (gameState.equippedWeapon.bonuses) {
    weaponToReturn.bonuses = {...gameState.equippedWeapon.bonuses};
  }
  inventory.push(weaponToReturn);

  const weaponName = gameState.equippedWeapon.name;
  const weaponLevel = gameState.weaponLevel || 1;

  gameState.equippedWeapon = null;
  gameState.weaponLevel = 1;

  // Update UI
  updateInventory();
  updateEquipmentSlots();

  if (typeof createNotification === 'function') {
    const levelText = weaponLevel > 1 ? ` (Lv${weaponLevel})` : '';
    createNotification(`Unequipped ${weaponName}${levelText}`, '#888', '⚔️');
  }

  console.log('Unequipped weapon:', weaponName, 'Level:', weaponLevel);
  console.log('Weapon returned to inventory with level:', weaponLevel);
}

// ===== CURSES DISPLAY =====

function getCurseRemainingText(curse) {
  const curseName = curse.name.toLowerCase();

  // Curse of Weakness - shows "Next roll"
  if (curseName.includes('weakness')) {
    return 'Next roll';
  }

  // Curse of Failure - shows "On natural 1"
  if (curseName.includes('failure')) {
    return 'On natural 1';
  }

  // Curse of Vulnerability - shows remaining curse duplications
  if (curseName.includes('vulnerability')) {
    if (!gameState.vulnerabilityUses) gameState.vulnerabilityUses = {};
    const used = gameState.vulnerabilityUses[curse.name] || 0;
    const maxUses = typeof getCurseMaxUses === 'function' ? getCurseMaxUses(curse.power) : (curse.power === 'High' ? 3 : curse.power === 'Medium' ? 2 : 1);
    const remaining = maxUses - used;
    return `${remaining}/${maxUses} Curses Obtained left`;
  }

  // Curse of Shroud - shows remaining game selections
  if (curseName.includes('shroud')) {
    if (!gameState.shroudUses) gameState.shroudUses = {};
    const used = gameState.shroudUses[curse.name] || 0;
    const maxUses = typeof getCurseMaxUses === 'function' ? getCurseMaxUses(curse.power) : (curse.power === 'High' ? 3 : curse.power === 'Medium' ? 2 : 1);
    const remaining = maxUses - used;
    return `${remaining}/${maxUses} selections left`;
  }

  // Curse of Frugality - shows "Next purchase"
  if (curseName.includes('frugality')) {
    return 'Next purchase';
  }

  // Curse of Decay - shows remaining passive items
  if (curseName.includes('decay')) {
    if (!gameState.decayUses) gameState.decayUses = {};
    const used = gameState.decayUses[curse.name] || 0;
    const maxUses = curse.power === 'High' ? 3 : curse.power === 'Medium' ? 2 : 1;
    const remaining = maxUses - used;
    return `${remaining}/${maxUses} passive items left`;
  }

  // Manual curses that track games beaten (Devotion, Greed, Impulse, etc.)
  const duration = curse.duration || '';
  if (duration.toLowerCase().includes('until') && duration.toLowerCase().includes('game')) {
    // Parse the required number of games from duration (e.g., "Until 2 Games Beaten" -> 2)
    const match = duration.match(/(\d+)\s+game/i);
    if (match) {
      const requiredGames = parseInt(match[1]);

      // Get current progress from tracker (use curse ID for accurate tracking of duplicates)
      if (!gameState.cursesTracker) gameState.cursesTracker = {};
      const trackerId = curse.id || curse.name; // Fallback to name for old saves
      const tracker = gameState.cursesTracker[trackerId] || { gamesBeaten: 0 };
      const currentGames = tracker.gamesBeaten || 0;
      return `${currentGames}/${requiredGames} games beaten`;
    }
  }

  // Default - show duration string
  return curse.duration;
}

function updateCursesDisplay() {
  const cursesList = document.getElementById('game-curses-list');
  if (!cursesList) return;

  // Get active curses from game state
  const activeCurses = gameState.activeCurses || [];

  if (activeCurses.length === 0) {
    cursesList.innerHTML = '<div class="empty-curses" style="color: #888; font-style: italic; padding: 10px; text-align: center;">No active curses</div>';
  } else {
    // Separate curses into restriction, manual, and automatic
    const restrictionCurses = activeCurses.filter(curse =>
      curse.name.toLowerCase().includes('blindness') ||
      curse.name.toLowerCase().includes('hubris')
    );
    const manualCurses = activeCurses.filter(curse =>
      curse.name.toLowerCase().includes('devotion') ||
      curse.name.toLowerCase().includes('greed') ||
      curse.name.toLowerCase().includes('impulse') ||
      curse.name.toLowerCase().includes('haste') ||
      curse.name.toLowerCase().includes('guilt')
    );
    const automaticCurses = activeCurses.filter(curse =>
      !restrictionCurses.includes(curse) && !manualCurses.includes(curse)
    );

    // Sort function: within same curse name, higher tier first (High > Medium > Low)
    const sortCursesByTier = (a, b) => {
      const powerOrder = { 'High': 3, 'Medium': 2, 'Low': 1 };
      const aBaseName = a.name.replace(/ (I|II|III)$/, '');
      const bBaseName = b.name.replace(/ (I|II|III)$/, '');

      // Same curse name - sort by tier
      if (aBaseName === bBaseName) {
        return (powerOrder[b.power] || 0) - (powerOrder[a.power] || 0);
      }
      // Different curse names - keep original order
      return 0;
    };

    // Sort each category by tier
    restrictionCurses.sort(sortCursesByTier);
    manualCurses.sort(sortCursesByTier);
    automaticCurses.sort(sortCursesByTier);

    // Display restriction (purple) first, then manual (orange), then automatic (red)
    const sortedCurses = [...restrictionCurses, ...manualCurses, ...automaticCurses];

    cursesList.innerHTML = sortedCurses.map((curse, idx) => {
      const remainingText = getCurseRemainingText(curse);
      const isRestriction = restrictionCurses.includes(curse);
      const isManual = manualCurses.includes(curse);

      // Different colors for restriction vs manual vs automatic curses
      const bgColor = isRestriction ? 'rgba(170, 102, 255, 0.1)' :
                      isManual ? 'rgba(255, 170, 68, 0.1)' :
                      'rgba(255, 102, 102, 0.1)';
      const borderColor = isRestriction ? '#aa66ff' :
                         isManual ? '#ffaa44' : '#ff6666';
      const titleColor = isRestriction ? '#bb99ff' :
                        isManual ? '#ffbb66' : '#ff9999';
      const descColor = isRestriction ? '#aa88cc' :
                       isManual ? '#ccaa88' : '#cc8888';
      const remainingColor = isRestriction ? '#9977aa' :
                            isManual ? '#aa9977' : '#aa7777';

      return `
        <div class="curse-display" style="
          background: ${bgColor};
          border: 1px solid ${borderColor};
          border-radius: 6px;
          padding: 8px;
          margin: 5px 0;
        ">
          <div style="color: ${titleColor}; font-weight: bold; font-size: 14px;">${curse.name}</div>
          <div style="color: ${descColor}; font-size: 12px; margin-top: 4px;">${curse.description}</div>
          <div style="color: ${remainingColor}; font-size: 11px; margin-top: 4px; font-style: italic;">Remaining: ${remainingText}</div>
        </div>
      `;
    }).join('');
  }
}

function updateVerificationCursesDisplay() {
  // Manual curses are now shown in the main curses display (orange-styled, above automatic curses)
  // This function is kept for backwards compatibility but no longer needed
  const verificationSection = document.getElementById('verification-curses');
  if (verificationSection) {
    verificationSection.style.display = 'none';
  }
}

// ===== GAME LISTS =====

function updateExcludedGamesList() {
  const excludedGamesListDiv = document.getElementById('excludedGamesList');
  excludedGamesListDiv.innerHTML = '';
  excludedGames.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'excluded-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-excluded-game" onclick="removeExcludedGame(${index})">×</span>
    `;
    excludedGamesListDiv.appendChild(gameDiv);
  });
}

function updateBeatenGamesList() {
  const beatenGamesListDiv = document.getElementById('beatenGamesList');
  beatenGamesListDiv.innerHTML = '';
  beatenGames.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'beaten-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-game" onclick="removeBeatenGame(${index})">×</span>
    `;
    beatenGamesListDiv.appendChild(gameDiv);
  });

  populateEscapeGameDropdown();
  document.getElementById('randomSelectForPhase2').disabled = beatenGames.length < 3;
}

function populateEscapeGameDropdown() {
  const selectGameForEscape = document.getElementById('selectGameForEscape');
  selectGameForEscape.innerHTML = '<option value="">-- Select a Game --</option>';
  beatenGames.forEach(game => {
    const option = document.createElement('option');
    option.value = game;
    option.textContent = game;
    selectGameForEscape.appendChild(option);
  });

  selectGameForEscape.disabled = beatenGames.length < 3;
  document.getElementById('addGameForEscape').disabled = beatenGames.length < 3;
}

function updateSelectedGamesDisplay() {
  const selectedGamesDiv = document.getElementById('selectedGames');
  selectedGamesDiv.innerHTML = '';
  selectedPhase2Games.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'beaten-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-selected-game" onclick="removeSelectedGame(${index})">×</span>
    `;
    selectedGamesDiv.appendChild(gameDiv);
  });

  if (selectedPhase2Games.length >= 3) {
    document.getElementById('selectGameForEscape').disabled = true;
    document.getElementById('addGameForEscape').disabled = true;
    document.getElementById('randomSelectForPhase2').disabled = true;
  }
}

// ===== PACT OF PUNISHMENT =====

function updateRoguePointsDisplay() {
  document.getElementById('rogue-points-display').textContent = `Rogue Points: ${roguePoints}`;
}

function updateConditionCounts() {
  document.getElementById('lessHealth-count').textContent = pactConditions.lessHealth;
  document.getElementById('moreGames-count').textContent = pactConditions.moreGames;
  document.getElementById('randomGame-count').textContent = pactConditions.randomGame;
  document.getElementById('challengeRun-count').textContent = pactConditions.challengeRun;
}

// ===== ENCOUNTER HISTORY =====

function updateEncounterHistory() {
  const historyDiv = document.getElementById('encounterHistory');
  historyDiv.innerHTML = '';

  encounterHistory.forEach((encounter, index) => {
    const encounterDiv = document.createElement('div');
    encounterDiv.className = 'encounter-history-item';

    if (encounter.type === 'event') {
      encounterDiv.innerHTML = `
        <strong>${encounter.name}</strong>
        <span class="remove-history-item" onclick="removeEncounterHistoryItem(${index})">×</span>
        <p>${encounter.option}</p>
        <small>${encounter.timestamp}</small>
      `;
    } else if (encounter.type === 'combat') {
      encounterDiv.innerHTML = `
        <strong>Combat: ${encounter.enemy}</strong>
        <span class="remove-history-item" onclick="removeEncounterHistoryItem(${index})">×</span>
        <p>${encounter.outcome}</p>
        <small>${encounter.timestamp}</small>
      `;
    }

    historyDiv.appendChild(encounterDiv);
  });
}

// ===== GAME STATS SIDEBAR =====

function updateGameStats() {
  // Update stats in the game view sidebar
  const statsHealth = document.getElementById('stats-health');
  const statsGold = document.getElementById('stats-gold');
  const statsStrength = document.getElementById('stats-strength');
  const statsPower = document.getElementById('stats-power');
  const statsDexterity = document.getElementById('stats-dexterity');
  const statsDefense = document.getElementById('stats-defense');
  const statsIntelligence = document.getElementById('stats-intelligence');
  const statsCharisma = document.getElementById('stats-charisma');
  const statsReroll = document.getElementById('stats-reroll');
  const statsDash = document.getElementById('stats-dash');
  const statsSkip = document.getElementById('stats-skip');
  const statsDiscovery = document.getElementById('stats-discovery');
  const statsFoV = document.getElementById('stats-fov');
  const statsLuck = document.getElementById('stats-luck');
  const statsItems = document.getElementById('stats-items');
  const statsGames = document.getElementById('stats-games');
  const statsSkippedGames = document.getElementById('stats-skipped');
  const statsDistance = document.getElementById('stats-distance');
  const statsDifficulty = document.getElementById('stats-difficulty');

  if (statsHealth) statsHealth.textContent = `${health}/${maxHealth}`;
  if (statsGold) statsGold.textContent = gold;

  // Update character info
  const characterIcon = document.getElementById('character-icon');
  const statsCharacterName = document.getElementById('stats-character-name');
  if (gameState && gameState.character && PLAYER_CHARACTERS[gameState.character]) {
    const character = PLAYER_CHARACTERS[gameState.character];
    if (characterIcon) characterIcon.src = character.fullImage || character.icon;
    if (statsCharacterName) statsCharacterName.textContent = character.name;
  }

  // Use getTotalBonuses() to include all bonuses (scalable passives + weapon)
  const totalBonuses = typeof getTotalBonuses === 'function' ? getTotalBonuses() : null;

  // Strength stat with bonuses
  if (statsStrength) {
    const effectiveStrength = totalBonuses ? strength + totalBonuses.strength : strength;
    if (totalBonuses && totalBonuses.strength !== 0) {
      statsStrength.textContent = `${effectiveStrength} (${strength}+${totalBonuses.strength})`;
    } else {
      statsStrength.textContent = strength;
    }
  }

  // Get active combat state for combat-time status bonuses
  const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
  const combatPower = cs ? (cs.player.statuses['power'] || 0) : 0;
  const combatDefense = cs ? (cs.player.statuses['defense'] || 0) : 0;

  // Power derived stat (every 3 Strength = 1 Power) + any combat/item power bonuses
  if (statsPower) {
    const effectiveStrength = totalBonuses ? strength + totalBonuses.strength : strength;
    const basePower = Math.floor(effectiveStrength / 3);
    const totalPower = basePower + combatPower;
    if (combatPower !== 0) {
      statsPower.textContent = `${totalPower} (${basePower}+${combatPower})`;
    } else {
      statsPower.textContent = totalPower;
    }
  }

  // Dexterity stat with bonuses
  if (statsDexterity) {
    const effectiveDexterity = totalBonuses ? dexterity + totalBonuses.dexterity : dexterity;
    if (totalBonuses && totalBonuses.dexterity !== 0) {
      statsDexterity.textContent = `${effectiveDexterity} (${dexterity}+${totalBonuses.dexterity})`;
    } else {
      statsDexterity.textContent = dexterity;
    }
  }

  // Defense derived stat (every 3 Dexterity = 1 Defense) + any combat/item defense bonuses
  if (statsDefense) {
    const effectiveDexterity = totalBonuses ? dexterity + totalBonuses.dexterity : dexterity;
    const baseDefense = Math.floor(effectiveDexterity / 3);
    const totalDefense = baseDefense + combatDefense;
    if (combatDefense !== 0) {
      statsDefense.textContent = `${totalDefense} (${baseDefense}+${combatDefense})`;
    } else {
      statsDefense.textContent = totalDefense;
    }
  }

  // Intelligence stat with bonuses
  if (statsIntelligence) {
    const effectiveIntelligence = totalBonuses ? intelligence + totalBonuses.intelligence : intelligence;
    if (totalBonuses && totalBonuses.intelligence !== 0) {
      statsIntelligence.textContent = `${effectiveIntelligence} (${intelligence}+${totalBonuses.intelligence})`;
    } else {
      statsIntelligence.textContent = intelligence;
    }
  }

  // Charisma stat with bonuses
  if (statsCharisma) {
    const effectiveCharisma = totalBonuses ? charisma + totalBonuses.charisma : charisma;
    if (totalBonuses && totalBonuses.charisma !== 0) {
      statsCharisma.textContent = `${effectiveCharisma} (${charisma}+${totalBonuses.charisma})`;
    } else {
      statsCharisma.textContent = charisma;
    }
  }
  if (statsReroll) statsReroll.textContent = reroll;
  if (statsDash) statsDash.textContent = dash;
  if (statsSkip) statsSkip.textContent = skip;
  if (statsDiscovery) statsDiscovery.textContent = discovery;

  // Check for Curse of Shroud (temporary FoV reduction) - handle stacking
  if (statsFoV) {
    const shroudCurses = gameState?.activeCurses?.filter(c => c.name.toLowerCase().includes('shroud')) || [];
    if (shroudCurses.length > 0) {
      const penalty = shroudCurses.length;
      const effectiveFoV = Math.max(1, fov - penalty);
      statsFoV.textContent = `${effectiveFoV} (${fov}-${penalty})`;
    } else {
      statsFoV.textContent = fov;
    }
  }

  if (statsLuck) statsLuck.textContent = luck;
  if (statsItems) statsItems.textContent = inventory.length;

  // Games Beaten = total games beaten in this run (includes duplicates)
  if (statsGames) {
    const finishedCount = gameState.totalGamesBeaten || 0;
    statsGames.textContent = finishedCount;
  }

  // Games Skipped = games skipped in this run
  if (statsSkippedGames) {
    const skippedCount = gameState.skippedGames?.length || 0;
    statsSkippedGames.textContent = skippedCount;
  }

  // Distance = total games played (including replays)
  if (statsDistance) {
    statsDistance.textContent = gameState.visitedGames?.length || 0;
  }

  // Difficulty = total games beaten (matches difficulty in progress bar)
  if (statsDifficulty) {
    // Ensure totalGamesBeaten is initialized
    if (typeof gameState.totalGamesBeaten !== 'number') {
      gameState.totalGamesBeaten = 0;
    }
    const difficulty = gameState.totalGamesBeaten;
    statsDifficulty.textContent = difficulty;
    console.log(`📊 Updating difficulty display: ${difficulty}`);
  }
}

// ===== SAVE/LOAD LIST =====

function updateSaveList() {
  const saveList = document.getElementById('save-list');
  if (!saveList) return;

  saveList.innerHTML = '';

  for (const [saveName, save] of Object.entries(gameSaves)) {
    const saveItem = document.createElement('div');
    saveItem.style.cssText = 'padding: 10px 15px; border-bottom: 1px solid #4a4440; display: flex; justify-content: space-between; align-items: center;';

    const characterName = PLAYER_CHARACTERS[save.character]?.name || 'Unknown';

    const infoDiv = document.createElement('div');
    infoDiv.style.cssText = 'cursor: pointer; flex: 1;';
    infoDiv.innerHTML = `
      <div style="font-weight: bold; color: #ffcc66;">${saveName}</div>
      <div style="font-size: 11px; color: #b8a890;">
        ${characterName} | Health: ${save.health}/${save.maxHealth} | Gold: ${save.gold} | Games: ${save.beatenGames?.length || 0}
      </div>
    `;

    infoDiv.onclick = () => {
      loadSavedGame(saveName);
      saveList.style.display = 'none';
    };

    infoDiv.onmouseenter = () => { saveItem.style.background = '#3a3430'; };
    infoDiv.onmouseleave = () => { saveItem.style.background = ''; };

    const deleteBtn = document.createElement('button');
    deleteBtn.textContent = '✕';
    deleteBtn.style.cssText = 'background: #ff6644; border: none; color: white; padding: 4px 8px; border-radius: 4px; cursor: pointer; font-weight: bold; margin-left: 10px;';
    deleteBtn.onclick = (e) => {
      e.stopPropagation();
      if (confirm(`Delete save "${saveName}"?`)) {
        delete gameSaves[saveName];
        GameStorage.save(STORAGE_KEYS.SAVED_GAMES, gameSaves);
        updateSaveList();
      }
    };

    saveItem.appendChild(infoDiv);
    saveItem.appendChild(deleteBtn);
    saveList.appendChild(saveItem);
  }

  const deleteBtn = document.createElement('div');
  deleteBtn.style.cssText = 'padding: 10px 15px; cursor: pointer; color: #ff6644; text-align: center; border-top: 1px solid #4a4440;';
  deleteBtn.textContent = 'Delete All Saves';
  deleteBtn.onclick = () => {
    if (confirm('Delete all saved games?')) {
      gameSaves = {};
      GameStorage.save(STORAGE_KEYS.SAVED_GAMES, gameSaves);
      updateSaveList();
    }
  };
  saveList.appendChild(deleteBtn);
}

// ===== ITEM TOOLTIPS =====

let itemTooltip;

function initItemTooltip() {
  if (!itemTooltip) {
    itemTooltip = document.getElementById('item-tooltip');
  }
  return itemTooltip;
}

function showItemTooltip(e, item) {
  const tooltip = initItemTooltip();
  if (!tooltip || !item) return;

  // Clear any pending hide timeout when showing
  if (itemTooltipHideTimeout) {
    clearTimeout(itemTooltipHideTimeout);
    itemTooltipHideTimeout = null;
  }

  // Get rarity color
  const rarityColors = {
    common: '#aaa',
    uncommon: '#4CAF50',
    rare: '#9b59b6',
    legendary: '#ff6b00'
  };
  const rarityColor = rarityColors[item.rarity] || '#ffffff';

  // Build tags HTML
  let tagsHTML = '';
  if (item.tags && item.tags.length > 0) {
    tagsHTML = `
      <div style="margin-top: 10px; padding-top: 8px; border-top: 1px solid rgba(255,255,255,0.2);">
        <div style="font-size: 11px; color: #888; margin-bottom: 4px;">Tags:</div>
        <div style="display: flex; flex-wrap: wrap; gap: 4px;">
          ${item.tags.map(tag => `
            <span style="
              font-size: 10px;
              padding: 2px 6px;
              background: rgba(100, 100, 100, 0.3);
              border: 1px solid rgba(150, 150, 150, 0.4);
              border-radius: 3px;
              color: #aaa;
            ">${tag}</span>
          `).join('')}
        </div>
      </div>
    `;
  }

  // Capitalize rarity
  const capitalizedRarity = item.rarity.charAt(0).toUpperCase() + item.rarity.slice(1);

  // Check if this is a weapon and get its level
  let weaponLevelText = '';
  if (item.type === 'Weapon') {
    // Check if this is the equipped weapon
    const isEquipped = gameState.equippedWeapon && gameState.equippedWeapon.name === item.name;
    const level = isEquipped ? (gameState.weaponLevel || 1) : (item.level || 1);

    if (level > 1) {
      weaponLevelText = `<div style="color: #ffaa44; font-weight: bold;">Level ${level}</div>`;
    }
  }

  // Get display name (with stat modifiers for passive items)
  const displayName = (item.type === 'Passive' && typeof getPassiveDisplayName === 'function')
    ? getPassiveDisplayName(item)
    : (item.displayName || item.name);

  // Build weapon bonuses display
  let bonusesHTML = '';
  if (item.type === 'Weapon' && item.bonuses) {
    const bonusEntries = [];
    if (item.bonuses.attack) bonusEntries.push(`+${item.bonuses.attack} Attack`);
    if (item.bonuses.strength) bonusEntries.push(`+${item.bonuses.strength} Strength`);
    if (item.bonuses.dexterity) bonusEntries.push(`+${item.bonuses.dexterity} Dexterity`);
    if (item.bonuses.intelligence) bonusEntries.push(`+${item.bonuses.intelligence} Intelligence`);
    if (item.bonuses.charisma) bonusEntries.push(`+${item.bonuses.charisma} Charisma`);
    if (item.bonuses.luck) bonusEntries.push(`+${item.bonuses.luck} Luck`);

    if (bonusEntries.length > 0) {
      bonusesHTML = `
        <div style="margin-top: 8px; padding-top: 8px; border-top: 1px solid rgba(76, 175, 80, 0.3);">
          <div style="font-size: 12px; color: #4CAF50; font-weight: bold; margin-bottom: 4px;">Accumulated Bonuses:</div>
          <div style="font-size: 12px; color: #8BC34A;">
            ${bonusEntries.join(' • ')}
          </div>
        </div>
      `;
    }
  }

  // Build scaling item bonuses display (e.g., Beefy Ring)
  let scalingBonusHTML = '';
  if (item.type === 'Scaling' && item.name === 'Beefy Ring') {
    const beefyRingBonus = Math.floor((gameState.maxHealth || maxHealth) / 10);
    if (beefyRingBonus > 0) {
      scalingBonusHTML = `
        <div style="margin-top: 8px; padding-top: 8px; border-top: 1px solid rgba(138, 43, 226, 0.3);">
          <div style="font-size: 12px; color: #ba55d3; font-weight: bold; margin-bottom: 4px;">Current Bonus:</div>
          <div style="font-size: 12px; color: #da70d6;">
            +${beefyRingBonus} Attack (from ${gameState.maxHealth || maxHealth} max health)
          </div>
        </div>
      `;
    }
  }

  tooltip.innerHTML = `
    <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 18px;">${displayName}</h4>
    <div style="font-size: 12px; color: #b8a890; margin-bottom: 6px;">
      ${item.reference ? `<div>From: ${item.reference}</div>` : ''}
      <div>${capitalizedRarity} ${item.type}</div>
      ${weaponLevelText}
    </div>
    <div style="font-size: 13px; color: #e0d0b0; line-height: 1.4;">
      ${item.description}
    </div>
    ${bonusesHTML}
    ${scalingBonusHTML}
    ${tagsHTML}
  `;

  tooltip.style.opacity = 1;
  tooltip.style.display = 'block';
  moveItemTooltip(e);
}

function moveItemTooltip(e) {
  const tooltip = initItemTooltip();
  if (!tooltip) return;

  // Position tooltip to the right of the cursor, with boundary checks
  let left = e.clientX + 14;
  let top = e.clientY + 14;

  // Check if tooltip would go off screen on the right
  const tooltipWidth = 280; // Match CSS width
  const tooltipHeight = tooltip.offsetHeight || 200; // Estimate if not rendered

  if (left + tooltipWidth > window.innerWidth) {
    left = e.clientX - tooltipWidth - 14; // Position to the left instead
  }

  // Check if tooltip would go off screen on the bottom
  if (top + tooltipHeight > window.innerHeight) {
    top = window.innerHeight - tooltipHeight - 10;
  }

  tooltip.style.left = left + 'px';
  tooltip.style.top = top + 'px';
}

let itemTooltipHideTimeout = null;

function hideItemTooltip() {
  const tooltip = initItemTooltip();
  if (!tooltip) return;

  // Clear any pending hide timeout
  if (itemTooltipHideTimeout) {
    clearTimeout(itemTooltipHideTimeout);
  }

  tooltip.style.opacity = 0;
  itemTooltipHideTimeout = setTimeout(() => {
    tooltip.style.display = 'none';
    itemTooltipHideTimeout = null;
  }, 150);
}

// ===== EQUIPMENT SLOTS =====

function updateEquipmentSlots() {
  const weaponSlot = document.getElementById('weapon-slot');

  console.log('🔧 updateEquipmentSlots called', {
    weaponSlotExists: !!weaponSlot,
    equippedWeapon: gameState.equippedWeapon?.name,
    weaponLevel: gameState.weaponLevel
  });

  if (!weaponSlot) {
    console.warn('⚠️ Weapon slot not found in DOM');
    return;
  }

  // Update weapon slot
  if (gameState.equippedWeapon) {
    const weaponLevel = gameState.weaponLevel || 1;
    const levelBadge = weaponLevel > 1 ? `
      <div style="
        position: absolute;
        top: 2px;
        right: 2px;
        background: #ffaa44;
        color: #000;
        font-weight: bold;
        font-size: 11px;
        padding: 2px 5px;
        border-radius: 4px;
        line-height: 1;
        z-index: 10;
        pointer-events: none;
      ">Lv${weaponLevel}</div>
    ` : '';

    console.log('✅ Updating weapon slot with:', gameState.equippedWeapon, 'Level:', weaponLevel);
    weaponSlot.classList.add('equipped');
    weaponSlot.innerHTML = `
      <img src="${gameState.equippedWeapon.image}" alt="${gameState.equippedWeapon.name}"
           onerror="this.style.display='none'">
      ${levelBadge}
      <button class="equipment-unequip-btn" onclick="unequipWeapon()">Unequip</button>
    `;

    // Add tooltip functionality
    weaponSlot.onmouseenter = (e) => {
      showWeaponTooltip(e, gameState.equippedWeapon);
    };
    weaponSlot.onmouseleave = () => {
      hideWeaponTooltip();
    };
  } else {
    weaponSlot.classList.remove('equipped');
    weaponSlot.innerHTML = '<div class="equipment-slot-empty">Weapon</div>';
    weaponSlot.onmouseenter = null;
    weaponSlot.onmouseleave = null;
  }
}

function showWeaponTooltip(event, weapon) {
  const tooltip = initItemTooltip();
  if (!tooltip || !weapon) return;

  // Get rarity color
  const rarityColors = {
    common: '#aaa',
    uncommon: '#4CAF50',
    rare: '#9b59b6',
    legendary: '#ff6b00'
  };
  const rarityColor = rarityColors[weapon.rarity?.toLowerCase()] || '#ffffff';

  // Build tags HTML
  let tagsHTML = '';
  if (weapon.tags && weapon.tags.length > 0) {
    tagsHTML = `
      <div style="margin-top: 10px; padding-top: 8px; border-top: 1px solid rgba(255,255,255,0.2);">
        <div style="font-size: 11px; color: #888; margin-bottom: 4px;">Tags:</div>
        <div style="display: flex; flex-wrap: wrap; gap: 4px;">
          ${weapon.tags.map(tag => `
            <span style="
              font-size: 10px;
              padding: 2px 6px;
              background: rgba(100, 100, 100, 0.3);
              border: 1px solid rgba(150, 150, 150, 0.4);
              border-radius: 3px;
              color: #aaa;
            ">${tag}</span>
          `).join('')}
        </div>
      </div>
    `;
  }

  // Capitalize rarity
  const capitalizedRarity = weapon.rarity.charAt(0).toUpperCase() + weapon.rarity.slice(1);

  // Get weapon level
  const weaponLevel = gameState.weaponLevel || 1;
  let weaponLevelText = '';
  if (weaponLevel > 1) {
    weaponLevelText = `<div style="color: #ffaa44; font-weight: bold;">Level ${weaponLevel}</div>`;
  }

  // Build weapon bonuses display
  let bonusesHTML = '';
  if (weapon.bonuses) {
    const bonusEntries = [];
    if (weapon.bonuses.attack) bonusEntries.push(`+${weapon.bonuses.attack} Attack`);
    if (weapon.bonuses.strength) bonusEntries.push(`+${weapon.bonuses.strength} Strength`);
    if (weapon.bonuses.dexterity) bonusEntries.push(`+${weapon.bonuses.dexterity} Dexterity`);
    if (weapon.bonuses.intelligence) bonusEntries.push(`+${weapon.bonuses.intelligence} Intelligence`);
    if (weapon.bonuses.charisma) bonusEntries.push(`+${weapon.bonuses.charisma} Charisma`);
    if (weapon.bonuses.luck) bonusEntries.push(`+${weapon.bonuses.luck} Luck`);

    if (bonusEntries.length > 0) {
      bonusesHTML = `
        <div style="margin-top: 8px; padding-top: 8px; border-top: 1px solid rgba(76, 175, 80, 0.3);">
          <div style="font-size: 12px; color: #4CAF50; font-weight: bold; margin-bottom: 4px;">Accumulated Bonuses:</div>
          <div style="font-size: 12px; color: #8BC34A;">
            ${bonusEntries.join(' • ')}
          </div>
        </div>
      `;
    }
  }

  tooltip.innerHTML = `
    <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 18px;">${weapon.name}</h4>
    <div style="font-size: 12px; color: #b8a890; margin-bottom: 6px;">
      ${weapon.reference ? `<div>From: ${weapon.reference}</div>` : ''}
      <div>${capitalizedRarity} ${weapon.type}</div>
      ${weaponLevelText}
    </div>
    <div style="font-size: 13px; color: #e0d0b0; line-height: 1.4;">
      ${weapon.description}
    </div>
    ${bonusesHTML}
    ${tagsHTML}
  `;

  tooltip.style.opacity = 1;
  tooltip.style.display = 'block';
  moveItemTooltip(event);
}

function hideWeaponTooltip() {
  hideItemTooltip();
}

function getRarityColor(rarity) {
  const rarityColors = {
    'Common': '#aaa',
    'Uncommon': '#4CAF50',
    'Rare': '#9b59b6',
    'Epic': '#e91e63',
    'Legendary': '#ff6b00'
  };
  return rarityColors[rarity] || '#aaa';
}

// Export functions to global scope for backwards compatibility
window.updateTopBar = updateTopBar;
window.updateHealthDisplay = updateHealthDisplay;
window.updateGoldDisplay = updateGoldDisplay;
window.updateLocationDisplay = updateLocationDisplay;
window.updateInventory = updateInventory;
window.updateCursesDisplay = updateCursesDisplay;
window.updateVerificationCursesDisplay = updateVerificationCursesDisplay;
window.updateExcludedGamesList = updateExcludedGamesList;
window.updateBeatenGamesList = updateBeatenGamesList;
window.updateSelectedGamesDisplay = updateSelectedGamesDisplay;
window.updateRoguePointsDisplay = updateRoguePointsDisplay;
window.updateConditionCounts = updateConditionCounts;
window.updateEncounterHistory = updateEncounterHistory;
window.updateGameStats = updateGameStats;
window.updateSaveList = updateSaveList;
window.populateEscapeGameDropdown = populateEscapeGameDropdown;
window.updateEquipmentSlots = updateEquipmentSlots;
window.equipWeapon = equipWeapon;
window.upgradeWeapon = upgradeWeapon;
window.unequipWeapon = unequipWeapon;
