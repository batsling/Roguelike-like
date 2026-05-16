// ===== MAIN.JS - Core Game Logic and Initialization =====
//
// This module handles:
// - Page initialization and event listener setup
// - Excel file upload and data loading
// - Save/load game system (localStorage via GameStorage)
// - Top-bar and UI controls (gold, HP, energy, reroll, dash)
// - Map generation and location management
// - Item shop, card rewards, and loot drops
// - Combat setup and post-combat flow
// - Curse system, difficulty scaling, and game completion
// - Tutorial, notifications, and modal orchestration
// - Integration of all other modules
//
// Collection UI, stats tracking, and detail panels live in collection.js.
// Escape phase and run history live in escape.js.

// ===== Z-INDEX LAYERING SYSTEM =====
// Organized from lowest to highest to prevent layering conflicts
//
// Layer 1 (Base): 1-20
//   - Map SVG arrows: 1
//   - Item hover effects: 10
//   - Combat hand cards: 20+
//
// Layer 2 (UI Chrome): 100
//   - #top-bar, #game-stats, ability buttons
//
// Layer 3 (Map / Dropdowns): 200
//   - #save-list dropdown
//
// Layer 4 (Floating Panels): 300
//   - #location-display-section, #goals-section, .floating-hud-complex, .box-zoom-popup
//
// Layer 5 (Hover Popovers): 400
//   - #game-tooltip, #item-tooltip
//
// Layer 6 (Modals): 500
//   - #game-modal (modals.js), #save-modal, #rewards-modal, .z-2000
//
// Layer 7 (Tooltips — always on top): 9000
//   - #combat-item-tooltip, #combat-status-tooltip
//   - #location-hover-tooltip, #game-stats .stat-tooltip::after
//
// ===== HELPER FUNCTIONS =====

// Get curses by type from active curses
function getCursesByType(curseType) {
  return gameState?.activeCurses?.filter(c =>
    c.name.toLowerCase().includes(curseType.toLowerCase())
  ) || [];
}

// Get numeric value for curse power level
function getPowerValue(power, scale = { Low: 1, Medium: 2, High: 3 }) {
  return scale[power] || 0;
}

// Get player stat value by name
function getPlayerStat(statName) {
  const stats = {
    Strength: strength,
    Dexterity: dexterity,
    Intelligence: intelligence,
    Charisma: charisma
  };
  return stats[statName] || 0;
}

// Consolidate curse display updates
function updateCurseUI() {
  updateCursesDisplay?.();
  updateActiveCursesList?.();
  updateVerificationCursesDisplay?.();
}

// ===== INITIALIZATION =====

document.addEventListener('DOMContentLoaded', async () => {

  // Initialize gameplay DOM references
  if (typeof initGameplayDOM === 'function') {
    initGameplayDOM();
  }

  // Initial UI update
  updateTopBar();

  // Load saved state if it exists
  loadState();

  // Update save list
  try {
    updateSaveList();
  } catch(err) {
    console.error('Error updating save list:', err);
  }

  // Initialize bingo system
  bingoGoals = [...BINGO_GOALS];
  generateBingoGrid();

  // Populate dev tool selects
  if (typeof populateItemSelects === 'function') populateItemSelects();
  if (typeof populateCurseSelects === 'function') populateCurseSelects();
  if (typeof populateEnemySelect === 'function') populateEnemySelect();
  if (typeof populateSpaceSelect === 'function') populateSpaceSelect();
  if (typeof populateDifficultyLocationSelect === 'function') populateDifficultyLocationSelect();
  if (typeof populateStatusGameSelect === 'function') populateStatusGameSelect();
  if (typeof populateEventSelect === 'function') populateEventSelect();

  // Add bingo event listeners
  const bingoToggleBtn = document.getElementById('bingo-toggle');
  if (bingoToggleBtn) {
    bingoToggleBtn.addEventListener('click', toggleBingo);
  }

  const toggleBingoBtn = document.getElementById('toggle-bingo-btn');
  if (toggleBingoBtn) {
    toggleBingoBtn.addEventListener('click', toggleBingo);
  }

  const viewRewardsBtn = document.getElementById('view-rewards-btn');
  if (viewRewardsBtn) {
    viewRewardsBtn.addEventListener('click', showBingoRewards);
  }

  const closeRewardsBtn = document.getElementById('close-rewards-btn');
  if (closeRewardsBtn) {
    closeRewardsBtn.addEventListener('click', () => {
      const rewardsModal = document.getElementById('rewards-modal');
      if (rewardsModal) {
        rewardsModal.classList.remove('show');
      }
    });
  }

  // Close rewards modal when clicking outside content
  const rewardsModal = document.getElementById('rewards-modal');
  if (rewardsModal) {
    rewardsModal.addEventListener('click', (e) => {
      if (e.target === rewardsModal) {
        rewardsModal.classList.remove('show');
      }
    });
  }

  // Add event listeners for map and loot buttons (removed inline onclick handlers)
  const mapBtn = document.getElementById('map-btn');
  if (mapBtn) {
    mapBtn.addEventListener('click', showMapModal);
  }

  const deckBtn = document.getElementById('deck-btn');
  if (deckBtn) {
    deckBtn.addEventListener('click', showDeckModal);
  }

  const diceTrayBtn = document.getElementById('dice-tray-btn');
  if (diceTrayBtn) {
    diceTrayBtn.addEventListener('click', showDiceTrayModal);
  }

  const spellsBtn = document.getElementById('spells-btn');
  if (spellsBtn) {
    spellsBtn.addEventListener('click', showSpellsModal);
  }

  const notifHistoryBtn = document.getElementById('notif-history-btn');
  if (notifHistoryBtn) {
    notifHistoryBtn.addEventListener('click', showNotificationHistory);
  }

  const lootBtn = document.getElementById('loot-btn');
  if (lootBtn) {
    lootBtn.addEventListener('click', showLootModal);
  }

});

// ===== SAVE/LOAD SYSTEM =====

function loadState() {
  const state = GameStorage.load(STORAGE_KEYS.GAME_STATE);
  if (state) {
    if (gameState) gameState.rations = state.rations ?? 10;
    gold = state.gold ?? 0;
    health = state.health;
    maxHealth = state.maxHealth ?? 10;
    inventory = state.inventory;
    beatenGames = state.beatenGames;
    selectedPhase2Games = state.selectedPhase2Games;
    excludedGames = state.excludedGames ?? [];
    startGame = state.startGame;
    amuletGame = state.amuletGame;
    encounterHistory = state.encounterHistory ?? [];
    markedSvg = state.markedSvg;

    // Load bingo state
    bingoGrid = state.bingoGrid ?? Array(9).fill(null);
    bingoCompleted = state.bingoCompleted ?? Array(9).fill(false);
    completedBingos = state.completedBingos ?? 0;
    bingoReroll = state.bingoReroll ?? 0;
    bingoSkip = state.bingoSkip ?? 0;
    bingoFoV = state.bingoFoV ?? 0;
    bingoDiscovery = state.bingoDiscovery ?? 0;
    bingoDash = state.bingoDash ?? 0;

    // Render bingo grid if available, or generate new one if empty
    if (bingoGrid && bingoGrid.some(g => g !== null)) {
      renderBingoGrid();
      updateBingoStatus();
    } else {
      // Generate new bingo grid for old saves that don't have one
      generateBingoGrid();
    }

    if (state.markedSvg) {
      document.getElementById('svg-viewport').innerHTML = markedSvg;
      setTimeout(() => {
        const svgElement = document.getElementById('svg-viewport').querySelector('svg');
        if (svgElement) {
          originalSvgWidth = parseFloat(svgElement.getAttribute('width')) || svgElement.viewBox?.baseVal?.width || 0;
          originalSvgHeight = parseFloat(svgElement.getAttribute('height')) || svgElement.viewBox?.baseVal?.height || 0;
          if (typeof resetView === 'function') resetView();
        }
      }, 100);
    }

    if (state.playerMarkerPosition || state.amuletMarkerPosition) {
      const svgElement = document.getElementById('svg-viewport').querySelector('svg');
      if (svgElement) {
        if (playerMarker) playerMarker.remove();
        if (amuletMarker) amuletMarker.remove();

        playerMarker = document.createElementNS('http://www.w3.org/2000/svg', 'image');
        playerMarker.setAttribute('href', playerImageUrl);
        playerMarker.setAttribute('width', '64');
        playerMarker.setAttribute('height', '64');
        playerMarker.setAttribute('x', state.playerMarkerPosition?.x || 50);
        playerMarker.setAttribute('y', state.playerMarkerPosition?.y || 50);
        playerMarker.setAttribute('class', 'movable-marker');
        playerMarker.dataset.type = 'player';
        playerMarker.style.cursor = 'move';

        amuletMarker = document.createElementNS('http://www.w3.org/2000/svg', 'image');
        amuletMarker.setAttribute('href', amuletImageUrl);
        amuletMarker.setAttribute('width', '64');
        amuletMarker.setAttribute('height', '64');
        amuletMarker.setAttribute('x', state.amuletMarkerPosition?.x || 150);
        amuletMarker.setAttribute('y', state.amuletMarkerPosition?.y || 50);
        amuletMarker.setAttribute('class', 'movable-marker');
        amuletMarker.dataset.type = 'amulet';
        amuletMarker.style.cursor = 'move';

        svgElement.appendChild(playerMarker);
        svgElement.appendChild(amuletMarker);

        if (typeof setupMarkerDragging === 'function') {
          setupMarkerDragging();
        }
      }
    }

    updateTopBar();
    updateInventory();
    updateBeatenGamesList();
    updateSelectedGamesDisplay();
    updateExcludedGamesList();
    updateRoguePointsDisplay();
    updateConditionCounts();
    updateEncounterHistory();

    if (startGame && amuletGame) {
      document.getElementById('output').innerHTML = `
        <p>Starting Game: ${startGame.name} (${startGame.year}, ${startGame.type})</p>
        <p>Amulet Game: ${amuletGame.name} (${amuletGame.year}, ${amuletGame.type})</p>
      `;
    }
  }
}

let selectedCharacter = null;
var selectedDeck = 'Random'; // Default deck for the current run selection (var so window.selectedDeck works cross-file)

// ===== DECK WIN TRACKING =====

function getDeckWinsForCharacter(charKey) {
  const all = GameStorage.load(STORAGE_KEYS.DECK_WINS, {});
  return all[charKey] || [];
}

function recordDeckWin(charKey, deckId) {
  if (!charKey || !deckId) return;
  const all = GameStorage.load(STORAGE_KEYS.DECK_WINS, {});
  if (!all[charKey]) all[charKey] = [];
  if (!all[charKey].includes(deckId)) {
    all[charKey].push(deckId);
    GameStorage.save(STORAGE_KEYS.DECK_WINS, all);
  }
}

// Combat system toggle - set to true to use new dice-based combat
let useDiceCombat = true;

function saveCurrentGame() {
  if (!gameState.saveName) return;

  // Deep copy inventory items to preserve all properties
  const inventoryCopy = inventory.map(item => ({
    name: item.name,
    type: item.type,
    rarity: item.rarity,
    description: item.description,
    image: item.image,
    reference: item.reference,
    tags: item.tags,
    quantity: item.quantity,
    uses: item.uses
  }));

  // Deep copy diceSlots items for serialization
  const copyItem = item => item ? ({
    name: item.name, type: item.type, rarity: item.rarity,
    description: item.description, image: item.image,
    reference: item.reference, tags: item.tags, quantity: item.quantity, uses: item.uses
  }) : null;
  const diceSlotsSnapshot = {};
  Object.entries(gameState.diceSlots || {}).forEach(([uid, item]) => {
    diceSlotsSnapshot[uid] = copyItem(item);
  });

  gameSaves[gameState.saveName] = {
    ...gameState,
    health: health,
    maxHealth: maxHealth,
    gold: gold,
    rations: gameState.rations ?? 10,
    inventory: inventoryCopy,
    diceSlots: diceSlotsSnapshot,
    beatenGames: [...beatenGames],
    strength: strength,
    dexterity: dexterity,
    intelligence: intelligence,
    charisma: charisma,
    reroll: reroll,
    dash: dash,
    skip: skip,
    discovery: discovery,
    // Save bingo state
    bingoGrid: bingoGrid,
    bingoCompleted: bingoCompleted,
    completedBingos: completedBingos,
    bingoReroll: bingoReroll,
    bingoSkip: bingoSkip,
    bingoFoV: bingoFoV,
    bingoDiscovery: bingoDiscovery,
    bingoDash: bingoDash
  };

  const result = GameStorage.save(STORAGE_KEYS.SAVED_GAMES, gameSaves);
  if (!result.success) {
    console.error('Failed to save game:', result.error);
    alert('Failed to save game: ' + result.error);
    return;
  }
}

function loadSavedGame(saveName) {
  const save = gameSaves[saveName];
  if (!save) return;

  // Restore game state
  gameState = { ...save };

  // Sync selectedCharacter with the saved character so combat lookups work
  selectedCharacter = gameState.character || Object.keys(PLAYER_CHARACTERS)[0];

  // Backward compatibility for new combat system properties (for old saves)
  if (gameState.playerLevel === undefined) {
    gameState.playerLevel = 1;
  }
  if (gameState.activeAllies === undefined) {
    gameState.activeAllies = [];
  }
  if (gameState.equippedWeapon === undefined) {
    gameState.equippedWeapon = null;
  }
  if (!gameState.deck) {
    gameState.deck = [];
  }
  if (!gameState.spells) {
    gameState.spells = [];
  }
  if (!gameState.diceSlots) {
    gameState.diceSlots = {};
  }
  window.playerSpells = gameState.spells; // keep in sync with combat fallback
  // Generate encounter types if they don't exist (for old saves)
  if (!gameState.encounterTypes) {
    gameState.encounterTypes = {};
    games.forEach(game => {
      gameState.encounterTypes[game.name] = 'combat';
    });
  } else {
    // Migrate old saves: change any non-combat encounters to combat
    Object.keys(gameState.encounterTypes).forEach(gameName => {
      gameState.encounterTypes[gameName] = 'combat';
    });
  }

  health = save.health;
  maxHealth = save.maxHealth;
  gold = save.gold;
  if (gameState) gameState.rations = save.rations || 10;
  inventory = [...(save.inventory || [])];
  beatenGames = [...(save.beatenGames || [])];
  strength = save.strength || 0;
  dexterity = save.dexterity || 0;
  intelligence = save.intelligence || 0;
  charisma = save.charisma || 0;
  reroll = save.reroll || 0;
  dash = save.dash || 0;
  skip = save.skip || 0;
  discovery = save.discovery || 0;

  // Restore bingo state
  bingoGrid = save.bingoGrid ?? Array(9).fill(null);
  bingoCompleted = save.bingoCompleted ?? Array(9).fill(false);
  completedBingos = save.completedBingos ?? 0;
  bingoReroll = save.bingoReroll ?? 0;
  bingoSkip = save.bingoSkip ?? 0;
  bingoFoV = save.bingoFoV ?? 0;
  bingoDiscovery = save.bingoDiscovery ?? 0;
  bingoDash = save.bingoDash ?? 0;

  // Render bingo grid
  if (bingoGrid && bingoGrid.some(g => g !== null)) {
    renderBingoGrid();
    updateBingoStatus();
  }

  // Invalidate BFS cache when loading a game (game state changed)
  if (typeof invalidateBFSCache === 'function') {
    invalidateBFSCache();
  }

  // Clean up any escape container
  const escapeContainer = document.getElementById('escape-container');
  if (escapeContainer) {
    escapeContainer.remove();
  }

  // Show dungeon screen
  document.getElementById('main-menu').style.display = 'none';
  document.getElementById('dungeon-screen').style.display = 'flex';

  // Show top-right buttons when in game
  const topBarRight = document.getElementById('top-bar-right');
  if (topBarRight) topBarRight.style.display = 'flex';

  // Show or hide elements based on escape phase
  if (gameState.escapePhase) {
    // In escape phase - show escape visualization
    document.getElementById('path-viewport').style.display = 'none';
    document.getElementById('target').style.display = 'none';
    showEscapeVisualization();
  } else {
    // Normal game - show path viewport
    document.getElementById('path-viewport').style.display = 'block';
    document.getElementById('target').style.display = 'block';

    // Render the game state
    if (typeof renderGameState === 'function') {
      renderGameState();
    }
  }

  updateTopBar();
  updateInventory();
  updateCursesDisplay();
  updateGameStats();

}

// ===== TUTORIAL AND UI CONTROLS =====

document.getElementById('toggleTutorial')?.addEventListener('click', () => {
  document.getElementById('tutorial-modal').style.display = 'flex';
});

document.getElementById('close-tutorial')?.addEventListener('click', () => {
  document.getElementById('tutorial-modal').style.display = 'none';
});

// Close tutorial modal when clicking outside
document.getElementById('tutorial-modal')?.addEventListener('click', (e) => {
  if (e.target.id === 'tutorial-modal') {
    document.getElementById('tutorial-modal').style.display = 'none';
  }
});

document.getElementById('clearAllData')?.addEventListener('click', () => {
  if (confirm('This will delete ALL saved games and reset the app. Are you sure?')) {
    localStorage.clear();
    location.reload();
  }
});

// ===== GAME STATE MANAGEMENT =====

// Character selection state
let currentCharacterIndex = 0;
let characterViewMode = 'horizontal'; // 'horizontal' or 'icon'

