// ===== MAIN.JS - Initialization and Event Listeners =====
//
// This module handles:
// - Page initialization
// - Event listener setup
// - Excel file upload
// - Save/load game system
// - Tutorial and UI controls
// - Integration of all other modules

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
  console.log('Initializing Roguelike-Like...');

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

  console.log('Initialization complete');
});

// ===== SAVE/LOAD SYSTEM =====

function loadState() {
  const state = GameStorage.load(STORAGE_KEYS.GAME_STATE);
  if (state) {
    rations = state.rations;
    gold = state.gold ?? 0;
    health = state.health;
    maxHealth = state.maxHealth ?? 10;
    inventory = state.inventory;
    beatenGames = state.beatenGames;
    selectedPhase2Games = state.selectedPhase2Games;
    excludedGames = state.excludedGames ?? [];
    roguePoints = state.roguePoints;
    pactConditions = state.pactConditions;
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

let selectedCharacter = "rogue";

function saveCurrentGame() {
  if (!gameState.saveName) return;

  gameSaves[gameState.saveName] = {
    ...gameState,
    health: health,
    maxHealth: maxHealth,
    gold: gold,
    rations: rations,
    inventory: [...inventory],
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
  console.log('Game saved:', gameState.saveName);
}

function loadSavedGame(saveName) {
  const save = gameSaves[saveName];
  if (!save) return;

  // Restore game state
  gameState = { ...save };

  // Generate encounter types if they don't exist (for old saves)
  if (!gameState.encounterTypes) {
    gameState.encounterTypes = {};
    games.forEach(game => {
      const roll = Math.random() * 100;
      if (roll < 75) {
        gameState.encounterTypes[game.name] = 'combat';
      } else if (roll < 90) {
        gameState.encounterTypes[game.name] = 'event';
      } else {
        gameState.encounterTypes[game.name] = 'shop';
      }
    });
  }

  health = save.health;
  maxHealth = save.maxHealth;
  gold = save.gold;
  rations = save.rations || 10;
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

  console.log('Game loaded:', saveName);
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
  console.log('=== START RUN CLICKED ===');
  console.log('games.length:', games.length);
  console.log('PLAYER_CHARACTERS keys:', Object.keys(PLAYER_CHARACTERS));

  if (games.length === 0) {
    alert('Game data is still loading... Please wait a moment and try again.');
    return;
  }

  // Reset character selection state
  currentCharacterIndex = 0;

  // Set first character as default selected
  const characterKeys = Object.keys(PLAYER_CHARACTERS);
  selectedCharacter = characterKeys.length > 0 ? characterKeys[0] : null;

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


document.getElementById('cancel-save')?.addEventListener('click', () => {
  document.getElementById('save-modal').style.display = 'none';
});

document.getElementById('confirm-save')?.addEventListener('click', () => {
  const saveName = document.getElementById('save-name-input').value.trim();
  if (!saveName) {
    alert('Please enter a save name');
    return;
  }

  // Check if a character has been selected
  if (!selectedCharacter) {
    alert('Please select a character before starting your run');
    return;
  }

  if (gameSaves[saveName] && !confirm('Overwrite existing save?')) {
    return;
  }

  // Pick random start and amulet
  const eligible = games.filter(g => g.connected);
  if (eligible.length < 2) {
    alert('Not enough games');
    return;
  }

  const start = eligible[Math.floor(Math.random() * eligible.length)];
  const candidates = eligible.filter(g =>
    Math.floor(g.year / 10) !== Math.floor(start.year / 10) && g.type !== start.type
  );

  if (candidates.length === 0) {
    alert('No valid amulet game');
    return;
  }
  const amulet = candidates[Math.floor(Math.random() * candidates.length)];

  // Initialize game state with character
  console.log('=== INITIALIZING NEW GAME ===');
  console.log('Selected character:', selectedCharacter);
  console.log('Character exists in PLAYER_CHARACTERS?', selectedCharacter in PLAYER_CHARACTERS);

  const character = PLAYER_CHARACTERS[selectedCharacter];
  if (!character) {
    console.error('ERROR: Character not found!', selectedCharacter);
    alert('Error: Character data not found. Please try again.');
    return;
  }

  console.log('Character data:', character);
  strength = character.startingStats.strength || 0;
  dexterity = character.startingStats.dexterity || 0;
  intelligence = character.startingStats.intelligence || 0;
  charisma = character.startingStats.charisma || 0;
  reroll = character.startingStats.reroll || 0;
  dash = character.startingStats.dash || 0;
  skip = character.startingStats.skip || 0;
  discovery = character.startingStats.discovery || 0;
  fov = character.startingStats.fov || 0;
  luck = character.startingStats.luck || 0;

  // Reset health and gold for new run
  health = 10;
  maxHealth = 10;
  gold = 0;

  // Clear inventory and curses for new run
  inventory = [];

  // Store character traits
  const characterTraits = character.traits || [];

  // Generate random encounter types for this run
  // Each game has: 75% combat, 15% event, 10% shop
  const encounterTypes = {};
  games.forEach(game => {
    const roll = Math.random() * 100;
    if (roll < 75) {
      encounterTypes[game.name] = 'combat';
    } else if (roll < 90) {
      encounterTypes[game.name] = 'event';
    } else {
      encounterTypes[game.name] = 'shop';
    }
  });

  gameState = {
    currentGame: start.name,
    visitedGames: [start.name],
    finishedGames: [], // Track unique games finished in this run
    skippedGames: [], // Track games skipped in this run
    saveName: saveName,
    gameStarted: true,
    health: health,
    maxHealth: maxHealth,
    gold: gold,
    inventory: [],
    activeCurses: [], // Clear curses for new run
    cursesTracker: {}, // Clear curse tracking for new run
    beatenGames: [...beatenGames],
    startGame: start,
    amuletGame: amulet,
    currentY: 120,
    character: selectedCharacter,
    traits: characterTraits,
    strength: strength,
    dexterity: dexterity,
    intelligence: intelligence,
    charisma: charisma,
    escapePhase: false,
    escapeGames: [],
    escapeProgress: 0,
    gameStatusEffects: {}, // Map of game names to arrays of status effects
    encounterTypes: encounterTypes // Map of game names to encounter types for this run
  };

  startGame = start;
  amuletGame = amulet;

  // Invalidate BFS cache for new run (new start/amulet games)
  if (typeof invalidateBFSCache === 'function') {
    invalidateBFSCache();
  }

  // Clean up any escape container from previous run
  const escapeContainer = document.getElementById('escape-container');
  if (escapeContainer) {
    escapeContainer.remove();
  }

  // Hide modal and menu
  document.getElementById('save-modal').style.display = 'none';
  document.getElementById('main-menu').style.display = 'none';
  document.getElementById('dungeon-screen').style.display = 'flex';

  // Show the normal game elements
  document.getElementById('path-viewport').style.display = 'block';
  // Note: floating-hud is always visible, no need to show/hide
  document.getElementById('target').style.display = 'block';

  // Render initial game state
  if (typeof renderGameState === 'function') {
    renderGameState();
  }

  // Update character UI
  updateCharacterUI();
  updateTraitsDisplay();

  // Generate new bingo grid for this run
  generateBingoGrid();

  saveCurrentGame();
  updateSaveList();
});

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

document.getElementById('return-menu')?.addEventListener('click', () => {
  if (confirm('Return to main menu? (Game will be saved)')) {
    saveCurrentGame();
    if (typeof clearAllArrows === 'function') {
      clearAllArrows();
    }
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';
  }
});

// Top bar menu button (same functionality)
document.getElementById('return-menu-top')?.addEventListener('click', () => {
  // Only show if in dungeon screen
  if (document.getElementById('dungeon-screen').style.display !== 'none') {
    if (confirm('Return to main menu? (Game will be saved)')) {
      saveCurrentGame();
      if (typeof clearAllArrows === 'function') {
        clearAllArrows();
      }
      document.getElementById('dungeon-screen').style.display = 'none';
      document.getElementById('main-menu').style.display = 'flex';
    }
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

      html += `
        <div class="map-game-box-${gameName.replace(/\s+/g, '-')}" data-game="${gameName}"
             onmouseenter="showMapTooltip(event, '${gameName.replace(/'/g, "\\'")}')"
             onmousemove="moveMapTooltip(event)"
             onmouseleave="hideMapTooltip()"
             style="
          background: ${boxColor};
          border: 2px solid ${borderColor};
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
          color: ${isCurrentGame ? 'white' : (isPastGame || !isOnShortestPath ? '#888' : '#e6d5b8')};
          box-shadow: 0 3px 6px rgba(0,0,0,0.3);
          cursor: pointer;
          opacity: ${!isOnShortestPath && !isCurrentGame && !isAmuletGame ? '0.5' : '1'};
          transform: translateX(${horizontalOffset}px);
          position: relative;
        ">
          ${isCurrentGame ? '📍 ' : ''}${gameName}${isAmuletGame ? ' 🏆' : ''}${isOnShortestPath && !isCurrentGame && !isAmuletGame ? ' ⭐' : ''}
          ${encounterIcon ? `<span style="position: absolute; top: -8px; right: -8px; width: 20px; height: 20px; background: ${encounterColor}; color: ${encounterColor === '#ffd700' ? '#000' : '#fff'}; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 12px; font-weight: bold; border: 2px solid #000; box-shadow: 0 2px 4px rgba(0,0,0,0.4);">${encounterIcon}</span>` : ''}
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

  console.log('Map modal - Current game:', currentGame, 'Amulet game:', amuletGame);

  // Get shortest path info first
  const shortestPathData = findAllShortestPaths(currentGame, amuletGame);

  console.log('Shortest path data:', shortestPathData);

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

  console.log('Drawing map arrows, pathData:', pathData);
  console.log('SVG dimensions set to:', parentRect.width, 'x', Math.max(parentRect.height, 2000));

  // Get all game boxes
  const gameBoxes = document.querySelectorAll('[data-game]');
  console.log('Found game boxes:', gameBoxes.length);
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
    console.log(`  Box "${gameName}": (${rect.left - containerRect.left + rect.width / 2}, ${rect.top - containerRect.top})`);
  });

  console.log('Total box positions mapped:', boxPositions.size);

  // Draw arrows between connected games
  const layers = Array.from(pathData.layers.keys()).sort((a, b) => a - b);
  console.log('Number of layers:', layers.length);

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
    console.log(`Layer ${layerIndex} (distance ${distance}): ${gamesAtLayer.length} games`);

    gamesAtLayer.forEach(fromGameData => {
      const fromGame = fromGameData.name || fromGameData;
      const fromIsOnShortestPath = fromGameData.isOnShortestPath !== undefined ? fromGameData.isOnShortestPath : true;
      const fromDistance = distance;

      // Skip if not on shortest path
      if (!fromIsOnShortestPath) return;

      const fromPos = boxPositions.get(fromGame);
      if (!fromPos) {
        console.log(`  ❌ No position for "${fromGame}"`);
        return;
      }

      const connections = getGameConnections(fromGame);
      console.log(`  "${fromGame}" connections:`, connections);

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
            console.log(`    ❌ No position for target "${toGame}"`);
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
    svg.appendChild(line);

    arrowsDrawn++;
    console.log(`    ✅ Drew arrow: "${arrow.fromGame}" (dist ${arrow.fromDistance}) → "${arrow.toGame}" (dist ${arrow.toDistance})`);
  });

  console.log(`✅ Total arrows drawn: ${arrowsDrawn}`);
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

  // Difficulty scales with number of games beaten
  const gamesBeaten = gameState.finishedGames?.length || 0;
  let powerText = 'Low';
  if (gamesBeaten >= 10) {
    powerText = 'High';
  } else if (gamesBeaten >= 5) {
    powerText = 'Medium';
  }

  const matchingEnemies = enemies.filter(enemy =>
    enemy.powerLevel === powerText && enemy.stat === requiredStat
  );

  if (matchingEnemies.length === 0) return;

  const randomIndex = Math.floor(Math.random() * matchingEnemies.length);
  const enemy = matchingEnemies[randomIndex];

  // Get player's stat value for this check
  const playerStatValue = getPlayerStat(enemy.stat);

  const enemyImagePath = getEnemyImagePath(enemy.name);

  createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #ff4444; margin-top: 0;">Combat Encounter!</h2>
      <h3>${enemy.name}</h3>
      <p style="color: #888;">From: ${enemy.game}</p>
      <img src="${enemyImagePath}" style="max-width: 200px; max-height: 200px; image-rendering: pixelated; margin: 10px auto; display: block;" alt="${enemy.name}" onerror="this.style.display='none'">
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
      <button id="roll-combat-btn" style="padding: 20px 40px; font-size: 20px; background: #4CAF50; border: none; border-radius: 8px; color: white; cursor: pointer; margin: 15px auto; display: block; min-width: 180px; font-weight: bold; position: relative; z-index: 10;">
        Roll D20
      </button>
      <div id="combat-result" style="margin-top: 20px; font-size: 16px;"></div>
    </div>
  `);

  const rollBtn = document.getElementById('roll-combat-btn');
  rollBtn.addEventListener('click', function handleRoll() {
    const diceRoll = Math.floor(Math.random() * 20) + 1;
    let cursePenalty = 0;
    let curseMessages = [];

    // Check for Curse of Weakness (subtract from roll) - handle stacking
    const weaknessCurses = getCursesByType('weakness');
    if (weaknessCurses.length > 0) {
      // Use only the first weakness curse and remove it
      const weaknessCurse = weaknessCurses[0];
      const penalty = getPowerValue(weaknessCurse.power, { Low: 2, Medium: 3, High: 4 });

      cursePenalty = penalty;
      curseMessages.push(`Curse of Weakness: -${penalty}`);

      // Remove this specific curse instance after this roll
      gameState.activeCurses.splice(gameState.activeCurses.indexOf(weaknessCurse), 1);
      updateCurseUI();
    }

    // Check for Curse of Failure (damage on rolling 1) - handle stacking
    if (diceRoll === 1) {
      const failureCurses = getCursesByType('failure');
      if (failureCurses.length > 0) {
        // Trigger all failure curses if rolled a 1
        let totalDamage = failureCurses.reduce((sum, curse) =>
          sum + getPowerValue(curse.power, { Low: 2, Medium: 3, High: 4 }), 0
        );

        // Apply damage reduction from items (like Garlic)
        if (typeof calculateDamageReduction === 'function') {
          totalDamage = calculateDamageReduction(totalDamage);
        }

        health = Math.max(0, health - totalDamage);
        gameState.health = health;
        updateTopBar?.();

        curseMessages.push(`Curse of Failure (×${failureCurses.length}): -${totalDamage} HP!`);

        // Show popup notification for Curse of Failure damage
        setTimeout(() => {
          createGameModal?.(`
            <div style="text-align: center;">
              <h2 style="color: #ff4444; margin-top: 0; font-size: 32px;">😱 Curse of Failure!</h2>
              <p style="font-size: 18px; color: #ff8888;">You rolled a natural 1!</p>
              <p style="font-size: 20px; font-weight: bold; color: #ff0000; margin: 15px 0;">
                ⚠️ CRITICAL FAILURE - Combat Auto-Lost!
              </p>
              <p style="font-size: 24px; font-weight: bold; color: #ff6666; margin: 20px 0;">
                -${totalDamage} HP
              </p>
              ${failureCurses.length > 1 ? `<p style="color: #cc8888; font-size: 14px;">${failureCurses.length} curses triggered</p>` : ''}
              <button onclick="closeGameModal()" style="
                padding: 10px 30px;
                margin-top: 20px;
                background: #ff4444;
                border: none;
                border-radius: 6px;
                color: white;
                cursor: pointer;
                font-weight: bold;
              ">Continue</button>
            </div>
          `);
        }, 500);

        // Remove all failure curses after triggering
        gameState.activeCurses = gameState.activeCurses.filter(c => !c.name.toLowerCase().includes('failure'));
        updateCurseUI();

        // Check for death
        if (health <= 0) {
          // Will be handled by the death check below
        }
      }
    }

    const totalRoll = diceRoll + playerStatValue - cursePenalty;

    // Curse of Failure causes critical fail - auto-lose combat
    const criticalFail = diceRoll === 1 && getCursesByType('failure').length > 0;
    const success = criticalFail ? false : (totalRoll >= enemy.rollCheck);

    let resultHTML = `
      <div style="background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; margin: 10px 0;">
        <p style="font-size: 20px; font-weight: bold;">Dice: ${diceRoll}</p>
        <p style="font-size: 16px; color: ${getStatColor(enemy.stat)};">+ ${enemy.stat} Bonus: ${playerStatValue}</p>
        ${cursePenalty > 0 ? `<p style="font-size: 16px; color: #ff6666;">- Weakness Penalty: ${cursePenalty}</p>` : ''}
        <p style="font-size: 24px; font-weight: bold; margin-top: 10px; color: gold;">Total: ${totalRoll}</p>
        ${criticalFail ? `<p style="font-size: 18px; font-weight: bold; color: #ff0000; margin-top: 10px;">⚠️ CRITICAL FAILURE!</p>` : ''}
        ${curseMessages.length > 0 ? `<p style="font-size: 14px; color: #ff8888; margin-top: 10px;">${curseMessages.join('<br>')}</p>` : ''}
      </div>
    `;

    if (success) {
      const goldMatch = enemy.successReward.match(/(\d+) Gold/);
      if (goldMatch) {
        const goldAmount = parseInt(goldMatch[1]);
        gold += goldAmount;
        gameState.gold = gold;
        updateTopBar();
      }

      // Trigger onEnemyDefeated effects for triggered items
      if (typeof triggerOnEnemyDefeated === 'function') {
        triggerOnEnemyDefeated();
      }

      resultHTML += `<p style="color: #4CAF50; font-weight: bold;">SUCCESS!</p>
                    <p>${enemy.successReward}</p>`;
    } else {
      // Damage based on difficulty level
      let healthLoss = 1; // Low difficulty
      if (powerText === 'Medium') {
        healthLoss = 2;
      } else if (powerText === 'High') {
        healthLoss = 3;
      }

      // Apply damage reduction from items (like Garlic)
      if (typeof calculateDamageReduction === 'function') {
        healthLoss = calculateDamageReduction(healthLoss);
      }

      health = Math.max(0, health - healthLoss);
      gameState.health = health;
      updateHealthDisplay();

      // Check for death
      if (health <= 0) {
        // Clear items and curses immediately on death
        inventory = [];
        if (gameState.activeCurses) {
          gameState.activeCurses = [];
        }

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
                  transition: all 0.2s;
                " onmouseover="this.style.background='#555'" onmouseout="this.style.background='#444'">
                  🏠 Home
                </button>
                <button id="death-retry-btn" style="
                  padding: 12px 24px;
                  background: #d32f2f;
                  border: 2px solid #f44336;
                  border-radius: 8px;
                  color: white;
                  cursor: pointer;
                  font-weight: bold;
                  font-size: 16px;
                  transition: all 0.2s;
                " onmouseover="this.style.background='#e53935'" onmouseout="this.style.background='#d32f2f'">
                  🔄 Try Again
                </button>
              </div>
            </div>
          `);

          document.getElementById('death-home-btn').onclick = () => {
            closeGameModal();
            // Update UI to reflect cleared items and curses
            updateInventory?.();
            updateCursesDisplay?.();
            updateActiveCursesList?.();
            updateGameStats?.();
            if (typeof clearAllArrows === 'function') {
              clearAllArrows();
            }
            document.getElementById('dungeon-screen').style.display = 'none';
            document.getElementById('main-menu').style.display = 'flex';
          };

          document.getElementById('death-retry-btn').onclick = () => {
            // Clear UI immediately to prevent flash
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
            setTimeout(() => {
              document.getElementById('new-game-btn')?.click();
            }, 100);
          };
        }, 300);
        return; // Exit the function early to prevent showing combat results
      }

      // Apply curse based on enemy's failure trigger
      const matchingCurses = curses.filter(curse =>
        curse.power === powerText && curse.stat === enemy.stat
      );
      let failureText = `Lose ${healthLoss} health`;
      if (matchingCurses.length > 0) {
        const randomCurseIndex = Math.floor(Math.random() * matchingCurses.length);
        const selectedCurse = matchingCurses[randomCurseIndex];

        // Add curse using helper function (handles Curse of Vulnerability)
        addCurse(selectedCurse);

        failureText = `Lose ${healthLoss} health and gain ${selectedCurse.name}!`;
      }

      resultHTML += `<p style="color: #ff4444; font-weight: bold;">FAILURE!</p>
                    <p>${failureText}</p>`;
    }

    resultHTML += `<button onclick="closeGameModal()" style="padding: 10px 20px; margin-top: 20px; background: #666; border: none; border-radius: 6px; color: white; cursor: pointer;">Continue</button>`;

    document.getElementById('combat-result').innerHTML = resultHTML;
    rollBtn.disabled = true;
    rollBtn.style.opacity = '0.5';
    rollBtn.style.cursor = 'not-allowed';
    rollBtn.removeEventListener('click', handleRoll);

    encounterHistory.push({
      type: 'combat',
      enemy: enemy.name,
      outcome: success ? 'Victory' : 'Defeat',
      timestamp: new Date().toLocaleString()
    });
    updateEncounterHistory();
    saveCurrentGame();
  });
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
      <img src="${enemyImagePath}" style="max-width: 200px; max-height: 200px; image-rendering: pixelated; margin: 10px auto; display: block;" alt="${enemy.name}" onerror="this.style.display='none'">
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
    // Trigger onEnemyDefeated effects for triggered items (like Cursed Slash)
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
    if (gameState.finishedGames && gameState.finishedGames.length >= 3) {
      gameState.finishedGames = gameState.finishedGames.slice(0, -3);
    } else {
      gameState.finishedGames = [];
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

    // Trigger onEnemyDefeated effects for triggered items (like Cursed Slash)
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
    const rarityItems = items.filter(item => item.rarity === targetRarity);
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

  // Special handling for Cursed Slash - restore the max health it took
  if (item.name === 'Cursed Slash') {
    const oldMaxHealth = maxHealth;
    const oldHealth = health;

    // Restore max health (reverse the halving by doubling)
    maxHealth = maxHealth * 2;

    // Restore current health proportionally (same proportion as before)
    health = Math.min(maxHealth, health * 2);

    gameState.maxHealth = maxHealth;
    gameState.health = health;
    updateHealthDisplay();
    updateTopBar();

    console.log(`Cursed Slash removed: Max health ${oldMaxHealth} → ${maxHealth}, Current health ${oldHealth} → ${health}`);

    // Remove from inventory (handle quantity) and return early
    if (item.quantity && item.quantity > 1) {
      item.quantity--;
      console.log(`${item.name} quantity decreased to ${item.quantity}`);
    } else {
      inventory.splice(index, 1);
    }
    gameState.inventory = inventory;
    updateInventory();
    return;
  }

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

  // Remove from inventory (handle quantity)
  if (item.quantity && item.quantity > 1) {
    item.quantity--;
    console.log(`${item.name} quantity decreased to ${item.quantity}`);
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
    const rarityItems = items.filter(item => item.rarity === targetRarity);

    if (rarityItems.length > 0) {
      const randomItem = rarityItems[Math.floor(Math.random() * rarityItems.length)];
      acquireItem(randomItem);
    } else {
      // Fallback to any random item if no items of target rarity exist
      const randomItem = items[Math.floor(Math.random() * items.length)];
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


function showItemChoiceModal(onComplete, chestType = 'normal') {
  if (items.length === 0) {
    // If no items, just spawn choices or call callback
    if (onComplete) {
      setTimeout(() => onComplete(), 300);
    } else {
      setTimeout(() => spawnChoices(), 300);
    }
    return;
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

      const rarityItems = items.filter(item => item.rarity === targetRarity);
      if (rarityItems.length > 0) {
        const randomIndex = Math.floor(Math.random() * rarityItems.length);
        selectedItem = rarityItems[randomIndex];
      } else if (!rarityFilter) {
        // Fallback to any item if no rarity filter (normal chest)
        const randomIndex = Math.floor(Math.random() * items.length);
        selectedItem = items[randomIndex];
      } else {
        // If rarity filter is set but no items of that rarity exist, break
        console.warn(`No items of rarity ${rarityFilter} available`);
        break;
      }

      // Check if this item is already in choices
      if (!choices.find(c => c.name === selectedItem.name)) {
        choices.push(selectedItem);
        break;
      }

      attempts++;
    }

    // If we couldn't find a unique item after max attempts, just add it anyway
    if (attempts >= maxAttempts && selectedItem) {
      choices.push(selectedItem);
    }
  }

  let itemsHTML = '<div style="display: flex; flex-wrap: wrap; gap: 20px; margin-top: 20px; justify-content: center;">';

  choices.forEach((item, index) => {
    const rarityColor = item.rarity === 'common' ? '#aaa' : item.rarity === 'uncommon' ? '#4CAF50' : '#9b59b6';

    itemsHTML += `
      <div class="item-choice-card" data-index="${index}" style="
        flex: 1;
        max-width: 250px;
        padding: 20px;
        background: #2d2d2d;
        border: 3px solid ${rarityColor};
        border-radius: 12px;
        cursor: pointer;
        transition: all 0.3s;
        text-align: center;
      ">
        ${item.image ? `<img src="${item.image}" style="width: 100px; height: 100px; object-fit: contain; image-rendering: pixelated; margin: 0 auto 15px; display: block; border-radius: 8px; border: 2px solid ${rarityColor};" alt="${item.name}" onerror="this.style.display='none';">` : ''}
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
      const itemIndex = parseInt(e.currentTarget.dataset.index);
      const item = choices[itemIndex];

      acquireItem(item);

      closeGameModal();

      // Set phase to selection so usable items become enabled
      gameState.phase = 'selection';
      if (typeof updateInventory === 'function') {
        updateInventory();
      }

      // Now spawn the next choices or call callback
      if (onComplete) {
        setTimeout(() => onComplete(), 300);
      } else {
        setTimeout(() => spawnChoices(), 300);
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

      // Spawn choices without acquiring an item or call callback
      if (onComplete) {
        setTimeout(() => onComplete(), 300);
      } else {
        setTimeout(() => spawnChoices(), 300);
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
 * Get game stats from localStorage
 * @returns {Object} Game stats object with game names as keys
 */
function getGameStats() {
  return GameStorage.load(STORAGE_KEYS.GAME_STATS, {});
}

/**
 * Save game stats to localStorage
 * @param {Object} stats - Game stats object
 */
function saveGameStats(stats) {
  const result = GameStorage.save(STORAGE_KEYS.GAME_STATS, stats);
  if (!result.success) {
    console.error('Error saving game stats:', result.error);
  }
}

/**
 * Increment beaten count for a game
 * @param {string} gameName - Name of the game
 * @param {boolean} hasAmulet - Whether this was an amulet game
 */
function incrementGameBeaten(gameName, hasAmulet = false) {
  const stats = getGameStats();

  if (!stats[gameName]) {
    stats[gameName] = { beaten: 0, amulets: 0 };
  }

  stats[gameName].beaten = (stats[gameName].beaten || 0) + 1;

  if (hasAmulet) {
    stats[gameName].amulets = (stats[gameName].amulets || 0) + 1;
    console.log(`${gameName} amulet collected! Total amulets: ${stats[gameName].amulets}`);
  }

  saveGameStats(stats);

  console.log(`${gameName} beaten count: ${stats[gameName].beaten}`);
}

/**
 * Show game details in the collection panel
 * @param {string} gameName - Name of the game to show details for
 */
function showGameDetails(gameName) {
  const game = games.find(g => g.name === gameName);
  if (!game) return;

  const stats = getGameStats();
  const gameStats = stats[gameName] || { beaten: 0 };

  // Get influenced by and influences lists
  const influencedBy = getInfluencedByGames(gameName);
  const influences = game.gamesInfluenced || [];

  const detailsPanel = document.getElementById('game-details');
  if (!detailsPanel) return;

  let connectionsHTML = '';

  if (influencedBy.length > 0) {
    connectionsHTML += `
      <div style="margin-top: 15px;">
        <strong style="color: #4CAF50;">Influenced By:</strong>
        <div style="margin-top: 8px; display: grid; grid-template-columns: repeat(2, 1fr); gap: 5px;">
          ${influencedBy.map(g => `
            <div style="font-size: 11px; padding: 5px 8px; background: rgba(76, 175, 80, 0.1);
              border: 1px solid rgba(76, 175, 80, 0.3); border-radius: 4px; color: #ddd;">
              ${g}
            </div>
          `).join('')}
        </div>
      </div>`;
  }

  if (influences.length > 0) {
    connectionsHTML += `
      <div style="margin-top: 15px;">
        <strong style="color: #9b59b6;">Influenced:</strong>
        <div style="margin-top: 8px; display: grid; grid-template-columns: repeat(2, 1fr); gap: 5px;">
          ${influences.map(g => `
            <div style="font-size: 11px; padding: 5px 8px; background: rgba(155, 89, 182, 0.1);
              border: 1px solid rgba(155, 89, 182, 0.3); border-radius: 4px; color: #ddd;">
              ${g}
            </div>
          `).join('')}
        </div>
      </div>`;
  }

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Game Info -->
      <div>
        <h3 style="margin: 0 0 10px 0; color: #ff9800;">${game.name}</h3>
        <div style="color: #aaa; font-size: 13px; line-height: 1.6;">
          <div><strong>Release Year:</strong> ${game.year || '—'}</div>
          <div><strong>Type:</strong> ${game.type || '—'}</div>
          ${game.tags && game.tags.length > 0 ? `<div><strong>Tags:</strong> ${game.tags.join(', ')}</div>` : ''}
        </div>
      </div>

      <!-- Tracked Stats -->
      <div style="padding: 12px; background: rgba(255, 152, 0, 0.1); border: 1px solid rgba(255, 152, 0, 0.3); border-radius: 6px;">
        <h4 style="margin: 0 0 8px 0; color: #ff9800; font-size: 14px;">📊 Tracked Stats</h4>
        <div style="font-size: 13px; color: #ddd; line-height: 1.8;">
          <div><strong>Beaten:</strong> ${gameStats.beaten}</div>
          ${gameStats.amulets > 0 ? `<div><strong>Amulets Collected:</strong> ${gameStats.amulets}</div>` : ''}
        </div>
      </div>

      <!-- Connections -->
      ${connectionsHTML}
    </div>
  `;
}

function markGameFinished(gameName) {
  if (!gameState.finishedGames) {
    gameState.finishedGames = [];
  }

  // Increment beaten count (tracks all completions, even if player dies later)
  // NOTE: Amulet stat is only incremented on successful escape (in showVictoryScreen)
  incrementGameBeaten(gameName, false);

  // Reroller trait: Every time you beat a game, gain +1 Reroll
  if (hasTrait('reroller')) {
    reroll++;
    console.log('Reroller trait triggered: +1 Reroll');
    if (typeof updateTopBar === 'function') {
      updateTopBar();
    }
  }

  // Only add if not already in finishedGames array
  if (!gameState.finishedGames.includes(gameName)) {
    gameState.finishedGames.push(gameName);
    console.log(`Game finished: ${gameName}. Total unique finished: ${gameState.finishedGames.length}`);

    // Check and update curse durations
    checkCurseDurations('game_beaten');

    // Update curse UI to reflect new progress
    if (typeof updateCurseUI === 'function') {
      updateCurseUI();
    }

    updateGameStats();
    saveCurrentGame();
  }
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

    // Check if this curse should be incremented
    if (cursesToIncrement.includes(curse.id)) {
      tracker.gamesBeaten = (tracker.gamesBeaten || 0) + 1;
      console.log(`Incremented curse ${curse.name} (${curse.id}): ${tracker.gamesBeaten} games beaten`);
    }

    // Check if curse duration is complete
    if (curse.duration) {
      const match = curse.duration.match(/(\d+)\s+game/i);
      if (match) {
        const requiredGames = parseInt(match[1]);
        if (tracker.gamesBeaten >= requiredGames) {
          console.log(`Curse ${curse.name} duration complete (${tracker.gamesBeaten}/${requiredGames})`);
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
 * @param {string} icon - Emoji icon for the status
 */
function addGameStatus(gameName, statusName, icon = '❓') {
  if (!gameState.gameStatusEffects) {
    gameState.gameStatusEffects = {};
  }

  if (!gameState.gameStatusEffects[gameName]) {
    gameState.gameStatusEffects[gameName] = [];
  }

  // Check if status already exists
  const existing = gameState.gameStatusEffects[gameName].find(s => s.name === statusName);
  if (existing) {
    console.log(`Status ${statusName} already exists on ${gameName}`);
    return;
  }

  gameState.gameStatusEffects[gameName].push({
    name: statusName,
    icon: icon
  });

  console.log(`Added status ${statusName} to ${gameName}`);

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
    console.log(`Removed status ${statusName} from ${gameName}`);

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
window.switchCollectionTab = switchCollectionTab;
window.showGameDetails = showGameDetails;
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

  // Update character name in header
  const statsCharacterNameEl = document.getElementById('stats-character-name');
  if (statsCharacterNameEl) {
    statsCharacterNameEl.textContent = character.name;
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

  console.log('Inventory sort buttons setup:', {
    sortAlphaBtn: !!sortAlphaBtn,
    sortRarityBtn: !!sortRarityBtn,
    sortTypeBtn: !!sortTypeBtn,
    updateInventory: typeof window.updateInventory
  });

  if (sortAlphaBtn) {
    sortAlphaBtn.addEventListener('click', () => {
      console.log('Sort A-Z clicked, changing mode from', window.inventorySortMode, 'to alphabetical');
      window.inventorySortMode = 'alphabetical';
      updateSortButtons(sortAlphaBtn);
      if (typeof window.updateInventory === 'function') {
        console.log('Calling updateInventory()');
        window.updateInventory();
        console.log('updateInventory() completed');
      } else {
        console.error('updateInventory not found');
      }
    });
  } else {
    console.error('sort-alpha-btn not found in DOM');
  }

  if (sortRarityBtn) {
    sortRarityBtn.addEventListener('click', () => {
      console.log('Sort Rarity clicked, changing mode from', window.inventorySortMode, 'to rarity');
      window.inventorySortMode = 'rarity';
      updateSortButtons(sortRarityBtn);
      if (typeof window.updateInventory === 'function') {
        console.log('Calling updateInventory()');
        window.updateInventory();
        console.log('updateInventory() completed');
      } else {
        console.error('updateInventory not found');
      }
    });
  } else {
    console.error('sort-rarity-btn not found in DOM');
  }

  if (sortTypeBtn) {
    sortTypeBtn.addEventListener('click', () => {
      console.log('Sort Type clicked, changing mode from', window.inventorySortMode, 'to type');
      window.inventorySortMode = 'type';
      updateSortButtons(sortTypeBtn);
      if (typeof window.updateInventory === 'function') {
        console.log('Calling updateInventory()');
        window.updateInventory();
        console.log('updateInventory() completed');
      } else {
        console.error('updateInventory not found');
      }
    });
  } else {
    console.error('sort-type-btn not found in DOM');
  }
});
