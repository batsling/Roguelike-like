/**
 * Run-time UI modals: deck viewer, dice tray, spells panel, level-up.
 *
 * Extracted from js/main.js as part of the Phase 3 decomposition.
 *
 * These are the modals the player can open at any time during a run
 * (and a couple of post-encounter prompts that bridge into the dice /
 * spell systems). The rules they expose live in cards.js, dice-system.js,
 * combat-engine.js; this file is the UI rendering + event-wiring layer
 * that connects buttons to those systems.
 *
 * Cluster contents:
 *   - Card preview / zoom helpers: _cardPreviewBtn, showCardUpgradeZoom,
 *     showCardZoomOverlay
 *   - Notification history modal: showNotificationHistory
 *   - Deck viewer: showDeckModal (with drag-to-sort UI)
 *   - Dice tray: showDiceTrayModal, _diceTrayUnequip, _diceTrayPickItem
 *   - Spells panel: showSpellsModal
 *   - Level-up flow: showLevelUpPrompt, confirmLevelUp,
 *     confirmLevelUpLegacy (deprecated), and the dice-face upgrade
 *     subsystem: upgradeDiceFace, generateDiceLevelUpOptions,
 *     generateNewSideOption, applyDiceLevelUpOption,
 *     showDiceLevelUpChoiceModal
 *
 * Phase 5 (ESM) will replace the window.* exports with named exports.
 */

// ============== DECK VIEWER ==============

// ===== CARD UPGRADE PREVIEW SYSTEM =====
// Registry so inline onclick can reference card objects by index.
window._cardPR = [];

function _cardPreviewBtn(card) {
  const isWeapon = !!(card && card.tags && card.tags.includes('weapon'));
  if (!card || (!card.upgradedDescription && !isWeapon)) return '';
  const idx = window._cardPR.push(card) - 1;
  return `<button
    onclick="event.stopPropagation();showCardUpgradeZoom(window._cardPR[${idx}])"
    title="Preview Upgrade"
    style="position:absolute;top:5px;left:5px;
      width:22px;height:22px;padding:0;
      background:rgba(39,174,96,0.92);border:1px solid #2ecc71;border-radius:5px;
      color:white;cursor:pointer;font-size:13px;font-weight:bold;
      display:flex;align-items:center;justify-content:center;
      z-index:10;line-height:1;box-shadow:0 1px 4px rgba(0,0,0,0.4);">↑</button>`;
}
window._cardPreviewBtn = _cardPreviewBtn;

function showCardUpgradeZoom(card) {
  const existing = document.getElementById('card-zoom-overlay');
  if (existing) existing.remove();

  const rarityColors = { Rare: '#9b59b6', Uncommon: '#4CAF50', Common: '#aaa', Starter: '#888' };
  const color = rarityColors[card.rarity] || '#888';
  const imgSrc = card.imageUrl || '';
  const isWeaponCard = !!(card.tags && card.tags.includes('weapon'));

  // Resolve (val1/val2/val3) level notation to the value at the given level
  const _resolveLevel = (desc, lv) => desc.replace(/\(([^)]+)\)/g, (_, inner) => {
    const pts = inner.split('/').map(s => s.trim());
    return pts[Math.min(lv - 1, pts.length - 1)] || pts[pts.length - 1];
  });

  const overlay = document.createElement('div');
  overlay.id = 'card-zoom-overlay';
  overlay.style.cssText = `
    position:fixed;inset:0;background:rgba(0,0,0,0.82);
    display:flex;align-items:center;justify-content:center;
    z-index:25000;cursor:pointer;flex-direction:column;gap:0;
  `;

  if (isWeaponCard) {
    // For weapon cards: show trigger info (condition/reward) at current and next level
    const weaponItem = (typeof gameState !== 'undefined' && gameState.inventory || [])
      .find(i => i.name === card.name && i.type === 'Weapon');
    const weaponDesc = weaponItem ? (weaponItem.description || '') : '';
    const currentLevel = weaponItem ? (weaponItem.level || 1) : (card._weaponLevel || (card.upgraded ? 2 : 1));
    const nextLevel = currentLevel + 1;

    const conditionMatch = weaponDesc.match(/If you ([^,]+),/i);
    const conditionText = conditionMatch ? 'If you ' + conditionMatch[1].trim() + ',' : '';
    const rewardRaw = weaponDesc.replace(/^[^,]+,\s*/i, '');

    const currentReward = _resolveLevel(rewardRaw, currentLevel).replace(/^(gain|get)\s+/i, '');
    const nextReward = _resolveLevel(rewardRaw, nextLevel).replace(/^(gain|get)\s+/i, '');

    function buildWeaponPanel(level, reward, isUpgraded) {
      const borderColor = isUpgraded ? '#2ecc71' : color;
      const descColor = isUpgraded ? '#7dffb0' : '#ddd';
      const name = card.name + (isUpgraded ? ' <span style="color:#4CAF50;font-size:18px">+</span>' : '');
      return `
        <div style="background:#1e1e2e;border:3px solid ${borderColor};border-radius:14px;
          padding:26px 28px;max-width:320px;width:88vw;text-align:center;
          box-shadow:0 12px 50px rgba(0,0,0,0.9);cursor:default;" onclick="event.stopPropagation()">
          ${imgSrc ? `<img src="${imgSrc}" alt="${card.name}"
            style="width:130px;height:130px;object-fit:contain;margin-bottom:14px;border-radius:8px;border:2px solid ${borderColor}40;"
            onerror="this.style.display='none'">` : ''}
          <h2 style="margin:0 0 6px;color:white;font-size:20px;">${name}</h2>
          <div style="color:${borderColor};font-size:13px;margin-bottom:10px;font-weight:bold;">
            ${card.rarity || 'Starter'} · Weapon (Lv${level})
          </div>
          <div style="color:#cc9966;font-size:12px;margin-bottom:8px;font-style:italic;">${conditionText}</div>
          <div style="color:${descColor};font-size:14px;line-height:1.6;margin-bottom:14px;
            ${isUpgraded ? 'background:rgba(46,204,113,0.08);border-radius:6px;padding:8px;border:1px solid rgba(46,204,113,0.2);' : ''}">
            ${reward}
          </div>
          <div style="color:#ffd700;font-size:16px;font-weight:bold;">Cost: ${card.cost !== undefined ? card.cost : '?'}</div>
        </div>`;
    }

    overlay.innerHTML = `
      <div style="display:flex;gap:20px;align-items:flex-start;flex-wrap:wrap;justify-content:center;cursor:default;" onclick="event.stopPropagation()">
        <div>
          <div style="text-align:center;color:#aaa;font-size:12px;font-weight:bold;margin-bottom:8px;letter-spacing:1px;">CURRENT (LV${currentLevel})</div>
          ${buildWeaponPanel(currentLevel, currentReward, false)}
        </div>
        <div>
          <div style="text-align:center;color:#4CAF50;font-size:12px;font-weight:bold;margin-bottom:8px;letter-spacing:1px;">UPGRADED (LV${nextLevel}) ↑</div>
          ${buildWeaponPanel(nextLevel, nextReward, true)}
        </div>
      </div>
      <div style="margin-top:10px;padding:7px 14px;background:rgba(255,170,68,0.12);border:1px solid rgba(255,170,68,0.35);border-radius:7px;color:#ffaa44;font-size:11px;text-align:center;">
        Upgrading levels up this weapon's trigger reward.
      </div>
      <button onclick="document.getElementById('card-zoom-overlay').remove()" style="
        margin-top:16px;padding:9px 28px;background:#333;border:1px solid #666;border-radius:8px;
        color:#ccc;cursor:pointer;font-size:13px;">Close</button>
    `;
  } else {
    const hasUpgrade = !!card.upgradedDescription;

    function buildCardPanel(upgraded) {
      const desc = upgraded && card.upgradedDescription ? card.upgradedDescription : (card.description || '');
      const cost = upgraded && card.upgradedCost !== undefined && card.upgradedCost !== null
        ? card.upgradedCost : card.cost;
      const name = card.name + (upgraded ? ' <span style="color:#4CAF50;font-size:18px">+</span>' : '');
      const descColor = upgraded ? '#7dffb0' : '#ddd';
      const borderColor = upgraded ? '#2ecc71' : color;
      return `
        <div style="background:#1e1e2e;border:3px solid ${borderColor};border-radius:14px;
          padding:26px 28px;max-width:320px;width:88vw;text-align:center;
          box-shadow:0 12px 50px rgba(0,0,0,0.9);cursor:default;position:relative;"
          onclick="event.stopPropagation()">
          ${imgSrc ? `<img src="${imgSrc}" alt="${card.name}"
            style="width:130px;height:130px;object-fit:contain;margin-bottom:14px;border-radius:8px;border:2px solid ${borderColor}40;"
            onerror="this.style.display='none'">` : ''}
          <h2 style="margin:0 0 6px;color:white;font-size:20px;">${name}</h2>
          <div style="color:${borderColor};font-size:13px;margin-bottom:10px;font-weight:bold;">
            ${card.rarity || 'Starter'} · ${card.type || ''}
          </div>
          <div style="color:${descColor};font-size:14px;line-height:1.6;margin-bottom:14px;
            ${upgraded ? 'background:rgba(46,204,113,0.08);border-radius:6px;padding:8px;border:1px solid rgba(46,204,113,0.2);' : ''}">
            ${desc}
          </div>
          <div style="color:#ffd700;font-size:16px;font-weight:bold;">Cost: ${cost !== undefined ? cost : '?'}</div>
        </div>`;
    }

    if (hasUpgrade && !card.upgraded) {
      overlay.innerHTML = `
        <div style="display:flex;gap:20px;align-items:flex-start;flex-wrap:wrap;justify-content:center;cursor:default;" onclick="event.stopPropagation()">
          <div>
            <div style="text-align:center;color:#aaa;font-size:12px;font-weight:bold;margin-bottom:8px;letter-spacing:1px;">BASE</div>
            ${buildCardPanel(false)}
          </div>
          <div>
            <div style="text-align:center;color:#4CAF50;font-size:12px;font-weight:bold;margin-bottom:8px;letter-spacing:1px;">UPGRADED ↑</div>
            ${buildCardPanel(true)}
          </div>
        </div>
        <button onclick="document.getElementById('card-zoom-overlay').remove()" style="
          margin-top:20px;padding:9px 28px;background:#333;border:1px solid #666;border-radius:8px;
          color:#ccc;cursor:pointer;font-size:13px;">Close</button>
      `;
    } else {
      overlay.innerHTML = `
        ${buildCardPanel(!!card.upgraded)}
        ${hasUpgrade && card.upgraded ? `<div style="text-align:center;color:#aaa;font-size:11px;margin-top:6px;">(This card is upgraded)</div>` : ''}
        <button onclick="document.getElementById('card-zoom-overlay').remove()" style="
          margin-top:16px;padding:9px 28px;background:#333;border:1px solid #666;border-radius:8px;
          color:#ccc;cursor:pointer;font-size:13px;">Close</button>
      `;
    }
  }

  overlay.addEventListener('click', () => overlay.remove());
  document.body.appendChild(overlay);
}
window.showCardUpgradeZoom = showCardUpgradeZoom;

