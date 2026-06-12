/**
 * Allies system.
 *
 * Extracted from js/main.js as part of the Phase 3 decomposition.
 *
 * Allies are non-player combatants the player can recruit during a run.
 * They roll their own die in combat (handled by combat-engine.js) and
 * have their own HP tracked on gameState.allies. This module owns:
 *   - recruit / dismiss + the random recruit flow
 *   - HP and heal mutators that target an ally by name
 *   - the side-panel UI that lists the active roster
 *
 * Phase 5 (ESM): the window.* exports go away in favor of named exports.
 */

function recruitAlly(allyName) {
  if (!ALLIES_DATA) {
    console.error('ALLIES_DATA not loaded');
    return false;
  }

  const allyData = ALLIES_DATA.find(a => a.name === allyName);
  if (!allyData) {
    console.error('Ally not found:', allyName);
    return false;
  }

  // Check if already recruited
  if (gameState.activeAllies.some(a => a.name === allyName)) {
    return false;
  }

  // Add ally with full HP
  gameState.activeAllies.push({
    name: allyData.name,
    currentHp: allyData.hp
  });

  saveCurrentGame();
  return true;
}

/**
 * Dismiss an ally
 * @param {string} allyName - Name of the ally to dismiss
 * @returns {boolean} Success
 */
function dismissAlly(allyName) {
  const index = gameState.activeAllies.findIndex(a => a.name === allyName);
  if (index === -1) {
    console.error('Ally not found in active allies:', allyName);
    return false;
  }

  gameState.activeAllies.splice(index, 1);
  saveCurrentGame();
  return true;
}

/**
 * Update ally HP after combat
 * @param {string} allyName - Name of the ally
 * @param {number} newHp - New HP value
 */
function updateAllyHp(allyName, newHp) {
  const ally = gameState.activeAllies.find(a => a.name === allyName);
  if (!ally) return;

  ally.currentHp = Math.max(0, newHp);

  // Remove ally if HP <= 0
  if (ally.currentHp <= 0) {
    dismissAlly(allyName);
  }
}

/**
 * Heal an ally
 * @param {string} allyName - Name of the ally
 * @param {number} amount - Amount to heal
 */
function healAlly(allyName, amount) {
  const ally = gameState.activeAllies.find(a => a.name === allyName);
  if (!ally) return;

  const allyData = ALLIES_DATA.find(a => a.name === allyName);
  if (!allyData) return;

  ally.currentHp = Math.min(ally.currentHp + amount, allyData.hp);
  saveCurrentGame();
}

/**
 * Show ally management UI
 */
function showAlliesPanel() {
  const allies = gameState.activeAllies || [];
  const allAvailableAllies = ALLIES_DATA || [];

  const activeAlliesHtml = allies.length > 0 ? allies.map(ally => {
    const baseAlly = allAvailableAllies.find(a => a.name === ally.name);
    if (!baseAlly) return '';
    return `
      <div style="
        background: rgba(76,175,80,0.1);
        border: 2px solid #4CAF50;
        border-radius: 8px;
        padding: 15px;
        display: flex;
        justify-content: space-between;
        align-items: center;
      ">
        <div>
          <div style="font-weight: bold; color: #4CAF50; font-size: 16px;">${baseAlly.name}</div>
          <div style="color: #aaa; font-size: 12px;">${baseAlly.type} - ${baseAlly.game}</div>
          <div style="color: #fff; margin-top: 5px;">
            HP: ${ally.currentHp}/${baseAlly.hp}
          </div>
          <div style="color: #888; font-size: 11px; margin-top: 5px;">
            Dice: ${baseAlly.dice.map(d => d.raw).slice(0, 3).join(', ')}...
          </div>
        </div>
        <button onclick="dismissAlly('${baseAlly.name}'); showAlliesPanel();" style="
          padding: 8px 16px;
          background: #d32f2f;
          border: none;
          border-radius: 6px;
          color: white;
          cursor: pointer;
        ">Dismiss</button>
      </div>
    `;
  }).join('') : '<p style="color: #666; text-align: center;">No active allies</p>';

  createGameModal(`
    <div style="padding: 20px; max-width: 600px;">
      <h2 style="color: #4CAF50; margin-bottom: 20px; text-align: center;">Allies</h2>

      <h3 style="color: #aaa; margin-bottom: 10px;">Active Allies (${allies.length})</h3>
      <div style="display: flex; flex-direction: column; gap: 10px; margin-bottom: 30px;">
        ${activeAlliesHtml}
      </div>

      <div style="text-align: center;">
        <button onclick="closeGameModal()" style="
          padding: 12px 30px;
          background: #444;
          border: 2px solid #666;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
        ">Close</button>
      </div>
    </div>
  `);
}

