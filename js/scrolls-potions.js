// ===== SCROLLS-POTIONS.JS =====
// Manages the Scrolls and Potions loot system.
//
// Scrolls: usable outside combat, trigger 2-roll INT system (DC 10 + crit check)
// Potions: usable inside combat, full target picker (player / allies / enemies)
// Both are stored in gameState.loot as { type:'scroll'|'potion', name, rarity }
// Identification is global per-type: gameState.identifiedScrollTypes / identifiedPotionTypes


// ========================================
// RARITY HELPERS
// ========================================

// RARITY_COLORS is defined in constants.js — do not redeclare here

const RARITY_BORDER = {
  Common:    '#888',
  Uncommon:  '#4CAF50',
  Rare:      '#9b59b6',
  Legendary: '#ff6b00'
};

function _rarityColor(r) { return (window.RARITY_COLORS || {})[r] || '#aaa'; }
function _rarityBorder(r) { return RARITY_BORDER[r] || '#888'; }

// ========================================
// IDENTIFICATION STATE
// ========================================

function getIdentifiedScrollTypes() {
  if (!gameState.identifiedScrollTypes) gameState.identifiedScrollTypes = [];
  return gameState.identifiedScrollTypes;
}

function getIdentifiedPotionTypes() {
  if (!gameState.identifiedPotionTypes) gameState.identifiedPotionTypes = [];
  return gameState.identifiedPotionTypes;
}

function isScrollIdentified(name) {
  return getIdentifiedScrollTypes().includes(name);
}

function isPotionIdentified(name) {
  return getIdentifiedPotionTypes().includes(name);
}

function identifyScrollType(name) {
  const list = getIdentifiedScrollTypes();
  if (!list.includes(name)) {
    list.push(name);
    gameState.identifiedScrollTypes = list;
    if (typeof saveCurrentGame === 'function') saveCurrentGame();
    if (typeof createNotification === 'function') {
      createNotification(`Identified: ${name}!`, '#9b59b6', '📜');
    }
  }
}

function identifyPotionType(name) {
  const list = getIdentifiedPotionTypes();
  if (!list.includes(name)) {
    list.push(name);
    gameState.identifiedPotionTypes = list;
    if (typeof saveCurrentGame === 'function') saveCurrentGame();
    if (typeof createNotification === 'function') {
      createNotification(`Identified: ${name}!`, '#3498db', '🧪');
    }
  }
}

function unidentifyScrollType(name) {
  const list = getIdentifiedScrollTypes();
  const idx = list.indexOf(name);
  if (idx !== -1) {
    list.splice(idx, 1);
    gameState.identifiedScrollTypes = list;
  }
}

function unidentifyPotionType(name) {
  const list = getIdentifiedPotionTypes();
  const idx = list.indexOf(name);
  if (idx !== -1) {
    list.splice(idx, 1);
    gameState.identifiedPotionTypes = list;
  }
}

// ========================================
// DISPLAY NAMES / IMAGES
// ========================================

function getScrollDisplayName(scrollName) {
  return isScrollIdentified(scrollName) ? scrollName : 'Unidentified Scroll';
}

function getScrollImagePath(scrollData) {
  if (isScrollIdentified(scrollData.name) && scrollData.file) {
    return `images/scrolls/${scrollData.file}.png`;
  }
  return 'images/scrolls/Unidentified.png';
}

function getPotionDisplayName(potionName) {
  return isPotionIdentified(potionName) ? potionName : 'Unidentified Potion';
}

function getPotionImagePath(potionData) {
  if (isPotionIdentified(potionData.name) && potionData.file) {
    return `images/potions/${potionData.file}.png`;
  }
  return 'images/potions/Unidentified.png';
}

// ========================================
// LOOT SELECTION (post-combat reward)
// ========================================

function selectRandomPotionOrScroll() {
  const rarity = selectRandomRarity();
  const rarityLabel = rarity.charAt(0).toUpperCase() + rarity.slice(1);

  // 50/50 chance between potion pool and scroll pool
  const usePotion = Math.random() < 0.5;

  const pool = usePotion ? POTIONS_DATA : SCROLLS_DATA;
  const matching = pool.filter(p => p.rarity.toLowerCase() === rarity);
  const candidates = matching.length > 0 ? matching : pool;

  const chosen = candidates[Math.floor(Math.random() * candidates.length)];

  if (usePotion) {
    return { type: 'potion', name: chosen.name, rarity: chosen.rarity };
  } else {
    return { type: 'scroll', name: chosen.name, rarity: chosen.rarity };
  }
}

// ========================================
// ADD TO LOOT
// ========================================

function addScrollOrPotionToLoot(item) {
  if (!gameState.loot) gameState.loot = [];
  gameState.loot.push(item);
  if (typeof updateLootDisplay === 'function') updateLootDisplay();
  if (typeof saveCurrentGame === 'function') saveCurrentGame();
}

// ========================================
// SCROLL ROLL SYSTEM
// ========================================

const SCROLL_CRIT_THRESHOLD_GOOD = 18; // 18/19/20 = crit success
const SCROLL_CRIT_THRESHOLD_BAD  = 3;  // 1/2/3 = crit fail
const SCROLL_DC = 10;

function _scrollRollD20() {
  const lv = typeof luck !== 'undefined' ? luck : 0;
  const a = Math.floor(Math.random() * 20) + 1;
  if (lv > 0 && Math.random() < lv * 0.1) {
    return Math.max(a, Math.floor(Math.random() * 20) + 1);
  }
  if (lv < 0 && Math.random() < Math.abs(lv) * 0.1) {
    return Math.min(a, Math.floor(Math.random() * 20) + 1);
  }
  return a;
}

function _resolveScrollOutcome(scrollData) {
  const intStat = typeof intelligence !== 'undefined' ? intelligence : 0;
  const roll1 = _scrollRollD20();
  const total1 = roll1 + intStat;
  const success = total1 >= SCROLL_DC;

  const roll2 = _scrollRollD20();
  const isCrit = success ? roll2 >= SCROLL_CRIT_THRESHOLD_GOOD : roll2 <= SCROLL_CRIT_THRESHOLD_BAD;

  let outcomeKey;
  if (success && isCrit)       outcomeKey = 'crit_good';
  else if (success)            outcomeKey = 'good';
  else if (!success && isCrit) outcomeKey = 'crit_bad';
  else                         outcomeKey = 'bad';

  return { roll1, total1, intStat, success, roll2, isCrit, outcomeKey };
}

// ========================================
// SCROLL USE — show result modal and apply
// ========================================

