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
  if (!card) { console.error('[addCardToDeck] called with null/undefined card'); return; }
  if (!gameState.deck) gameState.deck = [];
  const cardCopy = { ...card, upgraded: false };
  // Dice cards get a stable UID so item slots can reference them
  if ((card.type || '').toLowerCase() === 'dice') {
    cardCopy._dieUid = `die_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  }
  gameState.deck.push(cardCopy);

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

  // Learn spell on acquire (for Dice cards with a learn property or "Learn X" in description)
  learnSpellFromCard(card);

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

  // Return any slotted item back to inventory when the die is removed
  if (card._dieUid && gameState.diceSlots && gameState.diceSlots[card._dieUid]) {
    const slottedItem = gameState.diceSlots[card._dieUid];
    StateMutator.addItem(slottedItem);
    delete gameState.diceSlots[card._dieUid];
    if (typeof createNotification === 'function') {
      createNotification(`${slottedItem.name} returned to inventory.`, '#888', '📦');
    }
  }

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
  if (card.upgradedCost !== null && card.upgradedCost !== undefined) card.cost = card.upgradedCost;

  // Weapon cards: bump weapon level and update the Trigger indicator in the live description.
  // Weapon cards: bump level only. Do NOT replace description — accumulated bonus values must persist.
  // The verification screen reads weapon.level to show the correct (+1/+2) reward automatically.
  if (card.tags && card.tags.includes('weapon')) {
    const weaponItem = (gameState.inventory || []).find(i => i.name === card.name && i.type === 'Weapon');
    if (weaponItem) {
      weaponItem.level = (weaponItem.level || 1) + 1;
      if (typeof createNotification === 'function') {
        createNotification(`${card.name} upgraded! Verification reward is now Lv${weaponItem.level}`, '#ff9800', '⬆️');
      }
      saveCurrentGame();
      return true;
    }
  }

  // Non-weapon cards: apply the upgraded description normally
  if (card.upgradedDescription) card.description = card.upgradedDescription;

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

// ============================================================
// Card-reward modal, victory screen, spell-learn helper
// (Phase 3 extraction from main.js)
// ============================================================

function _doLearnSpell(card) {
  if (!card) return;
  let spellName = card.learn;
  if (!spellName && card.description) {
    const m = card.description.match(/\bLearn[:\s]+([A-Za-z][A-Za-z\s']*?)(?:[,.]|$)/i);
    if (m) spellName = m[1].trim();
  }
  if (!spellName) return;
  if (typeof SPELLS_DATA === 'undefined' || !Array.isArray(SPELLS_DATA)) {
    console.warn('[_doLearnSpell] SPELLS_DATA not available');
    return;
  }
  const spellDef = SPELLS_DATA.find(s => s.name === spellName);
  if (!spellDef) { console.warn('[_doLearnSpell] spell not in SPELLS_DATA:', spellName); return; }
  if (!gameState.spells) gameState.spells = [];
  if (gameState.spells.some(s => s.name === spellName)) return; // already known
  gameState.spells.push({ ...spellDef });
  window.playerSpells = gameState.spells;
  const _cs = window.CombatEngine && window.CombatEngine.getCombatState && window.CombatEngine.getCombatState();
  if (_cs && !(_cs.spells || []).some(s => s.name === spellName)) {
    _cs.spells = _cs.spells || [];
    _cs.spells.push({ ...spellDef });
  }
  if (typeof createNotification === 'function') {
    createNotification(`Learned: ${spellName}!`, '#c09aff', '✨');
  }
  if (typeof saveCurrentGame === 'function') saveCurrentGame();
}

/**
 * STS-style victory screen. Each reward (gold, loot, cards) is its own
 * clickable tile. Clicking gold/loot marks them collected; clicking
 * Card Reward opens the picker and returns here when done.
 * Continue is always available.
 */
function showVictoryScreen(enemyName, goldReward, lootIcon, lootName, lootRarity, difficulty) {
  let goldCollected = false;
  let lootCollected = false;
  let cardsCollected = false;

  const tileBase = 'padding:18px 20px;border-radius:10px;display:flex;flex-direction:column;align-items:center;gap:4px;min-width:130px;text-align:center;';

  function activeTileStyle(color) {
    return `${tileBase}background:rgba(0,0,0,0.35);border:2px solid ${color};cursor:pointer;transition:transform 0.15s,box-shadow 0.15s;`;
  }
  function doneStyle(color) {
    return `${tileBase}background:rgba(0,0,0,0.25);border:2px solid ${color};opacity:0.55;cursor:default;`;
  }

  function buildModal() {
    const goldInner = goldCollected
      ? `<div style="font-size:36px;">✓</div>
         <div style="color:#FFD700;font-weight:bold;font-size:15px;">+${goldReward} Gold</div>
         <div style="color:#888;font-size:11px;margin-top:4px;">Collected</div>`
      : `<div style="font-size:36px;">💰</div>
         <div style="color:#FFD700;font-weight:bold;font-size:15px;">+${goldReward} Gold</div>
         <div style="color:#aaa;font-size:11px;margin-top:4px;">Click to collect</div>`;

    const lootInner = lootName
      ? (lootCollected
        ? `<div style="font-size:36px;">✓</div>
           <div style="color:#c39be0;font-weight:bold;font-size:14px;">${lootName}</div>
           <div style="color:#888;font-size:11px;">${lootRarity}</div>
           <div style="color:#888;font-size:11px;margin-top:4px;">Added to Loot</div>`
        : `<div style="height:56px;display:flex;align-items:center;justify-content:center;">${lootIcon}</div>
           <div style="color:#c39be0;font-weight:bold;font-size:14px;">${lootName}</div>
           <div style="color:#888;font-size:11px;">${lootRarity}</div>
           <div style="color:#aaa;font-size:11px;margin-top:4px;">Click to collect</div>`)
      : '';

    const cardInner = cardsCollected
      ? `<div style="font-size:36px;">✓</div>
         <div style="color:#4CAF50;font-weight:bold;font-size:15px;">Card Collected</div>
         <div style="color:#888;font-size:11px;margin-top:4px;">Done</div>`
      : (() => {
          const deckId = gameState.selectedDeck && gameState.selectedDeck !== 'Random' ? gameState.selectedDeck : null;
          const deckImg = deckId ? `images/decks/${deckId}Deck.png` : null;
          const iconHTML = deckImg
            ? `<img src="${deckImg}" style="width:52px;height:52px;object-fit:contain;" onerror="this.outerHTML='<span style=\\'font-size:36px;\\'>🃏</span>'">`
            : `<span style="font-size:36px;">🃏</span>`;
          return `<div style="height:56px;display:flex;align-items:center;justify-content:center;">${iconHTML}</div>
         <div style="color:#c39be0;font-weight:bold;font-size:15px;">Card Reward</div>
         <div style="color:#aaa;font-size:11px;margin-top:4px;">Click to choose</div>`;
        })();

    createGameModal(`
      <div style="text-align:center;padding:28px 36px;min-width:440px;">
        <h2 style="color:#4CAF50;font-size:34px;margin:0 0 6px 0;">Victory!</h2>
        <div style="color:#bbb;font-size:17px;margin-bottom:22px;">${enemyName} defeated!</div>
        <div style="display:flex;gap:14px;justify-content:center;flex-wrap:wrap;margin-bottom:24px;">
          <div id="victory-gold-tile" style="${goldCollected ? doneStyle('#FFD700') : activeTileStyle('#FFD700')}">
            ${goldInner}
          </div>
          ${lootName ? `<div id="victory-loot-tile" style="${lootCollected ? doneStyle('#9b59b6') : activeTileStyle('#9b59b6')}">
            ${lootInner}
          </div>` : ''}
          <div id="victory-card-tile" style="${cardsCollected ? doneStyle('#9b59b6') : activeTileStyle('#9b59b6')}">
            ${cardInner}
          </div>
        </div>
        <button id="victory-continue-btn" style="
          padding:12px 44px;
          background:linear-gradient(145deg,#4CAF50,#2E7D32);border:none;
          border-radius:8px;color:white;cursor:pointer;
          font-size:15px;font-weight:bold;">Continue →</button>
      </div>
    `);

    attachListeners();
  }

  function attachListeners() {
    const goldTile    = document.getElementById('victory-gold-tile');
    const lootTile    = document.getElementById('victory-loot-tile');
    const cardTile    = document.getElementById('victory-card-tile');
    const continueBtn = document.getElementById('victory-continue-btn');

    if (goldTile && !goldCollected) {
      goldTile.addEventListener('mouseenter', () => { goldTile.style.transform = 'translateY(-4px)'; goldTile.style.boxShadow = '0 6px 20px rgba(255,215,0,0.4)'; });
      goldTile.addEventListener('mouseleave', () => { goldTile.style.transform = ''; goldTile.style.boxShadow = ''; });
      goldTile.addEventListener('click', () => {
        goldCollected = true;
        goldTile.style.cssText = doneStyle('#FFD700');
        goldTile.innerHTML = `<div style="font-size:36px;">✓</div>
          <div style="color:#FFD700;font-weight:bold;font-size:15px;">+${goldReward} Gold</div>
          <div style="color:#888;font-size:11px;margin-top:4px;">Collected</div>`;
      }, { once: true });
    }

    if (lootTile && !lootCollected) {
      lootTile.addEventListener('mouseenter', () => { lootTile.style.transform = 'translateY(-4px)'; lootTile.style.boxShadow = '0 6px 20px rgba(155,89,182,0.5)'; });
      lootTile.addEventListener('mouseleave', () => { lootTile.style.transform = ''; lootTile.style.boxShadow = ''; });
      lootTile.addEventListener('click', () => {
        lootCollected = true;
        lootTile.style.cssText = doneStyle('#9b59b6');
        lootTile.innerHTML = `<div style="font-size:36px;">✓</div>
          <div style="color:#c39be0;font-weight:bold;font-size:14px;">${lootName}</div>
          <div style="color:#888;font-size:11px;">${lootRarity}</div>
          <div style="color:#888;font-size:11px;margin-top:4px;">Added to Loot</div>`;
      }, { once: true });
    }

    if (cardTile && !cardsCollected) {
      cardTile.addEventListener('mouseenter', () => { cardTile.style.transform = 'translateY(-4px)'; cardTile.style.boxShadow = '0 6px 20px rgba(155,89,182,0.5)'; });
      cardTile.addEventListener('mouseleave', () => { cardTile.style.transform = ''; cardTile.style.boxShadow = ''; });
      cardTile.addEventListener('click', () => {
        closeGameModal();
        showCardRewardModal(() => { cardsCollected = true; buildModal(); }, null, difficulty);
      }, { once: true });
    }

    if (continueBtn) {
      continueBtn.addEventListener('click', () => { closeGameModal(); showPostCombatChoiceModal(difficulty); }, { once: true });
    }
  }

  buildModal();
}

function showCardRewardModal(onComplete, tagFilter = null, nodeDifficulty = null) {
  // Derive tagFilter from the run's chosen deck if not explicitly passed
  if (tagFilter === null && typeof gameState !== 'undefined' && gameState.selectedDeck) {
    const deckDef = (typeof AVAILABLE_DECKS !== 'undefined')
      ? AVAILABLE_DECKS.find(d => d.id === gameState.selectedDeck)
      : null;
    if (deckDef && deckDef.tagFilter) tagFilter = deckDef.tagFilter;
  }

  // Upgrade chance based on difficulty: Low=0%, Medium=25%, High=50%
  const _diff = nodeDifficulty || (typeof gameState !== 'undefined' ? gameState.lastDifficultyTier : null) || 'Low';
  const upgradeChance = _diff === 'High' ? 0.5 : _diff === 'Medium' ? 0.25 : 0;

  const rarityColor = (rarity) => {
    switch (rarity) {
      case 'Rare':     return '#9b59b6';
      case 'Uncommon': return '#4CAF50';
      case 'Common':   return '#aaa';
      default:         return '#666';
    }
  };

  // Pick one card with luck-weighted rarity, excluding already-seen names
  function pickOne(exclude) {
    let pool = (typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [])
      .filter(c => c.rarity && c.rarity !== 'Starter' && c.rarity !== 'N/A'
               && (c.type || '').toLowerCase() !== 'training'
               && (c.type || '').toLowerCase() !== 'curse'
               && !c.isTraining
               && !c.isStatusCard
               && !(c.tags && c.tags.includes('weapon'))
               && !exclude.has(c.name));

    if (tagFilter) {
      // Hero-tagged cards are universally available regardless of deck choice,
      // but dice cards (Slice & Dice) are excluded from specific-deck reward pools.
      const heroCards = pool.filter(c => Array.isArray(c.tags) && c.tags.includes('hero')
        && (c.type || '').toLowerCase() !== 'dice');
      const tagged    = pool.filter(c => Array.isArray(c.tags) && c.tags.includes(tagFilter));
      const combined  = [...tagged, ...heroCards.filter(h => !tagged.find(t => t.name === h.name))];
      if (combined.length > 0) pool = combined;
    }

    if (pool.length === 0) return null;

    // Base weights 75/20/5; luck advantage biases the roll toward higher buckets
    const wCommon = 75, wUncommon = 20, wRare = 5, total = 100;
    const roll = rollWithLuckAdvantage() * total;
    let pickedRarity;
    if      (roll < wCommon)              pickedRarity = 'Common';
    else if (roll < wCommon + wUncommon)  pickedRarity = 'Uncommon';
    else                                  pickedRarity = 'Rare';

    let candidates = pool.filter(c => c.rarity === pickedRarity);
    if (candidates.length === 0) candidates = pool;
    const card = candidates[Math.floor(Math.random() * candidates.length)];

    // Roll for pre-upgraded card
    if (card && card.canUpgrade && upgradeChance > 0 && rollWithLuckAdvantage(undefined, false) < upgradeChance) {
      return {
        ...card,
        description: card.upgradedDescription || card.description,
        cost: (card.upgradedCost !== null && card.upgradedCost !== undefined) ? card.upgradedCost : card.cost,
        upgraded: true,
        preUpgraded: true
      };
    }
    return card;
  }

  // Pick 3 + discovery unique cards
  const numCardChoices = 3 + (typeof discovery !== 'undefined' ? discovery : 0);
  const chosen = [];
  const seen   = new Set();
  for (let i = 0; i < numCardChoices; i++) {
    const card = pickOne(seen);
    if (!card) break;
    seen.add(card.name);
    chosen.push(card);
  }

  if (chosen.length === 0) {
    if (onComplete) onComplete();
    return;
  }

  const cardsHTML = chosen.map((card, idx) => {
    const color   = rarityColor(card.rarity);
    const imgSrc  = card.imageUrl || 'images/cards/default.png';
    const upgBtn  = typeof _cardPreviewBtn === 'function' ? _cardPreviewBtn(card) : '';
    const upgradedBg    = card.preUpgraded ? 'background:rgba(46,204,113,0.06);' : '';
    const upgradedBorder = card.preUpgraded ? '#2ecc71' : color;
    const nameLabel = card.preUpgraded
      ? `${card.name} <span style="color:#2ecc71;font-size:14px;font-weight:bold;">+</span>`
      : card.name;
    const upgradedBadge = card.preUpgraded
      ? `<div style="position:absolute;top:8px;left:8px;background:#2ecc71;color:#000;font-size:10px;font-weight:bold;padding:2px 7px;border-radius:4px;">UPGRADED</div>`
      : '';
    return `
      <div class="card-reward-option card-reward-card" data-card-idx="${idx}"
        style="border:3px solid ${upgradedBorder};${upgradedBg}"
        onmouseenter="if(!this.classList.contains('cr-selected')){this.style.transform='translateY(-4px)';this.style.boxShadow='0 8px 24px ${upgradedBorder}44';}"
        onmouseleave="if(!this.classList.contains('cr-selected')){this.style.transform='';this.style.boxShadow='';}">
        ${upgradedBadge}
        ${upgBtn}
        <img src="${imgSrc}" alt="${card.name}"
             style="width:110px;height:110px;object-fit:contain;margin-bottom:10px;"
             onerror="if(this.dataset.t){this.style.display='none';}else{this.dataset.t=1;this.src='images/heroes/'+this.alt+'.png';}">
        <div style="font-weight:bold;font-size:15px;color:white;text-align:center;margin-bottom:4px;">${nameLabel}</div>
        <div style="color:${color};font-size:12px;margin-bottom:6px;">${card.rarity} · ${card.type}</div>
        <div style="font-size:12px;color:${card.preUpgraded ? '#7dffb0' : '#ccc'};text-align:center;margin-bottom:8px;line-height:1.4;">${card.description}</div>
        <div style="color:var(--color-highlight);font-size:13px;font-weight:bold;">Cost: ${card.cost}</div>
      </div>
    `;
  }).join('');

  createGameModal(`
    <div style="text-align:center; padding:20px; max-width:920px;">
      <h2 style="color:#FFD700; margin-top:0; margin-bottom:8px;">🃏 Card Reward</h2>
      <p style="color:#aaa; margin-bottom:20px; font-size:13px;">Click a card to select it, then confirm your choice</p>
      <div style="display:flex; gap:16px; justify-content:center; flex-wrap:wrap;">
        ${cardsHTML}
      </div>
      <div style="margin-top:20px; display:flex; gap:14px; justify-content:center; align-items:center;">
        <button id="card-reward-confirm-btn" disabled style="
          padding:11px 28px; background:#555; border:2px solid #888; border-radius:8px;
          color:#888; cursor:not-allowed; font-size:14px; font-weight:bold; transition:all 0.15s;
        ">✓ Add to Deck</button>
        <button id="card-reward-skip-btn" style="
          padding:11px 28px; background:#333; border:2px solid #555; border-radius:8px;
          color:#aaa; cursor:pointer; font-size:14px; font-weight:bold;
        ">Skip</button>
      </div>
    </div>
  `);

  let selectedCardIdx = null;
  const confirmBtn = document.getElementById('card-reward-confirm-btn');
  const skipBtn    = document.getElementById('card-reward-skip-btn');

  function selectCard(idx) {
    selectedCardIdx = idx;
    document.querySelectorAll('.card-reward-option').forEach(el => {
      const i = parseInt(el.dataset.cardIdx);
      const c = chosen[i];
      const col = rarityColor(c.rarity);
      if (i === idx) {
        el.classList.add('cr-selected');
        el.style.borderColor = '#ffd700';
        el.style.boxShadow   = '0 0 22px #ffd70088';
        el.style.transform   = 'translateY(-6px) scale(1.04)';
      } else {
        el.classList.remove('cr-selected');
        el.style.borderColor = col;
        el.style.boxShadow   = 'none';
        el.style.transform   = '';
      }
    });
    confirmBtn.disabled          = false;
    confirmBtn.style.background  = 'linear-gradient(145deg, #9b59b6, #7d3c98)';
    confirmBtn.style.borderColor = '#9b59b6';
    confirmBtn.style.color       = 'white';
    confirmBtn.style.cursor      = 'pointer';
  }

  document.querySelectorAll('.card-reward-option').forEach(el => {
    el.onclick = () => selectCard(parseInt(el.dataset.cardIdx));
  });

  if (skipBtn) {
    skipBtn.onclick = () => { closeGameModal(); if (onComplete) onComplete(); };
  }

  confirmBtn.onclick = () => {
    if (selectedCardIdx === null) return;
    const card = chosen[selectedCardIdx];
    if (card) {
      const addFn = window.addCardToDeck || (typeof addCardToDeck !== 'undefined' ? addCardToDeck : null);
      if (addFn) {
        addFn(card);
      } else {
        if (!gameState.deck) gameState.deck = [];
        gameState.deck.push({ ...card, upgraded: false });
        saveCurrentGame();
        if (typeof createNotification === 'function') {
          createNotification(`${card.name} added to deck!`, '#9b59b6', '🃏');
        }
      }
      // Inline spell-learning — runs regardless of cached helper availability
      _doLearnSpell(card);
    }
    closeGameModal();
    if (onComplete) onComplete();
  };
}

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
    const upgBtn = typeof _cardPreviewBtn === 'function' ? _cardPreviewBtn(card) : '';
    return `
      <div style="
        background:#2d2d2d;border:2px solid ${color};border-radius:8px;
        padding:12px;display:flex;flex-direction:column;align-items:center;
        min-width:130px;max-width:160px;position:relative;
      ">
        ${upgBtn}
        ${label ? `<div style="position:absolute;top:4px;right:4px;background:${color};color:#000;font-size:9px;padding:2px 5px;border-radius:4px;font-weight:bold;">${label}</div>` : ''}
        ${card.imageUrl ? `<img src="${card.imageUrl}" alt="${card.name}" style="width:60px;height:60px;object-fit:contain;margin-bottom:8px;" onerror="this.style.display='none'">` : ''}
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

  createPanelOverlay(`
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
        <button onclick="closePanelOverlay()" style="padding:12px 30px;background:#555;border:none;border-radius:8px;color:white;cursor:pointer;font-weight:bold;">Close</button>
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
    .filter(c => c.isStatusCard && c.tags && c.tags.includes('pigment'));
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
    .filter(c => c.isStatusCard && c.tags && c.tags.includes('pigment'));
  if (pigments.length === 0) return;

  const card = { ...pigments[Math.floor(Math.random() * pigments.length)] };
  // Insert at a random position in the draw pile so it can be drawn soon
  const insertIdx = Math.floor(Math.random() * (combat.drawPile.length + 1));
  combat.drawPile.splice(insertIdx, 0, card);

  if (typeof window.updateCombatDisplay === 'function') window.updateCombatDisplay();
}

/**
 * Learn the spell tied to a card (if any), adding it to gameState.spells.
 * Safe to call multiple times — skips if spell already learned.
 * @param {Object} card - Card object that may have a learn property or "Learn X" in description
 */
function learnSpellFromCard(card) {
  if (!card) { console.warn('[learnSpellFromCard] called with no card'); return; }
  let spellName = card.learn;
  if (!spellName && card.description) {
    const m = card.description.match(/\bLearn[:\s]+([A-Za-z][A-Za-z\s']*?)(?:[,.]|$)/i);
    if (m) spellName = m[1].trim();
  }
  if (!spellName) return;
  if (typeof SPELLS_DATA === 'undefined') { console.warn('[learnSpellFromCard] SPELLS_DATA not loaded!'); return; }
  const spellDef = SPELLS_DATA.find(s => s.name === spellName);
  if (!spellDef) { console.warn('[learnSpellFromCard] spell not found in SPELLS_DATA:', spellName); return; }
  if (!gameState.spells) gameState.spells = [];
  if (gameState.spells.some(s => s.name === spellName)) return;
  gameState.spells.push({ ...spellDef });
  window.playerSpells = gameState.spells;
  // Inject into active combat if in progress
  const _cs = window.CombatEngine && window.CombatEngine.getCombatState && window.CombatEngine.getCombatState();
  if (_cs && !(_cs.spells || []).some(s => s.name === spellName)) {
    _cs.spells = _cs.spells || [];
    _cs.spells.push({ ...spellDef });
  }
  if (typeof createNotification === 'function') {
    createNotification(`Learned: ${spellName}!`, '#c09aff', '✨');
  }
  if (typeof saveCurrentGame === 'function') saveCurrentGame();
}

// Export
window.showCardRewardModal = showCardRewardModal;
window.showVictoryScreen = showVictoryScreen;
window._doLearnSpell = _doLearnSpell;
window.showDeckModal = showDeckModal;
window.addCardToDeck = addCardToDeck;
window.learnSpellFromCard = learnSpellFromCard;
window.removeCardFromDeck = removeCardFromDeck;
window.upgradeCardInDeck = upgradeCardInDeck;
window.addWeaponCardToDeck = addWeaponCardToDeck;
window.clearStatusCardsAfterCombat = clearStatusCardsAfterCombat;
window.addRandomPigmentToHand = addRandomPigmentToHand;
window.addRandomPigmentToDeck = addRandomPigmentToDeck;
window.HAND_SIZE_LIMIT = HAND_SIZE_LIMIT;