/**
 * Test function to recruit a random ally
 */
function recruitRandomAlly() {
  if (!ALLIES_DATA || ALLIES_DATA.length === 0) return false;
  const randomAlly = ALLIES_DATA[Math.floor(Math.random() * ALLIES_DATA.length)];
  return recruitAlly(randomAlly.name);
}

// Make ally functions globally available
window.recruitAlly = recruitAlly;
window.dismissAlly = dismissAlly;
window.updateAllyHp = updateAllyHp;
window.healAlly = healAlly;
window.showAlliesPanel = showAlliesPanel;
window.recruitRandomAlly = recruitRandomAlly;

// Combat-specific tooltip functions for item hover
window.showCombatItemTooltip = function showCombatItemTooltip(event, itemIndex) {
  const tooltip = document.getElementById('combat-item-tooltip');
  const tooltipContent = document.getElementById('combat-tooltip-content');

  if (!tooltip || !tooltipContent || itemIndex >= inventory.length) {
    return;
  }

  const item = inventory[itemIndex];

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
  const isUsable = item.type === 'Usable';
  const canUse = isUsable && typeof canUseItem === 'function' && canUseItem(item);

  // For Weapon items, find the card they add to the deck and show it
  const isWeapon = (item.type || '').toLowerCase() === 'weapon';
  let weaponCardHTML = '';
  if (isWeapon && typeof cards !== 'undefined') {
    const wCard = cards.find(c => c.name === item.name);
    if (wCard) {
      const wColor = wCard.type === 'Attack' ? '#e74c3c' : wCard.type === 'Skill' ? '#3498db' : wCard.type === 'Power' ? '#9b59b6' : '#aaa';
      const wImg   = wCard.imageUrl || '';
      weaponCardHTML = `
        <div style="margin-top:10px;padding-top:10px;border-top:1px solid #444;">
          <div style="color:#aaa;font-size:11px;margin-bottom:6px;">Card added to deck:</div>
          <div style="display:flex;gap:10px;align-items:flex-start;">
            ${wImg ? `<img src="${wImg}" alt="${wCard.name}" style="width:52px;height:52px;object-fit:contain;border:2px solid ${wColor};border-radius:6px;flex-shrink:0;" onerror="this.style.display='none'">` : ''}
            <div>
              <div style="font-weight:bold;color:white;font-size:13px;">${wCard.name}${wCard.upgraded ? ' <span style="color:#4CAF50">+</span>' : ''}</div>
              <div style="color:${wColor};font-size:11px;margin:2px 0;">${wCard.type} · ⚡${wCard.cost}</div>
              <div style="color:#ccc;font-size:11px;line-height:1.4;">${wCard.description || ''}</div>
            </div>
          </div>
        </div>`;
    }
  }

  tooltipContent.innerHTML = `
    <div style="min-width: 220px;">
      <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 16px; border-bottom: 2px solid ${rarityColor}; padding-bottom: 6px;">
        ${item.name}
      </h4>
      <div style="margin-bottom: 8px;">
        <span style="color: ${rarityColor}; font-weight: bold; font-size: 13px;">${item.rarity || 'Common'}</span>
        <span style="color: #666; margin: 0 6px;">•</span>
        <span style="color: #aaa; font-size: 13px;">${item.type || 'Item'}</span>
      </div>
      <p style="margin: 8px 0; color: #ccc; font-size: 13px; line-height: 1.4;">${item.description || 'No description'}</p>
      ${weaponCardHTML}
      ${isUsable ? `
        <button ${canUse ? `onclick="useCombatItem(${itemIndex}); hideCombatItemTooltip();"` : 'disabled'} style="
          width: 100%;
          padding: 8px;
          margin-top: 8px;
          background: ${canUse ? 'linear-gradient(145deg, #4CAF50, #2E7D32)' : 'linear-gradient(145deg, #555, #444)'};
          border: 2px solid ${canUse ? '#2E7D32' : '#666'};
          border-radius: 6px;
          color: ${canUse ? 'white' : '#888'};
          font-weight: bold;
          font-size: 14px;
          cursor: ${canUse ? 'pointer' : 'not-allowed'};
          opacity: ${canUse ? '1' : '0.5'};
          transition: all 0.2s;
        ">
          Use
        </button>
      ` : ''}
    </div>
  `;

  tooltip.style.display = 'block';
  tooltip.style.visibility = 'visible';
  tooltip.style.opacity = '1';

  // Position tooltip near cursor
  updateCombatTooltipPosition(event);

  // Update position as mouse moves
  tooltip._mouseMoveHandler = (e) => updateCombatTooltipPosition(e);
  document.addEventListener('mousemove', tooltip._mouseMoveHandler);
}