function useScrollFromLoot(lootIndex) {
  if (!gameState.loot || !gameState.loot[lootIndex]) return;
  const lootItem = gameState.loot[lootIndex];
  if (lootItem.type !== 'scroll') return;

  // Must be outside combat
  if (gameState.phase === 'combat') {
    if (typeof createNotification === 'function') {
      createNotification('Scrolls can only be used outside of combat!', '#e74c3c', '📜');
    }
    return;
  }

  const scrollData = SCROLLS_DATA.find(s => s.name === lootItem.name);
  if (!scrollData) return;

  // Identify on use
  identifyScrollType(lootItem.name);

  // Roll automatically
  const rollResult = _resolveScrollOutcome(scrollData);
  const outcomeKey = rollResult.outcomeKey;
  const outcomeText = scrollData.outcomes[outcomeKey] || 'Nothing happens.';

  const outcomeLabels = {
    crit_good: 'Critical Success',
    good:      'Success',
    bad:       'Failure',
    crit_bad:  'Critical Failure'
  };
  const outcomeColors = {
    crit_good: '#f1c40f',
    good:      '#2ecc71',
    bad:       '#e67e22',
    crit_bad:  '#e74c3c'
  };

  const label = outcomeLabels[outcomeKey];
  const color = outcomeColors[outcomeKey];

  const successStr = rollResult.success
    ? `${rollResult.roll1} + ${rollResult.intStat} INT = ${rollResult.total1} ≥ DC ${SCROLL_DC} ✓`
    : `${rollResult.roll1} + ${rollResult.intStat} INT = ${rollResult.total1} < DC ${SCROLL_DC} ✗`;
  const critStr = rollResult.isCrit
    ? `Rolled ${rollResult.roll2} — Critical!`
    : `Rolled ${rollResult.roll2} — Not Critical`;

  // Log to history before removing from loot
  if (typeof encounterHistory !== 'undefined') {
    encounterHistory.push({
      type: 'scroll',
      name: lootItem.name,
      outcome: label,
      timestamp: new Date().toLocaleString()
    });
    if (typeof updateEncounterHistory === 'function') updateEncounterHistory();
  }

  // Remove from loot first
  gameState.loot.splice(lootIndex, 1);
  if (typeof saveCurrentGame === 'function') saveCurrentGame();

  // Show result modal, then apply effect
  const modalHTML = `
    <div style="text-align:center; padding:10px;">
      <h2 style="color:#9b59b6; margin-top:0;">📜 ${lootItem.name}</h2>
      <div style="color:${color}; font-size:22px; font-weight:bold; margin:12px 0;
        text-shadow:0 0 16px ${color}88;">${label}</div>
      <div style="color:#aaa; font-size:13px; margin-bottom:4px;">${successStr}</div>
      <div style="color:#aaa; font-size:13px; margin-bottom:16px;">${critStr}</div>
      <div style="background:rgba(255,255,255,0.06); border-radius:8px; padding:14px;
        color:#ddd; font-size:14px; line-height:1.6; margin-bottom:20px; text-align:left;">
        ${outcomeText}
      </div>
      <div id="scroll-effect-area"></div>
      <button id="scroll-apply-btn" style="padding:12px 28px; background:${color};
        border:none; border-radius:8px; color:#000; font-weight:bold; font-size:15px;
        cursor:pointer;">Apply Effect →</button>
    </div>
  `;

  if (typeof createGameModal === 'function') {
    createGameModal(modalHTML);
  }

  // Wire up apply button
  setTimeout(() => {
    const btn = document.getElementById('scroll-apply-btn');
    if (btn) {
      btn.onclick = () => {
        closeGameModal();
        _applyScrollEffect(scrollData, outcomeKey, lootItem.rarity);
        if (typeof updateLootDisplay === 'function') updateLootDisplay();
      };
    }
  }, 50);
}

// ========================================
// SCROLL EFFECT HANDLERS
// ========================================

function _applyScrollEffect(scrollData, outcomeKey, rarity) {
  const name = scrollData.name;

  switch (name) {
    case 'Scroll of Teleportation': _scrollTeleport(outcomeKey); break;
    case 'Scroll of Identify':      _scrollIdentify(outcomeKey); break;
    case 'Scroll of Create Monster': _scrollCreateMonster(outcomeKey); break;
    case 'Scroll of Vorpalize Weapon': _scrollVorpalizeWeapon(outcomeKey); break;
    case 'Scroll of Scare Monster': _scrollScareMonster(outcomeKey); break;
    case 'Blank Scroll':            /* nothing */ break;
    case 'Scroll of Enchant Weapon': _scrollEnchantWeapon(outcomeKey); break;
    case 'Scroll of Sleep':         _scrollSleep(outcomeKey); break;
    case 'Scroll of Aggravate Monsters': _scrollAggravate(outcomeKey); break;
    case 'Scroll of Fire':          _scrollFire(outcomeKey); break;
    case 'Scroll of Amnesia':       _scrollAmnesia(outcomeKey); break;
    case 'Scroll of Create Food':   _scrollCreateFood(outcomeKey); break;
    default: break;
  }
}

// --- Teleportation ---
function _scrollTeleport(outcomeKey) {
  if (!gameState.amuletGame) {
    // Fallback: random teleport
    if (typeof teleportToRandomGame === 'function') teleportToRandomGame();
    return;
  }

  const amuletName = typeof gameState.amuletGame === 'string'
    ? gameState.amuletGame : gameState.amuletGame.name;
  const currentGame = gameState.currentGame;

  // Get all connected games except current
  const allGames = typeof games !== 'undefined' ? games.filter(g => g.connected && g.name !== currentGame) : [];
  if (allGames.length === 0) {
    if (typeof createNotification === 'function') createNotification('No connected games to teleport to!', '#e74c3c', '📜');
    return;
  }

  // Calculate BFS distances
  const bfsFn = typeof bfsCached === 'function' ? bfsCached : (typeof bfs === 'function' ? bfs : null);
  const currentDist = bfsFn ? bfsFn(currentGame, amuletName) : 0;

  let pool;
  if (outcomeKey === 'crit_bad') {
    pool = allGames;
  } else {
    const candidates = allGames.map(g => {
      const d = bfsFn ? bfsFn(g.name, amuletName) : 0;
      return { game: g, dist: d };
    });

    if (outcomeKey === 'crit_good') {
      // Closer: dist < currentDist, within 3 steps
      pool = candidates.filter(c => c.dist < currentDist && (currentDist - c.dist) <= 3).map(c => c.game);
      if (pool.length === 0) pool = candidates.filter(c => c.dist < currentDist).map(c => c.game);
      if (pool.length === 0) pool = allGames; // fallback
    } else if (outcomeKey === 'good') {
      // Same distance
      pool = candidates.filter(c => c.dist === currentDist).map(c => c.game);
      if (pool.length === 0) pool = allGames;
    } else {
      // Farther: dist > currentDist, within 3 steps farther
      pool = candidates.filter(c => c.dist > currentDist && (c.dist - currentDist) <= 3).map(c => c.game);
      if (pool.length === 0) pool = candidates.filter(c => c.dist > currentDist).map(c => c.game);
      if (pool.length === 0) pool = allGames;
    }
  }

  const target = pool[Math.floor(Math.random() * pool.length)];
  if (target && typeof advance === 'function') {
    advance(target.name, 450, (gameState.currentY || 0) + 200, null);
  }
}

