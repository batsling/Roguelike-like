/**
 * CARDS.JS - Card System
 *
 * Responsibilities:
 * - Card reward modal (post-combat, offer 3 cards)
 * - Deck management (view, upgrade, remove)
 * - Weapon acquisition → adds weapon card to deck
 * - Status cards (pigments) cleared after combat
 * - Hand limit: 10 cards
 *
 * Card rarities: Starter, Common, Uncommon, Rare
 * Starter cards are excluded from the reward pool.
 * Status cards (type = 'Status') cannot be upgraded and are removed after combat.
 */

console.log('✅ CARDS.JS loaded');

const HAND_SIZE_LIMIT = 10;

// ===== RARITY WEIGHTS FOR CARD REWARDS =====
// Uses the same luck system as items (calculateRarityWeights / selectRandomRarity)
// Starter cards are never offered as rewards.
// Rarity mapping from card data → luck system key
const CARD_RARITY_MAP = {
  'Common': 'common',
  'Uncommon': 'uncommon',
  'Rare': 'rare'
};

/**
 * Select 3 random cards from the reward pool (non-Starter, non-Status).
 * Weighted by rarity using the luck system.
 * @returns {Array} Array of up to 3 card objects
 */
function selectCardRewards() {
  if (!cards || cards.length === 0) return [];

  const pool = cards.filter(c =>
    c.rarity !== 'Starter' && !c.isStatusCard && c.rarity in CARD_RARITY_MAP
  );
  if (pool.length === 0) return [];

  const chosen = [];
  const maxAttempts = 100;

  for (let i = 0; i < 3; i++) {
    let attempts = 0;
    let selected = null;

    while (attempts < maxAttempts) {
      const rarityKey = selectRandomRarity();
      // Map luck system rarity keys back to card rarity labels
      const rarityLabel = Object.entries(CARD_RARITY_MAP).find(([_, k]) => k === rarityKey)?.[0];
      const rarityPool = rarityLabel ? pool.filter(c => c.rarity === rarityLabel) : [];
      const candidates = rarityPool.length > 0 ? rarityPool : pool;
      const candidate = candidates[Math.floor(Math.random() * candidates.length)];

      if (!chosen.find(c => c.name === candidate.name)) {
        selected = candidate;
        break;
      }
      attempts++;
    }

    if (selected) chosen.push(selected);
  }

  return chosen;
}

/**
 * Add a card to the player's deck.
 * @param {Object} card - Card object from CARDS_DATA
 */
function addCardToDeck(card) {
  if (!gameState.deck) gameState.deck = [];
  gameState.deck.push({ ...card, upgraded: false });
  if (typeof createNotification === 'function') {
    createNotification(`${card.name} added to deck!`, '#9b59b6', '🃏');
  }
  saveCurrentGame();
}

/**
 * Remove a card from the player's deck by index.
 * @param {number} index - Index in gameState.deck
 */
function removeCardFromDeck(index) {
  if (!gameState.deck || index < 0 || index >= gameState.deck.length) return;
  const card = gameState.deck[index];
  gameState.deck.splice(index, 1);
  if (typeof createNotification === 'function') {
    createNotification(`${card.name} removed from deck.`, '#888', '🗑️');
  }
  saveCurrentGame();
}

/**
 * Upgrade a card in the player's deck by index.
 * Status cards and cards without upgrade data cannot be upgraded.
 * @param {number} index - Index in gameState.deck
 * @returns {boolean} True if upgrade succeeded
 */
function upgradeCardInDeck(index) {
  if (!gameState.deck || index < 0 || index >= gameState.deck.length) return false;
  const card = gameState.deck[index];

  if (card.isStatusCard) {
    if (typeof createNotification === 'function') {
      createNotification('Status cards cannot be upgraded.', '#e74c3c', '❌');
    }
    return false;
  }
  if (!card.canUpgrade || card.upgraded) {
    if (typeof createNotification === 'function') {
      createNotification('This card cannot be upgraded further.', '#888', '❌');
    }
    return false;
  }

  card.upgraded = true;
  if (card.upgradedDescription) card.description = card.upgradedDescription;
  if (card.upgradedCost !== null && card.upgradedCost !== undefined) card.cost = card.upgradedCost;

  if (typeof createNotification === 'function') {
    createNotification(`${card.name} upgraded!`, '#ff9800', '⬆️');
  }
  saveCurrentGame();
  return true;
}

