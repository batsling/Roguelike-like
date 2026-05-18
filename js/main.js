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
    StateMutator.restoreState({
      gold: state.gold ?? 0,
      maxHealth: state.maxHealth ?? 10,
      health: state.health,
    });
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

  if (gameState) gameState.rations = save.rations || 10;
  inventory = [...(save.inventory || [])];
  beatenGames = [...(save.beatenGames || [])];
  StateMutator.restoreState({
    maxHealth: save.maxHealth,
    health: save.health,
    gold: save.gold,
    strength: save.strength,
    dexterity: save.dexterity,
    intelligence: save.intelligence,
    charisma: save.charisma,
    reroll: save.reroll,
    dash: save.dash,
    skip: save.skip,
    discovery: save.discovery,
  });

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


// Character/start-selection flow (bfsAllDistances, runStartProgression,
// applyStartingBonus, completeGameStart, showStartingChoiceModal, plus the
// preview / confirm / back flow) moved to js/character-start.js as part of
// the Phase 3 decomposition.


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
// SETTINGS SYSTEM moved to js/dev-tools.js (Phase 3 decomposition)
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

// Dev panel population (populateGameSelects, populateItemSelects, etc.),
// updateActiveCursesList, and enableButtons moved to js/dev-tools.js as
// part of the Phase 3 decomposition. They are re-exported on window so
// the existing typeof-defensive call sites elsewhere keep working.

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


// Map layout (Sugiyama layering, crossing minimization, layer reorg,
// horizontal offsets, amulet pinning), generateMapView, showMapModal,
// drawMapArrows, hover tooltip + path highlight, and zoom were moved to
// js/map-render.js as part of the Phase 3 decomposition.



// Combat flow orchestration (showCombatModal, buildWeightedEncounter,
// showDiceCombatModal, handleDiceCombatVictory/Defeat,
// showPostCombatChoiceModal, showSmithChoiceModal) moved to
// js/combat-flow.js as part of the Phase 3 decomposition.


// Make new combat modal available globally

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

// ============== ALLY SYSTEM ==============

/**
 * Recruit an ally
 * @param {string} allyName - Name of the ally from ALLIES_DATA
 * @returns {boolean} Success
 */

// Allies system (recruit/dismiss/heal/HP-update + side panel UI) moved
// to js/allies.js as part of the Phase 3 decomposition.


// Check if an event's requirement is met

// Event modal + special encounter flow (checkEventRequirement,
// showEventModal, handleEventChoice, triggerCombat, +Primordial Teleporter,
// Stone Golem, Wild Muncher, Colosseum handlers) moved to js/events.js
// as part of the Phase 3 decomposition.




// Item-choice modal (showItemChoiceModal) + chest helpers (offerChest,
// offerItemReward) moved to js/loot.js as part of the Phase 3
// decomposition.


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
  if (typeof createNotification === 'function') {
    createNotification(`Difficulty: ${gameState.totalGamesBeaten} (${newDifficultyAfterIncrement})`, '#3498db', '📈');
  }

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
    StateMutator.modifyAbility('dash', 1);
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

  // Keep the top-bar difficulty readout in sync (renderGameState() sets it on full redraws)
  const _distEl = document.getElementById('distance-display');
  if (_distEl && typeof bfsCached === 'function' && gameState.currentGame && gameState.amuletGame) {
    const _dist = bfsCached(gameState.currentGame, gameState.amuletGame.name);
    _distEl.textContent = `Target: ${gameState.amuletGame.name} — ${_dist} steps away | Difficulty: ${gameState.totalGamesBeaten}`;
  }

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

// Curse helpers (addCurse, getCurseMaxUses, checkCurseDurations) and
// game-status helpers (addGameStatus, removeGameStatus, hasGameStatus,
// getGameStatuses, getGamesWithStatus, triggerGameStatusEffects) moved
// to js/curse-manager.js as part of the Phase 3 decomposition.


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

  const removed = inventory[itemIndex];
  StateMutator.removeItem(itemIndex);

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
  const removed = inventory[randomIndex];
  StateMutator.removeItem(randomIndex);

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