function showCardZoomOverlay(card) {
  const existing = document.getElementById('card-zoom-overlay');
  if (existing) existing.remove();

  const rarityColors = { Rare: '#9b59b6', Uncommon: '#4CAF50', Common: '#aaa', Starter: '#888' };
  const color = rarityColors[card.rarity] || '#888';
  const imgSrc = card.imageUrl || '';
  const isDiceCard = (card.type || '').toLowerCase() === 'dice';
  const diceEntry = isDiceCard && typeof DICE_DATA !== 'undefined'
    ? DICE_DATA.find(d => d.name === card.name)
    : null;
  const zoomDiceFacesHTML = diceEntry ? `
    <div style="margin:12px 0;text-align:left;">
      <div style="font-size:12px;font-weight:bold;color:${color};margin-bottom:6px;text-align:center;">🎲 Die Faces</div>
      <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:5px;">
        ${diceEntry.faces.map((f,i) => `
          <div style="background:rgba(0,0,0,0.5);border:1px solid ${color}55;border-radius:5px;padding:5px 4px;text-align:center;">
            <div style="font-size:9px;color:#888;">Face ${i+1}</div>
            <div style="font-size:11px;color:${color};font-weight:bold;line-height:1.3;">${f.text || f.face || '?'}</div>
          </div>`).join('')}
      </div>
    </div>` : '';

  const overlay = document.createElement('div');
  overlay.id = 'card-zoom-overlay';
  overlay.style.cssText = `
    position:fixed; inset:0; background:rgba(0,0,0,0.75);
    display:flex; align-items:center; justify-content:center;
    z-index:35000; cursor:pointer;
  `;
  overlay.innerHTML = `
    <div style="
      background:#1e1e2e; border:3px solid ${color};
      border-radius:16px; padding:28px 32px;
      max-width:360px; width:90vw; text-align:center;
      box-shadow:0 12px 50px rgba(0,0,0,0.9);
      cursor:default;
    " onclick="event.stopPropagation()">
      ${imgSrc ? `<img src="${imgSrc}" alt="${card.name}"
        style="width:140px;height:140px;object-fit:contain;margin-bottom:14px;border-radius:8px;border:2px solid ${color}40;"
        onerror="this.style.display='none'">` : (isDiceCard ? `<div style="font-size:64px;margin-bottom:10px;">🎲</div>` : '')}
      <h2 style="margin:0 0 6px;color:white;font-size:20px;">${card.name}${card.upgraded ? ' <span style="color:#4CAF50">+</span>' : ''}</h2>
      <div style="color:${color};font-size:13px;margin-bottom:10px;font-weight:bold;">${card.rarity || 'Starter'} · ${card.type || ''}</div>
      <div style="color:#ddd;font-size:14px;line-height:1.6;margin-bottom:14px;">${card.description || ''}</div>
      ${zoomDiceFacesHTML}
      <div style="color:#ffd700;font-size:16px;font-weight:bold;">Cost: ${card.cost !== undefined ? card.cost : '?'}</div>
      <button onclick="document.getElementById('card-zoom-overlay').remove()" style="
        margin-top:18px; padding:8px 24px;
        background:#444; border:1px solid #666; border-radius:8px;
        color:white; cursor:pointer; font-size:13px;
      ">Close</button>
    </div>
  `;
  overlay.addEventListener('click', () => overlay.remove());
  document.body.appendChild(overlay);
}
window.showCardZoomOverlay = showCardZoomOverlay;

function showNotificationHistory() {
  const history = window._notificationHistory || [];
  const rows = history.length === 0
    ? '<p style="color:#888;text-align:center;margin:40px 0;">No notifications yet.</p>'
    : [...history].reverse().map(e => `
        <div style="display:flex;align-items:flex-start;gap:10px;padding:8px 12px;border-bottom:1px solid #333;border-left:3px solid ${e.bgColor || '#555'};">
          <span style="font-size:18px;line-height:1.4;">${e.emoji || ''}</span>
          <div style="flex:1;">
            <div style="color:#fff;font-size:14px;">${e.text}</div>
            <div style="color:#666;font-size:11px;margin-top:2px;">${e.time || ''}</div>
          </div>
        </div>`).join('');

  createPanelOverlay(`
    <div style="max-width:520px;width:100%;margin:0 auto;">
      <h2 style="text-align:center;color:#aed6f1;margin-bottom:16px;">📜 Notification History</h2>
      <div style="max-height:60vh;overflow-y:auto;background:#1a1a2e;border-radius:8px;border:1px solid #333;">
        ${rows}
      </div>
      <div style="text-align:center;margin-top:16px;">
        <button onclick="closePanelOverlay()" style="padding:10px 28px;background:#555;border:none;border-radius:8px;color:white;cursor:pointer;font-weight:bold;">Close</button>
      </div>
    </div>
  `);
}
window.showNotificationHistory = showNotificationHistory;