document.getElementById('new-game-btn')?.addEventListener('click', () => {

  if (games.length === 0) {
    alert('Game data is still loading... Please wait a moment and try again.');
    return;
  }

  // Reset character selection state
  currentCharacterIndex = 0;

  // Set first character as default selected
  const characterKeys = Object.keys(PLAYER_CHARACTERS);
  selectedCharacter = characterKeys.length > 0 ? characterKeys[0] : null;

  // Populate deck selection panel
  if (typeof populateDeckView === 'function') populateDeckView();

  // Populate icon view
  populateIconCharacterView();

  // Show details for first character
  if (selectedCharacter) {
    const detailsPanel = document.getElementById('icon-character-details');
    if (detailsPanel) {
      detailsPanel.style.display = 'flex';
      showIconCharacterDetails(selectedCharacter);
    }
  }

  document.getElementById('save-modal').style.display = 'flex';
});

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
    if (typeof markGameFinished === 'function') markGameFinished(gameState.currentGame);
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

  const triggerCombat = () => {
    const startCombat = () => {
      startNode.onclick = null;
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
      gold += 40;
      if (gameState) gameState.gold = gold;
      if (typeof updateGoldDisplay === 'function') updateGoldDisplay();
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
  strength    = stats.strength    || 0;
  dexterity   = stats.dexterity   || 0;
  intelligence= stats.intelligence|| 0;
  charisma    = stats.charisma    || 0;
  attack      = stats.attack      || 0;
  reroll      = stats.reroll      || 0;
  dash        = stats.dash        || 0;
  skip        = stats.skip        || 0;
  discovery   = stats.discovery   || 0;
  fov         = stats.fov         || 0;
  luck        = stats.luck        || 0;

  const baseHealth = character.health || 10;
  health = baseHealth;
  maxHealth = baseHealth;
  gold = 0;
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
    choiceDetails: {}
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

document.getElementById('continue-btn')?.addEventListener('click', () => {
  const saveList = document.getElementById('save-list');
  saveList.style.display = saveList.style.display === 'block' ? 'none' : 'block';
});

document.getElementById('run-history-btn')?.addEventListener('click', () => {
  showRunHistory();
});

document.getElementById('collection-btn')?.addEventListener('click', () => {
  showCollection();
});

// ============================================================
// SETTINGS SYSTEM
// ============================================================

const SETTINGS_KEY = 'roguelikeSettings';

/** Load settings from localStorage, merging with defaults. */
function loadSettings() {
  const defaults = { specificEnemies: false, devToolsEnabled: false };
  try {
    const stored = localStorage.getItem(SETTINGS_KEY);
    return stored ? { ...defaults, ...JSON.parse(stored) } : defaults;
  } catch (e) {
    return defaults;
  }
}

/** Show or hide the developer tools panel based on current settings. */
function applyDevToolsVisibility() {
  const panel = document.getElementById('dev-tools-panel');
  if (!panel) return;
  if (gameSettings.devToolsEnabled) {
    panel.classList.remove('dev-tools-hidden');
  } else {
    panel.classList.add('dev-tools-hidden');
  }
}

/** Persist settings to localStorage. */
function saveSettings(settings) {
  try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch (e) {}
}

/** Current in-memory settings (read once on load, written on change). */
let gameSettings = loadSettings();
// Apply visibility-driven settings as soon as the DOM is ready
document.addEventListener('DOMContentLoaded', applyDevToolsVisibility);

/** Show the settings modal. */
function showSettingsModal() {
  const overlay = document.createElement('div');
  overlay.id = 'settings-overlay';
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.75);display:flex;align-items:center;justify-content:center;z-index:30000;';

  overlay.innerHTML = `
    <div style="background:#1a1a2e;border:2px solid #444;border-radius:12px;padding:28px;min-width:340px;max-width:480px;color:#eee;font-family:inherit;">
      <h2 style="margin:0 0 18px;font-size:20px;color:#fff;">⚙️ Settings</h2>

      <div style="margin-bottom:22px;">
        <h3 style="margin:0 0 10px;font-size:14px;color:#aaa;text-transform:uppercase;letter-spacing:.05em;">Combat</h3>

        <label style="display:flex;align-items:flex-start;gap:12px;cursor:pointer;padding:10px;border-radius:8px;border:1px solid #333;background:#111;">
          <input type="checkbox" id="setting-specific-enemies" style="margin-top:3px;width:16px;height:16px;accent-color:#ff9800;flex-shrink:0;"
            ${gameSettings.specificEnemies ? 'checked' : ''}>
          <span>
            <strong style="display:block;margin-bottom:4px;">Specific Enemies</strong>
            <span style="font-size:12px;color:#aaa;">
              When <b>ON</b>: enemies are limited to those from the game you're currently visiting.<br>
              When <b>OFF</b> (default): any enemy whose type matches the game category can appear
              (Action→Strength, Deckbuilding→Charisma, Strategy→Intelligence, Traditional→Dexterity).
            </span>
          </span>
        </label>
      </div>

      <div style="margin-bottom:22px;">
        <h3 style="margin:0 0 10px;font-size:14px;color:#aaa;text-transform:uppercase;letter-spacing:.05em;">Developer</h3>

        <label style="display:flex;align-items:flex-start;gap:12px;cursor:pointer;padding:10px;border-radius:8px;border:1px solid #333;background:#111;">
          <input type="checkbox" id="setting-dev-tools" style="margin-top:3px;width:16px;height:16px;accent-color:#ff9800;flex-shrink:0;"
            ${gameSettings.devToolsEnabled ? 'checked' : ''}>
          <span>
            <strong style="display:block;margin-bottom:4px;">Developer Tools</strong>
            <span style="font-size:12px;color:#aaa;">
              Show the developer panel for spawning enemies, adding items, and triggering encounters directly.
            </span>
          </span>
        </label>
      </div>

      <div style="display:flex;justify-content:flex-end;gap:10px;">
        <button id="settings-save" style="padding:8px 20px;background:#4CAF50;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:14px;">Save</button>
        <button id="settings-cancel" style="padding:8px 20px;background:#555;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:14px;">Cancel</button>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  overlay.querySelector('#settings-save').addEventListener('click', () => {
    gameSettings.specificEnemies = overlay.querySelector('#setting-specific-enemies').checked;
    gameSettings.devToolsEnabled = overlay.querySelector('#setting-dev-tools').checked;
    saveSettings(gameSettings);
    applyDevToolsVisibility();
    overlay.remove();
  });

  overlay.querySelector('#settings-cancel').addEventListener('click', () => overlay.remove());
  overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
}

document.getElementById('settings-btn')?.addEventListener('click', showSettingsModal);

// ============================================================

document.getElementById('return-menu')?.addEventListener('click', () => {
  if (confirm('Return to main menu? (Game will be saved)')) {
    saveCurrentGame();
    if (typeof clearAllArrows === 'function') {
      clearAllArrows();
    }
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';

    // Hide top-right buttons when in menu
    const topBarRight = document.getElementById('top-bar-right');
    if (topBarRight) topBarRight.style.display = 'none';
  }
});

// Top bar menu button (same functionality)
document.getElementById('return-menu-top')?.addEventListener('click', () => {
  const inDungeon = document.getElementById('dungeon-screen').style.display !== 'none';
  if (!inDungeon) return;
  if (confirm('Return to main menu? (Game will be saved)')) {
    // End combat first if active
    const combatModal = document.getElementById('game-modal');
    if (combatModal) {
      if (window.CombatEngine && window.CombatEngine.endCombat) {
        window.CombatEngine.endCombat(false);
      }
      combatModal.remove();
    }
    saveCurrentGame();
    if (typeof clearAllArrows === 'function') clearAllArrows();
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';
    const topBarRight = document.getElementById('top-bar-right');
    if (topBarRight) topBarRight.style.display = 'none';
  }
});

// ===== DATA INITIALIZATION =====
// Data is now loaded automatically from JSON files via data.js

function populateGameSelects() {
  const startGameSelect = document.getElementById('startGameSelect');
  const amuletGameSelect = document.getElementById('amuletGameSelect');
  const gameSelect = document.getElementById('gameSelect');
  const beatenGameSelect = document.getElementById('beatenGameSelect');
  const excludeGameSelect = document.getElementById('excludeGameSelect');

  if (startGameSelect) {
    startGameSelect.innerHTML = '<option value="">-- Select a Start Game --</option>';
    amuletGameSelect.innerHTML = '<option value="">-- Select an Amulet Game --</option>';
    games.forEach(game => {
      if (game.connected) {
        const option = document.createElement('option');
        option.value = game.name;
        option.textContent = `${game.name} (${game.year}, ${game.type})`;
        startGameSelect.appendChild(option.cloneNode(true));
        amuletGameSelect.appendChild(option);
      }
    });
    startGameSelect.disabled = false;
    amuletGameSelect.disabled = false;
  }

  if (gameSelect) {
    gameSelect.innerHTML = '<option value="">-- Select a Game --</option>';
    games.forEach(game => {
      if (game.connected) {
        const option = document.createElement('option');
        option.value = game.name;
        option.textContent = game.name;
        gameSelect.appendChild(option);
      }
    });
    gameSelect.disabled = false;
  }

  if (beatenGameSelect) {
    beatenGameSelect.innerHTML = '<option value="">-- Select a Game --</option>';
    games.forEach(game => {
      const option = document.createElement('option');
      option.value = game.name;
      option.textContent = game.name;
      beatenGameSelect.appendChild(option);
    });
    beatenGameSelect.disabled = false;
  }

  if (excludeGameSelect) {
    excludeGameSelect.innerHTML = '<option value="">-- Select a Game to Exclude --</option>';
    games.forEach(game => {
      const option = document.createElement('option');
      option.value = game.name;
      option.textContent = `${game.name} (${game.year}, ${game.type})`;
      excludeGameSelect.appendChild(option);
    });
    excludeGameSelect.disabled = false;
  }

  // Populate decade, year, and type selects
  const decades = [...new Set(games.map(game => Math.floor(game.year / 10) * 10))];
  const decadeSelect = document.getElementById('decadeSelect');
  if (decadeSelect) {
    decadeSelect.innerHTML = '<option value="">-- Select a Decade --</option>';
    decades.forEach(decade => {
      const option = document.createElement('option');
      option.value = decade;
      option.textContent = `${decade}s`;
      decadeSelect.appendChild(option);
    });
    decadeSelect.disabled = false;
  }

  const years = [...new Set(games.map(game => game.year))];
  const yearSelect = document.getElementById('yearSelect');
  if (yearSelect) {
    yearSelect.innerHTML = '<option value="">-- Select a Year --</option>';
    years.forEach(year => {
      const option = document.createElement('option');
      option.value = year;
      option.textContent = year;
      yearSelect.appendChild(option);
    });
    yearSelect.disabled = false;
  }

  const types = [...new Set(games.map(game => game.type))];
  const typeSelect = document.getElementById('typeSelect');
  if (typeSelect) {
    typeSelect.innerHTML = '<option value="">-- Select a Type --</option>';
    types.forEach(type => {
      const option = document.createElement('option');
      option.value = type;
      option.textContent = type;
      typeSelect.appendChild(option);
    });
    typeSelect.disabled = false;
  }
}

function populateItemSelects() {
  const itemSelect = document.getElementById('itemSelect');
  if (itemSelect) {
    itemSelect.innerHTML = '<option value="">-- Select an Item --</option>';
    items.forEach(item => {
      const option = document.createElement('option');
      option.value = item.name;
      option.textContent = `${item.name} (${item.rarity})`;
      itemSelect.appendChild(option);
    });
    itemSelect.disabled = false;
  }
}

function populateCurseSelects() {
  const curseSelect = document.getElementById('curseSelect');
  if (curseSelect && typeof CURSES_DATA !== 'undefined') {
    curseSelect.innerHTML = '<option value="">-- Select a Curse --</option>';
    CURSES_DATA.forEach(curse => {
      const option = document.createElement('option');
      option.value = curse.name;
      option.textContent = `${curse.name} - ${curse.stat} ${curse.power}`;
      curseSelect.appendChild(option);
    });
    curseSelect.disabled = false;
  }
}

function populateEnemySelect() {
  const enemySelect = document.getElementById('specificEnemySelect');
  if (enemySelect && typeof enemies !== 'undefined' && enemies.length > 0) {
    enemySelect.innerHTML = '<option value="">-- Select Specific Enemy --</option>';
    enemies.forEach((enemy, index) => {
      const option = document.createElement('option');
      option.value = index;
      option.textContent = `${enemy.name} (${enemy.game}) - ${enemy.stat} ${enemy.power}`;
      enemySelect.appendChild(option);
    });
    enemySelect.disabled = false;
  }
}

function populateSpaceSelect() {
  const spaceSelect = document.getElementById('spaceSelect');
  if (spaceSelect && typeof games !== 'undefined' && games.length > 0) {
    spaceSelect.innerHTML = '<option value="">-- Select a Game --</option>';

    // Sort games alphabetically
    const sortedGames = [...games].sort((a, b) => a.name.localeCompare(b.name));

    sortedGames.forEach(game => {
      const option = document.createElement('option');
      option.value = game.name;
      option.textContent = `${game.name} (${game.year} - ${game.type})`;
      spaceSelect.appendChild(option);
    });
    spaceSelect.disabled = false;
  }
}

function populateDifficultyLocationSelect() {
  const locationSelect = document.getElementById('difficultyLocationSelect');
  if (locationSelect && typeof LOCATIONS_DATA !== 'undefined' && LOCATIONS_DATA.length > 0) {
    locationSelect.innerHTML = '<option value="">-- Select a Location --</option>';

    // Sort locations by difficulty then by name
    const difficultyOrder = { 'Easy': 1, 'Medium': 2, 'Hard': 3 };
    const sortedLocations = [...LOCATIONS_DATA].sort((a, b) => {
      const diffDiff = difficultyOrder[a.difficulty] - difficultyOrder[b.difficulty];
      if (diffDiff !== 0) return diffDiff;
      return a.name.localeCompare(b.name);
    });

    sortedLocations.forEach((location, index) => {
      const option = document.createElement('option');
      option.value = index;
      option.textContent = `${location.name} (${location.difficulty} - ${location.game})`;
      locationSelect.appendChild(option);
    });
    locationSelect.disabled = false;
  }
}

function updateCurrentLocationDisplay() {
  const display = document.getElementById('currentLocationDisplay');
  const info = document.getElementById('currentLocationInfo');

  if (!display || !info) return;

  if (gameState && gameState.location) {
    display.style.display = 'block';
    info.innerHTML = `
      <strong>${gameState.location.name}</strong><br>
      Difficulty: ${gameState.location.difficulty} | Game: ${gameState.location.game}<br>
      Type: ${gameState.location.type}
    `;
  } else {
    display.style.display = 'none';
  }
}

function populateStatusGameSelect() {
  const statusGameSelect = document.getElementById('statusGameSelect');
  if (statusGameSelect && typeof gameConnections !== 'undefined') {
    statusGameSelect.innerHTML = '<option value="">-- Select a Game --</option>';

    // Get all unique game names from connections
    const allGames = new Set();
    Object.keys(gameConnections).forEach(game => allGames.add(game));
    Object.values(gameConnections).forEach(connectedGames => {
      connectedGames.forEach(game => allGames.add(game));
    });

    // Sort alphabetically and add to select
    Array.from(allGames).sort().forEach(gameName => {
      const option = document.createElement('option');
      option.value = gameName;
      option.textContent = gameName;
      statusGameSelect.appendChild(option);
    });

    statusGameSelect.disabled = false;
  }
}

function populateEventSelect() {
  const eventSelect = document.getElementById('eventSelect');
  if (eventSelect && typeof events !== 'undefined' && events.length > 0) {
    eventSelect.innerHTML = '<option value="">-- Select an Event --</option>';
    events.forEach((event, index) => {
      const option = document.createElement('option');
      option.value = event.name;
      option.textContent = event.name;
      eventSelect.appendChild(option);
    });
    eventSelect.disabled = false;
  }
}

function updateActiveCursesList() {
  const activeCursesList = document.getElementById('activeCursesList');
  const removeCurseSelect = document.getElementById('removeCurseSelect');

  if (!activeCursesList) return;

  if (!gameState || !gameState.activeCurses || gameState.activeCurses.length === 0) {
    activeCursesList.innerHTML = '<div style="color: #888; font-style: italic; text-align: center; padding: 20px;">No active curses</div>';
    if (removeCurseSelect) {
      removeCurseSelect.innerHTML = '<option value="">-- Select a Curse --</option>';
      removeCurseSelect.disabled = true;
    }
    return;
  }

  // Update active curses list
  activeCursesList.innerHTML = gameState.activeCurses.map((curse, index) => `
    <div style="padding: 10px; margin-bottom: 8px; background: rgba(255, 68, 68, 0.1); border-left: 3px solid #ff4444; border-radius: 4px;">
      <strong style="color: #ffaa66;">${curse.name}</strong><br>
      <small style="color: #aaa;">${curse.stat} - ${curse.power}</small>
    </div>
  `).join('');

  // Update remove curse select
  if (removeCurseSelect) {
    removeCurseSelect.innerHTML = '<option value="">-- Select a Curse --</option>';
    gameState.activeCurses.forEach((curse, index) => {
      const option = document.createElement('option');
      option.value = index;
      option.textContent = curse.name;
      removeCurseSelect.appendChild(option);
    });
    removeCurseSelect.disabled = false;
  }
}

function enableButtons() {
  document.getElementById('pickRandomGames')?.removeAttribute('disabled');
  document.getElementById('pickConnectedGames')?.removeAttribute('disabled');
  document.getElementById('pickRandomItem')?.removeAttribute('disabled');
  document.getElementById('pickRandomChoice')?.removeAttribute('disabled');
  document.getElementById('giveSelectedItem')?.removeAttribute('disabled');
  document.getElementById('generateRandomGame')?.removeAttribute('disabled');
  document.getElementById('addBeatenGame')?.removeAttribute('disabled');
  document.getElementById('addExcludedGame')?.removeAttribute('disabled');
  document.getElementById('new-game-btn')?.removeAttribute('disabled');

  if (events.length > 0) {
    document.getElementById('checkEvent')?.removeAttribute('disabled');
  }

  if (enemies.length > 0) {
    document.getElementById('statSelect')?.removeAttribute('disabled');
    document.getElementById('powerSelect')?.removeAttribute('disabled');
    document.getElementById('generateEnemy')?.removeAttribute('disabled');
  }
}

// ===== HELPER FUNCTIONS =====

function getStatColor(stat) {
  switch(stat) {
    case 'Strength': return '#ff4444';
    case 'Charisma': return '#9b59b6';
    case 'Intelligence': return '#3498db';
    case 'Dexterity': return '#4CAF50';
    default: return '#fff';
  }
}

// Reorganize layers to avoid arrow crossings
// Returns { reorganizedLayers: Map, gameToLayer: Map }
// ===== SUGIYAMA GRAPH LAYOUT ALGORITHM =====
// Connection cache to avoid redundant lookups
const connectionCache = new Map();

function getCachedConnections(gameName) {
  if (!connectionCache.has(gameName)) {
    connectionCache.set(gameName, getGameConnections(gameName));
  }
  return connectionCache.get(gameName);
}

// Build edge data structures for efficient graph traversal
function buildEdgeData(layers, gameToLayer) {
  const outgoingEdges = new Map(); // game -> [connected games]
  const incomingEdges = new Map(); // game -> [games that connect to this]

  layers.forEach(layer => {
    layer.forEach(gameData => {
      const gameName = gameData.name || gameData;
      const connections = getCachedConnections(gameName);

      outgoingEdges.set(gameName, []);
      if (!incomingEdges.has(gameName)) {
        incomingEdges.set(gameName, []);
      }

      connections.forEach(targetGame => {
        const targetLayer = gameToLayer.get(targetGame);
        const sourceLayer = gameToLayer.get(gameName);

        // Only consider forward edges (going down the graph)
        if (targetLayer !== undefined && targetLayer > sourceLayer) {
          outgoingEdges.get(gameName).push(targetGame);

          if (!incomingEdges.has(targetGame)) {
            incomingEdges.set(targetGame, []);
          }
          incomingEdges.get(targetGame).push(gameName);
        }
      });
    });
  });

  return { outgoingEdges, incomingEdges };
}

// Calculate median position of connected nodes (Sugiyama median heuristic)
function getMedianPosition(gameName, adjacentLayer, edgeMap, layerPositions) {
  const connectedGames = edgeMap.get(gameName) || [];

  if (connectedGames.length === 0) {
    return layerPositions.get(gameName) || 0;
  }

  // Get positions of connected games in adjacent layer
  const positions = connectedGames
    .map(g => layerPositions.get(g))
    .filter(p => p !== undefined)
    .sort((a, b) => a - b);

  if (positions.length === 0) {
    return layerPositions.get(gameName) || 0;
  }

  // Return median position
  const mid = Math.floor(positions.length / 2);
  if (positions.length % 2 === 0) {
    return (positions[mid - 1] + positions[mid]) / 2;
  } else {
    return positions[mid];
  }
}

// Sugiyama crossing minimization using median heuristic
function minimizeCrossings(layers, gameToLayer, edgeData) {
  const { outgoingEdges, incomingEdges } = edgeData;
  const layerPositions = new Map(); // Track current position of each game in its layer

  // Initialize positions
  layers.forEach((layer, layerIndex) => {
    layer.forEach((gameData, position) => {
      const gameName = gameData.name || gameData;
      layerPositions.set(gameName, position);
    });
  });

  // Perform bi-directional sweeps
  const numIterations = 4;
  for (let iter = 0; iter < numIterations; iter++) {
    // Sweep down (order each layer based on previous layer)
    for (let i = 1; i < layers.length; i++) {
      const currentLayer = layers[i];
      const previousLayer = layers[i - 1];

      // Calculate median position for each game based on incoming edges
      const medianValues = currentLayer.map((gameData, idx) => {
        const gameName = gameData.name || gameData;
        const median = getMedianPosition(gameName, previousLayer, incomingEdges, layerPositions);
        return { gameData, gameName, median, originalIndex: idx };
      });

      // Sort by median position
      medianValues.sort((a, b) => {
        if (a.median !== b.median) {
          return a.median - b.median;
        }
        return a.originalIndex - b.originalIndex; // Stable sort
      });

      // Update layer order and positions
      layers[i] = medianValues.map(v => v.gameData);
      medianValues.forEach((v, newPos) => {
        layerPositions.set(v.gameName, newPos);
      });
    }

    // Sweep up (order each layer based on next layer)
    for (let i = layers.length - 2; i >= 0; i--) {
      const currentLayer = layers[i];
      const nextLayer = layers[i + 1];

      // Calculate median position for each game based on outgoing edges
      const medianValues = currentLayer.map((gameData, idx) => {
        const gameName = gameData.name || gameData;
        const median = getMedianPosition(gameName, nextLayer, outgoingEdges, layerPositions);
        return { gameData, gameName, median, originalIndex: idx };
      });

      // Sort by median position
      medianValues.sort((a, b) => {
        if (a.median !== b.median) {
          return a.median - b.median;
        }
        return a.originalIndex - b.originalIndex; // Stable sort
      });

      // Update layer order and positions
      layers[i] = medianValues.map(v => v.gameData);
      medianValues.forEach((v, newPos) => {
        layerPositions.set(v.gameName, newPos);
      });
    }
  }

  return layers;
}

// Main reorganization function using Sugiyama method
function reorganizeMapLayers(pathData) {
  // Clear connection cache for fresh run
  connectionCache.clear();

  const gameToLayer = new Map();

  // Copy all games to their initial layers (as arrays for ordering)
  const originalLayers = Array.from(pathData.layers.keys()).sort((a, b) => a - b);
  const layers = [];

  originalLayers.forEach(distance => {
    const gamesAtLayer = pathData.layers.get(distance);
    const layerArray = [...gamesAtLayer];
    layers.push(layerArray);

    gamesAtLayer.forEach(gameData => {
      const gameName = gameData.name || gameData;
      gameToLayer.set(gameName, distance);
    });
  });

  // Build edge data structures
  const edgeData = buildEdgeData(layers, gameToLayer);

  // Apply Sugiyama crossing minimization
  const optimizedLayers = minimizeCrossings(layers, gameToLayer, edgeData);

  // Convert back to Map structure for compatibility
  const reorganizedLayers = new Map();
  originalLayers.forEach((distance, index) => {
    reorganizedLayers.set(distance, optimizedLayers[index]);
  });

  return { reorganizedLayers, gameToLayer };
}

// Apply horizontal offsets using improved coordinate assignment
// Based on Brandes-Köpf style algorithm for straight edges
function applyHorizontalOffsets(reorganizedLayers, gameToLayer, pathData) {
  const gameOffsets = new Map();
  const layerKeys = Array.from(reorganizedLayers.keys()).sort((a, b) => a - b);

  // Build edge data for coordinate assignment
  const layers = layerKeys.map(key => reorganizedLayers.get(key));
  const edgeData = buildEdgeData(layers, gameToLayer);
  const { outgoingEdges, incomingEdges } = edgeData;

  // Assign initial coordinates based on layer position
  const coordinates = new Map();
  const minSeparation = 140; // Minimum horizontal separation between nodes

  layers.forEach((layer, layerIndex) => {
    layer.forEach((gameData, position) => {
      const gameName = gameData.name || gameData;
      // Initial coordinate based on position in layer
      coordinates.set(gameName, position * minSeparation);
    });
  });

  // Refine coordinates using median of connected nodes (4 passes)
  for (let pass = 0; pass < 4; pass++) {
    // Downward pass: align with incoming edges
    for (let i = 1; i < layers.length; i++) {
      const currentLayer = layers[i];

      currentLayer.forEach((gameData, idx) => {
        const gameName = gameData.name || gameData;
        const incoming = incomingEdges.get(gameName) || [];

        if (incoming.length > 0) {
          // Get coordinates of incoming nodes
          const incomingCoords = incoming
            .map(g => coordinates.get(g))
            .filter(c => c !== undefined)
            .sort((a, b) => a - b);

          if (incomingCoords.length > 0) {
            // Use median of incoming coordinates
            const mid = Math.floor(incomingCoords.length / 2);
            const medianCoord = incomingCoords.length % 2 === 0
              ? (incomingCoords[mid - 1] + incomingCoords[mid]) / 2
              : incomingCoords[mid];

            coordinates.set(gameName, medianCoord);
          }
        }
      });

      // Resolve conflicts: ensure minimum separation within layer
      const sortedLayer = [...currentLayer]
        .map(gd => ({ name: gd.name || gd, coord: coordinates.get(gd.name || gd) || 0 }))
        .sort((a, b) => a.coord - b.coord);

      let previousCoord = -Infinity;
      sortedLayer.forEach(item => {
        const minCoord = previousCoord + minSeparation;
        if (coordinates.get(item.name) < minCoord) {
          coordinates.set(item.name, minCoord);
        }
        previousCoord = coordinates.get(item.name);
      });
    }

    // Upward pass: align with outgoing edges
    for (let i = layers.length - 2; i >= 0; i--) {
      const currentLayer = layers[i];

      currentLayer.forEach((gameData, idx) => {
        const gameName = gameData.name || gameData;
        const outgoing = outgoingEdges.get(gameName) || [];

        if (outgoing.length > 0) {
          // Get coordinates of outgoing nodes
          const outgoingCoords = outgoing
            .map(g => coordinates.get(g))
            .filter(c => c !== undefined)
            .sort((a, b) => a - b);

          if (outgoingCoords.length > 0) {
            // Use median of outgoing coordinates
            const mid = Math.floor(outgoingCoords.length / 2);
            const medianCoord = outgoingCoords.length % 2 === 0
              ? (outgoingCoords[mid - 1] + outgoingCoords[mid]) / 2
              : outgoingCoords[mid];

            coordinates.set(gameName, medianCoord);
          }
        }
      });

      // Resolve conflicts: ensure minimum separation within layer
      const sortedLayer = [...currentLayer]
        .map(gd => ({ name: gd.name || gd, coord: coordinates.get(gd.name || gd) || 0 }))
        .sort((a, b) => a.coord - b.coord);

      let previousCoord = -Infinity;
      sortedLayer.forEach(item => {
        const minCoord = previousCoord + minSeparation;
        if (coordinates.get(item.name) < minCoord) {
          coordinates.set(item.name, minCoord);
        }
        previousCoord = coordinates.get(item.name);
      });
    }
  }

  // Center the layout: find the middle coordinate and shift to 0
  let minCoord = Infinity;
  let maxCoord = -Infinity;
  coordinates.forEach(coord => {
    minCoord = Math.min(minCoord, coord);
    maxCoord = Math.max(maxCoord, coord);
  });
  const centerOffset = -(minCoord + maxCoord) / 2;

  // Convert absolute coordinates to offsets from center
  coordinates.forEach((coord, gameName) => {
    gameOffsets.set(gameName, coord + centerOffset);
  });

  return gameOffsets;
}

// Ensure amulet game is at the deepest layer
function pushAmuletToBottom(reorganizedLayers, gameToLayer, amuletGame) {
  const amuletLayer = gameToLayer.get(amuletGame);
  if (amuletLayer !== undefined) {
    const maxLayer = Math.max(...Array.from(gameToLayer.values()));

    // If amulet is not already at the deepest layer, move it there
    if (amuletLayer < maxLayer) {
      const currentLayerGames = reorganizedLayers.get(amuletLayer);
      const amuletData = currentLayerGames.find(g => (g.name || g) === amuletGame);

      if (amuletData) {
        // Remove from current layer
        const index = currentLayerGames.indexOf(amuletData);
        currentLayerGames.splice(index, 1);

        // Add to deepest layer
        const newLayer = maxLayer + 1;
        if (!reorganizedLayers.has(newLayer)) {
          reorganizedLayers.set(newLayer, []);
        }
        reorganizedLayers.get(newLayer).push(amuletData);
        gameToLayer.set(amuletGame, newLayer);
      }
    }
  }
}

// Generate map visualization HTML for given distance
function generateMapView(currentGame, amuletGame, maxDistance, precomputedPathData = null) {
  const pathData = precomputedPathData || findPathsUpToDistance(currentGame, amuletGame, maxDistance);
  if (!pathData) return '<p style="color: #888;">No path data available</p>';

  const visitedGames = gameState.visitedGames || [];
  const pastGames = visitedGames.filter(g => g !== currentGame);

  let html = '';

  // Create outer container with padding
  html += '<div style="position: relative; padding: 40px; width: 100%; max-height: 70vh; overflow: auto;">';

  // Container for game boxes - zoom to fit if needed
  html += '<div id="map-game-boxes" style="position: relative; display: flex; flex-direction: column; align-items: center; width: fit-content; min-width: 100%; transform-origin: top center; margin: 0 auto;">';

  // SVG for arrows - as child of game boxes so it scales together
  html += '<svg id="map-arrows" style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 1; overflow: visible;"></svg>';

  // Show past games first
  if (pastGames.length > 0) {
    html += '<div style="margin-bottom: 30px; padding-bottom: 20px; border-bottom: 2px solid #555;">';
    html += '<h3 style="color: #888; font-size: 14px; margin-bottom: 15px;">Past Journey</h3>';
    html += '<div style="display: flex; flex-direction: column; align-items: center; gap: 5px;">';

    pastGames.forEach((gameName, index) => {
      html += `
        <div style="
          background: #3a3a3a;
          border: 2px solid #555;
          border-radius: 6px;
          padding: 8px 16px;
          font-size: 12px;
          color: #888;
        ">
          ${index + 1}. ${gameName}
        </div>
      `;
      if (index < pastGames.length - 1) {
        html += '<div style="color: #555;">↓</div>';
      }
    });

    html += '</div></div>';
  }

  // Build the layered path visualization
  // Shrink boxes significantly and adjust spacing based on view type
  const shortestDistance = pathData.shortestDistance;
  const isMorePathsView = maxDistance > shortestDistance;

  const boxWidth = 120;  // Reduced from 180
  const boxHeight = 35;  // Reduced from 50
  const horizontalGap = 30;  // Reduced from 40
  const verticalGap = isMorePathsView ? 120 : 80;  // More vertical space for complex view

  let currentY = pastGames.length > 0 ? 50 : 20;

  // Reorganize layers to avoid arrow crossings
  const { reorganizedLayers, gameToLayer } = reorganizeMapLayers(pathData);

  // Ensure amulet game is at the bottom
  pushAmuletToBottom(reorganizedLayers, gameToLayer, amuletGame);

  // Apply horizontal offsets to avoid arrow-box collisions
  const gameOffsets = applyHorizontalOffsets(reorganizedLayers, gameToLayer, pathData);

  // Iterate through reorganized layers
  const layers = Array.from(reorganizedLayers.keys()).sort((a, b) => a - b).filter(layer => reorganizedLayers.get(layer).length > 0);

  layers.forEach((distance, layerIndex) => {
    const gamesAtLayer = reorganizedLayers.get(distance);
    const numGames = gamesAtLayer.length;

    // Calculate total width needed for this layer
    const totalWidth = numGames * boxWidth + (numGames - 1) * horizontalGap;

    html += `<div style="display: flex; justify-content: center; align-items: center; margin-bottom: ${verticalGap}px; position: relative; width: 100%; flex-wrap: nowrap; gap: ${horizontalGap}px;">`;

    gamesAtLayer.forEach((gameData, index) => {
      // gameData is now {name, isOnShortestPath}
      const gameName = gameData.name || gameData; // Handle both old and new format
      const isOnShortestPath = gameData.isOnShortestPath !== undefined ? gameData.isOnShortestPath : true;

      const isCurrentGame = gameName === currentGame;
      const isAmuletGame = gameName === amuletGame;
      const isPastGame = pastGames.includes(gameName);
      const isChoice = !isCurrentGame && !isAmuletGame && !isPastGame &&
        (gameState.currentChoices || []).includes(gameName);

      let boxColor = '#4a4440';
      let borderColor = '#cc6600';

      if (isCurrentGame) {
        boxColor = '#2196F3';
        borderColor = '#4CAF50';
      } else if (isAmuletGame) {
        boxColor = '#cc6600';
        borderColor = 'gold';
      } else if (isPastGame) {
        boxColor = '#3a3a3a';
        borderColor = '#555';
      } else if (isChoice) {
        boxColor = '#3d2d00';
        borderColor = '#ff9900';
      } else if (!isOnShortestPath) {
        // Games NOT on shortest path: dimmed/grayed out
        boxColor = '#2a2a2a';
        borderColor = '#444';
      }

      // Get horizontal offset for this game (if any)
      const horizontalOffset = gameOffsets.get(gameName) || 0;

      // Get encounter icon for this game
      const game = games.find(g => g.name === gameName);
      let encounterIcon = '';
      let encounterColor = '';

      // Get encounter type from gameState (randomly assigned per run)
      const encounterType = gameState.encounterTypes?.[gameName];

      if (game && encounterType && !isCurrentGame && !isAmuletGame && !isPastGame) {
        if (encounterType === 'combat') {
          encounterIcon = '!';
          // Color based on game type
          switch(game.type?.toLowerCase()) {
            case 'action': encounterColor = '#ff4444'; break;
            case 'deckbuilding': encounterColor = '#bb66ff'; break;
            case 'strategy': encounterColor = '#4488ff'; break;
            default: encounterColor = '#44ff44'; break;
          }
        } else if (encounterType === 'event') {
          encounterIcon = '?';
          encounterColor = '#bb66ff';
        } else if (encounterType === 'shop') {
          encounterIcon = '$';
          encounterColor = '#ffd700';
        }
      }

      const choiceAttr = isChoice ? ' data-is-choice="true"' : '';
      const choiceEnterHandler = isChoice
        ? `highlightChoicePath(event, '${gameName.replace(/'/g, "\\'")}'); showMapTooltip(event, '${gameName.replace(/'/g, "\\'")}')`
        : `showMapTooltip(event, '${gameName.replace(/'/g, "\\'")}')`;
      const choiceLeaveHandler = isChoice
        ? `clearChoicePath(); hideMapTooltip()`
        : `hideMapTooltip()`;
      const choiceShadow = isChoice
        ? '0 0 10px rgba(255, 153, 0, 0.6), 0 3px 6px rgba(0,0,0,0.3)'
        : '0 3px 6px rgba(0,0,0,0.3)';
      // Clicking a choice node in the map opens the read-only node detail modal
      const safeGN = gameName.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
      const mapClickHandler = isChoice
        ? `onclick="if(typeof openNodeModalFromMap==='function') openNodeModalFromMap('${safeGN}')"`
        : '';

      // Game-type badge label for map view (replaces the !?$ encounter icons)
      const gameTypeForBadge = game?.type || '';
      const mapTypeColors = { action: '#c0392b', deckbuilding: '#7d3c98', strategy: '#1a6fa0', traditional: '#1e8449' };
      const mapBadgeColor = isAmuletGame ? '#b7950b' : (mapTypeColors[gameTypeForBadge.toLowerCase()] || '#555');
      const mapBadgeLabel = isAmuletGame ? '🏺' : (gameTypeForBadge || '');
      const mapBadgeHTML = (mapBadgeLabel && isChoice)
        ? `<span style="position:absolute;bottom:-9px;left:50%;transform:translateX(-50%);background:${mapBadgeColor};color:white;border-radius:3px;padding:1px 5px;font-size:8px;font-weight:bold;white-space:nowrap;border:1px solid rgba(0,0,0,0.3);pointer-events:none;">${mapBadgeLabel}</span>`
        : '';

      html += `
        <div class="map-game-box-${gameName.replace(/\s+/g, '-')}" data-game="${gameName}"${choiceAttr}
             onmouseenter="${choiceEnterHandler}"
             onmousemove="moveMapTooltip(event)"
             onmouseleave="${choiceLeaveHandler}"
             ${mapClickHandler}
             style="
          background: ${boxColor};
          border: ${isChoice ? '3px' : '2px'} solid ${borderColor};
          border-radius: 6px;
          padding: 6px 10px;
          width: ${boxWidth}px;
          min-height: ${boxHeight}px;
          display: flex;
          align-items: center;
          justify-content: center;
          text-align: center;
          font-weight: bold;
          font-size: 11px;
          color: ${isCurrentGame ? 'white' : (isPastGame || (!isOnShortestPath && !isChoice) ? '#888' : '#e6d5b8')};
          box-shadow: ${choiceShadow};
          cursor: pointer;
          opacity: ${!isOnShortestPath && !isChoice && !isCurrentGame && !isAmuletGame ? '0.5' : '1'};
          transform: translateX(${horizontalOffset}px);
          position: relative;
          margin-bottom: ${isChoice ? '10px' : '0'};
        ">
          ${isCurrentGame ? '📍 ' : ''}${isChoice ? '◆ ' : ''}${gameName}${isAmuletGame ? ' 🏆' : ''}${isOnShortestPath && !isCurrentGame && !isAmuletGame && !isChoice ? ' ⭐' : ''}
          ${mapBadgeHTML}
        </div>
      `;
    });

    html += '</div>';
    currentY += boxHeight + verticalGap;
  });

  html += '</div>'; // Close game boxes container
  html += '</div>'; // Close relative container

  // Add tooltip for hover
  html += '<div id="map-tooltip" style="display: none; position: absolute; background: rgba(30, 30, 30, 0.95); border: 2px solid #cc6600; border-radius: 6px; padding: 10px; z-index: 10000; pointer-events: none; max-width: 350px; font-size: 11px; line-height: 1.4;"></div>';

  return html;
}

// Show map modal with all shortest paths to amulet game
function showMapModal() {
  // Validate game state
  if (!gameState || !gameState.currentGame || !gameState.amuletGame) {
    console.error('Map modal validation failed:', {
      hasGameState: !!gameState,
      hasCurrentGame: !!gameState?.currentGame,
      hasAmuletGame: !!gameState?.amuletGame,
      currentGame: gameState?.currentGame,
      amuletGame: gameState?.amuletGame
    });
    createGameModal('<div style="text-align: center;"><h2>Map Not Available</h2><p>Game state not properly initialized.</p><button onclick="closeGameModal()" style="padding: 10px 20px; margin-top: 20px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer;">Close</button></div>');
    return;
  }

  // currentGame is already a string (game name), not an object
  // amuletGame might be a string or an object depending on how it was set
  const currentGame = typeof gameState.currentGame === 'string' ? gameState.currentGame : gameState.currentGame.name;
  const amuletGame = typeof gameState.amuletGame === 'string' ? gameState.amuletGame : gameState.amuletGame.name;


  // Get shortest path info first
  const shortestPathData = findAllShortestPaths(currentGame, amuletGame);


  let mapHTML = '<div style="text-align: center;">';
  mapHTML += '<h2 style="color: gold; margin-bottom: 20px;">🗺️ Map to Amulet</h2>';

  if (!shortestPathData) {
    mapHTML += '<p style="color: #888;">No path found</p>';
    mapHTML += `<p style="color: #666; font-size: 12px; margin-top: 10px;">From: ${currentGame}<br>To: ${amuletGame}</p>`;
    mapHTML += '<p style="color: #888; font-size: 11px; margin-top: 10px;">The games may not be connected,<br>or you may be at an isolated node.</p>';
  } else {
    const shortestDist = shortestPathData.shortestDistance;

    // Show header with controls at the top
    mapHTML += '<div style="margin-bottom: 20px; padding: 15px; background: rgba(0,0,0,0.3); border-radius: 8px; display: flex; justify-content: space-between; align-items: center; gap: 15px;">';
    mapHTML += `<span style="color: #e6d5b8; font-weight: bold;">Shortest Path: ${shortestDist} steps</span>`;

    // Zoom controls
    mapHTML += `
      <div style="display: flex; align-items: center; gap: 10px;">
        <button onclick="zoomMap(0.8)" style="padding: 5px 10px; background: #555; border: none; border-radius: 4px; color: white; cursor: pointer; font-weight: bold;">-</button>
        <span id="map-zoom-level" style="color: #888; min-width: 50px; text-align: center;">100%</span>
        <button onclick="zoomMap(1.25)" style="padding: 5px 10px; background: #555; border: none; border-radius: 4px; color: white; cursor: pointer; font-weight: bold;">+</button>
        <button onclick="resetMapZoom()" style="padding: 5px 10px; background: #555; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 10px;">Reset</button>
      </div>
    `;

    mapHTML += `<button onclick="closeGameModal()" style="padding: 8px 20px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold;">Close</button>`;
    mapHTML += '</div>';

    // Show shortest distance view only
    mapHTML += '<div id="map-view-container">';
    mapHTML += generateMapView(currentGame, amuletGame, shortestDist);
    mapHTML += '</div>';

    mapHTML += '</div>';

    createGameModal(mapHTML);

    // Reset zoom level
    currentMapZoom = 1.0;

    // Draw arrows after modal is rendered
    const initialPathData = findPathsUpToDistance(currentGame, amuletGame, shortestDist);
    setTimeout(() => {
      const { gameToLayer } = reorganizeMapLayers(initialPathData);
      drawMapArrows(initialPathData, currentGame, amuletGame, gameToLayer);
    }, 150);
  }
}

// Auto-zoom the map to fit all content within the viewport
function autoZoomMapToFit() {
  const mapContainer = document.getElementById('map-view-container');
  if (!mapContainer) return;

  const modalContent = document.querySelector('.modal-content');
  if (!modalContent) return;

  // Get the game boxes container
  const gameBoxesContainer = document.getElementById('map-game-boxes');
  if (!gameBoxesContainer) return;

  // Get all game boxes to find the total bounds
  const gameBoxes = mapContainer.querySelectorAll('[data-game]');
  if (gameBoxes.length === 0) return;

  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;

  gameBoxes.forEach(box => {
    const rect = box.getBoundingClientRect();
    const containerRect = gameBoxesContainer.getBoundingClientRect();

    const left = rect.left - containerRect.left;
    const right = rect.right - containerRect.left;
    const top = rect.top - containerRect.top;
    const bottom = rect.bottom - containerRect.top;

    minX = Math.min(minX, left);
    maxX = Math.max(maxX, right);
    minY = Math.min(minY, top);
    maxY = Math.max(maxY, bottom);
  });

  const contentWidth = maxX - minX + 160; // Add padding
  const contentHeight = maxY - minY + 160; // Add padding

  // Get available space in modal
  const modalRect = modalContent.getBoundingClientRect();
  const availableWidth = modalRect.width - 60; // Account for padding
  const availableHeight = modalRect.height - 200; // Account for header and padding

  // Calculate scale to fit
  const scaleX = availableWidth / contentWidth;
  const scaleY = availableHeight / contentHeight;
  const scale = Math.min(scaleX, scaleY, 1.0); // Don't zoom in, only zoom out

  if (scale < 1.0) {
    // Apply zoom to the game boxes container
    gameBoxesContainer.style.transform = `scale(${scale})`;
    gameBoxesContainer.setAttribute('data-scale', scale);

    // Adjust container height to account for scaling
    const scaledHeight = contentHeight * scale;
    gameBoxesContainer.parentElement.style.minHeight = scaledHeight + 'px';
  } else {
    gameBoxesContainer.removeAttribute('data-scale');
  }
}

