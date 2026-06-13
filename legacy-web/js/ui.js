// ===== UI.JS - All DOM Manipulation and Display Updates =====
//
// This module handles all visual updates to the UI including:
// - Top bar (health, gold, rations)
// - Inventory display
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

  // Calculate difficulty tier first — needed for both battery and location label
  const difficulty = gameState.totalGamesBeaten || 0;
  const thresholds = (typeof DIFFICULTY_THRESHOLDS !== 'undefined')
    ? DIFFICULTY_THRESHOLDS
    : { MEDIUM: 4, HARD: 8, INSANE: 12 };

  let tier, tierText, rangeText;
  if (difficulty >= thresholds.INSANE) {
    tier = 'insane'; tierText = 'Insane'; rangeText = `${thresholds.INSANE}+`;
  } else if (difficulty >= thresholds.HARD) {
    tier = 'hard'; tierText = 'Hard'; rangeText = `${thresholds.HARD}-${thresholds.INSANE - 1}`;
  } else if (difficulty >= thresholds.MEDIUM) {
    tier = 'medium'; tierText = 'Medium'; rangeText = `${thresholds.MEDIUM}-${thresholds.HARD - 1}`;
  } else {
    tier = 'easy'; tierText = 'Easy'; rangeText = `0-${thresholds.MEDIUM - 1}`;
  }

  // Always update battery bar — does not depend on location elements
  const tierSize = (typeof DIFFICULTY_TIER_SIZE !== 'undefined') ? DIFFICULTY_TIER_SIZE : 4;
  const fillCount = difficulty % tierSize;
  for (let i = 0; i < 4; i++) {
    const seg = document.getElementById(`battery-seg-${i}`);
    if (!seg) continue;
    seg.className = i < fillCount ? `battery-segment filled ${tier}` : 'battery-segment';
  }

  if (currentDifficulty) {
    currentDifficulty.textContent = `Current Difficulty: ${difficulty}`;
  }

  // Location name and tier label are optional — skip if elements absent
  if (tierLabel) {
    tierLabel.innerHTML = `${tierText}<br><span class="tier-range">${rangeText}</span>`;
    tierLabel.className = `tier-label ${tier}`;
  }

  if (!locationName) return;

  // Get the current location from gameState
  const location = gameState?.location;

  if (location) {
    locationName.textContent = location.name || 'Current Location';
    if (locationType) {
      const type = location.type || 'Unknown';
      const typeColors = {
        'Undead': '#9b59b6', 'Firey': '#e74c3c', 'Watery': '#3498db',
        'Building': '#95a5a6', 'Chaos': '#e67e22', 'General': '#2ecc71'
      };
      locationType.textContent = type;
      locationType.style.color = typeColors[type] || '#aaa';
    }
    if (locationGame) locationGame.textContent = location.game;
    if (locationEffect) locationEffect.textContent = location.effect || 'No effect';
    if (locationSection) locationSection.dataset.description = location.effect || 'No effect';
  } else {
    locationName.textContent = gameName || 'Current Location';
    if (locationType) { locationType.textContent = 'Unknown'; locationType.style.color = '#aaa'; }
    if (locationGame) locationGame.textContent = 'No location selected';
    if (locationEffect) locationEffect.textContent = 'No effect';
    if (locationSection) locationSection.dataset.description = gameDescription || 'No description available';
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

  // Reset inline display so the .visible CSS class can take effect
  locationTooltip.style.display = '';

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
    initStatTooltips();
  });
} else {
  initLocationTooltip();
  initStatTooltips();
}

// ===== STAT TOOLTIPS =====
// Body-level tooltip bypasses the overflow-y:auto stacking context on #game-stats