function showDeckModal() {
  const charKey = (selectedCharacter) || (gameState && gameState.character) || null;
  const charData = (charKey && typeof PLAYER_CHARACTERS !== 'undefined') ? PLAYER_CHARACTERS[charKey] : null;
  const startingEntries = (charData && charData.startingDeck) ? charData.startingDeck : [];

  const getRarityColor = (rarity) => {
    switch (rarity) {
      case 'Rare': return '#9b59b6'; case 'Uncommon': return '#4CAF50';
      case 'Common': return '#aaa';  case 'Starter':  return '#888';
      default: return '#666';
    }
  };

  const cardHtml = (card, label, idx) => {
    const color = getRarityColor(card.rarity);
    const imgSrc = card.imageUrl || '';
    const _isDice = (card.type || '').toLowerCase() === 'dice';
    const artHTML = imgSrc
      ? `<img src="${imgSrc}" alt="${card.name}" style="width:60px;height:60px;object-fit:contain;margin-bottom:8px;" onerror="this.style.display='none'">`
      : (_isDice ? `<div style="font-size:36px;margin-bottom:6px;">🎲</div>` : '');
    const upgBtn = typeof _cardPreviewBtn === 'function' ? _cardPreviewBtn(card) : '';
    return `
      <div data-deck-card-idx="${idx}" style="background:#2d2d2d;border:2px solid ${color};border-radius:8px;
        padding:12px;display:flex;flex-direction:column;align-items:center;
        min-width:130px;max-width:160px;position:relative;cursor:pointer;
        transition:transform 0.15s,box-shadow 0.15s;"
        onmouseenter="this.style.transform='scale(1.04)';this.style.boxShadow='0 6px 20px rgba(0,0,0,0.6)'"
        onmouseleave="this.style.transform='';this.style.boxShadow=''">
        ${upgBtn}
        ${label ? `<div style="position:absolute;top:4px;right:4px;background:${color};color:#000;font-size:9px;padding:2px 5px;border-radius:4px;font-weight:bold;">${label}</div>` : ''}
        ${artHTML}
        ${(() => {
          const isWpn = card.tags && card.tags.includes('weapon');
          const wpnItem = isWpn && typeof gameState !== 'undefined'
            ? (gameState.inventory || []).find(i => i.name === card.name && i.type === 'Weapon') : null;
          const lvl = wpnItem ? (wpnItem.level || 1) : null;
          return lvl && lvl > 1
            ? `<div style="position:absolute;bottom:5px;right:5px;background:#cc6600;color:#fff;font-size:9px;padding:1px 5px;border-radius:4px;font-weight:bold;">Lv${lvl}</div>`
            : '';
        })()}
        <div style="font-weight:bold;font-size:13px;color:white;text-align:center;margin-bottom:3px;">${card.name}${card.upgraded ? ' +' : ''}</div>
        <div style="color:${color};font-size:11px;margin-bottom:4px;">${card.rarity || 'Starter'} · ${card.type || ''}</div>
        <div style="font-size:11px;color:#ccc;text-align:center;margin-bottom:6px;">${card.description || ''}</div>
        <div style="color:#ffd700;font-size:11px;">Cost: ${card.cost !== undefined ? card.cost : '?'}</div>
      </div>
    `;
  };

  // Build starting cards from character startingDeck
  const CDATA = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : (typeof cards !== 'undefined' ? cards : []);
  const startingCards = [];
  for (const entry of startingEntries) {
    const tmpl = CDATA.find(c => c.name === entry.cardName || c.name.toLowerCase() === entry.cardName.toLowerCase());
    const obj = tmpl || { name: entry.cardName, rarity: 'Starter', type: '', description: '', cost: '?' };
    for (let i = 0; i < (entry.count || 1); i++) startingCards.push(obj);
  }

  // Collected (acquired) cards from this run
  const collectedCards = (gameState && gameState.deck) ? gameState.deck : [];

  const totalCount = startingCards.length + collectedCards.length;
  // Store all cards in order for click-to-zoom (starting first, then collected)
  window._deckModalAllCards = [...startingCards, ...collectedCards];
  const startingHTML = startingCards.map((c, i) => cardHtml(c, 'Starting', i)).join('');
  const collectedHTML = collectedCards.map((c, i) => cardHtml(c, 'Acquired', startingCards.length + i)).join('');

  createPanelOverlay(`
    <div style="padding:20px;max-width:1100px;margin:0 auto;">
      <h2 style="color:#9b59b6;text-align:center;margin-top:0;">🃏 Your Deck (${totalCount} cards)</h2>
      <p style="text-align:center;color:#888;font-size:12px;margin:0 0 12px;">Click a card to zoom in</p>
      ${startingHTML ? `
        <h3 style="color:#888;margin:12px 0 8px;">Starting Deck (${startingCards.length})</h3>
        <div style="display:flex;gap:12px;flex-wrap:wrap;margin-bottom:16px;">${startingHTML}</div>
      ` : '<p style="color:#888;text-align:center;">No starting deck</p>'}
      ${collectedHTML ? `
        <h3 style="color:#9b59b6;margin:12px 0 8px;">Acquired Cards (${collectedCards.length})</h3>
        <div style="display:flex;gap:12px;flex-wrap:wrap;">${collectedHTML}</div>
      ` : ''}
      <div style="text-align:center;margin-top:20px;">
        <button onclick="closePanelOverlay()" style="padding:12px 30px;background:#555;border:none;border-radius:8px;color:white;cursor:pointer;font-weight:bold;">Close</button>
      </div>
    </div>
  `);

  // Attach click-to-zoom on each card
  document.querySelectorAll('[data-deck-card-idx]').forEach(el => {
    el.addEventListener('click', () => {
      const idx = parseInt(el.dataset.deckCardIdx);
      const card = window._deckModalAllCards && window._deckModalAllCards[idx];
      if (card) showCardZoomOverlay(card);
    });
  });
}
window.showDeckModal = showDeckModal;

// ============== DICE TRAY ==============

