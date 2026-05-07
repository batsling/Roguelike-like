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


// Keeper's Sack: every 10 gold spent → +1 to a random stat
function _keepersSackCheck(amountSpent) {
  if (!inventory || !inventory.some(i => i.name === "Keeper's Sack")) return;
  const prev = gameState.keepersSackGoldSpent || 0;
  const next = prev + amountSpent;
  const statsBefore = Math.floor(prev / 10);
  const statsAfter  = Math.floor(next / 10);
  gameState.keepersSackGoldSpent = next;
  const gains = statsAfter - statsBefore;
  if (gains <= 0) return;
  const stats = ['strength', 'dexterity', 'intelligence', 'charisma'];
  for (let g = 0; g < gains; g++) {
    const stat = stats[Math.floor(Math.random() * stats.length)];
    if (typeof StateMutator !== 'undefined') StateMutator.modifyStat(stat, 1);
    if (typeof createNotification === 'function') createNotification(`Keeper's Sack: +1 ${stat.charAt(0).toUpperCase() + stat.slice(1)}!`, '#f1c40f', '💰');
  }
}

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

  // Initialize shop service counter if not present
  if (gameState.shopRemovesUsed === undefined) gameState.shopRemovesUsed = 0;

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
  // First reroll is free (no token needed); subsequent rerolls require a reroll token
  const canReroll = gameState.shopRerollCount === 0 || reroll > 0;

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

  // ===== CARD SERVICES PANEL =====
  // Cost scales by 25g per removal done this run (50 → 75 → 100 …)
  const CARD_REMOVE_COST = 50 + (gameState.cardsRemovedThisRun || 0) * 25;

  // Build combined card list: starter cards + collected deck cards (excluding status cards)
  const charKeyCS = gameState.character;
  const charDataCS = charKeyCS && typeof PLAYER_CHARACTERS !== 'undefined' ? PLAYER_CHARACTERS[charKeyCS] : null;
  const startingEntries = (charDataCS && charDataCS.startingDeck) ? charDataCS.startingDeck : [];
  const removedStarting  = gameState.removedStartingCards  || {};

  // Starter cards — one entry per non-removed copy
  const starterCards = [];
  startingEntries.forEach(entry => {
    const template = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === entry.cardName) : null;
    if (!template || template.isStatusCard) return;
    const total = entry.count || 1;
    const removed = removedStarting[entry.cardName] || 0;
    const remaining = total - removed;
    for (let i = 0; i < remaining; i++) {
      starterCards.push({ ...template, _isStarting: true, _startingName: entry.cardName });
    }
  });

  const collectedDeckCards = (gameState.deck || []).filter(c => !c.isStatusCard);
  // allDeckCards: starters first, then collected (indices 0..starterCards.length-1 are starters)
  const allDeckCards = [...starterCards, ...collectedDeckCards];

  const alreadyRemoved = gameState.shopRemovesUsed > 0;

  // Build remove selector — visual card grid so players can see upgrade status
  const _removeRarityColor = r => r === 'Rare' ? '#9b59b6' : r === 'Uncommon' ? '#4CAF50' : r === 'Starter' ? '#888' : '#aaa';
  let removeSelectHTML = '';
  if (allDeckCards.length > 0) {
    removeSelectHTML = `
      <div id="shop-remove-card-grid" style="
        display:flex;flex-wrap:wrap;gap:6px;
        max-height:160px;overflow-y:auto;
        padding:6px;margin-bottom:8px;
        background:#1a1a1a;border:1px solid #444;border-radius:6px;
      ">
        ${allDeckCards.map((c, i) => {
          const rc = _removeRarityColor(c._isStarting ? 'Starter' : c.rarity);
          const label = c._isStarting ? 'Starter' : c.rarity;
          const upgBadge = c.upgraded ? `<span style="color:#4CAF50;font-size:9px;font-weight:bold;"> +</span>` : '';
          return `<div class="shop-remove-card-item" data-remove-idx="${i}" style="
            cursor:pointer;padding:4px 8px;border-radius:5px;
            border:2px solid ${rc};background:rgba(0,0,0,0.4);
            font-size:11px;color:#ddd;white-space:nowrap;
            transition:all 0.12s;user-select:none;
          ">
            ${c.name}${upgBadge}
            <span style="color:${rc};font-size:9px;display:block;margin-top:1px;">${label}</span>
          </div>`;
        }).join('')}
      </div>
      <input type="hidden" id="shop-card-remove-select" value="">
    `;
  } else {
    removeSelectHTML = `<p style="color:#888;font-size:12px;margin:4px 0;">No cards in deck to remove.</p>`;
  }

  const cardServicesHTML = `
    <div style="
      background: #2d2d2d;
      border-radius: 12px;
      border: 3px solid #9b59b6;
      padding: 20px;
      margin-bottom: 20px;
    ">
      <h3 style="color: #9b59b6; margin-top: 0; text-align: center; font-size: 18px;">🃏 Card Services</h3>
      <div>
        <!-- Remove -->
        <div>
          <div style="color:#e74c3c;font-weight:bold;font-size:14px;margin-bottom:8px;">🗑️ Remove a Card (${CARD_REMOVE_COST}💰)</div>
          ${removeSelectHTML}
          <button id="shop-card-remove-btn" style="
            padding: 10px 16px;
            background: ${alreadyRemoved ? '#555' : (gold >= CARD_REMOVE_COST && allDeckCards.length > 0 ? '#e74c3c' : '#555')};
            border: none; border-radius: 6px; color: white;
            cursor: ${alreadyRemoved || allDeckCards.length === 0 || gold < CARD_REMOVE_COST ? 'not-allowed' : 'pointer'};
            font-weight: bold; font-size: 13px; width: 100%;
          " ${alreadyRemoved || allDeckCards.length === 0 || gold < CARD_REMOVE_COST ? 'disabled' : ''}>
            ${alreadyRemoved ? '✓ Removed This Shop' : `Remove (${CARD_REMOVE_COST}💰)`}
          </button>
        </div>
      </div>
    </div>
  `;

  // ===== CARDS FOR SALE =====
  // 4 cards from the player's character card pool + 2 from outside that pool
  if (!gameState.currentShopCards) {
    const allCards = cards ? cards.filter(c => c.rarity !== 'Starter' && !c.isStatusCard && !c.isCurse && (c.type || '').toLowerCase() !== 'curse') : [];

    // Determine character's card pool tag (e.g. 'ironclad', 'silent')
    const charKey = gameState.character;
    const charData = charKey && typeof PLAYER_CHARACTERS !== 'undefined' ? PLAYER_CHARACTERS[charKey] : null;
    const charTag = (charData && charData.levelUpReward && charData.levelUpReward.type === 'card')
      ? charData.levelUpReward.tag : null;

    // Build the set of all known class-specific tags so the outside pool never
    // shows another character's class cards (e.g. Claw/defect for a Silent run).
    const _classTags = new Set(['defect']); // hardcoded extras without a character entry yet
    if (typeof PLAYER_CHARACTERS !== 'undefined') {
      Object.values(PLAYER_CHARACTERS).forEach(ch => {
        if (ch.levelUpReward && ch.levelUpReward.type === 'card' && ch.levelUpReward.tag) {
          _classTags.add(ch.levelUpReward.tag);
        }
      });
    }

    // Hero-tagged cards are always included in any character's pool
    const heroCards = allCards.filter(c => Array.isArray(c.tags) && c.tags.includes('hero'));
    const classPool = charTag ? allCards.filter(c => Array.isArray(c.tags) && c.tags.includes(charTag)) : allCards;
    const inPool    = charTag
      ? [...classPool, ...heroCards.filter(h => !classPool.find(c => c.name === h.name))]
      : allCards;
    // Outside pool: not in character's class AND not in any other class-specific pool AND not hero
    const outPool = charTag
      ? allCards.filter(c => {
          const tags = Array.isArray(c.tags) ? c.tags : [];
          return !tags.includes(charTag) && !tags.some(t => _classTags.has(t)) && !tags.includes('hero');
        })
      : [];

    const pickRandom = (pool, count, alreadyPicked) => {
      const picked = [];
      const attempts = 100;
      for (let i = 0; i < count; i++) {
        let selected = null, tries = 0;
        while (tries < attempts && pool.length > 0) {
          const rarityKey = selectRandomRarity();
          const rarityLabel = { common: 'Common', uncommon: 'Uncommon', rare: 'Rare' }[rarityKey] || 'Common';
          const rarityPool = pool.filter(c => c.rarity === rarityLabel);
          const candidates = rarityPool.length > 0 ? rarityPool : pool;
          const candidate = candidates[Math.floor(Math.random() * candidates.length)];
          if (!alreadyPicked.find(c => c.name === candidate.name) && !picked.find(c => c.name === candidate.name)) {
            selected = candidate;
            break;
          }
          tries++;
        }
        if (selected) picked.push(selected);
      }
      return picked;
    };

    gameState.currentShopCards = [];
    const fromPool = pickRandom(inPool, 4, []);
    gameState.currentShopCards.push(...fromPool);
    if (outPool.length > 0) {
      const fromOutside = pickRandom(outPool, 2, fromPool);
      gameState.currentShopCards.push(...fromOutside);
    } else {
      // No distinct outside pool (character has no tag) — fill remaining from general pool
      const extra = pickRandom(allCards, 2, fromPool);
      gameState.currentShopCards.push(...extra);
    }
  }
  const shopCards = gameState.currentShopCards || [];
  const purchasedCardIndices = gameState.purchasedShopCards || [];

  const cardPriceFor = (c) => {
    const base = c.rarity === 'Rare' ? 50 : c.rarity === 'Uncommon' ? 30 : 15;
    return base + frugalityModifier;
  };

  let shopCardsHTML = '';
  if (shopCards.length > 0) {
    shopCardsHTML = `
      <div style="background:#2d2d2d;border-radius:12px;border:3px solid #9b59b6;padding:20px;margin-bottom:20px;">
        <h3 style="color:#9b59b6;margin-top:0;text-align:center;font-size:18px;">🃏 Cards for Sale</h3>
        <div style="display:grid;grid-template-columns:repeat(${Math.min(shopCards.length, 3)},1fr);gap:12px;">
    `;
    shopCards.forEach((card, idx) => {
      const isPurchased = purchasedCardIndices.includes(idx);
      const price = cardPriceFor(card);
      const color = getRarityColor(card.rarity);
      const upgBtn = typeof _cardPreviewBtn === 'function' ? _cardPreviewBtn(card) : '';
      shopCardsHTML += `
        <div style="
          background:#1e1e2e;border:2px solid ${color};border-radius:10px;
          padding:15px;display:flex;flex-direction:column;align-items:center;
          position:relative;
          ${isPurchased ? 'opacity:0.5;' : ''}
        ">
          ${upgBtn}
          ${card.imageUrl ? `<img src="${card.imageUrl}" alt="${card.name}" style="width:60px;height:60px;object-fit:contain;margin-bottom:8px;" onerror="this.style.display='none'">` : ''}
          <div style="font-weight:bold;font-size:14px;color:white;text-align:center;margin-bottom:3px;">${card.name}</div>
          <div style="color:${color};font-size:11px;margin-bottom:6px;">${card.rarity} · ${card.type}</div>
          <div style="font-size:11px;color:#ccc;text-align:center;margin-bottom:8px;">${card.description}</div>
          <div style="color:#ffd700;font-size:13px;font-weight:bold;margin-bottom:8px;">${price}💰</div>
          <button class="shop-card-buy-btn" data-card-index="${idx}" data-price="${price}" style="
            padding:8px 16px;background:${isPurchased ? '#555' : (gold >= price ? '#9b59b6' : '#555')};
            border:none;border-radius:6px;color:white;
            cursor:${isPurchased || gold < price ? 'not-allowed' : 'pointer'};
            font-weight:bold;font-size:12px;width:100%;
          " ${isPurchased || gold < price ? 'disabled' : ''}>
            ${isPurchased ? '✓ Purchased' : (gold >= price ? 'Buy' : '💰 Too Expensive')}
          </button>
        </div>
      `;
    });
    shopCardsHTML += `</div></div>`;
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
    const basePrice = rarityLower === 'common' ? 8 : rarityLower === 'uncommon' ? 15 : rarityLower === 'rare' ? 25 : 40;
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
    <div style="max-width: 900px; margin: 0 auto;">
      <h2 style="color: gold; margin-top: 0; text-align: center;">🛍️ Mystical Shop 🛍️</h2>
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; padding: 15px; background: #2d2d2d; border-radius: 8px;">
        <div style="color: gold; font-weight: bold; font-size: 18px;">💰 Your Gold: ${gold}</div>
        <div style="color: #9b59b6; font-weight: bold; font-size: 16px;">🃏 Deck: ${(gameState.deck||[]).length} cards</div>
        <div style="color: #4CAF50; font-weight: bold; font-size: 18px;">🔄 Rerolls: ${reroll}</div>
      </div>
      ${cardServicesHTML}
      ${shopCardsHTML}
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
    btn.onclick = () => {
      const itemIndex = parseInt(btn.dataset.index);
      const price = parseInt(btn.dataset.price);
      const item = shopItems[itemIndex];

      if (gold >= price) {
        gold -= price;
        gameState.gold = gold;
        _keepersSackCheck(price);
        acquireItem(item);

        // Auto-equip weapon if no weapon is equipped
        if (item.type === 'Weapon' && !gameState.equippedWeapon) {
          const weaponIndex = inventory.findIndex(i => i.name === item.name);
          if (weaponIndex !== -1 && typeof equipWeapon === 'function') {
            equipWeapon(weaponIndex);
          }
        }

        // Track purchased items
        purchasedIndices.push(itemIndex);

        // Check for Curse of Frugality and remove only ONE after first purchase
        const frugalityCurses = getCursesByType('frugality');
        if (frugalityCurses.length > 0) {
          const curseIndex = gameState.activeCurses.indexOf(frugalityCurses[0]);
          if (curseIndex !== -1) {
            gameState.activeCurses.splice(curseIndex, 1);
            updateCurseUI();
          }
        }

        saveCurrentGame();
        showShopModal(purchasedIndices);
      }
    };
  });

  // Card remove button handler
  // Re-build allDeckCards inside handler (same logic as above) so indices are consistent
  const getAllDeckCardsForHandlers = () => {
    const cKey = gameState.character;
    const cData = cKey && typeof PLAYER_CHARACTERS !== 'undefined' ? PLAYER_CHARACTERS[cKey] : null;
    const sEntries = (cData && cData.startingDeck) ? cData.startingDeck : [];
    const remSt = gameState.removedStartingCards || {};
    const starters = [];
    sEntries.forEach(entry => {
      const tmpl = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === entry.cardName) : null;
      if (!tmpl || tmpl.isStatusCard) return;
      const total = entry.count || 1;
      const removed = remSt[entry.cardName] || 0;
      for (let i = 0; i < total - removed; i++) {
        starters.push({ ...tmpl, _isStarting: true, _startingName: entry.cardName });
      }
    });
    return [...starters, ...(gameState.deck || []).filter(c => !c.isStatusCard)];
  };

  // Wire up visual card grid selection
  document.querySelectorAll('.shop-remove-card-item').forEach(el => {
    el.addEventListener('click', () => {
      document.querySelectorAll('.shop-remove-card-item').forEach(x => {
        x.style.background = 'rgba(0,0,0,0.4)';
        x.style.boxShadow = '';
      });
      el.style.background = 'rgba(231,76,60,0.25)';
      el.style.boxShadow = '0 0 8px rgba(231,76,60,0.6)';
      const hiddenInput = document.getElementById('shop-card-remove-select');
      if (hiddenInput) hiddenInput.value = el.dataset.removeIdx;
    });
  });

  const cardRemoveBtn = document.getElementById('shop-card-remove-btn');
  if (cardRemoveBtn && gameState.shopRemovesUsed === 0) {
    cardRemoveBtn.onclick = () => {
      const sel = document.getElementById('shop-card-remove-select');
      if (!sel || sel.value === '') {
        createNotification('Select a card to remove first.', '#888', '🗑️');
        return;
      }
      const cardIdx = parseInt(sel.value);
      if (isNaN(cardIdx) || gold < CARD_REMOVE_COST) return;
      const allCards = getAllDeckCardsForHandlers();
      if (cardIdx >= allCards.length) return;
      const card = allCards[cardIdx];
      gold -= CARD_REMOVE_COST;
      gameState.gold = gold;
      _keepersSackCheck(CARD_REMOVE_COST);
      gameState.shopRemovesUsed++;
      gameState.cardsRemovedThisRun = (gameState.cardsRemovedThisRun || 0) + 1;
      if (card._isStarting) {
        // Remove a starter card: track via removedStartingCards
        if (!gameState.removedStartingCards) gameState.removedStartingCards = {};
        gameState.removedStartingCards[card._startingName] = (gameState.removedStartingCards[card._startingName] || 0) + 1;
      } else {
        // Find by name match since the card object may be a different reference
        const deck = gameState.deck || [];
        const realIdx = deck.findIndex(c =>
          c.name === card.name && !!c.upgraded === !!card.upgraded && !c.isStatusCard
        );
        if (typeof removeCardFromDeck === 'function') removeCardFromDeck(realIdx);
      }
      saveCurrentGame();
      showShopModal(purchasedIndices);
    };
  }

  // Card buy button handlers
  document.querySelectorAll('.shop-card-buy-btn').forEach(btn => {
    btn.onclick = () => {
      const cardIndex = parseInt(btn.dataset.cardIndex);
      const price = parseInt(btn.dataset.price);
      if (isNaN(cardIndex) || gold < price) return;
      let card = shopCards[cardIndex];
      if (!card) return;
      // Refresh from CARDS_DATA so saved/cached shop cards pick up latest properties (learn, imageUrl, etc.)
      if (typeof CARDS_DATA !== 'undefined') {
        const freshCard = CARDS_DATA.find(c => c.name === card.name);
        if (freshCard) card = freshCard;
      }
      gold -= price;
      gameState.gold = gold;
      _keepersSackCheck(price);
      if (!gameState.purchasedShopCards) gameState.purchasedShopCards = [];
      gameState.purchasedShopCards.push(cardIndex);
      const deckBefore = (gameState.deck || []).length;
      if (typeof addCardToDeck === 'function') {
        addCardToDeck(card);
      } else {
        if (!gameState.deck) gameState.deck = [];
        gameState.deck.push({ ...card, upgraded: false });
        if (typeof createNotification === 'function') createNotification(`${card.name} added to deck!`, '#9b59b6', '🃏');
      }
      // Fallback: if the card didn't land in the deck for any reason, push it directly
      if ((gameState.deck || []).length <= deckBefore) {
        console.warn('[Shop] addCardToDeck did not add card; pushing directly:', card.name);
        if (!gameState.deck) gameState.deck = [];
        gameState.deck.push({ ...card, upgraded: false });
        if (typeof createNotification === 'function') createNotification(`${card.name} added to deck!`, '#9b59b6', '🃏');
      }
      // Ensure spell is learned regardless of which path added the card
      const _learnFn = window.learnSpellFromCard || window._doLearnSpell || (typeof learnSpellFromCard === 'function' ? learnSpellFromCard : null);
      if (_learnFn) _learnFn(card);
      saveCurrentGame();
      showShopModal(purchasedIndices);
    };
  });

  // Add reroll button handler
  const rerollBtn = document.getElementById('shop-reroll-btn');
  if (rerollBtn) {
    rerollBtn.onclick = () => {
      if ((gameState.shopRerollCount === 0 || reroll > 0) && gold >= rerollCost) {
        // Deduct reroll token only for paid rerolls; first reroll is free
        if (rerollCost > 0) {
          reroll -= 1;
          gameState.reroll = reroll;
        }
        gold -= rerollCost;
        gameState.gold = gold;
        _keepersSackCheck(rerollCost);

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
  gameState.currentShopCards = null;
  gameState.purchasedShopCards = null;
  gameState.shopRerollCount = 0;
  gameState.shopUpgradesUsed = 0;
  gameState.shopRemovesUsed = 0;
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
    delete gameState.currentShopCards;
    delete gameState.purchasedShopCards;
    gameState.shopRerollCount = 0;
    gameState.shopUpgradesUsed = 0;
    gameState.shopRemovesUsed = 0;
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