/**
 * When a weapon item is acquired, find the matching card and add it to the deck.
 * @param {string} weaponName - Name of the weapon
 */
function addWeaponCardToDeck(weaponName) {
  if (!cards) return;
  const card = cards.find(c => c.name === weaponName && c.tags && c.tags.includes('weapon'));
  if (card) {
    addCardToDeck(card);
  }
}

/**
 * Remove all Status cards (pigments, etc.) from deck after combat ends.
 */
function clearStatusCardsAfterCombat() {
  if (!gameState.deck) return;
  const before = gameState.deck.length;
  gameState.deck = gameState.deck.filter(c => !c.isStatusCard);
  const removed = before - gameState.deck.length;
  if (removed > 0) {
    addLog && addLog(`${removed} status card(s) removed from deck after combat.`, 'info');
  }
}

// ===== CARD REWARD MODAL =====

/**
 * Show the post-combat card reward modal.
 * Offers 3 random cards; player picks one to add to deck.
 */
function showCardRewardModal() {
  const rewardCards = selectCardRewards();
  if (rewardCards.length === 0) {
    if (typeof createNotification === 'function') {
      createNotification('No cards available!', '#888', '🃏');
    }
    return;
  }

  const getRarityColor = (rarity) => {
    switch (rarity) {
      case 'Rare': return '#9b59b6';
      case 'Uncommon': return '#4CAF50';
      case 'Common': return '#aaa';
      default: return '#888';
    }
  };

  const cardsHTML = rewardCards.map((card, i) => {
    const color = getRarityColor(card.rarity);
    const imgSrc = card.imageUrl || 'images/cards/default.png';
    return `
      <div class="card-reward-option" data-index="${i}" style="
        background: #2d2d2d;
        border: 3px solid ${color};
        border-radius: 12px;
        padding: 20px;
        cursor: pointer;
        transition: transform 0.2s, box-shadow 0.2s;
        display: flex;
        flex-direction: column;
        align-items: center;
        min-width: 160px;
        max-width: 200px;
      " onmouseover="this.style.transform='scale(1.05)'; this.style.boxShadow='0 0 20px ${color}44'"
         onmouseout="this.style.transform='scale(1)'; this.style.boxShadow='none'">
        <div style="
          width: 80px; height: 80px;
          display: flex; align-items: center; justify-content: center;
          background: rgba(0,0,0,0.3); border-radius: 8px;
          border: 2px solid ${color}; margin-bottom: 12px;
        ">
          <img src="${imgSrc}" alt="${card.name}" style="max-width:70px;max-height:70px;object-fit:contain;"
               onerror="this.style.display='none'; this.parentElement.innerHTML='<span style=font-size:32px>🃏</span>'">
        </div>
        <div style="font-weight:bold;font-size:15px;color:white;text-align:center;margin-bottom:4px;">${card.name}</div>
        <div style="color:${color};font-size:12px;text-transform:capitalize;margin-bottom:6px;">${card.rarity} · ${card.type}</div>
        <div style="font-size:12px;color:#ddd;text-align:center;margin-bottom:10px;min-height:50px;">${card.description}</div>
        <div style="color:#ffd700;font-size:13px;font-weight:bold;">Cost: ${card.cost} Energy</div>
        ${card.canUpgrade ? '<div style="color:#4CAF50;font-size:11px;margin-top:4px;">✓ Upgradeable</div>' : ''}
      </div>
    `;
  }).join('');

  createGameModal(`
    <div style="text-align:center;padding:20px;max-width:700px;margin:0 auto;">
      <h2 style="color:#9b59b6;margin-top:0;">🃏 Choose a Card</h2>
      <p style="color:#aaa;margin-bottom:20px;">Select one card to add to your deck</p>
      <div style="display:flex;gap:20px;justify-content:center;flex-wrap:wrap;" id="card-reward-grid">
        ${cardsHTML}
      </div>
      <button onclick="closeGameModal()" style="
        margin-top:25px;padding:12px 30px;
        background:#555;border:none;border-radius:8px;
        color:white;cursor:pointer;font-size:14px;font-weight:bold;
      ">Skip</button>
    </div>
  `);

  // Bind click handlers
  document.querySelectorAll('.card-reward-option').forEach(el => {
    el.onclick = () => {
      const idx = parseInt(el.dataset.index);
      if (idx >= 0 && idx < rewardCards.length) {
        addCardToDeck(rewardCards[idx]);
        closeGameModal();
      }
    };
  });
}