function initStatTooltips() {
  const popup = document.createElement('div');
  popup.id = 'stat-tooltip-popup';
  document.body.appendChild(popup);

  document.querySelectorAll('.stat-tooltip').forEach(el => {
    el.addEventListener('mouseenter', () => {
      const text = el.getAttribute('data-tooltip');
      if (!text) return;
      popup.textContent = text;
      popup.style.display = 'block';
    });
    el.addEventListener('mousemove', (e) => {
      const GAP = 14;
      const pw = popup.offsetWidth;
      const ph = popup.offsetHeight;
      let left = e.clientX + GAP;
      let top = e.clientY - ph / 2;
      if (left + pw > window.innerWidth - 8) left = e.clientX - pw - GAP;
      if (top < 8) top = 8;
      if (top + ph > window.innerHeight - 8) top = window.innerHeight - ph - 8;
      popup.style.left = left + 'px';
      popup.style.top = top + 'px';
    });
    el.addEventListener('mouseleave', () => {
      popup.style.display = 'none';
    });
  });
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

    const isCharged = typeof isChargedItem === 'function' && isChargedItem(item);
    const isUsable = item.type === 'Usable' || item.type === 'Active' || isCharged;
    const isIncremental = (item.type || '').toLowerCase() === 'incremental';
    const canUse = isUsable && typeof canUseItem === 'function' && canUseItem(item);
    const incBadge = isIncremental ? getIncrementalBadge(item) : '';

    const snowballBadge = item.name === 'Snowball' && (typeof gameState !== 'undefined') && (gameState.snowballTotal || 0) > 0
      ? `<div style="position:absolute;bottom:1px;left:1px;background:rgba(0,0,0,0.9);color:#88ccff;padding:1px 3px;border-radius:3px;font-size:8px;font-weight:bold;border:1px solid #88ccff;">+${gameState.snowballTotal}</div>`
      : '';

    const quantityBadge = item.quantity && item.quantity > 1
      ? `<div style="position:absolute;top:1px;right:1px;background:rgba(0,0,0,0.9);color:white;padding:1px 3px;border-radius:3px;font-size:8px;font-weight:bold;border:1px solid #ffaa00;">${item.quantity}</div>`
      : '';

    // Charged: render a segmented bar instead of an incremental counter
    let chargeBar = '';
    if (isCharged) {
      const max = parseChargedMax(item.type);
      const cur = typeof item.charges === 'number' ? item.charges : max;
      const segments = Array.from({ length: max }, (_, i) =>
        `<div style="flex:1;height:3px;border-radius:1px;background:${i < cur ? '#f1c40f' : 'rgba(255,255,255,0.15)'};"></div>`
      ).join('');
      chargeBar = `<div style="position:absolute;top:1px;left:1px;right:1px;display:flex;gap:1px;">${segments}</div>`;
    }

    const useBtn = isUsable
      ? `<button onclick="event.stopPropagation(); if(typeof useItem==='function') useItem(${idx});" title="${canUse ? 'Use' : 'Cannot use now'}" style="position:absolute;bottom:0;left:0;right:0;font-size:8px;padding:1px;background:${canUse ? '#4CAF50' : '#555'};color:${canUse ? 'white' : '#888'};border:none;border-radius:0 0 4px 4px;cursor:${canUse ? 'pointer' : 'not-allowed'};font-weight:bold;${canUse ? '' : 'opacity:0.6;'}">${canUse ? 'USE' : '—'}</button>`
      : '';

    const descText = isCharged && typeof getChargedDisplayDescription === 'function'
      ? getChargedDisplayDescription(item)
      : (item.description || '');

    return `<div title="${item.name}: ${descText}" style="position:relative;width:40px;height:40px;border:2px solid ${color};border-radius:6px;background:rgba(0,0,0,0.5);overflow:visible;flex-shrink:0;">
      ${imgSrc
        ? `<img src="${imgSrc}" alt="${item.name}" style="width:100%;height:100%;object-fit:contain;border-radius:4px;" onerror="this.style.display='none'">`
        : `<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;font-size:18px;">🎒</div>`}
      ${quantityBadge}${incBadge}${snowballBadge}${chargeBar}${useBtn}
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
    const displayName = ((item.type || '').includes('Passive') && typeof getPassiveDisplayName === 'function')
      ? getPassiveDisplayName(item)
      : (item.displayName || item.name);

    if (inventoryDiv) {
      const itemDiv = document.createElement('div');
      itemDiv.className = 'inventory-item';
      const snowballLine = item.name === 'Snowball' && (gameState.snowballTotal || 0) > 0
        ? `<p style="color: #88ccff;"><em>Intelligence granted this run: +${gameState.snowballTotal}</em></p>`
        : '';
      const isChargedInv = typeof isChargedItem === 'function' && isChargedItem(item);
      const descText = isChargedInv && typeof getChargedDisplayDescription === 'function'
        ? getChargedDisplayDescription(item)
        : (item.description || '');
      const chargeLine = isChargedInv ? (() => {
        const max = parseChargedMax(item.type);
        const cur = typeof item.charges === 'number' ? item.charges : max;
        const scopeLabel = typeof getChargedScopeLabel === 'function' ? getChargedScopeLabel(item) : '';
        return `<p><em style="color:#f1c40f;">Charges: ${cur}/${max}${scopeLabel ? ` · ${scopeLabel}` : ''}</em></p>`;
      })() : '';
      itemDiv.innerHTML = `
        <strong>${displayName}</strong> (${item.rarity})
        <span class="remove-item" onclick="removeItem(${index})">×</span>
        <p>${descText}</p>
        <p><em>Type: ${item.type}</em></p>
        ${chargeLine}
        ${snowballLine}
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

        const isCharged = typeof isChargedItem === 'function' && isChargedItem(item);
        const isUsable = item.type === 'Usable' || item.type === 'Active' || isCharged;
        const canUse = isUsable && typeof canUseItem === 'function' && canUseItem(item);
        const isWeapon = item.type === 'Weapon';
        const maxCharges = isCharged ? parseChargedMax(item.type) : 0;
        const curCharges = isCharged ? (typeof item.charges === 'number' ? item.charges : maxCharges) : 0;
        const scopeLabel = isCharged && typeof getChargedScopeLabel === 'function' ? getChargedScopeLabel(item) : '';
        const chargeBarHTML = isCharged && maxCharges > 0 ? `
          <div style="
            position:absolute; top:4px; left:4px; right:4px;
            display:flex; gap:2px; z-index:14;
          ">
            ${Array.from({ length: maxCharges }, (_, i) => `
              <div style="flex:1;height:5px;border-radius:2px;border:1px solid rgba(0,0,0,0.6);background:${i < curCharges ? '#f1c40f' : 'rgba(0,0,0,0.6)'};"></div>
            `).join('')}
          </div>` : '';
        const scopePillHTML = isCharged && scopeLabel ? `
          <div style="
            position:absolute; top:20px; left:-2px; right:-2px;
            text-align:center; font-size:8px; font-weight:bold;
            color:#fff; background:rgba(0,0,0,0.7);
            padding:1px 0; border-radius:3px; z-index:14;
            border:1px solid rgba(255,255,255,0.2);
            white-space:nowrap;
          ">${scopeLabel}</div>` : '';

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
              ${chargeBarHTML}
              ${scopePillHTML}
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
                  ${isCharged ? `${curCharges}/${maxCharges}` : `Use${item.uses && item.uses > 1 ? ` x${item.uses}` : ''}`}
                </button>
              ` : ''}
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

    }
  }

  updateGameStats();
  updateSidebarItems();
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
    if (statsCharacterName) {
      const lv = (typeof gameState !== 'undefined' && gameState.playerLevel) ? gameState.playerLevel : 1;
      statsCharacterName.innerHTML = `${character.name} <span style="color:#ff9800;font-size:13px;">Lv:${lv}</span>`;
    }
  }

  // Use getTotalBonuses() to include all bonuses (scalable passives + weapon)
  const totalBonuses = typeof getTotalBonuses === 'function' ? getTotalBonuses() : null;
  // Pill bonuses (combat + event scope) — temporary and shown as extra +X
  const pillBonuses = typeof getPillBonuses === 'function' ? getPillBonuses() : null;

  function fmtStatLine(base, passive, pill) {
    const total = base + passive + pill;
    const parts = [String(base)];
    if (passive) parts.push((passive >= 0 ? '+' : '') + passive);
    if (pill)    parts.push((pill    >= 0 ? '+' : '') + pill);
    return parts.length > 1 ? `${total} (${parts.join('')})` : String(total);
  }

  // Strength stat with bonuses
  if (statsStrength) {
    const passive = totalBonuses ? totalBonuses.strength : 0;
    const pill = pillBonuses ? pillBonuses.strength : 0;
    statsStrength.textContent = fmtStatLine(strength, passive, pill);
  }

  // Get active combat state for combat-time status bonuses
  const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
  const combatPower = cs ? (cs.player.statuses['power'] || 0) : 0;
  const combatDefense = cs ? (cs.player.statuses['defense'] || 0) : 0;

  // Power derived stat (every 3 Strength = 1 Power) + any combat/item power bonuses.
  // Pill bonuses in combat are already folded into statuses['power'], so the
  // base calculation only uses the persistent (non-pill) strength total — otherwise
  // we'd double-count.
  if (statsPower) {
    const passiveStr = totalBonuses ? totalBonuses.strength : 0;
    const pillStr = pillBonuses ? pillBonuses.strength : 0;
    const basePower = Math.floor((strength + passiveStr) / 3);
    const totalPower = basePower + combatPower + (cs ? 0 : pillStr ? Math.floor(pillStr / 3) : 0);
    if (combatPower !== 0) {
      statsPower.textContent = `${totalPower} (${basePower}+${combatPower})`;
    } else if (pillStr && !cs) {
      const extra = Math.floor(pillStr / 3);
      statsPower.textContent = extra ? `${totalPower} (${basePower}+${extra})` : String(totalPower);
    } else {
      statsPower.textContent = totalPower;
    }
  }

  // Dexterity stat with bonuses
  if (statsDexterity) {
    const passive = totalBonuses ? totalBonuses.dexterity : 0;
    const pill = pillBonuses ? pillBonuses.dexterity : 0;
    statsDexterity.textContent = fmtStatLine(dexterity, passive, pill);
  }

  // Defense derived stat
  if (statsDefense) {
    const passiveDex = totalBonuses ? totalBonuses.dexterity : 0;
    const pillDex = pillBonuses ? pillBonuses.dexterity : 0;
    const baseDefense = Math.floor((dexterity + passiveDex) / 3);
    const totalDefense = baseDefense + combatDefense + (cs ? 0 : Math.floor(pillDex / 3));
    if (combatDefense !== 0) {
      statsDefense.textContent = `${totalDefense} (${baseDefense}+${combatDefense})`;
    } else if (pillDex && !cs) {
      const extra = Math.floor(pillDex / 3);
      statsDefense.textContent = extra ? `${totalDefense} (${baseDefense}+${extra})` : String(totalDefense);
    } else {
      statsDefense.textContent = totalDefense;
    }
  }

  // Intelligence stat with bonuses
  if (statsIntelligence) {
    const passive = totalBonuses ? totalBonuses.intelligence : 0;
    const pill = pillBonuses ? pillBonuses.intelligence : 0;
    statsIntelligence.textContent = fmtStatLine(intelligence, passive, pill);
  }

  // Arcane derived stat
  const combatArcane = cs ? (cs.player.statuses['arcane'] || 0) : 0;
  const statsArcane = document.getElementById('stats-arcane');
  if (statsArcane) {
    const passiveInt = totalBonuses ? totalBonuses.intelligence : 0;
    const pillInt = pillBonuses ? pillBonuses.intelligence : 0;
    const baseArcane = Math.floor((intelligence + passiveInt) / 3);
    const totalArcane = baseArcane + combatArcane + (cs ? 0 : Math.floor(pillInt / 3));
    if (combatArcane !== 0) {
      statsArcane.textContent = `${totalArcane} (${baseArcane}+${combatArcane})`;
    } else if (pillInt && !cs) {
      const extra = Math.floor(pillInt / 3);
      statsArcane.textContent = extra ? `${totalArcane} (${baseArcane}+${extra})` : String(totalArcane);
    } else {
      statsArcane.textContent = totalArcane;
    }
  }

  // Charisma stat with bonuses
  if (statsCharisma) {
    const passive = totalBonuses ? totalBonuses.charisma : 0;
    const pill = pillBonuses ? pillBonuses.charisma : 0;
    statsCharisma.textContent = fmtStatLine(charisma, passive, pill);
  }

  // Persistence derived stat (5:1 ratio)
  const combatPersistence = cs ? (cs.player.statuses['persistence'] || 0) : 0;
  const statsPersistence = document.getElementById('stats-persistence');
  if (statsPersistence) {
    const passiveCha = totalBonuses ? totalBonuses.charisma : 0;
    const pillCha = pillBonuses ? pillBonuses.charisma : 0;
    const basePersistence = Math.floor((charisma + passiveCha) / 5);
    const totalPersistence = basePersistence + combatPersistence + (cs ? 0 : Math.floor(pillCha / 5));
    if (combatPersistence !== 0) {
      statsPersistence.textContent = `${totalPersistence} (${basePersistence}+${combatPersistence})`;
    } else if (pillCha && !cs) {
      const extra = Math.floor(pillCha / 5);
      statsPersistence.textContent = extra ? `${totalPersistence} (${basePersistence}+${extra})` : String(totalPersistence);
    } else {
      statsPersistence.textContent = totalPersistence;
    }
  }

  // Constitution derived stat — every 5 max HP above/below starting value = ±1 Constitution
  const statsConstitution = document.getElementById('stats-constitution');
  if (statsConstitution) {
    const startingHP = typeof gameState !== 'undefined' && gameState.startingMaxHealth != null
      ? gameState.startingMaxHealth
      : (typeof maxHealth !== 'undefined' ? maxHealth : 0);
    const currentMaxHP = typeof maxHealth !== 'undefined' ? maxHealth : 0;
    const constitution = Math.floor((currentMaxHP - startingHP) / 5);
    statsConstitution.textContent = constitution;
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

  if (statsLuck) {
    const pillLuck = pillBonuses ? pillBonuses.luck : 0;
    statsLuck.textContent = pillLuck ? `${luck + pillLuck} (${luck}${pillLuck >= 0 ? '+' : ''}${pillLuck})` : luck;
  }
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
  let weaponLevel = 1;
  if (item.type === 'Weapon') {
    const isEquipped = gameState.equippedWeapon && gameState.equippedWeapon.name === item.name;
    weaponLevel = isEquipped ? (gameState.weaponLevel || 1) : (item.level || 1);

    if (weaponLevel > 1) {
      weaponLevelText = `<div style="color: #ffaa44; font-weight: bold;">Level ${weaponLevel}</div>`;
    }
  }

  // Resolve (val1/val2/val3) level notation in weapon descriptions
  function resolveWeaponLevelText(desc, lv) {
    return desc.replace(/\(([^)]+)\)/g, (_, inner) => {
      const parts = inner.split('/').map(s => s.trim());
      return parts[Math.min(lv - 1, parts.length - 1)] || parts[parts.length - 1];
    });
  }
  const isChargedTip = typeof isChargedItem === 'function' && isChargedItem(item);
  const resolvedDescription = item.type === 'Weapon'
    ? resolveWeaponLevelText(item.description || '', weaponLevel)
    : isChargedTip && typeof getChargedDisplayDescription === 'function'
      ? getChargedDisplayDescription(item)
      : (item.description || '');

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

  // Build weapon card preview
  let weaponCardHTML = '';
  if (item.type === 'Weapon' && typeof CARDS_DATA !== 'undefined') {
    const baseCard = CARDS_DATA.find(c => c.name === item.name && c.tags && c.tags.includes('weapon'));
    if (baseCard) {
      const rarityCardColors = { Rare: '#9b59b6', Uncommon: '#4CAF50', Common: '#aaa', Starter: '#888' };
      const cardColor = rarityCardColors[baseCard.rarity] || '#aaa';

      const currentCard = (gameState.deck && gameState.deck.find(c => c.name === item.name)) || null;
      const isUpgraded = currentCard && (currentCard.upgraded || currentCard.description !== baseCard.description);

      function buildCardBlock(card, label) {
        const upgradedMark = card.upgraded ? ' +' : '';
        return `
          <div style="background: rgba(0,0,0,0.35); border: 1px solid ${cardColor}; border-radius: 6px; padding: 8px; margin-top: 4px;">
            ${label ? `<div style="font-size: 10px; color: #888; margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.5px;">${label}</div>` : ''}
            <div style="font-weight: bold; color: ${cardColor}; font-size: 12px;">${card.name}${upgradedMark}</div>
            <div style="font-size: 10px; color: #888; margin-bottom: 4px;">${card.rarity || ''} · ${card.type || ''} · Cost: ${card.cost !== undefined ? card.cost : '?'}</div>
            <div style="font-size: 11px; color: #ddd; line-height: 1.4;">${card.description || ''}</div>
          </div>`;
      }

      weaponCardHTML = `
        <div style="margin-top: 10px; padding-top: 8px; border-top: 1px solid rgba(255,165,0,0.3);">
          <div style="font-size: 11px; color: #ffaa44; font-weight: bold; margin-bottom: 4px;">Weapon Card</div>
          ${isUpgraded
            ? buildCardBlock(baseCard, 'Base') + buildCardBlock(currentCard, 'Current')
            : buildCardBlock(currentCard || baseCard, '')}
        </div>`;
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

  // Build Snowball intelligence total display
  let snowballHTML = '';
  if (item.name === 'Snowball') {
    const total = (typeof gameState !== 'undefined' && gameState.snowballTotal) || 0;
    snowballHTML = `
      <div style="margin-top: 8px; padding-top: 8px; border-top: 1px solid rgba(136, 204, 255, 0.3);">
        <div style="font-size: 12px; color: #88ccff; font-weight: bold; margin-bottom: 4px;">Intelligence Granted:</div>
        <div style="font-size: 12px; color: #aaddff;">+${total} total this run</div>
      </div>
    `;
  }

  // For charged items, render scope + charge count separately from description
  let chargedTipHTML = '';
  if (isChargedTip) {
    const max = parseChargedMax(item.type);
    const cur = typeof item.charges === 'number' ? item.charges : max;
    const scopeLabel = typeof getChargedScopeLabel === 'function' ? getChargedScopeLabel(item) : '';
    chargedTipHTML = `
      <div style="font-size:11px;color:#f1c40f;margin-bottom:6px;">
        <span style="font-weight:bold;">Charges:</span> ${cur} / ${max}
        ${scopeLabel ? `<span style="margin-left:8px;color:#7ec8e3;">${scopeLabel}</span>` : ''}
      </div>`;
  }

  tooltip.innerHTML = `
    <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 18px;">${displayName}</h4>
    <div style="font-size: 12px; color: #b8a890; margin-bottom: 6px;">
      ${item.reference ? `<div>From: ${item.reference}</div>` : ''}
      <div>${capitalizedRarity} ${item.type}</div>
      ${weaponLevelText}
    </div>
    ${chargedTipHTML}
    ${item.type === 'Weapon'
      ? `<div style="font-size:10px;color:#ffaa44;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:3px;">Passive Effect</div>`
      : ''}
    <div style="font-size: 13px; color: #e0d0b0; line-height: 1.4;">
      ${resolvedDescription}
    </div>
    ${item.type === 'Weapon'
      ? `<div style="font-size:10px;color:#888;margin-top:5px;font-style:italic;">Upgrading the weapon card levels up this passive.</div>`
      : ''}
    ${bonusesHTML}
    ${scalingBonusHTML}
    ${snowballHTML}
    ${weaponCardHTML}
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

function getRarityColor(rarity) {
  const rarityColors = {
    'Common':    'var(--color-common)',
    'Uncommon':  'var(--color-uncommon)',
    'Rare':      'var(--color-rare)',
    'Epic':      '#e91e63',
    'Legendary': 'var(--color-legendary)'
  };
  return rarityColors[rarity] || 'var(--color-common)';
}

// Export functions to global scope for backwards compatibility
/**
 * Re-render every sidebar/top panel from current gameState. Cheap to call —
 * each updater is idempotent and bails fast if its DOM target is missing.
 * Useful around transitions (post-combat → smith / shop / next encounter)
 * where stale state has been the source of "card I just got isn't showing up"
 * bugs.
 */
function refreshAllUI() {
  if (typeof updateTopBar === 'function')         updateTopBar();
  if (typeof updateGameStats === 'function')      updateGameStats();
  if (typeof updateHealthDisplay === 'function')  updateHealthDisplay();
  if (typeof updateGoldDisplay === 'function')    updateGoldDisplay();
  if (typeof updateInventory === 'function')      updateInventory();
  if (typeof updateSidebarItems === 'function')   updateSidebarItems();
  if (typeof updateCursesDisplay === 'function')  updateCursesDisplay();
  if (typeof updateLootDisplay === 'function')    updateLootDisplay();
}
window.refreshAllUI = refreshAllUI;

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
// updateRoguePointsDisplay and updateConditionCounts were dead references
// in the original code — no such functions exist. Removed so this script
// doesn't ReferenceError mid-evaluation.
window.updateEncounterHistory = updateEncounterHistory;
window.updateGameStats = updateGameStats;
window.updateSaveList = updateSaveList;
window.populateEscapeGameDropdown = populateEscapeGameDropdown;

// Phase 1 (refactor): subscribe to StateMutator notifications so future
// callers can mutate state without remembering which UI functions to call.
// Existing explicit updateTopBar() / updateInventory() calls scattered
// across the codebase remain in place — they double-render with this
// subscriber for now, which is harmless and lets us migrate call sites
// incrementally. Phase 3/4 deletes the explicit calls.
if (typeof window !== 'undefined' && window.StateMutator) {
  window.StateMutator.subscribe((tags) => {
    const t = tags || new Set();
    if (
      t.has('health') ||
      t.has('maxHealth') ||
      t.has('gold') ||
      t.has('maxEnergy') ||
      t.has('abilities') ||
      t.has('stats') ||
      t.has('curses')
    ) {
      if (typeof updateTopBar === 'function') updateTopBar();
    }
    if (
      t.has('stats') ||
      t.has('health') ||
      t.has('maxHealth') ||
      t.has('gold') ||
      t.has('abilities') ||
      t.has('discovery')
    ) {
      if (typeof updateGameStats === 'function') updateGameStats();
    }
    if (t.has('inventory')) {
      if (typeof updateInventory === 'function') updateInventory();
    }
    if (t.has('curses')) {
      if (typeof updateCursesDisplay === 'function') updateCursesDisplay();
    }
  });
}
