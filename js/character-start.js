/**
 * Character / start-game selection flow.
 *
 * Extracted from js/main.js as part of the Phase 3 decomposition.
 *
 * Owns the path from "press New Game" through to
 * "first encounter is rendered":
 *   - BFS distance helpers used to score and validate start/amulet pairs
 *     (bfsAllDistances, dagBranchScoreEarly)
 *   - The start-pick UI (showStartingChoiceModal) and its sub-flows
 *     (previewStartMap / backToStartChoice / confirmStartChoice)
 *   - The graph preview popup (showGameMapPreview / closeGameMapPreview /
 *     generateLayerPreview) — also reused from items.js (teleporter,
 *     poop selection) via window.showGameMapPreview
 *   - Run boot orchestration (runStartProgression, applyStartingBonus,
 *     completeGameStart)
 *
 * Module-level state (selectedCharacter etc.) lives in data.js with
 * the rest of the legacy globals.
 *
 * Phase 5 (ESM): the window.* exports go away in favor of named exports.
 */

// ===== CHARACTER SELECTION FUNCTIONS =====

// ===== STARTING GAME SELECTION =====

function bfsAllDistances(startName) {
  const dist = new Map();
  dist.set(startName, 0);
  const queue = [startName];
  let qi = 0;
  while (qi < queue.length) {
    const cur = queue[qi++];
    const curDist = dist.get(cur);
    const neighbors = typeof getGameConnections === 'function' ? getGameConnections(cur) : [];
    for (const nb of neighbors) {
      if (!dist.has(nb)) { dist.set(nb, curDist + 1); queue.push(nb); }
    }
  }
  return dist;
}

// Score a start→amulet pair by how many of the first earlyLayers have 2+ nodes in the
// shortest-path DAG. Pass dToAmuletCache to avoid re-running BFS from the amulet.
function dagBranchScoreEarly(dFromStart, amuletName, earlyLayers = 3, dToAmuletCache = null) {
  const amuletDist = dFromStart.get(amuletName);
  if (!amuletDist) return 0;
  const dToAmulet = dToAmuletCache || bfsAllDistances(amuletName);
  const countAtDepth = new Map();
  for (const [name, fromDist] of dFromStart) {
    if (fromDist === 0 || fromDist >= amuletDist || fromDist > earlyLayers) continue;
    const toDist = dToAmulet.get(name);
    if (toDist !== undefined && fromDist + toDist === amuletDist)
      countAtDepth.set(fromDist, (countAtDepth.get(fromDist) || 0) + 1);
  }
  let branched = 0;
  for (const c of countAtDepth.values()) if (c >= 2) branched++;
  return branched;
}

let _pendingStartOptions = null;

function confirmStartChoice(index) {
  if (!_pendingStartOptions) return;
  const { options, amulet, saveName } = _pendingStartOptions;
  const chosen = options[index];
  _pendingStartOptions = null;
  closeGameModal();
  completeGameStart(chosen.start, amulet, saveName, chosen.type);
}

