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
 * @param {string|null} tagFilter - If provided, only cards with this tag are eligible.
 * @returns {Array} Array of up to 3 card objects
 */
function selectCardRewards(tagFilter = null) {
  if (!cards || cards.length === 0) return [];

  let pool = cards.filter(c =>
    c.rarity !== 'Starter' && !c.isStatusCard && !c.isCurse && (c.type || '').toLowerCase() !== 'curse' && c.rarity in CARD_RARITY_MAP
  );

  if (tagFilter) {
    const filtered = pool.filter(c => Array.isArray(c.tags) && c.tags.includes(tagFilter));
    // Fall back to full pool if tag yields nothing (e.g. tag typo)
    if (filtered.length > 0) pool = filtered;
  }

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

  // Egg items: auto-upgrade the card if it matches the egg's type
  const inv = typeof inventory !== 'undefined' ? inventory : [];
  const newIndex = gameState.deck.length - 1;
  const cardType = (card.type || '').toLowerCase();

  if (!card.isStatusCard && !card.upgraded && card.upgradedDescription) {
    const shouldUpgrade =
      (cardType === 'attack' && inv.some(i => i.name === 'Molten Egg')) ||
      (cardType === 'skill'  && inv.some(i => i.name === 'Toxic Egg'))  ||
      (cardType === 'power'  && inv.some(i => i.name === 'Frozen Egg'));

    if (shouldUpgrade) {
      const addedCard = gameState.deck[newIndex];
      addedCard.upgraded = true;
      addedCard.description = card.upgradedDescription;
      if (card.upgradedCost !== null && card.upgradedCost !== undefined) {
        addedCard.cost = card.upgradedCost;
      }
      if (typeof createNotification === 'function') {
        createNotification(`${card.name} added to deck (upgraded by Egg)!`, '#ff9800', '🥚');
      }
      saveCurrentGame();
      return;
    }
  }

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
 * Cards with sequentialUpgrade:true can be upgraded unlimited times,
 * adding damage each upgrade (parsed from "Sequential Upgrade Dmg +N" in description).
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

  // Sequential upgrade: unlimited upgrades, each adds damage based on description
  if (card.sequentialUpgrade) {
    const level = card._seqLevel || 0;
    // Apply cost change on first upgrade only
    if (level === 0 && card.upgradedCost !== null && card.upgradedCost !== undefined) {
      card.cost = card.upgradedCost;
    }
    // Parse upgrade bonus from description (e.g. "Sequential Upgrade Dmg +3" → 3)
    const seqMatch = card.description.match(/Sequential Upgrade Dmg \+(\d+)/i);
    const dmgBonus = seqMatch ? parseInt(seqMatch[1]) : 3;
    // Update the damage number in description
    card.description = card.description.replace(/Deal (\d+) Dmg/i, (_, n) => `Deal ${parseInt(n) + dmgBonus} Dmg`);
    card._seqLevel = level + 1;
    card.upgraded = true;
    if (typeof createNotification === 'function') {
      createNotification(`${card.name} upgraded! (Lv ${card._seqLevel})`, '#ff9800', '⬆️');
    }
    saveCurrentGame();
    return true;
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

  // Weapon cards: upgrade their weapon item's level so the next verification effect is stronger
  if (card.tags && card.tags.includes('weapon')) {
    const weaponItem = (gameState.inventory || []).find(i => i.name === card.name && i.type === 'Weapon');
    if (weaponItem) {
      weaponItem.level = (weaponItem.level || 1) + 1;
      if (typeof createNotification === 'function') {
        createNotification(`${card.name} upgraded! Weapon effect now Lv${weaponItem.level}`, '#ff9800', '⬆️');
      }
      saveCurrentGame();
      return true;
    }
  }

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

// showCardRewardModal is defined in main.js (loaded after this file) and
// registered as window.showCardRewardModal there. Do not redefine it here.

// ===== DECK VIEWER MODAL =====

/**
 * Show the player's current deck.
 * Accessible from the inventory/UI.
 */
function showDeckModal() {
  const getRarityColor = (rarity) => {
    switch (rarity) {
      case 'Rare': return '#9b59b6';
      case 'Uncommon': return '#4CAF50';
      case 'Common': return '#aaa';
      case 'Starter': return '#888';
      default: return '#666';
    }
  };

  function cardHtml(card, label) {
    const color = getRarityColor(card.rarity);
    const imgSrc = card.imageUrl || 'images/cards/default.png';
    return `
      <div style="
        background:#2d2d2d;border:2px solid ${color};border-radius:8px;
        padding:12px;display:flex;flex-direction:column;align-items:center;
        min-width:130px;max-width:160px;position:relative;
      ">
        ${label ? `<div style="position:absolute;top:4px;right:4px;background:${color};color:#000;font-size:9px;padding:2px 5px;border-radius:4px;font-weight:bold;">${label}</div>` : ''}
        <img src="${imgSrc}" alt="${card.name}" style="width:60px;height:60px;object-fit:contain;margin-bottom:8px;"
             onerror="this.style.display='none'">
        <div style="font-weight:bold;font-size:13px;color:white;text-align:center;margin-bottom:3px;">${card.name}${card.upgraded ? ' +' : ''}</div>
        <div style="color:${color};font-size:11px;margin-bottom:4px;">${card.rarity || 'Starter'} · ${card.type || ''}</div>
        <div style="font-size:11px;color:#ccc;text-align:center;margin-bottom:6px;">${card.description || ''}</div>
        <div style="color:#ffd700;font-size:11px;">Cost: ${card.cost !== undefined ? card.cost : '?'}</div>
      </div>
    `;
  }

  // Build starting deck from character data
  const charKey = (typeof selectedCharacter !== 'undefined' && selectedCharacter)
               ? selectedCharacter
               : ((typeof gameState !== 'undefined' && gameState && gameState.character)
                 ? gameState.character
                 : null);
  const charData = (charKey && typeof PLAYER_CHARACTERS !== 'undefined') ? PLAYER_CHARACTERS[charKey] : null;
  const startingEntries = (charData && charData.startingDeck) ? charData.startingDeck : [];

  const upgradedStarting = (typeof gameState !== 'undefined' && gameState && gameState.upgradedStartingCards) || {};
  const startingCards = [];
  for (const entry of startingEntries) {
    const template = typeof CARDS_DATA !== 'undefined'
      ? CARDS_DATA.find(c => c.name === entry.cardName || c.name.toLowerCase() === entry.cardName.toLowerCase())
      : null;
    if (template) {
      const total = entry.count || 1;
      const val = upgradedStarting[entry.cardName];
      // Support both legacy boolean (upgrade all) and new count-based tracking
      const upgradedCount = typeof val === 'number' ? Math.min(val, total) : (val ? total : 0);
      const upgradedCard = upgradedCount > 0 ? {
        ...template,
        upgraded: true,
        description: template.upgradedDescription || template.description,
        cost: (template.upgradedCost !== null && template.upgradedCost !== undefined)
          ? template.upgradedCost : template.cost
      } : null;
      for (let i = 0; i < total; i++) {
        startingCards.push(i < upgradedCount ? upgradedCard : template);
      }
    } else {
      // Card template not found — show a placeholder
      for (let i = 0; i < (entry.count || 1); i++) {
        startingCards.push({ name: entry.cardName, rarity: 'Starter', type: '', description: '', cost: '?' });
      }
    }
  }

  // Collected cards
  const collectedCards = (typeof gameState !== 'undefined' && gameState && gameState.deck) ? gameState.deck : [];

  const totalCount = startingCards.length + collectedCards.length;
  const startingHTML = startingCards.map(c => cardHtml(c, 'Starting')).join('');
  const collectedHTML = collectedCards.map(c => cardHtml(c, 'Acquired')).join('');

  createGameModal(`
    <div style="padding:20px;max-width:1100px;margin:0 auto;">
      <h2 style="color:#9b59b6;text-align:center;margin-top:0;">🃏 Your Deck (${totalCount} cards)</h2>
      ${startingHTML ? `
        <h3 style="color:#888;margin:12px 0 8px;">Starting Deck (${startingCards.length})</h3>
        <div style="display:flex;gap:12px;flex-wrap:wrap;margin-bottom:16px;">${startingHTML}</div>
      ` : ''}
      ${collectedHTML ? `
        <h3 style="color:#9b59b6;margin:12px 0 8px;">Acquired Cards (${collectedCards.length})</h3>
        <div style="display:flex;gap:12px;flex-wrap:wrap;">${collectedHTML}</div>
      ` : ''}
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

/**
 * Pigment Rich hook — add a random pigment/status card to the player's combat hand.
 * Called by combat-engine when an enemy with pigment_rich status takes damage.
 */
function addRandomPigmentToHand() {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;

  const pigments = (typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [])
    .filter(c => c.isStatusCard);
  if (pigments.length === 0) return;

  const card = { ...pigments[Math.floor(Math.random() * pigments.length)] };
  combat.hand.push(card);

  if (typeof window.updateCombatDisplay === 'function') window.updateCombatDisplay();
}

/**
 * Add a random pigment/status card to the player's discard pile.
 * It will be shuffled into the draw pile on the next reshuffle.
 * Called by combat-engine for enemies that add pigments to the deck.
 */
function addRandomPigmentToDeck() {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;

  const pigments = (typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [])
    .filter(c => c.isStatusCard);
  if (pigments.length === 0) return;

  const card = { ...pigments[Math.floor(Math.random() * pigments.length)] };
  combat.discardPile.push(card);

  if (typeof window.updateCombatDisplay === 'function') window.updateCombatDisplay();
}

// Export
window.showCardRewardModal = showCardRewardModal;
window.showDeckModal = showDeckModal;
window.addCardToDeck = addCardToDeck;
window.removeCardFromDeck = removeCardFromDeck;
window.upgradeCardInDeck = upgradeCardInDeck;
window.addWeaponCardToDeck = addWeaponCardToDeck;
window.clearStatusCardsAfterCombat = clearStatusCardsAfterCombat;
window.addRandomPigmentToHand = addRandomPigmentToHand;
window.addRandomPigmentToDeck = addRandomPigmentToDeck;
window.HAND_SIZE_LIMIT = HAND_SIZE_LIMIT;