function showDiceTrayModal() {
  if (!gameState.diceSlots) gameState.diceSlots = {};

  const CDATA = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [];
  const DDATA = typeof DICE_DATA   !== 'undefined' ? DICE_DATA   : [];

  // Collect all dice cards: starting-deck dice + acquired dice
  const charKey  = (typeof selectedCharacter !== 'undefined' && selectedCharacter)
                 || (gameState && gameState.character) || null;
  const charData = (charKey && typeof PLAYER_CHARACTERS !== 'undefined') ? PLAYER_CHARACTERS[charKey] : null;
  const startingEntries = charData && charData.startingDeck ? charData.startingDeck : [];
  const startingDiceCards = [];
  for (const entry of startingEntries) {
    const tmpl = CDATA.find(c => c.name === entry.cardName || c.name.toLowerCase() === entry.cardName.toLowerCase());
    if (tmpl && (tmpl.type || '').toLowerCase() === 'dice') {
      for (let i = 0; i < (entry.count || 1); i++) {
        startingDiceCards.push({ ...tmpl, _isStarting: true, _dieUid: `starting_${tmpl.name}_${i}` });
      }
    }
  }
  const acquiredDiceCards = (gameState.deck || []).filter(c => (c.type || '').toLowerCase() === 'dice');

  const allDice = [...startingDiceCards, ...acquiredDiceCards];

  const getFaceList = (card) => {
    const def = DDATA.find(d => d.name === card.name);
    if (!def) return [];
    return def.faces || [];
  };

  const dieCardHTML = (card, idx) => {
    const uid   = card._dieUid || `anon_${idx}`;
    const slot  = gameState.diceSlots[uid] || null;
    const faces = getFaceList(card);
    const _addonBadge = (label, bg, color) =>
      `<span style="font-size:8px;background:${bg};color:${color};border-radius:3px;padding:1px 4px;white-space:nowrap;">${label}</span>`;
    const _addonStyle = {
      cantrip:   () => _addonBadge('Cantrip',   '#4a2c8a', '#c09aff'),
      singleuse: () => _addonBadge('1-Use',      '#8a2c2c', '#ffaaaa'),
      druid:     () => _addonBadge('Druid',      '#2c5a2c', '#aaffaa'),
      mandatory: () => _addonBadge('Mandatory',  '#6a2222', '#ffaaaa'),
      melee:     () => _addonBadge('Melee',      '#5a3a00', '#ffcc44'),
      cleave:    () => _addonBadge('Cleave',     '#005a5a', '#44ffff'),
      ranged:    () => _addonBadge('Ranged',     '#003a6a', '#44aaff'),
      magic:     () => _addonBadge('Magic',      '#3a006a', '#cc88ff'),
    };

    const facesHTML = faces.map(f => {
      const isBlank = f.isBlank || !f.text || f.text === 'X' || f.text === '—';
      const pip = ['⚀','⚁','⚂','⚃','⚄','⚅'][f.face-1] || '🎲';

      // Collect addons from face level + all effect levels
      const allAddons = new Set();
      (f.addons || []).forEach(a => allAddons.add(a.toLowerCase()));
      (f.effects || []).forEach(eff => (eff.addons || []).forEach(a => allAddons.add(a.toLowerCase())));

      const badges = [...allAddons]
        .map(a => (_addonStyle[a] ? _addonStyle[a]() : _addonBadge(a.charAt(0).toUpperCase()+a.slice(1), '#333', '#aaa')))
        .join('');

      return `<div data-face="${f.face}" style="
        background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.15);
        border-radius:6px;padding:5px 7px;display:flex;flex-direction:row;align-items:flex-start;gap:7px;">
        <div style="font-size:20px;line-height:1.2;flex-shrink:0;">${pip}</div>
        <div style="display:flex;flex-direction:column;gap:3px;min-width:0;">
          <div style="font-size:9px;color:${isBlank?'#444':'#ddd'};line-height:1.3;word-break:break-word;">
            ${isBlank ? '—' : (f.text || '—')}
          </div>
          ${badges ? `<div style="display:flex;flex-wrap:wrap;gap:2px;">${badges}</div>` : ''}
        </div>
      </div>`;
    }).join('');

    const slotHTML = slot
      ? `<div class="die-item-slot filled" data-die-uid="${uid}" style="
          display:flex;align-items:center;gap:8px;padding:6px 10px;
          background:rgba(100,70,20,0.4);border:2px solid #d35400;border-radius:8px;
          cursor:pointer;min-width:0;" title="Click to remove item">
          <img src="${slot.image || ''}" style="width:28px;height:28px;object-fit:contain;flex-shrink:0;border-radius:4px;background:rgba(0,0,0,0.3);"
            onerror="this.style.display='none'">
          <div style="min-width:0;">
            <div style="font-size:10px;font-weight:bold;color:#f0c850;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${slot.name}</div>
            <div style="font-size:9px;color:#aaa;line-height:1.3;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${slot.description || ''}</div>
          </div>
          <div style="margin-left:auto;color:#e74c3c;font-size:12px;flex-shrink:0;">✕</div>
        </div>`
      : `<div class="die-item-slot empty" data-die-uid="${uid}" style="
          display:flex;align-items:center;justify-content:center;gap:6px;
          padding:8px 12px;background:rgba(255,255,255,0.04);
          border:2px dashed rgba(255,255,255,0.2);border-radius:8px;
          cursor:pointer;color:#666;font-size:11px;" title="Click to equip an item">
          <span style="font-size:16px;">+</span> Equip Item
        </div>`;

    return `
      <div style="background:rgba(10,8,5,0.85);border:2px solid #7d4e00;border-radius:12px;
        padding:14px;display:flex;flex-direction:column;gap:10px;min-width:300px;max-width:400px;">
        <div style="display:flex;align-items:center;gap:10px;">
          ${card.imageUrl
            ? `<img src="${card.imageUrl}" style="width:40px;height:40px;object-fit:contain;border-radius:6px;background:rgba(0,0,0,0.4);" onerror="this.style.display='none';this.insertAdjacentHTML('afterend','<div style=\\'width:40px;height:40px;display:flex;align-items:center;justify-content:center;font-size:28px;border-radius:6px;background:rgba(0,0,0,0.3);\\'>🎲</div>')">`
            : `<div style="width:40px;height:40px;display:flex;align-items:center;justify-content:center;font-size:28px;border-radius:6px;background:rgba(0,0,0,0.3);">🎲</div>`}
          <div>
            <div style="font-weight:bold;font-size:13px;color:#f0c850;">${card.name}${card.upgraded ? ' +' : ''}</div>
            <div style="font-size:10px;color:#888;">${card.rarity || 'Starter'} Dice${card._isStarting ? ' · Starting' : ''}</div>
          </div>
        </div>
        ${faces.length > 0 ? `
          <div style="display:grid;grid-template-columns:repeat(2,1fr);gap:4px;">${facesHTML}</div>
        ` : `<div style="font-size:10px;color:#555;text-align:center;">No face data</div>`}
        ${slotHTML}
      </div>`;
  };

  const diceHTML = allDice.length > 0
    ? allDice.map((c, i) => dieCardHTML(c, i)).join('')
    : '<p style="color:#666;text-align:center;grid-column:1/-1;">No dice in your collection yet.</p>';

  createPanelOverlay(`
    <div style="padding:20px;max-width:1100px;margin:0 auto;">
      <h2 style="color:#d35400;text-align:center;margin-top:0;">🎲 Dice Tray (${allDice.length} dice)</h2>
      <p style="text-align:center;color:#888;font-size:12px;margin:0 0 16px;">
        Slot an item onto each die — items apply their effects when the die is played.
        Slotted items are not shown in inventory during combat.
      </p>
      <div style="display:flex;flex-wrap:wrap;gap:14px;justify-content:center;">
        ${diceHTML}
      </div>
      <div style="text-align:center;margin-top:20px;">
        <button onclick="closePanelOverlay()" style="padding:12px 30px;background:#555;border:none;border-radius:8px;color:white;cursor:pointer;font-weight:bold;">Close</button>
      </div>
    </div>
  `);

  // Wire up slot clicks
  document.querySelectorAll('.die-item-slot.filled').forEach(el => {
    el.addEventListener('click', () => {
      const uid = el.dataset.dieUid;
      _diceTrayUnequip(uid);
      showDiceTrayModal();
    });
  });

  document.querySelectorAll('.die-item-slot.empty').forEach(el => {
    el.addEventListener('click', () => {
      const uid = el.dataset.dieUid;
      _diceTrayPickItem(uid);
    });
  });
}

function _diceTrayUnequip(dieUid) {
  if (!gameState.diceSlots) gameState.diceSlots = {};
  const item = gameState.diceSlots[dieUid];
  if (!item) return;
  // Return item to inventory
  StateMutator.addItem(item);
  delete gameState.diceSlots[dieUid];
  if (typeof createNotification === 'function') {
    createNotification(`${item.name} unequipped from die.`, '#888', '📦');
  }
  saveCurrentGame();
}

function _diceTrayPickItem(dieUid) {
  const inv = typeof inventory !== 'undefined' ? inventory : (gameState.inventory || []);
  // Filter out items already slotted to other dice
  const slottedNames = new Set(
    Object.values(gameState.diceSlots || {}).filter(Boolean).map(i => i.name)
  );
  const available = inv.filter(item => !slottedNames.has(item.name));

  if (available.length === 0) {
    if (typeof createNotification === 'function') {
      createNotification('No items available to equip.', '#888', '📦');
    }
    return;
  }

  const rarityColor = r => {
    switch ((r || '').toLowerCase()) {
      case 'legendary': return '#ff6b00';
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      default: return '#aaa';
    }
  };

  const itemsHTML = available.map((item, idx) => `
    <div class="dice-tray-item-pick" data-item-idx="${idx}" style="
      display:flex;align-items:center;gap:10px;padding:8px 10px;
      background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.12);
      border-radius:8px;cursor:pointer;transition:background 0.15s;"
      onmouseover="this.style.background='rgba(211,84,0,0.18)'"
      onmouseout="this.style.background='rgba(255,255,255,0.04)'">
      <img src="${item.image || ''}" style="width:32px;height:32px;object-fit:contain;flex-shrink:0;border-radius:4px;background:rgba(0,0,0,0.3);"
        onerror="this.style.display='none'">
      <div style="min-width:0;">
        <div style="font-size:11px;font-weight:bold;color:${rarityColor(item.rarity)};">${item.name}</div>
        <div style="font-size:9px;color:#aaa;line-height:1.3;">${item.description || ''}</div>
      </div>
    </div>`).join('');

  // Show a picker overlay within the modal
  const existingPicker = document.getElementById('dice-item-picker');
  if (existingPicker) existingPicker.remove();

  const gameModal = document.querySelector('.game-modal-content') || document.getElementById('game-modal');
  if (!gameModal) return;

  const picker = document.createElement('div');
  picker.id = 'dice-item-picker';
  picker.style.cssText = `position:fixed;inset:0;z-index:30000;background:rgba(0,0,0,0.8);
    display:flex;align-items:center;justify-content:center;`;
  picker.innerHTML = `
    <div style="background:#1a1208;border:2px solid #d35400;border-radius:14px;padding:20px;
      max-width:500px;width:92%;max-height:75vh;display:flex;flex-direction:column;gap:12px;">
      <div style="display:flex;align-items:center;justify-content:space-between;">
        <h3 style="color:#f0c850;margin:0;font-size:16px;">📦 Choose an Item</h3>
        <button id="dice-item-picker-close" style="background:none;border:none;color:#aaa;font-size:20px;cursor:pointer;line-height:1;">✕</button>
      </div>
      <div style="overflow-y:auto;display:flex;flex-direction:column;gap:6px;max-height:55vh;">
        ${itemsHTML}
      </div>
    </div>`;
  document.body.appendChild(picker);

  picker.querySelector('#dice-item-picker-close').addEventListener('click', () => picker.remove());
  picker.addEventListener('click', e => { if (e.target === picker) picker.remove(); });

  picker.querySelectorAll('.dice-tray-item-pick').forEach(el => {
    el.addEventListener('click', () => {
      const idx  = parseInt(el.dataset.itemIdx);
      const item = available[idx];
      if (!item) return;
      picker.remove();

      // Remove from inventory, add to slot
      StateMutator.removeItem(item);
      if (!gameState.diceSlots) gameState.diceSlots = {};
      gameState.diceSlots[dieUid] = item;
      if (typeof createNotification === 'function') {
        createNotification(`${item.name} equipped to die!`, '#d35400', '🎲');
      }
      saveCurrentGame();
      showDiceTrayModal();
    });
  });
}