// Draw arrows between games on the map
function drawMapArrows(pathData, currentGame, amuletGame, gameToLayer = null) {
  const svg = document.getElementById('map-arrows');
  if (!svg) {
    console.error('SVG element not found!');
    return;
  }

  // Clear existing arrows
  svg.innerHTML = '';

  // Get parent dimensions and set SVG to fill it completely
  const parentRect = svg.parentElement.getBoundingClientRect();
  svg.setAttribute('width', parentRect.width);
  svg.setAttribute('height', Math.max(parentRect.height, 2000)); // Ensure enough height

  // Create arrowhead marker for shortest path
  const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');

  const marker = document.createElementNS('http://www.w3.org/2000/svg', 'marker');
  marker.setAttribute('id', 'map-arrowhead');
  marker.setAttribute('markerWidth', '10');
  marker.setAttribute('markerHeight', '10');
  marker.setAttribute('refX', '9');
  marker.setAttribute('refY', '5');
  marker.setAttribute('orient', 'auto');
  marker.setAttribute('markerUnits', 'userSpaceOnUse');

  const polygon = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
  polygon.setAttribute('points', '0,0 10,5 0,10');
  polygon.setAttribute('fill', '#4CAF50');
  marker.appendChild(polygon);
  defs.appendChild(marker);
  svg.appendChild(defs);

  // Get all game boxes
  const gameBoxes = document.querySelectorAll('[data-game]');
  const boxPositions = new Map();

  // Get the game boxes container to use as reference
  const gameBoxesContainer = document.getElementById('map-game-boxes');
  const containerRect = gameBoxesContainer ? gameBoxesContainer.getBoundingClientRect() : svg.getBoundingClientRect();

  gameBoxes.forEach(box => {
    const gameName = box.getAttribute('data-game');
    const rect = box.getBoundingClientRect();

    // Calculate position relative to the container (which is the SVG's parent)
    boxPositions.set(gameName, {
      x: rect.left - containerRect.left + rect.width / 2,
      y: rect.top - containerRect.top + rect.height / 2,
      bottom: rect.bottom - containerRect.top,
      top: rect.top - containerRect.top
    });
  });


  // Draw arrows between connected games
  const layers = Array.from(pathData.layers.keys()).sort((a, b) => a - b);

  let arrowsDrawn = 0;

  // Build a flat map of all games in all layers for quick lookup
  const allGamesInMap = new Map();
  const gameDistances = new Map(); // Track which distance each game is at

  // If reorganized layer data is provided, use it; otherwise use original pathData
  if (gameToLayer) {
    // Use the reorganized layer positions
    gameToLayer.forEach((distance, gameName) => {
      gameDistances.set(gameName, distance);
    });
    // Still need to populate allGamesInMap from pathData
    layers.forEach(distance => {
      const gamesAtLayer = pathData.layers.get(distance);
      gamesAtLayer.forEach(gameData => {
        const gameName = gameData.name || gameData;
        allGamesInMap.set(gameName, gameData);
      });
    });
  } else {
    // Use original pathData
    layers.forEach(distance => {
      const gamesAtLayer = pathData.layers.get(distance);
      gamesAtLayer.forEach(gameData => {
        const gameName = gameData.name || gameData;
        allGamesInMap.set(gameName, gameData);
        gameDistances.set(gameName, distance);
      });
    });
  }

  // Track drawn arrows to avoid duplicates
  const drawnArrows = new Set();

  // Collect all vertical arrows for cross-layer connections (only shortest path)
  const arrowsToDrawData = [];

  layers.forEach((distance, layerIndex) => {
    const gamesAtLayer = pathData.layers.get(distance);

    gamesAtLayer.forEach(fromGameData => {
      const fromGame = fromGameData.name || fromGameData;
      const fromIsOnShortestPath = fromGameData.isOnShortestPath !== undefined ? fromGameData.isOnShortestPath : true;
      const fromDistance = distance;

      // Skip if not on shortest path
      if (!fromIsOnShortestPath) return;

      const fromPos = boxPositions.get(fromGame);
      if (!fromPos) {
        return;
      }

      const connections = getGameConnections(fromGame);

      connections.forEach(toGame => {
        const toGameData = allGamesInMap.get(toGame);

        if (toGameData) {
          const toDistance = gameDistances.get(toGame);
          const toIsOnShortestPath = toGameData.isOnShortestPath !== undefined ? toGameData.isOnShortestPath : true;

          // Only draw arrows that are on the shortest path and go forward
          if (!toIsOnShortestPath || toDistance <= fromDistance) {
            return;
          }

          const arrowKey = `${fromGame}->${toGame}`;
          if (drawnArrows.has(arrowKey)) {
            return; // Already drawn this arrow
          }
          drawnArrows.add(arrowKey);

          const toPos = boxPositions.get(toGame);
          if (!toPos) {
            return;
          }

          // Store arrow data for later drawing
          arrowsToDrawData.push({
            fromGame,
            toGame,
            fromPos,
            toPos,
            fromDistance,
            toDistance
          });
        }
      });
    });
  });

  // Draw all shortest path arrows
  arrowsToDrawData.forEach(arrow => {
    const x1 = arrow.fromPos.x;
    const y1 = arrow.fromPos.bottom;
    const x2 = arrow.toPos.x;
    const y2 = arrow.toPos.top;

    // Use straight line for all connections
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
    line.setAttribute('x1', x1);
    line.setAttribute('y1', y1);
    line.setAttribute('x2', x2);
    line.setAttribute('y2', y2);
    line.setAttribute('stroke', '#4CAF50');
    line.setAttribute('stroke-width', '3');
    line.setAttribute('opacity', '0.8');
    line.setAttribute('marker-end', 'url(#map-arrowhead)');
    line.setAttribute('data-from', arrow.fromGame);
    line.setAttribute('data-to', arrow.toGame);
    svg.appendChild(line);

    arrowsDrawn++;
  });
}

// Highlight the shortest path from a choice game to the amulet game on the map.
// Called on mouseenter of a choice node.
function highlightChoicePath(event, choiceGame) {
  const amuletGame = typeof gameState.amuletGame === 'string'
    ? gameState.amuletGame
    : gameState.amuletGame?.name;
  if (!amuletGame) return;

  // Get the path from this choice to the amulet
  const path = bfsPath(choiceGame, amuletGame);
  const pathSet = new Set(path || [choiceGame]);

  // Collect all choice games so we can keep them at full opacity
  const choiceSet = new Set(gameState.currentChoices || []);

  // Dim all map nodes that aren't on this choice's path
  const allNodes = document.querySelectorAll('[data-game]');
  allNodes.forEach(node => {
    const name = node.getAttribute('data-game');
    const isOnPath = pathSet.has(name);
    const isChoice = choiceSet.has(name);
    const isHoveredChoice = name === choiceGame;

    if (isHoveredChoice) {
      node.style.borderColor = '#ffcc00';
      node.style.boxShadow = '0 0 16px rgba(255, 204, 0, 0.9), 0 3px 6px rgba(0,0,0,0.3)';
      node.style.opacity = '1';
    } else if (isOnPath) {
      node.style.borderColor = '#ff9900';
      node.style.boxShadow = '0 0 8px rgba(255, 153, 0, 0.5)';
      node.style.opacity = '1';
    } else if (isChoice) {
      // Other choices: dim slightly
      node.style.opacity = '0.35';
    } else {
      node.style.opacity = '0.25';
    }
  });

  // Highlight arrows on the path, dim others
  const svg = document.getElementById('map-arrows');
  if (svg) {
    svg.querySelectorAll('line').forEach(line => {
      const from = line.getAttribute('data-from');
      const to = line.getAttribute('data-to');
      if (pathSet.has(from) && pathSet.has(to)) {
        line.setAttribute('stroke', '#ffcc00');
        line.setAttribute('stroke-width', '4');
        line.setAttribute('opacity', '1');
      } else {
        line.setAttribute('opacity', '0.1');
      }
    });
  }
}

// Restore all map nodes and arrows to their default appearance.
function clearChoicePath() {
  const allNodes = document.querySelectorAll('[data-game]');
  allNodes.forEach(node => {
    node.style.opacity = '';
    node.style.borderColor = '';
    node.style.boxShadow = '';
  });

  const svg = document.getElementById('map-arrows');
  if (svg) {
    svg.querySelectorAll('line').forEach(line => {
      line.setAttribute('stroke', '#4CAF50');
      line.setAttribute('stroke-width', '3');
      line.setAttribute('opacity', '0.8');
    });
  }
}