function previewStartMap(index) {
  if (!_pendingStartOptions) return;
  const { options, amulet } = _pendingStartOptions;
  const opt = options[index];
  const startName = opt.start.name;
  const amuletName = amulet.name;
  const dFS = bfsAllDistances(startName);
  const shortestDist = dFS.get(amuletName) || 1;

  let html = '<div style="padding:12px;">';
  html += '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:10px;">';
  html += `<span style="color:var(--color-gold);font-weight:bold;font-size:14px;">${startName} → ${amuletName}</span>`;
  html += `<div style="display:flex;align-items:center;gap:8px;">
    <button onclick="zoomMap(0.8)" style="padding:4px 10px;background:#555;border:none;border-radius:4px;color:#fff;cursor:pointer;font-weight:bold;">−</button>
    <span id="map-zoom-level" style="color:#888;min-width:44px;text-align:center;">100%</span>
    <button onclick="zoomMap(1.25)" style="padding:4px 10px;background:#555;border:none;border-radius:4px;color:#fff;cursor:pointer;font-weight:bold;">+</button>
    <button onclick="resetMapZoom()" style="padding:4px 10px;background:#555;border:none;border-radius:4px;color:#fff;cursor:pointer;font-size:10px;">Reset</button>
    <button onclick="backToStartChoice()" style="padding:4px 14px;background:#444;border:none;border-radius:6px;color:#fff;cursor:pointer;font-weight:bold;">← Back</button>
  </div>`;
  html += '</div>';
  html += '<div id="map-view-container">';
  html += generateMapView(startName, amuletName, shortestDist);
  html += '</div></div>';

  createGameModal(html);
  currentMapZoom = 1.0;

  const pathData = findPathsUpToDistance(startName, amuletName, shortestDist);
  setTimeout(() => {
    const { gameToLayer } = reorganizeMapLayers(pathData);
    drawMapArrows(pathData, startName, amuletName, gameToLayer);
  }, 150);
}

function backToStartChoice() {
  if (!_pendingStartOptions) { closeGameModal(); return; }
  const { options, amulet, saveName } = _pendingStartOptions;
  showStartingChoiceModal(options, amulet, saveName);
}

// In-run map preview: shows the path from any game node to the amulet.
// returnFn is called when the player clicks "← Back"; pass null to just close.
let _previewMapReturnFn = null;

function showGameMapPreview(gameName, returnFn) {
  _previewMapReturnFn = returnFn || null;
  if (!gameState || !gameState.amuletGame) return;
  const amuletName = gameState.amuletGame.name;
  const dFS = bfsAllDistances(gameName);
  const shortestDist = dFS.get(amuletName) || 1;

  let html = '<div style="padding:12px;">';
  html += '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:10px;">';
  html += `<span style="color:var(--color-gold);font-weight:bold;font-size:14px;">${gameName} → ${amuletName}</span>`;
  html += `<div style="display:flex;align-items:center;gap:8px;">
    <button onclick="zoomMap(0.8)" style="padding:4px 10px;background:#555;border:none;border-radius:4px;color:#fff;cursor:pointer;font-weight:bold;">−</button>
    <span id="map-zoom-level" style="color:#888;min-width:44px;text-align:center;">100%</span>
    <button onclick="zoomMap(1.25)" style="padding:4px 10px;background:#555;border:none;border-radius:4px;color:#fff;cursor:pointer;font-weight:bold;">+</button>
    <button onclick="resetMapZoom()" style="padding:4px 10px;background:#555;border:none;border-radius:4px;color:#fff;cursor:pointer;font-size:10px;">Reset</button>
    <button onclick="closeGameMapPreview()" style="padding:4px 14px;background:#444;border:none;border-radius:6px;color:#fff;cursor:pointer;font-weight:bold;">← Back</button>
  </div>`;
  html += '</div><div id="map-view-container">';
  html += generateMapView(gameName, amuletName, shortestDist);
  html += '</div></div>';

  createGameModal(html);
  currentMapZoom = 1.0;

  const pathData = findPathsUpToDistance(gameName, amuletName, shortestDist);
  setTimeout(() => {
    const { gameToLayer } = reorganizeMapLayers(pathData);
    drawMapArrows(pathData, gameName, amuletName, gameToLayer);
  }, 150);
}

function closeGameMapPreview() {
  const fn = _previewMapReturnFn;
  _previewMapReturnFn = null;
  if (fn) fn(); else closeGameModal();
}

window.showGameMapPreview = showGameMapPreview;
window.closeGameMapPreview = closeGameMapPreview;