window.showDiceTrayModal = showDiceTrayModal;

// ============== SPELLS MODAL ==============

function showSpellsModal() {
  const spells = (gameState && gameState.spells) ? gameState.spells : [];

  const elementColor = el => {
    switch ((el || '').toLowerCase()) {
      case 'fire':     return '#ff6b35';
      case 'water':    return '#4488ff';
      case 'earth':    return '#88aa44';
      case 'dark':     return '#a855f7';
      case 'blood':    return '#cc2222';
      case 'poison':   return '#44bb44';
      case 'electric': return '#ffcc00';
      default:         return '#888';
    }
  };

  const rarityColor = r => {
    switch ((r || '').toLowerCase()) {
      case 'rare':     return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      case 'common':   return '#aaa';
      default:         return '#888';
    }
  };

  const spellCard = spell => {
    const rc = rarityColor(spell.rarity);
    const ec = elementColor(spell.element);
    const keywordsHTML = (spell.keywords || []).map(k =>
      `<span style="font-size:9px;padding:2px 7px;background:rgba(124,58,237,0.18);
        border:1px solid rgba(124,58,237,0.4);border-radius:10px;color:#c4b5fd;">${k}</span>`
    ).join('');

    return `
      <div style="background:rgba(10,5,20,0.9);border:2px solid ${rc};border-radius:12px;
        padding:14px;display:flex;flex-direction:column;gap:8px;
        min-width:190px;max-width:230px;position:relative;">
        <!-- Cost badge -->
        <div style="position:absolute;top:10px;right:10px;
          background:rgba(99,102,241,0.25);border:1px solid #6366f1;
          border-radius:50%;width:26px;height:26px;
          display:flex;align-items:center;justify-content:center;
          font-size:11px;font-weight:bold;color:#a5b4fc;" title="${spell.cost} Mana">
          ${spell.cost}
        </div>
        <!-- Image -->
        <div style="display:flex;gap:10px;align-items:center;">
          <img src="${spell.imageUrl || spell.image || ''}"
            style="width:44px;height:44px;object-fit:contain;border-radius:6px;
              background:rgba(0,0,0,0.4);border:1px solid ${rc}55;flex-shrink:0;"
            onerror="this.style.opacity='0.2'">
          <div style="min-width:0;padding-right:28px;">
            <div style="font-weight:bold;font-size:12px;color:#e9d5ff;
              overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${spell.name}</div>
            <div style="display:flex;gap:5px;margin-top:3px;flex-wrap:wrap;">
              <span style="font-size:9px;color:${rc};font-weight:bold;text-transform:uppercase;">${spell.rarity || ''}</span>
              ${spell.element && spell.element !== 'N/A'
                ? `<span style="font-size:9px;color:${ec};font-weight:bold;">${spell.element}</span>` : ''}
            </div>
          </div>
        </div>
        <!-- Description -->
        <div style="font-size:11px;color:#ccc;line-height:1.5;
          background:rgba(124,58,237,0.08);border-radius:6px;padding:6px 8px;">
          ${spell.description || 'No description.'}
        </div>
        ${keywordsHTML ? `<div style="display:flex;flex-wrap:wrap;gap:4px;">${keywordsHTML}</div>` : ''}
        ${spell.game ? `<div style="font-size:9px;color:#555;">From: <span style="color:#666;">${spell.game}</span></div>` : ''}
      </div>`;
  };

  const content = spells.length > 0
    ? `<div style="display:flex;flex-wrap:wrap;gap:12px;justify-content:center;">
        ${spells.map(spellCard).join('')}
      </div>`
    : `<div style="text-align:center;color:#555;padding:40px 0;">
        <div style="font-size:40px;margin-bottom:12px;">✨</div>
        <div>No spells learned yet.</div>
        <div style="font-size:12px;color:#444;margin-top:6px;">Acquire dice cards with a "Learn:" effect to gain spells.</div>
      </div>`;

  createPanelOverlay(`
    <div style="padding:20px;max-width:1000px;margin:0 auto;">
      <h2 style="color:#c4b5fd;text-align:center;margin-top:0;">✨ Your Spells (${spells.length})</h2>
      ${content}
      <div style="text-align:center;margin-top:20px;">
        <button onclick="closePanelOverlay()" style="padding:12px 30px;background:#2d1a4e;
          border:1px solid #7c3aed;border-radius:8px;color:#c4b5fd;cursor:pointer;font-weight:bold;">
          Close
        </button>
      </div>
    </div>
  `);
}
window.showSpellsModal = showSpellsModal;

// ============== LEVEL-UP SYSTEM ==============

/**
 * Show the level-up prompt for the current character
 */
function showLevelUpPrompt() {
  const characterKey = selectedCharacter || gameState.character || 'Rodney';
  const characterData = PLAYER_CHARACTERS[characterKey];

  if (!characterData) {
    console.error('Character data not found for level-up');
    return;
  }

  const currentLevel = gameState.playerLevel || 1;
  const levelUpCondition = characterData.levelUpCondition || 'Complete a special achievement';

  createGameModal(`
    <div style="text-align: center; padding: 20px; max-width: 500px; margin: 0 auto;">
      <h2 style="color: #FFD700; margin-bottom: 20px;">Level Up!</h2>
      <div style="
        background: rgba(0,0,0,0.4);
        border: 2px solid #FFD700;
        border-radius: 10px;
        padding: 20px;
        margin-bottom: 20px;
      ">
        <p style="color: #aaa; font-size: 14px; margin-bottom: 10px;">
          Current Level: <span style="color: #FFD700; font-size: 20px; font-weight: bold;">${currentLevel}</span>
        </p>
        <p style="color: #ccc; margin-bottom: 15px;">
          To level up, you must:
        </p>
        <p style="
          color: #fff;
          font-size: 16px;
          font-weight: bold;
          background: rgba(255,215,0,0.1);
          border: 1px solid rgba(255,215,0,0.3);
          border-radius: 6px;
          padding: 10px;
        ">
          "${levelUpCondition}"
        </p>
      </div>
      <p style="color: #aaa; font-size: 14px; margin-bottom: 20px;">
        Have you completed this requirement?
      </p>
      <div style="display: flex; gap: 15px; justify-content: center;">
        <button id="level-up-confirm-btn" style="
          padding: 12px 24px;
          background: linear-gradient(145deg, #4CAF50, #2E7D32);
          border: 2px solid #2E7D32;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">Yes, Level Up!</button>
        <button id="level-up-cancel-btn" style="
          padding: 12px 24px;
          background: #444;
          border: 2px solid #666;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">Not Yet</button>
      </div>
    </div>
  `);

  document.getElementById('level-up-confirm-btn').onclick = () => {
    closeGameModal();
    confirmLevelUp();
  };

  document.getElementById('level-up-cancel-btn').onclick = () => {
    closeGameModal();
  };
}

/**
 * Confirm level up and apply bonuses
 */