// Map tooltip functions
function showMapTooltip(e, gameName) {
  const game = games.find(g => g.name === gameName);
  if (!game) return;

  const tooltip = document.getElementById('map-tooltip');
  if (!tooltip) return;

  // Build connections HTML
  const influences = game.gamesInfluenced ?? [];
  const influencedBy = getInfluencedByGames(gameName);

  let connectionsHTML = '';
  if (influencedBy.length > 0) {
    connectionsHTML += `<div style="margin-top: 8px;"><strong style="color: #4CAF50;">Influenced By:</strong><div style="display: grid; grid-template-columns: 1fr 1fr; gap: 4px; margin-top: 4px;">${influencedBy.map(g => `<span style="background: rgba(76, 175, 80, 0.1); border: 1px solid rgba(76, 175, 80, 0.3); padding: 2px 6px; border-radius: 3px; font-size: 10px; word-wrap: break-word; line-height: 1.3;">${g} → ${gameName}</span>`).join('')}</div></div>`;
  }
  if (influences.length > 0) {
    connectionsHTML += `<div style="margin-top: 8px;"><strong style="color: #9b59b6;">Influences:</strong><div style="display: grid; grid-template-columns: 1fr 1fr; gap: 4px; margin-top: 4px;">${influences.map(g => `<span style="background: rgba(155, 89, 182, 0.1); border: 1px solid rgba(155, 89, 182, 0.3); padding: 2px 6px; border-radius: 3px; font-size: 10px; word-wrap: break-word; line-height: 1.3;">${gameName} → ${g}</span>`).join('')}</div></div>`;
  }
  if (influencedBy.length === 0 && influences.length === 0) {
    connectionsHTML = '<div style="margin-top: 8px; color: #888;">No connections</div>';
  }

  // Build tags HTML
  let tagsHTML = '';
  if (game.tags && game.tags.length > 0) {
    tagsHTML = `
      <div style="margin-top: 10px; padding-top: 8px; border-top: 1px solid rgba(255,255,255,0.2);">
        <div style="font-size: 11px; color: #888; margin-bottom: 4px;">Tags:</div>
        <div style="display: flex; flex-wrap: wrap; gap: 4px;">
          ${game.tags.map(tag => `
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

  tooltip.innerHTML = `<h4 style="margin: 0 0 8px 0; color: #e6d5b8;">${gameName}</h4>
    <div>Release Year: ${game.year || '—'}</div>
    <div>Type: ${game.type || '—'}</div>
    <div class="mini-map">${connectionsHTML}</div>
    ${tagsHTML}`;

  tooltip.style.display = 'block';
  moveMapTooltip(e);
}

function moveMapTooltip(e) {
  const tooltip = document.getElementById('map-tooltip');
  if (!tooltip) return;

  const offset = 14;
  const tooltipRect = tooltip.getBoundingClientRect();
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;

  // Calculate initial position
  let left = e.clientX + offset;
  let top = e.clientY + offset;

  // Check if tooltip would go off the right edge
  if (left + tooltipRect.width > viewportWidth) {
    left = e.clientX - tooltipRect.width - offset;
  }

  // Check if tooltip would go off the bottom edge
  if (top + tooltipRect.height > viewportHeight) {
    top = e.clientY - tooltipRect.height - offset;
  }

  // Keep tooltip on screen (left edge)
  if (left < 0) {
    left = offset;
  }

  // Keep tooltip on screen (top edge)
  if (top < 0) {
    top = offset;
  }

  tooltip.style.left = left + 'px';
  tooltip.style.top = top + 'px';
}

function hideMapTooltip() {
  const tooltip = document.getElementById('map-tooltip');
  if (tooltip) {
    tooltip.style.display = 'none';
  }
}

// Map zoom functions
let currentMapZoom = 1.0;

function zoomMap(factor) {
  const gameBoxesContainer = document.getElementById('map-game-boxes');
  if (!gameBoxesContainer) return;

  currentMapZoom *= factor;
  currentMapZoom = Math.max(0.25, Math.min(currentMapZoom, 3.0)); // Limit zoom between 25% and 300%

  gameBoxesContainer.style.transform = `scale(${currentMapZoom})`;
  gameBoxesContainer.setAttribute('data-scale', currentMapZoom);

  // Update zoom level display
  const zoomDisplay = document.getElementById('map-zoom-level');
  if (zoomDisplay) {
    zoomDisplay.textContent = Math.round(currentMapZoom * 100) + '%';
  }

  // Adjust container height to account for scaling
  const contentHeight = gameBoxesContainer.scrollHeight;
  const scaledHeight = contentHeight * currentMapZoom;
  gameBoxesContainer.parentElement.style.minHeight = scaledHeight + 'px';
}

function resetMapZoom() {
  currentMapZoom = 1.0;
  const gameBoxesContainer = document.getElementById('map-game-boxes');
  if (!gameBoxesContainer) return;

  gameBoxesContainer.style.transform = 'scale(1.0)';
  gameBoxesContainer.setAttribute('data-scale', '1.0');

  // Update zoom level display
  const zoomDisplay = document.getElementById('map-zoom-level');
  if (zoomDisplay) {
    zoomDisplay.textContent = '100%';
  }

  // Reset container height
  gameBoxesContainer.parentElement.style.minHeight = '';
}

// Make zoom functions globally available
window.zoomMap = zoomMap;
window.resetMapZoom = resetMapZoom;

function showCombatModal() {
  if (enemies.length === 0) return;

  // Set phase to combat
  gameState.phase = 'combat';
  updateInventory(); // Refresh item UI to update usable item buttons

  // Determine stat based on current game type
  const currentGameObj = games.find(g => g.name === gameState.currentGame);
  let requiredStat = 'Strength'; // Default

  if (currentGameObj && currentGameObj.type) {
    const gameType = currentGameObj.type.toLowerCase();
    switch(gameType) {
      case 'action': requiredStat = 'Strength'; break;
      case 'deckbuilding': requiredStat = 'Charisma'; break;
      case 'strategy': requiredStat = 'Intelligence'; break;
      case 'traditional': requiredStat = 'Dexterity'; break;
      default: requiredStat = 'Strength';
    }
  }

  // Difficulty scales with number of games beaten (thresholds match getDifficultyTier)
  const gamesBeaten = gameState.totalGamesBeaten || 0;
  const _thresholds = (typeof DIFFICULTY_THRESHOLDS !== 'undefined') ? DIFFICULTY_THRESHOLDS : { MEDIUM: 4, HARD: 8, INSANE: 12 };
  let powerText = 'Low';
  if (gamesBeaten >= _thresholds.HARD) {
    powerText = 'High';
  } else if (gamesBeaten >= _thresholds.MEDIUM) {
    powerText = 'Medium';
  }

  // Use pre-assigned enemy from node modal if available, otherwise pick randomly
  const _preAssigned = gameState.choiceDetails?.[gameState.currentGame]?.enemies;
  let enemy;
  if (_preAssigned && _preAssigned.length > 0) {
    enemy = _preAssigned[0];
    // Consume the pre-assigned slot so a retry generates fresh enemies
    delete gameState.choiceDetails[gameState.currentGame].enemies;
  } else {
    const matchingEnemies = enemies.filter(e =>
      e.powerLevel === powerText && e.stat === requiredStat
    );
    if (matchingEnemies.length === 0) return;
    enemy = matchingEnemies[Math.floor(Math.random() * matchingEnemies.length)];
  }

  // Initialize combat state
  const combat = window.CombatState.initializeCombat(enemy);

  // Apply any statuses queued by pre-combat events
  if (Array.isArray(gameState.pendingCombatStatuses) && gameState.pendingCombatStatuses.length > 0) {
    for (const pending of gameState.pendingCombatStatuses) {
      if (combat && combat.playerStatuses) {
        combat.playerStatuses[pending.status] = (combat.playerStatuses[pending.status] || 0) + (pending.stacks || 1);
      }
    }
    gameState.pendingCombatStatuses = [];
  }

  const enemyImagePath = getEnemyImagePath(enemy.name);
  const playerImagePath = getPlayerImagePath();

  // Create STS-style combat UI
  const combatHTML = `
    <div id="combat-container" style="
      display: flex;
      flex-direction: column;
      width: 92vw;
      max-width: 1400px;
      height: 90vh;
      max-height: 900px;
      padding: 20px;
      background: linear-gradient(135deg, #1a1410 0%, #2a1810 100%);
      border-radius: 12px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.6);
      position: relative;
      overflow: hidden;
    ">
      <!-- Stats Panel (Hidden by default, slides in from left) -->
      <div id="stats-panel" style="
        position: absolute;
        left: 0;
        top: 0;
        width: 320px;
        height: 100%;
        background: linear-gradient(145deg, rgba(30,30,40,0.98), rgba(20,20,30,0.98));
        border-right: 3px solid #4CAF50;
        border-radius: 12px 0 0 12px;
        padding: 25px;
        transform: translateX(-100%);
        transition: transform 0.3s ease;
        z-index: 1000;
        box-shadow: 4px 0 20px rgba(0,0,0,0.5);
        overflow-y: auto;
      ">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 2px solid rgba(76,175,80,0.3); padding-bottom: 15px;">
          <h3 style="margin: 0; color: #4CAF50; font-size: 24px;">📊 All Stats</h3>
          <button id="close-stats-btn" style="
            background: rgba(255,68,68,0.2);
            border: 2px solid #ff4444;
            border-radius: 6px;
            padding: 6px 12px;
            color: #ff6666;
            cursor: pointer;
            font-size: 18px;
            font-weight: bold;
          ">✕</button>
        </div>
        <div id="all-stats-content" style="display: flex; flex-direction: column; gap: 15px;">
          <!-- Will be populated with all stats -->
        </div>
      </div>

      <!-- Main Combat Area -->
      <div style="
        display: flex;
        flex-direction: column;
        flex: 1;
        min-height: 0;
        gap: 15px;
        overflow-y: auto;
      ">
        <!-- Combat Scene (Player vs Enemy + Dice) -->
        <div style="
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 15px;
        ">
          <!-- Combatants Area -->
          <div style="
            display: flex;
            flex-direction: column;
            gap: 15px;
            flex: 1;
            background: rgba(0,0,0,0.3);
            border: 2px solid #444;
            border-radius: 12px;
            padding: 25px;
          ">
            <!-- Player and Enemy Container -->
            <div style="
              display: flex;
              justify-content: space-between;
              align-items: center;
              gap: 30px;
              flex: 1;
            ">
            <!-- Player (Left) -->
            <div id="player-section" style="
              flex: 1;
              display: flex;
              flex-direction: column;
              align-items: center;
              position: relative;
            ">
              <!-- View All Stats Button -->
              <button id="view-stats-btn" style="
                position: absolute;
                top: -10px;
                left: 10px;
                background: rgba(76,175,80,0.2);
                border: 2px solid #4CAF50;
                border-radius: 6px;
                padding: 6px 12px;
                color: #4CAF50;
                cursor: pointer;
                font-size: 12px;
                font-weight: bold;
                text-transform: uppercase;
                transition: all 0.2s;
              ">📊 Stats</button>

              <div style="text-align: center; margin-bottom: 10px;">
                <p style="margin: 0 0 5px 0; font-size: 14px; color: #4CAF50; font-weight: bold; text-transform: uppercase;">YOU</p>
              </div>

              <!-- Player Image -->
              <div style="
                width: 200px;
                height: 200px;
                margin-bottom: 12px;
                border-radius: 8px;
                background: rgba(0,0,0,0.3);
                padding: 8px;
                border: 2px solid rgba(76,175,80,0.4);
                display: flex;
                align-items: center;
                justify-content: center;
              ">
                <img src="${playerImagePath}" style="
                  width: 100%;
                  height: 100%;
                  image-rendering: pixelated;
                  object-fit: contain;
                " alt="Player">
              </div>

              <!-- Health and Block Bar -->
              <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">
                <!-- Block Display -->
                <div id="player-block-display" style="
                  position: relative;
                  width: 50px;
                  height: 50px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  display: none;
                ">
                  <!-- Shield Icon -->
                  <div style="
                    position: absolute;
                    width: 100%;
                    height: 100%;
                    font-size: 50px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: #66ccff;
                    text-shadow: 0 0 8px rgba(102,204,255,0.5);
                  ">🛡️</div>
                  <!-- Block Value -->
                  <div id="player-block-value" style="
                    position: relative;
                    z-index: 1;
                    font-size: 18px;
                    font-weight: bold;
                    color: white;
                    text-shadow:
                      -1px -1px 0 #000,
                      1px -1px 0 #000,
                      -1px 1px 0 #000,
                      1px 1px 0 #000,
                      0 0 4px #000;
                  ">0</div>
                </div>

                <!-- HP Bar -->
                <div style="background: #2a2a2a; border-radius: 6px; height: 26px; width: 200px; position: relative; overflow: hidden; border: 2px solid #4CAF50;">
                  <div id="player-hp-bar" style="
                    background: linear-gradient(90deg, #4CAF50, #2E7D32);
                    height: 100%;
                    width: ${(health / maxHealth) * 100}%;
                    transition: width 0.3s ease;
                  "></div>
                  <span id="player-hp" style="
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    font-size: 14px;
                    font-weight: bold;
                    text-shadow: 0 0 4px black;
                    color: white;
                  ">${health}/${maxHealth}</span>
                </div>
              </div>

              <!-- Player Effects -->
              <div id="player-effects" style="font-size: 12px; text-align: center; min-height: 20px;">
                <!-- Effects will appear here -->
              </div>
            </div>

            <!-- Enemy Intent Display -->
            <div style="
              display: flex;
              flex-direction: column;
              align-items: center;
              gap: 8px;
              padding: 10px;
            ">
              <div style="
                font-size: 14px;
                font-weight: bold;
                color: #ffaa44;
                text-transform: uppercase;
                letter-spacing: 1px;
                margin-bottom: 5px;
              ">ENEMY INTENT</div>

              <!-- Enemy Dice Container -->
              <div style="
                background: rgba(204,51,51,0.1);
                border: 2px solid #cc3333;
                border-radius: 8px;
                padding: 8px;
              ">
                <div id="enemy-intent-dice-container" style="
                  width: 120px;
                  height: 120px;
                  position: relative;
                "></div>
              </div>

              <!-- Enemy Intent Text -->
              <div id="enemy-intent-text" style="
                background: rgba(0,0,0,0.5);
                padding: 8px 16px;
                border-radius: 6px;
                font-size: 14px;
                font-weight: bold;
                color: #ffaa44;
                text-align: center;
                min-width: 150px;
              ">
                Rolling...
              </div>
            </div>

            <!-- Enemy (Right) -->
            <div id="enemy-section" style="
              flex: 1;
              display: flex;
              flex-direction: column;
              align-items: center;
              position: relative;
            ">
              <div style="text-align: center; margin-bottom: 10px;">
                <h3 style="margin: 0 0 2px 0; color: #ff6644; font-size: 22px; text-shadow: 1px 1px 2px rgba(0,0,0,0.5);">${enemy.name}</h3>
                <p style="margin: 0 0 8px 0; font-size: 12px; color: #999; font-style: italic;">${enemy.game}</p>
              </div>

              <!-- Enemy Image -->
              <div style="
                width: 200px;
                height: 200px;
                margin-bottom: 12px;
                border-radius: 8px;
                background: rgba(0,0,0,0.3);
                padding: 8px;
                border: 2px solid rgba(255,68,68,0.4);
                display: flex;
                align-items: center;
                justify-content: center;
              ">
                <img src="${enemyImagePath}" style="
                  width: 100%;
                  height: 100%;
                  image-rendering: pixelated;
                  object-fit: contain;
                " alt="${enemy.name}" onerror="this.style.display='none'">
              </div>

              <!-- Health and Block Bar -->
              <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">
                <!-- Block Display -->
                <div id="enemy-block-display" style="
                  position: relative;
                  width: 50px;
                  height: 50px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  display: none;
                ">
                  <!-- Shield Icon -->
                  <div style="
                    position: absolute;
                    width: 100%;
                    height: 100%;
                    font-size: 50px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: #66ccff;
                    text-shadow: 0 0 8px rgba(102,204,255,0.5);
                  ">🛡️</div>
                  <!-- Block Value -->
                  <div id="enemy-block-value" style="
                    position: relative;
                    z-index: 1;
                    font-size: 18px;
                    font-weight: bold;
                    color: white;
                    text-shadow:
                      -1px -1px 0 #000,
                      1px -1px 0 #000,
                      -1px 1px 0 #000,
                      1px 1px 0 #000,
                      0 0 4px #000;
                  ">0</div>
                </div>

                <!-- HP Bar -->
                <div style="background: #2a2a2a; border-radius: 6px; height: 26px; width: 200px; position: relative; overflow: hidden; border: 2px solid #ff4444;">
                  <div id="enemy-hp-bar" style="
                    background: linear-gradient(90deg, #ff4444, #cc0000);
                    height: 100%;
                    width: 100%;
                    transition: width 0.3s ease;
                  "></div>
                  <span id="enemy-hp-text" style="
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    font-size: 14px;
                    font-weight: bold;
                    text-shadow: 0 0 4px black;
                    color: white;
                  ">${enemy.health}/${enemy.health}</span>
                </div>
              </div>

              <!-- Enemy Stats -->
              <div style="
                background: rgba(0,0,0,0.4);
                border: 1px solid #ff4444;
                border-radius: 6px;
                padding: 8px 16px;
                margin-bottom: 8px;
              ">
                <div style="display: flex; gap: 15px; font-size: 13px; justify-content: center;">
                  <div style="text-align: center;">
                    <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">AC</p>
                    <p style="margin: 2px 0 0 0; color: #66ccff; font-weight: bold; font-size: 16px;">${enemy.armorClass}</p>
                  </div>
                </div>
              </div>

              <!-- Enemy Effects -->
              <div id="enemy-effects" style="font-size: 12px; text-align: center; min-height: 20px;">
                <!-- Effects will appear here -->
              </div>

              <!-- View Combat Log Button -->
              <button id="view-log-btn" style="
                position: absolute;
                top: -10px;
                right: 10px;
                background: rgba(255,204,102,0.2);
                border: 2px solid #ffcc66;
                border-radius: 6px;
                padding: 6px 12px;
                color: #ffcc66;
                cursor: pointer;
                font-size: 12px;
                font-weight: bold;
                text-transform: uppercase;
                transition: all 0.2s;
              ">📜 Log</button>
            </div>
            </div>
          </div>

          <!-- Dice Area (Bottom) -->
          <div id="dice-area" style="
            background: linear-gradient(145deg, rgba(204,102,0,0.15), rgba(204,102,0,0.05));
            border: 3px solid #cc6600;
            border-radius: 12px;
            padding: 15px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            box-shadow: inset 0 2px 8px rgba(0,0,0,0.3);
            position: relative;
          ">
            <!-- Obstruction Indicator (shown when Curse of Obstruction is active) -->
            <div id="obstruction-indicator" style="
              position: absolute;
              top: 10px;
              left: 50%;
              transform: translateX(-50%);
              background: rgba(255,100,100,0.9);
              border: 2px solid #ff4444;
              border-radius: 8px;
              padding: 8px 16px;
              color: white;
              font-weight: bold;
              font-size: 13px;
              text-align: center;
              display: none;
              box-shadow: 0 4px 12px rgba(255,0,0,0.4);
              z-index: 100;
            ">
              ⚠️ DISADVANTAGE: Roll twice, take lower!
            </div>

            <!-- Energy Display -->
            <div id="energy-display" style="
              position: absolute;
              top: 15px;
              left: 20px;
              display: flex;
              align-items: center;
              gap: 8px;
              background: rgba(255,204,0,0.15);
              border: 2px solid #ffcc00;
              border-radius: 8px;
              padding: 8px 16px;
              box-shadow: 0 2px 8px rgba(255,204,0,0.3);
            ">
              <div style="
                font-size: 18px;
                font-weight: bold;
                color: #ffcc00;
                text-transform: uppercase;
                letter-spacing: 1px;
              ">Energy:</div>
              <div id="energy-bolts" style="
                display: flex;
                gap: 4px;
                font-size: 24px;
              ">⚡⚡</div>
              <div id="energy-count" style="
                font-size: 18px;
                font-weight: bold;
                color: #ffcc00;
              ">2/2</div>
            </div>

            <!-- Dual Dice Container -->
            <div style="
              display: flex;
              gap: 30px;
              align-items: center;
              justify-content: center;
              width: 100%;
              margin-top: 20px;
            ">
              <!-- Attack D20 -->
              <div style="
                display: flex;
                flex-direction: column;
                align-items: center;
                flex: 1;
                max-width: 400px;
              ">
                <div style="
                  display: flex;
                  align-items: center;
                  gap: 8px;
                  margin-bottom: 10px;
                ">
                  <div style="
                    font-size: 14px;
                    font-weight: bold;
                    color: #cc6600;
                    letter-spacing: 0.5px;
                  ">⚔️ Attack for ${attack} damage</div>
                  <div style="
                    font-size: 12px;
                    color: #ffcc00;
                    background: rgba(255,204,0,0.2);
                    border: 1px solid #ffcc00;
                    border-radius: 4px;
                    padding: 2px 6px;
                  ">1⚡</div>
                </div>
                <div style="
                  background: rgba(204,102,0,0.1);
                  border: 2px solid #cc6600;
                  border-radius: 8px;
                  padding: 10px;
                  width: 100%;
                ">
                  <div id="attack-dice-container" class="dice-clickable" style="
                    width: 100%;
                    height: 150px;
                    cursor: pointer;
                    position: relative;
                  "></div>
                  <div id="attack-roll-result" style="
                    margin-top: 6px;
                    font-size: 14px;
                    text-align: center;
                    width: 100%;
                    min-height: 20px;
                  "></div>

                  <!-- Attack Confirm/Reroll Buttons -->
                  <div style="display: flex; flex-direction: column; gap: 8px; margin-top: 10px;">
                    <button id="attack-confirm-btn" disabled style="
                      padding: 8px 20px;
                      font-size: 14px;
                      background: linear-gradient(145deg, #555, #444);
                      border: 2px solid #666;
                      border-radius: 6px;
                      color: #888;
                      cursor: not-allowed;
                      font-weight: bold;
                      opacity: 0.5;
                      text-transform: uppercase;
                      letter-spacing: 0.5px;
                    ">✓ Confirm</button>
                    <button id="attack-reroll-btn" disabled style="
                      padding: 6px 16px;
                      font-size: 12px;
                      background: linear-gradient(145deg, #555, #444);
                      border: 2px solid #666;
                      border-radius: 6px;
                      color: #888;
                      cursor: not-allowed;
                      font-weight: bold;
                      opacity: 0.5;
                      text-transform: uppercase;
                      letter-spacing: 0.5px;
                    ">🔄 Reroll (0)</button>
                  </div>
                </div>
              </div>

              <!-- Defense D6 -->
              <div style="
                display: flex;
                flex-direction: column;
                align-items: center;
                flex: 1;
                max-width: 400px;
              ">
                <div style="
                  display: flex;
                  align-items: center;
                  gap: 8px;
                  margin-bottom: 10px;
                ">
                  <div style="
                    font-size: 14px;
                    font-weight: bold;
                    color: #66ccff;
                    letter-spacing: 0.5px;
                  ">🛡️ Block Roll</div>
                  <div style="
                    font-size: 12px;
                    color: #ffcc00;
                    background: rgba(255,204,0,0.2);
                    border: 1px solid #ffcc00;
                    border-radius: 4px;
                    padding: 2px 6px;
                  ">1⚡</div>
                </div>
                <div style="
                  background: rgba(102,204,255,0.1);
                  border: 2px solid #66ccff;
                  border-radius: 8px;
                  padding: 10px;
                  width: 100%;
                ">
                  <div id="defense-dice-container" class="dice-clickable" style="
                    width: 100%;
                    height: 150px;
                    cursor: pointer;
                    position: relative;
                  "></div>
                  <div id="defense-roll-result" style="
                    margin-top: 6px;
                    font-size: 14px;
                    text-align: center;
                    width: 100%;
                    min-height: 20px;
                  "></div>

                  <!-- Defense Confirm/Reroll Buttons -->
                  <div style="display: flex; flex-direction: column; gap: 8px; margin-top: 10px;">
                    <button id="defense-confirm-btn" disabled style="
                      padding: 8px 20px;
                      font-size: 14px;
                      background: linear-gradient(145deg, #555, #444);
                      border: 2px solid #666;
                      border-radius: 6px;
                      color: #888;
                      cursor: not-allowed;
                      font-weight: bold;
                      opacity: 0.5;
                      text-transform: uppercase;
                      letter-spacing: 0.5px;
                    ">✓ Confirm</button>
                    <button id="defense-reroll-btn" disabled style="
                      padding: 6px 16px;
                      font-size: 12px;
                      background: linear-gradient(145deg, #555, #444);
                      border: 2px solid #666;
                      border-radius: 6px;
                      color: #888;
                      cursor: not-allowed;
                      font-weight: bold;
                      opacity: 0.5;
                      text-transform: uppercase;
                      letter-spacing: 0.5px;
                    ">🔄 Reroll (0)</button>
                  </div>
                </div>
              </div>
            </div>

            <!-- End Turn Button -->
            <button id="end-turn-btn" disabled style="
              position: absolute;
              top: 10px;
              right: 10px;
              padding: 10px 30px;
              font-size: 16px;
              background: linear-gradient(145deg, #555, #444);
              border: 3px solid #666;
              border-radius: 8px;
              color: #888;
              cursor: not-allowed;
              font-weight: bold;
              opacity: 0.5;
              text-transform: uppercase;
              letter-spacing: 1px;
              box-shadow: 0 4px 12px rgba(0,0,0,0.4);
              transition: all 0.3s ease;
            ">⏭️ End Turn</button>
          </div>
        </div>

      </div>

      <!-- Combat Log Panel (Hidden by default, slides in from right) -->
      <div id="log-panel" style="
        position: absolute;
        right: 0;
        top: 0;
        width: 380px;
        height: 100%;
        background: linear-gradient(145deg, rgba(30,30,40,0.98), rgba(20,20,30,0.98));
        border-left: 3px solid #ffcc66;
        border-radius: 0 12px 12px 0;
        padding: 25px;
        transform: translateX(100%);
        transition: transform 0.3s ease;
        z-index: 1000;
        box-shadow: -4px 0 20px rgba(0,0,0,0.5);
        overflow-y: auto;
      ">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 2px solid rgba(255,204,102,0.3); padding-bottom: 15px;">
          <h3 style="margin: 0; color: #ffcc66; font-size: 24px;">📜 Combat Log</h3>
          <button id="close-log-btn" style="
            background: rgba(255,68,68,0.2);
            border: 2px solid #ff4444;
            border-radius: 6px;
            padding: 6px 12px;
            color: #ff6666;
            cursor: pointer;
            font-size: 18px;
            font-weight: bold;
          ">✕</button>
        </div>
        <div id="combat-log-messages" style="display: flex; flex-direction: column; gap: 8px;">
          <p style="color: #aaa; margin: 0;">⚔️ Combat started! Turn <span style="color: #ffcc66;">1</span></p>
        </div>
      </div>
    </div>
  `;

  createGameModal(combatHTML);

  // Create tooltip element and append to document.body (not inside modal to avoid overflow issues)
  const existingTooltip = document.getElementById('combat-item-tooltip');
  if (existingTooltip) existingTooltip.remove();

  const tooltip = document.createElement('div');
  tooltip.id = 'combat-item-tooltip';
  tooltip.style.cssText = `
    position: fixed;
    display: none;
    background: linear-gradient(145deg, rgba(30,30,40,0.98), rgba(20,20,30,0.98));
    border: 3px solid #888;
    border-radius: 8px;
    padding: 12px 15px;
    max-width: 300px;
    z-index: 9000;
    pointer-events: none;
    box-shadow: 0 4px 20px rgba(0,0,0,0.8);
  `;

  const tooltipContent = document.createElement('div');
  tooltipContent.id = 'combat-tooltip-content';
  tooltip.appendChild(tooltipContent);
  document.body.appendChild(tooltip);

  // Add hover effects CSS for items
  const style = document.createElement('style');
  style.textContent = `
    .item-icon {
      transform: scale(1);
    }
    .item-icon:hover {
      transform: scale(1.15);
      filter: brightness(1.3);
      box-shadow: 0 0 15px rgba(255, 204, 102, 0.6);
      z-index: 10;
    }
    .item-icon:active {
      transform: scale(1.05);
    }
  `;
  document.head.appendChild(style);

  // Initialize 3D dice renderers (separate instances for attack, defense, and enemy)
  const attackDiceContainer = document.getElementById('attack-dice-container');
  const defenseDiceContainer = document.getElementById('defense-dice-container');
  const enemyIntentDiceContainer = document.getElementById('enemy-intent-dice-container');

  const attackRenderer = new window.DiceRendererInstance();
  attackRenderer.init(attackDiceContainer);
  attackRenderer.createDice(combat.dice.attack);

  const defenseRenderer = new window.DiceRendererInstance();
  defenseRenderer.init(defenseDiceContainer);
  defenseRenderer.createDice(combat.dice.defense);

  const enemyIntentRenderer = new window.DiceRendererInstance();
  enemyIntentRenderer.init(enemyIntentDiceContainer);
  enemyIntentRenderer.createDice(combat.dice.enemy);

  // Roll enemy dice and show intent
  showEnemyIntent();

  // Populate items bar
  populateItemsBar();

  // Check for Curse of Obstruction and show indicator
  const obstructionCurses = gameState.activeCurses ? gameState.activeCurses.filter(curse =>
    curse.name && curse.name.toLowerCase().includes('obstruction')
  ) : [];
  const obstructionIndicator = document.getElementById('obstruction-indicator');
  if (obstructionCurses.length > 0 && obstructionIndicator) {
    obstructionIndicator.style.display = 'block';
  }

  // Setup stats panel toggle
  setupStatsPanel();

  // Setup combat log panel toggle
  setupLogPanel();

  // Setup item tooltips
  setupItemTooltips();

  // Update energy display
  updateEnergyDisplay();

  // Pending roll state - stores roll data before confirmation
  const pendingRolls = {
    attack: null,
    defense: null
  };

  // Initialize reroll button text with current reroll count
  updateRerollButtonText();

  // Setup dice click handlers for both attack and defense
  attackDiceContainer.addEventListener('click', () => handleDiceClick('attack'));
  defenseDiceContainer.addEventListener('click', () => handleDiceClick('defense'));

  // Setup confirm button handlers
  document.getElementById('attack-confirm-btn').addEventListener('click', () => handleConfirm('attack'));
  document.getElementById('defense-confirm-btn').addEventListener('click', () => handleConfirm('defense'));

  // Setup reroll button handlers
  document.getElementById('attack-reroll-btn').addEventListener('click', () => handleReroll('attack'));
  document.getElementById('defense-reroll-btn').addEventListener('click', () => handleReroll('defense'));

  // Show enemy intent by rolling their dice
  function showEnemyIntent() {
    const currentCombat = window.CombatState.getCombatState();
    if (!currentCombat || !currentCombat.enemy.plannedAction) return;

    const plannedAction = currentCombat.enemy.plannedAction;
    const intentTextEl = document.getElementById('enemy-intent-text');

    // Animate the enemy dice
    enemyIntentRenderer.rollDice(currentCombat.dice.enemy, plannedAction.sideIndex, (result) => {
      // Update the intent text based on action type
      if (plannedAction.type === 'attack') {
        const totalDamage = plannedAction.value + currentCombat.enemy.strength;
        intentTextEl.innerHTML = `<span style="color: #ff6666;">⚔️ The enemy will attack for ${totalDamage} damage</span>`;
      } else {
        const totalBlock = plannedAction.value + currentCombat.enemy.defence;
        intentTextEl.innerHTML = `<span style="color: #66ccff;">🛡️ The enemy will gain ${totalBlock} block</span>`;
      }
    });
  }

  // Update energy display
  function updateEnergyDisplay() {
    const combat = window.CombatState.getCombatState();
    if (!combat) return;

    const energyBolts = document.getElementById('energy-bolts');
    const energyCount = document.getElementById('energy-count');

    if (energyBolts && energyCount) {
      // Show lightning bolts based on current energy
      const bolts = '⚡'.repeat(combat.player.energy);
      const greyBolts = '<span style="opacity: 0.3;">⚡</span>'.repeat(combat.player.maxEnergy - combat.player.energy);
      energyBolts.innerHTML = bolts + greyBolts;
      energyCount.textContent = `${combat.player.energy}/${combat.player.maxEnergy}`;
    }

    // Update dice container opacity based on available energy
    const attackContainer = document.getElementById('attack-dice-container');
    const defenseContainer = document.getElementById('defense-dice-container');

    if (combat.player.energy < 1) {
      if (attackContainer) attackContainer.style.opacity = '0.4';
      if (defenseContainer) defenseContainer.style.opacity = '0.4';
    } else {
      if (attackContainer) attackContainer.style.opacity = '1';
      if (defenseContainer) defenseContainer.style.opacity = '1';
    }
  }

  // Helper to update reroll button text with current count
  function updateRerollButtonText() {
    const attackRerollBtn = document.getElementById('attack-reroll-btn');
    const defenseRerollBtn = document.getElementById('defense-reroll-btn');
    const rerollCount = gameState.reroll || 0;

    if (attackRerollBtn) {
      attackRerollBtn.textContent = `🔄 Reroll (${rerollCount})`;
    }
    if (defenseRerollBtn) {
      defenseRerollBtn.textContent = `🔄 Reroll (${rerollCount})`;
    }
  }

  // Helper to enable/disable buttons
  function updateButtonStates(diceType, hasRoll, isConfirmed) {
    const confirmBtn = document.getElementById(`${diceType}-confirm-btn`);
    const rerollBtn = document.getElementById(`${diceType}-reroll-btn`);
    const rerollCount = gameState.reroll || 0;

    // Confirm button: enabled after roll, disabled after confirming or no roll
    if (confirmBtn) {
      if (hasRoll && !isConfirmed) {
        confirmBtn.disabled = false;
        confirmBtn.style.opacity = '1';
        confirmBtn.style.cursor = 'pointer';
        confirmBtn.style.background = 'linear-gradient(145deg, #4CAF50, #2E7D32)';
        confirmBtn.style.color = 'white';
        confirmBtn.style.borderColor = '#2E7D32';
      } else {
        confirmBtn.disabled = true;
        confirmBtn.style.opacity = '0.5';
        confirmBtn.style.cursor = 'not-allowed';
        confirmBtn.style.background = 'linear-gradient(145deg, #555, #444)';
        confirmBtn.style.color = '#888';
        confirmBtn.style.borderColor = '#666';
      }
    }

    // Reroll button: enabled after roll if reroll>0, disabled if reroll=0 or confirmed or no roll
    if (rerollBtn) {
      if (hasRoll && !isConfirmed && rerollCount > 0) {
        rerollBtn.disabled = false;
        rerollBtn.style.opacity = '1';
        rerollBtn.style.cursor = 'pointer';
        rerollBtn.style.background = 'linear-gradient(145deg, #9b59b6, #7d3c98)';
        rerollBtn.style.color = 'white';
        rerollBtn.style.borderColor = '#7d3c98';
      } else {
        rerollBtn.disabled = true;
        rerollBtn.style.opacity = '0.5';
        rerollBtn.style.cursor = 'not-allowed';
        rerollBtn.style.background = 'linear-gradient(145deg, #555, #444)';
        rerollBtn.style.color = '#888';
        rerollBtn.style.borderColor = '#666';
      }
    }
  }

  function handleDiceClick(diceType) {
    if (combat.phase !== 'player_turn') {
      return;
    }

    // Don't allow new rolls if this dice already has a pending roll
    if (pendingRolls[diceType]) {
      addCombatLogMessage('Please confirm or reroll the current roll first!', 'warning');
      return;
    }

    const currentCombat = window.CombatState.getCombatState();
    if (!currentCombat || currentCombat.player.energy < 1) {
      addCombatLogMessage('Not enough energy!', 'warning');
      return;
    }

    try {
      // Roll the dice through combat state
      const rollResult = window.CombatState.rollCombatDice(diceType);

      if (!rollResult.success) {
        addCombatLogMessage(rollResult.error, 'danger');
        return;
      }

      // Update energy display
      updateEnergyDisplay();

      // Get the appropriate renderer and result display
      const renderer = diceType === 'attack' ? attackRenderer : defenseRenderer;
      const resultDisplay = document.getElementById(`${diceType}-roll-result`);

      // Get the face number to show on the dice
      // For D20: use the rolled value (1-20)
      // For D6: use sideIndex + 1 to show correct face (1-6)
      const faceNumber = diceType === 'attack'
        ? rollResult.result.baseValue
        : rollResult.result.sideIndex + 1;

      // Animate the 3D dice
      renderer.rollDice(combat.dice[diceType], faceNumber, (result) => {
        if (diceType === 'attack') {
          // Hide obstruction indicator if curse expired
          const obstructionCursesAfterRoll = gameState.activeCurses ? gameState.activeCurses.filter(curse =>
            curse.name && curse.name.toLowerCase().includes('obstruction')
          ) : [];
          const obstructionIndicatorElement = document.getElementById('obstruction-indicator');
          if (obstructionCursesAfterRoll.length === 0 && obstructionIndicatorElement) {
            obstructionIndicatorElement.style.display = 'none';
          }

          // Calculate curse modifiers (but don't apply yet)
          let finalRoll = result;
          const statModifier = window.CombatState.getStatModifier();

          // Check for Curse of Failure
          const failureCurses = getCursesByType('failure');
          let failureDamage = 0;
          if (failureCurses.length > 0 && result === 1) {
            // Curse of Failure: Roll of 1 is auto-miss and deals damage
            failureDamage = failureCurses.reduce((sum, curse) =>
              sum + getPowerValue(curse.power, { Low: 2, Medium: 3, High: 4 }), 0
            );

            if (typeof calculateDamageReduction === 'function') {
              failureDamage = calculateDamageReduction(failureDamage);
            }

            // Treat roll as 0 for AC check (auto-miss)
            finalRoll = 0;
          }

          // Check for Curse of Weakness
          let cursePenalty = 0;
          let weaknessCurse = null;
          const weaknessCurses = getCursesByType('weakness');
          if (weaknessCurses.length > 0) {
            weaknessCurse = weaknessCurses[0];
            cursePenalty = getPowerValue(weaknessCurse.power, { Low: 2, Medium: 3, High: 4 });
          }

          const totalRoll = finalRoll + statModifier - cursePenalty;
          const hit = totalRoll >= combat.enemy.armorClass;

          // Calculate what damage WOULD be dealt (but don't apply it)
          let calculatedDamage = 0;
          let damagePreview = null;
          if (hit) {
            calculatedDamage = combat.player.attack;
            // Preview what would happen with block
            const enemyBlock = combat.enemy.effects.block || 0;
            const blockConsumed = Math.min(enemyBlock, calculatedDamage);
            const healthLost = calculatedDamage - blockConsumed;
            damagePreview = { blockConsumed, healthLost };
          }

          // Store pending roll data
          pendingRolls[diceType] = {
            result: result,
            finalRoll: finalRoll,
            statModifier: statModifier,
            cursePenalty: cursePenalty,
            weaknessCurse: weaknessCurse,
            failureCurses: failureCurses,
            failureDamage: failureDamage,
            totalRoll: totalRoll,
            hit: hit,
            damage: calculatedDamage,
            damagePreview: damagePreview
          };

          // Display roll result (preview)
          resultDisplay.innerHTML = `
            <div style="background: rgba(0,0,0,0.5); padding: 8px; border-radius: 6px;">
              <p style="margin: 2px 0; font-size: 12px;">Dice: <strong>${result}</strong></p>
              <p style="margin: 2px 0; font-size: 12px; color: ${getStatColor(combat.enemy.stat)};">+ ${combat.enemy.stat}: <strong>${statModifier}</strong></p>
              ${cursePenalty > 0 ? `<p style="margin: 2px 0; font-size: 12px; color: #ff6666;">- Weakness: <strong>${cursePenalty}</strong></p>` : ''}
              ${failureDamage > 0 ? `<p style="margin: 2px 0; font-size: 12px; color: #ff6666;">⚠️ Failure: <strong>${failureDamage} dmg to you</strong></p>` : ''}
              <p style="margin: 4px 0 0 0; font-size: 16px; color: ${hit ? '#4CAF50' : '#ff6666'};"><strong>${hit ? 'HIT!' : 'MISS'} (${totalRoll}/${combat.enemy.armorClass})</strong></p>
            </div>
          `;

        } else {
          // Defense dice - calculate block that would be gained
          const blockGained = rollResult.result.total;
          const newBlockTotal = (combat.player.effects.block || 0) + blockGained;

          // Store pending roll data
          pendingRolls[diceType] = {
            blockGained: blockGained,
            newBlockTotal: newBlockTotal
          };

          // Display roll result (preview)
          resultDisplay.innerHTML = `
            <div style="background: rgba(0,0,0,0.5); padding: 8px; border-radius: 6px;">
              <p style="margin: 2px 0; font-size: 16px; color: #66ccff;"><strong>+${blockGained} 🛡️</strong></p>
              <p style="margin: 4px 0 0 0; font-size: 12px;">Block: ${newBlockTotal}</p>
            </div>
          `;
        }

        // Enable confirm and reroll buttons
        updateButtonStates(diceType, true, false);
      });

    } catch (error) {
      console.error('Error rolling dice:', error);
      addCombatLogMessage(error.message, 'danger');
    }
  }

  // Handle confirming a roll (executes the stored effect)
  function handleConfirm(diceType) {
    if (!pendingRolls[diceType]) {
      return; // No pending roll
    }

    const pending = pendingRolls[diceType];

    if (diceType === 'attack') {
      // Execute attack effects
      if (pending.failureDamage > 0) {
        addCombatLogMessage(`Rolled a 1! Curse of Failure activated!`, 'danger');
        combat.player.health = Math.max(0, combat.player.health - pending.failureDamage);
        gameState.health = combat.player.health;
        updateCombatUI();
        addCombatLogMessage(`Curse of Failure dealt ${pending.failureDamage} damage!`, 'danger');
      }

      // Remove Curse of Weakness if it was applied
      if (pending.weaknessCurse) {
        addCombatLogMessage(`Curse of Weakness: -${pending.cursePenalty}`, 'warning');
        gameState.activeCurses.splice(gameState.activeCurses.indexOf(pending.weaknessCurse), 1);
        updateCurseUI();
      }

      if (pending.hit) {
        // Apply damage through enemy's block
        const damageResult = window.CombatEffects.processDamageWithBlock(combat.enemy, pending.damage);

        addCombatLogMessage(`⚔️ Attack hit! (${pending.totalRoll} vs AC ${combat.enemy.armorClass})`, 'success');

        if (damageResult.blockConsumed > 0) {
          addCombatLogMessage(`💥 Dealt ${damageResult.healthLost} damage (${damageResult.blockConsumed} blocked)!`, 'success');
        } else {
          addCombatLogMessage(`💥 Dealt ${damageResult.healthLost} damage to ${combat.enemy.name}!`, 'success');
        }

        // Update UI to show enemy damage
        updateCombatUI();

        // Check if enemy is defeated
        if (combat.enemy.health <= 0) {
          setTimeout(() => {
            handleVictory();
          }, 500);
        }
      } else {
        addCombatLogMessage(`❌ Attack missed! (${pending.totalRoll} vs AC ${combat.enemy.armorClass})`, 'info');
      }

    } else {
      // Execute defense effects
      combat.player.effects.block = pending.newBlockTotal;
      addCombatLogMessage(`🛡️ Gained ${pending.blockGained} block! (Total: ${pending.newBlockTotal})`, 'info');
      updateCombatUI();
    }

    // Clear the pending roll
    pendingRolls[diceType] = null;

    // Disable both confirm and reroll buttons after confirming
    updateButtonStates(diceType, false, true);

    // Enable end turn button after confirming
    const endTurnBtn = document.getElementById('end-turn-btn');
    endTurnBtn.disabled = false;
    endTurnBtn.style.opacity = '1';
    endTurnBtn.style.cursor = 'pointer';
    endTurnBtn.style.background = 'linear-gradient(145deg, #4CAF50, #2E7D32)';
    endTurnBtn.style.color = 'white';
    endTurnBtn.style.borderColor = '#2E7D32';
  }

  // Handle rerolling a dice (costs reroll stat)
  function handleReroll(diceType) {
    if (!pendingRolls[diceType]) {
      return; // No pending roll
    }

    if (gameState.reroll <= 0) {
      addCombatLogMessage('No rerolls remaining!', 'warning');
      return;
    }

    // Consume one reroll
    gameState.reroll--;

    // Clear the pending roll
    pendingRolls[diceType] = null;

    // Disable buttons temporarily
    updateButtonStates(diceType, false, false);

    // Update reroll button text
    updateRerollButtonText();

    addCombatLogMessage(`🔄 Rerolling ${diceType} dice... (${gameState.reroll} rerolls left)`, 'info');

    // Trigger a new roll (this will refund the energy since we're rerolling)
    // First, refund the energy that was spent
    combat.player.energy = Math.min(combat.player.energy + 1, combat.player.maxEnergy);
    updateEnergyDisplay();

    // Now roll again (this will spend energy again)
    setTimeout(() => {
      handleDiceClick(diceType);
    }, 100);
  }

  // Setup end turn button
  document.getElementById('end-turn-btn').addEventListener('click', handleEndTurn);

  function handleEndTurn() {
    try {
      // Check if combat is still active
      const combat = window.CombatState.getCombatState();
      if (!combat) {
        console.warn('No active combat');
        return;
      }

      // Check if it's player's turn
      if (combat.phase !== 'player_turn') {
        console.warn('Not in player turn phase:', combat.phase);
        return;
      }

      const turnResult = window.CombatState.endPlayerTurn();

      // Update UI
      updateCombatUI();

      // Check combat result
      if (turnResult.phase === 'victory') {
        handleVictory();
      } else if (turnResult.phase === 'defeat') {
        handleDefeat();
      } else {
        // Continue to next turn
        startNextTurn();
      }

    } catch (error) {
      console.error('Error ending turn:', error);
      addCombatLogMessage(error.message, 'danger');
    }
  }

  function startNextTurn() {
    // Reset for next turn
    const currentCombat = window.CombatState.getCombatState();

    // Clear roll results
    document.getElementById('attack-roll-result').innerHTML = '';
    document.getElementById('defense-roll-result').innerHTML = '';

    // Clear pending rolls
    pendingRolls.attack = null;
    pendingRolls.defense = null;

    // Reset confirm and reroll buttons
    updateButtonStates('attack', false, false);
    updateButtonStates('defense', false, false);

    const endTurnBtn = document.getElementById('end-turn-btn');
    endTurnBtn.disabled = true;
    endTurnBtn.style.opacity = '0.5';
    endTurnBtn.style.cursor = 'not-allowed';
    endTurnBtn.style.background = 'linear-gradient(145deg, #555, #444)';
    endTurnBtn.style.color = '#888';
    endTurnBtn.style.borderColor = '#666';

    // Reset energy to max
    currentCombat.player.energy = currentCombat.player.maxEnergy;

    // Reset block to 0 at start of turn
    currentCombat.player.effects.block = 0;

    // Update energy display
    updateEnergyDisplay();
    updateCombatUI();

    // Re-create dice for next roll
    attackRenderer.createDice(currentCombat.dice.attack);
    defenseRenderer.createDice(currentCombat.dice.defense);
    enemyIntentRenderer.createDice(currentCombat.dice.enemy);

    // Show new enemy intent
    showEnemyIntent();
  }

  function updateCombatUI() {
    // Update player HP bar and text
    const playerHpPercent = (combat.player.health / combat.player.maxHealth) * 100;
    const playerHpBar = document.getElementById('player-hp-bar');
    if (playerHpBar) {
      playerHpBar.style.width = `${playerHpPercent}%`;
    }
    document.getElementById('player-hp').textContent = `${combat.player.health}/${combat.player.maxHealth}`;

    // Update player block display
    const playerBlockDisplay = document.getElementById('player-block-display');
    const playerBlockValue = document.getElementById('player-block-value');
    if (playerBlockDisplay && playerBlockValue) {
      const playerBlock = combat.player.effects.block || 0;
      if (playerBlock > 0) {
        playerBlockDisplay.style.display = 'flex';
        playerBlockValue.textContent = playerBlock;
      } else {
        playerBlockDisplay.style.display = 'none';
      }
    }

    // Update enemy HP bar and text
    const enemyHpPercent = (combat.enemy.health / combat.enemy.maxHealth) * 100;
    document.getElementById('enemy-hp-bar').style.width = `${enemyHpPercent}%`;
    document.getElementById('enemy-hp-text').textContent = `${Math.max(0, combat.enemy.health)}/${combat.enemy.maxHealth}`;

    // Update enemy block display
    const enemyBlockDisplay = document.getElementById('enemy-block-display');
    const enemyBlockValue = document.getElementById('enemy-block-value');
    if (enemyBlockDisplay && enemyBlockValue) {
      const enemyBlock = combat.enemy.effects.block || 0;
      if (enemyBlock > 0) {
        enemyBlockDisplay.style.display = 'flex';
        enemyBlockValue.textContent = enemyBlock;
      } else {
        enemyBlockDisplay.style.display = 'none';
      }
    }

    // Update effects displays
    updateEffectsDisplay('player-effects', combat.player.effects);
    updateEffectsDisplay('enemy-effects', combat.enemy.effects);

    // Update combat log
    updateCombatLog();

    // Update global health and sync with main UI
    health = combat.player.health;
    updateTopBar();

    // Update inventory to reflect any changes
    updateCombatInventory();

    // Update items bar
    populateItemsBar();
  }

  function updateEffectsDisplay(elementId, effects) {
    const container = document.getElementById(elementId);
    const descriptions = window.CombatEffects.getEffectDescriptions(effects);

    if (descriptions.length === 0) {
      container.innerHTML = '';
    } else {
      container.innerHTML = descriptions.map(desc =>
        `<p style="margin: 2px 0; color: #aaa;">${desc}</p>`
      ).join('');
    }
  }

  function updateCombatLog() {
    const logContainer = document.getElementById('combat-log-messages');
    if (!logContainer) return;

    const messages = combat.log; // Show all messages

    logContainer.innerHTML = messages.map(msg => {
      const color = msg.type === 'success' ? '#4CAF50' :
                    msg.type === 'danger' ? '#ff4444' :
                    msg.type === 'warning' ? '#ff9800' : '#aaa';

      return `<p style="margin: 5px 0; color: ${color}; line-height: 1.4;">${msg.message}</p>`;
    }).join('');

    // Scroll to bottom
    logContainer.scrollTop = logContainer.scrollHeight;
  }

  function addCombatLogMessage(message, type = 'info') {
    window.CombatState.addCombatLog(message, type);
    updateCombatLog();
  }

  function populateItemsBar() {
    const itemsContainer = document.getElementById('items-icons');

    if (!itemsContainer) {
      console.warn('Items container not found');
      return;
    }

    if (inventory.length === 0) {
      itemsContainer.innerHTML = '<span style="color: #666; font-size: 13px;">No items</span>';
      return;
    }

    itemsContainer.innerHTML = inventory.map((item, idx) => {
      let imageUrl = item.image && item.image.trim() !== ''
        ? item.image
        : 'https://via.placeholder.com/50?text=%3F';

      // Fix imgur URLs
      if (imageUrl.includes('imgur.com/') && !imageUrl.includes('i.imgur.com')) {
        imageUrl = imageUrl.replace('imgur.com/', 'i.imgur.com/');
        if (!imageUrl.match(/\.(png|jpg|jpeg|gif)$/i)) {
          imageUrl += '.png';
        }
      }

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

      return `
        <div class="item-icon" data-item-index="${idx}" style="
          width: 50px;
          height: 50px;
          position: relative;
          border: 2px solid ${rarityColor};
          border-radius: 6px;
          background: rgba(0,0,0,0.5);
          cursor: pointer;
          transition: all 0.2s ease;
          ${!canUse && isUsable ? 'opacity: 0.5;' : ''}
        " onmouseenter="showCombatItemTooltip(event, ${idx})" onmouseleave="hideCombatItemTooltip()">
          <img src="${imageUrl}" style="
            width: 100%;
            height: 100%;
            object-fit: contain;
            border-radius: 4px;
          " alt="${item.name}" onerror="if(this.src!=='https://via.placeholder.com/50?text=%3F'){this.src='https://via.placeholder.com/50?text=%3F';}">
          ${item.quantity && item.quantity > 1 ? `
            <div style="
              position: absolute;
              bottom: 2px;
              right: 2px;
              background: rgba(0,0,0,0.9);
              color: white;
              padding: 1px 3px;
              border-radius: 3px;
              font-size: 9px;
              font-weight: bold;
              border: 1px solid #ffaa00;
            ">x${item.quantity}</div>
          ` : ''}
          ${(function() {
            if ((item.type || '').toLowerCase() !== 'incremental') return '';
            const cs = window.CombatEngine ? window.CombatEngine.getCombatState() : null;
            const inc = cs && cs.incrementals;
            let cur = 0, max = null;
            switch (item.name) {
              case 'Pen Nib':        cur = inc ? inc.attacksTotal % 10 : 0;      max = 10; break;
              case 'Nunchaku':       cur = inc ? inc.attacksTotal % 10 : 0;      max = 10; break;
              case 'Happy Flower':   cur = cs  ? (cs.turn - 1) % 3 : 0;         max = 3;  break;
              case 'Ornamental Fan': cur = inc ? inc.attacksThisTurn % 4 : 0;   max = 4;  break;
              case 'Shuriken':       cur = inc ? inc.attacksThisTurn % 3 : 0;   max = 3;  break;
            }
            if (max === null) return '';
            return '<div style="position:absolute;top:1px;left:1px;background:rgba(0,0,0,0.85);color:#ffcc44;padding:1px 3px;border-radius:3px;font-size:9px;font-weight:bold;border:1px solid #ffcc44;line-height:1.2;">' + cur + '/' + max + '</div>';
          })()}
        </div>
      `;
    }).join('');
  }

  function setupStatsPanel() {
    const statsPanel = document.getElementById('stats-panel');
    const viewStatsBtn = document.getElementById('view-stats-btn');
    const closeStatsBtn = document.getElementById('close-stats-btn');

    // Populate stats
    const statsContent = document.getElementById('all-stats-content');
    statsContent.innerHTML = `
      <div style="background: rgba(0,0,0,0.4); border: 2px solid #4CAF50; border-radius: 8px; padding: 15px;">
        <h4 style="margin: 0 0 12px 0; color: #4CAF50; font-size: 16px; border-bottom: 1px solid rgba(76,175,80,0.3); padding-bottom: 8px;">⚔️ Combat Stats</h4>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
          <div style="text-align: center; background: rgba(255,102,102,0.1); border: 1px solid #ff6666; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 11px; text-transform: uppercase;">Attack</p>
            <p style="margin: 4px 0 0 0; color: #ff6666; font-weight: bold; font-size: 20px;">${attack}</p>
          </div>
          <div style="text-align: center; background: rgba(76,175,80,0.1); border: 1px solid #4CAF50; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 11px; text-transform: uppercase;">Health</p>
            <p style="margin: 4px 0 0 0; color: #4CAF50; font-weight: bold; font-size: 20px;">${health}/${maxHealth}</p>
          </div>
        </div>
      </div>

      <div style="background: rgba(0,0,0,0.4); border: 2px solid #888; border-radius: 8px; padding: 15px;">
        <h4 style="margin: 0 0 12px 0; color: #aaa; font-size: 16px; border-bottom: 1px solid rgba(136,136,136,0.3); padding-bottom: 8px;">📊 Base Stats</h4>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px;">
          <div style="background: rgba(255,68,68,0.1); border: 1px solid #ff4444; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Strength</p>
            <p style="margin: 3px 0 0 0; color: #ff6666; font-weight: bold; font-size: 18px;">${strength}</p>
          </div>
          <div style="background: rgba(76,175,80,0.1); border: 1px solid #4CAF50; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Dexterity</p>
            <p style="margin: 3px 0 0 0; color: #4CAF50; font-weight: bold; font-size: 18px;">${dexterity}</p>
          </div>
          <div style="background: rgba(102,153,255,0.1); border: 1px solid #6699ff; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Intelligence</p>
            <p style="margin: 3px 0 0 0; color: #6699ff; font-weight: bold; font-size: 18px;">${intelligence}</p>
          </div>
          <div style="background: rgba(255,102,255,0.1); border: 1px solid #ff66ff; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Charisma</p>
            <p style="margin: 3px 0 0 0; color: #ff66ff; font-weight: bold; font-size: 18px;">${charisma}</p>
          </div>
          <div style="background: rgba(255,204,102,0.1); border: 1px solid #ffcc66; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Luck</p>
            <p style="margin: 3px 0 0 0; color: #ffcc66; font-weight: bold; font-size: 18px;">${luck}</p>
          </div>
          <div style="background: rgba(255,255,255,0.05); border: 1px solid #888; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Reroll</p>
            <p style="margin: 3px 0 0 0; color: #aaa; font-weight: bold; font-size: 18px;">${reroll}</p>
          </div>
        </div>
      </div>
    `;

    // Toggle panel
    viewStatsBtn.addEventListener('click', () => {
      statsPanel.style.transform = 'translateX(0)';
    });

    closeStatsBtn.addEventListener('click', () => {
      statsPanel.style.transform = 'translateX(-100%)';
    });
  }

  function setupLogPanel() {
    const logPanel = document.getElementById('log-panel');
    const viewLogBtn = document.getElementById('view-log-btn');
    const closeLogBtn = document.getElementById('close-log-btn');

    // Toggle panel
    viewLogBtn.addEventListener('click', () => {
      logPanel.style.transform = 'translateX(0)';
    });

    closeLogBtn.addEventListener('click', () => {
      logPanel.style.transform = 'translateX(100%)';
    });
  }

  function setupItemTooltips() {
    // Tooltip functions are defined globally below
  }

  function updateCombatInventory() {
    // Now uses the items bar instead of separate inventory section
    populateItemsBar();
    return;

    // Old code below is no longer used
    const container = document.getElementById('combat-inventory-items');

    if (!container) return; // Element no longer exists in new layout

    if (inventory.length === 0) {
      container.innerHTML = '<div style="text-align: center; padding: 40px 20px; color: #666; font-size: 14px;">No items</div>';
      return;
    }

    // Use the same rendering logic as main gameplay
    container.innerHTML = inventory.map((item, idx) => {
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

      // Get rarity color
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
      const isWeapon = item.type === 'Weapon';

      return `
        <div class="combat-item-container" style="
          display: flex;
          gap: 10px;
          background: rgba(0,0,0,0.3);
          border: 2px solid ${rarityColor};
          border-radius: 8px;
          padding: 8px;
          transition: all 0.2s ease;
          cursor: ${canUse ? 'pointer' : 'default'};
          opacity: ${canUse || !isUsable ? '1' : '0.6'};
        " ${canUse ? `onclick="useCombatItem(${idx})"` : ''}>
          <div style="flex-shrink: 0; position: relative;">
            <img src="${imageUrl}"
                 alt="${item.name}"
                 loading="lazy"
                 style="width: 60px; height: 60px; object-fit: contain; border-radius: 6px; background: #1a1a1a; padding: 2px; display: block;"
                 onerror="if(this.src!=='https://via.placeholder.com/70?text=%3F'){this.src='https://via.placeholder.com/70?text=%3F';}">
            ${item.quantity && item.quantity > 1 ? `
              <div style="
                position: absolute;
                top: 2px;
                right: 2px;
                background: rgba(0, 0, 0, 0.9);
                color: white;
                padding: 1px 4px;
                border-radius: 3px;
                font-size: 10px;
                font-weight: bold;
                border: 1px solid #ffaa00;
              ">x${item.quantity}</div>
            ` : ''}
            ${isWeapon && item.level && item.level > 1 ? `
              <div style="
                position: absolute;
                top: 2px;
                right: 2px;
                background: #ffaa44;
                color: #000;
                padding: 2px 4px;
                border-radius: 3px;
                font-size: 10px;
                font-weight: bold;
              ">Lv${item.level}</div>
            ` : ''}
          </div>
          <div style="flex: 1; min-width: 0;">
            <p style="margin: 0 0 4px 0; font-size: 13px; font-weight: bold; color: ${rarityColor}; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${item.name}</p>
            <p style="margin: 0 0 4px 0; font-size: 10px; color: #aaa; font-style: italic;">${item.type} • ${item.rarity}</p>
            <p style="margin: 0; font-size: 11px; color: #ccc; line-height: 1.3;">${item.description || item.effect || ''}</p>
            ${isUsable ? `
              <div style="margin-top: 6px;">
                <span style="
                  display: inline-block;
                  padding: 3px 8px;
                  font-size: 10px;
                  background: ${canUse ? '#4CAF50' : '#555'};
                  color: ${canUse ? 'white' : '#888'};
                  border-radius: 4px;
                  font-weight: bold;
                  text-transform: uppercase;
                ">
                  ${canUse ? '✓ Usable' : '✗ Cannot Use'}${item.uses && item.uses > 1 ? ` (${item.uses}x)` : ''}
                </span>
              </div>
            ` : ''}
          </div>
        </div>
      `;
    }).join('');

    // Also update the main gameplay inventory to keep them synced
    if (typeof updateInventory === 'function') {
      updateInventory();
    }
  }

  function handleVictory() {
    // Disable all combat buttons
    const endTurnBtn = document.getElementById('end-turn-btn');
    if (endTurnBtn) endTurnBtn.disabled = true;

    // Dispose all three dice renderers
    attackRenderer.dispose();
    defenseRenderer.dispose();
    enemyIntentRenderer.dispose();

    // Award rewards
    const goldMatch = enemy.successReward.match(/(\d+) Gold/);
    if (goldMatch) {
      const goldAmount = parseInt(goldMatch[1]);
      gold += goldAmount;
      gameState.gold = gold;
      updateTopBar();
    }

    // Trigger onEnemyDefeated effects
    if (typeof triggerOnEnemyDefeated === 'function') {
      triggerOnEnemyDefeated();
    }

    // Record encounter
    encounterHistory.push({
      type: 'combat',
      enemy: enemy.name,
      outcome: 'Victory',
      timestamp: new Date().toLocaleString()
    });
    updateEncounterHistory();
    saveCurrentGame();

    // Show victory screen
    setTimeout(() => {
      const _cardVictoryDifficulty = enemy.difficulty || 'Low';
      createGameModal(`
        <div style="text-align: center;">
          <h2 style="color: #4CAF50; font-size: 36px; margin: 20px 0;">⚔️ VICTORY!</h2>
          <h3>${enemy.name} defeated!</h3>
          <p style="color: #4CAF50; font-size: 18px; margin: 20px 0;">${enemy.successReward}</p>
          <button id="card-victory-continue-btn" style="
            padding: 15px 30px;
            background: #4CAF50;
            border: none;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-weight: bold;
            font-size: 16px;
          ">Continue</button>
        </div>
      `);
      const _btn = document.getElementById('card-victory-continue-btn');
      if (_btn) {
        _btn.addEventListener('click', () => {
          closeGameModal();
          showPostCombatChoiceModal(_cardVictoryDifficulty);
        }, { once: true });
      }
    }, 500);

    window.CombatState.endCombat(true);
  }

  function handleDefeat() {
    // Dispose all three dice renderers
    attackRenderer.dispose();
    defenseRenderer.dispose();
    enemyIntentRenderer.dispose();

    // Clear items and curses on death
    inventory = [];
    if (gameState.activeCurses) {
      gameState.activeCurses = [];
    }

    // Record encounter
    encounterHistory.push({
      type: 'combat',
      enemy: enemy.name,
      outcome: 'Defeat',
      timestamp: new Date().toLocaleString()
    });
    updateEncounterHistory();

    window.CombatState.endCombat(false);

    // Show death screen
    setTimeout(() => {
      createGameModal(`
        <div style="text-align: center;">
          <h1 style="color: #ff4444; font-size: 48px; margin: 20px 0;">💀 YOU ARE DEAD</h1>
          <p style="color: #aaa; font-size: 18px; margin: 20px 0;">Your journey has come to an end...</p>
          <div style="margin-top: 30px; display: flex; gap: 15px; justify-content: center;">
            <button id="death-home-btn" style="
              padding: 12px 24px;
              background: #444;
              border: 2px solid #666;
              border-radius: 8px;
              color: white;
              cursor: pointer;
              font-weight: bold;
              font-size: 16px;
            ">🏠 Home</button>
            <button id="death-retry-btn" style="
              padding: 12px 24px;
              background: #d32f2f;
              border: 2px solid #f44336;
              border-radius: 8px;
              color: white;
              cursor: pointer;
              font-weight: bold;
              font-size: 16px;
            ">🔄 Try Again</button>
          </div>
        </div>
      `);

      document.getElementById('death-home-btn').onclick = () => {
        closeGameModal();
        updateInventory?.();
        updateCursesDisplay?.();
        updateActiveCursesList?.();
        updateGameStats?.();
        if (typeof clearAllArrows === 'function') {
          clearAllArrows();
        }
        document.getElementById('dungeon-screen').style.display = 'none';
        document.getElementById('main-menu').style.display = 'flex';
        const topBarRight = document.getElementById('top-bar-right');
        if (topBarRight) topBarRight.style.display = 'none';
      };

      document.getElementById('death-retry-btn').onclick = () => {
        inventory = [];
        if (gameState.activeCurses) {
          gameState.activeCurses = [];
        }
        updateInventory?.();
        updateCursesDisplay?.();
        updateActiveCursesList?.();

        closeGameModal();
        if (typeof clearAllArrows === 'function') {
          clearAllArrows();
        }
        document.getElementById('dungeon-screen').style.display = 'none';
        document.getElementById('main-menu').style.display = 'flex';
        const topBarRight = document.getElementById('top-bar-right');
        if (topBarRight) topBarRight.style.display = 'none';

        setTimeout(() => {
          document.getElementById('new-game-btn')?.click();
        }, 100);
      };
    }, 300);
  }

  // Helper function to get player image
  function getPlayerImagePath() {
    if (gameState && gameState.character && PLAYER_CHARACTERS[gameState.character]) {
      const character = PLAYER_CHARACTERS[gameState.character];
      return character.fullImage || character.icon;
    }
    return 'images/characters/full/default.png';
  }

  // Initial UI update
  updateCombatUI();
}

// Make showCombatModal available globally
window.showCombatModal = showCombatModal;

/**
 * New Dice-Based Combat Modal
 * Uses CombatEngine and CombatUI for the new combat system
 */
/**
 * Build a combat encounter using the weight system.
 * Total weight budgets:
 *   First combat ever: 2
 *   Low (rest): 4
 *   Medium (first of tier): 5  |  Medium (rest): 7
 *   High (first of tier): 8    |  High (rest): 10
 * Max 4 enemies per encounter.
 * Enemy selection: pick a target weight 1..remaining equally, then pick a random
 * enemy with that weight from the eligible pool. Repeat until budget exhausted.
 */
function buildWeightedEncounter() {
  const gamesBeaten = gameState.totalGamesBeaten || 0;
  const combatsCompleted = gameState.totalCombatsCompleted || 0;

  // Determine current difficulty tier
  const _enc_thresholds = (typeof DIFFICULTY_THRESHOLDS !== 'undefined') ? DIFFICULTY_THRESHOLDS : { MEDIUM: 4, HARD: 8, INSANE: 12 };
  let currentTier;
  if (gamesBeaten >= _enc_thresholds.HARD) currentTier = 'High';
  else if (gamesBeaten >= _enc_thresholds.MEDIUM) currentTier = 'Medium';
  else currentTier = 'Low';

  // Detect first combat of a new tier
  const isFirstCombatEver = combatsCompleted === 0;
  const tierChanged = gameState.lastDifficultyTier !== currentTier;
  const isFirstOfTier = isFirstCombatEver || tierChanged;

  // Budget based on tier + first/rest
  let budget;
  if (isFirstCombatEver) {
    budget = 2;
  } else if (currentTier === 'Low') {
    budget = 4;
  } else if (currentTier === 'Medium') {
    budget = isFirstOfTier ? 5 : 7;
  } else { // High
    budget = isFirstOfTier ? 8 : 10;
  }

  // Update tier tracking (will persist after combat)
  gameState.lastDifficultyTier = currentTier;

  // Build eligible pool: difficulty tier + game-type filter
  const tierOrder = ['Low', 'Medium', 'High'];
  const maxTierIdx = tierOrder.indexOf(currentTier);

  // Determine which enemy type matches the current game's category
  const GAME_TYPE_TO_ENEMY_TYPE = {
    'Action': 'Strength',
    'Deckbuilding': 'Charisma',
    'Strategy': 'Intelligence',
    'Traditional': 'Dexterity',
  };
  const currentGameObj = typeof games !== 'undefined'
    ? games.find(g => g.name === gameState.currentGame)
    : null;
  const currentGameType = currentGameObj?.type || null;
  const requiredEnemyType = currentGameType ? (GAME_TYPE_TO_ENEMY_TYPE[currentGameType] || null) : null;

  // Base pool: tier-eligible enemies that match the game's enemy type
  // (falls back to all tier-eligible if no game type can be determined)
  let basePool = ENEMIES_DATA.filter(e =>
    e.weight !== null && e.difficulty !== null &&
    tierOrder.indexOf(e.difficulty) <= maxTierIdx &&
    (!requiredEnemyType || e.type === requiredEnemyType)
  );
  if (basePool.length === 0) {
    // Fallback: drop the type filter
    basePool = ENEMIES_DATA.filter(e =>
      e.weight !== null && e.difficulty !== null &&
      tierOrder.indexOf(e.difficulty) <= maxTierIdx
    );
  }

  // Specific Enemies setting: additionally restrict to enemies from the current game
  let eligiblePool = basePool;
  if (gameSettings.specificEnemies && gameState.currentGame) {
    const specificPool = basePool.filter(e => e.game === gameState.currentGame);
    // Only apply the game filter if it leaves at least one enemy
    if (specificPool.length > 0) eligiblePool = specificPool;
  }

  if (eligiblePool.length === 0) {
    console.error('No eligible enemies found for encounter');
    return null;
  }

  // Select enemies fairly
  const selectedEnemies = [];
  let remainingBudget = budget;
  const maxEnemies = 4;

  while (remainingBudget > 0 && selectedEnemies.length < maxEnemies) {
    // Find candidates that fit within remaining budget
    const fittingCandidates = eligiblePool.filter(e => e.weight <= remainingBudget);
    if (fittingCandidates.length === 0) break;

    // Determine available weight values (1 to max fitting weight), pick one equally
    const maxWeight = Math.max(...fittingCandidates.map(e => e.weight));
    const targetWeight = Math.floor(Math.random() * maxWeight) + 1;

    // Find enemies with exactly that weight; if none, find closest lower weight
    // Use ceiling so fractional-weight enemies (e.g. Fly at 0.5) map into the nearest integer bucket
    let weightCandidates = fittingCandidates.filter(e => Math.ceil(e.weight) === targetWeight);
    if (weightCandidates.length === 0) {
      // Pick any fitting enemy (fallback)
      weightCandidates = fittingCandidates;
    }

    const chosen = weightCandidates[Math.floor(Math.random() * weightCandidates.length)];
    selectedEnemies.push(chosen);
    remainingBudget -= chosen.weight;
  }

  return selectedEnemies;
}

function showDiceCombatModal() {
  if (!ENEMIES_DATA || ENEMIES_DATA.length === 0) {
    console.error('ENEMIES_DATA not loaded');
    return;
  }

  // Set phase to combat
  gameState.phase = 'combat';
  updateInventory();

  // Use pre-assigned enemies from the node modal if available, otherwise generate fresh
  const _preAssignedEnemies = gameState.choiceDetails?.[gameState.currentGame]?.enemies;
  const encounterEnemies = (_preAssignedEnemies && _preAssignedEnemies.length > 0)
    ? _preAssignedEnemies
    : buildWeightedEncounter();
  // Consume the pre-assigned slot so a retry generates fresh enemies
  if (_preAssignedEnemies && gameState.choiceDetails?.[gameState.currentGame]) {
    delete gameState.choiceDetails[gameState.currentGame].enemies;
  }
  if (!encounterEnemies || encounterEnemies.length === 0) {
    console.error('No matching enemies found');
    return;
  }

  // Append any event-spawned enemies (on top of the weight budget)
  if (Array.isArray(gameState.pendingSpawnEnemies) && gameState.pendingSpawnEnemies.length > 0) {
    for (const spawn of gameState.pendingSpawnEnemies) {
      const tmpl = ENEMIES_DATA.find(e => e.name.toLowerCase() === (spawn.enemy || '').toLowerCase());
      if (tmpl) {
        const count = spawn.min + Math.floor(Math.random() * (spawn.max - spawn.min + 1));
        for (let s = 0; s < count; s++) encounterEnemies.push(tmpl);
      }
    }
    gameState.pendingSpawnEnemies = [];
  }

  // Use the first enemy as the primary (multi-enemy support via array passed to initCombat)
  const enemyData = encounterEnemies[0];

  // Get character data
  const characterKey = selectedCharacter || gameState.character || 'Rodney';
  const characterData = PLAYER_CHARACTERS[characterKey];

  if (!characterData) {
    console.error('Character data not found for:', characterKey);
    // Fall back to old combat system
    showCombatModal();
    return;
  }

  // Merge player stats into character data
  characterData.stats = {
    strength: strength || 0,
    dexterity: dexterity || 0,
    intelligence: intelligence || 0,
    charisma: charisma || 0
  };
  characterData.health = health;
  characterData.maxHealth = maxHealth;
  characterData.reroll = gameState.reroll || reroll || 0;
  characterData.dash = gameState.dash || 0;

  // Get weapon data if equipped
  let weaponData = null;
  if (gameState.equippedWeapon && WEAPONS_DATA) {
    weaponData = WEAPONS_DATA.find(w => w.name === gameState.equippedWeapon.name);
  }

  // Get active allies from gameState
  const allies = (gameState.activeAllies || []).map(allyData => {
    // Each ally in gameState stores current HP, we need to merge with base data
    const baseAlly = ALLIES_DATA.find(a => a.name === allyData.name);
    if (!baseAlly) return null;
    return {
      ...baseAlly,
      currentHp: allyData.currentHp !== undefined ? allyData.currentHp : baseAlly.hp
    };
  }).filter(Boolean);

  // Clean up any lingering hover tooltips before combat starts
  if (typeof hideAllTooltips === 'function') hideAllTooltips();

  // Initialize combat with all encounter enemies
  const combatState = window.CombatEngine.initCombat(encounterEnemies, characterData, weaponData, allies);

  if (!combatState) {
    console.error('Failed to initialize combat');
    return;
  }

  // Apply statuses queued by pre-combat events (e.g. frail from event outcomes)
  if (Array.isArray(gameState.pendingCombatStatuses) && gameState.pendingCombatStatuses.length > 0) {
    for (const pending of gameState.pendingCombatStatuses) {
      if (combatState.player && combatState.player.statuses) {
        const key = pending.status.toLowerCase();
        combatState.player.statuses[key] = (combatState.player.statuses[key] || 0) + (pending.stacks || 1);
      }
    }
    gameState.pendingCombatStatuses = [];
  }

  // Full-screen combat — fill entire viewport, no modal chrome
  const existingModal = document.getElementById('game-modal');
  if (existingModal) existingModal.remove();
  const modal = document.createElement('div');
  modal.id = 'game-modal';
  const _topBar = document.getElementById('top-bar');
  const _topBarH = _topBar ? _topBar.offsetHeight : 0;
  modal.style.cssText = `position:fixed;top:${_topBarH}px;left:0;right:0;bottom:0;z-index:500;overflow:hidden;`;
  modal.innerHTML = `
    <div id="dice-combat-modal" style="width:100%;height:100%;display:flex;flex-direction:column;overflow:hidden;">
      <div id="dice-combat-content" style="flex:1;overflow:hidden;display:flex;flex-direction:column;min-height:0;"></div>
    </div>
  `;
  document.body.appendChild(modal);

  // Create tooltip element for item hover (reuse existing or create new)
  const existingTooltip = document.getElementById('combat-item-tooltip');
  if (!existingTooltip) {
    const tooltip = document.createElement('div');
    tooltip.id = 'combat-item-tooltip';
    tooltip.style.cssText = `
      position: fixed;
      display: none;
      background: linear-gradient(145deg, rgba(30,30,40,0.98), rgba(20,20,30,0.98));
      border: 3px solid #888;
      border-radius: 8px;
      padding: 12px 15px;
      max-width: 300px;
      z-index: 9000;
      pointer-events: auto;
      box-shadow: 0 4px 20px rgba(0,0,0,0.8);
    `;
    const tooltipContent = document.createElement('div');
    tooltipContent.id = 'combat-tooltip-content';
    tooltip.appendChild(tooltipContent);
    document.body.appendChild(tooltip);
  }

  // Render the combat UI
  const container = document.getElementById('dice-combat-content');
  if (container && window.CombatUI) {
    window.CombatUI.renderCombatUI(combatState, container);
  }

  // Override the checkCombatEnd to handle victory/defeat properly
  const originalCheckEnd = window.CombatUI.checkCombatEnd;
  window.CombatUI.checkCombatEnd = function() {
    const combat = window.CombatEngine.getCombatState();
    if (!combat) return;

    if (combat.phase === 'victory') {
      setTimeout(() => {
        handleDiceCombatVictory(enemyData);
      }, 500);
    } else if (combat.phase === 'defeat') {
      setTimeout(() => {
        handleDiceCombatDefeat(enemyData);
      }, 500);
    }
  };
}

/**
 * Handle victory in dice combat
 */
function handleDiceCombatVictory(enemy) {
  // Sync ally HP from combat state before ending
  const combatState = window.CombatEngine.getCombatState();
  if (combatState && combatState.allies) {
    combatState.allies.forEach(ally => {
      if (ally.isAlive) {
        updateAllyHp(ally.name, ally.health);
      } else {
        // Ally died in combat
        dismissAlly(ally.name);
      }
    });
  }

  // Cleanup 3D dice renderers
  if (window.CombatUI && window.CombatUI.cleanup3DDice) {
    window.CombatUI.cleanup3DDice();
  }

  // Hide all floating combat tooltips
  ['enemy-pattern-tooltip', 'combat-status-tooltip', 'combat-card-tooltip'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.style.display = 'none';
  });

  window.CombatEngine.endCombat(true);
  gameState.phase = 'selection'; // allow scrolls/items outside combat
  gameState.totalCombatsCompleted = (gameState.totalCombatsCompleted || 0) + 1;

  // Award gold based on difficulty tier
  const goldAmounts = { 'Low': 20, 'Medium': 35, 'High': 55 };
  const goldReward = goldAmounts[enemy.difficulty] || 10;
  gold += goldReward;
  gameState.gold = gold;
  updateTopBar();

  // Trigger onEnemyDefeated effects
  if (typeof triggerOnEnemyDefeated === 'function') {
    triggerOnEnemyDefeated();
  }

  // Record enemy defeated for collection stats
  if (typeof recordEnemyDefeated === 'function') {
    recordEnemyDefeated(enemy.name);
  }

  // Record encounter
  encounterHistory.push({
    type: 'combat',
    enemy: enemy.name,
    outcome: 'Victory',
    timestamp: new Date().toLocaleString()
  });
  updateEncounterHistory();

  // Award one random potion or scroll (always runs; try/catch prevents silent failures)
  let lootIcon = '', lootDisplayName = '', lootDisplayRarity = '';
  try {
    const lootReward = window.selectRandomPotionOrScroll();
    window.addScrollOrPotionToLoot(lootReward);
    if (lootReward.type === 'scroll') {
      const _scrollPath = typeof getScrollImagePath === 'function' ? getScrollImagePath(lootReward) : 'images/scrolls/Unidentified.png';
      lootIcon = `<img src="${_scrollPath}" style="width:56px;height:56px;object-fit:contain;" onerror="this.style.display='none'">`;
      lootDisplayName = typeof getScrollDisplayName === 'function' ? getScrollDisplayName(lootReward.name) : 'Unidentified Scroll';
    } else {
      const _potionPath = typeof getPotionImagePath === 'function' ? getPotionImagePath(lootReward) : 'images/potions/Unidentified.png';
      lootIcon = `<img src="${_potionPath}" style="width:56px;height:56px;object-fit:contain;" onerror="this.style.display='none'">`;
      lootDisplayName = typeof getPotionDisplayName === 'function' ? getPotionDisplayName(lootReward.name) : 'Unidentified Potion';
    }
    lootDisplayRarity = lootReward.rarity || '';
    encounterHistory.push({
      type: 'loot',
      name: lootDisplayName,
      rarity: lootDisplayRarity,
      timestamp: new Date().toLocaleString()
    });
    if (typeof updateEncounterHistory === 'function') updateEncounterHistory();
  } catch (e) {
    console.error('Failed to award post-combat loot:', e);
  }

  saveCurrentGame();

  const difficulty = enemy.difficulty || 'Low';
  showVictoryScreen(enemy.name, goldReward, lootIcon, lootDisplayName, lootDisplayRarity, difficulty);
}