// --- Identify ---
function _scrollIdentify(outcomeKey) {
  const unidentifiedScrolls = (gameState.loot || [])
    .filter(l => l.type === 'scroll' && !isScrollIdentified(l.name))
    .map(l => l.name)
    .filter((v, i, a) => a.indexOf(v) === i); // unique names

  if (outcomeKey === 'crit_good') {
    unidentifiedScrolls.forEach(n => identifyScrollType(n));
    if (typeof createNotification === 'function') createNotification('All scrolls identified!', '#f1c40f', '📜');
  } else if (outcomeKey === 'crit_bad') {
    if (unidentifiedScrolls.length > 0) {
      const rand = unidentifiedScrolls[Math.floor(Math.random() * unidentifiedScrolls.length)];
      identifyScrollType(rand);
    }
  } else {
    // good: up to 3, bad: up to 1
    const maxChoose = outcomeKey === 'good' ? 3 : 1;
    if (unidentifiedScrolls.length === 0) {
      if (typeof createNotification === 'function') createNotification('No unidentified scrolls to identify.', '#888', '📜');
      return;
    }
    _showScrollIdentifyPicker(unidentifiedScrolls, maxChoose);
  }
}

function _showScrollIdentifyPicker(names, maxChoose) {
  let selected = [];
  const itemsHTML = names.map(name => `
    <div class="id-pick-item" data-name="${name}" style="
      cursor:pointer; padding:10px 14px; border-radius:6px; margin-bottom:6px;
      border:2px solid #555; background:#2a2a2a; color:#ddd; font-size:13px;
      transition:border-color 0.15s;
    " onclick="window._scrollIdPickToggle('${name}', ${maxChoose}, this)">
      📜 ${name}
    </div>
  `).join('');

  const html = `
    <div style="text-align:center; padding:10px;">
      <h3 style="color:#9b59b6; margin-top:0;">Identify Scrolls</h3>
      <p style="color:#aaa; font-size:13px;">Choose up to ${maxChoose} scroll${maxChoose > 1 ? 's' : ''} to identify.</p>
      <div style="max-height:260px; overflow-y:auto; margin-bottom:16px;">${itemsHTML}</div>
      <button onclick="window._scrollIdPickConfirm()" style="
        padding:10px 24px; background:#9b59b6; border:none; border-radius:6px;
        color:white; font-weight:bold; cursor:pointer;">Identify Selected</button>
    </div>
  `;

  if (typeof createGameModal === 'function') createGameModal(html);

  window._scrollIdPickToggle = (name, max, el) => {
    if (selected.includes(name)) {
      selected = selected.filter(n => n !== name);
      el.style.borderColor = '#555';
      el.style.background = '#2a2a2a';
    } else if (selected.length < max) {
      selected.push(name);
      el.style.borderColor = '#9b59b6';
      el.style.background = '#3a2a4a';
    }
  };
  window._scrollIdPickConfirm = () => {
    selected.forEach(n => identifyScrollType(n));
    delete window._scrollIdPickToggle;
    delete window._scrollIdPickConfirm;
    if (typeof closeGameModal === 'function') closeGameModal();
    if (typeof updateLootDisplay === 'function') updateLootDisplay();
  };
}

// --- Create Monster ---
function _scrollCreateMonster(outcomeKey) {
  if (!window.ENEMIES_DATA) return;
  const counts = { crit_good: 1, good: 1, bad: 1, crit_bad: 2 };
  const maxWeights = { crit_good: 2, good: 3, bad: 5, crit_bad: 5 };

  const count = counts[outcomeKey] || 1;
  const maxW = maxWeights[outcomeKey] || 5;

  if (!gameState.pendingSpawnEnemies) gameState.pendingSpawnEnemies = [];

  for (let i = 0; i < count; i++) {
    const eligible = ENEMIES_DATA.filter(e => e.weight != null && e.weight <= maxW);
    if (eligible.length === 0) continue;
    const chosen = eligible[Math.floor(Math.random() * eligible.length)];
    gameState.pendingSpawnEnemies.push({ enemy: chosen.name, min: 1, max: 1 });
  }

  const plural = count > 1 ? 'enemies' : 'enemy';
  if (typeof createNotification === 'function') {
    createNotification(`${count} extra ${plural} added to next combat!`, '#e74c3c', '👹');
  }
}

// --- Vorpalize Weapon ---
function _scrollVorpalizeWeapon(outcomeKey) {
  const weaponCards = (gameState.deck || []).filter((c, i) => {
    const tags = Array.isArray(c.tags) ? c.tags : [];
    return tags.includes('weapon') && (c.type || '').toLowerCase() === 'attack';
  });

  if (weaponCards.length === 0) {
    if (typeof createNotification === 'function') createNotification('No Weapon Attack Cards in deck!', '#888', '📜');
    return;
  }

  const addBonus = (outcomeKey === 'crit_good' || outcomeKey === 'bad');

  if (outcomeKey === 'crit_good' || outcomeKey === 'good') {
    _showWeaponCardPicker(weaponCards, (card) => {
      _applyVorpal(card, addBonus);
    }, 'Vorpalize a Weapon Attack Card');
  } else {
    const card = weaponCards[Math.floor(Math.random() * weaponCards.length)];
    _applyVorpal(card, addBonus);
    if (typeof createNotification === 'function') {
      createNotification(`${card.name} gained Vorpal${addBonus ? ' +5 Dmg' : ''}!`, '#f1c40f', '⚔️');
    }
  }
}

function _applyVorpal(card, addDmgBonus) {
  // Pick a random enemy type and weight for the Vorpal bonus
  const types = ['Strength', 'Dexterity', 'Intelligence', 'Charisma'];
  const vorpalType = types[Math.floor(Math.random() * types.length)];
  const vorpalWeight = Math.floor(Math.random() * 5) + 1;

  card.vorpal = { type: vorpalType, weight: vorpalWeight };
  if (addDmgBonus) card.vorpalDmgBonus = (card.vorpalDmgBonus || 0) + 5;

  // Update description to reflect upgrade
  const badge = ` [Vorpal vs ${vorpalType} W${vorpalWeight}${addDmgBonus ? ' +5' : ''}]`;
  card.name = card.name.replace(/ \[Vorpal[^\]]*\]/, '') + badge;
}