function confirmLevelUp(onComplete) {
  const characterKey = selectedCharacter || gameState.character || 'Rodney';
  const characterData = PLAYER_CHARACTERS[characterKey];

  if (!characterData || !characterData.levelUpStats) {
    console.error('Character level-up data not found');
    return;
  }

  // Crown: 50% chance to level up an additional time after this one completes
  const _crownInv = typeof inventory !== 'undefined' ? inventory : [];
  const _crownCount = _crownInv.filter(i => i.name === 'Crown').length;
  function _afterReward() {
    if (_crownCount > 0 && Math.random() < 0.5) {
      if (typeof createNotification === 'function') {
        createNotification('Crown: Bonus Level Up!', '#FFD700', '👑');
      }
      confirmLevelUp(onComplete);
    } else {
      if (onComplete) onComplete();
    }
  }

  const oldLevel = gameState.playerLevel || 1;
  gameState.playerLevel = oldLevel + 1;

  const bonuses = characterData.levelUpStats;
  const appliedBonuses = [];

  // Apply stat bonuses
  const STAT_LABELS = {
    strength: 'Strength', dexterity: 'Dexterity', intelligence: 'Intelligence',
    charisma: 'Charisma', luck: 'Luck',
  };
  for (const stat of Object.keys(STAT_LABELS)) {
    if (bonuses[stat]) {
      StateMutator.modifyStat(stat, bonuses[stat]);
      appliedBonuses.push(`+${bonuses[stat]} ${STAT_LABELS[stat]}`);
    }
  }
  const ABILITY_LABELS = {
    reroll: 'Reroll', dash: 'Dash', skip: 'Skip',
    discovery: 'Discovery', fov: 'FoV',
  };
  for (const ability of Object.keys(ABILITY_LABELS)) {
    if (bonuses[ability]) {
      StateMutator.modifyAbility(ability, bonuses[ability]);
      appliedBonuses.push(`+${bonuses[ability]} ${ABILITY_LABELS[ability]}`);
    }
  }
  if (bonuses.maxHealth) {
    StateMutator.modifyMaxHealth(bonuses.maxHealth);
    StateMutator.modifyHealth(bonuses.maxHealth);
    appliedBonuses.push(`+${bonuses.maxHealth} Max Health`);
  }

  // Handle random stat allocation
  if (bonuses.random && bonuses.random > 0) {
    const randomStats = ['strength', 'dexterity', 'intelligence', 'charisma'];
    for (let i = 0; i < bonuses.random; i++) {
      const randomStat = randomStats[Math.floor(Math.random() * randomStats.length)];
      switch(randomStat) {
        case 'strength': strength++; break;
        case 'dexterity': dexterity++; break;
        case 'intelligence': intelligence++; break;
        case 'charisma': charisma++; break;
      }
      appliedBonuses.push(`+1 ${randomStat.charAt(0).toUpperCase() + randomStat.slice(1)} (random)`);
    }
  }

  // Sync stats to gameState
  gameState.strength = strength;
  gameState.dexterity = dexterity;
  gameState.intelligence = intelligence;
  gameState.charisma = charisma;
  gameState.luck = luck;

  // Rock Bottom: record new highs after level-up stat bonuses
  if (typeof inventory !== 'undefined' && inventory.some(i => i.name === 'Rock Bottom')) {
    if (!gameState.rockBottomBests) gameState.rockBottomBests = {};
    for (const _s of ['strength', 'dexterity', 'intelligence', 'charisma', 'fov', 'discovery', 'luck']) {
      const _cur = (typeof window[_s] !== 'undefined' ? window[_s] : 0) || 0;
      if (_cur > (gameState.rockBottomBests[_s] || 0)) gameState.rockBottomBests[_s] = _cur;
    }
  }

  // Update UI
  updateTopBar();
  saveCurrentGame();

  // Determine the extra reward for this character
  const reward = characterData.levelUpReward || { type: 'none' };

  const rewardLabels = {
    gold:  `💰 ${reward.amount} Gold`,
    item:  '📦 Choose an Item',
    card:  '🃏 Choose a Card',
    spell: '✨ Choose a Spell',
    none:  null,
  };
  const rewardLabel = rewardLabels[reward.type] || null;

  const rewardBtnHTML = rewardLabel ? `
    <button id="proceed-to-reward-btn" style="
      padding: 12px 30px;
      background: linear-gradient(145deg, #9b59b6, #7d3c98);
      border: 2px solid #9b59b6;
      border-radius: 8px;
      color: #fff;
      font-weight: bold;
      cursor: pointer;
      font-size: 16px;
    ">${rewardLabel}</button>
  ` : `
    <button id="proceed-to-reward-btn" style="
      padding: 12px 30px;
      background: #444;
      border: 2px solid #666;
      border-radius: 8px;
      color: #ccc;
      cursor: pointer;
      font-size: 16px;
    ">Continue</button>
  `;

  createGameModal(`
    <div style="text-align: center; padding: 20px; max-width: 500px; margin: 0 auto;">
      <h2 style="color: #FFD700; margin-bottom: 20px;">Level ${gameState.playerLevel}!</h2>
      <div style="
        background: rgba(76,175,80,0.1);
        border: 2px solid #4CAF50;
        border-radius: 10px;
        padding: 20px;
        margin-bottom: 20px;
      ">
        <p style="color: #4CAF50; font-size: 18px; margin-bottom: 15px; font-weight: bold;">
          Stat Bonuses Gained:
        </p>
        <div style="display: flex; flex-direction: column; gap: 8px;">
          ${appliedBonuses.length > 0 ? appliedBonuses.map(b => `
            <div style="color: #fff; font-size: 14px;">${b}</div>
          `).join('') : '<div style="color: #888; font-size: 14px;">No stat bonuses</div>'}
        </div>
      </div>
      ${rewardBtnHTML}
    </div>
  `);

  document.getElementById('proceed-to-reward-btn').onclick = () => {
    closeGameModal();
    switch (reward.type) {
      case 'gold':
        StateMutator.modifyGold(reward.amount);
        saveCurrentGame();
        if (typeof createNotification === 'function') {
          createNotification(`+${reward.amount} Gold!`, '#FFD700', '💰');
        }
        _afterReward();
        break;

      case 'item':
        if (typeof showItemChoiceModal === 'function') {
          showItemChoiceModal(_afterReward, 'small');
        } else _afterReward();
        break;

      case 'card':
        if (typeof window.showCardRewardModal === 'function') {
          window.showCardRewardModal(_afterReward, reward.tag || null);
          saveCurrentGame();
        } else _afterReward();
        break;

      case 'spell':
        if (typeof createGameModal === 'function') {
          createGameModal(`
            <div style="text-align:center; padding:30px; max-width:400px;">
              <h2 style="color:#9b59b6; margin-bottom:15px;">✨ Spell Reward</h2>
              <p style="color:#aaa; margin-bottom:20px;">Spells are not yet implemented. Check back later!</p>
              <button id="spell-reward-close-btn" style="
                padding:10px 24px; background:#444; border:none;
                border-radius:8px; color:white; cursor:pointer; font-size:14px;
              ">Close</button>
            </div>
          `);
          const spellBtn = document.getElementById('spell-reward-close-btn');
          if (spellBtn) spellBtn.onclick = () => { closeGameModal(); _afterReward(); };
        } else _afterReward();
        break;

      case 'none':
      default:
        _afterReward();
        break;
    }
  };
}

// Legacy function for backwards compatibility (random upgrade)
function confirmLevelUpLegacy() {
  const characterKey = selectedCharacter || gameState.character || 'Rodney';
  const characterData = PLAYER_CHARACTERS[characterKey];

  if (!characterData || !characterData.levelUpStats) {
    console.error('Character level-up data not found');
    return;
  }

  const oldLevel = gameState.playerLevel || 1;
  gameState.playerLevel = oldLevel + 1;

  const bonuses = characterData.levelUpStats;
  const appliedBonuses = [];

  // Apply stat bonuses (same as above)
  if (bonuses.strength) { strength += bonuses.strength; appliedBonuses.push(`+${bonuses.strength} Strength`); }
  if (bonuses.dexterity) { dexterity += bonuses.dexterity; appliedBonuses.push(`+${bonuses.dexterity} Dexterity`); }
  if (bonuses.intelligence) { intelligence += bonuses.intelligence; appliedBonuses.push(`+${bonuses.intelligence} Intelligence`); }
  if (bonuses.charisma) { charisma += bonuses.charisma; appliedBonuses.push(`+${bonuses.charisma} Charisma`); }
  if (bonuses.reroll) { reroll += bonuses.reroll; gameState.reroll = reroll; appliedBonuses.push(`+${bonuses.reroll} Reroll`); }
  if (bonuses.dash) { gameState.dash = (gameState.dash || 0) + bonuses.dash; appliedBonuses.push(`+${bonuses.dash} Dash`); }
  if (bonuses.luck) { luck += bonuses.luck; appliedBonuses.push(`+${bonuses.luck} Luck`); }

  // Upgrade a random dice face (old behavior)
  const diceUpgraded = upgradeDiceFace(characterKey);

  updateTopBar();
  saveCurrentGame();

  createGameModal(`
    <div style="text-align: center; padding: 20px; max-width: 500px; margin: 0 auto;">
      <h2 style="color: #FFD700; margin-bottom: 20px;">Level ${gameState.playerLevel}!</h2>
      <div style="
        background: rgba(76,175,80,0.1);
        border: 2px solid #4CAF50;
        border-radius: 10px;
        padding: 20px;
        margin-bottom: 20px;
      ">
        <p style="color: #4CAF50; font-size: 18px; margin-bottom: 15px; font-weight: bold;">
          Bonuses Gained:
        </p>
        <div style="display: flex; flex-direction: column; gap: 8px;">
          ${appliedBonuses.map(b => `<div style="color: #fff; font-size: 14px;">${b}</div>`).join('')}
          ${diceUpgraded ? `<div style="color: #FFD700; font-size: 14px; margin-top: 10px;">${diceUpgraded}</div>` : ''}
        </div>
      </div>
      <button onclick="closeGameModal()" style="
        padding: 12px 30px;
        background: linear-gradient(145deg, #4CAF50, #2E7D32);
        border: none;
        border-radius: 8px;
        color: white;
        cursor: pointer;
        font-weight: bold;
        font-size: 16px;
      ">Continue</button>
    </div>
  `);
}