/**
 * Show post-combat choice modal (Rest / Smith / Shop / Movement Event).
 * Each option can only be used once per difficulty tier per run.
 * @param {string} difficulty - 'Low' | 'Medium' | 'High'
 */
function showPostCombatChoiceModal(difficulty) {
  const tier = difficulty || 'Low';

  // Use the 2 pre-assigned options from the node modal if available for this game
  const preAssigned = gameState.choiceDetails?.[gameState.currentGame]?.postCombatOptions || null;

  const optionData = [
    {
      key: 'rest',
      label: 'Rest',
      icon: '🛌',
      desc: 'Heal 33% of your max health.',
      color: '#4CAF50',
      action: () => {
        const heal = Math.floor(maxHealth * 0.33);
        health = Math.min(health + heal, maxHealth);
        window.health = health;
        gameState.health = health;
        if (typeof updateTopBar === 'function') updateTopBar();
        if (typeof saveCurrentGame === 'function') saveCurrentGame();
        closeGameModal();
        if (typeof createNotification === 'function') createNotification(`Rested: +${heal} Health`, '#4CAF50', '🛌');
        if (window._postcombatOnComplete) { const cb = window._postcombatOnComplete; window._postcombatOnComplete = null; cb(); }
      }
    },
    {
      key: 'smith',
      label: 'Smith',
      icon: '⚒️',
      desc: 'Choose 2 cards from your deck to upgrade for free.',
      color: '#FF9800',
      action: () => {
        closeGameModal();
        showSmithChoiceModal();
      }
    },
    {
      key: 'shop',
      label: 'Shop',
      icon: '🛒',
      desc: 'Visit the shop to buy items.',
      color: '#FFD700',
      action: () => {
        closeGameModal();
        // Reset shop state so fresh items appear
        gameState.currentShopItems = null;
        gameState.shopRerollCount = 0;
        gameState.shopUpgradesUsed = 0;
        gameState.shopRemovesUsed = 0;
        if (typeof showShopModal === 'function') showShopModal();
      }
    },
    {
      key: 'movement',
      label: 'Movement Event',
      icon: '🗺️',
      desc: 'A special event that helps you navigate difficult terrain. (Coming soon)',
      color: '#9b59b6',
      action: () => {
        closeGameModal();
        if (typeof createNotification === 'function') createNotification('Movement Event coming soon!', '#9b59b6', '🗺️');
        if (window._postcombatOnComplete) { const cb = window._postcombatOnComplete; window._postcombatOnComplete = null; cb(); }
      }
    }
  ];

  // Filter to only the 2 pre-assigned options if the node modal set them
  const _filtered = preAssigned ? optionData.filter(o => preAssigned.includes(o.key)) : optionData;
  const visibleOptions = _filtered.length >= 2 ? _filtered : optionData;

  const buttonsHTML = visibleOptions.map(opt => `
      <div style="
        background: #2d2d2d;
        border: 2px solid ${opt.color};
        border-radius: 12px;
        padding: 20px;
        cursor: pointer;
        transition: transform 0.15s, box-shadow 0.15s;
        text-align: center;
        min-width: 160px;
        max-width: 200px;
        onmouseenter="this.style.transform='translateY(-4px)'; this.style.boxShadow='0 6px 20px ${opt.color}66'"
      "
      onclick="window._postcombatUseOption('${opt.key}', '${tier}')"
      id="postcombat-opt-${opt.key}">
        <div style="font-size:36px;margin-bottom:10px;">${opt.icon}</div>
        <div style="font-weight:bold;color:white;font-size:15px;margin-bottom:8px;">${opt.label}</div>
        <div style="color:#aaa;font-size:12px;line-height:1.4;">${opt.desc}</div>
      </div>
    `).join('');

  // Register option handler globally (modal scope)
  window._postcombatUseOption = (key, t) => {
    if (typeof saveCurrentGame === 'function') saveCurrentGame();
    const opt = optionData.find(o => o.key === key);
    if (opt) opt.action();
  };

  createGameModal(`
    <div style="text-align:center; padding:24px; max-width:920px;">
      <h2 style="color:#FFD700; margin-top:0; margin-bottom:6px;">After Battle</h2>
      <p style="color:#aaa; font-size:13px; margin-bottom:20px;">Choose your reward.</p>
      <div style="display:flex; gap:16px; justify-content:center; flex-wrap:wrap; margin-bottom:20px;">
        ${buttonsHTML}
      </div>
      <button onclick="closeGameModal();if(window._postcombatOnComplete){var _cb=window._postcombatOnComplete;window._postcombatOnComplete=null;_cb();}" style="
        padding:10px 30px; background:#444; border:none; border-radius:8px;
        color:#aaa; cursor:pointer; font-size:13px;
      ">Skip</button>
    </div>
  `);
}

/**
 * Show the Smith upgrade modal — player picks up to 2 cards to upgrade for free.
 */
function showSmithChoiceModal() {
  // Include starter cards from character's starting deck that haven't been smith-upgraded yet
  const upgradedStarting = gameState.upgradedStartingCards || {};
  const charKey = gameState.character;
  const charData = (charKey && typeof PLAYER_CHARACTERS !== 'undefined') ? PLAYER_CHARACTERS[charKey] : null;
  const startingEntries = (charData && charData.startingDeck) ? charData.startingDeck : [];

  const startingUpgradeable = [];
  startingEntries.forEach(entry => {
    const template = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === entry.cardName) : null;
    if (template && template.canUpgrade) {
      const totalCount   = entry.count || 1;
      const upgradedCount = upgradedStarting[entry.cardName] || 0;
      const remaining    = totalCount - upgradedCount;
      for (let i = 0; i < remaining; i++) {
        startingUpgradeable.push({ ...template, _isStarting: true });
      }
    }
  });

  const collectedUpgradeable = (gameState.deck || []).filter(c => c.canUpgrade && !c.upgraded);
  const upgradeable = [...startingUpgradeable, ...collectedUpgradeable];

  if (upgradeable.length === 0) {
    if (typeof createNotification === 'function') createNotification('No upgradeable cards in deck!', '#FF9800', '⚒️');
    return;
  }

  const MAX_UPGRADES = 2;
  const selectedIndices = new Set();

  const rarityCol = r => {
    if (r === 'Rare') return 'var(--color-rare)';
    if (r === 'Uncommon') return 'var(--color-uncommon)';
    return 'var(--color-common)';
  };

  // Build each card HTML once — selection state toggled in-place via DOM
  const cardsHTML = upgradeable.map((card, idx) => {
    const rc = rarityCol(card.rarity);
    const upgDesc = card.upgradedDescription
      ? `<div class="smith-upgrade-block">
           <div class="smith-upgrade-label">▶ Upgraded</div>
           <div class="smith-upgrade-cost">${card.upgradedCost != null ? `Cost: ${card.upgradedCost}` : `Cost: ${card.cost}`}</div>
           <div class="smith-upgrade-desc">${card.upgradedDescription}</div>
         </div>`
      : `<div class="smith-upgrade-block" style="color:#555;font-size:10px;font-style:italic;">No upgrade available</div>`;

    return `
      <div class="smith-card-option" data-smith-idx="${idx}"
           style="border:2px solid #555;">
        <img src="${card.imageUrl || 'images/cards/default.png'}" alt="${card.name}"
             style="width:72px;height:72px;object-fit:contain;margin-bottom:6px;"
             onerror="this.style.display='none'">
        <div style="font-weight:bold;font-size:13px;color:white;text-align:center;margin-bottom:2px;">${card.name}</div>
        <div style="font-size:10px;color:${rc};margin-bottom:6px;">${card.rarity} · ${card.type}</div>

        <div class="smith-current-block">
          <div style="font-size:10px;color:#888;margin-bottom:2px;">Current — Cost: ${card.cost}</div>
          <div style="font-size:11px;color:#ccc;line-height:1.4;">${card.description}</div>
        </div>

        ${upgDesc}

        <div class="smith-selected-badge" style="display:none;">✓ Selected</div>
      </div>
    `;
  }).join('');

  createGameModal(`
    <div style="text-align:center; padding:20px; max-width:960px;">
      <h2 style="color:#FF9800; margin-top:0; margin-bottom:4px;">⚒️ Smith</h2>
      <p style="color:#aaa; font-size:13px; margin-bottom:16px;">
        Select up to ${MAX_UPGRADES} cards to upgrade for free.
        <span id="smith-counter" style="color:#FF9800; font-weight:bold;">0/${MAX_UPGRADES} selected</span>
      </p>
      <div style="display:flex; gap:12px; flex-wrap:wrap; justify-content:center; margin-bottom:20px;">
        ${cardsHTML}
      </div>
      <div style="display:flex; gap:10px; justify-content:center;">
        <button id="smith-confirm-btn" disabled style="
          padding:10px 28px; background:#555; border:none; border-radius:8px;
          color:#999; cursor:not-allowed; font-weight:bold; font-size:14px;
          transition: background 0.15s, color 0.15s;
        ">Upgrade (0)</button>
        <button onclick="closeGameModal()" style="
          padding:10px 24px; background:#333; border:1px solid #555; border-radius:8px;
          color:#aaa; cursor:pointer; font-size:14px;
        ">Cancel</button>
      </div>
    </div>
  `);

  // Update selection visuals without re-rendering the modal
  function updateSmithUI() {
    document.querySelectorAll('.smith-card-option').forEach(el => {
      const idx = parseInt(el.dataset.smithIdx);
      const sel = selectedIndices.has(idx);
      el.style.borderColor  = sel ? '#FF9800' : '#555';
      el.style.background   = sel ? '#2a1a00' : '#2d2d2d';
      el.querySelector('.smith-selected-badge').style.display = sel ? 'block' : 'none';
    });
    const count = selectedIndices.size;
    const counter = document.getElementById('smith-counter');
    if (counter) counter.textContent = `${count}/${MAX_UPGRADES} selected`;
    const btn = document.getElementById('smith-confirm-btn');
    if (btn) {
      btn.disabled      = count === 0;
      btn.textContent   = `Upgrade (${count})`;
      btn.style.background = count > 0 ? '#FF9800' : '#555';
      btn.style.color      = count > 0 ? 'white'   : '#999';
      btn.style.cursor     = count > 0 ? 'pointer' : 'not-allowed';
    }
  }

  document.querySelectorAll('.smith-card-option').forEach(el => {
    el.addEventListener('click', () => {
      const idx = parseInt(el.dataset.smithIdx);
      if (selectedIndices.has(idx)) {
        selectedIndices.delete(idx);
      } else if (selectedIndices.size < MAX_UPGRADES) {
        selectedIndices.add(idx);
      }
      updateSmithUI();
    });
  });

  document.getElementById('smith-confirm-btn').addEventListener('click', () => {
    let upgradeCount = 0;
    selectedIndices.forEach(idx => {
      const card = upgradeable[idx];
      if (card._isStarting) {
        if (!gameState.upgradedStartingCards) gameState.upgradedStartingCards = {};
        gameState.upgradedStartingCards[card.name] = (gameState.upgradedStartingCards[card.name] || 0) + 1;
        upgradeCount++;
      } else {
        const deckIdx = gameState.deck.findIndex(c => c === card);
        if (deckIdx !== -1) {
          gameState.deck[deckIdx].upgraded = true;
          if (gameState.deck[deckIdx].upgradedDescription) {
            gameState.deck[deckIdx].description = gameState.deck[deckIdx].upgradedDescription;
          }
          if (gameState.deck[deckIdx].upgradedCost !== null && gameState.deck[deckIdx].upgradedCost !== undefined) {
            gameState.deck[deckIdx].cost = gameState.deck[deckIdx].upgradedCost;
          }
          upgradeCount++;
        }
      }
    });
    if (typeof saveCurrentGame === 'function') saveCurrentGame();
    closeGameModal();
    if (typeof createNotification === 'function') {
      createNotification(`Upgraded ${upgradeCount} card${upgradeCount !== 1 ? 's' : ''}!`, '#FF9800', '⚒️');
    }
    if (window._postcombatOnComplete) { const cb = window._postcombatOnComplete; window._postcombatOnComplete = null; cb(); }
  });
}

