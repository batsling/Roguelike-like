// ===== MAIN.JS - Initialization and Event Listeners =====
//
// This module handles:
// - Page initialization
// - Event listener setup

console.log('✅ MAIN.JS v45 loaded - inventory deep copy on save active');
// - Excel file upload
// - Save/load game system
// - Tutorial and UI controls
// - Integration of all other modules

// ===== Z-INDEX LAYERING SYSTEM =====
// Organized from lowest to highest to prevent layering conflicts
//
// Layer 1 (Base): 1-99
//   - Map SVG arrows: 1
//   - Item hover effects: 10
//
// Layer 2 (UI Panels): 100-999
//   - (Reserved for future use)
//
// Layer 3 (Side Panels): 1000-9999
//   - Combat stats panel: 1000
//   - Combat log panel: 1000
//
// Layer 4 (Modals): 10000-19999
//   - Modal backdrop: 10000 (from modals.js)
//   - Map tooltip: 10000
//   - Trait tooltips: 10000
//   - Generic buttons: 10000
//
// Layer 5 (Tooltips & Overlays): 20000+
//   - Combat item tooltip (#combat-item-tooltip): 20000
//   - Main inventory tooltip (#item-tooltip from index.html): inherits from parent
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

  const lootBtn = document.getElementById('loot-btn');
  if (lootBtn) {
    lootBtn.addEventListener('click', showLootModal);
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

  gameSaves[gameState.saveName] = {
    ...gameState,
    health: health,
    maxHealth: maxHealth,
    gold: gold,
    rations: rations,
    inventory: inventoryCopy,
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

  // Generate encounter types if they don't exist (for old saves)
  if (!gameState.encounterTypes) {
    gameState.encounterTypes = {};
    const startingConnections = gameState.startGame && typeof getGameConnections === 'function'
      ? getGameConnections(gameState.startGame.name)
      : [];

    games.forEach(game => {
      const roll = Math.random() * 100;
      const isConnectedToStart = startingConnections.includes(game.name);

      if (roll < 75) {
        gameState.encounterTypes[game.name] = 'combat';
      } else if (roll < 90) {
        gameState.encounterTypes[game.name] = 'event';
      } else {
        // If this is connected to starting game, re-roll to combat or event
        if (isConnectedToStart) {
          const reroll = Math.random() * 100;
          gameState.encounterTypes[game.name] = reroll < 83.33 ? 'combat' : 'event';
        } else {
          gameState.encounterTypes[game.name] = 'shop';
        }
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

  // Show map button when in game
  const mapBtn = document.getElementById('map-btn');
  if (mapBtn) mapBtn.style.display = 'inline-block';

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

  // Handle both old format (startingStats) and new format (no startingStats, all start at 0)
  const stats = character.startingStats || {};
  strength = stats.strength || 0;
  dexterity = stats.dexterity || 0;
  intelligence = stats.intelligence || 0;
  charisma = stats.charisma || 0;
  attack = stats.attack || 0;
  reroll = stats.reroll || 0;
  dash = stats.dash || 0;
  skip = stats.skip || 0;
  discovery = stats.discovery || 0;
  fov = stats.fov || 0;
  luck = stats.luck || 0;

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
  // Shops cannot spawn on games directly connected to the starting game (would be useless)
  const encounterTypes = {};
  const startingConnections = typeof getGameConnections === 'function'
    ? getGameConnections(start.name)
    : [];

  games.forEach(game => {
    const roll = Math.random() * 100;
    const isConnectedToStart = startingConnections.includes(game.name);

    if (roll < 75) {
      encounterTypes[game.name] = 'combat';
    } else if (roll < 90) {
      encounterTypes[game.name] = 'event';
    } else {
      // If this is connected to starting game, re-roll to combat or event
      if (isConnectedToStart) {
        const reroll = Math.random() * 100;
        encounterTypes[game.name] = reroll < 83.33 ? 'combat' : 'event'; // 75/90 = 83.33%
        console.log(`Prevented shop on ${game.name} (connected to start) - rerolled to ${encounterTypes[game.name]}`);
      } else {
        encounterTypes[game.name] = 'shop';
      }
    }
  });

  // Select a random location for this run (based on starting difficulty of 0)
  const initialDifficulty = getDifficultyTier(0); // Start with Easy tier
  const selectedLocation = getRandomLocation(initialDifficulty);

  gameState = {
    currentGame: start.name,
    visitedGames: [start.name],
    finishedGames: [], // Track unique games finished in this run
    totalGamesBeaten: 0, // Track total number of game completions (including duplicates)
    skippedGames: [], // Track games skipped in this run
    saveName: saveName,
    gameStarted: true,
    health: health,
    maxHealth: maxHealth,
    gold: gold,
    inventory: [],
    loot: [], // Loot inventory for fish and sellable items
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
    encounterTypes: encounterTypes, // Map of game names to encounter types for this run
    location: selectedLocation, // Current location for this run
    playerLevel: 1, // Character level for dice combat system
    activeAllies: [] // Allies that provide dice in combat
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

  // Show map button when in game
  const mapBtn = document.getElementById('map-btn');
  if (mapBtn) mapBtn.style.display = 'inline-block';

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

  // Check if starting location is a Hades location and show boon selection
  if (selectedLocation && selectedLocation.game === 'Hades' && typeof showHadesBoonSelection === 'function') {
    console.log('Starting in Hades location, showing boon selection...');
    // Small delay to let the dungeon screen render first
    // Store the timeout ID so it can be cleared if player finishes game before it fires
    gameState.hadesStartBoonTimeout = setTimeout(() => {
      gameState.hadesStartBoonTimeout = null;
      // Pass false - starting boon shouldn't spawn choices, player is already at the starting location
      showHadesBoonSelection(false);
    }, 500);
  }
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

    // Hide map button when in menu
    const mapBtn = document.getElementById('map-btn');
    if (mapBtn) mapBtn.style.display = 'none';
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

      // Hide map button when in menu
      const mapBtn = document.getElementById('map-btn');
      if (mapBtn) mapBtn.style.display = 'none';
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
  });
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
  const gamesBeaten = gameState.totalGamesBeaten || 0;
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

  // Initialize combat state
  const combat = window.CombatState.initializeCombat(enemy);

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
            <!-- Items Bar (at top) -->
            <div id="items-bar" style="
              background: rgba(0,0,0,0.5);
              border: 2px solid #666;
              border-radius: 8px;
              padding: 10px 15px;
              display: flex;
              align-items: center;
              justify-content: center;
              gap: 8px;
              overflow-x: auto;
              min-height: 60px;
            ">
              <div id="items-icons" style="display: flex; gap: 8px; flex-wrap: wrap; justify-content: center;">
                <!-- Item icons will be populated here -->
              </div>
            </div>

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
    z-index: 20000;
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
      createGameModal(`
        <div style="text-align: center;">
          <h2 style="color: #4CAF50; font-size: 36px; margin: 20px 0;">⚔️ VICTORY!</h2>
          <h3>${enemy.name} defeated!</h3>
          <p style="color: #4CAF50; font-size: 18px; margin: 20px 0;">${enemy.successReward}</p>
          <button onclick="closeGameModal()" style="
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
        const mapBtn = document.getElementById('map-btn');
        if (mapBtn) mapBtn.style.display = 'none';
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
        const mapBtn = document.getElementById('map-btn');
        if (mapBtn) mapBtn.style.display = 'none';

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

  // Global function for using items in combat
  window.useCombatItem = function(itemIndex) {
    if (combat.phase !== 'player_turn') {
      addCombatLogMessage('Cannot use items during enemy turn!', 'warning');
      return;
    }

    const item = inventory[itemIndex];
    if (!item || !item.usableInCombat) {
      addCombatLogMessage('This item cannot be used in combat!', 'warning');
      return;
    }

    // Use the item (this would call the item's effect function)
    // For now, just show a message
    addCombatLogMessage(`Used ${item.name}!`, 'success');

    // TODO: Implement item effects in combat
    // This would require updating the item system to work with combat state

    updateCombatInventory();
  };

  // Initial UI update
  updateCombatUI();
}

// Make showCombatModal available globally
window.showCombatModal = showCombatModal;

/**
 * New Dice-Based Combat Modal
 * Uses CombatEngine and CombatUI for the new combat system
 */
function showDiceCombatModal() {
  if (!ENEMIES_DATA || ENEMIES_DATA.length === 0) {
    console.error('ENEMIES_DATA not loaded');
    return;
  }

  // Set phase to combat
  gameState.phase = 'combat';
  updateInventory();

  // Get difficulty based on games beaten
  const gamesBeaten = gameState.totalGamesBeaten || 0;
  let difficulty = 'Low';
  if (gamesBeaten >= 10) {
    difficulty = 'High';
  } else if (gamesBeaten >= 5) {
    difficulty = 'Medium';
  }

  // Determine type based on current game
  const currentGameObj = games.find(g => g.name === gameState.currentGame);
  let enemyType = 'Strength';
  if (currentGameObj && currentGameObj.type) {
    const gameType = currentGameObj.type.toLowerCase();
    switch(gameType) {
      case 'action': enemyType = 'Strength'; break;
      case 'deckbuilding': enemyType = 'Charisma'; break;
      case 'strategy': enemyType = 'Intelligence'; break;
      case 'traditional': enemyType = 'Dexterity'; break;
      default: enemyType = 'Strength';
    }
  }

  // Filter enemies by difficulty and type
  const matchingEnemies = ENEMIES_DATA.filter(enemy =>
    enemy.difficulty === difficulty && enemy.type === enemyType
  );

  // Fallback to any enemy of the right difficulty if no type match
  const candidates = matchingEnemies.length > 0
    ? matchingEnemies
    : ENEMIES_DATA.filter(e => e.difficulty === difficulty);

  if (candidates.length === 0) {
    console.error('No matching enemies found');
    return;
  }

  // Select random enemy
  const enemyData = candidates[Math.floor(Math.random() * candidates.length)];

  // Get character data
  const characterKey = selectedCharacter || gameState.character || 'rodney';
  const characterData = CHARACTERS_DATA[characterKey];

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

  // Initialize combat
  const combatState = window.CombatEngine.initCombat([enemyData], characterData, weaponData, allies);

  if (!combatState) {
    console.error('Failed to initialize combat');
    return;
  }

  // Create modal HTML container
  const combatHTML = `
    <div id="dice-combat-modal" style="
      width: 95vw;
      max-width: 1200px;
      height: 90vh;
      max-height: 800px;
      display: flex;
      flex-direction: column;
      background: linear-gradient(135deg, #1a1410 0%, #2a1810 100%);
      border-radius: 12px;
      overflow: hidden;
    ">
      <div id="dice-combat-content" style="flex: 1; overflow: hidden;"></div>
    </div>
  `;

  createGameModal(combatHTML);

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
      z-index: 20000;
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

  window.CombatEngine.endCombat(true);

  // Award gold based on difficulty
  const goldAmounts = { 'Low': 10, 'Medium': 20, 'High': 30 };
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
  saveCurrentGame();

  // Show victory screen
  createGameModal(`
    <div style="text-align: center; padding: 30px;">
      <h2 style="color: #4CAF50; font-size: 36px; margin: 20px 0;">Victory!</h2>
      <h3 style="color: #fff; margin: 15px 0;">${enemy.name} defeated!</h3>
      <p style="color: #FFD700; font-size: 18px; margin: 20px 0;">+${goldReward} Gold</p>
      <button onclick="closeGameModal()" style="
        padding: 15px 30px;
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
 * Handle defeat in dice combat
 */
function handleDiceCombatDefeat(enemy) {
  // Cleanup 3D dice renderers
  if (window.CombatUI && window.CombatUI.cleanup3DDice) {
    window.CombatUI.cleanup3DDice();
  }

  window.CombatEngine.endCombat(false);

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
    const mapBtn = document.getElementById('map-btn');
    if (mapBtn) mapBtn.style.display = 'none';
  };

  document.getElementById('dice-death-retry-btn').onclick = () => {
    closeGameModal();
    if (typeof clearAllArrows === 'function') clearAllArrows();
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';
    const mapBtn = document.getElementById('map-btn');
    if (mapBtn) mapBtn.style.display = 'none';
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
    console.log(`Combat system: ${val ? 'New Dice-Based' : 'Classic D20'}`);
  }
});

// Toggle combat system function
window.toggleCombatSystem = function() {
  useDiceCombat = !useDiceCombat;
  console.log(`Combat system switched to: ${useDiceCombat ? 'New Dice-Based' : 'Classic D20'}`);
  return useDiceCombat;
};

// ============== LEVEL-UP SYSTEM ==============

/**
 * Show the level-up prompt for the current character
 */
function showLevelUpPrompt() {
  const characterKey = selectedCharacter || gameState.character || 'rodney';
  const characterData = CHARACTERS_DATA[characterKey];

  if (!characterData) {
    console.error('Character data not found for level-up');
    return;
  }

  const currentLevel = gameState.playerLevel || 1;
  const levelUpCondition = characterData.levelUpCondition || 'Complete a special achievement';

  createGameModal(`
    <div style="text-align: center; padding: 20px; max-width: 500px;">
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
function confirmLevelUp() {
  const characterKey = selectedCharacter || gameState.character || 'rodney';
  const characterData = CHARACTERS_DATA[characterKey];

  if (!characterData || !characterData.levelUpStats) {
    console.error('Character level-up data not found');
    return;
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
    appliedBonuses.push(`+${bonuses.luck} Luck`);
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

  // Update UI
  updateTopBar();
  saveCurrentGame();

  // Show stat bonuses first, then dice level-up choice
  createGameModal(`
    <div style="text-align: center; padding: 20px; max-width: 500px;">
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
            <div style="color: #fff; font-size: 14px;">
              ${b}
            </div>
          `).join('') : '<div style="color: #888; font-size: 14px;">No stat bonuses</div>'}
        </div>
      </div>
      <button id="proceed-to-dice-levelup-btn" style="
        padding: 12px 30px;
        background: linear-gradient(145deg, #FFD700, #FFA000);
        border: 2px solid #FFD700;
        border-radius: 8px;
        color: #000;
        font-weight: bold;
        cursor: pointer;
        font-size: 16px;
      ">🎲 Choose Dice Upgrade</button>
    </div>
  `);

  // Attach click handler for proceeding to dice level-up
  document.getElementById('proceed-to-dice-levelup-btn').onclick = () => {
    closeGameModal();
    // Show dice level-up choice modal
    showDiceLevelUpChoiceModal(characterKey, (diceResult) => {
      // Show final result
      if (diceResult) {
        createNotification(diceResult, '#FFD700', '🎲');
      }
      saveCurrentGame();
    });
  };
}

// Legacy function for backwards compatibility (random upgrade)
function confirmLevelUpLegacy() {
  const characterKey = selectedCharacter || gameState.character || 'rodney';
  const characterData = CHARACTERS_DATA[characterKey];

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
    <div style="text-align: center; padding: 20px; max-width: 500px;">
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
  const characterData = CHARACTERS_DATA[characterKey];
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
  const characterData = CHARACTERS_DATA[characterKey];
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
  const characterData = CHARACTERS_DATA[characterKey];
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
    console.log('Ally already recruited:', allyName);
    return false;
  }

  // Add ally with full HP
  gameState.activeAllies.push({
    name: allyData.name,
    currentHp: allyData.hp
  });

  saveCurrentGame();
  console.log(`Recruited ally: ${allyName}`);
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
  console.log(`Dismissed ally: ${allyName}`);
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
    console.log(`${allyName} has fallen!`);
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
  } else if (event.name === "A Sushi Bar By The Blue Hole") {
    closeGameModal();
    if (typeof showSushiBarEvent === 'function') {
      showSushiBarEvent();
    }
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


function showItemChoiceModal(onComplete, chestType = 'normal') {
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
    // Case-insensitive rarity color matching
    const rarityLower = (item.rarity || '').toLowerCase();
    const rarityColor = rarityLower === 'legendary' ? '#ff6b00' : rarityLower === 'rare' ? '#9b59b6' : rarityLower === 'uncommon' ? '#4CAF50' : '#aaa';

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

      // Check if we need to show Hades boon selection first
      if (gameState.pendingHadesBoonSelection) {
        gameState.pendingHadesBoonSelection = false;
        setTimeout(() => {
          if (typeof showHadesBoonSelection === 'function') {
            showHadesBoonSelection();
            // After boon selection, spawn choices or call callback
            // Note: The boon modal will handle spawning choices when it closes
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

      // Check if we need to show Hades boon selection first
      if (gameState.pendingHadesBoonSelection) {
        gameState.pendingHadesBoonSelection = false;
        setTimeout(() => {
          if (typeof showHadesBoonSelection === 'function') {
            showHadesBoonSelection();
            // After boon selection, spawn choices or call callback
            // Note: The boon modal will handle spawning choices when it closes
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

// ===== FISH STATS TRACKING SYSTEM =====

/**
 * Get fish stats from localStorage
 * @returns {Object} Fish stats object with fish names as keys
 */
function getFishStats() {
  return GameStorage.load(STORAGE_KEYS.FISH_STATS, {});
}

/**
 * Save fish stats to localStorage
 * @param {Object} stats - Fish stats object
 */
function saveFishStats(stats) {
  const result = GameStorage.save(STORAGE_KEYS.FISH_STATS, stats);
  if (!result.success) {
    console.error('Error saving fish stats:', result.error);
  }
}

/**
 * Increment caught count for a fish
 * @param {string} fishName - Name of the fish
 * @param {string} size - Size of the fish (Small, Medium, or Large)
 */
function incrementFishCaught(fishName, size = 'Medium') {
  const stats = getFishStats();

  if (!stats[fishName]) {
    stats[fishName] = {
      caught: 0,
      sizes: {
        Small: 0,
        Medium: 0,
        Large: 0
      }
    };
  }

  // Initialize sizes if missing (for backward compatibility)
  if (!stats[fishName].sizes) {
    stats[fishName].sizes = {
      Small: 0,
      Medium: 0,
      Large: 0
    };
  }

  stats[fishName].caught = (stats[fishName].caught || 0) + 1;
  stats[fishName].sizes[size] = (stats[fishName].sizes[size] || 0) + 1;

  saveFishStats(stats);

  console.log(`${fishName} (${size}) caught count: ${stats[fishName].caught} (Small: ${stats[fishName].sizes.Small}, Medium: ${stats[fishName].sizes.Medium}, Large: ${stats[fishName].sizes.Large})`);
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

function showEnemyDetails(enemyName) {
  const enemy = enemies.find(e => e.name === enemyName);
  if (!enemy) return;

  // Get enemy stats
  const enemyStats = getEnemyStats(enemyName);

  // Find variants of this enemy
  const variants = enemies.filter(e => e.variantOf === enemyName);

  // Get difficulty color
  const getDifficultyColor = (difficulty) => {
    switch((difficulty || '').toLowerCase()) {
      case 'low': return '#4CAF50';
      case 'medium': return '#ff9800';
      case 'high': return '#f44336';
      case 'boss': return '#9b59b6';
      default: return '#888';
    }
  };

  // Get type color
  const getTypeColor = (type) => {
    switch((type || '').toLowerCase()) {
      case 'strength': return '#f44336';
      case 'dexterity': return '#4CAF50';
      case 'intelligence': return '#2196F3';
      case 'charisma': return '#ff9800';
      default: return '#888';
    }
  };

  const diffColor = getDifficultyColor(enemy.difficulty);
  const typeColor = getTypeColor(enemy.type);

  const detailsPanel = document.getElementById('enemy-details');
  if (!detailsPanel) return;

  // Build variant images HTML
  let variantHTML = '';
  if (variants.length > 0) {
    const allForms = [enemy, ...variants];
    variantHTML = `
      <div style="margin-top: 15px;">
        <strong style="color: #9b59b6;">Forms:</strong>
        <div style="display: flex; gap: 10px; margin-top: 8px; flex-wrap: wrap;">
          ${allForms.map((form, idx) => `
            <div
              onclick="switchEnemyImage('${form.name.replace(/'/g, "\\'")}')"
              style="
                cursor: pointer;
                padding: 5px;
                border: 2px solid ${idx === 0 ? '#9b59b6' : '#444'};
                border-radius: 6px;
                background: rgba(0,0,0,0.3);
                transition: border-color 0.2s;
              "
              onmouseover="this.style.borderColor='#9b59b6'"
              onmouseout="this.style.borderColor='${idx === 0 ? '#9b59b6' : '#444'}'"
            >
              <img
                src="${form.imageUrl || getEnemyImagePath(form.name)}"
                alt="${form.name}"
                style="width: 60px; height: 60px; object-fit: contain;"
                onerror="this.style.opacity='0.3'"
              />
              <div style="font-size: 9px; text-align: center; color: #aaa; margin-top: 4px;">${form.name}</div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }

  // Build dice HTML
  const diceHTML = enemy.dice ? `
    <div id="enemy-dice-section" style="margin-top: 15px;">
      <strong style="color: #f44336;">Dice (${enemy.name}):</strong>
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 8px;">
        ${enemy.dice.map((face, idx) => {
          if (face.isBlank) {
            return `
              <div style="
                background: rgba(0,0,0,0.4);
                border: 1px solid #333;
                border-radius: 6px;
                padding: 8px;
                text-align: center;
                font-size: 11px;
                color: #666;
              ">
                <div style="font-weight: bold; color: #444;">Face ${idx + 1}</div>
                <div>Blank</div>
              </div>
            `;
          }
          return `
            <div style="
              background: rgba(244, 67, 54, 0.1);
              border: 1px solid rgba(244, 67, 54, 0.3);
              border-radius: 6px;
              padding: 8px;
              text-align: center;
              font-size: 11px;
              color: #ddd;
            ">
              <div style="font-weight: bold; color: #f44336; margin-bottom: 4px;">Face ${idx + 1}</div>
              <div>${face.raw || face.effects?.map(e => e.raw).join(', ') || '—'}</div>
            </div>
          `;
        }).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Enemy Header -->
      <div style="display: flex; gap: 15px; align-items: flex-start;">
        <img
          id="enemy-detail-image"
          src="${enemy.imageUrl || getEnemyImagePath(enemy.name)}"
          alt="${enemy.name}"
          style="width: 120px; height: 120px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); border: 2px solid ${diffColor}; image-rendering: pixelated; image-rendering: crisp-edges;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex: 1;">
          <h3 style="margin: 0 0 10px 0; color: #f44336;">${enemy.name}</h3>
          <div style="color: #aaa; font-size: 13px; line-height: 1.8;">
            <div><strong>Type:</strong> <span style="color: ${typeColor};">${enemy.type || '—'}</span></div>
            <div><strong>Difficulty:</strong> <span style="color: ${diffColor};">${enemy.difficulty || '—'}</span></div>
            <div><strong>HP:</strong> ${enemy.hp || '—'}</div>
            <div><strong>Game:</strong> ${enemy.game || '—'}</div>
            <div><strong>Location:</strong> ${enemy.location || '—'}</div>
          </div>
        </div>
      </div>

      <!-- Ability -->
      ${enemy.ability && enemy.ability !== 'N/A' ? `
        <div style="padding: 12px; background: rgba(155, 89, 182, 0.1); border: 1px solid rgba(155, 89, 182, 0.3); border-radius: 6px;">
          <h4 style="margin: 0 0 8px 0; color: #9b59b6; font-size: 14px;">⚡ Ability</h4>
          <div style="font-size: 13px; color: #ddd;">${enemy.ability}</div>
        </div>
      ` : ''}

      <!-- Combat Stats -->
      <div style="padding: 12px; background: rgba(244, 67, 54, 0.1); border: 1px solid rgba(244, 67, 54, 0.3); border-radius: 6px;">
        <h4 style="margin: 0 0 8px 0; color: #f44336; font-size: 14px;">📊 Combat Record</h4>
        <div style="font-size: 13px; color: #ddd; line-height: 1.8;">
          <div><strong>Times Defeated:</strong> ${enemyStats.timesBeaten || 0}</div>
          <div><strong>Times Killed Player:</strong> ${enemyStats.timesKilledPlayer || 0}</div>
        </div>
      </div>

      <!-- Variants -->
      ${variantHTML}

      <!-- Dice -->
      ${diceHTML}
    </div>
  `;
}

// Switch enemy form in details panel (for variants) - updates image and dice
function switchEnemyImage(enemyName) {
  const enemy = enemies.find(e => e.name === enemyName);
  if (!enemy) return;

  // Update image
  const img = document.getElementById('enemy-detail-image');
  if (img) {
    img.src = enemy.imageUrl || getEnemyImagePath(enemy.name);
  }

  // Update dice section
  const diceContainer = document.getElementById('enemy-dice-section');
  if (diceContainer && enemy.dice) {
    diceContainer.innerHTML = `
      <strong style="color: #f44336;">Dice (${enemy.name}):</strong>
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 8px;">
        ${enemy.dice.map((face, idx) => {
          if (face.isBlank) {
            return `
              <div style="
                background: rgba(0,0,0,0.4);
                border: 1px solid #333;
                border-radius: 6px;
                padding: 8px;
                text-align: center;
                font-size: 11px;
                color: #666;
              ">
                <div style="font-weight: bold; color: #444;">Face ${idx + 1}</div>
                <div>Blank</div>
              </div>
            `;
          }
          return `
            <div style="
              background: rgba(244, 67, 54, 0.1);
              border: 1px solid rgba(244, 67, 54, 0.3);
              border-radius: 6px;
              padding: 8px;
              text-align: center;
              font-size: 11px;
              color: #ddd;
            ">
              <div style="font-weight: bold; color: #f44336; margin-bottom: 4px;">Face ${idx + 1}</div>
              <div>${face.raw || face.effects?.map(e => e.raw).join(', ') || '—'}</div>
            </div>
          `;
        }).join('')}
      </div>
    `;
  }
}

/**
 * Show item details in the collection panel
 * @param {string} itemName - Name of the item to show details for
 */
function showItemDetails(itemName) {
  const item = items.find(i => i.name === itemName);
  if (!item) return;

  const detailsPanel = document.getElementById('item-details');
  if (!detailsPanel) return;

  // Get rarity color
  const getRarityColor = (rarity) => {
    const rarityLower = (rarity || '').toLowerCase();
    switch(rarityLower) {
      case 'legendary': return '#ff6b00';
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      case 'common': return '#aaa';
      default: return '#888';
    }
  };

  // Get type color
  const getTypeColor = (type) => {
    const typeLower = (type || '').toLowerCase();
    switch(typeLower) {
      case 'weapon': return '#f44336';
      case 'passive': return '#4CAF50';
      case 'consumable': return '#2196F3';
      case 'active': return '#ff9800';
      case 'boon': return '#9b59b6';
      default: return '#888';
    }
  };

  const rarityColor = getRarityColor(item.rarity);
  const typeColor = getTypeColor(item.type);

  // Build tags HTML
  const tagsHTML = item.tags && item.tags.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #9b59b6;">Tags:</strong>
      <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px;">
        ${item.tags.map(tag => `
          <span style="
            font-size: 11px;
            padding: 4px 10px;
            background: rgba(155, 89, 182, 0.15);
            border: 1px solid rgba(155, 89, 182, 0.4);
            border-radius: 12px;
            color: #ba68c8;
          ">${tag}</span>
        `).join('')}
      </div>
    </div>
  ` : '';

  // Look up weapon dice from WEAPONS_DATA if this is a weapon
  let weaponDice = null;
  if (item.type === 'Weapon' && typeof WEAPONS_DATA !== 'undefined') {
    const weaponData = WEAPONS_DATA.find(w => w.name === item.name);
    if (weaponData && weaponData.dice) {
      weaponDice = weaponData.dice;
    }
  }

  // Build dice HTML for weapons
  const diceHTML = weaponDice && weaponDice.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #f44336;">Weapon Dice:</strong>
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 8px;">
        ${weaponDice.map((face, idx) => {
          if (face.isBlank) {
            return `
              <div style="
                background: rgba(0,0,0,0.4);
                border: 1px solid #333;
                border-radius: 6px;
                padding: 8px;
                text-align: center;
                font-size: 11px;
                color: #666;
              ">
                <div style="font-weight: bold; color: #444;">Face ${idx + 1}</div>
                <div>Blank</div>
              </div>
            `;
          }
          return `
            <div style="
              background: rgba(244, 67, 54, 0.1);
              border: 1px solid rgba(244, 67, 54, 0.3);
              border-radius: 6px;
              padding: 8px;
              text-align: center;
              font-size: 11px;
              color: #ddd;
            ">
              <div style="font-weight: bold; color: #f44336; margin-bottom: 4px;">Face ${idx + 1}</div>
              <div>${face.raw || face.effects?.map(e => e.raw).join(', ') || '—'}</div>
            </div>
          `;
        }).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Item Header -->
      <div style="display: flex; gap: 15px; align-items: flex-start;">
        <img
          src="${item.image || 'images/items/no-item.svg'}"
          alt="${item.name}"
          style="width: 120px; height: 120px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); border: 2px solid ${rarityColor}; image-rendering: pixelated;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex: 1;">
          <h3 style="margin: 0 0 10px 0; color: ${rarityColor};">${item.name}</h3>
          <div style="color: #aaa; font-size: 13px; line-height: 1.8;">
            <div><strong>Rarity:</strong> <span style="color: ${rarityColor}; text-transform: uppercase; font-weight: bold;">${item.rarity || '—'}</span></div>
            <div><strong>Type:</strong> <span style="color: ${typeColor};">${item.type || '—'}</span></div>
            <div><strong>Game:</strong> ${item.game || '—'}</div>
          </div>
        </div>
      </div>

      <!-- Description -->
      <div style="padding: 12px; background: rgba(${rarityColor === '#ff6b00' ? '255,107,0' : rarityColor === '#9b59b6' ? '155,89,182' : rarityColor === '#4CAF50' ? '76,175,80' : '170,170,170'}, 0.1); border: 1px solid ${rarityColor}40; border-radius: 6px;">
        <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 14px;">📜 Description</h4>
        <div style="font-size: 13px; color: #ddd; line-height: 1.6;">${item.description || 'No description available.'}</div>
      </div>

      <!-- Unlock Condition -->
      ${item.unlockCondition && item.unlockCondition !== 'N/A' ? `
        <div style="padding: 12px; background: rgba(255, 152, 0, 0.1); border: 1px solid rgba(255, 152, 0, 0.3); border-radius: 6px;">
          <h4 style="margin: 0 0 8px 0; color: #ff9800; font-size: 14px;">🔓 Unlock Condition</h4>
          <div style="font-size: 13px; color: #ddd;">${item.unlockCondition}</div>
        </div>
      ` : ''}

      <!-- Tags -->
      ${tagsHTML}

      <!-- Dice (for weapons) -->
      ${diceHTML}
    </div>
  `;
}

function showSpellDetails(spellName) {
  const spellsData = typeof SPELLS_DATA !== 'undefined' ? SPELLS_DATA : [];
  const spell = spellsData.find(s => s.name === spellName);
  if (!spell) return;

  const detailsPanel = document.getElementById('spell-details');
  if (!detailsPanel) return;

  // Get rarity color
  const getRarityColor = (rarity) => {
    const rarityLower = (rarity || '').toLowerCase();
    switch(rarityLower) {
      case 'rare': return '#9b59b6';
      case 'uncommon': return '#4CAF50';
      case 'common': return '#aaa';
      default: return '#888';
    }
  };

  // Get element color
  const getElementColor = (element) => {
    switch((element || '').toLowerCase()) {
      case 'fire': return '#ff4444';
      case 'water': return '#4488ff';
      case 'earth': return '#88aa44';
      case 'dark': return '#8844aa';
      case 'blood': return '#cc2222';
      case 'poison': return '#44aa44';
      case 'electric': return '#ffcc00';
      default: return '#888';
    }
  };

  const rarityColor = getRarityColor(spell.rarity);
  const elementColor = getElementColor(spell.element);

  // Build keywords HTML
  const keywordsHTML = spell.keywords && spell.keywords.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #9b59b6;">Keywords:</strong>
      <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px;">
        ${spell.keywords.map(keyword => `
          <span style="
            font-size: 11px;
            padding: 4px 10px;
            background: rgba(155, 89, 182, 0.15);
            border: 1px solid rgba(155, 89, 182, 0.4);
            border-radius: 12px;
            color: #ba68c8;
          ">${keyword}</span>
        `).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Spell Header -->
      <div style="display: flex; gap: 15px; align-items: flex-start;">
        <img
          src="${spell.image || 'images/spells/no-spell.svg'}"
          alt="${spell.name}"
          style="width: 120px; height: 120px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); border: 2px solid ${rarityColor}; image-rendering: pixelated;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex: 1;">
          <h3 style="margin: 0 0 10px 0; color: ${rarityColor};">${spell.name}</h3>
          <div style="color: #aaa; font-size: 13px; line-height: 1.8;">
            <div><strong>Rarity:</strong> <span style="color: ${rarityColor}; text-transform: uppercase; font-weight: bold;">${spell.rarity || '—'}</span></div>
            <div><strong>Cost:</strong> <span style="color: #66b3ff; font-weight: bold;">${spell.cost} Mana</span></div>
            <div><strong>Game:</strong> ${spell.game || '—'}</div>
            <div><strong>Element:</strong> <span style="color: ${elementColor}; font-weight: bold;">${spell.element && spell.element !== 'N/A' ? spell.element : 'None'}</span></div>
          </div>
        </div>
      </div>

      <!-- Description -->
      <div style="padding: 12px; background: rgba(${rarityColor === '#9b59b6' ? '155,89,182' : rarityColor === '#4CAF50' ? '76,175,80' : '170,170,170'}, 0.1); border: 1px solid ${rarityColor}40; border-radius: 6px;">
        <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 14px;">Effect</h4>
        <div style="font-size: 13px; color: #ddd; line-height: 1.6;">${spell.description || 'No description available.'}</div>
      </div>

      <!-- Bonus Indicator -->
      <div style="padding: 12px; background: rgba(${spell.hasBonus ? '76, 175, 80' : '136, 136, 136'}, 0.1); border: 1px solid ${spell.hasBonus ? '#4CAF5040' : '#88888840'}; border-radius: 6px;">
        <div style="display: flex; align-items: center; gap: 8px;">
          <span style="font-size: 18px;">${spell.hasBonus ? '✓' : '✗'}</span>
          <div>
            <div style="font-weight: bold; color: ${spell.hasBonus ? '#4CAF50' : '#888'};">
              ${spell.hasBonus ? 'Has Bonus Effect' : 'No Bonus Effect'}
            </div>
            <div style="font-size: 11px; color: #888;">
              ${spell.hasBonus ? 'This spell can be enhanced with bonuses' : 'This spell cannot be enhanced'}
            </div>
          </div>
        </div>
      </div>

      <!-- Keywords -->
      ${keywordsHTML}
    </div>
  `;
}

function showCharacterDetails(charName) {
  const charactersData = typeof CHARACTERS_DATA !== 'undefined' ? CHARACTERS_DATA : [];
  const char = charactersData.find(c => c.name === charName);
  if (!char) return;

  const detailsPanel = document.getElementById('character-details');
  if (!detailsPanel) return;

  const charIcon = `images/characters/Full/${char.name}.png`;

  // Build stats HTML
  const stats = [
    { label: 'Strength', value: char.strength || 0, color: '#f44336' },
    { label: 'Dexterity', value: char.dexterity || 0, color: '#4CAF50' },
    { label: 'Intelligence', value: char.intelligence || 0, color: '#2196F3' },
    { label: 'Charisma', value: char.charisma || 0, color: '#9b59b6' },
    { label: 'Luck', value: char.luck || 0, color: '#ff9800' },
  ];

  const resources = [
    { label: 'Energy', value: char.energy || 0, color: '#ffcc00' },
    { label: 'Mana', value: char.mana || 0, color: '#66b3ff' },
    { label: 'Reroll', value: char.reroll || 0, color: '#888' },
    { label: 'Dash', value: char.dash || 0, color: '#888' },
    { label: 'Skip', value: char.skip || 0, color: '#888' },
    { label: 'Discovery', value: char.discovery || 0, color: '#888' },
  ];

  // Build dice HTML
  const diceHTML = char.dice && char.dice.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #4CAF50;">Starting Dice:</strong>
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 8px;">
        ${char.dice.map((face, idx) => {
          if (face.isBlank) {
            return `<div style="background: rgba(0,0,0,0.4); border: 1px solid #333; border-radius: 6px; padding: 8px; text-align: center; font-size: 11px; color: #666;">
              <div style="font-weight: bold; color: #444;">Face ${idx + 1}</div>
              <div>Blank</div>
            </div>`;
          }
          return `<div style="background: rgba(76, 175, 80, 0.1); border: 1px solid rgba(76, 175, 80, 0.3); border-radius: 6px; padding: 8px; text-align: center; font-size: 11px; color: #ddd;">
            <div style="font-weight: bold; color: #4CAF50; margin-bottom: 4px;">Face ${idx + 1}</div>
            <div>${face.raw || '—'}</div>
          </div>`;
        }).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Character Header -->
      <div style="display: flex; gap: 15px; align-items: flex-start;">
        <img
          src="${charIcon}"
          alt="${char.name}"
          style="width: 150px; height: 150px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); border: 2px solid #4CAF50; image-rendering: pixelated;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex: 1;">
          <h3 style="margin: 0 0 10px 0; color: #4CAF50;">${char.name}</h3>
          <div style="color: #aaa; font-size: 13px; line-height: 1.8;">
            <div><strong>Game:</strong> ${char.game || '—'}</div>
            <div><strong>Combat Start:</strong> ${char.combatStart || 'Dice'}</div>
          </div>
        </div>
      </div>

      <!-- Description -->
      <div style="padding: 12px; background: rgba(76, 175, 80, 0.1); border: 1px solid rgba(76, 175, 80, 0.3); border-radius: 6px;">
        <div style="font-size: 13px; color: #ddd; line-height: 1.6; font-style: italic;">"${char.description || 'No description available.'}"</div>
      </div>

      <!-- Resources -->
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px;">
        ${resources.map(r => `
          <div style="background: rgba(0,0,0,0.3); border-radius: 6px; padding: 8px; text-align: center;">
            <div style="font-size: 10px; color: #888; text-transform: uppercase;">${r.label}</div>
            <div style="font-size: 18px; font-weight: bold; color: ${r.color};">${r.value}</div>
          </div>
        `).join('')}
      </div>

      <!-- Stats -->
      <div style="display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px;">
        ${stats.map(s => `
          <div style="background: rgba(0,0,0,0.3); border-radius: 6px; padding: 8px; text-align: center;">
            <div style="font-size: 9px; color: #888; text-transform: uppercase;">${s.label.substring(0, 3)}</div>
            <div style="font-size: 16px; font-weight: bold; color: ${s.color};">${s.value}</div>
          </div>
        `).join('')}
      </div>

      <!-- Level Up Condition -->
      ${char.levelUp ? `
        <div style="padding: 12px; background: rgba(255, 152, 0, 0.1); border: 1px solid rgba(255, 152, 0, 0.3); border-radius: 6px;">
          <h4 style="margin: 0 0 8px 0; color: #ff9800; font-size: 14px;">⬆️ Level Up Condition</h4>
          <div style="font-size: 13px; color: #ddd;">${char.levelUp}</div>
        </div>
      ` : ''}

      <!-- Dice -->
      ${diceHTML}
    </div>
  `;
}

function showAllyDetails(allyName) {
  const alliesData = typeof ALLIES_DATA !== 'undefined' ? ALLIES_DATA : [];
  const ally = alliesData.find(a => a.name === allyName);
  if (!ally) return;

  const detailsPanel = document.getElementById('ally-details');
  if (!detailsPanel) return;

  const allyIcon = ally.image || `images/allies/${ally.name}.png`;

  // Get rarity color
  const getRarityColor = (rarity) => {
    switch((rarity || '').toLowerCase()) {
      case 'high': return '#9b59b6';
      case 'medium': return '#ff9800';
      case 'low': return '#4CAF50';
      default: return '#888';
    }
  };

  const rarityColor = getRarityColor(ally.rarity);

  // Build dice HTML
  const diceHTML = ally.dice && ally.dice.length > 0 ? `
    <div style="margin-top: 15px;">
      <strong style="color: #2196F3;">Ally Dice:</strong>
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 8px;">
        ${ally.dice.map((face, idx) => {
          if (face.isBlank || face.raw === 'X') {
            return `<div style="background: rgba(0,0,0,0.4); border: 1px solid #333; border-radius: 6px; padding: 8px; text-align: center; font-size: 11px; color: #666;">
              <div style="font-weight: bold; color: #444;">Face ${idx + 1}</div>
              <div>${face.raw === 'X' ? 'X' : 'Blank'}</div>
            </div>`;
          }
          return `<div style="background: rgba(33, 150, 243, 0.1); border: 1px solid rgba(33, 150, 243, 0.3); border-radius: 6px; padding: 8px; text-align: center; font-size: 11px; color: #ddd;">
            <div style="font-weight: bold; color: #2196F3; margin-bottom: 4px;">Face ${idx + 1}</div>
            <div>${face.raw || '—'}</div>
          </div>`;
        }).join('')}
      </div>
    </div>
  ` : '';

  detailsPanel.innerHTML = `
    <div style="display: flex; flex-direction: column; gap: 15px;">
      <!-- Ally Header -->
      <div style="display: flex; gap: 15px; align-items: flex-start;">
        <img
          src="${allyIcon}"
          alt="${ally.name}"
          style="width: 100px; height: 100px; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3); border: 2px solid ${rarityColor}; image-rendering: pixelated;"
          onerror="this.style.opacity='0.3'"
        />
        <div style="flex: 1;">
          <h3 style="margin: 0 0 10px 0; color: ${rarityColor};">${ally.name}</h3>
          <div style="color: #aaa; font-size: 13px; line-height: 1.8;">
            <div><strong>Type:</strong> ${ally.type || 'Ally'}</div>
            <div><strong>Rarity:</strong> <span style="color: ${rarityColor}; text-transform: uppercase; font-weight: bold;">${ally.rarity || '—'}</span></div>
            <div><strong>HP:</strong> <span style="color: #ff4444; font-weight: bold;">${ally.hp || '?'}</span></div>
            <div><strong>Game:</strong> ${ally.game || '—'}</div>
          </div>
        </div>
      </div>

      <!-- Ability -->
      ${ally.ability ? `
        <div style="padding: 12px; background: rgba(33, 150, 243, 0.1); border: 1px solid rgba(33, 150, 243, 0.3); border-radius: 6px;">
          <h4 style="margin: 0 0 8px 0; color: #2196F3; font-size: 14px;">✨ Special Ability</h4>
          <div style="font-size: 13px; color: #ddd; line-height: 1.6;">${ally.ability}</div>
        </div>
      ` : `
        <div style="padding: 12px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 6px;">
          <div style="font-size: 13px; color: #888; text-align: center;">No special ability</div>
        </div>
      `}

      <!-- Dice -->
      ${diceHTML}
    </div>
  `;
}

// Get enemy stats from gameState
function getEnemyStats(enemyName) {
  if (!gameState.enemyStats) {
    gameState.enemyStats = {};
  }

  // Find base enemy name (for variants)
  const enemy = enemies.find(e => e.name === enemyName);
  const baseName = enemy?.variantOf || enemyName;

  return gameState.enemyStats[baseName] || { timesBeaten: 0, timesKilledPlayer: 0 };
}

// Record enemy defeat
function recordEnemyDefeated(enemyName) {
  if (!gameState.enemyStats) {
    gameState.enemyStats = {};
  }

  // Find base enemy name (for variants)
  const enemy = enemies.find(e => e.name === enemyName);
  const baseName = enemy?.variantOf || enemyName;

  if (!gameState.enemyStats[baseName]) {
    gameState.enemyStats[baseName] = { timesBeaten: 0, timesKilledPlayer: 0 };
  }

  gameState.enemyStats[baseName].timesBeaten++;
  saveCurrentGame();
}

// Record player death to enemy
function recordPlayerKilledBy(enemyName) {
  if (!gameState.enemyStats) {
    gameState.enemyStats = {};
  }

  // Find base enemy name (for variants)
  const enemy = enemies.find(e => e.name === enemyName);
  const baseName = enemy?.variantOf || enemyName;

  if (!gameState.enemyStats[baseName]) {
    gameState.enemyStats[baseName] = { timesBeaten: 0, timesKilledPlayer: 0 };
  }

  gameState.enemyStats[baseName].timesKilledPlayer++;
  saveCurrentGame();
}

function markGameFinished(gameName) {
  if (!gameState.finishedGames) {
    gameState.finishedGames = [];
  }

  // Initialize totalGamesBeaten if it doesn't exist (backwards compatibility)
  if (typeof gameState.totalGamesBeaten !== 'number') {
    console.log('⚠️ totalGamesBeaten was not a number, initializing to 0');
    gameState.totalGamesBeaten = 0;
  }

  // Log the state before increment for debugging
  console.log(`📊 Before increment - totalGamesBeaten: ${gameState.totalGamesBeaten}`);

  // Increment beaten count (tracks all completions, even if player dies later)
  // NOTE: Amulet stat is only incremented on successful escape (in showVictoryScreen)
  incrementGameBeaten(gameName, false);

  // Increment total games beaten counter (counts ALL completions including duplicates)
  const previousDifficulty = getDifficultyTier(gameState.totalGamesBeaten);
  gameState.totalGamesBeaten++;
  console.log(`✅ Game finished: ${gameName}. Total games beaten: ${gameState.totalGamesBeaten} (was ${gameState.totalGamesBeaten - 1})`);

  // Reroller trait: Every time you beat a game, gain +1 Reroll
  if (hasTrait('reroller')) {
    reroll++;
    console.log('Reroller trait triggered: +1 Reroll');
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
    console.log(`Unique game finished: ${gameName}. Total unique: ${gameState.finishedGames.length}`);
  }

  // Check if difficulty tier changed and update location (unless manually overridden via dev tools)
  if (!gameState.manualLocationOverride) {
    const newDifficulty = getDifficultyTier(gameState.totalGamesBeaten);
    if (previousDifficulty !== newDifficulty) {
      const newLocation = getRandomLocation(newDifficulty);
      if (newLocation) {
        gameState.location = newLocation;
        console.log(`Difficulty tier changed to ${newDifficulty}! New location: ${newLocation.name}`);

      // Update the location display
      if (typeof updateLocationDisplay === 'function') {
        updateLocationDisplay(gameState.currentGame);
      }

      // Flag if this is a Hades location - will be shown after item choice
      if (newLocation.game === 'Hades') {
        gameState.pendingHadesBoonSelection = true;
        console.log('Hades location entered - boon selection will be shown after item choice');
      }
    }
    }
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
    console.log(`Status ${statusName} already exists on ${gameName}`);
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

  console.log(`Added status ${statusName} to ${gameName} with icon ${icon}`);

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
  let difficultyTier = 'Low';
  let curseSuffix = 'I';

  if (gamesBeaten >= 10) {
    difficultyTier = 'High';
    curseSuffix = 'III';
  } else if (gamesBeaten >= 5) {
    difficultyTier = 'Medium';
    curseSuffix = 'II';
  }

  console.log(`Triggering status effects on ${gameName} (Difficulty: ${difficultyTier})`);

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
      console.log(message);
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

  console.log(`Dev Tools: Set location to ${selectedLocation.name} (${selectedLocation.difficulty} - ${selectedLocation.game}) - Manual override enabled`);
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

  console.log(`Dev Tools: Set random location to ${randomLocation.name} (${randomLocation.difficulty} - ${randomLocation.game}) - Manual override enabled`);
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

  console.log('Dev Tools: Manual location override disabled - location will now change automatically with difficulty');
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
window.switchCollectionTab = switchCollectionTab;
window.showGameDetails = showGameDetails;
window.showEnemyDetails = showEnemyDetails;
window.showItemDetails = showItemDetails;
window.switchEnemyImage = switchEnemyImage;
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