/**
 * Upgrade a random dice face by increasing its value
 * @param {string} characterKey - The character key
 * @returns {string|null} Description of upgrade or null
 */
function upgradeDiceFace(characterKey) {
  const characterData = PLAYER_CHARACTERS[characterKey];
  if (!characterData || !characterData.dice) return null;

  // Find faces with numeric values that can be upgraded
  const upgradableFaces = [];
  characterData.dice.forEach((face, index) => {
    if (!face.isBlank && face.effects) {
      face.effects.forEach((effect, effectIndex) => {
        if (effect.value && typeof effect.value === 'number') {
          upgradableFaces.push({ faceIndex: index, effectIndex, effect });
        }
      });
    }
  });

  if (upgradableFaces.length === 0) return null;

  // Pick a random face to upgrade
  const chosen = upgradableFaces[Math.floor(Math.random() * upgradableFaces.length)];
  const oldValue = chosen.effect.value;

  // Upgrade the face
  characterData.dice[chosen.faceIndex].effects[chosen.effectIndex].value++;

  // Update the raw text
  const effect = characterData.dice[chosen.faceIndex].effects[chosen.effectIndex];
  const addonsStr = effect.addons && effect.addons.length > 0 ? ' ' + effect.addons.join(' ') : '';
  const targetStr = effect.target ? ' ' + effect.target : '';
  characterData.dice[chosen.faceIndex].effects[chosen.effectIndex].raw =
    `${effect.value} ${effect.move}${targetStr}${addonsStr}`;
  characterData.dice[chosen.faceIndex].raw =
    characterData.dice[chosen.faceIndex].effects.map(e => e.raw).join(', ');

  return `Dice upgraded: ${effect.move} ${oldValue} → ${effect.value}`;
}

/**
 * Generate level-up options for dice
 * @param {string} characterKey - The character key
 * @returns {Array} Array of upgrade options
 */
function generateDiceLevelUpOptions(characterKey) {
  const characterData = PLAYER_CHARACTERS[characterKey];
  if (!characterData || !characterData.dice) return [];

  const options = [];
  const luckValue = typeof luck !== 'undefined' ? luck : 0;

  // Find blank faces and upgradeable faces
  const blankFaces = [];
  const upgradableFaces = [];

  characterData.dice.forEach((face, index) => {
    if (face.isBlank) {
      blankFaces.push({ faceIndex: index, face });
    } else if (face.effects) {
      face.effects.forEach((effect, effectIndex) => {
        if (effect.value && typeof effect.value === 'number') {
          upgradableFaces.push({ faceIndex: index, effectIndex, effect, face });
        }
      });
    }
  });

  // Generate options - prioritize blank faces if available
  const hasBlankFace = blankFaces.length > 0;

  // If there's a blank face, at least one option should be adding a new side
  if (hasBlankFace) {
    const blankFace = blankFaces[Math.floor(Math.random() * blankFaces.length)];
    const newSideOption = generateNewSideOption(blankFace.faceIndex, luckValue);
    if (newSideOption) {
      options.push(newSideOption);
    }
  }

  // Fill remaining options with number upgrades (shuffle and pick)
  const shuffledUpgrades = upgradableFaces.sort(() => Math.random() - 0.5);
  for (const upgrade of shuffledUpgrades) {
    if (options.length >= 3) break;

    // Don't add duplicate face upgrades
    const alreadyHasFace = options.some(o => o.type === 'upgrade' && o.faceIndex === upgrade.faceIndex);
    if (alreadyHasFace) continue;

    options.push({
      type: 'upgrade',
      faceIndex: upgrade.faceIndex,
      effectIndex: upgrade.effectIndex,
      effect: upgrade.effect,
      face: upgrade.face,
      description: `+1 to ${upgrade.effect.move}`,
      before: upgrade.effect.value,
      after: upgrade.effect.value + 1
    });
  }

  // If we still need more options and have more blank faces, add them
  if (options.length < 3 && blankFaces.length > 1) {
    for (const blank of blankFaces) {
      if (options.length >= 3) break;
      const alreadyHasFace = options.some(o => o.faceIndex === blank.faceIndex);
      if (alreadyHasFace) continue;

      const newSideOption = generateNewSideOption(blank.faceIndex, luckValue);
      if (newSideOption) {
        options.push(newSideOption);
      }
    }
  }

  // If still under 3 options and we have upgradeable faces, add more upgrade variants
  // (different amount upgrades or duplicates with slight variations)
  while (options.length < 3 && upgradableFaces.length > 0) {
    const randomUpgrade = upgradableFaces[Math.floor(Math.random() * upgradableFaces.length)];
    options.push({
      type: 'upgrade',
      faceIndex: randomUpgrade.faceIndex,
      effectIndex: randomUpgrade.effectIndex,
      effect: randomUpgrade.effect,
      face: randomUpgrade.face,
      description: `+1 to ${randomUpgrade.effect.move}`,
      before: randomUpgrade.effect.value,
      after: randomUpgrade.effect.value + 1
    });
  }

  return options.slice(0, 3);
}

/**
 * Generate a new side option for a blank face
 * @param {number} faceIndex - Index of the blank face
 * @param {number} luckValue - Player's luck stat
 * @returns {Object} New side option
 */
function generateNewSideOption(faceIndex, luckValue) {
  // Get available moves for level-up (excluding special ones like spawn, alter)
  const levelUpMoves = ['dmg', 'block', 'heal', 'reroll', 'mana', 'get', 'inflict'];

  // Select a random move
  const selectedMove = levelUpMoves[Math.floor(Math.random() * levelUpMoves.length)];
  const moveData = MOVES_DATA ? MOVES_DATA[selectedMove] : null;

  // Determine base value based on rarity (affected by luck)
  const rarity = selectRandomRarity ? selectRandomRarity(luckValue) : 'common';
  let baseValue = 1;
  switch (rarity) {
    case 'uncommon': baseValue = 2; break;
    case 'rare': baseValue = 3; break;
    case 'legendary': baseValue = 4; break;
    default: baseValue = 1;
  }

  // Handle status moves (Get = buff, Inflict = debuff)
  let statusName = null;
  if (selectedMove === 'get' || selectedMove === 'inflict') {
    const isDebuff = selectedMove === 'inflict';
    const statuses = STATUSES_DATA ? Object.values(STATUSES_DATA) : [];

    // Filter by type
    const filteredStatuses = statuses.filter(s => {
      if (isDebuff) {
        return s.type === 'Debuff' || s.preference === 'Negative';
      } else {
        return s.type === 'Buff' || s.preference === 'Positive';
      }
    });

    if (filteredStatuses.length > 0) {
      const selectedStatus = filteredStatuses[Math.floor(Math.random() * filteredStatuses.length)];
      statusName = selectedStatus.name;
    } else {
      statusName = isDebuff ? 'Burn' : 'Power';
    }
  }

  // Build the effect description
  let effectDescription;
  let effectRaw;
  if (statusName) {
    effectDescription = `${baseValue} ${selectedMove.charAt(0).toUpperCase() + selectedMove.slice(1)} ${statusName}`;
    effectRaw = `${baseValue} ${selectedMove} ${statusName}`;
  } else {
    effectDescription = `${baseValue} ${moveData ? moveData.name : selectedMove.charAt(0).toUpperCase() + selectedMove.slice(1)}`;
    effectRaw = `${baseValue} ${selectedMove}`;
  }

  return {
    type: 'newSide',
    faceIndex: faceIndex,
    move: selectedMove,
    value: baseValue,
    statusName: statusName,
    rarity: rarity,
    description: `Add ${effectDescription}`,
    effectRaw: effectRaw,
    moveData: moveData
  };
}