/**
 * Handle defeat in dice combat
 */
function handleDiceCombatDefeat(enemy) {
  // Cleanup 3D dice renderers
  if (window.CombatUI && window.CombatUI.cleanup3DDice) {
    window.CombatUI.cleanup3DDice();
  }

  // Hide all floating combat tooltips
  ['enemy-pattern-tooltip', 'combat-status-tooltip', 'combat-card-tooltip'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.style.display = 'none';
  });

  window.CombatEngine.endCombat(false);
  gameState.phase = 'selection'; // allow scrolls/items outside combat

  // Clear items, curses, and allies on death
  inventory = [];
  if (gameState.activeCurses) {
    gameState.activeCurses = [];
  }
  if (gameState.activeAllies) {
    gameState.activeAllies = [];
  }

  // Record player killed by enemy for collection stats
  if (typeof recordPlayerKilledBy === 'function') {
    recordPlayerKilledBy(enemy.name);
  }

  // Record encounter
  encounterHistory.push({
    type: 'combat',
    enemy: enemy.name,
    outcome: 'Defeat',
    timestamp: new Date().toLocaleString()
  });
  updateEncounterHistory();

  // Show death screen
  createGameModal(`
    <div style="text-align: center; padding: 30px;">
      <h1 style="color: #ff4444; font-size: 48px; margin: 20px 0;">YOU DIED</h1>
      <p style="color: #aaa; font-size: 18px; margin: 20px 0;">Defeated by ${enemy.name}</p>
      <div style="margin-top: 30px; display: flex; gap: 15px; justify-content: center;">
        <button id="dice-death-home-btn" style="
          padding: 12px 24px;
          background: #444;
          border: 2px solid #666;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">Home</button>
        <button id="dice-death-retry-btn" style="
          padding: 12px 24px;
          background: #d32f2f;
          border: 2px solid #f44336;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">Try Again</button>
      </div>
    </div>
  `);

  document.getElementById('dice-death-home-btn').onclick = () => {
    closeGameModal();
    updateInventory?.();
    updateCursesDisplay?.();
    if (typeof clearAllArrows === 'function') clearAllArrows();
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';
    const topBarRight = document.getElementById('top-bar-right');
    if (topBarRight) topBarRight.style.display = 'none';
  };

  document.getElementById('dice-death-retry-btn').onclick = () => {
    closeGameModal();
    if (typeof clearAllArrows === 'function') clearAllArrows();
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';
    const topBarRight = document.getElementById('top-bar-right');
    if (topBarRight) topBarRight.style.display = 'none';
    setTimeout(() => {
      document.getElementById('new-game-btn')?.click();
    }, 100);
  };
}

// Make new combat modal available globally
window.showDiceCombatModal = showDiceCombatModal;

// Expose combat system toggle
Object.defineProperty(window, 'useDiceCombat', {
  get: function() { return useDiceCombat; },
  set: function(val) {
    useDiceCombat = val;
  }
});