// Returns a compact vertical bar chart of shortest-path DAG layer widths.
function generateLayerPreview(startName, amuletName) {
  const dFS = bfsAllDistances(startName);
  const amuletDist = dFS.get(amuletName);
  if (!amuletDist) return '<div style="color:#888;font-size:11px;">No path</div>';
  const dTA = bfsAllDistances(amuletName);
  const countAtDepth = new Map();
  for (const [name, fromDist] of dFS) {
    if (fromDist === 0 || fromDist > amuletDist) continue;
    const toDist = dTA.get(name);
    if (toDist !== undefined && fromDist + toDist === amuletDist)
      countAtDepth.set(fromDist, (countAtDepth.get(fromDist) || 0) + 1);
  }
  const maxCount = Math.max(1, ...countAtDepth.values());
  let html = '<div style="display:flex;flex-direction:column;align-items:center;gap:2px;padding:6px 0;">';
  html += '<div style="background:var(--color-accent);border-radius:3px;padding:2px 8px;font-size:9px;font-weight:bold;color:#fff;min-width:60px;text-align:center;">START</div>';
  for (let d = 1; d <= amuletDist; d++) {
    html += '<div style="color:#444;font-size:9px;line-height:1;">↓</div>';
    if (d === amuletDist) {
      html += '<div style="background:var(--color-gold);border-radius:3px;padding:2px 8px;font-size:9px;font-weight:bold;color:#000;min-width:60px;text-align:center;">AMULET</div>';
    } else {
      const count = countAtDepth.get(d) || 1;
      const w = Math.max(40, Math.round((count / maxCount) * 120));
      const bg = count >= 3 ? '#2e7d32' : count === 2 ? '#388e3c' : '#333';
      const label = count > 1 ? count + ' paths' : '';
      html += `<div style="background:${bg};border-radius:2px;height:13px;width:${w}px;display:flex;align-items:center;justify-content:center;font-size:9px;color:${count > 1 ? '#a5d6a7' : '#555'};font-weight:bold;">${label}</div>`;
    }
  }
  html += '</div>';
  return html;
}

function showStartingChoiceModal(startOptions, amulet, saveName) {
  _pendingStartOptions = { options: startOptions, amulet, saveName };
  const typeColors = { Action: '#c0392b', Traditional: '#7d3c98', Strategy: '#1a5276', Deckbuilding: '#1e8449' };
  const bonusDesc  = { Action: '1 Weapon Reward', Traditional: '1 Item Reward', Strategy: '40 Gold', Deckbuilding: '1 Card Reward' };
  const panels = startOptions.map((opt, i) => {
    const col = typeColors[opt.type] || '#555';
    const dFS = bfsAllDistances(opt.start.name);
    const pathLen = dFS.get(amulet.name) || '?';
    return `
      <div style="background:#222;border:2px solid ${col};border-radius:10px;padding:16px 12px;width:190px;display:flex;flex-direction:column;align-items:center;gap:8px;box-sizing:border-box;">
        <div style="background:${col};border-radius:4px;padding:2px 12px;font-size:11px;font-weight:bold;color:#fff;">${opt.type}</div>
        <div style="font-weight:bold;color:#e6d5b8;font-size:13px;text-align:center;line-height:1.3;">${opt.start.name}</div>
        <div style="font-size:11px;color:#777;">${opt.start.year || ''}</div>
        <div style="font-size:11px;color:#aaa;">Shortest path: <strong style="color:var(--color-gold);">${pathLen} games</strong></div>
        ${generateLayerPreview(opt.start.name, amulet.name)}
        <button onclick="previewStartMap(${i})" style="padding:4px 0;background:#333;border:1px solid #555;border-radius:5px;color:#bbb;cursor:pointer;font-size:11px;width:100%;">View Map</button>
        <div style="background:rgba(255,255,255,0.06);border-radius:6px;padding:7px;width:100%;box-sizing:border-box;text-align:center;font-size:11px;color:#ccc;">${bonusDesc[opt.type] || ''}</div>
        <button onclick="confirmStartChoice(${i})" style="padding:7px 0;background:${col};border:none;border-radius:6px;color:#fff;font-weight:bold;cursor:pointer;font-size:13px;width:100%;">Choose</button>
      </div>`;
  }).join('');
  createGameModal(`
    <div style="text-align:center;padding:8px;">
      <h2 style="color:var(--color-gold);margin-bottom:6px;">Choose Your Start</h2>
      <p style="color:#aaa;font-size:13px;margin-bottom:18px;">All paths lead to: <strong style="color:var(--color-gold);">${amulet.name}</strong></p>
      <div style="display:flex;gap:14px;justify-content:center;flex-wrap:wrap;">${panels}</div>
    </div>`);
}