/**
 * Apply a dice level-up option
 * @param {Object} option - The selected option
 * @param {string} characterKey - The character key
 * @returns {string} Description of what was applied
 */
function applyDiceLevelUpOption(option, characterKey) {
  const characterData = PLAYER_CHARACTERS[characterKey];
  if (!characterData || !characterData.dice) return null;

  if (option.type === 'upgrade') {
    // Upgrade existing face value
    const oldValue = option.effect.value;
    characterData.dice[option.faceIndex].effects[option.effectIndex].value++;

    // Update raw text
    const effect = characterData.dice[option.faceIndex].effects[option.effectIndex];
    const addonsStr = effect.addons && effect.addons.length > 0 ? ' ' + effect.addons.join(' ') : '';
    const targetStr = effect.target ? ' ' + effect.target : '';
    characterData.dice[option.faceIndex].effects[option.effectIndex].raw =
      `${effect.value} ${effect.move}${targetStr}${addonsStr}`;
    characterData.dice[option.faceIndex].raw =
      characterData.dice[option.faceIndex].effects.map(e => e.raw).join(', ');

    return `Dice upgraded: ${effect.move} ${oldValue} → ${effect.value}`;
  } else if (option.type === 'newSide') {
    // Add new side to blank face
    const newEffect = {
      move: option.move,
      value: option.value,
      raw: option.effectRaw
    };

    if (option.statusName) {
      newEffect.status = option.statusName;
    }

    // Determine target based on move type
    if (option.moveData && option.moveData.preferredTarget) {
      if (option.moveData.preferredTarget === 'Enemy') {
        newEffect.target = 'enemy';
      } else if (option.moveData.preferredTarget === 'Ally/Self') {
        newEffect.target = 'self';
      }
    }

    // Update the face
    characterData.dice[option.faceIndex] = {
      isBlank: false,
      effects: [newEffect],
      raw: option.effectRaw
    };

    return `New dice side: ${option.description}`;
  }

  return null;
}

/**
 * Show dice level-up choice modal
 * @param {string} characterKey - The character key
 * @param {Function} onComplete - Callback when selection is complete
 */
function showDiceLevelUpChoiceModal(characterKey, onComplete) {
  const options = generateDiceLevelUpOptions(characterKey);

  if (options.length === 0) {
    // No options available, skip dice upgrade
    if (onComplete) onComplete(null);
    return;
  }

  const getRarityColor = (rarity) => {
    switch (rarity?.toLowerCase()) {
      case 'legendary': return '#ff6b00';
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      default: return '#aaa';
    }
  };

  const optionsHTML = options.map((opt, idx) => {
    let previewHTML = '';
    let rarityBadge = '';

    if (opt.type === 'upgrade') {
      // Show before → after
      previewHTML = `
        <div style="display: flex; align-items: center; gap: 10px; justify-content: center; margin-top: 10px;">
          <div style="background: rgba(255,100,100,0.2); border: 2px solid #666; border-radius: 8px; padding: 10px; min-width: 80px; text-align: center;">
            <div style="font-size: 12px; color: #888; margin-bottom: 4px;">Before</div>
            <div style="font-size: 20px; color: #ff6666; font-weight: bold;">${opt.before}</div>
            <div style="font-size: 11px; color: #aaa;">${opt.effect.move}</div>
          </div>
          <div style="font-size: 24px; color: #FFD700;">→</div>
          <div style="background: rgba(100,255,100,0.2); border: 2px solid #4CAF50; border-radius: 8px; padding: 10px; min-width: 80px; text-align: center;">
            <div style="font-size: 12px; color: #888; margin-bottom: 4px;">After</div>
            <div style="font-size: 20px; color: #4CAF50; font-weight: bold;">${opt.after}</div>
            <div style="font-size: 11px; color: #aaa;">${opt.effect.move}</div>
          </div>
        </div>
      `;
    } else if (opt.type === 'newSide') {
      // Show new side preview
      const rarityColor = getRarityColor(opt.rarity);
      rarityBadge = `<span style="background: ${rarityColor}; color: white; padding: 2px 8px; border-radius: 4px; font-size: 10px; text-transform: uppercase; margin-left: 8px;">${opt.rarity}</span>`;
      previewHTML = `
        <div style="display: flex; align-items: center; gap: 10px; justify-content: center; margin-top: 10px;">
          <div style="background: rgba(100,100,100,0.2); border: 2px dashed #666; border-radius: 8px; padding: 10px; min-width: 80px; text-align: center;">
            <div style="font-size: 12px; color: #888; margin-bottom: 4px;">Before</div>
            <div style="font-size: 20px; color: #666;">—</div>
            <div style="font-size: 11px; color: #666;">Blank</div>
          </div>
          <div style="font-size: 24px; color: #FFD700;">→</div>
          <div style="background: rgba(255,215,0,0.2); border: 2px solid ${rarityColor}; border-radius: 8px; padding: 10px; min-width: 80px; text-align: center;">
            <div style="font-size: 12px; color: #888; margin-bottom: 4px;">After</div>
            <div style="font-size: 20px; color: ${rarityColor}; font-weight: bold;">${opt.value}</div>
            <div style="font-size: 11px; color: #aaa;">${opt.statusName || opt.move}</div>
          </div>
        </div>
      `;
    }

    return `
      <div class="dice-levelup-option" data-option-index="${idx}" style="
        background: rgba(40,40,50,0.8);
        border: 2px solid #555;
        border-radius: 12px;
        padding: 15px;
        cursor: pointer;
        transition: all 0.2s;
        flex: 1;
        min-width: 200px;
        max-width: 280px;
      " onmouseenter="this.style.borderColor='#FFD700'; this.style.transform='translateY(-4px)';"
         onmouseleave="this.style.borderColor='#555'; this.style.transform='translateY(0)';">
        <div style="font-size: 14px; color: #FFD700; font-weight: bold; text-align: center;">
          Face ${opt.faceIndex + 1}${rarityBadge}
        </div>
        <div style="font-size: 13px; color: #ccc; text-align: center; margin-top: 5px;">
          ${opt.description}
        </div>
        ${previewHTML}
      </div>
    `;
  }).join('');

  const modalHTML = `
    <div style="text-align: center; padding: 20px; max-width: 900px;">
      <h2 style="color: #FFD700; margin-bottom: 10px;">🎲 Dice Level Up!</h2>
      <p style="color: #aaa; margin-bottom: 20px;">Choose an upgrade for your dice:</p>
      <div style="display: flex; gap: 15px; justify-content: center; flex-wrap: wrap; margin-bottom: 20px;">
        ${optionsHTML}
      </div>
    </div>
  `;

  createGameModal(modalHTML);

  // Attach click handlers
  document.querySelectorAll('.dice-levelup-option').forEach((el, idx) => {
    el.onclick = () => {
      const selectedOption = options[idx];
      const result = applyDiceLevelUpOption(selectedOption, characterKey);
      closeGameModal();
      if (onComplete) onComplete(result);
    };
  });
}

// Inline spell-learning used by card-acquire paths in this file.
// Intentionally self-contained so it works regardless of cards.js cache state.

// _doLearnSpell, showVictoryScreen, showCardRewardModal moved to
// js/cards.js as part of the Phase 3 decomposition.


// Make level-up functions globally available
window.showLevelUpPrompt = showLevelUpPrompt;
window.confirmLevelUp = confirmLevelUp;
window.showDiceLevelUpChoiceModal = showDiceLevelUpChoiceModal;

if (typeof window !== 'undefined') {
  window._cardPreviewBtn           = _cardPreviewBtn;
  window.showCardUpgradeZoom       = showCardUpgradeZoom;
  window.showCardZoomOverlay       = showCardZoomOverlay;
  window.showNotificationHistory   = showNotificationHistory;
  window.showDeckModal             = showDeckModal;
  window.showDiceTrayModal         = showDiceTrayModal;
  window.showSpellsModal           = showSpellsModal;
  window.confirmLevelUpLegacy      = confirmLevelUpLegacy;
  window.upgradeDiceFace           = upgradeDiceFace;
  window.generateDiceLevelUpOptions = generateDiceLevelUpOptions;
  window.generateNewSideOption     = generateNewSideOption;
  window.applyDiceLevelUpOption    = applyDiceLevelUpOption;
  // showLevelUpPrompt / confirmLevelUp / showDiceLevelUpChoiceModal
  // already re-exported via the inline window.* block at the bottom of
  // the extracted code.
}