// Toggle combat system function
window.toggleCombatSystem = function() {
  useDiceCombat = !useDiceCombat;
  return useDiceCombat;
};

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
  if (!gameState.inventory) gameState.inventory = [];
  gameState.inventory.push(item);
  if (typeof inventory !== 'undefined') inventory.push(item);
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
      const globalInv = typeof inventory !== 'undefined' ? inventory : (gameState.inventory || []);
      const invIdx = globalInv.indexOf(item);
      if (invIdx !== -1) {
        globalInv.splice(invIdx, 1);
        if (gameState.inventory && gameState.inventory !== globalInv) {
          const gi = gameState.inventory.indexOf(item);
          if (gi !== -1) gameState.inventory.splice(gi, 1);
        }
      }
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
  if (bonuses.strength) {
    strength += bonuses.strength;
    appliedBonuses.push(`+${bonuses.strength} Strength`);
  }
  if (bonuses.dexterity) {
    dexterity += bonuses.dexterity;
    appliedBonuses.push(`+${bonuses.dexterity} Dexterity`);
  }
  if (bonuses.intelligence) {
    intelligence += bonuses.intelligence;
    appliedBonuses.push(`+${bonuses.intelligence} Intelligence`);
  }
  if (bonuses.charisma) {
    charisma += bonuses.charisma;
    appliedBonuses.push(`+${bonuses.charisma} Charisma`);
  }
  if (bonuses.reroll) {
    reroll += bonuses.reroll;
    gameState.reroll = reroll;
    appliedBonuses.push(`+${bonuses.reroll} Reroll`);
  }
  if (bonuses.dash) {
    gameState.dash = (gameState.dash || 0) + bonuses.dash;
    appliedBonuses.push(`+${bonuses.dash} Dash`);
  }
  if (bonuses.luck) {
    luck += bonuses.luck;
    gameState.luck = luck;
    appliedBonuses.push(`+${bonuses.luck} Luck`);
  }
  if (bonuses.skip) {
    skip += bonuses.skip;
    gameState.skip = skip;
    appliedBonuses.push(`+${bonuses.skip} Skip`);
  }
  if (bonuses.discovery) {
    discovery += bonuses.discovery;
    gameState.discovery = discovery;
    appliedBonuses.push(`+${bonuses.discovery} Discovery`);
  }
  if (bonuses.fov) {
    fov += bonuses.fov;
    gameState.fov = fov;
    appliedBonuses.push(`+${bonuses.fov} FoV`);
  }
  if (bonuses.maxHealth) {
    maxHealth += bonuses.maxHealth;
    health = Math.min(health + bonuses.maxHealth, maxHealth);
    gameState.maxHealth = maxHealth;
    gameState.health = health;
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
        gold = (gold || 0) + reward.amount;
        gameState.gold = gold;
        saveCurrentGame();
        if (typeof updateTopBar === 'function') updateTopBar();
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

// Make level-up functions globally available
window.showLevelUpPrompt = showLevelUpPrompt;
window.confirmLevelUp = confirmLevelUp;
window.showVictoryScreen = showVictoryScreen;
window.showCardRewardModal = showCardRewardModal;
window.showDiceLevelUpChoiceModal = showDiceLevelUpChoiceModal;
window._doLearnSpell = _doLearnSpell;

// ============== ALLY SYSTEM ==============

/**
 * Recruit an ally
 * @param {string} allyName - Name of the ally from ALLIES_DATA
 * @returns {boolean} Success
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

// Check if an event's requirement is met
function checkEventRequirement(event) {
  if (!event.requirement) return true; // No requirement means always available

  switch (event.requirement.type) {
    case 'minItems':
      return inventory.length >= event.requirement.value;
    // Add more requirement types here as needed
    default:
      return true;
  }
}

function showEventModal(specificEvent = null) {
  if (events.length === 0) return;

  // Set phase to event
  gameState.phase = 'event';
  updateInventory(); // Refresh item UI to update usable item buttons

  // Use specific event if provided, otherwise random from available events
  let event;
  if (specificEvent) {
    event = events.find(e => e.name === specificEvent);
    if (!event) {
      // Fallback to random if specific event not found
      const availableEvents = events.filter(e => checkEventRequirement(e));
      if (availableEvents.length === 0) {
        console.warn('No events available that meet requirements');
        return;
      }
      const randomIndex = Math.floor(Math.random() * availableEvents.length);
      event = availableEvents[randomIndex];
    }
  } else {
    // Filter events by requirements
    const availableEvents = events.filter(e => checkEventRequirement(e));
    if (availableEvents.length === 0) {
      console.warn('No events available that meet requirements');
      return;
    }
    const randomIndex = Math.floor(Math.random() * availableEvents.length);
    event = availableEvents[randomIndex];
  }

  // Store current event in gameState so we can return to it
  gameState.currentEvent = event.name;

  let optionsHTML = '<div style="display: flex; flex-direction: column; gap: 10px; margin-top: 20px;">';

  event.options.forEach((option, index) => {
    const optionType = detectOptionType(option);
    const borderColor = optionType === 'attack' ? '#e74c3c' :
                       optionType === 'explore' ? '#3498db' :
                       optionType === 'talk' ? '#2ecc71' : '#f39c12';

    optionsHTML += `
      <button class="event-modal-option" data-index="${index}" style="
        padding: 12px 20px;
        background: #2d2d2d;
        border: 2px solid ${borderColor};
        border-left: 6px solid ${borderColor};
        border-radius: 6px;
        color: white;
        cursor: pointer;
        text-align: left;
        transition: all 0.2s;
      ">${option}</button>
    `;
  });

  optionsHTML += '</div>';

  createGameModal(`
    <div>
      <h2 style="color: #9b59b6; margin-top: 0;">Event Encounter!</h2>
      <h3>${event.name}</h3>
      <p>${event.description}</p>
      ${optionsHTML}
    </div>
  `);

  document.querySelectorAll('.event-modal-option').forEach(btn => {
    btn.onmouseenter = (e) => {
      e.target.style.transform = 'translateX(5px)';
      e.target.style.background = '#4a4440';
    };
    btn.onmouseleave = (e) => {
      e.target.style.transform = '';
      e.target.style.background = '#3a3430';
    };
    btn.onclick = (e) => {
      const optionIndex = e.target.dataset.index;
      handleEventChoice(event, event.options[optionIndex]);
    };
  });
}

function handleEventChoice(event, option) {
  encounterHistory.push({
    type: 'event',
    name: event.name,
    option: option,
    timestamp: new Date().toLocaleString()
  });
  updateEncounterHistory();

  // Get option index
  const optionIndex = event.options.indexOf(option);

  // Handle each event specifically
  if (event.name === "Primordial Teleporter") {
    handlePrimordialTeleporter(optionIndex);
  } else if (event.name === "A Wild Muncher Appears") {
    handleWildMuncher(optionIndex);
  } else if (event.name === "The Colosseum") {
    handleColosseum(optionIndex);
  } else {
    // Default behavior for unknown events
    closeGameModal();
  }

  saveCurrentGame();
}

// ===== EVENT HANDLERS =====

// ----- Generic Combat Function -----
// This function can be called from anywhere to trigger a combat encounter
// Usage: triggerCombat(enemyObject, onSuccessCallback, onFailureCallback, powerLevel)
function triggerCombat(enemy, onSuccess = null, onFailure = null, powerLevel = 'Medium') {
  if (!enemy) {
    console.error('triggerCombat: No enemy provided');
    return;
  }

  // Get player's stat value for this check
  const playerStatValue = getPlayerStat(enemy.stat);

  const enemyImagePath = getEnemyImagePath(enemy.name);

  createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #ff4444; margin-top: 0;">Combat Encounter!</h2>
      <h3>${enemy.name}</h3>
      <p style="color: #888;">From: ${enemy.game || 'Unknown'}</p>
      <img src="${enemyImagePath}" style="width: 200px; height: 200px; image-rendering: pixelated; object-fit: contain; margin: 10px auto; display: block;" alt="${enemy.name}" onerror="this.style.display='none'">
      <div style="background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; margin: 15px 0;">
        <p style="font-size: 18px; margin: 5px 0;">
          <span style="color: ${getStatColor(enemy.stat)};">${enemy.stat}</span> Check:
          <strong>Roll ${enemy.rollCheck}+</strong>
        </p>
        <p style="font-size: 16px; margin: 5px 0; color: #aaa;">
          Your ${enemy.stat}: <strong style="color: ${getStatColor(enemy.stat)};">${playerStatValue >= 0 ? '+' : ''}${playerStatValue}</strong>
        </p>
        <p style="font-size: 14px; margin: 5px 0; color: #888;">
          (D20 + ${playerStatValue} must be ≥ ${enemy.rollCheck})
        </p>
      </div>
      <button id="roll-generic-combat-btn" style="padding: 20px 40px; font-size: 20px; background: #4CAF50; border: none; border-radius: 8px; color: white; cursor: pointer; margin: 15px auto; display: block; min-width: 180px; font-weight: bold; position: relative; z-index: 10;">
        Roll D20
      </button>
      <div id="generic-combat-result" style="margin-top: 20px; font-size: 16px;"></div>
    </div>
  `);

  document.getElementById('roll-generic-combat-btn').onclick = () => {
    const roll = Math.floor(Math.random() * 20) + 1;
    const total = roll + playerStatValue;
    const success = total >= enemy.rollCheck;

    document.getElementById('generic-combat-result').innerHTML = `
      <p style="font-size: 20px; color: ${success ? '#4CAF50' : '#ff4444'};">
        Rolled: ${roll} + ${playerStatValue} = ${total} ${success ? '✓ SUCCESS' : '✗ FAILURE'}
      </p>
      <button onclick="handleGenericCombatResult(${success}, '${powerLevel}')" style="padding: 10px 20px; margin-top: 20px; background: #4CAF50; border: none; border-radius: 6px; color: white; cursor: pointer;">Continue</button>
    `;

    // Store callbacks for the result handler
    window._genericCombatCallbacks = {
      success: onSuccess,
      failure: onFailure,
      enemy: enemy
    };
  };
}

function handleGenericCombatResult(success, powerLevel) {
  const callbacks = window._genericCombatCallbacks || {};
  const enemy = callbacks.enemy;

  if (success) {
    // Trigger onEnemyDefeated effects for triggered items
    if (typeof triggerOnEnemyDefeated === 'function') {
      triggerOnEnemyDefeated();
    }

    // Apply success rewards if specified
    if (enemy && enemy.successReward) {
      const goldMatch = enemy.successReward.match(/(\d+) Gold/);
      if (goldMatch) {
        const goldAmount = parseInt(goldMatch[1]);
        gold += goldAmount;
        gameState.gold = gold;
        updateTopBar();
      }
    }

    // Call custom success callback
    if (callbacks.success) {
      closeGameModal();
      callbacks.success();
    } else {
      closeGameModal();
    }
  } else {
    // Failed - take damage based on power level
    let healthLoss = 1; // Low difficulty
    if (powerLevel === 'Medium') {
      healthLoss = 2;
    } else if (powerLevel === 'High') {
      healthLoss = 3;
    }

    // Apply damage reduction from items (like Garlic)
    if (typeof calculateDamageReduction === 'function') {
      healthLoss = calculateDamageReduction(healthLoss);
    }

    health = Math.max(0, health - healthLoss);
    gameState.health = health;
    updateHealthDisplay();
    updateTopBar();

    // Call custom failure callback
    if (callbacks.failure) {
      closeGameModal();
      callbacks.failure();
    } else {
      closeGameModal();
    }
  }

  // Clean up callbacks
  delete window._genericCombatCallbacks;
}

// ----- Primordial Teleporter Event -----

function handlePrimordialTeleporter(optionIndex) {
  if (optionIndex === 0) {
    // Enter the teleporter - teleport to random action roguelike
    closeGameModal();
    teleportToRandomGameOfType('Action');
  } else if (optionIndex === 1) {
    // Interact with teleporter, then enter - teleport to starting game and decrease difficulty
    closeGameModal();

    // Decrease difficulty by 3 games
    if (gameState.totalGamesBeaten && gameState.totalGamesBeaten >= 3) {
      gameState.totalGamesBeaten -= 3;
    } else {
      gameState.totalGamesBeaten = 0;
    }

    // Teleport to starting game (gameState.startGame is already the game object)
    if (gameState.startGame) {
      const x = 450;
      const y = gameState.currentY + 200;
      advance(gameState.startGame.name, x, y, null); // Pass null to skip encounter
    }
  } else if (optionIndex === 2) {
    // Fight off the Stone Golems - 3 consecutive combats
    gameState.stoneGolemFightsRemaining = 3;
    closeGameModal();
    triggerStoneGolemFight();
  }
}

function triggerStoneGolemFight() {
  if (gameState.stoneGolemFightsRemaining <= 0) {
    // All fights complete
    delete gameState.stoneGolemFightsRemaining;
    createNotification('Defeated all Stone Golems!', '#4CAF50', '⚔️');
    return;
  }

  // Find the Stone Golem enemy
  const stoneGolem = enemies.find(e => e.name === 'Stone Golem');
  if (!stoneGolem) {
    console.error('Stone Golem enemy not found!');
    delete gameState.stoneGolemFightsRemaining;
    return;
  }

  // Trigger combat with Stone Golem
  const playerStatValue = getPlayerStat(stoneGolem.stat);

  const stoneGolemImagePath = getEnemyImagePath(stoneGolem.name);

  createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #ff4444; margin-top: 0;">Combat Encounter!</h2>
      <h3>${stoneGolem.name} (${4 - gameState.stoneGolemFightsRemaining}/3)</h3>
      <p style="color: #888;">From: ${stoneGolem.game}</p>
      <img src="${stoneGolemImagePath}" style="max-width: 200px; max-height: 200px; image-rendering: pixelated; margin: 10px auto; display: block;" alt="${stoneGolem.name}" onerror="this.style.display='none'">
      <div style="background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; margin: 15px 0;">
        <p style="font-size: 18px; margin: 5px 0;">
          <span style="color: ${getStatColor(stoneGolem.stat)};">${stoneGolem.stat}</span> Check:
          <strong>Roll ${stoneGolem.rollCheck}+</strong>
        </p>
        <p style="font-size: 16px; margin: 5px 0; color: #aaa;">
          Your ${stoneGolem.stat}: <strong style="color: ${getStatColor(stoneGolem.stat)};">${playerStatValue >= 0 ? '+' : ''}${playerStatValue}</strong>
        </p>
        <p style="font-size: 14px; margin: 5px 0; color: #888;">
          (D20 + ${playerStatValue} must be ≥ ${stoneGolem.rollCheck})
        </p>
      </div>
      <button id="roll-stone-golem-btn" style="padding: 20px 40px; font-size: 20px; background: #4CAF50; border: none; border-radius: 8px; color: white; cursor: pointer; margin: 15px auto; display: block; min-width: 180px; font-weight: bold; position: relative; z-index: 10;">
        Roll D20
      </button>
      <div id="stone-golem-result" style="margin-top: 20px; font-size: 16px;"></div>
    </div>
  `);

  document.getElementById('roll-stone-golem-btn').onclick = () => {
    const rollBtn = document.getElementById('roll-stone-golem-btn');
    rollBtn.disabled = true;
    rollBtn.style.opacity = '0.5';
    rollBtn.style.cursor = 'not-allowed';

    const roll = Math.floor(Math.random() * 20) + 1;
    const total = roll + playerStatValue;
    const success = total >= stoneGolem.rollCheck;

    document.getElementById('stone-golem-result').innerHTML = `
      <p style="font-size: 20px; color: ${success ? '#4CAF50' : '#ff4444'};">
        Rolled: ${roll} + ${playerStatValue} = ${total} ${success ? '✓ SUCCESS' : '✗ FAILURE'}
      </p>
      <button onclick="handleStoneGolemResult(${success})" style="padding: 10px 20px; margin-top: 20px; background: #4CAF50; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold;">Continue</button>
    `;
  };
}

function handleStoneGolemResult(success) {
  gameState.stoneGolemFightsRemaining--;

  if (success) {
    // Give gold for defeating Stone Golem
    const goldReward = 10;
    gold += goldReward;
    gameState.gold = gold;
    updateGoldDisplay();
    updateTopBar();
    createNotification(`+${goldReward} gold for defeating Stone Golem!`, '#ffdd77', '💰');

    // Trigger onEnemyDefeated effects for triggered items
    if (typeof triggerOnEnemyDefeated === 'function') {
      triggerOnEnemyDefeated();
    }
  } else {
    // Failed - take 2 damage and gain a curse
    let damage = 2;

    // Apply damage reduction from items (like Garlic)
    if (typeof calculateDamageReduction === 'function') {
      damage = calculateDamageReduction(damage);
    }

    health = Math.max(0, health - damage);
    gameState.health = health;
    updateHealthDisplay();
    updateTopBar();

    // Add a random curse for losing to Stone Golem
    const availableCurses = curses.filter(c =>
      !gameState.activeCurses.some(ac => ac.name === c.name)
    );

    if (availableCurses.length > 0) {
      const randomCurse = availableCurses[Math.floor(Math.random() * availableCurses.length)];
      if (typeof addCurse === 'function') {
        addCurse(randomCurse.name);
        createNotification(`Cursed with ${randomCurse.name}!`, '#ff4444', '😈');
      }
    }
  }

  if (gameState.stoneGolemFightsRemaining > 0) {
    // More fights remaining
    triggerStoneGolemFight();
  } else {
    // All fights complete
    delete gameState.stoneGolemFightsRemaining;
    closeGameModal();
    createNotification(success ? 'Defeated all Stone Golems!' : 'Survived the Stone Golems!', '#4CAF50', '⚔️');
  }
}

// ----- Wild Muncher Event -----

function handleWildMuncher(optionIndex) {
  if (optionIndex === 0) {
    // Feed it four items
    if (inventory.length < 4) {
      createGameModal(`
        <div style="text-align: center;">
          <h2 style="color: #ff4444; margin-top: 0;">Not Enough Items</h2>
          <p>You need at least 4 items to feed the Muncher!</p>
          <button onclick="closeGameModal()" style="padding: 10px 20px; margin-top: 20px; background: #4CAF50; border: none; border-radius: 6px; color: white; cursor: pointer;">Continue</button>
        </div>
      `);
      return;
    }

    // Show item selection modal for 4 items → 2 items
    showItemSelectionForMuncher(4, 2);
  } else if (optionIndex === 1) {
    // Feed it two items
    if (inventory.length < 2) {
      createGameModal(`
        <div style="text-align: center;">
          <h2 style="color: #ff4444; margin-top: 0;">Not Enough Items</h2>
          <p>You need at least 2 items to feed the Muncher!</p>
          <button onclick="closeGameModal()" style="padding: 10px 20px; margin-top: 20px; background: #4CAF50; border: none; border-radius: 6px; color: white; cursor: pointer;">Continue</button>
        </div>
      `);
      return;
    }

    // Show item selection modal for 2 items → 1 item
    showItemSelectionForMuncher(2, 1);
  } else {
    // Leave it hungry - do nothing
    closeGameModal();
    createNotification('You left the Muncher hungry...', '#888', '👀');
  }
}

function showItemSelectionForMuncher(itemsToFeed, itemsToReceive) {
  const itemsHTML = inventory.map((item, index) => `
    <div class="muncher-item" data-index="${index}" style="
      padding: 10px;
      margin: 5px 0;
      background: #3a3430;
      border: 2px solid #666;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.2s;
    ">
      <strong>${item.name}</strong> (${item.rarity})
    </div>
  `).join('');

  createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #4CAF50; margin-top: 0;">Feed the Muncher</h2>
      <p>Select ${itemsToFeed} items to feed to the Muncher. You'll get ${itemsToReceive} random item${itemsToReceive > 1 ? 's' : ''} in return.</p>
      <div id="muncher-selection" style="margin: 20px 0; max-height: 300px; overflow-y: auto;">
        ${itemsHTML}
      </div>
      <p id="muncher-count" style="color: #aaa; font-size: 14px;">Selected: 0/${itemsToFeed}</p>
      <div style="display: flex; gap: 10px; justify-content: center; margin-top: 15px;">
        <button id="muncher-back" style="padding: 10px 20px; background: #666; border: none; border-radius: 6px; color: white; cursor: pointer;">Back</button>
        <button id="muncher-confirm" disabled style="padding: 10px 20px; background: #666; border: none; border-radius: 6px; color: white; cursor: not-allowed;">Confirm</button>
      </div>
    </div>
  `);

  let selectedIndices = [];

  document.querySelectorAll('.muncher-item').forEach(div => {
    div.onclick = () => {
      const index = parseInt(div.dataset.index);

      if (selectedIndices.includes(index)) {
        // Deselect
        selectedIndices = selectedIndices.filter(i => i !== index);
        div.style.borderColor = '#666';
        div.style.background = '#3a3430';
      } else if (selectedIndices.length < itemsToFeed) {
        // Select
        selectedIndices.push(index);
        div.style.borderColor = '#4CAF50';
        div.style.background = '#2a4430';
      }

      document.getElementById('muncher-count').textContent = `Selected: ${selectedIndices.length}/${itemsToFeed}`;

      const confirmBtn = document.getElementById('muncher-confirm');
      if (selectedIndices.length === itemsToFeed) {
        confirmBtn.disabled = false;
        confirmBtn.style.background = '#4CAF50';
        confirmBtn.style.cursor = 'pointer';
      } else {
        confirmBtn.disabled = true;
        confirmBtn.style.background = '#666';
        confirmBtn.style.cursor = 'not-allowed';
      }
    };
  });

  document.getElementById('muncher-confirm').onclick = () => {
    feedMuncher(selectedIndices, itemsToReceive);
  };

  document.getElementById('muncher-back').onclick = () => {
    closeGameModal();
    // Return to the specific event that was showing
    showEventModal(gameState.currentEvent || 'A Wild Muncher Appears');
  };
}

function feedMuncher(indices, itemsToReceive) {
  // Get the items being fed
  const fedItems = indices.map(i => inventory[i]);

  // Determine rarity logic based on items fed
  const rarityOrder = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary'];

  let targetRarities = [];

  if (itemsToReceive === 2) {
    // 4 items → 2 items: correlating rarity (randomly pick from fed items' rarities)
    // Get all fed rarities and pick randomly for each new item
    const fedRarities = fedItems.map(item => item.rarity);
    targetRarities = [
      fedRarities[Math.floor(Math.random() * fedRarities.length)],
      fedRarities[Math.floor(Math.random() * fedRarities.length)]
    ];
  } else if (itemsToReceive === 1) {
    // 2 items → 1 item: least rare item discarded
    const fedRarities = fedItems.map(item => item.rarity);
    // Find the least rare (lowest in rarityOrder)
    const leastRare = fedRarities.reduce((least, current) => {
      const leastIndex = rarityOrder.indexOf(least);
      const currentIndex = rarityOrder.indexOf(current);
      return currentIndex < leastIndex ? current : least;
    });
    targetRarities = [leastRare];
  }

  // Remove items (in reverse order to maintain indices)
  indices.sort((a, b) => b - a);
  indices.forEach(index => {
    removeItemAndReverseStats(index);
  });

  // Give random items of target rarities
  targetRarities.forEach(targetRarity => {
    const rarityItems = items.filter(item => item.rarity === targetRarity && item.rarity !== 'N/A');
    if (rarityItems.length > 0) {
      const randomItem = rarityItems[Math.floor(Math.random() * rarityItems.length)];
      acquireItem(randomItem);
    }
  });

  closeGameModal();
  const rarityText = targetRarities.length > 1
    ? `${targetRarities.length} items (${targetRarities.join(', ')})`
    : `a ${targetRarities[0]} item`;
  createNotification(`Fed the Muncher! Received ${rarityText}!`, '#4CAF50', '🎁');
}

function removeItemAndReverseStats(index) {
  const item = inventory[index];

  // Reverse item effects (but NOT reroll, dash, skip)
  // NOTE: This parses the item description to determine what stats to reverse
  // For health items, we reduce max health and cap current health to prevent death
  // If an item gave "+5 Health", we treat it as max health for reversal purposes
  if (ITEM_EFFECTS && ITEM_EFFECTS[item.name] && ITEM_EFFECTS[item.name].onAcquire) {
    // Check if item modifies stats by parsing description
    const desc = item.description.toLowerCase();

    // Pattern: "+X Stat"
    const statMatches = [
      { pattern: /\+(\d+)\s+strength/i, stat: 'strength' },
      { pattern: /\+(\d+)\s+dexterity/i, stat: 'dexterity' },
      { pattern: /\+(\d+)\s+intelligence/i, stat: 'intelligence' },
      { pattern: /\+(\d+)\s+charisma/i, stat: 'charisma' },
      { pattern: /\+(\d+)\s+luck/i, stat: 'luck' },
      { pattern: /\+(\d+)\s+health/i, stat: 'maxHealth' },
      { pattern: /\+(\d+)\s+max health/i, stat: 'maxHealth' },
      { pattern: /\+(\d+)\s+gold/i, stat: 'gold' },
      { pattern: /\+(\d+)\s+discovery/i, stat: 'discovery' },
      { pattern: /\+(\d+)\s+fov/i, stat: 'fov' }
    ];

    statMatches.forEach(({ pattern, stat }) => {
      const match = desc.match(pattern);
      if (match) {
        const value = parseInt(match[1]);
        // Reverse the stat change (but skip reroll, dash, skip, and maxHealth/health)
        if (stat !== 'reroll' && stat !== 'dash' && stat !== 'skip' && stat !== 'maxHealth') {
          if (stat === 'gold') {
            gold = Math.max(0, gold - value);
            gameState.gold = gold;
            updateTopBar();
          } else {
            // Regular stats
            window[stat] = Math.max(0, window[stat] - value);
            gameState[stat] = window[stat];
          }
        }
        // Skip maxHealth and health changes (Binding of Isaac behavior - stats go down but not health)
      }
    });
  }

  // Remove stat modifiers from passive items (Caves of Qud effect)
  if (typeof removeItemStatEffects === 'function') {
    removeItemStatEffects(item);
  }

  // Remove from inventory (handle quantity)
  if (item.quantity && item.quantity > 1) {
    item.quantity--;
  } else {
    inventory.splice(index, 1);
  }
  gameState.inventory = inventory;
  updateInventory();
}

// ----- Colosseum Event -----

function handleColosseum(optionIndex) {
  if (!gameState.colosseumState) {
    // First time - start the first fight immediately
    gameState.colosseumState = {
      stage: 'first_fight',
      returnGame: gameState.currentGame
    };

    closeGameModal();

    // Teleport to random game with connected = false (or amulet game) without triggering encounter
    const unconnectedGames = games.filter(g => !g.connected || g.name === gameState.amuletGame?.name);
    if (unconnectedGames.length > 0) {
      const randomGame = unconnectedGames[Math.floor(Math.random() * unconnectedGames.length)];
      const x = 450;
      const y = gameState.currentY + 200;
      advance(randomGame.name, x, y, null); // Pass null to skip encounter
    } else {
      createNotification('No arena game available!', '#ff4444', '⚠️');
      delete gameState.colosseumState;
    }
  } else if (gameState.colosseumState.stage === 'choice') {
    // Player is making choice after beating first game
    if (optionIndex === 0) {
      // Escape the arena - teleport back without triggering encounter
      const returnGameName = gameState.colosseumState.returnGame;
      const returnGame = games.find(g => g.name === returnGameName);

      delete gameState.colosseumState;
      closeGameModal();

      if (returnGame) {
        const x = 450;
        const y = gameState.currentY + 200;
        advance(returnGame.name, x, y, null); // Pass null to skip encounter
      }
    } else if (optionIndex === 1) {
      // Challenge the Champion - teleport to another unconnected game without triggering encounter
      gameState.colosseumState.stage = 'champion';

      closeGameModal();

      // Teleport to unconnected game (or amulet game)
      const unconnectedGames = games.filter(g => !g.connected || g.name === gameState.amuletGame?.name);
      if (unconnectedGames.length > 0) {
        const randomGame = unconnectedGames[Math.floor(Math.random() * unconnectedGames.length)];
        const x = 450;
        const y = gameState.currentY + 200;
        advance(randomGame.name, x, y, null); // Pass null to skip encounter
      } else {
        createNotification('No champion available!', '#ff4444', '⚠️');
        delete gameState.colosseumState;
      }
    }
  }
}

function showColosseumChoices() {
  // Show the two choices after completing first fight: Escape or Challenge Champion
  createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #ff9900; margin-top: 0;">⚔️ The Colosseum</h2>
      <p style="color: #4CAF50; margin: 15px 0; font-size: 16px; font-weight: bold;">You survived the first battle! What will you do?</p>
      <div style="display: flex; flex-direction: column; gap: 15px; margin-top: 25px; align-items: center;">
        <button
          onclick="handleColosseum(0)"
          style="
            padding: 15px 25px;
            min-width: 300px;
            background: #4a90e2;
            border: 2px solid #5ca4f2;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-size: 16px;
            font-weight: bold;
            transition: all 0.2s;
          "
          onmouseover="this.style.background='#5ca4f2'; this.style.transform='scale(1.05)';"
          onmouseout="this.style.background='#4a90e2'; this.style.transform='scale(1)';"
        >
          Escape the arena (Return to original game)
        </button>
        <button
          onclick="handleColosseum(1)"
          style="
            padding: 15px 25px;
            min-width: 300px;
            background: #ff6600;
            border: 2px solid #ff8833;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-size: 14px;
            font-weight: bold;
            transition: all 0.2s;
            line-height: 1.4;
          "
          onmouseover="this.style.background='#ff8833'; this.style.transform='scale(1.05)';"
          onmouseout="this.style.background='#ff6600'; this.style.transform='scale(1)';"
        >
          Challenge the Champion<br>
          <span style="font-size: 12px; font-weight: normal; opacity: 0.9;">
            (Fight another action game not connected to the rest of the map. If you beat it within 3 attempts gain two random items, if not you lose 3 health)
          </span>
        </button>
      </div>
    </div>
  `);
}

function handleChampionResult() {
  // Player beat the champion game - ask if it took 3 or less attempts
  createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #ff9900; margin-top: 0;">⚔️ Champion Challenge Complete!</h2>
      <p style="color: #aaa; margin: 15px 0; font-size: 16px;">You've beaten the champion game!</p>
      <p style="color: #ffaa00; margin: 15px 0; font-size: 16px; font-weight: bold;">Did it take you three or less attempts?</p>
      <div style="margin-top: 25px;">
        <button
          onclick="completeChampionSuccess()"
          style="
            padding: 15px 30px;
            margin: 10px;
            background: #4CAF50;
            border: 2px solid #5cb85c;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-size: 16px;
            font-weight: bold;
          "
        >
          Yes (Gain 2 Random Items)
        </button>
        <button
          onclick="completeChampionFailure()"
          style="
            padding: 15px 30px;
            margin: 10px;
            background: #ff4444;
            border: 2px solid #ff6666;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-size: 16px;
            font-weight: bold;
          "
        >
          No (Lose 3 Health)
        </button>
      </div>
    </div>
  `);
}

function completeChampionSuccess() {
  // Give 2 items using luck-based rarity selection
  for (let i = 0; i < 2; i++) {
    const targetRarity = selectRandomRarity();
    const rarityItems = items.filter(item => item.rarity === targetRarity && item.rarity !== 'N/A');

    if (rarityItems.length > 0) {
      const randomItem = rarityItems[Math.floor(Math.random() * rarityItems.length)];
      acquireItem(randomItem);
    } else {
      // Fallback to any random item if no items of target rarity exist
      const nonNAItems = items.filter(item => item.rarity !== 'N/A');
      const randomItem = nonNAItems[Math.floor(Math.random() * nonNAItems.length)];
      acquireItem(randomItem);
    }
  }

  createNotification('Received 2 random items!', '#4CAF50', '🎁');

  // Teleport back to return game without triggering an encounter
  const returnGameName = gameState.colosseumState.returnGame;
  const returnGame = games.find(g => g.name === returnGameName);

  delete gameState.colosseumState;
  closeGameModal();

  if (returnGame) {
    const x = 450;
    const y = gameState.currentY + 200;
    advance(returnGame.name, x, y, null); // Pass null to skip encounter
  }
}

function completeChampionFailure() {
  // Lose 3 health
  let damage = 3;

  // Apply damage reduction from items (like Garlic)
  if (typeof calculateDamageReduction === 'function') {
    damage = calculateDamageReduction(damage);
  }

  health = Math.max(0, health - damage);
  gameState.health = health;
  updateHealthDisplay();
  updateTopBar();

  createNotification('Lost 3 health from failed challenge!', '#ff4444', '💔');

  // Teleport back to return game without triggering an encounter
  const returnGameName = gameState.colosseumState.returnGame;
  const returnGame = games.find(g => g.name === returnGameName);

  delete gameState.colosseumState;
  closeGameModal();

  if (returnGame) {
    const x = 450;
    const y = gameState.currentY + 200;
    advance(returnGame.name, x, y, null); // Pass null to skip encounter
  }

  // Check if player died
  if (health <= 0) {
    setTimeout(() => {
      if (typeof triggerDeath === 'function') {
        triggerDeath();
      }
    }, 1000);
  }
}


function showItemChoiceModal(onComplete, chestType = 'normal', typeFilter = null) {
  if (items.length === 0) {
    // If no items, just spawn choices or call callback
    if (typeof onComplete === 'function') {
      setTimeout(() => onComplete(), 300);
    } else {
      setTimeout(() => spawnChoices(), 300);
    }
    return;
  }

  // Apply location effects to item pool (e.g., gun spawn boost from Gungeon locations)
  // Exclude N/A rarity items (boons) from normal item pools
  let itemPool = items.filter(item => item.rarity !== 'N/A');
  if (typeFilter) {
    const filtered = itemPool.filter(item => item.type === typeFilter);
    if (filtered.length > 0) itemPool = filtered;
  }
  if (gameState?.location && typeof applyGunSpawnBoost === 'function') {
    itemPool = applyGunSpawnBoost(itemPool, gameState.location);
  }

  const choices = [];
  const maxAttempts = 100; // Prevent infinite loop

  // Determine base count and rarity filter based on chest type
  let baseCount = 2; // default for normal chest
  let rarityFilter = null; // null means any rarity
  let chestTitle = '🎁 Chest';

  switch(chestType) {
    case 'small':
      baseCount = 1;
      chestTitle = '📦 Small Chest';
      break;
    case 'large':
      baseCount = 3;
      chestTitle = '🎁 Large Chest';
      break;
    case 'common':
      rarityFilter = 'common';
      chestTitle = '📦 Common Chest';
      break;
    case 'uncommon':
      rarityFilter = 'uncommon';
      chestTitle = '📦 Uncommon Chest';
      break;
    case 'rare':
      rarityFilter = 'rare';
      chestTitle = '🎁 Rare Chest';
      break;
    case 'legendary':
      rarityFilter = 'legendary';
      chestTitle = '✨ Legendary Chest';
      break;
    default:
      chestTitle = '🎁 Chest';
  }

  // Number of item choices = baseCount + discovery stat
  const numChoices = baseCount + discovery;

  for (let i = 0; i < numChoices; i++) {
    let attempts = 0;
    let selectedItem = null;

    while (attempts < maxAttempts) {
      let targetRarity;

      if (rarityFilter) {
        // If chest has a rarity filter, use only that rarity
        targetRarity = rarityFilter;
      } else {
        // Use luck-based rarity selection for normal chests
        targetRarity = selectRandomRarity();
      }

      const rarityItems = itemPool.filter(item => item.rarity && item.rarity.toLowerCase() === targetRarity.toLowerCase());
      if (rarityItems.length > 0) {
        const randomIndex = Math.floor(Math.random() * rarityItems.length);
        selectedItem = rarityItems[randomIndex];
      } else if (!rarityFilter) {
        // Fallback to any item if no rarity filter (normal chest)
        const randomIndex = Math.floor(Math.random() * itemPool.length);
        selectedItem = itemPool[randomIndex];
      } else {
        // If rarity filter is set but no items of that rarity exist, break
        console.warn(`No items of rarity ${rarityFilter} available`);
        break;
      }

      // Sacred Orb: reroll Common items; 25% chance to reroll Uncommon
      if (selectedItem && typeof inventory !== 'undefined' && inventory.some(i => i.name === 'Sacred Orb')) {
        const r = (selectedItem.rarity || '').toLowerCase();
        if (r === 'common') { attempts++; continue; }
        if (r === 'uncommon' && Math.random() < 0.25) { attempts++; continue; }
      }

      // Check if this item is already in choices
      if (!choices.find(c => c.name === selectedItem.name)) {
        choices.push(selectedItem);
        break;
      }

      attempts++;
    }

    // If we couldn't find a unique item after max attempts, only add if pool is truly exhausted
    if (attempts >= maxAttempts && selectedItem) {
      const relevantPool = rarityFilter
        ? itemPool.filter(item => item.rarity && item.rarity.toLowerCase() === rarityFilter.toLowerCase())
        : itemPool;
      const poolExhausted = relevantPool.every(item => choices.find(c => c.name === item.name));
      if (poolExhausted) break; // Stop adding choices rather than show duplicates
    }
  }

  let itemsHTML = '<div style="display: flex; flex-wrap: wrap; gap: 20px; margin-top: 20px; justify-content: center;">';

  choices.forEach((item, index) => {
    // Case-insensitive rarity color matching
    const rarityLower = (item.rarity || '').toLowerCase();
    const rarityColor = rarityLower === 'legendary' ? '#ff6b00' : rarityLower === 'rare' ? '#9b59b6' : rarityLower === 'uncommon' ? '#4CAF50' : '#aaa';

    itemsHTML += `
      <div class="item-choice-card" data-index="${index}" style="
        flex: 1;
        max-width: 300px;
        padding: 20px;
        background: #2d2d2d;
        border: 3px solid ${rarityColor};
        border-radius: 12px;
        cursor: pointer;
        transition: all 0.3s;
        text-align: center;
      ">
        ${item.image ? `<img src="${item.image}" style="width: 130px; height: 130px; object-fit: contain; image-rendering: pixelated; margin: 0 auto 15px; display: block; border-radius: 8px; border: 2px solid ${rarityColor};" alt="${item.name}" onerror="this.style.display='none';">` : ''}
        <div style="font-size: 20px; font-weight: bold; margin-bottom: 10px;">${item.name}</div>
        <div style="color: ${rarityColor}; font-size: 14px; margin-bottom: 15px;">${item.rarity}</div>
        <div style="color: #ccc; font-size: 14px; line-height: 1.5;">${item.description}</div>
        <div style="color: #888; font-size: 12px; margin-top: 10px; font-style: italic;">${item.type}</div>
      </div>
    `;
  });

  itemsHTML += '</div>';
  itemsHTML += '<p style="text-align: center; color: #888; margin-top: 20px; font-size: 14px;">Click an item to choose it</p>';

  // Add Reroll and Skip buttons
  const rerollButtonHTML = `
    <div style="text-align: center; margin-top: 20px; display: flex; flex-wrap: wrap; gap: 15px; justify-content: center;">
      <button id="item-reroll-btn" ${reroll === 0 ? 'disabled' : ''} style="
        padding: 10px 24px;
        background: ${reroll > 0 ? '#ffcc66' : '#555'};
        border: 2px solid ${reroll > 0 ? '#ffdd77' : '#666'};
        border-radius: 8px;
        color: ${reroll > 0 ? '#333' : '#888'};
        cursor: ${reroll > 0 ? 'pointer' : 'not-allowed'};
        font-weight: bold;
        font-size: 14px;
        opacity: ${reroll > 0 ? '1' : '0.5'};
      ">
        🔄 Reroll Items (${reroll})
      </button>
      <button id="item-skip-btn" style="
        padding: 10px 24px;
        background: #666;
        border: 2px solid #888;
        border-radius: 8px;
        color: white;
        cursor: pointer;
        font-weight: bold;
        font-size: 14px;
      ">
        ⏭️ Skip (No Item)
      </button>
    </div>
    <p style="text-align: center; color: #888; margin-top: 10px; font-size: 12px;">Note: Skip does not use your Skip ability</p>
  `;

  createGameModal(`
    <div>
      <h2 style="color: #f39c12; margin-top: 0; text-align: center;">${chestTitle}</h2>
      <p style="text-align: center; color: #aaa;">Select one item to add to your inventory</p>
      ${itemsHTML}
      ${rerollButtonHTML}
    </div>
  `);

  document.querySelectorAll('.item-choice-card').forEach(card => {
    card.onmouseenter = (e) => {
      e.currentTarget.style.transform = 'translateY(-5px) scale(1.05)';
      e.currentTarget.style.boxShadow = '0 10px 30px rgba(204, 102, 0, 0.4)';
    };
    card.onmouseleave = (e) => {
      e.currentTarget.style.transform = '';
      e.currentTarget.style.boxShadow = '';
    };
    card.onclick = (e) => {
      if (e.currentTarget.dataset.picked) return;
      e.currentTarget.dataset.picked = '1';
      const itemIndex = parseInt(e.currentTarget.dataset.index);
      const item = choices[itemIndex];

      acquireItem(item);

      closeGameModal();

      // Set phase to selection so usable items become enabled
      gameState.phase = 'selection';
      if (typeof updateInventory === 'function') {
        updateInventory();
      }

      // Check and update curse durations after item selection
      // This ensures curse levels are current before moving to next path
      if (typeof checkCurseDurations === 'function') {
        checkCurseDurations('game_beaten');
      }

      // Update curse display to reflect any changes
      if (typeof updateCursesDisplay === 'function') {
        updateCursesDisplay();
      }
      if (typeof updateTopBar === 'function') {
        updateTopBar();
      }

      // Check if we need to offer a Risk of Rain 2 extra chest first
      if (gameState.pendingRoRExtraChest) {
        gameState.pendingRoRExtraChest = false;
        const afterRoR = () => {
          if (gameState.pendingHadesBoonSelection) {
            gameState.pendingHadesBoonSelection = false;
            if (typeof showHadesBoonSelection === 'function') showHadesBoonSelection();
          } else if (typeof onComplete === 'function') {
            onComplete();
          } else {
            spawnChoices();
          }
        };
        setTimeout(() => {
          if (typeof showRoRExtraChestOffer === 'function') showRoRExtraChestOffer(afterRoR);
          else afterRoR();
        }, 300);
      // Check if we need to show Hades boon selection first
      } else if (gameState.pendingHadesBoonSelection) {
        gameState.pendingHadesBoonSelection = false;
        setTimeout(() => {
          if (typeof showHadesBoonSelection === 'function') {
            showHadesBoonSelection();
          }
        }, 300);
      } else {
        // Normal flow: spawn the next choices or call callback
        if (typeof onComplete === 'function') {
          setTimeout(() => onComplete(), 300);
        } else {
          setTimeout(() => spawnChoices(), 300);
        }
      }
    };
  });

  // Add reroll button event listener
  const itemRerollBtn = document.getElementById('item-reroll-btn');
  if (itemRerollBtn && reroll > 0) {
    itemRerollBtn.onclick = () => {
      if (confirm('Reroll chest contents?')) {
        reroll--;
        closeGameModal();
        setTimeout(() => showItemChoiceModal(onComplete, chestType), 100);
      }
    };
  }

  // Add skip button event listener
  const itemSkipBtn = document.getElementById('item-skip-btn');
  if (itemSkipBtn) {
    itemSkipBtn.onclick = () => {
      closeGameModal();

      // Set phase to selection so usable items become enabled
      gameState.phase = 'selection';
      if (typeof updateInventory === 'function') {
        updateInventory();
      }

      // Check and update curse durations after skipping item selection
      // This ensures curse levels are current before moving to next path
      if (typeof checkCurseDurations === 'function') {
        checkCurseDurations('game_beaten');
      }

      // Update curse display to reflect any changes
      if (typeof updateCursesDisplay === 'function') {
        updateCursesDisplay();
      }
      if (typeof updateTopBar === 'function') {
        updateTopBar();
      }

      // Check if we need to offer a Risk of Rain 2 extra chest first
      if (gameState.pendingRoRExtraChest) {
        gameState.pendingRoRExtraChest = false;
        const afterRoR = () => {
          if (gameState.pendingHadesBoonSelection) {
            gameState.pendingHadesBoonSelection = false;
            if (typeof showHadesBoonSelection === 'function') showHadesBoonSelection();
          } else if (typeof onComplete === 'function') {
            onComplete();
          } else {
            spawnChoices();
          }
        };
        setTimeout(() => {
          if (typeof showRoRExtraChestOffer === 'function') showRoRExtraChestOffer(afterRoR);
          else afterRoR();
        }, 300);
      // Check if we need to show Hades boon selection first
      } else if (gameState.pendingHadesBoonSelection) {
        gameState.pendingHadesBoonSelection = false;
        setTimeout(() => {
          if (typeof showHadesBoonSelection === 'function') {
            showHadesBoonSelection();
          }
        }, 300);
      } else {
        // Normal flow: spawn choices without acquiring an item or call callback
        if (typeof onComplete === 'function') {
          setTimeout(() => onComplete(), 300);
        } else {
          setTimeout(() => spawnChoices(), 300);
        }
      }
    };
  }
}

// ===== CHEST SYSTEM ALIAS =====
// Alias function with clearer naming for "chest" system
function offerChest(chestType = 'normal', onComplete) {
  showItemChoiceModal(onComplete, chestType);
}

// Convenience function to offer a chest without callback (for item effects like Golden Beetle)
function offerItemReward(chestType = 'normal') {
  showItemChoiceModal(null, chestType);
}

// ===== GAME STATS TRACKING SYSTEM =====

/**

function markGameFinished(gameName) {
  if (!gameState.finishedGames) {
    gameState.finishedGames = [];
  }

  // Initialize totalGamesBeaten if it doesn't exist (backwards compatibility)
  if (typeof gameState.totalGamesBeaten !== 'number') {
    gameState.totalGamesBeaten = 0;
  }
  if (typeof gameState.insaneBatteryFills !== 'number') {
    gameState.insaneBatteryFills = 0;
  }

  // Log the state before increment for debugging

  // Increment beaten count (tracks all completions, even if player dies later)
  // NOTE: Amulet stat is only incremented on successful escape (in showVictoryScreen)
  incrementGameBeaten(gameName, false);

  // Increment total games beaten counter (counts ALL completions including duplicates)
  const previousDifficulty = getDifficultyTier(gameState.totalGamesBeaten);
  gameState.totalGamesBeaten++;
  const newDifficultyAfterIncrement = getDifficultyTier(gameState.totalGamesBeaten);

  // Reroller trait: Every time you beat a game, gain +1 Reroll
  if (hasTrait('reroller')) {
    reroll++;
    if (typeof updateTopBar === 'function') {
      updateTopBar();
    }
  }

  // Trigger onGameBeaten effects for items (like Unstable Genome)
  if (typeof triggerOnGameBeaten === 'function') {
    triggerOnGameBeaten();
  }

  // Only add if not already in finishedGames array (for unique tracking)
  if (!gameState.finishedGames.includes(gameName)) {
    gameState.finishedGames.push(gameName);
  } else {
    // Revisiting a game already beaten — award 1 Dash so the player can escape a dead end
    dash = (typeof dash !== 'undefined' ? dash : 0) + 1;
    gameState.dash = (gameState.dash || 0) + 1;
    if (typeof updateTopBar === 'function') updateTopBar();
    if (typeof createNotification === 'function') {
      createNotification('+1 Dash (revisited game)', '#3498db', '💨');
    }
  }

  // ---- Difficulty battery logic ----
  handleDifficultyBatteryFill(previousDifficulty, newDifficultyAfterIncrement);

  // Check if difficulty tier changed and update location (unless manually overridden via dev tools)
  if (!gameState.manualLocationOverride) {
    if (previousDifficulty !== newDifficultyAfterIncrement) {
      const newLocation = getRandomLocation(newDifficultyAfterIncrement);
      if (newLocation) {
        gameState.location = newLocation;
        if (typeof updateLocationDisplay === 'function') {
          updateLocationDisplay(gameState.currentGame);
        }
        if (newLocation.game === 'Hades') {
          gameState.pendingHadesBoonSelection = true;
        }
      }
    }
  }

  // Risk of Rain 2 location effect: 50% chance to accelerate difficulty + offer extra chest
  if (!gameState.manualLocationOverride && gameState.location &&
      typeof hasScalingReward === 'function' && hasScalingReward(gameState.location)) {
    const rorResult = applyRiskOfRainEffect(gameState.location);
    if (rorResult.difficultyIncreased) {
      const preRoR = getDifficultyTier(gameState.totalGamesBeaten);
      gameState.totalGamesBeaten++;
      const postRoR = getDifficultyTier(gameState.totalGamesBeaten);
      // Update battery for the RoR-triggered increment
      handleDifficultyBatteryFill(preRoR, postRoR);
      if (preRoR !== postRoR) {
        const escalatedLocation = getRandomLocation(postRoR);
        if (escalatedLocation) {
          gameState.location = escalatedLocation;
          if (typeof updateLocationDisplay === 'function') updateLocationDisplay(gameState.currentGame);
          if (escalatedLocation.game === 'Hades') gameState.pendingHadesBoonSelection = true;
        }
      }
      if (typeof createNotification === 'function') createNotification('Difficulty escalated! (Risk of Rain 2)', '#ff6600', '⬆️');
    }
    if (rorResult.offerExtraChest) gameState.pendingRoRExtraChest = true;
  }

  // Check and update curse durations
  checkCurseDurations('game_beaten');

  // Update curse UI to reflect new progress
  if (typeof updateCurseUI === 'function') {
    updateCurseUI();
  }

  updateGameStats();
  saveCurrentGame();
}

/**
 * Called after each totalGamesBeaten increment to handle battery fill events.
 * On a normal tier advance (Easy→Medium→Hard→Insane) the battery resets and shows
 * a tier-up notification. When already in Insane and the battery fills again,
 * it's an "overheat": escalating curses are applied and a hard combat is queued.
 */
function handleDifficultyBatteryFill(prevTier, newTier) {
  const tierSize = (typeof DIFFICULTY_TIER_SIZE !== 'undefined') ? DIFFICULTY_TIER_SIZE : 4;
  const filled = gameState.totalGamesBeaten % tierSize === 0 && gameState.totalGamesBeaten > 0;

  if (!filled) {
    // Battery gained a segment but didn't complete — just refresh the display
    if (typeof updateLocationDisplay === 'function') updateLocationDisplay(gameState.currentGame);
    return;
  }

  if (prevTier !== newTier) {
    // Normal tier advancement — battery empties as we enter the new tier
    const tierColors = { Easy: '#2ecc71', Medium: '#ff9800', Hard: '#f44336', Insane: '#aa44ff' };
    const color = tierColors[newTier] || '#aaa';
    if (typeof createNotification === 'function') {
      createNotification(`Difficulty increased: ${newTier}!`, color, '⚠️');
    }
  } else if (newTier === 'Insane') {
    // Insane overheat — battery filled without a tier change
    if (typeof gameState.insaneBatteryFills !== 'number') gameState.insaneBatteryFills = 0;
    gameState.insaneBatteryFills++;
    const curseCount = gameState.insaneBatteryFills;

    // Apply escalating curses
    const availableCurses = (typeof curses !== 'undefined')
      ? curses.filter(c => !gameState.activeCurses.some(ac => ac.name === c.name))
      : [];
    let cursesAdded = 0;
    for (let i = 0; i < curseCount && availableCurses.length > 0; i++) {
      const idx = Math.floor(Math.random() * availableCurses.length);
      const chosen = availableCurses.splice(idx, 1)[0];
      if (typeof addCurse === 'function') addCurse(chosen.name);
      cursesAdded++;
    }

    if (typeof createNotification === 'function') {
      createNotification(
        `OVERHEAT! +${cursesAdded} curse${cursesAdded !== 1 ? 's' : ''} — Hard combat incoming!`,
        '#cc00ff', '🔥'
      );
    }

    // Queue a hard combat encounter before the next set of choices
    gameState.pendingInsaneHardCombat = true;
  }

  if (typeof updateLocationDisplay === 'function') updateLocationDisplay(gameState.currentGame);
}

/**
 * Add a curse to the player (wrapper for StateMutator.addCurse)
 * Handles both curse objects and curse names (strings)
 * @param {Object|string} curseOrName - Curse object or curse name string
 * @returns {boolean} - Success status
 */
function addCurse(curseOrName) {
  // Extract curse name if an object was passed
  const curseName = typeof curseOrName === 'string' ? curseOrName : curseOrName.name;

  if (!curseName) {
    console.error('Invalid curse data:', curseOrName);
    return false;
  }

  // Use StateMutator to add the curse with UI updates
  return StateMutator.addCurse(curseName, { updateUI: true, notify: false });
}

/**
 * Get maximum uses for a curse based on its power level
 * @param {string} power - Power level ('High', 'Medium', 'Low')
 * @returns {number} - Maximum uses
 */
function getCurseMaxUses(power) {
  if (power === 'High') return 3;
  if (power === 'Medium') return 2;
  return 1; // Low or default
}

/**
 * Check and update curse durations after game events
 * @param {string} eventType - Type of event ('game_beaten', etc.)
 */
function checkCurseDurations(eventType = 'game_beaten') {
  if (!gameState || !gameState.activeCurses) return;

  // Initialize tracker if it doesn't exist
  if (!gameState.cursesTracker) {
    gameState.cursesTracker = {};
  }

  // Get list of restriction curses that were verified (from verification modal)
  const cursesToIncrement = gameState.restrictionCursesProcessed || [];

  // Track which curses to remove after iteration
  const cursesToRemove = [];

  // Process each active curse
  gameState.activeCurses.forEach(curse => {
    const trackerId = curse.id || curse.name;

    // Initialize tracker for this curse if it doesn't exist
    if (!gameState.cursesTracker[trackerId]) {
      gameState.cursesTracker[trackerId] = { gamesBeaten: 0 };
    }

    const tracker = gameState.cursesTracker[trackerId];

    // Check if this curse has a game-based duration
    let shouldIncrement = false;
    if (curse.duration && curse.duration.match(/(\d+)\s+game/i)) {
      // If it's a restriction curse, check if it was verified
      if (cursesToIncrement.includes(curse.id)) {
        shouldIncrement = true;
      }
      // If it's a manual curse (not in verification list), always increment
      else if (curse.automatic === 'Manual' || !curse.automatic) {
        shouldIncrement = true;
      }
    }

    // Increment the counter if needed
    if (shouldIncrement) {
      tracker.gamesBeaten = (tracker.gamesBeaten || 0) + 1;
    }

    // Check if curse duration is complete
    if (curse.duration) {
      const match = curse.duration.match(/(\d+)\s+game/i);
      if (match) {
        const requiredGames = parseInt(match[1]);
        if (tracker.gamesBeaten >= requiredGames) {
          cursesToRemove.push(curse);
        }
      }
    }
  });

  // Remove completed curses
  cursesToRemove.forEach(curse => {
    CurseManager.consume(curse);
    const trackerId = curse.id || curse.name;
    delete gameState.cursesTracker[trackerId];

    if (typeof createNotification === 'function') {
      createNotification(`${curse.name} duration complete!`, '#4CAF50', '✨');
    }
  });

  // Clear the processed list for next time
  gameState.restrictionCursesProcessed = [];

  // Update UI if curses were removed
  if (cursesToRemove.length > 0) {
    if (typeof updateActiveCursesList === 'function') {
      updateActiveCursesList();
    }
    if (typeof updateCursesDisplay === 'function') {
      updateCursesDisplay();
    }
  }
}

// ===== GAME STATUS EFFECTS SYSTEM =====

/**
 * Add a status effect to a game
 * @param {string} gameName - Name of the game
 * @param {string} statusName - Name of the status effect (e.g. 'stinky', 'portal')
 * @param {string} icon - Emoji icon for the status (optional, will be looked up if not provided)
 */
function addGameStatus(gameName, statusName, icon) {
  if (!gameState.gameStatusEffects) {
    gameState.gameStatusEffects = {};
  }

  if (!gameState.gameStatusEffects[gameName]) {
    gameState.gameStatusEffects[gameName] = [];
  }

  // Check if status already exists
  const existing = gameState.gameStatusEffects[gameName].find(s => s.name === statusName);
  if (existing) {
    return;
  }

  // Look up icon if not provided
  if (!icon) {
    const statusIcons = {
      'charmed': '💕',
      'devilish': '👹',
      'holy': '✨',
      'marked': '🎯',
      'portal': '🌀',
      'shielded': '🛡️',
      'shocked': '⚡',
      'soaked': '💧',
      'stinky': '💩',
      'timed': '⏱️'
    };
    icon = statusIcons[statusName.toLowerCase()] || '❓';
  }

  gameState.gameStatusEffects[gameName].push({
    name: statusName,
    icon: icon
  });


  // Refresh the display if we're looking at this game
  if (typeof updateGameDisplay === 'function') {
    updateGameDisplay();
  }
}

/**
 * Remove a status effect from a game
 * @param {string} gameName - Name of the game
 * @param {string} statusName - Name of the status effect to remove
 */
function removeGameStatus(gameName, statusName) {
  if (!gameState.gameStatusEffects || !gameState.gameStatusEffects[gameName]) {
    return;
  }

  const index = gameState.gameStatusEffects[gameName].findIndex(s => s.name === statusName);
  if (index !== -1) {
    gameState.gameStatusEffects[gameName].splice(index, 1);

    // Clean up empty arrays
    if (gameState.gameStatusEffects[gameName].length === 0) {
      delete gameState.gameStatusEffects[gameName];
    }

    // Refresh the display
    if (typeof updateGameDisplay === 'function') {
      updateGameDisplay();
    }
  }
}

/**
 * Check if a game has a specific status effect
 * @param {string} gameName - Name of the game
 * @param {string} statusName - Name of the status effect
 * @returns {boolean} - True if the game has the status
 */
function hasGameStatus(gameName, statusName) {
  if (!gameState.gameStatusEffects || !gameState.gameStatusEffects[gameName]) {
    return false;
  }

  return gameState.gameStatusEffects[gameName].some(s => s.name === statusName);
}

/**
 * Get all status effects for a game
 * @param {string} gameName - Name of the game
 * @returns {Array} - Array of status objects
 */
function getGameStatuses(gameName) {
  if (!gameState.gameStatusEffects || !gameState.gameStatusEffects[gameName]) {
    return [];
  }

  return gameState.gameStatusEffects[gameName];
}

/**
 * Get all games with a specific status
 * @param {string} statusName - Name of the status effect
 * @returns {Array} - Array of game names
 */
function getGamesWithStatus(statusName) {
  if (!gameState.gameStatusEffects) {
    return [];
  }

  const gamesWithStatus = [];
  for (const [gameName, statuses] of Object.entries(gameState.gameStatusEffects)) {
    if (statuses.some(s => s.name === statusName)) {
      gamesWithStatus.push(gameName);
    }
  }

  return gamesWithStatus;
}

/**
 * Trigger status effects when visiting a game
 * Status effects scale by difficulty: Low (0-4 games), Medium (5-9), High (10+)
 * @param {string} gameName - Name of the game being visited
 */
function triggerGameStatusEffects(gameName) {
  const statuses = getGameStatuses(gameName);
  if (!statuses || statuses.length === 0) return;

  // Calculate difficulty tier based on games beaten (same as combat)
  const gamesBeaten = gameState.totalGamesBeaten || 0;
  const _status_thresholds = (typeof DIFFICULTY_THRESHOLDS !== 'undefined') ? DIFFICULTY_THRESHOLDS : { MEDIUM: 4, HARD: 8, INSANE: 12 };
  let difficultyTier = 'Low';
  let curseSuffix = 'I';

  if (gamesBeaten >= _status_thresholds.HARD) {
    difficultyTier = 'High';
    curseSuffix = 'III';
  } else if (gamesBeaten >= _status_thresholds.MEDIUM) {
    difficultyTier = 'Medium';
    curseSuffix = 'II';
  }


  // Process each status effect
  statuses.forEach(status => {
    let message = '';
    let isPositive = false;

    switch(status.name.toLowerCase()) {
      case 'charmed':
        // Give Curse of Affection scaled by difficulty
        const affectionCurseName = `Curse of Affection ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const affectionCurse = CURSES_DATA.find(c => c.name === affectionCurseName);
          if (affectionCurse && typeof addCurse === 'function') {
            addCurse(affectionCurse);
            message = `${status.icon} Charmed! Gained ${affectionCurseName}`;
          }
        }
        break;

      case 'devilish':
        // Lose 2 health
        health = Math.max(0, health - 2);
        gameState.health = health;
        message = `${status.icon} Devilish aura deals 2 damage!`;
        break;

      case 'holy':
        // Gain 2 health
        const oldHealth = health;
        health = Math.min(health + 2, maxHealth);
        gameState.health = health;
        message = `${status.icon} Holy blessing restores ${health - oldHealth} health!`;
        isPositive = true;
        break;

      case 'marked':
        // Give Curse of the Hunter scaled by difficulty
        const hunterCurseName = `Curse of the Hunter ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const hunterCurse = CURSES_DATA.find(c => c.name === hunterCurseName);
          if (hunterCurse && typeof addCurse === 'function') {
            addCurse(hunterCurse);
            message = `${status.icon} Marked! Gained ${hunterCurseName}`;
          }
        }
        break;

      case 'portal':
        // Portal is handled by exploration.js, no trigger effect
        break;

      case 'shielded':
        // Give Curse of Obstruction scaled by difficulty
        const obstructionCurseName = `Curse of Obstruction ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const obstructionCurse = CURSES_DATA.find(c => c.name === obstructionCurseName);
          if (obstructionCurse && typeof addCurse === 'function') {
            addCurse(obstructionCurse);
            message = `${status.icon} Shielded! Gained ${obstructionCurseName}`;
          }
        }
        break;

      case 'shocked':
        // Give Curse of the Dazed scaled by difficulty
        const dazedCurseName = `Curse of the Dazed ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const dazedCurse = CURSES_DATA.find(c => c.name === dazedCurseName);
          if (dazedCurse && typeof addCurse === 'function') {
            addCurse(dazedCurse);
            message = `${status.icon} Shocked! Gained ${dazedCurseName}`;
          }
        }
        break;

      case 'soaked':
        // Give Curse of the Damp scaled by difficulty
        const dampCurseName = `Curse of the Damp ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const dampCurse = CURSES_DATA.find(c => c.name === dampCurseName);
          if (dampCurse && typeof addCurse === 'function') {
            addCurse(dampCurse);
            message = `${status.icon} Soaked! Gained ${dampCurseName}`;
          }
        }
        break;

      case 'stinky':
        // Stinky is handled by exploration.js, no trigger effect
        break;

      case 'timed':
        // Give Curse of Haste scaled by difficulty
        const hasteCurseName = `Curse of Haste ${curseSuffix}`;
        if (typeof CURSES_DATA !== 'undefined') {
          const hasteCurse = CURSES_DATA.find(c => c.name === hasteCurseName);
          if (hasteCurse && typeof addCurse === 'function') {
            addCurse(hasteCurse);
            message = `${status.icon} Timed! Gained ${hasteCurseName}`;
          }
        }
        break;
    }

    if (message) {
      showNotification(message, isPositive ? 'positive' : 'negative');
    }
  });

  // Update top bar to reflect health/curse changes
  if (typeof updateTopBar === 'function') {
    updateTopBar();
  }

  // Check for death
  if (health <= 0) {
    health = 0;
    gameState.health = 0;
    if (typeof handleDeath === 'function') {
      handleDeath('status effect');
    }
  }
}

/**
 * Show a notification message to the player
 * @param {string} message - The message to display
 * @param {string} type - 'positive' or 'negative' for styling
 */
function showNotification(message, type = 'neutral') {
  // Create notification element
  const notification = document.createElement('div');
  notification.className = `status-notification ${type}`;
  notification.textContent = message;
  notification.style.cssText = `
    position: fixed;
    top: 100px;
    left: 50%;
    transform: translateX(-50%);
    background: ${type === 'positive' ? 'rgba(76, 175, 80, 0.95)' : type === 'negative' ? 'rgba(244, 67, 54, 0.95)' : 'rgba(33, 33, 33, 0.95)'};
    color: white;
    padding: 12px 24px;
    border-radius: 8px;
    font-size: 16px;
    font-weight: bold;
    z-index: 10000;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    animation: notificationSlide 3s ease-in-out;
    pointer-events: none;
  `;

  document.body.appendChild(notification);

  // Remove after animation
  setTimeout(() => {
    notification.remove();
  }, 3000);
}

// Add notification animation to CSS (if not already present)
if (!document.querySelector('#notification-animation-style')) {
  const style = document.createElement('style');
  style.id = 'notification-animation-style';
  style.textContent = `
    @keyframes notificationSlide {
      0% {
        opacity: 0;
        transform: translateX(-50%) translateY(-20px);
      }
      10% {
        opacity: 1;
        transform: translateX(-50%) translateY(0);
      }
      90% {
        opacity: 1;
        transform: translateX(-50%) translateY(0);
      }
      100% {
        opacity: 0;
        transform: translateX(-50%) translateY(-20px);
      }
    }
  `;
  document.head.appendChild(style);
}

// ===== DEV TOOLS EVENT LISTENERS =====

// Item Add/Remove
document.getElementById('giveSelectedItem')?.addEventListener('click', () => {
  const itemSelect = document.getElementById('itemSelect');
  const itemName = itemSelect?.value;

  if (!itemName) {
    alert('Please select an item');
    return;
  }

  const item = items.find(i => i.name === itemName);
  if (!item) {
    alert('Item not found');
    return;
  }

  if (typeof acquireItem === 'function') {
    acquireItem(item);
  }

  const output = document.getElementById('output3');
  if (output) {
    output.textContent = `Added: ${itemName}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }
});