// --- Scare Monster ---
function _scrollScareMonster(outcomeKey) {
  if (!gameState.pendingEnemyStartStun) gameState.pendingEnemyStartStun = { count: 0, choose: 0, all: false };

  if (outcomeKey === 'crit_good') {
    gameState.pendingEnemyStartStun.all = true;
    if (typeof createNotification === 'function') createNotification('All enemies will be Stunned next combat!', '#f1c40f', '😱');
  } else if (outcomeKey === 'crit_bad') {
    gameState.pendingEnemyStartStun.count = (gameState.pendingEnemyStartStun.count || 0) + 1;
    if (typeof createNotification === 'function') createNotification('1 random enemy will be Stunned next combat!', '#2ecc71', '😱');
  } else {
    // good = choose up to 3, bad = choose 1 — picker shown at combat start
    const max = outcomeKey === 'good' ? 3 : 1;
    gameState.pendingEnemyStartStun.choose = (gameState.pendingEnemyStartStun.choose || 0) + max;
    if (typeof createNotification === 'function') {
      createNotification(`Choose up to ${max} enem${max > 1 ? 'ies' : 'y'} to Stun at combat start!`, '#2ecc71', '😱');
    }
  }
}

// --- Enchant Weapon ---
function _scrollEnchantWeapon(outcomeKey) {
  const weaponCards = (gameState.deck || []).filter(c => {
    const tags = Array.isArray(c.tags) ? c.tags : [];
    return tags.includes('weapon') && (c.type || '').toLowerCase() === 'attack';
  });

  if (weaponCards.length === 0) {
    if (typeof createNotification === 'function') createNotification('No Weapon Attack Cards in deck!', '#888', '📜');
    return;
  }

  const dmgBonus = (outcomeKey === 'crit_bad') ? 2 : 5;
  const addRetain = (outcomeKey === 'crit_good');

  if (outcomeKey === 'crit_good' || outcomeKey === 'good') {
    _showWeaponCardPicker(weaponCards, (card) => {
      _applyEnchant(card, dmgBonus, addRetain);
      if (typeof createNotification === 'function') {
        createNotification(`${card.name} enchanted!`, '#f1c40f', '⚔️');
      }
    }, `Enchant a Weapon Attack Card (+${dmgBonus} Dmg${addRetain ? ', Retain' : ''})`);
  } else {
    const card = weaponCards[Math.floor(Math.random() * weaponCards.length)];
    _applyEnchant(card, dmgBonus, addRetain);
    if (typeof createNotification === 'function') {
      createNotification(`${card.name} enchanted (+${dmgBonus} Dmg${addRetain ? ', Retain' : ''})!`, '#f1c40f', '⚔️');
    }
  }
}

function _applyEnchant(card, dmgBonus, addRetain) {
  card.enchantDmgBonus = (card.enchantDmgBonus || 0) + dmgBonus;
  if (addRetain) card.retain = true;

  // Append badge to name for display
  const retainStr = addRetain ? ' Retain' : '';
  const badge = ` [+${card.enchantDmgBonus} Dmg${retainStr}]`;
  card.name = card.name.replace(/ \[\+\d+ Dmg[^\]]*\]/, '') + badge;
}

// Helper: weapon card picker UI
function _showWeaponCardPicker(cards, onSelect, title) {
  const itemsHTML = cards.map((c, i) => `
    <div style="cursor:pointer; padding:10px 14px; border-radius:6px; margin-bottom:6px;
      border:2px solid #e67e22; background:#2a2a2a; color:#ddd; font-size:13px;
      transition:background 0.15s;"
      onmouseenter="this.style.background='#3a2a1a'" onmouseleave="this.style.background='#2a2a2a'"
      onclick="window._weaponPickSelect(${i})">
      ⚔️ ${c.name}
    </div>
  `).join('');

  const html = `
    <div style="text-align:center; padding:10px;">
      <h3 style="color:#e67e22; margin-top:0;">${title}</h3>
      <div style="max-height:260px; overflow-y:auto; margin-bottom:12px;">${itemsHTML}</div>
      <button onclick="closeGameModal(); delete window._weaponPickSelect;" style="
        padding:8px 20px; background:#555; border:none; border-radius:6px;
        color:#aaa; cursor:pointer;">Cancel</button>
    </div>
  `;

  if (typeof createGameModal === 'function') createGameModal(html);

  window._weaponPickSelect = (idx) => {
    delete window._weaponPickSelect;
    if (typeof closeGameModal === 'function') closeGameModal();
    onSelect(cards[idx]);
  };
}

// --- Sleep ---
function _scrollSleep(outcomeKey) {
  const healAmounts = { crit_good: 10, good: 0, bad: 0, crit_bad: 0 };
  const fearAmounts = { crit_good: 0, good: 0, bad: 1, crit_bad: 3 };
  const heal = healAmounts[outcomeKey] || 0;
  const fear = fearAmounts[outcomeKey] || 0;

  if (heal > 0) {
    if (typeof health !== 'undefined') {
      window.health = Math.min(health + heal, maxHealth || health + heal);
      gameState.health = window.health;
    }
    if (typeof updateTopBar === 'function') updateTopBar();
    if (typeof createNotification === 'function') createNotification(`Rested: +${heal} Health`, '#4CAF50', '😴');
  }

  if (fear > 0) {
    if (!gameState.pendingCombatStatuses) gameState.pendingCombatStatuses = [];
    gameState.pendingCombatStatuses.push({ status: 'fear', stacks: fear });
    if (typeof createNotification === 'function') createNotification(`Nightmare! +${fear} Fear next combat`, '#e74c3c', '😱');
  }

  // Always ambushed
  gameState.pendingAmbushed = (gameState.pendingAmbushed || 0) + 1;
  if (typeof createNotification === 'function') createNotification('You\'ll be Ambushed in your next Combat!', '#e67e22', '😴');
}

// --- Aggravate Monsters ---
function _scrollAggravate(outcomeKey) {
  const buffs = {
    crit_good: { power: 1, defense: 0 },
    good:      { power: 2, defense: 0 },
    bad:       { power: 3, defense: 0 },
    crit_bad:  { power: 3, defense: 3 }
  };
  const buff = buffs[outcomeKey] || { power: 0, defense: 0 };

  if (!gameState.pendingEnemyBuff) gameState.pendingEnemyBuff = { power: 0, defense: 0 };
  gameState.pendingEnemyBuff.power   = (gameState.pendingEnemyBuff.power || 0)   + buff.power;
  gameState.pendingEnemyBuff.defense = (gameState.pendingEnemyBuff.defense || 0) + buff.defense;

  const msg = `Enemies gain +${buff.power} Power${buff.defense > 0 ? ` and +${buff.defense} Defense` : ''} next combat!`;
  if (typeof createNotification === 'function') createNotification(msg, '#e74c3c', '👹');
}