// Drives the "first game complete" progression without a Finished button:
// curse verification → mark game finished → item choice → spawn next choices.
function runStartProgression() {
  const doFinish = () => {
    setTimeout(() => {
      const chestType = gameState.unstableGenomeTriggered ? 'large' : 'normal';
      if (gameState.unstableGenomeTriggered) gameState.unstableGenomeTriggered = false;
      if (typeof showItemChoiceModal === 'function') showItemChoiceModal(null, chestType);
    }, 150);
  };
  if (typeof showCurseVerificationModal === 'function') {
    showCurseVerificationModal(doFinish);
  } else {
    doFinish();
  }
}

// Wire the first game node so clicking it → node preview → Fight → combat → post-combat → progression.
// Called from both completeGameStart() and renderGameState() (for page reloads).
window.wireStartNodeCombat = function() {
  const startGameName = gameState.visitedGames && gameState.visitedGames[0];
  if (!startGameName) return;
  const allNodes = document.querySelectorAll('[data-game-name]');
  let startNode = null;
  for (const n of allNodes) {
    if (n.dataset.gameName === startGameName) { startNode = n; break; }
  }
  if (!startNode) return;

  startNode.classList.add('is-clickable');

  const triggerCombat = () => {
    const startCombat = () => {
      startNode.onclick = null;
      startNode.classList.remove('is-clickable');
      window._postcombatOnComplete = runStartProgression;
      if (window.useDiceCombat && typeof showDiceCombatModal === 'function') showDiceCombatModal();
      else if (typeof showCombatModal === 'function') showCombatModal();
    };
    if (typeof showEventModal === 'function') showEventModal(null, startCombat);
    else startCombat();
  };

  if (typeof showNodeDetailModal === 'function') {
    startNode.onclick = () => showNodeDetailModal(startGameName, null, null, 'combat', {
      onFight: () => triggerCombat()
    });
  } else {
    startNode.onclick = () => triggerCombat();
  }
};

function applyStartingBonus(type, onComplete) {
  switch (type) {
    case 'Action':
      showItemChoiceModal(onComplete, 'normal', 'Weapon');
      break;
    case 'Traditional':
      showItemChoiceModal(onComplete);
      break;
    case 'Strategy':
      StateMutator.modifyGold(40);
      onComplete();
      break;
    case 'Deckbuilding':
      showCardRewardModal(onComplete);
      break;
    default:
      onComplete();
  }
}

document.getElementById('cancel-save')?.addEventListener('click', () => {
  document.getElementById('save-modal').style.display = 'none';
});