document.getElementById('pickRandomItem')?.addEventListener('click', () => {
  if (!items || items.length === 0) {
    alert('No items available');
    return;
  }

  const randomItem = items[Math.floor(Math.random() * items.length)];

  if (typeof acquireItem === 'function') {
    acquireItem(randomItem);
  }

  const output = document.getElementById('output3');
  if (output) {
    output.textContent = `Added: ${randomItem.name}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }
});

document.getElementById('removeSelectedItem')?.addEventListener('click', () => {
  const removeItemSelect = document.getElementById('removeItemSelect');
  const itemIndex = parseInt(removeItemSelect?.value);

  if (isNaN(itemIndex) || itemIndex < 0) {
    alert('Please select an item to remove');
    return;
  }

  if (!inventory || itemIndex >= inventory.length) {
    alert('Invalid item selection');
    return;
  }

  const removed = inventory.splice(itemIndex, 1)[0];

  if (typeof updateInventory === 'function') {
    updateInventory();
  }

  const output = document.getElementById('removedItemOutput');
  if (output) {
    output.textContent = `Removed: ${removed.name}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }
});

document.getElementById('removeRandomItem')?.addEventListener('click', () => {
  if (!inventory || inventory.length === 0) {
    alert('No items to remove');
    return;
  }

  const randomIndex = Math.floor(Math.random() * inventory.length);
  const removed = inventory.splice(randomIndex, 1)[0];

  if (typeof updateInventory === 'function') {
    updateInventory();
  }

  const output = document.getElementById('removedItemOutput');
  if (output) {
    output.textContent = `Removed: ${removed.name}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }
});

// Curse Add/Remove
document.getElementById('addSelectedCurse')?.addEventListener('click', () => {
  const curseSelect = document.getElementById('curseSelect');
  const curseName = curseSelect?.value;

  if (!curseName) {
    alert('Please select a curse');
    return;
  }

  const curseData = CURSES_DATA.find(c => c.name === curseName);
  if (!curseData) {
    alert('Curse not found');
    return;
  }

  // Use addCurse helper to handle Vulnerability
  const added = addCurse(curseData);

  const output = document.getElementById('curseAddOutput');
  if (output) {
    output.textContent = added ? `Added: ${curseName}` : `Curse already active: ${curseName}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }
});

document.getElementById('addRandomCurse')?.addEventListener('click', () => {
  if (!CURSES_DATA || CURSES_DATA.length === 0) {
    alert('No curses available');
    return;
  }

  const randomCurse = CURSES_DATA[Math.floor(Math.random() * CURSES_DATA.length)];

  // Use addCurse helper to handle Vulnerability
  const added = addCurse(randomCurse);

  const output = document.getElementById('curseAddOutput');
  if (output) {
    output.textContent = added ? `Added: ${randomCurse.name}` : `Curse already active: ${randomCurse.name}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }
});

document.getElementById('removeSelectedCurse')?.addEventListener('click', () => {
  const removeCurseSelect = document.getElementById('removeCurseSelect');
  const curseIndex = parseInt(removeCurseSelect?.value);

  if (isNaN(curseIndex) || curseIndex < 0) {
    alert('Please select a curse to remove');
    return;
  }

  if (!gameState.activeCurses || curseIndex >= gameState.activeCurses.length) {
    alert('Invalid curse selection');
    return;
  }

  const removed = gameState.activeCurses.splice(curseIndex, 1)[0];

  // Trigger onCurseRemoved effects for triggered items (like Golden Beetle)
  if (typeof triggerOnCurseRemoved === 'function') {
    triggerOnCurseRemoved();
  }

  updateActiveCursesList();
  if (typeof updateCursesDisplay === 'function') {
    updateCursesDisplay();
  }

  const output = document.getElementById('curseRemoveOutput');
  if (output) {
    output.textContent = `Removed: ${removed.name}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }
});

document.getElementById('clearAllCurses')?.addEventListener('click', () => {
  if (!gameState.activeCurses || gameState.activeCurses.length === 0) {
    alert('No curses to clear');
    return;
  }

  if (confirm('Remove all curses?')) {
    gameState.activeCurses = [];
    updateActiveCursesList();
    if (typeof updateCursesDisplay === 'function') {
      updateCursesDisplay();
    }

    const output = document.getElementById('curseRemoveOutput');
    if (output) {
      output.textContent = 'All curses cleared';
      output.style.display = 'block';
      setTimeout(() => { output.style.display = 'none'; }, 2000);
    }
  }
});

// Quick Actions
document.getElementById('triggerShop')?.addEventListener('click', () => {
  if (!gameState || !gameState.gameStarted) {
    alert('Please start a run first');
    return;
  }

  if (typeof showShopModal === 'function') {
    showShopModal();
  } else {
    alert('Shop system not available');
  }
});

document.getElementById('triggerItemChoice')?.addEventListener('click', () => {
  if (!gameState || !gameState.gameStarted) {
    alert('Please start a run first');
    return;
  }

  if (typeof showItemChoiceModal === 'function') {
    showItemChoiceModal();
  } else {
    alert('Item choice system not available');
  }
});

// Event Triggers
document.getElementById('triggerSelectedEvent')?.addEventListener('click', () => {
  const eventSelect = document.getElementById('eventSelect');
  const eventName = eventSelect?.value;

  if (!eventName) {
    alert('Please select an event');
    return;
  }

  if (typeof showEventModal === 'function') {
    showEventModal(eventName);
  } else {
    alert('Event system not available');
  }
});

document.getElementById('checkEvent')?.addEventListener('click', () => {
  if (!gameState || !gameState.gameStarted) {
    alert('Please start a run first to use Random Event');
    return;
  }

  if (events.length === 0) {
    alert('No events available');
    return;
  }

  if (typeof showEventModal === 'function') {
    showEventModal();
  } else {
    alert('Event system not available');
  }
});

// Game Status Effects Dev Tools
document.getElementById('addGameStatus')?.addEventListener('click', () => {
  const gameSelect = document.getElementById('statusGameSelect');
  const statusSelect = document.getElementById('statusEffectType');
  const gameName = gameSelect?.value;
  const statusType = statusSelect?.value;

  if (!gameName) {
    alert('Please select a game');
    return;
  }

  if (!statusType) {
    alert('Please select a status effect');
    return;
  }

  // Map status type to icon
  const statusIcons = {
    'charmed': '💕',
    'devilish': '👹',
    'holy': '✨',
    'marked': '🎯',
    'portal': '🌀',
    'shielded': '🛡️',
    'shocked': '⚡',
    'soaked': '💧',
    'stinky': '💩',
    'timed': '⏱️'
  };

  const icon = statusIcons[statusType] || '❓';
  addGameStatus(gameName, statusType, icon);

  const output = document.getElementById('statusOutput');
  if (output) {
    output.textContent = `Added ${icon} ${statusType} to ${gameName}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }

  // Refresh the node display
  if (typeof updateNodeStatusIcons === 'function') {
    const nodes = document.querySelectorAll('.node');
    nodes.forEach(node => {
      const nodeGameName = node.textContent.replace(/[^\w\s:'-]/g, '').trim();
      if (nodeGameName === gameName) {
        updateNodeStatusIcons(node);
      }
    });
  }
});

document.getElementById('removeGameStatus')?.addEventListener('click', () => {
  const gameSelect = document.getElementById('statusGameSelect');
  const statusSelect = document.getElementById('statusEffectType');
  const gameName = gameSelect?.value;
  const statusType = statusSelect?.value;

  if (!gameName) {
    alert('Please select a game');
    return;
  }

  if (!statusType) {
    alert('Please select a status effect');
    return;
  }

  removeGameStatus(gameName, statusType);

  const output = document.getElementById('statusOutput');
  if (output) {
    output.textContent = `Removed ${statusType} from ${gameName}`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }

  // Refresh the node display
  if (typeof updateNodeStatusIcons === 'function') {
    const nodes = document.querySelectorAll('.node');
    nodes.forEach(node => {
      const nodeGameName = node.textContent.replace(/[^\w\s:'-]/g, '').trim();
      if (nodeGameName === gameName) {
        updateNodeStatusIcons(node);
      }
    });
  }
});

document.getElementById('clearAllStatuses')?.addEventListener('click', () => {
  if (confirm('Clear all status effects from all games?')) {
    if (gameState.gameStatusEffects) {
      gameState.gameStatusEffects = {};
    }

    const output = document.getElementById('statusOutput');
    if (output) {
      output.textContent = 'Cleared all status effects';
      output.style.display = 'block';
      setTimeout(() => { output.style.display = 'none'; }, 2000);
    }

    // Refresh all node displays
    if (typeof updateNodeStatusIcons === 'function') {
      const nodes = document.querySelectorAll('.node');
      nodes.forEach(node => updateNodeStatusIcons(node));
    }
  }
});

// Space Movement Dev Tools
document.getElementById('teleportToSelected')?.addEventListener('click', () => {
  if (!gameState || !gameState.gameStarted) {
    alert('Please start a run first');
    return;
  }

  const spaceSelect = document.getElementById('spaceSelect');
  const gameName = spaceSelect?.value;

  if (!gameName) {
    alert('Please select a game');
    return;
  }

  // Find the game to verify it exists
  const game = games.find(g => g.name === gameName);
  if (!game) {
    alert('Game not found');
    return;
  }

  // Teleport to the selected game (no encounter)
  const x = 450; // Center position
  const y = gameState.currentY + 200;

  if (typeof advance === 'function') {
    advance(gameName, x, y, null);

    const output = document.getElementById('teleportOutput');
    if (output) {
      output.textContent = `Teleported to ${gameName}`;
      output.style.display = 'block';
      setTimeout(() => { output.style.display = 'none'; }, 2000);
    }
  } else {
    alert('Teleport function not available');
  }
});

document.getElementById('teleportToRandom')?.addEventListener('click', () => {
  if (!gameState || !gameState.gameStarted) {
    alert('Please start a run first');
    return;
  }

  if (!games || games.length === 0) {
    alert('No games available');
    return;
  }

  // Pick a random game excluding current game
  const availableGames = games.filter(g => g.name !== gameState.currentGame);

  if (availableGames.length === 0) {
    alert('No other games available');
    return;
  }

  const randomGame = availableGames[Math.floor(Math.random() * availableGames.length)];

  // Teleport to the random game (no encounter)
  const x = 450; // Center position
  const y = gameState.currentY + 200;

  if (typeof advance === 'function') {
    advance(randomGame.name, x, y, null);

    const output = document.getElementById('teleportOutput');
    if (output) {
      output.textContent = `Teleported to ${randomGame.name}`;
      output.style.display = 'block';
      setTimeout(() => { output.style.display = 'none'; }, 2000);
    }
  } else {
    alert('Teleport function not available');
  }
});

// Difficulty-Based Locations Dev Tools
document.getElementById('setSelectedLocation')?.addEventListener('click', () => {
  if (!gameState || !gameState.gameStarted) {
    alert('Please start a run first');
    return;
  }

  const locationSelect = document.getElementById('difficultyLocationSelect');
  const locationIndex = parseInt(locationSelect?.value);

  if (isNaN(locationIndex) || locationIndex < 0) {
    alert('Please select a location');
    return;
  }

  if (!LOCATIONS_DATA || locationIndex >= LOCATIONS_DATA.length) {
    alert('Invalid location selection');
    return;
  }

  const selectedLocation = LOCATIONS_DATA[locationIndex];

  // Set the location and enable manual override flag
  gameState.location = selectedLocation;
  gameState.manualLocationOverride = true;

  // Update the location display if the function exists
  if (typeof updateLocationDisplay === 'function') {
    updateLocationDisplay(selectedLocation);
  }

  // Update the current location display in dev tools
  if (typeof updateCurrentLocationDisplay === 'function') {
    updateCurrentLocationDisplay();
  }

  const output = document.getElementById('locationOutput');
  if (output) {
    output.textContent = `Location set to ${selectedLocation.name} (auto-change disabled)`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }

});

document.getElementById('setRandomLocation')?.addEventListener('click', () => {
  if (!gameState || !gameState.gameStarted) {
    alert('Please start a run first');
    return;
  }

  if (!LOCATIONS_DATA || LOCATIONS_DATA.length === 0) {
    alert('No locations available');
    return;
  }

  // Pick a random location
  const randomLocation = LOCATIONS_DATA[Math.floor(Math.random() * LOCATIONS_DATA.length)];

  // Set the location and enable manual override flag
  gameState.location = randomLocation;
  gameState.manualLocationOverride = true;

  // Update the location display if the function exists
  if (typeof updateLocationDisplay === 'function') {
    updateLocationDisplay(randomLocation);
  }

  // Update the current location display in dev tools
  if (typeof updateCurrentLocationDisplay === 'function') {
    updateCurrentLocationDisplay();
  }

  const output = document.getElementById('locationOutput');
  if (output) {
    output.textContent = `Location set to ${randomLocation.name} (auto-change disabled)`;
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }

});

document.getElementById('enableAutoLocationChange')?.addEventListener('click', () => {
  if (!gameState) {
    alert('No game state available');
    return;
  }

  // Clear the manual override flag
  gameState.manualLocationOverride = false;

  const output = document.getElementById('locationOutput');
  if (output) {
    output.textContent = 'Auto location change enabled';
    output.style.display = 'block';
    setTimeout(() => { output.style.display = 'none'; }, 2000);
  }

});

// Specific Enemy Selection
document.getElementById('triggerSpecificEnemy')?.addEventListener('click', () => {
  const enemySelect = document.getElementById('specificEnemySelect');
  const enemyIndex = parseInt(enemySelect?.value);

  if (isNaN(enemyIndex) || enemyIndex < 0) {
    alert('Please select an enemy');
    return;
  }

  if (!enemies || enemyIndex >= enemies.length) {
    alert('Invalid enemy selection');
    return;
  }

  if (!gameState || !gameState.gameStarted) {
    alert('Please start a run first');
    return;
  }

  const enemy = enemies[enemyIndex];

  if (typeof showCombatModal === 'function') {
    showCombatModal(enemy);
  } else {
    alert('Combat system not available');
  }
});

// Export to global scope
window.getPowerValue = getPowerValue;
window.updateCurseUI = updateCurseUI;
window.loadState = loadState;
window.saveCurrentGame = saveCurrentGame;
window.loadSavedGame = loadSavedGame;
window.showCombatModal = showCombatModal;
window.showEventModal = showEventModal;
window.showShopModal = showShopModal;
window.leaveShop = leaveShop;
window.handleEventChoice = handleEventChoice;
window.showItemChoiceModal = showItemChoiceModal;
window.offerChest = offerChest; // Modern "chest" terminology
window.offerItemReward = offerItemReward; // For backward compatibility and item effects
window.markGameFinished = markGameFinished;
window.checkCurseDurations = checkCurseDurations;
window.addGameStatus = addGameStatus;
window.removeGameStatus = removeGameStatus;
window.hasGameStatus = hasGameStatus;
window.getGameStatuses = getGameStatuses;
window.getGamesWithStatus = getGamesWithStatus;
window.triggerGameStatusEffects = triggerGameStatusEffects;
window.getGameStatuses = getGameStatuses;
window.updateActiveCursesList = updateActiveCursesList;
window.addCurse = addCurse;
window.getCurseMaxUses = getCurseMaxUses;
window.getGamesWithStatus = getGamesWithStatus;
window.showPerfectGameVerificationModal = showPerfectGameVerificationModal;
// Event handlers
window.handleStoneGolemResult = handleStoneGolemResult;
window.triggerCombat = triggerCombat;
window.handleGenericCombatResult = handleGenericCombatResult;
window.showColosseumChoices = showColosseumChoices;
window.handleChampionResult = handleChampionResult;
window.completeChampionSuccess = completeChampionSuccess;
window.completeChampionFailure = completeChampionFailure;
window.showMapModal = showMapModal;
window.showMapTooltip = showMapTooltip;
window.moveMapTooltip = moveMapTooltip;
window.hideMapTooltip = hideMapTooltip;
window.drawMapArrows = drawMapArrows;

// ============== CARD NAME TOOLTIP ==============
// Lightweight floating card preview shown on hovering card names.

(function() {
  let _tooltipEl = null;

  function _getTooltipEl() {
    if (!_tooltipEl) {
      _tooltipEl = document.createElement('div');
      _tooltipEl.id = 'card-name-tooltip';
      _tooltipEl.style.cssText = [
        'position:fixed','z-index:99999','pointer-events:none',
        'display:none','background:#1a1a2e',
        'border-radius:10px','box-shadow:0 6px 24px rgba(0,0,0,0.8)',
        'overflow:hidden','width:160px',
      ].join(';');
      document.body.appendChild(_tooltipEl);
    }
    return _tooltipEl;
  }

  window.showCardNameTooltip = function(cardName, event) {
    const card = typeof CARDS_DATA !== 'undefined'
      ? CARDS_DATA.find(c => c.name === cardName || c.name.toLowerCase() === cardName.toLowerCase())
      : null;
    if (!card) return;

    const rc = card.rarity === 'Rare' ? '#9b59b6' : card.rarity === 'Uncommon' ? '#4CAF50' : card.rarity === 'Common' ? '#aaa' : '#888';
    const tc = (card.type||'').toLowerCase()==='attack' ? '#e74c3c'
             : (card.type||'').toLowerCase()==='skill'  ? '#2980b9'
             : (card.type||'').toLowerCase()==='power'  ? '#8e44ad'
             : (card.type||'').toLowerCase()==='dice'   ? '#d35400' : '#888';
    const imgSrc = card.imageUrl || '';
    const _tipTypeEmoji = {attack:'⚔',skill:'🛡',power:'✨',dice:'🎲',training:'📖'}[(card.type||'').toLowerCase()] || '🃏';

    const el = _getTooltipEl();
    el.style.border = '2px solid ' + rc;
    el.innerHTML = `
      <div style="position:relative;">
        <div style="position:absolute;top:5px;left:5px;width:20px;height:20px;border-radius:50%;background:${tc};border:2px solid rgba(255,255,255,0.3);display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:bold;color:white;z-index:2;">${card.cost !== null && card.cost !== undefined ? card.cost : '?'}</div>
        ${imgSrc
          ? `<img src="${imgSrc}" style="width:100%;height:120px;object-fit:contain;background:rgba(0,0,0,0.4);display:block;" onerror="this.style.display='none'">`
          : `<div style="width:100%;height:120px;display:flex;align-items:center;justify-content:center;font-size:36px;background:rgba(0,0,0,0.3);">${_tipTypeEmoji}</div>`}
      </div>
      <div style="padding:8px;">
        <div style="font-size:12px;font-weight:bold;color:#eee;margin-bottom:3px;">${card.name}</div>
        <div style="font-size:9px;color:${tc};text-transform:uppercase;font-weight:bold;margin-bottom:2px;">${card.type||''} · <span style="color:${rc}">${card.rarity||''}</span></div>
        <div style="font-size:10px;color:#ccc;line-height:1.4;">${card.description||''}</div>
      </div>
    `;

    el.style.display = 'block';
    const rect = event.target.getBoundingClientRect();
    const vpW = window.innerWidth, vpH = window.innerHeight;
    let left = rect.right + 8;
    let top = rect.top;
    if (left + 160 > vpW) left = rect.left - 168;
    if (top + 220 > vpH) top = vpH - 228;
    el.style.left = left + 'px';
    el.style.top = Math.max(4, top) + 'px';
  };

  window.hideCardNameTooltip = function() {
    const el = _getTooltipEl();
    el.style.display = 'none';
  };
})();

window.showStartingItemTip = function(el, event) {
  const name  = el.dataset.itemName  || '';
  const img   = el.dataset.itemImg   || '';
  const desc  = el.dataset.itemDesc  || '';
  const type  = el.dataset.itemType  || '';
  const ref   = el.dataset.itemRef   || '';
  const color = el.dataset.itemColor || '#888';

  let tip = document.getElementById('starting-item-tip');
  if (!tip) {
    tip = document.createElement('div');
    tip.id = 'starting-item-tip';
    tip.style.cssText = 'position:fixed;z-index:9000;pointer-events:none;background:linear-gradient(145deg,rgba(20,20,30,0.97),rgba(15,15,25,0.97));border-radius:8px;padding:12px 14px;max-width:260px;box-shadow:0 4px 20px rgba(0,0,0,0.8);font-family:Georgia,serif;font-size:12px;color:#e6d5b8;display:none;';
    document.body.appendChild(tip);
  }
  tip.style.border = '2px solid ' + color;
  tip.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
      ${img ? `<img src="${img}" style="width:36px;height:36px;object-fit:contain;flex-shrink:0;image-rendering:pixelated;" onerror="this.style.display='none'">` : ''}
      <div>
        <div style="font-weight:bold;font-size:13px;color:white;">${name}</div>
        ${type ? `<div style="font-size:10px;color:${color};text-transform:uppercase;font-weight:bold;">${type}${ref ? ' · ' + ref : ''}</div>` : ''}
      </div>
    </div>
    ${desc ? `<div style="color:#ccc;font-size:11px;line-height:1.5;">${desc}</div>` : ''}
  `;
  const r = el.getBoundingClientRect();
  const tx = Math.min(r.right + 8, window.innerWidth - 270);
  const ty = Math.min(r.top, window.innerHeight - 200);
  tip.style.left = tx + 'px';
  tip.style.top  = ty + 'px';
  tip.style.display = 'block';
};

window.hideStartingItemTip = function() {
  const tip = document.getElementById('starting-item-tip');
  if (tip) tip.style.display = 'none';
};

window.getEnemyStats = getEnemyStats;
window.recordEnemyDefeated = recordEnemyDefeated;
window.recordPlayerKilledBy = recordPlayerKilledBy;
// Bingo functions
window.generateBingoGrid = generateBingoGrid;
window.renderBingoGrid = renderBingoGrid;
window.toggleBingoCell = toggleBingoCell;
window.checkForBingo = checkForBingo;
window.updateBingoStatus = updateBingoStatus;
window.grantBingoReward = grantBingoReward;
window.giveRandomItems = giveRandomItems;
window.showBingoRewards = showBingoRewards;
window.toggleBingo = toggleBingo;

// ===== CHARACTER & TRAIT FUNCTIONS =====

function updateCharacterUI() {
  if (!gameState || !gameState.character) return;

  const character = PLAYER_CHARACTERS[gameState.character];
  if (!character) return;

  // Update character icon (use fullImage for UI display)
  const iconEl = document.getElementById('character-icon');
  if (iconEl) {
    iconEl.src = character.fullImage || character.icon;
    iconEl.alt = character.name;
  }

  // Update character name in header (with level)
  const statsCharacterNameEl = document.getElementById('stats-character-name');
  if (statsCharacterNameEl) {
    const level = gameState.playerLevel || 1;
    statsCharacterNameEl.innerHTML = `${character.name} <span style="color: #ff9800; font-size: 14px;">Lv.${level}</span>`;
  }
}

function updateTraitsDisplay() {
  const traitsList = document.getElementById('traits-list');
  if (!traitsList) return;

  const traits = gameState?.traits || [];
  if (traits.length === 0) {
    traitsList.innerHTML = '<div style="color: #888; font-style: italic; text-align: center; padding: 5px;">No traits</div>';
    return;
  }

  traitsList.innerHTML = '';
  traits.forEach(traitId => {
    const trait = TRAITS_DATA[traitId];
    if (!trait) return;

    const traitDiv = document.createElement('div');
    traitDiv.className = 'trait-item';
    traitDiv.style.cssText = 'padding: 8px; margin: 5px 0; background: rgba(204, 153, 0, 0.15); border: 1px solid #cc9900; border-radius: 6px; cursor: help; position: relative;';
    traitDiv.innerHTML = `
      <div style="display: flex; align-items: center; gap: 8px;">
        <span style="font-size: 18px;">${trait.icon}</span>
        <span style="color: #cc9900; font-weight: bold; font-size: 13px;">${trait.name}</span>
      </div>
    `;

    // Add tooltip
    traitDiv.setAttribute('data-tooltip', trait.description);

    // Hover effect for tooltip
    traitDiv.onmouseenter = function(e) {
      const tooltip = document.createElement('div');
      tooltip.id = 'trait-tooltip';
      tooltip.style.cssText = 'position: fixed; background: #2a2420; color: #e6d5b8; padding: 10px; border: 2px solid #cc9900; border-radius: 6px; font-size: 12px; z-index: 10000; max-width: 250px; pointer-events: none;';
      tooltip.textContent = trait.description;
      document.body.appendChild(tooltip);

      const rect = e.currentTarget.getBoundingClientRect();
      tooltip.style.left = (rect.right + 10) + 'px';
      tooltip.style.top = rect.top + 'px';
    };

    traitDiv.onmouseleave = function() {
      const tooltip = document.getElementById('trait-tooltip');
      if (tooltip) tooltip.remove();
    };

    traitsList.appendChild(traitDiv);
  });
}

// Check if player has a specific trait
function hasTrait(traitId) {
  return gameState?.traits?.includes(traitId) || false;
}

// Export character and trait functions
window.updateCharacterUI = updateCharacterUI;
window.updateTraitsDisplay = updateTraitsDisplay;
window.hasTrait = hasTrait;

// ===== INVENTORY SORTING EVENT LISTENERS =====

// Set up inventory sort button event listeners
document.addEventListener('DOMContentLoaded', () => {
  const sortAlphaBtn = document.getElementById('sort-alpha-btn');
  const sortRarityBtn = document.getElementById('sort-rarity-btn');
  const sortTypeBtn = document.getElementById('sort-type-btn');

  function updateSortButtons(activeBtn) {
    [sortAlphaBtn, sortRarityBtn, sortTypeBtn].forEach(btn => {
      if (btn === activeBtn) {
        btn.style.background = '#4CAF50';
        btn.style.borderColor = '#66bb6a';
      } else {
        btn.style.background = '#555';
        btn.style.borderColor = '#666';
      }
    });
  }

  if (sortAlphaBtn) {
    sortAlphaBtn.addEventListener('click', () => {
      window.inventorySortMode = 'alphabetical';
      updateSortButtons(sortAlphaBtn);
      if (typeof window.updateInventory === 'function') {
        window.updateInventory();
      } else {
        console.error('updateInventory not found');
      }
    });
  } else {
    console.error('sort-alpha-btn not found in DOM');
  }

  if (sortRarityBtn) {
    sortRarityBtn.addEventListener('click', () => {
      window.inventorySortMode = 'rarity';
      updateSortButtons(sortRarityBtn);
      if (typeof window.updateInventory === 'function') {
        window.updateInventory();
      } else {
        console.error('updateInventory not found');
      }
    });
  } else {
    console.error('sort-rarity-btn not found in DOM');
  }

  if (sortTypeBtn) {
    sortTypeBtn.addEventListener('click', () => {
      window.inventorySortMode = 'type';
      updateSortButtons(sortTypeBtn);
      if (typeof window.updateInventory === 'function') {
        window.updateInventory();
      } else {
        console.error('updateInventory not found');
      }
    });
  } else {
    console.error('sort-type-btn not found in DOM');
  }
});