// --- Fire ---
function _scrollFire(outcomeKey) {
  // Player takes 10 fire damage
  const dmg = 10;
  if (typeof health !== 'undefined') {
    window.health = Math.max(0, health - dmg);
    gameState.health = window.health;
    if (typeof updateTopBar === 'function') updateTopBar();
    if (typeof createNotification === 'function') createNotification(`Scroll of Fire dealt ${dmg} fire damage to you!`, '#e74c3c', '🔥');
  }

  // All enemies take 10 fire damage next combat
  gameState.pendingFireDamageAll = (gameState.pendingFireDamageAll || 0) + dmg;

  // Destroy items/scrolls/potions based on outcome
  if (outcomeKey === 'good' || outcomeKey === 'bad' || outcomeKey === 'crit_bad') {
    _destroyRandomItem();
  }
  if (outcomeKey === 'bad' || outcomeKey === 'crit_bad') {
    _destroyRandomLootOfType('scroll');
  }
  if (outcomeKey === 'crit_bad') {
    _destroyRandomLootOfType('potion');
  }
}

function _destroyRandomItem() {
  const inv = typeof inventory !== 'undefined' ? inventory : [];
  if (inv.length === 0) return;
  const idx = Math.floor(Math.random() * inv.length);
  const item = inv[idx];
  inv.splice(idx, 1);
  if (typeof gameState !== 'undefined') gameState.inventory = [...inv];
  if (typeof updateInventory === 'function') updateInventory();
  if (typeof createNotification === 'function') createNotification(`${item.name} was destroyed by fire!`, '#e74c3c', '🔥');
}

function _destroyRandomLootOfType(type) {
  if (!gameState.loot) return;
  const indices = gameState.loot.map((l, i) => l.type === type ? i : -1).filter(i => i !== -1);
  if (indices.length === 0) return;
  const idx = indices[Math.floor(Math.random() * indices.length)];
  const item = gameState.loot[idx];
  gameState.loot.splice(idx, 1);
  const label = type === 'scroll' ? getScrollDisplayName(item.name) : getPotionDisplayName(item.name);
  if (typeof createNotification === 'function') createNotification(`${label} was destroyed by fire!`, '#e74c3c', '🔥');
}

// --- Amnesia ---
function _scrollAmnesia(outcomeKey) {
  const identifiedScrolls = getIdentifiedScrollTypes().slice();
  const identifiedPotions = getIdentifiedPotionTypes().slice();

  if (outcomeKey === 'crit_good') {
    // Forget 1 of each
    if (identifiedScrolls.length > 0) {
      unidentifyScrollType(identifiedScrolls[Math.floor(Math.random() * identifiedScrolls.length)]);
    }
    if (identifiedPotions.length > 0) {
      unidentifyPotionType(identifiedPotions[Math.floor(Math.random() * identifiedPotions.length)]);
    }
  } else if (outcomeKey === 'good') {
    const picks = Math.min(2, identifiedScrolls.length);
    for (let i = 0; i < picks; i++) {
      const remaining = getIdentifiedScrollTypes();
      if (remaining.length > 0) unidentifyScrollType(remaining[Math.floor(Math.random() * remaining.length)]);
    }
    const ppicks = Math.min(2, identifiedPotions.length);
    for (let i = 0; i < ppicks; i++) {
      const remaining = getIdentifiedPotionTypes();
      if (remaining.length > 0) unidentifyPotionType(remaining[Math.floor(Math.random() * remaining.length)]);
    }
  } else if (outcomeKey === 'bad') {
    const picks = Math.min(3, identifiedScrolls.length);
    for (let i = 0; i < picks; i++) {
      const remaining = getIdentifiedScrollTypes();
      if (remaining.length > 0) unidentifyScrollType(remaining[Math.floor(Math.random() * remaining.length)]);
    }
    const ppicks = Math.min(3, identifiedPotions.length);
    for (let i = 0; i < ppicks; i++) {
      const remaining = getIdentifiedPotionTypes();
      if (remaining.length > 0) unidentifyPotionType(remaining[Math.floor(Math.random() * remaining.length)]);
    }
    _forgetRandomSpells(1);
  } else {
    // crit_bad: forget all
    gameState.identifiedScrollTypes = [];
    gameState.identifiedPotionTypes = [];
    _forgetRandomSpells(2);
    if (typeof createNotification === 'function') createNotification('All scroll and potion knowledge forgotten!', '#e74c3c', '🧠');
  }
}

function _forgetRandomSpells(count) {
  const spells = typeof gameState !== 'undefined' && Array.isArray(gameState.spells) ? gameState.spells : [];
  if (spells.length === 0) return;
  for (let i = 0; i < count; i++) {
    if (spells.length === 0) break;
    const idx = Math.floor(Math.random() * spells.length);
    const spell = spells.splice(idx, 1)[0];
    if (typeof createNotification === 'function') createNotification(`Forgot spell: ${spell.name}!`, '#e74c3c', '🧠');
  }
  gameState.spells = [...spells];
}

// --- Create Food ---
function _scrollCreateFood(outcomeKey) {
  const allItems = typeof items !== 'undefined' ? items : [];
  const foodItems = allItems.filter(i => Array.isArray(i.tags) && i.tags.includes('food'));
  if (foodItems.length === 0) {
    if (typeof createNotification === 'function') createNotification('No food items available!', '#888', '🍎');
    return;
  }

  const uncommonPlus = foodItems.filter(i => i.rarity === 'Uncommon' || i.rarity === 'Rare' || i.rarity === 'Legendary');
  const commonOnly = foodItems.filter(i => i.rarity === 'Common');

  if (outcomeKey === 'crit_bad') {
    // 1 random Common food
    const pool = commonOnly.length > 0 ? commonOnly : foodItems;
    const chosen = pool[Math.floor(Math.random() * pool.length)];
    _giveItem(chosen);
  } else if (outcomeKey === 'bad') {
    // 1 random food
    const chosen = foodItems[Math.floor(Math.random() * foodItems.length)];
    _giveItem(chosen);
  } else {
    // good: 2 random, crit_good: 2 Uncommon+
    const pool = (outcomeKey === 'crit_good' && uncommonPlus.length > 0) ? uncommonPlus : foodItems;
    const pick1 = pool[Math.floor(Math.random() * pool.length)];
    let pick2 = pool[Math.floor(Math.random() * pool.length)];
    let attempts = 0;
    while (pick2.name === pick1.name && pool.length > 1 && attempts++ < 20) {
      pick2 = pool[Math.floor(Math.random() * pool.length)];
    }

    _showFoodPicker([pick1, pick2]);
  }
}