document.getElementById('confirm-save')?.addEventListener('click', () => {
  const saveName = document.getElementById('save-name-input').value.trim();
  if (!saveName) { alert('Please enter a save name'); return; }
  if (!selectedCharacter) { alert('Please select a character before starting your run'); return; }
  if (gameSaves[saveName] && !confirm('Overwrite existing save?')) return;

  const eligible = games.filter(g => g.connected);
  if (eligible.length < 2) { alert('Not enough games'); return; }

  const eligibleStarts = eligible.filter(g => {
    const conns = typeof getGameConnections === 'function' ? getGameConnections(g.name) : [];
    return conns.length >= 3;
  });
  const startPool = eligibleStarts.length > 0 ? eligibleStarts : eligible;

  const MIN_PATH_LENGTH = 5;
  const MAX_PATH_LENGTH = 8;

  // Pick amulet using a random reference start for anchoring
  const refStart = startPool[Math.floor(Math.random() * startPool.length)];
  const dFromRef = bfsAllDistances(refStart.name);

  let amuletCandidates = eligible.filter(g => {
    if (g.name === refStart.name) return false;
    const d = dFromRef.get(g.name);
    return d !== undefined && d >= MIN_PATH_LENGTH && d <= MAX_PATH_LENGTH;
  });
  const amuletScored = amuletCandidates.map(g => ({ g, score: dagBranchScoreEarly(dFromRef, g.name) }));
  const amuletMax = amuletScored.reduce((m, s) => Math.max(m, s.score), 0);
  if (amuletMax > 0) amuletCandidates = amuletScored.filter(s => s.score >= amuletMax - 1).map(s => s.g);
  if (amuletCandidates.length === 0) amuletCandidates = eligible.filter(g => g.name !== refStart.name);
  if (amuletCandidates.length === 0) { alert('No valid amulet game'); return; }
  const amulet = amuletCandidates[Math.floor(Math.random() * amuletCandidates.length)];

  // Find the best eligible start per game type for this amulet, then show the top 3
  const dToAmulet = bfsAllDistances(amulet.name);
  const GAME_TYPES = ['Action', 'Traditional', 'Strategy', 'Deckbuilding'];
  const bestPerType = {};
  for (const type of GAME_TYPES) {
    const typeStarts = eligibleStarts.filter(g => games.find(gg => gg.name === g.name)?.type === type);
    const scored = typeStarts
      .map(g => {
        const dFS = bfsAllDistances(g.name);
        const dist = dFS.get(amulet.name);
        if (!dist || dist < MIN_PATH_LENGTH || dist > MAX_PATH_LENGTH) return null;
        return { g, score: dagBranchScoreEarly(dFS, amulet.name, 3, dToAmulet) };
      })
      .filter(Boolean)
      .sort((a, b) => b.score - a.score);
    if (scored.length > 0) bestPerType[type] = scored[0];
  }

  const startOptions = GAME_TYPES
    .filter(t => bestPerType[t])
    .sort((a, b) => bestPerType[b].score - bestPerType[a].score)
    .slice(0, 3)
    .map(t => ({ type: t, start: bestPerType[t].g }));

  if (startOptions.length === 0) { alert('Not enough start options found'); return; }

  document.getElementById('save-modal').style.display = 'none';
  showStartingChoiceModal(startOptions, amulet, saveName);
});