window.hideCombatItemTooltip = function hideCombatItemTooltip() {
  const tooltip = document.getElementById('combat-item-tooltip');
  if (!tooltip) return;

  tooltip.style.display = 'none';

  // Remove mouse move listener
  if (tooltip._mouseMoveHandler) {
    document.removeEventListener('mousemove', tooltip._mouseMoveHandler);
    tooltip._mouseMoveHandler = null;
  }
}

window.updateCombatTooltipPosition = function updateCombatTooltipPosition(event) {
  const tooltip = document.getElementById('combat-item-tooltip');
  if (!tooltip) return;

  const offset = 15;
  let x = event.clientX + offset;
  let y = event.clientY + offset;

  // Keep tooltip on screen
  const tooltipRect = tooltip.getBoundingClientRect();
  if (x + tooltipRect.width > window.innerWidth) {
    x = event.clientX - tooltipRect.width - offset;
  }
  if (y + tooltipRect.height > window.innerHeight) {
    y = event.clientX - tooltipRect.height - offset;
  }

  tooltip.style.left = x + 'px';
  tooltip.style.top = y + 'px';
}

window.useCombatItem = function useCombatItem(itemIndex) {
  if (itemIndex >= inventory.length) return;

  const item = inventory[itemIndex];

  // Use the item through the existing system
  if (typeof useItem === 'function') {
    useItem(itemIndex);

    // Refresh items bar (old combat system)
    const populateFunc = window.populateItemsBar || populateItemsBar;
    if (typeof populateFunc === 'function') {
      populateFunc();
    }

    // Refresh items bar (new combat system)
    if (window.CombatUI && typeof window.CombatUI.updateItemsBar === 'function') {
      window.CombatUI.updateItemsBar();
    }

    // Update combat UI
    if (typeof updateCombatUI === 'function') {
      updateCombatUI();
    }

    // Full re-render so item effects (HP, statuses, etc.) appear immediately
    if (window.CombatUI && typeof window.CombatUI.updateCombatDisplay === 'function') {
      window.CombatUI.updateCombatDisplay();
    }
  }
}

if (typeof window !== 'undefined') {
  window.recruitAlly       = recruitAlly;
  window.dismissAlly       = dismissAlly;
  window.updateAllyHp      = updateAllyHp;
  window.healAlly          = healAlly;
  window.showAlliesPanel   = showAlliesPanel;
  window.recruitRandomAlly = recruitRandomAlly;
}