function _showFoodPicker(choices) {
  const html = `
    <div style="text-align:center; padding:10px;">
      <h3 style="color:#4CAF50; margin-top:0;">🍎 Choose a Food Item</h3>
      <div style="display:flex; gap:16px; justify-content:center; flex-wrap:wrap; margin:16px 0;">
        ${choices.map((item, i) => `
          <div onclick="window._foodPickSelect(${i})" style="
            cursor:pointer; padding:14px; border-radius:8px; border:2px solid #4CAF50;
            background:#1a2a1a; min-width:120px; text-align:center;
            transition:background 0.15s;"
            onmouseenter="this.style.background='#2a3a2a'" onmouseleave="this.style.background='#1a2a1a'">
            <img src="${item.image || ''}" style="width:56px;height:56px;object-fit:contain;margin-bottom:8px;"
              onerror="this.style.display='none'">
            <div style="color:#ddd; font-size:13px; font-weight:bold;">${item.name}</div>
            <div style="color:#4CAF50; font-size:11px;">${item.rarity}</div>
          </div>
        `).join('')}
      </div>
    </div>
  `;

  if (typeof createGameModal === 'function') createGameModal(html);

  window._foodPickSelect = (idx) => {
    delete window._foodPickSelect;
    if (typeof closeGameModal === 'function') closeGameModal();
    _giveItem(choices[idx]);
  };
}

function _giveItem(item) {
  if (typeof inventory !== 'undefined') {
    inventory.push({ ...item });
    if (typeof gameState !== 'undefined') gameState.inventory = [...inventory];
    if (typeof updateInventory === 'function') updateInventory();
    if (typeof createNotification === 'function') createNotification(`Received: ${item.name}!`, '#4CAF50', '🍎');
  }
}

// ========================================
// POTION USE SYSTEM
// ========================================

function usePotionFromLoot(lootIndex) {
  if (!gameState.loot || !gameState.loot[lootIndex]) return;
  const lootItem = gameState.loot[lootIndex];
  if (lootItem.type !== 'potion') return;

  if (gameState.phase !== 'combat') {
    if (typeof createNotification === 'function') createNotification('Potions can only be used in combat!', '#e74c3c', '🧪');
    return;
  }

  const cs = typeof window.CombatEngine !== 'undefined' ? window.CombatEngine.getCombatState() : null;
  if (!cs) return;

  // Identify on use
  identifyPotionType(lootItem.name);

  // Show target picker
  _showPotionTargetPicker(lootIndex, lootItem.name, cs);
}

function _showPotionTargetPicker(lootIndex, potionName, cs) {
  const player = cs.player;
  const allies = (cs.allies || []).filter(a => a.isAlive);
  const enemies = (cs.enemies || []).filter(e => e.health > 0);

  let targetsHTML = `
    <div style="margin-bottom:10px;">
      <div style="color:#aaa; font-size:11px; font-weight:bold; margin-bottom:6px; text-transform:uppercase;">Player</div>
      <button onclick="window._potionTargetApply('player', -1)" style="
        width:100%; padding:10px 14px; background:#1a2a1a; border:2px solid #4CAF50;
        border-radius:6px; color:#ddd; cursor:pointer; font-size:13px; text-align:left; margin-bottom:4px;
        display:flex; align-items:center; gap:10px; transition:background 0.15s;"
        onmouseenter="this.style.background='#2a3a2a'" onmouseleave="this.style.background='#1a2a1a'">
        <span>🧑 You</span>
        <span style="margin-left:auto;color:#aaa;font-size:12px;">${player.health}/${player.maxHealth} HP</span>
      </button>
    </div>
  `;

  if (allies.length > 0) {
    targetsHTML += `<div style="color:#aaa; font-size:11px; font-weight:bold; margin-bottom:6px; text-transform:uppercase;">Allies</div>`;
    allies.forEach((ally, i) => {
      targetsHTML += `
        <button onclick="window._potionTargetApply('ally', ${i})" style="
          width:100%; padding:10px 14px; background:#1a2a1a; border:2px solid #3498db;
          border-radius:6px; color:#ddd; cursor:pointer; font-size:13px; text-align:left; margin-bottom:4px;
          display:flex; align-items:center; gap:10px; transition:background 0.15s;"
          onmouseenter="this.style.background='#1a2030'" onmouseleave="this.style.background='#1a2a1a'">
          ${ally.imageUrl ? `<img src="${ally.imageUrl}" style="width:32px;height:32px;object-fit:contain;" onerror="this.style.display='none'">` : '<span>🤝</span>'}
          <span>${ally.name}</span>
          <span style="margin-left:auto;color:#aaa;font-size:12px;">${ally.health}/${ally.maxHealth} HP</span>
        </button>
      `;
    });
  }

  if (enemies.length > 0) {
    targetsHTML += `<div style="color:#aaa; font-size:11px; font-weight:bold; margin:10px 0 6px; text-transform:uppercase;">Enemies</div>`;
    enemies.forEach((enemy, i) => {
      targetsHTML += `
        <button onclick="window._potionTargetApply('enemy', ${i})" style="
          width:100%; padding:10px 14px; background:#2a1a1a; border:2px solid #e74c3c;
          border-radius:6px; color:#ddd; cursor:pointer; font-size:13px; text-align:left; margin-bottom:4px;
          display:flex; align-items:center; gap:10px; transition:background 0.15s;"
          onmouseenter="this.style.background='#3a2a2a'" onmouseleave="this.style.background='#2a1a1a'">
          ${enemy.imageUrl ? `<img src="${enemy.imageUrl}" style="width:32px;height:32px;object-fit:contain;image-rendering:pixelated;" onerror="this.style.display='none'">` : '<span>👹</span>'}
          <span>${enemy.name}</span>
          <span style="margin-left:auto;color:#aaa;font-size:12px;">${enemy.health}/${enemy.maxHealth} HP</span>
        </button>
      `;
    });
  }

  const overlayId = 'potion-target-overlay';
  let existing = document.getElementById(overlayId);
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.id = overlayId;
  overlay.style.cssText = `
    position:fixed; inset:0; z-index:10000;
    background:rgba(0,0,0,0.82);
    display:flex; align-items:center; justify-content:center;
  `;
  overlay.innerHTML = `
    <div style="background:#1a1a2e; border-radius:12px; border:2px solid #9b59b6;
      padding:20px; min-width:300px; max-width:380px; max-height:80vh; overflow-y:auto;">
      <h3 style="color:#9b59b6; margin-top:0; text-align:center;">🧪 ${potionName}</h3>
      <p style="color:#aaa; font-size:12px; text-align:center; margin-bottom:14px;">Choose a target</p>
      ${targetsHTML}
      <button onclick="document.getElementById('${overlayId}')?.remove(); delete window._potionTargetApply;" style="
        width:100%; padding:10px; background:#444; border:none; border-radius:6px;
        color:#aaa; cursor:pointer; margin-top:6px;">Cancel</button>
    </div>
  `;
  document.body.appendChild(overlay);

  window._potionTargetApply = (targetType, targetIdx) => {
    delete window._potionTargetApply;
    document.getElementById(overlayId)?.remove();

    // Resolve target object
    let target;
    if (targetType === 'player') {
      target = cs.player;
    } else if (targetType === 'ally') {
      target = allies[targetIdx];
    } else {
      target = enemies[targetIdx];
    }

    if (!target) return;

    // Remove from loot
    gameState.loot.splice(lootIndex, 1);

    // Apply effect
    _applyPotionEffect(potionName, target, targetType, cs);

    // Log
    if (typeof encounterHistory !== 'undefined') {
      encounterHistory.push({
        type: 'potion',
        name: potionName,
        target: target.name || 'Player',
        timestamp: new Date().toLocaleString()
      });
      if (typeof updateEncounterHistory === 'function') updateEncounterHistory();
    }

    // Refresh combat UI
    if (window.CombatUI && typeof window.CombatUI.updateCombatDisplay === 'function') {
      window.CombatUI.updateCombatDisplay();
    }
    if (typeof saveCurrentGame === 'function') saveCurrentGame();
    if (typeof updateLootDisplay === 'function') updateLootDisplay();

    // Check if combat ended
    if (cs.enemies.every(e => e.health <= 0)) {
      cs.phase = 'victory';
      if (window.CombatUI && typeof window.CombatUI.checkCombatEnd === 'function') {
        window.CombatUI.checkCombatEnd();
      }
    }
  };
}