// ===== DECK VIEWER MODAL =====

/**
 * Show the player's current deck.
 * Accessible from the inventory/UI.
 */
function showDeckModal() {
  if (!gameState.deck || gameState.deck.length === 0) {
    createGameModal(`
      <div style="text-align:center;padding:30px;">
        <h2 style="color:#9b59b6;">🃏 Your Deck</h2>
        <p style="color:#aaa;">Your deck is empty. Win combats or find weapons to add cards!</p>
        <button onclick="closeGameModal()" style="padding:12px 30px;background:#555;border:none;border-radius:8px;color:white;cursor:pointer;font-weight:bold;">Close</button>
      </div>
    `);
    return;
  }

  const getRarityColor = (rarity) => {
    switch (rarity) {
      case 'Rare': return '#9b59b6';
      case 'Uncommon': return '#4CAF50';
      case 'Common': return '#aaa';
      case 'Starter': return '#888';
      default: return '#666';
    }
  };

  const deckHTML = gameState.deck.map((card, i) => {
    const color = getRarityColor(card.rarity);
    const imgSrc = card.imageUrl || 'images/cards/default.png';
    return `
      <div style="
        background:#2d2d2d;border:2px solid ${color};border-radius:8px;
        padding:12px;display:flex;flex-direction:column;align-items:center;
        min-width:130px;max-width:160px;
      ">
        <img src="${imgSrc}" alt="${card.name}" style="width:60px;height:60px;object-fit:contain;margin-bottom:8px;"
             onerror="this.style.display='none'">
        <div style="font-weight:bold;font-size:13px;color:white;text-align:center;margin-bottom:3px;">${card.name}${card.upgraded ? ' +' : ''}</div>
        <div style="color:${color};font-size:11px;margin-bottom:4px;">${card.rarity} · ${card.type}</div>
        <div style="font-size:11px;color:#ccc;text-align:center;margin-bottom:6px;">${card.description}</div>
        <div style="color:#ffd700;font-size:11px;">Cost: ${card.cost}</div>
      </div>
    `;
  }).join('');

  createGameModal(`
    <div style="padding:20px;max-width:900px;margin:0 auto;">
      <h2 style="color:#9b59b6;text-align:center;margin-top:0;">🃏 Your Deck (${gameState.deck.length} cards)</h2>
      <div style="display:flex;gap:12px;flex-wrap:wrap;justify-content:center;">
        ${deckHTML}
      </div>
      <div style="text-align:center;margin-top:20px;">
        <button onclick="closeGameModal()" style="padding:12px 30px;background:#555;border:none;border-radius:8px;color:white;cursor:pointer;font-weight:bold;">Close</button>
      </div>
    </div>
  `);
}

// Hook into item acquisition to detect weapons → add card
const _originalAcquireItem = window.acquireItem;
window.acquireItem = function(item) {
  if (typeof _originalAcquireItem === 'function') {
    _originalAcquireItem(item);
  }
  // If item is a weapon (has 'weapon' tag or type), add matching card
  const isWeapon = (item.tags && item.tags.includes('weapon')) ||
                   (item.type && item.type.toLowerCase() === 'weapon');
  if (isWeapon) {
    addWeaponCardToDeck(item.name);
  }
};

// Hook into combat end to clear status cards
const _originalEndCombat = window.CombatEngine && window.CombatEngine.endCombat;
if (window.CombatEngine) {
  const origEnd = window.CombatEngine.endCombat;
  window.CombatEngine.endCombat = function(victory) {
    if (typeof origEnd === 'function') origEnd(victory);
    clearStatusCardsAfterCombat();
  };
}

// Export
window.showCardRewardModal = showCardRewardModal;
window.showDeckModal = showDeckModal;
window.addCardToDeck = addCardToDeck;
window.removeCardFromDeck = removeCardFromDeck;
window.upgradeCardInDeck = upgradeCardInDeck;
window.addWeaponCardToDeck = addWeaponCardToDeck;
window.clearStatusCardsAfterCombat = clearStatusCardsAfterCombat;
window.HAND_SIZE_LIMIT = HAND_SIZE_LIMIT;
