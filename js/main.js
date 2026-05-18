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
    // updateRoguePointsDisplay / updateConditionCounts were dead calls
    // (no such functions exist). Skipped.
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


// Run-time UI modals (deck viewer, dice tray, spells panel,
// notification history, card preview/zoom, level-up flow incl. dice-face
// upgrade) moved to js/run-modals.js as part of the Phase 3 decomposition.


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


// Dev-tools event listeners and the redundant cross-module
// window.* re-export block moved to js/dev-tools.js as part of
// the Phase 4 cleanup. The moved-out functions self-export from
// their new owning files (combat-flow / events / shop / loot /
// curse-manager / map-render etc.).



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