function _applyPotionEffect(potionName, target, targetType, cs) {
  const log = (msg) => {
    if (cs.log) cs.log.push({ message: msg, type: 'info' });
    if (typeof createNotification === 'function') createNotification(msg, '#9b59b6', '🧪');
  };

  const applyDamage = (tgt, dmg) => {
    let actual = dmg;
    if (tgt.block > 0) {
      const blocked = Math.min(tgt.block, dmg);
      tgt.block -= blocked;
      actual = dmg - blocked;
    }
    tgt.health = Math.max(0, tgt.health - actual);
    return actual;
  };

  switch (potionName) {
    case 'Fire Potion': {
      const dealt = applyDamage(target, 20);
      log(`Fire Potion dealt ${dealt} fire damage to ${target.name || 'target'}!`);
      break;
    }
    case 'Block Potion': {
      target.block = (target.block || 0) + 12;
      log(`Block Potion: +12 Block to ${target.name || 'target'}!`);
      break;
    }
    case 'Energy Potion': {
      // Energy only makes sense on the player
      cs.player.energy = Math.min((cs.player.energy || 0) + 2, (cs.player.maxEnergy || 99));
      log('Energy Potion: +2 Energy!');
      break;
    }
    case 'Weak Potion': {
      target.statuses = target.statuses || {};
      target.statuses['weak'] = (target.statuses['weak'] || 0) + 3;
      log(`Weak Potion: 3 Weak on ${target.name || 'target'}!`);
      break;
    }
    case 'Vulnerable Potion': {
      target.statuses = target.statuses || {};
      target.statuses['vulnerable'] = (target.statuses['vulnerable'] || 0) + 3;
      log(`Vulnerable Potion: 3 Vulnerable on ${target.name || 'target'}!`);
      break;
    }
    case 'Speed Potion': {
      target.statuses = target.statuses || {};
      target.statuses['defense'] = (target.statuses['defense'] || 0) + 5;
      // Track for 1-turn removal at end of player turn
      cs._speedDefense = (cs._speedDefense || 0) + 5;
      log(`Speed Potion: +5 Defense (1 turn) to ${target.name || 'target'}!`);
      break;
    }
    case 'Flex Potion': {
      target.statuses = target.statuses || {};
      target.statuses['power'] = (target.statuses['power'] || 0) + 5;
      // Track for 1-turn removal at end of player turn (combat-engine removes _flexPower)
      cs._flexPower = (cs._flexPower || 0) + 5;
      log(`Flex Potion: +5 Power (1 turn) to ${target.name || 'target'}!`);
      break;
    }
    case 'Fruit Juice': {
      // +5 max health and current health on target
      if (targetType === 'player') {
        const newMax = (window.maxHealth || cs.player.maxHealth) + 5;
        window.maxHealth = newMax;
        gameState.maxHealth = newMax;
        cs.player.maxHealth = newMax;
        const newHp = Math.min(cs.player.health + 5, newMax);
        cs.player.health = newHp;
        window.health = newHp;
        gameState.health = newHp;
        if (typeof updateTopBar === 'function') updateTopBar();
      } else {
        target.maxHealth = (target.maxHealth || target.health) + 5;
        target.health = Math.min(target.health + 5, target.maxHealth);
      }
      log(`Fruit Juice: +5 Max Health and Health to ${target.name || 'target'}!`);
      break;
    }
    case 'Dexterity Potion': {
      target.statuses = target.statuses || {};
      target.statuses['defense'] = (target.statuses['defense'] || 0) + 2;
      log(`Dexterity Potion: +2 Defense to ${target.name || 'target'}!`);
      break;
    }
    case 'Strength Potion': {
      target.statuses = target.statuses || {};
      target.statuses['power'] = (target.statuses['power'] || 0) + 2;
      log(`Strength Potion: +2 Power to ${target.name || 'target'}!`);
      break;
    }
    case 'Explosive Ampoule': {
      // 10 fire damage to all enemies (cleave)
      const allEnemies = cs.enemies.filter(e => e.health > 0);
      allEnemies.forEach(e => {
        const dealt = applyDamage(e, 10);
        if (cs.log) cs.log.push({ message: `Explosive Ampoule: ${dealt} fire damage to ${e.name}!`, type: 'info' });
      });
      if (typeof createNotification === 'function') createNotification('Explosive Ampoule: 10 fire damage to all enemies!', '#e67e22', '💥');
      break;
    }
    case 'Liquid Bronze': {
      target.statuses = target.statuses || {};
      target.statuses['thorns'] = (target.statuses['thorns'] || 0) + 3;
      log(`Liquid Bronze: +3 Thorns to ${target.name || 'target'}!`);
      break;
    }
    case 'Mana Potion': {
      cs.player.mana = (cs.player.mana || 0) + 3;
      if (typeof window.mana !== 'undefined') window.mana = cs.player.mana;
      log('Mana Potion: +3 Mana!');
      break;
    }
    default:
      break;
  }
}

// ========================================
// SCARE MONSTER — combat-start stun chooser
// ========================================