function completeGameStart(start, amulet, saveName, startType) {
  const character = PLAYER_CHARACTERS[selectedCharacter];
  if (!character) {
    console.error('ERROR: Character not found!', selectedCharacter);
    alert('Error: Character data not found. Please try again.');
    return;
  }

  const stats = character.startingStats || {};
  attack = stats.attack || 0;
  const baseHealth = character.health || 10;
  StateMutator.restoreState({
    strength: stats.strength,
    dexterity: stats.dexterity,
    intelligence: stats.intelligence,
    charisma: stats.charisma,
    reroll: stats.reroll,
    dash: stats.dash,
    skip: stats.skip,
    discovery: stats.discovery,
    fov: stats.fov,
    luck: stats.luck,
    maxHealth: baseHealth,
    health: baseHealth,
    gold: 0,
  });
  inventory = [];

  const characterTraits = character.traits || [];
  const encounterTypes = {};
  games.forEach(game => { encounterTypes[game.name] = 'combat'; });

  const initialDifficulty = getDifficultyTier(0);
  const selectedLocation = getRandomLocation(initialDifficulty);

  gameState = {
    currentGame: start.name,
    visitedGames: [start.name],
    finishedGames: [],
    totalGamesBeaten: 0,
    skippedGames: [],
    saveName: saveName,
    gameStarted: true,
    health: health,
    maxHealth: maxHealth,
    gold: gold,
    inventory: [],
    loot: [],
    activeCurses: [],
    cursesTracker: {},
    beatenGames: [...beatenGames],
    startGame: start,
    amuletGame: amulet,
    currentY: 120,
    character: selectedCharacter,
    selectedDeck: selectedDeck || 'Random',
    startingMaxHealth: maxHealth,
    traits: characterTraits,
    strength: strength,
    dexterity: dexterity,
    intelligence: intelligence,
    charisma: charisma,
    escapePhase: false,
    escapeGames: [],
    escapeProgress: 0,
    gameStatusEffects: {},
    encounterTypes: encounterTypes,
    location: selectedLocation,
    playerLevel: 1,
    activeAllies: [],
    deck: [],
    spells: [],
    insaneBatteryFills: 0,
    pendingInsaneHardCombat: false,
    choiceDetails: {},
    eventsSeenCounts: {},
    // Persistent run-wide d20. Items mutate `sides[i].value` / displayValue
    // to alter the die's face values; events read this die when prompting
    // for a roll. Stays in gameState so changes persist through saves.
    playerD20: (typeof createD20 === 'function') ? createD20() : null
  };
  window.playerSpells = gameState.spells;

  // Pre-generate start node details so the node modal has data immediately
  if (typeof preGenerateEnemiesForGame === 'function') {
    gameState.choiceDetails[start.name] = {
      enemies: preGenerateEnemiesForGame(start.name),
      postCombatOptions: (typeof pickTwoPostCombatOptions === 'function')
        ? pickTwoPostCombatOptions()
        : ['rest', 'shop']
    };
  }

  startGame = start;
  amuletGame = amulet;

  if (typeof invalidateBFSCache === 'function') invalidateBFSCache();

  const escapeContainer = document.getElementById('escape-container');
  if (escapeContainer) escapeContainer.remove();

  document.getElementById('main-menu').style.display = 'none';
  document.getElementById('dungeon-screen').style.display = 'flex';

  const topBarRight = document.getElementById('top-bar-right');
  if (topBarRight) topBarRight.style.display = 'flex';

  document.getElementById('path-viewport').style.display = 'block';
  document.getElementById('target').style.display = 'block';

  if (typeof renderGameState === 'function') renderGameState();
  updateCharacterUI();
  updateTraitsDisplay();
  generateBingoGrid();

  const startingItemNames = character.startingItems || [];
  startingItemNames.forEach(itemName => {
    const itemData = items.find(i => i.name === itemName);
    if (itemData && typeof acquireItem === 'function') acquireItem(itemData);
    else console.warn(`Starting item not found: ${itemName}`);
  });

  applyStartingBonus(startType, () => {
    saveCurrentGame();
    updateSaveList();

    if (selectedLocation && selectedLocation.game === 'Hades' && typeof showHadesBoonSelection === 'function') {
      gameState.hadesStartBoonTimeout = setTimeout(() => {
        gameState.hadesStartBoonTimeout = null;
        showHadesBoonSelection(false);
      }, 500);
    } else {
      // Wire start node via the shared helper (also called by renderGameState on reload).
      if (typeof window.wireStartNodeCombat === 'function') {
        window.wireStartNodeCombat();
      }
    }
  });
}

// Window re-exports (legacy script-tag model; removed in Phase 5)
if (typeof window !== 'undefined') {
  window.bfsAllDistances       = bfsAllDistances;
  window.confirmStartChoice    = confirmStartChoice;
  window.previewStartMap       = previewStartMap;
  window.backToStartChoice     = backToStartChoice;
  window.showGameMapPreview    = showGameMapPreview;
  window.closeGameMapPreview   = closeGameMapPreview;
  window.showStartingChoiceModal = showStartingChoiceModal;
  window.runStartProgression   = runStartProgression;
  window.applyStartingBonus    = applyStartingBonus;
  window.completeGameStart     = completeGameStart;
}