function _showCombatStunPicker(combatState, maxCount) {
  const living = combatState.enemies.filter(e => e.health > 0);
  if (living.length === 0) return;

  // If fewer enemies than max, just stun them all
  if (living.length <= maxCount) {
    living.forEach(e => { e.statuses = e.statuses || {}; e.statuses['stun'] = 1; });
    if (typeof createNotification === 'function') {
      createNotification(`All ${living.length} enem${living.length > 1 ? 'ies' : 'y'} stunned!`, '#f1c40f', '😱');
    }
    if (window.CombatUI && typeof window.CombatUI.updateCombatDisplay === 'function') window.CombatUI.updateCombatDisplay();
    return;
  }

  let chosen = [];

  function renderPicker() {
    const html = `
      <div style="text-align:center; padding:16px; min-width:280px;">
        <h3 style="color:#f1c40f; margin-top:0;">😱 Scare Monster</h3>
        <p style="color:#aaa; font-size:13px; margin-bottom:14px;">
          Choose up to <strong style="color:#f1c40f;">${maxCount}</strong> enem${maxCount > 1 ? 'ies' : 'y'} to Stun
          (${chosen.length}/${maxCount} chosen)
        </p>
        <div style="display:flex; flex-direction:column; gap:8px; margin-bottom:16px;">
          ${living.map((e, i) => {
            const isSel = chosen.includes(i);
            return `<div onclick="window._stunPickToggle(${i})" style="
              padding:10px 14px; border-radius:6px; cursor:pointer; user-select:none;
              border:2px solid ${isSel ? '#f1c40f' : '#555'};
              background:${isSel ? 'rgba(241,196,15,0.18)' : '#2a2a2a'};
              color:${isSel ? '#f1c40f' : '#ddd'}; font-size:14px; font-weight:bold;
              transition:all 0.12s;">
              ${isSel ? '⭐' : '👹'} ${e.name} <span style="font-size:11px;color:#888;">(${e.health} HP)</span>
            </div>`;
          }).join('')}
        </div>
        <button onclick="window._stunPickConfirm()" style="
          padding:10px 28px; background:#f1c40f; border:none; border-radius:6px;
          color:#000; font-weight:bold; font-size:14px; cursor:pointer;">
          Confirm${chosen.length > 0 ? ` (${chosen.length})` : ''}
        </button>
      </div>
    `;
    if (typeof createGameModal === 'function') createGameModal(html);

    window._stunPickToggle = (idx) => {
      if (chosen.includes(idx)) {
        chosen = chosen.filter(i => i !== idx);
      } else if (chosen.length < maxCount) {
        chosen.push(idx);
      }
      renderPicker();
    };

    window._stunPickConfirm = () => {
      delete window._stunPickToggle;
      delete window._stunPickConfirm;
      if (typeof closeGameModal === 'function') closeGameModal();
      chosen.forEach(idx => {
        const e = living[idx];
        e.statuses = e.statuses || {};
        e.statuses['stun'] = 1;
      });
      if (chosen.length > 0 && typeof createNotification === 'function') {
        createNotification(`${chosen.length} enem${chosen.length > 1 ? 'ies' : 'y'} stunned!`, '#f1c40f', '😱');
      }
      if (window.CombatUI && typeof window.CombatUI.updateCombatDisplay === 'function') window.CombatUI.updateCombatDisplay();
    };
  }

  renderPicker();
}

// ========================================
// APPLY PENDING COMBAT EFFECTS AT COMBAT START
// Called from combat-engine.js initCombat
// ========================================

function applyPendingScrollEffects(combatState) {
  // Enemy start stun
  if (gameState.pendingEnemyStartStun) {
    const stunData = gameState.pendingEnemyStartStun;
    const living = combatState.enemies.filter(e => e.health > 0);
    if (stunData.all) {
      living.forEach(e => { e.statuses = e.statuses || {}; e.statuses['stun'] = 1; });
    } else if ((stunData.choose || 0) > 0) {
      // Player chooses which enemies to stun — show picker after combat UI renders
      const chooseCount = stunData.choose;
      setTimeout(() => _showCombatStunPicker(combatState, chooseCount), 800);
    } else if (stunData.count > 0) {
      const shuffled = living.slice().sort(() => Math.random() - 0.5);
      shuffled.slice(0, stunData.count).forEach(e => { e.statuses = e.statuses || {}; e.statuses['stun'] = 1; });
    }
    gameState.pendingEnemyStartStun = null;
  }

  // Enemy power/defense buff
  if (gameState.pendingEnemyBuff) {
    const buff = gameState.pendingEnemyBuff;
    combatState.enemies.forEach(e => {
      e.statuses = e.statuses || {};
      if (buff.power) e.statuses['power'] = (e.statuses['power'] || 0) + buff.power;
      if (buff.defense) e.statuses['defense'] = (e.statuses['defense'] || 0) + buff.defense;
    });
    gameState.pendingEnemyBuff = null;
  }

  // Fire damage all enemies
  if (gameState.pendingFireDamageAll) {
    const dmg = gameState.pendingFireDamageAll;
    combatState.enemies.forEach(e => {
      let actual = dmg;
      if (e.block > 0) { const b = Math.min(e.block, dmg); e.block -= b; actual = dmg - b; }
      e.health = Math.max(0, e.health - actual);
      if (combatState.log) combatState.log.push({ message: `Scroll of Fire: ${actual} fire damage to ${e.name}!`, type: 'info' });
    });
    gameState.pendingFireDamageAll = 0;
  }
}

// ========================================
// EXPORTS
// ========================================

window.POTIONS_DATA = typeof POTIONS_DATA !== 'undefined' ? POTIONS_DATA : window.POTIONS_DATA;
window.SCROLLS_DATA = typeof SCROLLS_DATA !== 'undefined' ? SCROLLS_DATA : window.SCROLLS_DATA;

window.getIdentifiedScrollTypes   = getIdentifiedScrollTypes;
window.getIdentifiedPotionTypes   = getIdentifiedPotionTypes;
window.isScrollIdentified         = isScrollIdentified;
window.isPotionIdentified         = isPotionIdentified;
window.identifyScrollType         = identifyScrollType;
window.identifyPotionType         = identifyPotionType;
window.unidentifyScrollType       = unidentifyScrollType;
window.unidentifyPotionType       = unidentifyPotionType;
window.getScrollDisplayName       = getScrollDisplayName;
window.getScrollImagePath         = getScrollImagePath;
window.getPotionDisplayName       = getPotionDisplayName;
window.getPotionImagePath         = getPotionImagePath;
window.selectRandomPotionOrScroll = selectRandomPotionOrScroll;
window.addScrollOrPotionToLoot    = addScrollOrPotionToLoot;
window.useScrollFromLoot          = useScrollFromLoot;
window.usePotionFromLoot          = usePotionFromLoot;
window.applyPendingScrollEffects  = applyPendingScrollEffects;
window._rarityColor               = _rarityColor;
window._rarityBorder              = _rarityBorder;
